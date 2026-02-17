// UnaMentis - Audio Engine Cache
// Keeps the platform audio engine warm between navigations.
//
// Part of Core/Audio (shared audio playback infrastructure)
//
// Without this cache, every screen transition tears down and rebuilds
// the audio engine (1-2 second cold start). The cache returns a warm
// engine instance if available, or nil if not.

import Foundation
import Logging

// MARK: - Audio Engine Cache

/// Singleton cache that keeps the AudioEngine warm between module navigations.
///
/// Behavior:
/// - Returns a warm engine instance if available, nil if not
/// - Starts a configurable inactivity timer on release
/// - If no module reclaims the engine within the timeout, tears it down
public actor AudioEngineCache {
    /// Shared singleton instance
    public static let shared = AudioEngineCache()

    private let logger = Logger(label: "com.unamentis.audio.enginecache")

    /// The cached engine (nil when cold)
    private var cachedEngine: AudioEngine?

    /// Timeout before tearing down an unclaimed engine (default: 2 minutes)
    private let inactivityTimeout: TimeInterval = 120

    /// Timer task for deferred teardown
    private var releaseTask: Task<Void, Never>?

    private init() {}

    /// Get the cached engine, or nil if no warm engine is available.
    /// Cancels any pending release timer.
    public func getEngine() -> AudioEngine? {
        releaseTask?.cancel()
        releaseTask = nil

        if let engine = cachedEngine {
            logger.debug("Returning warm AudioEngine from cache")
            return engine
        }

        logger.debug("No cached AudioEngine available")
        return nil
    }

    /// Store an engine in the cache for reuse by the next module.
    public func store(_ engine: AudioEngine) {
        releaseTask?.cancel()
        releaseTask = nil
        cachedEngine = engine
        logger.debug("AudioEngine stored in cache")
    }

    /// Schedule deferred release of the cached engine.
    /// If no module reclaims it within `inactivityTimeout`, it is torn down.
    public func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            await self?.releaseNow()
        }
        logger.debug("Scheduled deferred AudioEngine release")
    }

    /// Immediately release the cached engine.
    public func releaseNow() {
        releaseTask?.cancel()
        releaseTask = nil

        if let engine = cachedEngine {
            Task { await engine.stop() }
            cachedEngine = nil
            logger.info("AudioEngine released from cache")
        }
    }
}
