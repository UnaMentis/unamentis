// UnaMentis - LLM Service Protocol
// Protocol defining Language Model interface
//
// Part of the Provider Abstraction Layer (TDD Section 6)

import Foundation

// MARK: - LLM Message

/// Message for LLM conversation
public struct LLMMessage: Codable, Sendable {
    /// Role of the message sender
    public let role: Role
    
    /// Message content
    public let content: String
    
    /// Message role
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }
    
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - LLM Token

/// Token emitted during streaming completion
public struct LLMToken: Sendable {
    /// Token content
    public let content: String
    
    /// Whether this is the final token
    public let isDone: Bool
    
    /// Stop reason if done
    public let stopReason: StopReason?
    
    /// Token count (if available)
    public let tokenCount: Int?
    
    public init(content: String, isDone: Bool, stopReason: StopReason? = nil, tokenCount: Int? = nil) {
        self.content = content
        self.isDone = isDone
        self.stopReason = stopReason
        self.tokenCount = tokenCount
    }
}

/// Reason the LLM stopped generating
public enum StopReason: String, Codable, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
}

// MARK: - LLM Configuration

/// Configuration for LLM requests
public struct LLMConfig: Codable, Sendable {
    /// Model identifier
    public var model: String
    
    /// Maximum tokens to generate
    public var maxTokens: Int
    
    /// Temperature for sampling (0.0 - 2.0)
    public var temperature: Float
    
    /// Top-p sampling
    public var topP: Float?
    
    /// Stop sequences
    public var stopSequences: [String]?
    
    /// System prompt (if not in messages)
    public var systemPrompt: String?
    
    /// Streaming enabled
    public var stream: Bool
    
    public static let `default` = LLMConfig(
        model: "gpt-4o",
        maxTokens: 1024,
        temperature: 0.7,
        stream: true
    )
    
    /// Cost-optimized preset
    public static let costOptimized = LLMConfig(
        model: "gpt-4o-mini",
        maxTokens: 512,
        temperature: 0.5,
        stream: true
    )
    
    /// High quality preset
    public static let highQuality = LLMConfig(
        model: "gpt-4o",
        maxTokens: 2048,
        temperature: 0.8,
        stream: true
    )
    
    public init(
        model: String = "gpt-4o",
        maxTokens: Int = 1024,
        temperature: Float = 0.7,
        topP: Float? = nil,
        stopSequences: [String]? = nil,
        systemPrompt: String? = nil,
        stream: Bool = true
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.systemPrompt = systemPrompt
        self.stream = stream
    }
}

// MARK: - LLM Metrics

/// Performance metrics for LLM service
public struct LLMMetrics: Sendable {
    /// Median time to first token
    public var medianTTFT: TimeInterval
    
    /// 99th percentile TTFT
    public var p99TTFT: TimeInterval
    
    /// Total input tokens used
    public var totalInputTokens: Int
    
    /// Total output tokens generated
    public var totalOutputTokens: Int
    
    public init(medianTTFT: TimeInterval, p99TTFT: TimeInterval, totalInputTokens: Int, totalOutputTokens: Int) {
        self.medianTTFT = medianTTFT
        self.p99TTFT = p99TTFT
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
    }
}

// MARK: - LLM Service Protocol

/// Protocol for Language Model services
///
/// Implementations include:
/// - OpenAILLM: GPT-4o, GPT-4o-mini streaming
/// - AnthropicLLM: Claude 3.5 Sonnet, Haiku streaming
/// - LocalMLX: Local MLX models via MLX-Swift
public protocol LLMService: Actor {
    /// Performance metrics
    var metrics: LLMMetrics { get }

    /// Cost per input token (in USD)
    var costPerInputToken: Decimal { get }

    /// Cost per output token (in USD)
    var costPerOutputToken: Decimal { get }

    /// Model's context window size in tokens
    var contextWindowSize: Int { get }

    /// Stream a completion
    /// - Parameters:
    ///   - messages: Conversation messages
    ///   - config: LLM configuration
    /// - Returns: AsyncStream of tokens
    func streamCompletion(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> AsyncStream<LLMToken>

    /// Non-streaming completion (convenience)
    func complete(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> String

    /// Estimate token count for text
    /// - Parameter text: Text to count tokens for
    /// - Returns: Estimated token count
    func estimateTokenCount(_ text: String) -> Int

    /// Estimate token count for messages
    /// - Parameter messages: Messages to count tokens for
    /// - Returns: Estimated token count including message overhead
    func estimateTokenCount(for messages: [LLMMessage]) -> Int
}

// MARK: - Default Implementation

extension LLMService {
    /// Non-streaming completion by collecting stream
    public func complete(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> String {
        var result = ""
        let stream = try await streamCompletion(messages: messages, config: config)
        for await token in stream {
            result += token.content
        }
        return result
    }

    /// Default context window (128K for modern models)
    public var contextWindowSize: Int {
        128_000
    }

    /// Default token estimation: ~4 characters per token for English
    public func estimateTokenCount(_ text: String) -> Int {
        // Rough estimate: average of 4 characters per token
        // More accurate would use tiktoken or provider-specific tokenizer
        max(1, text.count / 4)
    }

    /// Default token estimation for messages
    /// Includes ~4 tokens overhead per message for role/formatting
    public func estimateTokenCount(for messages: [LLMMessage]) -> Int {
        var total = 0
        for message in messages {
            // ~4 tokens overhead for message structure (role, etc.)
            total += 4
            total += estimateTokenCount(message.content)
        }
        return total
    }
}

// MARK: - Token Estimation Utilities

/// Utilities for token estimation across different providers
public enum TokenEstimation {

    /// Estimate tokens using character-based heuristic
    /// - Parameters:
    ///   - text: Text to estimate
    ///   - charsPerToken: Average characters per token (default 4 for English)
    /// - Returns: Estimated token count
    public static func estimate(_ text: String, charsPerToken: Double = 4.0) -> Int {
        max(1, Int(Double(text.count) / charsPerToken))
    }

    /// Estimate tokens for messages with overhead
    /// - Parameters:
    ///   - messages: Messages to estimate
    ///   - messageOverhead: Tokens per message for formatting (default 4)
    /// - Returns: Estimated token count
    public static func estimate(
        messages: [LLMMessage],
        messageOverhead: Int = 4
    ) -> Int {
        messages.reduce(0) { total, message in
            total + messageOverhead + estimate(message.content)
        }
    }

    /// Check if messages fit within a context window
    /// - Parameters:
    ///   - messages: Messages to check
    ///   - contextWindow: Maximum context window size
    ///   - reservedForOutput: Tokens to reserve for model output
    /// - Returns: Whether messages fit
    public static func fitsInContext(
        messages: [LLMMessage],
        contextWindow: Int,
        reservedForOutput: Int = 2000
    ) -> Bool {
        let estimated = estimate(messages: messages)
        return estimated < (contextWindow - reservedForOutput)
    }
}

// MARK: - LLM Provider Enum

/// Available LLM provider implementations
public enum LLMProvider: String, Codable, Sendable, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic Claude"
    case selfHosted = "Self-Hosted"
    case localMLX = "Local MLX"

    /// Display name for UI
    public var displayName: String {
        rawValue
    }

    /// Short identifier
    public var identifier: String {
        switch self {
        case .openAI: return "openai"
        case .anthropic: return "anthropic"
        case .selfHosted: return "selfhosted"
        case .localMLX: return "mlx"
        }
    }

    /// Available models for this provider
    public var availableModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
        case .anthropic:
            return ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        case .selfHosted:
            return ["qwen2.5:7b", "qwen2.5:3b", "llama3.2:3b", "llama3.2:1b", "mistral:7b"]
        case .localMLX:
            return ["ministral-3b (on-device)"]  // Ministral 3B on-device via llama.cpp
        }
    }

    /// Whether this provider requires network connectivity
    public var requiresNetwork: Bool {
        switch self {
        case .localMLX: return false
        case .selfHosted: return true  // Local network, but still network
        default: return true
        }
    }

    /// Whether this provider is free (no API cost)
    public var isFree: Bool {
        switch self {
        case .selfHosted, .localMLX: return true
        default: return false
        }
    }
}

// MARK: - LLM Errors

/// Errors that can occur during LLM processing
public enum LLMError: Error, Sendable {
    case connectionFailed(String)
    case streamFailed(String)
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case quotaExceeded
    case invalidRequest(String)
    case modelNotFound(String)
    case contentFiltered
    case contextLengthExceeded(maxTokens: Int)
}

extension LLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "LLM connection failed: \(message)"
        case .streamFailed(let message):
            return "LLM streaming failed: \(message)"
        case .authenticationFailed:
            return "LLM authentication failed"
        case .rateLimited(let retryAfter):
            if let delay = retryAfter {
                return "Rate limited. Retry after \(Int(delay)) seconds."
            }
            return "LLM rate limit exceeded"
        case .quotaExceeded:
            return "LLM quota exceeded"
        case .invalidRequest(let message):
            return "Invalid LLM request: \(message)"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .contentFiltered:
            return "Content was filtered by safety systems"
        case .contextLengthExceeded(let maxTokens):
            return "Context length exceeded maximum of \(maxTokens) tokens"
        }
    }
}
