// UnaMentis - Confidence Monitor
// Uncertainty detection for automatic context expansion
//
// Part of FOV Context Management System
//
// Implements the hybrid expansion strategy by detecting:
// 1. Linguistic hedging markers in LLM responses
// 2. Explicit uncertainty signals
// 3. Question deflection patterns

import Foundation
import Logging

/// Actor responsible for analyzing LLM responses for uncertainty
/// and determining when context expansion is needed
public actor ConfidenceMonitor {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.confidencemonitor")

    /// Configuration for confidence thresholds
    private var config: ConfidenceConfig

    /// History of recent confidence scores for trend analysis
    private var recentScores: [Double] = []
    private let maxHistorySize = 10

    // MARK: - Initialization

    /// Initialize with default configuration
    public init(config: ConfidenceConfig = .default) {
        self.config = config
        logger.info("ConfidenceMonitor initialized")
    }

    // MARK: - Analysis

    /// Analyze an LLM response for uncertainty markers
    /// - Parameter response: The LLM's response text
    /// - Returns: Confidence analysis result
    public func analyzeResponse(_ response: String) -> ConfidenceAnalysis {
        let normalizedResponse = response.lowercased()

        // Calculate scores for each uncertainty dimension
        let hedgingScore = calculateHedgingScore(normalizedResponse)
        let questionDeflectionScore = calculateQuestionDeflectionScore(normalizedResponse)
        let knowledgeGapScore = calculateKnowledgeGapScore(normalizedResponse)
        let vagueLanguageScore = calculateVagueLanguageScore(normalizedResponse)

        // Weighted combination of scores
        let uncertaintyScore = (
            hedgingScore * config.hedgingWeight +
            questionDeflectionScore * config.deflectionWeight +
            knowledgeGapScore * config.knowledgeGapWeight +
            vagueLanguageScore * config.vagueLanguageWeight
        )

        // Confidence is inverse of uncertainty
        let confidenceScore = max(0, 1 - uncertaintyScore)

        // Detect specific markers
        let detectedMarkers = detectSpecificMarkers(normalizedResponse)

        // Record score for trend analysis
        recordScore(confidenceScore)

        let analysis = ConfidenceAnalysis(
            confidenceScore: confidenceScore,
            uncertaintyScore: uncertaintyScore,
            hedgingScore: hedgingScore,
            questionDeflectionScore: questionDeflectionScore,
            knowledgeGapScore: knowledgeGapScore,
            vagueLanguageScore: vagueLanguageScore,
            detectedMarkers: detectedMarkers,
            trend: calculateTrend()
        )

        logger.debug(
            "Analyzed response confidence",
            metadata: [
                "confidence": .stringConvertible(confidenceScore),
                "markers": .stringConvertible(detectedMarkers.count)
            ]
        )

        return analysis
    }

    /// Determine if context expansion should be triggered
    /// - Parameter analysis: The confidence analysis result
    /// - Returns: Whether expansion should be triggered
    public func shouldTriggerExpansion(_ analysis: ConfidenceAnalysis) -> Bool {
        // Primary check: confidence below threshold
        if analysis.confidenceScore < config.expansionThreshold {
            return true
        }

        // Secondary check: specific high-signal markers detected
        let highSignalMarkers = analysis.detectedMarkers.filter { marker in
            ConfidenceMarker.highSignalMarkers.contains(marker)
        }
        if !highSignalMarkers.isEmpty {
            return true
        }

        // Trend check: declining confidence over recent responses
        if analysis.trend == .declining && analysis.confidenceScore < config.trendThreshold {
            return true
        }

        return false
    }

    /// Get expansion recommendation based on analysis
    /// - Parameter analysis: The confidence analysis result
    /// - Returns: Expansion recommendation
    public func getExpansionRecommendation(_ analysis: ConfidenceAnalysis) -> ExpansionRecommendation {
        guard shouldTriggerExpansion(analysis) else {
            return ExpansionRecommendation(
                shouldExpand: false,
                priority: .none,
                suggestedScope: .currentTopic,
                reason: nil
            )
        }

        // Determine priority based on severity
        let priority: ExpansionPriority
        if analysis.confidenceScore < 0.3 {
            priority = .high
        } else if analysis.confidenceScore < 0.5 {
            priority = .medium
        } else {
            priority = .low
        }

        // Determine scope based on detected markers
        let scope: ExpansionScope
        if analysis.detectedMarkers.contains(.outOfScope) ||
           analysis.detectedMarkers.contains(.topicBoundary) {
            scope = .relatedTopics
        } else if analysis.knowledgeGapScore > 0.5 {
            scope = .currentUnit
        } else {
            scope = .currentTopic
        }

        // Determine reason
        let reason = determineExpansionReason(analysis)

        return ExpansionRecommendation(
            shouldExpand: true,
            priority: priority,
            suggestedScope: scope,
            reason: reason
        )
    }

    // MARK: - Score Calculations

    /// Calculate hedging language score
    private func calculateHedgingScore(_ text: String) -> Double {
        let hedgingPhrases = [
            "i'm not sure": 0.8,
            "i think": 0.4,
            "i believe": 0.4,
            "i'm uncertain": 0.9,
            "i'm not certain": 0.9,
            "possibly": 0.5,
            "perhaps": 0.5,
            "maybe": 0.5,
            "might be": 0.5,
            "could be": 0.5,
            "it seems": 0.4,
            "it appears": 0.4,
            "to my knowledge": 0.6,
            "as far as i know": 0.6,
            "i would guess": 0.7,
            "if i recall": 0.6,
            "not entirely sure": 0.8,
            "don't quote me": 0.9,
            "take this with a grain": 0.8
        ]

        var totalScore: Double = 0
        var matchCount = 0

        for (phrase, weight) in hedgingPhrases {
            if text.contains(phrase) {
                totalScore += weight
                matchCount += 1
            }
        }

        // Normalize: more matches = higher uncertainty
        return matchCount > 0 ? min(1.0, totalScore / Double(max(1, matchCount))) : 0
    }

    /// Calculate question deflection score
    private func calculateQuestionDeflectionScore(_ text: String) -> Double {
        let deflectionPhrases = [
            "i don't have enough information": 0.9,
            "i can't answer that": 0.8,
            "that's beyond": 0.7,
            "outside my": 0.7,
            "you should ask": 0.6,
            "consult a": 0.5,
            "i'd recommend checking": 0.6,
            "let me redirect": 0.6,
            "that question is": 0.5,
            "i'm not the right": 0.7,
            "that's a great question for": 0.6
        ]

        var maxScore: Double = 0
        for (phrase, weight) in deflectionPhrases {
            if text.contains(phrase) {
                maxScore = max(maxScore, weight)
            }
        }

        return maxScore
    }

    /// Calculate knowledge gap score
    private func calculateKnowledgeGapScore(_ text: String) -> Double {
        let gapIndicators = [
            "i don't know": 0.9,
            "i'm not familiar": 0.8,
            "i haven't learned": 0.8,
            "that's not something i": 0.7,
            "my training doesn't": 0.8,
            "i lack the context": 0.9,
            "without more information": 0.7,
            "i need more details": 0.6,
            "could you clarify": 0.5,
            "what do you mean by": 0.4,
            "can you be more specific": 0.5,
            "i'm missing": 0.7,
            "there's a gap in": 0.8
        ]

        var maxScore: Double = 0
        for (phrase, weight) in gapIndicators {
            if text.contains(phrase) {
                maxScore = max(maxScore, weight)
            }
        }

        return maxScore
    }

    /// Calculate vague language score
    private func calculateVagueLanguageScore(_ text: String) -> Double {
        let vagueTerms = [
            "something like": 0.5,
            "sort of": 0.4,
            "kind of": 0.4,
            "more or less": 0.5,
            "roughly": 0.4,
            "approximately": 0.3,
            "in general": 0.3,
            "generally speaking": 0.3,
            "it depends": 0.5,
            "various": 0.3,
            "several": 0.2,
            "some": 0.1, // Low weight, very common
            "typically": 0.2,
            "usually": 0.2
        ]

        var totalScore: Double = 0
        var matchCount = 0

        for (term, weight) in vagueTerms {
            // Count occurrences
            let count = text.components(separatedBy: term).count - 1
            if count > 0 {
                totalScore += weight * Double(min(count, 3)) // Cap at 3 occurrences
                matchCount += count
            }
        }

        // Normalize by response length (vague terms in short responses are more significant)
        let lengthFactor = Double(min(500, text.count)) / 500.0
        return min(1.0, totalScore * (1.5 - lengthFactor * 0.5))
    }

    /// Detect specific uncertainty markers
    private func detectSpecificMarkers(_ text: String) -> Set<ConfidenceMarker> {
        var markers: Set<ConfidenceMarker> = []

        // Hedging markers
        if text.contains("i'm not sure") || text.contains("i'm uncertain") {
            markers.insert(.hedging)
        }

        // Knowledge gap markers
        if text.contains("i don't know") || text.contains("i'm not familiar") {
            markers.insert(.knowledgeGap)
        }

        // Deflection markers
        if text.contains("you should ask") || text.contains("consult a") {
            markers.insert(.deflection)
        }

        // Topic boundary markers
        if text.contains("that's outside") || text.contains("beyond the scope") {
            markers.insert(.topicBoundary)
        }

        // Out of scope markers
        if text.contains("i can't help with") || text.contains("not within my") {
            markers.insert(.outOfScope)
        }

        // Clarification request markers
        if text.contains("could you clarify") || text.contains("what do you mean") {
            markers.insert(.clarificationNeeded)
        }

        // Speculation markers
        if text.contains("my guess") || text.contains("i would speculate") {
            markers.insert(.speculation)
        }

        return markers
    }

    // MARK: - Trend Analysis

    /// Record a confidence score for trend analysis
    private func recordScore(_ score: Double) {
        recentScores.append(score)
        if recentScores.count > maxHistorySize {
            recentScores.removeFirst()
        }
    }

    /// Calculate confidence trend
    private func calculateTrend() -> ConfidenceTrend {
        guard recentScores.count >= 3 else {
            return .stable
        }

        let recent = Array(recentScores.suffix(3))
        let oldest = recent[0]
        let newest = recent[2]

        let delta = newest - oldest

        if delta > 0.15 {
            return .improving
        } else if delta < -0.15 {
            return .declining
        }
        return .stable
    }

    /// Determine the reason for expansion recommendation
    private func determineExpansionReason(_ analysis: ConfidenceAnalysis) -> String {
        if analysis.knowledgeGapScore > 0.5 {
            return "Knowledge gap detected in response"
        }
        if analysis.hedgingScore > 0.6 {
            return "High uncertainty in response language"
        }
        if analysis.questionDeflectionScore > 0.5 {
            return "Response deflected the question"
        }
        if analysis.detectedMarkers.contains(.clarificationNeeded) {
            return "Response requested clarification"
        }
        if analysis.trend == .declining {
            return "Declining confidence trend"
        }
        return "Low overall confidence score"
    }

    // MARK: - Configuration

    /// Update confidence configuration
    public func updateConfig(_ config: ConfidenceConfig) {
        self.config = config
        logger.info("Updated confidence config")
    }

    /// Reset history
    public func reset() {
        recentScores.removeAll()
    }
}

// MARK: - Supporting Types

/// Configuration for confidence monitoring
public struct ConfidenceConfig: Sendable {
    /// Threshold below which expansion is triggered
    public var expansionThreshold: Double

    /// Threshold for trend-based expansion
    public var trendThreshold: Double

    /// Weight for hedging language
    public var hedgingWeight: Double

    /// Weight for question deflection
    public var deflectionWeight: Double

    /// Weight for knowledge gaps
    public var knowledgeGapWeight: Double

    /// Weight for vague language
    public var vagueLanguageWeight: Double

    public static let `default` = ConfidenceConfig(
        expansionThreshold: 0.6,
        trendThreshold: 0.7,
        hedgingWeight: 0.3,
        deflectionWeight: 0.25,
        knowledgeGapWeight: 0.3,
        vagueLanguageWeight: 0.15
    )

    /// More sensitive configuration for tutoring
    public static let tutoring = ConfidenceConfig(
        expansionThreshold: 0.7,
        trendThreshold: 0.75,
        hedgingWeight: 0.25,
        deflectionWeight: 0.3,
        knowledgeGapWeight: 0.35,
        vagueLanguageWeight: 0.1
    )

    public init(
        expansionThreshold: Double,
        trendThreshold: Double,
        hedgingWeight: Double,
        deflectionWeight: Double,
        knowledgeGapWeight: Double,
        vagueLanguageWeight: Double
    ) {
        self.expansionThreshold = expansionThreshold
        self.trendThreshold = trendThreshold
        self.hedgingWeight = hedgingWeight
        self.deflectionWeight = deflectionWeight
        self.knowledgeGapWeight = knowledgeGapWeight
        self.vagueLanguageWeight = vagueLanguageWeight
    }
}

/// Result of analyzing response confidence
public struct ConfidenceAnalysis: Sendable {
    /// Overall confidence score (0.0 = uncertain, 1.0 = confident)
    public let confidenceScore: Double

    /// Overall uncertainty score (inverse of confidence)
    public let uncertaintyScore: Double

    /// Score from hedging language detection
    public let hedgingScore: Double

    /// Score from question deflection detection
    public let questionDeflectionScore: Double

    /// Score from knowledge gap detection
    public let knowledgeGapScore: Double

    /// Score from vague language detection
    public let vagueLanguageScore: Double

    /// Specific uncertainty markers detected
    public let detectedMarkers: Set<ConfidenceMarker>

    /// Trend over recent responses
    public let trend: ConfidenceTrend

    /// Whether response indicates high confidence
    public var isHighConfidence: Bool {
        confidenceScore >= 0.8 && detectedMarkers.isEmpty
    }

    /// Whether response indicates low confidence
    public var isLowConfidence: Bool {
        confidenceScore < 0.5
    }
}

/// Specific markers of uncertainty
public enum ConfidenceMarker: String, Sendable, CaseIterable {
    case hedging
    case knowledgeGap
    case deflection
    case topicBoundary
    case outOfScope
    case clarificationNeeded
    case speculation

    /// Markers that strongly indicate expansion is needed
    public static let highSignalMarkers: Set<ConfidenceMarker> = [
        .knowledgeGap,
        .outOfScope,
        .topicBoundary
    ]
}

/// Confidence trend over recent responses
public enum ConfidenceTrend: String, Sendable {
    case improving
    case stable
    case declining
}

/// Recommendation for context expansion
public struct ExpansionRecommendation: Sendable {
    /// Whether expansion should be performed
    public let shouldExpand: Bool

    /// Priority level for expansion
    public let priority: ExpansionPriority

    /// Suggested scope for expansion search
    public let suggestedScope: ExpansionScope

    /// Reason for the recommendation
    public let reason: String?
}

/// Priority level for expansion
public enum ExpansionPriority: String, Sendable, Comparable {
    case none
    case low
    case medium
    case high

    public static func < (lhs: ExpansionPriority, rhs: ExpansionPriority) -> Bool {
        let order: [ExpansionPriority] = [.none, .low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}
