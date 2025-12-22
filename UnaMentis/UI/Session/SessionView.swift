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
    @StateObject private var viewModel: SessionViewModel

    /// The topic being studied (optional - for curriculum-based sessions)
    let topic: Topic?

    #if os(iOS)
    private static let backgroundGradientColors: [Color] = [Color(.systemBackground), Color(.systemGray6)]
    #else
    private static let backgroundGradientColors: [Color] = [Color(NSColor.windowBackgroundColor), Color(NSColor.controlBackgroundColor)]
    #endif

    public init(topic: Topic? = nil) {
        self.topic = topic
        // Initialize viewModel with topic context
        _viewModel = StateObject(wrappedValue: SessionViewModel(topic: topic))
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: Self.backgroundGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    // Status indicator
                    SessionStatusView(state: viewModel.state)
                        .padding(.top, 12)

                    // Transcript display - takes most of the space
                    TranscriptView(
                        conversationHistory: viewModel.conversationHistory,
                        userTranscript: viewModel.userTranscript,
                        aiResponse: viewModel.aiResponse
                    )
                    .frame(maxHeight: .infinity)

                    // Bottom control area - record button and VU meter side by side
                    HStack(alignment: .bottom, spacing: 16) {
                        // Main control button - smaller when recording, positioned left
                        SessionControlButton(
                            isActive: viewModel.isSessionActive,
                            isLoading: viewModel.isLoading,
                            action: {
                                await viewModel.toggleSession(appState: appState)
                            }
                        )

                        // VU meter - only visible when recording
                        if viewModel.isSessionActive {
                            AudioLevelView(level: viewModel.audioLevel)
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                                .transition(.opacity.combined(with: .scale))
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 20)
                    .animation(.spring(response: 0.3), value: viewModel.isSessionActive)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle(topic?.title ?? "Voice Session")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isSessionActive {
                        MetricsBadge(
                            latency: viewModel.lastLatency,
                            cost: viewModel.sessionCost
                        )
                    }
                }
            }
            #endif
            .sheet(isPresented: $viewModel.showSettings) {
                SessionSettingsView()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { viewModel.showError = false }
            } message: {
                Text(viewModel.errorMessage)
            }
            .task {
                // Auto-start session when initiated from a topic (lecture mode)
                if topic != nil && !viewModel.isSessionActive && !viewModel.isLoading {
                    await viewModel.toggleSession(appState: appState)
                }
            }
        }
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
    }
    
    private var statusColor: Color {
        switch state {
        case .idle: return .gray
        case .userSpeaking: return .green
        case .aiThinking: return .orange
        case .aiSpeaking: return .blue
        case .interrupted: return .yellow
        case .processingUserUtterance: return .purple
        case .error: return .red
        }
    }
}

// MARK: - Transcript View

struct TranscriptView: View {
    let conversationHistory: [ConversationMessage]
    let userTranscript: String
    let aiResponse: String

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
                            isUser: message.isUser
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
                        .fill(isUser ? Color.blue : Color(.systemGray5))
                        #else
                        .fill(isUser ? Color.blue : Color(NSColor.controlBackgroundColor))
                        #endif
                }
                .foregroundStyle(isUser ? .white : .primary)

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Audio Level View

struct AudioLevelView: View {
    let level: Float
    
    private let barCount = 20
    
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
    }
    
    private func barScale(for index: Int) -> CGFloat {
        // Convert dB to 0-1 range (-60dB to 0dB)
        let normalizedLevel = max(0, min(1, (level + 60) / 60))
        let threshold = Float(index) / Float(barCount)
        return normalizedLevel > threshold ? 1.0 : 0.2
    }
    
    private func barColor(for index: Int) -> Color {
        let ratio = Float(index) / Float(barCount)
        if ratio < 0.6 {
            return .green
        } else if ratio < 0.8 {
            return .yellow
        } else {
            return .red
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

// MARK: - Session Settings View

struct SessionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = SessionSettingsModel()

    var body: some View {
        NavigationStack {
            List {
                // MARK: Audio Settings
                Section("Audio") {
                    Picker("Sample Rate", selection: $settings.sampleRate) {
                        Text("16 kHz").tag(16000.0)
                        Text("24 kHz").tag(24000.0)
                        Text("48 kHz").tag(48000.0)
                    }

                    Picker("Buffer Size", selection: $settings.bufferSize) {
                        Text("256 (Low Latency)").tag(UInt32(256))
                        Text("512").tag(UInt32(512))
                        Text("1024 (Default)").tag(UInt32(1024))
                        Text("2048 (Stable)").tag(UInt32(2048))
                    }

                    Toggle("Voice Processing", isOn: $settings.enableVoiceProcessing)
                    Toggle("Echo Cancellation", isOn: $settings.enableEchoCancellation)
                    Toggle("Noise Suppression", isOn: $settings.enableNoiseSuppression)
                }

                // MARK: VAD Settings
                Section("Voice Activity Detection") {
                    Picker("VAD Provider", selection: $settings.vadProvider) {
                        ForEach(VADProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("VAD Threshold: \(settings.vadThreshold, specifier: "%.2f")")
                        Slider(value: $settings.vadThreshold, in: 0.1...0.9, step: 0.05)
                    }

                    Toggle("Enable Barge-In", isOn: $settings.enableBargeIn)

                    if settings.enableBargeIn {
                        VStack(alignment: .leading) {
                            Text("Barge-In Threshold: \(settings.bargeInThreshold, specifier: "%.2f")")
                            Slider(value: $settings.bargeInThreshold, in: 0.3...0.9, step: 0.05)
                        }
                    }
                }

                // MARK: Voice Settings
                Section("Voice (TTS)") {
                    Picker("Provider", selection: $settings.ttsProvider) {
                        ForEach(TTSProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    // Voice picker for self-hosted TTS providers
                    if settings.ttsProvider == .selfHosted || settings.ttsProvider == .vibeVoice {
                        Picker("Voice", selection: $settings.ttsVoice) {
                            ForEach(settings.availableVoices, id: \.self) { voice in
                                Text(settings.voiceDisplayName(voice)).tag(voice)
                            }
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Speaking Rate: \(settings.speakingRate, specifier: "%.1f")x")
                        Slider(value: $settings.speakingRate, in: 0.5...2.0, step: 0.1)
                    }

                    VStack(alignment: .leading) {
                        Text("Volume: \(Int(settings.volume * 100))%")
                        Slider(value: $settings.volume, in: 0.0...1.0, step: 0.1)
                    }
                }

                // MARK: LLM Settings
                Section("AI Model") {
                    Picker("Provider", selection: $settings.llmProvider) {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    Picker("Model", selection: $settings.llmModel) {
                        ForEach(settings.llmProvider.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Temperature: \(settings.temperature, specifier: "%.1f")")
                        Slider(value: $settings.temperature, in: 0.0...2.0, step: 0.1)
                    }

                    Stepper("Max Tokens: \(settings.maxTokens)", value: $settings.maxTokens, in: 256...4096, step: 256)
                }

                // MARK: Session Settings
                Section("Session") {
                    Toggle("Cost Tracking", isOn: $settings.enableCostTracking)
                    Toggle("Auto-Save Transcript", isOn: $settings.autoSaveTranscript)

                    Picker("Max Duration", selection: $settings.maxDuration) {
                        Text("30 minutes").tag(TimeInterval(1800))
                        Text("60 minutes").tag(TimeInterval(3600))
                        Text("90 minutes").tag(TimeInterval(5400))
                        Text("Unlimited").tag(TimeInterval(0))
                    }
                }
            }
            .navigationTitle("Session Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        settings.resetToDefaults()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Session Settings Model

@MainActor
class SessionSettingsModel: ObservableObject {
    private let defaults = UserDefaults.standard

    // Audio
    @Published var sampleRate: Double {
        didSet { defaults.set(sampleRate, forKey: "sampleRate") }
    }
    @Published var bufferSize: UInt32 {
        didSet { defaults.set(Int(bufferSize), forKey: "bufferSize") }
    }
    @Published var enableVoiceProcessing: Bool {
        didSet { defaults.set(enableVoiceProcessing, forKey: "enableVoiceProcessing") }
    }
    @Published var enableEchoCancellation: Bool {
        didSet { defaults.set(enableEchoCancellation, forKey: "enableEchoCancellation") }
    }
    @Published var enableNoiseSuppression: Bool {
        didSet { defaults.set(enableNoiseSuppression, forKey: "enableNoiseSuppression") }
    }

    // VAD
    @Published var vadProvider: VADProvider {
        didSet { defaults.set(vadProvider.rawValue, forKey: "vadProvider") }
    }
    @Published var vadThreshold: Float {
        didSet { defaults.set(vadThreshold, forKey: "vadThreshold") }
    }
    @Published var enableBargeIn: Bool {
        didSet { defaults.set(enableBargeIn, forKey: "enableBargeIn") }
    }
    @Published var bargeInThreshold: Float {
        didSet { defaults.set(bargeInThreshold, forKey: "bargeInThreshold") }
    }

    // TTS
    @Published var ttsProvider: TTSProvider {
        didSet { defaults.set(ttsProvider.rawValue, forKey: "ttsProvider") }
    }
    @Published var ttsVoice: String {
        didSet { defaults.set(ttsVoice, forKey: "ttsVoice") }
    }
    @Published var speakingRate: Float {
        didSet { defaults.set(speakingRate, forKey: "speakingRate") }
    }
    @Published var volume: Float {
        didSet { defaults.set(volume, forKey: "volume") }
    }

    /// Available TTS voices - includes both OpenAI-compatible and native VibeVoice voices
    var availableVoices: [String] {
        // OpenAI-compatible aliases + native VibeVoice voices
        ["alloy", "echo", "fable", "nova", "onyx", "shimmer",
         "Carter", "Davis", "Emma", "Frank", "Grace", "Mike", "Samuel"]
    }

    /// Voice display names with gender and description
    /// Covers both OpenAI-compatible aliases and native VibeVoice voices
    func voiceDisplayName(_ voiceId: String) -> String {
        switch voiceId.lowercased() {
        // OpenAI-compatible aliases (map to VibeVoice voices)
        case "alloy": return "Alloy → Carter - Male, Neutral"
        case "echo": return "Echo → Davis - Male, Warm"
        case "fable": return "Fable → Emma - Female, Storyteller"
        case "nova": return "Nova → Grace - Female, Friendly"
        case "onyx": return "Onyx → Frank - Male, Deep"
        case "shimmer": return "Shimmer → Mike - Male, Expressive"
        // Native VibeVoice voices
        case "carter": return "Carter - Male, Neutral"
        case "davis": return "Davis - Male, Warm"
        case "emma": return "Emma - Female, Storyteller"
        case "frank": return "Frank - Male, Deep"
        case "grace": return "Grace - Female, Friendly"
        case "mike": return "Mike - Male, Expressive"
        case "samuel": return "Samuel - Male, Indian Accent"
        default: return voiceId.capitalized
        }
    }

    // LLM
    @Published var llmProvider: LLMProvider {
        didSet {
            defaults.set(llmProvider.rawValue, forKey: "llmProvider")
            // Update model when provider changes
            if !llmProvider.availableModels.contains(llmModel) {
                llmModel = llmProvider.availableModels.first ?? ""
            }
        }
    }
    @Published var llmModel: String {
        didSet { defaults.set(llmModel, forKey: "llmModel") }
    }
    @Published var temperature: Float {
        didSet { defaults.set(temperature, forKey: "temperature") }
    }
    @Published var maxTokens: Int {
        didSet { defaults.set(maxTokens, forKey: "maxTokens") }
    }

    // Session
    @Published var enableCostTracking: Bool {
        didSet { defaults.set(enableCostTracking, forKey: "enableCostTracking") }
    }
    @Published var autoSaveTranscript: Bool {
        didSet { defaults.set(autoSaveTranscript, forKey: "autoSaveTranscript") }
    }
    @Published var maxDuration: TimeInterval {
        didSet { defaults.set(maxDuration, forKey: "maxDuration") }
    }

    init() {
        // Load saved values or use defaults
        self.sampleRate = defaults.object(forKey: "sampleRate") as? Double ?? 48000
        self.bufferSize = UInt32(defaults.object(forKey: "bufferSize") as? Int ?? 1024)
        self.enableVoiceProcessing = defaults.object(forKey: "enableVoiceProcessing") as? Bool ?? true
        self.enableEchoCancellation = defaults.object(forKey: "enableEchoCancellation") as? Bool ?? true
        self.enableNoiseSuppression = defaults.object(forKey: "enableNoiseSuppression") as? Bool ?? true

        self.vadProvider = defaults.string(forKey: "vadProvider")
            .flatMap { VADProvider(rawValue: $0) } ?? .silero
        self.vadThreshold = defaults.object(forKey: "vadThreshold") as? Float ?? 0.5
        self.enableBargeIn = defaults.object(forKey: "enableBargeIn") as? Bool ?? true
        self.bargeInThreshold = defaults.object(forKey: "bargeInThreshold") as? Float ?? 0.7

        self.ttsProvider = defaults.string(forKey: "ttsProvider")
            .flatMap { TTSProvider(rawValue: $0) } ?? .appleTTS
        self.ttsVoice = defaults.string(forKey: "ttsVoice") ?? "nova"
        self.speakingRate = defaults.object(forKey: "speakingRate") as? Float ?? 1.0
        self.volume = defaults.object(forKey: "volume") as? Float ?? 1.0

        self.llmProvider = defaults.string(forKey: "llmProvider")
            .flatMap { LLMProvider(rawValue: $0) } ?? .localMLX
        self.llmModel = defaults.string(forKey: "llmModel") ?? "ministral-3b (on-device)"
        self.temperature = defaults.object(forKey: "temperature") as? Float ?? 0.7
        self.maxTokens = defaults.object(forKey: "maxTokens") as? Int ?? 1024

        self.enableCostTracking = defaults.object(forKey: "enableCostTracking") as? Bool ?? true
        self.autoSaveTranscript = defaults.object(forKey: "autoSaveTranscript") as? Bool ?? true
        self.maxDuration = defaults.object(forKey: "maxDuration") as? TimeInterval ?? 5400
    }

    func resetToDefaults() {
        sampleRate = 48000
        bufferSize = 1024
        enableVoiceProcessing = true
        enableEchoCancellation = true
        enableNoiseSuppression = true
        vadProvider = .silero
        vadThreshold = 0.5
        enableBargeIn = true
        bargeInThreshold = 0.7
        ttsProvider = .appleTTS
        ttsVoice = "nova"
        speakingRate = 1.0
        volume = 1.0
        llmProvider = .localMLX
        llmModel = "ministral-3b (on-device)"
        temperature = 0.7
        maxTokens = 1024
        enableCostTracking = true
        autoSaveTranscript = true
        maxDuration = 5400
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

    /// VLCF transcript data for this topic (if available)
    @Published var vlcfTranscript: TopicTranscriptResponse?
    @Published var currentSegmentIndex: Int = 0

    /// Track last known transcripts to detect changes
    private var lastUserTranscript: String = ""
    private var lastAiResponse: String = ""

    private let logger = Logger(label: "com.unamentis.session.viewmodel")
    private var sessionManager: SessionManager?
    private var subscribers = Set<AnyCancellable>()

    /// Transcript streaming service for direct TTS playback (bypasses LLM)
    private let transcriptStreamer = TranscriptStreamingService()

    /// Audio player for direct transcript playback
    private var audioPlayer: AVAudioPlayer?

    /// Audio queue for sequential playback of transcript segments
    private var audioQueue: [Data] = []

    /// Whether audio is currently playing
    private var isPlayingAudio: Bool = false

    /// Audio player delegate for handling playback completion
    private var audioDelegate: AudioPlayerDelegate?

    /// Whether we're using direct transcript streaming (bypasses LLM)
    @Published var isDirectStreamingMode: Bool = false

    /// Topic for curriculum-based sessions (optional)
    let topic: Topic?

    /// Whether this is a lecture mode session (AI speaks first)
    var isLectureMode: Bool {
        topic != nil
    }

    /// Whether we have VLCF transcript data to use
    var hasTranscript: Bool {
        vlcfTranscript?.segments.isEmpty == false
    }

    init(topic: Topic? = nil) {
        self.topic = topic

        // If we have a topic, try to load transcript data
        if topic != nil {
            Task { await loadTranscriptData() }
        }
    }

    /// Load transcript data from local Core Data or fetch from server
    private func loadTranscriptData() async {
        guard let topic = topic,
              let topicId = topic.id else { return }

        // First, try to get transcript from local Core Data (document with transcript type)
        if let document = topic.documentSet.first(where: { $0.documentType == .transcript }),
           let transcriptData = document.decodedTranscript() {
            // Convert local TranscriptData to TopicTranscriptResponse format
            vlcfTranscript = TopicTranscriptResponse(
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

                vlcfTranscript = try await CurriculumService.shared.fetchTopicTranscript(
                    curriculumId: curriculumId.uuidString,
                    topicId: topicId.uuidString
                )
                logger.info("Fetched transcript from server: \(vlcfTranscript?.segments.count ?? 0) segments")
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

        // If we have VLCF transcript data, use it as the primary source
        if let transcript = vlcfTranscript, !transcript.segments.isEmpty {
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

    /// Generate system prompt that uses VLCF transcript content
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
        guard let transcript = vlcfTranscript,
              currentSegmentIndex < transcript.segments.count else {
            return nil
        }
        return transcript.segments[currentSegmentIndex]
    }

    /// Advance to the next transcript segment
    func advanceToNextSegment() -> Bool {
        guard let transcript = vlcfTranscript else { return false }
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
        defer { isLoading = false }

        // Get self-hosted server settings
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""

        // Check if we should use direct transcript streaming (bypasses LLM for pre-written content)
        // Use sourceId (UMLCF ID) for server communication, not the Core Data UUID
        if let topic = topic,
           let topicSourceId = topic.sourceId,
           let curriculum = topic.curriculum,
           let curriculumSourceId = curriculum.sourceId,
           selfHostedEnabled,
           !serverIP.isEmpty {

            // Check if server has transcript for this topic
            logger.info("Checking for direct transcript streaming for topic: \(topic.title ?? "unknown")")
            logger.info("Using sourceIds - curriculum: \(curriculumSourceId), topic: \(topicSourceId)")

            // Configure transcript streamer
            await transcriptStreamer.configure(host: serverIP, port: 8766)

            // Try direct streaming - this bypasses the LLM entirely
            isDirectStreamingMode = true
            state = .aiThinking  // Start with "AI thinking" while fetching transcript
            conversationHistory.removeAll()

            logger.info("Starting direct transcript streaming (bypassing LLM)")

            await transcriptStreamer.streamTopicAudio(
                curriculumId: curriculumSourceId,
                topicId: topicSourceId,
                voice: UserDefaults.standard.string(forKey: "ttsVoice") ?? "nova",
                onSegmentText: { [weak self] index, type, text in
                    Task { @MainActor in
                        guard let self = self else { return }
                        // Add segment text to conversation history for display
                        self.aiResponse = text
                        self.conversationHistory.append(ConversationMessage(
                            text: text,
                            isUser: false,
                            timestamp: Date()
                        ))
                        self.logger.info("Segment \(index): \(type) - \(text.prefix(50))...")
                    }
                },
                onSegmentAudio: { [weak self] index, audioData in
                    Task { @MainActor in
                        guard let self = self else { return }
                        // Transition to "AI speaking" when first audio arrives
                        if self.state == .aiThinking {
                            self.state = .aiSpeaking
                            self.logger.info("Transitioning to aiSpeaking - first audio received")
                        }
                        // Play the audio
                        self.playAudioData(audioData)
                    }
                },
                onComplete: { [weak self] in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.logger.info("Direct transcript streaming complete")
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
        await startLLMSession(appState: appState)
    }

    /// Start a traditional LLM-based session (used when no transcript available or direct streaming fails)
    private func startLLMSession(appState: AppState) async {
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
            guard let apiKey = await appState.apiKeys.getKey(.deepgram) else {
                errorMessage = "Deepgram API key not configured. Please add it in Settings or switch to on-device mode."
                showError = true
                return
            }
            sttService = DeepgramSTTService(apiKey: apiKey)
        case .assemblyAI:
            guard let apiKey = await appState.apiKeys.getKey(.assemblyAI) else {
                errorMessage = "AssemblyAI API key not configured. Please add it in Settings or switch to on-device mode."
                showError = true
                return
            }
            sttService = AssemblyAISTTService(apiKey: apiKey)
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
        case .elevenLabsFlash, .elevenLabsTurbo:
            guard let apiKey = await appState.apiKeys.getKey(.elevenLabs) else {
                errorMessage = "ElevenLabs API key not configured. Please add it in Settings or switch to Apple TTS."
                showError = true
                return
            }
            ttsService = ElevenLabsTTSService(apiKey: apiKey)
        case .deepgramAura2:
            guard let apiKey = await appState.apiKeys.getKey(.deepgram) else {
                errorMessage = "Deepgram API key not configured. Please add it in Settings or switch to Apple TTS."
                showError = true
                return
            }
            ttsService = DeepgramTTSService(apiKey: apiKey)
        default:
            logger.info("Using Apple TTS as default TTS provider")
            ttsService = AppleTTSService()
        }

        // Configure LLM based on settings
        logger.info("LLM provider setting: \(llmProviderSetting.rawValue)")
        logger.info("LLM config - selfHostedEnabled: \(selfHostedEnabled), serverIP: '\(serverIP)'")

        switch llmProviderSetting {
        case .localMLX:
            // On-device LLM not currently available (API incompatible), fall back to self-hosted
            logger.info("localMLX selected - falling back to SelfHostedLLMService (Ollama)")
            let llmModelSetting = UserDefaults.standard.string(forKey: "llmModel") ?? "llama3.2:3b"
            logger.info("LLM model from UserDefaults: '\(llmModelSetting)'")

            // Use configured server IP if available, otherwise fall back to localhost (simulator only)
            if selfHostedEnabled && !serverIP.isEmpty {
                logger.info("Creating SelfHostedLLMService.ollama(host: \(serverIP), model: \(llmModelSetting))")
                llmService = SelfHostedLLMService.ollama(host: serverIP, model: llmModelSetting)
            } else {
                logger.warning("No server IP configured - using localhost (only works on simulator)")
                llmService = SelfHostedLLMService.ollama(model: llmModelSetting)
            }
        case .anthropic:
            guard let apiKey = await appState.apiKeys.getKey(.anthropic) else {
                errorMessage = "Anthropic API key not configured. Please add it in Settings or switch to on-device mode."
                showError = true
                return
            }
            llmService = AnthropicLLMService(apiKey: apiKey)
        case .openAI:
            guard let apiKey = await appState.apiKeys.getKey(.openAI) else {
                errorMessage = "OpenAI API key not configured. Please add it in Settings or switch to on-device mode."
                showError = true
                return
            }
            llmService = OpenAILLMService(apiKey: apiKey)
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

            // Use configured server IP if available, otherwise fall back to localhost (simulator only)
            if selfHostedEnabled && !serverIP.isEmpty {
                logger.info("Creating SelfHostedLLMService.ollama(host: \(serverIP), model: \(llmModelSetting))")
                llmService = SelfHostedLLMService.ollama(host: serverIP, model: llmModelSetting)
            } else {
                logger.warning("No server IP configured - using localhost (only works on simulator)")
                llmService = SelfHostedLLMService.ollama(model: llmModelSetting)
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

        // Stop direct streaming if active
        if isDirectStreamingMode {
            await transcriptStreamer.stopStreaming()
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

        // Clear conversation history when session ends
        conversationHistory.removeAll()
        lastUserTranscript = ""
        lastAiResponse = ""
    }

    /// Queue audio data for sequential playback (for transcript streaming mode)
    private func playAudioData(_ audioData: Data) {
        audioQueue.append(audioData)
        logger.info("Queued audio segment (\(audioData.count) bytes), queue size: \(audioQueue.count)")

        // Start playback if not already playing
        if !isPlayingAudio {
            playNextAudioSegment()
        }
    }

    /// Play the next audio segment from the queue
    private func playNextAudioSegment() {
        guard !audioQueue.isEmpty else {
            isPlayingAudio = false
            logger.info("Audio queue empty, playback complete")

            // If we were in direct streaming mode and audio is done, transition state
            if isDirectStreamingMode {
                logger.info("Direct streaming audio complete, transitioning to userSpeaking")
                state = .userSpeaking
                isDirectStreamingMode = false
            }
            return
        }

        let audioData = audioQueue.removeFirst()
        isPlayingAudio = true

        do {
            // The audio data is in WAV format from the TTS server
            audioPlayer = try AVAudioPlayer(data: audioData)

            // Set up delegate to play next segment when this one finishes
            audioDelegate = AudioPlayerDelegate { [weak self] in
                Task { @MainActor in
                    self?.playNextAudioSegment()
                }
            }
            audioPlayer?.delegate = audioDelegate

            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            logger.info("Playing audio segment (\(audioData.count) bytes), \(audioQueue.count) remaining in queue")
        } catch {
            logger.error("Failed to play audio: \(error)")
            // Try the next segment
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


// MARK: - Preview

#Preview {
    SessionView()
        .environmentObject(AppState())
}
