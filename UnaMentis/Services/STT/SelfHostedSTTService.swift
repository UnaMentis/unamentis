// UnaMentis - Self-Hosted STT Service
// OpenAI-compatible Speech-to-Text service for self-hosted Whisper servers
// Supports both HTTP batch transcription and WebSocket streaming
//
// Part of Services/STT

import Foundation
import Logging
import AVFoundation

/// Self-hosted STT service compatible with OpenAI Whisper API format
///
/// Works with:
/// - whisper.cpp server (WebSocket streaming at /ws)
/// - faster-whisper server (WebSocket at /ws/transcribe)
/// - UnaMentis gateway STT endpoint
/// - Any OpenAI-compatible transcription API
///
/// Streaming Protocol:
/// - Connect via WebSocket
/// - Send audio chunks as binary data
/// - Receive JSON transcription results
/// - Close connection to finalize
public actor SelfHostedSTTService: STTService {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.stt.selfhosted")
    private let baseURL: URL
    private let authToken: String?
    private let language: String
    private let modelHint: String?

    /// Performance metrics
    public private(set) var metrics = STTMetrics(
        medianLatency: 0.3,
        p99Latency: 0.6,
        wordEmissionRate: 0
    )

    /// Cost per hour (self-hosted = $0, only compute costs)
    public var costPerHour: Decimal { Decimal(0) }

    /// Whether currently streaming
    public private(set) var isStreaming: Bool = false

    // WebSocket state
    private var webSocketTask: URLSessionWebSocketTask?
    private var streamContinuation: AsyncStream<STTResult>.Continuation?
    private var streamStartTime: Date?
    private var latencyValues: [TimeInterval] = []

    // MARK: - Initialization

    /// Initialize with explicit configuration
    /// - Parameters:
    ///   - baseURL: Base URL of the server (e.g., http://localhost:11401)
    ///   - language: Language code (e.g., "en", "auto")
    ///   - modelHint: Optional model hint for the server
    ///   - authToken: Optional authentication token
    public init(
        baseURL: URL,
        language: String = "en",
        modelHint: String? = nil,
        authToken: String? = nil
    ) {
        self.baseURL = baseURL
        self.language = language
        self.modelHint = modelHint
        self.authToken = authToken
        logger.info("SelfHostedSTTService initialized: \(baseURL.absoluteString)")
    }

    /// Initialize from ServerConfig
    public init?(server: ServerConfig, language: String = "en") {
        guard let baseURL = server.baseURL else {
            return nil
        }
        self.baseURL = baseURL
        self.language = language
        self.modelHint = nil
        self.authToken = nil
        logger.info("SelfHostedSTTService initialized from server config: \(server.name)")
    }

    /// Initialize with auto-discovery
    public init?() async {
        let serverManager = ServerConfigManager.shared
        let healthyServers = await serverManager.getHealthySTTServers()

        guard let server = healthyServers.first,
              let baseURL = server.baseURL else {
            return nil
        }

        self.baseURL = baseURL
        self.language = "en"
        self.modelHint = nil
        self.authToken = nil
    }

    // MARK: - STTService Protocol

    /// Transcribe audio data to text
    public func transcribe(audioData: Data) async throws -> TranscriptionResult {
        let startTime = Date()

        // Build URL for transcription endpoint
        let transcribeURL = baseURL.appendingPathComponent("v1/audio/transcriptions")

        // Create multipart form request
        let boundary = UUID().uuidString
        var request = URLRequest(url: transcribeURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build multipart body
        var body = Data()

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Add model hint if provided
        if let model = modelHint {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model)\r\n".data(using: .utf8)!)
        }

        // Add language
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(language)\r\n".data(using: .utf8)!)

        // Add response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw STTError.connectionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw STTError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw STTError.connectionFailed("Invalid JSON response")
        }

        let text = json["text"] as? String ?? ""
        let duration = json["duration"] as? Double ?? 0

        // Parse word-level timestamps if available
        var words: [TranscribedWord] = []
        if let segments = json["segments"] as? [[String: Any]] {
            for segment in segments {
                if let segmentWords = segment["words"] as? [[String: Any]] {
                    for wordInfo in segmentWords {
                        if let word = wordInfo["word"] as? String,
                           let start = wordInfo["start"] as? Double,
                           let end = wordInfo["end"] as? Double {
                            words.append(TranscribedWord(
                                word: word.trimmingCharacters(in: .whitespaces),
                                startTime: start,
                                endTime: end,
                                confidence: wordInfo["probability"] as? Float ?? 0.9
                            ))
                        }
                    }
                }
            }
        }

        // Calculate latency
        let latency = Date().timeIntervalSince(startTime)
        latencyValues.append(latency)
        updateMetrics()

        logger.debug("Transcription complete: \(text.prefix(50))... (latency: \(String(format: "%.3f", latency))s)")

        return TranscriptionResult(
            text: text,
            words: words,
            language: json["language"] as? String ?? language,
            duration: duration,
            isFinal: true
        )
    }

    // MARK: - STTService Protocol (Streaming)

    /// Start streaming transcription via WebSocket
    public func startStreaming(audioFormat: sending AVAudioFormat) async throws -> AsyncStream<STTResult> {
        guard !isStreaming else { throw STTError.alreadyStreaming }

        logger.info("Starting WebSocket stream with format: \(audioFormat.sampleRate)Hz")

        // Build WebSocket URL
        // Common endpoints: /ws, /ws/transcribe, /v1/audio/transcriptions/stream
        let wsURL = buildWebSocketURL(audioFormat: audioFormat)

        var request = URLRequest(url: wsURL)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)

        webSocketTask?.resume()
        isStreaming = true
        streamStartTime = Date()

        return AsyncStream { continuation in
            self.streamContinuation = continuation

            // Start listening for messages
            Task {
                await self.listenForMessages()
            }

            // Handle stream termination
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    try? await self?.stopStreaming()
                }
            }
        }
    }

    /// Send audio data for transcription
    public func sendAudio(_ buffer: sending AVAudioPCMBuffer) async throws {
        guard isStreaming, let ws = webSocketTask else {
            throw STTError.notStreaming
        }

        // Convert to PCM Int16 data (common format for Whisper servers)
        guard let data = buffer.toPCMInt16Data() else {
            throw STTError.invalidAudioFormat
        }

        let message = URLSessionWebSocketTask.Message.data(data)
        try await ws.send(message)
    }

    /// Stop streaming and finalize transcription
    public func stopStreaming() async throws {
        guard isStreaming else { return }

        logger.info("Stopping WebSocket stream")

        // Send end-of-stream signal (empty data or close frame)
        if let ws = webSocketTask {
            // Some servers expect an empty data frame to signal end
            try? await ws.send(.data(Data()))

            // Close WebSocket connection
            ws.cancel(with: .normalClosure, reason: nil)
        }

        webSocketTask = nil
        streamContinuation?.finish()
        streamContinuation = nil
        isStreaming = false
    }

    /// Cancel streaming without finalizing
    public func cancelStreaming() async {
        webSocketTask?.cancel()
        webSocketTask = nil
        streamContinuation?.finish()
        streamContinuation = nil
        isStreaming = false
    }

    // MARK: - WebSocket Message Handling

    private func listenForMessages() async {
        guard let ws = webSocketTask else { return }

        do {
            let message = try await ws.receive()

            if isStreaming {
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }

                // Continue listening (recursive call)
                await listenForMessages()
            }
        } catch {
            // Connection closed or error
            if isStreaming {
                logger.warning("WebSocket receive failed: \(error.localizedDescription)")
                await cancelStreaming()
            }
        }
    }

    private func handleMessage(_ jsonString: String) async {
        guard let data = jsonString.data(using: .utf8) else { return }

        // Calculate latency from stream start
        let latency: TimeInterval
        if let start = streamStartTime {
            latency = Date().timeIntervalSince(start)
            latencyValues.append(latency)
            updateMetrics()
        } else {
            latency = 0
        }

        do {
            // Try to parse as generic Whisper response
            // Different servers have different formats, so we try multiple
            if let result = try parseWhisperResponse(data, latency: latency) {
                streamContinuation?.yield(result)
            }
        } catch {
            logger.warning("Failed to parse streaming response: \(error.localizedDescription)")
        }
    }

    /// Parse various Whisper server response formats
    private func parseWhisperResponse(_ data: Data, latency: TimeInterval) throws -> STTResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Format 1: OpenAI-style { "text": "...", "is_final": true }
        if let text = json["text"] as? String {
            let isFinal = json["is_final"] as? Bool ?? json["isFinal"] as? Bool ?? true
            return STTResult(
                transcript: text,
                isFinal: isFinal,
                isEndOfUtterance: isFinal,
                confidence: Float(json["confidence"] as? Double ?? 0.9),
                timestamp: Date().timeIntervalSince1970,
                latency: latency,
                wordTimestamps: nil
            )
        }

        // Format 2: whisper.cpp streaming { "result": { "text": "..." } }
        if let result = json["result"] as? [String: Any],
           let text = result["text"] as? String {
            let isFinal = json["is_final"] as? Bool ?? true
            return STTResult(
                transcript: text,
                isFinal: isFinal,
                isEndOfUtterance: isFinal,
                confidence: 0.9,
                timestamp: Date().timeIntervalSince1970,
                latency: latency,
                wordTimestamps: nil
            )
        }

        // Format 3: faster-whisper { "transcript": "...", "partial": false }
        if let text = json["transcript"] as? String {
            let isPartial = json["partial"] as? Bool ?? false
            return STTResult(
                transcript: text,
                isFinal: !isPartial,
                isEndOfUtterance: !isPartial,
                confidence: Float(json["confidence"] as? Double ?? 0.9),
                timestamp: Date().timeIntervalSince1970,
                latency: latency,
                wordTimestamps: nil
            )
        }

        return nil
    }

    /// Build WebSocket URL with query parameters
    private func buildWebSocketURL(audioFormat: AVAudioFormat) -> URL {
        // Convert HTTP URL to WebSocket URL
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!

        // Change scheme to WebSocket
        if components.scheme == "http" {
            components.scheme = "ws"
        } else if components.scheme == "https" {
            components.scheme = "wss"
        }

        // Add streaming path if not present
        if components.path.isEmpty || components.path == "/" {
            components.path = "/ws"
        } else if !components.path.contains("ws") {
            components.path += "/ws"
        }

        // Add query parameters for audio configuration
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "language", value: language))
        queryItems.append(URLQueryItem(name: "encoding", value: "linear16"))
        queryItems.append(URLQueryItem(name: "sample_rate", value: String(Int(audioFormat.sampleRate))))
        queryItems.append(URLQueryItem(name: "channels", value: String(audioFormat.channelCount)))

        if let model = modelHint {
            queryItems.append(URLQueryItem(name: "model", value: model))
        }

        components.queryItems = queryItems

        return components.url!
    }

    // MARK: - Legacy Streaming (Deprecated)

    /// Start streaming transcription (legacy method, use startStreaming instead)
    @available(*, deprecated, message: "Use startStreaming(audioFormat:) instead")
    public func startStreamingTranscription() async throws -> AsyncStream<TranscriptionResult> {
        throw STTError.connectionFailed("Use startStreaming(audioFormat:) for WebSocket streaming")
    }

    // MARK: - Health Check

    /// Check if the server is healthy
    public func checkHealth() async -> Bool {
        let healthURL = baseURL.appendingPathComponent("health")

        do {
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            logger.warning("Health check failed: \(error.localizedDescription)")
        }

        return false
    }

    // MARK: - Private Methods

    private func updateMetrics() {
        let avgLatency = latencyValues.isEmpty ? 0.3 : latencyValues.reduce(0, +) / Double(latencyValues.count)

        metrics = STTMetrics(
            averageLatency: avgLatency,
            wordErrorRate: 0.05  // Estimated, would need ground truth to calculate
        )
    }
}

// MARK: - Factory

extension SelfHostedSTTService {

    /// Create a service connected to local Whisper server
    public static func whisper(
        host: String = "localhost",
        port: Int = 11401,
        language: String = "en"
    ) -> SelfHostedSTTService {
        let url = URL(string: "http://\(host):\(port)")!
        return SelfHostedSTTService(baseURL: url, language: language)
    }

    /// Create a service connected to UnaMentis gateway
    public static func voicelearnGateway(
        host: String = "localhost",
        port: Int = 11400,
        language: String = "en"
    ) -> SelfHostedSTTService {
        let url = URL(string: "http://\(host):\(port)")!
        return SelfHostedSTTService(baseURL: url, language: language)
    }

    /// Create a service from auto-discovered server
    public static func autoDiscover() async -> SelfHostedSTTService? {
        await SelfHostedSTTService()
    }
}

// MARK: - Supporting Types

// Note: TranscriptionResult, TranscribedWord, STTMetrics, and STTError are defined in STTService.swift

/// Legacy STT metrics (kept for compatibility)
struct SelfHostedSTTMetrics: Sendable {
    let averageLatency: TimeInterval
    let wordErrorRate: Double
}

/// Self-hosted specific errors
enum SelfHostedSTTError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case invalidAudioFormat
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message): return "Connection failed: \(message)"
        case .authenticationFailed: return "Authentication failed"
        case .invalidAudioFormat: return "Invalid audio format"
        case .serverError(let message): return "Server error: \(message)"
        }
    }
}
