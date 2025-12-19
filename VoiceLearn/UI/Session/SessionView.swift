// VoiceLearn - Session View
// Main voice conversation UI
//
// Part of UI/UX (TDD Section 10)

import SwiftUI
import Combine
import Logging

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
                
                VStack(spacing: 24) {
                    // Status indicator
                    SessionStatusView(state: viewModel.state)
                        .padding(.top, 20)
                    
                    Spacer()
                    
                    // Transcript display
                    TranscriptView(
                        userTranscript: viewModel.userTranscript,
                        aiResponse: viewModel.aiResponse
                    )
                    .frame(maxHeight: 300)
                    
                    Spacer()
                    
                    // Audio level visualizer
                    AudioLevelView(level: viewModel.audioLevel)
                        .frame(height: 60)
                    
                    // Main control button
                    SessionControlButton(
                        isActive: viewModel.isSessionActive,
                        isLoading: viewModel.isLoading,
                        action: {
                            await viewModel.toggleSession(appState: appState)
                        }
                    )
                    .padding(.bottom, 20)

                    // Debug LLM Test Button (for testing without voice)
                    #if DEBUG
                    VStack(spacing: 8) {
                        Button("Test LLM Directly") {
                            Task {
                                await viewModel.testOnDeviceLLM()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)

                        if !viewModel.debugTestResult.isEmpty {
                            Text(viewModel.debugTestResult)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .lineLimit(3)
                        }
                    }
                    .padding(.bottom, 20)
                    #endif
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Voice Session")
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
    let userTranscript: String
    let aiResponse: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !userTranscript.isEmpty {
                    TranscriptBubble(
                        text: userTranscript,
                        isUser: true
                    )
                }
                
                if !aiResponse.isEmpty {
                    TranscriptBubble(
                        text: aiResponse,
                        isUser: false
                    )
                }
            }
            .padding()
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 16)
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
    
    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isActive ? Color.red : Color.blue)
                    .frame(width: 80, height: 80)
                    .shadow(color: (isActive ? Color.red : Color.blue).opacity(0.4), radius: 10)
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: isActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isLoading)
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(.spring(response: 0.3), value: isActive)
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
    @Published var speakingRate: Float {
        didSet { defaults.set(speakingRate, forKey: "speakingRate") }
    }
    @Published var volume: Float {
        didSet { defaults.set(volume, forKey: "volume") }
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

    private let logger = Logger(label: "com.voicelearn.session.viewmodel")
    private var sessionManager: SessionManager?
    private var subscribers = Set<AnyCancellable>()

    /// Topic for curriculum-based sessions (optional)
    let topic: Topic?

    /// Whether this is a lecture mode session (AI speaks first)
    var isLectureMode: Bool {
        topic != nil
    }

    init(topic: Topic? = nil) {
        self.topic = topic
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
        if isSessionActive {
            await stopSession()
        } else {
            await startSession(appState: appState)
        }
    }
    
    private func startSession(appState: AppState) async {
        isLoading = true
        defer { isLoading = false }

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
            // Use SelfHostedTTSService to connect to Piper server
            let ttsVoiceSetting = UserDefaults.standard.string(forKey: "ttsVoice") ?? "nova"
            if selfHostedEnabled && !serverIP.isEmpty {
                logger.info("Using self-hosted TTS (Piper) at \(serverIP):11402 with voice: \(ttsVoiceSetting)")
                ttsService = SelfHostedTTSService.piper(host: serverIP, voice: ttsVoiceSetting)
            } else {
                logger.warning("Self-hosted TTS selected but no server IP configured - falling back to Apple TTS")
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
        
        if let manager = sessionManager {
            await manager.stopSession()
        }
        
        sessionManager = nil
        subscribers.removeAll()
        state = .idle
    }
    
    private func bindToSessionManager(_ manager: SessionManager) {
        // Since SessionManager properties are @MainActor, we can access them safely here
        
        manager.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$state)
            
        manager.$userTranscript
            .receive(on: DispatchQueue.main)
            .assign(to: &$userTranscript)
            
        manager.$aiResponse
            .receive(on: DispatchQueue.main)
            .assign(to: &$aiResponse)

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
