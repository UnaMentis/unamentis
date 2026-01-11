# UnaMentis Web Management Interface

A next-generation web management dashboard for monitoring and configuring UnaMentis services.

## Features

- **Real-time Dashboard** - Live stats, server health, and client monitoring
- **Performance Metrics** - Latency tracking, cost breakdown, session analytics
- **Live Logs** - Real-time log streaming with filtering and search
- **Remote Clients** - Monitor connected iOS devices
- **Server Management** - Health checks for Ollama, Whisper, Piper, etc.
- **Model Discovery** - View available LLM, STT, and TTS models
- **TTS Caching** - Global audio cache with cross-user sharing
- **Session Management** - Per-user state with voice config and playback tracking
- **Audio Streaming** - Real-time WebSocket audio coordination
- **Scheduled Deployments** - Pre-generate curriculum audio before deployment

## Quick Start

```bash
cd server/management
./run.sh
```

Then open http://localhost:8766 in your browser.

## Configuration

Environment variables:
- `UNAMENTIS_MGMT_HOST` - Host to bind to (default: `0.0.0.0`)
- `UNAMENTIS_MGMT_PORT` - Port to listen on (default: `8766`)

Example:
```bash
UNAMENTIS_MGMT_PORT=9000 ./run.sh
```

## Remote Testing via Tunnel

To access the dashboard remotely while developing, use a tunnel service:

### Option 1: ngrok (Recommended)

```bash
# Install ngrok
brew install ngrok  # macOS
# or download from https://ngrok.com/download

# Start the tunnel
ngrok http 8766
```

This will give you a public URL like `https://abc123.ngrok.io`

### Option 2: Cloudflare Tunnel

```bash
# Install cloudflared
brew install cloudflared  # macOS
# or download from https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/

# Quick tunnel (no account needed)
cloudflared tunnel --url http://localhost:8766
```

### Option 3: localtunnel

```bash
# Install
npm install -g localtunnel

# Start tunnel
lt --port 8766
```

## API Endpoints

### Core Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Dashboard UI |
| `/health` | GET | Health check |
| `/ws` | WS | WebSocket for real-time updates |
| `/api/stats` | GET | Dashboard statistics |
| `/api/logs` | GET | Get logs with filtering |
| `/api/logs` | POST | Receive log entries |
| `/api/logs` | DELETE | Clear all logs |
| `/api/metrics` | GET | Get metrics history |
| `/api/metrics` | POST | Receive metrics snapshot |
| `/api/clients` | GET | List remote clients |
| `/api/clients/heartbeat` | POST | Client heartbeat |
| `/api/servers` | GET | List servers with health |
| `/api/servers` | POST | Add a server |
| `/api/servers/{id}` | DELETE | Remove a server |
| `/api/models` | GET | List available models |

### TTS Caching Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/tts` | POST | Generate TTS audio (cache-first) |
| `/api/tts/cache` | GET | Check cache for audio |
| `/api/tts/cache` | PUT | Add audio to cache (testing) |
| `/api/tts/cache/stats` | GET | Cache statistics |
| `/api/tts/cache/coverage` | POST | Check cache coverage for segments |
| `/api/tts/prefetch` | POST | Prefetch upcoming segments |

### Scheduled Deployment Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/deployments` | GET | List all deployments |
| `/api/deployments` | POST | Schedule new deployment |
| `/api/deployments/{id}` | GET | Get deployment status |
| `/api/deployments/{id}` | DELETE | Cancel deployment |
| `/api/deployments/{id}/start` | POST | Manually start generation |
| `/api/deployments/{id}/pause` | POST | Pause generation |
| `/api/deployments/{id}/resume` | POST | Resume generation |
| `/api/deployments/{id}/cache` | GET | Check cache coverage |

### Audio WebSocket

| Endpoint | Protocol | Description |
|----------|----------|-------------|
| `/ws/audio` | WebSocket | Real-time audio streaming |

Connect with `?session_id=xxx` or `?user_id=xxx`. See Audio WebSocket Protocol below.

## TTS Caching Architecture

The TTS caching system provides cross-user audio sharing with priority-based generation.

### Key Components

- **TTSCache** - Global audio cache with user-agnostic keys
- **TTSResourcePool** - Priority-based generation with concurrency limits
- **SessionCacheIntegration** - Bridge between user sessions and global cache
- **ScheduledDeploymentManager** - Pre-generation for scheduled deployments

### Cache Key Design

Cache keys are user-agnostic: `hash(text + voice_id + provider + speed)`. Same text with same voice config produces the same cache entry for ALL users.

```
User A (voice=nova) requests "Welcome to the lesson":
  1. Cache MISS → Generate → Store → Return

User B (voice=nova) requests same segment:
  1. Cache HIT → Return immediately (0ms TTS latency)
```

### Priority Levels

| Priority | Value | Semaphore | Use Case |
|----------|-------|-----------|----------|
| LIVE | 10 | 7 concurrent | User actively waiting |
| PREFETCH | 5 | 3 concurrent | Near-future segments |
| SCHEDULED | 1 | 3 concurrent | Background pre-generation |

## Audio WebSocket Protocol

Connect to `/ws/audio?session_id=xxx` or `/ws/audio?user_id=xxx`.

### Client → Server Messages

**Request Audio:**
```json
{
    "type": "request_audio",
    "segment_index": 0,
    "curriculum_id": "...",
    "topic_id": "..."
}
```

**Sync (Heartbeat):**
```json
{
    "type": "sync",
    "segment_index": 5,
    "offset_ms": 1500,
    "is_playing": true
}
```

**Barge-in (Interruption):**
```json
{
    "type": "barge_in",
    "segment_index": 5,
    "offset_ms": 1500,
    "utterance": "wait, what does that mean?"
}
```

**Voice Config Update:**
```json
{
    "type": "voice_config",
    "voice_id": "nova",
    "tts_provider": "vibevoice",
    "speed": 1.0
}
```

### Server → Client Messages

**Audio Response:**
```json
{
    "type": "audio",
    "segment_index": 0,
    "audio_base64": "...",
    "duration_seconds": 2.5,
    "cache_hit": true,
    "total_segments": 50
}
```

**Error:**
```json
{
    "type": "error",
    "error": "No segments found for curriculum/topic"
}
```

## iOS Integration

Configure the iOS app to send logs and metrics to this server:

```swift
// In RemoteLogHandler.swift, set the server URL:
let serverURL = "http://YOUR_SERVER_IP:8766/api/logs"

// For metrics, configure TelemetryEngine to export to:
let metricsURL = "http://YOUR_SERVER_IP:8766/api/metrics"
```

### Client Headers

When sending logs/metrics, include these headers:
- `X-Client-ID`: Unique device identifier
- `X-Client-Name`: Device name (e.g., "iPhone 15 Pro")

### Log Entry Format

```json
{
    "timestamp": "2025-12-19T10:30:00.000Z",
    "level": "INFO",
    "label": "com.unamentis.audio",
    "message": "Audio engine started",
    "file": "AudioEngine.swift",
    "function": "start()",
    "line": 45,
    "metadata": {
        "sampleRate": 16000
    }
}
```

### Metrics Snapshot Format

```json
{
    "timestamp": "2025-12-19T10:30:00.000Z",
    "sessionDuration": 120.5,
    "turnsTotal": 15,
    "interruptions": 2,
    "sttLatencyMedian": 250,
    "sttLatencyP99": 450,
    "llmTTFTMedian": 380,
    "llmTTFTP99": 650,
    "ttsTTFBMedian": 180,
    "ttsTTFBP99": 320,
    "e2eLatencyMedian": 850,
    "e2eLatencyP99": 1200,
    "sttCost": 0.0012,
    "ttsCost": 0.0008,
    "llmCost": 0.0045,
    "totalCost": 0.0065,
    "thermalThrottleEvents": 0,
    "networkDegradations": 1
}
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Web Browser                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │              Dashboard UI                        │   │
│  │  • Real-time updates via WebSocket              │   │
│  │  • Chart.js for visualizations                  │   │
│  │  • TailwindCSS for styling                      │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────────┘
                      │ HTTP/WebSocket
                      ▼
┌─────────────────────────────────────────────────────────┐
│              Management Server (Python/aiohttp)         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │   REST API  │  │  WebSocket  │  │   Health    │    │
│  │  Endpoints  │  │   Handler   │  │  Checker    │    │
│  └─────────────┘  └─────────────┘  └─────────────┘    │
│                         │                               │
│  ┌──────────────────────┴──────────────────────────┐   │
│  │              In-Memory State                     │   │
│  │  • Logs (deque, max 10,000)                     │   │
│  │  • Metrics (deque, max 1,000)                   │   │
│  │  • Clients (dict)                               │   │
│  │  • Servers (dict)                               │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │              TTS Caching System                   │   │
│  │  ┌─────────────┐  ┌─────────────────────────┐   │   │
│  │  │  TTSCache   │  │  TTSResourcePool        │   │   │
│  │  │  (Global)   │  │  LIVE: 7 concurrent     │   │   │
│  │  │             │  │  BACKGROUND: 3 concurrent│   │   │
│  │  └─────────────┘  └─────────────────────────┘   │   │
│  │  ┌─────────────────────┐  ┌─────────────────┐   │   │
│  │  │SessionCacheIntegr.  │  │DeploymentManager│   │   │
│  │  │(User→Cache Bridge)  │  │(Pre-generation) │   │   │
│  │  └─────────────────────┘  └─────────────────┘   │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Session Management                   │   │
│  │  UserSession: voice_config, playback_state       │   │
│  │  Cross-device resume via server-side state       │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────────┘
                      │ HTTP/WebSocket
                      ▼
┌─────────────────────────────────────────────────────────┐
│                   iOS Clients                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  iPhone 1   │  │  iPhone 2   │  │  Simulator  │    │
│  └─────────────┘  └─────────────┘  └─────────────┘    │
│  Cross-user cache sharing: same voice = same audio     │
└─────────────────────────────────────────────────────────┘
                      │ HTTP
                      ▼
┌─────────────────────────────────────────────────────────┐
│                 Backend Servers                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │   Ollama    │  │   Whisper   │  │    Piper    │    │
│  │   (LLM)     │  │   (STT)     │  │   (TTS)     │    │
│  └─────────────┘  └─────────────┘  └─────────────┘    │
│  ┌─────────────┐  ┌─────────────┐                      │
│  │ Chatterbox  │  │  VibeVoice  │                      │
│  │   (TTS)     │  │   (TTS)     │                      │
│  └─────────────┘  └─────────────┘                      │
└─────────────────────────────────────────────────────────┘
```

## Development

The server is built with:
- **Python 3.9+** with aiohttp for async HTTP/WebSocket
- **TailwindCSS** (via CDN) for styling
- **Chart.js** for data visualization
- **Vanilla JavaScript** for frontend logic

To modify the UI, edit:
- `static/index.html` - HTML structure and TailwindCSS styles
- `static/app.js` - Frontend JavaScript logic

To modify the API, edit:
- `server.py` - Backend Python server
- `tts_api.py` - TTS generation and caching endpoints
- `deployment_api.py` - Scheduled deployment endpoints
- `audio_ws.py` - Audio WebSocket handler
- `session_cache_integration.py` - Session-cache bridge

### Key Files

| File | Purpose |
|------|---------|
| `tts_cache/cache.py` | Global TTS cache with disk persistence |
| `tts_cache/resource_pool.py` | Priority-based TTS generation |
| `tts_cache/prefetcher.py` | Background segment prefetching |
| `fov_context/session.py` | UserSession, PlaybackState, UserVoiceConfig |
| `session_cache_integration.py` | Bridge between sessions and cache |
| `deployment_api.py` | Scheduled pre-generation manager |
| `audio_ws.py` | Real-time audio WebSocket |

### Running Tests

```bash
# Run all management server tests
cd server/management
python -m pytest tests/ tts_cache/tests/ -v

# Run specific test file
python -m pytest tests/test_session_integration.py -v
```
