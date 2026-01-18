//
//  KBOralSessionView.swift
//  UnaMentis
//
//  Oral round practice view for Knowledge Bowl with voice interaction
//

import Combine
import SwiftUI

// MARK: - Oral Session View

struct KBOralSessionView: View {
    @ObservedObject var viewModel: KBOralSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header with progress
            sessionHeader

            // Main content
            Group {
                switch viewModel.state {
                case .notStarted:
                    startScreen
                case .readingQuestion:
                    questionReadingScreen
                case .conferenceTime:
                    conferenceScreen
                case .listeningForAnswer:
                    listeningScreen
                case .showingFeedback:
                    feedbackScreen
                case .completed:
                    summaryScreen
                }
            }
        }
        .background(Color.kbBgPrimary)
        .navigationBarBackButtonHidden(viewModel.state != .notStarted && viewModel.state != .completed)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.state != .notStarted && viewModel.state != .completed {
                    Button("End") {
                        Task { await viewModel.endSession() }
                    }
                    .foregroundColor(.kbFocusArea)
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.prepareServices()
            }
        }
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        VStack(spacing: 8) {
            // Progress bar
            progressBar

            // Question counter and score
            HStack {
                Text("Question \(viewModel.currentQuestionIndex + 1) of \(viewModel.questions.count)")
                    .font(.subheadline)
                    .foregroundColor(.kbTextSecondary)

                Spacer()

                Text("\(viewModel.session.correctCount) correct")
                    .font(.subheadline)
                    .foregroundColor(.kbMastered)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color.kbBgSecondary)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.kbBorder)
                    .frame(height: 4)

                Rectangle()
                    .fill(Color.kbMastered)
                    .frame(width: geometry.size.width * viewModel.progress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal)
    }

    // MARK: - Start Screen

    private var startScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundColor(.kbMastered)

            Text("Oral Round Practice")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.kbTextPrimary)

            Text("Questions will be read aloud. You'll have time to confer, then speak your answer.")
                .font(.body)
                .foregroundColor(.kbTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                configRow(icon: "number", label: "Questions", value: "\(viewModel.questions.count)")
                configRow(icon: "timer", label: "Conference Time", value: "\(Int(viewModel.regionalConfig.conferenceTime))s")
                configRow(icon: "mappin", label: "Region", value: viewModel.regionalConfig.region.displayName)
                configRow(icon: "star", label: "Points", value: "\(viewModel.regionalConfig.oralPointsPerCorrect) per correct")
                configRow(
                    icon: "person.2",
                    label: "Verbal Conferring",
                    value: viewModel.regionalConfig.verbalConferringAllowed ? "Allowed" : "Silent Only"
                )
            }
            .padding()
            .background(Color.kbBgSecondary)
            .cornerRadius(12)

            Spacer()

            // Permission status
            if !viewModel.hasPermissions {
                Text("Microphone and speech recognition permissions required")
                    .font(.caption)
                    .foregroundColor(.kbFocusArea)
            }

            Button(action: {
                Task { await viewModel.startSession() }
            }) {
                Text("Start Practice")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.kbMastered)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
    }

    private func configRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.kbTextSecondary)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.kbTextSecondary)
            Spacer()
            Text(value)
                .foregroundColor(.kbTextPrimary)
                .fontWeight(.medium)
        }
    }

    // MARK: - Question Reading Screen

    private var questionReadingScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            // Speaking indicator
            VStack(spacing: 16) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.kbIntermediate)
                    .symbolEffect(.variableColor.iterative, options: .repeating)

                Text("Reading Question...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.kbTextPrimary)
            }

            // Question card
            if let question = viewModel.currentQuestion {
                questionCard(question)
            }

            // TTS progress
            ProgressView(value: viewModel.ttsProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .kbIntermediate))
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Conference Screen

    private var conferenceScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            // Conference timer
            ZStack {
                Circle()
                    .stroke(Color.kbBorder, lineWidth: 8)
                    .frame(width: 150, height: 150)

                Circle()
                    .trim(from: 0, to: viewModel.conferenceProgress)
                    .stroke(
                        viewModel.conferenceTimeRemaining < 5 ? Color.kbFocusArea : Color.kbMastered,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: viewModel.conferenceProgress)

                VStack {
                    Text("\(Int(viewModel.conferenceTimeRemaining))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(viewModel.conferenceTimeRemaining < 5 ? .kbFocusArea : .kbTextPrimary)

                    Text("seconds")
                        .font(.caption)
                        .foregroundColor(.kbTextSecondary)
                }
            }

            Text("Conference Time")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.kbTextPrimary)

            Text(viewModel.regionalConfig.verbalConferringAllowed
                 ? "Discuss with your team"
                 : "Silent conferring only")
                .font(.body)
                .foregroundColor(.kbTextSecondary)

            // Question card (collapsed)
            if let question = viewModel.currentQuestion {
                questionCardCompact(question)
            }

            Spacer()

            // Skip conference button
            Button(action: {
                Task { await viewModel.skipConference() }
            }) {
                Text("Ready to Answer")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.kbIntermediate)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
    }

    // MARK: - Listening Screen

    private var listeningScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            // Listening indicator
            VStack(spacing: 16) {
                Image(systemName: viewModel.isListening ? "waveform.circle.fill" : "mic.fill")
                    .font(.system(size: 80))
                    .foregroundColor(viewModel.isListening ? .kbMastered : .kbIntermediate)
                    .symbolEffect(.bounce, value: viewModel.isListening)

                Text(viewModel.isListening ? "Listening..." : "Tap to Speak")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.kbTextPrimary)
            }

            // Error display
            if let error = viewModel.sttError {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.kbFocusArea)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.kbFocusArea.opacity(0.1))
                    .cornerRadius(8)
            }

            // Transcript display
            if !viewModel.transcript.isEmpty {
                Text(viewModel.transcript)
                    .font(.title3)
                    .foregroundColor(.kbTextPrimary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.kbBgSecondary)
                    .cornerRadius(12)
            }

            // Question card (compact)
            if let question = viewModel.currentQuestion {
                questionCardCompact(question)
            }

            Spacer()

            // Control buttons
            HStack(spacing: 16) {
                Button(action: {
                    Task { await viewModel.toggleListening() }
                }) {
                    HStack {
                        Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                        Text(viewModel.isListening ? "Stop" : "Start Listening")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isListening ? Color.kbFocusArea : Color.kbMastered)
                    .cornerRadius(12)
                }

                if !viewModel.transcript.isEmpty && !viewModel.isListening {
                    Button(action: {
                        Task { await viewModel.submitAnswer() }
                    }) {
                        Text("Submit")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.kbIntermediate)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
    }

    // MARK: - Feedback Screen

    private var feedbackScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            // Result icon
            Image(systemName: viewModel.lastAnswerCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(viewModel.lastAnswerCorrect == true ? .kbMastered : .kbFocusArea)

            Text(viewModel.lastAnswerCorrect == true ? "Correct!" : "Incorrect")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(viewModel.lastAnswerCorrect == true ? .kbMastered : .kbFocusArea)

            // Show correct answer if wrong
            if viewModel.lastAnswerCorrect != true, let question = viewModel.currentQuestion {
                VStack(spacing: 8) {
                    Text("Correct answer:")
                        .font(.subheadline)
                        .foregroundColor(.kbTextSecondary)

                    Text(question.answer.primary)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.kbTextPrimary)
                }
                .padding()
                .background(Color.kbBgSecondary)
                .cornerRadius(12)
            }

            // User's answer
            if !viewModel.transcript.isEmpty {
                VStack(spacing: 8) {
                    Text("Your answer:")
                        .font(.subheadline)
                        .foregroundColor(.kbTextSecondary)

                    Text(viewModel.transcript)
                        .font(.body)
                        .foregroundColor(.kbTextSecondary)
                }
            }

            Spacer()

            Button(action: {
                Task { await viewModel.nextQuestion() }
            }) {
                HStack {
                    Text(viewModel.isLastQuestion ? "See Results" : "Next Question")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.kbMastered)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
    }

    // MARK: - Summary Screen

    private var summaryScreen: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Result icon
                Image(systemName: viewModel.session.accuracy >= 0.7 ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 60))
                    .foregroundColor(viewModel.session.accuracy >= 0.7 ? .kbGold : .kbIntermediate)
                    .padding(.top, 40)

                // Title
                Text("Session Complete!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.kbTextPrimary)

                // Score card
                VStack(spacing: 16) {
                    summaryRow(label: "Score", value: "\(viewModel.session.correctCount)/\(viewModel.session.attempts.count)")
                    summaryRow(label: "Accuracy", value: String(format: "%.0f%%", viewModel.session.accuracy * 100))
                    summaryRow(label: "Points", value: "\(viewModel.session.totalPoints)")
                    summaryRow(label: "Time", value: formatTime(viewModel.session.duration))
                }
                .padding()
                .background(Color.kbBgSecondary)
                .cornerRadius(12)
                .padding(.horizontal)

                // Accuracy meter
                accuracyMeter

                Spacer()

                // Done button
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.kbMastered)
                        .cornerRadius(12)
                }
                .padding()
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.kbTextSecondary)
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundColor(.kbTextPrimary)
        }
    }

    private var accuracyMeter: some View {
        VStack(spacing: 8) {
            Text("Accuracy")
                .font(.headline)
                .foregroundColor(.kbTextPrimary)

            ZStack {
                Circle()
                    .stroke(Color.kbBorder, lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: viewModel.session.accuracy)
                    .stroke(
                        viewModel.session.accuracy >= 0.7 ? Color.kbMastered : Color.kbBeginner,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1), value: viewModel.session.accuracy)

                Text(String(format: "%.0f%%", viewModel.session.accuracy * 100))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.kbTextPrimary)
            }
        }
        .padding()
    }

    // MARK: - Question Cards

    private func questionCard(_ question: KBQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Domain indicator
            HStack {
                Image(systemName: question.domain.icon)
                    .foregroundColor(question.domain.color)
                Text(question.domain.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(question.domain.color)

                Spacer()

                Text(question.difficulty.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.kbBgSecondary)
                    .cornerRadius(4)
            }

            // Question text
            Text(question.text)
                .font(.title3)
                .foregroundColor(.kbTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color.kbBgSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(question.domain.color.opacity(0.3), lineWidth: 2)
        )
    }

    private func questionCardCompact(_ question: KBQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: question.domain.icon)
                    .foregroundColor(question.domain.color)
                Text(question.domain.displayName)
                    .font(.caption)
                    .foregroundColor(question.domain.color)

                Spacer()
            }

            Text(question.text)
                .font(.body)
                .foregroundColor(.kbTextSecondary)
                .lineLimit(2)
        }
        .padding()
        .background(Color.kbBgSecondary.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Oral Session View Model

@MainActor
final class KBOralSessionViewModel: ObservableObject {
    // MARK: - Published State

    @Published var session: KBSession
    @Published var questions: [KBQuestion]
    @Published var currentQuestionIndex: Int = 0
    @Published var state: KBOralSessionState = .notStarted

    // TTS State
    @Published var ttsProgress: Float = 0
    @Published var isSpeaking = false

    // STT State
    @Published var transcript = ""
    @Published var isListening = false

    // Conference State
    @Published var conferenceTimeRemaining: TimeInterval = 0
    @Published var conferenceProgress: Double = 1.0

    // Answer State
    @Published var lastAnswerCorrect: Bool?
    @Published var hasPermissions = false

    // Response Time Tracking
    private var questionStartTime: Date?

    // MARK: - Services

    private let tts = KBOnDeviceTTS()
    private let stt = KBOnDeviceSTT()
    private let validator = KBAnswerValidator()

    // MARK: - Configuration

    let config: KBSessionConfig
    let regionalConfig: KBRegionalConfig

    // MARK: - Tasks

    private var conferenceTask: Task<Void, Never>?

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

    // MARK: - Initialization

    init(questions: [KBQuestion], config: KBSessionConfig) {
        self.questions = questions
        self.config = config
        self.regionalConfig = config.region.config
        self.session = KBSession(config: config)
        self.conferenceTimeRemaining = config.region.config.conferenceTime
    }

    // MARK: - Combine Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Service Setup

    func prepareServices() async {
        // Set up TTS observation using Combine
        setupTTSObservation()

        // Check current authorization status (don't request yet)
        hasPermissions = stt.authorizationStatus == .authorized && stt.isAvailable
    }

    private func setupTTSObservation() {
        tts.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.ttsProgress = progress
            }
            .store(in: &cancellables)

        tts.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaking in
                self?.isSpeaking = speaking
            }
            .store(in: &cancellables)
    }

    private func requestPermissionsIfNeeded() async -> Bool {
        print("[KB] Oral session: requesting speech authorization...")
        let speechAuth = await stt.requestAuthorization()
        print("[KB] Oral session: speech auth = \(speechAuth)")

        print("[KB] Oral session: requesting microphone access...")
        let micAuth = await stt.requestMicrophoneAccess()
        print("[KB] Oral session: mic auth = \(micAuth)")

        hasPermissions = speechAuth && micAuth
        print("[KB] Oral session: hasPermissions = \(hasPermissions)")
        return hasPermissions
    }

    // MARK: - Session Control

    func startSession() async {
        print("[KB] Oral session: startSession() called")

        // Request permissions before starting
        print("[KB] Oral session: requesting permissions...")
        let hasPerms = await requestPermissionsIfNeeded()
        print("[KB] Oral session: permissions result = \(hasPerms)")

        guard hasPerms else {
            print("[KB] Oral session: permissions not granted, returning")
            return
        }

        print("[KB] Oral session: starting reading question...")
        state = .readingQuestion
        await readCurrentQuestion()
    }

    func endSession() async {
        conferenceTask?.cancel()
        tts.stop()
        stt.stopListening()

        session.endTime = Date()
        session.isComplete = true
        state = .completed
    }

    // MARK: - Question Flow

    private func readCurrentQuestion() async {
        guard let question = currentQuestion else {
            await endSession()
            return
        }

        state = .readingQuestion

        // Speak the question
        await tts.speakQuestion(question)

        // Start conference time
        await startConferenceTime()
    }

    private func startConferenceTime() async {
        conferenceTimeRemaining = regionalConfig.conferenceTime
        conferenceProgress = 1.0
        state = .conferenceTime

        conferenceTask = Task {
            let totalTime = regionalConfig.conferenceTime

            while conferenceTimeRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.conferenceTimeRemaining -= 0.1
                    self.conferenceProgress = max(0, self.conferenceTimeRemaining / totalTime)
                }
            }

            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.startListeningPhase()
                }
            }
        }
    }

    func skipConference() async {
        conferenceTask?.cancel()
        startListeningPhase()
    }

    private func startListeningPhase() {
        transcript = ""
        questionStartTime = Date()  // Start timing from when user can answer
        state = .listeningForAnswer
    }

    // MARK: - Voice Input

    @Published var sttError: String?

    func toggleListening() async {
        if isListening {
            stt.stopListening()
            isListening = false
        } else {
            do {
                try await stt.startListening()
                isListening = true
                sttError = nil

                // Observe transcript using Combine
                stt.$transcript
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] text in
                        self?.transcript = text
                    }
                    .store(in: &cancellables)
            } catch {
                // Handle error gracefully
                print("[KB] STT Error: \(error)")
                sttError = "Speech recognition unavailable. Please try on a physical device."
                isListening = false
            }
        }
    }

    func submitAnswer() async {
        stt.stopListening()
        isListening = false

        guard let question = currentQuestion else { return }

        // Validate answer
        let result = validator.validate(userAnswer: transcript, question: question)

        // Calculate response time from when user could start answering
        let responseTime = questionStartTime.map { Date().timeIntervalSince($0) } ?? 0

        let attempt = KBQuestionAttempt(
            questionId: question.id,
            domain: question.domain,
            userAnswer: transcript,
            responseTime: responseTime,
            wasCorrect: result.isCorrect,
            pointsEarned: result.isCorrect ? regionalConfig.oralPointsPerCorrect : 0,
            roundType: .oral,
            matchType: result.matchType
        )

        session.attempts.append(attempt)
        lastAnswerCorrect = result.isCorrect

        // Haptic feedback
        if result.isCorrect {
            KBHapticFeedback.success()
        } else {
            KBHapticFeedback.error()
        }

        state = .showingFeedback
    }

    func nextQuestion() async {
        transcript = ""
        lastAnswerCorrect = nil

        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            await readCurrentQuestion()
        } else {
            await endSession()
        }
    }
}

// MARK: - Oral Session State

enum KBOralSessionState: Equatable {
    case notStarted
    case readingQuestion
    case conferenceTime
    case listeningForAnswer
    case showingFeedback
    case completed
}

// MARK: - Preview

#if DEBUG
struct KBOralSessionView_Previews: PreviewProvider {
    static var previews: some View {
        let engine = KBQuestionEngine.preview()
        let config = KBSessionConfig.quickPractice(
            region: .colorado,
            roundType: .oral,
            questionCount: 5
        )
        let viewModel = KBOralSessionViewModel(
            questions: engine.questions,
            config: config
        )

        NavigationStack {
            KBOralSessionView(viewModel: viewModel)
        }
    }
}
#endif
