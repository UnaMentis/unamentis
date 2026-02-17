// UnaMentis - Audio Playback Orchestrator
// Shared playback engine for all TTS-based audio modules
//
// Replaces duplicated playback loops in SessionManager, ReadingPlaybackService,
// and KBVoiceCoordinator with a single, well-tested implementation.
//
// Core loop: cached audio -> prefetch cache -> wait for in-progress prefetch -> stream from TTS
// Supports: prefetching, inter-segment silence, pause/resume, dynamic segment append
//
// Part of Core/Audio

import Foundation
import Logging

// MARK: - Orchestrator State

/// Playback state machine for the orchestrator
public enum OrchestratorState: Equatable, Sendable {
    case idle
    case playing
    case paused
    case buffering
    case completed
    case error(String)
}

// MARK: - Audio Playback Orchestrator

/// Central actor that manages TTS audio playback for all modules.
///
/// Modules load segments, start playback, and receive events via the delegate.
/// The orchestrator handles the playback loop, prefetching, caching, and
/// inter-segment timing internally.
///
/// Usage:
/// ```swift
/// let orchestrator = AudioPlaybackOrchestrator(
///     config: .readingList,
///     ttsService: ttsService,
///     audioEngine: audioEngine
/// )
/// orchestrator.delegate = self
/// await orchestrator.loadSegments(chunks)
/// await orchestrator.startPlayback(from: 0)
/// ```
public actor AudioPlaybackOrchestrator {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.audio.orchestrator")

    /// Configuration (prefetch depth, silence, retention)
    public let config: PlaybackOrchestratorConfig

    /// TTS service for on-demand synthesis
    private let ttsService: any TTSService

    /// Audio engine for low-level playback
    private let audioEngine: AudioEngine

    /// Delegate for module-specific event handling
    public weak var delegate: (any PlaybackOrchestratorDelegate)?

    /// Current playback state
    public private(set) var state: OrchestratorState = .idle

    /// All segments in the current playback session
    private var segments: [any PlayableSegment] = []

    /// Current playback position index
    public private(set) var currentIndex: Int = 0

    /// Whether additional segments may still be appended (for streaming/dynamic use)
    private var expectsMoreSegments: Bool = false

    /// Prefetched audio keyed by segment index
    private var prefetchCache: [Int: [TTSAudioChunk]] = [:]

    /// In-progress prefetch tasks keyed by segment index
    private var prefetchTasks: [Int: Task<[TTSAudioChunk]?, Never>] = [:]

    /// Main playback loop task
    private var playbackTask: Task<Void, Never>?

    /// Prefetch loop task
    private var prefetchLoopTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(
        config: PlaybackOrchestratorConfig = .default,
        ttsService: any TTSService,
        audioEngine: AudioEngine
    ) {
        self.config = config
        self.ttsService = ttsService
        self.audioEngine = audioEngine
    }

    /// Set the delegate for receiving playback events.
    /// Required because actor-isolated properties cannot be set from outside the actor.
    public func setDelegate(_ newDelegate: any PlaybackOrchestratorDelegate) {
        self.delegate = newDelegate
    }

    // MARK: - Segment Management

    /// Load segments for playback. Replaces any previously loaded segments.
    public func loadSegments(_ newSegments: [any PlayableSegment]) {
        segments = newSegments
        prefetchCache.removeAll()
        cancelAllPrefetches()
        expectsMoreSegments = false
        logger.info("Loaded \(newSegments.count) segments")
    }

    /// Append segments dynamically (for SessionManager's streaming LLM sentences).
    /// Call `signalNoMoreSegments()` when the LLM stream finishes.
    public func appendSegments(_ newSegments: [any PlayableSegment]) {
        segments.append(contentsOf: newSegments)
        logger.debug("Appended \(newSegments.count) segments (total: \(segments.count))")
    }

    /// Signal that no more segments will be appended.
    /// The playback loop will finish when the queue empties.
    public func signalNoMoreSegments() {
        expectsMoreSegments = false
        logger.debug("Signaled no more segments")
    }

    /// Mark that more segments may arrive (for dynamic append mode).
    public func setExpectsMoreSegments(_ expects: Bool) {
        expectsMoreSegments = expects
    }

    /// Get current total segment count
    public var totalSegments: Int { segments.count }

    // MARK: - Playback Control

    /// Start playback from a given index.
    /// - Parameter startIndex: Segment index to begin at (default 0).
    public func startPlayback(from startIndex: Int = 0) async {
        guard !segments.isEmpty || expectsMoreSegments else {
            logger.warning("No segments loaded, cannot start playback")
            return
        }

        // Stop any existing playback
        await stopPlayback()

        currentIndex = min(startIndex, max(segments.count - 1, 0))
        state = .playing

        // Start prefetching ahead of current position
        startPrefetchLoop(from: currentIndex + 1)

        // Start main playback loop
        playbackTask = Task { [weak self] in
            await self?.runPlaybackLoop()
        }

        logger.info("Started playback from index \(currentIndex)")
    }

    /// Pause playback. Audio engine pauses, state preserved for resume.
    public func pausePlayback() async {
        guard state == .playing else { return }

        _ = await audioEngine.pausePlayback()
        state = .paused
        logger.debug("Paused at index \(currentIndex)")
    }

    /// Resume playback from paused state.
    public func resumePlayback() async {
        guard state == .paused else { return }

        _ = await audioEngine.resumePlayback()
        state = .playing

        // Restart the playback loop if it's not running
        if playbackTask == nil {
            playbackTask = Task { [weak self] in
                await self?.runPlaybackLoop()
            }
        }

        // Ensure prefetching continues
        if prefetchLoopTask == nil {
            startPrefetchLoop(from: currentIndex + 1)
        }

        logger.debug("Resumed from index \(currentIndex)")
    }

    /// Stop playback completely. Clears all state and caches.
    public func stopPlayback() async {
        playbackTask?.cancel()
        playbackTask = nil
        cancelAllPrefetches()
        prefetchLoopTask?.cancel()
        prefetchLoopTask = nil

        await audioEngine.stopPlayback()
        prefetchCache.removeAll()
        state = .idle

        logger.debug("Stopped playback")
    }

    /// Suspend playback preserving all cached state.
    /// Use when the view disappears but the user may return quickly.
    /// Cheaper than stopPlayback() because prefetch cache is retained.
    public func suspendPlayback() async {
        playbackTask?.cancel()
        playbackTask = nil
        prefetchLoopTask?.cancel()
        prefetchLoopTask = nil

        _ = await audioEngine.pausePlayback()
        state = .paused

        logger.debug("Suspended at index \(currentIndex), prefetch cache retained (\(prefetchCache.count) entries)")
    }

    /// Skip to a specific segment index.
    public func skipToSegment(_ index: Int) async {
        guard index >= 0 && index < segments.count else { return }

        // Stop current audio
        playbackTask?.cancel()
        playbackTask = nil
        await audioEngine.stopPlayback()

        // Update position
        currentIndex = index

        // Clear prefetch and restart from new position
        prefetchCache.removeAll()
        cancelAllPrefetches()
        prefetchLoopTask?.cancel()
        startPrefetchLoop(from: index + 1)

        // Restart playback if we were playing
        if state == .playing || state == .paused {
            state = .playing
            playbackTask = Task { [weak self] in
                await self?.runPlaybackLoop()
            }
        }

        await delegate?.orchestratorDidChangeSegment(index: index, total: segments.count)
    }

    // MARK: - Core Playback Loop

    private func runPlaybackLoop() async {
        while !Task.isCancelled && state == .playing {
            // Wait for segments if in dynamic mode and queue is empty
            if currentIndex >= segments.count {
                if expectsMoreSegments {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                } else {
                    // All segments played
                    state = .completed
                    await delegate?.orchestratorDidComplete()
                    logger.info("Playback completed (\(segments.count) segments)")
                    break
                }
            }

            let segment = segments[currentIndex]
            let index = currentIndex

            // Notify delegate of segment change
            await delegate?.orchestratorDidChangeSegment(index: index, total: segments.count)

            // Ask delegate if we should play this segment
            let shouldPlay = await delegate?.orchestratorWillPlaySegment(at: index) ?? true
            if !shouldPlay {
                currentIndex += 1
                continue
            }

            // Play the segment using the best available audio source
            let playResult = await playSegment(segment)

            guard !Task.isCancelled && state == .playing else { break }

            if case .failure(let error) = playResult {
                state = .error(error.localizedDescription)
                await delegate?.orchestratorDidEncounterError(error)
                logger.error("Playback error at index \(index): \(error.localizedDescription)")
                break
            }

            // Notify delegate that segment finished
            await delegate?.orchestratorDidFinishSegment(at: index)

            // Inter-segment silence
            if config.interSegmentSilenceMs > 0 {
                try? await Task.sleep(for: .milliseconds(config.interSegmentSilenceMs))
            }

            guard !Task.isCancelled && state == .playing else { break }

            // Advance to next segment
            currentIndex += 1

            // Evict old entries beyond retention window
            evictOldPrefetchEntries()

            // Trigger prefetch for upcoming segments
            if prefetchLoopTask == nil {
                startPrefetchLoop(from: currentIndex + 1)
            }
        }

        playbackTask = nil
    }

    /// Play a single segment from the best available source.
    /// Priority: 1) segment cached audio, 2) prefetch cache, 3) wait for in-progress prefetch, 4) stream from TTS
    private func playSegment(_ segment: any PlayableSegment) async -> Result<Void, Error> {
        let index = segment.segmentIndex

        // 1. Segment has pre-generated cached audio (e.g. import-time pre-gen)
        if let cached = segment.cachedAudio {
            logger.debug("Playing cached audio for segment \(index)")
            await TTFAInstrumentation.shared.markCachedHit()
            let chunk = cached.toTTSAudioChunk()
            do {
                try await audioEngine.playAudio(chunk)
                return .success(())
            } catch {
                logger.error("Cached audio playback failed, falling through to TTS: \(error.localizedDescription)")
                // Fall through to TTS synthesis
            }
        }

        // 2. Prefetch cache has synthesized audio ready
        if let chunks = prefetchCache[index] {
            logger.debug("Playing prefetched audio for segment \(index)")
            prefetchCache.removeValue(forKey: index)
            do {
                for chunk in chunks {
                    if Task.isCancelled || state != .playing { break }
                    try await audioEngine.playAudio(chunk)
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        // 3. Wait for in-progress prefetch task
        if let prefetchTask = prefetchTasks[index] {
            logger.debug("Waiting for in-progress prefetch for segment \(index)")
            state = .buffering
            if let chunks = await prefetchTask.value {
                state = .playing
                prefetchTasks.removeValue(forKey: index)
                do {
                    for chunk in chunks {
                        if Task.isCancelled || state != .playing { break }
                        try await audioEngine.playAudio(chunk)
                    }
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }
            state = .playing
            // Prefetch returned nil, fall through to direct synthesis
        }

        // 4. Fallback: stream directly from TTS
        logger.debug("Streaming segment \(index) from TTS")
        do {
            let stream = try await ttsService.synthesize(text: segment.segmentText)
            var isFirstChunk = true
            for await chunk in stream {
                if Task.isCancelled || state != .playing { break }
                if isFirstChunk {
                    isFirstChunk = false
                    await TTFAInstrumentation.shared.markTTSFirstChunk()
                }
                try await audioEngine.playAudio(chunk)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Prefetching

    private func startPrefetchLoop(from startIndex: Int) {
        prefetchLoopTask?.cancel()

        guard config.prefetchDepth > 0 else { return }

        prefetchLoopTask = Task { [weak self] in
            guard let self else { return }
            await self.runPrefetchLoop(from: startIndex)
        }
    }

    private func runPrefetchLoop(from startIndex: Int) async {
        var nextIndex = startIndex

        while !Task.isCancelled {
            // Don't prefetch beyond the configured depth ahead of current position
            let maxIndex = currentIndex + config.prefetchDepth
            if nextIndex > maxIndex {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }

            // Wait for more segments in dynamic mode
            if nextIndex >= segments.count {
                if expectsMoreSegments {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                } else {
                    break
                }
            }

            // Skip already cached or in-progress
            if prefetchCache[nextIndex] != nil || prefetchTasks[nextIndex] != nil {
                nextIndex += 1
                continue
            }

            let segment = segments[nextIndex]

            // Skip segments with pre-generated audio (no synthesis needed)
            if segment.cachedAudio != nil {
                nextIndex += 1
                continue
            }

            // Start prefetch for this segment
            let segmentIndex = nextIndex
            let text = segment.segmentText
            prefetchTasks[segmentIndex] = Task { [weak self] in
                guard let self else { return nil }
                return await self.synthesizeSegment(text: text)
            }

            nextIndex += 1
        }

        prefetchLoopTask = nil
    }

    /// Synthesize text into audio chunks (used by prefetch)
    private func synthesizeSegment(text: String) async -> [TTSAudioChunk]? {
        do {
            let stream = try await ttsService.synthesize(text: text)
            var chunks: [TTSAudioChunk] = []
            for await chunk in stream {
                chunks.append(chunk)
            }
            return chunks
        } catch {
            logger.error("Prefetch synthesis failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Store prefetched audio result in the cache (called from prefetch task completion)
    private func cachePrefetchResult(_ chunks: [TTSAudioChunk], for index: Int) {
        prefetchCache[index] = chunks
        prefetchTasks.removeValue(forKey: index)
    }

    private func cancelAllPrefetches() {
        for (_, task) in prefetchTasks {
            task.cancel()
        }
        prefetchTasks.removeAll()
    }

    private func evictOldPrefetchEntries() {
        guard config.retainBehindCount >= 0 else { return }
        let evictBefore = currentIndex - config.retainBehindCount
        for key in prefetchCache.keys where key < evictBefore {
            prefetchCache.removeValue(forKey: key)
        }
    }
}
