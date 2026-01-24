//
//  KBWatchDomainDrillView.swift
//  UnaMentis Watch App
//
//  Domain-focused practice for Knowledge Bowl on watchOS.
//  Allows users to drill specific subject areas.
//

import SwiftUI

// MARK: - Domain Drill View

/// Domain-specific practice session for watchOS
struct KBWatchDomainDrillView: View {
    let domain: KBDomain
    @StateObject private var viewModel: KBWatchDomainDrillViewModel
    @Environment(\.dismiss) private var dismiss

    init(domain: KBDomain) {
        self.domain = domain
        _viewModel = StateObject(wrappedValue: KBWatchDomainDrillViewModel(domain: domain))
    }

    var body: some View {
        VStack(spacing: 8) {
            // Domain header
            HStack {
                Image(systemName: domain.icon)
                    .foregroundStyle(domain.color)
                Text(domain.displayName)
                    .font(.caption)
            }

            // Progress
            Text("\(viewModel.currentIndex + 1)/\(viewModel.totalQuestions)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            if viewModel.isComplete {
                completeView
            } else if let question = viewModel.currentQuestion {
                questionView(question)
            } else {
                ProgressView("Loading...")
            }
        }
        .navigationTitle(domain.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.start()
        }
    }

    // MARK: - Question View

    private func questionView(_ question: KBWatchQuestion) -> some View {
        VStack(spacing: 8) {
            ScrollView {
                Text(question.text)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
            .frame(maxHeight: 80)

            Spacer()

            if viewModel.showingAnswer {
                answerView(question)
            } else {
                Button("Show Answer") {
                    viewModel.revealAnswer()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    private func answerView(_ question: KBWatchQuestion) -> some View {
        VStack(spacing: 8) {
            Text(question.answer)
                .font(.headline)
                .foregroundStyle(.blue)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button(action: { viewModel.markAnswer(correct: false) }) {
                    Image(systemName: "xmark")
                        .frame(width: 40, height: 40)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.markAnswer(correct: true) }) {
                    Image(systemName: "checkmark")
                        .frame(width: 40, height: 40)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Complete View

    private var completeView: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.title)
                .foregroundStyle(.yellow)

            Text("Drill Complete!")
                .font(.headline)

            Text("\(viewModel.correctCount)/\(viewModel.totalQuestions)")
                .font(.body)

            // Mastery indicator
            HStack {
                ForEach(0..<5) { index in
                    Image(systemName: index < viewModel.masteryStars ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
            }

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
final class KBWatchDomainDrillViewModel: ObservableObject {
    let domain: KBDomain
    let totalQuestions = 10

    private(set) var currentIndex: Int = 0
    private(set) var correctCount: Int = 0
    private(set) var showingAnswer: Bool = false
    private(set) var isComplete: Bool = false
    private(set) var currentQuestion: KBWatchQuestion?

    private var questions: [KBWatchQuestion] = []

    init(domain: KBDomain) {
        self.domain = domain
    }

    var masteryStars: Int {
        let accuracy = Double(correctCount) / Double(totalQuestions)
        if accuracy >= 0.9 { return 5 }
        if accuracy >= 0.8 { return 4 }
        if accuracy >= 0.7 { return 3 }
        if accuracy >= 0.6 { return 2 }
        if accuracy >= 0.4 { return 1 }
        return 0
    }

    func start() {
        // Load domain-specific questions
        questions = KBWatchQuestion.sampleQuestions
            .filter { $0.domain == domain }
            .shuffled()
            .prefix(totalQuestions)
            .map { $0 }

        // If not enough domain questions, fill with random
        if questions.count < totalQuestions {
            let remaining = KBWatchQuestion.sampleQuestions
                .shuffled()
                .prefix(totalQuestions - questions.count)
            questions.append(contentsOf: remaining)
        }

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

        // Advance
        currentIndex += 1
        showingAnswer = false

        if currentIndex < questions.count {
            currentQuestion = questions[currentIndex]
        } else {
            isComplete = true
            saveDomainStats()
        }
    }

    private func saveDomainStats() {
        let defaults = UserDefaults.standard
        let key = "kb_watch_domain_\(domain.rawValue)"

        let prevAttempts = defaults.integer(forKey: "\(key)_drill_attempts")
        let prevCorrect = defaults.integer(forKey: "\(key)_drill_correct")

        defaults.set(prevAttempts + totalQuestions, forKey: "\(key)_drill_attempts")
        defaults.set(prevCorrect + correctCount, forKey: "\(key)_drill_correct")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        KBWatchDomainDrillView(domain: .science)
    }
}
