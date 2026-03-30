---
name: audio-context
description: Critical audio pipeline context for voice, TTS, STT, and audio work. Auto-loads when working on audio-related code to prevent recurring provider fallback bugs.
user-invocable: false
---

# Audio Pipeline Context

**Standard on-device models (bundled with every build, always available):**
- **TTS:** Pocket TTS (KyutaiPocketTTSService) - 100M param, 8 voices, ~200ms TTFB
- **STT:** GLM-ASR (GLMASROnDeviceSTTService) - on-device speech recognition

These models ship with the app binary. They do NOT require separate download. They are ALWAYS available.

## TTS Fallback Rules

- Pocket TTS is the standard. Apple TTS is ONLY a last-resort degraded fallback.
- A fallback to Apple TTS is a **BUG**, not a normal operating state.
- Correct hierarchy: **User's chosen provider -> Pocket TTS -> Apple TTS**
- Reference pattern: `TTSService.swift` `TTSProvider.createLocalService()` (line ~364)
- Current AppleTTSService() fallback sites: !`grep -rc "AppleTTSService()" /Users/ramerman/dev/unamentis/UnaMentis/ 2>/dev/null | awk -F: '{s+=$2}END{print s}'`

## STT Fallback Rules

- GLM-ASR is the standard on-device STT. Apple Speech Recognition is the fallback.
- STTProviderRouter handles health-based routing with automatic failover.

## Key Files

- `UnaMentis/Services/TTS/KyutaiPocketTTSService.swift` - Primary TTS
- `UnaMentis/Services/STT/GLMASROnDeviceSTTService.swift` - Primary STT
- `UnaMentis/Services/Protocols/TTSService.swift` - TTSProvider enum + correct fallback pattern
- `UnaMentis/Services/STT/STTProviderRouter.swift` - STT routing with health monitoring
- `UnaMentis/Core/Audio/AudioPlaybackOrchestrator.swift` - Shared playback engine
