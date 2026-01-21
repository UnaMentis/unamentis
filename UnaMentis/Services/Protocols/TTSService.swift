// UnaMentis - TTS Service Protocol
// Protocol defining Text-to-Speech interface
//
// Part of the Provider Abstraction Layer (TDD Section 6)

import AVFoundation

// MARK: - TTS Audio Chunk

/// Chunk of synthesized audio from TTS service
public struct TTSAudioChunk: Sendable {
    /// Raw audio data
    public let audioData: Data
    
    /// Audio format
    public let format: TTSAudioFormat
    
    /// Sequence number for ordering chunks
    public let sequenceNumber: Int
    
    /// Whether this is the first chunk
    public let isFirst: Bool
    
    /// Whether this is the last chunk
    public let isLast: Bool
    
    /// Time to first byte (only set on first chunk)
    public let timeToFirstByte: TimeInterval?
    
    public init(
        audioData: Data,
        format: TTSAudioFormat,
        sequenceNumber: Int,
        isFirst: Bool,
        isLast: Bool,
        timeToFirstByte: TimeInterval? = nil
    ) {
        self.audioData = audioData
        self.format = format
        self.sequenceNumber = sequenceNumber
        self.isFirst = isFirst
        self.isLast = isLast
        self.timeToFirstByte = timeToFirstByte
    }
    
    /// Convert to AVAudioPCMBuffer for playback
    public func toAVAudioPCMBuffer() throws -> AVAudioPCMBuffer {
        // Implementation depends on format
        guard let audioFormat = format.avAudioFormat else {
            print("[TTS Buffer] ERROR: Invalid audio format - cannot convert to AVAudioFormat")
            throw TTSError.invalidAudioFormat
        }

        print("[TTS Buffer] Converting audio: inputSize=\(audioData.count) bytes, format=\(format)")

        // For WAV data, we need to strip the header (44 bytes for standard WAV)
        // WAV files start with "RIFF" magic bytes
        var pcmData = audioData
        if audioData.count > 44 {
            let headerBytes = [UInt8](audioData.prefix(4))
            let isWav = headerBytes == [0x52, 0x49, 0x46, 0x46] // "RIFF"
            print("[TTS Buffer] Header check: first 4 bytes = \(headerBytes.map { String(format: "%02X", $0) }.joined(separator: " ")), isWAV=\(isWav)")
            if isWav {
                // This is a WAV file - skip the 44-byte header to get raw PCM
                pcmData = audioData.dropFirst(44)
                print("[TTS Buffer] Stripped WAV header, PCM data size: \(pcmData.count) bytes")
            }
        }

        let bytesPerFrame = audioFormat.streamDescription.pointee.mBytesPerFrame
        let frameCount = UInt32(pcmData.count) / bytesPerFrame
        print("[TTS Buffer] bytesPerFrame=\(bytesPerFrame), frameCount=\(frameCount), sampleRate=\(audioFormat.sampleRate)")

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            print("[TTS Buffer] ERROR: Failed to create AVAudioPCMBuffer")
            throw TTSError.bufferCreationFailed
        }

        buffer.frameLength = frameCount

        // Copy data to the correct channel data type based on format
        pcmData.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                switch format {
                case .pcmFloat32:
                    if let channelData = buffer.floatChannelData?[0] {
                        memcpy(channelData, baseAddress, pcmData.count)
                        print("[TTS Buffer] Copied \(pcmData.count) bytes to float32 buffer")
                    } else {
                        print("[TTS Buffer] ERROR: floatChannelData is nil")
                    }
                case .pcmInt16:
                    if let channelData = buffer.int16ChannelData?[0] {
                        memcpy(channelData, baseAddress, pcmData.count)
                        print("[TTS Buffer] Copied \(pcmData.count) bytes to int16 buffer")
                    } else {
                        print("[TTS Buffer] ERROR: int16ChannelData is nil")
                    }
                default:
                    // For other formats, try float32
                    if let channelData = buffer.floatChannelData?[0] {
                        memcpy(channelData, baseAddress, pcmData.count)
                        print("[TTS Buffer] Copied \(pcmData.count) bytes to float32 buffer (default)")
                    }
                }
            }
        }

        print("[TTS Buffer] Successfully created buffer with \(frameCount) frames")
        return buffer
    }
}

/// Audio format for TTS output
public enum TTSAudioFormat: Sendable {
    case pcmFloat32(sampleRate: Double, channels: UInt32)
    case pcmInt16(sampleRate: Double, channels: UInt32)
    case opus
    case mp3
    case aac
    
    /// Convert to AVAudioFormat if possible
    public var avAudioFormat: AVAudioFormat? {
        switch self {
        case .pcmFloat32(let sampleRate, let channels):
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: false
            )
        case .pcmInt16(let sampleRate, let channels):
            return AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: false
            )
        case .opus, .mp3, .aac:
            return nil // Requires decoding
        }
    }
}

// MARK: - TTS Metrics

/// Performance metrics for TTS service
public struct TTSMetrics: Sendable {
    /// Median time to first byte
    public var medianTTFB: TimeInterval
    
    /// 99th percentile TTFB
    public var p99TTFB: TimeInterval
    
    public init(medianTTFB: TimeInterval, p99TTFB: TimeInterval) {
        self.medianTTFB = medianTTFB
        self.p99TTFB = p99TTFB
    }
}

// MARK: - TTS Voice Options

/// Voice configuration for TTS
public struct TTSVoiceConfig: Sendable, Codable {
    /// Voice identifier
    public var voiceId: String
    
    /// Speaking rate (0.5 - 2.0, 1.0 is normal)
    public var rate: Float
    
    /// Pitch adjustment (-1.0 to 1.0, 0.0 is normal)
    public var pitch: Float
    
    /// Volume (0.0 - 1.0)
    public var volume: Float
    
    /// Stability (provider-specific)
    public var stability: Float?
    
    /// Similarity boost (provider-specific)
    public var similarityBoost: Float?
    
    public static let `default` = TTSVoiceConfig(
        voiceId: "default",
        rate: 1.0,
        pitch: 0.0,
        volume: 1.0
    )
    
    public init(
        voiceId: String = "default",
        rate: Float = 1.0,
        pitch: Float = 0.0,
        volume: Float = 1.0,
        stability: Float? = nil,
        similarityBoost: Float? = nil
    ) {
        self.voiceId = voiceId
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.stability = stability
        self.similarityBoost = similarityBoost
    }
}

// MARK: - TTS Service Protocol

/// Protocol for Text-to-Speech services
///
/// Implementations include:
/// - DeepgramTTS: Aura-2 streaming
/// - ElevenLabsTTS: Flash/Turbo streaming
/// - AppleTTS: On-device AVSpeechSynthesizer
public protocol TTSService: Actor {
    /// Performance metrics
    var metrics: TTSMetrics { get }
    
    /// Cost per character
    var costPerCharacter: Decimal { get }
    
    /// Current voice configuration
    var voiceConfig: TTSVoiceConfig { get }
    
    /// Configure voice settings
    func configure(_ config: TTSVoiceConfig) async
    
    /// Synthesize text to audio stream
    /// - Parameter text: Text to synthesize
    /// - Returns: AsyncStream of audio chunks
    func synthesize(text: String) async throws -> AsyncStream<TTSAudioChunk>
    
    /// Flush any pending audio and stop synthesis
    func flush() async throws
}

// MARK: - TTS Provider Enum

/// Available TTS provider implementations
public enum TTSProvider: String, Codable, Sendable, CaseIterable {
    case deepgramAura2 = "Deepgram Aura-2"
    case elevenLabsFlash = "ElevenLabs Flash"
    case elevenLabsTurbo = "ElevenLabs Turbo"
    case playHT = "PlayHT"
    case appleTTS = "Apple TTS (On-Device)"
    case selfHosted = "Self-Hosted (Piper)"
    case vibeVoice = "Self-Hosted (VibeVoice)"
    case chatterbox = "Chatterbox TTS"
    case kyutaiPocket = "Kyutai Pocket (On-Device)"

    /// Display name for UI
    public var displayName: String {
        rawValue
    }

    /// Short identifier
    public var identifier: String {
        switch self {
        case .deepgramAura2: return "deepgram"
        case .elevenLabsFlash: return "elevenlabs-flash"
        case .elevenLabsTurbo: return "elevenlabs-turbo"
        case .playHT: return "playht"
        case .appleTTS: return "apple"
        case .selfHosted: return "piper"
        case .vibeVoice: return "vibevoice"
        case .chatterbox: return "chatterbox"
        case .kyutaiPocket: return "kyutai-pocket"
        }
    }

    /// Whether this provider requires network connectivity
    public var requiresNetwork: Bool {
        switch self {
        case .appleTTS, .kyutaiPocket:
            return false
        case .selfHosted, .vibeVoice, .chatterbox:
            return true  // Requires local network to self-hosted server
        default:
            return true
        }
    }

    /// Whether this provider requires an API key
    public var requiresAPIKey: Bool {
        switch self {
        case .appleTTS, .selfHosted, .vibeVoice, .chatterbox, .kyutaiPocket:
            return false
        default:
            return true
        }
    }

    /// Default port for self-hosted providers
    public var defaultPort: Int {
        switch self {
        case .selfHosted: return 11402  // Piper
        case .vibeVoice: return 8880    // VibeVoice
        case .chatterbox: return 8004   // Chatterbox TTS Server
        default: return 0
        }
    }

    /// Default sample rate for this provider
    public var sampleRate: Double {
        switch self {
        case .selfHosted: return 22050  // Piper outputs 22050 Hz
        case .vibeVoice: return 24000   // VibeVoice outputs 24000 Hz
        case .chatterbox: return 24000  // Chatterbox outputs 24000 Hz
        case .kyutaiPocket: return 24000  // Kyutai Pocket outputs 24000 Hz
        default: return 24000
        }
    }

    /// Whether this is a self-hosted provider (runs on user's server)
    public var isSelfHosted: Bool {
        switch self {
        case .selfHosted, .vibeVoice, .chatterbox:
            return true
        default:
            return false
        }
    }

    /// Whether this is an on-device provider (runs locally without network)
    public var isOnDevice: Bool {
        switch self {
        case .appleTTS, .kyutaiPocket:
            return true
        default:
            return false
        }
    }

    /// Description for provider selection UI
    public var providerDescription: String {
        switch self {
        case .deepgramAura2:
            return "Cloud TTS with low latency streaming"
        case .elevenLabsFlash:
            return "High-quality cloud TTS with fast delivery"
        case .elevenLabsTurbo:
            return "Premium cloud TTS with natural voices"
        case .playHT:
            return "Cloud TTS with voice cloning"
        case .appleTTS:
            return "Built-in iOS TTS, works offline"
        case .selfHosted:
            return "Self-hosted Piper TTS server"
        case .vibeVoice:
            return "Self-hosted VibeVoice server"
        case .chatterbox:
            return "Self-hosted Chatterbox with emotion control"
        case .kyutaiPocket:
            return "On-device neural TTS, works offline, 8 voices"
        }
    }
}

// MARK: - TTS Errors

/// Errors that can occur during TTS processing
public enum TTSError: Error, Sendable {
    case synthesizeFailed(String)
    case invalidAudioFormat
    case bufferCreationFailed
    case connectionFailed(String)
    case authenticationFailed
    case rateLimited
    case quotaExceeded
    case voiceNotFound(String)
}

extension TTSError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .synthesizeFailed(let message):
            return "TTS synthesis failed: \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format from TTS"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .connectionFailed(let message):
            return "TTS connection failed: \(message)"
        case .authenticationFailed:
            return "TTS authentication failed"
        case .rateLimited:
            return "TTS rate limit exceeded"
        case .quotaExceeded:
            return "TTS quota exceeded"
        case .voiceNotFound(let voiceId):
            return "Voice not found: \(voiceId)"
        }
    }
}
