// UnaMentis - Reading TTS Cache (Deprecated Wrapper)
// Now delegates to the shared AudioTTSCache in Core/Audio.
//
// This file exists for backward compatibility. New code should
// use AudioTTSCache.shared directly.
//
// Part of Services/ReadingPlayback

import Foundation

// MARK: - Reading TTS Cache (Deprecated)

/// Thin wrapper that delegates to AudioTTSCache.
/// Kept for backward compatibility; prefer `AudioTTSCache.shared` in new code.
public actor ReadingTTSCache {

    /// Shared singleton instance
    public static let shared = ReadingTTSCache()

    private init() {}

    /// Get or create a TTS service, keeping it warm between sessions.
    public func getService() async -> any TTSService {
        await AudioTTSCache.shared.getService()
    }

    /// Schedule deferred release of the TTS service.
    public func scheduleRelease() async {
        await AudioTTSCache.shared.scheduleRelease()
    }
}
