# VoiceLearn Web Management Interface

A next-generation web management dashboard for monitoring and configuring VoiceLearn services.

## Features

- **Real-time Dashboard** - Live stats, server health, and client monitoring
- **Performance Metrics** - Latency tracking, cost breakdown, session analytics
- **Live Logs** - Real-time log streaming with filtering and search
- **Remote Clients** - Monitor connected iOS devices
- **Server Management** - Health checks for Ollama, Whisper, Piper, etc.
- **Model Discovery** - View available LLM, STT, and TTS models

## Quick Start

```bash
cd server/management
./run.sh
```

Then open http://localhost:8766 in your browser.

## Configuration

Environment variables:
- `VOICELEARN_MGMT_HOST` - Host to bind to (default: `0.0.0.0`)
- `VOICELEARN_MGMT_PORT` - Port to listen on (default: `8766`)

Example:
```bash
VOICELEARN_MGMT_PORT=9000 ./run.sh
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
    "label": "com.voicelearn.audio",
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
└─────────────────────┬───────────────────────────────────┘
                      │ HTTP
                      ▼
┌─────────────────────────────────────────────────────────┐
│                   iOS Clients                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  iPhone 1   │  │  iPhone 2   │  │  Simulator  │    │
│  └─────────────┘  └─────────────┘  └─────────────┘    │
└─────────────────────────────────────────────────────────┘
                      │ HTTP
                      ▼
┌─────────────────────────────────────────────────────────┐
│                 Backend Servers                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │   Ollama    │  │   Whisper   │  │    Piper    │    │
│  │   (LLM)     │  │   (STT)     │  │   (TTS)     │    │
│  └─────────────┘  └─────────────┘  └─────────────┘    │
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
