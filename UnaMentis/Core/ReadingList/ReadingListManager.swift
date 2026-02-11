// UnaMentis - Reading List Manager
// Manages CRUD operations for reading list items
//
// Key responsibility: Import-time chunking for low-latency playback
// Text is segmented into TTS-ready chunks during import, not at playback.
//
// Part of Core/ReadingList

import Foundation
import CoreData
import Logging

/// Actor responsible for managing reading list items
///
/// Responsibilities:
/// - Import documents with text extraction and chunking
/// - CRUD operations for reading items
/// - Position tracking and auto-save
/// - Bookmark management
public actor ReadingListManager {

    // MARK: - Properties

    private let persistenceController: PersistenceController
    private let chunker: ReadingTextChunker
    private let webFetcher: WebArticleFetcher
    private let logger = Logger(label: "com.unamentis.readinglist.manager")

    /// Directory for storing imported documents (computed once at init)
    private let documentsDirectoryPath: String

    /// Shared instance for convenience
    @MainActor
    public static var shared: ReadingListManager?

    // MARK: - Initialization

    /// Initialize reading list manager with persistence controller
    /// - Parameters:
    ///   - persistenceController: Core Data persistence controller
    ///   - chunkingConfig: Configuration for text chunking
    public init(
        persistenceController: PersistenceController,
        chunkingConfig: ChunkingConfig = .default
    ) {
        self.persistenceController = persistenceController
        self.chunker = ReadingTextChunker(config: chunkingConfig)
        self.webFetcher = WebArticleFetcher()

        // Create documents directory for reading list
        let appDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let documentsDirectory = appDocuments.appendingPathComponent("ReadingList", isDirectory: true)
        self.documentsDirectoryPath = documentsDirectory.path

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)

        logger.info("ReadingListManager initialized")
    }

    // MARK: - Import Operations

    /// Import a document into the reading list
    /// - Parameters:
    ///   - url: Source file URL (will be copied to app storage)
    ///   - title: Optional custom title (defaults to filename)
    ///   - author: Optional author name
    /// - Returns: Created ReadingListItem with pre-chunked text
    @MainActor
    public func importDocument(
        from url: URL,
        title: String? = nil,
        author: String? = nil
    ) async throws -> ReadingListItem {
        // Detect source type
        guard let sourceType = ReadingListSourceType.from(url: url) else {
            throw ReadingListError.unsupportedFileType(url.pathExtension)
        }

        logger.info("Importing document: \(url.lastPathComponent) [\(sourceType.displayName)]")

        // Copy file to app storage (nonisolated file operations)
        let destinationURL = try Self.copyFile(from: url, toDirectory: documentsDirectoryPath)

        // Get file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0

        // Compute file hash for deduplication
        let fileHash = try Self.computeHash(at: destinationURL)

        // Check for duplicates
        if let existingItem = try findItemByHash(fileHash) {
            logger.warning("Duplicate document detected: \(existingItem.title ?? "Unknown")")
            // Clean up the copied file
            try? FileManager.default.removeItem(at: destinationURL)
            throw ReadingListError.duplicateDocument(existingItem.title ?? "Unknown")
        }

        // Extract text, chunk, and extract images
        let result = try await chunker.processDocumentWithImages(
            from: destinationURL,
            sourceType: sourceType
        )

        guard !result.chunks.isEmpty else {
            // Clean up if no text extracted
            try? FileManager.default.removeItem(at: destinationURL)
            throw ReadingListError.noTextContent
        }

        // Create Core Data entities
        let context = persistenceController.viewContext

        let item = ReadingListItem(context: context)
        item.configure(
            title: title ?? url.deletingPathExtension().lastPathComponent,
            sourceType: sourceType,
            fileURL: destinationURL,
            author: author
        )
        item.fileHash = fileHash
        item.fileSizeBytes = fileSize

        // Create chunk entities
        for chunkData in result.chunks {
            let chunk = ReadingChunk(context: context)
            chunk.configure(
                index: Int32(chunkData.index),
                text: chunkData.text,
                characterOffset: chunkData.characterOffset,
                estimatedDuration: chunkData.estimatedDurationSeconds
            )
            item.addToChunks(chunk)
        }

        // Create visual asset entities for extracted images
        if !result.images.isEmpty {
            let imagesDir = Self.imagesDirectory(forDocumentDir: documentsDirectoryPath)
            for mappedImage in result.images {
                let asset = ReadingVisualAsset(context: context)
                let localPath = Self.saveImageToDisk(
                    mappedImage.imageData,
                    directory: imagesDir
                )
                asset.configure(
                    chunkIndex: Int32(mappedImage.chunkIndex),
                    pageIndex: Int32(mappedImage.pageIndex),
                    positionOnPage: mappedImage.positionOnPage,
                    width: Int32(mappedImage.width),
                    height: Int32(mappedImage.height),
                    localPath: localPath
                )
                item.addToVisualAssets(asset)
            }
            logger.info("Created \(result.images.count) visual assets")
        }

        try persistenceController.save()
        logger.info(
            "Imported document with \(result.chunks.count) chunks: \(item.title ?? "Unknown")"
        )

        // Pre-generate TTS audio for the initial chunks in the background.
        // This runs asynchronously so it doesn't block the import flow.
        // Generating chunks 0-2 ensures seamless playback start with no
        // buffering during the first ~48 seconds of listening.
        if let itemId = item.id, !result.chunks.isEmpty {
            let preGenCount = min(
                ReadingAudioPreGenerator.defaultPreGenCount,
                result.chunks.count
            )
            let specs = result.chunks.prefix(preGenCount).map {
                PreGenChunkSpec(index: Int32($0.index), text: $0.text)
            }
            item.audioPreGenStatus = .generating
            try? persistenceController.save()
            await ReadingAudioPreGenerator.shared.preGenerateChunks(
                itemId: itemId,
                chunks: specs,
                persistenceController: persistenceController
            )
        }

        return item
    }

    /// Import a web article from a URL into the reading list
    /// - Parameters:
    ///   - url: Web page URL to fetch and extract
    ///   - title: Optional custom title (defaults to extracted title)
    ///   - author: Optional author name (defaults to extracted author)
    /// - Returns: Created ReadingListItem with pre-chunked text
    @MainActor
    public func importWebArticle(
        from url: URL,
        title: String? = nil,
        author: String? = nil
    ) async throws -> ReadingListItem {
        logger.info("Importing web article: \(url.absoluteString)")

        // Fetch and extract article content
        let article = try await webFetcher.fetchArticle(from: url)

        guard !article.text.isEmpty else {
            throw ReadingListError.noTextContent
        }

        // Save extracted text to a file in app storage
        let filename = UUID().uuidString + "_article.txt"
        let destinationURL = URL(fileURLWithPath: documentsDirectoryPath)
            .appendingPathComponent(filename)
        try article.text.write(to: destinationURL, atomically: true, encoding: .utf8)

        // Compute hash for dedup (hash the extracted text, not the HTML)
        let textData = article.text.data(using: .utf8) ?? Data()
        let fileHash = textData.sha256Hash

        // Check for duplicates
        if let existingItem = try findItemByHash(fileHash) {
            logger.warning("Duplicate article detected: \(existingItem.title ?? "Unknown")")
            try? FileManager.default.removeItem(at: destinationURL)
            throw ReadingListError.duplicateDocument(existingItem.title ?? "Unknown")
        }

        // Chunk the extracted text
        let result = try await chunker.processDocumentWithImages(
            from: destinationURL,
            sourceType: .webArticle
        )

        guard !result.chunks.isEmpty else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw ReadingListError.noTextContent
        }

        // Create Core Data entities
        let context = persistenceController.viewContext

        let item = ReadingListItem(context: context)
        item.configure(
            title: title ?? article.title ?? url.host ?? "Web Article",
            sourceType: .webArticle,
            fileURL: destinationURL,
            author: author ?? article.author
        )
        item.fileHash = fileHash
        item.fileSizeBytes = Int64(textData.count)

        // Create chunk entities
        for chunkData in result.chunks {
            let chunk = ReadingChunk(context: context)
            chunk.configure(
                index: Int32(chunkData.index),
                text: chunkData.text,
                characterOffset: chunkData.characterOffset,
                estimatedDuration: chunkData.estimatedDurationSeconds
            )
            item.addToChunks(chunk)
        }

        try persistenceController.save()
        logger.info(
            "Imported web article with \(result.chunks.count) chunks: \(item.title ?? "Unknown")"
        )

        // Pre-generate TTS audio for the initial chunks in the background
        if let itemId = item.id, !result.chunks.isEmpty {
            let preGenCount = min(
                ReadingAudioPreGenerator.defaultPreGenCount,
                result.chunks.count
            )
            let specs = result.chunks.prefix(preGenCount).map {
                PreGenChunkSpec(index: Int32($0.index), text: $0.text)
            }
            item.audioPreGenStatus = .generating
            try? persistenceController.save()
            await ReadingAudioPreGenerator.shared.preGenerateChunks(
                itemId: itemId,
                chunks: specs,
                persistenceController: persistenceController
            )
        }

        return item
    }

    /// Copy a file to the app's reading list storage (nonisolated for file system access)
    nonisolated private static func copyFile(from sourceURL: URL, toDirectory directoryPath: String) throws -> URL {
        let filename = sourceURL.lastPathComponent
        let destinationURL = URL(fileURLWithPath: directoryPath)
            .appendingPathComponent(UUID().uuidString + "_" + filename)

        // Start accessing security-scoped resource if needed
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    /// Get or create the images subdirectory
    nonisolated private static func imagesDirectory(forDocumentDir documentDir: String) -> String {
        let imagesDir = URL(fileURLWithPath: documentDir)
            .appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: imagesDir,
            withIntermediateDirectories: true
        )
        return imagesDir.path
    }

    /// Save image data to disk, returning the file path
    nonisolated private static func saveImageToDisk(
        _ data: Data,
        directory: String
    ) -> String? {
        let filename = UUID().uuidString + ".png"
        let filePath = URL(fileURLWithPath: directory)
            .appendingPathComponent(filename)
        do {
            try data.write(to: filePath)
            return filePath.path
        } catch {
            return nil
        }
    }

    /// Compute SHA256 hash of a file (nonisolated for file system access)
    nonisolated private static func computeHash(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return data.sha256Hash
    }

    // MARK: - Read Operations

    /// Fetch all active (not archived) reading items
    @MainActor
    public func fetchActiveItems() throws -> [ReadingListItem] {
        let context = persistenceController.viewContext
        let request = ReadingListItem.fetchRequest()
        request.predicate = NSPredicate(format: "statusRaw != %@", ReadingListStatus.archived.rawValue)
        request.sortDescriptors = [
            NSSortDescriptor(key: "statusRaw", ascending: true), // in_progress first
            NSSortDescriptor(key: "lastReadAt", ascending: false),
            NSSortDescriptor(key: "addedAt", ascending: false)
        ]
        return try context.fetch(request)
    }

    /// Fetch items by status
    @MainActor
    public func fetchItems(status: ReadingListStatus) throws -> [ReadingListItem] {
        let context = persistenceController.viewContext
        let request = ReadingListItem.fetchRequest()
        request.predicate = NSPredicate(format: "statusRaw == %@", status.rawValue)
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastReadAt", ascending: false),
            NSSortDescriptor(key: "addedAt", ascending: false)
        ]
        return try context.fetch(request)
    }

    /// Fetch a specific item by ID
    @MainActor
    public func fetchItem(id: UUID) throws -> ReadingListItem? {
        let context = persistenceController.viewContext
        let request = ReadingListItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Find item by file hash
    @MainActor
    private func findItemByHash(_ hash: String) throws -> ReadingListItem? {
        let context = persistenceController.viewContext
        let request = ReadingListItem.fetchRequest()
        request.predicate = NSPredicate(format: "fileHash == %@", hash)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    // MARK: - Update Operations

    /// Update reading position
    @MainActor
    public func updatePosition(item: ReadingListItem, chunkIndex: Int32) throws {
        item.updatePosition(chunkIndex: chunkIndex)
        try persistenceController.save()
        logger.debug("Updated position for '\(item.title ?? "Unknown")' to chunk \(chunkIndex)")
    }

    /// Update reading position by item ID (for cross-actor calls)
    @MainActor
    public func updatePositionById(itemId: UUID, chunkIndex: Int32) throws {
        guard let item = try fetchItem(id: itemId) else {
            throw ReadingListError.itemNotFound
        }
        item.updatePosition(chunkIndex: chunkIndex)
        try persistenceController.save()
        logger.debug("Updated position for '\(item.title ?? "Unknown")' to chunk \(chunkIndex)")
    }

    /// Save cached audio for a chunk (for cross-session caching).
    /// Called by the playback service after synthesizing audio during playback,
    /// so subsequent sessions can skip synthesis for this chunk.
    @MainActor
    public func saveCachedAudio(
        itemId: UUID,
        chunkIndex: Int32,
        audioData: Data,
        sampleRate: Double
    ) throws {
        guard let item = try fetchItem(id: itemId) else {
            throw ReadingListError.itemNotFound
        }
        guard let chunk = item.chunksArray.first(where: { $0.index == chunkIndex }) else {
            return
        }
        // Only save if not already cached (avoid overwriting)
        guard !chunk.hasCachedAudio else { return }

        chunk.cachedAudioData = audioData
        chunk.cachedAudioSampleRate = sampleRate
        try persistenceController.save()
        logger.debug("Cached audio for '\(item.title ?? "Unknown")' chunk \(chunkIndex)")
    }

    /// Update item metadata
    @MainActor
    public func updateItem(item: ReadingListItem, title: String?, author: String?) throws {
        if let title = title {
            item.title = title
        }
        if let author = author {
            item.author = author
        }
        try persistenceController.save()
    }

    /// Mark item as completed
    @MainActor
    public func completeItem(_ item: ReadingListItem) throws {
        item.markCompleted()
        try persistenceController.save()
        logger.info("Completed reading: \(item.title ?? "Unknown")")
    }

    /// Archive an item
    @MainActor
    public func archiveItem(_ item: ReadingListItem) throws {
        item.archive()
        try persistenceController.save()
        logger.info("Archived reading: \(item.title ?? "Unknown")")
    }

    /// Reset reading progress
    @MainActor
    public func resetProgress(item: ReadingListItem) throws {
        item.resetProgress()
        try persistenceController.save()
        logger.info("Reset progress for: \(item.title ?? "Unknown")")
    }

    // MARK: - Bookmark Operations

    /// Add a bookmark at the current position
    @MainActor
    public func addBookmark(
        to item: ReadingListItem,
        at chunkIndex: Int32? = nil,
        note: String? = nil
    ) throws -> ReadingBookmark {
        let context = persistenceController.viewContext

        let bookmark = ReadingBookmark(context: context)
        let targetIndex = chunkIndex ?? item.currentChunkIndex

        // Get snippet preview from the chunk
        if let chunk = item.chunksArray[safe: Int(targetIndex)] {
            bookmark.configure(from: chunk, note: note)
        } else {
            bookmark.configure(chunkIndex: targetIndex, note: note)
        }

        item.addToBookmarks(bookmark)
        try persistenceController.save()
        logger.debug("Added bookmark at chunk \(targetIndex) for '\(item.title ?? "Unknown")'")

        return bookmark
    }

    /// Remove a bookmark
    @MainActor
    public func removeBookmark(_ bookmark: ReadingBookmark) throws {
        let context = persistenceController.viewContext
        context.delete(bookmark)
        try persistenceController.save()
    }

    /// Add a bookmark by item ID (for cross-actor calls)
    /// Returns bookmark data instead of managed object for actor safety
    @MainActor
    public func addBookmarkById(
        itemId: UUID,
        chunkIndex: Int32,
        note: String?
    ) throws -> (id: UUID, chunkIndex: Int32, note: String?) {
        guard let item = try fetchItem(id: itemId) else {
            throw ReadingListError.itemNotFound
        }

        let context = persistenceController.viewContext
        let bookmark = ReadingBookmark(context: context)

        // Get snippet preview from the chunk
        if let chunk = item.chunksArray[safe: Int(chunkIndex)] {
            bookmark.configure(from: chunk, note: note)
        } else {
            bookmark.configure(chunkIndex: chunkIndex, note: note)
        }

        item.addToBookmarks(bookmark)
        try persistenceController.save()
        logger.debug("Added bookmark at chunk \(chunkIndex) for '\(item.title ?? "Unknown")'")

        return (id: bookmark.id ?? UUID(), chunkIndex: bookmark.chunkIndex, note: bookmark.note)
    }

    // MARK: - Delete Operations

    /// Delete a reading item and its associated files (document + images)
    @MainActor
    public func deleteItem(_ item: ReadingListItem) throws {
        // Delete the document file if it exists
        if let fileURL = item.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Delete associated image files
        for asset in item.visualAssetsArray {
            if let localPath = asset.localPath {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: localPath)
                )
            }
        }

        let context = persistenceController.viewContext
        context.delete(item)
        try persistenceController.save()
        logger.info("Deleted reading item: \(item.title ?? "Unknown")")
    }

    /// Delete all archived items
    @MainActor
    public func deleteAllArchived() throws {
        let context = persistenceController.viewContext
        let request = ReadingListItem.fetchRequest()
        request.predicate = NSPredicate(format: "statusRaw == %@", ReadingListStatus.archived.rawValue)

        let items = try context.fetch(request)
        for item in items {
            if let fileURL = item.fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            context.delete(item)
        }

        try persistenceController.save()
        logger.info("Deleted \(items.count) archived items")
    }

    // MARK: - Statistics

    /// Get reading statistics
    @MainActor
    public func getStatistics() throws -> ReadingListStatistics {
        let context = persistenceController.viewContext
        let request = ReadingListItem.fetchRequest()
        let allItems = try context.fetch(request)

        let unread = allItems.filter { $0.status == .unread }.count
        let inProgress = allItems.filter { $0.status == .inProgress }.count
        let completed = allItems.filter { $0.status == .completed }.count
        let archived = allItems.filter { $0.status == .archived }.count

        let totalReadingTime = allItems
            .filter { $0.status == .completed }
            .reduce(0) { $0 + $1.estimatedTotalDuration }

        return ReadingListStatistics(
            unreadCount: unread,
            inProgressCount: inProgress,
            completedCount: completed,
            archivedCount: archived,
            totalReadingTimeSeconds: totalReadingTime
        )
    }
}

// MARK: - Statistics Model

public struct ReadingListStatistics: Sendable {
    public let unreadCount: Int
    public let inProgressCount: Int
    public let completedCount: Int
    public let archivedCount: Int
    public let totalReadingTimeSeconds: Float

    public var totalActiveCount: Int {
        unreadCount + inProgressCount
    }

    public var totalReadingTimeFormatted: String {
        let hours = Int(totalReadingTimeSeconds) / 3600
        let minutes = (Int(totalReadingTimeSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Errors

public enum ReadingListError: LocalizedError {
    case unsupportedFileType(String)
    case duplicateDocument(String)
    case noTextContent
    case itemNotFound

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: .\(ext). Supported types: PDF, TXT, MD"
        case .duplicateDocument(let title):
            return "This document has already been imported: \(title)"
        case .noTextContent:
            return "No readable text could be extracted from this document"
        case .itemNotFound:
            return "Reading list item not found"
        }
    }
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

// MARK: - Data Extension for Hashing

private extension Data {
    var sha256Hash: String {
        // Simple hash implementation using CryptoKit would be ideal
        // but for compatibility, we'll use a simpler approach
        var hash = 0
        for byte in self {
            hash = hash &* 31 &+ Int(byte)
        }
        return String(format: "%016llx", UInt64(bitPattern: Int64(hash)))
    }
}
