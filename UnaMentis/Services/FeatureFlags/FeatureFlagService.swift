// UnaMentis - Feature Flag Service
// Unleash proxy client with offline caching and analytics
//
// Part of Quality Infrastructure (Phase 3)

import Foundation
import Logging

/// Feature flag service using Unleash proxy with offline support
public actor FeatureFlagService: FeatureFlagEvaluating {
    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.featureflags")
    private let config: FeatureFlagConfig
    private let cache: FeatureFlagCache

    private var flags: [String: (enabled: Bool, variant: FeatureFlagVariant?)] = [:]
    private var isInitialized = false
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshTime: Date?

    // Metrics
    private var totalEvaluations = 0
    private var cacheHits = 0
    private var cacheMisses = 0

    // MARK: - Singleton

    /// Shared instance (must be configured before use)
    public static let shared = FeatureFlagService()

    // MARK: - Initialization

    /// Initialize with custom configuration
    ///
    /// - Note: When using a custom config with this initializer, be aware that
    ///   `.shared` always uses `.development` config. If you need a custom config
    ///   throughout your app, use dependency injection instead of the singleton.
    public init(config: FeatureFlagConfig = .development) {
        self.config = config
        self.cache = FeatureFlagCache()
        logger.info("FeatureFlagService created with proxy: \(config.proxyURL.absoluteString)")
    }

    /// Start the service and begin polling
    public func start() async throws {
        guard !isInitialized else {
            logger.warning("FeatureFlagService already started")
            return
        }

        logger.info("Starting FeatureFlagService...")

        // Load from cache first for immediate availability
        if config.enableOfflineMode {
            do {
                try await cache.load()
                let stats = await cache.statistics
                if stats.count > 0 {
                    logger.info("Loaded \(stats.count) flags from cache")
                    // Populate from cache
                    for name in await cache.cachedFlagNames {
                        if let cached = await cache.get(name) {
                            flags[name] = cached
                        }
                    }
                }
            } catch {
                logger.warning("Failed to load cache: \(error.localizedDescription)")
            }
        }

        // Fetch fresh flags from server
        do {
            try await fetchFlags()
        } catch {
            logger.warning("Initial fetch failed: \(error.localizedDescription)")
            // Continue if we have cached data
            if flags.isEmpty {
                throw error
            }
        }

        isInitialized = true

        // Start background refresh
        startRefreshLoop()

        logger.info("FeatureFlagService started with \(flags.count) flags")
    }

    /// Stop the service
    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        isInitialized = false
        logger.info("FeatureFlagService stopped")
    }

    // MARK: - FeatureFlagEvaluating Protocol

    public func isEnabled(_ flagName: String) async -> Bool {
        await isEnabled(flagName, context: .current())
    }

    public func isEnabled(_ flagName: String, context: FeatureFlagContext) async -> Bool {
        totalEvaluations += 1

        // Check in-memory flags first
        if let flag = flags[flagName] {
            cacheHits += 1
            logger.debug("Flag '\(flagName)' = \(flag.enabled) (memory)")
            return flag.enabled
        }

        // Check persistent cache
        if config.enableOfflineMode, let cached = await cache.get(flagName) {
            cacheHits += 1
            logger.debug("Flag '\(flagName)' = \(cached.enabled) (cache)")
            return cached.enabled
        }

        cacheMisses += 1
        logger.debug("Flag '\(flagName)' not found, defaulting to false")
        return false
    }

    public func getVariant(_ flagName: String) async -> FeatureFlagVariant? {
        await getVariant(flagName, context: .current())
    }

    public func getVariant(_ flagName: String, context: FeatureFlagContext) async -> FeatureFlagVariant? {
        totalEvaluations += 1

        // Check in-memory flags first
        if let flag = flags[flagName] {
            cacheHits += 1
            return flag.variant
        }

        // Check persistent cache
        if config.enableOfflineMode, let cached = await cache.get(flagName) {
            cacheHits += 1
            return cached.variant
        }

        cacheMisses += 1
        return nil
    }

    public func refresh() async throws {
        try await fetchFlags()
    }

    // MARK: - Convenience Methods

    /// Check multiple flags at once
    public func areEnabled(_ flagNames: [String]) async -> [String: Bool] {
        var results: [String: Bool] = [:]
        for name in flagNames {
            results[name] = await isEnabled(name)
        }
        return results
    }

    /// Get current metrics
    public func getMetrics() -> FeatureFlagMetrics {
        FeatureFlagMetrics(
            totalEvaluations: totalEvaluations,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            lastRefreshTime: lastRefreshTime,
            flagCount: flags.count
        )
    }

    /// Get all flag names
    public var flagNames: [String] {
        Array(flags.keys)
    }

    // MARK: - Private Methods

    private func fetchFlags() async throws {
        var components = URLComponents(url: config.proxyURL, resolvingAgainstBaseURL: false)
        // Add context as query parameters
        components?.queryItems = [
            URLQueryItem(name: "appName", value: config.appName),
        ]

        guard let url = components?.url else {
            throw FeatureFlagError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.clientKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        logger.debug("Fetching flags from \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FeatureFlagError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                break
            case 401, 403:
                throw FeatureFlagError.unauthorized
            default:
                throw FeatureFlagError.serverError(httpResponse.statusCode)
            }

            let proxyResponse = try JSONDecoder().decode(UnleashProxyResponse.self, from: data)

            // Update flags
            var newFlags: [String: (enabled: Bool, variant: FeatureFlagVariant?)] = [:]
            for toggle in proxyResponse.toggles {
                let variant = toggle.variant.map { v in
                    FeatureFlagVariant(
                        name: v.name,
                        enabled: v.enabled,
                        payload: parsePayload(v.payload)
                    )
                }
                newFlags[toggle.name] = (toggle.enabled, variant)
            }

            flags = newFlags
            lastRefreshTime = Date()

            // Persist to cache
            if config.enableOfflineMode {
                do {
                    try await cache.save(flags: flags)
                } catch {
                    logger.warning("Failed to save flags to cache: \(error.localizedDescription)")
                }
            }

            logger.info("Fetched \(proxyResponse.toggles.count) flags")

        } catch let error as FeatureFlagError {
            throw error
        } catch {
            throw FeatureFlagError.networkError(error.localizedDescription)
        }
    }

    private func parsePayload(_ payload: UnleashPayload?) -> FeatureFlagPayload? {
        guard let payload else { return nil }

        switch payload.type {
        case "string":
            return .string(payload.value)
        case "number":
            if let number = Double(payload.value) {
                return .number(number)
            }
            return .string(payload.value)
        case "json":
            if let data = payload.value.data(using: .utf8),
               let json = try? JSONDecoder().decode([String: String].self, from: data) {
                return .json(json)
            }
            return .string(payload.value)
        default:
            return .string(payload.value)
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()

        // Note: Actors cannot be weakly referenced in Swift 6, so we don't use [weak self]
        // The task is cancelled in stop() which handles cleanup appropriately
        refreshTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(config.refreshInterval * 1_000_000_000))

                    if !Task.isCancelled {
                        do {
                            try await fetchFlags()
                        } catch {
                            await logRefreshError(error)
                        }
                    }
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
    }

    private func logRefreshError(_ error: Error) {
        logger.warning("Background refresh failed: \(error.localizedDescription)")
    }
}

// MARK: - SwiftUI Support

#if canImport(SwiftUI)
    import SwiftUI

    /// Environment key for feature flag service
    private struct FeatureFlagServiceKey: EnvironmentKey {
        static let defaultValue: FeatureFlagService = .shared
    }

    public extension EnvironmentValues {
        var featureFlags: FeatureFlagService {
            get { self[FeatureFlagServiceKey.self] }
            set { self[FeatureFlagServiceKey.self] = newValue }
        }
    }

    /// View modifier for conditional rendering based on feature flag
    public struct FeatureFlagViewModifier: ViewModifier {
        let flagName: String
        @Environment(\.featureFlags) private var featureFlags
        @State private var isEnabled = false

        public func body(content: Content) -> some View {
            Group {
                if isEnabled {
                    content
                }
            }
            .task {
                isEnabled = await featureFlags.isEnabled(flagName)
            }
        }
    }

    public extension View {
        /// Only show this view if the feature flag is enabled
        func featureFlag(_ flagName: String) -> some View {
            modifier(FeatureFlagViewModifier(flagName: flagName))
        }
    }
#endif
