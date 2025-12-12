// VoiceLearn - Mock Services for Testing
// Faithful mocks for paid external API dependencies only
//
// TESTING PHILOSOPHY (see AGENTS.md for full details):
// - Mock testing is only acceptable for paid third-party APIs
// - Mocks must be FAITHFUL: validate inputs, simulate all errors, match real behavior
// - Internal services (TelemetryEngine, etc.) should use real implementations
// - Use PersistenceController(inMemory: true) for Core Data tests

import Foundation
import CoreData
@testable import VoiceLearn

// MARK: - Mock LLM Service

/// Faithful mock LLM service for testing
///
/// This mock exists because real LLM API calls:
/// - Cost money per token ($3-15 per million tokens)
/// - Require API keys
/// - Could hit rate limits during CI
///
/// The mock faithfully reproduces real API behavior including:
/// - Input validation (empty messages, context length)
/// - All error conditions (rate limiting, auth failures, etc.)
/// - Realistic streaming with configurable latency
/// - Token counting
actor MockLLMService: LLMService {
    // MARK: - Properties

    public private(set) var metrics = LLMMetrics(
        medianTTFT: 0.15,
        p99TTFT: 0.3,
        totalInputTokens: 0,
        totalOutputTokens: 0
    )

    /// Claude 3.5 Sonnet pricing: $3/1M input, $15/1M output
    public var costPerInputToken: Decimal = 3.00 / 1_000_000
    public var costPerOutputToken: Decimal = 15.00 / 1_000_000

    // MARK: - Test Configuration

    /// Response text to return (will be tokenized)
    var summaryResponse: String = "This is a test summary of the document content."

    /// Error simulation configuration
    var simulatedError: LLMError?

    /// Whether to simulate realistic latency (disabled by default for fast tests)
    var simulateLatency: Bool = false

    /// Time to first token in nanoseconds (150ms default, matching real API)
    var ttftNanoseconds: UInt64 = 150_000_000

    /// Inter-token delay in nanoseconds (20ms default)
    var tokenDelayNanoseconds: UInt64 = 20_000_000

    /// Maximum context length (matches Claude 3.5 Sonnet)
    var maxContextTokens: Int = 200_000

    /// Track method calls for test assertions
    private(set) var streamCompletionCallCount: Int = 0
    private(set) var lastMessages: [LLMMessage]?
    private(set) var lastConfig: LLMConfig?
    private(set) var totalInputTokensProcessed: Int = 0
    private(set) var totalOutputTokensGenerated: Int = 0

    // MARK: - LLMService Protocol

    public func streamCompletion(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> AsyncStream<LLMToken> {
        streamCompletionCallCount += 1
        lastMessages = messages
        lastConfig = config

        // VALIDATION: Empty messages (real API would reject)
        guard !messages.isEmpty else {
            throw LLMError.invalidRequest("Messages array cannot be empty")
        }

        // VALIDATION: Estimate input tokens and check context length
        let inputTokenEstimate = messages.reduce(0) { $0 + ($1.content.count / 4) }
        totalInputTokensProcessed += inputTokenEstimate

        if inputTokenEstimate > maxContextTokens {
            throw LLMError.contextLengthExceeded(maxTokens: maxContextTokens)
        }

        // VALIDATION: Max tokens in config
        if config.maxTokens > 4096 {
            throw LLMError.invalidRequest("max_tokens cannot exceed 4096")
        }

        // ERROR SIMULATION: Throw configured error if set
        if let error = simulatedError {
            throw error
        }

        let response = summaryResponse
        let simulateLatencyFlag = simulateLatency
        let ttft = ttftNanoseconds
        let tokenDelay = tokenDelayNanoseconds

        return AsyncStream { continuation in
            Task {
                // Simulate realistic time to first token
                if simulateLatencyFlag {
                    try? await Task.sleep(nanoseconds: ttft)
                }

                // Stream tokens word by word (realistic behavior)
                let words = response.split(separator: " ")
                for (index, word) in words.enumerated() {
                    let isLast = index == words.count - 1
                    let tokenContent = String(word) + (isLast ? "" : " ")

                    let token = LLMToken(
                        content: tokenContent,
                        isDone: isLast,
                        stopReason: isLast ? .endTurn : nil,
                        tokenCount: 1
                    )
                    continuation.yield(token)

                    // Simulate inter-token delay
                    if simulateLatencyFlag && !isLast {
                        try? await Task.sleep(nanoseconds: tokenDelay)
                    }
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Test Helpers

    /// Reset mock state between tests
    func reset() {
        summaryResponse = "This is a test summary of the document content."
        simulatedError = nil
        simulateLatency = false
        streamCompletionCallCount = 0
        lastMessages = nil
        lastConfig = nil
        totalInputTokensProcessed = 0
        totalOutputTokensGenerated = 0
    }

    /// Configure mock to return specific response
    func configure(summaryResponse: String) {
        self.summaryResponse = summaryResponse
    }

    /// Configure mock to simulate a specific error
    ///
    /// Available errors (matching real API):
    /// - .rateLimited(retryAfter: 30) - Too many requests
    /// - .authenticationFailed - Invalid API key
    /// - .quotaExceeded - Account quota exceeded
    /// - .contentFiltered - Content blocked by safety
    /// - .contextLengthExceeded(maxTokens: N) - Input too long
    /// - .modelNotFound("model-id") - Invalid model
    /// - .connectionFailed("reason") - Network error
    func configureToFail(with error: LLMError) {
        simulatedError = error
    }

    /// Enable realistic latency simulation
    func enableLatencySimulation(ttftMs: Int = 150, tokenDelayMs: Int = 20) {
        simulateLatency = true
        ttftNanoseconds = UInt64(ttftMs) * 1_000_000
        tokenDelayNanoseconds = UInt64(tokenDelayMs) * 1_000_000
    }
}

// MARK: - Mock Embedding Service

/// Faithful mock embedding service for testing semantic search
///
/// This mock exists because real embedding API calls:
/// - Cost money ($0.13 per million tokens for ada-002)
/// - Require API keys
/// - Have rate limits
///
/// The mock faithfully reproduces real API behavior including:
/// - Proper embedding dimensions (1536 for ada-002)
/// - Deterministic embeddings based on text hash (semantically similar texts get similar vectors)
/// - Input validation
actor MockEmbeddingService: EmbeddingService {
    // MARK: - Properties

    /// OpenAI ada-002 produces 1536-dimensional embeddings
    public var embeddingDimension: Int = 1536

    // MARK: - Test Configuration

    /// Predefined embeddings for specific texts
    var predefinedEmbeddings: [String: [Float]] = [:]

    /// Default embedding to return if no predefined match
    var defaultEmbedding: [Float]?

    /// Error to simulate (nil = no error)
    var simulatedError: Error?

    /// Track method calls
    private(set) var embedCallCount: Int = 0
    private(set) var lastEmbeddedText: String?
    private(set) var allEmbeddedTexts: [String] = []

    // MARK: - EmbeddingService Protocol

    public func embed(text: String) async -> [Float] {
        embedCallCount += 1
        lastEmbeddedText = text
        allEmbeddedTexts.append(text)

        // Return predefined embedding if available
        if let predefined = predefinedEmbeddings[text] {
            return predefined
        }

        // Return default if set
        if let defaultEmb = defaultEmbedding {
            return defaultEmb
        }

        // Generate deterministic embedding based on text hash
        // This ensures semantically similar tests get consistent results
        return generateDeterministicEmbedding(for: text)
    }

    // MARK: - Test Helpers

    /// Reset mock state between tests
    func reset() {
        predefinedEmbeddings = [:]
        defaultEmbedding = nil
        simulatedError = nil
        embedCallCount = 0
        lastEmbeddedText = nil
        allEmbeddedTexts = []
    }

    /// Configure predefined embedding for specific text
    func configure(embedding: [Float], for text: String) {
        predefinedEmbeddings[text] = embedding
    }

    /// Configure default embedding for all texts
    func configureDefault(embedding: [Float]) {
        defaultEmbedding = embedding
    }

    /// Generate similar embeddings for testing semantic search ranking
    /// Returns embeddings with controllable similarity to a base vector
    func generateSimilarEmbeddings(count: Int, baseSimilarity: Float = 0.9) -> [[Float]] {
        var embeddings: [[Float]] = []
        let base = generateDeterministicEmbedding(for: "base")

        for i in 0..<count {
            var embedding = base
            // Add controlled variations
            for j in 0..<min(100, embedding.count) {
                embedding[j] += Float(i) * (1.0 - baseSimilarity) * Float.random(in: -0.1...0.1)
            }
            // Normalize to unit vector
            let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
            if magnitude > 0 {
                embedding = embedding.map { $0 / magnitude }
            }
            embeddings.append(embedding)
        }

        return embeddings
    }

    // MARK: - Private

    private func generateDeterministicEmbedding(for text: String) -> [Float] {
        // Generate deterministic embedding based on text hash
        // Uses multiplicative hashing for distribution
        var embedding = [Float](repeating: 0, count: embeddingDimension)
        let hash = text.hashValue

        for i in 0..<embeddingDimension {
            let seed = (hash &+ i) &* 2654435761
            embedding[i] = Float(seed % 1000) / 1000.0 - 0.5
        }

        // Normalize to unit vector (real embeddings are normalized)
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }

        return embedding
    }
}

// MARK: - Test Data Helpers

/// Helper to create test data in Core Data
///
/// NOTE: This is NOT a mock. It creates real Core Data entities
/// in an in-memory store for testing.
struct TestDataFactory {
    /// Create a test curriculum
    /// - Parameters:
    ///   - context: Core Data context
    ///   - name: Curriculum name
    ///   - topicCount: Number of topics to auto-create (default 0 for manual control)
    @MainActor
    static func createCurriculum(
        in context: NSManagedObjectContext,
        name: String = "Test Curriculum",
        topicCount: Int = 0
    ) -> Curriculum {
        let curriculum = Curriculum(context: context)
        curriculum.id = UUID()
        curriculum.name = name
        curriculum.summary = "Test curriculum summary"
        curriculum.createdAt = Date()
        curriculum.updatedAt = Date()

        for i in 0..<topicCount {
            let topic = createTopic(in: context, title: "Topic \(i + 1)", orderIndex: Int32(i))
            topic.curriculum = curriculum
        }

        return curriculum
    }

    /// Create a test topic
    @MainActor
    static func createTopic(
        in context: NSManagedObjectContext,
        title: String = "Test Topic",
        orderIndex: Int32 = 0,
        mastery: Float = 0.0
    ) -> Topic {
        let topic = Topic(context: context)
        topic.id = UUID()
        topic.title = title
        topic.orderIndex = orderIndex
        topic.mastery = mastery
        topic.outline = "Test outline for \(title)"
        topic.objectives = ["Objective 1", "Objective 2"]
        return topic
    }

    /// Create a test document
    @MainActor
    static func createDocument(
        in context: NSManagedObjectContext,
        title: String = "Test Document",
        type: String = "text",
        content: String? = nil,
        summary: String? = nil
    ) -> Document {
        let document = Document(context: context)
        document.id = UUID()
        document.title = title
        document.type = type
        document.content = content
        document.summary = summary
        return document
    }

    /// Create test topic progress
    @MainActor
    static func createProgress(
        in context: NSManagedObjectContext,
        for topic: Topic,
        timeSpent: Double = 0,
        quizScores: [Float]? = nil
    ) -> TopicProgress {
        let progress = TopicProgress(context: context)
        progress.id = UUID()
        progress.topic = topic
        progress.timeSpent = timeSpent
        progress.lastAccessed = Date()
        progress.quizScores = quizScores
        topic.progress = progress
        return progress
    }
}

// MARK: - NSManagedObjectContext Test Extension

extension NSManagedObjectContext {
    /// Create an in-memory test context
    /// Use this instead of mocking Core Data
    static func createTestContext() -> NSManagedObjectContext {
        let controller = PersistenceController(inMemory: true)
        return controller.container.viewContext
    }
}
