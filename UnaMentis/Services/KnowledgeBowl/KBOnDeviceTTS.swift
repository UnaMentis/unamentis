//
//  KBOnDeviceTTS.swift
//  UnaMentis
//
//  TTS adapter for Knowledge Bowl that respects user's global TTS provider setting
//

import AVFoundation
import OSLog

// MARK: - Audio Player Manager

/// MainActor-isolated audio player manager to properly retain AVAudioPlayer during playback
@MainActor
private final class AudioPlayerManager {
    static let shared = AudioPlayerManager()
    private var currentPlayer: AVAudioPlayer?

    private init() {}

    /// Play audio from URL and wait for completion
    func playAndWait(url: URL) async throws -> TimeInterval {
        // Clean up any previous player
        currentPlayer?.stop()
        currentPlayer = nil

        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        currentPlayer = player  // Retain the player!

        let duration = player.duration
        NSLog("🟡 AudioPlayerManager: duration=\(duration)s, playing...")
        player.play()

        return duration
    }

    /// Clear the current player after playback completes
    func clearPlayer() {
        currentPlayer?.stop()
        currentPlayer = nil
    }
}

// MARK: - Knowledge Bowl TTS Adapter

/// TTS adapter for Knowledge Bowl that delegates to the user's configured TTS provider
actor KBOnDeviceTTS {
    // MARK: - State

    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var progress: Float = 0

    // MARK: - Private State

    private var ttsService: TTSService?
    private let logger = Logger(subsystem: "com.unamentis", category: "KBOnDeviceTTS")


    // MARK: - Configuration

    /// Voice configuration for questions
    struct VoiceConfig: Sendable {
        var language: String = "en-US"
        var rate: Float = AVSpeechUtteranceDefaultSpeechRate
        var pitchMultiplier: Float = 1.0
        var volume: Float = 1.0
        var preUtteranceDelay: TimeInterval = 0
        var postUtteranceDelay: TimeInterval = 0

        /// Standard reading pace for questions
        static let questionPace = VoiceConfig(
            rate: AVSpeechUtteranceDefaultSpeechRate * 0.9,
            pitchMultiplier: 1.0
        )

        /// Slower pace for complex questions
        static let slowPace = VoiceConfig(
            rate: AVSpeechUtteranceDefaultSpeechRate * 0.75,
            pitchMultiplier: 1.0
        )

        /// Faster pace for experienced users
        static let fastPace = VoiceConfig(
            rate: AVSpeechUtteranceDefaultSpeechRate * 1.1,
            pitchMultiplier: 1.0
        )
    }

    // MARK: - Initialization

    init() {
        logger.info("KBOnDeviceTTS initialized - will use global TTS provider setting")
        // Service is created lazily on first use to respect user settings
    }

    // MARK: - Public API

    /// Pre-warm the TTS engine to avoid cold-start latency
    /// Call this during session preparation, before the first speak() call
    func prewarm() async {
        let prewarmStart = CFAbsoluteTimeGetCurrent()
        NSLog("⏱️ [KBOnDeviceTTS] prewarm() START")

        // Configure the service (creates it if needed)
        await ensureServiceConfigured()

        // For Kyutai, also ensure the model is loaded
        if let kyutaiService = ttsService as? KyutaiPocketTTSService {
            NSLog("⏱️ [KBOnDeviceTTS] prewarm() - loading Kyutai engine...")
            do {
                try await kyutaiService.ensureLoaded()
            } catch {
                logger.error("Failed to prewarm Kyutai engine: \(error.localizedDescription)")
                NSLog("⏱️ [KBOnDeviceTTS] prewarm() - Kyutai load FAILED: \(error.localizedDescription)")
            }
        }

        let prewarmTime = (CFAbsoluteTimeGetCurrent() - prewarmStart) * 1000
        NSLog("⏱️ [KBOnDeviceTTS] prewarm() COMPLETE - took %.1fms", prewarmTime)
    }

    /// Speak text with default configuration
    func speak(_ text: String) async {
        await speak(text, config: .questionPace)
    }

    /// Speak text with custom configuration
    func speak(_ text: String, config: VoiceConfig) async {
        let speakStart = CFAbsoluteTimeGetCurrent()
        NSLog("⏱️ [KBOnDeviceTTS] speak() START - text length: \(text.count)")

        // Ensure TTS service is configured
        let configureStart = CFAbsoluteTimeGetCurrent()
        await ensureServiceConfigured()
        let configureTime = (CFAbsoluteTimeGetCurrent() - configureStart) * 1000
        NSLog("⏱️ [KBOnDeviceTTS] ensureServiceConfigured took %.1fms", configureTime)

        NSLog("🟢 KBOnDeviceTTS.speak() - after ensureServiceConfigured, ttsService exists: \(ttsService != nil)")

        guard let service = ttsService else {
            logger.error("Failed to configure TTS service")
            NSLog("🔴 KBOnDeviceTTS.speak() - NO TTS SERVICE, returning")
            return
        }

        NSLog("🟢 KBOnDeviceTTS.speak() - service type: \(type(of: service))")

        isSpeaking = true
        progress = 0

        do {
            let synthesizeStart = CFAbsoluteTimeGetCurrent()
            NSLog("⏱️ [KBOnDeviceTTS] calling service.synthesize()")
            // Use the configured TTS service (respects user's global setting)
            let audioStream = try await service.synthesize(text: text)
            let synthesizeTime = (CFAbsoluteTimeGetCurrent() - synthesizeStart) * 1000
            NSLog("⏱️ [KBOnDeviceTTS] synthesize() returned stream in %.1fms", synthesizeTime)

            // AppleTTSService plays audio internally, others need external playback
            if service is AppleTTSService {
                NSLog("🟡 KBOnDeviceTTS.speak() - using AppleTTSService path")
                // AppleTTSService handles playback internally - just track progress
                var chunkCount = 0
                for try await chunk in audioStream {
                    chunkCount += 1
                    if chunk.isFirst {
                        progress = 0.1
                        NSLog("🟡 First chunk received")
                    } else if chunk.isLast {
                        progress = 1.0
                        NSLog("🟡 Last chunk received, total chunks: \(chunkCount)")
                    } else {
                        progress += 0.1
                    }
                }
            } else {
                NSLog("🟡 KBOnDeviceTTS.speak() - using Kyutai/external playback path")
                // For services that return raw audio (e.g., Kyutai), collect and play
                var audioChunks: [TTSAudioChunk] = []

                for try await chunk in audioStream {
                    audioChunks.append(chunk)

                    // Update progress during collection
                    if chunk.isFirst {
                        progress = 0.1
                        NSLog("🟡 First audio chunk received")
                    } else if !chunk.isLast {
                        progress = min(0.5, Float(audioChunks.count) * 0.05)
                    }
                }

                NSLog("🟡 Collected \(audioChunks.count) audio chunks")

                // Play the collected audio
                if !audioChunks.isEmpty {
                    NSLog("🟡 Playing collected audio...")
                    await playAudioChunks(audioChunks)
                    NSLog("🟡 Audio playback complete")
                } else {
                    NSLog("🔴 No audio chunks to play!")
                }
            }

            isSpeaking = false
            progress = 1.0
            let totalTime = (CFAbsoluteTimeGetCurrent() - speakStart) * 1000
            NSLog("⏱️ [KBOnDeviceTTS] speak() COMPLETE - TOTAL TIME: %.1fms", totalTime)

        } catch {
            logger.error("TTS synthesis failed: \(error.localizedDescription)")
            NSLog("🔴 KBOnDeviceTTS.speak() ERROR: \(error.localizedDescription)")
            isSpeaking = false
            progress = 0
        }
    }

    /// Speak a Knowledge Bowl question
    func speakQuestion(_ question: KBQuestion, config: VoiceConfig = .questionPace) async {
        logger.info("[KB-TTS] Speaking question: \(question.text.prefix(50))...")
        await speak(question.text, config: config)
    }

    /// Pause speech
    func pause() {
        // Not all TTS services support pause, but we set the flag
        guard isSpeaking, !isPaused else { return }
        isPaused = true
        logger.debug("Speech paused")
    }

    /// Resume speech
    func resume() {
        guard isPaused else { return }
        isPaused = false
        logger.debug("Speech resumed")
    }

    /// Stop speech
    func stop() async {
        if let service = ttsService {
            try? await service.flush()
        }

        isSpeaking = false
        isPaused = false
        progress = 0
        logger.debug("Speech stopped")
    }

    // MARK: - Private Helpers

    /// Play audio chunks using AVAudioPlayer
    private func playAudioChunks(_ chunks: [TTSAudioChunk]) async {
        guard !chunks.isEmpty else { return }

        // Combine all audio data
        var combinedData = Data()
        var sampleRate: Double = 24000.0
        var isFloat32 = false

        for chunk in chunks {
            combinedData.append(chunk.audioData)

            // Extract format from first chunk
            if case .pcmFloat32(let rate, _) = chunk.format {
                sampleRate = rate
                isFloat32 = true
            }
        }

        guard !combinedData.isEmpty else {
            logger.warning("No audio data to play")
            return
        }

        NSLog("🟡 playAudioChunks: combined data size: \(combinedData.count) bytes, sampleRate: \(sampleRate), isFloat32: \(isFloat32)")

        // Convert float32 to int16 PCM for better AVAudioPlayer compatibility
        // Also applies fade-in to eliminate pop/click at start
        var pcmData: Data
        if isFloat32 {
            pcmData = convertFloat32ToInt16(combinedData, fadeInMs: 10, sampleRate: sampleRate)
            NSLog("🟡 Converted to int16 PCM: \(pcmData.count) bytes")
        } else {
            pcmData = combinedData
        }

        progress = 0.6

        do {
            // Configure audio session for playback BEFORE creating player
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            NSLog("🟡 Audio session configured for playback")

            // Create standard PCM WAV file (int16) for AVAudioPlayer
            let wavData = createWAVFile(pcm: pcmData, sampleRate: Int(sampleRate), isFloat32: false)
            NSLog("🟡 WAV data created: \(wavData.count) bytes")

            // Write to Documents directory for analysis (DEBUG: keep file for verification)
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let tempURL = documentsURL.appendingPathComponent("kyutai_tts_output.wav")

            try wavData.write(to: tempURL)
            NSLog("🟡 WAV written to: \(tempURL.path)")

            progress = 0.7

            // Play using MainActor-isolated player manager (retains player during playback)
            let duration: TimeInterval
            do {
                duration = try await AudioPlayerManager.shared.playAndWait(url: tempURL)
            } catch {
                logger.error("Failed to play audio: \(error.localizedDescription)")
                NSLog("🔴 AudioPlayerManager error: \(error.localizedDescription)")
                return
            }

            progress = 0.8

            // Wait for playback duration plus a small buffer
            if duration > 0 {
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.5) * 1_000_000_000))
            }

            // Clear the retained player after playback
            await AudioPlayerManager.shared.clearPlayer()

            // DEBUG: Keep WAV file for analysis - do NOT delete
            // try? FileManager.default.removeItem(at: tempURL)
            NSLog("🟡 WAV file preserved at: \(tempURL.path)")

            progress = 1.0

        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
        }
    }

    /// Create WAV file from PCM data
    private func createWAVFile(pcm: Data, sampleRate: Int, isFloat32: Bool) -> Data {
        var wavData = Data()

        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = isFloat32 ? 32 : 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let audioFormat: UInt16 = isFloat32 ? 3 : 1  // 3 = IEEE float, 1 = PCM

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(UInt32(36 + pcm.count).littleEndianData)
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(UInt32(16).littleEndianData)
        wavData.append(audioFormat.littleEndianData)
        wavData.append(numChannels.littleEndianData)
        wavData.append(UInt32(sampleRate).littleEndianData)
        wavData.append(byteRate.littleEndianData)
        wavData.append(blockAlign.littleEndianData)
        wavData.append(bitsPerSample.littleEndianData)

        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(UInt32(pcm.count).littleEndianData)
        wavData.append(pcm)

        return wavData
    }

    /// Convert float32 PCM to int16 PCM with optional fade-in
    /// AVAudioPlayer has better support for int16 PCM than IEEE float
    private func convertFloat32ToInt16(_ data: Data, fadeInMs: Double, sampleRate: Double) -> Data {
        let sampleCount = data.count / MemoryLayout<Float>.size
        let fadeSamples = Int(sampleRate * fadeInMs / 1000.0)

        var int16Data = Data(capacity: sampleCount * MemoryLayout<Int16>.size)

        data.withUnsafeBytes { buffer in
            guard let floatPtr = buffer.baseAddress?.assumingMemoryBound(to: Float.self) else { return }

            for i in 0..<sampleCount {
                var sample = floatPtr[i]

                // Apply fade-in for first few samples
                if i < fadeSamples {
                    let fadeMultiplier = Float(i) / Float(fadeSamples)
                    sample *= fadeMultiplier
                }

                // Clamp to [-1, 1] and convert to int16
                let clamped = max(-1.0, min(1.0, sample))
                let int16Value = Int16(clamped * Float(Int16.max))

                // Append as little-endian bytes
                withUnsafeBytes(of: int16Value.littleEndian) { int16Data.append(contentsOf: $0) }
            }
        }

        NSLog("🟡 Converted \(sampleCount) float32 samples to int16 with \(fadeInMs)ms fade-in")
        return int16Data
    }

    /// Ensure TTS service is configured based on user settings
    private func ensureServiceConfigured() async {
        NSLog("🔵 KBOnDeviceTTS.ensureServiceConfigured() START")

        // If service already exists, reuse it
        if ttsService != nil {
            NSLog("🔵 TTS service already exists, reusing")
            return
        }

        // Read user's TTS provider setting (same key as main session)
        let ttsProviderRaw = UserDefaults.standard.string(forKey: "ttsProvider")
        NSLog("🔵 ttsProvider UserDefaults raw value: '\(ttsProviderRaw ?? "nil")'")

        let ttsProvider: TTSProvider

        if let rawValue = ttsProviderRaw,
           let provider = TTSProvider(rawValue: rawValue) {
            ttsProvider = provider
            NSLog("🔵 Parsed TTS provider: \(ttsProvider.rawValue)")
        } else {
            ttsProvider = .appleTTS  // Default fallback
            NSLog("🔵 Using default TTS provider: \(ttsProvider.rawValue)")
        }

        logger.info("Knowledge Bowl using TTS provider: \(ttsProvider.rawValue)")

        // Create the appropriate TTS service (same logic as SessionView)
        NSLog("🔵 Creating TTS service for provider: \(ttsProvider.rawValue)")
        switch ttsProvider {
        case .appleTTS:
            logger.info("Using Apple TTS")
            NSLog("🔵 Creating AppleTTSService")
            ttsService = AppleTTSService()

        case .kyutaiPocket:
            // Use Kyutai Pocket TTS (on-device Rust/Candle inference)
            // Use lowLatency preset for KB sessions to minimize delay before audio
            logger.info("Using Kyutai Pocket TTS (on-device) with lowLatency preset")
            NSLog("🔵 Creating KyutaiPocketTTSService with lowLatency config")
            ttsService = KyutaiPocketTTSService(config: .lowLatency)

        case .selfHosted, .vibeVoice, .chatterbox, .elevenLabsFlash, .elevenLabsTurbo, .deepgramAura2:
            // For server-based TTS, fall back to Apple TTS for Knowledge Bowl
            // (to avoid network dependency in timed competition setting)
            logger.warning("Server-based TTS not supported for Knowledge Bowl, using Apple TTS")
            NSLog("🔵 Server-based TTS, falling back to AppleTTSService")
            ttsService = AppleTTSService()

        default:
            logger.warning("Unknown TTS provider, using Apple TTS")
            NSLog("🔵 Unknown provider, using AppleTTSService")
            ttsService = AppleTTSService()
        }

        NSLog("🔵 TTS service created: \(type(of: ttsService!))")

        // Configure voice settings
        if let service = ttsService {
            await service.configure(TTSVoiceConfig(
                voiceId: "default",
                rate: 1.0
            ))
        }
    }

    // MARK: - Available Voices

    /// Get available voices for a language
    static func availableVoices(for language: String = "en-US") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language.prefix(2)) }
    }

    /// Get the best quality voice for a language
    static func bestVoice(for language: String = "en-US") -> AVSpeechSynthesisVoice? {
        let voices = availableVoices(for: language)

        // Prefer enhanced or premium voices
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }

        // Fall back to default
        return AVSpeechSynthesisVoice(language: language)
    }
}

// MARK: - Helper Extensions

extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

// MARK: - Preview Support

#if DEBUG
extension KBOnDeviceTTS {
    /// Create a TTS instance for previews
    static func preview() -> KBOnDeviceTTS {
        KBOnDeviceTTS()
    }
}
#endif
