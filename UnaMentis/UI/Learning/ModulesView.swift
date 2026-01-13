// UnaMentis - Modules View
// Lists available specialized training modules from the server
//
// Modules are server-delivered, not bundled with the app:
// - Fetches available modules from the connected server
// - Users can download modules they want to use
// - Shows both available and downloaded modules

import SwiftUI
import Logging

/// Wrapper for module ID to make it Identifiable for fullScreenCover
struct LaunchedModuleIdentifier: Identifiable {
    let id: String
}

/// View displaying available specialized training modules
struct ModulesView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var moduleService = ModuleService.shared
    @StateObject private var moduleRegistry = ModuleRegistry.shared

    @State private var availableModules: [ModuleSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedModule: ModuleSummary?
    @State private var showingModuleDetail = false
    @State private var launchedModule: LaunchedModuleIdentifier?

    private static let logger = Logger(label: "com.unamentis.modules.view")

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else if availableModules.isEmpty && moduleRegistry.allDownloaded.isEmpty {
                emptyStateView
            } else {
                moduleListView
            }
        }
        .task {
            await configureAndFetch()
        }
        .refreshable {
            await fetchModules()
        }
        .sheet(item: $selectedModule) { module in
            NavigationStack {
                ModuleDetailSheet(
                    module: module,
                    isDownloaded: moduleRegistry.isDownloaded(moduleId: module.id),
                    onDownload: { await downloadModule(module) },
                    onLaunch: { launchModule(module) }
                )
            }
        }
        .fullScreenCover(item: $launchedModule) { module in
            NavigationStack {
                moduleViewForId(module.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                launchedModule = nil
                            }
                        }
                    }
            }
        }
    }

    /// Returns the appropriate view for a module ID
    @ViewBuilder
    private func moduleViewForId(_ moduleId: String) -> some View {
        switch moduleId {
        case "knowledge-bowl":
            KBDashboardView()
        default:
            ContentUnavailableView(
                "Module Not Found",
                systemImage: "questionmark.circle",
                description: Text("This module is not available.")
            )
        }
    }

    // MARK: - Views

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading modules...")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Connection Error", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await fetchModules() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Modules Available", systemImage: "puzzlepiece.extension")
        } description: {
            Text("Connect to a server to browse available training modules.")
        } actions: {
            Button("Refresh") {
                Task { await fetchModules() }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var moduleListView: some View {
        List {
            // Downloaded modules section
            if !moduleRegistry.allDownloaded.isEmpty {
                Section {
                    ForEach(moduleRegistry.allDownloaded, id: \.id) { module in
                        DownloadedModuleRow(module: module)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Launch downloaded module
                                if let summary = availableModules.first(where: { $0.id == module.id }) {
                                    launchModule(summary)
                                }
                            }
                    }
                    .onDelete(perform: deleteDownloadedModules)
                } header: {
                    Text("Downloaded")
                } footer: {
                    Text("Tap to start practicing. Swipe to remove.")
                }
            }

            // Available modules from server
            if !availableModules.isEmpty {
                Section {
                    ForEach(availableModules) { module in
                        ServerModuleRow(
                            module: module,
                            isDownloaded: moduleRegistry.isDownloaded(moduleId: module.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedModule = module
                        }
                    }
                } header: {
                    Text("Available on Server")
                } footer: {
                    Text("Modules provide specialized training for competitions and skill development.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await fetchModules() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    // MARK: - Data Loading

    private func configureAndFetch() async {
        // Get server IP from UserDefaults (configured in Settings)
        let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
        let host = serverIP.isEmpty ? "localhost" : serverIP

        do {
            try await moduleService.configure(host: host, port: 8766)
            await fetchModules()
        } catch {
            Self.logger.error("Failed to configure module service: \(error)")
            errorMessage = "Failed to connect to server"
            isLoading = false
        }
    }

    private func fetchModules() async {
        isLoading = true
        errorMessage = nil

        do {
            availableModules = try await moduleService.fetchAvailableModules()
            Self.logger.info("Fetched \(availableModules.count) modules")
        } catch {
            Self.logger.error("Failed to fetch modules: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func downloadModule(_ module: ModuleSummary) async {
        do {
            _ = try await moduleService.downloadModule(moduleId: module.id)
            Self.logger.info("Downloaded module: \(module.name)")
        } catch {
            Self.logger.error("Failed to download module: \(error)")
        }
    }

    private func launchModule(_ module: ModuleSummary) {
        Self.logger.info("Launching module: \(module.name)")
        launchedModule = LaunchedModuleIdentifier(id: module.id)
    }

    private func deleteDownloadedModules(at offsets: IndexSet) {
        let downloaded = moduleRegistry.allDownloaded
        for index in offsets {
            let module = downloaded[index]
            moduleRegistry.removeDownloaded(moduleId: module.id)
        }
    }
}

// MARK: - Server Module Row

struct ServerModuleRow: View {
    let module: ModuleSummary
    let isDownloaded: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Module icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(module.themeColor.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: module.iconName)
                    .font(.title2)
                    .foregroundStyle(module.themeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(module.name)
                        .font(.headline)

                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                Text(module.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Feature badges
                HStack(spacing: 8) {
                    if module.supportsTeamMode {
                        FeatureBadge(text: "Team", icon: "person.2.fill", color: .blue)
                    }
                    if module.supportsSpeedTraining {
                        FeatureBadge(text: "Speed", icon: "bolt.fill", color: .orange)
                    }
                    if module.supportsCompetitionSim {
                        FeatureBadge(text: "Competition", icon: "trophy.fill", color: .yellow)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Downloaded Module Row

struct DownloadedModuleRow: View {
    let module: DownloadedModule

    var themeColor: Color {
        Color(hex: module.themeColorHex) ?? .purple
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeColor.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: module.iconName)
                    .font(.title2)
                    .foregroundStyle(themeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(module.name)
                    .font(.headline)

                Text(module.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("Ready to practice")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(themeColor)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Feature Badge

struct FeatureBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Module Detail Sheet

struct ModuleDetailSheet: View {
    let module: ModuleSummary
    let isDownloaded: Bool
    let onDownload: () async -> Void
    let onLaunch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isDownloading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(module.themeColor.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: module.iconName)
                            .font(.largeTitle)
                            .foregroundStyle(module.themeColor)
                    }

                    Text(module.name)
                        .font(.title.bold())

                    Text(module.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()

                // Action button
                if isDownloaded {
                    Button {
                        onLaunch()
                        dismiss()
                    } label: {
                        Label("Start Practicing", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(module.themeColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                } else {
                    Button {
                        Task {
                            isDownloading = true
                            await onDownload()
                            isDownloading = false
                        }
                    } label: {
                        if isDownloading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Label("Download Module", systemImage: "arrow.down.circle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(module.themeColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isDownloading)
                    .padding(.horizontal)

                    if let size = module.downloadSize {
                        Text("Download size: \(formatBytes(size))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Features
                VStack(alignment: .leading, spacing: 12) {
                    Text("Features")
                        .font(.headline)

                    if module.supportsTeamMode {
                        FeatureRow(icon: "person.2.fill", title: "Team Mode", description: "Practice with your team in synchronized sessions")
                    }
                    if module.supportsSpeedTraining {
                        FeatureRow(icon: "bolt.fill", title: "Speed Training", description: "Build quick recall with timed drills")
                    }
                    if module.supportsCompetitionSim {
                        FeatureRow(icon: "trophy.fill", title: "Competition Simulation", description: "Practice in realistic competition conditions")
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Spacer()
            }
        }
        .navigationTitle("Module Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ModulesView()
            .environmentObject(AppState())
    }
}
