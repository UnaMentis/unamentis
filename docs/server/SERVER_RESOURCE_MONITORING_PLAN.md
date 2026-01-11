# Server Resource Monitoring & Telemetry Plan

## Executive Summary

This document outlines a comprehensive plan to add detailed resource monitoring and telemetry to the UnaMentis server stack. The goal is to understand **exactly when and under what conditions** the server causes excessive battery drain and thermal activity, enabling informed optimization decisions.

---

## Problem Statement

When running the UnaMentis server stack on a development laptop (e.g., MacBook Pro):
- **Battery drains rapidly** even during apparent idle periods
- **Thermal activity is excessive** when minimal work is being performed
- **Root cause unclear** - which service(s) are responsible?
- **No visibility** into what's consuming resources when "idle"

---

## Current Server Architecture

Based on analysis of the codebase, the following services run on the server:

| Service | Port | Purpose | Resource Profile |
|---------|------|---------|------------------|
| Management Console | 8766 | Python aiohttp - orchestration | Low baseline |
| Ollama LLM | 11434 | LLM inference server | **HIGH when models loaded** |
| VibeVoice TTS | 8880 | Neural TTS (0.5B model) | **HIGH - model always loaded** |
| Next.js Dashboard | 3000 | Web UI | Medium (Node.js) |
| Piper TTS | 11402 | Lightweight TTS | Low |
| Whisper STT | 11401 | Speech-to-text | Medium when processing |

### Key Findings from Code Analysis

1. **VibeVoice TTS** ([vibevoice_realtime_openai_api.py](../../../vibevoice-realtime-openai-api/vibevoice_realtime_openai_api.py)):
   - Loads 0.5B parameter model **at startup**
   - Model stays in memory (GPU/MPS) permanently
   - Uses PyTorch with MPS acceleration
   - **No idle unloading mechanism**

2. **Ollama** ([server.py:857-894](../management/server.py#L857)):
   - Default `keep_alive` is 5 minutes
   - Models stay loaded in VRAM after requests
   - No automatic unload when idle
   - Currently running but with no models loaded (good!)

3. **Management Console** ([server.py](../management/server.py)):
   - Lightweight async Python server
   - Health checks run in parallel every request
   - WebSocket connections maintained
   - Unlikely to cause significant drain

---

## Monitoring Architecture

### Phase 1: System-Level Metrics Collection

Add comprehensive system metrics to the Management Console:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Resource Monitoring System                           │
│                                                                          │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐   │
│  │   powermetrics   │     │  Process Stats  │     │  GPU/MPS Stats  │   │
│  │  (thermal, CPU)  │     │   (ps, top)     │     │   (ioreg)       │   │
│  └────────┬────────┘     └────────┬────────┘     └────────┬────────┘   │
│           │                       │                       │             │
│           └───────────────────────┼───────────────────────┘             │
│                                   ▼                                      │
│                    ┌──────────────────────────────┐                     │
│                    │   ResourceMetricsCollector    │                     │
│                    │   (new Python module)         │                     │
│                    └──────────────┬───────────────┘                     │
│                                   │                                      │
│                                   ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Management Console API                        │   │
│  │   /api/system/metrics                                            │   │
│  │   /api/system/thermal                                            │   │
│  │   /api/system/power                                              │   │
│  │   /api/system/processes                                          │   │
│  └────────────────────────────────┬────────────────────────────────┘   │
│                                   │                                      │
│                                   ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Web Dashboard UI                               │   │
│  │   - Real-time graphs                                             │   │
│  │   - Historical trends                                            │   │
│  │   - Alerts for high usage                                        │   │
│  │   - Per-service breakdown                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Metrics to Collect

#### 1. Power & Thermal Metrics (via `powermetrics`)

| Metric | Source | Frequency | Purpose |
|--------|--------|-----------|---------|
| CPU Power (W) | powermetrics | 5s | Track CPU energy draw |
| GPU Power (W) | powermetrics | 5s | Track GPU/MPS energy draw |
| ANE Power (W) | powermetrics | 5s | Neural Engine usage |
| Package Power (W) | powermetrics | 5s | Total SoC power |
| CPU Die Temperature | powermetrics | 5s | Thermal state |
| Thermal Pressure | powermetrics | 5s | System throttling state |
| Fan Speed (RPM) | powermetrics | 5s | Cooling activity |

**Command:** `sudo powermetrics --samplers cpu_power,gpu_power,thermal,smc -i 5000 -n 1 --format json`

#### 2. Per-Process Metrics

| Metric | Source | Frequency | Purpose |
|--------|--------|-----------|---------|
| CPU % | ps/top | 2s | Per-service CPU usage |
| RSS (Memory) | ps | 5s | Resident memory |
| GPU Memory | N/A (unified) | 5s | MPS memory allocation |
| Thread Count | ps | 10s | Concurrency |
| Open Files | lsof | 30s | Resource leaks |

**Command:** `ps -p <pid> -o pid,ppid,user,%cpu,%mem,rss,vsz,command`

#### 3. Activity Correlation Metrics

| Metric | Source | Purpose |
|--------|--------|---------|
| Last API request time | Internal | Correlate activity with power |
| Request count (last 5m) | Internal | Activity level |
| Active WebSocket connections | Internal | Dashboard load |
| Model inference count | Internal | GPU activity |

---

## Data Collection Implementation

### New Module: `resource_monitor.py`

```python
# server/management/resource_monitor.py

import asyncio
import json
import subprocess
import time
from collections import deque
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional
from datetime import datetime

@dataclass
class PowerSnapshot:
    """Point-in-time power metrics"""
    timestamp: float
    cpu_power_w: float = 0.0
    gpu_power_w: float = 0.0
    ane_power_w: float = 0.0
    package_power_w: float = 0.0
    cpu_temp_c: float = 0.0
    thermal_pressure: str = "nominal"  # nominal, fair, serious, critical
    fan_speed_rpm: int = 0

@dataclass
class ProcessSnapshot:
    """Per-process resource usage"""
    pid: int
    name: str
    cpu_percent: float
    memory_mb: float
    thread_count: int

@dataclass
class ServiceMetrics:
    """Metrics for a managed service"""
    service_id: str
    service_name: str
    status: str
    cpu_percent: float
    memory_mb: float
    last_request_time: Optional[float]
    request_count_5m: int
    inference_count_5m: int

class ResourceMonitor:
    """Collects system resource metrics for power/thermal analysis"""

    def __init__(self, history_size: int = 720):  # 1 hour at 5s intervals
        self.power_history: deque = deque(maxlen=history_size)
        self.process_history: deque = deque(maxlen=history_size)
        self.service_metrics: Dict[str, ServiceMetrics] = {}
        self._running = False
        self._collection_task: Optional[asyncio.Task] = None

    async def start(self):
        """Start background metrics collection"""
        self._running = True
        self._collection_task = asyncio.create_task(self._collect_loop())

    async def stop(self):
        """Stop metrics collection"""
        self._running = False
        if self._collection_task:
            self._collection_task.cancel()

    async def _collect_loop(self):
        """Background collection loop"""
        while self._running:
            try:
                # Collect power metrics (requires sudo or privileges)
                power = await self._collect_power_metrics()
                self.power_history.append(power)

                # Collect process metrics
                processes = await self._collect_process_metrics()
                self.process_history.append({
                    "timestamp": time.time(),
                    "processes": processes
                })

            except Exception as e:
                print(f"[ResourceMonitor] Collection error: {e}")

            await asyncio.sleep(5)  # 5-second intervals

    async def _collect_power_metrics(self) -> PowerSnapshot:
        """Collect power metrics via powermetrics (macOS)"""
        try:
            # Note: powermetrics requires sudo
            # For non-sudo, use IOKit/ioreg alternatives
            result = await asyncio.create_subprocess_exec(
                "ioreg", "-r", "-c", "AppleSmartBattery",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            stdout, _ = await result.communicate()

            # Parse battery info for power draw
            # This is a simplified version - full implementation would parse JSON
            return PowerSnapshot(
                timestamp=time.time(),
                cpu_power_w=0.0,  # Requires powermetrics
                gpu_power_w=0.0,
                package_power_w=0.0,
                cpu_temp_c=0.0,
                thermal_pressure="nominal"
            )
        except Exception as e:
            return PowerSnapshot(timestamp=time.time())

    async def _collect_process_metrics(self) -> List[ProcessSnapshot]:
        """Collect per-process metrics"""
        processes = []

        # Get relevant process PIDs (our services)
        service_pids = {
            "ollama": await self._find_pid_by_name("ollama"),
            "vibevoice": await self._find_pid_by_port(8880),
            "nextjs": await self._find_pid_by_port(3000),
            "management": await self._find_pid_by_port(8766),
        }

        for name, pid in service_pids.items():
            if pid:
                metrics = await self._get_process_stats(pid)
                if metrics:
                    metrics.name = name
                    processes.append(metrics)

        return processes

    async def _find_pid_by_name(self, name: str) -> Optional[int]:
        """Find PID by process name"""
        try:
            result = await asyncio.create_subprocess_exec(
                "pgrep", "-x", name,
                stdout=subprocess.PIPE
            )
            stdout, _ = await result.communicate()
            if stdout.strip():
                return int(stdout.strip().split()[0])
        except:
            pass
        return None

    async def _find_pid_by_port(self, port: int) -> Optional[int]:
        """Find PID by listening port"""
        try:
            result = await asyncio.create_subprocess_exec(
                "lsof", "-t", "-i", f":{port}",
                stdout=subprocess.PIPE
            )
            stdout, _ = await result.communicate()
            if stdout.strip():
                return int(stdout.strip().split()[0])
        except:
            pass
        return None

    async def _get_process_stats(self, pid: int) -> Optional[ProcessSnapshot]:
        """Get stats for a specific process"""
        try:
            result = await asyncio.create_subprocess_exec(
                "ps", "-p", str(pid), "-o", "pid,%cpu,rss",
                stdout=subprocess.PIPE
            )
            stdout, _ = await result.communicate()
            lines = stdout.decode().strip().split('\n')
            if len(lines) > 1:
                parts = lines[1].split()
                return ProcessSnapshot(
                    pid=int(parts[0]),
                    name="",
                    cpu_percent=float(parts[1]),
                    memory_mb=int(parts[2]) / 1024,
                    thread_count=0
                )
        except:
            pass
        return None

    def get_summary(self) -> Dict:
        """Get summary metrics for dashboard"""
        recent_power = list(self.power_history)[-12:]  # Last minute
        recent_process = list(self.process_history)[-12:]

        # Calculate averages
        avg_power = sum(p.package_power_w for p in recent_power) / len(recent_power) if recent_power else 0

        # Find top CPU consumers
        top_cpu = {}
        for snapshot in recent_process:
            for proc in snapshot.get("processes", []):
                name = proc.name
                if name not in top_cpu:
                    top_cpu[name] = []
                top_cpu[name].append(proc.cpu_percent)

        avg_cpu_by_service = {
            name: sum(values) / len(values)
            for name, values in top_cpu.items()
        }

        return {
            "timestamp": time.time(),
            "power": {
                "avg_package_watts": round(avg_power, 2),
                "current_thermal_pressure": recent_power[-1].thermal_pressure if recent_power else "unknown",
                "current_cpu_temp": recent_power[-1].cpu_temp_c if recent_power else 0,
            },
            "processes": avg_cpu_by_service,
            "history_minutes": len(self.power_history) * 5 / 60
        }
```

### API Endpoints to Add

```python
# Add to server.py

@app.route('/api/system/metrics')
async def handle_system_metrics(request):
    """Get current system resource metrics"""
    return web.json_response(resource_monitor.get_summary())

@app.route('/api/system/power/history')
async def handle_power_history(request):
    """Get power metrics history"""
    limit = int(request.query.get("limit", "100"))
    history = list(resource_monitor.power_history)[-limit:]
    return web.json_response({
        "history": [asdict(p) for p in history],
        "count": len(history)
    })

@app.route('/api/system/processes')
async def handle_process_metrics(request):
    """Get per-process metrics"""
    if resource_monitor.process_history:
        latest = resource_monitor.process_history[-1]
        return web.json_response(latest)
    return web.json_response({"processes": []})
```

---

## Dashboard UI Additions

### New "System Health" Tab

The Web Dashboard should display:

1. **Real-time Power Graph**
   - X-axis: Time (last hour)
   - Y-axis: Watts
   - Lines: CPU, GPU, Package total
   - Overlay: Activity markers (API requests, inference)

2. **Service Resource Table**

   | Service | CPU % | Memory (MB) | Status | Last Active |
   |---------|-------|-------------|--------|-------------|
   | Ollama | 0.5% | 245 MB | Idle (no models) | 5m ago |
   | VibeVoice | **45%** | **2,100 MB** | Loaded | 2h ago |
   | Management | 1.2% | 85 MB | Active | now |
   | Next.js | 3.5% | 320 MB | Active | now |

3. **Thermal Status Panel**
   - Current thermal pressure (color-coded)
   - CPU temperature trend
   - Fan speed (if available)
   - Throttling events count

4. **Idle Analysis Panel**
   - "Time since last user activity"
   - "Resources consumed while idle"
   - Recommendations for optimization

---

## Alert Thresholds

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Package Power (idle) | > 5W | > 10W | Investigate service |
| CPU % (idle service) | > 5% | > 20% | Check for busy loops |
| Memory growth | > 100MB/hr | > 500MB/hr | Check for leaks |
| Thermal Pressure | fair | serious/critical | Reduce load or cool |

---

## Phase 2: Integration with Existing OpenTelemetry Plan

The resource monitoring integrates with the [OPENTELEMETRY_SPEC.md](../OPENTELEMETRY_SPEC.md):

### New Metrics for OTel

| Metric Name | Type | Description |
|-------------|------|-------------|
| `unamentis.server.power.cpu_watts` | gauge | CPU power consumption |
| `unamentis.server.power.gpu_watts` | gauge | GPU power consumption |
| `unamentis.server.power.package_watts` | gauge | Total SoC power |
| `unamentis.server.thermal.temperature` | gauge | CPU die temperature |
| `unamentis.server.thermal.pressure` | gauge | 0-3 scale |
| `unamentis.server.service.cpu_percent` | gauge | Per-service CPU |
| `unamentis.server.service.memory_mb` | gauge | Per-service memory |
| `unamentis.server.idle.duration_seconds` | gauge | Time since activity |

---

## Implementation Status

> **Status:** Phases 1-3 COMPLETE (January 2026)

### Phase 1: Basic Monitoring - COMPLETE
- [x] Create `resource_monitor.py` module (`server/management/resource_monitor.py`)
- [x] Add API endpoints to server.py
- [x] Implement process metrics collection (PowerSnapshot, ProcessSnapshot)
- [x] Add to Management Console dashboard (health-panel.tsx)
- [x] Test on development laptop

### Phase 2: Power Metrics - COMPLETE
- [x] Implement power metrics collection
- [x] Add battery/thermal state tracking
- [x] Create power history storage (`metrics_history.py`)
- [x] Add metrics visualization in dashboard

### Phase 3: Analysis Tools - COMPLETE
- [x] Implement idle detection (via IdleManager integration)
- [x] Service-level resource attribution (ServiceResourceMetrics)
- [x] Process-level metrics (CPU, memory, GPU estimates)

### Phase 4: Integration - PARTIAL
- [ ] Export to OpenTelemetry/SigNoz (deferred)
- [x] Add to existing dashboards
- [x] Document API for AI agent access
- [ ] Create troubleshooting runbook

### Implemented Components
- `ResourceMonitor` class with async collection loop
- `PowerSnapshot` for power/thermal metrics
- `ProcessSnapshot` for per-process usage
- `ServiceResourceMetrics` for service-level attribution
- API endpoints for metrics retrieval

---

## Expected Outcomes

After implementation, you will be able to:

1. **Identify the culprit** - See exactly which service uses resources when idle
2. **Quantify the waste** - Measure watt-hours consumed during idle periods
3. **Validate optimizations** - Before/after comparison of resource changes
4. **Set baseline** - Establish expected idle power consumption targets
5. **Alert on anomalies** - Get notified when idle power exceeds thresholds

---

## References

- [powermetrics Man Page](https://ss64.com/mac/powermetrics.html)
- [macOS Thermal Monitoring](https://mybyways.com/blog/monitoring-macbook-temperature)
- [Apple Silicon Temperature Monitor (GitHub)](https://github.com/Issac-Lopez/mac_temp_sensor)
- [Ollama Auto-unload Issue #11085](https://github.com/ollama/ollama/issues/11085)

---

## Related Documents

- [SERVER_IDLE_OPTIMIZATION_PLAN.md](./SERVER_IDLE_OPTIMIZATION_PLAN.md) - Optimization strategies
- [OPENTELEMETRY_SPEC.md](../OPENTELEMETRY_SPEC.md) - Full telemetry architecture
- [MACBOOK_M4_DEPLOYMENT.md](./MACBOOK_M4_DEPLOYMENT.md) - Deployment guide
