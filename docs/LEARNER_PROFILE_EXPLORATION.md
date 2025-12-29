# Learner Profile System: Exploration & Implementation Proposal

**Version:** 1.0.0
**Date:** 2025-12-29
**Status:** Exploration / Proposal
**Author:** AI-Assisted Design

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Analysis](#current-state-analysis)
3. [Design Philosophy](#design-philosophy)
4. [Scientific Foundations](#scientific-foundations)
5. [Profile Architecture](#profile-architecture)
6. [Implementation Proposal](#implementation-proposal)
7. [Data Schemas](#data-schemas)
8. [Integration Points](#integration-points)
9. [Phased Rollout](#phased-rollout)
10. [Open Questions](#open-questions)

---

## Executive Summary

### The Opportunity

UnaMentis is uniquely positioned to implement a learner profile system that is:
- **Voice-native:** Built for 90-minute conversations, not forms
- **Evidence-based:** Uses actual performance data, not self-reported "styles"
- **Continuous:** Updated throughout every session, not captured once
- **Scientifically sound:** Avoids the "learning styles" trap

### Current Gap

The existing UnaMentis architecture tracks:
- Per-topic mastery and progress (`TopicProgress`)
- Session transcripts and metrics
- User preferences (audio, TTS, LLM settings)

What's missing:
- **Learner-level attributes** that persist across topics
- **Strategy effectiveness signals** (what actually works for this learner)
- **Contextual constraints** (environment, time, attention patterns)
- **Micro-experiment infrastructure** to validate profile inferences

### Core Insight

> "Profile by conversation + validate by micro-experiments"

The profile isn't a form the user fills out. It's a living model that:
1. Emerges from natural conversation patterns
2. Gets validated through embedded micro-experiments
3. Updates continuously based on observed outcomes

---

## Current State Analysis

### Existing Data Collection Points

| System | Location | What It Tracks |
|--------|----------|----------------|
| `TelemetryEngine` | `Core/Telemetry/TelemetryEngine.swift:1-615` | Latency, costs, turns, interruptions, thermal |
| `TopicProgress` | `Core/Persistence/ManagedObjects/TopicProgress+CoreDataClass.swift` | Time spent, quiz scores per topic |
| `SessionManager` | `Core/Session/SessionManager.swift:1-1375` | Conversation history, turn states, user utterances |
| `CurriculumEngine` | `Core/Curriculum/CurriculumEngine.swift` | Topic ordering, mastery, depth levels |
| `SessionSettingsModel` | `UI/Session/SessionView.swift:777-940` | Audio, VAD, TTS, LLM preferences |

### Key Architectural Insights

1. **Session-Centric Design:** Learning happens within bounded `SessionManager` instances
2. **Transcript-Driven Tutoring:** Rich transcripts with checkpoints, misconceptions, examples (UMLCF format)
3. **Intent Classification:** Already planned for routing interactions (Categories A-D)
4. **Modular Services:** Protocol-based STT/TTS/LLM allow provider swapping

### What's Not Tracked Today

- Why the user asked for clarification
- Whether examples or theory worked better
- Attention/fatigue patterns over 90 minutes
- Time-of-day learning effectiveness
- Delayed recall performance
- Strategy signals (does spaced retrieval help this user?)

---

## Design Philosophy

### Avoid the Learning Styles Trap

The "meshing hypothesis" (matching instruction to visual/auditory/kinesthetic style) has poor empirical support. UnaMentis should NOT:

- Claim to "identify your learning style"
- Match instruction modality to self-reported preferences
- Use VARK or similar typologies as the engine

**Instead, treat "styles" as preference vocabulary:**

| Concept | What We Track | What We DON'T Claim |
|---------|---------------|---------------------|
| Preferences | "User prefers examples before theory" | "User IS an example learner" |
| Constraints | "User loses focus after 20 minutes" | "User has low attention capacity" |
| Strategies | "Retrieval practice improved recall" | "User requires retrieval practice" |

### Voice-Native Data Collection

The profile should be built from:
1. **Conversational signals:** Questions asked, clarifications requested, confusion expressed
2. **Behavioral patterns:** Interruption frequency, silence duration, pacing requests
3. **Performance outcomes:** Quiz results, delayed recall, explanation quality
4. **Micro-experiments:** Small A/B tests embedded in normal tutoring

### Continuous Over Static

The profile is a **state machine**, not a snapshot:

```
┌─────────────────────────────────────────────────────────────┐
│  PROFILE STATE MACHINE                                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐  │
│  │   Initial   │──────│  Emerging   │──────│  Validated  │  │
│  │  (onboard)  │      │ (observed)  │      │ (tested)    │  │
│  └─────────────┘      └─────────────┘      └─────────────┘  │
│                                                     │        │
│                                                     ▼        │
│                                              ┌─────────────┐ │
│                                              │  Updating   │ │
│                                              │ (continuous)│ │
│                                              └─────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Scientific Foundations

### What Actually Works (Learning Science)

| Principle | Evidence Level | How UnaMentis Can Use It |
|-----------|----------------|--------------------------|
| **Retrieval Practice** | Strong | Embed recall questions, track effectiveness |
| **Spaced Repetition** | Strong | Schedule reviews, track compliance/outcomes |
| **Elaborative Interrogation** | Moderate | "Why does this work?" questions |
| **Interleaving** | Moderate | Mix topics, measure transfer |
| **Dual Coding** | Moderate | Combine voice + visual assets |
| **Self-Explanation** | Moderate | Ask learner to explain back |

### Individual Differences That Do Matter

| Factor | Evidence | Profile Relevance |
|--------|----------|-------------------|
| **Prior Knowledge** | Strong | Adjust explanation depth |
| **Working Memory Capacity** | Strong | Chunk size, repetition needs |
| **Goal Orientation** | Moderate | Mastery vs. performance focus |
| **Self-Regulation Skills** | Moderate | How much scaffolding needed |
| **Domain Interest** | Moderate | Engagement strategies |
| **Anxiety/Confidence** | Moderate | Pacing, encouragement style |

### ACCLIP Mapping (1EdTech Accessibility)

For a voice-first app, accessibility preferences are learning preferences:

| ACCLIP Category | UnaMentis Mapping |
|-----------------|-------------------|
| **display** | Screen on/off during audio, visual asset frequency |
| **control** | Hands-free mode, tap-to-pause, voice commands |
| **content** | Transcript availability, summary frequency, example density |

---

## Profile Architecture

### Core Profile Schema (v1)

```swift
/// Learner profile built through conversation and validated by micro-experiments
public struct LearnerProfile: Codable, Sendable {
    // MARK: - Identity
    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Goals & Context
    public var goals: LearningGoals
    public var constraints: LearningConstraints
    public var accessContext: AccessibilityContext  // ACCLIP-inspired

    // MARK: - Observed Preferences (not "styles")
    public var preferences: ContentPreferences

    // MARK: - Strategy Effectiveness (evidence-based)
    public var strategies: StrategySignals

    // MARK: - Performance Evidence
    public var evidence: PerformanceEvidence

    // MARK: - Profile Maturity
    public var maturity: ProfileMaturity
}
```

### Supporting Types

```swift
public struct LearningGoals: Codable, Sendable {
    public var primaryTopic: String?
    public var targetLevel: ContentDepth
    public var deadline: Date?
    public var successDefinition: String?  // "pass exam", "understand basics", etc.
    public var priorExposure: PriorExposure
}

public enum PriorExposure: String, Codable, Sendable {
    case none           // "Never heard of it"
    case awareness      // "I know it exists"
    case basicUnderstanding  // "I know the basics"
    case practicalExperience // "I've used it"
    case expertise      // "I could teach it"
}

public struct LearningConstraints: Codable, Sendable {
    public var typicalSessionLength: TimeInterval?  // Observed, not asked
    public var preferredTimeOfDay: TimeOfDay?
    public var environmentNotes: String?            // "often in noisy room"
    public var attentionPatterns: AttentionPattern?
    public var fatigueThreshold: TimeInterval?      // When engagement drops
}

public struct AttentionPattern: Codable, Sendable {
    public var optimalChunkDuration: TimeInterval   // Before needing a break/shift
    public var needsFrequentRecaps: Bool
    public var prefersShorterTurns: Bool
    public var toleratesLongExplanations: Bool
    public var confidence: Float                    // 0.0-1.0
}

public struct AccessibilityContext: Codable, Sendable {
    // Display preferences
    public var showVisualAssetsWhileSpeaking: Bool
    public var preferLargerText: Bool
    public var preferTranscriptOnScreen: Bool

    // Control preferences
    public var handsFreeMode: Bool
    public var tapToPause: Bool
    public var voiceCommandsEnabled: Bool

    // Content preferences
    public var preferConciseSummaries: Bool
    public var needsTranscriptExport: Bool
    public var preferSlowerPace: Bool
}

public struct ContentPreferences: Codable, Sendable {
    // Explanation style
    public var explanationApproach: ExplanationApproach
    public var exampleDensity: Density              // few, moderate, many
    public var abstractionTolerance: Float          // 0.0 = needs concrete, 1.0 = enjoys theory

    // Interaction style
    public var checkpointFrequency: Density
    public var prefersSocraticQuestions: Bool
    public var toleratesBeingChallenged: Bool

    // Confidence levels (how sure are we about these?)
    public var confidence: PreferenceConfidence
}

public enum ExplanationApproach: String, Codable, Sendable {
    case examplesFirst      // "Show me an example, then explain"
    case theoryFirst        // "Explain the concept, then show examples"
    case interleaved        // "Mix theory and examples"
    case adaptive           // "No strong preference detected"
}

public enum Density: String, Codable, Sendable {
    case minimal, moderate, high
}

public struct PreferenceConfidence: Codable, Sendable {
    public var explanationApproach: Float       // 0.0-1.0
    public var exampleDensity: Float
    public var abstractionTolerance: Float
    public var overallConfidence: Float {
        (explanationApproach + exampleDensity + abstractionTolerance) / 3.0
    }
}

public struct StrategySignals: Codable, Sendable {
    // What learning strategies seem to work for this learner?
    public var retrievalPracticeEffectiveness: EffectivenessSignal?
    public var spacingCompliance: Float?        // Do they come back for reviews?
    public var selfExplanationQuality: Float?   // When asked to explain, how well do they do?
    public var elaborationTendency: Float?      // Do they naturally connect ideas?
    public var planningHabitStrength: Float?    // Do they set goals, track progress?
}

public struct EffectivenessSignal: Codable, Sendable {
    public var effectiveness: Float             // -1.0 to 1.0 (harmful to helpful)
    public var sampleSize: Int                  // How many data points
    public var lastUpdated: Date
    public var confidence: Float {
        // Confidence increases with sample size, plateaus around 10+
        min(Float(sampleSize) / 10.0, 1.0)
    }
}

public struct PerformanceEvidence: Codable, Sendable {
    // Micro-quiz results
    public var immediateRecallAccuracy: Float?      // Right after explanation
    public var delayedRecallAccuracy: Float?        // Next session or later
    public var recallDecayRate: Float?              // How fast they forget

    // Engagement metrics
    public var averageSessionLength: TimeInterval
    public var sessionCompletionRate: Float
    public var voluntaryReturnRate: Float           // Come back without prompting

    // Self-reported (lower weight)
    public var selfReportedEffort: Float?           // "How hard was that?"
    public var selfReportedConfidence: Float?       // "How well do you understand?"

    // Sample sizes
    public var totalSessions: Int
    public var totalQuizAttempts: Int
    public var totalDelayedRecallTests: Int
}

public struct ProfileMaturity: Codable, Sendable {
    public var stage: MaturityStage
    public var sessionsCompleted: Int
    public var lastMicroExperimentDate: Date?
    public var pendingExperiments: [MicroExperiment]

    public var isReadyForAdaptation: Bool {
        stage == .validated || stage == .updating
    }
}

public enum MaturityStage: String, Codable, Sendable {
    case initial            // Just created, no data
    case emerging           // Some observations, low confidence
    case validated          // Micro-experiments confirm preferences
    case updating           // Continuously refined
}
```

---

## Implementation Proposal

### Phase 1: Soft Onboarding Arc (Minutes 0-20)

The first session includes a "guided interview" that doesn't feel like an interview:

```
┌─────────────────────────────────────────────────────────────┐
│  SOFT ONBOARDING FLOW (First Session)                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PHASE 1 (0-5 min): GROUNDING                               │
│  ├── "What brings you to [topic] today?"                    │
│  ├── "What would success look like for you?"                │
│  ├── "Any deadline or timeline in mind?"                    │
│  └── "How much have you encountered this before?"           │
│      ↓ (extract: goals, deadline, prior_exposure)           │
│                                                              │
│  PHASE 2 (5-12 min): LEARNING STORIES                       │
│  ├── "Tell me about something you learned quickly."         │
│  │   ↓ (listen for: examples, hands-on, reading, video)    │
│  └── "Tell me about something that didn't stick."           │
│      ↓ (listen for: too abstract, too fast, no practice)   │
│      ↓ (extract: initial preferences, NOT types)            │
│                                                              │
│  PHASE 3 (12-20 min): TWO MICRO-EXPERIMENTS                 │
│  ├── Teach same concept two ways:                           │
│  │   A: Worked example → user explains back                 │
│  │   B: Abstract explanation → user summarizes              │
│  └── 2-3 questions later to measure retention               │
│      ↓ (extract: which approach led to better recall?)      │
│                                                              │
│  PHASE 4 (rest of session): PASSIVE PROFILING               │
│  └── Normal tutoring with signal extraction                 │
│                                                              │
│  PHASE 5 (end): 60-SECOND RECAP                             │
│  ├── "Here's what seemed to work today..."                  │
│  ├── "Next time, I'll try..."                               │
│  └── "One thing I'd like to experiment with..."             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Phase 2: Passive Signal Extraction

During normal tutoring, extract signals from:

```swift
public struct SessionSignals: Codable, Sendable {
    // Extracted from conversation patterns
    var exampleRequestCount: Int            // "Can you give an example?"
    var rephraseRequestCount: Int           // "Can you say that differently?"
    var clarificationRequestCount: Int      // "What do you mean by...?"
    var tangentAttempts: Int                // Off-topic questions
    var silencesAfterComplexContent: Int    // Long pauses = confusion?

    // Extracted from behavioral patterns
    var averageTurnDuration: TimeInterval   // How long before they interrupt
    var interruptionFrequency: Float        // Impatience or engagement?
    var pacingChangeRequests: Int           // "Slow down" / "Speed up"
    var timeToFirstResponse: TimeInterval   // After AI stops, how fast do they respond?

    // Extracted from checkpoint responses
    var checkpointPassRate: Float
    var needsRepeatExplanation: Float       // % of checkpoints needing retry
    var selfConfidenceCalibration: Float    // self-report vs. actual performance

    // Attention indicators
    var engagementDropoffTime: TimeInterval? // When did responses become shorter?
    var responseQualityOverTime: [Float]    // Does quality degrade?
}
```

### Phase 3: Micro-Experiment Engine

Small A/B tests embedded in normal tutoring:

```swift
public struct MicroExperiment: Codable, Sendable, Identifiable {
    public let id: UUID
    public var hypothesis: ExperimentHypothesis
    public var status: ExperimentStatus
    public var conditionA: ExperimentCondition
    public var conditionB: ExperimentCondition
    public var outcomeMetric: OutcomeMetric
    public var result: ExperimentResult?
}

public enum ExperimentHypothesis: String, Codable, Sendable {
    case examplesFirstBetter        // Does example→theory beat theory→example?
    case frequentRecapsBetter       // Do more recaps improve retention?
    case retrievalPracticeHelps     // Do quiz questions improve recall?
    case shorterChunksBetter        // Do shorter explanations work better?
    case socraticQuestionsHelp      // Does being asked questions help?
}

public struct ExperimentCondition: Codable, Sendable {
    public var description: String
    public var appliedAt: Date?
    public var outcomeScore: Float?     // 0.0-1.0
}

public enum OutcomeMetric: String, Codable, Sendable {
    case immediateRecall            // Quiz right after
    case delayedRecall              // Quiz next session
    case selfReportedClarity        // "Did that make sense?"
    case engagementMaintained       // Did they stay engaged?
    case requestedMoreDetail        // Did they ask to go deeper?
}

public struct ExperimentResult: Codable, Sendable {
    public var winningCondition: String     // "A" or "B"
    public var effectSize: Float            // How much better
    public var statisticalConfidence: Float // P-value equivalent
    public var conclusion: String           // "Examples first worked 30% better for this learner"
}
```

### Phase 4: Profile Update Loop

```
┌─────────────────────────────────────────────────────────────┐
│  PROFILE UPDATE LOOP (Runs async, off critical path)        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  SessionManager.conversationHistory                         │
│           │                                                  │
│           ▼                                                  │
│  ┌─────────────────────────────────────────┐                │
│  │ ProfileSignalExtractor                  │                │
│  │ - Parse utterances for signals          │                │
│  │ - Detect attention patterns             │                │
│  │ - Score checkpoint performance          │                │
│  └─────────────────────────────────────────┘                │
│           │                                                  │
│           ▼                                                  │
│  ┌─────────────────────────────────────────┐                │
│  │ ProfileInferenceEngine                  │                │
│  │ - Update preference probabilities       │                │
│  │ - Adjust confidence scores              │                │
│  │ - Trigger micro-experiments when unsure │                │
│  └─────────────────────────────────────────┘                │
│           │                                                  │
│           ▼                                                  │
│  ┌─────────────────────────────────────────┐                │
│  │ LearnerProfile (Core Data)              │                │
│  │ - Persist updated profile               │                │
│  │ - Available for next session            │                │
│  └─────────────────────────────────────────┘                │
│           │                                                  │
│           ▼                                                  │
│  ┌─────────────────────────────────────────┐                │
│  │ CurriculumEngine.adaptContent()         │                │
│  │ - Adjust explanation style              │                │
│  │ - Modify checkpoint frequency           │                │
│  │ - Select appropriate depth              │                │
│  └─────────────────────────────────────────┘                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Schemas

### Core Data Model Extensions

Add to existing Core Data schema:

```
LearnerProfile (new entity)
├── id: UUID
├── createdAt: Date
├── updatedAt: Date
├── goalsJSON: String              // Encoded LearningGoals
├── constraintsJSON: String        // Encoded LearningConstraints
├── accessContextJSON: String      // Encoded AccessibilityContext
├── preferencesJSON: String        // Encoded ContentPreferences
├── strategiesJSON: String         // Encoded StrategySignals
├── evidenceJSON: String           // Encoded PerformanceEvidence
├── maturityJSON: String           // Encoded ProfileMaturity
└── sessions: [Session]            // Relationship

SessionSignals (new entity)
├── id: UUID
├── sessionId: UUID
├── extractedAt: Date
├── signalsJSON: String            // Encoded SessionSignals
└── session: Session               // Relationship

MicroExperiment (new entity)
├── id: UUID
├── profileId: UUID
├── createdAt: Date
├── completedAt: Date?
├── hypothesisRaw: String
├── conditionAJSON: String
├── conditionBJSON: String
├── outcomeMetricRaw: String
├── resultJSON: String?
└── profile: LearnerProfile        // Relationship
```

### UMLCF Extensions for Profile-Aware Content

Extend `tutoringConfig` in UMLCF:

```json
{
  "tutoringConfig": {
    "contentDepth": "intermediate",
    "adaptiveDepth": true,
    "interactionMode": "socratic",

    "profileAdaptations": {
      "explanationVariants": {
        "examplesFirst": {
          "segmentOrder": ["example", "explanation", "checkpoint"]
        },
        "theoryFirst": {
          "segmentOrder": ["explanation", "example", "checkpoint"]
        }
      },
      "checkpointFrequencyOptions": {
        "minimal": 1,
        "moderate": 2,
        "high": 4
      },
      "chunkSizeVariants": {
        "short": "PT2M",
        "medium": "PT5M",
        "long": "PT10M"
      }
    }
  }
}
```

---

## Integration Points

### 1. SessionManager Integration

```swift
// SessionManager.swift additions

actor SessionManager {
    // MARK: - Profile Integration

    private var profileSignalCollector: ProfileSignalCollector?

    func startSession() async throws {
        // ... existing code ...

        // Initialize profile signal collection
        if let profile = await loadLearnerProfile() {
            profileSignalCollector = ProfileSignalCollector(profile: profile)

            // Apply profile-based adaptations
            await curriculumEngine?.applyProfileAdaptations(profile)
        }
    }

    func processUserUtterance(_ transcript: String) async throws {
        // ... existing code ...

        // Extract signals for profile
        await profileSignalCollector?.processUtterance(
            transcript,
            context: currentSessionContext
        )
    }

    func stopSession() async throws {
        // ... existing code ...

        // Finalize profile updates
        if let signals = await profileSignalCollector?.finalize() {
            await updateLearnerProfile(with: signals)
        }
    }
}
```

### 2. CurriculumEngine Integration

```swift
// CurriculumEngine.swift additions

actor CurriculumEngine {
    func applyProfileAdaptations(_ profile: LearnerProfile) async {
        // Adjust content based on profile

        // Example: If profile shows examples-first preference
        if profile.preferences.explanationApproach == .examplesFirst {
            currentTutoringConfig.segmentOrdering = .examplesFirst
        }

        // Example: If profile shows short attention chunks
        if let attention = profile.constraints.attentionPatterns,
           attention.optimalChunkDuration < 180 {  // < 3 min
            currentTutoringConfig.checkpointFrequency = .high
            currentTutoringConfig.maxSegmentLength = .short
        }

        // Example: If retrieval practice is effective for this learner
        if let retrieval = profile.strategies.retrievalPracticeEffectiveness,
           retrieval.effectiveness > 0.3 && retrieval.confidence > 0.5 {
            currentTutoringConfig.embedRetrievalQuestions = true
        }
    }
}
```

### 3. TelemetryEngine Extensions

```swift
// TelemetryEngine.swift additions

public enum TelemetryEvent: Sendable {
    // ... existing events ...

    // Profile events
    case profileSignalExtracted(type: String, value: Any)
    case microExperimentStarted(experimentId: UUID, hypothesis: String)
    case microExperimentCompleted(experimentId: UUID, result: String)
    case profileUpdated(field: String, oldValue: Any?, newValue: Any)
    case profileAdaptationApplied(adaptation: String)
}
```

### 4. Prompt Engineering for Profile-Aware Responses

```swift
func buildSystemPrompt(with profile: LearnerProfile?) -> String {
    var prompt = baseSystemPrompt

    if let profile = profile, profile.maturity.isReadyForAdaptation {
        prompt += """

        ## Learner Profile Adaptations

        This learner has the following observed preferences:
        - Explanation approach: \(profile.preferences.explanationApproach.rawValue)
        - Example density: \(profile.preferences.exampleDensity.rawValue)
        - Abstraction tolerance: \(formatAbstraction(profile.preferences.abstractionTolerance))

        Constraints to be aware of:
        - Optimal chunk duration: \(formatDuration(profile.constraints.attentionPatterns?.optimalChunkDuration))
        - Needs frequent recaps: \(profile.constraints.attentionPatterns?.needsFrequentRecaps ?? false)

        What works for this learner:
        \(formatStrategySignals(profile.strategies))

        Adapt your tutoring style accordingly, but remain flexible. These are observations, not rules.
        """
    }

    return prompt
}
```

---

## Phased Rollout

### Phase 1: Signal Collection (No Adaptation)

**Duration:** 2-4 weeks
**Goal:** Collect data without changing behavior

- [ ] Add `SessionSignals` entity to Core Data
- [ ] Implement `ProfileSignalCollector`
- [ ] Extract signals from conversation patterns
- [ ] Log to telemetry for analysis
- [ ] **No profile-based adaptations yet**

### Phase 2: Soft Onboarding Flow

**Duration:** 2-3 weeks
**Goal:** Implement the first-session guided interview

- [ ] Add `LearnerProfile` entity to Core Data
- [ ] Implement soft onboarding conversation flow
- [ ] Extract goals, constraints from onboarding
- [ ] Store initial (low-confidence) preferences
- [ ] End-of-session recap

### Phase 3: Micro-Experiment Engine

**Duration:** 3-4 weeks
**Goal:** Validate preferences with evidence

- [ ] Add `MicroExperiment` entity to Core Data
- [ ] Implement experiment scheduling
- [ ] Implement A/B content delivery
- [ ] Implement outcome measurement
- [ ] Update profile based on results

### Phase 4: Adaptive Tutoring

**Duration:** 4-6 weeks
**Goal:** Use profile to personalize content

- [ ] Implement `CurriculumEngine.applyProfileAdaptations()`
- [ ] Add profile context to LLM prompts
- [ ] Implement UMLCF `profileAdaptations` in transcript rendering
- [ ] Track adaptation effectiveness
- [ ] Continuous profile refinement

### Phase 5: Profile Export & Standards

**Duration:** 2-3 weeks
**Goal:** Interoperability

- [ ] Implement ACCLIP-compatible export
- [ ] Add xAPI event logging for profile changes
- [ ] Profile import from other systems (optional)

---

## Open Questions

### 1. Consent & Transparency

How do we communicate profile building to users?

**Options:**
- A: Explicit opt-in with detailed explanation
- B: Default on with easy opt-out and transparency
- C: Show profile insights in settings ("What UnaMentis learned about you")

**Recommendation:** B + C. Default on with full transparency. Show the profile in settings.

### 2. Profile Portability

Should profiles be exportable/importable?

**Options:**
- A: Local only, never leaves device
- B: Exportable in standard format (ACCLIP JSON)
- C: Syncable to server for cross-device use

**Recommendation:** A for v1, B for v2. Privacy-first.

### 3. Multi-Topic Profiles

One profile per learner, or one per learner-topic pair?

**Options:**
- A: Single global profile
- B: Profile per curriculum/topic
- C: Global profile + per-topic overrides

**Recommendation:** C. Some preferences are universal, some are domain-specific.

### 4. Experiment Ethics

How do we handle micro-experiments fairly?

**Principles:**
- Never disadvantage the learner (both conditions should be valid approaches)
- Short experiments (resolve within one session when possible)
- Learner can see and understand experiments ("I'm trying something new today")
- Immediate benefit (even "losing" condition teaches something)

### 5. Cold Start

What do we do for brand new users before we have profile data?

**Options:**
- A: Default profile based on population averages
- B: Ask a few quick questions before starting
- C: Start with the soft onboarding arc
- D: Use aggressive micro-experimentation in first 3 sessions

**Recommendation:** C + D. Soft onboarding plus rapid experimentation.

---

## Summary: What This Is and Isn't

### This IS:

- A **continuous observation system** that builds understanding over time
- An **evidence-based approach** that validates preferences with experiments
- A **voice-native design** that works within 90-minute conversations
- A **scientifically sound model** that avoids debunked "learning styles" claims
- An **adaptive system** that personalizes tutoring based on what actually works

### This IS NOT:

- A quiz that tells you "what kind of learner you are"
- A fixed typology (visual/auditory/kinesthetic)
- A one-time assessment
- A replacement for good curriculum design
- A guarantee of better outcomes (it's a tool for continuous improvement)

---

## References

1. Pashler, H., et al. (2008). "Learning Styles: Concepts and Evidence." Psychological Science in the Public Interest.
2. 1EdTech ACCLIP Specification: https://www.imsglobal.org/accessibility
3. xAPI Specification: https://xapi.com/overview/
4. Dunlosky, J., et al. (2013). "Improving Students' Learning With Effective Learning Techniques." Psychological Science in the Public Interest.
5. Roediger, H. L., & Butler, A. C. (2011). "The critical role of retrieval practice in long-term retention."

---

*Document created as exploration and proposal. Implementation decisions pending review.*
