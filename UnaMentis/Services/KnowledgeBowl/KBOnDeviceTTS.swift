//
//  KBOnDeviceTTS.swift
//  UnaMentis
//
//  On-device text-to-speech using AVSpeechSynthesizer for Knowledge Bowl oral rounds
//

import AVFoundation
import OSLog

// MARK: - On-Device TTS Service

/// Provides offline text-to-speech capability using AVSpeechSynthesizer
@MainActor
final class KBOnDeviceTTS: NSObject, ObservableObject {
    // MARK: - Published State

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var progress: Float = 0

    // MARK: - Private State

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var completionHandler: (() -> Void)?
    private let logger = Logger(subsystem: "com.unamentis", category: "KBOnDeviceTTS")

    // MARK: - Configuration

    /// Voice configuration for questions
    struct VoiceConfig: Sendable {
        var language: String = "en-US"
        var rate: Float = AVSpeechUtteranceDefaultSpeechRate
        var pitchMultiplier: Float = 1.0
        var volume: Float = 1.0
        var preUtteranceDelay: TimeInterval = 0
        var postUtteranceDelay: TimeInterval = 0

        /// Standard reading pace for questions
        static let questionPace = VoiceConfig(
            rate: AVSpeechUtteranceDefaultSpeechRate * 0.9,
            pitchMultiplier: 1.0
        )

        /// Slower pace for complex questions
        static let slowPace = VoiceConfig(
            rate: AVSpeechUtteranceDefaultSpeechRate * 0.75,
            pitchMultiplier: 1.0
        )

        /// Faster pace for experienced users
        static let fastPace = VoiceConfig(
            rate: AVSpeechUtteranceDefaultSpeechRate * 1.1,
            pitchMultiplier: 1.0
        )
    }

    // MARK: - Initialization

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API

    /// Speak text with default configuration
    func speak(_ text: String) async {
        await speak(text, config: .questionPace)
    }

    /// Speak text with custom configuration
    func speak(_ text: String, config: VoiceConfig) async {
        await withCheckedContinuation { continuation in
            speak(text, config: config) {
                continuation.resume()
            }
        }
    }

    /// Speak text with completion handler
    func speak(_ text: String, config: VoiceConfig = .questionPace, completion: (() -> Void)? = nil) {
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = config.rate
        utterance.pitchMultiplier = config.pitchMultiplier
        utterance.volume = config.volume
        utterance.preUtteranceDelay = config.preUtteranceDelay
        utterance.postUtteranceDelay = config.postUtteranceDelay

        // Select voice
        if let voice = AVSpeechSynthesisVoice(language: config.language) {
            utterance.voice = voice
        }

        currentUtterance = utterance
        completionHandler = completion
        progress = 0
        isSpeaking = true
        isPaused = false

        logger.debug("Speaking: \(text.prefix(50))...")
        synthesizer.speak(utterance)
    }

    /// Speak a Knowledge Bowl question
    func speakQuestion(_ question: KBQuestion, config: VoiceConfig = .questionPace) async {
        await speak(question.text, config: config)
    }

    /// Pause speech
    func pause() {
        guard synthesizer.isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        logger.debug("Speech paused")
    }

    /// Resume speech
    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
        logger.debug("Speech resumed")
    }

    /// Stop speech immediately
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        progress = 0
        currentUtterance = nil
        completionHandler = nil
        logger.debug("Speech stopped")
    }

    // MARK: - Available Voices

    /// Get available voices for a language
    static func availableVoices(for language: String = "en-US") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language.prefix(2)) }
    }

    /// Get the best quality voice for a language
    static func bestVoice(for language: String = "en-US") -> AVSpeechSynthesisVoice? {
        let voices = availableVoices(for: language)

        // Prefer enhanced or premium voices
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }

        // Fall back to default
        return AVSpeechSynthesisVoice(language: language)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension KBOnDeviceTTS: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isSpeaking = true
            logger.debug("Speech started")
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isSpeaking = false
            isPaused = false
            progress = 1.0
            logger.debug("Speech finished")
            completionHandler?()
            completionHandler = nil
            currentUtterance = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isSpeaking = false
            isPaused = false
            progress = 0
            logger.debug("Speech cancelled")
            completionHandler = nil
            currentUtterance = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        // Capture values before entering Task to avoid data race
        let totalLength = Float(utterance.speechString.count)
        let currentPosition = Float(characterRange.location + characterRange.length)
        let newProgress = currentPosition / totalLength
        Task { @MainActor in
            progress = newProgress
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isPaused = true
            logger.debug("Speech paused (delegate)")
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isPaused = false
            logger.debug("Speech continued (delegate)")
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension KBOnDeviceTTS {
    /// Create a TTS instance for previews
    static func preview() -> KBOnDeviceTTS {
        KBOnDeviceTTS()
    }
}
#endif
