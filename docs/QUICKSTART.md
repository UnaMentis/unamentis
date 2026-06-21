# UnaMentis - Quick Start Guide

**Get the UnaMentis server stack running locally.**

This repository contains the server infrastructure, curriculum system, and project-wide documentation. For the iOS app, see the [unamentis-ios](https://github.com/UnaMentis/unamentis-ios) repository. The Android client ([unamentis-android](https://github.com/UnaMentis/unamentis-android)) is paused.

---

## What You Get

- **Management API** (Python/aiohttp, port 8766): curriculum, imports, telemetry, TTS caching
- **Operations Console** (Next.js, port 3000): system health, logs, Voice Lab, Curriculum Studio
- **Web Client** (Next.js): browser-based voice learning
- **USM Core** (Rust, port 8787): cross-platform service manager
- **Latency test harness** (Python CLI): automated voice-pipeline latency testing
- **Curriculum importers**: source plugins for MIT OCW, CK-12, EngageNY, MERLOT, and Knowledge Bowl question sources

---

## Prerequisites

- **macOS or Linux**
- **Python**: 3.11+
- **Node.js**: 20+ with **pnpm**
- **Rust**: stable toolchain (only needed for USM Core)

Optional:
- API keys for cloud providers (Deepgram, ElevenLabs, Anthropic, OpenAI, AssemblyAI)
- Local inference servers (Ollama, whisper.cpp, Piper) for zero-cost providers

---

## Step 1: Clone and Configure (5 minutes)

```bash
git clone https://github.com/UnaMentis/unamentis.git
cd unamentis

# Create your environment file
cp .env.example .env
# Edit .env and add the API keys you have; everything degrades gracefully without them
```

---

## Step 2: Start the Management API (port 8766)

```bash
cd server/management
./run.sh
```

Then open http://localhost:8766 to confirm it is up.

---

## Step 3: Start the Operations Console (port 3000)

```bash
cd server/web
pnpm install
pnpm dev
```

Open http://localhost:3000 for system health, logs, Curriculum Studio, and Voice Lab.

---

## Step 4: Run the Latency Harness (2 minutes)

```bash
cd server

# List available suites
python -m latency_harness.cli --list-suites

# Quick validation in mock mode (no API keys needed)
python -m latency_harness.cli --suite quick_validation --mock

# Real providers (requires keys in .env)
python -m latency_harness.cli --suite quick_validation --no-mock
```

See [LATENCY_TEST_HARNESS_GUIDE.md](LATENCY_TEST_HARNESS_GUIDE.md) for full documentation.

---

## Step 5: Build USM Core (Optional)

```bash
cd server/usm-core
cargo build            # Debug build
cargo test             # Run tests
```

USM Core serves the service-management API on port 8787. See [server/usm-core/README.md](../server/usm-core/README.md).

---

## Running Tests

All test commands use tracked tooling only:

```bash
# Management API tests
cd server/management && python -m pytest

# Importer tests
cd server/importers && python -m pytest

# Rust tests (USM Core)
./scripts/test-rust.sh

# Operations Console tests
cd server/web && pnpm test
```

---

## Repository Structure

```
unamentis/
├── server/
│   ├── usm-core/        # Rust service manager (port 8787)
│   ├── management/      # Management API (port 8766)
│   ├── web/             # Operations Console (port 3000)
│   ├── web-client/      # Web Client (browser voice learning)
│   ├── importers/       # Curriculum import framework
│   └── latency_harness/ # Latency testing CLI
├── curriculum/          # UMCF specification and examples
└── docs/                # Cross-cutting documentation
```

---

## Curriculum System (UMCF)

UnaMentis uses the **Una Mentis Curriculum Format (UMCF)** for structured educational content. This is a JSON-based format designed for conversational AI learning.

### Quick Overview

- **Voice-native**: Every text field can have TTS-optimized variants
- **Standards-based**: Built on IEEE LOM, SCORM, xAPI, QTI, and 6+ other standards
- **Tutoring-first**: Stopping points, comprehension checks, alternative explanations
- **AI-enrichable**: Designed for automated content enhancement

### Curriculum Documentation

| Document | Description |
|----------|-------------|
| [Curriculum README](../curriculum/README.md) | **Comprehensive overview** |
| [UMCF Specification](../curriculum/spec/UMCF_SPECIFICATION.md) | Format specification |
| [JSON Schema](../curriculum/spec/umcf-schema.json) | Schema for validation |
| [Examples](../curriculum/examples/) | Example UMCF library |

### Import System

Source importers are implemented for MIT OCW, CK-12, EngageNY, and MERLOT; the AI enrichment pipeline that upgrades imported content to rich UMCF is in progress. See [Import Architecture](../curriculum/importers/IMPORTER_ARCHITECTURE.md).

---

## Documentation Index

| Document | Purpose |
|----------|---------|
| [STATUS.md](STATUS.md) | Honest "what works today" summary |
| [PROJECT_OVERVIEW.md](architecture/PROJECT_OVERVIEW.md) | Authoritative project overview |
| [UnaMentis_TDD.md](architecture/UnaMentis_TDD.md) | Full technical design |
| [SETUP.md](setup/SETUP.md) | Detailed setup instructions |
| [TESTING.md](testing/TESTING.md) | Testing guide |
| [TASK_STATUS.md](TASK_STATUS.md) | Implementation status |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |

---

## Next Steps

1. **Explore the Operations Console** at http://localhost:3000
2. **Browse the curriculum format** in [curriculum/README.md](../curriculum/README.md)
3. **Run a latency suite** against your provider keys
4. **Set up the iOS app** from [unamentis-ios](https://github.com/UnaMentis/unamentis-ios)

---

**Questions?** Open an issue on GitHub.
