# Workstream 3: iOS Client (STT, Testing, UI)

## Status: COMPLETE (2026-01-10)

All tasks in this workstream have been implemented and validated.

## Context
This is one of several parallel workstreams identified from an incomplete work audit. You are fixing iOS client issues across STT services, testing infrastructure, and UI components.

**Important:** Use MCP tools for building and testing:
```
mcp__XcodeBuildMCP__session-set-defaults({
  projectPath: "/Users/ramerman/dev/unamentis/UnaMentis.xcodeproj",
  scheme: "UnaMentis",
  simulatorName: "iPhone 17 Pro"
})
```

## Tasks

### 3.1 GLM-ASR On-Device STT
**Status:** ALREADY COMPLETE (working for weeks)
**File:** `UnaMentis/Services/STT/GLMASROnDeviceSTTService.swift`

**Note:** The original plan incorrectly listed this as blocked. GLM-ASR on-device STT has been fully functional for weeks with:
- CoreML models integrated
- GGUF model bundled and working
- Swift/C++ interop enabled
- No action was needed for this workstream

---

### 3.2 Self-Hosted STT Streaming (P2)
**Status:** COMPLETE
**File:** `UnaMentis/Services/STT/SelfHostedSTTService.swift`

**Implementation:**
- Added WebSocket streaming support (`startStreaming`, `sendAudio`, `stopStreaming`, `cancelStreaming`)
- Implemented multi-format response parsing (OpenAI-style, whisper.cpp, faster-whisper)
- HTTP to WebSocket URL conversion with proper query parameters
- Connection lifecycle management with error handling

---

### 4.1 Audio File Loading for Latency Tests (P1)
**Status:** COMPLETE
**File:** `UnaMentis/Testing/LatencyHarness/LatencyTestCoordinator.swift`

**Implementation:**
- Added `transcribeAudioFile()` method for loading audio files
- Implemented audio format conversion (any format to 16kHz mono PCM)
- Chunked audio streaming to STT service (100ms chunks)
- Proper timing metrics for STT latency
- Added shared `executeLLMAndTTSPhases()` for code reuse

---

### 5.1 Voice Cloning UI (P2)
**Status:** COMPLETE
**Files:**
- `UnaMentis/UI/Settings/ChatterboxSettingsView.swift`
- `UnaMentis/UI/Settings/ChatterboxSettingsViewModel.swift`
- `UnaMentis/UI/Settings/VoiceCloningViews.swift` (new file)

**Implementation:**
- Added voice cloning section to Chatterbox settings
- Created `AudioFilePickerView` for selecting audio files (WAV, MP3, M4A, AAC)
- Created `AudioRecorderView` for recording reference audio with level metering
- Validates 5+ second minimum duration
- Reference audio stored in Documents/VoiceCloning/

---

### 5.2 LaTeX Rendering (P3 - Lower Priority)
**Status:** ALREADY COMPLETE (no changes needed)
**File:** `UnaMentis/UI/Components/FormulaRendererView.swift`

**Finding:** The implementation was already complete with:
- SwiftMath integration via Package.swift dependency
- `MathViewRepresentable` wrapper for `MTMathUILabel`
- Both iOS and macOS support
- Unicode approximation fallback only when SwiftMath unavailable
- The plan description was outdated

---

## Verification

After completing each task:
1. Build with MCP: `mcp__XcodeBuildMCP__build_sim`
2. Run on simulator: `mcp__XcodeBuildMCP__build_run_sim`
3. Test specific functionality:
   - STT streaming: Test with self-hosted server
   - Audio loading: Run latency tests with audio files
   - Voice cloning: Navigate to settings, configure reference audio
   - LaTeX: View content with math formulas
4. Run `/validate` to ensure tests pass
