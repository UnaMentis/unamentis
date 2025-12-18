// VoiceLearn - TTS Service Protocol
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
            throw TTSError.invalidAudioFormat
        }
        
        let frameCount = UInt32(audioData.count) / audioFormat.streamDescription.pointee.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            throw TTSError.bufferCreationFailed
        }
        
        buffer.frameLength = frameCount
        audioData.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(buffer.floatChannelData?[0], baseAddress, audioData.count)
            }
        }
        
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
        }
    }

    /// Whether this provider requires network connectivity
    public var requiresNetwork: Bool {
        switch self {
        case .appleTTS:
            return false
        case .selfHosted:
            return true  // Requires local network to self-hosted server
        default:
            return true
        }
    }

    /// Whether this provider requires an API key
    public var requiresAPIKey: Bool {
        switch self {
        case .appleTTS, .selfHosted:
            return false
        default:
            return true
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
