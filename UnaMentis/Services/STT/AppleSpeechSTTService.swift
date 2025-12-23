// UnaMentis - Apple Speech STT Service
// On-device Speech-to-Text using Apple's Speech framework
//
// Part of Provider Abstraction Layer (TDD Section 6)

import Foundation
@preconcurrency import AVFoundation
import Speech
import Logging

/// On-device STT service using Apple's Speech framework
///
/// This service runs entirely on-device with no network required.
/// Uses Apple's SFSpeechRecognizer for transcription.
public actor AppleSpeechSTTService: STTService {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.stt.applespeech")

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var resultContinuation: AsyncStream<STTResult>.Continuation?

    private var sessionStartTime: Date?
    private var latencyMeasurements: [TimeInterval] = []
    private var lastAudioTime: Date?

    /// Performance metrics
    public private(set) var metrics = STTMetrics(
        medianLatency: 0.15,  // Apple Speech is typically very fast
        p99Latency: 0.3,
        wordEmissionRate: 0
    )

    /// Cost per hour (on-device = $0)
    public var costPerHour: Decimal { Decimal(0) }

    /// Whether currently streaming
    public private(set) var isStreaming: Bool = false

    // MARK: - Initialization

    public init() {
        logger.info("AppleSpeechSTTService initialized")
    }

    // MARK: - Authorization

    /// Request speech recognition authorization
    public static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Check if speech recognition is available
    public static var isAvailable: Bool {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        return recognizer?.isAvailable ?? false
    }

    // MARK: - STTService Protocol

    public func startStreaming(audioFormat: sending AVAudioFormat) async throws -> AsyncStream<STTResult> {
        guard !isStreaming else {
            throw STTError.alreadyStreaming
        }

        // Check authorization
        let authStatus = await Self.requestAuthorization()
        guard authStatus == .authorized else {
            logger.error("Speech recognition not authorized: \(authStatus.rawValue)")
            throw STTError.authenticationFailed
        }

        // Initialize recognizer
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            logger.error("Speech recognizer not available")
            throw STTError.connectionFailed("Speech recognizer not available")
        }

        logger.info("Starting Apple Speech stream")

        isStreaming = true
        sessionStartTime = Date()
        latencyMeasurements = []

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw STTError.streamingFailed("Failed to create recognition request")
        }

        // Configure for streaming
        request.shouldReportPartialResults = true

        // On-device recognition is preferred but not required on simulator
        // (Simulator doesn't support on-device speech recognition)
        #if targetEnvironment(simulator)
        request.requiresOnDeviceRecognition = false
        logger.info("Running on simulator - using server-based speech recognition")
        #else
        request.requiresOnDeviceRecognition = true  // Force on-device on real devices
        #endif

        #if os(iOS)
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        #endif

        // Use makeStream to avoid actor isolation issues with closure-based AsyncStream
        let (stream, continuation) = AsyncStream<STTResult>.makeStream()
        self.resultContinuation = continuation

        continuation.onTermination = { @Sendable _ in
            Task { [weak self] in
                await self?.cleanup()
            }
        }

        // Start recognition task - capture recognizer to avoid holding self
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard self != nil else { return }

            // Capture values to avoid data race
            let transcript = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            let confidence = result?.bestTranscription.segments.first?.confidence ?? 0.9
            let segments = result?.bestTranscription.segments.map { segment in
                WordTimestamp(
                    word: segment.substring,
                    startTime: segment.timestamp,
                    endTime: segment.timestamp + segment.duration,
                    confidence: segment.confidence
                )
            }
            let errorDesc = error?.localizedDescription

            Task { [weak self] in
                await self?.handleRecognitionResultValues(
                    transcript: transcript,
                    isFinal: isFinal,
                    confidence: confidence,
                    segments: segments,
                    errorDescription: errorDesc
                )
            }
        }

        return stream
    }

    public func sendAudio(_ buffer: sending AVAudioPCMBuffer) async throws {
        guard isStreaming else {
            throw STTError.notStreaming
        }

        guard let request = recognitionRequest else {
            throw STTError.streamingFailed("Recognition request not available")
        }

        lastAudioTime = Date()
        request.append(buffer)
    }

    public func stopStreaming() async throws {
        guard isStreaming else { return }

        logger.info("Stopping Apple Speech stream")

        // End the audio request
        recognitionRequest?.endAudio()

        // Wait briefly for final results
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        await cleanup()
        recordSessionMetrics()
    }

    public func cancelStreaming() async {
        recognitionTask?.cancel()
        await cleanup()
    }

    // MARK: - Private Methods

    private func handleRecognitionResultValues(
        transcript: String,
        isFinal: Bool,
        confidence: Float,
        segments: [WordTimestamp]?,
        errorDescription: String?
    ) {
        if let errorDesc = errorDescription {
            logger.error("Speech recognition error: \(errorDesc)")
            resultContinuation?.finish()
            return
        }

        guard !transcript.isEmpty || isFinal else { return }

        // Calculate latency
        let latency: TimeInterval
        if let audioTime = lastAudioTime {
            latency = Date().timeIntervalSince(audioTime)
            latencyMeasurements.append(latency)
        } else {
            latency = 0.1
        }

        let sttResult = STTResult(
            transcript: transcript,
            isFinal: isFinal,
            isEndOfUtterance: isFinal,
            confidence: confidence,
            latency: latency,
            wordTimestamps: segments
        )

        resultContinuation?.yield(sttResult)

        if isFinal {
            logger.info("Final result: \(transcript.prefix(50))...")
        }
    }

    private func cleanup() async {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        resultContinuation?.finish()
        resultContinuation = nil
        isStreaming = false
    }

    private func recordSessionMetrics() {
        let sortedLatencies = latencyMeasurements.sorted()

        let median: TimeInterval
        let p99: TimeInterval

        if sortedLatencies.isEmpty {
            median = 0.15
            p99 = 0.3
        } else {
            median = sortedLatencies[sortedLatencies.count / 2]
            let p99Index = min(Int(Double(sortedLatencies.count) * 0.99), sortedLatencies.count - 1)
            p99 = sortedLatencies[p99Index]
        }

        metrics = STTMetrics(
            medianLatency: median,
            p99Latency: p99,
            wordEmissionRate: 0
        )
    }
}
