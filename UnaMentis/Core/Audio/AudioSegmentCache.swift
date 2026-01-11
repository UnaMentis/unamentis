// AudioSegmentCache.swift
// UnaMentis
//
// Caches audio segments for the current topic to enable instant replay and segment navigation.

import Foundation
import os.log

/// Manages cached audio segments for the current topic.
/// Enables instant replay, segment rewind, and topic replay.
public actor AudioSegmentCache {
    private let logger = Logger(subsystem: "com.unamentis", category: "AudioSegmentCache")

    /// Cached segment data structure
    public struct CachedSegment: Sendable {
        public let index: Int
        public let text: String
        public let audioData: Data

        public init(index: Int, text: String, audioData: Data) {
            self.index = index
            self.text = text
            self.audioData = audioData
        }
    }

    /// All cached segments for current topic (keyed by index)
    private var segments: [Int: CachedSegment] = [:]

    /// Maximum cache size in bytes (50MB default)
    private let maxCacheBytes: Int

    /// Current cache size in bytes
    private var currentCacheBytes: Int = 0

    /// Topic ID for the currently cached content
    private var currentTopicId: String?

    public init(maxCacheMB: Int = 50) {
        self.maxCacheBytes = maxCacheMB * 1024 * 1024
    }

    /// Cache a segment (called when audio is received during streaming)
    /// - Parameters:
    ///   - index: Segment index
    ///   - text: Segment text content
    ///   - audioData: Raw audio data (WAV format)
    ///   - topicId: Optional topic ID to track which topic this belongs to
    public func cacheSegment(index: Int, text: String, audioData: Data, topicId: String? = nil) {
        // If we're caching for a different topic, clear first
        if let topicId = topicId, let currentId = currentTopicId, currentId != topicId {
            logger.info("Topic changed from \(currentId) to \(topicId), clearing cache")
            clearCacheInternal()
        }

        if let topicId = topicId {
            currentTopicId = topicId
        }

        // Calculate new size accounting for any existing segment at this index
        let existingSize = segments[index]?.audioData.count ?? 0
        let newSize = currentCacheBytes - existingSize + audioData.count

        // Check if we'd exceed cache limit
        if newSize > maxCacheBytes {
            logger.warning("Cache limit reached (\(newSize) > \(self.maxCacheBytes)), not caching segment \(index)")
            return
        }

        // Update cache
        let segment = CachedSegment(index: index, text: text, audioData: audioData)
        segments[index] = segment
        currentCacheBytes = newSize

        logger.debug("Cached segment \(index) (\(audioData.count) bytes), total cache: \(self.currentCacheBytes) bytes, \(self.segments.count) segments")
    }

    /// Get a cached segment by index
    /// - Parameter index: Segment index to retrieve
    /// - Returns: Cached segment if available
    public func getSegment(at index: Int) -> CachedSegment? {
        return segments[index]
    }

    /// Get all cached segments sorted by index
    /// - Returns: Array of all cached segments in order
    public func getAllSegments() -> [CachedSegment] {
        return segments.values.sorted { $0.index < $1.index }
    }

    /// Get segments from a specific index onward
    /// - Parameter startIndex: Starting index (inclusive)
    /// - Returns: Array of segments from startIndex onward, sorted by index
    public func getSegments(from startIndex: Int) -> [CachedSegment] {
        return segments.values
            .filter { $0.index >= startIndex }
            .sorted { $0.index < $1.index }
    }

    /// Clear all cached segments (called when moving to next topic)
    public func clearCache() {
        clearCacheInternal()
    }

    private func clearCacheInternal() {
        let previousCount = segments.count
        let previousSize = currentCacheBytes
        segments.removeAll()
        currentCacheBytes = 0
        currentTopicId = nil
        logger.info("Cleared cache: \(previousCount) segments, \(previousSize) bytes")
    }

    /// Get cache statistics
    public var segmentCount: Int {
        return segments.count
    }

    /// Get total cached bytes
    public var totalCachedBytes: Int {
        return currentCacheBytes
    }

    /// Check if a segment is cached
    public func hasSegment(at index: Int) -> Bool {
        return segments[index] != nil
    }

    /// Get the range of cached segment indices
    public var cachedRange: ClosedRange<Int>? {
        guard !segments.isEmpty else { return nil }
        let indices = segments.keys
        guard let minIndex = indices.min(), let maxIndex = indices.max() else { return nil }
        return minIndex...maxIndex
    }
}
