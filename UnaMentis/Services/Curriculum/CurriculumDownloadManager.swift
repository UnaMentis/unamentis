// UnaMentis - Curriculum Download Manager
// Handles background downloading of curricula with topic-level granularity and progress tracking
//
// Part of Curriculum Layer (TDD Section 4)

import Foundation
import CoreData
import Logging
import Combine

// MARK: - Download State

/// Represents the download state of a curriculum or topic
public enum DownloadState: Sendable, Equatable {
    case notStarted
    case queued
    case downloading(progress: Double)
    case completed
    case failed(String)
    case paused

    public var isActive: Bool {
        switch self {
        case .queued, .downloading:
            return true
        default:
            return false
        }
    }
}

/// Represents a downloadable topic within a curriculum
public struct DownloadableTopicInfo: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let orderIndex: Int
    public let estimatedSize: Int64 // bytes
    public let hasAssets: Bool
    public let segmentCount: Int
    public var isSelected: Bool
    public var downloadState: DownloadState

    public init(
        id: String,
        title: String,
        description: String,
        orderIndex: Int,
        estimatedSize: Int64 = 0,
        hasAssets: Bool = false,
        segmentCount: Int = 0,
        isSelected: Bool = true,
        downloadState: DownloadState = .notStarted
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.orderIndex = orderIndex
        self.estimatedSize = estimatedSize
        self.hasAssets = hasAssets
        self.segmentCount = segmentCount
        self.isSelected = isSelected
        self.downloadState = downloadState
    }
}

/// Overall download progress for a curriculum
public struct CurriculumDownloadProgress: Sendable {
    public let curriculumId: String
    public let curriculumTitle: String
    public var overallProgress: Double // 0.0 - 1.0
    public var topicsCompleted: Int
    public var topicsTotal: Int
    public var bytesDownloaded: Int64
    public var bytesTotal: Int64
    public var state: DownloadState
    public var currentTopicTitle: String?
    public var topics: [DownloadableTopicInfo]

    public init(
        curriculumId: String,
        curriculumTitle: String,
        overallProgress: Double = 0,
        topicsCompleted: Int = 0,
        topicsTotal: Int = 0,
        bytesDownloaded: Int64 = 0,
        bytesTotal: Int64 = 0,
        state: DownloadState = .notStarted,
        currentTopicTitle: String? = nil,
        topics: [DownloadableTopicInfo] = []
    ) {
        self.curriculumId = curriculumId
        self.curriculumTitle = curriculumTitle
        self.overallProgress = overallProgress
        self.topicsCompleted = topicsCompleted
        self.topicsTotal = topicsTotal
        self.bytesDownloaded = bytesDownloaded
        self.bytesTotal = bytesTotal
        self.state = state
        self.currentTopicTitle = currentTopicTitle
        self.topics = topics
    }
}

// MARK: - Download Manager

/// Observable class for managing curriculum downloads with background processing and progress tracking
@MainActor
public final class CurriculumDownloadManager: ObservableObject {
    private static let logger = Logger(label: "com.unamentis.curriculum.download")

    private let session: URLSession
    private var baseURL: URL?

    // Active downloads tracking
    @Published public private(set) var activeDownloads: [String: CurriculumDownloadProgress] = [:]

    public init() {
        // Use shared session - simpler and works correctly
        self.session = URLSession.shared
    }

    // MARK: - Configuration

    public func configure(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func configure(host: String, port: Int) throws {
        guard let url = URL(string: "http://\(host):\(port)") else {
            throw CurriculumServiceError.invalidURL
        }
        self.baseURL = url
    }

    // MARK: - Download Management

    /// Get current download progress for a curriculum
    public func getProgress(for curriculumId: String) -> CurriculumDownloadProgress? {
        activeDownloads[curriculumId]
    }

    /// Check if a download is active
    public func isDownloading(_ curriculumId: String) -> Bool {
        activeDownloads[curriculumId]?.state.isActive ?? false
    }

    /// Cancel a download
    public func cancelDownload(for curriculumId: String) {
        if var progress = activeDownloads[curriculumId] {
            progress.state = .notStarted
            activeDownloads.removeValue(forKey: curriculumId)
        }

        Self.logger.info("Cancelled download for curriculum: \(curriculumId)")
    }

    // MARK: - Download Execution

    /// Download selected topics from a curriculum
    /// Returns the imported Curriculum Core Data object
    public func downloadCurriculum(
        id curriculumId: String,
        title curriculumTitle: String,
        selectedTopicIds: Set<String>
    ) async throws -> Curriculum {
        guard let baseURL = baseURL else {
            throw CurriculumServiceError.noServerConfigured
        }

        Self.logger.info("Starting download for curriculum: \(curriculumTitle) with \(selectedTopicIds.count) topics")

        // Initialize progress
        var progress = CurriculumDownloadProgress(
            curriculumId: curriculumId,
            curriculumTitle: curriculumTitle,
            topicsTotal: selectedTopicIds.count,
            state: .downloading(progress: 0)
        )
        updateProgress(progress)

        // Fetch the full curriculum with assets
        progress.currentTopicTitle = "Connecting to server..."
        updateProgress(progress)

        let url = baseURL.appendingPathComponent("api/curricula/\(curriculumId)/full-with-assets")
        Self.logger.info("Fetching from URL: \(url.absoluteString)")

        let data: Data
        let response: URLResponse

        do {
            Self.logger.info("Starting network request...")
            (data, response) = try await session.data(from: url)
            Self.logger.info("Network request completed, received \(data.count) bytes")
        } catch {
            Self.logger.error("Network request failed: \(error)")
            progress.state = .failed("Network error: \(error.localizedDescription)")
            updateProgress(progress)
            throw CurriculumServiceError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let error = CurriculumServiceError.networkError("Invalid response")
            progress.state = .failed(error.localizedDescription ?? "Network error")
            updateProgress(progress)
            throw error
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)
            let error = CurriculumServiceError.serverError(httpResponse.statusCode, message)
            progress.state = .failed(error.localizedDescription ?? "Server error")
            updateProgress(progress)
            throw error
        }

        progress.currentTopicTitle = "Processing curriculum data..."
        progress.overallProgress = 0.3
        progress.state = .downloading(progress: 0.3)
        updateProgress(progress)

        // Decode the UMCF document
        let document: UMCFDocument
        do {
            document = try JSONDecoder().decode(UMCFDocument.self, from: data)
        } catch let decodingError as DecodingError {
            let errorDetail = formatDecodingError(decodingError)
            progress.state = .failed(errorDetail)
            updateProgress(progress)
            throw CurriculumServiceError.decodingError(errorDetail)
        }

        // Filter topics if not downloading all
        let filteredDocument: UMCFDocument
        let totalTopics = document.content.first?.children?.count ?? 0
        if !selectedTopicIds.isEmpty && selectedTopicIds.count < totalTopics {
            filteredDocument = filterDocument(document, keepingTopicIds: selectedTopicIds)
        } else {
            filteredDocument = document
        }

        progress.currentTopicTitle = "Importing to database..."
        progress.overallProgress = 0.5
        progress.state = .downloading(progress: 0.5)
        updateProgress(progress)

        // Import to Core Data using static method (avoids actor isolation issues)
        // Pass selectedTopicIds to filter which topics get imported
        let curriculum = try UMCFParser.importDocument(filteredDocument, replaceExisting: true, selectedTopicIds: selectedTopicIds)

        // Extract and cache assets
        progress.currentTopicTitle = "Caching visual assets..."
        progress.overallProgress = 0.7
        progress.state = .downloading(progress: 0.7)
        updateProgress(progress)

        // Extract asset data from response
        var assetDataMap: [String: Data] = [:]
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let assetDataDict = jsonObject["assetData"] as? [String: [String: Any]] {

            let selectedTopicAssetIds = getAssetIdsForTopics(document: filteredDocument, topicIds: selectedTopicIds)

            for (assetId, assetInfo) in assetDataDict {
                // Only cache assets for selected topics (or all if no selection)
                if selectedTopicIds.isEmpty || selectedTopicAssetIds.contains(assetId) {
                    if let base64String = assetInfo["data"] as? String,
                       let binaryData = Data(base64Encoded: base64String) {
                        assetDataMap[assetId] = binaryData
                    }
                }
            }
        }

        // Cache assets
        let assetCache = VisualAssetCache.shared
        let totalAssets = assetDataMap.count
        var cachedAssets = 0

        for (assetId, assetData) in assetDataMap {
            do {
                try await assetCache.cache(assetId: assetId, data: assetData)
                cachedAssets += 1

                let assetProgress = 0.7 + (0.25 * Double(cachedAssets) / Double(max(totalAssets, 1)))
                progress.overallProgress = assetProgress
                progress.state = .downloading(progress: assetProgress)
                updateProgress(progress)
            } catch {
                Self.logger.warning("Failed to cache asset \(assetId): \(error)")
            }
        }

        // Update Core Data entities with cached data
        if let topics = curriculum.topics as? Set<Topic> {
            for topic in topics {
                for asset in topic.visualAssetSet {
                    if let assetId = asset.assetId, let assetData = assetDataMap[assetId] {
                        asset.cachedData = assetData
                    }
                }
            }

            if curriculum.managedObjectContext?.hasChanges == true {
                try curriculum.managedObjectContext?.save()
            }
        }

        // Complete
        progress.overallProgress = 1.0
        progress.topicsCompleted = selectedTopicIds.isEmpty ? totalTopics : selectedTopicIds.count
        progress.state = .completed
        progress.currentTopicTitle = nil
        updateProgress(progress)

        // Remove from active downloads after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            self.activeDownloads.removeValue(forKey: curriculumId)
        }

        Self.logger.info("Successfully downloaded curriculum: \(curriculumTitle) with \(cachedAssets) assets")

        // Trigger server-side TTS pre-generation for the first topics.
        // The server's CurriculumPrefetcher will generate audio in the background
        // so it's ready when the user starts the curriculum.
        Task {
            await Self.triggerServerTTSPrefetch(
                curriculumId: curriculumId,
                topicIds: Array(selectedTopicIds)
            )
        }

        return curriculum
    }

    /// Request server-side TTS pre-generation for curriculum topics
    private static func triggerServerTTSPrefetch(curriculumId: String, topicIds: [String]) async {
        let selfHostedEnabled = UserDefaults.standard.bool(forKey: "selfHostedEnabled")
        let serverIP = UserDefaults.standard.string(forKey: "serverIP") ?? ""

        guard selfHostedEnabled, !serverIP.isEmpty else {
            logger.debug("Server not configured, skipping TTS prefetch for curriculum \(curriculumId)")
            return
        }

        let urlString = "http://\(serverIP):8766/api/tts-cache/prefetch"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "curriculumId": curriculumId,
            "topicIds": topicIds,
            "priority": "prefetch"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                logger.info("Server TTS prefetch started for curriculum \(curriculumId)")
            } else {
                logger.warning("Server TTS prefetch request returned non-200 for curriculum \(curriculumId)")
            }
        } catch {
            logger.debug("Server TTS prefetch unavailable for curriculum \(curriculumId): \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func updateProgress(_ progress: CurriculumDownloadProgress) {
        activeDownloads[progress.curriculumId] = progress
    }

    /// Filter a UMCF document to only include selected topics
    private func filterDocument(_ document: UMCFDocument, keepingTopicIds: Set<String>) -> UMCFDocument {
        // For now, return the full document since filtering requires reconstructing
        // the entire document structure. The server already supports filtering.
        // TODO: Implement topic-level filtering if needed for bandwidth optimization
        return document
    }

    /// Get asset IDs for specific topics
    private func getAssetIdsForTopics(document: UMCFDocument, topicIds: Set<String>) -> Set<String> {
        var assetIds = Set<String>()

        guard let root = document.content.first,
              let children = root.children else {
            return assetIds
        }

        for topic in children {
            let topicIdValue = topic.id.value
            if topicIds.isEmpty || topicIds.contains(topicIdValue) {
                if let media = topic.media {
                    for asset in (media.embedded ?? []) + (media.reference ?? []) {
                        assetIds.insert(asset.id)
                    }
                }
            }
        }

        return assetIds
    }

    private func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Missing key '\(key.stringValue)' at path: \(path.isEmpty ? "root" : path)"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Type mismatch: expected \(type) at path: \(path.isEmpty ? "root" : path)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Value not found: expected \(type) at path: \(path.isEmpty ? "root" : path)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Data corrupted at path: \(path.isEmpty ? "root" : path)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

// MARK: - Singleton Access

extension CurriculumDownloadManager {
    public static let shared = CurriculumDownloadManager()
}
