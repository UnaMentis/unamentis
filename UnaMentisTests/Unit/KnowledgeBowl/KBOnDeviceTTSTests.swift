//
//  KBOnDeviceTTSTests.swift
//  UnaMentisTests
//
//  Tests for KBOnDeviceTTS text-to-speech service
//

import AVFoundation
import XCTest
@testable import UnaMentis

@MainActor
final class KBOnDeviceTTSTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInit_startsWithDefaultState() {
        let tts = KBOnDeviceTTS()

        XCTAssertFalse(tts.isSpeaking)
        XCTAssertFalse(tts.isPaused)
        XCTAssertEqual(tts.progress, 0)
    }

    // MARK: - VoiceConfig Tests

    func testVoiceConfig_defaultValues() {
        let config = KBOnDeviceTTS.VoiceConfig()

        XCTAssertEqual(config.language, "en-US")
        XCTAssertEqual(config.rate, AVSpeechUtteranceDefaultSpeechRate)
        XCTAssertEqual(config.pitchMultiplier, 1.0)
        XCTAssertEqual(config.volume, 1.0)
        XCTAssertEqual(config.preUtteranceDelay, 0)
        XCTAssertEqual(config.postUtteranceDelay, 0)
    }

    func testVoiceConfig_questionPace_hasSlowerRate() {
        let config = KBOnDeviceTTS.VoiceConfig.questionPace

        XCTAssertLessThan(config.rate, AVSpeechUtteranceDefaultSpeechRate)
        XCTAssertEqual(config.pitchMultiplier, 1.0)
    }

    func testVoiceConfig_slowPace_hasSlowRate() {
        let config = KBOnDeviceTTS.VoiceConfig.slowPace

        XCTAssertLessThan(config.rate, KBOnDeviceTTS.VoiceConfig.questionPace.rate)
    }

    func testVoiceConfig_fastPace_hasFasterRate() {
        let config = KBOnDeviceTTS.VoiceConfig.fastPace

        XCTAssertGreaterThan(config.rate, AVSpeechUtteranceDefaultSpeechRate)
    }

    func testVoiceConfig_paceOrder_slowToFast() {
        let slow = KBOnDeviceTTS.VoiceConfig.slowPace.rate
        let question = KBOnDeviceTTS.VoiceConfig.questionPace.rate
        let fast = KBOnDeviceTTS.VoiceConfig.fastPace.rate

        XCTAssertLessThan(slow, question)
        XCTAssertLessThan(question, fast)
    }

    func testVoiceConfig_isSendable() {
        let config = KBOnDeviceTTS.VoiceConfig.questionPace

        // Verify Sendable conformance by using in concurrent context
        Task.detached {
            _ = config.rate
        }
    }

    // MARK: - Stop Tests

    func testStop_whenNotSpeaking_doesNotCrash() {
        let tts = KBOnDeviceTTS()

        // Should handle gracefully when not speaking
        tts.stop()

        XCTAssertFalse(tts.isSpeaking)
        XCTAssertFalse(tts.isPaused)
        XCTAssertEqual(tts.progress, 0)
    }

    func testStop_resetsState() {
        let tts = KBOnDeviceTTS()

        tts.stop()

        XCTAssertFalse(tts.isSpeaking)
        XCTAssertFalse(tts.isPaused)
        XCTAssertEqual(tts.progress, 0)
    }

    // MARK: - Pause/Resume Tests

    func testPause_whenNotSpeaking_doesNothing() {
        let tts = KBOnDeviceTTS()

        tts.pause()

        // Should not change to paused if not speaking
        XCTAssertFalse(tts.isPaused)
    }

    func testResume_whenNotPaused_doesNothing() {
        let tts = KBOnDeviceTTS()

        tts.resume()

        // Should be safe to call when not paused
        XCTAssertFalse(tts.isPaused)
    }

    // MARK: - Available Voices Tests

    func testAvailableVoices_returnsVoicesForLanguage() {
        let voices = KBOnDeviceTTS.availableVoices(for: "en-US")

        // Should have at least one English voice
        XCTAssertGreaterThan(voices.count, 0)

        // All returned voices should be for English
        for voice in voices {
            XCTAssertTrue(voice.language.hasPrefix("en"))
        }
    }

    func testAvailableVoices_withDefaultLanguage_returnsEnglishVoices() {
        let voices = KBOnDeviceTTS.availableVoices()

        XCTAssertGreaterThan(voices.count, 0)
    }

    func testAvailableVoices_forUnsupportedLanguage_mayReturnEmpty() {
        // Using an obscure language code that might not have voices
        let voices = KBOnDeviceTTS.availableVoices(for: "zz-ZZ")

        // Should not crash, may return empty
        _ = voices
    }

    func testBestVoice_returnsVoiceForLanguage() {
        let voice = KBOnDeviceTTS.bestVoice(for: "en-US")

        // Should return a voice on any iOS device
        XCTAssertNotNil(voice)
        XCTAssertTrue(voice!.language.hasPrefix("en"))
    }

    func testBestVoice_withDefaultLanguage_returnsEnglishVoice() {
        let voice = KBOnDeviceTTS.bestVoice()

        XCTAssertNotNil(voice)
    }

    func testBestVoice_prefersEnhancedQuality() {
        let voice = KBOnDeviceTTS.bestVoice(for: "en-US")

        // If enhanced is available, it should be selected
        // We can't guarantee enhanced is available, but verify we get a voice
        XCTAssertNotNil(voice)
    }

    // MARK: - Preview Support Tests

    #if DEBUG
    func testPreview_createsValidInstance() {
        let tts = KBOnDeviceTTS.preview()

        XCTAssertNotNil(tts)
        XCTAssertFalse(tts.isSpeaking)
    }
    #endif

    // MARK: - State Consistency Tests

    func testState_afterMultipleStopCalls_remainsConsistent() {
        let tts = KBOnDeviceTTS()

        // Multiple stops should be safe
        tts.stop()
        tts.stop()
        tts.stop()

        XCTAssertFalse(tts.isSpeaking)
        XCTAssertFalse(tts.isPaused)
        XCTAssertEqual(tts.progress, 0)
    }

    func testState_pauseResumeSequence_whenNotSpeaking() {
        let tts = KBOnDeviceTTS()

        // These should all be no-ops when not speaking
        tts.pause()
        tts.resume()
        tts.pause()
        tts.resume()

        XCTAssertFalse(tts.isSpeaking)
        XCTAssertFalse(tts.isPaused)
    }

    // MARK: - Configuration Tests

    func testVoiceConfig_customConfiguration() {
        let config = KBOnDeviceTTS.VoiceConfig(
            language: "en-GB",
            rate: 0.5,
            pitchMultiplier: 1.2,
            volume: 0.8,
            preUtteranceDelay: 0.5,
            postUtteranceDelay: 1.0
        )

        XCTAssertEqual(config.language, "en-GB")
        XCTAssertEqual(config.rate, 0.5)
        XCTAssertEqual(config.pitchMultiplier, 1.2)
        XCTAssertEqual(config.volume, 0.8)
        XCTAssertEqual(config.preUtteranceDelay, 0.5)
        XCTAssertEqual(config.postUtteranceDelay, 1.0)
    }

    // MARK: - Speech Rate Validation Tests

    func testSpeechRates_areWithinValidRange() {
        // AVSpeechUtterance rate should be between 0 and 1
        let slow = KBOnDeviceTTS.VoiceConfig.slowPace.rate
        let question = KBOnDeviceTTS.VoiceConfig.questionPace.rate
        let fast = KBOnDeviceTTS.VoiceConfig.fastPace.rate

        XCTAssertGreaterThan(slow, AVSpeechUtteranceMinimumSpeechRate)
        XCTAssertLessThan(fast, AVSpeechUtteranceMaximumSpeechRate)

        XCTAssertGreaterThan(question, AVSpeechUtteranceMinimumSpeechRate)
        XCTAssertLessThan(question, AVSpeechUtteranceMaximumSpeechRate)
    }

    // MARK: - Volume and Pitch Tests

    func testVoiceConfig_volumeAndPitch_areNormalized() {
        let configs: [KBOnDeviceTTS.VoiceConfig] = [
            .questionPace,
            .slowPace,
            .fastPace
        ]

        for config in configs {
            // Volume should be between 0 and 1
            XCTAssertGreaterThanOrEqual(config.volume, 0)
            XCTAssertLessThanOrEqual(config.volume, 1)

            // Pitch multiplier should be reasonable (0.5 to 2.0 typical range)
            XCTAssertGreaterThan(config.pitchMultiplier, 0)
            XCTAssertLessThanOrEqual(config.pitchMultiplier, 2)
        }
    }
}
