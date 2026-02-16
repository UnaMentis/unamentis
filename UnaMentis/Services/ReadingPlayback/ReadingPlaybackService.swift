// UnaMentis - Reading Playback Service
// Low-latency TTS playback for reading list items with pre-buffering
//
// Part of Services/ReadingPlayback
//
// Architecture:
// - Pre-generates audio for 2-3 chunks ahead while current chunk plays
// - Seamless transitions between chunks with no gaps
// - Auto-saves position on pause/stop
// - Supports barge-in via AudioEngine.pausePlayback()

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

// MARK: - Pre-buffered Chunk

/// A chunk with its pre-generated audio data
private struct PreBufferedChunk: Sendable {
    let chunk: ReadingChunkData
    let audioChunks: [TTSAudioChunk]
}

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
/// - Pre-buffers 2-3 chunks ahead for seamless playback
/// - Works with any TTSService (protocol-based)
/// - Auto-saves position via ReadingListManager
/// - Supports pause/resume for barge-in Q&A
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

    /// Pre-buffered audio ready for playback
    private var preBufferedChunks: [Int32: PreBufferedChunk] = [:]

    /// Number of chunks to pre-buffer ahead of current position
    private let preBufferCount: Int = 5

    /// Number of chunks to retain behind current position (FOV pattern)
    private let retainBehindCount: Int32 = 6

    /// TTS service for audio generation
    private var ttsService: (any TTSService)?

    /// Audio engine for playback
    private var audioEngine: AudioEngine?

    /// Reading list manager for position updates
    private var readingListManager: ReadingListManager?

    /// Callbacks for UI updates
    private var callbacks: ReadingPlaybackCallbacks?

    /// Task for pre-buffering
    private var preBufferTask: Task<Void, Never>?

    /// Task for playback loop
    private var playbackTask: Task<Void, Never>?

    /// Whether we're currently pre-buffering
    private var isPreBuffering = false

    // MARK: - Initialization

    public init() { }

    /// Configure the service with required dependencies
    public func configure(
        ttsService: any TTSService,
        audioEngine: AudioEngine,
        readingListManager: ReadingListManager,
        callbacks: ReadingPlaybackCallbacks = ReadingPlaybackCallbacks()
    ) {
        self.ttsService = ttsService
        self.audioEngine = audioEngine
        self.readingListManager = readingListManager
        self.callbacks = callbacks

        logger.info("ReadingPlaybackService configured")
    }

    // MARK: - Playback Control

    /// Start playing a reading item from the beginning or last position
    /// - Parameters:
    ///   - itemId: The reading item ID
    ///   - chunks: Pre-loaded chunk data from the item
    ///   - startIndex: Optional starting chunk index (defaults to 0)
    public func startPlayback(
        itemId: UUID,
        chunks: [ReadingChunkData],
        startIndex: Int32 = 0
    ) async throws {
        guard let ttsService, let audioEngine else {
            throw ReadingPlaybackError.notConfigured
        }

        guard !chunks.isEmpty else {
            throw ReadingPlaybackError.noChunks
        }

        logger.info("Starting playback for item \(itemId), \(chunks.count) chunks, starting at \(startIndex)")

        // TTFA: mark activation for reading list playback
        await TTFAInstrumentation.shared.markActivation(.readingPlay)

        // Clean up any existing playback
        await stopPlayback()

        // Set up new playback session
        self.currentItemId = itemId
        self.chunks = chunks
        self.currentChunkIndex = min(startIndex, Int32(chunks.count - 1))
        self.preBufferedChunks.removeAll()

        // Pre-buffer from the NEXT chunk while we stream the first one directly
        let nextIndex = currentChunkIndex + 1
        if nextIndex < Int32(chunks.count) {
            startPreBuffering(from: nextIndex)
        }

        // Check if first chunk has pre-generated audio (instant playback)
        let firstChunk = chunks[Int(currentChunkIndex)]
        let useCachedAudio = firstChunk.hasCachedAudio

        if useCachedAudio {
            logger.info("Using pre-generated audio for chunk \(currentChunkIndex) (instant start)")
        }

        // Stream first chunk directly for lowest time-to-first-audio.
        // If pre-generated audio exists, it plays instantly from cache.
        // Otherwise, streams from TTS as each segment arrives (~200ms TTFB).
        state = .playing
        if let cb = callbacks { await notify(cb.onStart) }
        startPlaybackLoop(streamFirstChunk: true, useCachedAudio: useCachedAudio)
    }

    /// Pause playback (for barge-in)
    public func pause() async {
        guard state == .playing else { return }

        logger.debug("Pausing playback at chunk \(currentChunkIndex)")

        // Pause audio
        if let audioEngine {
            _ = await audioEngine.pausePlayback()
        }

        state = .paused
        await saveCurrentPosition()
        if let cb = callbacks { await notify(cb.onPause) }
    }

    /// Resume playback after pause
    public func resume() async {
        guard state == .paused else { return }

        logger.debug("Resuming playback from chunk \(currentChunkIndex)")

        // TTFA: mark activation for resume (audio resumes from paused state)
        await TTFAInstrumentation.shared.markActivation(.readingResume)

        // Resume audio
        if let audioEngine {
            _ = await audioEngine.resumePlayback()
        }

        state = .playing
        if let cb = callbacks { await notify(cb.onResume) }

        // Continue playback loop if needed
        if playbackTask == nil {
            // Choose the best playback strategy for the current chunk:
            // 1. Pre-buffered in memory? Use normal path
            // 2. Cached audio from Core Data? Use cached path (instant)
            // 3. Neither? Stream directly for fastest TTFB
            if preBufferedChunks[currentChunkIndex] != nil {
                startPlaybackLoop()
            } else if Int(currentChunkIndex) < chunks.count,
                      chunks[Int(currentChunkIndex)].hasCachedAudio {
                startPlaybackLoop(useCachedAudio: true)
            } else {
                startPlaybackLoop(streamFirstChunk: true)
            }

            // Ensure pre-buffering is running ahead
            if !isPreBuffering {
                startPreBuffering(from: currentChunkIndex + 1)
            }
        }
    }

    /// Stop playback completely
    public func stopPlayback() async {
        guard state != .idle else { return }

        logger.debug("Stopping playback")

        // Cancel tasks
        preBufferTask?.cancel()
        preBufferTask = nil
        playbackTask?.cancel()
        playbackTask = nil

        // Stop audio
        if let audioEngine {
            await audioEngine.stopPlayback()
        }

        // Save position
        await saveCurrentPosition()

        // Clean up
        currentItemId = nil
        chunks.removeAll()
        preBufferedChunks.removeAll()
        state = .idle

        if let cb = callbacks { await notify(cb.onStop) }
    }

    /// Skip to a specific chunk
    public func skipToChunk(_ index: Int32) async throws {
        guard index >= 0 && index < Int32(chunks.count) else {
            throw ReadingPlaybackError.invalidChunkIndex
        }

        logger.debug("Skipping to chunk \(index)")

        // Stop current audio and cancel pending tasks
        playbackTask?.cancel()
        playbackTask = nil
        if let audioEngine {
            await audioEngine.stopPlayback()
        }

        // Update position
        currentChunkIndex = index

        // Clear pre-buffer and start fresh from next position
        preBufferedChunks.removeAll()
        preBufferTask?.cancel()
        let nextIndex = index + 1
        if nextIndex < Int32(chunks.count) {
            startPreBuffering(from: nextIndex)
        }

        // Stream the target chunk directly for immediate playback
        if state == .playing || state == .paused {
            state = .playing
            startPlaybackLoop(streamFirstChunk: true)
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

    // MARK: - Pre-buffering

    /// Start pre-buffering chunks ahead of the given index
    private func startPreBuffering(from startIndex: Int32) {
        preBufferTask?.cancel()

        preBufferTask = Task { [weak self] in
            guard let self else { return }

            await self.runPreBufferLoop(from: startIndex)
        }
    }

    /// Run the pre-buffer loop
    private func runPreBufferLoop(from startIndex: Int32) async {
        guard let ttsService else { return }

        isPreBuffering = true
        var nextIndexToBuffer = startIndex

        while !Task.isCancelled && nextIndexToBuffer < Int32(chunks.count) {
            // Only buffer up to preBufferCount chunks ahead of current playback
            let maxBufferIndex = currentChunkIndex + Int32(preBufferCount)

            if nextIndexToBuffer > maxBufferIndex {
                // Wait a bit before checking again
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }

            // Skip if already buffered
            if preBufferedChunks[nextIndexToBuffer] != nil {
                nextIndexToBuffer += 1
                continue
            }

            // Buffer this chunk
            let chunkIndex = nextIndexToBuffer
            guard Int(chunkIndex) < chunks.count else { break }

            let chunk = chunks[Int(chunkIndex)]

            // Check if this chunk already has cached audio from import-time
            // pre-generation. If so, use it directly (instant, no TTS needed).
            if chunk.hasCachedAudio, let audioData = chunk.cachedAudioData {
                logger.debug("Using cached audio for pre-buffer chunk \(chunkIndex)")
                let ttsChunk = TTSAudioChunk(
                    audioData: audioData,
                    format: .pcmFloat32(sampleRate: chunk.cachedAudioSampleRate, channels: 1),
                    sequenceNumber: 0,
                    isFirst: true,
                    isLast: true
                )
                let preBuffered = PreBufferedChunk(chunk: chunk, audioChunks: [ttsChunk])
                preBufferedChunks[chunkIndex] = preBuffered
                nextIndexToBuffer += 1
                continue
            }

            logger.debug("Pre-buffering chunk \(chunkIndex) (synthesizing)")

            do {
                // Generate TTS audio
                let audioStream = try await ttsService.synthesize(text: chunk.text)

                // Collect all audio chunks
                var audioChunks: [TTSAudioChunk] = []
                for await audioChunk in audioStream {
                    audioChunks.append(audioChunk)
                }

                // Store pre-buffered chunk
                let preBuffered = PreBufferedChunk(chunk: chunk, audioChunks: audioChunks)
                preBufferedChunks[chunkIndex] = preBuffered

                logger.debug("Buffered chunk \(chunkIndex) with \(audioChunks.count) audio segments")

                // Persist synthesized audio to Core Data so future sessions
                // can skip synthesis for this chunk (cross-session caching).
                if let itemId = currentItemId, let manager = readingListManager {
                    var combinedData = Data()
                    for ac in audioChunks {
                        combinedData.append(ac.audioData)
                    }
                    if !combinedData.isEmpty {
                        try? await MainActor.run {
                            try manager.saveCachedAudio(
                                itemId: itemId,
                                chunkIndex: chunkIndex,
                                audioData: combinedData,
                                sampleRate: 24000
                            )
                        }
                    }
                }

            } catch {
                logger.error("Failed to buffer chunk \(chunkIndex): \(error.localizedDescription)")
                // Continue to next chunk on error
            }

            nextIndexToBuffer += 1
        }

        isPreBuffering = false
    }

    /// Wait for a specific chunk to be buffered
    private func waitForChunk(at index: Int32) async throws {
        let timeout: TimeInterval = 10.0
        let startTime = Date()

        while preBufferedChunks[index] == nil {
            if Date().timeIntervalSince(startTime) > timeout {
                throw ReadingPlaybackError.bufferTimeout
            }

            if Task.isCancelled {
                throw CancellationError()
            }

            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Playback Loop

    /// Start the main playback loop
    /// - Parameters:
    ///   - streamFirstChunk: If true, the first chunk is streamed directly
    ///     from TTS to AudioEngine for lowest time-to-first-audio instead of waiting
    ///     for the full pre-buffer.
    ///   - useCachedAudio: If true, the first chunk uses pre-generated cached audio
    ///     for instant playback (0ms latency vs ~200ms for TTS streaming).
    private func startPlaybackLoop(streamFirstChunk: Bool = false, useCachedAudio: Bool = false) {
        playbackTask?.cancel()

        let streamFirst = streamFirstChunk
        let cached = useCachedAudio
        playbackTask = Task { [weak self] in
            guard let self else { return }

            await self.runPlaybackLoop(streamFirstChunk: streamFirst, useCachedAudio: cached)
        }
    }

    /// Run the main playback loop
    /// - Parameters:
    ///   - streamFirstChunk: Stream the first chunk directly from TTS
    ///   - useCachedAudio: Play the first chunk from pre-generated cache
    private func runPlaybackLoop(streamFirstChunk: Bool = false, useCachedAudio: Bool = false) async {
        guard let audioEngine, let ttsService else { return }

        var shouldStreamNext = streamFirstChunk
        var shouldUseCached = useCachedAudio

        while !Task.isCancelled && state == .playing {
            // Check if we've reached the end
            if currentChunkIndex >= Int32(chunks.count) {
                state = .completed
                await saveCurrentPosition()
                if let cb = callbacks { await notify(cb.onComplete) }
                break
            }

            // Notify chunk change
            let chunkIdx = currentChunkIndex
            let totalCount = chunks.count
            if let cb = callbacks {
                await MainActor.run { cb.onChunkChange(chunkIdx, totalCount) }
            }

            if shouldUseCached {
                // Play pre-generated audio from cache (instant, 0ms latency).
                // This audio was synthesized at import time and stored on the chunk.
                shouldUseCached = false
                shouldStreamNext = false
                let chunk = chunks[Int(currentChunkIndex)]

                logger.debug("Playing cached audio for chunk \(currentChunkIndex) (instant)")

                // TTFA: cached audio path (instant playback)
                await TTFAInstrumentation.shared.markCachedHit()

                if let audioData = chunk.cachedAudioData {
                    let ttsChunk = TTSAudioChunk(
                        audioData: audioData,
                        format: .pcmFloat32(sampleRate: chunk.cachedAudioSampleRate, channels: 1),
                        sequenceNumber: 0,
                        isFirst: true,
                        isLast: true
                    )
                    do {
                        try await audioEngine.playAudio(ttsChunk)
                    } catch {
                        logger.error("Cached audio playback error: \(error.localizedDescription)")
                        // Fall through to streaming on next iteration
                        shouldStreamNext = true
                        continue
                    }
                } else {
                    // Cache was expected but missing, fall through to streaming
                    shouldStreamNext = true
                    continue
                }
            } else if shouldStreamNext {
                // Stream this chunk directly from TTS to AudioEngine.
                // Audio plays as soon as the first TTS segment arrives (~200ms)
                // instead of waiting for the entire chunk to be synthesized.
                shouldStreamNext = false
                let chunk = chunks[Int(currentChunkIndex)]

                logger.debug("Streaming chunk \(currentChunkIndex) directly for low latency")

                do {
                    let audioStream = try await ttsService.synthesize(text: chunk.text)
                    var isFirstStreamChunk = true
                    for await audioChunk in audioStream {
                        if Task.isCancelled || state != .playing { break }
                        // TTFA: mark first TTS chunk received (streaming path)
                        if isFirstStreamChunk {
                            isFirstStreamChunk = false
                            await TTFAInstrumentation.shared.markTTSFirstChunk()
                        }
                        try await audioEngine.playAudio(audioChunk)
                    }
                } catch {
                    logger.error("Streaming playback error at chunk \(currentChunkIndex): \(error.localizedDescription)")
                    state = .error(error.localizedDescription)
                    if let cb = callbacks {
                        let errMsg = error.localizedDescription
                        await MainActor.run {
                            cb.onError(ReadingPlaybackError.playbackFailed(errMsg))
                        }
                    }
                    break
                }
            } else if let preBuffered = preBufferedChunks[currentChunkIndex] {
                // Use pre-buffered chunk (normal path for chunks already synthesized)
                do {
                    for audioChunk in preBuffered.audioChunks {
                        if Task.isCancelled || state != .playing {
                            break
                        }
                        try await audioEngine.playAudio(audioChunk)
                    }
                } catch {
                    logger.error("Playback error at chunk \(currentChunkIndex): \(error.localizedDescription)")
                    state = .error(error.localizedDescription)
                    if let cb = callbacks {
                        let errMsg = error.localizedDescription
                        await MainActor.run {
                            cb.onError(ReadingPlaybackError.playbackFailed(errMsg))
                        }
                    }
                    break
                }
            } else {
                // No pre-buffered audio available. Check if this chunk has
                // import-time cached audio (from pre-generation).
                let chunk = chunks[Int(currentChunkIndex)]
                if chunk.hasCachedAudio, let audioData = chunk.cachedAudioData {
                    logger.debug("Playing import-cached audio for chunk \(currentChunkIndex)")
                    let ttsChunk = TTSAudioChunk(
                        audioData: audioData,
                        format: .pcmFloat32(sampleRate: chunk.cachedAudioSampleRate, channels: 1),
                        sequenceNumber: 0,
                        isFirst: true,
                        isLast: true
                    )
                    do {
                        try await audioEngine.playAudio(ttsChunk)
                    } catch {
                        logger.error("Cached audio playback error: \(error.localizedDescription)")
                    }
                } else {
                    // No cached audio either, must wait for pre-buffer
                    state = .buffering
                    if let cb = callbacks { await notify(cb.onBuffering) }
                    do {
                        try await waitForChunk(at: currentChunkIndex)
                        state = .playing
                    } catch {
                        state = .error("Buffering failed")
                        if let cb = callbacks {
                            let errMsg = error.localizedDescription
                            await MainActor.run {
                                cb.onError(ReadingPlaybackError.playbackFailed(errMsg))
                            }
                        }
                        break
                    }
                    continue
                }
            }

            // Check if we should continue (might have been paused/stopped)
            guard state == .playing else { break }

            // Move to next chunk
            currentChunkIndex += 1

            // Persist position on every chunk transition so progress survives crashes
            await saveCurrentPosition()

            // Clean up old buffered chunks outside the FOV retention window.
            // Keep retainBehindCount chunks behind current position so the user
            // can skip back without triggering re-synthesis.
            let oldIndex = currentChunkIndex - retainBehindCount
            if oldIndex >= 0 {
                preBufferedChunks.removeValue(forKey: oldIndex)
            }

            // Trigger more pre-buffering if needed
            if !isPreBuffering && currentChunkIndex + Int32(preBufferCount) > Int32(preBufferedChunks.count) {
                startPreBuffering(from: currentChunkIndex + 1)
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
