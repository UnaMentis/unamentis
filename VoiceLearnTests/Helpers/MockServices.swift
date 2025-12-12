// VoiceLearn - Mock Services for Testing
// Simple actor-based mocks for external dependencies
//
// Following project testing philosophy: "Real implementations, no mocks"
// These mocks only exist for truly external dependencies (LLM, Embeddings)

import Foundation
import CoreData
@testable import VoiceLearn

// MARK: - Mock LLM Service

/// Mock LLM service for testing document summarization
actor MockLLMService: LLMService {
    // MARK: - Properties

    public var metrics: LLMMetrics = LLMMetrics(
        medianTTFT: 0.1,
        p99TTFT: 0.2,
        totalInputTokens: 0,
        totalOutputTokens: 0
    )

    public var costPerInputToken: Decimal = 0.00001
    public var costPerOutputToken: Decimal = 0.00003

    // MARK: - Test Configuration

    /// Predefined response for summary generation
    var summaryResponse: String = "This is a test summary of the document content."

    /// Whether to simulate a failure
    var shouldFail: Bool = false

    /// Error to throw when shouldFail is true
    var errorToThrow: LLMError = .connectionFailed("Mock failure")

    /// Track method calls
    var streamCompletionCallCount: Int = 0
    var lastMessages: [LLMMessage]?
    var lastConfig: LLMConfig?

    // MARK: - LLMService Protocol

    public func streamCompletion(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> AsyncStream<LLMToken> {
        streamCompletionCallCount += 1
        lastMessages = messages
        lastConfig = config

        if shouldFail {
            throw errorToThrow
        }

        return AsyncStream { continuation in
            // Emit summary as tokens
            let words = summaryResponse.split(separator: " ")
            for (index, word) in words.enumerated() {
                let isLast = index == words.count - 1
                let token = LLMToken(
                    content: String(word) + (isLast ? "" : " "),
                    isDone: isLast,
                    stopReason: isLast ? .endTurn : nil,
                    tokenCount: 1
                )
                continuation.yield(token)
            }
            continuation.finish()
        }
    }

    // MARK: - Test Helpers

    /// Reset mock state
    func reset() {
        summaryResponse = "This is a test summary of the document content."
        shouldFail = false
        streamCompletionCallCount = 0
        lastMessages = nil
        lastConfig = nil
    }

    /// Configure mock to return specific summary
    func configure(summaryResponse: String) {
        self.summaryResponse = summaryResponse
    }

    /// Configure mock to fail
    func configureToFail(with error: LLMError) {
        shouldFail = true
        errorToThrow = error
    }
}

// MARK: - Mock Embedding Service

/// Mock embedding service for testing semantic search
actor MockEmbeddingService: EmbeddingService {
    // MARK: - Properties

    public var embeddingDimension: Int = 1536

    // MARK: - Test Configuration

    /// Predefined embeddings to return (maps text to embedding)
    var predefinedEmbeddings: [String: [Float]] = [:]

    /// Default embedding to return if no predefined match
    var defaultEmbedding: [Float]?

    /// Track method calls
    var embedCallCount: Int = 0
    var lastEmbeddedText: String?

    // MARK: - EmbeddingService Protocol

    public func embed(text: String) async -> [Float] {
        embedCallCount += 1
        lastEmbeddedText = text

        // Return predefined embedding if available
        if let predefined = predefinedEmbeddings[text] {
            return predefined
        }

        // Return default if set
        if let defaultEmb = defaultEmbedding {
            return defaultEmb
        }

        // Generate deterministic embedding based on text hash
        return generateDeterministicEmbedding(for: text)
    }

    // MARK: - Test Helpers

    /// Reset mock state
    func reset() {
        predefinedEmbeddings = [:]
        defaultEmbedding = nil
        embedCallCount = 0
        lastEmbeddedText = nil
    }

    /// Configure predefined embedding for specific text
    func configure(embedding: [Float], for text: String) {
        predefinedEmbeddings[text] = embedding
    }

    /// Configure default embedding
    func configureDefault(embedding: [Float]) {
        defaultEmbedding = embedding
    }

    /// Generate similar embeddings for testing semantic search
    func generateSimilarEmbeddings(count: Int, baseSimilarity: Float = 0.9) -> [[Float]] {
        var embeddings: [[Float]] = []
        let base = generateDeterministicEmbedding(for: "base")

        for i in 0..<count {
            var embedding = base
            // Add small variations
            for j in 0..<min(100, embedding.count) {
                embedding[j] += Float(i) * (1.0 - baseSimilarity) * Float.random(in: -0.1...0.1)
            }
            // Normalize
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
        var embedding = [Float](repeating: 0, count: embeddingDimension)
        let hash = text.hashValue

        for i in 0..<embeddingDimension {
            // Use hash to seed pseudo-random values
            let seed = (hash &+ i) &* 2654435761
            embedding[i] = Float(seed % 1000) / 1000.0 - 0.5
        }

        // Normalize to unit vector
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }

        return embedding
    }
}

// MARK: - Mock Telemetry Engine

/// Mock telemetry engine for testing event recording
class MockTelemetryEngine: @unchecked Sendable {
    // MARK: - Properties

    /// Track recorded events
    private(set) var recordedEvents: [TelemetryEvent] = []

    /// Track recorded latencies
    private(set) var recordedLatencies: [(LatencyType, TimeInterval)] = []

    /// Track recorded costs
    private(set) var recordedCosts: [(CostType, Decimal, String)] = []

    /// Track method calls
    var recordEventWasCalled: Bool { !recordedEvents.isEmpty }
    var recordLatencyWasCalled: Bool { !recordedLatencies.isEmpty }
    var recordCostWasCalled: Bool { !recordedCosts.isEmpty }

    // MARK: - Mock Methods

    func recordEvent(_ event: TelemetryEvent) {
        recordedEvents.append(event)
    }

    func recordLatency(_ type: LatencyType, _ value: TimeInterval) {
        recordedLatencies.append((type, value))
    }

    func recordCost(_ type: CostType, amount: Decimal, description: String) {
        recordedCosts.append((type, amount, description))
    }

    // MARK: - Test Helpers

    /// Reset mock state
    func reset() {
        recordedEvents.removeAll()
        recordedLatencies.removeAll()
        recordedCosts.removeAll()
    }

    /// Check if specific event type was recorded
    func hasEvent(matching predicate: (TelemetryEvent) -> Bool) -> Bool {
        recordedEvents.contains(where: predicate)
    }
}

// MARK: - Test Data Helpers

/// Helper to create test curriculum data
struct TestDataFactory {
    /// Create a test curriculum in the given context
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

    /// Create a test topic in the given context
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

    /// Create a test document in the given context
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

    /// Create a test topic progress in the given context
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
    /// Convenience to create in-memory test context
    static func createTestContext() -> NSManagedObjectContext {
        let controller = PersistenceController(inMemory: true)
        return controller.container.viewContext
    }
}
