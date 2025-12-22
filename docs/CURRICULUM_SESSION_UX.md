# Curriculum Session UX Design Principles

This document defines the core UX principles for curriculum topic sessions. These principles ensure the app feels interactive and engaging even though much content is pre-generated.

## Core Principle: Synchronized Text and Audio

**The user should never see text far ahead of what they're hearing.**

When a curriculum topic session begins, content arrives from the server in segments. Each segment has:
- Text content (what will be displayed)
- Audio content (TTS of the text)

### The Synchronization Rule

1. **Text is buffered** when it arrives from the server
2. **Text is displayed** only when its corresponding audio **starts playing**
3. Audio and text for the same segment appear together, not separately
4. The next segment's text appears the instant the previous segment's audio ends

### Why This Matters

- Prevents the jarring experience of seeing 4-6 paragraphs appear at once
- Keeps the experience feeling "live" and interactive
- Works well whether the user is looking at the screen or listening with phone in pocket
- Creates a seamless, podcast-like flow

### Implementation Details

In `SessionViewModel`:
- `pendingTextSegments: [Int: String]` - Buffers text by segment index
- `audioQueue: [(audio: Data, text: String, index: Int)]` - Queues audio with its paired text
- `playNextAudioSegment()` displays text **only** when audio playback starts

```
Server sends: [text1] [text2] [text3] [text4]
             [audio1] [audio2] [audio3] [audio4]

Display timeline:
t=0   audio1 starts -> text1 displayed
t=30s audio1 ends, audio2 starts -> text2 displayed
t=60s audio2 ends, audio3 starts -> text3 displayed
...
```

---

## Session Progress Indicator

**Users need to know where they are in a topic, especially for pause/resume.**

### Design

- Position: Top of session view (above status indicator)
- Style: Minimal horizontal progress bar (4pt height)
- Shows: `completed/total` segments as small text
- Only visible for curriculum sessions, not free-form conversations

### Why Top Position?

- Bottom area has VU meter - putting progress there creates confusion
- Top naturally reads as "how far through this content am I"
- Minimal vertical footprint preserves screen real estate

---

## Start Button Iconography

**Icon choice should match the action's primary direction.**

| Context | Who Speaks First | Icon | Label |
|---------|------------------|------|-------|
| Free-form session | User | `mic.fill` | "Start Voice Session" |
| Curriculum topic | AI | `waveform` | "Start Lesson" |

### Rationale

- Microphone icon = "I'm going to talk"
- Waveform icon = "Audio will play" / "Someone will speak to me"
- Users shouldn't tap a microphone icon expecting to listen

---

## Curriculum vs Conversation Mode Differences

| Aspect | Curriculum Mode | Conversation Mode |
|--------|-----------------|-------------------|
| Who starts | AI speaks first | User speaks first |
| Content source | Pre-generated transcript | Dynamic LLM response |
| Progress tracking | Yes (segment-based) | No |
| Start icon | `waveform` | `mic.fill` |
| Controls shown | Stop / Pause-Play | Start/Stop button |
| Text delivery | Synchronized with audio | Streams as generated |

---

## Files Involved

- `UnaMentis/UI/Session/SessionView.swift` - Main session UI, progress bar, controls
- `UnaMentis/UI/Curriculum/CurriculumView.swift` - Topic detail view, start button
- `UnaMentis/Services/Curriculum/TranscriptStreamingService.swift` - Fetches and streams content
- `UnaMentis/Core/Session/SessionManager.swift` - Session state machine

---

## Future Considerations

1. **Audio prefetch depth** - Currently segments are fetched as needed. Could prefetch N segments ahead for seamless playback on slow connections.

2. **Checkpoint questions** - UMLCF format supports checkpoint questions. When these appear, playback should pause and wait for user response.

3. **Resume from position** - If user stops mid-topic and returns later, should resume from last completed segment.
