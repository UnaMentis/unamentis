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
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.transcript.streaming")
    private var serverHost: String?
    private var serverPort: Int = 8766
    private var currentTask: Task<Void, Never>?

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

        if httpResponse.statusCode == 404 {
            throw StreamingError.topicNotFound
        }

        guard httpResponse.statusCode == 200 else {
            throw StreamingError.networkError("HTTP \(httpResponse.statusCode)")
        }

        // Parse transcript
        guard let transcriptJSON = try? JSONSerialization.jsonObject(with: transcriptData) as? [String: Any],
              let segments = transcriptJSON["segments"] as? [[String: Any]] else {
            throw StreamingError.parsingError("Failed to parse transcript")
        }

        if segments.isEmpty {
            throw StreamingError.noTranscript
        }

        logger.info("Got \(segments.count) transcript segments, starting audio streaming")

        // Now stream audio for each segment
        for (index, segment) in segments.enumerated() {
            if Task.isCancelled { break }

            let segmentText = segment["content"] as? String ?? ""
            let segmentType = segment["type"] as? String ?? "narration"

            if segmentText.isEmpty { continue }

            // Notify that we have segment text (for immediate display)
            onSegmentText(index, segmentType, segmentText)

            // Request TTS for this segment
            let ttsURL = URL(string: "http://\(host):8880/v1/audio/speech")!
            var request = URLRequest(url: ttsURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30

            let ttsBody: [String: Any] = [
                "model": "tts-1",
                "input": segmentText,
                "voice": voice,
                "response_format": "wav"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: ttsBody)

            logger.info("Requesting TTS for segment \(index + 1)/\(segments.count): \(segmentText.prefix(50))...")

            let startTime = Date()
            let (audioData, audioResponse) = try await URLSession.shared.data(for: request)
            let latency = Date().timeIntervalSince(startTime)

            guard let audioHttpResponse = audioResponse as? HTTPURLResponse,
                  audioHttpResponse.statusCode == 200 else {
                logger.error("TTS failed for segment \(index)")
                continue
            }

            logger.info("Got \(audioData.count) bytes of audio in \(String(format: "%.2f", latency))s")

            // Notify that we have audio ready
            onSegmentAudio(index, audioData)
        }

        logger.info("Transcript streaming complete")
        onComplete()
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
