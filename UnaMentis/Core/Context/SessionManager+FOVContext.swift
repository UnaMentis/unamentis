// UnaMentis - SessionManager FOV Context Extension
// Integrates foveated context management into voice sessions
//
// Part of FOV Context Management System
//
// This extension adds:
// - Foveated context building for LLM calls
// - Confidence monitoring for automatic expansion
// - Integration with CurriculumEngine for topic-aware context

import Foundation
import Logging

// MARK: - FOV Context Integration

/// Extension to integrate FOV context management into SessionManager
/// Use via dependency injection rather than modifying core SessionManager
/// Note: @MainActor class because it works with Core Data objects (Topic)
@MainActor
public final class FOVSessionContextCoordinator {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.fovsession")

    /// FOV context manager
    public let contextManager: FOVContextManager

    /// Confidence monitor for automatic expansion
    public let confidenceMonitor: ConfidenceMonitor

    /// Context expansion handler
    private let expansionHandler: ContextExpansionHandler?

    /// Context summarizer for buffer compression
    private let summarizer: ContextSummarizer?

    /// Curriculum engine reference
    private weak var curriculumEngine: CurriculumEngine?

    /// Whether FOV context is enabled
    private var isEnabled: Bool = true

    /// Current topic being taught (for context building)
    private var currentTopic: Topic?

    /// Current transcript segment being played
    private var currentSegment: TranscriptSegmentContext?

    // MARK: - Initialization

    /// Initialize the FOV session coordinator
    /// - Parameters:
    ///   - curriculumEngine: Curriculum engine for content access
    ///   - llmService: LLM service for summarization (optional)
    ///   - modelContextWindow: Context window of the primary model
    public init(
        curriculumEngine: CurriculumEngine?,
        llmService: (any LLMService)? = nil,
        modelContextWindow: Int = 128_000
    ) {
        self.curriculumEngine = curriculumEngine

        // Initialize context manager
        self.contextManager = FOVContextManager(
            modelContextWindow: modelContextWindow
        )

        // Initialize confidence monitor
        self.confidenceMonitor = ConfidenceMonitor(config: .tutoring)

        // Initialize summarizer if LLM available
        if let llmService = llmService {
            let newSummarizer = ContextSummarizer(llmService: llmService)
            self.summarizer = newSummarizer
            // Set up summarizer after initialization completes
            let manager = contextManager
            Task {
                await manager.setSummarizer(newSummarizer)
            }
        } else {
            self.summarizer = nil
        }

        // Initialize expansion handler if curriculum available
        if let curriculum = curriculumEngine {
            self.expansionHandler = ContextExpansionHandler(
                curriculumEngine: curriculum,
                contextManager: contextManager
            )
        } else {
            self.expansionHandler = nil
        }

        logger.info("FOVSessionContextCoordinator initialized")
    }

    // MARK: - Context Building

    /// Build foveated context for an LLM call
    /// - Parameters:
    ///   - conversationHistory: Full conversation history
    ///   - bargeInUtterance: User's barge-in utterance (if any)
    /// - Returns: Array of LLM messages with foveated context as system message
    public func buildFoveatedMessages(
        conversationHistory: [LLMMessage],
        bargeInUtterance: String? = nil
    ) async -> [LLMMessage] {
        guard isEnabled else {
            // Return original messages if disabled
            return conversationHistory
        }

        // Build FOV context
        let fovContext = await contextManager.buildContext(
            conversationHistory: conversationHistory,
            bargeInUtterance: bargeInUtterance
        )

        // Create messages with foveated system prompt
        var messages: [LLMMessage] = []

        // System message with full foveated context
        messages.append(LLMMessage(
            role: .system,
            content: fovContext.toSystemMessage()
        ))

        // Add recent conversation turns (limited by immediate buffer config)
        let turnCount = fovContext.immediateBufferTurnCount
        let recentHistory = conversationHistory.suffix(turnCount * 2) // user + assistant pairs

        for message in recentHistory where message.role != .system {
            messages.append(message)
        }

        logger.debug(
            "Built foveated messages",
            metadata: [
                "totalMessages": .stringConvertible(messages.count),
                "turnCount": .stringConvertible(turnCount),
                "tokens": .stringConvertible(fovContext.totalTokenEstimate)
            ]
        )

        return messages
    }

    /// Analyze response and determine if expansion is needed
    /// - Parameter response: LLM response to analyze
    /// - Returns: Expansion recommendation
    public func analyzeResponseConfidence(_ response: String) async -> ExpansionRecommendation {
        let analysis = await confidenceMonitor.analyzeResponse(response)
        return await confidenceMonitor.getExpansionRecommendation(analysis)
    }

    /// Expand context based on recommendation
    /// - Parameter request: Expansion request
    /// - Returns: Expanded content (if any)
    public func expandContext(_ request: ExpansionRequest) async -> String? {
        guard let handler = expansionHandler else {
            logger.warning("No expansion handler configured")
            return nil
        }

        let result = await handler.execute(request)
        return result.hasContent ? result.content : nil
    }

    // MARK: - Topic Management

    /// Set the current topic for context building
    /// - Parameter topic: Current topic
    public func setCurrentTopic(_ topic: Topic?) async {
        currentTopic = topic

        guard let topic = topic, let curriculum = curriculumEngine else { return }

        // Update working buffer from curriculum engine
        let position = await curriculum.getTopicPosition(for: topic)
        let outline = await curriculum.generateCurriculumOutline()
        let glossaryTerms = await curriculum.getRelevantGlossaryTerms(for: "", in: topic)
        let misconceptions = await curriculum.getMisconceptionTriggers(for: topic)

        await contextManager.updateWorkingBuffer(
            topicTitle: topic.title ?? "Unknown Topic",
            topicContent: topic.outline ?? "",
            learningObjectives: topic.learningObjectives,
            glossaryTerms: glossaryTerms,
            misconceptionTriggers: misconceptions
        )

        await contextManager.updateSemanticBuffer(
            curriculumOutline: outline,
            position: position
        )

        logger.info("Set current topic: \(topic.title ?? "Unknown")")
    }

    /// Set the current TTS segment being played
    /// - Parameter segment: Current segment
    public func setCurrentSegment(_ segment: TranscriptSegmentContext?) async {
        currentSegment = segment
        await contextManager.setCurrentSegment(segment)
    }

    // MARK: - Session Events

    /// Record a user question for the episodic buffer
    /// - Parameter question: User's question
    public func recordUserQuestion(_ question: String) async {
        await contextManager.recordUserQuestion(question)
    }

    /// Record topic completion
    /// - Parameters:
    ///   - topic: Completed topic
    ///   - summary: Summary of the topic content
    ///   - masteryLevel: Achieved mastery level
    public func recordTopicCompletion(
        topic: Topic,
        summary: String,
        masteryLevel: Double
    ) async {
        let topicSummary = FOVTopicSummary(
            topicId: topic.id ?? UUID(),
            title: topic.title ?? "Unknown",
            summary: summary,
            masteryLevel: masteryLevel
        )
        await contextManager.recordTopicCompletion(topicSummary)
    }

    /// Record a clarification request (updates learner signals)
    public func recordClarificationRequest() async {
        await contextManager.recordClarificationRequest()
    }

    /// Record a repetition request (updates learner signals)
    public func recordRepetitionRequest() async {
        await contextManager.recordRepetitionRequest()
    }

    // MARK: - Configuration

    /// Enable or disable FOV context
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        logger.info("FOV context \(enabled ? "enabled" : "disabled")")
    }

    /// Update model configuration
    public func updateModelConfig(model: String) async {
        await contextManager.updateModelConfig(model: model)
    }

    /// Reset the coordinator for a new session
    public func reset() async {
        await contextManager.reset()
        await confidenceMonitor.reset()
        currentTopic = nil
        currentSegment = nil
        logger.info("FOVSessionContextCoordinator reset")
    }
}

// MARK: - Session Manager Integration Helpers

/// Helper to integrate FOV context into existing SessionManager workflow
public struct FOVContextIntegration {

    /// Create a coordinator from session dependencies
    @MainActor
    public static func createCoordinator(
        curriculumEngine: CurriculumEngine?,
        llmService: (any LLMService)?,
        model: String
    ) -> FOVSessionContextCoordinator {
        let contextWindow = ModelContextWindows.contextWindow(for: model)
        return FOVSessionContextCoordinator(
            curriculumEngine: curriculumEngine,
            llmService: llmService,
            modelContextWindow: contextWindow
        )
    }

    /// Process a response with confidence monitoring
    /// Returns additional context if expansion was triggered
    public static func processResponseWithConfidence(
        response: String,
        coordinator: FOVSessionContextCoordinator,
        conversationHistory: [LLMMessage]
    ) async -> (shouldExpand: Bool, additionalContext: String?) {
        let recommendation = await coordinator.analyzeResponseConfidence(response)

        if recommendation.shouldExpand {
            // Extract query from recent conversation
            let query = extractQueryFromHistory(conversationHistory)

            let request = ExpansionRequest(
                query: query,
                scope: recommendation.suggestedScope,
                reason: recommendation.reason
            )

            let additionalContext = await coordinator.expandContext(request)
            return (true, additionalContext)
        }

        return (false, nil)
    }

    /// Extract the most likely query from conversation history
    private static func extractQueryFromHistory(_ history: [LLMMessage]) -> String {
        // Get the last user message
        if let lastUserMessage = history.last(where: { $0.role == .user }) {
            return lastUserMessage.content
        }
        return "more information about the current topic"
    }
}

// MARK: - Barge-In Context Builder

/// Specialized builder for barge-in scenarios
public struct BargeInContextBuilder {

    /// Build context specifically for a barge-in interruption
    /// - Parameters:
    ///   - utterance: User's barge-in utterance
    ///   - interruptedSegment: The TTS segment that was interrupted
    ///   - playbackPosition: How far into the segment playback was
    ///   - coordinator: FOV coordinator
    ///   - conversationHistory: Current conversation history
    /// - Returns: Messages ready for LLM call
    public static func buildBargeInContext(
        utterance: String,
        interruptedSegment: TranscriptSegmentContext?,
        playbackPosition: TimeInterval?,
        coordinator: FOVSessionContextCoordinator,
        conversationHistory: [LLMMessage]
    ) async -> [LLMMessage] {
        // Update the immediate buffer with barge-in specific context
        if let segment = interruptedSegment {
            await coordinator.setCurrentSegment(segment)
        }

        // Build foveated messages with the barge-in utterance
        let messages = await coordinator.buildFoveatedMessages(
            conversationHistory: conversationHistory,
            bargeInUtterance: utterance
        )

        return messages
    }
}
