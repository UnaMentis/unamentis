//
//  KBWrittenSessionView.swift
//  UnaMentis
//
//  Written round practice view for Knowledge Bowl
//

import SwiftUI

// MARK: - Written Session View

struct KBWrittenSessionView: View {
    @StateObject var viewModel: KBWrittenSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header with timer and progress
            sessionHeader

            // Main content
            switch viewModel.state {
            case .notStarted:
                startScreen
            case .inProgress, .paused:
                questionContent
            case .reviewing:
                questionContent  // Same as in progress for now
            case .completed, .expired:
                summaryScreen
            }
        }
        .background(Color.kbBgPrimary)
        .navigationBarBackButtonHidden(viewModel.state != .notStarted && viewModel.state != .completed)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if case .inProgress = viewModel.state {
                    Button("End") {
                        viewModel.endSession()
                    }
                    .foregroundColor(.kbFocusArea)
                }
            }
        }
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        VStack(spacing: 8) {
            // Timer (if applicable)
            if viewModel.config.timeLimit != nil {
                timerDisplay
            }

            // Progress bar
            progressBar

            // Question counter
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

    private var timerDisplay: some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundColor(viewModel.timerState.color)

            Text(formatTime(viewModel.remainingTime))
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .foregroundColor(viewModel.timerState.color)
                .modifier(PulseModifier(
                    isActive: viewModel.timerState.pulseSpeed != nil,
                    speed: viewModel.timerState.pulseSpeed ?? 1.0
                ))
        }
        .padding(.horizontal)
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

            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.kbMastered)

            Text("Written Round Practice")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.kbTextPrimary)

            VStack(alignment: .leading, spacing: 8) {
                configRow(icon: "number", label: "Questions", value: "\(viewModel.questions.count)")
                if let timeLimit = viewModel.config.timeLimit {
                    configRow(icon: "clock", label: "Time Limit", value: formatTime(timeLimit))
                }
                configRow(icon: "mappin", label: "Region", value: viewModel.regionalConfig.region.displayName)
                configRow(icon: "star", label: "Points", value: "\(viewModel.regionalConfig.writtenPointsPerCorrect) per correct")
            }
            .padding()
            .background(Color.kbBgSecondary)
            .cornerRadius(12)

            Spacer()

            Button(action: {
                viewModel.startSession()
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

    // MARK: - Question Content

    private var questionContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Question card
                    if let question = viewModel.currentQuestion {
                        questionCard(question)

                        // MCQ Options
                        mcqOptions(question)
                    }
                }
                .padding()
            }

            // Submit button
            submitButton
        }
    }

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

    private func mcqOptions(_ question: KBQuestion) -> some View {
        VStack(spacing: 12) {
            ForEach(Array((question.mcqOptions ?? []).enumerated()), id: \.offset) { index, option in
                mcqOptionButton(
                    index: index,
                    option: option,
                    question: question
                )
            }
        }
    }

    private func mcqOptionButton(index: Int, option: String, question: KBQuestion) -> some View {
        let isSelected = viewModel.selectedAnswer == index
        let isCorrect = option.lowercased() == question.answer.primary.lowercased()
        let showResult = viewModel.showingFeedback

        let backgroundColor: Color = {
            if showResult {
                if isCorrect {
                    return .kbMastered.opacity(0.2)
                } else if isSelected {
                    return .kbFocusArea.opacity(0.2)
                }
            }
            return isSelected ? Color.kbIntermediate.opacity(0.2) : Color.kbBgSecondary
        }()

        let borderColor: Color = {
            if showResult {
                if isCorrect {
                    return .kbMastered
                } else if isSelected {
                    return .kbFocusArea
                }
            }
            return isSelected ? .kbIntermediate : .kbBorder
        }()

        // Safe letter lookup supporting more than 4 options
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let letter = index < letters.count ? String(letters[letters.index(letters.startIndex, offsetBy: index)]) : "?"

        return Button(action: {
            if !viewModel.showingFeedback {
                KBHapticFeedback.selection()
                viewModel.selectAnswer(index)
            }
        }) {
            HStack(spacing: 12) {
                // Letter circle
                Text(letter)
                    .font(.headline)
                    .foregroundColor(isSelected || (showResult && isCorrect) ? .white : .kbTextSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isSelected || (showResult && isCorrect) ? borderColor : Color.clear)
                    )
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: 2)
                    )

                // Option text
                Text(option)
                    .font(.body)
                    .foregroundColor(.kbTextPrimary)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Result indicator
                if showResult {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.kbMastered)
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.kbFocusArea)
                    }
                }
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .disabled(viewModel.showingFeedback)
    }

    private var submitButton: some View {
        VStack(spacing: 0) {
            Divider()

            Group {
                if viewModel.showingFeedback {
                    Button(action: {
                        viewModel.nextQuestion()
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
                } else {
                    Button(action: {
                        viewModel.submitAnswer()
                        // Trigger haptic feedback based on answer correctness
                        if let isCorrect = viewModel.lastAnswerCorrect {
                            if isCorrect {
                                KBHapticFeedback.success()
                            } else {
                                KBHapticFeedback.error()
                            }
                        }
                    }) {
                        Text("Submit Answer")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.selectedAnswer != nil ? Color.kbIntermediate : Color.kbBorder)
                            .cornerRadius(12)
                    }
                    .disabled(viewModel.selectedAnswer == nil)
                }
            }
            .padding()
        }
        .background(Color.kbBgPrimary)
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
                Text(viewModel.state == .expired ? "Time's Up!" : "Session Complete!")
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

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Pulse Modifier

struct PulseModifier: ViewModifier {
    let isActive: Bool
    let speed: Double

    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && isPulsing ? 1.1 : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: speed).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                isPulsing = isActive
            }
            .onChange(of: isActive) { _, newValue in
                isPulsing = newValue
            }
    }
}

// MARK: - Preview

// MARK: - Haptic Feedback Helper

#if os(iOS)
import UIKit

@MainActor
private enum KBHapticFeedback {
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
#endif

#if DEBUG
struct KBWrittenSessionView_Previews: PreviewProvider {
    static var previews: some View {
        let engine = KBQuestionEngine.preview()
        let config = KBSessionConfig.quickPractice(
            region: .colorado,
            roundType: .written,
            questionCount: 10
        )
        let viewModel = KBWrittenSessionViewModel(
            questions: engine.questions,
            config: config
        )

        NavigationStack {
            KBWrittenSessionView(viewModel: viewModel)
        }
    }
}
#endif
