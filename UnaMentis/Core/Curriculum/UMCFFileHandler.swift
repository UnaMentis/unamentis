// UnaMentis - UMCF File Handler
// Handles reading and writing UMCF files in both raw (.umcf) and compressed (.umcfz) formats
//
// Part of Curriculum Layer (TDD Section 4)

import Foundation
import Compression
import UniformTypeIdentifiers
import Logging

// MARK: - UMCF File Types

/// Supported UMCF file formats
public enum UMCFFileFormat: String, CaseIterable, Sendable {
    case raw = "umcf"           // Raw JSON format
    case compressed = "umcfz"   // Gzip-compressed format

    /// UTType for this format
    public var utType: UTType {
        switch self {
        case .raw:
            return UTType(exportedAs: "com.unamentis.umcf", conformingTo: .json)
        case .compressed:
            return UTType(exportedAs: "com.unamentis.umcfz", conformingTo: .gzip)
        }
    }

    /// MIME type for this format
    public var mimeType: String {
        switch self {
        case .raw:
            return "application/vnd.umcf+json"
        case .compressed:
            return "application/vnd.umcf+gzip"
        }
    }

    /// File extension including dot
    public var fileExtension: String {
        ".\(rawValue)"
    }

    /// Detect format from URL
    public static func detect(from url: URL) -> UMCFFileFormat? {
        let ext = url.pathExtension.lowercased()
        return UMCFFileFormat(rawValue: ext)
    }

    /// All supported file extensions for file picker
    public static var allExtensions: [String] {
        allCases.map { $0.rawValue }
    }

    /// All UTTypes for file picker
    public static var allUTTypes: [UTType] {
        [
            UTType(filenameExtension: "umcf") ?? .json,
            UTType(filenameExtension: "umcfz") ?? .gzip
        ]
    }
}

// MARK: - UMCF File Handler Errors

public enum UMCFFileError: Error, LocalizedError, Sendable {
    case unsupportedFormat(String)
    case decompressionFailed(String)
    case compressionFailed(String)
    case invalidArchiveStructure(String)
    case manifestNotFound
    case decodingFailed(String)
    case encodingFailed(String)
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case assetExtractionFailed(String)
    case securityViolation(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file format: .\(ext). Use .umcf or .umcfz"
        case .decompressionFailed(let reason):
            return "Failed to decompress file: \(reason)"
        case .compressionFailed(let reason):
            return "Failed to compress file: \(reason)"
        case .invalidArchiveStructure(let reason):
            return "Invalid archive structure: \(reason)"
        case .manifestNotFound:
            return "Archive does not contain a valid manifest.json"
        case .decodingFailed(let reason):
            return "Failed to decode UMCF document: \(reason)"
        case .encodingFailed(let reason):
            return "Failed to encode UMCF document: \(reason)"
        case .fileReadFailed(let reason):
            return "Failed to read file: \(reason)"
        case .fileWriteFailed(let reason):
            return "Failed to write file: \(reason)"
        case .assetExtractionFailed(let reason):
            return "Failed to extract assets: \(reason)"
        case .securityViolation(let reason):
            return "Security violation: \(reason)"
        }
    }
}

// MARK: - UMCF Import Result

/// Result of importing a UMCF file, including the document and any extracted assets
public struct UMCFImportResult: Sendable {
    public let document: UMCFDocument
    public let format: UMCFFileFormat
    public let assets: [String: Data]  // Asset ID -> binary data
    public let sourceURL: URL

    public init(document: UMCFDocument, format: UMCFFileFormat, assets: [String: Data] = [:], sourceURL: URL) {
        self.document = document
        self.format = format
        self.assets = assets
        self.sourceURL = sourceURL
    }
}

// MARK: - Package Metadata

/// Metadata for .umcfz packages
public struct UMCFPackageMetadata: Codable, Sendable {
    public let packageVersion: String
    public let createdAt: String
    public let createdBy: String?
    public let checksum: String?
    public let totalSize: Int?
    public let assetCount: Int?

    public init(
        packageVersion: String = "1.0.0",
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        createdBy: String? = "UnaMentis",
        checksum: String? = nil,
        totalSize: Int? = nil,
        assetCount: Int? = nil
    ) {
        self.packageVersion = packageVersion
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.checksum = checksum
        self.totalSize = totalSize
        self.assetCount = assetCount
    }
}

// MARK: - UMCF File Handler

/// Handler for reading and writing UMCF files in all supported formats
public actor UMCFFileHandler {
    private static let logger = Logger(label: "com.unamentis.umcf.filehandler")

    // Maximum allowed file size (100 MB)
    private let maxFileSize: Int = 100 * 1024 * 1024

    // Maximum decompressed size (500 MB) - protects against zip bombs
    private let maxDecompressedSize: Int = 500 * 1024 * 1024

    public init() {}

    // MARK: - Reading Files

    /// Read a UMCF file from URL, automatically detecting format
    public func read(from url: URL) async throws -> UMCFImportResult {
        guard let format = UMCFFileFormat.detect(from: url) else {
            let ext = url.pathExtension
            throw UMCFFileError.unsupportedFormat(ext)
        }

        Self.logger.info("Reading UMCF file: \(url.lastPathComponent) (format: \(format.rawValue))")

        switch format {
        case .raw:
            return try await readRawFormat(from: url)
        case .compressed:
            return try await readCompressedFormat(from: url)
        }
    }

    /// Read raw .umcf file
    private func readRawFormat(from url: URL) async throws -> UMCFImportResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw UMCFFileError.fileReadFailed(error.localizedDescription)
        }

        guard data.count <= maxFileSize else {
            throw UMCFFileError.fileReadFailed("File exceeds maximum size of \(maxFileSize / 1024 / 1024) MB")
        }

        let document: UMCFDocument
        do {
            document = try JSONDecoder().decode(UMCFDocument.self, from: data)
        } catch {
            throw UMCFFileError.decodingFailed(error.localizedDescription)
        }

        Self.logger.info("Successfully read raw UMCF: \(document.title)")
        return UMCFImportResult(document: document, format: .raw, assets: [:], sourceURL: url)
    }

    /// Read compressed .umcfz file
    private func readCompressedFormat(from url: URL) async throws -> UMCFImportResult {
        let compressedData: Data
        do {
            compressedData = try Data(contentsOf: url)
        } catch {
            throw UMCFFileError.fileReadFailed(error.localizedDescription)
        }

        guard compressedData.count <= maxFileSize else {
            throw UMCFFileError.fileReadFailed("File exceeds maximum size of \(maxFileSize / 1024 / 1024) MB")
        }

        // Decompress the data
        let decompressedData: Data
        do {
            decompressedData = try decompress(compressedData)
        } catch {
            throw UMCFFileError.decompressionFailed(error.localizedDescription)
        }

        guard decompressedData.count <= maxDecompressedSize else {
            throw UMCFFileError.securityViolation("Decompressed size exceeds maximum allowed")
        }

        // Try to decode as a simple compressed JSON first (single document)
        if let document = try? JSONDecoder().decode(UMCFDocument.self, from: decompressedData) {
            Self.logger.info("Successfully read compressed UMCF (simple format): \(document.title)")
            return UMCFImportResult(document: document, format: .compressed, assets: [:], sourceURL: url)
        }

        // Try to decode as archive format with manifest and assets
        return try await readArchiveFormat(from: decompressedData, sourceURL: url)
    }

    /// Read archive format with manifest and assets
    private func readArchiveFormat(from data: Data, sourceURL: URL) async throws -> UMCFImportResult {
        // Parse as archive structure
        // For now, we support a simple JSON structure with embedded asset data
        struct ArchiveStructure: Codable {
            let manifest: UMCFDocument
            let assets: [String: String]?  // Asset ID -> Base64 encoded data
            let metadata: UMCFPackageMetadata?
        }

        let archive: ArchiveStructure
        do {
            archive = try JSONDecoder().decode(ArchiveStructure.self, from: data)
        } catch {
            throw UMCFFileError.invalidArchiveStructure(error.localizedDescription)
        }

        // Decode assets from base64
        var decodedAssets: [String: Data] = [:]
        if let assets = archive.assets {
            for (assetId, base64String) in assets {
                // Security check: validate asset ID doesn't contain path traversal
                guard !assetId.contains("..") && !assetId.hasPrefix("/") else {
                    throw UMCFFileError.securityViolation("Invalid asset ID: \(assetId)")
                }

                if let assetData = Data(base64Encoded: base64String) {
                    decodedAssets[assetId] = assetData
                } else {
                    Self.logger.warning("Failed to decode base64 asset: \(assetId)")
                }
            }
        }

        Self.logger.info("Successfully read compressed UMCF archive: \(archive.manifest.title) with \(decodedAssets.count) assets")
        return UMCFImportResult(
            document: archive.manifest,
            format: .compressed,
            assets: decodedAssets,
            sourceURL: sourceURL
        )
    }

    // MARK: - Writing Files

    /// Write a UMCF document to file
    public func write(
        document: UMCFDocument,
        to url: URL,
        format: UMCFFileFormat,
        assets: [String: Data] = [:]
    ) async throws {
        Self.logger.info("Writing UMCF file: \(url.lastPathComponent) (format: \(format.rawValue))")

        switch format {
        case .raw:
            try await writeRawFormat(document: document, to: url)
        case .compressed:
            try await writeCompressedFormat(document: document, to: url, assets: assets)
        }
    }

    /// Write raw .umcf file
    private func writeRawFormat(document: UMCFDocument, to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw UMCFFileError.encodingFailed(error.localizedDescription)
        }

        do {
            try data.write(to: url)
        } catch {
            throw UMCFFileError.fileWriteFailed(error.localizedDescription)
        }

        Self.logger.info("Successfully wrote raw UMCF: \(url.lastPathComponent)")
    }

    /// Write compressed .umcfz file
    private func writeCompressedFormat(
        document: UMCFDocument,
        to url: URL,
        assets: [String: Data]
    ) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]  // No pretty print for compressed

        let dataToCompress: Data

        if assets.isEmpty {
            // Simple format: just compress the document
            do {
                dataToCompress = try encoder.encode(document)
            } catch {
                throw UMCFFileError.encodingFailed(error.localizedDescription)
            }
        } else {
            // Archive format: include manifest and assets
            struct ArchiveStructure: Codable {
                let manifest: UMCFDocument
                let assets: [String: String]  // Base64 encoded
                let metadata: UMCFPackageMetadata
            }

            // Encode assets to base64
            var encodedAssets: [String: String] = [:]
            for (assetId, assetData) in assets {
                encodedAssets[assetId] = assetData.base64EncodedString()
            }

            let archive = ArchiveStructure(
                manifest: document,
                assets: encodedAssets,
                metadata: UMCFPackageMetadata(assetCount: assets.count)
            )

            do {
                dataToCompress = try encoder.encode(archive)
            } catch {
                throw UMCFFileError.encodingFailed(error.localizedDescription)
            }
        }

        // Compress the data
        let compressedData: Data
        do {
            compressedData = try compress(dataToCompress)
        } catch {
            throw UMCFFileError.compressionFailed(error.localizedDescription)
        }

        do {
            try compressedData.write(to: url)
        } catch {
            throw UMCFFileError.fileWriteFailed(error.localizedDescription)
        }

        Self.logger.info("Successfully wrote compressed UMCF: \(url.lastPathComponent) (\(compressedData.count) bytes)")
    }

    // MARK: - Compression Helpers

    /// Decompress gzip data
    private func decompress(_ data: Data) throws -> Data {
        // Use NSData's built-in decompression
        let nsData = data as NSData
        do {
            let decompressed = try nsData.decompressed(using: .zlib)
            return decompressed as Data
        } catch {
            // Try lzfse as fallback
            do {
                let decompressed = try nsData.decompressed(using: .lzfse)
                return decompressed as Data
            } catch {
                throw UMCFFileError.decompressionFailed("Unable to decompress data")
            }
        }
    }

    /// Compress data with gzip
    private func compress(_ data: Data) throws -> Data {
        let nsData = data as NSData
        do {
            let compressed = try nsData.compressed(using: .zlib)
            return compressed as Data
        } catch {
            throw UMCFFileError.compressionFailed("Unable to compress data")
        }
    }
}

// MARK: - Convenience Extensions

extension UMCFFileHandler {
    /// Import a UMCF file and store it in Core Data
    @MainActor
    public func importAndStore(
        from url: URL,
        persistenceController: PersistenceController = .shared
    ) async throws -> Curriculum {
        let result = try await read(from: url)

        // Import the document to Core Data
        let curriculum = try UMCFParser.importDocument(
            result.document,
            replaceExisting: true,
            persistenceController: persistenceController
        )

        // Cache any extracted assets
        if !result.assets.isEmpty {
            let assetCache = VisualAssetCache.shared
            for (assetId, data) in result.assets {
                try? await assetCache.cache(assetId: assetId, data: data)
            }
        }

        Self.logger.info("Imported curriculum '\(curriculum.name ?? "Untitled")' with \(result.assets.count) assets")
        return curriculum
    }
}
