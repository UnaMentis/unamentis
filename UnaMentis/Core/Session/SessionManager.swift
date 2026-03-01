// UnaMentis - Session Manager
// Orchestrates voice conversation sessions
//
// Part of Core Components (TDD Section 3.2)

import Foundation
@preconcurrency import AVFoundation
import Combine
import CoreData
import Logging

// MARK: - Session State

/// State machine for session management
public enum SessionState: String, Sendable {
    case idle = "Idle"
    case userSpeaking = "User Speaking"
    case aiThinking = "AI Thinking"
    case aiSpeaking = "AI Speaking"
    case interrupted = "Interrupted"
    case paused = "Paused"
    case processingUserUtterance = "Processing Utterance"
    case error = "Error"

    /// Whether the session is actively running (not idle or error)
    public var isActive: Bool {
        switch self {
        case .idle, .error:
            return false
        default:
            return true
        }
    }

    /// Whether the session is paused (frozen state, can resume)
    public var isPaused: Bool {
        self == .paused
    }
}

// MARK: - TTS Playback Configuration

/// Configuration for TTS playback behavior - tunable settings for eliminating audio gaps
public struct TTSPlaybackConfig: Codable, Sendable {
    /// Enable prefetching next sentence while current plays
    public var enablePrefetch: Bool

    /// Minimum lookahead time in seconds (how far ahead to start prefetch)
    /// Lower = less memory, higher = smoother playback
    public var prefetchLookaheadSeconds: TimeInterval

    /// Number of sentences to prefetch ahead (1-3 recommended)
    public var prefetchQueueDepth: Int

    /// Silence duration between sentences in ms (0 = no gap, natural flow)
    public var interSentenceSilenceMs: Int

    /// Enable multi-buffer scheduling in AudioEngine
    public var enableMultiBufferScheduling: Bool

    /// Number of buffers to keep scheduled ahead
    public var scheduledBufferCount: Int

    public static let `default` = TTSPlaybackConfig(
        enablePrefetch: true,
        prefetchLookaheadSeconds: 1.5,
        prefetchQueueDepth: 1,
        interSentenceSilenceMs: 0,
        enableMultiBufferScheduling: true,
        scheduledBufferCount: 2
    )

    /// Minimal latency preset (aggressive prefetch)
    public static let lowLatency = TTSPlaybackConfig(
        enablePrefetch: true,
        prefetchLookaheadSeconds: 2.0,
        prefetchQueueDepth: 2,
        interSentenceSilenceMs: 0,
        enableMultiBufferScheduling: true,
        scheduledBufferCount: 3
    )

    /// Conservative preset (less aggressive, saves resources)
    public static let conservative = TTSPlaybackConfig(
        enablePrefetch: true,
        prefetchLookaheadSeconds: 1.0,
        prefetchQueueDepth: 1,
        interSentenceSilenceMs: 100,
        enableMultiBufferScheduling: false,
        scheduledBufferCount: 1
    )

    /// Disabled preset (original behavior, for debugging)
    public static let disabled = TTSPlaybackConfig(
        enablePrefetch: false,
        prefetchLookaheadSeconds: 0,
        prefetchQueueDepth: 0,
        interSentenceSilenceMs: 0,
        enableMultiBufferScheduling: false,
        scheduledBufferCount: 1
    )

    public init(
        enablePrefetch: Bool = true,
        prefetchLookaheadSeconds: TimeInterval = 1.5,
        prefetchQueueDepth: Int = 1,
        interSentenceSilenceMs: Int = 0,
        enableMultiBufferScheduling: Bool = true,
        scheduledBufferCount: Int = 2
    ) {
        self.enablePrefetch = enablePrefetch
        self.prefetchLookaheadSeconds = prefetchLookaheadSeconds
        self.prefetchQueueDepth = prefetchQueueDepth
        self.interSentenceSilenceMs = interSentenceSilenceMs
        self.enableMultiBufferScheduling = enableMultiBufferScheduling
        self.scheduledBufferCount = scheduledBufferCount
    }
}

/// TTS Playback preset options for UI picker
public enum TTSPlaybackPreset: String, CaseIterable, Sendable {
    case `default` = "Default"
    case lowLatency = "Low Latency"
    case conservative = "Conservative"
    case disabled = "Disabled"
    case custom = "Custom"

    public var config: TTSPlaybackConfig? {
        switch self {
        case .default: return .default
        case .lowLatency: return .lowLatency
        case .conservative: return .conservative
        case .disabled: return .disabled
        case .custom: return nil  // Custom means use individual settings
        }
    }
}

// MARK: - Session Configuration

/// Configuration for a voice session
public struct SessionConfig: Codable, Sendable {
    /// Audio configuration
    public var audio: AudioEngineConfig
    
    /// LLM configuration
    public var llm: LLMConfig
    
    /// TTS voice configuration
    public var voice: TTSVoiceConfig
    
    /// System prompt for the AI
    public var systemPrompt: String
    
    /// Enable cost tracking
    public var enableCostTracking: Bool
    
    /// Maximum session duration in seconds (0 = unlimited)
    public var maxDuration: TimeInterval
    
    /// Enable interruption handling
    public var enableInterruptions: Bool

    /// TTS playback configuration (prefetching, buffer scheduling)
    public var ttsPlayback: TTSPlaybackConfig

    public static let `default` = SessionConfig(
        audio: .default,
        llm: .default,
        voice: .default,
        systemPrompt: """
            You are a helpful AI learning assistant engaged in a voice conversation.
            Keep responses concise and conversational.
            Ask follow-up questions to check understanding.
            """,
        enableCostTracking: true,
        maxDuration: 5400, // 90 minutes
        enableInterruptions: true,
        ttsPlayback: .default
    )

    public init(
        audio: AudioEngineConfig = .default,
        llm: LLMConfig = .default,
        voice: TTSVoiceConfig = .default,
        systemPrompt: String = "",
        enableCostTracking: Bool = true,
        maxDuration: TimeInterval = 5400,
        enableInterruptions: Bool = true,
        ttsPlayback: TTSPlaybackConfig = .default
    ) {
        self.audio = audio
        self.llm = llm
        self.voice = voice
        self.systemPrompt = systemPrompt
        self.enableCostTracking = enableCostTracking
        self.maxDuration = maxDuration
        self.enableInterruptions = enableInterruptions
        self.ttsPlayback = ttsPlayback
    }
}

// MARK: - Session Manager

/// Orchestrates voice conversation sessions
///
/// Responsibilities:
/// - State machine management
/// - Turn-taking between user and AI
/// - Interruption handling
/// - Service coordination (VAD, STT, LLM, TTS)
/// - Context management for long conversations
@MainActor
public final class SessionManager: ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(label: "com.unamentis.session")
    
    /// Current session state
    @Published public private(set) var state: SessionState = .idle
    
    /// Current user transcript (interim/final)
    @Published public private(set) var userTranscript: String = ""
    
    /// Current AI response being spoken
    @Published public private(set) var aiResponse: String = ""

    /// Current audio level (dB) for visualization
    @Published public private(set) var audioLevel: Float = -60.0

    /// Conversation history
    private var conversationHistory: [LLMMessage] = []
    
    /// Services
    private var audioEngine: AudioEngine?
    private var sttService: (any STTService)?
    private var ttsService: (any TTSService)?
    private var llmService: (any LLMService)?
    private var telemetry: TelemetryEngine
    private var curriculum: CurriculumEngine?
    private var persistenceController: PersistenceController
    
    /// Configuration
    private var config: SessionConfig
    
    /// Session tracking
    private var sessionStartTime: Date?
    private var currentTurnStartTime: Date?
    
    /// Stream cancellation
    private var sttStreamTask: Task<Void, Never>?
    private var llmStreamTask: Task<Void, Never>?
    private var ttsStreamTask: Task<Void, Never>?
    private var audioSubscription: AnyCancellable?

    /// Silence detection for utterance completion
    private var silenceStartTime: Date?
    private var hasDetectedSpeech: Bool = false
    private var speechStartTime: Date?  // Track when user started speaking for STT cost
    private let silenceThreshold: TimeInterval = 1.5  // seconds of silence before completing utterance
    private var pendingUtteranceTask: Task<Void, Never>?

    /// Sentence-level TTS streaming
    private var sentenceBuffer: String = ""
    private var isLLMStreamingComplete: Bool = false
    private var sentenceIndex: Int = 0

    /// TTS playback orchestrator (replaces manual queue/prefetch)
    private var ttsOrchestrator: AudioPlaybackOrchestrator?

    /// Delegate bridge for orchestrator events
    private var ttsOrchestratorDelegate: SessionOrchestratorDelegate?

    /// Metrics upload
    private let metricsUploadService: MetricsUploadService
    private var metricsUploadTimer: Task<Void, Never>?
    private let metricsUploadInterval: TimeInterval = 300  // 5 minutes

    // MARK: - Initialization
    
    public init(
        config: SessionConfig = .default,
        telemetry: TelemetryEngine,
        curriculum: CurriculumEngine? = nil,
        persistenceController: PersistenceController = .shared
    ) {
        // Start with provided config and override TTS playback with saved settings
        var mutableConfig = config
        mutableConfig.ttsPlayback = Self.loadTTSPlaybackConfig()
        self.config = mutableConfig
        self.telemetry = telemetry
        self.curriculum = curriculum
        self.persistenceController = persistenceController
        self.metricsUploadService = MetricsUploadService()
        logger.info("SessionManager initialized with TTS config: prefetch=\(mutableConfig.ttsPlayback.enablePrefetch), lookahead=\(mutableConfig.ttsPlayback.prefetchLookaheadSeconds)s")
    }

    /// Load TTS playback configuration from UserDefaults
    private static func loadTTSPlaybackConfig() -> TTSPlaybackConfig {
        let defaults = UserDefaults.standard

        let enablePrefetch = defaults.object(forKey: "tts_playback_enable_prefetch") != nil
            ? defaults.bool(forKey: "tts_playback_enable_prefetch")
            : true

        let lookahead = defaults.double(forKey: "tts_playback_prefetch_lookahead")
        let prefetchLookahead = lookahead > 0 ? lookahead : 1.5

        let queueDepth = defaults.integer(forKey: "tts_playback_prefetch_queue_depth")
        let prefetchQueueDepth = queueDepth > 0 ? queueDepth : 1

        let interSentenceSilenceMs = defaults.integer(forKey: "tts_playback_inter_sentence_silence_ms")

        let enableMultiBuffer = defaults.object(forKey: "tts_playback_enable_multi_buffer") != nil
            ? defaults.bool(forKey: "tts_playback_enable_multi_buffer")
            : true

        let bufferCount = defaults.integer(forKey: "tts_playback_scheduled_buffer_count")
        let scheduledBufferCount = bufferCount > 0 ? bufferCount : 2

        return TTSPlaybackConfig(
            enablePrefetch: enablePrefetch,
            prefetchLookaheadSeconds: prefetchLookahead,
            prefetchQueueDepth: prefetchQueueDepth,
            interSentenceSilenceMs: interSentenceSilenceMs,
            enableMultiBufferScheduling: enableMultiBuffer,
            scheduledBufferCount: scheduledBufferCount
        )
    }
    
    // MARK: - Session Lifecycle
    
    /// Start a new session
    /// - Parameters:
    ///   - sttService: Speech-to-text service
    ///   - ttsService: Text-to-speech service
    ///   - llmService: Language model service
    ///   - vadService: Voice activity detection service
    ///   - systemPrompt: Optional override for system prompt (uses config default if nil)
    ///   - lectureMode: If true, AI speaks first immediately after session starts
    public func startSession(
        sttService: any STTService,
        ttsService: any TTSService,
        llmService: any LLMService,
        vadService: any VADService,
        systemPrompt: String? = nil,
        lectureMode: Bool = false
    ) async throws {
        guard state == .idle else {
            logger.warning("Cannot start session: not in idle state (current state: \(state.rawValue))")
            return
        }

        // Check maintenance mode feature flag
        if await FeatureFlagService.shared.isEnabled(SessionFeatureFlagKeys.maintenanceMode) {
            logger.warning("Session start blocked: maintenance mode is enabled")
            throw SessionError.maintenanceMode
        }

        logger.info("SessionManager.startSession called (lectureMode: \(lectureMode))")
        logger.info("  LLM service type: \(type(of: llmService))")
        logger.info("  TTS service type: \(type(of: ttsService))")
        logger.info("  STT service type: \(type(of: sttService))")

        // Store services
        self.sttService = sttService
        self.ttsService = ttsService
        self.llmService = llmService

        // Create and configure audio engine
        audioEngine = AudioEngine(
            config: config.audio,
            vadService: vadService,
            telemetry: telemetry
        )

        try await audioEngine?.configure(config: config.audio)

        // Note: TTS voice is already configured when ttsService is created in SessionView
        // Do NOT call ttsService.configure(config.voice) here as config.voice defaults to "default"
        // which would overwrite the properly configured voice ID

        // Initialize conversation with system prompt (use override if provided)
        let effectiveSystemPrompt = systemPrompt ?? config.systemPrompt
        conversationHistory = [
            LLMMessage(role: .system, content: effectiveSystemPrompt)
        ]
        
        // Start telemetry session with device metrics sampling
        await telemetry.startSession()
        await telemetry.startDeviceMetricsSampling()
        sessionStartTime = Date()

        // Configure and start metrics upload service
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let serverIP = UserDefaults.standard.string(forKey: "serverIP") ?? ""
        if selfHostedEnabled && !serverIP.isEmpty {
            await metricsUploadService.configure(serverHost: serverIP)
            // Drain any queued metrics from previous sessions
            await metricsUploadService.drainQueue()
        }
        startMetricsUploadTimer()

        // Initialize silence tracking
        hasDetectedSpeech = false
        silenceStartTime = nil
        pendingUtteranceTask = nil

        // Start audio capture
        try await audioEngine?.start()

        // Subscribe to audio stream for VAD events
        subscribeToAudioStream()

        if lectureMode {
            // Lecture mode: AI speaks first
            logger.info("Lecture mode enabled - AI will begin speaking")

            // Add a user message to trigger the lecture start
            conversationHistory.append(LLMMessage(role: .user, content: "Please begin the lecture now."))

            // Set timing for TTFT tracking
            currentTurnStartTime = Date()

            // Start LLM response immediately (generateAIResponse sets state to aiThinking)
            await generateAIResponse()
        } else {
            // Normal mode: User speaks first
            await setState(.userSpeaking)
            try await startSTTStreaming()
        }

        logger.info("Session started successfully")
    }
    
    /// Stop the current session with complete cleanup of all async tasks and state
    ///
    /// This method ensures a hard stop of all session components:
    /// - All streaming tasks (STT, LLM, TTS) are cancelled and awaited
    /// - All prefetch tasks are cancelled
    /// - Audio playback is stopped immediately
    /// - All queues are cleared
    /// - State is reset to idle
    public func stopSession() async {
        logger.info("Stopping session - beginning hard stop sequence")

        // CRITICAL: Set a flag to prevent any new work from starting
        let previousState = state
        await setState(.idle)  // Immediately mark as stopping

        // Cancel barge-in confirmation if in progress
        bargeInConfirmationTask?.cancel()
        bargeInConfirmationTask = nil
        isTentativePause = false

        // STEP 1: Cancel all streaming tasks first (order matters for race conditions)
        // Cancel LLM first to stop new tokens from being generated
        llmStreamTask?.cancel()

        // Stop TTS orchestrator to halt playback and prefetch
        if let orch = ttsOrchestrator {
            Task { await orch.stopPlayback() }
        }

        // Cancel STT stream
        sttStreamTask?.cancel()

        // Cancel legacy TTS stream
        ttsStreamTask?.cancel()

        // Cancel pending utterance detection
        pendingUtteranceTask?.cancel()

        // Cancel audio subscription to stop VAD processing
        audioSubscription?.cancel()

        // STEP 2: Nil out task references after cancellation
        llmStreamTask = nil
        sttStreamTask = nil
        ttsStreamTask = nil
        pendingUtteranceTask = nil
        audioSubscription = nil

        // STEP 3: Stop audio immediately (this stops any in-flight playback)
        await audioEngine?.stopPlayback()
        await audioEngine?.stop()

        // STEP 4: Stop STT service
        do {
            try await sttService?.stopStreaming()
        } catch {
            logger.warning("Error stopping STT service: \(error.localizedDescription)")
        }

        // STEP 5: End telemetry and stop device metrics sampling
        await telemetry.stopDeviceMetricsSampling()
        await telemetry.endSession()

        // STEP 5.5: Stop metrics upload timer and upload final metrics
        stopMetricsUploadTimer()
        if previousState.isActive, let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            let snapshot = await telemetry.exportMetrics()
            await metricsUploadService.upload(snapshot, sessionDuration: duration)
        }

        // STEP 6: Persist session to Core Data before clearing state
        // Only if we were actually in an active state
        if previousState.isActive {
            await persistSessionToStorage()
        }

        // STEP 7: Clear all state completely
        conversationHistory.removeAll()
        silenceStartTime = nil
        hasDetectedSpeech = false
        sentenceBuffer = ""
        sentenceIndex = 0
        isLLMStreamingComplete = false
        ttsOrchestrator = nil
        ttsOrchestratorDelegate = nil

        // Clear service references so they can be re-created on next session
        audioEngine = nil
        sttService = nil
        ttsService = nil
        llmService = nil

        await MainActor.run {
            userTranscript = ""
            aiResponse = ""
            audioLevel = -60.0
        }

        logger.info("Session stopped - all services, tasks, and state cleared")
    }

    /// State preserved during pause for resumption
    private var pausedFromState: SessionState?

    /// Pause the current session, freezing all state for later resumption
    ///
    /// When paused:
    /// - Audio playback is paused (not stopped)
    /// - STT continues but results are buffered
    /// - LLM streaming is suspended
    /// - TTS queue processing is suspended
    /// - All state is preserved for seamless resume
    ///
    /// - Returns: True if session was paused, false if not in a pauseable state
    @discardableResult
    public func pauseSession() async -> Bool {
        guard state.isActive && !state.isPaused else {
            logger.warning("Cannot pause: session not active or already paused (state: \(state.rawValue))")
            return false
        }

        logger.info("Pausing session from state: \(state.rawValue)")

        // Remember what state we were in for resumption
        pausedFromState = state

        // Pause audio playback (preserves position)
        _ = await audioEngine?.pausePlayback()

        // Transition to paused state
        await setState(.paused)

        logger.info("Session paused - state preserved for resumption")
        return true
    }

    /// Resume a paused session, continuing exactly where it left off
    ///
    /// - Returns: True if session was resumed, false if not paused
    @discardableResult
    public func resumeSession() async -> Bool {
        guard state == .paused else {
            logger.warning("Cannot resume: session not paused (state: \(state.rawValue))")
            return false
        }

        logger.info("Resuming session")

        // Resume audio playback
        _ = await audioEngine?.resumePlayback()

        // Restore previous state (default to userSpeaking if unknown)
        let targetState = pausedFromState ?? .userSpeaking
        pausedFromState = nil

        await setState(targetState)

        logger.info("Session resumed to state: \(targetState.rawValue)")
        return true
    }

    // MARK: - Session Persistence

    /// Persist the current session to Core Data storage
    private func persistSessionToStorage() async {
        guard let startTime = sessionStartTime else {
            logger.warning("No session start time, cannot persist session")
            return
        }

        // Only persist if there's actual conversation content (more than just system prompt)
        let hasContent = conversationHistory.count > 1
        guard hasContent else {
            logger.info("No conversation content to persist")
            return
        }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Create a copy of conversation history for the background task
        let historySnapshot = conversationHistory
        let configSnapshot = config

        logger.info("Persisting session with \(historySnapshot.count) messages, duration: \(duration)s")

        do {
            let context = persistenceController.viewContext

            // Create Session entity
            let session = Session(context: context)
            session.id = UUID()
            session.startTime = startTime
            session.endTime = endTime
            session.duration = duration

            // Encode config to Data
            if let configData = try? JSONEncoder().encode(configSnapshot) {
                session.config = configData
            }

            // Export and save metrics snapshot from telemetry
            let metricsSnapshot = await telemetry.exportMetrics()
            if let metricsData = try? JSONEncoder().encode(metricsSnapshot) {
                session.metricsSnapshot = metricsData
                logger.info("Saved metrics snapshot: e2eMedian=\(metricsSnapshot.latencies.e2eMedianMs)ms, totalCost=$\(metricsSnapshot.costs.totalSession)")
            }

            // Calculate and save total cost
            session.totalCost = NSDecimalNumber(decimal: metricsSnapshot.costs.totalSession)

            // Create TranscriptEntry entities for each message
            var transcriptEntries: [TranscriptEntry] = []
            for (index, message) in historySnapshot.enumerated() {
                // Skip system prompts in transcript
                if message.role == .system {
                    continue
                }

                let entry = TranscriptEntry(context: context)
                entry.id = UUID()
                entry.content = message.content
                entry.role = message.role.rawValue
                // Estimate timestamp based on order (we don't track exact message times)
                entry.timestamp = startTime.addingTimeInterval(Double(index) * 5.0)
                entry.session = session
                transcriptEntries.append(entry)
            }

            // Set the transcript relationship
            session.transcript = NSOrderedSet(array: transcriptEntries)

            // Save to Core Data
            try persistenceController.save()

            logger.info("Session persisted successfully with \(transcriptEntries.count) transcript entries")

        } catch {
            logger.error("Failed to persist session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - State Management
    
    private func setState(_ newState: SessionState) async {
        let oldState = await state
        logger.debug("State transition: \(oldState.rawValue) -> \(newState.rawValue)")
        
        await MainActor.run {
            state = newState
        }
    }
    
    // MARK: - Audio Stream Handling
    
    private func subscribeToAudioStream() {
        guard let audioEngine = audioEngine else { return }

        audioSubscription = audioEngine.audioStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (buffer, vadResult) in
                guard let self = self else { return }

                // Calculate audio level from buffer for visualization
                if let channelData = buffer.floatChannelData?[0] {
                    let frameLength = Int(buffer.frameLength)
                    var sum: Float = 0
                    for i in 0..<frameLength {
                        let sample = channelData[i]
                        sum += sample * sample
                    }
                    let rms = sqrt(sum / Float(frameLength))
                    let db = 20 * log10(max(rms, 1e-10))
                    self.audioLevel = db
                }

                Task.detached {
                    await self.handleVADResult(vadResult, buffer: buffer)
                }
            }
    }
    
    private func handleVADResult(_ result: VADResult, buffer: AVAudioPCMBuffer) async {
        let currentState = await state

        switch currentState {
        case .userSpeaking:
            // Send audio to STT
            do {
                try await sttService?.sendAudio(buffer)
            } catch {
                logger.error("Failed to send audio to STT: \(error.localizedDescription)")
            }

            // Track speech/silence for utterance detection
            if result.isSpeech {
                // User is speaking - mark speech detected and reset silence timer
                if !hasDetectedSpeech {
                    logger.info("🎤 Speech started - VAD detected voice activity")
                    speechStartTime = Date()  // Track when speech started for STT cost
                }
                hasDetectedSpeech = true
                silenceStartTime = nil
                pendingUtteranceTask?.cancel()
                pendingUtteranceTask = nil
            } else if hasDetectedSpeech {
                // User was speaking but now silent - start or check silence timer
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                    logger.debug("Silence detected after speech, starting timer")

                    // Schedule utterance completion after silence threshold
                    pendingUtteranceTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64(silenceThreshold * 1_000_000_000))

                        // Check if still silent and not cancelled
                        guard !Task.isCancelled else {
                            await self.logger.debug("Silence timer cancelled - user resumed speaking")
                            return
                        }
                        let currentState = await self.state
                        guard currentState == .userSpeaking else {
                            await self.logger.debug("Silence timer: state changed to \(currentState.rawValue), not completing")
                            return
                        }
                        let transcript = await self.userTranscript
                        guard !transcript.isEmpty else {
                            await self.logger.warning("🔇 Silence threshold reached but transcript is EMPTY - STT may not be working")
                            return
                        }

                        await self.logger.info("🔇 Silence threshold reached, completing utterance: \(transcript.prefix(50))...")
                        await self.completeUtteranceFromSilence(transcript)
                    }
                }
            }

        case .aiSpeaking:
            // Check for interruption - use tentative pause approach
            if config.enableInterruptions && result.isSpeech && result.confidence > config.audio.bargeInThreshold {
                // First barge-in triggers tentative pause
                await handleTentativeBargeIn()
            }

        case .interrupted:
            // We're in tentative pause - if speech continues, confirm the barge-in
            if result.isSpeech && result.confidence > config.audio.bargeInThreshold {
                // Continued speech confirms the barge-in
                await confirmBargeIn()
            }

        default:
            break
        }
    }

    /// Complete utterance based on silence detection (used when STT doesn't provide final results)
    private func completeUtteranceFromSilence(_ transcript: String) async {
        // Reset silence tracking
        silenceStartTime = nil
        hasDetectedSpeech = false
        pendingUtteranceTask = nil

        // Process the utterance
        await processUserUtterance(transcript)
    }
    
    // MARK: - STT Handling
    
    private func startSTTStreaming() async throws {
        guard let sttService = sttService,
              let sourceFormat = await audioEngine?.format,
              // Create a copy to satisfy Swift 6 sending requirements
              let format = AVAudioFormat(
                  commonFormat: sourceFormat.commonFormat,
                  sampleRate: sourceFormat.sampleRate,
                  channels: sourceFormat.channelCount,
                  interleaved: sourceFormat.isInterleaved
              ) else {
            throw SessionError.servicesNotConfigured
        }

        let stream = try await sttService.startStreaming(audioFormat: format)
        
        sttStreamTask = Task {
            for await result in stream {
                await handleSTTResult(result)
            }
        }
    }
    
    private func handleSTTResult(_ result: STTResult) async {
        logger.debug("STT result - transcript: '\(result.transcript.prefix(30))...', isFinal: \(result.isFinal), isEndOfUtterance: \(result.isEndOfUtterance)")

        // Update transcript
        await MainActor.run {
            userTranscript = result.transcript
        }

        // Record latency
        await telemetry.recordLatency(.sttEmission, result.latency)

        // If final result, process the utterance
        if result.isFinal && result.isEndOfUtterance && !result.transcript.isEmpty {
            logger.info("Got final STT result, will process utterance")
            await processUserUtterance(result.transcript)
        }
    }
    
    // MARK: - Debug Injection

    #if DEBUG
    /// Debug: Inject text as if user spoke it (bypasses STT)
    /// Use this for testing AI responses without voice input
    public func injectUserUtterance(_ text: String) async {
        guard state.isActive else {
            logger.warning("Cannot inject utterance - session not active")
            return
        }

        logger.info("[DEBUG] Injecting utterance: \(text.prefix(50))...")

        // Update transcript display
        await MainActor.run {
            self.userTranscript = text
        }

        // Process through normal pipeline
        await processUserUtterance(text)
    }
    #endif

    // MARK: - Cost Recording Helpers

    /// Record TTS cost for synthesized text
    private func recordTTSCost(for text: String) async {
        guard let ttsService = ttsService else { return }
        let costPerChar = await ttsService.costPerCharacter
        if costPerChar > 0 {
            let cost = Decimal(text.count) * costPerChar
            await telemetry.recordCost(.tts, amount: cost, description: "TTS (\(text.count) chars)")
            logger.info("Recorded TTS cost: $\(cost) for \(text.count) chars")
        }
    }

    // MARK: - Metrics Upload Timer

    /// Start the periodic metrics upload timer
    private func startMetricsUploadTimer() {
        metricsUploadTimer?.cancel()
        metricsUploadTimer = Task {
            while !Task.isCancelled {
                // Wait for the interval
                try? await Task.sleep(nanoseconds: UInt64(metricsUploadInterval * 1_000_000_000))

                // Upload interim metrics if session is still active
                if state.isActive, let startTime = sessionStartTime {
                    let duration = Date().timeIntervalSince(startTime)
                    let snapshot = await telemetry.exportMetrics()
                    await metricsUploadService.upload(snapshot, sessionDuration: duration)
                    logger.info("Uploaded interim metrics at \(String(format: "%.0f", duration))s")
                }
            }
        }
    }

    /// Stop the periodic metrics upload timer
    private func stopMetricsUploadTimer() {
        metricsUploadTimer?.cancel()
        metricsUploadTimer = nil
    }

    // MARK: - Utterance Processing

    private func processUserUtterance(_ transcript: String) async {
        logger.info("Processing user utterance: \(transcript.prefix(50))...")

        await setState(.processingUserUtterance)
        currentTurnStartTime = Date()

        // Record STT cost based on speech duration
        if let sttService = sttService, let startTime = speechStartTime {
            let duration = Date().timeIntervalSince(startTime)
            let costPerHour = await sttService.costPerHour
            if costPerHour > 0 {
                // Cost = (duration in hours) * cost per hour
                let cost = (Decimal(duration) / 3600) * costPerHour
                await telemetry.recordCost(.stt, amount: cost, description: "STT (\(String(format: "%.1f", duration))s audio)")
                logger.info("Recorded STT cost: $\(cost) for \(String(format: "%.1f", duration))s")
            }
        }
        speechStartTime = nil  // Reset for next utterance

        // Add to conversation history
        conversationHistory.append(LLMMessage(role: .user, content: transcript))

        // Record event
        await telemetry.recordEvent(.userFinishedSpeaking(transcript: transcript))

        // Generate AI response
        await generateAIResponse()
    }
    
    // MARK: - LLM Handling
    
    private func generateAIResponse() async {
        await setState(.aiThinking)

        guard let llmService = llmService else {
            logger.error("LLM service not available")
            await handleProcessingError("LLM service not configured")
            return
        }

        do {
            // Capture metrics before streaming to calculate cost delta
            let metricsBefore = await llmService.metrics

            logger.info("Calling LLM streamCompletion with \(conversationHistory.count) messages")
            let stream = try await llmService.streamCompletion(
                messages: conversationHistory,
                config: config.llm
            )

            var fullResponse = ""
            var isFirstToken = true

            // Reset sentence buffer and orchestrator for new response
            self.sentenceBuffer = ""
            self.sentenceIndex = 0

            // Start the TTS playback orchestrator for this turn
            self.startTTSOrchestrator()

            llmStreamTask = Task {
                for await token in stream {
                    if isFirstToken {
                        isFirstToken = false
                        logger.info("Received first LLM token")
                        await self.telemetry.recordEvent(.llmFirstTokenReceived)

                        // Record TTFT
                        if let turnStart = self.currentTurnStartTime {
                            let ttft = Date().timeIntervalSince(turnStart)
                            await self.telemetry.recordLatency(.llmFirstToken, ttft)
                        }

                        // Start speaking while streaming
                        await self.setState(.aiSpeaking)
                    }

                    fullResponse += token.content
                    self.sentenceBuffer += token.content

                    await MainActor.run {
                        self.aiResponse = fullResponse
                    }

                    // Check for complete sentences and queue them for TTS
                    await self.extractAndQueueSentences()

                    if token.isDone {
                        break
                    }
                }

                // Queue any remaining text in the buffer
                let remaining = self.sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !remaining.isEmpty {
                    let segment = SessionSentenceSegment(index: self.sentenceIndex, text: remaining)
                    self.sentenceIndex += 1
                    self.sentenceBuffer = ""
                    logger.info("Queued final sentence fragment for TTS")
                    if let orch = self.ttsOrchestrator {
                        await orch.appendSegments([segment])
                    }
                }

                // Check if we got any response
                if fullResponse.isEmpty {
                    logger.warning("LLM returned empty response")
                    await self.handleProcessingError("No response from AI")
                    return
                }

                logger.info("LLM response complete: \(fullResponse.prefix(50))...")

                // Add AI response to history
                self.conversationHistory.append(LLMMessage(role: .assistant, content: fullResponse))

                // Signal that LLM streaming is complete; orchestrator will finish
                // when all segments have been played
                self.isLLMStreamingComplete = true
                if let orch = self.ttsOrchestrator {
                    await orch.signalNoMoreSegments()
                }
                logger.info("LLM streaming complete - orchestrator will finish when all sentences played")

                // Record LLM cost based on token usage delta
                let metricsAfter = await llmService.metrics
                let inputTokens = metricsAfter.totalInputTokens - metricsBefore.totalInputTokens
                let outputTokens = metricsAfter.totalOutputTokens - metricsBefore.totalOutputTokens
                let inputCost = Decimal(inputTokens) * (await llmService.costPerInputToken)
                let outputCost = Decimal(outputTokens) * (await llmService.costPerOutputToken)

                if inputCost > 0 {
                    await self.telemetry.recordCost(.llmInput, amount: inputCost, description: "LLM input (\(inputTokens) tokens)")
                }
                if outputCost > 0 {
                    await self.telemetry.recordCost(.llmOutput, amount: outputCost, description: "LLM output (\(outputTokens) tokens)")
                }
                if inputCost > 0 || outputCost > 0 {
                    logger.info("Recorded LLM cost: input $\(inputCost) (\(inputTokens) tokens), output $\(outputCost) (\(outputTokens) tokens)")
                }

                // The queue processor will handle state transition when done
            }

        } catch {
            logger.error("LLM generation failed: \(error.localizedDescription)")
            await handleProcessingError("AI response failed: \(error.localizedDescription)")
        }
    }

    /// Handle processing errors with recovery back to listening state
    private func handleProcessingError(_ message: String) async {
        logger.error("❌ Processing error: \(message)")

        // Brief error state for UI feedback
        await setState(.error)

        // Clear any partial response
        await MainActor.run {
            aiResponse = ""
        }

        // Wait briefly so user sees error state
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        // Reset silence tracking
        hasDetectedSpeech = false
        silenceStartTime = nil

        // Recover to listening state
        await setState(.userSpeaking)

        logger.info("Recovered to userSpeaking state after error")
    }

    // MARK: - Sentence-Level TTS Streaming

    /// Extract complete sentences from the buffer and queue them for TTS
    private func extractAndQueueSentences() async {
        // Sentence-ending punctuation followed by space or end of string
        let sentenceEnders = CharacterSet(charactersIn: ".!?")

        while let range = sentenceBuffer.rangeOfCharacter(from: sentenceEnders) {
            // Check if this is followed by a space, newline, or is at the end
            let endIndex = range.upperBound
            let nextIndex = sentenceBuffer.index(after: range.lowerBound)

            // Make sure we're not in the middle of an abbreviation like "Dr." or "Mr."
            let beforePunctuation = String(sentenceBuffer[..<range.lowerBound])
            let isAbbreviation = beforePunctuation.hasSuffix("Dr") ||
                                 beforePunctuation.hasSuffix("Mr") ||
                                 beforePunctuation.hasSuffix("Mrs") ||
                                 beforePunctuation.hasSuffix("Ms") ||
                                 beforePunctuation.hasSuffix("vs") ||
                                 beforePunctuation.hasSuffix("etc") ||
                                 beforePunctuation.hasSuffix("e.g") ||
                                 beforePunctuation.hasSuffix("i.e")

            if isAbbreviation {
                // Move past this punctuation and continue looking
                if nextIndex < sentenceBuffer.endIndex {
                    let remaining = String(sentenceBuffer[nextIndex...])
                    if let nextRange = remaining.rangeOfCharacter(from: sentenceEnders) {
                        // Found another sentence ender, continue the loop
                        continue
                    }
                }
                break
            }

            // Check if followed by space or end
            if nextIndex >= sentenceBuffer.endIndex ||
               sentenceBuffer[nextIndex].isWhitespace ||
               sentenceBuffer[nextIndex].isNewline {
                // Extract the sentence (including the punctuation)
                let sentence = String(sentenceBuffer[..<nextIndex]).trimmingCharacters(in: .whitespacesAndNewlines)

                if !sentence.isEmpty {
                    // Append to orchestrator as a dynamic segment
                    let segment = SessionSentenceSegment(index: sentenceIndex, text: sentence)
                    sentenceIndex += 1
                    logger.info("🔊 Queued sentence for TTS (index \(segment.segmentIndex)): \"\(sentence.prefix(50))...\"")

                    if let orch = ttsOrchestrator {
                        Task { await orch.appendSegments([segment]) }
                    }
                }

                // Remove the sentence from the buffer
                if nextIndex < sentenceBuffer.endIndex {
                    sentenceBuffer = String(sentenceBuffer[nextIndex...]).trimmingCharacters(in: .whitespaces)
                } else {
                    sentenceBuffer = ""
                }
            } else {
                break
            }
        }
    }

    /// Start the TTS playback orchestrator for a new AI turn.
    /// Sentences are appended dynamically as LLM tokens arrive.
    private func startTTSOrchestrator() {
        guard let ttsService = ttsService, let audioEngine = audioEngine else {
            logger.error("Cannot start TTS orchestrator: services not available")
            return
        }

        // Stop any previous orchestrator
        if let prev = ttsOrchestrator {
            Task { await prev.stopPlayback() }
        }

        isLLMStreamingComplete = false

        let orch = AudioPlaybackOrchestrator(
            config: .session,
            ttsService: ttsService,
            audioEngine: audioEngine
        )

        let delegate = SessionOrchestratorDelegate(sessionManager: self)
        Task {
            await orch.setDelegate(delegate)
            await orch.setExpectsMoreSegments(true)
            await orch.startPlayback(from: 0)
        }

        ttsOrchestrator = orch
        ttsOrchestratorDelegate = delegate

        logger.info("🔊 TTS orchestrator started for new AI turn")
    }

    /// Called by orchestrator delegate when all sentences have been played
    func handleTTSPlaybackComplete() async {
        logger.info("🔊 TTS orchestrator finished - all sentences played")

        // Record end-to-end latency
        if let turnStart = currentTurnStartTime {
            let e2e = Date().timeIntervalSince(turnStart)
            await telemetry.recordLatency(.endToEndTurn, e2e)
            logger.info("Turn E2E latency: \(String(format: "%.3f", e2e))s")
        }

        // Ready for next user turn
        await telemetry.recordEvent(.aiFinishedSpeaking)
        logger.info("AI finished speaking")

        // Add a brief cooldown before accepting new speech
        logger.info("🔇 Cooldown period before accepting new speech...")
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms cooldown

        // Reset silence tracking for new turn
        hasDetectedSpeech = false
        silenceStartTime = nil

        // Clear current transcript for new turn (conversation history already saved)
        await MainActor.run {
            userTranscript = ""
        }

        await setState(.userSpeaking)
        logger.info("Ready for user to speak")

        // NOTE: aiResponse is NOT cleared so user can still see the AI's last response
    }

    // MARK: - TTS Handling (Legacy - Full Response)

    private func synthesizeAndPlayResponse(_ text: String) async {
        logger.info("synthesizeAndPlayResponse called with text length: \(text.count)")

        guard let ttsService = ttsService else {
            logger.error("TTS service is nil - cannot synthesize")
            return
        }

        logger.info("TTS service available, starting synthesis...")

        do {
            logger.debug("Calling ttsService.synthesize...")
            let stream = try await ttsService.synthesize(text: text)
            logger.info("TTS synthesis stream created successfully")

            ttsStreamTask = Task {
                var chunkCount = 0
                logger.debug("Starting TTS stream iteration...")

                for await chunk in stream {
                    chunkCount += 1
                    logger.debug("Received TTS chunk \(chunkCount): isFirst=\(chunk.isFirst), isLast=\(chunk.isLast), dataSize=\(chunk.audioData.count)")

                    // Record TTFB on first chunk
                    if chunk.isFirst, let ttfb = chunk.timeToFirstByte {
                        await self.telemetry.recordLatency(.ttsTTFB, ttfb)
                        logger.info("TTS TTFB: \(String(format: "%.3f", ttfb))s")
                    }

                    // Play audio chunk
                    logger.debug("Attempting to play audio chunk...")
                    if let audioEngine = self.audioEngine {
                        do {
                            try await audioEngine.playAudio(chunk)
                            logger.debug("Audio chunk played successfully")
                        } catch {
                            logger.error("Failed to play audio chunk: \(error.localizedDescription)")
                        }
                    } else {
                        logger.error("AudioEngine is nil - cannot play audio")
                    }

                    if chunk.isLast {
                        logger.info("Received last TTS chunk, total chunks: \(chunkCount)")
                        // Record TTS cost for full response synthesis
                        await self.recordTTSCost(for: text)
                        break
                    }
                }

                logger.info("TTS stream completed with \(chunkCount) chunks")

                // Record end-to-end latency
                if let turnStart = self.currentTurnStartTime {
                    let e2e = Date().timeIntervalSince(turnStart)
                    await self.telemetry.recordLatency(.endToEndTurn, e2e)
                    logger.info("Turn E2E latency: \(String(format: "%.3f", e2e))s")
                }

                // Ready for next user turn
                await self.telemetry.recordEvent(.aiFinishedSpeaking)
                logger.info("AI finished speaking, transitioning to userSpeaking state")

                // Reset silence tracking for new turn
                self.hasDetectedSpeech = false
                self.silenceStartTime = nil

                await self.setState(.userSpeaking)

                // Clear AI response display and user transcript for new turn
                await MainActor.run {
                    self.aiResponse = ""
                    self.userTranscript = ""
                }
            }

        } catch {
            logger.error("TTS synthesis failed: \(error.localizedDescription), full error: \(error)")
            await setState(.error)
        }
    }
    
    // MARK: - Interruption Handling

    /// Whether we're in a tentative barge-in pause (waiting to confirm real speech)
    private var isTentativePause = false

    /// Task for confirming barge-in after pause
    private var bargeInConfirmationTask: Task<Void, Never>?

    /// Handle initial barge-in detection - tentatively pause, wait for confirmation
    private func handleTentativeBargeIn() async {
        // Already in tentative pause or already interrupted - don't double-handle
        guard !isTentativePause && state == .aiSpeaking else { return }

        logger.info("Tentative barge-in detected - pausing playback")

        // Pause playback immediately (not stop - can resume)
        if let paused = await audioEngine?.pausePlayback(), paused {
            isTentativePause = true
            await setState(.interrupted)

            // Cancel any existing confirmation task
            bargeInConfirmationTask?.cancel()

            // Start confirmation: wait to see if real speech follows
            bargeInConfirmationTask = Task {
                // Wait for speech confirmation (e.g., 500ms of continued speech)
                // During this time, VAD will keep firing if there's real speech
                try? await Task.sleep(nanoseconds: 600_000_000) // 600ms

                // Check if still in tentative pause (not already confirmed or cancelled)
                guard !Task.isCancelled && isTentativePause else { return }

                // If we get here without continued speech, it was a false positive - resume
                logger.info("Barge-in not confirmed - resuming playback")
                await resumeFromTentativePause()
            }
        }
    }

    /// Resume playback after a false-positive barge-in
    private func resumeFromTentativePause() async {
        guard isTentativePause else { return }

        logger.info("Resuming from tentative pause")
        isTentativePause = false

        // Resume audio playback
        _ = await audioEngine?.resumePlayback()

        // Return to aiSpeaking state
        await setState(.aiSpeaking)
    }

    /// Confirm barge-in as real - fully stop and switch to user speaking
    private func confirmBargeIn() async {
        logger.info("Barge-in confirmed - fully interrupting")

        // Cancel the confirmation timer
        bargeInConfirmationTask?.cancel()
        bargeInConfirmationTask = nil
        isTentativePause = false

        await telemetry.recordEvent(.userInterrupted)

        // Now fully stop everything
        ttsStreamTask?.cancel()
        llmStreamTask?.cancel()
        if let orch = ttsOrchestrator {
            await orch.stopPlayback()
        }
        await audioEngine?.stopPlayback()

        // Clear buffers if configured
        if config.audio.ttsClearOnInterrupt {
            try? await ttsService?.flush()
        }

        // Return to listening
        await setState(.userSpeaking)

        // Reset silence tracking for new utterance
        hasDetectedSpeech = false
        silenceStartTime = nil

        await MainActor.run {
            aiResponse = ""
        }
    }

    /// Legacy full interruption handler (called for confirmed speech during pause)
    private func handleInterruption() async {
        if isTentativePause {
            // We're already paused tentatively - confirm the barge-in
            await confirmBargeIn()
        } else {
            // Direct interruption without tentative pause
            logger.info("Direct interruption (no tentative pause)")
            await confirmBargeIn()
        }
    }
}

// MARK: - Session Feature Flag Keys

/// Feature flag keys used by SessionManager
private enum SessionFeatureFlagKeys {
    static let maintenanceMode = "ops_maintenance_mode"
}

// MARK: - Session Errors

public enum SessionError: Error, LocalizedError {
    case servicesNotConfigured
    case sessionAlreadyActive
    case sessionNotActive
    case maintenanceMode

    public var errorDescription: String? {
        switch self {
        case .servicesNotConfigured:
            return "Required services not configured"
        case .sessionAlreadyActive:
            return "Session is already active"
        case .sessionNotActive:
            return "No active session"
        case .maintenanceMode:
            return "System is in maintenance mode. Please try again later."
        }
    }
}

// MARK: - Session Sentence Segment

/// A single sentence extracted from the LLM stream, conforming to PlayableSegment
/// for use with AudioPlaybackOrchestrator.
struct SessionSentenceSegment: PlayableSegment {
    let segmentIndex: Int
    let segmentText: String
    let cachedAudio: CachedSegmentAudio? = nil

    init(index: Int, text: String) {
        self.segmentIndex = index
        self.segmentText = text
    }
}

// MARK: - Session Orchestrator Delegate

/// Bridges AudioPlaybackOrchestrator events back to SessionManager.
/// Marked @MainActor because SessionManager is @MainActor.
@MainActor
final class SessionOrchestratorDelegate: PlaybackOrchestratorDelegate {
    private weak var sessionManager: SessionManager?
    private let logger = Logger(label: "com.unamentis.session.orchestrator")

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    nonisolated func orchestratorDidComplete() async {
        await MainActor.run { [weak self] in
            guard let self, let manager = self.sessionManager else { return }
            Task {
                await manager.handleTTSPlaybackComplete()
            }
        }
    }

    nonisolated func orchestratorDidEncounterError(_ error: Error) async {
        let errorMsg = error.localizedDescription
        await MainActor.run { [weak self] in
            self?.logger.error("TTS orchestrator error: \(errorMsg)")
        }
    }
}
