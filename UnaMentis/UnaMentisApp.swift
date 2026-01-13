// UnaMentis
// Real-Time Bidirectional Voice AI Platform for Extended Educational Conversations
//
// Entry point for the UnaMentis application.

import SwiftUI
import Logging

/// Main application entry point
@main
struct UnaMentisApp: App {
    /// Application state container
    @StateObject private var appState = AppState()

    /// Logger for app-level events (used after logging system is bootstrapped)
    private static let logger = Logger(label: "com.unamentis.app")

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
        let buildID = "TTS_QUEUE_FIX_20251219_X"
        print("=======================================================")
        print("UnaMentis App Starting")
        print("Version: \(appVersion) (Build \(buildNumber))")
        print("Build Date: \(buildDate)")
        print("Build ID: \(buildID)")
        print("=======================================================")

        // CRITICAL: Initialize Core Data store EARLY, before any views access it
        // This prevents deadlock when views try to access PersistenceController.shared
        // from the main thread during SwiftUI view lifecycle
        _ = PersistenceController.shared
        print("[Init] Core Data store initialized")

        // Activate Watch connectivity for companion app communication
        WatchConnectivityService.shared.activateSession()
        print("[Init] WatchConnectivity activated")

        // Configure remote logging server
        // For simulator: localhost works automatically
        // For device: set the IP of your Mac running log_server.py
        #if DEBUG
        // Determine effective log server IP (same logic as SettingsView)
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let primaryServerIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
        let logServerUsesSameIP = UserDefaults.standard.bool(forKey: "logServerUsesSameIP")
        let logServerIP = UserDefaults.standard.string(forKey: "logServerIP") ?? ""

        let effectiveLogIP: String
        if logServerUsesSameIP && selfHostedEnabled && !primaryServerIP.isEmpty {
            effectiveLogIP = primaryServerIP
        } else {
            effectiveLogIP = logServerIP
        }

        if !effectiveLogIP.isEmpty {
            print("[Logging] Using log server IP: \(effectiveLogIP)")
            RemoteLogging.configure(serverIP: effectiveLogIP)
        } else {
            print("[Logging] No log server IP configured, using localhost (simulator only)")
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

        // Initialize feature flags (non-blocking background task)
        Task {
            do {
                try await FeatureFlagService.shared.start()
                Self.logger.info("Feature flags initialized")
            } catch {
                Self.logger.warning("Feature flags failed to start: \(error.localizedDescription)")
            }
        }
        print("[Init] Feature flags initialization started")
    }

    /// Whether the user has completed onboarding
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                // Enable Dynamic Type scaling for accessibility
                .dynamicTypeSize(.medium ... .accessibility3)
                // Handle deep links from Siri and Shortcuts
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                // Show onboarding for first-time users
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { if $0 == false { hasCompletedOnboarding = true } }
                )) {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
        }
    }

    /// Handle deep links from Siri Shortcuts and App Intents
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "unamentis" else { return }

        switch url.host {
        case "lesson":
            // Handle: unamentis://lesson?id=UUID&depth=intermediate
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
               UUID(uuidString: idString) != nil {
                // Navigate to lesson with the specified topic
                // The appState.selectedTab and navigation will be handled by ContentView
                Self.logger.info("DeepLink: Start lesson \(idString)")
                NotificationCenter.default.post(
                    name: .startLessonFromDeepLink,
                    object: nil,
                    userInfo: ["topicId": idString]
                )
            }

        case "resume":
            // Handle: unamentis://resume?id=UUID
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let idString = components.queryItems?.first(where: { $0.name == "id" })?.value {
                Self.logger.info("DeepLink: Resume lesson \(idString)")
                NotificationCenter.default.post(
                    name: .resumeLessonFromDeepLink,
                    object: nil,
                    userInfo: ["topicId": idString]
                )
            }

        case "analytics":
            // Handle: unamentis://analytics
            Self.logger.info("DeepLink: Show analytics")
            NotificationCenter.default.post(name: .showAnalyticsFromDeepLink, object: nil)

        case "chat":
            // Handle: unamentis://chat?prompt=optional
            var userInfo: [String: Any] = [:]
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let prompt = components.queryItems?.first(where: { $0.name == "prompt" })?.value {
                userInfo["prompt"] = prompt
            }
            print("[DeepLink] Start chat\(userInfo.isEmpty ? "" : " with prompt")")
            NotificationCenter.default.post(
                name: .startChatFromDeepLink,
                object: nil,
                userInfo: userInfo.isEmpty ? nil : userInfo
            )

        default:
            Self.logger.warning("DeepLink: Unknown path: \(url.host ?? "nil")")
        }
    }
}

// MARK: - Deep Link Notifications

extension Notification.Name {
    /// Posted when a lesson should start from a deep link
    static let startLessonFromDeepLink = Notification.Name("startLessonFromDeepLink")
    /// Posted when a lesson should resume from a deep link
    static let resumeLessonFromDeepLink = Notification.Name("resumeLessonFromDeepLink")
    /// Posted when analytics should be shown from a deep link
    static let showAnalyticsFromDeepLink = Notification.Name("showAnalyticsFromDeepLink")
    /// Posted when freeform chat should start from a deep link
    static let startChatFromDeepLink = Notification.Name("startChatFromDeepLink")
}

// MARK: - Launch Screen View

/// Simple splash screen shown while app initializes
struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("LogoExpanded")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300)

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

/// Tab indices for programmatic navigation
enum AppTab: Int {
    case session = 0
    case learning = 1
    case todo = 2
    case history = 3
    case analytics = 4
    case settings = 5
}

// MARK: - Session Activity State

/// Observable state for tracking whether a tutoring session is active
/// Used to show/hide the tab bar during active sessions
///
/// IMPORTANT: This class uses explicit change guards to prevent unnecessary
/// SwiftUI re-renders. Always use the update methods rather than setting
/// properties directly.
@MainActor
final class SessionActivityState: ObservableObject {
    /// Whether a tutoring session is currently active (not paused)
    @Published private(set) var isSessionActive: Bool = false

    /// Whether the session is paused (tab bar should be visible when paused)
    @Published private(set) var isPaused: Bool = false

    /// Whether the tab bar should be hidden (derived from isSessionActive and isPaused)
    /// Using @Published instead of computed property to avoid re-render loops
    @Published private(set) var shouldHideTabBar: Bool = false

    /// Update session active state with change guard to prevent unnecessary publishes
    func setSessionActive(_ newValue: Bool) {
        guard isSessionActive != newValue else { return }
        isSessionActive = newValue
        updateShouldHideTabBar()
    }

    /// Update paused state with change guard to prevent unnecessary publishes
    func setPaused(_ newValue: Bool) {
        guard isPaused != newValue else { return }
        isPaused = newValue
        updateShouldHideTabBar()
    }

    /// Reset all state (used when leaving session view)
    func reset() {
        // Use change guards on ALL properties to prevent unnecessary @Published triggers
        if isSessionActive {
            isSessionActive = false
        }
        if isPaused {
            isPaused = false
        }
        if shouldHideTabBar {
            shouldHideTabBar = false
        }
    }

    /// Internal method to update derived shouldHideTabBar state
    private func updateShouldHideTabBar() {
        let newValue = isSessionActive && !isPaused
        guard shouldHideTabBar != newValue else { return }
        shouldHideTabBar = newValue
    }
}

/// Root content view with tab navigation
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var sessionActivityState = SessionActivityState()
    @State private var isLoading: Bool = true

    /// Logger for tab navigation debugging
    private static let logger = Logger(label: "com.unamentis.contentview")

    /// Selected tab for programmatic navigation from deep links
    @State private var selectedTab: Int = AppTab.session.rawValue

    /// Topic to open in session (from deep link)
    @State private var deepLinkTopicId: UUID?

    /// Whether to auto-start freeform chat (from deep link)
    @State private var autoStartChat: Bool = false

    /// Initial prompt for freeform chat (from deep link)
    @State private var chatPrompt: String?

    var body: some View {
        ZStack {
            if isLoading {
                LaunchScreenView()
            } else {
                mainContent
            }
        }
        .environmentObject(sessionActivityState)
        .task {
            // Initialize AppState async components (non-blocking)
            await appState.initializeAsync()

            // Give UI a moment to initialize and show splash
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.3)) {
                isLoading = false
            }
        }
        // Deep link notification observers
        .onReceive(NotificationCenter.default.publisher(for: .startLessonFromDeepLink)) { notification in
            handleStartLesson(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .resumeLessonFromDeepLink)) { notification in
            handleResumeLesson(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAnalyticsFromDeepLink)) { _ in
            handleShowAnalytics()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startChatFromDeepLink)) { notification in
            handleStartChat(notification)
        }
    }

    // MARK: - Deep Link Handlers

    private func handleStartLesson(_ notification: Notification) {
        guard let topicIdString = notification.userInfo?["topicId"] as? String,
              let topicId = UUID(uuidString: topicIdString) else { return }

        deepLinkTopicId = topicId
        autoStartChat = false
        selectedTab = AppTab.session.rawValue
    }

    private func handleResumeLesson(_ notification: Notification) {
        guard let topicIdString = notification.userInfo?["topicId"] as? String,
              let topicId = UUID(uuidString: topicIdString) else { return }

        deepLinkTopicId = topicId
        autoStartChat = false
        selectedTab = AppTab.session.rawValue
    }

    private func handleShowAnalytics() {
        deepLinkTopicId = nil
        autoStartChat = false
        selectedTab = AppTab.analytics.rawValue
    }

    private func handleStartChat(_ notification: Notification) {
        deepLinkTopicId = nil
        autoStartChat = true
        chatPrompt = notification.userInfo?["prompt"] as? String
        selectedTab = AppTab.session.rawValue
    }

    @ViewBuilder
    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            // NOTE: Removed debug logging from view body to prevent potential side effects
            SessionTabContent(
                deepLinkTopicId: $deepLinkTopicId,
                autoStartChat: $autoStartChat,
                chatPrompt: $chatPrompt
            )
            .tabItem {
                Label("Session", systemImage: "waveform")
            }
            .tag(AppTab.session.rawValue)
            #if os(iOS)
            .toolbar(sessionActivityState.shouldHideTabBar ? .hidden : .visible, for: .tabBar)
            #endif

            LearningView()
                .tabItem {
                    Label("Learning", systemImage: "graduationcap")
                }
                .tag(AppTab.learning.rawValue)

            TodoListView()
                .tabItem {
                    Label("To-Do", systemImage: "checklist")
                }
                .tag(AppTab.todo.rawValue)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(AppTab.history.rawValue)

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
                .tag(AppTab.analytics.rawValue)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings.rawValue)
        }
        // NOTE: Removed .animation() modifier here - it was causing continuous view re-renders
        // The tab bar visibility change is now handled without animation to prevent lockups
        // If animation is needed, use withAnimation() at the point where shouldHideTabBar is set
        .onChange(of: selectedTab) { oldTab, newTab in
            let oldName = AppTab(rawValue: oldTab).map { "\($0)" } ?? "unknown"
            let newName = AppTab(rawValue: newTab).map { "\($0)" } ?? "unknown"
            Self.logger.info("TAB SWITCH: \(oldName) -> \(newName)")
        }
    }
}

// MARK: - Session Tab Content

/// Container view for the Session tab that handles deep link navigation
///
/// This view manages the session state based on incoming deep links:
/// - Deep link with topic ID: Opens SessionView with the specified topic
/// - Deep link for chat: Opens SessionView for freeform conversation
/// - No deep link: Shows the default session selector
struct SessionTabContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.managedObjectContext) private var viewContext

    private static let logger = Logger(label: "com.unamentis.sessiontab")

    /// Topic ID from deep link (binding to parent so we can clear it)
    @Binding var deepLinkTopicId: UUID?

    /// Whether to auto-start freeform chat
    @Binding var autoStartChat: Bool

    /// Initial prompt for chat (optional)
    @Binding var chatPrompt: String?

    /// The fetched topic for deep link navigation
    @State private var deepLinkTopic: Topic?

    /// Whether we're showing a deep-link triggered session
    @State private var showingDeepLinkSession: Bool = false

    var body: some View {
        // NOTE: Removed debug logging from view body
        NavigationStack {
            Group {
                if showingDeepLinkSession {
                    // Show session triggered by deep link
                    if let topic = deepLinkTopic {
                        // Curriculum-based session
                        SessionView(topic: topic)
                    } else if autoStartChat {
                        // Freeform chat session with auto-start
                        FreeformSessionView(initialPrompt: chatPrompt)
                    } else {
                        // Fallback to regular session
                        SessionView()
                    }
                } else {
                    // Default session view - user can start a new session
                    SessionView()
                }
            }
        }
        .onChange(of: deepLinkTopicId) { _, newValue in
            if let topicId = newValue {
                fetchTopic(id: topicId)
            }
        }
        .onChange(of: autoStartChat) { _, newValue in
            if newValue {
                // Freeform chat requested
                deepLinkTopic = nil
                showingDeepLinkSession = true
            }
        }
        .onDisappear {
            // Clear deep link state when navigating away
            clearDeepLinkState()
        }
    }

    private func fetchTopic(id: UUID) {
        let request = Topic.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            let context = PersistenceController.shared.container.viewContext
            if let topic = try context.fetch(request).first {
                deepLinkTopic = topic
                showingDeepLinkSession = true
            } else {
                print("[SessionTabContent] Topic not found: \(id)")
                // Clear the deep link state since topic wasn't found
                clearDeepLinkState()
            }
        } catch {
            print("[SessionTabContent] Error fetching topic: \(error)")
            clearDeepLinkState()
        }
    }

    private func clearDeepLinkState() {
        deepLinkTopicId = nil
        autoStartChat = false
        chatPrompt = nil
        deepLinkTopic = nil
        showingDeepLinkSession = false
    }
}

// MARK: - Freeform Session View

/// A wrapper around SessionView specifically for freeform voice chat
/// that auto-starts the session when triggered from Siri
struct FreeformSessionView: View {
    let initialPrompt: String?

    var body: some View {
        // Use SessionView with autoStart=true for hands-free operation
        SessionView(topic: nil, autoStart: true)
    }
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
///
/// Architecture Note:
/// Initialization is synchronous and non-blocking. Async setup (configuration
/// checks, patch panel initialization) is deferred and triggered via
/// `initializeAsync()` from a view's `.task` modifier to prevent MainActor
/// contention during app launch.
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

    /// Whether async initialization has been performed
    private var hasInitializedAsync = false

    // MARK: - Initialization

    /// Synchronous initialization, non-blocking
    /// Call `initializeAsync()` from a view's `.task` modifier to complete setup
    public init() {
        // Initialize patch panel with telemetry (synchronous)
        self.patchPanel = PatchPanelService(telemetry: telemetry)

        // Detect device capability tier (synchronous, no I/O)
        self.deviceTier = Self.detectDeviceTier()

        // NOTE: No Task spawning here! Async work is deferred to initializeAsync()
    }

    /// Perform async initialization
    /// Call this from a view's `.task` modifier after the view hierarchy is set up
    public func initializeAsync() async {
        guard !hasInitializedAsync else { return }
        hasInitializedAsync = true

        await checkConfiguration()
        await initializePatchPanel()
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
