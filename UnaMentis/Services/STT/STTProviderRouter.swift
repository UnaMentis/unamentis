// UnaMentis - STT Provider Router
// Routes STT requests to appropriate provider with automatic failover
//
// Features:
// - Routes to GLM-ASR when healthy
// - Automatic failover to Deepgram when unhealthy
// - Health monitoring integration
//
// Related: docs/GLM_ASR_SERVER_TRD.md

import Foundation
@preconcurrency import AVFoundation
import Logging

/// Routes STT requests to appropriate provider with automatic failover
///
/// This router implements the STTService protocol and transparently
/// routes requests based on device capability and health status.
///
/// Priority order:
/// 1. On-Device GLM-ASR (if device supports it and models loaded)
/// 2. Server GLM-ASR (if healthy)
/// 3. Deepgram (fallback)
public actor STTProviderRouter: STTService {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.stt.router")

    #if LLAMA_AVAILABLE
    private let onDeviceService: GLMASROnDeviceSTTService?
    #endif
    private let glmASRService: any STTService
    private let deepgramService: any STTService
    private let healthMonitor: any HealthMonitorProtocol

    private var activeProvider: any STTService
    private var healthStatus: GLMASRHealthMonitor.HealthStatus = .healthy
    private var healthMonitorTask: Task<Void, Never>?
    private var onDeviceAvailable: Bool = false

    // MARK: - Cached Protocol Properties
    // These are cached to satisfy the non-async protocol requirements

    private var _metrics: STTMetrics = STTMetrics(medianLatency: 0, p99Latency: 0, wordEmissionRate: 0)
    private var _costPerHour: Decimal = 0
    private var _isStreaming: Bool = false

    /// Current provider identifier for debugging/telemetry
    public var currentProviderIdentifier: String {
        if onDeviceAvailable {
            return "glm-asr-ondevice"
        } else if healthStatus == .unhealthy {
            return "deepgram"
        }
        return "glm-asr"
    }

    // MARK: - STTService Protocol Properties

    /// Performance metrics from active provider
    public var metrics: STTMetrics {
        _metrics
    }

    /// Cost per hour from active provider
    public var costPerHour: Decimal {
        _costPerHour
    }

    /// Whether currently streaming
    public var isStreaming: Bool {
        _isStreaming
    }

    /// Update cached metrics from active provider
    private func updateCachedMetrics() async {
        _metrics = await activeProvider.metrics
        _costPerHour = await activeProvider.costPerHour
        _isStreaming = await activeProvider.isStreaming
    }

    // MARK: - Initialization

    #if LLAMA_AVAILABLE
    /// Initialize STT provider router with on-device support
    /// - Parameters:
    ///   - onDeviceService: On-device GLM-ASR service (optional, for supported devices)
    ///   - glmASRService: Server-based GLM-ASR service
    ///   - deepgramService: Fallback Deepgram service
    ///   - healthMonitor: Health monitor for server GLM-ASR
    public init(
        onDeviceService: GLMASROnDeviceSTTService? = nil,
        glmASRService: any STTService,
        deepgramService: any STTService,
        healthMonitor: any HealthMonitorProtocol
    ) {
        self.onDeviceService = onDeviceService
        self.glmASRService = glmASRService
        self.deepgramService = deepgramService
        self.healthMonitor = healthMonitor

        // Default to on-device if available, otherwise server GLM-ASR
        if let onDevice = onDeviceService, GLMASROnDeviceSTTService.isDeviceSupported {
            self.activeProvider = onDevice
            self.onDeviceAvailable = true
        } else {
            self.activeProvider = glmASRService
        }

        logger.info("STTProviderRouter initialized (on-device: \(onDeviceService != nil))")

        // Start health monitoring for server fallback
        Task {
            await self.startHealthMonitoring()
            // Try to load on-device models in background
            if let onDevice = onDeviceService {
                await self.tryLoadOnDeviceModels(onDevice)
            }
        }
    }

    /// Attempt to load on-device models
    private func tryLoadOnDeviceModels(_ service: GLMASROnDeviceSTTService) async {
        do {
            try await service.loadModels()
            onDeviceAvailable = true
            activeProvider = service
            logger.info("On-device GLM-ASR models loaded successfully")
        } catch {
            logger.warning("Failed to load on-device models: \(error). Using server fallback.")
            onDeviceAvailable = false
        }
    }
    #else
    /// Initialize STT provider router (server-only mode)
    /// - Parameters:
    ///   - glmASRService: Server-based GLM-ASR service
    ///   - deepgramService: Fallback Deepgram service
    ///   - healthMonitor: Health monitor for server GLM-ASR
    public init(
        glmASRService: any STTService,
        deepgramService: any STTService,
        healthMonitor: any HealthMonitorProtocol
    ) {
        self.glmASRService = glmASRService
        self.deepgramService = deepgramService
        self.healthMonitor = healthMonitor
        self.activeProvider = glmASRService

        logger.info("STTProviderRouter initialized (server-only mode)")

        // Start health monitoring
        Task {
            await self.startHealthMonitoring()
        }
    }
    #endif

    deinit {
        healthMonitorTask?.cancel()
    }

    // MARK: - STTService Protocol Methods

    /// Start streaming transcription
    /// - Parameter audioFormat: Audio format
    /// - Returns: AsyncStream of STT results
    public func startStreaming(audioFormat: sending AVAudioFormat) async throws -> AsyncStream<STTResult> {
        // Select provider based on health
        activeProvider = selectProvider()
        _isStreaming = true

        let providerName = currentProviderIdentifier
        logger.info("Starting streaming with provider: \(providerName)")

        let stream = try await activeProvider.startStreaming(audioFormat: audioFormat)
        await updateCachedMetrics()
        return stream
    }

    /// Send audio buffer for transcription
    /// - Parameter buffer: Audio buffer to transcribe
    public func sendAudio(_ buffer: sending AVAudioPCMBuffer) async throws {
        try await activeProvider.sendAudio(buffer)
    }

    /// Stop streaming and get final result
    public func stopStreaming() async throws {
        try await activeProvider.stopStreaming()
        _isStreaming = false
        await updateCachedMetrics()
    }

    /// Cancel streaming without finalizing
    public func cancelStreaming() async {
        await activeProvider.cancelStreaming()
        _isStreaming = false
        await updateCachedMetrics()
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

    private func handleHealthStatusChange(_ status: GLMASRHealthMonitor.HealthStatus) async {
        let previousStatus = healthStatus
        healthStatus = status

        if previousStatus != status {
            logger.info("Health status changed: \(previousStatus) → \(status)")

            // If currently streaming and provider changed, log but don't interrupt
            // Next streaming session will use new provider
            let isCurrentlyStreaming = await activeProvider.isStreaming
            if status == .unhealthy && isCurrentlyStreaming {
                logger.warning("GLM-ASR became unhealthy during streaming - will switch on next session")
            }
        }
    }

    private func selectProvider() -> any STTService {
        #if LLAMA_AVAILABLE
        // Priority 1: On-device if available and models loaded
        if onDeviceAvailable, let onDevice = onDeviceService {
            logger.debug("Selecting on-device GLM-ASR")
            return onDevice
        }
        #endif

        // Priority 2: Server GLM-ASR if healthy
        switch healthStatus {
        case .healthy, .degraded:
            logger.debug("Selecting server GLM-ASR (status: \(healthStatus))")
            return glmASRService
        case .unhealthy:
            logger.debug("Selecting Deepgram (GLM-ASR unhealthy)")
            return deepgramService
        }
    }

    /// Force switch to server mode (e.g., for thermal throttling)
    public func switchToServerMode() {
        onDeviceAvailable = false
        activeProvider = selectProvider()
        logger.info("Switched to server mode")
    }

    /// Try to re-enable on-device mode
    public func tryEnableOnDeviceMode() async {
        #if LLAMA_AVAILABLE
        guard let onDevice = onDeviceService else { return }
        await tryLoadOnDeviceModels(onDevice)
        #endif
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
