# UnaMentis Documentation

This repository is the project hub for UnaMentis. It contains server infrastructure, the curriculum system, and all cross-cutting documentation.

Client-specific documentation lives in each client repository:
- iOS: [unamentis-ios/docs/](https://github.com/UnaMentis/unamentis-ios/tree/main/docs)
- Android: [unamentis-android/docs/](https://github.com/UnaMentis/unamentis-android/tree/main/docs)

---

## Cross-Cutting Documentation (All Platforms)

These docs apply to all client implementations:

| Document | Description |
|----------|-------------|
| [client-spec/](client-spec/README.md) | Canonical UI/UX specification for all clients |
| [modules/](modules/SPECIALIZED_MODULES_FRAMEWORK.md) | Knowledge Bowl, SAT, Quiz Bowl, Science Bowl module specs |
| [design/HANDS_FREE_FIRST_DESIGN.md](design/HANDS_FREE_FIRST_DESIGN.md) | Voice-first interaction design for all platforms |
| [design/AUDIO_PLAYBACK_ORCHESTRATOR.md](design/AUDIO_PLAYBACK_ORCHESTRATOR.md) | Cross-platform audio pipeline specification |
| [testing/TESTING.md](testing/TESTING.md) | Real-over-mock testing philosophy |
| [testing/MOCK_VIOLATIONS_INVENTORY.md](testing/MOCK_VIOLATIONS_INVENTORY.md) | Mock violation patterns and remediation |

---

## Architecture

| Document | Description |
|----------|-------------|
| [architecture/PROJECT_OVERVIEW.md](architecture/PROJECT_OVERVIEW.md) | Authoritative project overview (kept current, used externally) |
| [architecture/UnaMentis_TDD.md](architecture/UnaMentis_TDD.md) | Technical Design Document |
| [architecture/PATCH_PANEL_ARCHITECTURE.md](architecture/PATCH_PANEL_ARCHITECTURE.md) | LLM routing and task classification |
| [architecture/FOV_CONTEXT_MANAGEMENT.md](architecture/FOV_CONTEXT_MANAGEMENT.md) | Foveated context for voice learning |
| [architecture/FALLBACK_ARCHITECTURE.md](architecture/FALLBACK_ARCHITECTURE.md) | Fallback and graceful degradation patterns |
| [architecture/SERVER_INFRASTRUCTURE.md](architecture/SERVER_INFRASTRUCTURE.md) | Server deployment architecture |
| [architecture/CLOUD_HOSTING_ARCHITECTURE.md](architecture/CLOUD_HOSTING_ARCHITECTURE.md) | Cloud hosting options and analysis |
| [architecture/CLOUD_DEPLOYMENT_EXECUTION_PLAN.md](architecture/CLOUD_DEPLOYMENT_EXECUTION_PLAN.md) | Cloud deployment execution plan |
| [architecture/DEVICE_CAPABILITY_TIERS.md](architecture/DEVICE_CAPABILITY_TIERS.md) | Device feature matrix by capability tier |
| [architecture/OPENTELEMETRY_SPEC.md](architecture/OPENTELEMETRY_SPEC.md) | Telemetry specification |
| [architecture/ARCHITECTURE_FOR_COMMUNICATIONS.md](architecture/ARCHITECTURE_FOR_COMMUNICATIONS.md) | Architecture summary for external communications |
| [architecture/QUALITY_INFRASTRUCTURE_RESEARCH.md](architecture/QUALITY_INFRASTRUCTURE_RESEARCH.md) | Quality infrastructure research |

---

## Server & Infrastructure

| Document | Description |
|----------|-------------|
| [server/README.md](server/README.md) | Server component overview |
| [server/VOICE_LAB_GUIDE.md](server/VOICE_LAB_GUIDE.md) | Voice Lab console section guide |
| [server/TTS_LAB_GUIDE.md](server/TTS_LAB_GUIDE.md) | TTS experimentation and batch processing |
| [server/RECOMMENDATIONS.md](server/RECOMMENDATIONS.md) | Server recommendations |
| [server/SERVER_IDLE_OPTIMIZATION_PLAN.md](server/SERVER_IDLE_OPTIMIZATION_PLAN.md) | Idle resource optimization plan |
| [server/SERVER_RESOURCE_MONITORING_PLAN.md](server/SERVER_RESOURCE_MONITORING_PLAN.md) | Resource monitoring plan |
| [api-spec/README.md](api-spec/README.md) | Server REST API specification |
| [LATENCY_TEST_HARNESS_GUIDE.md](LATENCY_TEST_HARNESS_GUIDE.md) | Latency test harness usage guide |
| [design/AUDIO_LATENCY_TEST_HARNESS.md](design/AUDIO_LATENCY_TEST_HARNESS.md) | Latency harness architecture |
| [REMOTE_LOGGING.md](REMOTE_LOGGING.md) | Log server and remote debugging |
| [FEATURE_FLAGS.md](FEATURE_FLAGS.md) | Feature flag definitions |
| [FEATURE_FLAGS_ARCHITECTURE.md](FEATURE_FLAGS_ARCHITECTURE.md) | Feature flag system architecture |

---

## AI & Machine Learning

| Document | Description |
|----------|-------------|
| [ai-ml/GLM_ASR_ON_DEVICE_GUIDE.md](ai-ml/GLM_ASR_ON_DEVICE_GUIDE.md) | On-device STT implementation |
| [ai-ml/GLM_ASR_NANO_2512.md](ai-ml/GLM_ASR_NANO_2512.md) | GLM-ASR Nano model details |
| [ai-ml/GLM_ASR_SERVER_TRD.md](ai-ml/GLM_ASR_SERVER_TRD.md) | Server-side ASR design |
| [ai-ml/GLM_ASR_IMPLEMENTATION_PROGRESS.md](ai-ml/GLM_ASR_IMPLEMENTATION_PROGRESS.md) | GLM-ASR implementation status |
| [ai-ml/APPLE_INTELLIGENCE.md](ai-ml/APPLE_INTELLIGENCE.md) | App Intents and Siri integration |
| [ai-ml/LLM_TOOLS.md](ai-ml/LLM_TOOLS.md) | LLM tool use implementation |
| [ai-ml/CHATTERBOX_SERVER_SETUP.md](ai-ml/CHATTERBOX_SERVER_SETUP.md) | Chatterbox TTS server setup |
| [AI_MODEL_SELECTION_2026.md](AI_MODEL_SELECTION_2026.md) | 2026 AI model selection analysis |
| [integrations/POCKET_TTS.md](integrations/POCKET_TTS.md) | Kyutai Pocket TTS integration |

---

## Testing

| Document | Description |
|----------|-------------|
| [testing/TESTING.md](testing/TESTING.md) | Testing philosophy and guide |
| [testing/CHAOS_ENGINEERING_RUNBOOK.md](testing/CHAOS_ENGINEERING_RUNBOOK.md) | Voice pipeline resilience testing |
| [testing/MOCK_VIOLATIONS_INVENTORY.md](testing/MOCK_VIOLATIONS_INVENTORY.md) | Mock violation patterns and remediation |
| [testing/AI_SIMULATOR_TESTING.md](testing/AI_SIMULATOR_TESTING.md) | Simulator testing with MCP |
| [testing/DEBUG_TESTING_UI.md](testing/DEBUG_TESTING_UI.md) | Built-in troubleshooting tools |
| [testing/KNOWLEDGE_BOWL_VALIDATION_TESTING.md](testing/KNOWLEDGE_BOWL_VALIDATION_TESTING.md) | Knowledge Bowl validation testing |
| [testing/QA_COVERAGE_AUDIT_REPORT.md](testing/QA_COVERAGE_AUDIT_REPORT.md) | QA coverage audit report |

---

## Quality & Process

| Document | Description |
|----------|-------------|
| [quality/DEVELOPMENT_EXCELLENCE.md](quality/DEVELOPMENT_EXCELLENCE.md) | Development tooling and automation plan |
| [quality/TOOL_TRUST_DOCTRINE.md](quality/TOOL_TRUST_DOCTRINE.md) | Tool findings trust policy |
| [quality/CODE_QUALITY_INITIATIVE.md](quality/CODE_QUALITY_INITIATIVE.md) | Code quality initiative |
| [quality/QUALITY_INFRASTRUCTURE_PLAN.md](quality/QUALITY_INFRASTRUCTURE_PLAN.md) | Quality infrastructure plan |
| [reviews/EXPERT_PANEL_REVIEW.md](reviews/EXPERT_PANEL_REVIEW.md) | Expert panel review (42 findings) |
| [reviews/EXPERT_PANEL_SOCRATIC_ENGINE.md](reviews/EXPERT_PANEL_SOCRATIC_ENGINE.md) | Socratic Engine proposal |

---

## Setup & Tools

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | Quick start guide for new developers |
| [setup/SETUP.md](setup/SETUP.md) | Detailed setup instructions |
| [setup/DEV_ENVIRONMENT.md](setup/DEV_ENVIRONMENT.md) | Developer environment configuration |
| [setup/DEVICE_SETUP_GUIDE.md](setup/DEVICE_SETUP_GUIDE.md) | Physical device configuration |
| [setup/CODERABBIT_SETUP.md](setup/CODERABBIT_SETUP.md) | CodeRabbit AI review setup |
| [setup/COMMS_SKILL_SETUP_GUIDE.md](setup/COMMS_SKILL_SETUP_GUIDE.md) | Slack/Trello communications setup |
| [tools/CODERABBIT.md](tools/CODERABBIT.md) | CodeRabbit AI code review usage |
| [tools/CROSS_REPO_ACCESS.md](tools/CROSS_REPO_ACCESS.md) | Cross-repository access for AI agents |
| [tools/GITHUB_WIKI.md](tools/GITHUB_WIKI.md) | GitHub Wiki setup and usage |

---

## Project Governance

| Document | Description |
|----------|-------------|
| [ABOUT.md](ABOUT.md) | About UnaMentis, core values, and mission |
| [PHILOSOPHY.md](PHILOSOPHY.md) | Founding philosophy on genuine learning |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |
| [PRIVACY_PRESERVING_USER_DATA.md](PRIVACY_PRESERVING_USER_DATA.md) | Privacy architecture |
| [APP_STORE_COMPLIANCE.md](APP_STORE_COMPLIANCE.md) | App Store compliance documentation |
| [TASK_STATUS.md](TASK_STATUS.md) | Current implementation progress |

---

## Specialized Modules

| Document | Description |
|----------|-------------|
| [modules/SPECIALIZED_MODULES_FRAMEWORK.md](modules/SPECIALIZED_MODULES_FRAMEWORK.md) | Module design methodology |
| [modules/KNOWLEDGE_BOWL_MODULE.md](modules/KNOWLEDGE_BOWL_MODULE.md) | Knowledge Bowl competition prep |
| [modules/KNOWLEDGE_BOWL_ANSWER_VALIDATION.md](modules/KNOWLEDGE_BOWL_ANSWER_VALIDATION.md) | 3-tier answer validation system |
| [modules/KNOWLEDGE_BOWL_MODULE_SPEC.md](modules/KNOWLEDGE_BOWL_MODULE_SPEC.md) | Knowledge Bowl module specification |
| [modules/KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md](modules/KNOWLEDGE_BOWL_CHAMPIONSHIP_SYSTEM.md) | Knowledge Bowl championship system |
| [modules/QUIZ_BOWL_MODULE_SPEC.md](modules/QUIZ_BOWL_MODULE_SPEC.md) | Quiz Bowl module specification |
| [modules/SCIENCE_BOWL_MODULE_SPEC.md](modules/SCIENCE_BOWL_MODULE_SPEC.md) | Science Bowl module specification |
| [modules/ACADEMIC_COMPETITION_MODULAR_ARCHITECTURE.md](modules/ACADEMIC_COMPETITION_MODULAR_ARCHITECTURE.md) | Academic competition modular architecture |
| [modules/SAT_MODULE.md](modules/SAT_MODULE.md) | SAT Preparation Module |
| [modules/UNIFIED_PROFICIENCY_SYSTEM.md](modules/UNIFIED_PROFICIENCY_SYSTEM.md) | Unified proficiency system |
| [modules/TRAINING_DATA_SOURCES.md](modules/TRAINING_DATA_SOURCES.md) | Training data sources |
| [modules/MASTER_TECHNICAL_IMPLEMENTATION.md](modules/MASTER_TECHNICAL_IMPLEMENTATION.md) | Master technical implementation |

---

## Features & UX

| Document | Description |
|----------|-------------|
| [TRANSCRIPT_DRIVEN_TUTORING.md](TRANSCRIPT_DRIVEN_TUTORING.md) | Tiered tutoring approach |
| [CURRICULUM_SESSION_UX.md](CURRICULUM_SESSION_UX.md) | Curriculum playback experience |

---

## Explorations & Research

| Document | Description |
|----------|-------------|
| [explorations/LEARNER_PROFILE_EXPLORATION.md](explorations/LEARNER_PROFILE_EXPLORATION.md) | Learner profiling approach |
| [explorations/MULTILINGUAL_VOICE_LEARNING_EXPLORATION.md](explorations/MULTILINGUAL_VOICE_LEARNING_EXPLORATION.md) | Multi-language support |
| [explorations/WATCH_APP_EXPLORATION.md](explorations/WATCH_APP_EXPLORATION.md) | Apple Watch companion |
| [explorations/VERIFIED_KNOWLEDGE_STREAM_EXPLORATION.md](explorations/VERIFIED_KNOWLEDGE_STREAM_EXPLORATION.md) | Verified knowledge stream |
| [explorations/AGNO_IOS_AGENT_ARCHITECTURE_EXPLORATION.md](explorations/AGNO_IOS_AGENT_ARCHITECTURE_EXPLORATION.md) | Agno iOS agent architecture |
| [explorations/commercial-stt-tts-providers.md](explorations/commercial-stt-tts-providers.md) | STT/TTS provider comparison |
| [CURRICULUM_SOURCE_API_RESEARCH.md](CURRICULUM_SOURCE_API_RESEARCH.md) | External curriculum sources |

---

## Curriculum Format (UMCF)

The curriculum format has its own comprehensive documentation:

| Document | Description |
|----------|-------------|
| [../curriculum/README.md](../curriculum/README.md) | Start here for UMCF |
| [../curriculum/spec/UMCF_SPECIFICATION.md](../curriculum/spec/UMCF_SPECIFICATION.md) | Format specification |
| [../curriculum/spec/STANDARDS_TRACEABILITY.md](../curriculum/spec/STANDARDS_TRACEABILITY.md) | Standards mapping |

---

## AI Development

| Document | Description |
|----------|-------------|
| [../AGENTS.md](../AGENTS.md) | AI development guidelines |
| [../CLAUDE.md](../CLAUDE.md) | Claude Code instructions |

---

## Quick Links

- **New to the project?** Start with [QUICKSTART.md](QUICKSTART.md)
- **Understanding the vision?** Read [ABOUT.md](ABOUT.md) and [PHILOSOPHY.md](PHILOSOPHY.md)
- **Architecture overview?** See [architecture/PROJECT_OVERVIEW.md](architecture/PROJECT_OVERVIEW.md)
- **Working with curriculum?** See [../curriculum/README.md](../curriculum/README.md)
- **Server API?** See [api-spec/README.md](api-spec/README.md)
- **Debugging issues?** Check [REMOTE_LOGGING.md](REMOTE_LOGGING.md) and [testing/DEBUG_TESTING_UI.md](testing/DEBUG_TESTING_UI.md)
- **Development tooling?** See [quality/DEVELOPMENT_EXCELLENCE.md](quality/DEVELOPMENT_EXCELLENCE.md)
