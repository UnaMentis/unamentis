//
//  KBAnswerValidator.swift
//  UnaMentis
//
//  Answer validation with rule-based matching for Knowledge Bowl
//

import Foundation
import OSLog

// MARK: - Answer Validator

/// Validates user answers against correct answers using various matching strategies
final class KBAnswerValidator: Sendable {
    private let logger = Logger(subsystem: "com.unamentis", category: "KBAnswerValidator")

    // MARK: - Configuration

    /// Configuration for answer validation
    struct Config: Sendable {
        /// Maximum Levenshtein distance for fuzzy matching (as percentage of answer length)
        var fuzzyThresholdPercent: Double = 0.20 // Allow ~20% error

        /// Minimum confidence for a match to be considered correct
        var minimumConfidence: Float = 0.6

        /// Whether to use strict mode (exact match only)
        var strictMode: Bool = false

        static let standard = Config()
        static let strict = Config(strictMode: true)
        static let lenient = Config(fuzzyThresholdPercent: 0.30, minimumConfidence: 0.5)
    }

    private let config: Config

    // MARK: - Initialization

    init(config: Config = .standard) {
        self.config = config
    }

    // MARK: - Public API

    /// Validate a user's answer against the question's correct answer
    func validate(userAnswer: String, question: KBQuestion) -> KBValidationResult {
        let answer = question.answer

        // Normalize the user answer
        let normalizedUser = normalize(userAnswer, for: answer.answerType)

        // 1. Check exact primary match
        let normalizedPrimary = normalize(answer.primary, for: answer.answerType)
        if normalizedUser == normalizedPrimary {
            logger.debug("Exact match for: \(userAnswer)")
            return KBValidationResult(
                isCorrect: true,
                confidence: 1.0,
                matchType: .exact,
                matchedAnswer: answer.primary
            )
        }

        // 2. Check acceptable alternatives
        if let acceptable = answer.acceptable {
            for alt in acceptable {
                let normalizedAlt = normalize(alt, for: answer.answerType)
                if normalizedUser == normalizedAlt {
                    logger.debug("Acceptable match for: \(userAnswer) -> \(alt)")
                    return KBValidationResult(
                        isCorrect: true,
                        confidence: 1.0,
                        matchType: .acceptable,
                        matchedAnswer: alt
                    )
                }
            }
        }

        // 3. Fuzzy matching (if not in strict mode)
        if !config.strictMode {
            let fuzzyResult = fuzzyMatch(normalizedUser, against: answer)
            if fuzzyResult.isCorrect {
                return fuzzyResult
            }
        }

        // No match found
        logger.debug("No match for: \(userAnswer)")
        return KBValidationResult(
            isCorrect: false,
            confidence: 0,
            matchType: .none,
            matchedAnswer: nil
        )
    }

    /// Validate an MCQ selection
    func validateMCQ(selectedIndex: Int, question: KBQuestion) -> KBValidationResult {
        guard let options = question.mcqOptions,
              selectedIndex >= 0 && selectedIndex < options.count else {
            return KBValidationResult(
                isCorrect: false,
                confidence: 0,
                matchType: .none,
                matchedAnswer: nil
            )
        }

        let selectedOption = options[selectedIndex]
        let isCorrect = normalize(selectedOption, for: .text) ==
            normalize(question.answer.primary, for: .text)

        return KBValidationResult(
            isCorrect: isCorrect,
            confidence: isCorrect ? 1.0 : 0,
            matchType: isCorrect ? .exact : .none,
            matchedAnswer: isCorrect ? selectedOption : nil
        )
    }

    // MARK: - Normalization

    /// Normalize text based on answer type
    private func normalize(_ text: String, for type: KBAnswerType) -> String {
        var normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch type {
        case .text:
            normalized = normalizeText(normalized)

        case .person:
            normalized = normalizePerson(normalized)

        case .place:
            normalized = normalizePlace(normalized)

        case .number:
            normalized = normalizeNumber(normalized)

        case .date:
            normalized = normalizeDate(normalized)

        case .title:
            normalized = normalizeTitle(normalized)

        case .scientific:
            normalized = normalizeScientific(normalized)

        case .multipleChoice:
            // Just extract the letter
            normalized = normalized.filter { $0.isLetter }.prefix(1).lowercased()
        }

        return normalized
    }

    private func normalizeText(_ text: String) -> String {
        var result = text
        // Remove common punctuation
        result = result.replacingOccurrences(of: "[.,!?;:'\"()-]", with: "", options: .regularExpression)
        // Collapse multiple spaces
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Remove articles
        result = removeArticles(result)
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func normalizePerson(_ text: String) -> String {
        var result = normalizeText(text)
        // Remove titles
        let titles = ["dr", "mr", "mrs", "ms", "miss", "prof", "professor", "sir", "dame", "lord", "lady"]
        for title in titles {
            result = result.replacingOccurrences(of: "^\(title)\\.?\\s+", with: "", options: .regularExpression)
        }
        // Handle "First Last" vs "Last, First"
        if result.contains(",") {
            let parts = result.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                result = "\(parts[1]) \(parts[0])"
            }
        }
        return result
    }

    private func normalizePlace(_ text: String) -> String {
        var result = normalizeText(text)
        // Handle common abbreviations
        let abbreviations: [String: String] = [
            "usa": "united states of america",
            "us": "united states",
            "uk": "united kingdom",
            "uae": "united arab emirates",
            "mt": "mount",
            "st": "saint",
            "ft": "fort"
        ]
        for (abbr, full) in abbreviations {
            if result == abbr {
                result = full
            }
        }
        return result
    }

    private func normalizeNumber(_ text: String) -> String {
        var result = normalizeText(text)

        // Parse written numbers
        let wordNumbers: [String: String] = [
            "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
            "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
            "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
            "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
            "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
            "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
            "eighty": "80", "ninety": "90", "hundred": "100", "thousand": "1000",
            "million": "1000000", "billion": "1000000000"
        ]

        for (word, num) in wordNumbers {
            if result == word {
                return num
            }
        }

        // Remove commas from numbers
        result = result.replacingOccurrences(of: ",", with: "")

        return result
    }

    private func normalizeDate(_ text: String) -> String {
        // Basic date normalization - could be expanded
        var result = normalizeText(text)
        // Handle month names
        let months: [String: String] = [
            "january": "1", "jan": "1", "february": "2", "feb": "2",
            "march": "3", "mar": "3", "april": "4", "apr": "4",
            "may": "5", "june": "6", "jun": "6", "july": "7", "jul": "7",
            "august": "8", "aug": "8", "september": "9", "sep": "9", "sept": "9",
            "october": "10", "oct": "10", "november": "11", "nov": "11",
            "december": "12", "dec": "12"
        ]
        for (name, num) in months {
            result = result.replacingOccurrences(of: name, with: num)
        }
        return result
    }

    private func normalizeTitle(_ text: String) -> String {
        var result = normalizeText(text)
        // Remove leading "the"
        result = result.replacingOccurrences(of: "^the\\s+", with: "", options: .regularExpression)
        // Remove subtitle after colon
        if let colonIndex = result.firstIndex(of: ":") {
            result = String(result[..<colonIndex])
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func normalizeScientific(_ text: String) -> String {
        var result = text.lowercased()
        // Keep some special characters for formulas
        result = result.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return result
    }

    private func removeArticles(_ text: String) -> String {
        var result = text
        let articles = ["the ", "a ", "an "]
        for article in articles {
            if result.hasPrefix(article) {
                result = String(result.dropFirst(article.count))
            }
        }
        return result
    }

    // MARK: - Fuzzy Matching

    private func fuzzyMatch(_ userAnswer: String, against answer: KBAnswer) -> KBValidationResult {
        let threshold = max(2, Int(Double(answer.primary.count) * config.fuzzyThresholdPercent))

        // Check against primary answer
        let primaryDistance = levenshteinDistance(userAnswer, normalize(answer.primary, for: answer.answerType))
        if primaryDistance <= threshold {
            let confidence = 1.0 - (Float(primaryDistance) / Float(max(1, answer.primary.count)))
            if confidence >= config.minimumConfidence {
                logger.debug("Fuzzy match (distance \(primaryDistance)): \(userAnswer) -> \(answer.primary)")
                return KBValidationResult(
                    isCorrect: true,
                    confidence: confidence,
                    matchType: .fuzzy,
                    matchedAnswer: answer.primary
                )
            }
        }

        // Check against acceptable alternatives
        if let acceptable = answer.acceptable {
            for alt in acceptable {
                let altDistance = levenshteinDistance(userAnswer, normalize(alt, for: answer.answerType))
                let altThreshold = max(2, Int(Double(alt.count) * config.fuzzyThresholdPercent))
                if altDistance <= altThreshold {
                    let confidence = 1.0 - (Float(altDistance) / Float(max(1, alt.count)))
                    if confidence >= config.minimumConfidence {
                        logger.debug("Fuzzy match (distance \(altDistance)): \(userAnswer) -> \(alt)")
                        return KBValidationResult(
                            isCorrect: true,
                            confidence: confidence,
                            matchType: .fuzzy,
                            matchedAnswer: alt
                        )
                    }
                }
            }
        }

        return KBValidationResult(isCorrect: false, confidence: 0, matchType: .none, matchedAnswer: nil)
    }

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        let s1Array = Array(s1)
        let s2Array = Array(s2)

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m {
            matrix[i][0] = i
        }
        for j in 0...n {
            matrix[0][j] = j
        }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,     // deletion
                    matrix[i][j - 1] + 1,     // insertion
                    matrix[i - 1][j - 1] + cost  // substitution
                )
            }
        }

        return matrix[m][n]
    }
}

// MARK: - Validation Result

/// Result of answer validation
struct KBValidationResult: Sendable {
    /// Whether the answer was correct
    let isCorrect: Bool

    /// Confidence level of the match (0.0-1.0)
    let confidence: Float

    /// How the answer was matched
    let matchType: KBMatchType

    /// The answer that was matched against (if correct)
    let matchedAnswer: String?

    /// Points earned (can be modified by caller based on timing, rebound, etc.)
    var pointsEarned: Int {
        isCorrect ? 1 : 0
    }
}

// MARK: - Preview Support

#if DEBUG
extension KBAnswerValidator {
    /// Create a validator for previews
    static func preview() -> KBAnswerValidator {
        KBAnswerValidator()
    }
}
#endif
