// UnaMentis - FOV Context Manager
// Hierarchical buffer management for voice tutoring context
//
// Part of FOV Context Management System
//
// Implements a "Field of View" approach to context management:
// - Immediate Buffer: Verbatim recent conversation + current segment
// - Working Buffer: Current topic content + objectives
// - Episodic Buffer: Compressed session history
// - Semantic Buffer: Curriculum outline + position

import Foundation
import Logging

/// Actor responsible for managing hierarchical context buffers
/// and building optimized context for LLM calls
public actor FOVContextManager {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.fovcontext")

    /// Current budget configuration (adapts to model)
    private var budgetConfig: AdaptiveBudgetConfig

    /// Immediate buffer (recent conversation + current segment)
    private var immediateBuffer: ImmediateBuffer

    /// Working buffer (current topic context)
    private var workingBuffer: WorkingBuffer

    /// Episodic buffer (session history summaries)
    private var episodicBuffer: EpisodicBuffer

    /// Semantic buffer (curriculum outline)
    private var semanticBuffer: SemanticBuffer

    /// Base system prompt for tutoring
    private let baseSystemPrompt: String

    /// Optional summarizer for compressing content
    private var summarizer: ContextSummarizer?

    // MARK: - Initialization

    /// Initialize with default configuration
    /// - Parameters:
    ///   - modelContextWindow: Context window size for the primary model
    ///   - baseSystemPrompt: Base tutor system prompt
    ///   - summarizer: Optional summarizer for compressing older content
    public init(
        modelContextWindow: Int = 128_000,
        baseSystemPrompt: String? = nil,
        summarizer: ContextSummarizer? = nil
    ) {
        self.budgetConfig = AdaptiveBudgetConfig(modelContextWindow: modelContextWindow)
        self.baseSystemPrompt = baseSystemPrompt ?? FOVContextManager.defaultSystemPrompt
        self.summarizer = summarizer

        self.immediateBuffer = ImmediateBuffer()
        self.workingBuffer = WorkingBuffer()
        self.episodicBuffer = EpisodicBuffer()
        self.semanticBuffer = SemanticBuffer()

        let tier = self.budgetConfig.tier.rawValue
        let budget = self.budgetConfig.totalBudget
        logger.info(
            "FOVContextManager initialized",
            metadata: [
                "tier": .string(tier),
                "totalBudget": .stringConvertible(budget)
            ]
        )
    }

    /// Create a manager for a specific model
    /// - Parameters:
    ///   - model: Model identifier (e.g., "gpt-4o", "claude-3-5-sonnet")
    ///   - baseSystemPrompt: Base tutor system prompt
    /// - Returns: Configured FOVContextManager
    public static func forModel(
        _ model: String,
        baseSystemPrompt: String? = nil
    ) -> FOVContextManager {
        let contextWindow = ModelContextWindows.contextWindow(for: model)
        return FOVContextManager(
            modelContextWindow: contextWindow,
            baseSystemPrompt: baseSystemPrompt
        )
    }

    // MARK: - Context Building

    /// Build complete FOV context for an LLM call
    /// - Parameters:
    ///   - conversationHistory: Recent conversation messages
    ///   - bargeInUtterance: User's barge-in utterance (if any)
    /// - Returns: Complete FOV context ready for LLM
    public func buildContext(
        conversationHistory: [LLMMessage] = [],
        bargeInUtterance: String? = nil
    ) -> FOVContext {
        // Update immediate buffer with current conversation
        updateImmediateBuffer(
            conversationHistory: conversationHistory,
            bargeInUtterance: bargeInUtterance
        )

        // Render each buffer within its token budget
        let immediateContent = immediateBuffer.render(
            tokenBudget: budgetConfig.immediateTokenBudget
        )
        let workingContent = workingBuffer.render(
            tokenBudget: budgetConfig.workingTokenBudget
        )
        let episodicContent = episodicBuffer.render(
            tokenBudget: budgetConfig.episodicTokenBudget
        )
        let semanticContent = semanticBuffer.render(
            tokenBudget: budgetConfig.semanticTokenBudget
        )

        let context = FOVContext(
            systemPrompt: baseSystemPrompt,
            immediateContext: immediateContent,
            workingContext: workingContent,
            episodicContext: episodicContent,
            semanticContext: semanticContent,
            immediateBufferTurnCount: min(
                conversationHistory.count,
                budgetConfig.conversationTurnCount
            ),
            budgetConfig: budgetConfig
        )

        logger.debug(
            "Built FOV context",
            metadata: [
                "totalTokens": .stringConvertible(context.totalTokenEstimate),
                "turns": .stringConvertible(context.immediateBufferTurnCount)
            ]
        )

        return context
    }

    // MARK: - Buffer Updates

    /// Update immediate buffer with conversation and barge-in
    private func updateImmediateBuffer(
        conversationHistory: [LLMMessage],
        bargeInUtterance: String?
    ) {
        immediateBuffer.bargeInUtterance = bargeInUtterance

        // Convert recent messages to conversation turns
        let turnCount = budgetConfig.conversationTurnCount
        let recentMessages = conversationHistory.suffix(turnCount)

        immediateBuffer.recentTurns = recentMessages.map { message in
            ConversationTurn(from: message)
        }
    }

    /// Set the current TTS segment being played
    /// - Parameter segment: Current segment context
    public func setCurrentSegment(_ segment: TranscriptSegmentContext?) {
        immediateBuffer.currentSegment = segment
        logger.trace("Set current segment: \(segment?.id ?? "nil")")
    }

    /// Set adjacent segments for context
    /// - Parameter segments: Adjacent segments (typically 1-2 before and after)
    public func setAdjacentSegments(_ segments: [TranscriptSegmentContext]) {
        immediateBuffer.adjacentSegments = segments
    }

    /// Update working buffer with topic content
    /// - Parameters:
    ///   - topicTitle: Current topic title
    ///   - topicContent: Topic description/outline
    ///   - learningObjectives: Learning objectives
    ///   - glossaryTerms: Relevant glossary terms
    ///   - misconceptionTriggers: Misconception triggers
    public func updateWorkingBuffer(
        topicTitle: String,
        topicContent: String,
        learningObjectives: [String] = [],
        glossaryTerms: [GlossaryTerm] = [],
        misconceptionTriggers: [MisconceptionTrigger] = []
    ) {
        workingBuffer = WorkingBuffer(
            topicTitle: topicTitle,
            topicContent: topicContent,
            learningObjectives: learningObjectives,
            glossaryTerms: glossaryTerms,
            misconceptionTriggers: misconceptionTriggers
        )

        logger.debug("Updated working buffer for topic: \(topicTitle)")
    }

    /// Add alternative explanations to working buffer
    /// - Parameter explanations: Alternative explanations available
    public func setAlternativeExplanations(_ explanations: [AlternativeExplanation]) {
        workingBuffer.alternativeExplanations = explanations
    }

    /// Expand working buffer with retrieved content
    /// - Parameter content: Content retrieved via semantic search
    public func expandWorkingBuffer(with content: [RetrievedContent]) {
        // Append retrieved content to topic content
        let expansionText = content.map { item in
            "[\(item.sourceTitle)]: \(item.content)"
        }.joined(separator: "\n\n")

        if !expansionText.isEmpty {
            workingBuffer.topicContent += "\n\n## Additional Context\n" + expansionText
            logger.debug("Expanded working buffer with \(content.count) items")
        }
    }

    /// Update semantic buffer with curriculum outline
    /// - Parameters:
    ///   - curriculumOutline: Compressed curriculum outline
    ///   - position: Current position in curriculum
    ///   - dependencies: Topic dependency information
    public func updateSemanticBuffer(
        curriculumOutline: String,
        position: CurriculumPosition,
        dependencies: [String] = []
    ) {
        semanticBuffer = SemanticBuffer(
            curriculumOutline: curriculumOutline,
            currentPosition: position,
            topicDependencies: dependencies
        )

        logger.debug("Updated semantic buffer: \(position.curriculumTitle)")
    }

    // MARK: - Episodic Buffer Management

    /// Record a completed topic in episodic buffer
    /// - Parameter summary: Topic summary to record
    public func recordTopicCompletion(_ summary: FOVTopicSummary) {
        episodicBuffer.topicSummaries.append(summary)

        // Trim old summaries if needed
        let maxSummaries = 10
        if episodicBuffer.topicSummaries.count > maxSummaries {
            episodicBuffer.topicSummaries = Array(episodicBuffer.topicSummaries.suffix(maxSummaries))
        }

        logger.debug("Recorded topic completion: \(summary.title)")
    }

    /// Record a user question
    /// - Parameter question: Question asked by user
    public func recordUserQuestion(_ question: String, wasAnswered: Bool = false) {
        episodicBuffer.userQuestions.append(
            UserQuestion(question: question, wasAnswered: wasAnswered)
        )

        // Trim old questions
        let maxQuestions = 10
        if episodicBuffer.userQuestions.count > maxQuestions {
            episodicBuffer.userQuestions = Array(episodicBuffer.userQuestions.suffix(maxQuestions))
        }
    }

    /// Record an addressed misconception
    /// - Parameter misconception: Misconception that was addressed
    public func recordAddressedMisconception(_ misconception: AddressedMisconception) {
        episodicBuffer.addressedMisconceptions.append(misconception)
    }

    /// Update learner signals
    /// - Parameter signals: Updated learner signals
    public func updateLearnerSignals(_ signals: LearnerSignals) {
        episodicBuffer.learnerSignals = signals
    }

    /// Increment clarification request count
    public func recordClarificationRequest() {
        episodicBuffer.learnerSignals.clarificationRequests += 1
    }

    /// Increment repetition request count
    public func recordRepetitionRequest() {
        episodicBuffer.learnerSignals.repetitionRequests += 1
    }

    // MARK: - Buffer Compression

    /// Compress episodic buffer when approaching token limits
    /// Uses summarizer to condense older content
    public func compressEpisodicBuffer() async {
        guard let summarizer = summarizer else {
            logger.warning("Cannot compress: no summarizer configured")
            return
        }

        // Summarize older topic summaries
        if episodicBuffer.topicSummaries.count > 5 {
            let oldSummaries = Array(episodicBuffer.topicSummaries.prefix(3))
            let summaryTexts = oldSummaries.map { "\($0.title): \($0.summary)" }
            let combinedText = summaryTexts.joined(separator: "\n")

            let condensed = await summarizer.summarizeTopicContent(combinedText)

            // Replace old summaries with single condensed one
            let condensedSummary = FOVTopicSummary(
                topicId: UUID(),
                title: "Earlier topics",
                summary: condensed,
                masteryLevel: oldSummaries.map(\.masteryLevel).reduce(0, +) / Double(oldSummaries.count)
            )

            episodicBuffer.topicSummaries = [condensedSummary] +
                Array(episodicBuffer.topicSummaries.dropFirst(3))

            logger.info("Compressed episodic buffer: merged \(oldSummaries.count) summaries")
        }
    }

    // MARK: - Configuration

    /// Update budget configuration for a different model
    /// - Parameter model: New model identifier
    public func updateModelConfig(model: String) {
        let contextWindow = ModelContextWindows.contextWindow(for: model)
        budgetConfig = AdaptiveBudgetConfig(modelContextWindow: contextWindow)

        logger.info(
            "Updated model config",
            metadata: [
                "model": .string(model),
                "tier": .string(budgetConfig.tier.rawValue)
            ]
        )
    }

    /// Update budget configuration with specific context window
    /// - Parameter contextWindow: Context window size in tokens
    public func updateContextWindow(_ contextWindow: Int) {
        budgetConfig = AdaptiveBudgetConfig(modelContextWindow: contextWindow)
    }

    /// Get current budget configuration
    public func getBudgetConfig() -> AdaptiveBudgetConfig {
        budgetConfig
    }

    /// Set the summarizer for buffer compression
    /// - Parameter summarizer: Summarizer to use
    public func setSummarizer(_ summarizer: ContextSummarizer) {
        self.summarizer = summarizer
    }

    // MARK: - Reset

    /// Reset all buffers (e.g., when starting new session)
    public func reset() {
        immediateBuffer = ImmediateBuffer()
        workingBuffer = WorkingBuffer()
        episodicBuffer = EpisodicBuffer()
        semanticBuffer = SemanticBuffer()

        logger.info("FOVContextManager reset")
    }

    /// Reset only the immediate buffer (e.g., when topic changes)
    public func resetImmediateBuffer() {
        immediateBuffer = ImmediateBuffer()
    }

    // MARK: - Default System Prompt

    /// Default system prompt for voice tutoring
    public static let defaultSystemPrompt = """
    You are an expert AI tutor conducting a voice-based educational session.

    INTERACTION GUIDELINES:
    - You are in a voice conversation, so be conversational and natural
    - Keep responses concise but comprehensive
    - Use Socratic questioning to guide learning
    - Encourage critical thinking and exploration
    - Adapt explanations to the student's demonstrated understanding
    - Use concrete examples and analogies
    - Check for understanding regularly
    - Be prepared for interruptions and clarification questions

    If the student interrupts or asks a question, respond helpfully based on the context provided. You have access to the curriculum content, learning objectives, and session history.

    Always maintain a supportive, encouraging tone while being intellectually rigorous.
    """
}

// MARK: - Convenience Extensions

extension FOVContextManager {
    /// Build context from curriculum engine data
    /// - Parameters:
    ///   - topic: Current topic being studied
    ///   - curriculum: Active curriculum
    ///   - conversationHistory: Recent conversation
    ///   - bargeInUtterance: User's barge-in utterance
    /// - Returns: Complete FOV context
    public func buildContext(
        topic: Topic,
        curriculum: Curriculum?,
        conversationHistory: [LLMMessage],
        bargeInUtterance: String? = nil
    ) -> FOVContext {
        // Update working buffer from topic
        updateWorkingBuffer(
            topicTitle: topic.title ?? "Unknown Topic",
            topicContent: topic.outline ?? "",
            learningObjectives: topic.learningObjectives
        )

        // Update semantic buffer from curriculum
        if let curriculum = curriculum {
            let topics = (curriculum.topics?.array as? [Topic]) ?? []
            let currentIndex = topics.firstIndex(where: { $0.id == topic.id }) ?? 0

            let outline = topics.prefix(20).map { t in
                "\(t.orderIndex + 1). \(t.title ?? "Untitled")"
            }.joined(separator: "\n")

            updateSemanticBuffer(
                curriculumOutline: outline,
                position: CurriculumPosition(
                    curriculumTitle: curriculum.name ?? "",
                    currentTopicIndex: currentIndex,
                    totalTopics: topics.count
                )
            )
        }

        // Build and return context
        return buildContext(
            conversationHistory: conversationHistory,
            bargeInUtterance: bargeInUtterance
        )
    }
}
