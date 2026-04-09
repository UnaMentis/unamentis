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

/// A Sendable holder for PassthroughSubject that can be safely shared across actor boundaries
/// This class is created once and passed around, avoiding repeated actor boundary crossings
private final class AudioStreamHolder: @unchecked Sendable {
    let subject = PassthroughSubject<(AVAudioPCMBuffer, VADResult), Never>()

    func send(_ buffer: AVAudioPCMBuffer, _ vadResult: VADResult) {
        subject.send((buffer, vadResult))
    }

    var publisher: AnyPublisher<(AVAudioPCMBuffer, VADResult), Never> {
        subject.eraseToAnyPublisher()
    }
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
    private var engine = AVAudioEngine()
    #if os(iOS)
    private let session = AVAudioSession.sharedInstance()
    #endif
    private var playerNode = AVAudioPlayerNode()

    private var vadService: any VADService
    private let telemetry: TelemetryEngine

    /// Whether TTS playback is currently active
    public private(set) var isPlaying = false

    /// Latest STT transcript received from the speech-to-text pipeline.
    /// Updated by the session layer when STT results arrive.
    public var lastTranscript: String = ""

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
    
    // Audio stream holder - Sendable so it can be safely used across actor boundaries
    private let audioStreamHolder = AudioStreamHolder()

    /// Stream of audio buffers with VAD results
    nonisolated public var audioStream: AnyPublisher<(AVAudioPCMBuffer, VADResult), Never> {
        audioStreamHolder.publisher
    }
    
    // Audio buffer processing stream (replaces per-buffer Task.detached)
    private var bufferStreamContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var bufferProcessingTask: Task<Void, Never>?

    // Thermal monitoring
    private var thermalStateObserver: NSObjectProtocol?

    // Audio session notification observers
    #if os(iOS)
    private var sessionNotificationObservers: [NSObjectProtocol] = []
    private var wasRunningBeforeInterruption = false
    private var wasPlayingBeforeInterruption = false
    #endif

    // Level monitoring is driven by the audio tap callback (no timer needed)
    
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
            await self.setupThermalMonitoring()
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
            setupSessionNotifications()
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
        
        // Remove any existing tap and cancel previous processing task
        inputNode.removeTap(onBus: 0)
        bufferProcessingTask?.cancel()
        bufferStreamContinuation?.finish()

        // Create AsyncStream for buffer processing (replaces per-buffer Task.detached)
        // This reduces ~253K task allocations per 90-min session to a single long-lived task
        let streamHolder = audioStreamHolder
        let vadServiceBox = UncheckedSendableBox(value: self.vadService)
        let telemetryBox = UncheckedSendableBox(value: self.telemetry)

        let (bufferStream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        self.bufferStreamContinuation = continuation

        // Single long-lived task consuming from the stream
        let levelMonitoringEnabled = config.enableAudioLevelMonitoring
        let engineRef = self
        bufferProcessingTask = Task.detached {
            for await buffer in bufferStream {
                let vadResult = await vadServiceBox.value.processBuffer(buffer)
                // Check cancellation after processBuffer (which may suspend) to avoid
                // publishing stale VAD results after teardown
                guard !Task.isCancelled else { break }
                streamHolder.send(buffer, vadResult)

                if levelMonitoringEnabled {
                    await engineRef.updateAudioLevel(buffer: buffer)
                }

                if vadResult.isSpeech {
                    await telemetryBox.value.recordEvent(.vadSpeechDetected(confidence: vadResult.confidence))
                }
            }
        }

        // Tap callback yields copied buffers to the stream instead of creating tasks.
        // AVAudioPCMBuffer from installTap is reused by AVFoundation after the callback
        // returns, so we must deep-copy before async handoff (per Apple QA1749/audio docs).
        // bufferingNewest(10) is intentional: for real-time VAD/STT, processing stale
        // audio increases latency without benefit; dropping old buffers keeps the pipeline current.
        inputNode.installTap(
            onBus: 0,
            bufferSize: config.bufferSize,
            format: format
        ) { @Sendable [continuation] buffer, _ in
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
                return
            }
            copy.frameLength = buffer.frameLength
            let dstList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            let srcList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
            for i in 0..<min(dstList.count, srcList.count) {
                guard let dstData = dstList[i].mData, let srcData = srcList[i].mData else { continue }
                memcpy(dstData, srcData, Int(srcList[i].mDataByteSize))
            }
            continuation.yield(copy)
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
        
        // Stop buffer processing stream
        bufferStreamContinuation?.finish()
        bufferProcessingTask?.cancel()
        bufferStreamContinuation = nil
        bufferProcessingTask = nil

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

        // Emit to subscribers via Sendable holder
        audioStreamHolder.send(buffer, vadResult)
        
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
        // Capture isLast before closure to avoid Swift 6 sending parameter issues
        let isLastChunk = chunk.isLast
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleBufferCompletion(isLastChunk: isLastChunk)
            }
        }

        // TTFA: mark audio buffer scheduled (first chunk only)
        if chunk.isFirst {
            await TTFAInstrumentation.shared.markAudioScheduled()
        }

        // Start playing if not already
        if !playerNode.isPlaying {
            playerNode.play()

            // TTFA: mark audio playing (closest to audible output)
            if chunk.isFirst {
                await TTFAInstrumentation.shared.markAudioPlaying()
            }
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
            guard let self else { return }
            Task { @MainActor in
                await self.handleBufferCompletion(isLastChunk: true)
            }
        }

        // TTFA: mark audio scheduled for raw audio path (cached playback)
        await TTFAInstrumentation.shared.markAudioScheduled()

        if !playerNode.isPlaying {
            playerNode.play()

            // TTFA: mark audio playing for raw audio path
            await TTFAInstrumentation.shared.markAudioPlaying()
        }
    }
    
    // MARK: - Audio Session Notifications

    #if os(iOS)
    /// Set up observers for AVAudioSession interruption, route change, and media services reset.
    /// These are critical for maintaining audio stability during 60-90+ minute voice sessions.
    private func setupSessionNotifications() {
        // Remove any existing observers first
        teardownSessionNotifications()

        // Interruption handling (phone calls, Siri, alarms)
        let interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            Task {
                await self?.handleSessionInterruption(notification)
            }
        }
        sessionNotificationObservers.append(interruptionObserver)

        // Route change handling (Bluetooth disconnect, headphone unplug)
        let routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            Task {
                await self?.handleRouteChange(notification)
            }
        }
        sessionNotificationObservers.append(routeChangeObserver)

        // Media services reset (rare but catastrophic, requires full rebuild)
        let mediaResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            Task {
                await self?.handleMediaServicesReset()
            }
        }
        sessionNotificationObservers.append(mediaResetObserver)

        logger.info("Audio session notification observers installed")
    }

    private func teardownSessionNotifications() {
        for observer in sessionNotificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionNotificationObservers.removeAll()
    }

    /// Handle audio session interruption (phone call, Siri, alarm, etc.)
    private func handleSessionInterruption(_ notification: Notification) async {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            logger.warning("Received audio session interruption with missing type info")
            return
        }

        switch type {
        case .began:
            logger.info("Audio session interruption began")
            wasRunningBeforeInterruption = isRunning
            // Only mark as playing if actively playing (not if user manually paused)
            wasPlayingBeforeInterruption = isPlaying && !isPaused

            // Pause playback if active (preserves state for potential resume)
            if isPlaying {
                _ = await pausePlayback()
            }

            // Stop the engine and tear down the capture pipeline to release audio hardware
            if isRunning {
                engine.inputNode.removeTap(onBus: 0)
                bufferStreamContinuation?.finish()
                bufferStreamContinuation = nil
                bufferProcessingTask?.cancel()
                bufferProcessingTask = nil
                engine.stop()
                isRunning = false
                await vadService.shutdown()
            }

            await telemetry.recordEvent(.adaptiveQualityAdjusted(reason: "Audio session interruption began"))

        case .ended:
            logger.info("Audio session interruption ended")

            // Check if we should resume
            let shouldResume: Bool
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume) && wasRunningBeforeInterruption
            } else {
                shouldResume = wasRunningBeforeInterruption
            }

            if shouldResume {
                do {
                    try session.setActive(true)
                    try await start()
                    logger.info("Audio engine restarted after interruption")

                    // Resume playback if it was active before
                    if wasPlayingBeforeInterruption && isPaused {
                        _ = await resumePlayback()
                    }
                } catch {
                    logger.error("Failed to restart audio after interruption: \(error.localizedDescription)")
                }
            }

            wasRunningBeforeInterruption = false
            wasPlayingBeforeInterruption = false
            await telemetry.recordEvent(.adaptiveQualityAdjusted(reason: "Audio session interruption ended"))

        @unknown default:
            logger.warning("Unknown audio session interruption type: \(typeValue)")
        }
    }

    /// Handle audio route change (Bluetooth disconnect, headphone unplug, etc.)
    private func handleRouteChange(_ notification: Notification) async {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        logger.info("Audio route changed", metadata: ["reason": .stringConvertible(reasonValue)])

        switch reason {
        case .oldDeviceUnavailable:
            // Bluetooth disconnected or headphones unplugged
            // Audio output switches to speaker automatically, but we need to restart engine
            // to ensure the audio pipeline is properly reconfigured
            if isRunning {
                logger.info("Audio device became unavailable, restarting engine")
                await stop()
                do {
                    try session.setCategory(
                        .playAndRecord,
                        mode: .voiceChat,
                        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
                    )
                    try session.setActive(true)
                    try await start()
                    logger.info("Audio engine restarted after route change")
                } catch {
                    logger.error("Failed to restart audio after route change: \(error.localizedDescription)")
                }
                await telemetry.recordEvent(.adaptiveQualityAdjusted(reason: "Audio route changed: device unavailable"))
            }

        case .newDeviceAvailable:
            logger.info("New audio device available")
            // New device connected, engine usually handles this automatically

        case .categoryChange:
            logger.debug("Audio category changed")

        default:
            break
        }
    }

    /// Handle media services reset (rare, requires full audio stack rebuild)
    private func handleMediaServicesReset() async {
        logger.critical("Media services were reset, rebuilding audio stack")

        // Drain the old buffer consumer before rebuilding to prevent stale
        // VAD results from bleeding state across sessions
        bufferStreamContinuation?.finish()
        bufferStreamContinuation = nil
        let oldTask = bufferProcessingTask
        bufferProcessingTask = nil
        oldTask?.cancel()
        await oldTask?.value

        // The entire audio system has been torn down by iOS.
        // All AVAudioEngine state is invalid. We must rebuild from scratch.
        wasRunningBeforeInterruption = false
        wasPlayingBeforeInterruption = false
        isRunning = false
        isPlaying = false
        isPaused = false
        pendingBuffers.removeAll()
        playbackFormat = nil

        // Resume any waiting continuation so callers don't hang
        if let continuation = playbackCompletionContinuation {
            playbackCompletionContinuation = nil
            continuation.resume()
        }

        // Dispose orphaned audio objects per Apple QA1749.
        // After a media services reset, existing AVAudioEngine/AVAudioPlayerNode
        // instances are invalid and must be fully recreated.
        engine.stop()
        engine.reset()
        if engine.attachedNodes.contains(playerNode) {
            engine.detach(playerNode)
        }
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // Rebuild: reconfigure and restart with fresh instances
        do {
            try await configure(config: config)
            try await start()
            logger.info("Audio stack rebuilt after media services reset")
        } catch {
            logger.error("Failed to rebuild audio stack after media reset: \(error.localizedDescription)")
        }

        await telemetry.recordEvent(.adaptiveQualityAdjusted(reason: "Media services reset, audio stack rebuilt"))
    }
    #endif

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
    
    /// Thermal adaptation levels, ordered by severity
    private enum ThermalAdaptationLevel: Int, Comparable {
        case none = 0
        case serious = 1
        case critical = 2

        static func < (lhs: ThermalAdaptationLevel, rhs: ThermalAdaptationLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Currently applied thermal adaptation level
    private var thermalAdaptationLevel: ThermalAdaptationLevel = .none

    private func adaptQualityForThermalState(_ state: ProcessInfo.ThermalState) async {
        // Protect TTS pipeline (primary capability). Shed other resources instead.
        switch state {
        case .serious:
            guard thermalAdaptationLevel != .serious else { return }
            thermalAdaptationLevel = .serious
            logger.warning("Thermal state SERIOUS: reducing non-TTS resource usage")
            // Increase VAD threshold to reduce processing frequency
            await vadService.configure(
                threshold: min(config.vadThreshold + 0.15, 0.9),
                contextWindow: config.vadContextWindow
            )
            await telemetry.recordEvent(.adaptiveQualityAdjusted(reason: "Thermal serious: increased VAD threshold, reduced monitoring"))

        case .critical:
            guard thermalAdaptationLevel != .critical else { return }
            thermalAdaptationLevel = .critical
            logger.error("Thermal state CRITICAL: aggressive non-TTS resource shedding")
            // Aggressively reduce non-TTS work
            await vadService.configure(
                threshold: min(config.vadThreshold + 0.25, 0.95),
                contextWindow: max(config.vadContextWindow - 1, 1)
            )
            await telemetry.recordEvent(.adaptiveQualityAdjusted(reason: "Thermal critical: aggressive resource shedding to protect TTS"))

        case .nominal, .fair:
            if thermalAdaptationLevel > .none {
                thermalAdaptationLevel = .none
                logger.info("Thermal state nominal/fair: restoring normal settings")
                // Restore original VAD settings
                await vadService.configure(
                    threshold: config.vadThreshold,
                    contextWindow: config.vadContextWindow
                )
                await telemetry.recordEvent(.adaptiveQualityAdjusted(reason: "Thermal recovered: restored normal settings"))
            }

        @unknown default:
            break
        }
    }

    // MARK: - Level Monitoring

    private func startLevelMonitoring(interval: TimeInterval) async {
        // Level updates are computed in processAudioBuffer/updateAudioLevel
        // No timer needed; the tap callback drives updates
    }

    private func stopLevelMonitoring() async {
        // No timer to clean up; level monitoring is driven by the audio tap
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
        #if os(iOS)
        teardownSessionNotifications()
        #endif
    }
}
