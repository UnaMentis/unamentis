// UnaMentis - TelemetryEngine Tests
// Unit tests for TelemetryEngine following TDD approach
//
// Tests cover: event recording, latency tracking, cost calculation

import XCTest
@testable import UnaMentis

/// Unit tests for TelemetryEngine
/// Following TDD approach: these tests are written before implementation
final class TelemetryEngineTests: XCTestCase {
    
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
    
    // MARK: - Event Recording Tests
    
    func testRecordEvent_storesEvent() async {
        await telemetry.recordEvent(.sessionStarted)
        
        let events = await telemetry.recentEvents
        XCTAssertFalse(events.isEmpty)
    }
    
    func testRecordEvent_includesTimestamp() async {
        let beforeTime = Date()
        await telemetry.recordEvent(.sessionStarted)
        let afterTime = Date()
        
        let events = await telemetry.recentEvents
        guard let event = events.first else {
            XCTFail("No events recorded")
            return
        }
        
        XCTAssertGreaterThanOrEqual(event.timestamp, beforeTime)
        XCTAssertLessThanOrEqual(event.timestamp, afterTime)
    }
    
    // MARK: - Latency Recording Tests
    
    func testRecordLatency_storesValue() async {
        await telemetry.recordLatency(.sttEmission, 0.150)
        
        let metrics = await telemetry.currentMetrics
        XCTAssertFalse(metrics.sttLatencies.isEmpty)
    }
    
    func testRecordLatency_maintainsSeparateCategories() async {
        await telemetry.recordLatency(.sttEmission, 0.150)
        await telemetry.recordLatency(.llmFirstToken, 0.200)
        await telemetry.recordLatency(.ttsTTFB, 0.100)
        
        let metrics = await telemetry.currentMetrics
        XCTAssertEqual(metrics.sttLatencies.count, 1)
        XCTAssertEqual(metrics.llmLatencies.count, 1)
        XCTAssertEqual(metrics.ttsLatencies.count, 1)
    }
    
    func testRecordLatency_calculatesMedian() async {
        await telemetry.recordLatency(.endToEndTurn, 0.100)
        await telemetry.recordLatency(.endToEndTurn, 0.200)
        await telemetry.recordLatency(.endToEndTurn, 0.300)
        
        let metrics = await telemetry.currentMetrics
        XCTAssertEqual(metrics.e2eLatencies.median, 0.200, accuracy: 0.001)
    }
    
    func testRecordLatency_calculatesP99() async {
        // Add 100 latency values
        for i in 1...100 {
            await telemetry.recordLatency(.endToEndTurn, Double(i) / 1000.0)
        }
        
        let metrics = await telemetry.currentMetrics
        let p99 = metrics.e2eLatencies.percentile(99)
        
        // P99 should be close to 0.099 (99ms)
        XCTAssertGreaterThan(p99, 0.095)
    }
    
    // MARK: - Cost Tracking Tests
    
    func testRecordCost_STT_accumulatesCost() async {
        await telemetry.recordCost(.stt, amount: Decimal(string: "0.0001")!, description: "1 minute of audio")
        await telemetry.recordCost(.stt, amount: Decimal(string: "0.0001")!, description: "1 minute of audio")
        
        let metrics = await telemetry.currentMetrics
        XCTAssertEqual(metrics.sttCost, Decimal(string: "0.0002")!)
    }
    
    func testRecordCost_TTS_accumulatesCost() async {
        await telemetry.recordCost(.tts, amount: Decimal(string: "0.00015")!, description: "1000 characters")
        
        let metrics = await telemetry.currentMetrics
        XCTAssertEqual(metrics.ttsCost, Decimal(string: "0.00015")!)
    }
    
    func testRecordCost_LLM_tracksSeparately() async {
        await telemetry.recordCost(.llmInput, amount: Decimal(string: "0.0003")!, description: "1000 tokens")
        await telemetry.recordCost(.llmOutput, amount: Decimal(string: "0.0006")!, description: "500 tokens")
        
        let metrics = await telemetry.currentMetrics
        let cost = NSDecimalNumber(decimal: metrics.llmCost).doubleValue
        XCTAssertEqual(cost, 0.0009, accuracy: 0.000001)
    }
    
    func testTotalCost_sumAllCategories() async {
        await telemetry.recordCost(.stt, amount: Decimal(string: "0.01")!, description: "10 min audio")
        await telemetry.recordCost(.tts, amount: Decimal(string: "0.02")!, description: "20k chars")
        await telemetry.recordCost(.llmInput, amount: Decimal(string: "0.03")!, description: "input")
        await telemetry.recordCost(.llmOutput, amount: Decimal(string: "0.04")!, description: "output")
        
        let metrics = await telemetry.currentMetrics
        XCTAssertEqual(metrics.totalCost, Decimal(string: "0.10")!)
    }
    
    // MARK: - Session Metrics Tests
    
    func testSessionDuration_tracksElapsedTime() async {
        await telemetry.startSession()
        
        // Wait a bit
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let metrics = await telemetry.currentMetrics
        XCTAssertGreaterThan(metrics.duration, 0.05)
    }
    
    func testTurnCount_incrementsCorrectly() async {
        await telemetry.startSession()
        await telemetry.recordEvent(.userFinishedSpeaking(transcript: "Hello"))
        await telemetry.recordEvent(.userFinishedSpeaking(transcript: "How are you?"))
        
        let metrics = await telemetry.currentMetrics
        XCTAssertEqual(metrics.turnsTotal, 2)
    }
    
    func testInterruptionCount_tracksInterruptions() async {
        await telemetry.startSession()
        await telemetry.recordEvent(.userInterrupted)
        await telemetry.recordEvent(.userInterrupted)
        
        let metrics = await telemetry.currentMetrics
        XCTAssertEqual(metrics.interruptions, 2)
    }
    
    // MARK: - Cost Per Hour Tests
    
    func testCostPerHour_calculatesCorrectly() async {
        await telemetry.startSession()
        
        // Simulate 1 minute of session with $0.05 cost
        await telemetry.recordCost(.stt, amount: 0.05, description: "test")
        
        // Wait to ensure some duration
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let metrics = await telemetry.currentMetrics
        // Cost per hour should be calculated from actual duration
        XCTAssertGreaterThan(metrics.costPerHour, 0)
    }
    
    // MARK: - Reset Tests
    
    func testReset_clearsAllMetrics() async {
        await telemetry.startSession()
        await telemetry.recordLatency(.endToEndTurn, 0.5)
        await telemetry.recordCost(.stt, amount: 0.01, description: "test")
        await telemetry.recordEvent(.sessionStarted)
        
        await telemetry.reset()
        
        let metrics = await telemetry.currentMetrics
        XCTAssertEqual(metrics.totalCost, Decimal.zero)
        XCTAssertTrue(metrics.e2eLatencies.isEmpty)
    }
    
    // MARK: - Export Tests
    
    func testExportMetrics_createsValidSnapshot() async {
        await telemetry.startSession()
        await telemetry.recordLatency(.sttEmission, 0.150)
        await telemetry.recordCost(.stt, amount: 0.01, description: "test")

        let snapshot = await telemetry.exportMetrics()

        XCTAssertEqual(snapshot.latencies.sttMedianMs, 150)
        XCTAssertEqual(snapshot.costs.sttTotal, Decimal(string: "0.01")!)
    }

    // MARK: - Array Extension Tests

    func testStandardDeviation_emptyArray_returnsZero() {
        let values: [TimeInterval] = []
        XCTAssertEqual(values.standardDeviation, 0)
    }

    func testStandardDeviation_singleValue_returnsZero() {
        let values: [TimeInterval] = [5.0]
        XCTAssertEqual(values.standardDeviation, 0)
    }

    func testStandardDeviation_uniformValues_returnsZero() {
        let values: [TimeInterval] = [3.0, 3.0, 3.0, 3.0]
        XCTAssertEqual(values.standardDeviation, 0, accuracy: 0.0001)
    }

    func testStandardDeviation_knownValues_calculatesCorrectly() {
        // Values: 2, 4, 4, 4, 5, 5, 7, 9
        // Mean = 5, Sample variance = 4.571, StdDev = 2.138
        let values: [TimeInterval] = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
        let stdDev = values.standardDeviation
        XCTAssertEqual(stdDev, 2.138, accuracy: 0.01)
    }
}
