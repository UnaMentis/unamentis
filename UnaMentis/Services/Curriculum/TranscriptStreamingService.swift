// UnaMentis - Transcript Streaming Service
// Direct streaming of transcript audio from server (bypasses LLM for pre-written content)
//
// Part of Services/Curriculum

import Foundation
import Logging
import AVFoundation

/// Service for streaming pre-written transcript audio directly from the server.
/// This bypasses the LLM entirely, enabling near-instant audio playback.
public actor TranscriptStreamingService {

    // MARK: - Types

    /// TTS Server options
    public enum TTSServer: String {
        case vibeVoice = "vibevoice"  // Port 8880, 24kHz
        case piper = "piper"          // Port 11402, 22050Hz

        var port: Int {
            switch self {
            case .vibeVoice: return 8880
            case .piper: return 11402
            }
        }
    }

    /// A segment of transcript with its audio data
    public struct TranscriptSegment {
        public let index: Int
        public let type: String
        public let textLength: Int
        public let audioData: Data
    }

    /// Delegate for receiving streaming events
    public protocol Delegate: AnyObject, Sendable {
        func transcriptStreaming(didReceiveSegment segment: TranscriptSegment)
        func transcriptStreaming(didReceiveText text: String, forSegment index: Int)
        func transcriptStreamingDidComplete()
        func transcriptStreaming(didEncounterError error: Error)
    }

    /// Errors specific to transcript streaming
    public enum StreamingError: Error, LocalizedError {
        case serverNotConfigured
        case topicNotFound
        case noTranscript
        case networkError(String)
        case parsingError(String)
        case ttsError(statusCode: Int, message: String)
        case allTTSServersFailed

        public var errorDescription: String? {
            switch self {
            case .serverNotConfigured:
                return "Server not configured"
            case .topicNotFound:
                return "Topic not found on server"
            case .noTranscript:
                return "Topic has no transcript"
            case .networkError(let msg):
                return "Network error: \(msg)"
            case .parsingError(let msg):
                return "Parsing error: \(msg)"
            case .ttsError(let statusCode, let message):
                return "TTS error (HTTP \(statusCode)): \(message)"
            case .allTTSServersFailed:
                return "All TTS servers failed to generate audio"
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.transcript.streaming")
    private var serverHost: String?
    private var serverPort: Int = 8766
    private var currentTask: Task<Void, Never>?

    /// Preferred TTS server order (will try in order, falling back if one fails)
    private var ttsServerOrder: [TTSServer] = [.piper, .vibeVoice]

    // Audio player for playback
    private var audioPlayer: AVAudioPlayer?
    private var audioQueue: [Data] = []
    private var isPlaying = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Configuration

    /// Configure the server connection
    public func configure(host: String, port: Int = 8766) {
        self.serverHost = host
        self.serverPort = port
        logger.info("TranscriptStreamingService configured: \(host):\(port)")
    }

    /// Set preferred TTS server
    public func setPreferredTTS(_ server: TTSServer) {
        if server == .piper {
            ttsServerOrder = [.piper, .vibeVoice]
        } else {
            ttsServerOrder = [.vibeVoice, .piper]
        }
        logger.info("TTS server preference: \(ttsServerOrder.map { $0.rawValue })")
    }

    // MARK: - Streaming

    /// Start streaming transcript audio for a topic
    /// - Parameters:
    ///   - curriculumId: The curriculum ID
    ///   - topicId: The topic ID
    ///   - voice: TTS voice to use (default: "nova")
    ///   - onSegmentText: Called when segment text is received (for display)
    ///   - onSegmentAudio: Called when segment audio is ready to play
    ///   - onComplete: Called when streaming is complete
    ///   - onError: Called if an error occurs
    public func streamTopicAudio(
        curriculumId: String,
        topicId: String,
        voice: String = "nova",
        onSegmentText: @escaping @Sendable (Int, String, String) -> Void,  // index, type, text
        onSegmentAudio: @escaping @Sendable (Int, Data) -> Void,  // index, audioData
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        // Cancel any existing stream
        currentTask?.cancel()

        currentTask = Task {
            do {
                try await performStreaming(
                    curriculumId: curriculumId,
                    topicId: topicId,
                    voice: voice,
                    onSegmentText: onSegmentText,
                    onSegmentAudio: onSegmentAudio,
                    onComplete: onComplete,
                    onError: onError
                )
            } catch {
                if !Task.isCancelled {
                    logger.error("Streaming failed with error: \(error.localizedDescription)")
                    onError(error)
                }
            }
        }
    }

    /// Stop any active streaming
    public func stopStreaming() {
        currentTask?.cancel()
        currentTask = nil
        audioQueue.removeAll()
        isPlaying = false
        logger.info("Streaming stopped")
    }

    // MARK: - Private Methods

    private func performStreaming(
        curriculumId: String,
        topicId: String,
        voice: String,
        onSegmentText: @escaping @Sendable (Int, String, String) -> Void,
        onSegmentAudio: @escaping @Sendable (Int, Data) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        guard let host = serverHost else {
            throw StreamingError.serverNotConfigured
        }

        // First, fetch the transcript segments to get the text
        let transcriptURL = URL(string: "http://\(host):\(serverPort)/api/curricula/\(curriculumId)/topics/\(topicId)/transcript")!

        logger.info("Fetching transcript from: \(transcriptURL)")

        let (transcriptData, transcriptResponse) = try await URLSession.shared.data(from: transcriptURL)

        guard let httpResponse = transcriptResponse as? HTTPURLResponse else {
            throw StreamingError.networkError("Invalid response")
        }

        logger.info("Transcript fetch response: HTTP \(httpResponse.statusCode)")

        if httpResponse.statusCode == 404 {
            throw StreamingError.topicNotFound
        }

        guard httpResponse.statusCode == 200 else {
            let bodyText = String(data: transcriptData, encoding: .utf8) ?? "unknown"
            logger.error("Transcript fetch failed: HTTP \(httpResponse.statusCode) - \(bodyText)")
            throw StreamingError.networkError("HTTP \(httpResponse.statusCode)")
        }

        // Parse transcript
        guard let transcriptJSON = try? JSONSerialization.jsonObject(with: transcriptData) as? [String: Any],
              let segments = transcriptJSON["segments"] as? [[String: Any]] else {
            let bodyText = String(data: transcriptData, encoding: .utf8) ?? "unknown"
            logger.error("Failed to parse transcript JSON: \(bodyText.prefix(500))")
            throw StreamingError.parsingError("Failed to parse transcript")
        }

        if segments.isEmpty {
            throw StreamingError.noTranscript
        }

        logger.info("Got \(segments.count) transcript segments, starting audio streaming")

        var successfulSegments = 0
        var failedSegments = 0

        // Now stream audio for each segment
        for (index, segment) in segments.enumerated() {
            if Task.isCancelled {
                logger.info("Streaming cancelled at segment \(index)")
                break
            }

            let segmentText = segment["content"] as? String ?? ""
            let segmentType = segment["type"] as? String ?? "narration"

            if segmentText.isEmpty {
                logger.debug("Skipping empty segment \(index)")
                continue
            }

            // Notify that we have segment text (for immediate display)
            onSegmentText(index, segmentType, segmentText)

            // Try TTS with fallback
            do {
                let audioData = try await requestTTSWithFallback(
                    host: host,
                    text: segmentText,
                    voice: voice,
                    segmentIndex: index,
                    totalSegments: segments.count
                )

                successfulSegments += 1

                // Notify that we have audio ready
                onSegmentAudio(index, audioData)

            } catch {
                failedSegments += 1
                logger.error("TTS failed for segment \(index): \(error.localizedDescription)")
                // Continue to next segment instead of failing entirely
            }
        }

        logger.info("Transcript streaming complete: \(successfulSegments) successful, \(failedSegments) failed")
        onComplete()
    }

    /// Request TTS with fallback to alternate servers
    private func requestTTSWithFallback(
        host: String,
        text: String,
        voice: String,
        segmentIndex: Int,
        totalSegments: Int
    ) async throws -> Data {
        var lastError: Error?

        for server in ttsServerOrder {
            do {
                let audioData = try await requestTTS(
                    host: host,
                    server: server,
                    text: text,
                    voice: voice,
                    segmentIndex: segmentIndex,
                    totalSegments: totalSegments
                )
                return audioData
            } catch {
                lastError = error
                logger.warning("TTS server \(server.rawValue) failed, trying next: \(error.localizedDescription)")
            }
        }

        throw lastError ?? StreamingError.allTTSServersFailed
    }

    /// Request TTS from a specific server
    private func requestTTS(
        host: String,
        server: TTSServer,
        text: String,
        voice: String,
        segmentIndex: Int,
        totalSegments: Int
    ) async throws -> Data {
        let ttsURL = URL(string: "http://\(host):\(server.port)/v1/audio/speech")!
        var request = URLRequest(url: ttsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let ttsBody: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": voice,
            "response_format": "wav"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: ttsBody)

        logger.info("[\(server.rawValue)] Requesting TTS segment \(segmentIndex + 1)/\(totalSegments): \(text.prefix(50))...")

        let startTime = Date()
        let (audioData, audioResponse) = try await URLSession.shared.data(for: request)
        let latency = Date().timeIntervalSince(startTime)

        guard let audioHttpResponse = audioResponse as? HTTPURLResponse else {
            throw StreamingError.networkError("Invalid response from \(server.rawValue)")
        }

        if audioHttpResponse.statusCode != 200 {
            let errorBody = String(data: audioData, encoding: .utf8) ?? "unknown"
            logger.error("[\(server.rawValue)] TTS failed: HTTP \(audioHttpResponse.statusCode) - \(errorBody)")
            throw StreamingError.ttsError(
                statusCode: audioHttpResponse.statusCode,
                message: errorBody
            )
        }

        // Validate audio data
        if audioData.count < 44 {
            logger.error("[\(server.rawValue)] Audio data too small: \(audioData.count) bytes")
            throw StreamingError.ttsError(statusCode: 200, message: "Audio data too small")
        }

        // Log WAV header info
        let headerBytes = Array(audioData.prefix(44))
        let riffHeader = String(bytes: headerBytes[0..<4], encoding: .ascii) ?? "?"
        let waveHeader = String(bytes: headerBytes[8..<12], encoding: .ascii) ?? "?"

        if riffHeader != "RIFF" || waveHeader != "WAVE" {
            logger.warning("[\(server.rawValue)] Unexpected audio format - RIFF: '\(riffHeader)', WAVE: '\(waveHeader)'")
        }

        logger.info("[\(server.rawValue)] Got \(audioData.count) bytes of audio in \(String(format: "%.2f", latency))s (RIFF: \(riffHeader), WAVE: \(waveHeader))")

        return audioData
    }
}

// MARK: - Convenience Factory Methods

extension TranscriptStreamingService {
    /// Create a service configured from UserDefaults
    public static func fromUserDefaults() -> TranscriptStreamingService {
        let service = TranscriptStreamingService()
        let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
        if !serverIP.isEmpty {
            Task {
                await service.configure(host: serverIP)
            }
        }
        return service
    }
}
