// USMCoreManager.swift
// Main service manager using USM Core via HTTP API and WebSocket events

import SwiftUI
import Combine

/// Main manager for USM-FFI app
/// Uses USM Core's HTTP API for operations and WebSocket for real-time updates
@MainActor
final class USMCoreManager: ObservableObject {
    // MARK: - Published State

    @Published private(set) var services: [ServiceInfo] = []
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?

    @Published var developmentMode: Bool {
        didSet {
            UserDefaults.standard.set(developmentMode, forKey: "USMFFI_DevelopmentMode")
        }
    }

    // MARK: - Computed Properties

    /// Services filtered by development mode setting
    var visibleServices: [ServiceInfo] {
        if developmentMode {
            return services
        }
        return services.filter { $0.category != .development }
    }

    /// Count of running services
    var runningCount: Int {
        visibleServices.filter { $0.status == .running }.count
    }

    /// Count of stopped services
    var stoppedCount: Int {
        visibleServices.filter { $0.status == .stopped }.count
    }

    // MARK: - Private State

    private let wsClient: WebSocketClient
    private let baseURL: URL
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var templateDisplayNames: [String: String] = [:]

    // MARK: - Initialization

    init() {
        // USM Core runs on 8787 (distinctly different from legacy USM on 8767)
        let port = 8787
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        self.wsClient = WebSocketClient(port: port)
        self.developmentMode = UserDefaults.standard.bool(forKey: "USMFFI_DevelopmentMode")

        setupWebSocket()
        checkConnection()

        // Regular metrics polling (every 5 seconds for live metrics updates)
        // WebSocket provides instant status changes, but metrics need periodic refresh
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshServices()
            }
        }
    }

    // No timer cleanup in deinit: refreshTimer uses [weak self], and this
    // manager lives for the app's lifetime. Touching main-actor state from a
    // nonisolated deinit is rejected under Swift 6 concurrency.

    // MARK: - Setup

    private func setupWebSocket() {
        wsClient.onEvent = { [weak self] event in
            self?.handleEvent(event)
        }

        wsClient.onConnectionChange = { [weak self] connected in
            Task { @MainActor in
                // Don't override isConnected based on WebSocket - health check determines that
                if connected {
                    // Refresh services when WebSocket connection is established
                    self?.refreshServices()
                }
            }
        }
    }

    // MARK: - Connection

    /// Check if USM Core is available and connect
    func checkConnection() {
        let healthURL = baseURL.appendingPathComponent("api/health")

        URLSession.shared.dataTask(with: healthURL) { [weak self] data, response, error in
            Task { @MainActor in
                if let error = error {
                    self?.isConnected = false
                    self?.lastError = "USM Core not available: \(error.localizedDescription)"
                    print("[USMCoreManager] Health check failed: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    self?.isConnected = false
                    self?.lastError = "USM Core health check failed"
                    return
                }

                print("[USMCoreManager] USM Core is available on port 8787")
                self?.isConnected = true
                self?.lastError = nil
                self?.fetchTemplates()
                self?.wsClient.connect()
                self?.refreshServices()
            }
        }.resume()
    }

    // MARK: - Service Operations

    /// Fetch templates to get display names
    private func fetchTemplates() {
        let templatesURL = baseURL.appendingPathComponent("api/templates")

        URLSession.shared.dataTask(with: templatesURL) { [weak self] data, _, _ in
            Task { @MainActor in
                guard let data = data else { return }

                do {
                    let templates = try JSONDecoder().decode([TemplateData].self, from: data)
                    for template in templates {
                        self?.templateDisplayNames[template.id] = template.displayName
                    }
                    print("[USMCoreManager] Loaded \(templates.count) templates")
                    // Refresh services again to apply display names
                    self?.refreshServices()
                } catch {
                    print("[USMCoreManager] Failed to decode templates: \(error)")
                }
            }
        }.resume()
    }

    /// Refresh all services from USM Core API
    func refreshServices() {
        let instancesURL = baseURL.appendingPathComponent("api/instances")

        URLSession.shared.dataTask(with: instancesURL) { [weak self] data, response, error in
            Task { @MainActor in
                if let error = error {
                    print("[USMCoreManager] Failed to fetch instances: \(error.localizedDescription)")
                    self?.lastError = error.localizedDescription
                    return
                }

                guard let data = data else {
                    print("[USMCoreManager] No data received")
                    return
                }

                do {
                    let response = try JSONDecoder().decode(InstancesResponse.self, from: data)
                    self?.services = response.instances.map { instance in
                        // Use template display name if available, otherwise format the id
                        let displayName = self?.templateDisplayNames[instance.templateId] ?? instance.templateId
                            .replacingOccurrences(of: "-", with: " ")
                            .split(separator: " ")
                            .map { $0.capitalized }
                            .joined(separator: " ")

                        return ServiceInfo(
                            id: instance.id,
                            templateId: instance.templateId,
                            displayName: displayName,
                            port: instance.port,
                            status: ServiceStatus.from(string: instance.status),
                            cpuPercent: instance.cpuPercent ?? 0,
                            memoryMB: instance.memoryMB ?? 0
                        )
                    }
                    self?.lastError = nil
                    print("[USMCoreManager] Loaded \(self?.services.count ?? 0) services")
                } catch {
                    print("[USMCoreManager] Failed to decode instances: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("[USMCoreManager] Response was: \(jsonString.prefix(500))")
                    }
                    self?.lastError = "Failed to parse services"
                }
            }
        }.resume()
    }

    /// Force UI update by replacing an element in the services array
    private func updateServiceStatus(_ serviceId: String, status: ServiceStatus) {
        if let index = services.firstIndex(where: { $0.id == serviceId }) {
            var updated = services[index]
            updated.status = status
            services[index] = updated  // Replace entire element to trigger SwiftUI update
        }
    }

    /// Start a service
    func start(_ serviceId: String) {
        let startURL = baseURL.appendingPathComponent("api/instances/\(serviceId)/start")
        var request = URLRequest(url: startURL)
        request.httpMethod = "POST"

        // Optimistic update - replace element to force SwiftUI refresh
        updateServiceStatus(serviceId, status: .starting)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                if let error = error {
                    print("[USMCoreManager] Failed to start \(serviceId): \(error.localizedDescription)")
                    self?.refreshServices()
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("[USMCoreManager] Start request failed for \(serviceId)")
                    self?.refreshServices()
                    return
                }

                print("[USMCoreManager] Started \(serviceId)")
                // Immediate refresh to get real status
                self?.refreshServices()
                // Quick follow-ups for metrics
                self?.scheduleDelayedRefresh(delay: 0.5)
                self?.scheduleDelayedRefresh(delay: 1.5)
            }
        }.resume()
    }

    /// Stop a service
    func stop(_ serviceId: String) {
        let stopURL = baseURL.appendingPathComponent("api/instances/\(serviceId)/stop")
        var request = URLRequest(url: stopURL)
        request.httpMethod = "POST"

        // Optimistic update - replace element to force SwiftUI refresh
        updateServiceStatus(serviceId, status: .stopping)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                if let error = error {
                    print("[USMCoreManager] Failed to stop \(serviceId): \(error.localizedDescription)")
                    self?.refreshServices()
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("[USMCoreManager] Stop request failed for \(serviceId)")
                    self?.refreshServices()
                    return
                }

                print("[USMCoreManager] Stopped \(serviceId)")
                // Immediate refresh to get real status
                self?.refreshServices()
            }
        }.resume()
    }

    /// Restart a service
    func restart(_ serviceId: String) {
        let restartURL = baseURL.appendingPathComponent("api/instances/\(serviceId)/restart")
        var request = URLRequest(url: restartURL)
        request.httpMethod = "POST"

        // Optimistic update - replace element to force SwiftUI refresh
        updateServiceStatus(serviceId, status: .stopping)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                if let error = error {
                    print("[USMCoreManager] Failed to restart \(serviceId): \(error.localizedDescription)")
                    self?.refreshServices()
                    return
                }

                print("[USMCoreManager] Restart request sent for \(serviceId)")
                // Immediate refresh
                self?.refreshServices()
                // Follow-up refresh after service restarts
                self?.scheduleDelayedRefresh(delay: 2.0)
                self?.scheduleDelayedRefresh(delay: 4.0)
            }
        }.resume()
    }

    /// Schedule a delayed refresh for metrics to catch up
    private func scheduleDelayedRefresh(delay: TimeInterval) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                self.refreshServices()
            }
        }
    }

    /// Start all visible services
    func startAll() {
        let servicesToStart = visibleServices.filter { $0.status == .stopped }
        for service in servicesToStart {
            start(service.id)
        }
        // Extra refresh passes to catch all services after they've started
        if !servicesToStart.isEmpty {
            scheduleDelayedRefresh(delay: 2.0)
            scheduleDelayedRefresh(delay: 4.0)
            scheduleDelayedRefresh(delay: 6.0)
        }
    }

    /// Stop all visible services
    func stopAll() {
        let servicesToStop = visibleServices.filter { $0.status == .running }
        for service in servicesToStop {
            stop(service.id)
        }
        // Extra refresh to confirm all stopped
        if !servicesToStop.isEmpty {
            scheduleDelayedRefresh(delay: 1.0)
            scheduleDelayedRefresh(delay: 2.0)
        }
    }

    /// Restart all visible services
    func restartAll() {
        let servicesToRestart = visibleServices.filter { $0.status == .running }
        for service in servicesToRestart {
            restart(service.id)
        }
        // Extra refresh passes for restarts
        if !servicesToRestart.isEmpty {
            scheduleDelayedRefresh(delay: 3.0)
            scheduleDelayedRefresh(delay: 5.0)
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: ServiceEvent) {
        switch event {
        case .statusChanged(let instanceId, let status, _):
            print("[USMCoreManager] WebSocket: Status changed \(instanceId) -> \(status)")
            // Use updateServiceStatus to force SwiftUI refresh
            updateServiceStatus(instanceId, status: status)
            // Also refresh to get metrics
            scheduleDelayedRefresh(delay: 0.3)

        case .metricsUpdated(let instanceId, let cpu, let mem):
            print("[USMCoreManager] WebSocket: Metrics \(instanceId) cpu=\(cpu) mem=\(mem)")
            if let index = services.firstIndex(where: { $0.id == instanceId }) {
                var updated = services[index]
                updated.cpuPercent = cpu
                updated.memoryMB = Int(mem)
                services[index] = updated  // Replace to force SwiftUI update
            }

        case .healthChanged(let instanceId, let healthy, _):
            print("[USMCoreManager] WebSocket: Health \(instanceId) -> \(healthy ? "healthy" : "unhealthy")")

        case .instanceCreated(let instanceId, _):
            print("[USMCoreManager] WebSocket: Instance created \(instanceId)")
            refreshServices()

        case .instanceRemoved(let instanceId):
            print("[USMCoreManager] WebSocket: Instance removed \(instanceId)")
            services.removeAll { $0.id == instanceId }

        case .error(let instanceId, let message):
            print("[USMCoreManager] WebSocket: Error for \(instanceId ?? "unknown"): \(message)")
            lastError = message

        case .configReloaded:
            print("[USMCoreManager] WebSocket: Config reloaded")
            refreshServices()
        }
    }
}

// MARK: - API Response Types

private struct InstancesResponse: Codable {
    let error: Int
    let instances: [InstanceData]
    let running: Int
    let stopped: Int
    let total: Int
}

private struct InstanceData: Codable {
    let id: String
    let templateId: String
    let port: Int
    let status: String
    let autoStart: Bool?
    let configPath: String?
    let envVars: [String: String]?
    let gitBranch: String?
    let tags: [String]?
    let version: String?
    let workingDir: String?
    let pid: Int?
    let startedAt: String?
    let cpuPercent: Double?
    let memoryMB: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case templateId = "template_id"
        case port
        case status
        case autoStart = "auto_start"
        case configPath = "config_path"
        case envVars = "env_vars"
        case gitBranch = "git_branch"
        case tags
        case version
        case workingDir = "working_dir"
        case pid
        case startedAt = "started_at"
        case cpuPercent = "cpu_percent"
        case memoryMB = "memory_mb"
    }
}

private struct TemplateData: Codable {
    let id: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}
