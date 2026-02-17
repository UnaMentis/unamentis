// UnaMentis - Playable Segment Protocol
// Abstraction for audio segments that can be played by the orchestrator
//
// Each module provides its own conforming type (ReadingChunkData,
// sentence wrappers, KBQuestion adapters) while the orchestrator
// handles the common playback logic.
//
// Part of Core/Audio

import Foundation

// MARK: - Cached Segment Audio

/// Pre-generated or previously synthesized audio data for a segment.
/// Enables instant playback (0ms latency) by bypassing TTS synthesis.
public struct CachedSegmentAudio: Sendable {
    /// Raw PCM audio data
    public let audioData: Data

    /// Sample rate of the audio (e.g. 24000 for Pocket TTS)
    public let sampleRate: Double

    /// Number of audio channels (typically 1 for mono TTS output)
    public let channels: UInt32

    public init(audioData: Data, sampleRate: Double, channels: UInt32 = 1) {
        self.audioData = audioData
        self.sampleRate = sampleRate
        self.channels = channels
    }

    /// Convert to a TTSAudioChunk for playback via AudioEngine
    public func toTTSAudioChunk() -> TTSAudioChunk {
        TTSAudioChunk(
            audioData: audioData,
            format: .pcmFloat32(sampleRate: sampleRate, channels: channels),
            sequenceNumber: 0,
            isFirst: true,
            isLast: true
        )
    }
}

// MARK: - Playable Segment Protocol

/// A segment of content that can be played by AudioPlaybackOrchestrator.
///
/// Each module provides its own conforming type:
/// - Reading List: `ReadingChunkData` (text chunks with optional cached audio)
/// - Session: Sentence wrapper (text from LLM streaming)
/// - Knowledge Bowl: Question/feedback adapter (with server cached audio)
public protocol PlayableSegment: Sendable {
    /// Position index in the playback sequence
    var segmentIndex: Int { get }

    /// Text content to synthesize if no cached audio is available
    var segmentText: String { get }

    /// Pre-generated or previously cached audio, if available.
    /// When non-nil, the orchestrator plays this instantly without TTS synthesis.
    var cachedAudio: CachedSegmentAudio? { get }
}
