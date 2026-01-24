//
//  KBConferenceManagerTests.swift
//  UnaMentisTests
//
//  Unit tests for Knowledge Bowl conference training manager.
//

import Testing
@testable import UnaMentis
import Foundation

// MARK: - Conference Configuration Tests

@Suite("KB Conference Config Tests")
struct KBConferenceConfigTests {

    @Test("Default config uses region settings")
    func defaultConfigUsesRegionSettings() {
        let config = KBConferenceConfig.forRegion(.colorado)

        #expect(config.region == .colorado)
        #expect(config.baseTimeLimit == 15.0)
        #expect(config.handSignalsOnly == true) // Colorado doesn't allow verbal
        #expect(config.progressiveDifficulty == true)
        #expect(config.questionCount == 15)
    }

    @Test("Minnesota config allows verbal conferring")
    func minnesotaConfigAllowsVerbal() {
        let config = KBConferenceConfig.forRegion(.minnesota)

        #expect(config.handSignalsOnly == false) // Minnesota allows verbal
    }

    @Test("Washington config allows verbal conferring")
    func washingtonConfigAllowsVerbal() {
        let config = KBConferenceConfig.forRegion(.washington)

        #expect(config.handSignalsOnly == false) // Washington allows verbal
    }

    @Test("Time limit respects progressive levels")
    func timeLimitRespectsProgressiveLevels() {
        let config = KBConferenceConfig.forRegion(.colorado)

        #expect(config.timeLimit(forLevel: 0) == 15)
        #expect(config.timeLimit(forLevel: 1) == 12)
        #expect(config.timeLimit(forLevel: 2) == 10)
        #expect(config.timeLimit(forLevel: 3) == 8)
    }

    @Test("Time limit clamps to max level")
    func timeLimitClampsToMaxLevel() {
        let config = KBConferenceConfig.forRegion(.colorado)

        #expect(config.timeLimit(forLevel: 100) == 8) // Clamped to max
    }

    @Test("Non-progressive config uses base time limit")
    func nonProgressiveUsesBaseTimeLimit() {
        let config = KBConferenceConfig(
            region: .colorado,
            baseTimeLimit: 20.0,
            progressiveDifficulty: false,
            handSignalsOnly: true,
            questionCount: 10
        )

        #expect(config.timeLimit(forLevel: 0) == 20.0)
        #expect(config.timeLimit(forLevel: 3) == 20.0)
    }
}

// MARK: - Conference Attempt Tests

@Suite("KB Conference Attempt Tests")
struct KBConferenceAttemptTests {

    @Test("Attempt calculates efficiency correctly")
    func attemptCalculatesEfficiency() {
        // 5 seconds used out of 15 seconds = 66.7% efficiency (faster is better)
        let attempt = KBConferenceAttempt(
            questionId: UUID(),
            domain: .science,
            conferenceTime: 5.0,
            timeLimitUsed: 15.0,
            wasCorrect: true
        )

        #expect(attempt.efficiency > 0.66)
        #expect(attempt.efficiency < 0.67)
    }

    @Test("Full time usage results in zero efficiency")
    func fullTimeUsageZeroEfficiency() {
        let attempt = KBConferenceAttempt(
            questionId: UUID(),
            domain: .science,
            conferenceTime: 15.0,
            timeLimitUsed: 15.0,
            wasCorrect: true
        )

        #expect(attempt.efficiency == 0.0)
        #expect(attempt.usedFullTime == true)
    }

    @Test("Used full time flag works correctly")
    func usedFullTimeFlagWorks() {
        // 95% of time limit counts as "full time"
        let almostFull = KBConferenceAttempt(
            questionId: UUID(),
            domain: .mathematics,
            conferenceTime: 14.5,
            timeLimitUsed: 15.0,
            wasCorrect: false
        )

        let quick = KBConferenceAttempt(
            questionId: UUID(),
            domain: .mathematics,
            conferenceTime: 5.0,
            timeLimitUsed: 15.0,
            wasCorrect: true
        )

        #expect(almostFull.usedFullTime == true)
        #expect(quick.usedFullTime == false)
    }

    @Test("Signal is recorded correctly")
    func signalIsRecorded() {
        let attempt = KBConferenceAttempt(
            questionId: UUID(),
            domain: .history,
            conferenceTime: 8.0,
            timeLimitUsed: 15.0,
            wasCorrect: true,
            signalUsed: .confident
        )

        #expect(attempt.signalUsed == .confident)
    }
}

// MARK: - Hand Signal Tests

@Suite("KB Hand Signal Tests")
struct KBHandSignalTests {

    @Test("All signals have display names")
    func allSignalsHaveDisplayNames() {
        for signal in KBHandSignal.allCases {
            #expect(!signal.displayName.isEmpty)
        }
    }

    @Test("All signals have gesture descriptions")
    func allSignalsHaveGestureDescriptions() {
        for signal in KBHandSignal.allCases {
            #expect(!signal.gestureDescription.isEmpty)
        }
    }

    @Test("All signals have emojis")
    func allSignalsHaveEmojis() {
        for signal in KBHandSignal.allCases {
            #expect(!signal.emoji.isEmpty)
        }
    }

    @Test("Signal count is correct")
    func signalCountIsCorrect() {
        #expect(KBHandSignal.allCases.count == 7)
    }

    @Test("Signal validation works")
    func signalValidationWorks() {
        #expect(KBConferenceManager.validateSignal(expected: .confident, given: .confident) == true)
        #expect(KBConferenceManager.validateSignal(expected: .confident, given: .unsure) == false)
    }
}

// MARK: - Conference Stats Tests

@Suite("KB Conference Stats Tests")
struct KBConferenceStatsTests {

    @Test("Stats calculate accuracy correctly")
    func statsCalculateAccuracy() {
        let stats = KBConferenceStats(
            totalAttempts: 10,
            correctCount: 7,
            averageConferenceTime: 8.0,
            fastestTime: 3.0,
            slowestTime: 14.0,
            timeoutsCount: 2,
            currentDifficultyLevel: 1,
            signalDistribution: [:]
        )

        #expect(stats.accuracy == 0.7)
    }

    @Test("Stats calculate timeout rate correctly")
    func statsCalculateTimeoutRate() {
        let stats = KBConferenceStats(
            totalAttempts: 10,
            correctCount: 8,
            averageConferenceTime: 10.0,
            fastestTime: 4.0,
            slowestTime: 15.0,
            timeoutsCount: 3,
            currentDifficultyLevel: 0,
            signalDistribution: [:]
        )

        #expect(stats.timeoutRate == 0.3)
    }

    @Test("Empty stats return zero values")
    func emptyStatsReturnZero() {
        let stats = KBConferenceStats(
            totalAttempts: 0,
            correctCount: 0,
            averageConferenceTime: 0,
            fastestTime: 0,
            slowestTime: 0,
            timeoutsCount: 0,
            currentDifficultyLevel: 0,
            signalDistribution: [:]
        )

        #expect(stats.accuracy == 0)
        #expect(stats.timeoutRate == 0)
    }
}

// MARK: - Conference Manager Tests

@Suite("KB Conference Manager Tests")
struct KBConferenceManagerTests {

    @Test("Session starts and ends correctly")
    func sessionStartsAndEnds() async {
        let manager = KBConferenceManager(region: .colorado)

        await manager.startSession()
        let isActive = await manager.isSessionActive()
        #expect(isActive == true)

        let stats = await manager.endSession()
        let isActiveAfter = await manager.isSessionActive()
        #expect(isActiveAfter == false)
        #expect(stats.totalAttempts == 0)
    }

    @Test("Recording attempt updates state")
    func recordingAttemptUpdatesState() async {
        let manager = KBConferenceManager(region: .minnesota)
        await manager.startSession()

        await manager.recordAttempt(
            questionId: UUID(),
            domain: .science,
            conferenceTime: 7.0,
            wasCorrect: true,
            signalUsed: .confident
        )

        let stats = await manager.calculateStats()
        #expect(stats.totalAttempts == 1)
        #expect(stats.correctCount == 1)
    }

    @Test("Multiple attempts are tracked")
    func multipleAttemptsAreTracked() async {
        let manager = KBConferenceManager(region: .washington)
        await manager.startSession()

        // Record several attempts
        for i in 0..<5 {
            await manager.recordAttempt(
                questionId: UUID(),
                domain: .history,
                conferenceTime: Double(5 + i),
                wasCorrect: i % 2 == 0, // Alternate correct/incorrect
                signalUsed: .answer
            )
        }

        let stats = await manager.calculateStats()
        #expect(stats.totalAttempts == 5)
        #expect(stats.correctCount == 3) // 0, 2, 4 are correct
    }

    @Test("Difficulty level starts at zero")
    func difficultyLevelStartsAtZero() async {
        let manager = KBConferenceManager(region: .colorado)
        await manager.startSession()

        let level = await manager.getCurrentDifficultyLevel()
        #expect(level == 0)
    }

    @Test("Consecutive correct answers increase difficulty")
    func consecutiveCorrectIncreaseDifficulty() async {
        let manager = KBConferenceManager(region: .colorado)
        await manager.startSession()

        // Record 3 consecutive correct (fast) answers to trigger promotion
        for _ in 0..<3 {
            await manager.recordAttempt(
                questionId: UUID(),
                domain: .science,
                conferenceTime: 5.0, // Fast answer
                wasCorrect: true
            )
        }

        let level = await manager.getCurrentDifficultyLevel()
        #expect(level == 1)
    }

    @Test("Timeouts decrease difficulty")
    func timeoutsDecreaseDifficulty() async {
        let manager = KBConferenceManager(region: .colorado)
        await manager.startSession()

        // First get to level 1
        for _ in 0..<3 {
            await manager.recordAttempt(
                questionId: UUID(),
                domain: .science,
                conferenceTime: 5.0,
                wasCorrect: true
            )
        }

        // Verify at level 1
        let levelBefore = await manager.getCurrentDifficultyLevel()
        #expect(levelBefore == 1)

        // Timeout (use full time)
        await manager.recordAttempt(
            questionId: UUID(),
            domain: .science,
            conferenceTime: 15.0, // Full time = timeout
            wasCorrect: false
        )

        let levelAfter = await manager.getCurrentDifficultyLevel()
        #expect(levelAfter == 0) // Should drop back to level 0
    }

    @Test("Time limit updates with difficulty")
    func timeLimitUpdatesWithDifficulty() async {
        let manager = KBConferenceManager(region: .colorado)
        await manager.startSession()

        let initialLimit = await manager.getCurrentTimeLimit()
        #expect(initialLimit == 15.0)

        // Promote to level 1
        for _ in 0..<3 {
            await manager.recordAttempt(
                questionId: UUID(),
                domain: .mathematics,
                conferenceTime: 5.0,
                wasCorrect: true
            )
        }

        let newLimit = await manager.getCurrentTimeLimit()
        #expect(newLimit == 12.0) // Level 1 time limit
    }

    @Test("Signal distribution is tracked")
    func signalDistributionIsTracked() async {
        let manager = KBConferenceManager(region: .colorado)
        await manager.startSession()

        await manager.recordAttempt(
            questionId: UUID(),
            domain: .science,
            conferenceTime: 5.0,
            wasCorrect: true,
            signalUsed: .confident
        )

        await manager.recordAttempt(
            questionId: UUID(),
            domain: .history,
            conferenceTime: 6.0,
            wasCorrect: true,
            signalUsed: .confident
        )

        await manager.recordAttempt(
            questionId: UUID(),
            domain: .literature,
            conferenceTime: 8.0,
            wasCorrect: false,
            signalUsed: .unsure
        )

        let stats = await manager.calculateStats()
        #expect(stats.signalDistribution[.confident] == 2)
        #expect(stats.signalDistribution[.unsure] == 1)
    }

    @Test("Domain-specific attempts can be retrieved")
    func domainSpecificAttemptsRetrieved() async {
        let manager = KBConferenceManager(region: .minnesota)
        await manager.startSession()

        await manager.recordAttempt(
            questionId: UUID(),
            domain: .science,
            conferenceTime: 5.0,
            wasCorrect: true
        )

        await manager.recordAttempt(
            questionId: UUID(),
            domain: .science,
            conferenceTime: 6.0,
            wasCorrect: false
        )

        await manager.recordAttempt(
            questionId: UUID(),
            domain: .history,
            conferenceTime: 7.0,
            wasCorrect: true
        )

        let scienceAttempts = await manager.getAttempts(for: .science)
        let historyAttempts = await manager.getAttempts(for: .history)

        #expect(scienceAttempts.count == 2)
        #expect(historyAttempts.count == 1)
    }

    @Test("Random signal prompt returns valid data")
    func randomSignalPromptReturnsValidData() {
        let (signal, scenario) = KBConferenceManager.randomSignalPrompt()

        #expect(KBHandSignal.allCases.contains(signal))
        #expect(!scenario.isEmpty)
    }
}

// MARK: - Conference Training Result Tests

@Suite("KB Conference Training Result Tests")
struct KBConferenceTrainingResultTests {

    @Test("Duration is calculated correctly")
    func durationIsCalculated() {
        let start = Date()
        let end = start.addingTimeInterval(600) // 10 minutes

        let result = KBConferenceTrainingResult(
            sessionId: UUID(),
            region: .colorado,
            startTime: start,
            endTime: end,
            stats: KBConferenceStats(
                totalAttempts: 10,
                correctCount: 7,
                averageConferenceTime: 8.0,
                fastestTime: 3.0,
                slowestTime: 14.0,
                timeoutsCount: 1,
                currentDifficultyLevel: 2,
                signalDistribution: [:]
            ),
            finalDifficultyLevel: 2,
            recommendation: "Good work!"
        )

        #expect(result.duration == 600)
    }

    @Test("Recommendation generation for high timeouts")
    func recommendationForHighTimeouts() {
        let stats = KBConferenceStats(
            totalAttempts: 10,
            correctCount: 8,
            averageConferenceTime: 12.0,
            fastestTime: 8.0,
            slowestTime: 15.0,
            timeoutsCount: 4, // 40% timeout rate
            currentDifficultyLevel: 0,
            signalDistribution: [:]
        )

        let recommendation = KBConferenceTrainingResult.generateRecommendation(from: stats)
        #expect(recommendation.contains("faster") || recommendation.contains("decision"))
    }

    @Test("Recommendation generation for low accuracy")
    func recommendationForLowAccuracy() {
        let stats = KBConferenceStats(
            totalAttempts: 10,
            correctCount: 4, // 40% accuracy
            averageConferenceTime: 6.0,
            fastestTime: 3.0,
            slowestTime: 10.0,
            timeoutsCount: 1,
            currentDifficultyLevel: 0,
            signalDistribution: [:]
        )

        let recommendation = KBConferenceTrainingResult.generateRecommendation(from: stats)
        #expect(recommendation.contains("accuracy") || recommendation.contains("analysis"))
    }

    @Test("Recommendation generation for excellent performance")
    func recommendationForExcellentPerformance() {
        let stats = KBConferenceStats(
            totalAttempts: 10,
            correctCount: 9, // 90% accuracy
            averageConferenceTime: 4.0, // Fast
            fastestTime: 2.0,
            slowestTime: 6.0,
            timeoutsCount: 0,
            currentDifficultyLevel: 3,
            signalDistribution: [:]
        )

        let recommendation = KBConferenceTrainingResult.generateRecommendation(from: stats)
        #expect(recommendation.contains("Excellent") || recommendation.contains("faster"))
    }
}
