# Fallback Architecture Guide

This document describes UnaMentis's graceful degradation system that ensures the app works on any device, even without API keys, servers, or network connectivity.

## Design Philosophy

UnaMentis is designed to **always work**, even in degraded conditions. The app should:

1. Never show an error when a fallback exists
2. Automatically use the best available service
3. Log warnings (not errors) when falling back
4. Provide a functional (if limited) experience on any device

## Fallback Chains

### Speech-to-Text (STT)

The STT system has multiple fallback layers:

```
User Selection
    ↓
┌─────────────────────────────────────────────────────────────┐
│ GLM-ASR On-Device                                           │
│   ├─ Primary: GLMASROnDeviceSTTService                      │
│   └─ Fallback: AppleSpeechSTTService (if device unsupported)│
├─────────────────────────────────────────────────────────────┤
│ Apple Speech                                                │
│   └─ Always available (no fallback needed)                  │
├─────────────────────────────────────────────────────────────┤
│ Deepgram Nova-3                                             │
│   ├─ Primary: DeepgramSTTService (requires API key)         │
│   └─ Fallback: AppleSpeechSTTService                        │
├─────────────────────────────────────────────────────────────┤
│ AssemblyAI                                                  │
│   ├─ Primary: AssemblyAISTTService (requires API key)       │
│   └─ Fallback: AppleSpeechSTTService                        │
├─────────────────────────────────────────────────────────────┤
│ Default/Unknown                                             │
│   └─ AppleSpeechSTTService                                  │
└─────────────────────────────────────────────────────────────┘
```

**Implementation:** [SessionView.swift](../UnaMentis/UI/Session/SessionView.swift) lines 1471-1506

### Text-to-Speech (TTS)

The TTS system falls back to Apple's built-in synthesizer:

```
User Selection
    ↓
┌─────────────────────────────────────────────────────────────┐
│ Apple TTS                                                   │
│   └─ Always available (no fallback needed)                  │
├─────────────────────────────────────────────────────────────┤
│ Self-Hosted (Piper)                                         │
│   ├─ Primary: SelfHostedTTSService (requires server)        │
│   └─ Fallback: AppleTTSService                              │
├─────────────────────────────────────────────────────────────┤
│ Self-Hosted (VibeVoice)                                     │
│   ├─ Primary: SelfHostedTTSService (requires server)        │
│   └─ Fallback: AppleTTSService                              │
├─────────────────────────────────────────────────────────────┤
│ ElevenLabs                                                  │
│   ├─ Primary: ElevenLabsTTSService (requires API key)       │
│   └─ Fallback: AppleTTSService                              │
├─────────────────────────────────────────────────────────────┤
│ Deepgram Aura-2                                             │
│   ├─ Primary: DeepgramTTSService (requires API key)         │
│   └─ Fallback: AppleTTSService                              │
├─────────────────────────────────────────────────────────────┤
│ Default/Unknown                                             │
│   └─ AppleTTSService                                        │
└─────────────────────────────────────────────────────────────┘
```

**Implementation:** [SessionView.swift](../UnaMentis/UI/Session/SessionView.swift) lines 1508-1551

### Language Model (LLM)

The LLM system has a three-tier fallback: Cloud API → Self-Hosted → On-Device:

```
User Selection
    ↓
┌─────────────────────────────────────────────────────────────┐
│ Local MLX (On-Device)                                       │
│   ├─ Primary: OnDeviceLLMService (requires bundled models)  │
│   ├─ Fallback 1: SelfHostedLLMService (if server available) │
│   └─ Fallback 2: Error (models required)                    │
├─────────────────────────────────────────────────────────────┤
│ Anthropic (Claude)                                          │
│   ├─ Primary: AnthropicLLMService (requires API key)        │
│   ├─ Fallback 1: SelfHostedLLMService (if server available) │
│   ├─ Fallback 2: OnDeviceLLMService (if models available)   │
│   └─ Fallback 3: Error (no LLM available)                   │
├─────────────────────────────────────────────────────────────┤
│ OpenAI (GPT-4o)                                             │
│   ├─ Primary: OpenAILLMService (requires API key)           │
│   ├─ Fallback 1: SelfHostedLLMService (if server available) │
│   ├─ Fallback 2: OnDeviceLLMService (if models available)   │
│   └─ Fallback 3: Error (no LLM available)                   │
├─────────────────────────────────────────────────────────────┤
│ Self-Hosted (Ollama)                                        │
│   ├─ Primary: SelfHostedLLMService (requires server)        │
│   ├─ Fallback 1: OnDeviceLLMService (if models available)   │
│   └─ Fallback 2: localhost (simulator only)                 │
└─────────────────────────────────────────────────────────────┘
```

**Implementation:** [SessionView.swift](../UnaMentis/UI/Session/SessionView.swift) lines 1553-1670

### Voice Activity Detection (VAD)

VAD has built-in fallback at the service level:

```
┌─────────────────────────────────────────────────────────────┐
│ SileroVADService                                            │
│   ├─ Primary: CoreML model on Neural Engine                 │
│   └─ Fallback: RMS-based dB level detection                 │
└─────────────────────────────────────────────────────────────┘
```

**Implementation:** [SileroVADService.swift](../UnaMentis/Services/VAD/SileroVADService.swift)

## Minimum Viable Configuration

The app can run with **zero configuration** using only built-in Apple services:

| Component | Built-in Service | Quality | Cost |
|-----------|------------------|---------|------|
| STT | Apple Speech | Good | Free |
| TTS | Apple TTS | Good | Free |
| LLM | OnDeviceLLMService* | Limited | Free |
| VAD | Silero (CoreML) | Excellent | Free |

*Requires bundled GGUF model files (~2GB for Ministral 3B or ~670MB for TinyLlama 1.1B)

## Device Compatibility

### Minimum Requirements (Fallback Mode)
- iPhone 12 or newer (A14 Bionic+)
- iOS 17.0+
- No network required
- No API keys required
- Uses Apple Speech + Apple TTS + On-device LLM (if models bundled)

### Recommended Configuration (Full Features)
- iPhone 15 Pro or newer (A17 Pro+)
- 8GB+ RAM for on-device LLM
- Network access for cloud providers
- API keys for premium STT/TTS/LLM

## Runtime Health Monitoring

### STT Provider Router

The [STTProviderRouter](../UnaMentis/Services/STT/STTProviderRouter.swift) monitors server health:

1. Monitors GLM-ASR server health via [GLMASRHealthMonitor](../UnaMentis/Services/STT/GLMASRHealthMonitor.swift)
2. Automatically switches to Deepgram when server is unhealthy
3. Falls back to on-device GLM-ASR when available

### Thermal Adaptation

The app monitors device thermal state and adapts:

```swift
switch ProcessInfo.processInfo.thermalState {
case .nominal: // Full capabilities
case .fair:    // Normal operation
case .serious: // Downgrade to lower-memory models
case .critical: // Disable on-device LLM, use cloud
}
```

## Error Handling Philosophy

### Recoverable Errors (Log Warning, Continue)
- API key missing → Fall back to built-in service
- Server unavailable → Fall back to on-device or cloud
- Model not loaded → Try to load, then fall back

### Non-Recoverable Errors (Show Error)
- No LLM available at all (no API keys, no server, no models)
- Microphone permission denied
- Critical system resource exhaustion

## Logging

Fallback events are logged with `.warning` level:

```
[STT] Deepgram API key not configured, falling back to Apple Speech
[TTS] ElevenLabs API key not configured, falling back to Apple TTS
[LLM] OpenAI API key not configured, falling back to self-hosted
[LLM] No server configured, falling back to on-device LLM
```

These logs help diagnose configuration issues without alarming users.

## Testing Fallback Chains

### Unit Tests
- [STTProviderRouterTests](../UnaMentisTests/Unit/STTProviderRouterTests.swift) - STT failover
- [SileroVADServiceTests](../UnaMentisTests/Unit/SileroVADServiceTests.swift) - VAD fallback

### Manual Testing

1. **No API Keys Test:**
   - Remove all API keys from Settings
   - Verify app uses Apple Speech + Apple TTS
   - Verify LLM falls back appropriately

2. **No Server Test:**
   - Disable self-hosted server
   - Verify STT/TTS fall back to cloud or Apple services
   - Verify LLM uses on-device if models available

3. **Airplane Mode Test:**
   - Enable airplane mode
   - Verify on-device services work
   - Verify appropriate error for cloud-only features

## Related Documentation

- [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) - Architecture overview
- [DEVICE_CAPABILITY_TIERS.md](DEVICE_CAPABILITY_TIERS.md) - Device-specific capabilities
- [APPLE_INTELLIGENCE.md](APPLE_INTELLIGENCE.md) - Apple platform integration
- [GLM_ASR_ON_DEVICE_GUIDE.md](GLM_ASR_ON_DEVICE_GUIDE.md) - On-device STT setup
