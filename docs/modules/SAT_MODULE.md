# SAT Preparation Module Specification

## Executive Summary

The SAT Preparation Module is a comprehensive, adaptive learning system designed to maximize student performance on the Digital SAT. Unlike traditional test prep that focuses solely on content review, this module integrates content mastery with strategic test-taking skills, time management, stress management, and adaptive practice that mirrors the actual test experience.

**Key Differentiators:**
- Adaptive practice that mimics the Digital SAT's multi-stage adaptive testing (MST)
- Integrated test-taking strategy training alongside content mastery
- Personalized pacing and timing optimization
- Anxiety and performance psychology components
- Real-time score prediction with targeted improvement paths
- College readiness alignment beyond just test scores

## Table of Contents

1. [Understanding the Digital SAT](#understanding-the-digital-sat)
2. [Module Architecture](#module-architecture)
3. [Content Domain Coverage](#content-domain-coverage)
4. [Test-Taking Mastery System](#test-taking-mastery-system)
5. [Adaptive Practice Engine](#adaptive-practice-engine)
6. [Timing and Pacing System](#timing-and-pacing-system)
7. [Performance Psychology](#performance-psychology)
8. [Score Prediction and Improvement](#score-prediction-and-improvement)
9. [UMCF Integration](#umcf-integration)
10. [Implementation Roadmap](#implementation-roadmap)

---

## Understanding the Digital SAT

### Digital SAT Overview (2024+)

The SAT transitioned to a fully digital, adaptive format in 2024. Key characteristics:

| Element | Digital SAT |
|---------|-------------|
| Total Duration | 2 hours 14 minutes |
| Format | Computer-based, adaptive |
| Sections | 2 (Reading/Writing, Math) |
| Adaptive Model | Multi-stage adaptive testing (MST) |
| Calculator | Allowed throughout (built-in Desmos) |
| Score Range | 400-1600 (200-800 per section) |
| Reading Passages | Shorter (25-150 words each) |
| Questions | 98 total (54 RW + 44 Math) |

### Multi-Stage Adaptive Testing (MST)

The Digital SAT uses a two-stage adaptive model within each section:

```
Section Start
     │
     ▼
┌─────────────────────────────────────────────────────┐
│              Module 1 (First Stage)                  │
│         Mix of easy, medium, hard questions          │
│              Establishes baseline ability            │
└─────────────────────────────────────────────────────┘
     │
     │ Performance determines Module 2 difficulty
     ▼
┌─────────────────────────────────────────────────────┐
│              Module 2 (Second Stage)                 │
│    Easier Module ◄──────────►  Harder Module        │
│    (Lower ceiling)              (Higher ceiling)     │
└─────────────────────────────────────────────────────┘
     │
     ▼
Final Score Calculation
(Based on difficulty + accuracy)
```

**Strategic Implication**: Strong Module 1 performance unlocks higher-scoring Module 2 questions. Early mistakes have compounding effects.

### Section Breakdown

| Section | Modules | Time | Questions | Time/Question |
|---------|---------|------|-----------|---------------|
| Reading & Writing | 2 | 64 min (32+32) | 54 (27+27) | ~71 seconds |
| Math | 2 | 70 min (35+35) | 44 (22+22) | ~95 seconds |

### Why Traditional Prep Falls Short

Standard SAT preparation fails because it:

1. Uses non-adaptive practice that doesn't mirror the real test
2. Separates content learning from test-taking strategy
3. Ignores timing patterns and pacing optimization
4. Neglects the psychological aspects of high-stakes testing
5. Provides generic advice instead of personalized improvement paths
6. Treats all errors equally instead of analyzing error patterns

---

## Module Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────┐
│                      SAT Preparation Module                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Content    │  │   Strategy   │  │    Psychology        │  │
│  │   Engine     │  │   Coach      │  │    Trainer           │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                      │              │
│         ▼                 ▼                      ▼              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Adaptive Learning Core                       │  │
│  │  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐  │  │
│  │  │ Mastery │  │ Timing   │  │ Error    │  │ Score     │  │  │
│  │  │ Tracker │  │ Optimizer│  │ Analyzer │  │ Predictor │  │  │
│  │  └─────────┘  └──────────┘  └──────────┘  └───────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Adaptive Practice Engine                     │  │
│  │        MST Simulation × Personalized Difficulty          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Core Components

#### 1. Content Engine
Manages all SAT content knowledge:
- Reading comprehension skills and passage types
- Writing conventions and expression of ideas
- Mathematical concepts across all domains
- Vocabulary in context
- Data interpretation and analysis

#### 2. Strategy Coach
Teaches and reinforces test-taking strategies:
- Question type identification
- Elimination techniques
- Time allocation decisions
- Educated guessing frameworks
- Answer verification methods

#### 3. Psychology Trainer
Addresses mental aspects of test performance:
- Test anxiety management
- Focus and concentration techniques
- Confidence building
- Mistake recovery strategies
- Peak performance mindset

#### 4. Adaptive Learning Core
Powers personalized learning:
- **Mastery Tracker**: Per-skill proficiency mapping
- **Timing Optimizer**: Personalized pacing strategies
- **Error Analyzer**: Pattern detection in mistakes
- **Score Predictor**: Real-time score estimation

---

## Content Domain Coverage

### Reading and Writing Section

The combined Reading and Writing section tests four content domains:

| Domain | Weight | Description |
|--------|--------|-------------|
| **Craft and Structure** | ~28% | Word meaning, text structure, purpose |
| **Information and Ideas** | ~26% | Central ideas, details, inferences |
| **Standard English Conventions** | ~26% | Grammar, punctuation, usage |
| **Expression of Ideas** | ~20% | Rhetorical synthesis, transitions |

#### Craft and Structure Skills

| Skill | Description | Question Types |
|-------|-------------|----------------|
| Words in Context | Determine word/phrase meaning from context | Vocabulary, connotation |
| Text Structure | Analyze how parts relate to whole | Purpose, organization |
| Cross-Text Connections | Compare perspectives across texts | Paired passages |

#### Information and Ideas Skills

| Skill | Description | Question Types |
|-------|-------------|----------------|
| Central Ideas | Identify main point or theme | Summary, thesis |
| Command of Evidence | Support claims with textual evidence | Cite evidence, strengthen/weaken |
| Inferences | Draw logical conclusions | Implied meaning, prediction |

#### Standard English Conventions Skills

| Skill | Description | Question Types |
|-------|-------------|----------------|
| Boundaries | Sentence structure, fragments, run-ons | Punctuation, sentence combination |
| Form, Structure, Sense | Agreement, verb forms, pronoun clarity | Grammar, syntax |

#### Expression of Ideas Skills

| Skill | Description | Question Types |
|-------|-------------|----------------|
| Rhetorical Synthesis | Integrate information effectively | Notes-based writing |
| Transitions | Connect ideas logically | Transition words, coherence |

### Math Section

The Math section covers four content domains:

| Domain | Weight | Description |
|--------|--------|-------------|
| **Algebra** | ~35% | Linear equations, systems, functions |
| **Advanced Math** | ~35% | Quadratics, polynomials, exponentials |
| **Problem Solving & Data** | ~15% | Ratios, percentages, statistics |
| **Geometry & Trigonometry** | ~15% | Area, volume, triangles, circles |

#### Algebra Skills

| Skill | Topics | Key Concepts |
|-------|--------|--------------|
| Linear Equations | Solve, graph, interpret | Slope, intercepts, forms |
| Linear Inequalities | Solve, graph, interpret | Boundary lines, shading |
| Systems of Equations | Two variables, word problems | Substitution, elimination |
| Linear Functions | Modeling, interpretation | Rate of change, domain/range |

#### Advanced Math Skills

| Skill | Topics | Key Concepts |
|-------|--------|--------------|
| Equivalent Expressions | Simplify, factor, expand | Polynomials, rational expressions |
| Quadratic Equations | Solve, graph, interpret | Factoring, formula, completing square |
| Exponential Functions | Growth, decay, interpretation | Exponential equations, graphs |
| Nonlinear Systems | Quadratic-linear systems | Intersections, solutions |

#### Problem Solving & Data Analysis Skills

| Skill | Topics | Key Concepts |
|-------|--------|--------------|
| Ratios and Proportions | Direct/inverse variation | Unit rates, scaling |
| Percentages | Increase/decrease, applications | Interest, markup, discount |
| Statistics | Mean, median, mode, spread | Standard deviation, outliers |
| Probability | Basic probability, expected value | Conditional probability |
| Data Interpretation | Tables, graphs, charts | Trends, comparisons |

#### Geometry & Trigonometry Skills

| Skill | Topics | Key Concepts |
|-------|--------|--------------|
| Area and Volume | 2D and 3D shapes | Formulas, composite shapes |
| Triangles | Properties, similarity, congruence | Pythagorean theorem, special triangles |
| Circles | Properties, arc length, sectors | Circumference, area, equations |
| Right Triangle Trig | Sine, cosine, tangent | SOH-CAH-TOA, applications |
| Coordinate Geometry | Distance, midpoint, parallel/perpendicular | Slope relationships |

---

## Test-Taking Mastery System

### Philosophy: Strategy as Skill

Test-taking strategy is not "tricks" but learnable cognitive skills:

| Myth | Reality |
|------|---------|
| "Smart students don't need strategies" | All high scorers use systematic approaches |
| "Strategies are shortcuts" | Strategies are efficient problem-solving |
| "Just learn the content" | Strategy + content = maximum performance |

### Core Strategy Framework

#### 1. Question Triage

Learn to quickly categorize questions:

| Category | Action | Time Investment |
|----------|--------|-----------------|
| **Immediate** | Answer confidently | Full time |
| **Workable** | Attempt systematically | Standard time |
| **Challenging** | Strategic guess, flag | Minimal time |
| **Skip-Return** | Mark and return if time | Remaining time |

#### 2. Process of Elimination (POE)

Systematic elimination increases accuracy:

```
Step 1: Read question, understand what's asked
Step 2: Predict answer before looking at choices
Step 3: Eliminate clearly wrong answers
Step 4: Compare remaining choices
Step 5: Select best answer (or guess strategically)
```

**POE Success Rates:**
| Eliminated | Random Guess | POE Guess |
|------------|--------------|-----------|
| 0 of 4 | 25% | 25% |
| 1 of 4 | 25% | 33% |
| 2 of 4 | 25% | 50% |
| 3 of 4 | 25% | 100% |

#### 3. Evidence-Based Answering

For Reading/Writing:
- Every correct answer has textual support
- If you can't point to evidence, reconsider
- Wrong answers often use words from passage misleadingly

#### 4. Back-Solving and Plugging In

For Math:
- When given answer choices, work backwards
- Substitute answer choices into the problem
- Start with middle value for efficiency

#### 5. Strategic Guessing

When to guess strategically:
- No penalty for wrong answers on Digital SAT
- Never leave questions blank
- Use POE to maximize guess accuracy
- Flag and return with remaining time

### Question Type Strategies

#### Reading: Words in Context

```
Strategy:
1. Cover the word, read surrounding context
2. Predict a simple word that fits
3. Find the answer matching your prediction
4. Verify by substituting back

Common Trap: Answer that matches a common meaning
but not the contextual meaning
```

#### Reading: Evidence Questions

```
Strategy:
1. Understand the claim you're supporting
2. Look for DIRECT support, not inferences
3. The evidence should explicitly state or strongly imply
4. Beware of evidence that's related but doesn't support

Common Trap: Evidence that mentions the topic
but doesn't actually support the specific claim
```

#### Writing: Grammar Questions

```
Strategy:
1. Identify the error type being tested
2. Apply the specific rule
3. Eliminate answers with the same error
4. Choose the clearest, most concise correct option

Common Trap: Overly complex "correct" sounding
answers when simple is right
```

#### Math: Word Problems

```
Strategy:
1. Read carefully, identify what's asked
2. Define variables explicitly
3. Translate words to equations systematically
4. Solve and check that answer makes sense

Key Translations:
- "is" = equals
- "of" = multiply
- "per" = divide
- "more than" = add
- "less than" = subtract
```

#### Math: Data/Graph Questions

```
Strategy:
1. Read axis labels and units first
2. Note any keys or legends
3. Identify what specifically is asked
4. Extract only the needed data points

Common Trap: Using wrong data point or
misreading scale/units
```

---

## Adaptive Practice Engine

### Mimicking the Real Test

The practice engine replicates MST behavior:

```
┌────────────────────────────────────────────────────────────────┐
│                   Adaptive Practice Session                     │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Module 1: Calibration                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Mixed difficulty questions (easy/medium/hard)            │   │
│  │ Establishes current performance level                    │   │
│  │ 27 questions (RW) or 22 questions (Math)                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│         ┌────────────────┴────────────────┐                    │
│         ▼                                 ▼                    │
│  ┌─────────────────┐              ┌─────────────────┐         │
│  │  Module 2: Easy │              │  Module 2: Hard │         │
│  │  Score cap ~600 │              │  Score cap ~800 │         │
│  │  Focus: mastery │              │  Focus: ceiling │         │
│  └─────────────────┘              └─────────────────┘         │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

### Difficulty Calibration

Questions are tagged with Item Response Theory (IRT) parameters:

| Parameter | Meaning | Range |
|-----------|---------|-------|
| Difficulty (b) | How hard the question is | -3 to +3 |
| Discrimination (a) | How well it separates ability levels | 0.5 to 2.5 |

### Practice Modes

#### 1. Section Practice (Timed)
- Full section simulation
- Real MST adaptation
- Authentic timing pressure
- Score prediction after

#### 2. Domain Drill (Flexible)
- Focus on specific content areas
- Adjustable difficulty
- Immediate explanations
- Mastery tracking

#### 3. Strategy Training
- Question type isolation
- Strategy application practice
- Deliberate slow practice
- Speed building over time

#### 4. Full Practice Test
- Complete 2+ hour simulation
- Both sections in order
- Realistic break timing
- Comprehensive score report

#### 5. Error Analysis Review
- Review missed questions
- Pattern identification
- Strategy refinement
- Concept remediation

### Question Selection Algorithm

```
For each practice question:

Priority Score =
    (Skill Gap × 0.30) +
    (Recency × 0.20) +
    (Difficulty Match × 0.25) +
    (Error Pattern × 0.15) +
    (Time Efficiency × 0.10)

Where:
- Skill Gap: 1.0 - current_mastery for that skill
- Recency: Days since last practice on this skill / 14
- Difficulty Match: How close to optimal challenge zone
- Error Pattern: Weight for repeated error types
- Time Efficiency: Prioritize high-value skills
```

---

## Timing and Pacing System

### The Timing Challenge

Digital SAT timing is tight:
- Reading/Writing: ~71 seconds per question
- Math: ~95 seconds per question

But not all questions should take equal time.

### Personalized Pacing Profiles

The system builds individual timing profiles:

```json
{
  "studentId": "student_123",
  "pacingProfile": {
    "readingWriting": {
      "wordsInContext": { "average": 45, "target": 40 },
      "centralIdeas": { "average": 85, "target": 70 },
      "grammar": { "average": 35, "target": 30 },
      "transitions": { "average": 50, "target": 45 }
    },
    "math": {
      "linearEquations": { "average": 60, "target": 50 },
      "quadratics": { "average": 120, "target": 90 },
      "geometry": { "average": 100, "target": 80 },
      "wordProblems": { "average": 150, "target": 120 }
    },
    "overallPattern": "rushes_early_struggles_late",
    "recommendedAdjustment": "slow_down_module_1"
  }
}
```

### Pacing Strategies

#### Module 1 Strategy (Critical)

Module 1 determines Module 2 difficulty. Pacing matters enormously:

| Approach | Risk | Recommendation |
|----------|------|----------------|
| Rush through | Miss easy points, hurt adaptive | Never |
| Steady pace | Balanced performance | Default |
| Front-load time | Run out at end | Avoid |
| Strategic allocation | Best results | Train for this |

**Recommended Module 1 Approach:**
1. Spend full time on questions you can solve
2. Don't waste time on questions you truly don't know
3. Accuracy > speed in Module 1
4. Strong Module 1 = easier path to high score

#### Time Banking

Build "time bank" from quick questions:

```
Example RW Section (32 minutes for 27 questions):

Question Type    | Count | Target Time | Total
-----------------|-------|-------------|-------
Quick grammar    | 8     | 30 sec      | 4 min
Medium inference | 12    | 70 sec      | 14 min
Hard synthesis   | 7     | 120 sec     | 14 min
                                       | 32 min

Strategy: Finish quick questions in 25 sec each
→ Banks 40 extra seconds for hard questions
```

### Timing Training Progression

| Phase | Focus | Method |
|-------|-------|--------|
| Untimed | Accuracy and understanding | No clock visible |
| Aware | Notice natural pacing | Clock visible, no pressure |
| Guided | Build target times | Per-question targets |
| Timed | Section pressure | Full section timing |
| Simulated | Test day conditions | Complete test simulation |

---

## Performance Psychology

### The Mental Game

High-stakes testing involves psychological challenges:

| Challenge | Impact | Intervention |
|-----------|--------|--------------|
| Test Anxiety | Reduced working memory | Relaxation techniques |
| Performance Pressure | Decision paralysis | Reframing strategies |
| Fatigue | Declining accuracy | Energy management |
| Frustration | Emotional interference | Mistake recovery |
| Overconfidence | Careless errors | Verification habits |

### Anxiety Management System

#### Pre-Test Anxiety

Techniques taught and practiced:

1. **Progressive Muscle Relaxation**
   - Systematic tension/release
   - Practiced before practice tests
   - Reduces physical anxiety symptoms

2. **Cognitive Reframing**
   - "This is a challenge, not a threat"
   - "I've prepared for this"
   - "One question at a time"

3. **Visualization**
   - Mentally rehearse test day
   - Imagine confident performance
   - Build procedural familiarity

#### During-Test Anxiety

Real-time strategies:

1. **Box Breathing**
   - 4 counts in, 4 hold, 4 out, 4 hold
   - Quick reset between sections
   - Use during hard questions

2. **Grounding Technique**
   - Feel feet on floor
   - Notice chair support
   - Return focus to present

3. **Positive Self-Talk**
   - "I know how to do this"
   - "Move on, next question is fresh"
   - "I'm prepared"

### Mistake Recovery Protocol

When you realize you made a mistake or miss a question:

```
RESET Protocol:

R - Recognize: Notice the mistake without judgment
E - Exhale: Take one deep breath
S - Set aside: That question is done
E - Engage: Focus fully on next question
T - Trust: Trust your preparation

Time allowed: 3-5 seconds maximum
```

### Focus and Concentration Training

Build sustained attention capacity:

| Week | Focus Duration | Method |
|------|----------------|--------|
| 1-2 | 15 minutes | Single domain practice |
| 3-4 | 25 minutes | Mixed practice |
| 5-6 | 35 minutes | Full module simulation |
| 7-8 | 70 minutes | Full section simulation |
| 9+ | 2+ hours | Full test simulation |

### Confidence Calibration

Balance confidence with accuracy:

| Pattern | Problem | Solution |
|---------|---------|----------|
| Overconfident | Careless errors, skip verification | Slow down, always verify |
| Underconfident | Second-guessing, time waste | Trust first instinct, practice |
| Variable | Inconsistent performance | Build systematic approach |

---

## Score Prediction and Improvement

### Score Prediction Model

The system predicts scores based on multiple factors:

```
Predicted Score = Base Score + Adjustments

Where:
- Base Score: Performance on adaptive practice
- Content Adjustment: Strength in remaining skills
- Strategy Adjustment: Test-taking skill level
- Timing Adjustment: Pacing efficiency
- Psychology Adjustment: Anxiety/focus factors
- Improvement Trajectory: Recent progress rate

Confidence Interval: ±30 points (typical)
```

### Score Improvement Paths

Different score ranges require different strategies:

#### 900-1100 → 1200+

Primary focus: **Content foundations**
- Fill major knowledge gaps
- Master core concepts
- Build procedural fluency
- Develop basic strategies

| Priority | Action |
|----------|--------|
| 1 | Algebra fundamentals |
| 2 | Reading comprehension basics |
| 3 | Grammar rules |
| 4 | Basic timing awareness |

#### 1100-1300 → 1400+

Primary focus: **Strategic refinement**
- Apply consistent strategies
- Eliminate careless errors
- Improve timing efficiency
- Handle medium-hard questions

| Priority | Action |
|----------|--------|
| 1 | POE mastery |
| 2 | Advanced math concepts |
| 3 | Evidence-based answering |
| 4 | Pacing optimization |

#### 1300-1450 → 1500+

Primary focus: **Peak performance**
- Perfect fundamentals
- Master hardest question types
- Optimize every second
- Psychological consistency

| Priority | Action |
|----------|--------|
| 1 | Hard question strategies |
| 2 | Error elimination |
| 3 | Time efficiency |
| 4 | Peak performance psychology |

### Improvement Analytics

Track improvement across dimensions:

```json
{
  "improvementReport": {
    "overallScore": {
      "starting": 1150,
      "current": 1320,
      "target": 1400,
      "progress": "68%"
    },
    "byDomain": {
      "algebra": { "start": 0.65, "current": 0.82, "trend": "improving" },
      "reading": { "start": 0.58, "current": 0.71, "trend": "improving" },
      "geometry": { "start": 0.45, "current": 0.55, "trend": "slow" }
    },
    "bySkill": {
      "timing": { "start": "poor", "current": "good" },
      "strategies": { "start": "none", "current": "consistent" },
      "anxiety": { "start": "high", "current": "moderate" }
    },
    "recommendations": [
      "Focus on geometry, especially circle problems",
      "Practice hard RW questions for last 50 points",
      "Continue timing drills for consistency"
    ]
  }
}
```

---

## UMCF Integration

### SAT UMCF Extensions

The module extends UMCF with SAT-specific fields:

```json
{
  "$schema": "umcf-schema.json",
  "version": "1.1.0",
  "extensions": {
    "sat": {
      "testVersion": "digital-2024",
      "section": "reading_writing",
      "domain": "craft_and_structure",
      "skill": "words_in_context",
      "difficultyIRT": {
        "b": 0.5,
        "a": 1.2
      },
      "timeTarget": 45,
      "strategyTags": ["context_clues", "connotation"],
      "commonErrors": ["secondary_meaning_trap"],
      "adaptiveLevel": "module_1",
      "passageType": "science"
    }
  }
}
```

### Curriculum Structure

```
sat-curriculum/
├── curriculum.json                 # Root manifest
├── reading-writing/
│   ├── craft-and-structure/
│   │   ├── words-in-context.json
│   │   ├── text-structure.json
│   │   └── cross-text.json
│   ├── information-and-ideas/
│   │   ├── central-ideas.json
│   │   ├── command-of-evidence.json
│   │   └── inferences.json
│   ├── standard-english-conventions/
│   │   ├── boundaries.json
│   │   └── form-structure-sense.json
│   └── expression-of-ideas/
│       ├── rhetorical-synthesis.json
│       └── transitions.json
├── math/
│   ├── algebra/
│   │   ├── linear-equations.json
│   │   ├── linear-inequalities.json
│   │   ├── systems.json
│   │   └── linear-functions.json
│   ├── advanced-math/
│   │   ├── equivalent-expressions.json
│   │   ├── quadratics.json
│   │   ├── exponentials.json
│   │   └── nonlinear-systems.json
│   ├── problem-solving-data/
│   │   ├── ratios-proportions.json
│   │   ├── percentages.json
│   │   ├── statistics.json
│   │   └── probability.json
│   └── geometry-trig/
│       ├── area-volume.json
│       ├── triangles.json
│       ├── circles.json
│       └── right-triangle-trig.json
├── strategies/
│   ├── question-triage.json
│   ├── process-of-elimination.json
│   ├── timing-strategies.json
│   └── section-specific/
├── psychology/
│   ├── anxiety-management.json
│   ├── focus-training.json
│   └── mistake-recovery.json
└── practice-tests/
    ├── diagnostic/
    ├── practice-1/
    └── [additional tests]/
```

### Sample Content Node

```json
{
  "id": "sat-math-algebra-linear-001",
  "nodeType": "segment",
  "title": "Solving Linear Equations",
  "description": "Techniques for solving single-variable linear equations",
  "spokenText": "Linear equations are fundamental to SAT math. Let's master solving them efficiently.",
  "extensions": {
    "sat": {
      "testVersion": "digital-2024",
      "section": "math",
      "domain": "algebra",
      "skill": "linear_equations_one_variable",
      "difficultyRange": { "min": -1.5, "max": 1.0 },
      "timeTarget": 60,
      "weight": 0.08,
      "strategyTags": ["isolation", "distribution", "combining_terms"],
      "commonErrors": ["sign_errors", "distribution_errors"],
      "collegeBoardAlignment": "PAM.A.1"
    }
  },
  "learningObjectives": [
    {
      "statement": "Solve linear equations with variables on one side",
      "bloomLevel": "apply"
    },
    {
      "statement": "Solve linear equations with variables on both sides",
      "bloomLevel": "apply"
    },
    {
      "statement": "Solve linear equations with fractions and decimals",
      "bloomLevel": "apply"
    }
  ],
  "content": {
    "conceptExplanation": "A linear equation contains a variable raised to the first power...",
    "workedExamples": [
      {
        "problem": "Solve: 3x + 7 = 22",
        "steps": [
          "Subtract 7 from both sides: 3x = 15",
          "Divide both sides by 3: x = 5"
        ],
        "solution": "x = 5",
        "verification": "Check: 3(5) + 7 = 15 + 7 = 22 ✓"
      }
    ],
    "strategyTips": [
      "Always perform the same operation on both sides",
      "Simplify each side before solving",
      "Check your answer by substituting back"
    ]
  },
  "assessments": [
    {
      "id": "linear-eq-001",
      "type": "choice",
      "stem": "What is the solution to 2x - 5 = 11?",
      "options": [
        { "id": "a", "text": "x = 3" },
        { "id": "b", "text": "x = 8", "correct": true },
        { "id": "c", "text": "x = 6" },
        { "id": "d", "text": "x = 16" }
      ],
      "extensions": {
        "sat": {
          "difficultyIRT": { "b": -1.0, "a": 1.0 },
          "timeTarget": 30,
          "adaptiveLevel": "module_1",
          "errorAnalysis": {
            "a": "Subtracted instead of adding",
            "c": "Arithmetic error",
            "d": "Forgot to divide by coefficient"
          }
        }
      }
    }
  ],
  "retrievalConfig": {
    "keyConceptForRetrieval": true,
    "difficulty": "easy",
    "retrievalPrompts": [
      "How do you isolate a variable in a linear equation?",
      "What's the first step to solve 4x + 3 = 19?"
    ],
    "spacingAlgorithm": "sm2",
    "initialInterval": "P1D",
    "maxInterval": "P14D"
  }
}
```

---

## Implementation Roadmap

### Phase 1: Content Foundation (Weeks 1-4)

**Deliverables:**
- [ ] SAT UMCF schema extensions
- [ ] Complete skill taxonomy (RW + Math)
- [ ] Core content for all domains
- [ ] Basic question bank (500+ questions)

**Technical Tasks:**
- Extend `UMCFParser` for SAT extensions
- Create `SATEngine` actor
- Implement domain mastery tracking
- Build initial question bank with IRT parameters

### Phase 2: Adaptive Practice (Weeks 5-8)

**Deliverables:**
- [ ] MST simulation engine
- [ ] Module 1 → Module 2 routing
- [ ] Difficulty calibration
- [ ] Score prediction model

**Technical Tasks:**
- Implement IRT-based question selection
- Build adaptive routing logic
- Create score estimation algorithm
- Integrate with practice session flow

### Phase 3: Strategy Training (Weeks 9-12)

**Deliverables:**
- [ ] Strategy curriculum
- [ ] Question type identification training
- [ ] POE skill building
- [ ] Strategy application tracking

**Technical Tasks:**
- Create strategy content nodes
- Build strategy practice modes
- Implement strategy effectiveness tracking
- Integrate strategy with content

### Phase 4: Timing System (Weeks 13-16)

**Deliverables:**
- [ ] Personalized pacing profiles
- [ ] Timing training progression
- [ ] Time banking visualization
- [ ] Pacing recommendations

**Technical Tasks:**
- Build timing analytics engine
- Create pacing profile generator
- Implement timing training modes
- Add real-time pacing feedback

### Phase 5: Psychology Module (Weeks 17-20)

**Deliverables:**
- [ ] Anxiety assessment and tracking
- [ ] Relaxation technique library
- [ ] Focus training progression
- [ ] Confidence calibration

**Technical Tasks:**
- Create psychology content modules
- Build anxiety/focus tracking
- Implement technique practice modes
- Integrate with overall performance

### Phase 6: Full Integration (Weeks 21-24)

**Deliverables:**
- [ ] Complete practice test simulation
- [ ] Comprehensive analytics dashboard
- [ ] Personalized study plans
- [ ] Progress reports for students/parents

**Technical Tasks:**
- Full end-to-end test simulation
- Dashboard implementation
- Study plan generator
- Report generation system

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Content Coverage | 100% of SAT skills | Curriculum audit |
| Question Bank Size | 2,000+ questions | Database count |
| Adaptive Accuracy | Within 30 points of real score | Prediction vs. actual |
| User Engagement | 4+ sessions/week | Usage analytics |
| Score Improvement | Average 100+ point gain | Pre/post comparison |
| Strategy Adoption | 80%+ apply strategies consistently | Strategy tracking |
| Anxiety Reduction | 50%+ report lower anxiety | Self-assessment |
| Completion Rate | 70%+ complete study plans | Progress tracking |

---

## Appendices

### A. Digital SAT Official Resources

| Resource | URL | Purpose |
|----------|-----|---------|
| College Board SAT | collegeboard.org/sat | Official information |
| Bluebook Practice App | Available on app stores | Official practice |
| Khan Academy SAT Prep | khanacademy.org/sat | Free practice (older format) |

### B. Score Conversion

The Digital SAT uses a scaled score:

| Section | Raw Score Range | Scaled Score Range |
|---------|-----------------|-------------------|
| Reading & Writing | 0-54 | 200-800 |
| Math | 0-44 | 200-800 |
| Total | - | 400-1600 |

### C. Related Documentation

- [UMCF Specification](/curriculum/spec/UMCF_SPECIFICATION.md)
- [SAT UMCF Extensions](/curriculum/spec/SAT_EXTENSIONS.md)
- [Progress Tracker](/UnaMentis/Core/Curriculum/ProgressTracker.swift)
- [iOS Style Guide](/docs/ios/IOS_STYLE_GUIDE.md)

---

*Document Version: 1.0.0*
*Last Updated: January 2025*
*Author: UnaMentis Development Team*
