// UnaMentis - ResponsePreGenerator Tests
// Tests for speculative response pre-generation logic (non-LLM paths)

import XCTest
@testable import UnaMentis

final class ResponsePreGeneratorTests: XCTestCase {

    var pregen: ResponsePreGenerator!

    override func setUp() async throws {
        pregen = ResponsePreGenerator()
    }

    override func tearDown() async throws {
        pregen = nil
    }

    // MARK: - Scenario ordering tests

    func testScenarioOrder_firstIsQuestionAboutTopic() {
        XCTAssertEqual(ResponsePreGenerator.Scenario.allCases.first, .questionAboutTopic,
                       "Most common scenario should be first so default budget covers it")
    }

    func testScenarioOrder_secondIsMoveOn() {
        let cases = ResponsePreGenerator.Scenario.allCases
        XCTAssertEqual(cases[1], .moveOn,
                       "moveOn (transition) should be second as it maps to a reachable intent")
    }

    func testScenarioOrder_thirdIsRepeatRequest() {
        let cases = ResponsePreGenerator.Scenario.allCases
        XCTAssertEqual(cases[2], .repeatRequest,
                       "repeatRequest (clarification) should be third")
    }

    func testScenarioCount_isFive() {
        XCTAssertEqual(ResponsePreGenerator.Scenario.allCases.count, 5)
    }

    // MARK: - stripThinkingBlocks tests

    func testStrip_noThinkingBlock_returnsOriginal() {
        let text = "That is a great question."
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: text), text)
    }

    func testStrip_withThinkingBlock_removesBlock() {
        let text = "<think>Let me reason...</think>Sure, here's my answer."
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: text), "Sure, here's my answer.")
    }

    func testStrip_multipleThinkingBlocks_removesAll() {
        let text = "<think>first</think>Response<think>second</think> done."
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: text), "Response done.")
    }

    func testStrip_emptyThinkingBlock_removesBlock() {
        let text = "<think></think>Answer here."
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: text), "Answer here.")
    }

    func testStrip_noContent_returnsEmpty() {
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: ""), "")
    }

    // MARK: - invalidate tests

    func testInvalidate_clearsAvailableCount() async {
        let count = await pregen.availableCount
        XCTAssertEqual(count, 0)
        await pregen.invalidate()
        let countAfter = await pregen.availableCount
        XCTAssertEqual(countAfter, 0)
    }

    func testInvalidate_resetsGeneratingFlag() async {
        await pregen.invalidate()
        let isGenerating = await pregen.isGenerating
        XCTAssertFalse(isGenerating)
    }

    // MARK: - getMatchingStarter tests

    func testGetMatchingStarter_withNoStarters_returnsNil() async {
        let result = await pregen.getMatchingStarter(for: "Why does this work?")
        XCTAssertNil(result)
    }
}
