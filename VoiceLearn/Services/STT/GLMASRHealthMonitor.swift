// VoiceLearn - GLM-ASR Health Monitor
// Monitors GLM-ASR server health and triggers failover
//
// Related: docs/GLM_ASR_SERVER_TRD.md

import Foundation
import Logging

/// Monitors GLM-ASR server health and triggers failover
///
/// Health monitoring features:
/// - Periodic HTTP health checks
/// - State machine: healthy → degraded → unhealthy
/// - Configurable thresholds for state transitions
/// - AsyncStream for status updates
public actor GLMASRHealthMonitor {

    // MARK: - Configuration

    /// Configuration for health monitoring
    public struct Configuration: Sendable {
        public let healthEndpoint: URL
        public let checkIntervalSeconds: Int
        public let unhealthyThreshold: Int  // Consecutive failures before unhealthy
        public let healthyThreshold: Int    // Consecutive successes before healthy

        public init(
            healthEndpoint: URL,
            checkIntervalSeconds: Int,
            unhealthyThreshold: Int,
            healthyThreshold: Int
        ) {
            self.healthEndpoint = healthEndpoint
            self.checkIntervalSeconds = checkIntervalSeconds
            self.unhealthyThreshold = unhealthyThreshold
            self.healthyThreshold = healthyThreshold
        }

        /// Default configuration
        public static let `default` = Configuration(
            healthEndpoint: URL(string: ProcessInfo.processInfo.environment["GLM_ASR_HEALTH_URL"]
                ?? "http://localhost:8080/health")!,
            checkIntervalSeconds: 30,
            unhealthyThreshold: 3,
            healthyThreshold: 2
        )
    }

    // MARK: - Health Status

    /// Server health status
    public enum HealthStatus: Sendable, Equatable {
        case healthy    // Server is responding normally
        case degraded   // Intermittent issues, transitioning
        case unhealthy  // Server is down, use fallback
    }

    // MARK: - Properties

    private let logger = Logger(label: "com.voicelearn.stt.healthmonitor")
    private let configuration: Configuration

    private var status: HealthStatus = .healthy
    private var consecutiveFailures: Int = 0
    private var consecutiveSuccesses: Int = 0
    private var monitorTask: Task<Void, Never>?
    private var statusContinuation: AsyncStream<HealthStatus>.Continuation?

    /// Current health status
    public var currentStatus: HealthStatus { status }

    // MARK: - Initialization

    /// Initialize health monitor with configuration
    /// - Parameter configuration: Health monitor configuration
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        logger.info("GLMASRHealthMonitor initialized with endpoint: \(configuration.healthEndpoint)")
    }

    // MARK: - Public Interface

    /// Start health monitoring
    /// - Returns: AsyncStream of health status updates
    public func startMonitoring() -> AsyncStream<HealthStatus> {
        logger.info("Starting health monitoring")

        return AsyncStream { continuation in
            self.statusContinuation = continuation

            // Emit initial status
            continuation.yield(self.status)

            self.monitorTask = Task {
                await self.monitorLoop()
            }

            continuation.onTermination = { @Sendable _ in
                Task { await self.stopMonitoring() }
            }
        }
    }

    /// Stop health monitoring
    public func stopMonitoring() {
        logger.info("Stopping health monitoring")
        monitorTask?.cancel()
        monitorTask = nil
        statusContinuation?.finish()
        statusContinuation = nil
    }

    /// Perform a single health check
    /// - Returns: Updated health status
    @discardableResult
    public func checkHealth() async -> HealthStatus {
        do {
            let (_, response) = try await URLSession.shared.data(
                from: configuration.healthEndpoint
            )

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return recordFailure()
            }

            return recordSuccess()
        } catch {
            logger.warning("Health check failed: \(error.localizedDescription)")
            return recordFailure()
        }
    }

    /// Manually record a success (for external callers)
    @discardableResult
    public func recordSuccess() -> HealthStatus {
        consecutiveSuccesses += 1
        consecutiveFailures = 0

        let previousStatus = status

        if consecutiveSuccesses >= configuration.healthyThreshold {
            status = .healthy
        } else if status == .unhealthy {
            status = .degraded
        }

        if status != previousStatus {
            logger.info("Health status changed: \(previousStatus) → \(status)")
            statusContinuation?.yield(status)
        }

        return status
    }

    /// Manually record a failure (for external callers)
    @discardableResult
    public func recordFailure() -> HealthStatus {
        consecutiveFailures += 1
        consecutiveSuccesses = 0

        let previousStatus = status

        if consecutiveFailures >= configuration.unhealthyThreshold {
            status = .unhealthy
        } else if status == .healthy {
            status = .degraded
        }

        if status != previousStatus {
            logger.info("Health status changed: \(previousStatus) → \(status)")
            statusContinuation?.yield(status)
        }

        return status
    }

    // MARK: - Private Methods

    private func monitorLoop() async {
        while !Task.isCancelled {
            _ = await checkHealth()

            do {
                try await Task.sleep(
                    nanoseconds: UInt64(configuration.checkIntervalSeconds) * 1_000_000_000
                )
            } catch {
                // Task was cancelled
                break
            }
        }
    }
}
