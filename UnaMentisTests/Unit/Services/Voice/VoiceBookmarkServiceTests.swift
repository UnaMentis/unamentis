//
//  VoiceBookmarkServiceTests.swift
//  UnaMentisTests
//
//  Tests for VoiceBookmarkService orchestration of bookmark and flag flows.

import XCTest
import CoreData
@testable import UnaMentis

// MARK: - Test Double: FlaggableActivity

/// Real FlaggableActivity implementation for testing (not a mock of an external API).
/// Tracks calls and state changes to verify orchestration flow.
@MainActor
final class TestFlaggableActivity: FlaggableActivity { // ALLOWED: test double for protocol, not paid API
    var currentSegmentIndex: Int32 = 5
    var totalSegments: Int32 = 20
    var currentSegmentText: String? = "The derivative of x squared is 2x."
    var previousSegmentText: String? = "Consider the function f(x) = x squared."
    var sourceTitle: String = "Introduction to Calculus"
    var sourceType: ReinforcementSourceType = .readingList
    var sourceId: UUID? = UUID()

    // Tracking properties
    private(set) var pausePlaybackCallCount = 0
    private(set) var resumePlaybackCallCount = 0
    private(set) var createBookmarkCallCount = 0
    private(set) var lastBookmarkNote: String?
    var bookmarkIdToReturn: UUID? = UUID()

    func createBookmark(note: String?) async -> UUID? {
        createBookmarkCallCount += 1
        lastBookmarkNote = note
        return bookmarkIdToReturn
    }

    func pausePlayback() async {
        pausePlaybackCallCount += 1
    }

    func resumePlayback() async {
        resumePlaybackCallCount += 1
    }

    func reset() {
        pausePlaybackCallCount = 0
        resumePlaybackCallCount = 0
        createBookmarkCallCount = 0
        lastBookmarkNote = nil
    }
}

// MARK: - VoiceBookmarkService Tests

final class VoiceBookmarkServiceTests: XCTestCase {

    private var service: VoiceBookmarkService!
    private var activity: TestFlaggableActivity!
    private var feedback: VoiceActivityFeedback!

    @MainActor
    private func setUpTestEnvironment() {
        service = VoiceBookmarkService()
        activity = TestFlaggableActivity()
        feedback = VoiceActivityFeedback()
        feedback.audioEnabled = false // Suppress audio in tests
        feedback.hapticsEnabled = false // Suppress haptics in tests
    }

    // MARK: - Bookmark Flow Tests

    @MainActor
    func testPerformBookmark_pausesPlayback() async {
        setUpTestEnvironment()

        await service.performBookmark(activity: activity, feedback: feedback)

        XCTAssertEqual(activity.pausePlaybackCallCount, 1)
    }

    @MainActor
    func testPerformBookmark_createsBookmarkWithNilNote() async {
        setUpTestEnvironment()

        await service.performBookmark(activity: activity, feedback: feedback)

        XCTAssertEqual(activity.createBookmarkCallCount, 1)
        XCTAssertNil(activity.lastBookmarkNote)
    }

    @MainActor
    func testPerformBookmark_resumesPlayback() async {
        setUpTestEnvironment()

        await service.performBookmark(activity: activity, feedback: feedback)

        XCTAssertEqual(activity.resumePlaybackCallCount, 1)
    }

    @MainActor
    func testPerformBookmark_completeFlow() async {
        setUpTestEnvironment()

        await service.performBookmark(activity: activity, feedback: feedback)

        // Verify all steps executed
        XCTAssertEqual(activity.pausePlaybackCallCount, 1)
        XCTAssertEqual(activity.createBookmarkCallCount, 1)
        XCTAssertNil(activity.lastBookmarkNote)
        XCTAssertEqual(activity.resumePlaybackCallCount, 1)
    }

    // MARK: - Flag Flow Tests

    @MainActor
    func testPerformFlag_pausesPlayback() async {
        setUpTestEnvironment()
        // No ReinforcementManager.shared set, but flag flow should still work
        await service.performFlag(activity: activity, feedback: feedback)

        XCTAssertEqual(activity.pausePlaybackCallCount, 1)
    }

    @MainActor
    func testPerformFlag_createsBookmarkWithFlagNote() async {
        setUpTestEnvironment()

        await service.performFlag(activity: activity, feedback: feedback)

        XCTAssertEqual(activity.createBookmarkCallCount, 1)
        XCTAssertEqual(activity.lastBookmarkNote, "Flagged for review")
    }

    @MainActor
    func testPerformFlag_resumesPlayback() async {
        setUpTestEnvironment()

        await service.performFlag(activity: activity, feedback: feedback)

        XCTAssertEqual(activity.resumePlaybackCallCount, 1)
    }

    @MainActor
    func testPerformFlag_createsReviewItem_whenManagerAvailable() async {
        setUpTestEnvironment()
        let persistenceController = PersistenceController(inMemory: true)
        let manager = ReinforcementManager(persistenceController: persistenceController)
        ReinforcementManager.shared = manager

        await service.performFlag(activity: activity, feedback: feedback)

        let items = try? await manager.fetchAllItems()
        XCTAssertEqual(items?.count, 1)

        if let item = items?.first {
            XCTAssertEqual(item.currentSegmentText, activity.currentSegmentText)
            XCTAssertEqual(item.previousSegmentText, activity.previousSegmentText)
            XCTAssertEqual(item.segmentIndex, activity.currentSegmentIndex)
            XCTAssertEqual(item.totalSegments, activity.totalSegments)
            XCTAssertEqual(item.sourceType, activity.sourceType)
            XCTAssertEqual(item.sourceId, activity.sourceId)
            XCTAssertEqual(item.sourceTitle, activity.sourceTitle)
            XCTAssertEqual(item.bookmarkId, activity.bookmarkIdToReturn)
            XCTAssertEqual(item.status, .pending)
        }

        // Clean up
        ReinforcementManager.shared = nil
    }

    @MainActor
    func testPerformFlag_noManager_stillCompletesWithoutCrash() async {
        setUpTestEnvironment()
        ReinforcementManager.shared = nil

        await service.performFlag(activity: activity, feedback: feedback)

        // Bookmark should still be created
        XCTAssertEqual(activity.createBookmarkCallCount, 1)
        // Playback should still resume
        XCTAssertEqual(activity.resumePlaybackCallCount, 1)
    }

    @MainActor
    func testPerformFlag_nilBookmarkId_stillCreatesReviewItem() async {
        setUpTestEnvironment()
        activity.bookmarkIdToReturn = nil
        let persistenceController = PersistenceController(inMemory: true)
        let manager = ReinforcementManager(persistenceController: persistenceController)
        ReinforcementManager.shared = manager

        await service.performFlag(activity: activity, feedback: feedback)

        let items = try? await manager.fetchAllItems()
        XCTAssertEqual(items?.count, 1)
        XCTAssertNil(items?.first?.bookmarkId)

        ReinforcementManager.shared = nil
    }

    @MainActor
    func testPerformFlag_firstSegment_nilPreviousText() async {
        setUpTestEnvironment()
        activity.currentSegmentIndex = 0
        activity.previousSegmentText = nil
        let persistenceController = PersistenceController(inMemory: true)
        let manager = ReinforcementManager(persistenceController: persistenceController)
        ReinforcementManager.shared = manager

        await service.performFlag(activity: activity, feedback: feedback)

        let items = try? await manager.fetchAllItems()
        XCTAssertEqual(items?.count, 1)
        XCTAssertNil(items?.first?.previousSegmentText)

        ReinforcementManager.shared = nil
    }
}
