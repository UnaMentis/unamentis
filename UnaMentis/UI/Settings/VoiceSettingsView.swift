// UnaMentis - Voice Settings View
// Consolidated voice model controls for STT, TTS, VAD, Audio, and LLM
//
// Part of UI/Settings

import SwiftUI

/// Consolidated voice settings view containing all voice model controls.
/// This view is accessible from both the main Settings and during voice sessions.
///
/// Contains:
/// - Audio Settings (Sample Rate, Voice Processing, Echo Cancellation, Noise Suppression)
/// - Voice Detection (VAD Threshold, Interruption Threshold, Barge-In)
/// - Speech Recognition (STT Provider)
/// - Language Model (LLM Provider, Model, Temperature, Max Tokens)
/// - Voice Output (TTS Provider, Voice, Speaking Rate, Chatterbox settings)
/// - Presets for quick configuration
public struct VoiceSettingsView: View {
    @StateObject private var viewModel = VoiceSettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Whether to show the done button (true when presented as sheet, false when pushed)
    var showDoneButton: Bool = false

    public init(showDoneButton: Bool = false) {
        self.showDoneButton = showDoneButton
    }

    public var body: some View {
        List {
            // Quick Presets
            presetsSection

            // Audio Settings
            audioSection

            // VAD Settings
            vadSection

            // STT Settings
            sttSection

            // LLM Settings
            llmSection

            // TTS Settings
            ttsSection

            // Curriculum Playback Settings
            curriculumSection
        }
        .navigationTitle("Voice Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if showDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #endif
        .task {
            await viewModel.loadAsync()
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        Section {
            Button {
                viewModel.applyPreset(.balanced)
            } label: {
                Label("Balanced (Default)", systemImage: "slider.horizontal.3")
            }

            Button {
                viewModel.applyPreset(.lowLatency)
            } label: {
                Label("Low Latency", systemImage: "hare")
            }

            Button {
                viewModel.applyPreset(.highQuality)
            } label: {
                Label("High Quality", systemImage: "waveform")
            }

            Button {
                viewModel.applyPreset(.costOptimized)
            } label: {
                Label("Cost Optimized", systemImage: "dollarsign.circle")
            }

            if viewModel.selfHostedEnabled {
                Button {
                    viewModel.applyPreset(.selfHosted)
                } label: {
                    Label("Self-Hosted (Free)", systemImage: "server.rack")
                }
            }
        } header: {
            Text("Presets")
        } footer: {
            Text("Quick configurations for common use cases. Custom adjustments override presets.")
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        Section {
            Picker("Sample Rate", selection: $viewModel.sampleRate) {
                Text("16 kHz").tag(16000.0)
                Text("24 kHz").tag(24000.0)
                Text("48 kHz").tag(48000.0)
            }
            .accessibilityHint("Audio quality setting. Higher rates sound better but use more data.")

            Toggle("Voice Processing", isOn: $viewModel.enableVoiceProcessing)
                .accessibilityHint("Enhances voice clarity using Apple's audio processing")

            Toggle("Echo Cancellation", isOn: $viewModel.enableEchoCancellation)
                .accessibilityHint("Prevents the microphone from picking up the AI's voice through speakers")

            Toggle("Noise Suppression", isOn: $viewModel.enableNoiseSuppression)
                .accessibilityHint("Filters background noise like fans or traffic")
        } header: {
            HStack {
                Text("Audio")
                Spacer()
                InfoButton(title: "Audio Settings", content: HelpContent.Settings.sampleRate)
            }
        }
    }

    // MARK: - VAD Section

    private var vadSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Detection Threshold: \(viewModel.vadThreshold, specifier: "%.2f")")
                    InfoButton(title: "Detection Threshold", content: HelpContent.Settings.vadThreshold)
                }
                Slider(value: $viewModel.vadThreshold, in: 0.3...0.9)
                    .accessibilityLabel("Voice detection threshold")
                    .accessibilityValue(String(format: "%.2f", viewModel.vadThreshold))
                    .accessibilityHint("Lower values detect quieter speech but may pick up noise")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Interruption Threshold: \(viewModel.bargeInThreshold, specifier: "%.2f")")
                    InfoButton(title: "Interruption Threshold", content: HelpContent.Settings.interruptionThreshold)
                }
                Slider(value: $viewModel.bargeInThreshold, in: 0.5...0.95)
                    .accessibilityLabel("Interruption threshold")
                    .accessibilityValue(String(format: "%.2f", viewModel.bargeInThreshold))
                    .accessibilityHint("How loud you need to speak to interrupt the AI")
            }

            Toggle("Enable Interruptions", isOn: $viewModel.enableBargeIn)
                .accessibilityHint("When enabled, speaking while the AI talks will pause it to listen")
        } header: {
            Text("Voice Detection")
        }
    }

    // MARK: - STT Section

    private var sttSection: some View {
        Section {
            Picker("Provider", selection: $viewModel.sttProvider) {
                Text("GLM-ASR (On-Device)").tag(STTProvider.glmASROnDevice)
                Text("Groq Whisper (Free)").tag(STTProvider.groqWhisper)
                Text("Deepgram Nova-3").tag(STTProvider.deepgramNova3)
                Text("AssemblyAI").tag(STTProvider.assemblyAI)
                Text("Apple Speech").tag(STTProvider.appleSpeech)
            }

            if !viewModel.sttProvider.requiresNetwork {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Works offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Speech Recognition")
        }
    }

    // MARK: - LLM Section

    private var llmSection: some View {
        Section {
            Picker("Provider", selection: $viewModel.llmProvider) {
                Text("On-Device (llama.cpp)").tag(LLMProvider.localMLX)
                Text("Anthropic Claude").tag(LLMProvider.anthropic)
                Text("OpenAI").tag(LLMProvider.openAI)
                Text("Self-Hosted").tag(LLMProvider.selfHosted)
            }
            .accessibilityHint("Choose where AI processing happens")

            if viewModel.llmProvider != .localMLX {
                Picker("Model", selection: $viewModel.llmModel) {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        if let info = viewModel.modelInfo(for: model),
                           let context = info.contextWindowFormatted {
                            HStack {
                                Text(model)
                                Spacer()
                                Text(context)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }.tag(model)
                        } else {
                            Text(model).tag(model)
                        }
                    }
                }
                .accessibilityHint("Larger models are smarter but slower and more expensive")

                // Show selected model context window if available
                if viewModel.llmProvider == .selfHosted,
                   let info = viewModel.modelInfo(for: viewModel.llmModel),
                   let context = info.contextWindowFormatted {
                    HStack {
                        Text("Context Window")
                        Spacer()
                        Text(context)
                            .foregroundStyle(.blue)
                            .fontWeight(.medium)
                    }
                    .font(.footnote)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature: \(viewModel.temperature, specifier: "%.1f")")
                    InfoButton(title: "Temperature", content: HelpContent.Settings.temperature)
                }
                Slider(value: $viewModel.temperature, in: 0...1)
                    .accessibilityLabel("Temperature")
                    .accessibilityValue(String(format: "%.1f", viewModel.temperature))
                    .accessibilityHint("Controls response creativity. Lower for factual, higher for creative.")
            }

            HStack {
                Stepper("Max Tokens: \(viewModel.maxTokens)", value: $viewModel.maxTokens, in: 256...4096, step: 256)
                    .accessibilityHint("Maximum response length. One token is roughly 4 characters.")
                InfoButton(title: "Max Tokens", content: HelpContent.Settings.maxTokens)
            }

            if !viewModel.llmProvider.requiresNetwork {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Works offline - Free")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text("Language Model")
                Spacer()
                InfoButton(title: "Language Model", content: HelpContent.Settings.llmProvider)
            }
        }
    }

    // MARK: - TTS Section

    private var ttsSection: some View {
        Section {
            Picker("Provider", selection: $viewModel.ttsProvider) {
                Text("Apple TTS (On-Device)").tag(TTSProvider.appleTTS)
                if viewModel.selfHostedEnabled {
                    Text("Piper (22kHz)").tag(TTSProvider.selfHosted)
                    Text("VibeVoice (24kHz)").tag(TTSProvider.vibeVoice)
                    Text("Chatterbox (24kHz)").tag(TTSProvider.chatterbox)
                }
                Text("ElevenLabs").tag(TTSProvider.elevenLabsFlash)
                Text("Deepgram Aura").tag(TTSProvider.deepgramAura2)
            }
            .accessibilityHint("Choose the voice synthesis provider")

            // Voice picker for self-hosted TTS providers (not Chatterbox, which has its own settings)
            if viewModel.ttsProvider == .selfHosted || viewModel.ttsProvider == .vibeVoice {
                Picker("Voice", selection: $viewModel.ttsVoice) {
                    let voices = viewModel.discoveredVoices.isEmpty ? viewModel.defaultTTSVoices : viewModel.discoveredVoices
                    ForEach(voices, id: \.self) { voice in
                        Text(viewModel.voiceDisplayName(voice)).tag(voice)
                    }
                }
                .accessibilityHint("Select the AI tutor's voice")
            }

            // Chatterbox-specific settings
            if viewModel.ttsProvider == .chatterbox {
                NavigationLink {
                    ChatterboxSettingsView()
                } label: {
                    HStack {
                        Label("Chatterbox Settings", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text(viewModel.chatterboxPresetName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Quick emotion slider for convenience
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Emotion Level")
                        Spacer()
                        Text(String(format: "%.1f", viewModel.chatterboxExaggeration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.chatterboxExaggeration, in: 0.0...1.5, step: 0.1)
                        .accessibilityLabel("Emotion level")
                        .accessibilityHint("Adjust voice expressiveness from monotone to dramatic")
                }
            }

            // Show TTS provider info
            if viewModel.ttsProvider == .selfHosted || viewModel.ttsProvider == .vibeVoice || viewModel.ttsProvider == .chatterbox {
                HStack {
                    Text("Port")
                    Spacer()
                    Text("\(viewModel.ttsProvider.defaultPort)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Sample Rate")
                    Spacer()
                    Text("\(Int(viewModel.ttsProvider.sampleRate)) Hz")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speaking Rate: \(viewModel.speakingRate, specifier: "%.1f")x")
                    InfoButton(title: "Speaking Rate", content: HelpContent.Settings.speakingRate)
                }
                Slider(value: $viewModel.speakingRate, in: 0.5...2.0)
                    .accessibilityLabel("Speaking rate")
                    .accessibilityValue(String(format: "%.1f times speed", viewModel.speakingRate))
                    .accessibilityHint("Adjust how fast the AI speaks")
            }

            // TTS Playback Tuning link
            NavigationLink {
                TTSPlaybackTuningView()
            } label: {
                Label("Playback Tuning", systemImage: "waveform.path")
            }

            if !viewModel.ttsProvider.requiresAPIKey {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(viewModel.ttsProvider == .selfHosted ? "Uses Piper server - Free" :
                         viewModel.ttsProvider == .vibeVoice ? "Uses VibeVoice server - Free" :
                         viewModel.ttsProvider == .chatterbox ? "Uses Chatterbox server - Free" :
                         "Works offline - Free")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text("Voice Output")
                Spacer()
                InfoButton(title: "Voice Settings", content: HelpContent.Settings.ttsProvider)
            }
        }
    }

    // MARK: - Curriculum Playback Section

    private var curriculumSection: some View {
        Section {
            Toggle("Auto-continue to next topic", isOn: $viewModel.autoContinueTopics)
                .accessibilityHint("When enabled, automatically starts the next topic when the current one finishes")

            Text("When a topic completes, seamlessly continue to the next topic in the curriculum with an audio announcement.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Curriculum Playback")
        }
    }
}

// MARK: - Voice Settings View Model

@MainActor
class VoiceSettingsViewModel: ObservableObject {
    private let defaults = UserDefaults.standard

    // Audio
    @AppStorage("sampleRate") var sampleRate: Double = 48000
    @AppStorage("enableVoiceProcessing") var enableVoiceProcessing = true
    @AppStorage("enableEchoCancellation") var enableEchoCancellation = true
    @AppStorage("enableNoiseSuppression") var enableNoiseSuppression = true

    // VAD
    @AppStorage("vadThreshold") var vadThreshold: Double = 0.5
    @AppStorage("bargeInThreshold") var bargeInThreshold: Double = 0.7
    @AppStorage("enableBargeIn") var enableBargeIn = true

    // STT
    @Published var sttProvider: STTProvider {
        didSet {
            guard sttProvider != oldValue else { return }
            defaults.set(sttProvider.rawValue, forKey: "sttProvider")
        }
    }

    // LLM
    @Published var llmProvider: LLMProvider {
        didSet {
            guard llmProvider != oldValue else { return }
            defaults.set(llmProvider.rawValue, forKey: "llmProvider")
        }
    }
    @AppStorage("llmModel") var llmModel = "llama3.2:3b"
    @AppStorage("temperature") var temperature: Double = 0.7
    @AppStorage("maxTokens") var maxTokens = 1024

    // TTS
    @Published var ttsProvider: TTSProvider {
        didSet {
            guard ttsProvider != oldValue else { return }
            defaults.set(ttsProvider.rawValue, forKey: "ttsProvider")
        }
    }
    @AppStorage("speakingRate") var speakingRate: Double = 1.0
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"

    // Chatterbox TTS settings
    @AppStorage("chatterbox_exaggeration") var chatterboxExaggeration: Double = 0.5
    @AppStorage("chatterbox_preset") var chatterboxPresetRaw: String = "default"

    // Self-hosted
    @AppStorage("selfHostedEnabled") var selfHostedEnabled: Bool = false

    // Curriculum Playback
    @AppStorage("autoContinueTopics") var autoContinueTopics: Bool = true

    // Discovered capabilities
    @Published var discoveredModels: [String] = []
    @Published var discoveredPiperVoices: [String] = []
    @Published var discoveredVibeVoiceVoices: [String] = []

    // Management API model info (includes context windows)
    @Published var managementModels: [ManagementModelInfo] = []

    /// Get management model info for a model name
    func modelInfo(for name: String) -> ManagementModelInfo? {
        managementModels.first { $0.name == name }
    }

    /// Chatterbox preset display name
    var chatterboxPresetName: String {
        ChatterboxPreset(rawValue: chatterboxPresetRaw)?.displayName ?? "Default"
    }

    /// Get discovered voices for the currently selected TTS provider
    var discoveredVoices: [String] {
        switch ttsProvider {
        case .selfHosted:
            return discoveredPiperVoices
        case .vibeVoice:
            return discoveredVibeVoiceVoices
        default:
            return []
        }
    }

    /// Default TTS voices
    var defaultTTSVoices: [String] {
        ["alloy", "echo", "fable", "nova", "onyx", "shimmer",
         "Carter", "Davis", "Emma", "Frank", "Grace", "Mike", "Samuel"]
    }

    /// Voice display names
    func voiceDisplayName(_ voiceId: String) -> String {
        switch voiceId.lowercased() {
        case "alloy": return "Alloy - Carter - Male, Neutral"
        case "echo": return "Echo - Davis - Male, Warm"
        case "fable": return "Fable - Emma - Female, Storyteller"
        case "nova": return "Nova - Grace - Female, Friendly"
        case "onyx": return "Onyx - Frank - Male, Deep"
        case "shimmer": return "Shimmer - Mike - Male, Expressive"
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

    /// Available models for current provider
    var availableModels: [String] {
        switch llmProvider {
        case .openAI:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
        case .anthropic:
            return ["claude-3-5-sonnet-20241022", "claude-3-haiku-20240307"]
        case .selfHosted:
            if !discoveredModels.isEmpty {
                return discoveredModels
            }
            return ["qwen2.5:32b", "qwen2.5:7b", "llama3.2:3b", "mistral:7b"]
        case .localMLX:
            return ["ministral-3b (on-device)"]
        }
    }

    init() {
        // Load persisted provider settings
        if let sttRaw = defaults.string(forKey: "sttProvider"),
           let stt = STTProvider(rawValue: sttRaw) {
            self.sttProvider = stt
        } else {
            self.sttProvider = .glmASROnDevice
        }

        if let llmRaw = defaults.string(forKey: "llmProvider"),
           let llm = LLMProvider(rawValue: llmRaw) {
            self.llmProvider = llm
        } else {
            self.llmProvider = .localMLX
        }

        if let ttsRaw = defaults.string(forKey: "ttsProvider"),
           let tts = TTSProvider(rawValue: ttsRaw) {
            self.ttsProvider = tts
        } else {
            self.ttsProvider = .appleTTS
        }
    }

    /// Load async data (capabilities discovery)
    func loadAsync() async {
        if selfHostedEnabled {
            let primaryServerIP = defaults.string(forKey: "primaryServerIP") ?? ""
            if !primaryServerIP.isEmpty {
                // Try Management API first (includes context window info)
                let mgmtModels = await ServerConfigManager.shared.discoverManagementModels(host: primaryServerIP)
                if !mgmtModels.isEmpty {
                    managementModels = mgmtModels
                    // Extract LLM model names for the picker
                    discoveredModels = mgmtModels.filter { $0.type == "llm" }.map { $0.name }
                } else {
                    // Fallback to direct discovery
                    let capabilities = await ServerConfigManager.shared.discoverCapabilities(host: primaryServerIP)
                    discoveredModels = capabilities.llmModels
                    discoveredPiperVoices = capabilities.piperVoices
                    discoveredVibeVoiceVoices = capabilities.vibeVoiceVoices
                }

                // Still get TTS voices from direct discovery if Management API doesn't have them
                if discoveredPiperVoices.isEmpty && discoveredVibeVoiceVoices.isEmpty {
                    let capabilities = await ServerConfigManager.shared.discoverCapabilities(host: primaryServerIP)
                    discoveredPiperVoices = capabilities.piperVoices
                    discoveredVibeVoiceVoices = capabilities.vibeVoiceVoices
                }
            }
        }
    }

    // MARK: - Presets

    enum Preset {
        case balanced, lowLatency, highQuality, costOptimized, selfHosted
    }

    func applyPreset(_ preset: Preset) {
        switch preset {
        case .balanced:
            llmProvider = .openAI
            sampleRate = 48000
            vadThreshold = 0.5
            llmModel = "gpt-4o"
            temperature = 0.7
            maxTokens = 1024

        case .lowLatency:
            llmProvider = .openAI
            sampleRate = 24000
            vadThreshold = 0.4
            llmModel = "gpt-4o-mini"
            temperature = 0.5
            maxTokens = 512

        case .highQuality:
            llmProvider = .openAI
            sampleRate = 48000
            vadThreshold = 0.6
            llmModel = "gpt-4o"
            temperature = 0.8
            maxTokens = 2048

        case .costOptimized:
            sttProvider = .glmASROnDevice
            llmProvider = .localMLX
            ttsProvider = .appleTTS
            sampleRate = 16000
            vadThreshold = 0.5
            temperature = 0.5
            maxTokens = 512

        case .selfHosted:
            llmProvider = .selfHosted
            ttsProvider = .selfHosted
            sampleRate = 48000
            vadThreshold = 0.5
            llmModel = "qwen2.5:7b"
            temperature = 0.7
            maxTokens = 1024
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VoiceSettingsView()
    }
}

#Preview("Voice Settings Sheet") {
    VoiceSettingsView(showDoneButton: true)
}
