# UnaMentis - Project Overview

## Purpose

UnaMentis is an AI-powered voice tutoring platform that enables extended (60-90+ minute) educational conversations. The project addresses limitations in existing voice AI (like ChatGPT's Advanced Voice Mode) by providing low-latency, natural voice interaction with curriculum-driven learning.

**Vision:** AI-powered learning that makes you smarter, not dependent. A personalized tutor that works with you over long stretches of time, understands your learning progress and style, and evolves into a true personal tutor, while ensuring genuine understanding through teachback, productive struggle, and spaced retrieval.

**Core Principle:** AI is at the core of what we're building, but the real core is the individual learner. UnaMentis exists to strengthen, not replace, the cognitive work of genuine understanding.

**Development Model:** 100% AI-assisted development (Claude Code mostly).

See [About UnaMentis](ABOUT.md) for our complete philosophy and values.

---

## Client Applications

UnaMentis provides voice tutoring across multiple platforms:

| Client | Platform | Technology | Status | Repository |
|--------|----------|------------|--------|------------|
| **iOS App** | iPhone/iPad | Swift 6.0, SwiftUI | Primary, feature-complete | This repo (`UnaMentis/`) |
| **Web Client** | Browsers | Next.js 15+, React 19, TypeScript | Feature-complete | This repo (`server/web-client/`) |
| **Android App** | Android | Kotlin | In development | Separate repo |

### iOS App (Primary)
- **Target Devices:** iPhone 16/17 Pro Max (optimized), iPad
- **Minimum OS:** iOS 18.0
- **Features:** Full voice pipeline, on-device inference, Siri integration, offline capability

### Web Client
- **Browsers:** Chrome, Safari, Edge (desktop and mobile)
- **Real-time Voice:** OpenAI Realtime API via WebRTC
- **Features:** Voice conversations, curriculum browser, visual assets, responsive design

### Android App
- **Status:** Active development in separate repository
- **Technology:** Kotlin with on-device inference support
- **Note:** Feature parity with iOS is the goal; currently implementing core voice pipeline

---

## Monorepo Structure

```
unamentis/
├── UnaMentis/                 # iOS App (Swift 6.0/SwiftUI)
├── UnaMentisTests/            # iOS Test Suite (126+ tests)
├── server/                    # Backend Infrastructure
│   ├── management/            # Management API (Python/aiohttp, port 8766)
│   ├── web/                   # Operations Console (Next.js/React, port 3000)
│   ├── web-client/            # Web Client (Next.js, voice tutoring for browsers)
│   ├── database/              # Shared SQLite curriculum database
│   └── importers/             # Curriculum import framework
├── curriculum/                # UMCF specification and examples
├── docs/                      # Comprehensive documentation (40+ files)
├── scripts/                   # Build, test, lint automation
└── .github/                   # CI/CD workflows
```

### Component Summary

| Component | Location | Technology | Purpose |
|-----------|----------|------------|---------|
| iOS App | `UnaMentis/` | Swift 6.0, SwiftUI | Voice tutoring client (primary) |
| iOS Tests | `UnaMentisTests/` | XCTest | 126+ unit, 16+ integration tests |
| Web Client | `server/web-client/` | Next.js 15+, React, TypeScript | Voice tutoring for browsers |
| Management API | `server/management/` | Python, aiohttp | Backend API (port 8766) |
| Operations Console | `server/web/` | Next.js 16.1, React 19 | System/content management (port 3000) |
| Importers | `server/importers/` | Python | Plugin-based curriculum import |
| Curriculum | `curriculum/` | UMCF JSON | Format specification |
| Latency Harness | `server/latency_harness/` | Python | Automated latency testing |

---

## AI Models & Providers

All components are **protocol-based and swappable**. The system supports multiple providers for each capability, enabling cost optimization, offline operation, and graceful degradation.

### Speech-to-Text (STT) Models

| Provider | Model | Type | Notes |
|----------|-------|------|-------|
| **Apple Speech** | Native | On-device | Zero cost, always available, ~150ms latency |
| **GLM-ASR** | GLM-ASR-Nano | On-device (CoreML) | Requires A17+ chip, ~2.4GB download |
| **Deepgram** | Nova-3 | Cloud (WebSocket) | ~300ms latency, streaming |
| **AssemblyAI** | Universal-2 | Cloud | Word-level timestamps |
| **Groq** | Whisper-large-v3-turbo | Cloud | Free tier (14,400 req/day), 300x real-time |
| **OpenAI** | Whisper | Cloud | High accuracy, batch processing |
| **Self-hosted** | whisper.cpp, faster-whisper | Local server | OpenAI-compatible API, WebSocket streaming |

### Text-to-Speech (TTS) Models

| Provider | Model | Type | Notes |
|----------|-------|------|-------|
| **Apple TTS** | AVSpeechSynthesizer | On-device | Zero cost, ~50ms TTFB, always available |
| **Chatterbox** | Chatterbox-turbo (350M) | Self-hosted | Emotion control, voice cloning, paralinguistic tags |
| **Chatterbox** | Chatterbox-multilingual (500M) | Self-hosted | 23 languages, expressive speech |
| **VibeVoice** | VibeVoice-Realtime-0.5B | Self-hosted | Microsoft model, 0.5B parameters, real-time |
| **ElevenLabs** | Turbo v2.5 | Cloud | Premium quality, WebSocket streaming |
| **Deepgram** | Aura-2 | Cloud | Multiple voices, 24kHz, streaming |
| **Piper** | Various voices | Self-hosted | OpenAI-compatible endpoint |

#### Chatterbox TTS (Resemble AI)

Chatterbox is our featured self-hosted TTS model with advanced capabilities:

- **Emotion Control:** Exaggeration parameter (0.0-1.5) controls emotional intensity
- **Generation Fidelity:** CFG weight (0.0-1.0) for output consistency
- **Paralinguistic Tags:** `[laugh]`, `[cough]`, `[chuckle]`, `[sigh]`, `[gasp]`
- **Voice Cloning:** Zero-shot cloning from reference audio (with UI for file selection and recording)
- **Languages:** 23 languages supported
- **Modes:** Streaming and non-streaming
- **Presets:** Default, Natural, Expressive, Low Latency

The iOS app includes a dedicated Chatterbox Settings view with voice cloning UI that allows users to:
- Enable/disable voice cloning
- Select reference audio files from device storage
- Record new reference audio directly (5+ seconds required)
- Preview and manage reference audio samples

### Large Language Models (LLM)

| Provider | Model | Type | Notes |
|----------|-------|------|-------|
| **On-Device** | Ministral-3B-Instruct-Q4_K_M | On-device (llama.cpp) | ~2.1GB, primary on-device |
| **On-Device** | TinyLlama-1.1B-Chat | On-device (llama.cpp) | Fallback, smaller footprint |
| **Anthropic** | Claude 3.5 Sonnet | Cloud | Primary cloud model |
| **OpenAI** | GPT-4o, GPT-4o-mini | Cloud | Alternative cloud option |
| **OpenAI Realtime** | gpt-4o-realtime-preview | Cloud (WebRTC) | Web client real-time voice |
| **Ollama** | Mistral 7B, Qwen2.5:32B, Llama3.2:3B | Self-hosted | OpenAI-compatible API |
| **llama.cpp server** | Any GGUF model | Self-hosted | Custom OpenAI-compatible |
| **vLLM** | Any HuggingFace model | Self-hosted | High-throughput inference |

### Voice Activity Detection (VAD)

| Provider | Model | Type | Notes |
|----------|-------|------|-------|
| **Silero VAD** | CoreML model | On-device (Neural Engine) | Apple Silicon optimized |
| **RMS-based** | Custom | On-device | Energy-based fallback |

### Embedding Models

| Provider | Model | Type | Purpose |
|----------|-------|------|---------|
| **OpenAI** | text-embedding-3-small | Cloud | Semantic search, retrieval |

### Graceful Degradation

The app works on any device, even without API keys or servers:

| Component | Built-in Fallback | Always Available |
|-----------|-------------------|------------------|
| **STT** | Apple Speech | Yes |
| **TTS** | Apple TTS | Yes |
| **LLM** | OnDeviceLLMService | Requires bundled models |
| **VAD** | RMS-based detection | Yes |

---

## iOS App Architecture

**Target:** iPhone 16/17 Pro Max | **Minimum:** iOS 18.0 | **Language:** Swift 6.0

### Core Components

```
UnaMentis/
├── Core/
│   ├── Audio/           # AudioEngine, VAD, thermal management
│   ├── Config/          # APIKeyManager (Keychain), ServerConfigManager
│   ├── Curriculum/      # CurriculumEngine, ProgressTracker, UMCFParser
│   ├── Logging/         # RemoteLogHandler
│   ├── Persistence/     # PersistenceController, 7 Core Data entities
│   ├── Routing/         # PatchPanelService, LLMEndpoint, RoutingTable
│   ├── Session/         # SessionManager (state machine, TTS config)
│   └── Telemetry/       # TelemetryEngine (latency, cost, events)
├── Services/
│   ├── LLM/             # OpenAI, Anthropic, Self-Hosted, On-Device
│   ├── STT/             # AssemblyAI, Deepgram, Groq, Apple, GLM-ASR, Router
│   ├── TTS/             # Chatterbox, ElevenLabs, Deepgram, Apple, VibeVoice
│   ├── VAD/             # SileroVADService (CoreML)
│   ├── Embeddings/      # OpenAIEmbeddingService
│   └── Curriculum/      # CurriculumService, VisualAssetCache
├── Intents/             # Siri & App Intents (iOS 16+)
│   ├── StartLessonIntent.swift      # "Hey Siri, start a lesson"
│   ├── ResumeLearningIntent.swift   # "Hey Siri, resume my lesson"
│   ├── ShowProgressIntent.swift     # "Hey Siri, show my progress"
│   ├── CurriculumEntity.swift       # Exposes curricula to Siri
│   └── TopicEntity.swift            # Exposes topics to Siri
└── UI/
    ├── Session/         # SessionView, VisualAssetView
    ├── Curriculum/      # CurriculumView
    ├── Settings/        # SettingsView, ServerSettingsView, ChatterboxSettingsView
    ├── History/         # HistoryView
    ├── Analytics/       # AnalyticsView
    └── Debug/           # DeviceMetricsView, DebugConversationTestView
```

### Service Counts

| Category | Count | Providers |
|----------|-------|-----------|
| **STT Providers** | 9 | AssemblyAI, Deepgram, Groq, Apple, GLM-ASR server, GLM-ASR on-device, Self-Hosted, Router, Health Monitor |
| **TTS Providers** | 7 | Chatterbox, VibeVoice, ElevenLabs, Deepgram, Apple, Self-Hosted, Pronunciation Processor |
| **LLM Providers** | 5 | OpenAI, Anthropic, Self-Hosted, On-Device, Mock |
| **UI Views** | 11+ | Session, Curriculum, History, Analytics, Settings, Debug, and supporting views |
| **Swift Files** | 80+ | Source files across Core, Services, UI |
| **Test Files** | 26 | Unit and integration tests |

### Session Flow

```
Microphone -> AudioEngine -> VAD -> STT (streaming)
    -> SessionManager (turn-taking, context)
    -> FOV Context Manager (build hierarchical context)
    -> PatchPanel (route to LLM endpoint)
    -> LLM (streaming) -> Confidence Monitor
    -> TTS (streaming)
    -> AudioEngine -> Speaker
```

**Session States:** Idle → User Speaking → Processing → AI Thinking → AI Speaking → (loop)

### Curriculum Auto-Continuation

Seamless topic-to-topic transitions for uninterrupted learning sessions:

**Features:**
- **Auto-Continue:** Automatically transitions to next topic when current topic completes
- **Pre-Generation:** Starts generating next topic's audio at 70% progress for seamless transitions
- **Transition Announcements:** Clear audio and visual notification of topic changes
- **Audio Segment Caching:** Caches all segments for current topic (up to 50MB) for instant replay
- **Navigation Controls:** Go back one segment, replay topic, skip to next topic buttons
- **User Preference:** Settings toggle to enable/disable auto-continuation (default ON)

**Implementation:**
- `AudioSegmentCache` actor for thread-safe segment caching
- Pre-generation buffer for next topic audio
- Transition announcement via Apple TTS
- `CurriculumControlBar` UI component with navigation buttons

### FOV Context Management

Foveated context management builds optimal LLM context for voice tutoring, inspired by VR foveated rendering where the center of attention gets full detail.

**Hierarchical Buffers:**

| Buffer | Purpose | Token Budget (Cloud) |
|--------|---------|---------------------|
| **Immediate** | Current segment, recent turns, barge-in | 4,000 |
| **Working** | Current topic content, glossary, misconceptions | 4,000 |
| **Episodic** | Session history, learner signals, completed topics | 2,500 |
| **Semantic** | Curriculum outline, position, prerequisites | 1,500 |

**Adaptive Scaling:** Budgets scale for model context window (Cloud 12K, Mid-range 8K, On-device 4K, Tiny 2K).

**Confidence Monitoring:** Analyzes responses for hedging, deflection, knowledge gaps. Automatically expands context when uncertainty detected.

See [FOV_CONTEXT_MANAGEMENT.md](FOV_CONTEXT_MANAGEMENT.md) for complete documentation.

### LLM Routing (Patch Panel)

A switchboard system for routing LLM calls to any endpoint:

**Routing Priority:**
1. Global override (debugging)
2. Manual task-type override
3. Auto-routing rules (thermal, network, cost conditions)
4. Default routes per task type
5. Fallback chain

**20+ Task Types:** Tutoring, content generation, navigation, classification, and simple responses.

**Condition-Based Routing:** Device conditions (thermal, memory, battery), network conditions, cost thresholds, and time conditions.

### Data Persistence

**Core Data entities (7 total):**
- `Curriculum` - Course containers
- `Topic` - Hierarchical learning units
- `Session` - Recorded conversations with transcripts
- `TopicProgress` - Time spent, mastery scores
- `TranscriptEntry` - Conversation history
- `Document` - Imported curriculum documents
- `VisualAsset` - Images, diagrams, equations linked to topics

---

## Web Client Architecture

**Technology:** Next.js 15+, React 19, TypeScript 5, Tailwind CSS

### Features

- **Real-time Voice:** OpenAI Realtime API via WebRTC for low-latency conversations
- **Curriculum Browser:** Full UMCF content navigation with hierarchy
- **Visual Assets:** Rich display of formulas, maps, diagrams, charts with LaTeX rendering
- **Cost Tracking:** Real-time session cost display
- **Responsive Design:** Desktop and mobile optimized
- **Theme Support:** Light/dark mode with comprehensive theming

### Provider Support

| Function | Providers |
|----------|-----------|
| **STT** | OpenAI Realtime, Deepgram, AssemblyAI, Groq, Self-hosted |
| **TTS** | OpenAI Realtime, ElevenLabs, Self-hosted |
| **LLM** | OpenAI Realtime, Anthropic Claude, Groq |

### Key Components

- `VoiceSession` - Real-time voice conversation management
- `CurriculumBrowser` - Hierarchical curriculum navigation
- `VisualAssetDisplay` - Formula, diagram, chart rendering
- `SessionContext` - Global state management
- `ConnectionState` - Real-time connection handling

---

## Server Infrastructure

### Management API (Port 8766)

**Purpose:** Backend API for curriculum and configuration data

**Tech Stack:** Python 3, aiohttp (async), SQLite

**Features:**
- Curriculum CRUD operations
- Import job orchestration with progress tracking
- Visual asset management
- AI enrichment pipeline (7 stages)
- User progress tracking and analytics
- Plugin management API
- Authentication (JWT tokens, rate limiting)
- Diagnostic logging and resource monitoring
- **FOV Context Management** for voice tutoring sessions (see [FOV_CONTEXT_MANAGEMENT.md](FOV_CONTEXT_MANAGEMENT.md))
- **TTS Caching System** - Global cross-user audio cache with priority-based generation
- **Session Management** - Per-user session state with cross-device resume support
- **Scheduled Deployments** - Admin-triggered curriculum pre-generation

### Operations Console (Port 3000)

**Purpose:** Unified web interface for system and content management

**Tech Stack:** Next.js 16.1.0, React 19.2.3, TypeScript 5, Tailwind CSS 4

**Features:**
- System health monitoring (CPU, memory, thermal, battery)
- Service status dashboard (Ollama, Chatterbox, VibeVoice, Piper, Gateway)
- Power/idle management profiles
- Performance metrics (E2E latency, STT/LLM/TTS latencies, costs)
- Logs and diagnostics with real-time filtering
- Client connection monitoring
- **Curriculum Studio** for viewing/editing UMCF content
- **Plugin Manager** for configuring content sources
- **Users Dashboard** for user and session management

### Self-Hosted Server Support

UnaMentis can connect to local/LAN servers for zero-cost inference:

| Server Type | Port | Purpose |
|-------------|------|---------|
| Ollama | 11434 | LLM inference (primary) |
| llama.cpp | 8080 | LLM inference |
| vLLM | 8000 | High-throughput LLM |
| GLM-ASR server | 11401 | STT (WebSocket streaming) |
| Chatterbox TTS | 8004 | Expressive TTS |
| VibeVoice TTS | 11403 | Real-time TTS |
| Piper TTS | 11402 | Lightweight TTS |
| UnaMentis Gateway | 11400 | Unified API gateway |

**Features:**
- Auto-discovery of available models/voices
- Health monitoring with automatic fallback
- OpenAI-compatible API support

### TTS Caching & Session Management

A comprehensive architecture for multi-user tutoring with global audio caching and per-user session state.

**Components:**

| Component | Purpose |
|-----------|---------|
| **TTSCache** | Global user-agnostic audio cache (shared across all users) |
| **TTSResourcePool** | Priority-based TTS generation with concurrency limits |
| **SessionCacheIntegration** | Bridge between per-user sessions and global cache |
| **UserSession** | Per-user state with voice config and playback position |
| **ScheduledDeploymentManager** | Admin-triggered curriculum pre-generation |

**Key Design Principles:**

1. **User-Agnostic Cache Keys:** Cache keys contain only `text + voice_id + provider + speed` (no user_id). Users with identical voice configurations share cached audio.

2. **Cross-User Cache Sharing:** When User A generates audio for "Welcome to the lesson" with voice "nova", User B requesting the same text with the same voice gets an instant cache hit (0ms TTS latency).

3. **Priority-Based Generation:**
   - `LIVE (10)` - User actively waiting, highest priority (7 concurrent max)
   - `PREFETCH (5)` - Near-future prefetch, background priority
   - `SCHEDULED (1)` - Background pre-generation (3 concurrent max)

4. **Separate Semaphores:** Live requests never blocked by background generation. Each priority level has its own concurrency pool.

**Performance (tested):**
- Sequential cache hits: 1-3ms latency
- 50 concurrent cache hits: 1,155 req/sec, 35ms avg latency
- Cache storage: Filesystem-based with async I/O

**API Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/tts` | POST | Generate TTS (cache-first) |
| `/api/tts/cache/stats` | GET | Cache and resource pool stats |
| `/api/tts/cache` | GET | Direct cache lookup |
| `/api/tts/cache` | PUT | Direct cache insertion (dev) |
| `/api/tts/cache` | DELETE | Clear cache |
| `/api/tts/prefetch/topic` | POST | Prefetch topic segments |
| `/api/deployments` | POST/GET | Scheduled pre-generation |

**Corporate Training Example:**
```
500 employees start "Security Training 2024" simultaneously:
- Admin pre-generates all segments the night before
- Day-of: 100% cache hits, 0ms TTS latency for everyone
- Server easily handles 500 concurrent sessions
```

### Architecture Relationship

```
┌─────────────────────────────────────────────────────────┐
│              Operations Console (Port 3000)             │
│              Next.js/React Frontend                     │
└────────────────────────┬────────────────────────────────┘
                         │ Proxy requests
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Management API (Port 8766)                 │
│              Python/aiohttp Backend                     │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              SQLite Curriculum Database                 │
│              Curricula, Topics, Assets, Progress        │
└─────────────────────────────────────────────────────────┘
```

---

## Curriculum System (UMCF)

**Una Mentis Curriculum Format** - A JSON-based specification designed for conversational AI tutoring.

### Specification Status: Complete (v1.0.0)
- JSON Schema: 1,905 lines, 152 fields
- Standards alignment: IEEE LOM, LRMI, Dublin Core, SCORM, xAPI, CASE, QTI, Open Badges
- UMCF-native fields: 70 (46%) for tutoring-specific needs

### Structure

```
Curriculum
├── Metadata (title, version, language, lifecycle, rights, compliance)
├── Content[] (unlimited nesting depth)
│   ├── Node types: curriculum, unit, module, topic, subtopic, lesson, section, segment
│   ├── Learning objectives (Bloom's taxonomy aligned)
│   ├── Transcript segments with stopping points
│   ├── Alternative explanations (simpler, technical, analogy)
│   ├── Misconceptions + remediation (trigger phrases)
│   ├── Assessments (choice, multiple_choice, text_entry, true_false)
│   ├── Media (images, diagrams, equations, videos, slide decks)
│   └── Speaking notes for TTS (pace, emphasis, emotional tone)
└── Glossary (terms with spoken definitions)
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
- **Segment timing:** Controls when visuals appear during playback
- **Reference media:** Optional supplementary materials with keyword matching
- **Accessibility:** Required alt text, audio descriptions for all visual content
- **Equation format:** LaTeX notation with spoken description

---

## Curriculum Importers

### Plugin Architecture

The framework uses **filesystem-based plugin discovery** with explicit enable/disable control:

- **Auto-Discovery**: Plugins discovered from `plugins/` folder
- **Explicit Enablement**: Plugins must be enabled via Plugin Manager UI
- **Persistent State**: Plugin state persists in `plugins.json`
- **First-Run Wizard**: New installations prompt users to select plugins

### Implemented Importers

| Source | Status | Target Audience | Description |
|--------|--------|-----------------|-------------|
| **MIT OpenCourseWare** | Complete | Collegiate | 247 courses loaded, full catalog browser |
| **CK-12 FlexBooks** | Complete | K-12 (8th grade focus) | EPUB, PDF, HTML import |
| **EngageNY** | Complete | K-12 | New York State curriculum resources |
| **MERLOT** | Complete | Higher Ed | MERLOT digital collections |
| **Fast.ai** | Spec Complete | Collegiate AI/ML | Jupyter notebook import |
| **Stanford SEE** | Spec Complete | Engineering | PDF, transcript import |

### Import Pipeline Stages

1. **Download** - Fetch course materials
2. **Validate** - Check completeness and format
3. **Extract** - Parse into intermediate structure
4. **Enrich** - AI processing (optional)
5. **Generate** - Transform to UMCF
6. **Store** - Save to curriculum database

### AI Enrichment Pipeline (7 Stages)

1. **Content Analysis** - Readability metrics, domain detection, quality indicators
2. **Structure Inference** - Topic boundaries, hierarchical grouping
3. **Content Segmentation** - Meta-chunking based boundary detection
4. **Learning Objective Extraction** - Bloom's taxonomy alignment
5. **Assessment Generation** - Question generation with SRL + LLM
6. **Tutoring Enhancement** - Spoken text, misconceptions, glossary extraction
7. **Knowledge Graph** - Concept extraction, Wikidata linking, prerequisites

---

## Testing Infrastructure

### Latency Test Harness

Systematic latency testing framework for validating performance against project targets (<500ms median, <1000ms P99).

#### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Server CLI | `server/latency_harness/` | Test orchestration, analysis, storage |
| iOS Harness | `UnaMentis/Testing/LatencyHarness/` | High-precision iOS test execution |
| Web Dashboard | Operations Console → Latency Tests | Real-time monitoring |
| REST API | Management API (port 8766) | Programmatic access |

#### Built-in Test Suites

| Suite | Tests | Duration | Use Case |
|-------|-------|----------|----------|
| `quick_validation` | 3 | ~2 min | CI/CD, quick checks |
| `provider_comparison` | 450 | ~30 min | Full provider analysis |

#### CLI Commands

```bash
# List available suites
python -m latency_harness.cli --list-suites

# Run quick validation (mock mode for fast checks)
python -m latency_harness.cli --suite quick_validation --mock

# Run with real providers
python -m latency_harness.cli --suite quick_validation --no-mock

# JSON output for automation
python -m latency_harness.cli --suite quick_validation --format json
```

#### API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/latency-tests/suites` | GET | List test suites |
| `/api/latency-tests/runs` | POST | Start test run |
| `/api/latency-tests/runs/{id}` | GET | Get run status |
| `/api/latency-tests/runs/{id}/analysis` | GET | Get analysis report |
| `/api/latency-tests/baselines` | GET/POST | Manage performance baselines |
| `/api/latency-tests/baselines/{id}/check` | GET | Check run against baseline |

#### Key Features

- **High-Precision Timing:** iOS uses `mach_absolute_time()` for nanosecond precision
- **Observer Effect Mitigation:** Fire-and-forget result reporting, no blocking during measurements
- **Network Projections:** Automatic latency projections for localhost, WiFi, cellular
- **Regression Detection:** Baseline comparison with severity levels (minor/moderate/severe)
- **Resource Monitoring:** CPU, memory, thermal state tracking during tests
- **Audio File Loading:** Full audio input scenario support with file loading, format conversion, and STT streaming

See `server/latency_harness/CLAUDE.md` and `docs/LATENCY_TEST_HARNESS_GUIDE.md` for details.

---

## Code Quality Infrastructure

UnaMentis implements a comprehensive **5-phase Code Quality Initiative** that enables enterprise-grade quality standards through intelligent automation. This infrastructure allows a small team to maintain quality typically requiring 10+ engineers.

### Quality Gates

| Gate | Threshold | Enforcement |
|------|-----------|-------------|
| Code Coverage (iOS) | 80% minimum | CI fails if below |
| Latency P50 | 500ms | CI warns at +10%, fails at +20% |
| Latency P99 | 1000ms | CI warns at +10%, fails at +20% |
| SwiftLint | Zero violations (strict) | Pre-commit hook |
| Ruff (Python) | Zero violations | Pre-commit hook |
| ESLint/Prettier | Zero violations | Pre-commit hook |
| Secrets Detection | Zero findings | Pre-commit + CI |
| Security Vulnerabilities | Zero critical/high | Security workflow |

### Automation Components

| Component | Tool | Purpose |
|-----------|------|---------|
| Pre-commit Hooks | Native git hooks | Lint, format, secrets check |
| Hook Bypass Audit | `scripts/hook-audit.sh` | Detect `--no-verify` usage |
| Dependency Management | Renovate | Auto-updates with grouping |
| AI Code Review | CodeRabbit | Automated PR review (free for OSS) |
| Performance Testing | Latency Harness | Regression detection |
| Security Scanning | CodeQL, Gitleaks | Vulnerability detection |
| DORA Metrics | Apache DevLake | Engineering health |
| Feature Flags | Unleash | Safe rollouts |
| Mutation Testing | mutmut, Stryker, Muter | Test quality validation |
| Chaos Engineering | Custom runbook | Voice pipeline resilience |

### GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| iOS CI | Push/PR | Build, lint, test, coverage |
| Server CI | Push/PR | Python linting, tests, coverage |
| Web Client CI | Push/PR | Lint, typecheck, build, coverage |
| Nightly E2E | Daily 2am | Full E2E + latency tests |
| Performance | Push/PR/scheduled | Latency regression check |
| Security | Push/PR/weekly | Secrets, CodeQL, audits |
| Quality Metrics | Daily | CI/PR/bug metrics |
| Feature Flags | Weekly | Stale flag audit |
| Mutation Testing | Weekly (Sunday 4am) | Test quality validation |

### Feature Flag System

Self-hosted Unleash infrastructure with SDKs for all platforms:

| Component | Port | Purpose |
|-----------|------|---------|
| Unleash Server | 4242 | Flag management |
| Unleash Proxy | 3063 | Client SDK endpoint |
| PostgreSQL | 5432 | Data persistence |

**SDK Support:**
- iOS: Actor-based service with SwiftUI view modifier
- Web: React context, hooks (`useFlag`, `useFlagVariant`)
- Lifecycle: Automated stale flag detection + cleanup issues

### DORA Metrics (DevLake)

Apache DevLake provides visibility into engineering health:

| Metric | What It Measures | Elite Target |
|--------|-----------------|--------------|
| Deployment Frequency | How often code ships | Multiple/day |
| Lead Time for Changes | Commit to production | < 1 hour |
| Change Failure Rate | Failures from deployments | 0-15% |
| Mean Time to Recovery | Incident resolution | < 1 hour |

**Access:**
- Config UI: http://localhost:4000
- Grafana Dashboards: http://localhost:3002

### Quick Setup

```bash
# Install git hooks
./scripts/install-hooks.sh

# Start DORA metrics
cd server/devlake && docker compose up -d

# Start feature flags
cd server/feature-flags && docker compose up -d

# Audit for hook bypasses
./scripts/hook-audit.sh
```

### Chaos Engineering

The project includes a comprehensive chaos engineering runbook for testing voice pipeline resilience:

- **Network Degradation:** High latency (500ms+), packet loss (5-20%), disconnections
- **API Failures:** Provider timeouts, rate limiting, partial responses
- **Resource Pressure:** Memory limits, thermal throttling, battery constraints

See [CHAOS_ENGINEERING_RUNBOOK.md](../testing/CHAOS_ENGINEERING_RUNBOOK.md) for test scenarios.

See [CODE_QUALITY_INITIATIVE.md](../quality/CODE_QUALITY_INITIATIVE.md) for complete documentation.

---

## Current Status

### Complete
- All iOS services implemented (STT, TTS, LLM, VAD, Embeddings)
- Full UI (Session, Curriculum, History, Analytics, Settings, Debug)
- UMCF 1.0 specification with JSON Schema (1,905 lines)
- 126+ unit tests across 26 test files (including 23 App Intents tests)
- 16+ integration tests
- Telemetry, cost tracking, thermal management
- Self-hosted server discovery and health monitoring
- Patch Panel LLM routing system
- GLM-ASR implementation (server + on-device)
- Groq STT integration (Whisper API)
- Chatterbox TTS integration with emotion control
- VibeVoice TTS integration
- STT Provider Router with automatic failover
- Visual asset support design
- Import architecture with 4 complete importers (MIT OCW, CK-12, EngageNY, MERLOT)
- Operations Console (React/TypeScript) with Curriculum Studio
- Management API (Python/aiohttp)
- Web Client (Next.js) with voice tutoring, curriculum browser, visual assets
- iOS Simulator MCP for AI-driven testing
- Siri & App Intents integration (voice commands, deep links)
- Graceful degradation architecture
- Plugin-based importer framework
- Latency test harness (CLI, REST API, iOS harness, Web dashboard)
- FOV Context Management (hierarchical cognitive buffers, confidence monitoring)
- Curriculum auto-continuation with pre-generation and segment caching
- CodeRabbit AI code review integration (CLI + VS Code extension)
- **TTS Caching System** (global cross-user cache, priority-based generation, 1000+ req/sec)
- **Session Management** (UserSession, PlaybackState, SessionCacheIntegration)
- **TTSResourcePool** (separate semaphores for live vs background, concurrency control)
- **Self-hosted STT WebSocket streaming** (whisper.cpp, faster-whisper compatible)
- **Voice cloning UI** (Chatterbox settings with file picker and audio recorder)
- **Latency harness audio file loading** (full STT pipeline testing with real audio)
- **LaTeX formula rendering** (SwiftMath integration with Unicode fallback)

### In Progress
- Android client (separate repository)
- Visual asset caching optimization
- AI enrichment pipeline implementation
- Fast.ai and Stanford SEE importers

### Pending User Setup
- API key configuration (OpenAI, Anthropic, Deepgram, ElevenLabs, AssemblyAI, Groq)
- Physical device testing (iPhone 16/17 Pro Max)
- On-device GLM-ASR model download (~2.4GB)
- Long-session stability validation (90+ minutes)
- Curriculum content creation

---

## Performance Targets

| Metric | Target (Median) | Acceptable (P99) |
|--------|-----------------|------------------|
| End-to-end latency | <500ms | <1000ms |
| STT latency | <300ms | <1000ms |
| LLM time-to-first-token | <200ms | <500ms |
| TTS time-to-first-byte | <200ms | <400ms |
| Session duration | 60-90+ minutes | - |
| Memory growth | <50MB over 90 min | - |

## Cost Targets

| Preset | Target |
|--------|--------|
| Balanced | <$3/hour |
| Cost-optimized | <$1.50/hour |

---

## Tech Stack Summary

### iOS App
| Layer | Technology |
|-------|-----------|
| Language | Swift 6.0 with strict concurrency |
| UI | SwiftUI |
| Concurrency | Actors, @MainActor, async/await |
| Persistence | Core Data (SQLite) |
| Audio | AVFoundation, Audio Toolbox |
| Networking | LiveKit (WebRTC), URLSession |
| Inference | llama.cpp, CoreML |
| Testing | XCTest (real > mock philosophy) |

### Web Client
| Layer | Technology |
|-------|-----------|
| Framework | Next.js 15+ (App Router) |
| UI Library | React 19 |
| Language | TypeScript 5 |
| Styling | Tailwind CSS |
| Real-time | OpenAI Realtime API (WebRTC) |

### Operations Console
| Layer | Technology |
|-------|-----------|
| Framework | Next.js 16.1.0 (App Router) |
| UI Library | React 19.2.3 |
| Language | TypeScript 5 |
| Styling | Tailwind CSS 4 |
| Icons | Lucide React |

### Management API
| Layer | Technology |
|-------|-----------|
| Language | Python 3 |
| Framework | aiohttp (async) |
| Database | SQLite |

### Importers
| Layer | Technology |
|-------|-----------|
| Language | Python 3 |
| Architecture | Plugin-based discovery |
| Output | UMCF JSON |

---

## Key Files

| Path | Purpose |
|------|---------|
| `UnaMentis/Core/Session/SessionManager.swift` | Orchestrates voice sessions, state machine |
| `UnaMentis/Core/Curriculum/CurriculumEngine.swift` | Curriculum context generation |
| `UnaMentis/Core/Routing/PatchPanelService.swift` | LLM endpoint routing |
| `UnaMentis/Services/STT/STTProviderRouter.swift` | STT failover routing |
| `UnaMentis/Services/STT/GroqSTTService.swift` | Groq Whisper integration |
| `UnaMentis/Services/TTS/ChatterboxTTSService.swift` | Chatterbox TTS with emotion control |
| `UnaMentis/Services/LLM/SelfHostedLLMService.swift` | Ollama/llama.cpp integration |
| `UnaMentis/Services/STT/GLMASROnDeviceSTTService.swift` | On-device speech recognition |
| `curriculum/spec/umcf-schema.json` | UMCF JSON Schema (1,905 lines) |
| `curriculum/spec/UMCF_SPECIFICATION.md` | Human-readable format spec |
| `server/management/server.py` | Management API backend |
| `server/management/tts_cache/cache.py` | Global TTS cache implementation |
| `server/management/tts_cache/resource_pool.py` | Priority-based TTS generation pool |
| `server/management/session_cache_integration.py` | Session-cache bridge |
| `server/management/fov_context/session.py` | UserSession, PlaybackState, SessionManager |
| `server/importers/plugins/sources/mit_ocw.py` | MIT OCW course handler |
| `server/web/src/components/curriculum/` | Curriculum Studio components |
| `server/web-client/src/app/` | Web client application |

---

## Documentation

### Getting Started
| Document | Purpose |
|----------|---------|
| [QUICKSTART.md](QUICKSTART.md) | START HERE |
| [SETUP.md](SETUP.md) | Environment setup |
| [TESTING.md](TESTING.md) | Testing guide |
| [DEBUG_TESTING_UI.md](DEBUG_TESTING_UI.md) | Built-in troubleshooting |

### Architecture & Design
| Document | Purpose |
|----------|---------|
| [UnaMentis_TDD.md](UnaMentis_TDD.md) | Technical Design Document |
| [ENTERPRISE_ARCHITECTURE.md](ENTERPRISE_ARCHITECTURE.md) | System design |
| [PATCH_PANEL_ARCHITECTURE.md](PATCH_PANEL_ARCHITECTURE.md) | LLM routing |
| [FOV_CONTEXT_MANAGEMENT.md](FOV_CONTEXT_MANAGEMENT.md) | Foveated context for voice tutoring |
| [FALLBACK_ARCHITECTURE.md](FALLBACK_ARCHITECTURE.md) | Graceful degradation |

### Curriculum
| Document | Purpose |
|----------|---------|
| [curriculum/README.md](../curriculum/README.md) | UMCF overview |
| [UMCF_SPECIFICATION.md](../curriculum/spec/UMCF_SPECIFICATION.md) | Format spec |
| [IMPORTER_ARCHITECTURE.md](../curriculum/importers/IMPORTER_ARCHITECTURE.md) | Import system |
| [AI_ENRICHMENT_PIPELINE.md](../curriculum/importers/AI_ENRICHMENT_PIPELINE.md) | AI processing |

### Feature Documentation
| Document | Purpose |
|----------|---------|
| [APPLE_INTELLIGENCE.md](APPLE_INTELLIGENCE.md) | Siri & App Intents |
| [GLM_ASR_ON_DEVICE_GUIDE.md](GLM_ASR_ON_DEVICE_GUIDE.md) | On-device STT |
| [AI_SIMULATOR_TESTING.md](AI_SIMULATOR_TESTING.md) | AI-driven testing |
| [VISUAL_ASSET_SUPPORT.md](VISUAL_ASSET_SUPPORT.md) | Curriculum media |

---

## Roadmap

### Phase 1-5: Core Implementation (Complete)
- Voice pipeline, UI, curriculum system, telemetry

### Phase 6: Curriculum Import System (Mostly Complete)
- MIT OCW, CK-12, EngageNY, MERLOT importers (complete)
- Curriculum Studio (complete)
- Plugin management framework (complete)
- AI enrichment pipeline (in progress)
- Fast.ai and Stanford SEE importers (spec complete)

### Phase 7: Cross-Platform Expansion (In Progress)
- Android client development
- Feature parity across iOS, Web, Android
- Shared curriculum sync

### Phase 8: Advanced Features (Planned)
- Knowledge graph construction
- Interactive visual diagrams
- Collaborative annotations

### Phase 9: Production Hardening (Pending)
- Performance optimization based on device testing
- 90-minute session stability
- TestFlight distribution

---

## Project Vision

### Open Source Core
The fundamental core of UnaMentis will always remain open source:
- Core voice pipeline and session management
- Curriculum system and progress tracking
- All provider integrations
- Cross-platform support

### Enterprise Features (Future)
A separate commercial layer may offer:
- Single sign-on (SSO) integration
- Advanced reporting and analytics
- Permission controls and user management
- Corporate curriculum publishing
- Priority support

---

## File Statistics

| Component | Language | Files | Purpose |
|-----------|----------|-------|---------|
| iOS App | Swift | 80+ | Voice tutoring client (primary) |
| iOS Tests | Swift | 26 | Unit & integration tests |
| Web Client | TypeScript/React | 50+ | Voice tutoring for browsers |
| Management API | Python | 10+ | Backend API |
| Operations Console | TypeScript/React | 67 | System/content management |
| Importers | Python | 25+ | Curriculum ingestion |
| Curriculum Spec | Markdown/JSON | 19 | Format specification |
| Documentation | Markdown | 40+ | Comprehensive guides |
| **TOTAL** | Mixed | 317+ | Full system |
