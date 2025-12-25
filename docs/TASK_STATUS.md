# UnaMentis Task Status

This document tracks all tasks for completing the UnaMentis iOS project. Tasks are divided into:
- **Part 1**: Autonomous tasks (AI agent can complete independently)
- **Part 2**: Collaborative tasks (requires user participation - API keys, device testing)

**Last Updated:** December 2025

---

## Current Project State

| Component | Status | Notes |
|-----------|--------|-------|
| Build | **Zero Errors** | `swift build` succeeds |
| Unit Tests | **126+ Passing** | Including 23 App Intents tests |
| Integration Tests | **16+ Passing** | Multi-component tests |
| Core Data | **Complete** | Manual NSManagedObject classes for SPM |
| Platform Compatibility | **Complete** | macOS + iOS builds work |
| GLM-ASR Server | **Implemented** | Server-side STT service |
| GLM-ASR On-Device | **Implemented** | On-device STT with CoreML + llama.cpp |
| iOS Simulator MCP | **Installed** | AI-driven testing capability |
| **Siri & App Intents** | **Implemented** | Voice commands, deep links, entities |
| Documentation | **Updated** | New guides for Apple Intelligence |
| **UI Simulator Testing** | **Verified** | All tabs functional, navigation working |

---

## PART 1: Autonomous Tasks (Agent Independent)

### 1. Build & Test Fixes

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 1.1 | Fix SessionManagerTests MainActor errors | completed | UnaMentisTests/Unit/SessionManagerTests.swift:23,43 | Added @MainActor to test methods |
| 1.2 | Restore deleted docs | completed | docs/implementation_plan.md, docs/task.md, docs/parallel_agent_curriculum_prompt.md | git checkout HEAD -- |
| 1.3 | Run full test suite | completed | - | All 103 tests pass |
| 1.4 | Fix Core Data SPM compatibility | completed | UnaMentis/Core/Persistence/ManagedObjects/*.swift | Created manual NSManagedObject subclasses |
| 1.5 | Fix macOS API compatibility | completed | Multiple UI files | Added #if os(iOS) guards |

### 2. UI Data Binding

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 2.1 | HistoryView - loadFromCoreData() | completed | UnaMentis/UI/History/HistoryView.swift | Fetch Session entities from Core Data |
| 2.2 | HistoryView - exportSession() | completed | UnaMentis/UI/History/HistoryView.swift | JSON export with ShareSheet |
| 2.3 | HistoryView - clearCoreData() | completed | UnaMentis/UI/History/HistoryView.swift | Delete all sessions |
| 2.4 | SessionSettingsView - audio controls | completed | UnaMentis/UI/Session/SessionView.swift | Sample rate, buffer size, voice processing |
| 2.5 | SessionSettingsView - voice selection | completed | UnaMentis/UI/Session/SessionView.swift | TTS provider and rate controls |
| 2.6 | SessionSettingsView - model selection | completed | UnaMentis/UI/Session/SessionView.swift | LLM provider/model/temperature/tokens |
| 2.7 | AnalyticsView - connect telemetry | completed | UnaMentis/UI/Analytics/AnalyticsView.swift | Already connected to TelemetryEngine |
| 2.8 | AnalyticsView - latency charts | completed | UnaMentis/UI/Analytics/AnalyticsView.swift | STT/LLM/TTS/E2E with targets |
| 2.9 | AnalyticsView - cost breakdown | completed | UnaMentis/UI/Analytics/AnalyticsView.swift | Provider breakdown with totals |
| 2.10 | SettingsView - API key entry | completed | UnaMentis/UI/Settings/SettingsView.swift | SecureField with edit sheet |
| 2.11 | SettingsView - preset selector | completed | UnaMentis/UI/Settings/SettingsView.swift | 4 presets implemented |
| 2.12 | Debug/Testing UI | completed | UnaMentis/UI/Settings/SettingsView.swift | DiagnosticsView, AudioTestView, ProviderTestView |

### 3. Audio Playback

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 3.1 | AudioEngine.playAudio() | completed | UnaMentis/Core/Audio/AudioEngine.swift | AVAudioEngine playback with AVAudioPlayerNode |
| 3.2 | TTS streaming support | completed | UnaMentis/Core/Audio/AudioEngine.swift | Handle chunked audio from TTS, format conversion |

### 4. Integration Tests

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 4.1 | Create VoiceSessionIntegrationTests | completed | UnaMentisTests/Integration/VoiceSessionIntegrationTests.swift | 16 integration tests added |
| 4.2 | Telemetry integration test | completed | UnaMentisTests/Integration/ | Latency, cost, event tracking |
| 4.3 | Audio pipeline test | completed | UnaMentisTests/Integration/ | VAD, playback, thermal |
| 4.4 | Curriculum context test | completed | UnaMentisTests/Integration/ | Context generation, navigation |
| 4.5 | Core Data persistence test | completed | UnaMentisTests/Integration/ | Curriculum, topic, document persistence |

### 5. Code Quality

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 5.1 | Verify Core Data models | completed | UnaMentis/UnaMentis.xcdatamodeld | Session, Topic, Curriculum, Document, TopicProgress, TranscriptEntry all present |
| 5.2 | Clean up Swift warnings | pending | - | Minor async/await warnings remain (non-critical) |
| 5.3 | Update documentation | completed | docs/*.md | Comprehensive documentation update |

### 6. GLM-ASR Implementation

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 6.1 | GLMASRSTTService (server) | completed | UnaMentis/Services/STT/GLMASRSTTService.swift | WebSocket-based server STT |
| 6.2 | GLMASRHealthMonitor | completed | UnaMentis/Services/STT/GLMASRHealthMonitor.swift | Server health monitoring |
| 6.3 | STTProviderRouter | completed | UnaMentis/Services/STT/STTProviderRouter.swift | Intelligent provider routing |
| 6.4 | GLMASROnDeviceSTTService | completed | UnaMentis/Services/STT/GLMASROnDeviceSTTService.swift | On-device CoreML + llama.cpp |
| 6.5 | Enable simulator testing | completed | GLMASROnDeviceSTTService.swift | Allow simulator when models present |

### 7. Infrastructure

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 7.1 | iOS Simulator MCP | completed | ~/.claude.json | ios-simulator-mcp installed |
| 7.2 | Documentation update | completed | docs/*.md | New GLM-ASR and AI testing guides |

### 8. Curriculum Format (UMLCF) Specification

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 8.1 | Create UMLCF JSON Schema | completed | curriculum/spec/umlcf-schema.json | Draft 2020-12, 1,847 lines |
| 8.2 | Write UMLCF Specification doc | completed | curriculum/spec/VLCF_SPECIFICATION.md | Human-readable spec |
| 8.3 | Write Standards Traceability | completed | curriculum/spec/STANDARDS_TRACEABILITY.md | 152 fields, 10 standards |
| 8.4 | Create minimal examples | completed | curriculum/examples/minimal/*.umlcf | 3 validation examples |
| 8.5 | Create realistic examples | completed | curriculum/examples/realistic/*.umlcf | 3 full curricula |
| 8.6 | Design import architecture | completed | curriculum/importers/IMPORTER_ARCHITECTURE.md | Plugin system spec |
| 8.7 | Write CK-12 importer spec | completed | curriculum/importers/CK12_IMPORTER_SPEC.md | K-12 (8th grade) |
| 8.8 | Write Fast.ai importer spec | completed | curriculum/importers/FASTAI_IMPORTER_SPEC.md | AI/ML collegiate |
| 8.9 | Write AI enrichment pipeline | completed | curriculum/importers/AI_ENRICHMENT_PIPELINE.md | Sparse → rich transformation |
| 8.10 | Create master curriculum README | completed | curriculum/README.md | Comprehensive overview |

### 9. Apple Intelligence Integration

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 9.1 | Create CurriculumEntity for Siri | completed | UnaMentis/Intents/CurriculumEntity.swift | AppEntity + EntityQuery |
| 9.2 | Create TopicEntity for Siri | completed | UnaMentis/Intents/TopicEntity.swift | AppEntity + EntityStringQuery |
| 9.3 | Create StartLessonIntent | completed | UnaMentis/Intents/StartLessonIntent.swift | "Start a lesson" voice command |
| 9.4 | Create ResumeLearningIntent | completed | UnaMentis/Intents/ResumeLearningIntent.swift | "Resume my lesson" voice command |
| 9.5 | Create ShowProgressIntent | completed | UnaMentis/Intents/ShowProgressIntent.swift | "Show my progress" voice command |
| 9.6 | Create AppShortcutsProvider | completed | UnaMentis/Intents/AppShortcutsProvider.swift | Register shortcuts with Siri |
| 9.7 | Add URL scheme for deep links | completed | UnaMentis/Info.plist | unamentis:// scheme |
| 9.8 | Add deep link handler | completed | UnaMentis/UnaMentisApp.swift | .onOpenURL handler |
| 9.9 | Write App Intents tests | completed | UnaMentisTests/Unit/Intents/AppIntentsTests.swift | 23 tests passing |
| 9.10 | Create Apple Intelligence docs | completed | docs/APPLE_INTELLIGENCE.md | Integration guide |

### 10. Graceful Degradation & Fallback Architecture

| ID | Task | Status | File(s) | Notes |
|----|------|--------|---------|-------|
| 10.1 | Add STT fallback to Apple Speech | completed | UnaMentis/UI/Session/SessionView.swift | Deepgram/AssemblyAI → Apple Speech |
| 10.2 | Add TTS fallback to Apple TTS | completed | UnaMentis/UI/Session/SessionView.swift | ElevenLabs/Deepgram → Apple TTS |
| 10.3 | Add LLM multi-tier fallback | completed | UnaMentis/UI/Session/SessionView.swift | Cloud → Self-Hosted → On-Device |
| 10.4 | Enable OnDeviceLLMService integration | completed | UnaMentis/UI/Session/SessionView.swift | localMLX uses real on-device LLM |
| 10.5 | Document fallback architecture | completed | docs/FALLBACK_ARCHITECTURE.md | Complete degradation guide |

---

## PART 2: Collaborative Tasks (User Participation Required)

### 11. API Configuration

| ID | Task | Status | Depends On | Notes |
|----|------|--------|------------|-------|
| 11.1 | Get Deepgram API key | pending | User | STT/TTS provider |
| 11.2 | Get ElevenLabs API key | pending | User | TTS provider |
| 11.3 | Get Anthropic API key | pending | User | LLM provider (Claude) |
| 11.4 | Get OpenAI API key | pending | User | LLM/Embeddings provider |
| 11.5 | Get AssemblyAI API key | pending | User | STT provider |
| 11.6 | Configure keys in app | pending | 11.1-11.5 | Use APIKeyManager |
| 11.7 | Test provider connectivity | pending | 11.6 | Verify each API works |

### 12. On-Device Model Setup

| ID | Task | Status | Depends On | Notes |
|----|------|--------|------------|-------|
| 12.1 | Download GLM-ASR models | pending | User | ~2.4GB from Hugging Face |
| 12.2 | Place in models directory | pending | 12.1 | models/glm-asr-nano/ |
| 12.3 | Add to Xcode target | pending | 12.2 | Copy Bundle Resources |
| 12.4 | Test on-device inference | pending | 12.3 | Verify CoreML + llama.cpp |

### 13. Device Testing

| ID | Task | Status | Depends On | Notes |
|----|------|--------|------------|-------|
| 13.1 | Test on physical iPhone | pending | Part 1, 11.x | iPhone 15 Pro+ / 16/17 Pro Max |
| 13.2 | Verify microphone permissions | pending | 13.1 | Check Info.plist config |
| 13.3 | Test audio session config | pending | 13.1 | AVAudioSession voice chat mode |
| 13.4 | Test VAD on Neural Engine | pending | 13.1 | Silero model performance |
| 13.5 | Profile latency | pending | 13.1-13.4 | Target: <500ms E2E |
| 13.6 | 90-minute session test | pending | 13.5 | Stability & memory check |

### 14. Content Setup

| ID | Task | Status | Depends On | Notes |
|----|------|--------|------------|-------|
| 14.1 | Create test curriculum | pending | Part 1 | Sample topics for testing |
| 14.2 | Test PDF import | pending | 14.1 | DocumentProcessor verification |
| 14.3 | Test OpenStax API | pending | 11.x | Online resource integration |
| 14.4 | Test Wikipedia API | pending | - | Online resource integration |

### 15. UMLCF Implementation (Future)

| ID | Task | Status | Depends On | Notes |
|----|------|--------|------------|-------|
| 15.1 | Implement Python importer package | pending | 8.x spec | Entry points, CLI, API |
| 15.2 | Build CK-12 importer | pending | 15.1 | K-12 EPUB import |
| 15.3 | Build Fast.ai importer | pending | 15.1 | Jupyter notebook import |
| 15.4 | Build AI enrichment pipeline | pending | 15.1 | Sparse → rich transformation |
| 15.5 | Create web-based editor | pending | 15.1-15.4 | Human-in-the-loop review |
| 15.6 | Integrate UMLCF with iOS app | pending | 15.1 | Replace current curriculum format |

### 16. Final Polish

| ID | Task | Status | Depends On | Notes |
|----|------|--------|------------|-------|
| 16.1 | UI/UX refinements | pending | 13.x, 14.x | Based on testing feedback |
| 16.2 | Performance optimization | pending | 13.5 | Based on profiling results |
| 16.3 | Bug fixes | pending | 13.x, 14.x | Issues from testing |

---

## Completed Tasks

| ID | Task | Completed By | Date | Notes |
|----|------|--------------|------|-------|
| - | Open source readiness | Claude Code | 2025-12-11 | LICENSE, CODE_OF_CONDUCT, SECURITY, CHANGELOG, templates |
| - | Curriculum System verification | Claude Code | 2025-12-11 | CurriculumEngine, DocumentProcessor, ProgressTracker tests pass |
| 1.1 | Fix SessionManagerTests MainActor errors | Claude Code | 2025-12-12 | Added @MainActor annotations |
| 1.2 | Restore deleted docs | Claude Code | 2025-12-12 | implementation_plan.md, task.md, parallel_agent_curriculum_prompt.md |
| 1.3 | Run full test suite | Claude Code | 2025-12-12 | All 103+ tests pass |
| 2.1-2.12 | Complete UI data binding | Claude Code | 2025-12-12 | All UI views connected to data sources |
| 3.1-3.2 | Implement AudioEngine playback | Claude Code | 2025-12-12 | TTS streaming playback with AVAudioPlayerNode |
| 4.1-4.5 | Create integration tests | Claude Code | 2025-12-12 | 16 new integration tests added |
| 1.4 | Fix Core Data SPM compatibility | Claude Code | 2025-12-16 | Manual NSManagedObject subclasses |
| 1.5 | Fix macOS API compatibility | Claude Code | 2025-12-16 | #if os(iOS) guards |
| 6.1-6.5 | GLM-ASR implementation | Claude Code | 2025-12-16 | Server + on-device STT |
| 7.1-7.2 | Infrastructure & docs | Claude Code | 2025-12-16 | MCP setup, documentation |
| 8.1-8.10 | UMLCF specification complete | Claude Code | 2025-12-17 | Schema, spec, examples, importers, AI pipeline |
| 9.1-9.10 | Apple Intelligence integration | Claude Code | 2025-12-24 | Siri voice commands, App Intents, deep links, 23 tests |
| 10.1-10.5 | Graceful degradation architecture | Claude Code | 2025-12-24 | STT/TTS/LLM fallbacks to built-in services |

---

## Currently Active

| Task | Agent/Tool | Started | Notes |
|------|------------|---------|-------|
| Part 1 COMPLETE | Claude Code | 2025-12-16 | All autonomous tasks finished |
| Ready for Part 2 | User | - | API keys, model download, device testing |

---

## Notes

### Task Dependencies
- Part 1 tasks (1.x - 7.x) can be done autonomously by AI agent - **COMPLETE**
- Part 2 tasks (8.x - 12.x) require user participation
- Dependencies shown in "Depends On" column

### Performance Targets (from TDD)
| Component | Target (Median) | Acceptable (P99) |
|-----------|----------------|------------------|
| STT | <300ms | <1000ms |
| LLM First Token | <200ms | <500ms |
| TTS TTFB | <200ms | <400ms |
| E2E Turn | <500ms | <1000ms |

### Success Criteria
- [x] All unit tests pass (126+ tests, including 23 App Intents tests)
- [x] All integration tests pass (16 new tests)
- [x] `swift build` succeeds with zero errors
- [x] **Graceful degradation** (STT/TTS/LLM fallback to Apple services)
- [x] Core Data works with SPM builds
- [x] Platform compatibility (iOS + macOS)
- [x] GLM-ASR server implementation
- [x] GLM-ASR on-device implementation
- [x] iOS Simulator MCP installed
- [x] Documentation updated
- [x] **UMLCF specification complete** (JSON Schema, human-readable spec, standards traceability)
- [x] **Import system designed** (CK-12, Fast.ai, AI enrichment pipeline)
- [x] **Apple Intelligence integration** (Siri voice commands, App Intents, deep links)
- [ ] Full voice conversation works on device (requires API keys)
- [ ] Sub-600ms E2E latency achieved (requires device testing)
- [ ] 90-minute session completes without crash (requires device testing)

### Critical Files Reference
- **Core**: SessionManager.swift, AudioEngine.swift, CurriculumEngine.swift, TelemetryEngine.swift
- **STT**: GLMASRSTTService.swift, GLMASROnDeviceSTTService.swift, STTProviderRouter.swift
- **UI**: SessionView.swift, HistoryView.swift, AnalyticsView.swift, SettingsView.swift
- **Intents**: StartLessonIntent.swift, ResumeLearningIntent.swift, ShowProgressIntent.swift, CurriculumEntity.swift, TopicEntity.swift, AppShortcutsProvider.swift
- **Docs**: UnaMentis_TDD.md, GLM_ASR_ON_DEVICE_GUIDE.md, AI_SIMULATOR_TESTING.md, APPLE_INTELLIGENCE.md, FALLBACK_ARCHITECTURE.md

### New Documentation
| Document | Purpose |
|----------|---------|
| GLM_ASR_ON_DEVICE_GUIDE.md | Complete on-device STT setup guide |
| AI_SIMULATOR_TESTING.md | AI-driven testing workflow |
| APPLE_INTELLIGENCE.md | Apple Intelligence & Siri integration guide |
| FALLBACK_ARCHITECTURE.md | Graceful degradation and service fallbacks |
| (Updated) QUICKSTART.md | Current project state |
| (Updated) SETUP.md | Model setup instructions |
| (Updated) PROJECT_OVERVIEW.md | Added Intents architecture, Graceful Degradation |

### Curriculum Format (UMLCF) Documentation
| Document | Purpose |
|----------|---------|
| [curriculum/README.md](../curriculum/README.md) | **Comprehensive UMLCF overview** |
| [curriculum/spec/VLCF_SPECIFICATION.md](../curriculum/spec/VLCF_SPECIFICATION.md) | Human-readable format spec |
| [curriculum/spec/umlcf-schema.json](../curriculum/spec/umlcf-schema.json) | JSON Schema (Draft 2020-12) |
| [curriculum/spec/STANDARDS_TRACEABILITY.md](../curriculum/spec/STANDARDS_TRACEABILITY.md) | Field-by-field standards mapping |
| [curriculum/importers/IMPORTER_ARCHITECTURE.md](../curriculum/importers/IMPORTER_ARCHITECTURE.md) | Import system design |
| [curriculum/importers/CK12_IMPORTER_SPEC.md](../curriculum/importers/CK12_IMPORTER_SPEC.md) | K-12 curriculum importer |
| [curriculum/importers/FASTAI_IMPORTER_SPEC.md](../curriculum/importers/FASTAI_IMPORTER_SPEC.md) | AI/ML notebook importer |
| [curriculum/importers/AI_ENRICHMENT_PIPELINE.md](../curriculum/importers/AI_ENRICHMENT_PIPELINE.md) | AI content enrichment spec |

---

## UI Simulator Testing Report (December 2025)

### Test Environment
- **Simulator**: iPhone 17 Pro (iOS 26.1)
- **Build**: Debug (xcodebuild)
- **Bundle ID**: com.unamentis.app
- **Test Method**: AppleScript automation + xcrun simctl screenshots

### Tests Performed

| Test | Result | Notes |
|------|--------|-------|
| App Launch | PASS | App launches successfully, PID assigned |
| Tab Navigation - Session | PASS | Session view displays correctly |
| Tab Navigation - Curriculum | PASS | Shows "No Curriculum Loaded" empty state |
| Tab Navigation - History | PASS | Shows "No Sessions Yet" empty state |
| Tab Navigation - Analytics | PASS | Displays metrics cards (zeroed) |
| Tab Navigation - Settings | PASS | Full settings UI rendered |

### UI Components Verified

#### Session View
- Main conversation interface present
- Tab bar navigation functional

#### Curriculum View
- Title: "Curriculum" displays
- Empty state with book icon
- "Import a curriculum to get started" message
- Proper styling and layout

#### History View
- Title: "History" displays
- Clock icon with question mark
- "No Sessions Yet" empty state
- Informative message about first session

#### Analytics View (AnalyticsView.swift)
- Quick Stats cards (Sessions, Duration, Cost)
- Latency Metrics card (STT, LLM TTFT, TTS TTFB, E2E)
- Cost Breakdown card (STT, TTS, LLM costs)
- Session Quality card (Turns, Interruptions, Throttle Events)
- Export toolbar button

#### Settings View (SettingsView.swift)
- **API Keys Section**: 5 provider key rows (OpenAI, Anthropic, Deepgram, ElevenLabs, AssemblyAI)
- **Audio Section**: Sample rate picker, Voice/Echo/Noise toggles
- **Voice Detection Section**: VAD threshold, Interruption threshold, Enable toggle
- **Language Model Section**: Provider picker, Model picker, Temperature slider, Max tokens
- **Voice (TTS) Section**: Provider picker, Speaking rate slider
- **Presets Section**: Balanced, Low Latency, High Quality, Cost Optimized buttons
- **Debug & Testing Section**: Diagnostics, Audio Test, Provider Test navigation links
- **About Section**: Version, Documentation link, Privacy Policy link

### Screenshots Captured
| File | Description |
|------|-------------|
| 01-initial-launch.png | Initial app launch state |
| 02-session-tab.png | Session tab view |
| 03-curriculum-tab.png | Curriculum empty state |
| 04-history-tab.png | History empty state |
| 05-analytics-tab.png | Analytics dashboard |
| 06-settings-tab.png | Settings view |
| 07-session-tab.png | Session tab revisited |
| 08-settings-detail.png | Settings detail view |
| 09-settings-scrolled.png | Settings scrolled |
| 10-analytics-view.png | Analytics final view |

**Screenshots location**: `/tmp/voicelearn-screenshots/`

### AI Testing Capability Assessment

| Capability | Status | Notes |
|------------|--------|-------|
| Simulator boot/shutdown | WORKING | xcrun simctl boot/shutdown |
| App install | WORKING | xcrun simctl install |
| App launch | WORKING | xcrun simctl launch |
| Screenshot capture | WORKING | xcrun simctl io booted screenshot |
| UI click interaction | WORKING | AppleScript System Events |
| Keyboard input | PARTIAL | Arrow keys work, needs cliclick for swipe |
| Scroll gestures | NEEDS WORK | Requires cliclick installation |
| Deep navigation | WORKING | Tab bar navigation confirmed |

### Recommendations
1. Install `cliclick` for better gesture support: `brew install cliclick`
2. Add accessibility identifiers to all interactive elements for reliable automation
3. Consider XCUITest for more robust UI testing automation
4. Current AppleScript approach works well for basic navigation testing
