// UnaMentis - ResponseIntent Tests
// Tests for intent classification used by the zero-latency canned response system

import XCTest
@testable import UnaMentis

final class ResponseIntentTests: XCTestCase {

    // MARK: - classify() Tests

    func testClassify_shortAck_returnsAcknowledgment() {
        XCTAssertEqual(ResponseIntent.classify(from: "yes"), .acknowledgment)
        XCTAssertEqual(ResponseIntent.classify(from: "yeah"), .acknowledgment)
        XCTAssertEqual(ResponseIntent.classify(from: "ok"), .acknowledgment)
        XCTAssertEqual(ResponseIntent.classify(from: "got it"), .acknowledgment)
        XCTAssertEqual(ResponseIntent.classify(from: "no"), .acknowledgment)
        XCTAssertEqual(ResponseIntent.classify(from: "nope"), .acknowledgment)
    }

    func testClassify_clarificationKeywords_returnsClarification() {
        XCTAssertEqual(ResponseIntent.classify(from: "I'm confused"), .clarification)
        XCTAssertEqual(ResponseIntent.classify(from: "Can you explain that?"), .clarification)
        XCTAssertEqual(ResponseIntent.classify(from: "I don't understand"), .clarification)
        XCTAssertEqual(ResponseIntent.classify(from: "Say that again"), .clarification)
        XCTAssertEqual(ResponseIntent.classify(from: "What does that mean"), .clarification)
        XCTAssertEqual(ResponseIntent.classify(from: "I'm not following"), .clarification)
    }

    func testClassify_transitionKeywords_returnsTransition() {
        XCTAssertEqual(ResponseIntent.classify(from: "next"), .transition)
        XCTAssertEqual(ResponseIntent.classify(from: "move on please"), .transition)
        XCTAssertEqual(ResponseIntent.classify(from: "I'm done"), .transition)
        XCTAssertEqual(ResponseIntent.classify(from: "keep going"), .transition)
        XCTAssertEqual(ResponseIntent.classify(from: "let's go"), .transition)
        XCTAssertEqual(ResponseIntent.classify(from: "what's next"), .transition)
    }

    func testClassify_questionMarkers_returnsEngagement() {
        XCTAssertEqual(ResponseIntent.classify(from: "Why does this work?"), .engagement)
        XCTAssertEqual(ResponseIntent.classify(from: "How does that happen?"), .engagement)
        XCTAssertEqual(ResponseIntent.classify(from: "Can you tell me more?"), .engagement)
        XCTAssertEqual(ResponseIntent.classify(from: "Is it always like that?"), .engagement)
        XCTAssertEqual(ResponseIntent.classify(from: "Tell me about it"), .engagement)
    }

    func testClassify_thinkingSignals_returnsThinking() {
        XCTAssertEqual(ResponseIntent.classify(from: "umm let me think"), .thinking)
        XCTAssertEqual(ResponseIntent.classify(from: "hmm"), .thinking)
        XCTAssertEqual(ResponseIntent.classify(from: "let me think"), .thinking)
        XCTAssertEqual(ResponseIntent.classify(from: "give me a second"), .thinking)
        XCTAssertEqual(ResponseIntent.classify(from: "hold on"), .thinking)
    }

    func testClassify_socraticPrompts_returnsSocratic() {
        XCTAssertEqual(ResponseIntent.classify(from: "what do you think about this?"), .socratic)
        XCTAssertEqual(ResponseIntent.classify(from: "how would you approach it?"), .socratic)
        XCTAssertEqual(ResponseIntent.classify(from: "what's your take?"), .socratic)
    }

    func testClassify_answerSignals_returnsEncouragement() {
        XCTAssertEqual(ResponseIntent.classify(from: "I think it's photosynthesis"), .encouragement)
        XCTAssertEqual(ResponseIntent.classify(from: "my answer is forty two"), .encouragement)
        XCTAssertEqual(ResponseIntent.classify(from: "I believe it is carbon dioxide"), .encouragement)
    }

    func testClassify_allCasesReachable() {
        let allCases = ResponseIntent.allCases
        let reachableIntents: Set<ResponseIntent> = [
            .classify(from: "yes"),               // acknowledgment
            .classify(from: "I'm confused"),       // clarification
            .classify(from: "next"),               // transition
            .classify(from: "Why?"),               // engagement
            .classify(from: "hmm"),                // thinking
            .classify(from: "what do you think?"), // socratic
            .classify(from: "I think it's X"),     // encouragement
            .classify(from: "I believe that in this longer sentence about a complex topic, the answer should demonstrate knowledge of the subject matter at hand") // redirect
        ]
        for intent in allCases {
            XCTAssertTrue(reachableIntents.contains(intent), "Intent \(intent) is unreachable via classify(from:)")
        }
    }

    func testClassify_longNonQuestion_returnsRedirectOrEngagement() {
        let longUtterance = "I think the mitochondria is the powerhouse of the cell but I am not completely sure about the exact mechanism of ATP synthesis"
        let result = ResponseIntent.classify(from: longUtterance)
        XCTAssertTrue(result == .redirect || result == .engagement || result == .encouragement,
                      "Long non-question utterance should return redirect, engagement, or encouragement, got \(result)")
    }

    // MARK: - phrases Tests

    func testPhrases_allCasesHaveNonEmptyPhrases() {
        for intent in ResponseIntent.allCases {
            XCTAssertFalse(intent.phrases.isEmpty, "Intent \(intent) has no phrases")
        }
    }

    func testPhrases_noDuplicatesAcrossIntents() {
        var allPhrases: [String] = []
        for intent in ResponseIntent.allCases {
            allPhrases.append(contentsOf: intent.phrases)
        }
        let unique = Set(allPhrases)
        XCTAssertEqual(allPhrases.count, unique.count, "Duplicate phrases found across intent banks")
    }
}
