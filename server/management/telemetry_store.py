#!/usr/bin/env python3
"""
SQLite-backed persistence for client telemetry.

The management server keeps a small in-memory deque of recent client metrics
snapshots as a hot cache. This module is the durable layer behind it, so the
Operations Console survives server restarts (audit findings T1/T8).

Design notes:
- Uses the stdlib sqlite3 driver executed on a dedicated single-thread
  executor. This is the lightest option consistent with the codebase
  (aiosqlite is only a test dependency, asyncpg requires DATABASE_URL).
  The single worker thread guarantees the connection is only ever touched
  from the thread that created it and serializes all access.
- Tables: session_snapshots (typed columns only, deliberately no raw_data
  column so the intake allow-list is also schema-enforced), client_registry,
  client_sessions (session dedupe across restarts), rollups (hourly
  aggregates kept indefinitely), and daily_counters (shared budget counters,
  e.g. the realtime token mint budget).
- Retention: raw snapshots are pruned after SNAPSHOT_RETENTION_DAYS; hourly
  rollups are computed before pruning and kept indefinitely (tiny footprint,
  matching the metrics_history approach).
"""

from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

DEFAULT_DB_PATH = Path(__file__).parent / "data" / "telemetry.db"

SNAPSHOT_RETENTION_DAYS = 30
SESSION_RETENTION_DAYS = 30
COUNTER_RETENTION_DAYS = 7
PRUNE_INTERVAL_SECONDS = 3600

# Typed snapshot columns persisted to SQLite. errors_by_stage is stored as a
# small JSON object; everything else is a scalar.
SNAPSHOT_COLUMNS: Tuple[str, ...] = (
    "id",
    "client_id",
    "client_name",
    "session_id",
    "timestamp",
    "received_at",
    "session_duration",
    "turns_total",
    "interruptions",
    "stt_latency_median",
    "stt_latency_p99",
    "llm_ttft_median",
    "llm_ttft_p99",
    "tts_ttfb_median",
    "tts_ttfb_p99",
    "e2e_latency_median",
    "e2e_latency_p99",
    "ttfa_median",
    "ttfa_p99",
    "error_count",
    "error_rate",
    "errors_by_stage",
    "stt_cost",
    "tts_cost",
    "llm_cost",
    "total_cost",
    "thermal_throttle_events",
    "network_degradations",
)

_SCHEMA = """
CREATE TABLE IF NOT EXISTS session_snapshots (
    id TEXT PRIMARY KEY,
    client_id TEXT NOT NULL DEFAULT '',
    client_name TEXT NOT NULL DEFAULT '',
    session_id TEXT NOT NULL DEFAULT '',
    timestamp TEXT NOT NULL DEFAULT '',
    received_at REAL NOT NULL,
    session_duration REAL NOT NULL DEFAULT 0,
    turns_total INTEGER NOT NULL DEFAULT 0,
    interruptions INTEGER NOT NULL DEFAULT 0,
    stt_latency_median REAL NOT NULL DEFAULT 0,
    stt_latency_p99 REAL NOT NULL DEFAULT 0,
    llm_ttft_median REAL NOT NULL DEFAULT 0,
    llm_ttft_p99 REAL NOT NULL DEFAULT 0,
    tts_ttfb_median REAL NOT NULL DEFAULT 0,
    tts_ttfb_p99 REAL NOT NULL DEFAULT 0,
    e2e_latency_median REAL NOT NULL DEFAULT 0,
    e2e_latency_p99 REAL NOT NULL DEFAULT 0,
    ttfa_median REAL NOT NULL DEFAULT 0,
    ttfa_p99 REAL NOT NULL DEFAULT 0,
    error_count INTEGER NOT NULL DEFAULT 0,
    error_rate REAL NOT NULL DEFAULT 0,
    errors_by_stage TEXT NOT NULL DEFAULT '{}',
    stt_cost REAL NOT NULL DEFAULT 0,
    tts_cost REAL NOT NULL DEFAULT 0,
    llm_cost REAL NOT NULL DEFAULT 0,
    total_cost REAL NOT NULL DEFAULT 0,
    thermal_throttle_events INTEGER NOT NULL DEFAULT 0,
    network_degradations INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_snapshots_received_at
    ON session_snapshots(received_at);
CREATE INDEX IF NOT EXISTS idx_snapshots_client_received
    ON session_snapshots(client_id, received_at);

CREATE TABLE IF NOT EXISTS client_registry (
    client_id TEXT PRIMARY KEY,
    name TEXT NOT NULL DEFAULT '',
    first_seen REAL NOT NULL,
    last_seen REAL NOT NULL,
    total_sessions INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS client_sessions (
    client_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    first_seen REAL NOT NULL,
    PRIMARY KEY (client_id, session_id)
);

CREATE TABLE IF NOT EXISTS rollups (
    hour TEXT PRIMARY KEY,
    snapshots INTEGER NOT NULL DEFAULT 0,
    sessions INTEGER NOT NULL DEFAULT 0,
    turns INTEGER NOT NULL DEFAULT 0,
    avg_e2e_latency_median REAL NOT NULL DEFAULT 0,
    avg_e2e_latency_p99 REAL NOT NULL DEFAULT 0,
    avg_ttfa_median REAL NOT NULL DEFAULT 0,
    total_errors INTEGER NOT NULL DEFAULT 0,
    avg_error_rate REAL NOT NULL DEFAULT 0,
    total_cost REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS daily_counters (
    name TEXT NOT NULL,
    day TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (name, day)
);
"""


def _utc_day(ts: Optional[float] = None) -> str:
    """Return the UTC day key (YYYY-MM-DD) for a unix timestamp."""
    dt = datetime.fromtimestamp(ts if ts is not None else time.time(), tz=timezone.utc)
    return dt.strftime("%Y-%m-%d")


def _hour_key(received_at: float) -> str:
    """Return the UTC hour key (ISO, minute zeroed) for a unix timestamp."""
    dt = datetime.fromtimestamp(received_at, tz=timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:00:00")


class TelemetryStore:
    """Durable store for client telemetry snapshots and budget counters.

    All public methods are async. Internally each operation runs on a
    dedicated single-thread executor that owns the sqlite3 connection, so
    every read-check-update sequence is naturally atomic with respect to
    other store calls in this process.
    """

    def __init__(self, db_path: Path | str = DEFAULT_DB_PATH):
        self.db_path = Path(db_path)
        self._executor: Optional[ThreadPoolExecutor] = None
        self._conn: Optional[sqlite3.Connection] = None
        self._prune_task: Optional[asyncio.Task] = None
        self._started = False

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def start(self) -> None:
        """Open the database, apply schema, and start the prune loop."""
        if self._started:
            return
        self._executor = ThreadPoolExecutor(
            max_workers=1, thread_name_prefix="telemetry-store"
        )
        await self._run(self._open_sync)
        self._started = True
        self._prune_task = asyncio.create_task(self._prune_loop())
        logger.info(f"Telemetry store ready at {self.db_path}")

    async def stop(self) -> None:
        """Stop the prune loop and close the database."""
        if not self._started:
            return
        self._started = False
        if self._prune_task:
            self._prune_task.cancel()
            try:
                await self._prune_task
            except asyncio.CancelledError:
                pass
            self._prune_task = None
        await self._run(self._close_sync)
        if self._executor:
            self._executor.shutdown(wait=True)
            self._executor = None

    def _open_sync(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.db_path))
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._conn.executescript(_SCHEMA)
        self._conn.commit()

    def _close_sync(self) -> None:
        if self._conn is not None:
            self._conn.commit()
            self._conn.close()
            self._conn = None

    async def _run(self, fn, *args):
        if self._executor is None:
            raise RuntimeError("TelemetryStore is not started")
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(self._executor, fn, *args)

    async def _prune_loop(self) -> None:
        while True:
            try:
                await asyncio.sleep(PRUNE_INTERVAL_SECONDS)
                await self.rollup_and_prune()
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error(f"Telemetry store prune failed: {e}")

    # ------------------------------------------------------------------
    # Snapshots
    # ------------------------------------------------------------------

    async def save_snapshot(self, snapshot: Dict[str, Any]) -> None:
        """Persist one metrics snapshot (dict of MetricsSnapshot fields).

        Unknown keys are ignored; only the typed SNAPSHOT_COLUMNS are stored.
        """
        row = []
        for col in SNAPSHOT_COLUMNS:
            value = snapshot.get(col)
            if col == "errors_by_stage":
                value = json.dumps(value or {})
            row.append(value)
        placeholders = ", ".join("?" for _ in SNAPSHOT_COLUMNS)
        sql = (
            f"INSERT OR REPLACE INTO session_snapshots "
            f"({', '.join(SNAPSHOT_COLUMNS)}) VALUES ({placeholders})"
        )

        def _write():
            self._conn.execute(sql, row)
            self._conn.commit()

        await self._run(_write)

    async def load_recent_snapshots(self, limit: int = 1000) -> List[Dict[str, Any]]:
        """Load the most recent snapshots, oldest first (deque append order)."""

        def _read():
            cur = self._conn.execute(
                "SELECT * FROM session_snapshots ORDER BY received_at DESC LIMIT ?",
                (int(limit),),
            )
            return [dict(r) for r in cur.fetchall()]

        rows = await self._run(_read)
        rows.reverse()
        for r in rows:
            try:
                r["errors_by_stage"] = json.loads(r.get("errors_by_stage") or "{}")
            except (TypeError, ValueError):
                r["errors_by_stage"] = {}
        return rows

    # ------------------------------------------------------------------
    # Client registry and session dedupe
    # ------------------------------------------------------------------

    async def upsert_client(
        self,
        client_id: str,
        name: str,
        first_seen: float,
        last_seen: float,
        total_sessions: int,
    ) -> None:
        """Insert or update a client registry row."""

        def _write():
            self._conn.execute(
                """
                INSERT INTO client_registry
                    (client_id, name, first_seen, last_seen, total_sessions)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(client_id) DO UPDATE SET
                    name = excluded.name,
                    last_seen = excluded.last_seen,
                    total_sessions = excluded.total_sessions
                """,
                (client_id, name, first_seen, last_seen, int(total_sessions)),
            )
            self._conn.commit()

        await self._run(_write)

    async def load_clients(self) -> List[Dict[str, Any]]:
        """Load all client registry rows."""

        def _read():
            cur = self._conn.execute("SELECT * FROM client_registry")
            return [dict(r) for r in cur.fetchall()]

        return await self._run(_read)

    async def record_session(self, client_id: str, session_id: str) -> bool:
        """Record a (client, session) pair. Returns True when first seen."""

        def _write() -> bool:
            cur = self._conn.execute(
                "INSERT OR IGNORE INTO client_sessions "
                "(client_id, session_id, first_seen) VALUES (?, ?, ?)",
                (client_id, session_id, time.time()),
            )
            self._conn.commit()
            return cur.rowcount > 0

        return await self._run(_write)

    async def load_session_ids(self) -> Dict[str, List[str]]:
        """Load known session ids grouped by client id (for dedupe hydration)."""

        def _read():
            cur = self._conn.execute(
                "SELECT client_id, session_id FROM client_sessions"
            )
            return cur.fetchall()

        rows = await self._run(_read)
        result: Dict[str, List[str]] = {}
        for row in rows:
            result.setdefault(row["client_id"], []).append(row["session_id"])
        return result

    # ------------------------------------------------------------------
    # Daily counters (shared budget primitives)
    # ------------------------------------------------------------------

    async def increment_daily_counter(
        self, name: str, limit: Optional[int] = None, day: Optional[str] = None
    ) -> Tuple[bool, int]:
        """Atomically increment today's counter for ``name``.

        When ``limit`` is given the increment only happens while the counter
        is below the limit. Returns (allowed, current_count_after_call).
        """
        day_key = day or _utc_day()

        def _write() -> Tuple[bool, int]:
            cur = self._conn.execute(
                "SELECT count FROM daily_counters WHERE name = ? AND day = ?",
                (name, day_key),
            )
            row = cur.fetchone()
            current = int(row["count"]) if row else 0
            if limit is not None and current >= limit:
                return (False, current)
            self._conn.execute(
                """
                INSERT INTO daily_counters (name, day, count) VALUES (?, ?, 1)
                ON CONFLICT(name, day) DO UPDATE SET count = count + 1
                """,
                (name, day_key),
            )
            self._conn.commit()
            return (True, current + 1)

        return await self._run(_write)

    async def get_daily_counter(self, name: str, day: Optional[str] = None) -> int:
        """Return today's counter value for ``name`` (0 when absent)."""
        day_key = day or _utc_day()

        def _read() -> int:
            cur = self._conn.execute(
                "SELECT count FROM daily_counters WHERE name = ? AND day = ?",
                (name, day_key),
            )
            row = cur.fetchone()
            return int(row["count"]) if row else 0

        return await self._run(_read)

    # ------------------------------------------------------------------
    # Rollups and retention
    # ------------------------------------------------------------------

    async def rollup_and_prune(
        self,
        snapshot_retention_days: int = SNAPSHOT_RETENTION_DAYS,
        session_retention_days: int = SESSION_RETENTION_DAYS,
        counter_retention_days: int = COUNTER_RETENTION_DAYS,
        now: Optional[float] = None,
    ) -> Dict[str, int]:
        """Compute hourly rollups for completed hours, then prune old rows.

        Returns counts of pruned rows per table for observability.
        """
        ts = now if now is not None else time.time()
        snapshot_cutoff = ts - snapshot_retention_days * 86400
        session_cutoff = ts - session_retention_days * 86400
        counter_cutoff_day = _utc_day(ts - counter_retention_days * 86400)
        current_hour = _hour_key(ts)

        def _work() -> Dict[str, int]:
            # Roll up all completed hours (everything before the current hour)
            # so aggregates survive snapshot pruning. INSERT OR REPLACE keeps
            # this idempotent across runs.
            cur = self._conn.execute(
                """
                SELECT
                    strftime('%Y-%m-%dT%H:00:00', received_at, 'unixepoch') AS hour,
                    COUNT(*) AS snapshots,
                    COUNT(DISTINCT CASE WHEN session_id != ''
                          THEN session_id ELSE id END) AS sessions,
                    SUM(turns_total) AS turns,
                    AVG(e2e_latency_median) AS avg_e2e_latency_median,
                    AVG(e2e_latency_p99) AS avg_e2e_latency_p99,
                    AVG(ttfa_median) AS avg_ttfa_median,
                    SUM(error_count) AS total_errors,
                    AVG(error_rate) AS avg_error_rate,
                    SUM(total_cost) AS total_cost
                FROM session_snapshots
                GROUP BY hour
                HAVING hour < ?
                """,
                (current_hour,),
            )
            for row in cur.fetchall():
                self._conn.execute(
                    """
                    INSERT OR REPLACE INTO rollups
                        (hour, snapshots, sessions, turns,
                         avg_e2e_latency_median, avg_e2e_latency_p99,
                         avg_ttfa_median, total_errors, avg_error_rate,
                         total_cost)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        row["hour"],
                        row["snapshots"],
                        row["sessions"],
                        row["turns"] or 0,
                        row["avg_e2e_latency_median"] or 0.0,
                        row["avg_e2e_latency_p99"] or 0.0,
                        row["avg_ttfa_median"] or 0.0,
                        row["total_errors"] or 0,
                        row["avg_error_rate"] or 0.0,
                        row["total_cost"] or 0.0,
                    ),
                )

            pruned = {}
            cur = self._conn.execute(
                "DELETE FROM session_snapshots WHERE received_at < ?",
                (snapshot_cutoff,),
            )
            pruned["session_snapshots"] = cur.rowcount
            cur = self._conn.execute(
                "DELETE FROM client_sessions WHERE first_seen < ?",
                (session_cutoff,),
            )
            pruned["client_sessions"] = cur.rowcount
            cur = self._conn.execute(
                "DELETE FROM daily_counters WHERE day < ?",
                (counter_cutoff_day,),
            )
            pruned["daily_counters"] = cur.rowcount
            self._conn.commit()
            return pruned

        pruned = await self._run(_work)
        total = sum(pruned.values())
        if total:
            logger.info(f"Telemetry store pruned {pruned}")
        return pruned

    async def get_rollups(self, limit: int = 168) -> List[Dict[str, Any]]:
        """Return the most recent hourly rollups, oldest first."""

        def _read():
            cur = self._conn.execute(
                "SELECT * FROM rollups ORDER BY hour DESC LIMIT ?", (int(limit),)
            )
            return [dict(r) for r in cur.fetchall()]

        rows = await self._run(_read)
        rows.reverse()
        return rows
