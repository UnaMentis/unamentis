// VoiceLearn - STT Provider Router
// Routes STT requests to appropriate provider with automatic failover
//
// Features:
// - Routes to GLM-ASR when healthy
// - Automatic failover to Deepgram when unhealthy
// - Health monitoring integration
//
// Related: docs/GLM_ASR_SERVER_TRD.md

import Foundation
import AVFoundation
import Logging

/// Routes STT requests to appropriate provider with automatic failover
///
/// This router implements the STTService protocol and transparently
/// routes requests to either GLM-ASR (primary) or Deepgram (fallback)
/// based on health status.
public actor STTProviderRouter: STTService {

    // MARK: - Properties

    private let logger = Logger(label: "com.voicelearn.stt.router")

    private let glmASRService: any STTService
    private let deepgramService: any STTService
    private let healthMonitor: GLMASRHealthMonitor

    private var activeProvider: any STTService
    private var healthStatus: GLMASRHealthMonitor.HealthStatus = .healthy
    private var healthMonitorTask: Task<Void, Never>?

    /// Current provider identifier for debugging/telemetry
    public var currentProviderIdentifier: String {
        get async {
            if healthStatus == .unhealthy {
                return "deepgram"
            }
            return "glm-asr"
        }
    }

    // MARK: - STTService Protocol Properties

    /// Performance metrics from active provider
    public var metrics: STTMetrics {
        get async { await activeProvider.metrics }
    }

    /// Cost per hour from active provider
    public var costPerHour: Decimal {
        get async { await activeProvider.costPerHour }
    }

    /// Whether currently streaming
    public var isStreaming: Bool {
        get async { await activeProvider.isStreaming }
    }

    // MARK: - Initialization

    /// Initialize STT provider router
    /// - Parameters:
    ///   - glmASRService: Primary GLM-ASR service
    ///   - deepgramService: Fallback Deepgram service
    ///   - healthMonitor: Health monitor for GLM-ASR
    public init(
        glmASRService: any STTService,
        deepgramService: any STTService,
        healthMonitor: GLMASRHealthMonitor
    ) {
        self.glmASRService = glmASRService
        self.deepgramService = deepgramService
        self.healthMonitor = healthMonitor
        self.activeProvider = glmASRService

        logger.info("STTProviderRouter initialized")

        // Start health monitoring
        Task {
            await self.startHealthMonitoring()
        }
    }

    /// Initialize with mock health monitor (for testing)
    public init(
        glmASRService: any STTService,
        deepgramService: any STTService,
        healthMonitor: MockHealthMonitor
    ) {
        self.glmASRService = glmASRService
        self.deepgramService = deepgramService

        // Create a real health monitor but we'll use the mock's status
        self.healthMonitor = GLMASRHealthMonitor(configuration: .default)
        self.activeProvider = glmASRService

        // Set up monitoring with mock
        Task {
            await self.startMockHealthMonitoring(mock: healthMonitor)
        }
    }

    deinit {
        healthMonitorTask?.cancel()
    }

    // MARK: - STTService Protocol Methods

    /// Start streaming transcription
    /// - Parameter audioFormat: Audio format
    /// - Returns: AsyncStream of STT results
    public func startStreaming(audioFormat: AVAudioFormat) async throws -> AsyncStream<STTResult> {
        // Select provider based on health
        activeProvider = selectProvider()

        let providerName = await currentProviderIdentifier
        logger.info("Starting streaming with provider: \(providerName)")

        return try await activeProvider.startStreaming(audioFormat: audioFormat)
    }

    /// Send audio buffer for transcription
    /// - Parameter buffer: Audio buffer to transcribe
    public func sendAudio(_ buffer: AVAudioPCMBuffer) async throws {
        try await activeProvider.sendAudio(buffer)
    }

    /// Stop streaming and get final result
    public func stopStreaming() async throws {
        try await activeProvider.stopStreaming()
    }

    /// Cancel streaming without finalizing
    public func cancelStreaming() async {
        await activeProvider.cancelStreaming()
    }

    // MARK: - Private Methods

    private func startHealthMonitoring() async {
        let healthStream = await healthMonitor.startMonitoring()

        healthMonitorTask = Task {
            for await status in healthStream {
                await self.handleHealthStatusChange(status)
            }
        }
    }

    private func startMockHealthMonitoring(mock: MockHealthMonitor) async {
        // For testing, poll the mock's status
        healthMonitorTask = Task {
            while !Task.isCancelled {
                let status = await mock.currentStatus
                await self.handleHealthStatusChange(status)
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            }
        }
    }

    private func handleHealthStatusChange(_ status: GLMASRHealthMonitor.HealthStatus) async {
        let previousStatus = healthStatus
        healthStatus = status

        if previousStatus != status {
            logger.info("Health status changed: \(previousStatus) → \(status)")

            // If currently streaming and provider changed, log but don't interrupt
            // Next streaming session will use new provider
            if status == .unhealthy && await activeProvider.isStreaming {
                logger.warning("GLM-ASR became unhealthy during streaming - will switch on next session")
            }
        }
    }

    private func selectProvider() -> any STTService {
        switch healthStatus {
        case .healthy, .degraded:
            logger.debug("Selecting GLM-ASR (status: \(healthStatus))")
            return glmASRService
        case .unhealthy:
            logger.debug("Selecting Deepgram (GLM-ASR unhealthy)")
            return deepgramService
        }
    }
}

// MARK: - Protocol for Mock Health Monitor (Testing)

/// Protocol for mock health monitor in tests
public protocol HealthMonitorProtocol: Actor {
    var currentStatus: GLMASRHealthMonitor.HealthStatus { get async }
    func startMonitoring() async -> AsyncStream<GLMASRHealthMonitor.HealthStatus>
    func stopMonitoring() async
}

// Make GLMASRHealthMonitor conform
extension GLMASRHealthMonitor: HealthMonitorProtocol {}
