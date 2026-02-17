// UnaMentis - Audio TTS Cache
// Caches the TTS service between playback sessions so the model stays warm
//
// When a user closes and reopens a playback view, the TTS model would
// normally need to reload (500-1000ms). This cache keeps it alive for
// a configurable timeout after the last session ends, eliminating the
// reload delay for quick re-entry.
//
// Shared across all modules (reading list, sessions, knowledge bowl).
//
// Part of Core/Audio

import Foundation
import Logging

// MARK: - Audio TTS Cache

/// Singleton actor that caches the TTS service between playback sessions.
///
/// Uses the same TTS provider resolution as the rest of the platform
/// (`TTSProvider.resolveConfiguredService()`), ensuring all modules
/// use consistent voice settings.
///
/// The cached service is released after an inactivity timeout to free
/// memory when the user isn't actively using audio features.
public actor AudioTTSCache {

    /// Shared singleton instance
    public static let shared = AudioTTSCache()

    private let logger = Logger(label: "com.unamentis.audio.tts.cache")

    /// Cached TTS service instance
    private var cachedService: (any TTSService)?

    /// Task that will release the service after timeout
    private var releaseTask: Task<Void, Never>?

    /// How long to keep the model warm after playback stops
    private let inactivityTimeout: TimeInterval = 120 // 2 minutes

    private init() {}

    // MARK: - Public API

    /// Get or create a TTS service, keeping it warm between sessions.
    ///
    /// Uses `TTSProvider.resolveConfiguredService()` for consistency
    /// with the rest of the platform (curriculum, Knowledge Bowl, etc.).
    public func getService() async -> any TTSService {
        releaseTask?.cancel()
        releaseTask = nil

        if let service = cachedService {
            logger.debug("Returning cached TTS service")
            return service
        }

        // Resolve on main actor since TTSProvider may access UserDefaults
        let service = await MainActor.run {
            TTSProvider.resolveConfiguredService()
        }
        cachedService = service
        logger.info("Created new TTS service for audio cache")
        return service
    }

    /// Schedule deferred release of the TTS service.
    ///
    /// Called when playback stops. The service stays warm for the
    /// inactivity timeout, then is released to free memory.
    public func scheduleRelease() {
        releaseTask?.cancel()
        let timeout = inactivityTimeout
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.clearCache()
        }
        logger.debug("Scheduled TTS cache release in \(inactivityTimeout)s")
    }

    /// Immediately release the cached service (for explicit cleanup).
    public func releaseNow() async {
        releaseTask?.cancel()
        releaseTask = nil
        clearCache()
    }

    // MARK: - Private

    private func clearCache() {
        cachedService = nil
        releaseTask = nil
        logger.info("Released cached TTS service (inactivity timeout)")
    }
}
