// UnaMentis - UMCF Parser Tests
// Tests for parsing and importing UMCF curriculum format
//
// Part of Curriculum Layer Testing

import XCTest
import CoreData
@testable import UnaMentis

final class UMCFParserTests: XCTestCase {

    // MARK: - Properties

    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!
    var parser: UMCFParser!

    // MARK: - Setup / Teardown

    @MainActor
    override func setUp() async throws {
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        parser = UMCFParser(persistenceController: persistenceController)
    }

    @MainActor
    override func tearDown() async throws {
        parser = nil
        context = nil
        persistenceController = nil
    }

    // MARK: - Helper Methods

    private func createMinimalUMCF() -> Data {
        let json = """
        {
            "umcf": "1.0",
            "id": {"value": "test-curriculum-001"},
            "title": "Test Curriculum",
            "description": "A test curriculum",
            "version": {"number": "1.0.0"},
            "content": []
        }
        """
        return json.data(using: .utf8)!
    }

    private func createUMCFWithTopics() -> Data {
        let json = """
        {
            "umcf": "1.0",
            "id": {"value": "curriculum-with-topics"},
            "title": "Curriculum With Topics",
            "description": "Has topics",
            "version": {"number": "1.0.0"},
            "content": [
                {
                    "id": {"value": "root-001"},
                    "title": "Root",
                    "type": "course",
                    "children": [
                        {
                            "id": {"value": "topic-001"},
                            "title": "First Topic",
                            "type": "topic",
                            "description": "The first topic",
                            "learningObjectives": [
                                {
                                    "id": {"value": "obj-001"},
                                    "statement": "Understand basics"
                                }
                            ]
                        },
                        {
                            "id": {"value": "topic-002"},
                            "title": "Second Topic",
                            "type": "topic"
                        }
                    ]
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func createUMCFWithTranscript() -> Data {
        let json = """
        {
            "umcf": "1.0",
            "id": {"value": "curriculum-transcript"},
            "title": "Transcript Test",
            "version": {"number": "1.0.0"},
            "content": [
                {
                    "id": {"value": "topic-trans"},
                    "title": "Topic With Transcript",
                    "type": "topic",
                    "transcript": {
                        "segments": [
                            {
                                "id": "seg-001",
                                "type": "introduction",
                                "content": "Welcome to this lesson."
                            },
                            {
                                "id": "seg-002",
                                "type": "explanation",
                                "content": "Let me explain the concept."
                            }
                        ],
                        "totalDuration": "PT10M"
                    }
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func createUMCFWithMedia() -> Data {
        let json = """
        {
            "umcf": "1.0",
            "id": {"value": "curriculum-media"},
            "title": "Media Test",
            "version": {"number": "1.0.0"},
            "content": [
                {
                    "id": {"value": "topic-media"},
                    "title": "Topic With Media",
                    "type": "topic",
                    "media": {
                        "embedded": [
                            {
                                "id": "img-001",
                                "type": "image",
                                "url": "https://example.com/image.png",
                                "title": "Diagram",
                                "alt": "A diagram showing the concept",
                                "dimensions": {"width": 800, "height": 600}
                            }
                        ],
                        "reference": [
                            {
                                "id": "ref-001",
                                "type": "diagram",
                                "title": "Reference Diagram"
                            }
                        ]
                    }
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    // MARK: - Parsing Tests

    func testParse_minimalUMCF_parsesSuccessfully() async throws {
        // Given
        let data = createMinimalUMCF()

        // When
        let document = try await parser.parse(data: data)

        // Then
        XCTAssertEqual(document.umcf, "1.0")
        XCTAssertEqual(document.id.value, "test-curriculum-001")
        XCTAssertEqual(document.title, "Test Curriculum")
        XCTAssertEqual(document.version.number, "1.0.0")
    }

    func testParse_withTopics_parsesContentNodes() async throws {
        // Given
        let data = createUMCFWithTopics()

        // When
        let document = try await parser.parse(data: data)

        // Then
        XCTAssertEqual(document.content.count, 1)
        let root = document.content[0]
        XCTAssertEqual(root.type, "course")
        XCTAssertEqual(root.children?.count, 2)
    }

    func testParse_invalidJSON_throwsError() async {
        // Given
        let invalidData = "not json".data(using: .utf8)!

        // When/Then
        do {
            _ = try await parser.parse(data: invalidData)
            XCTFail("Should have thrown error")
        } catch {
            // Expected - parsing invalid JSON should fail
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testParse_missingRequiredFields_throwsError() async {
        // Given - missing title
        let json = """
        {
            "umcf": "1.0",
            "id": {"value": "test"},
            "version": {"number": "1.0.0"},
            "content": []
        }
        """
        let data = json.data(using: .utf8)!

        // When/Then
        do {
            _ = try await parser.parse(data: data)
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    // MARK: - UMCFIdentifier Tests

    func testUMCFIdentifier_decodesSimpleString() async throws {
        // Given
        let json = """
        {
            "umcf": "1.0",
            "id": "simple-string-id",
            "title": "Test",
            "version": {"number": "1.0.0"},
            "content": []
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let document = try await parser.parse(data: data)

        // Then
        XCTAssertEqual(document.id.value, "simple-string-id")
        XCTAssertNil(document.id.catalog)
    }

    func testUMCFIdentifier_decodesObjectWithCatalog() async throws {
        // Given
        let json = """
        {
            "umcf": "1.0",
            "id": {"catalog": "my-catalog", "value": "object-id"},
            "title": "Test",
            "version": {"number": "1.0.0"},
            "content": []
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let document = try await parser.parse(data: data)

        // Then
        XCTAssertEqual(document.id.value, "object-id")
        XCTAssertEqual(document.id.catalog, "my-catalog")
    }

    // MARK: - Core Data Import Tests

    @MainActor
    func testImportToCoreData_createsNewCurriculum() async throws {
        // Given
        let data = createMinimalUMCF()
        let document = try await parser.parse(data: data)

        // When
        let curriculum = try await parser.importToCoreData(document: document)

        // Then
        XCTAssertNotNil(curriculum)
        XCTAssertEqual(curriculum.name, "Test Curriculum")
        XCTAssertEqual(curriculum.summary, "A test curriculum")
        XCTAssertEqual(curriculum.sourceId, "test-curriculum-001")
    }

    @MainActor
    func testImportToCoreData_createsTopics() async throws {
        // Given
        let data = createUMCFWithTopics()
        let document = try await parser.parse(data: data)

        // When
        let curriculum = try await parser.importToCoreData(document: document)

        // Then
        let topics = curriculum.topics?.array as? [Topic] ?? []
        XCTAssertEqual(topics.count, 2)

        let sortedTopics = topics.sorted { $0.orderIndex < $1.orderIndex }
        XCTAssertEqual(sortedTopics[0].title, "First Topic")
        XCTAssertEqual(sortedTopics[1].title, "Second Topic")
    }

    @MainActor
    func testImportToCoreData_setsTopicObjectives() async throws {
        // Given
        let data = createUMCFWithTopics()
        let document = try await parser.parse(data: data)

        // When
        let curriculum = try await parser.importToCoreData(document: document)

        // Then
        let topics = curriculum.topics?.array as? [Topic] ?? []
        let firstTopic = topics.first { $0.sourceId == "topic-001" }
        XCTAssertNotNil(firstTopic?.objectives)
        XCTAssertTrue(firstTopic?.objectives?.contains("Understand basics") ?? false)
    }

    @MainActor
    func testImportToCoreData_replaceExisting_deletesOld() async throws {
        // Given - import first time
        let data = createMinimalUMCF()
        let document = try await parser.parse(data: data)
        _ = try await parser.importToCoreData(document: document)

        // Modify title for second import
        let json = """
        {
            "umcf": "1.0",
            "id": {"value": "test-curriculum-001"},
            "title": "Updated Curriculum",
            "version": {"number": "2.0.0"},
            "content": []
        }
        """
        let updatedData = json.data(using: .utf8)!
        let updatedDocument = try await parser.parse(data: updatedData)

        // When - import with replace
        let curriculum = try await parser.importToCoreData(
            document: updatedDocument,
            replaceExisting: true
        )

        // Then - only one curriculum exists
        let fetchRequest = Curriculum.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "sourceId == %@", "test-curriculum-001")
        let results = try context.fetch(fetchRequest)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(curriculum.name, "Updated Curriculum")
    }

    @MainActor
    func testImportToCoreData_createsTranscriptDocument() async throws {
        // Given
        let data = createUMCFWithTranscript()
        let document = try await parser.parse(data: data)

        // When
        let curriculum = try await parser.importToCoreData(document: document)

        // Then
        let topics = curriculum.topics?.array as? [Topic] ?? []
        XCTAssertEqual(topics.count, 1)

        let topic = topics.first!
        let documents = topic.documents?.allObjects as? [Document] ?? []
        XCTAssertEqual(documents.count, 1)

        let transcriptDoc = documents.first!
        XCTAssertEqual(transcriptDoc.documentType, DocumentType.transcript)
        XCTAssertNotNil(transcriptDoc.content)
        XCTAssertTrue(transcriptDoc.content?.contains("Welcome to this lesson") ?? false)
    }

    @MainActor
    func testImportToCoreData_decodesTranscriptData() async throws {
        // Given
        let data = createUMCFWithTranscript()
        let document = try await parser.parse(data: data)

        // When
        let curriculum = try await parser.importToCoreData(document: document)

        // Then
        let topic = (curriculum.topics?.array as? [Topic])?.first
        let transcriptDoc = (topic?.documents?.allObjects as? [Document])?.first
        let transcriptData = transcriptDoc?.decodedTranscript()

        XCTAssertNotNil(transcriptData)
        XCTAssertEqual(transcriptData?.segments.count, 2)
        XCTAssertEqual(transcriptData?.totalDuration, "PT10M")
    }

    @MainActor
    func testImportToCoreData_createsVisualAssets() async throws {
        // Given
        let data = createUMCFWithMedia()
        let document = try await parser.parse(data: data)

        // When
        let curriculum = try await parser.importToCoreData(document: document)

        // Then
        let topic = (curriculum.topics?.array as? [Topic])?.first
        let assets = topic?.visualAssets?.allObjects as? [VisualAsset] ?? []

        XCTAssertEqual(assets.count, 2)

        let embeddedAsset = assets.first { !$0.isReference }
        XCTAssertNotNil(embeddedAsset)
        XCTAssertEqual(embeddedAsset?.assetId, "img-001")
        XCTAssertEqual(embeddedAsset?.type, "image")
        XCTAssertEqual(embeddedAsset?.width, 800)
        XCTAssertEqual(embeddedAsset?.height, 600)

        let referenceAsset = assets.first { $0.isReference }
        XCTAssertNotNil(referenceAsset)
        XCTAssertEqual(referenceAsset?.assetId, "ref-001")
    }

    // MARK: - Static Import Tests

    @MainActor
    func testStaticImportDocument_worksFromMainActor() throws {
        // Given
        let json = """
        {
            "umcf": "1.0",
            "id": {"value": "static-import-test"},
            "title": "Static Import Test",
            "version": {"number": "1.0.0"},
            "content": []
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let document = try decoder.decode(UMCFDocument.self, from: data)

        // When
        let curriculum = try UMCFParser.importDocument(
            document,
            persistenceController: persistenceController
        )

        // Then
        XCTAssertEqual(curriculum.name, "Static Import Test")
    }

    @MainActor
    func testStaticImportDocument_selectsSpecificTopics() throws {
        // Given
        let json = """
        {
            "umcf": "1.0",
            "id": {"value": "selective-import"},
            "title": "Selective Import",
            "version": {"number": "1.0.0"},
            "content": [
                {
                    "id": {"value": "topic-a"},
                    "title": "Topic A",
                    "type": "topic"
                },
                {
                    "id": {"value": "topic-b"},
                    "title": "Topic B",
                    "type": "topic"
                },
                {
                    "id": {"value": "topic-c"},
                    "title": "Topic C",
                    "type": "topic"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let document = try JSONDecoder().decode(UMCFDocument.self, from: data)

        // When - only import topic-a and topic-c
        let curriculum = try UMCFParser.importDocument(
            document,
            selectedTopicIds: Set(["topic-a", "topic-c"]),
            persistenceController: persistenceController
        )

        // Then
        let topics = curriculum.topics?.array as? [Topic] ?? []
        XCTAssertEqual(topics.count, 2)

        let topicIds = Set(topics.compactMap { $0.sourceId })
        XCTAssertTrue(topicIds.contains("topic-a"))
        XCTAssertTrue(topicIds.contains("topic-c"))
        XCTAssertFalse(topicIds.contains("topic-b"))
    }

    // MARK: - Pronunciation Guide Tests

    func testParse_withPronunciationGuide_parsesEntries() async throws {
        // Given
        let json = """
        {
            "umcf": "1.0",
            "id": {"value": "pronunciation-test"},
            "title": "Pronunciation Test",
            "version": {"number": "1.0.0"},
            "content": [
                {
                    "id": {"value": "topic-pron"},
                    "title": "Topic",
                    "type": "topic",
                    "transcript": {
                        "segments": [
                            {"id": "seg-1", "type": "text", "content": "The Medici family was powerful."}
                        ],
                        "pronunciationGuide": {
                            "Medici": {
                                "ipa": "/ˈmɛdɪtʃi/",
                                "respelling": "MED-ih-chee",
                                "language": "it"
                            }
                        }
                    }
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!

        // When
        let document = try await parser.parse(data: data)

        // Then
        let topic = document.content.first
        let pronunciation = topic?.transcript?.pronunciationGuide?["Medici"]
        XCTAssertNotNil(pronunciation)
        XCTAssertEqual(pronunciation?.ipa, "/ˈmɛdɪtʃi/")
        XCTAssertEqual(pronunciation?.respelling, "MED-ih-chee")
        XCTAssertEqual(pronunciation?.language, "it")
    }
}
