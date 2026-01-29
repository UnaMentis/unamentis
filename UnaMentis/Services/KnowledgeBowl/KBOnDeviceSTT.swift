//
//  KBOnDeviceSTT.swift
//  UnaMentis
//
//  On-device speech-to-text using SFSpeechRecognizer for Knowledge Bowl oral rounds
//

import AVFoundation
import OSLog
import Speech

// MARK: - On-Device STT Service

/// Provides offline speech recognition using SFSpeechRecognizer
/// Conforms to STTService protocol for integration with provider abstraction layer
public actor KBOnDeviceSTT: STTService {
    // MARK: - STTService Protocol Requirements

    public private(set) var metrics = STTMetrics(
        medianLatency: 0.15,  // Apple Speech is typically very fast
        p99Latency: 0.3,
        wordEmissionRate: 0
    )

    public var costPerHour: Decimal { Decimal(0) }  // On-device = free

    public private(set) var isStreaming: Bool = false

    // MARK: - Private State

    private let logger = Logger(subsystem: "com.unamentis", category: "KBOnDeviceSTT")
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var resultContinuation: AsyncStream<STTResult>.Continuation?

    private var sessionStartTime: Date?
    private var latencyMeasurements: [TimeInterval] = []
    private var lastAudioTime: Date?

    // MARK: - Initialization

    public init() {
        logger.info("KBOnDeviceSTT initialized")
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

        // Check microphone permission
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            logger.error("Microphone access denied")
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
        let startTime = Date()
        sessionStartTime = startTime
        latencyMeasurements = []

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw STTError.streamingFailed("Failed to create recognition request")
        }

        // Configure for streaming
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        // Create audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw STTError.streamingFailed("Failed to create audio engine")
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create result stream using AsyncStream.makeStream for proper actor isolation
        let (stream, continuation) = AsyncStream<STTResult>.makeStream()
        self.resultContinuation = continuation

        // Start recognition task
        // The callback from SFSpeechRecognizer runs on an arbitrary thread, so we must
        // dispatch results to avoid actor isolation violations
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Handle error
            if let error = error {
                // Log errors asynchronously to avoid actor isolation issues
                Task { [weak self] in
                    await self?.logError("Recognition error: \(error.localizedDescription)")
                }
                continuation.finish()
                return
            }

            guard let result = result else { return }

            // Extract all data locally before yielding
            let transcript = result.bestTranscription.formattedString
            let isFinal = result.isFinal
            let confidence = result.bestTranscription.segments.last?.confidence ?? 0.0
            let latency = Date().timeIntervalSince(startTime)

            let sttResult = STTResult(
                transcript: transcript,
                isFinal: isFinal,
                isEndOfUtterance: isFinal,
                confidence: confidence,
                timestamp: Date().timeIntervalSince1970,
                latency: latency,
                wordTimestamps: nil
            )

            continuation.yield(sttResult)

            if isFinal {
                Task { [weak self] in
                    await self?.logInfo("Final transcript: \(transcript)")
                }
                continuation.finish()
            }
        }

        // Install tap on input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            continuation.finish()
            return stream
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            // Send buffer directly to recognition request
            request.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            logger.info("Audio engine started")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            continuation.finish()
        }

        // Handle cancellation
        continuation.onTermination = { @Sendable [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.cleanup()
            }
        }

        return stream
    }

    // MARK: - Logging Helpers (for safe access from callbacks)

    private func logError(_ message: String) {
        logger.error("\(message)")
    }

    private func logInfo(_ message: String) {
        logger.info("\(message)")
    }

    public func sendAudio(_ buffer: sending AVAudioPCMBuffer) async throws {
        guard isStreaming else {
            throw STTError.notStreaming
        }

        lastAudioTime = Date()
        recognitionRequest?.append(buffer)
    }

    public func stopStreaming() async throws {
        guard isStreaming else { return }

        logger.info("Stopping Apple Speech stream")

        recognitionRequest?.endAudio()
        resultContinuation?.finish()

        await cleanup()
    }

    public func cancelStreaming() async {
        logger.info("Cancelling Apple Speech stream")

        recognitionTask?.cancel()
        resultContinuation?.finish()

        await cleanup()
    }

    // MARK: - Private Helpers

    private func cleanup() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        resultContinuation = nil
        isStreaming = false

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }

        logger.debug("Cleanup complete")
    }
}

// MARK: - Errors

enum KBSTTError: LocalizedError, Sendable {
    case authorizationDenied
    case microphoneAccessDenied
    case restricted
    case recognizerUnavailable
    case recognitionRequestFailed
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition permission was denied"
        case .microphoneAccessDenied:
            return "Microphone access was denied"
        case .restricted:
            return "Speech recognition is restricted on this device"
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .recognitionRequestFailed:
            return "Failed to create speech recognition request"
        case .recognitionFailed(let message):
            return "Speech recognition failed: \(message)"
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension KBOnDeviceSTT {
    /// Create an STT instance for previews
    static func preview() -> KBOnDeviceSTT {
        KBOnDeviceSTT()
    }
}
#endif
