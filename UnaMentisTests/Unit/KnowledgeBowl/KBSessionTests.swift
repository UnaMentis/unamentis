//
//  KBSessionTests.swift
//  UnaMentisTests
//
//  Tests for KBSession, KBSessionSummary, and session state management
//

import XCTest
@testable import UnaMentis

final class KBSessionTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeConfig(
        region: KBRegion = .colorado,
        roundType: KBRoundType = .written,
        questionCount: Int = 10,
        timeLimit: TimeInterval? = 300
    ) -> KBSessionConfig {
        KBSessionConfig(
            region: region,
            roundType: roundType,
            questionCount: questionCount,
            timeLimit: timeLimit,
            domains: nil,
            difficulty: nil,
            gradeLevel: nil
        )
    }

    private func makeAttempt(
        wasCorrect: Bool = true,
        pointsEarned: Int = 1,
        responseTime: TimeInterval = 5.0,
        domain: KBDomain = .science
    ) -> KBQuestionAttempt {
        KBQuestionAttempt(
            questionId: UUID(),
            domain: domain,
            responseTime: responseTime,
            wasCorrect: wasCorrect,
            pointsEarned: pointsEarned,
            roundType: .written
        )
    }

    // MARK: - Initialization Tests

    func testInit_createsSessionWithDefaults() {
        let config = makeConfig()
        let session = KBSession(config: config)

        XCTAssertNotNil(session.id)
        XCTAssertEqual(session.config.questionCount, 10)
        XCTAssertNil(session.endTime)
        XCTAssertTrue(session.attempts.isEmpty)
        XCTAssertEqual(session.currentQuestionIndex, 0)
        XCTAssertFalse(session.isComplete)
    }

    func testInit_setsStartTime() {
        let beforeCreation = Date()
        let config = makeConfig()
        let session = KBSession(config: config)
        let afterCreation = Date()

        XCTAssertGreaterThanOrEqual(session.startTime, beforeCreation)
        XCTAssertLessThanOrEqual(session.startTime, afterCreation)
    }

    func testInit_acceptsCustomId() {
        let customId = UUID()
        let config = makeConfig()
        let session = KBSession(id: customId, config: config)

        XCTAssertEqual(session.id, customId)
    }

    // MARK: - Duration Tests

    func testDuration_withNoEndTime_calculatesFromNow() {
        let config = makeConfig()
        var session = KBSession(config: config)

        // Duration should be very small since we just created it
        XCTAssertLessThan(session.duration, 1.0)

        // Manually set an older start time
        session = KBSession(
            id: session.id,
            config: config,
            startTime: Date().addingTimeInterval(-60)
        )

        XCTAssertGreaterThanOrEqual(session.duration, 59.0)
        XCTAssertLessThanOrEqual(session.duration, 61.0)
    }

    func testDuration_withEndTime_calculatesFromStartToEnd() {
        let config = makeConfig()
        let startTime = Date().addingTimeInterval(-120)
        let endTime = Date().addingTimeInterval(-60)

        var session = KBSession(config: config, startTime: startTime)
        session.endTime = endTime

        XCTAssertEqual(session.duration, 60.0, accuracy: 0.1)
    }

    // MARK: - Attempt Statistics Tests

    func testCorrectCount_countsCorrectAttempts() {
        let config = makeConfig()
        var session = KBSession(config: config)

        session.attempts = [
            makeAttempt(wasCorrect: true),
            makeAttempt(wasCorrect: true),
            makeAttempt(wasCorrect: false),
            makeAttempt(wasCorrect: true)
        ]

        XCTAssertEqual(session.correctCount, 3)
    }

    func testIncorrectCount_countsIncorrectAttempts() {
        let config = makeConfig()
        var session = KBSession(config: config)

        session.attempts = [
            makeAttempt(wasCorrect: true),
            makeAttempt(wasCorrect: false),
            makeAttempt(wasCorrect: false)
        ]

        XCTAssertEqual(session.incorrectCount, 2)
    }

    func testTotalPoints_sumsPointsEarned() {
        let config = makeConfig()
        var session = KBSession(config: config)

        session.attempts = [
            makeAttempt(wasCorrect: true, pointsEarned: 5),
            makeAttempt(wasCorrect: true, pointsEarned: 5),
            makeAttempt(wasCorrect: false, pointsEarned: 0),
            makeAttempt(wasCorrect: true, pointsEarned: 5)
        ]

        XCTAssertEqual(session.totalPoints, 15)
    }

    func testAccuracy_calculatesPercentageCorrect() {
        let config = makeConfig()
        var session = KBSession(config: config)

        session.attempts = [
            makeAttempt(wasCorrect: true),
            makeAttempt(wasCorrect: true),
            makeAttempt(wasCorrect: false),
            makeAttempt(wasCorrect: false)
        ]

        XCTAssertEqual(session.accuracy, 0.5, accuracy: 0.001)
    }

    func testAccuracy_withNoAttempts_returnsZero() {
        let config = makeConfig()
        let session = KBSession(config: config)

        XCTAssertEqual(session.accuracy, 0)
    }

    func testAverageResponseTime_calculatesCorrectly() {
        let config = makeConfig()
        var session = KBSession(config: config)

        session.attempts = [
            makeAttempt(responseTime: 2.0),
            makeAttempt(responseTime: 4.0),
            makeAttempt(responseTime: 6.0)
        ]

        XCTAssertEqual(session.averageResponseTime, 4.0, accuracy: 0.001)
    }

    func testAverageResponseTime_withNoAttempts_returnsZero() {
        let config = makeConfig()
        let session = KBSession(config: config)

        XCTAssertEqual(session.averageResponseTime, 0)
    }

    // MARK: - Progress Tests

    func testProgress_calculatesPercentageComplete() {
        let config = makeConfig(questionCount: 10)
        var session = KBSession(config: config)

        session.attempts = [makeAttempt(), makeAttempt(), makeAttempt()]

        XCTAssertEqual(session.progress, 0.3, accuracy: 0.001)
    }

    func testProgress_withZeroQuestions_returnsZero() {
        let config = makeConfig(questionCount: 0)
        let session = KBSession(config: config)

        XCTAssertEqual(session.progress, 0)
    }

    func testProgress_whenComplete_returnsOne() {
        let config = makeConfig(questionCount: 3)
        var session = KBSession(config: config)

        session.attempts = [makeAttempt(), makeAttempt(), makeAttempt()]

        XCTAssertEqual(session.progress, 1.0, accuracy: 0.001)
    }

    // MARK: - Time Remaining Tests

    func testTimeRemaining_withNoTimeLimit_returnsNil() {
        let config = makeConfig(timeLimit: nil)
        let session = KBSession(config: config)

        XCTAssertNil(session.timeRemaining())
    }

    func testTimeRemaining_calculatesCorrectly() {
        let config = makeConfig(timeLimit: 300)  // 5 minutes
        let startTime = Date().addingTimeInterval(-60)  // Started 1 minute ago
        let session = KBSession(config: config, startTime: startTime)

        let remaining = session.timeRemaining()

        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining!, 240, accuracy: 1.0)  // ~4 minutes left
    }

    func testTimeRemaining_whenExpired_returnsZero() {
        let config = makeConfig(timeLimit: 60)  // 1 minute
        let startTime = Date().addingTimeInterval(-120)  // Started 2 minutes ago
        let session = KBSession(config: config, startTime: startTime)

        let remaining = session.timeRemaining()

        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining!, 0)
    }

    // MARK: - Timer State Tests

    func testTimerState_withNoTimeLimit_returnsNil() {
        let config = makeConfig(timeLimit: nil)
        let session = KBSession(config: config)

        XCTAssertNil(session.timerState())
    }

    func testTimerState_withZeroTimeLimit_returnsNil() {
        let config = makeConfig(timeLimit: 0)
        let session = KBSession(config: config)

        XCTAssertNil(session.timerState())
    }

    // MARK: - Domain Performance Tests

    func testPerformanceByDomain_groupsAttempts() {
        let config = makeConfig()
        var session = KBSession(config: config)

        session.attempts = [
            makeAttempt(wasCorrect: true, responseTime: 2.0, domain: .science),
            makeAttempt(wasCorrect: false, responseTime: 4.0, domain: .science),
            makeAttempt(wasCorrect: true, responseTime: 3.0, domain: .mathematics)
        ]

        let performance = session.performanceByDomain

        XCTAssertEqual(performance[.science]?.total, 2)
        XCTAssertEqual(performance[.science]?.correct, 1)
        XCTAssertEqual(performance[.mathematics]?.total, 1)
        XCTAssertEqual(performance[.mathematics]?.correct, 1)
    }

    func testPerformanceByDomain_calculatesAverageTime() {
        let config = makeConfig()
        var session = KBSession(config: config)

        session.attempts = [
            makeAttempt(responseTime: 2.0, domain: .science),
            makeAttempt(responseTime: 4.0, domain: .science)
        ]

        let performance = session.performanceByDomain
        XCTAssertEqual(performance[.science]?.averageTime, 3.0, accuracy: 0.001)
    }

    // MARK: - DomainPerformance Tests

    func testDomainPerformance_accuracy_calculatesCorrectly() {
        let performance = DomainPerformance(
            domain: .science,
            correct: 7,
            total: 10,
            averageTime: 5.0
        )

        XCTAssertEqual(performance.accuracy, 0.7, accuracy: 0.001)
    }

    func testDomainPerformance_accuracy_withZeroTotal_returnsZero() {
        let performance = DomainPerformance(
            domain: .science,
            correct: 0,
            total: 0,
            averageTime: 0
        )

        XCTAssertEqual(performance.accuracy, 0)
    }

    // MARK: - KBSessionSummary Tests

    func testSessionSummary_initFromSession_extractsCorrectValues() {
        let config = makeConfig(region: .minnesota)
        var session = KBSession(config: config)
        session.endTime = Date()
        session.attempts = [
            makeAttempt(wasCorrect: true, pointsEarned: 5, responseTime: 2.0),
            makeAttempt(wasCorrect: true, pointsEarned: 5, responseTime: 4.0),
            makeAttempt(wasCorrect: false, pointsEarned: 0, responseTime: 3.0)
        ]

        let summary = KBSessionSummary(from: session)

        XCTAssertEqual(summary.sessionId, session.id)
        XCTAssertEqual(summary.roundType, .written)
        XCTAssertEqual(summary.region, .minnesota)
        XCTAssertEqual(summary.totalQuestions, 3)
        XCTAssertEqual(summary.totalCorrect, 2)
        XCTAssertEqual(summary.totalPoints, 10)
        XCTAssertEqual(summary.accuracy, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.averageResponseTime, 3.0, accuracy: 0.001)
    }

    func testSessionSummary_codable_encodesAndDecodes() throws {
        let config = makeConfig()
        var session = KBSession(config: config)
        session.endTime = Date()
        session.attempts = [makeAttempt()]

        let summary = KBSessionSummary(from: session)

        let encoder = JSONEncoder()
        let data = try encoder.encode(summary)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(KBSessionSummary.self, from: data)

        XCTAssertEqual(decoded.sessionId, summary.sessionId)
        XCTAssertEqual(decoded.totalQuestions, summary.totalQuestions)
        XCTAssertEqual(decoded.accuracy, summary.accuracy, accuracy: 0.001)
    }

    // MARK: - KBSessionState Tests

    func testSessionState_equatable() {
        XCTAssertEqual(KBSessionState.notStarted, KBSessionState.notStarted)
        XCTAssertEqual(KBSessionState.completed, KBSessionState.completed)
        XCTAssertEqual(KBSessionState.paused, KBSessionState.paused)
        XCTAssertEqual(KBSessionState.expired, KBSessionState.expired)
        XCTAssertEqual(KBSessionState.inProgress(questionIndex: 5), KBSessionState.inProgress(questionIndex: 5))
        XCTAssertEqual(KBSessionState.reviewing(attemptIndex: 3), KBSessionState.reviewing(attemptIndex: 3))

        XCTAssertNotEqual(KBSessionState.notStarted, KBSessionState.completed)
        XCTAssertNotEqual(KBSessionState.inProgress(questionIndex: 1), KBSessionState.inProgress(questionIndex: 2))
    }

    // MARK: - KBQuestionAttempt Tests

    func testQuestionAttempt_hasUniqueId() {
        let attempt1 = makeAttempt()
        let attempt2 = makeAttempt()

        XCTAssertNotEqual(attempt1.id, attempt2.id)
    }

    func testQuestionAttempt_codable_encodesAndDecodes() throws {
        let attempt = KBQuestionAttempt(
            questionId: UUID(),
            domain: .science,
            userAnswer: "Paris",
            responseTime: 5.0,
            wasCorrect: true,
            pointsEarned: 5,
            roundType: .oral,
            wasRebound: true,
            matchType: .fuzzy
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(attempt)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(KBQuestionAttempt.self, from: data)

        XCTAssertEqual(decoded.questionId, attempt.questionId)
        XCTAssertEqual(decoded.domain, attempt.domain)
        XCTAssertEqual(decoded.userAnswer, attempt.userAnswer)
        XCTAssertEqual(decoded.wasCorrect, attempt.wasCorrect)
        XCTAssertEqual(decoded.pointsEarned, attempt.pointsEarned)
        XCTAssertEqual(decoded.roundType, attempt.roundType)
        XCTAssertEqual(decoded.wasRebound, attempt.wasRebound)
        XCTAssertEqual(decoded.matchType, attempt.matchType)
    }

    func testQuestionAttempt_defaultValues() {
        let attempt = KBQuestionAttempt(
            questionId: UUID(),
            domain: .mathematics,
            responseTime: 3.0,
            wasCorrect: true,
            pointsEarned: 1,
            roundType: .written
        )

        XCTAssertNil(attempt.userAnswer)
        XCTAssertNil(attempt.selectedChoice)
        XCTAssertFalse(attempt.usedConference)
        XCTAssertNil(attempt.conferenceTime)
        XCTAssertFalse(attempt.wasRebound)
    }

    // MARK: - KBRoundType Tests

    func testRoundType_displayName() {
        XCTAssertEqual(KBRoundType.written.displayName, "Written Round")
        XCTAssertEqual(KBRoundType.oral.displayName, "Oral Round")
    }

    func testRoundType_icon() {
        XCTAssertEqual(KBRoundType.written.icon, "pencil.and.list.clipboard")
        XCTAssertEqual(KBRoundType.oral.icon, "mic.fill")
    }

    func testRoundType_allCases() {
        XCTAssertEqual(KBRoundType.allCases.count, 2)
        XCTAssertTrue(KBRoundType.allCases.contains(.written))
        XCTAssertTrue(KBRoundType.allCases.contains(.oral))
    }

    // MARK: - KBMatchType Tests

    func testMatchType_allCases() {
        let allCases: [KBMatchType] = [.exact, .acceptable, .fuzzy, .ai, .manual, .none]
        for matchType in allCases {
            XCTAssertNotNil(matchType.rawValue)
        }
    }

    func testMatchType_codable() throws {
        let matchType = KBMatchType.fuzzy

        let encoder = JSONEncoder()
        let data = try encoder.encode(matchType)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(KBMatchType.self, from: data)

        XCTAssertEqual(decoded, matchType)
    }
}
