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
    case processingUserUtterance = "Processing Utterance"
    case error = "Error"
    
    /// Whether the session is actively running
    public var isActive: Bool {
        switch self {
        case .idle, .error:
            return false
        default:
            return true
        }
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
            You are a helpful AI tutor engaged in a voice conversation.
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
    private let silenceThreshold: TimeInterval = 1.5  // seconds of silence before completing utterance
    private var pendingUtteranceTask: Task<Void, Never>?

    /// Sentence-level TTS streaming
    private var ttsSentenceQueue: [String] = []
    private var isTTSPlaying: Bool = false
    private var sentenceBuffer: String = ""
    private var ttsQueueTask: Task<Void, Never>?
    private var isLLMStreamingComplete: Bool = false

    /// TTS Prefetching state
    private var prefetchedAudioCache: [String: TTSAudioChunk] = [:]  // sentence -> audio chunk
    private var prefetchTasks: [String: Task<TTSAudioChunk?, Never>] = [:]  // sentence -> prefetch task
    private var currentPrefetchCount: Int = 0
    
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
    
    /// Stop the current session
    public func stopSession() async {
        logger.info("Stopping session")

        // Cancel all streaming tasks first
        sttStreamTask?.cancel()
        sttStreamTask = nil
        llmStreamTask?.cancel()
        llmStreamTask = nil
        ttsStreamTask?.cancel()
        ttsStreamTask = nil
        ttsQueueTask?.cancel()
        ttsQueueTask = nil
        pendingUtteranceTask?.cancel()
        pendingUtteranceTask = nil
        audioSubscription?.cancel()
        audioSubscription = nil

        // Stop services
        await audioEngine?.stop()
        try? await sttService?.stopStreaming()

        // End telemetry and stop device metrics sampling
        await telemetry.stopDeviceMetricsSampling()
        await telemetry.endSession()

        // Persist session to Core Data before clearing state
        await persistSessionToStorage()

        // Clear all state
        conversationHistory.removeAll()
        silenceStartTime = nil
        hasDetectedSpeech = false
        ttsSentenceQueue.removeAll()
        sentenceBuffer = ""
        isTTSPlaying = false
        isLLMStreamingComplete = false

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

        await setState(.idle)

        logger.info("Session stopped - all services and state cleared")
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

    // MARK: - Utterance Processing

    private func processUserUtterance(_ transcript: String) async {
        logger.info("Processing user utterance: \(transcript.prefix(50))...")
        
        await setState(.processingUserUtterance)
        currentTurnStartTime = Date()
        
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
            logger.info("Calling LLM streamCompletion with \(conversationHistory.count) messages")
            let stream = try await llmService.streamCompletion(
                messages: conversationHistory,
                config: config.llm
            )

            var fullResponse = ""
            var isFirstToken = true

            // Reset sentence buffer and TTS queue for new response
            self.sentenceBuffer = ""
            self.ttsSentenceQueue = []
            self.isTTSPlaying = false

            // Start the TTS queue processor
            self.startTTSQueueProcessor()

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
                if !self.sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.ttsSentenceQueue.append(self.sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
                    self.sentenceBuffer = ""
                    logger.info("Queued final sentence fragment for TTS")
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

                // Signal that LLM streaming is complete - TTS queue processor will finish
                // when all sentences have been played
                self.isLLMStreamingComplete = true
                logger.info("LLM streaming complete - TTS queue will finish when all sentences played")

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
                    ttsSentenceQueue.append(sentence)
                    logger.info("🔊 Queued sentence for TTS (\(ttsSentenceQueue.count) in queue): \"\(sentence.prefix(50))...\"")

                    // Start prefetching this sentence immediately if not already being prefetched
                    // This ensures prefetch starts as soon as sentences are queued, not just when dequeued
                    if config.ttsPlayback.enablePrefetch && prefetchedAudioCache[sentence] == nil && prefetchTasks[sentence] == nil {
                        let sentenceToFetch = sentence
                        logger.info("🔊 Prefetch: Immediate prefetch for newly queued \"\(sentenceToFetch.prefix(30))...\"")
                        prefetchTasks[sentenceToFetch] = Task { [weak self] in
                            guard let self = self else { return nil }
                            let chunk = await self.prefetchSentence(sentenceToFetch)
                            if let chunk = chunk {
                                self.prefetchedAudioCache[sentenceToFetch] = chunk
                            }
                            return chunk
                        }
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

    /// Start the TTS queue processor that plays sentences as they're queued
    private func startTTSQueueProcessor() {
        ttsQueueTask?.cancel()
        isLLMStreamingComplete = false

        ttsQueueTask = Task {
            logger.info("🔊 TTS queue processor started")
            var isFirstSentence = true

            while !Task.isCancelled {
                // Wait for items in the queue
                if ttsSentenceQueue.isEmpty {
                    // Check if LLM is done AND we've finished all sentences
                    if isLLMStreamingComplete {
                        // Double-check the queue is still empty (might have been filled during last play)
                        if ttsSentenceQueue.isEmpty {
                            logger.info("🔊 LLM complete and queue empty, finishing TTS processor")
                            break
                        }
                    }
                    // Wait a bit for more sentences
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    continue
                }

                // Dequeue the next sentence
                let sentence = ttsSentenceQueue.removeFirst()
                logger.info("🔊 Processing TTS for: \"\(sentence.prefix(50))...\" (\(ttsSentenceQueue.count) remaining in queue)")

                // Start prefetching upcoming sentences while we play the current one
                startPrefetchingIfNeeded()

                // Record TTFB on first sentence
                if isFirstSentence {
                    isFirstSentence = false
                    if let turnStart = currentTurnStartTime {
                        let ttsTTFB = Date().timeIntervalSince(turnStart)
                        await telemetry.recordLatency(.ttsTTFB, ttsTTFB)
                        logger.info("🔊 TTS TTFB (first sentence queued): \(String(format: "%.3f", ttsTTFB))s")
                    }
                }

                // Synthesize and play this sentence - WAIT for it to complete before getting next
                isTTSPlaying = true
                await synthesizeAndPlaySentence(sentence)
                isTTSPlaying = false
                logger.info("🔊 Finished playing sentence")
            }

            logger.info("🔊 TTS queue processor finished - all sentences played")

            // Clear prefetch state
            clearPrefetchState()

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
            // This prevents echo/feedback from the just-finished TTS being picked up as user speech
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
    }

    /// Prefetch TTS audio for a sentence (does not play, just caches)
    private func prefetchSentence(_ text: String) async -> TTSAudioChunk? {
        guard let ttsService = ttsService else {
            logger.warning("🔊 Prefetch: TTS service is nil")
            return nil
        }

        logger.info("🔊 Prefetch: Starting for \"\(text.prefix(30))...\"")
        let startTime = Date()

        do {
            let stream = try await ttsService.synthesize(text: text)
            for await chunk in stream {
                if chunk.isLast {
                    let elapsed = Date().timeIntervalSince(startTime)
                    logger.info("🔊 Prefetch: Completed in \(String(format: "%.3f", elapsed))s for \"\(text.prefix(30))...\"")
                    return chunk  // Return the full audio chunk
                }
            }
        } catch {
            logger.error("🔊 Prefetch: Failed for \"\(text.prefix(30))...\": \(error.localizedDescription)")
        }
        return nil
    }

    /// Start prefetching for upcoming sentences in the queue
    private func startPrefetchingIfNeeded() {
        guard config.ttsPlayback.enablePrefetch else { return }

        let maxPrefetch = config.ttsPlayback.prefetchQueueDepth
        // Prefetch the next N sentences in the queue (the current one is already being played)
        let sentencesToPrefetch = Array(ttsSentenceQueue.prefix(maxPrefetch))

        for sentence in sentencesToPrefetch {
            // Skip if already cached or being prefetched
            if prefetchedAudioCache[sentence] != nil || prefetchTasks[sentence] != nil {
                continue
            }

            // Start prefetch task - capture sentence for the closure
            let sentenceToFetch = sentence
            logger.info("🔊 Prefetch: Queueing prefetch for \"\(sentenceToFetch.prefix(30))...\"")
            prefetchTasks[sentenceToFetch] = Task { [weak self] in
                guard let self = self else { return nil }
                let chunk = await self.prefetchSentence(sentenceToFetch)
                // Cache the result when done - store directly in actor's cache
                if let chunk = chunk {
                    self.prefetchedAudioCache[sentenceToFetch] = chunk
                }
                return chunk
            }
        }
    }

    /// Clear prefetch state (call when stopping session or after AI finishes)
    private func clearPrefetchState() {
        // Cancel any pending prefetch tasks
        for (_, task) in prefetchTasks {
            task.cancel()
        }
        prefetchTasks.removeAll()
        prefetchedAudioCache.removeAll()
        currentPrefetchCount = 0
    }

    /// Synthesize and play a single sentence (uses prefetched audio if available)
    private func synthesizeAndPlaySentence(_ text: String) async {
        guard let ttsService = ttsService else {
            logger.error("TTS service is nil - cannot synthesize sentence")
            return
        }

        // Check if we have prefetched audio for this sentence
        if let cachedChunk = prefetchedAudioCache[text] {
            logger.info("🔊 Using prefetched audio for \"\(text.prefix(30))...\"")
            prefetchedAudioCache.removeValue(forKey: text)
            prefetchTasks.removeValue(forKey: text)

            if let audioEngine = audioEngine {
                do {
                    try await audioEngine.playAudio(cachedChunk)
                } catch {
                    logger.error("Failed to play prefetched audio: \(error.localizedDescription)")
                }
            }

            // Add inter-sentence silence if configured
            if config.ttsPlayback.interSentenceSilenceMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(config.ttsPlayback.interSentenceSilenceMs) * 1_000_000)
            }
            return
        }

        // Wait for prefetch task if it's in progress
        if let prefetchTask = prefetchTasks[text] {
            logger.info("🔊 Waiting for in-progress prefetch for \"\(text.prefix(30))...\"")
            if let chunk = await prefetchTask.value {
                prefetchedAudioCache.removeValue(forKey: text)
                prefetchTasks.removeValue(forKey: text)

                if let audioEngine = audioEngine {
                    do {
                        try await audioEngine.playAudio(chunk)
                    } catch {
                        logger.error("Failed to play prefetched audio: \(error.localizedDescription)")
                    }
                }

                // Add inter-sentence silence if configured
                if config.ttsPlayback.interSentenceSilenceMs > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(config.ttsPlayback.interSentenceSilenceMs) * 1_000_000)
                }
                return
            }
        }

        // No cached audio - synthesize and play directly (fallback)
        logger.info("🔊 No prefetch available, synthesizing directly for \"\(text.prefix(30))...\"")
        do {
            let stream = try await ttsService.synthesize(text: text)

            for await chunk in stream {
                if let audioEngine = audioEngine {
                    try await audioEngine.playAudio(chunk)
                }

                if chunk.isLast {
                    break
                }
            }
        } catch {
            logger.error("Failed to synthesize sentence: \(error.localizedDescription)")
        }

        // Add inter-sentence silence if configured
        if config.ttsPlayback.interSentenceSilenceMs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(config.ttsPlayback.interSentenceSilenceMs) * 1_000_000)
        }
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
        ttsQueueTask?.cancel()
        await audioEngine?.stopPlayback()

        // Clear TTS queue and prefetch cache
        ttsSentenceQueue.removeAll()
        clearPrefetchState()

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

// MARK: - Session Errors

public enum SessionError: Error, LocalizedError {
    case servicesNotConfigured
    case sessionAlreadyActive
    case sessionNotActive
    
    public var errorDescription: String? {
        switch self {
        case .servicesNotConfigured:
            return "Required services not configured"
        case .sessionAlreadyActive:
            return "Session is already active"
        case .sessionNotActive:
            return "No active session"
        }
    }
}
