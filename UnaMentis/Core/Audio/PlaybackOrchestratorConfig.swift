// UnaMentis - Playback Orchestrator Configuration
// Controls how the AudioPlaybackOrchestrator behaves per module.
//
// Part of Core/Audio (shared audio playback infrastructure)

import Foundation

// MARK: - Playback Orchestrator Config

/// Configuration for the AudioPlaybackOrchestrator.
/// Modules select a preset or provide custom values.
public struct PlaybackOrchestratorConfig: Sendable {
    /// Number of segments to synthesize ahead of the current one
    public let prefetchDepth: Int

    /// Milliseconds of silence inserted between segments
    public let interSegmentSilenceMs: Int

    /// Number of played segments to keep in memory for skip-back
    public let retainBehindCount: Int

    /// Max wait time for a prefetch to complete before falling back to direct synthesis
    public let bufferTimeoutSeconds: TimeInterval

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
}

// MARK: - Config Presets

extension PlaybackOrchestratorConfig {
    /// General purpose preset
    public static let `default` = PlaybackOrchestratorConfig(
        prefetchDepth: 3,
        interSegmentSilenceMs: 0,
        retainBehindCount: 0,
        bufferTimeoutSeconds: 10
    )

    /// Long-form reading with natural pacing
    public static let readingList = PlaybackOrchestratorConfig(
        prefetchDepth: 5,
        interSegmentSilenceMs: 600,
        retainBehindCount: 6,
        bufferTimeoutSeconds: 10
    )

    /// Conversational voice sessions, low-latency
    public static let session = PlaybackOrchestratorConfig(
        prefetchDepth: 2,
        interSegmentSilenceMs: 0,
        retainBehindCount: 0,
        bufferTimeoutSeconds: 15
    )

    /// Single question/answer, fire-and-forget
    public static let knowledgeBowl = PlaybackOrchestratorConfig(
        prefetchDepth: 0,
        interSegmentSilenceMs: 0,
        retainBehindCount: 0,
        bufferTimeoutSeconds: 10
    )
}
