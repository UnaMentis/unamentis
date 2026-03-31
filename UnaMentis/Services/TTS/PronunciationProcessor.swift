// UnaMentis - Pronunciation Processor
// Transforms text with pronunciation hints for TTS services
//
// Part of Services/TTS

import Foundation

/// Processes text with pronunciation hints for TTS services.
/// Applies IPA pronunciations from curriculum pronunciation guides
/// to improve TTS output for proper nouns, foreign terms, etc.
public struct PronunciationProcessor {

    // MARK: - Types

    /// A pronunciation entry for a term
    public struct PronunciationHint: Sendable {
        public let term: String
        public let ipa: String
        public let respelling: String?
        public let language: String?

        public init(term: String, ipa: String, respelling: String? = nil, language: String? = nil) {
            self.term = term
            self.ipa = ipa
            self.respelling = respelling
            self.language = language
        }
    }

    /// Output format for the processed text
    public enum OutputFormat: Sendable {
        /// SSML with <phoneme> tags (for TTS services that support SSML)
        case ssml
        /// Plain text with respelling hints in parentheses
        case respelling
        /// Plain text unchanged (rely on TTS to guess)
        case plain
    }

    // MARK: - Properties

    private let hints: [String: PronunciationHint]
    private let outputFormat: OutputFormat

    // MARK: - Initialization

    /// Initialize with pronunciation hints
    /// - Parameters:
    ///   - hints: Dictionary mapping terms to their pronunciation hints
    ///   - outputFormat: How to format the output text
    public init(hints: [String: PronunciationHint], outputFormat: OutputFormat = .ssml) {
        self.hints = hints
        self.outputFormat = outputFormat
    }

    /// Initialize from TranscriptData pronunciation guide
    /// - Parameters:
    ///   - pronunciationGuide: Pronunciation guide from curriculum transcript
    ///   - outputFormat: How to format the output text
    public init(
        pronunciationGuide: [String: TranscriptData.PronunciationEntry]?,
        outputFormat: OutputFormat = .ssml
    ) {
        var hints: [String: PronunciationHint] = [:]

        if let guide = pronunciationGuide {
            for (term, entry) in guide {
                hints[term] = PronunciationHint(
                    term: term,
                    ipa: entry.ipa,
                    respelling: entry.respelling,
                    language: entry.language
                )
            }
        }

        self.hints = hints
        self.outputFormat = outputFormat
    }

    // MARK: - Processing

    /// Process text by applying pronunciation hints
    /// - Parameter text: The input text to process
    /// - Returns: Text with pronunciation hints applied according to output format
    public func process(_ text: String) -> String {
        guard !hints.isEmpty else { return text }

        var processedText = text

        // Sort hints by term length (longest first) to avoid partial replacements
        let sortedHints = hints.sorted { $0.key.count > $1.key.count }

        for (term, hint) in sortedHints {
            switch outputFormat {
            case .ssml:
                // Replace with SSML phoneme tag
                // Note: Most TTS services that support SSML use the "ipa" alphabet
                let ssmlTag = buildSSMLPhoneme(term: term, hint: hint)
                processedText = replaceWholeWords(in: processedText, term: term, replacement: ssmlTag)

            case .respelling:
                // Add respelling hint in parentheses (for TTS without SSML support)
                if let respelling = hint.respelling {
                    let withHint = "\(term) (\(respelling))"
                    processedText = replaceWholeWords(in: processedText, term: term, replacement: withHint)
                }

            case .plain:
                // No modification
                break
            }
        }

        return processedText
    }

    /// Process text and wrap in SSML speak tags if using SSML format
    /// - Parameter text: The input text to process
    /// - Returns: Text wrapped in SSML speak tags if using SSML format
    public func processWithSSMLWrapper(_ text: String) -> String {
        let processed = process(text)

        if outputFormat == .ssml && !hints.isEmpty {
            return "<speak>\(processed)</speak>"
        }

        return processed
    }

    // MARK: - Private Methods

    /// Build an SSML phoneme tag for a term
    private func buildSSMLPhoneme(term: String, hint: PronunciationHint) -> String {
        // Strip leading/trailing slashes from IPA if present
        let cleanIPA = hint.ipa
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Add xml:lang attribute if language is specified
        if let language = hint.language {
            return "<phoneme alphabet=\"ipa\" ph=\"\(cleanIPA)\" xml:lang=\"\(language)\">\(term)</phoneme>"
        } else {
            return "<phoneme alphabet=\"ipa\" ph=\"\(cleanIPA)\">\(term)</phoneme>"
        }
    }

    /// Cache of pre-compiled regexes keyed by term to avoid recompilation per call
    private static let regexCacheLock = NSLock()
    private static nonisolated(unsafe) var regexCache: [String: NSRegularExpression] = [:]

    /// Replace whole words only (not partial matches)
    private func replaceWholeWords(in text: String, term: String, replacement: String) -> String {
        // Use cached regex, or compile and cache on first use
        let regex: NSRegularExpression
        Self.regexCacheLock.lock()
        if let cached = Self.regexCache[term] {
            Self.regexCacheLock.unlock()
            regex = cached
        } else {
            Self.regexCacheLock.unlock()
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: []) else {
                return text
            }
            Self.regexCacheLock.lock()
            Self.regexCache[term] = compiled
            Self.regexCacheLock.unlock()
            regex = compiled
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}

// MARK: - Extension for String

extension String {
    /// Apply pronunciation hints from a curriculum pronunciation guide
    /// - Parameters:
    ///   - guide: Pronunciation guide dictionary
    ///   - format: Output format (default: SSML)
    /// - Returns: Text with pronunciation hints applied
    public func withPronunciationHints(
        from guide: [String: TranscriptData.PronunciationEntry]?,
        format: PronunciationProcessor.OutputFormat = .ssml
    ) -> String {
        let processor = PronunciationProcessor(pronunciationGuide: guide, outputFormat: format)
        return processor.process(self)
    }
}

// MARK: - TTS Service Extension

/// Extension to provide pronunciation-aware synthesis
extension TranscriptData {
    /// Get text for a segment with pronunciation hints applied
    /// - Parameters:
    ///   - segmentIndex: Index of the segment
    ///   - format: Output format for pronunciation hints
    /// - Returns: Segment text with pronunciation hints, or nil if segment not found
    public func textWithPronunciation(
        forSegment segmentIndex: Int,
        format: PronunciationProcessor.OutputFormat = .ssml
    ) -> String? {
        guard segmentIndex < segments.count else { return nil }

        let segment = segments[segmentIndex]
        return segment.content.withPronunciationHints(from: pronunciationGuide, format: format)
    }
}
