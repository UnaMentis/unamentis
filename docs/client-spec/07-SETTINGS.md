# Settings

**Version:** 1.0.0
**Last Updated:** 2026-01-16
**Platform:** iOS (Swift/SwiftUI)

---

## Overview

Settings (accessed via More menu) allows users to configure API providers, voice preferences, self-hosted server options, and debug tools. The settings screen is organized into logical sections.

![Settings - Providers](screenshots/settings/settings-providers-iphone.png)

---

## Settings Structure

```
Settings
├── API Providers
│   ├── AssemblyAI (STT)
│   ├── Deepgram (STT + TTS)
│   ├── OpenAI (LLM)
│   ├── Anthropic (LLM)
│   ├── ElevenLabs (TTS)
│   ├── Groq (STT)
│   ├── LiveKit API Key (RT)
│   └── LiveKit Secret (RT)
├── Session Cost Estimates
├── Voice & AI Settings
├── Self-Hosted Server
├── Debug & Testing
│   ├── Subsystem Diagnostics
│   ├── Device Health Monitor
│   ├── Audio Pipeline Test
│   ├── Provider Connectivity
│   ├── TTS Playback Tuning
│   └── Conversation Test
├── Help
│   ├── Help & Voice Commands
│   ├── Siri Voice Commands
│   └── Show Welcome Tour
└── About
    ├── Version
    ├── Documentation
    └── Privacy Policy
```

---

## API Providers

### Provider Configuration

Each provider row shows:
- Provider icon/logo
- Provider name
- Service type (STT, TTS, LLM, RT)
- Configuration status (Set / Not set)

Tap to configure:

```
┌──────────────────────────────────────┐
│ < Settings      OpenAI        [Test] │
├──────────────────────────────────────┤
│                                      │
│ API Key                              │
│ ┌──────────────────────────────────┐ │
│ │ sk-••••••••••••••••••••••••XXXX │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Model                                │
│ [gpt-4o ▼]                          │
│                                      │
│ Pricing                              │
│ Input: $0.0025/1K tokens             │
│ Output: $0.01/1K tokens              │
│                                      │
│ Status: ● Connected                  │
│ Last tested: 2 minutes ago           │
│                                      │
└──────────────────────────────────────┘
```

### Provider Types

| Type | Providers | Purpose |
|------|-----------|---------|
| STT | AssemblyAI, Deepgram, Groq | Speech-to-text |
| TTS | ElevenLabs, Deepgram | Text-to-speech |
| LLM | OpenAI, Anthropic | Language model |
| RT | LiveKit | Real-time audio streaming |

### Configuration Fields

| Provider | Fields |
|----------|--------|
| AssemblyAI | API Key |
| Deepgram | API Key |
| OpenAI | API Key, Model selection |
| Anthropic | API Key, Model selection |
| ElevenLabs | API Key, Voice selection |
| Groq | API Key |
| LiveKit | API Key, Secret |

### Connection Testing

Each provider has a "Test" button:
- Validates API key
- Tests actual API call
- Shows latency
- Reports errors

---

## Session Cost Estimates

View estimated costs per session:

| Provider | Rate | Typical Session |
|----------|------|-----------------|
| STT | $0.006/min | $0.09 (15 min) |
| TTS | $0.015/1K chars | $0.03 |
| LLM | $0.01/1K tokens | $0.15 |
| **Total** | | **$0.27** |

---

## Voice & AI Settings

### Voice Output

| Setting | Options |
|---------|---------|
| TTS Provider | Apple (On-Device), ElevenLabs, Deepgram |
| Voice | Provider-specific voice list |
| Speed | 0.75x - 2.0x |
| Pitch | Low, Normal, High |

### Voice Input

| Setting | Options |
|---------|---------|
| STT Provider | Apple (On-Device), AssemblyAI, Deepgram, Groq |
| Language | Auto-detect, English, Spanish, etc. |
| VAD Sensitivity | Low, Medium, High |
| Silence Duration | 1.0s - 3.0s |

### AI Model

| Setting | Options |
|---------|---------|
| LLM Provider | OpenAI, Anthropic, Local (MLX) |
| Model | Provider-specific model list |
| Temperature | 0.0 - 1.0 |
| Max Tokens | 256 - 4096 |

### On-Device Options

When using on-device processing:
- **Apple Speech**: Built-in STT
- **Apple TTS**: Built-in voices
- **Local MLX**: On-device LLM (requires download)

---

## Self-Hosted Server

### Enable Self-Hosted

Toggle to use local server instead of cloud:

```
┌──────────────────────────────────────┐
│ Self-Hosted Server                   │
├──────────────────────────────────────┤
│ Enable Self-Hosted Server    [    ]  │
│                                      │
│ Enable to use your Mac as an AI      │
│ server for zero-cost inference.      │
│                                      │
│ Server Address                       │
│ ┌──────────────────────────────────┐ │
│ │ http://192.168.1.100:8766       │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Status: ○ Not connected              │
│ [Test Connection]                    │
│                                      │
└──────────────────────────────────────┘
```

### Server Requirements

- UnaMentis Server running on Mac
- Network connectivity to device
- USM (UnaMentis Server Manager) installed

### Auto-Discovery

When enabled:
- Scans local network for servers
- Shows available servers
- One-tap connection

---

## Debug & Testing

### Subsystem Diagnostics

System health checks:
- Audio subsystem status
- Network connectivity
- Provider availability
- Storage usage

### Device Health Monitor

Real-time monitoring:
- Memory usage
- CPU usage
- Battery impact
- Thermal state

### Audio Pipeline Test

End-to-end audio testing:
- Microphone check
- Speaker check
- Latency measurement
- Quality assessment

### Provider Connectivity

Test all configured providers:
- Connection status
- Response latency
- Error details

### TTS Playback Tuning

Adjust audio playback:
- Buffer size
- Pre-buffering
- Latency vs. quality

### Conversation Test

Simulated conversation:
- Test full pipeline
- Measure latencies
- Verify configuration

---

## Debug Mode Settings

### Debug Mode

Master toggle for debug features:
- Shows additional UI elements
- Enables logging
- Exposes developer tools

### Verbose Logging

Enhanced logging:
- Detailed API logs
- Audio processing logs
- State transitions

### Remote Logging

Send logs to log server:
- Log Server IP configuration
- Real-time log streaming
- Useful for debugging

### Use Same IP as Server

Auto-configure log server:
- Uses self-hosted server IP
- Simplifies setup

---

## Help Section

### Help & Voice Commands

In-app help documentation:
- Feature guides
- Voice command reference
- FAQ

### Siri Voice Commands

Configure Siri integration:
- Available shortcuts
- Custom phrases
- Setup instructions

### Show Welcome Tour

Re-run onboarding:
- App introduction
- Feature highlights
- Setup wizard

---

## About Section

### Version

App version information:
- Version number
- Build number
- Tap for detailed info

### Documentation

Links to documentation:
- User guide
- API documentation
- Release notes

### Privacy Policy

Legal information:
- Privacy policy
- Terms of service
- Data handling

---

## Data Storage

### Settings Persistence

| Data | Storage | Sync |
|------|---------|------|
| API Keys | Keychain | No (security) |
| Preferences | UserDefaults | iCloud |
| Provider config | UserDefaults | iCloud |

### Reset Options

- Reset individual provider
- Reset all settings
- Clear all data

---

## Accessibility

### VoiceOver

- Section headers announced
- Toggle states read
- Input fields labeled

### Dynamic Type

- All text scales
- Layout adapts
- Maintains usability

---

## Related Documentation

- [01-NAVIGATION_ARCHITECTURE.md](01-NAVIGATION_ARCHITECTURE.md) - Accessing settings
- [06-ANALYTICS_TAB.md](06-ANALYTICS_TAB.md) - Provider metrics
- [Server API: System](../api-spec/07-SYSTEM.md) - Server configuration
