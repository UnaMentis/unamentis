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
    /// AI needs time to process (buying time gracefully)
    case thinking
    /// Brief confirmation that the user was heard
    case acknowledgment
    /// Turning the question back to the learner (Socratic)
    case socratic

    /// Canned response phrases for this intent
    var phrases: [String] {
        switch self {
        case .engagement:
            return [
                "That's a really great question.",
                "Let me think about that.",
                "Good, let's work through this.",
                "Interesting, let me look at that.",
                "That's worth exploring.",
                "I hadn't considered that angle.",
                "Good question, let me explore that.",
                "Let me think about the best way to explain this.",
                "I'm glad you asked that.",
                "That's exactly what I was hoping you'd ask.",
                "Let me pull that together for you.",
                "Good timing on that question."
            ]
        case .encouragement:
            return [
                "That's exactly right.",
                "Spot on!",
                "You nailed it.",
                "Excellent work.",
                "That's impressive.",
                "You really understand this.",
                "Perfect, well done.",
                "That shows strong understanding.",
                "Great recall.",
                "You're getting the hang of this."
            ]
        case .redirect:
            return [
                "Not quite, but you're thinking in the right direction.",
                "Close! Let me help you see it differently.",
                "Good thinking, but there's a twist.",
                "Almost there. Let me give you a hint.",
                "I can see why you'd think that.",
                "That's a common misconception. Here's the thing.",
                "You're on the right track, just a slight adjustment.",
                "Interesting take. Let me clarify."
            ]
        case .transition:
            return [
                "Great, let's move on.",
                "Ready for the next one?",
                "Good, let's keep going.",
                "Alright, next topic.",
                "Shall we continue?",
                "Let's build on that.",
                "Moving right along.",
                "On to the next concept."
            ]
        case .clarification:
            return [
                "I see what you're getting at.",
                "Let me explain that differently.",
                "Good question. Let me break that down.",
                "Here's another way to think about it.",
                "Let me simplify that.",
                "I'll walk you through it step by step.",
                "That's a tricky one. Here's the key.",
                "Let me back up and approach it differently."
            ]
        case .thinking:
            return [
                "Hmm, let me think about that.",
                "That's a deep question.",
                "Give me just a moment.",
                "Let me consider the best way to answer that.",
                "That deserves a thoughtful answer.",
                "Let me work through that.",
                "Good question, let me dig into that."
            ]
        case .acknowledgment:
            return [
                "Got it.",
                "I understand.",
                "Makes sense.",
                "I see.",
                "Okay.",
                "Right.",
                "Understood."
            ]
        case .socratic:
            return [
                "What do you think?",
                "How would you approach that?",
                "What's your instinct telling you?",
                "Have you seen something like this before?",
                "What would you try first?",
                "Before I answer, what's your take on it?",
                "Let's think about that together. Where would you start?"
            ]
        }
    }

    /// Classify intent from user utterance using keyword matching and heuristics
    /// - Parameter utterance: The user's spoken text
    /// - Returns: Best-matching intent
    public static func classify(from utterance: String) -> ResponseIntent {
        let lower = utterance.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Very short utterances are typically acknowledgments
        let wordCount = lower.split(separator: " ").count
        if wordCount <= 2 {
            let shortAcks = ["yes", "yeah", "yep", "ok", "okay", "sure", "right",
                             "got it", "no", "nope", "nah", "uh huh", "mm hmm"]
            if shortAcks.contains(where: { lower == $0 || lower.hasPrefix($0) }) {
                return .acknowledgment
            }
        }

        // Check for confusion/clarification signals
        let clarificationKeywords = ["confused", "don't understand", "what do you mean",
                                      "explain", "clarify", "huh", "what is", "how does",
                                      "i'm lost", "say that again", "repeat", "go back",
                                      "wait what", "i don't get", "can you explain",
                                      "what does that mean", "i'm not following"]
        if clarificationKeywords.contains(where: { lower.contains($0) }) {
            return .clarification
        }

        // Check for transition requests
        let transitionKeywords = ["next", "move on", "skip", "continue", "let's go",
                                   "done", "finished", "what's next", "keep going",
                                   "i'm ready", "go ahead"]
        if transitionKeywords.contains(where: { lower.contains($0) }) {
            return .transition
        }

        // Check for thinking/stalling signals (user needs time)
        let thinkingKeywords = ["umm", "hmm", "let me think", "hold on",
                                 "give me a second", "wait", "one moment",
                                 "i need to think", "let me see"]
        if thinkingKeywords.contains(where: { lower.contains($0) }) {
            return .thinking
        }

        // Check for Socratic prompts (turning questions back to learner)
        let socraticKeywords = ["what do you think", "how would you", "what would you",
                                 "what's your", "your opinion", "your take",
                                 "you tell me", "figure it out", "try it yourself"]
        if socraticKeywords.contains(where: { lower.contains($0) }) {
            return .socratic
        }

        // Check if the user is asking the AI a question (contains question markers)
        let isQuestion = lower.contains("?") ||
            lower.hasPrefix("why") || lower.hasPrefix("how") ||
            lower.hasPrefix("what") || lower.hasPrefix("when") ||
            lower.hasPrefix("where") || lower.hasPrefix("who") ||
            lower.hasPrefix("can you") || lower.hasPrefix("could you") ||
            lower.hasPrefix("do you") || lower.hasPrefix("is it") ||
            lower.hasPrefix("tell me")
        if isQuestion {
            return .engagement
        }

        // Check for encouragement signals (positive affirmations about answers)
        let encouragementKeywords = ["i think it's", "my answer is", "i believe",
                                      "the answer is", "i got it", "i know this"]
        if encouragementKeywords.contains(where: { lower.contains($0) }) {
            return .encouragement
        }

        // Default to redirect for longer non-question utterances (substantive comment needing guidance)
        if wordCount > 8 {
            return .redirect
        }

        // Default to engagement for medium-length utterances
        return .engagement
    }
}
