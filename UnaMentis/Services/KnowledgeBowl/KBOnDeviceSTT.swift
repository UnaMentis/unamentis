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
@MainActor
final class KBOnDeviceSTT: NSObject, ObservableObject {
    // MARK: - Published State

    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var isFinal = false
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published private(set) var error: KBSTTError?

    // MARK: - Private State

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let logger = Logger(subsystem: "com.unamentis", category: "KBOnDeviceSTT")

    // MARK: - Initialization

    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        speechRecognizer?.delegate = self

        // Request on-device recognition for offline capability
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            logger.info("On-device speech recognition is supported")
        } else {
            logger.warning("On-device speech recognition not supported, will use server")
        }
    }

    // MARK: - Authorization

    /// Request speech recognition authorization
    func requestAuthorization() async -> Bool {
        logger.debug("Requesting speech recognition authorization...")

        // Check current status first
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        logger.debug("Current authorization status: \(String(describing: currentStatus))")

        if currentStatus == .authorized {
            await MainActor.run {
                self.authorizationStatus = .authorized
            }
            return true
        }

        // Request authorization
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                // Resume continuation immediately, update state on main actor separately
                let isAuthorized = status == .authorized

                Task { @MainActor [weak self] in
                    self?.authorizationStatus = status
                    switch status {
                    case .authorized:
                        self?.logger.info("Speech recognition authorized")
                    case .denied:
                        self?.logger.warning("Speech recognition denied")
                        self?.error = .authorizationDenied
                    case .restricted:
                        self?.logger.warning("Speech recognition restricted")
                        self?.error = .restricted
                    case .notDetermined:
                        self?.logger.info("Speech recognition not determined")
                    @unknown default:
                        break
                    }
                }

                continuation.resume(returning: isAuthorized)
            }
        }
    }

    /// Check microphone authorization
    func requestMicrophoneAccess() async -> Bool {
        logger.debug("Requesting microphone access...")
        let granted = await AVAudioApplication.requestRecordPermission()
        logger.debug("Microphone access: \(granted ? "granted" : "denied")")
        return granted
    }

    // MARK: - Recognition

    /// Start listening for speech input
    func startListening() async throws {
        // Check authorization
        if authorizationStatus != .authorized {
            let authorized = await requestAuthorization()
            guard authorized else {
                throw KBSTTError.authorizationDenied
            }
        }

        // Check microphone access
        let micAccess = await requestMicrophoneAccess()
        guard micAccess else {
            throw KBSTTError.microphoneAccessDenied
        }

        // Stop any existing recognition
        stopListening()

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw KBSTTError.recognitionRequestFailed
        }

        // Configure for on-device recognition if available
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = speechRecognizer?.supportsOnDeviceRecognition ?? false

        // Get input node
        let inputNode = audioEngine.inputNode

        // Get and validate audio format
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        logger.debug("Input node format: \(recordingFormat)")

        // Check if format is valid (sample rate and channel count must be > 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            logger.error("Invalid audio format: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")
            throw KBSTTError.recognitionRequestFailed
        }

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let error = error {
                    self.logger.error("Recognition error: \(error.localizedDescription)")
                    self.error = .recognitionFailed(error.localizedDescription)
                    self.stopListening()
                    return
                }

                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    self.isFinal = result.isFinal

                    if result.isFinal {
                        self.logger.info("Final transcript: \(self.transcript)")
                        self.stopListening()
                    }
                }
            }
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
        transcript = ""
        isFinal = false
        error = nil

        logger.info("Started listening for speech")
    }

    /// Stop listening and get final transcript
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
        logger.debug("Stopped listening")
    }

    /// Listen for a specific duration and return the transcript
    func listen(for duration: TimeInterval) async throws -> String {
        try await startListening()

        // Wait for the specified duration or until final result
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        stopListening()
        return transcript
    }

    /// Listen until silence is detected or max duration reached
    func listenUntilSilence(maxDuration: TimeInterval = 10) async throws -> String {
        try await startListening()

        let startTime = Date()
        var lastTranscriptLength = 0
        var silenceStartTime: Date?
        let silenceThreshold: TimeInterval = 1.5 // 1.5 seconds of silence

        while isListening {
            try await Task.sleep(nanoseconds: 100_000_000) // Check every 100ms

            // Check max duration
            if Date().timeIntervalSince(startTime) >= maxDuration {
                break
            }

            // Check for silence (no new words)
            if transcript.count == lastTranscriptLength {
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                } else if let startTime = silenceStartTime,
                          Date().timeIntervalSince(startTime) >= silenceThreshold {
                    break
                }
            } else {
                silenceStartTime = nil
                lastTranscriptLength = transcript.count
            }

            // Check if final result received
            if isFinal {
                break
            }
        }

        stopListening()
        return transcript
    }

    // MARK: - Availability

    /// Check if speech recognition is available
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    /// Check if on-device recognition is supported
    var supportsOnDevice: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension KBOnDeviceSTT: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer,
        availabilityDidChange available: Bool
    ) {
        Task { @MainActor in
            if !available {
                logger.warning("Speech recognition became unavailable")
                error = .recognizerUnavailable
            } else {
                logger.info("Speech recognition available")
            }
        }
    }
}

// MARK: - Errors

enum KBSTTError: LocalizedError, Sendable {
    case authorizationDenied
    case microphoneAccessDenied
    case restricted
    case recognizerUnavailable
    case recognitionRequestFailed
    case recognitionFailed(String)  // Store error message instead of Error for Sendable

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
