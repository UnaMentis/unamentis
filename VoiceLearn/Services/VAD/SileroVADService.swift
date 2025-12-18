// VoiceLearn - Silero VAD Service
// On-device Voice Activity Detection using Silero model on Neural Engine
//
// Part of Provider Implementations (TDD Section 6)

@preconcurrency import AVFoundation
import CoreML
import Logging

/// Silero VAD implementation using CoreML on Neural Engine
///
/// The Silero VAD model provides:
/// - Low latency voice activity detection (~20-30ms per frame)
/// - High accuracy speech detection
/// - Optimized for Neural Engine execution
public actor SileroVADService: VADService {
    
    // MARK: - Properties
    
    private let logger = Logger(label: "com.voicelearn.vad.silero")
    
    /// Current configuration
    public private(set) var configuration: VADConfiguration
    
    /// Whether the service is active
    public private(set) var isActive: Bool = false
    
    /// CoreML model for VAD
    private var model: MLModel?
    
    /// Hidden state for LSTM (Silero uses stateful model)
    private var hiddenState: MLMultiArray?
    private var cellState: MLMultiArray?
    
    /// Buffer for smoothing VAD decisions
    private var smoothingBuffer: [Float] = []
    
    /// Sample rate expected by Silero model
    private let expectedSampleRate: Double = 16000
    
    /// Frame size in samples (Silero expects 512 samples at 16kHz = 32ms)
    private let frameSize: Int = 512
    
    // MARK: - Initialization
    
    public init(configuration: VADConfiguration = .default) {
        self.configuration = configuration
        logger.info("SileroVADService initialized")
    }
    
    // MARK: - VADService Protocol
    
    public func configure(threshold: Float, contextWindow: Int) async {
        configuration = VADConfiguration(
            threshold: threshold,
            contextWindow: contextWindow,
            smoothingWindow: configuration.smoothingWindow,
            minSpeechDuration: configuration.minSpeechDuration,
            minSilenceDuration: configuration.minSilenceDuration
        )
        logger.debug("Configured with threshold: \(threshold), contextWindow: \(contextWindow)")
    }
    
    public func configure(_ configuration: VADConfiguration) async {
        self.configuration = configuration
        logger.debug("Configured with full configuration")
    }
    
    public func processBuffer(_ buffer: AVAudioPCMBuffer) async -> VADResult {
        guard isActive else {
            return VADResult(isSpeech: false, confidence: 0, timestamp: Date().timeIntervalSince1970)
        }
        
        let startTime = Date()
        
        // Convert buffer to expected format if needed
        guard let floatData = buffer.floatChannelData?[0] else {
            logger.warning("No float channel data available")
            return VADResult(isSpeech: false, confidence: 0, timestamp: startTime.timeIntervalSince1970)
        }
        
        let frameLength = Int(buffer.frameLength)
        
        // If model is loaded, run inference
        if let model = model {
            do {
                let confidence = try runInference(floatData: floatData, frameLength: frameLength)
                
                // Apply smoothing
                let smoothedConfidence = applySmoothing(confidence)
                
                // Determine if speech based on threshold
                let isSpeech = smoothedConfidence >= configuration.threshold
                
                logger.trace("VAD result: \(isSpeech ? "speech" : "silence"), confidence: \(smoothedConfidence)")
                
                return VADResult(
                    isSpeech: isSpeech,
                    confidence: smoothedConfidence,
                    timestamp: startTime.timeIntervalSince1970,
                    segmentDuration: Double(frameLength) / expectedSampleRate
                )
            } catch {
                logger.error("VAD inference failed: \(error.localizedDescription)")
            }
        }
        
        // Fallback: dB-based detection when model unavailable
        // Use dB scale for more reliable speech/silence discrimination
        let rms = calculateRMS(floatData: floatData, frameLength: frameLength)
        let db = 20 * log10(max(rms, 1e-10))

        // dB thresholds: speech typically > -35dB, silence typically < -50dB
        // Map dB to 0-1 confidence: -60dB -> 0.0, -20dB -> 1.0
        let dbMin: Float = -60.0
        let dbMax: Float = -20.0
        let normalizedDB = max(0, min(1, (db - dbMin) / (dbMax - dbMin)))

        // Apply smoothing to the dB-based value
        let smoothedConfidence = applySmoothing(normalizedDB)

        // Use threshold comparison (default 0.5 means ~-40dB)
        let isSpeech = smoothedConfidence >= configuration.threshold

        logger.trace("VAD fallback: db=\(db), normalized=\(normalizedDB), smoothed=\(smoothedConfidence), isSpeech=\(isSpeech)")

        return VADResult(
            isSpeech: isSpeech,
            confidence: smoothedConfidence,
            timestamp: startTime.timeIntervalSince1970,
            segmentDuration: Double(frameLength) / buffer.format.sampleRate
        )
    }
    
    public func reset() async {
        smoothingBuffer.removeAll()
        hiddenState = nil
        cellState = nil
        logger.debug("VAD state reset")
    }
    
    public func prepare() async throws {
        logger.info("Preparing Silero VAD...")
        
        // Try to load the CoreML model
        do {
            try loadModel()
            initializeHiddenState()
            isActive = true
            logger.info("Silero VAD prepared successfully with CoreML model")
        } catch {
            // Model not available - use fallback RMS detection
            logger.warning("Silero model not available, using RMS fallback: \(error.localizedDescription)")
            isActive = true
        }
    }
    
    public func shutdown() async {
        isActive = false
        model = nil
        hiddenState = nil
        cellState = nil
        smoothingBuffer.removeAll()
        logger.info("Silero VAD shutdown")
    }
    
    // MARK: - Private Methods
    
    private func loadModel() throws {
        // Look for Silero VAD model in bundle
        // The model file should be named "silero_vad.mlmodelc" or "silero_vad.mlpackage"
        guard let modelURL = Bundle.main.url(forResource: "silero_vad", withExtension: "mlmodelc") else {
            throw VADError.modelLoadFailed("silero_vad.mlmodelc not found in bundle")
        }
        
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine // Prefer Neural Engine
        
        model = try MLModel(contentsOf: modelURL, configuration: config)
        logger.info("Loaded Silero VAD model from: \(modelURL.path)")
    }
    
    private func initializeHiddenState() {
        // Silero VAD uses LSTM with hidden state size of 64
        do {
            hiddenState = try MLMultiArray(shape: [2, 1, 64], dataType: .float32)
            cellState = try MLMultiArray(shape: [2, 1, 64], dataType: .float32)
            
            // Initialize to zeros
            for i in 0..<hiddenState!.count {
                hiddenState![i] = 0
            }
            for i in 0..<cellState!.count {
                cellState![i] = 0
            }
        } catch {
            logger.error("Failed to initialize hidden state: \(error)")
        }
    }
    
    private func runInference(floatData: UnsafeMutablePointer<Float>, frameLength: Int) throws -> Float {
        guard let model = model else {
            throw VADError.notPrepared
        }
        
        // Create input array
        let inputArray = try MLMultiArray(shape: [1, NSNumber(value: frameLength)], dataType: .float32)
        for i in 0..<frameLength {
            inputArray[i] = NSNumber(value: floatData[i])
        }
        
        // Create feature provider with input
        let inputName = "input"
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: inputArray)
        ])
        
        // Run prediction
        let output = try model.prediction(from: provider)
        
        // Extract probability from output
        guard let outputArray = output.featureValue(for: "output")?.multiArrayValue else {
            throw VADError.processingFailed("Could not extract output")
        }
        
        return outputArray[0].floatValue
    }
    
    private func applySmoothing(_ confidence: Float) -> Float {
        smoothingBuffer.append(confidence)
        
        // Keep only last N values for smoothing
        while smoothingBuffer.count > configuration.smoothingWindow {
            smoothingBuffer.removeFirst()
        }
        
        // Return average
        let sum = smoothingBuffer.reduce(0, +)
        return sum / Float(smoothingBuffer.count)
    }
    
    private func calculateRMS(floatData: UnsafeMutablePointer<Float>, frameLength: Int) -> Float {
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += floatData[i] * floatData[i]
        }
        return sqrt(sum / Float(frameLength))
    }
}
