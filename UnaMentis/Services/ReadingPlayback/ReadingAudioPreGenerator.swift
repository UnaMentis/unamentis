// UnaMentis - Reading Audio Pre-Generator
// Background TTS synthesis for initial chunks at import time
//
// Pre-generates audio for the first few chunks so playback starts
// instantly and transitions between early chunks are seamless.
// If the user starts playback while generation is still in progress,
// the playback service waits for the in-progress task rather than
// starting a duplicate synthesis.
//
// Part of Services/ReadingPlayback

import Foundation
import CoreData
import Logging

// MARK: - Chunk Spec

/// Lightweight descriptor for a chunk to pre-generate
public struct PreGenChunkSpec: Sendable {
    public let index: Int32
    public let text: String

    public init(index: Int32, text: String) {
        self.index = index
        self.text = text
    }
}

// MARK: - Reading Audio Pre-Generator

/// Actor that pre-generates TTS audio for the initial chunks of reading list items.
///
/// Triggered after document import, runs in the background. The playback path
/// checks for cached audio and coordinates with in-progress generation to avoid
/// duplicate work.
///
/// Audio is stored as raw PCM Float32 data on the ReadingChunk entity.
/// TODO: Migrate to Opus encoding when project-wide Opus codec is implemented.
public actor ReadingAudioPreGenerator {

    /// Shared singleton instance
    public static let shared = ReadingAudioPreGenerator()

    private let logger = Logger(label: "com.unamentis.reading.audio.pregen")

    /// Number of chunks to pre-generate at import time
    public static let defaultPreGenCount = 3

    /// In-progress generation tasks keyed by item ID.
    /// Callers can await the task value to wait for completion.
    private var inProgressTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - Pre-generation

    /// Pre-generate TTS audio for the initial chunks of a reading item.
    /// Runs in the background and stores results on the Core Data entities.
    ///
    /// Generates chunks sequentially (on-device TTS is single-threaded).
    /// Each chunk's audio is saved to Core Data as soon as it completes,
    /// so partial results are available even if generation is interrupted.
    ///
    /// - Parameters:
    ///   - itemId: The reading item's UUID
    ///   - chunks: The chunks to pre-generate (index + text)
    ///   - persistenceController: Core Data persistence for saving results
    public func preGenerateChunks(
        itemId: UUID,
        chunks: [PreGenChunkSpec],
        persistenceController: PersistenceController
    ) {
        guard !chunks.isEmpty else { return }

        // Don't duplicate if already generating
        guard inProgressTasks[itemId] == nil else {
            logger.debug("Pre-generation already in progress for \(itemId)")
            return
        }

        logger.info("Starting pre-generation for item \(itemId), \(chunks.count) chunks")

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }

            var successCount = 0

            for chunk in chunks {
                guard !Task.isCancelled else { break }

                let audioData = await self.synthesizeChunk(text: chunk.text)

                if let audioData {
                    await self.storeCachedAudioForChunk(
                        audioData,
                        itemId: itemId,
                        chunkIndex: chunk.index,
                        persistenceController: persistenceController
                    )
                    successCount += 1
                    await self.logger.debug(
                        "Pre-generated chunk \(chunk.index) for \(itemId), \(audioData.count) bytes"
                    )
                } else {
                    await self.logger.warning(
                        "Pre-generation failed for chunk \(chunk.index) of \(itemId)"
                    )
                }
            }

            // Mark overall status based on results
            if successCount > 0 {
                await self.markPreGenReady(
                    itemId: itemId,
                    persistenceController: persistenceController
                )
                await self.logger.info(
                    "Pre-generation complete for \(itemId): \(successCount)/\(chunks.count) chunks"
                )
            } else {
                await self.markPreGenFailed(
                    itemId: itemId,
                    persistenceController: persistenceController
                )
                await self.logger.warning("Pre-generation failed for all chunks of \(itemId)")
            }

            await self.removeTask(itemId: itemId)
        }

        inProgressTasks[itemId] = task
    }

    /// Convenience: Pre-generate the first chunk only (backward compatibility).
    public func preGenerateFirstChunk(
        itemId: UUID,
        chunkText: String,
        persistenceController: PersistenceController
    ) {
        preGenerateChunks(
            itemId: itemId,
            chunks: [PreGenChunkSpec(index: 0, text: chunkText)],
            persistenceController: persistenceController
        )
    }

    /// Wait for an in-progress pre-generation to complete.
    /// Returns nil immediately if no generation is in progress.
    public func waitForPreGeneration(itemId: UUID) async -> Data? {
        guard let task = inProgressTasks[itemId] else {
            return nil
        }
        await task.value
        return nil
    }

    /// Check if pre-generation is currently in progress for an item
    public func isGenerating(itemId: UUID) -> Bool {
        inProgressTasks[itemId] != nil
    }

    // MARK: - Private

    private func removeTask(itemId: UUID) {
        inProgressTasks.removeValue(forKey: itemId)
    }

    /// Synthesize audio for a chunk of text using the configured TTS provider
    private func synthesizeChunk(text: String) async -> Data? {
        // Use the platform-wide TTS provider for consistency with playback
        let ttsService = await MainActor.run {
            TTSProvider.resolveConfiguredService()
        }

        do {
            // Pre-warm the model if it's Pocket TTS
            if let pocketService = ttsService as? KyutaiPocketTTSService {
                try await pocketService.ensureLoaded()
            }

            // Synthesize and collect all audio segments
            let audioStream = try await ttsService.synthesize(text: text)
            var allAudioData = Data()

            for await audioChunk in audioStream {
                allAudioData.append(audioChunk.audioData)
            }

            guard !allAudioData.isEmpty else {
                logger.warning("TTS produced empty audio")
                return nil
            }

            logger.debug("Synthesized \(allAudioData.count) bytes")
            return allAudioData
        } catch {
            logger.error("TTS synthesis failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Store pre-generated audio data on a specific ReadingChunk entity
    private func storeCachedAudioForChunk(
        _ audioData: Data,
        itemId: UUID,
        chunkIndex: Int32,
        persistenceController: PersistenceController
    ) async {
        await MainActor.run {
            let context = persistenceController.viewContext

            let request = ReadingListItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", itemId as CVarArg)
            request.fetchLimit = 1

            guard let item = try? context.fetch(request).first else {
                return
            }

            guard let chunk = item.chunksArray.first(where: { $0.index == chunkIndex }) else {
                return
            }

            // Only write if not already cached (avoid overwriting)
            guard !chunk.hasCachedAudio else { return }

            chunk.cachedAudioData = audioData
            chunk.cachedAudioSampleRate = 24000 // Pocket TTS / platform TTS output rate

            try? persistenceController.save()
        }
    }

    /// Mark pre-generation as ready on the item
    private func markPreGenReady(
        itemId: UUID,
        persistenceController: PersistenceController
    ) async {
        await MainActor.run {
            let context = persistenceController.viewContext
            let request = ReadingListItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", itemId as CVarArg)
            request.fetchLimit = 1

            guard let item = try? context.fetch(request).first else { return }
            item.audioPreGenStatus = .ready
            try? persistenceController.save()
        }
    }

    /// Mark pre-generation as failed on the item
    private func markPreGenFailed(
        itemId: UUID,
        persistenceController: PersistenceController
    ) async {
        await MainActor.run {
            let context = persistenceController.viewContext
            let request = ReadingListItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", itemId as CVarArg)
            request.fetchLimit = 1

            guard let item = try? context.fetch(request).first else { return }
            item.audioPreGenStatus = .failed
            try? persistenceController.save()
        }
    }
}
