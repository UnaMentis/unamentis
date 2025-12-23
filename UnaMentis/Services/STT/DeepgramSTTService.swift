// UnaMentis - Deepgram STT Service
// Streaming Speech-to-Text using Deepgram Nova-3 via WebSockets
//
// Part of Provider Implementations (Phase 5)

import Foundation
import AVFoundation
import Logging

/// Deepgram Nova-3 streaming STT implementation
public actor DeepgramSTTService: STTService {
    
    // MARK: - Properties
    
    private let logger = Logger(label: "com.unamentis.stt.deepgram")
    private let apiKey: String
    private let baseURL = "wss://api.deepgram.com/v1/listen"
    
    /// Performance metrics
    public private(set) var metrics = STTMetrics(
        medianLatency: 0.3, // Approximate for Nova-2/3
        p99Latency: 0.6,
        wordEmissionRate: 0
    )
    
    /// Cost per hour ($0.0043/min -> $0.258/hour)
    public var costPerHour: Decimal {
        Decimal(string: "0.258")!
    }
    
    /// Streaming state
    public private(set) var isStreaming: Bool = false
    
    // WebSocket
    private var webSocketTask: URLSessionWebSocketTask?
    private var streamContinuation: AsyncStream<STTResult>.Continuation?
    
    // MARK: - Initialization
    
    public init(apiKey: String) {
        self.apiKey = apiKey
        logger.info("DeepgramSTTService initialized")
    }
    
    // MARK: - STTService Protocol
    
    public func startStreaming(audioFormat: sending AVAudioFormat) async throws -> AsyncStream<STTResult> {
        guard !isStreaming else { throw STTError.alreadyStreaming }
        
        logger.info("Starting Deepgram stream with format: \(audioFormat.sampleRate)Hz")
        
        // Build URL
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"), // Use Nova-3 or nova-2
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "encoding", value: "linear16"), // Assuming PCM Int16
            URLQueryItem(name: "sample_rate", value: String(Int(audioFormat.sampleRate))),
            URLQueryItem(name: "channels", value: String(audioFormat.channelCount))
        ]
        
        guard let url = components.url else { throw STTError.connectionFailed("Invalid URL") }
        
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        
        webSocketTask?.resume()
        isStreaming = true
        
        return AsyncStream { continuation in
            self.streamContinuation = continuation
            
            // Start listening loop
            Task {
                await self.listenForMessages()
            }
            
            // Handle termination
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    try? await self?.stopStreaming()
                }
            }
        }
    }
    
    public func sendAudio(_ buffer: sending AVAudioPCMBuffer) async throws {
        guard isStreaming, let ws = webSocketTask else { throw STTError.notStreaming }
        
        // Convert to 16-bit PCM Data
        guard let data = buffer.toPCMInt16Data() else {
            throw STTError.invalidAudioFormat
        }
        
        let message = URLSessionWebSocketTask.Message.data(data)
        try await ws.send(message)
    }
    
    public func stopStreaming() async throws {
        guard isStreaming else { return }
        
        logger.info("Stopping Deepgram stream")
        
        // Send close frame (EOS)
        // Deepgram usually expects close frame or empty data to signal end
        let empty = Data()
        try? await webSocketTask?.send(.data(empty))
        
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        
        streamContinuation?.finish()
        streamContinuation = nil
        isStreaming = false
    }
    
    public func cancelStreaming() async {
        webSocketTask?.cancel()
        webSocketTask = nil
        streamContinuation?.finish()
        streamContinuation = nil
        isStreaming = false
    }
    
    // MARK: - Private Methods
    
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
            logger.error("WebSocket receive failed: \(error)")
            await cancelStreaming()
        }
    }
    
    private func handleMessage(_ jsonString: String) async {
        // Parse Deepgram JSON response
        guard let data = jsonString.data(using: .utf8) else { return }
        
        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            
            if let result = response.channel.alternatives.first {
                let transcript = result.transcript
                guard !transcript.isEmpty else { return }
                
                let sttResult = STTResult(
                    transcript: transcript,
                    isFinal: response.isFinal,
                    isEndOfUtterance: response.isFinal,
                    confidence: Float(result.confidence),
                    timestamp: Date().timeIntervalSince1970
                )
                
                streamContinuation?.yield(sttResult)
            }
        } catch {
            logger.error("Failed to parse Deepgram response: \(error)")
        }
    }
}

// MARK: - Deepgram Models

private struct DeepgramResponse: Codable {
    let channel: Channel
    let isFinal: Bool
    
    enum CodingKeys: String, CodingKey {
        case channel
        case isFinal = "is_final"
    }
}

private struct Channel: Codable {
    let alternatives: [Alternative]
}

private struct Alternative: Codable {
    let transcript: String
    let confidence: Double
}

// MARK: - Helper

extension AVAudioPCMBuffer {
    func toPCMInt16Data() -> Data? {
        guard let floatChannelData = self.floatChannelData else { return nil }
        
        let frameLength = Int(self.frameLength)
        let channels = Int(self.format.channelCount)
        let totalSamples = frameLength * channels
        
        var data = Data(count: totalSamples * 2)
        
        data.withUnsafeMutableBytes { bufferPointer in
            let int16Buffer = bufferPointer.bindMemory(to: Int16.self)
            
            // Interleave and convert if needed, or just convert mono
            // Assuming mono for simplicity or handle interleaving
            let ptr = floatChannelData[0] // Only taking first channel (mono) for now if multi
            
            for i in 0..<frameLength {
                let floatSample = ptr[i]
                let intSample = Int16(max(-32768, min(32767, floatSample * 32767.0)))
                int16Buffer[i] = intSample
            }
        }
        
        return data
    }
}
