// UnaMentis - PlayableSegment Tests
// Unit tests for PlayableSegment protocol, CachedSegmentAudio,
// and module-specific adapter types.

import XCTest
@testable import UnaMentis

// MARK: - CachedSegmentAudio Tests

final class CachedSegmentAudioTests: XCTestCase {

    func testInit_setsProperties() {
        let data = Data(repeating: 0x42, count: 100)
        let cached = CachedSegmentAudio(audioData: data, sampleRate: 24000, channels: 2)

        XCTAssertEqual(cached.audioData.count, 100)
        XCTAssertEqual(cached.sampleRate, 24000)
        XCTAssertEqual(cached.channels, 2)
    }

    func testInit_defaultsToMonoChannel() {
        let cached = CachedSegmentAudio(audioData: Data(), sampleRate: 48000)
        XCTAssertEqual(cached.channels, 1)
    }

    func testToTTSAudioChunk_createsValidChunk() {
        let data = Data(repeating: 0x00, count: 9600)
        let cached = CachedSegmentAudio(audioData: data, sampleRate: 24000)

        let chunk = cached.toTTSAudioChunk()

        XCTAssertEqual(chunk.audioData, data)
        XCTAssertTrue(chunk.isFirst)
        XCTAssertTrue(chunk.isLast)
        XCTAssertEqual(chunk.sequenceNumber, 0)
    }

    func testToTTSAudioChunk_respectsSequenceNumber() {
        let cached = CachedSegmentAudio(audioData: Data(count: 100), sampleRate: 24000)
        let chunk = cached.toTTSAudioChunk(sequenceNumber: 5)

        XCTAssertEqual(chunk.sequenceNumber, 5)
    }
}

// MARK: - ReadingChunkData PlayableSegment Conformance Tests

final class ReadingChunkDataSegmentTests: XCTestCase {

    func testSegmentIndex_returnsChunkIndex() {
        let chunk = ReadingChunkData(
            index: 7,
            text: "Test text",
            characterOffset: 100,
            estimatedDurationSeconds: 5.0
        )

        XCTAssertEqual(chunk.segmentIndex, 7)
    }

    func testSegmentText_returnsChunkText() {
        let chunk = ReadingChunkData(
            index: 0,
            text: "The quick brown fox",
            characterOffset: 0,
            estimatedDurationSeconds: 3.0
        )

        XCTAssertEqual(chunk.segmentText, "The quick brown fox")
    }

    func testCachedAudio_whenNoCachedData_returnsNil() {
        let chunk = ReadingChunkData(
            index: 0,
            text: "No audio",
            characterOffset: 0,
            estimatedDurationSeconds: 2.0
        )

        XCTAssertNil(chunk.cachedAudio)
    }

    func testCachedAudio_whenHasCachedData_returnsCachedSegmentAudio() {
        let audioData = Data(repeating: 0x42, count: 9600)
        let chunk = ReadingChunkData(
            index: 0,
            text: "Has audio",
            characterOffset: 0,
            estimatedDurationSeconds: 2.0,
            cachedAudioData: audioData,
            cachedAudioSampleRate: 24000
        )

        XCTAssertNotNil(chunk.cachedAudio)
        XCTAssertEqual(chunk.cachedAudio?.audioData, audioData)
        XCTAssertEqual(chunk.cachedAudio?.sampleRate, 24000)
    }

    func testCachedAudio_whenSampleRateZero_returnsNil() {
        let chunk = ReadingChunkData(
            index: 0,
            text: "Bad rate",
            characterOffset: 0,
            estimatedDurationSeconds: 2.0,
            cachedAudioData: Data(count: 100),
            cachedAudioSampleRate: 0
        )

        XCTAssertNil(chunk.cachedAudio)
    }

    func testHasCachedAudio_whenPresent_returnsTrue() {
        let chunk = ReadingChunkData(
            index: 0,
            text: "Test",
            characterOffset: 0,
            estimatedDurationSeconds: 1.0,
            cachedAudioData: Data(count: 100),
            cachedAudioSampleRate: 24000
        )

        XCTAssertTrue(chunk.hasCachedAudio)
    }

    func testHasCachedAudio_whenAbsent_returnsFalse() {
        let chunk = ReadingChunkData(
            index: 0,
            text: "Test",
            characterOffset: 0,
            estimatedDurationSeconds: 1.0
        )

        XCTAssertFalse(chunk.hasCachedAudio)
    }
}

// NOTE: KBTextSegment tests are omitted because KBVoiceCoordinator.swift is
// excluded from the build in project.yml (Modules/KnowledgeBowl/Services/**).

// MARK: - SessionSentenceSegment Tests

final class SessionSentenceSegmentTests: XCTestCase {

    func testInit_setsIndexAndText() {
        let segment = SessionSentenceSegment(index: 3, text: "This is a sentence from the LLM.")

        XCTAssertEqual(segment.segmentIndex, 3)
        XCTAssertEqual(segment.segmentText, "This is a sentence from the LLM.")
    }

    func testCachedAudio_isAlwaysNil() {
        // Session segments are always synthesized live (no pre-generated audio)
        let segment = SessionSentenceSegment(index: 0, text: "Hello")
        XCTAssertNil(segment.cachedAudio)
    }
}

// MARK: - PlaybackOrchestratorConfig Tests

final class PlaybackOrchestratorConfigTests: XCTestCase {

    func testCustomConfig_setsAllFields() {
        let config = PlaybackOrchestratorConfig(
            prefetchDepth: 10,
            interSegmentSilenceMs: 250,
            retainBehindCount: 3,
            bufferTimeoutSeconds: 30
        )

        XCTAssertEqual(config.prefetchDepth, 10)
        XCTAssertEqual(config.interSegmentSilenceMs, 250)
        XCTAssertEqual(config.retainBehindCount, 3)
        XCTAssertEqual(config.bufferTimeoutSeconds, 30)
    }
}

// MARK: - PlaybackOrchestratorDelegate Default Tests

/// Concrete delegate with no overrides to test default implementations
private final class NoOpDelegate: PlaybackOrchestratorDelegate, @unchecked Sendable {}

final class PlaybackOrchestratorDelegateDefaultTests: XCTestCase {

    func testDefaultWillPlaySegment_returnsTrue() async {
        let delegate = NoOpDelegate()
        let result = await delegate.orchestratorWillPlaySegment(at: 0)
        XCTAssertTrue(result, "Default willPlaySegment should return true")
    }

    func testDefaultMethods_doNotCrash() async {
        let delegate = NoOpDelegate()

        // All default implementations should be no-ops and not crash
        await delegate.orchestratorDidFinishSegment(at: 0)
        await delegate.orchestratorDidChangeSegment(index: 1, total: 5)
        await delegate.orchestratorDidComplete()
        await delegate.orchestratorDidEncounterError(TTSError.synthesizeFailed("test"))
    }
}
