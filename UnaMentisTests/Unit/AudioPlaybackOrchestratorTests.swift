// UnaMentis - AudioPlaybackOrchestrator Tests
// Unit tests for the shared audio playback pipeline.
//
// Tests cover: state machine, playback loop, prefetch, pause/resume,
// dynamic segment append, config presets, delegate callbacks, error handling.

import XCTest
@testable import UnaMentis

// MARK: - Test Segment

/// Minimal PlayableSegment for testing
private struct TestSegment: PlayableSegment {
    let segmentIndex: Int
    let segmentText: String
    let cachedAudio: CachedSegmentAudio?

    init(index: Int, text: String, cached: CachedSegmentAudio? = nil) {
        self.segmentIndex = index
        self.segmentText = text
        self.cachedAudio = cached
    }
}

// MARK: - Test Delegate

/// Spy delegate that records all callbacks
private final class TestDelegate: PlaybackOrchestratorDelegate, @unchecked Sendable {
    var willPlaySegmentCalls: [Int] = []
    var didFinishSegmentCalls: [Int] = []
    var didChangeSegmentCalls: [(index: Int, total: Int)] = []
    var didCompleteCalled = false
    var errors: [Error] = []

    /// Segments to skip (return false from willPlaySegment)
    var segmentsToSkip: Set<Int> = []

    func orchestratorWillPlaySegment(at index: Int) async -> Bool {
        willPlaySegmentCalls.append(index)
        return !segmentsToSkip.contains(index)
    }

    func orchestratorDidFinishSegment(at index: Int) async {
        didFinishSegmentCalls.append(index)
    }

    func orchestratorDidChangeSegment(index: Int, total: Int) async {
        didChangeSegmentCalls.append((index: index, total: total))
    }

    func orchestratorDidComplete() async {
        didCompleteCalled = true
    }

    func orchestratorDidEncounterError(_ error: Error) async {
        errors.append(error)
    }

    func reset() {
        willPlaySegmentCalls = []
        didFinishSegmentCalls = []
        didChangeSegmentCalls = []
        didCompleteCalled = false
        errors = []
        segmentsToSkip = []
    }
}

// MARK: - AudioPlaybackOrchestrator Tests

final class AudioPlaybackOrchestratorTests: XCTestCase {

    // MARK: - Properties

    private var mockTTS: MockTTSService!
    private var audioEngine: AudioEngine!
    private var mockVAD: MockVADService!
    private var telemetry: TelemetryEngine!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockTTS = MockTTSService()
        mockVAD = MockVADService()
        telemetry = TelemetryEngine()
        audioEngine = AudioEngine(config: .default, vadService: mockVAD, telemetry: telemetry)
        try await audioEngine.configure(config: .default)
    }

    override func tearDown() async throws {
        await audioEngine.stop()
        audioEngine = nil
        mockTTS = nil
        mockVAD = nil
        telemetry = nil
        try await super.tearDown()
    }

    // MARK: - Helper

    private func makeOrchestrator(
        config: PlaybackOrchestratorConfig = .default
    ) -> AudioPlaybackOrchestrator {
        AudioPlaybackOrchestrator(
            config: config,
            ttsService: mockTTS,
            audioEngine: audioEngine
        )
    }

    // MARK: - Initial State

    func testInit_stateIsIdle() async {
        let orch = makeOrchestrator()
        let state = await orch.state
        XCTAssertEqual(state, .idle)
    }

    func testInit_currentIndexIsZero() async {
        let orch = makeOrchestrator()
        let index = await orch.currentIndex
        XCTAssertEqual(index, 0)
    }

    // MARK: - Config Presets

    func testConfigDefault_hasExpectedValues() {
        let config = PlaybackOrchestratorConfig.default
        XCTAssertEqual(config.prefetchDepth, 3)
        XCTAssertEqual(config.interSegmentSilenceMs, 0)
        XCTAssertEqual(config.retainBehindCount, 0)
        XCTAssertEqual(config.bufferTimeoutSeconds, 10)
    }

    func testConfigReadingList_hasExpectedValues() {
        let config = PlaybackOrchestratorConfig.readingList
        XCTAssertEqual(config.prefetchDepth, 5)
        XCTAssertEqual(config.interSegmentSilenceMs, 600)
        XCTAssertEqual(config.retainBehindCount, 6)
        XCTAssertEqual(config.bufferTimeoutSeconds, 10)
    }

    func testConfigSession_hasExpectedValues() {
        let config = PlaybackOrchestratorConfig.session
        XCTAssertEqual(config.prefetchDepth, 2)
        XCTAssertEqual(config.interSegmentSilenceMs, 0)
        XCTAssertEqual(config.retainBehindCount, 0)
        XCTAssertEqual(config.bufferTimeoutSeconds, 15)
    }

    func testConfigKnowledgeBowl_hasExpectedValues() {
        let config = PlaybackOrchestratorConfig.knowledgeBowl
        XCTAssertEqual(config.prefetchDepth, 0)
        XCTAssertEqual(config.interSegmentSilenceMs, 0)
        XCTAssertEqual(config.retainBehindCount, 0)
        XCTAssertEqual(config.bufferTimeoutSeconds, 10)
    }

    // MARK: - Load Segments

    func testLoadSegments_setsSegments() async {
        let orch = makeOrchestrator()
        let segments = [
            TestSegment(index: 0, text: "Hello"),
            TestSegment(index: 1, text: "World")
        ]
        await orch.loadSegments(segments)

        // State should still be idle after loading
        let state = await orch.state
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Start Playback

    func testStartPlayback_transitionsToPlaying() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)
        let segments = [TestSegment(index: 0, text: "Test")]
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        // Give the playback loop a moment to start
        try? await Task.sleep(for: .milliseconds(50))

        let state = await orch.state
        // Should be playing or completed (single segment with KB config)
        XCTAssertTrue(state == .playing || state == .completed)
    }

    func testStartPlayback_fromMiddle_setsCurrentIndex() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)
        let segments = (0..<5).map { TestSegment(index: $0, text: "Segment \($0)") }
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 3)

        let index = await orch.currentIndex
        XCTAssertEqual(index, 3)
    }

    // MARK: - Stop Playback

    func testStopPlayback_transitionsToIdle() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)
        let segments = [TestSegment(index: 0, text: "Test sentence for playback")]
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        try? await Task.sleep(for: .milliseconds(50))
        await orch.stopPlayback()

        let state = await orch.state
        XCTAssertEqual(state, .idle)
    }

    func testStopPlayback_resetsCurrentIndex() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)
        let segments = (0..<3).map { TestSegment(index: $0, text: "Segment \($0)") }
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 2)

        try? await Task.sleep(for: .milliseconds(50))
        await orch.stopPlayback()

        let index = await orch.currentIndex
        XCTAssertEqual(index, 0)
    }

    // MARK: - Pause / Resume

    func testPausePlayback_transitionsToPaused() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)
        await mockTTS.configureStreaming(chunks: 5, bytesPerChunk: 9600)
        await mockTTS.enableLatencySimulation(ttftMs: 0, tokenDelayMs: 200)

        let segments = (0..<5).map { TestSegment(index: $0, text: "Segment \($0)") }
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        // Give it time to start playing
        try? await Task.sleep(for: .milliseconds(100))
        await orch.pausePlayback()

        let state = await orch.state
        XCTAssertEqual(state, .paused)
    }

    func testResumePlayback_whenPaused_transitionsToPlaying() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)
        await mockTTS.configureStreaming(chunks: 5, bytesPerChunk: 9600)
        await mockTTS.enableLatencySimulation(ttftMs: 0, tokenDelayMs: 200)

        let segments = (0..<5).map { TestSegment(index: $0, text: "Segment \($0)") }
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        try? await Task.sleep(for: .milliseconds(100))
        await orch.pausePlayback()
        await orch.resumePlayback()

        let state = await orch.state
        XCTAssertEqual(state, .playing)
    }

    func testResumePlayback_whenNotPaused_doesNothing() async {
        let orch = makeOrchestrator()
        await orch.resumePlayback()

        let state = await orch.state
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Suspend

    func testSuspendPlayback_transitionsToPaused() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)
        await mockTTS.configureStreaming(chunks: 5, bytesPerChunk: 9600)
        await mockTTS.enableLatencySimulation(ttftMs: 0, tokenDelayMs: 200)

        let segments = (0..<5).map { TestSegment(index: $0, text: "Segment \($0)") }
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        try? await Task.sleep(for: .milliseconds(100))
        await orch.suspendPlayback()

        let state = await orch.state
        XCTAssertEqual(state, .paused)
    }

    // MARK: - Delegate Callbacks

    func testDelegate_didComplete_calledWhenAllSegmentsPlayed() async {
        let delegate = TestDelegate()
        let orch = makeOrchestrator(config: .knowledgeBowl)
        await orch.setDelegate(delegate)

        let segments = [TestSegment(index: 0, text: "Single segment")]
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed { break }
        }

        XCTAssertTrue(delegate.didCompleteCalled)
    }

    func testDelegate_didFinishSegment_calledForEachSegment() async {
        let delegate = TestDelegate()
        let orch = makeOrchestrator(config: .knowledgeBowl)
        await orch.setDelegate(delegate)

        let segments = [
            TestSegment(index: 0, text: "First"),
            TestSegment(index: 1, text: "Second")
        ]
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed { break }
        }

        XCTAssertEqual(delegate.didFinishSegmentCalls.count, 2)
        XCTAssertEqual(delegate.didFinishSegmentCalls, [0, 1])
    }

    func testDelegate_willPlaySegment_canSkipSegments() async {
        let delegate = TestDelegate()
        delegate.segmentsToSkip = [1]

        let orch = makeOrchestrator(config: .knowledgeBowl)
        await orch.setDelegate(delegate)

        let segments = [
            TestSegment(index: 0, text: "First"),
            TestSegment(index: 1, text: "Skip me"),
            TestSegment(index: 2, text: "Third")
        ]
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed { break }
        }

        // Segment 1 should not appear in didFinish
        XCTAssertFalse(delegate.didFinishSegmentCalls.contains(1))
        XCTAssertTrue(delegate.didCompleteCalled)
    }

    func testDelegate_didEncounterError_calledOnTTSFailure() async {
        let delegate = TestDelegate()
        let orch = makeOrchestrator(config: .knowledgeBowl)
        await orch.setDelegate(delegate)

        // Make TTS fail
        await mockTTS.configureToFail(with: .connectionFailed("test error"))

        let segments = [TestSegment(index: 0, text: "Will fail")]
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        // Wait for completion (should complete after error, since it skips failed segments)
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed || state == .idle { break }
        }

        XCTAssertFalse(delegate.errors.isEmpty, "Should have received an error callback")
    }

    // MARK: - Dynamic Segment Append

    func testAppendSegments_addsToExistingSegments() async {
        let orch = makeOrchestrator(config: .session)
        await orch.setExpectsMoreSegments(true)

        // Start with one segment
        let initial = [TestSegment(index: 0, text: "First")]
        await orch.loadSegments(initial)
        await orch.startPlayback(from: 0)

        try? await Task.sleep(for: .milliseconds(100))

        // Append more
        let additional = [TestSegment(index: 1, text: "Second")]
        await orch.appendSegments(additional)

        // Signal done
        await orch.signalNoMoreSegments()

        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed { break }
        }

        let state = await orch.state
        XCTAssertEqual(state, .completed)
    }

    func testSetExpectsMoreSegments_false_signalsNoMore() async {
        let orch = makeOrchestrator(config: .session)
        await orch.setExpectsMoreSegments(true)

        let segments = [TestSegment(index: 0, text: "Only one")]
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        try? await Task.sleep(for: .milliseconds(100))

        // Signal no more by setting expectation to false
        await orch.setExpectsMoreSegments(false)

        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed { break }
        }

        let state = await orch.state
        XCTAssertEqual(state, .completed)
    }

    // MARK: - Cached Audio Path

    func testPlaySegment_withCachedAudio_skipsTTS() async {
        let cachedAudio = CachedSegmentAudio(
            audioData: Data(count: 9600),
            sampleRate: 24000
        )
        let segment = TestSegment(index: 0, text: "Has cache", cached: cachedAudio)

        let orch = makeOrchestrator(config: .knowledgeBowl)
        await orch.loadSegments([segment])
        await orch.startPlayback(from: 0)

        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed { break }
        }

        // TTS should NOT have been called
        let callCount = await mockTTS.synthesizeCallCount
        XCTAssertEqual(callCount, 0, "TTS should be skipped when cached audio is present")
    }

    func testPlaySegment_withoutCachedAudio_usesTTS() async {
        let segment = TestSegment(index: 0, text: "No cache")

        let orch = makeOrchestrator(config: .knowledgeBowl)
        await orch.loadSegments([segment])
        await orch.startPlayback(from: 0)

        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed { break }
        }

        let callCount = await mockTTS.synthesizeCallCount
        XCTAssertGreaterThanOrEqual(callCount, 1, "TTS should be called when no cached audio")
    }

    // MARK: - TTS Call Tracking

    func testSynthesizeCallsPassCorrectText() async {
        let segment = TestSegment(index: 0, text: "Specific text to verify")

        let orch = makeOrchestrator(config: .knowledgeBowl)
        await orch.loadSegments([segment])
        await orch.startPlayback(from: 0)

        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed { break }
        }

        let texts = await mockTTS.synthesizedTexts
        XCTAssertTrue(texts.contains("Specific text to verify"))
    }

    // MARK: - State Machine

    func testStateTransitions_idleToPlayingToCompleted() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)

        var state = await orch.state
        XCTAssertEqual(state, .idle)

        let segments = [TestSegment(index: 0, text: "Test")]
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        // Wait for completion
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            state = await orch.state
            if state == .completed { break }
        }

        XCTAssertEqual(state, .completed)
    }

    func testStopFromPlaying_goesToIdle() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)
        await mockTTS.enableLatencySimulation(ttftMs: 0, tokenDelayMs: 500)

        let segments = (0..<10).map { TestSegment(index: $0, text: "Segment \($0)") }
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        try? await Task.sleep(for: .milliseconds(100))
        await orch.stopPlayback()

        let state = await orch.state
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Restart After Completion

    func testStartPlayback_afterCompletion_works() async {
        let orch = makeOrchestrator(config: .knowledgeBowl)

        // First playback
        let segments = [TestSegment(index: 0, text: "First run")]
        await orch.loadSegments(segments)
        await orch.startPlayback(from: 0)

        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            let state = await orch.state
            if state == .completed { break }
        }

        var state = await orch.state
        XCTAssertEqual(state, .completed)

        // Second playback
        let segments2 = [TestSegment(index: 0, text: "Second run")]
        await orch.loadSegments(segments2)
        await orch.startPlayback(from: 0)

        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            state = await orch.state
            if state == .completed { break }
        }

        XCTAssertEqual(state, .completed)
    }
}
