# Daily Technology Scout Prompt for UnaMentis

**Purpose:** Identify new models, libraries, techniques, and resources relevant to the UnaMentis voice AI tutoring platform.

**Usage:** Run this prompt daily with an AI assistant (Claude, ChatGPT, Perplexity) that has web search capabilities. Review the output and create GitHub issues for items worth investigating.

---

## The Prompt

```
You are a technology scout for UnaMentis, a cross-platform voice AI tutoring system. Your job is to find NEW developments (within the last 7 days) that could improve the project.

## Project Context

UnaMentis is a voice AI tutoring platform with iOS, Android, and server components for 60-90+ minute voice-based AI tutoring sessions with these key requirements:
- Sub-500ms end-to-end latency for voice interactions
- Natural bidirectional conversation with interruption support
- Curriculum-driven learning with structured content
- Provider-agnostic architecture (swappable STT, TTS, LLM, VAD)
- 90+ minute session stability
- Cost optimization through smart provider selection

## Current Technology Stack

### Speech-to-Text (STT)
- Cloud: AssemblyAI Universal-Streaming, Deepgram Nova-2, Groq Whisper
- On-device iOS: GLM-ASR (ggml), Apple Speech
- On-device Android: Whisper.cpp, Vosk, Google Speech
- Looking for: Lower latency, better accuracy, on-device models, streaming support

### Text-to-Speech (TTS)
- Cloud: Deepgram Aura-2, ElevenLabs
- On-device iOS: Apple AVSpeechSynthesizer, Chatterbox (self-hosted)
- On-device Android: Android TextToSpeech, Piper TTS
- Looking for: More natural voices, lower latency, emotional expression, on-device options

### Large Language Models (LLM)
- Cloud: Anthropic Claude, OpenAI GPT-4
- On-device iOS: MLX-based models, llama.cpp
- On-device Android: llama.cpp (NDK), MLC LLM, MediaPipe LLM
- Looking for: Faster inference, better reasoning, lower cost, on-device viable models

### Voice Activity Detection (VAD)
- iOS: Silero VAD (Core ML)
- Android: Silero VAD (ONNX/TFLite), WebRTC VAD
- Looking for: Better turn-taking detection, semantic end-of-turn, lower latency

### Audio/Transport
- iOS: LiveKit Swift SDK, AVFoundation
- Android: LiveKit Android SDK, AudioRecord/AudioTrack, Oboe
- Looking for: Better echo cancellation, noise suppression, adaptive quality

### Educational Content
- Sources: OpenStax, MIT OpenCourseWare, Wikipedia
- Format: Custom UMCF (voice-optimized curriculum format)
- Looking for: New OER sources, curriculum APIs, educational standards updates

### iOS Development
- Swift 6.0 with strict concurrency
- SwiftUI for UI
- Core ML for on-device inference
- Looking for: Performance patterns, memory optimization, background audio handling

### Android Development
- Kotlin with Coroutines/Flow
- Jetpack Compose for UI
- TensorFlow Lite / NNAPI for on-device inference
- Looking for: Performance patterns, audio latency optimization, background services

### Server Infrastructure
- Python/aiohttp for Management API (port 8766)
- Next.js/React for web interface (port 3000)
- Curriculum import/export pipelines
- Looking for: Async patterns, WebSocket optimizations, caching strategies

## Search Categories

For each category, find NEW items from the past 7 days:

### 1. STT Models & Services
Search for:
- New speech recognition models (especially streaming/real-time)
- Whisper variants and optimizations
- On-device ASR models for iOS/Apple Silicon and Android/ARM
- AssemblyAI, Deepgram, Groq announcements
- Vosk, Whisper.cpp, sherpa-onnx updates
- Academic papers on low-latency STT

### 2. TTS Models & Services
Search for:
- New voice synthesis models
- Zero-shot voice cloning advances
- Emotional/expressive TTS
- On-device TTS for iOS and Android (Piper, Sherpa-ONNX)
- Deepgram, ElevenLabs, PlayHT, Cartesia announcements
- Open-source TTS models (Coqui successors, Chatterbox, etc.)

### 3. LLM Updates
Search for:
- New Claude, GPT model releases
- Small/efficient models suitable for on-device (Phi, Gemma, Qwen)
- Models optimized for conversation/tutoring
- MLX model releases and optimizations (iOS)
- llama.cpp updates for iOS and Android
- MLC LLM, MediaPipe LLM updates (Android)
- Reasoning model improvements

### 4. Voice AI & Conversational AI
Search for:
- Turn-taking and interruption handling techniques
- Voice activity detection improvements
- End-to-end voice conversation systems
- Latency optimization techniques
- Real-time voice AI frameworks

### 5. iOS Development
Search for:
- Swift concurrency patterns and updates
- Core ML optimizations
- AVFoundation improvements
- Memory management for long-running apps
- Background audio handling
- iOS 18/19 relevant APIs

### 6. Android Development
Search for:
- Kotlin Coroutines/Flow patterns and updates
- Jetpack Compose performance improvements
- TensorFlow Lite / NNAPI optimizations
- Android audio latency (Oboe, AAudio)
- Background service patterns for audio apps
- Android 14/15 relevant APIs
- MediaPipe updates

### 7. Server & Backend
Search for:
- Python async patterns (aiohttp, FastAPI)
- Next.js/React performance updates
- WebSocket optimization techniques
- Caching strategies (Redis, in-memory)
- Vector database updates (for curriculum search)
- API gateway patterns

### 8. Educational Technology
Search for:
- New OER (Open Educational Resources) sources
- Curriculum standards updates
- AI tutoring research papers
- Adaptive learning techniques
- Educational content APIs
- Spaced repetition/retrieval practice advances

### 9. Libraries & Frameworks
Search for:
- Swift packages for audio processing
- Kotlin/Android audio libraries
- WebRTC/LiveKit updates (both platforms)
- ML model conversion tools (Core ML, TFLite, ONNX)
- Vector database libraries
- Cross-platform caching and persistence

### 10. Cost Optimization
Search for:
- API pricing changes for STT/TTS/LLM providers
- New providers with competitive pricing
- Techniques to reduce token usage
- Caching strategies for AI responses
- Self-hosting cost comparisons

## Output Format

For each finding, provide:

```markdown
### [Category] Finding Title

**Source:** [URL]
**Date:** [Publication date]
**Relevance:** [High/Medium/Low]

**Summary:** 2-3 sentences describing what it is

**Why It Matters for UnaMentis:**
- Specific benefit 1
- Specific benefit 2

**Action Items:**
- [ ] Concrete next step to evaluate/integrate

**Risk/Considerations:**
- Any downsides or concerns
```

## Priority Signals

Flag as HIGH priority if:
- Directly improves latency (our key metric)
- Enables better on-device processing
- Significantly reduces costs
- Improves voice naturalness
- Has iOS/Swift OR Android/Kotlin support
- Works cross-platform (both mobile platforms)
- From a provider we already use

Flag as MEDIUM priority if:
- Interesting technique we could adapt
- Academic paper with practical applications
- New provider worth evaluating
- Curriculum source expansion
- Server-side optimization

Flag as LOW priority if:
- Requires significant architecture changes
- Only supports one platform we're not prioritizing
- Theoretical without implementation
- Minor incremental improvement

## Additional Context

The project is 100% AI-developed and emphasizes:
- Real implementations over mocks in testing
- Modular, protocol-based architecture
- Comprehensive observability and telemetry
- Cost transparency and optimization

Current pain points to solve:
1. On-device STT quality vs cloud latency tradeoff
2. TTS naturalness for extended educational content
3. Turn-taking detection to feel conversational
4. Memory stability over 90-minute sessions
5. Cost scaling for production usage

Now search the web for developments in each category from the past 7 days and report your findings.
```

---

## How to Use

### Option 1: Claude with Web Search
```bash
# Via Claude.ai with web search enabled
# Paste the prompt above
```

### Option 2: Perplexity
```bash
# Use Perplexity Pro for comprehensive web search
# Paste the prompt above
```

### Option 3: ChatGPT with Browsing
```bash
# Use ChatGPT Plus with browsing enabled
# Paste the prompt above
```

### Automation Ideas

1. **GitHub Actions scheduled workflow**: Run daily via API, create issues for high-priority items
2. **Slack integration**: Post daily digest to a #tech-scout channel
3. **Notion/Linear integration**: Auto-create backlog items

---

## Processing the Results

After running the scout:

1. **Review findings** for accuracy and relevance
2. **Create GitHub issues** for actionable items:
   ```bash
   gh issue create --title "Evaluate: [Finding Title]" \
     --body "Source: [URL]\n\nSummary: ...\n\nAction: ..." \
     --label "tech-scout,evaluation"
   ```
3. **Update docs/TECH_RADAR.md** if maintaining a technology radar
4. **Schedule deep-dives** for high-priority findings

---

## Supplementary Searches

For deeper investigation on specific topics:

### STT Deep Dive
```
Search for "streaming speech recognition 2025" OR "real-time ASR low latency" OR "whisper streaming inference" site:arxiv.org OR site:github.com
```

### TTS Deep Dive
```
Search for "neural TTS 2025" OR "zero-shot voice synthesis" OR "emotional speech synthesis" site:arxiv.org OR site:github.com
```

### iOS ML Deep Dive
```
Search for "Core ML 2025" OR "MLX iOS" OR "on-device LLM iPhone" site:developer.apple.com OR site:github.com/apple
```

### Android ML Deep Dive
```
Search for "TensorFlow Lite 2025" OR "MediaPipe LLM" OR "on-device LLM Android" OR "NNAPI optimization" site:developer.android.com OR site:github.com/google
```

### Server/Backend Deep Dive
```
Search for "aiohttp performance" OR "FastAPI async" OR "Next.js 14 optimization" OR "WebSocket scaling" site:github.com OR site:dev.to
```

### Educational AI Deep Dive
```
Search for "AI tutoring system" OR "conversational learning" OR "adaptive education AI" site:arxiv.org OR site:acm.org
```

### Cross-Platform Deep Dive
```
Search for "llama.cpp mobile" OR "whisper.cpp android ios" OR "on-device inference mobile" site:github.com
```
