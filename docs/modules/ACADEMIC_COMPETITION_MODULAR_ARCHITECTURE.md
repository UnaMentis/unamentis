# Academic Competition Modular Architecture

## Design Philosophy: Separate Yet Unified

This document defines the architecture for building **independent but interconnected** competition modules. Each module (Knowledge Bowl, Quiz Bowl, Science Bowl) operates autonomously while sharing a common foundation of questions, techniques, and functionality.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         COMPETITION MODULES                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │ Knowledge   │    │ Quiz Bowl   │    │ Science     │    │ Future      │  │
│  │ Bowl Module │    │ Module      │    │ Bowl Module │    │ Modules...  │  │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘  │
│         │                  │                  │                  │          │
│         └──────────────────┴──────────────────┴──────────────────┘          │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    SHARED CORE LAYER                                 │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │    │
│  │  │Question │  │ Voice   │  │Analytics│  │Training │  │  User   │   │    │
│  │  │ Engine  │  │Pipeline │  │ Engine  │  │Techniques│  │Profiles │   │    │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

# PART I: SHARED CORE LAYER

## 1. Universal Question Engine

### 1.1 Canonical Question Schema

All questions across all modules are stored in a **single unified schema**. Module-specific renderings are transformations of this canonical form.

```swift
// MARK: - Canonical Question (Competition-Agnostic)

struct CanonicalQuestion: Codable, Identifiable {
    let id: UUID
    let version: Int
    let createdAt: Date
    let updatedAt: Date

    // Core Content
    let content: QuestionContent
    let answer: AnswerSpec
    let metadata: QuestionMetadata

    // Domain Classification
    let domains: [DomainTag]
    let difficulty: DifficultyRating

    // Competition Compatibility
    let compatibleFormats: [CompetitionFormat]
    let transformationHints: TransformationHints
}

struct QuestionContent: Codable {
    /// Full pyramidal version (longest, most clues)
    let pyramidalFull: String

    /// Medium length version (3-4 sentences)
    let mediumForm: String

    /// Short form (1-2 sentences, giveaway only)
    let shortForm: String

    /// Individual clues for pyramidal questions
    let clues: [PyramidalClue]?

    /// Power mark position (character index where 15→10 transition occurs)
    let powerMarkIndex: Int?
}

struct PyramidalClue: Codable {
    let text: String
    let difficulty: ClueDifficulty  // .leadIn, .early, .middle, .late, .giveaway
    let standaloneUsable: Bool      // Can this clue work as a short-form question?
}

enum ClueDifficulty: String, Codable {
    case leadIn     // Hardest, only experts know
    case early      // Very difficult
    case middle     // Moderate difficulty
    case late       // Easier, common knowledge among players
    case giveaway   // Most players should know
}

struct AnswerSpec: Codable {
    /// Primary accepted answer
    let primary: String

    /// Alternative acceptable answers
    let alternates: [String]

    /// Answers that prompt "be more specific"
    let promptForMore: [String]

    /// Phonetic hints for voice recognition
    let phoneticVariants: [String]

    /// Answer type for validation
    let answerType: AnswerType
}

enum AnswerType: String, Codable {
    case person
    case place
    case thing
    case concept
    case number
    case date
    case title        // Book, film, artwork
    case scientific   // Formula, element, species
}

struct QuestionMetadata: Codable {
    let author: String?
    let source: String?           // Original competition/set
    let yearWritten: Int?
    let lastVerified: Date?
    let factualAccuracyScore: Double?  // 0-1, from verification system
    let usageCount: Int
    let averageCorrectRate: Double?
}
```

### 1.2 Domain Taxonomy (Shared Across All Modules)

```swift
struct DomainTag: Codable, Hashable {
    let primary: PrimaryDomain
    let secondary: String?        // Subdomain
    let tertiary: String?         // Specific topic
}

enum PrimaryDomain: String, Codable, CaseIterable {
    // Academic Domains (shared by most competitions)
    case literature
    case history
    case science
    case mathematics
    case fineArts
    case geography
    case socialScience

    // Specialized Domains
    case religion
    case mythology
    case philosophy
    case currentEvents
    case popCulture

    // Science Bowl Specific (subdomains of .science)
    case biology
    case chemistry
    case physics
    case earthScience
    case astronomy
    case energy

    // Returns which competitions use this domain
    var competitionCompatibility: [CompetitionFormat] {
        switch self {
        case .literature, .history, .geography, .socialScience:
            return [.quizBowl, .knowledgeBowl, .historyBowl]
        case .science:
            return [.quizBowl, .knowledgeBowl, .scienceBowl]
        case .biology, .chemistry, .physics, .earthScience, .astronomy, .energy:
            return [.scienceBowl, .quizBowl, .knowledgeBowl]
        case .mathematics:
            return [.quizBowl, .knowledgeBowl, .scienceBowl]
        case .fineArts:
            return [.quizBowl, .knowledgeBowl]
        case .religion, .mythology, .philosophy:
            return [.quizBowl, .knowledgeBowl]
        case .currentEvents:
            return [.knowledgeBowl]
        case .popCulture:
            return [.knowledgeBowl]  // Limited in QB
        }
    }
}
```

### 1.3 Difficulty Rating System (Universal)

```swift
struct DifficultyRating: Codable {
    /// Absolute difficulty (1-10 scale, competition-agnostic)
    let absolute: Double

    /// Competition-specific difficulty estimates
    let competitionRelative: [CompetitionFormat: RelativeDifficulty]

    /// Grade level appropriateness
    let gradeLevels: [GradeLevel]
}

struct RelativeDifficulty: Codable {
    let tier: DifficultyTier       // .easy, .medium, .hard, .championship
    let percentileEstimate: Double  // What % of players would get this?
}

enum DifficultyTier: String, Codable {
    case novice         // New players, first year
    case developing     // 1-2 years experience
    case competent      // Regional competitive
    case advanced       // State competitive
    case championship   // National/elite level
}

enum GradeLevel: String, Codable {
    case elementary     // 4-6
    case middleSchool   // 7-9
    case highSchool     // 9-12
    case college        // Post-secondary
}
```

---

## 2. Question Transformation Engine

The transformation engine converts canonical questions into competition-specific formats.

### 2.1 Transformation Pipeline

```swift
protocol QuestionTransformer {
    associatedtype Output

    /// Transform a canonical question for a specific competition
    func transform(_ question: CanonicalQuestion) -> Output?

    /// Check if a question can be used in this competition
    func isCompatible(_ question: CanonicalQuestion) -> Bool

    /// Get transformation quality score (how well does this fit?)
    func qualityScore(_ question: CanonicalQuestion) -> Double
}

// MARK: - Quiz Bowl Transformer

struct QuizBowlTransformer: QuestionTransformer {
    typealias Output = QuizBowlTossup

    func transform(_ question: CanonicalQuestion) -> QuizBowlTossup? {
        guard isCompatible(question) else { return nil }

        return QuizBowlTossup(
            id: UUID(),
            sourceQuestionId: question.id,
            text: question.content.pyramidalFull,
            clues: question.content.clues ?? [],
            powerMarkIndex: question.content.powerMarkIndex ?? estimatePowerMark(question),
            answer: question.answer,
            domains: question.domains,
            difficulty: question.difficulty.competitionRelative[.quizBowl]?.tier ?? .competent
        )
    }

    func isCompatible(_ question: CanonicalQuestion) -> Bool {
        // Must have pyramidal content or be transformable
        return question.content.pyramidalFull.count > 100 ||
               question.content.clues?.count ?? 0 >= 3
    }

    private func estimatePowerMark(_ question: CanonicalQuestion) -> Int {
        // Power mark typically at ~40% through the question
        return Int(Double(question.content.pyramidalFull.count) * 0.4)
    }
}

// MARK: - Knowledge Bowl Transformer

struct KnowledgeBowlTransformer: QuestionTransformer {
    typealias Output = KnowledgeBowlQuestion

    func transform(_ question: CanonicalQuestion) -> KnowledgeBowlQuestion? {
        guard isCompatible(question) else { return nil }

        // Use medium or short form for KB (not pyramidal)
        let text = question.content.mediumForm.isEmpty ?
                   question.content.shortForm :
                   question.content.mediumForm

        return KnowledgeBowlQuestion(
            id: UUID(),
            sourceQuestionId: question.id,
            text: text,
            answer: question.answer,
            domains: question.domains,
            suitableForWritten: true,  // Most KB questions work for both
            suitableForOral: true
        )
    }

    func isCompatible(_ question: CanonicalQuestion) -> Bool {
        // KB can use almost any question
        return !question.content.shortForm.isEmpty ||
               !question.content.mediumForm.isEmpty
    }
}

// MARK: - Science Bowl Transformer

struct ScienceBowlTransformer: QuestionTransformer {
    typealias Output = ScienceBowlQuestion

    let scienceDomains: Set<PrimaryDomain> = [
        .science, .biology, .chemistry, .physics,
        .earthScience, .astronomy, .energy, .mathematics
    ]

    func transform(_ question: CanonicalQuestion) -> ScienceBowlQuestion? {
        guard isCompatible(question) else { return nil }

        // Science Bowl uses short, direct questions
        let text = question.content.shortForm

        // Determine Science Bowl category
        let category = determineScienceBowlCategory(question.domains)

        return ScienceBowlQuestion(
            id: UUID(),
            sourceQuestionId: question.id,
            text: text,
            answer: question.answer,
            category: category,
            questionType: .tossup,  // Or determine based on content
            difficulty: question.difficulty.competitionRelative[.scienceBowl]?.tier ?? .competent
        )
    }

    func isCompatible(_ question: CanonicalQuestion) -> Bool {
        // Must be STEM domain
        return question.domains.contains { scienceDomains.contains($0.primary) }
    }

    private func determineScienceBowlCategory(_ domains: [DomainTag]) -> ScienceBowlCategory {
        for domain in domains {
            switch domain.primary {
            case .biology: return .biology
            case .chemistry: return .chemistry
            case .physics: return .physics
            case .earthScience, .astronomy: return .earthAndSpace
            case .mathematics: return .mathematics
            case .energy: return .energy
            default: continue
            }
        }
        return .generalScience
    }
}
```

### 2.2 Bidirectional Question Creation

Questions can be created in any module and flow to others:

```swift
class QuestionSharingService {
    private let canonicalStore: CanonicalQuestionStore
    private let transformers: [CompetitionFormat: any QuestionTransformer]

    /// Create a new question from any competition format
    func ingestQuestion<T: CompetitionQuestion>(_ question: T,
                                                  source: CompetitionFormat) -> CanonicalQuestion {
        // Convert competition-specific question to canonical form
        let canonical = canonicalize(question, source: source)

        // Store in canonical database
        canonicalStore.save(canonical)

        // Notify other modules of new content
        NotificationCenter.default.post(
            name: .newCanonicalQuestionAvailable,
            object: canonical
        )

        return canonical
    }

    /// Get questions for a specific competition
    func questionsFor(competition: CompetitionFormat,
                      filters: QuestionFilters) -> [any CompetitionQuestion] {
        let canonicals = canonicalStore.query(filters)

        guard let transformer = transformers[competition] else { return [] }

        return canonicals.compactMap { canonical in
            transformer.transform(canonical) as? any CompetitionQuestion
        }
    }

    /// Find questions that work across multiple competitions
    func crossCompatibleQuestions(competitions: Set<CompetitionFormat>,
                                   filters: QuestionFilters) -> [CanonicalQuestion] {
        return canonicalStore.query(filters).filter { question in
            competitions.isSubset(of: Set(question.compatibleFormats))
        }
    }
}
```

---

## 3. Shared Voice Pipeline

### 3.1 Universal Voice Interface

```swift
protocol VoiceCapable {
    /// Start listening for answer
    func startListening(timeout: TimeInterval)

    /// Stop listening and process
    func stopListening() -> VoiceResult

    /// Speak text aloud
    func speak(_ text: String, rate: SpeechRate) async

    /// Detect buzz signal
    func detectBuzz() -> BuzzEvent?
}

struct VoiceResult {
    let transcript: String
    let confidence: Double
    let alternativeTranscripts: [String]
    let duration: TimeInterval
    let buzzTimestamp: Date?
}

enum SpeechRate: Double {
    case slow = 0.8
    case normal = 1.0
    case fast = 1.2
    case competitionSpeed = 1.4
}

// Shared implementation used by all modules
class UniversalVoicePipeline: VoiceCapable {
    private let speechRecognizer: SpeechRecognizer
    private let speechSynthesizer: SpeechSynthesizer
    private let buzzDetector: BuzzDetector

    // Competition-specific configurations
    private var currentConfig: VoiceConfig

    struct VoiceConfig {
        let buzzMode: BuzzMode
        let answerTimeout: TimeInterval
        let speakingRate: SpeechRate
        let allowInterruption: Bool
    }

    enum BuzzMode {
        case individual      // Quiz Bowl - one person buzzes
        case team           // Knowledge Bowl - team buzzer
        case timed          // Science Bowl - recognition then answer
    }

    func configure(for competition: CompetitionFormat) {
        switch competition {
        case .quizBowl:
            currentConfig = VoiceConfig(
                buzzMode: .individual,
                answerTimeout: 5.0,
                speakingRate: .competitionSpeed,
                allowInterruption: true  // Can buzz mid-question
            )
        case .knowledgeBowl:
            currentConfig = VoiceConfig(
                buzzMode: .team,
                answerTimeout: 15.0,  // Conference time
                speakingRate: .normal,
                allowInterruption: true
            )
        case .scienceBowl:
            currentConfig = VoiceConfig(
                buzzMode: .individual,
                answerTimeout: 5.0,
                speakingRate: .fast,
                allowInterruption: false  // Must be recognized first
            )
        default:
            currentConfig = VoiceConfig(
                buzzMode: .individual,
                answerTimeout: 5.0,
                speakingRate: .normal,
                allowInterruption: true
            )
        }
    }
}
```

---

## 4. Shared Analytics Engine

### 4.1 Universal Performance Metrics

```swift
struct UniversalPerformanceProfile: Codable {
    let userId: UUID
    let lastUpdated: Date

    // Domain Mastery (shared across all competitions)
    var domainMastery: [PrimaryDomain: MasteryLevel]

    // Speed Metrics
    var responseSpeed: ResponseSpeedProfile

    // Accuracy Metrics
    var accuracy: AccuracyProfile

    // Competition-Specific Extensions
    var competitionProfiles: [CompetitionFormat: CompetitionSpecificProfile]
}

struct MasteryLevel: Codable {
    let score: Double           // 0-100
    let confidence: Double      // Statistical confidence in score
    let questionsAttempted: Int
    let lastPracticed: Date
    let trend: Trend            // .improving, .stable, .declining

    // Subdomain breakdown
    var subdomains: [String: Double]
}

struct ResponseSpeedProfile: Codable {
    // Universal metrics
    var averageResponseTime: TimeInterval
    var medianResponseTime: TimeInterval
    var fastestDecile: TimeInterval

    // By domain
    var speedByDomain: [PrimaryDomain: TimeInterval]

    // By difficulty
    var speedByDifficulty: [DifficultyTier: TimeInterval]
}

struct AccuracyProfile: Codable {
    var overallAccuracy: Double
    var accuracyByDomain: [PrimaryDomain: Double]
    var accuracyByDifficulty: [DifficultyTier: Double]

    // Trend analysis
    var recentAccuracy: Double      // Last 50 questions
    var trend: Trend
}

// Competition-specific profiles extend the base
protocol CompetitionSpecificProfile: Codable {
    var competitionFormat: CompetitionFormat { get }
}

struct QuizBowlProfile: CompetitionSpecificProfile {
    let competitionFormat = CompetitionFormat.quizBowl

    var powerRate: Double           // % of correct answers that were powers
    var negRate: Double             // % of buzzes that were negs
    var buzzDepth: Double           // Average % through question at buzz
    var bonusConversion: Double     // Average bonus points per bonus heard
    var celerity: Double            // Speed score (NAQT metric)
}

struct KnowledgeBowlProfile: CompetitionSpecificProfile {
    let competitionFormat = CompetitionFormat.knowledgeBowl

    var conferenceEfficiency: Double    // How well team discussion helps
    var reboundSuccessRate: Double      // Success on rebound opportunities
    var writtenRoundAccuracy: Double
    var oralRoundAccuracy: Double
    var letThemFightSuccess: Double     // Strategic hold success
}

struct ScienceBowlProfile: CompetitionSpecificProfile {
    let competitionFormat = CompetitionFormat.scienceBowl

    var categoryStrengths: [ScienceBowlCategory: Double]
    var tossupAccuracy: Double
    var bonusAccuracy: Double
    var mathSpeed: TimeInterval         // Computation questions
}
```

### 4.2 Cross-Competition Insights

```swift
class CrossCompetitionAnalytics {

    /// Identify strengths that transfer across competitions
    func identifyTransferableStrengths(profile: UniversalPerformanceProfile) -> [TransferableStrength] {
        var strengths: [TransferableStrength] = []

        // Domain mastery transfers
        for (domain, mastery) in profile.domainMastery where mastery.score > 70 {
            let applicableCompetitions = domain.competitionCompatibility

            strengths.append(TransferableStrength(
                type: .domainKnowledge(domain),
                currentLevel: mastery.score,
                applicableTo: applicableCompetitions,
                recommendation: "Your \(domain) strength applies to: \(applicableCompetitions.map(\.rawValue).joined(separator: ", "))"
            ))
        }

        // Speed skills transfer
        if profile.responseSpeed.averageResponseTime < 2.0 {
            strengths.append(TransferableStrength(
                type: .quickRecall,
                currentLevel: 85,
                applicableTo: [.quizBowl, .scienceBowl],
                recommendation: "Your quick recall is valuable for individual buzzer competitions"
            ))
        }

        // Team skills (from KB) transfer
        if let kbProfile = profile.competitionProfiles[.knowledgeBowl] as? KnowledgeBowlProfile,
           kbProfile.conferenceEfficiency > 0.7 {
            strengths.append(TransferableStrength(
                type: .teamCommunication,
                currentLevel: kbProfile.conferenceEfficiency * 100,
                applicableTo: [.quizBowl, .knowledgeBowl],  // Bonus collaboration
                recommendation: "Your team communication skills help with Quiz Bowl bonuses"
            ))
        }

        return strengths
    }

    /// Recommend which competition to try based on current profile
    func recommendNewCompetition(profile: UniversalPerformanceProfile,
                                  currentCompetitions: Set<CompetitionFormat>) -> CompetitionRecommendation {
        var scores: [CompetitionFormat: Double] = [:]

        for format in CompetitionFormat.allCases where !currentCompetitions.contains(format) {
            scores[format] = calculateFitScore(profile: profile, for: format)
        }

        guard let best = scores.max(by: { $0.value < $1.value }) else {
            return CompetitionRecommendation(format: .quizBowl, confidence: 0, reasons: [])
        }

        return CompetitionRecommendation(
            format: best.key,
            confidence: best.value,
            reasons: generateReasons(profile: profile, for: best.key)
        )
    }
}

struct TransferableStrength {
    enum StrengthType {
        case domainKnowledge(PrimaryDomain)
        case quickRecall
        case teamCommunication
        case pyramidalParsing
        case strategicBuzzing
    }

    let type: StrengthType
    let currentLevel: Double
    let applicableTo: [CompetitionFormat]
    let recommendation: String
}
```

---

## 5. Shared Training Techniques

### 5.1 Universal Training Protocol Library

```swift
protocol TrainingProtocol {
    var id: UUID { get }
    var name: String { get }
    var description: String { get }
    var applicableCompetitions: [CompetitionFormat] { get }
    var requiredCapabilities: [TrainingCapability] { get }

    func configure(for competition: CompetitionFormat) -> TrainingSession
}

enum TrainingCapability {
    case voiceInput
    case voiceOutput
    case buzzerSimulation
    case timerSystem
    case multiPlayer
    case writtenInterface
}

// MARK: - Shared Training Protocols

struct SpacedRepetitionProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Spaced Repetition"
    let description = "Review questions at optimal intervals for long-term retention"
    let applicableCompetitions: [CompetitionFormat] = [.quizBowl, .knowledgeBowl, .scienceBowl, .historyBowl]
    let requiredCapabilities: [TrainingCapability] = [.voiceOutput]

    func configure(for competition: CompetitionFormat) -> TrainingSession {
        // Configuration varies by competition but algorithm is shared
        return TrainingSession(/* ... */)
    }
}

struct DomainDrillProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Domain Deep Dive"
    let description = "Focused practice on a single knowledge domain"
    let applicableCompetitions: [CompetitionFormat] = CompetitionFormat.allCases
    let requiredCapabilities: [TrainingCapability] = [.voiceInput, .voiceOutput]

    let targetDomain: PrimaryDomain
    let duration: TimeInterval
    let difficultyProgression: Bool
}

struct SpeedDrillProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Speed Training"
    let description = "Progressively faster question delivery to improve recall speed"
    let applicableCompetitions: [CompetitionFormat] = [.quizBowl, .scienceBowl]
    let requiredCapabilities: [TrainingCapability] = [.voiceInput, .voiceOutput, .timerSystem]

    let startingPace: TimeInterval
    let targetPace: TimeInterval
    let decrementPerRound: TimeInterval
}

// MARK: - Competition-Specific Training (uses shared base)

struct PyramidalParsingProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Pyramidal Pattern Recognition"
    let description = "Learn to identify answer from early clues in pyramidal questions"
    let applicableCompetitions: [CompetitionFormat] = [.quizBowl, .historyBowl]
    let requiredCapabilities: [TrainingCapability] = [.voiceInput, .voiceOutput, .buzzerSimulation]

    // Quiz Bowl specific
    let showClueProgression: Bool
    let targetBuzzDepth: Double  // Aim to buzz at 40% through question
}

struct ConferenceEfficiencyProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Team Conference Training"
    let description = "Optimize 15-second team discussion window"
    let applicableCompetitions: [CompetitionFormat] = [.knowledgeBowl]
    let requiredCapabilities: [TrainingCapability] = [.voiceInput, .voiceOutput, .timerSystem, .multiPlayer]

    // Knowledge Bowl specific
    let progressiveTimeReduction: Bool
    let handSignalMode: Bool  // For Colorado teams
}
```

### 5.2 Training Protocol Sharing Matrix

| Protocol | Quiz Bowl | Knowledge Bowl | Science Bowl | Notes |
|----------|-----------|----------------|--------------|-------|
| Spaced Repetition | ✅ | ✅ | ✅ | Identical algorithm |
| Domain Drill | ✅ | ✅ | ✅ (STEM only) | Filter by domain |
| Speed Training | ✅ | ❌ | ✅ | KB has conference time |
| Pyramidal Parsing | ✅ | ❌ | ❌ | QB-specific format |
| Conference Training | ❌ | ✅ | ❌ | KB-specific mechanic |
| Bonus Conversion | ✅ | ❌ | ✅ | Similar mechanic |
| Neg Avoidance | ✅ | ❌ | ❌ | KB has no negs |

---

## 6. User Profile Unification

### 6.1 Single Identity Across Modules

```swift
struct UnifiedUserProfile: Codable {
    let userId: UUID
    let displayName: String
    let email: String
    let createdAt: Date

    // Enabled modules
    var activeModules: Set<CompetitionFormat>

    // Unified performance data
    var performanceProfile: UniversalPerformanceProfile

    // Module-specific settings
    var moduleSettings: [CompetitionFormat: ModuleSettings]

    // Cross-module achievements
    var achievements: [Achievement]

    // Learning preferences (apply across all modules)
    var learningPreferences: LearningPreferences
}

struct LearningPreferences: Codable {
    var preferredSessionLength: TimeInterval
    var voiceSpeed: SpeechRate
    var difficultyProgression: ProgressionStyle
    var practiceReminders: Bool
    var reminderTime: DateComponents?

    enum ProgressionStyle: String, Codable {
        case adaptive       // System chooses based on performance
        case gradual        // Slow increase
        case aggressive     // Quick ramp-up
        case maintenance    // Stay at current level
    }
}

struct Achievement: Codable {
    let id: UUID
    let name: String
    let description: String
    let earnedAt: Date
    let applicableCompetitions: [CompetitionFormat]  // Some achievements span modules
    let rarity: AchievementRarity
}
```

---

# PART II: QUIZ BOWL MODULE SPECIFICATION

## 7. Quiz Bowl Module Overview

### 7.1 Competition Profile

| Attribute | Value |
|-----------|-------|
| **Module ID** | `com.unamentis.quizbowl` |
| **Primary Organizations** | NAQT, ACF, PACE |
| **Geographic Scope** | 50 US states + Canada + International |
| **Annual Participants** | ~50,000 students |
| **Voice Percentage** | 95% |
| **Unique Mechanics** | Pyramidal questions, Powers, Negs, Tossup/Bonus |

### 7.2 Module Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     QUIZ BOWL MODULE                                 │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │ Tossup Engine   │  │ Bonus Engine    │  │ Match Simulator │     │
│  │ - Pyramidal     │  │ - 3-part bonus  │  │ - 2-team format │     │
│  │ - Power/Neg     │  │ - Team collab   │  │ - Full rounds   │     │
│  │ - Buzz timing   │  │ - 30 pt max     │  │ - Stat tracking │     │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘     │
│           │                    │                    │               │
│           └────────────────────┴────────────────────┘               │
│                                │                                     │
│                    ┌───────────┴───────────┐                        │
│                    │  QB-Specific Analytics │                        │
│                    │  - Celerity           │                        │
│                    │  - Power rate         │                        │
│                    │  - Neg rate           │                        │
│                    │  - Bonus conversion   │                        │
│                    └───────────────────────┘                        │
│                                │                                     │
│  ┌─────────────────────────────┴─────────────────────────────┐     │
│  │                    SHARED CORE LAYER                       │     │
│  │  Question Engine │ Voice Pipeline │ Analytics │ Profiles  │     │
│  └────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.3 Quiz Bowl Data Models

```swift
// MARK: - Quiz Bowl Specific Models

struct QuizBowlTossup: CompetitionQuestion {
    let id: UUID
    let sourceQuestionId: UUID?  // Link to canonical question

    let text: String
    let clues: [PyramidalClue]
    let powerMarkIndex: Int

    let answer: AnswerSpec
    let domains: [DomainTag]
    let difficulty: DifficultyTier

    // QB-specific metadata
    let setSource: String?      // "2024 NAQT SCT", "2023 ACF Fall"
    let questionNumber: Int?
}

struct QuizBowlBonus: Codable {
    let id: UUID
    let sourceQuestionId: UUID?

    let leadin: String          // "Name these European rivers..."
    let parts: [BonusPart]
    let domains: [DomainTag]
    let difficulty: DifficultyTier
}

struct BonusPart: Codable {
    let text: String
    let answer: AnswerSpec
    let pointValue: Int         // Usually 10
    let difficulty: PartDifficulty

    enum PartDifficulty: String, Codable {
        case easy       // Most teams get
        case medium     // Good teams get
        case hard       // Top teams get
    }
}

struct QuizBowlMatchResult: Codable {
    let matchId: UUID
    let timestamp: Date
    let format: QBMatchFormat

    // Player results
    let playerStats: [UUID: QBPlayerStats]

    // Team results
    let teamScore: Int
    let opponentScore: Int?     // nil for solo practice

    // Question breakdown
    let tossupResults: [TossupResult]
    let bonusResults: [BonusResult]
}

struct QBPlayerStats: Codable {
    let playerId: UUID

    // Tossup stats
    var tossups: Int            // Total attempts
    var powers: Int             // 15-point answers
    var tens: Int               // 10-point answers
    var negs: Int               // -5 point wrong buzzes

    // Derived metrics
    var points: Int { powers * 15 + tens * 10 - negs * 5 }
    var powerRate: Double { tossups > 0 ? Double(powers) / Double(tossups) : 0 }
    var negRate: Double { tossups > 0 ? Double(negs) / Double(tossups) : 0 }

    // Bonus contribution (when applicable)
    var bonusPointsContributed: Int
}

struct TossupResult: Codable {
    let questionId: UUID
    let buzzerId: UUID?         // Who buzzed (nil if dead)
    let buzzPoint: Int          // Character index at buzz
    let wasCorrect: Bool
    let pointsAwarded: Int      // 15, 10, 0, or -5
    let timeToAnswer: TimeInterval
}

enum QBMatchFormat: String, Codable {
    case naqt           // 24 tossups, powers at 15
    case acf            // 20 tossups, no powers, no negs
    case pace           // 20 tossups, powers at 20, no negs
    case practice       // Flexible
}
```

### 7.4 Quiz Bowl Training Modes

```swift
enum QuizBowlTrainingMode {
    /// Solo tossup practice with immediate feedback
    case tossupDrill(TossupDrillConfig)

    /// Bonus practice (team or solo)
    case bonusPractice(BonusPracticeConfig)

    /// Full packet practice (tossups + bonuses)
    case packetPractice(PacketConfig)

    /// Pyramidal parsing - learn to buzz early
    case pyramidalTraining(PyramidalConfig)

    /// Neg reduction - learn when NOT to buzz
    case negReduction(NegReductionConfig)

    /// Speed training - faster recall
    case speedDrill(SpeedConfig)

    /// Match simulation against AI
    case matchSimulation(MatchSimConfig)
}

struct TossupDrillConfig {
    let questionCount: Int
    let domains: [PrimaryDomain]?   // nil = all domains
    let difficulty: DifficultyTier?
    let showClueProgression: Bool   // Highlight clues as read
    let allowReplay: Bool
}

struct PyramidalConfig {
    let targetBuzzDepth: Double     // Aim for 40% = buzz at 40% through
    let showOptimalBuzzPoint: Bool  // After answer, show where top players buzz
    let trackImprovement: Bool
    let difficultyProgression: Bool // Start easier, get harder
}

struct NegReductionConfig {
    let showConfidencePrompt: Bool  // "How sure are you?" before allowing buzz
    let penaltyEmphasis: Bool       // Highlight point cost of negs
    let reviewNeggedQuestions: Bool // Extra study on wrong buzzes
}
```

### 7.5 Quiz Bowl Analytics

```swift
struct QuizBowlAnalytics {
    let userId: UUID
    let periodStart: Date
    let periodEnd: Date

    // Core Performance
    var totalTossups: Int
    var totalPowers: Int
    var totalTens: Int
    var totalNegs: Int
    var totalPoints: Int

    // Rates
    var conversionRate: Double      // (powers + tens) / tossups
    var powerRate: Double           // powers / (powers + tens)
    var negRate: Double             // negs / tossups

    // NAQT-style Celerity
    var celerity: Double            // Average buzz depth (lower = better)
    var celerityByDomain: [PrimaryDomain: Double]

    // Bonus Performance
    var bonusesHeard: Int
    var totalBonusPoints: Int
    var bonusConversion: Double     // Average PPB (points per bonus)
    var bonusConversionByDomain: [PrimaryDomain: Double]

    // Domain Breakdown
    var performanceByDomain: [PrimaryDomain: DomainPerformance]

    // Trends
    var weeklyTrend: [WeeklySnapshot]
    var improvementRate: Double     // % improvement per week
}

struct DomainPerformance: Codable {
    let domain: PrimaryDomain
    var tossups: Int
    var correct: Int
    var powers: Int
    var negs: Int
    var averageBuzzDepth: Double
}
```

---

## 8. Quiz Bowl Training Curriculum

### 8.1 Skill Progression Framework

```
Level 1: Foundation (Weeks 1-4)
├── Learn answer recognition
├── Build core knowledge base
├── Understand pyramidal structure
└── Target: 40% conversion rate

Level 2: Development (Weeks 5-12)
├── Improve buzz timing
├── Reduce neg rate to <15%
├── Expand domain coverage
└── Target: 55% conversion, <10% negs

Level 3: Competitive (Weeks 13-24)
├── Power training (buzz early on known topics)
├── Bonus optimization
├── Strategic buzzing (know when to hold)
└── Target: 65% conversion, 30% power rate

Level 4: Elite (Ongoing)
├── Clue anticipation
├── Cross-clue recognition
├── Tournament preparation
└── Target: 75%+ conversion, 40%+ power rate
```

### 8.2 Quiz Bowl-Specific Drills

```swift
// MARK: - QB Training Drills

struct PowerBuzzDrill {
    /// Practice buzzing on earlier clues for topics you know well

    let name = "Power Hunting"
    let description = "Identify your strongest topics and practice buzzing before the power mark"

    func execute(session: TrainingSession) {
        // 1. Select questions from user's strongest domains
        let strongDomains = session.user.performanceProfile
            .domainMastery
            .filter { $0.value.score > 75 }
            .map { $0.key }

        // 2. Present questions, track buzz timing
        // 3. Show where power mark is after each answer
        // 4. Celebrate early buzzes, analyze late ones
    }
}

struct NegAvoidanceDrill {
    /// Learn to recognize when you DON'T know vs. might know

    let name = "Confidence Calibration"
    let description = "Improve your internal sense of whether you actually know the answer"

    func execute(session: TrainingSession) {
        // 1. Present tossups
        // 2. Before allowing buzz, ask "Confidence: High/Medium/Low"
        // 3. Track calibration (did high confidence = correct?)
        // 4. Train on patterns where overconfidence leads to negs
    }
}

struct BonusConversionDrill {
    /// Maximize points from bonus opportunities

    let name = "Bonus Maximizer"
    let description = "Practice getting all three parts of bonuses"

    func execute(session: TrainingSession) {
        // 1. Present bonuses from weakest domains
        // 2. Allow unlimited time for deep study
        // 3. Track improvement in weak areas
    }
}
```

---

# PART III: SCIENCE BOWL MODULE SPECIFICATION

## 9. Science Bowl Module Overview

### 9.1 Competition Profile

| Attribute | Value |
|-----------|-------|
| **Module ID** | `com.unamentis.sciencebowl` |
| **Primary Organization** | US Department of Energy |
| **Geographic Scope** | 50 US states + territories |
| **Annual Participants** | ~18,500 students |
| **Voice Percentage** | 100% |
| **Unique Mechanics** | STEM-only, Short questions, 4-part bonus, Math computation |

### 9.2 Module Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SCIENCE BOWL MODULE                               │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │ Tossup Engine   │  │ Bonus Engine    │  │ Match Simulator │     │
│  │ - Short form    │  │ - 4-part bonus  │  │ - DOE format    │     │
│  │ - No negs       │  │ - 10 pt bonus   │  │ - Full rounds   │     │
│  │ - Recognition   │  │ - No bounce     │  │ - Category mix  │     │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘     │
│           │                    │                    │               │
│           └────────────────────┴────────────────────┘               │
│                                │                                     │
│                    ┌───────────┴───────────┐                        │
│                    │  SB-Specific Features │                        │
│                    │  - Category balance   │                        │
│                    │  - Math computation   │                        │
│                    │  - Formula recall     │                        │
│                    └───────────────────────┘                        │
│                                │                                     │
│  ┌─────────────────────────────┴─────────────────────────────┐     │
│  │                    SHARED CORE LAYER                       │     │
│  │  Question Engine │ Voice Pipeline │ Analytics │ Profiles  │     │
│  └────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘
```

### 9.3 Science Bowl Data Models

```swift
// MARK: - Science Bowl Specific Models

enum ScienceBowlCategory: String, Codable, CaseIterable {
    case biology = "BIO"
    case chemistry = "CHEM"
    case physics = "PHY"
    case mathematics = "MATH"
    case earthAndSpace = "EARTH"
    case energy = "ENERGY"
    case generalScience = "GEN"

    var fullName: String {
        switch self {
        case .biology: return "Biology"
        case .chemistry: return "Chemistry"
        case .physics: return "Physics"
        case .mathematics: return "Mathematics"
        case .earthAndSpace: return "Earth and Space Science"
        case .energy: return "Energy"
        case .generalScience: return "General Science"
        }
    }

    /// Approximate percentage in official Science Bowl
    var targetPercentage: Double {
        switch self {
        case .biology: return 0.20
        case .chemistry: return 0.20
        case .physics: return 0.20
        case .mathematics: return 0.15
        case .earthAndSpace: return 0.15
        case .energy: return 0.10
        case .generalScience: return 0.0  // Rarely used
        }
    }
}

enum ScienceBowlQuestionType: String, Codable {
    case multipleChoice = "MC"
    case shortAnswer = "SA"
}

struct ScienceBowlQuestion: CompetitionQuestion {
    let id: UUID
    let sourceQuestionId: UUID?  // Link to canonical question

    let category: ScienceBowlCategory
    let questionType: ScienceBowlQuestionType
    let questionRole: QuestionRole

    let text: String
    let answer: AnswerSpec

    // For multiple choice
    let choices: [String]?       // W, X, Y, Z options

    // For computation questions
    let requiresCalculation: Bool
    let expectedWorkTime: TimeInterval?

    let difficulty: DifficultyTier

    enum QuestionRole: String, Codable {
        case tossup
        case bonus
    }
}

struct ScienceBowlBonus: Codable {
    let id: UUID
    let sourceQuestionId: UUID?

    let category: ScienceBowlCategory
    let parts: [ScienceBowlBonusPart]  // 4 parts

    var totalPossiblePoints: Int { 10 }  // Bonus is worth 10 total
}

struct ScienceBowlBonusPart: Codable {
    let text: String
    let answer: AnswerSpec
    let questionType: ScienceBowlQuestionType
}

struct ScienceBowlMatchResult: Codable {
    let matchId: UUID
    let timestamp: Date

    // Team results
    let teamScore: Int
    let opponentScore: Int?

    // Category breakdown
    let categoryPerformance: [ScienceBowlCategory: CategoryStats]

    // Question type breakdown
    let multipleChoiceAccuracy: Double
    let shortAnswerAccuracy: Double

    // Individual player stats
    let playerStats: [UUID: SBPlayerStats]
}

struct CategoryStats: Codable {
    var questionsAttempted: Int
    var questionsCorrect: Int
    var tossupPoints: Int
    var bonusPoints: Int

    var accuracy: Double {
        questionsAttempted > 0 ? Double(questionsCorrect) / Double(questionsAttempted) : 0
    }
}

struct SBPlayerStats: Codable {
    let playerId: UUID

    var tossupsAttempted: Int
    var tossupsCorrect: Int
    var tossupPoints: Int       // 4 points each

    var bonusPartsAttempted: Int
    var bonusPartsCorrect: Int

    // Category strengths
    var categoryBreakdown: [ScienceBowlCategory: Int]
}
```

### 9.4 Science Bowl Training Modes

```swift
enum ScienceBowlTrainingMode {
    /// Category-specific drilling
    case categoryDrill(CategoryDrillConfig)

    /// Full round practice
    case roundPractice(RoundConfig)

    /// Math computation speed training
    case mathSpeed(MathSpeedConfig)

    /// Formula and constant memorization
    case formulaReview(FormulaConfig)

    /// Multiple choice strategy
    case mcStrategy(MCStrategyConfig)

    /// Match simulation
    case matchSimulation(MatchSimConfig)
}

struct CategoryDrillConfig {
    let category: ScienceBowlCategory
    let questionCount: Int
    let includeBonus: Bool
    let difficulty: DifficultyTier?
    let questionTypes: [ScienceBowlQuestionType]  // MC, SA, or both
}

struct MathSpeedConfig {
    let problemTypes: [MathProblemType]
    let targetTime: TimeInterval
    let showWorkspace: Bool     // Virtual scratch paper

    enum MathProblemType: String, Codable {
        case arithmetic
        case algebra
        case geometry
        case trigonometry
        case calculus
        case statistics
    }
}

struct FormulaConfig {
    let categories: [ScienceBowlCategory]
    let includeConstants: Bool
    let includeUnits: Bool
    let flashcardMode: Bool
}
```

### 9.5 Science Bowl Analytics

```swift
struct ScienceBowlAnalytics {
    let userId: UUID
    let periodStart: Date
    let periodEnd: Date

    // Overall Performance
    var totalQuestions: Int
    var totalCorrect: Int
    var overallAccuracy: Double

    // Category Breakdown
    var categoryPerformance: [ScienceBowlCategory: SBCategoryAnalytics]

    // Question Type Performance
    var multipleChoiceAccuracy: Double
    var shortAnswerAccuracy: Double

    // Speed Metrics
    var averageResponseTime: TimeInterval
    var responseTimeByCategory: [ScienceBowlCategory: TimeInterval]

    // Math-Specific
    var mathComputationAccuracy: Double
    var averageMathTime: TimeInterval

    // Trends
    var weeklyProgress: [WeeklySnapshot]
    var strongestCategory: ScienceBowlCategory
    var weakestCategory: ScienceBowlCategory
}

struct SBCategoryAnalytics: Codable {
    let category: ScienceBowlCategory
    var questionsAttempted: Int
    var questionsCorrect: Int
    var accuracy: Double
    var averageTime: TimeInterval
    var trend: Trend
    var masteryLevel: MasteryLevel
}
```

---

## 10. Science Bowl Training Curriculum

### 10.1 Skill Progression Framework

```
Level 1: Foundation (Weeks 1-4)
├── Establish baseline in each category
├── Identify strongest/weakest areas
├── Learn multiple choice strategy (elimination)
└── Target: 50% accuracy across categories

Level 2: Category Building (Weeks 5-12)
├── Deep dive on weakest category
├── Build formula and constant recall
├── Improve math computation speed
└── Target: 60% accuracy, no category below 45%

Level 3: Competition Ready (Weeks 13-20)
├── Balanced category training
├── Speed optimization
├── Bonus maximization
└── Target: 70% accuracy, consistent across categories

Level 4: Regional/National (Weeks 21+)
├── Hard question exposure
├── Time pressure training
├── Match simulation
└── Target: 80%+ accuracy
```

### 10.2 Science Bowl-Specific Drills

```swift
// MARK: - Science Bowl Training Drills

struct CategoryBalanceDrill {
    /// Ensure even coverage across all Science Bowl categories

    let name = "Category Equalizer"
    let description = "Practice weaker categories until all are within 10% of each other"

    func selectCategory(analytics: ScienceBowlAnalytics) -> ScienceBowlCategory {
        // Always train the weakest category
        return analytics.weakestCategory
    }
}

struct MathComputationDrill {
    /// Build speed and accuracy on calculation questions

    let name = "Mental Math"
    let description = "Practice common Science Bowl calculations without a calculator"

    let problemTypes: [String] = [
        "Unit conversions",
        "Scientific notation",
        "Percentage/ratio calculations",
        "Basic physics formulas",
        "Stoichiometry"
    ]
}

struct FormulaFlashcardDrill {
    /// Memorize key formulas and constants

    let name = "Formula Flash"
    let description = "Rapid recall of essential formulas and physical constants"

    let essentialFormulas: [String: String] = [
        "F = ma": "Newton's Second Law",
        "E = mc²": "Mass-energy equivalence",
        "PV = nRT": "Ideal Gas Law",
        "v = fλ": "Wave equation",
        // ... etc
    ]

    let essentialConstants: [String: String] = [
        "c = 3×10⁸ m/s": "Speed of light",
        "g = 9.8 m/s²": "Gravitational acceleration",
        "Avogadro's number = 6.02×10²³": "Particles per mole",
        // ... etc
    ]
}

struct MCEliminationDrill {
    /// Practice multiple choice elimination strategies

    let name = "Process of Elimination"
    let description = "Learn to identify wrong answers even when unsure of the right one"

    func train(question: ScienceBowlQuestion) {
        guard let choices = question.choices else { return }
        // 1. Present question
        // 2. Ask user to eliminate ONE wrong answer
        // 3. Ask to eliminate another
        // 4. Reveal if final two contain correct answer
        // 5. Discuss why eliminated choices were wrong
    }
}
```

---

# PART IV: CROSS-MODULE INTEGRATION

## 11. Question Sharing Implementation

### 11.1 Content Flow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    QUESTION CONTENT FLOW                         │
│                                                                  │
│  External Sources              Internal Creation                 │
│  ┌──────────────┐             ┌──────────────┐                  │
│  │ NAQT Sets    │             │ AI Generated │                  │
│  │ NSB Archive  │             │ Coach Created│                  │
│  │ KB Archives  │             │ User Contrib │                  │
│  └──────┬───────┘             └──────┬───────┘                  │
│         │                            │                          │
│         └────────────┬───────────────┘                          │
│                      ▼                                          │
│         ┌────────────────────────┐                              │
│         │   INGESTION PIPELINE   │                              │
│         │  - Parse formats       │                              │
│         │  - Extract domains     │                              │
│         │  - Rate difficulty     │                              │
│         │  - Verify accuracy     │                              │
│         └───────────┬────────────┘                              │
│                     ▼                                           │
│         ┌────────────────────────┐                              │
│         │  CANONICAL QUESTION DB │                              │
│         │  (Unified Schema)      │                              │
│         └───────────┬────────────┘                              │
│                     │                                           │
│      ┌──────────────┼──────────────┐                           │
│      ▼              ▼              ▼                           │
│ ┌─────────┐   ┌─────────┐   ┌─────────┐                        │
│ │ QB View │   │ KB View │   │ SB View │                        │
│ │Pyramidal│   │ Short   │   │ STEM    │                        │
│ │+Bonus   │   │ Written │   │ Only    │                        │
│ └─────────┘   └─────────┘   └─────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

### 11.2 Cross-Module Question Query API

```swift
class CrossModuleQuestionService {
    private let canonicalDB: CanonicalQuestionDatabase
    private let transformers: [CompetitionFormat: any QuestionTransformer]

    /// Get questions usable by multiple competitions
    func sharedQuestions(
        competitions: Set<CompetitionFormat>,
        domains: [PrimaryDomain]? = nil,
        difficulty: DifficultyTier? = nil,
        limit: Int = 50
    ) -> [CanonicalQuestion] {

        var query = canonicalDB.query()

        // Filter by domain
        if let domains = domains {
            query = query.filter { q in
                q.domains.contains { domains.contains($0.primary) }
            }
        }

        // Filter by difficulty
        if let difficulty = difficulty {
            query = query.filter { $0.difficulty.absolute <= difficultyThreshold(difficulty) }
        }

        // Filter by competition compatibility
        query = query.filter { question in
            competitions.isSubset(of: Set(question.compatibleFormats))
        }

        return Array(query.prefix(limit))
    }

    /// Convert questions between formats
    func convert(
        questions: [CanonicalQuestion],
        to format: CompetitionFormat
    ) -> [any CompetitionQuestion] {
        guard let transformer = transformers[format] else { return [] }
        return questions.compactMap { transformer.transform($0) as? any CompetitionQuestion }
    }

    /// Find the best questions that work for a specific pair of competitions
    func bestSharedQuestions(
        primary: CompetitionFormat,
        secondary: CompetitionFormat,
        count: Int
    ) -> [(CanonicalQuestion, qualityForPrimary: Double, qualityForSecondary: Double)] {

        let shared = sharedQuestions(competitions: [primary, secondary], limit: count * 3)

        return shared.map { question in
            let primaryQuality = transformers[primary]?.qualityScore(question) ?? 0
            let secondaryQuality = transformers[secondary]?.qualityScore(question) ?? 0
            return (question, primaryQuality, secondaryQuality)
        }
        .sorted { ($0.1 + $0.2) > ($1.1 + $1.2) }
        .prefix(count)
        .map { $0 }
    }
}
```

### 11.3 Question Transformation Rules

| Source | Target | Transformation Required |
|--------|--------|------------------------|
| QB → KB | Shorten pyramidal to medium/short form |
| QB → SB | Extract STEM content only, shorten |
| KB → QB | Add pyramid structure, create bonus |
| KB → SB | Filter STEM, already short format |
| SB → QB | Expand to pyramidal, add clues |
| SB → KB | Use as-is (already short) |

```swift
struct TransformationRules {

    /// Transform Quiz Bowl question to Knowledge Bowl
    static func quizBowlToKnowledgeBowl(_ qb: QuizBowlTossup) -> KnowledgeBowlQuestion {
        // Use giveaway clue or last 2-3 sentences
        let shortText = extractGiveaway(qb.text, clues: qb.clues)

        return KnowledgeBowlQuestion(
            id: UUID(),
            sourceQuestionId: qb.sourceQuestionId,
            text: shortText,
            answer: qb.answer,
            domains: qb.domains,
            suitableForWritten: true,
            suitableForOral: true
        )
    }

    /// Transform Knowledge Bowl question to Quiz Bowl
    static func knowledgeBowlToQuizBowl(_ kb: KnowledgeBowlQuestion) -> QuizBowlTossup? {
        // Need to add pyramidal structure - this requires AI assistance
        // or manual curation
        guard let expanded = expandToPyramidal(kb.text, answer: kb.answer.primary) else {
            return nil
        }

        return QuizBowlTossup(
            id: UUID(),
            sourceQuestionId: kb.sourceQuestionId,
            text: expanded.text,
            clues: expanded.clues,
            powerMarkIndex: expanded.powerMark,
            answer: kb.answer,
            domains: kb.domains,
            difficulty: .competent
        )
    }

    /// Transform Quiz Bowl STEM question to Science Bowl
    static func quizBowlToScienceBowl(_ qb: QuizBowlTossup) -> ScienceBowlQuestion? {
        // Must be STEM domain
        guard let stemDomain = qb.domains.first(where: {
            [.science, .biology, .chemistry, .physics, .earthScience, .mathematics].contains($0.primary)
        }) else {
            return nil
        }

        let category = mapToScienceBowlCategory(stemDomain.primary)
        let shortText = extractGiveaway(qb.text, clues: qb.clues)

        return ScienceBowlQuestion(
            id: UUID(),
            sourceQuestionId: qb.sourceQuestionId,
            category: category,
            questionType: .shortAnswer,
            questionRole: .tossup,
            text: shortText,
            answer: qb.answer,
            choices: nil,
            requiresCalculation: false,
            expectedWorkTime: nil,
            difficulty: qb.difficulty
        )
    }
}
```

---

## 12. Shared Training Protocol Implementation

### 12.1 Universal Training Session Manager

```swift
class UniversalTrainingManager {
    private let questionService: CrossModuleQuestionService
    private let voicePipeline: UniversalVoicePipeline
    private let analyticsEngine: CrossCompetitionAnalytics

    /// Create a training session that can draw from multiple modules
    func createCrossTrainingSession(
        user: UnifiedUserProfile,
        primaryCompetition: CompetitionFormat,
        includeFrom: Set<CompetitionFormat>,
        duration: TimeInterval
    ) -> CrossTrainingSession {

        // Get questions compatible with all specified competitions
        let questions = questionService.sharedQuestions(
            competitions: includeFrom.union([primaryCompetition]),
            limit: Int(duration / 30)  // Estimate ~30 sec per question
        )

        // Transform to primary format
        let formatted = questionService.convert(questions: questions, to: primaryCompetition)

        return CrossTrainingSession(
            user: user,
            primaryFormat: primaryCompetition,
            questions: formatted,
            trackingAcross: includeFrom.union([primaryCompetition])
        )
    }

    /// Suggest cross-training based on user's profile
    func suggestCrossTraining(user: UnifiedUserProfile) -> [CrossTrainingSuggestion] {
        var suggestions: [CrossTrainingSuggestion] = []

        // If user does KB, suggest QB for deeper knowledge
        if user.activeModules.contains(.knowledgeBowl) &&
           !user.activeModules.contains(.quizBowl) {
            suggestions.append(CrossTrainingSuggestion(
                targetCompetition: .quizBowl,
                reason: "Quiz Bowl's pyramidal questions will deepen your knowledge base",
                benefitToExisting: "Faster recognition in KB from earlier clue exposure",
                sharedContentPercent: 0.75
            ))
        }

        // If user does QB, suggest Science Bowl for STEM focus
        if user.activeModules.contains(.quizBowl) {
            let qbProfile = user.performanceProfile.competitionProfiles[.quizBowl] as? QuizBowlProfile
            if let performance = user.performanceProfile.domainMastery[.science],
               performance.score > 70 {
                suggestions.append(CrossTrainingSuggestion(
                    targetCompetition: .scienceBowl,
                    reason: "Your strong science performance would transfer well",
                    benefitToExisting: "Science Bowl practice will boost your QB science tossups",
                    sharedContentPercent: 0.40
                ))
            }
        }

        return suggestions
    }
}

struct CrossTrainingSuggestion {
    let targetCompetition: CompetitionFormat
    let reason: String
    let benefitToExisting: String
    let sharedContentPercent: Double
}
```

### 12.2 Skill Transfer Mapping

```swift
struct SkillTransferMap {

    /// Skills that transfer FROM Quiz Bowl to other competitions
    static let fromQuizBowl: [CompetitionFormat: [TransferableSkill]] = [
        .knowledgeBowl: [
            TransferableSkill(
                name: "Broad Knowledge Base",
                transferStrength: 0.9,
                notes: "QB covers same domains, just deeper"
            ),
            TransferableSkill(
                name: "Quick Recall",
                transferStrength: 0.7,
                notes: "KB has conference time, so speed less critical"
            ),
            TransferableSkill(
                name: "Bonus Collaboration",
                transferStrength: 0.8,
                notes: "QB bonus teamwork applies to KB conferring"
            )
        ],
        .scienceBowl: [
            TransferableSkill(
                name: "STEM Knowledge",
                transferStrength: 0.85,
                notes: "Direct transfer for science/math questions"
            ),
            TransferableSkill(
                name: "Buzz Timing",
                transferStrength: 0.6,
                notes: "SB requires recognition before buzzing"
            )
        ]
    ]

    /// Skills that transfer FROM Knowledge Bowl to other competitions
    static let fromKnowledgeBowl: [CompetitionFormat: [TransferableSkill]] = [
        .quizBowl: [
            TransferableSkill(
                name: "Team Communication",
                transferStrength: 0.8,
                notes: "KB conference skills help QB bonus discussion"
            ),
            TransferableSkill(
                name: "Content Knowledge",
                transferStrength: 0.7,
                notes: "KB questions cover similar material"
            ),
            TransferableSkill(
                name: "Written Round Skills",
                transferStrength: 0.3,
                notes: "QB has no written round"
            )
        ],
        .scienceBowl: [
            TransferableSkill(
                name: "STEM Knowledge",
                transferStrength: 0.5,
                notes: "KB covers STEM but not as deeply"
            ),
            TransferableSkill(
                name: "Quick Response",
                transferStrength: 0.4,
                notes: "KB conference time doesn't build speed"
            )
        ]
    ]

    /// Skills that transfer FROM Science Bowl to other competitions
    static let fromScienceBowl: [CompetitionFormat: [TransferableSkill]] = [
        .quizBowl: [
            TransferableSkill(
                name: "Science Depth",
                transferStrength: 0.95,
                notes: "SB science knowledge is elite-level for QB"
            ),
            TransferableSkill(
                name: "Math Speed",
                transferStrength: 0.6,
                notes: "QB rarely has computation questions"
            )
        ],
        .knowledgeBowl: [
            TransferableSkill(
                name: "Science Depth",
                transferStrength: 0.9,
                notes: "SB science helps KB science questions"
            ),
            TransferableSkill(
                name: "Quick Recall",
                transferStrength: 0.7,
                notes: "SB speed training helps oral rounds"
            )
        ]
    ]
}

struct TransferableSkill {
    let name: String
    let transferStrength: Double  // 0-1, how well it transfers
    let notes: String
}
```

---

## 13. Module Independence Guarantees

### 13.1 Module Isolation Principles

```swift
/// Each module MUST be able to function completely independently
protocol IndependentModule {
    /// Module can operate without other modules present
    var canOperateAlone: Bool { get }

    /// Module has its own question set (even if shared DB exists)
    var hasIndependentQuestionSource: Bool { get }

    /// Module has its own analytics (even if unified profile exists)
    var hasIndependentAnalytics: Bool { get }

    /// Module can be installed/uninstalled independently
    var isIndependentlyDeployable: Bool { get }
}

struct ModuleManifest {
    let moduleId: String
    let version: String
    let competition: CompetitionFormat

    // Dependencies
    let requiredCoreVersion: String
    let optionalModules: [String]  // Enhances experience if present

    // Capabilities
    let providesQuestions: Bool
    let consumesSharedQuestions: Bool
    let providesAnalytics: Bool
    let consumesUnifiedProfile: Bool
}

// Example manifests
let quizBowlManifest = ModuleManifest(
    moduleId: "com.unamentis.quizbowl",
    version: "1.0.0",
    competition: .quizBowl,
    requiredCoreVersion: "1.0.0",
    optionalModules: ["com.unamentis.knowledgebowl", "com.unamentis.sciencebowl"],
    providesQuestions: true,
    consumesSharedQuestions: true,
    providesAnalytics: true,
    consumesUnifiedProfile: true
)
```

### 13.2 Graceful Degradation

```swift
class ModuleCoordinator {
    private var installedModules: [String: IndependentModule] = [:]

    /// Check if cross-module features are available
    func crossModuleFeaturesAvailable(for moduleId: String) -> Bool {
        return installedModules.count > 1
    }

    /// Get available shared content for a module
    func sharedContentAvailable(for moduleId: String) -> SharedContentStatus {
        guard let module = installedModules[moduleId] else {
            return .moduleNotFound
        }

        if installedModules.count == 1 {
            return .soloMode(
                message: "Running in standalone mode. Install other modules to access shared content."
            )
        }

        let otherModules = installedModules.keys.filter { $0 != moduleId }
        return .sharedModeActive(connectedModules: Array(otherModules))
    }
}

enum SharedContentStatus {
    case moduleNotFound
    case soloMode(message: String)
    case sharedModeActive(connectedModules: [String])
}
```

---

## 14. Implementation Roadmap

### Phase 1: Core Infrastructure (Weeks 1-4)
- [ ] Implement CanonicalQuestion schema
- [ ] Build QuestionTransformer protocol and base implementations
- [ ] Create UniversalVoicePipeline
- [ ] Implement UniversalPerformanceProfile

### Phase 2: Quiz Bowl Module (Weeks 5-10)
- [ ] Implement QuizBowlTossup and QuizBowlBonus models
- [ ] Build pyramidal question training modes
- [ ] Implement QB-specific analytics
- [ ] Create QB training curriculum

### Phase 3: Science Bowl Module (Weeks 11-16)
- [ ] Implement ScienceBowlQuestion models
- [ ] Build category-based training system
- [ ] Implement math computation training
- [ ] Create SB training curriculum

### Phase 4: Cross-Module Integration (Weeks 17-20)
- [ ] Implement CrossModuleQuestionService
- [ ] Build question transformation pipeline
- [ ] Create cross-training suggestions
- [ ] Implement skill transfer tracking

### Phase 5: Testing & Optimization (Weeks 21-24)
- [ ] Module independence testing
- [ ] Cross-module integration testing
- [ ] Performance optimization
- [ ] User acceptance testing

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-17 | UnaMentis Team | Initial modular architecture design |

---

*This document defines the technical architecture for building independent yet interconnected academic competition modules. It should be read alongside:*
- *[KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md](KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md) - Complete Knowledge Bowl specification*
- *[US_ACADEMIC_COMPETITION_LANDSCAPE.md](US_ACADEMIC_COMPETITION_LANDSCAPE.md) - Competition landscape analysis*
