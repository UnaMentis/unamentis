// UnaMentis - On-Device LLM Model Manager
// Manages multiple on-device LLM models: download, storage, selection, and lifecycle
//
// Part of Services/LLM

import Foundation
import OSLog

// MARK: - Chat Format

/// Chat prompt format used by a model
public enum ChatFormat: String, Sendable {
    case mistral    // [INST] ... [/INST]
    case chatML     // <|im_start|> ... <|im_end|>
}

// MARK: - Model Configuration

/// Model configuration for on-device LLM
public struct OnDeviceLLMModelConfig: Sendable {
    /// Model identifier
    let id: String
    /// Display name
    let displayName: String
    /// Hugging Face repository
    let huggingFaceRepo: String
    /// Filename in the repository
    let filename: String
    /// Expected file size in bytes
    let expectedSizeBytes: Int64
    /// Quantization type
    let quantization: String
    /// Context window size
    let contextSize: UInt32
    /// Minimum RAM required in GB
    let minimumRAMGB: Int
    /// Description for users
    let description: String
    /// Chat prompt format
    let chatFormat: ChatFormat
    /// Publisher/creator
    let publisher: String
    /// License
    let license: String
    /// Release version/date
    let version: String

    /// Direct download URL from Hugging Face CDN
    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(huggingFaceRepo)/resolve/main/\(filename)")!
    }

    /// Expected size in MB for display
    var expectedSizeMB: Int {
        Int(expectedSizeBytes / 1_000_000)
    }

    /// Expected size formatted for display (e.g., "1.1 GB" or "920 MB")
    var expectedSizeFormatted: String {
        let gb = Double(expectedSizeBytes) / 1_000_000_000
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            return "\(expectedSizeMB) MB"
        }
    }

    /// Why users should keep on-device models
    static let keepModelReasons = [
        "Enables fully offline AI features for learning modules",
        "No internet connection required for learning sessions",
        "Your data stays private and never leaves your device",
        "No API costs for on-device processing",
        "Faster response times compared to cloud services"
    ]

    /// What happens if all on-device models are deleted
    static let deletionConsequences = [
        "Learning modules will fall back to simpler validation methods",
        "Complex answers requiring judgment may not be validated correctly",
        "Some curriculum features may require an internet connection",
        "You can re-download models anytime from Settings"
    ]
}

// MARK: - Available Models

/// Available on-device LLM models
public enum OnDeviceLLMModel: String, CaseIterable, Sendable {
    case falconH1_1_5B = "falcon-h1-1.5b"
    case qwen35_2B = "qwen3.5-2b"
    case qwen3_1_7B = "qwen3-1.7b"
    case smolLM3_3B = "smollm3-3b"
    case ministral3_3B = "ministral-3-3b"

    /// The recommended default model for new installs
    public static var defaultModel: OnDeviceLLMModel { .falconH1_1_5B }

    /// UserDefaults key for persisted model selection
    static let selectedModelKey = "selectedOnDeviceLLMModel"

    /// Model configuration
    public var config: OnDeviceLLMModelConfig {
        switch self {
        case .falconH1_1_5B:
            return OnDeviceLLMModelConfig(
                id: "falcon-h1-1.5b-deep-instruct-q4_k_m",
                displayName: "Falcon-H1 1.5B Deep",
                huggingFaceRepo: "tiiuae/Falcon-H1-1.5B-Deep-Instruct-GGUF",
                filename: "Falcon-H1-1.5B-Deep-Instruct-Q4_K_M.gguf",
                expectedSizeBytes: 938_465_920, // ~938 MB
                quantization: "Q4_K_M",
                contextSize: 8192,
                minimumRAMGB: 3,
                description: "Hybrid Mamba-2 + Transformer. Under 1 GB but rivals 3B models: MMLU 66, GSM8K 82, HumanEval 74. Best efficiency/quality ratio.",
                chatFormat: .chatML,
                publisher: "TII (UAE)",
                license: "Apache 2.0",
                version: "May 2025"
            )
        case .qwen35_2B:
            return OnDeviceLLMModelConfig(
                id: "qwen3.5-2b-q4_k_m",
                displayName: "Qwen3.5 2B",
                huggingFaceRepo: "unsloth/Qwen3.5-2B-GGUF",
                filename: "Qwen3.5-2B-Q4_K_M.gguf",
                expectedSizeBytes: 1_280_000_000, // ~1.28 GB
                quantization: "Q4_K_M",
                contextSize: 32768,
                minimumRAMGB: 3,
                description: "Natively multimodal (text, images, video). 262K native context. Hybrid Gated DeltaNet + MoE architecture. Matches 7B quality from 2024.",
                chatFormat: .chatML,
                publisher: "Alibaba (Qwen)",
                license: "Apache 2.0",
                version: "March 2026"
            )
        case .qwen3_1_7B:
            return OnDeviceLLMModelConfig(
                id: "qwen3-1.7b-q4_k_m",
                displayName: "Qwen3 1.7B",
                huggingFaceRepo: "unsloth/Qwen3-1.7B-GGUF",
                filename: "Qwen3-1.7B-Q4_K_M.gguf",
                expectedSizeBytes: 1_110_000_000, // ~1.11 GB
                quantization: "Q4_K_M",
                contextSize: 32768,
                minimumRAMGB: 3,
                description: "Compact and fast. Matches Qwen2.5-3B quality at half the size. Ideal for long sessions with minimal thermal impact.",
                chatFormat: .chatML,
                publisher: "Alibaba (Qwen)",
                license: "Apache 2.0",
                version: "April 2025"
            )
        case .smolLM3_3B:
            return OnDeviceLLMModelConfig(
                id: "smollm3-3b-q4_k_m",
                displayName: "SmolLM3 3B",
                huggingFaceRepo: "ggml-org/SmolLM3-3B-GGUF",
                filename: "SmolLM3-Q4_K_M.gguf",
                expectedSizeBytes: 1_920_000_000, // ~1.92 GB
                quantization: "Q4_K_M",
                contextSize: 32768,
                minimumRAMGB: 4,
                description: "Best-in-class 3B model. Outperforms Llama 3.2 3B and Qwen2.5 3B across 12 benchmarks. Dual-mode reasoning.",
                chatFormat: .chatML,
                publisher: "Hugging Face",
                license: "Apache 2.0",
                version: "July 2025"
            )
        case .ministral3_3B:
            return OnDeviceLLMModelConfig(
                id: "ministral-3-3b-instruct-2512",
                displayName: "Ministral 3 3B",
                huggingFaceRepo: "mistralai/Ministral-3-3B-Instruct-2512-GGUF",
                filename: "Ministral-3-3B-Instruct-2512-Q4_K_M.gguf",
                expectedSizeBytes: 2_150_000_000, // ~2.15 GB
                quantization: "Q4_K_M",
                contextSize: 4096,
                minimumRAMGB: 4,
                description: "December 2025 release from Mistral AI. Solid instruction following and reasoning capabilities.",
                chatFormat: .mistral,
                publisher: "Mistral AI",
                license: "Apache 2.0",
                version: "December 2025"
            )
        }
    }

    /// Whether this is the recommended model
    public var isRecommended: Bool {
        self == Self.defaultModel
    }
}

// MARK: - Model Manager

/// Manages on-device LLM model files
///
/// Model files are stored in Documents/models/LLM/ and downloaded from Hugging Face CDN.
///
/// Features:
/// - Multiple model support with independent download/state tracking
/// - Download from Hugging Face with progress tracking
/// - Model selection persisted via UserDefaults
/// - Delete models to free storage
/// - Verify model integrity
///
/// This is a shared singleton to ensure consistent state across the app.
/// The settings UI and service both reference the same instance.
public actor OnDeviceLLMModelManager {
    /// Shared singleton instance
    public static let shared = OnDeviceLLMModelManager()

    private let logger = Logger(subsystem: "com.unamentis", category: "OnDeviceLLMModelManager")

    // MARK: - Model State

    /// Current state of a model
    public enum ModelState: Sendable, Equatable {
        case notDownloaded       // Model not present
        case downloading(Float)  // Download in progress with progress (0.0-1.0)
        case verifying           // Verifying downloaded file
        case available           // Model present, not loaded
        case loading(Float)      // Loading into memory
        case loaded              // Ready for inference
        case error(String)       // Error occurred

        public static func == (lhs: ModelState, rhs: ModelState) -> Bool {
            switch (lhs, rhs) {
            case (.notDownloaded, .notDownloaded),
                 (.verifying, .verifying),
                 (.available, .available),
                 (.loaded, .loaded):
                return true
            case let (.downloading(p1), .downloading(p2)),
                 let (.loading(p1), .loading(p2)):
                return abs(p1 - p2) < 0.01
            case let (.error(e1), .error(e2)):
                return e1 == e2
            default:
                return false
            }
        }

        public var isReady: Bool {
            self == .loaded
        }

        public var isAvailable: Bool {
            self == .available || self == .loaded
        }

        public var displayText: String {
            switch self {
            case .notDownloaded: return "Not Downloaded"
            case .downloading(let progress): return "Downloading \(Int(progress * 100))%"
            case .verifying: return "Verifying..."
            case .available: return "Ready to Load"
            case .loading(let progress): return "Loading \(Int(progress * 100))%"
            case .loaded: return "Loaded"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    /// Per-model state tracking
    private var modelStates: [OnDeviceLLMModel: ModelState] = [:]

    /// State for the currently selected model (backward compat)
    public var state: ModelState {
        modelStates[selectedModel] ?? .notDownloaded
    }

    /// Get state for a specific model
    public func state(for model: OnDeviceLLMModel) -> ModelState {
        modelStates[model] ?? .notDownloaded
    }

    /// Currently selected model
    public private(set) var selectedModel: OnDeviceLLMModel

    // MARK: - Download State (per-model)

    private var downloadTasks: [OnDeviceLLMModel: URLSessionDownloadTask] = [:]
    private var downloadContinuations: [OnDeviceLLMModel: CheckedContinuation<URL, Error>] = [:]
    private var progressObservations: [OnDeviceLLMModel: NSKeyValueObservation] = [:]

    // MARK: - Model Paths

    /// Base directory for LLM models
    private var modelDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("models/LLM", isDirectory: true)
    }

    /// Path to the currently selected model file
    public var modelPath: URL {
        modelPath(for: selectedModel)
    }

    /// Path to a specific model file
    public func modelPath(for model: OnDeviceLLMModel) -> URL {
        modelDirectory.appendingPathComponent(model.config.filename)
    }

    /// Path as string for llama.cpp
    public var modelPathString: String {
        modelPath.path
    }

    // MARK: - Initialization

    public init() {
        // Resolve selected model from UserDefaults with migration
        if let savedRaw = UserDefaults.standard.string(forKey: OnDeviceLLMModel.selectedModelKey),
           let saved = OnDeviceLLMModel(rawValue: savedRaw) {
            self.selectedModel = saved
        } else {
            // Migration: check if Ministral 3B file exists on disk (existing user)
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let ministralPath = documentsPath
                .appendingPathComponent("models/LLM")
                .appendingPathComponent(OnDeviceLLMModel.ministral3_3B.config.filename)

            if FileManager.default.fileExists(atPath: ministralPath.path) {
                self.selectedModel = .ministral3_3B
            } else {
                self.selectedModel = .defaultModel
            }
            UserDefaults.standard.set(self.selectedModel.rawValue, forKey: OnDeviceLLMModel.selectedModelKey)
        }

        Task {
            await checkAllModelAvailability()
        }
    }

    // MARK: - Model Selection

    /// Select a model as the active on-device LLM
    public func selectModel(_ model: OnDeviceLLMModel) {
        selectedModel = model
        UserDefaults.standard.set(model.rawValue, forKey: OnDeviceLLMModel.selectedModelKey)
        logger.info("Selected model: \(model.config.displayName)")
    }

    // MARK: - Public API

    /// Get current state of the selected model (refreshes from filesystem first)
    nonisolated public func currentState() async -> ModelState {
        await refreshStateFromFilesystem(for: await selectedModel)
        return await state
    }

    /// Get current state of a specific model (refreshes from filesystem first)
    nonisolated public func currentState(for model: OnDeviceLLMModel) async -> ModelState {
        await refreshStateFromFilesystem(for: model)
        return await state(for: model)
    }

    /// Get states for all models
    public func allModelStates() -> [OnDeviceLLMModel: ModelState] {
        var states: [OnDeviceLLMModel: ModelState] = [:]
        for model in OnDeviceLLMModel.allCases {
            states[model] = modelStates[model] ?? .notDownloaded
        }
        return states
    }

    /// Refresh state from filesystem to ensure it's accurate
    private func refreshStateFromFilesystem(for model: OnDeviceLLMModel) {
        let currentState = modelStates[model] ?? .notDownloaded

        // Only refresh if we're in a potentially stale state
        switch currentState {
        case .downloading, .verifying, .loading:
            // These are transient states managed by operations, don't override
            return
        case .notDownloaded, .available, .loaded, .error:
            // Check actual file presence
            if isModelAvailable(model) {
                if case .notDownloaded = currentState {
                    modelStates[model] = .available
                }
                // Keep .loaded state if we were loaded
            } else {
                modelStates[model] = .notDownloaded
            }
        }
    }

    /// Check if a specific model is available locally
    public func isModelAvailable(_ model: OnDeviceLLMModel? = nil) -> Bool {
        let target = model ?? selectedModel
        return FileManager.default.fileExists(atPath: modelPath(for: target).path)
    }

    /// Check if any on-device model is available locally
    public func isAnyModelAvailable() -> Bool {
        OnDeviceLLMModel.allCases.contains { isModelAvailable($0) }
    }

    /// Get model file size in bytes (0 if not downloaded)
    public func modelSizeBytes(for model: OnDeviceLLMModel? = nil) -> Int64 {
        let target = model ?? selectedModel
        guard isModelAvailable(target) else { return 0 }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: modelPath(for: target).path)
            return attrs[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    /// Get model file size in MB for display
    public func modelSizeMB(for model: OnDeviceLLMModel? = nil) -> Int {
        Int(modelSizeBytes(for: model) / 1_000_000)
    }

    /// Total storage used by all downloaded models in bytes
    public func totalStorageUsed() -> Int64 {
        OnDeviceLLMModel.allCases.reduce(0) { $0 + modelSizeBytes(for: $1) }
    }

    /// Number of downloaded models
    public func downloadedModelCount() -> Int {
        OnDeviceLLMModel.allCases.filter { isModelAvailable($0) }.count
    }

    /// Ensure selected model is available (download if needed)
    public func ensureModelAvailable() async throws {
        if isModelAvailable() {
            modelStates[selectedModel] = .available
            return
        }

        try await downloadModel()
    }

    /// Download a model from Hugging Face
    public func downloadModel(for model: OnDeviceLLMModel? = nil) async throws {
        let target = model ?? selectedModel

        guard !isModelAvailable(target) else {
            modelStates[target] = .available
            return
        }

        let config = target.config
        logger.info("Starting download of \(config.displayName) from Hugging Face")

        modelStates[target] = .downloading(0.0)

        // Create model directory if needed
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        // Create URLSession configuration
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 3600 // 1 hour for large file
        let session = URLSession(configuration: sessionConfig)

        // Download file
        let tempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.downloadContinuations[target] = continuation

            let task = session.downloadTask(with: config.downloadURL) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    continuation.resume(throwing: OnDeviceLLMModelError.downloadFailed("Invalid response"))
                    return
                }

                guard let tempURL = tempURL else {
                    continuation.resume(throwing: OnDeviceLLMModelError.downloadFailed("No file returned"))
                    return
                }

                continuation.resume(returning: tempURL)
            }

            self.downloadTasks[target] = task

            // Observe progress
            self.progressObservations[target] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { [weak self] in
                    await self?.updateDownloadProgress(Float(progress.fractionCompleted), for: target)
                }
            }

            task.resume()
        }

        // Clean up observation
        progressObservations[target]?.invalidate()
        progressObservations[target] = nil
        downloadTasks[target] = nil
        downloadContinuations[target] = nil

        // Verify and move file
        modelStates[target] = .verifying
        logger.info("Download complete, verifying file...")

        let targetPath = modelPath(for: target)
        do {
            // Move to final location
            if FileManager.default.fileExists(atPath: targetPath.path) {
                try FileManager.default.removeItem(at: targetPath)
            }
            try FileManager.default.moveItem(at: tempURL, to: targetPath)

            // Verify size
            let actualSize = modelSizeBytes(for: target)
            let expectedSize = config.expectedSizeBytes
            let tolerance: Int64 = 100_000_000 // 100MB tolerance for compression variations

            if abs(actualSize - expectedSize) > tolerance {
                logger.warning("Model size mismatch: expected \(expectedSize), got \(actualSize)")
            }

            modelStates[target] = .available
            logger.info("Model \(config.displayName) downloaded successfully (\(self.modelSizeMB(for: target)) MB)")

        } catch {
            modelStates[target] = .error("Failed to save model: \(error.localizedDescription)")
            throw OnDeviceLLMModelError.downloadFailed(error.localizedDescription)
        }
    }

    /// Cancel ongoing download for a model
    public func cancelDownload(for model: OnDeviceLLMModel? = nil) {
        let target = model ?? selectedModel

        downloadTasks[target]?.cancel()
        downloadTasks[target] = nil
        progressObservations[target]?.invalidate()
        progressObservations[target] = nil

        if let continuation = downloadContinuations[target] {
            continuation.resume(throwing: CancellationError())
            downloadContinuations[target] = nil
        }

        modelStates[target] = .notDownloaded
        logger.info("Download cancelled for \(target.config.displayName)")
    }

    /// Delete a model to free storage
    public func deleteModel(for model: OnDeviceLLMModel? = nil) async throws {
        let target = model ?? selectedModel

        guard isModelAvailable(target) else {
            return
        }

        let path = modelPath(for: target)
        logger.info("Deleting model at \(path.path)")

        do {
            try FileManager.default.removeItem(at: path)
            modelStates[target] = .notDownloaded
            logger.info("Model \(target.config.displayName) deleted successfully")
        } catch {
            logger.error("Failed to delete model: \(error.localizedDescription)")
            throw OnDeviceLLMModelError.deleteFailed(error.localizedDescription)
        }
    }

    /// Mark selected model as loaded (called by OnDeviceLLMService after successful load)
    public func markLoaded() {
        modelStates[selectedModel] = .loaded
    }

    /// Mark selected model as available (called when unloading)
    public func markUnloaded() {
        if isModelAvailable() {
            modelStates[selectedModel] = .available
        } else {
            modelStates[selectedModel] = .notDownloaded
        }
    }

    // MARK: - Private Helpers

    private func checkAllModelAvailability() {
        for model in OnDeviceLLMModel.allCases {
            let path = modelPath(for: model)
            if FileManager.default.fileExists(atPath: path.path) {
                modelStates[model] = .available
                logger.info("Model found: \(model.config.displayName) at \(path.path)")
            } else {
                modelStates[model] = .notDownloaded
            }
        }
    }

    private func updateDownloadProgress(_ progress: Float, for model: OnDeviceLLMModel) {
        modelStates[model] = .downloading(progress)
    }
}

// MARK: - Model Error

/// Errors for on-device LLM model operations
public enum OnDeviceLLMModelError: Error, LocalizedError {
    case modelNotDownloaded
    case downloadFailed(String)
    case deleteFailed(String)
    case insufficientStorage
    case insufficientRAM
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "The on-device LLM model is not downloaded. Download it in Settings to enable this feature."
        case .downloadFailed(let reason):
            return "Failed to download model: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete model: \(reason)"
        case .insufficientStorage:
            return "Not enough storage space for this model."
        case .insufficientRAM:
            return "This device does not have enough RAM to run the selected on-device LLM."
        case .networkUnavailable:
            return "Network connection is required to download the model."
        }
    }
}

// MARK: - State Observer

/// Observable wrapper for model state (for SwiftUI)
@MainActor
public final class OnDeviceLLMModelStateObserver: ObservableObject {
    @Published public var state: OnDeviceLLMModelManager.ModelState = .notDownloaded
    @Published public var downloadProgress: Float = 0.0
    @Published public var allStates: [OnDeviceLLMModel: OnDeviceLLMModelManager.ModelState] = [:]

    private let manager: OnDeviceLLMModelManager

    public init(manager: OnDeviceLLMModelManager) {
        self.manager = manager
        Task {
            await refreshState()
        }
    }

    public func refreshState() async {
        state = await manager.currentState()
        allStates = await manager.allModelStates()
        if case .downloading(let progress) = state {
            downloadProgress = progress
        }
    }

    public func downloadModel(for model: OnDeviceLLMModel? = nil) async throws {
        try await manager.downloadModel(for: model)
        await refreshState()
    }

    public func cancelDownload(for model: OnDeviceLLMModel? = nil) async {
        await manager.cancelDownload(for: model)
        await refreshState()
    }

    public func deleteModel(for model: OnDeviceLLMModel? = nil) async throws {
        try await manager.deleteModel(for: model)
        await refreshState()
    }

    public func selectModel(_ model: OnDeviceLLMModel) async {
        await manager.selectModel(model)
        await refreshState()
    }

    public var isModelAvailable: Bool {
        get async { await manager.isModelAvailable() }
    }

    public var modelSizeMB: Int {
        get async { await manager.modelSizeMB() }
    }

    public var modelPath: String {
        get async { await manager.modelPathString }
    }
}

// MARK: - Preview Support

#if DEBUG
extension OnDeviceLLMModelManager {
    public static func preview() -> OnDeviceLLMModelManager {
        OnDeviceLLMModelManager()
    }
}
#endif
