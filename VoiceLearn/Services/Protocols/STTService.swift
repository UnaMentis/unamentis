// VoiceLearn - STT Service Protocol
// Protocol defining Speech-to-Text interface
//
// Part of the Provider Abstraction Layer (TDD Section 6)

import AVFoundation

// MARK: - STT Result

/// Result from Speech-to-Text processing
public struct STTResult: Sendable {
    /// Transcribed text
    public let transcript: String
    
    /// Whether this is a final result (vs partial/interim)
    public let isFinal: Bool
    
    /// Whether this marks the end of an utterance
    public let isEndOfUtterance: Bool
    
    /// Confidence score (0.0 - 1.0)
    public let confidence: Float
    
    /// Timestamp when the result was received
    public let timestamp: TimeInterval
    
    /// Latency from audio to result in seconds
    public let latency: TimeInterval
    
    /// Word-level timestamps if available
    public let wordTimestamps: [WordTimestamp]?
    
    public init(
        transcript: String,
        isFinal: Bool,
        isEndOfUtterance: Bool,
        confidence: Float,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        latency: TimeInterval = 0,
        wordTimestamps: [WordTimestamp]? = nil
    ) {
        self.transcript = transcript
        self.isFinal = isFinal
        self.isEndOfUtterance = isEndOfUtterance
        self.confidence = confidence
        self.timestamp = timestamp
        self.latency = latency
        self.wordTimestamps = wordTimestamps
    }
}

/// Word-level timestamp information
public struct WordTimestamp: Sendable, Codable {
    public let word: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float?
    
    public init(word: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float? = nil) {
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

// MARK: - STT Metrics

/// Performance metrics for STT service
public struct STTMetrics: Sendable {
    /// Median latency from audio to transcript
    public var medianLatency: TimeInterval
    
    /// 99th percentile latency
    public var p99Latency: TimeInterval
    
    /// Words emitted per second
    public var wordEmissionRate: Double
    
    public init(medianLatency: TimeInterval, p99Latency: TimeInterval, wordEmissionRate: Double) {
        self.medianLatency = medianLatency
        self.p99Latency = p99Latency
        self.wordEmissionRate = wordEmissionRate
    }
}

// MARK: - STT Service Protocol

/// Protocol for Speech-to-Text services
///
/// Implementations include:
/// - AssemblyAISTT: WebSocket streaming with Universal-Streaming
/// - DeepgramSTT: Nova-3 streaming
/// - AppleSTT: On-device Speech framework
public protocol STTService: Actor {
    /// Performance metrics
    var metrics: STTMetrics { get }
    
    /// Cost per hour of audio processing
    var costPerHour: Decimal { get }
    
    /// Whether currently streaming
    var isStreaming: Bool { get }
    
    /// Start streaming transcription
    /// - Parameter audioFormat: Format of audio that will be sent
    /// - Returns: AsyncStream of STT results
    func startStreaming(audioFormat: AVAudioFormat) async throws -> AsyncStream<STTResult>
    
    /// Send audio data for transcription
    /// - Parameter buffer: Audio buffer to transcribe
    func sendAudio(_ buffer: AVAudioPCMBuffer) async throws
    
    /// Stop streaming and finalize
    func stopStreaming() async throws
    
    /// Cancel streaming without finalizing
    func cancelStreaming() async
}

// MARK: - STT Provider Enum

/// Available STT provider implementations
public enum STTProvider: String, Codable, Sendable, CaseIterable {
    case assemblyAI = "AssemblyAI Universal-Streaming"
    case deepgramNova3 = "Deepgram Nova-3"
    case openAIWhisper = "OpenAI Whisper"
    case appleSpeech = "Apple Speech (On-Device)"
    case glmASRNano = "GLM-ASR-Nano (Self-Hosted)"

    /// Display name for UI
    public var displayName: String {
        rawValue
    }

    /// Short identifier
    public var identifier: String {
        switch self {
        case .assemblyAI: return "assemblyai"
        case .deepgramNova3: return "deepgram"
        case .openAIWhisper: return "whisper"
        case .appleSpeech: return "apple"
        case .glmASRNano: return "glm-asr"
        }
    }

    /// Whether this provider requires network connectivity
    public var requiresNetwork: Bool {
        switch self {
        case .appleSpeech:
            return false
        default:
            return true
        }
    }

    /// Cost per hour for this provider
    public var costPerHour: Decimal {
        switch self {
        case .assemblyAI: return Decimal(string: "0.37")!    // $0.37/hour
        case .deepgramNova3: return Decimal(string: "0.258")! // $0.258/hour
        case .openAIWhisper: return Decimal(string: "0.36")!  // $0.006/min
        case .appleSpeech: return 0                           // Free (on-device)
        case .glmASRNano: return 0                            // Self-hosted
        }
    }

    /// Whether this provider is self-hosted
    public var isSelfHosted: Bool {
        self == .glmASRNano
    }
}

// MARK: - STT Errors

/// Errors that can occur during STT processing
public enum STTError: Error, Sendable {
    case connectionFailed(String)
    case streamingFailed(String)
    case invalidAudioFormat
    case notStreaming
    case alreadyStreaming
    case authenticationFailed
    case rateLimited
    case quotaExceeded
}

extension STTError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "STT connection failed: \(message)"
        case .streamingFailed(let message):
            return "STT streaming failed: \(message)"
        case .invalidAudioFormat:
            return "Invalid audio format for STT processing"
        case .notStreaming:
            return "Not currently streaming"
        case .alreadyStreaming:
            return "Already streaming"
        case .authenticationFailed:
            return "STT authentication failed"
        case .rateLimited:
            return "STT rate limit exceeded"
        case .quotaExceeded:
            return "STT quota exceeded"
        }
    }
}
