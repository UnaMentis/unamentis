// UnaMentis - Response Intent Classification
// Classifies user utterances to select appropriate canned acknowledgments
//
// Part of Zero-Latency Response System

import Foundation

/// Intent categories for selecting canned acknowledgment responses
public enum ResponseIntent: String, CaseIterable, Sendable {
    /// User asks a question during a lesson
    case engagement
    /// User gives a correct answer
    case encouragement
    /// User gives an incorrect answer
    case redirect
    /// Moving between sections/topics
    case transition
    /// User expresses confusion or asks for clarification
    case clarification

    /// Canned response phrases for this intent
    var phrases: [String] {
        switch self {
        case .engagement:
            return [
                "Great question!",
                "Let me think about that.",
                "Good, let's work through this.",
                "Interesting, let me look at that.",
                "That's worth exploring."
            ]
        case .encouragement:
            return [
                "Nice work!",
                "You're on the right track.",
                "That's a solid answer.",
                "Exactly right.",
                "Well done."
            ]
        case .redirect:
            return [
                "Not quite, let's look at it another way.",
                "Close! Let me explain.",
                "Good try. Here's what to consider.",
                "Almost there, let me clarify.",
                "Let's think about that differently."
            ]
        case .transition:
            return [
                "Let's move on to the next part.",
                "Ready for the next topic?",
                "Great, let's continue.",
                "Moving on.",
                "Alright, next up."
            ]
        case .clarification:
            return [
                "I see what you mean.",
                "Let me clarify that.",
                "Good question, let me explain.",
                "Here's another way to think about it.",
                "Let me break that down."
            ]
        }
    }

    /// Classify intent from user utterance using keyword matching
    /// - Parameter utterance: The user's spoken text
    /// - Returns: Best-matching intent
    public static func classify(from utterance: String) -> ResponseIntent {
        let lower = utterance.lowercased()

        // Check for confusion/clarification signals
        let clarificationKeywords = ["confused", "don't understand", "what do you mean",
                                      "explain", "clarify", "huh", "what", "how does",
                                      "i'm lost", "say that again", "repeat"]
        if clarificationKeywords.contains(where: { lower.contains($0) }) {
            return .clarification
        }

        // Check for transition requests
        let transitionKeywords = ["next", "move on", "skip", "continue", "let's go", "done"]
        if transitionKeywords.contains(where: { lower.contains($0) }) {
            return .transition
        }

        // Default to engagement (user is asking a question or making a comment)
        return .engagement
    }
}
