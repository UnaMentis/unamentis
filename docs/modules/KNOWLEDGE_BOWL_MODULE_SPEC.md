# Knowledge Bowl Module Technical Specification

**Module ID:** `com.unamentis.knowledgebowl`
**Version:** 1.1
**Last Updated:** 2026-01-24
**Status:** Phase 2 Complete - Phase 3 watchOS Complete

---

## Table of Contents

1. [Module Overview](#1-module-overview)
2. [Competition Rules & Formats](#2-competition-rules--formats)
3. [Data Models](#3-data-models)
4. [Core Services](#4-core-services)
5. [Training Modes](#5-training-modes)
6. [Analytics & Metrics](#6-analytics--metrics)
7. [User Interface](#7-user-interface)
8. [watchOS Integration](#8-watchos-integration)
9. [Implementation Priorities](#9-implementation-priorities)
10. [Testing Requirements](#10-testing-requirements)

---

## 1. Module Overview

### 1.1 Module Manifest

```swift
let knowledgeBowlManifest = ModuleManifest(
    moduleId: "com.unamentis.knowledgebowl",
    displayName: "Knowledge Bowl",
    version: "1.0.0",
    competition: .knowledgeBowl,
    minimumCoreVersion: "1.0.0",
    optionalModules: [
        "com.unamentis.quizbowl",
        "com.unamentis.sciencebowl"
    ],
    capabilities: ModuleCapabilities(
        providesQuestions: true,
        consumesSharedQuestions: true,
        providesAnalytics: true,
        consumesUnifiedProfile: true,
        supportsVoiceInterface: true,
        supportsWatchOS: true
    ),
    bundledQuestionCount: 5000,
    supportedDomains: StandardDomain.allCases,
    supportedRegions: [.colorado, .minnesota, .washington]
)
```

### 1.2 Competition Profile

| Attribute | Value |
|-----------|-------|
| **Geographic Scope** | Colorado, Minnesota, Washington (+ limited elsewhere) |
| **Annual Participants** | ~15,000 students |
| **Grade Levels** | 7th-12th (Junior High + High School divisions) |
| **Voice Percentage** | ~60-70% (oral rounds are voice; written rounds are not) |
| **Match Format** | 3 teams per match |
| **Team Size** | 1-4 active players (varies by state) |
| **Key Organizations** | Colorado KB Foundation, MN Service Cooperatives, WA ESDs |

### 1.3 Related Documents

| Document | Purpose |
|----------|---------|
| [KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md](KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md) | Complete domain knowledge, training philosophy, pedagogy |
| [MASTER_TECHNICAL_IMPLEMENTATION.md](MASTER_TECHNICAL_IMPLEMENTATION.md) | Platform architecture, shared services |
| [UNIFIED_PROFICIENCY_SYSTEM.md](UNIFIED_PROFICIENCY_SYSTEM.md) | Cross-module proficiency tracking |
| [ACADEMIC_COMPETITION_MODULAR_ARCHITECTURE.md](ACADEMIC_COMPETITION_MODULAR_ARCHITECTURE.md) | Module integration patterns |

---

## 2. Competition Rules & Formats

### 2.1 Regional Configuration

Knowledge Bowl has significant rule variations between states. The module must support all variants.

```swift
// MARK: - Regional Configuration

struct KBRegionalConfig: Codable, Identifiable {
    let id: String
    let region: KBRegion
    let displayName: String

    // Match Format
    let teamsPerMatch: Int
    let teamSize: TeamSizeConfig
    let matchStructure: MatchStructure

    // Oral Round Rules
    let oralRoundConfig: OralRoundConfig

    // Written Round Rules
    let writtenRoundConfig: WrittenRoundConfig

    // Scoring
    let scoringConfig: ScoringConfig
}

enum KBRegion: String, Codable, CaseIterable {
    case colorado
    case coloradoSprings  // Special sub-region with stricter conferring rules
    case minnesota
    case washington
}

struct TeamSizeConfig: Codable {
    let minPlayers: Int
    let maxPlayers: Int
    let activeInWritten: Int      // Usually all
    let activeInOral: Int         // Usually 4

    static let colorado = TeamSizeConfig(
        minPlayers: 1,
        maxPlayers: 4,
        activeInWritten: 4,
        activeInOral: 4
    )

    static let minnesota = TeamSizeConfig(
        minPlayers: 3,
        maxPlayers: 6,
        activeInWritten: 6,
        activeInOral: 4
    )

    static let washington = TeamSizeConfig(
        minPlayers: 3,
        maxPlayers: 5,
        activeInWritten: 5,
        activeInOral: 4
    )
}
```

### 2.2 Conferring Rules

**Critical**: Conferring rules vary significantly between regions.

```swift
struct ConferringConfig: Codable {
    /// Time allowed for team discussion (0 = no time limit)
    let conferenceTimeSeconds: Int

    /// Whether verbal discussion about the answer is allowed
    let verbalConferringAllowed: Bool

    /// Whether hand signals are allowed
    let handSignalsAllowed: Bool

    /// Whether conferring is required (some formats)
    let conferringRequired: Bool

    // MARK: - Regional Presets

    static let colorado = ConferringConfig(
        conferenceTimeSeconds: 15,
        verbalConferringAllowed: false,  // NO discussion about the answer
        handSignalsAllowed: true,
        conferringRequired: false
    )

    static let coloradoSprings = ConferringConfig(
        conferenceTimeSeconds: 15,
        verbalConferringAllowed: false,  // Strictly no verbal
        handSignalsAllowed: true,        // Hand signals REQUIRED
        conferringRequired: false
    )

    static let minnesota = ConferringConfig(
        conferenceTimeSeconds: 15,
        verbalConferringAllowed: true,   // Can discuss
        handSignalsAllowed: true,
        conferringRequired: false
    )

    static let washington = ConferringConfig(
        conferenceTimeSeconds: 15,
        verbalConferringAllowed: true,
        handSignalsAllowed: true,
        conferringRequired: false
    )
}
```

### 2.3 Match Structure

```swift
struct MatchStructure: Codable {
    let teamsPerMatch: Int
    let rounds: [RoundDefinition]
}

struct RoundDefinition: Codable {
    let type: RoundType
    let questionCount: Int
    let timeLimit: TimeInterval?
    let pointsPerQuestion: Int
}

enum RoundType: String, Codable {
    case written       // MCQ, team works together
    case oral          // Buzzer-based, verbal answers
    case tieredOral    // MN: Different difficulty tiers
    case bonus         // Some formats have bonus rounds
}

// MARK: - Regional Match Structures

extension MatchStructure {
    static let coloradoStandard = MatchStructure(
        teamsPerMatch: 3,
        rounds: [
            RoundDefinition(type: .written, questionCount: 60, timeLimit: 900, pointsPerQuestion: 1),
            RoundDefinition(type: .oral, questionCount: 50, timeLimit: nil, pointsPerQuestion: 5)
        ]
    )

    static let minnesotaStandard = MatchStructure(
        teamsPerMatch: 3,
        rounds: [
            RoundDefinition(type: .written, questionCount: 60, timeLimit: 900, pointsPerQuestion: 2),
            RoundDefinition(type: .oral, questionCount: 50, timeLimit: nil, pointsPerQuestion: 5)
        ]
    )

    static let washingtonStandard = MatchStructure(
        teamsPerMatch: 3,
        rounds: [
            RoundDefinition(type: .written, questionCount: 50, timeLimit: 2700, pointsPerQuestion: 2),  // 45 minutes
            RoundDefinition(type: .oral, questionCount: 50, timeLimit: nil, pointsPerQuestion: 5)
        ]
    )
}
```

### 2.4 Scoring System

```swift
struct ScoringConfig: Codable {
    /// Points for correct written answer
    let writtenCorrect: Int

    /// Points for correct oral answer (first team)
    let oralCorrect: Int

    /// Points for correct oral answer (rebound)
    let oralRebound: Int

    /// Penalty for incorrect oral answer (NO penalties in KB)
    let oralIncorrect: Int = 0  // Always 0 - KB has no negs

    /// Minnesota SOS Bonus system
    let sosBonus: SOSBonusConfig?
}

struct SOSBonusConfig: Codable {
    /// Bonus multiplier based on opponent strength
    let enabled: Bool
    let maxMultiplier: Double
}

// MARK: - Regional Scoring

extension ScoringConfig {
    static let colorado = ScoringConfig(
        writtenCorrect: 1,
        oralCorrect: 5,
        oralRebound: 5,
        sosBonus: nil
    )

    static let minnesota = ScoringConfig(
        writtenCorrect: 2,
        oralCorrect: 5,
        oralRebound: 5,
        sosBonus: SOSBonusConfig(enabled: true, maxMultiplier: 1.5)
    )

    static let washington = ScoringConfig(
        writtenCorrect: 2,
        oralCorrect: 5,
        oralRebound: 5,
        sosBonus: nil
    )
}
```

---

## 3. Data Models

### 3.1 Question Models

```swift
// MARK: - Knowledge Bowl Question

struct KBQuestion: CompetitionQuestion, Codable, Identifiable {
    let id: UUID
    let sourceQuestionId: UUID?  // Link to canonical question

    // Content
    let text: String
    let answer: AnswerSpec

    // Classification
    let domains: [DomainTag]
    let difficulty: DifficultyTier

    // KB-Specific
    let suitability: KBQuestionSuitability
    let estimatedReadTime: TimeInterval

    // Metadata
    let source: String?
    let yearWritten: Int?
    let usageCount: Int
}

struct KBQuestionSuitability: Codable {
    /// Suitable for written round (MCQ possible)
    let forWritten: Bool

    /// Suitable for oral round
    let forOral: Bool

    /// Can be made into multiple choice
    let mcqPossible: Bool

    /// Requires visual aid (equations, diagrams)
    let requiresVisual: Bool
}

// MARK: - Multiple Choice for Written Round

struct KBWrittenQuestion: Codable, Identifiable {
    let id: UUID
    let sourceQuestion: KBQuestion

    let choices: [MCQChoice]
    let correctChoiceIndex: Int

    struct MCQChoice: Codable {
        let label: String       // "A", "B", "C", "D"
        let text: String
        let isCorrect: Bool
    }
}
```

### 3.2 Session Models

```swift
// MARK: - Practice Session

struct KBPracticeSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let startTime: Date
    var endTime: Date?

    let sessionType: KBSessionType
    let regionalConfig: KBRegion
    let difficulty: DifficultyTier

    // Results
    var attempts: [KBQuestionAttempt]
    var summary: KBSessionSummary?
}

enum KBSessionType: String, Codable {
    case writtenPractice
    case oralPractice
    case fullMatchSimulation
    case domainDrill
    case speedDrill
    case conferencePractice      // Team conferring training
    case reboundPractice         // Rebound opportunity training
    case mixedReview
}

struct KBQuestionAttempt: Codable, Identifiable {
    let id: UUID
    let questionId: UUID
    let timestamp: Date

    // Response
    let userAnswer: String?
    let selectedChoice: Int?     // For MCQ
    let responseTime: TimeInterval
    let usedConference: Bool     // Did they use conference time?
    let conferenceTime: TimeInterval?

    // Result
    let wasCorrect: Bool
    let pointsEarned: Int

    // Context
    let roundType: RoundType
    let wasRebound: Bool         // Was this a rebound opportunity?
}

struct KBSessionSummary: Codable {
    // Overall
    let totalQuestions: Int
    let totalCorrect: Int
    let totalPoints: Int

    // By Round Type
    let writtenAccuracy: Double?
    let oralAccuracy: Double?

    // Speed Metrics
    let averageResponseTime: TimeInterval
    let averageConferenceTime: TimeInterval?

    // Domain Breakdown
    let domainPerformance: [StandardDomain: DomainSessionStats]
}

struct DomainSessionStats: Codable {
    let attempted: Int
    let correct: Int
    let averageTime: TimeInterval
}
```

### 3.3 Analytics Models

```swift
// MARK: - KB-Specific Analytics

struct KBAnalyticsProfile: CompetitionSpecificProfile, Codable {
    let competitionFormat = CompetitionFormat.knowledgeBowl
    let userId: UUID
    let lastUpdated: Date

    // Overall Performance
    var overallAccuracy: Double
    var totalQuestionsAttempted: Int
    var totalPracticeTime: TimeInterval

    // Round-Specific
    var writtenRoundStats: RoundStats
    var oralRoundStats: RoundStats

    // Conference Efficiency (for regions that allow conferring)
    var conferenceStats: ConferenceStats

    // Rebound Performance
    var reboundStats: ReboundStats

    // Domain Mastery (links to unified proficiency)
    var domainPerformance: [StandardDomain: KBDomainStats]

    // Difficulty Progression
    var performanceByDifficulty: [DifficultyTier: Double]

    // Trends
    var weeklyProgress: [WeeklySnapshot]
}

struct RoundStats: Codable {
    var questionsAttempted: Int
    var questionsCorrect: Int
    var accuracy: Double { questionsAttempted > 0 ? Double(questionsCorrect) / Double(questionsAttempted) : 0 }
    var averageResponseTime: TimeInterval
}

struct ConferenceStats: Codable {
    /// How often conferring leads to correct answer
    var conferenceSuccessRate: Double

    /// Average time used when conferring
    var averageConferenceTime: TimeInterval

    /// Accuracy when conferring vs not conferring
    var accuracyWithConference: Double
    var accuracyWithoutConference: Double

    /// Efficiency: Did conferring help?
    var conferenceEfficiency: Double {
        accuracyWithConference - accuracyWithoutConference
    }
}

struct ReboundStats: Codable {
    /// Success rate on rebound opportunities
    var reboundSuccessRate: Double

    /// How many rebound opportunities seen
    var reboundOpportunities: Int

    /// How many converted
    var reboundsConverted: Int

    /// Strategic holds: When user intentionally didn't buzz to let opponents miss
    var strategicHoldsAttempted: Int
    var strategicHoldsSuccessful: Int
}

struct KBDomainStats: Codable {
    let domain: StandardDomain
    var questionsAttempted: Int
    var questionsCorrect: Int
    var writtenAccuracy: Double
    var oralAccuracy: Double
    var averageResponseTime: TimeInterval
    var trend: PerformanceTrend
}
```

---

## 4. Core Services

**Architecture Philosophy: On-Device First**

All Knowledge Bowl core services operate on-device to enable:
- ✅ **Full offline practice capability** - Individual practice works without internet
- ✅ **Low latency** - No network round-trips for question loading or answer validation
- ✅ **Privacy** - No answer data sent to server during individual practice
- ✅ **Scalability** - Server not in critical path for practice sessions

**Server Role** (secondary, supporting):
- **Question Delivery**: Download question packs (bundled JSON + audio)
- **Team Coordination**: WebSocket session orchestration for distributed team practice
- **Statistics Aggregation**: Aggregate individual/team performance for leaderboards
- **Configuration Management**: Deliver regional configs, feature flags, model availability

### 4.1 KB Question Service

```swift
// MARK: - KB Question Service
// On-Device: Questions stored locally in SQLite + bundled JSON

class KBQuestionService {
    private let questionEngine: QuestionEngine
    private let transformer: KBTransformer

    // ═══════════════════════════════════════════════════════════════════════
    // QUESTION RETRIEVAL
    // ═══════════════════════════════════════════════════════════════════════

    /// Get questions for a practice session
    func getQuestions(
        count: Int,
        for sessionType: KBSessionType,
        difficulty: DifficultyTier?,
        domains: [StandardDomain]?,
        region: KBRegion
    ) -> [KBQuestion] {

        var filters = QuestionFilters()
        filters.domains = domains?.map { PrimaryDomain(from: $0) }
        filters.difficulty = difficulty.map { $0...$0 }

        // Get from shared question engine
        let canonicals = questionEngine.query(filters: filters, limit: count * 2)

        // Transform to KB format
        return canonicals
            .compactMap { transformer.transform($0) }
            .filter { question in
                switch sessionType {
                case .writtenPractice:
                    return question.suitability.forWritten
                case .oralPractice, .fullMatchSimulation:
                    return question.suitability.forOral
                default:
                    return true
                }
            }
            .prefix(count)
            .map { $0 }
    }

    /// Get questions for written round (with MCQ conversion)
    func getWrittenQuestions(
        count: Int,
        difficulty: DifficultyTier?,
        domains: [StandardDomain]?
    ) -> [KBWrittenQuestion] {

        let baseQuestions = getQuestions(
            count: count,
            for: .writtenPractice,
            difficulty: difficulty,
            domains: domains,
            region: .colorado  // Written format is similar across regions
        )

        return baseQuestions.compactMap { convertToMCQ($0) }
    }

    private func convertToMCQ(_ question: KBQuestion) -> KBWrittenQuestion? {
        guard question.suitability.mcqPossible else { return nil }

        // Generate distractors
        let distractors = generateDistractors(for: question, count: 3)

        var choices = distractors.map { MCQChoice(label: "", text: $0, isCorrect: false) }
        choices.append(MCQChoice(label: "", text: question.answer.primary, isCorrect: true))
        choices.shuffle()

        // Assign labels
        let labels = ["A", "B", "C", "D"]
        for i in 0..<choices.count {
            choices[i] = MCQChoice(
                label: labels[i],
                text: choices[i].text,
                isCorrect: choices[i].isCorrect
            )
        }

        let correctIndex = choices.firstIndex { $0.isCorrect } ?? 0

        return KBWrittenQuestion(
            id: UUID(),
            sourceQuestion: question,
            choices: choices,
            correctChoiceIndex: correctIndex
        )
    }
}
```

### 4.2 KB Session Manager

```swift
// MARK: - KB Session Manager

class KBSessionManager {
    private let questionService: KBQuestionService
    private let voicePipeline: UniversalVoicePipeline
    private let analyticsService: KBAnalyticsService
    private let proficiencyStore: ProficiencyStore

    private var currentSession: KBPracticeSession?

    // ═══════════════════════════════════════════════════════════════════════
    // SESSION LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════

    /// Start a new practice session
    func startSession(
        type: KBSessionType,
        config: KBSessionConfig
    ) async throws -> KBPracticeSession {

        // Configure voice pipeline for KB
        voicePipeline.configure(for: .knowledgeBowl)

        // Get questions
        let questions = questionService.getQuestions(
            count: config.questionCount,
            for: type,
            difficulty: config.difficulty,
            domains: config.domains,
            region: config.region
        )

        let session = KBPracticeSession(
            id: UUID(),
            userId: config.userId,
            startTime: Date(),
            sessionType: type,
            regionalConfig: config.region,
            difficulty: config.difficulty ?? .competent,
            attempts: []
        )

        currentSession = session
        return session
    }

    /// Process a question in the session
    func processQuestion(
        _ question: KBQuestion,
        in session: inout KBPracticeSession,
        config: KBRegionalConfig
    ) async -> KBQuestionAttempt {

        // Speak the question (for oral rounds)
        if session.sessionType != .writtenPractice {
            await voicePipeline.speak(question.text)
        }

        // Start listening/timing
        let startTime = Date()

        // Handle conference period if applicable
        var conferenceTime: TimeInterval? = nil
        if config.oralRoundConfig.conferring.conferenceTimeSeconds > 0 {
            conferenceTime = await handleConferencePeriod(config: config.oralRoundConfig.conferring)
        }

        // Get answer
        let result = await voicePipeline.listenForAnswer(timeout: 5.0)
        let responseTime = Date().timeIntervalSince(startTime)

        // Validate answer
        let isCorrect = validateAnswer(result.transcript, against: question.answer)

        let attempt = KBQuestionAttempt(
            id: UUID(),
            questionId: question.id,
            timestamp: Date(),
            userAnswer: result.transcript,
            selectedChoice: nil,
            responseTime: responseTime,
            usedConference: conferenceTime != nil,
            conferenceTime: conferenceTime,
            wasCorrect: isCorrect,
            pointsEarned: isCorrect ? config.scoringConfig.oralCorrect : 0,
            roundType: .oral,
            wasRebound: false
        )

        // Record to proficiency store
        recordAttemptToProficiency(attempt, question: question)

        return attempt
    }

    private func handleConferencePeriod(config: ConferringConfig) async -> TimeInterval {
        let startTime = Date()

        // Announce conference (if verbal allowed)
        if config.verbalConferringAllowed {
            await voicePipeline.speak("Conference")
        }

        // Wait for conference time or early answer signal
        // ... implementation

        return Date().timeIntervalSince(startTime)
    }

    /// End the current session
    func endSession() async -> KBSessionSummary {
        guard var session = currentSession else {
            fatalError("No active session")
        }

        session.endTime = Date()

        // Generate summary
        let summary = generateSummary(for: session)
        session.summary = summary

        // Update analytics
        await analyticsService.recordSession(session)

        // Clear current session
        currentSession = nil

        return summary
    }
}

struct KBSessionConfig {
    let userId: UUID
    let questionCount: Int
    let difficulty: DifficultyTier?
    let domains: [StandardDomain]?
    let region: KBRegion
}
```

### 4.3 KB Transformer

```swift
// MARK: - KB Question Transformer

struct KBTransformer: QuestionTransformer {
    typealias Output = KBQuestion

    func transform(_ canonical: CanonicalQuestion) -> KBQuestion? {
        guard isCompatible(canonical) else { return nil }

        // Use medium or short form (KB questions are short)
        let text = canonical.content.mediumForm.isEmpty
            ? canonical.content.shortForm
            : canonical.content.mediumForm

        // Determine suitability
        let suitability = KBQuestionSuitability(
            forWritten: true,  // Most KB questions work for written
            forOral: !canonical.metadata.requiresCalculation,
            mcqPossible: canGenerateMCQ(canonical),
            requiresVisual: canonical.metadata.hasFormula
        )

        // Estimate read time (~150 words per minute for competition reading)
        let wordCount = text.split(separator: " ").count
        let readTime = Double(wordCount) / 150.0 * 60.0  // seconds

        return KBQuestion(
            id: UUID(),
            sourceQuestionId: canonical.id,
            text: text,
            answer: canonical.answer,
            domains: canonical.domains,
            difficulty: canonical.difficulty.competitionRelative[.knowledgeBowl]?.tier ?? .competent,
            suitability: suitability,
            estimatedReadTime: readTime,
            source: canonical.metadata.source,
            yearWritten: canonical.metadata.yearWritten,
            usageCount: canonical.metadata.usageCount
        )
    }

    func isCompatible(_ canonical: CanonicalQuestion) -> Bool {
        // KB can use almost any question
        return !canonical.content.shortForm.isEmpty ||
               !canonical.content.mediumForm.isEmpty
    }

    func qualityScore(_ canonical: CanonicalQuestion) -> Double {
        var score = 0.5

        // Prefer questions with medium form (ideal length for KB)
        if !canonical.content.mediumForm.isEmpty { score += 0.2 }

        // Prefer questions that can be MCQ
        if canGenerateMCQ(canonical) { score += 0.1 }

        // Prefer questions without complex formulas (voice-friendly)
        if !canonical.metadata.hasFormula { score += 0.1 }

        // Domain weighting (some domains more common in KB)
        let kbCommonDomains: Set<PrimaryDomain> = [
            .literature, .history, .geography, .science, .currentEvents
        ]
        if canonical.domains.contains(where: { kbCommonDomains.contains($0.primary) }) {
            score += 0.1
        }

        return min(1.0, score)
    }

    func canonicalize(_ question: KBQuestion) -> CanonicalQuestion {
        // Reverse transformation
        return CanonicalQuestion(
            id: question.sourceQuestionId ?? UUID(),
            version: 1,
            createdAt: Date(),
            updatedAt: Date(),
            content: QuestionContent(
                pyramidalFull: "",  // KB doesn't have pyramidal
                mediumForm: question.text,
                shortForm: question.text,
                clues: nil,
                powerMarkIndex: nil
            ),
            answer: question.answer,
            metadata: QuestionMetadata(/* ... */),
            domains: question.domains,
            difficulty: DifficultyRating(/* ... */),
            compatibleFormats: [.knowledgeBowl],
            transformationHints: TransformationHints()
        )
    }

    private func canGenerateMCQ(_ canonical: CanonicalQuestion) -> Bool {
        // Can generate MCQ if answer is a discrete entity (person, place, thing)
        let mcqFriendlyTypes: Set<AnswerType> = [
            .person, .place, .thing, .title, .scientific
        ]
        return mcqFriendlyTypes.contains(canonical.answer.answerType)
    }
}
```

### 4.4 KB Answer Validation Service

The Knowledge Bowl module implements a **3-tier answer validation system** that operates entirely on-device, providing different accuracy levels based on device capabilities and regional compliance requirements.

#### 4.4.1 Architecture Philosophy

**On-Device First**: All answer validation happens on the client device to enable:
- ✅ Full offline practice capability
- ✅ Low latency validation (<50ms for Tier 1, <80ms for Tier 2, <250ms for Tier 3)
- ✅ Privacy (no answer data sent to server during individual practice)
- ✅ Scalability (server not in critical path for validation)

**Regional Compliance**: Validation strictness adapts to regional competition rules:
- **Colorado (`.strict`)**: Tier 1 baseline only (Levenshtein distance matching)
- **Minnesota/Washington (`.standard`)**: Tier 1 enhanced algorithms
- **Practice Mode (`.lenient`)**: All tiers available (including embeddings and LLM)

#### 4.4.2 Three-Tier Validation System

```swift
// MARK: - KB Answer Validator

class KBAnswerValidator {
    private let tier1Matcher: KBAlgorithmicMatcher
    private let tier2Service: KBEmbeddingsService?      // Optional: iPhone XS+
    private let tier3Service: KBLLMValidator?           // Optional: iPhone 12+

    /// Validate answer with automatic tier selection
    func validate(
        userAnswer: String,
        question: KBQuestion,
        strictness: KBStrictnessLevel
    ) async -> KBValidationResult {

        // Tier 1: Enhanced Algorithms (always available)
        let tier1Result = await tier1Matcher.validate(
            userAnswer: userAnswer,
            correctAnswer: question.answer,
            strictness: strictness
        )

        // For strict mode (Colorado), only use Tier 1 baseline
        if strictness == .strict {
            return tier1Result.usingBaseline()
        }

        // If Tier 1 is confident, return early
        if tier1Result.confidence >= 0.9 {
            return tier1Result
        }

        // Tier 2: Semantic Embeddings (optional, 92-95% accuracy)
        if let tier2 = tier2Service, strictness == .lenient {
            let tier2Result = await tier2.validateSemantic(
                userAnswer: userAnswer,
                correctAnswer: question.answer.primary
            )

            if tier2Result.confidence >= 0.85 {
                return KBValidationResult(
                    isCorrect: tier2Result.isCorrect,
                    confidence: tier2Result.confidence,
                    tier: .semantic,
                    matchType: .semantic
                )
            }
        }

        // Tier 3: LLM Validation (optional, 95-98% accuracy, admin-controlled)
        if let tier3 = tier3Service, strictness == .lenient {
            let tier3Result = await tier3.validateWithLLM(
                userAnswer: userAnswer,
                question: question
            )

            return KBValidationResult(
                isCorrect: tier3Result.isCorrect,
                confidence: tier3Result.confidence,
                tier: .llm,
                matchType: .llm,
                explanation: tier3Result.reasoning
            )
        }

        // Fallback to Tier 1 result
        return tier1Result
    }
}

struct KBValidationResult {
    let isCorrect: Bool
    let confidence: Float           // 0.0-1.0
    let tier: KBValidationTier
    let matchType: KBMatchType
    let explanation: String?        // Optional reasoning (Tier 3 only)
}

enum KBValidationTier {
    case algorithmic    // Tier 1
    case semantic       // Tier 2
    case llm            // Tier 3
}

enum KBStrictnessLevel {
    case strict     // Colorado: Levenshtein only
    case standard   // Minnesota/Washington: Enhanced algorithms
    case lenient    // Practice: All tiers
}
```

#### 4.4.3 Tier 1: Enhanced Algorithmic Matching

**Accuracy**: 85-90%
**Storage**: 0 bytes (all algorithms in code)
**Latency**: <50ms (P95)
**Availability**: All devices

Tier 1 uses six complementary matching algorithms:

1. **Levenshtein Distance** (baseline for strict mode)
   - Edit distance with configurable threshold
   - Handles minor typos and spelling variations

2. **Double Metaphone Phonetic Matching**
   - Phonetic encoding for sound-alike answers
   - Catches "Marie Curie" vs "Mary Curie"

3. **N-Gram Similarity**
   - Character-level bigrams/trigrams
   - Word-level n-grams
   - Jaccard coefficient scoring

4. **Token-Based Similarity**
   - Jaccard coefficient (set intersection/union)
   - Dice coefficient (2 × intersection / total tokens)
   - Handles word order variations

5. **Domain-Specific Synonyms**
   - ~650 curated synonym entries
   - Scientific terms, historical names, geographic aliases
   - Example: "USA" ↔ "United States" ↔ "America"

6. **Linguistic Matching (Apple NL Framework)**
   - Lemmatization and tokenization
   - Named entity recognition
   - Language-aware text processing

```swift
// MARK: - Tier 1 Algorithmic Matcher

class KBAlgorithmicMatcher {
    private let phoneticMatcher: KBPhoneticMatcher
    private let ngramMatcher: KBNGramMatcher
    private let tokenMatcher: KBTokenMatcher
    private let linguisticMatcher: KBLinguisticMatcher
    private let synonymStore: KBSynonymStore

    func validate(
        userAnswer: String,
        correctAnswer: KBAnswer,
        strictness: KBStrictnessLevel
    ) async -> KBValidationResult {

        let normalized = normalize(userAnswer)
        let correctNormalized = normalize(correctAnswer.primary)

        // 1. Exact match (highest confidence)
        if normalized == correctNormalized {
            return KBValidationResult(
                isCorrect: true,
                confidence: 1.0,
                tier: .algorithmic,
                matchType: .exact
            )
        }

        // 2. Acceptable alternatives
        if let acceptables = correctAnswer.acceptable {
            for acceptable in acceptables {
                if normalize(acceptable) == normalized {
                    return KBValidationResult(
                        isCorrect: true,
                        confidence: 1.0,
                        tier: .algorithmic,
                        matchType: .acceptable
                    )
                }
            }
        }

        // For strict mode, only use Levenshtein
        if strictness == .strict {
            return validateLevenshtein(normalized, correctNormalized)
        }

        // 3. Phonetic matching (sound-alike)
        if phoneticMatcher.matches(normalized, correctNormalized) {
            return KBValidationResult(
                isCorrect: true,
                confidence: 0.85,
                tier: .algorithmic,
                matchType: .phonetic
            )
        }

        // 4. N-gram similarity
        let ngramScore = ngramMatcher.similarity(normalized, correctNormalized)
        if ngramScore >= 0.8 {
            return KBValidationResult(
                isCorrect: true,
                confidence: Float(ngramScore),
                tier: .algorithmic,
                matchType: .ngram
            )
        }

        // 5. Token-based similarity
        let tokenScore = tokenMatcher.similarity(normalized, correctNormalized)
        if tokenScore >= 0.75 {
            return KBValidationResult(
                isCorrect: true,
                confidence: Float(tokenScore),
                tier: .algorithmic,
                matchType: .token
            )
        }

        // 6. Synonym matching
        if synonymStore.areSynonyms(normalized, correctNormalized) {
            return KBValidationResult(
                isCorrect: true,
                confidence: 0.9,
                tier: .algorithmic,
                matchType: .synonym
            )
        }

        // 7. Linguistic matching
        if linguisticMatcher.matches(normalized, correctNormalized) {
            return KBValidationResult(
                isCorrect: true,
                confidence: 0.8,
                tier: .algorithmic,
                matchType: .linguistic
            )
        }

        // No match found
        return KBValidationResult(
            isCorrect: false,
            confidence: 0.0,
            tier: .algorithmic,
            matchType: .none
        )
    }

    private func validateLevenshtein(
        _ userAnswer: String,
        _ correctAnswer: String
    ) -> KBValidationResult {
        let distance = levenshteinDistance(userAnswer, correctAnswer)
        let threshold = max(2, correctAnswer.count / 5)  // Allow ~20% error

        if distance <= threshold {
            let confidence = 1.0 - (Float(distance) / Float(correctAnswer.count))
            return KBValidationResult(
                isCorrect: true,
                confidence: max(0.5, confidence),
                tier: .algorithmic,
                matchType: .fuzzy
            )
        }

        return KBValidationResult(
            isCorrect: false,
            confidence: 0.0,
            tier: .algorithmic,
            matchType: .none
        )
    }

    private func normalize(_ text: String) -> String {
        // Lowercase, remove articles ("the", "a", "an"), punctuation
        // Handle common abbreviations and variations
        return text.lowercased()
            .replacingOccurrences(of: "^(the|a|an)\\s+", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }
}

enum KBMatchType {
    case exact          // Exact string match
    case acceptable     // Listed in acceptable alternatives
    case fuzzy          // Levenshtein distance match
    case phonetic       // Double Metaphone match
    case ngram          // N-gram similarity
    case token          // Token-based similarity
    case synonym        // Domain synonym match
    case linguistic     // Apple NL framework match
    case semantic       // Tier 2: Embeddings
    case llm            // Tier 3: LLM reasoning
    case none           // No match
}
```

#### 4.4.4 Tier 2: Semantic Embeddings (Optional)

**Accuracy**: 92-95%
**Storage**: 80MB (CoreML model)
**Latency**: <80ms (P95)
**Availability**: iPhone XS+ (Neural Engine required)
**Model**: all-MiniLM-L6-v2 (FP16 quantized)

Tier 2 uses sentence embeddings to capture semantic similarity:

```swift
// MARK: - Tier 2 Semantic Embeddings

class KBEmbeddingsService {
    private let model: MLModel  // all-MiniLM-L6-v2 CoreML

    func validateSemantic(
        userAnswer: String,
        correctAnswer: String
    ) async -> (isCorrect: Bool, confidence: Float) {

        // Generate embeddings (384-dim vectors)
        let userEmbedding = await generateEmbedding(userAnswer)
        let correctEmbedding = await generateEmbedding(correctAnswer)

        // Cosine similarity
        let similarity = cosineSimilarity(userEmbedding, correctEmbedding)

        // Threshold: 0.75 for semantic match
        let isCorrect = similarity >= 0.75

        return (isCorrect: isCorrect, confidence: Float(similarity))
    }

    private func generateEmbedding(_ text: String) async -> [Float] {
        // Run CoreML model inference
        // Returns 384-dimensional vector
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        return Double(dotProduct) / (Double(magnitudeA) * Double(magnitudeB))
    }
}
```

#### 4.4.5 Tier 3: LLM Validation (Optional, Admin-Controlled)

**Accuracy**: 95-98%
**Storage**: 1.5GB (quantized model)
**Latency**: <250ms (P95)
**Availability**: iPhone 12+ (A14+ required)
**Model**: Llama 3.2 1B (4-bit quantized GGUF)
**Server Control**: Feature flag determines availability

Tier 3 uses a small on-device LLM for reasoning-based validation:

```swift
// MARK: - Tier 3 LLM Validator

class KBLLMValidator {
    private let llmService: LLMService  // llama.cpp integration

    func validateWithLLM(
        userAnswer: String,
        question: KBQuestion
    ) async -> (isCorrect: Bool, confidence: Float, reasoning: String) {

        let prompt = """
        Question: \(question.text)
        Correct Answer: \(question.answer.primary)
        Student Answer: \(userAnswer)

        Is the student's answer correct? Consider:
        - Semantic equivalence
        - Common abbreviations
        - Phonetic similarities
        - Domain-specific knowledge

        Respond with EXACTLY this format:
        VERDICT: [CORRECT/INCORRECT]
        CONFIDENCE: [0.0-1.0]
        REASONING: [one sentence explanation]
        """

        let response = await llmService.generate(prompt, maxTokens: 100)

        // Parse structured response
        let verdict = parseVerdict(response)
        let confidence = parseConfidence(response)
        let reasoning = parseReasoning(response)

        return (
            isCorrect: verdict == "CORRECT",
            confidence: confidence,
            reasoning: reasoning
        )
    }
}
```

#### 4.4.6 Performance Targets

| Tier | Accuracy | Latency (P95) | Storage | Availability |
|------|----------|---------------|---------|--------------|
| Tier 1 (Algorithms) | 85-90% | <50ms | 0 bytes | All devices |
| Tier 2 (Embeddings) | 92-95% | <80ms | 80MB | iPhone XS+ |
| Tier 3 (LLM) | 95-98% | <250ms | 1.5GB | iPhone 12+ (admin-controlled) |

#### 4.4.7 Regional Strictness Compliance

```swift
enum KBRegion: String, Codable {
    case colorado
    case minnesota
    case washington

    var validationStrictness: KBStrictnessLevel {
        switch self {
        case .colorado:
            return .strict      // Levenshtein only
        case .minnesota, .washington:
            return .standard    // Enhanced algorithms
        }
    }
}

// Practice mode always uses lenient
let practiceStrictness: KBStrictnessLevel = .lenient  // All tiers available
```

### 4.5 KB Voice Services (TTS/STT)

Knowledge Bowl oral round practice requires high-quality on-device voice services for both question reading (TTS) and answer capture (STT).

#### 4.5.1 Text-to-Speech (TTS)

**Current Implementation:** AVSpeechSynthesizer (iOS built-in)
- ✅ Zero storage requirement
- ✅ Instant availability on all devices
- ✅ Adjustable speed and pitch
- ⚠️ Limited voice quality (robotic)
- ⚠️ Not suitable for competition simulation

**Planned Upgrade:** Kyutai Pocket TTS (January 2026)
- ✅ **100M parameters** - Lightweight (~100MB storage)
- ✅ **Sub-50ms latency** - Real-time speech generation
- ✅ **CPU-only** - Runs on all iOS devices without GPU
- ✅ **High-quality voice cloning** - Using just 5 seconds of audio
- ✅ **Open source** - MIT license, free to integrate
- ✅ **Competition-grade quality** - Can simulate actual moderator voices
- ✅ **Python 3.10+ / PyTorch 2.5+** - Mobile deployment via CoreML conversion

**Implementation Strategy:**

```swift
// MARK: - KB TTS Service (with Pocket TTS upgrade)

actor KBOnDeviceTTS {
    private enum TTSEngine {
        case avSpeech           // Current: AVSpeechSynthesizer
        case pocketTTS          // Upgrade: Kyutai Pocket TTS
    }

    private let engine: TTSEngine
    private var avSpeechSynthesizer: AVSpeechSynthesizer?
    private var pocketTTSModel: PocketTTSModel?  // CoreML converted model

    init(preferPocketTTS: Bool = true) {
        // Try to load Pocket TTS first if available
        if preferPocketTTS, let model = try? PocketTTSModel.load() {
            self.engine = .pocketTTS
            self.pocketTTSModel = model
        } else {
            // Fallback to AVSpeech
            self.engine = .avSpeech
            self.avSpeechSynthesizer = AVSpeechSynthesizer()
        }
    }

    /// Speak question text (supports both engines)
    func speak(_ text: String, rate: Float = 1.0) async throws {
        switch engine {
        case .avSpeech:
            // Current implementation using AVSpeechSynthesizer
            try await speakWithAVSpeech(text, rate: rate)

        case .pocketTTS:
            // Upgraded implementation using Pocket TTS
            try await speakWithPocketTTS(text, rate: rate)
        }
    }

    /// Voice cloning for moderator simulation (Pocket TTS only)
    func cloneVoice(from audioSample: URL) async throws -> VoiceProfile {
        guard engine == .pocketTTS, let model = pocketTTSModel else {
            throw TTSError.voiceCloningNotSupported
        }

        // Clone voice using 5 seconds of audio
        return try await model.cloneVoice(audioFile: audioSample)
    }

    /// Speak with cloned moderator voice
    func speakWithVoice(_ text: String, voice: VoiceProfile) async throws {
        guard engine == .pocketTTS, let model = pocketTTSModel else {
            throw TTSError.voiceCloningNotSupported
        }

        try await model.synthesize(text: text, voiceProfile: voice)
    }

    private func speakWithAVSpeech(_ text: String, rate: Float) async throws {
        guard let synthesizer = avSpeechSynthesizer else {
            throw TTSError.engineNotInitialized
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        // Await completion (implementation omitted for brevity)
        synthesizer.speak(utterance)
    }

    private func speakWithPocketTTS(_ text: String, rate: Float) async throws {
        guard let model = pocketTTSModel else {
            throw TTSError.engineNotInitialized
        }

        // Generate audio with Pocket TTS (<50ms latency)
        let audioData = try await model.synthesize(text: text, speedFactor: rate)

        // Play audio immediately
        try await playAudio(audioData)
    }
}

struct VoiceProfile: Codable {
    let id: UUID
    let name: String
    let embeddings: [Float]  // Voice embedding from 5s sample
    let sampleDuration: TimeInterval
    let createdAt: Date
}

enum TTSError: Error {
    case engineNotInitialized
    case voiceCloningNotSupported
    case synthesisFailed
    case audioPlaybackFailed
}
```

**Migration Path:**
1. **Phase 1 (Current)**: Use AVSpeechSynthesizer for basic practice
2. **Phase 2 (Q1 2026)**: Convert Pocket TTS to CoreML for iOS deployment
3. **Phase 3 (Q2 2026)**: Create competition moderator voice clones
4. **Phase 4 (Q2 2026)**: Make Pocket TTS the default TTS engine

**Storage Requirements:**
- AVSpeechSynthesizer: 0 bytes (built into iOS)
- Pocket TTS CoreML: ~100MB (downloaded once)
- Voice clones: ~1MB each (embeddings only)

**Quality Comparison:**

| Engine | Latency | Quality | Voice Cloning | Storage |
|--------|---------|---------|---------------|---------|
| AVSpeechSynthesizer | ~200ms | Basic (robotic) | ❌ No | 0 bytes |
| Pocket TTS | <50ms | High (natural) | ✅ Yes (5s sample) | ~100MB |

#### 4.5.2 Speech-to-Text (STT)

**Implementation:** SFSpeechRecognizer (iOS built-in)
- ✅ On-device recognition (iOS 13+)
- ✅ Streaming transcription
- ✅ High accuracy for general speech
- ✅ Zero storage requirement
- ⚠️ Requires on-device speech model download (first use)

```swift
// MARK: - KB STT Service

actor KBOnDeviceSTT {
    private let recognizer: SFSpeechRecognizer?

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.recognizer?.supportsOnDeviceRecognition = true
    }

    /// Start streaming recognition
    func startStreaming(audioFormat: AVAudioFormat) async throws -> AsyncStream<RecognitionResult> {
        // Implementation details in existing KBOnDeviceSTT.swift
        // Returns stream of partial and final recognition results
    }

    /// Check if on-device recognition is available
    static var isAvailable: Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            return false
        }
        return recognizer.supportsOnDeviceRecognition
    }
}
```

**Note:** STT does not currently have an upgrade path. SFSpeechRecognizer provides excellent on-device performance for Knowledge Bowl answer capture.

#### 4.5.3 Voice Service Usage in Oral Rounds

**Question Reading Flow:**
1. Load question text from local database
2. Synthesize speech using Pocket TTS (<50ms latency)
3. Play audio immediately
4. Show question text on screen simultaneously
5. Monitor TTS progress for UI feedback

**Answer Capture Flow:**
1. Start SFSpeechRecognizer streaming
2. Capture user's spoken answer
3. Display live transcription
4. Get final transcription when user stops speaking
5. Validate answer using 3-tier validation system (§4.4)

**Competition Simulation:**
- Use cloned moderator voice for realistic practice
- Match actual competition question reading speed
- Simulate conference time announcements
- Practice buzzer timing and answer delivery

---

## 5. Training Modes

### 5.1 Training Mode Definitions

```swift
// MARK: - KB Training Modes

enum KBTrainingMode {
    /// Practice written round (MCQ format)
    case writtenRound(WrittenConfig)

    /// Practice oral round (voice interface)
    case oralRound(OralConfig)

    /// Full match simulation (written + oral)
    case matchSimulation(MatchSimConfig)

    /// Focus on specific domain
    case domainDrill(DomainDrillConfig)

    /// Speed training for faster recall
    case speedDrill(SpeedConfig)

    /// Team conferring practice
    case conferencePractice(ConferenceConfig)

    /// Rebound opportunity practice
    case reboundPractice(ReboundConfig)

    /// Mixed review (spaced repetition)
    case spacedRepetition(SRConfig)
}

struct WrittenConfig {
    let questionCount: Int
    let timeLimit: TimeInterval
    let difficulty: DifficultyTier?
    let domains: [StandardDomain]?
    let showCorrectAfterEach: Bool  // Show answer after each question
}

struct OralConfig {
    let questionCount: Int
    let difficulty: DifficultyTier?
    let domains: [StandardDomain]?
    let simulateConference: Bool
    let conferenceTime: TimeInterval
    let speakingRate: Float
    let includeRebounds: Bool
}

struct MatchSimConfig {
    let region: KBRegion
    let difficulty: DifficultyTier
    let simulateOpponents: Bool
    let opponentStrength: OpponentStrength

    enum OpponentStrength: String, Codable {
        case weak       // New teams
        case average    // Regional level
        case strong     // State level
        case elite      // Championship level
    }
}

struct DomainDrillConfig {
    let targetDomain: StandardDomain
    let questionCount: Int
    let difficulty: DifficultyTier?
    let mixedSubdomains: Bool
}

struct SpeedConfig {
    let startingTimeLimit: TimeInterval
    let minimumTimeLimit: TimeInterval
    let decrementPerQuestion: TimeInterval
    let questionCount: Int
}

struct ConferenceConfig {
    let region: KBRegion  // Determines if verbal allowed
    let startingConferenceTime: TimeInterval
    let targetConferenceTime: TimeInterval  // Goal to reduce to
    let progressiveReduction: Bool
}

struct ReboundConfig {
    let reboundProbability: Double  // How often to simulate rebound opportunity
    let questionCount: Int
    let strategicHoldTraining: Bool  // Practice intentionally not buzzing
}
```

### 5.2 Training Protocol Implementations

```swift
// MARK: - KB-Specific Training Protocols

struct KBWrittenRoundProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Written Round Practice"
    let description = "Practice multiple-choice questions under time pressure"
    let applicableCompetitions: Set<CompetitionFormat> = [.knowledgeBowl]
    let requiredCapabilities: Set<TrainingCapability> = [.writtenInterface, .timerSystem]

    func createSession(config: TrainingSessionConfig) -> TrainingSession {
        return KBWrittenSession(config: config)
    }
}

struct KBOralRoundProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Oral Round Practice"
    let description = "Practice buzzer-based questions with voice answers"
    let applicableCompetitions: Set<CompetitionFormat> = [.knowledgeBowl]
    let requiredCapabilities: Set<TrainingCapability> = [.voiceInput, .voiceOutput, .buzzerSimulation]

    func createSession(config: TrainingSessionConfig) -> TrainingSession {
        return KBOralSession(config: config)
    }
}

struct KBConferenceProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Conference Efficiency Training"
    let description = "Optimize the 15-second team discussion window"
    let applicableCompetitions: Set<CompetitionFormat> = [.knowledgeBowl]
    let requiredCapabilities: Set<TrainingCapability> = [.voiceInput, .voiceOutput, .timerSystem]

    /// For solo practice: Focus on decision speed
    /// For team practice: Focus on communication efficiency
    let soloMode: Bool

    func createSession(config: TrainingSessionConfig) -> TrainingSession {
        return KBConferenceSession(config: config, soloMode: soloMode)
    }
}

struct KBReboundProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Rebound Opportunity Training"
    let description = "Capitalize on opponents' mistakes"
    let applicableCompetitions: Set<CompetitionFormat> = [.knowledgeBowl]
    let requiredCapabilities: Set<TrainingCapability> = [.voiceInput, .voiceOutput]

    func createSession(config: TrainingSessionConfig) -> TrainingSession {
        return KBReboundSession(config: config)
    }
}

struct KBHandSignalProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Hand Signal Communication"
    let description = "Practice non-verbal team communication for Colorado Springs teams"
    let applicableCompetitions: Set<CompetitionFormat> = [.knowledgeBowl]
    let requiredCapabilities: Set<TrainingCapability> = [.voiceOutput]

    /// Recommended signal system
    let signalSystem: HandSignalSystem

    struct HandSignalSystem {
        static let standard = HandSignalSystem()

        let signals: [String: String] = [
            "Closed fist": "I know the answer",
            "Flat hand": "Not sure",
            "Point to teammate": "They should answer",
            "Thumbs up": "Agree with current answer",
            "Thumbs down": "Disagree",
            "Raised fingers (1-5)": "Confidence level"
        ]
    }
}
```

---

## 6. Analytics & Metrics

### 6.1 KB Analytics Service

```swift
// MARK: - KB Analytics Service

class KBAnalyticsService {
    private let proficiencyStore: ProficiencyStore
    private let sessionStore: KBSessionStore

    // ═══════════════════════════════════════════════════════════════════════
    // RECORD OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Record a completed session
    func recordSession(_ session: KBPracticeSession) async {
        // Update session store
        sessionStore.save(session)

        // Update unified proficiency
        for attempt in session.attempts {
            let proficiencyAttempt = QuestionAttempt(
                timestamp: attempt.timestamp,
                moduleId: "com.unamentis.knowledgebowl",
                questionId: attempt.questionId,
                domain: /* lookup domain */,
                subdomain: nil,
                difficulty: session.difficulty,
                wasCorrect: attempt.wasCorrect,
                responseTime: attempt.responseTime,
                competitionMetadata: [
                    "roundType": attempt.roundType.rawValue,
                    "usedConference": attempt.usedConference,
                    "wasRebound": attempt.wasRebound
                ]
            )
            proficiencyStore.recordAttempt(proficiencyAttempt)
        }

        // Update KB-specific analytics
        await updateKBAnalytics(from: session)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // QUERY OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get KB analytics profile for user
    func getAnalytics(for userId: UUID) -> KBAnalyticsProfile {
        return sessionStore.getAnalyticsProfile(for: userId)
    }

    /// Get performance by domain
    func getDomainPerformance(for userId: UUID) -> [StandardDomain: KBDomainStats] {
        return sessionStore.getDomainStats(for: userId)
    }

    /// Get conference efficiency metrics
    func getConferenceEfficiency(for userId: UUID) -> ConferenceStats {
        return sessionStore.getConferenceStats(for: userId)
    }

    /// Get rebound performance
    func getReboundPerformance(for userId: UUID) -> ReboundStats {
        return sessionStore.getReboundStats(for: userId)
    }

    /// Get trend data for visualization
    func getTrends(for userId: UUID, period: DateInterval) -> [WeeklySnapshot] {
        return sessionStore.getTrends(for: userId, in: period)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INSIGHTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Generate actionable insights
    func generateInsights(for userId: UUID) -> [KBInsight] {
        let analytics = getAnalytics(for: userId)
        var insights: [KBInsight] = []

        // Written vs Oral comparison
        if analytics.writtenRoundStats.accuracy > analytics.oralRoundStats.accuracy + 0.15 {
            insights.append(KBInsight(
                type: .performanceGap,
                title: "Oral Round Needs Work",
                message: "Your written accuracy (\(Int(analytics.writtenRoundStats.accuracy * 100))%) is much higher than oral (\(Int(analytics.oralRoundStats.accuracy * 100))%). Focus on oral round practice.",
                priority: .high,
                suggestedAction: .practiceOralRound
            ))
        }

        // Conference efficiency
        if analytics.conferenceStats.conferenceEfficiency < 0.05 {
            insights.append(KBInsight(
                type: .inefficiency,
                title: "Conference Time Not Helping",
                message: "Using conference time isn't improving your accuracy. Practice quicker decision-making.",
                priority: .medium,
                suggestedAction: .practiceConference
            ))
        }

        // Rebound opportunities
        if analytics.reboundStats.reboundSuccessRate < 0.3 && analytics.reboundStats.reboundOpportunities > 20 {
            insights.append(KBInsight(
                type: .missedOpportunity,
                title: "Missing Rebound Opportunities",
                message: "You're converting only \(Int(analytics.reboundStats.reboundSuccessRate * 100))% of rebound opportunities. Practice rebound scenarios.",
                priority: .medium,
                suggestedAction: .practiceRebounds
            ))
        }

        // Domain weaknesses
        let weakDomains = analytics.domainPerformance.filter { $0.value.questionsAttempted > 10 && ($0.value.writtenAccuracy + $0.value.oralAccuracy) / 2 < 0.4 }
        for (domain, stats) in weakDomains {
            insights.append(KBInsight(
                type: .domainWeakness,
                title: "\(domain.rawValue.capitalized) Needs Attention",
                message: "Your accuracy in \(domain.rawValue) is below 40%. Dedicate practice time to this domain.",
                priority: .high,
                suggestedAction: .domainDrill(domain)
            ))
        }

        return insights.sorted { $0.priority.rawValue < $1.priority.rawValue }
    }
}

struct KBInsight {
    let type: InsightType
    let title: String
    let message: String
    let priority: Priority

    let suggestedAction: SuggestedAction

    enum InsightType {
        case performanceGap
        case inefficiency
        case missedOpportunity
        case domainWeakness
        case improvement
        case milestone
    }

    enum Priority: Int {
        case critical = 0
        case high = 1
        case medium = 2
        case low = 3
    }

    enum SuggestedAction {
        case practiceOralRound
        case practiceWrittenRound
        case practiceConference
        case practiceRebounds
        case domainDrill(StandardDomain)
        case speedTraining
    }
}
```

---

## 7. User Interface

### 7.1 UI Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         KB MODULE UI ARCHITECTURE                            │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                          MAIN DASHBOARD                                 ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   ││
│  │  │   Quick     │  │  Training   │  │  Progress   │  │  Settings   │   ││
│  │  │   Start     │  │   Modes     │  │  Analytics  │  │  Regional   │   ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│         ┌──────────────────────────┼──────────────────────────┐             │
│         ▼                          ▼                          ▼             │
│  ┌─────────────┐           ┌─────────────┐           ┌─────────────┐       │
│  │   Written   │           │    Oral     │           │   Match     │       │
│  │   Session   │           │   Session   │           │ Simulation  │       │
│  │     UI      │           │     UI      │           │     UI      │       │
│  └─────────────┘           └─────────────┘           └─────────────┘       │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                       SHARED COMPONENTS                                 ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   ││
│  │  │  Question   │  │   Answer    │  │   Timer     │  │   Results   │   ││
│  │  │   Card      │  │   Input     │  │  Display    │  │   Summary   │   ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Key Views

```swift
// MARK: - Main Dashboard

struct KBDashboardView: View {
    @StateObject private var viewModel: KBDashboardViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Quick Stats Card
                    QuickStatsCard(stats: viewModel.quickStats)

                    // Quick Start
                    QuickStartSection(
                        onWrittenTap: { viewModel.startQuickWritten() },
                        onOralTap: { viewModel.startQuickOral() }
                    )

                    // Recent Progress
                    RecentProgressSection(sessions: viewModel.recentSessions)

                    // Insights
                    if !viewModel.insights.isEmpty {
                        InsightsSection(insights: viewModel.insights)
                    }

                    // Training Modes
                    TrainingModesGrid(modes: viewModel.availableModes)
                }
                .padding()
            }
            .navigationTitle("Knowledge Bowl")
        }
    }
}

// MARK: - Oral Session View

struct KBOralSessionView: View {
    @StateObject private var viewModel: KBOralSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Progress Bar
            ProgressView(value: viewModel.progress)
                .padding(.horizontal)

            // Question Display
            QuestionDisplayView(
                question: viewModel.currentQuestion,
                isReading: viewModel.isReading
            )

            Spacer()

            // Conference Timer (if applicable)
            if viewModel.showConferenceTimer {
                ConferenceTimerView(
                    timeRemaining: viewModel.conferenceTimeRemaining,
                    onSkip: { viewModel.skipConference() }
                )
            }

            // Answer Input
            VoiceAnswerInputView(
                isListening: viewModel.isListening,
                transcript: viewModel.currentTranscript,
                onSubmit: { viewModel.submitAnswer() }
            )

            // Feedback (after answer)
            if let feedback = viewModel.currentFeedback {
                AnswerFeedbackView(feedback: feedback)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("End Session") {
                    viewModel.endSession()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Written Session View

struct KBWrittenSessionView: View {
    @StateObject private var viewModel: KBWrittenSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Timer
            TimerDisplayView(
                timeRemaining: viewModel.timeRemaining,
                isWarning: viewModel.timeRemaining < 60
            )

            // Question + Choices
            ScrollView {
                VStack(spacing: 20) {
                    Text(viewModel.currentQuestion.text)
                        .font(.title3)
                        .padding()

                    ForEach(viewModel.currentQuestion.choices, id: \.label) { choice in
                        ChoiceButton(
                            choice: choice,
                            isSelected: viewModel.selectedChoice == choice.label,
                            isDisabled: viewModel.hasAnswered
                        ) {
                            viewModel.selectChoice(choice.label)
                        }
                    }
                }
                .padding()
            }

            // Submit Button
            Button(action: { viewModel.submitAnswer() }) {
                Text("Submit")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedChoice == nil)
            .padding()
        }
    }
}
```

### 7.3 View Models

```swift
// MARK: - Dashboard View Model

@MainActor
class KBDashboardViewModel: ObservableObject {
    @Published var quickStats: KBQuickStats
    @Published var recentSessions: [KBSessionSummary]
    @Published var insights: [KBInsight]
    @Published var availableModes: [KBTrainingModeInfo]

    private let analyticsService: KBAnalyticsService
    private let sessionManager: KBSessionManager

    init(analyticsService: KBAnalyticsService, sessionManager: KBSessionManager) {
        self.analyticsService = analyticsService
        self.sessionManager = sessionManager
        self.quickStats = KBQuickStats()
        self.recentSessions = []
        self.insights = []
        self.availableModes = KBTrainingModeInfo.allModes
    }

    func loadData() async {
        let userId = getCurrentUserId()

        // Load analytics
        let analytics = analyticsService.getAnalytics(for: userId)

        // Update quick stats
        quickStats = KBQuickStats(
            overallAccuracy: analytics.overallAccuracy,
            writtenAccuracy: analytics.writtenRoundStats.accuracy,
            oralAccuracy: analytics.oralRoundStats.accuracy,
            totalQuestions: analytics.totalQuestionsAttempted,
            streak: calculateStreak()
        )

        // Load recent sessions
        recentSessions = sessionManager.getRecentSessions(for: userId, limit: 5)

        // Generate insights
        insights = analyticsService.generateInsights(for: userId)
    }

    func startQuickWritten() {
        // Navigate to written session with default config
    }

    func startQuickOral() {
        // Navigate to oral session with default config
    }
}

struct KBQuickStats {
    var overallAccuracy: Double = 0
    var writtenAccuracy: Double = 0
    var oralAccuracy: Double = 0
    var totalQuestions: Int = 0
    var streak: Int = 0
}
```

---

## 8. watchOS Integration

### 8.1 Watch App Architecture

```swift
// MARK: - watchOS KB Module

/// Standalone watch training for Knowledge Bowl
/// Focus on: Quick oral practice, flash cards, speed drills

struct KBWatchApp: App {
    var body: some Scene {
        WindowGroup {
            KBWatchMainView()
        }
    }
}

struct KBWatchMainView: View {
    @StateObject private var viewModel = KBWatchViewModel()

    var body: some View {
        NavigationStack {
            List {
                // Quick Practice
                Section("Quick Practice") {
                    NavigationLink("10 Questions") {
                        KBWatchQuickSessionView(questionCount: 10)
                    }
                    NavigationLink("25 Questions") {
                        KBWatchQuickSessionView(questionCount: 25)
                    }
                }

                // Domain Focus
                Section("Domain Drill") {
                    ForEach(viewModel.topDomains, id: \.self) { domain in
                        NavigationLink(domain.rawValue.capitalized) {
                            KBWatchDomainDrillView(domain: domain)
                        }
                    }
                }

                // Flash Cards
                Section("Flash Cards") {
                    NavigationLink("Review Missed") {
                        KBWatchFlashCardsView(mode: .missedQuestions)
                    }
                    NavigationLink("All Topics") {
                        KBWatchFlashCardsView(mode: .allTopics)
                    }
                }

                // Today's Stats
                Section("Today") {
                    StatsRowView(label: "Questions", value: "\(viewModel.todayStats.questionsAnswered)")
                    StatsRowView(label: "Accuracy", value: "\(Int(viewModel.todayStats.accuracy * 100))%")
                }
            }
            .navigationTitle("KB Training")
        }
    }
}
```

### 8.2 Watch-Optimized Training

```swift
// MARK: - Watch Quick Session

struct KBWatchQuickSessionView: View {
    let questionCount: Int
    @StateObject private var viewModel: KBWatchSessionViewModel
    @Environment(\.dismiss) private var dismiss

    init(questionCount: Int) {
        self.questionCount = questionCount
        _viewModel = StateObject(wrappedValue: KBWatchSessionViewModel(questionCount: questionCount))
    }

    var body: some View {
        VStack {
            // Progress
            Text("\(viewModel.currentIndex + 1)/\(questionCount)")
                .font(.caption)

            // Question (scrollable for longer questions)
            ScrollView {
                Text(viewModel.currentQuestion?.text ?? "")
                    .font(.body)
            }
            .frame(maxHeight: 100)

            // Voice Input Button
            Button(action: { viewModel.startListening() }) {
                Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                    .font(.title)
            }
            .buttonStyle(.bordered)

            // Feedback
            if let result = viewModel.lastResult {
                HStack {
                    Image(systemName: result.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.wasCorrect ? .green : .red)
                    Text(result.wasCorrect ? "Correct!" : viewModel.currentQuestion?.answer.primary ?? "")
                        .font(.caption)
                }
            }
        }
        .padding()
        .onAppear { viewModel.start() }
    }
}

@MainActor
class KBWatchSessionViewModel: ObservableObject {
    @Published var currentIndex = 0
    @Published var currentQuestion: KBQuestion?
    @Published var isListening = false
    @Published var lastResult: QuestionResult?

    private let questionCount: Int
    private var questions: [KBQuestion] = []
    private let voicePipeline: UniversalVoicePipeline

    init(questionCount: Int) {
        self.questionCount = questionCount
        self.voicePipeline = UniversalVoicePipeline.shared
    }

    func start() {
        // Load questions optimized for watch (shorter questions)
        questions = loadWatchOptimizedQuestions(count: questionCount)
        currentQuestion = questions.first
    }

    func startListening() {
        isListening = true
        Task {
            let result = await voicePipeline.listenForAnswer(timeout: 5.0)
            await processAnswer(result.transcript)
        }
    }

    private func processAnswer(_ answer: String) async {
        guard let question = currentQuestion else { return }

        let wasCorrect = validateAnswer(answer, against: question.answer)
        lastResult = QuestionResult(wasCorrect: wasCorrect)

        isListening = false

        // Brief delay then next question
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        advanceToNext()
    }

    private func advanceToNext() {
        currentIndex += 1
        if currentIndex < questions.count {
            currentQuestion = questions[currentIndex]
            lastResult = nil
        }
    }
}

struct QuestionResult {
    let wasCorrect: Bool
}
```

---

## 9. Implementation Priorities

### 9.1 Phase 1: Core KB Functionality (Weeks 7-10)

**Status: In Progress** - Core on-device functionality largely complete, validation system enhanced.

| Week | Task | Priority | Status | Deliverable |
|------|------|----------|--------|-------------|
| 7 | KB data models | P0 | ✅ Complete | `KBQuestion.swift`, `KBSession.swift`, `KBRegionalConfig.swift` |
| 7 | Regional configs | P0 | ✅ Complete | Colorado, Minnesota, Washington configs |
| 7 | KB transformer | P0 | ⬜ TODO | `KBTransformer.swift` (spec defined) |
| 8 | Question service | P0 | ✅ Complete | `KBQuestionEngine.swift` (on-device, offline) |
| 8 | Session manager | P0 | ⬜ TODO | Extract from view models to `KBSessionManager.swift` |
| 8 | Unit tests | P0 | ✅ Partial | Core models and services tested |
| 9 | Written round training | P0 | ✅ Complete | `KBWrittenSessionView`, MCQ practice working |
| 9 | Oral round training | P0 | ✅ Complete | `KBOralSessionView`, TTS/STT working |
| 9 | **3-tier answer validation** | P0 | ✅ Complete | Enhanced on-device validation (see §4.4) |
| 9 | On-device TTS/STT | P0 | ✅ Complete | `KBOnDeviceTTS`, `KBOnDeviceSTT` |
| 10 | Analytics service | P0 | ⬜ TODO | `KBAnalyticsService.swift` (spec defined) |
| 10 | Integration tests | P0 | ⬜ TODO | Integration coverage |

**Key Accomplishments:**
- ✅ **On-device architecture established** - Full offline practice capability
- ✅ **3-tier answer validation system** - 85-98% accuracy depending on device tier
- ✅ **Regional compliance** - Strictness levels for Colorado/Minnesota/Washington
- ✅ **Voice services** - AVSpeechSynthesizer TTS, SFSpeechRecognizer STT
- ✅ **Working MVP** - Both written and oral practice modes functional

**Remaining Phase 1 Work:**
- Create `KBTransformer.swift` (canonical → KB question transformation)
- Extract session management logic to `KBSessionManager.swift`
- Create `KBAnalyticsService.swift` (proficiency tracking, insights)
- Complete integration test coverage

### 9.2 Phase 2: Advanced Features (Weeks 11-12)

**Status: Complete** - All Phase 2 features implemented with comprehensive test coverage.

| Week | Task | Priority | Status | Deliverable |
|------|------|----------|--------|-------------|
| 11 | Conference training | P1 | ✅ Complete | `KBConferenceManager.swift`, `KBConferenceTrainingView.swift` |
| 11 | Rebound training | P1 | ✅ Complete | `KBReboundSimulator.swift`, `KBReboundTrainingView.swift` |
| 11 | Match simulation | P1 | ✅ Complete | `KBMatchEngine.swift`, `KBMatchSimulationView.swift` |
| 12 | Analytics UI | P0 | ✅ Complete | `KBProgressView.swift`, `KBDomainMasteryView.swift`, `KBTrendChartView.swift` |
| 12 | Insights generation | P1 | ✅ Complete | Integrated in `KBAnalyticsService.swift` |
| 12 | Domain drill mode | P1 | ✅ Complete | `KBDomainDrillView.swift` |

**Key Phase 2 Accomplishments:**
- ✅ **Conference Training System** - Hand signal training, progressive difficulty, efficiency metrics
- ✅ **Rebound Simulator** - Opponent behavior simulation, strategic decision training
- ✅ **Full Match Engine** - Multi-team simulation, written + oral rounds, scoring by region
- ✅ **Analytics Dashboard** - Progress tracking, domain mastery visualization, trend charts
- ✅ **Comprehensive Test Suite** - Unit tests for all Phase 2 services achieving 80%+ coverage

### 9.3 Phase 3: Polish (Weeks 13-14)

**Status: watchOS Complete** - Dashboard, Settings, and watchOS app implemented.

| Week | Task | Priority | Status | Deliverable |
|------|------|----------|--------|-------------|
| 13 | Dashboard UI | P0 | ✅ Complete | `KBDashboardView.swift` with quick start, stats, session history |
| 13 | Settings UI | P0 | ✅ Complete | `KBSettingsView` (within Dashboard) with regional config |
| 13 | watchOS app | P1 | ✅ Complete | `KBWatchMainView.swift`, `KBWatchQuickSessionView.swift`, `KBWatchDomainDrillView.swift`, `KBWatchFlashCardsView.swift` |
| 14 | User testing | P0 | ⬜ TODO | Feedback integration |
| 14 | Performance optimization | P0 | ⬜ TODO | Optimized builds |
| 14 | Documentation | P1 | ⬜ TODO | User guide |

**Phase 3 Progress:**
- ✅ Main dashboard with header, quick start buttons, session history
- ✅ Statistics section with overall progress, domain breakdown
- ✅ Region selector with rules summary
- ✅ Settings view with full regional configuration display
- ✅ watchOS main view with quick practice, domain drill, flash cards sections
- ✅ watchOS quick session view with tap-to-reveal answers and progress tracking
- ✅ watchOS domain drill view for domain-focused practice
- ✅ watchOS flash cards view with flip animation and review modes

### 9.4 Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| Written round accuracy tracking | 100% | All answers recorded |
| Oral round accuracy tracking | 100% | All answers recorded |
| Voice recognition accuracy | >90% | Correct transcript rate |
| Question retrieval latency | <200ms | P95 latency |
| Session save reliability | 100% | No data loss |
| Analytics accuracy | 100% | Verified calculations |
| Regional rule compliance | 100% | Manual verification |

---

## 10. Testing Requirements

### 10.1 Unit Tests

```swift
// MARK: - KB Unit Tests

class KBQuestionTests: XCTestCase {

    func testTransformation_canonicalToKB() {
        let canonical = createTestCanonicalQuestion()
        let transformer = KBTransformer()

        let kbQuestion = transformer.transform(canonical)

        XCTAssertNotNil(kbQuestion)
        XCTAssertFalse(kbQuestion!.text.isEmpty)
        XCTAssertEqual(kbQuestion!.answer.primary, canonical.answer.primary)
    }

    func testSuitability_writtenRound() {
        let question = createKBQuestion(forWritten: true, forOral: true)

        XCTAssertTrue(question.suitability.forWritten)
        XCTAssertTrue(question.suitability.forOral)
    }

    func testMCQConversion_validQuestion() {
        let question = createKBQuestion(mcqPossible: true)
        let service = KBQuestionService()

        let mcq = service.convertToMCQ(question)

        XCTAssertNotNil(mcq)
        XCTAssertEqual(mcq!.choices.count, 4)
        XCTAssertTrue(mcq!.choices.contains { $0.isCorrect })
    }
}

class KBRegionalConfigTests: XCTestCase {

    func testColoradoConfig_noVerbalConferring() {
        let config = ConferringConfig.colorado

        XCTAssertFalse(config.verbalConferringAllowed)
        XCTAssertTrue(config.handSignalsAllowed)
        XCTAssertEqual(config.conferenceTimeSeconds, 15)
    }

    func testMinnesotaConfig_verbalConferringAllowed() {
        let config = ConferringConfig.minnesota

        XCTAssertTrue(config.verbalConferringAllowed)
        XCTAssertEqual(config.conferenceTimeSeconds, 15)
    }

    func testWashingtonWrittenTime_45Minutes() {
        let structure = MatchStructure.washingtonStandard
        let writtenRound = structure.rounds.first { $0.type == .written }

        XCTAssertEqual(writtenRound?.timeLimit, 2700)  // 45 minutes
    }
}

class KBAnalyticsTests: XCTestCase {

    func testConferenceEfficiency_calculation() {
        let stats = ConferenceStats(
            conferenceSuccessRate: 0.7,
            averageConferenceTime: 10.0,
            accuracyWithConference: 0.75,
            accuracyWithoutConference: 0.65
        )

        XCTAssertEqual(stats.conferenceEfficiency, 0.10, accuracy: 0.01)
    }

    func testInsightGeneration_oralWeakness() {
        let analytics = createAnalyticsProfile(
            writtenAccuracy: 0.85,
            oralAccuracy: 0.55
        )
        let service = KBAnalyticsService()

        let insights = service.generateInsights(for: analytics.userId)

        XCTAssertTrue(insights.contains { $0.type == .performanceGap })
    }
}
```

### 10.2 Integration Tests

```swift
// MARK: - KB Integration Tests

class KBSessionIntegrationTests: XCTestCase {

    func testOralSession_fullFlow() async throws {
        let sessionManager = KBSessionManager()
        let config = KBSessionConfig(
            userId: UUID(),
            questionCount: 5,
            difficulty: .competent,
            domains: nil,
            region: .colorado
        )

        // Start session
        var session = try await sessionManager.startSession(type: .oralPractice, config: config)
        XCTAssertNotNil(session)

        // Process questions (mocked voice input)
        for _ in 0..<5 {
            // ... process with mock
        }

        // End session
        let summary = await sessionManager.endSession()
        XCTAssertEqual(summary.totalQuestions, 5)
    }

    func testProficiencyUpdate_afterSession() async throws {
        let proficiencyStore = ProficiencyStore.shared
        let initialProfile = proficiencyStore.getProfile()

        // Run a session
        // ...

        let updatedProfile = proficiencyStore.getProfile()
        XCTAssertGreaterThan(
            updatedProfile.totalQuestionsAttempted,
            initialProfile.totalQuestionsAttempted
        )
    }
}
```

---

## Appendix A: Regional Rule Summary

| Rule | Colorado | Minnesota | Washington |
|------|----------|-----------|------------|
| Teams per match | 3 | 3 | 3 |
| Team size | 1-4 | 3-6 | 3-5 |
| Active in oral | 4 | 4 | 4 |
| Written questions | 60 | 60 | 50 |
| Written time | 15 min | 15 min | 45 min |
| Written points | 1 | 2 | 2 |
| Oral questions | 50 | 50 | 50 |
| Oral points | 5 | 5 | 5 |
| Conference time | 15 sec | 15 sec | 15 sec |
| Verbal conferring | **NO** | Yes | Yes |
| Hand signals | Yes | Yes | Yes |
| Negative scoring | No | No | No |
| SOS Bonus | No | Yes | No |

---

## Appendix B: Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-17 | Development Team | Initial KB module specification |
| 1.1 | 2026-01-24 | Development Team | Phase 2 complete: Conference training, rebound simulator, match engine, analytics UI. Added comprehensive test coverage for all Phase 2 services. Phase 3 watchOS complete: Dashboard, Settings, and full watchOS companion app with quick practice, domain drill, and flash cards modes. |

---

*This document provides the technical specification for implementing the Knowledge Bowl module. For detailed domain knowledge, training philosophy, and pedagogical approaches, see [KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md](KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md).*
