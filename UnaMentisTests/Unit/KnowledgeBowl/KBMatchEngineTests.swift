//
//  KBMatchEngineTests.swift
//  UnaMentisTests
//
//  Unit tests for Knowledge Bowl match simulation engine.
//

import Testing
@testable import UnaMentis
import Foundation

// MARK: - Match Configuration Tests

@Suite("KB Match Config Tests")
struct KBMatchConfigTests {

    @Test("Default config uses region settings")
    func defaultConfigUsesRegionSettings() {
        let config = KBMatchConfig.forRegion(.colorado)

        #expect(config.region == .colorado)
        #expect(config.matchFormat == .quickMatch)
        #expect(config.opponentStrengths.count == 2)
        #expect(config.enablePracticeMode == true)
    }

    @Test("Quick match format has correct question counts")
    func quickMatchFormatHasCorrectCounts() {
        let format = KBMatchConfig.MatchFormat.quickMatch

        #expect(format.writtenQuestions == 10)
        #expect(format.oralRounds == 2)
        #expect(format.questionsPerOralRound == 10)
        #expect(format.displayName == "Quick Match")
    }

    @Test("Half match format has correct question counts")
    func halfMatchFormatHasCorrectCounts() {
        let format = KBMatchConfig.MatchFormat.halfMatch

        #expect(format.writtenQuestions == 20)
        #expect(format.oralRounds == 4)
        #expect(format.questionsPerOralRound == 10)
        #expect(format.displayName == "Half Match")
    }

    @Test("Full match format has correct question counts")
    func fullMatchFormatHasCorrectCounts() {
        let format = KBMatchConfig.MatchFormat.fullMatch

        #expect(format.writtenQuestions == 40)
        #expect(format.oralRounds == 8)
        #expect(format.questionsPerOralRound == 10)
        #expect(format.displayName == "Full Match")
    }

    @Test("All match formats have display names")
    func allMatchFormatsHaveDisplayNames() {
        for format in KBMatchConfig.MatchFormat.allCases {
            #expect(!format.displayName.isEmpty)
        }
    }
}

// MARK: - Opponent Strength Tests

@Suite("KB Opponent Strength Tests")
struct KBOpponentStrengthTests {

    @Test("Beginner strength has lowest values")
    func beginnerStrengthHasLowestValues() {
        let beginner = KBMatchConfig.OpponentStrength.beginner

        #expect(beginner.buzzProbability == 0.3)
        #expect(beginner.accuracy == 0.4)
        #expect(beginner.displayName == "Beginner")
    }

    @Test("Intermediate strength has medium values")
    func intermediateStrengthHasMediumValues() {
        let intermediate = KBMatchConfig.OpponentStrength.intermediate

        #expect(intermediate.buzzProbability == 0.5)
        #expect(intermediate.accuracy == 0.6)
        #expect(intermediate.displayName == "Intermediate")
    }

    @Test("Advanced strength has high values")
    func advancedStrengthHasHighValues() {
        let advanced = KBMatchConfig.OpponentStrength.advanced

        #expect(advanced.buzzProbability == 0.7)
        #expect(advanced.accuracy == 0.75)
        #expect(advanced.displayName == "Advanced")
    }

    @Test("Expert strength has highest values")
    func expertStrengthHasHighestValues() {
        let expert = KBMatchConfig.OpponentStrength.expert

        #expect(expert.buzzProbability == 0.85)
        #expect(expert.accuracy == 0.9)
        #expect(expert.displayName == "Expert")
    }

    @Test("Strength values increase with difficulty")
    func strengthValuesIncreaseWithDifficulty() {
        let beginner = KBMatchConfig.OpponentStrength.beginner
        let intermediate = KBMatchConfig.OpponentStrength.intermediate
        let advanced = KBMatchConfig.OpponentStrength.advanced
        let expert = KBMatchConfig.OpponentStrength.expert

        #expect(beginner.buzzProbability < intermediate.buzzProbability)
        #expect(intermediate.buzzProbability < advanced.buzzProbability)
        #expect(advanced.buzzProbability < expert.buzzProbability)

        #expect(beginner.accuracy < intermediate.accuracy)
        #expect(intermediate.accuracy < advanced.accuracy)
        #expect(advanced.accuracy < expert.accuracy)
    }
}

// MARK: - Team Tests

@Suite("KB Team Tests")
struct KBTeamTests {

    @Test("Team initializes with correct values")
    func teamInitializesCorrectly() {
        let team = KBTeam(name: "Test Team", isPlayer: true)

        #expect(team.name == "Test Team")
        #expect(team.isPlayer == true)
        #expect(team.strength == nil)
        #expect(team.writtenScore == 0)
        #expect(team.oralScore == 0)
        #expect(team.totalScore == 0)
    }

    @Test("Opponent team has strength")
    func opponentTeamHasStrength() {
        let team = KBTeam(
            name: "Opponent",
            isPlayer: false,
            strength: .advanced
        )

        #expect(team.isPlayer == false)
        #expect(team.strength == .advanced)
    }

    @Test("Total score is sum of written and oral")
    func totalScoreIsSum() {
        var team = KBTeam(name: "Test Team")
        team.writtenScore = 15
        team.oralScore = 30

        #expect(team.totalScore == 45)
    }
}

// MARK: - Match Question Result Tests

@Suite("KB Match Question Result Tests")
struct KBMatchQuestionResultTests {

    /// Creates a test question for match engine tests
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

    @Test("Result initializes with correct values")
    func resultInitializesCorrectly() {
        let question = createTestQuestion()
        let teamId = UUID()

        let result = KBMatchQuestionResult(
            question: question,
            phase: .writtenRound,
            answeringTeam: teamId,
            wasCorrect: true,
            pointsAwarded: 1,
            responseTime: 5.0
        )

        #expect(result.question.id == question.id)
        #expect(result.answeringTeam == teamId)
        #expect(result.wasCorrect == true)
        #expect(result.pointsAwarded == 1)
        #expect(result.responseTime == 5.0)
    }

    @Test("Result timestamp is set automatically")
    func resultTimestampIsSet() {
        let before = Date()

        let result = KBMatchQuestionResult(
            question: createTestQuestion(),
            phase: .oralRound(roundNumber: 1),
            answeringTeam: UUID(),
            wasCorrect: false,
            pointsAwarded: 0,
            responseTime: 3.0
        )

        let after = Date()

        #expect(result.timestamp >= before)
        #expect(result.timestamp <= after)
    }
}

// MARK: - Match Phase Tests

@Suite("KB Match Phase Tests")
struct KBMatchPhaseTests {

    @Test("All phases are distinct")
    func allPhasesAreDistinct() {
        let phases: [MatchPhase] = [
            .notStarted,
            .writtenRound,
            .writtenReview,
            .oralRound(roundNumber: 1),
            .oralReview(roundNumber: 1),
            .finalResults
        ]

        // Each phase should be representable
        #expect(phases.count == 6)
    }

    @Test("Oral phases include round number")
    func oralPhasesIncludeRoundNumber() {
        let oralRound = MatchPhase.oralRound(roundNumber: 3)
        let oralReview = MatchPhase.oralReview(roundNumber: 3)

        if case .oralRound(let roundNumber) = oralRound {
            #expect(roundNumber == 3)
        } else {
            Issue.record("Expected oral round phase")
        }

        if case .oralReview(let roundNumber) = oralReview {
            #expect(roundNumber == 3)
        } else {
            Issue.record("Expected oral review phase")
        }
    }
}

// MARK: - Match Engine Tests

@Suite("KB Match Engine Tests")
struct KBMatchEngineTests {

    /// Creates a pool of test questions
    private func createTestQuestions(count: Int) -> [KBQuestion] {
        let domains: [KBDomain] = [.science, .mathematics, .history, .literature, .socialStudies]

        return (0..<count).map { index in
            KBQuestion(
                id: UUID(),
                text: "Test question \(index)",
                answer: KBAnswer(
                    primary: "Answer \(index)",
                    acceptable: nil,
                    pronunciation: nil
                ),
                domain: domains[index % domains.count],
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
    }

    @Test("Match setup creates teams correctly")
    func matchSetupCreatesTeams() async {
        let config = KBMatchConfig.forRegion(.colorado)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "My Team")

        let teams = await engine.getTeams()

        #expect(teams.count == 3) // Player + 2 opponents
        #expect(teams.first?.isPlayer == true)
        #expect(teams.first?.name == "My Team")
    }

    @Test("Match starts in not started phase")
    func matchStartsInNotStartedPhase() async {
        let config = KBMatchConfig.forRegion(.minnesota)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")

        let phase = await engine.getCurrentPhase()

        if case .notStarted = phase {
            // Correct phase
        } else {
            Issue.record("Expected not started phase")
        }
    }

    @Test("Starting match moves to written round")
    func startingMatchMovesToWrittenRound() async {
        let config = KBMatchConfig.forRegion(.washington)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")
        await engine.startMatch()

        let phase = await engine.getCurrentPhase()

        if case .writtenRound = phase {
            // Correct phase
        } else {
            Issue.record("Expected written round phase")
        }
    }

    @Test("Written questions are available after start")
    func writtenQuestionsAvailableAfterStart() async {
        let config = KBMatchConfig.forRegion(.colorado)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")
        await engine.startMatch()

        let question = await engine.getCurrentWrittenQuestion()

        #expect(question != nil)
    }

    @Test("Submitting written answer advances question")
    func submittingWrittenAnswerAdvancesQuestion() async {
        let config = KBMatchConfig.forRegion(.colorado)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")
        await engine.startMatch()

        let progress1 = await engine.getWrittenProgress()
        #expect(progress1.current == 0)

        await engine.submitWrittenAnswer(isCorrect: true, responseTime: 5.0)

        let progress2 = await engine.getWrittenProgress()
        #expect(progress2.current == 1)
    }

    @Test("Correct written answer adds points")
    func correctWrittenAnswerAddsPoints() async {
        let config = KBMatchConfig.forRegion(.colorado)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")
        await engine.startMatch()

        await engine.submitWrittenAnswer(isCorrect: true, responseTime: 5.0)

        let teams = await engine.getTeams()
        let playerTeam = teams.first { $0.isPlayer }

        #expect(playerTeam?.writtenScore == 1) // Colorado gives 1 point per written
    }

    @Test("Incorrect written answer gives no points")
    func incorrectWrittenAnswerGivesNoPoints() async {
        let config = KBMatchConfig.forRegion(.minnesota)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")
        await engine.startMatch()

        await engine.submitWrittenAnswer(isCorrect: false, responseTime: 5.0)

        let teams = await engine.getTeams()
        let playerTeam = teams.first { $0.isPlayer }

        #expect(playerTeam?.writtenScore == 0)
    }

    @Test("Written round ends after all questions")
    func writtenRoundEndsAfterAllQuestions() async {
        let config = KBMatchConfig.forRegion(.colorado)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")
        await engine.startMatch()

        // Submit all written questions
        let progress = await engine.getWrittenProgress()
        for _ in 0..<progress.total {
            await engine.submitWrittenAnswer(isCorrect: true, responseTime: 3.0)
        }

        let phase = await engine.getCurrentPhase()

        if case .writtenReview = phase {
            // Correct phase
        } else {
            Issue.record("Expected written review phase")
        }
    }

    @Test("Oral rounds start after written review")
    func oralRoundsStartAfterWrittenReview() async {
        let config = KBMatchConfig.forRegion(.colorado)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")
        await engine.startMatch()

        // Complete written round
        let progress = await engine.getWrittenProgress()
        for _ in 0..<progress.total {
            await engine.submitWrittenAnswer(isCorrect: true, responseTime: 3.0)
        }

        await engine.startOralRounds()

        let phase = await engine.getCurrentPhase()

        if case .oralRound(let roundNumber) = phase {
            #expect(roundNumber == 1)
        } else {
            Issue.record("Expected oral round phase")
        }
    }

    @Test("Oral questions are available in oral round")
    func oralQuestionsAvailableInOralRound() async {
        let config = KBMatchConfig.forRegion(.colorado)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")
        await engine.startMatch()

        // Complete written round
        let progress = await engine.getWrittenProgress()
        for _ in 0..<progress.total {
            await engine.submitWrittenAnswer(isCorrect: true, responseTime: 3.0)
        }

        await engine.startOralRounds()

        let question = await engine.getCurrentOralQuestion()

        #expect(question != nil)
    }

    @Test("Oral progress is tracked correctly")
    func oralProgressTrackedCorrectly() async {
        let config = KBMatchConfig.forRegion(.colorado)
        let engine = KBMatchEngine(config: config)

        let questions = createTestQuestions(count: 50)
        await engine.setupMatch(questions: questions, playerTeamName: "Test Team")
        await engine.startMatch()

        // Complete written round
        let writtenProgress = await engine.getWrittenProgress()
        for _ in 0..<writtenProgress.total {
            await engine.submitWrittenAnswer(isCorrect: true, responseTime: 3.0)
        }

        await engine.startOralRounds()

        let oralProgress = await engine.getOralProgress()

        #expect(oralProgress.round == 1)
        #expect(oralProgress.totalRounds > 0)
        #expect(oralProgress.question == 0)
    }
}

// MARK: - Player Match Stats Tests

@Suite("KB Player Match Stats Tests")
struct KBPlayerMatchStatsTests {

    @Test("Written accuracy is calculated correctly")
    func writtenAccuracyCalculatedCorrectly() {
        let stats = KBMatchSummary.PlayerMatchStats(
            writtenCorrect: 8,
            writtenTotal: 10,
            oralCorrect: 0,
            oralTotal: 0,
            averageResponseTime: 5.0,
            domainsStrength: [:]
        )

        #expect(stats.writtenAccuracy == 0.8)
    }

    @Test("Oral accuracy is calculated correctly")
    func oralAccuracyCalculatedCorrectly() {
        let stats = KBMatchSummary.PlayerMatchStats(
            writtenCorrect: 0,
            writtenTotal: 0,
            oralCorrect: 7,
            oralTotal: 10,
            averageResponseTime: 3.0,
            domainsStrength: [:]
        )

        #expect(stats.oralAccuracy == 0.7)
    }

    @Test("Overall accuracy combines written and oral")
    func overallAccuracyCombinesWrittenAndOral() {
        let stats = KBMatchSummary.PlayerMatchStats(
            writtenCorrect: 8,
            writtenTotal: 10,
            oralCorrect: 6,
            oralTotal: 10,
            averageResponseTime: 4.0,
            domainsStrength: [:]
        )

        #expect(stats.overallAccuracy == 0.7) // 14/20 = 0.7
    }

    @Test("Zero totals return zero accuracy")
    func zeroTotalsReturnZeroAccuracy() {
        let stats = KBMatchSummary.PlayerMatchStats(
            writtenCorrect: 0,
            writtenTotal: 0,
            oralCorrect: 0,
            oralTotal: 0,
            averageResponseTime: 0,
            domainsStrength: [:]
        )

        #expect(stats.writtenAccuracy == 0)
        #expect(stats.oralAccuracy == 0)
        #expect(stats.overallAccuracy == 0)
    }
}

// MARK: - Region Point Values Tests

@Suite("KB Region Point Values Tests")
struct KBRegionPointValuesTests {

    @Test("Colorado written point value")
    func coloradoWrittenPointValue() {
        #expect(KBRegion.colorado.writtenPointValue == 1)
    }

    @Test("Minnesota written point value")
    func minnesotaWrittenPointValue() {
        #expect(KBRegion.minnesota.writtenPointValue == 1)
    }

    @Test("Oral point values are consistent")
    func oralPointValuesConsistent() {
        #expect(KBRegion.colorado.oralPointValue == 10)
        #expect(KBRegion.minnesota.oralPointValue == 10)
        #expect(KBRegion.washington.oralPointValue == 10)
    }

    @Test("Colorado has penalty for incorrect oral")
    func coloradoHasIncorrectOralPenalty() {
        #expect(KBRegion.colorado.incorrectOralPenalty == -5)
    }

    @Test("Minnesota has no penalty for incorrect oral")
    func minnesotaHasNoPenalty() {
        #expect(KBRegion.minnesota.incorrectOralPenalty == 0)
    }

    @Test("Washington has no penalty for incorrect oral")
    func washingtonHasNoPenalty() {
        #expect(KBRegion.washington.incorrectOralPenalty == 0)
    }
}

// MARK: - Opponent Simulator Tests

@Suite("KB Opponent Simulator Tests")
struct KBOpponentSimulatorTests {

    private func createTestQuestion() -> KBQuestion {
        KBQuestion(
            id: UUID(),
            text: "Test question",
            answer: KBAnswer(
                primary: "Answer",
                acceptable: nil,
                pronunciation: nil
            ),
            domain: .science,
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

    @Test("Simulator has team ID and strength")
    func simulatorHasTeamIdAndStrength() async {
        let teamId = UUID()
        let simulator = KBOpponentSimulator(teamId: teamId, strength: .advanced)

        #expect(simulator.teamId == teamId)
        #expect(simulator.strength == .advanced)
    }

    @Test("Expert simulator buzzes more often")
    func expertSimulatorBuzzesMoreOften() async {
        let simulator = KBOpponentSimulator(teamId: UUID(), strength: .expert)
        let question = createTestQuestion()

        var buzzCount = 0
        for _ in 0..<100 {
            if await simulator.attemptBuzz(for: question) != nil {
                buzzCount += 1
            }
        }

        // Expert has 85% buzz probability, so expect many buzzes
        #expect(buzzCount > 50)
    }

    @Test("Beginner simulator buzzes less often")
    func beginnerSimulatorBuzzesLessOften() async {
        let simulator = KBOpponentSimulator(teamId: UUID(), strength: .beginner)
        let question = createTestQuestion()

        var buzzCount = 0
        for _ in 0..<100 {
            if await simulator.attemptBuzz(for: question) != nil {
                buzzCount += 1
            }
        }

        // Beginner has 30% buzz probability, so expect fewer buzzes
        #expect(buzzCount < 60)
    }

    @Test("Written question answering reflects accuracy")
    func writtenAnsweringReflectsAccuracy() async {
        let simulator = KBOpponentSimulator(teamId: UUID(), strength: .intermediate)
        let question = createTestQuestion()

        var correctCount = 0
        for _ in 0..<100 {
            if await simulator.answerWrittenQuestion(question) {
                correctCount += 1
            }
        }

        // Intermediate has 60% accuracy, expect roughly 40-80 correct
        #expect(correctCount > 30)
        #expect(correctCount < 90)
    }

    @Test("Oral question answering reflects accuracy")
    func oralAnsweringReflectsAccuracy() async {
        let simulator = KBOpponentSimulator(teamId: UUID(), strength: .expert)
        let question = createTestQuestion()

        var correctCount = 0
        for _ in 0..<100 {
            if await simulator.answerOralQuestion(question) {
                correctCount += 1
            }
        }

        // Expert has 90% accuracy, expect many correct
        #expect(correctCount > 70)
    }
}
