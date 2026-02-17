// UnaMentis - Audio TTS Cache
// Keeps the TTS model loaded between sessions to avoid cold starts.
//
// Part of Core/Audio (shared audio playback infrastructure)
//
// On-device models have significant cold-start times (1-2 seconds
// for model loading). This cache keeps the service alive between
// module navigations with a configurable inactivity timeout.

import Foundation
import Logging

// MARK: - Audio TTS Cache

/// Singleton cache that keeps the TTS service warm between module navigations.
///
/// Behavior:
/// - Returns the cached TTS service or creates a new one
/// - Deferred release with configurable timeout (default: 2 minutes)
/// - Uses TTSProvider.resolveConfiguredService() to respect user's provider choice
public actor AudioTTSCache {
    /// Shared singleton instance
    public static let shared = AudioTTSCache()

    private let logger = Logger(label: "com.unamentis.audio.ttscache")

    /// The cached TTS service (nil when cold)
    private var cachedService: (any TTSService)?

    /// Timer task for deferred teardown
    private var releaseTask: Task<Void, Never>?

    private init() {}

    /// Get the cached TTS service, or create a new one using the user's
    /// configured provider preference.
    /// Cancels any pending release timer.
    public func getService() -> any TTSService {
        releaseTask?.cancel()
        releaseTask = nil

        if let service = cachedService {
            logger.debug("Returning warm TTS service from cache")
            return service
        }

        let service = TTSProvider.resolveConfiguredService()
        cachedService = service
        logger.info("Created new TTS service via provider resolution")
        return service
    }

    /// Schedule deferred release of the cached TTS service.
    /// If no module reclaims it within the timeout, it is released.
    public func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            await self?.releaseNow()
        }
        logger.debug("Scheduled deferred TTS service release")
    }

    /// Immediately release the cached TTS service.
    public func releaseNow() {
        releaseTask?.cancel()
        releaseTask = nil
        cachedService = nil
        logger.info("TTS service released from cache")
    }
}
