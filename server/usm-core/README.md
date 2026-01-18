# USM Core - Cross-Platform Service Manager

**USM Core** is a high-performance, cross-platform service management library written in Rust. It provides the foundation for managing development services across macOS, Linux, and web platforms with native UI wrappers for each.

## Why Rust?

| Requirement | How Rust Delivers |
|-------------|-------------------|
| **Months of uptime** | No garbage collector, deterministic memory, no "stop the world" pauses |
| **Strongly typed** | Compile-time type checking, no null pointers, Result/Option types |
| **Very performant** | Zero-cost abstractions, compiles to native, predictable latency |
| **Cross-platform** | Single codebase compiles to macOS, Linux, WASM |
| **Library-friendly** | Produces .dylib (macOS), .so (Linux), C FFI for Swift/Python |
| **Async I/O** | Tokio runtime handles thousands of connections efficiently |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      USM Core (Rust)                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Service Registry        Process Monitor            │   │
│  │  - Template definitions  - Platform backends        │   │
│  │  - Instance lifecycle    - macOS: libproc/sysinfo  │   │
│  │  - Health tracking       - Linux: procfs           │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  HTTP/WebSocket Server   Event System               │   │
│  │  - REST API (Axum)       - Pub/Sub for UI updates  │   │
│  │  - WebSocket push        - Service state changes   │   │
│  │  - Real-time metrics     - <50ms latency target    │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Resource Monitor        Configuration             │   │
│  │  - CPU/Memory per proc   - TOML config files      │   │
│  │  - System-wide metrics   - Hot-reload support     │   │
│  │  - Load averages         - Runtime reconfiguration │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
              │              │              │
              ▼              ▼              ▼
     ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
     │ macOS Swift  │ │ Linux TUI/   │ │ Web Dashboard│
     │ Menu Bar App │ │ GTK App      │ │ (HTTP/WS)    │
     │ (C FFI)      │ │ (C FFI)      │ │ (REST API)   │
     └──────────────┘ └──────────────┘ └──────────────┘
```

## Core Concepts

### Templates + Instances Model

Services are defined as **templates** (blueprints) that can spawn multiple **instances** with different ports, configs, and versions.

```
Template: "management-api"
├── Default port: 8766
├── Start command: python3 {working_dir}/server.py --port {port}
└── Health endpoint: http://localhost:{port}/health

Instances:
├── mgmt-api-v1     (Port 8766, Version 1.0, Production)
├── mgmt-api-v2     (Port 8767, Version 2.0-beta, Testing)
└── mgmt-api-dev    (Port 8768, feature/xyz branch, Development)
```

### Variable Substitution

Commands support these placeholders:
- `{port}` - Instance port number
- `{working_dir}` - Working directory path
- `{config}` - Configuration file path
- `{pid}` - Process ID (for stop commands)

## Project Structure

```
server/usm-core/
├── Cargo.toml                    # Workspace manifest
├── Cargo.lock                    # Locked dependencies
├── config/
│   └── services.toml             # Service definitions
├── crates/
│   ├── usm-core/                 # Main library
│   │   ├── src/
│   │   │   ├── lib.rs           # Public API, UsmCore struct
│   │   │   ├── config/          # TOML config parsing
│   │   │   ├── events/          # Event bus (pub/sub)
│   │   │   ├── metrics/         # System & instance metrics
│   │   │   ├── monitor/         # Process monitoring
│   │   │   │   ├── backend.rs   # ProcessMonitor trait
│   │   │   │   ├── macos.rs     # macOS implementation
│   │   │   │   └── linux.rs     # Linux implementation
│   │   │   ├── server/          # HTTP/WebSocket (Axum)
│   │   │   └── service/         # Templates & instances
│   │   └── Cargo.toml
│   ├── usm-ffi/                  # C FFI bindings for Swift
│   │   ├── src/lib.rs
│   │   └── Cargo.toml
│   └── usm-cli/                  # Command-line interface
│       ├── src/main.rs
│       └── Cargo.toml
└── .gitignore
```

## Building

### Prerequisites

```bash
# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Verify installation
rustc --version
cargo --version
```

### Build Commands

```bash
cd server/usm-core

# Debug build
cargo build

# Release build (optimized, stripped)
cargo build --release

# Run tests
cargo test

# Run with clippy linting
cargo clippy -- -D warnings

# Format code
cargo fmt

# Check formatting without modifying
cargo fmt --check
```

### Build Outputs

| Output | Location | Purpose |
|--------|----------|---------|
| Debug library | `target/debug/libusm_core.dylib` | Development |
| Release library | `target/release/libusm_core.dylib` | Production |
| CLI binary | `target/release/usm` | Command-line tool |
| FFI library | `target/release/libusm_ffi.dylib` | Swift integration |

## Configuration

### services.toml

```toml
# Templates define service blueprints
[templates.management-api]
display_name = "Management API"
description = "Python backend API server"
default_port = 8766
port_range = [8766, 8799]
start_command = "python3 {working_dir}/management/server.py --port {port}"
health_endpoint = "http://localhost:{port}/health"
health_timeout_ms = 5000
category = "core"
supports_multiple = true

[templates.ollama]
display_name = "Ollama LLM Server"
default_port = 11434
start_command = "OLLAMA_HOST=0.0.0.0:{port} ollama serve"
health_endpoint = "http://localhost:{port}/api/tags"
category = "core"
supports_multiple = true

# Instances are running services
[instances.management-api-primary]
template = "management-api"
port = 8766
working_dir = "${PROJECT_ROOT}/server"
auto_start = true
tags = ["core", "primary"]

[instances.ollama-primary]
template = "ollama"
port = 11434
auto_start = false
tags = ["llm"]
```

## HTTP API

The USM Core server runs on port 8787 by default (8767 is reserved for the legacy Swift USM app).

### Templates

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/templates` | GET | List all templates |
| `/api/templates/{id}` | GET | Get template details |
| `/api/templates` | POST | Register new template |

### Instances

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/instances` | GET | List instances (filter: `?template=X`, `?tag=Y`, `?status=running`) |
| `/api/instances/{id}` | GET | Get instance details with metrics |
| `/api/instances` | POST | Create new instance |
| `/api/instances/{id}/start` | POST | Start instance |
| `/api/instances/{id}/stop` | POST | Stop instance |
| `/api/instances/{id}/restart` | POST | Restart instance |

### System

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | USM Core health check |
| `/api/metrics` | GET | System-wide metrics |

### WebSocket

Connect to `ws://localhost:8787/ws` for real-time events:

```json
{"type": "status_changed", "instance_id": "mgmt-api-v1", "status": "running", "pid": 12345}
{"type": "metrics_updated", "instance_id": "ollama-primary", "cpu": 45.2, "memory_mb": 1024}
{"type": "health_changed", "instance_id": "mgmt-api-v1", "healthy": true}
```

## CLI Usage

```bash
# Start the HTTP/WebSocket server
usm server --port 8787

# List templates
usm templates

# List instances
usm instances
usm instances --template management-api
usm instances --tag core
usm instances --status running

# Control instances
usm start <instance-id>
usm stop <instance-id>
usm restart <instance-id>

# Create new instance
usm create --template management-api --id my-api --port 8770

# Remove instance
usm remove <instance-id>

# System metrics
usm metrics
```

## C FFI for Swift Integration

The `usm-ffi` crate provides C-compatible bindings for Swift:

```c
// Create USM Core instance
UsmHandle* usm_create(const char* config_path);

// Destroy instance
void usm_destroy(UsmHandle* handle);

// Get all services
ServiceArray* usm_get_services(const UsmHandle* handle);

// Control services
int usm_start_service(UsmHandle* handle, const char* instance_id);
int usm_stop_service(UsmHandle* handle, const char* instance_id);
int usm_restart_service(UsmHandle* handle, const char* instance_id);

// Free memory
void usm_free_services(ServiceArray* services);

// Server port and version
int usm_get_server_port();
const char* usm_version();
```

### Swift Integration Example

```swift
import Foundation

class USMBridge {
    private var handle: OpaquePointer?

    init(configPath: String) {
        handle = usm_create(configPath)
    }

    deinit {
        if let h = handle { usm_destroy(h) }
    }

    func startService(_ id: String) -> Bool {
        guard let h = handle else { return false }
        return usm_start_service(h, id) == 0
    }
}
```

## Platform Support

| Platform | Monitor Backend | Status |
|----------|-----------------|--------|
| macOS | libproc + sysinfo | Complete |
| Linux | procfs | Implemented |
| Windows | WMI | Not yet |

## Performance Targets

| Metric | Target |
|--------|--------|
| Status update latency | <50ms |
| Memory usage | <10MB |
| CPU per monitoring cycle | <5ms |
| Startup time | <100ms |
| Binary size (release) | <2MB |
| Uptime reliability | Months |

## Testing

```bash
# Run all tests
cargo test

# Run with verbose output
cargo test -- --nocapture

# Run specific test
cargo test test_template_registry

# Run tests with coverage (requires cargo-tarpaulin)
cargo install cargo-tarpaulin
cargo tarpaulin --out Html
```

### Current Test Coverage

- 49 tests across core functionality (unit + property-based)
- Template registry CRUD
- Instance lifecycle management
- Event bus pub/sub
- Config file parsing with property tests
- System metrics collection
- Process monitoring
- TOML serialization roundtrip verification

## Development

### Code Quality

```bash
# Lint with clippy
cargo clippy -- -D warnings

# Format code
cargo fmt

# Check for security vulnerabilities
cargo audit
```

### Adding a New Service Template

1. Add template definition to `config/services.toml`
2. Start USM Core server
3. Template is automatically available via API

### Adding a New Platform Backend

1. Create new file in `src/monitor/` (e.g., `windows.rs`)
2. Implement `ProcessMonitor` trait
3. Add conditional compilation in `src/monitor/mod.rs`
4. Update `create_monitor()` factory function

## Integration with UnaMentis

USM Core is designed to replace the Swift-based subprocess monitoring in the USM menu bar app:

### Current Status

- **Rust Core**: Fully functional with HTTP API and CLI
- **Swift App**: Works independently (not yet using Rust backend)
- **Integration**: Can communicate via HTTP API (port 8787)

### Integration Roadmap

1. **Phase 1** (Current): Rust core runs alongside Swift app
   - Rust CLI can manage services via `usm` command
   - HTTP API available for external control
   - Swift app continues to work independently
2. **Phase 2**: Swift app calls Rust via HTTP API
   - Swift makes HTTP requests to Rust server
   - Gradual migration of service control
3. **Phase 3**: Swift app uses Rust via FFI (lower latency)
   - Direct library calls via C bindings
   - Requires cbindgen header generation
4. **Phase 4**: Same Rust core powers Linux and Web UIs
   - TUI for Linux servers
   - Web dashboard via HTTP/WebSocket

## Related Documentation

- [Plan File](../../.claude/plans/fuzzy-bubbling-waffle.md) - Full implementation plan
- [Project Overview](../../docs/architecture/PROJECT_OVERVIEW.md) - System architecture
- [Server Infrastructure](../../docs/architecture/SERVER_INFRASTRUCTURE.md) - Server components

## License

Part of the UnaMentis project.
