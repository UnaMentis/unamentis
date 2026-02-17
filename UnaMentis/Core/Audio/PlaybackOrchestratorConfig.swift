// UnaMentis - Playback Orchestrator Configuration
// Tunable parameters for audio playback behavior per module
//
// Part of Core/Audio

import Foundation

// MARK: - Playback Orchestrator Configuration

/// Configuration for AudioPlaybackOrchestrator behavior.
///
/// Each module uses a different preset tuned to its playback pattern:
/// - Reading List: deep prefetch, inter-segment silence, retention for skip-back
/// - Session: shallow prefetch, no silence, dynamic segment append
/// - Knowledge Bowl: minimal prefetch, single segment at a time
public struct PlaybackOrchestratorConfig: Sendable {

    /// Number of segments to prefetch ahead of the current playback position.
    /// Higher values reduce buffering risk at the cost of memory.
    public var prefetchDepth: Int

    /// Milliseconds of silence to insert between segments.
    /// Creates natural pacing for reading content (600ms recommended).
    /// Set to 0 for conversation-like flow (sessions).
    public var interSegmentSilenceMs: Int

    /// Number of played segments to retain behind the current position.
    /// Enables instant skip-back without re-synthesis.
    /// Set to 0 for memory-constrained scenarios (sessions).
    public var retainBehindCount: Int

    /// Maximum seconds to wait for a segment's audio to become available
    /// before reporting a buffer timeout error.
    public var bufferTimeoutSeconds: TimeInterval

    public init(
        prefetchDepth: Int,
        interSegmentSilenceMs: Int,
        retainBehindCount: Int,
        bufferTimeoutSeconds: TimeInterval
    ) {
        self.prefetchDepth = prefetchDepth
        self.interSegmentSilenceMs = interSegmentSilenceMs
        self.retainBehindCount = retainBehindCount
        self.bufferTimeoutSeconds = bufferTimeoutSeconds
    }

    // MARK: - Presets

    /// Default configuration (conservative settings)
    public static let `default` = PlaybackOrchestratorConfig(
        prefetchDepth: 3,
        interSegmentSilenceMs: 0,
        retainBehindCount: 0,
        bufferTimeoutSeconds: 10
    )

    /// Reading list preset: deep prefetch, natural pacing, skip-back support
    public static let readingList = PlaybackOrchestratorConfig(
        prefetchDepth: 5,
        interSegmentSilenceMs: 600,
        retainBehindCount: 6,
        bufferTimeoutSeconds: 10
    )

    /// Session preset: shallow prefetch, no gaps, dynamic segment append
    public static let session = PlaybackOrchestratorConfig(
        prefetchDepth: 2,
        interSegmentSilenceMs: 0,
        retainBehindCount: 0,
        bufferTimeoutSeconds: 15
    )

    /// Knowledge Bowl preset: single segment, no prefetch, server cache
    public static let knowledgeBowl = PlaybackOrchestratorConfig(
        prefetchDepth: 0,
        interSegmentSilenceMs: 0,
        retainBehindCount: 0,
        bufferTimeoutSeconds: 10
    )
}
