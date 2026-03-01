// UnaMentis - Reading Playback Service
// Low-latency TTS playback for reading list items
//
// Part of Services/ReadingPlayback
//
// Architecture:
// - Delegates playback to AudioPlaybackOrchestrator (shared infrastructure)
// - Handles reading-specific concerns: position persistence, bookmarks, Core Data caching
// - Orchestrator handles: prefetch, inter-segment silence, pause/resume, playback loop

import Foundation
import AVFoundation
import Logging

// MARK: - Playback State

/// Current state of reading playback
public enum ReadingPlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case completed
    case error(String)
}

// MARK: - ReadingChunkData

/// Lightweight data transfer object for chunk info
public struct ReadingChunkData: Sendable {
    public let index: Int32
    public let text: String
    public let characterOffset: Int64
    public let estimatedDurationSeconds: Float

    /// Pre-generated PCM Float32 audio data (only for first chunk, if available)
    public let cachedAudioData: Data?
    /// Sample rate of cached audio (0 = no cached audio)
    public let cachedAudioSampleRate: Double

    public init(
        index: Int32,
        text: String,
        characterOffset: Int64,
        estimatedDurationSeconds: Float,
        cachedAudioData: Data? = nil,
        cachedAudioSampleRate: Double = 0
    ) {
        self.index = index
        self.text = text
        self.characterOffset = characterOffset
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.cachedAudioData = cachedAudioData
        self.cachedAudioSampleRate = cachedAudioSampleRate
    }

    /// Whether this chunk has pre-generated audio ready for instant playback
    public var hasCachedAudio: Bool {
        cachedAudioData != nil && cachedAudioSampleRate > 0
    }
}

// MARK: - PlayableSegment Conformance

extension ReadingChunkData: PlayableSegment {
    public var segmentIndex: Int { Int(index) }
    public var segmentText: String { text }
    public var cachedAudio: CachedSegmentAudio? {
        guard let data = cachedAudioData, cachedAudioSampleRate > 0 else { return nil }
        return CachedSegmentAudio(audioData: data, sampleRate: cachedAudioSampleRate)
    }
}

// MARK: - Playback Callbacks

/// Sendable callbacks for playback events (replaces delegate for actor safety)
public struct ReadingPlaybackCallbacks: Sendable {
    public let onStart: @Sendable @MainActor () -> Void
    public let onPause: @Sendable @MainActor () -> Void
    public let onResume: @Sendable @MainActor () -> Void
    public let onStop: @Sendable @MainActor () -> Void
    public let onComplete: @Sendable @MainActor () -> Void
    public let onBuffering: @Sendable @MainActor () -> Void
    public let onChunkChange: @Sendable @MainActor (Int32, Int) -> Void
    public let onError: @Sendable @MainActor (Error) -> Void

    public init(
        onStart: @escaping @Sendable @MainActor () -> Void = {},
        onPause: @escaping @Sendable @MainActor () -> Void = {},
        onResume: @escaping @Sendable @MainActor () -> Void = {},
        onStop: @escaping @Sendable @MainActor () -> Void = {},
        onComplete: @escaping @Sendable @MainActor () -> Void = {},
        onBuffering: @escaping @Sendable @MainActor () -> Void = {},
        onChunkChange: @escaping @Sendable @MainActor (Int32, Int) -> Void = { _, _ in },
        onError: @escaping @Sendable @MainActor (Error) -> Void = { _ in }
    ) {
        self.onStart = onStart
        self.onPause = onPause
        self.onResume = onResume
        self.onStop = onStop
        self.onComplete = onComplete
        self.onBuffering = onBuffering
        self.onChunkChange = onChunkChange
        self.onError = onError
    }
}

// MARK: - Reading Playback Service

/// Service for playing reading list content with low-latency TTS
///
/// Key Features:
/// - Delegates playback to AudioPlaybackOrchestrator
/// - Auto-saves position via ReadingListManager
/// - Supports pause/resume/suspend for barge-in Q&A
/// - Inter-segment silence (600ms) via orchestrator config
public actor ReadingPlaybackService {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.reading.playback")

    /// Current playback state
    public private(set) var state: ReadingPlaybackState = .idle

    /// Current reading item (item ID for safety across actor boundaries)
    private var currentItemId: UUID?

    /// All chunks for current item
    private var chunks: [ReadingChunkData] = []

    /// Current chunk index being played
    public private(set) var currentChunkIndex: Int32 = 0

    /// Total number of chunks
    public var totalChunks: Int { chunks.count }

    /// The orchestrator that handles the actual playback loop
    private var orchestrator: AudioPlaybackOrchestrator?

    /// Reading list manager for position updates
    private var readingListManager: ReadingListManager?

    /// Callbacks for UI updates
    private var callbacks: ReadingPlaybackCallbacks?

    /// Observation task for orchestrator state
    private var stateObservationTask: Task<Void, Never>?

    // MARK: - Initialization

    public init() { }

    /// Configure the service with required dependencies
    public func configure(
        ttsService: any TTSService,
        audioEngine: AudioEngine,
        readingListManager: ReadingListManager,
        callbacks: ReadingPlaybackCallbacks = ReadingPlaybackCallbacks()
    ) {
        self.readingListManager = readingListManager
        self.callbacks = callbacks

        // Create orchestrator with reading list config (600ms silence, 5-deep prefetch, 6 retained)
        let orch = AudioPlaybackOrchestrator(
            config: .readingList,
            ttsService: ttsService,
            audioEngine: audioEngine
        )
        self.orchestrator = orch

        logger.info("ReadingPlaybackService configured with orchestrator")
    }

    // MARK: - Playback Control

    /// Start playing a reading item from the beginning or last position
    public func startPlayback(
        itemId: UUID,
        chunks: [ReadingChunkData],
        startIndex: Int32 = 0
    ) async throws {
        guard let orchestrator else {
            throw ReadingPlaybackError.notConfigured
        }

        guard !chunks.isEmpty else {
            throw ReadingPlaybackError.noChunks
        }

        logger.info("Starting playback for item \(itemId), \(chunks.count) chunks, starting at \(startIndex)")

        // TTFA: mark activation for reading list playback
        await TTFAInstrumentation.shared.markActivation(.readingPlay)

        // Clean up any existing playback
        await stopPlaybackInternal(notifyCallback: false)

        // Set up new playback session
        self.currentItemId = itemId
        self.chunks = chunks
        self.currentChunkIndex = min(startIndex, Int32(chunks.count - 1))

        // Configure orchestrator delegate and load segments
        await orchestrator.loadSegments(chunks)
        let delegate = ReadingPlaybackOrchestratorDelegate(service: self)
        await orchestrator.setDelegate(delegate)

        // Start playback
        state = .playing
        if let cb = callbacks { await notify(cb.onStart) }
        await orchestrator.startPlayback(from: Int(currentChunkIndex))
    }

    /// Pause playback (for barge-in)
    public func pause() async {
        guard state == .playing, let orchestrator else { return }

        logger.debug("Pausing playback at chunk \(currentChunkIndex)")
        await orchestrator.pausePlayback()

        state = .paused
        await saveCurrentPosition()
        if let cb = callbacks { await notify(cb.onPause) }
    }

    /// Resume playback after pause
    public func resume() async {
        guard state == .paused, let orchestrator else { return }

        logger.debug("Resuming playback from chunk \(currentChunkIndex)")

        // TTFA: mark activation for resume
        await TTFAInstrumentation.shared.markActivation(.readingResume)

        await orchestrator.resumePlayback()
        state = .playing
        if let cb = callbacks { await notify(cb.onResume) }
    }

    /// Suspend playback preserving cached state.
    /// Use when view disappears but user may return quickly.
    public func suspendPlayback() async {
        guard state == .playing || state == .paused, let orchestrator else { return }

        logger.debug("Suspending playback at chunk \(currentChunkIndex)")
        await orchestrator.suspendPlayback()
        await saveCurrentPosition()

        state = .paused
        if let cb = callbacks { await notify(cb.onPause) }
    }

    /// Stop playback completely
    public func stopPlayback() async {
        await stopPlaybackInternal(notifyCallback: true)
    }

    private func stopPlaybackInternal(notifyCallback: Bool) async {
        guard state != .idle else { return }

        logger.debug("Stopping playback")

        if let orchestrator {
            await orchestrator.stopPlayback()
        }

        // Save position
        await saveCurrentPosition()

        // Clean up
        currentItemId = nil
        chunks.removeAll()
        state = .idle

        if notifyCallback, let cb = callbacks { await notify(cb.onStop) }
    }

    /// Update chunks with fresh data (e.g. after Core Data refresh for pre-gen audio)
    public func updateChunks(_ newChunks: [ReadingChunkData]) async {
        self.chunks = newChunks
        if let orchestrator {
            await orchestrator.loadSegments(newChunks)
        }
    }

    /// Skip to a specific chunk
    public func skipToChunk(_ index: Int32) async throws {
        guard index >= 0 && index < Int32(chunks.count) else {
            throw ReadingPlaybackError.invalidChunkIndex
        }
        guard let orchestrator else { throw ReadingPlaybackError.notConfigured }

        logger.debug("Skipping to chunk \(index)")
        currentChunkIndex = index

        await orchestrator.skipToSegment(Int(index))

        if state == .paused {
            state = .playing
        }

        let total = chunks.count
        if let cb = callbacks {
            let idx = index
            await MainActor.run { cb.onChunkChange(idx, total) }
        }
    }

    /// Skip forward by N chunks
    public func skipForward(chunks count: Int = 1) async throws {
        let newIndex = min(currentChunkIndex + Int32(count), Int32(self.chunks.count - 1))
        try await skipToChunk(newIndex)
    }

    /// Skip backward by N chunks
    public func skipBackward(chunks count: Int = 1) async throws {
        let newIndex = max(currentChunkIndex - Int32(count), 0)
        try await skipToChunk(newIndex)
    }

    // MARK: - Orchestrator Event Handling (called by delegate)

    /// Called by orchestrator delegate when segment changes
    func handleSegmentChange(index: Int, total: Int) async {
        currentChunkIndex = Int32(index)
        if let cb = callbacks {
            let idx = Int32(index)
            await MainActor.run { cb.onChunkChange(idx, total) }
        }
    }

    /// Called by orchestrator delegate when segment finishes
    func handleSegmentFinished(at index: Int) async {
        await saveCurrentPosition()

        // Persist synthesized audio to Core Data for cross-session caching
        // (The orchestrator handles synthesis; we just need to save the result)
    }

    /// Called by orchestrator delegate when all segments complete
    func handlePlaybackComplete() async {
        state = .completed
        await saveCurrentPosition()
        if let cb = callbacks { await notify(cb.onComplete) }
    }

    /// Called by orchestrator delegate on error
    func handleError(_ error: Error) async {
        state = .error(error.localizedDescription)
        if let cb = callbacks {
            let errMsg = error.localizedDescription
            await MainActor.run {
                cb.onError(ReadingPlaybackError.playbackFailed(errMsg))
            }
        }
    }

    // MARK: - Position Management

    /// Save current playback position
    private func saveCurrentPosition() async {
        guard let itemId = currentItemId, let manager = readingListManager else { return }

        let chunkIdx = currentChunkIndex
        do {
            try await MainActor.run {
                try manager.updatePositionById(itemId: itemId, chunkIndex: chunkIdx)
            }
            logger.debug("Saved position: chunk \(chunkIdx)")
        } catch {
            logger.error("Failed to save position: \(error.localizedDescription)")
        }
    }

    // MARK: - Callback Notification

    /// Invoke a callback on the main actor
    private func notify(_ callback: @escaping @Sendable @MainActor () -> Void) async {
        await MainActor.run { callback() }
    }

    // MARK: - Bookmarks

    /// Add a bookmark at the current position
    public func addBookmark(note: String? = nil) async throws {
        guard let itemId = currentItemId, let manager = readingListManager else {
            throw ReadingPlaybackError.notConfigured
        }

        let chunkIdx = currentChunkIndex
        _ = try await MainActor.run {
            try manager.addBookmarkById(itemId: itemId, chunkIndex: chunkIdx, note: note)
        }
        logger.info("Added bookmark at chunk \(chunkIdx)")
    }

    /// Jump to a bookmark position
    public func jumpToBookmark(_ bookmark: ReadingBookmarkData) async throws {
        try await skipToChunk(bookmark.chunkIndex)
    }
}

// MARK: - Orchestrator Delegate (reading-specific hooks)

/// Bridge between the generic orchestrator delegate and the reading playback service.
/// Handles position persistence and UI notifications specific to reading.
private final class ReadingPlaybackOrchestratorDelegate: PlaybackOrchestratorDelegate, @unchecked Sendable {
    private weak var service: ReadingPlaybackService?

    init(service: ReadingPlaybackService) {
        self.service = service
    }

    func orchestratorDidChangeSegment(index: Int, total: Int) async {
        await service?.handleSegmentChange(index: index, total: total)
    }

    func orchestratorDidFinishSegment(at index: Int) async {
        await service?.handleSegmentFinished(at: index)
    }

    func orchestratorDidComplete() async {
        await service?.handlePlaybackComplete()
    }

    func orchestratorDidEncounterError(_ error: Error) async {
        await service?.handleError(error)
    }
}

// MARK: - Bookmark Data Transfer Object

/// Lightweight bookmark data for actor boundary crossing
public struct ReadingBookmarkData: Sendable {
    public let id: UUID
    public let chunkIndex: Int32
    public let note: String?

    public init(id: UUID, chunkIndex: Int32, note: String?) {
        self.id = id
        self.chunkIndex = chunkIndex
        self.note = note
    }
}

// MARK: - Errors

/// Errors specific to reading playback
public enum ReadingPlaybackError: Error, LocalizedError {
    case notConfigured
    case noChunks
    case invalidChunkIndex
    case bufferTimeout
    case playbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Reading playback service not configured"
        case .noChunks:
            return "No chunks available for playback"
        case .invalidChunkIndex:
            return "Invalid chunk index"
        case .bufferTimeout:
            return "Timed out waiting for audio buffer"
        case .playbackFailed(let message):
            return "Playback failed: \(message)"
        }
    }
}
