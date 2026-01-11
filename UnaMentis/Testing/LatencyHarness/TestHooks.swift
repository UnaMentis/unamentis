// UnaMentis - Test Hooks for Automated Testing
// =============================================
//
// Provides programmatic hooks for automated testing infrastructure.
// These hooks enable external test orchestrators (like the mass test
// system) to trigger test scenarios without requiring UI interaction.
//
// ARCHITECTURE
// ------------
// TestHooks follows the same pattern as the web client's test-hooks.ts:
// - Singleton access for easy integration
// - Event-driven callbacks for test lifecycle
// - Direct access to test execution without UI dependencies
//
// USAGE
// -----
// ```swift
// // Register for test events
// await TestHooks.shared.onTestComplete { result in
//     print("Test completed: \(result.e2eLatencyMs)ms")
// }
//
// // Execute a test programmatically
// try await TestHooks.shared.executeTest(
//     stt: .deepgramNova3,
//     llm: .anthropic,
//     llmModel: "claude-3-5-haiku-20241022",
//     tts: .chatterbox,
//     utterance: "Hello, how are you?"
// )
// ```
//
// INTEGRATION WITH MASS TEST ORCHESTRATOR
// ---------------------------------------
// The orchestrator uses these hooks to:
// 1. Configure provider combinations
// 2. Execute tests with specific utterances
// 3. Collect latency metrics in real-time
// 4. Report results back to the server
//
// SEE ALSO
// --------
// - LatencyTestCoordinator.swift: Core test execution
// - LatencyMetricsCollector.swift: Metrics collection
// - server/web/src/lib/test-hooks.ts: Web client equivalent

import Foundation
import Logging
#if os(iOS)
import UIKit
#endif

// MARK: - Test Hook Events

/// Events emitted during test execution
public enum TestHookEvent: Sendable {
    case testStarted(configId: String, utterance: String)
    case sttComplete(latencyMs: Double, transcript: String)
    case llmFirstToken(ttfbMs: Double)
    case llmComplete(completionMs: Double, tokens: Int)
    case ttsFirstByte(ttfbMs: Double)
    case ttsComplete(completionMs: Double, audioDurationMs: Double)
    case testComplete(result: TestResult)
    case testFailed(error: String)
}

/// Callback type for test events
public typealias TestEventCallback = @Sendable (TestHookEvent) async -> Void

/// Callback type for test completion
public typealias TestCompleteCallback = @Sendable (TestResult) async -> Void

// MARK: - Test Hooks Actor

/// Singleton actor providing programmatic test hooks
///
/// Use this for automated testing scenarios where you need to:
/// - Execute tests without UI interaction
/// - Register callbacks for test events
/// - Configure provider combinations programmatically
public actor TestHooks {

    // MARK: - Singleton

    /// Shared instance for global access
    public static let shared = TestHooks()

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.test-hooks")
    private let coordinator: LatencyTestCoordinator
    private let metricsExporter: MetricsExporter

    // Event callbacks
    private var eventCallbacks: [UUID: TestEventCallback] = [:]
    private var completionCallbacks: [UUID: TestCompleteCallback] = [:]

    // State
    private var isReady = false
    private var serverURL: URL?
    private var clientId: String

    // MARK: - Initialization

    private init() {
        self.clientId = UserDefaults.standard.string(forKey: "TestHooksClientId")
            ?? UUID().uuidString
        UserDefaults.standard.set(self.clientId, forKey: "TestHooksClientId")

        self.coordinator = LatencyTestCoordinator(clientId: clientId)
        self.metricsExporter = MetricsExporter()
    }

    // MARK: - Configuration

    /// Configure the test hooks with server connection
    /// - Parameters:
    ///   - serverHost: Management server hostname
    ///   - port: Management server port (default 8766)
    public func configure(serverHost: String, port: Int = 8766) async {
        let url = URL(string: "http://\(serverHost):\(port)")!
        self.serverURL = url
        await coordinator.configureServer(url: url)
        await metricsExporter.configure(serverHost: serverHost, port: port)
        isReady = true
        logger.info("TestHooks configured with server: \(serverHost):\(port)")
    }

    /// Check if test hooks are ready
    public var ready: Bool {
        isReady
    }

    // MARK: - Event Registration

    /// Register a callback for test events
    /// - Parameter callback: Called for each test event
    /// - Returns: Subscription ID for later removal
    @discardableResult
    public func onEvent(_ callback: @escaping TestEventCallback) -> UUID {
        let id = UUID()
        eventCallbacks[id] = callback
        return id
    }

    /// Register a callback for test completion
    /// - Parameter callback: Called when a test completes
    /// - Returns: Subscription ID for later removal
    @discardableResult
    public func onTestComplete(_ callback: @escaping TestCompleteCallback) -> UUID {
        let id = UUID()
        completionCallbacks[id] = callback
        return id
    }

    /// Remove an event subscription
    public func removeSubscription(_ id: UUID) {
        eventCallbacks.removeValue(forKey: id)
        completionCallbacks.removeValue(forKey: id)
    }

    /// Remove all subscriptions
    public func removeAllSubscriptions() {
        eventCallbacks.removeAll()
        completionCallbacks.removeAll()
    }

    // MARK: - Test Execution

    /// Execute a single test with specified providers
    /// - Parameters:
    ///   - stt: Speech-to-text provider
    ///   - llm: Language model provider
    ///   - llmModel: Specific LLM model identifier
    ///   - tts: Text-to-speech provider
    ///   - ttsVoice: Optional TTS voice identifier
    ///   - utterance: Test utterance to process
    ///   - networkProfile: Network profile for projections
    /// - Returns: Test result with all latency metrics
    public func executeTest(
        stt: STTProvider = .deepgramNova3,
        llm: LLMProvider = .anthropic,
        llmModel: String = "claude-3-5-haiku-20241022",
        tts: TTSProvider = .chatterbox,
        ttsVoice: String? = nil,
        utterance: String,
        networkProfile: NetworkProfile = .localhost
    ) async throws -> TestResult {

        guard isReady else {
            throw TestHooksError.notConfigured
        }

        let configId = "hook_\(UUID().uuidString.prefix(8))"

        // Emit start event
        await emitEvent(.testStarted(configId: configId, utterance: utterance))

        logger.info("Executing test: stt=\(stt), llm=\(llm)/\(llmModel), tts=\(tts)")

        // Build test configuration
        let config = TestConfiguration(
            id: configId,
            sttConfig: STTTestConfig(
                provider: stt,
                requiresNetwork: stt.requiresNetwork
            ),
            llmConfig: LLMTestConfig(
                provider: llm,
                model: llmModel,
                requiresNetwork: llm != .localMLX
            ),
            ttsConfig: TTSTestConfig(
                provider: tts,
                voice: ttsVoice ?? tts.defaultVoice,
                requiresNetwork: tts.requiresNetwork
            ),
            audioConfig: AudioEngineTestConfig.default,
            networkProfile: networkProfile,
            scenarioName: "hook_test",
            repetitions: 1
        )

        do {
            // Configure and execute
            try await coordinator.configure(with: config)
            let result = try await coordinator.executeScenario(
                utterance: utterance,
                repetition: 1
            )

            // Emit completion events
            await emitEvent(.testComplete(result: result))
            await notifyCompletion(result)

            // Export to server
            await metricsExporter.export(result)

            return result

        } catch {
            let errorMessage = error.localizedDescription
            await emitEvent(.testFailed(error: errorMessage))
            throw TestHooksError.executionFailed(errorMessage)
        }
    }

    /// Execute a batch of tests with different configurations
    /// - Parameters:
    ///   - configurations: Array of test configurations
    ///   - utterances: Array of utterances to cycle through
    /// - Returns: Array of test results
    public func executeBatch(
        configurations: [TestConfiguration],
        utterances: [String]
    ) async throws -> [TestResult] {

        guard isReady else {
            throw TestHooksError.notConfigured
        }

        var results: [TestResult] = []

        for config in configurations {
            for (index, utterance) in utterances.enumerated() {
                do {
                    try await coordinator.configure(with: config)
                    let result = try await coordinator.executeScenario(
                        utterance: utterance,
                        repetition: index + 1
                    )
                    results.append(result)

                    await emitEvent(.testComplete(result: result))
                    await notifyCompletion(result)

                } catch {
                    logger.error("Batch test failed: \(error.localizedDescription)")
                    await emitEvent(.testFailed(error: error.localizedDescription))
                }
            }
        }

        // Export all results
        await metricsExporter.exportBatch(results)

        return results
    }

    // MARK: - Quick Test Methods

    /// Execute a quick validation test with default providers
    public func quickTest(utterance: String = "Hello, how are you?") async throws -> TestResult {
        try await executeTest(
            stt: .deepgramNova3,
            llm: .anthropic,
            llmModel: "claude-3-5-haiku-20241022",
            tts: .chatterbox,
            utterance: utterance
        )
    }

    /// Execute a provider comparison across common configurations
    public func compareProviders(utterance: String) async throws -> [TestResult] {
        let configs: [(LLMProvider, String, TTSProvider)] = [
            (.anthropic, "claude-3-5-haiku-20241022", .chatterbox),
            (.anthropic, "claude-3-5-sonnet-20241022", .chatterbox),
            (.openAI, "gpt-4o-mini", .chatterbox),
            (.openAI, "gpt-4o", .chatterbox),
        ]

        var results: [TestResult] = []

        for (llm, model, tts) in configs {
            do {
                let result = try await executeTest(
                    llm: llm,
                    llmModel: model,
                    tts: tts,
                    utterance: utterance
                )
                results.append(result)
            } catch {
                logger.error("Provider comparison failed for \(llm)/\(model): \(error)")
            }
        }

        return results
    }

    // MARK: - State Access

    /// Get current client ID
    public var currentClientId: String {
        clientId
    }

    /// Get current server URL
    public var currentServerURL: URL? {
        serverURL
    }

    // MARK: - Private Methods

    private func emitEvent(_ event: TestHookEvent) async {
        for callback in eventCallbacks.values {
            await callback(event)
        }
    }

    private func notifyCompletion(_ result: TestResult) async {
        for callback in completionCallbacks.values {
            await callback(result)
        }
    }
}

// MARK: - Test Hooks Errors

public enum TestHooksError: Error, LocalizedError {
    case notConfigured
    case executionFailed(String)
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "TestHooks not configured. Call configure() first."
        case .executionFailed(let message):
            return "Test execution failed: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}

// MARK: - Provider Extensions

extension STTProvider {
    /// Whether this provider requires network
    public var requiresNetwork: Bool {
        switch self {
        case .appleSpeech, .glmASROnDevice:
            return false
        default:
            return true
        }
    }
}

extension LLMProvider {
    /// Whether this provider requires network
    public var requiresNetwork: Bool {
        self != .localMLX
    }
}

extension TTSProvider {
    /// Whether this provider requires network
    public var requiresNetwork: Bool {
        switch self {
        case .appleTTS:
            return false
        default:
            return true
        }
    }

    /// Default voice for this provider
    public var defaultVoice: String {
        switch self {
        case .chatterbox:
            return "default"
        case .elevenLabsFlash, .elevenLabsTurbo:
            return "rachel"
        case .deepgramAura2:
            return "aura-asteria-en"
        case .appleTTS:
            return "com.apple.voice.compact.en-US.Samantha"
        default:
            return "default"
        }
    }
}
