# Audio Playback Orchestrator

Cross-platform specification for the unified audio playback pipeline used by all voice-enabled modules in UnaMentis.

## Problem

Every module that plays audio (voice sessions, reading list, knowledge bowl, curriculum) independently implements the same core loop:

```
synthesize text -> stream audio chunks -> play via audio engine -> wait -> next segment -> gap
```

This duplication means:
- Bug fixes must be applied N times
- Performance tuning diverges across modules
- New modules re-invent the wheel
- Latency, caching, and silence behavior vary unpredictably

## Solution

A single **AudioPlaybackOrchestrator** component handles the core playback loop. Modules configure it with presets and receive callbacks for module-specific behavior (position persistence, bookmarks, barge-in, etc.).

```
+--------------------------------------------------------------+
|  AudioPlaybackOrchestrator                                   |
|  Core (shared by all modules):                               |
|  - Play segment: cached -> prefetched -> stream from TTS     |
|  - Prefetch N segments ahead (configurable depth)            |
|  - Inter-segment silence (configurable)                      |
|  - Pause / resume / stop / suspend                           |
|  - State machine: idle, playing, paused, buffering, error    |
|  - Time-to-first-audio instrumentation hooks                 |
+--------------------------------------------------------------+
         |                    |                    |
    SessionManager      ReadingPlayback      KBVoiceCoord
    + LLM streaming     + position persist   + server cache
    + sentence extract  + skip back/forward  + cache warming
    + barge-in          + bookmarks          + fallback TTS
    + utterance detect  + import pre-gen
```

## Components

### 1. PlayableSegment

An abstraction over the unit of content that gets synthesized and played. Each module provides its own conforming type.

**Required properties:**

| Property | Type | Description |
|----------|------|-------------|
| `segmentIndex` | `Int` | Zero-based position in the segment sequence |
| `segmentText` | `String` | Text content to synthesize (ignored if cached audio exists) |
| `cachedAudio` | `CachedSegmentAudio?` | Pre-existing audio data, `nil` means TTS synthesis is needed |

**CachedSegmentAudio** holds raw audio bytes plus format metadata (sample rate, channel count, encoding). When present, the orchestrator skips TTS entirely and plays the cached audio with zero synthesis latency.

**Module-specific conforming types:**
- **Session:** Sentence wrapper (text extracted from LLM token stream)
- **Reading List:** Chunk data (text + optional import-time pre-generated audio)
- **Knowledge Bowl:** Question/feedback adapter (text + optional server-cached WAV)
- **Curriculum:** Transcript segment (text + optional server TTS audio)

### 2. PlaybackOrchestratorConfig

Controls how the orchestrator behaves. Modules select a preset or provide custom values.

| Field | Type | Description |
|-------|------|-------------|
| `prefetchDepth` | `Int` | Number of segments to synthesize ahead of the current one |
| `interSegmentSilenceMs` | `Int` | Milliseconds of silence inserted between segments |
| `retainBehindCount` | `Int` | Number of played segments to keep in memory for skip-back |
| `bufferTimeoutSeconds` | `TimeInterval` | Max wait time for a prefetch to complete before falling back to direct synthesis |

**Presets:**

| Preset | Prefetch | Silence | Retain Behind | Timeout | Use Case |
|--------|----------|---------|---------------|---------|----------|
| `default` | 3 | 0 | 0 | 10s | General purpose |
| `readingList` | 5 | 600 | 6 | 10s | Long-form reading with natural pacing |
| `session` | 2 | 0 | 0 | 15s | Conversational, low-latency |
| `knowledgeBowl` | 0 | 0 | 0 | 10s | Single question/answer, fire-and-forget |

### 3. PlaybackOrchestratorDelegate

Callback interface for module-specific behavior. All methods have default no-op implementations so modules only override what they need.

| Method | Description | Example Usage |
|--------|-------------|---------------|
| `orchestratorWillPlaySegment(at:)` | Called before playing; return `false` to skip | Skip empty segments |
| `orchestratorDidFinishSegment(at:)` | Called after a segment finishes playing | Save position to persistence |
| `orchestratorDidChangeSegment(index:, total:)` | Called when the current segment changes | Update UI progress |
| `orchestratorDidComplete()` | Called when all segments have played | Show completion state |
| `orchestratorDidEncounterError(_:)` | Called on playback error | Show error UI |

### 4. AudioPlaybackOrchestrator (Core)

The orchestrator itself. Must be thread-safe (actor in Swift, coroutine-safe in Kotlin).

**Dependencies:**
- A TTS service (conforms to platform TTS protocol)
- An audio engine (platform low-level audio player)

**Public API:**

| Method | Description |
|--------|-------------|
| `loadSegments(_:)` | Set the full list of segments to play |
| `appendSegments(_:)` | Add segments dynamically (for streaming/LLM use case) |
| `signalNoMoreSegments()` | Tell the orchestrator no more segments will arrive |
| `startPlayback(from:)` | Start playing from a given segment index |
| `pausePlayback()` | Pause playback, preserving all state |
| `resumePlayback()` | Resume from paused state |
| `stopPlayback()` | Full stop, release resources |
| `suspendPlayback()` | Lightweight stop: preserves cached audio, prefetch state, and position |
| `skipToSegment(_:)` | Jump to a specific segment index |
| `setExpectsMoreSegments(_:)` | Enable/disable dynamic segment mode |

**Read-only state:**

| Property | Type | Description |
|----------|------|-------------|
| `state` | `OrchestratorState` | Current state (idle, playing, paused, buffering, completed, error) |
| `currentIndex` | `Int` | Index of the currently playing segment |
| `segments.count` | `Int` | Total number of loaded segments |

### 5. Audio Engine Cache

A shared cache that keeps the platform audio engine warm between navigations. Without this, every screen transition tears down and rebuilds the audio engine (1-2 second cold start).

**Behavior:**
- Singleton, shared across all modules
- Returns a warm engine instance if available, creates a new one if not
- Starts a configurable inactivity timer (default: 2 minutes) on release
- If no module reclaims the engine within the timeout, tears it down

### 6. TTS Service Cache

A shared cache that keeps the TTS model loaded between sessions. On-device models have significant cold-start times (1-2 seconds for model loading).

**Behavior:**
- Singleton, shared across all modules
- Returns the cached TTS service or creates a new one
- Deferred release with configurable timeout (default: 2 minutes)
- Platform-specific: references the TTS provider resolution system

## Core Playback Loop

This is the single implementation that replaces all module-specific loops. Pseudocode:

```
while state == playing AND segments remain:
    segment = segments[currentIndex]

    // 1. Try cached audio (0ms latency)
    if segment.cachedAudio exists:
        play(segment.cachedAudio)
        instrument: markCachedHit

    // 2. Try prefetch cache (0ms latency if ready)
    else if prefetchCache[currentIndex] exists:
        play(prefetchCache[currentIndex])

    // 3. Wait for in-progress prefetch (bounded by bufferTimeout)
    else if prefetchTask[currentIndex] is running:
        audio = await prefetchTask[currentIndex] with timeout
        if audio:
            play(audio)
        else:
            goto step 4  // timeout, fall back to direct synthesis

    // 4. Direct synthesis (streaming, ~200ms TTFB)
    else:
        stream = ttsService.synthesize(segment.text)
        for chunk in stream:
            instrument: markTTSFirstChunk (first chunk only)
            audioEngine.play(chunk)

    // 5. Post-segment
    delegate.didFinishSegment(currentIndex)

    // 6. Inter-segment silence
    if config.interSegmentSilenceMs > 0:
        sleep(config.interSegmentSilenceMs)

    // 7. Advance
    currentIndex += 1
    delegate.didChangeSegment(currentIndex, totalSegments)

    // 8. Trigger prefetch for upcoming segments
    for i in (currentIndex + 1) ..< (currentIndex + 1 + config.prefetchDepth):
        if i < totalSegments AND prefetchCache[i] is nil AND no active task:
            start prefetch task for segments[i]

    // 9. Evict old entries
    evict entries where index < (currentIndex - config.retainBehindCount)

delegate.didComplete()
```

### Pause/Resume

- **Pause:** Sets state to `paused`, pauses audio engine output. The playback loop checks state at the top of each iteration and suspends.
- **Resume:** Sets state to `playing`, resumes audio engine. The loop continues from where it left off.

### Suspend vs. Stop

- **Suspend:** Preserves all cached audio, prefetch state, current position, and loaded segments. Used when navigating away temporarily (e.g., switching screens). The audio engine and TTS service are returned to their respective caches.
- **Stop:** Full teardown. Clears all state, cancels prefetch tasks, releases resources. Used on explicit user action (e.g., "Done" button).

### Dynamic Segment Addition

For modules where content arrives while playing (e.g., voice sessions where sentences are extracted from an LLM token stream):

1. Module calls `appendSegments()` as new content arrives
2. The playback loop sees the updated segment list and continues
3. Module calls `signalNoMoreSegments()` when the LLM response is complete
4. The loop plays remaining segments and calls `didComplete()`

If the loop reaches the end of available segments before `signalNoMoreSegments()` is called, it enters `buffering` state and waits for new segments or the signal.

## Module Integration Patterns

### Voice Session

The session module has unique requirements: content arrives incrementally from an LLM, sentences are extracted in real-time, and the user can interrupt (barge-in).

**Integration:**
- Sentence extraction remains external to the orchestrator
- Extracted sentences are wrapped as PlayableSegment and appended via `appendSegments()`
- Barge-in is handled externally: on voice detection, call `orchestrator.stop()` and transition to listening state
- Inter-sentence silence: 0ms (natural conversational flow)
- Prefetch depth: 2 (sentences arrive faster than they play)

### Reading List

The reading list plays pre-chunked document content with bookmarks, skip controls, and position persistence.

**Integration:**
- Chunks loaded at startup, passed via `loadSegments()`
- Import-time pre-generated audio attached as `cachedAudio` on first N segments
- Delegate implements `didFinishSegment()` for position persistence to database
- Delegate implements `didChangeSegment()` for UI progress updates
- On navigate away: call `suspend()` (preserves state for instant resume)
- On explicit Done: call `stop()`
- Inter-segment silence: 600ms (natural reading pace)
- Prefetch depth: 5 with retain-behind of 6 for skip-back

### Knowledge Bowl

Knowledge Bowl plays individual questions and feedback with optional server-cached audio.

**Integration:**
- Each question/feedback is a single-segment playback via `KBTextSegment`
- Server-cached audio attached as `cachedAudio` when available (converted from `KBCachedAudio`)
- Falls back to local TTS when server cache misses
- Cache warming: prefetch first N questions at session start (via `KBAudioCache`)
- No prefetch depth (single-segment, fire-and-forget)
- Orchestrator created per `speak()` call, not persistent

### Curriculum/Transcript

Curriculum modules play pre-written transcript content, potentially with server-side TTS.

**Integration:**
- Transcript segments loaded via `loadSegments()`
- Server-generated audio attached as `cachedAudio`
- Falls back to local TTS when server is unavailable
- Delegate handles segment type differentiation (narration, checkpoint, activity)

## State Machine

```
                    +---> buffering ---+
                    |                  |
    idle ---> playing <---> paused     |
      ^         |  ^        |         |
      |         |  +--------+         |
      |         v                     |
      +--- completed <----------------+
      |
      +--- error
```

| State | Description |
|-------|-------------|
| `idle` | No playback active. Ready to start. |
| `playing` | Actively playing audio segments. |
| `paused` | Playback suspended, all state preserved. |
| `buffering` | Waiting for content (prefetch or dynamic segment arrival). |
| `completed` | All segments played successfully. |
| `error(message)` | An error occurred. Contains description. |

## Time-to-First-Audio (TTFA) Instrumentation

The orchestrator includes hooks for measuring latency at each stage:

| Event | When Fired | What It Measures |
|-------|------------|------------------|
| `markActivation` | `play()` called | User intent captured |
| `markCachedHit` | Cached audio found | Cache effectiveness |
| `markTTSFirstChunk` | First TTS chunk received | TTS synthesis latency |
| `markAudioScheduled` | First buffer scheduled on engine | Pipeline overhead |
| `markAudioPlaying` | Engine begins outputting audio | True TTFA |

## Platform Implementation Notes

### iOS (Swift)

- Orchestrator is an `actor` for thread safety
- Audio engine wraps `AVAudioEngine` with `AVAudioPlayerNode`
- TTS service protocol uses `AsyncStream<TTSAudioChunk>`
- Prefetch tasks are Swift `Task` instances
- Delegate methods are `async` for actor isolation
- PlayableSegment requires `Sendable` conformance

### Android (Kotlin)

- Orchestrator uses coroutines with a `Mutex` or is a class with coroutine-safe internal state
- Audio engine wraps **Oboe** (Google's low-latency C++ audio library) via JNI
- TTS service protocol uses `Flow<TTSAudioChunk>`
- Prefetch uses `CoroutineScope` with `launch` for background synthesis
- Delegate methods are `suspend` functions
- PlayableSegment is a `data class` or interface

### Shared Principles (Both Platforms)

1. **Single playback loop:** One implementation, configured per module
2. **Three-tier audio resolution:** cached -> prefetched -> direct synthesis
3. **Configurable silence:** Per-module inter-segment gap
4. **Warm caching:** Audio engine and TTS model kept alive between navigations
5. **Suspend vs. stop:** Lightweight state preservation for temporary navigation vs. full teardown
6. **Dynamic segments:** Support for content that arrives while playing
7. **Skip controls:** Forward, backward, and jump-to within retain window
8. **Instrumentation:** Consistent TTFA measurement across all paths

## Config Presets Reference

These presets encode the known-good settings for each module. Custom values are allowed but these should be the defaults.

```
default:
  prefetchDepth: 3
  interSegmentSilenceMs: 0
  retainBehindCount: 0
  bufferTimeoutSeconds: 10

readingList:
  prefetchDepth: 5
  interSegmentSilenceMs: 600
  retainBehindCount: 6
  bufferTimeoutSeconds: 10

session:
  prefetchDepth: 2
  interSegmentSilenceMs: 0
  retainBehindCount: 0
  bufferTimeoutSeconds: 15

knowledgeBowl:
  prefetchDepth: 0
  interSegmentSilenceMs: 0
  retainBehindCount: 0
  bufferTimeoutSeconds: 10
```

## Eviction Strategy

The prefetch cache uses a sliding window approach:

- **Ahead:** Always keep `prefetchDepth` segments synthesized ahead of current
- **Behind:** Keep `retainBehindCount` segments for instant skip-back
- **Evict:** When `currentIndex - segmentIndex > retainBehindCount`, remove from cache
- **Memory cap:** Total cached audio should not exceed 50MB (configurable)

When playing from cached/pre-generated audio (no synthesis needed), the prefetch window still applies to segments without cached audio.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| TTS synthesis fails for one segment | Log error, skip segment, continue to next |
| TTS synthesis fails for all segments | Transition to error state, notify delegate |
| Audio engine fails | Transition to error state, notify delegate |
| Prefetch timeout | Fall back to direct synthesis for that segment |
| Dynamic segment stall | Enter buffering state, resume when segments arrive or signal received |

The orchestrator never silently fails. Every error is either recovered from (with logging) or surfaced to the delegate.

## Migration Checklist

When migrating a module to use the orchestrator:

1. Define the module's PlayableSegment conforming type
2. Choose or create a config preset
3. Implement the delegate (only override needed methods)
4. Replace the module's internal playback loop with orchestrator calls
5. Replace direct TTS synthesis calls with segment loading
6. Replace custom prefetch logic with config-driven orchestrator prefetch
7. Replace custom state tracking with orchestrator state observation
8. Wire up UI to delegate callbacks
9. Use `suspendPlayback()` for temporary navigation, `stopPlayback()` for explicit exit
10. Verify TTFA instrumentation fires correctly
11. Test: play, pause, resume, skip forward, skip back, error recovery
12. Test: cold start, warm resume, pre-generated audio path

## iOS Implementation Status

All three iOS modules have been migrated to the shared orchestrator:

| Module | Status | Segment Type | Delegate | Config Preset |
|--------|--------|-------------|----------|---------------|
| Reading List | Migrated | `ReadingChunkData` | `ReadingPlaybackOrchestratorDelegate` | `.readingList` |
| Voice Session | Migrated | `SessionSentenceSegment` | `SessionOrchestratorDelegate` | `.session` |
| Knowledge Bowl | Migrated | `KBTextSegment` | None (fire-and-forget) | `.knowledgeBowl` |

**iOS files:**
- `Core/Audio/AudioPlaybackOrchestrator.swift` (core actor)
- `Core/Audio/PlayableSegment.swift` (protocol + CachedSegmentAudio)
- `Core/Audio/PlaybackOrchestratorConfig.swift` (config + presets)
- `Core/Audio/PlaybackOrchestratorDelegate.swift` (delegate protocol)
- `Core/Audio/AudioEngineCache.swift` (warm engine singleton)
- `Core/Audio/AudioTTSCache.swift` (warm TTS singleton)
