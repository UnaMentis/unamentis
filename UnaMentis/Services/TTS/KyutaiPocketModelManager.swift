// UnaMentis - Kyutai Pocket TTS Model Manager
// Manages Kyutai Pocket TTS model files for Rust/Candle inference
//
// Part of Services/TTS

import Foundation
import OSLog

// MARK: - Model Manager

/// Manager for Kyutai Pocket TTS model files
///
/// Model files (~230MB total) are stored in Documents/models/kyutai-pocket-ios/
/// and loaded by the Rust/Candle inference engine.
///
/// Directory structure expected by Rust engine:
/// - model.safetensors - Main transformer weights (225MB)
/// - tokenizer.json - Vocabulary for tokenization (JSON format)
/// - voices/ - Voice embedding directory
///   - alba.safetensors, marius.safetensors, etc. (8 voices)
actor KyutaiPocketModelManager {
    private let logger = Logger(subsystem: "com.unamentis", category: "KyutaiPocketModelManager")

    // MARK: - Model State

    /// Current state of the model
    enum ModelState: Sendable, Equatable {
        case notDownloaded      // Models not present
        case downloading(Float) // Download in progress
        case available          // Models present, not loaded
        case loading(Float)     // Loading into Rust engine
        case loaded             // Ready for inference
        case error(String)      // Error occurred

        static func == (lhs: ModelState, rhs: ModelState) -> Bool {
            switch (lhs, rhs) {
            case (.notDownloaded, .notDownloaded),
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

        var isReady: Bool {
            self == .loaded
        }

        var displayText: String {
            switch self {
            case .notDownloaded: return "Not Downloaded"
            case .downloading(let progress): return "Downloading \(Int(progress * 100))%"
            case .available: return "Ready to Load"
            case .loading(let progress): return "Loading \(Int(progress * 100))%"
            case .loaded: return "Loaded"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    private(set) var state: ModelState = .notDownloaded

    // MARK: - Model Paths

    /// Base directory for Kyutai Pocket TTS models
    private var modelDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("models/kyutai-pocket-ios", isDirectory: true)
    }

    /// Path to main model weights
    private var modelPath: URL {
        modelDirectory.appendingPathComponent("model.safetensors")
    }

    /// Path to tokenizer (JSON vocab)
    private var tokenizerPath: URL {
        modelDirectory.appendingPathComponent("tokenizer.json")
    }

    /// Path to voices directory
    private var voicesDirectory: URL {
        modelDirectory.appendingPathComponent("voices", isDirectory: true)
    }

    // MARK: - Initialization

    init() {
        Task {
            await checkModelAvailability()
            // Proactively copy models from bundle if needed
            try? await ensureModelsAvailable()
            await checkModelAvailability()  // Refresh state after copy
        }
    }

    // MARK: - Public API

    /// Get current model state
    nonisolated func currentState() async -> ModelState {
        await state
    }

    /// Get model directory path for Rust engine
    func getModelPath() async throws -> String {
        // Ensure models are available (copies from bundle if needed)
        try await ensureModelsAvailable()

        guard await isModelAvailable() else {
            throw KyutaiPocketModelError.modelsNotDownloaded
        }
        return modelDirectory.path
    }

    /// Check if models are available locally
    func isModelAvailable() async -> Bool {
        let fm = FileManager.default

        // Check required files exist
        let modelExists = fm.fileExists(atPath: modelPath.path)
        let tokenizerExists = fm.fileExists(atPath: tokenizerPath.path)
        let voicesExist = fm.fileExists(atPath: voicesDirectory.path)

        return modelExists && tokenizerExists && voicesExist
    }

    /// Legacy compatibility
    func isDownloaded() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: modelPath.path)
    }

    /// Get total model size in MB
    func totalSizeMB() -> Float {
        229.3  // From manifest
    }

    /// Load model configuration (validates files exist)
    func loadModels(config: KyutaiPocketTTSConfig) async throws {
        logger.info("Validating Kyutai Pocket TTS model files for Rust/Candle")
        state = .loading(0.0)

        guard await isModelAvailable() else {
            state = .error("Model files not found")
            throw KyutaiPocketModelError.modelsNotDownloaded
        }

        state = .loading(0.5)

        // Log file paths for debugging
        logger.info("Model directory: \(self.modelDirectory.path)")
        logger.info("Model weights: \(self.modelPath.path)")
        logger.info("Tokenizer: \(self.tokenizerPath.path)")
        logger.info("Voices: \(self.voicesDirectory.path)")

        state = .loaded
        logger.info("Model files validated, ready for Rust/Candle inference")
    }

    /// Mark model as loaded (called by TTS service after successful engine init)
    func markLoaded() {
        state = .loaded
    }

    /// Unload models (reset state)
    func unloadModels() {
        logger.info("Resetting Kyutai Pocket TTS state")
        state = .available
    }

    /// Get available voice names
    func getAvailableVoices() -> [String] {
        KyutaiPocketVoice.allCases.map { $0.displayName }
    }

    // MARK: - Model Download

    /// Copy models from bundle or download from server
    func ensureModelsAvailable() async throws {
        if await isModelAvailable() {
            state = .available
            return
        }

        // First, try to copy from app bundle
        if await copyModelsFromBundle() {
            state = .available
            return
        }

        // Otherwise, download from server
        try await downloadModels()
    }

    /// Copy models from app bundle if available
    private func copyModelsFromBundle() async -> Bool {
        let fm = FileManager.default

        // Check if models are bundled (in app bundle root)
        guard let bundleURL = Bundle.main.resourceURL else {
            logger.error("Could not get bundle resource URL")
            return false
        }

        let bundleModelDir = bundleURL.appendingPathComponent("kyutai-pocket-ios")
        guard fm.fileExists(atPath: bundleModelDir.path) else {
            logger.info("Models not found in app bundle at: \(bundleModelDir.path)")
            return false
        }

        logger.info("Found bundled models at: \(bundleModelDir.path)")

        do {
            // Create destination directory
            try fm.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

            // Copy model files (only if they don't already exist)
            let bundleModel = bundleModelDir.appendingPathComponent("model.safetensors")
            let bundleTokenizer = bundleModelDir.appendingPathComponent("tokenizer.json")
            let bundleVoices = bundleModelDir.appendingPathComponent("voices")

            // Copy files if they don't already exist
            let modelExists = fm.fileExists(atPath: modelPath.path)
            let tokenizerExists = fm.fileExists(atPath: tokenizerPath.path)
            let voicesExist = fm.fileExists(atPath: voicesDirectory.path)

            if !modelExists && fm.fileExists(atPath: bundleModel.path) {
                try fm.copyItem(at: bundleModel, to: modelPath)
                logger.info("Copied model.safetensors")
            }
            if !tokenizerExists && fm.fileExists(atPath: bundleTokenizer.path) {
                try fm.copyItem(at: bundleTokenizer, to: tokenizerPath)
                logger.info("Copied tokenizer.json")
            }
            if !voicesExist && fm.fileExists(atPath: bundleVoices.path) {
                try fm.copyItem(at: bundleVoices, to: voicesDirectory)
                logger.info("Copied voices directory")
            }

            logger.info("Models ready in Documents directory")
            return await isModelAvailable()

        } catch {
            logger.error("Failed to copy models from bundle: \(error.localizedDescription)")
            return false
        }
    }

    /// Download models from server
    private func downloadModels() async throws {
        state = .downloading(0.0)
        logger.info("Downloading Kyutai Pocket TTS models...")

        // TODO: Implement actual download from models.unamentis.com
        // For now, throw error indicating models need to be copied manually

        throw KyutaiPocketModelError.modelsNotDownloaded
    }

    // MARK: - Private Helpers

    private func checkModelAvailability() async {
        if await isModelAvailable() {
            state = .available
            logger.info("Model files found at: \(self.modelDirectory.path)")
        } else {
            state = .notDownloaded
            logger.info("Model files not found, need to be installed")
        }
    }
}

// MARK: - Model Error

/// Errors for Kyutai Pocket model operations
enum KyutaiPocketModelError: Error, LocalizedError {
    case modelsNotDownloaded
    case modelsNotLoaded
    case serverUnavailable
    case networkError(Error)
    case invalidVoice
    case inferenceError(String)

    var errorDescription: String? {
        switch self {
        case .modelsNotDownloaded:
            return "Kyutai Pocket TTS models are not installed. Please copy models to Documents/models/kyutai-pocket-ios/"
        case .modelsNotLoaded:
            return "Kyutai Pocket TTS engine is not loaded."
        case .serverUnavailable:
            return "Model download server is not available."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidVoice:
            return "Invalid voice specified."
        case .inferenceError(let reason):
            return "Speech synthesis failed: \(reason)"
        }
    }
}

// MARK: - Model State Publisher

/// Observable wrapper for model state
@MainActor
final class KyutaiPocketModelStateObserver: ObservableObject {
    @Published var state: KyutaiPocketModelManager.ModelState = .notDownloaded

    private let manager: KyutaiPocketModelManager

    init(manager: KyutaiPocketModelManager) {
        self.manager = manager
        Task {
            await refreshState()
        }
    }

    func refreshState() async {
        state = await manager.currentState()
    }
}

// MARK: - Preview Support

#if DEBUG
extension KyutaiPocketModelManager {
    static func preview() -> KyutaiPocketModelManager {
        KyutaiPocketModelManager()
    }
}
#endif
