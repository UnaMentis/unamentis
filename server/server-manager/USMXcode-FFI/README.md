# USM-FFI - UnaMentis Server Manager (Rust-based)

A macOS menu bar application for managing UnaMentis services, using the Rust-based USM Core for real-time service management via HTTP API and WebSocket events.

## Overview

USM-FFI is a parallel implementation of the USM menu bar app that connects to USM Core (Rust) instead of running its own service manager. This provides:

- **Real-time updates** via WebSocket (not 5-second polling)
- **Shared service management** with USM Core
- **Live metrics** (CPU%, Memory) for all running services
- **Development mode** toggle for dev-only services

## Architecture

```
┌─────────────────────┐     HTTP API      ┌──────────────────┐
│     USM-FFI App     │◄─────────────────►│    USM Core      │
│   (Swift/SwiftUI)   │                   │     (Rust)       │
│                     │◄─────────────────►│   Port 8787      │
│   Menu Bar UI       │    WebSocket      │                  │
└─────────────────────┘                   └──────────────────┘
```

### Key Components

| File | Purpose |
|------|---------|
| `USMFFI/Core/USMCoreManager.swift` | Main service manager, HTTP API client |
| `USMFFI/Core/WebSocketClient.swift` | Real-time event streaming |
| `USMFFI/Models/Service.swift` | Service models and event decoding |
| `USMFFI/Views/PopoverContent.swift` | Main menu bar popover UI |
| `USMFFI/Views/ServiceRow.swift` | Individual service row component |

## Services

The app manages these services (configured in `server/usm-core/config/services.toml`):

| Service | Port | Category |
|---------|------|----------|
| PostgreSQL | 5432 | Core |
| Log Server | 8765 | Core |
| Management API | 8766 | Core |
| Operations Console | 3000 | Core |
| Web Client | 3001 | Core |
| Ollama | 11434 | Core |
| Feature Flags | 3063 | Development |

## Development

### Prerequisites

- macOS 15.4+
- Xcode 16+
- Rust toolchain (for USM Core)
- USM Core running on port 8787

### Building

1. Start USM Core:
   ```bash
   cd server/usm-core
   cargo build --release
   PROJECT_ROOT=/path/to/unamentis ./target/release/usm server --port 8787
   ```

2. Build the app:
   ```bash
   xcodebuild -workspace USMFFI.xcworkspace -scheme USMFFI build
   ```

Or use XcodeBuildMCP:
```
mcp__XcodeBuildMCP__session-set-defaults({
  workspacePath: "server/server-manager/USMXcode-FFI/USMFFI.xcworkspace",
  scheme: "USMFFI"
})
mcp__XcodeBuildMCP__build_run_macos()
```

### Project Structure

```
USMXcode-FFI/
├── USMFFI.xcworkspace/          # Open this in Xcode
├── USMFFI.xcodeproj/            # App project
├── USMFFI/                      # Main app code
│   ├── Core/                    # USMCoreManager, WebSocketClient
│   ├── Models/                  # Service, ServiceEvent
│   ├── Views/                   # PopoverContent, ServiceRow
│   └── USMFFIApp.swift          # App entry point
├── Config/                      # Build configuration
│   ├── Shared.xcconfig          # Bundle ID, versions
│   ├── Debug.xcconfig
│   └── Release.xcconfig
└── Assets.xcassets/             # App icons
```

## Configuration

### Bundle ID

`com.unamentis.server-manager-ffi` (distinct from original USM app)

### Ports

- **USM Core API**: `http://127.0.0.1:8787`
- **WebSocket**: `ws://127.0.0.1:8787/ws`

### Dev Mode

Toggle "Dev Mode" in the menu bar to show/hide development services (Feature Flags, etc.)

## Testing

Run Swift tests:
```bash
xcodebuild test -workspace USMFFI.xcworkspace -scheme USMFFI -destination 'platform=macOS'
```

## Comparison with Original USM

| Feature | USM (Original) | USM-FFI |
|---------|---------------|---------|
| Backend | Self-contained Swift | USM Core (Rust) |
| Updates | 5-second polling | WebSocket real-time |
| Port | 8767 | 8787 (USM Core) |
| Bundle ID | `com.unamentis.server-manager2` | `com.unamentis.server-manager-ffi` |
| Can run together | Yes | Yes |

## Related Documentation

- [USM Core](../../usm-core/README.md) - Rust service manager
- [Original USM](../USMXcode/README.md) - Legacy Swift implementation
