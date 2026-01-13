// UnaMentis - Module Service
// Handles server communication for module discovery and interaction
//
// Modules are server-delivered, not bundled with the app:
// - Server controls which modules are available
// - Users download modules they want to use
// - All practice/reinforcement flows through the server

import Foundation
import Logging

// MARK: - Module Service

/// Service for discovering and interacting with server-hosted modules
@MainActor
public final class ModuleService: ObservableObject {
    /// Shared singleton instance
    public static let shared = ModuleService()

    private static let logger = Logger(label: "com.unamentis.modules.service")

    /// Base URL for the Management API
    private var baseURL: URL?

    /// Whether the service is configured
    @Published private(set) var isConfigured = false

    /// Available modules from the connected server
    @Published private(set) var availableModules: [ModuleSummary] = []

    /// Currently loading
    @Published private(set) var isLoading = false

    /// Last error
    @Published private(set) var lastError: ModuleServiceError?

    private init() {}

    // MARK: - Configuration

    /// Configure the service with server connection details
    /// - Parameters:
    ///   - host: Server hostname or IP
    ///   - port: Server port (default 8766)
    public func configure(host: String, port: Int = 8766) async throws {
        guard !host.isEmpty else {
            throw ModuleServiceError.configurationError("Host cannot be empty")
        }

        let urlString = "http://\(host):\(port)"
        guard let url = URL(string: urlString) else {
            throw ModuleServiceError.configurationError("Invalid URL: \(urlString)")
        }

        self.baseURL = url
        self.isConfigured = true
        Self.logger.info("Module service configured with host: \(host):\(port)")
    }

    // MARK: - Module Discovery

    /// Fetch available modules from the server
    /// - Returns: List of available module summaries
    public func fetchAvailableModules() async throws -> [ModuleSummary] {
        guard let baseURL = baseURL else {
            throw ModuleServiceError.notConfigured
        }

        isLoading = true
        lastError = nil

        defer { isLoading = false }

        let url = baseURL.appendingPathComponent("/api/modules")

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ModuleServiceError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw ModuleServiceError.serverError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let moduleResponse = try decoder.decode(ModuleListResponse.self, from: data)
            self.availableModules = moduleResponse.modules

            Self.logger.info("Fetched \(moduleResponse.modules.count) modules from server")
            return moduleResponse.modules

        } catch let error as ModuleServiceError {
            self.lastError = error
            throw error
        } catch {
            let serviceError = ModuleServiceError.networkError(error.localizedDescription)
            self.lastError = serviceError
            throw serviceError
        }
    }

    /// Fetch detailed information about a specific module
    /// - Parameter moduleId: The module identifier
    /// - Returns: Detailed module information
    public func fetchModuleDetail(moduleId: String) async throws -> ModuleDetail {
        guard let baseURL = baseURL else {
            throw ModuleServiceError.notConfigured
        }

        let url = baseURL.appendingPathComponent("/api/modules/\(moduleId)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModuleServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw ModuleServiceError.moduleNotFound(moduleId)
            }
            throw ModuleServiceError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try decoder.decode(ModuleDetail.self, from: data)
    }

    /// Download a module for local use
    /// - Parameter moduleId: The module identifier
    /// - Returns: Downloaded module data
    public func downloadModule(moduleId: String) async throws -> DownloadedModule {
        guard let baseURL = baseURL else {
            throw ModuleServiceError.notConfigured
        }

        let url = baseURL.appendingPathComponent("/api/modules/\(moduleId)/download")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModuleServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ModuleServiceError.downloadFailed(moduleId)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let downloadedModule = try decoder.decode(DownloadedModule.self, from: data)

        // Store in local registry
        ModuleRegistry.shared.registerDownloaded(downloadedModule)

        Self.logger.info("Downloaded module: \(downloadedModule.name)")
        return downloadedModule
    }
}

// MARK: - Error Types

public enum ModuleServiceError: LocalizedError {
    case notConfigured
    case configurationError(String)
    case networkError(String)
    case invalidResponse
    case serverError(Int)
    case moduleNotFound(String)
    case downloadFailed(String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Module service not configured. Please connect to a server."
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .moduleNotFound(let id):
            return "Module not found: \(id)"
        case .downloadFailed(let id):
            return "Failed to download module: \(id)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        }
    }
}

// MARK: - Response Types

/// Response from module list endpoint
public struct ModuleListResponse: Codable {
    public let modules: [ModuleSummary]
    public let serverVersion: String?
}

/// Summary information about an available module
public struct ModuleSummary: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let description: String
    public let iconName: String
    public let themeColorHex: String
    public let version: String
    public let enabled: Bool?  // Server-side enable/disable
    public let supportsTeamMode: Bool  // Effective flag (base AND override)
    public let supportsSpeedTraining: Bool
    public let supportsCompetitionSim: Bool
    public let downloadSize: Int?  // Size in bytes
    public let isInstalled: Bool?

    /// Whether the module is available (enabled on server)
    public var isEnabled: Bool {
        enabled ?? true
    }

    /// Convert hex color to SwiftUI Color (computed on iOS side)
    public var themeColor: Color {
        Color(hex: themeColorHex) ?? .purple
    }
}

/// Feature overrides configuration from server
public struct FeatureOverrides: Codable, Hashable {
    public let teamMode: Bool?
    public let speedTraining: Bool?
    public let competitionSim: Bool?
}

/// Detailed module information
public struct ModuleDetail: Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let longDescription: String
    public let iconName: String
    public let themeColorHex: String
    public let version: String
    public let enabled: Bool?  // Server-side enable/disable
    // Effective flags (base AND override)
    public let supportsTeamMode: Bool
    public let supportsSpeedTraining: Bool
    public let supportsCompetitionSim: Bool
    // Base capabilities (what the module inherently supports)
    public let baseSupportsTeamMode: Bool?
    public let baseSupportsSpeedTraining: Bool?
    public let baseSupportsCompetitionSim: Bool?
    // Current overrides applied
    public let featureOverrides: FeatureOverrides?
    public let domains: [ModuleDomain]?
    public let studyModes: [String]?
    public let totalQuestions: Int?
    public let estimatedStudyHours: Double?

    /// Whether the module is available (enabled on server)
    public var isEnabled: Bool {
        enabled ?? true
    }
}

/// Domain within a module (e.g., Science, Math for Knowledge Bowl)
public struct ModuleDomain: Codable, Identifiable {
    public let id: String
    public let name: String
    public let weight: Double  // Percentage weight in competition
    public let iconName: String
    public let questionCount: Int?
}

/// Downloaded module data for local storage
///
/// Includes all content needed for offline operation:
/// - Questions and answers for all domains
/// - Study session configurations
/// - Progress tracking metadata
///
/// Can operate in two modes:
/// - **Online**: Enhanced experience with server TTS/AI
/// - **Offline**: Full functionality with on-device AI/TTS
public struct DownloadedModule: Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let iconName: String
    public let themeColorHex: String
    public let version: String
    public let downloadedAt: Date
    public let enabled: Bool?  // Server-side enable/disable
    // Effective feature flags (base AND override applied by server)
    public let supportsTeamMode: Bool
    public let supportsSpeedTraining: Bool
    public let supportsCompetitionSim: Bool

    // MARK: - Content (for offline operation)

    /// All domains in this module
    public let domains: [ModuleContentDomain]?

    /// Total question count
    public let totalQuestions: Int

    /// Study session configurations
    public let studyModes: [ModuleStudyMode]?

    /// Module-specific settings
    public let settings: ModuleSettings?

    /// Whether the module is available (enabled on server at download time)
    public var isEnabled: Bool {
        enabled ?? true
    }
}

/// Domain with full content for offline use
public struct ModuleContentDomain: Codable, Identifiable {
    public let id: String
    public let name: String
    public let iconName: String
    public let weight: Double  // Competition weight percentage
    public let questions: [ModuleQuestion]
    public let subcategories: [String]?
}

/// Question content for offline practice
public struct ModuleQuestion: Codable, Identifiable {
    public let id: String
    public let domainId: String
    public let subcategory: String?
    public let questionText: String
    public let answerText: String
    public let acceptableAnswers: [String]?  // Alternative correct answers
    public let difficulty: Int  // 1-5
    public let speedTargetSeconds: Double?
    public let questionType: String  // "toss-up", "bonus", "lightning", etc.
    public let hints: [String]?
    public let explanation: String?
}

/// Study mode configuration
public struct ModuleStudyMode: Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let iconName: String
    public let questionCount: Int?
    public let timeLimitSeconds: Int?
    public let allowHints: Bool
    public let shuffleQuestions: Bool
}

/// Module-specific settings
public struct ModuleSettings: Codable {
    public let defaultTimePerQuestion: Double
    public let conferTimeSeconds: Double?  // For team mode
    public let enableSpokenQuestions: Bool
    public let enableSpokenAnswers: Bool
    public let minimumMasteryForCompletion: Double
}

// MARK: - Color Extension

import SwiftUI

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
