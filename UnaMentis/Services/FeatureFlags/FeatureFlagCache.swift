// UnaMentis - Feature Flag Cache
// Persistent offline caching for feature flags
//
// Part of Quality Infrastructure (Phase 3)

import Foundation
import Logging

/// Manages persistent caching of feature flags for offline support
public actor FeatureFlagCache {
    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.featureflags.cache")
    private let cacheDirectory: URL
    private let cacheFileName = "feature_flags_cache.json"
    private let maxCacheAge: TimeInterval

    private var inMemoryCache: [String: CachedFlag] = [:]
    private var lastLoadTime: Date?

    // MARK: - Types

    struct CachedFlag: Codable {
        let name: String
        let enabled: Bool
        let variant: FeatureFlagVariant?
        let cachedAt: Date
    }

    struct CacheFile: Codable {
        let version: Int
        let updatedAt: Date
        let flags: [String: CachedFlag]
    }

    // MARK: - Initialization

    public init(maxCacheAge: TimeInterval = 86400) { // 24 hours default
        self.maxCacheAge = maxCacheAge

        // Use app's caches directory
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cacheDirectory = paths[0].appendingPathComponent("FeatureFlags", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        logger.info("FeatureFlagCache initialized at \(cacheDirectory.path)")
    }

    // MARK: - Public Methods

    /// Load flags from persistent cache
    public func load() async throws {
        let cacheFile = cacheDirectory.appendingPathComponent(cacheFileName)

        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            logger.debug("No cache file found")
            return
        }

        do {
            let data = try Data(contentsOf: cacheFile)
            let cache = try JSONDecoder().decode(CacheFile.self, from: data)

            // Check if cache is still valid
            let cacheAge = Date().timeIntervalSince(cache.updatedAt)
            if cacheAge > maxCacheAge {
                logger.info("Cache expired (age: \(Int(cacheAge))s), clearing")
                try? FileManager.default.removeItem(at: cacheFile)
                return
            }

            inMemoryCache = cache.flags
            lastLoadTime = Date()

            logger.info("Loaded \(cache.flags.count) flags from cache (age: \(Int(cacheAge))s)")
        } catch {
            logger.error("Failed to load cache: \(error.localizedDescription)")
            throw FeatureFlagError.cacheError("Failed to load: \(error.localizedDescription)")
        }
    }

    /// Save flags to persistent cache
    public func save(flags: [String: (enabled: Bool, variant: FeatureFlagVariant?)]) async throws {
        let now = Date()

        // Update in-memory cache
        for (name, value) in flags {
            inMemoryCache[name] = CachedFlag(
                name: name,
                enabled: value.enabled,
                variant: value.variant,
                cachedAt: now
            )
        }

        // Persist to disk
        let cacheFile = CacheFile(
            version: 1,
            updatedAt: now,
            flags: inMemoryCache
        )

        do {
            let data = try JSONEncoder().encode(cacheFile)
            let cacheURL = cacheDirectory.appendingPathComponent(cacheFileName)
            try data.write(to: cacheURL, options: .atomic)

            logger.debug("Saved \(flags.count) flags to cache")
        } catch {
            logger.error("Failed to save cache: \(error.localizedDescription)")
            throw FeatureFlagError.cacheError("Failed to save: \(error.localizedDescription)")
        }
    }

    /// Get a cached flag value
    public func get(_ flagName: String) -> (enabled: Bool, variant: FeatureFlagVariant?)? {
        guard let cached = inMemoryCache[flagName] else {
            return nil
        }

        // Check if this specific flag is expired
        let age = Date().timeIntervalSince(cached.cachedAt)
        if age > maxCacheAge {
            return nil
        }

        return (cached.enabled, cached.variant)
    }

    /// Check if we have a valid cache
    public var hasValidCache: Bool {
        !inMemoryCache.isEmpty
    }

    /// Get cache statistics
    public var statistics: (count: Int, oldestAge: TimeInterval?) {
        guard !inMemoryCache.isEmpty else {
            return (0, nil)
        }

        let oldest = inMemoryCache.values.map(\.cachedAt).min()
        let age = oldest.map { Date().timeIntervalSince($0) }

        return (inMemoryCache.count, age)
    }

    /// Clear all cached flags
    public func clear() async throws {
        inMemoryCache.removeAll()

        let cacheFile = cacheDirectory.appendingPathComponent(cacheFileName)
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            try FileManager.default.removeItem(at: cacheFile)
        }

        logger.info("Cache cleared")
    }

    /// Get all cached flag names
    public var cachedFlagNames: [String] {
        Array(inMemoryCache.keys)
    }
}
