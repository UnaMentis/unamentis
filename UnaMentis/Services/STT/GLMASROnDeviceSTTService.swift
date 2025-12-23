// UnaMentis - GLM-ASR On-Device STT Service
// Full on-device Speech-to-Text using CoreML + llama.cpp
//
// Pipeline:
// 1. Audio → Mel Spectrogram (128 x 3000)
// 2. CoreML Whisper Encoder → Audio embeddings (1 x 1500 x 1280)
// 3. CoreML Audio Adapter → Language embeddings (1 x 375 x 2048)
// 4. llama.cpp GGUF → Text tokens
// 5. Tokenizer → Transcript
//
// Target: iPhone 17 Pro Max (A19 Pro, 12GB RAM)
//
// NOTE: llama.cpp integration requires Swift/C++ interop enabled in Xcode.
// Set SWIFT_OBJC_INTEROP_MODE = objcxx in build settings.

import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreML
import Accelerate
import Logging

// GLM-ASR decoder disabled - use Apple Speech fallback for STT
// The LLM service (OnDeviceLLMService) handles LLM inference using LocalLLMClient
private let llamaAvailable = false

/// On-device GLM-ASR STT service using CoreML + llama.cpp
///
/// This service runs entirely on-device with no network required.
/// Uses Neural Engine for Whisper encoder and GPU for LLaMA decoder.
public actor GLMASROnDeviceSTTService: STTService {

    // MARK: - Types

    public enum OnDeviceError: Error, LocalizedError {
        case modelNotFound(String)
        case modelLoadFailed(String)
        case inferenceError(String)
        case audioProcessingError(String)
        case notConfigured
        case deviceNotSupported

        public var errorDescription: String? {
            switch self {
            case .modelNotFound(let name): return "Model not found: \(name)"
            case .modelLoadFailed(let msg): return "Failed to load model: \(msg)"
            case .inferenceError(let msg): return "Inference error: \(msg)"
            case .audioProcessingError(let msg): return "Audio processing error: \(msg)"
            case .notConfigured: return "On-device STT not configured"
            case .deviceNotSupported: return "Device does not support on-device GLM-ASR"
            }
        }
    }

    /// Configuration for on-device service
    public struct Configuration: Sendable {
        /// Directory containing CoreML models
        public let modelDirectory: URL
        /// Maximum audio duration in seconds
        public let maxAudioDuration: TimeInterval
        /// Whether to use Neural Engine for CoreML
        public let useNeuralEngine: Bool
        /// Number of GPU layers for llama.cpp
        public let gpuLayers: Int32

        public init(
            modelDirectory: URL,
            maxAudioDuration: TimeInterval = 30.0,
            useNeuralEngine: Bool = true,
            gpuLayers: Int32 = 99  // Use all GPU layers
        ) {
            self.modelDirectory = modelDirectory
            self.maxAudioDuration = maxAudioDuration
            self.useNeuralEngine = useNeuralEngine
            self.gpuLayers = gpuLayers
        }

        public static var `default`: Configuration {
            // Default to app bundle or documents directory
            let modelDir = Bundle.main.resourceURL ?? FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("models/glm-asr-nano")

            return Configuration(modelDirectory: modelDir)
        }
    }

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.stt.glmasr.ondevice")
    private let configuration: Configuration

    // CoreML models
    private var whisperEncoder: MLModel?
    private var audioAdapter: MLModel?
    private var embedHead: MLModel?

    // llama.cpp context
    private var llamaModel: OpaquePointer?
    private var llamaContext: OpaquePointer?

    // Streaming state
    private var resultContinuation: AsyncStream<STTResult>.Continuation?
    private var audioBuffer: [Float] = []
    private var sessionStartTime: Date?
    private var latencyMeasurements: [TimeInterval] = []

    /// Performance metrics
    public private(set) var metrics = STTMetrics(
        medianLatency: 0.25,  // Expected on-device latency
        p99Latency: 0.5,
        wordEmissionRate: 0
    )

    /// Cost per hour (on-device = $0)
    public var costPerHour: Decimal { Decimal(0) }

    /// Whether currently streaming
    public private(set) var isStreaming: Bool = false

    /// Whether models are loaded
    public private(set) var isLoaded: Bool = false

    // MARK: - Mel Spectrogram Config

    private let sampleRate: Double = 16000
    private let nFFT: Int = 400
    private let hopLength: Int = 160
    private let nMels: Int = 128
    private let chunkLength: Int = 30  // seconds

    // MARK: - Initialization

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        logger.info("GLMASROnDeviceSTTService initialized")
    }

    // NOTE: deinit cannot access actor-isolated properties in Swift 6
    // Model cleanup happens in unloadModels() which should be called via stopStreaming()
    // before releasing the service. The llama_backend_free is called there.

    // MARK: - Model Loading

    /// Load all required models
    public func loadModels() async throws {
        guard !isLoaded else { return }

        logger.info("Loading on-device GLM-ASR models...")

        // Configure CoreML for Neural Engine or GPU
        let config = MLModelConfiguration()
        config.computeUnits = configuration.useNeuralEngine ? .all : .cpuAndGPU

        // Load Whisper Encoder
        let encoderURL = configuration.modelDirectory
            .appendingPathComponent("GLMASRWhisperEncoder.mlpackage")
        guard FileManager.default.fileExists(atPath: encoderURL.path) else {
            throw OnDeviceError.modelNotFound("GLMASRWhisperEncoder.mlpackage")
        }

        do {
            whisperEncoder = try MLModel(contentsOf: encoderURL, configuration: config)
            logger.info("Loaded Whisper encoder")
        } catch {
            throw OnDeviceError.modelLoadFailed("Whisper encoder: \(error)")
        }

        // Load Audio Adapter
        let adapterURL = configuration.modelDirectory
            .appendingPathComponent("GLMASRAudioAdapter.mlpackage")
        guard FileManager.default.fileExists(atPath: adapterURL.path) else {
            throw OnDeviceError.modelNotFound("GLMASRAudioAdapter.mlpackage")
        }

        do {
            audioAdapter = try MLModel(contentsOf: adapterURL, configuration: config)
            logger.info("Loaded audio adapter")
        } catch {
            throw OnDeviceError.modelLoadFailed("Audio adapter: \(error)")
        }

        // Load Embed Head
        let embedURL = configuration.modelDirectory
            .appendingPathComponent("GLMASREmbedHead.mlpackage")
        guard FileManager.default.fileExists(atPath: embedURL.path) else {
            throw OnDeviceError.modelNotFound("GLMASREmbedHead.mlpackage")
        }

        do {
            embedHead = try MLModel(contentsOf: embedURL, configuration: config)
            logger.info("Loaded embed head")
        } catch {
            throw OnDeviceError.modelLoadFailed("Embed head: \(error)")
        }

        // Load GGUF model with llama.cpp
        let ggufURL = configuration.modelDirectory
            .appendingPathComponent("glm-asr-nano-q4km.gguf")
        guard FileManager.default.fileExists(atPath: ggufURL.path) else {
            throw OnDeviceError.modelNotFound("glm-asr-nano-q4km.gguf")
        }

        try loadLlamaModel(path: ggufURL.path)

        isLoaded = true
        logger.info("All on-device models loaded successfully")
    }

    private func loadLlamaModel(path: String) throws {
        #if LLAMA_AVAILABLE
        llama_backend_init()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = configuration.gpuLayers

        llamaModel = llama_load_model_from_file(path, modelParams)
        guard llamaModel != nil else {
            throw OnDeviceError.modelLoadFailed("llama.cpp model")
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 2048
        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        ctxParams.n_threads = UInt32(nThreads)
        ctxParams.n_threads_batch = UInt32(nThreads)

        llamaContext = llama_new_context_with_model(llamaModel, ctxParams)
        guard llamaContext != nil else {
            throw OnDeviceError.modelLoadFailed("llama.cpp context")
        }

        logger.info("Loaded llama.cpp model with \(nThreads) threads")
        #else
        logger.error("llama.cpp not available - build requires C++ interop enabled in Xcode (LLAMA_AVAILABLE flag)")
        throw OnDeviceError.modelLoadFailed("llama.cpp not available - requires Xcode build with C++ interop enabled")
        #endif
    }

    private func unloadModels() {
        whisperEncoder = nil
        audioAdapter = nil
        embedHead = nil

        #if LLAMA_AVAILABLE
        if let ctx = llamaContext {
            llama_free(ctx)
            llamaContext = nil
        }
        if let model = llamaModel {
            llama_free_model(model)
            llamaModel = nil
        }
        llama_backend_free()
        #endif

        isLoaded = false
    }

    // MARK: - STTService Protocol

    public func startStreaming(audioFormat: sending AVAudioFormat) async throws -> AsyncStream<STTResult> {
        guard !isStreaming else {
            throw STTError.alreadyStreaming
        }

        // Load models if not already loaded
        if !isLoaded {
            try await loadModels()
        }

        guard audioFormat.sampleRate == 16000 && audioFormat.channelCount == 1 else {
            throw STTError.invalidAudioFormat
        }

        logger.info("Starting on-device GLM-ASR stream")

        isStreaming = true
        sessionStartTime = Date()
        audioBuffer = []
        latencyMeasurements = []

        return AsyncStream { continuation in
            self.resultContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.cleanup()
                }
            }
        }
    }

    public func sendAudio(_ buffer: sending AVAudioPCMBuffer) async throws {
        guard isStreaming else {
            throw STTError.notStreaming
        }

        guard let floatData = buffer.floatChannelData?[0] else {
            throw STTError.invalidAudioFormat
        }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: floatData, count: frameCount))
        audioBuffer.append(contentsOf: samples)

        // Process when we have enough audio (e.g., 3 seconds)
        let processingThreshold = Int(sampleRate * 3)
        if audioBuffer.count >= processingThreshold {
            try await processAccumulatedAudio()
        }
    }

    public func stopStreaming() async throws {
        guard isStreaming else { return }

        logger.info("Stopping on-device GLM-ASR stream")

        // Process any remaining audio
        if !audioBuffer.isEmpty {
            try await processAccumulatedAudio()
        }

        await cleanup()
        recordSessionMetrics()
    }

    public func cancelStreaming() async {
        await cleanup()
    }

    // MARK: - Audio Processing Pipeline

    private func processAccumulatedAudio() async throws {
        let startTime = Date()

        // Step 1: Compute mel spectrogram
        let melSpectrogram = try computeMelSpectrogram(audioBuffer)

        // Step 2: Run Whisper encoder (CoreML)
        let encodedAudio = try await runWhisperEncoder(melSpectrogram)

        // Step 3: Run audio adapter (CoreML)
        let adaptedAudio = try await runAudioAdapter(encodedAudio)

        // Step 4: Run LLaMA decoder (llama.cpp)
        let transcript = try await runLlamaDecoder(adaptedAudio)

        let latency = Date().timeIntervalSince(startTime)
        latencyMeasurements.append(latency)

        // Emit result
        let result = STTResult(
            transcript: transcript,
            isFinal: true,
            isEndOfUtterance: true,
            confidence: 0.9,  // On-device doesn't provide confidence
            latency: latency
        )

        resultContinuation?.yield(result)

        // Clear processed audio
        audioBuffer.removeAll()
    }

    // MARK: - Mel Spectrogram

    private func computeMelSpectrogram(_ audio: [Float]) throws -> MLMultiArray {
        // Compute STFT and convert to mel spectrogram
        // This is a simplified version - full implementation would use vDSP

        let numFrames = min(3000, (audio.count - nFFT) / hopLength + 1)

        guard let melArray = try? MLMultiArray(shape: [1, NSNumber(value: nMels), NSNumber(value: numFrames)], dataType: .float32) else {
            throw OnDeviceError.audioProcessingError("Failed to create mel array")
        }

        // Simple energy-based approximation for now
        // TODO: Implement full mel spectrogram with FFT
        for frame in 0..<numFrames {
            let start = frame * hopLength
            let end = min(start + nFFT, audio.count)

            var energy: Float = 0
            for i in start..<end {
                energy += audio[i] * audio[i]
            }
            energy = sqrt(energy / Float(end - start))

            // Distribute energy across mel bins (simplified)
            for mel in 0..<nMels {
                let index = mel + frame * nMels
                melArray[index] = NSNumber(value: log(max(energy * Float(mel + 1) / Float(nMels), 1e-10)))
            }
        }

        return melArray
    }

    // MARK: - CoreML Inference

    private func runWhisperEncoder(_ melSpectrogram: MLMultiArray) async throws -> MLMultiArray {
        guard let encoder = whisperEncoder else {
            throw OnDeviceError.notConfigured
        }

        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "input_features": MLFeatureValue(multiArray: melSpectrogram)
        ])

        let output = try await encoder.prediction(from: inputFeatures)

        guard let encodedOutput = output.featureValue(for: "output")?.multiArrayValue else {
            throw OnDeviceError.inferenceError("Whisper encoder output missing")
        }

        return encodedOutput
    }

    private func runAudioAdapter(_ encodedAudio: MLMultiArray) async throws -> MLMultiArray {
        guard let adapter = audioAdapter else {
            throw OnDeviceError.notConfigured
        }

        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "input": MLFeatureValue(multiArray: encodedAudio)
        ])

        let output = try await adapter.prediction(from: inputFeatures)

        guard let adaptedOutput = output.featureValue(for: "output")?.multiArrayValue else {
            throw OnDeviceError.inferenceError("Audio adapter output missing")
        }

        return adaptedOutput
    }

    // MARK: - LLaMA Decoder

    private func runLlamaDecoder(_ audioEmbeddings: MLMultiArray) async throws -> String {
        #if LLAMA_AVAILABLE
        guard let context = llamaContext, let model = llamaModel else {
            throw OnDeviceError.notConfigured
        }

        // For now, use a simple text completion approach
        // TODO: Integrate audio embeddings properly with the decoder

        // Create prompt with audio placeholder
        let prompt = "<|user|>\n<|begin_of_audio|><|end_of_audio|>\n<|user|>\nPlease transcribe this audio into text<|assistant|>\n"

        // Tokenize
        let tokens = tokenize(prompt, model: model)

        // Create batch
        var batch = llama_batch_init(Int32(tokens.count + 512), 0, 1)
        defer { llama_batch_free(batch) }

        // Add prompt tokens
        for (i, token) in tokens.enumerated() {
            batch.token[i] = token
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0
        }
        batch.logits[tokens.count - 1] = 1
        batch.n_tokens = Int32(tokens.count)

        // Decode prompt
        if llama_decode(context, batch) != 0 {
            throw OnDeviceError.inferenceError("llama_decode failed")
        }

        // Generate tokens using greedy sampling
        var outputTokens: [llama_token] = []
        var nCur = Int32(tokens.count)
        let maxTokens: Int32 = 256
        let nVocab = llama_n_vocab(model)

        // Get vocab from model for EOG check (new llama.cpp b7263+ API)
        let vocab = llama_model_get_vocab(model)

        while nCur < maxTokens {
            // Get logits for the last token
            guard let logits = llama_get_logits_ith(context, -1) else {
                break
            }

            // Build candidates array for sampling
            var candidates = [llama_token_data]()
            candidates.reserveCapacity(Int(nVocab))
            for tokenId in 0..<nVocab {
                candidates.append(llama_token_data(
                    id: tokenId,
                    logit: logits[Int(tokenId)],
                    p: 0
                ))
            }

            // Sample using greedy (highest probability token)
            let newToken: llama_token = candidates.withUnsafeMutableBufferPointer { buffer in
                var candidatesArray = llama_token_data_array(
                    data: buffer.baseAddress,
                    size: buffer.count,
                    sorted: false
                )
                // Apply temperature and sample
                llama_sample_temp(context, &candidatesArray, 0.1)
                return llama_sample_token_greedy(context, &candidatesArray)
            }

            // Check for end of generation (use vocab, not model - new API)
            if llama_vocab_is_eog(vocab, newToken) {
                break
            }

            outputTokens.append(newToken)

            // Prepare next batch
            llama_batch_clear(&batch)
            batch.token[0] = newToken
            batch.pos[0] = nCur
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            batch.n_tokens = 1

            if llama_decode(context, batch) != 0 {
                break
            }

            nCur += 1
        }

        // Detokenize
        return detokenize(outputTokens, model: model)
        #else
        logger.error("Cannot run LLaMA decoder - llama.cpp not available")
        throw OnDeviceError.inferenceError("llama.cpp not available - requires Xcode build with C++ interop")
        #endif
    }

    #if LLAMA_AVAILABLE
    private func tokenize(_ text: String, model: OpaquePointer) -> [llama_token] {
        let utf8Count = text.utf8.count
        let maxTokens = utf8Count + 2
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: maxTokens)
        defer { tokens.deallocate() }

        let tokenCount = llama_tokenize(model, text, Int32(utf8Count), tokens, Int32(maxTokens), true, false)

        var result: [llama_token] = []
        for i in 0..<Int(max(0, tokenCount)) {
            result.append(tokens[i])
        }
        return result
    }

    private func detokenize(_ tokens: [llama_token], model: OpaquePointer) -> String {
        var result = ""
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
        defer { buffer.deallocate() }

        for token in tokens {
            let length = llama_token_to_piece(model, token, buffer, 256, false)
            if length > 0 {
                buffer[Int(length)] = 0
                if let str = String(cString: buffer, encoding: .utf8) {
                    result += str
                }
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    // MARK: - Helpers

    private func cleanup() async {
        isStreaming = false
        resultContinuation?.finish()
        resultContinuation = nil
        audioBuffer = []
    }

    private func recordSessionMetrics() {
        let sortedLatencies = latencyMeasurements.sorted()

        let median: TimeInterval
        let p99: TimeInterval

        if sortedLatencies.isEmpty {
            median = 0.25
            p99 = 0.5
        } else {
            median = sortedLatencies[sortedLatencies.count / 2]
            let p99Index = min(Int(Double(sortedLatencies.count) * 0.99), sortedLatencies.count - 1)
            p99 = sortedLatencies[p99Index]
        }

        metrics = STTMetrics(
            medianLatency: median,
            p99Latency: p99,
            wordEmissionRate: 0
        )
    }
}

// MARK: - llama_batch Extension

#if LLAMA_AVAILABLE
private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}
#endif

// MARK: - Device Capability Check

extension GLMASROnDeviceSTTService {
    /// Check if the current device supports on-device GLM-ASR
    ///
    /// Returns true for devices with:
    /// - A17 Pro or newer (iPhone 15 Pro+)
    /// - At least 8GB RAM
    /// - Models available in app bundle
    public static var isDeviceSupported: Bool {
        let logger = Logger(label: "com.unamentis.glmasr.support")

        // Check available memory
        let memoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        logger.debug("Device memory: \(memoryGB)GB")
        guard memoryGB >= 8 else {
            logger.info("Device not supported: insufficient memory (\(memoryGB)GB < 8GB)")
            return false
        }

        #if targetEnvironment(simulator)
        // Simulator: GLM-ASR CoreML models are too large/complex to load on simulator
        // Always return false to use Apple Speech fallback instead
        // Real device testing is required for GLM-ASR functionality
        logger.info("GLM-ASR not supported on simulator - use Apple Speech fallback")
        return false
        #else
        // On device: check if models are in the bundle
        guard let bundleURL = Bundle.main.resourceURL else {
            return false
        }
        let encoderPath = bundleURL.appendingPathComponent("GLMASRWhisperEncoder.mlpackage").path
        return FileManager.default.fileExists(atPath: encoderPath)
        #endif
    }
}
