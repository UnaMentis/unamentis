"""
Tests for the realtime token budget API (denial-of-wallet residual).

Durable daily counters (telemetry-store backed) behind the web client's
realtime token route: a global daily spend ceiling plus a per-IP quota.

TESTING PHILOSOPHY: Real Over Mock
==================================
- Uses the REAL aiohttp test client and the REAL TelemetryStore against a
  temporary SQLite database
"""

import sys
from pathlib import Path

import pytest

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from aiohttp import web  # noqa: E402

from realtime_budget_api import (  # noqa: E402
    TOTAL_COUNTER,
    register_realtime_budget_routes,
)
from telemetry_store import TelemetryStore  # noqa: E402


@pytest.fixture
async def store(tmp_path):
    """Real TelemetryStore backed by a temporary database file."""
    s = TelemetryStore(tmp_path / "telemetry.db")
    await s.start()
    yield s
    await s.stop()


@pytest.fixture
async def client(aiohttp_client, store):
    """Test client for an app with the budget routes and a real store."""
    app = web.Application()
    app["telemetry_store"] = store
    register_realtime_budget_routes(app)
    return await aiohttp_client(app)


@pytest.fixture
async def storeless_client(aiohttp_client):
    """Test client for an app without a telemetry store."""
    app = web.Application()
    register_realtime_budget_routes(app)
    return await aiohttp_client(app)


@pytest.mark.asyncio
class TestReserveBudget:
    """POST /api/realtime/budget/reserve"""

    async def test_reserve_allowed_and_counts(self, client, store):
        resp = await client.post(
            "/api/realtime/budget/reserve", json={"clientIp": "203.0.113.9"}
        )
        assert resp.status == 200
        data = await resp.json()
        assert data["allowed"] is True
        assert data["totalToday"] == 1
        assert await store.get_daily_counter(TOTAL_COUNTER) == 1

    async def test_daily_budget_refuses_above_ceiling(self, client, monkeypatch):
        monkeypatch.setenv("REALTIME_DAILY_TOKEN_BUDGET", "2")
        monkeypatch.setenv("REALTIME_IP_DAILY_QUOTA", "100")
        for _ in range(2):
            resp = await client.post(
                "/api/realtime/budget/reserve", json={"clientIp": "203.0.113.9"}
            )
            assert resp.status == 200

        resp = await client.post(
            "/api/realtime/budget/reserve", json={"clientIp": "203.0.113.9"}
        )
        assert resp.status == 429
        data = await resp.json()
        assert data["allowed"] is False
        assert "daily token budget" in data["reason"]

    async def test_per_ip_quota_independent_of_budget(self, client, monkeypatch):
        monkeypatch.setenv("REALTIME_DAILY_TOKEN_BUDGET", "100")
        monkeypatch.setenv("REALTIME_IP_DAILY_QUOTA", "2")
        for _ in range(2):
            resp = await client.post(
                "/api/realtime/budget/reserve", json={"clientIp": "203.0.113.9"}
            )
            assert resp.status == 200

        # Third mint from the same source trips the per-IP quota
        resp = await client.post(
            "/api/realtime/budget/reserve", json={"clientIp": "203.0.113.9"}
        )
        assert resp.status == 429
        data = await resp.json()
        assert "per-ip" in data["reason"]

        # A different source is unaffected (its own quota)
        resp = await client.post(
            "/api/realtime/budget/reserve", json={"clientIp": "198.51.100.7"}
        )
        assert resp.status == 200

    async def test_missing_body_falls_back_to_peer_ip(self, client):
        resp = await client.post("/api/realtime/budget/reserve")
        assert resp.status == 200
        data = await resp.json()
        assert data["allowed"] is True

    async def test_no_store_returns_503(self, storeless_client):
        resp = await storeless_client.post(
            "/api/realtime/budget/reserve", json={"clientIp": "203.0.113.9"}
        )
        assert resp.status == 503
        data = await resp.json()
        assert data["allowed"] is False

    async def test_budget_survives_restart(self, aiohttp_client, tmp_path, monkeypatch):
        monkeypatch.setenv("REALTIME_DAILY_TOKEN_BUDGET", "1")
        db_path = tmp_path / "budget.db"

        store1 = TelemetryStore(db_path)
        await store1.start()
        app1 = web.Application()
        app1["telemetry_store"] = store1
        register_realtime_budget_routes(app1)
        client1 = await aiohttp_client(app1)
        resp = await client1.post(
            "/api/realtime/budget/reserve", json={"clientIp": "203.0.113.9"}
        )
        assert resp.status == 200
        await store1.stop()

        # New store instance over the same database: budget remains spent
        store2 = TelemetryStore(db_path)
        await store2.start()
        try:
            app2 = web.Application()
            app2["telemetry_store"] = store2
            register_realtime_budget_routes(app2)
            client2 = await aiohttp_client(app2)
            resp = await client2.post(
                "/api/realtime/budget/reserve", json={"clientIp": "203.0.113.9"}
            )
            assert resp.status == 429
        finally:
            await store2.stop()


@pytest.mark.asyncio
class TestBudgetStatus:
    """GET /api/realtime/budget"""

    async def test_status_reports_counts(self, client, monkeypatch):
        monkeypatch.setenv("REALTIME_DAILY_TOKEN_BUDGET", "10")
        await client.post(
            "/api/realtime/budget/reserve", json={"clientIp": "203.0.113.9"}
        )

        resp = await client.get("/api/realtime/budget")
        assert resp.status == 200
        data = await resp.json()
        assert data["totalToday"] == 1
        assert data["dailyBudget"] == 10
        assert data["remaining"] == 9

    async def test_status_without_store_returns_503(self, storeless_client):
        resp = await storeless_client.get("/api/realtime/budget")
        assert resp.status == 503
