// UnaMentis - Reading Playback View Model
// State management for reading playback UI
//
// Part of UI/ReadingList

import Foundation
import SwiftUI
import Combine
import Logging
import OSLog

// MARK: - Visual Asset Data Transfer Object

/// Sendable DTO for visual asset data (safe to cross actor boundaries)
public struct ReadingVisualAssetData: Identifiable, Sendable {
    public let id: UUID
    public let chunkIndex: Int32
    public let localPath: String?
    public let cachedData: Data?
    public let width: Int32
    public let height: Int32
    public let altText: String?
}

// MARK: - Reading Playback View Model

/// View model for the reading playback interface
@MainActor
public final class ReadingPlaybackViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var state: ReadingPlaybackState = .idle
    @Published public var currentChunkIndex: Int32 = 0
    @Published public var totalChunks: Int = 0
    @Published public var currentChunkText: String?
    @Published public var bookmarks: [ReadingBookmarkData] = []
    @Published public var currentChunkImages: [ReadingVisualAssetData] = []
    @Published public var showError: Bool = false
    @Published public var errorMessage: String?

    // MARK: - Computed Properties

    /// Current playback progress (0.0 to 1.0)
    public var progress: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(currentChunkIndex) / Double(totalChunks)
    }

    /// Whether currently playing
    public var isPlaying: Bool {
        state == .playing
    }

    /// Whether playback is active (playing, paused, or buffering).
    /// Controls should remain visible in all these states.
    public var hasActivePlayback: Bool {
        switch state {
        case .playing, .paused, .buffering:
            return true
        default:
            return false
        }
    }

    /// Whether can skip backward
    public var canSkipBackward: Bool {
        currentChunkIndex > 0 && state != .loading
    }

    /// Whether can skip forward
    public var canSkipForward: Bool {
        currentChunkIndex < Int32(totalChunks - 1) && state != .loading
    }

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.reading.playback.viewmodel")
    private let item: ReadingListItem
    private var chunks: [ReadingChunkData] = []
    private var playbackService: ReadingPlaybackService?
    private var allVisualAssets: [ReadingVisualAssetData] = []
    private var storedAudioEngine: AudioEngine?
    private var storedTTSService: (any TTSService)?

    // Voice command support
    private let voiceCommandRecognizer = VoiceCommandRecognizer()
    private let voiceBookmarkService = VoiceBookmarkService()
    private let voiceFeedback = VoiceActivityFeedback()
    private var voiceMonitoringTask: Task<Void, Never>?
    private var lastProcessedTranscript: String = ""

    // MARK: - Initialization

    public init(item: ReadingListItem) {
        self.item = item
        self.totalChunks = item.totalChunks
        self.currentChunkIndex = item.currentChunkIndex
    }

    // MARK: - Setup

    /// Load chunks and prepare for playback
    public func loadAndPrepare() async {
        state = .loading

        do {
            // If audio pre-generation is in progress for this item, wait for it
            // so we have the cached audio ready before loading chunks.
            if item.audioPreGenStatus == .generating, let itemId = item.id {
                logger.info("Waiting for audio pre-generation to complete...")
                _ = await ReadingAudioPreGenerator.shared.waitForPreGeneration(itemId: itemId)
                // Re-fault the item to pick up the cached audio data
                item.managedObjectContext?.refresh(item, mergeChanges: true)
            }

            // Load chunks from Core Data (includes cached audio on chunk 0)
            chunks = loadChunksFromItem()
            totalChunks = chunks.count

            // Set current chunk text
            if !chunks.isEmpty && Int(currentChunkIndex) < chunks.count {
                currentChunkText = chunks[Int(currentChunkIndex)].text
            }

            // Load bookmarks
            loadBookmarks()

            // Load visual assets and set images for current chunk
            loadVisualAssets()
            updateCurrentChunkImages(for: currentChunkIndex)

            // Create playback service
            let service = ReadingPlaybackService()

            // Initialize AudioEngine and TTS service in parallel
            async let audioEngineResult = getAudioEngine()
            async let ttsServiceResult = getTTSService()

            if let audioEngine = await audioEngineResult,
               let ttsService = await ttsServiceResult,
               let manager = ReadingListManager.shared {

                // Pre-warm the TTS model so synthesis starts instantly
                if let pocketService = ttsService as? KyutaiPocketTTSService {
                    try await pocketService.ensureLoaded()
                }

                let callbacks = makeCallbacks()
                await service.configure(
                    ttsService: ttsService,
                    audioEngine: audioEngine,
                    readingListManager: manager,
                    callbacks: callbacks
                )

                playbackService = service
                state = .idle
                logger.info("Playback prepared with \(chunks.count) chunks")
            } else {
                state = .error("Services not available")
                errorMessage = "Audio services not available"
                showError = true
            }

        } catch {
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Load chunks from the reading item, including cached audio on chunk 0
    private func loadChunksFromItem() -> [ReadingChunkData] {
        return item.chunksArray.map { chunk in
            ReadingChunkData(
                index: chunk.index,
                text: chunk.text ?? "",
                characterOffset: chunk.characterOffset,
                estimatedDurationSeconds: chunk.estimatedDurationSeconds,
                cachedAudioData: chunk.cachedAudioData,
                cachedAudioSampleRate: chunk.cachedAudioSampleRate
            )
        }
    }

    /// Load bookmarks from the reading item
    private func loadBookmarks() {
        bookmarks = item.bookmarksArray.compactMap { bookmark in
            guard let id = bookmark.id else { return nil }
            return ReadingBookmarkData(
                id: id,
                chunkIndex: bookmark.chunkIndex,
                note: bookmark.note
            )
        }
    }

    /// Load visual assets from the reading item
    private func loadVisualAssets() {
        allVisualAssets = item.visualAssetsArray.compactMap { asset in
            guard let id = asset.id else { return nil }
            return ReadingVisualAssetData(
                id: id,
                chunkIndex: asset.chunkIndex,
                localPath: asset.localPath,
                cachedData: asset.cachedData,
                width: asset.width,
                height: asset.height,
                altText: asset.altText
            )
        }
    }

    /// Update the current chunk images for display
    private func updateCurrentChunkImages(for index: Int32) {
        currentChunkImages = allVisualAssets.filter { $0.chunkIndex == index }
    }

    // MARK: - Playback Control

    /// Toggle between play and pause
    public func togglePlayPause() async {
        guard let service = playbackService else { return }

        switch state {
        case .idle, .paused:
            await startOrResume()
        case .playing:
            await service.pause()
        case .completed:
            // Restart from beginning
            currentChunkIndex = 0
            await startOrResume()
        default:
            break
        }
    }

    /// Start or resume playback
    private func startOrResume() async {
        guard let service = playbackService else { return }

        if state == .paused {
            await service.resume()
        } else {
            guard let itemId = item.id else {
                logger.error("Cannot start playback: reading item has no ID")
                return
            }
            do {
                try await service.startPlayback(
                    itemId: itemId,
                    chunks: chunks,
                    startIndex: currentChunkIndex
                )
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// Stop playback and release audio resources
    public func stopPlayback() async {
        if let service = playbackService {
            await service.stopPlayback()
        }

        // Release AudioEngine resources
        if let engine = storedAudioEngine {
            await engine.stop()
            await engine.cleanup()
            storedAudioEngine = nil
        }

        // Schedule deferred TTS release (keeps model warm for quick re-entry)
        storedTTSService = nil
        await ReadingTTSCache.shared.scheduleRelease()
    }

    /// Skip forward
    public func skipForward() async {
        guard let service = playbackService else { return }

        do {
            try await service.skipForward()
        } catch {
            logger.error("Skip forward failed: \(error.localizedDescription)")
        }
    }

    /// Skip backward
    public func skipBackward() async {
        guard let service = playbackService else { return }

        do {
            try await service.skipBackward()
        } catch {
            logger.error("Skip backward failed: \(error.localizedDescription)")
        }
    }

    /// Start playback from a specific chunk index (for "listen from here" in reader view)
    public func startPlaybackFromChunk(_ chunkIndex: Int32) async {
        currentChunkIndex = chunkIndex

        if state == .paused {
            // If paused, skip to the new position
            guard let service = playbackService else { return }
            do {
                try await service.skipToChunk(chunkIndex)
                await service.resume()
            } catch {
                logger.error("Skip to chunk failed: \(error.localizedDescription)")
            }
        } else {
            // Start fresh from the requested position
            guard let service = playbackService, let itemId = item.id else { return }
            do {
                try await service.startPlayback(
                    itemId: itemId,
                    chunks: chunks,
                    startIndex: chunkIndex
                )
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Bookmarks

    /// Add bookmark at a specific chunk index (or current position if nil)
    public func addBookmark(note: String? = nil, atChunk chunkIndex: Int32? = nil) async {
        let targetIndex = chunkIndex ?? currentChunkIndex

        // When an explicit chunk index is provided (e.g., from reader scroll position),
        // use the direct manager path to ensure the correct position is saved.
        // The playback service path only uses its own currentChunkIndex and ignores
        // any explicit index, so we reserve it for "bookmark at playback position" only.
        if chunkIndex == nil, let service = playbackService {
            do {
                try await service.addBookmark(note: note)
                loadBookmarks()
            } catch {
                errorMessage = "Failed to add bookmark"
                showError = true
            }
        } else if let manager = ReadingListManager.shared, let itemId = item.id {
            do {
                _ = try await manager.addBookmarkById(
                    itemId: itemId,
                    chunkIndex: targetIndex,
                    note: note
                )
                loadBookmarks()
            } catch {
                errorMessage = "Failed to add bookmark"
                showError = true
            }
        }
    }

    /// Jump to a bookmark
    public func jumpToBookmark(_ bookmark: ReadingBookmarkData) async {
        guard let service = playbackService else { return }

        do {
            try await service.jumpToBookmark(bookmark)
        } catch {
            logger.error("Jump to bookmark failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Callback Factory

    /// Create Sendable callbacks that update this view model on the main actor
    private func makeCallbacks() -> ReadingPlaybackCallbacks {
        // Capture weak self to avoid retain cycles
        let weakChunks = chunks

        return ReadingPlaybackCallbacks(
            onStart: { [weak self] in
                self?.state = .playing
            },
            onPause: { [weak self] in
                self?.state = .paused
            },
            onResume: { [weak self] in
                self?.state = .playing
            },
            onStop: { [weak self] in
                self?.state = .idle
            },
            onComplete: { [weak self] in
                self?.state = .completed
            },
            onBuffering: { [weak self] in
                self?.state = .buffering
            },
            onChunkChange: { [weak self] index, total in
                self?.currentChunkIndex = index
                self?.totalChunks = total
                if Int(index) < weakChunks.count {
                    self?.currentChunkText = weakChunks[Int(index)].text
                }
                self?.updateCurrentChunkImages(for: index)
            },
            onError: { [weak self] error in
                self?.state = .error(error.localizedDescription)
                self?.errorMessage = error.localizedDescription
                self?.showError = true
            }
        )
    }

    // MARK: - Service Access (Simplified)

    /// Create or return cached AudioEngine for TTS playback
    private func getAudioEngine() async -> AudioEngine? {
        if let engine = storedAudioEngine { return engine }

        let engine = AudioEngine(vadService: SileroVADService(), telemetry: TelemetryEngine())
        do {
            try await engine.configure(config: .default)
            try await engine.start()
            self.storedAudioEngine = engine
            return engine
        } catch {
            logger.error("Failed to create AudioEngine: \(error.localizedDescription)")
            return nil
        }
    }

    /// Create or return cached TTS service for reading narration.
    /// Uses the platform-wide TTS provider resolution for consistency
    /// with curriculum modules and Knowledge Bowl.
    private func getTTSService() async -> (any TTSService)? {
        if let service = storedTTSService { return service }

        let service = await ReadingTTSCache.shared.getService()
        self.storedTTSService = service
        return service
    }

    // MARK: - Voice Command Monitoring

    /// Valid voice commands for the current playback state
    private func validCommandsForState() -> Set<VoiceCommand>? {
        switch state {
        case .playing:
            return [.bookmark, .flag]
        default:
            return nil
        }
    }

    /// Start monitoring for voice commands during playback.
    /// Called when playback starts or resumes.
    public func startVoiceCommandMonitoring() {
        stopVoiceCommandMonitoring()

        guard let engine = storedAudioEngine else { return }

        voiceMonitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }

                guard let self else { return }
                guard let validCommands = self.validCommandsForState() else { continue }

                // Get the latest transcript from the audio engine
                let transcript = await engine.lastTranscript
                guard !transcript.isEmpty, transcript != self.lastProcessedTranscript else { continue }
                self.lastProcessedTranscript = transcript

                // Check for voice commands
                if let result = await self.voiceCommandRecognizer.recognize(
                    transcript: transcript,
                    validCommands: validCommands
                ), result.shouldExecute {
                    await self.handleVoiceCommand(result.command)
                    self.lastProcessedTranscript = ""
                }
            }
        }
    }

    /// Stop voice command monitoring
    public func stopVoiceCommandMonitoring() {
        voiceMonitoringTask?.cancel()
        voiceMonitoringTask = nil
    }

    /// Handle a recognized voice command
    private func handleVoiceCommand(_ command: VoiceCommand) async {
        switch command {
        case .bookmark:
            await voiceBookmarkService.performBookmark(
                activity: self,
                feedback: voiceFeedback
            )
            loadBookmarks()
        case .flag:
            await voiceBookmarkService.performFlag(
                activity: self,
                feedback: voiceFeedback
            )
            loadBookmarks()
        default:
            break
        }
    }
}

// MARK: - FlaggableActivity Conformance

extension ReadingPlaybackViewModel: FlaggableActivity {

    public var currentSegmentIndex: Int32 {
        currentChunkIndex
    }

    public var totalSegments: Int32 {
        Int32(totalChunks)
    }

    public var currentSegmentText: String? {
        currentChunkText
    }

    public var previousSegmentText: String? {
        let prevIndex = Int(currentChunkIndex) - 1
        guard prevIndex >= 0, prevIndex < chunks.count else { return nil }
        return chunks[prevIndex].text
    }

    public var sourceTitle: String {
        item.title ?? "Reading List Item"
    }

    public var sourceType: ReinforcementSourceType {
        .readingList
    }

    public var sourceId: UUID? {
        item.id
    }

    public func createBookmark(note: String?) async -> UUID? {
        guard let manager = ReadingListManager.shared else { return nil }
        guard let itemId = item.id else {
            logger.error("Cannot create bookmark: reading item has no ID")
            return nil
        }

        do {
            let result = try await manager.addBookmarkById(
                itemId: itemId,
                chunkIndex: currentChunkIndex,
                note: note
            )
            return result.id
        } catch {
            logger.error("Failed to create bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    public func pausePlayback() async {
        guard let service = playbackService, state == .playing else { return }
        await service.pause()
    }

    public func resumePlayback() async {
        guard let service = playbackService, state == .paused else { return }
        await service.resume()
    }
}
