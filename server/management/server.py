#!/usr/bin/env python3
"""
UnaMentis Web Management Server
A next-generation management interface for monitoring and configuring UnaMentis services.
"""

import asyncio
import json
import logging
import os
import signal
import subprocess
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

# Service paths (relative to unamentis-ios root)
PROJECT_ROOT = Path(__file__).parent.parent.parent
VIBEVOICE_DIR = PROJECT_ROOT.parent / "vibevoice-realtime-openai-api"
NEXTJS_DIR = PROJECT_ROOT / "server" / "web"

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


@dataclass
class ManagedService:
    """Represents a managed subprocess service."""
    id: str
    name: str
    service_type: str  # vibevoice, nextjs
    command: List[str]
    cwd: str
    port: int
    health_url: str
    process: Optional[subprocess.Popen] = None
    status: str = "stopped"  # stopped, starting, running, error
    pid: Optional[int] = None
    started_at: Optional[float] = None
    error_message: str = ""
    auto_restart: bool = True


@dataclass
class CurriculumSummary:
    """Summary of a curriculum for listing/browsing."""
    id: str
    title: str
    description: str
    version: str
    topic_count: int
    total_duration: str
    difficulty: str
    age_range: str
    keywords: List[str] = field(default_factory=list)
    file_path: str = ""
    loaded_at: float = field(default_factory=time.time)


@dataclass
class TopicSummary:
    """Summary of a topic within a curriculum."""
    id: str
    title: str
    description: str
    order_index: int
    duration: str
    has_transcript: bool = False
    segment_count: int = 0
    assessment_count: int = 0


@dataclass
class CurriculumDetail:
    """Full curriculum detail including topics."""
    id: str
    title: str
    description: str
    version: str
    difficulty: str
    age_range: str
    duration: str
    keywords: List[str]
    topics: List[TopicSummary]
    glossary_terms: List[Dict[str, Any]]
    learning_objectives: List[Dict[str, Any]]
    raw_umlcf: Dict[str, Any] = field(default_factory=dict)


class ManagementState:
    """Global state for the management server."""

    def __init__(self):
        self.logs: deque = deque(maxlen=MAX_LOG_ENTRIES)
        self.metrics_history: deque = deque(maxlen=MAX_METRICS_HISTORY)
        self.clients: Dict[str, RemoteClient] = {}
        self.servers: Dict[str, ServerStatus] = {}
        self.models: Dict[str, ModelInfo] = {}
        self.managed_services: Dict[str, ManagedService] = {}
        self.websockets: Set[web.WebSocketResponse] = set()
        # Curriculum storage
        self.curriculums: Dict[str, CurriculumSummary] = {}
        self.curriculum_details: Dict[str, CurriculumDetail] = {}
        self.curriculum_raw: Dict[str, Dict[str, Any]] = {}  # Full UMLCF data by ID
        self.stats = {
            "total_logs_received": 0,
            "total_metrics_received": 0,
            "server_start_time": time.time(),
            "errors_count": 0,
            "warnings_count": 0,
        }
        # Initialize default servers
        self._init_default_servers()
        # Initialize managed services
        self._init_managed_services()
        # Load curricula from disk
        self._load_curricula()

    def _init_default_servers(self):
        """Initialize default server configurations."""
        default_servers = [
            ("gateway", "UnaMentis Gateway", "unamentisGateway", "localhost", 11400),
            ("ollama", "Ollama LLM", "ollama", "localhost", 11434),
            ("whisper", "Whisper STT", "whisper", "localhost", 11401),
            ("piper", "Piper TTS", "piper", "localhost", 11402),
            ("vibevoice", "VibeVoice TTS", "vibevoice", "localhost", 8880),
            ("nextjs", "Web Dashboard", "nextjs", "localhost", 3000),
        ]
        for server_id, name, server_type, host, port in default_servers:
            self.servers[server_id] = ServerStatus(
                id=server_id,
                name=name,
                type=server_type,
                url=f"http://{host}:{port}",
                port=port
            )

    def _init_managed_services(self):
        """Initialize managed service configurations."""
        # VibeVoice TTS Server
        vibevoice_venv = VIBEVOICE_DIR / ".venv" / "bin" / "python"
        vibevoice_script = VIBEVOICE_DIR / "vibevoice_realtime_openai_api.py"

        if VIBEVOICE_DIR.exists():
            self.managed_services["vibevoice"] = ManagedService(
                id="vibevoice",
                name="VibeVoice TTS",
                service_type="vibevoice",
                command=[
                    str(vibevoice_venv) if vibevoice_venv.exists() else "python3",
                    str(vibevoice_script),
                    "--port", "8880",
                    "--device", "mps"
                ],
                cwd=str(VIBEVOICE_DIR),
                port=8880,
                health_url="http://localhost:8880/health"
            )

        # Next.js Dashboard
        if NEXTJS_DIR.exists():
            self.managed_services["nextjs"] = ManagedService(
                id="nextjs",
                name="Web Dashboard",
                service_type="nextjs",
                command=["npx", "next", "dev"],
                cwd=str(NEXTJS_DIR),
                port=3000,
                health_url="http://localhost:3000"
            )

    def _load_curricula(self):
        """Load all UMLCF curriculum files from the curriculum directory."""
        curriculum_dir = PROJECT_ROOT / "curriculum" / "examples" / "realistic"
        if not curriculum_dir.exists():
            logger.warning(f"Curriculum directory not found: {curriculum_dir}")
            return

        for umlcf_file in curriculum_dir.glob("*.umlcf"):
            try:
                self._load_curriculum_file(umlcf_file)
            except Exception as e:
                logger.error(f"Failed to load curriculum {umlcf_file}: {e}")

        logger.info(f"Loaded {len(self.curriculums)} curricula")

    def _load_curriculum_file(self, file_path: Path):
        """Load a single UMLCF file and extract summary/details."""
        with open(file_path, 'r', encoding='utf-8') as f:
            umlcf = json.load(f)

        # Extract ID from the UMLCF or generate from filename
        umlcf_id = umlcf.get("id", {}).get("value", file_path.stem)

        # Extract educational metadata
        educational = umlcf.get("educational", {})
        version_info = umlcf.get("version", {})

        # Count topics and calculate duration
        content = umlcf.get("content", [])
        topic_count = 0
        topics = []
        if content and isinstance(content, list):
            root = content[0]
            children = root.get("children", [])
            topic_count = len(children)

            for idx, child in enumerate(children):
                time_estimates = child.get("timeEstimates", {})
                duration = time_estimates.get("intermediate", time_estimates.get("introductory", "PT30M"))
                transcript = child.get("transcript", {})
                segments = transcript.get("segments", [])
                assessments = child.get("assessments", [])

                topics.append(TopicSummary(
                    id=child.get("id", {}).get("value", f"topic-{idx}"),
                    title=child.get("title", "Untitled"),
                    description=child.get("description", ""),
                    order_index=child.get("orderIndex", idx),
                    duration=duration,
                    has_transcript=len(segments) > 0,
                    segment_count=len(segments),
                    assessment_count=len(assessments)
                ))

        # Extract glossary
        glossary = umlcf.get("glossary", {}).get("terms", [])

        # Extract learning objectives from root content
        learning_objectives = []
        if content and isinstance(content, list):
            root = content[0]
            learning_objectives = root.get("learningObjectives", [])

        # Create summary for listing
        summary = CurriculumSummary(
            id=umlcf_id,
            title=umlcf.get("title", "Untitled"),
            description=umlcf.get("description", ""),
            version=version_info.get("number", "1.0.0"),
            topic_count=topic_count,
            total_duration=educational.get("typicalLearningTime", "PT4H"),
            difficulty=educational.get("difficulty", "medium"),
            age_range=educational.get("typicalAgeRange", "18+"),
            keywords=umlcf.get("metadata", {}).get("keywords", []),
            file_path=str(file_path)
        )

        # Create detailed view
        detail = CurriculumDetail(
            id=umlcf_id,
            title=umlcf.get("title", "Untitled"),
            description=umlcf.get("description", ""),
            version=version_info.get("number", "1.0.0"),
            difficulty=educational.get("difficulty", "medium"),
            age_range=educational.get("typicalAgeRange", "18+"),
            duration=educational.get("typicalLearningTime", "PT4H"),
            keywords=umlcf.get("metadata", {}).get("keywords", []),
            topics=[asdict(t) for t in topics],
            glossary_terms=glossary,
            learning_objectives=learning_objectives,
            raw_umlcf=umlcf
        )

        self.curriculums[umlcf_id] = summary
        self.curriculum_details[umlcf_id] = detail
        self.curriculum_raw[umlcf_id] = umlcf

    def reload_curricula(self):
        """Reload all curricula from disk."""
        self.curriculums.clear()
        self.curriculum_details.clear()
        self.curriculum_raw.clear()
        self._load_curricula()


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

async def get_ollama_model_details() -> dict:
    """Get detailed model info from Ollama including sizes and loaded status."""
    model_details = {}
    loaded_models = {}

    try:
        timeout = aiohttp.ClientTimeout(total=5)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            # Get model tags (includes sizes)
            async with session.get("http://localhost:11434/api/tags") as response:
                if response.status == 200:
                    data = await response.json()
                    for model in data.get("models", []):
                        name = model.get("name", "")
                        model_details[name] = {
                            "size_bytes": model.get("size", 0),
                            "size_gb": round(model.get("size", 0) / (1024**3), 2),
                            "parameter_size": model.get("details", {}).get("parameter_size", ""),
                            "quantization": model.get("details", {}).get("quantization_level", ""),
                            "family": model.get("details", {}).get("family", "")
                        }

            # Get currently loaded models (includes VRAM usage)
            async with session.get("http://localhost:11434/api/ps") as response:
                if response.status == 200:
                    data = await response.json()
                    for model in data.get("models", []):
                        name = model.get("name", "")
                        loaded_models[name] = {
                            "loaded": True,
                            "size_vram": model.get("size_vram", 0),
                            "size_vram_gb": round(model.get("size_vram", 0) / (1024**3), 2),
                            "expires_at": model.get("expires_at", "")
                        }
    except Exception as e:
        logger.debug(f"Failed to get Ollama model details: {e}")

    return {"details": model_details, "loaded": loaded_models}


async def handle_get_models(request: web.Request) -> web.Response:
    """Get all available models from servers."""
    try:
        models = []
        total_size_bytes = 0
        total_loaded_vram = 0

        # Get Ollama model details
        ollama_info = await get_ollama_model_details()

        for srv in state.servers.values():
            if srv.status == "healthy":
                if srv.type == "ollama":
                    for model_name in srv.models:
                        details = ollama_info["details"].get(model_name, {})
                        loaded_info = ollama_info["loaded"].get(model_name, {})
                        is_loaded = model_name in ollama_info["loaded"]

                        size_bytes = details.get("size_bytes", 0)
                        total_size_bytes += size_bytes
                        if is_loaded:
                            total_loaded_vram += loaded_info.get("size_vram", 0)

                        models.append({
                            "id": f"{srv.id}:{model_name}",
                            "name": model_name,
                            "type": "llm",
                            "server_id": srv.id,
                            "server_name": srv.name,
                            "status": "loaded" if is_loaded else "available",
                            "size_bytes": size_bytes,
                            "size_gb": details.get("size_gb", 0),
                            "parameter_size": details.get("parameter_size", ""),
                            "quantization": details.get("quantization", ""),
                            "family": details.get("family", ""),
                            "vram_bytes": loaded_info.get("size_vram", 0) if is_loaded else 0,
                            "vram_gb": loaded_info.get("size_vram_gb", 0) if is_loaded else 0
                        })
                elif srv.type == "whisper":
                    models.append({
                        "id": f"{srv.id}:whisper",
                        "name": "Whisper",
                        "type": "stt",
                        "server_id": srv.id,
                        "server_name": srv.name,
                        "status": "available",
                        "size_bytes": 0,
                        "size_gb": 0
                    })
                elif srv.type == "piper":
                    # Piper voices can be nested: {"voices": {"voices": [...]}}
                    try:
                        voices_data = srv.capabilities.get("voices", {})
                        if isinstance(voices_data, dict):
                            voices = voices_data.get("voices", [])
                        else:
                            voices = voices_data if isinstance(voices_data, list) else []

                        if not isinstance(voices, list):
                            voices = []

                        for voice in list(voices)[:10]:  # Limit to 10 voices
                            voice_name = voice if isinstance(voice, str) else voice.get("name", "unknown")
                            models.append({
                                "id": f"{srv.id}:{voice_name}",
                                "name": voice_name,
                                "type": "tts",
                                "server_id": srv.id,
                                "server_name": srv.name,
                                "status": "available",
                                "size_bytes": 0,
                                "size_gb": 0
                            })
                    except Exception as e:
                        logger.warning(f"Failed to parse piper voices: {e}")
                elif srv.type == "vibevoice":
                    # VibeVoice model info
                    models.append({
                        "id": f"{srv.id}:vibevoice",
                        "name": "VibeVoice-Realtime-0.5B",
                        "type": "tts",
                        "server_id": srv.id,
                        "server_name": srv.name,
                        "status": "loaded",
                        "size_bytes": 2 * 1024**3,  # ~2GB
                        "size_gb": 2.0,
                        "parameter_size": "0.5B"
                    })

        return web.json_response({
            "models": models,
            "total": len(models),
            "by_type": {
                "llm": sum(1 for m in models if m["type"] == "llm"),
                "stt": sum(1 for m in models if m["type"] == "stt"),
                "tts": sum(1 for m in models if m["type"] == "tts")
            },
            "total_size_gb": round(total_size_bytes / (1024**3), 2),
            "loaded_vram_gb": round(total_loaded_vram / (1024**3), 2),
            "system_memory": get_system_memory()
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
# API Handlers - Managed Services
# =============================================================================

def get_process_memory(pid: int) -> dict:
    """Get memory usage for a process by PID."""
    try:
        result = subprocess.run(
            ["ps", "-o", "rss=,vsz=", "-p", str(pid)],
            capture_output=True,
            text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split()
            if len(parts) >= 2:
                rss_kb = int(parts[0])
                vsz_kb = int(parts[1])
                return {
                    "rss_mb": round(rss_kb / 1024, 1),
                    "vsz_mb": round(vsz_kb / 1024, 1),
                    "rss_bytes": rss_kb * 1024,
                    "vsz_bytes": vsz_kb * 1024
                }
    except Exception as e:
        logger.debug(f"Failed to get memory for PID {pid}: {e}")
    return {"rss_mb": 0, "vsz_mb": 0, "rss_bytes": 0, "vsz_bytes": 0}


def get_system_memory() -> dict:
    """Get system memory info (unified memory on Apple Silicon)."""
    try:
        # Use vm_stat for macOS
        result = subprocess.run(["vm_stat"], capture_output=True, text=True)
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            stats = {}
            page_size = 16384  # Default for Apple Silicon
            for line in lines:
                if ':' in line:
                    key, value = line.split(':', 1)
                    value = value.strip().rstrip('.')
                    try:
                        stats[key.strip()] = int(value)
                    except ValueError:
                        pass

            # Calculate memory in bytes
            free_pages = stats.get('Pages free', 0)
            active_pages = stats.get('Pages active', 0)
            inactive_pages = stats.get('Pages inactive', 0)
            wired_pages = stats.get('Pages wired down', 0)
            compressed_pages = stats.get('Pages occupied by compressor', 0)

            # Also get total memory from sysctl
            sysctl_result = subprocess.run(
                ["sysctl", "-n", "hw.memsize"],
                capture_output=True,
                text=True
            )
            total_bytes = int(sysctl_result.stdout.strip()) if sysctl_result.returncode == 0 else 0

            used_bytes = (active_pages + wired_pages + compressed_pages) * page_size
            free_bytes = free_pages * page_size

            return {
                "total_gb": round(total_bytes / (1024**3), 1),
                "used_gb": round(used_bytes / (1024**3), 1),
                "free_gb": round(free_bytes / (1024**3), 1),
                "percent_used": round((used_bytes / total_bytes) * 100, 1) if total_bytes > 0 else 0,
                "total_bytes": total_bytes,
                "used_bytes": used_bytes
            }
    except Exception as e:
        logger.debug(f"Failed to get system memory: {e}")
    return {"total_gb": 0, "used_gb": 0, "free_gb": 0, "percent_used": 0}


def service_to_dict(service: ManagedService) -> dict:
    """Convert ManagedService to JSON-serializable dict."""
    memory = get_process_memory(service.pid) if service.pid else {"rss_mb": 0, "vsz_mb": 0}
    return {
        "id": service.id,
        "name": service.name,
        "service_type": service.service_type,
        "port": service.port,
        "status": service.status,
        "pid": service.pid,
        "started_at": service.started_at,
        "error_message": service.error_message,
        "auto_restart": service.auto_restart,
        "health_url": service.health_url,
        "memory": memory
    }


async def check_service_running(service: ManagedService) -> bool:
    """Check if a service is running by checking its health endpoint."""
    try:
        timeout = aiohttp.ClientTimeout(total=2)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(service.health_url) as response:
                return response.status == 200
    except Exception:
        return False


async def detect_existing_processes():
    """Detect if managed services are already running (started externally)."""
    for service_id, service in state.managed_services.items():
        if service.status == "stopped":
            is_running = await check_service_running(service)
            if is_running:
                service.status = "running"
                service.started_at = time.time()
                # Try to find the PID
                try:
                    result = subprocess.run(
                        ["lsof", "-t", "-i", f":{service.port}"],
                        capture_output=True,
                        text=True
                    )
                    if result.stdout.strip():
                        service.pid = int(result.stdout.strip().split()[0])
                except Exception:
                    pass
                logger.info(f"Detected running service: {service.name} on port {service.port}")


async def start_service(service_id: str) -> tuple[bool, str]:
    """Start a managed service."""
    if service_id not in state.managed_services:
        return False, f"Service {service_id} not found"

    service = state.managed_services[service_id]

    # Check if already running
    if service.process and service.process.poll() is None:
        return False, "Service is already running"

    # Check if port is in use
    is_running = await check_service_running(service)
    if is_running:
        service.status = "running"
        return False, "Service is already running on port"

    try:
        service.status = "starting"
        service.error_message = ""
        await broadcast_message("service_update", service_to_dict(service))

        # Prepare environment
        env = os.environ.copy()
        if service.service_type == "vibevoice":
            env["CFG_SCALE"] = "1.25"

        # Start the process
        logger.info(f"Starting service: {service.name}")
        logger.info(f"Command: {' '.join(service.command)}")
        logger.info(f"CWD: {service.cwd}")

        service.process = subprocess.Popen(
            service.command,
            cwd=service.cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True  # Detach from parent
        )
        service.pid = service.process.pid
        service.started_at = time.time()

        # Wait a bit and check if it's running
        await asyncio.sleep(2)

        if service.process.poll() is not None:
            # Process exited
            output = service.process.stdout.read().decode() if service.process.stdout else ""
            service.status = "error"
            service.error_message = f"Process exited with code {service.process.returncode}: {output[:500]}"
            await broadcast_message("service_update", service_to_dict(service))
            return False, service.error_message

        service.status = "running"
        await broadcast_message("service_update", service_to_dict(service))
        logger.info(f"Service {service.name} started with PID {service.pid}")
        return True, f"Service started with PID {service.pid}"

    except Exception as e:
        service.status = "error"
        service.error_message = str(e)
        await broadcast_message("service_update", service_to_dict(service))
        logger.error(f"Failed to start service {service.name}: {e}")
        return False, str(e)


async def stop_service(service_id: str) -> tuple[bool, str]:
    """Stop a managed service."""
    if service_id not in state.managed_services:
        return False, f"Service {service_id} not found"

    service = state.managed_services[service_id]

    try:
        # Try to kill by PID if we have it
        if service.pid:
            try:
                os.kill(service.pid, signal.SIGTERM)
                await asyncio.sleep(1)
                # Check if still running
                try:
                    os.kill(service.pid, 0)
                    # Still running, force kill
                    os.kill(service.pid, signal.SIGKILL)
                except OSError:
                    pass  # Process already dead
            except OSError as e:
                logger.warning(f"Could not kill PID {service.pid}: {e}")

        # Also try to kill by port
        try:
            result = subprocess.run(
                ["lsof", "-t", "-i", f":{service.port}"],
                capture_output=True,
                text=True
            )
            if result.stdout.strip():
                for pid_str in result.stdout.strip().split():
                    try:
                        pid = int(pid_str)
                        os.kill(pid, signal.SIGTERM)
                    except (ValueError, OSError):
                        pass
        except Exception:
            pass

        # Clean up process reference
        if service.process:
            try:
                service.process.terminate()
                service.process.wait(timeout=5)
            except Exception:
                try:
                    service.process.kill()
                except Exception:
                    pass
            service.process = None

        service.status = "stopped"
        service.pid = None
        service.started_at = None
        await broadcast_message("service_update", service_to_dict(service))
        logger.info(f"Service {service.name} stopped")
        return True, "Service stopped"

    except Exception as e:
        service.error_message = str(e)
        await broadcast_message("service_update", service_to_dict(service))
        logger.error(f"Failed to stop service {service.name}: {e}")
        return False, str(e)


async def handle_get_services(request: web.Request) -> web.Response:
    """Get all managed services and their status."""
    try:
        # Update status of all services
        for service in state.managed_services.values():
            if service.status == "running":
                is_running = await check_service_running(service)
                if not is_running:
                    # Check if process is still alive
                    if service.process and service.process.poll() is not None:
                        service.status = "error"
                        service.error_message = f"Process exited with code {service.process.returncode}"
                    else:
                        service.status = "error"
                        service.error_message = "Health check failed"

        services = [service_to_dict(s) for s in state.managed_services.values()]

        # Calculate total memory used by services
        total_memory_mb = sum(s.get("memory", {}).get("rss_mb", 0) for s in services)

        return web.json_response({
            "services": services,
            "total": len(services),
            "running": sum(1 for s in state.managed_services.values() if s.status == "running"),
            "stopped": sum(1 for s in state.managed_services.values() if s.status == "stopped"),
            "error": sum(1 for s in state.managed_services.values() if s.status == "error"),
            "total_memory_mb": round(total_memory_mb, 1),
            "system_memory": get_system_memory()
        })

    except Exception as e:
        logger.error(f"Error getting services: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_start_service(request: web.Request) -> web.Response:
    """Start a managed service."""
    try:
        service_id = request.match_info.get("service_id")
        success, message = await start_service(service_id)

        if success:
            return web.json_response({"status": "ok", "message": message})
        else:
            return web.json_response({"status": "error", "message": message}, status=400)

    except Exception as e:
        logger.error(f"Error starting service: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_stop_service(request: web.Request) -> web.Response:
    """Stop a managed service."""
    try:
        service_id = request.match_info.get("service_id")
        success, message = await stop_service(service_id)

        if success:
            return web.json_response({"status": "ok", "message": message})
        else:
            return web.json_response({"status": "error", "message": message}, status=400)

    except Exception as e:
        logger.error(f"Error stopping service: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_restart_service(request: web.Request) -> web.Response:
    """Restart a managed service."""
    try:
        service_id = request.match_info.get("service_id")

        # Stop first
        await stop_service(service_id)
        await asyncio.sleep(1)

        # Then start
        success, message = await start_service(service_id)

        if success:
            return web.json_response({"status": "ok", "message": message})
        else:
            return web.json_response({"status": "error", "message": message}, status=400)

    except Exception as e:
        logger.error(f"Error restarting service: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_start_all_services(request: web.Request) -> web.Response:
    """Start all managed services."""
    try:
        results = {}
        for service_id in state.managed_services:
            success, message = await start_service(service_id)
            results[service_id] = {"success": success, "message": message}

        return web.json_response({"status": "ok", "results": results})

    except Exception as e:
        logger.error(f"Error starting all services: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_stop_all_services(request: web.Request) -> web.Response:
    """Stop all managed services."""
    try:
        results = {}
        for service_id in state.managed_services:
            success, message = await stop_service(service_id)
            results[service_id] = {"success": success, "message": message}

        return web.json_response({"status": "ok", "results": results})

    except Exception as e:
        logger.error(f"Error stopping all services: {e}")
        return web.json_response({"error": str(e)}, status=500)


# =============================================================================
# API Handlers - Curriculum
# =============================================================================

async def handle_get_curricula(request: web.Request) -> web.Response:
    """Get list of available curricula."""
    try:
        search = request.query.get("search", "").lower()
        difficulty = request.query.get("difficulty", "")

        curricula = list(state.curriculums.values())

        # Apply filters
        if search:
            curricula = [
                c for c in curricula
                if search in c.title.lower() or search in c.description.lower()
                or any(search in kw.lower() for kw in c.keywords)
            ]

        if difficulty:
            curricula = [c for c in curricula if c.difficulty == difficulty]

        return web.json_response({
            "curricula": [asdict(c) for c in curricula],
            "total": len(curricula)
        })

    except Exception as e:
        logger.error(f"Error getting curricula: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_curriculum_detail(request: web.Request) -> web.Response:
    """Get detailed curriculum info including topics."""
    try:
        curriculum_id = request.match_info.get("curriculum_id")

        if curriculum_id not in state.curriculum_details:
            return web.json_response({"error": "Curriculum not found"}, status=404)

        detail = state.curriculum_details[curriculum_id]
        # Don't include raw_umlcf in detail response (it's huge)
        result = asdict(detail)
        del result["raw_umlcf"]

        return web.json_response(result)

    except Exception as e:
        logger.error(f"Error getting curriculum detail: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_curriculum_full(request: web.Request) -> web.Response:
    """Get full UMLCF data for a curriculum (for iOS download)."""
    try:
        curriculum_id = request.match_info.get("curriculum_id")

        if curriculum_id not in state.curriculum_raw:
            return web.json_response({"error": "Curriculum not found"}, status=404)

        return web.json_response(state.curriculum_raw[curriculum_id])

    except Exception as e:
        logger.error(f"Error getting curriculum full: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_topic_transcript(request: web.Request) -> web.Response:
    """Get transcript segments for a specific topic."""
    try:
        curriculum_id = request.match_info.get("curriculum_id")
        topic_id = request.match_info.get("topic_id")

        if curriculum_id not in state.curriculum_raw:
            return web.json_response({"error": "Curriculum not found"}, status=404)

        umlcf = state.curriculum_raw[curriculum_id]
        content = umlcf.get("content", [])

        if not content:
            return web.json_response({"error": "No content in curriculum"}, status=404)

        # Find the topic
        root = content[0]
        children = root.get("children", [])

        for child in children:
            child_id = child.get("id", {}).get("value", "")
            if child_id == topic_id:
                transcript = child.get("transcript", {})
                # Extract segments directly for iOS client compatibility
                segments = transcript.get("segments", []) if isinstance(transcript, dict) else []
                return web.json_response({
                    "topic_id": topic_id,
                    "topic_title": child.get("title", ""),
                    "segments": segments,
                    "misconceptions": child.get("misconceptions", []),
                    "examples": child.get("examples", []),
                    "assessments": child.get("assessments", [])
                })

        return web.json_response({"error": "Topic not found"}, status=404)

    except Exception as e:
        logger.error(f"Error getting topic transcript: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_stream_topic_audio(request: web.Request) -> web.StreamResponse:
    """Stream audio for a topic's transcript segments.

    This endpoint bypasses the LLM and directly converts transcript text to audio,
    enabling near-instant playback of pre-written curriculum content.

    Query params:
        voice: TTS voice ID (default: "nova")
        tts_server: TTS server to use - "vibevoice" (default) or "piper"
    """
    try:
        curriculum_id = request.match_info.get("curriculum_id")
        topic_id = request.match_info.get("topic_id")
        voice = request.query.get("voice", "nova")
        tts_server = request.query.get("tts_server", "vibevoice")

        logger.info(f"Stream topic audio: curriculum={curriculum_id}, topic={topic_id}, voice={voice}, tts={tts_server}")

        if curriculum_id not in state.curriculum_raw:
            return web.json_response({"error": "Curriculum not found"}, status=404)

        umlcf = state.curriculum_raw[curriculum_id]
        content = umlcf.get("content", [])

        if not content:
            return web.json_response({"error": "No content in curriculum"}, status=404)

        # Find the topic
        root = content[0]
        children = root.get("children", [])
        transcript_segments = None
        topic_title = ""

        for child in children:
            child_id = child.get("id", {}).get("value", "")
            if child_id == topic_id:
                transcript = child.get("transcript", {})
                transcript_segments = transcript.get("segments", []) if isinstance(transcript, dict) else []
                topic_title = child.get("title", "")
                break

        if transcript_segments is None:
            return web.json_response({"error": "Topic not found"}, status=404)

        if not transcript_segments:
            return web.json_response({"error": "Topic has no transcript segments"}, status=404)

        # Determine TTS server URL
        if tts_server == "piper":
            tts_url = "http://localhost:11402/v1/audio/speech"
        else:  # vibevoice
            tts_url = "http://localhost:8880/v1/audio/speech"

        # Create streaming response
        response = web.StreamResponse(
            status=200,
            reason="OK",
            headers={
                "Content-Type": "application/octet-stream",
                "X-Topic-Title": topic_title,
                "X-Segment-Count": str(len(transcript_segments)),
                "Transfer-Encoding": "chunked"
            }
        )
        await response.prepare(request)

        # Stream audio for each segment
        for idx, segment in enumerate(transcript_segments):
            segment_text = segment.get("content", "")
            segment_type = segment.get("type", "narration")

            if not segment_text.strip():
                continue

            logger.info(f"  Segment {idx + 1}/{len(transcript_segments)}: {segment_type}, {len(segment_text)} chars")

            # Send segment metadata as a header chunk
            meta_header = f"SEG:{idx}:{segment_type}:{len(segment_text)}\n".encode('utf-8')
            await response.write(meta_header)

            # Request TTS for this segment
            try:
                async with aiohttp.ClientSession() as session:
                    tts_payload = {
                        "model": "tts-1",
                        "input": segment_text,
                        "voice": voice,
                        "response_format": "wav"
                    }

                    async with session.post(tts_url, json=tts_payload, timeout=aiohttp.ClientTimeout(total=30)) as tts_response:
                        if tts_response.status == 200:
                            # Stream audio data as it arrives
                            audio_data = await tts_response.read()

                            # Send audio size header
                            size_header = f"AUD:{len(audio_data)}\n".encode('utf-8')
                            await response.write(size_header)

                            # Send audio data in chunks
                            chunk_size = 8192
                            for i in range(0, len(audio_data), chunk_size):
                                chunk = audio_data[i:i + chunk_size]
                                await response.write(chunk)

                            logger.info(f"    Sent {len(audio_data)} bytes of audio")
                        else:
                            error_text = await tts_response.text()
                            logger.error(f"    TTS error: {tts_response.status} - {error_text}")
                            # Send error marker
                            await response.write(f"ERR:{tts_response.status}\n".encode('utf-8'))

            except Exception as e:
                logger.error(f"    TTS request failed: {e}")
                await response.write(f"ERR:{str(e)}\n".encode('utf-8'))

        # Send end marker
        await response.write(b"END\n")
        await response.write_eof()

        logger.info(f"Completed streaming {len(transcript_segments)} segments for topic {topic_id}")
        return response

    except Exception as e:
        logger.error(f"Error streaming topic audio: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_reload_curricula(request: web.Request) -> web.Response:
    """Reload all curricula from disk."""
    try:
        state.reload_curricula()
        await broadcast_message("curricula_reloaded", {
            "count": len(state.curriculums)
        })
        return web.json_response({
            "status": "ok",
            "count": len(state.curriculums)
        })

    except Exception as e:
        logger.error(f"Error reloading curricula: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_save_curriculum(request: web.Request) -> web.Response:
    """Save/update a curriculum VLCF file."""
    try:
        curriculum_id = request.match_info.get("curriculum_id")
        data = await request.json()

        # Validate it's valid UMLCF (basic check)
        if "umlcf" not in data or "title" not in data:
            return web.json_response({"error": "Invalid UMLCF data"}, status=400)

        # Determine file path
        if curriculum_id in state.curriculums:
            file_path = Path(state.curriculums[curriculum_id].file_path)
        else:
            # New curriculum - create filename from title
            safe_name = "".join(c if c.isalnum() or c in "-_" else "-" for c in data["title"].lower())
            file_path = PROJECT_ROOT / "curriculum" / "examples" / "realistic" / f"{safe_name}.umlcf"

        # Write the file
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)

        # Reload the curriculum
        state._load_curriculum_file(file_path)

        await broadcast_message("curriculum_updated", {
            "id": curriculum_id,
            "title": data.get("title")
        })

        return web.json_response({
            "status": "ok",
            "id": data.get("id", {}).get("value", file_path.stem),
            "file_path": str(file_path)
        })

    except Exception as e:
        logger.error(f"Error saving curriculum: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_import_curriculum(request: web.Request) -> web.Response:
    """Import a curriculum from URL or direct content."""
    try:
        data = await request.json()
        umlcf_data = None
        source_url = None

        # Import from URL
        if "url" in data:
            source_url = data["url"]
            logger.info(f"Importing curriculum from URL: {source_url}")

            import aiohttp
            async with aiohttp.ClientSession() as session:
                async with session.get(source_url, timeout=aiohttp.ClientTimeout(total=30)) as response:
                    if response.status != 200:
                        return web.json_response(
                            {"error": f"Failed to fetch URL: HTTP {response.status}"},
                            status=400
                        )
                    content = await response.text()
                    try:
                        umlcf_data = json.loads(content)
                    except json.JSONDecodeError as e:
                        return web.json_response(
                            {"error": f"Invalid JSON at URL: {str(e)}"},
                            status=400
                        )

        # Import from direct content
        elif "content" in data:
            umlcf_data = data["content"]
            logger.info("Importing curriculum from direct content")

        else:
            return web.json_response(
                {"error": "Must provide 'url' or 'content'"},
                status=400
            )

        # Validate UMLCF format
        if not isinstance(umlcf_data, dict):
            return web.json_response({"error": "Content must be a JSON object"}, status=400)

        if umlcf_data.get("formatIdentifier") != "umlcf":
            return web.json_response(
                {"error": "Invalid format: formatIdentifier must be 'umlcf'"},
                status=400
            )

        # Extract title for filename
        metadata = umlcf_data.get("metadata", {})
        title = metadata.get("title", "Imported Curriculum")
        curriculum_id = umlcf_data.get("id", {}).get("value", "")

        # Create safe filename
        safe_name = "".join(c if c.isalnum() or c in "-_" else "-" for c in title.lower())
        if not safe_name:
            safe_name = f"imported-{int(time.time())}"

        # Determine destination path
        curriculum_dir = PROJECT_ROOT / "curriculum" / "examples" / "realistic"
        curriculum_dir.mkdir(parents=True, exist_ok=True)

        file_path = curriculum_dir / f"{safe_name}.umlcf"

        # Handle duplicate filenames
        counter = 1
        while file_path.exists():
            file_path = curriculum_dir / f"{safe_name}-{counter}.umlcf"
            counter += 1

        # Write the file
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(umlcf_data, f, indent=2, ensure_ascii=False)

        logger.info(f"Saved imported curriculum to: {file_path}")

        # Load into state
        state._load_curriculum_file(file_path)

        # Broadcast update
        await broadcast_message("curriculum_imported", {
            "id": curriculum_id or file_path.stem,
            "title": title,
            "file_path": str(file_path)
        })

        return web.json_response({
            "status": "ok",
            "id": curriculum_id or file_path.stem,
            "title": title,
            "file_path": str(file_path),
            "source_url": source_url
        })

    except asyncio.TimeoutError:
        return web.json_response({"error": "Timeout fetching URL"}, status=408)
    except Exception as e:
        logger.error(f"Error importing curriculum: {e}")
        import traceback
        traceback.print_exc()
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

    # Managed Services
    app.router.add_get("/api/services", handle_get_services)
    app.router.add_post("/api/services/{service_id}/start", handle_start_service)
    app.router.add_post("/api/services/{service_id}/stop", handle_stop_service)
    app.router.add_post("/api/services/{service_id}/restart", handle_restart_service)
    app.router.add_post("/api/services/start-all", handle_start_all_services)
    app.router.add_post("/api/services/stop-all", handle_stop_all_services)

    # Curriculum
    app.router.add_get("/api/curricula", handle_get_curricula)
    app.router.add_get("/api/curricula/{curriculum_id}", handle_get_curriculum_detail)
    app.router.add_get("/api/curricula/{curriculum_id}/full", handle_get_curriculum_full)
    app.router.add_get("/api/curricula/{curriculum_id}/topics/{topic_id}/transcript", handle_get_topic_transcript)
    app.router.add_get("/api/curricula/{curriculum_id}/topics/{topic_id}/stream-audio", handle_stream_topic_audio)
    app.router.add_post("/api/curricula/reload", handle_reload_curricula)
    app.router.add_post("/api/curricula/import", handle_import_curriculum)
    app.router.add_put("/api/curricula/{curriculum_id}", handle_save_curriculum)

    # WebSocket
    app.router.add_get("/ws", handle_websocket)

    # Static files and dashboard
    static_dir = Path(__file__).parent / "static"
    if static_dir.exists():
        app.router.add_static("/static", static_dir)
    app.router.add_get("/", handle_dashboard)

    # Startup hook to detect existing services and load curricula
    async def on_startup(app):
        await detect_existing_processes()
        state._load_curricula()  # Load all UMLCF curricula on startup

    app.on_startup.append(on_startup)

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
