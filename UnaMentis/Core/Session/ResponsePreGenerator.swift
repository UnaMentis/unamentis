// UnaMentis - Response Pre-Generator
// Speculative response generation during idle periods for zero-latency feel
//
// Part of Zero-Latency Response System
//
// During idle time (user listening to TTS, thinking), the on-device LLM
// pre-generates probable response starters. If a starter matches the user's
// actual intent, it's used immediately; otherwise discarded.

import Foundation
import Logging

/// Speculates probable response starters during idle time
///
/// Generates short (first-sentence-only) responses for likely user intents
/// based on the current FOV context. Results are cached and invalidated
/// when context shifts (new segment, topic change).
public actor ResponsePreGenerator {

    // MARK: - Types

    /// A pre-generated response starter
    public struct PreGeneratedStarter: Sendable {
        /// The scenario this was generated for
        public let scenario: Scenario
        /// The generated text (first sentence only)
        public let text: String
        /// When this was generated
        public let generatedAt: Date
        /// Whether this has been consumed
        public var isConsumed: Bool = false
    }

    /// Scenarios to pre-generate responses for
    public enum Scenario: String, CaseIterable, Sendable {
        /// User asks about the current topic
        case questionAboutTopic
        /// User asks to repeat what was just said
        case repeatRequest
        /// User gives a correct answer
        case correctAnswer
        /// User gives a wrong answer
        case wrongAnswer
        /// User asks to move on
        case moveOn
    }

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.pregenerate")

    /// Cached pre-generated starters
    private var starters: [Scenario: PreGeneratedStarter] = [:]

    /// Currently active generation tasks
    private var generationTasks: [Scenario: Task<Void, Never>] = [:]

    /// Context fingerprint for cache invalidation
    private var contextFingerprint: String = ""

    /// Whether pre-generation is currently running
    public private(set) var isGenerating: Bool = false

    /// Maximum tokens per speculative starter
    private var maxTokens: Int {
        Int(UserDefaults.standard.double(forKey: "zerolatency_pregenMaxTokens"))
            .clamped(to: 10...100, default: 30)
    }

    /// Number of scenarios to pre-generate
    private var scenarioCount: Int {
        Int(UserDefaults.standard.double(forKey: "zerolatency_pregenCount"))
            .clamped(to: 1...5, default: 3)
    }

    // MARK: - Public API

    /// Pre-generate responses for likely scenarios using the given LLM service and context
    /// - Parameters:
    ///   - llmService: LLM service for generation
    ///   - fovContext: Current FOV context (provides topic awareness)
    ///   - conversationHistory: Recent conversation for context
    public func preGenerate(
        using llmService: any LLMService,
        fovContext: FOVContext?,
        conversationHistory: [LLMMessage]
    ) async {
        guard UserDefaults.standard.bool(forKey: "zerolatency_pregenEnabled") else { return }

        // Check if context has changed (invalidate cache if so)
        let newFingerprint = buildFingerprint(fovContext: fovContext, history: conversationHistory)
        if newFingerprint == contextFingerprint && !starters.isEmpty {
            logger.debug("Pre-generation cache still valid, skipping")
            return
        }

        contextFingerprint = newFingerprint
        isGenerating = true

        // Cancel any existing generation tasks
        for (_, task) in generationTasks {
            task.cancel()
        }
        generationTasks.removeAll()
        starters.removeAll()

        // Generate for the top N scenarios
        let scenarios = Array(Scenario.allCases.prefix(scenarioCount))

        for scenario in scenarios {
            let task = Task { [weak self] in
                guard let self = self else { return }
                guard !Task.isCancelled else { return }

                let prompt = await self.buildPrompt(for: scenario, fovContext: fovContext, history: conversationHistory)
                let config = LLMConfig(
                    maxTokens: await self.maxTokens,
                    temperature: 0.7,
                    systemPrompt: nil
                )

                do {
                    var text = ""
                    let stream = try await llmService.streamCompletion(
                        messages: [LLMMessage(role: .user, content: prompt)],
                        config: config
                    )

                    for await token in stream {
                        guard !Task.isCancelled else { break }
                        text += token.content

                        // Stop at first sentence boundary
                        if text.containsSentenceEnd() {
                            text = text.upToFirstSentenceEnd()
                            break
                        }

                        if token.isDone { break }
                    }

                    if !text.isEmpty && !Task.isCancelled {
                        // Strip any thinking blocks (<think>...</think>)
                        let cleaned = Self.stripThinkingBlocks(from: text)
                        await self.cacheStarter(PreGeneratedStarter(
                            scenario: scenario,
                            text: cleaned,
                            generatedAt: Date()
                        ))
                    }
                } catch {
                    if !Task.isCancelled {
                        await self.logError(scenario: scenario, error: error)
                    }
                }
            }
            generationTasks[scenario] = task
        }

        // Wait for all to complete (or cancel)
        for (_, task) in generationTasks {
            await task.value
        }

        generationTasks.removeAll()
        isGenerating = false
        logger.info("Pre-generation complete: \(starters.count) starters cached")
    }

    /// Get a pre-generated starter matching the user's intent
    /// - Parameter utterance: The user's spoken text
    /// - Returns: A matching starter text, or nil if no match
    public func getMatchingStarter(for utterance: String) -> String? {
        let intent = ResponseIntent.classify(from: utterance)
        let scenario = mapIntentToScenario(intent)

        guard let starter = starters[scenario], !starter.isConsumed else {
            return nil
        }

        starters[scenario]?.isConsumed = true
        return starter.text
    }

    /// Invalidate all cached starters (e.g., on topic change)
    public func invalidate() {
        starters.removeAll()
        contextFingerprint = ""
        for (_, task) in generationTasks {
            task.cancel()
        }
        generationTasks.removeAll()
    }

    /// Number of cached starters available
    public var availableCount: Int {
        starters.values.filter { !$0.isConsumed }.count
    }

    // MARK: - Text Processing

    /// Strip thinking blocks (<think>...</think>) from generated text
    static func stripThinkingBlocks(from text: String) -> String {
        var result = text
        while let thinkStart = result.range(of: "<think>"),
              let thinkEnd = result.range(of: "</think>") {
            guard thinkStart.lowerBound < thinkEnd.upperBound else { break }
            result.removeSubrange(thinkStart.lowerBound..<thinkEnd.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helpers

    private func cacheStarter(_ starter: PreGeneratedStarter) {
        starters[starter.scenario] = starter
    }

    private func logError(scenario: Scenario, error: Error) {
        logger.warning(
            "Pre-generation failed",
            metadata: [
                "scenario": .string(scenario.rawValue),
                "error": .string(error.localizedDescription)
            ]
        )
    }

    private func buildFingerprint(fovContext: FOVContext?, history: [LLMMessage]) -> String {
        let historyHash = history.last?.content.prefix(50) ?? ""
        let contextHash = fovContext?.workingContext.prefix(50) ?? ""
        return "\(historyHash)|\(contextHash)"
    }

    private func buildPrompt(
        for scenario: Scenario,
        fovContext: FOVContext?,
        history: [LLMMessage]
    ) -> String {
        let topicContext = fovContext?.workingContext ?? "general learning session"

        switch scenario {
        case .questionAboutTopic:
            return "You are a learning assistant. The student just asked a question about: \(topicContext). Give a brief, helpful opening sentence to start your explanation."
        case .repeatRequest:
            return "You are a learning assistant. The student asked you to repeat or re-explain something about: \(topicContext). Give a brief opening sentence acknowledging and starting the re-explanation."
        case .correctAnswer:
            return "You are a learning assistant. The student just answered correctly about: \(topicContext). Give a brief, encouraging sentence acknowledging their correct answer."
        case .wrongAnswer:
            return "You are a learning assistant. The student gave an incorrect answer about: \(topicContext). Give a brief, supportive sentence redirecting them without discouraging."
        case .moveOn:
            return "You are a learning assistant. The student wants to move to the next topic after: \(topicContext). Give a brief transition sentence."
        }
    }

    private func mapIntentToScenario(_ intent: ResponseIntent) -> Scenario {
        switch intent {
        case .engagement: return .questionAboutTopic
        case .encouragement: return .correctAnswer
        case .redirect: return .wrongAnswer
        case .transition: return .moveOn
        case .clarification: return .repeatRequest
        case .thinking: return .questionAboutTopic
        case .acknowledgment: return .moveOn
        case .socratic: return .questionAboutTopic
        }
    }
}

// MARK: - String Extensions

private extension String {
    func containsSentenceEnd() -> Bool {
        let trimmed = self.trimmingCharacters(in: .whitespaces)
        return trimmed.contains(". ") || trimmed.contains("! ") || trimmed.contains("? ")
            || trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")
    }

    func upToFirstSentenceEnd() -> String {
        let terminators: [Character] = [".", "!", "?"]
        for (i, char) in self.enumerated() {
            if terminators.contains(char) {
                return String(self.prefix(i + 1))
            }
        }
        return self
    }
}

// MARK: - Int Clamping

private extension Int {
    func clamped(to range: ClosedRange<Int>, default defaultValue: Int) -> Int {
        if self == 0 { return defaultValue }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
