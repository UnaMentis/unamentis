//
//  KBSession.swift
//  UnaMentis
//
//  Practice session model for Knowledge Bowl
//

import Foundation

// MARK: - Practice Session

/// A Knowledge Bowl practice session
struct KBSession: Codable, Identifiable {
    let id: UUID
    let config: KBSessionConfig
    let startTime: Date
    var endTime: Date?
    var attempts: [KBQuestionAttempt]
    var currentQuestionIndex: Int
    var isComplete: Bool

    init(
        id: UUID = UUID(),
        config: KBSessionConfig,
        startTime: Date = Date()
    ) {
        self.id = id
        self.config = config
        self.startTime = startTime
        self.endTime = nil
        self.attempts = []
        self.currentQuestionIndex = 0
        self.isComplete = false
    }

    // MARK: - Computed Properties

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var correctCount: Int {
        attempts.filter { $0.wasCorrect }.count
    }

    var incorrectCount: Int {
        attempts.filter { !$0.wasCorrect }.count
    }

    var totalPoints: Int {
        attempts.reduce(0) { $0 + $1.pointsEarned }
    }

    var accuracy: Double {
        guard !attempts.isEmpty else { return 0 }
        return Double(correctCount) / Double(attempts.count)
    }

    var averageResponseTime: TimeInterval {
        guard !attempts.isEmpty else { return 0 }
        return attempts.reduce(0) { $0 + $1.responseTime } / Double(attempts.count)
    }

    /// Progress through the session (0.0 to 1.0)
    var progress: Double {
        guard config.questionCount > 0 else { return 0 }
        return Double(attempts.count) / Double(config.questionCount)
    }

    /// Time remaining in session (if time-limited)
    func timeRemaining(from currentTime: Date = Date()) -> TimeInterval? {
        guard let timeLimit = config.timeLimit else { return nil }
        let elapsed = currentTime.timeIntervalSince(startTime)
        return max(0, timeLimit - elapsed)
    }

    /// Timer state based on remaining time
    func timerState(from currentTime: Date = Date()) -> KBTimerState? {
        guard let timeLimit = config.timeLimit, timeLimit > 0 else { return nil }
        guard let remaining = timeRemaining(from: currentTime) else { return nil }
        let percent = remaining / timeLimit
        return KBTimerState.from(remainingPercent: percent)
    }

    // MARK: - Domain Performance

    /// Accuracy breakdown by domain
    var performanceByDomain: [KBDomain: DomainPerformance] {
        var stats: [KBDomain: (correct: Int, total: Int, time: TimeInterval)] = [:]

        for attempt in attempts {
            let domain = attempt.domain
            var current = stats[domain] ?? (correct: 0, total: 0, time: 0)
            current.total += 1
            if attempt.wasCorrect {
                current.correct += 1
            }
            current.time += attempt.responseTime
            stats[domain] = current
        }

        var result: [KBDomain: DomainPerformance] = [:]
        for (domain, stat) in stats {
            let avgTime = stat.total > 0 ? stat.time / Double(stat.total) : 0
            result[domain] = DomainPerformance(
                domain: domain,
                correct: stat.correct,
                total: stat.total,
                averageTime: avgTime
            )
        }

        return result
    }
}

// MARK: - Domain Performance

struct DomainPerformance: Codable {
    let domain: KBDomain
    let correct: Int
    let total: Int
    let averageTime: TimeInterval

    var accuracy: Double {
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total)
    }
}

// MARK: - Session Summary

/// Summary of a completed session
struct KBSessionSummary: Codable {
    let sessionId: UUID
    let roundType: KBRoundType
    let region: KBRegion
    let totalQuestions: Int
    let totalCorrect: Int
    let totalPoints: Int
    let accuracy: Double
    let averageResponseTime: TimeInterval
    let duration: TimeInterval
    let completedAt: Date

    init(from session: KBSession) {
        self.sessionId = session.id
        self.roundType = session.config.roundType
        self.region = session.config.region
        self.totalQuestions = session.attempts.count
        self.totalCorrect = session.correctCount
        self.totalPoints = session.totalPoints
        self.accuracy = session.accuracy
        self.averageResponseTime = session.averageResponseTime
        self.duration = session.duration
        self.completedAt = session.endTime ?? Date()
    }
}

// MARK: - Session State

/// Current state of an active session
enum KBSessionState: Equatable {
    case notStarted
    case inProgress(questionIndex: Int)
    case paused
    case reviewing(attemptIndex: Int)
    case completed
    case expired  // Time ran out
}

// MARK: - Written Session View Model

/// ViewModel for managing a written practice session
@MainActor
final class KBWrittenSessionViewModel: ObservableObject {
    // MARK: - Published State

    @Published var session: KBSession
    @Published var questions: [KBQuestion]
    @Published var currentQuestionIndex: Int = 0
    @Published var selectedAnswer: Int? = nil
    @Published var showingFeedback = false
    @Published var lastAnswerCorrect: Bool? = nil
    @Published var state: KBSessionState = .notStarted

    // MARK: - Timer

    @Published var remainingTime: TimeInterval = 0
    @Published var timerState: KBTimerState = .normal
    private var timerTask: Task<Void, Never>?

    // MARK: - Pause Tracking

    private var pauseStart: Date?
    private var accumulatedPausedTime: TimeInterval = 0

    // MARK: - Question Timing

    private var questionStartTime: Date?

    // MARK: - Configuration

    let config: KBSessionConfig
    let regionalConfig: KBRegionalConfig

    // MARK: - Computed Properties

    var currentQuestion: KBQuestion? {
        guard currentQuestionIndex < questions.count else { return nil }
        return questions[currentQuestionIndex]
    }

    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(currentQuestionIndex) / Double(questions.count)
    }

    var isLastQuestion: Bool {
        currentQuestionIndex >= questions.count - 1
    }

    var questionsRemaining: Int {
        max(0, questions.count - currentQuestionIndex)
    }

    // MARK: - Initialization

    init(questions: [KBQuestion], config: KBSessionConfig) {
        self.questions = questions
        self.config = config
        self.regionalConfig = config.region.config
        self.session = KBSession(config: config)

        if let timeLimit = config.timeLimit {
            self.remainingTime = timeLimit
        }
    }

    // MARK: - Session Control

    func startSession() {
        state = .inProgress(questionIndex: 0)
        questionStartTime = Date()
        startTimer()
    }

    func pauseSession() {
        pauseStart = Date()
        state = .paused
        stopTimer()
    }

    func resumeSession() {
        if let pauseStart = pauseStart {
            accumulatedPausedTime += Date().timeIntervalSince(pauseStart)
            self.pauseStart = nil
        }
        state = .inProgress(questionIndex: currentQuestionIndex)
        startTimer()
    }

    func endSession(expired: Bool = false) {
        stopTimer()
        session.endTime = Date()
        session.isComplete = true
        state = expired ? .expired : .completed
    }

    // MARK: - Timer

    private func startTimer() {
        guard config.timeLimit != nil else { return }

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    guard case .inProgress = self.state else { return }

                    if let timeLimit = self.config.timeLimit {
                        let elapsed = Date().timeIntervalSince(self.session.startTime) - self.accumulatedPausedTime
                        let remaining = max(0, timeLimit - elapsed)
                        self.remainingTime = remaining
                        self.timerState = self.session.timerState() ?? .normal

                        if remaining <= 0 {
                            self.endSession(expired: true)
                        }
                    }
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Answer Handling

    func selectAnswer(_ index: Int) {
        guard !showingFeedback else { return }
        selectedAnswer = index
    }

    func submitAnswer() {
        guard let selectedAnswer = selectedAnswer,
              let question = currentQuestion,
              let questionStartTime = questionStartTime else { return }

        let responseTime = Date().timeIntervalSince(questionStartTime)
        let isCorrect = checkAnswer(selectedIndex: selectedAnswer, question: question)
        let points = isCorrect ? regionalConfig.writtenPointsPerCorrect : 0

        let attempt = KBQuestionAttempt(
            questionId: question.id,
            domain: question.domain,
            selectedChoice: selectedAnswer,
            responseTime: responseTime,
            wasCorrect: isCorrect,
            pointsEarned: points,
            roundType: .written,
            matchType: .exact
        )

        session.attempts.append(attempt)
        lastAnswerCorrect = isCorrect
        showingFeedback = true
    }

    func nextQuestion() {
        showingFeedback = false
        selectedAnswer = nil
        lastAnswerCorrect = nil

        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            questionStartTime = Date()  // Reset for next question
            state = .inProgress(questionIndex: currentQuestionIndex)
        } else {
            endSession()
        }
    }

    private func checkAnswer(selectedIndex: Int, question: KBQuestion) -> Bool {
        guard let options = question.mcqOptions,
              selectedIndex < options.count else { return false }

        let selectedOption = options[selectedIndex]
        return selectedOption.lowercased() == question.answer.primary.lowercased()
    }

    // MARK: - Summary

    var summary: KBSessionSummary {
        KBSessionSummary(from: session)
    }
}
