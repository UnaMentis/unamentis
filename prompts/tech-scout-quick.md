# Quick Daily Tech Scout

**For rapid daily checks. Use the full prompt in `daily-tech-scout.md` for comprehensive weekly reviews.**

---

## Quick Scout Prompt

```
Find NEW announcements from the past 24-48 hours relevant to a cross-platform voice AI tutoring system (iOS, Android, server):

MUST SEARCH:
1. "Anthropic Claude" OR "OpenAI GPT" new model announcement
2. "Deepgram" OR "AssemblyAI" OR "ElevenLabs" new feature
3. "whisper" OR "speech recognition" breakthrough
4. "text to speech" OR "voice synthesis" new model
5. "iOS" OR "Swift" OR "Core ML" Apple announcement
6. "Android" OR "Kotlin" OR "TensorFlow Lite" Google announcement
7. "MLX" OR "llama.cpp" OR "MLC LLM" update
8. "Next.js" OR "aiohttp" OR "FastAPI" server update

CONTEXT: We need sub-500ms latency, on-device preferred, iOS Swift + Android Kotlin + Python/Next.js server.

OUTPUT: Only report if something genuinely new and impactful. No findings is a valid response.

Format each finding as:
- **What:** One sentence
- **Platform:** iOS / Android / Server / Cross-platform
- **Link:** URL
- **Priority:** High/Medium/Low
- **Action:** What to do next
```

---

## Provider-Specific Checks

### STT Providers
```
Check for updates in the past 48 hours:
- AssemblyAI blog: https://www.assemblyai.com/blog/
- Deepgram blog: https://deepgram.com/blog/
- Groq announcements: https://groq.com/news/
- OpenAI Whisper releases: https://github.com/openai/whisper/releases
- Sherpa-ONNX releases: https://github.com/k2-fsa/sherpa-onnx/releases
```

### TTS Providers
```
Check for updates in the past 48 hours:
- Deepgram TTS: https://deepgram.com/blog/
- ElevenLabs: https://elevenlabs.io/blog/
- PlayHT: https://play.ht/blog/
- Cartesia: https://cartesia.ai/blog/
- Piper TTS: https://github.com/rhasspy/piper/releases
```

### LLM Providers
```
Check for updates in the past 48 hours:
- Anthropic: https://www.anthropic.com/news
- OpenAI: https://openai.com/blog/
- Meta Llama: https://ai.meta.com/blog/
- Google (Gemma): https://ai.google.dev/
```

### iOS/Swift
```
Check for updates:
- Swift forums: https://forums.swift.org/
- Apple ML: https://machinelearning.apple.com/
- MLX releases: https://github.com/ml-explore/mlx/releases
```

### Android/Kotlin
```
Check for updates:
- Android Developers blog: https://android-developers.googleblog.com/
- Kotlin blog: https://blog.jetbrains.com/kotlin/
- TensorFlow Lite: https://github.com/tensorflow/tensorflow/releases
- MediaPipe: https://github.com/google/mediapipe/releases
- MLC LLM: https://github.com/mlc-ai/mlc-llm/releases
```

### Server/Backend
```
Check for updates:
- Next.js releases: https://github.com/vercel/next.js/releases
- aiohttp releases: https://github.com/aio-libs/aiohttp/releases
- FastAPI releases: https://github.com/tiangolo/fastapi/releases
```

---

## RSS Feeds to Monitor

```xml
<!-- Add these to your RSS reader for passive monitoring -->

<!-- AI Providers -->
https://www.assemblyai.com/blog/rss/
https://deepgram.com/blog/feed/
https://www.anthropic.com/news/rss.xml
https://openai.com/blog/rss/
https://huggingface.co/blog/feed.xml

<!-- Academic -->
https://arxiv.org/rss/cs.CL  <!-- Computational Linguistics -->
https://arxiv.org/rss/cs.SD  <!-- Sound/Audio -->
https://arxiv.org/rss/eess.AS <!-- Audio/Speech Processing -->

<!-- Platform-Specific -->
https://developer.apple.com/news/rss/news.rss
https://android-developers.googleblog.com/feeds/posts/default
https://blog.jetbrains.com/kotlin/feed/

<!-- Server/Web -->
https://nextjs.org/blog/rss.xml
```

---

## Hacker News Monitoring

```
Search HN for past 24 hours:
https://hn.algolia.com/?dateRange=last24h&query=speech+recognition
https://hn.algolia.com/?dateRange=last24h&query=text+to+speech
https://hn.algolia.com/?dateRange=last24h&query=voice+AI
https://hn.algolia.com/?dateRange=last24h&query=whisper
https://hn.algolia.com/?dateRange=last24h&query=llama+ios
https://hn.algolia.com/?dateRange=last24h&query=llama+android
https://hn.algolia.com/?dateRange=last24h&query=on-device+LLM
https://hn.algolia.com/?dateRange=last24h&query=tensorflow+lite
```

---

## GitHub Monitoring

Star and watch these repos for releases:

### Cross-Platform / ML
- `openai/whisper`
- `ggerganov/llama.cpp`
- `ggerganov/whisper.cpp`
- `k2-fsa/sherpa-onnx`
- `snakers4/silero-vad`
- `resemble-ai/chatterbox`
- `rhasspy/piper`

### iOS-Specific
- `ml-explore/mlx`
- `ml-explore/mlx-examples`
- `livekit/client-sdk-swift`

### Android-Specific
- `livekit/client-sdk-android`
- `mlc-ai/mlc-llm`
- `google/mediapipe`
- `alphacep/vosk-android`
- `huggingface/tflite-android-transformers`

### Server/Backend
- `vercel/next.js`
- `aio-libs/aiohttp`
- `tiangolo/fastapi`
