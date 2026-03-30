//
//  ResponseIntentTests.swift
//  UnaMentisTests
//
//  Unit tests for ResponseIntent classification and phrase management
//

import XCTest
@testable import UnaMentis

/// Tests for ResponseIntent enum and keyword-based classification
final class ResponseIntentTests: XCTestCase {

    // MARK: - Enum Coverage

    func testAllIntentCasesExist() {
        let allCases = ResponseIntent.allCases
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.engagement))
        XCTAssertTrue(allCases.contains(.encouragement))
        XCTAssertTrue(allCases.contains(.redirect))
        XCTAssertTrue(allCases.contains(.transition))
        XCTAssertTrue(allCases.contains(.clarification))
    }

    func testRawValues() {
        XCTAssertEqual(ResponseIntent.engagement.rawValue, "engagement")
        XCTAssertEqual(ResponseIntent.encouragement.rawValue, "encouragement")
        XCTAssertEqual(ResponseIntent.redirect.rawValue, "redirect")
        XCTAssertEqual(ResponseIntent.transition.rawValue, "transition")
        XCTAssertEqual(ResponseIntent.clarification.rawValue, "clarification")
    }

    // MARK: - Phrases

    func testAllIntentsHavePhrases() {
        for intent in ResponseIntent.allCases {
            XCTAssertFalse(intent.phrases.isEmpty, "\(intent) should have phrases")
            XCTAssertGreaterThanOrEqual(
                intent.phrases.count, 3,
                "\(intent) should have at least 3 phrases"
            )
        }
    }

    func testPhrasesAreNonEmpty() {
        for intent in ResponseIntent.allCases {
            for phrase in intent.phrases {
                XCTAssertFalse(
                    phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(intent) has an empty phrase"
                )
            }
        }
    }

    func testPhrasesAreUnique() {
        for intent in ResponseIntent.allCases {
            let phrases = intent.phrases
            let uniquePhrases = Set(phrases)
            XCTAssertEqual(
                phrases.count, uniquePhrases.count,
                "\(intent) has duplicate phrases"
            )
        }
    }

    // MARK: - Classification: Clarification

    func testClassifyClarificationKeywords() {
        let clarificationInputs = [
            "I'm confused about this",
            "I don't understand",
            "What do you mean?",
            "Can you explain that?",
            "Please clarify",
            "Huh?",
            "How does that work?",
            "I'm lost here",
            "Say that again please",
            "Can you repeat that?"
        ]

        for input in clarificationInputs {
            XCTAssertEqual(
                ResponseIntent.classify(from: input),
                .clarification,
                "'\(input)' should classify as clarification"
            )
        }
    }

    // MARK: - Classification: Transition

    func testClassifyTransitionKeywords() {
        let transitionInputs = [
            "Let's move on",
            "Next topic please",
            "Skip this one",
            "Continue to the next part",
            "Let's go to the next section",
            "I'm done with this"
        ]

        for input in transitionInputs {
            XCTAssertEqual(
                ResponseIntent.classify(from: input),
                .transition,
                "'\(input)' should classify as transition"
            )
        }
    }

    // MARK: - Classification: Engagement (Default)

    func testClassifyEngagementDefault() {
        let engagementInputs = [
            "What is photosynthesis?",
            "Tell me about the American Revolution",
            "How do quadratic equations work?",
            "I think the answer is 42",
            "That's interesting"
        ]

        for input in engagementInputs {
            XCTAssertEqual(
                ResponseIntent.classify(from: input),
                .engagement,
                "'\(input)' should classify as engagement (default)"
            )
        }
    }

    // MARK: - Classification: Edge Cases

    func testClassifyEmptyString() {
        XCTAssertEqual(ResponseIntent.classify(from: ""), .engagement)
    }

    func testClassifyCaseInsensitive() {
        XCTAssertEqual(
            ResponseIntent.classify(from: "I'M CONFUSED"),
            .clarification
        )
        XCTAssertEqual(
            ResponseIntent.classify(from: "MOVE ON"),
            .transition
        )
    }

    func testClassifyClarificationPriority() {
        // When both clarification and transition keywords present,
        // clarification should win (checked first)
        let mixed = "I don't understand, can we move on?"
        XCTAssertEqual(ResponseIntent.classify(from: mixed), .clarification)
    }
}
