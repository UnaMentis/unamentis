// VoiceLearn - Document Processor
// Handles text extraction, summarization, and embedding generation for documents
//
// Part of Curriculum Layer (TDD Section 4)

import Foundation
import CoreData
import PDFKit
import Logging

/// Actor responsible for processing curriculum documents
///
/// Responsibilities:
/// - Extract text from various document formats (PDF, text, markdown, transcripts)
/// - Generate summaries using LLM service
/// - Create embeddings for semantic search
/// - Chunk text for optimal processing
public actor DocumentProcessor {

    // MARK: - Properties

    private let llmService: any LLMService
    private let embeddingService: any EmbeddingService
    private let logger = Logger(label: "com.voicelearn.documentprocessor")

    /// Maximum characters to send to LLM for summarization
    private let maxSummaryInputChars = 8000

    /// Default chunk size for embeddings
    private let defaultChunkSize = 500

    // MARK: - Initialization

    /// Initialize document processor with required services
    /// - Parameters:
    ///   - llmService: LLM service for summary generation
    ///   - embeddingService: Embedding service for vector generation
    public init(llmService: any LLMService, embeddingService: any EmbeddingService) {
        self.llmService = llmService
        self.embeddingService = embeddingService
        logger.info("DocumentProcessor initialized")
    }

    // MARK: - Document Processing

    /// Process a document: extract text, generate summary, create embeddings
    /// - Parameter document: Core Data Document entity to process
    @MainActor
    public func processDocument(_ document: Document) async throws {
        guard let fileURL = document.sourceURL else {
            throw DocumentError.fileNotFound(URL(fileURLWithPath: "unknown"))
        }

        let documentType = document.documentType

        // Extract text
        logger.debug("Extracting text from: \(fileURL.lastPathComponent)")
        let extractedText = try await extractText(from: fileURL, type: documentType)
        document.content = extractedText

        // Generate summary
        logger.debug("Generating summary for: \(document.title ?? "Unknown")")
        do {
            let summary = try await generateSummary(text: extractedText)
            document.summary = summary
        } catch {
            logger.warning("Failed to generate summary: \(error.localizedDescription)")
            // Continue without summary - not critical
        }

        // Create embeddings
        logger.debug("Creating embeddings for: \(document.title ?? "Unknown")")
        let chunks = await chunkText(extractedText, maxChunkSize: defaultChunkSize)
        if !chunks.isEmpty {
            do {
                let embeddedChunks = try await createEmbeddings(
                    chunks: chunks,
                    documentId: document.id ?? UUID()
                )
                document.embedding = try JSONEncoder().encode(embeddedChunks)
            } catch {
                logger.warning("Failed to create embeddings: \(error.localizedDescription)")
                // Continue without embeddings - not critical
            }
        }

        logger.info("Document processed: \(document.title ?? "Unknown")")
    }

    // MARK: - Text Extraction

    /// Extract text from a file based on its type
    /// - Parameters:
    ///   - url: File URL to extract from
    ///   - type: Document type
    /// - Returns: Extracted text content
    public func extractText(from url: URL, type: DocumentType) async throws -> String {
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentError.fileNotFound(url)
        }

        switch type {
        case .pdf:
            return try await extractPDFText(url: url)
        case .text, .markdown:
            return try await extractPlainText(url: url)
        case .transcript:
            return try await extractTranscriptText(url: url)
        }
    }

    /// Extract text from a PDF file
    private func extractPDFText(url: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw DocumentError.pdfLoadFailed(url)
        }

        var text = ""
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex),
                  let pageText = page.string else {
                continue
            }
            text += pageText + "\n\n"
        }

        guard !text.isEmpty else {
            throw DocumentError.extractionFailed("PDF contains no extractable text")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract text from a plain text or markdown file
    private func extractPlainText(url: URL) async throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw DocumentError.extractionFailed("Failed to read text file: \(error.localizedDescription)")
        }
    }

    /// Extract text from a transcript JSON file
    private func extractTranscriptText(url: URL) async throws -> String {
        do {
            let data = try Data(contentsOf: url)
            let turns = try JSONDecoder().decode([TranscriptTurn].self, from: data)
            return turns.map { "\($0.speaker): \($0.transcript)" }.joined(separator: "\n")
        } catch {
            throw DocumentError.extractionFailed("Failed to parse transcript: \(error.localizedDescription)")
        }
    }

    // MARK: - Text Chunking

    /// Split text into chunks for embedding
    /// - Parameters:
    ///   - text: Text to chunk
    ///   - maxChunkSize: Maximum characters per chunk
    /// - Returns: Array of text chunks with indices
    public func chunkText(_ text: String, maxChunkSize: Int) -> [(text: String, index: Int)] {
        guard !text.isEmpty else { return [] }

        let words = text.split(separator: " ")
        guard !words.isEmpty else { return [] }

        var chunks: [(String, Int)] = []
        var currentChunk: [Substring] = []
        var chunkIndex = 0

        for word in words {
            // Check if adding this word would exceed the limit
            var testChunk = currentChunk
            testChunk.append(word)
            let testText = testChunk.joined(separator: " ")

            if testText.count > maxChunkSize && !currentChunk.isEmpty {
                // Output current chunk before adding the word that exceeds limit
                chunks.append((currentChunk.joined(separator: " "), chunkIndex))
                chunkIndex += 1
                currentChunk = [word]
            } else {
                currentChunk.append(word)
            }
        }

        // Add remaining words as final chunk
        if !currentChunk.isEmpty {
            chunks.append((currentChunk.joined(separator: " "), chunkIndex))
        }

        return chunks
    }

    // MARK: - Summary Generation

    /// Generate a summary of text using LLM
    /// - Parameter text: Text to summarize
    /// - Returns: Generated summary
    public func generateSummary(text: String) async throws -> String {
        // Truncate text if too long
        let truncatedText = String(text.prefix(maxSummaryInputChars))

        let prompt = """
        Summarize the following educational material in 3-5 paragraphs. Focus on:
        - Main concepts and topics covered
        - Key learning points
        - Important examples or case studies

        Material:
        \(truncatedText)
        """

        let messages = [LLMMessage(role: .user, content: prompt)]

        do {
            let stream = try await llmService.streamCompletion(
                messages: messages,
                config: .costOptimized
            )

            var summary = ""
            for await token in stream {
                summary += token.content
            }

            return summary.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw DocumentError.summaryGenerationFailed(error.localizedDescription)
        }
    }

    // MARK: - Embedding Creation

    /// Create embeddings for text chunks
    /// - Parameters:
    ///   - chunks: Array of text chunks with indices
    ///   - documentId: ID of the source document
    /// - Returns: Array of DocumentChunk with embeddings
    public func createEmbeddings(
        chunks: [(text: String, index: Int)],
        documentId: UUID
    ) async throws -> [DocumentChunk] {
        var embeddedChunks: [DocumentChunk] = []

        for chunk in chunks {
            let embedding = await embeddingService.embed(text: chunk.text)

            let documentChunk = DocumentChunk(
                id: UUID(),
                documentId: documentId,
                text: chunk.text,
                embedding: embedding,
                pageNumber: nil,
                chunkIndex: chunk.index
            )

            embeddedChunks.append(documentChunk)
        }

        return embeddedChunks
    }

    // MARK: - Utility Methods

    /// Count words in text
    /// - Parameter text: Text to count
    /// - Returns: Word count
    public func countWords(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        return words.count
    }

    /// Estimate reading time in minutes
    /// - Parameters:
    ///   - text: Text to estimate
    ///   - wordsPerMinute: Reading speed (default 200 WPM)
    /// - Returns: Estimated minutes
    public func estimateReadingTime(for text: String, wordsPerMinute: Int = 200) -> Int {
        let wordCount = countWords(in: text)
        return max(1, wordCount / wordsPerMinute)
    }
}

// MARK: - Document Processor Factory

/// Factory for creating DocumentProcessor instances
public struct DocumentProcessorFactory {
    /// Create a document processor with given services
    public static func create(
        llmService: any LLMService,
        embeddingService: any EmbeddingService
    ) -> DocumentProcessor {
        return DocumentProcessor(
            llmService: llmService,
            embeddingService: embeddingService
        )
    }
}
