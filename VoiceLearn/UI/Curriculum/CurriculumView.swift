// VoiceLearn - Curriculum View
// UI for browsing and starting curriculum topics
//
// Part of Curriculum UI (Phase 4 Integration)

import SwiftUI
import Logging

struct CurriculumView: View {
    @EnvironmentObject var appState: AppState
    @State private var topics: [Topic] = []
    @State private var curriculumName: String?
    @State private var isLoading = false
    @State private var selectedTopic: Topic?

    private static let logger = Logger(label: "com.voicelearn.curriculum.view")

    init() {
        Self.logger.info("CurriculumView init() called")
    }

    var body: some View {
        let _ = Self.logger.debug("CurriculumView body START")
        NavigationStack {
            List {
                if topics.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Curriculum Loaded",
                        systemImage: "book.closed",
                        description: Text("Import a curriculum to get started.")
                    )
                } else {
                    if let name = curriculumName {
                        Section {
                            ForEach(topics, id: \.id) { topic in
                                TopicRow(topic: topic)
                                    .onTapGesture {
                                        Self.logger.debug("Topic tapped: \(topic.title ?? "unknown")")
                                        selectedTopic = topic
                                    }
                            }
                        } header: {
                            Text(name)
                        } footer: {
                            Text("\(topics.count) topics")
                        }
                    } else {
                        ForEach(topics, id: \.id) { topic in
                            TopicRow(topic: topic)
                                .onTapGesture {
                                    Self.logger.debug("Topic tapped: \(topic.title ?? "unknown")")
                                    selectedTopic = topic
                                }
                        }
                    }
                }
            }
            .navigationTitle("Curriculum")
            .onAppear {
                Self.logger.info("CurriculumView onAppear")
            }
            .task {
                Self.logger.info("CurriculumView .task STARTED")
                await loadCurriculumAndTopics()
                Self.logger.info("CurriculumView .task COMPLETED")
            }
            .refreshable {
                await loadCurriculumAndTopics()
            }
            .sheet(item: $selectedTopic) { topic in
                NavigationStack {
                    TopicDetailView(topic: topic)
                        .environmentObject(appState)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    selectedTopic = nil
                                }
                            }
                        }
                }
            }
        }
    }

    private func loadCurriculumAndTopics() async {
        isLoading = true
        Self.logger.info("loadCurriculumAndTopics START")

        // First, try to load first available curriculum from Core Data
        await loadFirstCurriculum()

        // Then load topics from the active curriculum
        guard let engine = appState.curriculum else {
            Self.logger.warning("No curriculum engine available")
            await MainActor.run {
                self.isLoading = false
            }
            return
        }

        let loadedTopics = await engine.getTopics()
        let name = await engine.activeCurriculum?.name

        await MainActor.run {
            self.topics = loadedTopics
            self.curriculumName = name
            self.isLoading = false
        }
        Self.logger.info("loadCurriculumAndTopics COMPLETE - \(loadedTopics.count) topics")
    }

    @MainActor
    private func loadFirstCurriculum() async {
        guard let engine = appState.curriculum else { return }

        // Check if we already have an active curriculum
        let hasActive = await engine.activeCurriculum != nil
        if hasActive { return }

        // Load first available curriculum
        let context = PersistenceController.shared.viewContext
        let request = Curriculum.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Curriculum.createdAt, ascending: false)]

        do {
            let results = try context.fetch(request)
            if let firstCurriculum = results.first, let id = firstCurriculum.id {
                try await engine.loadCurriculum(id)
            }
        } catch {
            Self.logger.error("Failed to load curriculum: \(error)")
        }
    }
}

struct TopicRow: View {
    @ObservedObject var topic: Topic

    var body: some View {
        HStack {
            StatusIcon(status: topic.status)

            VStack(alignment: .leading) {
                Text(topic.title ?? "Untitled Topic")
                    .font(.headline)

                if let summary = topic.outline, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let progress = topic.progress, progress.timeSpent > 0 {
                    Text(formatTime(progress.timeSpent))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return "\(minutes)m spent"
    }
}

struct StatusIcon: View {
    let status: TopicStatus

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: 32, height: 32)

            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
    }

    var iconName: String {
        switch status {
        case .notStarted: return "circle"
        case .inProgress: return "clock"
        case .completed: return "checkmark.circle.fill"
        case .reviewing: return "arrow.triangle.2.circlepath"
        }
    }

    var iconColor: Color {
        switch status {
        case .notStarted: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        case .reviewing: return .orange
        }
    }
}

// MARK: - Topic Detail View

struct TopicDetailView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var topic: Topic
    @State private var showingSession = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Status and Progress Section
                HStack {
                    StatusIcon(status: topic.status)
                        .scaleEffect(1.5)

                    VStack(alignment: .leading) {
                        Text(topic.status.rawValue.capitalized)
                            .font(.headline)
                        if let progress = topic.progress {
                            Text("\(Int(progress.timeSpent / 60)) minutes spent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Mastery indicator
                    VStack {
                        Text("\(Int(topic.mastery * 100))%")
                            .font(.title2.bold())
                        Text("Mastery")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                }

                // Overview Section
                if let outline = topic.outline, !outline.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Overview")
                            .font(.headline)
                        Text(outline)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // Learning Objectives Section
                if let objectives = topic.objectives, !objectives.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Learning Objectives")
                            .font(.headline)

                        ForEach(objectives, id: \.self) { objective in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.green)
                                    .font(.body)
                                Text(objective)
                                    .font(.body)
                            }
                        }
                    }
                }

                Spacer(minLength: 40)

                // Start Session Button
                Button {
                    showingSession = true
                } label: {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Start Voice Session")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle(topic.title ?? "Topic")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .fullScreenCover(isPresented: $showingSession) {
            NavigationStack {
                SessionView(topic: topic)
                    .environmentObject(appState)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingSession = false
                            }
                        }
                    }
            }
        }
    }
}

#Preview {
    CurriculumView()
        .environmentObject(AppState())
}
