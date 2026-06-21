"""
Tests for the hardened telemetry intake (audit findings T1, T2, T4, T7,
ND2, ND3) and the log redaction guards (ws-token-in-access-logs).

TESTING PHILOSOPHY: Real Over Mock
==================================
- Uses REAL aiohttp test utilities (make_mocked_request) and the REAL
  TelemetryStore against temporary SQLite databases
- No mock classes for internal services
"""

import json
import sys
import time
import uuid
from pathlib import Path

import pytest

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from aiohttp import web  # noqa: E402
from aiohttp.test_utils import make_mocked_request  # noqa: E402

import server as server_module  # noqa: E402
from server import (  # noqa: E402
    MAX_METRICS_BODY_BYTES,
    MetricsSnapshot,
    RedactingAccessLogger,
    handle_get_metrics,
    handle_receive_metrics,
    hydrate_telemetry_state,
    sanitize_metrics_payload,
    state,
)
from diagnostic_logging import redact_query  # noqa: E402
from telemetry_store import TelemetryStore  # noqa: E402


class RecordingSocket:
    """Minimal real WebSocket stand-in that records broadcast frames."""

    def __init__(self):
        self.messages = []

    async def send_str(self, message: str):
        self.messages.append(message)


@pytest.fixture(autouse=True)
def clean_state():
    """Isolate the module-global state between tests."""

    def _reset():
        state.metrics_history.clear()
        state._metrics_history_sizes.clear()
        state.metrics_history_bytes = 0
        state.session_ids_by_client.clear()
        state.clients.clear()
        state.websockets.clear()

    _reset()
    yield
    _reset()


def make_metrics_request(json_data, headers=None, app_extras=None):
    """Build a real mocked POST /api/metrics request."""
    app = web.Application()
    if app_extras:
        for key, value in app_extras.items():
            app[key] = value
    request = make_mocked_request(
        "POST",
        "/api/metrics",
        app=app,
        headers=headers
        or {"X-Client-ID": "test-client", "X-Client-Name": "Test Device"},
    )

    async def _json():
        return json_data

    request.json = _json
    return request


def make_get_metrics_request(query=None):
    """Build a real mocked GET /api/metrics request."""
    path = "/api/metrics"
    request = make_mocked_request("GET", path, app=web.Application())
    if query:
        from yarl import URL

        request._rel_url = URL(path).with_query(query)
        request._cache["query"] = query
    return request


# =============================================================================
# T7: allow-list payload sanitization
# =============================================================================


class TestSanitizeMetricsPayload:
    """Tests for the intake field allow-list."""

    def test_drops_unknown_fields(self):
        clean = sanitize_metrics_payload(
            {
                "turnsTotal": 5,
                "transcript": "the user said something private",
                "userUtterances": ["hello"],
                "deviceContacts": {"a": 1},
            }
        )
        assert clean == {"turnsTotal": 5}

    def test_coerces_numeric_types(self):
        clean = sanitize_metrics_payload(
            {
                "e2eLatencyMedian": "450.5",
                "turnsTotal": "12",
                "errorCount": 3.9,
                "sttCost": "not-a-number",
            }
        )
        assert clean["e2eLatencyMedian"] == 450.5
        assert clean["turnsTotal"] == 12
        assert clean["errorCount"] == 3
        assert clean["sttCost"] == 0.0

    def test_clamps_negative_values(self):
        clean = sanitize_metrics_payload({"turnsTotal": -5, "e2eLatencyMedian": -100.0})
        assert clean["turnsTotal"] == 0
        assert clean["e2eLatencyMedian"] == 0.0

    def test_caps_string_lengths(self):
        clean = sanitize_metrics_payload(
            {"sessionId": "x" * 500, "timestamp": "y" * 500}
        )
        assert len(clean["sessionId"]) == 64
        assert len(clean["timestamp"]) == 64

    def test_drops_non_string_session_id(self):
        clean = sanitize_metrics_payload({"sessionId": {"nested": "object"}})
        assert "sessionId" not in clean

    def test_errors_by_stage_keeps_only_known_stages(self):
        clean = sanitize_metrics_payload(
            {
                "errorsByStage": {
                    "stt": 2,
                    "tts": "1",
                    "freeform transcript text": 1,
                    "llm": -3,
                }
            }
        )
        assert clean["errorsByStage"] == {"stt": 2, "tts": 1, "llm": 0}


@pytest.mark.asyncio
class TestIntakeAllowList:
    """End-to-end: unknown fields never reach storage, GET, or broadcast."""

    async def test_transcript_never_stored_or_served(self):
        request = make_metrics_request(
            {
                "timestamp": "2026-06-10T12:00:00Z",
                "turnsTotal": 3,
                "transcript": "SECRET-TRANSCRIPT-CONTENT",
            }
        )
        response = await handle_receive_metrics(request)
        assert response.status == 200

        # Not in the stored snapshot
        snapshot = state.metrics_history[-1]
        assert "transcript" not in snapshot.raw_data
        assert "SECRET-TRANSCRIPT-CONTENT" not in json.dumps(
            snapshot.raw_data, default=str
        )

        # Not in the GET /api/metrics response
        get_response = await handle_get_metrics(make_get_metrics_request())
        assert get_response.status == 200
        assert "SECRET-TRANSCRIPT-CONTENT" not in get_response.body.decode()

    async def test_broadcast_excludes_raw_data(self):
        socket = RecordingSocket()
        state.websockets.add(socket)
        request = make_metrics_request(
            {"timestamp": "2026-06-10T12:00:00Z", "turnsTotal": 3}
        )
        response = await handle_receive_metrics(request)
        assert response.status == 200
        assert len(socket.messages) == 1
        frame = json.loads(socket.messages[0])
        assert frame["type"] == "metrics"
        assert "raw_data" not in frame["data"]
        assert frame["data"]["turns_total"] == 3


@pytest.mark.asyncio
class TestIntakeBodyCap:
    """ND2: oversized payloads are rejected before parsing."""

    async def test_oversized_content_length_rejected(self):
        request = make_mocked_request(
            "POST",
            "/api/metrics",
            app=web.Application(),
            headers={
                "X-Client-ID": "test-client",
                "Content-Length": str(MAX_METRICS_BODY_BYTES + 1),
            },
        )
        response = await handle_receive_metrics(request)
        assert response.status == 413

    async def test_body_at_cap_accepted(self):
        request = make_metrics_request({"turnsTotal": 1})
        # make_mocked_request leaves Content-Length unset (None), which is
        # within the cap by definition.
        response = await handle_receive_metrics(request)
        assert response.status == 200

    async def test_non_object_body_rejected(self):
        request = make_metrics_request(["not", "an", "object"])
        response = await handle_receive_metrics(request)
        assert response.status == 400


class TestByteAwareHotCache:
    """ND2: the in-memory cache is capped by bytes, not just count."""

    def test_eviction_when_byte_budget_exceeded(self, monkeypatch):
        monkeypatch.setattr(server_module, "MAX_METRICS_CACHE_BYTES", 2048)
        for i in range(20):
            snapshot = MetricsSnapshot(
                id=str(uuid.uuid4()),
                client_id="c1",
                client_name="Device",
                timestamp="2026-06-10T12:00:00Z",
                received_at=time.time(),
                raw_data={"filler": "x" * 400, "index": i},
            )
            state.append_metrics_snapshot(snapshot)
            assert state.metrics_history_bytes <= 2048

        # Oldest entries were evicted, newest retained
        assert len(state.metrics_history) < 20
        assert state.metrics_history[-1].raw_data["index"] == 19


# =============================================================================
# T2/T4: error and TTFA fields in schema and aggregates
# =============================================================================


@pytest.mark.asyncio
class TestErrorAndTTFAFields:
    """Typed error_count/errors_by_stage/ttfa fields flow through."""

    async def test_snapshot_captures_new_fields(self):
        request = make_metrics_request(
            {
                "timestamp": "2026-06-10T12:00:00Z",
                "turnsTotal": 10,
                "errorCount": 2,
                "errorsByStage": {"stt": 1, "tts": 1},
                "ttfaMedian": 320.5,
                "ttfaP99": 800.0,
                "sessionId": "session-xyz",
            }
        )
        response = await handle_receive_metrics(request)
        assert response.status == 200

        snapshot = state.metrics_history[-1]
        assert snapshot.error_count == 2
        assert snapshot.error_rate == 0.2
        assert snapshot.errors_by_stage == {"stt": 1, "tts": 1}
        assert snapshot.ttfa_median == 320.5
        assert snapshot.ttfa_p99 == 800.0
        assert snapshot.session_id == "session-xyz"

    async def test_aggregates_include_new_metrics(self):
        for i, session in enumerate(["s1", "s2"]):
            request = make_metrics_request(
                {
                    "timestamp": "2026-06-10T12:00:00Z",
                    "sessionId": session,
                    "turnsTotal": 10,
                    "errorCount": 1,
                    "errorsByStage": {"llm": 1},
                    "ttfaMedian": 300.0 + i * 100,
                    "ttfaP99": 600.0,
                    "e2eLatencyP99": 900.0,
                }
            )
            await handle_receive_metrics(request)

        response = await handle_get_metrics(make_get_metrics_request())
        data = json.loads(response.body)
        aggregates = data["aggregates"]
        assert aggregates["total_errors"] == 2
        assert aggregates["avg_error_rate"] == 0.1
        assert aggregates["errors_by_stage"] == {"llm": 2}
        assert aggregates["avg_ttfa"] == 350.0
        assert aggregates["avg_ttfa_p99"] == 600.0
        assert aggregates["avg_e2e_p99"] == 900.0

    async def test_empty_aggregates_include_new_keys(self):
        response = await handle_get_metrics(make_get_metrics_request())
        aggregates = json.loads(response.body)["aggregates"]
        for key in (
            "avg_e2e_p99",
            "avg_ttfa",
            "avg_ttfa_p99",
            "total_errors",
            "avg_error_rate",
            "errors_by_stage",
        ):
            assert key in aggregates


# =============================================================================
# ND3: session counting dedupe
# =============================================================================


@pytest.mark.asyncio
class TestSessionDedupe:
    """Sessions are counted by unique sessionId, not per POST."""

    async def test_repeat_session_id_counts_once(self):
        for _ in range(3):
            request = make_metrics_request({"sessionId": "session-1", "turnsTotal": 1})
            await handle_receive_metrics(request)

        assert state.clients["test-client"].total_sessions == 1

    async def test_distinct_session_ids_count_separately(self):
        for session in ("session-1", "session-2"):
            request = make_metrics_request({"sessionId": session})
            await handle_receive_metrics(request)

        assert state.clients["test-client"].total_sessions == 2

    async def test_missing_session_id_keeps_legacy_per_post_count(self):
        for _ in range(2):
            await handle_receive_metrics(make_metrics_request({"turnsTotal": 1}))

        assert state.clients["test-client"].total_sessions == 2

    async def test_aggregate_total_sessions_dedupes(self):
        for session in ("session-1", "session-1", "session-2"):
            await handle_receive_metrics(make_metrics_request({"sessionId": session}))

        response = await handle_get_metrics(make_get_metrics_request())
        data = json.loads(response.body)
        assert data["aggregates"]["total_sessions"] == 2


# =============================================================================
# T1: persistence write-through and restart hydration
# =============================================================================


@pytest.mark.asyncio
class TestPersistenceWireThrough:
    """Snapshots, clients, and sessions write through to the store."""

    async def test_post_persists_and_hydration_restores(self, tmp_path):
        store = TelemetryStore(tmp_path / "telemetry.db")
        await store.start()
        try:
            request = make_metrics_request(
                {
                    "timestamp": "2026-06-10T12:00:00Z",
                    "sessionId": "session-1",
                    "turnsTotal": 7,
                    "errorCount": 1,
                    "ttfaMedian": 333.0,
                },
                app_extras={"telemetry_store": store},
            )
            response = await handle_receive_metrics(request)
            assert response.status == 200

            # Persisted to SQLite
            rows = await store.load_recent_snapshots()
            assert len(rows) == 1
            assert rows[0]["turns_total"] == 7
            assert rows[0]["session_id"] == "session-1"
            clients = await store.load_clients()
            assert clients[0]["client_id"] == "test-client"
            assert clients[0]["total_sessions"] == 1

            # Simulate a restart: wipe the in-memory state, then hydrate
            state.metrics_history.clear()
            state._metrics_history_sizes.clear()
            state.metrics_history_bytes = 0
            state.clients.clear()
            state.session_ids_by_client.clear()

            await hydrate_telemetry_state(store)

            assert len(state.metrics_history) == 1
            restored = state.metrics_history[-1]
            assert restored.turns_total == 7
            assert restored.ttfa_median == 333.0
            assert state.clients["test-client"].total_sessions == 1
            assert "session-1" in state.session_ids_by_client["test-client"]

            # A re-posted snapshot for the same session does not double count
            request = make_metrics_request(
                {"sessionId": "session-1", "turnsTotal": 8},
                app_extras={"telemetry_store": store},
            )
            await handle_receive_metrics(request)
            assert state.clients["test-client"].total_sessions == 1
        finally:
            await store.stop()

    async def test_intake_survives_store_failure(self, tmp_path):
        store = TelemetryStore(tmp_path / "telemetry.db")
        await store.start()
        await store.stop()  # closed store: writes will fail

        request = make_metrics_request(
            {"turnsTotal": 2}, app_extras={"telemetry_store": store}
        )
        response = await handle_receive_metrics(request)
        # Hot cache still serves even when persistence fails
        assert response.status == 200
        assert len(state.metrics_history) == 1


# =============================================================================
# ws-token-in-access-logs: redaction guards
# =============================================================================


class TestAccessLogRedaction:
    """Tokens passed as query parameters never reach access logs."""

    def test_token_query_redacted_in_request_line(self):
        request = make_mocked_request(
            "GET", "/api/audio/ws?session_id=abc&token=eyJhbGci.secret.value"
        )
        line = RedactingAccessLogger._format_r(request, None, 0.0)
        assert "eyJhbGci.secret.value" not in line
        assert "token=REDACTED" in line
        assert "session_id=abc" in line

    def test_other_sensitive_keys_redacted(self):
        request = make_mocked_request(
            "GET", "/api/thing?api_key=abc123&password=hunter2&q=ok"
        )
        line = RedactingAccessLogger._format_r(request, None, 0.0)
        assert "abc123" not in line
        assert "hunter2" not in line
        assert "q=ok" in line

    def test_plain_paths_unchanged(self):
        request = make_mocked_request("GET", "/api/metrics?limit=10")
        line = RedactingAccessLogger._format_r(request, None, 0.0)
        assert line == "GET /api/metrics?limit=10 HTTP/1.1"

    def test_none_request_returns_dash(self):
        assert RedactingAccessLogger._format_r(None, None, 0.0) == "-"

    def test_emitted_access_log_line_is_redacted(self, caplog):
        """End-to-end through the compiled format path.

        AccessLogger binds atom formatters to the base class and caches them
        globally, so this verifies the redaction survives the real logging
        pipeline, not just a direct _format_r call.
        """
        import logging

        access_logger = RedactingAccessLogger(logging.getLogger("test.access"))
        request = make_mocked_request(
            "GET", "/api/audio/ws?session_id=abc&token=eyJlive.jwt.token"
        )
        response = web.Response(status=101)
        with caplog.at_level(logging.INFO, logger="test.access"):
            access_logger.log(request, response, 0.012)

        combined = " ".join(r.getMessage() for r in caplog.records)
        assert combined  # the access line was emitted
        assert "eyJlive.jwt.token" not in combined
        assert "token=REDACTED" in combined


class TestDiagnosticQueryRedaction:
    """diagnostic_logging redacts sensitive query values."""

    def test_redacts_sensitive_keys(self):
        query = {"token": "eyJsecret", "session_id": "abc", "KEY": "k123"}
        redacted = redact_query(query)
        assert redacted["token"] == "REDACTED"
        assert redacted["KEY"] == "REDACTED"
        assert redacted["session_id"] == "abc"
