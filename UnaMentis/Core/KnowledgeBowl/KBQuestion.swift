//
//  KBQuestion.swift
//  UnaMentis
//
//  Core question model for Knowledge Bowl module
//

import Foundation

// MARK: - Question Model

/// A Knowledge Bowl question with answer, metadata, and suitability flags
struct KBQuestion: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let text: String
    let answer: KBAnswer
    let domain: KBDomain
    let subdomain: String?
    let difficulty: KBDifficulty
    let gradeLevel: KBGradeLevel
    let suitability: KBSuitability
    let estimatedReadTime: TimeInterval

    /// Reference to pre-recorded audio file (optional)
    let audioAssetId: String?

    /// MCQ options for written round (A, B, C, D)
    let mcqOptions: [String]?

    /// Source attribution for CC-licensed content
    let source: String?
    let sourceAttribution: String?

    /// Tags for filtering and categorization
    let tags: [String]?

    init(
        id: UUID = UUID(),
        text: String,
        answer: KBAnswer,
        domain: KBDomain,
        subdomain: String? = nil,
        difficulty: KBDifficulty = .varsity,
        gradeLevel: KBGradeLevel = .highSchool,
        suitability: KBSuitability = KBSuitability(),
        estimatedReadTime: TimeInterval? = nil,
        audioAssetId: String? = nil,
        mcqOptions: [String]? = nil,
        source: String? = nil,
        sourceAttribution: String? = nil,
        tags: [String]? = nil
    ) {
        self.id = id
        self.text = text
        self.answer = answer
        self.domain = domain
        self.subdomain = subdomain
        self.difficulty = difficulty
        self.gradeLevel = gradeLevel
        self.suitability = suitability
        // Estimate read time based on word count if not provided
        self.estimatedReadTime = estimatedReadTime ?? Self.estimateReadTime(for: text)
        self.audioAssetId = audioAssetId
        self.mcqOptions = mcqOptions
        self.source = source
        self.sourceAttribution = sourceAttribution
        self.tags = tags
    }

    /// Estimate read time based on average reading speed
    private static func estimateReadTime(for text: String) -> TimeInterval {
        let wordCount = text.split(separator: " ").count
        // Average speech rate: ~150 words per minute = 2.5 words per second
        return Double(wordCount) / 2.5
    }

    // MARK: - Custom Codable

    enum CodingKeys: String, CodingKey {
        case id, text, answer, domain, subdomain, difficulty, gradeLevel, suitability
        case estimatedReadTime, audioAssetId, mcqOptions, source, sourceAttribution, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        answer = try container.decode(KBAnswer.self, forKey: .answer)
        domain = try container.decode(KBDomain.self, forKey: .domain)
        subdomain = try container.decodeIfPresent(String.self, forKey: .subdomain)
        difficulty = try container.decode(KBDifficulty.self, forKey: .difficulty)
        gradeLevel = try container.decode(KBGradeLevel.self, forKey: .gradeLevel)
        suitability = try container.decode(KBSuitability.self, forKey: .suitability)

        // Compute estimatedReadTime if not present in JSON
        if let readTime = try container.decodeIfPresent(TimeInterval.self, forKey: .estimatedReadTime) {
            estimatedReadTime = readTime
        } else {
            estimatedReadTime = Self.estimateReadTime(for: text)
        }

        audioAssetId = try container.decodeIfPresent(String.self, forKey: .audioAssetId)
        mcqOptions = try container.decodeIfPresent([String].self, forKey: .mcqOptions)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        sourceAttribution = try container.decodeIfPresent(String.self, forKey: .sourceAttribution)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
    }
}

// MARK: - Answer Model

/// Answer with primary response and acceptable alternatives
struct KBAnswer: Codable, Hashable, Sendable {
    /// The canonical correct answer
    let primary: String

    /// Alternative acceptable answers (e.g., "USA" for "United States")
    let acceptable: [String]?

    /// Type of answer for smart matching
    let answerType: KBAnswerType

    init(
        primary: String,
        acceptable: [String]? = nil,
        answerType: KBAnswerType = .text
    ) {
        self.primary = primary
        self.acceptable = acceptable
        self.answerType = answerType
    }

    /// All valid answers including primary and alternatives
    var allValidAnswers: [String] {
        var answers = [primary]
        if let acceptable = acceptable {
            answers.append(contentsOf: acceptable)
        }
        return answers
    }
}

// MARK: - Answer Type

/// Type of answer for specialized matching logic
enum KBAnswerType: String, Codable, CaseIterable, Sendable {
    case text           // Generic text answer
    case person         // Person's name (handle first/last order, titles)
    case place          // Geographic location (handle "the", abbreviations)
    case number         // Numeric answer (parse written numbers)
    case date           // Date answer (handle multiple formats)
    case title          // Book/movie/work title (handle "The")
    case scientific     // Scientific term (handle formulas, abbreviations)
    case multipleChoice // MCQ letter (A, B, C, D)
}

// MARK: - Difficulty Level

/// Difficulty levels aligned with competition standards
enum KBDifficulty: String, Codable, CaseIterable, Comparable, Sendable {
    case overview       // Basic familiarity
    case foundational   // Core concepts
    case intermediate   // Deeper understanding
    case varsity        // Competition-ready
    case championship   // Top-tier difficulty
    case research       // Expert-level

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .foundational: return "Foundational"
        case .intermediate: return "Intermediate"
        case .varsity: return "Varsity"
        case .championship: return "Championship"
        case .research: return "Research"
        }
    }

    /// Numeric value for comparison
    var level: Int {
        switch self {
        case .overview: return 1
        case .foundational: return 2
        case .intermediate: return 3
        case .varsity: return 4
        case .championship: return 5
        case .research: return 6
        }
    }

    static func < (lhs: KBDifficulty, rhs: KBDifficulty) -> Bool {
        lhs.level < rhs.level
    }
}

// MARK: - Grade Level

/// Target grade levels for questions
enum KBGradeLevel: String, Codable, CaseIterable, Sendable {
    case middleSchool   // Grades 6-8
    case highSchool     // Grades 9-12
    case advanced       // College-prep / early college

    var displayName: String {
        switch self {
        case .middleSchool: return "Middle School (6-8)"
        case .highSchool: return "High School (9-12)"
        case .advanced: return "Advanced"
        }
    }

    var gradeRange: ClosedRange<Int> {
        switch self {
        case .middleSchool: return 6...8
        case .highSchool: return 9...12
        case .advanced: return 11...14
        }
    }
}

// MARK: - Suitability Flags

/// Flags indicating which round types a question is suitable for
struct KBSuitability: Codable, Hashable, Sendable {
    /// Can be used in written (MCQ) round
    let forWritten: Bool

    /// Can be used in oral (spoken) round
    let forOral: Bool

    /// Can be converted to multiple choice format
    let mcqPossible: Bool

    /// Requires visual elements (diagrams, equations, maps)
    let requiresVisual: Bool

    init(
        forWritten: Bool = true,
        forOral: Bool = true,
        mcqPossible: Bool = true,
        requiresVisual: Bool = false
    ) {
        self.forWritten = forWritten
        self.forOral = forOral
        self.mcqPossible = mcqPossible
        self.requiresVisual = requiresVisual
    }
}

// MARK: - Question Attempt

/// Record of a user's attempt at answering a question
struct KBQuestionAttempt: Codable, Identifiable, Sendable {
    let id: UUID
    let questionId: UUID
    let domain: KBDomain  // Domain for performance tracking
    let timestamp: Date
    let userAnswer: String?
    let selectedChoice: Int?  // 0-3 for A-D in MCQ
    let responseTime: TimeInterval
    let usedConference: Bool
    let conferenceTime: TimeInterval?
    let wasCorrect: Bool
    let pointsEarned: Int
    let roundType: KBRoundType
    let wasRebound: Bool  // Answered after opponent missed
    let matchType: KBMatchType?  // How the answer was validated

    init(
        id: UUID = UUID(),
        questionId: UUID,
        domain: KBDomain,
        timestamp: Date = Date(),
        userAnswer: String? = nil,
        selectedChoice: Int? = nil,
        responseTime: TimeInterval,
        usedConference: Bool = false,
        conferenceTime: TimeInterval? = nil,
        wasCorrect: Bool,
        pointsEarned: Int,
        roundType: KBRoundType,
        wasRebound: Bool = false,
        matchType: KBMatchType? = nil
    ) {
        self.id = id
        self.questionId = questionId
        self.domain = domain
        self.timestamp = timestamp
        self.userAnswer = userAnswer
        self.selectedChoice = selectedChoice
        self.responseTime = responseTime
        self.usedConference = usedConference
        self.conferenceTime = conferenceTime
        self.wasCorrect = wasCorrect
        self.pointsEarned = pointsEarned
        self.roundType = roundType
        self.wasRebound = wasRebound
        self.matchType = matchType
    }
}

// MARK: - Round Type

/// Types of Knowledge Bowl rounds
enum KBRoundType: String, Codable, CaseIterable, Sendable {
    case written    // MCQ, team works together, timed
    case oral       // Spoken questions, buzzer-based

    var displayName: String {
        switch self {
        case .written: return "Written Round"
        case .oral: return "Oral Round"
        }
    }

    var icon: String {
        switch self {
        case .written: return "pencil.and.list.clipboard"
        case .oral: return "mic.fill"
        }
    }
}

// MARK: - Match Type

/// How an answer was validated
enum KBMatchType: String, Codable, Sendable {
    case exact          // Exact match to primary answer
    case acceptable     // Matched an acceptable alternative
    case fuzzy          // Matched via fuzzy matching (typos)
    case ai             // Matched via AI/ML evaluation
    case manual         // Manually marked correct
    case none           // No match (incorrect)
}

// MARK: - Question Bundle

/// Container for bundled questions (loaded from JSON)
struct KBQuestionBundle: Codable, Sendable {
    let version: String
    let generatedAt: Date?
    let questions: [KBQuestion]

    init(version: String = "1.0.0", generatedAt: Date? = Date(), questions: [KBQuestion]) {
        self.version = version
        self.generatedAt = generatedAt
        self.questions = questions
    }
}
