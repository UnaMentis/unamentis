# Knowledge Bowl Module

**Version:** 1.0.0
**Last Updated:** 2026-01-25
**Reference Platform:** iOS (Swift/SwiftUI)

---

## Overview

The Knowledge Bowl module provides specialized training for academic quiz bowl competitions. It supports multiple practice modes, team coordination, and analytics to help students prepare for regional and national competitions.

**Key Differentiators:**
- Voice-first design with on-device TTS/STT for offline practice
- 3-tier answer validation (phonetic, semantic, LLM)
- Regional competition rule compliance (Colorado, Minnesota, Washington)
- Team-based training with domain assignments

---

## Navigation Structure

```
Knowledge Bowl Dashboard
├── Quick Start
│   ├── Written Practice (MCQ)
│   └── Oral Practice (Voice)
├── Competition Training
│   ├── Match Simulation
│   ├── Conference Training
│   ├── Domain Drill
│   └── Rebound Training
├── Session History
├── Statistics Summary
├── Region Selector
└── Settings / Help
```

---

## Views

### 1. Dashboard View (KBDashboardView)

**Purpose:** Main entry point for Knowledge Bowl module

**Layout:**
```
┌─────────────────────────────────────────┐
│  ← [Help]   Knowledge Bowl   [Settings] │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────────┐│
│  │         🏆 Knowledge Bowl           ││
│  │      {region} • {question_count}    ││
│  └─────────────────────────────────────┘│
│                                          │
│  Quick Start                             │
│  ┌──────────────┐  ┌──────────────┐     │
│  │  ✏️ Written  │  │  🎤 Oral     │     │
│  │   Practice   │  │   Practice   │     │
│  └──────────────┘  └──────────────┘     │
│                                          │
│  Competition Training                    │
│  ┌──────────────┐  ┌──────────────┐     │
│  │ ⚔️ Match    │  │ 🎪 Conference│     │
│  │  Simulation  │  │   Training   │     │
│  └──────────────┘  └──────────────┘     │
│  ┌──────────────┐  ┌──────────────┐     │
│  │ 🎯 Domain   │  │ ↩️ Rebound   │     │
│  │    Drill     │  │   Training   │     │
│  └──────────────┘  └──────────────┘     │
│                                          │
│  Recent Sessions                         │
│  ┌─────────────────────────────────────┐│
│  │ Written • 85% • 15 questions        ││
│  │ 2 hours ago                         ││
│  └─────────────────────────────────────┘│
│                                          │
│  Statistics                              │
│  ┌─────────────────────────────────────┐│
│  │ Accuracy: 82%  │  Streak: 5 days   ││
│  │ Total Qs: 450  │  Mastered: 8/12   ││
│  └─────────────────────────────────────┘│
│                                          │
│  Region: [Colorado ▼]                    │
└─────────────────────────────────────────┘
```

**State:**
- `selectedRegion: KBRegion` - Active competition rules
- `recentSessions: [KBSession]` - Last 5 sessions
- `statistics: KBStatistics` - Aggregated performance data

**Interactions:**
- Tap Quick Start buttons to launch practice modes
- Tap Competition Training buttons for advanced modes
- Region picker updates validation rules
- Settings button opens KBSettingsView
- Help button opens KBHelpSheet

---

### 2. Written Session View (KBWrittenSessionView)

**Purpose:** Multiple choice practice mode

**Layout:**
```
┌─────────────────────────────────────────┐
│  ← End           Written          12/20 │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────────┐│
│  │ Science                   ⭐⭐⭐    ││
│  │                                     ││
│  │ What is the chemical symbol for    ││
│  │ gold?                               ││
│  └─────────────────────────────────────┘│
│                                          │
│  ┌─────────────────────────────────────┐│
│  │ A) Ag                               ││
│  └─────────────────────────────────────┘│
│  ┌─────────────────────────────────────┐│
│  │ B) Au                    ← Selected ││
│  └─────────────────────────────────────┘│
│  ┌─────────────────────────────────────┐│
│  │ C) Go                               ││
│  └─────────────────────────────────────┘│
│  ┌─────────────────────────────────────┐│
│  │ D) Gd                               ││
│  └─────────────────────────────────────┘│
│                                          │
│  ╔═════════════════════════════════════╗│
│  ║        [Submit Answer]              ║│
│  ╚═════════════════════════════════════╝│
│                                          │
│  ┌── Progress ──────────────────────┐  │
│  │ ████████████░░░░░░░░  60%        │  │
│  └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**States:**
- `answering` - User selecting answer
- `feedback` - Showing correct/incorrect with explanation
- `transitioning` - Moving to next question

**Features:**
- Domain badge with difficulty stars (1-5)
- Randomized answer order
- Immediate feedback with explanations
- Progress bar showing session completion
- Timer (optional, configurable)

---

### 3. Oral Session View (KBOralSessionView)

**Purpose:** Voice-based practice mimicking competition format

**Layout:**
```
┌─────────────────────────────────────────┐
│  ← End            Oral            8/15  │
├─────────────────────────────────────────┤
│                                          │
│         ┌───────────────────┐           │
│         │   🎤              │           │
│         │   Listening...    │           │
│         │   ████░░░░░░      │           │
│         └───────────────────┘           │
│                                          │
│  ┌─────────────────────────────────────┐│
│  │ Literature                ⭐⭐       ││
│  │                                     ││
│  │ Who wrote "Pride and Prejudice"?   ││
│  │                                     ││
│  │ 🔊 [Replay Question]               ││
│  └─────────────────────────────────────┘│
│                                          │
│  Your answer:                            │
│  ┌─────────────────────────────────────┐│
│  │ "Jane Austen"                       ││
│  └─────────────────────────────────────┘│
│                                          │
│  ┌──────────┐  ┌──────────┐             │
│  │ ✓ Submit │  │ ⟳ Retry  │             │
│  └──────────┘  └──────────┘             │
│                                          │
│  Timer: 0:05                             │
└─────────────────────────────────────────┘
```

**States:**
- `readingQuestion` - TTS reading question aloud
- `listening` - Recording user's spoken answer
- `processing` - Validating answer through 3-tier system
- `feedback` - Showing result with validation details

**Voice Features:**
- On-device TTS via Kyutai Pocket (primary) or Apple TTS (fallback)
- On-device STT via Apple Speech
- Replay question button
- Visual speech level indicator
- Configurable timer (5-15 seconds per question)

---

### 4. Domain Drill View (KBDomainDrillView)

**Purpose:** Focused practice on a single domain with progressive difficulty

**Layout (Setup):**
```
┌─────────────────────────────────────────┐
│              Domain Drill               │
├─────────────────────────────────────────┤
│  Select Domain                           │
│  ┌────────┐ ┌────────┐ ┌────────┐      │
│  │Science │ │  Math  │ │  Lit   │      │
│  └────────┘ └────────┘ └────────┘      │
│  ┌────────┐ ┌────────┐ ┌────────┐      │
│  │History │ │  Arts  │ │ Events │      │
│  └────────┘ └────────┘ └────────┘      │
│  ┌────────┐ ┌────────┐ ┌────────┐      │
│  │Language│ │Religion│ │PopCult │      │
│  └────────┘ └────────┘ └────────┘      │
│  ┌────────┐ ┌────────┐ ┌────────┐      │
│  │  Tech  │ │Social  │ │  Misc  │      │
│  └────────┘ └────────┘ └────────┘      │
│                                          │
│  Settings                                │
│  ───────────────────────────────────    │
│  Questions: 15       [────●────]        │
│  ☑ Progressive Difficulty               │
│  ☐ Audio Mode                           │
│                                          │
│  ╔═════════════════════════════════════╗│
│  ║          [Start Drill]              ║│
│  ╚═════════════════════════════════════╝│
└─────────────────────────────────────────┘
```

**Features:**
- Domain grid with 12 subjects (3x4)
- Progressive difficulty: starts easy, increases on correct answers
- Question count slider (5-30)
- Optional audio mode (uses TTS/STT)
- Results show performance by difficulty level

---

### 5. Match Simulation View (KBMatchSimulationView)

**Purpose:** Simulate actual competition match experience

**Layout:**
```
┌─────────────────────────────────────────┐
│            Match Simulation             │
├─────────────────────────────────────────┤
│  Round 2 of 4           Question 5/10   │
│                                          │
│  ┌─────────────────────────────────────┐│
│  │ You: 45 pts    │    Opponent: 35 pts││
│  └─────────────────────────────────────┘│
│                                          │
│  ┌─────────────────────────────────────┐│
│  │ Mathematics               ⭐⭐⭐⭐   ││
│  │                                     ││
│  │ What is the derivative of sin(x)?  ││
│  └─────────────────────────────────────┘│
│                                          │
│  ╔═════════════════════════════════════╗│
│  ║           [🔔 BUZZ IN]              ║│
│  ╚═════════════════════════════════════╝│
│                                          │
│  Timer: 0:08                             │
│                                          │
│  Round Progress:                         │
│  █████░░░░░ 50%                         │
└─────────────────────────────────────────┘
```

**Features:**
- Multi-round format (configurable 2-4 rounds)
- Simulated opponent with configurable skill level
- Buzz-in mechanic with timing
- Scoring based on regional rules (Colorado: 15 pts, Minnesota: 10 pts)
- Point deduction for incorrect buzzes
- Round summaries between rounds
- Final match statistics

---

### 6. Conference Training View (KBConferenceTrainingView)

**Purpose:** Multi-room conference format practice

**Features:**
- Simulates moving between competition rooms
- Room assignment and scheduling
- Mixed domain questions per room
- Conference-style timing (60-second question sets)
- Team position rotation

---

### 7. Rebound Training View (KBReboundTrainingView)

**Purpose:** Practice capitalizing on opponent misses

**Layout (Active):**
```
┌─────────────────────────────────────────┐
│           Rebound Training              │
├─────────────────────────────────────────┤
│                                          │
│  ┌─────────────────────────────────────┐│
│  │ Opponent buzzes...                  ││
│  │ ⏳ Answering...                     ││
│  └─────────────────────────────────────┘│
│                                          │
│  ┌─────────────────────────────────────┐│
│  │ Science                             ││
│  │                                     ││
│  │ What planet is known as the        ││
│  │ "Red Planet"?                       ││
│  └─────────────────────────────────────┘│
│                                          │
│  ❌ Opponent answered: "Venus"          │
│     (Incorrect!)                         │
│                                          │
│  ┌─────────────────────────────────────┐│
│  │ 🎯 REBOUND OPPORTUNITY!             ││
│  │ Timer: 0:03                         ││
│  │ [Type your answer...]               ││
│  └─────────────────────────────────────┘│
│                                          │
│  Stats: Rebounds: 5/8 (62.5%)            │
└─────────────────────────────────────────┘
```

**Features:**
- Simulated opponent buzz-ins and answers
- Configurable opponent error rate (30-70%)
- Rebound timer (3-5 seconds based on region)
- Tracks rebound success rate
- Teaches strategic patience

**Practice Scenarios:**
- Standard rebound (opponent incorrect)
- Quick rebound (partial answer given)
- No rebound (opponent correct)
- Double rebound (second opponent also misses)

---

### 8. Progress View (KBProgressView)

**Purpose:** Overall progress and mastery tracking

**Sections:**
- Domain mastery bars (12 domains)
- Weekly activity chart
- Streak calendar
- Question count by difficulty
- Average response time trends

---

### 9. Domain Mastery View (KBDomainMasteryView)

**Purpose:** Detailed breakdown by subject domain

**Layout:**
```
┌─────────────────────────────────────────┐
│           Domain Mastery                │
├─────────────────────────────────────────┤
│  Science                    85% ████▓░  │
│  Mathematics                72% ███▓░░  │
│  Literature                 90% █████░  │
│  History                    68% ███░░░  │
│  Social Studies            55% ██▓░░░  │
│  Fine Arts                 45% ██░░░░  │
│  Current Events            30% █▓░░░░  │
│  Language                  75% ███▓░░  │
│  Religion/Philosophy       40% ██░░░░  │
│  Pop Culture               65% ███░░░  │
│  Technology                80% ████░░  │
│  Miscellaneous             50% ██▓░░░  │
│                                          │
│  Tap domain for detailed breakdown       │
└─────────────────────────────────────────┘
```

**Features:**
- Progress bars with mastery percentage
- Tap to expand subcategory breakdown
- Suggested focus areas
- Question bank coverage indicator

---

### 10. Trend Chart View (KBTrendChartView)

**Purpose:** Performance trends over time

**Chart Types:**
- Accuracy trend (7-day, 30-day, all-time)
- Response time trend
- Domain balance radar chart
- Session frequency histogram

---

### 11. Help Sheet (KBHelpSheet)

**Purpose:** Competition rules and strategy guide

**Sections:**
- Competition format overview
- Scoring rules (by region)
- Buzzer strategy tips
- Domain study priorities
- Answer validation explanation
- Team coordination guidance

---

### 12. Settings View (KBSettingsView)

**Purpose:** Module configuration

**Settings:**
```
┌─────────────────────────────────────────┐
│           Knowledge Bowl Settings        │
├─────────────────────────────────────────┤
│  Competition Region                      │
│  ┌─────────────────────────────────────┐│
│  │ ○ Colorado (15 pts, strict)         ││
│  │ ● Minnesota (10 pts, moderate)      ││
│  │ ○ Washington (10 pts, lenient)      ││
│  └─────────────────────────────────────┘│
│                                          │
│  Answer Validation                       │
│  ───────────────────────────────────    │
│  Tier 1 (Algorithmic)         [Always]  │
│  Tier 2 (Semantic Embeddings)    [On]   │
│  Tier 3 (LLM Validation)        [Off]   │
│                                          │
│  Voice Settings                          │
│  ───────────────────────────────────    │
│  TTS Provider:    [Kyutai Pocket ▼]     │
│  STT Provider:    [Apple Speech  ▼]     │
│  Reading Speed:   [────●────] 1.0x      │
│                                          │
│  Timer Settings                          │
│  ───────────────────────────────────    │
│  Question Timer:  [☑] 10 seconds        │
│  Show Countdown:  [☑]                   │
│                                          │
│  Team                                    │
│  ───────────────────────────────────    │
│  [Manage Team →]                        │
└─────────────────────────────────────────┘
```

---

### 13. Enhanced Validation Setup View (KBEnhancedValidationSetupView)

**Purpose:** Configure and test answer validation tiers

**Features:**
- Tier explanation with accuracy percentages
- Download status for Tier 2 embeddings model (~80MB)
- Toggle for Tier 3 LLM validation (admin-controlled)
- Test mode to validate sample answers
- Model resource usage display

---

## Team Features

### Team Profile

**Purpose:** Manage team composition and domain assignments

**Data Model:**
```
KBTeamProfile
├── id: UUID
├── teamCode: String (6 chars, shareable)
├── name: String
├── region: KBRegion
├── members: [KBTeamMember]
├── domainAssignments: [KBDomainAssignment]
├── isCaptain: Bool
└── timestamps
```

**Member Model:**
```
KBTeamMember
├── id: UUID
├── name: String
├── role: captain | member
├── primaryDomain: KBDomain?
├── secondaryDomain: KBDomain?
└── isActive: Bool
```

**Features:**
- Team code sharing for joining
- Domain assignment matrix
- Coverage analysis (which domains lack coverage)
- Member statistics integration
- Export/import for backup

---

## 12 Subject Domains

| Domain | Weight | Example Subcategories |
|--------|--------|----------------------|
| Science | High | Biology, Chemistry, Physics, Earth Science |
| Mathematics | High | Algebra, Geometry, Calculus, Statistics |
| Literature | High | American, British, World, Poetry |
| History | High | US, World, Ancient, Modern |
| Social Studies | Medium | Geography, Government, Economics |
| Fine Arts | Medium | Visual Arts, Music, Theater, Architecture |
| Current Events | Medium | Politics, Technology, Culture |
| Language | Medium | Grammar, Vocabulary, Etymology |
| Religion/Philosophy | Low | World Religions, Philosophy, Ethics |
| Pop Culture | Low | Entertainment, Media, Games |
| Technology | Low | Inventions, Computing, Engineering |
| Miscellaneous | Low | General Trivia, Cross-domain |

---

## Regional Competition Rules

| Rule | Colorado | Minnesota | Washington |
|------|----------|-----------|------------|
| Points per correct | 15 | 10 | 10 |
| Points deducted for incorrect | -5 | 0 | 0 |
| Answer strictness | Strict | Moderate | Lenient |
| Pronunciation tolerance | Low | Medium | High |
| Partial credit | No | Sometimes | Yes |

---

## Answer Validation System

### 3-Tier Architecture

**Tier 1: Algorithmic (All Devices)**
- Levenshtein fuzzy matching
- Double Metaphone phonetic matching
- N-gram similarity (character + word)
- Token-based similarity (Jaccard + Dice)
- Domain-specific synonyms (~650 entries)
- Apple NL framework linguistic matching
- **Accuracy:** 85-90%

**Tier 2: Semantic Embeddings (iPhone XS+)**
- all-MiniLM-L6-v2 model (~80MB optional download)
- Cosine similarity threshold (0.85)
- Context-aware matching
- **Accuracy:** 92-95%

**Tier 3: LLM Validation (iPhone 12+)**
- Open-source LLM (Llama 3.2 1B)
- ~1.5GB model download
- Admin-controlled enablement
- **Accuracy:** 95-98%

---

## Accessibility

### VoiceOver Support
- All practice modes fully accessible
- Question text read aloud automatically
- Answer options with indices ("Option A: Ag")
- Timer announcements
- Result feedback with haptics

### Dynamic Type
- All text scales appropriately
- Button minimum sizes maintained
- Card layouts adapt to larger text

### Reduce Motion
- Progress animations simplified
- Transition effects reduced
- Focus on content over decoration

---

## Offline Capability

The Knowledge Bowl module is designed for offline use:

| Feature | Offline | Notes |
|---------|---------|-------|
| Written Practice | Yes | Questions bundled |
| Oral Practice | Yes | On-device TTS/STT |
| Domain Drill | Yes | All content local |
| Match Simulation | Yes | Simulated opponent |
| Answer Validation T1 | Yes | Algorithmic |
| Answer Validation T2 | Yes | After model download |
| Answer Validation T3 | Yes | After model download |
| Statistics | Yes | Local storage |
| Team Sync | No | Requires network |

---

## Related Documentation

- [Knowledge Bowl Module Spec](../modules/KNOWLEDGE_BOWL_MODULE_SPEC.md) - Complete technical specification
- [Knowledge Bowl Answer Validation](../modules/KNOWLEDGE_BOWL_ANSWER_VALIDATION.md) - Validation system details
- [Knowledge Bowl API](../api-spec/09-KNOWLEDGE-BOWL.md) - Server API for pack management
- [Settings](07-SETTINGS.md) - App-level settings integration
