//
//  KBDashboardView.swift
//  UnaMentis
//
//  Main dashboard and entry point for Knowledge Bowl module
//

import SwiftUI

// MARK: - Dashboard View

struct KBDashboardView: View {
    @StateObject private var engine = KBQuestionEngine()
    @State private var selectedRegion: KBRegion = .colorado
    @State private var showingWrittenSession = false
    @State private var showingOralSession = false
    @State private var showingSettings = false
    @State private var writtenSessionViewModel: KBWrittenSessionViewModel?
    @State private var oralSessionViewModel: KBOralSessionViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header card
                    headerCard

                    // Quick start section
                    quickStartSection

                    // Region selector
                    regionSelector

                    // Stats section (placeholder for now)
                    if engine.totalQuestionCount > 0 {
                        statsSection
                    }
                }
                .padding()
            }
            .background(Color.kbBgPrimary)
            .navigationTitle("Knowledge Bowl")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .task {
                await loadQuestions()
            }
            .sheet(isPresented: $showingSettings) {
                KBSettingsView(selectedRegion: $selectedRegion)
            }
            .navigationDestination(isPresented: $showingWrittenSession) {
                if let viewModel = writtenSessionViewModel {
                    KBWrittenSessionView(viewModel: viewModel)
                }
            }
            .navigationDestination(isPresented: $showingOralSession) {
                if let viewModel = oralSessionViewModel {
                    KBOralSessionView(viewModel: viewModel)
                }
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 40))
                    .foregroundColor(.kbMastered)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Knowledge Bowl")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.kbTextPrimary)

                    Text("Train for academic competitions")
                        .font(.subheadline)
                        .foregroundColor(.kbTextSecondary)
                }

                Spacer()
            }

            // Loading state
            if engine.isLoading {
                ProgressView("Loading questions...")
                    .foregroundColor(.kbTextSecondary)
            } else if let error = engine.loadError {
                Text("Error: \(error.localizedDescription)")
                    .font(.caption)
                    .foregroundColor(.kbFocusArea)
            } else {
                HStack {
                    statBadge(value: "\(engine.totalQuestionCount)", label: "Questions")
                    Spacer()
                    statBadge(value: "\(KBDomain.allCases.count)", label: "Domains")
                    Spacer()
                    statBadge(value: selectedRegion.abbreviation, label: "Region")
                }
            }
        }
        .padding()
        .background(Color.kbBgSecondary)
        .cornerRadius(16)
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.kbMastered)
            Text(label)
                .font(.caption)
                .foregroundColor(.kbTextSecondary)
        }
    }

    // MARK: - Quick Start Section

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Start")
                .font(.headline)
                .foregroundColor(.kbTextPrimary)

            HStack(spacing: 12) {
                // Written Practice
                quickStartButton(
                    icon: "pencil.and.list.clipboard",
                    title: "Written",
                    subtitle: "MCQ Practice",
                    color: .kbIntermediate
                ) {
                    startWrittenPractice()
                }

                // Oral Practice
                quickStartButton(
                    icon: "mic.fill",
                    title: "Oral",
                    subtitle: "Voice Q&A",
                    color: .kbMastered
                ) {
                    startOralPractice()
                }
            }
        }
    }

    private func quickStartButton(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)

                Text(title)
                    .font(.headline)
                    .foregroundColor(.kbTextPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.kbTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.kbBgSecondary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 2)
            )
        }
        .disabled(engine.totalQuestionCount == 0)
    }

    // MARK: - Region Selector

    private var regionSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Competition Region")
                .font(.headline)
                .foregroundColor(.kbTextPrimary)

            HStack(spacing: 8) {
                ForEach([KBRegion.colorado, .minnesota, .washington], id: \.self) { region in
                    regionButton(region)
                }
            }

            // Regional rules summary
            Text(selectedRegion.config.conferringRuleDescription)
                .font(.caption)
                .foregroundColor(.kbTextSecondary)
                .padding(.horizontal, 4)
        }
    }

    private func regionButton(_ region: KBRegion) -> some View {
        let isSelected = selectedRegion == region

        return Button(action: {
            withAnimation {
                selectedRegion = region
            }
        }) {
            Text(region.abbreviation)
                .font(.headline)
                .foregroundColor(isSelected ? .white : .kbTextPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.kbMastered : Color.kbBgSecondary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.clear : Color.kbBorder, lineWidth: 1)
                )
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Question Bank")
                .font(.headline)
                .foregroundColor(.kbTextPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(KBDomain.allCases.prefix(6)) { domain in
                    domainCard(domain)
                }
            }

            // Show more domains
            if KBDomain.allCases.count > 6 {
                DisclosureGroup("More domains") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(Array(KBDomain.allCases.dropFirst(6))) { domain in
                            domainCard(domain)
                        }
                    }
                }
                .foregroundColor(.kbTextSecondary)
            }
        }
    }

    private func domainCard(_ domain: KBDomain) -> some View {
        let count = engine.questionsByDomain[domain] ?? 0

        return VStack(spacing: 4) {
            Image(systemName: domain.icon)
                .font(.title2)
                .foregroundColor(domain.color)

            Text("\(count)")
                .font(.headline)
                .foregroundColor(.kbTextPrimary)

            Text(domain.displayName)
                .font(.caption2)
                .foregroundColor(.kbTextSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.kbBgSecondary)
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func loadQuestions() async {
        do {
            try await engine.loadBundledQuestions()
        } catch {
            // Error is captured in engine.loadError
        }
    }

    private func startWrittenPractice() {
        let config = KBSessionConfig.quickPractice(
            region: selectedRegion,
            roundType: .written,
            questionCount: 10
        )
        let questions = engine.selectForSession(config: config)
        writtenSessionViewModel = KBWrittenSessionViewModel(questions: questions, config: config)
        showingWrittenSession = true
    }

    private func startOralPractice() {
        let config = KBSessionConfig.quickPractice(
            region: selectedRegion,
            roundType: .oral,
            questionCount: 5  // Fewer questions for oral practice
        )
        let questions = engine.selectForSession(config: config)
        oralSessionViewModel = KBOralSessionViewModel(questions: questions, config: config)
        showingOralSession = true
    }
}

// MARK: - Settings View

struct KBSettingsView: View {
    @Binding var selectedRegion: KBRegion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Competition Region") {
                    ForEach(KBRegion.allCases) { region in
                        Button(action: {
                            selectedRegion = region
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(region.displayName)
                                        .foregroundColor(.kbTextPrimary)
                                    Text(region.config.conferringRuleDescription)
                                        .font(.caption)
                                        .foregroundColor(.kbTextSecondary)
                                }

                                Spacer()

                                if selectedRegion == region {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.kbMastered)
                                }
                            }
                        }
                    }
                }

                Section("Regional Rules") {
                    let config = selectedRegion.config

                    HStack {
                        Text("Written Questions")
                        Spacer()
                        Text("\(config.writtenQuestionCount)")
                            .foregroundColor(.kbTextSecondary)
                    }

                    HStack {
                        Text("Written Time")
                        Spacer()
                        Text(config.writtenTimeLimitDisplay)
                            .foregroundColor(.kbTextSecondary)
                    }

                    HStack {
                        Text("Points per Written")
                        Spacer()
                        Text("\(config.writtenPointsPerCorrect)")
                            .foregroundColor(.kbTextSecondary)
                    }

                    HStack {
                        Text("Conference Time")
                        Spacer()
                        Text(config.conferenceTimeDisplay)
                            .foregroundColor(.kbTextSecondary)
                    }

                    HStack {
                        Text("Verbal Conferring")
                        Spacer()
                        Text(config.verbalConferringAllowed ? "Allowed" : "Not Allowed")
                            .foregroundColor(config.verbalConferringAllowed ? .kbMastered : .kbFocusArea)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct KBDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        KBDashboardView()
    }
}
#endif
