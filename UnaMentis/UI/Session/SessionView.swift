// UnaMentis - Session View
// Main voice conversation UI
//
// Part of UI/UX (TDD Section 10)

import SwiftUI
import Combine
import Logging
import AVFoundation

#if os(macOS)
import AppKit
#endif

/// Main session view for voice conversations
public struct SessionView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionActivityState: SessionActivityState
    @StateObject private var viewModel: SessionViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingSessionHelp = false

    private static let logger = Logger(label: "com.unamentis.session.view")

    /// The topic being studied (optional - for curriculum-based sessions)
    let topic: Topic?

    /// Whether to auto-start the session (for Siri-triggered freeform chat)
    let autoStart: Bool

    #if os(iOS)
    private static let backgroundGradientColors: [Color] = [Color(.systemBackground), Color(.systemGray6)]
    #else
    private static let backgroundGradientColors: [Color] = [Color(NSColor.windowBackgroundColor), Color(NSColor.controlBackgroundColor)]
    #endif

    /// Whether to show side panel for visuals (iPad with curriculum)
    private var showSidePanel: Bool {
        horizontalSizeClass == .regular && topic != nil && viewModel.isDirectStreamingMode
    }

    public init(topic: Topic? = nil, autoStart: Bool = false) {
        Self.logger.info("SessionView init() called - topic=\(topic?.title ?? "nil"), autoStart=\(autoStart)")
        self.topic = topic
        self.autoStart = autoStart
        // Initialize viewModel with topic context
        _viewModel = StateObject(wrappedValue: SessionViewModel(topic: topic))
    }

    public var body: some View {
        // NOTE: Removed debug logging from view body to prevent side effects
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background gradient
                LinearGradient(
                    colors: Self.backgroundGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    // Topic progress bar - only for curriculum sessions
                    if topic != nil && viewModel.totalSegments > 0 {
                        TopicProgressBar(
                            completedSegments: viewModel.completedSegmentCount,
                            totalSegments: viewModel.totalSegments
                        )
                        .padding(.top, 8)
                    }

                    // Status indicator
                    SessionStatusView(state: viewModel.state)
                        .padding(.top, topic != nil ? 4 : 12)

                    // Transcript display with visual overlay - takes most of the space
                    // On iPad: side-by-side layout (transcript left, visuals right)
                    // On iPhone: overlay at bottom
                    if showSidePanel {
                        // iPad layout: transcript and visual panel side by side
                        HStack(spacing: 16) {
                            // Transcript on the left
                            TranscriptView(
                                conversationHistory: viewModel.conversationHistory,
                                userTranscript: viewModel.userTranscript,
                                aiResponse: viewModel.aiResponse,
                                highlightedMessageId: viewModel.highlightedMessageId
                            )
                            .frame(maxWidth: .infinity)

                            // Visual panel on the right
                            VisualAssetSidePanel(
                                currentSegment: viewModel.currentSegmentIndex,
                                topic: topic
                            )
                            .frame(width: 340)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        // iPhone layout: overlay at bottom
                        ZStack(alignment: .bottom) {
                            TranscriptView(
                                conversationHistory: viewModel.conversationHistory,
                                userTranscript: viewModel.userTranscript,
                                aiResponse: viewModel.aiResponse,
                                highlightedMessageId: viewModel.highlightedMessageId
                            )

                            // Visual asset overlay - shows synchronized visuals during curriculum playback
                            if topic != nil && viewModel.isDirectStreamingMode {
                                VisualAssetOverlay(
                                    currentSegment: viewModel.currentSegmentIndex,
                                    topic: topic,
                                    isExpanded: $viewModel.visualsExpanded
                                )
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }

                    // Spacer for bottom controls when not in session (controls are inside content flow)
                    // When session active, controls float at bottom via ZStack overlay
                    if !viewModel.isSessionActive {
                        SessionControlButton(
                            isActive: viewModel.isSessionActive,
                            isLoading: viewModel.isLoading,
                            action: {
                                await viewModel.toggleSession(appState: appState)
                            }
                        )
                        .padding(.bottom, 20)
                    }
                }
                .padding(.horizontal, 20)
                // Add bottom padding when session active so transcript doesn't go behind controls
                .padding(.bottom, viewModel.isSessionActive ? 140 : 0)

                // Bottom control area - positioned at tab bar location when session is active
                if viewModel.isSessionActive {
                    VStack {
                        Spacer()
                        VStack(spacing: 12) {
                            // VU meter - visible when session active
                            // Color scheme: Blue for AI speaking, Green for user speaking
                            AudioLevelView(level: viewModel.audioLevel, state: viewModel.state)
                                .frame(height: 40)
                                .transition(.opacity.combined(with: .scale))

                            if viewModel.showCurriculumControls {
                                // Curriculum playback controls with segment navigation
                                CurriculumPlaybackControls(
                                    isPaused: $viewModel.isPaused,
                                    isMuted: $viewModel.isMuted,
                                    currentSegmentIndex: viewModel.currentSegmentIndex,
                                    hasNextTopic: viewModel.hasNextTopic,
                                    nextTopicTitle: viewModel.nextTopicTitle,
                                    onPauseResume: {
                                        if viewModel.isPaused {
                                            viewModel.resumePlayback()
                                        } else {
                                            viewModel.pausePlayback()
                                        }
                                    },
                                    onStop: {
                                        viewModel.stopPlayback()
                                    },
                                    onGoBack: {
                                        viewModel.goBackOneSegment()
                                    },
                                    onReplay: {
                                        viewModel.replayCurrentTopic()
                                    },
                                    onNextTopic: {
                                        viewModel.skipToNextTopic()
                                    },
                                    onMuteChanged: { muted in
                                        viewModel.setMicrophoneMuted(muted)
                                    }
                                )
                            } else {
                                // Stop button for regular conversation mode
                                SessionControlButton(
                                    isActive: viewModel.isSessionActive,
                                    isLoading: viewModel.isLoading,
                                    action: {
                                        await viewModel.toggleSession(appState: appState)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34) // Match tab bar's bottom padding for home indicator
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: viewModel.isSessionActive)
                    .animation(.spring(response: 0.3), value: viewModel.isDirectStreamingMode)
                }
            }
            .navigationTitle(topic?.title ?? "Voice Session")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showingSessionHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel("Session help")
                        .accessibilityHint("Learn how to use voice conversations")

                        Button {
                            viewModel.showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("Session settings")
                        .accessibilityHint("Configure audio and AI settings")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isSessionActive {
                        MetricsBadge(
                            latency: viewModel.lastLatency,
                            cost: viewModel.sessionCost
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Session metrics")
                        .accessibilityValue("Latency \(Int(viewModel.lastLatency * 1000)) milliseconds, Cost \(String(format: "$%.3f", NSDecimalNumber(decimal: viewModel.sessionCost).doubleValue))")
                    } else {
                        BrandLogo(size: .compact)
                    }
                }
            }
            #endif
            .sheet(isPresented: $showingSessionHelp) {
                SessionHelpSheet()
            }
            .sheet(isPresented: $viewModel.showSettings) {
                NavigationStack {
                    VoiceSettingsView(showDoneButton: true)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { viewModel.showError = false }
            } message: {
                Text(viewModel.errorMessage)
            }
            .task {
                // Auto-start session when:
                // 1. Initiated from a topic (lecture mode)
                // 2. Triggered via Siri for freeform chat (autoStart = true)
                let shouldAutoStart = (topic != nil || autoStart)
                if shouldAutoStart && !viewModel.isSessionActive && !viewModel.isLoading {
                    Self.logger.info("SessionView .task auto-starting session")
                    await viewModel.toggleSession(appState: appState)
                }
            }
            // Update session activity state for tab bar visibility
            // Using setter methods with built-in change guards to prevent re-render loops
            .onChange(of: viewModel.isSessionActive) { _, newValue in
                sessionActivityState.setSessionActive(newValue)
            }
            .onChange(of: viewModel.isPaused) { _, newValue in
                sessionActivityState.setPaused(newValue)
            }
            .onDisappear {
                // Reset session activity state when view disappears
                sessionActivityState.reset()
            }
        }
    }
}

// MARK: - Topic Progress Bar

/// Minimal progress bar showing how far through a topic session the user is
struct TopicProgressBar: View {
    let completedSegments: Int
    let totalSegments: Int

    private var progress: Double {
        guard totalSegments > 0 else { return 0 }
        return Double(completedSegments) / Double(totalSegments)
    }

    private var progressPercentage: Int {
        Int(progress * 100)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 4)

            // Progress text (minimal)
            HStack {
                Spacer()
                Text("\(completedSegments)/\(totalSegments)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lesson progress")
        .accessibilityValue("\(completedSegments) of \(totalSegments) segments completed, \(progressPercentage) percent")
        .accessibilityHint("Shows your progress through the current lesson")
    }
}

// MARK: - Session Status View

struct SessionStatusView: View {
    let state: SessionState

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay {
                    if state.isActive {
                        Circle()
                            .stroke(statusColor.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.7)
                    }
                }

            Text(state.rawValue)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session status")
        .accessibilityValue(statusAccessibilityDescription)
    }

    private var statusColor: Color {
        switch state {
        case .idle: return .gray
        case .userSpeaking: return .green
        case .aiThinking: return .orange
        case .aiSpeaking: return .blue
        case .interrupted: return .yellow
        case .paused: return .cyan
        case .processingUserUtterance: return .purple
        case .error: return .red
        }
    }

    private var statusAccessibilityDescription: String {
        switch state {
        case .idle:
            return "Idle. Ready to start a conversation."
        case .userSpeaking:
            return "Listening. Speak now, you are being heard."
        case .aiThinking:
            return "Processing. The AI is preparing a response."
        case .aiSpeaking:
            return "Speaking. The AI tutor is responding."
        case .interrupted:
            return "Interrupted. The AI paused to listen to you."
        case .paused:
            return "Paused. Session is paused, tap play to resume."
        case .processingUserUtterance:
            return "Processing your speech."
        case .error:
            return "Error occurred."
        }
    }
}

// MARK: - Transcript View

struct TranscriptView: View {
    let conversationHistory: [ConversationMessage]
    let userTranscript: String
    let aiResponse: String

    /// ID of the currently playing message for highlighting and scrolling
    var highlightedMessageId: UUID?

    /// Check if user transcript is already in history (to avoid duplication)
    private var isUserTranscriptInHistory: Bool {
        guard !userTranscript.isEmpty else { return false }
        // Check if the last user message in history matches current transcript
        if let lastUserMessage = conversationHistory.last(where: { $0.isUser }) {
            return lastUserMessage.text == userTranscript
        }
        return false
    }

    /// Check if AI response is already in history (to avoid duplication)
    private var isAIResponseInHistory: Bool {
        guard !aiResponse.isEmpty else { return false }
        // Check if the last AI message in history matches current response
        if let lastAIMessage = conversationHistory.last(where: { !$0.isUser }) {
            return lastAIMessage.text == aiResponse
        }
        return false
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Show full conversation history
                    ForEach(conversationHistory) { message in
                        TranscriptBubble(
                            text: message.text,
                            isUser: message.isUser,
                            isHighlighted: message.id == highlightedMessageId
                        )
                        .id(message.id)
                    }

                    // Show current in-progress messages (only if not already in history)
                    if !userTranscript.isEmpty && !isUserTranscriptInHistory {
                        TranscriptBubble(
                            text: userTranscript,
                            isUser: true
                        )
                        .id("currentUser")
                    }

                    if !aiResponse.isEmpty && !isAIResponseInHistory {
                        TranscriptBubble(
                            text: aiResponse,
                            isUser: false
                        )
                        .id("currentAI")
                    }

                    // Invisible anchor for auto-scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .onChange(of: conversationHistory.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: aiResponse) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: userTranscript) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: highlightedMessageId) { _, newId in
                // Scroll to highlighted message when segment navigation occurs
                if let id = newId {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }
}

struct TranscriptBubble: View {
    let text: String
    let isUser: Bool
    var isHighlighted: Bool = false

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            Text(text)
                .font(.subheadline)  // Smaller font for better transcript density
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        #if os(iOS)
                        .fill(isUser ? Color.blue : (isHighlighted ? Color.blue.opacity(0.2) : Color(.systemGray5)))
                        #else
                        .fill(isUser ? Color.blue : (isHighlighted ? Color.blue.opacity(0.2) : Color(NSColor.controlBackgroundColor)))
                        #endif
                }
                .foregroundStyle(isUser ? .white : .primary)
                .overlay {
                    if isHighlighted && !isUser {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.blue.opacity(0.5), lineWidth: 2)
                    }
                }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Audio Level View

struct AudioLevelView: View {
    let level: Float
    let state: SessionState

    private let barCount = 20

    /// Whether this is showing AI audio (blue tones) vs user audio (green tones)
    private var isAIAudio: Bool {
        state == .aiSpeaking || state == .aiThinking
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 8)
                    .scaleEffect(y: barScale(for: index), anchor: .bottom)
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel("Audio level meter")
        .accessibilityValue(accessibilityDescription)
        .accessibilityHint(isAIAudio ? "Shows AI speech volume" : "Shows your voice volume")
    }

    private var accessibilityDescription: String {
        let normalizedLevel = max(0, min(1, (level + 60) / 60))
        let percentage = Int(normalizedLevel * 100)
        let source = isAIAudio ? "AI" : "Your voice"
        return "\(source) at \(percentage) percent"
    }

    private func barScale(for index: Int) -> CGFloat {
        // Convert dB to 0-1 range (-60dB to 0dB)
        let normalizedLevel = max(0, min(1, (level + 60) / 60))
        let threshold = Float(index) / Float(barCount)
        return normalizedLevel > threshold ? 1.0 : 0.2
    }

    private func barColor(for index: Int) -> Color {
        let ratio = Float(index) / Float(barCount)

        if isAIAudio {
            // AI speaking: Blue color scheme
            if ratio < 0.6 {
                return .blue
            } else if ratio < 0.8 {
                return .cyan
            } else {
                return .purple
            }
        } else {
            // User speaking: Green color scheme
            if ratio < 0.6 {
                return .green
            } else if ratio < 0.8 {
                return .yellow
            } else {
                return .red
            }
        }
    }
}

// MARK: - Session Control Button

struct SessionControlButton: View {
    let isActive: Bool
    let isLoading: Bool
    let action: () async -> Void

    /// Button size: large (80pt) when inactive, smaller (50pt) when recording
    private var buttonSize: CGFloat {
        isActive ? 50 : 80
    }

    /// Icon size: scales with button
    private var iconSize: CGFloat {
        isActive ? 20 : 32
    }

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isActive ? Color.red : Color.blue)
                    .frame(width: buttonSize, height: buttonSize)
                    .shadow(color: (isActive ? Color.red : Color.blue).opacity(0.4), radius: isActive ? 6 : 10)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: isActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: iconSize))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isLoading)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        .accessibilityLabel(isLoading ? "Loading" : (isActive ? "Stop session" : "Start session"))
        .accessibilityHint(isActive ? "Double-tap to end the conversation" : "Double-tap to begin a voice conversation")
    }
}

// MARK: - Curriculum Playback Controls

/// Controls for curriculum playback mode with segment navigation.
/// Uses CurriculumControlBar for full navigation capabilities (go-back, replay, next topic).
@MainActor
struct CurriculumPlaybackControls: View {
    /// Whether the session is paused
    @Binding var isPaused: Bool

    /// Whether the microphone is muted
    @Binding var isMuted: Bool

    /// Current segment index (for enabling go-back button)
    var currentSegmentIndex: Int = 0

    /// Whether there is a next topic available
    var hasNextTopic: Bool = false

    /// Title of the next topic (for accessibility)
    var nextTopicTitle: String?

    /// Callback when pause/resume is toggled
    let onPauseResume: @MainActor () -> Void

    /// Callback when stop action completes
    let onStop: @MainActor () -> Void

    /// Callback when go-back button is tapped
    var onGoBack: (@MainActor () -> Void)?

    /// Callback when replay button is tapped
    var onReplay: (@MainActor () -> Void)?

    /// Callback when next topic button is tapped
    var onNextTopic: (@MainActor () -> Void)?

    /// Optional callback when mute changes
    var onMuteChanged: (@MainActor (Bool) -> Void)?

    var body: some View {
        CurriculumControlBar(
            isPaused: $isPaused,
            isMuted: $isMuted,
            currentSegmentIndex: currentSegmentIndex,
            hasNextTopic: hasNextTopic,
            nextTopicTitle: nextTopicTitle,
            onStop: onStop,
            onGoBack: { [onGoBack] in onGoBack?() },
            onReplay: { [onReplay] in onReplay?() },
            onNextTopic: { [onNextTopic] in onNextTopic?() },
            onPauseChanged: { [onPauseResume] _ in
                onPauseResume()
            },
            onMuteChanged: onMuteChanged
        )
    }
}

/// Legacy interface for backward compatibility
extension CurriculumPlaybackControls {
    /// Initializer for backward compatibility with existing code that uses closures
    init(
        isPaused: Bool,
        onPauseResume: @escaping @MainActor () -> Void,
        onStop: @escaping @MainActor () -> Void
    ) {
        self._isPaused = .constant(isPaused)
        self._isMuted = .constant(false)
        self.onPauseResume = onPauseResume
        self.onStop = onStop
        self.onMuteChanged = nil
        self.onGoBack = nil
        self.onReplay = nil
        self.onNextTopic = nil
    }
}

// MARK: - Metrics Badge

struct MetricsBadge: View {
    let latency: TimeInterval
    let cost: Decimal

    var body: some View {
        HStack(spacing: 8) {
            // Latency
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.caption2)
                Text(String(format: "%.0fms", latency * 1000))
                    .font(.caption.monospacedDigit())
            }

            // Cost
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption2)
                Text(String(format: "$%.3f", NSDecimalNumber(decimal: cost).doubleValue))
                    .font(.caption.monospacedDigit())
            }
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Conversation Message Model

/// A single message in the conversation history
struct ConversationMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
}

// MARK: - Audio Player Delegate

/// Wrapper to make AVAudioPCMBuffer usable across actor boundaries
/// This is safe because we only use it for passing buffers to STT services
private struct SendableAudioBufferWrapper: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Delegate to handle audio playback completion for sequential segment playback
final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

// MARK: - Session View Model

@MainActor
class SessionViewModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var userTranscript: String = ""
    @Published var aiResponse: String = ""
    @Published var audioLevel: Float = -60
    @Published var isLoading: Bool = false
    @Published var showSettings: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var lastLatency: TimeInterval = 0
    @Published var sessionCost: Decimal = 0
    @Published var debugTestResult: String = ""

    /// Full conversation history for display
    @Published var conversationHistory: [ConversationMessage] = []

    /// ID of the currently playing message for transcript highlighting
    @Published var highlightedMessageId: UUID?

    /// UMCF transcript data for this topic (if available)
    @Published var umcfTranscript: TopicTranscriptResponse?
    @Published var currentSegmentIndex: Int = 0

    /// Track last known transcripts to detect changes
    private var lastUserTranscript: String = ""
    private var lastAiResponse: String = ""

    private let logger = Logger(label: "com.unamentis.session.viewmodel")
    private var sessionManager: SessionManager?
    private var subscribers = Set<AnyCancellable>()

    // MARK: - Watch Connectivity

    /// Subscribers for Watch state sync
    private var watchSyncCancellables = Set<AnyCancellable>()

    /// Transcript streaming service for direct TTS playback (bypasses LLM)
    private let transcriptStreamer = TranscriptStreamingService()

    // MARK: - Barge-In Support for Direct Streaming Mode

    /// Audio engine for microphone monitoring during direct streaming (barge-in detection)
    private var bargeInAudioEngine: AudioEngine?

    /// VAD service for barge-in detection
    private var bargeInVADService: SileroVADService?

    /// STT service for transcribing user speech during barge-in
    private var bargeInSTTService: (any STTService)?

    /// LLM service for handling barge-in questions
    private var bargeInLLMService: (any LLMService)?

    /// TTS service for speaking barge-in AI responses
    private var bargeInTTSService: (any TTSService)?

    /// Barge-in confirmation timer (600ms window to confirm real speech vs noise)
    private var bargeInConfirmationTask: Task<Void, Never>?

    /// Whether we're in tentative barge-in state (paused, waiting for confirmation)
    @Published var isTentativeBargeIn: Bool = false

    /// Barge-in threshold (higher = less sensitive, fewer false positives)
    private let bargeInThreshold: Float = 0.7

    /// Barge-in confirmation window in seconds
    private let bargeInConfirmationWindow: TimeInterval = 0.6

    /// Minimum silence duration to consider end of utterance (seconds)
    private let endOfUtteranceSilenceDuration: TimeInterval = 1.0

    /// Timestamp when silence started (for end-of-utterance detection)
    private var silenceStartTime: Date?

    /// Whether we've detected any speech during confirmed barge-in
    private var hasDetectedSpeechInBargeIn: Bool = false

    /// Audio buffers collected during barge-in for STT processing
    private var bargeInAudioBuffers: [AVAudioPCMBuffer] = []

    /// Segment index where we paused for barge-in (to resume from)
    private var bargeInPauseSegmentIndex: Int = 0

    /// Position in current segment's audio where we paused
    private var bargeInPauseTime: TimeInterval = 0

    /// Audio player for direct transcript playback
    private var audioPlayer: AVAudioPlayer?

    /// Audio queue for sequential playback of transcript segments.
    ///
    /// **DESIGN PRINCIPLE: Synchronized Text/Audio Display**
    ///
    /// Text is ONLY displayed when its corresponding audio starts playing.
    /// This prevents the jarring UX of seeing 4-6 paragraphs appear at once.
    /// The experience should feel "live" - as if the AI is speaking in real-time.
    ///
    /// Flow:
    /// 1. Server sends text → buffered in `pendingTextSegments`
    /// 2. Server sends audio → combined with buffered text, queued here
    /// 3. `playNextAudioSegment()` → displays text AND starts audio together
    ///
    /// See docs/CURRICULUM_SESSION_UX.md for full design documentation.
    private var audioQueue: [(audio: Data, text: String, index: Int)] = []

    // MARK: - Audio Segment Caching (for replay/rewind)

    /// Cache of audio segments for instant replay and segment navigation
    private let audioSegmentCache = AudioSegmentCache()

    // MARK: - Auto-Continue to Next Topic

    /// User preference for auto-continuing to next topic
    @AppStorage("autoContinueTopics") private var autoContinueTopics: Bool = true

    /// Pre-fetched audio queue for the next topic (for seamless transition)
    private var nextTopicAudioQueue: [(audio: Data, text: String, index: Int)] = []

    /// Pending text segments for the next topic
    private var nextTopicPendingText: [Int: String] = [:]

    /// Total segments in the pre-generated next topic
    private var nextTopicTotalSegments: Int = 0

    /// The topic being pre-generated (if any)
    private var preGeneratedNextTopic: Topic?

    /// Whether we're currently pre-generating the next topic
    private var isPreGeneratingNextTopic: Bool = false

    /// Whether audio is currently playing
    @Published private(set) var isPlayingAudio: Bool = false

    /// Audio player delegate for handling playback completion
    private var audioDelegate: AudioPlayerDelegate?

    /// Player for transition announcements (retained to prevent deallocation during playback)
    private var announcementPlayer: AVAudioPlayer?

    /// Timer for updating audio level from playback metering
    private var audioMeteringTimer: Timer?

    /// Whether we're using direct transcript streaming (bypasses LLM)
    @Published var isDirectStreamingMode: Bool = false {
        didSet {
            logger.info("🎬 isDirectStreamingMode changed: \(oldValue) -> \(isDirectStreamingMode)")
        }
    }

    /// Whether playback is paused (for curriculum mode)
    @Published var isPaused: Bool = false

    /// Whether the visual asset overlay is expanded
    @Published var visualsExpanded: Bool = true

    /// Whether the microphone is muted (prevents barge-in and speech detection)
    @Published var isMuted: Bool = false

    /// Whether curriculum controls should be shown
    /// This is true when we have a topic AND the AI is speaking (curriculum playback mode)
    var showCurriculumControls: Bool {
        guard topic != nil else { return false }
        // Show curriculum controls when AI is speaking or thinking in a topic-based session
        return state == .aiSpeaking || state == .aiThinking
    }

    /// Whether there is a next topic in the curriculum
    var hasNextTopic: Bool {
        guard let currentTopic = topic,
              let curriculum = currentTopic.curriculum,
              let topicsArray = curriculum.topics?.array as? [Topic] else { return false }
        let sortedTopics = topicsArray.sorted { ($0.orderIndex) < ($1.orderIndex) }
        guard let currentIndex = sortedTopics.firstIndex(where: { $0.id == currentTopic.id }) else { return false }
        return currentIndex + 1 < sortedTopics.count
    }

    /// Title of the next topic (for accessibility)
    var nextTopicTitle: String? {
        guard let currentTopic = topic,
              let curriculum = currentTopic.curriculum,
              let topicsArray = curriculum.topics?.array as? [Topic] else { return nil }
        let sortedTopics = topicsArray.sorted { ($0.orderIndex) < ($1.orderIndex) }
        guard let currentIndex = sortedTopics.firstIndex(where: { $0.id == currentTopic.id }),
              currentIndex + 1 < sortedTopics.count else { return nil }
        return sortedTopics[currentIndex + 1].title
    }

    /// Pending text segments waiting for audio (keyed by segment index).
    /// Text is buffered here until its audio arrives, then both are displayed together.
    /// See `audioQueue` documentation for the full synchronization design.
    private var pendingTextSegments: [Int: String] = [:]

    /// Total segments for progress tracking
    @Published var totalSegments: Int = 0

    /// Completed segment count for progress tracking
    @Published var completedSegmentCount: Int = 0

    /// Session start time for duration tracking
    private var sessionStartTime: Date?

    /// Topic for curriculum-based sessions (mutable to allow in-place topic transitions)
    private(set) var topic: Topic?

    /// Whether this is a lecture mode session (AI speaks first)
    var isLectureMode: Bool {
        topic != nil
    }

    /// Whether we have UMCF transcript data to use
    var hasTranscript: Bool {
        umcfTranscript?.segments.isEmpty == false
    }

    init(topic: Topic? = nil) {
        self.topic = topic
        logger.info("SessionViewModel init() START - topic=\(topic?.title ?? "nil")")

        // If we have a topic, try to load transcript data
        // NOTE: This Task spawns async work from init() - potential MainActor contention
        if topic != nil {
            logger.info("SessionViewModel init() spawning Task for loadTranscriptData")
            Task { await loadTranscriptData() }
        }
        logger.info("SessionViewModel init() COMPLETE")
    }

    /// Load transcript data from local Core Data or fetch from server
    private func loadTranscriptData() async {
        logger.info("loadTranscriptData() START")
        guard let topic = topic,
              let topicId = topic.id else {
            logger.info("loadTranscriptData() SKIPPED - no topic or topicId")
            return
        }
        logger.info("loadTranscriptData() checking for local transcript")

        // First, try to get transcript from local Core Data (document with transcript type)
        if let document = topic.documentSet.first(where: { $0.documentType == .transcript }),
           let transcriptData = document.decodedTranscript() {
            // Convert local TranscriptData to TopicTranscriptResponse format
            umcfTranscript = TopicTranscriptResponse(
                topicId: topicId.uuidString,
                topicTitle: topic.title,
                segments: transcriptData.segments.map { segment in
                    TranscriptSegmentInfo(
                        id: segment.id,
                        type: segment.type,
                        content: segment.content,
                        speakingNotes: segment.speakingNotes.map { notes in
                            SpeakingNotesInfo(
                                pace: notes.pace,
                                emotionalTone: notes.emotionalTone,
                                pauseAfter: notes.pauseAfter
                            )
                        },
                        checkpoint: segment.checkpointQuestion.map { q in
                            CheckpointInfo(type: "question", question: q)
                        }
                    )
                }
            )
            logger.info("Loaded transcript from local Core Data: \(transcriptData.segments.count) segments")
            return
        }

        // If no local transcript, try to fetch from server
        if let curriculum = topic.curriculum,
           let curriculumId = curriculum.id {
            do {
                // Configure service using server IP from UserDefaults
                let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
                let host = serverIP.isEmpty ? "localhost" : serverIP
                try await CurriculumService.shared.configure(host: host, port: 8766)

                umcfTranscript = try await CurriculumService.shared.fetchTopicTranscript(
                    curriculumId: curriculumId.uuidString,
                    topicId: topicId.uuidString
                )
                logger.info("Fetched transcript from server: \(umcfTranscript?.segments.count ?? 0) segments")
            } catch {
                logger.warning("Could not fetch transcript from server: \(error)")
                // Not fatal - we'll fall back to AI-generated content
            }
        }
    }

    /// Generate system prompt based on topic and depth level
    func generateSystemPrompt() -> String {
        guard let topic = topic else {
            // Default conversational system prompt
            return """
            You are a helpful educational assistant in a voice conversation.
            Keep responses concise and natural for spoken delivery.
            Avoid visual references, code blocks, or complex formatting.
            """
        }

        let topicTitle = topic.title ?? "the topic"
        let depth = topic.depthLevel
        let objectives = topic.objectives ?? []

        // If we have UMCF transcript data, use it as the primary source
        if let transcript = umcfTranscript, !transcript.segments.isEmpty {
            return generateTranscriptBasedPrompt(topic: topic, transcript: transcript)
        }

        // Otherwise, fall back to AI-generated content
        var prompt = """
        You are an expert lecturer delivering an audio-only educational lecture.

        TOPIC: \(topicTitle)
        DEPTH LEVEL: \(depth.displayName)

        \(depth.aiInstructions)

        AUDIO-FRIENDLY GUIDELINES:
        - This is an audio-only format. The learner cannot see any visual content.
        - Never reference diagrams, images, code blocks, or written equations.
        - \(depth.mathPresentationStyle)
        - Use natural spoken language, not written/academic style.
        - Speak clearly and at a measured pace.
        - Use verbal signposting: "First...", "Next...", "To summarize..."
        - Pause briefly between major sections.
        """

        if !objectives.isEmpty {
            prompt += "\n\nLEARNING OBJECTIVES:\n"
            for (index, objective) in objectives.enumerated() {
                prompt += "  \(index + 1). \(objective)\n"
            }
            prompt += "\nEnsure the lecture covers these objectives."
        }

        if let outline = topic.outline, !outline.isEmpty {
            prompt += "\n\nTOPIC OUTLINE:\n\(outline)"
        }

        prompt += """


        BEGIN THE LECTURE:
        Start speaking now. Introduce the topic naturally and begin teaching.
        The learner is listening and ready to learn.
        """

        return prompt
    }

    /// Generate system prompt that uses UMCF transcript content
    private func generateTranscriptBasedPrompt(topic: Topic, transcript: TopicTranscriptResponse) -> String {
        let topicTitle = topic.title ?? "the topic"
        let depth = topic.depthLevel

        // Collect all transcript segments as the content to deliver
        let transcriptContent = transcript.segments.enumerated().map { (index, segment) in
            var segmentText = "[\(segment.type.uppercased())] \(segment.content)"

            // Add speaking notes if available
            if let notes = segment.speakingNotes {
                if let pace = notes.pace {
                    segmentText += " [Pace: \(pace)]"
                }
                if let tone = notes.emotionalTone {
                    segmentText += " [Tone: \(tone)]"
                }
            }

            // Mark checkpoint segments
            if let checkpoint = segment.checkpoint, let question = checkpoint.question {
                segmentText += "\n[CHECKPOINT: \(question)]"
            }

            return "SEGMENT \(index + 1):\n\(segmentText)"
        }.joined(separator: "\n\n---\n\n")

        return """
        You are an expert lecturer delivering an audio-only educational lecture.
        You have been provided with a complete, professionally written transcript to deliver.

        TOPIC: \(topicTitle)
        DEPTH LEVEL: \(depth.displayName)

        IMPORTANT INSTRUCTIONS:
        1. Deliver the transcript content naturally, as if speaking it for the first time.
        2. Follow the speaking notes (pace, tone, pauses) when indicated.
        3. At CHECKPOINT segments, pause and ask the checkpoint question.
        4. Wait for the learner to respond before continuing.
        5. If the learner asks a question, answer it using your knowledge, then continue with the transcript.
        6. Maintain a conversational, engaging tone throughout.

        AUDIO-FRIENDLY REMINDERS:
        - This is audio-only. Never reference visuals or written content.
        - Speak mathematical concepts verbally (e.g., "x squared" not "x^2").
        - Use natural transitions between segments.

        === TRANSCRIPT TO DELIVER ===

        \(transcriptContent)

        === END TRANSCRIPT ===

        BEGIN NOW:
        Start delivering the first segment naturally. Speak as if you're having a one-on-one tutoring session.
        """
    }

    /// Get the current segment to deliver (for progressive transcript delivery)
    func getCurrentSegment() -> TranscriptSegmentInfo? {
        guard let transcript = umcfTranscript,
              currentSegmentIndex < transcript.segments.count else {
            return nil
        }
        return transcript.segments[currentSegmentIndex]
    }

    /// Advance to the next transcript segment
    func advanceToNextSegment() -> Bool {
        guard let transcript = umcfTranscript else { return false }
        if currentSegmentIndex < transcript.segments.count - 1 {
            currentSegmentIndex += 1
            return true
        }
        return false
    }

    /// Reset to the beginning of the transcript
    func resetTranscript() {
        currentSegmentIndex = 0
    }

    /// Generate the initial lecture opening for AI to speak first
    func generateLectureOpening() -> String {
        guard let topic = topic else { return "" }

        let topicTitle = topic.title ?? "this topic"
        let depth = topic.depthLevel

        return """
        Begin a \(depth.displayName.lowercased())-level lecture on \(topicTitle).
        Start with a brief introduction, then proceed through the material systematically.
        Expected duration: \(depth.expectedDurationRange.lowerBound)-\(depth.expectedDurationRange.upperBound) minutes.
        """
    }

    /// Debug test function to directly test on-device LLM without voice input
    func testOnDeviceLLM() async {
        logger.info("[DEBUG] Starting direct LLM test")
        print("[DEBUG] Starting direct LLM test")

        debugTestResult = "Testing LLM..."

        // Use configured server IP or fall back to localhost
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
        let llmModelSetting = UserDefaults.standard.string(forKey: "llmModel") ?? "llama3.2:3b"

        let llmService: SelfHostedLLMService
        if selfHostedEnabled && !serverIP.isEmpty {
            logger.info("[DEBUG] Using self-hosted LLM at \(serverIP):11434")
            llmService = SelfHostedLLMService.ollama(host: serverIP, model: llmModelSetting)
        } else {
            logger.warning("[DEBUG] No server IP configured - using localhost")
            llmService = SelfHostedLLMService.ollama(model: llmModelSetting)
        }

        let messages = [
            LLMMessage(role: .system, content: "You are a helpful assistant. Be brief."),
            LLMMessage(role: .user, content: "Hello! Say hi in one sentence.")
        ]

        // Use a config with empty model to let the service use its configured model
        var config = LLMConfig.default
        config.model = ""  // Let SelfHostedLLMService use its configured model (llama3.2:3b)

        do {
            print("[DEBUG] Calling streamCompletion...")
            let stream = try await llmService.streamCompletion(messages: messages, config: config)

            var response = ""
            print("[DEBUG] Iterating stream...")

            for await token in stream {
                response += token.content
                debugTestResult = "Response: \(response)"
                print("[DEBUG] Token: '\(token.content)', isDone: \(token.isDone)")

                if token.isDone {
                    break
                }
            }

            debugTestResult = "Success: \(response)"
            print("[DEBUG] LLM test complete: \(response)")

        } catch {
            debugTestResult = "Error: \(error.localizedDescription)"
            print("[DEBUG] LLM test error: \(error)")
            logger.error("[DEBUG] LLM test failed: \(error)")
        }
    }
    
    var isSessionActive: Bool {
        state.isActive
    }
    
    func toggleSession(appState: AppState) async {
        logger.info("toggleSession called - isSessionActive: \(isSessionActive), state: \(state.rawValue)")
        if isSessionActive {
            logger.info("Stopping session...")
            await stopSession()
            logger.info("Session stopped - state is now: \(state.rawValue)")
        } else {
            logger.info("Starting session...")
            await startSession(appState: appState)
            logger.info("Session started - state is now: \(state.rawValue)")
        }
    }
    
    private func startSession(appState: AppState) async {
        isLoading = true
        defer {
            logger.info("🔴 startSession defer executing - setting isLoading = false")
            isLoading = false
        }

        // Track session start time for auto-resume duration calculation
        sessionStartTime = Date()

        logger.info("🟢 startSession called")

        // Get self-hosted server settings
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""

        logger.info("🟡 Settings: selfHostedEnabled=\(selfHostedEnabled), serverIP='\(serverIP)'")
        logger.info("🟡 Topic: \(topic?.title ?? "nil"), sourceId=\(topic?.sourceId ?? "nil")")
        logger.info("🟡 Curriculum sourceId: \(topic?.curriculum?.sourceId ?? "nil")")

        // Check if we should use direct transcript streaming (bypasses LLM for pre-written content)
        // Use sourceId (UMCF ID) for server communication, not the Core Data UUID
        if let topic = topic,
           let topicSourceId = topic.sourceId,
           let curriculum = topic.curriculum,
           let curriculumSourceId = curriculum.sourceId,
           selfHostedEnabled,
           !serverIP.isEmpty {
            logger.info("🟢 Direct streaming conditions MET - entering direct streaming mode")

            // Check if server has transcript for this topic
            logger.info("Checking for direct transcript streaming for topic: \(topic.title ?? "unknown")")
            logger.info("Using sourceIds - curriculum: \(curriculumSourceId), topic: \(topicSourceId)")

            // Configure transcript streamer
            await transcriptStreamer.configure(host: serverIP, port: 8766)

            // Try direct streaming - this bypasses the LLM entirely
            isDirectStreamingMode = true
            state = .aiThinking  // Start with "AI thinking" while fetching transcript

            // Clear all previous session state
            conversationHistory.removeAll()
            userTranscript = ""
            aiResponse = ""
            audioQueue.removeAll()
            pendingTextSegments.removeAll()
            isPlayingAudio = false
            isPaused = false
            audioLevel = -60
            currentSegmentIndex = 0
            completedSegmentCount = 0
            totalSegments = 0

            logger.info("Starting direct transcript streaming (bypassing LLM)")

            // Start barge-in monitoring (microphone + VAD) in parallel with playback
            await startBargeInMonitoring(appState: appState)

            // Set up Watch sync for direct streaming mode
            setupWatchSync()

            await transcriptStreamer.streamTopicAudio(
                curriculumId: curriculumSourceId,
                topicId: topicSourceId,
                voice: UserDefaults.standard.string(forKey: "ttsVoice") ?? "nova",
                onSegmentText: { [weak self] index, type, text in
                    Task { @MainActor in
                        guard let self = self else { return }
                        // Buffer text - DON'T display yet, wait for audio to arrive
                        // This ensures text and audio stay synchronized
                        self.pendingTextSegments[index] = text
                        self.totalSegments = max(self.totalSegments, index + 1)
                        self.logger.info("Buffered segment \(index) text: \(type) - \(text.prefix(50))...")
                    }
                },
                onSegmentAudio: { [weak self] index, audioData in
                    Task { @MainActor in
                        guard let self = self else { return }
                        // Get the buffered text for this segment
                        let text = self.pendingTextSegments.removeValue(forKey: index) ?? ""

                        // Transition to "AI speaking" when first audio arrives
                        if self.state == .aiThinking {
                            self.state = .aiSpeaking
                            self.logger.info("Transitioning to aiSpeaking - first audio received")
                        }

                        // Queue the audio WITH its associated text for synchronized playback
                        self.queueAudioWithText(audioData: audioData, text: text, index: index)
                    }
                },
                onComplete: { [weak self] in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.logger.info("Direct transcript streaming complete - \(self.totalSegments) total segments")
                        // Note: Stay in aiSpeaking until audio queue is empty
                        // The audio queue completion will set state to userSpeaking
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.logger.error("Direct streaming failed: \(error), falling back to LLM mode")
                        self.isDirectStreamingMode = false
                        // Fall through to regular LLM-based session
                        await self.startLLMSession(appState: appState)
                    }
                }
            )
            return
        }

        // Fall back to LLM-based session
        logger.info("🟠 Direct streaming conditions NOT met - falling back to LLM session")
        await startLLMSession(appState: appState)
    }

    /// Start a traditional LLM-based session (used when no transcript available or direct streaming fails)
    private func startLLMSession(appState: AppState) async {
        logger.info("🟢 startLLMSession called")

        // Set state to aiThinking immediately so UI shows we're starting
        // This prevents the "stuck at Idle with spinner" bug
        state = .aiThinking

        // Read user settings from UserDefaults
        let sttProviderSetting = UserDefaults.standard.string(forKey: "sttProvider")
            .flatMap { STTProvider(rawValue: $0) } ?? .glmASROnDevice
        let llmProviderSetting = UserDefaults.standard.string(forKey: "llmProvider")
            .flatMap { LLMProvider(rawValue: $0) } ?? .localMLX
        let ttsProviderSetting = UserDefaults.standard.string(forKey: "ttsProvider")
            .flatMap { TTSProvider(rawValue: $0) } ?? .appleTTS

        // Get self-hosted server settings (needed for TTS and LLM configuration)
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""

        let sttService: any STTService
        let ttsService: any TTSService
        let llmService: any LLMService
        let vadService: any VADService = SileroVADService()

        // Configure STT based on settings
        logger.info("STT provider setting: \(sttProviderSetting.rawValue)")
        switch sttProviderSetting {
        case .glmASROnDevice:
            // Try GLM-ASR first, fall back to Apple Speech if models not available
            let isSupported = GLMASROnDeviceSTTService.isDeviceSupported
            logger.info("GLM-ASR isDeviceSupported: \(isSupported)")
            if isSupported {
                logger.info("Using GLMASROnDeviceSTTService")
                sttService = GLMASROnDeviceSTTService()
            } else {
                logger.warning("GLM-ASR not supported on this device/simulator, using Apple Speech fallback")
                sttService = AppleSpeechSTTService()
            }
        case .appleSpeech:
            logger.info("Using AppleSpeechSTTService (user selected)")
            sttService = AppleSpeechSTTService()
        case .deepgramNova3:
            if let apiKey = await appState.apiKeys.getKey(.deepgram) {
                sttService = DeepgramSTTService(apiKey: apiKey)
            } else {
                logger.warning("Deepgram API key not configured, falling back to Apple Speech")
                sttService = AppleSpeechSTTService()
            }
        case .assemblyAI:
            if let apiKey = await appState.apiKeys.getKey(.assemblyAI) {
                sttService = AssemblyAISTTService(apiKey: apiKey)
            } else {
                logger.warning("AssemblyAI API key not configured, falling back to Apple Speech")
                sttService = AppleSpeechSTTService()
            }
        default:
            // Default fallback to Apple Speech (always available)
            logger.info("Using Apple Speech as default STT provider")
            sttService = AppleSpeechSTTService()
        }

        // Configure TTS based on settings
        logger.info("TTS provider setting: \(ttsProviderSetting.rawValue)")
        switch ttsProviderSetting {
        case .appleTTS:
            logger.info("Using AppleTTSService")
            ttsService = AppleTTSService()
        case .selfHosted:
            // Use SelfHostedTTSService to connect to Piper server (22050 Hz)
            let ttsVoiceSetting = UserDefaults.standard.string(forKey: "ttsVoice") ?? "nova"
            if selfHostedEnabled && !serverIP.isEmpty {
                logger.info("Using self-hosted TTS (Piper) at \(serverIP):11402 with voice: \(ttsVoiceSetting)")
                ttsService = SelfHostedTTSService.piper(host: serverIP, voice: ttsVoiceSetting)
            } else {
                logger.warning("Self-hosted TTS selected but no server IP configured - falling back to Apple TTS")
                ttsService = AppleTTSService()
            }
        case .vibeVoice:
            // Use SelfHostedTTSService to connect to VibeVoice server (24000 Hz)
            let ttsVoiceSetting = UserDefaults.standard.string(forKey: "ttsVoice") ?? "nova"
            if selfHostedEnabled && !serverIP.isEmpty {
                logger.info("Using self-hosted TTS (VibeVoice) at \(serverIP):8880 with voice: \(ttsVoiceSetting)")
                ttsService = SelfHostedTTSService.vibeVoice(host: serverIP, voice: ttsVoiceSetting)
            } else {
                logger.warning("VibeVoice TTS selected but no server IP configured - falling back to Apple TTS")
                ttsService = AppleTTSService()
            }
        case .chatterbox:
            // Use ChatterboxTTSService with full configuration loaded from UserDefaults
            if selfHostedEnabled && !serverIP.isEmpty {
                let config = ChatterboxConfig.fromUserDefaults()
                logger.info("Using Chatterbox TTS at \(serverIP):8004 with exaggeration=\(config.exaggeration), cfg=\(config.cfgWeight), speed=\(config.speed)")
                ttsService = ChatterboxTTSService.chatterbox(host: serverIP, config: config)
            } else {
                logger.warning("Chatterbox TTS selected but no server IP configured - falling back to Apple TTS")
                ttsService = AppleTTSService()
            }
        case .elevenLabsFlash, .elevenLabsTurbo:
            if let apiKey = await appState.apiKeys.getKey(.elevenLabs) {
                ttsService = ElevenLabsTTSService(apiKey: apiKey)
            } else {
                logger.warning("ElevenLabs API key not configured, falling back to Apple TTS")
                ttsService = AppleTTSService()
            }
        case .deepgramAura2:
            if let apiKey = await appState.apiKeys.getKey(.deepgram) {
                ttsService = DeepgramTTSService(apiKey: apiKey)
            } else {
                logger.warning("Deepgram TTS API key not configured, falling back to Apple TTS")
                ttsService = AppleTTSService()
            }
        default:
            logger.info("Using Apple TTS as default TTS provider")
            ttsService = AppleTTSService()
        }

        // Configure LLM based on settings with graceful fallback
        // Priority: User selection → Self-hosted → On-device → Error
        logger.info("LLM provider setting: \(llmProviderSetting.rawValue)")
        logger.info("LLM config - selfHostedEnabled: \(selfHostedEnabled), serverIP: '\(serverIP)'")

        // Helper to create on-device LLM if available
        func createOnDeviceLLMIfAvailable() -> (any LLMService)? {
            #if LLAMA_AVAILABLE
            if OnDeviceLLMService.isDeviceSupported && OnDeviceLLMService.areModelsAvailable {
                logger.info("Using OnDeviceLLMService as fallback (device supported, models available)")
                return OnDeviceLLMService()
            }
            #endif
            return nil
        }

        // Helper to create self-hosted LLM if available
        func createSelfHostedLLMIfAvailable() -> (any LLMService)? {
            if selfHostedEnabled && !serverIP.isEmpty {
                let llmModelSetting = UserDefaults.standard.string(forKey: "llmModel") ?? "llama3.2:3b"
                logger.info("Using SelfHostedLLMService as fallback (host: \(serverIP), model: \(llmModelSetting))")
                return SelfHostedLLMService.ollama(host: serverIP, model: llmModelSetting)
            }
            return nil
        }

        switch llmProviderSetting {
        case .localMLX:
            // Try on-device LLM first (the intended behavior for localMLX)
            #if LLAMA_AVAILABLE
            if OnDeviceLLMService.isDeviceSupported && OnDeviceLLMService.areModelsAvailable {
                logger.info("localMLX selected - using OnDeviceLLMService")
                llmService = OnDeviceLLMService()
            } else if let selfHosted = createSelfHostedLLMIfAvailable() {
                logger.warning("On-device LLM not available, falling back to self-hosted")
                llmService = selfHosted
            } else {
                logger.warning("No LLM available - on-device not supported and no server configured")
                errorMessage = "On-device LLM requires model files. Please download models or configure a server."
                showError = true
                state = .idle
                return
            }
            #else
            // LLAMA not available, try self-hosted
            if let selfHosted = createSelfHostedLLMIfAvailable() {
                logger.warning("LLAMA not available in build, falling back to self-hosted")
                llmService = selfHosted
            } else {
                logger.warning("No LLM available - LLAMA not in build and no server configured")
                errorMessage = "On-device LLM not available in this build. Please configure a server."
                showError = true
                state = .idle
                return
            }
            #endif

        case .anthropic:
            if let apiKey = await appState.apiKeys.getKey(.anthropic) {
                llmService = AnthropicLLMService(apiKey: apiKey)
            } else if let selfHosted = createSelfHostedLLMIfAvailable() {
                logger.warning("Anthropic API key not configured, falling back to self-hosted")
                llmService = selfHosted
            } else if let onDevice = createOnDeviceLLMIfAvailable() {
                logger.warning("Anthropic API key not configured, falling back to on-device LLM")
                llmService = onDevice
            } else {
                errorMessage = "Anthropic API key not configured and no fallback available. Please add it in Settings or configure a server."
                showError = true
                state = .idle
                return
            }

        case .openAI:
            if let apiKey = await appState.apiKeys.getKey(.openAI) {
                llmService = OpenAILLMService(apiKey: apiKey)
            } else if let selfHosted = createSelfHostedLLMIfAvailable() {
                logger.warning("OpenAI API key not configured, falling back to self-hosted")
                llmService = selfHosted
            } else if let onDevice = createOnDeviceLLMIfAvailable() {
                logger.warning("OpenAI API key not configured, falling back to on-device LLM")
                llmService = onDevice
            } else {
                errorMessage = "OpenAI API key not configured and no fallback available. Please add it in Settings or configure a server."
                showError = true
                state = .idle
                return
            }

        case .selfHosted:
            // Use SelfHostedLLMService to connect to Ollama server
            var llmModelSetting = UserDefaults.standard.string(forKey: "llmModel") ?? "llama3.2:3b"
            logger.info("selfHosted selected - initial llmModel from UserDefaults: '\(llmModelSetting)'")

            // If the model setting looks like an OpenAI model, use discovered models or fallback
            let openAIModels = ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
            if openAIModels.contains(llmModelSetting) {
                logger.warning("Model '\(llmModelSetting)' looks like an OpenAI model, attempting to discover server models")
                // Get discovered models from server config
                let discoveredModels = await ServerConfigManager.shared.getAllDiscoveredModels()
                if !discoveredModels.isEmpty {
                    llmModelSetting = discoveredModels.first!
                    logger.info("Overriding OpenAI model with discovered server model: \(llmModelSetting)")
                } else {
                    llmModelSetting = "llama3.2:3b" // Safe fallback
                    logger.warning("No discovered models, using fallback: \(llmModelSetting)")
                }
            }

            // Use configured server IP if available
            if selfHostedEnabled && !serverIP.isEmpty {
                logger.info("Creating SelfHostedLLMService.ollama(host: \(serverIP), model: \(llmModelSetting))")
                llmService = SelfHostedLLMService.ollama(host: serverIP, model: llmModelSetting)
            } else if let onDevice = createOnDeviceLLMIfAvailable() {
                logger.warning("No server configured, falling back to on-device LLM")
                llmService = onDevice
            } else {
                #if targetEnvironment(simulator)
                // Simulator can use localhost to reach Ollama on the Mac
                logger.info("Using localhost for self-hosted LLM (simulator only)")
                llmService = SelfHostedLLMService.ollama(model: llmModelSetting)
                #else
                // Physical device: localhost won't work, show error
                errorMessage = "Self-hosted LLM requires a server IP. Please configure in Settings."
                showError = true
                state = .idle
                return
                #endif
            }
        }

        do {
            // Create SessionManager
            let manager = try await appState.createSessionManager()
            self.sessionManager = manager

            // Bind State
            bindToSessionManager(manager)

            // Generate system prompt and determine lecture mode
            let systemPrompt = generateSystemPrompt()
            let lectureMode = isLectureMode

            if lectureMode {
                logger.info("Starting lecture session for topic: \(topic?.title ?? "unknown")")
            }

            // Start Session
            try await manager.startSession(
                sttService: sttService,
                ttsService: ttsService,
                llmService: llmService,
                vadService: vadService,
                systemPrompt: systemPrompt,
                lectureMode: lectureMode
            )

            // Set up Watch sync after session starts
            setupWatchSync()

        } catch {
            logger.error("Session start failed: \(error.localizedDescription)", metadata: [
                "error_type": "\(type(of: error))",
                "full_error": "\(error)"
            ])
            errorMessage = "Failed to start session: \(error.localizedDescription)"
            showError = true
            await stopSession()
        }
    }
    
    private func stopSession() async {
        isLoading = true
        defer { isLoading = false }

        // Create auto-resume item BEFORE clearing state
        await createAutoResumeIfNeeded()

        // Stop direct streaming if active
        if isDirectStreamingMode {
            await transcriptStreamer.stopStreaming()
            await stopBargeInMonitoring()
            stopAudioMeteringTimer()
            audioPlayer?.stop()
            audioPlayer = nil
            isDirectStreamingMode = false
        }

        if let manager = sessionManager {
            await manager.stopSession()
        }

        sessionManager = nil
        subscribers.removeAll()
        state = .idle
        sessionStartTime = nil

        // Clear conversation history when session ends
        conversationHistory.removeAll()
        lastUserTranscript = ""
        lastAiResponse = ""

        // Notify Watch of session end
        teardownWatchSync()
    }

    /// Queue audio with associated text for synchronized playback (for transcript streaming mode)
    /// Text is only displayed when the audio for that segment starts playing
    private func queueAudioWithText(audioData: Data, text: String, index: Int) {
        audioQueue.append((audio: audioData, text: text, index: index))
        logger.info("Queued segment \(index) audio (\(audioData.count) bytes), queue size: \(audioQueue.count)")

        // Cache segment for replay/rewind capability
        let topicId = topic?.sourceId ?? topic?.id?.uuidString
        Task { [weak self] in
            guard let cache = self?.audioSegmentCache else { return }
            await cache.cacheSegment(
                index: index,
                text: text,
                audioData: audioData,
                topicId: topicId
            )
        }

        // Start playback if not already playing and not paused
        if !isPlayingAudio && !isPaused {
            // Configure audio session for playback (required for direct streaming mode)
            configureAudioSessionForPlayback()
            playNextAudioSegment()
        }
    }

    /// Pause curriculum playback - freezes everything in place
    func pausePlayback() {
        guard showCurriculumControls else { return }
        isPaused = true
        audioPlayer?.pause()
        logger.info("Playback paused at segment \(currentSegmentIndex)")
    }

    /// Set the microphone muted state
    /// When muted, the microphone is disabled and barge-in detection is suspended
    func setMicrophoneMuted(_ muted: Bool) {
        isMuted = muted
        logger.info("Microphone muted: \(muted)")

        // Pause or resume barge-in audio monitoring based on mute state
        if muted {
            // Stop the barge-in audio engine when muted
            Task {
                if let audioEngine = bargeInAudioEngine {
                    await audioEngine.stop()
                    logger.info("Barge-in monitoring paused (muted)")
                }
            }
        } else {
            // Restart the barge-in audio engine when unmuted
            Task {
                if let audioEngine = bargeInAudioEngine {
                    do {
                        try await audioEngine.start()
                        logger.info("Barge-in monitoring resumed (unmuted)")
                    } catch {
                        logger.error("Failed to resume barge-in monitoring: \(error)")
                    }
                }
            }
        }
    }

    /// Resume curriculum playback from where it was paused
    func resumePlayback() {
        guard showCurriculumControls && isPaused else { return }
        isPaused = false

        // If we have a paused audio player, resume it
        if let player = audioPlayer, !player.isPlaying {
            player.play()
            logger.info("Resumed playing current segment")
        } else if !audioQueue.isEmpty {
            // Otherwise, start next segment
            playNextAudioSegment()
        }
        logger.info("Playback resumed")
    }

    /// Go back one segment (replay the previous segment)
    /// Uses cached audio for instant playback
    func goBackOneSegment() {
        guard currentSegmentIndex > 0 else {
            logger.info("Cannot go back - already at first segment")
            return
        }

        let targetIndex = currentSegmentIndex - 1
        logger.info("Going back to segment \(targetIndex) from \(currentSegmentIndex)")

        // Stop current playback
        audioPlayer?.stop()
        audioPlayer = nil
        audioQueue.removeAll()

        Task {
            // Get all cached segments from target index onward
            let segmentsToReplay = await audioSegmentCache.getSegments(from: targetIndex)

            guard !segmentsToReplay.isEmpty else {
                logger.warning("Segment \(targetIndex) not cached, cannot go back")
                return
            }

            // Rebuild the queue from cached segments
            await MainActor.run {
                audioQueue = segmentsToReplay.map { (audio: $0.audioData, text: $0.text, index: $0.index) }
                currentSegmentIndex = targetIndex
                completedSegmentCount = targetIndex

                // Resume playback
                isPaused = false
                playNextAudioSegment()
            }

            logger.info("Replaying from segment \(targetIndex), queue size: \(segmentsToReplay.count)")
        }
    }

    /// Replay the entire current topic from the beginning
    /// Uses cached audio for instant playback
    func replayCurrentTopic() {
        logger.info("Replaying current topic from beginning")

        // Stop current playback
        audioPlayer?.stop()
        audioPlayer = nil
        audioQueue.removeAll()

        Task {
            // Get all cached segments
            let allSegments = await audioSegmentCache.getAllSegments()

            guard !allSegments.isEmpty else {
                logger.warning("No cached segments available for replay")
                return
            }

            // Rebuild the queue from all cached segments
            await MainActor.run {
                audioQueue = allSegments.map { (audio: $0.audioData, text: $0.text, index: $0.index) }
                currentSegmentIndex = 0
                completedSegmentCount = 0

                // Clear conversation history to restart fresh
                conversationHistory.removeAll()
                aiResponse = ""

                // Resume playback
                isPaused = false
                playNextAudioSegment()
            }

            logger.info("Replaying topic from beginning, \(allSegments.count) segments queued")
        }
    }

    /// Skip to the next topic in the curriculum
    /// This is called manually by the user or automatically on topic completion
    func skipToNextTopic() {
        logger.info("Skip to next topic requested")

        // If we have pre-generated content, use it
        if preGeneratedNextTopic != nil && !nextTopicAudioQueue.isEmpty {
            Task {
                await transitionToNextTopic()
            }
            return
        }

        // Otherwise, try to start the next topic fresh
        Task {
            await tryStartNextTopic()
        }
    }

    /// Stop curriculum playback completely and save progress
    func stopPlayback() {
        guard showCurriculumControls else { return }

        logger.info("Stopping playback at segment \(currentSegmentIndex)/\(totalSegments)")

        // Create auto-resume item before clearing state
        Task {
            await createAutoResumeIfNeeded()
        }

        // Stop audio and metering
        stopAudioMeteringTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        audioQueue.removeAll()
        pendingTextSegments.removeAll()
        isPlayingAudio = false
        isPaused = false

        // Stop barge-in monitoring
        Task {
            await stopBargeInMonitoring()
        }

        // Save progress to topic if available
        if let topic = topic {
            saveProgress(to: topic)
        }

        // Transition to idle
        isDirectStreamingMode = false
        state = .idle
        sessionStartTime = nil

        // Notify Watch of session end
        teardownWatchSync()
    }

    // MARK: - Topic Auto-Continue

    /// Pre-generate the next topic's audio for seamless transition
    /// Called automatically when current topic reaches 70% progress
    private func preGenerateNextTopic() async {
        guard !isPreGeneratingNextTopic else {
            logger.info("Already pre-generating next topic")
            return
        }

        guard let currentTopic = topic,
              let curriculum = currentTopic.curriculum else {
            logger.info("No curriculum context for pre-generation")
            return
        }

        // Get next topic using CurriculumEngine pattern
        let topics = (curriculum.topics?.array as? [Topic] ?? []).sorted { ($0.orderIndex) < ($1.orderIndex) }
        guard let currentIndex = topics.firstIndex(where: { $0.id == currentTopic.id }),
              currentIndex + 1 < topics.count else {
            logger.info("No next topic available - at end of curriculum")
            return
        }

        let nextTopic = topics[currentIndex + 1]

        // Ensure we have valid source IDs before pre-generating
        guard let curriculumSourceId = curriculum.sourceId, !curriculumSourceId.isEmpty,
              let nextTopicSourceId = nextTopic.sourceId, !nextTopicSourceId.isEmpty else {
            logger.warning("Missing source IDs for curriculum or next topic - cannot pre-generate")
            return
        }

        logger.info("Pre-generating audio for next topic: \(nextTopic.title ?? "Unknown")")

        isPreGeneratingNextTopic = true
        preGeneratedNextTopic = nextTopic

        // Get voice from settings
        let voice = UserDefaults.standard.string(forKey: "ttsVoice") ?? "nova"

        // Stream next topic's audio into separate buffer
        await transcriptStreamer.streamTopicAudio(
            curriculumId: curriculumSourceId,
            topicId: nextTopicSourceId,
            voice: voice,
            onSegmentText: { [weak self] index, _, text in
                Task { @MainActor in
                    self?.nextTopicPendingText[index] = text
                }
            },
            onSegmentAudio: { [weak self] index, audioData in
                Task { @MainActor in
                    guard let self = self else { return }
                    let text = self.nextTopicPendingText[index] ?? ""
                    self.nextTopicAudioQueue.append((audio: audioData, text: text, index: index))
                    self.nextTopicTotalSegments = max(self.nextTopicTotalSegments, index + 1)
                }
            },
            onComplete: { [weak self] in
                Task { @MainActor in
                    self?.logger.info("Pre-generation complete for next topic: \(self?.nextTopicAudioQueue.count ?? 0) segments")
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.logger.error("Pre-generation failed: \(error.localizedDescription)")
                    self?.isPreGeneratingNextTopic = false
                    self?.preGeneratedNextTopic = nil
                }
            }
        )
    }

    /// Transition to the next topic using pre-generated content
    private func transitionToNextTopic() async {
        guard let nextTopic = preGeneratedNextTopic else {
            logger.warning("No pre-generated topic available for transition")
            return
        }

        logger.info("Transitioning to next topic: \(nextTopic.title ?? "Unknown")")

        // Announce the transition via a brief spoken message
        let currentTitle = topic?.title ?? "the current topic"
        let nextTitle = nextTopic.title ?? "the next topic"
        let announcement = "Great work completing \(currentTitle). Now continuing with \(nextTitle)."

        // Update UI to show transition
        aiResponse = "Transitioning to: \(nextTitle)"

        // Speak the transition announcement using TTS
        await speakTransitionAnnouncement(announcement)

        // Clear current topic's cache
        await audioSegmentCache.clearCache()

        // Swap to the next topic
        topic = nextTopic
        audioQueue = nextTopicAudioQueue
        pendingTextSegments = nextTopicPendingText
        totalSegments = nextTopicTotalSegments
        currentSegmentIndex = 0
        completedSegmentCount = 0

        // Clear conversation for fresh topic
        conversationHistory.removeAll()
        aiResponse = ""

        // Reset pre-generation state
        nextTopicAudioQueue = []
        nextTopicPendingText = [:]
        nextTopicTotalSegments = 0
        preGeneratedNextTopic = nil
        isPreGeneratingNextTopic = false

        // Continue playback with the new topic
        playNextAudioSegment()
    }

    /// Try to start the next topic without pre-generated content
    private func tryStartNextTopic() async {
        guard let currentTopic = topic,
              let curriculum = currentTopic.curriculum else {
            logger.info("No curriculum context for next topic")
            state = .userSpeaking
            isDirectStreamingMode = false
            return
        }

        // Get next topic
        let topics = (curriculum.topics?.array as? [Topic] ?? []).sorted { ($0.orderIndex) < ($1.orderIndex) }
        guard let currentIndex = topics.firstIndex(where: { $0.id == currentTopic.id }),
              currentIndex + 1 < topics.count else {
            logger.info("No next topic - reached end of curriculum")
            state = .userSpeaking
            isDirectStreamingMode = false
            return
        }

        let nextTopic = topics[currentIndex + 1]
        logger.info("Starting next topic fresh: \(nextTopic.title ?? "Unknown")")

        // Announce transition
        let announcement = "Now continuing with \(nextTopic.title ?? "the next topic")."
        await speakTransitionAnnouncement(announcement)

        // Clear current state
        await audioSegmentCache.clearCache()
        audioQueue.removeAll()
        pendingTextSegments.removeAll()
        conversationHistory.removeAll()
        aiResponse = ""

        // Switch to next topic
        topic = nextTopic
        currentSegmentIndex = 0
        completedSegmentCount = 0
        totalSegments = 0

        // Start streaming the new topic
        await startDirectStreamingForCurrentTopic()
    }

    /// Speak a transition announcement using TTS
    private func speakTransitionAnnouncement(_ text: String) async {
        // Use Apple TTS for announcement - it's always available and reliable
        // This is a brief interruption before continuing with the next topic
        do {
            let ttsService = AppleTTSService()

            // Synthesize the announcement
            let stream = try await ttsService.synthesize(text: text)

            // Collect all audio chunks
            var audioData = Data()
            for try await chunk in stream {
                audioData.append(chunk.audioData)
            }

            guard !audioData.isEmpty else {
                logger.warning("No audio data generated for transition announcement")
                return
            }

            // Play the complete announcement (retain player to prevent deallocation)
            announcementPlayer = try AVAudioPlayer(data: audioData)
            announcementPlayer?.play()

            // Wait for playback to complete
            if let duration = announcementPlayer?.duration {
                try await Task.sleep(for: .milliseconds(Int(duration * 1000) + 100))
            }

            // Release the player
            announcementPlayer = nil
        } catch {
            logger.warning("Failed to speak transition announcement: \(error.localizedDescription)")
            announcementPlayer = nil
            // Continue anyway - the announcement is not critical
        }
    }

    /// Start direct streaming for the current topic
    private func startDirectStreamingForCurrentTopic() async {
        guard let currentTopic = topic,
              let curriculum = currentTopic.curriculum else {
            logger.warning("No topic or curriculum for streaming")
            return
        }

        // Ensure we have valid source IDs before streaming
        guard let curriculumSourceId = curriculum.sourceId, !curriculumSourceId.isEmpty,
              let topicSourceId = currentTopic.sourceId, !topicSourceId.isEmpty else {
            logger.error("Missing source IDs for curriculum or topic - cannot stream")
            state = .idle
            isDirectStreamingMode = false
            return
        }

        let voice = UserDefaults.standard.string(forKey: "ttsVoice") ?? "nova"

        await transcriptStreamer.streamTopicAudio(
            curriculumId: curriculumSourceId,
            topicId: topicSourceId,
            voice: voice,
            onSegmentText: { [weak self] index, _, text in
                Task { @MainActor in
                    self?.pendingTextSegments[index] = text
                    self?.totalSegments = max(self?.totalSegments ?? 0, index + 1)
                }
            },
            onSegmentAudio: { [weak self] index, audioData in
                Task { @MainActor in
                    guard let self = self else { return }
                    let text = self.pendingTextSegments[index] ?? ""
                    self.queueAudioWithText(audioData: audioData, text: text, index: index)
                }
            },
            onComplete: { [weak self] in
                Task { @MainActor in
                    self?.logger.info("Topic streaming complete")
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.logger.error("Topic streaming failed: \(error.localizedDescription)")
                    self?.state = .idle
                    self?.isDirectStreamingMode = false
                }
            }
        )
    }

    // MARK: - Watch Sync Methods

    /// Set up Watch connectivity observers for state sync
    private func setupWatchSync() {
        logger.info("Setting up Watch sync")

        // Set up command handler for Watch commands
        WatchConnectivityService.shared.setCommandHandler { [weak self] command in
            await self?.handleWatchCommand(command) ?? CommandResponse(
                command: command,
                success: false,
                error: "Session not available"
            )
        }

        // Sync on state changes
        $state.sink { [weak self] _ in
            self?.syncToWatch()
        }.store(in: &watchSyncCancellables)

        $isPaused.sink { [weak self] _ in
            self?.syncToWatch()
        }.store(in: &watchSyncCancellables)

        $isMuted.sink { [weak self] _ in
            self?.syncToWatch()
        }.store(in: &watchSyncCancellables)

        $currentSegmentIndex.sink { [weak self] _ in
            self?.syncToWatch()
        }.store(in: &watchSyncCancellables)

        $completedSegmentCount.sink { [weak self] _ in
            self?.syncToWatch()
        }.store(in: &watchSyncCancellables)

        // Initial sync
        syncToWatch()
    }

    /// Sync current state to Watch
    private func syncToWatch() {
        let watchState = generateWatchState()
        WatchConnectivityService.shared.syncSessionState(watchState)
    }

    /// Generate WatchSessionState from current view model state
    private func generateWatchState() -> WatchSessionState {
        let sessionMode: WatchSessionState.SessionMode
        if isDirectStreamingMode {
            sessionMode = .directStreaming
        } else if topic != nil {
            sessionMode = .curriculum
        } else {
            sessionMode = .freeform
        }

        let elapsedSeconds: TimeInterval
        if let startTime = sessionStartTime {
            elapsedSeconds = Date().timeIntervalSince(startTime)
        } else {
            elapsedSeconds = 0
        }

        return WatchSessionState(
            isActive: state != .idle,
            isPaused: isPaused,
            isMuted: isMuted,
            curriculumTitle: topic?.curriculum?.name,
            topicTitle: topic?.title,
            sessionMode: sessionMode,
            currentSegment: currentSegmentIndex,
            totalSegments: totalSegments,
            elapsedSeconds: elapsedSeconds
        )
    }

    /// Handle command received from Watch
    private func handleWatchCommand(_ command: SessionCommand) async -> CommandResponse {
        logger.info("Handling Watch command: \(command.commandDescription)")

        switch command {
        case .pause:
            pausePlayback()
        case .resume:
            resumePlayback()
        case .mute:
            setMicrophoneMuted(true)
        case .unmute:
            setMicrophoneMuted(false)
        case .stop:
            stopPlayback()
        }

        return CommandResponse(
            command: command,
            success: true,
            updatedState: generateWatchState()
        )
    }

    /// Tear down Watch sync when session ends
    private func teardownWatchSync() {
        logger.info("Tearing down Watch sync")
        watchSyncCancellables.removeAll()
        WatchConnectivityService.shared.clearCommandHandler()
        // Send idle state
        WatchConnectivityService.shared.syncSessionState(.idle)
    }

    /// Save progress to the topic
    private func saveProgress(to topic: Topic) {
        guard totalSegments > 0 else { return }

        let progress = Float(completedSegmentCount) / Float(totalSegments)
        logger.info("Saving progress: \(completedSegmentCount)/\(totalSegments) segments = \(Int(progress * 100))%")

        // Update topic mastery based on progress
        // Note: This is a simple linear progress - could be enhanced with actual comprehension tracking
        let context = PersistenceController.shared.viewContext
        topic.mastery = max(topic.mastery, progress)

        // Update or create topic progress
        if let topicProgress = topic.progress {
            topicProgress.timeSpent += Double(completedSegmentCount * 30)  // Estimate ~30s per segment
            topicProgress.lastAccessed = Date()
        } else {
            // Create new progress record
            let newProgress = TopicProgress(context: context)
            newProgress.id = UUID()
            newProgress.timeSpent = Double(completedSegmentCount * 30)
            newProgress.lastAccessed = Date()
            topic.progress = newProgress
        }

        do {
            try context.save()
            logger.info("Progress saved successfully")
        } catch {
            logger.error("Failed to save progress: \(error)")
        }
    }

    /// Create an auto-resume to-do item if the session was interrupted mid-curriculum
    private func createAutoResumeIfNeeded() async {
        // Only for curriculum sessions
        guard let topic = topic,
              let topicId = topic.id else {
            logger.debug("No auto-resume: not a curriculum session")
            return
        }

        // Check session duration (minimum 2 minutes for substantive session)
        let minDuration: TimeInterval = 120 // 2 minutes
        let sessionDuration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        guard sessionDuration >= minDuration else {
            logger.debug("No auto-resume: session too short (\(Int(sessionDuration))s < \(Int(minDuration))s)")
            return
        }

        // Check if we've made progress (not at beginning)
        guard currentSegmentIndex > 0 else {
            logger.debug("No auto-resume: still at beginning (segment 0)")
            return
        }

        // Check if topic not completed (some segments remaining)
        let isCompleted = totalSegments > 0 && completedSegmentCount >= totalSegments
        guard !isCompleted else {
            logger.debug("No auto-resume: topic already completed")
            // Clear any existing auto-resume for this topic since it's done
            await AutoResumeService.shared.clearAutoResume(for: topicId)
            return
        }

        // Build conversation context from history (last 10 messages)
        let recentMessages = conversationHistory.suffix(10).map { msg in
            ResumeConversationMessage(
                role: msg.isUser ? "user" : "assistant",
                content: msg.text
            )
        }

        // Create auto-resume context
        let context = AutoResumeContext(
            topicId: topicId,
            topicTitle: topic.title ?? "Unknown Topic",
            curriculumId: topic.curriculum?.id,
            segmentIndex: Int32(currentSegmentIndex),
            totalSegments: Int32(totalSegments),
            sessionDuration: sessionDuration,
            conversationMessages: Array(recentMessages)
        )

        // Create or update auto-resume item
        let created = await AutoResumeService.shared.handleSessionStop(context: context)
        if created {
            logger.info("Created auto-resume item for topic '\(topic.title ?? "")' at segment \(currentSegmentIndex)/\(totalSegments)")
        }
    }

    // MARK: - Barge-In Monitoring

    /// Start microphone monitoring for barge-in detection during direct streaming
    /// This runs the AudioEngine in parallel with AVAudioPlayer playback
    private func startBargeInMonitoring(appState: AppState) async {
        logger.info("Starting barge-in monitoring for direct streaming mode")

        // Create VAD service
        let vadService = SileroVADService()
        self.bargeInVADService = vadService

        // Create audio engine with VAD
        let telemetry = TelemetryEngine()
        var audioConfig = AudioEngineConfig.default
        audioConfig.enableBargeIn = true
        audioConfig.bargeInThreshold = bargeInThreshold

        let audioEngine = AudioEngine(
            config: audioConfig,
            vadService: vadService,
            telemetry: telemetry
        )
        self.bargeInAudioEngine = audioEngine

        // Configure STT service for transcribing barge-in speech
        let sttProviderSetting = UserDefaults.standard.string(forKey: "sttProvider")
            .flatMap { STTProvider(rawValue: $0) } ?? .appleSpeech

        switch sttProviderSetting {
        case .glmASROnDevice:
            if GLMASROnDeviceSTTService.isDeviceSupported {
                bargeInSTTService = GLMASROnDeviceSTTService()
            } else {
                bargeInSTTService = AppleSpeechSTTService()
            }
        case .appleSpeech:
            bargeInSTTService = AppleSpeechSTTService()
        default:
            bargeInSTTService = AppleSpeechSTTService()
        }

        // Configure LLM service for responding to barge-in questions
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
        let llmModelSetting = UserDefaults.standard.string(forKey: "llmModel") ?? "llama3.2:3b"

        if selfHostedEnabled && !serverIP.isEmpty {
            bargeInLLMService = SelfHostedLLMService.ollama(host: serverIP, model: llmModelSetting)
        } else {
            bargeInLLMService = SelfHostedLLMService.ollama(model: llmModelSetting)
        }

        // Configure TTS service for speaking barge-in responses
        let ttsProviderSetting = UserDefaults.standard.string(forKey: "ttsProvider")
            .flatMap { TTSProvider(rawValue: $0) } ?? .appleTTS
        let ttsVoiceSetting = UserDefaults.standard.string(forKey: "ttsVoice") ?? "nova"

        switch ttsProviderSetting {
        case .vibeVoice:
            if selfHostedEnabled && !serverIP.isEmpty {
                bargeInTTSService = SelfHostedTTSService.vibeVoice(host: serverIP, voice: ttsVoiceSetting)
            } else {
                bargeInTTSService = AppleTTSService()
            }
        case .selfHosted:
            if selfHostedEnabled && !serverIP.isEmpty {
                bargeInTTSService = SelfHostedTTSService.piper(host: serverIP, voice: ttsVoiceSetting)
            } else {
                bargeInTTSService = AppleTTSService()
            }
        case .chatterbox:
            if selfHostedEnabled && !serverIP.isEmpty {
                // Use same config as main TTS but without seed for barge-in
                var config = ChatterboxConfig.fromUserDefaults()
                config.seed = nil  // Barge-in doesn't need reproducibility
                bargeInTTSService = ChatterboxTTSService.chatterbox(host: serverIP, config: config)
            } else {
                bargeInTTSService = AppleTTSService()
            }
        default:
            bargeInTTSService = AppleTTSService()
        }

        do {
            // Configure and start audio engine
            try await audioEngine.configure(config: audioConfig)
            try await audioEngine.start()

            // Subscribe to audio stream for VAD events
            await audioEngine.audioStream
                .receive(on: DispatchQueue.main)
                .sink { [weak self] (buffer, vadResult) in
                    Task { @MainActor in
                        await self?.handleVADResult(buffer: buffer, vadResult: vadResult)
                    }
                }
                .store(in: &subscribers)

            logger.info("Barge-in monitoring started successfully")
        } catch {
            logger.error("Failed to start barge-in monitoring: \(error)")
        }
    }

    /// Calculate audio level (dB) from an audio buffer
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return -60 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return -60 }

        // Calculate RMS
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        // Convert to dB (with floor at -60dB)
        let db = 20 * log10(max(rms, 0.000001))
        return max(-60, min(0, db))
    }

    /// Start timer to update audio level from AVAudioPlayer metering (for AI speaking visualization)
    private func startAudioMeteringTimer() {
        // Stop any existing timer
        stopAudioMeteringTimer()

        // Create timer that fires 30 times per second for smooth VU meter updates
        audioMeteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAudioLevelFromPlayback()
            }
        }
    }

    /// Stop the audio metering timer
    private func stopAudioMeteringTimer() {
        audioMeteringTimer?.invalidate()
        audioMeteringTimer = nil
    }

    /// Update audio level from AVAudioPlayer metering (used during AI playback)
    private func updateAudioLevelFromPlayback() {
        guard let player = audioPlayer, player.isPlaying else {
            // If not playing, stop the timer and reset level
            stopAudioMeteringTimer()
            if state != .userSpeaking {
                audioLevel = -60
            }
            return
        }

        // Update meters and get average power
        player.updateMeters()
        let power = player.averagePower(forChannel: 0)
        audioLevel = power
    }

    /// Stop barge-in monitoring and clean up resources
    private func stopBargeInMonitoring() async {
        logger.info("Stopping barge-in monitoring")

        bargeInConfirmationTask?.cancel()
        bargeInConfirmationTask = nil

        if let audioEngine = bargeInAudioEngine {
            await audioEngine.stop()
        }
        bargeInAudioEngine = nil
        bargeInVADService = nil
        bargeInSTTService = nil
        bargeInLLMService = nil
        bargeInTTSService = nil
        bargeInAudioBuffers.removeAll()
        isTentativeBargeIn = false
    }

    /// Handle VAD result during direct streaming playback
    private func handleVADResult(buffer: AVAudioPCMBuffer, vadResult: VADResult) async {
        // Update audio level for UI only when user is speaking
        // When AI is speaking, the metering timer handles the audio level from playback
        if state == .userSpeaking {
            audioLevel = calculateAudioLevel(from: buffer)
        }

        // Handle different states
        switch state {
        case .aiSpeaking where isDirectStreamingMode:
            // Check if this looks like user speech (above barge-in threshold)
            if vadResult.isSpeech && vadResult.confidence > bargeInThreshold {
                if !isTentativeBargeIn {
                    // Stage 1: Tentative barge-in - pause playback and wait for confirmation
                    await handleTentativeBargeIn()
                } else {
                    // Stage 2: Continued speech during confirmation window - confirm barge-in
                    bargeInAudioBuffers.append(buffer)
                    await confirmBargeIn()
                }
            }

            // Collect audio during tentative barge-in for STT
            if isTentativeBargeIn {
                bargeInAudioBuffers.append(buffer)
            }

        case .interrupted:
            // During tentative barge-in, check for continued speech or silence
            bargeInAudioBuffers.append(buffer)
            if vadResult.isSpeech && vadResult.confidence > bargeInThreshold {
                await confirmBargeIn()
            }

        case .userSpeaking:
            // User is speaking after confirmed barge-in - collect audio and detect end
            bargeInAudioBuffers.append(buffer)

            if vadResult.isSpeech && vadResult.confidence > 0.3 {
                // Active speech - reset silence timer
                hasDetectedSpeechInBargeIn = true
                silenceStartTime = nil
            } else {
                // Silence detected
                if hasDetectedSpeechInBargeIn {
                    // We had speech before, now silence - check duration
                    if silenceStartTime == nil {
                        silenceStartTime = Date()
                    } else if let startTime = silenceStartTime {
                        let silenceDuration = Date().timeIntervalSince(startTime)
                        if silenceDuration >= endOfUtteranceSilenceDuration {
                            // End of utterance detected
                            logger.info("End of utterance detected after \(silenceDuration)s silence")
                            silenceStartTime = nil
                            hasDetectedSpeechInBargeIn = false
                            await handleBargeInUtteranceComplete()
                        }
                    }
                }
            }

        default:
            break
        }
    }

    /// Stage 1: Tentative barge-in - pause playback, start confirmation timer
    private func handleTentativeBargeIn() async {
        guard !isTentativeBargeIn else { return }

        logger.info("Tentative barge-in detected - pausing playback for confirmation")

        isTentativeBargeIn = true
        state = .interrupted

        // Record where we paused so we can resume
        bargeInPauseSegmentIndex = currentSegmentIndex
        bargeInPauseTime = audioPlayer?.currentTime ?? 0

        // Pause playback (don't stop - we might resume)
        audioPlayer?.pause()

        // Clear audio buffer for fresh STT input
        bargeInAudioBuffers.removeAll()

        // Start confirmation timer - if no continued speech, resume playback
        bargeInConfirmationTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(bargeInConfirmationWindow * 1_000_000_000))

            // If we get here without being cancelled, no continued speech - resume
            if !Task.isCancelled && isTentativeBargeIn {
                await resumeFromTentativeBargeIn()
            }
        }
    }

    /// Stage 2: Confirmed barge-in - user is actually speaking
    private func confirmBargeIn() async {
        guard isTentativeBargeIn else { return }

        logger.info("Barge-in confirmed - stopping playback, listening to user")

        // Cancel confirmation timer
        bargeInConfirmationTask?.cancel()
        bargeInConfirmationTask = nil

        // Stop playback completely (not just pause)
        stopAudioMeteringTimer()
        audioPlayer?.stop()
        audioPlayer = nil

        // Transition to user speaking
        state = .userSpeaking
        isTentativeBargeIn = false

        // Start collecting user's full utterance
        // The VAD will continue detecting speech; when silence is detected, we'll process
        startListeningForBargeInUtterance()
    }

    /// Resume playback after false positive barge-in (no continued speech)
    private func resumeFromTentativeBargeIn() async {
        guard isTentativeBargeIn else { return }

        logger.info("False positive barge-in - resuming playback from \(bargeInPauseTime)s")

        isTentativeBargeIn = false
        bargeInAudioBuffers.removeAll()

        // Resume playback
        state = .aiSpeaking
        audioPlayer?.play()
    }

    /// Start listening for the user's complete utterance after confirmed barge-in
    private func startListeningForBargeInUtterance() {
        logger.info("Listening for user's barge-in utterance...")

        // We'll detect end of speech via VAD silence detection
        // When speech ends, handleBargeInUtteranceComplete will be called
    }

    /// Handle completion of user's barge-in utterance
    /// Called when VAD detects sufficient silence after confirmed barge-in
    private func handleBargeInUtteranceComplete() async {
        guard state == .userSpeaking else { return }

        logger.info("User finished speaking - processing barge-in utterance")
        state = .processingUserUtterance

        // Transcribe the collected audio
        guard let sttService = bargeInSTTService else {
            logger.error("No STT service available for barge-in")
            await resumeAfterBargeIn(userQuestion: nil)
            return
        }

        do {
            // Combine audio buffers and transcribe
            let transcript = try await transcribeBargeInAudio(sttService: sttService)

            if transcript.isEmpty {
                // No intelligible speech - treat as false positive, resume
                logger.info("Empty transcript from barge-in - resuming playback")
                await resumeAfterBargeIn(userQuestion: nil)
            } else {
                // Got a real question/comment - process with LLM
                logger.info("User said: \(transcript)")
                userTranscript = transcript
                conversationHistory.append(ConversationMessage(
                    text: transcript,
                    isUser: true,
                    timestamp: Date()
                ))
                await handleBargeInQuestion(question: transcript)
            }
        } catch {
            logger.error("Failed to transcribe barge-in audio: \(error)")
            await resumeAfterBargeIn(userQuestion: nil)
        }
    }

    /// Transcribe the collected barge-in audio buffers
    private func transcribeBargeInAudio(sttService: any STTService) async throws -> String {
        guard !bargeInAudioBuffers.isEmpty else {
            logger.warning("No audio buffers to transcribe")
            return ""
        }

        logger.info("Transcribing \(bargeInAudioBuffers.count) audio buffers for barge-in")

        // Get format from first buffer and create a copy to satisfy Swift 6 sending requirements
        guard let sourceFormat = bargeInAudioBuffers.first?.format,
              let format = AVAudioFormat(
                  commonFormat: sourceFormat.commonFormat,
                  sampleRate: sourceFormat.sampleRate,
                  channels: sourceFormat.channelCount,
                  interleaved: sourceFormat.isInterleaved
              ) else {
            logger.error("No audio format available from buffers")
            return ""
        }

        // Start STT streaming
        let resultsStream = try await sttService.startStreaming(audioFormat: format)

        // Send all collected audio buffers using nonisolated wrapper to avoid Sendable issues
        // AVAudioPCMBuffer isn't Sendable, but we're on MainActor and the STT service handles isolation
        for buffer in bargeInAudioBuffers {
            let wrapper = SendableAudioBufferWrapper(buffer: buffer)
            try await sttService.sendAudio(wrapper.buffer)
        }

        // Signal end of audio
        try await sttService.stopStreaming()

        // Collect final transcript from results
        var finalTranscript = ""
        for await result in resultsStream {
            if result.isFinal {
                finalTranscript = result.transcript
                break
            }
        }

        logger.info("Barge-in transcription complete: '\(finalTranscript)'")
        return finalTranscript
    }

    /// Handle user's barge-in question with LLM
    private func handleBargeInQuestion(question: String) async {
        // First, check if this is a visual request
        if VisualRequestDetector.isVisualRequest(question) {
            await handleVisualRequest(question)
            return
        }

        guard let llmService = bargeInLLMService else {
            logger.error("No LLM service available for barge-in response")
            await resumeAfterBargeIn(userQuestion: question)
            return
        }

        state = .aiThinking

        // Build context including current topic and where we paused
        let topicContext = topic?.title ?? "the current topic"
        let systemPrompt = """
        You are a helpful tutor. The student was listening to a lecture about \(topicContext) and interrupted with a question.
        Answer their question concisely and helpfully. After answering, ask if they'd like to continue with the lecture or explore this topic further.
        Keep your response brief - this is a voice conversation.
        """

        let messages = [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user, content: question)
        ]

        do {
            var response = ""
            let stream = try await llmService.streamCompletion(messages: messages, config: .default)

            state = .aiSpeaking
            for await token in stream {
                response += token.content
                aiResponse = response

                if token.isDone {
                    break
                }
            }

            // Add to conversation history
            conversationHistory.append(ConversationMessage(
                text: response,
                isUser: false,
                timestamp: Date()
            ))

            // Speak the response using TTS
            await speakBargeInResponse(response)

            // After responding, wait for user to either ask more or signal to continue
            await waitForUserDecision()

        } catch {
            logger.error("LLM failed to respond to barge-in: \(error)")
            await resumeAfterBargeIn(userQuestion: question)
        }
    }

    /// Speak the barge-in AI response using TTS
    private func speakBargeInResponse(_ text: String) async {
        guard let ttsService = bargeInTTSService else {
            logger.warning("No TTS service available for barge-in response - text only")
            return
        }

        logger.info("Speaking barge-in response: '\(text.prefix(50))...'")

        do {
            let audioStream = try await ttsService.synthesize(text: text)

            for await chunk in audioStream {
                // Convert chunk to AVAudioPlayer and play
                do {
                    let player = try AVAudioPlayer(data: chunk.audioData)
                    player.volume = 1.0

                    // Play synchronously using a continuation
                    await withCheckedContinuation { continuation in
                        let delegate = AudioPlayerDelegate {
                            continuation.resume()
                        }
                        // Store delegate to prevent deallocation
                        self.audioDelegate = delegate
                        player.delegate = delegate
                        player.play()
                    }
                } catch {
                    logger.error("Failed to play TTS audio chunk: \(error)")
                }
            }

            logger.info("Finished speaking barge-in response")
        } catch {
            logger.error("TTS synthesis failed for barge-in response: \(error)")
        }
    }

    /// Wait for user to decide: continue lecture or ask more questions
    private func waitForUserDecision() async {
        logger.info("Waiting for user decision - continue or ask more?")
        state = .userSpeaking
        // User can either:
        // 1. Say nothing (silence) -> resume lecture
        // 2. Say "continue" or similar -> resume lecture
        // 3. Ask another question -> handle with LLM
        // This will be detected by the VAD and handled accordingly
    }

    // MARK: - Visual Request Handling

    /// Handle a visual request from the user during barge-in
    private func handleVisualRequest(_ request: String) async {
        logger.info("Handling visual request: \(request)")

        guard let topic = topic else {
            logger.warning("No topic available for visual request")
            await speakBargeInResponse("I don't have any visuals available for this session.")
            await waitForUserDecision()
            return
        }

        // Extract what the user is looking for
        let subject = VisualRequestDetector.extractVisualSubject(request)
        logger.info("Visual request subject: \(subject ?? "none")")

        // Search reference assets first
        let matchingAssets: [VisualAsset]
        if let subject = subject {
            matchingAssets = topic.findReferenceAssets(matching: subject)
        } else {
            // Show all reference assets if no specific subject
            matchingAssets = topic.referenceVisualAssets
        }

        // Also check embedded assets for the current segment
        let currentEmbeddedAssets = topic.visualAssetsForSegment(currentSegmentIndex)

        if !matchingAssets.isEmpty {
            // Found matching reference assets - show them
            logger.info("Found \(matchingAssets.count) matching reference assets")

            // Expand the visuals overlay to show the results
            visualsExpanded = true

            // Speak confirmation
            let assetNames = matchingAssets.compactMap { $0.title }.joined(separator: ", ")
            let response = matchingAssets.count == 1
                ? "Here's the \(matchingAssets.first?.title ?? "visual") you asked for."
                : "I found \(matchingAssets.count) relevant visuals: \(assetNames)"

            await speakBargeInResponse(response)

            // Add the matching assets to conversation as a special visual message
            conversationHistory.append(ConversationMessage(
                text: "[Visual: \(assetNames)]",
                isUser: false,
                timestamp: Date()
            ))

            await waitForUserDecision()

        } else if !currentEmbeddedAssets.isEmpty {
            // Show current segment's embedded assets
            logger.info("Showing \(currentEmbeddedAssets.count) embedded assets for current segment")

            visualsExpanded = true

            let assetNames = currentEmbeddedAssets.compactMap { $0.title }.joined(separator: ", ")
            let response = "Here are the visuals for what we're currently discussing: \(assetNames)"

            await speakBargeInResponse(response)
            await waitForUserDecision()

        } else {
            // No matching visuals found
            logger.info("No matching visuals found for request")

            let response = "I don't have a specific visual for that. Would you like me to continue with the lecture, or can I help you with something else?"

            await speakBargeInResponse(response)
            await waitForUserDecision()
        }
    }

    /// Resume lecture playback after handling barge-in
    private func resumeAfterBargeIn(userQuestion: String?) async {
        logger.info("Resuming lecture after barge-in")

        // Clear barge-in state
        bargeInAudioBuffers.removeAll()

        // Resume from where we paused
        state = .aiSpeaking
        isDirectStreamingMode = true

        // If we have remaining audio in the current segment, resume it
        // Otherwise, continue with next segment
        if audioPlayer != nil {
            audioPlayer?.play()
        } else {
            playNextAudioSegment()
        }
    }

    /// Configure AVAudioSession for audio playback (needed in direct streaming mode)
    private func configureAudioSessionForPlayback() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // Use playAndRecord to enable microphone for barge-in detection
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            logger.info("Audio session configured for playback with barge-in support")
        } catch {
            logger.error("Failed to configure audio session: \(error)")
        }
        #endif
    }

    /// Play the next audio segment from the queue
    /// Text is displayed ONLY when the audio for that segment starts playing
    private func playNextAudioSegment() {
        // Don't proceed if paused
        guard !isPaused else {
            logger.info("Playback paused, not starting next segment")
            return
        }

        guard !audioQueue.isEmpty else {
            isPlayingAudio = false
            logger.info("Audio queue empty, playback complete")

            // If we were in direct streaming mode and audio is done, handle completion
            if isDirectStreamingMode {
                // Save progress before transitioning
                if let topic = topic {
                    completedSegmentCount = totalSegments
                    saveProgress(to: topic)
                }

                // Check for auto-continue to next topic
                if autoContinueTopics && preGeneratedNextTopic != nil && !nextTopicAudioQueue.isEmpty {
                    logger.info("Auto-continuing to pre-generated next topic")
                    Task {
                        await transitionToNextTopic()
                    }
                } else if autoContinueTopics {
                    logger.info("Auto-continue enabled, trying to start next topic")
                    Task {
                        await tryStartNextTopic()
                    }
                } else {
                    logger.info("Direct streaming audio complete, transitioning to userSpeaking")
                    state = .userSpeaking
                    isDirectStreamingMode = false
                }
            }
            return
        }

        // Trigger pre-generation at 70% progress (or 3 segments remaining)
        if isDirectStreamingMode && autoContinueTopics && totalSegments > 0 {
            let progress = Double(completedSegmentCount) / Double(totalSegments)
            let remainingSegments = totalSegments - completedSegmentCount
            let shouldPreGenerate = !isPreGeneratingNextTopic &&
                                   preGeneratedNextTopic == nil &&
                                   (progress > 0.7 || remainingSegments <= 3)

            if shouldPreGenerate {
                logger.info("Triggering pre-generation at \(Int(progress * 100))% progress")
                Task {
                    await preGenerateNextTopic()
                }
            }
        }

        let segment = audioQueue.removeFirst()
        let audioData = segment.audio
        let text = segment.text
        let index = segment.index

        isPlayingAudio = true
        currentSegmentIndex = index

        // NOW display the text - synchronized with audio playback start
        if !text.isEmpty {
            aiResponse = text
            let message = ConversationMessage(
                text: text,
                isUser: false,
                timestamp: Date()
            )
            conversationHistory.append(message)

            // Set highlighted message for transcript scrolling
            highlightedMessageId = message.id

            logger.info("Displaying segment \(index) text (synced with audio start)")
        }

        // Log WAV header info for debugging
        if audioData.count >= 44 {
            let headerBytes = Array(audioData.prefix(44))
            let riffHeader = String(bytes: headerBytes[0..<4], encoding: .ascii) ?? "?"
            let waveHeader = String(bytes: headerBytes[8..<12], encoding: .ascii) ?? "?"
            logger.info("WAV header check - RIFF: '\(riffHeader)', WAVE: '\(waveHeader)', size: \(audioData.count) bytes")
        } else {
            logger.warning("Audio data too small for WAV header: \(audioData.count) bytes")
        }

        do {
            // The audio data is in WAV format from the TTS server
            audioPlayer = try AVAudioPlayer(data: audioData)

            // Enable metering for VU meter visualization
            audioPlayer?.isMeteringEnabled = true

            // Set up delegate to play next segment when this one finishes
            audioDelegate = AudioPlayerDelegate { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    // Mark segment as completed
                    self.completedSegmentCount = index + 1
                    self.playNextAudioSegment()
                }
            }
            audioPlayer?.delegate = audioDelegate

            // Set volume to maximum
            audioPlayer?.volume = 1.0

            // Start metering timer for VU meter updates during playback
            startAudioMeteringTimer()

            let prepared = audioPlayer?.prepareToPlay() ?? false
            logger.info("Audio player prepared: \(prepared), duration: \(audioPlayer?.duration ?? 0)s, format: \(audioPlayer?.format.description ?? "unknown")")

            let playing = audioPlayer?.play() ?? false
            logger.info("Audio player play() returned: \(playing), isPlaying: \(audioPlayer?.isPlaying ?? false)")

            if !playing {
                logger.error("AVAudioPlayer.play() returned false - audio will not play")
                // Mark as completed and try the next segment
                completedSegmentCount = index + 1
                playNextAudioSegment()
                return
            }

            logger.info("Playing segment \(index) audio (\(audioData.count) bytes), \(audioQueue.count) remaining in queue")
        } catch {
            logger.error("Failed to create AVAudioPlayer: \(error.localizedDescription)")
            // Mark as completed and try the next segment
            completedSegmentCount = index + 1
            playNextAudioSegment()
        }
    }

    private func bindToSessionManager(_ manager: SessionManager) {
        // Since SessionManager properties are @MainActor, we can access them safely here

        manager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self else { return }
                let oldState = self.state
                self.state = newState

                // When transitioning from aiSpeaking to userSpeaking, the AI turn is complete
                // Add the AI response to conversation history (but DON'T clear - let it remain visible)
                if oldState == .aiSpeaking && newState == .userSpeaking {
                    if !self.aiResponse.isEmpty && self.aiResponse != self.lastAiResponse {
                        self.conversationHistory.append(ConversationMessage(
                            text: self.aiResponse,
                            isUser: false,
                            timestamp: Date()
                        ))
                        self.lastAiResponse = self.aiResponse
                        // Only clear aiResponse after it's been added to history
                        self.aiResponse = ""
                    }
                    // DON'T clear userTranscript here - it should already be in history
                }

                // When transitioning from userSpeaking to processing/aiThinking, add user transcript
                if oldState == .userSpeaking && (newState == .processingUserUtterance || newState == .aiThinking) {
                    if !self.userTranscript.isEmpty && self.userTranscript != self.lastUserTranscript {
                        self.conversationHistory.append(ConversationMessage(
                            text: self.userTranscript,
                            isUser: true,
                            timestamp: Date()
                        ))
                        self.lastUserTranscript = self.userTranscript
                        // Only clear after adding to history
                        self.userTranscript = ""
                    }
                }
            }
            .store(in: &subscribers)

        manager.$userTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                // Only update userTranscript if it's non-empty or we're actively speaking
                // This prevents empty STT results from clearing valid transcripts
                if self.state == .userSpeaking && !newValue.isEmpty {
                    self.userTranscript = newValue
                } else if self.state == .idle && !newValue.isEmpty {
                    self.userTranscript = newValue
                }
                // Ignore empty values - don't clear the transcript mid-utterance
            }
            .store(in: &subscribers)

        manager.$aiResponse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                // Update AI response during AI-related states
                // Only update with non-empty values to prevent clearing
                if self.state == .aiThinking || self.state == .aiSpeaking || self.state == .processingUserUtterance {
                    if !newValue.isEmpty {
                        self.aiResponse = newValue
                    }
                }
            }
            .store(in: &subscribers)

        // Bind audio level for visualization
        manager.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)
    }
}


// MARK: - Session Help Sheet

/// In-app help for the session view explaining all UI elements and interactions
struct SessionHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Overview Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice conversations let you learn through natural dialogue with an AI tutor. Just speak and the tutor will respond.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Status Indicator Section
                Section("Status Indicator") {
                    StatusHelpRow(color: .gray, title: "Idle", description: "Ready to start. Tap the mic button to begin.")
                    StatusHelpRow(color: .green, title: "Listening", description: "Your voice is being heard. Speak naturally.")
                    StatusHelpRow(color: .orange, title: "Processing", description: "The AI is preparing a response.")
                    StatusHelpRow(color: .blue, title: "Speaking", description: "The AI tutor is responding.")
                    StatusHelpRow(color: .yellow, title: "Interrupted", description: "You spoke while the AI was talking. It paused to listen.")
                }

                // Controls Section
                Section("Controls") {
                    HelpItemRow(
                        icon: "mic.fill",
                        iconColor: .blue,
                        title: "Start Button",
                        description: "Tap to begin a voice conversation."
                    )
                    HelpItemRow(
                        icon: "stop.fill",
                        iconColor: .red,
                        title: "Stop Button",
                        description: "Tap to end the current session."
                    )
                    HelpItemRow(
                        icon: "playpause.fill",
                        iconColor: .blue,
                        title: "Pause/Resume",
                        description: "In lessons, pause to take a break without ending."
                    )
                }

                // Audio Level Section
                Section("Audio Level Meter") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The bars show audio volume in real-time:")
                            .font(.subheadline)

                        HStack {
                            Circle().fill(.blue).frame(width: 12, height: 12)
                            Text("Blue bars: AI is speaking")
                                .font(.caption)
                        }
                        HStack {
                            Circle().fill(.green).frame(width: 12, height: 12)
                            Text("Green bars: Your voice")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Tips Section
                Section("Tips") {
                    Label("Speak clearly at a normal pace", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green, .primary)
                    Label("You can interrupt anytime by speaking", systemImage: "hand.raised.fill")
                        .foregroundStyle(.orange, .primary)
                    Label("Use headphones for best results", systemImage: "airpodspro")
                        .foregroundStyle(.blue, .primary)
                    Label("Visual aids appear during lessons", systemImage: "photo.fill")
                        .foregroundStyle(.purple, .primary)
                }

                // Metrics Section
                Section("Session Metrics") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "timer")
                            Text("Latency: Response time in milliseconds. Lower is better.")
                                .font(.caption)
                        }
                        HStack {
                            Image(systemName: "dollarsign.circle")
                            Text("Cost: Estimated API usage cost. On-device is free.")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Session Help")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Helper row for status indicator help
private struct StatusHelpRow: View {
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

/// Helper row for controls and features help
private struct HelpItemRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

// MARK: - Preview

#Preview {
    SessionView()
        .environmentObject(AppState())
        .environmentObject(SessionActivityState())
}

#Preview("Session Help") {
    SessionHelpSheet()
}
