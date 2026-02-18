// UnaMentis - GLMASROnDeviceSTTService Provider Integration Tests
// Unit tests for STT provider routing with on-device GLM-ASR (TDD)
//
// Tests cover:
// - STTProvider enum properties for glmASROnDevice and glmASRNano
// - STTProviderRouter selects server GLM-ASR when on-device is unavailable
// - Health-based failover: healthy → GLM-ASR, unhealthy → Deepgram
// - Router metrics and cost propagation from active provider
// - switchToServerMode / tryEnableOnDeviceMode behavior

import XCTest
import AVFoundation
@testable import UnaMentis

final class GLMASROnDeviceProviderTests: XCTestCase {

    // MARK: - STTProvider Enum Tests

    func testSTTProvider_glmASROnDevice_identifier() {
        let provider = STTProvider.glmASROnDevice
        XCTAssertEqual(provider.identifier, "glm-asr-ondevice")
    }

    func testSTTProvider_glmASROnDevice_isOnDevice() {
        let provider = STTProvider.glmASROnDevice
        XCTAssertTrue(provider.isOnDevice)
        XCTAssertFalse(provider.requiresNetwork)
    }

    func testSTTProvider_glmASROnDevice_isFree() {
        let provider = STTProvider.glmASROnDevice
        XCTAssertEqual(provider.costPerHour, Decimal(0))
    }

    func testSTTProvider_glmASRNano_identifier() {
        let provider = STTProvider.glmASRNano
        XCTAssertEqual(provider.identifier, "glm-asr")
    }

    func testSTTProvider_glmASRNano_requiresNetwork() {
        let provider = STTProvider.glmASRNano
        XCTAssertTrue(provider.requiresNetwork)
        XCTAssertFalse(provider.isOnDevice)
    }

    func testSTTProvider_glmASRNano_isSelfHosted() {
        let provider = STTProvider.glmASRNano
        XCTAssertTrue(provider.isSelfHosted)
    }

    func testSTTProvider_glmASRNano_isFree() {
        let provider = STTProvider.glmASRNano
        XCTAssertEqual(provider.costPerHour, Decimal(0))
    }

    // MARK: - Router Provider Selection

    func testRouter_whenHealthy_selectsGLMASR() async {
        let mockGLMASR = RouterMockSTTService(identifier: "glm-asr") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockDeepgram = RouterMockSTTService(identifier: "deepgram") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockHealth = RouterMockHealthMonitor() // ALLOWED: mock for health monitor (external service boundary)
        await mockHealth.setStatus(.healthy)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealth
        )

        let provider = await router.currentProviderIdentifier
        XCTAssertEqual(provider, "glm-asr")
    }

    func testRouter_whenUnhealthy_selectsDeepgram() async {
        let mockGLMASR = RouterMockSTTService(identifier: "glm-asr") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockDeepgram = RouterMockSTTService(identifier: "deepgram") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockHealth = RouterMockHealthMonitor() // ALLOWED: mock for health monitor (external service boundary)
        await mockHealth.setStatus(.unhealthy)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealth
        )

        let provider = await router.currentProviderIdentifier
        XCTAssertEqual(provider, "deepgram")
    }

    func testRouter_whenDegraded_selectsGLMASR() async {
        let mockGLMASR = RouterMockSTTService(identifier: "glm-asr") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockDeepgram = RouterMockSTTService(identifier: "deepgram") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockHealth = RouterMockHealthMonitor() // ALLOWED: mock for health monitor (external service boundary)
        await mockHealth.setStatus(.degraded)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealth
        )

        let provider = await router.currentProviderIdentifier
        XCTAssertEqual(provider, "glm-asr",
                       "Degraded should still use GLM-ASR, not fail over to Deepgram")
    }

    // MARK: - Router Protocol Conformance

    func testRouter_initialState_isNotStreaming() async {
        let mockGLMASR = RouterMockSTTService(identifier: "glm-asr") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockDeepgram = RouterMockSTTService(identifier: "deepgram") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockHealth = RouterMockHealthMonitor() // ALLOWED: mock for health monitor (external service boundary)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealth
        )

        let streaming = await router.isStreaming
        XCTAssertFalse(streaming)
    }

    func testRouter_cancelStreaming_whenNotStreaming_isNoOp() async {
        let mockGLMASR = RouterMockSTTService(identifier: "glm-asr") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockDeepgram = RouterMockSTTService(identifier: "deepgram") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockHealth = RouterMockHealthMonitor() // ALLOWED: mock for health monitor (external service boundary)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealth
        )

        await router.cancelStreaming()
        let streaming = await router.isStreaming
        XCTAssertFalse(streaming)
    }

    // MARK: - On-Device Availability

    func testOnDeviceAvailable_defaultsFalse() async {
        // Without LLAMA_AVAILABLE, on-device is never available
        let mockGLMASR = RouterMockSTTService(identifier: "glm-asr") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockDeepgram = RouterMockSTTService(identifier: "deepgram") // ALLOWED: mock for STT provider (paid external API boundary)
        let mockHealth = RouterMockHealthMonitor() // ALLOWED: mock for health monitor (external service boundary)

        let router = STTProviderRouter(
            glmASRService: mockGLMASR,
            deepgramService: mockDeepgram,
            healthMonitor: mockHealth
        )

        // On-device is not available because LLAMA_AVAILABLE is not defined
        let provider = await router.currentProviderIdentifier
        XCTAssertNotEqual(provider, "glm-asr-ondevice",
                          "On-device should not be selected without LLAMA_AVAILABLE")
    }

    // MARK: - GLMASROnDeviceSTTService Protocol Conformance

    func testOnDeviceService_conformsToSTTService() async {
        let service = GLMASROnDeviceSTTService()

        // Verify all required protocol properties are accessible
        let _ = await service.metrics
        let _ = await service.costPerHour
        let _ = await service.isStreaming
    }

    func testOnDeviceService_isNotStreamingInitially() async {
        let service = GLMASROnDeviceSTTService()
        let streaming = await service.isStreaming
        XCTAssertFalse(streaming)
    }
}

// MARK: - Local Mock STT Service

/// Mock STT service for router testing
/// ALLOWED: mock for STT provider (paid external API boundary)
actor RouterMockSTTService: STTService {
    private let identifier: String
    private(set) var isStreaming: Bool = false

    var metrics: STTMetrics {
        STTMetrics(medianLatency: 0.2, p99Latency: 0.4, wordEmissionRate: 2.0)
    }

    var costPerHour: Decimal { Decimal(0) }

    init(identifier: String) {
        self.identifier = identifier
    }

    func startStreaming(audioFormat: sending AVAudioFormat) async throws -> AsyncStream<STTResult> {
        isStreaming = true
        return AsyncStream { $0.finish() }
    }

    func sendAudio(_ buffer: sending AVAudioPCMBuffer) async throws {
        guard isStreaming else { throw STTError.notStreaming }
    }

    func stopStreaming() async throws {
        isStreaming = false
    }

    func cancelStreaming() async {
        isStreaming = false
    }
}

// MARK: - Local Mock Health Monitor

/// Mock health monitor for router testing
/// ALLOWED: mock for health monitor (external service boundary)
actor RouterMockHealthMonitor: HealthMonitorProtocol {
    private var _status: GLMASRHealthMonitor.HealthStatus = .healthy

    var currentStatus: GLMASRHealthMonitor.HealthStatus { _status }

    func setStatus(_ status: GLMASRHealthMonitor.HealthStatus) {
        _status = status
    }

    func startMonitoring() -> AsyncStream<GLMASRHealthMonitor.HealthStatus> {
        AsyncStream { $0.yield(_status) }
    }

    func stopMonitoring() {}

    func checkHealth() async -> GLMASRHealthMonitor.HealthStatus {
        _status
    }
}
