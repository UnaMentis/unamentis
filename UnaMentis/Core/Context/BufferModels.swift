// UnaMentis - FOV Context Buffer Models
// Data structures for hierarchical context management
//
// Part of FOV Context Management System

import Foundation

// MARK: - FOV Context

/// Complete hierarchical context for LLM calls
/// Contains all buffer layers merged into a single context payload
public struct FOVContext: Sendable {
    /// Base tutor system prompt
    public let systemPrompt: String

    /// Immediate buffer: verbatim recent conversation + current segment
    public let immediateContext: String

    /// Working buffer: current topic content + objectives + glossary
    public let workingContext: String

    /// Episodic buffer: compressed session history + learner signals
    public let episodicContext: String

    /// Semantic buffer: curriculum outline + position
    public let semanticContext: String

    /// Number of conversation turns included in immediate buffer
    public let immediateBufferTurnCount: Int

    /// Budget configuration used to build this context
    public let budgetConfig: AdaptiveBudgetConfig

    /// Timestamp when this context was generated
    public let generatedAt: Date

    public init(
        systemPrompt: String,
        immediateContext: String,
        workingContext: String,
        episodicContext: String,
        semanticContext: String,
        immediateBufferTurnCount: Int,
        budgetConfig: AdaptiveBudgetConfig,
        generatedAt: Date = Date()
    ) {
        self.systemPrompt = systemPrompt
        self.immediateContext = immediateContext
        self.workingContext = workingContext
        self.episodicContext = episodicContext
        self.semanticContext = semanticContext
        self.immediateBufferTurnCount = immediateBufferTurnCount
        self.budgetConfig = budgetConfig
        self.generatedAt = generatedAt
    }

    /// Flatten all buffers into a single system message for LLM
    public func toSystemMessage() -> String {
        var sections: [String] = []

        sections.append(systemPrompt)

        if !semanticContext.isEmpty {
            sections.append("""
            ## CURRICULUM OVERVIEW
            \(semanticContext)
            """)
        }

        if !episodicContext.isEmpty {
            sections.append("""
            ## SESSION HISTORY
            \(episodicContext)
            """)
        }

        if !workingContext.isEmpty {
            sections.append("""
            ## CURRENT TOPIC CONTEXT
            \(workingContext)
            """)
        }

        if !immediateContext.isEmpty {
            sections.append("""
            ## IMMEDIATE CONTEXT
            \(immediateContext)
            """)
        }

        return sections.joined(separator: "\n\n")
    }

    /// Estimated total token count for this context
    public var totalTokenEstimate: Int {
        let totalChars = systemPrompt.count +
            immediateContext.count +
            workingContext.count +
            episodicContext.count +
            semanticContext.count
        // Rough estimate: ~4 characters per token for English
        return totalChars / 4
    }
}

// MARK: - Adaptive Budget Configuration

/// Token budget configuration that adapts to model context window size
public struct AdaptiveBudgetConfig: Sendable, Equatable {
    /// Model's maximum context window in tokens
    public let modelContextWindow: Int

    /// Model tier classification
    public let tier: ModelTier

    /// Token budget for immediate buffer (recent conversation)
    public var immediateTokenBudget: Int {
        tier.budgets.immediate
    }

    /// Token budget for working buffer (current topic)
    public var workingTokenBudget: Int {
        tier.budgets.working
    }

    /// Token budget for episodic buffer (session history)
    public var episodicTokenBudget: Int {
        tier.budgets.episodic
    }

    /// Token budget for semantic buffer (curriculum outline)
    public var semanticTokenBudget: Int {
        tier.budgets.semantic
    }

    /// Total budget across all buffers
    public var totalBudget: Int {
        tier.budgets.total
    }

    /// Number of conversation turns to keep verbatim
    public var conversationTurnCount: Int {
        tier.conversationTurns
    }

    public init(modelContextWindow: Int) {
        self.modelContextWindow = modelContextWindow
        self.tier = ModelTier.from(contextWindow: modelContextWindow)
    }

    /// Create config for a specific model identifier
    public static func forModel(_ model: String) -> AdaptiveBudgetConfig {
        let contextWindow = ModelContextWindows.contextWindow(for: model)
        return AdaptiveBudgetConfig(modelContextWindow: contextWindow)
    }
}

// MARK: - Model Tier

/// Classification of model capability based on context window
public enum ModelTier: String, Sendable, CaseIterable {
    case cloud       // 128K+ tokens (GPT-4o, Claude 3.5)
    case midRange    // 32K-128K tokens
    case onDevice    // 8K-32K tokens
    case tiny        // <8K tokens

    /// Token budgets for each buffer tier
    public var budgets: BufferBudgets {
        switch self {
        case .cloud:
            return BufferBudgets(
                total: 12_000,
                immediate: 3_000,
                working: 5_000,
                episodic: 2_500,
                semantic: 1_500
            )
        case .midRange:
            return BufferBudgets(
                total: 8_000,
                immediate: 2_000,
                working: 3_500,
                episodic: 1_500,
                semantic: 1_000
            )
        case .onDevice:
            return BufferBudgets(
                total: 4_000,
                immediate: 1_200,
                working: 1_500,
                episodic: 800,
                semantic: 500
            )
        case .tiny:
            return BufferBudgets(
                total: 2_000,
                immediate: 800,
                working: 700,
                episodic: 300,
                semantic: 200
            )
        }
    }

    /// Number of conversation turns to keep verbatim
    public var conversationTurns: Int {
        switch self {
        case .cloud: return 10
        case .midRange: return 7
        case .onDevice: return 5
        case .tiny: return 3
        }
    }

    /// Classify model tier from context window size
    public static func from(contextWindow: Int) -> ModelTier {
        switch contextWindow {
        case 128_000...: return .cloud
        case 32_000..<128_000: return .midRange
        case 8_000..<32_000: return .onDevice
        default: return .tiny
        }
    }
}

/// Token budgets for buffer tiers
public struct BufferBudgets: Sendable, Equatable {
    public let total: Int
    public let immediate: Int
    public let working: Int
    public let episodic: Int
    public let semantic: Int
}

// MARK: - Model Context Windows

/// Lookup table for known model context windows
public enum ModelContextWindows {
    /// Get context window size for a model identifier
    public static func contextWindow(for model: String) -> Int {
        let normalizedModel = model.lowercased()

        // OpenAI models
        if normalizedModel.contains("gpt-4o") {
            return 128_000
        }
        if normalizedModel.contains("gpt-4-turbo") {
            return 128_000
        }
        if normalizedModel.contains("gpt-4") {
            return 8_192
        }
        if normalizedModel.contains("gpt-3.5") {
            return 16_385
        }

        // Anthropic models
        if normalizedModel.contains("claude-3") {
            return 200_000
        }
        if normalizedModel.contains("claude-2") {
            return 100_000
        }

        // Self-hosted models (common configurations)
        if normalizedModel.contains("qwen2.5") {
            return 32_768
        }
        if normalizedModel.contains("llama3.2") {
            return 128_000
        }
        if normalizedModel.contains("llama3.1") {
            return 128_000
        }
        if normalizedModel.contains("mistral") {
            return 32_768
        }

        // On-device models
        if normalizedModel.contains("ministral") {
            return 8_192
        }
        if normalizedModel.contains("phi") {
            return 4_096
        }

        // Default fallback
        return 8_192
    }
}

// MARK: - Buffer Content Types

/// Content for the immediate buffer
public struct ImmediateBuffer: Sendable {
    /// Current TTS segment being played
    public var currentSegment: TranscriptSegmentContext?

    /// Adjacent segments for context (typically 1-2 before and after)
    public var adjacentSegments: [TranscriptSegmentContext]

    /// Recent conversation turns (verbatim)
    public var recentTurns: [ConversationTurn]

    /// User's barge-in utterance (if applicable)
    public var bargeInUtterance: String?

    public init(
        currentSegment: TranscriptSegmentContext? = nil,
        adjacentSegments: [TranscriptSegmentContext] = [],
        recentTurns: [ConversationTurn] = [],
        bargeInUtterance: String? = nil
    ) {
        self.currentSegment = currentSegment
        self.adjacentSegments = adjacentSegments
        self.recentTurns = recentTurns
        self.bargeInUtterance = bargeInUtterance
    }

    /// Render to string within token budget
    public func render(tokenBudget: Int) -> String {
        var parts: [String] = []
        var estimatedTokens = 0

        // Always include barge-in utterance first (highest priority)
        if let bargeIn = bargeInUtterance, !bargeIn.isEmpty {
            let bargeInText = "The user just interrupted with: \"\(bargeIn)\""
            parts.append(bargeInText)
            estimatedTokens += bargeInText.count / 4
        }

        // Include current segment
        if let segment = currentSegment {
            let segmentText = "Currently teaching: \(segment.content)"
            if estimatedTokens + segmentText.count / 4 <= tokenBudget {
                parts.append(segmentText)
                estimatedTokens += segmentText.count / 4
            }
        }

        // Include recent turns (newest first, within budget)
        for turn in recentTurns.reversed() {
            let turnText = "[\(turn.role.rawValue.capitalized)]: \(turn.content)"
            let turnTokens = turnText.count / 4
            if estimatedTokens + turnTokens <= tokenBudget {
                parts.insert(turnText, at: parts.count > 0 ? 1 : 0)
                estimatedTokens += turnTokens
            } else {
                break
            }
        }

        return parts.joined(separator: "\n\n")
    }
}

/// Content for the working buffer
public struct WorkingBuffer: Sendable {
    /// Current topic title
    public var topicTitle: String

    /// Topic description/outline
    public var topicContent: String

    /// Learning objectives for current topic
    public var learningObjectives: [String]

    /// Glossary terms relevant to current segment
    public var glossaryTerms: [GlossaryTerm]

    /// Alternative explanations available
    public var alternativeExplanations: [AlternativeExplanation]

    /// Misconception triggers for current topic
    public var misconceptionTriggers: [MisconceptionTrigger]

    public init(
        topicTitle: String = "",
        topicContent: String = "",
        learningObjectives: [String] = [],
        glossaryTerms: [GlossaryTerm] = [],
        alternativeExplanations: [AlternativeExplanation] = [],
        misconceptionTriggers: [MisconceptionTrigger] = []
    ) {
        self.topicTitle = topicTitle
        self.topicContent = topicContent
        self.learningObjectives = learningObjectives
        self.glossaryTerms = glossaryTerms
        self.alternativeExplanations = alternativeExplanations
        self.misconceptionTriggers = misconceptionTriggers
    }

    /// Render to string within token budget
    public func render(tokenBudget: Int) -> String {
        var parts: [String] = []
        var estimatedTokens = 0

        // Topic title and content (highest priority)
        let titleSection = "Topic: \(topicTitle)\n\(topicContent)"
        parts.append(titleSection)
        estimatedTokens += titleSection.count / 4

        // Learning objectives
        if !learningObjectives.isEmpty && estimatedTokens < tokenBudget {
            let objectivesText = "Learning Objectives:\n" +
                learningObjectives.map { "- \($0)" }.joined(separator: "\n")
            if estimatedTokens + objectivesText.count / 4 <= tokenBudget {
                parts.append(objectivesText)
                estimatedTokens += objectivesText.count / 4
            }
        }

        // Glossary terms
        if !glossaryTerms.isEmpty && estimatedTokens < tokenBudget {
            let glossaryText = "Key Terms:\n" +
                glossaryTerms.map { "- \($0.term): \($0.definition)" }.joined(separator: "\n")
            if estimatedTokens + glossaryText.count / 4 <= tokenBudget {
                parts.append(glossaryText)
                estimatedTokens += glossaryText.count / 4
            }
        }

        // Misconception triggers (important for tutoring)
        if !misconceptionTriggers.isEmpty && estimatedTokens < tokenBudget {
            let triggerText = "Watch for these common misconceptions:\n" +
                misconceptionTriggers.map { "- If student says '\($0.triggerPhrase)': \($0.remediation)" }
                    .joined(separator: "\n")
            if estimatedTokens + triggerText.count / 4 <= tokenBudget {
                parts.append(triggerText)
                estimatedTokens += triggerText.count / 4
            }
        }

        return parts.joined(separator: "\n\n")
    }
}

/// Content for the episodic buffer
public struct EpisodicBuffer: Sendable {
    /// Summaries of prior topics covered in this session
    public var topicSummaries: [FOVTopicSummary]

    /// User's questions/confusions from earlier
    public var userQuestions: [UserQuestion]

    /// Misconceptions that were triggered and addressed
    public var addressedMisconceptions: [AddressedMisconception]

    /// Learning profile signals detected during session
    public var learnerSignals: LearnerSignals

    public init(
        topicSummaries: [FOVTopicSummary] = [],
        userQuestions: [UserQuestion] = [],
        addressedMisconceptions: [AddressedMisconception] = [],
        learnerSignals: LearnerSignals = LearnerSignals()
    ) {
        self.topicSummaries = topicSummaries
        self.userQuestions = userQuestions
        self.addressedMisconceptions = addressedMisconceptions
        self.learnerSignals = learnerSignals
    }

    /// Render to string within token budget
    public func render(tokenBudget: Int) -> String {
        var parts: [String] = []
        var estimatedTokens = 0

        // Learner signals (concise, high value)
        let signalsText = learnerSignals.render()
        if !signalsText.isEmpty {
            parts.append(signalsText)
            estimatedTokens += signalsText.count / 4
        }

        // Topic summaries (most recent first)
        if !topicSummaries.isEmpty {
            let summariesText = "Topics covered:\n" +
                topicSummaries.suffix(5).map { "- \($0.title): \($0.summary)" }.joined(separator: "\n")
            if estimatedTokens + summariesText.count / 4 <= tokenBudget {
                parts.append(summariesText)
                estimatedTokens += summariesText.count / 4
            }
        }

        // Recent user questions
        if !userQuestions.isEmpty && estimatedTokens < tokenBudget {
            let questionsText = "Student's earlier questions:\n" +
                userQuestions.suffix(3).map { "- \($0.question)" }.joined(separator: "\n")
            if estimatedTokens + questionsText.count / 4 <= tokenBudget {
                parts.append(questionsText)
                estimatedTokens += questionsText.count / 4
            }
        }

        return parts.joined(separator: "\n\n")
    }
}

/// Content for the semantic buffer
public struct SemanticBuffer: Sendable {
    /// Compressed curriculum outline (titles + brief objectives)
    public var curriculumOutline: String

    /// Current position in curriculum
    public var currentPosition: CurriculumPosition

    /// Topic dependency information
    public var topicDependencies: [String]

    public init(
        curriculumOutline: String = "",
        currentPosition: CurriculumPosition = CurriculumPosition(),
        topicDependencies: [String] = []
    ) {
        self.curriculumOutline = curriculumOutline
        self.currentPosition = currentPosition
        self.topicDependencies = topicDependencies
    }

    /// Render to string within token budget
    public func render(tokenBudget: Int) -> String {
        var parts: [String] = []

        // Current position (always included)
        parts.append(currentPosition.render())

        // Curriculum outline (compressed)
        if !curriculumOutline.isEmpty {
            // Truncate outline to fit budget
            let outlineTokens = curriculumOutline.count / 4
            let availableTokens = tokenBudget - parts.joined().count / 4
            if outlineTokens <= availableTokens {
                parts.append("Course outline:\n\(curriculumOutline)")
            } else {
                // Truncate to fit
                let truncatedLength = availableTokens * 4
                let truncated = String(curriculumOutline.prefix(truncatedLength)) + "..."
                parts.append("Course outline:\n\(truncated)")
            }
        }

        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Supporting Types

/// Context for a transcript segment
public struct TranscriptSegmentContext: Sendable, Identifiable {
    public let id: String
    public let content: String
    public let segmentIndex: Int
    public let glossaryRefs: [String]

    public init(id: String, content: String, segmentIndex: Int, glossaryRefs: [String] = []) {
        self.id = id
        self.content = content
        self.segmentIndex = segmentIndex
        self.glossaryRefs = glossaryRefs
    }
}

/// A single turn in conversation history
public struct ConversationTurn: Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    public let role: Role
    public let content: String
    public let timestamp: Date

    public init(role: Role, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    /// Create from LLMMessage
    public init(from message: LLMMessage, timestamp: Date = Date()) {
        switch message.role {
        case .user: self.role = .user
        case .assistant: self.role = .assistant
        case .system: self.role = .system
        }
        self.content = message.content
        self.timestamp = timestamp
    }
}

/// Glossary term with definition
public struct GlossaryTerm: Sendable {
    public let term: String
    public let definition: String
    public let spokenDefinition: String?

    public init(term: String, definition: String, spokenDefinition: String? = nil) {
        self.term = term
        self.definition = definition
        self.spokenDefinition = spokenDefinition
    }
}

/// Alternative explanation for a concept
public struct AlternativeExplanation: Sendable {
    public enum Style: String, Sendable {
        case simpler
        case technical
        case analogy
    }

    public let style: Style
    public let content: String

    public init(style: Style, content: String) {
        self.style = style
        self.content = content
    }
}

/// Misconception trigger with remediation
public struct MisconceptionTrigger: Sendable {
    public let triggerPhrase: String
    public let misconception: String
    public let remediation: String

    public init(triggerPhrase: String, misconception: String, remediation: String) {
        self.triggerPhrase = triggerPhrase
        self.misconception = misconception
        self.remediation = remediation
    }
}

/// Summary of a completed topic for FOV context episodic buffer
public struct FOVTopicSummary: Sendable {
    public let topicId: UUID
    public let title: String
    public let summary: String
    public let masteryLevel: Double
    public let completedAt: Date

    public init(
        topicId: UUID,
        title: String,
        summary: String,
        masteryLevel: Double,
        completedAt: Date = Date()
    ) {
        self.topicId = topicId
        self.title = title
        self.summary = summary
        self.masteryLevel = masteryLevel
        self.completedAt = completedAt
    }
}

/// User question from earlier in the session
public struct UserQuestion: Sendable {
    public let question: String
    public let wasAnswered: Bool
    public let timestamp: Date

    public init(question: String, wasAnswered: Bool, timestamp: Date = Date()) {
        self.question = question
        self.wasAnswered = wasAnswered
        self.timestamp = timestamp
    }
}

/// Misconception that was addressed
public struct AddressedMisconception: Sendable {
    public let misconception: String
    public let remediation: String
    public let seemsResolved: Bool
    public let addressedAt: Date

    public init(
        misconception: String,
        remediation: String,
        seemsResolved: Bool,
        addressedAt: Date = Date()
    ) {
        self.misconception = misconception
        self.remediation = remediation
        self.seemsResolved = seemsResolved
        self.addressedAt = addressedAt
    }
}

/// Learner profile signals detected during session
public struct LearnerSignals: Sendable {
    /// Detected pace preference (slow, moderate, fast)
    public var pacePreference: PacePreference?

    /// Detected explanation style preference
    public var explanationStylePreference: AlternativeExplanation.Style?

    /// Number of clarification requests
    public var clarificationRequests: Int

    /// Number of repetition requests
    public var repetitionRequests: Int

    /// Average think time before responding (seconds)
    public var averageThinkTime: TimeInterval?

    public init(
        pacePreference: PacePreference? = nil,
        explanationStylePreference: AlternativeExplanation.Style? = nil,
        clarificationRequests: Int = 0,
        repetitionRequests: Int = 0,
        averageThinkTime: TimeInterval? = nil
    ) {
        self.pacePreference = pacePreference
        self.explanationStylePreference = explanationStylePreference
        self.clarificationRequests = clarificationRequests
        self.repetitionRequests = repetitionRequests
        self.averageThinkTime = averageThinkTime
    }

    /// Render to concise string
    public func render() -> String {
        var signals: [String] = []

        if let pace = pacePreference {
            signals.append("Preferred pace: \(pace.rawValue)")
        }
        if let style = explanationStylePreference {
            signals.append("Prefers \(style.rawValue) explanations")
        }
        if clarificationRequests > 2 {
            signals.append("Has asked for clarification \(clarificationRequests) times")
        }
        if repetitionRequests > 1 {
            signals.append("Has requested repetition \(repetitionRequests) times")
        }

        return signals.isEmpty ? "" : "Learner profile: " + signals.joined(separator: "; ")
    }
}

/// Pace preference enum
public enum PacePreference: String, Sendable {
    case slow
    case moderate
    case fast
}

/// Current position in curriculum
public struct CurriculumPosition: Sendable {
    public var curriculumTitle: String
    public var currentTopicIndex: Int
    public var totalTopics: Int
    public var currentUnitTitle: String?

    public init(
        curriculumTitle: String = "",
        currentTopicIndex: Int = 0,
        totalTopics: Int = 0,
        currentUnitTitle: String? = nil
    ) {
        self.curriculumTitle = curriculumTitle
        self.currentTopicIndex = currentTopicIndex
        self.totalTopics = totalTopics
        self.currentUnitTitle = currentUnitTitle
    }

    /// Render position to string
    public func render() -> String {
        var parts: [String] = []

        if !curriculumTitle.isEmpty {
            parts.append("Course: \(curriculumTitle)")
        }

        if let unit = currentUnitTitle {
            parts.append("Unit: \(unit)")
        }

        if totalTopics > 0 {
            let progress = Int((Double(currentTopicIndex + 1) / Double(totalTopics)) * 100)
            parts.append("Progress: Topic \(currentTopicIndex + 1) of \(totalTopics) (\(progress)%)")
        }

        return parts.joined(separator: " | ")
    }
}

// MARK: - Expansion Types

/// Scope for context expansion requests
public enum ExpansionScope: String, Sendable {
    case currentTopic     // Search within current topic only
    case currentUnit      // Search within current unit
    case fullCurriculum   // Search entire curriculum
    case relatedTopics    // Search related/prerequisite topics
}

/// Result of context expansion
public struct ExpansionResult: Sendable {
    public let query: String
    public let scope: ExpansionScope
    public let retrievedContent: [RetrievedContent]
    public let totalTokens: Int

    public init(query: String, scope: ExpansionScope, retrievedContent: [RetrievedContent]) {
        self.query = query
        self.scope = scope
        self.retrievedContent = retrievedContent
        self.totalTokens = retrievedContent.reduce(0) { $0 + $1.estimatedTokens }
    }
}

/// Content retrieved during expansion
public struct RetrievedContent: Sendable {
    public let sourceTitle: String
    public let content: String
    public let relevanceScore: Float
    public let estimatedTokens: Int

    public init(sourceTitle: String, content: String, relevanceScore: Float) {
        self.sourceTitle = sourceTitle
        self.content = content
        self.relevanceScore = relevanceScore
        self.estimatedTokens = content.count / 4
    }
}
