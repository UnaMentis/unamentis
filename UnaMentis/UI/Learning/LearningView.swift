// UnaMentis - Learning View
// Container view with segmented control for Curriculum and Modules
//
// Part of the Learning tab that provides access to both structured
// curriculum content and specialized training modules.

import SwiftUI
import Logging
import CoreData
import UniformTypeIdentifiers

/// Sections available in the Learning tab
enum LearningSection: String, CaseIterable, Identifiable {
    case curriculum = "Curriculum"
    case modules = "Modules"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .curriculum: return "book.fill"
        case .modules: return "puzzlepiece.extension.fill"
        }
    }
}

/// Main Learning tab view with segmented control navigation
struct LearningView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSection: LearningSection = .curriculum

    private static let logger = Logger(label: "com.unamentis.learning.view")

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control for section selection
                Picker("Learning Section", selection: $selectedSection) {
                    ForEach(LearningSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Divider()

                // Content based on selection
                switch selectedSection {
                case .curriculum:
                    CurriculumContentView()
                        .environmentObject(appState)
                case .modules:
                    ModulesView()
                        .environmentObject(appState)
                }
            }
            .navigationTitle("Learning")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BrandLogo(size: .compact)
                }
            }
        }
        .onChange(of: selectedSection) { _, newSection in
            Self.logger.debug("Learning section changed to: \(newSection.rawValue)")
        }
    }
}

/// Wrapper for CurriculumView that removes its own NavigationStack
/// since LearningView provides the navigation context
struct CurriculumContentView: View {
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

    private static let logger = Logger(label: "com.unamentis.curriculum.content")

    var body: some View {
        curriculumListContent
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
                    CurriculumRowCompact(curriculum: curriculum)
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
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        showingCurriculumHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Curriculum help")

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
                            .accessibilityLabel("Curriculum options")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCurriculumHelp) {
            CurriculumHelpSheet()
        }
        .task {
            await loadCurricula()
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
                showingServerBrowser = false
                Task { await loadCurricula() }
            }
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
        .alert("Import Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    @MainActor
    private func loadSampleCurriculum() async {
        isLoading = true
        do {
            let seeder = SampleCurriculumSeeder()
            try seeder.seedPyTorchCurriculum()
            await loadCurricula()
        } catch {
            importError = error.localizedDescription
            showingError = true
            isLoading = false
        }
    }

    @MainActor
    private func handleFileImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImportingFile = true
            isLoading = true

            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw UMCFFileError.fileReadFailed("Unable to access file")
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let fileHandler = UMCFFileHandler()
                _ = try await fileHandler.importAndStore(from: url)
                await loadCurricula()
            } catch {
                importError = error.localizedDescription
                showingError = true
                isLoading = false
            }
            isImportingFile = false

        case .failure(let error):
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
            context.delete(curriculum)
        }

        do {
            try context.save()
            curricula.remove(atOffsets: offsets)
        } catch {
            importError = error.localizedDescription
            showingError = true
        }
    }

    private func loadCurricula() async {
        await MainActor.run { isLoading = true }

        let backgroundContext = PersistenceController.shared.newBackgroundContext()
        let detachedLogger = Logger(label: "com.unamentis.curriculum.content.detached")

        let objectIDs: [NSManagedObjectID] = await Task.detached(priority: .userInitiated) {
            await backgroundContext.perform {
                let request = Curriculum.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Curriculum.createdAt, ascending: false)]
                request.relationshipKeyPathsForPrefetching = ["topics"]

                do {
                    let results = try backgroundContext.fetch(request)
                    return results.map { $0.objectID }
                } catch {
                    detachedLogger.error("loadCurricula fetch ERROR: \(error)")
                    return []
                }
            }
        }.value

        await MainActor.run {
            let mainContext = PersistenceController.shared.container.viewContext
            self.curricula = objectIDs.compactMap { mainContext.object(with: $0) as? Curriculum }
            self.isLoading = false
        }
    }
}

/// Compact curriculum row for use within LearningView
struct CurriculumRowCompact: View {
    @ObservedObject var curriculum: Curriculum

    private var topicCount: Int {
        curriculum.topics?.count ?? 0
    }

    var body: some View {
        HStack {
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

#Preview {
    LearningView()
        .environmentObject(AppState())
}
