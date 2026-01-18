// Service.swift
// Service models for USM-FFI

import SwiftUI

// MARK: - Service Status

enum ServiceStatus: Int, Codable, CaseIterable {
    case stopped = 0
    case running = 1
    case error = 2
    case starting = 3
    case stopping = 4
    case unknown = 5

    var displayName: String {
        switch self {
        case .stopped: return "Stopped"
        case .running: return "Running"
        case .error: return "Error"
        case .starting: return "Starting"
        case .stopping: return "Stopping"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .running: return .green
        case .stopped: return .red
        case .error: return .orange
        case .starting, .stopping: return .yellow
        case .unknown: return .gray
        }
    }

    /// Create from API string representation
    static func from(string: String) -> ServiceStatus {
        switch string.lowercased() {
        case "stopped": return .stopped
        case "running": return .running
        case "starting": return .starting
        case "stopping": return .stopping
        case "error": return .error
        default: return .unknown
        }
    }

    /// String value for API serialization (matches decoder expectation)
    var stringValue: String {
        switch self {
        case .stopped: return "stopped"
        case .running: return "running"
        case .starting: return "starting"
        case .stopping: return "stopping"
        case .error: return "error"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - Service Category

enum ServiceCategory: String, Codable, CaseIterable {
    case core
    case development
    case database
    case infrastructure
    case custom

    var displayName: String {
        switch self {
        case .core: return "Core"
        case .development: return "Development"
        case .database: return "Database"
        case .infrastructure: return "Infrastructure"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Service Info

struct ServiceInfo: Identifiable, Equatable {
    let id: String
    let templateId: String
    let displayName: String
    let port: Int
    var status: ServiceStatus
    var cpuPercent: Double
    var memoryMB: Int

    // Computed display name (formatted from ID if needed)
    var formattedName: String {
        if displayName.isEmpty || displayName == id {
            return id
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
        return displayName
    }

    // Category inferred from template ID
    // Must match old app's categorization: only feature-flags is development
    var category: ServiceCategory {
        // Development tools - only feature flags
        // Note: log-server is core, not development (matches old app behavior)
        if templateId == "feature-flags" || templateId.contains("feature-flag") {
            return .development
        }
        // Databases
        if templateId.contains("postgres") || templateId.contains("redis") ||
           templateId.contains("db") || templateId.contains("mysql") ||
           templateId.contains("mongo") {
            return .database
        }
        // Infrastructure
        if templateId.contains("docker") || templateId.contains("infra") {
            return .infrastructure
        }
        return .core
    }

    static func == (lhs: ServiceInfo, rhs: ServiceInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.cpuPercent == rhs.cpuPercent &&
        lhs.memoryMB == rhs.memoryMB
    }
}

// MARK: - Service Events (for WebSocket)

enum ServiceEvent: Codable {
    case statusChanged(instanceId: String, status: ServiceStatus, pid: Int?)
    case metricsUpdated(instanceId: String, cpuPercent: Double, memoryMB: UInt64)
    case healthChanged(instanceId: String, healthy: Bool, message: String?)
    case instanceCreated(instanceId: String, templateId: String)
    case instanceRemoved(instanceId: String)
    case error(instanceId: String?, message: String)
    case configReloaded

    enum CodingKeys: String, CodingKey {
        case type
        case instanceId = "instance_id"
        case templateId = "template_id"
        case status
        case pid
        case cpuPercent = "cpu_percent"
        case memoryMB = "memory_mb"
        case healthy
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        // Rust uses snake_case for event types (e.g., "status_changed")
        switch type {
        case "status_changed":
            let instanceId = try container.decode(String.self, forKey: .instanceId)
            // Rust sends status as lowercase string (e.g., "running")
            let statusString = try container.decode(String.self, forKey: .status)
            let status = ServiceStatus.from(string: statusString)
            let pid = try container.decodeIfPresent(Int.self, forKey: .pid)
            self = .statusChanged(instanceId: instanceId, status: status, pid: pid)

        case "metrics_updated":
            let instanceId = try container.decode(String.self, forKey: .instanceId)
            let cpu = try container.decode(Double.self, forKey: .cpuPercent)
            let mem = try container.decode(UInt64.self, forKey: .memoryMB)
            self = .metricsUpdated(instanceId: instanceId, cpuPercent: cpu, memoryMB: mem)

        case "health_changed":
            let instanceId = try container.decode(String.self, forKey: .instanceId)
            let healthy = try container.decode(Bool.self, forKey: .healthy)
            let message = try container.decodeIfPresent(String.self, forKey: .message)
            self = .healthChanged(instanceId: instanceId, healthy: healthy, message: message)

        case "instance_created":
            let instanceId = try container.decode(String.self, forKey: .instanceId)
            let templateId = try container.decode(String.self, forKey: .templateId)
            self = .instanceCreated(instanceId: instanceId, templateId: templateId)

        case "instance_removed":
            let instanceId = try container.decode(String.self, forKey: .instanceId)
            self = .instanceRemoved(instanceId: instanceId)

        case "error":
            let instanceId = try container.decodeIfPresent(String.self, forKey: .instanceId)
            let message = try container.decode(String.self, forKey: .message)
            self = .error(instanceId: instanceId, message: message)

        case "config_reloaded":
            self = .configReloaded

        default:
            print("[ServiceEvent] Unknown event type: \(type)")
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown event type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .statusChanged(let instanceId, let status, let pid):
            try container.encode("status_changed", forKey: .type)
            try container.encode(instanceId, forKey: .instanceId)
            try container.encode(status.stringValue, forKey: .status)
            try container.encodeIfPresent(pid, forKey: .pid)

        case .metricsUpdated(let instanceId, let cpu, let mem):
            try container.encode("metrics_updated", forKey: .type)
            try container.encode(instanceId, forKey: .instanceId)
            try container.encode(cpu, forKey: .cpuPercent)
            try container.encode(mem, forKey: .memoryMB)

        case .healthChanged(let instanceId, let healthy, let message):
            try container.encode("health_changed", forKey: .type)
            try container.encode(instanceId, forKey: .instanceId)
            try container.encode(healthy, forKey: .healthy)
            try container.encodeIfPresent(message, forKey: .message)

        case .instanceCreated(let instanceId, let templateId):
            try container.encode("instance_created", forKey: .type)
            try container.encode(instanceId, forKey: .instanceId)
            try container.encode(templateId, forKey: .templateId)

        case .instanceRemoved(let instanceId):
            try container.encode("instance_removed", forKey: .type)
            try container.encode(instanceId, forKey: .instanceId)

        case .error(let instanceId, let message):
            try container.encode("error", forKey: .type)
            try container.encodeIfPresent(instanceId, forKey: .instanceId)
            try container.encode(message, forKey: .message)

        case .configReloaded:
            try container.encode("config_reloaded", forKey: .type)
        }
    }
}
