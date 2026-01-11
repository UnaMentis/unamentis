# UnaMentis Documentation

This directory contains the documentation for the UnaMentis project. Use this index to navigate the documentation.

---

## Directory Structure

```
docs/
├── setup/           # Environment and device setup guides
├── architecture/    # System design and technical documents
├── ios/             # iOS development standards and guides
├── testing/         # Testing guides and automation
├── ai-ml/           # AI/ML features (GLM-ASR, LLM tools)
├── explorations/    # Research and feature explorations
├── planning/        # Implementation plans
├── prompts/         # AI prompt templates
└── server/          # Server infrastructure docs
```

---

## Getting Started

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | Quick start guide for new developers |
| [setup/SETUP.md](setup/SETUP.md) | Detailed setup instructions |
| [setup/DEV_ENVIRONMENT.md](setup/DEV_ENVIRONMENT.md) | Developer environment configuration |
| [setup/DEVICE_SETUP_GUIDE.md](setup/DEVICE_SETUP_GUIDE.md) | Physical device configuration |

---

## Philosophy & Vision

| Document | Description |
|----------|-------------|
| [ABOUT.md](ABOUT.md) | About UnaMentis, core values, and mission |
| [PHILOSOPHY.md](PHILOSOPHY.md) | Founding philosophy on genuine learning |
| [architecture/PROJECT_OVERVIEW.md](architecture/PROJECT_OVERVIEW.md) | Technical overview and architecture |

---

## Architecture & Design

| Document | Description |
|----------|-------------|
| [architecture/UnaMentis_TDD.md](architecture/UnaMentis_TDD.md) | Technical Design Document |
| [architecture/PATCH_PANEL_ARCHITECTURE.md](architecture/PATCH_PANEL_ARCHITECTURE.md) | LLM routing and task classification |
| [architecture/FOV_CONTEXT_MANAGEMENT.md](architecture/FOV_CONTEXT_MANAGEMENT.md) | Foveated context for voice tutoring |
| [architecture/FALLBACK_ARCHITECTURE.md](architecture/FALLBACK_ARCHITECTURE.md) | Fallback and degradation patterns |
| [architecture/SERVER_INFRASTRUCTURE.md](architecture/SERVER_INFRASTRUCTURE.md) | Server deployment architecture |
| [architecture/CLOUD_HOSTING_ARCHITECTURE.md](architecture/CLOUD_HOSTING_ARCHITECTURE.md) | Cloud hosting options |
| [architecture/DEVICE_CAPABILITY_TIERS.md](architecture/DEVICE_CAPABILITY_TIERS.md) | Device feature matrix |
| [architecture/OPENTELEMETRY_SPEC.md](architecture/OPENTELEMETRY_SPEC.md) | Telemetry specification |

---

## iOS Development

| Document | Description |
|----------|-------------|
| [ios/IOS_STYLE_GUIDE.md](ios/IOS_STYLE_GUIDE.md) | **MANDATORY** iOS coding standards |
| [ios/IOS_BEST_PRACTICES_REVIEW.md](ios/IOS_BEST_PRACTICES_REVIEW.md) | Platform compliance audit |
| [ios/VISUAL_ASSET_SUPPORT.md](ios/VISUAL_ASSET_SUPPORT.md) | Visual content display system |
| [ios/PRONUNCIATION_GUIDE.md](ios/PRONUNCIATION_GUIDE.md) | TTS pronunciation enhancement |
| [ios/SPEAKER_MIC_BARGE_IN_DESIGN.md](ios/SPEAKER_MIC_BARGE_IN_DESIGN.md) | Voice interruption handling |

---

## Testing & QA

| Document | Description |
|----------|-------------|
| [testing/TESTING.md](testing/TESTING.md) | Testing guide and philosophy |
| [testing/AI_SIMULATOR_TESTING.md](testing/AI_SIMULATOR_TESTING.md) | Simulator testing with MCP |
| [testing/DEBUG_TESTING_UI.md](testing/DEBUG_TESTING_UI.md) | Built-in troubleshooting tools |

---

## AI/ML Features

| Document | Description |
|----------|-------------|
| [ai-ml/GLM_ASR_ON_DEVICE_GUIDE.md](ai-ml/GLM_ASR_ON_DEVICE_GUIDE.md) | On-device STT implementation |
| [ai-ml/GLM_ASR_NANO_2512.md](ai-ml/GLM_ASR_NANO_2512.md) | GLM-ASR Nano model details |
| [ai-ml/GLM_ASR_SERVER_TRD.md](ai-ml/GLM_ASR_SERVER_TRD.md) | Server-side ASR design |
| [ai-ml/GLM_ASR_IMPLEMENTATION_PROGRESS.md](ai-ml/GLM_ASR_IMPLEMENTATION_PROGRESS.md) | Implementation status |
| [ai-ml/APPLE_INTELLIGENCE.md](ai-ml/APPLE_INTELLIGENCE.md) | App Intents and Siri integration |
| [ai-ml/LLM_TOOLS.md](ai-ml/LLM_TOOLS.md) | LLM tool use implementation |
| [ai-ml/CHATTERBOX_SERVER_SETUP.md](ai-ml/CHATTERBOX_SERVER_SETUP.md) | Chatterbox TTS server setup |

---

## Server & Infrastructure

| Document | Description |
|----------|-------------|
| [server/README.md](server/README.md) | Server component overview |
| [REMOTE_LOGGING.md](REMOTE_LOGGING.md) | Log server and debugging |

---

## Features & UX

| Document | Description |
|----------|-------------|
| [TRANSCRIPT_DRIVEN_TUTORING.md](TRANSCRIPT_DRIVEN_TUTORING.md) | Tiered tutoring approach |
| [CURRICULUM_SESSION_UX.md](CURRICULUM_SESSION_UX.md) | Curriculum playback experience |

---

## Explorations & Research

These documents capture research and planning for features under consideration:

| Document | Description |
|----------|-------------|
| [explorations/LEARNER_PROFILE_EXPLORATION.md](explorations/LEARNER_PROFILE_EXPLORATION.md) | Learner profiling approach |
| [explorations/MULTILINGUAL_VOICE_LEARNING_EXPLORATION.md](explorations/MULTILINGUAL_VOICE_LEARNING_EXPLORATION.md) | Multi-language support |
| [explorations/WATCH_APP_EXPLORATION.md](explorations/WATCH_APP_EXPLORATION.md) | Apple Watch companion |
| [explorations/commercial-stt-tts-providers.md](explorations/commercial-stt-tts-providers.md) | STT/TTS provider comparison |
| [CURRICULUM_SOURCE_API_RESEARCH.md](CURRICULUM_SOURCE_API_RESEARCH.md) | External curriculum sources |
| [PRIVACY_PRESERVING_USER_DATA.md](PRIVACY_PRESERVING_USER_DATA.md) | Privacy architecture |

---

## Project Management

| Document | Description |
|----------|-------------|
| [TASK_STATUS.md](TASK_STATUS.md) | Current implementation progress |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |
| [DEVELOPMENT_EXCELLENCE.md](quality/DEVELOPMENT_EXCELLENCE.md) | Development tooling and automation plan |

---

## Curriculum Format (UMCF)

The curriculum format has its own comprehensive documentation:

| Document | Description |
|----------|-------------|
| [../curriculum/README.md](../curriculum/README.md) | **START HERE** for UMCF |
| [../curriculum/spec/UMCF_SPECIFICATION.md](../curriculum/spec/UMCF_SPECIFICATION.md) | Format specification |
| [../curriculum/spec/STANDARDS_TRACEABILITY.md](../curriculum/spec/STANDARDS_TRACEABILITY.md) | Standards mapping |

---

## AI Development

| Document | Description |
|----------|-------------|
| [../AGENTS.md](../AGENTS.md) | AI development guidelines |
| [../CLAUDE.md](../CLAUDE.md) | Claude Code instructions |

---

## Tools & Automation

| Document | Description |
|----------|-------------|
| [tools/CROSS_REPO_ACCESS.md](tools/CROSS_REPO_ACCESS.md) | Cross-repository access for AI agents |
| [tools/CODERABBIT.md](tools/CODERABBIT.md) | CodeRabbit AI code review |
| [tools/GITHUB_WIKI.md](tools/GITHUB_WIKI.md) | GitHub Wiki setup and usage |

---

## Quick Links

- **New to the project?** Start with [QUICKSTART.md](QUICKSTART.md)
- **Understanding the vision?** Read [ABOUT.md](ABOUT.md) and [PHILOSOPHY.md](PHILOSOPHY.md)
- **Writing iOS code?** Follow [ios/IOS_STYLE_GUIDE.md](ios/IOS_STYLE_GUIDE.md)
- **Working with curriculum?** See [../curriculum/README.md](../curriculum/README.md)
- **Debugging issues?** Check [testing/DEBUG_TESTING_UI.md](testing/DEBUG_TESTING_UI.md) and [REMOTE_LOGGING.md](REMOTE_LOGGING.md)
- **Development tooling?** See [DEVELOPMENT_EXCELLENCE.md](quality/DEVELOPMENT_EXCELLENCE.md)
