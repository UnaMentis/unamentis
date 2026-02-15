//
//  KBReboundTrainingView.swift
//  UnaMentis
//
//  Rebound training mode for Knowledge Bowl.
//  Trains students to capitalize on opponent misses.
//  Supports both written-only and audio modes.
//

import AVFoundation
import SwiftUI

// MARK: - Rebound Training View

/// Main view for rebound training mode
struct KBReboundTrainingView: View {
    @State private var viewModel: KBReboundTrainingViewModel
    @Environment(\.dismiss) private var dismiss

    init(region: KBRegion, questions: [KBQuestion]) {
        _viewModel = State(initialValue: KBReboundTrainingViewModel(region: region, questions: questions))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .setup:
                    setupView
                case .waitingForOpponent:
                    waitingView
                case .opponentAnswering:
                    opponentAnsweringView
                case .reboundOpportunity:
                    reboundOpportunityView
                case .userTurn:
                    userTurnView
                case .feedback:
                    feedbackView
                case .results:
                    resultsView
                }
            }
            .navigationTitle("Rebound Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.kbExcellent)

                    Text("Rebound Training")
                        .font(.title2.bold())

                    Text("Practice capitalizing on opponent misses")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Explanation Card
                explanationCard

                // Settings Card
                settingsCard

                // Start Button
                Button {
                    viewModel.startTraining()
                } label: {
                    Label("Start Training", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.kbExcellent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                // Practice Scenarios Button
                Button {
                    viewModel.showPracticeScenarios()
                } label: {
                    Label("View Practice Scenarios", systemImage: "book.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.kbStrong.opacity(0.2))
                        .foregroundStyle(Color.kbStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .sheet(isPresented: $viewModel.showingPracticeScenarios) {
            practiceScenarioSheet
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.kbExcellent)
                Text("How Rebounds Work")
                    .font(.headline)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                reboundExplanationRow(
                    icon: "1.circle.fill",
                    text: "Opponent buzzes and answers"
                )
                reboundExplanationRow(
                    icon: "2.circle.fill",
                    text: "If wrong, it's a rebound opportunity"
                )
                reboundExplanationRow(
                    icon: "3.circle.fill",
                    text: "Decide: buzz for points or hold strategically"
                )
            }

            Divider()

            Text("Key Strategy: Don't buzz unless you're confident. A wrong rebound costs points!")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func reboundExplanationRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.kbExcellent)
            Text(text)
                .font(.subheadline)
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opponent Accuracy: \(Int(viewModel.opponentAccuracy * 100))%")
                        .font(.subheadline)
                    InfoButton(
                        title: "Opponent Accuracy",
                        content: KBHelpContent.TrainingModes.matchOpponents
                    )
                }
                Slider(value: $viewModel.opponentAccuracy, in: 0.3...0.9, step: 0.1)
                    .tint(Color.kbExcellent)
                Text("Lower = more rebound opportunities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Rebound Probability: \(Int(viewModel.reboundProbability * 100))%")
                        .font(.subheadline)
                    InfoButton(
                        title: "Rebound Probability",
                        content: KBHelpContent.TrainingModes.reboundProbability
                    )
                }
                Slider(value: $viewModel.reboundProbability, in: 0.3...0.8, step: 0.1)
                    .tint(Color.kbExcellent)
                Text("Chance opponent buzzes first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Show Opponent's Answer", isOn: $viewModel.showOpponentAnswer)
                .tint(Color.kbExcellent)

            Stepper("Questions: \(viewModel.questionCount)", value: $viewModel.questionCount, in: 5...30, step: 5)

            Divider()

            // Audio mode
            HStack {
                Toggle("Read Questions Aloud", isOn: $viewModel.audioMode)
                    .tint(Color.kbExcellent)
                InfoButton(
                    title: "Audio Mode",
                    content: "When enabled, questions will be read aloud during the 'Reading question' phase. This simulates real competition conditions."
                )
            }
            if viewModel.audioMode {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.kbExcellent)
                    Text("Questions spoken during reading phase")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var practiceScenarioSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(KBReboundSimulator.generatePracticeScenarios(), id: \.scenario) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.scenario)
                                .font(.body)

                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                Text(item.tip)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Practice Scenarios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.showingPracticeScenarios = false
                    }
                }
            }
        }
    }

    // MARK: - Training Views

    private var waitingView: some View {
        VStack(spacing: 24) {
            progressHeader

            Spacer()

            VStack(spacing: 16) {
                // Show speaker animation if audio mode is on and speaking
                if viewModel.audioMode && viewModel.isSpeaking {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.kbExcellent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                } else {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.isSpeaking ? "Reading question aloud..." : "Reading question...")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let question = viewModel.currentQuestion {
                    questionCard(question)
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            viewModel.simulateOpponent()
        }
    }

    private var opponentAnsweringView: some View {
        VStack(spacing: 24) {
            progressHeader

            Spacer()

            VStack(spacing: 16) {
                // Opponent buzzing animation
                Image(systemName: "bell.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce.byLayer, options: .repeating)

                Text("\(viewModel.opponentName) BUZZED!")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)

                if let question = viewModel.currentQuestion {
                    questionCard(question)
                }

                if let scenario = viewModel.currentScenario, viewModel.showOpponentAnswer {
                    VStack(spacing: 8) {
                        Text("Their answer:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(scenario.opponentAnswer ?? "...")
                            .font(.title3.bold())
                            .foregroundStyle(scenario.opponentWasCorrect ? .green : .red)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Spacer()
        }
        .padding()
    }

    private var reboundOpportunityView: some View {
        VStack(spacing: 24) {
            progressHeader

            Spacer()

            VStack(spacing: 16) {
                // Rebound alert
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.kbExcellent)
                    .symbolEffect(.pulse, options: .repeating)

                HStack {
                    Text("REBOUND OPPORTUNITY!")
                        .font(.title2.bold())
                        .foregroundStyle(Color.kbExcellent)

                    InfoButton(
                        title: "Rebound Strategy",
                        content: KBHelpContent.TrainingModes.reboundStrategy
                    )
                }

                Text("\(viewModel.opponentName) got it WRONG")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let question = viewModel.currentQuestion {
                    questionCard(question)
                }

                // Decision buttons
                VStack(spacing: 12) {
                    Button {
                        viewModel.buzzOnRebound()
                    } label: {
                        HStack {
                            Image(systemName: "bell.fill")
                            Text("BUZZ!")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.kbExcellent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        viewModel.holdStrategically()
                    } label: {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                            Text("Hold (Don't know)")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            // Timer
            if viewModel.reboundTimeRemaining > 0 {
                Text("Time remaining: \(String(format: "%.1f", viewModel.reboundTimeRemaining))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var userTurnView: some View {
        VStack(spacing: 24) {
            progressHeader

            Spacer()

            VStack(spacing: 16) {
                Text("Your turn to answer!")
                    .font(.title3.bold())

                if let question = viewModel.currentQuestion {
                    questionCard(question)
                }

                // Answer options
                VStack(spacing: 12) {
                    Button {
                        viewModel.submitAnswer(wasCorrect: true)
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("I Got It Right")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        viewModel.submitAnswer(wasCorrect: false)
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("I Got It Wrong")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)

                // Show correct answer hint
                if let question = viewModel.currentQuestion {
                    VStack(spacing: 4) {
                        Text("Correct answer:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(question.answer.primary)
                            .font(.subheadline.bold())
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer()
        }
        .padding()
    }

    private var feedbackView: some View {
        VStack(spacing: 24) {
            progressHeader

            Spacer()

            if let feedback = viewModel.lastFeedback {
                VStack(spacing: 16) {
                    Image(systemName: feedback.icon)
                        .font(.system(size: 60))
                        .foregroundStyle(feedback.color)

                    Text(feedback.title)
                        .font(.title2.bold())

                    Text(feedback.message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    if feedback.points != 0 {
                        Text("\(feedback.points > 0 ? "+" : "")\(feedback.points) points")
                            .font(.title3.bold())
                            .foregroundStyle(feedback.points > 0 ? .green : .red)
                    }
                }
            }

            Spacer()

            Button {
                viewModel.nextQuestion()
            } label: {
                Text("Next Question")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.kbExcellent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Results View

    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                resultHeader

                statsCards

                if let result = viewModel.trainingResult {
                    recommendationCard(result.recommendation)
                }

                // Actions
                VStack(spacing: 12) {
                    Button {
                        viewModel.restartTraining()
                    } label: {
                        Label("Train Again", systemImage: "arrow.counterclockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.kbExcellent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }

    // MARK: - Shared Components

    private var progressHeader: some View {
        HStack {
            Text("vs \(viewModel.opponentName)")
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(Capsule())

            Spacer()

            Text("\(viewModel.currentQuestionIndex + 1)/\(viewModel.totalQuestions)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(viewModel.totalPoints) pts")
                .font(.subheadline.bold())
                .foregroundStyle(viewModel.totalPoints >= 0 ? .green : .red)
        }
    }

    private func questionCard(_ question: KBQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(question.domain.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(question.domain.color.opacity(0.2))
                    .foregroundStyle(question.domain.color)
                    .clipShape(Capsule())

                Spacer()

                Text(question.difficulty.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(question.text)
                .font(.body)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var resultHeader: some View {
        VStack(spacing: 12) {
            let stats = viewModel.trainingResult?.stats

            Image(systemName: resultIcon(for: stats?.reboundAccuracy ?? 0))
                .font(.system(size: 60))
                .foregroundStyle(resultColor(for: stats?.reboundAccuracy ?? 0))

            Text(resultTitle(for: stats?.reboundAccuracy ?? 0))
                .font(.title.bold())

            if let stats = stats {
                Text("\(stats.reboundsCorrect)/\(stats.reboundsTaken) rebounds correct")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resultIcon(for accuracy: Double) -> String {
        if accuracy >= 0.8 { return "star.fill" }
        if accuracy >= 0.6 { return "hand.thumbsup.fill" }
        return "arrow.up.circle.fill"
    }

    private func resultColor(for accuracy: Double) -> Color {
        if accuracy >= 0.8 { return .yellow }
        if accuracy >= 0.6 { return .green }
        return .blue
    }

    private func resultTitle(for accuracy: Double) -> String {
        if accuracy >= 0.8 { return "Rebound Master!" }
        if accuracy >= 0.6 { return "Good Instincts!" }
        return "Keep Practicing!"
    }

    private var statsCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let stats = viewModel.trainingResult?.stats {
                statCard("Total Points", value: "\(stats.totalPoints)", icon: "star.fill")
                statCard("Rebound Accuracy", value: "\(Int(stats.reboundAccuracy * 100))%", icon: "target")
                statCard("Opportunities", value: "\(stats.reboundOpportunities)", icon: "arrow.uturn.backward")
                statCard("Rebounds Taken", value: "\(stats.reboundsTaken)", icon: "bell.fill")
                statCard("Strategic Holds", value: "\(stats.strategicHolds)", icon: "hand.raised.fill")
                statCard("Avg Response", value: String(format: "%.1fs", stats.averageResponseTime), icon: "clock")
            }
        }
        .padding(.horizontal)
    }

    private func statCard(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.kbExcellent)

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func recommendationCard(_ recommendation: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.title2)
                .foregroundStyle(.yellow)

            Text(recommendation)
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Feedback Model

struct ReboundFeedback {
    let title: String
    let message: String
    let icon: String
    let color: Color
    let points: Int
}

// MARK: - Training Result

struct KBReboundTrainingResult {
    let sessionId: UUID
    let region: KBRegion
    let startTime: Date
    let endTime: Date
    let stats: KBReboundStats
    let recommendation: String

    static func generateRecommendation(from stats: KBReboundStats) -> String {
        if stats.reboundAccuracy >= 0.8 {
            return "Excellent rebound instincts! You're capitalizing on opponent mistakes effectively."
        } else if stats.missedOpportunities > stats.reboundsTaken {
            return "Try to be more aggressive on rebounds. You're missing opportunities to score."
        } else if stats.reboundAccuracy < 0.5 {
            return "Focus on only buzzing when confident. A wrong rebound costs points."
        } else {
            return "Good balance between aggression and caution. Keep practicing!"
        }
    }
}

// MARK: - View Model

@MainActor
@Observable
final class KBReboundTrainingViewModel {

    // MARK: - State

    enum TrainingState {
        case setup
        case waitingForOpponent
        case opponentAnswering
        case reboundOpportunity
        case userTurn
        case feedback
        case results
    }

    private(set) var state: TrainingState = .setup
    private var simulator: KBReboundSimulator
    private var questions: [KBQuestion]

    // Setup options
    var opponentAccuracy: Double = 0.6
    var reboundProbability: Double = 0.5
    var showOpponentAnswer: Bool = true
    var questionCount: Int = 15
    var showingPracticeScenarios: Bool = false
    var audioMode: Bool = false  // Audio toggle for TTS question reading

    // Audio
    private var announcementPlayer: AVAudioPlayer?
    private var speakingTask: Task<Void, Never>?
    private(set) var isSpeaking: Bool = false

    // Training state
    private(set) var currentQuestionIndex: Int = 0
    private(set) var currentScenario: KBReboundScenario?
    private(set) var totalPoints: Int = 0
    private(set) var reboundTimeRemaining: TimeInterval = 5.0
    private(set) var lastFeedback: ReboundFeedback?
    private(set) var opponentName: String = "Team Alpha"

    // Results
    private(set) var trainingResult: KBReboundTrainingResult?

    // Timer
    private var reboundTimer: Timer?
    private var turnStartTime: Date?

    // MARK: - Computed Properties

    var currentQuestion: KBQuestion? {
        currentScenario?.question
    }

    var totalQuestions: Int {
        min(questionCount, questions.count)
    }

    // MARK: - Initialization

    init(region: KBRegion, questions: [KBQuestion]) {
        let config = KBReboundConfig.forRegion(region)
        self.simulator = KBReboundSimulator(config: config)
        self.questions = questions.shuffled()
    }

    // MARK: - Training Control

    func startTraining() {
        let config = KBReboundConfig(
            region: .colorado,
            reboundProbability: reboundProbability,
            opponentAccuracy: opponentAccuracy,
            questionCount: questionCount,
            showOpponentAnswer: showOpponentAnswer
        )
        simulator = KBReboundSimulator(config: config)

        Task {
            await simulator.startSession()
            opponentName = await simulator.getCurrentOpponent()
        }

        currentQuestionIndex = 0
        totalPoints = 0
        state = .waitingForOpponent
    }

    func simulateOpponent() {
        guard currentQuestionIndex < totalQuestions else {
            endTraining()
            return
        }

        let question = questions[currentQuestionIndex]

        Task {
            let scenario = await simulator.generateScenario(for: question)
            currentScenario = scenario

            // Read question aloud if audio mode is enabled
            if audioMode {
                await speakQuestion(question.text)
            } else {
                // Simulate reading time without audio
                try? await Task.sleep(for: .seconds(2))
            }

            if scenario.opponentBuzzed {
                state = .opponentAnswering

                // Show opponent answering
                try? await Task.sleep(for: .seconds(1.5))

                if scenario.isReboundOpportunity {
                    startReboundTimer()
                    state = .reboundOpportunity
                } else {
                    // Opponent got it right, show feedback and move on
                    showOpponentCorrectFeedback()
                }
            } else {
                // No opponent buzz, user's turn
                turnStartTime = Date()
                state = .userTurn
            }
        }
    }

    /// Speak the question text via the configured TTS provider
    private func speakQuestion(_ text: String) async {
        isSpeaking = true

        // TTFA: mark activation for rebound training audio
        await TTFAInstrumentation.shared.markActivation(.kbRebound)

        let ttsService = TTSProvider.resolveConfiguredService()

        do {
            let stream = try await ttsService.synthesize(text: text)

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
            announcementPlayer = nil
        }

        isSpeaking = false
    }

    /// Cancel any ongoing speech and clean up
    private func cancelSpeech() {
        speakingTask?.cancel()
        speakingTask = nil
        announcementPlayer?.stop()
        announcementPlayer = nil
        isSpeaking = false
    }

    func buzzOnRebound() {
        stopReboundTimer()
        turnStartTime = Date()
        state = .userTurn
    }

    func holdStrategically() {
        stopReboundTimer()

        guard let scenario = currentScenario else { return }

        Task {
            await simulator.recordAttempt(
                buzzedOnRebound: false,
                userAnswer: nil,
                wasCorrect: false,
                responseTime: 5.0 - reboundTimeRemaining,
                knewAnswer: false
            )

            let points = 2
            totalPoints += points

            lastFeedback = ReboundFeedback(
                title: "Strategic Hold",
                message: "Good decision to hold when unsure. Correct answer: \(scenario.question.answer.primary)",
                icon: "hand.raised.fill",
                color: .blue,
                points: points
            )

            state = .feedback
        }
    }

    func submitAnswer(wasCorrect: Bool) {
        guard let scenario = currentScenario else { return }

        let responseTime = turnStartTime.map { Date().timeIntervalSince($0) } ?? 0

        Task {
            await simulator.recordAttempt(
                buzzedOnRebound: scenario.isReboundOpportunity,
                userAnswer: wasCorrect ? scenario.question.answer.primary : "wrong",
                wasCorrect: wasCorrect,
                responseTime: responseTime,
                knewAnswer: true
            )

            let points: Int
            if scenario.isReboundOpportunity {
                points = wasCorrect ? 10 : -5
            } else {
                points = wasCorrect ? 10 : -5
            }
            totalPoints += points

            if wasCorrect {
                lastFeedback = ReboundFeedback(
                    title: "Correct!",
                    message: scenario.isReboundOpportunity
                        ? "Great rebound! You capitalized on their mistake."
                        : "Nice answer!",
                    icon: "checkmark.circle.fill",
                    color: .green,
                    points: points
                )
            } else {
                lastFeedback = ReboundFeedback(
                    title: "Incorrect",
                    message: "The answer was: \(scenario.question.answer.primary)",
                    icon: "xmark.circle.fill",
                    color: .red,
                    points: points
                )
            }

            state = .feedback
        }
    }

    func nextQuestion() {
        currentQuestionIndex += 1

        if currentQuestionIndex >= totalQuestions {
            endTraining()
        } else {
            Task {
                await simulator.rotateOpponent()
                opponentName = await simulator.getCurrentOpponent()
            }
            state = .waitingForOpponent
            simulateOpponent()
        }
    }

    func restartTraining() {
        cancelSpeech()
        trainingResult = nil
        state = .setup
    }

    func showPracticeScenarios() {
        showingPracticeScenarios = true
    }

    // MARK: - Private Helpers

    private func showOpponentCorrectFeedback() {
        guard let scenario = currentScenario else { return }

        Task {
            await simulator.recordAttempt(
                buzzedOnRebound: false,
                userAnswer: nil,
                wasCorrect: false,
                responseTime: 0,
                knewAnswer: false
            )

            let points = 1
            totalPoints += points

            lastFeedback = ReboundFeedback(
                title: "\(opponentName) Got It!",
                message: "No rebound opportunity. Answer: \(scenario.question.answer.primary)",
                icon: "person.fill.checkmark",
                color: .orange,
                points: points
            )

            state = .feedback
        }
    }

    private func startReboundTimer() {
        reboundTimeRemaining = 5.0
        reboundTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reboundTimerTick()
            }
        }
    }

    private func stopReboundTimer() {
        reboundTimer?.invalidate()
        reboundTimer = nil
    }

    private func reboundTimerTick() {
        reboundTimeRemaining = max(0, reboundTimeRemaining - 0.1)

        if reboundTimeRemaining <= 0 {
            // Time expired, count as missed opportunity
            stopReboundTimer()
            missedReboundOpportunity()
        }
    }

    private func missedReboundOpportunity() {
        guard let scenario = currentScenario else { return }

        Task {
            await simulator.recordAttempt(
                buzzedOnRebound: false,
                userAnswer: nil,
                wasCorrect: false,
                responseTime: 5.0,
                knewAnswer: false
            )

            let points = -2
            totalPoints += points

            lastFeedback = ReboundFeedback(
                title: "Missed Opportunity",
                message: "Time ran out! Correct answer: \(scenario.question.answer.primary)",
                icon: "clock.badge.exclamationmark.fill",
                color: .orange,
                points: points
            )

            state = .feedback
        }
    }

    private func endTraining() {
        stopReboundTimer()
        cancelSpeech()

        Task {
            let stats = await simulator.endSession()

            trainingResult = KBReboundTrainingResult(
                sessionId: UUID(),
                region: .colorado,
                startTime: Date().addingTimeInterval(-Double(totalQuestions) * 15),
                endTime: Date(),
                stats: stats,
                recommendation: KBReboundTrainingResult.generateRecommendation(from: stats)
            )

            state = .results
        }
    }
}

// MARK: - Preview

#Preview {
    KBReboundTrainingView(
        region: .colorado,
        questions: [
            KBQuestion(
                id: UUID(),
                text: "What is the capital of France?",
                answer: KBAnswer(primary: "Paris", acceptable: nil, answerType: .place),
                domain: .socialStudies,
                difficulty: .foundational,
                gradeLevel: .highSchool,
                suitability: KBSuitability()
            )
        ]
    )
}
