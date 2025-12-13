// VoiceLearn - GLMASRHealthMonitor Tests
// Unit tests for GLM-ASR Health Monitoring (TDD)
//
// Tests cover:
// - Health check success/failure paths
// - State transitions (healthy/degraded/unhealthy)
// - Consecutive failure/success thresholds
// - Configuration validation

import XCTest
@testable import VoiceLearn

@MainActor
final class GLMASRHealthMonitorTests: XCTestCase {

    // MARK: - Configuration Tests

    func testConfiguration_defaultValues() {
        let config = GLMASRHealthMonitor.Configuration.default

        XCTAssertEqual(config.checkIntervalSeconds, 30)
        XCTAssertEqual(config.unhealthyThreshold, 3)
        XCTAssertEqual(config.healthyThreshold, 2)
    }

    func testConfiguration_customValues() {
        let config = GLMASRHealthMonitor.Configuration(
            healthEndpoint: URL(string: "https://custom-server.com/health")!,
            checkIntervalSeconds: 60,
            unhealthyThreshold: 5,
            healthyThreshold: 3
        )

        XCTAssertEqual(config.checkIntervalSeconds, 60)
        XCTAssertEqual(config.unhealthyThreshold, 5)
        XCTAssertEqual(config.healthyThreshold, 3)
    }

    // MARK: - Initialization Tests

    func testInit_startsHealthy() async {
        let monitor = GLMASRHealthMonitor(configuration: .mockLocal)

        let status = await monitor.currentStatus
        XCTAssertEqual(status, .healthy)
    }

    // MARK: - State Transition Tests

    func testRecordSuccess_whenHealthy_staysHealthy() async {
        let monitor = GLMASRHealthMonitor(configuration: .mockLocal)

        await monitor.recordSuccess()

        let status = await monitor.currentStatus
        XCTAssertEqual(status, .healthy)
    }

    func testRecordFailure_singleFailure_staysHealthyOrDegraded() async {
        let monitor = GLMASRHealthMonitor(
            configuration: .init(
                healthEndpoint: URL(string: "http://localhost:8080/health")!,
                checkIntervalSeconds: 30,
                unhealthyThreshold: 3,  // Need 3 failures
                healthyThreshold: 2
            )
        )

        await monitor.recordFailure()

        let status = await monitor.currentStatus
        // After single failure, should be degraded (not unhealthy yet)
        XCTAssertTrue(status == .healthy || status == .degraded)
    }

    func testRecordFailure_thresholdExceeded_becomesUnhealthy() async {
        let monitor = GLMASRHealthMonitor(
            configuration: .init(
                healthEndpoint: URL(string: "http://localhost:8080/health")!,
                checkIntervalSeconds: 30,
                unhealthyThreshold: 3,
                healthyThreshold: 2
            )
        )

        // Record 3 consecutive failures
        await monitor.recordFailure()
        await monitor.recordFailure()
        await monitor.recordFailure()

        let status = await monitor.currentStatus
        XCTAssertEqual(status, .unhealthy)
    }

    func testRecordSuccess_afterUnhealthy_becomesDegraded() async {
        let monitor = GLMASRHealthMonitor(
            configuration: .init(
                healthEndpoint: URL(string: "http://localhost:8080/health")!,
                checkIntervalSeconds: 30,
                unhealthyThreshold: 2,
                healthyThreshold: 3  // Need 3 successes to become healthy
            )
        )

        // Make it unhealthy
        await monitor.recordFailure()
        await monitor.recordFailure()

        // Now record a success
        await monitor.recordSuccess()

        let status = await monitor.currentStatus
        XCTAssertEqual(status, .degraded)
    }

    func testRecordSuccess_thresholdExceeded_becomesHealthy() async {
        let monitor = GLMASRHealthMonitor(
            configuration: .init(
                healthEndpoint: URL(string: "http://localhost:8080/health")!,
                checkIntervalSeconds: 30,
                unhealthyThreshold: 2,
                healthyThreshold: 2  // Need 2 successes
            )
        )

        // Make it unhealthy
        await monitor.recordFailure()
        await monitor.recordFailure()

        // Record enough successes
        await monitor.recordSuccess()
        await monitor.recordSuccess()

        let status = await monitor.currentStatus
        XCTAssertEqual(status, .healthy)
    }

    func testRecordSuccess_resetsFailureCount() async {
        let monitor = GLMASRHealthMonitor(
            configuration: .init(
                healthEndpoint: URL(string: "http://localhost:8080/health")!,
                checkIntervalSeconds: 30,
                unhealthyThreshold: 3,
                healthyThreshold: 2
            )
        )

        // Record 2 failures (not enough to be unhealthy)
        await monitor.recordFailure()
        await monitor.recordFailure()

        // Success should reset the count
        await monitor.recordSuccess()

        // Now 2 more failures shouldn't make it unhealthy
        await monitor.recordFailure()
        await monitor.recordFailure()

        let status = await monitor.currentStatus
        XCTAssertNotEqual(status, .unhealthy, "Success should reset failure count")
    }

    func testRecordFailure_resetsSuccessCount() async {
        let monitor = GLMASRHealthMonitor(
            configuration: .init(
                healthEndpoint: URL(string: "http://localhost:8080/health")!,
                checkIntervalSeconds: 30,
                unhealthyThreshold: 2,
                healthyThreshold: 3
            )
        )

        // Make it unhealthy
        await monitor.recordFailure()
        await monitor.recordFailure()

        // Record 2 successes (not enough to be healthy)
        await monitor.recordSuccess()
        await monitor.recordSuccess()

        // Failure should reset the success count
        await monitor.recordFailure()

        // Need 2 more for unhealthy
        await monitor.recordFailure()

        let status = await monitor.currentStatus
        XCTAssertEqual(status, .unhealthy, "Failure should reset success count")
    }

    // MARK: - Health Status Enum Tests

    func testHealthStatus_equality() {
        XCTAssertEqual(GLMASRHealthMonitor.HealthStatus.healthy, .healthy)
        XCTAssertEqual(GLMASRHealthMonitor.HealthStatus.degraded, .degraded)
        XCTAssertEqual(GLMASRHealthMonitor.HealthStatus.unhealthy, .unhealthy)

        XCTAssertNotEqual(GLMASRHealthMonitor.HealthStatus.healthy, .unhealthy)
    }

    // MARK: - Monitoring Lifecycle Tests

    func testStartMonitoring_returnsStream() async {
        let monitor = GLMASRHealthMonitor(configuration: .mockLocal)

        let stream = await monitor.startMonitoring()

        XCTAssertNotNil(stream)

        // Stop to clean up
        await monitor.stopMonitoring()
    }

    func testStopMonitoring_stopsLoop() async {
        let monitor = GLMASRHealthMonitor(
            configuration: .init(
                healthEndpoint: URL(string: "http://localhost:8080/health")!,
                checkIntervalSeconds: 1,  // Very short for test
                unhealthyThreshold: 3,
                healthyThreshold: 2
            )
        )

        _ = await monitor.startMonitoring()

        // Wait briefly
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        await monitor.stopMonitoring()

        // Verify stopped (no crash, clean termination)
        let status = await monitor.currentStatus
        XCTAssertNotNil(status)
    }

    // MARK: - Check Health Tests

    func testCheckHealth_noServer_returnsUnhealthyEventually() async {
        let monitor = GLMASRHealthMonitor(
            configuration: .init(
                healthEndpoint: URL(string: "http://localhost:9999/nonexistent")!,
                checkIntervalSeconds: 30,
                unhealthyThreshold: 1,  // Single failure = unhealthy
                healthyThreshold: 1
            )
        )

        // This should fail since there's no server
        _ = await monitor.checkHealth()

        let status = await monitor.currentStatus
        XCTAssertEqual(status, .unhealthy)
    }
}

// MARK: - Mock Configuration Extension

extension GLMASRHealthMonitor.Configuration {
    /// Mock configuration for testing
    static var mockLocal: GLMASRHealthMonitor.Configuration {
        GLMASRHealthMonitor.Configuration(
            healthEndpoint: URL(string: "http://localhost:8080/health")!,
            checkIntervalSeconds: 30,
            unhealthyThreshold: 3,
            healthyThreshold: 2
        )
    }
}
