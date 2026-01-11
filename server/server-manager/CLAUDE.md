# UnaMentis Server Manager (USM)

A macOS menu bar application for managing UnaMentis server components, with an HTTP API for programmatic control by AI agents.

## Purpose

USM provides both visual and programmatic control over all UnaMentis services:

1. **AI Agent API** - HTTP API on port 8767 for programmatic service control
2. **Visual Monitoring** - Menu bar UI showing status, CPU, and memory usage
3. **Bulk Operations** - Start/stop/restart all services with one action

## HTTP API (Port 8767)

**AI agents MUST use this API for all service control operations.** Never use bash commands like pkill.

### Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/health` | GET | API health check |
| `/api/services` | GET | List all services with status, PID, CPU, memory |
| `/api/services/{id}/start` | POST | Start a service |
| `/api/services/{id}/stop` | POST | Stop a service |
| `/api/services/{id}/restart` | POST | Restart a service |
| `/api/services/start-all` | POST | Start all stopped services |
| `/api/services/stop-all` | POST | Stop all running services |
| `/api/services/restart-all` | POST | Restart all services |

### Example Usage

```bash
# Check API is running
curl -s http://localhost:8767/api/health

# List all services
curl -s http://localhost:8767/api/services | python3 -m json.tool

# Restart management server after code changes
curl -X POST http://localhost:8767/api/services/management-api/restart

# Start all services
curl -X POST http://localhost:8767/api/services/start-all

# Stop everything
curl -X POST http://localhost:8767/api/services/stop-all
```

### Response Format

```json
{
  "services": [
    {
      "id": "management-api",
      "name": "Management API",
      "status": "running",
      "port": 8766,
      "pid": 12345,
      "cpu_percent": 2.5,
      "memory_mb": 48
    }
  ],
  "total": 6,
  "running": 5,
  "stopped": 1
}
```

## Managed Services

| Service ID | Display Name | Port |
|------------|--------------|------|
| `postgresql` | PostgreSQL | 5432 |
| `log-server` | Log Server | 8765 |
| `management-api` | Management API | 8766 |
| `web-server` | Operations Console | 3000 |
| `web-client` | Web Client | 3001 |
| `ollama` | Ollama | 11434 |

## Architecture

```
server/server-manager/
├── USMXcode/              # Xcode workspace and project
│   ├── USM.xcworkspace/   # Open this in Xcode
│   ├── USM/               # App shell
│   │   └── USMApp.swift   # ServiceManager + APIServer + UI
│   └── USMPackage/        # SPM package for features
├── MACOS26_MENUBAR_TDD.md # Technical design document
├── MACOS_26_MENUBAR_SPEC.md # Menu bar app specification
└── SPEC.md                # Implementation specification
```

## Key Components

**USMApp.swift** contains:
- `APIServer` - HTTP server on port 8767 for AI agent access
- `ServiceManager` - Manages service lifecycle (start/stop/restart)
- `PopoverContent` - Menu bar popover UI
- `ServiceRow` - Individual service status display

## Building and Running

Using XcodeBuildMCP:
```
mcp__XcodeBuildMCP__session-set-defaults({
  workspacePath: "/Users/ramerman/dev/unamentis/server/server-manager/USMXcode/USM.xcworkspace",
  scheme: "USM"
})
mcp__XcodeBuildMCP__build_macos()
mcp__XcodeBuildMCP__launch_mac_app({ appPath: "..." })
```

Or manually:
```bash
cd server/server-manager/USMXcode
open USM.xcworkspace
# Build with Cmd+B, Run with Cmd+R
```

## Important Notes

1. **USM must be running** for the API to work
2. The API starts automatically when USM launches
3. API runs on port 8767, management server on 8766
4. All service IDs must match exactly (case-sensitive)
5. Restart operations wait for services to fully stop before starting
