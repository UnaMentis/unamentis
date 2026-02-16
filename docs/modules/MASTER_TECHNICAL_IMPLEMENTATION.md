# Master Technical Implementation Guide

## Academic Competition Training Platform

**Version:** 1.0
**Last Updated:** 2026-01-17
**Status:** Implementation Planning

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Architecture Overview](#2-system-architecture-overview)
3. [Shared Core Layer](#3-shared-core-layer)
4. [Data Exchange Protocols](#4-data-exchange-protocols)
5. [Module Specifications](#5-module-specifications)
6. [Infrastructure Requirements](#6-infrastructure-requirements)
7. [Build Order & Dependencies](#7-build-order--dependencies)
8. [Prioritized Implementation Roadmap](#8-prioritized-implementation-roadmap)
9. [Testing Strategy](#9-testing-strategy)
10. [Deployment & Distribution](#10-deployment--distribution)

---

## 1. Executive Summary

### 1.1 Project Vision

Build a unified academic competition training platform that supports multiple competition formats (Knowledge Bowl, Quiz Bowl, Science Bowl) through independent yet interconnected modules sharing a common foundation.

### 1.2 Core Principles

| Principle | Description |
|-----------|-------------|
| **Module Independence** | Each module functions completely standalone |
| **Data Sovereignty** | User owns all proficiency data; persists across module lifecycles |
| **Shared Foundation** | Common question database, voice pipeline, and analytics engine |
| **Graceful Enhancement** | Multiple modules enhance each other when present |
| **Voice-First** | All competitions are 50%+ voice-based; voice interface is primary |

### 1.3 Platform Scope

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ACADEMIC COMPETITION TRAINING PLATFORM                    │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         COMPETITION MODULES                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │ Knowledge   │  │ Quiz Bowl   │  │ Science     │  │ Future      │  │  │
│  │  │ Bowl        │  │             │  │ Bowl        │  │ Modules     │  │  │
│  │  │ ~15K users  │  │ ~50K users  │  │ ~18K users  │  │ ...         │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                          SHARED CORE LAYER                             │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │  │
│  │  │ Question │ │ Voice    │ │Analytics │ │Proficiency│ │ Training │   │  │
│  │  │ Engine   │ │ Pipeline │ │ Engine   │ │ System   │ │ Library  │   │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        PLATFORM FOUNDATION                             │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │  │
│  │  │ Local    │ │ Speech   │ │ User     │ │ Settings │ │ Export   │   │  │
│  │  │ Storage  │ │ Services │ │ Identity │ │ Manager  │ │ System   │   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 Related Documents

| Document | Purpose |
|----------|---------|
| [KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md](KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md) | Complete KB specification |
| [ACADEMIC_COMPETITION_MODULAR_ARCHITECTURE.md](ACADEMIC_COMPETITION_MODULAR_ARCHITECTURE.md) | Module architecture patterns |
| [UNIFIED_PROFICIENCY_SYSTEM.md](UNIFIED_PROFICIENCY_SYSTEM.md) | Cross-module proficiency tracking |
| [US_ACADEMIC_COMPETITION_LANDSCAPE.md](US_ACADEMIC_COMPETITION_LANDSCAPE.md) | Competition landscape research |
| KNOWLEDGE_BOWL_MODULE_SPEC.md | KB module technical spec (planned) |
| QUIZ_BOWL_MODULE_SPEC.md | QB module technical spec (planned) |
| SCIENCE_BOWL_MODULE_SPEC.md | SB module technical spec (planned) |

---

## 2. System Architecture Overview

### 2.1 Layered Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ LAYER 5: USER INTERFACE                                                      │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │  Competition Module UIs  │  Unified Dashboard  │  Settings  │  Export   │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────────────┤
│ LAYER 4: COMPETITION MODULES                                                 │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │  Knowledge Bowl  │  Quiz Bowl  │  Science Bowl  │  [Extensible...]      │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────────────┤
│ LAYER 3: SHARED SERVICES                                                     │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │  Question Engine  │  Voice Pipeline  │  Analytics  │  Training Library  │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────────────┤
│ LAYER 2: DATA LAYER                                                          │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │  Unified Proficiency Store  │  Canonical Question DB  │  Session Store  │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────────────┤
│ LAYER 1: PLATFORM FOUNDATION                                                 │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │  iOS/watchOS APIs  │  Speech Framework  │  Core Data  │  File System    │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Module Communication

```swift
// MARK: - Module Communication Architecture

/// All inter-module communication goes through defined protocols
/// Modules NEVER communicate directly with each other

protocol ModuleCommunicationHub {
    /// Register a module to receive events
    func register(module: CompetitionModule)

    /// Unregister a module
    func unregister(moduleId: String)

    /// Post an event to the hub (other modules may listen)
    func post(event: ModuleEvent)

    /// Subscribe to specific event types
    func subscribe(to eventType: ModuleEventType, handler: @escaping (ModuleEvent) -> Void)
}

enum ModuleEventType {
    case questionCompleted       // A question was answered
    case sessionCompleted        // A training session ended
    case proficiencyUpdated      // User proficiency changed
    case moduleInstalled         // New module available
    case moduleUninstalled       // Module removed
    case crossTrainingAvailable  // Shared content opportunity
}

struct ModuleEvent {
    let id: UUID
    let type: ModuleEventType
    let sourceModule: String
    let timestamp: Date
    let payload: [String: Any]
}
```

### 2.3 Data Flow Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                           DATA FLOW OVERVIEW                                │
│                                                                             │
│  ┌─────────────┐                                    ┌─────────────┐        │
│  │   User      │                                    │   Module    │        │
│  │   Action    │                                    │   UI        │        │
│  └──────┬──────┘                                    └──────▲──────┘        │
│         │                                                  │               │
│         ▼                                                  │               │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────┴────────────┐ │
│  │   Voice     │────▶│   Module    │────▶│   Results + Analytics        │ │
│  │   Input     │     │   Logic     │     │                              │ │
│  └─────────────┘     └──────┬──────┘     └──────────────────────────────┘ │
│                             │                                              │
│         ┌───────────────────┼───────────────────┐                         │
│         ▼                   ▼                   ▼                         │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                  │
│  │  Question   │     │ Proficiency │     │  Analytics  │                  │
│  │  Engine     │     │   Store     │     │   Engine    │                  │
│  └─────────────┘     └─────────────┘     └─────────────┘                  │
│         │                   │                   │                         │
│         └───────────────────┴───────────────────┘                         │
│                             │                                              │
│                             ▼                                              │
│                      ┌─────────────┐                                       │
│                      │   Local     │                                       │
│                      │   Storage   │                                       │
│                      └─────────────┘                                       │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Shared Core Layer

### 3.1 Component Overview

| Component | Responsibility | Dependencies |
|-----------|---------------|--------------|
| **Question Engine** | Store, retrieve, transform questions across formats | Local Storage |
| **Voice Pipeline** | Speech recognition, synthesis, buzz detection | iOS Speech Framework |
| **Analytics Engine** | Performance tracking, trends, insights | Proficiency Store |
| **Proficiency System** | Cross-module skill tracking, transfer recognition | Local Storage |
| **Training Library** | Shared training protocols, drills | Question Engine |

### 3.2 Question Engine

```swift
// MARK: - Question Engine Core

/// Central question management service
/// All modules request questions through this engine

class QuestionEngine {
    private let canonicalStore: CanonicalQuestionStore
    private let transformerRegistry: TransformerRegistry
    private let indexer: QuestionIndexer

    // ═══════════════════════════════════════════════════════════════════════
    // QUERY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// Get questions for a specific competition
    func questions(
        for competition: CompetitionFormat,
        matching filters: QuestionFilters,
        count: Int
    ) -> [any CompetitionQuestion] {
        // 1. Query canonical store
        let canonicals = canonicalStore.query(filters, limit: count * 2)

        // 2. Transform to competition format
        guard let transformer = transformerRegistry.transformer(for: competition) else {
            return []
        }

        // 3. Filter and return
        return canonicals
            .compactMap { transformer.transform($0) as? any CompetitionQuestion }
            .prefix(count)
            .map { $0 }
    }

    /// Get questions usable by multiple competitions
    func crossCompatibleQuestions(
        competitions: Set<CompetitionFormat>,
        filters: QuestionFilters
    ) -> [CanonicalQuestion] {
        return canonicalStore.query(filters).filter { question in
            competitions.isSubset(of: Set(question.compatibleFormats))
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INGESTION INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// Ingest a question from any competition format
    func ingest<T: CompetitionQuestion>(
        _ question: T,
        source: CompetitionFormat
    ) -> CanonicalQuestion {
        // Convert to canonical form
        let canonical = canonicalize(question, source: source)

        // Index for search
        indexer.index(canonical)

        // Store
        canonicalStore.save(canonical)

        // Notify interested modules
        NotificationCenter.default.post(
            name: .newQuestionAvailable,
            object: canonical
        )

        return canonical
    }
}

struct QuestionFilters {
    var domains: [PrimaryDomain]?
    var difficulty: ClosedRange<DifficultyTier>?
    var gradeLevels: [GradeLevel]?
    var excludeRecentlyUsed: Bool = true
    var recentUsageWindow: TimeInterval = 86400 * 7  // 1 week
    var requireVoiceSafe: Bool = false  // Filter out questions with complex formulas
}
```

### 3.3 Voice Pipeline

```swift
// MARK: - Universal Voice Pipeline

/// Shared voice services for all competition modules

class UniversalVoicePipeline {
    private let speechRecognizer: SFSpeechRecognizer
    private let speechSynthesizer: AVSpeechSynthesizer
    private let buzzDetector: BuzzDetector
    private let audioEngine: AVAudioEngine

    private var currentConfig: VoicePipelineConfig

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════

    struct VoicePipelineConfig {
        let buzzMode: BuzzMode
        let answerTimeout: TimeInterval
        let speakingRate: Float
        let allowInterruption: Bool
        let conferenceTime: TimeInterval?  // nil = no conference period

        enum BuzzMode {
            case individual      // Quiz Bowl - one person buzzes
            case team           // Knowledge Bowl - team buzzer
            case recognition    // Science Bowl - must be recognized first
        }
    }

    /// Configure pipeline for specific competition
    func configure(for competition: CompetitionFormat) {
        switch competition {
        case .knowledgeBowl:
            currentConfig = VoicePipelineConfig(
                buzzMode: .team,
                answerTimeout: 5.0,
                speakingRate: 1.0,
                allowInterruption: true,
                conferenceTime: 15.0
            )
        case .quizBowl:
            currentConfig = VoicePipelineConfig(
                buzzMode: .individual,
                answerTimeout: 5.0,
                speakingRate: 1.2,
                allowInterruption: true,
                conferenceTime: nil
            )
        case .scienceBowl:
            currentConfig = VoicePipelineConfig(
                buzzMode: .recognition,
                answerTimeout: 5.0,
                speakingRate: 1.1,
                allowInterruption: false,
                conferenceTime: nil
            )
        default:
            currentConfig = .default
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SPEECH OUTPUT
    // ═══════════════════════════════════════════════════════════════════════

    /// Speak text aloud
    func speak(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentConfig.speakingRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        speechSynthesizer.speak(utterance)

        // Wait for completion
        await withCheckedContinuation { continuation in
            // ... completion handling
        }
    }

    /// Speak with interruption capability
    func speakInterruptible(_ text: String, onInterrupt: @escaping () -> Void) async {
        guard currentConfig.allowInterruption else {
            await speak(text)
            return
        }

        // Start listening for buzz while speaking
        buzzDetector.startDetection()

        let speakTask = Task {
            await speak(text)
        }

        // Check for buzz
        if let buzz = await buzzDetector.waitForBuzz(timeout: 30) {
            speakTask.cancel()
            speechSynthesizer.stopSpeaking(at: .immediate)
            onInterrupt()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SPEECH INPUT
    // ═══════════════════════════════════════════════════════════════════════

    /// Listen for answer
    func listenForAnswer(timeout: TimeInterval) async -> VoiceResult {
        let recognitionTask = speechRecognizer.recognitionTask(/* ... */)

        // Apply timeout
        let result = await withTimeout(timeout) {
            // ... recognition logic
        }

        return VoiceResult(
            transcript: result.bestTranscription.formattedString,
            confidence: result.confidence,
            alternatives: result.transcriptions.dropFirst().map(\.formattedString),
            duration: result.duration
        )
    }

    /// Start conference period (KB specific)
    func startConferencePeriod() async -> ConferenceResult {
        guard let conferenceTime = currentConfig.conferenceTime else {
            return ConferenceResult(skipped: true)
        }

        // Announce conference start
        await speak("Conference")

        // Wait for conference time or early submission
        // ...
    }
}

struct VoiceResult {
    let transcript: String
    let confidence: Double
    let alternatives: [String]
    let duration: TimeInterval
}
```

### 3.4 Analytics Engine

```swift
// MARK: - Cross-Competition Analytics Engine

/// Unified analytics across all modules

class AnalyticsEngine {
    private let proficiencyStore: ProficiencyStore
    private let sessionStore: SessionStore

    // ═══════════════════════════════════════════════════════════════════════
    // PERFORMANCE TRACKING
    // ═══════════════════════════════════════════════════════════════════════

    /// Record a question attempt (from any module)
    func recordAttempt(_ attempt: QuestionAttempt) {
        // Update proficiency store
        proficiencyStore.recordAttempt(attempt)

        // Update session metrics
        sessionStore.addAttempt(attempt)

        // Check for achievements
        checkAchievements(after: attempt)

        // Update trends
        updateTrends(for: attempt.domain)
    }

    /// Get cross-competition insights
    func getCrossCompetitionInsights(userId: UUID) -> [CrossCompetitionInsight] {
        let profile = proficiencyStore.getProfile()
        var insights: [CrossCompetitionInsight] = []

        // Find transferable strengths
        for (domain, mastery) in profile.domainMastery where mastery.score > 70 {
            let relevantComps = domain.relevantCompetitions
            if relevantComps.count > 1 {
                insights.append(CrossCompetitionInsight(
                    type: .transferableStrength,
                    domain: domain,
                    message: "Your \(domain) strength (score: \(Int(mastery.score))) transfers well to \(relevantComps.map(\.rawValue).joined(separator: ", "))"
                ))
            }
        }

        // Find shared weaknesses
        let weakDomains = profile.domainMastery.filter { $0.value.score < 40 && $0.value.questionsAttempted > 10 }
        if !weakDomains.isEmpty {
            insights.append(CrossCompetitionInsight(
                type: .sharedWeakness,
                domain: weakDomains.first!.key,
                message: "Focus on \(weakDomains.map(\.key.rawValue).joined(separator: ", ")) - weak across all your competitions"
            ))
        }

        return insights
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TREND ANALYSIS
    // ═══════════════════════════════════════════════════════════════════════

    func getTrends(for domain: StandardDomain, period: DateInterval) -> DomainTrend {
        let snapshots = proficiencyStore.getSnapshots(for: domain, in: period)

        guard snapshots.count >= 2 else {
            return DomainTrend(direction: .insufficientData, magnitude: 0)
        }

        // Calculate trend
        let firstHalf = snapshots.prefix(snapshots.count / 2)
        let secondHalf = snapshots.suffix(snapshots.count / 2)

        let firstAvg = firstHalf.map(\.masteryScore).reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.map(\.masteryScore).reduce(0, +) / Double(secondHalf.count)

        let change = secondAvg - firstAvg

        return DomainTrend(
            direction: change > 2 ? .improving : (change < -2 ? .declining : .stable),
            magnitude: abs(change)
        )
    }
}

struct CrossCompetitionInsight {
    let type: InsightType
    let domain: StandardDomain
    let message: String

    enum InsightType {
        case transferableStrength
        case sharedWeakness
        case recommendedCrossTraining
        case balanceRecommendation
    }
}
```

### 3.5 Training Protocol Library

```swift
// MARK: - Shared Training Protocols

/// Training protocols usable by multiple modules

protocol TrainingProtocol: Identifiable {
    var id: UUID { get }
    var name: String { get }
    var description: String { get }
    var applicableCompetitions: Set<CompetitionFormat> { get }
    var requiredCapabilities: Set<TrainingCapability> { get }

    func createSession(config: TrainingSessionConfig) -> TrainingSession
}

enum TrainingCapability {
    case voiceInput
    case voiceOutput
    case buzzerSimulation
    case timerSystem
    case multiPlayer
    case writtenInterface
}

// MARK: - Universal Protocols

struct SpacedRepetitionProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Spaced Repetition"
    let description = "Review questions at optimal intervals for long-term retention"
    let applicableCompetitions: Set<CompetitionFormat> = [.quizBowl, .knowledgeBowl, .scienceBowl]
    let requiredCapabilities: Set<TrainingCapability> = [.voiceOutput]

    func createSession(config: TrainingSessionConfig) -> TrainingSession {
        // SM-2 algorithm implementation
        return SpacedRepetitionSession(config: config)
    }
}

struct DomainDrillProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Domain Deep Dive"
    let description = "Focused practice on a single knowledge domain"
    let applicableCompetitions: Set<CompetitionFormat> = [.quizBowl, .knowledgeBowl, .scienceBowl]
    let requiredCapabilities: Set<TrainingCapability> = [.voiceInput, .voiceOutput]

    let targetDomain: StandardDomain

    func createSession(config: TrainingSessionConfig) -> TrainingSession {
        return DomainDrillSession(domain: targetDomain, config: config)
    }
}

struct SpeedTrainingProtocol: TrainingProtocol {
    let id = UUID()
    let name = "Speed Training"
    let description = "Progressively faster question delivery to improve recall speed"
    let applicableCompetitions: Set<CompetitionFormat> = [.quizBowl, .scienceBowl]  // Not KB - has conference
    let requiredCapabilities: Set<TrainingCapability> = [.voiceInput, .voiceOutput, .timerSystem]

    func createSession(config: TrainingSessionConfig) -> TrainingSession {
        return SpeedDrillSession(config: config)
    }
}

// MARK: - Training Protocol Registry

class TrainingProtocolRegistry {
    static let shared = TrainingProtocolRegistry()

    private var protocols: [UUID: any TrainingProtocol] = [:]

    init() {
        registerBuiltInProtocols()
    }

    private func registerBuiltInProtocols() {
        register(SpacedRepetitionProtocol())
        register(DomainDrillProtocol(targetDomain: .literature))
        register(SpeedTrainingProtocol())
        // ... more protocols
    }

    func register(_ protocol: any TrainingProtocol) {
        protocols[`protocol`.id] = `protocol`
    }

    func protocols(for competition: CompetitionFormat) -> [any TrainingProtocol] {
        return protocols.values.filter { $0.applicableCompetitions.contains(competition) }
    }
}
```

---

## 4. Data Exchange Protocols

### 4.1 Inter-Module Data Exchange

```swift
// MARK: - Data Exchange Protocol

/// Defines how modules share data with each other

protocol DataExchangeProtocol {
    /// Export data in shareable format
    func exportData(scope: ExportScope) -> ExportableData

    /// Import data from another module or external source
    func importData(_ data: ExportableData) throws

    /// Validate data before import
    func validateImport(_ data: ExportableData) -> ValidationResult
}

enum ExportScope {
    case proficiencyOnly          // Just skill levels
    case questionsOnly            // Just question history
    case full                     // Everything
    case forModule(String)        // Filtered for specific module compatibility
}

struct ExportableData: Codable {
    let version: String
    let exportedAt: Date
    let sourceModule: String
    let scope: String

    // Proficiency data
    let proficiencyProfile: UnifiedProficiencyProfile?

    // Question data
    let questions: [CanonicalQuestion]?

    // Session history
    let sessionHistory: [SessionSummary]?

    // Metadata
    let metadata: [String: AnyCodable]
}

struct ValidationResult {
    let isValid: Bool
    let errors: [ValidationError]
    let warnings: [ValidationWarning]

    struct ValidationError {
        let field: String
        let message: String
    }

    struct ValidationWarning {
        let field: String
        let message: String
    }
}
```

### 4.2 Question Transformation Protocol

```swift
// MARK: - Question Transformation

/// Standardized question transformation between formats

protocol QuestionTransformer {
    associatedtype Output: CompetitionQuestion

    /// Transform canonical question to competition-specific format
    func transform(_ canonical: CanonicalQuestion) -> Output?

    /// Check if question is compatible with this competition
    func isCompatible(_ canonical: CanonicalQuestion) -> Bool

    /// Get quality score for transformation (0-1)
    func qualityScore(_ canonical: CanonicalQuestion) -> Double

    /// Reverse transform (competition-specific to canonical)
    func canonicalize(_ question: Output) -> CanonicalQuestion
}

// MARK: - Transformation Matrix

/// Documents how questions transform between competitions

struct TransformationMatrix {

    /// QB → KB: Shorten pyramidal to medium/short form
    static func quizBowlToKnowledgeBowl(_ qb: QuizBowlTossup) -> KnowledgeBowlQuestion {
        let shortText = extractGiveawayClues(qb.text, clues: qb.clues)
        return KnowledgeBowlQuestion(
            id: UUID(),
            sourceQuestionId: qb.id,
            text: shortText,
            answer: qb.answer,
            domains: qb.domains
        )
    }

    /// KB → QB: Expand to pyramidal (requires AI or manual curation)
    static func knowledgeBowlToQuizBowl(_ kb: KnowledgeBowlQuestion) -> QuizBowlTossup? {
        // This transformation requires additional clue generation
        // May return nil if expansion not possible
        guard let expanded = tryExpandToPyramidal(kb) else { return nil }
        return expanded
    }

    /// QB STEM → SB: Extract science content only
    static func quizBowlToScienceBowl(_ qb: QuizBowlTossup) -> ScienceBowlQuestion? {
        let stemDomains: Set<PrimaryDomain> = [.biology, .chemistry, .physics, .mathematics, .earthScience, .astronomy]

        guard qb.domains.contains(where: { stemDomains.contains($0.primary) }) else {
            return nil  // Not a STEM question
        }

        return ScienceBowlQuestion(
            id: UUID(),
            sourceQuestionId: qb.id,
            text: extractGiveawayClues(qb.text, clues: qb.clues),
            answer: qb.answer,
            category: mapToSBCategory(qb.domains)
        )
    }

    /// SB → KB: Direct use (already short form)
    static func scienceBowlToKnowledgeBowl(_ sb: ScienceBowlQuestion) -> KnowledgeBowlQuestion {
        return KnowledgeBowlQuestion(
            id: UUID(),
            sourceQuestionId: sb.id,
            text: sb.text,
            answer: sb.answer,
            domains: [DomainTag(primary: mapSBCategoryToDomain(sb.category))]
        )
    }
}
```

### 4.3 Proficiency Transfer Protocol

```swift
// MARK: - Proficiency Transfer

/// How skill levels transfer between competitions

struct ProficiencyTransferService {
    private let weightMatrix: TransferWeightMatrix

    /// Calculate proficiency transfer when user starts new competition
    func calculateTransfer(
        from sourceCompetitions: Set<CompetitionFormat>,
        to targetCompetition: CompetitionFormat,
        profile: UnifiedProficiencyProfile
    ) -> TransferredProficiency {

        var domainTransfers: [StandardDomain: Double] = [:]

        for (domain, mastery) in profile.domainMastery {
            var bestTransfer = 0.0

            for source in sourceCompetitions {
                let weight = weightMatrix.weight(
                    from: source,
                    to: targetCompetition,
                    domain: domain
                )
                let transferredScore = mastery.score * weight
                bestTransfer = max(bestTransfer, transferredScore)
            }

            domainTransfers[domain] = bestTransfer
        }

        // Calculate overall transferred proficiency
        let relevantDomains = targetCompetition.relevantDomains
        let relevantScores = domainTransfers.filter { relevantDomains.contains($0.key) }
        let averageScore = relevantScores.values.reduce(0, +) / Double(max(1, relevantScores.count))

        return TransferredProficiency(
            overallScore: averageScore,
            domainScores: domainTransfers,
            suggestedStartingLevel: determineLevelFromScore(averageScore),
            confidence: calculateConfidence(profile, domains: relevantDomains)
        )
    }
}

struct TransferWeightMatrix {
    /// Weight matrix: [SourceCompetition][TargetCompetition][Domain] → TransferWeight
    private let weights: [CompetitionFormat: [CompetitionFormat: [StandardDomain: Double]]]

    func weight(from source: CompetitionFormat, to target: CompetitionFormat, domain: StandardDomain) -> Double {
        return weights[source]?[target]?[domain] ?? 0.5  // Default 50% transfer
    }

    static let standard = TransferWeightMatrix(weights: [
        .knowledgeBowl: [
            .quizBowl: [
                .literature: 0.85,
                .history: 0.85,
                .geography: 0.85,
                .biology: 0.80,
                .chemistry: 0.80,
                .physics: 0.80,
                .mathematics: 0.75,
                .fineArts: 0.80
            ],
            .scienceBowl: [
                .biology: 0.70,
                .chemistry: 0.70,
                .physics: 0.70,
                .mathematics: 0.65,
                .earthScience: 0.65
            ]
        ],
        .quizBowl: [
            .knowledgeBowl: [
                .literature: 0.90,
                .history: 0.90,
                .geography: 0.90,
                .biology: 0.85,
                .chemistry: 0.85,
                .physics: 0.85,
                .mathematics: 0.80,
                .fineArts: 0.85
            ],
            .scienceBowl: [
                .biology: 0.75,
                .chemistry: 0.75,
                .physics: 0.75,
                .mathematics: 0.70,
                .earthScience: 0.70
            ]
        ],
        .scienceBowl: [
            .quizBowl: [
                .biology: 0.95,
                .chemistry: 0.95,
                .physics: 0.95,
                .mathematics: 0.80,
                .earthScience: 0.90
            ],
            .knowledgeBowl: [
                .biology: 0.90,
                .chemistry: 0.90,
                .physics: 0.90,
                .mathematics: 0.75,
                .earthScience: 0.85
            ]
        ]
    ])
}
```

---

## 5. Module Specifications

### 5.1 Module Structure

Each competition module follows a standard structure:

```
ModuleName/
├── Sources/
│   ├── Core/
│   │   ├── ModuleManifest.swift       # Module metadata and dependencies
│   │   ├── ModuleCoordinator.swift    # Module lifecycle management
│   │   └── ModuleConfig.swift         # Competition-specific configuration
│   │
│   ├── Models/
│   │   ├── Questions/                 # Competition-specific question models
│   │   ├── Sessions/                  # Match/practice session models
│   │   └── Analytics/                 # Competition-specific metrics
│   │
│   ├── Services/
│   │   ├── QuestionService.swift      # Question retrieval/transformation
│   │   ├── SessionManager.swift       # Training session management
│   │   └── AnalyticsService.swift     # Competition-specific analytics
│   │
│   ├── Training/
│   │   ├── Protocols/                 # Competition-specific training drills
│   │   └── Curriculum/                # Skill progression framework
│   │
│   └── UI/
│       ├── Views/                     # SwiftUI views
│       └── ViewModels/                # View state management
│
├── Resources/
│   ├── Questions/                     # Bundled question content
│   └── Assets/                        # Images, sounds, etc.
│
└── Tests/
    ├── UnitTests/
    └── IntegrationTests/
```

### 5.2 Module Manifest

```swift
// MARK: - Module Manifest

/// Every module must declare its manifest

struct ModuleManifest: Codable {
    let moduleId: String              // e.g., "com.unamentis.knowledgebowl"
    let displayName: String           // e.g., "Knowledge Bowl"
    let version: String               // Semantic versioning
    let competition: CompetitionFormat

    // Dependencies
    let minimumCoreVersion: String
    let optionalModules: [String]     // Modules that enhance this one

    // Capabilities
    let capabilities: ModuleCapabilities

    // Content
    let bundledQuestionCount: Int
    let supportedDomains: [StandardDomain]

    // Regional Support
    let supportedRegions: [RegionalConfig]
}

struct ModuleCapabilities: Codable {
    let providesQuestions: Bool
    let consumesSharedQuestions: Bool
    let providesAnalytics: Bool
    let consumesUnifiedProfile: Bool
    let supportsVoiceInterface: Bool
    let supportsWatchOS: Bool
}

// Example: Knowledge Bowl Module Manifest
let knowledgeBowlManifest = ModuleManifest(
    moduleId: "com.unamentis.knowledgebowl",
    displayName: "Knowledge Bowl",
    version: "1.0.0",
    competition: .knowledgeBowl,
    minimumCoreVersion: "1.0.0",
    optionalModules: ["com.unamentis.quizbowl", "com.unamentis.sciencebowl"],
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

### 5.3 Module Links

| Module | Spec Document | Status |
|--------|---------------|--------|
| Knowledge Bowl | [KNOWLEDGE_BOWL_MODULE_SPEC.md](KNOWLEDGE_BOWL_MODULE_SPEC.md) | Planned |
| Quiz Bowl | [QUIZ_BOWL_MODULE_SPEC.md](QUIZ_BOWL_MODULE_SPEC.md) | Planned |
| Science Bowl | [SCIENCE_BOWL_MODULE_SPEC.md](SCIENCE_BOWL_MODULE_SPEC.md) | Planned |

---

## 6. Infrastructure Requirements

### 6.1 iOS/watchOS Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| iOS Version | 16.0 | 17.0+ |
| watchOS Version | 9.0 | 10.0+ |
| Swift Version | 5.9 | 5.10+ |
| Xcode Version | 15.0 | 15.2+ |

### 6.2 Framework Dependencies

```swift
// MARK: - Core Dependencies

import Foundation
import SwiftUI
import Combine

// Speech Services
import Speech          // SFSpeechRecognizer
import AVFoundation   // AVSpeechSynthesizer

// Data Persistence
import CoreData       // Optional: For complex queries
import SwiftData      // Primary: Modern persistence (iOS 17+)

// Networking (future: cloud sync)
import Network        // Connectivity monitoring

// Watch Connectivity
import WatchConnectivity
```

### 6.3 Storage Requirements

```swift
// MARK: - Storage Estimates

struct StorageRequirements {
    /// Core app (no modules)
    static let coreApp = StorageEstimate(
        initialSize: 5_000_000,    // 5 MB
        growthPerMonth: 100_000    // 100 KB/month
    )

    /// Per-module estimates
    static let perModule: [CompetitionFormat: StorageEstimate] = [
        .knowledgeBowl: StorageEstimate(
            initialSize: 15_000_000,   // 15 MB (5000 questions)
            growthPerMonth: 500_000    // 500 KB/month (session data)
        ),
        .quizBowl: StorageEstimate(
            initialSize: 25_000_000,   // 25 MB (pyramidal questions larger)
            growthPerMonth: 750_000
        ),
        .scienceBowl: StorageEstimate(
            initialSize: 12_000_000,   // 12 MB
            growthPerMonth: 400_000
        )
    ]

    /// Proficiency store (shared)
    static let proficiencyStore = StorageEstimate(
        initialSize: 100_000,      // 100 KB
        growthPerMonth: 50_000     // 50 KB/month
    )
}

struct StorageEstimate {
    let initialSize: Int      // Bytes
    let growthPerMonth: Int   // Bytes per month of active use
}
```

### 6.4 Performance Requirements

| Metric | Target | Maximum |
|--------|--------|---------|
| App Launch | < 1s | 2s |
| Question Retrieval | < 100ms | 500ms |
| Speech Recognition Start | < 500ms | 1s |
| Voice Synthesis Start | < 200ms | 500ms |
| Proficiency Update | < 50ms | 200ms |
| Memory Usage (active) | < 150MB | 300MB |
| Memory Usage (background) | < 50MB | 100MB |

---

## 7. Build Order & Dependencies

### 7.1 Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        BUILD DEPENDENCY GRAPH                                │
│                                                                              │
│  Level 0: Platform Foundation                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ iOS/watchOS APIs │ Speech Framework │ Storage APIs │ File System        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    ▲                                         │
│                                    │                                         │
│  Level 1: Core Data Layer                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ CanonicalQuestionSchema │ UnifiedProficiencyProfile │ StorageManager    ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    ▲                                         │
│                                    │                                         │
│  Level 2: Core Services                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ QuestionEngine │ VoicePipeline │ ProficiencyStore │ AnalyticsEngine     ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    ▲                                         │
│                                    │                                         │
│  Level 3: Shared Protocols                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ TrainingProtocolLibrary │ TransformationEngine │ ModuleCoordinator      ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    ▲                                         │
│                                    │                                         │
│  Level 4: Competition Modules (Independent, Parallel Development)            │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                    │
│  │ Knowledge     │  │ Quiz Bowl     │  │ Science       │                    │
│  │ Bowl Module   │  │ Module        │  │ Bowl Module   │                    │
│  └───────────────┘  └───────────────┘  └───────────────┘                    │
│                                    ▲                                         │
│                                    │                                         │
│  Level 5: Cross-Module Integration                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ CrossTrainingService │ UnifiedDashboard │ DataExportService             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Build Order

| Phase | Component | Depends On | Blocks |
|-------|-----------|------------|--------|
| 1.1 | CanonicalQuestionSchema | - | QuestionEngine |
| 1.2 | UnifiedProficiencyProfile | - | ProficiencyStore |
| 1.3 | StorageManager | iOS APIs | All Level 2 |
| 2.1 | ProficiencyStore | 1.2, 1.3 | Analytics, Modules |
| 2.2 | QuestionEngine | 1.1, 1.3 | Modules |
| 2.3 | VoicePipeline | iOS Speech | Modules |
| 2.4 | AnalyticsEngine | 2.1 | Modules |
| 3.1 | TrainingProtocolLibrary | 2.2, 2.3 | Modules |
| 3.2 | TransformationEngine | 2.2 | Cross-Module |
| 3.3 | ModuleCoordinator | 2.1-2.4 | Modules |
| 4.1 | Knowledge Bowl Module | Level 3 | - |
| 4.2 | Quiz Bowl Module | Level 3 | - |
| 4.3 | Science Bowl Module | Level 3 | - |
| 5.1 | CrossTrainingService | 4.1-4.3 | - |
| 5.2 | UnifiedDashboard | 4.1-4.3, 5.1 | - |

---

## 8. Prioritized Implementation Roadmap

### 8.1 Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     IMPLEMENTATION TIMELINE OVERVIEW                         │
│                                                                              │
│  Phase 1: Foundation          Phase 2: KB Module      Phase 3: Expansion    │
│  ┌─────────────────────┐      ┌─────────────────┐    ┌─────────────────┐   │
│  │ Core Infrastructure │      │ Knowledge Bowl  │    │ QB & SB Modules │   │
│  │ Weeks 1-6           │      │ Weeks 7-14      │    │ Weeks 15-26     │   │
│  └─────────────────────┘      └─────────────────┘    └─────────────────┘   │
│          │                           │                       │              │
│          │                           │                       │              │
│          ▼                           ▼                       ▼              │
│  ┌─────────────────────┐      ┌─────────────────┐    ┌─────────────────┐   │
│  │ - Data schemas      │      │ - KB models     │    │ - QB module     │   │
│  │ - Storage layer     │      │ - KB training   │    │ - SB module     │   │
│  │ - Voice pipeline    │      │ - KB analytics  │    │ - Cross-training│   │
│  │ - Proficiency store │      │ - KB UI/UX      │    │ - Unified dash  │   │
│  └─────────────────────┘      └─────────────────┘    └─────────────────┘   │
│                                                                              │
│  Phase 4: Polish & Launch                                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ Testing, Optimization, App Store Launch (Weeks 27-32)               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Phase 1: Foundation (Weeks 1-6)

**Goal:** Build the shared infrastructure that all modules depend on.

#### Week 1-2: Data Layer

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| Define CanonicalQuestion schema | P0 | Medium | `CanonicalQuestion.swift` |
| Define UnifiedProficiencyProfile | P0 | Medium | `UnifiedProficiencyProfile.swift` |
| Implement StorageManager | P0 | High | `StorageManager.swift` |
| Create StandardDomain taxonomy | P0 | Low | `StandardDomain.swift` |
| Unit tests for data models | P0 | Medium | Test coverage |

#### Week 3-4: Core Services

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| Implement ProficiencyStore | P0 | High | `ProficiencyStore.swift` |
| Implement QuestionEngine basic | P0 | High | `QuestionEngine.swift` |
| Implement VoicePipeline basic | P0 | High | `VoicePipeline.swift` |
| Integration tests | P0 | Medium | Test coverage |

#### Week 5-6: Shared Protocols

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| Define ModuleProtocol | P0 | Medium | `ModuleProtocol.swift` |
| Define TrainingProtocol | P0 | Medium | `TrainingProtocol.swift` |
| Implement ModuleCoordinator | P0 | High | `ModuleCoordinator.swift` |
| Create module manifest schema | P0 | Low | `ModuleManifest.swift` |
| End-to-end integration tests | P0 | High | Test coverage |

**Phase 1 Exit Criteria:**
- [ ] All data schemas validated
- [ ] Storage read/write working
- [ ] Voice input/output functional
- [ ] Proficiency tracking working
- [ ] Module protocol defined and tested

### 8.3 Phase 2: Knowledge Bowl Module (Weeks 7-14)

**Goal:** Complete the Knowledge Bowl module as the reference implementation.

#### Week 7-8: KB Core Models

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| KnowledgeBowlQuestion model | P0 | Medium | `KBQuestion.swift` |
| KB session models | P0 | Medium | `KBSession.swift` |
| KB regional configs | P0 | High | `KBRegionalConfig.swift` |
| KB transformer | P0 | Medium | `KBTransformer.swift` |

#### Week 9-10: KB Training System

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| Written round training | P0 | High | Written training mode |
| Oral round training | P0 | High | Oral training mode |
| Conference training (team) | P1 | Medium | Conference mode |
| Regional rule variants | P0 | Medium | Rule engine |

#### Week 11-12: KB Analytics

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| KB-specific metrics | P0 | Medium | `KBAnalytics.swift` |
| Domain breakdown | P0 | Medium | Analytics views |
| Progress tracking | P0 | Medium | Progress UI |
| Regional comparison | P1 | Low | Comparison views |

#### Week 13-14: KB UI/UX

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| Main KB dashboard | P0 | High | Dashboard view |
| Training session UI | P0 | High | Session views |
| Analytics visualization | P0 | Medium | Charts/graphs |
| watchOS companion | P1 | High | Watch app |
| User testing | P0 | Medium | Feedback integration |

**Phase 2 Exit Criteria:**
- [ ] Complete KB training modes
- [ ] All regional variants supported
- [ ] Analytics functional
- [ ] iOS app polished
- [ ] User testing complete

### 8.4 Phase 3: Module Expansion (Weeks 15-26)

**Goal:** Add Quiz Bowl and Science Bowl modules.

#### Weeks 15-18: Quiz Bowl Module

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| QB question models (pyramidal) | P0 | High | `QBQuestion.swift` |
| QB tossup training | P0 | High | Tossup mode |
| QB bonus training | P0 | Medium | Bonus mode |
| Pyramidal parsing training | P0 | High | Clue recognition |
| Neg avoidance training | P1 | Medium | Risk management |
| QB analytics (celerity, etc.) | P0 | Medium | `QBAnalytics.swift` |
| QB UI/UX | P0 | High | QB interface |

#### Weeks 19-22: Science Bowl Module

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| SB question models | P0 | Medium | `SBQuestion.swift` |
| SB category training | P0 | High | Category drills |
| Math computation training | P0 | High | Math speed mode |
| Formula recall training | P1 | Medium | Flashcard system |
| MC elimination training | P1 | Medium | Strategy training |
| SB analytics | P0 | Medium | `SBAnalytics.swift` |
| SB UI/UX | P0 | High | SB interface |

#### Weeks 23-26: Cross-Module Integration

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| CrossTrainingService | P0 | High | Cross-training engine |
| Question sharing | P0 | High | Shared question pool |
| Proficiency transfer | P0 | High | Transfer recognition |
| Unified Dashboard | P1 | Medium | Master dashboard |
| Cross-module insights | P1 | Medium | Insight generation |

**Phase 3 Exit Criteria:**
- [ ] All three modules functional
- [ ] Cross-module features working
- [ ] Proficiency transfers correctly
- [ ] Unified dashboard complete

### 8.5 Phase 4: Polish & Launch (Weeks 27-32)

#### Weeks 27-28: Testing

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| Unit test completion | P0 | Medium | >90% coverage |
| Integration testing | P0 | High | Integration suite |
| Performance testing | P0 | Medium | Performance report |
| Accessibility testing | P0 | Medium | A11y compliance |
| Beta testing program | P0 | Medium | Beta feedback |

#### Weeks 29-30: Optimization

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| Performance optimization | P0 | High | Optimized builds |
| Memory optimization | P0 | Medium | Reduced footprint |
| Battery optimization | P0 | Medium | Power efficiency |
| Voice recognition tuning | P0 | High | Improved accuracy |

#### Weeks 31-32: Launch

| Task | Priority | Complexity | Deliverable |
|------|----------|------------|-------------|
| App Store assets | P0 | Medium | Screenshots, etc. |
| Documentation | P0 | Medium | User guides |
| Marketing materials | P1 | Low | Launch materials |
| App Store submission | P0 | Low | Published app |
| Launch monitoring | P0 | Medium | Monitoring setup |

### 8.6 Priority Matrix Summary

| Priority | Definition | Examples |
|----------|------------|----------|
| **P0** | Launch blocker | Core functionality, data integrity, voice pipeline |
| **P1** | Important | Enhanced features, secondary UI, analytics |
| **P2** | Nice to have | Advanced analytics, additional drills |
| **P3** | Future | Cloud sync, social features |

---

## 9. Testing Strategy

### 9.1 Testing Pyramid

```
                    ┌───────────────┐
                    │   E2E Tests   │  < 5%
                    │  (User Flows) │
                    └───────┬───────┘
                            │
                   ┌────────┴────────┐
                   │ Integration     │  ~20%
                   │ Tests           │
                   │ (Module + Core) │
                   └────────┬────────┘
                            │
          ┌─────────────────┴─────────────────┐
          │           Unit Tests              │  ~75%
          │ (Models, Services, Transformers)  │
          └───────────────────────────────────┘
```

### 9.2 Test Categories

```swift
// MARK: - Test Categories

/// Unit Tests - Fast, isolated, comprehensive
class QuestionEngineTests: XCTestCase {
    func testQuestionTransformation_QBtoKB() { }
    func testQuestionFiltering_byDomain() { }
    func testQuestionFiltering_byDifficulty() { }
}

/// Integration Tests - Module + Core interaction
class KBModuleIntegrationTests: XCTestCase {
    func testKBSession_savesToProficiencyStore() { }
    func testKBQuestions_loadFromQuestionEngine() { }
    func testKBVoice_usesUniversalPipeline() { }
}

/// E2E Tests - Full user flows
class TrainingFlowE2ETests: XCTestCase {
    func testCompleteTrainingSession_startToFinish() { }
    func testCrossModuleTraining_transfersCorrectly() { }
}
```

### 9.3 Voice Testing

```swift
// MARK: - Voice Testing Strategy

/// Voice tests require special handling due to async nature

class VoicePipelineTests: XCTestCase {

    /// Test with mock audio input
    func testSpeechRecognition_withMockedInput() async {
        let mockAudio = loadTestAudio("correct_answer.m4a")
        let result = await voicePipeline.recognize(audio: mockAudio)
        XCTAssertEqual(result.transcript, "Abraham Lincoln")
    }

    /// Test speech synthesis output
    func testSpeechSynthesis_producesOutput() async {
        let expectation = expectation(description: "Speech completed")
        voicePipeline.speak("Test question") {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5)
    }
}
```

---

## 10. Deployment & Distribution

### 10.1 App Store Structure

UnaMentis is fully open source. All modules are free with no in-app purchases.

| App | Bundle ID | Cost |
|-----|-----------|------|
| Main App (all modules) | `com.unamentis.academictrainer` | Free |

### 10.2 Update Strategy

```swift
// MARK: - Module Update Protocol

struct ModuleUpdatePolicy {
    /// Modules can update independently
    let independentModuleUpdates = true

    /// Core updates may require module updates
    let coreUpdateRequiresModuleCheck = true

    /// Data migration handled automatically
    let automaticDataMigration = true

    /// Rollback supported for failed updates
    let rollbackSupported = true
}
```

### 10.3 Data Backup & Export

```swift
// MARK: - Export System

class DataExportService {

    /// Export user's complete data
    func exportAllData() throws -> URL {
        let profile = proficiencyStore.getProfile()
        let sessions = sessionStore.getAllSessions()

        let export = CompleteExport(
            proficiency: profile,
            sessions: sessions,
            exportedAt: Date(),
            appVersion: Bundle.main.version
        )

        let data = try JSONEncoder().encode(export)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("academic_trainer_export.json")

        try data.write(to: url)
        return url
    }

    /// Import previously exported data
    func importData(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let export = try JSONDecoder().decode(CompleteExport.self, from: data)

        // Merge with existing data (don't overwrite)
        try proficiencyStore.merge(export.proficiency)
        try sessionStore.importSessions(export.sessions)
    }
}
```

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **Canonical Question** | Competition-agnostic question format used for storage |
| **Competition Format** | Specific competition type (KB, QB, SB) |
| **Domain Mastery** | User's proficiency level in a knowledge domain |
| **Module** | Independently deployable competition-specific package |
| **Proficiency Transfer** | Recognition of skills from one competition in another |
| **Pyramidal Question** | Question structure with clues ordered hard-to-easy |
| **Transformer** | Component that converts questions between formats |

---

## Appendix B: Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-17 | Development Team | Initial master implementation guide |

---

## Appendix C: Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Cloud sync for multi-device? | Deferred | Phase 2 post-launch |
| Social/leaderboard features? | Under discussion | TBD |
| Coach/team management features? | Planned | Future module |
| AI question generation? | Research | Evaluation needed |

---

*This document serves as the authoritative technical guide for the Academic Competition Training Platform. All module specifications should align with the patterns and protocols defined here.*
