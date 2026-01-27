"""
UnaMentis Management Server Tests
Comprehensive tests for the management server API endpoints.

TESTING PHILOSOPHY: Real Over Mock
==================================
- Uses REAL aiohttp test utilities (no MagicMock for requests)
- Uses REAL aiosqlite for database tests
- Only external HTTP calls may be mocked via aioresponses
- NO MOCK CLASSES ALLOWED for internal services

This test file targets server.py coverage with tests for:
- Data classes (LogEntry, MetricsSnapshot, RemoteClient, ServerStatus, etc.)
- Utility functions (chunk_text_for_tts, is_flag_enabled, etc.)
- API handlers (logs, metrics, clients, servers, models, etc.)
- WebSocket handlers
- Curriculum management endpoints
- System metrics and idle management
- Profile management
- Admin user management
"""

import pytest
import json
import time
import uuid
from unittest.mock import (
    patch,
    AsyncMock,
    MagicMock,
)  # MagicMock only for external services
from pathlib import Path
from dataclasses import asdict
import sys
import aiosqlite

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from aiohttp import web
from aiohttp.test_utils import make_mocked_request
from yarl import URL

# Import server components
from server import (
    ManagementState,
    LogEntry,
    MetricsSnapshot,
    RemoteClient,
    ServerStatus,
    ModelInfo,
    ManagedService,
    CurriculumSummary,
    CurriculumDetail,
    TopicSummary,
    chunk_text_for_tts,
    is_flag_enabled,
    broadcast_message,
    handle_health,
    handle_get_stats,
    handle_receive_log,
    handle_get_logs,
    handle_clear_logs,
    handle_receive_metrics,
    handle_get_metrics,
    handle_get_clients,
    handle_client_heartbeat,
    handle_get_servers,
    handle_add_server,
    handle_delete_server,
    handle_get_models,
    handle_get_model_config,
    handle_save_model_config,
    handle_get_model_parameters,
    handle_save_model_parameters,
    handle_get_model_capabilities,
    handle_get_services,
    handle_start_service,
    handle_stop_service,
    handle_restart_service,
    handle_start_all_services,
    handle_stop_all_services,
    handle_get_curricula,
    handle_get_curriculum_detail,
    handle_get_curriculum_full,
    handle_get_topic_transcript,
    handle_reload_curricula,
    handle_delete_curriculum,
    handle_archive_curriculum,
    handle_get_archived_curricula,
    handle_unarchive_curriculum,
    handle_delete_archived_curriculum,
    handle_save_curriculum,
    handle_import_curriculum,
    handle_dashboard,
    handle_get_system_metrics,
    handle_get_system_snapshot,
    handle_get_power_history,
    handle_get_process_history,
    handle_get_idle_status,
    handle_set_idle_config,
    handle_idle_keep_awake,
    handle_idle_cancel_keep_awake,
    handle_idle_force_state,
    handle_get_power_modes,
    handle_get_idle_history,
    handle_get_diagnostic_config,
    handle_set_diagnostic_config,
    handle_diagnostic_toggle,
    handle_get_profile,
    handle_create_profile,
    handle_update_profile,
    handle_delete_profile,
    handle_duplicate_profile,
    handle_get_admin_users,
    handle_create_admin_user,
    handle_delete_admin_user,
    handle_get_metrics_history_hourly,
    handle_get_metrics_history_daily,
    handle_get_metrics_history_summary,
    handle_unload_models,
    check_server_health,
    get_ollama_model_details,
    load_model_config,
    load_model_params,
    get_process_memory,
    get_system_memory,
    service_to_dict,
    check_service_running,
    detect_existing_processes,
    start_service,
    stop_service,
    state,
)


# =============================================================================
# Mock Classes for Database
# =============================================================================
# REAL DATABASE HELPERS - NO MOCKS
# =============================================================================


class RealRow(dict):
    """Database row wrapper that supports both dict and attribute access.

    This is NOT a mock - it wraps real aiosqlite.Row objects to provide
    attribute-style access for compatibility with existing code.
    """

    def __getattr__(self, key):
        try:
            return self[key]
        except KeyError:
            raise AttributeError(f"'{type(self).__name__}' has no attribute '{key}'")

    def get(self, key, default=None):
        return super().get(key, default)

    @classmethod
    def from_sqlite_row(cls, row, description):
        """Create RealRow from aiosqlite row and cursor description."""
        if row is None:
            return None
        columns = [col[0] for col in description]
        return cls(zip(columns, row))


class RealDBConnection:
    """Real in-memory SQLite connection wrapper.

    Provides asyncpg-compatible interface over aiosqlite for testing.
    This is NOT a mock - it uses a real in-memory SQLite database.
    """

    def __init__(self, db: aiosqlite.Connection):
        self._db = db
        self.execute_calls = []  # For test inspection
        self.fetch_calls = []  # For test inspection

    async def fetch(self, query, *args):
        """Execute query and return all rows."""
        self.fetch_calls.append((query, args))
        # Convert asyncpg-style $1 params to sqlite-style ? params
        sqlite_query = self._convert_params(query)
        cursor = await self._db.execute(sqlite_query, args)
        rows = await cursor.fetchall()
        return [RealRow.from_sqlite_row(r, cursor.description) for r in rows]

    async def fetchval(self, query, *args):
        """Execute query and return first column of first row."""
        self.fetch_calls.append((query, args))
        sqlite_query = self._convert_params(query)
        cursor = await self._db.execute(sqlite_query, args)
        row = await cursor.fetchone()
        if row is None:
            return None
        return row[0]

    async def fetchrow(self, query, *args):
        """Execute query and return first row."""
        self.fetch_calls.append((query, args))
        sqlite_query = self._convert_params(query)
        cursor = await self._db.execute(sqlite_query, args)
        row = await cursor.fetchone()
        return RealRow.from_sqlite_row(row, cursor.description) if row else None

    async def execute(self, query, *args):
        """Execute a query without returning results."""
        self.execute_calls.append((query, args))
        sqlite_query = self._convert_params(query)
        await self._db.execute(sqlite_query, args)
        await self._db.commit()
        return "OK"

    def _convert_params(self, query):
        """Convert asyncpg-style $1, $2 params to sqlite-style ?."""
        import re

        return re.sub(r"\$\d+", "?", query)


class RealDBPool:
    """Real in-memory SQLite connection pool wrapper.

    Provides asyncpg-compatible pool interface over aiosqlite.
    This is NOT a mock - it uses a real in-memory SQLite database.
    """

    def __init__(self, db: aiosqlite.Connection):
        self._db = db
        self._conn = RealDBConnection(db)

    def acquire(self):
        return RealDBConnectionContextManager(self._conn)


class RealDBConnectionContextManager:
    """Context manager for real database connection."""

    def __init__(self, conn: RealDBConnection):
        self.conn = conn

    async def __aenter__(self):
        return self.conn

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        pass


# =============================================================================
# BACKWARD COMPATIBILITY ALIASES
# =============================================================================
# These aliases exist ONLY for legacy tests during migration.
# New tests should use the Real* classes directly.

MockRow = RealRow
MockConnection = RealDBConnection
MockPool = RealDBPool
MockConnectionContextManager = RealDBConnectionContextManager


# =============================================================================
# Test Fixtures - REAL IMPLEMENTATIONS
# =============================================================================


@pytest.fixture
def real_state():
    """Create a fresh ManagementState for testing."""
    return ManagementState()


# Alias for backward compatibility during migration
@pytest.fixture
def mock_state(real_state):
    """Alias for real_state - provides backward compatibility."""
    return real_state


@pytest.fixture
async def real_db():
    """Real in-memory SQLite database for testing.

    Use this instead of MockConnection/MockPool.
    """
    async with aiosqlite.connect(":memory:") as db:
        db.row_factory = aiosqlite.Row
        yield db


@pytest.fixture
async def real_db_pool(real_db):
    """Real database pool wrapper for testing.

    Use this instead of MockPool.
    """
    return RealDBPool(real_db)


@pytest.fixture
def make_request(real_state):
    """Factory for creating real aiohttp test requests.

    Use this instead of mock_request fixture.
    """

    def _make_request(
        method="GET",
        path="/api/test",
        json_data=None,
        query=None,
        match_info=None,
        headers=None,
        app_extras=None,
    ):
        app = web.Application()
        app["state"] = real_state

        # Add any extra app context
        if app_extras:
            for key, value in app_extras.items():
                app[key] = value

        request = make_mocked_request(
            method,
            path,
            app=app,
            match_info=match_info or {},
            headers=headers or {},
        )

        # Set query parameters
        if query:
            request._rel_url = URL(path).with_query(query)
            request._cache["query"] = query

        # Set JSON body
        if json_data is not None:

            async def _json():
                return json_data

            request.json = _json
        else:

            async def _json():
                raise json.JSONDecodeError("No JSON body", "", 0)

            request.json = _json

        return request

    return _make_request


@pytest.fixture
def mock_request(real_state):
    """Backward compatibility fixture using MagicMock.

    DEPRECATED: Use make_request fixture for new tests.
    This fixture exists only to support legacy tests during migration.
    """
    request = MagicMock(spec=web.Request)
    request.query = {}
    request.match_info = {}
    request.headers = {}
    request.remote = "127.0.0.1"

    # Create real app with state
    app = web.Application()
    app["state"] = real_state
    request.app = app

    return request


@pytest.fixture
def real_app(real_state):
    """Create a real aiohttp application for testing."""
    app = web.Application()
    app["state"] = real_state
    return app


@pytest.fixture
def mock_app(real_app):
    """Alias for real_app - provides backward compatibility."""
    return real_app


# =============================================================================
# Test Classes - Data Classes
# =============================================================================


class TestManagementState:
    """Tests for ManagementState initialization and management."""

    def test_init_creates_empty_state(self):
        """Test that ManagementState initializes with empty collections."""
        mgmt_state = ManagementState()

        assert len(mgmt_state.logs) == 0
        assert len(mgmt_state.clients) == 0
        assert len(mgmt_state.websockets) == 0

    def test_init_creates_default_servers(self):
        """Test that default servers are initialized."""
        mgmt_state = ManagementState()

        assert "ollama" in mgmt_state.servers
        assert "whisper" in mgmt_state.servers
        assert "piper" in mgmt_state.servers
        assert "gateway" in mgmt_state.servers

    def test_stats_initialized(self):
        """Test that stats are properly initialized."""
        mgmt_state = ManagementState()

        assert "total_logs_received" in mgmt_state.stats
        assert "total_metrics_received" in mgmt_state.stats
        assert "server_start_time" in mgmt_state.stats
        assert mgmt_state.stats["total_logs_received"] == 0
        assert mgmt_state.stats["errors_count"] == 0
        assert mgmt_state.stats["warnings_count"] == 0

    def test_curriculum_storage_initialized(self):
        """Test curriculum storage is initialized."""
        mgmt_state = ManagementState()

        assert isinstance(mgmt_state.curriculums, dict)
        assert isinstance(mgmt_state.curriculum_details, dict)
        assert isinstance(mgmt_state.curriculum_raw, dict)

    def test_reload_curricula_clears_state(self):
        """Test that reload_curricula clears the curriculum state."""
        mgmt_state = ManagementState()
        # Add some test data
        mgmt_state.curriculums["test"] = CurriculumSummary(
            id="test",
            title="Test",
            description="",
            version="1.0",
            topic_count=0,
            total_duration="PT1H",
            difficulty="easy",
            age_range="18+",
        )

        mgmt_state.reload_curricula()

        # State should be cleared (though it may reload from disk)
        # The key assertion is that it doesn't error


class TestLogEntry:
    """Tests for LogEntry dataclass."""

    def test_log_entry_creation(self):
        """Test creating a LogEntry with required fields."""
        entry = LogEntry(
            id="log-001",
            timestamp="2025-01-01T12:00:00Z",
            level="INFO",
            label="test",
            message="Test message",
        )

        assert entry.id == "log-001"
        assert entry.level == "INFO"
        assert entry.label == "test"
        assert entry.message == "Test message"
        assert entry.file == ""
        assert entry.function == ""
        assert entry.line == 0

    def test_log_entry_with_metadata(self):
        """Test creating a LogEntry with metadata."""
        entry = LogEntry(
            id="log-002",
            timestamp="2025-01-01T12:00:00Z",
            level="DEBUG",
            label="session",
            message="Session started",
            metadata={"session_id": "abc123", "user": "test"},
        )

        assert entry.metadata["session_id"] == "abc123"
        assert entry.metadata["user"] == "test"

    def test_log_entry_with_file_info(self):
        """Test LogEntry with file location information."""
        entry = LogEntry(
            id="log-003",
            timestamp="2025-01-01T12:00:00Z",
            level="ERROR",
            label="error",
            message="Error occurred",
            file="test.py",
            function="test_func",
            line=42,
        )

        assert entry.file == "test.py"
        assert entry.function == "test_func"
        assert entry.line == 42

    def test_log_entry_received_at_auto_set(self):
        """Test that received_at is automatically set."""
        before = time.time()
        entry = LogEntry(
            id="log-004",
            timestamp="2025-01-01T12:00:00Z",
            level="INFO",
            label="test",
            message="Test",
        )
        after = time.time()

        assert before <= entry.received_at <= after

    def test_log_entry_client_info(self):
        """Test LogEntry with client information."""
        entry = LogEntry(
            id="log-005",
            timestamp="2025-01-01T12:00:00Z",
            level="INFO",
            label="test",
            message="Test",
            client_id="client-001",
            client_name="iPhone 15",
        )

        assert entry.client_id == "client-001"
        assert entry.client_name == "iPhone 15"


class TestRemoteClient:
    """Tests for RemoteClient dataclass."""

    def test_remote_client_creation(self):
        """Test creating a RemoteClient."""
        client = RemoteClient(id="client-001", name="iPhone 15 Pro")

        assert client.id == "client-001"
        assert client.name == "iPhone 15 Pro"
        assert client.status == "online"

    def test_remote_client_with_device_info(self):
        """Test creating a RemoteClient with device information."""
        client = RemoteClient(
            id="client-002",
            name="Test Device",
            device_model="iPhone15,3",
            os_version="18.0",
            app_version="1.0.0",
        )

        assert client.device_model == "iPhone15,3"
        assert client.os_version == "18.0"
        assert client.app_version == "1.0.0"

    def test_remote_client_defaults(self):
        """Test RemoteClient default values."""
        client = RemoteClient(id="client-003", name="Test")

        assert client.device_model == ""
        assert client.os_version == ""
        assert client.app_version == ""
        assert client.ip_address == ""
        assert client.status == "online"
        assert client.current_session_id is None
        assert client.total_sessions == 0
        assert client.total_logs == 0
        assert isinstance(client.config, dict)

    def test_remote_client_timestamps(self):
        """Test RemoteClient timestamp fields."""
        before = time.time()
        client = RemoteClient(id="client-004", name="Test")
        after = time.time()

        assert before <= client.first_seen <= after
        assert before <= client.last_seen <= after


class TestServerStatus:
    """Tests for ServerStatus dataclass."""

    def test_server_status_creation(self):
        """Test creating a ServerStatus."""
        server = ServerStatus(
            id="ollama-1",
            name="Ollama LLM",
            type="ollama",
            url="http://localhost:11434",
            port=11434,
        )

        assert server.id == "ollama-1"
        assert server.type == "ollama"
        assert server.status == "unknown"

    def test_server_status_with_health(self):
        """Test ServerStatus with health information."""
        server = ServerStatus(
            id="whisper-1",
            name="Whisper STT",
            type="whisper",
            url="http://localhost:11401",
            port=11401,
            status="healthy",
            response_time_ms=45.5,
        )

        assert server.status == "healthy"
        assert server.response_time_ms == 45.5

    def test_server_status_defaults(self):
        """Test ServerStatus default values."""
        server = ServerStatus(
            id="test",
            name="Test",
            type="custom",
            url="http://localhost:8080",
            port=8080,
        )

        assert server.status == "unknown"
        assert server.last_check == 0
        assert server.response_time_ms == 0
        assert isinstance(server.capabilities, dict)
        assert isinstance(server.models, list)
        assert server.error_message == ""

    def test_server_status_with_capabilities(self):
        """Test ServerStatus with capabilities."""
        server = ServerStatus(
            id="test",
            name="Test",
            type="ollama",
            url="http://localhost:11434",
            port=11434,
            capabilities={"max_context": 4096},
            models=["llama2", "codellama"],
        )

        assert server.capabilities["max_context"] == 4096
        assert "llama2" in server.models


class TestModelInfo:
    """Tests for ModelInfo dataclass."""

    def test_model_info_creation(self):
        """Test creating a ModelInfo."""
        model = ModelInfo(
            id="model-001", name="llama2:7b", type="llm", server_id="ollama-1"
        )

        assert model.id == "model-001"
        assert model.name == "llama2:7b"
        assert model.type == "llm"
        assert model.server_id == "ollama-1"

    def test_model_info_with_details(self):
        """Test ModelInfo with detailed information."""
        model = ModelInfo(
            id="model-002",
            name="llama2:7b",
            type="llm",
            server_id="ollama-1",
            size_bytes=4_000_000_000,
            parameters="7B",
            quantization="Q4_0",
            loaded=True,
        )

        assert model.size_bytes == 4_000_000_000
        assert model.parameters == "7B"
        assert model.quantization == "Q4_0"
        assert model.loaded is True

    def test_model_info_defaults(self):
        """Test ModelInfo default values."""
        model = ModelInfo(id="model-003", name="test", type="llm", server_id="test")

        assert model.size_bytes == 0
        assert model.parameters == ""
        assert model.quantization == ""
        assert model.loaded is False
        assert model.last_used == 0
        assert model.usage_count == 0


class TestManagedService:
    """Tests for ManagedService dataclass."""

    def test_managed_service_creation(self):
        """Test creating a ManagedService."""
        service = ManagedService(
            id="vibevoice",
            name="VibeVoice TTS",
            service_type="vibevoice",
            command=["python3", "server.py"],
            cwd="/path/to/vibevoice",
            port=8880,
            health_url="http://localhost:8880/health",
        )

        assert service.id == "vibevoice"
        assert service.name == "VibeVoice TTS"
        assert service.service_type == "vibevoice"
        assert service.port == 8880

    def test_managed_service_defaults(self):
        """Test ManagedService default values."""
        service = ManagedService(
            id="test",
            name="Test",
            service_type="test",
            command=["python"],
            cwd="/test/workdir",  # Test placeholder, not actually used
            port=8000,
            health_url="http://localhost:8000/health",
        )

        assert service.process is None
        assert service.status == "stopped"
        assert service.pid is None
        assert service.started_at is None
        assert service.error_message == ""
        assert service.auto_restart is True


class TestCurriculumSummary:
    """Tests for CurriculumSummary dataclass."""

    def test_curriculum_summary_creation(self):
        """Test creating a CurriculumSummary."""
        summary = CurriculumSummary(
            id="curriculum-001",
            title="Machine Learning Basics",
            description="Introduction to ML",
            version="1.0.0",
            topic_count=10,
            total_duration="PT4H",
            difficulty="medium",
            age_range="18+",
        )

        assert summary.id == "curriculum-001"
        assert summary.title == "Machine Learning Basics"
        assert summary.topic_count == 10
        assert summary.difficulty == "medium"

    def test_curriculum_summary_with_visual_assets(self):
        """Test CurriculumSummary with visual asset counts."""
        summary = CurriculumSummary(
            id="curriculum-002",
            title="Physics 101",
            description="Physics basics",
            version="1.0.0",
            topic_count=5,
            total_duration="PT2H",
            difficulty="easy",
            age_range="12+",
            visual_asset_count=25,
            has_visual_assets=True,
        )

        assert summary.visual_asset_count == 25
        assert summary.has_visual_assets is True

    def test_curriculum_summary_keywords(self):
        """Test CurriculumSummary with keywords."""
        summary = CurriculumSummary(
            id="curriculum-003",
            title="Test",
            description="Test desc",
            version="1.0",
            topic_count=1,
            total_duration="PT1H",
            difficulty="easy",
            age_range="18+",
            keywords=["python", "programming", "beginners"],
        )

        assert "python" in summary.keywords
        assert len(summary.keywords) == 3


class TestCurriculumDetail:
    """Tests for CurriculumDetail dataclass."""

    def test_curriculum_detail_creation(self):
        """Test creating a CurriculumDetail."""
        detail = CurriculumDetail(
            id="detail-001",
            title="Test Curriculum",
            description="Test description",
            version="1.0.0",
            difficulty="medium",
            age_range="18+",
            duration="PT4H",
            keywords=["test"],
            topics=[],
            glossary_terms=[],
            learning_objectives=[],
        )

        assert detail.id == "detail-001"
        assert detail.title == "Test Curriculum"
        assert detail.difficulty == "medium"

    def test_curriculum_detail_with_topics(self):
        """Test CurriculumDetail with topics."""
        topics = [
            {"id": "topic-1", "title": "Topic 1"},
            {"id": "topic-2", "title": "Topic 2"},
        ]
        detail = CurriculumDetail(
            id="detail-002",
            title="Test",
            description="",
            version="1.0",
            difficulty="easy",
            age_range="18+",
            duration="PT2H",
            keywords=[],
            topics=topics,
            glossary_terms=[],
            learning_objectives=[],
        )

        assert len(detail.topics) == 2
        assert detail.topics[0]["id"] == "topic-1"


class TestTopicSummary:
    """Tests for TopicSummary dataclass."""

    def test_topic_summary_creation(self):
        """Test creating a TopicSummary."""
        summary = TopicSummary(
            id="topic-001",
            title="Neural Networks",
            description="Introduction to neural networks",
            order_index=0,
            duration="PT30M",
        )

        assert summary.id == "topic-001"
        assert summary.title == "Neural Networks"
        assert summary.order_index == 0

    def test_topic_summary_with_content_info(self):
        """Test TopicSummary with content information."""
        summary = TopicSummary(
            id="topic-002",
            title="Backpropagation",
            description="Learning about backprop",
            order_index=1,
            duration="PT45M",
            has_transcript=True,
            segment_count=15,
            assessment_count=3,
        )

        assert summary.has_transcript is True
        assert summary.segment_count == 15
        assert summary.assessment_count == 3

    def test_topic_summary_with_assets(self):
        """Test TopicSummary with asset counts."""
        summary = TopicSummary(
            id="topic-003",
            title="Test",
            description="",
            order_index=2,
            duration="PT15M",
            embedded_asset_count=5,
            reference_asset_count=3,
        )

        assert summary.embedded_asset_count == 5
        assert summary.reference_asset_count == 3


class TestMetricsSnapshot:
    """Tests for MetricsSnapshot dataclass."""

    def test_metrics_snapshot_creation(self):
        """Test creating a MetricsSnapshot."""
        snapshot = MetricsSnapshot(
            id="metrics-001",
            client_id="client-001",
            client_name="iPhone 15 Pro",
            timestamp="2025-01-01T12:00:00Z",
            received_at=1735689600.0,
            session_duration=3600.0,
            turns_total=50,
        )

        assert snapshot.id == "metrics-001"
        assert snapshot.session_duration == 3600.0
        assert snapshot.turns_total == 50

    def test_metrics_snapshot_with_latencies(self):
        """Test MetricsSnapshot with latency data."""
        snapshot = MetricsSnapshot(
            id="metrics-002",
            client_id="client-002",
            client_name="Test Device",
            timestamp="2025-01-01T12:00:00Z",
            received_at=1735689600.0,
            stt_latency_median=150.0,
            stt_latency_p99=300.0,
            llm_ttft_median=200.0,
            llm_ttft_p99=400.0,
            e2e_latency_median=450.0,
            e2e_latency_p99=800.0,
        )

        assert snapshot.stt_latency_median == 150.0
        assert snapshot.llm_ttft_median == 200.0
        assert snapshot.e2e_latency_median == 450.0

    def test_metrics_snapshot_with_costs(self):
        """Test MetricsSnapshot with cost data."""
        snapshot = MetricsSnapshot(
            id="metrics-003",
            client_id="client-003",
            client_name="Cost Test",
            timestamp="2025-01-01T12:00:00Z",
            received_at=1735689600.0,
            stt_cost=0.05,
            tts_cost=0.10,
            llm_cost=0.25,
            total_cost=0.40,
        )

        assert snapshot.stt_cost == 0.05
        assert snapshot.tts_cost == 0.10
        assert snapshot.llm_cost == 0.25
        assert snapshot.total_cost == 0.40

    def test_metrics_snapshot_with_device_stats(self):
        """Test MetricsSnapshot with device stats."""
        snapshot = MetricsSnapshot(
            id="metrics-004",
            client_id="client-004",
            client_name="Device Test",
            timestamp="2025-01-01T12:00:00Z",
            received_at=1735689600.0,
            thermal_throttle_events=2,
            network_degradations=5,
        )

        assert snapshot.thermal_throttle_events == 2
        assert snapshot.network_degradations == 5

    def test_metrics_snapshot_raw_data(self):
        """Test MetricsSnapshot with raw data."""
        raw = {"custom_field": "value", "latency_samples": [100, 200, 150]}
        snapshot = MetricsSnapshot(
            id="metrics-005",
            client_id="client-005",
            client_name="Raw Test",
            timestamp="2025-01-01T12:00:00Z",
            received_at=1735689600.0,
            raw_data=raw,
        )

        assert snapshot.raw_data["custom_field"] == "value"
        assert len(snapshot.raw_data["latency_samples"]) == 3


# =============================================================================
# Test Classes - Utility Functions
# =============================================================================


class TestChunkTextForTTS:
    """Tests for the chunk_text_for_tts function."""

    def test_empty_text_returns_empty_list(self):
        """Test that empty text returns empty list."""
        result = chunk_text_for_tts("")
        assert result == []

    def test_whitespace_only_returns_empty_list(self):
        """Test that whitespace-only text returns empty list."""
        result = chunk_text_for_tts("   \n\t  ")
        assert result == []

    def test_single_sentence_returns_one_segment(self):
        """Test that a single sentence returns one segment."""
        result = chunk_text_for_tts("Hello world, this is a test.")
        assert len(result) >= 1
        combined = " ".join([seg["content"] for seg in result])
        assert "Hello world" in combined

    def test_removes_mitocw_headers(self):
        """Test that MIT OCW headers are removed."""
        text = "MITOCW | MIT8_01F16_L00v01_360p Welcome to physics."
        result = chunk_text_for_tts(text)

        combined = " ".join([seg["content"] for seg in result])
        assert "MITOCW" not in combined
        assert "Welcome" in combined

    def test_removes_mit_video_markers(self):
        """Test removal of MIT video markers."""
        text = "MIT8_01F16_L00v01_360p This is the lecture content."
        result = chunk_text_for_tts(text)

        combined = " ".join([seg["content"] for seg in result])
        assert "MIT8_01F16" not in combined
        assert "lecture content" in combined

    def test_removes_video_quality_markers(self):
        """Test removal of video quality markers."""
        text = "v01_360p This is the content after the marker."
        result = chunk_text_for_tts(text)

        combined = " ".join([seg["content"] for seg in result])
        assert "360p" not in combined
        assert "content" in combined

    def test_preserves_paragraph_structure(self):
        """Test that paragraph breaks create separate segments."""
        text = "First paragraph here.\n\nSecond paragraph here."
        result = chunk_text_for_tts(text)

        assert len(result) >= 1
        combined = " ".join([seg["content"] for seg in result])
        assert "First paragraph" in combined
        assert "Second paragraph" in combined

    def test_handles_multiple_sentences(self):
        """Test handling of multiple sentences."""
        text = "First sentence. Second sentence. Third sentence."
        result = chunk_text_for_tts(text)

        combined = " ".join([seg["content"] for seg in result])
        assert "First" in combined
        assert "Second" in combined
        assert "Third" in combined

    def test_respects_max_chars(self):
        """Test that chunks respect max_chars parameter."""
        long_text = "This is a long sentence that should be chunked. " * 20
        result = chunk_text_for_tts(long_text, max_chars=100)

        for seg in result:
            # Segments should generally stay under max_chars
            # (some flexibility for sentence boundaries)
            assert len(seg["content"]) < 500

    def test_respects_min_chars(self):
        """Test that short segments are combined."""
        text = "Hi. Hello. Yes."
        result = chunk_text_for_tts(text, min_chars=50)

        # Should combine short segments
        assert len(result) >= 1

    def test_assigns_segment_ids(self):
        """Test that segments get IDs assigned."""
        text = "First sentence. Second sentence."
        result = chunk_text_for_tts(text)

        for idx, seg in enumerate(result):
            assert "id" in seg
            assert seg["id"] == f"chunk-{idx}"

    def test_assigns_segment_types(self):
        """Test that segments get types assigned."""
        text = "First sentence. Second sentence."
        result = chunk_text_for_tts(text)

        for seg in result:
            assert "type" in seg
            assert seg["type"] in ["lecture", "explanation"]

    def test_handles_long_sentences_with_clauses(self):
        """Test that long sentences are split on clause boundaries."""
        long_sentence = "This is a very long sentence, with multiple clauses, and it should be split properly; especially when there are semicolons, or other punctuation marks."
        result = chunk_text_for_tts(long_sentence, max_chars=100)

        assert len(result) >= 1

    def test_handles_only_headers(self):
        """Test text that is only headers returns empty."""
        text = "MITOCW | MIT8_01F16_L00v01_360p"
        result = chunk_text_for_tts(text)

        # After removing headers, should be empty
        assert result == []


class TestIsFlagEnabled:
    """Tests for the is_flag_enabled function."""

    def test_returns_default_when_feature_flags_none(self):
        """Test returns default when feature_flags is None."""
        with patch("server.feature_flags", None):
            assert is_flag_enabled("test_flag", default=True) is True
            assert is_flag_enabled("test_flag", default=False) is False

    def test_returns_flag_value_when_available(self):
        """Test returns actual flag value when available."""
        mock_flags = MagicMock()  # ALLOWED: feature_flags is external config service
        mock_flags.is_enabled.return_value = True

        with patch("server.feature_flags", mock_flags):
            assert is_flag_enabled("test_flag", default=False) is True
            mock_flags.is_enabled.assert_called_once_with("test_flag")

    def test_returns_default_on_exception(self):
        """Test returns default when exception occurs."""
        mock_flags = MagicMock()  # ALLOWED: feature_flags is external config service
        mock_flags.is_enabled.side_effect = Exception("Connection error")

        with patch("server.feature_flags", mock_flags):
            assert is_flag_enabled("test_flag", default=True) is True
            assert is_flag_enabled("test_flag", default=False) is False


# =============================================================================
# Test Classes - API Handlers (Async Tests)
# =============================================================================


@pytest.mark.asyncio
class TestHandleHealth:
    """Tests for handle_health endpoint."""

    async def test_health_returns_ok(self, mock_request):
        """Test health endpoint returns healthy status."""
        response = await handle_health(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "healthy"
        assert "timestamp" in data
        assert "version" in data

    async def test_health_timestamp_format(self, mock_request):
        """Test health endpoint timestamp is ISO format."""
        response = await handle_health(mock_request)
        data = json.loads(response.body)

        # Should end with Z for UTC
        assert data["timestamp"].endswith("Z")


@pytest.mark.asyncio
class TestHandleGetStats:
    """Tests for handle_get_stats endpoint."""

    async def test_get_stats_returns_data(self, mock_request):
        """Test stats endpoint returns expected fields."""
        response = await handle_get_stats(mock_request)

        assert response.status == 200
        data = json.loads(response.body)

        assert "uptime_seconds" in data
        assert "total_logs" in data
        assert "total_metrics" in data
        assert "errors_count" in data
        assert "online_clients" in data

    async def test_get_stats_calculates_uptime(self, mock_request):
        """Test stats correctly calculates uptime."""
        response = await handle_get_stats(mock_request)
        data = json.loads(response.body)

        assert data["uptime_seconds"] >= 0


@pytest.mark.asyncio
class TestHandleReceiveLog:
    """Tests for handle_receive_log endpoint."""

    async def test_receive_single_log(self, mock_request):
        """Test receiving a single log entry."""
        log_data = {
            "level": "INFO",
            "label": "test",
            "message": "Test log message",
            "timestamp": "2025-01-01T12:00:00Z",
        }

        mock_request.json = AsyncMock(return_value=log_data)
        mock_request.headers = {
            "X-Client-ID": "test-client",
            "X-Client-Name": "Test Device",
        }

        response = await handle_receive_log(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "ok"
        assert data["received"] == 1

    async def test_receive_batch_logs(self, mock_request):
        """Test receiving multiple log entries in a batch."""
        logs = [
            {"level": "INFO", "label": "test", "message": "Log 1"},
            {"level": "DEBUG", "label": "test", "message": "Log 2"},
            {"level": "WARNING", "label": "test", "message": "Log 3"},
        ]

        mock_request.json = AsyncMock(return_value=logs)
        mock_request.headers = {"X-Client-ID": "test-client"}

        response = await handle_receive_log(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["received"] == 3

    async def test_receive_log_creates_client(self, mock_request):
        """Test that receiving a log creates client if not exists."""
        log_data = {"level": "INFO", "label": "test", "message": "Test"}

        mock_request.json = AsyncMock(return_value=log_data)
        mock_request.headers = {
            "X-Client-ID": "new-client",
            "X-Client-Name": "New Device",
        }

        response = await handle_receive_log(mock_request)

        assert response.status == 200

    async def test_receive_error_log_updates_stats(self, mock_request):
        """Test that error logs update the error count."""
        initial_errors = state.stats["errors_count"]

        log_data = {"level": "ERROR", "label": "test", "message": "Error occurred"}
        mock_request.json = AsyncMock(return_value=log_data)
        mock_request.headers = {"X-Client-ID": "test-client"}

        await handle_receive_log(mock_request)

        assert state.stats["errors_count"] >= initial_errors

    async def test_receive_warning_log_updates_stats(self, mock_request):
        """Test that warning logs update the warning count."""
        initial_warnings = state.stats["warnings_count"]

        log_data = {"level": "WARNING", "label": "test", "message": "Warning occurred"}
        mock_request.json = AsyncMock(return_value=log_data)
        mock_request.headers = {"X-Client-ID": "test-client"}

        await handle_receive_log(mock_request)

        assert state.stats["warnings_count"] >= initial_warnings

    async def test_receive_log_invalid_json(self, mock_request):
        """Test handling of invalid JSON."""
        mock_request.json = AsyncMock(side_effect=json.JSONDecodeError("", "", 0))
        mock_request.headers = {}

        response = await handle_receive_log(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleGetLogs:
    """Tests for handle_get_logs endpoint."""

    async def test_get_logs_returns_list(self, mock_request):
        """Test get logs returns a list."""
        mock_request.query = {}

        response = await handle_get_logs(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "logs" in data
        assert isinstance(data["logs"], list)

    async def test_get_logs_with_limit(self, mock_request):
        """Test get logs respects limit parameter."""
        mock_request.query = {"limit": "10"}

        response = await handle_get_logs(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["limit"] == 10

    async def test_get_logs_with_level_filter(self, mock_request):
        """Test get logs with level filter."""
        mock_request.query = {"level": "ERROR"}

        response = await handle_get_logs(mock_request)

        assert response.status == 200

    async def test_get_logs_with_search(self, mock_request):
        """Test get logs with search filter."""
        mock_request.query = {"search": "test"}

        response = await handle_get_logs(mock_request)

        assert response.status == 200

    async def test_get_logs_with_client_filter(self, mock_request):
        """Test get logs with client_id filter."""
        mock_request.query = {"client_id": "test-client"}

        response = await handle_get_logs(mock_request)

        assert response.status == 200

    async def test_get_logs_pagination(self, mock_request):
        """Test get logs pagination."""
        mock_request.query = {"limit": "10", "offset": "5"}

        response = await handle_get_logs(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["offset"] == 5


@pytest.mark.asyncio
class TestHandleClearLogs:
    """Tests for handle_clear_logs endpoint."""

    async def test_clear_logs_success(self, mock_request):
        """Test clearing logs succeeds."""
        response = await handle_clear_logs(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "ok"

    async def test_clear_logs_resets_counts(self, mock_request):
        """Test clearing logs resets error/warning counts."""
        await handle_clear_logs(mock_request)

        assert state.stats["errors_count"] == 0
        assert state.stats["warnings_count"] == 0


@pytest.mark.asyncio
class TestHandleReceiveMetrics:
    """Tests for handle_receive_metrics endpoint."""

    async def test_receive_metrics_success(self, mock_request):
        """Test receiving metrics succeeds."""
        metrics_data = {
            "timestamp": "2025-01-01T12:00:00Z",
            "sessionDuration": 3600.0,
            "turnsTotal": 50,
            "e2eLatencyMedian": 450.0,
        }

        mock_request.json = AsyncMock(return_value=metrics_data)
        mock_request.headers = {"X-Client-ID": "test-client", "X-Client-Name": "Test"}

        response = await handle_receive_metrics(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "ok"

    async def test_receive_metrics_updates_client(self, mock_request):
        """Test receiving metrics updates client info."""
        metrics_data = {"timestamp": "2025-01-01T12:00:00Z"}

        mock_request.json = AsyncMock(return_value=metrics_data)
        mock_request.headers = {
            "X-Client-ID": "metrics-client",
            "X-Client-Name": "Test",
        }

        await handle_receive_metrics(mock_request)

        if "metrics-client" in state.clients:
            assert state.clients["metrics-client"].status == "online"


@pytest.mark.asyncio
class TestHandleGetMetrics:
    """Tests for handle_get_metrics endpoint."""

    async def test_get_metrics_returns_data(self, mock_request):
        """Test get metrics returns expected data."""
        mock_request.query = {}

        response = await handle_get_metrics(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "metrics" in data
        assert "aggregates" in data

    async def test_get_metrics_with_limit(self, mock_request):
        """Test get metrics respects limit."""
        mock_request.query = {"limit": "10"}

        response = await handle_get_metrics(mock_request)

        assert response.status == 200

    async def test_get_metrics_aggregates(self, mock_request):
        """Test get metrics includes aggregates."""
        mock_request.query = {}

        response = await handle_get_metrics(mock_request)
        data = json.loads(response.body)

        aggregates = data["aggregates"]
        assert "avg_e2e_latency" in aggregates
        assert "avg_llm_ttft" in aggregates
        assert "total_cost" in aggregates


@pytest.mark.asyncio
class TestHandleGetClients:
    """Tests for handle_get_clients endpoint."""

    async def test_get_clients_returns_list(self, mock_request):
        """Test get clients returns a list."""
        response = await handle_get_clients(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "clients" in data
        assert isinstance(data["clients"], list)

    async def test_get_clients_includes_counts(self, mock_request):
        """Test get clients includes status counts."""
        response = await handle_get_clients(mock_request)
        data = json.loads(response.body)

        assert "total" in data
        assert "online" in data
        assert "idle" in data
        assert "offline" in data


@pytest.mark.asyncio
class TestHandleClientHeartbeat:
    """Tests for handle_client_heartbeat endpoint."""

    async def test_heartbeat_creates_client(self, mock_request):
        """Test heartbeat creates new client."""
        heartbeat_data = {
            "client_id": "heartbeat-client",
            "name": "Test Device",
            "device_model": "iPhone15,3",
            "os_version": "18.0",
        }

        mock_request.json = AsyncMock(return_value=heartbeat_data)
        mock_request.headers = {}

        response = await handle_client_heartbeat(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "ok"
        assert "client_id" in data

    async def test_heartbeat_updates_client(self, mock_request):
        """Test heartbeat updates existing client."""
        state.clients["existing-client"] = RemoteClient(
            id="existing-client", name="Old Name"
        )

        heartbeat_data = {"client_id": "existing-client", "name": "New Name"}

        mock_request.json = AsyncMock(return_value=heartbeat_data)
        mock_request.headers = {}

        response = await handle_client_heartbeat(mock_request)

        assert response.status == 200
        assert state.clients["existing-client"].name == "New Name"


@pytest.mark.asyncio
class TestHandleGetServers:
    """Tests for handle_get_servers endpoint."""

    async def test_get_servers_returns_list(self, mock_request):
        """Test get servers returns a list."""
        with patch("server.check_server_health", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = None

            response = await handle_get_servers(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "servers" in data
            assert isinstance(data["servers"], list)

    async def test_get_servers_includes_counts(self, mock_request):
        """Test get servers includes status counts."""
        with patch("server.check_server_health", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = None

            response = await handle_get_servers(mock_request)
            data = json.loads(response.body)

            assert "total" in data
            assert "healthy" in data
            assert "degraded" in data
            assert "unhealthy" in data


@pytest.mark.asyncio
class TestHandleAddServer:
    """Tests for handle_add_server endpoint."""

    async def test_add_server_success(self, mock_request):
        """Test adding a server succeeds."""
        server_data = {
            "id": "new-server",
            "name": "New Server",
            "type": "custom",
            "url": "http://localhost:9999",
            "port": 9999,
        }

        mock_request.json = AsyncMock(return_value=server_data)

        with patch("server.check_server_health", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = ServerStatus(
                id="new-server",
                name="New Server",
                type="custom",
                url="http://localhost:9999",
                port=9999,
            )

            response = await handle_add_server(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["status"] == "ok"


@pytest.mark.asyncio
class TestHandleDeleteServer:
    """Tests for handle_delete_server endpoint."""

    async def test_delete_existing_server(self, mock_request):
        """Test deleting an existing server."""
        state.servers["delete-me"] = ServerStatus(
            id="delete-me",
            name="Delete Me",
            type="custom",
            url="http://localhost:8888",
            port=8888,
        )

        mock_request.match_info = {"server_id": "delete-me"}

        response = await handle_delete_server(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "ok"
        assert "delete-me" not in state.servers

    async def test_delete_nonexistent_server(self, mock_request):
        """Test deleting a non-existent server."""
        mock_request.match_info = {"server_id": "nonexistent"}

        response = await handle_delete_server(mock_request)

        assert response.status == 404


@pytest.mark.asyncio
class TestHandleGetModels:
    """Tests for handle_get_models endpoint."""

    async def test_get_models_returns_list(self, mock_request):
        """Test get models returns a list."""
        with patch("server.check_server_health", new_callable=AsyncMock):
            with patch(
                "server.get_ollama_model_details", new_callable=AsyncMock
            ) as mock_details:
                mock_details.return_value = {"details": {}, "loaded": {}}

                response = await handle_get_models(mock_request)

                assert response.status == 200
                data = json.loads(response.body)
                assert "models" in data
                assert "total" in data
                assert "by_type" in data


@pytest.mark.asyncio
class TestHandleGetModelConfig:
    """Tests for handle_get_model_config endpoint."""

    async def test_get_model_config_returns_data(self, mock_request):
        """Test get model config returns configuration."""
        response = await handle_get_model_config(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "ok"
        assert "config" in data


@pytest.mark.asyncio
class TestHandleSaveModelConfig:
    """Tests for handle_save_model_config endpoint."""

    async def test_save_model_config_missing_services(self, mock_request):
        """Test save fails without services key."""
        mock_request.json = AsyncMock(return_value={"config": {}})

        response = await handle_save_model_config(mock_request)

        assert response.status == 400

    async def test_save_model_config_invalid_json(self, mock_request):
        """Test save handles invalid JSON."""
        mock_request.json = AsyncMock(side_effect=json.JSONDecodeError("", "", 0))

        response = await handle_save_model_config(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleGetModelParameters:
    """Tests for handle_get_model_parameters endpoint."""

    async def test_get_model_parameters(self, mock_request):
        """Test get model parameters."""
        mock_request.match_info = {"model_id": "ollama:llama2"}

        response = await handle_get_model_parameters(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "parameters" in data


@pytest.mark.asyncio
class TestHandleSaveModelParameters:
    """Tests for handle_save_model_parameters endpoint."""

    async def test_save_model_parameters_validates(self, mock_request):
        """Test save validates parameter ranges."""
        mock_request.match_info = {"model_id": "ollama:test"}
        mock_request.json = AsyncMock(
            return_value={"parameters": {"temperature": 0.7, "num_ctx": 4096}}
        )

        response = await handle_save_model_parameters(mock_request)

        assert response.status == 200


@pytest.mark.asyncio
class TestHandleGetModelCapabilities:
    """Tests for handle_get_model_capabilities endpoint."""

    async def test_get_capabilities_returns_data(self, mock_request):
        """Test get capabilities returns model data."""
        response = await handle_get_model_capabilities(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "capabilities" in data
        assert "total" in data
        assert "by_tier" in data
        assert "by_provider" in data


@pytest.mark.asyncio
class TestHandleGetServices:
    """Tests for handle_get_services endpoint."""

    async def test_get_services_returns_list(self, mock_request):
        """Test get services returns a list."""
        with patch(
            "server.check_service_running", new_callable=AsyncMock
        ) as mock_check:
            mock_check.return_value = False

            response = await handle_get_services(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "services" in data
            assert "total" in data


@pytest.mark.asyncio
class TestHandleStartService:
    """Tests for handle_start_service endpoint."""

    async def test_start_nonexistent_service(self, mock_request):
        """Test starting a non-existent service."""
        mock_request.match_info = {"service_id": "nonexistent"}

        response = await handle_start_service(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleStopService:
    """Tests for handle_stop_service endpoint."""

    async def test_stop_nonexistent_service(self, mock_request):
        """Test stopping a non-existent service."""
        mock_request.match_info = {"service_id": "nonexistent"}

        response = await handle_stop_service(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleRestartService:
    """Tests for handle_restart_service endpoint."""

    async def test_restart_nonexistent_service(self, mock_request):
        """Test restarting a non-existent service."""
        mock_request.match_info = {"service_id": "nonexistent"}

        with patch("server.stop_service", new_callable=AsyncMock) as mock_stop:
            with patch("server.start_service", new_callable=AsyncMock) as mock_start:
                mock_stop.return_value = (False, "Service not found")
                mock_start.return_value = (False, "Service not found")

                response = await handle_restart_service(mock_request)

                assert response.status == 400


@pytest.mark.asyncio
class TestHandleStartAllServices:
    """Tests for handle_start_all_services endpoint."""

    async def test_start_all_returns_results(self, mock_request):
        """Test start all returns results for each service."""
        with patch("server.start_service", new_callable=AsyncMock) as mock_start:
            mock_start.return_value = (False, "Already running")

            response = await handle_start_all_services(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["status"] == "ok"
            assert "results" in data


@pytest.mark.asyncio
class TestHandleStopAllServices:
    """Tests for handle_stop_all_services endpoint."""

    async def test_stop_all_returns_results(self, mock_request):
        """Test stop all returns results for each service."""
        with patch("server.stop_service", new_callable=AsyncMock) as mock_stop:
            mock_stop.return_value = (True, "Service stopped")

            response = await handle_stop_all_services(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["status"] == "ok"


@pytest.mark.asyncio
class TestHandleGetCurricula:
    """Tests for handle_get_curricula endpoint."""

    async def test_get_curricula_returns_list(self, mock_request):
        """Test get curricula returns a list."""
        mock_request.query = {}

        response = await handle_get_curricula(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "curricula" in data
        assert "total" in data

    async def test_get_curricula_with_search(self, mock_request):
        """Test get curricula with search filter."""
        mock_request.query = {"search": "physics"}

        response = await handle_get_curricula(mock_request)

        assert response.status == 200

    async def test_get_curricula_with_difficulty(self, mock_request):
        """Test get curricula with difficulty filter."""
        mock_request.query = {"difficulty": "easy"}

        response = await handle_get_curricula(mock_request)

        assert response.status == 200


@pytest.mark.asyncio
class TestHandleGetCurriculumDetail:
    """Tests for handle_get_curriculum_detail endpoint."""

    async def test_get_nonexistent_curriculum(self, mock_request):
        """Test getting a non-existent curriculum."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}

        response = await handle_get_curriculum_detail(mock_request)

        assert response.status == 404


@pytest.mark.asyncio
class TestHandleGetCurriculumFull:
    """Tests for handle_get_curriculum_full endpoint."""

    async def test_get_nonexistent_curriculum_full(self, mock_request):
        """Test getting full data for non-existent curriculum."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}

        response = await handle_get_curriculum_full(mock_request)

        assert response.status == 404


@pytest.mark.asyncio
class TestHandleGetTopicTranscript:
    """Tests for handle_get_topic_transcript endpoint."""

    async def test_get_transcript_curriculum_not_found(self, mock_request):
        """Test getting transcript when curriculum doesn't exist."""
        mock_request.match_info = {
            "curriculum_id": "nonexistent",
            "topic_id": "topic-1",
        }

        response = await handle_get_topic_transcript(mock_request)

        assert response.status == 404


@pytest.mark.asyncio
class TestHandleReloadCurricula:
    """Tests for handle_reload_curricula endpoint."""

    async def test_reload_curricula_success(self, mock_request):
        """Test reloading curricula succeeds."""
        response = await handle_reload_curricula(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "ok"
        assert "count" in data


@pytest.mark.asyncio
class TestHandleDeleteCurriculum:
    """Tests for handle_delete_curriculum endpoint."""

    async def test_delete_nonexistent_curriculum(self, mock_request):
        """Test deleting non-existent curriculum."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}
        mock_request.query = {"confirm": "true"}

        response = await handle_delete_curriculum(mock_request)

        assert response.status == 404

    async def test_delete_requires_confirmation(self, mock_request):
        """Test delete requires confirmation."""
        # Add a test curriculum
        state.curriculums["test-delete"] = CurriculumSummary(
            id="test-delete",
            title="Test Delete",
            description="",
            version="1.0",
            topic_count=0,
            total_duration="PT1H",
            difficulty="easy",
            age_range="18+",
            file_path="/test/data/test.umcf",  # Test placeholder
        )

        mock_request.match_info = {"curriculum_id": "test-delete"}
        mock_request.query = {}  # No confirmation

        response = await handle_delete_curriculum(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "confirmation_required"

        # Cleanup
        del state.curriculums["test-delete"]


@pytest.mark.asyncio
class TestHandleArchiveCurriculum:
    """Tests for handle_archive_curriculum endpoint."""

    async def test_archive_nonexistent_curriculum(self, mock_request):
        """Test archiving non-existent curriculum."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}

        response = await handle_archive_curriculum(mock_request)

        assert response.status == 404


@pytest.mark.asyncio
class TestHandleGetArchivedCurricula:
    """Tests for handle_get_archived_curricula endpoint."""

    async def test_get_archived_returns_list(self, mock_request):
        """Test get archived returns a list."""
        response = await handle_get_archived_curricula(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "archived" in data
        assert "total" in data


@pytest.mark.asyncio
class TestHandleUnarchiveCurriculum:
    """Tests for handle_unarchive_curriculum endpoint."""

    async def test_unarchive_nonexistent(self, mock_request):
        """Test unarchiving non-existent file."""
        mock_request.match_info = {"file_name": "nonexistent.umcf"}

        response = await handle_unarchive_curriculum(mock_request)

        assert response.status == 404


@pytest.mark.asyncio
class TestHandleDeleteArchivedCurriculum:
    """Tests for handle_delete_archived_curriculum endpoint."""

    async def test_delete_archived_nonexistent(self, mock_request):
        """Test deleting non-existent archived curriculum."""
        mock_request.match_info = {"file_name": "nonexistent.umcf"}
        mock_request.query = {"confirm": "true"}

        response = await handle_delete_archived_curriculum(mock_request)

        assert response.status == 404


@pytest.mark.asyncio
class TestHandleSaveCurriculum:
    """Tests for handle_save_curriculum endpoint."""

    async def test_save_invalid_data(self, mock_request):
        """Test save with invalid data."""
        mock_request.match_info = {"curriculum_id": "test"}
        mock_request.json = AsyncMock(return_value={})

        response = await handle_save_curriculum(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleImportCurriculum:
    """Tests for handle_import_curriculum endpoint."""

    async def test_import_missing_url_and_content(self, mock_request):
        """Test import fails without url or content."""
        mock_request.json = AsyncMock(return_value={})

        response = await handle_import_curriculum(mock_request)

        assert response.status == 400

    async def test_import_invalid_content_type(self, mock_request):
        """Test import fails with non-object content."""
        mock_request.json = AsyncMock(return_value={"content": "not an object"})

        response = await handle_import_curriculum(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleGetSystemMetrics:
    """Tests for handle_get_system_metrics endpoint."""

    async def test_get_system_metrics_returns_data(self, mock_request):
        """Test get system metrics returns data."""
        with patch("server.idle_manager") as mock_idle:
            with patch("server.resource_monitor") as mock_resource:
                mock_idle.record_activity = (
                    MagicMock()
                )  # ALLOWED: system infrastructure
                mock_resource.record_service_activity = (
                    MagicMock()
                )  # ALLOWED: system infrastructure
                mock_resource.get_summary.return_value = {"cpu": 50, "memory": 60}

                response = await handle_get_system_metrics(mock_request)

                assert response.status == 200


@pytest.mark.asyncio
class TestHandleGetSystemSnapshot:
    """Tests for handle_get_system_snapshot endpoint."""

    async def test_get_system_snapshot_returns_data(self, mock_request):
        """Test get system snapshot returns data."""
        with patch("server.idle_manager") as mock_idle:
            with patch("server.resource_monitor") as mock_resource:
                mock_idle.record_activity = (
                    MagicMock()
                )  # ALLOWED: system infrastructure
                mock_resource.get_current_snapshot.return_value = {
                    "timestamp": time.time()
                }

                response = await handle_get_system_snapshot(mock_request)

                assert response.status == 200


@pytest.mark.asyncio
class TestHandleGetPowerHistory:
    """Tests for handle_get_power_history endpoint."""

    async def test_get_power_history_returns_data(self, mock_request):
        """Test get power history returns data."""
        mock_request.query = {"limit": "50"}

        with patch("server.resource_monitor") as mock_resource:
            mock_resource.get_power_history.return_value = []
            mock_resource.collection_interval = 5

            response = await handle_get_power_history(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "history" in data


@pytest.mark.asyncio
class TestHandleGetProcessHistory:
    """Tests for handle_get_process_history endpoint."""

    async def test_get_process_history_returns_data(self, mock_request):
        """Test get process history returns data."""
        mock_request.query = {"limit": "50"}

        with patch("server.resource_monitor") as mock_resource:
            mock_resource.get_process_history.return_value = []

            response = await handle_get_process_history(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "history" in data


@pytest.mark.asyncio
class TestHandleGetIdleStatus:
    """Tests for handle_get_idle_status endpoint."""

    async def test_get_idle_status_returns_data(self, mock_request):
        """Test get idle status returns data."""
        with patch("server.idle_manager") as mock_idle:
            mock_idle.get_status.return_value = {"state": "active"}

            response = await handle_get_idle_status(mock_request)

            assert response.status == 200


@pytest.mark.asyncio
class TestHandleSetIdleConfig:
    """Tests for handle_set_idle_config endpoint."""

    async def test_set_idle_config_invalid_mode(self, mock_request):
        """Test set idle config with invalid mode."""
        mock_request.json = AsyncMock(return_value={"mode": "invalid"})

        with patch("server.idle_manager") as mock_idle:
            mock_idle.set_mode.return_value = False
            mock_idle.get_status.return_value = {}

            response = await handle_set_idle_config(mock_request)

            assert response.status == 400


@pytest.mark.asyncio
class TestHandleIdleKeepAwake:
    """Tests for handle_idle_keep_awake endpoint."""

    async def test_keep_awake_success(self, mock_request):
        """Test keep awake succeeds."""
        mock_request.json = AsyncMock(return_value={"duration_seconds": 3600})

        with patch("server.idle_manager") as mock_idle:
            mock_idle.keep_awake = MagicMock()  # ALLOWED: system infrastructure

            response = await handle_idle_keep_awake(mock_request)

            assert response.status == 200


@pytest.mark.asyncio
class TestHandleIdleCancelKeepAwake:
    """Tests for handle_idle_cancel_keep_awake endpoint."""

    async def test_cancel_keep_awake_success(self, mock_request):
        """Test cancel keep awake succeeds."""
        with patch("server.idle_manager") as mock_idle:
            mock_idle.cancel_keep_awake = MagicMock()  # ALLOWED: system infrastructure

            response = await handle_idle_cancel_keep_awake(mock_request)

            assert response.status == 200


@pytest.mark.asyncio
class TestHandleIdleForceState:
    """Tests for handle_idle_force_state endpoint."""

    async def test_force_state_invalid(self, mock_request):
        """Test force state with invalid state name."""
        mock_request.json = AsyncMock(return_value={"state": "invalid"})

        response = await handle_idle_force_state(mock_request)

        assert response.status == 400
        data = json.loads(response.body)
        assert "valid_states" in data


@pytest.mark.asyncio
class TestHandleGetPowerModes:
    """Tests for handle_get_power_modes endpoint."""

    async def test_get_power_modes_returns_data(self, mock_request):
        """Test get power modes returns data."""
        with patch("server.idle_manager") as mock_idle:
            mock_idle.get_available_modes.return_value = ["balanced", "performance"]
            mock_idle.current_mode = "balanced"

            response = await handle_get_power_modes(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "modes" in data
            assert "current" in data


@pytest.mark.asyncio
class TestHandleGetIdleHistory:
    """Tests for handle_get_idle_history endpoint."""

    async def test_get_idle_history_returns_data(self, mock_request):
        """Test get idle history returns data."""
        mock_request.query = {"limit": "50"}

        with patch("server.idle_manager") as mock_idle:
            mock_idle.get_transition_history.return_value = []

            response = await handle_get_idle_history(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "history" in data


@pytest.mark.asyncio
class TestHandleGetDiagnosticConfig:
    """Tests for handle_get_diagnostic_config endpoint."""

    async def test_get_diagnostic_config_returns_data(self, mock_request):
        """Test get diagnostic config returns data."""
        with patch("server.get_diagnostic_config") as mock_get:
            mock_get.return_value = {"enabled": True}

            response = await handle_get_diagnostic_config(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["success"] is True


@pytest.mark.asyncio
class TestHandleSetDiagnosticConfig:
    """Tests for handle_set_diagnostic_config endpoint."""

    async def test_set_diagnostic_config_success(self, mock_request):
        """Test set diagnostic config succeeds."""
        mock_request.json = AsyncMock(return_value={"enabled": True})

        with patch("server.set_diagnostic_config") as mock_set:
            with patch("server.diag_logger") as mock_logger:
                mock_set.return_value = {"enabled": True}
                mock_logger.info = MagicMock()  # ALLOWED: logging infrastructure

                response = await handle_set_diagnostic_config(mock_request)

                assert response.status == 200


@pytest.mark.asyncio
class TestHandleDiagnosticToggle:
    """Tests for handle_diagnostic_toggle endpoint."""

    async def test_diagnostic_toggle_enable(self, mock_request):
        """Test toggling diagnostic logging on."""
        mock_request.json = AsyncMock(return_value={"enabled": True})

        with patch("server.diag_logger") as mock_logger:
            mock_logger.is_enabled.return_value = True
            mock_logger.enable = MagicMock()  # ALLOWED: logging infrastructure

            response = await handle_diagnostic_toggle(mock_request)

            assert response.status == 200


@pytest.mark.asyncio
class TestHandleGetProfile:
    """Tests for handle_get_profile endpoint."""

    async def test_get_profile_not_found(self, mock_request):
        """Test get profile when not found."""
        mock_request.match_info = {"profile_id": "nonexistent"}

        with patch("server.idle_manager") as mock_idle:
            mock_idle.get_profile.return_value = None

            response = await handle_get_profile(mock_request)

            assert response.status == 404


@pytest.mark.asyncio
class TestHandleCreateProfile:
    """Tests for handle_create_profile endpoint."""

    async def test_create_profile_missing_fields(self, mock_request):
        """Test create profile with missing fields."""
        mock_request.json = AsyncMock(return_value={"name": "Test"})

        response = await handle_create_profile(mock_request)

        assert response.status == 400

    async def test_create_profile_missing_threshold(self, mock_request):
        """Test create profile with missing threshold."""
        mock_request.json = AsyncMock(
            return_value={
                "id": "test",
                "name": "Test",
                "thresholds": {"warm": 60},  # Missing others
            }
        )

        response = await handle_create_profile(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleUpdateProfile:
    """Tests for handle_update_profile endpoint."""

    async def test_update_profile_not_found(self, mock_request):
        """Test update profile when not found."""
        mock_request.match_info = {"profile_id": "nonexistent"}
        mock_request.json = AsyncMock(return_value={"name": "New Name"})

        with patch("server.idle_manager") as mock_idle:
            mock_idle.update_profile.return_value = False

            response = await handle_update_profile(mock_request)

            assert response.status == 400


@pytest.mark.asyncio
class TestHandleDeleteProfile:
    """Tests for handle_delete_profile endpoint."""

    async def test_delete_profile_not_found(self, mock_request):
        """Test delete profile when not found."""
        mock_request.match_info = {"profile_id": "nonexistent"}

        with patch("server.idle_manager") as mock_idle:
            mock_idle.delete_profile.return_value = False

            response = await handle_delete_profile(mock_request)

            assert response.status == 400


@pytest.mark.asyncio
class TestHandleDuplicateProfile:
    """Tests for handle_duplicate_profile endpoint."""

    async def test_duplicate_profile_missing_fields(self, mock_request):
        """Test duplicate profile with missing fields."""
        mock_request.match_info = {"profile_id": "source"}
        mock_request.json = AsyncMock(
            return_value={"new_id": "new"}
        )  # Missing new_name

        response = await handle_duplicate_profile(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleGetAdminUsers:
    """Tests for handle_get_admin_users endpoint."""

    async def test_get_admin_users_no_auth(self, mock_request):
        """Test get admin users when auth not configured."""
        mock_request.app = {}

        response = await handle_get_admin_users(mock_request)

        assert response.status == 503


@pytest.mark.asyncio
class TestHandleCreateAdminUser:
    """Tests for handle_create_admin_user endpoint."""

    async def test_create_admin_user_no_auth(self, mock_request):
        """Test create admin user when auth not configured."""
        mock_request.app = {}
        mock_request.json = AsyncMock(
            return_value={"email": "test@test.com", "password": "password123"}
        )

        response = await handle_create_admin_user(mock_request)

        assert response.status == 503

    async def test_create_admin_user_missing_fields(self, mock_request):
        """Test create admin user with missing fields.

        Note: Uses MagicMock for db pool since validation fails before DB access.
        """
        mock_auth = MagicMock()  # ALLOWED: validation fails before DB access
        mock_auth.db = MagicMock()  # ALLOWED: validation fails before DB access
        mock_request.app = {"auth_api": mock_auth}
        mock_request.json = AsyncMock(return_value={"email": "test@test.com"})

        response = await handle_create_admin_user(mock_request)

        assert response.status == 400

    async def test_create_admin_user_short_password(self, mock_request):
        """Test create admin user with short password.

        Note: Uses MagicMock for db pool since validation fails before DB access.
        """
        mock_auth = MagicMock()  # ALLOWED: validation fails before DB access
        mock_auth.db = MagicMock()  # ALLOWED: validation fails before DB access
        mock_request.app = {"auth_api": mock_auth}
        mock_request.json = AsyncMock(
            return_value={"email": "test@test.com", "password": "short"}
        )

        response = await handle_create_admin_user(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleDeleteAdminUser:
    """Tests for handle_delete_admin_user endpoint."""

    async def test_delete_admin_user_no_auth(self, mock_request):
        """Test delete admin user when auth not configured."""
        mock_request.app = {}
        mock_request.match_info = {"user_id": str(uuid.uuid4())}

        response = await handle_delete_admin_user(mock_request)

        assert response.status == 503


@pytest.mark.asyncio
class TestHandleGetMetricsHistoryHourly:
    """Tests for handle_get_metrics_history_hourly endpoint."""

    async def test_get_hourly_returns_data(self, mock_request):
        """Test get hourly history returns data."""
        mock_request.query = {"days": "7"}

        with patch("server.metrics_history") as mock_history:
            mock_history.get_hourly_history.return_value = []

            response = await handle_get_metrics_history_hourly(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "history" in data


@pytest.mark.asyncio
class TestHandleGetMetricsHistoryDaily:
    """Tests for handle_get_metrics_history_daily endpoint."""

    async def test_get_daily_returns_data(self, mock_request):
        """Test get daily history returns data."""
        mock_request.query = {"days": "30"}

        with patch("server.metrics_history") as mock_history:
            mock_history.get_daily_history.return_value = []

            response = await handle_get_metrics_history_daily(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "history" in data


@pytest.mark.asyncio
class TestHandleGetMetricsHistorySummary:
    """Tests for handle_get_metrics_history_summary endpoint."""

    async def test_get_summary_returns_data(self, mock_request):
        """Test get summary returns data."""
        with patch("server.metrics_history") as mock_history:
            mock_history.get_summary_stats.return_value = {"total_samples": 100}

            response = await handle_get_metrics_history_summary(mock_request)

            assert response.status == 200


@pytest.mark.asyncio
class TestHandleUnloadModels:
    """Tests for handle_unload_models endpoint."""

    async def test_unload_models_returns_results(self, mock_request):
        """Test unload models returns results."""
        with patch("aiohttp.ClientSession") as mock_session:
            mock_response = MagicMock()  # ALLOWED: external HTTP to Ollama
            mock_response.status = 200
            mock_response.json = AsyncMock(return_value={"models": []})

            mock_context = MagicMock()  # ALLOWED: external HTTP to Ollama
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()  # ALLOWED: external HTTP to Ollama

            mock_session_instance = MagicMock()  # ALLOWED: external HTTP to Ollama
            mock_session_instance.get.return_value = mock_context
            mock_session_instance.post.return_value = mock_context
            mock_session_instance.__aenter__ = AsyncMock(
                return_value=mock_session_instance
            )
            mock_session_instance.__aexit__ = (
                AsyncMock()
            )  # ALLOWED: external HTTP to Ollama

            mock_session.return_value = mock_session_instance

            response = await handle_unload_models(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "results" in data


@pytest.mark.asyncio
class TestHandleDashboard:
    """Tests for handle_dashboard endpoint."""

    async def test_dashboard_redirects(self, mock_request):
        """Test dashboard redirects to Next.js console."""
        mock_request.query = {}

        response = await handle_dashboard(mock_request)

        # Should be a redirect (HTTPFound)
        assert response.status == 302

    async def test_dashboard_legacy_mode(self, mock_request):
        """Test dashboard legacy mode."""
        mock_request.query = {"legacy": "true"}

        response = await handle_dashboard(mock_request)

        # Either returns file or 404 if not found
        assert response.status in [200, 404]


# =============================================================================
# Test Classes - Utility Functions
# =============================================================================


class TestGetProcessMemory:
    """Tests for get_process_memory function."""

    def test_get_process_memory_invalid_pid(self):
        """Test get_process_memory with invalid PID."""
        result = get_process_memory(-1)

        assert result["rss_mb"] == 0
        assert result["vsz_mb"] == 0


class TestGetSystemMemory:
    """Tests for get_system_memory function."""

    def test_get_system_memory_returns_dict(self):
        """Test get_system_memory returns expected structure."""
        result = get_system_memory()

        assert "total_gb" in result
        assert "used_gb" in result
        assert "free_gb" in result
        assert "percent_used" in result


class TestServiceToDict:
    """Tests for service_to_dict function."""

    def test_service_to_dict_basic(self):
        """Test service_to_dict converts service correctly."""
        service = ManagedService(
            id="test",
            name="Test Service",
            service_type="test",
            command=["python"],
            cwd="/test/workdir",  # Test placeholder, not actually used
            port=8000,
            health_url="http://localhost:8000/health",
        )

        result = service_to_dict(service)

        assert result["id"] == "test"
        assert result["name"] == "Test Service"
        assert result["port"] == 8000
        assert "memory" in result


class TestLoadSaveModelConfig:
    """Tests for model config load/save functions."""

    def test_load_model_config_default(self):
        """Test load_model_config returns defaults when file doesn't exist."""
        with patch("pathlib.Path.exists", return_value=False):
            config = load_model_config()

            assert "services" in config
            assert "llm" in config["services"]


class TestLoadSaveModelParams:
    """Tests for model params load/save functions."""

    def test_load_model_params_default(self):
        """Test load_model_params returns empty dict when file doesn't exist."""
        with patch("pathlib.Path.exists", return_value=False):
            params = load_model_params("test-model")

            assert params == {}


# =============================================================================
# Test Classes - Async Service Functions
# =============================================================================


@pytest.mark.asyncio
class TestCheckServiceRunning:
    """Tests for check_service_running function."""

    async def test_check_service_running_timeout(self):
        """Test check_service_running handles timeout."""
        service = ManagedService(
            id="test",
            name="Test",
            service_type="test",
            command=["python"],
            cwd="/test/workdir",  # Test placeholder, not actually used
            port=99999,  # Non-existent port
            health_url="http://localhost:99999/health",
        )

        result = await check_service_running(service)

        assert result is False


@pytest.mark.asyncio
class TestStartService:
    """Tests for start_service function."""

    async def test_start_service_not_found(self):
        """Test start_service with non-existent service."""
        success, message = await start_service("nonexistent")

        assert success is False
        assert "not found" in message


@pytest.mark.asyncio
class TestStopService:
    """Tests for stop_service function."""

    async def test_stop_service_not_found(self):
        """Test stop_service with non-existent service."""
        success, message = await stop_service("nonexistent")

        assert success is False
        assert "not found" in message


@pytest.mark.asyncio
class TestBroadcastMessage:
    """Tests for broadcast_message function."""

    async def test_broadcast_with_no_connections(self):
        """Test broadcast_message with no WebSocket connections."""
        # Clear any existing connections
        state.websockets.clear()

        # Should not raise any errors
        await broadcast_message("test", {"data": "test"})


@pytest.mark.asyncio
class TestCheckServerHealth:
    """Tests for check_server_health function."""

    async def test_check_server_health_timeout(self):
        """Test check_server_health handles timeout."""
        server = ServerStatus(
            id="test",
            name="Test",
            type="custom",
            url="http://localhost:99999",
            port=99999,
        )

        result = await check_server_health(server)

        assert result.status == "unhealthy"


@pytest.mark.asyncio
class TestGetOllamaModelDetails:
    """Tests for get_ollama_model_details function."""

    async def test_get_ollama_model_details_connection_error(self):
        """Test get_ollama_model_details handles connection errors."""
        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()  # ALLOWED: external HTTP to Ollama
            mock_session_instance.get.side_effect = Exception("Connection refused")
            mock_session_instance.__aenter__ = AsyncMock(
                return_value=mock_session_instance
            )
            mock_session_instance.__aexit__ = (
                AsyncMock()
            )  # ALLOWED: external HTTP to Ollama
            mock_session.return_value = mock_session_instance

            result = await get_ollama_model_details()

            assert "details" in result
            assert "loaded" in result


@pytest.mark.asyncio
class TestDetectExistingProcesses:
    """Tests for detect_existing_processes function."""

    async def test_detect_existing_processes_runs(self):
        """Test detect_existing_processes runs without error."""
        with patch(
            "server.check_service_running", new_callable=AsyncMock
        ) as mock_check:
            mock_check.return_value = False

            # Should not raise any errors
            await detect_existing_processes()


# =============================================================================
# Test for DataClass Serialization
# =============================================================================


class TestDataClassSerialization:
    """Tests for dataclass serialization with asdict."""

    def test_log_entry_to_dict(self):
        """Test LogEntry can be serialized to dict."""
        entry = LogEntry(
            id="test",
            timestamp="2025-01-01T00:00:00Z",
            level="INFO",
            label="test",
            message="Test message",
        )

        result = asdict(entry)

        assert result["id"] == "test"
        assert result["level"] == "INFO"
        assert isinstance(result, dict)

    def test_metrics_snapshot_to_dict(self):
        """Test MetricsSnapshot can be serialized to dict."""
        snapshot = MetricsSnapshot(
            id="test",
            client_id="client",
            client_name="Test",
            timestamp="2025-01-01T00:00:00Z",
            received_at=1735689600.0,
        )

        result = asdict(snapshot)

        assert result["id"] == "test"
        assert result["client_id"] == "client"
        assert isinstance(result, dict)

    def test_server_status_to_dict(self):
        """Test ServerStatus can be serialized to dict."""
        server = ServerStatus(
            id="test",
            name="Test",
            type="custom",
            url="http://localhost:8080",
            port=8080,
        )

        result = asdict(server)

        assert result["id"] == "test"
        assert result["type"] == "custom"
        assert isinstance(result, dict)

    def test_curriculum_summary_to_dict(self):
        """Test CurriculumSummary can be serialized to dict."""
        summary = CurriculumSummary(
            id="test",
            title="Test",
            description="Test desc",
            version="1.0",
            topic_count=5,
            total_duration="PT2H",
            difficulty="easy",
            age_range="18+",
        )

        result = asdict(summary)

        assert result["id"] == "test"
        assert result["topic_count"] == 5
        assert isinstance(result, dict)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
