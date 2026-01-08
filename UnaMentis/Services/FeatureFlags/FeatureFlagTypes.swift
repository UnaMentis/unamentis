// UnaMentis - Feature Flag Types
// Type definitions for the feature flag system
//
// Part of Quality Infrastructure (Phase 3)

import Foundation

// MARK: - Feature Flag Protocol

/// Protocol for feature flag evaluation
public protocol FeatureFlagEvaluating: Sendable {
    /// Check if a feature flag is enabled
    func isEnabled(_ flagName: String) async -> Bool

    /// Check if a feature flag is enabled with context
    func isEnabled(_ flagName: String, context: FeatureFlagContext) async -> Bool

    /// Get a variant value for a flag
    func getVariant(_ flagName: String) async -> FeatureFlagVariant?

    /// Get a variant value for a flag with context
    func getVariant(_ flagName: String, context: FeatureFlagContext) async -> FeatureFlagVariant?

    /// Force refresh flags from server
    func refresh() async throws
}

// MARK: - Context

/// Context for feature flag evaluation (user targeting, etc.)
public struct FeatureFlagContext: Sendable, Codable, Equatable {
    public let userId: String?
    public let sessionId: String?
    public let appVersion: String?
    public let platform: String
    public let properties: [String: String]

    public init(
        userId: String? = nil,
        sessionId: String? = nil,
        appVersion: String? = nil,
        platform: String = "iOS",
        properties: [String: String] = [:]
    ) {
        self.userId = userId
        self.sessionId = sessionId
        self.appVersion = appVersion
        self.platform = platform
        self.properties = properties
    }

    /// Create context with current app version
    public static func current(userId: String? = nil, sessionId: String? = nil) -> FeatureFlagContext {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return FeatureFlagContext(
            userId: userId,
            sessionId: sessionId,
            appVersion: version,
            platform: "iOS"
        )
    }
}

// MARK: - Variant

/// A feature flag variant (for A/B tests, etc.)
public struct FeatureFlagVariant: Sendable, Codable, Equatable {
    public let name: String
    public let enabled: Bool
    public let payload: FeatureFlagPayload?

    public init(name: String, enabled: Bool, payload: FeatureFlagPayload? = nil) {
        self.name = name
        self.enabled = enabled
        self.payload = payload
    }
}

/// Payload for feature flag variants
public enum FeatureFlagPayload: Sendable, Codable, Equatable {
    case string(String)
    case number(Double)
    case json([String: String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let jsonValue = try? container.decode([String: String].self) {
            self = .json(jsonValue)
        } else {
            throw DecodingError.typeMismatch(
                FeatureFlagPayload.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unable to decode payload"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .json(value):
            try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    public var jsonValue: [String: String]? {
        if case let .json(value) = self { return value }
        return nil
    }
}

// MARK: - Configuration

/// Configuration for the feature flag service
public struct FeatureFlagConfig: Sendable {
    public let proxyURL: URL
    public let clientKey: String
    public let appName: String
    public let refreshInterval: TimeInterval
    public let enableOfflineMode: Bool
    public let enableMetrics: Bool

    public init(
        proxyURL: URL,
        clientKey: String,
        appName: String = "UnaMentis-iOS",
        refreshInterval: TimeInterval = 30.0,
        enableOfflineMode: Bool = true,
        enableMetrics: Bool = true
    ) {
        self.proxyURL = proxyURL
        self.clientKey = clientKey
        self.appName = appName
        self.refreshInterval = refreshInterval
        self.enableOfflineMode = enableOfflineMode
        self.enableMetrics = enableMetrics
    }

    /// Default development configuration
    public static var development: FeatureFlagConfig {
        FeatureFlagConfig(
            proxyURL: URL(string: "http://localhost:3063/proxy")!,
            clientKey: "proxy-client-key",
            appName: "UnaMentis-iOS-Dev"
        )
    }
}

// MARK: - Errors

/// Errors from the feature flag service
public enum FeatureFlagError: Error, LocalizedError, Sendable {
    case networkError(String)
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case cacheError(String)
    case notInitialized

    public var errorDescription: String? {
        switch self {
        case let .networkError(message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from feature flag server"
        case .unauthorized:
            return "Unauthorized: Invalid client key"
        case let .serverError(code):
            return "Server error: \(code)"
        case let .cacheError(message):
            return "Cache error: \(message)"
        case .notInitialized:
            return "Feature flag service not initialized"
        }
    }
}

// MARK: - Internal Types

/// Response from Unleash proxy
struct UnleashProxyResponse: Codable {
    let toggles: [UnleashToggle]
}

/// A single toggle from Unleash
struct UnleashToggle: Codable {
    let name: String
    let enabled: Bool
    let variant: UnleashVariant?
    let impressionData: Bool?
}

/// Variant from Unleash
struct UnleashVariant: Codable {
    let name: String
    let enabled: Bool
    let payload: UnleashPayload?
}

/// Payload from Unleash
struct UnleashPayload: Codable {
    let type: String
    let value: String
}

// MARK: - Metrics

/// Metrics for feature flag usage
public struct FeatureFlagMetrics: Sendable {
    public let totalEvaluations: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let lastRefreshTime: Date?
    public let flagCount: Int

    public var cacheHitRate: Double {
        guard totalEvaluations > 0 else { return 0 }
        return Double(cacheHits) / Double(totalEvaluations)
    }
}
