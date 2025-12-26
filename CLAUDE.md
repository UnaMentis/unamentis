# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

UnaMentis is an iOS voice AI tutoring app built with Swift 6.0/SwiftUI. It enables 60-90+ minute voice-based learning sessions with sub-500ms latency. The project is developed with 100% AI assistance.

## Build & Test Commands

```bash
# Build for simulator
xcodebuild -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run all tests
xcodebuild test -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run specific test class
xcodebuild test -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:UnaMentisTests/ProgressTrackerTests

# Quick tests
./scripts/test-quick.sh

# All tests
./scripts/test-all.sh

# Lint and format
./scripts/lint.sh
./scripts/format.sh

# Health check (lint + quick tests)
./scripts/health-check.sh
```

## Architecture

```
UnaMentis/
├── Core/           # Business logic (actors)
│   ├── Audio/      # Audio pipeline, VAD integration
│   ├── Curriculum/ # Curriculum management, progress tracking
│   ├── Session/    # Session management
│   └── Telemetry/  # Metrics, cost tracking
├── Services/       # Provider integrations
│   ├── STT/        # Speech-to-text (AssemblyAI, Deepgram)
│   ├── TTS/        # Text-to-speech (ElevenLabs, Deepgram Aura)
│   └── LLM/        # Language models (OpenAI, Anthropic)
├── Intents/        # Siri & App Intents (iOS 16+)
├── UI/             # SwiftUI views
└── Persistence/    # Core Data stack

UnaMentisTests/
├── Unit/           # Unit tests
├── Integration/    # Integration tests
└── Helpers/        # Test utilities (MockServices.swift, TestDataFactory)

server/              # Backend servers
├── management/      # Management Console (port 8766) - Python/aiohttp
│   └── static/      # HTML/JS frontend for management features
├── database/        # Curriculum database
└── web/            # Operations Console (port 3000) - React/TypeScript
```

## Key Technical Requirements

**Swift 6.0 Strict Concurrency:**
- All services must be actors
- ViewModels use @MainActor
- Types crossing actor boundaries must be Sendable

**Testing Philosophy (Real Over Mock):**
- Only mock paid external APIs (LLM, STT, TTS, Embeddings)
- Use real implementations for all internal services
- Use `PersistenceController(inMemory: true)` for Core Data tests
- Use temp directories for file operations
- Mocks must be faithful: simulate realistic delays, validate inputs, reproduce all error conditions

**Performance Targets:**
- E2E turn latency: <500ms (median), <1000ms (P99)
- Memory growth: <50MB over 90 minutes
- Session stability: 90+ minutes without crashes

## Mandatory Style Requirements

Read `docs/IOS_STYLE_GUIDE.md` before implementation. Key requirements:

- Accessibility labels on all interactive elements
- Localizable strings for all user-facing text (use LocalizedStringKey)
- iPad adaptive layouts using size class detection
- Use NavigationStack/NavigationSplitView (not NavigationView)
- Minimum 44x44pt touch targets
- Support Dynamic Type scaling
- Respect Reduce Motion preference

## Writing Style

Never use em dashes or en dashes as sentence interrupters. Use commas for parenthetical phrases or periods to break up sentences.

## Multi-Agent Coordination

Check `docs/TASK_STATUS.md` before starting work. Claim tasks before working to prevent conflicts with other AI agents.

## Commit Convention

Follow Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `perf:`, `ci:`, `chore:`

Before committing: `./scripts/lint.sh && ./scripts/test-quick.sh`

## Server Work Requirements

When modifying server code, you MUST restart and verify changes before considering work complete:

1. Restart the affected server after code changes
2. Verify changes work via API calls or log inspection
3. Never tell the user to restart the server; that means you didn't finish

See `AGENTS.md` for detailed restart and verification procedures.

## Web Interfaces

UnaMentis has two separate web interfaces for different purposes:

### Operations Console (port 3000)
**Purpose:** Backend infrastructure monitoring (DevOps focus)
- System health monitoring (CPU, memory, thermal, battery)
- Service status (Ollama, VibeVoice, Piper, etc.)
- Power/idle management profiles
- Logs, metrics, and performance data
- Client connection monitoring

**Tech:** React/TypeScript (`server/web/`)
**URL:** http://localhost:3000

### Management Console (port 8766)
**Purpose:** Application management and content administration
- Curriculum management (import, browse, edit)
- User progress tracking and analytics
- Visual asset management
- Source browser for external curriculum import
- AI enrichment pipeline
- User management (future)

**Tech:** Python/aiohttp with vanilla JS (`server/management/`)
**URL:** http://localhost:8766

## Key Documentation

- `docs/IOS_STYLE_GUIDE.md` - Mandatory coding standards
- `docs/UnaMentis_TDD.md` - Technical design document
- `docs/TASK_STATUS.md` - Current task status
- `AGENTS.md` - AI development guidelines and testing philosophy
- `curriculum/README.md` - UMLCF curriculum format
