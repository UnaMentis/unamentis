// UnaMentis - Audio Pre-Generation Invalidator
// Clears cached pre-generated audio when TTS provider or voice settings change
//
// When a user changes their TTS provider or voice, all pre-generated audio
// becomes stale (wrong voice). This actor listens for those setting changes
// and clears the cached audio from Core Data ReadingChunk entities.

import Foundation
import CoreData
import Logging

/// Monitors TTS setting changes and invalidates pre-generated audio caches
@MainActor
public final class AudioPreGenInvalidator {

    public static let shared = AudioPreGenInvalidator()

    private let logger = Logger(label: "com.unamentis.audio.pregen.invalidator")

    /// UserDefaults keys that trigger invalidation when changed
    private let watchedKeys = ["ttsProvider", "ttsVoice", "pocketTTSVoiceId"]

    /// Last known values for change detection
    private var lastKnownValues: [String: String] = [:]

    private var observationTask: Task<Void, Never>?

    private init() {
        // Capture initial values
        for key in watchedKeys {
            lastKnownValues[key] = UserDefaults.standard.string(forKey: key) ?? ""
        }
    }

    /// Start observing TTS setting changes
    public func startObserving() {
        observationTask?.cancel()

        observationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: UserDefaults.didChangeNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                self?.checkForChanges()
            }
        }

        logger.info("AudioPreGenInvalidator started observing TTS setting changes")
    }

    /// Stop observing
    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    private func checkForChanges() {
        var changed = false

        for key in watchedKeys {
            let currentValue = UserDefaults.standard.string(forKey: key) ?? ""
            if currentValue != lastKnownValues[key] {
                logger.info("TTS setting changed: \(key) = \(currentValue)")
                lastKnownValues[key] = currentValue
                changed = true
            }
        }

        if changed {
            invalidateAllPreGeneratedAudio()
        }
    }

    /// Clear all pre-generated audio from ReadingChunk entities
    private func invalidateAllPreGeneratedAudio() {
        logger.info("Invalidating all pre-generated audio due to TTS setting change")

        let log = logger
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "ReadingChunk")
            fetchRequest.predicate = NSPredicate(format: "cachedAudioData != nil")

            do {
                let chunks = try context.fetch(fetchRequest)
                var clearedCount = 0
                for chunk in chunks {
                    chunk.setValue(nil, forKey: "cachedAudioData")
                    clearedCount += 1
                }
                if clearedCount > 0 {
                    try context.save()
                    log.info("Cleared pre-generated audio from \(clearedCount) chunks")
                }
            } catch {
                log.error("Failed to clear pre-generated audio: \(error)")
            }
        }
    }
}
