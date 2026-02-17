// UnaMentis - Audio Engine Cache
// Keeps AudioEngine warm between view transitions for instant resume
//
// When a user navigates away from a reading/playback view and returns,
// the AudioEngine normally needs reconfiguration (~200-500ms). This
// cache keeps a configured, running AudioEngine available for a timeout
// period, eliminating the delay on quick re-entry.
//
// Part of Core/Audio

import Foundation
import Logging

// MARK: - Audio Engine Cache

/// Singleton actor that caches a configured AudioEngine between view transitions.
///
/// The cached engine is released after an inactivity timeout to free
/// resources when the user isn't actively in a playback view.
public actor AudioEngineCache {

    /// Shared singleton instance
    public static let shared = AudioEngineCache()

    private let logger = Logger(label: "com.unamentis.audio.engine.cache")

    /// Cached AudioEngine instance
    private var cachedEngine: AudioEngine?

    /// Task that will release the engine after timeout
    private var releaseTask: Task<Void, Never>?

    /// How long to keep the engine warm after use
    private let inactivityTimeout: TimeInterval = 120 // 2 minutes

    private init() {}

    // MARK: - Public API

    /// Get or create a configured AudioEngine.
    ///
    /// Returns the cached engine if available, otherwise creates and
    /// configures a new one. The engine is started and ready for playback.
    public func getEngine() async -> AudioEngine? {
        releaseTask?.cancel()
        releaseTask = nil

        if let engine = cachedEngine {
            // Ensure it's still running
            let isRunning = await engine.isRunning
            if isRunning {
                logger.debug("Returning cached AudioEngine")
                return engine
            }
            // Engine stopped unexpectedly, recreate
            logger.info("Cached AudioEngine not running, recreating")
        }

        // Create new engine
        let engine = AudioEngine(
            vadService: SileroVADService(),
            telemetry: TelemetryEngine()
        )

        do {
            try await engine.configure(config: .default)
            try await engine.start()
            cachedEngine = engine
            logger.info("Created and cached new AudioEngine")
            return engine
        } catch {
            logger.error("Failed to create AudioEngine: \(error.localizedDescription)")
            return nil
        }
    }

    /// Schedule deferred release of the AudioEngine.
    ///
    /// Called when playback suspends or a view disappears. The engine
    /// stays warm for the timeout, then is stopped and released.
    public func scheduleRelease() {
        releaseTask?.cancel()
        let timeout = inactivityTimeout
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.clearCache()
        }
        logger.debug("Scheduled AudioEngine release in \(inactivityTimeout)s")
    }

    /// Immediately release the cached engine (for explicit cleanup).
    public func releaseNow() async {
        releaseTask?.cancel()
        releaseTask = nil
        await clearCache()
    }

    // MARK: - Private

    private func clearCache() async {
        if let engine = cachedEngine {
            await engine.stop()
            await engine.cleanup()
        }
        cachedEngine = nil
        releaseTask = nil
        logger.info("Released cached AudioEngine (inactivity timeout)")
    }
}
