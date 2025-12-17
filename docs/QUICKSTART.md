# VoiceLearn - Quick Start Guide

**Get up and running with VoiceLearn iOS**

---

## Project Status

VoiceLearn is a fully-implemented voice-based AI tutoring app with:

- **Voice conversation pipeline** - Audio capture, VAD, STT, LLM, TTS
- **Curriculum system** - Topics, documents, progress tracking
- **Multiple STT providers** - Deepgram, AssemblyAI, GLM-ASR (server + on-device)
- **Multiple TTS providers** - ElevenLabs, Deepgram Aura
- **Multiple LLM providers** - Anthropic Claude, OpenAI GPT
- **Analytics & telemetry** - Latency tracking, cost monitoring
- **Core Data persistence** - Sessions, curriculum, progress
- **AI-driven testing** - iOS Simulator MCP integration

---

## Prerequisites

- **macOS**: 14.0+ (Sonoma or later)
- **Xcode**: 15.4+
- **Swift**: 6.0 (comes with Xcode)
- **iOS Target**: 18.0+

Optional:
- API keys for cloud providers (Deepgram, ElevenLabs, Anthropic, OpenAI)
- GLM-ASR models for on-device speech recognition (~2.4GB)

---

## Step 1: Clone and Build (5 minutes)

```bash
# Clone the repository
git clone https://github.com/your-org/voicelearn-ios.git
cd voicelearn-ios

# Build with Swift Package Manager
swift build

# Or open in Xcode
open Package.swift
```

Build should complete with **zero errors**.

---

## Step 2: Run Tests (2 minutes)

```bash
# Run all tests
swift test

# Or use the test script
./scripts/test-quick.sh
```

Expected: **103+ unit tests, 16+ integration tests passing**

---

## Step 3: Configure API Keys (Optional)

For cloud-based providers, add API keys:

1. Copy the environment template:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your keys:
   ```
   DEEPGRAM_API_KEY=your_key
   ELEVENLABS_API_KEY=your_key
   ANTHROPIC_API_KEY=your_key
   OPENAI_API_KEY=your_key
   ASSEMBLYAI_API_KEY=your_key
   ```

3. Keys are loaded by `APIKeyManager` at runtime

**No API keys?** The app works with on-device GLM-ASR (if models present).

---

## Step 4: Set Up On-Device Models (Optional)

For on-device speech recognition without API costs:

1. **Download models** (~2.4GB total):
   - GLMASRWhisperEncoder.mlpackage (1.2 GB)
   - GLMASRAudioAdapter.mlpackage (56 MB)
   - GLMASREmbedHead.mlpackage (232 MB)
   - glm-asr-nano-q4km.gguf (935 MB)

2. **Place in models directory**:
   ```
   models/glm-asr-nano/
   ├── GLMASRWhisperEncoder.mlpackage/
   ├── GLMASRAudioAdapter.mlpackage/
   ├── GLMASREmbedHead.mlpackage/
   └── glm-asr-nano-q4km.gguf
   ```

3. **Add to Xcode target** (Copy Bundle Resources)

See [GLM_ASR_ON_DEVICE_GUIDE.md](GLM_ASR_ON_DEVICE_GUIDE.md) for details.

---

## Step 5: Run in Simulator (5 minutes)

```bash
# Build for simulator
xcodebuild build \
    -scheme VoiceLearn \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Or in Xcode: Select iPhone 17 Pro simulator, press Cmd+R
```

---

## Project Structure

```
VoiceLearn/
├── Core/                    # Core business logic
│   ├── Audio/               # AudioEngine, VAD integration
│   ├── Session/             # SessionManager, state machine
│   ├── Curriculum/          # CurriculumEngine, DocumentProcessor
│   ├── Persistence/         # Core Data, ManagedObjects
│   └── Telemetry/           # TelemetryEngine, MetricsSnapshot
├── Services/                # External service integrations
│   ├── STT/                 # Speech-to-text providers
│   │   ├── DeepgramSTTService.swift
│   │   ├── AssemblyAISTTService.swift
│   │   ├── GLMASRSTTService.swift        # Server-based
│   │   └── GLMASROnDeviceSTTService.swift # On-device
│   ├── TTS/                 # Text-to-speech providers
│   ├── LLM/                 # Language model providers
│   └── Protocols/           # Service protocols
├── UI/                      # SwiftUI views
│   ├── Session/             # Main conversation view
│   ├── Curriculum/          # Curriculum browser
│   ├── History/             # Session history
│   ├── Analytics/           # Metrics dashboard
│   └── Settings/            # Configuration & debug tools
└── VoiceLearn.xcdatamodeld  # Core Data model
```

---

## Key Files

| File | Purpose |
|------|---------|
| `Package.swift` | SPM package definition |
| `VoiceLearn/Core/Session/SessionManager.swift` | Main conversation orchestrator |
| `VoiceLearn/Core/Audio/AudioEngine.swift` | Audio capture & playback |
| `VoiceLearn/Services/STT/GLMASROnDeviceSTTService.swift` | On-device STT |
| `docs/VoiceLearn_TDD.md` | Technical design document |

---

## Development Workflows

### Make Code Changes

1. Edit files in VoiceLearn/
2. Build: `swift build` or Cmd+B in Xcode
3. Test: `swift test` or Cmd+U in Xcode
4. Commit when tests pass

### Run on Device

1. Connect iPhone (15 Pro or later recommended)
2. Select device in Xcode
3. Build and run (Cmd+R)
4. Grant microphone permission when prompted

### AI-Assisted Testing

With ios-simulator-mcp installed, Claude Code can:
- Boot simulators
- Install and launch apps
- Take screenshots
- Tap, swipe, type
- Verify UI state

See [AI_SIMULATOR_TESTING.md](AI_SIMULATOR_TESTING.md) for details.

---

## Troubleshooting

### Build fails with Core Data errors

Core Data model uses manual NSManagedObject subclasses:
```bash
# Ensure ManagedObjects directory exists
ls VoiceLearn/Core/Persistence/ManagedObjects/
```

### Build fails with llama.cpp errors

C++ interop requires Xcode (not SPM CLI for some operations):
```bash
# Open in Xcode instead
open Package.swift
```

### Tests fail in simulator

Some tests require iOS 18.0 simulator:
```bash
# Check available simulators
xcrun simctl list devices
```

---

## Documentation Index

| Document | Purpose |
|----------|---------|
| [VoiceLearn_TDD.md](VoiceLearn_TDD.md) | Full technical design |
| [SETUP.md](SETUP.md) | Detailed setup instructions |
| [TESTING.md](TESTING.md) | Testing guide |
| [GLM_ASR_ON_DEVICE_GUIDE.md](GLM_ASR_ON_DEVICE_GUIDE.md) | On-device STT setup |
| [GLM_ASR_NANO_2512.md](GLM_ASR_NANO_2512.md) | GLM-ASR model overview |
| [AI_SIMULATOR_TESTING.md](AI_SIMULATOR_TESTING.md) | AI testing workflow |
| [TASK_STATUS.md](TASK_STATUS.md) | Implementation status |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |
| [DEBUG_TESTING_UI.md](DEBUG_TESTING_UI.md) | Built-in debug tools |

---

## Next Steps

1. **Run the app** - Build and launch in simulator
2. **Explore the code** - Start with SessionManager.swift
3. **Read the TDD** - [VoiceLearn_TDD.md](VoiceLearn_TDD.md) has full architecture details
4. **Set up models** - For on-device STT, see [GLM_ASR_ON_DEVICE_GUIDE.md](GLM_ASR_ON_DEVICE_GUIDE.md)
5. **Configure APIs** - Add provider keys for cloud services

---

**Questions?** Open an issue on GitHub.
