// UnaMentis - On-Device LLM Service
// Local Language Model using llama.cpp (b7263+)
//
// This service provides fully on-device LLM inference with no network required.
// Uses llama.cpp XCFramework with C++ interop for efficient inference on Apple Silicon.
//
// Recommended models for iPhone (bundled):
// - Ministral-3B-Instruct-Q4_K_M (~2.1GB) - Primary model, requires llama.cpp ≥b7263
// - TinyLlama-1.1B-Chat-v1.0-Q4_K_M (~670MB) - Fallback for low-memory devices

import Foundation
import Logging
import llama

// MARK: - Batch Helpers

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seq_ids: [llama_seq_id], _ logits: Bool) {
    batch.token   [Int(batch.n_tokens)] = id
    batch.pos     [Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        batch.seq_id[Int(batch.n_tokens)]![Int(i)] = seq_ids[i]
    }
    batch.logits  [Int(batch.n_tokens)] = logits ? 1 : 0
    batch.n_tokens += 1
}

/// On-device LLM service using Stanford BDHG llama.cpp
///
/// Benefits:
/// - Free (no API costs)
/// - Works offline
/// - Privacy-preserving (data never leaves device)
/// - Low latency for short responses
public actor OnDeviceLLMService: LLMService {

    // MARK: - Types

    public enum OnDeviceLLMError: Error, LocalizedError {
        case modelNotFound(String)
        case modelLoadFailed(String)
        case inferenceError(String)
        case notConfigured

        public var errorDescription: String? {
            switch self {
            case .modelNotFound(let name): return "Model not found: \(name)"
            case .modelLoadFailed(let msg): return "Failed to load model: \(msg)"
            case .inferenceError(let msg): return "Inference error: \(msg)"
            case .notConfigured: return "On-device LLM not configured"
            }
        }
    }

    /// Configuration for on-device LLM
    public struct Configuration: Sendable {
        /// Path to GGUF model file
        public let modelPath: URL
        /// Context size (tokens)
        public let contextSize: UInt32
        /// Number of GPU layers
        public let gpuLayers: Int32

        public init(
            modelPath: URL,
            contextSize: UInt32 = 2048,
            gpuLayers: Int32 = 99
        ) {
            self.modelPath = modelPath
            self.contextSize = contextSize
            self.gpuLayers = gpuLayers
        }

        public static var `default`: Configuration {
            // Primary: Ministral 3B - high quality 3B model (requires llama.cpp ≥b7263)
            if let bundleMinistralPath = Bundle.main.url(
                forResource: "ministral-3b-instruct-q4_k_m",
                withExtension: "gguf"
            ) {
                return Configuration(modelPath: bundleMinistralPath, contextSize: 4096)
            }

            // Fallback to filesystem path for development
            let ministralPath = "models/ministral-3b-instruct-q4_k_m.gguf"
            if FileManager.default.fileExists(atPath: ministralPath) {
                return Configuration(modelPath: URL(fileURLWithPath: ministralPath), contextSize: 4096)
            }

            // Final fallback: TinyLlama 1.1B for low-memory devices
            if let bundleTinyLlamaPath = Bundle.main.url(
                forResource: "tinyllama-1.1b-chat-v1.0.Q4_K_M",
                withExtension: "gguf"
            ) {
                return Configuration(modelPath: bundleTinyLlamaPath)
            }

            return Configuration(modelPath: URL(fileURLWithPath: "models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"))
        }
    }

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.llm.ondevice")
    private static let staticLogger = Logger(label: "com.unamentis.llm.ondevice.static")
    private let configuration: Configuration

    // llama.cpp state
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var isLoaded: Bool = false

    // Token tracking
    private var totalInputTokens: Int = 0
    private var totalOutputTokens: Int = 0
    private var ttftMeasurements: [TimeInterval] = []

    /// Performance metrics
    public var metrics: LLMMetrics {
        let sortedTTFT = ttftMeasurements.sorted()
        let median = sortedTTFT.isEmpty ? 0.5 : sortedTTFT[sortedTTFT.count / 2]
        let p99Index = min(Int(Double(sortedTTFT.count) * 0.99), max(0, sortedTTFT.count - 1))
        let p99 = sortedTTFT.isEmpty ? 1.0 : sortedTTFT[p99Index]

        return LLMMetrics(
            medianTTFT: median,
            p99TTFT: p99,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens
        )
    }

    /// Cost per input token ($0 - free on-device)
    public var costPerInputToken: Decimal { Decimal(0) }

    /// Cost per output token ($0 - free on-device)
    public var costPerOutputToken: Decimal { Decimal(0) }

    // MARK: - Initialization

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        logger.info("OnDeviceLLMService initialized with model path: \(configuration.modelPath.path)")
    }

    deinit {
        // Note: Can't call unloadModel() here due to actor isolation
        // Ensure stopStreaming() or explicit cleanup is called before release
    }

    // MARK: - Model Loading

    public func loadModel() async throws {
        guard !isLoaded else {
            logger.debug("Model already loaded")
            return
        }

        // Use the configured model path
        let modelPath = configuration.modelPath.path

        logger.info("Loading on-device LLM from \(modelPath)")

        guard FileManager.default.fileExists(atPath: modelPath) else {
            logger.error("Model file not found at: \(modelPath)")
            throw OnDeviceLLMError.modelNotFound(configuration.modelPath.lastPathComponent)
        }

        logger.debug("Model file exists, initializing backend...")

        // Initialize llama backend
        llama_backend_init()
        logger.debug("Backend initialized")

        // Load model
        var modelParams = llama_model_default_params()

        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        logger.info("Running on simulator, n_gpu_layers = 0")
        #else
        modelParams.n_gpu_layers = configuration.gpuLayers
        logger.info("Running on device, n_gpu_layers = \(configuration.gpuLayers)")
        #endif

        logger.info("Loading model file (this may take a while for 2GB file)...")
        model = llama_load_model_from_file(modelPath, modelParams)
        guard model != nil else {
            logger.error("llama_load_model_from_file failed")
            throw OnDeviceLLMError.modelLoadFailed("llama_load_model_from_file failed")
        }
        logger.info("Model loaded successfully")

        // Create context
        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = configuration.contextSize
        ctxParams.n_threads = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)

        logger.debug("Creating context with \(nThreads) threads, context size: \(configuration.contextSize)")
        context = llama_new_context_with_model(model, ctxParams)
        guard context != nil else {
            llama_free_model(model)
            model = nil
            logger.error("llama_new_context_with_model failed")
            throw OnDeviceLLMError.modelLoadFailed("llama_new_context_with_model failed")
        }

        isLoaded = true
        logger.info("On-device LLM loaded successfully with \(nThreads) threads")
    }

    public func unloadModel() {
        if let ctx = context {
            llama_free(ctx)
            context = nil
        }
        if let mdl = model {
            llama_free_model(mdl)
            model = nil
        }
        llama_backend_free()
        isLoaded = false
    }

    // MARK: - LLMService Protocol

    public func streamCompletion(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> AsyncStream<LLMToken> {
        logger.debug("streamCompletion called with \(messages.count) messages")

        // Load model if needed
        if !isLoaded {
            logger.info("Model not loaded, loading now...")
            try await loadModel()
        }

        guard let ctx = context, let mdl = model else {
            logger.error("Context or model is nil after loading")
            throw OnDeviceLLMError.notConfigured
        }

        // Format messages into prompt
        let prompt = formatChatPrompt(messages: messages, systemPrompt: config.systemPrompt)
        logger.debug("Formatted prompt length: \(prompt.count) chars")
        logger.debug("Prompt: \(prompt.prefix(200))...")

        let startTime = Date()

        return AsyncStream { continuation in
            Task {
                do {
                    // Tokenize prompt
                    self.logger.debug("Tokenizing prompt...")
                    let tokens = self.tokenize(prompt, model: mdl)
                    self.totalInputTokens += tokens.count
                    self.logger.debug("Tokenized to \(tokens.count) tokens")

                    // Create batch for processing
                    var batch = llama_batch_init(512, 0, 1)
                    defer { llama_batch_free(batch) }

                    // Add prompt tokens to batch
                    llama_batch_clear(&batch)
                    for (i, token) in tokens.enumerated() {
                        llama_batch_add(&batch, token, Int32(i), [0], false)
                    }
                    batch.logits[Int(batch.n_tokens) - 1] = 1  // Enable logits for last token

                    // Process prompt
                    self.logger.debug("Processing prompt through decoder...")
                    if llama_decode(ctx, batch) != 0 {
                        self.logger.error("Initial decode failed")
                        throw OnDeviceLLMError.inferenceError("Initial decode failed")
                    }
                    self.logger.debug("Prompt processed, starting generation...")

                    // Generate tokens
                    var nCur = batch.n_tokens
                    let maxTokens = Int32(config.maxTokens)
                    var generatedCount = 0
                    var firstTokenEmitted = false
                    var temporaryInvalidCChars: [CChar] = []

                    // Create a greedy sampler once for the generation loop (new llama.cpp b7263+ API)
                    let sampler = llama_sampler_init_greedy()
                    defer { llama_sampler_free(sampler) }

                    // Get vocab from model for EOG check (new llama.cpp b7263+ API)
                    let vocab = llama_model_get_vocab(mdl)

                    while nCur < Int32(tokens.count) + maxTokens {
                        // Sample using greedy - the sampler gets logits from context at the last token position
                        let newToken = llama_sampler_sample(sampler, ctx, batch.n_tokens - 1)

                        // Check for end of generation (use vocab, not model - new API)
                        if llama_vocab_is_eog(vocab, newToken) {
                            // Emit any remaining text
                            if !temporaryInvalidCChars.isEmpty {
                                let text = String(cString: temporaryInvalidCChars + [0])
                                continuation.yield(LLMToken(
                                    content: text,
                                    isDone: false,
                                    stopReason: nil,
                                    tokenCount: generatedCount
                                ))
                            }
                            break
                        }

                        // Decode token to text
                        let newTokenCChars = self.tokenToPiece(token: newToken, model: mdl)
                        temporaryInvalidCChars.append(contentsOf: newTokenCChars)

                        let tokenText: String
                        if let string = String(validatingUTF8: temporaryInvalidCChars + [0]) {
                            temporaryInvalidCChars.removeAll()
                            tokenText = string
                        } else {
                            tokenText = ""
                        }

                        // Record TTFT
                        if !firstTokenEmitted && !tokenText.isEmpty {
                            let ttft = Date().timeIntervalSince(startTime)
                            self.ttftMeasurements.append(ttft)
                            firstTokenEmitted = true
                        }

                        if !tokenText.isEmpty {
                            generatedCount += 1

                            // Emit token
                            continuation.yield(LLMToken(
                                content: tokenText,
                                isDone: false,
                                stopReason: nil,
                                tokenCount: generatedCount
                            ))
                        }

                        // Prepare next batch
                        llama_batch_clear(&batch)
                        llama_batch_add(&batch, newToken, nCur, [0], true)

                        if llama_decode(ctx, batch) != 0 {
                            self.logger.error("llama_decode failed during generation")
                            break
                        }

                        nCur += 1
                    }

                    self.totalOutputTokens += generatedCount

                    // Final token
                    continuation.yield(LLMToken(
                        content: "",
                        isDone: true,
                        stopReason: .endTurn,
                        tokenCount: generatedCount
                    ))
                    continuation.finish()

                } catch {
                    self.logger.error("Stream completion failed: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatChatPrompt(messages: [LLMMessage], systemPrompt: String?) -> String {
        // Detect model type from configuration path
        let modelName = configuration.modelPath.lastPathComponent.lowercased()

        if modelName.contains("ministral") || modelName.contains("mistral") {
            return formatMistralPrompt(messages: messages, systemPrompt: systemPrompt)
        } else {
            return formatTinyLlamaPrompt(messages: messages, systemPrompt: systemPrompt)
        }
    }

    /// Format prompt for Mistral/Ministral models
    /// Uses [INST] [/INST] format with system prompt at the beginning
    private func formatMistralPrompt(messages: [LLMMessage], systemPrompt: String?) -> String {
        var prompt = ""

        // Get system prompt
        let system = systemPrompt ?? messages.first(where: { $0.role == .system })?.content

        // Build conversation
        var isFirstUserMessage = true
        for message in messages where message.role != .system {
            if message.role == .user {
                if isFirstUserMessage {
                    // Include system prompt with first user message
                    if let system = system {
                        prompt += "[INST] \(system)\n\n\(message.content) [/INST]"
                    } else {
                        prompt += "[INST] \(message.content) [/INST]"
                    }
                    isFirstUserMessage = false
                } else {
                    prompt += "[INST] \(message.content) [/INST]"
                }
            } else {
                // Assistant response
                prompt += "\(message.content)</s>"
            }
        }

        return prompt
    }

    /// Format prompt for TinyLlama ChatML style
    /// Uses <|system|>, <|user|>, <|assistant|> tags
    private func formatTinyLlamaPrompt(messages: [LLMMessage], systemPrompt: String?) -> String {
        var prompt = ""

        // Add system prompt
        let system = systemPrompt ?? messages.first(where: { $0.role == .system })?.content
        if let system = system {
            prompt += "<|system|>\n\(system)</s>\n"
        }

        // Add conversation messages
        for message in messages where message.role != .system {
            if message.role == .user {
                prompt += "<|user|>\n\(message.content)</s>\n"
            } else {
                prompt += "<|assistant|>\n\(message.content)</s>\n"
            }
        }

        // Add assistant prompt for generation
        prompt += "<|assistant|>\n"

        return prompt
    }

    private func tokenize(_ text: String, model: OpaquePointer) -> [llama_token] {
        let utf8Count = text.utf8.count
        let nTokens = utf8Count + 2
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: nTokens)
        defer { tokens.deallocate() }

        // Get vocab from model - new API in llama.cpp b7263+
        let vocab = llama_model_get_vocab(model)

        // New API: llama_tokenize(vocab, text, text_len, tokens, n_tokens_max, add_special, parse_special)
        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(nTokens), true, false)

        var result: [llama_token] = []
        for i in 0..<Int(max(0, tokenCount)) {
            result.append(tokens[i])
        }
        return result
    }

    private func tokenToPiece(token: llama_token, model: OpaquePointer) -> [CChar] {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: Int8(0), count: 8)
        defer { result.deallocate() }

        // Get vocab from model - new API in llama.cpp b7263+
        let vocab = llama_model_get_vocab(model)

        // New API: llama_token_to_piece(vocab, token, buf, length, lstrip, special)
        // lstrip = 0 means don't strip leading whitespace
        // special = false means don't handle special tokens specially
        let nTokens = llama_token_to_piece(vocab, token, result, 8, 0, false)

        if nTokens < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
            newResult.initialize(repeating: Int8(0), count: Int(-nTokens))
            defer { newResult.deallocate() }
            let nNewTokens = llama_token_to_piece(vocab, token, newResult, Int32(-nTokens), 0, false)
            let bufferPointer = UnsafeBufferPointer(start: newResult, count: Int(nNewTokens))
            return Array(bufferPointer)
        } else {
            let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nTokens))
            return Array(bufferPointer)
        }
    }
}

// MARK: - Device Capability Check

extension OnDeviceLLMService {
    /// Check if the current device supports on-device LLM
    public static var isDeviceSupported: Bool {
        // Check available memory (need ~4GB free for 3B model)
        let memoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        guard memoryGB >= 6 else {
            return false
        }

        #if targetEnvironment(simulator)
        // Simulator may work but performance will be poor
        return FileManager.default.fileExists(
            atPath: Configuration.default.modelPath.path
        )
        #else
        return true
        #endif
    }

    /// Check if on-device models are available
    public static var areModelsAvailable: Bool {
        // Check for Ministral 3B in bundle (primary - requires llama.cpp ≥b7263)
        if let bundleURL = Bundle.main.url(forResource: "ministral-3b-instruct-q4_k_m", withExtension: "gguf") {
            let exists = FileManager.default.fileExists(atPath: bundleURL.path)
            staticLogger.debug("Ministral 3B bundle URL: \(bundleURL.path), exists: \(exists)")
            if exists { return true }
        }

        // Check filesystem path for Ministral 3B (development)
        let ministralPath = "models/ministral-3b-instruct-q4_k_m.gguf"
        if FileManager.default.fileExists(atPath: ministralPath) {
            staticLogger.debug("Ministral 3B filesystem path exists: \(ministralPath)")
            return true
        }

        // Fallback: check for TinyLlama 1.1B in bundle
        if let bundleURL = Bundle.main.url(forResource: "tinyllama-1.1b-chat-v1.0.Q4_K_M", withExtension: "gguf") {
            let exists = FileManager.default.fileExists(atPath: bundleURL.path)
            staticLogger.debug("TinyLlama bundle URL: \(bundleURL.path), exists: \(exists)")
            if exists { return true }
        }

        // Fallback: check filesystem path for TinyLlama (development)
        let tinyLlamaPath = "models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
        if FileManager.default.fileExists(atPath: tinyLlamaPath) {
            staticLogger.debug("TinyLlama filesystem path exists: \(tinyLlamaPath)")
            return true
        }

        staticLogger.debug("No models available")
        return false
    }
}
