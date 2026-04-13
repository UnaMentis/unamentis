# Session Tab

**Version:** 1.0.0
**Last Updated:** 2026-01-16
**Platform:** iOS (Swift/SwiftUI)

---

## Overview

The Session tab is the primary interface for voice-based learning conversations. It manages the full lifecycle of a tutoring session including recording, AI response playback, transcript display, and visual asset presentation.

![Session Idle State](screenshots/session/session-idle-iphone.png)

---

## Session States

### State Machine

```
┌─────────┐     Start      ┌───────────┐
│  Idle   │───────────────▶│ Recording │
└─────────┘                └───────────┘
     ▲                           │
     │                           │ Voice detected
     │                           ▼
     │                    ┌───────────┐
     │    End session     │Processing │
     │◀───────────────────│           │
     │                    └───────────┘
     │                           │
     │                           │ Response ready
     │                           ▼
     │                    ┌───────────┐
     │                    │  Playing  │
     │                    └───────────┘
     │                           │
     │         Done              │ User interrupts
     │◀──────────────────────────┤
     │                           ▼
     │                    ┌───────────┐
     └────────────────────│ Recording │
                          └───────────┘
```

### State Definitions

| State | Description | User Actions Available |
|-------|-------------|----------------------|
| **Idle** | No active session, ready to start | Tap mic to start |
| **Recording** | Capturing user speech | Tap to stop, wait for VAD |
| **Processing** | STT → LLM → TTS pipeline running | Cancel, view progress |
| **Playing** | AI response audio playing | Pause, interrupt, skip |
| **Paused** | Session paused mid-conversation | Resume, end session |

### Visual Indicators

| State | Mic Button | Status Text | Animation |
|-------|------------|-------------|-----------|
| Idle | Blue, static | "Idle" | None |
| Recording | Red, pulsing | "Recording..." | Waveform |
| Processing | Gray, spinner | "Thinking..." | Progress dots |
| Playing | Blue, speaker icon | "Speaking..." | Audio levels |
| Paused | Yellow, pause icon | "Paused" | None |

---

## UI Layout

### Main View Structure

```
┌──────────────────────────────────────┐
│ [Logo]    Voice Session    [?] [⚙️]  │  ← Navigation Bar
├──────────────────────────────────────┤
│            ● Idle                    │  ← Status Indicator
├──────────────────────────────────────┤
│                                      │
│                                      │
│         [Visual Asset Area]          │  ← Diagrams, images, maps
│                                      │
│                                      │
├──────────────────────────────────────┤
│                                      │
│         [Transcript Area]            │  ← Scrollable conversation
│                                      │
├──────────────────────────────────────┤
│              [🎤]                    │  ← Microphone Button
├──────────────────────────────────────┤
│  Session │ Curriculum │ ... │ More  │  ← Tab Bar
└──────────────────────────────────────┘
```

### Component Details

#### Navigation Bar
- **Left**: UnaMentis logo (tappable, shows app info)
- **Center**: "Voice Session" title
- **Right**: Help button (?), Session settings (⚙️)

#### Status Indicator
- Pill-shaped badge showing current state
- Color-coded: gray (idle), red (recording), blue (playing)
- Includes brief description text

#### Visual Asset Area
- Displays diagrams, formulas, maps, images
- Pinch-to-zoom supported
- Tap to expand full-screen
- Swipeable if multiple assets
- Auto-hides when no assets to show

#### Transcript Area
- Scrollable conversation history
- User messages aligned right (blue bubbles)
- AI messages aligned left (gray bubbles)
- Timestamps on long-press
- Auto-scrolls to latest message

#### Microphone Button
- Large, centered tap target (80pt diameter)
- Press and hold for push-to-talk mode
- Single tap for toggle mode
- Visual feedback on press

---

## Recording Modes

### Voice Activity Detection (VAD)
Default mode using Silero VAD for automatic speech detection:
- Automatically starts when speech detected
- Ends after configurable silence duration (default: 1.5s)
- Shows real-time waveform visualization

### Push-to-Talk
Optional mode for noisy environments:
- Hold microphone button while speaking
- Release to send
- No VAD processing required

### Toggle Mode
Tap-to-start, tap-to-stop:
- First tap begins recording
- Second tap ends recording
- Useful for longer statements

---

## Transcript Display

### Message Types

| Type | Appearance | Content |
|------|------------|---------|
| User | Right-aligned, blue bubble | Transcribed speech |
| AI | Left-aligned, gray bubble | AI response text |
| System | Centered, italic | Status messages |
| Visual | Inline card | Asset thumbnail + caption |

### Transcript Features

- **Auto-scroll**: Follows conversation in real-time
- **Manual scroll**: Disable auto-scroll when user scrolls up
- **Copy text**: Long-press to copy message
- **Timestamps**: Long-press reveals time
- **Read indicator**: Checkmarks for sent/received

### Rich Content

AI responses may include:
- **Markdown**: Bold, italic, lists, code blocks
- **LaTeX**: Rendered math formulas
- **Diagrams**: Inline Mermaid/diagram references
- **Links**: Tappable references (opened in-app)

---

## Visual Assets

### Asset Types

| Type | Rendering | Source |
|------|-----------|--------|
| Diagram | SVG/PNG | Server-generated Mermaid |
| Formula | LaTeX render | MathJax/KaTeX |
| Map | Interactive | MapKit with annotations |
| Image | JPEG/PNG | Curriculum assets |
| Code | Syntax highlighted | AI-generated examples |

### Asset Behavior

- **Auto-display**: Assets appear when referenced in conversation
- **Queue**: Multiple assets stack, swipeable
- **Persistence**: Assets remain until dismissed or replaced
- **Fullscreen**: Tap to expand with zoom/pan
- **Share**: Long-press for share sheet

### Asset Positioning

```
┌────────────────────────────────┐
│  ┌──────────────────────────┐  │
│  │                          │  │
│  │     [Visual Asset]       │  │  ← Flexible height
│  │                          │  │
│  └──────────────────────────┘  │
│  ○ ○ ● ○                       │  ← Page indicators
└────────────────────────────────┘
```

---

## Controls

### Primary Controls

| Control | Location | Action |
|---------|----------|--------|
| Microphone | Bottom center | Start/stop recording |
| Help | Nav bar right | Show help overlay |
| Settings | Nav bar right | Session-specific settings |

### Contextual Controls

Appear based on session state:

| Control | When Visible | Action |
|---------|--------------|--------|
| Pause | During playback | Pause AI response |
| Skip | During playback | Skip to end of response |
| Cancel | During processing | Cancel current request |
| End Session | Any active state | End and save session |

### Gesture Controls

| Gesture | Action |
|---------|--------|
| Tap mic | Toggle recording |
| Long-press mic | Push-to-talk |
| Swipe up on transcript | Scroll history |
| Pinch on asset | Zoom |
| Double-tap asset | Fullscreen toggle |
| Swipe left/right on assets | Navigate assets |

---

## Session Settings

Accessible via gear icon in navigation bar:

### Audio Settings
- **Input device**: Microphone selection
- **Output device**: Speaker/headphone selection
- **Input gain**: Microphone sensitivity
- **Playback speed**: 0.75x - 2.0x

### Conversation Settings
- **Silence threshold**: VAD sensitivity (1-3 seconds)
- **Auto-continue**: Auto-record after AI finishes
- **Push-to-talk**: Enable/disable

### Display Settings
- **Show timestamps**: Always/on-demand/never
- **Asset auto-expand**: Enable/disable
- **Transcript font size**: Small/Medium/Large

---

## Session Lifecycle

### Starting a Session

1. User taps microphone button
2. App checks for active curriculum/topic
3. If no topic selected, prompt to select
4. Initialize audio session
5. Connect to server WebSocket
6. Begin recording

### During Session

1. User speaks, audio captured
2. VAD detects end of speech
3. Audio sent to STT provider
4. Transcript sent to LLM with context
5. LLM response streamed
6. Response sent to TTS provider
7. Audio played back to user
8. Cycle repeats

### Ending a Session

1. User taps "End Session" or app closes
2. Audio session released
3. WebSocket disconnected
4. Session saved to history
5. Return to idle state

### Error Recovery

| Error | Recovery |
|-------|----------|
| Network loss | Queue messages, retry on reconnect |
| STT failure | Show error, allow retry or type |
| LLM timeout | Show error, allow retry |
| TTS failure | Show text, skip audio |

---

## Performance Requirements

| Metric | Target | Measurement |
|--------|--------|-------------|
| Recording start | < 100ms | Mic button tap to waveform |
| STT latency | < 500ms | End of speech to transcript |
| LLM TTFT | < 500ms | Request to first token |
| TTS TTFB | < 200ms | Text to first audio byte |
| E2E turn | < 2s | User done speaking to AI starts |

---

## Accessibility

### VoiceOver

- Microphone button: "Start session. Double-tap to begin a voice conversation"
- Status indicator: Announces state changes
- Transcript: "Conversation history. {N} messages"
- Assets: Describes content type and caption

### Dynamic Type

- Transcript text scales with system setting
- Minimum touch targets maintained
- Layout adapts to larger text

### Reduce Motion

- Waveform animation simplified
- Pulse effects disabled
- Transitions use fades instead of slides

---

## Related Documentation

- [01-NAVIGATION_ARCHITECTURE.md](01-NAVIGATION_ARCHITECTURE.md) - App navigation
- [03-CURRICULUM_TAB.md](03-CURRICULUM_TAB.md) - Topic selection
- [08-SIRI_SHORTCUTS.md](08-SIRI_SHORTCUTS.md) - Voice command shortcuts
- [Server API: Sessions](../api-spec/03-SESSIONS.md) - Session API endpoints
- [Server API: WebSocket](../api-spec/08-WEBSOCKET.md) - Real-time protocol
