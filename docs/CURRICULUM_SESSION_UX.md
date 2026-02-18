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

> **Note:** This describes the curriculum transcript streaming path (server-side TTS via `TranscriptStreamingService`), which uses its own audio queue and AVAudioPlayer. The interactive voice session path uses `AudioPlaybackOrchestrator` with dynamic segment append instead. See `docs/design/AUDIO_PLAYBACK_ORCHESTRATOR.md`.

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

## Barge-In: Interrupting the Lecture

**Users can interrupt at any time to ask questions, request examples, or clarify concepts.**

Barge-in is a first-class feature that makes curriculum sessions feel conversational rather than passive.

### Two-Stage Confirmation

To avoid false positives (coughs, background noise, speaker audio leaking into mic):

1. **Stage 1: Tentative Pause** (0-600ms)
   - VAD detects speech above threshold (0.7 confidence)
   - Playback pauses immediately (not stopped)
   - System waits for confirmation

2. **Stage 2: Confirmation or Resume**
   - If continued speech detected → Confirmed barge-in, full interrupt
   - If silence → False positive, resume playback immediately

### State Flow

```
AI Speaking (lecture playing)
    ↓ VAD detects speech > 0.7 confidence
.interrupted (tentative pause)
    ├─ Continued speech → User Speaking (collect utterance)
    │   ↓ 1s silence detected
    │   Processing (transcribe + LLM)
    │   ↓
    │   AI Speaking (respond to question)
    │   ↓
    │   User Speaking (wait for decision)
    │   ├─ Silence → Resume lecture
    │   └─ More speech → Another question
    │
    └─ No speech (600ms) → AI Speaking (resume from pause point)
```

### Echo/Feedback Prevention

The microphone runs in parallel with speaker playback. To prevent the AI's voice from triggering barge-in:

1. Audio session uses `.voiceChat` mode (hardware AEC)
2. Barge-in threshold (0.7) is higher than general VAD (0.5)
3. Voice processing enabled on AudioEngine input node
4. Hardware AEC/AGC/NS via `setVoiceProcessingEnabled(true)`

### After Barge-In: Resume vs Tangent

When the AI finishes responding to a question:
- User says nothing (silence) → Resume lecture from pause point
- User says "continue" or similar → Resume lecture
- User asks another question → Answer it, then wait again

The AI's response should naturally invite the user to choose:
> "...does that clarify things? Would you like to continue with the lecture, or explore this further?"

### Implementation Details

In `SessionViewModel`:
- `bargeInAudioEngine` - AudioEngine running VAD on microphone during playback
- `isTentativeBargeIn` - Whether we're in the 600ms confirmation window
- `bargeInConfirmationTask` - Timer that resumes if no continued speech
- `bargeInPauseSegmentIndex` / `bargeInPauseTime` - Where to resume from
- `handleVADResult()` - Processes VAD results, triggers state transitions
- `handleTentativeBargeIn()` - Stage 1: pause and wait
- `confirmBargeIn()` - Stage 2: full interrupt, listen to user
- `resumeFromTentativeBargeIn()` - False positive recovery

---

## Testing Barge-In

Since barge-in requires real audio input, testing can be challenging. Approaches:

### 1. Manual Testing with Headphones
- Use headphones to prevent speaker→mic feedback
- Start a curriculum session
- Speak during playback to trigger barge-in
- Verify pause/resume behavior

### 2. Audio Injection (Development)
The `AudioEngine.processAudioBuffer()` method allows direct buffer injection:
```swift
// Inject a buffer that simulates speech
await audioEngine.processAudioBuffer(speechBuffer)
```

### 3. VAD Mock (Unit Tests)
Mock the VADService to return controlled results:
```swift
let mockVAD = MockVADService()
mockVAD.nextResult = VADResult(isSpeech: true, confidence: 0.8, ...)
```

---

## Future Considerations

1. **Audio prefetch depth** - Currently segments are fetched as needed. Could prefetch N segments ahead for seamless playback on slow connections.

2. **Checkpoint questions** - UMCF format supports checkpoint questions. When these appear, playback should pause and wait for user response.

3. **Resume from position** - If user stops mid-topic and returns later, should resume from last completed segment.

4. **Adaptive barge-in threshold** - Adjust threshold based on ambient noise level or false positive rate.

5. **TTS for barge-in responses** - Currently the AI response after barge-in is text-only. Should be spoken via TTS.
