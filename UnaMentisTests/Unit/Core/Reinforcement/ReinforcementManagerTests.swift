//
//  ReinforcementManagerTests.swift
//  UnaMentisTests
//
//  Tests for ReinforcementManager CRUD operations and grouping.

import XCTest
import CoreData
@testable import UnaMentis

final class ReinforcementManagerTests: XCTestCase {

    private var persistenceController: PersistenceController!
    private var manager: ReinforcementManager!

    @MainActor
    private func setUpTestEnvironment() {
        persistenceController = PersistenceController(inMemory: true)
        manager = ReinforcementManager(persistenceController: persistenceController)
    }

    override func tearDown() {
        persistenceController = nil
        manager = nil
        super.tearDown()
    }

    // MARK: - Create Item Tests

    @MainActor
    func testCreateItem_withAllFields_createsItem() async throws {
        setUpTestEnvironment()
        let sourceId = UUID()
        let bookmarkId = UUID()

        let item = try manager.createItem(
            currentSegmentText: "The derivative of x squared is 2x.",
            previousSegmentText: "Consider the function f(x) = x squared.",
            segmentIndex: 5,
            totalSegments: 20,
            sourceType: .readingList,
            sourceId: sourceId,
            sourceTitle: "Introduction to Calculus",
            bookmarkId: bookmarkId
        )

        XCTAssertNotNil(item.id)
        XCTAssertNotNil(item.createdAt)
        XCTAssertEqual(item.currentSegmentText, "The derivative of x squared is 2x.")
        XCTAssertEqual(item.previousSegmentText, "Consider the function f(x) = x squared.")
        XCTAssertEqual(item.segmentIndex, 5)
        XCTAssertEqual(item.totalSegments, 20)
        XCTAssertEqual(item.sourceType, .readingList)
        XCTAssertEqual(item.sourceId, sourceId)
        XCTAssertEqual(item.sourceTitle, "Introduction to Calculus")
        XCTAssertEqual(item.bookmarkId, bookmarkId)
        XCTAssertEqual(item.status, .pending)
        XCTAssertNil(item.reviewedAt)
    }

    @MainActor
    func testCreateItem_withNilPreviousSegment_firstSegment() async throws {
        setUpTestEnvironment()

        let item = try manager.createItem(
            currentSegmentText: "Welcome to calculus.",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 20,
            sourceType: .readingList,
            sourceId: UUID(),
            sourceTitle: "Calculus",
            bookmarkId: nil
        )

        XCTAssertNil(item.previousSegmentText)
        XCTAssertEqual(item.segmentIndex, 0)
        XCTAssertNil(item.bookmarkId)
    }

    @MainActor
    func testCreateItem_generatesSnippetPreview() async throws {
        setUpTestEnvironment()

        let shortItem = try manager.createItem(
            currentSegmentText: "Short text.",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 1,
            sourceType: .curriculum,
            sourceId: nil,
            sourceTitle: "Test",
            bookmarkId: nil
        )
        XCTAssertEqual(shortItem.snippetPreview, "Short text.")

        let longText = String(repeating: "word ", count: 50) // 250 chars
        let longItem = try manager.createItem(
            currentSegmentText: longText,
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 1,
            sourceType: .curriculum,
            sourceId: nil,
            sourceTitle: "Test",
            bookmarkId: nil
        )
        XCTAssertNotNil(longItem.snippetPreview)
        XCTAssertLessThanOrEqual(longItem.snippetPreview!.count, 84) // 80 + "..."
    }

    @MainActor
    func testCreateItem_withDifferentSourceTypes() async throws {
        setUpTestEnvironment()

        for sourceType in ReinforcementSourceType.allCases {
            let item = try manager.createItem(
                currentSegmentText: "Test for \(sourceType.rawValue)",
                previousSegmentText: nil,
                segmentIndex: 0,
                totalSegments: 1,
                sourceType: sourceType,
                sourceId: nil,
                sourceTitle: sourceType.displayName,
                bookmarkId: nil
            )
            XCTAssertEqual(item.sourceType, sourceType)
        }
    }

    // MARK: - Fetch All Items Tests

    @MainActor
    func testFetchAllItems_emptyDatabase_returnsEmptyArray() async throws {
        setUpTestEnvironment()

        let items = try manager.fetchAllItems()

        XCTAssertTrue(items.isEmpty)
    }

    @MainActor
    func testFetchAllItems_returnsAllItems() async throws {
        setUpTestEnvironment()

        _ = try manager.createItem(
            currentSegmentText: "Item 1",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 10,
            sourceType: .readingList,
            sourceId: nil,
            sourceTitle: "Source 1",
            bookmarkId: nil
        )
        _ = try manager.createItem(
            currentSegmentText: "Item 2",
            previousSegmentText: nil,
            segmentIndex: 1,
            totalSegments: 10,
            sourceType: .curriculum,
            sourceId: nil,
            sourceTitle: "Source 2",
            bookmarkId: nil
        )

        let items = try manager.fetchAllItems()

        XCTAssertEqual(items.count, 2)
    }

    // MARK: - Fetch Pending Items Tests

    @MainActor
    func testFetchPendingItems_returnsOnlyPending() async throws {
        setUpTestEnvironment()

        let pendingItem = try manager.createItem(
            currentSegmentText: "Pending",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 1,
            sourceType: .readingList,
            sourceId: nil,
            sourceTitle: "Source",
            bookmarkId: nil
        )
        let reviewedItem = try manager.createItem(
            currentSegmentText: "Reviewed",
            previousSegmentText: nil,
            segmentIndex: 1,
            totalSegments: 1,
            sourceType: .readingList,
            sourceId: nil,
            sourceTitle: "Source",
            bookmarkId: nil
        )
        try manager.markReviewed(reviewedItem)

        let pending = try manager.fetchPendingItems()

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, pendingItem.id)
    }

    // MARK: - Fetch Grouped Items Tests

    @MainActor
    func testFetchItemsGroupedBySource_groupsCorrectly() async throws {
        setUpTestEnvironment()
        let sourceId1 = UUID()
        let sourceId2 = UUID()

        // Two items from source 1
        _ = try manager.createItem(
            currentSegmentText: "Source 1, item 1",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 10,
            sourceType: .readingList,
            sourceId: sourceId1,
            sourceTitle: "Calculus Book",
            bookmarkId: nil
        )
        _ = try manager.createItem(
            currentSegmentText: "Source 1, item 2",
            previousSegmentText: "Source 1, item 1",
            segmentIndex: 5,
            totalSegments: 10,
            sourceType: .readingList,
            sourceId: sourceId1,
            sourceTitle: "Calculus Book",
            bookmarkId: nil
        )

        // One item from source 2
        _ = try manager.createItem(
            currentSegmentText: "Source 2, item 1",
            previousSegmentText: nil,
            segmentIndex: 3,
            totalSegments: 8,
            sourceType: .curriculum,
            sourceId: sourceId2,
            sourceTitle: "Biology Course",
            bookmarkId: nil
        )

        let groups = try manager.fetchItemsGroupedBySource()

        XCTAssertEqual(groups.count, 2)

        let calcGroup = groups.first { $0.sourceTitle == "Calculus Book" }
        XCTAssertNotNil(calcGroup)
        XCTAssertEqual(calcGroup?.items.count, 2)
        XCTAssertEqual(calcGroup?.sourceType, .readingList)
        XCTAssertEqual(calcGroup?.sourceId, sourceId1)

        let bioGroup = groups.first { $0.sourceTitle == "Biology Course" }
        XCTAssertNotNil(bioGroup)
        XCTAssertEqual(bioGroup?.items.count, 1)
        XCTAssertEqual(bioGroup?.sourceType, .curriculum)
    }

    @MainActor
    func testFetchItemsGroupedBySource_sortsBySegmentIndex() async throws {
        setUpTestEnvironment()
        let sourceId = UUID()

        _ = try manager.createItem(
            currentSegmentText: "Later segment",
            previousSegmentText: nil,
            segmentIndex: 10,
            totalSegments: 20,
            sourceType: .readingList,
            sourceId: sourceId,
            sourceTitle: "Book",
            bookmarkId: nil
        )
        _ = try manager.createItem(
            currentSegmentText: "Earlier segment",
            previousSegmentText: nil,
            segmentIndex: 2,
            totalSegments: 20,
            sourceType: .readingList,
            sourceId: sourceId,
            sourceTitle: "Book",
            bookmarkId: nil
        )

        let groups = try manager.fetchItemsGroupedBySource()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items[0].segmentIndex, 2)
        XCTAssertEqual(groups[0].items[1].segmentIndex, 10)
    }

    @MainActor
    func testFetchItemsGroupedBySource_pendingCount() async throws {
        setUpTestEnvironment()
        let sourceId = UUID()

        _ = try manager.createItem(
            currentSegmentText: "Item 1",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 10,
            sourceType: .readingList,
            sourceId: sourceId,
            sourceTitle: "Book",
            bookmarkId: nil
        )
        let reviewedItem = try manager.createItem(
            currentSegmentText: "Item 2",
            previousSegmentText: nil,
            segmentIndex: 1,
            totalSegments: 10,
            sourceType: .readingList,
            sourceId: sourceId,
            sourceTitle: "Book",
            bookmarkId: nil
        )
        try manager.markReviewed(reviewedItem)

        let groups = try manager.fetchItemsGroupedBySource()

        XCTAssertEqual(groups[0].count, 2)
        XCTAssertEqual(groups[0].pendingCount, 1)
    }

    // MARK: - Status Transition Tests

    @MainActor
    func testMarkReviewed_changesStatus() async throws {
        setUpTestEnvironment()

        let item = try manager.createItem(
            currentSegmentText: "To review",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 1,
            sourceType: .readingList,
            sourceId: nil,
            sourceTitle: "Source",
            bookmarkId: nil
        )
        XCTAssertEqual(item.status, .pending)

        try manager.markReviewed(item)

        XCTAssertEqual(item.status, .reviewed)
        XCTAssertNotNil(item.reviewedAt)
    }

    @MainActor
    func testMarkMastered_changesStatus() async throws {
        setUpTestEnvironment()

        let item = try manager.createItem(
            currentSegmentText: "To master",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 1,
            sourceType: .readingList,
            sourceId: nil,
            sourceTitle: "Source",
            bookmarkId: nil
        )

        try manager.markMastered(item)

        XCTAssertEqual(item.status, .mastered)
        XCTAssertNotNil(item.reviewedAt)
    }

    // MARK: - Delete Tests

    @MainActor
    func testDeleteItem_removesFromDatabase() async throws {
        setUpTestEnvironment()

        let item = try manager.createItem(
            currentSegmentText: "To delete",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 1,
            sourceType: .readingList,
            sourceId: nil,
            sourceTitle: "Source",
            bookmarkId: nil
        )

        try manager.deleteItem(item)

        let items = try manager.fetchAllItems()
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - ReinforcementItem Entity Tests

    @MainActor
    func testReinforcementSourceType_displayNames() {
        XCTAssertEqual(ReinforcementSourceType.readingList.displayName, "Reading List")
        XCTAssertEqual(ReinforcementSourceType.curriculum.displayName, "Curriculum")
        XCTAssertEqual(ReinforcementSourceType.session.displayName, "Session")
        XCTAssertEqual(ReinforcementSourceType.knowledgeBowl.displayName, "Knowledge Bowl")
    }

    @MainActor
    func testReinforcementSourceType_iconNames() {
        XCTAssertEqual(ReinforcementSourceType.readingList.iconName, "book.pages")
        XCTAssertEqual(ReinforcementSourceType.curriculum.iconName, "book.fill")
        XCTAssertEqual(ReinforcementSourceType.session.iconName, "bubble.left.and.bubble.right")
        XCTAssertEqual(ReinforcementSourceType.knowledgeBowl.iconName, "trophy")
    }

    @MainActor
    func testReinforcementStatus_displayNames() {
        XCTAssertEqual(ReinforcementStatus.pending.displayName, "Pending")
        XCTAssertEqual(ReinforcementStatus.reviewed.displayName, "Reviewed")
        XCTAssertEqual(ReinforcementStatus.mastered.displayName, "Mastered")
    }

    @MainActor
    func testReinforcementStatus_iconNames() {
        XCTAssertEqual(ReinforcementStatus.pending.iconName, "circle")
        XCTAssertEqual(ReinforcementStatus.reviewed.iconName, "checkmark.circle")
        XCTAssertEqual(ReinforcementStatus.mastered.iconName, "checkmark.circle.fill")
    }

    @MainActor
    func testDisplayText_shortText_returnsFullText() async throws {
        setUpTestEnvironment()

        let item = try manager.createItem(
            currentSegmentText: "Short text",
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 1,
            sourceType: .readingList,
            sourceId: nil,
            sourceTitle: "Source",
            bookmarkId: nil
        )

        XCTAssertEqual(item.displayText, "Short text")
    }

    @MainActor
    func testDisplayText_longText_truncates() async throws {
        setUpTestEnvironment()
        let longText = "This is a very long text that exceeds eighty characters and should be truncated at a word boundary to keep the preview readable"

        let item = try manager.createItem(
            currentSegmentText: longText,
            previousSegmentText: nil,
            segmentIndex: 0,
            totalSegments: 1,
            sourceType: .readingList,
            sourceId: nil,
            sourceTitle: "Source",
            bookmarkId: nil
        )

        XCTAssertTrue(item.displayText.hasSuffix("..."))
        XCTAssertLessThanOrEqual(item.displayText.count, 84)
    }
}
