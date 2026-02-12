//
//  VoiceActivityFeedback.swift
//  UnaMentis
//
//  General-purpose audio and haptic feedback for voice-first activities.
//  Provides announcements via configured TTS and quick feedback via system sounds/haptics.
//  See docs/design/HANDS_FREE_FIRST_DESIGN.md
//

import AVFoundation
import OSLog
import UIKit

// MARK: - Feedback Tone

/// System sounds for quick feedback (no TTS latency)
public enum FeedbackTone: Sendable {
    case commandRecognized    // Subtle confirmation
    case commandInvalid       // Brief error tone
    case countdownTick        // Countdown tick sound
    case correct              // Success chime
    case incorrect            // Failure tone
    case attention            // Get user's attention
    case bookmarkSaved        // Bookmark created confirmation
    case flaggedForReview     // Flagged for review confirmation
}

// MARK: - Voice Activity Feedback

/// Provides audio and haptic feedback for voice-first activities.
///
/// Two feedback modes:
/// 1. **TTS Announcements**: For state changes, instructions, results (uses configured TTS provider)
/// 2. **System Tones**: For quick acknowledgments, countdowns (instant playback)
///
/// All feedback is designed to work with:
/// - Hands-free scenarios (driving, cooking)
/// - VoiceOver enabled (accessibility)
/// - Sound off (haptic fallback)
@MainActor
public final class VoiceActivityFeedback: ObservableObject {
    private let logger = Logger(subsystem: "com.unamentis", category: "VoiceActivityFeedback")

    // MARK: - Configuration

    /// Whether audio announcements are enabled
    @Published public var audioEnabled: Bool = true

    /// Whether haptic feedback is enabled
    @Published public var hapticsEnabled: Bool = true

    /// Speech rate for announcements (0.5 - 2.0)
    @Published public var speechRate: Float = 1.1

    // MARK: - Private State

    private var soundIDs: [FeedbackTone: SystemSoundID] = [:]
    private var announcementPlayer: AVAudioPlayer?
    private var currentSpeakingTask: Task<Void, Never>?
    @Published private var _isSpeaking: Bool = false

    // Haptic generators (reused for performance)
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    // MARK: - Initialization

    public init() {
        setupSystemSounds()
        prepareHaptics()
    }

    deinit {
        // Clean up system sounds
        for soundID in soundIDs.values {
            AudioServicesDisposeSystemSoundID(soundID)
        }
    }

    // MARK: - Public API: Announcements

    /// Speak an announcement via the configured TTS provider
    /// - Parameter text: Text to speak
    /// - Parameter priority: If true, interrupts current speech
    public func announce(_ text: String, priority: Bool = false) {
        guard audioEnabled else {
            logger.debug("Audio disabled, skipping announcement: \(text)")
            return
        }

        if priority {
            stopSpeaking()
        }

        // Fire-and-forget async TTS
        currentSpeakingTask = Task { [weak self] in
            await self?.speakWithConfiguredTTS(text)
        }

        logger.debug("Announced: \(text)")
    }

    /// Announce countdown start
    /// - Parameters:
    ///   - seconds: Total countdown seconds
    ///   - context: Activity context (e.g., "conference time")
    public func announceCountdownStart(seconds: Int, context: String) {
        announce("\(context). \(seconds) seconds.", priority: true)
        impactHaptic()
    }

    /// Announce countdown milestone
    /// - Parameter seconds: Remaining seconds
    public func announceCountdownMilestone(seconds: Int) {
        announce("\(seconds) seconds")
    }

    /// Announce countdown complete
    /// - Parameter context: What happens next (e.g., "Ready to answer")
    public func announceCountdownComplete(context: String) {
        announce("Time. \(context)", priority: true)
        notificationHaptic(.warning)
    }

    /// Announce command was recognized
    /// - Parameter command: The recognized command
    public func announceCommandRecognized(_ command: VoiceCommand) {
        playTone(.commandRecognized)
        selectionHaptic()
        // Don't TTS the command name - the action itself confirms it
    }

    /// Announce bookmark was saved (quick, non-disruptive)
    public func announceBookmarkSaved() {
        playTone(.bookmarkSaved)
        selectionHaptic()
    }

    /// Announce item was flagged for review (slightly more prominent)
    public func announceFlaggedForReview() {
        playTone(.flaggedForReview)
        impactHaptic(style: .medium)
    }

    /// Announce that answer was received
    public func announceAnswerReceived() {
        announce("Answer received", priority: false)
        selectionHaptic()
    }

    /// Announce correct answer
    public func announceCorrect() {
        playTone(.correct)
        notificationHaptic(.success)
        announce("Correct!")
    }

    /// Announce incorrect answer
    /// - Parameter correctAnswer: The correct answer to announce (optional)
    public func announceIncorrect(correctAnswer: String? = nil) {
        playTone(.incorrect)
        notificationHaptic(.error)
        if let answer = correctAnswer {
            announce("The answer was \(answer)")
        } else {
            announce("Incorrect")
        }
    }

    /// Announce activity started
    /// - Parameter name: Activity name
    public func announceActivityStarted(_ name: String) {
        announce("\(name) started", priority: true)
        impactHaptic()
    }

    /// Announce activity completed
    /// - Parameter summary: Completion summary
    public func announceActivityCompleted(_ summary: String) {
        announce(summary, priority: true)
        notificationHaptic(.success)
    }

    /// Announce next question
    /// - Parameters:
    ///   - number: Question number
    ///   - total: Total questions
    public func announceNextQuestion(number: Int, total: Int) {
        announce("Question \(number) of \(total)")
    }

    // MARK: - Public API: Tones

    /// Play a feedback tone (instant, no TTS latency)
    /// - Parameter tone: The tone to play
    public func playTone(_ tone: FeedbackTone) {
        guard audioEnabled else { return }

        if let soundID = soundIDs[tone] {
            AudioServicesPlaySystemSound(soundID)
            logger.debug("Played tone: \(String(describing: tone))")
        } else {
            // Fallback to system sounds
            playFallbackTone(tone)
        }

        // Always provide haptic with tone
        playToneHaptic(tone)
    }

    /// Play countdown tick with haptic
    public func playCountdownTick() {
        playTone(.countdownTick)
        impactHaptic(style: .light)
    }

    // MARK: - Public API: Haptics

    /// Trigger impact haptic
    /// - Parameter style: Impact style
    public func impactHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    /// Trigger notification haptic
    /// - Parameter type: Notification type
    public func notificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard hapticsEnabled else { return }
        notificationGenerator.notificationOccurred(type)
    }

    /// Trigger selection haptic (light tap)
    public func selectionHaptic() {
        guard hapticsEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    // MARK: - Control

    /// Stop any ongoing speech
    public func stopSpeaking() {
        currentSpeakingTask?.cancel()
        currentSpeakingTask = nil
        announcementPlayer?.stop()
        announcementPlayer = nil
        _isSpeaking = false
    }

    /// Check if currently speaking
    public var isSpeaking: Bool {
        _isSpeaking
    }

    // MARK: - Private: TTS Synthesis

    /// Synthesize and play text using the configured TTS provider
    private func speakWithConfiguredTTS(_ text: String) async {
        _isSpeaking = true
        defer { _isSpeaking = false }

        let ttsService = TTSProvider.resolveConfiguredService()

        do {
            let stream = try await ttsService.synthesize(text: text)

            // Collect all audio chunks
            var audioData = Data()
            for await chunk in stream {
                guard !Task.isCancelled else { return }
                audioData.append(chunk.audioData)
            }

            guard !audioData.isEmpty, !Task.isCancelled else { return }

            // Play the collected audio
            announcementPlayer = try AVAudioPlayer(data: audioData)
            announcementPlayer?.play()

            // Wait for playback to complete
            if let duration = announcementPlayer?.duration {
                try await Task.sleep(for: .milliseconds(Int(duration * 1000) + 50))
            }

            announcementPlayer = nil
        } catch {
            guard !Task.isCancelled else { return }
            logger.warning("Configured TTS failed for announcement, falling back to Apple TTS: \(error.localizedDescription)")
            // Fall back to Apple TTS if the configured provider fails
            await speakWithAppleTTSFallback(text)
        }
    }

    /// Fallback to Apple TTS if the configured provider fails
    private func speakWithAppleTTSFallback(_ text: String) async {
        do {
            let appleTTS = AppleTTSService()
            let stream = try await appleTTS.synthesize(text: text)

            var audioData = Data()
            for await chunk in stream {
                guard !Task.isCancelled else { return }
                audioData.append(chunk.audioData)
            }

            guard !audioData.isEmpty, !Task.isCancelled else { return }

            announcementPlayer = try AVAudioPlayer(data: audioData)
            announcementPlayer?.play()

            if let duration = announcementPlayer?.duration {
                try await Task.sleep(for: .milliseconds(Int(duration * 1000) + 50))
            }

            announcementPlayer = nil
        } catch {
            logger.error("Apple TTS fallback also failed: \(error.localizedDescription)")
            announcementPlayer = nil
        }
    }

    // MARK: - Private Helpers

    private func setupSystemSounds() {
        // Map tones to system sound IDs
        // These are standard iOS system sounds
        soundIDs[.commandRecognized] = 1057  // Tink
        soundIDs[.commandInvalid] = 1053     // Key pressed (subtle)
        soundIDs[.countdownTick] = 1104      // Tock
        soundIDs[.correct] = 1025            // New mail
        soundIDs[.incorrect] = 1073          // Voicemail
        soundIDs[.attention] = 1007          // SMS received
        soundIDs[.bookmarkSaved] = 1054      // Subtle pop
        soundIDs[.flaggedForReview] = 1001   // Bloom (slightly more prominent)
    }

    private func prepareHaptics() {
        impactGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    private func playFallbackTone(_ tone: FeedbackTone) {
        // Use built-in system sounds as fallback
        let soundID: SystemSoundID
        switch tone {
        case .commandRecognized:
            soundID = 1057
        case .commandInvalid:
            soundID = 1053
        case .countdownTick:
            soundID = 1104
        case .correct:
            soundID = 1025
        case .incorrect:
            soundID = 1073
        case .attention:
            soundID = 1007
        case .bookmarkSaved:
            soundID = 1054
        case .flaggedForReview:
            soundID = 1001
        }
        AudioServicesPlaySystemSound(soundID)
    }

    private func playToneHaptic(_ tone: FeedbackTone) {
        guard hapticsEnabled else { return }

        switch tone {
        case .commandRecognized:
            selectionGenerator.selectionChanged()
        case .commandInvalid:
            notificationGenerator.notificationOccurred(.warning)
        case .countdownTick:
            impactGenerator.impactOccurred(intensity: 0.5)
        case .correct:
            notificationGenerator.notificationOccurred(.success)
        case .incorrect:
            notificationGenerator.notificationOccurred(.error)
        case .attention:
            impactGenerator.impactOccurred(intensity: 1.0)
        case .bookmarkSaved:
            selectionGenerator.selectionChanged()
        case .flaggedForReview:
            impactGenerator.impactOccurred(intensity: 0.7)
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension VoiceActivityFeedback {
    public static func preview() -> VoiceActivityFeedback {
        VoiceActivityFeedback()
    }
}
#endif
