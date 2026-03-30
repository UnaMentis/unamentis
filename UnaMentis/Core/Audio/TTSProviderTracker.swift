// UnaMentis - TTS Provider Tracker
// Tracks which TTS provider is actually active vs. what was requested.
// Logs at .error level if a fallback to Apple TTS is detected, since
// Pocket TTS ships bundled and should always be available.
//
// Part of Core/Audio

import Foundation
import OSLog

/// Tracks TTS provider state for diagnostics and fallback detection.
///
/// Pocket TTS ships bundled with every build and should ALWAYS initialize
/// successfully. A fallback to Apple TTS indicates a bug, not normal operation.
@MainActor @Observable
public final class TTSProviderTracker {
    public static let shared = TTSProviderTracker()

    private static let logger = Logger(
        subsystem: "com.unamentis.audio",
        category: "TTSProviderTracker"
    )

    /// The provider the user configured (or the default)
    public private(set) var requestedProvider: String = "pocketTTS"

    /// The provider actually in use
    public private(set) var activeProvider: String = "pocketTTS"

    /// Why the fallback occurred (nil if no fallback)
    public private(set) var fallbackReason: String?

    /// Whether the active provider differs from the requested one in a degraded way
    public var isFallback: Bool {
        // A fallback means we're using Apple TTS when we shouldn't be
        activeProvider == "appleTTS" && requestedProvider != "appleTTS"
    }

    private init() {}

    /// Record that a TTS provider was successfully activated as requested
    public func recordProviderActive(requested: String, active: String) {
        self.requestedProvider = requested
        self.activeProvider = active
        self.fallbackReason = nil

        if requested == active {
            Self.logger.info("TTS provider active: \(active)")
        } else if active == "pocketTTS" {
            // Falling back to Pocket TTS from a cloud/server provider is acceptable
            Self.logger.info("TTS provider: requested \(requested), using Pocket TTS (on-device fallback)")
        } else {
            Self.logger.info("TTS provider: requested \(requested), using \(active)")
        }
    }

    /// Record a degraded fallback to Apple TTS. This is always a bug
    /// since Pocket TTS is bundled and should be available.
    public func recordFallbackToAppleTTS(requested: String, reason: String) {
        self.requestedProvider = requested
        self.activeProvider = "appleTTS"
        self.fallbackReason = reason

        Self.logger.error(
            "TTS FALLBACK BUG: Requested \(requested) but fell back to Apple TTS. Reason: \(reason). Pocket TTS is bundled and should always be available."
        )
    }
}
