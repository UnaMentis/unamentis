// UnaMentis - Kyutai Pocket TTS Service
// On-device Text-to-Speech service using Kyutai Pocket TTS via Rust/Candle
//
// Part of Services/TTS

import AVFoundation
import Foundation
import OSLog

// MARK: - Kyutai Pocket TTS Service

/// On-device TTS service using Kyutai Pocket TTS with Rust/Candle inference
///
/// Kyutai Pocket TTS is a 100M parameter on-device model featuring:
/// - 8 built-in voices (Les Misérables characters)
/// - 5-second voice cloning capability
/// - 24kHz high-quality audio output
/// - ~200ms time to first audio
/// - 1.84% WER (best in class for on-device)
/// - MIT licensed
///
/// This implementation uses Rust/Candle for native CPU inference on iOS,
/// providing better performance and compatibility than CoreML for
/// stateful streaming transformers.
public actor KyutaiPocketTTSService: TTSService {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.unamentis", category: "KyutaiPocketTTS")

    /// Rust TTS engine instance
    private var engine: PocketTtsEngine?

    /// Model manager for model state
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
        logger.info("KyutaiPocketTTSService initialized (Rust/Candle backend)")
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

        // Update Rust engine config if loaded
        if let engine = engine {
            do {
                let rustConfig = createRustConfig()
                try engine.configure(config: rustConfig)
            } catch {
                logger.error("Failed to configure engine: \(error.localizedDescription)")
            }
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

        // Update Rust engine config if loaded
        if let engine = engine {
            do {
                let rustConfig = createRustConfig()
                try engine.configure(config: rustConfig)
            } catch {
                logger.error("Failed to configure engine: \(error.localizedDescription)")
            }
        }

        logger.debug("Kyutai Pocket configured: voice=\(config.voiceIndex), temp=\(config.temperature)")
    }

    /// Synthesize text to audio stream
    public func synthesize(text: String) async throws -> AsyncStream<TTSAudioChunk> {
        logger.info("[KyutaiPocket] synthesize called - text length: \(text.count)")

        // Ensure engine is loaded
        try await ensureLoaded()

        guard let engine = engine else {
            throw KyutaiPocketModelError.modelsNotLoaded
        }

        let startTime = Date()

        return AsyncStream { continuation in
            Task {
                do {
                    // Perform synchronous synthesis using Rust engine
                    let result = try engine.synthesize(text: text)

                    let ttfb = Date().timeIntervalSince(startTime)
                    self.latencyValues.append(ttfb)
                    self.updateMetrics()
                    self.logger.info("[KyutaiPocket] TTFB: \(String(format: "%.3f", ttfb))s")

                    // Convert WAV data to raw PCM for streaming
                    let audioData = result.audioData
                    let sampleRate = result.sampleRate

                    // Skip WAV header (44 bytes) to get raw PCM
                    let pcmData = audioData.count > 44 ? audioData.dropFirst(44) : audioData

                    // Emit chunks for streaming compatibility
                    let chunkSize = Int(sampleRate) / 10 * 4  // ~100ms at 24kHz, 32-bit float
                    var offset = 0
                    var sequenceNumber = 0

                    while offset < pcmData.count {
                        let remaining = pcmData.count - offset
                        let currentChunkSize = min(chunkSize, remaining)
                        let chunkData = Data(pcmData[pcmData.startIndex.advanced(by: offset)..<pcmData.startIndex.advanced(by: offset + currentChunkSize)])

                        let isFirst = sequenceNumber == 0
                        let isLast = offset + currentChunkSize >= pcmData.count

                        let chunk = TTSAudioChunk(
                            audioData: chunkData,
                            format: .pcmFloat32(sampleRate: Double(sampleRate), channels: 1),
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
                    self.logger.info("[KyutaiPocket] Synthesis complete: \(text.count) chars in \(String(format: "%.3f", totalTime))s, duration: \(String(format: "%.2f", result.durationSeconds))s")

                } catch let error as PocketTtsError {
                    self.logger.error("[KyutaiPocket] Synthesis failed: \(error.localizedDescription)")
                } catch {
                    self.logger.error("[KyutaiPocket] Synthesis failed: \(error.localizedDescription)")
                }

                continuation.finish()
            }
        }
    }

    /// Flush any pending audio
    public func flush() async throws {
        // Rust engine doesn't maintain state between calls
        logger.debug("[KyutaiPocket] flush called (no-op)")
    }

    // MARK: - Model Management

    /// Get model manager for UI binding
    nonisolated func getModelManager() -> KyutaiPocketModelManager {
        modelManager
    }

    /// Check if models are ready for synthesis
    public func isReady() async -> Bool {
        engine?.isReady() ?? false
    }

    /// Ensure models are loaded
    public func ensureLoaded() async throws {
        if engine != nil && engine!.isReady() {
            return
        }

        logger.info("[KyutaiPocket] Loading Rust/Candle engine...")

        // Get model path
        let modelPath = try await modelManager.getModelPath()

        do {
            // Create Rust engine with model path
            engine = try PocketTtsEngine(modelPath: modelPath)

            // Configure with current settings
            let rustConfig = createRustConfig()
            try engine?.configure(config: rustConfig)

            logger.info("[KyutaiPocket] Engine loaded successfully")
            logger.info("[KyutaiPocket] Model version: \(self.engine?.modelVersion() ?? "unknown")")
            logger.info("[KyutaiPocket] Parameters: \(self.engine?.parameterCount() ?? 0)")

        } catch let error as PocketTtsError {
            logger.error("[KyutaiPocket] Failed to load engine: \(error.localizedDescription)")
            throw KyutaiPocketModelError.inferenceError(error.localizedDescription)
        }
    }

    /// Unload models to free memory
    public func unloadModels() async {
        engine?.unload()
        engine = nil
        logger.info("[KyutaiPocket] Engine unloaded")
    }

    // MARK: - Private Helpers

    /// Create Rust TtsConfig from Swift config
    private func createRustConfig() -> TtsConfig {
        TtsConfig(
            voiceIndex: UInt32(config.voiceIndex),
            temperature: config.temperature,
            topP: config.topP,
            speed: config.speed,
            consistencySteps: UInt32(config.consistencySteps),
            useFixedSeed: false,
            seed: 0
        )
    }

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

    /// Set reference audio for voice cloning
    public func setReferenceAudio(path: String?) async {
        var newConfig = config
        newConfig.referenceAudioPath = path
        await configurePocket(newConfig)

        // If we have an engine, set reference audio
        if let engine = engine, let audioPath = path {
            do {
                let audioData = try Data(contentsOf: URL(fileURLWithPath: audioPath))
                try engine.setReferenceAudio(audioData: audioData, sampleRate: 24000)
                logger.info("[KyutaiPocket] Reference audio set for voice cloning")
            } catch {
                logger.error("[KyutaiPocket] Failed to set reference audio: \(error.localizedDescription)")
            }
        } else if let engine = engine, path == nil {
            engine.clearReferenceAudio()
        }
    }

    /// Get current configuration
    public func getPocketConfig() -> KyutaiPocketTTSConfig {
        config
    }

    /// Get available voices from Rust engine
    public func getAvailableVoices() -> [VoiceInfo] {
        availableVoices().map { pocketVoice in
            VoiceInfo(
                id: String(pocketVoice.index),
                name: pocketVoice.name,
                language: "en",  // Kyutai Pocket is English only
                gender: pocketVoice.gender
            )
        }
    }

    /// Get library version
    public func getVersion() -> String {
        version()
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
