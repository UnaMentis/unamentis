// UnaMentis - Latency Test Result Models
// Data structures for capturing test execution results
//
// Part of the Audio Latency Test Harness

import Foundation

// MARK: - Test Result

/// Complete result from a single latency test execution
public struct TestResult: Codable, Sendable, Identifiable {
    public let id: UUID
    public let configId: String
    public let scenarioName: String
    public let repetition: Int
    public let timestamp: Date

    // MARK: - Per-Stage Latencies (milliseconds)

    /// Time from audio start to STT transcript (for audio input scenarios)
    public let sttLatencyMs: Double?

    /// Time from request to first LLM token
    public let llmTTFBMs: Double

    /// Time from request to LLM completion (all tokens received)
    public let llmCompletionMs: Double

    /// Time from TTS request to first audio byte
    public let ttsTTFBMs: Double

    /// Time from TTS request to all audio received
    public let ttsCompletionMs: Double

    /// End-to-end latency (full pipeline)
    public let e2eLatencyMs: Double

    // MARK: - Network Projections

    /// Network profile used for this test
    public let networkProfile: NetworkProfile

    /// Projected E2E latency for different network conditions
    public let networkProjections: [String: Double]

    // MARK: - Quality Metrics

    /// STT confidence score (0.0 - 1.0)
    public let sttConfidence: Float?

    /// Duration of synthesized audio in milliseconds
    public let ttsAudioDurationMs: Double?

    /// Number of LLM output tokens
    public let llmOutputTokens: Int?

    /// Number of LLM input tokens
    public let llmInputTokens: Int?

    // MARK: - Resource Utilization

    /// Peak CPU usage during test (0-100%)
    public let peakCPUPercent: Double

    /// Peak memory usage in megabytes
    public let peakMemoryMB: Double

    /// Most severe thermal state observed
    public let thermalState: String

    // MARK: - Configuration Snapshot

    /// Full STT configuration used
    public let sttConfig: STTTestConfig

    /// Full LLM configuration used
    public let llmConfig: LLMTestConfig

    /// Full TTS configuration used
    public let ttsConfig: TTSTestConfig

    /// Full audio engine configuration used
    public let audioConfig: AudioEngineTestConfig

    // MARK: - Errors

    /// Any errors that occurred during the test
    public let errors: [String]

    /// Whether the test completed successfully
    public var isSuccess: Bool {
        errors.isEmpty
    }

    public init(
        id: UUID = UUID(),
        configId: String,
        scenarioName: String,
        repetition: Int,
        timestamp: Date = Date(),
        sttLatencyMs: Double? = nil,
        llmTTFBMs: Double,
        llmCompletionMs: Double,
        ttsTTFBMs: Double,
        ttsCompletionMs: Double,
        e2eLatencyMs: Double,
        networkProfile: NetworkProfile,
        networkProjections: [String: Double] = [:],
        sttConfidence: Float? = nil,
        ttsAudioDurationMs: Double? = nil,
        llmOutputTokens: Int? = nil,
        llmInputTokens: Int? = nil,
        peakCPUPercent: Double,
        peakMemoryMB: Double,
        thermalState: String,
        sttConfig: STTTestConfig,
        llmConfig: LLMTestConfig,
        ttsConfig: TTSTestConfig,
        audioConfig: AudioEngineTestConfig,
        errors: [String] = []
    ) {
        self.id = id
        self.configId = configId
        self.scenarioName = scenarioName
        self.repetition = repetition
        self.timestamp = timestamp
        self.sttLatencyMs = sttLatencyMs
        self.llmTTFBMs = llmTTFBMs
        self.llmCompletionMs = llmCompletionMs
        self.ttsTTFBMs = ttsTTFBMs
        self.ttsCompletionMs = ttsCompletionMs
        self.e2eLatencyMs = e2eLatencyMs
        self.networkProfile = networkProfile
        self.networkProjections = networkProjections
        self.sttConfidence = sttConfidence
        self.ttsAudioDurationMs = ttsAudioDurationMs
        self.llmOutputTokens = llmOutputTokens
        self.llmInputTokens = llmInputTokens
        self.peakCPUPercent = peakCPUPercent
        self.peakMemoryMB = peakMemoryMB
        self.thermalState = thermalState
        self.sttConfig = sttConfig
        self.llmConfig = llmConfig
        self.ttsConfig = ttsConfig
        self.audioConfig = audioConfig
        self.errors = errors
    }

    /// Calculate network-adjusted projections
    public func withNetworkProjections() -> TestResult {
        var projections: [String: Double] = [:]

        for profile in NetworkProfile.allCases {
            var projected = e2eLatencyMs

            // Add network latency for each stage that requires network
            if sttConfig.requiresNetwork {
                projected += profile.addedLatencyMs
            }
            if llmConfig.requiresNetwork {
                projected += profile.addedLatencyMs
            }
            if ttsConfig.requiresNetwork {
                projected += profile.addedLatencyMs
            }

            projections[profile.rawValue] = projected
        }

        return TestResult(
            id: id,
            configId: configId,
            scenarioName: scenarioName,
            repetition: repetition,
            timestamp: timestamp,
            sttLatencyMs: sttLatencyMs,
            llmTTFBMs: llmTTFBMs,
            llmCompletionMs: llmCompletionMs,
            ttsTTFBMs: ttsTTFBMs,
            ttsCompletionMs: ttsCompletionMs,
            e2eLatencyMs: e2eLatencyMs,
            networkProfile: networkProfile,
            networkProjections: projections,
            sttConfidence: sttConfidence,
            ttsAudioDurationMs: ttsAudioDurationMs,
            llmOutputTokens: llmOutputTokens,
            llmInputTokens: llmInputTokens,
            peakCPUPercent: peakCPUPercent,
            peakMemoryMB: peakMemoryMB,
            thermalState: thermalState,
            sttConfig: sttConfig,
            llmConfig: llmConfig,
            ttsConfig: ttsConfig,
            audioConfig: audioConfig,
            errors: errors
        )
    }
}

// MARK: - Test Run

/// A complete test run (execution of a test suite)
public struct TestRun: Codable, Sendable, Identifiable {
    public let id: String
    public let suiteName: String
    public let suiteId: String
    public let startedAt: Date
    public var completedAt: Date?
    public let clientId: String
    public let clientDevice: String?
    public var status: RunStatus
    public let totalConfigurations: Int
    public var completedConfigurations: Int
    public var results: [TestResult]

    public init(
        id: String = "run_\(Date().formatted(.iso8601))",
        suiteName: String,
        suiteId: String,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        clientId: String,
        clientDevice: String? = nil,
        status: RunStatus = .running,
        totalConfigurations: Int,
        completedConfigurations: Int = 0,
        results: [TestResult] = []
    ) {
        self.id = id
        self.suiteName = suiteName
        self.suiteId = suiteId
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.clientId = clientId
        self.clientDevice = clientDevice
        self.status = status
        self.totalConfigurations = totalConfigurations
        self.completedConfigurations = completedConfigurations
        self.results = results
    }

    public enum RunStatus: String, Codable, Sendable {
        case pending = "pending"
        case running = "running"
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"
    }

    /// Progress as percentage (0-100)
    public var progressPercent: Double {
        guard totalConfigurations > 0 else { return 0 }
        return Double(completedConfigurations) / Double(totalConfigurations) * 100
    }

    /// Elapsed time since start
    public var elapsedTime: TimeInterval {
        let endTime = completedAt ?? Date()
        return endTime.timeIntervalSince(startedAt)
    }
}

// MARK: - Analysis Report

/// Analysis report for a test run
public struct AnalysisReport: Codable, Sendable {
    public let runId: String
    public let generatedAt: Date
    public let summary: SummaryStatistics
    public let bestConfigurations: [RankedConfiguration]
    public let networkProjections: [NetworkProjection]
    public let regressions: [Regression]
    public let recommendations: [String]

    public init(
        runId: String,
        generatedAt: Date = Date(),
        summary: SummaryStatistics,
        bestConfigurations: [RankedConfiguration],
        networkProjections: [NetworkProjection],
        regressions: [Regression] = [],
        recommendations: [String] = []
    ) {
        self.runId = runId
        self.generatedAt = generatedAt
        self.summary = summary
        self.bestConfigurations = bestConfigurations
        self.networkProjections = networkProjections
        self.regressions = regressions
        self.recommendations = recommendations
    }
}

// MARK: - Summary Statistics

/// Summary statistics for a test run
public struct SummaryStatistics: Codable, Sendable {
    public let totalConfigurations: Int
    public let totalTests: Int
    public let successfulTests: Int
    public let failedTests: Int

    // Overall latency stats (across all configs)
    public let overallMedianE2EMs: Double
    public let overallP99E2EMs: Double
    public let overallMinE2EMs: Double
    public let overallMaxE2EMs: Double

    // Per-stage medians
    public let medianSTTMs: Double?
    public let medianLLMTTFBMs: Double
    public let medianLLMCompletionMs: Double
    public let medianTTSTTFBMs: Double
    public let medianTTSCompletionMs: Double

    // Test duration
    public let testDurationMinutes: Double

    public init(
        totalConfigurations: Int,
        totalTests: Int,
        successfulTests: Int,
        failedTests: Int,
        overallMedianE2EMs: Double,
        overallP99E2EMs: Double,
        overallMinE2EMs: Double,
        overallMaxE2EMs: Double,
        medianSTTMs: Double? = nil,
        medianLLMTTFBMs: Double,
        medianLLMCompletionMs: Double,
        medianTTSTTFBMs: Double,
        medianTTSCompletionMs: Double,
        testDurationMinutes: Double
    ) {
        self.totalConfigurations = totalConfigurations
        self.totalTests = totalTests
        self.successfulTests = successfulTests
        self.failedTests = failedTests
        self.overallMedianE2EMs = overallMedianE2EMs
        self.overallP99E2EMs = overallP99E2EMs
        self.overallMinE2EMs = overallMinE2EMs
        self.overallMaxE2EMs = overallMaxE2EMs
        self.medianSTTMs = medianSTTMs
        self.medianLLMTTFBMs = medianLLMTTFBMs
        self.medianLLMCompletionMs = medianLLMCompletionMs
        self.medianTTSTTFBMs = medianTTSTTFBMs
        self.medianTTSCompletionMs = medianTTSCompletionMs
        self.testDurationMinutes = testDurationMinutes
    }
}

// MARK: - Ranked Configuration

/// A configuration ranked by performance
public struct RankedConfiguration: Codable, Sendable {
    public let rank: Int
    public let configId: String
    public let medianE2EMs: Double
    public let p99E2EMs: Double
    public let stddevMs: Double
    public let sampleCount: Int

    // Per-stage breakdown
    public let breakdown: LatencyBreakdown

    // Network projections
    public let networkProjections: [String: NetworkMeetsTarget]

    // Cost estimate
    public let estimatedCostPerHour: Double

    public init(
        rank: Int,
        configId: String,
        medianE2EMs: Double,
        p99E2EMs: Double,
        stddevMs: Double,
        sampleCount: Int,
        breakdown: LatencyBreakdown,
        networkProjections: [String: NetworkMeetsTarget],
        estimatedCostPerHour: Double
    ) {
        self.rank = rank
        self.configId = configId
        self.medianE2EMs = medianE2EMs
        self.p99E2EMs = p99E2EMs
        self.stddevMs = stddevMs
        self.sampleCount = sampleCount
        self.breakdown = breakdown
        self.networkProjections = networkProjections
        self.estimatedCostPerHour = estimatedCostPerHour
    }
}

/// Latency breakdown by stage
public struct LatencyBreakdown: Codable, Sendable {
    public let sttMs: Double?
    public let llmTTFBMs: Double
    public let llmCompletionMs: Double
    public let ttsTTFBMs: Double
    public let ttsCompletionMs: Double

    public init(
        sttMs: Double? = nil,
        llmTTFBMs: Double,
        llmCompletionMs: Double,
        ttsTTFBMs: Double,
        ttsCompletionMs: Double
    ) {
        self.sttMs = sttMs
        self.llmTTFBMs = llmTTFBMs
        self.llmCompletionMs = llmCompletionMs
        self.ttsTTFBMs = ttsTTFBMs
        self.ttsCompletionMs = ttsCompletionMs
    }
}

/// Network projection with target compliance
public struct NetworkMeetsTarget: Codable, Sendable {
    public let e2eMs: Double
    public let meets500ms: Bool
    public let meets1000ms: Bool

    public init(e2eMs: Double, meets500ms: Bool, meets1000ms: Bool) {
        self.e2eMs = e2eMs
        self.meets500ms = meets500ms
        self.meets1000ms = meets1000ms
    }
}

// MARK: - Network Projection

/// Network-adjusted projection for a test run
public struct NetworkProjection: Codable, Sendable {
    public let network: String
    public let addedLatencyMs: Double
    public let projectedMedianMs: Double
    public let projectedP99Ms: Double
    public let meetsTarget: Bool
    public let configsMeetingTarget: Int
    public let totalConfigs: Int

    public init(
        network: String,
        addedLatencyMs: Double,
        projectedMedianMs: Double,
        projectedP99Ms: Double,
        meetsTarget: Bool,
        configsMeetingTarget: Int,
        totalConfigs: Int
    ) {
        self.network = network
        self.addedLatencyMs = addedLatencyMs
        self.projectedMedianMs = projectedMedianMs
        self.projectedP99Ms = projectedP99Ms
        self.meetsTarget = meetsTarget
        self.configsMeetingTarget = configsMeetingTarget
        self.totalConfigs = totalConfigs
    }
}

// MARK: - Regression

/// Detected regression from baseline
public struct Regression: Codable, Sendable {
    public let configId: String
    public let metric: String
    public let baselineValue: Double
    public let currentValue: Double
    public let changePercent: Double
    public let severity: Severity

    public init(
        configId: String,
        metric: String,
        baselineValue: Double,
        currentValue: Double,
        changePercent: Double,
        severity: Severity
    ) {
        self.configId = configId
        self.metric = metric
        self.baselineValue = baselineValue
        self.currentValue = currentValue
        self.changePercent = changePercent
        self.severity = severity
    }

    public enum Severity: String, Codable, Sendable {
        case minor = "minor"       // 10-20% regression
        case moderate = "moderate" // 20-50% regression
        case severe = "severe"     // >50% regression
    }
}

// MARK: - Statistical Helpers

extension Array where Element == Double {

    /// Calculate median of the array
    public var median: Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let mid = count / 2
        if count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }

    /// Calculate percentile (0-100)
    public func percentile(_ p: Int) -> Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let index = Double(p) / 100.0 * Double(count - 1)
        let lower = Int(index)
        let upper = lower + 1
        let weight = index - Double(lower)

        if upper >= count {
            return sorted[lower]
        }
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    /// Calculate standard deviation
    public var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let mean = self.reduce(0, +) / Double(count)
        let squaredDiffs = self.map { ($0 - mean) * ($0 - mean) }
        let variance = squaredDiffs.reduce(0, +) / Double(count - 1)
        return variance.squareRoot()
    }
}
