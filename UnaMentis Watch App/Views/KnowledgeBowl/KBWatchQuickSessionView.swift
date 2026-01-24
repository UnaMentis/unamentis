//
//  KBWatchQuickSessionView.swift
//  UnaMentis Watch App
//
//  Quick practice session for Knowledge Bowl on watchOS.
//  Optimized for short questions and tap-based answer reveal.
//

import SwiftUI

// MARK: - Quick Session View

/// A quick practice session on the watch with tap-to-reveal answers
struct KBWatchQuickSessionView: View {
    let questionCount: Int
    @StateObject private var viewModel: KBWatchQuickSessionViewModel
    @Environment(\.dismiss) private var dismiss

    init(questionCount: Int) {
        self.questionCount = questionCount
        _viewModel = StateObject(wrappedValue: KBWatchQuickSessionViewModel(questionCount: questionCount))
    }

    var body: some View {
        VStack(spacing: 8) {
            // Progress indicator
            progressIndicator

            if viewModel.isComplete {
                // Session complete view
                sessionCompleteView
            } else if let question = viewModel.currentQuestion {
                // Question view
                questionView(question)
            } else {
                // Loading
                ProgressView()
            }
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.start()
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack {
            Text("\(viewModel.currentIndex + 1)/\(questionCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(viewModel.correctCount) correct")
                .font(.caption)
                .foregroundStyle(.green)
        }
        .padding(.horizontal)
    }

    // MARK: - Question View

    private func questionView(_ question: KBWatchQuestion) -> some View {
        VStack(spacing: 12) {
            // Question text (scrollable)
            ScrollView {
                Text(question.text)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
            .frame(maxHeight: 100)

            Spacer()

            if viewModel.showingAnswer {
                // Answer revealed
                answerRevealView(question)
            } else {
                // Tap to reveal
                tapToRevealButton
            }
        }
        .padding(.horizontal)
    }

    private var tapToRevealButton: some View {
        Button(action: { viewModel.revealAnswer() }) {
            VStack(spacing: 4) {
                Image(systemName: "eye")
                    .font(.title2)
                Text("Tap to Reveal")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.bordered)
    }

    private func answerRevealView(_ question: KBWatchQuestion) -> some View {
        VStack(spacing: 8) {
            Text(question.answer)
                .font(.headline)
                .foregroundStyle(.blue)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                // Wrong button
                Button(action: { viewModel.markAnswer(correct: false) }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Correct button
                Button(action: { viewModel.markAnswer(correct: true) }) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Session Complete View

    private var sessionCompleteView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)

            Text("Complete!")
                .font(.headline)

            Text("\(viewModel.correctCount)/\(questionCount) correct")
                .font(.body)

            Text("\(viewModel.accuracyPercentage)%")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(viewModel.accuracyColor)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - View Model

@MainActor
@Observable
final class KBWatchQuickSessionViewModel: ObservableObject {
    let questionCount: Int

    private(set) var currentIndex: Int = 0
    private(set) var correctCount: Int = 0
    private(set) var showingAnswer: Bool = false
    private(set) var isComplete: Bool = false
    private(set) var currentQuestion: KBWatchQuestion?

    private var questions: [KBWatchQuestion] = []

    init(questionCount: Int) {
        self.questionCount = questionCount
    }

    var accuracyPercentage: Int {
        guard questionCount > 0 else { return 0 }
        return Int(Double(correctCount) / Double(questionCount) * 100)
    }

    var accuracyColor: Color {
        if accuracyPercentage >= 80 { return .green }
        if accuracyPercentage >= 60 { return .orange }
        return .red
    }

    func start() {
        // Load questions optimized for watch (shorter questions)
        questions = loadWatchQuestions(count: questionCount)
        currentIndex = 0
        correctCount = 0
        showingAnswer = false
        isComplete = false
        currentQuestion = questions.first
    }

    func revealAnswer() {
        showingAnswer = true
    }

    func markAnswer(correct: Bool) {
        if correct {
            correctCount += 1
        }

        // Record to stats
        recordAnswer(correct: correct)

        // Advance to next question
        advanceToNext()
    }

    private func advanceToNext() {
        currentIndex += 1
        showingAnswer = false

        if currentIndex < questions.count {
            currentQuestion = questions[currentIndex]
        } else {
            isComplete = true
            saveSessionStats()
        }
    }

    private func recordAnswer(correct: Bool) {
        // Record individual answer (for weak area tracking)
        if let question = currentQuestion {
            let defaults = UserDefaults.standard
            let key = "kb_watch_domain_\(question.domain.rawValue)"
            let attempts = defaults.integer(forKey: "\(key)_attempts") + 1
            let corrects = defaults.integer(forKey: "\(key)_correct") + (correct ? 1 : 0)
            defaults.set(attempts, forKey: "\(key)_attempts")
            defaults.set(corrects, forKey: "\(key)_correct")
        }
    }

    private func saveSessionStats() {
        let defaults = UserDefaults.standard
        let todayKey = todayDateKey()

        let prevQuestions = defaults.integer(forKey: "kb_watch_\(todayKey)_questions")
        let prevCorrect = defaults.integer(forKey: "kb_watch_\(todayKey)_correct")

        defaults.set(prevQuestions + questionCount, forKey: "kb_watch_\(todayKey)_questions")
        defaults.set(prevCorrect + correctCount, forKey: "kb_watch_\(todayKey)_correct")
    }

    private func todayDateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func loadWatchQuestions(count: Int) -> [KBWatchQuestion] {
        // Load short questions suitable for watch
        // In production, this would load from the shared question database
        KBWatchQuestion.sampleQuestions.shuffled().prefix(count).map { $0 }
    }
}

// MARK: - Watch Question Model

/// Simplified question model for watchOS
struct KBWatchQuestion: Identifiable, Sendable {
    let id: UUID
    let text: String
    let answer: String
    let domain: KBDomain

    init(id: UUID = UUID(), text: String, answer: String, domain: KBDomain) {
        self.id = id
        self.text = text
        self.answer = answer
        self.domain = domain
    }

    /// Sample questions for testing (would be replaced with real data)
    static let sampleQuestions: [KBWatchQuestion] = [
        KBWatchQuestion(text: "What is the chemical symbol for gold?", answer: "Au", domain: .science),
        KBWatchQuestion(text: "Who wrote 'Romeo and Juliet'?", answer: "William Shakespeare", domain: .literature),
        KBWatchQuestion(text: "What is the capital of France?", answer: "Paris", domain: .socialStudies),
        KBWatchQuestion(text: "What is the square root of 144?", answer: "12", domain: .mathematics),
        KBWatchQuestion(text: "In what year did World War II end?", answer: "1945", domain: .history),
        KBWatchQuestion(text: "What planet is known as the Red Planet?", answer: "Mars", domain: .science),
        KBWatchQuestion(text: "Who painted the Mona Lisa?", answer: "Leonardo da Vinci", domain: .arts),
        KBWatchQuestion(text: "What is the largest ocean on Earth?", answer: "Pacific Ocean", domain: .socialStudies),
        KBWatchQuestion(text: "What is 7 x 8?", answer: "56", domain: .mathematics),
        KBWatchQuestion(text: "Who was the first President of the United States?", answer: "George Washington", domain: .history),
        KBWatchQuestion(text: "What is H2O commonly known as?", answer: "Water", domain: .science),
        KBWatchQuestion(text: "Who wrote 'The Great Gatsby'?", answer: "F. Scott Fitzgerald", domain: .literature),
        KBWatchQuestion(text: "What is the capital of Japan?", answer: "Tokyo", domain: .socialStudies),
        KBWatchQuestion(text: "What is the value of pi to two decimal places?", answer: "3.14", domain: .mathematics),
        KBWatchQuestion(text: "In what year did the American Civil War begin?", answer: "1861", domain: .history)
    ]
}

// MARK: - Preview

#Preview {
    NavigationStack {
        KBWatchQuickSessionView(questionCount: 5)
    }
}
