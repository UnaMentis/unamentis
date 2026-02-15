//
//  KBDomainDrillView.swift
//  UnaMentis
//
//  Domain drill view for Knowledge Bowl.
//  Allows focused practice on a single domain with progressive difficulty.
//  Supports both written-only and audio modes.
//

import AVFoundation
import Logging
import SwiftUI

// MARK: - Domain Drill View

/// Focused practice mode for a single Knowledge Bowl domain
struct KBDomainDrillView: View {
    @State private var viewModel: KBDomainDrillViewModel
    @Environment(\.dismiss) private var dismiss

    init(domain: KBDomain? = nil, config: DrillConfig = .default) {
        _viewModel = State(initialValue: KBDomainDrillViewModel(
            initialDomain: domain,
            config: config
        ))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .setup:
                setupView
            case .readingQuestion:
                readingQuestionView
            case .drilling:
                drillingView
            case .feedback:
                feedbackView
            case .results:
                resultsView
            }
        }
        .navigationTitle("Domain Drill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.state == .drilling {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") {
                        viewModel.endDrill()
                    }
                    .accessibilityLabel("End drill")
                    .accessibilityHint("Ends the current drill session and shows results")
                }
            }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Domain Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Domain")
                        .font(.headline)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(KBDomain.allCases) { domain in
                            domainButton(domain)
                        }
                    }
                }

                Divider()

                // Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.headline)

                    // Question count
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Questions: \(viewModel.questionCount)")
                                .font(.subheadline)
                            InfoButton(
                                title: "Question Count",
                                content: KBHelpContent.UIElements.questionCount
                            )
                        }
                        Slider(value: $viewModel.questionCountDouble, in: 5...30, step: 5)
                            .accessibilityLabel("Number of questions")
                            .accessibilityValue("\(viewModel.questionCount) questions")
                    }

                    // Progressive difficulty
                    HStack {
                        Toggle("Progressive Difficulty", isOn: $viewModel.progressiveDifficulty)
                        InfoButton(
                            title: "Progressive Difficulty",
                            content: KBHelpContent.TrainingModes.domainDrillProgressive
                        )
                    }

                    // Time pressure
                    HStack {
                        Toggle("Time Pressure Mode", isOn: $viewModel.timePressureMode)
                        InfoButton(
                            title: "Time Pressure",
                            content: KBHelpContent.TrainingModes.domainDrillTimePressure
                        )
                    }
                    if viewModel.timePressureMode {
                        Text("30 seconds per question")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Audio mode
                    HStack {
                        Toggle("Read Questions Aloud", isOn: $viewModel.audioMode)
                        InfoButton(
                            title: "Audio Mode",
                            content: "When enabled, questions will be read aloud using text-to-speech. The question text is still visible, so you can follow along or read ahead."
                        )
                    }
                    if viewModel.audioMode {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.blue)
                            Text("Questions will be spoken before you answer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let audioError = viewModel.audioError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(audioError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Start Button
                Button {
                    viewModel.startDrill()
                } label: {
                    Label("Start Drill", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.selectedDomain?.color ?? .gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.selectedDomain == nil)
                .accessibilityLabel("Start drill")
                .accessibilityHint(viewModel.selectedDomain != nil ?
                    "Starts a \(viewModel.selectedDomain!.displayName) domain drill" :
                    "Select a domain first")
            }
            .padding()
        }
    }

    private func domainButton(_ domain: KBDomain) -> some View {
        let isSelected = viewModel.selectedDomain == domain

        return Button {
            viewModel.selectedDomain = domain
        } label: {
            VStack(spacing: 6) {
                Image(systemName: domain.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : domain.color)

                Text(domain.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? domain.color : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? domain.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(domain.displayName) domain")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Reading Question View (Audio Mode)

    private var readingQuestionView: some View {
        VStack(spacing: 0) {
            // Progress header
            drillProgressHeader

            Divider()

            // Reading indicator
            Spacer()

            VStack(spacing: 24) {
                // Speaker animation
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(viewModel.selectedDomain?.color ?? .blue)
                    .symbolEffect(.variableColor.iterative, options: .repeating)

                Text("Reading Question...")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                // Show question text below (user can read along)
                if let question = viewModel.currentQuestion {
                    Text(question.text)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }
            }

            Spacer()
        }
    }

    // MARK: - Drilling View

    private var drillingView: some View {
        VStack(spacing: 0) {
            // Progress header
            drillProgressHeader

            Divider()

            // Question content
            if let question = viewModel.currentQuestion {
                ScrollView {
                    VStack(spacing: 24) {
                        // Timer (if time pressure mode)
                        if viewModel.timePressureMode {
                            timerView
                        }

                        // Audio mode indicator
                        if viewModel.audioMode {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.blue)
                                Text("Question was read aloud")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Question text
                        Text(question.text)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .padding()

                        // Answer options or input
                        answerInputView
                    }
                    .padding()
                }
            }

            Spacer()

            // Submit button
            if !viewModel.userAnswer.isEmpty {
                Button {
                    viewModel.submitAnswer()
                } label: {
                    Text("Submit Answer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.selectedDomain?.color ?? Color.kbExcellent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
                .accessibilityLabel("Submit answer")
                .accessibilityHint("Submits your answer for scoring")
            }
        }
    }

    private var drillProgressHeader: some View {
        HStack {
            // Domain badge
            if let domain = viewModel.selectedDomain {
                Label(domain.displayName, systemImage: domain.icon)
                    .font(.subheadline.bold())
                    .foregroundStyle(domain.color)
            }

            Spacer()

            // Progress
            Text("\(viewModel.currentIndex + 1) / \(viewModel.totalQuestions)")
                .font(.subheadline.bold())
                .monospacedDigit()

            // Score
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(viewModel.correctCount)")
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private var timerView: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)

            Circle()
                .trim(from: 0, to: viewModel.timerProgress)
                .stroke(
                    viewModel.timerProgress > 0.3 ? Color.kbExcellent : .red,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(viewModel.timeRemaining))")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(viewModel.timerProgress > 0.3 ? Color.primary : Color.red)
        }
        .frame(width: 60, height: 60)
    }

    private var answerInputView: some View {
        VStack(spacing: 12) {
            TextField("Type your answer...", text: $viewModel.userAnswer)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    if !viewModel.userAnswer.isEmpty {
                        viewModel.submitAnswer()
                    }
                }

            Text("Press Return to submit")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Feedback View

    private var feedbackView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Result indicator
            Image(systemName: viewModel.lastWasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(viewModel.lastWasCorrect ? .green : .red)

            Text(viewModel.lastWasCorrect ? "Correct!" : "Incorrect")
                .font(.largeTitle.bold())

            if let question = viewModel.lastQuestion {
                VStack(spacing: 8) {
                    if !viewModel.lastWasCorrect {
                        Text("Correct answer:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(question.answer.primary)
                            .font(.headline)
                    }

                    if let source = question.source {
                        Text("Source: \(source)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                    }
                }
                .padding()
            }

            Spacer()

            Button {
                viewModel.nextQuestion()
            } label: {
                Text(viewModel.hasMoreQuestions ? "Next Question" : "See Results")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.selectedDomain?.color ?? Color.kbExcellent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .accessibilityLabel(viewModel.hasMoreQuestions ? "Next question" : "See results")
            .accessibilityHint(viewModel.hasMoreQuestions ?
                "Advances to the next question" : "Shows your drill results")
        }
    }

    // MARK: - Results View

    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary header
                VStack(spacing: 8) {
                    if let domain = viewModel.selectedDomain {
                        Label(domain.displayName, systemImage: domain.icon)
                            .font(.headline)
                            .foregroundStyle(domain.color)
                    }

                    Text("Drill Complete!")
                        .font(.largeTitle.bold())
                }

                // Score circle
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 12)

                    Circle()
                        .trim(from: 0, to: viewModel.accuracy)
                        .stroke(
                            accuracyColor(viewModel.accuracy),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 4) {
                        Text("\(Int(viewModel.accuracy * 100))%")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        Text("\(viewModel.correctCount) / \(viewModel.totalQuestions)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 160, height: 160)

                // Stats
                HStack(spacing: 24) {
                    statCard(title: "Avg Time", value: String(format: "%.1fs", viewModel.averageTime))
                    statCard(title: "Best Streak", value: "\(viewModel.bestStreak)")
                    statCard(title: "Difficulty", value: viewModel.finalDifficulty)
                }

                Divider()

                // Performance breakdown
                if !viewModel.questionResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Question Breakdown")
                            .font(.headline)

                        ForEach(Array(viewModel.questionResults.enumerated()), id: \.offset) { index, result in
                            HStack {
                                Text("Q\(index + 1)")
                                    .font(.subheadline.bold())
                                    .frame(width: 30)

                                Image(systemName: result.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.correct ? .green : .red)

                                Text(result.question.answer.primary)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer()

                                Text(String(format: "%.1fs", result.responseTime))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        viewModel.restartDrill()
                    } label: {
                        Label("Drill Again", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.selectedDomain?.color ?? Color.kbExcellent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Drill again")
                    .accessibilityHint("Starts a new drill in the same domain")

                    Button {
                        viewModel.resetToSetup()
                    } label: {
                        Text("Choose Different Domain")
                            .font(.subheadline)
                    }
                    .accessibilityLabel("Choose different domain")
                    .accessibilityHint("Returns to domain selection")
                }
            }
            .padding()
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.8 { return .green }
        if accuracy >= 0.6 { return .orange }
        return .red
    }
}

// MARK: - Drill Config

struct DrillConfig: Sendable {
    let questionCount: Int
    let progressiveDifficulty: Bool
    let timePressureMode: Bool
    let timePerQuestion: TimeInterval
    let audioMode: Bool

    static let `default` = DrillConfig(
        questionCount: 10,
        progressiveDifficulty: true,
        timePressureMode: false,
        timePerQuestion: 30,
        audioMode: false
    )
}

// MARK: - View Model

@MainActor
@Observable
final class KBDomainDrillViewModel {
    enum State {
        case setup
        case readingQuestion  // TTS reading question (audio mode only)
        case drilling
        case feedback
        case results
    }

    // State
    private(set) var state: State = .setup

    // Setup
    var selectedDomain: KBDomain?
    var questionCountDouble: Double = 10
    var progressiveDifficulty: Bool = true
    var timePressureMode: Bool = false
    var audioMode: Bool = false  // Audio toggle for TTS question reading

    var questionCount: Int { Int(questionCountDouble) }

    // Audio
    private var announcementPlayer: AVAudioPlayer?
    private var speakingTask: Task<Void, Never>?
    private(set) var isSpeaking: Bool = false
    private(set) var audioError: String?

    private static let logger = Logger(label: "com.unamentis.kb.domaindrill")

    // Drilling
    private(set) var questions: [KBQuestion] = []
    private(set) var currentIndex: Int = 0
    private(set) var totalQuestions: Int = 0
    private(set) var correctCount: Int = 0
    var userAnswer: String = ""

    // Timer
    private(set) var timeRemaining: TimeInterval = 30
    private(set) var timerProgress: CGFloat = 1.0
    private var timer: Timer?
    private var questionStartTime: Date?

    // Feedback
    private(set) var lastWasCorrect: Bool = false
    private(set) var lastQuestion: KBQuestion?

    // Results
    private(set) var questionResults: [QuestionResult] = []
    private(set) var bestStreak: Int = 0
    private var currentStreak: Int = 0

    struct QuestionResult {
        let question: KBQuestion
        let correct: Bool
        let responseTime: TimeInterval
    }

    var currentQuestion: KBQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var hasMoreQuestions: Bool {
        currentIndex < questions.count - 1
    }

    var accuracy: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(correctCount) / Double(totalQuestions)
    }

    var averageTime: TimeInterval {
        guard !questionResults.isEmpty else { return 0 }
        return questionResults.reduce(0) { $0 + $1.responseTime } / Double(questionResults.count)
    }

    var finalDifficulty: String {
        if progressiveDifficulty {
            let level = min(5, 1 + correctCount / 3)
            return "Level \(level)"
        }
        return "Standard"
    }

    init(initialDomain: KBDomain?, config: DrillConfig) {
        self.selectedDomain = initialDomain
        self.questionCountDouble = Double(config.questionCount)
        self.progressiveDifficulty = config.progressiveDifficulty
        self.timePressureMode = config.timePressureMode
        self.timeRemaining = config.timePerQuestion
        self.audioMode = config.audioMode
    }

    // MARK: - Actions

    func startDrill() {
        guard let domain = selectedDomain else { return }

        // Generate questions for the domain
        questions = generateQuestions(for: domain, count: questionCount)
        totalQuestions = questions.count
        currentIndex = 0
        correctCount = 0
        questionResults = []
        bestStreak = 0
        currentStreak = 0
        userAnswer = ""
        audioError = nil

        // Start drill with or without audio
        if audioMode {
            Task {
                state = .readingQuestion
                await speakCurrentQuestion()
            }
        } else {
            state = .drilling
            startQuestionTimer()
        }
    }

    /// Speak the current question via the configured TTS provider
    private func speakCurrentQuestion() async {
        guard let question = currentQuestion else {
            // Fall through to drilling state if no question
            state = .drilling
            startQuestionTimer()
            return
        }

        isSpeaking = true

        // TTFA: mark activation for drill mode audio
        await TTFAInstrumentation.shared.markActivation(.kbDrill)

        let ttsService = TTSProvider.resolveConfiguredService()

        do {
            let stream = try await ttsService.synthesize(text: question.text)

            // Collect all audio chunks
            var audioData = Data()
            var isFirstChunk = true
            for await chunk in stream {
                guard !Task.isCancelled else {
                    isSpeaking = false
                    return
                }
                audioData.append(chunk.audioData)
                if isFirstChunk {
                    // TTFA: mark first TTS chunk received
                    await TTFAInstrumentation.shared.markTTSFirstChunk()
                    isFirstChunk = false
                }
            }

            guard !audioData.isEmpty, !Task.isCancelled else {
                isSpeaking = false
                state = .drilling
                startQuestionTimer()
                return
            }

            // TTFA: mark audio scheduled (AVAudioPlayer path)
            await TTFAInstrumentation.shared.markAudioScheduled()

            // Play the collected audio
            announcementPlayer = try AVAudioPlayer(data: audioData)
            announcementPlayer?.play()

            // TTFA: mark audio playing
            await TTFAInstrumentation.shared.markAudioPlaying()

            // Wait for playback to complete
            if let duration = announcementPlayer?.duration {
                try await Task.sleep(for: .milliseconds(Int(duration * 1000) + 50))
            }

            announcementPlayer = nil
        } catch {
            Self.logger.error("TTS failed for question reading: \(error.localizedDescription)")
            audioError = error.localizedDescription
            announcementPlayer = nil
        }

        isSpeaking = false

        // Transition to drilling state after TTS completes
        state = .drilling
        startQuestionTimer()
    }

    /// Stop any ongoing speech playback
    private func stopSpeech() {
        speakingTask?.cancel()
        speakingTask = nil
        announcementPlayer?.stop()
        announcementPlayer = nil
        isSpeaking = false
    }

    func submitAnswer() {
        guard let question = currentQuestion else { return }

        stopTimer()

        let responseTime = questionStartTime.map { Date().timeIntervalSince($0) } ?? 0

        // Check answer
        let isCorrect = checkAnswer(userAnswer, against: question)

        if isCorrect {
            correctCount += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
        } else {
            currentStreak = 0
        }

        questionResults.append(QuestionResult(
            question: question,
            correct: isCorrect,
            responseTime: responseTime
        ))

        lastWasCorrect = isCorrect
        lastQuestion = question
        userAnswer = ""

        state = .feedback
    }

    func nextQuestion() {
        if hasMoreQuestions {
            currentIndex += 1
            if audioMode {
                // Read the next question with TTS
                Task {
                    state = .readingQuestion
                    await speakCurrentQuestion()
                }
            } else {
                state = .drilling
                startQuestionTimer()
            }
        } else {
            stopSpeech()
            state = .results
        }
    }

    func endDrill() {
        stopTimer()
        totalQuestions = questionResults.count
        stopSpeech()
        state = .results
    }

    func restartDrill() {
        startDrill()
    }

    func resetToSetup() {
        stopTimer()
        stopSpeech()
        state = .setup
    }

    // MARK: - Timer

    private func startQuestionTimer() {
        questionStartTime = Date()

        guard timePressureMode else { return }

        timeRemaining = 30
        timerProgress = 1.0

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimer()
            }
        }
    }

    private func updateTimer() {
        timeRemaining -= 0.1
        timerProgress = timeRemaining / 30.0

        if timeRemaining <= 0 {
            submitAnswer() // Auto-submit with empty answer
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    private func generateQuestions(for domain: KBDomain, count: Int) -> [KBQuestion] {
        // Generate sample questions for the domain
        (0..<count).map { index in
            KBQuestion(
                id: UUID(),
                text: "Sample \(domain.displayName) question #\(index + 1). What is the answer to this knowledge question?",
                answer: KBAnswer(
                    primary: "Sample Answer \(index + 1)",
                    acceptable: nil,
                    answerType: .text
                ),
                domain: domain,
                subdomain: nil,
                difficulty: progressiveDifficulty ? .foundational : .varsity,
                source: "Sample Question Bank"
            )
        }
    }

    private func checkAnswer(_ userAnswer: String, against question: KBQuestion) -> Bool {
        let normalized = userAnswer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let correct = question.answer.primary.lowercased()

        // Exact match
        if normalized == correct {
            return true
        }

        // Check acceptable alternatives
        if let acceptable = question.answer.acceptable {
            for alternate in acceptable {
                if normalized == alternate.lowercased() {
                    return true
                }
            }
        }

        // Partial match (at least 80% of characters match)
        let similarity = stringSimilarity(normalized, correct)
        return similarity >= 0.8
    }

    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let longer = s1.count > s2.count ? s1 : s2
        let shorter = s1.count > s2.count ? s2 : s1

        guard !longer.isEmpty else { return 1.0 }

        let distance = levenshteinDistance(Array(longer), Array(shorter))
        return Double(longer.count - distance) / Double(longer.count)
    }

    private func levenshteinDistance(_ s1: [Character], _ s2: [Character]) -> Int {
        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[m][n]
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        KBDomainDrillView()
    }
}
