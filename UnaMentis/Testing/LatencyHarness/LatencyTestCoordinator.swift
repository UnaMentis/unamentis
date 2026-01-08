// UnaMentis - Latency Test Coordinator
// Main coordinator for executing latency tests on iOS
//
// Part of the Audio Latency Test Harness
//
// IMPORTANT: Observer Effect Mitigation
// =====================================
// All result reporting and logging is designed to be FIRE-AND-FORGET
// to avoid introducing latency into the measurements themselves.
//
// Key principles:
// 1. Timing uses mach_absolute_time (nanosecond precision, zero overhead)
// 2. Results are collected in memory during test execution
// 3. Reporting to server happens asynchronously AFTER measurement capture
// 4. No synchronous network I/O in the measurement path
// 5. Result queue handles batching and retries in background

import Foundation
import Logging
#if os(iOS)
import UIKit
#endif

// MARK: - Test Coordinator Error

public enum TestCoordinatorError: Error, Sendable {
    case notConfigured
    case providerCreationFailed(String)
    case testExecutionFailed(String)
    case serverCommunicationFailed(String)
    case scenarioNotSupported(String)
}

extension TestCoordinatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Test coordinator not configured. Call configure() first."
        case .providerCreationFailed(let message):
            return "Failed to create provider: \(message)"
        case .testExecutionFailed(let message):
            return "Test execution failed: \(message)"
        case .serverCommunicationFailed(let message):
            return "Server communication failed: \(message)"
        case .scenarioNotSupported(let message):
            return "Scenario not supported: \(message)"
        }
    }
}

// MARK: - Latency Test Coordinator

/// Coordinates latency test execution on iOS
///
/// This actor manages:
/// - Dynamic provider configuration based on test parameters
/// - Test scenario execution with precise timing
/// - Metrics collection and reporting to server
/// - Resource monitoring during tests
public actor LatencyTestCoordinator {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.latency-harness")
    private let metricsCollector = LatencyMetricsCollector()

    // Current test state
    private var currentConfig: TestConfiguration?
    private var currentRun: TestRun?

    // Providers (dynamically configured per test)
    private var sttService: (any STTService)?
    private var llmService: (any LLMService)?
    private var ttsService: (any TTSService)?

    // Server communication
    private var serverURL: URL?
    private var clientId: String

    // MARK: - Initialization

    public init(clientId: String = UUID().uuidString) {
        self.clientId = clientId
    }

    // MARK: - Server Configuration

    /// Configure connection to test orchestration server
    public func configureServer(url: URL) {
        self.serverURL = url
        logger.info("Configured server URL: \(url)")
    }

    // MARK: - Provider Configuration

    /// Configure providers for a specific test configuration
    public func configure(with config: TestConfiguration) async throws {
        logger.info("Configuring providers for test: \(config.id)")

        // Create STT service
        sttService = try await createSTTService(config.stt)

        // Create LLM service
        llmService = try await createLLMService(config.llm)

        // Create TTS service
        ttsService = try await createTTSService(config.tts)

        currentConfig = config
        logger.info("Providers configured successfully")
    }

    // MARK: - Test Execution

    /// Execute a single test scenario
    public func executeTest(
        scenario: TestScenario,
        config: TestConfiguration
    ) async throws -> TestResult {
        // Configure if needed
        if currentConfig?.id != config.id {
            try await configure(with: config)
        }

        guard let llmService = llmService,
              let ttsService = ttsService else {
            throw TestCoordinatorError.notConfigured
        }

        logger.info("Executing test: \(scenario.name) (rep \(config.repetition))")

        // Start metrics collection
        await metricsCollector.startTest(
            configId: config.configId,
            scenarioName: scenario.name,
            repetition: config.repetition,
            sttConfig: config.stt,
            llmConfig: config.llm,
            ttsConfig: config.tts,
            audioConfig: config.audioEngine,
            networkProfile: config.networkProfile
        )

        do {
            switch scenario.scenarioType {
            case .audioInput:
                try await executeAudioInputScenario(scenario, llmService: llmService, ttsService: ttsService)

            case .textInput:
                try await executeTextInputScenario(scenario, llmService: llmService, ttsService: ttsService)

            case .ttsOnly:
                try await executeTTSOnlyScenario(scenario, ttsService: ttsService)

            case .conversation:
                throw TestCoordinatorError.scenarioNotSupported("Conversation scenarios not yet implemented")
            }
        } catch {
            await metricsCollector.recordError(error)
        }

        // Finalize and return result
        let result = await metricsCollector.finalizeTest()
        logger.info("Test completed: E2E=\(String(format: "%.1f", result.e2eLatencyMs))ms")

        return result
    }

    /// Execute full test suite
    public func executeTestSuite(_ suite: TestSuiteDefinition) async throws -> TestRun {
        let configurations = suite.generateConfigurations()

        logger.info("Starting test suite: \(suite.name) with \(configurations.count) configurations")

        var run = TestRun(
            suiteName: suite.name,
            suiteId: suite.id,
            clientId: clientId,
            clientDevice: getDeviceInfo(),
            totalConfigurations: configurations.count
        )

        for (index, config) in configurations.enumerated() {
            // Find the scenario for this config
            guard let scenario = suite.scenarios.first(where: { $0.name == config.scenarioName }) else {
                continue
            }

            do {
                let result = try await executeTest(scenario: scenario, config: config)
                run.results.append(result)
                run.completedConfigurations = index + 1

                // Report progress
                logger.info("Progress: \(run.completedConfigurations)/\(run.totalConfigurations)")

            } catch {
                logger.error("Test failed: \(error.localizedDescription)")
                // Continue with next configuration
            }
        }

        run.status = .completed
        run.completedAt = Date()

        logger.info("Test suite completed: \(run.results.count) results")

        return run
    }

    // MARK: - Scenario Execution

    /// Execute text input scenario (skip STT, go directly to LLM)
    private func executeTextInputScenario(
        _ scenario: TestScenario,
        llmService: any LLMService,
        ttsService: any TTSService
    ) async throws {
        guard let userText = scenario.userUtteranceText else {
            throw TestCoordinatorError.testExecutionFailed("No user utterance text provided")
        }

        // Build messages
        let messages = [
            LLMMessage(role: .system, content: "You are a helpful tutor. Be concise."),
            LLMMessage(role: .user, content: userText)
        ]

        // Phase: LLM
        let llmPhase = TestPhaseTimer()
        var firstTokenReceived = false
        var fullResponse = ""
        var outputTokenCount = 0

        guard let config = currentConfig else {
            throw TestCoordinatorError.notConfigured
        }

        let stream = try await llmService.streamCompletion(
            messages: messages,
            config: config.llm.toLLMConfig()
        )

        for await token in stream {
            if !firstTokenReceived {
                firstTokenReceived = true
                await metricsCollector.recordLLMTTFB(llmPhase.elapsedMs)
            }
            fullResponse += token.content
            if let count = token.tokenCount {
                outputTokenCount = count
            }
        }

        await metricsCollector.recordLLMCompletion(llmPhase.elapsedMs)
        await metricsCollector.recordLLMTokenCounts(
            input: messages.reduce(0) { $0 + $1.content.count / 4 }, // Rough estimate
            output: outputTokenCount
        )

        // Phase: TTS
        let ttsPhase = TestPhaseTimer()
        var firstAudioReceived = false
        var totalAudioDurationMs: Double = 0

        let audioStream = try await ttsService.synthesize(text: fullResponse)

        for await chunk in audioStream {
            if !firstAudioReceived {
                firstAudioReceived = true
                await metricsCollector.recordTTSTTFB(ttsPhase.elapsedMs)
            }

            // Estimate audio duration from chunk size and format
            if case .pcmFloat32(let sampleRate, _) = chunk.format {
                let samples = chunk.audioData.count / 4 // 4 bytes per float32 sample
                let durationMs = Double(samples) / sampleRate * 1000.0
                totalAudioDurationMs += durationMs
            } else if case .pcmInt16(let sampleRate, _) = chunk.format {
                let samples = chunk.audioData.count / 2 // 2 bytes per int16 sample
                let durationMs = Double(samples) / sampleRate * 1000.0
                totalAudioDurationMs += durationMs
            }
        }

        await metricsCollector.recordTTSCompletion(ttsPhase.elapsedMs)
        await metricsCollector.recordTTSAudioDuration(totalAudioDurationMs)

        // Record E2E
        await metricsCollector.recordE2ELatencyFromTestStart()
    }

    /// Execute audio input scenario (full pipeline: STT → LLM → TTS)
    private func executeAudioInputScenario(
        _ scenario: TestScenario,
        llmService: any LLMService,
        ttsService: any TTSService
    ) async throws {
        guard let sttService = sttService else {
            throw TestCoordinatorError.notConfigured
        }

        // For now, use text input as fallback (audio file loading not implemented)
        // In production, this would load audio from scenario.userUtteranceAudioPath
        // and stream through STT

        if let fallbackText = scenario.userUtteranceText {
            // Use text input as fallback
            logger.warning("Audio input not implemented, using text fallback")
            try await executeTextInputScenario(scenario, llmService: llmService, ttsService: ttsService)
        } else {
            throw TestCoordinatorError.scenarioNotSupported("Audio input requires audio file or text fallback")
        }
    }

    /// Execute TTS-only scenario (benchmark TTS in isolation)
    private func executeTTSOnlyScenario(
        _ scenario: TestScenario,
        ttsService: any TTSService
    ) async throws {
        let testText: String
        switch scenario.expectedResponseType {
        case .short:
            testText = "The capital of France is Paris. It is known for the Eiffel Tower."
        case .medium:
            testText = """
            Photosynthesis is the process by which plants convert sunlight into energy. \
            During this process, plants absorb carbon dioxide from the air and water from the soil. \
            Using sunlight as energy, they convert these into glucose and oxygen. \
            The glucose provides energy for the plant to grow, while the oxygen is released into the atmosphere.
            """
        case .long:
            testText = """
            The human heart is a remarkable organ that serves as the body's primary circulatory pump. \
            Located in the chest cavity between the lungs, it beats approximately 100,000 times per day. \
            The heart consists of four chambers: two upper chambers called atria and two lower chambers called ventricles. \
            Deoxygenated blood returns to the right atrium from the body through the superior and inferior vena cava. \
            It then flows into the right ventricle, which pumps it to the lungs for oxygenation. \
            Oxygen-rich blood returns from the lungs to the left atrium, flows into the left ventricle, \
            and is then pumped throughout the body via the aorta. The heart's rhythmic contractions are \
            controlled by electrical signals originating from the sinoatrial node, often called the heart's \
            natural pacemaker. This intricate system ensures that every cell in your body receives the \
            oxygen and nutrients it needs to function properly.
            """
        }

        let ttsPhase = TestPhaseTimer()
        var firstAudioReceived = false
        var totalAudioDurationMs: Double = 0

        let audioStream = try await ttsService.synthesize(text: testText)

        for await chunk in audioStream {
            if !firstAudioReceived {
                firstAudioReceived = true
                await metricsCollector.recordTTSTTFB(ttsPhase.elapsedMs)
            }

            // Calculate duration from chunk
            if case .pcmFloat32(let sampleRate, _) = chunk.format {
                let samples = chunk.audioData.count / 4
                totalAudioDurationMs += Double(samples) / sampleRate * 1000.0
            } else if case .pcmInt16(let sampleRate, _) = chunk.format {
                let samples = chunk.audioData.count / 2
                totalAudioDurationMs += Double(samples) / sampleRate * 1000.0
            }
        }

        await metricsCollector.recordTTSCompletion(ttsPhase.elapsedMs)
        await metricsCollector.recordTTSAudioDuration(totalAudioDurationMs)

        // For TTS-only, E2E = TTS time
        await metricsCollector.recordE2ELatency(ttsPhase.elapsedMs)
    }

    // MARK: - Provider Factory

    private func createSTTService(_ config: STTTestConfig) async throws -> any STTService {
        switch config.provider {
        case .deepgramNova3:
            // Would create DeepgramSTTService
            throw TestCoordinatorError.providerCreationFailed("Deepgram STT requires API key configuration")

        case .assemblyAI:
            throw TestCoordinatorError.providerCreationFailed("AssemblyAI STT requires API key configuration")

        case .appleSpeech:
            return AppleSpeechSTTService()

        case .glmASRNano:
            throw TestCoordinatorError.providerCreationFailed("GLM-ASR requires server configuration")

        case .glmASROnDevice:
            throw TestCoordinatorError.providerCreationFailed("GLM-ASR On-Device not yet available")

        case .openAIWhisper, .groqWhisper:
            throw TestCoordinatorError.providerCreationFailed("Provider \(config.provider) not yet supported in test harness")
        }
    }

    private func createLLMService(_ config: LLMTestConfig) async throws -> any LLMService {
        switch config.provider {
        case .anthropic:
            // Would create AnthropicLLMService with config
            throw TestCoordinatorError.providerCreationFailed("Anthropic LLM requires API key configuration")

        case .openAI:
            throw TestCoordinatorError.providerCreationFailed("OpenAI LLM requires API key configuration")

        case .selfHosted:
            // Get endpoint from ServerConfigManager
            if let endpoint = await ServerConfigManager.shared.getBestLLMEndpoint() {
                return SelfHostedLLMService(baseURL: endpoint, model: config.model)
            }
            throw TestCoordinatorError.providerCreationFailed("No healthy self-hosted LLM server available")

        case .localMLX:
            throw TestCoordinatorError.providerCreationFailed("Local MLX not yet available")
        }
    }

    private func createTTSService(_ config: TTSTestConfig) async throws -> any TTSService {
        switch config.provider {
        case .chatterbox:
            // Get endpoint from ServerConfigManager
            let servers = await ServerConfigManager.shared.getHealthyChatterboxServers()
            if let server = servers.first, let baseURL = server.baseURL {
                let chatterboxConfig = config.chatterboxConfig ?? .default
                return ChatterboxTTSService(baseURL: baseURL, config: chatterboxConfig)
            }
            throw TestCoordinatorError.providerCreationFailed("No healthy Chatterbox server available")

        case .vibeVoice:
            let servers = await ServerConfigManager.shared.getHealthyTTSServers()
            if let server = servers.first(where: { $0.serverType == .vibeVoiceServer }),
               let baseURL = server.baseURL {
                return SelfHostedTTSService(baseURL: baseURL)
            }
            throw TestCoordinatorError.providerCreationFailed("No healthy VibeVoice server available")

        case .appleTTS:
            return AppleTTSService()

        case .selfHosted:
            // Piper TTS
            let servers = await ServerConfigManager.shared.getHealthyTTSServers()
            if let server = servers.first(where: { $0.serverType == .piperServer }),
               let baseURL = server.baseURL {
                return SelfHostedTTSService(baseURL: baseURL)
            }
            throw TestCoordinatorError.providerCreationFailed("No healthy Piper server available")

        case .deepgramAura2, .elevenLabsFlash, .elevenLabsTurbo, .playHT:
            throw TestCoordinatorError.providerCreationFailed("Provider \(config.provider) requires API key configuration")
        }
    }

    // MARK: - Utilities

    private func getDeviceInfo() -> String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return "Simulator"
        #endif
    }
}

// MARK: - Fire-and-Forget Result Reporter

/// Non-blocking result reporter that queues results for async server submission
///
/// CRITICAL: This actor is designed to never block the test execution path.
/// Results are queued immediately and sent to the server asynchronously.
public actor ResultReporter {

    private let logger = Logger(label: "com.unamentis.result-reporter")
    private var serverURL: URL?
    private var clientId: String
    private var runId: String?

    // Result queue
    private var pendingResults: [TestResult] = []
    private var reportTask: Task<Void, Never>?
    private var isRunning = false

    public init(clientId: String) {
        self.clientId = clientId
    }

    /// Configure server connection
    public func configure(serverURL: URL, runId: String) {
        self.serverURL = serverURL
        self.runId = runId
    }

    /// Start the background reporter
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        reportTask = Task {
            await reportLoop()
        }
    }

    /// Stop the reporter and flush pending results
    public func stop() async {
        isRunning = false
        reportTask?.cancel()

        // Final flush
        await flushResults()
    }

    /// Queue a result for async reporting (returns immediately)
    ///
    /// This method is designed to be called during test execution.
    /// It returns immediately without any blocking operations.
    public func enqueueResult(_ result: TestResult) {
        pendingResults.append(result)
    }

    /// Queue multiple results
    public func enqueueResults(_ results: [TestResult]) {
        pendingResults.append(contentsOf: results)
    }

    // MARK: - Background Reporting

    private func reportLoop() async {
        while isRunning {
            // Batch send every 2 seconds or when queue reaches 10 items
            if pendingResults.count >= 10 {
                await flushResults()
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            if !pendingResults.isEmpty {
                await flushResults()
            }
        }
    }

    private func flushResults() async {
        guard let serverURL = serverURL,
              let runId = runId,
              !pendingResults.isEmpty else { return }

        let batch = pendingResults
        pendingResults = []

        // Send batch to server (fire-and-forget - don't retry endlessly)
        do {
            try await sendResultBatch(batch, to: serverURL, runId: runId)
            logger.debug("Reported \(batch.count) results to server")
        } catch {
            logger.warning("Failed to report results: \(error.localizedDescription)")
            // Could implement retry logic here, but don't block
        }
    }

    private func sendResultBatch(_ results: [TestResult], to serverURL: URL, runId: String) async throws {
        let url = serverURL.appendingPathComponent("/api/latency-tests/runs/\(runId)/results")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientId, forHTTPHeaderField: "X-Client-ID")

        let payload: [[String: Any]] = results.map { result in
            result.toDictionary()
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: ["results": payload])

        // Use short timeout - we don't want to block
        request.timeoutInterval = 5.0

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TestCoordinatorError.serverCommunicationFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
    }
}

// MARK: - Analysis Extension

extension LatencyTestCoordinator {

    /// Analyze results from a test run
    public func analyzeResults(_ run: TestRun) -> AnalysisReport {
        let results = run.results

        // Group results by configuration
        var byConfig: [String: [TestResult]] = [:]
        for result in results {
            byConfig[result.configId, default: []].append(result)
        }

        // Calculate per-config statistics
        var rankedConfigs: [RankedConfiguration] = []
        var rank = 0

        for (configId, configResults) in byConfig {
            rank += 1
            let e2eLatencies = configResults.map { $0.e2eLatencyMs }

            let breakdown = LatencyBreakdown(
                sttMs: configResults.compactMap { $0.sttLatencyMs }.median,
                llmTTFBMs: configResults.map { $0.llmTTFBMs }.median,
                llmCompletionMs: configResults.map { $0.llmCompletionMs }.median,
                ttsTTFBMs: configResults.map { $0.ttsTTFBMs }.median,
                ttsCompletionMs: configResults.map { $0.ttsCompletionMs }.median
            )

            // Network projections for this config
            var networkProjections: [String: NetworkMeetsTarget] = [:]
            if let firstResult = configResults.first {
                for profile in NetworkProfile.allCases {
                    if let projected = firstResult.networkProjections[profile.rawValue] {
                        networkProjections[profile.rawValue] = NetworkMeetsTarget(
                            e2eMs: projected,
                            meets500ms: projected < 500,
                            meets1000ms: projected < 1000
                        )
                    }
                }
            }

            rankedConfigs.append(RankedConfiguration(
                rank: rank,
                configId: configId,
                medianE2EMs: e2eLatencies.median,
                p99E2EMs: e2eLatencies.percentile(99),
                stddevMs: e2eLatencies.standardDeviation,
                sampleCount: configResults.count,
                breakdown: breakdown,
                networkProjections: networkProjections,
                estimatedCostPerHour: 0 // TODO: Calculate from provider costs
            ))
        }

        // Sort by median E2E
        rankedConfigs.sort { $0.medianE2EMs < $1.medianE2EMs }
        for i in 0..<rankedConfigs.count {
            rankedConfigs[i] = RankedConfiguration(
                rank: i + 1,
                configId: rankedConfigs[i].configId,
                medianE2EMs: rankedConfigs[i].medianE2EMs,
                p99E2EMs: rankedConfigs[i].p99E2EMs,
                stddevMs: rankedConfigs[i].stddevMs,
                sampleCount: rankedConfigs[i].sampleCount,
                breakdown: rankedConfigs[i].breakdown,
                networkProjections: rankedConfigs[i].networkProjections,
                estimatedCostPerHour: rankedConfigs[i].estimatedCostPerHour
            )
        }

        // Overall statistics
        let allE2E = results.map { $0.e2eLatencyMs }
        let summary = SummaryStatistics(
            totalConfigurations: byConfig.count,
            totalTests: results.count,
            successfulTests: results.filter { $0.isSuccess }.count,
            failedTests: results.filter { !$0.isSuccess }.count,
            overallMedianE2EMs: allE2E.median,
            overallP99E2EMs: allE2E.percentile(99),
            overallMinE2EMs: allE2E.min() ?? 0,
            overallMaxE2EMs: allE2E.max() ?? 0,
            medianSTTMs: results.compactMap { $0.sttLatencyMs }.median,
            medianLLMTTFBMs: results.map { $0.llmTTFBMs }.median,
            medianLLMCompletionMs: results.map { $0.llmCompletionMs }.median,
            medianTTSTTFBMs: results.map { $0.ttsTTFBMs }.median,
            medianTTSCompletionMs: results.map { $0.ttsCompletionMs }.median,
            testDurationMinutes: run.elapsedTime / 60.0
        )

        // Network projections (aggregate)
        var networkProjections: [NetworkProjection] = []
        for profile in NetworkProfile.allCases {
            let projectedValues = results.compactMap { $0.networkProjections[profile.rawValue] }
            if !projectedValues.isEmpty {
                let meetingTarget = projectedValues.filter { $0 < 500 }.count
                networkProjections.append(NetworkProjection(
                    network: profile.displayName,
                    addedLatencyMs: profile.addedLatencyMs,
                    projectedMedianMs: projectedValues.median,
                    projectedP99Ms: projectedValues.percentile(99),
                    meetsTarget: projectedValues.median < 500,
                    configsMeetingTarget: meetingTarget,
                    totalConfigs: byConfig.count
                ))
            }
        }

        // Generate recommendations
        var recommendations: [String] = []
        if let best = rankedConfigs.first {
            recommendations.append("Best configuration: \(best.configId) with \(String(format: "%.0f", best.medianE2EMs))ms median E2E")
            if best.medianE2EMs < 500 {
                recommendations.append("Target of <500ms median achieved on localhost")
            }
        }

        return AnalysisReport(
            runId: run.id,
            summary: summary,
            bestConfigurations: rankedConfigs,
            networkProjections: networkProjections,
            recommendations: recommendations
        )
    }
}
