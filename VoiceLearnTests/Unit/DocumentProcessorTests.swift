// VoiceLearn - Document Processor Tests
// TDD tests for DocumentProcessor
//
// Tests written first per TDD methodology

import XCTest
import CoreData
@testable import VoiceLearn

final class DocumentProcessorTests: XCTestCase {

    // MARK: - Properties

    var documentProcessor: DocumentProcessor!
    var mockLLMService: MockLLMService!
    var mockEmbeddingService: MockEmbeddingService!
    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!

    // MARK: - Setup / Teardown

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        mockLLMService = MockLLMService()
        mockEmbeddingService = MockEmbeddingService()
        documentProcessor = DocumentProcessor(
            llmService: mockLLMService,
            embeddingService: mockEmbeddingService
        )
    }

    override func tearDown() async throws {
        documentProcessor = nil
        mockLLMService = nil
        mockEmbeddingService = nil
        context = nil
        persistenceController = nil
        try await super.tearDown()
    }

    // MARK: - Text Extraction Tests

    func testExtractText_fromPlainText() async throws {
        // Given
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.txt")
        let content = "Hello World"
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        
        // When
        let extracted = try await documentProcessor.extractText(from: tempURL, type: .text)
        
        // Then
        XCTAssertEqual(extracted, "Hello World")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    func testExtractText_throwsInternalErrorForNonExistentFile() async throws {
        // Given
        let url = URL(fileURLWithPath: "/non/existent/file.txt")
        
        // When/Then
        do {
            _ = try await documentProcessor.extractText(from: url, type: .text)
            XCTFail("Should throw")
        } catch let error as DocumentError {
            if case .fileNotFound = error {
                // Success
            } else {
                 XCTFail("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - Summary Generation Tests

    @MainActor
    func testProcessDocument_generatesSummary() async throws {
        // Given
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("summary_test.txt")
        try "Content to summarize".write(to: tempURL, atomically: true, encoding: .utf8)
        
        let doc = TestDataFactory.createDocument(in: context)
        doc.sourceURL = tempURL
        doc.type = "text"
        
        mockLLMService.mockCompletion = "This is a summary."

        // When
        try await documentProcessor.processDocument(doc)

        // Then
        XCTAssertEqual(doc.content, "Content to summarize")
        XCTAssertEqual(doc.summary, "This is a summary.")
        XCTAssertTrue(mockLLMService.streamCompletionCalled)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Chunking Tests

    func testChunkText_splitsCorrectly() async {
        // Given
        let text = "One Two Three Four Five"
        
        // When - simple split by size not strictly by words in this implementation check
        // The implementation splits by words and accumulates.
        // "One Two " (8 chars including space)
        // With maxChunkSize 10:
        // "One Two" -> 7 chars. Next is "Three" -> "One Two Three" is 13 chars > 10.
        // So Chunk 1: "One Two"
        // Chunk 2: "Three " -> "Three Four" -> 10 chars. OK. Next "Five" -> "Three Four Five" -> 15.
        // So Chunk 2: "Three Four"
        // Chunk 3: "Five"
        
        let chunks = await documentProcessor.chunkText(text, maxChunkSize: 10)
        
        // Then
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].text, "One Two")
        XCTAssertEqual(chunks[1].text, "Three Four")
        XCTAssertEqual(chunks[2].text, "Five")
    }

    // MARK: - Embedding Tests
    
    @MainActor
    func testProcessDocument_createsEmbeddings() async throws {
        // Given
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("embed_test.txt")
        try "One Two Three".write(to: tempURL, atomically: true, encoding: .utf8)
        
        let doc = TestDataFactory.createDocument(in: context)
        doc.sourceURL = tempURL
        doc.type = "text"
        
        mockEmbeddingService.mockEmbedding = [0.1, 0.2]

        // When
        try await documentProcessor.processDocument(doc)

        // Then
        XCTAssertNotNil(doc.embedding)
        let chunks = doc.decodedChunks()
        XCTAssertNotNil(chunks)
        XCTAssertFalse(chunks!.isEmpty)
        XCTAssertEqual(chunks![0].embedding, [0.1, 0.2])
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }
}

// MARK: - Mocks

actor MockLLMService: LLMService {
    var metrics: LLMMetrics = LLMMetrics(medianTTFT: 0, p99TTFT: 0, totalInputTokens: 0, totalOutputTokens: 0)
    var costPerInputToken: Decimal = 0
    var costPerOutputToken: Decimal = 0
    
    var streamCompletionCalled = false
    var mockCompletion = "Mock completion"
    
    func streamCompletion(messages: [LLMMessage], config: LLMConfig) async throws -> AsyncStream<LLMToken> {
        streamCompletionCalled = true
        let content = mockCompletion
        
        return AsyncStream { continuation in
            continuation.yield(LLMToken(content: content, isDone: true))
            continuation.finish()
        }
    }
}
