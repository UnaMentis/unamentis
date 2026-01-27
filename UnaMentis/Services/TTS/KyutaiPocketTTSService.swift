// UnaMentis - Kyutai Pocket TTS Service
// On-device Text-to-Speech service using Kyutai Pocket TTS via Rust/Candle
//
// Part of Services/TTS

import AVFoundation
import Foundation
import OSLog

// MARK: - Streaming Event Handler

/// Handler for streaming TTS events, bridging Rust callbacks to AsyncStream
/// This class is NOT actor-isolated to allow callbacks from Rust threads
private final class StreamingEventHandler: TtsEventHandler {
    private let continuation: AsyncStream<TTSAudioChunk>.Continuation
    private var sequenceNumber = 0
    private var isFirst = true
    private var ttfbRecorded = false
    private let startTime: CFAbsoluteTime
    private var ttfb: TimeInterval = 0

    init(continuation: AsyncStream<TTSAudioChunk>.Continuation, startTime: CFAbsoluteTime) {
        self.continuation = continuation
        self.startTime = startTime
    }

    func onAudioChunk(chunk: AudioChunk) {
        if !ttfbRecorded {
            ttfb = CFAbsoluteTimeGetCurrent() - startTime
            ttfbRecorded = true
            NSLog("⏱️ [KyutaiPocket] STREAMING TTFB: %.3fs (%.0fms)", ttfb, ttfb * 1000)
        }

        // AudioChunk from Rust contains raw PCM data (not WAV)
        let ttsChunk = TTSAudioChunk(
            audioData: chunk.audioData,
            format: .pcmFloat32(sampleRate: Double(chunk.sampleRate), channels: 1),
            sequenceNumber: sequenceNumber,
            isFirst: isFirst,
            isLast: chunk.isFinal,
            timeToFirstByte: isFirst ? ttfb : nil
        )

        continuation.yield(ttsChunk)

        sequenceNumber += 1
        isFirst = false

        if chunk.isFinal {
            NSLog("⏱️ [KyutaiPocket] Final chunk received, sequence: %d", sequenceNumber - 1)
        }
    }

    func onProgress(progress: Float) {
        // Progress updates for debugging (commented out to reduce noise)
        // NSLog("⏱️ [KyutaiPocket] Streaming progress: %.1f%%", progress * 100)
    }

    func onComplete() {
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        NSLog("⏱️ [KyutaiPocket] Streaming complete - total: %.3fs, TTFB: %.3fs", totalTime, ttfb)
        continuation.finish()
    }

    func onError(message: String) {
        NSLog("🔴 [KyutaiPocket] Streaming error: %@", message)
        continuation.finish()
    }

    func getTimeToFirstByte() -> TimeInterval {
        ttfb
    }
}

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

    /// Synthesize text to audio stream using streaming API for low latency
    public func synthesize(text: String) async throws -> AsyncStream<TTSAudioChunk> {
        let synthesizeStart = CFAbsoluteTimeGetCurrent()
        logger.info("[KyutaiPocket] synthesize called - text length: \(text.count)")
        NSLog("⏱️ [KyutaiPocket] synthesize() START (STREAMING) - text length: \(text.count)")

        // Ensure engine is loaded
        let ensureStart = CFAbsoluteTimeGetCurrent()
        try await ensureLoaded()
        let ensureTime = (CFAbsoluteTimeGetCurrent() - ensureStart) * 1000
        NSLog("⏱️ [KyutaiPocket] synthesize: ensureLoaded took %.1fms", ensureTime)

        guard let engine = engine else {
            throw KyutaiPocketModelError.modelsNotLoaded
        }

        // Capture engine reference for the closure
        let capturedEngine = engine

        // Create AsyncStream with streaming handler
        // The handler receives callbacks from Rust as audio chunks are generated
        return AsyncStream { continuation in
            let streamStart = CFAbsoluteTimeGetCurrent()
            let handler = StreamingEventHandler(continuation: continuation, startTime: streamStart)

            NSLog("⏱️ [KyutaiPocket] Starting streaming synthesis...")

            do {
                // startStreaming is non-blocking - it kicks off synthesis and returns immediately
                // The handler will receive onAudioChunk callbacks as audio is generated
                try capturedEngine.startStreaming(text: text, handler: handler)
                NSLog("⏱️ [KyutaiPocket] startStreaming() returned, waiting for callbacks...")
            } catch let error as PocketTtsError {
                NSLog("🔴 [KyutaiPocket] startStreaming failed: %@", error.localizedDescription)
                continuation.finish()
            } catch {
                NSLog("🔴 [KyutaiPocket] startStreaming failed: %@", error.localizedDescription)
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
        let overallStart = CFAbsoluteTimeGetCurrent()

        if engine != nil && engine!.isReady() {
            NSLog("⏱️ [KyutaiPocket] ensureLoaded: already loaded (0ms)")
            return
        }

        logger.info("[KyutaiPocket] Loading Rust/Candle engine...")
        NSLog("⏱️ [KyutaiPocket] ensureLoaded: COLD START - loading engine...")

        // Get model path
        let pathStart = CFAbsoluteTimeGetCurrent()
        let modelPath = try await modelManager.getModelPath()
        let pathTime = (CFAbsoluteTimeGetCurrent() - pathStart) * 1000
        NSLog("⏱️ [KyutaiPocket] ensureLoaded: getModelPath took %.1fms", pathTime)

        do {
            // Create Rust engine with model path
            let engineStart = CFAbsoluteTimeGetCurrent()
            engine = try PocketTtsEngine(modelPath: modelPath)
            let engineTime = (CFAbsoluteTimeGetCurrent() - engineStart) * 1000
            NSLog("⏱️ [KyutaiPocket] ensureLoaded: PocketTtsEngine() took %.1fms", engineTime)

            // Configure with current settings
            let configStart = CFAbsoluteTimeGetCurrent()
            let rustConfig = createRustConfig()
            try engine?.configure(config: rustConfig)
            let configTime = (CFAbsoluteTimeGetCurrent() - configStart) * 1000
            NSLog("⏱️ [KyutaiPocket] ensureLoaded: configure() took %.1fms", configTime)

            let totalTime = (CFAbsoluteTimeGetCurrent() - overallStart) * 1000
            logger.info("[KyutaiPocket] Engine loaded successfully")
            logger.info("[KyutaiPocket] Model version: \(self.engine?.modelVersion() ?? "unknown")")
            logger.info("[KyutaiPocket] Parameters: \(self.engine?.parameterCount() ?? 0)")
            NSLog("⏱️ [KyutaiPocket] ensureLoaded: TOTAL COLD START = %.1fms (path: %.1fms, engine: %.1fms, config: %.1fms)",
                  totalTime, pathTime, engineTime, configTime)

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
