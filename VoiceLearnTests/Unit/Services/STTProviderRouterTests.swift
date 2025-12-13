// VoiceLearn - STTProviderRouter Tests
// Unit tests for STT Provider Routing with Failover (TDD)
//
// Tests cover:
// - Provider selection based on health
// - Failover behavior
// - Recovery to primary provider
// - STTService protocol conformance

import XCTest
import AVFoundation
@testable import VoiceLearn

@MainActor
final class STTProviderRouterTests: XCTestCase {

    // MARK: - Properties

    var mockGLMASR: MockSTTService!
    var mockDeepgram: MockSTTService!
    var mockHealthMonitor: MockHealthMonitor!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockGLMASR = MockSTTService(identifier: "glm-asr")
        mockDeepgram = MockSTTService(identifier: "deepgram")
        mockHealthMonitor = MockHealthMonitor()
    }

    override func tearDown() async throws {
        mockGLMASR = nil
        mockDeepgram = nil
        mockHealthMonitor = nil
        try await super.tearDown()
    }

    // MARK: - Provider Selection Tests

    func testSelectProvider_whenHealthy_returnsGLMASR() async {
        await mockHealthMonitor.setStatus(.healthy)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        let provider = await router.currentProviderIdentifier

        XCTAssertEqual(provider, "glm-asr")
    }

    func testSelectProvider_whenDegraded_returnsGLMASR() async {
        await mockHealthMonitor.setStatus(.degraded)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        let provider = await router.currentProviderIdentifier

        XCTAssertEqual(provider, "glm-asr")
    }

    func testSelectProvider_whenUnhealthy_returnsDeepgram() async {
        await mockHealthMonitor.setStatus(.unhealthy)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        let provider = await router.currentProviderIdentifier

        XCTAssertEqual(provider, "deepgram")
    }

    // MARK: - Streaming Tests

    func testStartStreaming_whenHealthy_usesGLMASR() async throws {
        await mockHealthMonitor.setStatus(.healthy)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        _ = try await router.startStreaming(audioFormat: format)

        let glmWasCalled = await mockGLMASR.startStreamingWasCalled
        let deepgramWasCalled = await mockDeepgram.startStreamingWasCalled

        XCTAssertTrue(glmWasCalled)
        XCTAssertFalse(deepgramWasCalled)

        await router.cancelStreaming()
    }

    func testStartStreaming_whenUnhealthy_usesDeepgram() async throws {
        await mockHealthMonitor.setStatus(.unhealthy)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        _ = try await router.startStreaming(audioFormat: format)

        let glmWasCalled = await mockGLMASR.startStreamingWasCalled
        let deepgramWasCalled = await mockDeepgram.startStreamingWasCalled

        XCTAssertFalse(glmWasCalled)
        XCTAssertTrue(deepgramWasCalled)

        await router.cancelStreaming()
    }

    // MARK: - Failover Tests

    func testHealthStatusChange_triggersFailover() async throws {
        await mockHealthMonitor.setStatus(.healthy)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        // Start streaming with healthy GLM-ASR
        _ = try await router.startStreaming(audioFormat: format)

        // Verify GLM-ASR was used
        var glmWasCalled = await mockGLMASR.startStreamingWasCalled
        XCTAssertTrue(glmWasCalled)

        // Cancel current session
        await router.cancelStreaming()

        // Reset mock call tracking
        await mockGLMASR.reset()
        await mockDeepgram.reset()

        // Change health status to unhealthy
        await mockHealthMonitor.setStatus(.unhealthy)

        // Start new streaming session
        _ = try await router.startStreaming(audioFormat: format)

        // Verify Deepgram was used this time
        glmWasCalled = await mockGLMASR.startStreamingWasCalled
        let deepgramWasCalled = await mockDeepgram.startStreamingWasCalled

        XCTAssertFalse(glmWasCalled, "GLM-ASR should not be used when unhealthy")
        XCTAssertTrue(deepgramWasCalled, "Deepgram should be used as fallback")

        await router.cancelStreaming()
    }

    func testRecovery_whenHealthyAgain_returnsToGLMASR() async throws {
        // Start unhealthy
        await mockHealthMonitor.setStatus(.unhealthy)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        // Start with Deepgram (fallback)
        _ = try await router.startStreaming(audioFormat: format)
        await router.cancelStreaming()
        await mockGLMASR.reset()
        await mockDeepgram.reset()

        // Recover to healthy
        await mockHealthMonitor.setStatus(.healthy)

        // Should now use GLM-ASR again
        _ = try await router.startStreaming(audioFormat: format)

        let glmWasCalled = await mockGLMASR.startStreamingWasCalled
        XCTAssertTrue(glmWasCalled, "Should return to GLM-ASR when healthy")

        await router.cancelStreaming()
    }

    // MARK: - Cost Passthrough Tests

    func testCostPerHour_whenHealthy_returnsGLMASRCost() async {
        await mockHealthMonitor.setStatus(.healthy)
        await mockGLMASR.setCostPerHour(0)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        let cost = await router.costPerHour

        XCTAssertEqual(cost, 0, "GLM-ASR is self-hosted, should be $0")
    }

    func testCostPerHour_whenUnhealthy_returnsDeepgramCost() async {
        await mockHealthMonitor.setStatus(.unhealthy)
        await mockDeepgram.setCostPerHour(Decimal(string: "0.258")!)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        let cost = await router.costPerHour

        XCTAssertEqual(cost, Decimal(string: "0.258"), "Should use Deepgram cost when failover")
    }

    // MARK: - Metrics Passthrough Tests

    func testMetrics_returnsActiveProviderMetrics() async {
        await mockHealthMonitor.setStatus(.healthy)

        let expectedMetrics = STTMetrics(
            medianLatency: 0.15,
            p99Latency: 0.35,
            wordEmissionRate: 2.5
        )
        await mockGLMASR.setMetrics(expectedMetrics)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        let metrics = await router.metrics

        XCTAssertEqual(metrics.medianLatency, expectedMetrics.medianLatency)
    }

    // MARK: - Protocol Conformance Tests

    func testIsStreaming_reflectsState() async {
        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealthMonitor
        )

        var isStreaming = await router.isStreaming
        XCTAssertFalse(isStreaming, "Should not be streaming initially")

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else { return }

        _ = try? await router.startStreaming(audioFormat: format)

        isStreaming = await router.isStreaming
        XCTAssertTrue(isStreaming, "Should be streaming after start")

        await router.cancelStreaming()

        isStreaming = await router.isStreaming
        XCTAssertFalse(isStreaming, "Should not be streaming after cancel")
    }
}

// MARK: - Mock STT Service

/// Mock STT Service for testing router behavior
actor MockSTTService: STTService {
    private let identifier: String
    private var _metrics: STTMetrics
    private var _costPerHour: Decimal
    private(set) var isStreaming: Bool = false
    private(set) var startStreamingWasCalled = false
    private(set) var sendAudioWasCalled = false
    private(set) var stopStreamingWasCalled = false

    var metrics: STTMetrics { _metrics }
    var costPerHour: Decimal { _costPerHour }

    init(identifier: String) {
        self.identifier = identifier
        self._metrics = STTMetrics(medianLatency: 0.2, p99Latency: 0.4, wordEmissionRate: 2.0)
        self._costPerHour = Decimal(0)
    }

    func startStreaming(audioFormat: AVAudioFormat) async throws -> AsyncStream<STTResult> {
        startStreamingWasCalled = true
        isStreaming = true
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    func sendAudio(_ buffer: AVAudioPCMBuffer) async throws {
        sendAudioWasCalled = true
        guard isStreaming else { throw STTError.notStreaming }
    }

    func stopStreaming() async throws {
        stopStreamingWasCalled = true
        isStreaming = false
    }

    func cancelStreaming() async {
        isStreaming = false
    }

    // Test helpers
    func reset() {
        startStreamingWasCalled = false
        sendAudioWasCalled = false
        stopStreamingWasCalled = false
        isStreaming = false
    }

    func setMetrics(_ metrics: STTMetrics) {
        self._metrics = metrics
    }

    func setCostPerHour(_ cost: Decimal) {
        self._costPerHour = cost
    }

    func getIdentifier() -> String {
        identifier
    }
}

// MARK: - Mock Health Monitor

/// Mock Health Monitor for testing router behavior
actor MockHealthMonitor {
    private var _status: GLMASRHealthMonitor.HealthStatus = .healthy

    var currentStatus: GLMASRHealthMonitor.HealthStatus { _status }

    func setStatus(_ status: GLMASRHealthMonitor.HealthStatus) {
        _status = status
    }

    func startMonitoring() -> AsyncStream<GLMASRHealthMonitor.HealthStatus> {
        return AsyncStream { continuation in
            continuation.yield(_status)
        }
    }

    func stopMonitoring() {
        // No-op for mock
    }

    func checkHealth() async -> GLMASRHealthMonitor.HealthStatus {
        return _status
    }
}
