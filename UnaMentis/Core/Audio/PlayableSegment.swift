// UnaMentis - Playable Segment Protocol
// Abstraction over the unit of content that gets synthesized and played.
//
// Part of Core/Audio (shared audio playback infrastructure)

import Foundation

// MARK: - Cached Segment Audio

/// Pre-existing audio data for a segment, allowing the orchestrator
/// to skip TTS synthesis entirely and play with zero latency.
public struct CachedSegmentAudio: Sendable {
    /// Raw PCM audio bytes
    public let audioData: Data

    /// Sample rate of the audio (e.g., 24000)
    public let sampleRate: Double

    /// Number of audio channels (default: 1 for mono)
    public let channels: UInt32

    public init(audioData: Data, sampleRate: Double, channels: UInt32 = 1) {
        self.audioData = audioData
        self.sampleRate = sampleRate
        self.channels = channels
    }

    /// Convert to TTSAudioChunk for playback through the audio engine
    public func toTTSAudioChunk(sequenceNumber: Int = 0) -> TTSAudioChunk {
        TTSAudioChunk(
            audioData: audioData,
            format: .pcmFloat32(sampleRate: sampleRate, channels: channels),
            sequenceNumber: sequenceNumber,
            isFirst: true,
            isLast: true
        )
    }
}

// MARK: - Playable Segment Protocol

/// An abstraction over the unit of content that gets synthesized and played.
/// Each module provides its own conforming type.
///
/// Conforming types:
/// - `ReadingChunkData` (Reading List)
/// - `SessionSentenceSegment` (Voice Session)
/// - `KBTextSegment` (Knowledge Bowl)
public protocol PlayableSegment: Sendable {
    /// Zero-based position in the segment sequence
    var segmentIndex: Int { get }

    /// Text content to synthesize (ignored if cachedAudio exists)
    var segmentText: String { get }

    /// Pre-existing audio data. When present, the orchestrator skips TTS
    /// entirely and plays the cached audio with zero synthesis latency.
    var cachedAudio: CachedSegmentAudio? { get }
}
