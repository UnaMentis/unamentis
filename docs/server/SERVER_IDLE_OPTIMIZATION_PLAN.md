# Server Idle Resource Optimization Plan

## Executive Summary

This document outlines strategies to dramatically reduce power consumption and thermal activity when the UnaMentis server stack is idle. The goal is to implement a tiered "sleep" system where services reduce resource usage based on inactivity duration while maintaining acceptable responsiveness.

---

## The Problem

When running all AI services locally, even during idle periods:

| Current State | Expected | Actual | Gap |
|--------------|----------|--------|-----|
| Idle power draw | ~2-3W | ~15-25W | **10-20W excess** |
| GPU utilization | 0% | 5-30% | Models in VRAM |
| Memory pressure | Low | High | Models always loaded |
| Battery life (idle) | 10+ hours | 3-4 hours | **Severe impact** |

### Root Causes Identified

1. **VibeVoice TTS Model Always Loaded** - 0.5B parameter model sits in MPS memory
2. **Ollama Models in VRAM** - Default 5-minute keep_alive, but often models stay loaded
3. **Background polling/health checks** - Continuous network activity
4. **Next.js Hot Reload** - Development mode file watching
5. **No coordinated idle detection** - Services don't know system is idle

---

## Tiered Idle State Architecture

### Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Idle State Machine                                   │
│                                                                              │
│  ┌──────────┐     30s      ┌──────────┐     5min     ┌──────────┐          │
│  │  ACTIVE  │─────────────▶│  WARM    │─────────────▶│  COOL    │          │
│  │          │◀─────────────│          │◀─────────────│          │          │
│  └──────────┘   request    └──────────┘   request    └──────────┘          │
│       │                                                    │                 │
│       │                                               30min│                 │
│       │                                                    ▼                 │
│       │         request    ┌──────────┐     request   ┌──────────┐          │
│       └───────────────────▶│  COLD    │◀──────────────│ DORMANT  │          │
│                            │          │               │          │          │
│                            └──────────┘               └──────────┘          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### State Definitions

| State | Inactivity | Response Time | Power Target | Description |
|-------|------------|---------------|--------------|-------------|
| **ACTIVE** | 0-30s | Instant | Full | Normal operation, all services hot |
| **WARM** | 30s-5min | <500ms | -30% | Reduce polling, maintain models |
| **COOL** | 5-30min | 1-2s | -60% | Unload TTS model, reduce Ollama keep_alive |
| **COLD** | 30min-2hr | 3-5s | -80% | Unload all models, minimal processes |
| **DORMANT** | 2hr+ | 10-15s | -95% | Only management console running |

---

## Service-Specific Optimization Strategies

### 1. VibeVoice TTS (Port 8880)

**Current Behavior:**
- Model loaded at startup ([vibevoice_realtime_openai_api.py:163-219](../../../vibevoice-realtime-openai-api/vibevoice_realtime_openai_api.py#L163))
- Stays in MPS memory permanently
- ~2GB GPU memory usage
- Continuous idle power draw

**Optimization Strategy:**

#### Option A: Lazy Loading (Recommended)
```python
# Modify VibeVoiceTTSService class

class VibeVoiceTTSService:
    def __init__(self, model_path: str, device: str = "cuda"):
        self.model_path = model_path
        self.device = device
        self.processor = None  # Don't load yet
        self.model = None      # Don't load yet
        self._last_used = 0
        self._unload_timeout = 300  # 5 minutes

    def _ensure_loaded(self):
        """Load model on first use"""
        if self.model is None:
            self._load_model()
        self._last_used = time.time()

    def _load_model(self):
        """Load model (called on demand)"""
        print(f"[startup] Loading model on demand...")
        self.processor = VibeVoiceStreamingProcessor.from_pretrained(self.model_path)
        # ... rest of loading logic
        print(f"[startup] Model ready (loaded on demand)")

    def _unload_model(self):
        """Unload model to free memory"""
        if self.model is not None:
            print("[idle] Unloading model to save resources")
            del self.model
            self.model = None
            del self.processor
            self.processor = None
            torch.cuda.empty_cache()  # Or torch.mps.empty_cache()
            gc.collect()

    async def _idle_checker(self):
        """Background task to unload when idle"""
        while True:
            await asyncio.sleep(60)  # Check every minute
            if self.model is not None:
                idle_time = time.time() - self._last_used
                if idle_time > self._unload_timeout:
                    self._unload_model()

    def generate_speech(self, text: str, voice: str, cfg_scale: float = 1.5):
        self._ensure_loaded()  # Load if needed
        # ... rest of generation logic
```

**Expected Impact:**
- Idle power: -2-3W
- First request after idle: +2-4s latency
- Memory freed: ~2GB GPU memory

#### Option B: Process-Level Unloading (Gunicorn Pattern)

Based on research from [Immich's approach](https://github.com/immich-app/immich/pull/3340):

```python
# Run VibeVoice under gunicorn with worker management

# gunicorn_config.py
workers = 1
worker_class = "uvicorn.workers.UvicornWorker"
max_requests = 100  # Restart worker after 100 requests
max_requests_jitter = 10
timeout = 300  # Worker timeout

# Custom idle shutdown hook
def worker_int(worker):
    """Called when worker receives SIGINT"""
    # Graceful shutdown with memory cleanup
    pass
```

### 2. Ollama LLM (Port 11434)

**Current Behavior:**
- Default `keep_alive` is 5 minutes ([FAQ](https://docs.ollama.com/faq))
- Models stay in VRAM after unload timeout
- No environment variable set in current deployment

**Optimization Strategy:**

#### Environment Configuration
```bash
# Set in launchctl plist or startup script
export OLLAMA_KEEP_ALIVE="2m"   # Shorter default (2 minutes)
export OLLAMA_MAX_LOADED_MODELS=1  # Only one model at a time
```

#### API-Level Control
```python
# In management console, send unload command after idle threshold

async def unload_ollama_models():
    """Force unload all Ollama models"""
    async with aiohttp.ClientSession() as session:
        # List loaded models
        async with session.get("http://localhost:11434/api/ps") as resp:
            data = await resp.json()
            for model in data.get("models", []):
                model_name = model.get("name")
                # Send unload request (keep_alive: 0)
                await session.post(
                    "http://localhost:11434/api/generate",
                    json={
                        "model": model_name,
                        "keep_alive": 0
                    }
                )
                print(f"[idle] Unloaded Ollama model: {model_name}")
```

#### Ollama Command Reference
```bash
# Immediately unload a model
curl http://localhost:11434/api/generate -d '{"model": "qwen2.5:7b", "keep_alive": 0}'

# Or use ollama CLI
ollama stop qwen2.5:7b
```

**Expected Impact:**
- VRAM freed: 5-40GB (depending on model)
- Idle power: -3-8W
- First request after idle: +5-15s (model reload)

### 3. Management Console (Port 8766)

**Current Behavior:**
- Health checks on every `/api/servers` request ([server.py:792](../management/server.py#L792))
- WebSocket broadcast to all clients
- Curriculum loading at startup

**Optimization Strategy:**

#### Reduce Health Check Frequency
```python
# Add caching to health checks

class ServerHealthCache:
    def __init__(self, ttl_seconds: int = 30):
        self._cache = {}
        self._ttl = ttl_seconds

    async def get_server_health(self, server: ServerStatus) -> ServerStatus:
        cache_key = server.id
        now = time.time()

        if cache_key in self._cache:
            cached, timestamp = self._cache[cache_key]
            if now - timestamp < self._ttl:
                return cached

        # Cache miss - do actual health check
        result = await check_server_health(server)
        self._cache[cache_key] = (result, now)
        return result

# Modify handle_get_servers to use cache
async def handle_get_servers(request: web.Request) -> web.Response:
    # Use cache instead of checking every time
    tasks = [health_cache.get_server_health(s) for s in state.servers.values()]
    # ...
```

#### Adaptive Polling Based on Dashboard Activity
```python
# Track WebSocket activity
class AdaptivePoller:
    def __init__(self):
        self.last_ws_activity = time.time()
        self.poll_interval = 30  # Start at 30s

    def on_ws_activity(self):
        self.last_ws_activity = time.time()
        self.poll_interval = 5  # Speed up polling when active

    async def adaptive_poll_loop(self):
        while True:
            idle_time = time.time() - self.last_ws_activity
            if idle_time > 300:  # 5 min idle
                self.poll_interval = 60
            elif idle_time > 60:  # 1 min idle
                self.poll_interval = 30
            else:
                self.poll_interval = 5

            await asyncio.sleep(self.poll_interval)
            # Do background tasks
```

### 4. Next.js Dashboard (Port 3000)

**Current Behavior:**
- `npx next dev` runs in development mode
- File watching for hot reload
- Constant compilation checks

**Optimization Strategy:**

#### Use Production Build
```bash
# Build for production
cd server/web
npm run build

# Start production server (much lower resource usage)
npm run start  # Instead of npm run dev
```

**Expected Impact:**
- CPU: -10-30% reduction
- Memory: -100-200MB
- No file watching overhead

#### Conditional Development Mode
```python
# In managed_services, detect environment
if os.environ.get("NODE_ENV") == "production":
    command = ["npx", "next", "start"]
else:
    command = ["npx", "next", "dev"]
```

---

## Coordinated Idle Management

### Central Idle Manager

```python
# server/management/idle_manager.py

from enum import Enum
from dataclasses import dataclass
import asyncio
import time

class IdleState(Enum):
    ACTIVE = "active"
    WARM = "warm"
    COOL = "cool"
    COLD = "cold"
    DORMANT = "dormant"

@dataclass
class IdleThresholds:
    warm: int = 30        # seconds
    cool: int = 300       # 5 minutes
    cold: int = 1800      # 30 minutes
    dormant: int = 7200   # 2 hours

class IdleManager:
    def __init__(self):
        self.last_activity = time.time()
        self.current_state = IdleState.ACTIVE
        self.thresholds = IdleThresholds()
        self._state_handlers = {}

    def record_activity(self, activity_type: str = "request"):
        """Record user activity, reset to ACTIVE"""
        self.last_activity = time.time()
        if self.current_state != IdleState.ACTIVE:
            self._transition_to(IdleState.ACTIVE)

    def register_handler(self, state: IdleState, handler):
        """Register callback for state transitions"""
        if state not in self._state_handlers:
            self._state_handlers[state] = []
        self._state_handlers[state].append(handler)

    async def _transition_to(self, new_state: IdleState):
        """Handle state transition"""
        old_state = self.current_state
        self.current_state = new_state
        print(f"[IdleManager] State transition: {old_state.value} -> {new_state.value}")

        # Call registered handlers
        for handler in self._state_handlers.get(new_state, []):
            try:
                await handler(old_state, new_state)
            except Exception as e:
                print(f"[IdleManager] Handler error: {e}")

    async def monitor_loop(self):
        """Background loop to check idle state"""
        while True:
            await asyncio.sleep(10)  # Check every 10 seconds

            idle_seconds = time.time() - self.last_activity
            new_state = self._calculate_state(idle_seconds)

            if new_state != self.current_state:
                await self._transition_to(new_state)

    def _calculate_state(self, idle_seconds: float) -> IdleState:
        if idle_seconds >= self.thresholds.dormant:
            return IdleState.DORMANT
        elif idle_seconds >= self.thresholds.cold:
            return IdleState.COLD
        elif idle_seconds >= self.thresholds.cool:
            return IdleState.COOL
        elif idle_seconds >= self.thresholds.warm:
            return IdleState.WARM
        else:
            return IdleState.ACTIVE


# Usage in server.py
idle_manager = IdleManager()

# Register handlers for each service
async def on_cool_state(old_state, new_state):
    """Called when entering COOL state"""
    print("[COOL] Unloading TTS model")
    await unload_vibevoice_model()

async def on_cold_state(old_state, new_state):
    """Called when entering COLD state"""
    print("[COLD] Unloading all models")
    await unload_ollama_models()
    await stop_nextjs_dashboard()

async def on_active_state(old_state, new_state):
    """Called when activity detected"""
    if old_state in (IdleState.COLD, IdleState.DORMANT):
        print("[ACTIVE] Waking up services")
        await start_critical_services()

idle_manager.register_handler(IdleState.COOL, on_cool_state)
idle_manager.register_handler(IdleState.COLD, on_cold_state)
idle_manager.register_handler(IdleState.ACTIVE, on_active_state)
```

---

## Wake-Up Strategy

When transitioning from idle states back to ACTIVE, services need to reload quickly:

### Warm-Up Priority Order

1. **Management Console** - Already running, no action
2. **Ollama** - Send a warmup request to preload model
3. **VibeVoice** - Trigger model load in background
4. **Next.js** - Start if stopped (not critical for API)

### Predictive Wake-Up

```python
# If first request comes to Management Console,
# proactively start warming up other services

async def handle_any_request(request):
    """Middleware to detect activity and pre-warm"""
    idle_manager.record_activity()

    # If coming from COLD state, pre-warm in background
    if idle_manager.current_state in (IdleState.COLD, IdleState.DORMANT):
        asyncio.create_task(pre_warm_services())

    return await actual_handler(request)

async def pre_warm_services():
    """Background task to warm up services"""
    # Start Ollama model loading (don't wait)
    asyncio.create_task(warm_ollama())

    # Start VibeVoice model loading (don't wait)
    asyncio.create_task(warm_vibevoice())
```

---

## Configuration API

Allow users to configure idle behavior:

```python
# API endpoint for idle configuration
@app.post("/api/system/idle/config")
async def configure_idle(request):
    data = await request.json()

    # Update thresholds
    if "thresholds" in data:
        idle_manager.thresholds = IdleThresholds(**data["thresholds"])

    # Enable/disable idle management
    if "enabled" in data:
        idle_manager.enabled = data["enabled"]

    return web.json_response({"status": "ok"})

@app.get("/api/system/idle/status")
async def get_idle_status(request):
    return web.json_response({
        "current_state": idle_manager.current_state.value,
        "seconds_idle": time.time() - idle_manager.last_activity,
        "thresholds": asdict(idle_manager.thresholds),
        "enabled": idle_manager.enabled
    })
```

---

## Dashboard Controls

Add UI controls for idle management:

### "Power Mode" Selector

| Mode | Description | Thresholds |
|------|-------------|------------|
| **Performance** | Never idle, always ready | All disabled |
| **Balanced** | Default settings | 30s/5m/30m/2h |
| **Power Saver** | Aggressive power saving | 10s/1m/5m/30m |
| **Manual** | User-controlled | Custom |

### Quick Actions

- "Unload All Models Now" button
- "Keep Awake for 1 Hour" button
- "Enter Low Power Mode" button

---

## Implementation Status

> **Status:** Phases 1-4 COMPLETE (January 2026)

### Phase 1: Foundation - COMPLETE
- [x] Implement `IdleManager` class (`server/management/idle_manager.py`)
- [x] Add activity tracking to all API endpoints
- [x] Create idle state transitions with handlers
- [x] Add `/api/system/idle/status` endpoint

### Phase 2: VibeVoice Lazy Loading - COMPLETE
- [x] Add `_unload_vibevoice()` method
- [x] Model unload on COOL state transition
- [x] Pre-warm on activity detection

### Phase 3: Ollama Integration - COMPLETE
- [x] Implement `_unload_ollama_models()`
- [x] Configure model unloading via API
- [x] Add model preloading on wake (`_pre_warm_services()`)

### Phase 4: Coordinated Idle - COMPLETE
- [x] Implement state transition handlers
- [x] Add predictive wake-up (`_pre_warm_services()`)
- [x] Power profiles (Performance, Balanced, Power Saver, Manual)
- [x] Full API: status, config, history, modes, keep-awake, force-state

### Phase 5: Validation - PARTIAL
- [ ] Measure actual power savings (needs testing)
- [ ] Validate response time targets (needs testing)
- [x] Document configuration options (API documented)
- [ ] Create user guide

### API Endpoints Implemented
- `GET /api/system/idle/status` - Current idle state
- `POST /api/system/idle/config` - Configure thresholds
- `GET /api/system/idle/history` - Transition history
- `GET /api/system/idle/modes` - Available power modes
- `POST /api/system/idle/keep-awake` - Prevent idle transitions
- `POST /api/system/idle/cancel-keep-awake` - Cancel keep-awake
- `POST /api/system/idle/force-state` - Force state transition

---

## Expected Outcomes

### Power Consumption Targets

| State | Current (est.) | Target | Savings |
|-------|----------------|--------|---------|
| ACTIVE | 15-25W | 15-25W | - |
| WARM | 15-25W | 10-15W | 30-40% |
| COOL | 15-25W | 5-8W | 60-70% |
| COLD | 15-25W | 2-4W | 80-85% |
| DORMANT | 15-25W | 1-2W | 90-95% |

### Battery Life Improvement

| Scenario | Current | Expected |
|----------|---------|----------|
| Continuous use | 2-3 hours | 2-3 hours |
| Mixed use (50% idle) | 3-4 hours | 6-8 hours |
| Mostly idle (80% idle) | 4-5 hours | 10-15 hours |
| Standby overnight | Heavy drain | Minimal drain |

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Slow wake-up frustrates users | UX | Predictive wake-up, clear loading indicators |
| Model reload fails | Availability | Graceful fallback, retry logic |
| State machine complexity | Bugs | Comprehensive testing, simple states |
| Memory fragmentation | Performance | Periodic full restart (weekly) |

---

## Alternative Approaches Considered

### 1. Separate Server Machine
- **Pro:** Laptop stays cool, no optimization needed
- **Con:** Additional hardware cost, network latency

### 2. Docker Container Isolation
- **Pro:** Easy start/stop of services
- **Con:** MPS passthrough complexity on macOS

### 3. Scheduled Service Hours
- **Pro:** Predictable resource usage
- **Con:** Not responsive to actual usage patterns

---

## References

- [Ollama keep_alive FAQ](https://docs.ollama.com/faq)
- [Ollama Auto-unload Feature Request #11085](https://github.com/ollama/ollama/issues/11085)
- [LM Studio TTL-based Model Unloading](https://lmstudio.ai/docs/python/manage-models/loading)
- [Immich ML Model Unloading PR #3340](https://github.com/immich-app/immich/pull/3340)
- [PyTorch GPU Memory Clearing](https://saturncloud.io/blog/how-to-clear-gpu-memory-after-pytorch-model-training-without-restarting-kernel/)
- [macOS Power Management (pmset)](https://ss64.com/mac/pmset.html)

---

## Related Documents

- [SERVER_RESOURCE_MONITORING_PLAN.md](./SERVER_RESOURCE_MONITORING_PLAN.md) - Monitoring implementation
- [MACBOOK_M4_DEPLOYMENT.md](./MACBOOK_M4_DEPLOYMENT.md) - Hardware deployment guide
- [OPENTELEMETRY_SPEC.md](../OPENTELEMETRY_SPEC.md) - Telemetry architecture
