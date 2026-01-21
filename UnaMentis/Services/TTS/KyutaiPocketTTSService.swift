// UnaMentis - Kyutai Pocket TTS Service
// On-device Text-to-Speech service using Kyutai Pocket TTS
//
// Part of Services/TTS

import AVFoundation
@preconcurrency import CoreML
import Foundation
import OSLog

// MARK: - Kyutai Pocket TTS Service

/// On-device TTS service using Kyutai Pocket TTS
///
/// Kyutai Pocket TTS is a 100M parameter on-device model featuring:
/// - 8 built-in voices (Les Misérables characters)
/// - 5-second voice cloning capability
/// - 24kHz high-quality audio output
/// - ~200ms time to first audio
/// - 1.84% WER (best in class for on-device)
/// - MIT licensed
///
/// Architecture:
/// - Transformer Backbone: Text encoding and audio token generation
/// - MLP Sampler: Consistency sampling for high-quality tokens
/// - Mimi VAE Decoder: Audio tokens to waveform conversion
public actor KyutaiPocketTTSService: TTSService {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.unamentis", category: "KyutaiPocketTTS")

    /// Model manager for download/load operations
    private let modelManager: KyutaiPocketModelManager

    /// Current configuration
    private var config: KyutaiPocketTTSConfig

    /// Performance metrics
    public private(set) var metrics: TTSMetrics = TTSMetrics(
        medianTTFB: 0.2,   // ~200ms typical
        p99TTFB: 0.35
    )

    /// Cost per character (free for on-device)
    public var costPerCharacter: Decimal { 0 }

    /// Current voice configuration
    public private(set) var voiceConfig: TTSVoiceConfig

    /// Latency tracking
    private var latencyValues: [TimeInterval] = []

    /// Tokenizer for text processing
    private var tokenizer: KyutaiPocketTokenizer?

    /// Voice embedding cache
    private var currentVoiceEmbedding: MLMultiArray?

    // MARK: - Initialization

    /// Initialize with configuration
    /// - Parameters:
    ///   - config: Kyutai Pocket TTS configuration
    ///   - modelManager: Model manager instance (shared)
    init(
        config: KyutaiPocketTTSConfig = .default,
        modelManager: KyutaiPocketModelManager? = nil
    ) {
        self.config = config
        self.modelManager = modelManager ?? KyutaiPocketModelManager()
        self.voiceConfig = TTSVoiceConfig(
            voiceId: KyutaiPocketVoice(rawValue: config.voiceIndex)?.displayName ?? "Alba",
            rate: config.speed
        )
        logger.info("KyutaiPocketTTSService initialized")
    }

    // MARK: - TTSService Protocol

    /// Configure voice settings
    public func configure(_ config: TTSVoiceConfig) async {
        self.voiceConfig = config
        // Map voice ID to index if possible
        if let voice = KyutaiPocketVoice.allCases.first(where: {
            $0.displayName.lowercased() == config.voiceId.lowercased()
        }) {
            self.config.voiceIndex = voice.rawValue
        }
        logger.debug("Voice configured: \(config.voiceId)")
    }

    /// Configure Kyutai Pocket specific settings
    public func configurePocket(_ config: KyutaiPocketTTSConfig) async {
        self.config = config
        // Update voice config to match
        if let voice = KyutaiPocketVoice(rawValue: config.voiceIndex) {
            self.voiceConfig = TTSVoiceConfig(
                voiceId: voice.displayName,
                rate: config.speed
            )
        }
        // Clear cached voice embedding
        currentVoiceEmbedding = nil
        logger.debug("Kyutai Pocket configured: voice=\(config.voiceIndex), temp=\(config.temperature)")
    }

    /// Synthesize text to audio stream
    public func synthesize(text: String) async throws -> AsyncStream<TTSAudioChunk> {
        logger.info("[KyutaiPocket] synthesize called - text length: \(text.count)")

        // Ensure models are loaded
        let modelState = await modelManager.currentState()
        guard modelState == .loaded else {
            logger.error("[KyutaiPocket] Models not loaded, state: \(modelState.displayText)")
            throw KyutaiPocketModelError.modelsNotLoaded
        }

        let startTime = Date()

        return AsyncStream { continuation in
            Task {
                do {
                    // Perform synthesis
                    let audioData = try await self.performSynthesis(text: text, startTime: startTime)

                    let ttfb = Date().timeIntervalSince(startTime)
                    self.latencyValues.append(ttfb)
                    self.updateMetrics()
                    self.logger.info("[KyutaiPocket] TTFB: \(String(format: "%.3f", ttfb))s")

                    // Emit chunks for streaming compatibility
                    let chunkSize = 4800  // ~100ms at 24kHz 16-bit mono
                    var offset = 0
                    var sequenceNumber = 0

                    while offset < audioData.count {
                        let remaining = audioData.count - offset
                        let currentChunkSize = min(chunkSize, remaining)
                        let chunkData = audioData.subdata(in: offset..<offset + currentChunkSize)

                        let isFirst = sequenceNumber == 0
                        let isLast = offset + currentChunkSize >= audioData.count

                        let chunk = TTSAudioChunk(
                            audioData: chunkData,
                            format: .pcmFloat32(sampleRate: 24000, channels: 1),
                            sequenceNumber: sequenceNumber,
                            isFirst: isFirst,
                            isLast: isLast,
                            timeToFirstByte: isFirst ? ttfb : nil
                        )

                        continuation.yield(chunk)

                        offset += currentChunkSize
                        sequenceNumber += 1
                    }

                    let totalTime = Date().timeIntervalSince(startTime)
                    self.logger.info("[KyutaiPocket] Synthesis complete: \(text.count) chars in \(String(format: "%.3f", totalTime))s")

                } catch {
                    self.logger.error("[KyutaiPocket] Synthesis failed: \(error.localizedDescription)")
                }

                continuation.finish()
            }
        }
    }

    /// Flush any pending audio
    public func flush() async throws {
        // On-device synthesis doesn't maintain state between calls
        logger.debug("[KyutaiPocket] flush called (no-op)")
    }

    // MARK: - Model Management

    /// Get model manager for UI binding
    nonisolated func getModelManager() -> KyutaiPocketModelManager {
        modelManager
    }

    /// Check if models are ready for synthesis
    public func isReady() async -> Bool {
        let state = await modelManager.currentState()
        return state == .loaded
    }

    /// Ensure models are loaded
    public func ensureLoaded() async throws {
        let state = await modelManager.currentState()

        switch state {
        case .loaded:
            return

        case .available:
            logger.info("[KyutaiPocket] Loading models...")
            try await modelManager.loadModels(config: config)

        case .notDownloaded:
            throw KyutaiPocketModelError.modelsNotDownloaded

        case .downloading, .loading:
            // Wait for current operation
            while true {
                let currentState = await modelManager.currentState()
                if currentState == .loaded {
                    return
                }
                if case .error = currentState {
                    throw KyutaiPocketModelError.modelsNotLoaded
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

        case .error(let message):
            throw KyutaiPocketModelError.inferenceError(message)
        }
    }

    /// Unload models to free memory
    public func unloadModels() async {
        await modelManager.unloadModels()
        tokenizer = nil
        currentVoiceEmbedding = nil
        logger.info("[KyutaiPocket] Models unloaded")
    }

    // MARK: - Private Synthesis

    /// Perform the actual synthesis using CoreML models
    private func performSynthesis(text: String, startTime: Date) async throws -> Data {
        let models = try await modelManager.getLoadedModels()

        // Initialize tokenizer if needed
        if tokenizer == nil {
            tokenizer = try KyutaiPocketTokenizer()
        }

        guard let tokenizer = tokenizer else {
            throw KyutaiPocketModelError.inferenceError("Tokenizer not initialized")
        }

        // Step 1: Tokenize text
        let tokens = tokenizer.encode(text)
        let inputIds = try createInputTensor(from: tokens)

        // Step 2: Get voice embedding
        let voiceEmbedding = try await getVoiceEmbedding()

        // Step 3: Run transformer to generate audio token logits
        let transformerOutput = try await runTransformer(
            model: models.transformer,
            inputIds: inputIds,
            voiceEmbedding: voiceEmbedding
        )

        // Step 4: Run sampler with consistency steps
        let audioTokens = try await runSampler(
            model: models.sampler,
            logits: transformerOutput,
            temperature: config.temperature,
            topP: config.topP,
            consistencySteps: config.consistencySteps
        )

        // Step 5: Run Mimi decoder to generate waveform
        let waveform = try await runMimiDecoder(
            model: models.mimiDecoder,
            audioTokens: audioTokens
        )

        // Convert waveform to PCM data
        return waveformToData(waveform)
    }

    /// Get voice embedding for current configuration
    private func getVoiceEmbedding() async throws -> MLMultiArray {
        // Use cached if available and voice hasn't changed
        if let cached = currentVoiceEmbedding {
            return cached
        }

        // Check for voice cloning reference audio
        if let refPath = config.referenceAudioPath {
            let embedding = try await extractVoiceEmbedding(from: refPath)
            currentVoiceEmbedding = embedding
            return embedding
        }

        // Use built-in voice embedding
        let voice = KyutaiPocketVoice(rawValue: config.voiceIndex) ?? .alba
        let floatEmbedding = try await modelManager.getVoiceEmbedding(for: voice)
        let embedding = try createVoiceEmbeddingTensor(from: floatEmbedding)
        currentVoiceEmbedding = embedding
        return embedding
    }

    /// Extract voice embedding from reference audio for cloning
    private func extractVoiceEmbedding(from audioPath: String) async throws -> MLMultiArray {
        // Load and preprocess audio
        let url = URL(fileURLWithPath: audioPath)
        let audioFile = try AVAudioFile(forReading: url)

        // Validate duration (need ~5 seconds)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        guard duration >= 3.0 else {
            throw KyutaiPocketModelError.inferenceError("Reference audio too short (need 3+ seconds)")
        }

        // Extract embedding using encoder portion of model
        // This is a simplified placeholder - actual implementation needs the encoder model
        logger.info("[KyutaiPocket] Extracting voice embedding from \(audioPath)")

        // For now, return default voice embedding
        let defaultVoice = try await modelManager.getVoiceEmbedding(for: .alba)
        return try createVoiceEmbeddingTensor(from: defaultVoice)
    }

    // MARK: - CoreML Inference

    /// Run transformer model
    private func runTransformer(
        model: MLModel,
        inputIds: MLMultiArray,
        voiceEmbedding: MLMultiArray
    ) async throws -> MLMultiArray {
        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIds,
            "voice_embedding": voiceEmbedding
        ])

        let output = try await model.prediction(from: inputFeatures)

        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
            throw KyutaiPocketModelError.inferenceError("Failed to get transformer output")
        }

        return logits
    }

    /// Run MLP sampler with consistency steps
    private func runSampler(
        model: MLModel,
        logits: MLMultiArray,
        temperature: Float,
        topP: Float,
        consistencySteps: Int
    ) async throws -> MLMultiArray {
        // Create temperature and topP tensors
        let tempArray = try MLMultiArray(shape: [1, 1], dataType: .float32)
        tempArray[0] = NSNumber(value: temperature)

        let topPArray = try MLMultiArray(shape: [1, 1], dataType: .float32)
        topPArray[0] = NSNumber(value: topP)

        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "logits": logits,
            "temperature": tempArray,
            "top_p": topPArray
        ])

        // Run multiple consistency steps
        var currentLogits = logits
        for step in 0..<consistencySteps {
            let stepFeatures = try MLDictionaryFeatureProvider(dictionary: [
                "logits": currentLogits,
                "temperature": tempArray,
                "top_p": topPArray
            ])

            let output = try await model.prediction(from: stepFeatures)

            if let refined = output.featureValue(for: "sampled_tokens")?.multiArrayValue {
                currentLogits = refined
            }

            logger.debug("[KyutaiPocket] Consistency step \(step + 1)/\(consistencySteps)")
        }

        guard let tokens = currentLogits as MLMultiArray? else {
            throw KyutaiPocketModelError.inferenceError("Failed to sample audio tokens")
        }

        return tokens
    }

    /// Run Mimi VAE decoder
    private func runMimiDecoder(
        model: MLModel,
        audioTokens: MLMultiArray
    ) async throws -> MLMultiArray {
        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "audio_tokens": audioTokens
        ])

        let output = try await model.prediction(from: inputFeatures)

        guard let waveform = output.featureValue(for: "waveform")?.multiArrayValue else {
            throw KyutaiPocketModelError.inferenceError("Failed to decode waveform")
        }

        return waveform
    }

    // MARK: - Tensor Helpers

    /// Create input tensor from token IDs
    private func createInputTensor(from tokens: [Int]) throws -> MLMultiArray {
        let shape = [1, NSNumber(value: tokens.count)]
        let array = try MLMultiArray(shape: shape, dataType: .int32)

        for (i, token) in tokens.enumerated() {
            array[i] = NSNumber(value: token)
        }

        return array
    }

    /// Create voice embedding tensor
    private func createVoiceEmbeddingTensor(from embedding: [Float]) throws -> MLMultiArray {
        let shape = [1, NSNumber(value: embedding.count)]
        let array = try MLMultiArray(shape: shape, dataType: .float32)

        for (i, value) in embedding.enumerated() {
            array[i] = NSNumber(value: value)
        }

        return array
    }

    /// Convert MLMultiArray waveform to PCM Data
    private func waveformToData(_ waveform: MLMultiArray) -> Data {
        let count = waveform.count
        var floatData = [Float](repeating: 0, count: count)

        let pointer = waveform.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            floatData[i] = pointer[i]
        }

        // Apply speed adjustment
        let adjustedData = applySpeedAdjustment(floatData, speed: config.speed)

        // Convert to Data
        return adjustedData.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Apply speed adjustment to waveform
    private func applySpeedAdjustment(_ samples: [Float], speed: Float) -> [Float] {
        guard speed != 1.0 else { return samples }

        // Simple linear interpolation for speed adjustment
        let newLength = Int(Float(samples.count) / speed)
        var result = [Float](repeating: 0, count: newLength)

        for i in 0..<newLength {
            let srcPos = Float(i) * speed
            let srcIndex = Int(srcPos)
            let frac = srcPos - Float(srcIndex)

            if srcIndex + 1 < samples.count {
                result[i] = samples[srcIndex] * (1 - frac) + samples[srcIndex + 1] * frac
            } else if srcIndex < samples.count {
                result[i] = samples[srcIndex]
            }
        }

        return result
    }

    // MARK: - Metrics

    /// Update performance metrics
    private func updateMetrics() {
        guard !latencyValues.isEmpty else { return }

        let sorted = latencyValues.sorted()
        let medianIndex = sorted.count / 2
        let p99Index = min(Int(Double(sorted.count) * 0.99), sorted.count - 1)

        metrics = TTSMetrics(
            medianTTFB: sorted[medianIndex],
            p99TTFB: sorted[p99Index]
        )
    }
}

// MARK: - Convenience Extensions

extension KyutaiPocketTTSService {

    /// Apply a preset configuration
    public func applyPreset(_ preset: KyutaiPocketPreset) async {
        await configurePocket(preset.config)
        logger.info("[KyutaiPocket] Applied preset: \(preset.displayName)")
    }

    /// Set voice by enum
    public func setVoice(_ voice: KyutaiPocketVoice) async {
        var newConfig = config
        newConfig.voiceIndex = voice.rawValue
        await configurePocket(newConfig)
    }

    /// Update temperature
    public func updateTemperature(_ value: Float) async {
        var newConfig = config
        newConfig.temperature = value
        await configurePocket(newConfig)
    }

    /// Update top-p
    public func updateTopP(_ value: Float) async {
        var newConfig = config
        newConfig.topP = value
        await configurePocket(newConfig)
    }

    /// Update speed
    public func updateSpeed(_ value: Float) async {
        var newConfig = config
        newConfig.speed = value
        await configurePocket(newConfig)
    }

    /// Update consistency steps
    public func updateConsistencySteps(_ value: Int) async {
        var newConfig = config
        newConfig.consistencySteps = value
        await configurePocket(newConfig)
    }

    /// Toggle Neural Engine usage
    public func setUseNeuralEngine(_ enabled: Bool) async {
        var newConfig = config
        newConfig.useNeuralEngine = enabled
        await configurePocket(newConfig)

        // Reload models with new compute unit setting
        if await modelManager.currentState() == .loaded {
            await modelManager.unloadModels()
            try? await modelManager.loadModels(config: newConfig)
        }
    }

    /// Set reference audio for voice cloning
    public func setReferenceAudio(path: String?) async {
        var newConfig = config
        newConfig.referenceAudioPath = path
        currentVoiceEmbedding = nil  // Clear cached embedding
        await configurePocket(newConfig)
    }

    /// Get current configuration
    public func getPocketConfig() -> KyutaiPocketTTSConfig {
        config
    }
}

// MARK: - Tokenizer

/// Simple tokenizer wrapper for Kyutai Pocket TTS
public class KyutaiPocketTokenizer {
    // Placeholder - actual implementation uses SentencePiece
    // The tokenizer model is loaded from tokenizer.model file

    init() throws {
        // Initialize SentencePiece processor
    }

    func encode(_ text: String) -> [Int] {
        // Placeholder implementation
        // Returns token IDs for the input text
        return Array(text.utf8).map { Int($0) }
    }

    func decode(_ tokens: [Int]) -> String {
        // Placeholder implementation
        return String(tokens.compactMap { UnicodeScalar($0) }.map { Character($0) })
    }
}

// MARK: - Preview Support

#if DEBUG
extension KyutaiPocketTTSService {
    static func preview() -> KyutaiPocketTTSService {
        KyutaiPocketTTSService()
    }
}
#endif
