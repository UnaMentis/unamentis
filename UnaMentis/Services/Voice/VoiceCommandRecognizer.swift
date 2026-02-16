//
//  VoiceCommandRecognizer.swift
//  UnaMentis
//
//  General-purpose voice command recognition using local matching (no LLM).
//  Designed for both activity-mode voice-first (Tier 1) and future app-wide
//  voice navigation (Tier 2). See docs/design/HANDS_FREE_FIRST_DESIGN.md
//

import Foundation
import OSLog

// MARK: - Voice Command

/// Unified command vocabulary for all voice interactions
public enum VoiceCommand: String, Sendable, CaseIterable {
    case ready      // Proceed/confirm
    case submit     // Submit current input
    case next       // Advance forward
    case skip       // Skip current item
    case repeatLast // Repeat last audio
    case quit       // Exit/cancel
    case bookmark   // Create positional bookmark
    case flag       // Flag for review (creates bookmark + review item)

    /// Human-readable name for feedback
    public var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .submit: return "Submit"
        case .next: return "Next"
        case .skip: return "Skip"
        case .repeatLast: return "Repeat"
        case .quit: return "Exit"
        case .bookmark: return "Bookmark"
        case .flag: return "Flag"
        }
    }
}

// MARK: - Recognition Result

/// Result of voice command recognition attempt
public struct VoiceCommandResult: Sendable {
    public let command: VoiceCommand
    public let confidence: Float
    public let matchedPhrase: String
    public let matchType: MatchType

    public enum MatchType: String, Sendable {
        case exact      // Direct string match
        case phonetic   // Phonetic similarity (Double Metaphone)
        case token      // Token similarity (Jaccard)
    }

    /// Whether confidence meets minimum threshold for execution
    public var shouldExecute: Bool {
        confidence >= 0.75
    }
}

// MARK: - Voice Command Recognizer

/// Recognizes voice commands using local matching algorithms.
///
/// Uses a tiered matching strategy:
/// 1. Exact match (confidence 1.0)
/// 2. Phonetic match via Double Metaphone (confidence 0.9)
/// 3. Token similarity via Jaccard (confidence based on score)
///
/// Designed for reuse across all voice-centric activities and future
/// app-wide voice navigation.
public actor VoiceCommandRecognizer {
    private let logger = Logger(subsystem: "com.unamentis", category: "VoiceCommandRecognizer")

    // Matchers (reused from KB algorithms, same implementations)
    private let phoneticMatcher = PhoneticMatcher()
    private let tokenMatcher = TokenMatcher()

    // MARK: - Command Phrase Library

    /// All recognized phrase variations for each command
    private let commandPhrases: [VoiceCommand: [String]] = [
        .ready: [
            "ready",
            "i'm ready",
            "im ready",
            "let's go",
            "lets go",
            "go ahead",
            "start",
            "begin",
            "answer now",
            "yes"
        ],
        .submit: [
            "submit",
            "that's my answer",
            "thats my answer",
            "done",
            "final answer",
            "finished",
            "i'm done",
            "im done"
        ],
        .next: [
            "next",
            "continue",
            "next question",
            "move on",
            "okay",
            "ok"
        ],
        .skip: [
            "skip",
            "pass",
            "i don't know",
            "i dont know",
            "dont know",
            "no idea",
            "skip this"
        ],
        .repeatLast: [
            "repeat",
            "say again",
            "what was that",
            "repeat question",
            "say that again",
            "pardon",
            "again"
        ],
        .quit: [
            "quit",
            "stop",
            "end",
            "exit",
            "go back",
            "cancel",
            "end session"
        ],
        .bookmark: [
            "bookmark",
            "bookmark this",
            "mark this",
            "save my place",
            "mark my place"
        ],
        .flag: [
            "flag",
            "flag this",
            "flag for review",
            "review this",
            "study this",
            "remember this",
            "come back to this"
        ]
    ]

    // Pre-computed phonetic codes for faster matching
    private var phoneticCodes: [VoiceCommand: [(phrase: String, primary: String, secondary: String?)]] = [:]

    // MARK: - Initialization

    public init() {
        // Precompute phonetic codes synchronously during init
        // Using a local variable to avoid actor isolation issues
        var codes: [VoiceCommand: [(phrase: String, primary: String, secondary: String?)]] = [:]
        for (command, phrases) in commandPhrases {
            var commandCodes: [(phrase: String, primary: String, secondary: String?)] = []
            for phrase in phrases {
                let result = phoneticMatcher.metaphone(phrase)
                commandCodes.append((phrase, result.primary, result.secondary))
            }
            codes[command] = commandCodes
        }
        self.phoneticCodes = codes
    }

    // MARK: - Public API

    /// Attempt to recognize a voice command from transcript
    /// - Parameters:
    ///   - transcript: The STT transcript to analyze
    ///   - validCommands: Optional filter for valid commands in current context
    /// - Returns: Recognition result if a command was found, nil otherwise
    public func recognize(
        transcript: String,
        validCommands: Set<VoiceCommand>? = nil
    ) -> VoiceCommandResult? {
        let normalized = normalize(transcript)

        guard !normalized.isEmpty else {
            return nil
        }

        // Filter commands if context provided
        let commandsToCheck = validCommands ?? Set(VoiceCommand.allCases)

        var bestResult: VoiceCommandResult?

        for command in commandsToCheck {
            if let result = matchCommand(command, against: normalized) {
                if bestResult == nil || result.confidence > bestResult!.confidence {
                    bestResult = result
                }
            }
        }

        // Log recognition attempt
        if let result = bestResult {
            logger.debug("Recognized command: \(result.command.rawValue) (confidence: \(result.confidence), type: \(result.matchType.rawValue))")
        }

        return bestResult
    }

    /// Check if transcript contains a specific command
    /// - Parameters:
    ///   - command: The command to check for
    ///   - transcript: The STT transcript
    /// - Returns: True if command found with sufficient confidence
    public func contains(command: VoiceCommand, in transcript: String) -> Bool {
        guard let result = matchCommand(command, against: normalize(transcript)) else {
            return false
        }
        return result.shouldExecute
    }

    // MARK: - Private Matching

    private func matchCommand(_ command: VoiceCommand, against input: String) -> VoiceCommandResult? {
        guard let phrases = commandPhrases[command] else {
            return nil
        }

        // Tier 1: Exact match
        for phrase in phrases {
            if input == phrase || input.contains(phrase) {
                return VoiceCommandResult(
                    command: command,
                    confidence: 1.0,
                    matchedPhrase: phrase,
                    matchType: .exact
                )
            }
        }

        // Tier 2: Phonetic match
        if let codes = phoneticCodes[command] {
            let inputCodes = phoneticMatcher.metaphone(input)

            for (phrase, primary, secondary) in codes {
                if phoneticMatch(input: inputCodes, target: (primary, secondary)) {
                    return VoiceCommandResult(
                        command: command,
                        confidence: 0.9,
                        matchedPhrase: phrase,
                        matchType: .phonetic
                    )
                }
            }
        }

        // Tier 3: Token similarity
        for phrase in phrases {
            let similarity = tokenMatcher.jaccardSimilarity(input, phrase)
            if similarity >= 0.7 {
                // Scale confidence based on similarity (0.7 -> 0.75, 1.0 -> 0.9)
                let confidence = 0.75 + (similarity - 0.7) * 0.5
                return VoiceCommandResult(
                    command: command,
                    confidence: min(confidence, 0.89), // Cap below phonetic
                    matchedPhrase: phrase,
                    matchType: .token
                )
            }
        }

        return nil
    }

    private func phoneticMatch(
        input: (primary: String, secondary: String?),
        target: (primary: String, secondary: String?)
    ) -> Bool {
        guard !input.primary.isEmpty && !target.primary.isEmpty else {
            return false
        }

        // Match if primary codes match
        if input.primary == target.primary {
            return true
        }

        // Match if either secondary matches the other's primary
        if let inputSec = input.secondary, inputSec == target.primary {
            return true
        }

        if let targetSec = target.secondary, input.primary == targetSec {
            return true
        }

        // Match if both secondaries match
        if let inputSec = input.secondary, let targetSec = target.secondary, inputSec == targetSec {
            return true
        }

        return false
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "'", with: "'") // Normalize apostrophes
    }
}

// MARK: - Phonetic Matcher (Embedded for independence)

/// Double Metaphone phonetic encoding for command matching
private struct PhoneticMatcher {

    /// Generate Double Metaphone codes for a text string
    func metaphone(_ text: String) -> (primary: String, secondary: String?) {
        let cleaned = text.uppercased().filter { $0.isLetter || $0 == " " }
        guard !cleaned.isEmpty else {
            return ("", nil)
        }

        // For short phrases, encode each word and concatenate
        let words = cleaned.components(separatedBy: " ").filter { !$0.isEmpty }
        var primaryCodes: [String] = []
        var secondaryCodes: [String] = []

        for word in words {
            let (primary, secondary) = encodeWord(word)
            primaryCodes.append(primary)
            if let sec = secondary {
                secondaryCodes.append(sec)
            }
        }

        let primary = primaryCodes.joined()
        let secondary = secondaryCodes.isEmpty ? nil : secondaryCodes.joined()

        return (String(primary.prefix(8)), secondary.map { String($0.prefix(8)) })
    }

    private func encodeWord(_ word: String) -> (primary: String, secondary: String?) {
        var context = MetaphoneContext(text: word)
        processInitialExceptions(&context)
        processMainLoop(&context)
        return context.result()
    }

    private func processInitialExceptions(_ context: inout MetaphoneContext) {
        if context.stringAt(0, 2, "GN", "KN", "PN", "WR", "PS") {
            context.advanceIndex()
        }
        if context.charAt(0) == "X" {
            context.appendBoth("S")
            context.advanceIndex()
        }
    }

    private func processMainLoop(_ context: inout MetaphoneContext) {
        while context.hasMore() {
            let ch = context.currentChar()
            processCharacter(ch, context: &context)
            context.advanceIndex()
        }
    }

    private func processCharacter(_ ch: Character, context: inout MetaphoneContext) {
        switch ch {
        case "A", "E", "I", "O", "U", "Y":
            if context.currentPosition() == 0 {
                context.appendBoth("A")
            }
        case "B": context.appendBoth("P")
        case "C":
            if context.stringAt(context.currentPosition(), 2, "CH") {
                context.appendBoth("X")
                context.advanceIndex()
            } else if context.stringAt(context.currentPosition(), 2, "CE", "CI", "CY") {
                context.appendBoth("S")
            } else {
                context.appendBoth("K")
            }
        case "D":
            if context.stringAt(context.currentPosition(), 2, "DG") {
                context.appendBoth("J")
                context.advanceIndex()
            } else {
                context.appendBoth("T")
            }
        case "F": context.appendBoth("F")
        case "G":
            if context.charAt(1) == "H" {
                context.appendBoth("K")
            } else if context.charAt(1) == "N" {
                // Silent GN
            } else if context.charAt(1) == "E" || context.charAt(1) == "I" || context.charAt(1) == "Y" {
                context.appendPrimary("J")
                context.appendSecondary("K")
            } else {
                context.appendBoth("K")
            }
        case "H":
            if context.isVowel(context.charAt(1)) && (context.currentPosition() == 0 || !context.isVowel(context.charAt(-1))) {
                context.appendBoth("H")
            }
        case "J":
            context.appendBoth("J")
        case "K", "Q":
            context.appendBoth("K")
        case "L":
            context.appendBoth("L")
        case "M":
            context.appendBoth("M")
        case "N":
            context.appendBoth("N")
        case "P":
            if context.charAt(1) == "H" {
                context.appendBoth("F")
                context.advanceIndex()
            } else {
                context.appendBoth("P")
            }
        case "R":
            context.appendBoth("R")
        case "S":
            if context.stringAt(context.currentPosition(), 2, "SH") {
                context.appendBoth("X")
                context.advanceIndex()
            } else {
                context.appendBoth("S")
            }
        case "T":
            if context.stringAt(context.currentPosition(), 2, "TH") {
                context.appendPrimary("0")
                context.appendSecondary("T")
                context.advanceIndex()
            } else {
                context.appendBoth("T")
            }
        case "V":
            context.appendBoth("F")
        case "W":
            if context.isVowel(context.charAt(1)) {
                context.appendBoth("A")
            }
        case "X":
            context.appendBoth("KS")
        case "Z":
            context.appendBoth("S")
        default:
            break
        }
    }
}

// MARK: - Metaphone Context

private struct MetaphoneContext {
    let text: String
    var index: String.Index
    var primary: String = ""
    var secondary: String = ""

    init(text: String) {
        self.text = text
        self.index = text.startIndex
    }

    mutating func advanceIndex(by offset: Int = 1) {
        index = text.index(index, offsetBy: offset, limitedBy: text.endIndex) ?? text.endIndex
    }

    func hasMore() -> Bool {
        index < text.endIndex
    }

    func currentChar() -> Character {
        text[index]
    }

    func currentPosition() -> Int {
        text.distance(from: text.startIndex, to: index)
    }

    func charAt(_ offset: Int) -> Character? {
        let targetIndex = text.index(index, offsetBy: offset, limitedBy: offset < 0 ? text.startIndex : text.endIndex)
        guard let targetIndex = targetIndex, text.indices.contains(targetIndex) else {
            return nil
        }
        return text[targetIndex]
    }

    func stringAt(_ start: Int, _ length: Int, _ matches: String...) -> Bool {
        guard start >= 0 else { return false }
        let startIdx = text.index(text.startIndex, offsetBy: start, limitedBy: text.endIndex)
        guard let startIdx = startIdx else { return false }
        guard text.distance(from: startIdx, to: text.endIndex) >= length else { return false }
        let endIdx = text.index(startIdx, offsetBy: length)
        let substr = String(text[startIdx..<endIdx])
        return matches.contains(substr)
    }

    func isVowel(_ ch: Character?) -> Bool {
        guard let ch = ch else { return false }
        return "AEIOUY".contains(ch)
    }

    mutating func appendPrimary(_ code: String) {
        primary.append(code)
    }

    mutating func appendSecondary(_ code: String) {
        secondary.append(code)
    }

    mutating func appendBoth(_ code: String) {
        primary.append(code)
        secondary.append(code)
    }

    func result() -> (primary: String, secondary: String?) {
        let primaryCode = String(primary.prefix(4))
        let secondaryCode = secondary.isEmpty || secondary == primary ? nil : String(secondary.prefix(4))
        return (primaryCode, secondaryCode)
    }
}

// MARK: - Token Matcher (Embedded for independence)

/// Token-based similarity for command matching
private struct TokenMatcher {

    /// Compute Jaccard similarity (intersection / union of tokens)
    func jaccardSimilarity(_ str1: String, _ str2: String) -> Float {
        let tokens1 = tokenize(str1)
        let tokens2 = tokenize(str2)

        if tokens1.isEmpty && tokens2.isEmpty {
            return 1.0
        }

        guard !tokens1.isEmpty && !tokens2.isEmpty else {
            return 0.0
        }

        let intersection = tokens1.intersection(tokens2).count
        let union = tokens1.union(tokens2).count

        guard union > 0 else { return 0.0 }

        return Float(intersection) / Float(union)
    }

    private func tokenize(_ text: String) -> Set<String> {
        let normalized = text.lowercased()

        let tokens = normalized.components(separatedBy: .whitespacesAndNewlines)
            .flatMap { word in
                word.components(separatedBy: .punctuationCharacters)
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Minimal stop words for command matching (keep most words)
        let stopWords: Set<String> = ["the", "a", "an"]
        let filtered = tokens.filter { !stopWords.contains($0) }

        return Set(filtered)
    }
}

// MARK: - Preview Support

#if DEBUG
extension VoiceCommandRecognizer {
    public static func preview() -> VoiceCommandRecognizer {
        VoiceCommandRecognizer()
    }
}
#endif
