// UnaMentis - Knowledge Bowl Voice Coordinator
// Handles voice-first integration for practice sessions
//
// Automatically speaks questions via TTS and listens for
// verbal answers via STT, working alongside the text UI.

@preconcurrency import AVFoundation
import Combine
import Foundation
import Logging

/// Coordinates TTS and STT for voice-first Knowledge Bowl practice
@MainActor
final class KBVoiceCoordinator: ObservableObject {
    // MARK: - Published State

    /// Whether TTS is currently speaking
    @Published private(set) var isSpeaking = false

    /// Whether STT is currently listening
    @Published private(set) var isListening = false

    /// Current transcript from STT (real-time)
    @Published private(set) var currentTranscript = ""

    /// Whether voice services are ready
    @Published private(set) var isReady = false

    // MARK: - Services

    private var ttsService: (any TTSService)?
    private var sttService: (any STTService)?
    private var vadService: (any VADService)?
    private var audioEngine: AudioEngine?
    private let telemetry: TelemetryEngine

    /// Pre-generated audio cache for KB questions
    private var audioCache: KBAudioCache?

    /// Whether to use server pre-generated TTS (vs local Apple TTS)
    private var useServerTTS: Bool = false

    // MARK: - State Management

    private var sttStreamTask: Task<Void, Never>?
    private var audioSubscription: AnyCancellable?

    /// Silence detection for utterance completion
    private var silenceStartTime: Date?
    private var hasDetectedSpeech = false
    private let silenceThreshold: TimeInterval = 1.5

    /// Callbacks
    private var onTranscriptComplete: ((String) -> Void)?

    private static let logger = Logger(label: "com.unamentis.kb.voice")

    // MARK: - Initialization

    init() {
        // Create dedicated telemetry for KB module
        self.telemetry = TelemetryEngine()
    }

    // MARK: - Setup

    /// Initialize voice services for practice session
    func setup() async throws {
        Self.logger.info("Setting up KB voice coordinator")

        // Create on-device TTS service (no API key needed)
        let tts = AppleTTSService()
        self.ttsService = tts

        // Create on-device STT service
        let stt = AppleSpeechSTTService()
        self.sttService = stt

        // Create VAD service for speech detection
        let vad = SileroVADService()
        self.vadService = vad

        // Create audio engine
        let engine = AudioEngine(
            config: .default,
            vadService: vad,
            telemetry: telemetry
        )
        self.audioEngine = engine

        // Configure audio engine
        try await engine.configure(config: .default)

        // Initialize server audio cache if self-hosted is enabled
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""

        if selfHostedEnabled && !serverIP.isEmpty {
            audioCache = KBAudioCache(serverHost: serverIP)
            useServerTTS = true
            Self.logger.info("KB audio cache initialized for server: \(serverIP)")
        }

        isReady = true
        Self.logger.info("KB voice coordinator ready")
    }

    /// Start audio engine for listening
    func startListening() async throws {
        guard let audioEngine = audioEngine,
              let sttService = sttService else {
            throw VoiceCoordinatorError.notConfigured
        }

        // Start audio engine
        try await audioEngine.start()

        // Subscribe to audio stream for VAD
        subscribeToAudioStream()

        // Start STT streaming
        guard let format = await audioEngine.format else {
            throw VoiceCoordinatorError.audioFormatUnavailable
        }

        // Create a copy of the format for sending
        guard let formatCopy = AVAudioFormat(
            commonFormat: format.commonFormat,
            sampleRate: format.sampleRate,
            channels: format.channelCount,
            interleaved: format.isInterleaved
        ) else {
            throw VoiceCoordinatorError.audioFormatUnavailable
        }

        let stream = try await sttService.startStreaming(audioFormat: formatCopy)

        sttStreamTask = Task {
            for await result in stream {
                await handleSTTResult(result)
            }
        }

        isListening = true
        Self.logger.info("KB voice listening started")
    }

    /// Stop audio engine and STT
    func stopListening() async {
        sttStreamTask?.cancel()
        sttStreamTask = nil
        audioSubscription?.cancel()
        audioSubscription = nil

        try? await sttService?.stopStreaming()
        await audioEngine?.stop()

        isListening = false
        hasDetectedSpeech = false
        silenceStartTime = nil
        currentTranscript = ""

        Self.logger.info("KB voice listening stopped")
    }

    /// Shutdown all voice services
    func shutdown() async {
        await stopListening()

        audioEngine = nil
        sttService = nil
        ttsService = nil
        vadService = nil
        isReady = false

        Self.logger.info("KB voice coordinator shut down")
    }

    // MARK: - TTS: Speaking

    /// Speak text using TTS and wait for completion
    func speak(_ text: String) async {
        guard let ttsService = ttsService,
              let audioEngine = audioEngine else {
            Self.logger.warning("Voice services not ready, cannot speak")
            return
        }

        // Ensure audio engine is running for playback
        let engineRunning = await audioEngine.isRunning
        if !engineRunning {
            do {
                try await audioEngine.start()
            } catch {
                Self.logger.error("Failed to start audio engine for TTS: \(error)")
                return
            }
        }

        isSpeaking = true
        Self.logger.info("Speaking: \"\(text.prefix(50))...\"")

        do {
            let stream = try await ttsService.synthesize(text: text)

            for await chunk in stream {
                try await audioEngine.playAudio(chunk)
                if chunk.isLast {
                    break
                }
            }
        } catch {
            Self.logger.error("TTS failed: \(error)")
        }

        isSpeaking = false
        Self.logger.info("Finished speaking")
    }

    /// Speak a question with proper pacing for competition style
    func speakQuestion(_ question: KBQuestion) async {
        // Try server cache first if available
        if useServerTTS, let cache = audioCache {
            do {
                if let cached = try await cache.getAudio(
                    questionId: question.id,
                    segment: .question
                ) {
                    try await playCachedAudio(cached)
                    return
                }
            } catch {
                Self.logger.warning("Server audio unavailable, falling back to local: \(error)")
            }
        }

        // Fallback: speak with local TTS
        await speak(question.questionText)
    }

    /// Speak correct/incorrect feedback with explanation
    func speakFeedback(isCorrect: Bool, correctAnswer: String, explanation: String, question: KBQuestion? = nil) async {
        // Try server feedback audio first
        if useServerTTS, let cache = audioCache {
            do {
                let feedbackType = isCorrect ? "correct" : "incorrect"
                if let feedbackAudio = try await cache.getFeedbackAudio(feedbackType) {
                    try await playCachedAudio(feedbackAudio)
                } else {
                    // Fallback for feedback
                    if isCorrect {
                        await speak("Correct!")
                    } else {
                        await speak("Incorrect. The correct answer is \(correctAnswer).")
                    }
                }
            } catch {
                // Fallback to local TTS
                if isCorrect {
                    await speak("Correct!")
                } else {
                    await speak("Incorrect. The correct answer is \(correctAnswer).")
                }
            }
        } else {
            if isCorrect {
                await speak("Correct!")
            } else {
                await speak("Incorrect. The correct answer is \(correctAnswer).")
            }
        }

        // Brief pause before explanation
        try? await Task.sleep(nanoseconds: 500_000_000)

        if !explanation.isEmpty {
            // Try cached explanation
            if useServerTTS, let cache = audioCache, let q = question {
                do {
                    if let cached = try await cache.getAudio(
                        questionId: q.id,
                        segment: .explanation
                    ) {
                        try await playCachedAudio(cached)
                        return
                    }
                } catch {
                    Self.logger.debug("Explanation cache miss, using local TTS")
                }
            }

            // Fallback: local TTS
            await speak(explanation)
        }
    }

    /// Speak session completion message
    func speakCompletion(correctCount: Int, totalCount: Int) async {
        let accuracy = totalCount > 0 ? Double(correctCount) / Double(totalCount) * 100 : 0
        let message: String

        if accuracy >= 80 {
            message = "Excellent work! You got \(correctCount) out of \(totalCount) correct. That's \(Int(accuracy)) percent accuracy."
        } else if accuracy >= 60 {
            message = "Good effort! You got \(correctCount) out of \(totalCount) correct. Keep practicing to improve."
        } else {
            message = "Session complete. You got \(correctCount) out of \(totalCount) correct. Consider reviewing the topics you missed."
        }

        await speak(message)
    }

    // MARK: - Server Audio Cache

    /// Play pre-cached audio from server
    private func playCachedAudio(_ cached: KBCachedAudio) async throws {
        guard let audioEngine = audioEngine else {
            throw VoiceCoordinatorError.notConfigured
        }

        // Ensure audio engine is running for playback
        let engineRunning = await audioEngine.isRunning
        if !engineRunning {
            try await audioEngine.start()
        }

        isSpeaking = true
        Self.logger.debug("Playing cached audio (\(cached.data.count) bytes)")

        // Create format for 24kHz 16-bit mono WAV (server default)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(cached.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw VoiceCoordinatorError.audioFormatUnavailable
        }

        // Skip WAV header (44 bytes) to get raw PCM data
        let pcmData: Data
        if cached.data.count > 44 {
            pcmData = cached.data.dropFirst(44)
        } else {
            pcmData = cached.data
        }

        do {
            try await audioEngine.playRawAudio(pcmData, format: format)
        } catch {
            Self.logger.error("Failed to play cached audio: \(error)")
            throw error
        }

        isSpeaking = false
        Self.logger.debug("Finished playing cached audio")
    }

    /// Warm the cache at session start
    func warmCache(questions: [KBQuestion]) async {
        guard let cache = audioCache else { return }

        Self.logger.info("Warming audio cache for \(min(5, questions.count)) questions")
        await cache.warmCache(questions: questions, lookahead: 5)
    }

    /// Prefetch audio for upcoming questions
    func prefetchUpcoming(questions: [KBQuestion], currentIndex: Int) async {
        guard let cache = audioCache else { return }

        await cache.prefetchUpcoming(
            questions: questions,
            currentIndex: currentIndex,
            lookahead: 3
        )
    }

    // MARK: - STT: Listening for Answers

    /// Set callback for when a complete transcript is available
    func onTranscriptComplete(_ callback: @escaping (String) -> Void) {
        self.onTranscriptComplete = callback
    }

    /// Clear the current transcript and reset for new answer
    func resetTranscript() {
        currentTranscript = ""
        hasDetectedSpeech = false
        silenceStartTime = nil
    }

    // MARK: - Private: Audio Stream Handling

    private func subscribeToAudioStream() {
        guard let audioEngine = audioEngine else { return }

        audioSubscription = audioEngine.audioStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (buffer, vadResult) in
                guard let self = self else { return }
                Task {
                    await self.handleVADResult(vadResult, buffer: buffer)
                }
            }
    }

    private func handleVADResult(_ result: VADResult, buffer: sending AVAudioPCMBuffer) async {
        // Only process VAD when listening and not speaking
        guard isListening && !isSpeaking else { return }

        // Send audio to STT
        do {
            try await sttService?.sendAudio(buffer)
        } catch {
            Self.logger.error("Failed to send audio to STT: \(error)")
        }

        // Track speech/silence for utterance detection
        if result.isSpeech {
            if !hasDetectedSpeech {
                Self.logger.debug("Speech detected")
            }
            hasDetectedSpeech = true
            silenceStartTime = nil
        } else if hasDetectedSpeech {
            // Speech ended, start silence timer
            if silenceStartTime == nil {
                silenceStartTime = Date()
            } else if let startTime = silenceStartTime,
                      Date().timeIntervalSince(startTime) >= silenceThreshold {
                // Silence threshold reached, finalize utterance
                finalizeUtterance()
            }
        }
    }

    private func handleSTTResult(_ result: STTResult) async {
        // Update transcript in real-time
        currentTranscript = result.transcript

        // If STT gives us a final result with end-of-utterance, use it
        if result.isFinal && result.isEndOfUtterance && !result.transcript.isEmpty {
            finalizeUtterance()
        }
    }

    private func finalizeUtterance() {
        guard !currentTranscript.isEmpty else { return }

        let transcript = currentTranscript
        Self.logger.info("Utterance complete: \"\(transcript)\"")

        // Reset state
        hasDetectedSpeech = false
        silenceStartTime = nil

        // Notify callback
        onTranscriptComplete?(transcript)
    }
}

// MARK: - Errors

enum VoiceCoordinatorError: Error, LocalizedError {
    case notConfigured
    case audioFormatUnavailable
    case ttsUnavailable
    case sttUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Voice services not configured"
        case .audioFormatUnavailable:
            return "Audio format not available"
        case .ttsUnavailable:
            return "Text-to-speech service unavailable"
        case .sttUnavailable:
            return "Speech-to-text service unavailable"
        }
    }
}
