// UnaMentis - Knowledge Bowl Audio Cache
// Client-side cache for pre-generated TTS audio from the server
//
// Fetches and caches audio for KB questions to achieve zero-latency
// playback during practice sessions.

import AVFoundation
import Foundation
import Logging

/// Segment types for KB question audio
enum KBSegmentType: String, Sendable {
    case question
    case answer
    case hint
    case explanation
}

/// Cached audio entry
struct KBCachedAudio: Sendable {
    let data: Data
    let durationSeconds: Double
    let sampleRate: Int
}

/// Batch query result for prefetching
struct KBAudioBatchInfo: Sendable {
    let questionId: String
    let segment: KBSegmentType
    let available: Bool
    let durationSeconds: Double
    let sizeBytes: Int
}

/// Client-side cache for pre-fetched KB TTS audio
actor KBAudioCache {
    // MARK: - Properties

    /// In-memory cache of audio data
    private var cache: [String: KBCachedAudio] = [:]

    /// Questions currently being prefetched
    private var prefetchInProgress: Set<String> = []

    /// Maximum cache size in bytes (50MB default)
    private let maxCacheSize: Int

    /// Server connection
    private let serverHost: String
    private let serverPort: Int

    /// Module ID
    private let moduleId: String

    private static let logger = Logger(label: "com.unamentis.kb.audiocache")

    // MARK: - Initialization

    init(
        serverHost: String,
        serverPort: Int = 8766,
        moduleId: String = "knowledge-bowl",
        maxCacheSize: Int = 50 * 1024 * 1024
    ) {
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.moduleId = moduleId
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Cache Key

    private func cacheKey(questionId: String, segment: KBSegmentType, hintIndex: Int = 0) -> String {
        if segment == .hint {
            return "\(questionId):\(segment.rawValue):\(hintIndex)"
        }
        return "\(questionId):\(segment.rawValue)"
    }

    // MARK: - Public API

    /// Get audio for a question segment, fetching from server if not cached
    func getAudio(
        questionId: String,
        segment: KBSegmentType,
        hintIndex: Int = 0
    ) async throws -> KBCachedAudio? {
        let key = cacheKey(questionId: questionId, segment: segment, hintIndex: hintIndex)

        // Check cache first
        if let cached = cache[key] {
            Self.logger.debug("Cache hit: \(key)")
            return cached
        }

        // Fetch from server
        Self.logger.debug("Cache miss, fetching: \(key)")
        return try await fetchAudio(questionId: questionId, segment: segment, hintIndex: hintIndex)
    }

    /// Check if audio is cached without fetching
    func hasAudio(questionId: String, segment: KBSegmentType, hintIndex: Int = 0) -> Bool {
        let key = cacheKey(questionId: questionId, segment: segment, hintIndex: hintIndex)
        return cache[key] != nil
    }

    /// Prefetch audio for multiple questions
    func prefetchQuestions(
        _ questionIds: [String],
        segments: [KBSegmentType] = [.question, .answer, .explanation]
    ) async {
        for questionId in questionIds {
            // Skip if already being prefetched
            if prefetchInProgress.contains(questionId) {
                continue
            }

            prefetchInProgress.insert(questionId)

            for segment in segments {
                // Skip if already cached
                let key = cacheKey(questionId: questionId, segment: segment)
                if cache[key] != nil {
                    continue
                }

                // Fetch in background
                do {
                    _ = try await fetchAudio(questionId: questionId, segment: segment)
                } catch {
                    Self.logger.warning("Prefetch failed for \(questionId)/\(segment): \(error)")
                }
            }

            prefetchInProgress.remove(questionId)
        }
    }

    /// Warm cache at session start (first N questions)
    func warmCache(questions: [KBQuestion], lookahead: Int = 5) async {
        let questionsToWarm = Array(questions.prefix(lookahead))
        let questionIds = questionsToWarm.map { $0.id }

        Self.logger.info("Warming cache for \(questionIds.count) questions")
        await prefetchQuestions(questionIds)
    }

    /// Prefetch next questions from current position
    func prefetchUpcoming(
        questions: [KBQuestion],
        currentIndex: Int,
        lookahead: Int = 3
    ) async {
        let startIndex = currentIndex + 1
        let endIndex = min(startIndex + lookahead, questions.count)

        guard startIndex < questions.count else { return }

        let upcoming = Array(questions[startIndex..<endIndex])
        let questionIds = upcoming.map { $0.id }

        Self.logger.debug("Prefetching \(questionIds.count) upcoming questions")
        await prefetchQuestions(questionIds)
    }

    /// Clear the cache
    func clear() {
        cache.removeAll()
        Self.logger.info("Cache cleared")
    }

    /// Get current cache size in bytes
    func cacheSize() -> Int {
        cache.values.reduce(0) { $0 + $1.data.count }
    }

    /// Get cache entry count
    func entryCount() -> Int {
        cache.count
    }

    // MARK: - Server Communication

    /// Fetch audio from server
    private func fetchAudio(
        questionId: String,
        segment: KBSegmentType,
        hintIndex: Int = 0
    ) async throws -> KBCachedAudio? {
        var urlString = "http://\(serverHost):\(serverPort)/api/kb/audio/\(questionId)/\(segment.rawValue)"
        urlString += "?module_id=\(moduleId)"
        if segment == .hint {
            urlString += "&hint_index=\(hintIndex)"
        }

        guard let url = URL(string: urlString) else {
            throw KBAudioCacheError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KBAudioCacheError.invalidResponse
        }

        // 404 means audio not pre-generated yet
        if httpResponse.statusCode == 404 {
            Self.logger.debug("Audio not available: \(questionId)/\(segment)")
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw KBAudioCacheError.serverError(httpResponse.statusCode)
        }

        // Parse duration from header
        let durationString = httpResponse.value(forHTTPHeaderField: "X-KB-Duration-Seconds") ?? "0"
        let duration = Double(durationString) ?? 0

        // Parse sample rate from header
        let sampleRateString = httpResponse.value(forHTTPHeaderField: "X-KB-Sample-Rate") ?? "24000"
        let sampleRate = Int(sampleRateString) ?? 24000

        let cached = KBCachedAudio(
            data: data,
            durationSeconds: duration,
            sampleRate: sampleRate
        )

        // Store in cache
        let key = cacheKey(questionId: questionId, segment: segment, hintIndex: hintIndex)
        cache[key] = cached

        // Evict if over size limit
        await evictIfNeeded()

        Self.logger.debug("Cached audio: \(key) (\(data.count) bytes)")
        return cached
    }

    /// Fetch batch info to check what's available
    func fetchBatchInfo(
        questionIds: [String],
        segments: [KBSegmentType] = [.question, .answer, .explanation]
    ) async throws -> [KBAudioBatchInfo] {
        let urlString = "http://\(serverHost):\(serverPort)/api/kb/audio/batch"

        guard let url = URL(string: urlString) else {
            throw KBAudioCacheError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "module_id": moduleId,
            "question_ids": questionIds,
            "segments": segments.map { $0.rawValue }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw KBAudioCacheError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segmentsDict = json["segments"] as? [String: [String: [String: Any]]] else {
            throw KBAudioCacheError.invalidResponse
        }

        var results: [KBAudioBatchInfo] = []

        for (qid, segmentInfo) in segmentsDict {
            for (segType, info) in segmentInfo {
                guard let segment = KBSegmentType(rawValue: segType) else { continue }

                let available = info["available"] as? Bool ?? false
                let duration = info["duration"] as? Double ?? 0
                let size = info["size"] as? Int ?? 0

                results.append(KBAudioBatchInfo(
                    questionId: qid,
                    segment: segment,
                    available: available,
                    durationSeconds: duration,
                    sizeBytes: size
                ))
            }
        }

        return results
    }

    /// Fetch feedback audio (correct/incorrect)
    func getFeedbackAudio(_ feedbackType: String) async throws -> KBCachedAudio? {
        let key = "feedback:\(feedbackType)"

        // Check cache
        if let cached = cache[key] {
            return cached
        }

        let urlString = "http://\(serverHost):\(serverPort)/api/kb/feedback/\(feedbackType)"

        guard let url = URL(string: urlString) else {
            throw KBAudioCacheError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KBAudioCacheError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw KBAudioCacheError.serverError(httpResponse.statusCode)
        }

        let cached = KBCachedAudio(
            data: data,
            durationSeconds: 0.5,  // Short feedback
            sampleRate: 24000
        )

        cache[key] = cached
        return cached
    }

    // MARK: - Cache Management

    /// Evict oldest entries if cache is over size limit
    private func evictIfNeeded() async {
        let currentSize = cacheSize()

        if currentSize <= maxCacheSize {
            return
        }

        // Simple eviction: remove random entries until under limit
        // In practice, could use LRU based on access time
        var keysToRemove: [String] = []
        var sizeToRemove = currentSize - maxCacheSize

        for (key, entry) in cache {
            if sizeToRemove <= 0 { break }
            keysToRemove.append(key)
            sizeToRemove -= entry.data.count
        }

        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }

        Self.logger.info("Evicted \(keysToRemove.count) entries to stay under size limit")
    }
}

// MARK: - Errors

enum KBAudioCacheError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .notAvailable:
            return "Audio not available"
        }
    }
}
