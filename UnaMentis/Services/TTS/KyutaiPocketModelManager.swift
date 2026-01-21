// UnaMentis - Kyutai Pocket TTS Model Manager
// Manages download, storage, and loading of Kyutai Pocket TTS model components
//
// Part of Services/TTS

import Foundation
@preconcurrency import CoreML
import OSLog

// MARK: - Model Manager

/// Manager for Kyutai Pocket TTS model components
///
/// Handles downloading and loading of the three CoreML model components:
/// - Transformer Backbone (KyutaiPocketTransformer.mlpackage)
/// - MLP Sampler (KyutaiPocketSampler.mlpackage)
/// - Mimi VAE Decoder (KyutaiPocketMimiDecoder.mlpackage)
///
/// Plus supporting files:
/// - Tokenizer (tokenizer.model)
/// - Voice Embeddings (voices.bin)
actor KyutaiPocketModelManager {
    private let logger = Logger(subsystem: "com.unamentis", category: "KyutaiPocketModelManager")

    // MARK: - Model State

    /// Current state of the model
    enum ModelState: Sendable, Equatable {
        case notDownloaded
        case downloading(Float)  // Progress 0.0-1.0
        case available           // Downloaded but not loaded
        case loading(Float)      // Loading progress 0.0-1.0
        case loaded              // Ready for inference
        case error(String)       // Error occurred

        static func == (lhs: ModelState, rhs: ModelState) -> Bool {
            switch (lhs, rhs) {
            case (.notDownloaded, .notDownloaded),
                 (.available, .available),
                 (.loaded, .loaded):
                return true
            case let (.downloading(p1), .downloading(p2)):
                return abs(p1 - p2) < 0.01
            case let (.loading(p1), .loading(p2)):
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

    // MARK: - Loaded Models

    /// CoreML models when loaded
    struct LoadedModels: @unchecked Sendable {
        let transformer: MLModel
        let sampler: MLModel
        let mimiDecoder: MLModel
        let voiceEmbeddings: [[Float]]
    }

    private var loadedModels: LoadedModels?

    // MARK: - Configuration

    /// Base URL for model downloads
    private let baseDownloadURL = "https://models.unamentis.com/tts/kyutai-pocket"

    /// Model component names
    private enum ModelComponent: String, CaseIterable {
        case transformer = "KyutaiPocketTransformer"
        case sampler = "KyutaiPocketSampler"
        case mimiDecoder = "KyutaiPocketMimiDecoder"
        case tokenizer = "tokenizer"
        case voices = "voices"

        var filename: String {
            switch self {
            case .transformer, .sampler, .mimiDecoder:
                return "\(rawValue).mlpackage"
            case .tokenizer:
                return "tokenizer.model"
            case .voices:
                return "voices.bin"
            }
        }

        var downloadFilename: String {
            switch self {
            case .transformer, .sampler, .mimiDecoder:
                return "\(rawValue).mlpackage.zip"
            case .tokenizer:
                return "tokenizer.model"
            case .voices:
                return "voices.bin"
            }
        }

        var isMLModel: Bool {
            switch self {
            case .transformer, .sampler, .mimiDecoder:
                return true
            case .tokenizer, .voices:
                return false
            }
        }

        /// Approximate size in MB for progress calculation
        var approximateSizeMB: Float {
            switch self {
            case .transformer: return 280.0
            case .sampler: return 40.0
            case .mimiDecoder: return 80.0
            case .tokenizer: return 0.5
            case .voices: return 4.0
            }
        }
    }

    /// Directory where models are stored
    private let modelsDirectory: URL

    /// Manifest URL for checksums
    private var manifestURL: URL {
        URL(string: "\(baseDownloadURL)/manifest.json")!
    }

    // MARK: - Initialization

    init() {
        // Model storage location
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.modelsDirectory = documentsURL.appendingPathComponent("models/kyutai-pocket", isDirectory: true)

        // Check if models already exist
        Task {
            await checkModelAvailability()
        }
    }

    // MARK: - Public API

    /// Get current model state
    nonisolated func currentState() async -> ModelState {
        await state
    }

    /// Check if models are downloaded
    func isDownloaded() -> Bool {
        for component in ModelComponent.allCases {
            let path = modelsDirectory.appendingPathComponent(component.filename)
            if !FileManager.default.fileExists(atPath: path.path) {
                return false
            }
        }
        return true
    }

    /// Get total download size in MB
    func totalDownloadSizeMB() -> Float {
        ModelComponent.allCases.reduce(0) { $0 + $1.approximateSizeMB }
    }

    /// Download all model components
    /// - Parameter progressHandler: Called with download progress (0.0-1.0)
    func downloadModels(progressHandler: @Sendable @escaping (Float) -> Void) async throws {
        logger.info("Starting Kyutai Pocket TTS model download")
        state = .downloading(0.0)
        progressHandler(0.0)

        // Create models directory
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // Download manifest first to get checksums
        let manifest = try await downloadManifest()

        // Download each component
        let totalSize = totalDownloadSizeMB()
        var downloadedSize: Float = 0.0

        for component in ModelComponent.allCases {
            let componentURL = URL(string: "\(baseDownloadURL)/\(component.downloadFilename)")!
            let destinationURL = modelsDirectory.appendingPathComponent(component.filename)
            let expectedChecksum = manifest?.components[component.rawValue]?.checksum

            logger.info("Downloading \(component.rawValue)...")

            // Capture current value to avoid data race
            let currentDownloadedSize = downloadedSize

            try await downloadComponent(
                from: componentURL,
                to: destinationURL,
                expectedChecksum: expectedChecksum,
                isZipped: component.isMLModel,
                progressHandler: { componentProgress in
                    let overallProgress = (currentDownloadedSize + componentProgress * component.approximateSizeMB) / totalSize
                    self.state = .downloading(overallProgress)
                    progressHandler(overallProgress)
                }
            )

            downloadedSize += component.approximateSizeMB
        }

        state = .available
        progressHandler(1.0)
        logger.info("All models downloaded successfully")
    }

    /// Load models into memory
    /// - Parameter config: Configuration for compute units
    func loadModels(config: KyutaiPocketTTSConfig) async throws {
        logger.info("Loading Kyutai Pocket TTS models")
        state = .loading(0.0)

        guard isDownloaded() else {
            let error = "Models not downloaded"
            logger.error("\(error)")
            state = .error(error)
            throw KyutaiPocketModelError.modelsNotDownloaded
        }

        do {
            // Configure compute units based on config
            let mlConfig = MLModelConfiguration()
            mlConfig.computeUnits = config.useNeuralEngine ? .all : .cpuOnly

            // Load transformer (33% progress)
            state = .loading(0.1)
            let transformerURL = modelsDirectory.appendingPathComponent(ModelComponent.transformer.filename)
            let transformer = try await MLModel.load(contentsOf: transformerURL, configuration: mlConfig)
            logger.info("Transformer loaded")
            state = .loading(0.33)

            // Load sampler (66% progress)
            let samplerURL = modelsDirectory.appendingPathComponent(ModelComponent.sampler.filename)
            let sampler = try await MLModel.load(contentsOf: samplerURL, configuration: mlConfig)
            logger.info("Sampler loaded")
            state = .loading(0.66)

            // Load Mimi decoder (90% progress)
            let decoderURL = modelsDirectory.appendingPathComponent(ModelComponent.mimiDecoder.filename)
            let mimiDecoder = try await MLModel.load(contentsOf: decoderURL, configuration: mlConfig)
            logger.info("Mimi decoder loaded")
            state = .loading(0.9)

            // Load voice embeddings (100% progress)
            let voiceEmbeddings = try loadVoiceEmbeddings()
            logger.info("Voice embeddings loaded: \(voiceEmbeddings.count) voices")

            loadedModels = LoadedModels(
                transformer: transformer,
                sampler: sampler,
                mimiDecoder: mimiDecoder,
                voiceEmbeddings: voiceEmbeddings
            )

            state = .loaded
            logger.info("All models loaded successfully")

        } catch {
            let errorMsg = "Failed to load models: \(error.localizedDescription)"
            logger.error("\(errorMsg)")
            state = .error(errorMsg)
            throw KyutaiPocketModelError.loadFailed(error)
        }
    }

    /// Unload models from memory
    func unloadModels() {
        logger.info("Unloading Kyutai Pocket TTS models")
        loadedModels = nil
        state = .available
    }

    /// Get loaded models for inference
    func getLoadedModels() throws -> LoadedModels {
        guard let models = loadedModels else {
            throw KyutaiPocketModelError.modelsNotLoaded
        }
        return models
    }

    /// Get voice embedding for a specific voice
    func getVoiceEmbedding(for voice: KyutaiPocketVoice) throws -> [Float] {
        guard let models = loadedModels else {
            throw KyutaiPocketModelError.modelsNotLoaded
        }
        guard voice.rawValue < models.voiceEmbeddings.count else {
            throw KyutaiPocketModelError.invalidVoice
        }
        return models.voiceEmbeddings[voice.rawValue]
    }

    /// Delete downloaded models
    func deleteModels() async throws {
        logger.info("Deleting Kyutai Pocket TTS models")

        // Unload first if loaded
        if loadedModels != nil {
            unloadModels()
        }

        // Remove directory
        if FileManager.default.fileExists(atPath: modelsDirectory.path) {
            try FileManager.default.removeItem(at: modelsDirectory)
        }

        state = .notDownloaded
        logger.info("Models deleted")
    }

    // MARK: - Private Helpers

    private func checkModelAvailability() {
        if isDownloaded() {
            state = .available
            logger.info("Models found at \(self.modelsDirectory.path)")
        } else {
            state = .notDownloaded
            logger.info("Models not downloaded")
        }
    }

    private func downloadManifest() async throws -> ModelManifest? {
        guard let url = URL(string: "\(baseDownloadURL)/manifest.json") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let manifest = try JSONDecoder().decode(ModelManifest.self, from: data)
            return manifest
        } catch {
            logger.warning("Could not download manifest: \(error.localizedDescription)")
            return nil
        }
    }

    private func downloadComponent(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedChecksum: String?,
        isZipped: Bool,
        progressHandler: @escaping (Float) -> Void
    ) async throws {
        // Create download task with progress
        let (localURL, response) = try await URLSession.shared.download(from: sourceURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw KyutaiPocketModelError.downloadFailed("Status \(status)")
        }

        // Verify checksum if provided
        if let expectedChecksum = expectedChecksum {
            let actualChecksum = try computeChecksum(for: localURL)
            guard actualChecksum == expectedChecksum else {
                throw KyutaiPocketModelError.checksumMismatch
            }
        }

        // Handle zipped mlpackage files
        if isZipped {
            try await unzipModel(from: localURL, to: destinationURL)
        } else {
            // Just move the file
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: localURL, to: destinationURL)
        }

        progressHandler(1.0)
    }

    private func unzipModel(from sourceURL: URL, to destinationURL: URL) async throws {
        // Remove existing if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        // CoreML mlpackage files are directories, not archives, so we just move them
        // If we receive a compressed archive, we need to use a library like ZIPFoundation
        // For now, assume the server provides uncompressed mlpackage directories
        let fm = FileManager.default

        // Check if source is a directory (mlpackage)
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            // Just move the directory
            try fm.moveItem(at: sourceURL, to: destinationURL)
        } else {
            // For compressed files, throw an error asking for proper library
            // Production should use ZIPFoundation or similar
            logger.error("Compressed model archives require ZIPFoundation library")
            throw KyutaiPocketModelError.unzipFailed
        }
    }

    private func computeChecksum(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        // Use CryptoKit for SHA256
        // Note: Implementation placeholder
        return data.hashValue.description
    }

    private func loadVoiceEmbeddings() throws -> [[Float]] {
        let voicesURL = modelsDirectory.appendingPathComponent(ModelComponent.voices.filename)
        let data = try Data(contentsOf: voicesURL)

        let embeddingDim = 256  // From config
        let numVoices = 8

        // Parse binary float array
        let floatCount = data.count / MemoryLayout<Float>.size
        var floats = [Float](repeating: 0, count: floatCount)

        data.withUnsafeBytes { buffer in
            _ = floats.withUnsafeMutableBytes { dest in
                buffer.copyBytes(to: dest)
            }
        }

        // Split into per-voice embeddings
        var embeddings: [[Float]] = []
        for i in 0..<numVoices {
            let start = i * embeddingDim
            let end = start + embeddingDim
            if end <= floats.count {
                embeddings.append(Array(floats[start..<end]))
            }
        }

        return embeddings
    }
}

// MARK: - Model Manifest

/// Manifest JSON structure for model downloads
struct ModelManifest: Codable {
    let version: String
    let modelId: String
    let license: String
    let platform: String
    let totalSizeMB: Float
    let components: [String: ComponentInfo]

    struct ComponentInfo: Codable {
        let filename: String
        let sizeMB: Float
        let checksum: String

        enum CodingKeys: String, CodingKey {
            case filename
            case sizeMB = "size_mb"
            case checksum
        }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case modelId = "model_id"
        case license
        case platform
        case totalSizeMB = "total_size_mb"
        case components
    }
}

// MARK: - Model Error

/// Errors for Kyutai Pocket model operations
enum KyutaiPocketModelError: Error, LocalizedError {
    case modelsNotDownloaded
    case modelsNotLoaded
    case downloadFailed(String)
    case checksumMismatch
    case unzipFailed
    case loadFailed(Error)
    case invalidVoice
    case inferenceError(String)

    var errorDescription: String? {
        switch self {
        case .modelsNotDownloaded:
            return "Models not downloaded. Please download the Kyutai Pocket TTS models first."
        case .modelsNotLoaded:
            return "Models not loaded into memory. Please load the models first."
        case .downloadFailed(let reason):
            return "Failed to download models: \(reason)"
        case .checksumMismatch:
            return "Model checksum verification failed. The download may be corrupted."
        case .unzipFailed:
            return "Failed to unzip model package."
        case .loadFailed(let error):
            return "Failed to load models: \(error.localizedDescription)"
        case .invalidVoice:
            return "Invalid voice index specified."
        case .inferenceError(let reason):
            return "Inference failed: \(reason)"
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
