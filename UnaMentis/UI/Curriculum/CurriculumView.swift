// UnaMentis - Curriculum View
// UI for browsing and starting curriculum topics
//
// Part of Curriculum UI (Phase 4 Integration)

import SwiftUI
import Logging

struct CurriculumView: View {
    @EnvironmentObject var appState: AppState
    @State private var curricula: [Curriculum] = []
    @State private var isLoading = false
    @State private var selectedCurriculum: Curriculum?
    @State private var showingImportOptions = false
    @State private var showingServerBrowser = false
    @State private var importError: String?
    @State private var showingError = false

    private static let logger = Logger(label: "com.unamentis.curriculum.view")

    init() {
        Self.logger.info("CurriculumView init() called")
    }

    var body: some View {
        let _ = Self.logger.debug("CurriculumView body START")
        NavigationStack {
            List {
                if curricula.isEmpty && !isLoading {
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
                    ForEach(curricula, id: \.id) { curriculum in
                        CurriculumRow(curriculum: curriculum)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Self.logger.debug("Curriculum tapped: \(curriculum.name ?? "unknown")")
                                selectedCurriculum = curriculum
                            }
                    }
                    .onDelete(perform: deleteCurricula)
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

                        if !curricula.isEmpty {
                            Divider()
                            Button(role: .destructive) {
                                Task { await deleteAllCurricula() }
                            } label: {
                                Label("Delete All Curricula", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                Self.logger.info("CurriculumView onAppear")
            }
            .task {
                Self.logger.info("CurriculumView .task STARTED")
                await loadCurricula()
                Self.logger.info("CurriculumView .task COMPLETED")
            }
            .refreshable {
                await loadCurricula()
            }
            .sheet(item: $selectedCurriculum) { curriculum in
                NavigationStack {
                    CurriculumDetailView(curriculum: curriculum)
                        .environmentObject(appState)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    selectedCurriculum = nil
                                }
                            }
                        }
                }
            }
            .confirmationDialog("Import Curriculum", isPresented: $showingImportOptions) {
                Button("Browse Server Curricula") {
                    showingServerBrowser = true
                }
                Button("Load Sample (PyTorch Fundamentals)") {
                    Task { await loadSampleCurriculum() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose how to import a curriculum")
            }
            .sheet(isPresented: $showingServerBrowser) {
                ServerCurriculumBrowser { downloadedCurriculum in
                    // Curriculum was downloaded, refresh the view
                    showingServerBrowser = false
                    Task { await loadCurricula() }
                }
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
        Self.logger.info("Loading sample curriculum")
        do {
            let seeder = SampleCurriculumSeeder()
            try seeder.seedPyTorchCurriculum()
            Self.logger.info("Sample curriculum seeded successfully")
            await loadCurricula()
        } catch {
            Self.logger.error("Failed to seed curriculum: \(error)")
            importError = error.localizedDescription
            showingError = true
            isLoading = false
        }
    }

    private func deleteAllCurricula() async {
        do {
            let seeder = SampleCurriculumSeeder()
            try seeder.deleteSampleCurriculum()
            curricula = []
        } catch {
            importError = error.localizedDescription
            showingError = true
        }
    }

    private func deleteCurricula(at offsets: IndexSet) {
        let context = PersistenceController.shared.viewContext

        for index in offsets {
            let curriculum = curricula[index]
            Self.logger.info("Deleting curriculum: \(curriculum.name ?? "unknown")")
            context.delete(curriculum)
        }

        do {
            try context.save()
            curricula.remove(atOffsets: offsets)
            Self.logger.info("Successfully deleted \(offsets.count) curriculum(s)")
        } catch {
            Self.logger.error("Failed to delete curriculum: \(error)")
            importError = error.localizedDescription
            showingError = true
        }
    }

    @MainActor
    private func loadCurricula() async {
        isLoading = true
        Self.logger.info("loadCurricula START")

        // Load all curricula from Core Data
        let context = PersistenceController.shared.viewContext
        let request = Curriculum.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Curriculum.createdAt, ascending: false)]

        do {
            let results = try context.fetch(request)
            self.curricula = results
            Self.logger.info("Loaded \(results.count) curricula")
        } catch {
            Self.logger.error("Failed to load curricula: \(error)")
            self.curricula = []
        }

        self.isLoading = false
        Self.logger.info("loadCurricula COMPLETE")
    }
}

// MARK: - Curriculum Row (for list view)

struct CurriculumRow: View {
    @ObservedObject var curriculum: Curriculum

    var body: some View {
        HStack {
            // Curriculum icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: "book.fill")
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(curriculum.name ?? "Untitled Curriculum")
                    .font(.headline)

                if let summary = curriculum.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Show topic count
                let topicCount = curriculum.topics?.count ?? 0
                Text("\(topicCount) topics")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Curriculum Detail View (shows topics)

struct CurriculumDetailView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var curriculum: Curriculum
    @State private var selectedTopic: Topic?

    private static let logger = Logger(label: "com.unamentis.curriculum.detail")

    var sortedTopics: [Topic] {
        guard let orderedSet = curriculum.topics else { return [] }
        let topicsList = orderedSet.array as? [Topic] ?? []
        return topicsList.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        List {
            // Curriculum info section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let summary = curriculum.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("\(sortedTopics.count) topics", systemImage: "list.bullet")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }

            // Topics section
            Section("Topics") {
                ForEach(sortedTopics, id: \.id) { topic in
                    TopicRow(topic: topic)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Self.logger.debug("Topic tapped: \(topic.title ?? "unknown")")
                            selectedTopic = topic
                        }
                }
            }
        }
        .navigationTitle(curriculum.name ?? "Curriculum")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
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
        VStack(spacing: 0) {
            // Start Session Button - Always visible at top
            // Uses waveform icon (not microphone) because the AI speaks first in curriculum sessions
            Button {
                showingSession = true
            } label: {
                HStack {
                    Image(systemName: "waveform")
                    Text("Start Lesson")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))

            Divider()

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
                }
                .padding()
            }
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

// MARK: - Server Curriculum Browser

struct ServerCurriculumBrowser: View {
    let onDownload: (Curriculum) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var curricula: [CurriculumSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedCurriculum: CurriculumSummary?
    @State private var curriculumDetail: CurriculumDetail?
    @State private var isDownloading = false
    @State private var downloadProgress: String?
    @State private var downloadError: String?
    @State private var showingDownloadError = false

    private static let logger = Logger(label: "com.unamentis.curriculum.browser")

    var filteredCurricula: [CurriculumSummary] {
        if searchText.isEmpty {
            return curricula
        }
        return curricula.filter { curriculum in
            curriculum.title.localizedCaseInsensitiveContains(searchText) ||
            curriculum.description.localizedCaseInsensitiveContains(searchText) ||
            (curriculum.keywords ?? []).contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading curricula...")
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        "Connection Error",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                } else if curricula.isEmpty {
                    ContentUnavailableView(
                        "No Curricula Available",
                        systemImage: "book.closed",
                        description: Text("No curricula found on the server.")
                    )
                } else {
                    List {
                        ForEach(filteredCurricula) { curriculum in
                            ServerCurriculumRow(curriculum: curriculum)
                                .onTapGesture {
                                    selectedCurriculum = curriculum
                                    Task { await loadCurriculumDetail(curriculum.id) }
                                }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search curricula")
                }
            }
            .navigationTitle("Server Curricula")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadCurricula() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await configureCurriculumService()
                await loadCurricula()
            }
            .sheet(item: $selectedCurriculum) { curriculum in
                ServerCurriculumDetailView(
                    curriculum: curriculum,
                    detail: curriculumDetail,
                    isDownloading: isDownloading,
                    downloadProgress: downloadProgress,
                    onDownload: { await downloadCurriculum(curriculum) }
                )
            }
            .alert("Download Failed", isPresented: $showingDownloadError) {
                Button("OK") { }
            } message: {
                Text(downloadError ?? "An unknown error occurred while downloading the curriculum.")
            }
        }
    }

    private func configureCurriculumService() async {
        // Get server IP from UserDefaults (configured in Settings)
        let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
        let host = serverIP.isEmpty ? "localhost" : serverIP

        do {
            try await CurriculumService.shared.configure(host: host, port: 8766)
            Self.logger.info("Configured curriculum service with host: \(host):8766")
        } catch {
            Self.logger.error("Failed to configure curriculum service: \(error)")
        }
    }

    private func loadCurricula() async {
        isLoading = true
        errorMessage = nil

        do {
            curricula = try await CurriculumService.shared.fetchCurricula()
            Self.logger.info("Loaded \(curricula.count) curricula from server")
        } catch {
            Self.logger.error("Failed to load curricula: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadCurriculumDetail(_ id: String) async {
        do {
            curriculumDetail = try await CurriculumService.shared.fetchCurriculumDetail(id: id)
        } catch {
            Self.logger.error("Failed to load curriculum detail: \(error)")
        }
    }

    @MainActor
    private func downloadCurriculum(_ curriculum: CurriculumSummary) async {
        Self.logger.info("⬇️ Download initiated for curriculum: \(curriculum.title) (id: \(curriculum.id))")

        isDownloading = true
        downloadProgress = "Connecting to server..."
        downloadError = nil

        do {
            Self.logger.info("⬇️ Step 1: Creating parser...")
            let parser = VLCFParser()

            Self.logger.info("⬇️ Step 2: Starting download from server...")
            downloadProgress = "Downloading curriculum data..."

            let downloadedCurriculum = try await CurriculumService.shared.downloadAndImport(
                curriculumId: curriculum.id,
                parser: parser
            )

            Self.logger.info("✅ Successfully downloaded and imported curriculum: \(curriculum.title)")
            Self.logger.info("✅ Curriculum has \(downloadedCurriculum.topics?.count ?? 0) topics")

            downloadProgress = "Download complete!"

            // Brief delay to show success message
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            isDownloading = false
            downloadProgress = nil
            selectedCurriculum = nil
            onDownload(downloadedCurriculum)
        } catch {
            // Log full error details for debugging
            Self.logger.error("❌ Failed to download curriculum: \(error)")
            Self.logger.error("❌ Error type: \(type(of: error))")

            var errorDetail = error.localizedDescription

            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    Self.logger.error("❌ Missing key '\(key.stringValue)' at path: \(path)")
                    errorDetail = "Missing data field: \(key.stringValue) at \(path)"
                case .typeMismatch(let type, let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    Self.logger.error("❌ Type mismatch for \(type) at path: \(path)")
                    errorDetail = "Data format error at: \(path)"
                case .valueNotFound(let type, let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    Self.logger.error("❌ Value not found for \(type) at path: \(path)")
                    errorDetail = "Missing value at: \(path)"
                case .dataCorrupted(let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    Self.logger.error("❌ Data corrupted at path: \(path)")
                    errorDetail = "Corrupted data at: \(path)"
                @unknown default:
                    Self.logger.error("❌ Unknown decoding error")
                    errorDetail = "Unknown data format error"
                }
            } else if let serviceError = error as? CurriculumServiceError {
                errorDetail = serviceError.errorDescription ?? error.localizedDescription
            }

            isDownloading = false
            downloadProgress = nil
            downloadError = errorDetail
            showingDownloadError = true
        }
    }
}

struct ServerCurriculumRow: View {
    let curriculum: CurriculumSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(curriculum.title)
                    .font(.headline)
                Spacer()
                if let difficulty = curriculum.difficulty {
                    Text(difficulty)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(difficultyColor.opacity(0.2))
                        .foregroundColor(difficultyColor)
                        .cornerRadius(4)
                }
            }

            Text(curriculum.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 16) {
                Label("\(curriculum.topicCount) topics", systemImage: "list.bullet")
                if let duration = curriculum.totalDuration {
                    Label(formatDuration(duration), systemImage: "clock")
                }
                if let ageRange = curriculum.ageRange {
                    Label(ageRange, systemImage: "person.2")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            if let keywords = curriculum.keywords, !keywords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(keywords.prefix(5), id: \.self) { keyword in
                            Text(keyword)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    var difficultyColor: Color {
        switch curriculum.difficulty?.lowercased() {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .gray
        }
    }

    func formatDuration(_ ptDuration: String) -> String {
        // Parse PT format (e.g., PT6H, PT30M)
        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: ptDuration, range: NSRange(ptDuration.startIndex..., in: ptDuration)) else {
            return ptDuration
        }

        var hours = 0
        var minutes = 0

        if let hourRange = Range(match.range(at: 1), in: ptDuration) {
            hours = Int(ptDuration[hourRange]) ?? 0
        }
        if let minRange = Range(match.range(at: 2), in: ptDuration) {
            minutes = Int(ptDuration[minRange]) ?? 0
        }

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

struct ServerCurriculumDetailView: View {
    let curriculum: CurriculumSummary
    let detail: CurriculumDetail?
    let isDownloading: Bool
    let downloadProgress: String?
    let onDownload: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Download Button - Always visible at top
                if isDownloading {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        if let progress = downloadProgress {
                            Text(progress)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    Button {
                        Task { await onDownload() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Curriculum")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(curriculum.title)
                                .font(.title2.bold())

                            Text(curriculum.description)
                                .font(.body)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 16) {
                                if let difficulty = curriculum.difficulty {
                                    Label(difficulty, systemImage: "gauge")
                                }
                                Label("\(curriculum.topicCount) topics", systemImage: "list.bullet")
                                if let duration = curriculum.totalDuration {
                                    Label(formatDuration(duration), systemImage: "clock")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        }

                        Divider()

                    // Topics
                    if let detail = detail, !detail.topics.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Topics")
                                .font(.headline)

                            ForEach(Array(detail.topics.enumerated()), id: \.element.id) { index, topic in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Color.blue)
                                        .cornerRadius(12)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(topic.title)
                                            .font(.subheadline.weight(.medium))
                                        if !topic.description.isEmpty {
                                            Text(topic.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        HStack {
                                            if topic.hasTranscript {
                                                Label("\(topic.segmentCount) segments", systemImage: "text.quote")
                                            }
                                            if topic.assessmentCount > 0 {
                                                Label("\(topic.assessmentCount) quizzes", systemImage: "checkmark.circle")
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    }

                                    Spacer()
                                }
                            }
                        }
                    }

                    // Glossary Terms
                    if let detail = detail, !detail.glossaryTerms.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Key Terms")
                                .font(.headline)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(detail.glossaryTerms.prefix(6), id: \.term) { term in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(term.term)
                                            .font(.caption.weight(.medium))
                                        if let definition = term.definition {
                                            Text(definition)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Curriculum Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    func formatDuration(_ ptDuration: String) -> String {
        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: ptDuration, range: NSRange(ptDuration.startIndex..., in: ptDuration)) else {
            return ptDuration
        }

        var hours = 0
        var minutes = 0

        if let hourRange = Range(match.range(at: 1), in: ptDuration) {
            hours = Int(ptDuration[hourRange]) ?? 0
        }
        if let minRange = Range(match.range(at: 2), in: ptDuration) {
            minutes = Int(ptDuration[minRange]) ?? 0
        }

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    CurriculumView()
        .environmentObject(AppState())
}
