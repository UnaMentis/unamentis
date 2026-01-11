// UnaMentis - Server Configuration Manager
// Manages self-hosted server configuration, discovery, and health monitoring
//
// Part of Core/Config

import Foundation
import Logging
import Network

// MARK: - Server Configuration

/// Configuration for a self-hosted server
public struct ServerConfig: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var isEnabled: Bool
    public var lastHealthCheck: Date?
    public var healthStatus: ServerHealthStatus
    public var serverType: ServerType
    public var discoveredServices: [DiscoveredService]
    public var discoveredModels: [String]
    public var discoveredVoices: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        isEnabled: Bool = true,
        lastHealthCheck: Date? = nil,
        healthStatus: ServerHealthStatus = .unknown,
        serverType: ServerType = .unamentisGateway,
        discoveredServices: [DiscoveredService] = [],
        discoveredModels: [String] = [],
        discoveredVoices: [String] = []
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.isEnabled = isEnabled
        self.lastHealthCheck = lastHealthCheck
        self.healthStatus = healthStatus
        self.serverType = serverType
        self.discoveredServices = discoveredServices
        self.discoveredModels = discoveredModels
        self.discoveredVoices = discoveredVoices
    }

    /// Full URL to the server
    public var baseURL: URL? {
        URL(string: "http://\(host):\(port)")
    }

    /// URL for health check endpoint
    public var healthURL: URL? {
        baseURL?.appendingPathComponent("health")
    }

    /// URL for discovery endpoint (UnaMentis gateway)
    public var discoveryURL: URL? {
        baseURL
    }
}

// MARK: - Server Types

/// Type of self-hosted server
public enum ServerType: String, Codable, Sendable, CaseIterable {
    case unamentisGateway = "unamentis"  // Our unified gateway
    case ollama = "ollama"                  // Ollama LLM server
    case whisperServer = "whisper"          // Whisper STT server
    case piperServer = "piper"              // Piper TTS server
    case vibeVoiceServer = "vibevoice"      // VibeVoice TTS server (Microsoft VibeVoice-Realtime-0.5B)
    case chatterboxServer = "chatterbox"    // Chatterbox TTS server (Resemble AI)
    case llamaCpp = "llama.cpp"             // llama.cpp server
    case vllm = "vllm"                      // vLLM server
    case custom = "custom"                  // Custom OpenAI-compatible

    public var displayName: String {
        switch self {
        case .unamentisGateway: return "UnaMentis Gateway"
        case .ollama: return "Ollama"
        case .whisperServer: return "Whisper"
        case .piperServer: return "Piper TTS"
        case .vibeVoiceServer: return "VibeVoice TTS"
        case .chatterboxServer: return "Chatterbox TTS"
        case .llamaCpp: return "llama.cpp"
        case .vllm: return "vLLM"
        case .custom: return "Custom Server"
        }
    }

    public var defaultPort: Int {
        switch self {
        case .unamentisGateway: return 11400
        case .ollama: return 11434
        case .whisperServer: return 11401
        case .piperServer: return 11402
        case .vibeVoiceServer: return 8880
        case .chatterboxServer: return 8004
        case .llamaCpp: return 8080
        case .vllm: return 8000
        case .custom: return 8080
        }
    }

    public var supportsDiscovery: Bool {
        self == .unamentisGateway
    }
}

// MARK: - Discovered Service

/// A service discovered from a UnaMentis gateway
public struct DiscoveredService: Codable, Sendable {
    public let type: ServiceType
    public let url: String
    public let model: String?

    public enum ServiceType: String, Codable, Sendable {
        case llm
        case stt
        case tts
    }
}

// MARK: - Health Status

/// Health status of a server
public enum ServerHealthStatus: String, Codable, Sendable {
    case unknown
    case checking
    case healthy
    case degraded
    case unhealthy

    public var isUsable: Bool {
        self == .healthy || self == .degraded
    }

    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .checking: return "Checking..."
        case .healthy: return "Healthy"
        case .degraded: return "Degraded"
        case .unhealthy: return "Unavailable"
        }
    }

    public var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .checking: return "arrow.clockwise"
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .unhealthy: return "xmark.circle.fill"
        }
    }
}

// MARK: - Server Config Manager

/// Manages self-hosted server configuration and health monitoring
public actor ServerConfigManager {

    // MARK: - Singleton

    public static let shared = ServerConfigManager()

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.serverconfig")
    private var servers: [UUID: ServerConfig] = [:]
    private var healthCheckTask: Task<Void, Never>?
    private let userDefaults = UserDefaults.standard
    private let storageKey = "voicelearn.server.configs"

    /// Health check interval in seconds
    public var healthCheckInterval: TimeInterval = 30

    // MARK: - Initialization

    private init() {
        Task {
            await loadSavedConfigs()
            await startHealthMonitoring()
        }
    }

    // MARK: - Server Management

    /// Get all configured servers
    public func getAllServers() -> [ServerConfig] {
        Array(servers.values).sorted { $0.name < $1.name }
    }

    /// Get a specific server by ID
    public func getServer(_ id: UUID) -> ServerConfig? {
        servers[id]
    }

    /// Get servers by type
    public func getServers(ofType type: ServerType) -> [ServerConfig] {
        servers.values.filter { $0.serverType == type }
    }

    /// Get all healthy LLM servers
    public func getHealthyLLMServers() -> [ServerConfig] {
        servers.values.filter { server in
            server.isEnabled &&
            server.healthStatus.isUsable &&
            (server.serverType == .ollama ||
             server.serverType == .llamaCpp ||
             server.serverType == .vllm ||
             server.serverType == .unamentisGateway ||
             server.serverType == .custom)
        }
    }

    /// Get all healthy STT servers
    public func getHealthySTTServers() -> [ServerConfig] {
        servers.values.filter { server in
            server.isEnabled &&
            server.healthStatus.isUsable &&
            (server.serverType == .whisperServer ||
             server.serverType == .unamentisGateway)
        }
    }

    /// Get all healthy TTS servers
    public func getHealthyTTSServers() -> [ServerConfig] {
        servers.values.filter { server in
            server.isEnabled &&
            server.healthStatus.isUsable &&
            (server.serverType == .piperServer ||
             server.serverType == .vibeVoiceServer ||
             server.serverType == .chatterboxServer ||
             server.serverType == .unamentisGateway)
        }
    }

    /// Get all healthy Chatterbox TTS servers
    public func getHealthyChatterboxServers() -> [ServerConfig] {
        servers.values.filter { server in
            server.isEnabled &&
            server.healthStatus.isUsable &&
            server.serverType == .chatterboxServer
        }
    }

    /// Add a new server configuration
    @discardableResult
    public func addServer(_ config: ServerConfig) -> ServerConfig {
        servers[config.id] = config
        saveConfigs()
        logger.info("Added server: \(config.name) at \(config.host):\(config.port)")

        // Immediately check health
        Task {
            await checkServerHealth(config.id)
        }

        return config
    }

    /// Update an existing server configuration
    public func updateServer(_ config: ServerConfig) {
        servers[config.id] = config
        saveConfigs()
        logger.info("Updated server: \(config.name)")
    }

    /// Remove a server configuration
    public func removeServer(_ id: UUID) {
        if let server = servers.removeValue(forKey: id) {
            saveConfigs()
            logger.info("Removed server: \(server.name)")
        }
    }

    /// Add default localhost server
    public func addDefaultServer() {
        let defaultServer = ServerConfig(
            name: "Local Mac",
            host: "localhost",
            port: 11400,
            serverType: .unamentisGateway
        )
        addServer(defaultServer)
    }

    // MARK: - Auto-Discovery

    /// Discover UnaMentis servers on the local network
    public func discoverLocalServers() async -> [ServerConfig] {
        logger.info("Starting local server discovery...")
        var discovered: [ServerConfig] = []

        // Common hosts to check
        let hosts = [
            "localhost",
            "127.0.0.1",
            getLocalIPAddress() ?? "localhost"
        ]

        // Ports to scan
        let ports = [11400, 11434, 8080, 8000]

        await withTaskGroup(of: ServerConfig?.self) { group in
            for host in hosts {
                for port in ports {
                    group.addTask {
                        await self.probeServer(host: host, port: port)
                    }
                }
            }

            for await result in group {
                if let server = result {
                    discovered.append(server)
                }
            }
        }

        logger.info("Discovery complete. Found \(discovered.count) servers.")
        return discovered
    }

    /// Probe a specific host:port for a compatible server
    private func probeServer(host: String, port: Int) async -> ServerConfig? {
        let urlString = "http://\(host):\(port)"

        // Try UnaMentis gateway discovery first
        if let gatewayServer = await probeUnaMentisGateway(host: host, port: port) {
            return gatewayServer
        }

        // Try Ollama
        if let ollamaServer = await probeOllama(host: host, port: port) {
            return ollamaServer
        }

        return nil
    }

    /// Probe for UnaMentis gateway
    private func probeUnaMentisGateway(host: String, port: Int) async -> ServerConfig? {
        guard let url = URL(string: "http://\(host):\(port)/") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Parse discovery response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let isUnaMentis = json["unamentis_server"] as? Bool,
               isUnaMentis {

                var discoveredServices: [DiscoveredService] = []

                if let services = json["services"] as? [String: [String: Any]] {
                    for (type, info) in services {
                        if let serviceType = DiscoveredService.ServiceType(rawValue: type),
                           let serviceUrl = info["url"] as? String {
                            let model = info["model"] as? String
                            discoveredServices.append(DiscoveredService(
                                type: serviceType,
                                url: serviceUrl,
                                model: model
                            ))
                        }
                    }
                }

                return ServerConfig(
                    name: "UnaMentis Server (\(host))",
                    host: host,
                    port: port,
                    healthStatus: .healthy,
                    serverType: .unamentisGateway,
                    discoveredServices: discoveredServices
                )
            }
        } catch {
            // Not a UnaMentis gateway
        }

        return nil
    }

    /// Probe for Ollama server
    private func probeOllama(host: String, port: Int) async -> ServerConfig? {
        guard let url = URL(string: "http://\(host):\(port)/api/version") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Parse Ollama version response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["version"] != nil {
                return ServerConfig(
                    name: "Ollama (\(host))",
                    host: host,
                    port: port,
                    healthStatus: .healthy,
                    serverType: .ollama
                )
            }
        } catch {
            // Not an Ollama server
        }

        return nil
    }

    // MARK: - Health Monitoring

    /// Start periodic health monitoring
    public func startHealthMonitoring() {
        healthCheckTask?.cancel()

        healthCheckTask = Task {
            while !Task.isCancelled {
                await checkAllServersHealth()
                try? await Task.sleep(for: .seconds(healthCheckInterval))
            }
        }

        logger.info("Started health monitoring with \(healthCheckInterval)s interval")
    }

    /// Stop health monitoring
    public func stopHealthMonitoring() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        logger.info("Stopped health monitoring")
    }

    /// Check health of all servers
    public func checkAllServersHealth() async {
        await withTaskGroup(of: Void.self) { group in
            for id in servers.keys {
                group.addTask {
                    await self.checkServerHealth(id)
                }
            }
        }
    }

    /// Check health of a specific server
    @discardableResult
    public func checkServerHealth(_ id: UUID) async -> ServerHealthStatus {
        guard var server = servers[id] else {
            return .unknown
        }

        server.healthStatus = .checking
        servers[id] = server

        let status = await performHealthCheck(server)

        server.healthStatus = status
        server.lastHealthCheck = Date()
        servers[id] = server
        saveConfigs()

        logger.debug("Server \(server.name) health: \(status.rawValue)")

        return status
    }

    /// Perform actual health check request
    private func performHealthCheck(_ server: ServerConfig) async -> ServerHealthStatus {
        guard let healthURL = server.healthURL else {
            return .unhealthy
        }

        do {
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .unhealthy
            }

            switch httpResponse.statusCode {
            case 200:
                return .healthy
            case 503:
                return .degraded
            default:
                return .unhealthy
            }
        } catch {
            logger.warning("Health check failed for \(server.name): \(error.localizedDescription)")
            return .unhealthy
        }
    }

    // MARK: - Capability Discovery

    /// Discover available models on an Ollama server
    public func discoverOllamaModels(host: String, port: Int = 11434) async -> [String] {
        guard let url = URL(string: "http://\(host):\(port)/api/tags") else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }

            // Parse Ollama /api/tags response: { "models": [{ "name": "qwen2.5:32b", ... }] }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                return models.compactMap { $0["name"] as? String }
            }
        } catch {
            logger.debug("Failed to discover Ollama models: \(error.localizedDescription)")
        }

        return []
    }

    /// Discover available voices on a Piper TTS server
    public func discoverPiperVoices(host: String, port: Int = 11402) async -> [String] {
        guard let url = URL(string: "http://\(host):\(port)/voices") else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }

            // Parse Piper /voices response: { "voices": [{ "id": "nova", "name": "Nova" }] }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let voices = json["voices"] as? [[String: Any]] {
                return voices.compactMap { $0["id"] as? String }
            }
        } catch {
            logger.debug("Failed to discover Piper voices: \(error.localizedDescription)")
        }

        return []
    }

    /// Discover available voices on a VibeVoice TTS server
    public func discoverVibeVoiceVoices(host: String, port: Int = 8880) async -> [String] {
        guard let url = URL(string: "http://\(host):\(port)/v1/audio/voices") else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }

            // Parse VibeVoice /v1/audio/voices response: { "voices": [{ "voice_id": "nova", "name": "nova" }] }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let voices = json["voices"] as? [[String: Any]] {
                return voices.compactMap { $0["voice_id"] as? String }
            }
        } catch {
            logger.debug("Failed to discover VibeVoice voices: \(error.localizedDescription)")
        }

        return []
    }

    /// Check if Chatterbox TTS server is available and get its capabilities
    public func discoverChatterboxCapabilities(host: String, port: Int = 8004) async -> ChatterboxServerInfo? {
        guard let healthURL = URL(string: "http://\(host):\(port)/health") else {
            return nil
        }

        do {
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Parse health response to get model info
            var modelType = "turbo"
            var device = "unknown"

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let model = json["model"] as? String {
                    modelType = model
                }
                if let dev = json["device"] as? String {
                    device = dev
                }
            }

            // Check for multilingual model availability
            let isMultilingualAvailable = await checkChatterboxMultilingual(host: host, port: port)

            return ChatterboxServerInfo(
                isAvailable: true,
                modelType: modelType,
                device: device,
                isMultilingualAvailable: isMultilingualAvailable
            )
        } catch {
            logger.debug("Failed to discover Chatterbox server: \(error.localizedDescription)")
        }

        return nil
    }

    /// Check if Chatterbox multilingual model is available
    private func checkChatterboxMultilingual(host: String, port: Int) async -> Bool {
        guard let modelsURL = URL(string: "http://\(host):\(port)/v1/models") else {
            return false
        }

        do {
            var request = URLRequest(url: modelsURL)
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [String] {
                return models.contains { $0.lowercased().contains("multilingual") }
            }
        } catch {
            // Models endpoint may not exist
        }

        return false
    }

    /// Full capability discovery for a given host (checks all known services)
    public func discoverCapabilities(host: String) async -> ServerCapabilities {
        async let ollamaModels = discoverOllamaModels(host: host, port: 11434)
        async let piperVoices = discoverPiperVoices(host: host, port: 11402)
        async let vibeVoiceVoices = discoverVibeVoiceVoices(host: host, port: 8880)
        async let chatterboxInfo = discoverChatterboxCapabilities(host: host, port: 8004)

        let models = await ollamaModels
        let piper = await piperVoices
        let vibeVoice = await vibeVoiceVoices
        let chatterbox = await chatterboxInfo

        logger.info("Discovered capabilities on \(host): \(models.count) LLM models, \(piper.count) Piper voices, \(vibeVoice.count) VibeVoice voices, Chatterbox: \(chatterbox != nil)")

        return ServerCapabilities(
            llmModels: models,
            piperVoices: piper,
            vibeVoiceVoices: vibeVoice,
            chatterboxInfo: chatterbox,
            hasOllama: !models.isEmpty,
            hasPiperTTS: !piper.isEmpty,
            hasVibeVoiceTTS: !vibeVoice.isEmpty,
            hasChatterboxTTS: chatterbox != nil
        )
    }

    /// Get all discovered LLM models across all healthy servers
    public func getAllDiscoveredModels() -> [String] {
        var models = Set<String>()
        for server in servers.values where server.healthStatus.isUsable {
            models.formUnion(server.discoveredModels)
        }
        return Array(models).sorted()
    }

    /// Get all discovered TTS voices across all healthy servers
    public func getAllDiscoveredVoices() -> [String] {
        var voices = Set<String>()
        for server in servers.values where server.healthStatus.isUsable {
            voices.formUnion(server.discoveredVoices)
        }
        return Array(voices).sorted()
    }

    // MARK: - Persistence

    /// Save configurations to UserDefaults
    private func saveConfigs() {
        do {
            let data = try JSONEncoder().encode(Array(servers.values))
            userDefaults.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to save server configs: \(error.localizedDescription)")
        }
    }

    /// Load configurations from UserDefaults
    private func loadSavedConfigs() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            logger.info("No saved server configurations found")
            return
        }

        do {
            let configs = try JSONDecoder().decode([ServerConfig].self, from: data)
            for config in configs {
                servers[config.id] = config
            }
            logger.info("Loaded \(configs.count) server configurations")
        } catch {
            logger.error("Failed to load server configs: \(error.localizedDescription)")
        }
    }

    // MARK: - Utilities

    /// Get the device's local IP address
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }

        return address
    }

    // MARK: - Convenience Accessors

    /// Get the best available LLM endpoint URL
    public func getBestLLMEndpoint() -> URL? {
        if let server = getHealthyLLMServers().first,
           let baseURL = server.baseURL {
            // For UnaMentis gateway, use the unified endpoint
            if server.serverType == .unamentisGateway {
                return baseURL.appendingPathComponent("v1/chat/completions")
            }
            // For Ollama
            if server.serverType == .ollama {
                return baseURL.appendingPathComponent("v1/chat/completions")
            }
            return baseURL
        }
        return nil
    }

    /// Get the best available STT endpoint URL
    public func getBestSTTEndpoint() -> URL? {
        if let server = getHealthySTTServers().first,
           let baseURL = server.baseURL {
            return baseURL.appendingPathComponent("v1/audio/transcriptions")
        }
        return nil
    }

    /// Get the best available TTS endpoint URL
    public func getBestTTSEndpoint() -> URL? {
        if let server = getHealthyTTSServers().first,
           let baseURL = server.baseURL {
            return baseURL.appendingPathComponent("v1/audio/speech")
        }
        return nil
    }

    /// Check if any self-hosted server is available
    public var hasAvailableServer: Bool {
        !getHealthyLLMServers().isEmpty
    }
}

// MARK: - Server Capabilities

/// Information about a discovered Chatterbox server
public struct ChatterboxServerInfo: Sendable {
    public let isAvailable: Bool
    public let modelType: String  // "turbo" or "multilingual"
    public let device: String     // "cuda", "mps", "cpu"
    public let isMultilingualAvailable: Bool

    public init(
        isAvailable: Bool,
        modelType: String,
        device: String,
        isMultilingualAvailable: Bool
    ) {
        self.isAvailable = isAvailable
        self.modelType = modelType
        self.device = device
        self.isMultilingualAvailable = isMultilingualAvailable
    }
}

/// Discovered capabilities from a server
public struct ServerCapabilities: Sendable {
    public let llmModels: [String]
    public let piperVoices: [String]
    public let vibeVoiceVoices: [String]
    public let chatterboxInfo: ChatterboxServerInfo?
    public let hasOllama: Bool
    public let hasPiperTTS: Bool
    public let hasVibeVoiceTTS: Bool
    public let hasChatterboxTTS: Bool

    /// All TTS voices (combined from Piper and VibeVoice)
    public var ttsVoices: [String] {
        piperVoices + vibeVoiceVoices
    }

    public var isEmpty: Bool {
        llmModels.isEmpty && piperVoices.isEmpty && vibeVoiceVoices.isEmpty && !hasChatterboxTTS
    }

    public var summary: String {
        var parts: [String] = []
        if hasOllama {
            parts.append("\(llmModels.count) LLM model(s)")
        }
        if hasPiperTTS {
            parts.append("Piper TTS")
        }
        if hasVibeVoiceTTS {
            parts.append("VibeVoice TTS")
        }
        if hasChatterboxTTS {
            let model = chatterboxInfo?.modelType ?? "unknown"
            parts.append("Chatterbox TTS (\(model))")
        }
        return parts.isEmpty ? "No services found" : parts.joined(separator: ", ")
    }
}

// MARK: - Management API Model Info

/// Model information from the Management API
public struct ManagementModelInfo: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let type: String  // "llm", "stt", "tts"
    public let serverID: String
    public let serverName: String
    public let status: String  // "available", "loaded", "loading"
    public let sizeGB: Double?
    public let parameterSize: String?
    public let quantization: String?
    public let family: String?
    public let contextWindow: Int?
    public let contextWindowFormatted: String?
    public let vramGB: Double?

    public init(
        id: String,
        name: String,
        type: String,
        serverID: String,
        serverName: String,
        status: String,
        sizeGB: Double? = nil,
        parameterSize: String? = nil,
        quantization: String? = nil,
        family: String? = nil,
        contextWindow: Int? = nil,
        contextWindowFormatted: String? = nil,
        vramGB: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.serverID = serverID
        self.serverName = serverName
        self.status = status
        self.sizeGB = sizeGB
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.family = family
        self.contextWindow = contextWindow
        self.contextWindowFormatted = contextWindowFormatted
        self.vramGB = vramGB
    }
}

/// Model parameter definition from the Management API
public struct ModelParameterDef: Sendable {
    public let value: Double
    public let min: Double
    public let max: Double
    public let step: Double?
    public let description: String
    public let modelMaxContext: Int?
}

/// Model parameters response from the Management API
public struct ModelParametersResponse: Sendable {
    public let model: String
    public let parameters: [String: ModelParameterDef]
    public let contextWindow: Int?
    public let contextWindowFormatted: String?
}

// MARK: - Management API Extensions

extension ServerConfigManager {

    /// Discover models from the Management API
    /// - Parameter host: The host IP address (Management API is on port 8766)
    /// - Returns: Array of ManagementModelInfo
    public func discoverManagementModels(host: String) async -> [ManagementModelInfo] {
        guard !host.isEmpty else { return [] }

        let urlString = "http://\(host):8766/api/models"
        guard let url = URL(string: urlString) else { return [] }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArray = json["models"] as? [[String: Any]] else {
                return []
            }

            var models: [ManagementModelInfo] = []
            for modelDict in modelsArray {
                guard let id = modelDict["id"] as? String,
                      let name = modelDict["name"] as? String,
                      let type = modelDict["type"] as? String,
                      let serverID = modelDict["server_id"] as? String,
                      let serverName = modelDict["server_name"] as? String,
                      let status = modelDict["status"] as? String else {
                    continue
                }

                let model = ManagementModelInfo(
                    id: id,
                    name: name,
                    type: type,
                    serverID: serverID,
                    serverName: serverName,
                    status: status,
                    sizeGB: modelDict["size_gb"] as? Double,
                    parameterSize: modelDict["parameter_size"] as? String,
                    quantization: modelDict["quantization"] as? String,
                    family: modelDict["family"] as? String,
                    contextWindow: modelDict["context_window"] as? Int,
                    contextWindowFormatted: modelDict["context_window_formatted"] as? String,
                    vramGB: modelDict["vram_gb"] as? Double
                )
                models.append(model)
            }

            return models
        } catch {
            print("ServerConfigManager: Failed to discover management models: \(error)")
            return []
        }
    }

    /// Get model parameters from the Management API
    /// - Parameters:
    ///   - host: The host IP address
    ///   - modelID: The model ID (e.g., "ollama:ministral-3:14b")
    /// - Returns: ModelParametersResponse or nil
    public func getModelParameters(host: String, modelID: String) async -> ModelParametersResponse? {
        guard !host.isEmpty else { return nil }

        let urlString = "http://\(host):8766/api/models/\(modelID)/parameters"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String,
                  status == "ok",
                  let modelName = json["model"] as? String,
                  let paramsDict = json["parameters"] as? [String: [String: Any]] else {
                return nil
            }

            var parameters: [String: ModelParameterDef] = [:]
            for (key, paramDict) in paramsDict {
                guard let value = paramDict["value"] as? Double,
                      let min = paramDict["min"] as? Double,
                      let max = paramDict["max"] as? Double,
                      let description = paramDict["description"] as? String else {
                    continue
                }

                parameters[key] = ModelParameterDef(
                    value: value,
                    min: min,
                    max: max,
                    step: paramDict["step"] as? Double,
                    description: description,
                    modelMaxContext: paramDict["model_max_context"] as? Int
                )
            }

            // Extract model_info if present
            let modelInfo = json["model_info"] as? [String: Any]

            return ModelParametersResponse(
                model: modelName,
                parameters: parameters,
                contextWindow: modelInfo?["context_window"] as? Int,
                contextWindowFormatted: modelInfo?["context_window_formatted"] as? String
            )
        } catch {
            print("ServerConfigManager: Failed to get model parameters: \(error)")
            return nil
        }
    }

    /// Save model parameters via the Management API
    /// - Parameters:
    ///   - host: The host IP address
    ///   - modelID: The model ID
    ///   - parameters: Dictionary of parameter name to value
    /// - Returns: True if successful
    public func saveModelParameters(host: String, modelID: String, parameters: [String: Double]) async -> Bool {
        guard !host.isEmpty else { return false }

        let urlString = "http://\(host):8766/api/models/\(modelID)/parameters"
        guard let url = URL(string: urlString) else { return false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10

            let body: [String: Any] = ["parameters": parameters]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String,
                  status == "ok" else {
                return false
            }

            return true
        } catch {
            print("ServerConfigManager: Failed to save model parameters: \(error)")
            return false
        }
    }

    /// Get the model configuration from the Management API
    /// - Parameter host: The host IP address
    /// - Returns: Dictionary with config or nil
    public func getModelConfig(host: String) async -> [String: Any]? {
        guard !host.isEmpty else { return nil }

        let urlString = "http://\(host):8766/api/models/config"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let config = json["config"] as? [String: Any] else {
                return nil
            }

            return config
        } catch {
            print("ServerConfigManager: Failed to get model config: \(error)")
            return nil
        }
    }

    /// Save model configuration via the Management API
    /// - Parameters:
    ///   - host: The host IP address
    ///   - config: Configuration dictionary
    /// - Returns: True if successful
    public func saveModelConfig(host: String, config: [String: Any]) async -> Bool {
        guard !host.isEmpty else { return false }

        let urlString = "http://\(host):8766/api/models/config"
        guard let url = URL(string: urlString) else { return false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            request.httpBody = try JSONSerialization.data(withJSONObject: config)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String,
                  status == "ok" else {
                return false
            }

            return true
        } catch {
            print("ServerConfigManager: Failed to save model config: \(error)")
            return false
        }
    }
}

// MARK: - Server Config Manager Delegate

/// Protocol for receiving server status updates
public protocol ServerConfigManagerDelegate: AnyObject, Sendable {
    func serverStatusChanged(_ server: ServerConfig)
    func serversDiscovered(_ servers: [ServerConfig])
}
