// UnaMentis - TodoManager Tests
// Comprehensive tests for TodoManager actor
//
// Part of Todo System Testing

import XCTest
import CoreData
@testable import UnaMentis

final class TodoManagerTests: XCTestCase {

    private var persistenceController: PersistenceController!
    private var todoManager: TodoManager!

    @MainActor
    private func setUpTestEnvironment() {
        persistenceController = PersistenceController(inMemory: true)
        todoManager = TodoManager(persistenceController: persistenceController)
    }

    override func tearDown() {
        persistenceController = nil
        todoManager = nil
        super.tearDown()
    }

    // MARK: - Create Item Tests

    @MainActor
    func testCreateItem_withValidData_createsItem() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(
            title: "Test Item",
            type: .learningTarget,
            source: .manual,
            notes: "Test notes"
        )

        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.title, "Test Item")
        XCTAssertEqual(item.itemType, .learningTarget)
        XCTAssertEqual(item.source, .manual)
        XCTAssertEqual(item.notes, "Test notes")
        XCTAssertEqual(item.status, .pending)
    }

    @MainActor
    func testCreateItem_withoutNotes_createsItemWithNilNotes() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(
            title: "No Notes Item",
            type: .curriculum
        )

        XCTAssertNil(item.notes)
    }

    @MainActor
    func testCreateItem_assignsIncrementingPriority() throws {
        setUpTestEnvironment()

        let item1 = try todoManager.createItem(title: "First", type: .topic)
        let item2 = try todoManager.createItem(title: "Second", type: .topic)
        let item3 = try todoManager.createItem(title: "Third", type: .topic)

        XCTAssertEqual(item1.priority, 0)
        XCTAssertEqual(item2.priority, 1)
        XCTAssertEqual(item3.priority, 2)
    }

    @MainActor
    func testCreateItem_setsCreatedAtAndUpdatedAt() throws {
        setUpTestEnvironment()
        let beforeCreate = Date()

        let item = try todoManager.createItem(title: "Dated Item", type: .module)

        XCTAssertNotNil(item.createdAt)
        XCTAssertNotNil(item.updatedAt)
        XCTAssertGreaterThanOrEqual(item.createdAt!, beforeCreate)
    }

    // MARK: - Create Curriculum Item Tests

    @MainActor
    func testCreateCurriculumItem_withCurriculumGranularity() throws {
        setUpTestEnvironment()
        let curriculumId = UUID()

        let item = try todoManager.createCurriculumItem(
            title: "Study Calculus",
            curriculumId: curriculumId,
            granularity: "curriculum"
        )

        XCTAssertEqual(item.itemType, .curriculum)
        XCTAssertEqual(item.curriculumId, curriculumId)
        XCTAssertEqual(item.granularity, "curriculum")
    }

    @MainActor
    func testCreateCurriculumItem_withModuleGranularity() throws {
        setUpTestEnvironment()
        let curriculumId = UUID()

        let item = try todoManager.createCurriculumItem(
            title: "Study Module 1",
            curriculumId: curriculumId,
            granularity: "module"
        )

        XCTAssertEqual(item.itemType, .module)
    }

    @MainActor
    func testCreateCurriculumItem_withTopicGranularity() throws {
        setUpTestEnvironment()
        let curriculumId = UUID()
        let topicId = UUID()

        let item = try todoManager.createCurriculumItem(
            title: "Study Derivatives",
            curriculumId: curriculumId,
            topicId: topicId,
            granularity: "topic"
        )

        XCTAssertEqual(item.itemType, .topic)
        XCTAssertEqual(item.topicId, topicId)
    }

    @MainActor
    func testCreateCurriculumItem_withInvalidGranularity_defaultsToCurriculum() throws {
        setUpTestEnvironment()

        let item = try todoManager.createCurriculumItem(
            title: "Invalid Granularity",
            curriculumId: UUID(),
            granularity: "invalid"
        )

        XCTAssertEqual(item.itemType, .curriculum)
    }

    // MARK: - Create Auto-Resume Item Tests

    @MainActor
    func testCreateAutoResumeItem_createsNewItem() throws {
        setUpTestEnvironment()
        let topicId = UUID()
        let contextData = "test context".data(using: .utf8)

        let item = try todoManager.createAutoResumeItem(
            title: "Continue: Calculus",
            topicId: topicId,
            segmentIndex: 5,
            conversationContext: contextData
        )

        XCTAssertEqual(item.itemType, .autoResume)
        XCTAssertEqual(item.source, .autoResume)
        XCTAssertEqual(item.resumeTopicId, topicId)
        XCTAssertEqual(item.resumeSegmentIndex, 5)
        XCTAssertEqual(item.resumeConversationContext, contextData)
        XCTAssertEqual(item.priority, 0, "Auto-resume should have highest priority")
    }

    @MainActor
    func testCreateAutoResumeItem_updatesExistingForSameTopic() throws {
        setUpTestEnvironment()
        let topicId = UUID()

        let firstItem = try todoManager.createAutoResumeItem(
            title: "Continue: Calculus",
            topicId: topicId,
            segmentIndex: 5,
            conversationContext: nil
        )

        let secondItem = try todoManager.createAutoResumeItem(
            title: "Continue: Calculus (updated)",
            topicId: topicId,
            segmentIndex: 10,
            conversationContext: nil
        )

        XCTAssertEqual(firstItem.id, secondItem.id)
        XCTAssertEqual(secondItem.resumeSegmentIndex, 10)
    }

    @MainActor
    func testCreateAutoResumeItem_shiftsExistingPriorities() throws {
        setUpTestEnvironment()

        let item1 = try todoManager.createItem(title: "Regular 1", type: .topic)
        let item2 = try todoManager.createItem(title: "Regular 2", type: .topic)

        _ = try todoManager.createAutoResumeItem(
            title: "Continue",
            topicId: UUID(),
            segmentIndex: 0,
            conversationContext: nil
        )

        let items = try todoManager.fetchActiveItems()
        let regularItems = items.filter { $0.itemType != .autoResume }

        XCTAssertEqual(items.first?.itemType, .autoResume)

        for item in regularItems {
            XCTAssertGreaterThan(item.priority, 0)
        }
    }

    // MARK: - Create Reinforcement Item Tests

    @MainActor
    func testCreateReinforcementItem_createsWithSessionId() throws {
        setUpTestEnvironment()
        let sessionId = UUID()

        let item = try todoManager.createReinforcementItem(
            title: "Review: Integration techniques",
            notes: "User struggled with u-substitution",
            sessionId: sessionId
        )

        XCTAssertEqual(item.itemType, .reinforcement)
        XCTAssertEqual(item.source, .reinforcement)
        XCTAssertEqual(item.sourceSessionId, sessionId)
        XCTAssertEqual(item.notes, "User struggled with u-substitution")
    }

    // MARK: - Fetch Active Items Tests

    @MainActor
    func testFetchActiveItems_excludesCompletedAndArchived() throws {
        setUpTestEnvironment()

        let activeItem = try todoManager.createItem(title: "Active", type: .topic)
        let completedItem = try todoManager.createItem(title: "Completed", type: .topic)
        let archivedItem = try todoManager.createItem(title: "Archived", type: .topic)

        try todoManager.completeItem(completedItem)
        try todoManager.archiveItem(archivedItem)

        let activeItems = try todoManager.fetchActiveItems()

        XCTAssertEqual(activeItems.count, 1)
        XCTAssertEqual(activeItems.first?.id, activeItem.id)
    }

    @MainActor
    func testFetchActiveItems_sortsByPriority() throws {
        setUpTestEnvironment()

        _ = try todoManager.createItem(title: "Third", type: .topic)
        _ = try todoManager.createItem(title: "Fourth", type: .topic)

        _ = try todoManager.createAutoResumeItem(
            title: "First (auto-resume)",
            topicId: UUID(),
            segmentIndex: 0,
            conversationContext: nil
        )

        let items = try todoManager.fetchActiveItems()

        XCTAssertEqual(items.first?.title, "First (auto-resume)")
        for i in 0..<(items.count - 1) {
            XCTAssertLessThanOrEqual(items[i].priority, items[i + 1].priority)
        }
    }

    @MainActor
    func testFetchActiveItems_emptyDatabase_returnsEmptyArray() throws {
        setUpTestEnvironment()

        let items = try todoManager.fetchActiveItems()

        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Fetch Completed Items Tests

    @MainActor
    func testFetchCompletedItems_returnsOnlyCompleted() throws {
        setUpTestEnvironment()

        let pendingItem = try todoManager.createItem(title: "Pending", type: .topic)
        let completedItem = try todoManager.createItem(title: "Completed", type: .topic)

        try todoManager.completeItem(completedItem)

        let items = try todoManager.fetchCompletedItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, completedItem.id)
    }

    // MARK: - Fetch Archived Items Tests

    @MainActor
    func testFetchArchivedItems_returnsOnlyArchived() throws {
        setUpTestEnvironment()

        let activeItem = try todoManager.createItem(title: "Active", type: .topic)
        let archivedItem = try todoManager.createItem(title: "Archived", type: .topic)

        try todoManager.archiveItem(archivedItem)

        let items = try todoManager.fetchArchivedItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, archivedItem.id)
    }

    // MARK: - Fetch Items By Type Tests

    @MainActor
    func testFetchItemsByType_returnsOnlyMatchingType() throws {
        setUpTestEnvironment()

        _ = try todoManager.createItem(title: "Topic 1", type: .topic)
        _ = try todoManager.createItem(title: "Topic 2", type: .topic)
        _ = try todoManager.createItem(title: "Learning Goal", type: .learningTarget)

        let topics = try todoManager.fetchItems(ofType: .topic)
        let learningTargets = try todoManager.fetchItems(ofType: .learningTarget)

        XCTAssertEqual(topics.count, 2)
        XCTAssertEqual(learningTargets.count, 1)
    }

    // MARK: - Fetch Item By ID Tests

    @MainActor
    func testFetchItemById_existingItem_returnsItem() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "Find Me", type: .topic)

        let found = try todoManager.fetchItem(id: item.id!)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "Find Me")
    }

    @MainActor
    func testFetchItemById_nonExistentId_returnsNil() throws {
        setUpTestEnvironment()

        let found = try todoManager.fetchItem(id: UUID())

        XCTAssertNil(found)
    }

    // MARK: - Update Status Tests

    @MainActor
    func testUpdateStatus_changesToInProgress() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "Test", type: .topic)
        XCTAssertEqual(item.status, .pending)

        try todoManager.updateStatus(item: item, status: .inProgress)

        XCTAssertEqual(item.status, .inProgress)
    }

    @MainActor
    func testUpdateStatus_updatesUpdatedAt() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "Test", type: .topic)
        let originalUpdatedAt = item.updatedAt!

        // Small delay to ensure different timestamps
        Thread.sleep(forTimeInterval: 0.01)

        try todoManager.updateStatus(item: item, status: .inProgress)

        XCTAssertGreaterThan(item.updatedAt!, originalUpdatedAt)
    }

    // MARK: - Complete Item Tests

    @MainActor
    func testCompleteItem_setsStatusToCompleted() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "To Complete", type: .topic)

        try todoManager.completeItem(item)

        XCTAssertEqual(item.status, .completed)
    }

    // MARK: - Archive Item Tests

    @MainActor
    func testArchiveItem_setsStatusToArchived() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "To Archive", type: .topic)

        try todoManager.archiveItem(item)

        XCTAssertEqual(item.status, .archived)
    }

    // MARK: - Restore Item Tests

    @MainActor
    func testRestoreItem_setsStatusToPendingAndClearsArchivedAt() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "To Restore", type: .topic)
        try todoManager.archiveItem(item)
        XCTAssertEqual(item.status, .archived)

        try todoManager.restoreItem(item)

        XCTAssertEqual(item.status, .pending)
        XCTAssertNil(item.archivedAt)
    }

    // MARK: - Update Item Tests

    @MainActor
    func testUpdateItem_changesTitle() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "Original", type: .topic)

        try todoManager.updateItem(item: item, title: "Updated", notes: nil)

        XCTAssertEqual(item.title, "Updated")
    }

    @MainActor
    func testUpdateItem_changesNotes() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "Test", type: .topic)

        try todoManager.updateItem(item: item, title: nil, notes: "New notes")

        XCTAssertEqual(item.notes, "New notes")
    }

    @MainActor
    func testUpdateItem_nilTitlePreservesOriginal() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "Original", type: .topic)

        try todoManager.updateItem(item: item, title: nil, notes: "Notes only")

        XCTAssertEqual(item.title, "Original")
        XCTAssertEqual(item.notes, "Notes only")
    }

    // MARK: - Move Item Tests

    @MainActor
    func testMoveItem_toHigherIndex() throws {
        setUpTestEnvironment()

        let item0 = try todoManager.createItem(title: "Item 0", type: .topic)
        let item1 = try todoManager.createItem(title: "Item 1", type: .topic)
        let item2 = try todoManager.createItem(title: "Item 2", type: .topic)

        XCTAssertEqual(item0.priority, 0)
        XCTAssertEqual(item1.priority, 1)
        XCTAssertEqual(item2.priority, 2)

        try todoManager.moveItem(item0, to: 2)

        XCTAssertEqual(item0.priority, 2)
        XCTAssertEqual(item1.priority, 0)
        XCTAssertEqual(item2.priority, 1)
    }

    @MainActor
    func testMoveItem_toLowerIndex() throws {
        setUpTestEnvironment()

        let item0 = try todoManager.createItem(title: "Item 0", type: .topic)
        let item1 = try todoManager.createItem(title: "Item 1", type: .topic)
        let item2 = try todoManager.createItem(title: "Item 2", type: .topic)

        try todoManager.moveItem(item2, to: 0)

        XCTAssertEqual(item2.priority, 0)
        XCTAssertEqual(item0.priority, 1)
        XCTAssertEqual(item1.priority, 2)
    }

    @MainActor
    func testMoveItem_invalidIndex_doesNothing() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "Item", type: .topic)
        let originalPriority = item.priority

        try todoManager.moveItem(item, to: 100)

        XCTAssertEqual(item.priority, originalPriority)
    }

    // MARK: - Reorder Items Tests

    @MainActor
    func testReorderItems_setsNewPriorities() throws {
        setUpTestEnvironment()

        let item0 = try todoManager.createItem(title: "A", type: .topic)
        let item1 = try todoManager.createItem(title: "B", type: .topic)
        let item2 = try todoManager.createItem(title: "C", type: .topic)

        try todoManager.reorderItems(orderedIds: [item2.id!, item0.id!, item1.id!])

        XCTAssertEqual(item2.priority, 0)
        XCTAssertEqual(item0.priority, 1)
        XCTAssertEqual(item1.priority, 2)
    }

    // MARK: - Delete Item Tests

    @MainActor
    func testDeleteItem_removesFromDatabase() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "To Delete", type: .topic)
        let itemId = item.id!

        try todoManager.deleteItem(item)

        let found = try todoManager.fetchItem(id: itemId)
        XCTAssertNil(found)
    }

    // MARK: - Delete All Completed Tests

    @MainActor
    func testDeleteAllCompleted_removesOnlyCompleted() throws {
        setUpTestEnvironment()

        let activeItem = try todoManager.createItem(title: "Active", type: .topic)
        let completedItem1 = try todoManager.createItem(title: "Completed 1", type: .topic)
        let completedItem2 = try todoManager.createItem(title: "Completed 2", type: .topic)

        try todoManager.completeItem(completedItem1)
        try todoManager.completeItem(completedItem2)

        try todoManager.deleteAllCompleted()

        let activeItems = try todoManager.fetchActiveItems()
        let completedItems = try todoManager.fetchCompletedItems()

        XCTAssertEqual(activeItems.count, 1)
        XCTAssertEqual(activeItems.first?.id, activeItem.id)
        XCTAssertTrue(completedItems.isEmpty)
    }

    // MARK: - Clear Auto-Resume Tests

    @MainActor
    func testClearAutoResume_removesItemForTopic() throws {
        setUpTestEnvironment()
        let topicId = UUID()

        let autoResumeItem = try todoManager.createAutoResumeItem(
            title: "Continue",
            topicId: topicId,
            segmentIndex: 5,
            conversationContext: nil
        )
        let autoResumeId = autoResumeItem.id!

        try todoManager.clearAutoResume(for: topicId)

        let found = try todoManager.fetchItem(id: autoResumeId)
        XCTAssertNil(found)
    }

    @MainActor
    func testClearAutoResume_nonExistentTopic_doesNotThrow() throws {
        setUpTestEnvironment()

        try todoManager.clearAutoResume(for: UUID())
    }

    // MARK: - Get Resume Context Tests

    @MainActor
    func testGetResumeContext_existingAutoResume_returnsContext() throws {
        setUpTestEnvironment()
        let topicId = UUID()
        let contextData = "context data".data(using: .utf8)

        _ = try todoManager.createAutoResumeItem(
            title: "Continue",
            topicId: topicId,
            segmentIndex: 7,
            conversationContext: contextData
        )

        let context = try todoManager.getResumeContext(for: topicId)

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.segmentIndex, 7)
        XCTAssertEqual(context?.context, contextData)
    }

    @MainActor
    func testGetResumeContext_noAutoResume_returnsNil() throws {
        setUpTestEnvironment()

        let context = try todoManager.getResumeContext(for: UUID())

        XCTAssertNil(context)
    }

    // MARK: - Update Suggested Curricula Tests

    @MainActor
    func testUpdateSuggestedCurricula_learningTarget_updatesSuggestions() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(
            title: "Learn Calculus",
            type: .learningTarget
        )
        let suggestions = ["curriculum-1", "curriculum-2", "curriculum-3"]

        try todoManager.updateSuggestedCurricula(item: item, curriculumIds: suggestions)

        XCTAssertEqual(item.suggestedCurriculumIds, suggestions)
    }

    @MainActor
    func testUpdateSuggestedCurricula_nonLearningTarget_doesNotUpdate() throws {
        setUpTestEnvironment()

        let item = try todoManager.createItem(title: "Topic", type: .topic)

        try todoManager.updateSuggestedCurricula(item: item, curriculumIds: ["test"])

        XCTAssertNil(item.suggestedCurriculumIds)
    }
}

// MARK: - TodoError Tests

final class TodoErrorTests: XCTestCase {

    func testItemNotFound_errorDescription() {
        let id = UUID()
        let error = TodoError.itemNotFound(id)
        XCTAssertEqual(error.errorDescription, "To-do item not found: \(id)")
    }

    func testInvalidOperation_errorDescription() {
        let error = TodoError.invalidOperation("Test message")
        XCTAssertEqual(error.errorDescription, "Invalid operation: Test message")
    }

    func testSaveFailed_errorDescription() {
        let error = TodoError.saveFailed("Database error")
        XCTAssertEqual(error.errorDescription, "Failed to save: Database error")
    }
}
