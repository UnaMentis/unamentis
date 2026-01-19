//
//  LearningView.swift
//  UnaMentis
//
//  Main learning hub with sections for Curriculum and Modules
//

import CoreData
import Logging
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Learning Section Enum

/// Sections available in the Learning tab
enum LearningSection: String, CaseIterable, Identifiable {
    case curriculum = "Curriculum"
    case modules = "Modules"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .curriculum: return "book.fill"
        case .modules: return "square.stack.3d.up.fill"
        }
    }
}

// MARK: - Learning View

/// Main learning hub that provides access to Curriculum and Modules
struct LearningView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSection: LearningSection = .curriculum
    @State private var modulesEnabled = false
    @State private var checkingFeatureFlag = true

    private static let logger = Logger(label: "com.unamentis.learning.view")

    /// Available sections based on feature flags
    private var availableSections: [LearningSection] {
        modulesEnabled ? LearningSection.allCases : [.curriculum]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Only show segmented control if modules are enabled
                if modulesEnabled {
                    Picker("Learning Section", selection: $selectedSection) {
                        ForEach(availableSections) { section in
                            Label(section.rawValue, systemImage: section.icon)
                                .tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    Divider()
                }

                // Content based on selection
                switch selectedSection {
                case .curriculum:
                    CurriculumContentView()
                        .environmentObject(appState)
                case .modules:
                    if modulesEnabled {
                        ModulesView()
                            .environmentObject(appState)
                    } else {
                        // Fallback to curriculum if modules disabled
                        CurriculumContentView()
                            .environmentObject(appState)
                    }
                }
            }
            .navigationTitle("Learning")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BrandLogo(size: .compact)
                }
            }
        }
        .task {
            await checkFeatureFlags()
        }
        .onChange(of: selectedSection) { _, newSection in
            Self.logger.debug("Learning section changed to: \(newSection.rawValue)")
        }
    }

    /// Check feature flags for modules visibility
    private func checkFeatureFlags() async {
        checkingFeatureFlag = true

        // Check if specialized modules feature is enabled
        // Key matches FeatureFlagKeys.specializedModules
        var enabled = await FeatureFlagService.shared.isEnabled("feature_specialized_modules")

        // For development: enable modules when flag service is unavailable
        #if DEBUG
        if !enabled {
            Self.logger.debug("Feature flag disabled or unavailable, enabling modules for DEBUG build")
            enabled = true
        }
        #endif

        await MainActor.run {
            modulesEnabled = enabled
            checkingFeatureFlag = false

            // If modules are disabled and currently selected, switch to curriculum
            if !enabled && selectedSection == .modules {
                selectedSection = .curriculum
            }
        }

        Self.logger.info("Specialized modules feature flag: \(enabled)")
    }
}

// MARK: - Curriculum Content View

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
                    Button {
                        Self.logger.debug("Curriculum tapped: \(curriculum.name ?? "unknown")")
                        selectedCurriculum = curriculum
                    } label: {
                        CurriculumRowCompact(curriculum: curriculum)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(curriculum.name ?? "Curriculum")
                    .accessibilityHint("Double tap to select")
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
            try seeder.deleteAllCurricula()
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

        // Capture logger for use in detached task (avoid MainActor isolation issue)
        let detachedLogger = Logger(label: "com.unamentis.curriculum.content.detached")

        // Use Task.detached to ensure we're truly off the MainActor
        let objectIDs: [NSManagedObjectID] = await Task.detached(priority: .userInitiated) {
            let result = await backgroundContext.perform {
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
            return result
        }.value

        await MainActor.run {
            let mainContext = PersistenceController.shared.container.viewContext
            self.curricula = objectIDs.compactMap { mainContext.object(with: $0) as? Curriculum }
            self.isLoading = false
        }
    }
}

// MARK: - Curriculum Row Compact

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

// MARK: - Modules View

/// Grid view showing available learning modules like Knowledge Bowl
struct ModulesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learning Modules")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Interactive learning experiences beyond traditional curriculum")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Modules grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    // Knowledge Bowl Module
                    NavigationLink(destination: KBDashboardView()) {
                        ModuleCard(
                            title: "Knowledge Bowl",
                            subtitle: "Academic competition training",
                            icon: "brain.head.profile",
                            color: .kbMastered,
                            status: "Available"
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Future modules (placeholders)
                    ModuleCard(
                        title: "Flashcards",
                        subtitle: "Spaced repetition study",
                        icon: "rectangle.on.rectangle.angled",
                        color: .blue,
                        status: "Coming Soon"
                    )
                    .opacity(0.6)

                    ModuleCard(
                        title: "Practice Tests",
                        subtitle: "Timed assessments",
                        icon: "clock.badge.checkmark",
                        color: .orange,
                        status: "Coming Soon"
                    )
                    .opacity(0.6)

                    ModuleCard(
                        title: "Study Groups",
                        subtitle: "Collaborative learning",
                        icon: "person.3.fill",
                        color: .purple,
                        status: "Coming Soon"
                    )
                    .opacity(0.6)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Module Card

struct ModuleCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)

            // Title and subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Status badge
            Text(status)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(status == "Available" ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status == "Available" ? color : Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#if DEBUG
struct LearningView_Previews: PreviewProvider {
    static var previews: some View {
        LearningView()
            .environmentObject(AppState())
    }
}

struct ModulesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ModulesView()
                .environmentObject(AppState())
        }
    }
}
#endif
