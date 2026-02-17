// UnaMentis - Audio Playback Orchestrator
// Single shared playback loop for all voice-enabled modules.
//
// Part of Core/Audio (shared audio playback infrastructure)
//
// Replaces per-module playback loops in SessionManager,
// ReadingPlaybackService, and KBVoiceCoordinator.

import Foundation
import Logging

// MARK: - Orchestrator State

/// Current state of the playback orchestrator
public enum OrchestratorState: Equatable, Sendable {
    case idle
    case playing
    case paused
    case buffering
    case completed
    case error(String)
}

// MARK: - Audio Playback Orchestrator

/// Handles the core TTS playback loop: cached -> prefetched -> direct synthesis.
/// Modules configure it with presets and receive callbacks via the delegate.
///
/// Thread-safe via Swift actor isolation.
public actor AudioPlaybackOrchestrator {
    private let logger = Logger(label: "com.unamentis.audio.orchestrator")

    // MARK: - Configuration

    private let config: PlaybackOrchestratorConfig
    private let ttsService: any TTSService
    private let audioEngine: AudioEngine

    // MARK: - State

    /// Current orchestrator state
    public private(set) var state: OrchestratorState = .idle

    /// Index of the currently playing segment
    public private(set) var currentIndex: Int = 0

    /// All loaded segments
    private var segments: [any PlayableSegment] = []

    /// Delegate for module-specific hooks
    public weak var delegate: (any PlaybackOrchestratorDelegate)?

    // MARK: - Prefetch

    /// Cache of prefetched audio keyed by segment index
    private var prefetchCache: [Int: TTSAudioChunk] = [:]

    /// Active prefetch tasks
    private var prefetchTasks: [Int: Task<TTSAudioChunk?, Never>] = [:]

    // MARK: - Dynamic Segment Mode

    /// Whether more segments are expected (streaming LLM use case)
    private var expectsMoreSegments: Bool = false

    /// Whether `signalNoMoreSegments()` has been called
    private var noMoreSegmentsSignaled: Bool = false

    // MARK: - Playback Loop

    /// The main playback task
    private var playbackTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(
        config: PlaybackOrchestratorConfig,
        ttsService: any TTSService,
        audioEngine: AudioEngine
    ) {
        self.config = config
        self.ttsService = ttsService
        self.audioEngine = audioEngine
    }

    // MARK: - Public API

    /// Set the full list of segments to play
    public func loadSegments(_ newSegments: [any PlayableSegment]) {
        segments = newSegments
    }

    /// Add segments dynamically (for streaming/LLM use case)
    public func appendSegments(_ newSegments: [any PlayableSegment]) {
        segments.append(contentsOf: newSegments)

        // If we were buffering and waiting for content, kick the loop
        if state == .buffering {
            // The playback loop polls for new segments, so just updating
            // the array is sufficient. State change will happen in the loop.
        }
    }

    /// Tell the orchestrator no more segments will arrive
    public func signalNoMoreSegments() {
        noMoreSegmentsSignaled = true
    }

    /// Enable/disable dynamic segment mode
    public func setExpectsMoreSegments(_ expects: Bool) {
        expectsMoreSegments = expects
        if !expects {
            noMoreSegmentsSignaled = true
        }
    }

    /// Start playing from a given segment index
    public func startPlayback(from index: Int) {
        switch state {
        case .idle, .completed, .error:
            break // Allowed: restart from these states
        default:
            return // Already playing/paused/buffering
        }

        currentIndex = index
        state = .playing
        noMoreSegmentsSignaled = !expectsMoreSegments

        // Launch the playback loop
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            await self?.playbackLoop()
        }
    }

    /// Pause playback, preserving all state
    public func pausePlayback() {
        guard state == .playing else { return }
        state = .paused
        Task { await audioEngine.pausePlayback() }
    }

    /// Resume from paused state
    public func resumePlayback() {
        guard state == .paused else { return }
        state = .playing
        Task { await audioEngine.resumePlayback() }
    }

    /// Full stop, release resources
    public func stopPlayback() {
        let wasPlaying = state == .playing || state == .paused || state == .buffering
        state = .idle

        playbackTask?.cancel()
        playbackTask = nil

        // Cancel all prefetch tasks
        for (_, task) in prefetchTasks {
            task.cancel()
        }
        prefetchTasks.removeAll()
        prefetchCache.removeAll()

        segments.removeAll()
        currentIndex = 0
        expectsMoreSegments = false
        noMoreSegmentsSignaled = false

        if wasPlaying {
            Task { await audioEngine.stopPlayback() }
        }
    }

    /// Lightweight stop: preserves cached audio, prefetch state, and position.
    /// Used when navigating away temporarily.
    public func suspendPlayback() {
        guard state == .playing || state == .paused else { return }
        state = .paused

        Task { await audioEngine.stopPlayback() }
        // Note: we do NOT clear prefetchCache or segments,
        // so resume can pick up where we left off.
    }

    /// Jump to a specific segment index
    public func skipToSegment(_ index: Int) {
        guard index >= 0 && index < segments.count else { return }
        currentIndex = index

        // Stop current playback, the loop will restart from new index
        Task { await audioEngine.stopPlayback() }

        if state == .paused {
            state = .playing
            playbackTask?.cancel()
            playbackTask = Task { [weak self] in
                await self?.playbackLoop()
            }
        }
    }

    // MARK: - Playback Loop

    private func playbackLoop() async {
        while state == .playing || state == .buffering {
            // Check for cancellation
            if Task.isCancelled { break }

            // Check if we have a segment to play
            guard currentIndex < segments.count else {
                // No more segments available
                if noMoreSegmentsSignaled || !expectsMoreSegments {
                    // All done
                    state = .completed
                    await delegate?.orchestratorDidComplete()
                    break
                } else {
                    // Wait for more segments
                    state = .buffering
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
            }

            // We have a segment
            if state == .buffering { state = .playing }
            let segment = segments[currentIndex]

            // Ask delegate if we should play this segment
            if let del = delegate {
                let shouldPlay = await del.orchestratorWillPlaySegment(at: currentIndex)
                if !shouldPlay {
                    await advanceToNextSegment()
                    continue
                }
            }

            // Play the segment through the 3-tier resolution
            do {
                try await playSegment(segment)
            } catch {
                logger.error("Failed to play segment \(currentIndex): \(error)")
                // Skip this segment and continue
                await delegate?.orchestratorDidEncounterError(error)
            }

            // Post-segment
            await delegate?.orchestratorDidFinishSegment(at: currentIndex)

            // Inter-segment silence
            if config.interSegmentSilenceMs > 0 {
                try? await Task.sleep(for: .milliseconds(config.interSegmentSilenceMs))
            }

            // Check state again (may have been paused/stopped during sleep)
            if state == .paused {
                // Wait for resume
                while state == .paused {
                    try? await Task.sleep(for: .milliseconds(50))
                    if Task.isCancelled { return }
                }
                if state != .playing { break }
            } else if state != .playing {
                break
            }

            // Advance
            await advanceToNextSegment()
        }
    }

    private func advanceToNextSegment() async {
        currentIndex += 1
        let total = segments.count
        await delegate?.orchestratorDidChangeSegment(index: currentIndex, total: total)

        // Trigger prefetch for upcoming segments
        triggerPrefetch()

        // Evict old entries
        evictOldEntries()
    }

    // MARK: - 3-Tier Audio Resolution

    /// Play a segment using: cached audio -> prefetched audio -> direct synthesis
    private func playSegment(_ segment: any PlayableSegment) async throws {
        let index = segment.segmentIndex

        // Tier 1: Cached audio (0ms latency)
        if let cached = segment.cachedAudio {
            let chunk = cached.toTTSAudioChunk()
            try await audioEngine.playAudio(chunk)
            return
        }

        // Tier 2: Prefetch cache (0ms latency if ready)
        if let prefetched = prefetchCache[index] {
            prefetchCache.removeValue(forKey: index)
            try await audioEngine.playAudio(prefetched)
            return
        }

        // Tier 2.5: Wait for in-progress prefetch (bounded by timeout)
        if let task = prefetchTasks[index] {
            let result = await withTaskGroup(of: TTSAudioChunk?.self) { group in
                group.addTask { await task.value }
                group.addTask {
                    try? await Task.sleep(for: .seconds(self.config.bufferTimeoutSeconds))
                    return nil
                }
                let first = await group.next()
                group.cancelAll()
                return first ?? nil
            }

            prefetchTasks.removeValue(forKey: index)

            if let chunk = result {
                try await audioEngine.playAudio(chunk)
                return
            }
            // Timeout, fall through to direct synthesis
        }

        // Tier 3: Direct synthesis (streaming)
        let stream = try await ttsService.synthesize(text: segment.segmentText)
        for await chunk in stream {
            try await audioEngine.playAudio(chunk)
        }
    }

    // MARK: - Prefetch

    private func triggerPrefetch() {
        guard config.prefetchDepth > 0 else { return }

        let segmentCount = segments.count
        let start = currentIndex + 1
        guard start < segmentCount else { return }

        let end = min(start + config.prefetchDepth, segmentCount)

        for i in start..<end where i < segmentCount {
            guard prefetchCache[i] == nil, prefetchTasks[i] == nil else { continue }

            let text = segments[i].segmentText
            let hasCached = segments[i].cachedAudio != nil
            // Skip prefetch for segments with cached audio
            if hasCached { continue }

            let tts = ttsService
            prefetchTasks[i] = Task {
                do {
                    let stream = try await tts.synthesize(text: text)
                    var allData = Data()
                    var lastChunk: TTSAudioChunk?

                    for await chunk in stream {
                        allData.append(chunk.audioData)
                        lastChunk = chunk
                    }

                    guard let last = lastChunk else { return nil }

                    let combined = TTSAudioChunk(
                        audioData: allData,
                        format: last.format,
                        sequenceNumber: 0,
                        isFirst: true,
                        isLast: true
                    )
                    return combined
                } catch {
                    return nil
                }
            }
        }
    }

    // MARK: - Eviction

    private func evictOldEntries() {
        let threshold = currentIndex - config.retainBehindCount
        for key in prefetchCache.keys where key < threshold {
            prefetchCache.removeValue(forKey: key)
        }
        for key in prefetchTasks.keys where key < threshold {
            prefetchTasks[key]?.cancel()
            prefetchTasks.removeValue(forKey: key)
        }
    }
}
