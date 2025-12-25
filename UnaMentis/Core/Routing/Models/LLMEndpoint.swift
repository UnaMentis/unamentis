// UnaMentis - LLM Endpoint Model
// Defines LLM endpoint configuration for the Patch Panel routing system
//
// Part of Core/Routing (Patch Panel Architecture)
//
// An endpoint represents a single LLM inference target - could be a cloud API,
// a self-hosted server, or an on-device model. Each endpoint has:
// - Connection configuration (how to reach it)
// - Capability profile (what it can do)
// - Cost profile (how much it costs)
// - Performance profile (how fast it is)
// - Current status (is it available?)

import Foundation

// MARK: - LLM Endpoint

/// Represents a single LLM inference endpoint
///
/// Endpoints are the targets for routing decisions. The Patch Panel routes
/// task requests to endpoints based on task requirements, endpoint capabilities,
/// and current conditions (thermal state, network, budget, etc.)
///
/// ## Example Usage
/// ```swift
/// let gpt4o = LLMEndpoint(
///     id: "gpt-4o",
///     displayName: "GPT-4o (OpenAI)",
///     provider: .openAI,
///     location: .cloud,
///     maxContextTokens: 128_000,
///     ...
/// )
/// ```
public struct LLMEndpoint: Identifiable, Codable, Sendable {

    // MARK: - Identity

    /// Unique identifier for this endpoint (e.g., "gpt-4o", "llama-3b-device")
    public let id: String

    /// Human-readable display name (e.g., "GPT-4o (OpenAI)")
    public let displayName: String

    /// Provider that hosts this endpoint
    public let provider: EndpointProvider

    /// Physical location of the endpoint
    public let location: EndpointLocation

    // MARK: - Capabilities

    /// Maximum input context tokens supported
    public let maxContextTokens: Int

    /// Maximum output tokens that can be generated
    public let maxOutputTokens: Int

    /// Whether this endpoint supports streaming responses
    public let supportsStreaming: Bool

    /// Whether this endpoint supports system prompts
    public let supportsSystemPrompt: Bool

    /// Whether this endpoint supports function/tool calling
    public let supportsFunctionCalling: Bool

    // MARK: - Performance

    /// Expected time to first token in milliseconds
    public let expectedTTFTMs: Int

    /// Expected tokens per second generation rate
    public let expectedTokensPerSec: Int

    /// Historical reliability score (0.0 - 1.0)
    public let reliabilityScore: Float

    // MARK: - Cost

    /// Cost per input token in USD (0 for free/on-device)
    public let costPerInputToken: Decimal

    /// Cost per output token in USD (0 for free/on-device)
    public let costPerOutputToken: Decimal

    // MARK: - Configuration

    /// Connection configuration for reaching this endpoint
    public var connectionConfig: EndpointConnectionConfig?

    // MARK: - Runtime State

    /// Current availability status
    public var status: EndpointStatus = .available

    /// Last time health was checked
    public var lastHealthCheck: Date = Date()

    // MARK: - Initialization

    public init(
        id: String,
        displayName: String,
        provider: EndpointProvider,
        location: EndpointLocation,
        maxContextTokens: Int,
        maxOutputTokens: Int,
        supportsStreaming: Bool,
        supportsSystemPrompt: Bool,
        supportsFunctionCalling: Bool,
        expectedTTFTMs: Int,
        expectedTokensPerSec: Int,
        reliabilityScore: Float,
        costPerInputToken: Decimal,
        costPerOutputToken: Decimal,
        connectionConfig: EndpointConnectionConfig? = nil,
        status: EndpointStatus = .available,
        lastHealthCheck: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.location = location
        self.maxContextTokens = maxContextTokens
        self.maxOutputTokens = maxOutputTokens
        self.supportsStreaming = supportsStreaming
        self.supportsSystemPrompt = supportsSystemPrompt
        self.supportsFunctionCalling = supportsFunctionCalling
        self.expectedTTFTMs = expectedTTFTMs
        self.expectedTokensPerSec = expectedTokensPerSec
        self.reliabilityScore = reliabilityScore
        self.costPerInputToken = costPerInputToken
        self.costPerOutputToken = costPerOutputToken
        self.connectionConfig = connectionConfig
        self.status = status
        self.lastHealthCheck = lastHealthCheck
    }

    // MARK: - Cost Estimation

    /// Estimate the cost for a given number of input and output tokens
    /// - Parameters:
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens
    /// - Returns: Estimated cost in USD
    public func estimateCost(inputTokens: Int, outputTokens: Int) -> Decimal {
        let inputCost = Decimal(inputTokens) * costPerInputToken
        let outputCost = Decimal(outputTokens) * costPerOutputToken
        return inputCost + outputCost
    }

    /// Whether this endpoint has zero cost (on-device or self-hosted)
    public var isFree: Bool {
        costPerInputToken == 0 && costPerOutputToken == 0
    }
}

// MARK: - Endpoint Provider

/// Provider/vendor for an LLM endpoint
public enum EndpointProvider: String, Codable, Sendable, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case selfHosted = "Self-Hosted"
    case onDevice = "On-Device"

    /// Short identifier for logging/metrics
    public var identifier: String {
        switch self {
        case .openAI: return "openai"
        case .anthropic: return "anthropic"
        case .selfHosted: return "selfhosted"
        case .onDevice: return "ondevice"
        }
    }

    /// Whether this provider requires network connectivity
    public var requiresNetwork: Bool {
        self != .onDevice
    }
}

// MARK: - Endpoint Location

/// Physical location of an LLM endpoint
public enum EndpointLocation: String, Codable, Sendable {
    /// Cloud-hosted API (OpenAI, Anthropic, etc.)
    case cloud

    /// Self-hosted server on local network (Ollama, llama.cpp, etc.)
    case localServer

    /// On-device inference (CoreML, MLX)
    case onDevice
}

// MARK: - Endpoint Status

/// Current availability status of an endpoint
public enum EndpointStatus: String, Codable, Sendable {
    /// Endpoint is available and working normally
    case available

    /// Endpoint is working but with degraded performance
    case degraded

    /// Endpoint is not reachable or not responding
    case unavailable

    /// Endpoint has been manually disabled
    case disabled

    /// Endpoint is loading (e.g., on-device model being loaded into memory)
    case loading

    /// Whether this status allows the endpoint to be used
    public var isUsable: Bool {
        self == .available || self == .degraded
    }
}

// MARK: - Connection Configuration

/// Configuration for connecting to an LLM endpoint
public struct EndpointConnectionConfig: Codable, Sendable {

    // MARK: - Cloud API Configuration

    /// Reference to API key in secure storage (not the actual key)
    public var apiKeyReference: String?

    /// Base URL for API requests
    public var baseURL: URL?

    /// API version string
    public var apiVersion: String?

    // MARK: - Local Server Configuration

    /// Server hostname or IP address
    public var serverHost: String?

    /// Server port number
    public var serverPort: Int?

    // MARK: - On-Device Configuration

    /// Path to CoreML model file
    public var modelPath: String?

    /// Compute units to use for inference
    public var computeUnits: ComputeUnits?

    // MARK: - Initialization

    public init(
        apiKeyReference: String? = nil,
        baseURL: URL? = nil,
        apiVersion: String? = nil,
        serverHost: String? = nil,
        serverPort: Int? = nil,
        modelPath: String? = nil,
        computeUnits: ComputeUnits? = nil
    ) {
        self.apiKeyReference = apiKeyReference
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.modelPath = modelPath
        self.computeUnits = computeUnits
    }

    // MARK: - Factory Methods

    /// Create configuration for a cloud API endpoint
    public static func cloudConfig(apiKeyReference: String, baseURL: URL, apiVersion: String? = nil) -> EndpointConnectionConfig {
        EndpointConnectionConfig(
            apiKeyReference: apiKeyReference,
            baseURL: baseURL,
            apiVersion: apiVersion
        )
    }

    /// Create configuration for a local server endpoint
    public static func serverConfig(host: String, port: Int) -> EndpointConnectionConfig {
        EndpointConnectionConfig(
            serverHost: host,
            serverPort: port
        )
    }

    /// Create configuration for an on-device endpoint
    public static func onDeviceConfig(modelPath: String, computeUnits: ComputeUnits = .cpuAndNeuralEngine) -> EndpointConnectionConfig {
        EndpointConnectionConfig(
            modelPath: modelPath,
            computeUnits: computeUnits
        )
    }
}

// MARK: - Compute Units

/// Compute units for on-device inference
public enum ComputeUnits: String, Codable, Sendable {
    /// CPU only
    case cpuOnly

    /// CPU and GPU
    case cpuAndGPU

    /// CPU and Neural Engine (recommended for efficiency)
    case cpuAndNeuralEngine

    /// All available compute units
    case all
}

// MARK: - Static Value Helpers

/// Helper to create Decimal from a static string that is known to be valid at compile time.
/// Uses preconditionFailure in debug to catch any typos during development.
private func staticDecimal(_ value: String) -> Decimal {
    guard let decimal = Decimal(string: value) else {
        preconditionFailure("Invalid static Decimal string: \(value)")
    }
    return decimal
}

/// Helper to create URL from a static string that is known to be valid at compile time.
/// Uses preconditionFailure in debug to catch any typos during development.
private func staticURL(_ value: String) -> URL {
    guard let url = URL(string: value) else {
        preconditionFailure("Invalid static URL string: \(value)")
    }
    return url
}

// MARK: - Default Registry

extension LLMEndpoint {
    /// Default registry of known LLM endpoints
    ///
    /// This provides a starting point with common endpoints pre-configured.
    /// Users can customize this registry through the Patch Panel settings.
    public static let defaultRegistry: [String: LLMEndpoint] = [
        // MARK: OpenAI Cloud Endpoints

        "gpt-4o": LLMEndpoint(
            id: "gpt-4o",
            displayName: "GPT-4o (OpenAI)",
            provider: .openAI,
            location: .cloud,
            maxContextTokens: 128_000,
            maxOutputTokens: 4_096,
            supportsStreaming: true,
            supportsSystemPrompt: true,
            supportsFunctionCalling: true,
            expectedTTFTMs: 300,
            expectedTokensPerSec: 80,
            reliabilityScore: 0.99,
            costPerInputToken: staticDecimal("0.0000025"),   // $2.50/1M
            costPerOutputToken: staticDecimal("0.00001"),    // $10/1M
            connectionConfig: .cloudConfig(
                apiKeyReference: "openai_api_key",
                baseURL: staticURL("https://api.openai.com/v1")
            )
        ),

        "gpt-4o-mini": LLMEndpoint(
            id: "gpt-4o-mini",
            displayName: "GPT-4o Mini (OpenAI)",
            provider: .openAI,
            location: .cloud,
            maxContextTokens: 128_000,
            maxOutputTokens: 4_096,
            supportsStreaming: true,
            supportsSystemPrompt: true,
            supportsFunctionCalling: true,
            expectedTTFTMs: 200,
            expectedTokensPerSec: 100,
            reliabilityScore: 0.99,
            costPerInputToken: staticDecimal("0.00000015"),  // $0.15/1M
            costPerOutputToken: staticDecimal("0.0000006"),  // $0.60/1M
            connectionConfig: .cloudConfig(
                apiKeyReference: "openai_api_key",
                baseURL: staticURL("https://api.openai.com/v1")
            )
        ),

        // MARK: Anthropic Cloud Endpoints

        "claude-3.5-sonnet": LLMEndpoint(
            id: "claude-3.5-sonnet",
            displayName: "Claude 3.5 Sonnet (Anthropic)",
            provider: .anthropic,
            location: .cloud,
            maxContextTokens: 200_000,
            maxOutputTokens: 8_192,
            supportsStreaming: true,
            supportsSystemPrompt: true,
            supportsFunctionCalling: true,
            expectedTTFTMs: 500,
            expectedTokensPerSec: 60,
            reliabilityScore: 0.98,
            costPerInputToken: staticDecimal("0.000003"),    // $3/1M
            costPerOutputToken: staticDecimal("0.000015"),   // $15/1M
            connectionConfig: .cloudConfig(
                apiKeyReference: "anthropic_api_key",
                baseURL: staticURL("https://api.anthropic.com/v1"),
                apiVersion: "2023-06-01"
            )
        ),

        "claude-3.5-haiku": LLMEndpoint(
            id: "claude-3.5-haiku",
            displayName: "Claude 3.5 Haiku (Anthropic)",
            provider: .anthropic,
            location: .cloud,
            maxContextTokens: 200_000,
            maxOutputTokens: 8_192,
            supportsStreaming: true,
            supportsSystemPrompt: true,
            supportsFunctionCalling: true,
            expectedTTFTMs: 300,
            expectedTokensPerSec: 100,
            reliabilityScore: 0.98,
            costPerInputToken: staticDecimal("0.0000008"),   // $0.80/1M
            costPerOutputToken: staticDecimal("0.000004"),   // $4/1M
            connectionConfig: .cloudConfig(
                apiKeyReference: "anthropic_api_key",
                baseURL: staticURL("https://api.anthropic.com/v1"),
                apiVersion: "2023-06-01"
            )
        ),

        // MARK: Self-Hosted Server Endpoints

        "llama-70b-server": LLMEndpoint(
            id: "llama-70b-server",
            displayName: "Llama 3.1 70B (Server)",
            provider: .selfHosted,
            location: .localServer,
            maxContextTokens: 8_192,
            maxOutputTokens: 2_048,
            supportsStreaming: true,
            supportsSystemPrompt: true,
            supportsFunctionCalling: false,
            expectedTTFTMs: 800,
            expectedTokensPerSec: 20,
            reliabilityScore: 0.90,
            costPerInputToken: 0,
            costPerOutputToken: 0,
            connectionConfig: .serverConfig(host: "localhost", port: 11434),
            status: .unavailable  // Needs to be configured
        ),

        "llama-8b-server": LLMEndpoint(
            id: "llama-8b-server",
            displayName: "Llama 3.1 8B (Server)",
            provider: .selfHosted,
            location: .localServer,
            maxContextTokens: 8_192,
            maxOutputTokens: 2_048,
            supportsStreaming: true,
            supportsSystemPrompt: true,
            supportsFunctionCalling: false,
            expectedTTFTMs: 300,
            expectedTokensPerSec: 100,
            reliabilityScore: 0.90,
            costPerInputToken: 0,
            costPerOutputToken: 0,
            connectionConfig: .serverConfig(host: "localhost", port: 11434),
            status: .unavailable  // Needs to be configured
        ),

        // MARK: On-Device Endpoints

        "llama-3b-device": LLMEndpoint(
            id: "llama-3b-device",
            displayName: "Llama 3.2 3B (On-Device)",
            provider: .onDevice,
            location: .onDevice,
            maxContextTokens: 4_096,
            maxOutputTokens: 512,
            supportsStreaming: true,
            supportsSystemPrompt: true,
            supportsFunctionCalling: false,
            expectedTTFTMs: 200,
            expectedTokensPerSec: 15,
            reliabilityScore: 0.95,
            costPerInputToken: 0,
            costPerOutputToken: 0,
            connectionConfig: .onDeviceConfig(
                modelPath: "llama-3.2-3b.mlmodelc",
                computeUnits: .cpuAndNeuralEngine
            ),
            status: .unavailable  // Needs model to be downloaded
        ),

        "llama-1b-device": LLMEndpoint(
            id: "llama-1b-device",
            displayName: "Llama 3.2 1B (On-Device)",
            provider: .onDevice,
            location: .onDevice,
            maxContextTokens: 4_096,
            maxOutputTokens: 512,
            supportsStreaming: true,
            supportsSystemPrompt: true,
            supportsFunctionCalling: false,
            expectedTTFTMs: 100,
            expectedTokensPerSec: 30,
            reliabilityScore: 0.95,
            costPerInputToken: 0,
            costPerOutputToken: 0,
            connectionConfig: .onDeviceConfig(
                modelPath: "llama-3.2-1b.mlmodelc",
                computeUnits: .cpuAndNeuralEngine
            ),
            status: .unavailable  // Needs model to be downloaded
        )
    ]
}
