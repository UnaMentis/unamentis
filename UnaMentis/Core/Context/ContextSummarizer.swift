// UnaMentis - Context Summarizer
// Compression and summarization for episodic buffer management
//
// Part of FOV Context Management System
//
// Uses a smaller/cheaper LLM to compress older conversation
// content while preserving essential information.

import Foundation
import Logging

/// Actor responsible for summarizing and compressing context content
/// Uses a cost-optimized LLM for summarization tasks
public actor ContextSummarizer {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.contextsummarizer")

    /// LLM service for generating summaries
    private let llmService: any LLMService

    /// Configuration for summarization
    private var config: SummarizerConfig

    /// Cache for recent summaries to avoid redundant work
    private var summaryCache: [String: CachedSummary] = [:]
    private let maxCacheSize = 50

    // MARK: - Initialization

    /// Initialize with an LLM service
    /// - Parameters:
    ///   - llmService: LLM service for generating summaries
    ///   - config: Summarizer configuration
    public init(
        llmService: any LLMService,
        config: SummarizerConfig = .default
    ) {
        self.llmService = llmService
        self.config = config
        logger.info("ContextSummarizer initialized")
    }

    // MARK: - Summarization

    /// Summarize conversation turns into a compressed representation
    /// - Parameter turns: Conversation turns to summarize
    /// - Returns: Compressed summary of the conversation
    public func summarizeTurns(_ turns: [ConversationTurn]) async -> String {
        guard !turns.isEmpty else { return "" }

        // Create cache key
        let cacheKey = turns.map { "\($0.role):\($0.content.prefix(50))" }.joined(separator: "|")
        if let cached = summaryCache[cacheKey], !cached.isExpired {
            logger.debug("Using cached summary")
            return cached.summary
        }

        // Format turns for summarization
        let turnText = turns.map { turn in
            "[\(turn.role.rawValue.capitalized)]: \(turn.content)"
        }.joined(separator: "\n\n")

        let prompt = """
        Summarize the following conversation between a student and AI tutor.
        Focus on:
        - Key topics discussed
        - Questions asked by the student
        - Main points explained
        - Any areas of confusion or difficulty

        Keep the summary concise (2-3 sentences max).

        Conversation:
        \(turnText)

        Summary:
        """

        let summary = await generateSummary(prompt)

        // Cache result
        cacheSummary(cacheKey, summary: summary)

        return summary
    }

    /// Summarize topic content for the episodic buffer
    /// - Parameter content: Topic content to summarize
    /// - Returns: Compressed summary
    public func summarizeTopicContent(_ content: String) async -> String {
        guard !content.isEmpty else { return "" }

        // Check cache
        let cacheKey = "topic:" + String(content.hashValue)
        if let cached = summaryCache[cacheKey], !cached.isExpired {
            return cached.summary
        }

        let prompt = """
        Summarize the following educational topic content into a brief overview.
        Focus on the main concepts and key takeaways.
        Keep it under 2 sentences.

        Content:
        \(content.prefix(config.maxInputLength))

        Summary:
        """

        let summary = await generateSummary(prompt)
        cacheSummary(cacheKey, summary: summary)

        return summary
    }

    /// Summarize a list of user questions
    /// - Parameter questions: Questions to summarize
    /// - Returns: Compressed summary of question themes
    public func summarizeQuestions(_ questions: [UserQuestion]) async -> String {
        guard !questions.isEmpty else { return "" }

        let questionText = questions.map { $0.question }.joined(separator: "\n- ")

        let prompt = """
        Identify the main themes from these student questions:
        - \(questionText)

        List 1-3 key areas of interest or confusion (one line each):
        """

        return await generateSummary(prompt)
    }

    /// Generate a learning progress summary
    /// - Parameters:
    ///   - topicSummaries: Summaries of completed topics
    ///   - signals: Learner signals detected
    /// - Returns: Progress summary
    public func generateProgressSummary(
        topicSummaries: [FOVTopicSummary],
        signals: LearnerSignals
    ) async -> String {
        guard !topicSummaries.isEmpty else { return "" }

        let topicsText = topicSummaries.map { summary in
            "\(summary.title) (mastery: \(Int(summary.masteryLevel * 100))%)"
        }.joined(separator: ", ")

        var signalsText = ""
        if let pace = signals.pacePreference {
            signalsText += "Pace preference: \(pace.rawValue). "
        }
        if signals.clarificationRequests > 0 {
            signalsText += "Asked for clarification \(signals.clarificationRequests) times. "
        }

        let prompt = """
        Create a brief learning progress note:
        Topics covered: \(topicsText)
        \(signalsText)

        Write one sentence summarizing the student's progress and any notable patterns:
        """

        return await generateSummary(prompt)
    }

    // MARK: - Compression Utilities

    /// Compress text to fit within a token budget
    /// - Parameters:
    ///   - text: Text to compress
    ///   - targetTokens: Target token count
    /// - Returns: Compressed text within budget
    public func compressToFit(_ text: String, targetTokens: Int) async -> String {
        let estimatedTokens = text.count / 4

        // If already fits, return as-is
        if estimatedTokens <= targetTokens {
            return text
        }

        // Calculate compression ratio needed
        let ratio = Float(targetTokens) / Float(estimatedTokens)

        let prompt: String
        if ratio > 0.5 {
            // Light compression
            prompt = """
            Condense this text by removing redundancy while keeping all key information:

            \(text.prefix(config.maxInputLength))

            Condensed version (about \(Int(ratio * 100))% of original length):
            """
        } else {
            // Heavy compression
            prompt = """
            Summarize the essential points from this text in just 1-2 sentences:

            \(text.prefix(config.maxInputLength))

            Essential summary:
            """
        }

        return await generateSummary(prompt)
    }

    /// Extract key concepts from text
    /// - Parameter text: Text to extract from
    /// - Returns: List of key concepts
    public func extractKeyConcepts(_ text: String) async -> [String] {
        let prompt = """
        Extract 3-5 key concepts from this educational content as a comma-separated list:

        \(text.prefix(config.maxInputLength))

        Key concepts:
        """

        let response = await generateSummary(prompt)
        return response.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Internal Helpers

    /// Generate a summary using the LLM
    private func generateSummary(_ prompt: String) async -> String {
        do {
            let messages = [
                LLMMessage(role: .system, content: config.systemPrompt),
                LLMMessage(role: .user, content: prompt)
            ]

            let response = try await llmService.complete(
                messages: messages,
                config: config.llmConfig
            )

            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("Summarization failed: \(error.localizedDescription)")
            // Fall back to simple truncation
            return String(prompt.prefix(200)) + "..."
        }
    }

    /// Cache a summary
    private func cacheSummary(_ key: String, summary: String) {
        // Evict old entries if cache is full
        if summaryCache.count >= maxCacheSize {
            let oldestKey = summaryCache.min { $0.value.timestamp < $1.value.timestamp }?.key
            if let key = oldestKey {
                summaryCache.removeValue(forKey: key)
            }
        }

        summaryCache[key] = CachedSummary(
            summary: summary,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(config.cacheExpiration)
        )
    }

    // MARK: - Configuration

    /// Update summarizer configuration
    public func updateConfig(_ config: SummarizerConfig) {
        self.config = config
    }

    /// Clear the summary cache
    public func clearCache() {
        summaryCache.removeAll()
        logger.info("Summary cache cleared")
    }
}

// MARK: - Supporting Types

/// Configuration for the summarizer
public struct SummarizerConfig: Sendable {
    /// System prompt for summarization tasks
    public var systemPrompt: String

    /// LLM configuration to use
    public var llmConfig: LLMConfig

    /// Maximum input length to process
    public var maxInputLength: Int

    /// Cache expiration time in seconds
    public var cacheExpiration: TimeInterval

    public static let `default` = SummarizerConfig(
        systemPrompt: """
            You are a concise summarization assistant for an educational tutoring system.
            Create brief, accurate summaries that preserve essential information.
            Be direct and avoid filler words.
            """,
        llmConfig: LLMConfig.costOptimized,
        maxInputLength: 4000,
        cacheExpiration: 3600 // 1 hour
    )

    /// Configuration optimized for minimal token usage
    public static let minimal = SummarizerConfig(
        systemPrompt: "Summarize concisely.",
        llmConfig: LLMConfig(
            model: "gpt-4o-mini",
            maxTokens: 150,
            temperature: 0.3,
            stream: false
        ),
        maxInputLength: 2000,
        cacheExpiration: 1800
    )

    public init(
        systemPrompt: String,
        llmConfig: LLMConfig,
        maxInputLength: Int,
        cacheExpiration: TimeInterval
    ) {
        self.systemPrompt = systemPrompt
        self.llmConfig = llmConfig
        self.maxInputLength = maxInputLength
        self.cacheExpiration = cacheExpiration
    }
}

/// Cached summary entry
private struct CachedSummary {
    let summary: String
    let timestamp: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }
}
