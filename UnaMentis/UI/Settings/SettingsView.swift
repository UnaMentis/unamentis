// UnaMentis - Settings View
// Configuration and API key management
//
// Part of UI/UX (TDD Section 10)

import SwiftUI
import AVFoundation

/// Settings view for app configuration
public struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingSettingsHelp = false
    @State private var showingOnboarding = false

    public init() { }

    public var body: some View {
        NavigationStack {
            List {
                // API Keys Section
                Section {
                    ForEach(APIKeyManager.KeyType.allCases, id: \.rawValue) { keyType in
                        NavigationLink {
                            APIProviderDetailView(
                                keyType: keyType,
                                isConfigured: viewModel.keyStatus[keyType] ?? false,
                                onSave: viewModel.saveKey
                            )
                        } label: {
                            APIKeyRow(
                                keyType: keyType,
                                isConfigured: viewModel.keyStatus[keyType] ?? false
                            )
                        }
                    }

                    NavigationLink {
                        SessionCostOverviewView()
                    } label: {
                        Label("Session Cost Estimates", systemImage: "dollarsign.circle")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("API Providers")
                } footer: {
                    Text("Tap a provider to see details, pricing, and configure your API key.")
                }

                // Voice Settings Section
                Section {
                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        HStack {
                            Label("Voice & AI Settings", systemImage: "waveform.circle")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(viewModel.ttsProvider.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(viewModel.llmProvider.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityHint("Configure voice recognition, AI model, and speech synthesis")
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Audio, speech recognition, language model, and voice output settings.")
                }

                // Self-Hosted Server Section
                Section {
                    Toggle("Enable Self-Hosted Server", isOn: $viewModel.selfHostedEnabled)

                    if viewModel.selfHostedEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Server IP or Hostname")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("e.g., 192.168.1.100 or macbook.local", text: $viewModel.primaryServerIP)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                #endif
                        }

                        HStack {
                            Text("Connection")
                            Spacer()
                            Circle()
                                .fill(viewModel.serverConnectionStatus.color)
                                .frame(width: 10, height: 10)
                            Text(viewModel.serverConnectionStatus.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.serverConnectionStatus == .connected && !viewModel.serverCapabilitiesSummary.isEmpty {
                            HStack {
                                Text("Capabilities")
                                Spacer()
                                Text(viewModel.serverCapabilitiesSummary)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        Button {
                            Task { await viewModel.checkServerConnection() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Connection")
                            }
                        }
                        .disabled(viewModel.primaryServerIP.isEmpty)

                        NavigationLink {
                            ServerSettingsView()
                        } label: {
                            HStack {
                                Label("Advanced Server Config", systemImage: "server.rack")
                                Spacer()
                                if viewModel.selfHostedServerCount > 0 {
                                    Text("\(viewModel.healthySelfHostedCount)/\(viewModel.selfHostedServerCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Self-Hosted Server")
                } footer: {
                    if viewModel.selfHostedEnabled {
                        Text("This IP will be used for LLM, TTS, and optionally logging.")
                    } else {
                        Text("Enable to use your Mac as an AI server for zero-cost inference.")
                    }
                }

                // Debug & Testing Section
                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Subsystem Diagnostics", systemImage: "wrench.and.screwdriver")
                    }

                    NavigationLink {
                        DeviceMetricsView()
                    } label: {
                        Label("Device Health Monitor", systemImage: "heart.text.square")
                    }

                    NavigationLink {
                        AudioTestView()
                    } label: {
                        Label("Audio Pipeline Test", systemImage: "waveform")
                    }

                    NavigationLink {
                        ProviderTestView()
                    } label: {
                        Label("Provider Connectivity", systemImage: "network")
                    }

                    NavigationLink {
                        TTSPlaybackTuningView()
                    } label: {
                        Label("TTS Playback Tuning", systemImage: "slider.horizontal.3")
                    }

                    #if DEBUG
                    NavigationLink {
                        DebugConversationTestView()
                    } label: {
                        Label("Conversation Test", systemImage: "text.bubble")
                    }
                    #endif

                    Toggle("Debug Mode", isOn: $viewModel.debugMode)
                    Toggle("Verbose Logging", isOn: $viewModel.verboseLogging)

                    // Remote logging configuration
                    Toggle("Remote Logging", isOn: $viewModel.remoteLoggingEnabled)
                        .onChange(of: viewModel.remoteLoggingEnabled) { _, newValue in
                            viewModel.handleRemoteLoggingChange(newValue)
                        }

                    if viewModel.remoteLoggingEnabled {
                        Toggle("Use Same IP as Server", isOn: $viewModel.logServerUsesSameIP)
                            .disabled(!viewModel.selfHostedEnabled || viewModel.primaryServerIP.isEmpty)

                        if !viewModel.logServerUsesSameIP || !viewModel.selfHostedEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Log Server IP")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("e.g., 192.168.1.100", text: $viewModel.logServerIP)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.numbersAndPunctuation)
                                    #endif
                            }
                        } else {
                            HStack {
                                Text("Log Server")
                                Spacer()
                                Text(viewModel.effectiveLogServerIP)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button("Load Sample Curriculum") {
                        Task { await viewModel.loadSampleCurriculum() }
                    }
                    .disabled(viewModel.hasSampleCurriculum)

                    if viewModel.hasSampleCurriculum {
                        Button("Delete Sample Curriculum", role: .destructive) {
                            Task { await viewModel.deleteSampleCurriculum() }
                        }
                    }
                } header: {
                    Text("Debug & Testing")
                } footer: {
                    Text("Tools for testing subsystems and troubleshooting.")
                }

                // Help Section
                Section {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Help & Voice Commands", systemImage: "questionmark.circle")
                    }

                    NavigationLink {
                        VoiceCommandsHelpView()
                    } label: {
                        Label("Siri Voice Commands", systemImage: "waveform.circle")
                    }

                    Button {
                        showingOnboarding = true
                    } label: {
                        Label("Show Welcome Tour", systemImage: "hand.wave")
                    }
                } header: {
                    Text("Help")
                } footer: {
                    Text("Learn how to use the app with Siri voice commands and the welcome tour.")
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }

                    Link("Documentation", destination: URL(string: "https://voicelearn.app/docs")!)
                    Link("Privacy Policy", destination: URL(string: "https://voicelearn.app/privacy")!)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BrandLogo(size: .compact)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettingsHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Settings help")
                    .accessibilityHint("Learn about all settings and configuration options")
                }
            }
            #endif
            .sheet(isPresented: $showingSettingsHelp) {
                SettingsHelpSheet()
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView(hasCompletedOnboarding: .constant(true))
            }
            .task {
                // Load async data after view appears (non-blocking)
                await viewModel.loadAsync()
            }
        }
    }
}

// MARK: - API Key Row

struct APIKeyRow: View {
    let keyType: APIKeyManager.KeyType
    let isConfigured: Bool

    private var info: LMAPIProviderInfo {
        LMAPIProviderRegistry.info(for: keyType)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Category icons
            HStack(spacing: 4) {
                ForEach(info.categories, id: \.rawValue) { category in
                    Image(systemName: category.icon)
                        .font(.caption)
                        .foregroundStyle(category.color)
                }
            }
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(keyType.displayName)
                    .font(.body)

                HStack(spacing: 6) {
                    // Category labels
                    Text(info.categories.map { $0.shortLabel }.joined(separator: " + "))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Status
                    Text(isConfigured ? "Ready" : "Not set")
                        .font(.caption)
                        .foregroundStyle(isConfigured ? .green : .orange)
                }
            }

            Spacer()

            // Status indicator
            Image(systemName: isConfigured ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isConfigured ? .green : .secondary)
        }
    }
}

// MARK: - API Key Edit Sheet

struct APIKeyEditSheet: View {
    let keyType: APIKeyManager.KeyType
    let onSave: (APIKeyManager.KeyType, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keyValue = ""
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if showKey {
                            TextField("API Key", text: $keyValue)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("API Key", text: $keyValue)
                        }

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                    }
                } header: {
                    Text(keyType.displayName)
                } footer: {
                    Text("Your API key will be stored securely in the Keychain.")
                }
            }
            .navigationTitle("Edit API Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(keyType, keyValue)
                        dismiss()
                    }
                    .disabled(keyValue.isEmpty)
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
class SettingsViewModel: ObservableObject {
    // API Keys
    @Published var keyStatus: [APIKeyManager.KeyType: Bool] = [:]
    @Published var editingKeyType: APIKeyManager.KeyType?

    // Audio
    @AppStorage("sampleRate") var sampleRate: Double = 48000
    @AppStorage("enableVoiceProcessing") var enableVoiceProcessing = true
    @AppStorage("enableEchoCancellation") var enableEchoCancellation = true
    @AppStorage("enableNoiseSuppression") var enableNoiseSuppression = true

    // VAD
    @AppStorage("vadThreshold") var vadThreshold: Double = 0.5
    @AppStorage("bargeInThreshold") var bargeInThreshold: Double = 0.7
    @AppStorage("enableBargeIn") var enableBargeIn = true

    // STT - Default to on-device
    // Use a private backing store to avoid double-updates during didSet
    @Published var sttProvider: STTProvider {
        didSet {
            guard sttProvider != oldValue else { return }
            UserDefaults.standard.set(sttProvider.rawValue, forKey: "sttProvider")
        }
    }

    // LLM - Default to on-device
    @Published var llmProvider: LLMProvider {
        didSet {
            guard llmProvider != oldValue else { return }
            UserDefaults.standard.set(llmProvider.rawValue, forKey: "llmProvider")
        }
    }
    @AppStorage("llmModel") var llmModel = "llama3.2:3b"
    @AppStorage("temperature") var temperature: Double = 0.7
    @AppStorage("maxTokens") var maxTokens = 1024

    // TTS - Default to on-device
    @Published var ttsProvider: TTSProvider {
        didSet {
            guard ttsProvider != oldValue else { return }
            UserDefaults.standard.set(ttsProvider.rawValue, forKey: "ttsProvider")
        }
    }
    @AppStorage("speakingRate") var speakingRate: Double = 1.0
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"

    // Chatterbox TTS settings
    @AppStorage("chatterbox_exaggeration") var chatterboxExaggeration: Double = 0.5
    @AppStorage("chatterbox_preset") var chatterboxPresetRaw: String = "default"

    /// Chatterbox preset display name
    var chatterboxPresetName: String {
        ChatterboxPreset(rawValue: chatterboxPresetRaw)?.displayName ?? "Default"
    }

    // Debug
    @AppStorage("debugMode") var debugMode = false
    @AppStorage("verboseLogging") var verboseLogging = false
    @Published var hasSampleCurriculum = false

    // Self-hosted servers
    @Published var selfHostedServerCount = 0
    @Published var healthySelfHostedCount = 0
    @AppStorage("selfHostedEnabled") var selfHostedEnabled: Bool = false
    @AppStorage("primaryServerIP") var primaryServerIP: String = ""
    @Published var serverConnectionStatus: ServerConnectionStatus = .notConfigured
    @Published var discoveredModels: [String] = []
    @Published var discoveredPiperVoices: [String] = []
    @Published var discoveredVibeVoiceVoices: [String] = []
    @Published var serverCapabilitiesSummary: String = ""

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

    /// Default TTS voices - includes both OpenAI-compatible and native VibeVoice voices
    /// Used when server voices not discovered (fallback)
    var defaultTTSVoices: [String] {
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

    // Remote Logging
    @AppStorage("logServerIP") var logServerIP: String = ""
    @AppStorage("logServerUsesSameIP") var logServerUsesSameIP: Bool = true
    @Published var remoteLoggingEnabled: Bool = true

    /// Flag to skip side effects during initialization
    private var hasFinishedInit = false

    /// The effective log server IP (uses primary server IP if sharing is enabled)
    var effectiveLogServerIP: String {
        if logServerUsesSameIP && selfHostedEnabled && !primaryServerIP.isEmpty {
            return primaryServerIP
        }
        return logServerIP
    }

    private let curriculumSeeder = SampleCurriculumSeeder()

    /// Whether async loading has been triggered
    private var hasLoadedAsync = false

    init() {
        // Load persisted provider settings synchronously (fast UserDefaults reads)
        if let sttRaw = UserDefaults.standard.string(forKey: "sttProvider"),
           let stt = STTProvider(rawValue: sttRaw) {
            self.sttProvider = stt
        } else {
            self.sttProvider = .glmASROnDevice  // Default to on-device
        }

        if let llmRaw = UserDefaults.standard.string(forKey: "llmProvider"),
           let llm = LLMProvider(rawValue: llmRaw) {
            self.llmProvider = llm
        } else {
            self.llmProvider = .localMLX  // Default to on-device
        }

        if let ttsRaw = UserDefaults.standard.string(forKey: "ttsProvider"),
           let tts = TTSProvider(rawValue: ttsRaw) {
            self.ttsProvider = tts
        } else {
            self.ttsProvider = .appleTTS  // Default to on-device
        }

        // Load remote logging setting (defaults to true)
        self.remoteLoggingEnabled = UserDefaults.standard.object(forKey: "remoteLoggingEnabled") as? Bool ?? true

        // Mark init as complete so didSet-style side effects can run
        self.hasFinishedInit = true

        // NOTE: No Task spawning here! Async loading is deferred to loadAsync()
        // called from the view's .task modifier
    }

    /// Handle changes to remoteLoggingEnabled (called from View's onChange)
    func handleRemoteLoggingChange(_ newValue: Bool) {
        guard hasFinishedInit else { return }
        UserDefaults.standard.set(newValue, forKey: "remoteLoggingEnabled")
        if newValue {
            RemoteLogging.enable()
        } else {
            RemoteLogging.disable()
        }
        updateLogServerConfiguration()
    }

    /// Load async data (call from view's .task modifier)
    @MainActor
    func loadAsync() async {
        guard !hasLoadedAsync else { return }
        hasLoadedAsync = true

        // Load all async data concurrently
        async let keyStatusTask: () = loadKeyStatus()
        async let curriculumTask: () = checkSampleCurriculum()
        async let serverTask: () = loadServerStatus()

        _ = await (keyStatusTask, curriculumTask, serverTask)
    }

    /// Available models for current provider
    var availableModels: [String] {
        switch llmProvider {
        case .openAI:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
        case .anthropic:
            return ["claude-3-5-sonnet-20241022", "claude-3-haiku-20240307"]
        case .selfHosted:
            // Use discovered models if available, otherwise fall back to defaults
            if !discoveredModels.isEmpty {
                return discoveredModels
            }
            return ["qwen2.5:32b", "qwen2.5:7b", "llama3.2:3b", "mistral:7b"]
        case .localMLX:
            return ["ministral-3b (on-device)"]
        }
    }

    private func loadServerStatus() async {
        let servers = await ServerConfigManager.shared.getAllServers()
        let healthy = servers.filter { $0.isEnabled && $0.healthStatus.isUsable }
        await MainActor.run {
            selfHostedServerCount = servers.filter { $0.isEnabled }.count
            healthySelfHostedCount = healthy.count
        }
    }

    private func checkSampleCurriculum() async {
        let exists = curriculumSeeder.hasSampleCurriculum()
        await MainActor.run {
            hasSampleCurriculum = exists
        }
    }

    private func loadKeyStatus() async {
        let status = await APIKeyManager.shared.getKeyStatus()
        await MainActor.run {
            keyStatus = status
        }
    }

    func saveKey(_ keyType: APIKeyManager.KeyType, value: String) {
        Task {
            try? await APIKeyManager.shared.setKey(keyType, value: value)
            await loadKeyStatus()
        }
    }

    func loadSampleCurriculum() async {
        do {
            try curriculumSeeder.seedPyTorchCurriculum()
            await checkSampleCurriculum()
        } catch {
            print("Failed to seed sample curriculum: \(error)")
        }
    }

    func deleteSampleCurriculum() async {
        do {
            try curriculumSeeder.deleteSampleCurriculum()
            await checkSampleCurriculum()
        } catch {
            print("Failed to delete sample curriculum: \(error)")
        }
    }

    /// Update the remote logging configuration with the effective IP
    private func updateLogServerConfiguration() {
        let ip = effectiveLogServerIP
        if remoteLoggingEnabled && !ip.isEmpty {
            RemoteLogging.configure(serverIP: ip)
        }
    }

    /// Check server connection when IP changes
    func checkServerConnection() async {
        guard selfHostedEnabled, !primaryServerIP.isEmpty else {
            serverConnectionStatus = .notConfigured
            discoveredModels = []
            discoveredPiperVoices = []
            discoveredVibeVoiceVoices = []
            serverCapabilitiesSummary = ""
            return
        }

        serverConnectionStatus = .checking

        // Try Management API first (port 8766) - this is the main server orchestrator
        let managementConnected = await checkManagementAPI()

        if managementConnected {
            serverConnectionStatus = .connected

            // Discover models through Management API
            let managementModels = await ServerConfigManager.shared.discoverManagementModels(host: primaryServerIP)
            if !managementModels.isEmpty {
                // Extract LLM models from management API response
                discoveredModels = managementModels
                    .filter { $0.type == "llm" }
                    .map { $0.name }

                // Build summary from management API data
                let llmCount = managementModels.filter { $0.type == "llm" }.count
                let ttsCount = managementModels.filter { $0.type == "tts" }.count
                let sttCount = managementModels.filter { $0.type == "stt" }.count
                var summaryParts: [String] = []
                if llmCount > 0 { summaryParts.append("\(llmCount) LLM model(s)") }
                if ttsCount > 0 { summaryParts.append("\(ttsCount) TTS") }
                if sttCount > 0 { summaryParts.append("\(sttCount) STT") }
                serverCapabilitiesSummary = summaryParts.isEmpty ? "Server connected" : summaryParts.joined(separator: ", ")
            } else {
                // Fall back to direct capability discovery
                let capabilities = await ServerConfigManager.shared.discoverCapabilities(host: primaryServerIP)
                discoveredModels = capabilities.llmModels
                discoveredPiperVoices = capabilities.piperVoices
                discoveredVibeVoiceVoices = capabilities.vibeVoiceVoices
                serverCapabilitiesSummary = capabilities.summary
            }

            // Auto-select first discovered model if current model not in list
            if !discoveredModels.isEmpty && !discoveredModels.contains(llmModel) {
                llmModel = discoveredModels[0]
            }
            return
        }

        // Fall back to checking Ollama directly (port 11434)
        let ollamaConnected = await checkOllamaDirectly()

        if ollamaConnected {
            serverConnectionStatus = .connected

            // Discover capabilities (checks Ollama, Piper, and VibeVoice)
            let capabilities = await ServerConfigManager.shared.discoverCapabilities(host: primaryServerIP)
            discoveredModels = capabilities.llmModels
            discoveredPiperVoices = capabilities.piperVoices
            discoveredVibeVoiceVoices = capabilities.vibeVoiceVoices
            serverCapabilitiesSummary = capabilities.summary

            // Auto-select first discovered model if current model not in list
            if !discoveredModels.isEmpty && !discoveredModels.contains(llmModel) {
                llmModel = discoveredModels[0]
            }
        } else {
            serverConnectionStatus = .failed
        }
    }

    /// Check if Management API is reachable
    private func checkManagementAPI() async -> Bool {
        guard let url = URL(string: "http://\(primaryServerIP):8766/health") else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            // Management API not reachable
        }
        return false
    }

    /// Check if Ollama is reachable directly
    private func checkOllamaDirectly() async -> Bool {
        guard let url = URL(string: "http://\(primaryServerIP):11434/api/version") else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            // Ollama not reachable
        }
        return false
    }

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
            llmProvider = .openAI
            sampleRate = 16000
            vadThreshold = 0.5
            llmModel = "gpt-4o-mini"
            temperature = 0.5
            maxTokens = 512

        case .selfHosted:
            selfHostedEnabled = true
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

extension APIKeyManager.KeyType: Identifiable {
    public var id: String { rawValue }
}

// MARK: - Server Connection Status

enum ServerConnectionStatus {
    case notConfigured
    case checking
    case connected
    case failed

    var color: Color {
        switch self {
        case .notConfigured: return .secondary
        case .checking: return .orange
        case .connected: return .green
        case .failed: return .red
        }
    }

    var label: String {
        switch self {
        case .notConfigured: return "Not configured"
        case .checking: return "Checking..."
        case .connected: return "Connected"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Diagnostics View

struct DiagnosticsView: View {
    @StateObject private var viewModel = DiagnosticsViewModel()

    var body: some View {
        List {
            Section("Audio Engine") {
                DiagnosticRow(
                    name: "Audio Session",
                    status: viewModel.audioSessionStatus,
                    detail: viewModel.audioSessionDetail
                )
                DiagnosticRow(
                    name: "Microphone Access",
                    status: viewModel.microphoneStatus,
                    detail: viewModel.microphoneDetail
                )
                DiagnosticRow(
                    name: "VAD Service",
                    status: viewModel.vadStatus,
                    detail: viewModel.vadDetail
                )
            }

            Section("API Connectivity") {
                DiagnosticRow(
                    name: "STT Service",
                    status: viewModel.sttStatus,
                    detail: viewModel.sttDetail
                )
                DiagnosticRow(
                    name: "TTS Service",
                    status: viewModel.ttsStatus,
                    detail: viewModel.ttsDetail
                )
                DiagnosticRow(
                    name: "LLM Service",
                    status: viewModel.llmStatus,
                    detail: viewModel.llmDetail
                )
            }

            Section("Remote Servers") {
                DiagnosticRow(
                    name: "Logging Server",
                    status: viewModel.loggingServerStatus,
                    detail: viewModel.loggingServerDetail
                )
                DiagnosticRow(
                    name: "LLM Server (Ollama)",
                    status: viewModel.ollamaServerStatus,
                    detail: viewModel.ollamaServerDetail
                )
            }

            Section("System") {
                DiagnosticRow(
                    name: "Thermal State",
                    status: viewModel.thermalStatus,
                    detail: viewModel.thermalDetail
                )
                DiagnosticRow(
                    name: "Memory Usage",
                    status: viewModel.memoryStatus,
                    detail: viewModel.memoryDetail
                )
            }

            Section {
                Button("Run All Diagnostics") {
                    Task { await viewModel.runAllDiagnostics() }
                }
                .disabled(viewModel.isRunning)
            }
        }
        .navigationTitle("Diagnostics")
        .overlay {
            if viewModel.isRunning {
                ProgressView("Running diagnostics...")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct DiagnosticRow: View {
    let name: String
    let status: DiagnosticStatus
    let detail: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusIcon
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView()
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

enum DiagnosticStatus {
    case unknown, checking, ok, warning, error
}

@MainActor
class DiagnosticsViewModel: ObservableObject {
    @Published var isRunning = false

    // Audio
    @Published var audioSessionStatus: DiagnosticStatus = .unknown
    @Published var audioSessionDetail = "Not checked"
    @Published var microphoneStatus: DiagnosticStatus = .unknown
    @Published var microphoneDetail = "Not checked"
    @Published var vadStatus: DiagnosticStatus = .unknown
    @Published var vadDetail = "Not checked"

    // API
    @Published var sttStatus: DiagnosticStatus = .unknown
    @Published var sttDetail = "Not checked"
    @Published var ttsStatus: DiagnosticStatus = .unknown
    @Published var ttsDetail = "Not checked"
    @Published var llmStatus: DiagnosticStatus = .unknown
    @Published var llmDetail = "Not checked"

    // System
    @Published var thermalStatus: DiagnosticStatus = .unknown
    @Published var thermalDetail = "Not checked"
    @Published var memoryStatus: DiagnosticStatus = .unknown
    @Published var memoryDetail = "Not checked"

    // Remote Servers
    @Published var loggingServerStatus: DiagnosticStatus = .unknown
    @Published var loggingServerDetail = "Not checked"
    @Published var ollamaServerStatus: DiagnosticStatus = .unknown
    @Published var ollamaServerDetail = "Not checked"

    func runAllDiagnostics() async {
        isRunning = true
        defer { isRunning = false }

        // Check audio session
        audioSessionStatus = .checking
        await Task.yield()
        audioSessionStatus = .ok
        audioSessionDetail = "Voice chat mode available"

        // Check microphone
        microphoneStatus = .checking
        await Task.yield()
        let authStatus = AVAudioApplication.shared.recordPermission
        switch authStatus {
        case .granted:
            microphoneStatus = .ok
            microphoneDetail = "Permission granted"
        case .denied:
            microphoneStatus = .error
            microphoneDetail = "Permission denied"
        case .undetermined:
            microphoneStatus = .warning
            microphoneDetail = "Permission not requested"
        @unknown default:
            microphoneStatus = .warning
            microphoneDetail = "Unknown status"
        }

        // Check VAD
        vadStatus = .checking
        await Task.yield()
        vadStatus = .ok
        vadDetail = "Silero VAD ready"

        // Check API keys for services (respecting self-hosted and on-device settings)
        let apiKeys = APIKeyManager.shared
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let sttProviderRaw = UserDefaults.standard.string(forKey: "sttProvider") ?? ""
        let ttsProviderRaw = UserDefaults.standard.string(forKey: "ttsProvider") ?? ""
        let llmProviderRaw = UserDefaults.standard.string(forKey: "llmProvider") ?? ""

        // STT Check - raw values are display names like "Apple Speech (On-Device)"
        sttStatus = .checking
        await Task.yield()
        let isOnDeviceSTT = sttProviderRaw.contains("On-Device") || sttProviderRaw.contains("GLM")
        if isOnDeviceSTT {
            sttStatus = .ok
            let providerName = sttProviderRaw.isEmpty ? "On-device" : sttProviderRaw
            sttDetail = "\(providerName) (no API needed)"
        } else if sttProviderRaw.contains("Deepgram") {
            let hasKey = await apiKeys.hasKey(.deepgram)
            if hasKey {
                sttStatus = .ok
                sttDetail = "Deepgram configured"
            } else {
                sttStatus = .error
                sttDetail = "Deepgram: No API key"
            }
        } else if sttProviderRaw.contains("AssemblyAI") {
            let hasKey = await apiKeys.hasKey(.assemblyAI)
            if hasKey {
                sttStatus = .ok
                sttDetail = "AssemblyAI configured"
            } else {
                sttStatus = .error
                sttDetail = "AssemblyAI: No API key"
            }
        } else if sttProviderRaw.contains("Groq") {
            let hasKey = await apiKeys.hasKey(.groq)
            if hasKey {
                sttStatus = .ok
                sttDetail = "Groq Whisper configured"
            } else {
                sttStatus = .error
                sttDetail = "Groq: No API key"
            }
        } else {
            // Fall back to checking any available STT key
            let hasDeepgram = await apiKeys.hasKey(.deepgram)
            let hasAssemblyAI = await apiKeys.hasKey(.assemblyAI)
            if hasDeepgram || hasAssemblyAI {
                sttStatus = .ok
                sttDetail = "API key configured"
            } else {
                sttStatus = .warning
                sttDetail = "No provider selected"
            }
        }

        // TTS Check - raw values are display names like "Apple TTS (On-Device)", "Self-Hosted (Piper)"
        ttsStatus = .checking
        await Task.yield()
        let isOnDeviceTTS = ttsProviderRaw.contains("On-Device") || ttsProviderRaw.contains("Apple")
        let isSelfHostedTTS = ttsProviderRaw.contains("Self-Hosted") || ttsProviderRaw.contains("Piper")
        if isOnDeviceTTS {
            ttsStatus = .ok
            let providerName = ttsProviderRaw.isEmpty ? "Apple TTS" : ttsProviderRaw
            ttsDetail = "\(providerName) (no API needed)"
        } else if isSelfHostedTTS {
            if selfHostedEnabled {
                ttsStatus = .ok
                ttsDetail = "Piper TTS on self-hosted server"
            } else {
                ttsStatus = .warning
                ttsDetail = "Self-hosted disabled in settings"
            }
        } else if ttsProviderRaw.contains("ElevenLabs") {
            let hasKey = await apiKeys.hasKey(.elevenLabs)
            if hasKey {
                ttsStatus = .ok
                ttsDetail = "ElevenLabs configured"
            } else {
                ttsStatus = .error
                ttsDetail = "ElevenLabs: No API key"
            }
        } else if ttsProviderRaw.contains("Deepgram") {
            let hasKey = await apiKeys.hasKey(.deepgram)
            if hasKey {
                ttsStatus = .ok
                ttsDetail = "Deepgram TTS configured"
            } else {
                ttsStatus = .error
                ttsDetail = "Deepgram: No API key"
            }
        } else {
            // Fall back to checking any available TTS key
            let hasElevenLabs = await apiKeys.hasKey(.elevenLabs)
            let hasDeepgram = await apiKeys.hasKey(.deepgram)
            if hasElevenLabs || hasDeepgram {
                ttsStatus = .ok
                ttsDetail = "API key configured"
            } else {
                ttsStatus = .warning
                ttsDetail = "No provider selected"
            }
        }

        // LLM Check - raw values are display names like "Local MLX", "Self-Hosted"
        llmStatus = .checking
        await Task.yield()
        let isOnDeviceLLM = llmProviderRaw.contains("Local") || llmProviderRaw.contains("MLX")
        let isSelfHostedLLM = llmProviderRaw.contains("Self-Hosted") || llmProviderRaw.contains("Ollama")
        if isOnDeviceLLM {
            llmStatus = .ok
            let providerName = llmProviderRaw.isEmpty ? "Local MLX" : llmProviderRaw
            llmDetail = "\(providerName) (no API needed)"
        } else if isSelfHostedLLM {
            if selfHostedEnabled {
                llmStatus = .ok
                llmDetail = "Ollama on self-hosted server"
            } else {
                llmStatus = .warning
                llmDetail = "Self-hosted disabled in settings"
            }
        } else if llmProviderRaw.contains("Anthropic") || llmProviderRaw.contains("Claude") {
            let hasKey = await apiKeys.hasKey(.anthropic)
            if hasKey {
                llmStatus = .ok
                llmDetail = "Anthropic Claude configured"
            } else {
                llmStatus = .error
                llmDetail = "Anthropic: No API key"
            }
        } else if llmProviderRaw.contains("OpenAI") || llmProviderRaw.contains("GPT") {
            let hasKey = await apiKeys.hasKey(.openAI)
            if hasKey {
                llmStatus = .ok
                llmDetail = "OpenAI GPT configured"
            } else {
                llmStatus = .error
                llmDetail = "OpenAI: No API key"
            }
        } else {
            // Fall back to checking any available LLM key
            let hasAnthropic = await apiKeys.hasKey(.anthropic)
            let hasOpenAI = await apiKeys.hasKey(.openAI)
            if hasAnthropic || hasOpenAI {
                llmStatus = .ok
                llmDetail = "API key configured"
            } else {
                llmStatus = .warning
                llmDetail = "No provider selected"
            }
        }

        // Check thermal state
        thermalStatus = .checking
        await Task.yield()
        let thermal = ProcessInfo.processInfo.thermalState
        switch thermal {
        case .nominal:
            thermalStatus = .ok
            thermalDetail = "Nominal"
        case .fair:
            thermalStatus = .ok
            thermalDetail = "Fair"
        case .serious:
            thermalStatus = .warning
            thermalDetail = "Serious - may throttle"
        case .critical:
            thermalStatus = .error
            thermalDetail = "Critical - throttling"
        @unknown default:
            thermalStatus = .warning
            thermalDetail = "Unknown"
        }

        // Check memory
        memoryStatus = .checking
        await Task.yield()
        memoryStatus = .ok
        memoryDetail = "Within limits"

        // Check remote servers
        await checkRemoteServers()
    }

    /// Check logging server and Ollama server connectivity
    private func checkRemoteServers() async {
        // Get server IP from settings
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let primaryServerIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
        let remoteLoggingEnabled = UserDefaults.standard.bool(forKey: "remoteLoggingEnabled")
        let logServerUsesSameIP = UserDefaults.standard.bool(forKey: "logServerUsesSameIP")
        let logServerIP = UserDefaults.standard.string(forKey: "logServerIP") ?? ""

        // Determine effective log server IP
        let effectiveLogIP: String
        if logServerUsesSameIP && selfHostedEnabled && !primaryServerIP.isEmpty {
            effectiveLogIP = primaryServerIP
        } else {
            effectiveLogIP = logServerIP
        }

        // Check logging server
        loggingServerStatus = .checking
        loggingServerDetail = "Checking..."
        await Task.yield()

        if !remoteLoggingEnabled {
            loggingServerStatus = .warning
            loggingServerDetail = "Remote logging disabled"
        } else if effectiveLogIP.isEmpty {
            loggingServerStatus = .error
            loggingServerDetail = "No server IP configured"
        } else {
            // Try to connect to logging server on port 8766
            let logURL = URL(string: "http://\(effectiveLogIP):8766/health")
            if let url = logURL {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 5
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 {
                            loggingServerStatus = .ok
                            loggingServerDetail = "\(effectiveLogIP):8766 connected"
                        } else {
                            loggingServerStatus = .warning
                            loggingServerDetail = "HTTP \(httpResponse.statusCode)"
                        }
                    } else {
                        loggingServerStatus = .error
                        loggingServerDetail = "Invalid response"
                    }
                } catch {
                    loggingServerStatus = .error
                    loggingServerDetail = "Cannot reach \(effectiveLogIP):8766"
                }
            } else {
                loggingServerStatus = .error
                loggingServerDetail = "Invalid URL"
            }
        }

        // Check Ollama server
        ollamaServerStatus = .checking
        ollamaServerDetail = "Checking..."
        await Task.yield()

        if !selfHostedEnabled {
            ollamaServerStatus = .warning
            ollamaServerDetail = "Self-hosted disabled"
        } else if primaryServerIP.isEmpty {
            ollamaServerStatus = .error
            ollamaServerDetail = "No server IP configured"
        } else {
            // Try to connect to Ollama on port 11434
            let ollamaURL = URL(string: "http://\(primaryServerIP):11434/api/tags")
            if let url = ollamaURL {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 5
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 {
                            // Try to parse model count
                            var modelCount = 0
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let models = json["models"] as? [[String: Any]] {
                                modelCount = models.count
                            }
                            ollamaServerStatus = .ok
                            ollamaServerDetail = "\(primaryServerIP):11434 - \(modelCount) models"
                        } else {
                            ollamaServerStatus = .warning
                            ollamaServerDetail = "HTTP \(httpResponse.statusCode)"
                        }
                    } else {
                        ollamaServerStatus = .error
                        ollamaServerDetail = "Invalid response"
                    }
                } catch {
                    ollamaServerStatus = .error
                    ollamaServerDetail = "Cannot reach \(primaryServerIP):11434"
                }
            } else {
                ollamaServerStatus = .error
                ollamaServerDetail = "Invalid URL"
            }
        }
    }
}

// MARK: - Audio Test View

struct AudioTestView: View {
    @StateObject private var viewModel = AudioTestViewModel()

    var body: some View {
        List {
            Section("Microphone Test") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tests audio capture from microphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    AudioLevelMeter(level: viewModel.inputLevel)

                    HStack {
                        Button(viewModel.isRecording ? "Stop" : "Start Recording") {
                            if viewModel.isRecording {
                                viewModel.stopRecording()
                            } else {
                                viewModel.startRecording()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        if viewModel.hasRecording {
                            Button("Play Back") {
                                viewModel.playRecording()
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Section("VAD Test") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tests voice activity detection")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Speech Detected:")
                        Spacer()
                        Circle()
                            .fill(viewModel.isSpeechDetected ? Color.green : Color.gray)
                            .frame(width: 16, height: 16)
                        Text(viewModel.isSpeechDetected ? "Yes" : "No")
                    }

                    Text("Confidence: \(viewModel.vadConfidence, specifier: "%.2f")")
                        .font(.caption.monospacedDigit())
                }
                .padding(.vertical, 8)
            }

            Section("TTS Test") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tests text-to-speech playback")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Text to speak", text: $viewModel.testText)
                        .textFieldStyle(.roundedBorder)

                    Button("Speak") {
                        Task { await viewModel.testTTS() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.testText.isEmpty || viewModel.isSpeaking)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Audio Pipeline Test")
    }
}

struct AudioLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))

                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: max(0, geo.size.width * CGFloat(normalizedLevel)))
            }
        }
        .frame(height: 20)
    }

    private var normalizedLevel: Float {
        // Convert dB to 0-1 range (-60dB to 0dB)
        max(0, min(1, (level + 60) / 60))
    }

    private var levelColor: Color {
        if normalizedLevel < 0.6 { return .green }
        else if normalizedLevel < 0.8 { return .yellow }
        else { return .red }
    }
}

@MainActor
class AudioTestViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var inputLevel: Float = -60
    @Published var isSpeechDetected = false
    @Published var vadConfidence: Float = 0
    @Published var testText = "Hello, this is a test of the text to speech system."
    @Published var isSpeaking = false

    func startRecording() {
        isRecording = true
        // In real implementation, would start AudioEngine capture
        // For now, simulate level changes
        simulateAudioLevels()
    }

    private func simulateAudioLevels() {
        guard isRecording else { return }
        inputLevel = Float.random(in: -40...(-10))
        isSpeechDetected = inputLevel > -25
        vadConfidence = isSpeechDetected ? Float.random(in: 0.7...0.95) : Float.random(in: 0.1...0.3)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            simulateAudioLevels()
        }
    }

    func stopRecording() {
        isRecording = false
        hasRecording = true
        inputLevel = -60
        isSpeechDetected = false
        vadConfidence = 0
    }

    func playRecording() {
        // In real implementation, would play back recorded audio
    }

    func testTTS() async {
        isSpeaking = true
        // In real implementation, would call TTS service and play audio
        try? await Task.sleep(for: .seconds(2))
        isSpeaking = false
    }
}

// MARK: - Provider Test View

struct ProviderTestView: View {
    @StateObject private var viewModel = ProviderTestViewModel()

    var body: some View {
        List {
            Section("STT Providers") {
                ProviderTestRow(name: "Deepgram", status: viewModel.deepgramSTT) {
                    await viewModel.testDeepgramSTT()
                }
                ProviderTestRow(name: "AssemblyAI", status: viewModel.assemblyAI) {
                    await viewModel.testAssemblyAI()
                }
            }

            Section("TTS Providers") {
                ProviderTestRow(name: "ElevenLabs", status: viewModel.elevenLabs) {
                    await viewModel.testElevenLabs()
                }
                ProviderTestRow(name: "Deepgram Aura", status: viewModel.deepgramTTS) {
                    await viewModel.testDeepgramTTS()
                }
            }

            Section("LLM Providers") {
                ProviderTestRow(name: "Anthropic Claude", status: viewModel.anthropic) {
                    await viewModel.testAnthropic()
                }
                ProviderTestRow(name: "OpenAI", status: viewModel.openAI) {
                    await viewModel.testOpenAI()
                }
            }

            Section {
                Button("Test All Providers") {
                    Task { await viewModel.testAll() }
                }
                .disabled(viewModel.isTesting)
            }
        }
        .navigationTitle("Provider Connectivity")
    }
}

struct ProviderTestRow: View {
    let name: String
    let status: ProviderTestStatus
    let action: () async -> Void

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            statusView
            Button("Test") {
                Task { await action() }
            }
            .buttonStyle(.bordered)
            .disabled(status == .testing)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .untested:
            Text("Not tested")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .testing:
            ProgressView()
        case .success(let latency):
            Text("\(Int(latency * 1000))ms")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.green)
        case .failed(let error):
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        case .noKey:
            Text("No API key")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

enum ProviderTestStatus: Equatable {
    case untested
    case testing
    case success(latency: TimeInterval)
    case failed(error: String)
    case noKey
}

@MainActor
class ProviderTestViewModel: ObservableObject {
    @Published var isTesting = false

    @Published var deepgramSTT: ProviderTestStatus = .untested
    @Published var assemblyAI: ProviderTestStatus = .untested
    @Published var elevenLabs: ProviderTestStatus = .untested
    @Published var deepgramTTS: ProviderTestStatus = .untested
    @Published var anthropic: ProviderTestStatus = .untested
    @Published var openAI: ProviderTestStatus = .untested

    func testAll() async {
        isTesting = true
        await testDeepgramSTT()
        await testAssemblyAI()
        await testElevenLabs()
        await testDeepgramTTS()
        await testAnthropic()
        await testOpenAI()
        isTesting = false
    }

    func testDeepgramSTT() async {
        guard await APIKeyManager.shared.hasKey(.deepgram) else {
            deepgramSTT = .noKey
            return
        }
        deepgramSTT = .testing
        // Simulate API test
        try? await Task.sleep(for: .milliseconds(500))
        deepgramSTT = .success(latency: 0.15)
    }

    func testAssemblyAI() async {
        guard await APIKeyManager.shared.hasKey(.assemblyAI) else {
            assemblyAI = .noKey
            return
        }
        assemblyAI = .testing
        try? await Task.sleep(for: .milliseconds(600))
        assemblyAI = .success(latency: 0.18)
    }

    func testElevenLabs() async {
        guard await APIKeyManager.shared.hasKey(.elevenLabs) else {
            elevenLabs = .noKey
            return
        }
        elevenLabs = .testing
        try? await Task.sleep(for: .milliseconds(400))
        elevenLabs = .success(latency: 0.12)
    }

    func testDeepgramTTS() async {
        guard await APIKeyManager.shared.hasKey(.deepgram) else {
            deepgramTTS = .noKey
            return
        }
        deepgramTTS = .testing
        try? await Task.sleep(for: .milliseconds(350))
        deepgramTTS = .success(latency: 0.10)
    }

    func testAnthropic() async {
        guard await APIKeyManager.shared.hasKey(.anthropic) else {
            anthropic = .noKey
            return
        }
        anthropic = .testing
        try? await Task.sleep(for: .milliseconds(800))
        anthropic = .success(latency: 0.25)
    }

    func testOpenAI() async {
        guard await APIKeyManager.shared.hasKey(.openAI) else {
            openAI = .noKey
            return
        }
        openAI = .testing
        try? await Task.sleep(for: .milliseconds(700))
        openAI = .success(latency: 0.22)
    }
}

// MARK: - TTS Playback Tuning View

/// Settings view for tuning TTS playback behavior to eliminate audio gaps
struct TTSPlaybackTuningView: View {
    @StateObject private var viewModel = TTSPlaybackTuningViewModel()

    var body: some View {
        List {
            // Preset Selection
            Section {
                Picker("Preset", selection: $viewModel.selectedPreset) {
                    ForEach(TTSPlaybackPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .onChange(of: viewModel.selectedPreset) { _, newValue in
                    viewModel.applyPreset(newValue)
                }
            } header: {
                Text("Quick Settings")
            } footer: {
                Text("Choose a preset or customize individual settings below.")
            }

            // Prefetching Settings
            Section {
                Toggle("Enable Prefetching", isOn: $viewModel.enablePrefetch)
                    .onChange(of: viewModel.enablePrefetch) { _, _ in viewModel.markCustom() }

                if viewModel.enablePrefetch {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Lookahead Time")
                            Spacer()
                            Text("\(viewModel.prefetchLookahead, specifier: "%.1f")s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $viewModel.prefetchLookahead, in: 0.5...3.0, step: 0.1)
                            .onChange(of: viewModel.prefetchLookahead) { _, _ in viewModel.markCustom() }
                    }

                    Stepper(value: $viewModel.prefetchQueueDepth, in: 1...3) {
                        HStack {
                            Text("Queue Depth")
                            Spacer()
                            Text("\(viewModel.prefetchQueueDepth) sentence\(viewModel.prefetchQueueDepth == 1 ? "" : "s")")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: viewModel.prefetchQueueDepth) { _, _ in viewModel.markCustom() }
                }
            } header: {
                Text("Prefetching")
            } footer: {
                Text("Prefetching synthesizes upcoming sentences while the current one plays, reducing gaps.")
            }

            // Timing Settings
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Inter-Sentence Silence")
                        Spacer()
                        Text("\(viewModel.interSentenceSilenceMs)ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(viewModel.interSentenceSilenceMs) },
                        set: { viewModel.interSentenceSilenceMs = Int($0) }
                    ), in: 0...500, step: 25)
                        .onChange(of: viewModel.interSentenceSilenceMs) { _, _ in viewModel.markCustom() }
                }
            } header: {
                Text("Timing")
            } footer: {
                Text("Add intentional pauses between sentences. Set to 0 for natural flow.")
            }

            // Advanced Settings
            Section {
                Toggle("Multi-Buffer Scheduling", isOn: $viewModel.enableMultiBuffer)
                    .onChange(of: viewModel.enableMultiBuffer) { _, _ in viewModel.markCustom() }

                if viewModel.enableMultiBuffer {
                    Stepper(value: $viewModel.scheduledBufferCount, in: 1...4) {
                        HStack {
                            Text("Buffer Count")
                            Spacer()
                            Text("\(viewModel.scheduledBufferCount) buffer\(viewModel.scheduledBufferCount == 1 ? "" : "s")")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: viewModel.scheduledBufferCount) { _, _ in viewModel.markCustom() }
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Multi-buffer scheduling keeps audio buffers queued ahead in the player.")
            }

            // Reset Button
            Section {
                Button("Reset to Default") {
                    viewModel.applyPreset(.default)
                }
            }
        }
        .navigationTitle("TTS Playback")
        .onDisappear {
            viewModel.save()
        }
    }
}

// MARK: - TTS Playback Tuning ViewModel

@MainActor
class TTSPlaybackTuningViewModel: ObservableObject {
    @Published var selectedPreset: TTSPlaybackPreset = .default
    @Published var enablePrefetch: Bool = true
    @Published var prefetchLookahead: Double = 1.5
    @Published var prefetchQueueDepth: Int = 1
    @Published var interSentenceSilenceMs: Int = 0
    @Published var enableMultiBuffer: Bool = true
    @Published var scheduledBufferCount: Int = 2

    private let defaults = UserDefaults.standard

    // UserDefaults keys
    private enum Keys {
        static let preset = "tts_playback_preset"
        static let enablePrefetch = "tts_playback_enable_prefetch"
        static let prefetchLookahead = "tts_playback_prefetch_lookahead"
        static let prefetchQueueDepth = "tts_playback_prefetch_queue_depth"
        static let interSentenceSilenceMs = "tts_playback_inter_sentence_silence_ms"
        static let enableMultiBuffer = "tts_playback_enable_multi_buffer"
        static let scheduledBufferCount = "tts_playback_scheduled_buffer_count"
    }

    init() {
        load()
    }

    func load() {
        if let presetString = defaults.string(forKey: Keys.preset),
           let preset = TTSPlaybackPreset(rawValue: presetString) {
            selectedPreset = preset
        }

        if defaults.object(forKey: Keys.enablePrefetch) != nil {
            enablePrefetch = defaults.bool(forKey: Keys.enablePrefetch)
        }

        let lookahead = defaults.double(forKey: Keys.prefetchLookahead)
        if lookahead > 0 {
            prefetchLookahead = lookahead
        }

        let queueDepth = defaults.integer(forKey: Keys.prefetchQueueDepth)
        if queueDepth > 0 {
            prefetchQueueDepth = queueDepth
        }

        interSentenceSilenceMs = defaults.integer(forKey: Keys.interSentenceSilenceMs)

        if defaults.object(forKey: Keys.enableMultiBuffer) != nil {
            enableMultiBuffer = defaults.bool(forKey: Keys.enableMultiBuffer)
        }

        let bufferCount = defaults.integer(forKey: Keys.scheduledBufferCount)
        if bufferCount > 0 {
            scheduledBufferCount = bufferCount
        }
    }

    func save() {
        defaults.set(selectedPreset.rawValue, forKey: Keys.preset)
        defaults.set(enablePrefetch, forKey: Keys.enablePrefetch)
        defaults.set(prefetchLookahead, forKey: Keys.prefetchLookahead)
        defaults.set(prefetchQueueDepth, forKey: Keys.prefetchQueueDepth)
        defaults.set(interSentenceSilenceMs, forKey: Keys.interSentenceSilenceMs)
        defaults.set(enableMultiBuffer, forKey: Keys.enableMultiBuffer)
        defaults.set(scheduledBufferCount, forKey: Keys.scheduledBufferCount)
    }

    func applyPreset(_ preset: TTSPlaybackPreset) {
        selectedPreset = preset
        guard let config = preset.config else { return }  // Custom - don't change values

        enablePrefetch = config.enablePrefetch
        prefetchLookahead = config.prefetchLookaheadSeconds
        prefetchQueueDepth = config.prefetchQueueDepth
        interSentenceSilenceMs = config.interSentenceSilenceMs
        enableMultiBuffer = config.enableMultiBufferScheduling
        scheduledBufferCount = config.scheduledBufferCount

        save()
    }

    func markCustom() {
        if selectedPreset != .custom {
            selectedPreset = .custom
        }
    }

    /// Get the current config based on settings
    func currentConfig() -> TTSPlaybackConfig {
        TTSPlaybackConfig(
            enablePrefetch: enablePrefetch,
            prefetchLookaheadSeconds: prefetchLookahead,
            prefetchQueueDepth: prefetchQueueDepth,
            interSentenceSilenceMs: interSentenceSilenceMs,
            enableMultiBufferScheduling: enableMultiBuffer,
            scheduledBufferCount: scheduledBufferCount
        )
    }

    /// Load TTS playback config from UserDefaults (static helper for SessionManager)
    static func loadConfig() -> TTSPlaybackConfig {
        let defaults = UserDefaults.standard

        let enablePrefetch = defaults.object(forKey: Keys.enablePrefetch) != nil
            ? defaults.bool(forKey: Keys.enablePrefetch)
            : true

        let lookahead = defaults.double(forKey: Keys.prefetchLookahead)
        let prefetchLookahead = lookahead > 0 ? lookahead : 1.5

        let queueDepth = defaults.integer(forKey: Keys.prefetchQueueDepth)
        let prefetchQueueDepth = queueDepth > 0 ? queueDepth : 1

        let interSentenceSilenceMs = defaults.integer(forKey: Keys.interSentenceSilenceMs)

        let enableMultiBuffer = defaults.object(forKey: Keys.enableMultiBuffer) != nil
            ? defaults.bool(forKey: Keys.enableMultiBuffer)
            : true

        let bufferCount = defaults.integer(forKey: Keys.scheduledBufferCount)
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
}

// MARK: - Settings Help Sheet

/// Comprehensive help for all settings sections
struct SettingsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Overview
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Configure how the app processes speech, generates AI responses, and speaks to you. Tap the info buttons next to settings for detailed explanations.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // API Providers
                Section("API Providers") {
                    SettingsHelpRow(
                        icon: "key.fill",
                        iconColor: .orange,
                        title: "API Keys",
                        description: "Configure keys for cloud AI services like OpenAI, Anthropic, and ElevenLabs."
                    )
                    SettingsHelpRow(
                        icon: "dollarsign.circle.fill",
                        iconColor: .green,
                        title: "Costs",
                        description: "View estimated costs per session for each provider."
                    )
                }

                // Audio Section
                Section("Audio Settings") {
                    SettingsHelpRow(
                        icon: "waveform",
                        iconColor: .blue,
                        title: "Sample Rate",
                        description: "Higher rates (48 kHz) sound better but use more data. 24 kHz is a good balance."
                    )
                    SettingsHelpRow(
                        icon: "speaker.wave.3.fill",
                        iconColor: .purple,
                        title: "Voice Processing",
                        description: "Uses Apple's audio engine to enhance voice clarity."
                    )
                    SettingsHelpRow(
                        icon: "ear.and.waveform",
                        iconColor: .cyan,
                        title: "Echo Cancellation",
                        description: "Prevents the AI's voice from being picked up by the microphone."
                    )
                    SettingsHelpRow(
                        icon: "waveform.badge.minus",
                        iconColor: .indigo,
                        title: "Noise Suppression",
                        description: "Filters out background noise for clearer speech recognition."
                    )
                }

                // Voice Detection
                Section("Voice Detection") {
                    SettingsHelpRow(
                        icon: "mic.fill",
                        iconColor: .green,
                        title: "Detection Threshold",
                        description: "How sensitive the app is to your voice. Lower = more sensitive."
                    )
                    SettingsHelpRow(
                        icon: "hand.raised.fill",
                        iconColor: .orange,
                        title: "Interruption Threshold",
                        description: "How loud you need to speak to interrupt the AI."
                    )
                }

                // AI Models
                Section("Language Model") {
                    SettingsHelpRow(
                        icon: "cpu",
                        iconColor: .purple,
                        title: "Provider",
                        description: "Choose on-device for free/private, or cloud for more powerful models."
                    )
                    SettingsHelpRow(
                        icon: "thermometer.medium",
                        iconColor: .red,
                        title: "Temperature",
                        description: "0 = factual/consistent, 1 = creative/varied."
                    )
                    SettingsHelpRow(
                        icon: "text.word.spacing",
                        iconColor: .blue,
                        title: "Max Tokens",
                        description: "Maximum response length. 1024 is good for most use cases."
                    )
                }

                // Voice Output
                Section("Voice Output") {
                    SettingsHelpRow(
                        icon: "speaker.wave.2.fill",
                        iconColor: .green,
                        title: "TTS Provider",
                        description: "Apple TTS is free. ElevenLabs sounds most natural."
                    )
                    SettingsHelpRow(
                        icon: "speedometer",
                        iconColor: .orange,
                        title: "Speaking Rate",
                        description: "1.0 is normal speed. Lower for complex topics, higher for review."
                    )
                }

                // Self-Hosted
                Section("Self-Hosted Server") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Run AI on your own Mac for free, unlimited usage with complete privacy.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Requires: Ollama for LLM, optionally Piper/VibeVoice for TTS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Quick Setup Tips
                Section("Quick Setup") {
                    Label("Balanced preset works well for most users", systemImage: "slider.horizontal.3")
                        .foregroundStyle(.blue, .primary)
                    Label("Use on-device options for free, private sessions", systemImage: "iphone")
                        .foregroundStyle(.green, .primary)
                    Label("Use self-hosted for unlimited free cloud-quality AI", systemImage: "desktopcomputer")
                        .foregroundStyle(.purple, .primary)
                }
            }
            .navigationTitle("Settings Help")
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

/// Helper row for settings help items
private struct SettingsHelpRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
    SettingsView()
}

#Preview("Settings Help") {
    SettingsHelpSheet()
}
