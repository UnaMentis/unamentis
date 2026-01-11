import SwiftUI
import Foundation
import AppKit

// MARK: - Service Model

enum ServiceStatus: String {
    case running = "Running"
    case stopped = "Stopped"
    case unknown = "Unknown"

    var color: Color {
        switch self {
        case .running: return .green
        case .stopped: return .red
        case .unknown: return .gray
        }
    }
}

enum ServiceCategory: String, CaseIterable {
    case core = "Core Services"
    case development = "Development Tools"
}

struct Service: Identifiable {
    let id: String
    let displayName: String
    let processName: String
    let port: Int?
    let startCommand: String
    let stopCommand: String?  // Optional custom stop command (for Docker, etc.)
    let workingDirectory: String?
    let category: ServiceCategory
    let isDockerCompose: Bool  // Whether this is a Docker Compose stack
    let webUIPort: Int?  // Port for opening web UI (if different from main port)
    var status: ServiceStatus = .unknown
    var cpuPercent: Double?
    var memoryMB: Int?
    var pid: Int?

    init(
        id: String,
        displayName: String,
        processName: String,
        port: Int?,
        startCommand: String,
        stopCommand: String? = nil,
        workingDirectory: String? = nil,
        category: ServiceCategory = .core,
        isDockerCompose: Bool = false,
        webUIPort: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.processName = processName
        self.port = port
        self.startCommand = startCommand
        self.stopCommand = stopCommand
        self.workingDirectory = workingDirectory
        self.category = category
        self.isDockerCompose = isDockerCompose
        self.webUIPort = webUIPort
    }
}

// MARK: - Service Manager

@MainActor
class ServiceManager: ObservableObject {
    @Published var services: [Service] = []
    @Published var developmentMode: Bool {
        didSet {
            UserDefaults.standard.set(developmentMode, forKey: "USM_DevelopmentMode")
        }
    }

    private var timer: Timer?
    private let serverPath = "/Users/ramerman/dev/unamentis/server"
    private let projectPath = "/Users/ramerman/dev/unamentis"

    /// Services visible based on current mode
    var visibleServices: [Service] {
        if developmentMode {
            return services
        } else {
            return services.filter { $0.category == .core }
        }
    }

    /// Core services only
    var coreServices: [Service] {
        services.filter { $0.category == .core }
    }

    /// Development services only
    var developmentServices: [Service] {
        services.filter { $0.category == .development }
    }

    init() {
        self.developmentMode = UserDefaults.standard.bool(forKey: "USM_DevelopmentMode")
        setupServices()
        startMonitoring()
    }

    private func setupServices() {
        services = [
            // MARK: Core Services
            Service(
                id: "postgresql",
                displayName: "PostgreSQL",
                processName: "postgres",
                port: 5432,
                startCommand: "/opt/homebrew/bin/brew services start postgresql@17",
                stopCommand: "/opt/homebrew/bin/brew services stop postgresql@17",
                workingDirectory: nil,
                category: .core
            ),
            Service(
                id: "log-server",
                displayName: "Log Server",
                processName: "log_server.py",
                port: 8765,
                startCommand: "python3 scripts/log_server.py",
                workingDirectory: projectPath,
                category: .core
            ),
            Service(
                id: "management-api",
                displayName: "Management API",
                processName: "server.py",
                port: 8766,
                startCommand: "AUTH_SECRET_KEY=466EB0C062CD48768B409697AFC251E9 DATABASE_URL=postgresql://ramerman@localhost/unamentis python3 management/server.py",
                workingDirectory: serverPath,
                category: .core
            ),
            Service(
                id: "web-server",
                displayName: "Operations Console",
                processName: "next-server",
                port: 3000,
                startCommand: "npm run serve",
                workingDirectory: "\(serverPath)/web",
                category: .core
            ),
            Service(
                id: "web-client",
                displayName: "Web Client",
                processName: "next-server",
                port: 3001,
                startCommand: "pnpm dev --port 3001",
                workingDirectory: "\(serverPath)/web-client",
                category: .core
            ),
            Service(
                id: "ollama",
                displayName: "Ollama",
                processName: "ollama",
                port: 11434,
                startCommand: "ollama serve",
                workingDirectory: nil,
                category: .core
            ),

            // MARK: Development Tools
            Service(
                id: "feature-flags",
                displayName: "Feature Flags",
                processName: "unleash-server",
                port: 3063,  // Proxy port (what clients connect to)
                startCommand: "/usr/local/bin/docker compose -f \(serverPath)/feature-flags/docker-compose.yml up -d",
                stopCommand: "/usr/local/bin/docker compose -f \(serverPath)/feature-flags/docker-compose.yml down",
                workingDirectory: "\(serverPath)/feature-flags",
                category: .development,
                isDockerCompose: true,
                webUIPort: 4242  // Unleash admin UI
            )
        ]
    }

    private func startMonitoring() {
        updateStatuses()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatuses()
            }
        }
    }

    func updateStatuses() {
        for i in services.indices {
            let service = services[i]
            let result: (running: Bool, pid: Int?, cpuPercent: Double?, memoryMB: Int?)

            if service.isDockerCompose {
                result = checkDockerContainer(name: service.processName)
            } else {
                result = checkProcess(name: service.processName, port: service.port)
            }

            services[i].status = result.running ? .running : .stopped
            services[i].pid = result.pid
            services[i].cpuPercent = result.cpuPercent
            services[i].memoryMB = result.memoryMB
        }
    }

    private func checkProcess(name: String, port: Int?) -> (running: Bool, pid: Int?, cpuPercent: Double?, memoryMB: Int?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", name]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty,
               let pid = Int(output.components(separatedBy: "\n").first ?? "") {
                // Get CPU and memory usage
                let statsTask = Process()
                statsTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                statsTask.arguments = ["-o", "%cpu=,rss=", "-p", "\(pid)"]
                let statsPipe = Pipe()
                statsTask.standardOutput = statsPipe
                statsTask.standardError = FileHandle.nullDevice
                try statsTask.run()
                statsTask.waitUntilExit()

                let statsData = statsPipe.fileHandleForReading.readDataToEndOfFile()
                let statsStr = String(data: statsData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let parts = statsStr.split(separator: " ").map { String($0) }

                var cpuPercent: Double?
                var memoryMB: Int?

                if parts.count >= 1 {
                    cpuPercent = Double(parts[0])
                }
                if parts.count >= 2 {
                    let memoryKB = Int(parts[1]) ?? 0
                    memoryMB = memoryKB / 1024
                }

                return (true, pid, cpuPercent, memoryMB)
            }
        } catch {
            // Process check failed
        }

        return (false, nil, nil, nil)
    }

    /// Check if a Docker container is running
    private func checkDockerContainer(name: String) -> (running: Bool, pid: Int?, cpuPercent: Double?, memoryMB: Int?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
        task.arguments = ["ps", "--filter", "name=\(name)", "--format", "{{.Status}}"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty,
               output.lowercased().contains("up") {
                // Container is running, get stats
                let statsTask = Process()
                statsTask.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
                statsTask.arguments = ["stats", name, "--no-stream", "--format", "{{.CPUPerc}},{{.MemUsage}}"]
                let statsPipe = Pipe()
                statsTask.standardOutput = statsPipe
                statsTask.standardError = FileHandle.nullDevice
                try statsTask.run()
                statsTask.waitUntilExit()

                let statsData = statsPipe.fileHandleForReading.readDataToEndOfFile()
                let statsStr = String(data: statsData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let parts = statsStr.split(separator: ",").map { String($0) }

                var cpuPercent: Double?
                var memoryMB: Int?

                if parts.count >= 1 {
                    // Parse "1.23%" -> 1.23
                    let cpuStr = parts[0].replacingOccurrences(of: "%", with: "")
                    cpuPercent = Double(cpuStr)
                }
                if parts.count >= 2 {
                    // Parse "123.4MiB / 1GiB" -> 123
                    let memStr = parts[1].split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? ""
                    if memStr.contains("GiB") {
                        let val = Double(memStr.replacingOccurrences(of: "GiB", with: "")) ?? 0
                        memoryMB = Int(val * 1024)
                    } else if memStr.contains("MiB") {
                        memoryMB = Int(Double(memStr.replacingOccurrences(of: "MiB", with: "")) ?? 0)
                    }
                }

                return (true, nil, cpuPercent, memoryMB)
            }
        } catch {
            // Docker check failed
        }

        return (false, nil, nil, nil)
    }

    func start(_ serviceId: String) {
        guard let service = services.first(where: { $0.id == serviceId }) else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "cd \(service.workingDirectory ?? "~") && \(service.startCommand) &"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            print("Failed to start \(service.displayName): \(error)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.updateStatuses()
        }
    }

    func stop(_ serviceId: String) {
        guard let index = services.firstIndex(where: { $0.id == serviceId }) else { return }
        let service = services[index]

        let task = Process()

        // Use custom stop command if available
        if let stopCommand = service.stopCommand {
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", stopCommand]
        } else {
            // Fall back to killing by PID
            guard let pid = service.pid else { return }
            task.executableURL = URL(fileURLWithPath: "/bin/kill")
            task.arguments = ["\(pid)"]
        }

        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("Failed to stop service: \(error)")
        }

        // Docker Compose takes longer to stop
        let delay = service.isDockerCompose ? 3.0 : 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.updateStatuses()
        }
    }

    func restart(_ serviceId: String) {
        stop(serviceId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.start(serviceId)
        }
    }

    func startAll() {
        // Only start visible services (respects dev mode)
        for service in visibleServices where service.status != .running {
            start(service.id)
        }
    }

    func stopAll() {
        // Only stop visible services (respects dev mode)
        for service in visibleServices where service.status == .running {
            stop(service.id)
        }
    }

    func openDashboard() {
        if let url = URL(string: "http://localhost:3000") {
            NSWorkspace.shared.open(url)
        }
    }

    func openLogs() {
        if let url = URL(string: "http://localhost:8765") {
            NSWorkspace.shared.open(url)
        }
    }

    func openWebClient() {
        if let url = URL(string: "http://localhost:3001") {
            NSWorkspace.shared.open(url)
        }
    }

    func openFeatureFlags() {
        if let url = URL(string: "http://localhost:4242") {
            NSWorkspace.shared.open(url)
        }
    }

    func openServiceUI(_ serviceId: String) {
        guard let service = services.first(where: { $0.id == serviceId }) else { return }
        let port = service.webUIPort ?? service.port ?? 0
        if port > 0, let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Calculates the width needed for the longest service name plus padding
    /// Uses all services (not just visible) to ensure consistent layout
    var maxServiceNameWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let padding: CGFloat = 8

        let maxWidth = services.map { service in
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let size = (service.displayName as NSString).size(withAttributes: attributes)
            return size.width
        }.max() ?? 100

        return maxWidth + padding
    }
}

// MARK: - App

@main
struct USMApp: App {
    @StateObject private var serviceManager = ServiceManager()

    var body: some Scene {
        MenuBarExtra {
            PopoverContent(serviceManager: serviceManager)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("UnaMentis Server Manager Settings")
                .padding()
        }
    }
}

// MARK: - Popover Content

struct PopoverContent: View {
    @ObservedObject var serviceManager: ServiceManager
    @State private var devToolsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("UnaMentis Server Manager")
                    .font(.headline)
                Spacer()
                Button(action: { serviceManager.updateStatuses() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Core Services List
            VStack(spacing: 1) {
                ForEach(serviceManager.coreServices) { service in
                    ServiceRow(
                        service: service,
                        nameWidth: serviceManager.maxServiceNameWidth,
                        serviceManager: serviceManager
                    )
                }
            }
            .padding(.vertical, 4)

            // Development Tools Section (only visible in dev mode)
            if serviceManager.developmentMode && !serviceManager.developmentServices.isEmpty {
                Divider()

                // Collapsible header
                Button(action: { devToolsExpanded.toggle() }) {
                    HStack {
                        Image(systemName: devToolsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Development Tools")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if devToolsExpanded {
                    VStack(spacing: 1) {
                        ForEach(serviceManager.developmentServices) { service in
                            ServiceRow(
                                service: service,
                                nameWidth: serviceManager.maxServiceNameWidth,
                                serviceManager: serviceManager
                            )
                        }
                    }
                    .padding(.bottom, 4)
                }
            }

            Divider()

            // Action Buttons
            HStack(spacing: 8) {
                Button("Start All") {
                    serviceManager.startAll()
                }
                .buttonStyle(.bordered)

                Button("Stop All") {
                    serviceManager.stopAll()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: { serviceManager.openDashboard() }) {
                    Image(systemName: "globe")
                }
                .buttonStyle(.borderless)
                .help("Open Operations Console (localhost:3000)")

                Button(action: { serviceManager.openWebClient() }) {
                    Image(systemName: "laptopcomputer")
                }
                .buttonStyle(.borderless)
                .help("Open Web Client (localhost:3001)")

                Button(action: { serviceManager.openLogs() }) {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("Open Logs (localhost:8765)")

                // Feature Flags UI button (only in dev mode when running)
                if serviceManager.developmentMode,
                   let ffService = serviceManager.services.first(where: { $0.id == "feature-flags" }),
                   ffService.status == .running {
                    Button(action: { serviceManager.openFeatureFlags() }) {
                        Image(systemName: "flag")
                    }
                    .buttonStyle(.borderless)
                    .help("Open Feature Flags UI (localhost:4242)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Footer: Dev Mode Toggle and Quit
            HStack {
                Toggle(isOn: $serviceManager.developmentMode) {
                    Label("Dev Mode", systemImage: "wrench.and.screwdriver")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .help("Show development tools like Feature Flags, Latency Harness")

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 370)
    }
}

// MARK: - Service Row

struct ServiceRow: View {
    let service: Service
    let nameWidth: CGFloat
    @ObservedObject var serviceManager: ServiceManager

    /// Tooltip showing port info when service is running
    private var serviceTooltip: String {
        if service.status == .running, let port = service.port {
            return "\(service.displayName) running on port \(port)"
        } else if let port = service.port {
            return "Port \(port)"
        } else {
            return service.displayName
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(service.status.color)
                .frame(width: 8, height: 8)

            // Service name - fixed width, no wrapping
            Text(service.displayName)
                .lineLimit(1)
                .frame(width: nameWidth, alignment: .leading)
                .help(serviceTooltip)

            // CPU
            HStack(spacing: 2) {
                Image(systemName: "cpu")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let cpu = service.cpuPercent, service.status == .running {
                    Text(String(format: "%.1f%%", cpu))
                        .font(.caption)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 55, alignment: .trailing)

            // Memory
            HStack(spacing: 2) {
                Image(systemName: "memorychip")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let mem = service.memoryMB, service.status == .running, mem > 0 {
                    Text("\(mem)MB")
                        .font(.caption)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 60, alignment: .trailing)

            // Action buttons
            HStack(spacing: 4) {
                // Start button
                Button(action: { serviceManager.start(service.id) }) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(service.status == .running)
                .opacity(service.status == .running ? 0.3 : 1.0)
                .help("Start")

                // Stop button
                Button(action: { serviceManager.stop(service.id) }) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(service.status != .running)
                .opacity(service.status != .running ? 0.3 : 1.0)
                .help("Stop")

                // Restart button
                Button(action: { serviceManager.restart(service.id) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(service.status != .running)
                .opacity(service.status != .running ? 0.3 : 1.0)
                .help("Restart")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.clear)
    }
}
