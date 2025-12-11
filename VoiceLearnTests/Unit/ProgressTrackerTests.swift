// VoiceLearn - Progress Tracker Tests
// TDD tests for topic progress tracking
//
// Tests written first per TDD methodology

import XCTest
import CoreData
@testable import VoiceLearn

final class ProgressTrackerTests: XCTestCase {

    // MARK: - Properties

    var progressTracker: ProgressTracker!
    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!

    // MARK: - Setup / Teardown

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        progressTracker = ProgressTracker(persistenceController: persistenceController)
    }

    override func tearDown() async throws {
        progressTracker = nil
        context = nil
        persistenceController = nil
        try await super.tearDown()
    }

    // MARK: - Progress Creation Tests

    @MainActor
    func testCreateProgress_forTopic_createsNewProgress() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context, title: "Test Topic")
        try context.save()

        // When
        let progress = try progressTracker.createProgress(for: topic)

        // Then
        XCTAssertNotNil(progress)
        XCTAssertNotNil(progress.id)
        XCTAssertEqual(progress.topic, topic)
        XCTAssertEqual(progress.timeSpent, 0)
        XCTAssertNil(progress.quizScores)
    }

    @MainActor
    func testCreateProgress_setsLastAccessedToNow() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        try context.save()
        let beforeCreation = Date()

        // When
        let progress = try progressTracker.createProgress(for: topic)

        // Then
        XCTAssertNotNil(progress.lastAccessed)
        XCTAssertGreaterThanOrEqual(progress.lastAccessed!, beforeCreation)
    }

    @MainActor
    func testCreateProgress_linksTopicToProgress() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        try context.save()

        // When
        let progress = try progressTracker.createProgress(for: topic)

        // Then
        XCTAssertEqual(topic.progress, progress)
    }

    // MARK: - Time Tracking Tests

    @MainActor
    func testUpdateTimeSpent_addsTime() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let progress = TestDataFactory.createProgress(in: context, for: topic, timeSpent: 100)
        try context.save()

        // When
        try progressTracker.updateTimeSpent(progress: progress, additionalTime: 50)

        // Then
        XCTAssertEqual(progress.timeSpent, 150)
    }

    @MainActor
    func testUpdateTimeSpent_accumulatesMultipleCalls() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let progress = TestDataFactory.createProgress(in: context, for: topic, timeSpent: 0)
        try context.save()

        // When
        try progressTracker.updateTimeSpent(progress: progress, additionalTime: 30)
        try progressTracker.updateTimeSpent(progress: progress, additionalTime: 45)
        try progressTracker.updateTimeSpent(progress: progress, additionalTime: 25)

        // Then
        XCTAssertEqual(progress.timeSpent, 100)
    }

    @MainActor
    func testUpdateTimeSpent_updatesLastAccessed() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let progress = TestDataFactory.createProgress(in: context, for: topic)
        let oldAccessTime = progress.lastAccessed
        try context.save()

        // Small delay to ensure time difference
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // When
        try progressTracker.updateTimeSpent(progress: progress, additionalTime: 60)

        // Then
        XCTAssertNotNil(progress.lastAccessed)
        if let oldTime = oldAccessTime {
            XCTAssertGreaterThan(progress.lastAccessed!, oldTime)
        }
    }

    // MARK: - Mastery Update Tests

    @MainActor
    func testUpdateMastery_setsLevel() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context, mastery: 0.0)
        let _ = TestDataFactory.createProgress(in: context, for: topic)
        try context.save()

        // When
        try progressTracker.updateMastery(topic: topic, level: 0.75)

        // Then
        XCTAssertEqual(topic.mastery, 0.75, accuracy: 0.001)
    }

    @MainActor
    func testUpdateMastery_clampsToValidRange() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let _ = TestDataFactory.createProgress(in: context, for: topic)
        try context.save()

        // When - above 1.0
        try progressTracker.updateMastery(topic: topic, level: 1.5)

        // Then
        XCTAssertEqual(topic.mastery, 1.0, accuracy: 0.001)

        // When - below 0.0
        try progressTracker.updateMastery(topic: topic, level: -0.5)

        // Then
        XCTAssertEqual(topic.mastery, 0.0, accuracy: 0.001)
    }

    // MARK: - Quiz Score Tests

    @MainActor
    func testRecordQuizScore_addsScore() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let progress = TestDataFactory.createProgress(in: context, for: topic)
        try context.save()

        // When
        try progressTracker.recordQuizScore(progress: progress, score: 0.85)

        // Then
        XCTAssertNotNil(progress.quizScores)
        XCTAssertEqual(progress.quizScores?.count, 1)
        XCTAssertEqual(Double(progress.quizScores?.first ?? 0), 0.85, accuracy: 0.001)
    }

    @MainActor
    func testRecordQuizScore_accumulatesScores() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let progress = TestDataFactory.createProgress(in: context, for: topic)
        try context.save()

        // When
        try progressTracker.recordQuizScore(progress: progress, score: 0.70)
        try progressTracker.recordQuizScore(progress: progress, score: 0.85)
        try progressTracker.recordQuizScore(progress: progress, score: 0.95)

        // Then
        XCTAssertEqual(progress.quizScores?.count, 3)
    }

    @MainActor
    func testAverageQuizScore_calculatesCorrectly() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let progress = TestDataFactory.createProgress(
            in: context,
            for: topic,
            quizScores: [0.70, 0.80, 0.90]
        )
        try context.save()

        // When
        let average = progressTracker.averageQuizScore(for: progress)

        // Then
        XCTAssertEqual(average, 0.80, accuracy: 0.001)
    }

    @MainActor
    func testAverageQuizScore_returnsZeroForNoScores() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        let progress = TestDataFactory.createProgress(in: context, for: topic)
        try context.save()

        // When
        let average = progressTracker.averageQuizScore(for: progress)

        // Then
        XCTAssertEqual(average, 0.0)
    }

    // MARK: - Status Transition Tests

    @MainActor
    func testMarkCompleted_setsCompletionState() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context, mastery: 0.5)
        let _ = TestDataFactory.createProgress(in: context, for: topic, timeSpent: 3600)
        try context.save()

        // When
        try progressTracker.markCompleted(topic: topic, masteryLevel: 0.9)

        // Then
        XCTAssertEqual(topic.mastery, 0.9, accuracy: 0.001)
        XCTAssertEqual(topic.status, .completed)
    }

    @MainActor
    func testTopicStatus_notStarted_whenNoProgress() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        // No progress created

        // Then
        XCTAssertEqual(topic.status, .notStarted)
    }

    @MainActor
    func testTopicStatus_inProgress_whenHasTimeSpent() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context, mastery: 0.3)
        let _ = TestDataFactory.createProgress(in: context, for: topic, timeSpent: 600)
        try context.save()

        // Then
        XCTAssertEqual(topic.status, .inProgress)
    }

    @MainActor
    func testTopicStatus_completed_whenHighMastery() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context, mastery: 0.85)
        let _ = TestDataFactory.createProgress(in: context, for: topic, timeSpent: 3600)
        try context.save()

        // Then
        XCTAssertEqual(topic.status, .completed)
    }

    // MARK: - Persistence Tests

    @MainActor
    func testProgress_persistsAfterSave() async throws {
        // Given
        let topic = TestDataFactory.createTopic(in: context)
        try context.save()
        let topicId = topic.id!

        // When
        let progress = try progressTracker.createProgress(for: topic)
        try progressTracker.updateTimeSpent(progress: progress, additionalTime: 120)
        try progressTracker.recordQuizScore(progress: progress, score: 0.9)

        // Fetch fresh from context
        let fetchRequest = Topic.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", topicId as CVarArg)
        let fetchedTopics = try context.fetch(fetchRequest)
        let fetchedTopic = fetchedTopics.first

        // Then
        XCTAssertNotNil(fetchedTopic?.progress)
        XCTAssertEqual(fetchedTopic?.progress?.timeSpent, 120)
        XCTAssertEqual(Double(fetchedTopic?.progress?.quizScores?.first ?? 0), 0.9, accuracy: 0.001)
    }
}
