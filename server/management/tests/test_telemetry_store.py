"""
Tests for the SQLite-backed telemetry store (audit findings T1/T8).

TESTING PHILOSOPHY: Real Over Mock
==================================
- Uses the REAL TelemetryStore against a temporary SQLite database
- No mock classes for internal services
"""

import sys
import time
import uuid
from pathlib import Path

import pytest

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from telemetry_store import TelemetryStore, _utc_day  # noqa: E402


def make_snapshot(**overrides):
    """Build a snapshot dict matching the persisted columns."""
    snapshot = {
        "id": str(uuid.uuid4()),
        "client_id": "client-1",
        "client_name": "Test Device",
        "session_id": "session-1",
        "timestamp": "2026-06-10T12:00:00Z",
        "received_at": time.time(),
        "session_duration": 120.0,
        "turns_total": 10,
        "interruptions": 1,
        "stt_latency_median": 100.0,
        "stt_latency_p99": 150.0,
        "llm_ttft_median": 200.0,
        "llm_ttft_p99": 300.0,
        "tts_ttfb_median": 80.0,
        "tts_ttfb_p99": 120.0,
        "e2e_latency_median": 450.0,
        "e2e_latency_p99": 900.0,
        "ttfa_median": 350.0,
        "ttfa_p99": 700.0,
        "error_count": 2,
        "error_rate": 0.2,
        "errors_by_stage": {"stt": 1, "tts": 1},
        "stt_cost": 0.01,
        "tts_cost": 0.02,
        "llm_cost": 0.03,
        "total_cost": 0.06,
        "thermal_throttle_events": 0,
        "network_degradations": 1,
    }
    snapshot.update(overrides)
    return snapshot


@pytest.fixture
async def store(tmp_path):
    """Real TelemetryStore backed by a temporary database file."""
    s = TelemetryStore(tmp_path / "telemetry.db")
    await s.start()
    yield s
    await s.stop()


@pytest.mark.asyncio
class TestSnapshotPersistence:
    """Snapshot save/load roundtrip."""

    async def test_save_and_load_roundtrip(self, store):
        snap = make_snapshot()
        await store.save_snapshot(snap)

        rows = await store.load_recent_snapshots()
        assert len(rows) == 1
        row = rows[0]
        assert row["id"] == snap["id"]
        assert row["client_id"] == "client-1"
        assert row["e2e_latency_p99"] == 900.0
        assert row["ttfa_median"] == 350.0
        assert row["error_count"] == 2
        assert row["errors_by_stage"] == {"stt": 1, "tts": 1}

    async def test_load_recent_returns_oldest_first(self, store):
        now = time.time()
        for i in range(5):
            await store.save_snapshot(
                make_snapshot(received_at=now + i, session_id=f"s-{i}")
            )

        rows = await store.load_recent_snapshots(limit=3)
        assert len(rows) == 3
        # Most recent 3, in append (oldest-first) order
        assert [r["session_id"] for r in rows] == ["s-2", "s-3", "s-4"]

    async def test_unknown_keys_are_ignored(self, store):
        snap = make_snapshot()
        snap["transcript"] = "should never be stored"
        await store.save_snapshot(snap)

        rows = await store.load_recent_snapshots()
        assert len(rows) == 1
        assert "transcript" not in rows[0]

    async def test_snapshots_survive_restart(self, tmp_path):
        db_path = tmp_path / "telemetry.db"
        store1 = TelemetryStore(db_path)
        await store1.start()
        snap = make_snapshot()
        await store1.save_snapshot(snap)
        await store1.stop()

        store2 = TelemetryStore(db_path)
        await store2.start()
        try:
            rows = await store2.load_recent_snapshots()
            assert len(rows) == 1
            assert rows[0]["id"] == snap["id"]
        finally:
            await store2.stop()


@pytest.mark.asyncio
class TestClientRegistry:
    """Client registry persistence and session dedupe."""

    async def test_upsert_and_load_clients(self, store):
        await store.upsert_client(
            client_id="c1",
            name="Device A",
            first_seen=100.0,
            last_seen=200.0,
            total_sessions=3,
        )
        await store.upsert_client(
            client_id="c1",
            name="Device A renamed",
            first_seen=100.0,
            last_seen=300.0,
            total_sessions=4,
        )

        clients = await store.load_clients()
        assert len(clients) == 1
        client = clients[0]
        assert client["name"] == "Device A renamed"
        assert client["last_seen"] == 300.0
        assert client["total_sessions"] == 4

    async def test_record_session_dedupes(self, store):
        assert await store.record_session("c1", "session-a") is True
        assert await store.record_session("c1", "session-a") is False
        assert await store.record_session("c1", "session-b") is True
        assert await store.record_session("c2", "session-a") is True

        session_ids = await store.load_session_ids()
        assert sorted(session_ids["c1"]) == ["session-a", "session-b"]
        assert session_ids["c2"] == ["session-a"]


@pytest.mark.asyncio
class TestDailyCounters:
    """Shared daily counters (realtime token budget)."""

    async def test_increment_and_get(self, store):
        allowed, count = await store.increment_daily_counter("realtime:mints")
        assert allowed is True
        assert count == 1
        allowed, count = await store.increment_daily_counter("realtime:mints")
        assert count == 2
        assert await store.get_daily_counter("realtime:mints") == 2

    async def test_limit_refuses_above_budget(self, store):
        for i in range(3):
            allowed, _ = await store.increment_daily_counter("budget", limit=3)
            assert allowed is True
        allowed, count = await store.increment_daily_counter("budget", limit=3)
        assert allowed is False
        assert count == 3
        # The refused call must not have incremented.
        assert await store.get_daily_counter("budget") == 3

    async def test_counters_are_per_day(self, store):
        await store.increment_daily_counter("budget", day="2026-06-09")
        assert await store.get_daily_counter("budget", day="2026-06-09") == 1
        assert await store.get_daily_counter("budget", day=_utc_day()) == 0

    async def test_counters_survive_restart(self, tmp_path):
        db_path = tmp_path / "telemetry.db"
        store1 = TelemetryStore(db_path)
        await store1.start()
        await store1.increment_daily_counter("realtime:mints")
        await store1.stop()

        store2 = TelemetryStore(db_path)
        await store2.start()
        try:
            assert await store2.get_daily_counter("realtime:mints") == 1
        finally:
            await store2.stop()


@pytest.mark.asyncio
class TestRollupAndPrune:
    """Hourly rollups and retention pruning."""

    async def test_old_snapshots_pruned_and_rolled_up(self, store):
        now = time.time()
        old = now - 40 * 86400  # past the 30-day retention window
        for i in range(4):
            await store.save_snapshot(
                make_snapshot(received_at=old + i, session_id="old-session")
            )
        await store.save_snapshot(make_snapshot(received_at=now))

        pruned = await store.rollup_and_prune(now=now)
        assert pruned["session_snapshots"] == 4

        rows = await store.load_recent_snapshots()
        assert len(rows) == 1

        rollups = await store.get_rollups()
        assert len(rollups) >= 1
        old_rollup = rollups[0]
        assert old_rollup["snapshots"] == 4
        assert old_rollup["sessions"] == 1  # deduped by session_id
        assert old_rollup["turns"] == 40
        assert old_rollup["total_errors"] == 8

    async def test_current_hour_not_rolled_up(self, store):
        now = time.time()
        await store.save_snapshot(make_snapshot(received_at=now))
        await store.rollup_and_prune(now=now)
        rollups = await store.get_rollups()
        assert rollups == []

    async def test_old_counters_pruned(self, store):
        await store.increment_daily_counter("budget", day="2020-01-01")
        await store.increment_daily_counter("budget")
        pruned = await store.rollup_and_prune()
        assert pruned["daily_counters"] == 1
        assert await store.get_daily_counter("budget") == 1
