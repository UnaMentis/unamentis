// VoiceLearn - Curriculum View
// UI for browsing and starting curriculum topics
//
// Part of Curriculum UI (Phase 4 Integration)

import SwiftUI
import UniformTypeIdentifiers

struct CurriculumView: View {
    @EnvironmentObject var appState: AppState
    @State private var topics: [Topic] = []
    @State private var curriculumName: String?
    @State private var isLoading = false
    @State private var showingImportOptions = false
    @State private var showingFileImporter = false
    @State private var importError: String?
    @State private var showingError = false
    @State private var selectedTopic: Topic?

    private let curriculumSeeder = SampleCurriculumSeeder()

    var body: some View {
        NavigationStack {
            List {
                if topics.isEmpty && !isLoading {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "No Curriculum Loaded",
                            systemImage: "book.closed",
                            description: Text("Import a curriculum to get started.")
                        )

                        Button {
                            showingImportOptions = true
                        } label: {
                            Label("Import Curriculum", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    if let name = curriculumName {
                        Section {
                            ForEach(topics, id: \.id) { topic in
                                NavigationLink(value: topic) {
                                    TopicRow(topic: topic)
                                }
                            }
                        } header: {
                            Text(name)
                        } footer: {
                            Text("\(topics.count) topics")
                        }
                    } else {
                        ForEach(topics, id: \.id) { topic in
                            NavigationLink(value: topic) {
                                TopicRow(topic: topic)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Curriculum")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingImportOptions = true
                        } label: {
                            Label("Import Curriculum", systemImage: "square.and.arrow.down")
                        }

                        if !topics.isEmpty {
                            Divider()
                            Button(role: .destructive) {
                                Task { await deleteCurriculum() }
                            } label: {
                                Label("Delete Curriculum", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                await loadCurriculumAndTopics()
            }
            .refreshable {
                await loadCurriculumAndTopics()
            }
            .navigationDestination(for: Topic.self) { topic in
                TopicDetailView(topic: topic)
                    .environmentObject(appState)
            }
            .confirmationDialog("Import Curriculum", isPresented: $showingImportOptions) {
                Button("Load Sample (PyTorch Fundamentals)") {
                    Task { await loadSampleCurriculum() }
                }
                Button("Import from File...") {
                    showingFileImporter = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose how to import a curriculum")
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleFileImport(result) }
            }
            .alert("Import Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(importError ?? "Unknown error")
            }
        }
    }

    @MainActor
    private func loadSampleCurriculum() async {
        isLoading = true
        do {
            try curriculumSeeder.seedPyTorchCurriculum()
            print("DEBUG: Sample curriculum seeded successfully")
            await loadCurriculumAndTopics()
        } catch {
            print("DEBUG: Failed to seed curriculum: \(error)")
            importError = error.localizedDescription
            showingError = true
            isLoading = false
        }
    }

    private func deleteCurriculum() async {
        do {
            try curriculumSeeder.deleteSampleCurriculum()
            topics = []
            curriculumName = nil
        } catch {
            importError = error.localizedDescription
            showingError = true
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // TODO: Implement JSON curriculum import
            importError = "File import coming soon. Use 'Load Sample' for now."
            showingError = true
        case .failure(let error):
            importError = error.localizedDescription
            showingError = true
        }
    }

    @MainActor
    private func loadCurriculumAndTopics() async {
        isLoading = true
        print("DEBUG: loadCurriculumAndTopics called")

        // Load curriculum and topics directly from Core Data
        let context = PersistenceController.shared.viewContext

        do {
            // Fetch the most recent curriculum
            let curriculumRequest = Curriculum.fetchRequest()
            curriculumRequest.fetchLimit = 1
            curriculumRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Curriculum.createdAt, ascending: false)]

            let curriculums = try context.fetch(curriculumRequest)
            print("DEBUG: Found \(curriculums.count) curriculums")

            if let curriculum = curriculums.first {
                print("DEBUG: Curriculum name: \(curriculum.name ?? "nil")")

                // Get topics from the curriculum's relationship (it's an NSOrderedSet)
                var topicsList: [Topic] = []
                if let orderedSet = curriculum.topics {
                    topicsList = orderedSet.array as? [Topic] ?? []
                }
                print("DEBUG: Found \(topicsList.count) topics")

                let sortedTopics = topicsList.sorted { ($0.orderIndex) < ($1.orderIndex) }

                self.topics = sortedTopics
                self.curriculumName = curriculum.name
                self.isLoading = false
                // Note: CurriculumEngine.loadCurriculum() is called when starting a session,
                // not when viewing the curriculum list (avoids actor isolation deadlock)
            } else {
                print("DEBUG: No curriculum found")
                self.topics = []
                self.curriculumName = nil
                self.isLoading = false
            }
        } catch {
            print("DEBUG: Failed to load curriculum: \(error)")
            self.topics = []
            self.curriculumName = nil
            self.isLoading = false
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
        #else
        .sheet(isPresented: $showingSession) {
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
        #endif
    }
}

#Preview {
    CurriculumView()
        .environmentObject(AppState())
}
