// UnaMentis - Knowledge Bowl Practice Engine
// Manages the flow of practice sessions
//
// Handles question selection, timing, and scoring for
// different practice modes.

import Foundation
import Logging

/// Manages a Knowledge Bowl practice session
@MainActor
final class KBPracticeEngine: ObservableObject {
    // MARK: - Published State

    @Published private(set) var currentQuestion: KBQuestion?
    @Published private(set) var questionIndex: Int = 0
    @Published private(set) var totalQuestions: Int = 0
    @Published private(set) var results: [KBQuestionResult] = []
    @Published private(set) var sessionState: SessionState = .notStarted
    @Published private(set) var timeRemaining: TimeInterval = 0
    @Published private(set) var questionStartTime: Date?

    // MARK: - Session Configuration

    private var questions: [KBQuestion] = []
    private var mode: KBStudyMode = .diagnostic
    private var sessionStartTime: Date?
    private var timer: Timer?

    private static let logger = Logger(label: "com.unamentis.kb.practice.engine")

    // MARK: - Session State

    enum SessionState: Equatable {
        case notStarted
        case inProgress
        case showingAnswer(isCorrect: Bool)
        case completed
    }

    // MARK: - Initialization

    init() {}

    // Note: No deinit needed - timer uses [weak self] so deallocation is safe.
    // The timer will auto-invalidate when no strong references remain.

    // MARK: - Session Control

    /// Start a new practice session with the given questions and mode
    func startSession(questions: [KBQuestion], mode: KBStudyMode) {
        // Stop any existing timer from previous session
        stopTimer()
        timeRemaining = 0

        self.questions = mode == .diagnostic ? questions : questions.shuffled()
        self.mode = mode
        self.totalQuestions = min(questions.count, questionCountForMode(mode))
        self.questionIndex = 0
        self.results = []
        self.sessionStartTime = Date()
        self.sessionState = .inProgress

        // Set time limit for speed modes
        if mode == .speed {
            timeRemaining = 300  // 5 minutes for speed drill
            startTimer()
        }

        presentNextQuestion()
        Self.logger.info("Started \(mode.rawValue) session with \(totalQuestions) questions")
    }

    /// Submit an answer for the current question
    func submitAnswer(_ answer: String) {
        guard let question = currentQuestion,
              let startTime = questionStartTime,
              sessionState == .inProgress else {
            return
        }

        let responseTime = Date().timeIntervalSince(startTime)
        let result = KBQuestionResult(
            question: question,
            userAnswer: answer,
            responseTimeSeconds: responseTime
        )

        results.append(result)
        sessionState = .showingAnswer(isCorrect: result.isCorrect)

        Self.logger.debug("Answer submitted: \(result.isCorrect ? "correct" : "incorrect") in \(String(format: "%.1f", responseTime))s")
    }

    /// Skip the current question
    func skipQuestion() {
        guard let question = currentQuestion,
              sessionState == .inProgress else {
            return
        }

        let result = KBQuestionResult(
            question: question,
            userAnswer: "",
            responseTimeSeconds: 0,
            wasSkipped: true
        )

        results.append(result)
        sessionState = .showingAnswer(isCorrect: false)

        Self.logger.debug("Question skipped")
    }

    /// Move to the next question after viewing the answer
    func nextQuestion() {
        // Only advance when showing an answer, not during question presentation
        guard case .showingAnswer = sessionState else {
            return
        }

        questionIndex += 1

        if questionIndex >= totalQuestions || (mode == .speed && timeRemaining <= 0) {
            endSession()
        } else {
            sessionState = .inProgress
            presentNextQuestion()
        }
    }

    /// End the session early
    func endSessionEarly() {
        endSession()
    }

    // MARK: - Session Summary

    /// Generate a summary of the completed session
    func generateSummary() -> KBSessionSummary {
        let correctCount = results.filter { $0.isCorrect }.count
        // Exclude skipped questions from average time calculation
        let answeredResults = results.filter { !$0.wasSkipped }
        let avgTime = answeredResults.isEmpty ? 0 : answeredResults.map { $0.responseTimeSeconds }.reduce(0, +) / Double(answeredResults.count)
        let speedTargetCount = results.filter { $0.wasWithinSpeedTarget }.count

        var domainBreakdown: [String: KBSessionSummary.DomainScore] = [:]
        for result in results {
            let domainId = result.question.domainId
            var score = domainBreakdown[domainId] ?? KBSessionSummary.DomainScore(total: 0, correct: 0)
            score = KBSessionSummary.DomainScore(
                total: score.total + 1,
                correct: score.correct + (result.isCorrect ? 1 : 0)
            )
            domainBreakdown[domainId] = score
        }

        let duration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0

        return KBSessionSummary(
            totalQuestions: results.count,
            correctAnswers: correctCount,
            averageResponseTime: avgTime,
            questionsWithinSpeedTarget: speedTargetCount,
            domainBreakdown: domainBreakdown,
            duration: duration
        )
    }

    // MARK: - Private Helpers

    private func questionCountForMode(_ mode: KBStudyMode) -> Int {
        switch mode {
        case .diagnostic: return 50
        case .targeted: return 25
        case .breadth: return 36
        case .speed: return 20
        case .competition: return 45
        case .team: return 45
        }
    }

    private func presentNextQuestion() {
        guard questionIndex < questions.count && questionIndex < totalQuestions else {
            endSession()
            return
        }

        currentQuestion = questions[questionIndex]
        questionStartTime = Date()
    }

    private func endSession() {
        stopTimer()
        sessionState = .completed
        Self.logger.info("Session completed: \(results.filter { $0.isCorrect }.count)/\(results.count) correct")
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tickTimer() {
        guard timeRemaining > 0 else {
            endSession()
            return
        }
        timeRemaining -= 1
    }
}
