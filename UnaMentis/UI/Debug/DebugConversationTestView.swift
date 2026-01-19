// UnaMentis - Debug Conversation Test View
// UI for testing AI conversations without voice input
//
// DEBUG only - not included in release builds

#if DEBUG

import SwiftUI

struct DebugConversationTestView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = DebugConversationViewModel()
    @State private var selectedScenario: ConversationTestScenario?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Provider Selection Section
            providerSection

            Divider()

            // Status Section
            statusSection

            Divider()

            // Conversation Log
            conversationLogSection

            Divider()

            // Input Section
            inputSection

            // Control Buttons
            controlSection
        }
        .navigationTitle("Conversation Test")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: .constant(viewModel.lastError != nil)) {
            Button("OK") {
                viewModel.lastError = nil
            }
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }

    // MARK: - Provider Selection

    private var providerSection: some View {
        VStack(spacing: 8) {
            Toggle("Use Current Settings", isOn: $viewModel.useCurrentSettings)
                .padding(.horizontal)
                .onChange(of: viewModel.useCurrentSettings) { _, newValue in
                    if newValue {
                        viewModel.loadCurrentSettings()
                    }
                }

            if !viewModel.useCurrentSettings {
                HStack {
                    Text("Provider")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Provider", selection: $viewModel.selectedLLMProvider) {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.selectedLLMProvider) { _, _ in
                        viewModel.updateAvailableModels()
                    }
                }
                .padding(.horizontal)

                HStack {
                    Text("Model")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Model", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
            } else {
                HStack {
                    Text("Using: \(viewModel.selectedLLMProvider.displayName) - \(viewModel.selectedModel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 16) {
            // Session State
            HStack(spacing: 6) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
                Text(viewModel.sessionState.rawValue)
                    .font(.caption)
            }

            Spacer()

            // TTS Status
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2")
                    .font(.caption)
                Text(viewModel.ttsStatus)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            // Turn count
            if viewModel.turnCount > 0 {
                Text("\(viewModel.turnCount) turns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Latency
            if viewModel.lastLatency > 0 {
                Text(String(format: "%.1fs", viewModel.lastLatency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var stateColor: Color {
        switch viewModel.sessionState {
        case .idle:
            return .gray
        case .userSpeaking:
            return .green
        case .aiThinking:
            return .orange
        case .aiSpeaking:
            return .blue
        case .error:
            return .red
        case .interrupted:
            return .yellow
        case .paused:
            return .cyan
        case .processingUserUtterance:
            return .purple
        }
    }

    // MARK: - Conversation Log

    private var conversationLogSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.conversationLog) { entry in
                        ConversationBubble(entry: entry)
                            .id(entry.id)
                    }

                    // Processing indicator
                    if viewModel.isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Processing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.conversationLog.count) { _, _ in
                if let lastEntry = viewModel.conversationLog.last {
                    withAnimation {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Input Section

    private var inputSection: some View {
        HStack(spacing: 8) {
            TextField("Type a message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .focused($isInputFocused)
                .disabled(!viewModel.isSessionActive || viewModel.isProcessing)
                .onSubmit {
                    Task { await viewModel.sendMessage() }
                }

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(viewModel.isSessionActive && !viewModel.inputText.isEmpty ? Color.blue : Color.gray)
                    .clipShape(Circle())
            }
            .disabled(!viewModel.isSessionActive || viewModel.inputText.isEmpty || viewModel.isProcessing)
        }
        .padding()
    }

    // MARK: - Control Section

    private var controlSection: some View {
        VStack(spacing: 12) {
            // Test Scenario Picker
            HStack {
                Menu {
                    ForEach(ConversationTestScenario.allCases) { scenario in
                        Button {
                            Task { await viewModel.runConversationTestScenario(scenario) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(scenario.rawValue)
                                Text(scenario.description)
                                    .font(.caption)
                            }
                        }
                        .disabled(!viewModel.isSessionActive || viewModel.isProcessing)
                    }
                } label: {
                    Label("Test Scenarios", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isSessionActive || viewModel.isProcessing)

                Button(role: .destructive) {
                    viewModel.clearConversation()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.conversationLog.isEmpty)
            }

            // Session Controls
            HStack(spacing: 16) {
                if viewModel.isSessionActive {
                    Button {
                        Task { await viewModel.stopSession() }
                    } label: {
                        Label("Stop Session", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        Task { await viewModel.startDebugSession(appState: appState) }
                    } label: {
                        if viewModel.isProcessing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Start Session", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isProcessing)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Conversation Bubble

struct ConversationBubble: View {
    let entry: ConversationEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Role indicator
            roleIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                // Role label and timestamp
                HStack {
                    Text(entry.role.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(roleColor)

                    Text(entry.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Content
                Text(entry.content)
                    .font(.body)
                    .foregroundStyle(entry.role == .error ? .red : .primary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var roleIcon: some View {
        switch entry.role {
        case .user:
            Image(systemName: "person.fill")
                .foregroundStyle(.blue)
        case .assistant:
            Image(systemName: "cpu")
                .foregroundStyle(.purple)
        case .system:
            Image(systemName: "gear")
                .foregroundStyle(.gray)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var roleColor: Color {
        switch entry.role {
        case .user: return .blue
        case .assistant: return .purple
        case .system: return .gray
        case .error: return .red
        }
    }

    private var backgroundColor: Color {
        switch entry.role {
        case .user:
            return Color.blue.opacity(0.1)
        case .assistant:
            return Color.purple.opacity(0.1)
        case .system:
            return Color.gray.opacity(0.1)
        case .error:
            return Color.red.opacity(0.1)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DebugConversationTestView()
            .environmentObject(AppState())
    }
}

#endif
