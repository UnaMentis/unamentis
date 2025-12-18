// VoiceLearn - Self-Hosted LLM Service
// OpenAI-compatible LLM service for self-hosted servers (Ollama, llama.cpp, vLLM, etc.)
//
// Part of Services/LLM

import Foundation
import Logging

/// Self-hosted LLM service compatible with OpenAI API format
///
/// Works with:
/// - Ollama (localhost:11434)
/// - llama.cpp server
/// - vLLM
/// - text-generation-webui
/// - Any OpenAI-compatible API
public actor SelfHostedLLMService: LLMService {

    // MARK: - Properties

    private let logger = Logger(label: "com.voicelearn.llm.selfhosted")
    private let baseURL: URL
    private let modelName: String
    private let authToken: String?

    /// Performance metrics
    public private(set) var metrics: LLMMetrics = LLMMetrics(
        medianTTFT: 0.1,  // Self-hosted typically faster TTFT
        p99TTFT: 0.3,
        totalInputTokens: 0,
        totalOutputTokens: 0
    )

    /// Cost per token (free for self-hosted)
    public var costPerInputToken: Decimal { 0 }
    public var costPerOutputToken: Decimal { 0 }

    /// Track TTFT for metrics
    private var ttftValues: [TimeInterval] = []
    private var totalInputTokensCount: Int = 0
    private var totalOutputTokensCount: Int = 0

    // MARK: - Initialization

    /// Initialize with explicit configuration
    /// - Parameters:
    ///   - baseURL: Base URL of the server (e.g., http://localhost:11434)
    ///   - modelName: Model name to use (e.g., "qwen2.5:7b", "llama3.2:3b")
    ///   - authToken: Optional authentication token
    public init(baseURL: URL, modelName: String, authToken: String? = nil) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.authToken = authToken
        logger.info("SelfHostedLLMService initialized: \(baseURL.absoluteString) with model \(modelName)")
    }

    /// Initialize from ServerConfig
    /// - Parameters:
    ///   - server: Server configuration
    ///   - modelName: Model name to use
    public init?(server: ServerConfig, modelName: String) {
        guard let baseURL = server.baseURL else {
            return nil
        }
        self.baseURL = baseURL
        self.modelName = modelName
        self.authToken = nil
        logger.info("SelfHostedLLMService initialized from server config: \(server.name)")
    }

    /// Initialize with auto-discovery
    /// Attempts to find a healthy self-hosted LLM server
    public init?() async {
        let serverManager = ServerConfigManager.shared
        let healthyServers = await serverManager.getHealthyLLMServers()

        guard let server = healthyServers.first,
              let baseURL = server.baseURL else {
            return nil
        }

        self.baseURL = baseURL
        // Try to get model from discovered services, or use default
        if let llmService = server.discoveredServices.first(where: { $0.type == .llm }),
           let model = llmService.model {
            self.modelName = model
        } else {
            self.modelName = "qwen2.5:7b"  // Default model
        }
        self.authToken = nil
    }

    // MARK: - LLMService Protocol

    public func streamCompletion(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> AsyncStream<LLMToken> {
        // For self-hosted services, prefer the constructor-provided model
        // Only use config.model if it looks like a valid Ollama model (not OpenAI)
        let openAIModels = ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        let effectiveModel: String
        if config.model.isEmpty || openAIModels.contains(config.model) {
            effectiveModel = modelName
        } else {
            effectiveModel = config.model
        }

        logger.info("Starting stream completion with model: \(effectiveModel)")
        let startTime = Date()

        // Build request URL - use /v1/chat/completions for OpenAI compatibility
        let completionsURL = baseURL.appendingPathComponent("v1/chat/completions")

        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth header if provided
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build message array
        var apiMessages: [[String: String]] = []

        if let systemPrompt = config.systemPrompt {
            apiMessages.append(["role": "system", "content": systemPrompt])
        }

        for message in messages {
            apiMessages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        var body: [String: Any] = [
            "model": effectiveModel,
            "messages": apiMessages,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "stream": config.stream
        ]

        if let topP = config.topP {
            body["top_p"] = topP
        }

        if let stops = config.stopSequences {
            body["stop"] = stops
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Estimate input tokens (rough: 4 chars per token)
        let inputChars = apiMessages.reduce(0) { $0 + ($1["content"]?.count ?? 0) }
        let estimatedInputTokens = inputChars / 4
        totalInputTokensCount += estimatedInputTokens

        return AsyncStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.connectionFailed("Invalid response")
                    }

                    if httpResponse.statusCode == 401 {
                        throw LLMError.authenticationFailed
                    }

                    if httpResponse.statusCode == 429 {
                        let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                            .flatMap { Double($0) }
                        throw LLMError.rateLimited(retryAfter: retryAfter)
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw LLMError.connectionFailed("HTTP \(httpResponse.statusCode)")
                    }

                    var isFirst = true
                    var outputTokens = 0
                    var lineBuffer = ""

                    for try await byte in bytes {
                        lineBuffer.append(Character(UnicodeScalar(byte)))

                        // Process complete lines
                        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
                            let line = String(lineBuffer[..<newlineIndex])
                            lineBuffer.removeSubrange(...newlineIndex)

                            // Parse SSE data
                            if line.hasPrefix("data: ") {
                                let jsonStr = String(line.dropFirst(6))

                                if jsonStr == "[DONE]" {
                                    continuation.yield(LLMToken(
                                        content: "",
                                        isDone: true,
                                        stopReason: .endTurn,
                                        tokenCount: outputTokens
                                    ))
                                    self.totalOutputTokensCount += outputTokens
                                    await self.updateMetrics()
                                    continuation.finish()
                                    return
                                }

                                if let data = jsonStr.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let choices = json["choices"] as? [[String: Any]],
                                   let firstChoice = choices.first,
                                   let delta = firstChoice["delta"] as? [String: Any] {

                                    // Content may be nil for role-only deltas
                                    let content = delta["content"] as? String ?? ""

                                    if isFirst && !content.isEmpty {
                                        let ttft = Date().timeIntervalSince(startTime)
                                        self.ttftValues.append(ttft)
                                        self.logger.debug("TTFT: \(String(format: "%.3f", ttft))s")
                                        isFirst = false
                                    }

                                    outputTokens += 1  // Rough estimate

                                    // Check for finish reason
                                    let finishReason = firstChoice["finish_reason"] as? String
                                    let stopReason: StopReason? = finishReason.flatMap { reason in
                                        switch reason {
                                        case "stop": return .endTurn
                                        case "length": return .maxTokens
                                        default: return nil
                                        }
                                    }

                                    continuation.yield(LLMToken(
                                        content: content,
                                        isDone: stopReason != nil,
                                        stopReason: stopReason
                                    ))
                                }
                            }
                        }
                    }

                    continuation.finish()

                } catch {
                    self.logger.error("LLM stream failed: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Non-Streaming Completion

    /// Perform a non-streaming completion
    public func complete(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> String {
        var nonStreamConfig = config
        nonStreamConfig.stream = false

        let completionsURL = baseURL.appendingPathComponent("v1/chat/completions")

        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var apiMessages: [[String: String]] = []

        if let systemPrompt = config.systemPrompt {
            apiMessages.append(["role": "system", "content": systemPrompt])
        }

        for message in messages {
            apiMessages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        let body: [String: Any] = [
            "model": modelName,
            "messages": apiMessages,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.connectionFailed("Request failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.connectionFailed("Invalid response format")
        }

        return content
    }

    // MARK: - Ollama-Specific Methods

    /// List available models on the server (Ollama-specific)
    public func listModels() async throws -> [String] {
        let modelsURL = baseURL.appendingPathComponent("api/tags")

        let (data, response) = try await URLSession.shared.data(from: modelsURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.connectionFailed("Failed to list models")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { $0["name"] as? String }
    }

    /// Pull a model (Ollama-specific)
    public func pullModel(_ modelName: String) async throws {
        let pullURL = baseURL.appendingPathComponent("api/pull")

        var request = URLRequest(url: pullURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": modelName])

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.connectionFailed("Failed to pull model")
        }

        logger.info("Model \(modelName) pull initiated")
    }

    // MARK: - Health Check

    /// Check if the server is healthy
    public func checkHealth() async -> Bool {
        // Try OpenAI-compatible health endpoint
        let healthURL = baseURL.appendingPathComponent("health")

        do {
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            // Try Ollama-specific version endpoint
            let versionURL = baseURL.appendingPathComponent("api/version")

            do {
                let (_, response) = try await URLSession.shared.data(from: versionURL)

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    return true
                }
            } catch {
                logger.warning("Health check failed: \(error.localizedDescription)")
            }
        }

        return false
    }

    // MARK: - Private Methods

    private func updateMetrics() {
        let sorted = ttftValues.sorted()
        let medianIndex = sorted.count / 2
        let p99Index = Int(Double(sorted.count) * 0.99)

        metrics = LLMMetrics(
            medianTTFT: sorted.isEmpty ? 0.1 : sorted[medianIndex],
            p99TTFT: sorted.isEmpty ? 0.3 : sorted[Swift.min(p99Index, Swift.max(0, sorted.count - 1))],
            totalInputTokens: totalInputTokensCount,
            totalOutputTokens: totalOutputTokensCount
        )
    }
}

// MARK: - Factory

extension SelfHostedLLMService {

    /// Create a service connected to local Ollama
    public static func ollama(
        host: String = "localhost",
        port: Int = 11434,
        model: String = "qwen2.5:7b"
    ) -> SelfHostedLLMService {
        let url = URL(string: "http://\(host):\(port)")!
        return SelfHostedLLMService(baseURL: url, modelName: model)
    }

    /// Create a service connected to VoiceLearn gateway
    public static func voicelearnGateway(
        host: String = "localhost",
        port: Int = 11400,
        model: String = "qwen2.5:7b"
    ) -> SelfHostedLLMService {
        let url = URL(string: "http://\(host):\(port)")!
        return SelfHostedLLMService(baseURL: url, modelName: model)
    }

    /// Create a service from auto-discovered server
    public static func autoDiscover() async -> SelfHostedLLMService? {
        await SelfHostedLLMService()
    }
}
