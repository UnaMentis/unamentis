//
//  QuestionTransformer.swift
//  UnaMentis
//
//  Protocol for transforming questions between canonical and module-specific formats.
//  Enables cross-module question sharing with format-appropriate conversions.
//

import Foundation

// MARK: - Question Transformer Protocol

/// Protocol for transforming questions between canonical and module-specific formats.
///
/// Modules implement this protocol to convert questions from the shared pool
/// to their specific format, and optionally back to canonical form.
///
/// Example usage:
/// ```swift
/// let transformer = KBTransformer()
/// if let kbQuestion = transformer.transform(canonicalQuestion) {
///     // Use the KB-formatted question
/// }
/// ```
public protocol QuestionTransformer {
    /// The module-specific question type this transformer produces
    associatedtype ModuleQuestion

    /// Transform a canonical question to module-specific format.
    ///
    /// - Parameter canonical: The universal question format
    /// - Returns: Module-specific question, or nil if incompatible
    func transform(_ canonical: CanonicalQuestion) -> ModuleQuestion?

    /// Transform a module-specific question back to canonical format.
    ///
    /// This enables questions created within a module to be shared
    /// with other modules.
    ///
    /// - Parameter question: The module-specific question
    /// - Returns: Canonical question format
    func canonicalize(_ question: ModuleQuestion) -> CanonicalQuestion

    /// Check if a canonical question is compatible with this module.
    ///
    /// Use this for filtering before attempting transformation.
    ///
    /// - Parameter canonical: The question to check
    /// - Returns: true if the question can be transformed for this module
    func isCompatible(_ canonical: CanonicalQuestion) -> Bool

    /// Calculate a quality score for a canonical question.
    ///
    /// Higher scores indicate the question is well-suited for this module.
    /// Used for ranking questions when multiple are available.
    ///
    /// - Parameter canonical: The question to score
    /// - Returns: Quality score from 0.0 (poor fit) to 1.0 (excellent fit)
    func qualityScore(_ canonical: CanonicalQuestion) -> Double
}

// MARK: - Default Implementations

extension QuestionTransformer {
    /// Default compatibility check based on transform success
    public func isCompatible(_ canonical: CanonicalQuestion) -> Bool {
        transform(canonical) != nil
    }

    /// Default quality score based on basic heuristics
    public func qualityScore(_ canonical: CanonicalQuestion) -> Double {
        var score = 0.5

        // Prefer questions with medium form text
        if !canonical.content.mediumForm.isEmpty {
            score += 0.2
        }

        // Prefer questions that can be MCQ
        if canonical.transformationHints.mcqPossible {
            score += 0.1
        }

        // Prefer questions without visual requirements
        if !canonical.transformationHints.requiresVisual {
            score += 0.1
        }

        // Prefer questions with acceptable alternatives
        if let acceptable = canonical.answer.acceptable, !acceptable.isEmpty {
            score += 0.1
        }

        return min(1.0, score)
    }
}

// MARK: - Batch Transformation

extension QuestionTransformer {
    /// Transform a batch of canonical questions.
    ///
    /// - Parameter questions: Array of canonical questions
    /// - Returns: Array of successfully transformed module questions
    public func transformBatch(_ questions: [CanonicalQuestion]) -> [ModuleQuestion] {
        questions.compactMap { transform($0) }
    }

    /// Transform and filter by quality threshold.
    ///
    /// - Parameters:
    ///   - questions: Array of canonical questions
    ///   - threshold: Minimum quality score (0.0 to 1.0)
    /// - Returns: Array of questions meeting the quality threshold
    public func transformFiltered(
        _ questions: [CanonicalQuestion],
        threshold: Double = 0.5
    ) -> [ModuleQuestion] {
        questions
            .filter { qualityScore($0) >= threshold }
            .compactMap { transform($0) }
    }

    /// Sort questions by quality score.
    ///
    /// - Parameter questions: Array of canonical questions
    /// - Returns: Array sorted by quality (highest first)
    public func sortByQuality(_ questions: [CanonicalQuestion]) -> [CanonicalQuestion] {
        questions.sorted { qualityScore($0) > qualityScore($1) }
    }
}

// MARK: - Type-Erased Transformer

/// Type-erased question transformer for use in collections.
///
/// Wraps any QuestionTransformer to enable heterogeneous collections
/// while preserving transformation capability.
public struct AnyQuestionTransformer<ModuleQuestion>: QuestionTransformer {
    private let _transform: (CanonicalQuestion) -> ModuleQuestion?
    private let _canonicalize: (ModuleQuestion) -> CanonicalQuestion
    private let _isCompatible: (CanonicalQuestion) -> Bool
    private let _qualityScore: (CanonicalQuestion) -> Double

    public init<T: QuestionTransformer>(_ transformer: T) where T.ModuleQuestion == ModuleQuestion {
        _transform = transformer.transform
        _canonicalize = transformer.canonicalize
        _isCompatible = transformer.isCompatible
        _qualityScore = transformer.qualityScore
    }

    public func transform(_ canonical: CanonicalQuestion) -> ModuleQuestion? {
        _transform(canonical)
    }

    public func canonicalize(_ question: ModuleQuestion) -> CanonicalQuestion {
        _canonicalize(question)
    }

    public func isCompatible(_ canonical: CanonicalQuestion) -> Bool {
        _isCompatible(canonical)
    }

    public func qualityScore(_ canonical: CanonicalQuestion) -> Double {
        _qualityScore(canonical)
    }
}
