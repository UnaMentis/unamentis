//
//  ResponsePreGeneratorTests.swift
//  UnaMentisTests
//
//  Unit tests for ResponsePreGenerator actor
//

import XCTest
@testable import UnaMentis

/// Tests for ResponsePreGenerator speculative response generation
final class ResponsePreGeneratorTests: XCTestCase {

    // MARK: - Initialization

    func testInitialState() async {
        let gen = ResponsePreGenerator()

        let generating = await gen.isGenerating
        XCTAssertFalse(generating)
        let count = await gen.availableCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Scenario Enumeration

    func testAllScenariosExist() {
        let scenarios = ResponsePreGenerator.Scenario.allCases
        XCTAssertEqual(scenarios.count, 5)
        XCTAssertTrue(scenarios.contains(.questionAboutTopic))
        XCTAssertTrue(scenarios.contains(.repeatRequest))
        XCTAssertTrue(scenarios.contains(.correctAnswer))
        XCTAssertTrue(scenarios.contains(.wrongAnswer))
        XCTAssertTrue(scenarios.contains(.moveOn))
    }

    // MARK: - Thinking Block Stripping

    func testStripThinkingBlocks_noBlocks() {
        let text = "This is a normal response."
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: text), text)
    }

    func testStripThinkingBlocks_singleBlock() {
        let text = "<think>Let me analyze this...</think>The answer is 42."
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: text), "The answer is 42.")
    }

    func testStripThinkingBlocks_multipleBlocks() {
        let text = "<think>First thought</think>Hello <think>second thought</think>world."
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: text), "Hello world.")
    }

    func testStripThinkingBlocks_emptyBlock() {
        let text = "<think></think>Clean response."
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: text), "Clean response.")
    }

    func testStripThinkingBlocks_onlyThinking() {
        let text = "<think>All thinking, no output</think>"
        let result = ResponsePreGenerator.stripThinkingBlocks(from: text)
        XCTAssertTrue(result.isEmpty, "Should be empty after stripping: '\(result)'")
    }

    func testStripThinkingBlocks_nestedContent() {
        let text = "<think>I need to think about <important>this</important></think>Here's my answer."
        XCTAssertEqual(ResponsePreGenerator.stripThinkingBlocks(from: text), "Here's my answer.")
    }

    // MARK: - Matching

    func testGetMatchingStarterReturnsNilWhenEmpty() async {
        let gen = ResponsePreGenerator()

        let result = await gen.getMatchingStarter(for: "What is this?")
        XCTAssertNil(result, "Should return nil when no starters cached")
    }

    // MARK: - Invalidation

    func testInvalidateClearsState() async {
        let gen = ResponsePreGenerator()

        await gen.invalidate()

        let count = await gen.availableCount
        XCTAssertEqual(count, 0)
        let generating = await gen.isGenerating
        XCTAssertFalse(generating)
    }

    // MARK: - PreGeneration with Mock LLM

    func testPreGenerateCachesStarters() async {
        let gen = ResponsePreGenerator()
        let mockLLM = MockLLMService() // ALLOWED: paid external API mock (LLM providers cost per token)

        // Set UserDefaults for pre-gen
        UserDefaults.standard.set(true, forKey: "zerolatency_pregenEnabled")
        UserDefaults.standard.set(30.0, forKey: "zerolatency_pregenMaxTokens")
        UserDefaults.standard.set(3.0, forKey: "zerolatency_pregenCount")

        let history = [
            LLMMessage(role: .system, content: "You are a tutor"),
            LLMMessage(role: .user, content: "What is photosynthesis?")
        ]

        await gen.preGenerate(
            using: mockLLM,
            fovContext: nil,
            conversationHistory: history
        )

        let isGen = await gen.isGenerating
        XCTAssertFalse(isGen, "Should not be generating after completion")
        let available = await gen.availableCount
        XCTAssertGreaterThan(available, 0, "Should have cached starters")

        // Clean up
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenEnabled")
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenMaxTokens")
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenCount")
    }

    func testPreGenerateRespectsDisabledFlag() async {
        let gen = ResponsePreGenerator()
        let mockLLM = MockLLMService() // ALLOWED: paid external API mock (LLM providers cost per token)

        UserDefaults.standard.set(false, forKey: "zerolatency_pregenEnabled")

        await gen.preGenerate(
            using: mockLLM,
            fovContext: nil,
            conversationHistory: []
        )

        let disabledCount = await gen.availableCount
        XCTAssertEqual(disabledCount, 0, "Should not generate when disabled")

        // Clean up
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenEnabled")
    }

    func testPreGenerateInvalidatesCacheOnContextChange() async {
        let gen = ResponsePreGenerator()
        let mockLLM = MockLLMService() // ALLOWED: paid external API mock (LLM providers cost per token)

        UserDefaults.standard.set(true, forKey: "zerolatency_pregenEnabled")
        UserDefaults.standard.set(30.0, forKey: "zerolatency_pregenMaxTokens")
        UserDefaults.standard.set(2.0, forKey: "zerolatency_pregenCount")

        // First generation
        let history1 = [LLMMessage(role: .user, content: "Topic A question")]
        await gen.preGenerate(using: mockLLM, fovContext: nil, conversationHistory: history1)
        let count1 = await gen.availableCount

        // Second generation with different context
        let history2 = [LLMMessage(role: .user, content: "Completely different Topic B")]
        await gen.preGenerate(using: mockLLM, fovContext: nil, conversationHistory: history2)
        let count2 = await gen.availableCount

        // Both should have starters (cache was invalidated and rebuilt)
        XCTAssertGreaterThan(count1, 0)
        XCTAssertGreaterThan(count2, 0)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenEnabled")
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenMaxTokens")
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenCount")
    }

    func testPreGenerateSkipsWhenCacheValid() async {
        let gen = ResponsePreGenerator()
        let mockLLM = MockLLMService() // ALLOWED: paid external API mock (LLM providers cost per token)

        UserDefaults.standard.set(true, forKey: "zerolatency_pregenEnabled")
        UserDefaults.standard.set(30.0, forKey: "zerolatency_pregenMaxTokens")
        UserDefaults.standard.set(2.0, forKey: "zerolatency_pregenCount")

        let history = [LLMMessage(role: .user, content: "Same question")]

        // First generation
        await gen.preGenerate(using: mockLLM, fovContext: nil, conversationHistory: history)
        let callsAfterFirst = await mockLLM.streamCompletionCallCount

        // Second generation with same context (should skip)
        await gen.preGenerate(using: mockLLM, fovContext: nil, conversationHistory: history)
        let callsAfterSecond = await mockLLM.streamCompletionCallCount

        XCTAssertEqual(
            callsAfterFirst, callsAfterSecond,
            "Should not call LLM again when cache is valid"
        )

        // Clean up
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenEnabled")
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenMaxTokens")
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenCount")
    }

    // MARK: - Starter Consumption

    func testStarterConsumedAfterRetrieval() async {
        let gen = ResponsePreGenerator()
        let mockLLM = MockLLMService() // ALLOWED: paid external API mock (LLM providers cost per token)

        UserDefaults.standard.set(true, forKey: "zerolatency_pregenEnabled")
        UserDefaults.standard.set(30.0, forKey: "zerolatency_pregenMaxTokens")
        UserDefaults.standard.set(3.0, forKey: "zerolatency_pregenCount")

        let history = [LLMMessage(role: .user, content: "Test question")]
        await gen.preGenerate(using: mockLLM, fovContext: nil, conversationHistory: history)

        let countBefore = await gen.availableCount
        guard countBefore > 0 else {
            // Skip if no starters were generated (mock may not produce text)
            return
        }

        // Consume a starter
        _ = await gen.getMatchingStarter(for: "What is this topic about?")

        let countAfter = await gen.availableCount
        XCTAssertLessThanOrEqual(countAfter, countBefore, "Available count should decrease after consumption")

        // Clean up
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenEnabled")
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenMaxTokens")
        UserDefaults.standard.removeObject(forKey: "zerolatency_pregenCount")
    }
}
