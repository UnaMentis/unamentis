// UnaMentis - Audio Engine
// iOS audio capture and playback with voice processing and VAD integration
//
// Part of Core Components (TDD Section 3.1)

@preconcurrency import AVFoundation
import Combine
import Logging

// MARK: - Sendable Wrapper

/// Wrapper to make non-Sendable types usable in @Sendable closures
/// Used for PassthroughSubject in audio tap callback
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}

// MARK: - Audio Engine

/// Manages all iOS audio I/O with voice optimization and on-device VAD
///
/// Key Responsibilities:
/// - Configure AVAudioSession for voice chat
/// - Enable hardware AEC/AGC/NS via voice processing
/// - Capture audio and run on-device VAD
/// - Stream audio to transport layer
/// - Play TTS audio with interruption support
/// - Monitor thermal state for adaptive quality
public actor AudioEngine: ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(label: "com.unamentis.audio")
    private let engine = AVAudioEngine()
    #if os(iOS)
    private let session = AVAudioSession.sharedInstance()
    #endif
    private let playerNode = AVAudioPlayerNode()

    private var vadService: any VADService
    private let telemetry: TelemetryEngine

    /// Whether TTS playback is currently active
    public private(set) var isPlaying = false

    /// Queue of scheduled audio buffers for sequential playback
    private var pendingBuffers: [AVAudioPCMBuffer] = []

    /// Current playback format (set when first chunk arrives)
    private var playbackFormat: AVAudioFormat?

    /// Continuation for waiting on playback completion
    private var playbackCompletionContinuation: CheckedContinuation<Void, Never>?
    
    /// Current configuration
    public private(set) var config: AudioEngineConfig
    
    /// Whether the engine is currently running
    public private(set) var isRunning = false
    
    /// Current audio format
    public var format: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: config.bitDepth.avFormat,
            sampleRate: config.sampleRate,
            channels: config.channels,
            interleaved: false
        )
    }
    
    /// Current audio level (dB)
    @MainActor @Published public private(set) var currentAudioLevel: Float = -160.0
    
    /// Current thermal state
    @MainActor @Published public private(set) var currentThermalState: ProcessInfo.ThermalState = .nominal
    
    // Audio stream for subscribers - nonisolated since PassthroughSubject is thread-safe
    nonisolated(unsafe) private let audioStreamSubject = PassthroughSubject<(AVAudioPCMBuffer, VADResult), Never>()

    /// Stream of audio buffers with VAD results
    nonisolated public var audioStream: AnyPublisher<(AVAudioPCMBuffer, VADResult), Never> {
        audioStreamSubject.eraseToAnyPublisher()
    }

    /// Send audio buffer to subscribers (nonisolated to avoid actor boundary crossing)
    nonisolated private func sendToAudioStream(_ buffer: AVAudioPCMBuffer, _ vadResult: VADResult) {
        audioStreamSubject.send((buffer, vadResult))
    }

    /// Get audio stream subject wrapped in sendable box (nonisolated for use in closures from async context)
    nonisolated private var audioStreamSubjectBox: UncheckedSendableBox<PassthroughSubject<(AVAudioPCMBuffer, VADResult), Never>> {
        UncheckedSendableBox(value: audioStreamSubject)
    }
    
    // Thermal monitoring
    private var thermalStateObserver: NSObjectProtocol?
    
    // Level monitoring handled on MainActor
    @MainActor private static var levelMonitorTimer: Timer?
    
    // MARK: - Initialization
    
    /// Initialize AudioEngine with configuration and dependencies
    public init(
        config: AudioEngineConfig = .default,
        vadService: any VADService,
        telemetry: TelemetryEngine
    ) {
        self.config = config
        self.vadService = vadService
        self.telemetry = telemetry
        
        Task {
            await setupThermalMonitoring()
        }
    }
    
    // MARK: - Configuration
    
    /// Configure the audio engine with new settings
    public func configure(config: AudioEngineConfig) async throws {
        self.config = config
        
        logger.info("Configuring AudioEngine", metadata: [
            "sampleRate": .stringConvertible(config.sampleRate),
            "channels": .stringConvertible(config.channels),
            "vadProvider": .string(config.vadProvider.identifier)
        ])
        
        // Configure audio session (iOS only)
        #if os(iOS)
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setPreferredSampleRate(config.sampleRate)
            try session.setPreferredIOBufferDuration(Double(config.bufferSize) / config.sampleRate)
            try session.setActive(true)
        } catch {
            throw AudioEngineError.audioSessionConfigurationFailed(error.localizedDescription)
        }
        #endif
        
        // Configure voice processing
        if config.enableVoiceProcessing {
            do {
                try engine.inputNode.setVoiceProcessingEnabled(true)
            } catch {
                logger.warning("Voice processing not available: \(error.localizedDescription)")
            }
        }

        // Configure VAD
        await vadService.configure(
            threshold: config.vadThreshold,
            contextWindow: config.vadContextWindow
        )

        // Attach player node for TTS playback (if not already attached)
        if !engine.attachedNodes.contains(playerNode) {
            engine.attach(playerNode)
        }

        // Connect player node to output (will reconnect with correct format when playing)
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        // Prepare engine
        engine.prepare()
        
        // Record telemetry
        await telemetry.recordEvent(.audioEngineConfigured(config))
    }
    
    // MARK: - Lifecycle
    
    /// Start the audio engine
    public func start() async throws {
        guard !isRunning else {
            logger.debug("AudioEngine already running")
            return
        }
        
        logger.info("Starting AudioEngine")
        
        // Install tap for audio capture
        let inputNode = engine.inputNode
        guard let format = format else {
            throw AudioEngineError.invalidConfiguration("Could not create audio format")
        }
        
        // Remove any existing tap
        inputNode.removeTap(onBus: 0)
        
        // Install new tap with @Sendable closure to avoid Swift 6 actor isolation crash
        // The closure runs on a real-time audio thread and must not reference the actor
        // Wrap non-Sendable types in UncheckedSendableBox for use in @Sendable closure
        let audioSubjectBox = audioStreamSubjectBox
        let vadServiceBox = UncheckedSendableBox(value: self.vadService)
        let telemetryBox = UncheckedSendableBox(value: self.telemetry)

        inputNode.installTap(
            onBus: 0,
            bufferSize: config.bufferSize,
            format: format
        ) { @Sendable buffer, _ in
            // Process audio completely off the actor to avoid Swift 6 isolation crash
            // Use Task.detached to ensure no actor context is inherited
            Task.detached {
                // Run VAD on the buffer
                let vadResult = await vadServiceBox.value.processBuffer(buffer)

                // Emit to subscribers via thread-safe subject
                audioSubjectBox.value.send((buffer, vadResult))

                // Record VAD events
                if vadResult.isSpeech {
                    await telemetryBox.value.recordEvent(.vadSpeechDetected(confidence: vadResult.confidence))
                }
            }
        }
        
        // Prepare VAD
        try await vadService.prepare()
        
        // Start engine
        do {
            try engine.start()
            isRunning = true
            await telemetry.recordEvent(.audioEngineStarted)
            logger.info("AudioEngine started successfully")
        } catch {
            throw AudioEngineError.engineStartFailed(error.localizedDescription)
        }
        
        // Start level monitoring if enabled
        if config.enableAudioLevelMonitoring {
            let interval = config.levelUpdateInterval
            await startLevelMonitoring(interval: interval)
        }
    }
    
    /// Stop the audio engine
    public func stop() async {
        guard isRunning else {
            return
        }
        
        logger.info("Stopping AudioEngine")
        
        // Stop level monitoring
        await stopLevelMonitoring()
        
        // Remove tap and stop
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        // Shutdown VAD
        await vadService.shutdown()
        
        isRunning = false
        await telemetry.recordEvent(.audioEngineStopped)
    }
    
    // MARK: - Audio Processing
    
    /// Process an incoming audio buffer (for testing and direct injection)
    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        let startTime = Date()

        // Check thermal state if adaptive quality enabled
        if config.enableAdaptiveQuality {
            await checkAndAdaptToThermalState()
        }

        // Run VAD
        let vadResult = await vadService.processBuffer(buffer)

        // Emit to subscribers via nonisolated helper
        sendToAudioStream(buffer, vadResult)
        
        // Update audio level if monitoring enabled
        if config.enableAudioLevelMonitoring {
            await updateAudioLevel(buffer: buffer)
        }
        
        // Record VAD events
        if vadResult.isSpeech {
            await telemetry.recordEvent(.vadSpeechDetected(confidence: vadResult.confidence))
        }
        
        // Record processing latency
        let processingTime = Date().timeIntervalSince(startTime)
        await telemetry.recordLatency(.audioProcessing, processingTime)
    }
    
    /// Whether playback is currently paused (vs stopped)
    public private(set) var isPaused = false

    /// Pause audio playback (tentative barge-in - can resume)
    /// Returns true if playback was paused, false if nothing was playing
    public func pausePlayback() async -> Bool {
        guard isPlaying && !isPaused else {
            logger.debug("Pause requested but not playing or already paused")
            return false
        }

        logger.debug("Pausing audio playback")
        playerNode.pause()
        isPaused = true
        await telemetry.recordEvent(.ttsPlaybackPaused)
        return true
    }

    /// Resume paused audio playback
    /// Returns true if playback was resumed, false if not paused
    public func resumePlayback() async -> Bool {
        guard isPaused else {
            logger.debug("Resume requested but not paused")
            return false
        }

        logger.debug("Resuming audio playback")
        playerNode.play()
        isPaused = false
        await telemetry.recordEvent(.ttsPlaybackResumed)
        return true
    }

    /// Stop audio playback completely (full interruption - cannot resume)
    public func stopPlayback() async {
        logger.debug("Stopping audio playback")

        // Stop the player node
        playerNode.stop()

        // Clear pending buffers
        pendingBuffers.removeAll()

        isPlaying = false
        isPaused = false
        playbackFormat = nil

        // Resume any waiting continuation so callers don't hang
        if let continuation = playbackCompletionContinuation {
            playbackCompletionContinuation = nil
            continuation.resume()
        }

        await telemetry.recordEvent(.ttsPlaybackInterrupted)
    }

    /// Play audio buffer (for TTS output) and wait for playback to complete
    ///
    /// Handles streaming TTS chunks by queueing them for sequential playback.
    /// Automatically handles format conversion when needed.
    /// For chunks marked as isLast, this method blocks until playback finishes.
    public func playAudio(_ chunk: TTSAudioChunk) async throws {
        logger.debug("Playing TTS chunk", metadata: [
            "sequence": .stringConvertible(chunk.sequenceNumber),
            "isFirst": .stringConvertible(chunk.isFirst),
            "isLast": .stringConvertible(chunk.isLast),
            "dataSize": .stringConvertible(chunk.audioData.count)
        ])

        // Ensure engine is running
        guard isRunning else {
            throw AudioEngineError.notRunning
        }

        // Convert chunk to PCM buffer
        let buffer: AVAudioPCMBuffer
        do {
            buffer = try chunk.toAVAudioPCMBuffer()
        } catch {
            logger.error("Failed to convert TTS chunk to buffer: \(error)")
            throw AudioEngineError.bufferConversionFailed
        }

        guard let bufferFormat = buffer.format as AVAudioFormat? else {
            throw AudioEngineError.bufferConversionFailed
        }

        // Check if format has changed - only reconnect if truly different
        let needsReconnect = playbackFormat == nil || !formatsAreCompatible(playbackFormat!, bufferFormat)

        // Handle format change or first-time setup
        if needsReconnect {
            logger.debug("TTS format change/setup: reconnecting player node")

            // Stop any existing playback only if we need to reconnect
            if isPlaying {
                playerNode.stop()
                pendingBuffers.removeAll()
                // Cancel any pending completion wait
                playbackCompletionContinuation?.resume()
                playbackCompletionContinuation = nil
            }

            // Reconnect player node with correct format
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: bufferFormat)
            playbackFormat = bufferFormat
        }

        // Mark as playing if not already
        if !isPlaying {
            isPlaying = true

            // Record TTFB if available (only on first chunk of session)
            if let ttfb = chunk.timeToFirstByte {
                await telemetry.recordLatency(.ttsTimeToFirstByte, ttfb)
            }

            await telemetry.recordEvent(.ttsPlaybackStarted)
        }

        // For the last chunk, we'll wait for playback to complete
        let shouldWait = chunk.isLast

        // Schedule buffer for playback with completion callback
        // Using completionCallbackType: .dataPlayedBack ensures callback fires when audio
        // actually finishes playing, not just when buffer is consumed/scheduled
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task {
                await self?.handleBufferCompletion(isLastChunk: chunk.isLast)
            }
        }

        // Start playing if not already
        if !playerNode.isPlaying {
            playerNode.play()
        }

        // If this is the last chunk, wait for playback to complete
        // We set up the continuation here - the callback will resume it when audio finishes
        // Note: This is safe because the audio playback takes non-trivial time (hundreds of ms)
        // and the continuation is set before the callback can reasonably fire
        if shouldWait {
            logger.debug("Waiting for TTS audio to finish playing...")
            await withCheckedContinuation { continuation in
                self.playbackCompletionContinuation = continuation
            }
            logger.debug("TTS audio playback finished")
        }
    }

    /// Check if two audio formats are compatible for playback continuity
    private func formatsAreCompatible(_ format1: AVAudioFormat, _ format2: AVAudioFormat) -> Bool {
        return format1.sampleRate == format2.sampleRate &&
               format1.channelCount == format2.channelCount &&
               format1.commonFormat == format2.commonFormat
    }

    /// Handle completion of a buffer playback
    private func handleBufferCompletion(isLastChunk: Bool) async {
        if isLastChunk {
            isPlaying = false
            playbackFormat = nil

            // Resume any waiting continuation
            if let continuation = playbackCompletionContinuation {
                playbackCompletionContinuation = nil
                continuation.resume()
            }

            await telemetry.recordEvent(.ttsPlaybackCompleted)
            logger.debug("TTS playback completed")
        }
    }

    /// Play raw audio data with specified format
    ///
    /// Convenience method for playing audio from sources other than TTS
    public func playRawAudio(_ data: Data, format: AVAudioFormat) async throws {
        guard isRunning else {
            throw AudioEngineError.notRunning
        }

        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        let frameCount = UInt32(data.count) / bytesPerFrame

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioEngineError.bufferConversionFailed
        }

        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                if format.commonFormat == .pcmFormatFloat32 {
                    memcpy(buffer.floatChannelData?[0], baseAddress, data.count)
                } else if format.commonFormat == .pcmFormatInt16 {
                    memcpy(buffer.int16ChannelData?[0], baseAddress, data.count)
                }
            }
        }

        // Reconnect player node with correct format if needed
        if playbackFormat != format {
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            playbackFormat = format
        }

        isPlaying = true

        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task {
                await self?.handleBufferCompletion(isLastChunk: true)
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
    
    // MARK: - Thermal Management
    
    private func setupThermalMonitoring() async {
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleThermalStateChange(ProcessInfo.processInfo.thermalState)
            }
        }
        
        // Set initial state
        await MainActor.run {
            currentThermalState = ProcessInfo.processInfo.thermalState
        }
    }
    
    /// Handle thermal state changes
    public func handleThermalStateChange(_ state: ProcessInfo.ThermalState) async {
        await MainActor.run {
            currentThermalState = state
        }
        
        await telemetry.recordEvent(.thermalStateChanged(state))
        
        // Apply adaptive quality if threshold exceeded
        if config.enableAdaptiveQuality && config.thermalThrottleThreshold.isExceededBy(state) {
            await adaptQualityForThermalState(state)
        }
    }
    
    private func checkAndAdaptToThermalState() async {
        let state = ProcessInfo.processInfo.thermalState
        if config.thermalThrottleThreshold.isExceededBy(state) {
            await adaptQualityForThermalState(state)
        }
    }
    
    private func adaptQualityForThermalState(_ state: ProcessInfo.ThermalState) async {
        // Reduce quality to prevent throttling
        // Could reduce sample rate, increase buffer size, etc.
        let reason = "Thermal state: \(state)"
        await telemetry.recordEvent(.adaptiveQualityAdjusted(reason: reason))
        logger.warning("Adapting quality due to thermal state: \(state)")
    }
    
    // MARK: - Level Monitoring
    
    private func startLevelMonitoring(interval: TimeInterval) async {
        await MainActor.run {
            AudioEngine.levelMonitorTimer?.invalidate()
            AudioEngine.levelMonitorTimer = Timer.scheduledTimer(
                withTimeInterval: interval,
                repeats: true
            ) { _ in
                // Level is updated in processAudioBuffer
            }
        }
    }
    
    private func stopLevelMonitoring() async {
        await MainActor.run {
            AudioEngine.levelMonitorTimer?.invalidate()
            AudioEngine.levelMonitorTimer = nil
        }
    }
    
    private func updateAudioLevel(buffer: AVAudioPCMBuffer) async {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(max(rms, 1e-10))
        
        await MainActor.run {
            currentAudioLevel = db
        }
    }
    
    // MARK: - Cleanup
    
    /// Call this before deallocating to properly clean up observers
    public func cleanup() {
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalStateObserver = nil
        }
    }
}
