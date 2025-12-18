// VoiceLearn iOS
// Real-Time Bidirectional Voice AI Platform for Extended Educational Conversations
//
// Entry point for the VoiceLearn application.

import SwiftUI
import Logging

/// Main application entry point
@main
struct VoiceLearnApp: App {
    /// Application state container
    @StateObject private var appState = AppState()

    /// Get the build date from the app bundle's executable
    private static func getBuildDate() -> String {
        guard let executablePath = Bundle.main.executablePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath),
              let modDate = attributes[.modificationDate] as? Date else {
            return "unknown"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: modDate)
    }

    /// Configure logging on app launch
    init() {
        // Log app version immediately at startup for debugging
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let buildDate = Self.getBuildDate()
        // Unique build ID - change this each time to verify new build is running
        let buildID = "TTS_PIPER_FIX_20251218_J"
        print("=======================================================")
        print("VoiceLearn App Starting")
        print("Version: \(appVersion) (Build \(buildNumber))")
        print("Build Date: \(buildDate)")
        print("Build ID: \(buildID)")
        print("=======================================================")

        // CRITICAL: Initialize Core Data store EARLY, before any views access it
        // This prevents deadlock when views try to access PersistenceController.shared
        // from the main thread during SwiftUI view lifecycle
        _ = PersistenceController.shared
        print("[Init] Core Data store initialized")

        // Configure remote logging server
        // For simulator: localhost works automatically
        // For device: set the IP of your Mac running log_server.py
        #if DEBUG
        // Read server IP from UserDefaults or use localhost
        if let serverIP = UserDefaults.standard.string(forKey: "logServerIP"), !serverIP.isEmpty {
            RemoteLogging.configure(serverIP: serverIP)
        } else {
            RemoteLogging.configure() // Uses localhost for simulator
        }
        #endif

        // Bootstrap logging with both console and remote handlers
        LoggingSystem.bootstrap { label in
            #if DEBUG
            // In debug builds, send logs to both console and remote server
            var consoleHandler = StreamLogHandler.standardOutput(label: label)
            consoleHandler.logLevel = .debug

            let remoteHandler = RemoteLogHandler(label: label)

            return MultiplexLogHandler([
                consoleHandler,
                remoteHandler
            ])
            #else
            // In release builds, only use console handler with info level
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
            #endif
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Launch Screen View

/// Simple splash screen shown while app initializes
struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("VoiceLearn")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.top, 10)

                Text("Loading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Root content view with tab navigation
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var debugTestResult: String = ""
    @State private var isTestingLLM: Bool = false
    @State private var isLoading: Bool = true

    var body: some View {
        ZStack {
            if isLoading {
                LaunchScreenView()
            } else {
                mainContent
            }
        }
        .task {
            // Give UI a moment to initialize and show splash
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeOut(duration: 0.3)) {
                isLoading = false
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        TabView {
            // Debug LLM test view on first tab in DEBUG builds
            #if DEBUG
            VStack(spacing: 20) {
                Text("LLM Debug Test")
                    .font(.title)

                if isTestingLLM {
                    ProgressView("Testing LLM...")
                } else {
                    Button("Test LLM") {
                        Task {
                            await testOnDeviceLLM()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                ScrollView {
                    Text(debugTestResult)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding()
            }
            .tabItem {
                Label("Debug", systemImage: "ladybug")
            }
            // Note: Auto-LLM test removed - it caused hangs on physical device
            // when trying to connect to localhost. Use the Test button manually.
            #endif

            SessionView()
                .tabItem {
                    Label("Session", systemImage: "waveform")
                }
            
            CurriculumView()
                .tabItem {
                    Label("Curriculum", systemImage: "book")
                }
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
            
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }

    #if DEBUG
    /// Debug test function to directly test on-device LLM without voice input
    private func testOnDeviceLLM() async {
        print("[DEBUG] Starting direct LLM test")
        isTestingLLM = true
        debugTestResult = "Testing LLM...\n"

        // Use SelfHostedLLMService to connect to local Ollama server for testing
        let llmService = SelfHostedLLMService.ollama(model: "qwen2.5:32b")

        let messages = [
            LLMMessage(role: .system, content: "You are a helpful assistant. Be brief."),
            LLMMessage(role: .user, content: "Hello! Say hi in one sentence.")
        ]

        // Use a config with empty model to let the service use its configured model
        var config = LLMConfig.default
        config.model = ""  // Let SelfHostedLLMService use its configured model (llama3.2:3b)

        do {
            debugTestResult += "[DEBUG] Calling streamCompletion...\n"
            print("[DEBUG] Calling streamCompletion...")
            let stream = try await llmService.streamCompletion(messages: messages, config: config)

            var response = ""
            debugTestResult += "[DEBUG] Iterating stream...\n"
            print("[DEBUG] Iterating stream...")

            for await token in stream {
                response += token.content
                debugTestResult = "Response so far: \(response)\n"
                print("[DEBUG] Token: '\(token.content)', isDone: \(token.isDone)")

                if token.isDone {
                    break
                }
            }

            debugTestResult = "SUCCESS!\n\nResponse:\n\(response)"
            print("[DEBUG] LLM test complete: \(response)")

        } catch {
            debugTestResult = "ERROR:\n\(error.localizedDescription)\n\nFull error:\n\(error)"
            print("[DEBUG] LLM test error: \(error)")
        }

        isTestingLLM = false
    }
    #endif
}



// MARK: - App State

/// Central application state container
/// Manages all core services and shared state
///
/// AppState is the central hub that:
/// - Initializes and holds references to all core services
/// - Manages application configuration state
/// - Provides factory methods for creating session managers
/// - Coordinates between subsystems (Telemetry, PatchPanel, Curriculum, etc.)
@MainActor
public class AppState: ObservableObject {

    // MARK: - Core Services

    /// Telemetry engine for metrics tracking
    public let telemetry = TelemetryEngine()

    /// API key manager
    public let apiKeys = APIKeyManager.shared

    /// Patch panel for LLM routing decisions
    /// This is the central routing hub that determines which LLM endpoint
    /// handles each task based on task type, device conditions, and rules.
    public private(set) var patchPanel: PatchPanelService!

    /// Curriculum engine for content management
    @Published public var curriculum: CurriculumEngine?

    /// Session manager (created when session starts)
    @Published public var sessionManager: SessionManager?

    // MARK: - State

    /// Whether the app has all required configuration
    @Published public var isConfigured: Bool = false

    /// Current device capability tier
    @Published public var deviceTier: DeviceCapabilityTier = .proMax

    // MARK: - Initialization

    public init() {
        // Initialize patch panel with telemetry
        self.patchPanel = PatchPanelService(telemetry: telemetry)

        // Detect device capability tier
        self.deviceTier = Self.detectDeviceTier()

        Task {
            await checkConfiguration()
            await initializePatchPanel()
        }
    }

    // MARK: - Configuration

    /// Check if all required API keys are configured
    private func checkConfiguration() async {
        let missingKeys = await apiKeys.validateRequiredKeys()
        await MainActor.run {
            isConfigured = missingKeys.isEmpty
        }

        if isConfigured {
            await initializeCurriculum()
        }
    }

    /// Initialize the patch panel with current endpoint availability
    private func initializePatchPanel() async {
        // Update endpoint availability based on API key presence
        let hasOpenAI = await apiKeys.getKey(.openAI) != nil
        let hasAnthropic = await apiKeys.getKey(.anthropic) != nil

        // Mark cloud endpoints as available/unavailable based on keys
        if hasOpenAI {
            await patchPanel.setEndpointStatus("gpt-4o", status: .available)
            await patchPanel.setEndpointStatus("gpt-4o-mini", status: .available)
        } else {
            await patchPanel.setEndpointStatus("gpt-4o", status: .unavailable)
            await patchPanel.setEndpointStatus("gpt-4o-mini", status: .unavailable)
        }

        if hasAnthropic {
            await patchPanel.setEndpointStatus("claude-3.5-sonnet", status: .available)
            await patchPanel.setEndpointStatus("claude-3.5-haiku", status: .available)
        } else {
            await patchPanel.setEndpointStatus("claude-3.5-sonnet", status: .unavailable)
            await patchPanel.setEndpointStatus("claude-3.5-haiku", status: .unavailable)
        }

        // Self-hosted endpoints start as unavailable until configured
        await patchPanel.setEndpointStatus("llama-70b-server", status: .unavailable)
        await patchPanel.setEndpointStatus("llama-8b-server", status: .unavailable)

        // On-device LLM currently unavailable (API incompatible), mark as unavailable
        // Using SelfHostedLLMService (Ollama) instead
        await patchPanel.setEndpointStatus("llama-3b-device", status: .unavailable)
        // 1B model not currently bundled
        await patchPanel.setEndpointStatus("llama-1b-device", status: .unavailable)
    }

    private func initializeCurriculum() async {
        guard let openAIKey = await apiKeys.getKey(.openAI) else { return }

        let embeddingService = OpenAIEmbeddingService(apiKey: openAIKey)
        let engine = CurriculumEngineFactory.create(
            persistenceController: .shared,
            embeddingService: embeddingService,
            telemetry: telemetry
        )

        await MainActor.run {
            self.curriculum = engine
        }
    }

    // MARK: - Session Management

    /// Create a new session manager with configured services
    public func createSessionManager() async throws -> SessionManager {
        guard isConfigured else {
            throw SessionError.servicesNotConfigured
        }

        let manager = SessionManager(
            telemetry: telemetry,
            curriculum: curriculum
        )
        sessionManager = manager
        return manager
    }

    // MARK: - Device Tier Detection

    /// Detect the current device's capability tier
    private static func detectDeviceTier() -> DeviceCapabilityTier {
        // Get device identifier
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }

        // Get RAM in GB
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)

        // Tier 1: Pro Max devices with 8GB+ RAM
        let tier1Identifiers: Set<String> = [
            "iPhone15,3",  // iPhone 14 Pro Max
            "iPhone16,2",  // iPhone 15 Pro Max
            "iPhone17,2",  // iPhone 16 Pro Max
            // Simulator
            "x86_64", "arm64"
        ]

        if tier1Identifiers.contains(identifier) && ramGB >= 8 {
            return .proMax
        }

        // Tier 2: Pro devices with 6GB+ RAM
        let tier2Identifiers: Set<String> = [
            "iPhone14,2",  // iPhone 13 Pro
            "iPhone14,3",  // iPhone 13 Pro Max
            "iPhone15,2",  // iPhone 14 Pro
            "iPhone15,3",  // iPhone 14 Pro Max
            "iPhone16,1",  // iPhone 15 Pro
            "iPhone16,2",  // iPhone 15 Pro Max
            "iPhone17,1",  // iPhone 16 Pro
            "iPhone17,2",  // iPhone 16 Pro Max
            // Simulator (treat as tier 2 for testing)
            "x86_64", "arm64"
        ]

        if tier2Identifiers.contains(identifier) && ramGB >= 6 {
            return .proStandard
        }

        // For simulator, default to proStandard for testing
        if identifier == "x86_64" || identifier == "arm64" {
            return .proStandard
        }

        return .unsupported
    }

    // MARK: - Routing Context

    /// Create a routing context with current device/system state
    public func createRoutingContext() -> RoutingContext {
        // In a full implementation, this would query real system state
        // For now, we provide reasonable defaults

        let thermalState: ThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = .nominal
        case .fair: thermalState = .fair
        case .serious: thermalState = .serious
        case .critical: thermalState = .critical
        @unknown default: thermalState = .nominal
        }

        return RoutingContext(
            thermalState: thermalState,
            memoryPressure: .normal,  // Would need to query os_proc_available_memory
            availableMemoryMB: 4000,
            batteryLevel: 1.0,  // Would query UIDevice.current.batteryLevel
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            deviceTier: deviceTier,
            networkType: .wifi,  // Would query NWPathMonitor
            networkLatencyMs: 50.0,
            endpointStatuses: [:],
            endpointLatencies: [:],
            remainingBudget: 1.0,
            estimatedTaskCost: 0.01,
            sessionDurationSeconds: 0,
            promptTokenCount: 0,
            contextTokenCount: 0
        )
    }

    // MARK: - Developer Mode

    /// Enable developer mode for patch panel access
    public func enableDeveloperMode() async {
        await patchPanel.enableDeveloperMode()
    }

    /// Disable developer mode
    public func disableDeveloperMode() async {
        await patchPanel.disableDeveloperMode()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
