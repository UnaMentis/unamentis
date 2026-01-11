# UnaMentis iOS App

Swift 6.0/SwiftUI iOS application for voice-first AI tutoring.

## Build Commands

```bash
# Build for simulator (iPhone 16 Pro for CI parity)
xcodebuild -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Testing - use the unified test runner for CI parity
./scripts/test-quick.sh          # Unit tests only (fast)
./scripts/test-all.sh            # All tests + 80% coverage enforcement
./scripts/test-ci.sh             # Direct runner with env var config

# Run specific test class
xcodebuild test -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:UnaMentisTests/ProgressTrackerTests
```

## MANDATORY: Validate Before Complete

**Use the `/validate` skill before marking any work complete.**

```
/validate           # Lint + quick tests
/validate --full    # Lint + full test suite
```

When adding new files:
1. Verify the file is added to the Xcode project (not just the filesystem)
2. Run `/validate` to confirm compilation and tests pass

See `.claude/skills/validate/SKILL.md` for details.

## Swift 6.0 Strict Concurrency

This codebase uses Swift 6.0 strict concurrency. All code must comply:

### Actors

All services must be actors:

```swift
actor AudioEngine {
    func startRecording() async throws { ... }
}
```

### @MainActor

ViewModels and UI-related code use @MainActor:

```swift
@MainActor
class SessionViewModel: ObservableObject {
    @Published var isRecording = false
}
```

### Sendable

Types crossing actor boundaries must be Sendable:

```swift
struct LLMMessage: Sendable {
    let role: String
    let content: String
}
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
│   ├── STT/        # Speech-to-text (AssemblyAI, Deepgram, on-device)
│   ├── TTS/        # Text-to-speech (ElevenLabs, Apple, self-hosted)
│   ├── LLM/        # Language models (OpenAI, Anthropic, local)
│   └── Protocols/  # Service protocol definitions
├── Intents/        # Siri & App Intents (iOS 16+)
├── UI/             # SwiftUI views
└── Persistence/    # Core Data stack
```

## Mandatory Style Requirements

**Read `docs/ios/IOS_STYLE_GUIDE.md` before implementation.** Key requirements:

- Accessibility labels on all interactive elements
- Localizable strings for all user-facing text (use LocalizedStringKey)
- iPad adaptive layouts using size class detection
- Use NavigationStack/NavigationSplitView (not NavigationView)
- Minimum 44x44pt touch targets
- Support Dynamic Type scaling
- Respect Reduce Motion preference

## Service Patterns

All external service integrations follow the protocol pattern:

```swift
protocol STTService: Actor {
    func transcribe(audio: Data) async throws -> TranscriptionResult
}

actor DeepgramSTTService: STTService {
    func transcribe(audio: Data) async throws -> TranscriptionResult { ... }
}
```

## Core Data

Use the persistence controller for all Core Data operations:

```swift
// In production
let controller = PersistenceController.shared

// In tests
let controller = PersistenceController(inMemory: true)
```

## Testing

Tests are in `UnaMentisTests/`. See `AGENTS.md` in the project root for the "Real Over Mock" testing philosophy.
