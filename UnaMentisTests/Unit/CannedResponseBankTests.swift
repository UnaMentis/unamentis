//
//  CannedResponseBankTests.swift
//  UnaMentisTests
//
//  Unit tests for CannedResponseBank actor
//

import XCTest
@testable import UnaMentis

/// Tests for CannedResponseBank pre-rendered TTS clip management
final class CannedResponseBankTests: XCTestCase {

    // MARK: - Initialization

    func testInitialState() async {
        let bank = CannedResponseBank()

        let isReady = await bank.isReady
        XCTAssertFalse(isReady, "Bank should not be ready before population")

        let clip = await bank.getResponse(for: .engagement)
        XCTAssertNil(clip, "Should return nil before population")
    }

    // MARK: - Population

    func testPopulateWithMockTTS() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)

        await bank.populate(using: mockTTS)

        let isReady = await bank.isReady
        XCTAssertTrue(isReady, "Bank should be ready after population")
    }

    func testPopulateRendersAllIntents() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)

        await bank.populate(using: mockTTS)

        // Each intent should have at least one clip
        for intent in ResponseIntent.allCases {
            let clip = await bank.getResponse(for: intent)
            XCTAssertNotNil(clip, "\(intent) should have clips after population")
        }
    }

    func testPopulateTracksAllSynthesizeCalls() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)

        await bank.populate(using: mockTTS)

        // Total phrases across all intents
        let totalPhrases = ResponseIntent.allCases.reduce(0) { $0 + $1.phrases.count }
        let callCount = await mockTTS.synthesizeCallCount
        XCTAssertEqual(callCount, totalPhrases, "Should synthesize every phrase")
    }

    // MARK: - Response Selection

    func testGetResponseReturnsClip() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)
        await bank.populate(using: mockTTS)

        let clip = await bank.getResponse(for: .engagement)
        XCTAssertNotNil(clip)
        XCTAssertEqual(clip?.intent, .engagement)
        XCTAssertFalse(clip?.text.isEmpty ?? true)
        XCTAssertFalse(clip?.audioData.isEmpty ?? true)
    }

    func testGetResponseAvoidsDuplicates() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)
        await bank.populate(using: mockTTS)

        // Get multiple responses and verify variety
        var texts: Set<String> = []
        for _ in 0..<10 {
            if let clip = await bank.getResponse(for: .engagement) {
                texts.insert(clip.text)
            }
        }

        // Should see more than 1 unique text (randomization + recently-used tracking)
        XCTAssertGreaterThan(texts.count, 1, "Should vary responses to avoid repetition")
    }

    func testGetResponseReturnsValidPhrase() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)
        await bank.populate(using: mockTTS)

        for intent in ResponseIntent.allCases {
            if let clip = await bank.getResponse(for: intent) {
                XCTAssertTrue(
                    intent.phrases.contains(clip.text),
                    "Clip text '\(clip.text)' should be from \(intent) phrases"
                )
            }
        }
    }

    // MARK: - Utterance-Based Selection

    func testGetResponseForUtterance() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)
        await bank.populate(using: mockTTS)

        let clip = await bank.getResponse(forUtterance: "I don't understand this")
        XCTAssertNotNil(clip)
        XCTAssertEqual(clip?.intent, .clarification)
    }

    func testGetResponseForTransitionUtterance() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)
        await bank.populate(using: mockTTS)

        let clip = await bank.getResponse(forUtterance: "Let's move on to the next topic")
        XCTAssertNotNil(clip)
        XCTAssertEqual(clip?.intent, .transition)
    }

    // MARK: - Clear

    func testClearResetsBank() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)
        await bank.populate(using: mockTTS)

        let isReadyBefore = await bank.isReady
        XCTAssertTrue(isReadyBefore)

        await bank.clear()

        let isReadyAfter = await bank.isReady
        XCTAssertFalse(isReadyAfter, "Bank should not be ready after clear")

        let clip = await bank.getResponse(for: .engagement)
        XCTAssertNil(clip, "Should return nil after clear")
    }

    // MARK: - Error Handling

    func testPopulateHandlesTTSErrors() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)
        await mockTTS.configureToFail(with: TTSError.synthesizeFailed("Test error"))

        await bank.populate(using: mockTTS)

        let isReady = await bank.isReady
        XCTAssertFalse(isReady, "Bank should not be ready when all synthesize calls fail")
    }

    // MARK: - Audio Clip Properties

    func testAudioClipHasPositiveDuration() async {
        let bank = CannedResponseBank()
        let mockTTS = MockTTSService() // ALLOWED: paid external API mock (TTS providers cost per character or require hardware)
        await bank.populate(using: mockTTS)

        if let clip = await bank.getResponse(for: .engagement) {
            XCTAssertGreaterThan(clip.duration, 0, "Clip should have positive duration")
        }
    }
}
