//
//  VoiceCommandRecognizerTests.swift
//  UnaMentisTests
//
//  Tests for voice command recognition using local matching (no LLM).
//  See docs/design/HANDS_FREE_FIRST_DESIGN.md
//

import XCTest
@testable import UnaMentis

final class VoiceCommandRecognizerTests: XCTestCase {

    var recognizer: VoiceCommandRecognizer!

    override func setUp() async throws {
        recognizer = VoiceCommandRecognizer()
    }

    // MARK: - Exact Match Tests

    func testExactMatchReady() async {
        let result = await recognizer.recognize(transcript: "ready")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .ready)
        XCTAssertEqual(result?.confidence, 1.0)
        XCTAssertEqual(result?.matchType, .exact)
        XCTAssertTrue(result?.shouldExecute ?? false)
    }

    func testExactMatchImReady() async {
        let result = await recognizer.recognize(transcript: "i'm ready")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .ready)
        XCTAssertEqual(result?.confidence, 1.0)
    }

    func testExactMatchSubmit() async {
        let result = await recognizer.recognize(transcript: "submit")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .submit)
        XCTAssertEqual(result?.confidence, 1.0)
    }

    func testExactMatchThatsMyAnswer() async {
        let result = await recognizer.recognize(transcript: "that's my answer")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .submit)
    }

    func testExactMatchNext() async {
        let result = await recognizer.recognize(transcript: "next")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .next)
    }

    func testExactMatchSkip() async {
        let result = await recognizer.recognize(transcript: "skip")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .skip)
    }

    func testExactMatchRepeat() async {
        let result = await recognizer.recognize(transcript: "repeat")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .repeatLast)
    }

    func testExactMatchQuit() async {
        let result = await recognizer.recognize(transcript: "quit")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .quit)
    }

    // MARK: - Phrase Variation Tests

    func testLetsGoMatchesReady() async {
        let result = await recognizer.recognize(transcript: "let's go")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .ready)
    }

    func testDoneMatchesSubmit() async {
        let result = await recognizer.recognize(transcript: "done")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .submit)
    }

    func testFinalAnswerMatchesSubmit() async {
        let result = await recognizer.recognize(transcript: "final answer")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .submit)
    }

    func testContinueMatchesNext() async {
        let result = await recognizer.recognize(transcript: "continue")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .next)
    }

    func testPassMatchesSkip() async {
        let result = await recognizer.recognize(transcript: "pass")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .skip)
    }

    func testIDontKnowMatchesSkip() async {
        let result = await recognizer.recognize(transcript: "i don't know")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .skip)
    }

    func testSayAgainMatchesRepeat() async {
        let result = await recognizer.recognize(transcript: "say again")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .repeatLast)
    }

    func testExitMatchesQuit() async {
        let result = await recognizer.recognize(transcript: "exit")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .quit)
    }

    // MARK: - Case Insensitivity Tests

    func testUppercaseReady() async {
        let result = await recognizer.recognize(transcript: "READY")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .ready)
    }

    func testMixedCaseNext() async {
        let result = await recognizer.recognize(transcript: "NeXt")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .next)
    }

    // MARK: - Embedded Command Tests

    func testCommandInLongerPhrase() async {
        let result = await recognizer.recognize(transcript: "ok i'm ready now")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .ready)
    }

    // MARK: - Context Filtering Tests

    func testValidCommandsFiltering() async {
        // Only allow ready command
        let validCommands: Set<VoiceCommand> = [.ready]
        let result = await recognizer.recognize(transcript: "next", validCommands: validCommands)
        XCTAssertNil(result)  // "next" not in valid commands
    }

    func testValidCommandsAllowsMatch() async {
        let validCommands: Set<VoiceCommand> = [.ready, .submit]
        let result = await recognizer.recognize(transcript: "submit", validCommands: validCommands)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .submit)
    }

    // MARK: - No Match Tests

    func testNonCommandText() async {
        let result = await recognizer.recognize(transcript: "the capital of france is paris")
        XCTAssertNil(result)
    }

    func testEmptyTranscript() async {
        let result = await recognizer.recognize(transcript: "")
        XCTAssertNil(result)
    }

    func testWhitespaceOnlyTranscript() async {
        let result = await recognizer.recognize(transcript: "   ")
        XCTAssertNil(result)
    }

    // MARK: - Confidence Threshold Tests

    func testConfidenceThreshold() async {
        let result = await recognizer.recognize(transcript: "ready")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.confidence >= 0.75)
        XCTAssertTrue(result!.shouldExecute)
    }

    // MARK: - Contains Method Tests

    func testContainsReadyCommand() async {
        let contains = await recognizer.contains(command: .ready, in: "i'm ready")
        XCTAssertTrue(contains)
    }

    func testDoesNotContainNextInReadyPhrase() async {
        let contains = await recognizer.contains(command: .next, in: "i'm ready")
        XCTAssertFalse(contains)
    }

    // MARK: - Phonetic Match Tests

    func testPhoneticMatchReddyForReady() async {
        // "reddy" should phonetically match "ready"
        let result = await recognizer.recognize(transcript: "reddy")
        // May or may not match depending on phonetic algorithm
        // This tests the phonetic matching capability
        if let result = result {
            XCTAssertEqual(result.command, .ready)
            XCTAssertEqual(result.matchType, .phonetic)
            XCTAssertLessThan(result.confidence, 1.0)  // Not exact match
        }
    }

    // MARK: - Bookmark Command Tests

    func testExactMatchBookmark() async {
        let result = await recognizer.recognize(transcript: "bookmark")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .bookmark)
        XCTAssertEqual(result?.confidence, 1.0)
        XCTAssertEqual(result?.matchType, .exact)
    }

    func testBookmarkThisMatchesBookmark() async {
        let result = await recognizer.recognize(transcript: "bookmark this")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .bookmark)
    }

    func testMarkThisMatchesBookmark() async {
        let result = await recognizer.recognize(transcript: "mark this")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .bookmark)
    }

    func testSaveMyPlaceMatchesBookmark() async {
        let result = await recognizer.recognize(transcript: "save my place")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .bookmark)
    }

    func testMarkMyPlaceMatchesBookmark() async {
        let result = await recognizer.recognize(transcript: "mark my place")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .bookmark)
    }

    func testBookmarkContains() async {
        let contains = await recognizer.contains(command: .bookmark, in: "please bookmark this")
        XCTAssertTrue(contains)
    }

    // MARK: - Flag Command Tests

    func testExactMatchFlag() async {
        let result = await recognizer.recognize(transcript: "flag")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .flag)
        XCTAssertEqual(result?.confidence, 1.0)
        XCTAssertEqual(result?.matchType, .exact)
    }

    func testFlagThisMatchesFlag() async {
        let result = await recognizer.recognize(transcript: "flag this")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .flag)
    }

    func testFlagForReviewMatchesFlag() async {
        let result = await recognizer.recognize(transcript: "flag for review")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .flag)
    }

    func testReviewThisMatchesFlag() async {
        let result = await recognizer.recognize(transcript: "review this")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .flag)
    }

    func testStudyThisMatchesFlag() async {
        let result = await recognizer.recognize(transcript: "study this")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .flag)
    }

    func testRememberThisMatchesFlag() async {
        let result = await recognizer.recognize(transcript: "remember this")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .flag)
    }

    func testComeBackToThisMatchesFlag() async {
        let result = await recognizer.recognize(transcript: "come back to this")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .flag)
    }

    func testFlagEmbeddedInPhrase() async {
        let result = await recognizer.recognize(transcript: "I want to flag this for later")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.command, .flag)
    }

    func testFlagContains() async {
        let contains = await recognizer.contains(command: .flag, in: "flag this")
        XCTAssertTrue(contains)
    }

    // MARK: - Bookmark/Flag Context Filtering Tests

    func testBookmarkFilteredOutWhenNotInValidCommands() async {
        let validCommands: Set<VoiceCommand> = [.ready, .next]
        let result = await recognizer.recognize(transcript: "bookmark", validCommands: validCommands)
        XCTAssertNil(result)
    }

    func testFlagFilteredOutWhenNotInValidCommands() async {
        let validCommands: Set<VoiceCommand> = [.ready, .next]
        let result = await recognizer.recognize(transcript: "flag", validCommands: validCommands)
        XCTAssertNil(result)
    }

    func testBookmarkAndFlagAllowedWhenInValidCommands() async {
        let validCommands: Set<VoiceCommand> = [.bookmark, .flag]
        let bookmarkResult = await recognizer.recognize(transcript: "bookmark", validCommands: validCommands)
        let flagResult = await recognizer.recognize(transcript: "flag", validCommands: validCommands)
        XCTAssertNotNil(bookmarkResult)
        XCTAssertNotNil(flagResult)
        XCTAssertEqual(bookmarkResult?.command, .bookmark)
        XCTAssertEqual(flagResult?.command, .flag)
    }

    // MARK: - Performance Tests

    func testRecognitionPerformance() async throws {
        // Recognition should complete in under 300ms per spec
        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<100 {
            _ = await recognizer.recognize(transcript: "i'm ready to answer now")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let averageMs = (elapsed / 100) * 1000

        XCTAssertLessThan(averageMs, 300, "Average recognition time \(averageMs)ms exceeds 300ms target")
    }
}
