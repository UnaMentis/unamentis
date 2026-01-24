//
//  KBWatchMainView.swift
//  UnaMentis Watch App
//
//  Knowledge Bowl training entry point for watchOS.
//  Provides quick practice, domain drills, and flash card modes
//  optimized for the watch form factor.
//

import SwiftUI

// MARK: - Main KB Watch View

/// Main entry point for Knowledge Bowl practice on watchOS
struct KBWatchMainView: View {
    @StateObject private var viewModel = KBWatchMainViewModel()

    var body: some View {
        NavigationStack {
            List {
                // Quick Practice Section
                Section("Quick Practice") {
                    NavigationLink {
                        KBWatchQuickSessionView(questionCount: 5)
                    } label: {
                        Label("5 Questions", systemImage: "bolt")
                    }

                    NavigationLink {
                        KBWatchQuickSessionView(questionCount: 10)
                    } label: {
                        Label("10 Questions", systemImage: "bolt.fill")
                    }
                }

                // Domain Drill Section
                Section("Domain Drill") {
                    ForEach(viewModel.availableDomains.prefix(4), id: \.self) { domain in
                        NavigationLink {
                            KBWatchDomainDrillView(domain: domain)
                        } label: {
                            Label(domain.displayName, systemImage: domain.icon)
                        }
                    }
                }

                // Flash Cards Section
                Section("Flash Cards") {
                    NavigationLink {
                        KBWatchFlashCardsView(mode: .missedQuestions)
                    } label: {
                        Label("Review Missed", systemImage: "xmark.circle")
                    }

                    NavigationLink {
                        KBWatchFlashCardsView(mode: .random)
                    } label: {
                        Label("Random Mix", systemImage: "shuffle")
                    }
                }

                // Today's Stats Section
                Section("Today") {
                    HStack {
                        Text("Questions")
                        Spacer()
                        Text("\(viewModel.todayQuestions)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Accuracy")
                        Spacer()
                        Text(viewModel.todayAccuracyText)
                            .foregroundStyle(viewModel.todayAccuracyColor)
                    }
                }
            }
            .navigationTitle("KB Training")
            .onAppear {
                viewModel.loadStats()
            }
        }
    }
}

// MARK: - Main View Model

@MainActor
@Observable
final class KBWatchMainViewModel {
    private(set) var availableDomains: [KBDomain] = []
    private(set) var todayQuestions: Int = 0
    private(set) var todayAccuracy: Double = 0

    var todayAccuracyText: String {
        if todayQuestions == 0 {
            return "---"
        }
        return "\(Int(todayAccuracy * 100))%"
    }

    var todayAccuracyColor: Color {
        if todayQuestions == 0 { return .secondary }
        if todayAccuracy >= 0.8 { return .green }
        if todayAccuracy >= 0.6 { return .orange }
        return .red
    }

    func loadStats() {
        // Load available domains (prioritize user's weak areas)
        availableDomains = [
            .science,
            .mathematics,
            .history,
            .literature,
            .socialStudies,
            .arts
        ]

        // Load today's stats from UserDefaults
        loadTodayStats()
    }

    private func loadTodayStats() {
        let defaults = UserDefaults.standard
        let todayKey = todayDateKey()

        todayQuestions = defaults.integer(forKey: "kb_watch_\(todayKey)_questions")

        let correct = defaults.integer(forKey: "kb_watch_\(todayKey)_correct")
        todayAccuracy = todayQuestions > 0 ? Double(correct) / Double(todayQuestions) : 0
    }

    private func todayDateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Preview

#Preview {
    KBWatchMainView()
}
