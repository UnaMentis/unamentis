"""
Tests for the auth-path IP retention sweep (privacy audit finding B10).

The sweep nulls stored exact IPs on auth_audit_log rows older than the
retention window and on expired/revoked refresh_tokens rows. These tests use a
small recording connection double for the asyncpg pool (the same database-layer
testing approach as test_auth_api.py) and assert the SQL targets, the cutoff
parameter, and the parsed row counts.
"""

import asyncio
from datetime import datetime, timedelta, timezone

import pytest

from auth.ip_retention import (
    AUTH_IP_RETENTION_DAYS,
    _parse_update_count,
    auth_ip_retention_loop,
    sweep_auth_ip_retention,
)


class RecordingConnection:
    """Records executed queries and returns canned asyncpg command statuses."""

    def __init__(self, statuses=None):
        self.executed_queries = []
        self._statuses = list(statuses) if statuses else []

    async def execute(self, query: str, *args):
        self.executed_queries.append((query, args))
        if self._statuses:
            return self._statuses.pop(0)
        return "UPDATE 0"


class RecordingConnectionContext:
    def __init__(self, conn):
        self.conn = conn

    async def __aenter__(self):
        return self.conn

    async def __aexit__(self, *args):
        pass


class RecordingPool:
    """Pool double exposing acquire() like asyncpg.Pool."""

    def __init__(self, statuses=None, fail_times: int = 0):
        self.conn = RecordingConnection(statuses)
        self.fail_times = fail_times
        self.acquire_count = 0

    def acquire(self):
        self.acquire_count += 1
        if self.fail_times > 0:
            self.fail_times -= 1
            raise ConnectionError("simulated pool failure")
        return RecordingConnectionContext(self.conn)


class TestParseUpdateCount:
    def test_parses_standard_status(self):
        assert _parse_update_count("UPDATE 3") == 3

    def test_parses_zero(self):
        assert _parse_update_count("UPDATE 0") == 0

    def test_handles_garbage(self):
        assert _parse_update_count("nonsense") == 0

    def test_handles_none(self):
        assert _parse_update_count(None) == 0


class TestSweep:
    @pytest.mark.asyncio
    async def test_sweep_targets_both_tables(self):
        """The sweep nulls ip_address on auth_audit_log and refresh_tokens."""
        pool = RecordingPool(statuses=["UPDATE 5", "UPDATE 2"])

        counts = await sweep_auth_ip_retention(pool)

        assert counts == {"auth_audit_log": 5, "refresh_tokens": 2}
        queries = [q for q, _ in pool.conn.executed_queries]
        assert len(queries) == 2
        assert "UPDATE auth_audit_log" in queries[0]
        assert "SET ip_address = NULL" in queries[0]
        assert "ip_address IS NOT NULL" in queries[0]
        assert "UPDATE refresh_tokens" in queries[1]
        assert "SET ip_address = NULL" in queries[1]
        # Live tokens keep their IP: only expired or revoked rows are scrubbed.
        assert "is_revoked" in queries[1]
        assert "expires_at < NOW()" in queries[1]

    @pytest.mark.asyncio
    async def test_sweep_uses_retention_cutoff(self):
        """Both statements are bound to a cutoff of now minus the window."""
        pool = RecordingPool()

        before = datetime.now(timezone.utc)
        await sweep_auth_ip_retention(pool, retention_days=90)
        after = datetime.now(timezone.utc)

        for _, args in pool.conn.executed_queries:
            assert len(args) == 1
            cutoff = args[0]
            assert before - timedelta(days=90) <= cutoff
            assert cutoff <= after - timedelta(days=90)

    @pytest.mark.asyncio
    async def test_sweep_default_window_is_disclosed_90_days(self):
        """The default window matches the 90 days disclosed on /privacy."""
        assert AUTH_IP_RETENTION_DAYS == 90

        pool = RecordingPool()
        await sweep_auth_ip_retention(pool)

        cutoff = pool.conn.executed_queries[0][1][0]
        expected = datetime.now(timezone.utc) - timedelta(days=90)
        assert abs((cutoff - expected).total_seconds()) < 60

    @pytest.mark.asyncio
    async def test_sweep_returns_zero_when_nothing_to_scrub(self):
        pool = RecordingPool(statuses=["UPDATE 0", "UPDATE 0"])

        counts = await sweep_auth_ip_retention(pool)

        assert counts == {"auth_audit_log": 0, "refresh_tokens": 0}


class TestRetentionLoop:
    @pytest.mark.asyncio
    async def test_loop_sweeps_immediately_and_repeats(self):
        """The loop runs one sweep at startup, then again each interval."""
        pool = RecordingPool()

        task = asyncio.create_task(auth_ip_retention_loop(pool, interval_seconds=0.01))
        try:
            for _ in range(100):
                await asyncio.sleep(0.01)
                if pool.acquire_count >= 2:
                    break
        finally:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

        assert pool.acquire_count >= 2

    @pytest.mark.asyncio
    async def test_loop_survives_sweep_errors(self):
        """A failing sweep is logged and the loop keeps running."""
        pool = RecordingPool(fail_times=1)

        task = asyncio.create_task(auth_ip_retention_loop(pool, interval_seconds=0.01))
        try:
            for _ in range(100):
                await asyncio.sleep(0.01)
                # First acquire raised; wait for a later successful sweep.
                if pool.conn.executed_queries:
                    break
        finally:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

        assert pool.acquire_count >= 2
        assert pool.conn.executed_queries

    @pytest.mark.asyncio
    async def test_loop_cancels_cleanly(self):
        pool = RecordingPool()

        task = asyncio.create_task(auth_ip_retention_loop(pool, interval_seconds=60))
        await asyncio.sleep(0.05)
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

        assert task.done()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
