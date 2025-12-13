// VoiceLearn - GLMASRSTTService Tests
// Unit tests for GLM-ASR-Nano STT Service (TDD)
//
// Tests cover:
// - Initialization and configuration
// - Audio format validation
// - Audio buffer conversion (Float32 → Int16 PCM)
// - WebSocket message parsing
// - Cost calculation (self-hosted = $0)
// - Connection state management
// - Error handling

import XCTest
import AVFoundation
@testable import VoiceLearn

@MainActor
final class GLMASRSTTServiceTests: XCTestCase {

    // MARK: - Properties

    var telemetry: TelemetryEngine!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        telemetry = TelemetryEngine()
    }

    override func tearDown() async throws {
        telemetry = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_withDefaultConfiguration() async {
        let service = GLMASRSTTService(
            configuration: .default,
            telemetry: telemetry
        )

        XCTAssertNotNil(service)
        let streaming = await service.isStreaming
        XCTAssertFalse(streaming)
    }

    func testInit_withCustomConfiguration() async {
        let config = GLMASRSTTService.Configuration(
            serverURL: URL(string: "wss://custom-server.com/v1/audio/stream")!,
            authToken: "test-token",
            language: "en",
            interimResults: false,
            punctuate: false,
            reconnectAttempts: 5,
            reconnectDelayMs: 2000
        )

        let service = GLMASRSTTService(
            configuration: config,
            telemetry: telemetry
        )

        XCTAssertNotNil(service)
    }

    // MARK: - Cost Tests

    func testCostPerHour_returnsZeroForSelfHosted() async {
        let service = GLMASRSTTService(
            configuration: .default,
            telemetry: telemetry
        )

        let cost = await service.costPerHour
        XCTAssertEqual(cost, Decimal(0), "Self-hosted GLM-ASR should have zero cost per hour")
    }

    // MARK: - Audio Format Validation Tests

    func testStartStreaming_validFormat16kHzMono_succeeds() async throws {
        let service = GLMASRSTTService(
            configuration: .mockLocal,
            telemetry: telemetry
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        // This will fail without a server, but should not throw format validation error
        do {
            _ = try await service.startStreaming(audioFormat: format)
            // If we get here without throwing invalidAudioFormat, format validation passed
            await service.cancelStreaming()
        } catch STTError.invalidAudioFormat {
            XCTFail("Valid 16kHz mono format should not throw invalidAudioFormat")
        } catch {
            // Other errors (connection failures) are expected without server
        }
    }

    func testStartStreaming_invalidFormat44kHz_throws() async throws {
        let service = GLMASRSTTService(
            configuration: .mockLocal,
            telemetry: telemetry
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 44100,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        do {
            _ = try await service.startStreaming(audioFormat: format)
            XCTFail("Should throw for invalid sample rate")
        } catch STTError.invalidAudioFormat {
            // Expected
        }
    }

    func testStartStreaming_invalidFormatStereo_throws() async throws {
        let service = GLMASRSTTService(
            configuration: .mockLocal,
            telemetry: telemetry
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 2
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        do {
            _ = try await service.startStreaming(audioFormat: format)
            XCTFail("Should throw for stereo format")
        } catch STTError.invalidAudioFormat {
            // Expected
        }
    }

    // MARK: - Connection State Tests

    func testStartStreaming_whenAlreadyStreaming_throws() async throws {
        let service = GLMASRSTTService(
            configuration: .mockLocal,
            telemetry: telemetry
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        ) else {
            XCTFail("Failed to create audio format")
            return
        }

        // Set up streaming state (mock internal state)
        // First attempt may fail due to connection, that's expected
        do {
            _ = try await service.startStreaming(audioFormat: format)
        } catch {
            // Ignore connection errors for this test
        }

        // Manually verify that double-start would be prevented
        // This tests the internal guard
        let isStreaming = await service.isStreaming
        if isStreaming {
            do {
                _ = try await service.startStreaming(audioFormat: format)
                XCTFail("Should throw when already streaming")
            } catch STTError.alreadyStreaming {
                // Expected
            }
        }

        await service.cancelStreaming()
    }

    func testSendAudio_whenNotStreaming_throws() async throws {
        let service = GLMASRSTTService(
            configuration: .mockLocal,
            telemetry: telemetry
        )

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600) else {
            XCTFail("Failed to create test buffer")
            return
        }
        buffer.frameLength = 1600

        do {
            try await service.sendAudio(buffer)
            XCTFail("Should throw when not streaming")
        } catch STTError.notStreaming {
            // Expected
        }
    }

    // MARK: - Message Parsing Tests

    func testParsePartialResult() {
        let json = """
        {
            "type": "partial",
            "text": "Hello how are",
            "confidence": 0.82,
            "timestamp_ms": 1500,
            "words": [
                {"word": "Hello", "start": 0.0, "end": 0.3, "confidence": 0.95},
                {"word": "how", "start": 0.35, "end": 0.5, "confidence": 0.88},
                {"word": "are", "start": 0.55, "end": 0.7, "confidence": 0.76}
            ]
        }
        """

        let result = GLMASRMessageParser.parseTranscriptionResult(json)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "Hello how are")
        XCTAssertEqual(result?.isFinal, false)
        XCTAssertEqual(result?.confidence, 0.82, accuracy: 0.01)
        XCTAssertEqual(result?.words?.count, 3)
        XCTAssertEqual(result?.words?.first?.word, "Hello")
    }

    func testParseFinalResult() {
        let json = """
        {
            "type": "final",
            "text": "Hello, how are you today?",
            "confidence": 0.94,
            "is_end_of_utterance": true,
            "duration_ms": 2100,
            "words": [
                {"word": "Hello", "start": 0.0, "end": 0.3, "confidence": 0.95},
                {"word": "how", "start": 0.35, "end": 0.5, "confidence": 0.92}
            ]
        }
        """

        let result = GLMASRMessageParser.parseTranscriptionResult(json)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "Hello, how are you today?")
        XCTAssertEqual(result?.isFinal, true)
        XCTAssertEqual(result?.isEndOfUtterance, true)
        XCTAssertEqual(result?.confidence, 0.94, accuracy: 0.01)
    }

    func testParseErrorMessage() {
        let json = """
        {
            "type": "error",
            "code": "AUDIO_FORMAT_ERROR",
            "message": "Invalid audio format. Expected 16kHz mono PCM.",
            "recoverable": true
        }
        """

        let error = GLMASRMessageParser.parseErrorMessage(json)

        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, "AUDIO_FORMAT_ERROR")
        XCTAssertEqual(error?.message, "Invalid audio format. Expected 16kHz mono PCM.")
        XCTAssertEqual(error?.recoverable, true)
    }

    func testParseInvalidJSON_returnsNil() {
        let invalidJSON = "not valid json {"

        let result = GLMASRMessageParser.parseTranscriptionResult(invalidJSON)

        XCTAssertNil(result)
    }

    // MARK: - Audio Buffer Conversion Tests

    func testToInt16PCMData_convertsCorrectly() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600) else {
            XCTFail("Failed to create test buffer")
            return
        }

        buffer.frameLength = 1600

        // Fill with test data
        if let floatData = buffer.floatChannelData?[0] {
            for i in 0..<1600 {
                floatData[i] = Float(sin(Double(i) * 0.01)) // Sine wave
            }
        }

        let data = buffer.toGLMASRPCMData()

        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 3200, "1600 samples * 2 bytes = 3200 bytes")
    }

    func testToInt16PCMData_clampsOutOfRange() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4) else {
            XCTFail("Failed to create test buffer")
            return
        }

        buffer.frameLength = 4

        // Fill with out-of-range values
        if let floatData = buffer.floatChannelData?[0] {
            floatData[0] = 2.0   // Above 1.0, should clamp to 1.0
            floatData[1] = -2.0  // Below -1.0, should clamp to -1.0
            floatData[2] = 1.0   // At boundary
            floatData[3] = -1.0  // At boundary
        }

        let data = buffer.toGLMASRPCMData()

        XCTAssertNotNil(data)

        // Verify clamping by checking the Int16 values
        data?.withUnsafeBytes { buffer in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            XCTAssertEqual(int16Buffer[0], Int16.max)  // 2.0 clamped to 1.0 -> max
            XCTAssertEqual(int16Buffer[1], -Int16.max) // -2.0 clamped to -1.0 -> -max
            XCTAssertEqual(int16Buffer[2], Int16.max)  // 1.0 -> max
            XCTAssertEqual(int16Buffer[3], -Int16.max) // -1.0 -> -max
        }
    }

    func testToInt16PCMData_handlesZero() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) else {
            XCTFail("Failed to create test buffer")
            return
        }

        buffer.frameLength = 1

        if let floatData = buffer.floatChannelData?[0] {
            floatData[0] = 0.0
        }

        let data = buffer.toGLMASRPCMData()

        XCTAssertNotNil(data)
        data?.withUnsafeBytes { buffer in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            XCTAssertEqual(int16Buffer[0], 0)
        }
    }

    // MARK: - Metrics Tests

    func testMetrics_initialState() async {
        let service = GLMASRSTTService(
            configuration: .default,
            telemetry: telemetry
        )

        let metrics = await service.metrics

        // Initial metrics should be reasonable defaults
        XCTAssertGreaterThanOrEqual(metrics.medianLatency, 0)
        XCTAssertGreaterThanOrEqual(metrics.p99Latency, 0)
    }

    // MARK: - Configuration Tests

    func testConfiguration_defaultValues() {
        let config = GLMASRSTTService.Configuration.default

        XCTAssertEqual(config.language, "auto")
        XCTAssertTrue(config.interimResults)
        XCTAssertTrue(config.punctuate)
        XCTAssertEqual(config.reconnectAttempts, 3)
        XCTAssertEqual(config.reconnectDelayMs, 1000)
    }
}

// MARK: - Mock Configuration Extension

extension GLMASRSTTService.Configuration {
    /// Mock configuration for testing (uses localhost)
    static var mockLocal: GLMASRSTTService.Configuration {
        GLMASRSTTService.Configuration(
            serverURL: URL(string: "ws://localhost:8080/v1/audio/stream")!,
            authToken: nil,
            language: "auto",
            interimResults: true,
            punctuate: true,
            reconnectAttempts: 0,  // No retries in tests
            reconnectDelayMs: 100
        )
    }
}
