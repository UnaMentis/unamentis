// VoiceLearn - Session Manager
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
        enableInterruptions: true
    )
    
    public init(
        audio: AudioEngineConfig = .default,
        llm: LLMConfig = .default,
        voice: TTSVoiceConfig = .default,
        systemPrompt: String = "",
        enableCostTracking: Bool = true,
        maxDuration: TimeInterval = 5400,
        enableInterruptions: Bool = true
    ) {
        self.audio = audio
        self.llm = llm
        self.voice = voice
        self.systemPrompt = systemPrompt
        self.enableCostTracking = enableCostTracking
        self.maxDuration = maxDuration
        self.enableInterruptions = enableInterruptions
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
    
    private let logger = Logger(label: "com.voicelearn.session")
    
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
    
    // MARK: - Initialization
    
    public init(
        config: SessionConfig = .default,
        telemetry: TelemetryEngine,
        curriculum: CurriculumEngine? = nil,
        persistenceController: PersistenceController = .shared
    ) {
        self.config = config
        self.telemetry = telemetry
        self.curriculum = curriculum
        self.persistenceController = persistenceController
        logger.info("SessionManager initialized")
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
        guard await state == .idle else {
            logger.warning("Cannot start session: not in idle state")
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

        // Configure TTS voice
        await ttsService.configure(config.voice)

        // Initialize conversation with system prompt (use override if provided)
        let effectiveSystemPrompt = systemPrompt ?? config.systemPrompt
        conversationHistory = [
            LLMMessage(role: .system, content: effectiveSystemPrompt)
        ]
        
        // Start telemetry session
        await telemetry.startSession()
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

        // Cancel all streaming tasks
        sttStreamTask?.cancel()
        llmStreamTask?.cancel()
        ttsStreamTask?.cancel()
        pendingUtteranceTask?.cancel()
        audioSubscription?.cancel()

        // Stop services
        await audioEngine?.stop()
        try? await sttService?.stopStreaming()

        // End telemetry
        await telemetry.endSession()

        // Persist session to Core Data before clearing state
        await persistSessionToStorage()

        // Clear state
        conversationHistory.removeAll()
        silenceStartTime = nil
        hasDetectedSpeech = false
        pendingUtteranceTask = nil
        await MainActor.run {
            userTranscript = ""
            aiResponse = ""
            audioLevel = -60.0
        }

        await setState(.idle)

        logger.info("Session stopped")
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
            // Check for interruption
            if config.enableInterruptions && result.isSpeech && result.confidence > config.audio.bargeInThreshold {
                await handleInterruption()
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
              let format = await audioEngine?.format else {
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

                    await MainActor.run {
                        self.aiResponse = fullResponse
                    }

                    // Stream text to TTS
                    // (In production, buffer sentences before TTS)

                    if token.isDone {
                        break
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

                // Synthesize and play TTS
                await self.synthesizeAndPlayResponse(fullResponse)
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
    
    // MARK: - TTS Handling
    
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
    
    private func handleInterruption() async {
        logger.info("Handling user interruption")
        
        await setState(.interrupted)
        await telemetry.recordEvent(.userInterrupted)
        
        // Cancel current TTS playback
        ttsStreamTask?.cancel()
        llmStreamTask?.cancel()
        await audioEngine?.stopPlayback()
        
        // Clear buffers if configured
        if config.audio.ttsClearOnInterrupt {
            try? await ttsService?.flush()
        }
        
        // Return to listening
        await setState(.userSpeaking)
        
        await MainActor.run {
            aiResponse = ""
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
