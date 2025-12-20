#!/usr/bin/env python3
"""
VoiceLearn Web Management Server
A next-generation management interface for monitoring and configuring VoiceLearn services.
"""

import asyncio
import json
import logging
import os
import sys
import time
import uuid
from collections import deque
from dataclasses import dataclass, field, asdict
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Set
from pathlib import Path

# Add aiohttp for async HTTP server with WebSocket support
try:
    from aiohttp import web
    import aiohttp
except ImportError:
    print("Installing required dependencies...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "aiohttp"])
    from aiohttp import web
    import aiohttp

# Configuration
HOST = os.environ.get("VOICELEARN_MGMT_HOST", "0.0.0.0")
PORT = int(os.environ.get("VOICELEARN_MGMT_PORT", "8766"))
MAX_LOG_ENTRIES = 10000
MAX_METRICS_HISTORY = 1000

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


@dataclass
class LogEntry:
    """Represents a single log entry from a client."""
    id: str
    timestamp: str
    level: str
    label: str
    message: str
    file: str = ""
    function: str = ""
    line: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)
    client_id: str = ""
    client_name: str = ""
    received_at: float = field(default_factory=time.time)


@dataclass
class MetricsSnapshot:
    """Represents a metrics snapshot from a client."""
    id: str
    client_id: str
    client_name: str
    timestamp: str
    received_at: float
    session_duration: float = 0.0
    turns_total: int = 0
    interruptions: int = 0
    # Latencies (in ms)
    stt_latency_median: float = 0.0
    stt_latency_p99: float = 0.0
    llm_ttft_median: float = 0.0
    llm_ttft_p99: float = 0.0
    tts_ttfb_median: float = 0.0
    tts_ttfb_p99: float = 0.0
    e2e_latency_median: float = 0.0
    e2e_latency_p99: float = 0.0
    # Costs
    stt_cost: float = 0.0
    tts_cost: float = 0.0
    llm_cost: float = 0.0
    total_cost: float = 0.0
    # Device stats
    thermal_throttle_events: int = 0
    network_degradations: int = 0
    # Raw data for charts
    raw_data: Dict[str, Any] = field(default_factory=dict)


@dataclass
class RemoteClient:
    """Represents a connected remote client (iOS device)."""
    id: str
    name: str
    device_model: str = ""
    os_version: str = ""
    app_version: str = ""
    first_seen: float = field(default_factory=time.time)
    last_seen: float = field(default_factory=time.time)
    ip_address: str = ""
    status: str = "online"  # online, idle, offline
    current_session_id: Optional[str] = None
    total_sessions: int = 0
    total_logs: int = 0
    config: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ServerStatus:
    """Represents a backend server status."""
    id: str
    name: str
    type: str  # ollama, whisper, piper, gateway, custom
    url: str
    port: int
    status: str = "unknown"  # unknown, healthy, degraded, unhealthy
    last_check: float = 0
    response_time_ms: float = 0
    capabilities: Dict[str, Any] = field(default_factory=dict)
    models: List[str] = field(default_factory=list)
    error_message: str = ""


@dataclass
class ModelInfo:
    """Represents a model available on a server."""
    id: str
    name: str
    type: str  # llm, stt, tts
    server_id: str
    size_bytes: int = 0
    parameters: str = ""
    quantization: str = ""
    loaded: bool = False
    last_used: float = 0
    usage_count: int = 0


class ManagementState:
    """Global state for the management server."""

    def __init__(self):
        self.logs: deque = deque(maxlen=MAX_LOG_ENTRIES)
        self.metrics_history: deque = deque(maxlen=MAX_METRICS_HISTORY)
        self.clients: Dict[str, RemoteClient] = {}
        self.servers: Dict[str, ServerStatus] = {}
        self.models: Dict[str, ModelInfo] = {}
        self.websockets: Set[web.WebSocketResponse] = set()
        self.stats = {
            "total_logs_received": 0,
            "total_metrics_received": 0,
            "server_start_time": time.time(),
            "errors_count": 0,
            "warnings_count": 0,
        }
        # Initialize default servers
        self._init_default_servers()

    def _init_default_servers(self):
        """Initialize default server configurations."""
        default_servers = [
            ("gateway", "VoiceLearn Gateway", "voicelearnGateway", "localhost", 11400),
            ("ollama", "Ollama LLM", "ollama", "localhost", 11434),
            ("whisper", "Whisper STT", "whisper", "localhost", 11401),
            ("piper", "Piper TTS", "piper", "localhost", 11402),
        ]
        for server_id, name, server_type, host, port in default_servers:
            self.servers[server_id] = ServerStatus(
                id=server_id,
                name=name,
                type=server_type,
                url=f"http://{host}:{port}",
                port=port
            )


# Global state
state = ManagementState()


# =============================================================================
# WebSocket Broadcasting
# =============================================================================

async def broadcast_message(msg_type: str, data: Any):
    """Broadcast a message to all connected WebSocket clients."""
    if not state.websockets:
        return

    message = json.dumps({
        "type": msg_type,
        "data": data,
        "timestamp": datetime.utcnow().isoformat() + "Z"
    })

    dead_sockets = set()
    for ws in state.websockets:
        try:
            await ws.send_str(message)
        except Exception:
            dead_sockets.add(ws)

    # Clean up dead connections
    state.websockets -= dead_sockets


# =============================================================================
# API Handlers - Logs
# =============================================================================

async def handle_receive_log(request: web.Request) -> web.Response:
    """Receive log entries from iOS clients."""
    try:
        data = await request.json()
        client_id = request.headers.get("X-Client-ID", "unknown")
        client_name = request.headers.get("X-Client-Name", "Unknown Device")
        client_ip = request.remote or "unknown"

        # Update or create client
        if client_id not in state.clients:
            state.clients[client_id] = RemoteClient(
                id=client_id,
                name=client_name,
                ip_address=client_ip
            )
        client = state.clients[client_id]
        client.last_seen = time.time()
        client.status = "online"
        client.total_logs += 1

        # Handle single log or batch
        logs = data if isinstance(data, list) else [data]

        for log_data in logs:
            entry = LogEntry(
                id=str(uuid.uuid4()),
                timestamp=log_data.get("timestamp", datetime.utcnow().isoformat() + "Z"),
                level=log_data.get("level", "INFO"),
                label=log_data.get("label", ""),
                message=log_data.get("message", ""),
                file=log_data.get("file", ""),
                function=log_data.get("function", ""),
                line=log_data.get("line", 0),
                metadata=log_data.get("metadata", {}),
                client_id=client_id,
                client_name=client_name
            )
            state.logs.append(entry)
            state.stats["total_logs_received"] += 1

            if entry.level in ("ERROR", "CRITICAL"):
                state.stats["errors_count"] += 1
            elif entry.level == "WARNING":
                state.stats["warnings_count"] += 1

            # Broadcast to WebSocket clients
            await broadcast_message("log", asdict(entry))

        return web.json_response({"status": "ok", "received": len(logs)})

    except Exception as e:
        logger.error(f"Error receiving log: {e}")
        return web.json_response({"error": str(e)}, status=400)


async def handle_get_logs(request: web.Request) -> web.Response:
    """Get log entries with filtering."""
    try:
        # Parse query parameters
        limit = int(request.query.get("limit", "500"))
        offset = int(request.query.get("offset", "0"))
        level = request.query.get("level", "").upper()
        search = request.query.get("search", "").lower()
        client_id = request.query.get("client_id", "")
        label = request.query.get("label", "")
        since = request.query.get("since", "")

        # Filter logs
        filtered = list(state.logs)

        if level:
            levels = level.split(",")
            filtered = [l for l in filtered if l.level in levels]

        if search:
            filtered = [l for l in filtered if search in l.message.lower() or search in l.label.lower()]

        if client_id:
            filtered = [l for l in filtered if l.client_id == client_id]

        if label:
            filtered = [l for l in filtered if label in l.label]

        if since:
            since_ts = float(since)
            filtered = [l for l in filtered if l.received_at > since_ts]

        # Sort by received_at descending (newest first)
        filtered.sort(key=lambda x: x.received_at, reverse=True)

        # Paginate
        total = len(filtered)
        filtered = filtered[offset:offset + limit]

        return web.json_response({
            "logs": [asdict(l) for l in filtered],
            "total": total,
            "limit": limit,
            "offset": offset
        })

    except Exception as e:
        logger.error(f"Error getting logs: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_clear_logs(request: web.Request) -> web.Response:
    """Clear all logs."""
    state.logs.clear()
    state.stats["errors_count"] = 0
    state.stats["warnings_count"] = 0
    await broadcast_message("logs_cleared", {})
    return web.json_response({"status": "ok"})


# =============================================================================
# API Handlers - Metrics
# =============================================================================

async def handle_receive_metrics(request: web.Request) -> web.Response:
    """Receive metrics snapshot from iOS clients."""
    try:
        data = await request.json()
        client_id = request.headers.get("X-Client-ID", "unknown")
        client_name = request.headers.get("X-Client-Name", "Unknown Device")

        # Update client
        if client_id not in state.clients:
            state.clients[client_id] = RemoteClient(
                id=client_id,
                name=client_name,
                ip_address=request.remote or "unknown"
            )
        client = state.clients[client_id]
        client.last_seen = time.time()
        client.status = "online"
        client.total_sessions += 1

        # Create metrics snapshot
        snapshot = MetricsSnapshot(
            id=str(uuid.uuid4()),
            client_id=client_id,
            client_name=client_name,
            timestamp=data.get("timestamp", datetime.utcnow().isoformat() + "Z"),
            received_at=time.time(),
            session_duration=data.get("sessionDuration", 0),
            turns_total=data.get("turnsTotal", 0),
            interruptions=data.get("interruptions", 0),
            stt_latency_median=data.get("sttLatencyMedian", 0),
            stt_latency_p99=data.get("sttLatencyP99", 0),
            llm_ttft_median=data.get("llmTTFTMedian", 0),
            llm_ttft_p99=data.get("llmTTFTP99", 0),
            tts_ttfb_median=data.get("ttsTTFBMedian", 0),
            tts_ttfb_p99=data.get("ttsTTFBP99", 0),
            e2e_latency_median=data.get("e2eLatencyMedian", 0),
            e2e_latency_p99=data.get("e2eLatencyP99", 0),
            stt_cost=data.get("sttCost", 0),
            tts_cost=data.get("ttsCost", 0),
            llm_cost=data.get("llmCost", 0),
            total_cost=data.get("totalCost", 0),
            thermal_throttle_events=data.get("thermalThrottleEvents", 0),
            network_degradations=data.get("networkDegradations", 0),
            raw_data=data
        )

        state.metrics_history.append(snapshot)
        state.stats["total_metrics_received"] += 1

        # Broadcast to WebSocket clients
        await broadcast_message("metrics", asdict(snapshot))

        return web.json_response({"status": "ok"})

    except Exception as e:
        logger.error(f"Error receiving metrics: {e}")
        return web.json_response({"error": str(e)}, status=400)


async def handle_get_metrics(request: web.Request) -> web.Response:
    """Get metrics history."""
    try:
        limit = int(request.query.get("limit", "100"))
        client_id = request.query.get("client_id", "")

        metrics = list(state.metrics_history)

        if client_id:
            metrics = [m for m in metrics if m.client_id == client_id]

        # Sort by received_at descending
        metrics.sort(key=lambda x: x.received_at, reverse=True)
        metrics = metrics[:limit]

        # Calculate aggregates
        if metrics:
            avg_e2e = sum(m.e2e_latency_median for m in metrics) / len(metrics)
            avg_llm = sum(m.llm_ttft_median for m in metrics) / len(metrics)
            avg_stt = sum(m.stt_latency_median for m in metrics) / len(metrics)
            avg_tts = sum(m.tts_ttfb_median for m in metrics) / len(metrics)
            total_cost = sum(m.total_cost for m in metrics)
            total_sessions = len(set(m.id for m in metrics))
            total_turns = sum(m.turns_total for m in metrics)
        else:
            avg_e2e = avg_llm = avg_stt = avg_tts = total_cost = total_sessions = total_turns = 0

        return web.json_response({
            "metrics": [asdict(m) for m in metrics],
            "aggregates": {
                "avg_e2e_latency": round(avg_e2e, 2),
                "avg_llm_ttft": round(avg_llm, 2),
                "avg_stt_latency": round(avg_stt, 2),
                "avg_tts_ttfb": round(avg_tts, 2),
                "total_cost": round(total_cost, 4),
                "total_sessions": total_sessions,
                "total_turns": total_turns
            }
        })

    except Exception as e:
        logger.error(f"Error getting metrics: {e}")
        return web.json_response({"error": str(e)}, status=500)


# =============================================================================
# API Handlers - Remote Clients
# =============================================================================

async def handle_get_clients(request: web.Request) -> web.Response:
    """Get all remote clients."""
    try:
        # Update client statuses based on last_seen
        now = time.time()
        for client in state.clients.values():
            if now - client.last_seen > 300:  # 5 minutes
                client.status = "offline"
            elif now - client.last_seen > 60:  # 1 minute
                client.status = "idle"
            else:
                client.status = "online"

        clients = list(state.clients.values())
        clients.sort(key=lambda x: x.last_seen, reverse=True)

        return web.json_response({
            "clients": [asdict(c) for c in clients],
            "total": len(clients),
            "online": sum(1 for c in clients if c.status == "online"),
            "idle": sum(1 for c in clients if c.status == "idle"),
            "offline": sum(1 for c in clients if c.status == "offline")
        })

    except Exception as e:
        logger.error(f"Error getting clients: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_client_heartbeat(request: web.Request) -> web.Response:
    """Handle client heartbeat/registration."""
    try:
        data = await request.json()
        client_id = data.get("client_id") or request.headers.get("X-Client-ID", str(uuid.uuid4()))

        if client_id not in state.clients:
            state.clients[client_id] = RemoteClient(
                id=client_id,
                name=data.get("name", "Unknown Device"),
                device_model=data.get("device_model", ""),
                os_version=data.get("os_version", ""),
                app_version=data.get("app_version", ""),
                ip_address=request.remote or "unknown"
            )

        client = state.clients[client_id]
        client.last_seen = time.time()
        client.status = "online"
        client.name = data.get("name", client.name)
        client.device_model = data.get("device_model", client.device_model)
        client.os_version = data.get("os_version", client.os_version)
        client.app_version = data.get("app_version", client.app_version)
        client.config = data.get("config", client.config)

        await broadcast_message("client_update", asdict(client))

        return web.json_response({
            "status": "ok",
            "client_id": client_id,
            "server_time": datetime.utcnow().isoformat() + "Z"
        })

    except Exception as e:
        logger.error(f"Error handling heartbeat: {e}")
        return web.json_response({"error": str(e)}, status=400)


# =============================================================================
# API Handlers - Servers
# =============================================================================

async def check_server_health(server: ServerStatus) -> ServerStatus:
    """Check health of a single server."""
    try:
        timeout = aiohttp.ClientTimeout(total=5)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            start = time.time()

            # Determine health endpoint based on server type
            if server.type == "ollama":
                url = f"{server.url}/api/tags"
            elif server.type == "whisper":
                url = f"{server.url}/health"
            elif server.type == "piper":
                url = f"{server.url}/voices"
            else:
                url = f"{server.url}/health"

            async with session.get(url) as response:
                elapsed = (time.time() - start) * 1000
                server.response_time_ms = round(elapsed, 2)
                server.last_check = time.time()

                if response.status == 200:
                    server.status = "healthy"
                    server.error_message = ""

                    # Parse capabilities
                    try:
                        data = await response.json()
                        if server.type == "ollama" and "models" in data:
                            server.models = [m.get("name", "") for m in data.get("models", [])]
                            server.capabilities = {"models": server.models}
                        elif server.type == "piper":
                            server.capabilities = {"voices": data}
                    except:
                        pass
                elif response.status == 503:
                    server.status = "degraded"
                else:
                    server.status = "unhealthy"
                    server.error_message = f"HTTP {response.status}"

    except asyncio.TimeoutError:
        server.status = "unhealthy"
        server.error_message = "Timeout"
        server.last_check = time.time()
    except Exception as e:
        server.status = "unhealthy"
        server.error_message = str(e)
        server.last_check = time.time()

    return server


async def handle_get_servers(request: web.Request) -> web.Response:
    """Get all servers and their status."""
    try:
        # Check health in parallel
        tasks = [check_server_health(s) for s in state.servers.values()]
        await asyncio.gather(*tasks, return_exceptions=True)

        servers = list(state.servers.values())

        return web.json_response({
            "servers": [asdict(s) for s in servers],
            "total": len(servers),
            "healthy": sum(1 for s in servers if s.status == "healthy"),
            "degraded": sum(1 for s in servers if s.status == "degraded"),
            "unhealthy": sum(1 for s in servers if s.status == "unhealthy")
        })

    except Exception as e:
        logger.error(f"Error getting servers: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_add_server(request: web.Request) -> web.Response:
    """Add a new server."""
    try:
        data = await request.json()
        server_id = data.get("id") or str(uuid.uuid4())

        server = ServerStatus(
            id=server_id,
            name=data.get("name", "Custom Server"),
            type=data.get("type", "custom"),
            url=data.get("url", ""),
            port=data.get("port", 8080)
        )

        # Check health immediately
        await check_server_health(server)

        state.servers[server_id] = server
        await broadcast_message("server_added", asdict(server))

        return web.json_response({"status": "ok", "server": asdict(server)})

    except Exception as e:
        logger.error(f"Error adding server: {e}")
        return web.json_response({"error": str(e)}, status=400)


async def handle_delete_server(request: web.Request) -> web.Response:
    """Delete a server."""
    try:
        server_id = request.match_info.get("server_id")
        if server_id in state.servers:
            del state.servers[server_id]
            await broadcast_message("server_deleted", {"id": server_id})
            return web.json_response({"status": "ok"})
        else:
            return web.json_response({"error": "Server not found"}, status=404)

    except Exception as e:
        logger.error(f"Error deleting server: {e}")
        return web.json_response({"error": str(e)}, status=500)


# =============================================================================
# API Handlers - Models
# =============================================================================

async def handle_get_models(request: web.Request) -> web.Response:
    """Get all available models from servers."""
    try:
        models = []

        for server in state.servers.values():
            if server.status == "healthy":
                if server.type == "ollama":
                    for model_name in server.models:
                        models.append({
                            "id": f"{server.id}:{model_name}",
                            "name": model_name,
                            "type": "llm",
                            "server_id": server.id,
                            "server_name": server.name,
                            "status": "available"
                        })
                elif server.type == "whisper":
                    models.append({
                        "id": f"{server.id}:whisper",
                        "name": "Whisper",
                        "type": "stt",
                        "server_id": server.id,
                        "server_name": server.name,
                        "status": "available"
                    })
                elif server.type == "piper":
                    voices = server.capabilities.get("voices", [])
                    for voice in voices[:10]:  # Limit to 10 voices
                        voice_name = voice if isinstance(voice, str) else voice.get("name", "unknown")
                        models.append({
                            "id": f"{server.id}:{voice_name}",
                            "name": voice_name,
                            "type": "tts",
                            "server_id": server.id,
                            "server_name": server.name,
                            "status": "available"
                        })

        return web.json_response({
            "models": models,
            "total": len(models),
            "by_type": {
                "llm": sum(1 for m in models if m["type"] == "llm"),
                "stt": sum(1 for m in models if m["type"] == "stt"),
                "tts": sum(1 for m in models if m["type"] == "tts")
            }
        })

    except Exception as e:
        logger.error(f"Error getting models: {e}")
        return web.json_response({"error": str(e)}, status=500)


# =============================================================================
# API Handlers - Dashboard Stats
# =============================================================================

async def handle_get_stats(request: web.Request) -> web.Response:
    """Get overall dashboard statistics."""
    try:
        now = time.time()
        uptime = now - state.stats["server_start_time"]

        # Calculate metrics from last hour
        hour_ago = now - 3600
        recent_metrics = [m for m in state.metrics_history if m.received_at > hour_ago]
        recent_logs = [l for l in state.logs if l.received_at > hour_ago]

        # Online clients
        online_clients = sum(1 for c in state.clients.values() if c.status == "online")

        # Healthy servers
        healthy_servers = sum(1 for s in state.servers.values() if s.status == "healthy")

        # Average latencies
        if recent_metrics:
            avg_e2e = sum(m.e2e_latency_median for m in recent_metrics) / len(recent_metrics)
            avg_llm = sum(m.llm_ttft_median for m in recent_metrics) / len(recent_metrics)
        else:
            avg_e2e = avg_llm = 0

        return web.json_response({
            "uptime_seconds": round(uptime, 0),
            "total_logs": state.stats["total_logs_received"],
            "total_metrics": state.stats["total_metrics_received"],
            "errors_count": state.stats["errors_count"],
            "warnings_count": state.stats["warnings_count"],
            "logs_last_hour": len(recent_logs),
            "sessions_last_hour": len(recent_metrics),
            "online_clients": online_clients,
            "total_clients": len(state.clients),
            "healthy_servers": healthy_servers,
            "total_servers": len(state.servers),
            "avg_e2e_latency": round(avg_e2e, 2),
            "avg_llm_ttft": round(avg_llm, 2),
            "websocket_connections": len(state.websockets)
        })

    except Exception as e:
        logger.error(f"Error getting stats: {e}")
        return web.json_response({"error": str(e)}, status=500)


# =============================================================================
# WebSocket Handler
# =============================================================================

async def handle_websocket(request: web.Request) -> web.WebSocketResponse:
    """Handle WebSocket connections for real-time updates."""
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    state.websockets.add(ws)
    logger.info(f"WebSocket connected. Total connections: {len(state.websockets)}")

    try:
        # Send initial state
        await ws.send_json({
            "type": "connected",
            "data": {
                "server_time": datetime.utcnow().isoformat() + "Z",
                "stats": {
                    "total_logs": state.stats["total_logs_received"],
                    "online_clients": sum(1 for c in state.clients.values() if c.status == "online")
                }
            }
        })

        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    # Handle client commands if needed
                    if data.get("type") == "ping":
                        await ws.send_json({"type": "pong", "timestamp": time.time()})
                except json.JSONDecodeError:
                    pass
            elif msg.type == aiohttp.WSMsgType.ERROR:
                logger.error(f"WebSocket error: {ws.exception()}")
                break

    finally:
        state.websockets.discard(ws)
        logger.info(f"WebSocket disconnected. Total connections: {len(state.websockets)}")

    return ws


# =============================================================================
# Static Files & Dashboard
# =============================================================================

async def handle_dashboard(request: web.Request) -> web.Response:
    """Serve the main dashboard HTML."""
    static_dir = Path(__file__).parent / "static"
    index_file = static_dir / "index.html"

    if index_file.exists():
        return web.FileResponse(index_file)
    else:
        return web.Response(
            text="Dashboard not found. Please ensure static/index.html exists.",
            status=404
        )


async def handle_health(request: web.Request) -> web.Response:
    """Health check endpoint."""
    return web.json_response({
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "version": "1.0.0"
    })


# =============================================================================
# Application Setup
# =============================================================================

def create_app() -> web.Application:
    """Create and configure the aiohttp application."""
    app = web.Application()

    # CORS middleware
    @web.middleware
    async def cors_middleware(request: web.Request, handler):
        if request.method == "OPTIONS":
            response = web.Response()
        else:
            response = await handler(request)

        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, X-Client-ID, X-Client-Name"
        return response

    app.middlewares.append(cors_middleware)

    # API Routes
    app.router.add_get("/health", handle_health)
    app.router.add_get("/api/stats", handle_get_stats)

    # Logs
    app.router.add_post("/api/logs", handle_receive_log)
    app.router.add_post("/log", handle_receive_log)  # Legacy compatibility
    app.router.add_get("/api/logs", handle_get_logs)
    app.router.add_delete("/api/logs", handle_clear_logs)

    # Metrics
    app.router.add_post("/api/metrics", handle_receive_metrics)
    app.router.add_get("/api/metrics", handle_get_metrics)

    # Clients
    app.router.add_get("/api/clients", handle_get_clients)
    app.router.add_post("/api/clients/heartbeat", handle_client_heartbeat)

    # Servers
    app.router.add_get("/api/servers", handle_get_servers)
    app.router.add_post("/api/servers", handle_add_server)
    app.router.add_delete("/api/servers/{server_id}", handle_delete_server)

    # Models
    app.router.add_get("/api/models", handle_get_models)

    # WebSocket
    app.router.add_get("/ws", handle_websocket)

    # Static files and dashboard
    static_dir = Path(__file__).parent / "static"
    if static_dir.exists():
        app.router.add_static("/static", static_dir)
    app.router.add_get("/", handle_dashboard)

    return app


def main():
    """Main entry point."""
    print(f"""
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║   ██╗   ██╗ ██████╗ ██╗ ██████╗███████╗                     ║
║   ██║   ██║██╔═══██╗██║██╔════╝██╔════╝                     ║
║   ██║   ██║██║   ██║██║██║     █████╗                       ║
║   ╚██╗ ██╔╝██║   ██║██║██║     ██╔══╝                       ║
║    ╚████╔╝ ╚██████╔╝██║╚██████╗███████╗                     ║
║     ╚═══╝   ╚═════╝ ╚═╝ ╚═════╝╚══════╝                     ║
║                                                              ║
║   ██╗     ███████╗ █████╗ ██████╗ ███╗   ██╗                ║
║   ██║     ██╔════╝██╔══██╗██╔══██╗████╗  ██║                ║
║   ██║     █████╗  ███████║██████╔╝██╔██╗ ██║                ║
║   ██║     ██╔══╝  ██╔══██║██╔══██╗██║╚██╗██║                ║
║   ███████╗███████╗██║  ██║██║  ██║██║ ╚████║                ║
║   ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝                ║
║                                                              ║
║              Web Management Interface v1.0                   ║
║                                                              ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  Dashboard:  http://{HOST}:{PORT}/
║  API:        http://{HOST}:{PORT}/api/
║  WebSocket:  ws://{HOST}:{PORT}/ws
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
""")

    app = create_app()
    web.run_app(app, host=HOST, port=PORT, print=None)


if __name__ == "__main__":
    main()
