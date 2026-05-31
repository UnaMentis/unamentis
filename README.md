<p align="center">
  <img src="images/UnaMentis_expanded_color.png" alt="UnaMentis" width="500">
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Server CI](https://github.com/UnaMentis/unamentis/actions/workflows/server.yml/badge.svg)](https://github.com/UnaMentis/unamentis/actions/workflows/server.yml)
[![codecov](https://codecov.io/gh/UnaMentis/unamentis/branch/main/graph/badge.svg)](https://codecov.io/gh/UnaMentis/unamentis)
[![Code Quality](https://img.shields.io/badge/code%20quality-A-brightgreen)](docs/quality/CODE_QUALITY_INITIATIVE.md)
[![Backers on Open Collective](https://opencollective.com/unamentis/backers/badge.svg)](https://opencollective.com/unamentis)
[![Sponsors on Open Collective](https://opencollective.com/unamentis/sponsors/badge.svg)](https://opencollective.com/unamentis)

**Voice AI learning platform. This repository contains the server infrastructure, curriculum system, and project-wide documentation.**

## Why UnaMentis?

We live in an age where AI can write essays, solve problems, and answer any question instantly. This power is extraordinary, but it's also dangerous without foundation. A calculator is useless to someone who doesn't understand what multiplication means. AI writing is hollow to someone who has never formed their own thoughts.

**UnaMentis takes a different approach: AI as learning partner, not substitute.**

We use artificial intelligence to deliver personalized, voice-based instruction at scale. But our goal isn't to give you answers. It's to build genuine understanding. We challenge you to explain concepts back in your own words. We celebrate the time you spend thinking before asking for help. We revisit what you learned last week to make sure you truly remember it.

Quality curriculum, often from institutions like MIT, combined with AI that guides rather than replaces, creates something powerful: a platform that makes you genuinely smarter.

**This is education technology that serves learning, not shortcuts.**

### Core Principles

- **Genuine Understanding**: We reinforce real comprehension through teachback, productive struggle, and spaced retrieval
- **Quality Curriculum**: Content from respected sources (MIT, CK-12, and more), designed for voice-based delivery
- **Privacy-First**: On-device capabilities, user control, and transparent data practices
- **Open Source Core**: The fundamental infrastructure will always remain open source

See [About UnaMentis](docs/ABOUT.md) for our complete philosophy and [docs/PHILOSOPHY.md](docs/PHILOSOPHY.md) for the founding vision.

## Ecosystem

UnaMentis is a multi-repo project. Each component has its own repository:

| Repository | Purpose | Status |
|------------|---------|--------|
| [unamentis](https://github.com/UnaMentis/unamentis) | Server infrastructure, curriculum, project docs (this repo) | Active |
| [unamentis-ios](https://github.com/UnaMentis/unamentis-ios) | iOS client (Swift 6/SwiftUI) | Pre-beta |
| [unamentis-android](https://github.com/UnaMentis/unamentis-android) | Android client (Kotlin/Jetpack Compose) | In development |

## Overview

UnaMentis enables 60-90+ minute voice-based learning sessions with AI. The platform spans iOS, Android, and web clients backed by shared server infrastructure. Key design goals:

- Sub-500ms end-to-end latency
- Natural interruption handling (no push-to-talk)
- Curriculum-driven learning with progress tracking
- Comprehensive observability and cost tracking
- Modular architecture with swappable providers

## Provider Flexibility

UnaMentis is designed to be provider-agnostic with strong emphasis on on-device capabilities. The system supports pluggable providers for every component of the voice AI pipeline:

- **STT (Speech-to-Text)**: On-device (Apple Speech, GLM-ASR), cloud (Deepgram, AssemblyAI), or self-hosted (Whisper)
- **TTS (Text-to-Speech)**: On-device (Apple), cloud (ElevenLabs, Deepgram Aura), or self-hosted (VibeVoice, Piper)
- **LLM**: On-device (Ministral-3B via llama.cpp), self-hosted (Mistral 7B via Ollama), or cloud (Anthropic, OpenAI)
- **Embeddings**: OpenAI or compatible embedding services
- **VAD**: Silero (Core ML, on-device)

The right model depends on the task, the moment, and the cost. The architecture prioritizes flexibility so you can:

- Swap providers without code changes
- Use different models for different tasks (fast/cheap for simple responses, powerful for complex explanations)
- Run entirely on-device for privacy, offline use, or zero API costs
- Self-host models on local servers for cost control
- A/B test provider combinations to find optimal setups

## Quick Start

```bash
# 1. Set up environment
./scripts/setup-local-env.sh

# 2. Configure API keys
cp .env.example .env
# Edit .env and add your keys

# 3. Start server components
cd server/management && python -m management.app   # Management API (port 8766)
cd server/web && pnpm install && pnpm dev           # Operations Console (port 3000)

# 4. Run a quick check (latency harness, mock mode)
python -m latency_harness.cli --suite quick_validation --mock
```

For iOS client setup, see the [unamentis-ios](https://github.com/UnaMentis/unamentis-ios) repository.
See [Quick Start Guide](docs/QUICKSTART.md) for complete server setup.

## Current Status

This repository (server infrastructure, curriculum, and project documentation) is being prepared for public open-source release. The iOS client is in pre-beta in its own repository, [unamentis-ios](https://github.com/UnaMentis/unamentis-ios).

**Server components implemented**
- USM Core (Rust service manager), Management API (Python/aiohttp), Operations Console and Web Client (Next.js), and the curriculum importer framework.
- UMCF curriculum specification (v1.0) with JSON Schema.
- Automated latency test harness with baseline regression detection.

**In progress**
- Security hardening ahead of public release (see [docs/reviews/](docs/reviews/)).
- Curriculum import and content setup.

See [docs/TASK_STATUS.md](docs/TASK_STATUS.md) for detailed task tracking.

## Documentation

### 📚 Developer Wiki

**[Visit the UnaMentis Wiki](https://github.com/UnaMentis/unamentis/wiki)** for comprehensive developer documentation including:

- Complete development environment setup
- Architecture deep-dives and patterns
- Code quality standards and workflows
- Performance testing harness guide
- Tool configuration (CodeRabbit, MCP servers, CI/CD)
- API and CLI references

The wiki is the primary resource for contributors and maintainers.

### Getting Started
- [Quick Start Guide](docs/QUICKSTART.md) - START HERE
- [Setup Guide](docs/setup/SETUP.md)
- [Testing Guide](docs/testing/TESTING.md)

### Curriculum Format (UMCF)
- [Curriculum Overview](curriculum/README.md) - **Comprehensive guide to UMCF**
- [UMCF Specification](curriculum/spec/UMCF_SPECIFICATION.md) - Format specification
- [Standards Traceability](curriculum/spec/STANDARDS_TRACEABILITY.md) - Standards mapping
- [Import Architecture](curriculum/importers/IMPORTER_ARCHITECTURE.md) - Import system design

### Architecture & Design
- [Project Overview](docs/architecture/PROJECT_OVERVIEW.md) - High-level architecture
- [Patch Panel Architecture](docs/architecture/PATCH_PANEL_ARCHITECTURE.md) - LLM routing system
- [Technical Design Document](docs/architecture/UnaMentis_TDD.md) - Complete TDD

### Standards & Guidelines
- [AI Development Guidelines](AGENTS.md) - Guidelines for AI-assisted development
- iOS Style Guide and Best Practices are maintained in the [unamentis-ios](https://github.com/UnaMentis/unamentis-ios) repository

### Project
- [Contributing](docs/CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [Task Status](docs/TASK_STATUS.md) - Current implementation progress

## Development

```bash
# Run server tests (Python)
cd server/management && python -m pytest

# Format code
./scripts/format.sh

# Lint code
./scripts/lint.sh

# Health check
./scripts/health-check.sh
```

### Latency Testing

UnaMentis includes a comprehensive latency test harness for validating performance targets (<500ms E2E latency):

```bash
# List available test suites
python -m latency_harness.cli --list-suites

# Quick validation (uses mocks, fast)
python -m latency_harness.cli --suite quick_validation --mock

# Real provider testing
python -m latency_harness.cli --suite quick_validation --no-mock

# Full provider comparison (~30 min)
python -m latency_harness.cli --suite provider_comparison --no-mock
```

Features:
- High-precision timing
- Network projections (localhost, WiFi, cellular)
- Baseline comparison for regression detection
- Web dashboard at Operations Console → Latency Tests
- REST API for programmatic access

See [docs/LATENCY_TEST_HARNESS_GUIDE.md](docs/LATENCY_TEST_HARNESS_GUIDE.md) for complete documentation.

## Code Quality Infrastructure

UnaMentis implements a comprehensive **5-phase Code Quality Initiative** that enables enterprise-grade quality standards through intelligent automation:

### Quality Gates

| Gate | Threshold | Enforcement |
|------|-----------|-------------|
| Code Coverage | 80% minimum | CI fails if below |
| Latency (P50) | 500ms | CI warns/fails on regression |
| Linting | Zero violations | Pre-commit hook |
| Security Scan | Zero critical findings | CI + weekly audit |

### Automation Tools

- **Pre-commit Hooks**: Ruff, ESLint, Clippy, Gitleaks
- **Hook Bypass Auditing**: Detect `--no-verify` usage with `scripts/hook-audit.sh`
- **Dependency Management**: Renovate with auto-merge for patches
- **AI Code Review**: CodeRabbit (free for open source)
- **Performance Testing**: Automated latency regression detection
- **Security Scanning**: CodeQL, Gitleaks, pip-audit, npm audit
- **DORA Metrics**: Apache DevLake for engineering health
- **Mutation Testing**: Weekly validation with mutmut (Python), Stryker (Web)
- **Chaos Engineering**: Voice pipeline resilience testing (see [runbook](docs/testing/CHAOS_ENGINEERING_RUNBOOK.md))

### Feature Flags

Self-hosted Unleash system with full lifecycle management:
- iOS SDK with SwiftUI integration
- Web SDK with React hooks
- Automated stale flag detection

```bash
# Install quality infrastructure
./scripts/install-hooks.sh      # Git hooks
./scripts/hook-audit.sh         # Check for bypasses
cd server/devlake && docker compose up -d    # DORA metrics
cd server/feature-flags && docker compose up -d  # Feature flags
```

See [docs/quality/CODE_QUALITY_INITIATIVE.md](docs/quality/CODE_QUALITY_INITIATIVE.md) for the complete quality initiative documentation, including mutation testing and chaos engineering.

## Architecture

```
server/
├── usm-core/        # Rust cross-platform service manager (port 8787)
├── management/      # Management API (port 8766)
├── web/             # Operations Console (port 3000)
├── web-client/      # Web Client (voice learning for browsers)
├── importers/       # Curriculum import framework
└── latency_harness/ # Latency testing CLI and orchestrator

curriculum/
├── spec/            # UMCF specification and JSON schema
├── importers/       # Import architecture docs
└── examples/        # Example curriculum files
```

## Web Interfaces

UnaMentis includes three web-based interfaces:

### Web Client (voice learning)
Browser-based voice learning that matches iOS app capabilities:
- Real-time voice conversations with the AI learning partner (OpenAI Realtime API via WebRTC)
- Full curriculum browser and lesson playback
- Rich visual asset display (formulas, diagrams, maps, charts)
- Responsive design for desktop and mobile browsers
- Sub-500ms latency voice interaction

See [server/web-client/README.md](server/web-client/README.md) for setup and documentation.

### Operations Console (port 3000)
Backend infrastructure monitoring for DevOps:
- System health (CPU, memory, thermal, battery)
- Service status and management
- Power/idle profiles
- Logs, metrics, performance data

### Management API (port 8766)
Application and content management:
- Curriculum management (import, browse, edit)
- Visual asset management
- User progress tracking
- Source browser for external curriculum
- AI enrichment pipeline

## Technology Stack

### Server Infrastructure
- **Service Manager**: Rust (USM Core, port 8787)
- **Management API**: Python/aiohttp (port 8766)
- **Operations Console**: Next.js/React/TypeScript (port 3000)
- **Web Client**: Next.js/React (voice learning for browsers)
- **Importers**: Python with pluggy plugin architecture

### Speech-to-Text (STT)
| Provider | Model | Type | Notes |
|----------|-------|------|-------|
| Apple Speech | Native | On-device | Zero cost, ~150ms latency |
| GLM-ASR | Whisper encoder + GLM-ASR-Nano | On-device | CoreML + llama.cpp, requires A17+ |
| Groq | Whisper-large-v3-turbo | Cloud | Free tier (14,400 req/day), 300x real-time |
| Deepgram | Nova-3 | Cloud | WebSocket streaming, ~300ms latency |
| AssemblyAI | Universal-2 | Cloud | Word-level timestamps |
| Self-hosted | Whisper-compatible | Local | whisper.cpp, faster-whisper |

### Text-to-Speech (TTS)
| Provider | Model | Type | Notes |
|----------|-------|------|-------|
| Apple TTS | AVSpeechSynthesizer | On-device | Zero cost, ~50ms TTFB |
| Kyutai | TTS 1.6B | Self-hosted | 40+ voices, emotion control, batch processing |
| Kyutai | Pocket TTS (100M) | On-device/CPU | 8 voices, sub-50ms latency |
| Chatterbox | Chatterbox-turbo (350M) | Self-hosted | Emotion control, voice cloning |
| Deepgram | Aura-2 | Cloud | Multiple voices, 24kHz |
| ElevenLabs | Turbo v2.5 | Cloud | Premium quality, WebSocket |
| VibeVoice | VibeVoice-Realtime-0.5B | Self-hosted | Microsoft model, real-time |

### Large Language Models (LLM)
| Provider | Model | Type | Notes |
|----------|-------|------|-------|
| On-device | Ministral-3B-Instruct-Q4_K_M | On-device | Primary on-device, via llama.cpp |
| On-device | TinyLlama-1.1B-Chat | On-device | Fallback, smaller footprint |
| Ollama | Mistral 7B | Self-hosted | **Primary server model** |
| Ollama | qwen2.5:32b, llama3.2:3b | Self-hosted | Alternative server models |
| Anthropic | Claude 3.5 Sonnet | Cloud | Primary cloud model |
| OpenAI | GPT-4o / GPT-4o-mini | Cloud | Alternative cloud option |

### Voice Activity Detection (VAD)
- **Silero VAD**: Core ML model for on-device speech detection

## Curriculum System (UMCF)

UnaMentis includes a comprehensive curriculum format specification: the **Una Mentis Curriculum Format (UMCF)**. This is a JSON-based standard designed specifically for conversational AI learning.

### Key Features

- **Voice-native**: Content optimized for text-to-speech delivery
- **Standards-based**: Built on IEEE LOM, LRMI, SCORM, xAPI, QTI, and more
- **Tutoring-first**: Stopping points, comprehension checks, misconception handling
- **AI-enrichable**: Designed for automated content enhancement

### Curriculum Documentation

| Document | Description |
|----------|-------------|
| [curriculum/README.md](curriculum/README.md) | **START HERE** - Complete overview |
| [curriculum/spec/UMCF_SPECIFICATION.md](curriculum/spec/UMCF_SPECIFICATION.md) | Human-readable specification |
| [curriculum/spec/umcf-schema.json](curriculum/spec/umcf-schema.json) | JSON Schema (Draft 2020-12) |
| [curriculum/spec/STANDARDS_TRACEABILITY.md](curriculum/spec/STANDARDS_TRACEABILITY.md) | Field-by-field standards mapping |

### Import System

UMCF includes a pluggable import architecture for converting external curriculum formats:

| Importer | Source | Target Audience |
|----------|--------|-----------------|
| CK-12 | FlexBooks (EPUB) | K-12 education |
| Fast.ai | Jupyter notebooks | Collegiate AI/ML |
| AI Enrichment | Raw text | Any (sparse → rich) |

See [curriculum/importers/](curriculum/importers/) for specifications.

### Future Direction

UMCF may be spun off as a standalone project to enable adoption by other learning systems. The specification is designed for academic review and potential standardization.

---

## Project Vision

### Open Source Core

The fundamental core of UnaMentis will always remain open source. This ensures the greatest possible audience can collaborate on and utilize this work. The open source commitment includes:

- Core voice pipeline and session management
- Curriculum system and progress tracking
- All provider integrations
- Cross-platform support (planned)

### Current Platform Support

- **iOS**: Primary platform, pre-beta ([unamentis-ios](https://github.com/UnaMentis/unamentis-ios))
- **Web**: Browser-based voice learning (Chrome, Safari, Edge recommended)
- **Android**: In active development ([unamentis-android](https://github.com/UnaMentis/unamentis-android))
- **Server**: Management API, Operations Console, and USM Core (this repo)

### Future Directions

- **Desktop apps**: Native macOS and Windows applications
- **Plugin architecture**: Extensible system for value-added capabilities
- **Enhanced collaboration**: Multi-user learning sessions

## Support the Project

UnaMentis is fiscally hosted by [Open Collective Europe](https://opencollective.com/europe). Your donations directly support ongoing development, server costs, and infrastructure.

<a href="https://opencollective.com/unamentis/donate" target="_blank">
  <img src="https://opencollective.com/unamentis/donate/button@2x.png?color=blue" width="300" />
</a>

### Backers

Thank you to all our backers!

<a href="https://opencollective.com/unamentis">
  <img src="https://opencollective.com/unamentis/backers.svg?width=890" />
</a>

### Sponsors

Support this project by becoming a sponsor. Your logo will appear here with a link to your website.

<a href="https://opencollective.com/unamentis">
  <img src="https://opencollective.com/unamentis/sponsors.svg?width=890" />
</a>

## Contributing

Contributions are welcome! Please read our [Contributing Guide](docs/CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before submitting PRs.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

Copyright (c) 2025-2026 Richard Amerman
