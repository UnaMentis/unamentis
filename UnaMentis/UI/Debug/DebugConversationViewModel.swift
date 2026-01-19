// UnaMentis - Debug Conversation ViewModel
// ViewModel for testing AI conversations without voice input
//
// DEBUG only - not included in release builds

#if DEBUG

import Foundation
import Combine
import Logging

/// Entry in the conversation log
struct ConversationEntry: Identifiable {
    let id = UUID()
    let role: ConversationRole
    let content: String
    let timestamp: Date

    enum ConversationRole {
        case user
        case assistant
        case system
        case error

        var displayName: String {
            switch self {
            case .user: return "You"
            case .assistant: return "AI"
            case .system: return "System"
            case .error: return "Error"
            }
        }
    }
}

/// Pre-defined test scenarios for multi-turn conversation testing
enum ConversationTestScenario: String, CaseIterable, Identifiable {
    case greeting = "Greeting & Follow-up"
    case factualQA = "Factual Q&A Chain"
    case conceptExplain = "Concept Explanation"

    var id: String { rawValue }

    var messages: [String] {
        switch self {
        case .greeting:
            return [
                "Hello, how are you?",
                "What topics can you help me learn about?",
                "Tell me something interesting about science."
            ]
        case .factualQA:
            return [
                "What is photosynthesis?",
                "Why is it important for life on Earth?",
                "How do plants get the light they need?"
            ]
        case .conceptExplain:
            return [
                "Can you explain what gravity is?",
                "How does that affect objects on Earth?",
                "What would happen without gravity?"
            ]
        }
    }

    var description: String {
        switch self {
        case .greeting:
            return "Tests basic conversation flow with 3 exchanges"
        case .factualQA:
            return "Tests contextual understanding across related questions"
        case .conceptExplain:
            return "Tests progressive explanation and follow-up handling"
        }
    }
}

/// ViewModel for debug conversation testing
@MainActor
class DebugConversationViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var inputText: String = ""
    @Published var conversationLog: [ConversationEntry] = []
    @Published var sessionState: SessionState = .idle
    @Published var isProcessing: Bool = false
    @Published var lastError: String?
    @Published var ttsStatus: String = "Not started"

    // Provider selection
    @Published var selectedLLMProvider: LLMProvider = .selfHosted
    @Published var selectedModel: String = ""
    @Published var availableModels: [String] = []
    @Published var useCurrentSettings: Bool = true

    // Session status
    @Published var isSessionActive: Bool = false
    @Published var turnCount: Int = 0
    @Published var lastLatency: TimeInterval = 0

    // MARK: - Private Properties

    private let logger = Logger(label: "com.unamentis.debug.conversation")
    private var sessionManager: SessionManager?
    private var cancellables = Set<AnyCancellable>()
    private weak var appState: AppState?

    // MARK: - Initialization

    init() {
        loadCurrentSettings()
    }

    // MARK: - Settings

    /// Load current provider/model settings from UserDefaults
    func loadCurrentSettings() {
        let llmProviderSetting = UserDefaults.standard.string(forKey: "llmProvider")
            .flatMap { LLMProvider(rawValue: $0) } ?? .selfHosted
        let modelSetting = UserDefaults.standard.string(forKey: "llmModel") ?? "llama3.2:3b"

        selectedLLMProvider = llmProviderSetting
        selectedModel = modelSetting
        updateAvailableModels()
    }

    /// Update available models based on selected provider
    func updateAvailableModels() {
        switch selectedLLMProvider {
        case .openAI:
            availableModels = ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
        case .anthropic:
            availableModels = ["claude-sonnet-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-haiku-20240307"]
        case .selfHosted, .localMLX:
            // Get discovered models from server
            Task {
                let discovered = await ServerConfigManager.shared.getAllDiscoveredModels()
                await MainActor.run {
                    self.availableModels = discovered.isEmpty ? ["llama3.2:3b", "llama3.2:1b", "mistral:7b"] : discovered
                    // Ensure selected model is in list
                    if !self.availableModels.contains(self.selectedModel) && !self.availableModels.isEmpty {
                        self.selectedModel = self.availableModels.first!
                    }
                }
            }
        }

        // Ensure selected model is valid for new provider
        if !availableModels.isEmpty && !availableModels.contains(selectedModel) {
            selectedModel = availableModels.first!
        }
    }

    // MARK: - Session Management

    /// Start a debug session with the selected LLM provider
    func startDebugSession(appState: AppState) async {
        self.appState = appState
        isProcessing = true
        lastError = nil

        defer { isProcessing = false }

        // Determine which provider/model to use
        let provider: LLMProvider
        let model: String

        if useCurrentSettings {
            provider = UserDefaults.standard.string(forKey: "llmProvider")
                .flatMap { LLMProvider(rawValue: $0) } ?? .selfHosted
            model = UserDefaults.standard.string(forKey: "llmModel") ?? "llama3.2:3b"
        } else {
            provider = selectedLLMProvider
            model = selectedModel
        }

        logger.info("[DEBUG] Starting session with provider: \(provider.rawValue), model: \(model)")
        addSystemMessage("Starting session with \(provider.displayName) - \(model)")

        // Create LLM service based on provider
        let llmService: any LLMService

        do {
            switch provider {
            case .anthropic:
                guard let apiKey = await appState.apiKeys.getKey(.anthropic) else {
                    throw DebugSessionError.missingAPIKey("Anthropic")
                }
                llmService = AnthropicLLMService(apiKey: apiKey)

            case .openAI:
                guard let apiKey = await appState.apiKeys.getKey(.openAI) else {
                    throw DebugSessionError.missingAPIKey("OpenAI")
                }
                llmService = OpenAILLMService(apiKey: apiKey)

            case .selfHosted, .localMLX:
                let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
                let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""

                if selfHostedEnabled && !serverIP.isEmpty {
                    logger.info("[DEBUG] Using self-hosted at \(serverIP):11434")
                    llmService = SelfHostedLLMService.ollama(host: serverIP, model: model)
                } else {
                    logger.warning("[DEBUG] No server IP - using localhost")
                    llmService = SelfHostedLLMService.ollama(model: model)
                }
            }

            // Create session manager
            let manager = try await appState.createSessionManager()
            self.sessionManager = manager

            // Subscribe to session state changes
            bindToSessionManager(manager)

            // Use a minimal STT service (not needed but required by API)
            let sttService = AppleSpeechSTTService()
            let ttsService = AppleTTSService()
            let vadService = SileroVADService()

            // Start the session
            try await manager.startSession(
                sttService: sttService,
                ttsService: ttsService,
                llmService: llmService,
                vadService: vadService,
                systemPrompt: "You are a helpful AI tutor. Keep responses concise and conversational.",
                lectureMode: false
            )

            isSessionActive = true
            addSystemMessage("Session started successfully")

        } catch {
            lastError = error.localizedDescription
            addErrorMessage("Failed to start session: \(error.localizedDescription)")
            logger.error("[DEBUG] Session start failed: \(error)")
        }
    }

    /// Stop the debug session
    func stopSession() async {
        guard let manager = sessionManager else { return }

        await manager.stopSession()
        isSessionActive = false
        sessionManager = nil
        sessionState = .idle
        ttsStatus = "Stopped"
        addSystemMessage("Session stopped")
    }

    /// Bind to session manager state updates
    private func bindToSessionManager(_ manager: SessionManager) {
        cancellables.removeAll()

        manager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.sessionState = state
                self?.updateTTSStatus(for: state)
            }
            .store(in: &cancellables)

        manager.$aiResponse
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] response in
                guard let self = self, !response.isEmpty else { return }
                // Update the last AI entry or add a new one
                self.updateOrAddAIResponse(response)
            }
            .store(in: &cancellables)
    }

    // MARK: - Message Handling

    /// Send the current input text to the AI
    func sendMessage() async {
        guard isSessionActive, let manager = sessionManager else {
            lastError = "No active session. Start a session first."
            return
        }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isProcessing = true
        inputText = ""

        // Add user message to log
        addUserMessage(text)

        // Inject the utterance
        let startTime = Date()
        await manager.injectUserUtterance(text)

        // Wait for response to complete
        await waitForResponseCompletion()

        lastLatency = Date().timeIntervalSince(startTime)
        turnCount += 1
        isProcessing = false
    }

    /// Run a pre-defined test scenario
    func runConversationTestScenario(_ scenario: ConversationTestScenario) async {
        guard isSessionActive else {
            lastError = "No active session. Start a session first."
            return
        }

        addSystemMessage("Running scenario: \(scenario.rawValue)")

        for (index, message) in scenario.messages.enumerated() {
            inputText = message
            await sendMessage()

            // Wait between messages for natural flow
            if index < scenario.messages.count - 1 {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s between messages
            }
        }

        addSystemMessage("Scenario complete: \(turnCount) turns")
    }

    /// Clear the conversation log
    func clearConversation() {
        conversationLog.removeAll()
        turnCount = 0
        lastLatency = 0
    }

    // MARK: - Private Helpers

    private func addUserMessage(_ text: String) {
        conversationLog.append(ConversationEntry(
            role: .user,
            content: text,
            timestamp: Date()
        ))
    }

    private func updateOrAddAIResponse(_ response: String) {
        // Check if the last entry is an AI response we can update
        if let lastIndex = conversationLog.lastIndex(where: { $0.role == .assistant }) {
            // Replace with updated content
            let updatedEntry = ConversationEntry(
                role: .assistant,
                content: response,
                timestamp: conversationLog[lastIndex].timestamp
            )
            conversationLog[lastIndex] = updatedEntry
        } else {
            // Add new AI response
            conversationLog.append(ConversationEntry(
                role: .assistant,
                content: response,
                timestamp: Date()
            ))
        }
    }

    private func addSystemMessage(_ text: String) {
        conversationLog.append(ConversationEntry(
            role: .system,
            content: text,
            timestamp: Date()
        ))
    }

    private func addErrorMessage(_ text: String) {
        conversationLog.append(ConversationEntry(
            role: .error,
            content: text,
            timestamp: Date()
        ))
    }

    private func updateTTSStatus(for state: SessionState) {
        switch state {
        case .aiSpeaking:
            ttsStatus = "Speaking..."
        case .aiThinking:
            ttsStatus = "Generating..."
        case .userSpeaking:
            ttsStatus = "Listening"
        case .idle:
            ttsStatus = "Ready"
        case .error:
            ttsStatus = "Error"
        default:
            ttsStatus = state.rawValue
        }
    }

    private func waitForResponseCompletion() async {
        // Wait for state to return to userSpeaking or error
        var iterations = 0
        let maxIterations = 300 // 30 seconds max

        while iterations < maxIterations {
            if sessionState == .userSpeaking || sessionState == .error || sessionState == .idle {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            iterations += 1
        }

        if iterations >= maxIterations {
            logger.warning("[DEBUG] Response wait timed out")
        }
    }
}

// MARK: - Errors

enum DebugSessionError: LocalizedError {
    case missingAPIKey(String)
    case sessionStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "\(provider) API key not configured. Please add it in Settings."
        case .sessionStartFailed(let reason):
            return "Session failed to start: \(reason)"
        }
    }
}

#endif
