# UnaMentis iOS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Real-time bidirectional, hands free, mobile, voice learning platform that uses AI on device and on a server to provide extensive learning sessions.
These sessions can be ad-hoc or based on proven curriculum from many well known sources.**

## Why UnaMentis?

One of my earliest experiences re-engaging with AI earlier this year was with ChatGPT's Advanced Voice Mode. Very quickly, I fell in love with the capability of having seamless, hands-free conversations with AI. Initially these were about bouncing off ideas and exploring things, but it evolved into the ultimate way of learning. I could give advanced topics to the AI and it would deliver detailed lectures on demand.

That capability was completely killed when ChatGPT 5.0 came out. No other models or tools have matched ChatGPT's seamless user experience. It got better with 5.1, but it's been hit or miss. Lately it's been useless again.

I realized I can't rely on off-the-shelf tools to meet this need. There's a lot of more advanced things I can bring to this purpose. I really think this is ultimately a universal need: a personalized tutor that can work with you over long stretches of time, develop an understanding of your learning progress and learning style, and evolve into a true personal tutor over time.

## Overview

UnaMentis is an iOS application that enables 60-90+ minute voice-based learning sessions with AI tutoring. Built for iPhone 16/17 Pro Max with emphasis on:

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
# 1. Create Xcode project (manual - see docs/QUICKSTART.md)

# 2. Set up environment
./scripts/setup-local-env.sh

# 3. Configure API keys
cp .env.example .env
# Edit .env and add your keys

# 4. Run tests
./scripts/test-quick.sh
```

See [Quick Start Guide](docs/QUICKSTART.md) for complete setup.

## Current Status

**Part 1 Complete (Autonomous Implementation)**
- All unit tests pass (103+ tests)
- All integration tests pass (16+ tests)
- Core components implemented: SessionManager, AudioEngine, CurriculumEngine, TelemetryEngine
- All UI views connected to data sources
- TTS playback with streaming audio support
- Debug/Testing UI for subsystem validation

**Part 2 Pending (Requires User Participation)**
- API key configuration
- Physical device testing
- Content setup and curriculum creation
- Performance optimization

See [docs/TASK_STATUS.md](docs/TASK_STATUS.md) for detailed task tracking.

## Documentation

### Getting Started
- [Quick Start Guide](docs/QUICKSTART.md) - START HERE
- [Setup Guide](docs/SETUP.md)
- [Testing Guide](docs/TESTING.md)
- [Debug & Testing UI](docs/DEBUG_TESTING_UI.md) - Built-in troubleshooting tools

### Curriculum Format (UMLCF)
- [Curriculum Overview](curriculum/README.md) - **Comprehensive guide to UMLCF**
- [UMLCF Specification](curriculum/spec/VLCF_SPECIFICATION.md) - Format specification
- [Standards Traceability](curriculum/spec/STANDARDS_TRACEABILITY.md) - Standards mapping
- [Import Architecture](curriculum/importers/IMPORTER_ARCHITECTURE.md) - Import system design
- [Pronunciation Guide](docs/PRONUNCIATION_GUIDE.md) - TTS pronunciation enhancement system

### Architecture & Design
- [Project Overview](docs/PROJECT_OVERVIEW.md) - High-level architecture
- [Enterprise Architecture](docs/ENTERPRISE_ARCHITECTURE.md) - Comprehensive system design
- [Patch Panel Architecture](docs/PATCH_PANEL_ARCHITECTURE.md) - LLM routing system
- [Technical Design Document](docs/UnaMentis_TDD.md) - Complete TDD

### Standards & Guidelines
- [iOS Style Guide](docs/IOS_STYLE_GUIDE.md) - **MANDATORY** coding standards, accessibility, i18n
- [iOS Best Practices Review](docs/IOS_BEST_PRACTICES_REVIEW.md) - Platform compliance audit
- [AI Development Guidelines](AGENTS.md) - Guidelines for AI-assisted development

### Project
- [Contributing](docs/CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [Task Status](docs/TASK_STATUS.md) - Current implementation progress

## Development

```bash
# Quick tests
./scripts/test-quick.sh

# All tests
./scripts/test-all.sh

# Format code
./scripts/format.sh

# Lint code
./scripts/lint.sh

# Health check
./scripts/health-check.sh
```

## Architecture

```
UnaMentis/
├── Core/           # Core business logic
│   ├── Audio/      # Audio engine, VAD
│   ├── Session/    # Session management
│   ├── Curriculum/ # Learning materials
│   └── Telemetry/  # Metrics
├── Services/       # Provider integrations
│   ├── STT/        # Speech-to-text
│   ├── TTS/        # Text-to-speech
│   └── LLM/        # Language models
└── UI/             # SwiftUI views

server/
├── management/     # Management Console (port 8766)
└── web/            # Operations Console (port 3000)
```

## Web Interfaces

UnaMentis includes two web-based administration interfaces:

### Operations Console (port 3000)
Backend infrastructure monitoring for DevOps:
- System health (CPU, memory, thermal, battery)
- Service status and management
- Power/idle profiles
- Logs, metrics, performance data

### Management Console (port 8766)
Application and content management:
- Curriculum management (import, browse, edit)
- Visual asset management
- User progress tracking
- Source browser for external curriculum
- AI enrichment pipeline

## Technology Stack

### Core Platform
- **Language**: Swift 6.0
- **UI**: SwiftUI
- **Audio**: AVFoundation
- **Transport**: LiveKit WebRTC
- **ML Framework**: Core ML, llama.cpp (C++ interop)
- **Persistence**: Core Data
- **Testing**: XCTest (no mocks, real implementations)

### Speech-to-Text (STT)
| Provider | Model | Type | Notes |
|----------|-------|------|-------|
| Apple Speech | Native | On-device | Zero cost, ~150ms latency |
| GLM-ASR | Whisper encoder + GLM-ASR-Nano | On-device | CoreML + llama.cpp, requires A19 Pro |
| Deepgram | Nova-3 | Cloud | WebSocket streaming, ~300ms latency |
| AssemblyAI | Universal-2 | Cloud | Word-level timestamps |
| Self-hosted | Whisper-compatible | Local | whisper.cpp, faster-whisper |

### Text-to-Speech (TTS)
| Provider | Model | Type | Notes |
|----------|-------|------|-------|
| Apple TTS | AVSpeechSynthesizer | On-device | Zero cost, ~50ms TTFB |
| Deepgram | Aura-2 | Cloud | Multiple voices, 24kHz |
| ElevenLabs | Turbo v2.5 | Cloud | Premium quality, WebSocket |
| Microsoft | VibeVoice-Realtime-0.5B | Self-hosted | Via Piper/custom server |

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

## Curriculum System (UMLCF)

UnaMentis includes a comprehensive curriculum format specification: the **UnaMentis Markup Language Curriculum Format (UMLCF)**. This is a JSON-based standard designed specifically for conversational AI tutoring.

### Key Features

- **Voice-native**: Content optimized for text-to-speech delivery
- **Standards-based**: Built on IEEE LOM, LRMI, SCORM, xAPI, QTI, and more
- **Tutoring-first**: Stopping points, comprehension checks, misconception handling
- **AI-enrichable**: Designed for automated content enhancement

### Curriculum Documentation

| Document | Description |
|----------|-------------|
| [curriculum/README.md](curriculum/README.md) | **START HERE** - Complete overview |
| [curriculum/spec/VLCF_SPECIFICATION.md](curriculum/spec/VLCF_SPECIFICATION.md) | Human-readable specification |
| [curriculum/spec/umlcf-schema.json](curriculum/spec/umlcf-schema.json) | JSON Schema (Draft 2020-12) |
| [curriculum/spec/STANDARDS_TRACEABILITY.md](curriculum/spec/STANDARDS_TRACEABILITY.md) | Field-by-field standards mapping |

### Import System

UMLCF includes a pluggable import architecture for converting external curriculum formats:

| Importer | Source | Target Audience |
|----------|--------|-----------------|
| CK-12 | FlexBooks (EPUB) | K-12 education |
| Fast.ai | Jupyter notebooks | Collegiate AI/ML |
| AI Enrichment | Raw text | Any (sparse → rich) |

See [curriculum/importers/](curriculum/importers/) for specifications.

### Future Direction

UMLCF may be spun off as a standalone project to enable adoption by other tutoring systems. The specification is designed for academic review and potential standardization.

---

## Project Vision

### Open Source Core

The fundamental core of UnaMentis will always remain open source. This ensures the greatest possible audience can collaborate on and utilize this work. The open source commitment includes:

- Core voice pipeline and session management
- Curriculum system and progress tracking
- All provider integrations
- Cross-platform support (planned)

### Future Directions

- **Cross-platform**: Expand beyond iOS to Android, web, and desktop
- **Server component**: Enable cloud-hosted sessions and curriculum management
- **Plugin architecture**: Extensible system for value-added capabilities

### Enterprise Features (Future)

A separate commercial layer may offer enterprise-specific capabilities:

- Single sign-on (SSO) integration
- Advanced reporting and analytics
- Permission controls and user management
- Corporate curriculum publishing and management
- Priority support

These features would build on top of the open source core without restricting it.

## Contributing

Contributions are welcome! Please read our [Contributing Guide](docs/CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before submitting PRs.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

Copyright (c) 2025 Richard Amerman
