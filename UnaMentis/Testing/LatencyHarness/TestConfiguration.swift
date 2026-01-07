// UnaMentis - Latency Test Configuration Models
// Data structures for defining latency test parameters
//
// Part of the Audio Latency Test Harness

import Foundation

// MARK: - Test Configuration

/// Complete configuration for a single latency test execution
public struct TestConfiguration: Codable, Sendable, Identifiable {
    public let id: String
    public let scenarioName: String
    public let repetition: Int

    // Provider configurations
    public let stt: STTTestConfig
    public let llm: LLMTestConfig
    public let tts: TTSTestConfig
    public let audioEngine: AudioEngineTestConfig

    // Network simulation
    public let networkProfile: NetworkProfile

    public init(
        id: String,
        scenarioName: String,
        repetition: Int,
        stt: STTTestConfig,
        llm: LLMTestConfig,
        tts: TTSTestConfig,
        audioEngine: AudioEngineTestConfig,
        networkProfile: NetworkProfile = .localhost
    ) {
        self.id = id
        self.scenarioName = scenarioName
        self.repetition = repetition
        self.stt = stt
        self.llm = llm
        self.tts = tts
        self.audioEngine = audioEngine
        self.networkProfile = networkProfile
    }

    /// Generate configuration ID from component settings
    public var configId: String {
        "\(stt.provider.identifier)_\(llm.provider.identifier)_\(llm.model)_\(tts.provider.identifier)"
    }
}

// MARK: - STT Test Configuration

/// STT provider configuration for testing
public struct STTTestConfig: Codable, Sendable {
    public let provider: STTProvider
    public let model: String?
    public let chunkSizeMs: Int?
    public let language: String

    public init(
        provider: STTProvider,
        model: String? = nil,
        chunkSizeMs: Int? = nil,
        language: String = "en-US"
    ) {
        self.provider = provider
        self.model = model
        self.chunkSizeMs = chunkSizeMs
        self.language = language
    }

    /// Whether this STT configuration requires network
    public var requiresNetwork: Bool {
        provider.requiresNetwork
    }

    public static let defaultDeepgram = STTTestConfig(
        provider: .deepgramNova3,
        model: "nova-3"
    )

    public static let defaultOnDevice = STTTestConfig(
        provider: .appleSpeech
    )
}

// MARK: - LLM Test Configuration

/// LLM provider configuration for testing
public struct LLMTestConfig: Codable, Sendable {
    public let provider: LLMProvider
    public let model: String
    public let maxTokens: Int
    public let temperature: Float
    public let topP: Float?
    public let stream: Bool

    public init(
        provider: LLMProvider,
        model: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float? = nil,
        stream: Bool = true
    ) {
        self.provider = provider
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stream = stream
    }

    /// Whether this LLM configuration requires network
    public var requiresNetwork: Bool {
        provider.requiresNetwork
    }

    /// Convert to LLMConfig for service usage
    public func toLLMConfig() -> LLMConfig {
        LLMConfig(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stream: stream
        )
    }

    public static let defaultClaude = LLMTestConfig(
        provider: .anthropic,
        model: "claude-3-5-haiku-20241022",
        maxTokens: 512,
        temperature: 0.7
    )

    public static let defaultSelfHosted = LLMTestConfig(
        provider: .selfHosted,
        model: "qwen2.5:7b",
        maxTokens: 512,
        temperature: 0.7
    )
}

// MARK: - TTS Test Configuration

/// TTS provider configuration for testing
public struct TTSTestConfig: Codable, Sendable {
    public let provider: TTSProvider
    public let voiceId: String?
    public let speed: Float
    public let useStreaming: Bool

    // Chatterbox-specific
    public let chatterboxConfig: ChatterboxConfig?

    public init(
        provider: TTSProvider,
        voiceId: String? = nil,
        speed: Float = 1.0,
        useStreaming: Bool = true,
        chatterboxConfig: ChatterboxConfig? = nil
    ) {
        self.provider = provider
        self.voiceId = voiceId
        self.speed = speed
        self.useStreaming = useStreaming
        self.chatterboxConfig = chatterboxConfig
    }

    /// Whether this TTS configuration requires network
    public var requiresNetwork: Bool {
        provider.requiresNetwork
    }

    /// Convert to TTSVoiceConfig for service usage
    public func toVoiceConfig() -> TTSVoiceConfig {
        TTSVoiceConfig(
            voiceId: voiceId ?? "default",
            rate: speed
        )
    }

    public static let defaultChatterbox = TTSTestConfig(
        provider: .chatterbox,
        useStreaming: true,
        chatterboxConfig: .lowLatency
    )

    public static let defaultOnDevice = TTSTestConfig(
        provider: .appleTTS,
        useStreaming: false
    )
}

// MARK: - Audio Engine Test Configuration

/// Audio engine configuration for testing
public struct AudioEngineTestConfig: Codable, Sendable {
    public let sampleRate: Double
    public let bufferSize: UInt32
    public let vadThreshold: Float
    public let vadSmoothingWindow: Int

    public init(
        sampleRate: Double = 24000,
        bufferSize: UInt32 = 1024,
        vadThreshold: Float = 0.5,
        vadSmoothingWindow: Int = 5
    ) {
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.vadThreshold = vadThreshold
        self.vadSmoothingWindow = vadSmoothingWindow
    }

    /// Convert to AudioEngineConfig for engine usage
    public func toAudioEngineConfig() -> AudioEngineConfig {
        AudioEngineConfig(
            sampleRate: sampleRate,
            vadThreshold: vadThreshold,
            vadSmoothingWindow: vadSmoothingWindow,
            bufferSize: bufferSize
        )
    }

    public static let `default` = AudioEngineTestConfig()

    public static let lowLatency = AudioEngineTestConfig(
        sampleRate: 24000,
        bufferSize: 512,
        vadThreshold: 0.4,
        vadSmoothingWindow: 3
    )
}

// MARK: - Network Profile

/// Simulated network condition profile
public enum NetworkProfile: String, Codable, Sendable, CaseIterable {
    case localhost = "localhost"
    case wifi = "wifi"
    case cellularUS = "cellular_us"
    case cellularEU = "cellular_eu"
    case intercontinental = "intercontinental"

    /// Expected additional round-trip latency in milliseconds
    public var addedLatencyMs: Double {
        switch self {
        case .localhost: return 0
        case .wifi: return 10
        case .cellularUS: return 50
        case .cellularEU: return 70
        case .intercontinental: return 120
        }
    }

    public var displayName: String {
        switch self {
        case .localhost: return "Localhost"
        case .wifi: return "WiFi"
        case .cellularUS: return "US Cellular"
        case .cellularEU: return "EU Cellular"
        case .intercontinental: return "Intercontinental"
        }
    }
}

// MARK: - Test Scenario

/// Definition of a test scenario
public struct TestScenario: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let scenarioType: ScenarioType
    public let repetitions: Int

    // For audio input scenarios
    public let userUtteranceAudioPath: String?

    // For text input scenarios (skip STT)
    public let userUtteranceText: String?

    // Expected response characteristics
    public let expectedResponseType: ResponseType

    public init(
        id: String,
        name: String,
        description: String,
        scenarioType: ScenarioType,
        repetitions: Int = 10,
        userUtteranceAudioPath: String? = nil,
        userUtteranceText: String? = nil,
        expectedResponseType: ResponseType = .medium
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.scenarioType = scenarioType
        self.repetitions = repetitions
        self.userUtteranceAudioPath = userUtteranceAudioPath
        self.userUtteranceText = userUtteranceText
        self.expectedResponseType = expectedResponseType
    }

    public enum ScenarioType: String, Codable, Sendable {
        case audioInput = "audio_input"    // Full pipeline: audio → STT → LLM → TTS
        case textInput = "text_input"      // Skip STT: text → LLM → TTS
        case ttsOnly = "tts_only"          // TTS benchmark only: text → TTS
        case conversation = "conversation" // Multi-turn conversation
    }

    public enum ResponseType: String, Codable, Sendable {
        case short = "short"     // 10-30 words
        case medium = "medium"   // 30-100 words
        case long = "long"       // 100-300 words

        /// Approximate word count range
        public var wordRange: ClosedRange<Int> {
            switch self {
            case .short: return 10...30
            case .medium: return 30...100
            case .long: return 100...300
            }
        }
    }
}

// MARK: - Test Suite Definition

/// Complete test suite definition
public struct TestSuiteDefinition: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let scenarios: [TestScenario]
    public let networkProfiles: [NetworkProfile]
    public let parameterSpace: ParameterSpace

    public init(
        id: String,
        name: String,
        description: String,
        scenarios: [TestScenario],
        networkProfiles: [NetworkProfile] = [.localhost],
        parameterSpace: ParameterSpace
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.scenarios = scenarios
        self.networkProfiles = networkProfiles
        self.parameterSpace = parameterSpace
    }

    /// Generate all test configurations from parameter space
    public func generateConfigurations() -> [TestConfiguration] {
        var configs: [TestConfiguration] = []
        var configIndex = 0

        for scenario in scenarios {
            for sttConfig in parameterSpace.sttConfigs {
                for llmConfig in parameterSpace.llmConfigs {
                    for ttsConfig in parameterSpace.ttsConfigs {
                        for audioConfig in parameterSpace.audioConfigs {
                            for networkProfile in networkProfiles {
                                for repetition in 1...scenario.repetitions {
                                    configIndex += 1
                                    let config = TestConfiguration(
                                        id: "config_\(configIndex)",
                                        scenarioName: scenario.name,
                                        repetition: repetition,
                                        stt: sttConfig,
                                        llm: llmConfig,
                                        tts: ttsConfig,
                                        audioEngine: audioConfig,
                                        networkProfile: networkProfile
                                    )
                                    configs.append(config)
                                }
                            }
                        }
                    }
                }
            }
        }

        return configs
    }

    /// Estimated total test count
    public var totalTestCount: Int {
        let scenarioReps = scenarios.reduce(0) { $0 + $1.repetitions }
        return scenarioReps
            * parameterSpace.sttConfigs.count
            * parameterSpace.llmConfigs.count
            * parameterSpace.ttsConfigs.count
            * parameterSpace.audioConfigs.count
            * networkProfiles.count
    }
}

// MARK: - Parameter Space

/// Defines the parameter space to explore
public struct ParameterSpace: Codable, Sendable {
    public let sttConfigs: [STTTestConfig]
    public let llmConfigs: [LLMTestConfig]
    public let ttsConfigs: [TTSTestConfig]
    public let audioConfigs: [AudioEngineTestConfig]

    public init(
        sttConfigs: [STTTestConfig],
        llmConfigs: [LLMTestConfig],
        ttsConfigs: [TTSTestConfig],
        audioConfigs: [AudioEngineTestConfig] = [.default]
    ) {
        self.sttConfigs = sttConfigs
        self.llmConfigs = llmConfigs
        self.ttsConfigs = ttsConfigs
        self.audioConfigs = audioConfigs
    }

    /// Quick validation parameter space (minimal combinations)
    public static let quickValidation = ParameterSpace(
        sttConfigs: [.defaultDeepgram],
        llmConfigs: [.defaultClaude],
        ttsConfigs: [.defaultChatterbox]
    )

    /// Provider comparison parameter space
    public static let providerComparison = ParameterSpace(
        sttConfigs: [
            .defaultDeepgram,
            STTTestConfig(provider: .assemblyAI),
            .defaultOnDevice
        ],
        llmConfigs: [
            .defaultClaude,
            LLMTestConfig(provider: .openAI, model: "gpt-4o-mini"),
            .defaultSelfHosted
        ],
        ttsConfigs: [
            .defaultChatterbox,
            TTSTestConfig(provider: .vibeVoice),
            .defaultOnDevice
        ]
    )
}

// MARK: - Predefined Test Suites

extension TestSuiteDefinition {

    /// Quick validation suite for CI/CD
    public static let quickValidation = TestSuiteDefinition(
        id: "quick_validation",
        name: "Quick Validation",
        description: "Fast sanity check for CI/CD pipelines",
        scenarios: [
            TestScenario(
                id: "short_response",
                name: "Short Response",
                description: "Brief Q&A exchange",
                scenarioType: .textInput,
                repetitions: 3,
                userUtteranceText: "What is the capital of France?",
                expectedResponseType: .short
            )
        ],
        parameterSpace: .quickValidation
    )

    /// Provider comparison suite
    public static let providerComparison = TestSuiteDefinition(
        id: "provider_comparison",
        name: "Provider Comparison",
        description: "Compare all available providers",
        scenarios: [
            TestScenario(
                id: "short_response",
                name: "Short Response",
                description: "Brief Q&A exchange",
                scenarioType: .textInput,
                repetitions: 10,
                userUtteranceText: "What is photosynthesis?",
                expectedResponseType: .short
            ),
            TestScenario(
                id: "medium_response",
                name: "Medium Response",
                description: "Moderate explanation",
                scenarioType: .textInput,
                repetitions: 5,
                userUtteranceText: "Explain how the human heart works.",
                expectedResponseType: .medium
            )
        ],
        networkProfiles: [.localhost, .wifi, .cellularUS],
        parameterSpace: .providerComparison
    )
}
