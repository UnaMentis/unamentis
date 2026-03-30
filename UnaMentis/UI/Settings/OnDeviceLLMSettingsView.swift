// UnaMentis - On-Device LLM Settings View
// Settings UI for managing multiple on-device LLM models
//
// Part of UI/Settings

import SwiftUI

/// Settings view for on-device LLM model management
///
/// Features:
/// - Browse available models with status indicators
/// - Download/delete individual models
/// - Select active model for inference
/// - View model details and storage usage
struct OnDeviceLLMSettingsView: View {

    @StateObject private var viewModel = OnDeviceLLMSettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Active model indicator
            activeModelSection

            // Model catalog
            modelCatalogSection

            // Why download section (shown when no models downloaded)
            if viewModel.downloadedCount == 0 {
                benefitsSection
            }

            // Storage overview
            if viewModel.downloadedCount > 0 {
                storageSection
            }

            // Advanced settings
            Section {
                NavigationLink {
                    OnDeviceLLMAdvancedSettingsView()
                } label: {
                    Label("Advanced Settings", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("Tune inference parameters, FOV context budgets, response latency, and thermal behavior.")
            }
        }
        .navigationTitle("On-Device LLM")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task {
                await viewModel.refreshState()
            }
        }
    }

    // MARK: - Active Model Section

    private var activeModelSection: some View {
        Section {
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(.blue)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Model")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(viewModel.selectedModel.config.displayName)
                        .font(.headline)
                }
                Spacer()
                statusBadge(for: viewModel.modelState(for: viewModel.selectedModel))
            }
        } footer: {
            if viewModel.isSelectedModelReady {
                Text("Model is loaded and ready for offline inference.")
            } else if viewModel.isSelectedModelDownloaded {
                Text("Model is downloaded. It will load automatically when needed.")
            } else {
                Text("Download a model to enable on-device AI features.")
            }
        }
    }

    // MARK: - Model Catalog Section

    private var modelCatalogSection: some View {
        Section {
            ForEach(OnDeviceLLMModel.allCases, id: \.rawValue) { model in
                NavigationLink {
                    ModelDetailView(model: model, viewModel: viewModel)
                } label: {
                    modelRow(for: model)
                }
            }
        } header: {
            Text("Available Models")
        } footer: {
            Text("All models use Q4_K_M quantization for optimal quality-to-size ratio on Apple Silicon.")
        }
    }

    private func modelRow(for model: OnDeviceLLMModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.config.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if model.isRecommended {
                        Text("Recommended")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    if model == viewModel.selectedModel {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text("\(model.config.expectedSizeFormatted) \u{2022} \(model.config.publisher)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(for: viewModel.modelState(for: model))
        }
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        Section {
            ForEach(OnDeviceLLMModelConfig.keepModelReasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Text(reason)
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Why Download?")
        } footer: {
            Text("On-device models enable advanced features that work without an internet connection.")
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section {
            HStack {
                Text("Models Downloaded")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.downloadedCount) of \(OnDeviceLLMModel.allCases.count)")
                    .font(.subheadline)
            }
            HStack {
                Text("Total Storage Used")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.totalStorageFormatted)
                    .font(.subheadline)
            }
        } header: {
            Text("Storage")
        }
    }

    // MARK: - Helpers

    private func statusBadge(for state: OnDeviceLLMModelManager.ModelState) -> some View {
        Group {
            switch state {
            case .notDownloaded:
                Text("Not Downloaded")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.gray.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            case .downloading(let progress):
                Text("Downloading \(Int(progress * 100))%")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            case .verifying:
                Text("Verifying")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            case .available:
                Text("Downloaded")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            case .loading:
                Text("Loading")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            case .loaded:
                Text("Active")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            case .error:
                Text("Error")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Model Detail View

/// Detail view for a single on-device LLM model
private struct ModelDetailView: View {
    let model: OnDeviceLLMModel
    @ObservedObject var viewModel: OnDeviceLLMSettingsViewModel
    @State private var showDeleteConfirmation = false

    private var config: OnDeviceLLMModelConfig { model.config }
    private var state: OnDeviceLLMModelManager.ModelState { viewModel.modelState(for: model) }

    var body: some View {
        List {
            // Status and actions
            statusSection

            // Download progress
            if viewModel.isDownloading(model) {
                progressSection
            }

            // Model info
            infoSection

            // Storage management (if downloaded)
            if viewModel.isDownloaded(model) {
                storageManagementSection
            }
        }
        .navigationTitle(config.displayName)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task { await viewModel.refreshState() }
        }
        .alert("Delete \(config.displayName)?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteModel(model) }
            }
        } message: {
            Text("This will remove the \(config.expectedSizeFormatted) model from your device. You can re-download it anytime.")
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            // Status indicator
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.displayText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(statusSubtext)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Action buttons
            actionButtons
        } header: {
            Text("Status")
        } footer: {
            if model.isRecommended {
                Text("Recommended for most devices. Compact size with excellent quality.")
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch state {
        case .notDownloaded:
            Button {
                Task { await viewModel.downloadModel(model) }
            } label: {
                HStack {
                    Label("Download Model", systemImage: "arrow.down.circle")
                    Spacer()
                    Text("~\(config.expectedSizeFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!viewModel.hasEnoughStorage(for: model))

            if !viewModel.hasEnoughStorage(for: model) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Not enough storage space")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

        case .downloading:
            Button(role: .destructive) {
                Task { await viewModel.cancelDownload(for: model) }
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }

        case .available:
            if model != viewModel.selectedModel {
                Button {
                    Task { await viewModel.selectModel(model) }
                } label: {
                    Label("Set as Active Model", systemImage: "checkmark.circle")
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Currently Active")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }

        case .loaded:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Loaded and Ready")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

        case .verifying, .loading:
            EmptyView()

        case .error:
            Button {
                Task { await viewModel.refreshState() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }
    }

    private var statusIcon: some View {
        Group {
            switch state {
            case .notDownloaded:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
            case .downloading:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            case .verifying:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.orange)
            case .available:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            case .loading:
                Image(systemName: "cpu")
                    .foregroundStyle(.blue)
            case .loaded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.title2)
    }

    private var statusSubtext: String {
        switch state {
        case .notDownloaded:
            return "Download to enable on-device AI"
        case .downloading:
            return "Downloading from Hugging Face..."
        case .verifying:
            return "Verifying download..."
        case .available:
            let sizeMB = viewModel.modelSizeMB(for: model)
            return model == viewModel.selectedModel
                ? "Active model (\(sizeMB) MB)"
                : "Ready (\(sizeMB) MB)"
        case .loading:
            return "Loading into memory..."
        case .loaded:
            return "Ready for inference"
        case .error(let message):
            return message
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: viewModel.downloadProgress(for: model))
                    .progressViewStyle(.linear)

                HStack {
                    Text("Downloading from Hugging Face...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.downloadProgress(for: model) * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            InfoRow(label: "Model", value: config.displayName)
            InfoRow(label: "Version", value: config.version)
            InfoRow(label: "Publisher", value: config.publisher)
            InfoRow(label: "Size", value: config.expectedSizeFormatted)
            InfoRow(label: "Quantization", value: config.quantization)
            InfoRow(label: "Context Window", value: "\(config.contextSize) tokens")
            InfoRow(label: "Min RAM", value: "\(config.minimumRAMGB) GB")
            InfoRow(label: "License", value: config.license)
        } header: {
            Text("Model Information")
        } footer: {
            Text(config.description)
        }
    }

    // MARK: - Storage Management Section

    private var storageManagementSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Used")
                        .font(.subheadline)
                    Text("\(viewModel.modelSizeMB(for: model)) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            // Warning about deletion
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Before You Delete")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                ForEach(OnDeviceLLMModelConfig.deletionConsequences, id: \.self) { consequence in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\u{2022}")
                            .foregroundStyle(.secondary)
                        Text(consequence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

        } header: {
            Text("Storage Management")
        } footer: {
            Text("You can re-download this model anytime from Settings.")
        }
    }
}

// MARK: - View Model

@MainActor
final class OnDeviceLLMSettingsViewModel: ObservableObject {
    @Published var selectedModel: OnDeviceLLMModel = .defaultModel
    @Published var modelStates: [OnDeviceLLMModel: OnDeviceLLMModelManager.ModelState] = [:]
    @Published var errorMessage: String?

    private var modelManager: OnDeviceLLMModelManager?
    private var refreshTasks: [OnDeviceLLMModel: Task<Void, Never>] = [:]

    init() {
        Task {
            await setupModelManager()
        }
    }

    private func setupModelManager() async {
        modelManager = OnDeviceLLMModelManager.shared
        selectedModel = await modelManager!.selectedModel
        await refreshState()
    }

    func refreshState() async {
        guard let manager = modelManager else { return }

        selectedModel = await manager.selectedModel
        for model in OnDeviceLLMModel.allCases {
            modelStates[model] = await manager.currentState(for: model)
        }
    }

    func modelState(for model: OnDeviceLLMModel) -> OnDeviceLLMModelManager.ModelState {
        modelStates[model] ?? .notDownloaded
    }

    var isSelectedModelReady: Bool {
        modelState(for: selectedModel).isReady
    }

    var isSelectedModelDownloaded: Bool {
        modelState(for: selectedModel).isAvailable
    }

    func isDownloaded(_ model: OnDeviceLLMModel) -> Bool {
        let state = modelState(for: model)
        switch state {
        case .available, .loading, .loaded:
            return true
        default:
            return false
        }
    }

    func isDownloading(_ model: OnDeviceLLMModel) -> Bool {
        if case .downloading = modelState(for: model) { return true }
        return false
    }

    func downloadProgress(for model: OnDeviceLLMModel) -> Float {
        if case .downloading(let progress) = modelState(for: model) {
            return progress
        }
        return 0
    }

    func modelSizeMB(for model: OnDeviceLLMModel) -> Int {
        guard let manager = modelManager else { return 0 }
        // Use a cached/sync approach; actual size fetched during refresh
        return model.config.expectedSizeMB
    }

    var downloadedCount: Int {
        OnDeviceLLMModel.allCases.filter { isDownloaded($0) }.count
    }

    var totalStorageFormatted: String {
        let totalMB = OnDeviceLLMModel.allCases
            .filter { isDownloaded($0) }
            .reduce(0) { $0 + $1.config.expectedSizeMB }
        let gb = Double(totalMB) / 1000
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            return "\(totalMB) MB"
        }
    }

    func hasEnoughStorage(for model: OnDeviceLLMModel) -> Bool {
        // Need model size + temp file during download
        let requiredBytes = Int64(Double(model.config.expectedSizeBytes) * 1.5)
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let freeSpace = attrs[.systemFreeSize] as? Int64 ?? 0
            return freeSpace >= requiredBytes
        } catch {
            return true // Assume we have space if we can't check
        }
    }

    func downloadModel(_ model: OnDeviceLLMModel) async {
        guard let manager = modelManager else { return }

        // Start progress monitoring
        refreshTasks[model] = Task {
            while !Task.isCancelled {
                await refreshState()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        do {
            try await manager.downloadModel(for: model)
            await refreshState()
        } catch {
            errorMessage = error.localizedDescription
            await refreshState()
        }

        refreshTasks[model]?.cancel()
        refreshTasks[model] = nil
    }

    func cancelDownload(for model: OnDeviceLLMModel) async {
        guard let manager = modelManager else { return }
        await manager.cancelDownload(for: model)
        refreshTasks[model]?.cancel()
        refreshTasks[model] = nil
        await refreshState()
    }

    func deleteModel(_ model: OnDeviceLLMModel) async {
        guard let manager = modelManager else { return }

        do {
            try await manager.deleteModel(for: model)
            await refreshState()
        } catch {
            errorMessage = error.localizedDescription
            await refreshState()
        }
    }

    func selectModel(_ model: OnDeviceLLMModel) async {
        guard let manager = modelManager else { return }
        await manager.selectModel(model)
        await refreshState()
    }
}

// MARK: - Helper Views

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OnDeviceLLMSettingsView()
    }
}
