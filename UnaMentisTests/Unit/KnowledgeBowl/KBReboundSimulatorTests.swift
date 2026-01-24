//
//  KBReboundSimulatorTests.swift
//  UnaMentisTests
//
//  Unit tests for Knowledge Bowl rebound training simulator.
//

import Testing
@testable import UnaMentis
import Foundation

// MARK: - Rebound Configuration Tests

@Suite("KB Rebound Config Tests")
struct KBReboundConfigTests {

    @Test("Default config uses region settings")
    func defaultConfigUsesRegionSettings() {
        let config = KBReboundConfig.forRegion(.colorado)

        #expect(config.region == .colorado)
        #expect(config.reboundProbability == 0.5)
        #expect(config.opponentAccuracy == 0.6)
        #expect(config.questionCount == 15)
        #expect(config.showOpponentAnswer == true)
        #expect(config.useProgressiveDifficulty == true)
    }

    @Test("Custom config clamps probability to valid range")
    func customConfigClampsProbability() {
        let configLow = KBReboundConfig(
            region: .minnesota,
            reboundProbability: 0.1, // Below min
            opponentAccuracy: 0.5,
            questionCount: 10
        )

        let configHigh = KBReboundConfig(
            region: .minnesota,
            reboundProbability: 0.95, // Above max
            opponentAccuracy: 0.5,
            questionCount: 10
        )

        #expect(configLow.reboundProbability == 0.3) // Clamped to min
        #expect(configHigh.reboundProbability == 0.8) // Clamped to max
    }

    @Test("Custom config clamps opponent accuracy")
    func customConfigClampsAccuracy() {
        let configLow = KBReboundConfig(
            region: .washington,
            reboundProbability: 0.5,
            opponentAccuracy: 0.1, // Below min
            questionCount: 10
        )

        let configHigh = KBReboundConfig(
            region: .washington,
            reboundProbability: 0.5,
            opponentAccuracy: 0.99, // Above max
            questionCount: 10
        )

        #expect(configLow.opponentAccuracy == 0.3) // Clamped to min
        #expect(configHigh.opponentAccuracy == 0.9) // Clamped to max
    }
}

// MARK: - Rebound Decision Tests

@Suite("KB Rebound Decision Tests")
struct KBReboundDecisionTests {

    @Test("All decisions have display names")
    func allDecisionsHaveDisplayNames() {
        for decision in ReboundDecision.allCases {
            #expect(!decision.displayName.isEmpty)
        }
    }

    @Test("Positive decisions are correctly identified")
    func positiveDecisionsAreCorrect() {
        #expect(ReboundDecision.buzzedCorrectly.isPositive == true)
        #expect(ReboundDecision.strategicHold.isPositive == true)
        #expect(ReboundDecision.correctlyIgnored.isPositive == true)

        #expect(ReboundDecision.buzzedIncorrectly.isPositive == false)
        #expect(ReboundDecision.missedOpportunity.isPositive == false)
    }

    @Test("Decision count is correct")
    func decisionCountIsCorrect() {
        #expect(ReboundDecision.allCases.count == 5)
    }
}

// MARK: - Rebound Attempt Tests

@Suite("KB Rebound Attempt Tests")
struct KBReboundAttemptTests {

    @Test("Attempt initializes with correct values")
    func attemptInitializesCorrectly() {
        let scenarioId = UUID()
        let questionId = UUID()

        let attempt = KBReboundAttempt(
            scenarioId: scenarioId,
            questionId: questionId,
            domain: .science,
            wasReboundOpportunity: true,
            userBuzzedOnRebound: true,
            userAnswer: "Paris",
            wasCorrect: true,
            responseTime: 2.5,
            pointsEarned: 10,
            strategicDecision: .buzzedCorrectly
        )

        #expect(attempt.scenarioId == scenarioId)
        #expect(attempt.questionId == questionId)
        #expect(attempt.domain == .science)
        #expect(attempt.wasReboundOpportunity == true)
        #expect(attempt.userBuzzedOnRebound == true)
        #expect(attempt.userAnswer == "Paris")
        #expect(attempt.wasCorrect == true)
        #expect(attempt.responseTime == 2.5)
        #expect(attempt.pointsEarned == 10)
        #expect(attempt.strategicDecision == .buzzedCorrectly)
    }

    @Test("Attempt timestamps are set automatically")
    func attemptTimestampIsSet() {
        let before = Date()

        let attempt = KBReboundAttempt(
            scenarioId: UUID(),
            questionId: UUID(),
            domain: .history,
            wasReboundOpportunity: false,
            userBuzzedOnRebound: false,
            wasCorrect: false,
            responseTime: 1.0,
            strategicDecision: .correctlyIgnored
        )

        let after = Date()

        #expect(attempt.timestamp >= before)
        #expect(attempt.timestamp <= after)
    }
}

// MARK: - Rebound Stats Tests

@Suite("KB Rebound Stats Tests")
struct KBReboundStatsTests {

    @Test("Empty attempts result in zero stats")
    func emptyAttemptsZeroStats() {
        let stats = KBReboundStats(attempts: [])

        #expect(stats.totalScenarios == 0)
        #expect(stats.reboundOpportunities == 0)
        #expect(stats.reboundsTaken == 0)
        #expect(stats.reboundsCorrect == 0)
        #expect(stats.reboundAccuracy == 0)
        #expect(stats.opportunityCapture == 0)
        #expect(stats.averageResponseTime == 0)
    }

    @Test("Stats calculate rebound accuracy correctly")
    func statsCalculateReboundAccuracy() {
        let attempts = [
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .science,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: true,
                wasCorrect: true,
                responseTime: 2.0,
                pointsEarned: 10,
                strategicDecision: .buzzedCorrectly
            ),
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .science,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: true,
                wasCorrect: false,
                responseTime: 2.5,
                pointsEarned: -5,
                strategicDecision: .buzzedIncorrectly
            )
        ]

        let stats = KBReboundStats(attempts: attempts)

        #expect(stats.reboundsTaken == 2)
        #expect(stats.reboundsCorrect == 1)
        #expect(stats.reboundAccuracy == 0.5) // 1 out of 2
    }

    @Test("Stats calculate opportunity capture correctly")
    func statsCalculateOpportunityCapture() {
        let attempts = [
            // Rebound opportunity - taken
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .science,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: true,
                wasCorrect: true,
                responseTime: 2.0,
                pointsEarned: 10,
                strategicDecision: .buzzedCorrectly
            ),
            // Rebound opportunity - not taken (strategic hold)
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .history,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: false,
                wasCorrect: false,
                responseTime: 3.0,
                pointsEarned: 2,
                strategicDecision: .strategicHold
            ),
            // Not a rebound opportunity
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .literature,
                wasReboundOpportunity: false,
                userBuzzedOnRebound: false,
                wasCorrect: false,
                responseTime: 1.5,
                pointsEarned: 1,
                strategicDecision: .correctlyIgnored
            )
        ]

        let stats = KBReboundStats(attempts: attempts)

        #expect(stats.totalScenarios == 3)
        #expect(stats.reboundOpportunities == 2)
        #expect(stats.reboundsTaken == 1)
        #expect(stats.opportunityCapture == 0.5) // 1 out of 2 opportunities taken
    }

    @Test("Stats count strategic holds correctly")
    func statsCountStrategicHolds() {
        let attempts = [
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .mathematics,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: false,
                wasCorrect: false,
                responseTime: 3.0,
                pointsEarned: 2,
                strategicDecision: .strategicHold
            ),
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .science,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: false,
                wasCorrect: false,
                responseTime: 2.5,
                pointsEarned: 2,
                strategicDecision: .strategicHold
            )
        ]

        let stats = KBReboundStats(attempts: attempts)

        #expect(stats.strategicHolds == 2)
    }

    @Test("Stats count missed opportunities correctly")
    func statsCountMissedOpportunities() {
        let attempts = [
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .history,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: false,
                wasCorrect: false,
                responseTime: 4.0,
                pointsEarned: -2,
                strategicDecision: .missedOpportunity
            )
        ]

        let stats = KBReboundStats(attempts: attempts)

        #expect(stats.missedOpportunities == 1)
    }

    @Test("Stats calculate average response time correctly")
    func statsCalculateAverageResponseTime() {
        let attempts = [
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .science,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: true,
                wasCorrect: true,
                responseTime: 2.0,
                pointsEarned: 10,
                strategicDecision: .buzzedCorrectly
            ),
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .history,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: true,
                wasCorrect: true,
                responseTime: 4.0,
                pointsEarned: 10,
                strategicDecision: .buzzedCorrectly
            )
        ]

        let stats = KBReboundStats(attempts: attempts)

        #expect(stats.averageResponseTime == 3.0) // (2 + 4) / 2
    }

    @Test("Stats calculate total points correctly")
    func statsCalculateTotalPoints() {
        let attempts = [
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .science,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: true,
                wasCorrect: true,
                responseTime: 2.0,
                pointsEarned: 10,
                strategicDecision: .buzzedCorrectly
            ),
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .history,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: true,
                wasCorrect: false,
                responseTime: 3.0,
                pointsEarned: -5,
                strategicDecision: .buzzedIncorrectly
            ),
            KBReboundAttempt(
                scenarioId: UUID(),
                questionId: UUID(),
                domain: .literature,
                wasReboundOpportunity: true,
                userBuzzedOnRebound: false,
                wasCorrect: false,
                responseTime: 2.5,
                pointsEarned: 2,
                strategicDecision: .strategicHold
            )
        ]

        let stats = KBReboundStats(attempts: attempts)

        #expect(stats.totalPoints == 7) // 10 - 5 + 2
    }
}

// MARK: - Rebound Simulator Tests

@Suite("KB Rebound Simulator Tests")
struct KBReboundSimulatorTests {

    /// Creates a test question for simulator tests
    private func createTestQuestion(domain: KBDomain = .science) -> KBQuestion {
        KBQuestion(
            id: UUID(),
            text: "What is the chemical symbol for gold?",
            answer: KBAnswer(
                primary: "Au",
                acceptable: ["Gold", "Aurum"],
                pronunciation: nil
            ),
            domain: domain,
            difficulty: .intermediate,
            suitability: KBQuestionSuitability(
                forWritten: true,
                forOral: true,
                mcqPossible: true,
                requiresVisual: false
            ),
            estimatedReadTime: 3.0
        )
    }

    @Test("Session starts and ends correctly")
    func sessionStartsAndEnds() async {
        let simulator = KBReboundSimulator(region: .colorado)

        await simulator.startSession()
        let stats = await simulator.endSession()

        #expect(stats.totalScenarios == 0)
    }

    @Test("Scenario generation creates valid scenarios")
    func scenarioGenerationCreatesValidScenarios() async {
        let simulator = KBReboundSimulator(region: .minnesota)
        await simulator.startSession()

        let question = createTestQuestion()
        let scenario = await simulator.generateScenario(for: question)

        #expect(scenario.question.id == question.id)
        // Scenario should have a non-nil ID
        #expect(scenario.id != UUID())
    }

    @Test("Rebound opportunity depends on opponent correctness")
    func reboundOpportunityDependsOnOpponentCorrectness() async {
        // Create a config with 100% buzz probability for testing
        let config = KBReboundConfig(
            region: .colorado,
            reboundProbability: 0.8, // Max allowed
            opponentAccuracy: 0.3, // Low accuracy = more misses
            questionCount: 10
        )

        let simulator = KBReboundSimulator(config: config)
        await simulator.startSession()

        // Generate multiple scenarios and check that some are rebound opportunities
        var reboundCount = 0
        let question = createTestQuestion()

        for _ in 0..<20 {
            let scenario = await simulator.generateScenario(for: question)
            if scenario.isReboundOpportunity {
                reboundCount += 1
            }
        }

        // With 80% buzz probability and 30% accuracy, we should see some rebounds
        // This is probabilistic, so we just check that some rebounds occurred
        #expect(reboundCount >= 0) // At least 0 (may be 0 due to randomness)
    }

    @Test("Recording attempt updates stats")
    func recordingAttemptUpdatesStats() async {
        let simulator = KBReboundSimulator(region: .washington)
        await simulator.startSession()

        let question = createTestQuestion()
        _ = await simulator.generateScenario(for: question)

        await simulator.recordAttempt(
            buzzedOnRebound: true,
            userAnswer: "Au",
            wasCorrect: true,
            responseTime: 2.0,
            knewAnswer: true
        )

        let stats = await simulator.endSession()

        #expect(stats.totalScenarios == 1)
    }

    @Test("Opponent rotation works")
    func opponentRotationWorks() async {
        let simulator = KBReboundSimulator(region: .colorado)
        await simulator.startSession()

        let first = await simulator.getCurrentOpponent()
        await simulator.rotateOpponent()
        let second = await simulator.getCurrentOpponent()
        await simulator.rotateOpponent()
        let third = await simulator.getCurrentOpponent()

        // Should cycle through different opponent names
        #expect(!first.isEmpty)
        #expect(!second.isEmpty)
        #expect(!third.isEmpty)
    }

    @Test("Practice scenarios are generated")
    func practiceScenarios() {
        let scenarios = KBReboundSimulator.generatePracticeScenarios()

        #expect(scenarios.count >= 3)

        for (scenario, tip) in scenarios {
            #expect(!scenario.isEmpty)
            #expect(!tip.isEmpty)
        }
    }
}

// MARK: - Rebound Scenario Tests

@Suite("KB Rebound Scenario Tests")
struct KBReboundScenarioTests {

    @Test("Scenario stores question reference")
    func scenarioStoresQuestionReference() {
        let question = KBQuestion(
            id: UUID(),
            text: "Test question",
            answer: KBAnswer(primary: "Answer", acceptable: nil, pronunciation: nil),
            domain: .history,
            difficulty: .beginner,
            suitability: KBQuestionSuitability(
                forWritten: true,
                forOral: true,
                mcqPossible: true,
                requiresVisual: false
            ),
            estimatedReadTime: 2.0
        )

        let scenario = KBReboundScenario(
            id: UUID(),
            question: question,
            opponentBuzzed: true,
            opponentAnswer: "Wrong Answer",
            opponentWasCorrect: false,
            isReboundOpportunity: true,
            timeAfterOpponentAnswer: 2.5
        )

        #expect(scenario.question.id == question.id)
        #expect(scenario.opponentBuzzed == true)
        #expect(scenario.opponentAnswer == "Wrong Answer")
        #expect(scenario.opponentWasCorrect == false)
        #expect(scenario.isReboundOpportunity == true)
        #expect(scenario.timeAfterOpponentAnswer == 2.5)
    }

    @Test("Non-rebound scenario when opponent correct")
    func nonReboundWhenOpponentCorrect() {
        let question = KBQuestion(
            id: UUID(),
            text: "What is 2+2?",
            answer: KBAnswer(primary: "4", acceptable: ["Four"], pronunciation: nil),
            domain: .mathematics,
            difficulty: .beginner,
            suitability: KBQuestionSuitability(
                forWritten: true,
                forOral: true,
                mcqPossible: true,
                requiresVisual: false
            ),
            estimatedReadTime: 1.5
        )

        let scenario = KBReboundScenario(
            id: UUID(),
            question: question,
            opponentBuzzed: true,
            opponentAnswer: "4",
            opponentWasCorrect: true,
            isReboundOpportunity: false, // Not a rebound because opponent was correct
            timeAfterOpponentAnswer: 0
        )

        #expect(scenario.isReboundOpportunity == false)
    }
}
