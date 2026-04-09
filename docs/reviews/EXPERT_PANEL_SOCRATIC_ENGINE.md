# UnaMentis Expert Panel: Activating the Socratic Engine

**Date:** March 29, 2026
**Subject:** Deep learner adaptation, Socratic engagement, and institutional analytics
**Panel:** Dr. Aria Vasquez (Voice AI), Marcus Chen (iOS Platform), Dr. Priya Sharma (Educational Software)
**Context:** Response to platform creator's vision for countering AI's negative effects on education

---

## The Vision

UnaMentis exists to counter AI's negative impact on education. Instead of giving answers, the system uses AI to push hard in the opposite direction: Socratic engagement that challenges, probes, and draws out genuine understanding. The system must learn and adapt to each individual endlessly. Institutions need curriculum effectiveness data. The learner profile should never be "done."

---

## Part 1: Panel Discussion

### Dr. Vasquez (Voice AI)

**What excites me:** Voice carries cognitive state that text cannot. Hesitation, rising intonation, filler words, pacing, these encode uncertainty far more reliably than textual content alone. The infrastructure exists: SileroVAD, AudioEngine with sophisticated buffer scheduling, session states distinguishing userSpeaking/aiSpeaking/interrupted/paused. None of this is used for pedagogical purposes yet.

**Highest-leverage opportunity:** The gap between the audio pipeline and the learning engine. Without any new audio analysis, the existing pipeline can compute:

1. **Response latency**: Time between AI finishing and learner starting to speak (long = thinking/confused, short = confident)
2. **Utterance duration vs. content ratio**: Short utterances with few words = uncertain. Long, flowing = engaged.
3. **Interruption patterns**: Barge-in during explanation = highly engaged OR frustrated. Content disambiguates.
4. **Silence tolerance**: How long the learner sits before prompting the AI = productive struggle tolerance.

These signals are available TODAY from existing telemetry. They just need to flow into `LearnerSignals` and from there into the profile.

**Voice-specific Socratic tools:**
- **Productive silence as pedagogy**: After a probing question, the system should *wait*. Silence after a challenge is learning. "Take your time" after 5 seconds. Never interpret silence as disengagement during a Socratic probe.
- **STT word-level confidence**: Deepgram and AssemblyAI return per-word confidence scores. A word with 0.6 confidence likely corresponds to hesitant speech. Currently consumed and discarded by STT services.
- **Conversational repair patterns**: "Wait, let me start over," "Actually..." reveal self-monitoring, evolving understanding, and where understanding breaks down.
- **Strategic silence insertion**: Not TTS speed changes (which affect naturalness), but micro-pauses before key terms, giving the brain a fraction of a second longer to process vocabulary.
- **Turn-taking as Socratic control**: During Elicitation, the AI asks ONE question and stops. The TTS adds deliberate pauses after question marks to signal "your turn."

---

### Marcus Chen (iOS Platform)

**What excites me:** The architectural bones are sound. FOVContextManager's four-tier buffer hierarchy, ConfidenceMonitor's response analysis, ContextExpansionTool's LLM-driven content requests. The problem is three critical data paths that exist as structs but have no runtime connections:

1. **Signal collection to profile**: `LearnerSignals` exists but is never populated from behavior
2. **Profile to adaptation**: `ContentPreferences`, `StrategySignals` are designed with zero code
3. **Adaptation to LLM context**: System prompt says "be Socratic" but never adapts based on who the learner is

**The single most important missing piece:** `LearnerProfile` Core Data entity. Without persistent learner state, every session starts from zero. The 867-line exploration doc has designed the schema. Implementation path:

1. Add Core Data entity with JSON-encoded sub-objects (`goalsJSON`, `constraintsJSON`, `preferencesJSON`, `strategiesJSON`, `evidenceJSON`)
2. Create `ProfileSignalCollector` actor receiving events from SessionManager
3. Create `ProfileInferenceEngine` actor running periodically (not per-utterance) to update preferences
4. Inject profile into `FOVContextManager.buildContext()` so system prompt adapts

JSON-in-Core-Data is correct for v1: avoids schema migration headaches while profile shape evolves. Sub-structs are Codable and Sendable.

**Privacy architecture:** Core Data with `NSPersistentStoreDescription.setOption(FileProtectionType.complete)` ensures profile is inaccessible when device is locked. For institutional deployments, profiles sync to server only with explicit consent, only in aggregate form. Individual profiles stay on-device.

**Performance concern:** For 90+ minute sessions, any inference engine must run off the main path. `FOVSessionContextCoordinator` is @MainActor for Core Data access. Signal analysis must dispatch to a background actor.

---

### Dr. Sharma (Educational Software)

**What excites me:** The vision of countering AI's negative effects is the most compelling edtech framing I've seen. Most AI learning tools optimize for engagement metrics, which means giving answers quickly and creating dependency. The Socratic approach inverts this by creating *productive friction*.

`ProductiveStruggleMetrics` embodies this: it tracks think time, teachback attempts/successes, clarification/repetition requests. The `encouragementMessage` rewards struggle: "You invested 3 minutes of deep thinking. That is how real learning happens." This is pedagogically correct, effortful retrieval strengthens memory traces.

**What concerns me:** None of the pedagogy is wired up. `TeachbackResult` exists but nothing creates instances of it. No code evaluates a learner's explanation, scores it, or routes to the appropriate next action. The system prompt says "Use Socratic questioning" but doesn't enforce it. An LLM given a vague Socratic instruction will default to explaining when the learner seems confused, the exact opposite of what you want.

**Critical observation about ContentDepth:** The `aiInstructions` at every depth level focus entirely on what content to present. Not one mentions asking the learner to explain, predict, or apply before providing the answer. The instructions need Socratic directives baked in.

**Highest-leverage opportunity:** Curriculum effectiveness falls out naturally from proper teachback implementation. If you aggregate `TeachbackResult.missedConcepts` across all learners studying the same curriculum and 70% miss the same concept, the curriculum's explanation of that concept is inadequate. This is the "curriculum quality feedback" the vision calls for.

---

## Part 2: The Socratic Engine

### The Core Problem

"Use Socratic questioning" in a system prompt produces occasional, shallow questions. A true Socratic engine requires structured dialogue patterns that the system actively enforces.

### Architecture: SocraticDialogueManager

A new actor between SessionManager and LLM calls, modifying the system prompt and enforcing pedagogical protocol.

**Location:** `UnaMentis/Core/Pedagogy/SocraticDialogueManager.swift`

```swift
public actor SocraticDialogueManager {
    private var currentPhase: SocraticPhase = .elicitation
    private var phaseHistory: [PhaseTransition] = []
    private var conceptUnderDiscussion: String?
    private var learnerStatedUnderstanding: String?
    private var socraticDepth: Int = 0
    private let maxSocraticDepth: Int = 4

    private let confidenceMonitor: ConfidenceMonitor
    private let profileAccessor: LearnerProfileAccessor?
}
```

### The Five Socratic Phases

```
ELICITATION -> PROBING -> TESTING -> CONSOLIDATION -> ADVANCEMENT
     ^            |          |              |
     |            v          v              |
     +---- SCAFFOLDING (entered on struggle, returns to prior phase)
```

**Phase 1: Elicitation** -- Before explaining anything, ask what the learner already knows.
- Prompt injection: "Before explaining [concept], ask the learner what they already know about it. Do NOT provide any information until they have attempted an answer."
- Key principle: **Never explain first. Always elicit first.**

**Phase 2: Probing** -- Challenge the learner's stated understanding.
- Prompt injection: "The learner said: '[response]'. Identify the strongest and weakest parts. Ask a targeted question that probes the weakest part. Do NOT correct them yet."
- Transition: Solid understanding -> Testing. Struggle after maxSocraticDepth probes -> Scaffolding.
- Key principle: **Questions should reveal gaps, not fill them.**

**Phase 3: Testing** -- Verify understanding through application.
- Prompt injection: "Present a scenario or problem requiring applying [concept]. Ask them to work through it. Do NOT provide the solution."
- This is where `TeachbackResult` gets populated via structured LLM evaluation rubric.
- Transition: good/excellent -> Consolidation, partial -> back to Probing, struggling -> Scaffolding.

**Phase 4: Consolidation** -- Connect to broader knowledge.
- Prompt injection: "The learner demonstrated understanding. Ask them to connect [concept] to [previously learned concept] or predict implications for [upcoming concept]."
- This is where cross-topic connections form.

**Phase 5: Advancement** -- Move to next concept.
- Record mastery in ProgressTracker, update ProductiveStruggleMetrics, schedule retrieval via RetrievalSchedule.
- Reset to Elicitation for next concept.

**Scaffolding (entered from any phase):**
- Triggered by: consecutive failed probes, explicit confusion signals, or voice hesitation patterns.
- Prompt injection: "The learner is struggling. Provide ONE hint or guiding question. Do NOT explain the full answer. Break [concept] into a smaller sub-concept."
- Returns to the phase that triggered it, with reduced complexity.
- Key principle: **Minimum help needed, then return to Socratic questioning.**

### Anti-Patterns the Engine Must Prevent

1. **Premature explanation**: LLM explains before learner has attempted articulation. Engine detects explanation before Elicitation completes, forces a question instead.
2. **Shallow questioning**: LLM asks "Does that make sense?" Engine detects yes/no questions and replaces with open-ended probes.
3. **Giving up too quickly**: After one wrong answer, LLM explains everything. Engine enforces minimum probe depth before allowing explanation.
4. **Over-scaffolding**: LLM provides too much help. Engine limits hints to single-concept guidance.

### Integration with Existing Code

The SocraticDialogueManager adds a `## SOCRATIC PROTOCOL` section to the system message produced by `FOVContext.toSystemMessage()`, containing phase-specific instructions, current concept, and learner's stated understanding. Requires small extension to `FOVContext.toSystemMessage()` to accept pedagogical context.

---

## Part 3: The Learner Adaptation Architecture

### The Core Feedback Loop (currently broken)

```
Current:  SessionManager -> (signals collected but dropped)

Needed:   SessionManager -> ProfileSignalCollector -> ProfileInferenceEngine
               -> LearnerProfile (Core Data) -> AdaptiveContextInjector
               -> FOVContext -> LLM prompt -> adapted behavior
```

### Data Flow Architecture

```
[Voice Session Active]
        |
        v
SessionManager (existing) emits events:
  - utterance completed (with STT timestamps)
  - AI response delivered
  - silence detected / barge-in occurred
  - checkpoint attempted / teachback scored
        |
        v
ProfileSignalCollector (NEW actor)
  - Computes derived signals:
    - response latency (AI done -> learner starts)
    - utterance complexity (word count, structure)
    - confusion markers ("I don't understand", "wait", "huh")
    - engagement markers ("oh!", "interesting", "so you mean")
    - conversational repair ("actually...", "wait, let me...")
  - Batches signals every 2 minutes (not per-utterance)
        |
        v
ProfileInferenceEngine (NEW actor)
  - Runs on batched signals, NOT on main path
  - Bayesian preference updates:
    - P(prefers_examples_first | observed_signals)
    - P(optimal_chunk_length | silence_patterns)
    - P(socratic_tolerance | response_to_probing)
  - Each preference has confidence score increasing with evidence
  - Triggers micro-experiments when confidence low
        |
        v
LearnerProfile (Core Data, NEW)
  - JSON-encoded sub-objects (Codable, Sendable)
  - Loaded at session start
  - Updated at session end (not during, avoids Core Data contention)
  - Server sync: optional, anonymized, explicit consent
        |
        v
AdaptiveContextInjector (extends FOVSessionContextCoordinator)
  - Injects profile into FOVContext at each LLM call:
    - Socratic phase adjusted for learner's probing tolerance
    - Explanation approach matched to observed preference
    - Checkpoint frequency matched to attention patterns
    - Content depth adjusted for demonstrated prior knowledge
```

### Signal Collection (Ranked by Value)

**Tier 1 (available now, highest value):**

| Signal | Source | Profile Field |
|--------|--------|---------------|
| Response latency | STT timestamps vs TTS end | thinkTimePattern, productiveStruggleTolerance |
| Clarification requests | Intent classification | clarificationRate, explanationApproach |
| Barge-in frequency | SessionState.interrupted | engagementLevel, paceTolerance |
| Session duration patterns | Start/end times | optimalSessionLength, fatigueThreshold |
| Teachback scores | TeachbackResult | selfExplanationQuality, per-concept mastery |

**Tier 2 (requires new analysis):**

| Signal | Source | Profile Field |
|--------|--------|---------------|
| Utterance complexity over time | Word count from STT | engagementDecayRate, fatigueOnset |
| Question type distribution | Classify as factual/conceptual/meta | learningGoalOrientation |
| Topic request patterns | "Can we go back to..." | sequencingPreference |
| Self-correction frequency | Repair marker detection | metacognitiveSkill |

**Tier 3 (requires micro-experiments):**

| Signal | Source | Profile Field |
|--------|--------|---------------|
| Retrieval practice effectiveness | Delayed recall with/without retrieval | retrievalPracticeEffectiveness |
| Example-first vs theory-first | A/B explanation ordering | explanationApproach |
| Checkpoint frequency preference | A/B checkpoint density | checkpointFrequency |

### How the Profile Changes Behavior

1. **Low productiveStruggleTolerance**: Scaffolding enters sooner (after 2 failed probes instead of 4). Still asks questions; never jumps to explaining.
2. **High selfExplanationQuality**: More teachback checkpoints, fewer simple confirmations. System trusts learner to articulate understanding.
3. **Short optimalSessionLength**: More frequent consolidation, more "let's summarize what we covered" breaks.
4. **Strong retrievalPracticeEffectiveness**: Session opens with retrieval questions from previous sessions before new material.
5. **Domain-specific preferences**: A learner might prefer examples-first in physics but theory-first in history. Profile tracks per-domain overrides.

### The Profile Must Never Be "Done"

Even in the "updating" maturity state, micro-experiments continue. A learner who preferred examples-first six months ago may have developed enough expertise to prefer theory-first. The profile tracks domain-specific preferences with decay: old evidence gradually loses weight compared to recent observations.

---

## Part 4: Institutional Analytics

### Design Principles

1. **Privacy by aggregation**: Individual data never leaves device without explicit consent. Analytics computed on-device, uploaded as anonymized aggregates.
2. **Curriculum-centric, not learner-centric**: "Is this curriculum effective?" not "Is this learner struggling?"
3. **Actionable feedback**: Every metric should suggest a concrete action for the curriculum creator.

### Key Metrics

**Curriculum Quality Metrics:**

| Metric | Computation | Action for Creator |
|--------|-------------|-------------------|
| Concept missed rate | Aggregate TeachbackResult.missedConcepts | Rewrite explanation for frequently missed concepts |
| Confusion hotspots | Aggregate clarification requests per segment | Add examples, simplify language |
| Sequence effectiveness | Compare mastery across topic orderings | Reorder prerequisites |
| Explanation variant performance | Compare outcomes across AlternativeExplanation styles | Adopt winning variant |
| Retention decay curve | Aggregate RetrievalSchedule outcomes | Add retrieval prompts for fast-decaying concepts |

**Institutional Engagement Metrics:**

| Metric | What It Reveals |
|--------|-----------------|
| Active learner count | Adoption health |
| Average session duration | Engagement depth |
| Completion funnel | Where learners disengage |
| Return rate (sessions/learner/week) | Habit formation |
| Mastery velocity (time to 80%) | Curriculum difficulty calibration |

### Auto-Generated Curriculum Feedback Report

```
Curriculum: "Introduction to Quantum Mechanics"
Period: Last 30 days | Learners: 47

TOP ISSUES (most frequently missed in teachback):
  1. Wave-particle duality (67% miss rate, n=43)
     - Common confusion: conflating with classical wave behavior
     - Suggestion: Add concrete examples before mathematical formulation

  2. Superposition principle (54% miss rate, n=38)
     - Common confusion: thinking states must be either/or
     - Suggestion: Use coin analogy before formal state vector notation

STRENGTHS (highest first-attempt success):
  1. Photoelectric effect (89% success, n=41)
  2. Planck's constant (82% success, n=39)

SEQUENCE RECOMMENDATION:
  Current: Topics 3->4->5
  Suggested: Topics 4->3->5
  Reason: Learners who encountered Topic 4 first had 23% higher
  mastery on Topic 3 (n=12, medium confidence)
```

Generated entirely from aggregated TeachbackResult data, RetrievalSchedule outcomes, and ProductiveStruggleMetrics. No individual learner data included.

---

## Part 5: Implementation Roadmap

### Phase 0: Teachback Implementation (Weeks 1-2)
*Foundation for everything. Creates value immediately for beta users.*

- Implement LLM-based teachback evaluation using existing TeachbackResult/TeachbackTier types
- Create teachback evaluation prompt template scoring against correctConcepts/missedConcepts
- Wire CheckpointType.teachback into session flow
- Start recording ProductiveStruggleMetrics from session events
- **Integration:** SessionManager calls teachback evaluation, results flow to ProgressTracker
- **Files:** New `TeachbackEvaluator.swift`, modifications to `SessionManager.swift`, `CurriculumEngine.swift`

### Phase 1: Signal Collection & Profile Foundation (Weeks 3-5)
*Collect data silently. No behavior changes yet.*

- Add LearnerProfile Core Data entity (schema from exploration doc)
- Implement ProfileSignalCollector actor extracting signals from session events
- Compute response latency, utterance complexity, confusion markers from existing STT/VAD data
- Populate LearnerSignals fields (currently always empty)
- **No adaptation yet.** Just observe and record.
- **Beta milestone:** 5-person beta can begin with silent profile collection.
- **Files:** New entity in persistence model, new `LearnerProfileManager.swift`, new `ProfileSignalCollector.swift`

### Phase 2: Socratic Engine v1 (Weeks 5-8)
*The core pedagogical differentiator.*

- Implement SocraticDialogueManager with five-phase protocol
- Modify FOVContext.toSystemMessage() for Socratic protocol injection
- Implement anti-pattern detection (premature explanation, shallow questioning)
- Wire Socratic phases to CheckpointType values
- Create prompt templates for each phase
- Add socraticDepth tracking to ProductiveStruggleMetrics
- **Files:** New `Core/Pedagogy/SocraticDialogueManager.swift`, modifications to `FOVContextManager.swift`

### Phase 3: Profile-Driven Adaptation (Weeks 8-11)
*Profile starts changing behavior.*

- Implement ProfileInferenceEngine with Bayesian preference updates
- Create AdaptiveContextInjector modifying LLM prompts based on profile
- Adapt Socratic Engine based on profile (probe depth, scaffolding triggers)
- Implement micro-experiment scheduling (one per session, low-stakes only)
- Connect RetrievalSchedule to session opening (review previous material)
- **Larger beta milestone:** Profile adaptation active for larger cohort.
- **Files:** New `ProfileInferenceEngine.swift`, extensions to `FOVSessionContextCoordinator.swift`

### Phase 4: Institutional Analytics (Weeks 11-14)
*Server-side analytics for institutional customers.*

- Add analytics tables to server database
- Create API endpoints at /api/analytics/ in management API
- Implement on-device aggregate computation and anonymized upload
- Build curriculum effectiveness dashboard in web console
- Generate automated curriculum feedback reports
- **Files:** `server/management/analytics/`, `server/database/schema.sql`, `server/web/` dashboard components

### Phase 5: Voice-Specific Adaptation (Weeks 14-17)
*Leverage voice signals for deepest adaptation.*

- Compute response latency and silence patterns from STT timestamps
- Feed voice-derived signals into ProfileInferenceEngine
- Adapt turn-taking: increase wait time for learners needing more think time
- Implement engagement decay detection from utterance complexity trends
- Add PedagogicalPauseController for strategic silence insertion
- Surface STT word-level confidence to signal pipeline
- **MVP launch milestone:** Full stack active.
- **Files:** Extensions to STT services, new `PedagogicalPauseController.swift`, `ProfileSignalCollector.swift`

---

## Part 6: Voice-Specific Opportunities

### What Voice Can Do That Text Cannot

| Capability | How It Works | Pedagogical Value |
|------------|-------------|-------------------|
| Productive silence | System waits after probing question, celebrates thinking time | Normalizes struggle, prevents premature rescue |
| Vocal confidence detection | STT word-level confidence scores, filler word detection | Detects uncertainty invisible in text |
| Conversational repair | "Wait, let me start over..." detection | Reveals metacognitive skill and understanding boundaries |
| Strategic pacing | Micro-pauses before key terms in TTS | Gives brain processing time for new vocabulary |
| Turn-taking control | Deliberate pauses after questions, silence tolerance | Enforces Socratic protocol through audio pipeline |
| Engagement decay | Utterance complexity trending downward over session | Detects fatigue before learner is aware |
| Interruption analysis | Barge-in content classification (eager vs frustrated) | Distinguishes engagement from disengagement |

### Audio Pipeline Evolution

1. **PedagogicalPauseController**: Strategic silences based on Socratic phase, not just interSentenceSilenceMs. After Socratic question: 1.5s pause. After scaffolding hint: 2s pause.
2. **STT word-level confidence routing**: Currently consumed and discarded by STT services. Route to ProfileSignalCollector.
3. **Audio session continuity tracking**: Whether learner kept session active (not backgrounded, not muted) is a stronger engagement signal than duration alone.

---

## Summary: The Key Insight

**The infrastructure exists. The connections do not.**

Every component needed for deep Socratic engagement is already built as a data structure, protocol, or algorithm:
- TeachbackResult, TeachbackTier, TeachbackNextAction
- LearnerSignals, ProductiveStruggleMetrics
- RetrievalSchedule (Leitner + SM2)
- ContentDepth with AI instructions
- ConfidenceMonitor, ContextExpansionTool
- FOVContextManager with 4-tier cognitive buffer
- CheckpointType with 5 assessment levels

None of them are connected to each other. The work ahead is primarily integration and feedback-loop closure, not new invention.

**Priority order of deliverables:**

| # | Deliverable | Creates |
|---|-------------|---------|
| 1 | Teachback evaluation | Data for everything downstream |
| 2 | LearnerProfile persistence | Cross-session memory |
| 3 | SocraticDialogueManager | Core pedagogical differentiator |
| 4 | ProfileSignalCollector | Populates empty LearnerSignals |
| 5 | ProfileInferenceEngine | Closes the adaptation loop |
| 6 | AdaptiveContextInjector | Profile changes LLM behavior |
| 7 | Institutional analytics API | Revenue-enabling for institutional sales |
| 8 | Voice signal extraction | Deepest learner understanding |

---

*Panel review conducted by Dr. Aria Vasquez (Voice AI), Marcus Chen (iOS Platform), and Dr. Priya Sharma (Educational Software) on March 29, 2026.*
