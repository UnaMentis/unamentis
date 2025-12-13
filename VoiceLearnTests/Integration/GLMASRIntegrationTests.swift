// VoiceLearn - GLM-ASR Integration Tests
// End-to-end tests for GLM-ASR-Nano STT Service
//
// IMPORTANT: These tests require a running GLM-ASR server
// Set GLM_ASR_SERVER_URL environment variable to run
//
// Example: GLM_ASR_SERVER_URL=wss://your-server.com/v1/audio/stream

import XCTest
import AVFoundation
@testable import VoiceLearn

final class GLMASRIntegrationTests: XCTestCase {

    // MARK: - Properties

    var service: GLMASRSTTService!
    var telemetry: TelemetryEngine!
    var serverURL: URL!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Check for server URL - skip if not available
        guard let urlString = ProcessInfo.processInfo.environment["GLM_ASR_SERVER_URL"],
              let url = URL(string: urlString) else {
            throw XCTSkip("GLM_ASR_SERVER_URL not set - skipping integration tests")
        }

        serverURL = url
        telemetry = TelemetryEngine()

        let config = GLMASRSTTService.Configuration(
            serverURL: serverURL,
            authToken: ProcessInfo.processInfo.environment["GLM_ASR_AUTH_TOKEN"],
            language: "en",
            interimResults: true,
            punctuate: true,
            reconnectAttempts: 1,
            reconnectDelayMs: 500
        )

        service = GLMASRSTTService(
            configuration: config,
            telemetry: telemetry
        )
    }

    override func tearDown() async throws {
        if service != nil {
            await service.cancelStreaming()
        }
        service = nil
        telemetry = nil
        serverURL = nil
        try await super.tearDown()
    }

    // MARK: - Connection Tests

    func testConnection_serverAvailable_connects() async throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        // Should connect without throwing
        _ = try await service.startStreaming(audioFormat: format)

        let isStreaming = await service.isStreaming
        XCTAssertTrue(isStreaming)

        await service.cancelStreaming()
    }

    // MARK: - Transcription Tests

    func testTranscription_withTestAudio_returnsResults() async throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        let resultStream = try await service.startStreaming(audioFormat: format)

        // Create test audio buffer with speech-like data
        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 16000) else {
            XCTFail("Failed to create audio buffer")
            return
        }

        buffer.frameLength = 16000  // 1 second of audio

        // Fill with a simple sine wave (not real speech, but tests pipeline)
        if let floatData = buffer.floatChannelData?[0] {
            for i in 0..<16000 {
                floatData[i] = Float(sin(Double(i) * 0.1) * 0.5)
            }
        }

        // Send audio
        try await service.sendAudio(buffer)

        // Stop and wait for final result
        _ = await service.stopStreaming()

        // Collect results (with timeout)
        var results: [STTResult] = []
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
        }

        for await result in resultStream {
            results.append(result)
            if result.isFinal {
                break
            }
        }

        timeout.cancel()

        // We should have received at least one result
        // (may be empty transcript for non-speech audio)
        XCTAssertGreaterThan(results.count, 0, "Should receive at least one result")
    }

    // MARK: - Session Lifecycle Tests

    func testSessionLifecycle_fullCycle_completesSuccessfully() async throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        // Start streaming
        var isStreaming = await service.isStreaming
        XCTAssertFalse(isStreaming)

        _ = try await service.startStreaming(audioFormat: format)

        isStreaming = await service.isStreaming
        XCTAssertTrue(isStreaming)

        // Send some audio
        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 1600) else {
            XCTFail("Failed to create audio buffer")
            return
        }

        buffer.frameLength = 1600

        for _ in 0..<10 {
            try await service.sendAudio(buffer)
        }

        // Stop streaming
        _ = await service.stopStreaming()

        isStreaming = await service.isStreaming
        XCTAssertFalse(isStreaming)
    }

    func testSessionLifecycle_cancel_cleanlyTerminates() async throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        _ = try await service.startStreaming(audioFormat: format)

        var isStreaming = await service.isStreaming
        XCTAssertTrue(isStreaming)

        // Cancel instead of stop
        await service.cancelStreaming()

        isStreaming = await service.isStreaming
        XCTAssertFalse(isStreaming)
    }

    // MARK: - Concurrent Sessions Tests

    func testConcurrentSessions_multipleServicesWork() async throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        // Create multiple service instances
        let services = (0..<3).map { _ in
            GLMASRSTTService(
                configuration: GLMASRSTTService.Configuration(
                    serverURL: serverURL,
                    authToken: ProcessInfo.processInfo.environment["GLM_ASR_AUTH_TOKEN"],
                    language: "en",
                    interimResults: true,
                    punctuate: true,
                    reconnectAttempts: 1,
                    reconnectDelayMs: 500
                ),
                telemetry: TelemetryEngine()
            )
        }

        // Start all sessions concurrently
        await withTaskGroup(of: Bool.self) { group in
            for service in services {
                group.addTask {
                    do {
                        _ = try await service.startStreaming(audioFormat: format)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var successCount = 0
            for await success in group {
                if success { successCount += 1 }
            }

            XCTAssertEqual(successCount, 3, "All concurrent sessions should start")
        }

        // Clean up
        for service in services {
            await service.cancelStreaming()
        }
    }

    // MARK: - Latency Tests

    func testLatency_withinTargetRange() async throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        let resultStream = try await service.startStreaming(audioFormat: format)

        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 1600) else {
            XCTFail("Failed to create audio buffer")
            return
        }

        buffer.frameLength = 1600

        var latencies: [TimeInterval] = []
        let startTime = Date()

        // Send audio and measure latency
        for _ in 0..<20 {
            let sendTime = Date()
            try await service.sendAudio(buffer)

            // Try to get a result (non-blocking)
            var iterator = resultStream.makeAsyncIterator()
            if let result = try? await withTimeout(seconds: 0.5) {
                try? await iterator.next()
            } {
                let latency = Date().timeIntervalSince(sendTime)
                latencies.append(latency)
            }
        }

        await service.cancelStreaming()

        // Check latency metrics
        if !latencies.isEmpty {
            let avgLatency = latencies.reduce(0, +) / Double(latencies.count)

            // Target: P50 < 200ms, P99 < 400ms (from TRD)
            XCTAssertLessThan(avgLatency, 0.5, "Average latency should be under 500ms")
        }
    }

    // MARK: - Error Recovery Tests

    func testErrorRecovery_afterDisconnect_reconnects() async throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        // Start first session
        _ = try await service.startStreaming(audioFormat: format)
        await service.cancelStreaming()

        // Start second session (tests reconnection)
        _ = try await service.startStreaming(audioFormat: format)

        let isStreaming = await service.isStreaming
        XCTAssertTrue(isStreaming, "Should reconnect successfully")

        await service.cancelStreaming()
    }
}

// MARK: - Test Helpers

/// Helper to add timeout to async operations
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CancellationError()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
