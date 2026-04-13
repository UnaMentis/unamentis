# Siri Shortcuts & Voice Commands

**Version:** 1.0.0
**Last Updated:** 2026-01-16
**Platform:** iOS (Swift/SwiftUI)

---

## Overview

UnaMentis integrates with Siri and the Shortcuts app to enable hands-free control and automation. Users can start sessions, access content, and control the app using voice commands.

---

## App Intents

### Available Intents

| Intent | Description | Parameters |
|--------|-------------|------------|
| StartSession | Begin a learning session | curriculum?, topic? |
| StopSession | End current session | - |
| PauseSession | Pause active session | - |
| ResumeSession | Resume paused session | - |
| OpenCurriculum | Open curriculum browser | curriculum? |
| OpenTopic | Navigate to specific topic | curriculum, topic |
| ShowAnalytics | Display analytics dashboard | - |
| ShowHistory | Open session history | - |

### Intent Definitions

```swift
// StartSession Intent
struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Learning Session"
    static var description = IntentDescription("Begin a voice learning session")

    @Parameter(title: "Curriculum")
    var curriculum: CurriculumEntity?

    @Parameter(title: "Topic")
    var topic: TopicEntity?

    func perform() async throws -> some IntentResult {
        // Start session logic
    }
}
```

---

## Siri Voice Commands

### Built-in Phrases

| Phrase | Action |
|--------|--------|
| "Hey Siri, start learning with UnaMentis" | Opens app, starts session |
| "Hey Siri, stop my UnaMentis session" | Ends active session |
| "Hey Siri, pause UnaMentis" | Pauses session |
| "Hey Siri, resume learning" | Resumes paused session |
| "Hey Siri, open UnaMentis" | Opens app |

### Custom Phrases

Users can add custom phrases:
1. Open Settings → Siri & Search → UnaMentis
2. Tap "Add Shortcut to Siri"
3. Record custom phrase
4. Associate with intent

### Suggested Phrases

App suggests phrases based on usage:
- "Continue learning Physics"
- "Start Calculus session"
- "Review Newton's Laws"

---

## Shortcuts App Integration

### Pre-built Shortcuts

Available in Shortcuts Gallery:

| Shortcut | Description |
|----------|-------------|
| Quick Study | Start session with last topic |
| Daily Review | Review flagged topics |
| Export Progress | Export learning analytics |

### Shortcut Actions

Actions available in Shortcuts app:

```
UnaMentis
├── Start Session
│   ├── With specific curriculum
│   ├── With specific topic
│   └── Continue last session
├── Control Session
│   ├── Pause
│   ├── Resume
│   └── Stop
├── Get Information
│   ├── Current session status
│   ├── Learning progress
│   └── Session history
└── Open Views
    ├── Curriculum browser
    ├── Analytics
    └── Settings
```

### Automation Triggers

Shortcuts can trigger on:
- Time of day
- Location arrival/departure
- App open/close
- Focus mode change
- NFC tag tap

### Example Automations

**Morning Study Routine:**
```
When: 7:00 AM on weekdays
Do:
  1. Open UnaMentis
  2. Start session with "Daily Review" curriculum
  3. Set Do Not Disturb
```

**Commute Learning:**
```
When: Connect to Car Bluetooth
Do:
  1. Start UnaMentis session
  2. Set audio output to Car
```

---

## Deep Links

### URL Scheme

```
unamentis://
```

### Supported Deep Links

| URL | Action |
|-----|--------|
| `unamentis://session` | Open Session tab |
| `unamentis://session/start` | Start new session |
| `unamentis://session/start?curriculum=ID` | Start with curriculum |
| `unamentis://session/start?topic=ID` | Start with topic |
| `unamentis://curriculum` | Open Curriculum tab |
| `unamentis://curriculum/ID` | Open specific curriculum |
| `unamentis://todo` | Open To-Do tab |
| `unamentis://history` | Open History tab |
| `unamentis://analytics` | Open Analytics |
| `unamentis://settings` | Open Settings |

### Universal Links

Web URLs that open in app:
```
https://unamentis.com/curriculum/ID
https://unamentis.com/session/ID
```

---

## Voice Control (iOS)

### Supported Commands

When Voice Control is enabled:

| Command | Action |
|---------|--------|
| "Tap microphone" | Taps mic button |
| "Tap Session" | Switches to Session tab |
| "Tap Curriculum" | Switches to Curriculum tab |
| "Scroll down" | Scrolls content |
| "Go back" | Navigates back |

### Custom Voice Control Commands

Users can add custom commands via Accessibility settings.

---

## Implementation Details

### Entity Definitions

```swift
struct CurriculumEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Curriculum")

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct TopicEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Topic")

    var id: UUID
    var title: String
    var curriculum: CurriculumEntity

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}
```

### Entity Query

```swift
struct CurriculumEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CurriculumEntity] {
        // Fetch from Core Data
    }

    func suggestedEntities() async throws -> [CurriculumEntity] {
        // Return recent/popular curricula
    }
}
```

### Intent Donations

```swift
// Donate intent when user manually starts session
func donateStartSessionIntent(curriculum: Curriculum, topic: Topic) {
    let intent = StartSessionIntent()
    intent.curriculum = CurriculumEntity(from: curriculum)
    intent.topic = TopicEntity(from: topic)

    let interaction = INInteraction(intent: intent, response: nil)
    interaction.donate { error in
        // Handle error
    }
}
```

---

## Privacy & Permissions

### Required Permissions

| Permission | Purpose |
|------------|---------|
| Siri | Voice command processing |
| Speech Recognition | On-device transcription |
| Microphone | Voice input |

### Data Shared with Siri

- Curriculum names (for suggestions)
- Topic names (for suggestions)
- Recent activity (for predictions)

### User Control

Users can:
- Disable Siri integration entirely
- Clear Siri learning data
- Manage shortcut permissions

---

## Accessibility

### VoiceOver + Siri

- Intents have spoken descriptions
- Results announced via VoiceOver
- Compatible with screen reader workflows

### Switch Control

- All intents accessible via switches
- Shortcuts work with switch control
- No timing-dependent actions

---

## Related Documentation

- [01-NAVIGATION_ARCHITECTURE.md](01-NAVIGATION_ARCHITECTURE.md) - Deep link handling
- [02-SESSION_TAB.md](02-SESSION_TAB.md) - Session control
- [07-SETTINGS.md](07-SETTINGS.md) - Siri settings
