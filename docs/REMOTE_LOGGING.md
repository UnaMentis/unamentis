# UnaMentis Remote Logging Infrastructure

This document describes the remote logging system that enables real-time log viewing from iOS simulator and physical devices.

## Overview

The remote logging infrastructure consists of:
1. **RemoteLogHandler** - Swift log handler that sends logs over HTTP
2. **log_server.py** - Python server with web interface for viewing logs
3. **launchd service** - Background service that runs automatically

## Quick Start

### One-Time Setup

Install the log server as a background service:

```bash
./scripts/setup_log_service.sh install
```

This will:
- Install the service to run automatically at login
- Start the log server immediately
- Show you the web interface URL and device configuration IP

### Viewing Logs

**Web Interface (recommended):**
- Open http://localhost:8765/ in any browser
- Features:
  - Real-time log updates (polls every 500ms)
  - Filter by log level (Debug, Info, Warning, Error)
  - Search messages
  - Filter by label/subsystem
  - Download logs as JSON
  - Error/warning counters

**Terminal:**
```bash
# Run interactively (for debugging the server itself)
python3 scripts/log_server.py
```

## Architecture

```
┌─────────────────────┐     HTTP POST      ┌──────────────────────┐
│   iOS App           │ ─────────────────► │   Log Server         │
│   (Simulator/Device)│     /log           │   (Python + Web UI)  │
│                     │                    │                      │
│  RemoteLogHandler   │                    │  - Receives logs     │
│  + MultiplexHandler │                    │  - Web dashboard     │
└─────────────────────┘                    │  - Terminal output   │
                                           │  - JSON API          │
                                           └──────────────────────┘
```

## Configuration

### For Simulator
Logs work automatically - localhost:8765 is used by default.

### For Physical Device
1. Run `./scripts/setup_log_service.sh status` to see your Mac's IP
2. In the app: Settings > Debug & Testing > Remote Log Server IP
3. Enter your Mac's IP address (e.g., `192.168.1.100`)
4. Ensure device and Mac are on the same network

## Service Management

```bash
# Check if service is running
./scripts/setup_log_service.sh status

# Restart the service
./scripts/setup_log_service.sh restart

# View service logs (stdout/stderr)
./scripts/setup_log_service.sh logs

# Uninstall the service
./scripts/setup_log_service.sh uninstall
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Web interface |
| `/log` | POST | Receive log entry (JSON) |
| `/logs` | GET | Get all logs as JSON array |
| `/clear` | POST | Clear log buffer |
| `/health` | GET | Health check (returns "OK") |

## Log Entry Format

```json
{
  "timestamp": "2025-12-17T04:58:10.405Z",
  "level": "INFO",
  "label": "com.unamentis.telemetry",
  "message": "TelemetryEngine initialized",
  "file": "TelemetryEngine.swift",
  "function": "init()",
  "line": 172,
  "metadata": {"key": "value"}
}
```

## Files

| File | Description |
|------|-------------|
| `UnaMentis/Core/Logging/RemoteLogHandler.swift` | Swift log handler |
| `scripts/log_server.py` | Python log server with web UI |
| `scripts/setup_log_service.sh` | Service installer script |
| `scripts/com.unamentis.logserver.plist` | launchd template |

## Troubleshooting

### Logs not appearing
1. Check service status: `./scripts/setup_log_service.sh status`
2. Verify port is listening: `lsof -i :8765`
3. Check service logs: `./scripts/setup_log_service.sh logs`
4. For device: verify IP address is correct and devices are on same network

### Service won't start
1. Check for port conflicts: `lsof -i :8765`
2. Restart the log server via USM: `/service restart log-server`
3. Reinstall: `./scripts/setup_log_service.sh uninstall && ./scripts/setup_log_service.sh install`

### Web interface not loading
1. Verify server is running: `curl http://localhost:8765/health`
2. Check browser console for errors
3. Try a different browser

## Disabling Remote Logging

In the app's Settings > Debug & Testing, toggle "Remote Logging" off.

Or programmatically:
```swift
RemoteLogging.disable()
```

## Buffer Limits

- In-memory buffer: 5000 log entries
- Web UI displays: last 500 entries (filtered)
- Logs are not persisted to disk by default

To save logs to file:
```bash
python3 scripts/log_server.py --output /path/to/logs.jsonl
```
