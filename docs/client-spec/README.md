# UnaMentis Client Feature Specification

**Version:** 1.1.0
**Status:** Active
**Last Updated:** 2026-01-25
**Reference Platform:** iOS (Swift/SwiftUI)

---

## Purpose

This specification defines the canonical feature set, UI patterns, and user experience for UnaMentis clients. The iOS app serves as the reference implementation. Other clients (Android, Web) should achieve feature parity as documented here.

**Target Audience:** AI agents and developers building or maintaining UnaMentis clients in any platform.

---

## Document Index

| Document | Purpose | Key Content |
|----------|---------|-------------|
| [01-NAVIGATION_ARCHITECTURE.md](01-NAVIGATION_ARCHITECTURE.md) | App structure | Tab bar, navigation patterns, deep links, state management |
| [02-SESSION_TAB.md](02-SESSION_TAB.md) | Voice conversations | Recording UI, transcript, controls, visual assets, adaptive layouts |
| [03-CURRICULUM_TAB.md](03-CURRICULUM_TAB.md) | Content browsing | List/detail views, import flow, progress tracking, topic selection |
| [04-TODO_TAB.md](04-TODO_TAB.md) | Learning goals | Filters, CRUD operations, AI suggestions, empty states |
| [05-HISTORY_TAB.md](05-HISTORY_TAB.md) | Session replay | History list, detail view, export, clear functionality |
| [06-ANALYTICS_TAB.md](06-ANALYTICS_TAB.md) | Metrics dashboard | Stats cards, latency display, cost breakdown, export |
| [07-SETTINGS.md](07-SETTINGS.md) | Configuration | Providers, voice settings, self-hosted, debug tools |
| [08-SIRI_SHORTCUTS.md](08-SIRI_SHORTCUTS.md) | Voice integration | App intents, voice commands, deep link schemes |
| [09-UI_COMPONENTS.md](09-UI_COMPONENTS.md) | Reusable elements | Common components, design tokens, interaction patterns |
| [10-ACCESSIBILITY.md](10-ACCESSIBILITY.md) | A11y standards | VoiceOver, touch targets, dynamic type, reduce motion |
| [11-KNOWLEDGE_BOWL.md](11-KNOWLEDGE_BOWL.md) | Knowledge Bowl module | Practice modes, team features, answer validation, analytics |

---

## Quick Reference

### Navigation Structure

The app uses a 6-tab navigation:

```
┌─────────────────────────────────────────────────────────────┐
│                        UnaMentis                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│                    [Main Content Area]                       │
│                                                              │
├──────────┬──────────┬──────────┬──────────┬──────────┬──────┤
│ Session  │Curriculum│  To-Do   │ History  │Analytics │Settings│
│    🎙    │    📚    │    ✓     │    🕐    │    📊    │   ⚙   │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────┘
```

### Feature Matrix

| Feature | Session | Curriculum | To-Do | History | Analytics | Settings |
|---------|:-------:|:----------:|:-----:|:-------:|:---------:|:--------:|
| Voice Input | ✓ | | | | | |
| Voice Output | ✓ | | | | | |
| Visual Assets | ✓ | ✓ | | | | |
| Progress Tracking | ✓ | ✓ | ✓ | | | |
| Data Export | | | | ✓ | ✓ | |
| Provider Config | | | | | | ✓ |
| Offline Support | ✓ | ✓ | ✓ | ✓ | | ✓ |

### Provider Support

| Provider Type | Cloud Options | Self-Hosted | On-Device |
|---------------|---------------|-------------|-----------|
| STT (Speech-to-Text) | AssemblyAI, Deepgram, Groq | Whisper.cpp, faster-whisper | Apple Speech, GLM-ASR |
| TTS (Text-to-Speech) | ElevenLabs, Deepgram Aura | Chatterbox, VibeVoice, Piper, Kyutai 1.6B | **Kyutai Pocket**, Apple TTS |
| LLM (Language Model) | OpenAI, Anthropic | Ollama, llama.cpp, vLLM | Ministral-3B, TinyLlama |
| VAD (Voice Activity) | | | Silero VAD |
| Embeddings | OpenAI | | all-MiniLM-L6-v2 (KB) |

### Specialized Modules

Beyond general tutoring, the client supports specialized learning modules:

| Module | Purpose | Status |
|--------|---------|--------|
| **Knowledge Bowl** | Academic competition prep (12 subject domains) | Implemented |
| **SAT Preparation** | Digital SAT adaptive learning | Specification complete |

**Knowledge Bowl Features:**
- Written and oral round practice modes with voice-first interaction
- Advanced training modes: Match Simulation, Conference Training, Domain Drill, Rebound Training
- 3-tier answer validation (phonetic, n-gram, token, linguistic, semantic, LLM)
- Team management with domain assignments and coverage analysis
- Session persistence with pause tracking and per-question response times
- Regional competition rules (Colorado, Minnesota, Washington strictness levels)
- On-device STT/TTS (Kyutai Pocket) for offline practice capability
- Analytics dashboard with domain mastery tracking and trend charts

See [11-KNOWLEDGE_BOWL.md](11-KNOWLEDGE_BOWL.md) for complete client specification.
See [../modules/](../modules/) for technical module specifications.

---

## Platform Considerations

### Adaptive Layouts

The iOS app supports two primary form factors:

- **iPhone**: Single-column layouts, bottom sheet modals, compact controls
- **iPad**: Multi-column layouts, side panels, larger touch targets

Each document notes where layouts differ between devices.

### State Management

- **AppState**: Global singleton managing app-wide state
- **View-specific ViewModels**: Isolated state per feature area
- **Core Data**: Persistent storage for curricula, sessions, todos
- **UserDefaults**: Settings and preferences

---

## Related Documentation

- **Server API Specification**: [../api-spec/README.md](../api-spec/README.md)
- **iOS Style Guide**: [../ios/IOS_STYLE_GUIDE.md](../ios/IOS_STYLE_GUIDE.md)
- **Project Overview**: [../architecture/PROJECT_OVERVIEW.md](../architecture/PROJECT_OVERVIEW.md)

---

## Screenshots Directory

Screenshots are organized by feature area:

```
screenshots/
├── navigation/       # Tab bar, app-wide navigation
├── session/          # Voice session UI states
├── curriculum/       # Content browsing views
├── todo/             # Learning goals interface
├── history/          # Session history views
├── analytics/        # Metrics dashboard
├── settings/         # Configuration screens
└── knowledge-bowl/   # Knowledge Bowl module screens
```

Screenshot naming convention: `{screen}-{state}-{device}.png`

Examples:
- `session-idle-iphone.png`
- `session-recording-ipad.png`
- `curriculum-list-iphone.png`
