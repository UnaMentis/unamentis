// UnaMentis - HTMLArticleExtractor
// Extracts article content from HTML pages for reading list import.
// Uses SwiftSoup for HTML parsing and content extraction.
//
// Part of Core/ReadingList

import Foundation
import Logging
import SwiftSoup

// MARK: - Extraction Result

/// Result of extracting article content from HTML
public struct HTMLExtractionResult: Sendable {
    public let title: String?
    public let author: String?
    public let text: String

    public init(title: String?, author: String?, text: String) {
        self.title = title
        self.author = author
        self.text = text
    }
}

// MARK: - HTML Article Extractor

/// Extracts readable article text from HTML pages using SwiftSoup.
public struct HTMLArticleExtractor: Sendable {

    private static let logger = Logger(label: "com.unamentis.readinglist.htmlextractor")

    public init() { }

    /// Extract article content from an HTML string
    /// - Parameters:
    ///   - html: Raw HTML content
    ///   - url: Source URL (unused, kept for API compatibility)
    /// - Returns: Extracted article with title, author, and clean text
    public func extractArticle(from html: String, url: URL? = nil) -> HTMLExtractionResult {
        return basicExtraction(from: html)
    }

    // MARK: - Extraction

    private func basicExtraction(from html: String) -> HTMLExtractionResult {
        do {
            let doc = try SwiftSoup.parse(html)

            // Extract title
            let title = try doc.title().isEmpty ? nil : doc.title()

            // Extract author from meta tags
            let author = try extractMetaAuthor(from: doc)

            // Remove non-content elements
            let skipSelectors = [
                "script", "style", "nav", "header", "footer", "aside",
                "noscript", "svg", "form", "button", "select", "textarea",
                "iframe", "[class*=sidebar]", "[class*=menu]", "[class*=comment]",
                "[class*=share]", "[class*=social]", "[class*=related]",
                "[class*=advertisement]", "[class*=cookie]", "[class*=newsletter]",
            ]

            for selector in skipSelectors {
                try doc.select(selector).remove()
            }

            // Try to find main content area
            var contentElement: SwiftSoup.Element?
            let contentSelectors = ["article", "main", "[role=main]", ".content", ".post", ".entry"]
            for selector in contentSelectors {
                let elements = try doc.select(selector)
                if let element = elements.first(), try element.text().count > 200 {
                    contentElement = element
                    break
                }
            }

            // Fall back to body
            let source = contentElement ?? doc.body()
            let text = try source?.text() ?? ""

            return HTMLExtractionResult(
                title: title,
                author: author,
                text: postProcess(text)
            )
        } catch {
            Self.logger.error("SwiftSoup fallback failed: \(error.localizedDescription)")
            return HTMLExtractionResult(title: nil, author: nil, text: "")
        }
    }

    /// Extract author from meta tags using SwiftSoup
    private func extractMetaAuthor(from doc: SwiftSoup.Document) throws -> String? {
        // Try meta author tag
        if let authorMeta = try doc.select("meta[name=author]").first(),
           let content = try? authorMeta.attr("content"),
           !content.isEmpty {
            return content
        }

        // Try article:author
        if let authorMeta = try doc.select("meta[property=article:author]").first(),
           let content = try? authorMeta.attr("content"),
           !content.isEmpty {
            return content
        }

        return nil
    }

    // MARK: - Post-Processing

    /// Post-process extracted text for TTS readability
    private func postProcess(_ text: String) -> String {
        var result = text

        // Remove footnote-style markers: [1], [2], etc.
        if let regex = try? NSRegularExpression(pattern: #"\[\d+\]"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        // Collapse multiple newlines to at most 2
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Collapse multiple spaces to single
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
