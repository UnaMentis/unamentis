// VoiceLearn - Curriculum Engine Tests
// TDD tests for CurriculumEngine
//
// Tests written first per TDD methodology

import XCTest
import CoreData
@testable import VoiceLearn

final class CurriculumEngineTests: XCTestCase {

    // MARK: - Properties

    var curriculumEngine: CurriculumEngine!
    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!
    var mockEmbeddingService: MockEmbeddingService!

    // MARK: - Setup / Teardown

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        mockEmbeddingService = MockEmbeddingService()
        curriculumEngine = CurriculumEngine(
            persistenceController: persistenceController,
            embeddingService: mockEmbeddingService
        )
    }

    override func tearDown() async throws {
        curriculumEngine = nil
        context = nil
        persistenceController = nil
        mockEmbeddingService = nil
        try await super.tearDown()
    }

    // MARK: - Curriculum Loading Tests

    @MainActor
    func testLoadCurriculum_loadsCorrectly() async throws {
        // Given
        let curriculum = TestDataFactory.createCurriculum(in: context, name: "Voice AI Course")
        let topic1 = TestDataFactory.createTopic(in: context, title: "Intro")
        topic1.orderIndex = 0
        topic1.curriculum = curriculum
        
        let topic2 = TestDataFactory.createTopic(in: context, title: "Advanced")
        topic2.orderIndex = 1
        topic2.curriculum = curriculum
        
        try context.save()

        // When
        try await curriculumEngine.loadCurriculum(curriculum.id!)

        // Then
        XCTAssertEqual(curriculumEngine.activeCurriculum?.id, curriculum.id)
        XCTAssertEqual(curriculumEngine.activeCurriculum?.name, "Voice AI Course")
        XCTAssertEqual(curriculumEngine.getTopics().count, 2)
    }
    
    @MainActor
    func testLoadCurriculum_throwsIfNotFound() async throws {
        // When/Then
        do {
            try await curriculumEngine.loadCurriculum(UUID())
            XCTFail("Should have thrown error")
        } catch let error as CurriculumError {
            if case .curriculumNotFound = error {
                // Success
            } else {
                XCTFail("Wrong error type")
            }
        }
    }

    // MARK: - Topic Navigation Tests

    @MainActor
    func testStartTopic_setsCurrentTopic() async throws {
        // Given
        let curriculum = TestDataFactory.createCurriculum(in: context)
        let topic = TestDataFactory.createTopic(in: context)
        topic.curriculum = curriculum
        try context.save()
        
        try await curriculumEngine.loadCurriculum(curriculum.id!)

        // When
        try await curriculumEngine.startTopic(topic)

        // Then
        XCTAssertEqual(curriculumEngine.currentTopic?.id, topic.id)
        XCTAssertNotNil(topic.progress) // Should auto-create progress
    }
    
    @MainActor
    func testNavigation_nextAndPrevious() async throws {
        // Given
        let curriculum = TestDataFactory.createCurriculum(in: context)
        let t1 = TestDataFactory.createTopic(in: context, title: "1"); t1.orderIndex = 0; t1.curriculum = curriculum
        let t2 = TestDataFactory.createTopic(in: context, title: "2"); t2.orderIndex = 1; t2.curriculum = curriculum
        let t3 = TestDataFactory.createTopic(in: context, title: "3"); t3.orderIndex = 2; t3.curriculum = curriculum
        try context.save()
        
        try await curriculumEngine.loadCurriculum(curriculum.id!)
        
        // When - Start T1
        try await curriculumEngine.startTopic(t1)
        
        // Then - Next should be T2
        let next1 = await curriculumEngine.getNextTopic()
        XCTAssertEqual(next1?.id, t2.id)
        
        // When - Move to T2
        try await curriculumEngine.startTopic(t2)
        
        // Then - Prev is T1, Next is T3
        let prev2 = await curriculumEngine.getPreviousTopic()
        let next2 = await curriculumEngine.getNextTopic()
        XCTAssertEqual(prev2?.id, t1.id)
        XCTAssertEqual(next2?.id, t3.id)
        
        // When - Move to T3
        try await curriculumEngine.startTopic(t3)
        
        // Then - Next is nil
        let next3 = await curriculumEngine.getNextTopic()
        XCTAssertNil(next3)
    }

    // MARK: - Context Generation Tests

    @MainActor
    func testGenerateContext_includesTitleAndOutline() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context, title: "Swift Basics")
        topic.outline = "- Variables\n- Loops"
        topic.objectives = ["Learn 'let'", "Learn 'var'"]
        try context.save()

        // When
        let contextString = await curriculumEngine.generateContext(for: topic)

        // Then
        XCTAssertTrue(contextString.contains("Swift Basics"))
        XCTAssertTrue(contextString.contains("- Variables"))
        XCTAssertTrue(contextString.contains("Learn 'let'"))
    }
    
    @MainActor
    func testGenerateContext_includesReferences() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let doc = TestDataFactory.createDocument(in: context, title: "Swift Guide", summary: "A guide about Swift.")
        doc.topic = topic
        try context.save()

        // When
        let contextString = await curriculumEngine.generateContext(for: topic)

        // Then
        XCTAssertTrue(contextString.contains("REFERENCE: Swift Guide"))
        XCTAssertTrue(contextString.contains("A guide about Swift."))
     }

    // MARK: - Semantic Search Tests

    @MainActor
    func testSemanticSearch_callsEmbeddingService() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let doc = TestDataFactory.createDocument(in: context)
        doc.topic = topic
        
        // Create chunk in document (manually setting bytes)
        let chunk = DocumentChunk(id: UUID(), documentId: doc.id!, text: "Hello", embedding: [0.1, 0.2], chunkIndex: 0)
        doc.embedding = try JSONEncoder().encode([chunk])
        
        try context.save()
        
        mockEmbeddingService.mockEmbedding = [0.1, 0.2] // Perfect match

        // When
        let contextString = await curriculumEngine.generateContextForQuery(query: "Hello", topic: topic)

        // Then
        XCTAssertTrue(mockEmbeddingService.embedCalled)
        XCTAssertTrue(contextString.contains("Hello"))
    }
    
    // MARK: - Progress Tracking Tests
    
    @MainActor
    func testUpdateProgress_updatesTimeSpent() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        try await curriculumEngine.startTopic(topic) // creates progress
        
        // When
        try await curriculumEngine.updateProgress(topic: topic, timeSpent: 100, conceptsCovered: [])
        
        // Then
        XCTAssertEqual(topic.progress?.timeSpent, 100)
    }
    
    @MainActor
    func testCompleteTopic_updatesStatus() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        try await curriculumEngine.startTopic(topic)
        
        // When
        try await curriculumEngine.completeTopic(topic, masteryLevel: 0.9)
        
        // Then
        XCTAssertEqual(topic.mastery, 0.9)
        // Check status logic
        XCTAssertEqual(topic.status, .completed)
    }
}

// MARK: - Mocks

actor MockEmbeddingService: EmbeddingService {
    var embedCalled = false
    var mockEmbedding: [Float] = [0.1, 0.1]
    
    func embed(text: String) async -> [Float] {
        embedCalled = true
        return mockEmbedding
    }
    
    var embeddingDimension: Int { return 2 }
}

// Verify TestDataFactory Extensions for Curriculum
extension TestDataFactory {
    @discardableResult
    static func createCurriculum(in context: NSManagedObjectContext, name: String = "Test Curriculum") -> Curriculum {
        let curriculum = Curriculum(context: context)
        curriculum.id = UUID()
        curriculum.name = name
        curriculum.createdAt = Date()
        curriculum.updatedAt = Date()
        return curriculum
    }
    
    @discardableResult
    static func createDocument(in context: NSManagedObjectContext, title: String = "Doc", summary: String? = nil) -> Document {
        let doc = Document(context: context)
        doc.id = UUID()
        doc.title = title
        doc.summary = summary
        doc.type = "text"
        return doc
    }
}
