// VoiceLearn - GLM-ASR-Nano STT Service
// Streaming Speech-to-Text using GLM-ASR-Nano via WebSocket
//
// Self-hosted STT service with zero per-hour cost
// Designed for 16kHz mono PCM audio input
//
// Related: docs/GLM_ASR_SERVER_TRD.md

import Foundation
import AVFoundation
import Logging

/// GLM-ASR-Nano streaming STT service via WebSocket
///
/// This service connects to a self-hosted GLM-ASR-Nano server for speech-to-text.
/// Features:
/// - Zero cost per hour (self-hosted)
/// - Low latency streaming transcription
/// - Automatic reconnection with exponential backoff
/// - Word-level timestamps support
public actor GLMASRSTTService: STTService {

    // MARK: - Configuration

    /// Configuration for GLM-ASR service
    public struct Configuration: Sendable {
        public let serverURL: URL
        public let authToken: String?
        public let language: String
        public let interimResults: Bool
        public let punctuate: Bool
        public let reconnectAttempts: Int
        public let reconnectDelayMs: Int

        public init(
            serverURL: URL,
            authToken: String?,
            language: String,
            interimResults: Bool,
            punctuate: Bool,
            reconnectAttempts: Int,
            reconnectDelayMs: Int
        ) {
            self.serverURL = serverURL
            self.authToken = authToken
            self.language = language
            self.interimResults = interimResults
            self.punctuate = punctuate
            self.reconnectAttempts = reconnectAttempts
            self.reconnectDelayMs = reconnectDelayMs
        }

        /// Default configuration (requires setting serverURL via environment or settings)
        public static let `default` = Configuration(
            serverURL: URL(string: ProcessInfo.processInfo.environment["GLM_ASR_SERVER_URL"]
                ?? "wss://localhost:8080/v1/audio/stream")!,
            authToken: ProcessInfo.processInfo.environment["GLM_ASR_AUTH_TOKEN"],
            language: "auto",
            interimResults: true,
            punctuate: true,
            reconnectAttempts: 3,
            reconnectDelayMs: 1000
        )
    }

    // MARK: - Properties

    private let logger = Logger(label: "com.voicelearn.stt.glmasr")
    private let configuration: Configuration
    private let telemetry: TelemetryEngine

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var resultContinuation: AsyncStream<STTResult>.Continuation?
    private var sessionStartTime: Date?
    private var audioBytesSent: Int = 0
    private var latencyMeasurements: [TimeInterval] = []

    /// Performance metrics
    public private(set) var metrics = STTMetrics(
        medianLatency: 0.15,  // Target: 150ms
        p99Latency: 0.35,     // Target: 350ms
        wordEmissionRate: 0
    )

    /// Cost per hour (self-hosted = $0)
    public var costPerHour: Decimal { Decimal(0) }

    /// Whether currently streaming
    public private(set) var isStreaming: Bool = false

    // MARK: - Initialization

    /// Initialize GLM-ASR STT service
    /// - Parameters:
    ///   - configuration: Service configuration
    ///   - telemetry: Telemetry engine for event tracking
    public init(
        configuration: Configuration = .default,
        telemetry: TelemetryEngine
    ) {
        self.configuration = configuration
        self.telemetry = telemetry
        self.urlSession = URLSession(configuration: .default)
        logger.info("GLMASRSTTService initialized with server: \(configuration.serverURL)")
    }

    // MARK: - STTService Protocol

    /// Start streaming transcription
    /// - Parameter audioFormat: Audio format (must be 16kHz mono)
    /// - Returns: AsyncStream of STT results
    public func startStreaming(audioFormat: AVAudioFormat) async throws -> AsyncStream<STTResult> {
        guard !isStreaming else {
            throw STTError.alreadyStreaming
        }

        // Validate audio format - GLM-ASR requires 16kHz mono
        guard audioFormat.sampleRate == 16000,
              audioFormat.channelCount == 1 else {
            throw STTError.invalidAudioFormat
        }

        logger.info("Starting GLM-ASR stream")

        // Build WebSocket URL with auth if provided
        var request = URLRequest(url: configuration.serverURL)
        if let token = configuration.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        webSocket = urlSession.webSocketTask(with: request)
        webSocket?.resume()

        // Send start configuration message
        let startMessage = StartMessage(
            type: "start",
            config: .init(
                language: configuration.language,
                interimResults: configuration.interimResults,
                punctuate: configuration.punctuate
            )
        )
        try await sendJSON(startMessage)

        isStreaming = true
        sessionStartTime = Date()
        audioBytesSent = 0
        latencyMeasurements = []

        await telemetry.recordEvent(.audioEngineStarted)

        return AsyncStream { continuation in
            self.resultContinuation = continuation

            Task {
                await self.receiveLoop()
            }

            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.cleanup()
                }
            }
        }
    }

    /// Send audio buffer for transcription
    /// - Parameter buffer: Audio buffer to transcribe
    public func sendAudio(_ buffer: AVAudioPCMBuffer) async throws {
        guard isStreaming, let ws = webSocket else {
            throw STTError.notStreaming
        }

        // Convert Float32 to Int16 PCM
        guard let data = buffer.toGLMASRPCMData() else {
            throw STTError.invalidAudioFormat
        }

        do {
            try await ws.send(.data(data))
            audioBytesSent += data.count
        } catch {
            logger.error("Failed to send audio: \(error)")
            throw STTError.streamingFailed(error.localizedDescription)
        }
    }

    /// Stop streaming and get final result
    public func stopStreaming() async throws {
        guard isStreaming else { return }

        logger.info("Stopping GLM-ASR stream")

        // Send end message
        try? await sendJSON(EndMessage(type: "end"))

        // Wait briefly for final results
        try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

        await cleanup()
        await recordSessionMetrics()
    }

    /// Cancel streaming without finalizing
    public func cancelStreaming() async {
        await cleanup()
    }

    // MARK: - Private Methods

    private func receiveLoop() async {
        guard let ws = webSocket else { return }

        while isStreaming {
            do {
                let message = try await ws.receive()

                switch message {
                case .string(let text):
                    await handleTextMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleTextMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if isStreaming {
                    logger.error("WebSocket receive failed: \(error)")
                    await handleConnectionError(error)
                }
                break
            }
        }
    }

    private func handleTextMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "partial":
            if let result = parseTranscriptionResult(json, isFinal: false) {
                resultContinuation?.yield(result)
                recordLatency(result.latency)
            }

        case "final":
            if let result = parseTranscriptionResult(json, isFinal: true) {
                resultContinuation?.yield(result)
                recordLatency(result.latency)
            }

        case "error":
            await handleServerError(json)

        case "pong":
            // Keepalive acknowledged
            break

        default:
            logger.warning("Unknown message type: \(type)")
        }
    }

    private func parseTranscriptionResult(
        _ json: [String: Any],
        isFinal: Bool
    ) -> STTResult? {
        guard let text = json["text"] as? String else { return nil }

        let confidence = json["confidence"] as? Float ?? 0.0
        let timestampMs = json["timestamp_ms"] as? Int ?? 0
        let isEndOfUtterance = json["is_end_of_utterance"] as? Bool ?? isFinal

        // Parse word timestamps if available
        var words: [WordTimestamp]?
        if let wordArray = json["words"] as? [[String: Any]] {
            words = wordArray.compactMap { wordJson in
                guard let word = wordJson["word"] as? String,
                      let start = wordJson["start"] as? Double,
                      let end = wordJson["end"] as? Double else {
                    return nil
                }
                return WordTimestamp(
                    word: word,
                    startTime: start,
                    endTime: end,
                    confidence: wordJson["confidence"] as? Float
                )
            }
        }

        // Calculate latency
        let latency: TimeInterval
        if let startTime = sessionStartTime {
            latency = Date().timeIntervalSince(startTime) - (Double(timestampMs) / 1000.0)
        } else {
            latency = 0
        }

        return STTResult(
            transcript: text,
            isFinal: isFinal,
            isEndOfUtterance: isEndOfUtterance,
            confidence: confidence,
            latency: max(0, latency),
            wordTimestamps: words
        )
    }

    private func handleServerError(_ json: [String: Any]) async {
        let code = json["code"] as? String ?? "UNKNOWN"
        let message = json["message"] as? String ?? "Unknown error"
        let recoverable = json["recoverable"] as? Bool ?? false

        logger.error("GLM-ASR server error: \(code) - \(message)")

        if !recoverable {
            await cleanup()
        }
    }

    private func handleConnectionError(_ error: Error) async {
        logger.error("GLM-ASR connection error: \(error)")

        // Attempt reconnection if configured
        if configuration.reconnectAttempts > 0 {
            await attemptReconnection()
        } else {
            await cleanup()
        }
    }

    private func attemptReconnection() async {
        for attempt in 1...configuration.reconnectAttempts {
            let delay = configuration.reconnectDelayMs * attempt
            logger.info("Reconnection attempt \(attempt)/\(configuration.reconnectAttempts) in \(delay)ms")

            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)

            do {
                var request = URLRequest(url: configuration.serverURL)
                if let token = configuration.authToken {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                webSocket = urlSession.webSocketTask(with: request)
                webSocket?.resume()

                // Re-send start message
                let startMessage = StartMessage(
                    type: "start",
                    config: .init(
                        language: configuration.language,
                        interimResults: configuration.interimResults,
                        punctuate: configuration.punctuate
                    )
                )
                try await sendJSON(startMessage)

                logger.info("Reconnected successfully on attempt \(attempt)")

                // Resume receive loop
                Task {
                    await self.receiveLoop()
                }

                return
            } catch {
                logger.warning("Reconnection attempt \(attempt) failed: \(error)")
                continue
            }
        }

        logger.error("All reconnection attempts failed")
        await cleanup()
    }

    private func cleanup() async {
        isStreaming = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        resultContinuation?.finish()
        resultContinuation = nil
    }

    private func recordLatency(_ latency: TimeInterval) {
        latencyMeasurements.append(latency)
    }

    private func recordSessionMetrics() async {
        guard let startTime = sessionStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)

        // Calculate median and p99 latency
        let sortedLatencies = latencyMeasurements.sorted()
        let medianLatency: TimeInterval
        let p99Latency: TimeInterval

        if sortedLatencies.isEmpty {
            medianLatency = 0.15  // Default
            p99Latency = 0.35
        } else {
            let medianIndex = sortedLatencies.count / 2
            medianLatency = sortedLatencies[medianIndex]

            let p99Index = min(Int(Double(sortedLatencies.count) * 0.99), sortedLatencies.count - 1)
            p99Latency = sortedLatencies[p99Index]
        }

        metrics = STTMetrics(
            medianLatency: medianLatency,
            p99Latency: p99Latency,
            wordEmissionRate: 0  // TODO: Calculate from results
        )

        logger.info("Session completed: duration=\(duration)s, median_latency=\(medianLatency)s")
    }

    private func sendJSON<T: Encodable>(_ value: T) async throws {
        guard let ws = webSocket else { return }
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else { return }
        try await ws.send(.string(string))
    }
}

// MARK: - Message Types

extension GLMASRSTTService {
    struct StartMessage: Encodable {
        let type: String
        let config: Config

        struct Config: Encodable {
            let language: String
            let interimResults: Bool
            let punctuate: Bool

            enum CodingKeys: String, CodingKey {
                case language
                case interimResults = "interim_results"
                case punctuate
            }
        }
    }

    struct EndMessage: Encodable {
        let type: String
    }
}

// MARK: - Message Parser

/// Parser for GLM-ASR WebSocket messages
public enum GLMASRMessageParser {

    /// Parsed transcription result
    public struct ParsedResult {
        public let text: String
        public let isFinal: Bool
        public let isEndOfUtterance: Bool
        public let confidence: Float
        public let words: [ParsedWord]?
    }

    /// Parsed word with timing
    public struct ParsedWord {
        public let word: String
        public let start: Double
        public let end: Double
        public let confidence: Float
    }

    /// Parsed error message
    public struct ParsedError {
        public let code: String
        public let message: String
        public let recoverable: Bool
    }

    /// Parse transcription result from JSON string
    public static func parseTranscriptionResult(_ jsonString: String) -> ParsedResult? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            return nil
        }

        let type = json["type"] as? String ?? ""
        let isFinal = type == "final"
        let confidence = (json["confidence"] as? Double).map { Float($0) } ?? 0.0
        let isEndOfUtterance = json["is_end_of_utterance"] as? Bool ?? isFinal

        var words: [ParsedWord]?
        if let wordArray = json["words"] as? [[String: Any]] {
            words = wordArray.compactMap { wordJson in
                guard let word = wordJson["word"] as? String,
                      let start = wordJson["start"] as? Double,
                      let end = wordJson["end"] as? Double else {
                    return nil
                }
                return ParsedWord(
                    word: word,
                    start: start,
                    end: end,
                    confidence: (wordJson["confidence"] as? Double).map { Float($0) } ?? 0.0
                )
            }
        }

        return ParsedResult(
            text: text,
            isFinal: isFinal,
            isEndOfUtterance: isEndOfUtterance,
            confidence: confidence,
            words: words
        )
    }

    /// Parse error message from JSON string
    public static func parseErrorMessage(_ jsonString: String) -> ParsedError? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "error" else {
            return nil
        }

        let code = json["code"] as? String ?? "UNKNOWN"
        let message = json["message"] as? String ?? "Unknown error"
        let recoverable = json["recoverable"] as? Bool ?? false

        return ParsedError(code: code, message: message, recoverable: recoverable)
    }
}

// MARK: - Audio Buffer Extension

extension AVAudioPCMBuffer {
    /// Convert Float32 audio buffer to Int16 PCM data for GLM-ASR
    ///
    /// GLM-ASR expects:
    /// - 16-bit signed integer, little-endian
    /// - 16kHz sample rate
    /// - Mono channel
    func toGLMASRPCMData() -> Data? {
        guard let floatData = floatChannelData?[0] else { return nil }

        let frameCount = Int(frameLength)
        var int16Samples = [Int16](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            // Clamp to [-1.0, 1.0] and convert to Int16 range
            let sample = max(-1.0, min(1.0, floatData[i]))
            int16Samples[i] = Int16(sample * Float(Int16.max))
        }

        return int16Samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}
