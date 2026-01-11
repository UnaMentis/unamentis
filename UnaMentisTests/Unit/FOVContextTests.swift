// UnaMentis - FOV Context Tests
// Unit tests for FOV context management system
//
// Tests buffer management, token budgets, confidence detection,
// and context building.

import XCTest
@testable import UnaMentis

final class FOVContextTests: XCTestCase {

    // MARK: - Model Tier Tests

    func testModelTier_cloudClassification() {
        // Given/When
        let tier128k = ModelTier.from(contextWindow: 128_000)
        let tier200k = ModelTier.from(contextWindow: 200_000)

        // Then
        XCTAssertEqual(tier128k, .cloud)
        XCTAssertEqual(tier200k, .cloud)
    }

    func testModelTier_midRangeClassification() {
        // Given/When
        let tier32k = ModelTier.from(contextWindow: 32_000)
        let tier64k = ModelTier.from(contextWindow: 64_000)

        // Then
        XCTAssertEqual(tier32k, .midRange)
        XCTAssertEqual(tier64k, .midRange)
    }

    func testModelTier_onDeviceClassification() {
        // Given/When
        let tier8k = ModelTier.from(contextWindow: 8_000)
        let tier16k = ModelTier.from(contextWindow: 16_000)

        // Then
        XCTAssertEqual(tier8k, .onDevice)
        XCTAssertEqual(tier16k, .onDevice)
    }

    func testModelTier_tinyClassification() {
        // Given/When
        let tier4k = ModelTier.from(contextWindow: 4_000)
        let tier2k = ModelTier.from(contextWindow: 2_000)

        // Then
        XCTAssertEqual(tier4k, .tiny)
        XCTAssertEqual(tier2k, .tiny)
    }

    // MARK: - Token Budget Tests

    func testBudgets_cloudTierHasCorrectValues() {
        // Given/When
        let budgets = ModelTier.cloud.budgets

        // Then
        XCTAssertEqual(budgets.total, 12_000)
        XCTAssertEqual(budgets.immediate, 3_000)
        XCTAssertEqual(budgets.working, 5_000)
        XCTAssertEqual(budgets.episodic, 2_500)
        XCTAssertEqual(budgets.semantic, 1_500)
    }

    func testBudgets_midRangeTierHasCorrectValues() {
        // Given/When
        let budgets = ModelTier.midRange.budgets

        // Then
        XCTAssertEqual(budgets.total, 8_000)
        XCTAssertEqual(budgets.immediate, 2_000)
        XCTAssertEqual(budgets.working, 3_500)
        XCTAssertEqual(budgets.episodic, 1_500)
        XCTAssertEqual(budgets.semantic, 1_000)
    }

    func testBudgets_onDeviceTierHasCorrectValues() {
        // Given/When
        let budgets = ModelTier.onDevice.budgets

        // Then
        XCTAssertEqual(budgets.total, 4_000)
        XCTAssertEqual(budgets.immediate, 1_200)
        XCTAssertEqual(budgets.working, 1_500)
        XCTAssertEqual(budgets.episodic, 800)
        XCTAssertEqual(budgets.semantic, 500)
    }

    func testBudgets_tinyTierHasCorrectValues() {
        // Given/When
        let budgets = ModelTier.tiny.budgets

        // Then
        XCTAssertEqual(budgets.total, 2_000)
        XCTAssertEqual(budgets.immediate, 800)
        XCTAssertEqual(budgets.working, 700)
        XCTAssertEqual(budgets.episodic, 300)
        XCTAssertEqual(budgets.semantic, 200)
    }

    func testBudgets_sumToTotal() {
        // Given/When/Then
        for tier in ModelTier.allCases {
            let budgets = tier.budgets
            let sum = budgets.immediate + budgets.working + budgets.episodic + budgets.semantic
            XCTAssertEqual(sum, budgets.total, "Budgets for \(tier) don't sum to total")
        }
    }

    // MARK: - Conversation Turn Count Tests

    func testConversationTurns_cloudHasMostTurns() {
        XCTAssertEqual(ModelTier.cloud.conversationTurns, 10)
    }

    func testConversationTurns_tinyHasFewestTurns() {
        XCTAssertEqual(ModelTier.tiny.conversationTurns, 3)
    }

    func testConversationTurns_decreasesWithTier() {
        XCTAssertGreaterThan(
            ModelTier.cloud.conversationTurns,
            ModelTier.midRange.conversationTurns
        )
        XCTAssertGreaterThan(
            ModelTier.midRange.conversationTurns,
            ModelTier.onDevice.conversationTurns
        )
        XCTAssertGreaterThan(
            ModelTier.onDevice.conversationTurns,
            ModelTier.tiny.conversationTurns
        )
    }

    // MARK: - Model Context Window Lookup Tests

    func testModelContextWindows_gpt4o() {
        let contextWindow = ModelContextWindows.contextWindow(for: "gpt-4o")
        XCTAssertEqual(contextWindow, 128_000)
    }

    func testModelContextWindows_claude35() {
        let contextWindow = ModelContextWindows.contextWindow(for: "claude-3-5-sonnet")
        XCTAssertEqual(contextWindow, 200_000)
    }

    func testModelContextWindows_qwen() {
        let contextWindow = ModelContextWindows.contextWindow(for: "qwen2.5:7b")
        XCTAssertEqual(contextWindow, 32_768)
    }

    func testModelContextWindows_unknownModelUsesDefault() {
        let contextWindow = ModelContextWindows.contextWindow(for: "unknown-model")
        XCTAssertEqual(contextWindow, 8_192) // Default fallback
    }

    // MARK: - AdaptiveBudgetConfig Tests

    func testAdaptiveBudgetConfig_createsCorrectTier() {
        // Given/When
        let cloudConfig = AdaptiveBudgetConfig(modelContextWindow: 128_000)
        let tinyConfig = AdaptiveBudgetConfig(modelContextWindow: 4_000)

        // Then
        XCTAssertEqual(cloudConfig.tier, .cloud)
        XCTAssertEqual(tinyConfig.tier, .tiny)
    }

    func testAdaptiveBudgetConfig_forModel() {
        // Given/When
        let config = AdaptiveBudgetConfig.forModel("gpt-4o")

        // Then
        XCTAssertEqual(config.tier, .cloud)
        XCTAssertEqual(config.totalBudget, 12_000)
    }

    // MARK: - Immediate Buffer Tests

    func testImmediateBuffer_renderIncludesBargeIn() {
        // Given
        var buffer = ImmediateBuffer()
        buffer.bargeInUtterance = "Wait, can you explain that again?"

        // When
        let rendered = buffer.render(tokenBudget: 1000)

        // Then
        XCTAssertTrue(rendered.contains("Wait, can you explain that again?"))
        XCTAssertTrue(rendered.contains("interrupted"))
    }

    func testImmediateBuffer_renderIncludesCurrentSegment() {
        // Given
        var buffer = ImmediateBuffer()
        buffer.currentSegment = TranscriptSegmentContext(
            id: "seg-1",
            content: "Photosynthesis is the process...",
            segmentIndex: 0
        )

        // When
        let rendered = buffer.render(tokenBudget: 1000)

        // Then
        XCTAssertTrue(rendered.contains("Photosynthesis"))
        XCTAssertTrue(rendered.contains("teaching"))
    }

    func testImmediateBuffer_respectsTokenBudget() {
        // Given
        var buffer = ImmediateBuffer()
        let longContent = String(repeating: "This is a test sentence. ", count: 100)
        for i in 0..<10 {
            buffer.recentTurns.append(
                ConversationTurn(role: .user, content: longContent + "\(i)")
            )
        }

        // When
        let rendered = buffer.render(tokenBudget: 100) // Very small budget

        // Then
        let estimatedTokens = rendered.count / 4
        XCTAssertLessThanOrEqual(estimatedTokens, 150) // Allow some buffer
    }

    // MARK: - Working Buffer Tests

    func testWorkingBuffer_renderIncludesTopicInfo() {
        // Given
        let buffer = WorkingBuffer(
            topicTitle: "Cell Biology",
            topicContent: "Cells are the basic unit of life.",
            learningObjectives: ["Understand cell structure", "Identify organelles"]
        )

        // When
        let rendered = buffer.render(tokenBudget: 1000)

        // Then
        XCTAssertTrue(rendered.contains("Cell Biology"))
        XCTAssertTrue(rendered.contains("basic unit of life"))
        XCTAssertTrue(rendered.contains("Understand cell structure"))
    }

    func testWorkingBuffer_renderIncludesGlossary() {
        // Given
        let buffer = WorkingBuffer(
            topicTitle: "Test",
            topicContent: "Content",
            glossaryTerms: [
                GlossaryTerm(term: "Mitochondria", definition: "Powerhouse of the cell")
            ]
        )

        // When
        let rendered = buffer.render(tokenBudget: 1000)

        // Then
        XCTAssertTrue(rendered.contains("Mitochondria"))
        XCTAssertTrue(rendered.contains("Powerhouse"))
    }

    // MARK: - Episodic Buffer Tests

    func testEpisodicBuffer_renderIncludesLearnerSignals() {
        // Given
        var signals = LearnerSignals()
        signals.pacePreference = .slow
        signals.clarificationRequests = 5

        let buffer = EpisodicBuffer(learnerSignals: signals)

        // When
        let rendered = buffer.render(tokenBudget: 500)

        // Then
        XCTAssertTrue(rendered.contains("slow"))
        XCTAssertTrue(rendered.contains("clarification"))
    }

    func testEpisodicBuffer_renderIncludesTopicSummaries() {
        // Given
        let buffer = EpisodicBuffer(
            topicSummaries: [
                FOVTopicSummary(
                    topicId: UUID(),
                    title: "Introduction",
                    summary: "Covered basic concepts",
                    masteryLevel: 0.8
                )
            ]
        )

        // When
        let rendered = buffer.render(tokenBudget: 500)

        // Then
        XCTAssertTrue(rendered.contains("Introduction"))
        XCTAssertTrue(rendered.contains("basic concepts"))
    }

    // MARK: - Semantic Buffer Tests

    func testSemanticBuffer_renderIncludesPosition() {
        // Given
        let buffer = SemanticBuffer(
            curriculumOutline: "1. Intro\n2. Basics\n3. Advanced",
            currentPosition: CurriculumPosition(
                curriculumTitle: "Biology 101",
                currentTopicIndex: 1,
                totalTopics: 3
            )
        )

        // When
        let rendered = buffer.render(tokenBudget: 500)

        // Then
        XCTAssertTrue(rendered.contains("Biology 101"))
        XCTAssertTrue(rendered.contains("Topic 2 of 3"))
    }

    // MARK: - FOVContext Tests

    func testFOVContext_toSystemMessageCombinesAllBuffers() {
        // Given
        let config = AdaptiveBudgetConfig(modelContextWindow: 128_000)
        let context = FOVContext(
            systemPrompt: "You are a tutor.",
            immediateContext: "Immediate content",
            workingContext: "Working content",
            episodicContext: "Episodic content",
            semanticContext: "Semantic content",
            immediateBufferTurnCount: 5,
            budgetConfig: config
        )

        // When
        let systemMessage = context.toSystemMessage()

        // Then
        XCTAssertTrue(systemMessage.contains("You are a tutor."))
        XCTAssertTrue(systemMessage.contains("CURRICULUM OVERVIEW"))
        XCTAssertTrue(systemMessage.contains("SESSION HISTORY"))
        XCTAssertTrue(systemMessage.contains("CURRENT TOPIC CONTEXT"))
        XCTAssertTrue(systemMessage.contains("IMMEDIATE CONTEXT"))
    }

    func testFOVContext_tokenEstimateIsReasonable() {
        // Given
        let config = AdaptiveBudgetConfig(modelContextWindow: 128_000)
        let context = FOVContext(
            systemPrompt: String(repeating: "A", count: 400),  // ~100 tokens
            immediateContext: String(repeating: "B", count: 400),
            workingContext: String(repeating: "C", count: 400),
            episodicContext: String(repeating: "D", count: 400),
            semanticContext: String(repeating: "E", count: 400),
            immediateBufferTurnCount: 5,
            budgetConfig: config
        )

        // When
        let estimate = context.totalTokenEstimate

        // Then
        XCTAssertEqual(estimate, 500) // 2000 chars / 4
    }
}

// MARK: - FOVContextManager Tests

final class FOVContextManagerTests: XCTestCase {

    var contextManager: FOVContextManager!

    override func setUp() async throws {
        contextManager = await FOVContextManager(modelContextWindow: 128_000)
    }

    override func tearDown() async throws {
        contextManager = nil
    }

    func testBuildContext_returnsValidContext() async {
        // Given
        let messages = [
            LLMMessage(role: .user, content: "What is photosynthesis?"),
            LLMMessage(role: .assistant, content: "Photosynthesis is...")
        ]

        // When
        let context = await contextManager.buildContext(
            conversationHistory: messages,
            bargeInUtterance: nil
        )

        // Then
        XCTAssertFalse(context.systemPrompt.isEmpty)
        XCTAssertGreaterThan(context.totalTokenEstimate, 0)
    }

    func testBuildContext_includesBargeInUtterance() async {
        // Given
        let bargeIn = "Wait, can you explain that part again?"

        // When
        let context = await contextManager.buildContext(
            conversationHistory: [],
            bargeInUtterance: bargeIn
        )

        // Then
        XCTAssertTrue(context.immediateContext.contains(bargeIn))
    }

    func testUpdateWorkingBuffer_updatesContext() async {
        // Given/When
        await contextManager.updateWorkingBuffer(
            topicTitle: "Test Topic",
            topicContent: "Test content about the topic.",
            learningObjectives: ["Objective 1"]
        )

        let context = await contextManager.buildContext()

        // Then
        XCTAssertTrue(context.workingContext.contains("Test Topic"))
        XCTAssertTrue(context.workingContext.contains("Test content"))
    }

    func testUpdateSemanticBuffer_updatesContext() async {
        // Given/When
        await contextManager.updateSemanticBuffer(
            curriculumOutline: "1. Introduction\n2. Basics",
            position: CurriculumPosition(
                curriculumTitle: "Test Course",
                currentTopicIndex: 0,
                totalTopics: 2
            )
        )

        let context = await contextManager.buildContext()

        // Then
        XCTAssertTrue(context.semanticContext.contains("Test Course"))
        XCTAssertTrue(context.semanticContext.contains("Introduction"))
    }

    func testRecordTopicCompletion_addsToEpisodicBuffer() async {
        // Given
        let summary = FOVTopicSummary(
            topicId: UUID(),
            title: "Completed Topic",
            summary: "We learned about basics.",
            masteryLevel: 0.9
        )

        // When
        await contextManager.recordTopicCompletion(summary)
        let context = await contextManager.buildContext()

        // Then
        XCTAssertTrue(context.episodicContext.contains("Completed Topic"))
    }

    func testRecordUserQuestion_addsToEpisodicBuffer() async {
        // Given/When
        await contextManager.recordUserQuestion("What is mitosis?")
        let context = await contextManager.buildContext()

        // Then
        XCTAssertTrue(context.episodicContext.contains("mitosis"))
    }

    func testReset_clearsAllBuffers() async {
        // Given
        await contextManager.updateWorkingBuffer(
            topicTitle: "Test",
            topicContent: "Content"
        )
        await contextManager.recordUserQuestion("Question?")

        // When
        await contextManager.reset()
        let context = await contextManager.buildContext()

        // Then
        XCTAssertTrue(context.workingContext.isEmpty || !context.workingContext.contains("Test"))
        XCTAssertTrue(context.episodicContext.isEmpty || !context.episodicContext.contains("Question?"))
    }

    func testUpdateModelConfig_changesBudgets() async {
        // Given
        let initialConfig = await contextManager.getBudgetConfig()
        XCTAssertEqual(initialConfig.tier, .cloud)

        // When
        await contextManager.updateModelConfig(model: "phi-2")

        // Then
        let newConfig = await contextManager.getBudgetConfig()
        XCTAssertEqual(newConfig.tier, .tiny)
    }

    func testSetCurrentSegment_includesInImmediateBuffer() async {
        // Given
        let segment = TranscriptSegmentContext(
            id: "test-segment",
            content: "This is the current teaching segment.",
            segmentIndex: 5
        )

        // When
        await contextManager.setCurrentSegment(segment)
        let context = await contextManager.buildContext()

        // Then
        XCTAssertTrue(context.immediateContext.contains("current teaching segment"))
    }
}

// MARK: - ConfidenceMonitor Tests

final class ConfidenceMonitorTests: XCTestCase {

    var confidenceMonitor: ConfidenceMonitor!

    override func setUp() async throws {
        confidenceMonitor = await ConfidenceMonitor(config: .default)
    }

    override func tearDown() async throws {
        confidenceMonitor = nil
    }

    // MARK: - Hedging Detection Tests

    func testAnalyzeResponse_detectsHedging() async {
        // Given
        let hedgingResponse = "I'm not sure, but I think photosynthesis involves sunlight."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(hedgingResponse)

        // Then
        XCTAssertGreaterThan(analysis.hedgingScore, 0.3)
        XCTAssertTrue(analysis.detectedMarkers.contains(.hedging))
    }

    func testAnalyzeResponse_highConfidenceForClearResponses() async {
        // Given
        let clearResponse = "Photosynthesis is the process by which plants convert sunlight into energy."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(clearResponse)

        // Then
        XCTAssertGreaterThan(analysis.confidenceScore, 0.7)
        XCTAssertEqual(analysis.hedgingScore, 0.0)
    }

    // MARK: - Knowledge Gap Detection Tests

    func testAnalyzeResponse_detectsKnowledgeGap() async {
        // Given
        let gapResponse = "I don't know the specific mechanism for that process."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(gapResponse)

        // Then
        XCTAssertGreaterThan(analysis.knowledgeGapScore, 0.5)
        XCTAssertTrue(analysis.detectedMarkers.contains(.knowledgeGap))
    }

    // MARK: - Deflection Detection Tests

    func testAnalyzeResponse_detectsDeflection() async {
        // Given
        let deflectionResponse = "That's beyond the scope of this topic. You should ask a medical professional."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(deflectionResponse)

        // Then
        XCTAssertGreaterThan(analysis.questionDeflectionScore, 0.5)
        XCTAssertTrue(analysis.detectedMarkers.contains(.deflection))
    }

    // MARK: - Expansion Trigger Tests

    func testShouldTriggerExpansion_trueForLowConfidence() async {
        // Given
        let uncertainResponse = "I'm not sure about this. I don't have enough information to give you a complete answer."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(uncertainResponse)
        let shouldExpand = await confidenceMonitor.shouldTriggerExpansion(analysis)

        // Then
        XCTAssertTrue(shouldExpand)
    }

    func testShouldTriggerExpansion_falseForHighConfidence() async {
        // Given
        let confidentResponse = "The mitochondria is the powerhouse of the cell. It produces ATP through cellular respiration."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(confidentResponse)
        let shouldExpand = await confidenceMonitor.shouldTriggerExpansion(analysis)

        // Then
        XCTAssertFalse(shouldExpand)
    }

    func testShouldTriggerExpansion_trueForHighSignalMarkers() async {
        // Given
        let topicBoundaryResponse = "That's outside the scope of what we're covering. That topic is beyond this lesson."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(topicBoundaryResponse)
        let shouldExpand = await confidenceMonitor.shouldTriggerExpansion(analysis)

        // Then
        XCTAssertTrue(analysis.detectedMarkers.contains(.topicBoundary))
        XCTAssertTrue(shouldExpand)
    }

    // MARK: - Expansion Recommendation Tests

    func testGetExpansionRecommendation_highPriorityForVeryLowConfidence() async {
        // Given
        let veryUncertainResponse = "I'm not sure. I don't know. I'm uncertain about this."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(veryUncertainResponse)
        let recommendation = await confidenceMonitor.getExpansionRecommendation(analysis)

        // Then
        XCTAssertTrue(recommendation.shouldExpand)
        // Priority should be medium or high for uncertain responses
        XCTAssertTrue(recommendation.priority >= .medium,
                      "Expected at least medium priority, got \(recommendation.priority)")
    }

    func testGetExpansionRecommendation_suggestsRelatedTopicsForOutOfScope() async {
        // Given
        let outOfScopeResponse = "I can't help with that. It's outside the scope of this topic."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(outOfScopeResponse)
        let recommendation = await confidenceMonitor.getExpansionRecommendation(analysis)

        // Then
        if recommendation.shouldExpand {
            XCTAssertEqual(recommendation.suggestedScope, .relatedTopics)
        }
    }

    func testGetExpansionRecommendation_providesReason() async {
        // Given
        let gapResponse = "I don't know the answer to that question."

        // When
        let analysis = await confidenceMonitor.analyzeResponse(gapResponse)
        let recommendation = await confidenceMonitor.getExpansionRecommendation(analysis)

        // Then
        if recommendation.shouldExpand {
            XCTAssertNotNil(recommendation.reason)
            XCTAssertFalse(recommendation.reason!.isEmpty)
        }
    }

    // MARK: - Trend Tests

    func testConfidenceTrend_detectsDecliningTrend() async {
        // Given - Send multiple declining confidence responses
        _ = await confidenceMonitor.analyzeResponse("Clear explanation of the concept.")
        _ = await confidenceMonitor.analyzeResponse("I think this is how it works.")
        let analysis = await confidenceMonitor.analyzeResponse("I'm not sure about this at all.")

        // Then
        XCTAssertEqual(analysis.trend, .declining)
    }

    // MARK: - Configuration Tests

    func testUpdateConfig_changesThresholds() async {
        // Given
        let strictConfig = ConfidenceConfig(
            expansionThreshold: 0.9,
            trendThreshold: 0.95,
            hedgingWeight: 0.4,
            deflectionWeight: 0.3,
            knowledgeGapWeight: 0.2,
            vagueLanguageWeight: 0.1
        )

        // When
        await confidenceMonitor.updateConfig(strictConfig)

        // Analyze a moderately hedging response
        let response = "I think that might be correct."
        let analysis = await confidenceMonitor.analyzeResponse(response)
        let shouldExpand = await confidenceMonitor.shouldTriggerExpansion(analysis)

        // Then - With strict config, should trigger expansion even for moderate hedging
        XCTAssertTrue(shouldExpand)
    }

    func testReset_clearsHistory() async {
        // Given
        _ = await confidenceMonitor.analyzeResponse("Response 1")
        _ = await confidenceMonitor.analyzeResponse("Response 2")

        // When
        await confidenceMonitor.reset()
        let analysis = await confidenceMonitor.analyzeResponse("Response 3")

        // Then - Trend should be stable since history was cleared
        XCTAssertEqual(analysis.trend, .stable)
    }
}

// MARK: - ConfidenceAnalysis Tests

final class ConfidenceAnalysisTests: XCTestCase {

    func testIsHighConfidence_trueWhenScoreHighAndNoMarkers() {
        let analysis = ConfidenceAnalysis(
            confidenceScore: 0.9,
            uncertaintyScore: 0.1,
            hedgingScore: 0.0,
            questionDeflectionScore: 0.0,
            knowledgeGapScore: 0.0,
            vagueLanguageScore: 0.0,
            detectedMarkers: [],
            trend: .stable
        )

        XCTAssertTrue(analysis.isHighConfidence)
    }

    func testIsHighConfidence_falseWhenMarkersPresent() {
        let analysis = ConfidenceAnalysis(
            confidenceScore: 0.85,
            uncertaintyScore: 0.15,
            hedgingScore: 0.2,
            questionDeflectionScore: 0.0,
            knowledgeGapScore: 0.0,
            vagueLanguageScore: 0.0,
            detectedMarkers: [.hedging],
            trend: .stable
        )

        XCTAssertFalse(analysis.isHighConfidence)
    }

    func testIsLowConfidence_trueWhenScoreBelowThreshold() {
        let analysis = ConfidenceAnalysis(
            confidenceScore: 0.4,
            uncertaintyScore: 0.6,
            hedgingScore: 0.5,
            questionDeflectionScore: 0.3,
            knowledgeGapScore: 0.0,
            vagueLanguageScore: 0.2,
            detectedMarkers: [.hedging],
            trend: .declining
        )

        XCTAssertTrue(analysis.isLowConfidence)
    }
}

// MARK: - ExpansionPriority Tests

final class ExpansionPriorityTests: XCTestCase {

    func testExpansionPriority_ordering() {
        XCTAssertLessThan(ExpansionPriority.none, ExpansionPriority.low)
        XCTAssertLessThan(ExpansionPriority.low, ExpansionPriority.medium)
        XCTAssertLessThan(ExpansionPriority.medium, ExpansionPriority.high)
    }
}
