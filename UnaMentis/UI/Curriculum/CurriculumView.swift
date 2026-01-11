// UnaMentis - Curriculum View
// UI for browsing and starting curriculum topics
//
// Part of Curriculum UI (Phase 4 Integration)

import SwiftUI
import CoreData
import Logging
import UniformTypeIdentifiers

struct CurriculumView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var curricula: [Curriculum] = []
    @State private var isLoading = false
    @State private var selectedCurriculum: Curriculum?
    @State private var showingImportOptions = false
    @State private var showingServerBrowser = false
    @State private var showingFileImporter = false
    @State private var importError: String?
    @State private var showingError = false
    @State private var showingCurriculumHelp = false
    @State private var isImportingFile = false

    private static let logger = Logger(label: "com.unamentis.curriculum.view")

    init() {
        // NOTE: Removed debug logging from init to prevent side effects
    }

    var body: some View {
        // NOTE: Removed debug logging from view body to prevent side effects
        adaptiveNavigation
    }

    // MARK: - Adaptive Navigation (iPad vs iPhone)

    @ViewBuilder
    private var adaptiveNavigation: some View {
        if horizontalSizeClass == .regular {
            // iPad: Use NavigationSplitView for multi-column layout
            NavigationSplitView {
                curriculumListContent
                    .navigationTitle("Curriculum")
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } detail: {
                if let curriculum = selectedCurriculum {
                    CurriculumDetailView(curriculum: curriculum)
                        .environmentObject(appState)
                } else {
                    ContentUnavailableView(
                        "Select a Curriculum",
                        systemImage: "book.closed",
                        description: Text("Choose a curriculum from the list to view its topics.")
                    )
                }
            }
            .navigationSplitViewStyle(.prominentDetail)
        } else {
            // iPhone: Use NavigationStack with sheet for detail
            NavigationStack {
                curriculumListContent
                    .navigationTitle("Curriculum")
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
            }
        }
    }

    // MARK: - Curriculum List Content

    @ViewBuilder
    private var curriculumListContent: some View {
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrandLogo(size: .compact)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        showingCurriculumHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Curriculum help")
                    .accessibilityHint("Learn about curricula and topics")

                    Menu {
                        Button {
                            showingImportOptions = true
                        } label: {
                            Label("Import Curriculum", systemImage: "square.and.arrow.down")
                        }
                        .keyboardShortcut("i", modifiers: .command)

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
                            .accessibilityLabel("Curriculum options")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCurriculumHelp) {
            CurriculumHelpSheet()
        }
        .onAppear {
            Self.logger.info("CurriculumView onAppear")
        }
        .task {
            // Load curricula after view appears
            Self.logger.info("CurriculumView .task STARTED")
            await loadCurricula()
            Self.logger.info("CurriculumView .task COMPLETED")
        }
        .refreshable {
            await loadCurricula()
        }
        .confirmationDialog("Import Curriculum", isPresented: $showingImportOptions) {
            Button("Browse Server Curricula") {
                showingServerBrowser = true
            }
            Button("Import from File") {
                showingFileImporter = true
            }
            Button("Load Sample (PyTorch Fundamentals)") {
                Task { await loadSampleCurriculum() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose how to import a curriculum")
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "umcf") ?? .json,
                UTType(filenameExtension: "umcfz") ?? .gzip
            ],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFileImport(result) }
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

    @MainActor
    private func handleFileImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                Self.logger.warning("No file selected")
                return
            }

            isImportingFile = true
            isLoading = true
            Self.logger.info("Importing UMCF file: \(url.lastPathComponent)")

            do {
                // Start accessing the security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    throw UMCFFileError.fileReadFailed("Unable to access file")
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let fileHandler = UMCFFileHandler()
                _ = try await fileHandler.importAndStore(from: url)

                Self.logger.info("Successfully imported curriculum from file")
                await loadCurricula()
            } catch {
                Self.logger.error("Failed to import file: \(error)")
                importError = error.localizedDescription
                showingError = true
                isLoading = false
            }

            isImportingFile = false

        case .failure(let error):
            Self.logger.error("File picker error: \(error)")
            importError = error.localizedDescription
            showingError = true
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

    private func loadCurricula() async {
        await MainActor.run { isLoading = true }
        Self.logger.info("loadCurricula START - creating background context")

        // Fetch on background context to avoid blocking MainActor
        let backgroundContext = PersistenceController.shared.newBackgroundContext()
        Self.logger.info("loadCurricula background context created, launching Task.detached")

        // Capture logger for use in detached task (avoid MainActor isolation issue)
        let detachedLogger = Logger(label: "com.unamentis.curriculum.view.detached")

        // Use Task.detached to ensure we're truly off the MainActor
        let objectIDs: [NSManagedObjectID] = await Task.detached(priority: .userInitiated) {
            detachedLogger.info("loadCurricula Task.detached ENTERED")
            let result = await backgroundContext.perform {
                detachedLogger.info("loadCurricula backgroundContext.perform ENTERED")
                let request = Curriculum.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Curriculum.createdAt, ascending: false)]
                // Prefetch topics relationship
                request.relationshipKeyPathsForPrefetching = ["topics"]

                do {
                    detachedLogger.info("loadCurricula executing fetch...")
                    let results = try backgroundContext.fetch(request)
                    detachedLogger.info("loadCurricula fetched \(results.count) curricula")
                    return results.map { $0.objectID }
                } catch {
                    detachedLogger.error("loadCurricula fetch ERROR: \(error)")
                    return []
                }
            }
            detachedLogger.info("loadCurricula backgroundContext.perform COMPLETE")
            return result
        }.value

        Self.logger.info("loadCurricula Task.detached COMPLETE, updating UI with \(objectIDs.count) curricula")

        // Transfer to main context on MainActor
        await MainActor.run {
            let mainContext = PersistenceController.shared.container.viewContext
            self.curricula = objectIDs.compactMap { mainContext.object(with: $0) as? Curriculum }
            Self.logger.info("Loaded \(self.curricula.count) curricula to UI")
            self.isLoading = false
        }

        Self.logger.info("loadCurricula COMPLETE")
    }
}

// MARK: - Curriculum Row (for list view)

struct CurriculumRow: View {
    @ObservedObject var curriculum: Curriculum
    @State private var showingAddedConfirmation = false

    private var topicCount: Int {
        curriculum.topics?.count ?? 0
    }

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
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(curriculum.name ?? "Untitled Curriculum")
                    .font(.headline)

                if let summary = curriculum.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("\(topicCount) topics")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(curriculum.name ?? "Untitled Curriculum")")
        .accessibilityValue("\(topicCount) topics")
        .accessibilityHint("Double-tap to view curriculum details")
        .contextMenu {
            Button {
                addToTodoList()
            } label: {
                Label("Add to To-Do", systemImage: "checklist")
            }
        }
        .sensoryFeedback(.success, trigger: showingAddedConfirmation)
    }

    private func addToTodoList() {
        guard let curriculumId = curriculum.id else { return }

        Task {
            guard let manager = TodoManager.shared else { return }
            do {
                _ = try await manager.createCurriculumItem(
                    title: curriculum.name ?? "Untitled Curriculum",
                    curriculumId: curriculumId,
                    topicId: nil,
                    granularity: "curriculum",
                    source: .manual
                )
                showingAddedConfirmation = true
            } catch {
                // Error handling would go here
            }
        }
    }
}

// MARK: - Curriculum Detail View (shows topics)

struct CurriculumDetailView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var curriculum: Curriculum
    @State private var selectedTopic: Topic?
    @State private var showingAddedConfirmation = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addCurriculumToTodo()
                } label: {
                    Image(systemName: "checklist.checked")
                }
                .accessibilityLabel("Add curriculum to to-do list")
            }
        }
        .sensoryFeedback(.success, trigger: showingAddedConfirmation)
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

    private func addCurriculumToTodo() {
        guard let curriculumId = curriculum.id else { return }

        Task {
            guard let manager = TodoManager.shared else { return }
            do {
                _ = try await manager.createCurriculumItem(
                    title: curriculum.name ?? "Untitled Curriculum",
                    curriculumId: curriculumId,
                    topicId: nil,
                    granularity: "curriculum",
                    source: .manual
                )
                showingAddedConfirmation = true
            } catch {
                // Error handling would go here
            }
        }
    }
}

struct TopicRow: View {
    @ObservedObject var topic: Topic
    @State private var showingAddedConfirmation = false

    var body: some View {
        HStack {
            StatusIcon(status: topic.status)
                .accessibilityHidden(true)

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
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.title ?? "Untitled Topic")")
        .accessibilityValue("Status: \(topic.status.accessibilityDescription), \(Int(topic.mastery * 100)) percent mastery")
        .accessibilityHint("Double-tap to view topic details and start lesson")
        .contextMenu {
            Button {
                addToTodoList()
            } label: {
                Label("Add to To-Do", systemImage: "checklist")
            }
        }
        .sensoryFeedback(.success, trigger: showingAddedConfirmation)
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return "\(minutes)m spent"
    }

    private func addToTodoList() {
        guard let topicId = topic.id else { return }

        Task {
            guard let manager = TodoManager.shared else { return }
            do {
                _ = try await manager.createCurriculumItem(
                    title: topic.title ?? "Untitled Topic",
                    curriculumId: topic.curriculum?.id ?? UUID(),
                    topicId: topicId,
                    granularity: "topic",
                    source: .manual
                )
                showingAddedConfirmation = true
            } catch {
                // Error handling would go here
            }
        }
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
    @State private var showingAddedConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Action Buttons - Start Session and Add to To-Do
            HStack(spacing: 16) {
                // Start Session Button
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
                .accessibilityLabel("Start Lesson")
                .accessibilityHint("Begin a voice-guided lesson on \(topic.title ?? "this topic")")

                // Add to To-Do Button
                Button {
                    addToTodoList()
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                        Text("Add to To-Do")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .accessibilityLabel("Add to to-do list")
                .accessibilityHint("Add this topic to your to-do list for later study")
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .sensoryFeedback(.success, trigger: showingAddedConfirmation)

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

    private func addToTodoList() {
        guard let topicId = topic.id else { return }

        Task {
            guard let manager = TodoManager.shared else { return }
            do {
                _ = try await manager.createCurriculumItem(
                    title: topic.title ?? "Untitled Topic",
                    curriculumId: topic.curriculum?.id ?? UUID(),
                    topicId: topicId,
                    granularity: "topic",
                    source: .manual
                )
                showingAddedConfirmation = true
            } catch {
                // Error handling would go here
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
                CurriculumDownloadFlowView(
                    curriculum: curriculum,
                    detail: curriculumDetail,
                    onDownload: { selectedTopicIds in
                        await downloadCurriculum(curriculum, selectedTopicIds: selectedTopicIds)
                    },
                    onDismiss: {
                        selectedCurriculum = nil
                    }
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
    private func downloadCurriculum(_ curriculum: CurriculumSummary, selectedTopicIds: Set<String>) async {
        Self.logger.info("⬇️ Download initiated for curriculum: \(curriculum.title) (id: \(curriculum.id)) with \(selectedTopicIds.count) topics")
        Self.logger.info("⬇️ Selected topic IDs: \(selectedTopicIds)")

        downloadError = nil

        do {
            // Configure download manager with same server settings
            let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
            let host = serverIP.isEmpty ? "localhost" : serverIP
            Self.logger.info("⬇️ Configuring download manager with host: \(host):8766")
            try CurriculumDownloadManager.shared.configure(host: host, port: 8766)

            Self.logger.info("⬇️ Starting download via CurriculumDownloadManager...")

            let downloadedCurriculum = try await CurriculumDownloadManager.shared.downloadCurriculum(
                id: curriculum.id,
                title: curriculum.title,
                selectedTopicIds: selectedTopicIds
            )

            Self.logger.info("✅ Successfully downloaded and imported curriculum: \(curriculum.title)")
            Self.logger.info("✅ Curriculum has \(downloadedCurriculum.topics?.count ?? 0) topics")

            // Close sheet and notify parent
            selectedCurriculum = nil
            onDownload(downloadedCurriculum)
        } catch {
            Self.logger.error("❌ Failed to download curriculum: \(error)")
            Self.logger.error("❌ Error type: \(type(of: error))")

            var errorDetail = error.localizedDescription

            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    Self.logger.error("❌ DecodingError: Missing key '\(key.stringValue)' at path: \(path)")
                    errorDetail = "Missing data field: \(key.stringValue) at \(path)"
                case .typeMismatch(let type, let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    Self.logger.error("❌ DecodingError: Type mismatch for \(type) at path: \(path)")
                    errorDetail = "Data format error at: \(path)"
                case .valueNotFound(let type, let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    Self.logger.error("❌ DecodingError: Value not found for \(type) at path: \(path)")
                    errorDetail = "Missing value at: \(path)"
                case .dataCorrupted(let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    Self.logger.error("❌ DecodingError: Data corrupted at path: \(path)")
                    errorDetail = "Corrupted data at: \(path)"
                @unknown default:
                    Self.logger.error("❌ DecodingError: Unknown")
                    errorDetail = "Unknown data format error"
                }
            } else if let serviceError = error as? CurriculumServiceError {
                Self.logger.error("❌ CurriculumServiceError: \(serviceError)")
                errorDetail = serviceError.errorDescription ?? error.localizedDescription
            }

            // Show error alert, then dismiss sheet
            downloadError = errorDetail
            showingDownloadError = true
            selectedCurriculum = nil
        }
    }
}

// MARK: - Curriculum Download Flow View
// Wrapper view that handles navigation between detail and topic selection

struct CurriculumDownloadFlowView: View {
    let curriculum: CurriculumSummary
    let detail: CurriculumDetail?
    let onDownload: (Set<String>) async -> Void
    let onDismiss: () -> Void

    @State private var showingTopicSelection = false

    var body: some View {
        NavigationStack {
            if showingTopicSelection {
                TopicSelectionView(
                    curriculum: curriculum,
                    detail: detail,
                    onDownload: onDownload,
                    onCancel: {
                        showingTopicSelection = false
                    }
                )
            } else {
                ServerCurriculumDetailView(
                    curriculum: curriculum,
                    detail: detail,
                    onSelectTopics: {
                        showingTopicSelection = true
                    }
                )
            }
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
    let onSelectTopics: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Download Button - Opens topic selection
            Button {
                onSelectTopics()
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Download Topics")
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

// MARK: - Curriculum Help Sheet

/// In-app help for the curriculum view explaining concepts and navigation
struct CurriculumHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Overview Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Curricula are structured courses containing topics for progressive learning. Each topic is a focused lesson on a specific concept.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Curriculum vs Topic Section
                Section("Understanding Structure") {
                    CurriculumHelpRow(
                        icon: "book.fill",
                        iconColor: .blue,
                        title: "Curriculum",
                        description: "A complete course with multiple related topics."
                    )
                    CurriculumHelpRow(
                        icon: "doc.text.fill",
                        iconColor: .orange,
                        title: "Topic",
                        description: "A single lesson covering one concept with audio and visuals."
                    )
                    CurriculumHelpRow(
                        icon: "text.quote",
                        iconColor: .purple,
                        title: "Segment",
                        description: "A portion of a topic that covers one idea."
                    )
                }

                // Status Icons Section
                Section("Topic Status") {
                    HStack(spacing: 12) {
                        StatusIcon(status: .notStarted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not Started")
                                .font(.subheadline.weight(.medium))
                            Text("You haven't begun this topic yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        StatusIcon(status: .inProgress)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("In Progress")
                                .font(.subheadline.weight(.medium))
                            Text("You're currently studying this topic.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        StatusIcon(status: .completed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Completed")
                                .font(.subheadline.weight(.medium))
                            Text("You've finished this topic at least once.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        StatusIcon(status: .reviewing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reviewing")
                                .font(.subheadline.weight(.medium))
                            Text("You're revisiting for reinforcement.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Mastery Section
                Section("Mastery Score") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your mastery percentage shows how well you understand a topic:")
                            .font(.subheadline)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Time spent studying")
                            Text("• Questions answered correctly")
                            Text("• Amount of content covered")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text("Higher mastery means better understanding and retention.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }

                // Import Section
                Section("Getting Content") {
                    CurriculumHelpRow(
                        icon: "globe",
                        iconColor: .green,
                        title: "Browse Server",
                        description: "Download curricula from your management console."
                    )
                    CurriculumHelpRow(
                        icon: "doc.fill",
                        iconColor: .blue,
                        title: "Import from File",
                        description: "Import .umcf or .umcfz curriculum files from Files app."
                    )
                    CurriculumHelpRow(
                        icon: "doc.badge.plus",
                        iconColor: .orange,
                        title: "Load Sample",
                        description: "Try a built-in sample curriculum to get started."
                    )
                }

                // Tips Section
                Section("Tips") {
                    Label("Tap any topic to see details and start a lesson", systemImage: "hand.tap.fill")
                        .foregroundStyle(.blue, .primary)
                    Label("Swipe left on a curriculum to delete it", systemImage: "hand.draw.fill")
                        .foregroundStyle(.red, .primary)
                    Label("Pull down to refresh your curriculum list", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.green, .primary)
                }
            }
            .navigationTitle("Curriculum Help")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Helper row for curriculum help items
private struct CurriculumHelpRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

#Preview {
    CurriculumView()
        .environmentObject(AppState())
}

#Preview("Curriculum Help") {
    CurriculumHelpSheet()
}
