// UnaMentis - Server Settings View
// UI for configuring self-hosted servers with auto-discovery
//
// Part of UI/Settings

import SwiftUI

/// View for configuring self-hosted servers with automatic discovery
public struct ServerSettingsView: View {
    @StateObject private var viewModel = ServerSettingsViewModel()

    public init() {}

    public var body: some View {
        List {
            // Connection Status Section
            if viewModel.showDiscoveryProgress {
                Section {
                    DiscoveryProgressView(
                        state: viewModel.discoveryState,
                        currentTier: viewModel.currentTier,
                        progress: viewModel.discoveryProgress,
                        onCancel: { viewModel.cancelDiscovery() },
                        onRetry: { Task { await viewModel.startAutoDiscovery() } },
                        onManualSetup: { viewModel.showManualSetup = true }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                // Status Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Self-Hosted Mode")
                                .font(.headline)
                            Text(viewModel.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Circle()
                            .fill(viewModel.overallStatus.color)
                            .frame(width: 12, height: 12)
                    }

                    // Connected server info with discovery badge
                    if let connectedServer = viewModel.connectedServer {
                        ConnectedServerRow(server: connectedServer)
                    }
                } header: {
                    Text("Status")
                }
            }

            // Configured Servers Section
            Section {
                if viewModel.servers.isEmpty {
                    Text("No servers configured")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(viewModel.servers) { server in
                        ServerRow(
                            server: server,
                            discoveryMethod: viewModel.discoveryMethodFor(server),
                            onToggle: { viewModel.toggleServer(server.id) },
                            onDelete: { viewModel.deleteServer(server.id) },
                            onTest: { await viewModel.testServer(server.id) }
                        )
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deleteServer(viewModel.servers[index].id)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Servers")
                    Spacer()
                    Button("Add") {
                        viewModel.showAddServer = true
                    }
                    .font(.caption)
                }
            } footer: {
                Text("Servers are checked automatically every 30 seconds.")
            }

            // Discovery Section
            Section {
                Button {
                    Task { await viewModel.startAutoDiscovery() }
                } label: {
                    HStack {
                        Label("Auto-Discover Server", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        if viewModel.discoveryState.isDiscovering {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.discoveryState.isDiscovering)

                Button {
                    viewModel.showQRScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                }

                Button {
                    viewModel.showManualSetup = true
                } label: {
                    Label("Enter Manually", systemImage: "keyboard")
                }
            } header: {
                Text("Connect to Server")
            } footer: {
                Text("Your Mac server will be found automatically on most networks. Use QR code or manual entry if auto-discovery fails.")
            }

            // Info Section
            Section {
                NavigationLink {
                    ServerSetupGuideView()
                } label: {
                    Label("Setup Guide", systemImage: "book")
                }

                Link(destination: URL(string: "https://github.com/ollama/ollama")!) {
                    Label("Ollama Documentation", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Help")
            }
        }
        .navigationTitle("Self-Hosted Servers")
        .sheet(isPresented: $viewModel.showAddServer) {
            AddServerSheet(onAdd: viewModel.addServer)
        }
        .sheet(isPresented: $viewModel.showQRScanner) {
            QRCodeScannerView(
                onScanned: { data in
                    Task { await viewModel.configureFromQRCode(data) }
                },
                onManualEntry: {
                    viewModel.showManualSetup = true
                }
            )
        }
        .sheet(isPresented: $viewModel.showManualSetup) {
            ManualServerEntrySheet { host, port, name in
                Task { await viewModel.configureManually(host: host, port: port, name: name) }
            }
        }
        .task {
            await viewModel.loadServers()
        }
        .refreshable {
            await viewModel.refreshServers()
        }
    }
}

// MARK: - Connected Server Row

struct ConnectedServerRow: View {
    let server: DiscoveredServer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("\(server.host):\(server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DiscoveryMethodBadge(method: server.discoveryMethod)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Server Row

struct ServerRow: View {
    let server: ServerConfig
    let discoveryMethod: DiscoveryMethod?
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onTest: () async -> Void

    @State private var isTesting = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: server.healthStatus.icon)
                .foregroundStyle(server.healthStatus.color)
                .frame(width: 24)

            // Server info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(server.name)
                        .font(.body)

                    if let method = discoveryMethod {
                        DiscoveryMethodBadge(method: method)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(server.host):\(server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(server.serverType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            Toggle("", isOn: Binding(
                get: { server.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()

            Button {
                isTesting = true
                Task {
                    await onTest()
                    isTesting = false
                }
            } label: {
                if isTesting {
                    ProgressView()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Server Sheet

struct AddServerSheet: View {
    let onAdd: (ServerConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = "localhost"
    @State private var port = "11400"
    @State private var serverType: ServerType = .unamentisGateway
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Details") {
                    TextField("Name", text: $name)

                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)

                    Picker("Server Type", selection: $serverType) {
                        ForEach(ServerType.allCases, id: \.rawValue) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else if let result = testResult {
                                switch result {
                                case .success:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                case .failure:
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .disabled(host.isEmpty || port.isEmpty)

                    if case .failure(let message) = testResult {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let config = ServerConfig(
                            name: name.isEmpty ? "\(serverType.displayName) (\(host))" : name,
                            host: host,
                            port: Int(port) ?? serverType.defaultPort,
                            serverType: serverType
                        )
                        onAdd(config)
                        dismiss()
                    }
                    .disabled(host.isEmpty || port.isEmpty)
                }
            }
            .onChange(of: serverType) { _, newValue in
                port = String(newValue.defaultPort)
            }
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        guard let portNum = Int(port),
              let url = URL(string: "http://\(host):\(portNum)/health") else {
            testResult = .failure("Invalid URL")
            isTesting = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                testResult = .success
            } else {
                testResult = .failure("Server returned error")
            }
        } catch {
            testResult = .failure(error.localizedDescription)
        }

        isTesting = false
    }
}

// MARK: - Server Setup Guide

struct ServerSetupGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Quick Start
                VStack(alignment: .leading, spacing: 12) {
                    Label("Quick Start", systemImage: "1.circle.fill")
                        .font(.headline)

                    Text("On your Mac, run the setup script:")
                        .font(.subheadline)

                    CodeBlock("""
                    cd path/to/unamentis/server
                    ./setup.sh
                    """)
                }

                Divider()

                // What Gets Installed
                VStack(alignment: .leading, spacing: 12) {
                    Label("What Gets Installed", systemImage: "2.circle.fill")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        BulletPoint("Ollama - Local LLM inference")
                        BulletPoint("whisper.cpp - Speech-to-text")
                        BulletPoint("Piper TTS - Text-to-speech")
                        BulletPoint("Unified API gateway")
                    }
                }

                Divider()

                // Default Ports
                VStack(alignment: .leading, spacing: 12) {
                    Label("Default Ports", systemImage: "3.circle.fill")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        PortRow(name: "Gateway", port: 11400)
                        PortRow(name: "Ollama", port: 11434)
                        PortRow(name: "Whisper", port: 11401)
                        PortRow(name: "Piper", port: 11402)
                    }
                }

                Divider()

                // Auto Discovery
                VStack(alignment: .leading, spacing: 12) {
                    Label("Auto Discovery", systemImage: "4.circle.fill")
                        .font(.headline)

                    Text("When your Mac server is running, this app will automatically find it on your local network using Bonjour.")
                        .font(.subheadline)

                    Text("If auto-discovery doesn't work (common on school/corporate networks), use the QR code on your Mac's menu bar app, or enter the IP address manually.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Commands
                VStack(alignment: .leading, spacing: 12) {
                    Label("Control Commands", systemImage: "5.circle.fill")
                        .font(.headline)

                    CodeBlock("""
                    voicelearn-server start
                    voicelearn-server stop
                    voicelearn-server status
                    """)
                }
            }
            .padding()
        }
        .navigationTitle("Setup Guide")
    }
}

struct CodeBlock: View {
    let code: String

    init(_ code: String) {
        self.code = code
    }

    var body: some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.subheadline)
    }
}

struct PortRow: View {
    let name: String
    let port: Int

    var body: some View {
        HStack {
            Text(name)
                .font(.subheadline)
            Spacer()
            Text(":\(port)")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - View Model

@MainActor
class ServerSettingsViewModel: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var showAddServer = false
    @Published var showQRScanner = false
    @Published var showManualSetup = false
    @Published var showDiscoveryProgress = false

    // Discovery state from DeviceDiscoveryManager
    @Published var discoveryState: DiscoveryState = .idle
    @Published var currentTier: DiscoveryTier?
    @Published var discoveryProgress: Double = 0
    @Published var connectedServer: DiscoveredServer?

    // Map server IDs to discovery methods
    private var serverDiscoveryMethods: [UUID: DiscoveryMethod] = [:]

    var overallStatus: ServerHealthStatus {
        let enabledServers = servers.filter { $0.isEnabled }
        if enabledServers.isEmpty { return .unknown }
        if enabledServers.allSatisfy({ $0.healthStatus == .healthy }) { return .healthy }
        if enabledServers.contains(where: { $0.healthStatus.isUsable }) { return .degraded }
        return .unhealthy
    }

    var statusMessage: String {
        if let connected = connectedServer {
            return "Connected to \(connected.name)"
        }
        let healthy = servers.filter { $0.isEnabled && $0.healthStatus.isUsable }.count
        let total = servers.filter { $0.isEnabled }.count
        if total == 0 { return "No servers configured" }
        return "\(healthy)/\(total) servers available"
    }

    func discoveryMethodFor(_ server: ServerConfig) -> DiscoveryMethod? {
        serverDiscoveryMethods[server.id]
    }

    func loadServers() async {
        let serverManager = ServerConfigManager.shared
        servers = await serverManager.getAllServers()

        // Check for connected server from discovery manager
        connectedServer = DeviceDiscoveryManager.shared.connectedServer
    }

    func refreshServers() async {
        let serverManager = ServerConfigManager.shared
        await serverManager.checkAllServersHealth()
        servers = await serverManager.getAllServers()
    }

    func startAutoDiscovery() async {
        showDiscoveryProgress = true
        let discoveryManager = DeviceDiscoveryManager.shared

        // Start observing discovery state
        Task {
            while showDiscoveryProgress {
                discoveryState = discoveryManager.state
                currentTier = discoveryManager.currentTier
                discoveryProgress = discoveryManager.progress
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // Run discovery
        if let discovered = await discoveryManager.startDiscovery() {
            connectedServer = discovered
            serverDiscoveryMethods[UUID()] = discovered.discoveryMethod

            // Add to server config
            let serverManager = ServerConfigManager.shared
            _ = await serverManager.connectWithAutoDiscovery()
            await loadServers()
        }

        // Update final state
        discoveryState = discoveryManager.state
        showDiscoveryProgress = discoveryState.isDiscovering

        // Hide progress after a brief delay if connected
        if case .connected = discoveryState {
            try? await Task.sleep(for: .seconds(1.5))
            showDiscoveryProgress = false
        }
    }

    func cancelDiscovery() {
        Task {
            await DeviceDiscoveryManager.shared.cancelDiscovery()
            showDiscoveryProgress = false
            discoveryState = .idle
        }
    }

    func configureFromQRCode(_ data: Data) async {
        let serverManager = ServerConfigManager.shared
        if let config = await serverManager.configureServerFromQRCode(data) {
            serverDiscoveryMethods[config.id] = .qrCode
            await loadServers()

            // Update connected server display
            connectedServer = DiscoveredServer(
                name: config.name,
                host: config.host,
                port: config.port,
                discoveryMethod: .qrCode
            )
        }
    }

    func configureManually(host: String, port: Int, name: String?) async {
        let serverManager = ServerConfigManager.shared
        if let config = await serverManager.configureServerManually(
            host: host,
            port: port,
            name: name
        ) {
            serverDiscoveryMethods[config.id] = .manual
            await loadServers()

            // Update connected server display
            connectedServer = DiscoveredServer(
                name: config.name,
                host: config.host,
                port: config.port,
                discoveryMethod: .manual
            )
        }
    }

    func toggleServer(_ id: UUID) {
        Task {
            let serverManager = ServerConfigManager.shared
            if var server = await serverManager.getServer(id) {
                server.isEnabled.toggle()
                await serverManager.updateServer(server)
                await loadServers()
            }
        }
    }

    func deleteServer(_ id: UUID) {
        Task {
            let serverManager = ServerConfigManager.shared
            await serverManager.removeServer(id)
            serverDiscoveryMethods.removeValue(forKey: id)
            await loadServers()
        }
    }

    func testServer(_ id: UUID) async {
        let serverManager = ServerConfigManager.shared
        await serverManager.checkServerHealth(id)
        await loadServers()
    }

    func addServer(_ config: ServerConfig) {
        Task {
            let serverManager = ServerConfigManager.shared
            await serverManager.addServer(config)
            serverDiscoveryMethods[config.id] = .manual
            await loadServers()
        }
    }
}

// MARK: - Health Status Color

extension ServerHealthStatus {
    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .checking: return .orange
        case .healthy: return .green
        case .degraded: return .yellow
        case .unhealthy: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ServerSettingsView()
    }
}
