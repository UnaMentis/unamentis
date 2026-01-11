#!/usr/bin/env python3
"""
UnaMentis Web Management Server
A next-generation management interface for monitoring and configuring UnaMentis services.
"""

import asyncio
import json
import logging
import os
import re
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

# Import resource monitoring and idle management
from resource_monitor import resource_monitor, ResourceMonitor
from idle_manager import idle_manager, IdleManager, IdleState
from metrics_history import metrics_history, MetricsHistory

# Import curriculum importer system
from import_api import register_import_routes, init_import_system, set_import_complete_callback

# Import curriculum reprocessing system
from reprocess_api import register_reprocess_routes, init_reprocess_system

# Import plugin management system
from plugin_api import register_plugin_routes

# Import media generation system
from media_api import register_media_routes

# Import authentication system
from auth import (
    AuthAPI, register_auth_routes, auth_middleware, rate_limit_middleware,
    TokenService, TokenConfig, RateLimiter, setup_token_service
)

# Import latency test harness system
from latency_harness_api import register_latency_harness_routes, init_latency_harness, shutdown_latency_harness

# Import diagnostic logging system
from diagnostic_logging import diag_logger, get_diagnostic_config, set_diagnostic_config

# Import FOV context management API
from fov_context_api import setup_fov_context_routes

# Import TTS cache system
from tts_cache import TTSCache, TTSResourcePool, CurriculumPrefetcher
from tts_api import register_tts_routes

# Import session-cache integration
from session_cache_integration import SessionCacheIntegration

# Import deployment API
from deployment_api import register_deployment_routes, ScheduledDeploymentManager

# Import audio WebSocket handler
from audio_ws import AudioWebSocketHandler, register_audio_websocket

# Import session management (for UserSession, UserVoiceConfig)
from fov_context import SessionManager, UserVoiceConfig

# Import model context windows for dynamic parameter limits
from fov_context.models import MODEL_CONTEXT_WINDOWS

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

try:
    import asyncpg
except ImportError:
    print("Installing asyncpg for database support...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "asyncpg"])
    import asyncpg

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
    visual_asset_count: int = 0
    has_visual_assets: bool = False


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
    embedded_asset_count: int = 0
    reference_asset_count: int = 0


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
    raw_umcf: Dict[str, Any] = field(default_factory=dict)


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
        self.curriculum_raw: Dict[str, Dict[str, Any]] = {}  # Full UMCF data by ID
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
        """Load all UMCF curriculum files from the curriculum directory."""
        curriculum_dir = PROJECT_ROOT / "curriculum" / "examples" / "realistic"
        if not curriculum_dir.exists():
            logger.warning(f"Curriculum directory not found: {curriculum_dir}")
            return

        for umcf_file in curriculum_dir.glob("*.umcf"):
            try:
                self._load_curriculum_file(umcf_file)
            except Exception as e:
                logger.error(f"Failed to load curriculum {umcf_file}: {e}")

        logger.info(f"Loaded {len(self.curriculums)} curricula")

    def _load_curriculum_file(self, file_path: Path):
        """Load a single UMCF file and extract summary/details."""
        with open(file_path, 'r', encoding='utf-8') as f:
            umcf = json.load(f)

        # Extract ID from the UMCF or generate from filename
        umcf_id = umcf.get("id", {}).get("value", file_path.stem)

        # Extract educational metadata
        educational = umcf.get("educational", {})
        version_info = umcf.get("version", {})

        # Count topics and calculate duration
        content = umcf.get("content", [])
        topic_count = 0
        topics = []
        total_visual_assets = 0
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

                # Count visual assets
                media = child.get("media", {})
                embedded_count = len(media.get("embedded", []))
                reference_count = len(media.get("reference", []))
                total_visual_assets += embedded_count + reference_count

                topics.append(TopicSummary(
                    id=child.get("id", {}).get("value", f"topic-{idx}"),
                    title=child.get("title", "Untitled"),
                    description=child.get("description", ""),
                    order_index=child.get("orderIndex", idx),
                    duration=duration,
                    has_transcript=len(segments) > 0,
                    segment_count=len(segments),
                    assessment_count=len(assessments),
                    embedded_asset_count=embedded_count,
                    reference_asset_count=reference_count
                ))

        # Extract glossary
        glossary = umcf.get("glossary", {}).get("terms", [])

        # Extract learning objectives from root content
        learning_objectives = []
        if content and isinstance(content, list):
            root = content[0]
            learning_objectives = root.get("learningObjectives", [])

        # Create summary for listing
        summary = CurriculumSummary(
            id=umcf_id,
            title=umcf.get("title", "Untitled"),
            description=umcf.get("description", ""),
            version=version_info.get("number", "1.0.0"),
            topic_count=topic_count,
            total_duration=educational.get("typicalLearningTime", "PT4H"),
            difficulty=educational.get("difficulty", "medium"),
            age_range=educational.get("typicalAgeRange", "18+"),
            keywords=umcf.get("metadata", {}).get("keywords", []),
            file_path=str(file_path),
            visual_asset_count=total_visual_assets,
            has_visual_assets=total_visual_assets > 0
        )

        # Create detailed view
        detail = CurriculumDetail(
            id=umcf_id,
            title=umcf.get("title", "Untitled"),
            description=umcf.get("description", ""),
            version=version_info.get("number", "1.0.0"),
            difficulty=educational.get("difficulty", "medium"),
            age_range=educational.get("typicalAgeRange", "18+"),
            duration=educational.get("typicalLearningTime", "PT4H"),
            keywords=umcf.get("metadata", {}).get("keywords", []),
            topics=[asdict(t) for t in topics],
            glossary_terms=glossary,
            learning_objectives=learning_objectives,
            raw_umcf=umcf
        )

        self.curriculums[umcf_id] = summary
        self.curriculum_details[umcf_id] = detail
        self.curriculum_raw[umcf_id] = umcf

    def reload_curricula(self):
        """Reload all curricula from disk."""
        self.curriculums.clear()
        self.curriculum_details.clear()
        self.curriculum_raw.clear()
        self._load_curricula()


# Global state
state = ManagementState()


# =============================================================================
# Text Chunking for Natural Speech
# =============================================================================

def chunk_text_for_tts(text: str, max_chars: int = 300, min_chars: int = 50) -> list[dict]:
    """
    Split text into natural segments for TTS streaming.

    This creates segments that:
    - End at sentence boundaries when possible
    - Are small enough for fast TTS response (<300 chars ideal)
    - Are large enough to sound natural (>50 chars when possible)
    - Preserve paragraph breaks as natural pause points

    Returns list of segment dicts with 'content' and 'type' keys.
    """
    if not text or not text.strip():
        return []

    # Clean up the text
    text = text.strip()

    # Remove common metadata headers that shouldn't be spoken
    # These are often video/document identifiers that the TTS shouldn't read
    # Pattern for MIT OCW headers like "MITOCW | MIT8_01F16_L00v01_360p"
    text = re.sub(r'^MITOCW\s*\|\s*[A-Za-z0-9_]+\s*', '', text, flags=re.IGNORECASE)
    # Pattern for standalone video markers like "MIT8_01F16_L00v01_360p"
    text = re.sub(r'^MIT\d+[A-Za-z]*_[A-Za-z0-9_]+\s*', '', text, flags=re.IGNORECASE)
    # Pattern for leftover video quality markers like "v01_360p"
    text = re.sub(r'^[vV]\d+_\d+p\s*', '', text)
    text = text.strip()

    if not text:
        return []

    # Split into paragraphs first (double newlines or single newlines with blank content)
    paragraphs = []
    current_para = []

    for line in text.split('\n'):
        stripped = line.strip()
        if not stripped:
            if current_para:
                paragraphs.append(' '.join(current_para))
                current_para = []
        else:
            current_para.append(stripped)

    if current_para:
        paragraphs.append(' '.join(current_para))

    segments = []

    for para_idx, paragraph in enumerate(paragraphs):
        if not paragraph:
            continue

        # Split paragraph into sentences
        # Handle common sentence endings while preserving abbreviations
        # Split on sentence-ending punctuation followed by space or end
        sentence_pattern = r'(?<=[.!?])\s+(?=[A-Z])|(?<=[.!?])$'
        sentences = re.split(sentence_pattern, paragraph)
        sentences = [s.strip() for s in sentences if s.strip()]

        # Now group sentences into chunks of appropriate size
        current_chunk = []
        current_length = 0

        for sentence in sentences:
            sentence_len = len(sentence)

            # If this single sentence is too long, we need to split it
            if sentence_len > max_chars:
                # Flush current chunk first
                if current_chunk:
                    chunk_text = ' '.join(current_chunk)
                    segments.append({
                        "content": chunk_text,
                        "type": "lecture" if para_idx == 0 else "explanation"
                    })
                    current_chunk = []
                    current_length = 0

                # Split long sentence on clause boundaries (commas, semicolons)
                clause_pattern = r'(?<=[,;:])\s+'
                clauses = re.split(clause_pattern, sentence)

                clause_chunk = []
                clause_length = 0

                for clause in clauses:
                    clause = clause.strip()
                    if not clause:
                        continue

                    if clause_length + len(clause) + 1 > max_chars and clause_chunk:
                        segments.append({
                            "content": ' '.join(clause_chunk),
                            "type": "lecture"
                        })
                        clause_chunk = []
                        clause_length = 0

                    clause_chunk.append(clause)
                    clause_length += len(clause) + 1

                if clause_chunk:
                    current_chunk = clause_chunk
                    current_length = clause_length
            else:
                # Normal case: accumulate sentences
                if current_length + sentence_len + 1 > max_chars and current_chunk:
                    # Flush current chunk
                    chunk_text = ' '.join(current_chunk)
                    segments.append({
                        "content": chunk_text,
                        "type": "lecture" if len(segments) == 0 else "explanation"
                    })
                    current_chunk = []
                    current_length = 0

                current_chunk.append(sentence)
                current_length += sentence_len + 1

        # Flush remaining chunk for this paragraph
        if current_chunk:
            chunk_text = ' '.join(current_chunk)
            # Only add if it meets minimum length or it's all we have
            if len(chunk_text) >= min_chars or not segments:
                segments.append({
                    "content": chunk_text,
                    "type": "lecture" if len(segments) == 0 else "explanation"
                })
            elif segments:
                # Append to previous segment if too short
                prev = segments[-1]
                prev["content"] = prev["content"] + " " + chunk_text

    # Add segment IDs
    for idx, seg in enumerate(segments):
        seg["id"] = f"chunk-{idx}"

    logger.info(f"Chunked {len(text)} chars into {len(segments)} segments")
    for idx, seg in enumerate(segments):
        logger.debug(f"  Segment {idx}: {len(seg['content'])} chars - {seg['content'][:50]}...")

    return segments


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

        # First, check health of all servers to update their status and models list
        tasks = [check_server_health(s) for s in state.servers.values()]
        await asyncio.gather(*tasks, return_exceptions=True)

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

                        # Get context window from MODEL_CONTEXT_WINDOWS
                        context_window = MODEL_CONTEXT_WINDOWS.get(model_name, 32_000)

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
                            "context_window": context_window,
                            "context_window_formatted": f"{context_window // 1000}K" if context_window >= 1000 else str(context_window),
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


async def handle_load_model(request: web.Request) -> web.Response:
    """Load a specific model into memory via Ollama API."""
    model_id = request.match_info["model_id"]

    try:
        # Parse optional request body
        try:
            body = await request.json()
        except Exception:
            body = {}

        keep_alive = body.get("keep_alive", "5m")

        # Extract model name from model_id (format: "server_id:model_name")
        if ":" in model_id:
            _, model_name = model_id.split(":", 1)
        else:
            model_name = model_id

        # Load model by sending a minimal request with keep_alive
        # This triggers Ollama to load the model into VRAM
        timeout = aiohttp.ClientTimeout(total=120)  # Loading can take time
        start_time = time.time()

        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                "http://localhost:11434/api/generate",
                json={
                    "model": model_name,
                    "prompt": "",
                    "keep_alive": keep_alive
                }
            ) as resp:
                if resp.status != 200:
                    error_text = await resp.text()
                    return web.json_response({
                        "status": "error",
                        "model": model_name,
                        "error": f"Ollama returned {resp.status}: {error_text}"
                    }, status=resp.status)

                # Consume the streaming response
                async for _ in resp.content:
                    pass

        load_time_ms = int((time.time() - start_time) * 1000)

        # Get updated VRAM usage
        vram_bytes = 0
        try:
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=5)) as session:
                async with session.get("http://localhost:11434/api/ps") as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        for m in data.get("models", []):
                            if m.get("name") == model_name:
                                vram_bytes = m.get("size_vram", 0)
                                break
        except Exception:
            pass

        logger.info(f"Loaded model {model_name} in {load_time_ms}ms")
        await broadcast_message("model_loaded", {"model": model_name, "vram_bytes": vram_bytes})

        return web.json_response({
            "status": "ok",
            "model": model_name,
            "vram_bytes": vram_bytes,
            "vram_gb": round(vram_bytes / (1024**3), 2),
            "load_time_ms": load_time_ms,
            "message": f"Model {model_name} loaded successfully"
        })

    except asyncio.TimeoutError:
        return web.json_response({
            "status": "error",
            "model": model_id,
            "error": "Timeout loading model (may still be loading in background)"
        }, status=504)
    except Exception as e:
        logger.error(f"Error loading model {model_id}: {e}")
        return web.json_response({
            "status": "error",
            "model": model_id,
            "error": str(e)
        }, status=500)


async def handle_unload_model(request: web.Request) -> web.Response:
    """Unload a specific model from memory."""
    model_id = request.match_info["model_id"]

    try:
        # Extract model name from model_id (format: "server_id:model_name")
        if ":" in model_id:
            _, model_name = model_id.split(":", 1)
        else:
            model_name = model_id

        # Get current VRAM usage before unload
        vram_before = 0
        try:
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=5)) as session:
                async with session.get("http://localhost:11434/api/ps") as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        for m in data.get("models", []):
                            if m.get("name") == model_name:
                                vram_before = m.get("size_vram", 0)
                                break
        except Exception:
            pass

        if vram_before == 0:
            return web.json_response({
                "status": "ok",
                "model": model_name,
                "message": "Model was not loaded",
                "freed_vram_bytes": 0
            })

        # Unload by setting keep_alive to 0
        timeout = aiohttp.ClientTimeout(total=30)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                "http://localhost:11434/api/generate",
                json={
                    "model": model_name,
                    "prompt": "",
                    "keep_alive": 0
                }
            ) as resp:
                if resp.status != 200:
                    error_text = await resp.text()
                    return web.json_response({
                        "status": "error",
                        "model": model_name,
                        "error": f"Ollama returned {resp.status}: {error_text}"
                    }, status=resp.status)

                # Consume the streaming response
                async for _ in resp.content:
                    pass

        logger.info(f"Unloaded model {model_name}, freed {vram_before / (1024**3):.2f} GB")
        await broadcast_message("model_unloaded", {"model": model_name, "freed_vram_bytes": vram_before})

        return web.json_response({
            "status": "ok",
            "model": model_name,
            "freed_vram_bytes": vram_before,
            "freed_vram_gb": round(vram_before / (1024**3), 2),
            "message": f"Model {model_name} unloaded"
        })

    except Exception as e:
        logger.error(f"Error unloading model {model_id}: {e}")
        return web.json_response({
            "status": "error",
            "model": model_id,
            "error": str(e)
        }, status=500)


async def handle_pull_model(request: web.Request) -> web.StreamResponse:
    """Pull (download) a model from Ollama registry with SSE progress streaming."""
    try:
        body = await request.json()
        model_name = body.get("model")

        if not model_name:
            return web.json_response({"error": "Model name required"}, status=400)

        logger.info(f"Starting pull for model: {model_name}")

        # Set up SSE response
        response = web.StreamResponse(
            status=200,
            reason="OK",
            headers={
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            }
        )
        await response.prepare(request)

        # Stream pull progress from Ollama
        timeout = aiohttp.ClientTimeout(total=3600)  # 1 hour for large models
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                "http://localhost:11434/api/pull",
                json={"name": model_name, "stream": True}
            ) as resp:
                if resp.status != 200:
                    error_msg = await resp.text()
                    await response.write(
                        f"data: {json.dumps({'status': 'error', 'error': error_msg})}\n\n".encode()
                    )
                    await response.write_eof()
                    return response

                async for line in resp.content:
                    if line:
                        try:
                            data = json.loads(line.decode())
                            # Forward the progress event
                            sse_data = {
                                "status": data.get("status", ""),
                                "digest": data.get("digest", ""),
                                "completed": data.get("completed", 0),
                                "total": data.get("total", 0),
                            }

                            # Check for completion or error
                            if "error" in data:
                                sse_data["error"] = data["error"]
                                sse_data["status"] = "error"

                            await response.write(f"data: {json.dumps(sse_data)}\n\n".encode())

                        except json.JSONDecodeError:
                            continue

        # Send completion event
        await response.write(
            f"data: {json.dumps({'status': 'success', 'model': model_name})}\n\n".encode()
        )

        logger.info(f"Model pull completed: {model_name}")
        await broadcast_message("model_pulled", {"model": model_name})
        await response.write_eof()
        return response

    except asyncio.CancelledError:
        logger.info("Model pull cancelled by client")
        raise
    except Exception as e:
        logger.error(f"Error pulling model: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_delete_model(request: web.Request) -> web.Response:
    """Delete a model from Ollama."""
    model_id = request.match_info["model_id"]

    try:
        # Extract model name from model_id (format: "server_id:model_name")
        if ":" in model_id:
            _, model_name = model_id.split(":", 1)
        else:
            model_name = model_id

        timeout = aiohttp.ClientTimeout(total=30)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.delete(
                "http://localhost:11434/api/delete",
                json={"name": model_name}
            ) as resp:
                if resp.status == 200:
                    logger.info(f"Deleted model: {model_name}")
                    await broadcast_message("model_deleted", {"model": model_name})
                    return web.json_response({
                        "status": "ok",
                        "model": model_name,
                        "message": f"Model {model_name} deleted"
                    })
                else:
                    error_text = await resp.text()
                    return web.json_response({
                        "status": "error",
                        "model": model_name,
                        "error": f"Ollama returned {resp.status}: {error_text}"
                    }, status=resp.status)

    except Exception as e:
        logger.error(f"Error deleting model {model_id}: {e}")
        return web.json_response({
            "status": "error",
            "model": model_id,
            "error": str(e)
        }, status=500)


# Model configuration file path
MODEL_CONFIG_PATH = Path(__file__).parent / "data" / "model_config.json"


def load_model_config() -> dict:
    """Load model configuration from disk."""
    if MODEL_CONFIG_PATH.exists():
        try:
            with open(MODEL_CONFIG_PATH, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            logger.warning(f"Failed to load model config: {e}")
    # Return default config
    return {
        "services": {
            "llm": {"default_model": None, "fallback_model": None},
            "tts": {"default_provider": "vibevoice", "default_voice": "nova"},
            "stt": {"default_model": "whisper"}
        }
    }


def save_model_config(config: dict) -> None:
    """Save model configuration to disk."""
    MODEL_CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(MODEL_CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)


async def handle_get_model_config(request: web.Request) -> web.Response:
    """Get current model configuration for all services."""
    try:
        config = load_model_config()
        return web.json_response({
            "status": "ok",
            "config": config
        })
    except Exception as e:
        logger.error(f"Error getting model config: {e}")
        return web.json_response({
            "status": "error",
            "error": str(e)
        }, status=500)


async def handle_save_model_config(request: web.Request) -> web.Response:
    """Save model configuration for services."""
    try:
        body = await request.json()
        config = body.get("config", {})

        # Validate structure
        if "services" not in config:
            return web.json_response({
                "status": "error",
                "error": "Invalid config: 'services' key required"
            }, status=400)

        # Merge with existing config to preserve unset values
        existing = load_model_config()
        for service, settings in config["services"].items():
            if service in existing["services"]:
                existing["services"][service].update(settings)
            else:
                existing["services"][service] = settings

        save_model_config(existing)
        logger.info(f"Model config saved: {existing}")

        return web.json_response({
            "status": "ok",
            "config": existing,
            "message": "Configuration saved"
        })

    except json.JSONDecodeError:
        return web.json_response({
            "status": "error",
            "error": "Invalid JSON"
        }, status=400)
    except Exception as e:
        logger.error(f"Error saving model config: {e}")
        return web.json_response({
            "status": "error",
            "error": str(e)
        }, status=500)


# Model parameters configuration file path
MODEL_PARAMS_PATH = Path(__file__).parent / "data" / "model_params.json"

# Default parameter definitions with ranges
DEFAULT_MODEL_PARAMS = {
    "num_ctx": {"value": 4096, "min": 256, "max": 131072, "description": "Context window size"},
    "temperature": {"value": 0.8, "min": 0.0, "max": 2.0, "step": 0.1, "description": "Sampling temperature"},
    "top_p": {"value": 0.9, "min": 0.0, "max": 1.0, "step": 0.05, "description": "Top-p (nucleus) sampling"},
    "top_k": {"value": 40, "min": 1, "max": 100, "description": "Top-k sampling"},
    "repeat_penalty": {"value": 1.1, "min": 0.0, "max": 2.0, "step": 0.1, "description": "Repeat penalty"},
    "seed": {"value": -1, "min": -1, "max": 2147483647, "description": "Random seed (-1 for random)"},
}


def load_model_params(model_name: str) -> dict:
    """Load model parameters from disk."""
    if MODEL_PARAMS_PATH.exists():
        try:
            with open(MODEL_PARAMS_PATH, "r") as f:
                all_params = json.load(f)
                return all_params.get(model_name, {})
        except (json.JSONDecodeError, IOError) as e:
            logger.warning(f"Failed to load model params: {e}")
    return {}


def save_model_params(model_name: str, params: dict) -> None:
    """Save model parameters to disk."""
    MODEL_PARAMS_PATH.parent.mkdir(parents=True, exist_ok=True)
    all_params = {}
    if MODEL_PARAMS_PATH.exists():
        try:
            with open(MODEL_PARAMS_PATH, "r") as f:
                all_params = json.load(f)
        except (json.JSONDecodeError, IOError):
            pass
    all_params[model_name] = params
    with open(MODEL_PARAMS_PATH, "w") as f:
        json.dump(all_params, f, indent=2)


async def handle_get_model_parameters(request: web.Request) -> web.Response:
    """Get parameters for a specific model with their ranges."""
    model_id = request.match_info["model_id"]

    try:
        # Extract model name from model_id (format: "server_id:model_name")
        if ":" in model_id:
            _, model_name = model_id.split(":", 1)
        else:
            model_name = model_id

        # Load saved parameters for this model
        saved_params = load_model_params(model_name)

        # Get model's actual context window from MODEL_CONTEXT_WINDOWS
        model_context_window = MODEL_CONTEXT_WINDOWS.get(model_name, 32_000)

        # Merge with defaults, adjusting num_ctx max based on model capability
        params = {}
        for key, default_def in DEFAULT_MODEL_PARAMS.items():
            param = {
                **default_def,
                "value": saved_params.get(key, default_def["value"])
            }
            # Override num_ctx max with model's actual context window
            if key == "num_ctx":
                param["max"] = model_context_window
                param["model_max_context"] = model_context_window
            params[key] = param

        return web.json_response({
            "status": "ok",
            "model": model_name,
            "parameters": params,
            "model_info": {
                "context_window": model_context_window,
                "context_window_formatted": f"{model_context_window // 1000}K" if model_context_window >= 1000 else str(model_context_window)
            }
        })

    except Exception as e:
        logger.error(f"Error getting model parameters: {e}")
        return web.json_response({
            "status": "error",
            "model": model_id,
            "error": str(e)
        }, status=500)


async def handle_save_model_parameters(request: web.Request) -> web.Response:
    """Save parameters for a specific model."""
    model_id = request.match_info["model_id"]

    try:
        body = await request.json()
        new_params = body.get("parameters", {})

        # Extract model name from model_id
        if ":" in model_id:
            _, model_name = model_id.split(":", 1)
        else:
            model_name = model_id

        # Validate parameters
        validated_params = {}
        for key, value in new_params.items():
            if key in DEFAULT_MODEL_PARAMS:
                param_def = DEFAULT_MODEL_PARAMS[key]
                # Clamp value to valid range
                min_val = param_def.get("min", float("-inf"))
                max_val = param_def.get("max", float("inf"))
                validated_params[key] = max(min_val, min(max_val, value))

        # Save parameters
        save_model_params(model_name, validated_params)
        logger.info(f"Model parameters saved for {model_name}: {validated_params}")

        return web.json_response({
            "status": "ok",
            "model": model_name,
            "parameters": validated_params,
            "message": "Parameters saved"
        })

    except json.JSONDecodeError:
        return web.json_response({
            "status": "error",
            "error": "Invalid JSON"
        }, status=400)
    except Exception as e:
        logger.error(f"Error saving model parameters: {e}")
        return web.json_response({
            "status": "error",
            "model": model_id,
            "error": str(e)
        }, status=500)


async def handle_get_model_capabilities(request: web.Request) -> web.Response:
    """Get all known model capabilities including context windows."""
    try:
        # Build capabilities for all known models
        capabilities = []
        for model_name, context_window in MODEL_CONTEXT_WINDOWS.items():
            # Determine model tier based on context window
            if context_window >= 100_000:
                tier = "cloud"
            elif context_window >= 32_000:
                tier = "mid_range"
            elif context_window >= 8_000:
                tier = "on_device"
            else:
                tier = "tiny"

            # Determine provider from model name
            if model_name.startswith("claude"):
                provider = "anthropic"
            elif model_name.startswith("gpt"):
                provider = "openai"
            elif model_name.startswith("mlx-"):
                provider = "mlx"
            else:
                provider = "ollama"

            capabilities.append({
                "model": model_name,
                "context_window": context_window,
                "context_window_formatted": f"{context_window // 1000}K" if context_window >= 1000 else str(context_window),
                "tier": tier,
                "provider": provider
            })

        # Sort by context window descending
        capabilities.sort(key=lambda x: x["context_window"], reverse=True)

        return web.json_response({
            "status": "ok",
            "capabilities": capabilities,
            "total": len(capabilities),
            "by_tier": {
                "cloud": sum(1 for c in capabilities if c["tier"] == "cloud"),
                "mid_range": sum(1 for c in capabilities if c["tier"] == "mid_range"),
                "on_device": sum(1 for c in capabilities if c["tier"] == "on_device"),
                "tiny": sum(1 for c in capabilities if c["tier"] == "tiny")
            },
            "by_provider": {
                "anthropic": sum(1 for c in capabilities if c["provider"] == "anthropic"),
                "openai": sum(1 for c in capabilities if c["provider"] == "openai"),
                "ollama": sum(1 for c in capabilities if c["provider"] == "ollama"),
                "mlx": sum(1 for c in capabilities if c["provider"] == "mlx")
            }
        })
    except Exception as e:
        logger.error(f"Error getting model capabilities: {e}")
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
        # Don't include raw_umcf in detail response (it's huge)
        result = asdict(detail)
        del result["raw_umcf"]

        return web.json_response(result)

    except Exception as e:
        logger.error(f"Error getting curriculum detail: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_curriculum_full(request: web.Request) -> web.Response:
    """Get full UMCF data for a curriculum (for iOS download)."""
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

        umcf = state.curriculum_raw[curriculum_id]
        content = umcf.get("content", [])

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

                # FALLBACK: If no transcript.segments, check for content.text
                # This handles imported curricula (like MIT physics) that use content.text
                if not segments:
                    content_obj = child.get("content", {})
                    if isinstance(content_obj, dict):
                        raw_text = content_obj.get("text", "")
                        if raw_text:
                            logger.info(f"Topic {topic_id} has no transcript.segments, using content.text ({len(raw_text)} chars)")
                            # Chunk the raw text into natural speech segments
                            segments = chunk_text_for_tts(raw_text, max_chars=300, min_chars=50)
                            logger.info(f"Created {len(segments)} segments from content.text")

                # Get media assets
                media = child.get("media", {})
                embedded_assets = media.get("embedded", [])
                reference_assets = media.get("reference", [])

                return web.json_response({
                    "topic_id": topic_id,
                    "topic_title": child.get("title", ""),
                    "segments": segments,
                    "misconceptions": child.get("misconceptions", []),
                    "examples": child.get("examples", []),
                    "assessments": child.get("assessments", []),
                    "media": {
                        "embedded": embedded_assets,
                        "reference": reference_assets,
                        "total_count": len(embedded_assets) + len(reference_assets)
                    }
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

        umcf = state.curriculum_raw[curriculum_id]
        content = umcf.get("content", [])

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

                # FALLBACK: If no transcript.segments, check for content.text
                # This handles imported curricula (like MIT physics) that use content.text
                if not transcript_segments:
                    content_obj = child.get("content", {})
                    if isinstance(content_obj, dict):
                        raw_text = content_obj.get("text", "")
                        if raw_text:
                            logger.info(f"[stream] Topic {topic_id} has no transcript.segments, using content.text ({len(raw_text)} chars)")
                            # Chunk the raw text into natural speech segments
                            transcript_segments = chunk_text_for_tts(raw_text, max_chars=300, min_chars=50)
                            logger.info(f"[stream] Created {len(transcript_segments)} segments from content.text")
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


async def handle_delete_curriculum(request: web.Request) -> web.Response:
    """
    DELETE /api/curricula/{curriculum_id}

    Permanently delete a curriculum file.
    Query params:
    - confirm: Must be "true" to actually delete (safety check)
    """
    try:
        curriculum_id = request.match_info.get("curriculum_id")
        confirm = request.query.get("confirm", "false").lower() == "true"
        logger.info(f"Delete curriculum request: id={curriculum_id}, confirm={confirm}")

        if curriculum_id not in state.curriculums:
            logger.warning(f"Delete failed: curriculum not found: {curriculum_id}")
            return web.json_response({"error": "Curriculum not found"}, status=404)

        curriculum = state.curriculums[curriculum_id]
        file_path = Path(curriculum.file_path)

        if not confirm:
            # Return info about what would be deleted without actually deleting
            return web.json_response({
                "status": "confirmation_required",
                "message": "Add ?confirm=true to permanently delete this curriculum",
                "curriculum": {
                    "id": curriculum_id,
                    "title": curriculum.title,
                    "file_path": str(file_path),
                    "topic_count": curriculum.topic_count,
                }
            })

        if not file_path.exists():
            logger.warning(f"Delete failed: file not found on disk: {file_path}")
            return web.json_response({"error": "Curriculum file not found on disk"}, status=404)

        # Delete the file
        file_path.unlink()
        logger.info(f"Successfully deleted curriculum file: {file_path}")

        # Remove from state
        del state.curriculums[curriculum_id]
        if curriculum_id in state.curriculum_details:
            del state.curriculum_details[curriculum_id]
        if curriculum_id in state.curriculum_raw:
            del state.curriculum_raw[curriculum_id]

        await broadcast_message("curriculum_deleted", {
            "id": curriculum_id,
            "title": curriculum.title,
        })

        return web.json_response({
            "status": "deleted",
            "id": curriculum_id,
            "title": curriculum.title,
        })

    except Exception as e:
        logger.error(f"Error deleting curriculum: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_archive_curriculum(request: web.Request) -> web.Response:
    """
    POST /api/curricula/{curriculum_id}/archive

    Archive a curriculum (move to archived folder instead of deleting).
    """
    try:
        curriculum_id = request.match_info.get("curriculum_id")
        logger.info(f"Archive curriculum request: id={curriculum_id}")

        if curriculum_id not in state.curriculums:
            logger.warning(f"Archive failed: curriculum not found: {curriculum_id}")
            return web.json_response({"error": "Curriculum not found"}, status=404)

        curriculum = state.curriculums[curriculum_id]
        file_path = Path(curriculum.file_path)

        if not file_path.exists():
            logger.warning(f"Archive failed: file not found on disk: {file_path}")
            return web.json_response({"error": "Curriculum file not found on disk"}, status=404)

        # Create archived directory if it doesn't exist
        archived_dir = PROJECT_ROOT / "curriculum" / "archived"
        archived_dir.mkdir(parents=True, exist_ok=True)

        # Move to archived folder
        archived_path = archived_dir / file_path.name
        # Handle name conflicts
        counter = 1
        while archived_path.exists():
            archived_path = archived_dir / f"{file_path.stem}-{counter}{file_path.suffix}"
            counter += 1

        import shutil
        shutil.move(str(file_path), str(archived_path))
        logger.info(f"Successfully archived curriculum: {file_path} -> {archived_path}")

        # Remove from state
        del state.curriculums[curriculum_id]
        if curriculum_id in state.curriculum_details:
            del state.curriculum_details[curriculum_id]
        if curriculum_id in state.curriculum_raw:
            del state.curriculum_raw[curriculum_id]

        await broadcast_message("curriculum_archived", {
            "id": curriculum_id,
            "title": curriculum.title,
            "archived_path": str(archived_path),
        })

        return web.json_response({
            "status": "archived",
            "id": curriculum_id,
            "title": curriculum.title,
            "archived_path": str(archived_path),
        })

    except Exception as e:
        logger.error(f"Error archiving curriculum: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_archived_curricula(_request: web.Request) -> web.Response:
    """
    GET /api/curricula/archived

    Get list of archived curricula.
    """
    try:
        archived_dir = PROJECT_ROOT / "curriculum" / "archived"

        if not archived_dir.exists():
            return web.json_response({
                "archived": [],
                "total": 0
            })

        archived = []
        for umcf_file in archived_dir.glob("*.umcf"):
            try:
                with open(umcf_file, 'r', encoding='utf-8') as f:
                    umcf = json.load(f)

                umcf_id = umcf.get("id", {}).get("value", umcf_file.stem)
                content = umcf.get("content", [])
                topic_count = 0
                if content and isinstance(content, list):
                    root = content[0]
                    topic_count = len(root.get("children", []))

                archived.append({
                    "id": umcf_id,
                    "title": umcf.get("title", "Untitled"),
                    "description": umcf.get("description", ""),
                    "file_path": str(umcf_file),
                    "file_name": umcf_file.name,
                    "topic_count": topic_count,
                    "archived_at": umcf_file.stat().st_mtime,
                })
            except Exception as e:
                logger.warning(f"Failed to read archived curriculum {umcf_file}: {e}")

        # Sort by archived date (newest first)
        archived.sort(key=lambda x: x["archived_at"], reverse=True)

        return web.json_response({
            "archived": archived,
            "total": len(archived)
        })

    except Exception as e:
        logger.error(f"Error getting archived curricula: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_unarchive_curriculum(request: web.Request) -> web.Response:
    """
    POST /api/curricula/archived/{file_name}/unarchive

    Restore an archived curriculum back to active.
    """
    try:
        file_name = request.match_info.get("file_name")

        archived_dir = PROJECT_ROOT / "curriculum" / "archived"
        archived_path = archived_dir / file_name

        if not archived_path.exists():
            return web.json_response({"error": "Archived curriculum not found"}, status=404)

        # Move back to active directory
        active_dir = PROJECT_ROOT / "curriculum" / "examples" / "realistic"
        active_path = active_dir / file_name

        # Handle name conflicts
        counter = 1
        while active_path.exists():
            active_path = active_dir / f"{archived_path.stem}-{counter}{archived_path.suffix}"
            counter += 1

        import shutil
        shutil.move(str(archived_path), str(active_path))
        logger.info(f"Unarchived curriculum: {archived_path} -> {active_path}")

        # Reload the curriculum
        state._load_curriculum_file(active_path)

        # Get the curriculum info
        with open(active_path, 'r', encoding='utf-8') as f:
            umcf = json.load(f)
        curriculum_id = umcf.get("id", {}).get("value", active_path.stem)

        await broadcast_message("curriculum_unarchived", {
            "id": curriculum_id,
            "title": umcf.get("title", "Untitled"),
        })

        return web.json_response({
            "status": "unarchived",
            "id": curriculum_id,
            "title": umcf.get("title", "Untitled"),
            "file_path": str(active_path),
        })

    except Exception as e:
        logger.error(f"Error unarchiving curriculum: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_delete_archived_curriculum(request: web.Request) -> web.Response:
    """
    DELETE /api/curricula/archived/{file_name}

    Permanently delete an archived curriculum.
    Query params:
    - confirm: Must be "true" to actually delete
    """
    try:
        file_name = request.match_info.get("file_name")
        confirm = request.query.get("confirm", "false").lower() == "true"

        archived_dir = PROJECT_ROOT / "curriculum" / "archived"
        archived_path = archived_dir / file_name

        if not archived_path.exists():
            return web.json_response({"error": "Archived curriculum not found"}, status=404)

        # Read info for response
        with open(archived_path, 'r', encoding='utf-8') as f:
            umcf = json.load(f)
        curriculum_id = umcf.get("id", {}).get("value", archived_path.stem)
        title = umcf.get("title", "Untitled")

        if not confirm:
            return web.json_response({
                "status": "confirmation_required",
                "message": "Add ?confirm=true to permanently delete this archived curriculum",
                "curriculum": {
                    "id": curriculum_id,
                    "title": title,
                    "file_path": str(archived_path),
                }
            })

        # Delete the file
        archived_path.unlink()
        logger.info(f"Permanently deleted archived curriculum: {archived_path}")

        return web.json_response({
            "status": "deleted",
            "id": curriculum_id,
            "title": title,
        })

    except Exception as e:
        logger.error(f"Error deleting archived curriculum: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_save_curriculum(request: web.Request) -> web.Response:
    """Save/update a curriculum UMCF file."""
    try:
        curriculum_id = request.match_info.get("curriculum_id")
        data = await request.json()

        # Validate it's valid UMCF (basic check)
        if "umcf" not in data or "title" not in data:
            return web.json_response({"error": "Invalid UMCF data"}, status=400)

        # Determine file path
        if curriculum_id in state.curriculums:
            file_path = Path(state.curriculums[curriculum_id].file_path)
        else:
            # New curriculum - create filename from title
            safe_name = "".join(c if c.isalnum() or c in "-_" else "-" for c in data["title"].lower())
            file_path = PROJECT_ROOT / "curriculum" / "examples" / "realistic" / f"{safe_name}.umcf"

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
        umcf_data = None
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
                        umcf_data = json.loads(content)
                    except json.JSONDecodeError as e:
                        return web.json_response(
                            {"error": f"Invalid JSON at URL: {str(e)}"},
                            status=400
                        )

        # Import from direct content
        elif "content" in data:
            umcf_data = data["content"]
            logger.info("Importing curriculum from direct content")

        else:
            return web.json_response(
                {"error": "Must provide 'url' or 'content'"},
                status=400
            )

        # Validate UMCF format
        if not isinstance(umcf_data, dict):
            return web.json_response({"error": "Content must be a JSON object"}, status=400)

        if umcf_data.get("formatIdentifier") != "umcf":
            return web.json_response(
                {"error": "Invalid format: formatIdentifier must be 'umcf'"},
                status=400
            )

        # Extract title for filename
        metadata = umcf_data.get("metadata", {})
        title = metadata.get("title", "Imported Curriculum")
        curriculum_id = umcf_data.get("id", {}).get("value", "")

        # Create safe filename
        safe_name = "".join(c if c.isalnum() or c in "-_" else "-" for c in title.lower())
        if not safe_name:
            safe_name = f"imported-{int(time.time())}"

        # Determine destination path
        curriculum_dir = PROJECT_ROOT / "curriculum" / "examples" / "realistic"
        curriculum_dir.mkdir(parents=True, exist_ok=True)

        file_path = curriculum_dir / f"{safe_name}.umcf"

        # Handle duplicate filenames
        counter = 1
        while file_path.exists():
            file_path = curriculum_dir / f"{safe_name}-{counter}.umcf"
            counter += 1

        # Write the file
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(umcf_data, f, indent=2, ensure_ascii=False)

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
# API Handlers - Visual Assets
# =============================================================================

async def handle_upload_visual_asset(request: web.Request) -> web.Response:
    """Upload a visual asset for a curriculum topic."""
    try:
        curriculum_id = request.match_info.get("curriculum_id")
        topic_id = request.match_info.get("topic_id")

        if curriculum_id not in state.curriculum_raw:
            return web.json_response({"error": "Curriculum not found"}, status=404)

        # Parse multipart form data
        reader = await request.multipart()
        file_data = None
        file_name = None
        file_content_type = None
        metadata = {}

        while True:
            part = await reader.next()
            if part is None:
                break

            if part.name == "file":
                file_name = part.filename
                file_content_type = part.headers.get("Content-Type", "image/png")
                file_data = await part.read()
            elif part.name == "metadata":
                metadata_str = await part.text()
                metadata = json.loads(metadata_str)
            elif part.name == "topicId":
                topic_id = await part.text()

        if not file_data or not file_name:
            return web.json_response({"error": "No file uploaded"}, status=400)

        if not metadata.get("alt"):
            return web.json_response({"error": "Alt text is required for accessibility"}, status=400)

        # Create assets directory if needed
        assets_dir = PROJECT_ROOT / "curriculum" / "assets" / curriculum_id / topic_id
        assets_dir.mkdir(parents=True, exist_ok=True)

        # Generate unique asset ID
        asset_id = f"img-{int(time.time() * 1000)}"
        ext = Path(file_name).suffix or ".png"
        local_path = assets_dir / f"{asset_id}{ext}"

        # Save the file
        with open(local_path, "wb") as f:
            f.write(file_data)

        logger.info(f"Saved visual asset: {local_path}")

        # Create the asset object
        asset = {
            "id": asset_id,
            "type": metadata.get("type", "image"),
            "localPath": str(local_path.relative_to(PROJECT_ROOT)),
            "title": metadata.get("title", file_name),
            "alt": metadata["alt"],
            "caption": metadata.get("caption"),
            "mimeType": file_content_type,
        }

        # Add segment timing for embedded assets
        if not metadata.get("isReference", False):
            asset["segmentTiming"] = {
                "startSegment": metadata.get("startSegment", 0),
                "endSegment": metadata.get("endSegment", 0),
                "displayMode": metadata.get("displayMode", "inline")
            }
        else:
            asset["keywords"] = metadata.get("keywords", [])

        # Update the curriculum file
        umcf = state.curriculum_raw[curriculum_id]
        content = umcf.get("content", [])

        if content:
            root = content[0]
            children = root.get("children", [])

            for child in children:
                child_id = child.get("id", {}).get("value", "")
                if child_id == topic_id:
                    # Initialize media if needed
                    if "media" not in child:
                        child["media"] = {"embedded": [], "reference": []}

                    # Add to appropriate list
                    if metadata.get("isReference", False):
                        child["media"]["reference"].append(asset)
                    else:
                        child["media"]["embedded"].append(asset)

                    break

            # Save the updated curriculum
            if curriculum_id in state.curriculums:
                file_path = Path(state.curriculums[curriculum_id].file_path)
                with open(file_path, 'w', encoding='utf-8') as f:
                    json.dump(umcf, f, indent=2, ensure_ascii=False)

                # Reload to update state
                state._load_curriculum_file(file_path)

        return web.json_response({
            "status": "success",
            "asset": asset,
            "localPath": str(local_path)
        })

    except Exception as e:
        logger.error(f"Error uploading visual asset: {e}")
        import traceback
        traceback.print_exc()
        return web.json_response({"error": str(e)}, status=500)


async def handle_delete_visual_asset(request: web.Request) -> web.Response:
    """Delete a visual asset from a curriculum topic."""
    try:
        curriculum_id = request.match_info.get("curriculum_id")
        topic_id = request.match_info.get("topic_id")
        asset_id = request.match_info.get("asset_id")

        if curriculum_id not in state.curriculum_raw:
            return web.json_response({"error": "Curriculum not found"}, status=404)

        umcf = state.curriculum_raw[curriculum_id]
        content = umcf.get("content", [])

        if content:
            root = content[0]
            children = root.get("children", [])

            for child in children:
                child_id = child.get("id", {}).get("value", "")
                if child_id == topic_id:
                    media = child.get("media", {})

                    # Remove from embedded
                    embedded = media.get("embedded", [])
                    media["embedded"] = [a for a in embedded if a.get("id") != asset_id]

                    # Remove from reference
                    reference = media.get("reference", [])
                    media["reference"] = [a for a in reference if a.get("id") != asset_id]

                    break

            # Save the updated curriculum
            if curriculum_id in state.curriculums:
                file_path = Path(state.curriculums[curriculum_id].file_path)
                with open(file_path, 'w', encoding='utf-8') as f:
                    json.dump(umcf, f, indent=2, ensure_ascii=False)

                state._load_curriculum_file(file_path)

        return web.json_response({"status": "success"})

    except Exception as e:
        logger.error(f"Error deleting visual asset: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_update_visual_asset(request: web.Request) -> web.Response:
    """Update visual asset metadata."""
    try:
        curriculum_id = request.match_info.get("curriculum_id")
        topic_id = request.match_info.get("topic_id")
        asset_id = request.match_info.get("asset_id")
        updates = await request.json()

        if curriculum_id not in state.curriculum_raw:
            return web.json_response({"error": "Curriculum not found"}, status=404)

        umcf = state.curriculum_raw[curriculum_id]
        content = umcf.get("content", [])
        updated_asset = None

        if content:
            root = content[0]
            children = root.get("children", [])

            for child in children:
                child_id = child.get("id", {}).get("value", "")
                if child_id == topic_id:
                    media = child.get("media", {})

                    # Update in embedded
                    for asset in media.get("embedded", []):
                        if asset.get("id") == asset_id:
                            asset.update(updates)
                            updated_asset = asset
                            break

                    # Update in reference
                    if not updated_asset:
                        for asset in media.get("reference", []):
                            if asset.get("id") == asset_id:
                                asset.update(updates)
                                updated_asset = asset
                                break

                    break

            # Save the updated curriculum
            if updated_asset and curriculum_id in state.curriculums:
                file_path = Path(state.curriculums[curriculum_id].file_path)
                with open(file_path, 'w', encoding='utf-8') as f:
                    json.dump(umcf, f, indent=2, ensure_ascii=False)

                state._load_curriculum_file(file_path)

        if not updated_asset:
            return web.json_response({"error": "Asset not found"}, status=404)

        return web.json_response({
            "status": "success",
            "asset": updated_asset
        })

    except Exception as e:
        logger.error(f"Error updating visual asset: {e}")
        return web.json_response({"error": str(e)}, status=500)


# =============================================================================
# Asset Pre-Download & Caching
# =============================================================================

# Rate limiter for external downloads (especially Wikimedia)
_last_download_time = 0.0
_download_lock = asyncio.Lock()
DOWNLOAD_RATE_LIMIT_SECONDS = 1.0  # 1 request per second for Wikimedia


async def download_and_save_asset(
    url: str,
    curriculum_id: str,
    topic_id: str,
    asset_id: str
) -> Optional[str]:
    """
    Download an asset from a remote URL and save it locally.
    Returns the local path relative to PROJECT_ROOT, or None on failure.

    Rate-limited to 1 request per second for Wikimedia Commons compliance.
    """
    global _last_download_time

    async with _download_lock:
        # Enforce rate limiting
        now = time.time()
        elapsed = now - _last_download_time
        if elapsed < DOWNLOAD_RATE_LIMIT_SECONDS:
            await asyncio.sleep(DOWNLOAD_RATE_LIMIT_SECONDS - elapsed)

        _last_download_time = time.time()

    try:
        # Determine file extension from URL
        url_path = url.split("?")[0]  # Remove query params
        ext = Path(url_path).suffix.lower()
        if not ext or ext not in [".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"]:
            ext = ".jpg"  # Default to jpg

        # Create assets directory
        assets_dir = PROJECT_ROOT / "curriculum" / "assets" / curriculum_id / topic_id
        assets_dir.mkdir(parents=True, exist_ok=True)

        local_path = assets_dir / f"{asset_id}{ext}"

        # Skip if already downloaded
        if local_path.exists():
            logger.info(f"Asset already cached: {local_path}")
            return str(local_path.relative_to(PROJECT_ROOT))

        # Download with proper headers
        headers = {
            "User-Agent": "UnaMentis/1.0 (Educational App; https://unamentis.com; support@unamentis.com)"
        }

        async with aiohttp.ClientSession() as session:
            async with session.get(url, headers=headers, timeout=aiohttp.ClientTimeout(total=30)) as response:
                if response.status == 200:
                    content = await response.read()

                    # Verify it's actually an image
                    content_type = response.headers.get("Content-Type", "")
                    if not content_type.startswith("image/"):
                        logger.warning(f"Non-image content type for {url}: {content_type}")

                    # Save to disk
                    with open(local_path, "wb") as f:
                        f.write(content)

                    logger.info(f"Downloaded asset: {url} -> {local_path} ({len(content)} bytes)")
                    return str(local_path.relative_to(PROJECT_ROOT))

                elif response.status == 429:
                    logger.warning(f"Rate limited downloading {url}, will retry later")
                    return None
                else:
                    logger.error(f"Failed to download {url}: HTTP {response.status}")
                    return None

    except asyncio.TimeoutError:
        logger.error(f"Timeout downloading {url}")
        return None
    except Exception as e:
        logger.error(f"Error downloading {url}: {e}")
        return None


async def handle_preload_curriculum_assets(request: web.Request) -> web.Response:
    """
    Pre-download all remote assets for a curriculum and update UMCF with localPath.

    POST /api/curricula/{curriculum_id}/preload-assets

    This endpoint:
    1. Iterates all topics in the curriculum
    2. For each media asset with a URL but no localPath, downloads the asset
    3. Updates the UMCF file with localPath references
    4. Returns a summary of downloaded/failed assets
    """
    try:
        curriculum_id = request.match_info.get("curriculum_id")

        if curriculum_id not in state.curriculum_raw:
            return web.json_response({"error": "Curriculum not found"}, status=404)

        umcf = state.curriculum_raw[curriculum_id]
        content = umcf.get("content", [])

        if not content:
            return web.json_response({"error": "No content in curriculum"}, status=404)

        root = content[0]
        children = root.get("children", [])

        downloaded = []
        failed = []
        skipped = []

        for topic in children:
            topic_id = topic.get("id", {}).get("value", "")
            if not topic_id:
                continue

            media = topic.get("media", {})

            # Process both embedded and reference assets
            for asset_list_key in ["embedded", "reference"]:
                assets = media.get(asset_list_key, [])

                for asset in assets:
                    asset_id = asset.get("id", "")
                    url = asset.get("url", "")
                    local_path = asset.get("localPath", "")

                    # Skip if no URL or already has localPath
                    if not url:
                        continue
                    if local_path:
                        skipped.append({"id": asset_id, "reason": "already_cached"})
                        continue

                    # Download the asset
                    logger.info(f"Downloading asset {asset_id} from {url}")
                    result_path = await download_and_save_asset(
                        url=url,
                        curriculum_id=curriculum_id,
                        topic_id=topic_id,
                        asset_id=asset_id
                    )

                    if result_path:
                        asset["localPath"] = result_path
                        downloaded.append({
                            "id": asset_id,
                            "topic": topic_id,
                            "localPath": result_path
                        })
                    else:
                        failed.append({
                            "id": asset_id,
                            "topic": topic_id,
                            "url": url
                        })

        # Save the updated curriculum file
        if downloaded and curriculum_id in state.curriculums:
            file_path = Path(state.curriculums[curriculum_id].file_path)
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(umcf, f, indent=2, ensure_ascii=False)

            # Reload to update state
            state._load_curriculum_file(file_path)
            logger.info(f"Updated curriculum file with {len(downloaded)} local paths")

        return web.json_response({
            "status": "success",
            "downloaded": len(downloaded),
            "failed": len(failed),
            "skipped": len(skipped),
            "details": {
                "downloaded": downloaded,
                "failed": failed,
                "skipped": skipped
            }
        })

    except Exception as e:
        logger.error(f"Error preloading curriculum assets: {e}")
        import traceback
        traceback.print_exc()
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_curriculum_with_assets(request: web.Request) -> web.Response:
    """
    Get full UMCF data with base64-encoded asset data bundled.

    GET /api/curricula/{curriculum_id}/full-with-assets

    Returns the UMCF JSON with an additional 'assetData' field containing
    base64-encoded binary data for all assets that have localPath set.

    Response format:
    {
        ...umcf fields...,
        "assetData": {
            "asset-id-1": {
                "data": "base64-encoded-data",
                "mimeType": "image/jpeg",
                "size": 12345
            },
            ...
        }
    }
    """
    try:
        curriculum_id = request.match_info.get("curriculum_id")

        if curriculum_id not in state.curriculum_raw:
            return web.json_response({"error": "Curriculum not found"}, status=404)

        # Deep copy the UMCF to avoid modifying the cached version
        import copy
        umcf = copy.deepcopy(state.curriculum_raw[curriculum_id])

        content = umcf.get("content", [])
        if not content:
            return web.json_response(umcf)

        root = content[0]
        children = root.get("children", [])

        # Collect all assets with local paths
        asset_data = {}

        for topic in children:
            media = topic.get("media", {})

            for asset_list_key in ["embedded", "reference"]:
                assets = media.get(asset_list_key, [])

                for asset in assets:
                    asset_id = asset.get("id", "")
                    local_path = asset.get("localPath", "")

                    if not local_path or not asset_id:
                        continue

                    # Read the local file
                    full_path = PROJECT_ROOT / local_path
                    if not full_path.exists():
                        logger.warning(f"Local asset file not found: {full_path}")
                        continue

                    try:
                        with open(full_path, "rb") as f:
                            data = f.read()

                        # Determine MIME type
                        ext = full_path.suffix.lower()
                        mime_types = {
                            ".jpg": "image/jpeg",
                            ".jpeg": "image/jpeg",
                            ".png": "image/png",
                            ".gif": "image/gif",
                            ".webp": "image/webp",
                            ".svg": "image/svg+xml"
                        }
                        mime_type = mime_types.get(ext, "application/octet-stream")

                        import base64
                        asset_data[asset_id] = {
                            "data": base64.b64encode(data).decode("ascii"),
                            "mimeType": mime_type,
                            "size": len(data)
                        }

                    except Exception as e:
                        logger.error(f"Error reading asset {asset_id}: {e}")

        # Add asset data to response
        umcf["assetData"] = asset_data

        logger.info(f"Returning curriculum with {len(asset_data)} bundled assets")

        return web.json_response(umcf)

    except Exception as e:
        logger.error(f"Error getting curriculum with assets: {e}")
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
    """Redirect to the unified Next.js console on port 3000.

    The legacy vanilla JS dashboard has been replaced by the unified
    Next.js console. This redirect ensures users are directed to the
    new interface while maintaining API compatibility on port 8766.
    """
    # Check if redirect is disabled via query param for backward compatibility
    if request.query.get("legacy") == "true":
        static_dir = Path(__file__).parent / "static"
        index_file = static_dir / "index.html"
        if index_file.exists():
            return web.FileResponse(index_file)
        return web.Response(
            text="Legacy dashboard not found.",
            status=404
        )

    # Redirect to the unified console
    return web.HTTPFound("http://localhost:3000")


async def handle_health(request: web.Request) -> web.Response:
    """Health check endpoint."""
    return web.json_response({
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "version": "1.0.0"
    })


# =============================================================================
# API Handlers - System Metrics & Idle Management
# =============================================================================

async def handle_get_system_metrics(request: web.Request) -> web.Response:
    """Get current system resource metrics summary."""
    try:
        # Record activity
        idle_manager.record_activity("api_request", "management")
        resource_monitor.record_service_activity("management", "request")

        summary = resource_monitor.get_summary()
        return web.json_response(summary)

    except Exception as e:
        logger.error(f"Error getting system metrics: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_system_snapshot(request: web.Request) -> web.Response:
    """Get detailed current metrics snapshot."""
    try:
        idle_manager.record_activity("api_request", "management")

        snapshot = resource_monitor.get_current_snapshot()
        return web.json_response(snapshot)

    except Exception as e:
        logger.error(f"Error getting system snapshot: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_power_history(request: web.Request) -> web.Response:
    """Get power metrics history for charts."""
    try:
        limit = int(request.query.get("limit", "100"))
        history = resource_monitor.get_power_history(limit)
        return web.json_response({
            "history": history,
            "count": len(history),
            "interval_seconds": resource_monitor.collection_interval,
        })

    except Exception as e:
        logger.error(f"Error getting power history: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_process_history(request: web.Request) -> web.Response:
    """Get per-process metrics history."""
    try:
        limit = int(request.query.get("limit", "100"))
        history = resource_monitor.get_process_history(limit)
        return web.json_response({
            "history": history,
            "count": len(history),
        })

    except Exception as e:
        logger.error(f"Error getting process history: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_idle_status(request: web.Request) -> web.Response:
    """Get current idle manager status."""
    try:
        status = idle_manager.get_status()
        return web.json_response(status)

    except Exception as e:
        logger.error(f"Error getting idle status: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_set_idle_config(request: web.Request) -> web.Response:
    """Configure idle management settings."""
    try:
        data = await request.json()

        # Set power mode
        if "mode" in data:
            mode = data["mode"]
            if not idle_manager.set_mode(mode):
                return web.json_response({"error": f"Unknown mode: {mode}"}, status=400)

        # Set custom thresholds
        if "thresholds" in data:
            idle_manager.set_thresholds(data["thresholds"])

        # Enable/disable
        if "enabled" in data:
            idle_manager.enabled = data["enabled"]

        await broadcast_message("idle_config_changed", idle_manager.get_status())
        return web.json_response({"status": "ok", "config": idle_manager.get_status()})

    except Exception as e:
        logger.error(f"Error setting idle config: {e}")
        return web.json_response({"error": str(e)}, status=400)


async def handle_idle_keep_awake(request: web.Request) -> web.Response:
    """Keep system awake for specified duration."""
    try:
        data = await request.json()
        duration = int(data.get("duration_seconds", 3600))  # Default 1 hour

        idle_manager.keep_awake(duration)
        await broadcast_message("idle_keep_awake", {"duration": duration})

        return web.json_response({
            "status": "ok",
            "keeping_awake_for": duration,
        })

    except Exception as e:
        logger.error(f"Error setting keep awake: {e}")
        return web.json_response({"error": str(e)}, status=400)


async def handle_idle_cancel_keep_awake(request: web.Request) -> web.Response:
    """Cancel keep-awake override."""
    try:
        idle_manager.cancel_keep_awake()
        await broadcast_message("idle_keep_awake_cancelled", {})
        return web.json_response({"status": "ok"})

    except Exception as e:
        logger.error(f"Error cancelling keep awake: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_idle_force_state(request: web.Request) -> web.Response:
    """Force transition to a specific idle state."""
    try:
        data = await request.json()
        state_name = data.get("state", "").lower()

        state_map = {
            "active": IdleState.ACTIVE,
            "warm": IdleState.WARM,
            "cool": IdleState.COOL,
            "cold": IdleState.COLD,
            "dormant": IdleState.DORMANT,
        }

        if state_name not in state_map:
            return web.json_response({
                "error": f"Unknown state: {state_name}",
                "valid_states": list(state_map.keys())
            }, status=400)

        await idle_manager.force_state(state_map[state_name])
        await broadcast_message("idle_state_changed", idle_manager.get_status())

        return web.json_response({
            "status": "ok",
            "new_state": state_name,
        })

    except Exception as e:
        logger.error(f"Error forcing idle state: {e}")
        return web.json_response({"error": str(e)}, status=400)


async def handle_get_power_modes(request: web.Request) -> web.Response:
    """Get available power modes."""
    try:
        modes = idle_manager.get_available_modes()
        return web.json_response({
            "modes": modes,
            "current": idle_manager.current_mode,
        })

    except Exception as e:
        logger.error(f"Error getting power modes: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_idle_history(request: web.Request) -> web.Response:
    """Get idle state transition history."""
    try:
        limit = int(request.query.get("limit", "50"))
        history = idle_manager.get_transition_history(limit)
        return web.json_response({
            "history": history,
            "count": len(history),
        })

    except Exception as e:
        logger.error(f"Error getting idle history: {e}")
        return web.json_response({"error": str(e)}, status=500)


# =============================================================================
# Diagnostic Logging API Endpoints
# =============================================================================


async def handle_get_diagnostic_config(request: web.Request) -> web.Response:
    """Get current diagnostic logging configuration."""
    try:
        config = get_diagnostic_config()
        return web.json_response({
            "success": True,
            "config": config,
        })
    except Exception as e:
        logger.error(f"Error getting diagnostic config: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_set_diagnostic_config(request: web.Request) -> web.Response:
    """
    Update diagnostic logging configuration.

    Request body options:
    {
        "enabled": true/false,       // Toggle diagnostic logging on/off
        "level": "DEBUG",            // DEBUG, INFO, WARNING, ERROR
        "log_requests": true/false,  // Log HTTP requests
        "log_responses": true/false, // Log HTTP responses
        "log_timing": true/false     // Log operation timing
    }
    """
    try:
        data = await request.json()

        # Update config with provided values
        updated_config = set_diagnostic_config(**data)

        diag_logger.info("Diagnostic config updated via API", context=updated_config)

        return web.json_response({
            "success": True,
            "config": updated_config,
            "message": "Diagnostic logging configuration updated"
        })

    except Exception as e:
        logger.error(f"Error setting diagnostic config: {e}")
        return web.json_response({"error": str(e)}, status=400)


async def handle_diagnostic_toggle(request: web.Request) -> web.Response:
    """
    Quick toggle for diagnostic logging on/off.

    POST /api/system/diagnostic/toggle
    Body: {"enabled": true} or {"enabled": false}
    """
    try:
        data = await request.json()
        enabled = data.get("enabled", not diag_logger.is_enabled())

        if enabled:
            diag_logger.enable()
            message = "Diagnostic logging ENABLED"
        else:
            diag_logger.disable()
            message = "Diagnostic logging DISABLED"

        logger.info(message)

        return web.json_response({
            "success": True,
            "enabled": diag_logger.is_enabled(),
            "message": message
        })

    except Exception as e:
        logger.error(f"Error toggling diagnostic logging: {e}")
        return web.json_response({"error": str(e)}, status=400)


# =============================================================================
# Profile Management API Endpoints
# =============================================================================


async def handle_get_profile(request: web.Request) -> web.Response:
    """Get a specific power profile by ID."""
    try:
        profile_id = request.match_info.get("profile_id")
        profile = idle_manager.get_profile(profile_id)

        if profile is None:
            return web.json_response({"error": "Profile not found"}, status=404)

        return web.json_response(profile)

    except Exception as e:
        logger.error(f"Error getting profile: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_create_profile(request: web.Request) -> web.Response:
    """Create a new custom power profile."""
    try:
        data = await request.json()

        # Validate required fields
        required = ["id", "name", "thresholds"]
        for field in required:
            if field not in data:
                return web.json_response(
                    {"error": f"Missing required field: {field}"},
                    status=400
                )

        # Validate thresholds
        thresholds = data["thresholds"]
        for key in ["warm", "cool", "cold", "dormant"]:
            if key not in thresholds:
                return web.json_response(
                    {"error": f"Missing threshold: {key}"},
                    status=400
                )
            if not isinstance(thresholds[key], (int, float)) or thresholds[key] < 0:
                return web.json_response(
                    {"error": f"Invalid threshold value for {key}"},
                    status=400
                )

        success = idle_manager.create_profile(
            profile_id=data["id"],
            name=data["name"],
            description=data.get("description", ""),
            thresholds=thresholds,
            enabled=data.get("enabled", True),
        )

        if not success:
            return web.json_response(
                {"error": "Could not create profile (ID may already exist or is reserved)"},
                status=400
            )

        return web.json_response({
            "status": "created",
            "profile": idle_manager.get_profile(data["id"].lower().replace(" ", "_")),
        })

    except json.JSONDecodeError:
        return web.json_response({"error": "Invalid JSON"}, status=400)
    except Exception as e:
        logger.error(f"Error creating profile: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_update_profile(request: web.Request) -> web.Response:
    """Update an existing custom power profile."""
    try:
        profile_id = request.match_info.get("profile_id")
        data = await request.json()

        success = idle_manager.update_profile(
            profile_id=profile_id,
            name=data.get("name"),
            description=data.get("description"),
            thresholds=data.get("thresholds"),
            enabled=data.get("enabled"),
        )

        if not success:
            return web.json_response(
                {"error": "Could not update profile (not found or is built-in)"},
                status=400
            )

        return web.json_response({
            "status": "updated",
            "profile": idle_manager.get_profile(profile_id),
        })

    except json.JSONDecodeError:
        return web.json_response({"error": "Invalid JSON"}, status=400)
    except Exception as e:
        logger.error(f"Error updating profile: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_delete_profile(request: web.Request) -> web.Response:
    """Delete a custom power profile."""
    try:
        profile_id = request.match_info.get("profile_id")

        success = idle_manager.delete_profile(profile_id)

        if not success:
            return web.json_response(
                {"error": "Could not delete profile (not found or is built-in)"},
                status=400
            )

        return web.json_response({"status": "deleted", "profile_id": profile_id})

    except Exception as e:
        logger.error(f"Error deleting profile: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_duplicate_profile(request: web.Request) -> web.Response:
    """Duplicate an existing profile as a new custom profile."""
    try:
        source_id = request.match_info.get("profile_id")
        data = await request.json()

        if "new_id" not in data or "new_name" not in data:
            return web.json_response(
                {"error": "Missing required fields: new_id, new_name"},
                status=400
            )

        success = idle_manager.duplicate_profile(
            source_id=source_id,
            new_id=data["new_id"],
            new_name=data["new_name"],
        )

        if not success:
            return web.json_response(
                {"error": "Could not duplicate profile"},
                status=400
            )

        new_id = data["new_id"].lower().replace(" ", "_")
        return web.json_response({
            "status": "duplicated",
            "profile": idle_manager.get_profile(new_id),
        })

    except json.JSONDecodeError:
        return web.json_response({"error": "Invalid JSON"}, status=400)
    except Exception as e:
        logger.error(f"Error duplicating profile: {e}")
        return web.json_response({"error": str(e)}, status=500)


# =============================================================================
# Admin User Management
# =============================================================================

async def handle_get_admin_users(request: web.Request) -> web.Response:
    """Get all users for admin panel."""
    try:
        auth_api = request.app.get("auth_api")
        if not auth_api:
            return web.json_response({"error": "Auth not configured"}, status=503)

        async with auth_api.db.acquire() as conn:
            rows = await conn.fetch("""
                SELECT id, email, display_name, role, is_active, is_locked, created_at, last_login_at
                FROM users
                ORDER BY created_at DESC
            """)

            def get_status(row):
                if row.get("is_locked"):
                    return "suspended"
                elif row.get("is_active", True):
                    return "active"
                else:
                    return "inactive"

            users = [
                {
                    "id": str(row["id"]),
                    "email": row["email"],
                    "display_name": row["display_name"],
                    "role": row.get("role", "user"),
                    "status": get_status(row),
                    "created_at": row["created_at"].isoformat() if row["created_at"] else None,
                    "last_login": row["last_login_at"].isoformat() if row.get("last_login_at") else None,
                }
                for row in rows
            ]

            return web.json_response({"users": users, "count": len(users)})

    except Exception as e:
        logger.error(f"Error getting users: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_create_admin_user(request: web.Request) -> web.Response:
    """Create a new user via admin panel."""
    try:
        auth_api = request.app.get("auth_api")
        if not auth_api:
            return web.json_response({"error": "Auth not configured"}, status=503)

        data = await request.json()
        email = data.get("email", "").strip().lower()
        password = data.get("password", "")
        display_name = data.get("display_name", "").strip()
        role = data.get("role", "user")

        if not email or not password:
            return web.json_response(
                {"error": "Email and password required"},
                status=400
            )

        if len(password) < 8:
            return web.json_response(
                {"error": "Password must be at least 8 characters"},
                status=400
            )

        password_hash = auth_api.password_service.hash_password(password)
        user_id = str(uuid.uuid4())

        async with auth_api.db.acquire() as conn:
            # Check if email exists
            existing = await conn.fetchval(
                "SELECT id FROM users WHERE email = $1", email
            )
            if existing:
                return web.json_response(
                    {"error": "Email already registered"},
                    status=409
                )

            # Create user
            await conn.execute("""
                INSERT INTO users (id, email, password_hash, display_name, role, is_active, created_at)
                VALUES ($1, $2, $3, $4, $5, true, NOW())
            """, uuid.UUID(user_id), email, password_hash, display_name or email.split("@")[0], role)

            return web.json_response({
                "status": "created",
                "user": {
                    "id": user_id,
                    "email": email,
                    "display_name": display_name or email.split("@")[0],
                    "role": role,
                }
            }, status=201)

    except json.JSONDecodeError:
        return web.json_response({"error": "Invalid JSON"}, status=400)
    except Exception as e:
        logger.error(f"Error creating user: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_delete_admin_user(request: web.Request) -> web.Response:
    """Delete a user via admin panel."""
    try:
        auth_api = request.app.get("auth_api")
        if not auth_api:
            return web.json_response({"error": "Auth not configured"}, status=503)

        user_id = request.match_info.get("user_id")
        if not user_id:
            return web.json_response({"error": "User ID required"}, status=400)

        async with auth_api.db.acquire() as conn:
            # Delete user sessions first
            await conn.execute(
                "DELETE FROM sessions WHERE user_id = $1",
                uuid.UUID(user_id)
            )
            # Delete user
            result = await conn.execute(
                "DELETE FROM users WHERE id = $1",
                uuid.UUID(user_id)
            )

            if result == "DELETE 0":
                return web.json_response({"error": "User not found"}, status=404)

            return web.json_response({"status": "deleted", "user_id": user_id})

    except Exception as e:
        logger.error(f"Error deleting user: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_metrics_history_hourly(request: web.Request) -> web.Response:
    """Get hourly aggregated metrics history."""
    try:
        days = int(request.query.get("days", "7"))
        history = metrics_history.get_hourly_history(days)
        return web.json_response({
            "history": history,
            "count": len(history),
            "days_requested": days,
        })

    except Exception as e:
        logger.error(f"Error getting hourly history: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_metrics_history_daily(request: web.Request) -> web.Response:
    """Get daily aggregated metrics history."""
    try:
        days = int(request.query.get("days", "30"))
        history = metrics_history.get_daily_history(days)
        return web.json_response({
            "history": history,
            "count": len(history),
            "days_requested": days,
        })

    except Exception as e:
        logger.error(f"Error getting daily history: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_metrics_history_summary(request: web.Request) -> web.Response:
    """Get summary statistics of historical metrics."""
    try:
        summary = metrics_history.get_summary_stats()
        return web.json_response(summary)

    except Exception as e:
        logger.error(f"Error getting metrics summary: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_unload_models(request: web.Request) -> web.Response:
    """Manually unload all models to save resources."""
    try:
        results = {"ollama": False, "vibevoice": False}

        # Unload Ollama models
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get("http://localhost:11434/api/ps", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        for model in data.get("models", []):
                            model_name = model.get("name")
                            if model_name:
                                await session.post(
                                    "http://localhost:11434/api/generate",
                                    json={"model": model_name, "keep_alive": 0},
                                    timeout=aiohttp.ClientTimeout(total=10)
                                )
                                logger.info(f"Unloaded Ollama model: {model_name}")
                        results["ollama"] = True
        except Exception as e:
            logger.debug(f"Ollama unload failed: {e}")

        # Signal VibeVoice to unload (if it supports the endpoint)
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    "http://localhost:8880/admin/unload",
                    timeout=aiohttp.ClientTimeout(total=5)
                ) as resp:
                    results["vibevoice"] = resp.status == 200
        except Exception as e:
            logger.debug(f"VibeVoice unload failed: {e}")

        await broadcast_message("models_unloaded", results)
        return web.json_response({
            "status": "ok",
            "results": results,
        })

    except Exception as e:
        logger.error(f"Error unloading models: {e}")
        return web.json_response({"error": str(e)}, status=500)


# =============================================================================
# Background Tasks
# =============================================================================

async def _metrics_recording_loop():
    """Background task to record metrics samples to history"""
    logger.info("[MetricsRecorder] Starting metrics recording loop")
    while True:
        try:
            await asyncio.sleep(30)  # Record every 30 seconds

            # Get current metrics summary
            summary = resource_monitor.get_summary()
            idle_state = idle_manager.current_state.value

            # Record to persistent history
            metrics_history.record_sample(summary, idle_state)

        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"[MetricsRecorder] Error: {e}")
            await asyncio.sleep(30)


# =============================================================================
# Application Setup
# =============================================================================

def setup_auth_routes(app: web.Application, db_pool) -> bool:
    """
    Initialize auth routes with database connection.

    Call this function after database pool is created to enable auth endpoints.
    Requires AUTH_SECRET_KEY to be set in environment.

    Args:
        app: The aiohttp application
        db_pool: asyncpg connection pool

    Returns:
        True if auth routes were registered, False otherwise
    """
    if "token_service" not in app:
        logger.warning("Auth not initialized - AUTH_SECRET_KEY not set")
        return False

    token_service = app["token_service"]
    rate_limiter = app.get("rate_limiter")

    auth_api = AuthAPI(
        db_pool=db_pool,
        token_service=token_service,
        rate_limiter=rate_limiter,
    )

    register_auth_routes(app, auth_api)
    app["auth_api"] = auth_api

    logger.info("Authentication routes registered")
    return True


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
    app.router.add_post("/api/models/{model_id}/load", handle_load_model)
    app.router.add_post("/api/models/{model_id}/unload", handle_unload_model)
    app.router.add_post("/api/models/pull", handle_pull_model)
    app.router.add_delete("/api/models/{model_id}", handle_delete_model)
    app.router.add_get("/api/models/config", handle_get_model_config)
    app.router.add_post("/api/models/config", handle_save_model_config)
    app.router.add_get("/api/models/capabilities", handle_get_model_capabilities)
    app.router.add_get("/api/models/{model_id}/parameters", handle_get_model_parameters)
    app.router.add_post("/api/models/{model_id}/parameters", handle_save_model_parameters)

    # Managed Services
    app.router.add_get("/api/services", handle_get_services)
    app.router.add_post("/api/services/{service_id}/start", handle_start_service)
    app.router.add_post("/api/services/{service_id}/stop", handle_stop_service)
    app.router.add_post("/api/services/{service_id}/restart", handle_restart_service)
    app.router.add_post("/api/services/start-all", handle_start_all_services)
    app.router.add_post("/api/services/stop-all", handle_stop_all_services)

    # Curriculum
    app.router.add_get("/api/curricula", handle_get_curricula)
    app.router.add_get("/api/curricula/archived", handle_get_archived_curricula)  # Must be before {curriculum_id}
    app.router.add_get("/api/curricula/{curriculum_id}", handle_get_curriculum_detail)
    app.router.add_get("/api/curricula/{curriculum_id}/full", handle_get_curriculum_full)
    app.router.add_get("/api/curricula/{curriculum_id}/topics/{topic_id}/transcript", handle_get_topic_transcript)
    app.router.add_get("/api/curricula/{curriculum_id}/topics/{topic_id}/stream-audio", handle_stream_topic_audio)
    app.router.add_post("/api/curricula/reload", handle_reload_curricula)
    app.router.add_post("/api/curricula/import", handle_import_curriculum)
    app.router.add_put("/api/curricula/{curriculum_id}", handle_save_curriculum)
    app.router.add_delete("/api/curricula/{curriculum_id}", handle_delete_curriculum)
    app.router.add_post("/api/curricula/{curriculum_id}/archive", handle_archive_curriculum)
    app.router.add_post("/api/curricula/archived/{file_name}/unarchive", handle_unarchive_curriculum)
    app.router.add_delete("/api/curricula/archived/{file_name}", handle_delete_archived_curriculum)

    # Visual Asset Management
    app.router.add_post("/api/curricula/{curriculum_id}/topics/{topic_id}/assets", handle_upload_visual_asset)
    app.router.add_delete("/api/curricula/{curriculum_id}/topics/{topic_id}/assets/{asset_id}", handle_delete_visual_asset)
    app.router.add_patch("/api/curricula/{curriculum_id}/topics/{topic_id}/assets/{asset_id}", handle_update_visual_asset)

    # Asset Pre-Download & Caching
    app.router.add_post("/api/curricula/{curriculum_id}/preload-assets", handle_preload_curriculum_assets)
    app.router.add_get("/api/curricula/{curriculum_id}/full-with-assets", handle_get_curriculum_with_assets)

    # Plugin Management System
    register_plugin_routes(app)

    # Curriculum Import System (Source Browser)
    register_import_routes(app)

    # Curriculum Reprocessing System
    register_reprocess_routes(app)

    # Media Generation System (Diagrams, Formulas, Maps)
    register_media_routes(app)

    # TTS Cache System
    register_tts_routes(app)

    # Authentication System
    # Note: Auth requires a database pool. For now, we set up the routes but
    # auth_api initialization with db pool happens in main() after db setup.
    # The auth routes are registered here as placeholders; full initialization
    # happens when AUTH_SECRET_KEY is set in environment.
    auth_secret = os.environ.get("AUTH_SECRET_KEY")
    if auth_secret:
        token_config = TokenConfig(
            secret_key=auth_secret,
            algorithm=os.environ.get("AUTH_ALGORITHM", "HS256"),
            access_token_lifetime_minutes=int(os.environ.get("AUTH_ACCESS_TOKEN_MINUTES", "15")),
            refresh_token_lifetime_days=int(os.environ.get("AUTH_REFRESH_TOKEN_DAYS", "30")),
        )
        token_service = TokenService(token_config)
        rate_limiter = RateLimiter()

        # Store in app for later use when db pool is available
        app["token_service"] = token_service
        app["rate_limiter"] = rate_limiter

        # Set up token service for middleware
        setup_token_service(app, auth_secret)

        # Add auth middleware (applies JWT validation to protected routes)
        app.middlewares.append(auth_middleware)
        app.middlewares.append(rate_limit_middleware)

        logger.info("Authentication system initialized (routes pending database connection)")
    else:
        logger.warning("AUTH_SECRET_KEY not set - authentication disabled")

    # Latency Test Harness
    register_latency_harness_routes(app)

    # FOV Context Management System
    setup_fov_context_routes(app)

    # Set up callback to reload curricula when import completes
    def on_import_complete(progress):
        """Called when an import job completes successfully."""
        logger.info(f"Import completed: {progress.config.output_name}, reloading curricula")
        state.reload_curricula()
        # Also broadcast to connected clients
        asyncio.create_task(broadcast_message("curriculum_imported", {
            "id": progress.config.output_name,
            "title": getattr(progress, "_course_title", progress.config.output_name),
        }))

    set_import_complete_callback(on_import_complete)

    # WebSocket
    app.router.add_get("/ws", handle_websocket)

    # System Metrics & Resource Monitoring
    app.router.add_get("/api/system/metrics", handle_get_system_metrics)
    app.router.add_get("/api/system/snapshot", handle_get_system_snapshot)
    app.router.add_get("/api/system/power/history", handle_get_power_history)
    app.router.add_get("/api/system/processes/history", handle_get_process_history)

    # Idle Management & Power Modes
    app.router.add_get("/api/system/idle/status", handle_get_idle_status)
    app.router.add_post("/api/system/idle/config", handle_set_idle_config)
    app.router.add_get("/api/system/idle/history", handle_get_idle_history)
    app.router.add_get("/api/system/idle/modes", handle_get_power_modes)
    app.router.add_post("/api/system/idle/keep-awake", handle_idle_keep_awake)
    app.router.add_post("/api/system/idle/cancel-keep-awake", handle_idle_cancel_keep_awake)
    app.router.add_post("/api/system/idle/force-state", handle_idle_force_state)
    app.router.add_post("/api/system/unload-models", handle_unload_models)

    # Diagnostic Logging
    app.router.add_get("/api/system/diagnostic", handle_get_diagnostic_config)
    app.router.add_post("/api/system/diagnostic", handle_set_diagnostic_config)
    app.router.add_post("/api/system/diagnostic/toggle", handle_diagnostic_toggle)

    # Profile Management
    app.router.add_get("/api/system/profiles/{profile_id}", handle_get_profile)
    app.router.add_post("/api/system/profiles", handle_create_profile)
    app.router.add_put("/api/system/profiles/{profile_id}", handle_update_profile)
    app.router.add_delete("/api/system/profiles/{profile_id}", handle_delete_profile)
    app.router.add_post("/api/system/profiles/{profile_id}/duplicate", handle_duplicate_profile)

    # Admin User Management
    app.router.add_get("/api/admin/users", handle_get_admin_users)
    app.router.add_post("/api/admin/users", handle_create_admin_user)
    app.router.add_delete("/api/admin/users/{user_id}", handle_delete_admin_user)

    # Historical Metrics (persisted)
    app.router.add_get("/api/system/history/hourly", handle_get_metrics_history_hourly)
    app.router.add_get("/api/system/history/daily", handle_get_metrics_history_daily)
    app.router.add_get("/api/system/history/summary", handle_get_metrics_history_summary)

    # Static files and dashboard
    static_dir = Path(__file__).parent / "static"
    if static_dir.exists():
        app.router.add_static("/static", static_dir)

    # Serve curriculum assets from the assets directory
    assets_dir = Path(__file__).parent.parent.parent / "curriculum" / "assets"
    if assets_dir.exists():
        app.router.add_static("/assets/curriculum/assets", assets_dir)
        logger.info(f"Serving curriculum assets from: {assets_dir}")

    app.router.add_get("/", handle_dashboard)

    # Startup hook to detect existing services and load curricula
    async def on_startup(app):
        await detect_existing_processes()
        state._load_curricula()  # Load all UMCF curricula on startup

        # Initialize TTS cache
        cache_dir = Path(__file__).parent / "data" / "tts_cache"
        tts_cache = TTSCache(cache_dir)
        await tts_cache.initialize()
        app["tts_cache"] = tts_cache

        # Initialize TTS resource pool (priority-based generation)
        resource_pool = TTSResourcePool(
            max_concurrent_live=7,      # Live users get 7 concurrent slots
            max_concurrent_background=3  # Background pre-generation gets 3
        )
        app["tts_resource_pool"] = resource_pool

        # Initialize TTS prefetcher with resource pool
        prefetcher = CurriculumPrefetcher(tts_cache, resource_pool)
        app["tts_prefetcher"] = prefetcher

        # Initialize session manager (handles both FOV and user sessions)
        session_manager = SessionManager()
        app["session_manager"] = session_manager

        # Initialize session-cache integration bridge
        session_cache = SessionCacheIntegration(tts_cache, resource_pool, prefetcher)
        app["session_cache"] = session_cache

        # Initialize scheduled deployment manager
        deployment_manager = ScheduledDeploymentManager(tts_cache, resource_pool)

        # Set up segment loader for deployment manager
        async def load_curriculum_segments(curriculum_id: str) -> list:
            """Load all segments from a curriculum."""
            curriculum = state.curriculum_raw.get(curriculum_id)
            if not curriculum:
                return []
            segments = []
            content = curriculum.get("content", [])
            if content and content[0].get("children"):
                for topic in content[0]["children"]:
                    transcript = topic.get("transcript", {})
                    for seg in transcript.get("segments", []):
                        if seg.get("content"):
                            segments.append(seg["content"])
            return segments

        deployment_manager.set_segment_loader(load_curriculum_segments)
        app["deployment_manager"] = deployment_manager

        # Initialize audio WebSocket handler
        audio_ws_handler = AudioWebSocketHandler(session_manager, session_cache)
        register_audio_websocket(app, audio_ws_handler)

        # Register deployment API routes
        register_deployment_routes(app)

        logger.info("[Startup] TTS cache, resource pool, session management, and deployment API initialized")

        # Initialize database connection for auth
        database_url = os.environ.get("DATABASE_URL")
        if database_url and "token_service" in app:
            try:
                db_pool = await asyncpg.create_pool(database_url, min_size=2, max_size=10)
                app["db_pool"] = db_pool
                if setup_auth_routes(app, db_pool):
                    logger.info("[Startup] Database connected and auth routes initialized")
                else:
                    logger.warning("[Startup] Auth routes setup failed")
            except Exception as e:
                logger.error(f"[Startup] Database connection failed: {e}")
        elif "token_service" in app:
            logger.warning("[Startup] DATABASE_URL not set, auth database features disabled")

        # Start resource monitoring and idle management
        await resource_monitor.start()
        await idle_manager.start()
        await metrics_history.start()

        # Start metrics recording task
        asyncio.create_task(_metrics_recording_loop())

        # Start latency test harness
        await init_latency_harness()

        logger.info("[Startup] Resource monitoring, idle management, metrics history, and latency harness started")

        # Log diagnostic logging status
        diag_logger.info("Server startup complete", context={
            "host": HOST,
            "port": PORT,
            "diagnostic_enabled": diag_logger.is_enabled()
        })

    # Cleanup hook to stop background tasks
    async def on_cleanup(app):
        # Close database pool if it exists
        if "db_pool" in app:
            await app["db_pool"].close()
            logger.info("[Cleanup] Database pool closed")

        # Cleanup inactive user sessions
        if "session_manager" in app:
            removed = app["session_manager"].cleanup_inactive_user_sessions(max_inactive_minutes=0)
            logger.info(f"[Cleanup] Removed {removed} user sessions")

        # Cleanup old deployments
        if "deployment_manager" in app:
            removed = app["deployment_manager"].cleanup_old_deployments(max_age_days=0)
            logger.info(f"[Cleanup] Removed {removed} old deployments")

        # Shutdown TTS cache
        if "tts_cache" in app:
            await app["tts_cache"].shutdown()
            logger.info("[Cleanup] TTS cache saved")

        await resource_monitor.stop()
        await idle_manager.stop()
        await metrics_history.stop()
        await shutdown_latency_harness()
        logger.info("[Cleanup] Background tasks stopped")

    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)

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
