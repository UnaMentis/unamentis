//
//  CanonicalQuestion.swift
//  UnaMentis
//
//  Universal question format for cross-module sharing.
//  Enables questions to be transformed between different competition formats
//  (Knowledge Bowl, Quiz Bowl, Science Bowl, etc.)
//

import Foundation

// MARK: - Canonical Question

/// Universal question format that can be transformed to any module-specific format.
///
/// This is the authoritative format for the shared question pool. Each module
/// transformer can convert to/from this format, enabling question reuse across
/// competition types.
public struct CanonicalQuestion: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let version: Int
    public let createdAt: Date
    public let updatedAt: Date

    // MARK: - Content

    /// Question content in multiple forms for different uses
    public let content: QuestionContent

    /// Answer specification with primary and acceptable alternatives
    public let answer: AnswerSpec

    // MARK: - Classification

    /// Question metadata for filtering and attribution
    public let metadata: QuestionMetadata

    /// Domain classification with primary and secondary tags
    public let domains: [DomainTag]

    /// Difficulty rating with absolute and competition-relative values
    public let difficulty: DifficultyRating

    // MARK: - Compatibility

    /// Competition formats this question is compatible with
    public let compatibleFormats: Set<CompetitionFormat>

    /// Hints for transformation to specific formats
    public let transformationHints: TransformationHints

    public init(
        id: UUID = UUID(),
        version: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        content: QuestionContent,
        answer: AnswerSpec,
        metadata: QuestionMetadata,
        domains: [DomainTag],
        difficulty: DifficultyRating,
        compatibleFormats: Set<CompetitionFormat>,
        transformationHints: TransformationHints = TransformationHints()
    ) {
        self.id = id
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.content = content
        self.answer = answer
        self.metadata = metadata
        self.domains = domains
        self.difficulty = difficulty
        self.compatibleFormats = compatibleFormats
        self.transformationHints = transformationHints
    }
}

// MARK: - Question Content

/// Question text in multiple forms for different use cases
public struct QuestionContent: Codable, Hashable, Sendable {
    /// Full pyramidal form with progressive clues (for Quiz Bowl)
    public let pyramidalFull: String

    /// Medium-length form suitable for most competitions
    public let mediumForm: String

    /// Short form for quick practice or written rounds
    public let shortForm: String

    /// Individual clues parsed from pyramidal form
    public let clues: [String]?

    /// Index marking the "power" position in pyramidal form
    public let powerMarkIndex: Int?

    public init(
        pyramidalFull: String = "",
        mediumForm: String,
        shortForm: String,
        clues: [String]? = nil,
        powerMarkIndex: Int? = nil
    ) {
        self.pyramidalFull = pyramidalFull
        self.mediumForm = mediumForm
        self.shortForm = shortForm
        self.clues = clues
        self.powerMarkIndex = powerMarkIndex
    }

    /// Best available text form (prefers medium, falls back to short)
    public var bestForm: String {
        if !mediumForm.isEmpty { return mediumForm }
        if !shortForm.isEmpty { return shortForm }
        return pyramidalFull
    }
}

// MARK: - Answer Specification

/// Complete answer specification with alternatives and validation hints
public struct AnswerSpec: Codable, Hashable, Sendable {
    /// The canonical correct answer
    public let primary: String

    /// Acceptable alternative answers
    public let acceptable: [String]?

    /// Answers that should be marked incorrect even if close
    public let antipatterns: [String]?

    /// Type of answer for specialized matching
    public let answerType: AnswerType

    /// Whether partial answers are acceptable
    public let partialAcceptable: Bool

    public init(
        primary: String,
        acceptable: [String]? = nil,
        antipatterns: [String]? = nil,
        answerType: AnswerType = .text,
        partialAcceptable: Bool = false
    ) {
        self.primary = primary
        self.acceptable = acceptable
        self.antipatterns = antipatterns
        self.answerType = answerType
        self.partialAcceptable = partialAcceptable
    }

    /// All valid answers including primary and alternatives
    public var allValidAnswers: [String] {
        var answers = [primary]
        if let acceptable = acceptable {
            answers.append(contentsOf: acceptable)
        }
        return answers
    }
}

// MARK: - Answer Type

/// Type of answer for specialized matching logic
public enum AnswerType: String, Codable, CaseIterable, Sendable {
    case text           // Generic text answer
    case person         // Person's name
    case place          // Geographic location
    case number         // Numeric answer
    case date           // Date answer
    case title          // Work title (book, movie, etc.)
    case scientific     // Scientific term or formula
    case thing          // Physical object or concept
}

// MARK: - Question Metadata

/// Metadata for attribution, filtering, and tracking
public struct QuestionMetadata: Codable, Hashable, Sendable {
    /// Source of the question (e.g., "DOE Science Bowl 2023")
    public let source: String?

    /// Attribution text for CC-licensed content
    public let attribution: String?

    /// Year the question was written
    public let yearWritten: Int?

    /// Number of times this question has been used
    public let usageCount: Int

    /// Whether the question requires calculation
    public let requiresCalculation: Bool

    /// Whether the question contains formulas or equations
    public let hasFormula: Bool

    /// Tags for additional categorization
    public let tags: [String]?

    public init(
        source: String? = nil,
        attribution: String? = nil,
        yearWritten: Int? = nil,
        usageCount: Int = 0,
        requiresCalculation: Bool = false,
        hasFormula: Bool = false,
        tags: [String]? = nil
    ) {
        self.source = source
        self.attribution = attribution
        self.yearWritten = yearWritten
        self.usageCount = usageCount
        self.requiresCalculation = requiresCalculation
        self.hasFormula = hasFormula
        self.tags = tags
    }
}

// MARK: - Domain Tag

/// Domain classification with primary category and optional subcategory
public struct DomainTag: Codable, Hashable, Sendable {
    /// Primary domain (e.g., science, history)
    public let primary: PrimaryDomain

    /// Optional subdomain (e.g., physics, American history)
    public let subdomain: String?

    public init(primary: PrimaryDomain, subdomain: String? = nil) {
        self.primary = primary
        self.subdomain = subdomain
    }
}

// MARK: - Primary Domain

/// Standard domain categories across all competition formats
public enum PrimaryDomain: String, Codable, CaseIterable, Sendable {
    case science
    case mathematics
    case literature
    case history
    case socialStudies
    case arts
    case currentEvents
    case language
    case technology
    case popCulture
    case religionPhilosophy
    case miscellaneous
}

// MARK: - Difficulty Rating

/// Difficulty assessment with absolute and competition-relative values
public struct DifficultyRating: Codable, Hashable, Sendable {
    /// Absolute difficulty on a 1-6 scale
    public let absoluteLevel: Int

    /// Competition-relative difficulty ratings
    public let competitionRelative: [CompetitionFormat: RelativeDifficulty]?

    public init(
        absoluteLevel: Int,
        competitionRelative: [CompetitionFormat: RelativeDifficulty]? = nil
    ) {
        self.absoluteLevel = absoluteLevel
        self.competitionRelative = competitionRelative
    }
}

/// Difficulty relative to a specific competition format
public struct RelativeDifficulty: Codable, Hashable, Sendable {
    /// Tier within the competition (e.g., novice, varsity)
    public let tier: DifficultyTier

    /// Percentile ranking within the competition (0-100)
    public let percentile: Int?

    public init(tier: DifficultyTier, percentile: Int? = nil) {
        self.tier = tier
        self.percentile = percentile
    }
}

/// Standard difficulty tiers across competitions
public enum DifficultyTier: String, Codable, CaseIterable, Comparable, Sendable {
    case novice
    case competent
    case varsity
    case championship

    public static func < (lhs: DifficultyTier, rhs: DifficultyTier) -> Bool {
        let order: [DifficultyTier] = [.novice, .competent, .varsity, .championship]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else { return false }
        return lhsIndex < rhsIndex
    }
}

// MARK: - Competition Format

/// Supported competition formats for question sharing
public enum CompetitionFormat: String, Codable, CaseIterable, Sendable {
    case knowledgeBowl
    case quizBowl
    case scienceBowl
    case scienceOlympiad
    case general
}

// MARK: - Transformation Hints

/// Hints for transforming questions to specific formats
public struct TransformationHints: Codable, Hashable, Sendable {
    /// Whether this question can be converted to multiple choice
    public let mcqPossible: Bool

    /// Suggested distractors for MCQ generation
    public let suggestedDistractors: [String]?

    /// Whether the question requires visual elements
    public let requiresVisual: Bool

    /// Estimated read time in seconds
    public let estimatedReadTime: TimeInterval?

    public init(
        mcqPossible: Bool = true,
        suggestedDistractors: [String]? = nil,
        requiresVisual: Bool = false,
        estimatedReadTime: TimeInterval? = nil
    ) {
        self.mcqPossible = mcqPossible
        self.suggestedDistractors = suggestedDistractors
        self.requiresVisual = requiresVisual
        self.estimatedReadTime = estimatedReadTime
    }
}
