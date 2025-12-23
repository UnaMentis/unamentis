// UnaMentis - AssemblyAI STT Service
// Streaming Speech-to-Text using AssemblyAI Universal-Streaming
//
// Part of Provider Implementations (TDD Section 6)

import Foundation
@preconcurrency import AVFoundation
import Logging

/// AssemblyAI streaming STT implementation
///
/// Uses WebSocket connection for real-time transcription with:
/// - Low latency streaming
/// - Word-level timestamps
/// - End of utterance detection
public actor AssemblyAISTTService: STTService {
    
    // MARK: - Properties
    
    private let logger = Logger(label: "com.unamentis.stt.assemblyai")
    private let apiKey: String
    
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var streamContinuation: AsyncStream<STTResult>.Continuation?
    
    /// Performance metrics
    public private(set) var metrics: STTMetrics = STTMetrics(
        medianLatency: 0.15,
        p99Latency: 0.3,
        wordEmissionRate: 3.0
    )
    
    /// Cost per hour of audio ($0.65/hour for Universal)
    public let costPerHour: Decimal = 0.65
    
    /// Whether currently streaming
    public private(set) var isStreaming: Bool = false
    
    /// Track latencies for metrics
    private var latencies: [TimeInterval] = []
    private var streamStartTime: Date?
    
    // MARK: - Initialization
    
    public init(apiKey: String) {
        self.apiKey = apiKey
        logger.info("AssemblyAISTTService initialized")
    }
    
    // MARK: - STTService Protocol
    
    public func startStreaming(audioFormat: sending AVAudioFormat) async throws -> AsyncStream<STTResult> {
        guard !isStreaming else {
            throw STTError.alreadyStreaming
        }
        
        logger.info("Starting AssemblyAI streaming session")
        streamStartTime = Date()
        latencies.removeAll()
        
        // Create WebSocket connection
        let url = URL(string: "wss://api.assemblyai.com/v2/realtime/ws?sample_rate=\(Int(audioFormat.sampleRate))")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        
        urlSession = URLSession(configuration: .default)
        webSocket = urlSession?.webSocketTask(with: request)
        
        // Create the async stream
        let stream = AsyncStream<STTResult> { continuation in
            self.streamContinuation = continuation
            
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.handleStreamTermination()
                }
            }
        }
        
        // Connect and start receiving
        webSocket?.resume()
        isStreaming = true
        
        // Start receive loop
        Task {
            await receiveMessages()
        }
        
        logger.info("AssemblyAI streaming started")
        return stream
    }
    
    public func sendAudio(_ buffer: sending AVAudioPCMBuffer) async throws {
        guard isStreaming, let webSocket = webSocket else {
            throw STTError.notStreaming
        }
        
        // Convert buffer to base64-encoded PCM data
        guard let data = buffer.toData() else {
            throw STTError.invalidAudioFormat
        }
        
        let base64Audio = data.base64EncodedString()
        let message: [String: Any] = ["audio_data": base64Audio]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw STTError.streamingFailed("Failed to encode audio")
        }
        
        try await webSocket.send(.string(jsonString))
    }
    
    public func stopStreaming() async throws {
        guard isStreaming else { return }
        
        logger.info("Stopping AssemblyAI streaming")
        
        // Send terminate message
        if let webSocket = webSocket {
            let terminateMessage = "{\"terminate_session\": true}"
            try? await webSocket.send(.string(terminateMessage))
        }
        
        await cleanup()
        updateMetrics()
    }
    
    public func cancelStreaming() async {
        logger.info("Cancelling AssemblyAI streaming")
        await cleanup()
    }
    
    // MARK: - Private Methods
    
    private func receiveMessages() async {
        guard let webSocket = webSocket else { return }
        
        while isStreaming {
            do {
                let message = try await webSocket.receive()
                
                switch message {
                case .string(let text):
                    if let result = parseTranscriptMessage(text) {
                        streamContinuation?.yield(result)
                    }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8),
                       let result = parseTranscriptMessage(text) {
                        streamContinuation?.yield(result)
                    }
                @unknown default:
                    break
                }
            } catch {
                if isStreaming {
                    logger.error("WebSocket receive error: \(error.localizedDescription)")
                }
                break
            }
        }
    }
    
    private func parseTranscriptMessage(_ text: String) -> STTResult? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Handle different message types
        guard let messageType = json["message_type"] as? String else {
            return nil
        }
        
        switch messageType {
        case "PartialTranscript", "FinalTranscript":
            guard let transcript = json["text"] as? String else { return nil }
            
            let isFinal = messageType == "FinalTranscript"
            let confidence = (json["confidence"] as? Double).map { Float($0) } ?? 0.9
            
            // Calculate latency
            let latency: TimeInterval
            if let audioStart = json["audio_start"] as? Double {
                latency = Date().timeIntervalSince1970 - (streamStartTime?.timeIntervalSince1970 ?? 0) - (audioStart / 1000.0)
                latencies.append(latency)
            } else {
                latency = 0.15 // Default estimate
            }
            
            // Parse word timestamps if available
            var wordTimestamps: [WordTimestamp]? = nil
            if let words = json["words"] as? [[String: Any]] {
                wordTimestamps = words.compactMap { word -> WordTimestamp? in
                    guard let text = word["text"] as? String,
                          let start = word["start"] as? Double,
                          let end = word["end"] as? Double else { return nil }
                    let conf = (word["confidence"] as? Double).map { Float($0) }
                    return WordTimestamp(word: text, startTime: start / 1000.0, endTime: end / 1000.0, confidence: conf)
                }
            }
            
            return STTResult(
                transcript: transcript,
                isFinal: isFinal,
                isEndOfUtterance: isFinal,
                confidence: confidence,
                latency: latency,
                wordTimestamps: wordTimestamps
            )
            
        case "SessionTerminated":
            logger.info("AssemblyAI session terminated")
            streamContinuation?.finish()
            return nil
            
        default:
            return nil
        }
    }
    
    private func handleStreamTermination() async {
        await cleanup()
    }
    
    private func cleanup() async {
        isStreaming = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        streamContinuation?.finish()
        streamContinuation = nil
    }
    
    private func updateMetrics() {
        guard !latencies.isEmpty else { return }
        
        let sorted = latencies.sorted()
        let medianIndex = sorted.count / 2
        let p99Index = Int(Double(sorted.count) * 0.99)
        
        metrics = STTMetrics(
            medianLatency: sorted[medianIndex],
            p99Latency: sorted[Swift.min(p99Index, sorted.count - 1)],
            wordEmissionRate: 3.0 // Could calculate from actual data
        )
    }
}

// MARK: - AVAudioPCMBuffer Extension

extension AVAudioPCMBuffer {
    /// Convert buffer to raw PCM data
    func toData() -> Data? {
        guard let channelData = floatChannelData?[0] else { return nil }
        
        let frameLength = Int(self.frameLength)
        var data = Data(capacity: frameLength * MemoryLayout<Int16>.size)
        
        // Convert float32 to int16
        for i in 0..<frameLength {
            let sample = channelData[i]
            let clampedSample = max(-1.0, min(1.0, sample))
            let intSample = Int16(clampedSample * Float(Int16.max))
            withUnsafeBytes(of: intSample.littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
    }
}
