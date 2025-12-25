# UnaMentis iOS - Project Overview

## Purpose

UnaMentis is an AI-powered voice tutoring app for iOS that enables extended (60-90+ minute) educational conversations. Built to address limitations in existing voice AI (like ChatGPT's Advanced Voice Mode), it provides low-latency, natural voice interaction with curriculum-driven learning.

**Target:** iPhone 15 Pro+ / 16/17 Pro Max
**Goal:** Sub-500ms end-to-end latency with natural interruption handling

**Development Model:** 100% AI-assisted development (Claude Code, Cursor, Windsurf). The entire app (Phases 1-5 of a 12-week roadmap) was implemented in approximately 5 hours, demonstrating ~200x speedup over traditional development.

---

## Architecture

### Voice Pipeline

All components are **protocol-based and swappable**:

| Component | On-Device | Cloud | Self-Hosted |
|-----------|-----------|-------|-------------|
| **STT** | Apple Speech, GLM-ASR-Nano | Deepgram Nova-3, AssemblyAI, OpenAI Whisper | GLM-ASR server |
| **TTS** | Apple TTS | ElevenLabs Turbo v2.5, Deepgram Aura-2 | Piper TTS |
| **LLM** | llama.cpp (experimental) | Anthropic Claude, OpenAI GPT-4o | Ollama, llama.cpp server, vLLM |
| **VAD** | Silero (CoreML on Neural Engine) | - | - |
| **Embeddings** | - | OpenAI text-embedding-3-small | - |

### Graceful Degradation

The app is designed to work on any device, even without API keys or servers. See [FALLBACK_ARCHITECTURE.md](FALLBACK_ARCHITECTURE.md) for complete details.

| Component | Built-in Fallback | Always Available |
|-----------|-------------------|------------------|
| **STT** | Apple Speech | Yes |
| **TTS** | Apple TTS | Yes |
| **LLM** | OnDeviceLLMService | Requires bundled models |
| **VAD** | RMS-based detection | Yes |

### STT Provider Router

Intelligent automatic failover system for speech-to-text:
- Primary: On-device STT (GLM-ASR-Nano or Apple Speech)
- Fallback: Server-based STT (GLM-ASR server)
- Final fallback: Cloud providers (Deepgram, AssemblyAI)
- Ultimate fallback: Apple Speech (always available)

### LLM Routing (Patch Panel)

A switchboard system for routing any LLM call to any endpoint with manual and automatic modes:

**Routing Priority:**
1. Global override (debugging)
2. Manual task-type override
3. Auto-routing rules (thermal, network, cost conditions)
4. Default routes per task type
5. Fallback chain

**20+ Task Types:**
- Tutoring: tutoringResponse, understandingCheck, socraticQuestion, misconceptionCorrection
- Content: explanationGeneration, exampleGeneration, analogyGeneration, rephrasing, simplification
- Navigation: tangentExploration, topicTransition, sessionSummary
- Classification: intentClassification, sentimentAnalysis, topicClassification
- Simple: acknowledgment, fillerResponse, navigationConfirmation

**Condition-Based Routing:**
- Device conditions: thermal state, memory pressure, battery level, device tier
- Network conditions: type (wifi/cellular/none), latency thresholds
- Cost conditions: session budget, task cost estimates
- Time conditions: session duration, time of day

### Session Flow

```
Microphone -> AudioEngine -> VAD -> STT (streaming)
    -> SessionManager (turn-taking, context)
    -> PatchPanel (route to LLM endpoint)
    -> LLM (streaming) -> TTS (streaming)
    -> AudioEngine -> Speaker
```

**Session States:** Idle -> User Speaking -> Processing User Utterance -> AI Thinking -> AI Speaking -> (loop)

**TTS Playback Optimization:**
- 5 presets: default, lowLatency, conservative, disabled, custom
- Prefetching and multi-buffer scheduling
- Configurable inter-segment silences

---

## Self-Hosted Server Support

UnaMentis can connect to local/LAN servers for zero-cost inference:

| Server Type | Port | Purpose |
|-------------|------|---------|
| Ollama | 11434 | LLM inference (primary target) |
| llama.cpp | 8080 | LLM inference |
| vLLM | 8000 | High-throughput LLM |
| GLM-ASR server | 11401 | STT (with WebSocket streaming) |
| Piper TTS | 11402 | TTS |

**Features:**
- Auto-discovery of available models/voices
- Health monitoring with automatic fallback
- OpenAI-compatible API support

---

## Curriculum System (UMLCF)

**UnaMentis Markup Language Curriculum Format** - A JSON-based specification designed for conversational AI tutoring.

### Specification Status: Complete (v1.0.0)
- JSON Schema: 1,905 lines, 152 fields
- Standards alignment: IEEE LOM, LRMI, Dublin Core, SCORM, xAPI, CASE, QTI, Open Badges
- UMLCF-native fields: 70 (46%) for tutoring-specific needs

### Structure
```
Curriculum
+-- Metadata (title, version, language, lifecycle, rights, compliance)
+-- Content[] (unlimited nesting depth)
|   +-- Node types: curriculum, unit, module, topic, subtopic, lesson, section, segment
|   +-- Learning objectives (Bloom's taxonomy aligned)
|   +-- Transcript segments with stopping points
|   +-- Alternative explanations (simpler, technical, analogy)
|   +-- Misconceptions + remediation (trigger phrases)
|   +-- Assessments (choice, multiple_choice, text_entry, true_false)
|   +-- Media (images, diagrams, equations, videos, slide decks)
|   +-- Speaking notes for TTS (pace, emphasis, emotional tone)
+-- Glossary (terms with spoken definitions)
```

### Content Depth Levels
| Level | Duration | Purpose |
|-------|----------|---------|
| Overview | 2-5 min | Intuition only |
| Introductory | 5-15 min | Basic concepts |
| Intermediate | 15-30 min | Moderate detail |
| Advanced | 30-60 min | In-depth with derivations |
| Graduate | 60-120 min | Comprehensive |
| Research | 90-180 min | Paper-level depth |

### Visual Asset Support
- **Embedded media types:** image, diagram, equation, chart, slideImage, slideDeck, video
- **Segment timing:** Controls when visuals appear during playback (persistent, highlight, popup, inline)
- **Reference media:** Optional supplementary materials with keyword matching
- **Accessibility:** Required alt text, audio descriptions for all visual content
- **Equation format:** LaTeX notation with spoken description

### Importers (Designed, Implementation In Progress)

| Source | Format | Target Audience | Status |
|--------|--------|-----------------|--------|
| **CK-12 FlexBooks** | EPUB, PDF, HTML | K-12 (8th grade focus) | Spec complete |
| **Fast.ai** | Jupyter notebooks | Collegiate, AI/ML | Spec complete |
| **MIT OpenCourseWare** | ZIP packages (HTML, PDF, video) | Collegiate | Spec + implementation started |
| **Stanford SEE** | PDF, transcripts | Engineering | Spec complete |
| **Raw JSON/YAML** | Native UMLCF | Any | Ready |
| **IMSCC** | IMS Common Cartridge | LMS interop | Planned |

**MIT OCW Implementation:**
- Catalog of 247 courses loaded
- Course browser with search/filter
- Import job system with progress tracking
- License preservation (CC-BY-NC-SA 4.0)

### AI Enrichment Pipeline (7 Stages)

1. **Content Analysis** - Readability metrics, domain detection, quality indicators
2. **Structure Inference** - Topic boundaries, hierarchical grouping
3. **Content Segmentation** - Meta-chunking based boundary detection
4. **Learning Objective Extraction** - Bloom's taxonomy alignment
5. **Assessment Generation** - Question generation with SRL + LLM
6. **Tutoring Enhancement** - Spoken text, misconceptions, glossary extraction
7. **Knowledge Graph** - Concept extraction, Wikidata linking, prerequisites

---

## Data Persistence

**Core Data entities (7 total):**
- `Curriculum` - Course containers
- `Topic` - Hierarchical learning units
- `Session` - Recorded conversations with transcripts
- `TopicProgress` - Time spent, mastery scores
- `TranscriptEntry` - Conversation history
- `Document` - Imported curriculum documents
- `VisualAsset` - Images, diagrams, equations linked to topics

---

## Server Infrastructure

### Operations Console (Port 3000)
**Purpose:** Backend infrastructure monitoring (DevOps focus)
**Tech:** Next.js/React with TypeScript, Tailwind CSS

- System health monitoring (CPU, memory, thermal, battery)
- Service status dashboard (Ollama, VibeVoice, Piper, Gateway)
- Power/idle management profiles
- Performance metrics (E2E latency, STT/LLM/TTS latencies, costs)
- Logs and diagnostics with real-time filtering
- Client connection monitoring
- Model management

### Management Console (Port 8766)
**Purpose:** Application management and content administration
**Tech:** Python/aiohttp with vanilla JavaScript frontend

- **Curriculum management:** Import, browse, edit, delete
- **Source Browser:** Discover courses from MIT OCW, Stanford SEE, CK-12, Fast.ai
- **Import Jobs:** Progress tracking, cancellation, error handling
- **Visual asset management:** Curriculum images and diagrams
- **AI enrichment pipeline:** 7-stage processing with progress
- **User progress tracking:** Analytics and mastery data
- **Diagnostic logging:** Structured real-time logs

### Import Pipeline Architecture

**Plugin System:**
- Discovery via Python entry points (PEP 621)
- Base class: `CurriculumSourceHandler`
- Async-native I/O operations

**Pipeline Stages:**
1. Download - Fetch course materials
2. Validate - Check completeness and format
3. Extract - Parse into intermediate structure
4. Enrich - AI processing (optional)
5. Generate - Transform to UMLCF
6. Store - Save to curriculum database

**Storage Backends:**
- FileSystem (development)
- PostgreSQL with JSON caching (production)

---

## iOS App Structure

### Core Components

```
UnaMentis/
+-- Core/
|   +-- Audio/           # AudioEngine, VAD integration, thermal management
|   +-- Config/          # APIKeyManager (Keychain), ServerConfigManager
|   +-- Curriculum/      # CurriculumEngine, ProgressTracker, UMLCFParser
|   +-- Logging/         # RemoteLogHandler
|   +-- Persistence/     # PersistenceController, 7 Core Data entities
|   +-- Routing/         # PatchPanelService, LLMEndpoint, RoutingTable
|   +-- Session/         # SessionManager (state machine, TTS config)
|   +-- Telemetry/       # TelemetryEngine (latency, cost, events)
+-- Services/
|   +-- LLM/             # OpenAI, Anthropic, Self-Hosted, On-Device, Mock
|   +-- STT/             # AssemblyAI, Deepgram, Apple, GLM-ASR (server + device), Router
|   +-- TTS/             # ElevenLabs, Deepgram, Apple, Self-Hosted, PronunciationProcessor
|   +-- VAD/             # SileroVADService (CoreML)
|   +-- Embeddings/      # OpenAIEmbeddingService
|   +-- Curriculum/      # CurriculumService, VisualAssetCache, TranscriptStreamingService
|   +-- Protocols/       # LLMService, STTService, TTSService, VADService
+-- Intents/             # Siri & App Intents integration (iOS 16+)
|   +-- AppShortcutsProvider.swift   # Registers shortcuts with Siri
|   +-- StartLessonIntent.swift      # "Hey Siri, start a lesson"
|   +-- ResumeLearningIntent.swift   # "Hey Siri, resume my lesson"
|   +-- ShowProgressIntent.swift     # "Hey Siri, show my progress"
|   +-- CurriculumEntity.swift       # Exposes curricula to Siri
|   +-- TopicEntity.swift            # Exposes topics to Siri
+-- UI/
|   +-- Session/         # SessionView, VisualAssetView
|   +-- Curriculum/      # CurriculumView
|   +-- Settings/        # SettingsView, ServerSettingsView, APIProviderDetailView
|   +-- History/         # HistoryView
|   +-- Analytics/       # AnalyticsView
|   +-- Debug/           # DeviceMetricsView, DebugConversationTestView
```

### Service Counts
- **LLM Providers:** 5 (OpenAI, Anthropic, Self-Hosted, On-Device, Mock)
- **STT Providers:** 8 (AssemblyAI, Deepgram, Apple, GLM-ASR server, GLM-ASR on-device, Self-Hosted, Router, Health Monitor)
- **TTS Providers:** 5 (ElevenLabs, Deepgram, Apple, Self-Hosted, Pronunciation Processor)
- **UI Views:** 11 major views with supporting subviews
- **Total Swift Files:** 66+

---

## Current Status

### Complete
- All iOS services implemented (STT, TTS, LLM, VAD, Embeddings)
- Full UI (Session, Curriculum, History, Analytics, Settings, Debug)
- UMLCF 1.0 specification with JSON Schema (1,905 lines)
- 103+ unit tests, 16+ integration tests passing
- Telemetry, cost tracking, thermal management
- Self-hosted server discovery and health monitoring
- Patch Panel LLM routing system
- GLM-ASR implementation (server + on-device)
- STT Provider Router with automatic failover
- Visual asset support design
- Import architecture and MIT OCW importer started
- Operations Console (React/TypeScript)
- Management Console (Python/aiohttp)
- iOS Simulator MCP for AI-driven testing
- **Siri & App Intents integration** (voice commands, deep links)

### In Progress
- MIT OCW import pipeline implementation
- Visual asset caching optimization
- AI enrichment pipeline implementation
- Source browser UI completion

### Pending User Setup
- API key configuration (OpenAI, Anthropic, Deepgram, ElevenLabs, AssemblyAI)
- Physical device testing (iPhone 15 Pro+ / 16/17 Pro Max)
- On-device GLM-ASR model download (~2.4GB)
- Long-session stability validation (90+ minutes)
- Curriculum content creation

---

## Key Files

| Path | Purpose |
|------|---------|
| `UnaMentis/Core/Session/SessionManager.swift` | Orchestrates voice sessions, state machine |
| `UnaMentis/Core/Curriculum/CurriculumEngine.swift` | Curriculum context generation |
| `UnaMentis/Core/Routing/PatchPanelService.swift` | LLM endpoint routing |
| `UnaMentis/Services/STT/STTProviderRouter.swift` | STT failover routing |
| `UnaMentis/Services/LLM/SelfHostedLLMService.swift` | Ollama/llama.cpp integration |
| `UnaMentis/Services/STT/GLMASROnDeviceSTTService.swift` | On-device speech recognition |
| `curriculum/spec/umlcf-schema.json` | UMLCF JSON Schema (1,905 lines) |
| `curriculum/spec/UMLCF_SPECIFICATION.md` | Human-readable format spec |
| `curriculum/importers/IMPORTER_ARCHITECTURE.md` | Import system design |
| `curriculum/importers/AI_ENRICHMENT_PIPELINE.md` | 7-stage AI processing |
| `server/management/server.py` | Management Console backend |
| `server/importers/sources/mit_ocw.py` | MIT OCW course handler |
| `server/web/src/components/dashboard/` | Operations Console UI |

---

## Tech Stack

- **Swift 6.0** with strict concurrency (Actor isolation)
- **SwiftUI** for all UI
- **AVFoundation** for audio (AVAudioEngine)
- **CoreML** for on-device VAD
- **Core Data** for persistence
- **XCTest** with real services (mocks only for paid APIs)
- **Next.js/React** for Operations Console
- **Python/aiohttp** for Management Console
- **PostgreSQL** for curriculum database (production)

---

## Performance Targets

| Metric | Target |
|--------|--------|
| End-to-end latency | <500ms (median), <1000ms (P99) |
| STT latency | <300ms |
| LLM time-to-first-token | <500ms |
| TTS time-to-first-byte | <200ms |
| Session duration | 60-90+ minutes |
| Memory growth | <50MB over 90 minutes |

---

## Cost Targets

| Preset | Target |
|--------|--------|
| Balanced | <$3/hour |
| Cost-optimized | <$1.50/hour |

---

## Documentation

### Core Documentation
| Document | Purpose |
|----------|---------|
| [UnaMentis_TDD.md](UnaMentis_TDD.md) | Technical Design Document |
| [TASK_STATUS.md](TASK_STATUS.md) | Current task status and progress |
| [AGENTS.md](../AGENTS.md) | AI development guidelines, testing philosophy |
| [IOS_STYLE_GUIDE.md](IOS_STYLE_GUIDE.md) | Mandatory coding standards |

### Curriculum Documentation
| Document | Purpose |
|----------|---------|
| [curriculum/README.md](../curriculum/README.md) | Comprehensive UMLCF overview |
| [UMLCF_SPECIFICATION.md](../curriculum/spec/UMLCF_SPECIFICATION.md) | Format specification |
| [STANDARDS_TRACEABILITY.md](../curriculum/spec/STANDARDS_TRACEABILITY.md) | Standards field mapping |
| [IMPORTER_ARCHITECTURE.md](../curriculum/importers/IMPORTER_ARCHITECTURE.md) | Import system design |
| [AI_ENRICHMENT_PIPELINE.md](../curriculum/importers/AI_ENRICHMENT_PIPELINE.md) | 7-stage AI processing |

### Feature Documentation
| Document | Purpose |
|----------|---------|
| [APPLE_INTELLIGENCE.md](APPLE_INTELLIGENCE.md) | Apple Intelligence integration guide |
| [FALLBACK_ARCHITECTURE.md](FALLBACK_ARCHITECTURE.md) | Graceful degradation and service fallbacks |
| [PATCH_PANEL_ARCHITECTURE.md](PATCH_PANEL_ARCHITECTURE.md) | LLM routing system |
| [VISUAL_ASSET_SUPPORT.md](VISUAL_ASSET_SUPPORT.md) | Curriculum visual assets |
| [GLM_ASR_ON_DEVICE_GUIDE.md](GLM_ASR_ON_DEVICE_GUIDE.md) | On-device STT setup |
| [AI_SIMULATOR_TESTING.md](AI_SIMULATOR_TESTING.md) | AI-driven testing workflow |

---

## Roadmap

### Phase 1-5: Core Implementation (Complete)
- Voice pipeline, UI, curriculum system, telemetry

### Phase 6: Curriculum Import System (In Progress)
- MIT OCW importer
- Source browser UI
- AI enrichment pipeline

### Phase 7: Advanced Features (Planned)
- CK-12 and Fast.ai importers
- Knowledge graph construction
- Interactive visual diagrams
- Collaborative annotations

### Phase 8: Production Hardening (Pending)
- Performance optimization based on device testing
- 90-minute session stability
- TestFlight distribution
