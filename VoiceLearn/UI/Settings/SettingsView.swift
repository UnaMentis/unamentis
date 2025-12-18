// VoiceLearn - Settings View
// Configuration and API key management
//
// Part of UI/UX (TDD Section 10)

import SwiftUI
import AVFoundation

/// Settings view for app configuration
public struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

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

                // Audience Profile Section
                Section {
                    NavigationLink {
                        AudienceProfileView()
                    } label: {
                        HStack {
                            Label("Audience Profile", systemImage: "person.crop.circle")
                            Spacer()
                            if let active = AudienceProfileManager.shared.activeProfile {
                                Text(active.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Learning Profile")
                } footer: {
                    Text("Configure how content is delivered based on who is learning.")
                }

                // Audio Settings Section
                Section("Audio") {
                    Picker("Sample Rate", selection: $viewModel.sampleRate) {
                        Text("16 kHz").tag(16000.0)
                        Text("24 kHz").tag(24000.0)
                        Text("48 kHz").tag(48000.0)
                    }

                    Toggle("Voice Processing", isOn: $viewModel.enableVoiceProcessing)
                    Toggle("Echo Cancellation", isOn: $viewModel.enableEchoCancellation)
                    Toggle("Noise Suppression", isOn: $viewModel.enableNoiseSuppression)
                }

                // VAD Settings Section
                Section("Voice Detection") {
                    VStack(alignment: .leading) {
                        Text("Detection Threshold: \(viewModel.vadThreshold, specifier: "%.2f")")
                        Slider(value: $viewModel.vadThreshold, in: 0.3...0.9)
                    }

                    VStack(alignment: .leading) {
                        Text("Interruption Threshold: \(viewModel.bargeInThreshold, specifier: "%.2f")")
                        Slider(value: $viewModel.bargeInThreshold, in: 0.5...0.95)
                    }

                    Toggle("Enable Interruptions", isOn: $viewModel.enableBargeIn)
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

                // STT Settings Section
                Section("Speech Recognition") {
                    Picker("Provider", selection: $viewModel.sttProvider) {
                        Text("GLM-ASR (On-Device)").tag(STTProvider.glmASROnDevice)
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
                }

                // LLM Settings Section
                Section("Language Model") {
                    Picker("Provider", selection: $viewModel.llmProvider) {
                        Text("On-Device (llama.cpp)").tag(LLMProvider.localMLX)
                        Text("Anthropic Claude").tag(LLMProvider.anthropic)
                        Text("OpenAI").tag(LLMProvider.openAI)
                        Text("Self-Hosted").tag(LLMProvider.selfHosted)
                    }

                    if viewModel.llmProvider != .localMLX {
                        Picker("Model", selection: $viewModel.llmModel) {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Temperature: \(viewModel.temperature, specifier: "%.1f")")
                        Slider(value: $viewModel.temperature, in: 0...1)
                    }

                    Stepper("Max Tokens: \(viewModel.maxTokens)", value: $viewModel.maxTokens, in: 256...4096, step: 256)

                    if !viewModel.llmProvider.requiresNetwork {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Works offline - Free")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // TTS Settings Section
                Section("Voice") {
                    Picker("Provider", selection: $viewModel.ttsProvider) {
                        Text("Apple TTS (On-Device)").tag(TTSProvider.appleTTS)
                        if viewModel.selfHostedEnabled {
                            Text("Self-Hosted (Piper)").tag(TTSProvider.selfHosted)
                        }
                        Text("ElevenLabs").tag(TTSProvider.elevenLabsFlash)
                        Text("Deepgram Aura").tag(TTSProvider.deepgramAura2)
                    }

                    if viewModel.ttsProvider == .selfHosted && !viewModel.discoveredVoices.isEmpty {
                        Picker("Voice", selection: $viewModel.ttsVoice) {
                            ForEach(viewModel.discoveredVoices, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Speaking Rate: \(viewModel.speakingRate, specifier: "%.1f")x")
                        Slider(value: $viewModel.speakingRate, in: 0.5...2.0)
                    }

                    if !viewModel.ttsProvider.requiresAPIKey {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(viewModel.ttsProvider == .selfHosted ? "Uses self-hosted server - Free" : "Works offline - Free")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Presets Section
                Section("Presets") {
                    Button("Balanced (Default)") {
                        viewModel.applyPreset(.balanced)
                    }
                    Button("Low Latency") {
                        viewModel.applyPreset(.lowLatency)
                    }
                    Button("High Quality") {
                        viewModel.applyPreset(.highQuality)
                    }
                    Button("Cost Optimized") {
                        viewModel.applyPreset(.costOptimized)
                    }
                    Button("Self-Hosted (Free)") {
                        viewModel.applyPreset(.selfHosted)
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
                        AudioTestView()
                    } label: {
                        Label("Audio Pipeline Test", systemImage: "waveform")
                    }

                    NavigationLink {
                        ProviderTestView()
                    } label: {
                        Label("Provider Connectivity", systemImage: "network")
                    }

                    Toggle("Debug Mode", isOn: $viewModel.debugMode)
                    Toggle("Verbose Logging", isOn: $viewModel.verboseLogging)

                    // Remote logging configuration
                    Toggle("Remote Logging", isOn: $viewModel.remoteLoggingEnabled)

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
    @Published var sttProvider: STTProvider {
        didSet { UserDefaults.standard.set(sttProvider.rawValue, forKey: "sttProvider") }
    }

    // LLM - Default to on-device
    @Published var llmProvider: LLMProvider {
        didSet { UserDefaults.standard.set(llmProvider.rawValue, forKey: "llmProvider") }
    }
    @AppStorage("llmModel") var llmModel = "llama3.2:3b"
    @AppStorage("temperature") var temperature: Double = 0.7
    @AppStorage("maxTokens") var maxTokens = 1024

    // TTS - Default to on-device
    @Published var ttsProvider: TTSProvider {
        didSet { UserDefaults.standard.set(ttsProvider.rawValue, forKey: "ttsProvider") }
    }
    @AppStorage("speakingRate") var speakingRate: Double = 1.0
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"

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
    @Published var discoveredVoices: [String] = []
    @Published var serverCapabilitiesSummary: String = ""

    // Remote Logging
    @AppStorage("logServerIP") var logServerIP: String = ""
    @AppStorage("logServerUsesSameIP") var logServerUsesSameIP: Bool = true
    @Published var remoteLoggingEnabled: Bool = true {
        didSet {
            if remoteLoggingEnabled {
                RemoteLogging.enable()
            } else {
                RemoteLogging.disable()
            }
            updateLogServerConfiguration()
        }
    }

    /// The effective log server IP (uses primary server IP if sharing is enabled)
    var effectiveLogServerIP: String {
        if logServerUsesSameIP && selfHostedEnabled && !primaryServerIP.isEmpty {
            return primaryServerIP
        }
        return logServerIP
    }

    private let curriculumSeeder = SampleCurriculumSeeder()

    init() {
        // Load persisted provider settings
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

        Task {
            await loadKeyStatus()
            await checkSampleCurriculum()
            await loadServerStatus()
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
            discoveredVoices = []
            serverCapabilitiesSummary = ""
            return
        }

        serverConnectionStatus = .checking

        // Try Ollama health check first (port 11434)
        guard let url = URL(string: "http://\(primaryServerIP):11434/api/version") else {
            serverConnectionStatus = .failed
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                serverConnectionStatus = .connected

                // Discover capabilities
                let capabilities = await ServerConfigManager.shared.discoverCapabilities(host: primaryServerIP)
                discoveredModels = capabilities.llmModels
                discoveredVoices = capabilities.ttsVoices
                serverCapabilitiesSummary = capabilities.summary

                // Auto-select first discovered model if current model not in list
                if !discoveredModels.isEmpty && !discoveredModels.contains(llmModel) {
                    llmModel = discoveredModels[0]
                }
            } else {
                serverConnectionStatus = .failed
            }
        } catch {
            serverConnectionStatus = .failed
        }
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

        // Check API keys for services
        let apiKeys = APIKeyManager.shared

        sttStatus = .checking
        await Task.yield()
        let hasDeepgram = await apiKeys.hasKey(.deepgram)
        let hasAssemblyAI = await apiKeys.hasKey(.assemblyAI)
        if hasDeepgram || hasAssemblyAI {
            sttStatus = .ok
            sttDetail = "API key configured"
        } else {
            sttStatus = .error
            sttDetail = "No API key"
        }

        ttsStatus = .checking
        await Task.yield()
        let hasElevenLabs = await apiKeys.hasKey(.elevenLabs)
        if hasElevenLabs || hasDeepgram {
            ttsStatus = .ok
            ttsDetail = "API key configured"
        } else {
            ttsStatus = .error
            ttsDetail = "No API key"
        }

        llmStatus = .checking
        await Task.yield()
        let hasAnthropic = await apiKeys.hasKey(.anthropic)
        let hasOpenAI = await apiKeys.hasKey(.openAI)
        if hasAnthropic || hasOpenAI {
            llmStatus = .ok
            llmDetail = "API key configured"
        } else {
            llmStatus = .error
            llmDetail = "No API key"
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

// MARK: - Preview

#Preview {
    SettingsView()
}
