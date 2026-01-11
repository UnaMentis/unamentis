import SwiftUI
import Foundation
import AppKit
import Network

// MARK: - API Server for AI Agent Access

/// HTTP API Server that allows AI agents to control services programmatically
/// Runs on port 8767 and exposes REST endpoints for service management
@MainActor
class APIServer {
    private var listener: NWListener?
    private let port: UInt16 = 8767
    private weak var serviceManager: ServiceManager?

    init(serviceManager: ServiceManager) {
        self.serviceManager = serviceManager
    }

    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("USM API Server listening on port 8767")
                case .failed(let error):
                    print("USM API Server failed: \(error)")
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }

            listener?.start(queue: .main)
        } catch {
            print("Failed to start API server: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                if let data = data, !data.isEmpty {
                    self?.processRequest(data: data, connection: connection)
                }
                if isComplete || error != nil {
                    connection.cancel()
                }
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: #"{"error": "Invalid request"}"#)
            return
        }

        // Parse HTTP request
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: "400 Bad Request", body: #"{"error": "Empty request"}"#)
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", body: #"{"error": "Malformed request"}"#)
            return
        }

        let method = parts[0]
        let path = parts[1]

        // Route the request
        routeRequest(method: method, path: path, connection: connection)
    }

    private func routeRequest(method: String, path: String, connection: NWConnection) {
        guard let manager = serviceManager else {
            sendResponse(connection: connection, status: "500 Internal Server Error", body: #"{"error": "Service manager not available"}"#)
            return
        }

        // Health check
        if path == "/api/health" && method == "GET" {
            let json = #"{"status": "ok", "service": "USM API Server", "port": 8767}"#
            sendResponse(connection: connection, status: "200 OK", body: json)
            return
        }

        // List all services
        if path == "/api/services" && method == "GET" {
            Task { @MainActor in
                manager.updateStatuses()
                let servicesJson = manager.services.map { service -> String in
                    let cpu = service.cpuPercent.map { String(format: "%.1f", $0) } ?? "null"
                    let mem = service.memoryMB.map { String($0) } ?? "null"
                    let pid = service.pid.map { String($0) } ?? "null"
                    return """
                    {"id": "\(service.id)", "name": "\(service.displayName)", "status": "\(service.status.rawValue.lowercased())", "port": \(service.port ?? 0), "pid": \(pid), "cpu_percent": \(cpu), "memory_mb": \(mem)}
                    """
                }.joined(separator: ", ")

                let running = manager.services.filter { $0.status == .running }.count
                let stopped = manager.services.filter { $0.status == .stopped }.count

                let json = """
                {"services": [\(servicesJson)], "total": \(manager.services.count), "running": \(running), "stopped": \(stopped)}
                """
                self.sendResponse(connection: connection, status: "200 OK", body: json)
            }
            return
        }

        // Start all services
        if path == "/api/services/start-all" && method == "POST" {
            Task { @MainActor in
                manager.startAll()
                // Wait a moment for services to start
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                manager.updateStatuses()
                let running = manager.services.filter { $0.status == .running }.count
                let json = #"{"status": "ok", "message": "Start all initiated", "running": \#(running)}"#
                self.sendResponse(connection: connection, status: "200 OK", body: json)
            }
            return
        }

        // Stop all services
        if path == "/api/services/stop-all" && method == "POST" {
            Task { @MainActor in
                manager.stopAll()
                // Wait a moment for services to stop
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                manager.updateStatuses()
                let stopped = manager.services.filter { $0.status == .stopped }.count
                let json = #"{"status": "ok", "message": "Stop all initiated", "stopped": \#(stopped)}"#
                self.sendResponse(connection: connection, status: "200 OK", body: json)
            }
            return
        }

        // Restart all services
        if path == "/api/services/restart-all" && method == "POST" {
            Task { @MainActor in
                // Stop all first
                manager.stopAll()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                // Then start all
                manager.startAll()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                manager.updateStatuses()
                let running = manager.services.filter { $0.status == .running }.count
                let json = #"{"status": "ok", "message": "Restart all initiated", "running": \#(running)}"#
                self.sendResponse(connection: connection, status: "200 OK", body: json)
            }
            return
        }

        // Individual service operations: /api/services/{id}/{action}
        if path.hasPrefix("/api/services/") {
            let pathParts = path.dropFirst("/api/services/".count).components(separatedBy: "/")

            if pathParts.count == 2 {
                let serviceId = pathParts[0]
                let action = pathParts[1]

                // Verify service exists
                guard manager.services.contains(where: { $0.id == serviceId }) else {
                    sendResponse(connection: connection, status: "404 Not Found", body: #"{"error": "Service '\#(serviceId)' not found"}"#)
                    return
                }

                if method == "POST" {
                    Task { @MainActor in
                        switch action {
                        case "start":
                            manager.start(serviceId)
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            manager.updateStatuses()
                            let service = manager.services.first { $0.id == serviceId }
                            let status = service?.status.rawValue.lowercased() ?? "unknown"
                            let json = #"{"status": "ok", "message": "Start initiated for \#(serviceId)", "service_status": "\#(status)"}"#
                            self.sendResponse(connection: connection, status: "200 OK", body: json)

                        case "stop":
                            manager.stop(serviceId)
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            manager.updateStatuses()
                            let service = manager.services.first { $0.id == serviceId }
                            let status = service?.status.rawValue.lowercased() ?? "unknown"
                            let json = #"{"status": "ok", "message": "Stop initiated for \#(serviceId)", "service_status": "\#(status)"}"#
                            self.sendResponse(connection: connection, status: "200 OK", body: json)

                        case "restart":
                            manager.restart(serviceId)
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            manager.updateStatuses()
                            let service = manager.services.first { $0.id == serviceId }
                            let status = service?.status.rawValue.lowercased() ?? "unknown"
                            let json = #"{"status": "ok", "message": "Restart initiated for \#(serviceId)", "service_status": "\#(status)"}"#
                            self.sendResponse(connection: connection, status: "200 OK", body: json)

                        default:
                            self.sendResponse(connection: connection, status: "400 Bad Request", body: #"{"error": "Unknown action '\#(action)'. Use start, stop, or restart."}"#)
                        }
                    }
                    return
                }
            }
        }

        // Unknown route
        sendResponse(connection: connection, status: "404 Not Found", body: #"{"error": "Unknown endpoint", "path": "\#(path)"}"#)
    }

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

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
    private var apiServer: APIServer?

    private let projectRoot: String
    private let serverPath: String

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
        // Detect project root dynamically
        self.projectRoot = ServiceManager.detectProjectRoot()
        self.serverPath = "\(projectRoot)/server"
        self.developmentMode = UserDefaults.standard.bool(forKey: "USM_DevelopmentMode")
        setupServices()
        startMonitoring()
        startAPIServer()
    }

    /// Detects the UnaMentis project root directory
    /// Priority: 1) UNAMENTIS_ROOT env var, 2) Walk up from current dir, 3) Common dev locations
    private static func detectProjectRoot() -> String {
        // 1. Check environment variable
        if let envRoot = ProcessInfo.processInfo.environment["UNAMENTIS_ROOT"] {
            if FileManager.default.fileExists(atPath: "\(envRoot)/UnaMentis.xcodeproj") {
                return envRoot
            }
        }

        // 2. Try to find project root by walking up from current directory
        var currentPath = FileManager.default.currentDirectoryPath
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: "\(currentPath)/UnaMentis.xcodeproj") {
                return currentPath
            }
            currentPath = (currentPath as NSString).deletingLastPathComponent
            if currentPath == "/" { break }
        }

        // 3. Check common development locations
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "\(homeDir)/dev/unamentis",
            "\(homeDir)/Developer/unamentis",
            "\(homeDir)/Projects/unamentis",
            "\(homeDir)/Code/unamentis"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: "\(path)/UnaMentis.xcodeproj") {
                return path
            }
        }

        // 4. Last resort: use home directory based path (will show error if not found)
        print("Warning: Could not detect UnaMentis project root. Set UNAMENTIS_ROOT environment variable.")
        return "\(homeDir)/dev/unamentis"
    }

    private func startAPIServer() {
        apiServer = APIServer(serviceManager: self)
        apiServer?.start()
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
                workingDirectory: projectRoot,
                category: .core
            ),
            Service(
                id: "management-api",
                displayName: "Management API",
                processName: "server.py",
                port: 8766,
                startCommand: "python3 management/server.py",  // Expects AUTH_SECRET_KEY and DATABASE_URL from environment
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
        // If we have a port, use lsof to find the exact process listening on that port
        // This properly differentiates services that share process names (e.g., multiple next-server instances)
        if let port = port {
            let lsofTask = Process()
            lsofTask.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            lsofTask.arguments = ["-i", ":\(port)", "-sTCP:LISTEN", "-t"]

            let lsofPipe = Pipe()
            lsofTask.standardOutput = lsofPipe
            lsofTask.standardError = FileHandle.nullDevice

            do {
                try lsofTask.run()
                lsofTask.waitUntilExit()

                let lsofData = lsofPipe.fileHandleForReading.readDataToEndOfFile()
                if let lsofOutput = String(data: lsofData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !lsofOutput.isEmpty,
                   let pid = Int(lsofOutput.components(separatedBy: "\n").first ?? "") {
                    return getProcessStats(pid: pid)
                }
            } catch {
                // lsof failed, fall through to pgrep
            }
        }

        // Fall back to pgrep for services without ports (or if lsof failed)
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
                return getProcessStats(pid: pid)
            }
        } catch {
            // Process check failed
        }

        return (false, nil, nil, nil)
    }

    private func getProcessStats(pid: Int) -> (running: Bool, pid: Int?, cpuPercent: Double?, memoryMB: Int?) {
        let statsTask = Process()
        statsTask.executableURL = URL(fileURLWithPath: "/bin/ps")
        statsTask.arguments = ["-o", "%cpu=,rss=", "-p", "\(pid)"]
        let statsPipe = Pipe()
        statsTask.standardOutput = statsPipe
        statsTask.standardError = FileHandle.nullDevice

        do {
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
        } catch {
            // Stats fetch failed but process exists
            return (true, pid, nil, nil)
        }
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
            // Try to get PID from stored value, or look it up by port
            var pidToKill: Int?

            if let pid = service.pid {
                pidToKill = pid
            } else if let port = service.port {
                // Look up the PID by port using lsof
                pidToKill = findPidByPort(port)
            }

            guard let pid = pidToKill else {
                print("No PID found for \(service.displayName)")
                return
            }

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

    private func findPidByPort(_ port: Int) -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-i", ":\(port)", "-sTCP:LISTEN", "-t"]

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
                return pid
            }
        } catch {
            // Failed to find PID by port
        }

        return nil
    }

    func restart(_ serviceId: String) {
        stop(serviceId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.start(serviceId)
        }
    }

    func startAll() {
        // Refresh status first to get accurate state
        updateStatuses()

        // Only start visible services (respects dev mode)
        let servicesToStart = visibleServices.filter { $0.status != .running }

        // Start services with a small delay between each to avoid overwhelming the system
        for (index, service) in servicesToStart.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                self.start(service.id)
            }
        }
    }

    func stopAll() {
        // Refresh status first to get accurate PIDs
        updateStatuses()

        // Only stop visible services (respects dev mode), in reverse order
        let servicesToStop = visibleServices.filter { $0.status == .running }.reversed()

        // Stop services with a small delay between each
        for (index, service) in servicesToStop.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.3) {
                self.stop(service.id)
            }
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
            VStack(alignment: .leading, spacing: 12) {
                Text("UnaMentis Server Manager")
                    .font(.headline)

                Divider()

                Text("API Server")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("http://localhost:8767")
                        .font(.system(.body, design: .monospaced))
                }

                Text("AI agents can control services via this API.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Text("Available Endpoints:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("GET  /api/health")
                    Text("GET  /api/services")
                    Text("POST /api/services/{id}/start")
                    Text("POST /api/services/{id}/stop")
                    Text("POST /api/services/{id}/restart")
                    Text("POST /api/services/start-all")
                    Text("POST /api/services/stop-all")
                    Text("POST /api/services/restart-all")
                }
                .font(.system(.caption, design: .monospaced))
            }
            .padding()
            .frame(width: 320)
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
