//
//  KBEnhancedValidationSetupView.swift
//  UnaMentis
//
//  Setup view for enhanced answer validation (Tier 2 & 3)
//  Allows users to download embeddings model and enable LLM validation
//  Features are controlled by server administrator via feature flags
//

import SwiftUI
import OSLog

// MARK: - Enhanced Validation Setup View

struct KBEnhancedValidationSetupView: View {
    @StateObject private var viewModel = ViewModel()

    var body: some View {
        List {
            // Device Capability Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(DeviceCapability.deviceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Device Information")
            }

            // Tier 2: Embeddings
            if DeviceCapability.supportsEmbeddings() {
                Section {
                    tier2Content
                } header: {
                    Text("Tier 2: Semantic Matching")
                } footer: {
                    Text("Uses sentence embeddings to better understand answer meaning. Improves accuracy to 92-95%. Requires 80MB download.")
                }
            }

            // Tier 3: LLM Validation
            if DeviceCapability.supportsLLMValidation() {
                Section {
                    tier3Content
                } header: {
                    Text("Tier 3: LLM Validation")
                } footer: {
                    Text("Uses a small open-source language model (Llama 3.2 1B) for expert-level validation. Achieves 95-98% accuracy. Requires 1.5GB download. Availability controlled by server administrator.")
                }
            }
        }
        .navigationTitle("Enhanced Validation")
        .task {
            await viewModel.loadState()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Tier 2 Content

    @ViewBuilder
    private var tier2Content: some View {
        switch viewModel.embeddingsState {
        case .notDownloaded:
            Button {
                Task {
                    await viewModel.downloadEmbeddings()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text("Download Embeddings Model")
                    Spacer()
                    Text("80 MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(Text("Download embeddings model, 80 megabytes", comment: "Accessibility label for embeddings download button"))

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloading...")
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .accessibilityLabel(Text("Download progress", comment: "Accessibility label for download progress bar"))
                    .accessibilityValue(Text("\(Int(progress * 100)) percent", comment: "Accessibility value showing download percentage"))
            }
            .accessibilityElement(children: .combine)

        case .available:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Model Downloaded")
                Spacer()
                Button("Remove") {
                    Task {
                        await viewModel.removeEmbeddings()
                    }
                }
                .foregroundStyle(.red)
                .accessibilityLabel(Text("Remove downloaded embeddings model", comment: "Accessibility label for remove embeddings button"))
            }

        case .loaded:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Model Active")
                Spacer()
                Text("Tier 2 Enabled")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Embeddings model active, tier 2 validation enabled", comment: "Accessibility label for active embeddings status"))

        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Error")
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task {
                        await viewModel.downloadEmbeddings()
                    }
                }
                .accessibilityLabel(Text("Retry downloading embeddings model", comment: "Accessibility label for retry embeddings download button"))
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Tier 3 Content

    @ViewBuilder
    private var tier3Content: some View {
        if !viewModel.isLLMFeatureEnabled {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary)
                    Text("Feature Not Enabled")
                }
                Text("LLM validation has not been enabled by your server administrator. Contact your administrator to request access to this feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            switch viewModel.llmState {
            case .notConfigured:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                        Text("LLM Service Not Configured")
                    }
                    Text("The on-device LLM service needs to be configured. This requires the Ministral or TinyLlama model to be bundled with the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .loading:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Loading LLM...")
                        Spacer()
                        ProgressView()
                            .accessibilityLabel(Text("Loading LLM model", comment: "Accessibility label for LLM loading progress"))
                    }
                }
                .accessibilityElement(children: .combine)

            case .available:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Model Downloaded")
                    Spacer()
                    Button("Remove") {
                        Task {
                            await viewModel.removeLLM()
                        }
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel(Text("Remove downloaded LLM model", comment: "Accessibility label for remove LLM button"))
                }

            case .loaded:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Model Active")
                    Spacer()
                    Text("Tier 3 Enabled")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("LLM model active, tier 3 validation enabled", comment: "Accessibility label for active LLM status"))

            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Error")
                    }
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task {
                            await viewModel.downloadLLM()
                        }
                    }
                    .accessibilityLabel(Text("Retry downloading LLM model", comment: "Accessibility label for retry LLM download button"))
                }
                .accessibilityElement(children: .contain)
            }
        }
    }
}

// MARK: - View Model

extension KBEnhancedValidationSetupView {
    @MainActor
    class ViewModel: ObservableObject {
        private let logger = Logger(subsystem: "com.unamentis", category: "KBEnhancedValidationSetup")

        @Published var embeddingsState: KBEmbeddingsService.ModelState = .notDownloaded
        @Published var llmState: KBLLMValidator.ModelState = .notConfigured
        @Published var isLLMFeatureEnabled = false
        @Published var showError = false
        @Published var errorMessage: String?

        private var embeddingsService: KBEmbeddingsService?
        private var llmValidator: KBLLMValidator?
        private var featureFlags: KBFeatureFlags?

        func loadState() async {
            // Initialize services
            embeddingsService = KBEmbeddingsService()
            // llmValidator = KBLLMValidator() // TODO: Implement

            // Load feature flags from server configuration
            // TODO: Fetch from server - for now use default configuration
            featureFlags = .defaultConfiguration()

            // Load states
            if let service = embeddingsService {
                embeddingsState = await service.currentState()
            }

            // Check if LLM feature is enabled by server admin
            if let flags = featureFlags {
                isLLMFeatureEnabled = await flags.isFeatureEnabled(.llmValidation)
            }
        }

        func downloadEmbeddings() async {
            guard let service = embeddingsService else { return }

            do {
                try await service.downloadModel { @Sendable [weak self] progress in
                    Task { @MainActor in
                        self?.embeddingsState = .downloading(progress)
                    }
                }
                embeddingsState = await service.currentState()
            } catch {
                logger.error("Failed to download embeddings: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
            }
        }

        func removeEmbeddings() async {
            // TODO: Implement removal
            logger.info("Removing embeddings model")
        }

        func downloadLLM() async {
            // TODO: Implement LLM download
            logger.info("Downloading LLM model")
        }

        func removeLLM() async {
            // TODO: Implement LLM removal
            logger.info("Removing LLM model")
        }
    }
}

// MARK: - Preview Support

#if DEBUG
struct KBEnhancedValidationSetupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            KBEnhancedValidationSetupView()
        }
    }
}
#endif
