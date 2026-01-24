//
//  KBWatchFlashCardsView.swift
//  UnaMentis Watch App
//
//  Flash card review mode for Knowledge Bowl on watchOS.
//  Supports reviewing missed questions and random practice.
//

import SwiftUI

// MARK: - Flash Card Mode

/// Mode for flash card practice
enum KBFlashCardMode: Sendable {
    case missedQuestions  // Review questions user got wrong
    case random           // Random selection across all domains
}

// MARK: - Flash Cards View

/// Flash card style review on watchOS
struct KBWatchFlashCardsView: View {
    let mode: KBFlashCardMode
    @StateObject private var viewModel: KBWatchFlashCardsViewModel
    @Environment(\.dismiss) private var dismiss

    init(mode: KBFlashCardMode) {
        self.mode = mode
        _viewModel = StateObject(wrappedValue: KBWatchFlashCardsViewModel(mode: mode))
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text(mode == .missedQuestions ? "Review" : "Random")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(viewModel.currentIndex + 1)/\(viewModel.totalCards)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if viewModel.isEmpty {
                emptyView
            } else if viewModel.isComplete {
                completeView
            } else {
                flashCardView
            }
        }
        .navigationTitle("Flash Cards")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.start()
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)

            Text("All Clear!")
                .font(.headline)

            Text(mode == .missedQuestions
                 ? "No missed questions to review"
                 : "No questions available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Flash Card View

    private var flashCardView: some View {
        VStack(spacing: 8) {
            // Card
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.darkGray))

                if viewModel.isFlipped {
                    // Answer side
                    VStack(spacing: 4) {
                        Text("Answer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(viewModel.currentCard?.answer ?? "")
                            .font(.headline)
                            .foregroundStyle(.blue)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                } else {
                    // Question side
                    ScrollView {
                        Text(viewModel.currentCard?.text ?? "")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(8)
                    }
                }
            }
            .frame(height: 100)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.flipCard()
                }
            }

            // Domain indicator
            if let domain = viewModel.currentCard?.domain {
                HStack {
                    Image(systemName: domain.icon)
                        .font(.caption2)
                    Text(domain.displayName)
                        .font(.caption2)
                }
                .foregroundStyle(domain.color)
            }

            Spacer()

            // Navigation buttons
            if viewModel.isFlipped {
                HStack(spacing: 16) {
                    Button(action: { viewModel.markAndNext(correct: false) }) {
                        Image(systemName: "xmark")
                            .frame(width: 36, height: 36)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.markAndNext(correct: true) }) {
                        Image(systemName: "checkmark")
                            .frame(width: 36, height: 36)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Tap card to flip")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Complete View

    private var completeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.yellow)

            Text("Review Complete!")
                .font(.headline)

            VStack(spacing: 4) {
                Text("Mastered: \(viewModel.masteredCount)")
                    .foregroundStyle(.green)
                Text("Need Review: \(viewModel.needsReviewCount)")
                    .foregroundStyle(.orange)
            }
            .font(.caption)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - View Model

@MainActor
@Observable
final class KBWatchFlashCardsViewModel: ObservableObject {
    let mode: KBFlashCardMode

    private(set) var currentIndex: Int = 0
    private(set) var totalCards: Int = 0
    private(set) var isFlipped: Bool = false
    private(set) var isComplete: Bool = false
    private(set) var isEmpty: Bool = false
    private(set) var currentCard: KBWatchQuestion?

    private(set) var masteredCount: Int = 0
    private(set) var needsReviewCount: Int = 0

    private var cards: [KBWatchQuestion] = []

    init(mode: KBFlashCardMode) {
        self.mode = mode
    }

    func start() {
        switch mode {
        case .missedQuestions:
            loadMissedQuestions()
        case .random:
            loadRandomQuestions()
        }

        totalCards = cards.count
        isEmpty = cards.isEmpty
        currentIndex = 0
        isFlipped = false
        isComplete = false
        masteredCount = 0
        needsReviewCount = 0
        currentCard = cards.first
    }

    func flipCard() {
        isFlipped.toggle()
    }

    func markAndNext(correct: Bool) {
        if correct {
            masteredCount += 1
        } else {
            needsReviewCount += 1
        }

        // Advance
        currentIndex += 1
        isFlipped = false

        if currentIndex < cards.count {
            currentCard = cards[currentIndex]
        } else {
            isComplete = true
        }
    }

    private func loadMissedQuestions() {
        // In production, load from missed questions database
        // For now, return a subset as "missed"
        cards = Array(KBWatchQuestion.sampleQuestions.shuffled().prefix(8))
    }

    private func loadRandomQuestions() {
        cards = KBWatchQuestion.sampleQuestions.shuffled()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        KBWatchFlashCardsView(mode: .random)
    }
}
