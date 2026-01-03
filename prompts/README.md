# UnaMentis Prompts

This directory contains prompts for AI-assisted workflows.

## Technology Scouting

| File | Purpose | Frequency |
|------|---------|-----------|
| [daily-tech-scout.md](daily-tech-scout.md) | Comprehensive technology scouting prompt | Weekly |
| [tech-scout-quick.md](tech-scout-quick.md) | Quick daily check prompt + RSS feeds | Daily |
| [FINDINGS_TEMPLATE.md](FINDINGS_TEMPLATE.md) | Template for documenting findings | Per scout run |

### Workflow

1. **Daily (2-3 min):** Run the quick scout or check RSS feeds
2. **Weekly (15-20 min):** Run the full scout prompt
3. **After each run:** Create GitHub issues for actionable items

### Recommended Tools

- **Perplexity Pro** - Best for comprehensive web search
- **Claude with web search** - Good for analysis and recommendations
- **Feedly/Inoreader** - For RSS feed monitoring
- **GitHub Actions** - For automation (see below)

### Automation (Optional)

To automate daily scouting with Claude API:

```python
# scripts/tech_scout.py
import anthropic
from datetime import datetime

client = anthropic.Anthropic()

with open("prompts/daily-tech-scout.md") as f:
    prompt = f.read()

# Extract just the prompt section
# ... implementation details ...

message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=4096,
    messages=[{"role": "user", "content": prompt}]
)

# Save to findings/YYYY-MM-DD.md
# ... implementation details ...
```

### Categories Monitored

**AI Services:**
- **STT:** AssemblyAI, Deepgram, Groq, Whisper, Vosk, Sherpa-ONNX
- **TTS:** Deepgram Aura, ElevenLabs, Chatterbox, Piper
- **LLM:** Claude, GPT, Llama, Gemma, Phi, Qwen
- **VAD:** Silero, WebRTC VAD, turn-taking detection

**Platforms:**
- **iOS:** Swift, Core ML, MLX, AVFoundation
- **Android:** Kotlin, TensorFlow Lite, NNAPI, MediaPipe, Oboe
- **Server:** Python/aiohttp, Next.js/React, WebSockets

**Other:**
- **Educational:** OER sources, curriculum standards, AI tutoring research
- **Infrastructure:** WebRTC, LiveKit, caching, vector databases
