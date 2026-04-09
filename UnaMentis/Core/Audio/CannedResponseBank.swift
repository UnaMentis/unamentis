// UnaMentis - Canned Response Bank
// Pre-rendered TTS audio clips for instant acknowledgment during barge-in
//
// Part of Zero-Latency Response System
//
// Provides instant audio responses while the LLM generates a real answer.
// Clips are pre-rendered at app launch using the active TTS provider.

import Foundation
import Logging

/// Manages a bank of pre-rendered TTS audio clips for instant acknowledgments
///
/// The bank pre-generates audio for common response phrases at launch,
/// then serves them instantly (<10ms) when a user barges in during playback.
/// This eliminates the perceived latency gap between user speech and AI response.
public actor CannedResponseBank {

    // MARK: - Types

    /// A pre-rendered audio clip ready for instant playback
    public struct AudioClip: Sendable {
        /// The text that was rendered
        public let text: String
        /// The intent category
        public let intent: ResponseIntent
        /// Audio data (PCM or encoded, depending on TTS provider)
        public let audioData: Data
        /// Duration in seconds
        public let duration: TimeInterval
    }

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.cannedresponse")

    /// Pre-rendered clips indexed by intent
    private var clips: [ResponseIntent: [AudioClip]] = [:]

    /// Track which clips were recently used to avoid repetition
    private var recentlyUsed: [ResponseIntent: Set<String>] = [:]

    /// Whether the bank has been populated
    public private(set) var isReady: Bool = false

    /// TTS service used for rendering
    private weak var ttsServiceHolder: AnyObject?

    // MARK: - Initialization

    public init() {
        for intent in ResponseIntent.allCases {
            clips[intent] = []
            recentlyUsed[intent] = []
        }
    }

    // MARK: - Bank Population

    /// Pre-render all canned responses using the provided TTS service
    /// Call this at app launch or when TTS provider changes
    /// - Parameter ttsService: TTS service to use for rendering
    public func populate(using ttsService: any TTSService) async {
        logger.info("Populating canned response bank...")

        var totalClips = 0

        for intent in ResponseIntent.allCases {
            var intentClips: [AudioClip] = []

            for phrase in intent.phrases {
                do {
                    let stream = try await ttsService.synthesize(text: phrase)
                    var combinedData = Data()
                    for await chunk in stream {
                        combinedData.append(chunk.audioData)
                    }
                    guard !combinedData.isEmpty else { continue }
                    let clip = AudioClip(
                        text: phrase,
                        intent: intent,
                        audioData: combinedData,
                        duration: estimateDuration(dataSize: combinedData.count)
                    )
                    intentClips.append(clip)
                    totalClips += 1
                } catch {
                    logger.warning(
                        "Failed to render canned response",
                        metadata: [
                            "phrase": .string(phrase),
                            "intent": .string(intent.rawValue),
                            "error": .string(error.localizedDescription)
                        ]
                    )
                }
            }

            clips[intent] = intentClips
        }

        isReady = totalClips > 0
        logger.info(
            "Canned response bank populated",
            metadata: ["totalClips": .stringConvertible(totalClips)]
        )
    }

    // MARK: - Response Selection

    /// Get a canned response for the given intent
    /// Avoids repeating recently used phrases within the same intent
    /// - Parameter intent: The classified intent
    /// - Returns: A pre-rendered audio clip, or nil if none available
    public func getResponse(for intent: ResponseIntent) -> AudioClip? {
        guard let intentClips = clips[intent], !intentClips.isEmpty else {
            return nil
        }

        let used = recentlyUsed[intent] ?? []

        // Find a clip not recently used
        let available = intentClips.filter { !used.contains($0.text) }

        // If all have been used, reset and pick from full set
        let candidates = available.isEmpty ? intentClips : available
        if available.isEmpty {
            recentlyUsed[intent] = []
        }

        guard let selected = candidates.randomElement() else {
            return nil
        }

        // Track as recently used
        recentlyUsed[intent, default: []].insert(selected.text)

        // Keep recently-used set bounded (retain last N-1 to always have options)
        if let used = recentlyUsed[intent], used.count >= intentClips.count - 1 {
            recentlyUsed[intent] = [selected.text]
        }

        return selected
    }

    /// Get a response for a user utterance (classifies intent automatically)
    /// - Parameter utterance: The user's spoken text
    /// - Returns: A pre-rendered audio clip, or nil if none available
    public func getResponse(forUtterance utterance: String) -> AudioClip? {
        let intent = ResponseIntent.classify(from: utterance)
        return getResponse(for: intent)
    }

    /// Clear all pre-rendered clips (e.g., when TTS provider changes)
    public func clear() {
        clips = [:]
        recentlyUsed = [:]
        isReady = false
        for intent in ResponseIntent.allCases {
            clips[intent] = []
            recentlyUsed[intent] = []
        }
        logger.info("Canned response bank cleared")
    }

    // MARK: - Helpers

    /// Rough duration estimate from audio data size
    /// Assumes 16kHz 16-bit mono PCM (~32KB/sec)
    private func estimateDuration(dataSize: Int) -> TimeInterval {
        let bytesPerSecond = 32_000.0 // 16kHz * 16-bit * mono
        return Double(dataSize) / bytesPerSecond
    }
}
