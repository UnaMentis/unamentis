---
name: verify-audio
description: Build, launch, and verify the audio pipeline is using correct TTS/STT providers via MCP simulator interaction
argument-hint: "[quick|full]"
disable-model-invocation: true
---

# /verify-audio - Audio Pipeline Verification

## Purpose

Verifies that the correct TTS and STT providers are active in the running app. Catches silent fallbacks (e.g., Pocket TTS falling back to Apple TTS) that are invisible during manual testing.

**Critical:** Pocket TTS is bundled with every build. If it's not active, something is broken.

## Usage

```
/verify-audio           # Build, launch, verify TTS/STT providers (default)
/verify-audio quick     # Skip build, just verify already-running app
/verify-audio full      # Build + verify all modules (Learning, KB, Reading List)
```

## Workflow

### 1. Pre-flight

Ensure MCP session defaults are configured:
```
mcp__XcodeBuildMCP__session-set-defaults({
  projectPath: "/Users/ramerman/dev/unamentis/UnaMentis.xcodeproj",
  scheme: "UnaMentis",
  simulatorName: "iPhone 16 Pro"
})
```

If `quick` mode, skip to step 4.

### 2. Build

Build for simulator:
```
mcp__XcodeBuildMCP__build_sim
```

If build fails, report FAIL with build errors and stop.

### 3. Install and Launch

```
mcp__XcodeBuildMCP__install_app_sim
mcp__XcodeBuildMCP__launch_app_sim
```

Wait 3 seconds for app startup.

### 4. Start Log Capture

```
mcp__XcodeBuildMCP__start_sim_log_cap
```

### 5. Navigate to Learning

Use deep link to navigate to a learning session:
```bash
xcrun simctl openurl booted "unamentis://learning"
```

Wait 5 seconds for session initialization and provider setup.

### 6. Stop Log Capture and Screenshot

```
mcp__XcodeBuildMCP__stop_sim_log_cap
mcp__ios-simulator__screenshot
```

### 7. Analyze Logs

Check for these patterns in the captured logs:

**PASS indicators:**
- `KyutaiPocketTTSService` or `Pocket TTS` initialization messages
- `ensureLoaded` model loading confirmation
- `STREAMING TTFB` latency measurements from Pocket TTS

**FAIL indicators:**
- `falling back to Apple TTS` or `Using Apple TTS (fallback`
- `Pocket TTS models not available`
- `AppleTTSService` being created when Pocket TTS was expected
- Any `.error` level TTS fallback logs

**STT checks:**
- `GLM-ASR` or `GLMASROnDevice` initialization = PASS
- STTProviderRouter health status

### 8. Navigate to Settings (full mode)

For `full` mode, also verify Settings shows correct providers:
```bash
xcrun simctl openurl booted "unamentis://settings"
```

Use `mcp__ios-simulator__ui_describe_all` to read the settings UI and verify:
- TTS provider shows Pocket TTS (or user's chosen provider)
- STT provider shows GLM-ASR (or user's chosen provider)

For `full` mode, also navigate to Knowledge Bowl and Reading List to verify TTS in those modules.

### 9. Report

```
AUDIO PIPELINE VERIFICATION
============================
Mode: [default|quick|full]

TTS Provider:
  [PASS/FAIL] Pocket TTS initialized: [yes/no]
  [PASS/FAIL] Model loaded: [yes/no]
  [PASS/FAIL] No Apple TTS fallback detected: [yes/no]
  TTFB: [measured or N/A]

STT Provider:
  [PASS/FAIL] GLM-ASR initialized: [yes/no]
  [PASS/FAIL] STTProviderRouter healthy: [yes/no]

Evidence:
  Log lines: [relevant excerpts]
  Screenshot: [path]

RESULT: [PASS/FAIL]
```

## Success Criteria

- **PASS:** Pocket TTS active, no Apple TTS fallback, GLM-ASR initialized
- **FAIL:** Any Apple TTS fallback detected, or Pocket TTS not initialized

## When to Run

- After modifying any TTS/STT/audio code
- After modifying provider selection or configuration code
- Before running `/validate` as part of the development loop
- Before staging changes for commit
