"""
Latency Test Harness - Storage Layer
=====================================

This module provides the persistence layer for the latency test harness,
supporting both development (file-based) and production (PostgreSQL) storage.

Storage Backends
---------------
1. **FileBasedLatencyStorage** - JSON files on disk
   - Best for: Development, simple deployments, debugging
   - Location: `server/data/latency_harness/`
   - Structure: Separate directories for suites/, runs/, baselines/

2. **PostgreSQLLatencyStorage** - Relational database
   - Best for: Production, high-volume testing, concurrent access
   - Requires: `asyncpg` library and PostgreSQL database
   - Tables: latency_test_suites, latency_test_runs, latency_test_results, latency_baselines

Data Model
----------
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  TestSuite      │     │    TestRun      │     │   TestResult    │
│  Definition     │────►│                 │────►│                 │
├─────────────────┤     ├─────────────────┤     ├─────────────────┤
│ id              │     │ id              │     │ id              │
│ name            │     │ suite_id        │     │ run_id          │
│ scenarios[]     │     │ client_id       │     │ config_id       │
│ parameter_space │     │ status          │     │ e2e_latency_ms  │
│ network_profiles│     │ results[]       │     │ llm_ttfb_ms     │
└─────────────────┘     └─────────────────┘     │ tts_ttfb_ms     │
                                                └─────────────────┘

┌─────────────────┐
│ Performance     │
│ Baseline        │
├─────────────────┤
│ id              │
│ run_id          │  ◄── Created from a completed TestRun
│ config_metrics  │
│ is_active       │
└─────────────────┘
```

Usage Examples
-------------
```python
# File-based storage (development)
from latency_harness.storage import create_latency_storage

storage = create_latency_storage(storage_type="file")
await storage.initialize()

# PostgreSQL storage (production)
storage = create_latency_storage(
    storage_type="postgresql",
    connection_string="postgresql://user:pass@localhost/unamentis"
)
await storage.connect()
await storage.initialize_schema()

# Save a test run
await storage.save_run(run)

# Query results
results = await storage.get_results(run_id="run_123", limit=100)

# Create baseline from run
baseline = PerformanceBaseline(
    id="baseline_v1",
    name="Production Baseline",
    run_id="run_123",
    ...
)
await storage.save_baseline(baseline)
```

Environment Variables
--------------------
- `LATENCY_STORAGE_TYPE`: "file" or "postgresql" (default: "file")
- `LATENCY_DATABASE_URL`: PostgreSQL connection string
- `DATABASE_URL`: Fallback connection string

Thread Safety
------------
- FileBasedLatencyStorage: Uses in-memory caches, safe for single-process
- PostgreSQLLatencyStorage: Connection pool handles concurrency

See Also
--------
- `orchestrator.py`: Uses storage for persistence
- `models.py`: Data model definitions
- `docs/LATENCY_TEST_HARNESS_GUIDE.md`: Complete usage guide
"""

import json
import os
import uuid
from abc import ABC, abstractmethod
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
import logging

from .models import (
    TestSuiteDefinition,
    TestRun,
    TestResult,
    RunStatus,
    NetworkProfile,
    PerformanceBaseline,
)

logger = logging.getLogger(__name__)

# Try to import asyncpg for PostgreSQL support
try:
    import asyncpg
    HAS_ASYNCPG = True
except ImportError:
    HAS_ASYNCPG = False


class LatencyHarnessStorage(ABC):
    """Abstract base class for latency harness storage."""

    # =========================================================================
    # Test Suite Operations
    # =========================================================================

    @abstractmethod
    async def list_suites(self) -> List[TestSuiteDefinition]:
        """List all test suites."""
        pass

    @abstractmethod
    async def get_suite(self, suite_id: str) -> Optional[TestSuiteDefinition]:
        """Get a specific test suite by ID."""
        pass

    @abstractmethod
    async def save_suite(self, suite: TestSuiteDefinition) -> str:
        """Save a test suite. Returns the suite ID."""
        pass

    @abstractmethod
    async def delete_suite(self, suite_id: str) -> bool:
        """Delete a test suite. Returns True if deleted."""
        pass

    # =========================================================================
    # Test Run Operations
    # =========================================================================

    @abstractmethod
    async def list_runs(
        self,
        status: Optional[RunStatus] = None,
        suite_id: Optional[str] = None,
        limit: int = 50,
        offset: int = 0
    ) -> Tuple[List[TestRun], int]:
        """List test runs with optional filtering."""
        pass

    @abstractmethod
    async def get_run(self, run_id: str) -> Optional[TestRun]:
        """Get a specific test run by ID."""
        pass

    @abstractmethod
    async def save_run(self, run: TestRun) -> str:
        """Save a test run. Returns the run ID."""
        pass

    @abstractmethod
    async def update_run_status(
        self,
        run_id: str,
        status: RunStatus,
        completed_configurations: Optional[int] = None,
        completed_at: Optional[datetime] = None
    ) -> bool:
        """Update run status. Returns True if updated."""
        pass

    @abstractmethod
    async def delete_run(self, run_id: str) -> bool:
        """Delete a test run. Returns True if deleted."""
        pass

    # =========================================================================
    # Test Result Operations
    # =========================================================================

    @abstractmethod
    async def save_result(self, run_id: str, result: TestResult) -> str:
        """Save a test result. Returns result ID."""
        pass

    @abstractmethod
    async def get_results(
        self,
        run_id: str,
        config_id: Optional[str] = None,
        limit: int = 1000
    ) -> List[TestResult]:
        """Get results for a run with optional config filtering."""
        pass

    # =========================================================================
    # Baseline Operations
    # =========================================================================

    @abstractmethod
    async def list_baselines(self) -> List[PerformanceBaseline]:
        """List all performance baselines."""
        pass

    @abstractmethod
    async def get_baseline(self, baseline_id: str) -> Optional[PerformanceBaseline]:
        """Get a specific baseline by ID."""
        pass

    @abstractmethod
    async def save_baseline(self, baseline: PerformanceBaseline) -> str:
        """Save a baseline. Returns the baseline ID."""
        pass

    @abstractmethod
    async def delete_baseline(self, baseline_id: str) -> bool:
        """Delete a baseline. Returns True if deleted."""
        pass

    @abstractmethod
    async def get_active_baseline(self) -> Optional[PerformanceBaseline]:
        """Get the currently active baseline."""
        pass


class FileBasedLatencyStorage(LatencyHarnessStorage):
    """
    File-based storage for development and simple deployments.
    Stores data as JSON files in a directory structure.
    """

    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.suites_dir = data_dir / "suites"
        self.runs_dir = data_dir / "runs"
        self.baselines_dir = data_dir / "baselines"

        # In-memory caches
        self._suites: Dict[str, TestSuiteDefinition] = {}
        self._runs: Dict[str, TestRun] = {}
        self._baselines: Dict[str, PerformanceBaseline] = {}

    async def initialize(self):
        """Initialize storage directories and load cached data."""
        # Create directories
        for dir_path in [self.suites_dir, self.runs_dir, self.baselines_dir]:
            dir_path.mkdir(parents=True, exist_ok=True)

        # Load existing data
        await self._load_suites()
        await self._load_runs()
        await self._load_baselines()

        logger.info(f"Loaded {len(self._suites)} suites, {len(self._runs)} runs, "
                   f"{len(self._baselines)} baselines from {self.data_dir}")

    async def _load_suites(self):
        """Load test suites from disk."""
        for suite_file in self.suites_dir.glob("*.json"):
            try:
                with open(suite_file, 'r') as f:
                    data = json.load(f)
                suite = TestSuiteDefinition.from_dict(data)
                self._suites[suite.id] = suite
            except Exception as e:
                logger.error(f"Failed to load suite {suite_file}: {e}")

    async def _load_runs(self):
        """Load test runs from disk."""
        for run_file in self.runs_dir.glob("*.json"):
            try:
                with open(run_file, 'r') as f:
                    data = json.load(f)
                run = TestRun.from_dict(data)
                self._runs[run.id] = run
            except Exception as e:
                logger.error(f"Failed to load run {run_file}: {e}")

    async def _load_baselines(self):
        """Load baselines from disk."""
        for baseline_file in self.baselines_dir.glob("*.json"):
            try:
                with open(baseline_file, 'r') as f:
                    data = json.load(f)
                baseline = PerformanceBaseline.from_dict(data)
                self._baselines[baseline.id] = baseline
            except Exception as e:
                logger.error(f"Failed to load baseline {baseline_file}: {e}")

    # =========================================================================
    # Test Suite Operations
    # =========================================================================

    async def list_suites(self) -> List[TestSuiteDefinition]:
        return list(self._suites.values())

    async def get_suite(self, suite_id: str) -> Optional[TestSuiteDefinition]:
        return self._suites.get(suite_id)

    async def save_suite(self, suite: TestSuiteDefinition) -> str:
        self._suites[suite.id] = suite

        # Write to disk
        suite_file = self.suites_dir / f"{suite.id}.json"
        with open(suite_file, 'w') as f:
            json.dump(suite.to_dict(), f, indent=2, default=str)

        return suite.id

    async def delete_suite(self, suite_id: str) -> bool:
        if suite_id not in self._suites:
            return False

        del self._suites[suite_id]
        suite_file = self.suites_dir / f"{suite_id}.json"
        if suite_file.exists():
            suite_file.unlink()
        return True

    # =========================================================================
    # Test Run Operations
    # =========================================================================

    async def list_runs(
        self,
        status: Optional[RunStatus] = None,
        suite_id: Optional[str] = None,
        limit: int = 50,
        offset: int = 0
    ) -> Tuple[List[TestRun], int]:
        runs = list(self._runs.values())

        # Apply filters
        if status:
            runs = [r for r in runs if r.status == status]
        if suite_id:
            runs = [r for r in runs if r.suite_id == suite_id]

        # Sort by start time descending
        runs.sort(key=lambda r: r.started_at or datetime.min, reverse=True)

        total = len(runs)
        runs = runs[offset:offset + limit]

        return runs, total

    async def get_run(self, run_id: str) -> Optional[TestRun]:
        return self._runs.get(run_id)

    async def save_run(self, run: TestRun) -> str:
        self._runs[run.id] = run

        # Write to disk
        run_file = self.runs_dir / f"{run.id}.json"
        with open(run_file, 'w') as f:
            json.dump(run.to_dict(), f, indent=2, default=str)

        return run.id

    async def update_run_status(
        self,
        run_id: str,
        status: RunStatus,
        completed_configurations: Optional[int] = None,
        completed_at: Optional[datetime] = None
    ) -> bool:
        run = self._runs.get(run_id)
        if not run:
            return False

        run.status = status
        if completed_configurations is not None:
            run.completed_configurations = completed_configurations
        if completed_at is not None:
            run.completed_at = completed_at

        await self.save_run(run)
        return True

    async def delete_run(self, run_id: str) -> bool:
        if run_id not in self._runs:
            return False

        del self._runs[run_id]

        run_file = self.runs_dir / f"{run_id}.json"
        if run_file.exists():
            run_file.unlink()

        # Also delete results directory if exists
        results_dir = self.runs_dir / run_id
        if results_dir.exists():
            import shutil
            shutil.rmtree(results_dir)

        return True

    # =========================================================================
    # Test Result Operations
    # =========================================================================

    async def save_result(self, run_id: str, result: TestResult) -> str:
        # Add result to run
        run = self._runs.get(run_id)
        if run:
            run.results.append(result)
            await self.save_run(run)

        return result.id

    async def get_results(
        self,
        run_id: str,
        config_id: Optional[str] = None,
        limit: int = 1000
    ) -> List[TestResult]:
        run = self._runs.get(run_id)
        if not run:
            return []

        results = run.results
        if config_id:
            results = [r for r in results if r.config_id == config_id]

        return results[:limit]

    # =========================================================================
    # Baseline Operations
    # =========================================================================

    async def list_baselines(self) -> List[PerformanceBaseline]:
        return list(self._baselines.values())

    async def get_baseline(self, baseline_id: str) -> Optional[PerformanceBaseline]:
        return self._baselines.get(baseline_id)

    async def save_baseline(self, baseline: PerformanceBaseline) -> str:
        self._baselines[baseline.id] = baseline

        # Write to disk
        baseline_file = self.baselines_dir / f"{baseline.id}.json"
        with open(baseline_file, 'w') as f:
            json.dump(baseline.to_dict(), f, indent=2, default=str)

        return baseline.id

    async def delete_baseline(self, baseline_id: str) -> bool:
        if baseline_id not in self._baselines:
            return False

        del self._baselines[baseline_id]
        baseline_file = self.baselines_dir / f"{baseline_id}.json"
        if baseline_file.exists():
            baseline_file.unlink()
        return True

    async def get_active_baseline(self) -> Optional[PerformanceBaseline]:
        """Get the baseline marked as active, or the most recent one."""
        baselines = list(self._baselines.values())
        if not baselines:
            return None

        # Find active baseline
        for baseline in baselines:
            if baseline.is_active:
                return baseline

        # Return most recent
        baselines.sort(key=lambda b: b.created_at or datetime.min, reverse=True)
        return baselines[0]


class PostgreSQLLatencyStorage(LatencyHarnessStorage):
    """
    PostgreSQL storage for production deployments.
    Provides efficient queries and scalable storage.
    """

    def __init__(self, connection_string: str):
        self.connection_string = connection_string
        self.pool: Optional[asyncpg.Pool] = None

    async def connect(self):
        """Initialize the connection pool."""
        if not HAS_ASYNCPG:
            raise RuntimeError("asyncpg is required for PostgreSQL storage")

        self.pool = await asyncpg.create_pool(
            self.connection_string,
            min_size=2,
            max_size=10
        )
        logger.info("Connected to PostgreSQL for latency harness storage")

    async def close(self):
        """Close the connection pool."""
        if self.pool:
            await self.pool.close()

    async def initialize_schema(self):
        """Create tables if they don't exist."""
        async with self.pool.acquire() as conn:
            await conn.execute(LATENCY_HARNESS_SCHEMA)
            logger.info("Latency harness schema initialized")

    # =========================================================================
    # Test Suite Operations
    # =========================================================================

    async def list_suites(self) -> List[TestSuiteDefinition]:
        async with self.pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT id, name, description, definition_json, created_at, updated_at
                FROM latency_test_suites
                ORDER BY name
            """)

            return [
                TestSuiteDefinition.from_dict(json.loads(row['definition_json']))
                for row in rows
            ]

    async def get_suite(self, suite_id: str) -> Optional[TestSuiteDefinition]:
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow("""
                SELECT definition_json FROM latency_test_suites WHERE id = $1
            """, suite_id)

            if not row:
                return None

            return TestSuiteDefinition.from_dict(json.loads(row['definition_json']))

    async def save_suite(self, suite: TestSuiteDefinition) -> str:
        async with self.pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO latency_test_suites (id, name, description, definition_json, updated_at)
                VALUES ($1, $2, $3, $4, NOW())
                ON CONFLICT (id) DO UPDATE SET
                    name = EXCLUDED.name,
                    description = EXCLUDED.description,
                    definition_json = EXCLUDED.definition_json,
                    updated_at = NOW()
            """, suite.id, suite.name, suite.description, json.dumps(suite.to_dict(), default=str))

            return suite.id

    async def delete_suite(self, suite_id: str) -> bool:
        async with self.pool.acquire() as conn:
            result = await conn.execute("""
                DELETE FROM latency_test_suites WHERE id = $1
            """, suite_id)
            return "DELETE 1" in result

    # =========================================================================
    # Test Run Operations
    # =========================================================================

    async def list_runs(
        self,
        status: Optional[RunStatus] = None,
        suite_id: Optional[str] = None,
        limit: int = 50,
        offset: int = 0
    ) -> Tuple[List[TestRun], int]:
        async with self.pool.acquire() as conn:
            conditions = []
            params = []
            param_idx = 1

            if status:
                conditions.append(f"status = ${param_idx}")
                params.append(status.value)
                param_idx += 1

            if suite_id:
                conditions.append(f"suite_id = ${param_idx}")
                params.append(suite_id)
                param_idx += 1

            where_clause = " AND ".join(conditions) if conditions else "TRUE"

            # Get total count
            count_query = f"SELECT COUNT(*) FROM latency_test_runs WHERE {where_clause}"
            total = await conn.fetchval(count_query, *params)

            # Get runs
            query = f"""
                SELECT id, suite_id, suite_name, client_id, client_type,
                       status, total_configurations, completed_configurations,
                       started_at, completed_at, run_json
                FROM latency_test_runs
                WHERE {where_clause}
                ORDER BY started_at DESC
                LIMIT ${param_idx} OFFSET ${param_idx + 1}
            """
            params.extend([limit, offset])

            rows = await conn.fetch(query, *params)

            runs = []
            for row in rows:
                run = TestRun.from_dict(json.loads(row['run_json']))
                runs.append(run)

            return runs, total

    async def get_run(self, run_id: str) -> Optional[TestRun]:
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow("""
                SELECT run_json FROM latency_test_runs WHERE id = $1
            """, run_id)

            if not row:
                return None

            return TestRun.from_dict(json.loads(row['run_json']))

    async def save_run(self, run: TestRun) -> str:
        async with self.pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO latency_test_runs (
                    id, suite_id, suite_name, client_id, client_type,
                    status, total_configurations, completed_configurations,
                    started_at, completed_at, run_json
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                ON CONFLICT (id) DO UPDATE SET
                    status = EXCLUDED.status,
                    completed_configurations = EXCLUDED.completed_configurations,
                    completed_at = EXCLUDED.completed_at,
                    run_json = EXCLUDED.run_json
            """,
                run.id, run.suite_id, run.suite_name, run.client_id,
                run.client_type.value if run.client_type else None,
                run.status.value, run.total_configurations, run.completed_configurations,
                run.started_at, run.completed_at,
                json.dumps(run.to_dict(), default=str)
            )

            return run.id

    async def update_run_status(
        self,
        run_id: str,
        status: RunStatus,
        completed_configurations: Optional[int] = None,
        completed_at: Optional[datetime] = None
    ) -> bool:
        async with self.pool.acquire() as conn:
            # First get the current run
            row = await conn.fetchrow("""
                SELECT run_json FROM latency_test_runs WHERE id = $1
            """, run_id)

            if not row:
                return False

            run = TestRun.from_dict(json.loads(row['run_json']))
            run.status = status
            if completed_configurations is not None:
                run.completed_configurations = completed_configurations
            if completed_at is not None:
                run.completed_at = completed_at

            await self.save_run(run)
            return True

    async def delete_run(self, run_id: str) -> bool:
        async with self.pool.acquire() as conn:
            # Delete results first (cascade would handle this if FK is set)
            await conn.execute("""
                DELETE FROM latency_test_results WHERE run_id = $1
            """, run_id)

            result = await conn.execute("""
                DELETE FROM latency_test_runs WHERE id = $1
            """, run_id)
            return "DELETE 1" in result

    # =========================================================================
    # Test Result Operations
    # =========================================================================

    async def save_result(self, run_id: str, result: TestResult) -> str:
        async with self.pool.acquire() as conn:
            result_id = result.id or str(uuid.uuid4())

            await conn.execute("""
                INSERT INTO latency_test_results (
                    id, run_id, config_id, scenario_name, repetition,
                    timestamp, stt_latency_ms, llm_ttfb_ms, llm_completion_ms,
                    tts_ttfb_ms, tts_completion_ms, e2e_latency_ms,
                    network_profile, is_success, errors, result_json
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
            """,
                result_id, run_id, result.config_id, result.scenario_name,
                result.repetition, result.timestamp,
                result.stt_latency_ms, result.llm_ttfb_ms, result.llm_completion_ms,
                result.tts_ttfb_ms, result.tts_completion_ms, result.e2e_latency_ms,
                result.network_profile.value, result.is_success,
                result.errors, json.dumps(result.to_dict(), default=str)
            )

            return result_id

    async def get_results(
        self,
        run_id: str,
        config_id: Optional[str] = None,
        limit: int = 1000
    ) -> List[TestResult]:
        async with self.pool.acquire() as conn:
            if config_id:
                rows = await conn.fetch("""
                    SELECT result_json FROM latency_test_results
                    WHERE run_id = $1 AND config_id = $2
                    ORDER BY timestamp
                    LIMIT $3
                """, run_id, config_id, limit)
            else:
                rows = await conn.fetch("""
                    SELECT result_json FROM latency_test_results
                    WHERE run_id = $1
                    ORDER BY timestamp
                    LIMIT $2
                """, run_id, limit)

            return [
                TestResult.from_dict(json.loads(row['result_json']))
                for row in rows
            ]

    # =========================================================================
    # Baseline Operations
    # =========================================================================

    async def list_baselines(self) -> List[PerformanceBaseline]:
        async with self.pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT baseline_json FROM latency_baselines
                ORDER BY created_at DESC
            """)

            return [
                PerformanceBaseline.from_dict(json.loads(row['baseline_json']))
                for row in rows
            ]

    async def get_baseline(self, baseline_id: str) -> Optional[PerformanceBaseline]:
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow("""
                SELECT baseline_json FROM latency_baselines WHERE id = $1
            """, baseline_id)

            if not row:
                return None

            return PerformanceBaseline.from_dict(json.loads(row['baseline_json']))

    async def save_baseline(self, baseline: PerformanceBaseline) -> str:
        async with self.pool.acquire() as conn:
            # If this baseline is active, deactivate others
            if baseline.is_active:
                await conn.execute("""
                    UPDATE latency_baselines SET is_active = FALSE
                """)

            await conn.execute("""
                INSERT INTO latency_baselines (
                    id, name, description, run_id, is_active, created_at, baseline_json
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (id) DO UPDATE SET
                    name = EXCLUDED.name,
                    description = EXCLUDED.description,
                    is_active = EXCLUDED.is_active,
                    baseline_json = EXCLUDED.baseline_json
            """,
                baseline.id, baseline.name, baseline.description,
                baseline.run_id, baseline.is_active, baseline.created_at,
                json.dumps(baseline.to_dict(), default=str)
            )

            return baseline.id

    async def delete_baseline(self, baseline_id: str) -> bool:
        async with self.pool.acquire() as conn:
            result = await conn.execute("""
                DELETE FROM latency_baselines WHERE id = $1
            """, baseline_id)
            return "DELETE 1" in result

    async def get_active_baseline(self) -> Optional[PerformanceBaseline]:
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow("""
                SELECT baseline_json FROM latency_baselines
                WHERE is_active = TRUE
                LIMIT 1
            """)

            if not row:
                # Fall back to most recent
                row = await conn.fetchrow("""
                    SELECT baseline_json FROM latency_baselines
                    ORDER BY created_at DESC
                    LIMIT 1
                """)

            if not row:
                return None

            return PerformanceBaseline.from_dict(json.loads(row['baseline_json']))


# PostgreSQL Schema
LATENCY_HARNESS_SCHEMA = """
-- Test Suites
CREATE TABLE IF NOT EXISTS latency_test_suites (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    definition_json JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Test Runs
CREATE TABLE IF NOT EXISTS latency_test_runs (
    id VARCHAR(255) PRIMARY KEY,
    suite_id VARCHAR(255) NOT NULL,
    suite_name VARCHAR(255) NOT NULL,
    client_id VARCHAR(255),
    client_type VARCHAR(50),
    status VARCHAR(50) NOT NULL,
    total_configurations INTEGER NOT NULL,
    completed_configurations INTEGER DEFAULT 0,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,
    run_json JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_latency_runs_status ON latency_test_runs(status);
CREATE INDEX IF NOT EXISTS idx_latency_runs_suite ON latency_test_runs(suite_id);
CREATE INDEX IF NOT EXISTS idx_latency_runs_started ON latency_test_runs(started_at DESC);

-- Test Results
CREATE TABLE IF NOT EXISTS latency_test_results (
    id VARCHAR(255) PRIMARY KEY,
    run_id VARCHAR(255) NOT NULL REFERENCES latency_test_runs(id) ON DELETE CASCADE,
    config_id VARCHAR(255) NOT NULL,
    scenario_name VARCHAR(255),
    repetition INTEGER,
    timestamp TIMESTAMP NOT NULL,
    stt_latency_ms REAL,
    llm_ttfb_ms REAL,
    llm_completion_ms REAL,
    tts_ttfb_ms REAL,
    tts_completion_ms REAL,
    e2e_latency_ms REAL,
    network_profile VARCHAR(50),
    is_success BOOLEAN,
    errors TEXT[],
    result_json JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_latency_results_run ON latency_test_results(run_id);
CREATE INDEX IF NOT EXISTS idx_latency_results_config ON latency_test_results(config_id);
CREATE INDEX IF NOT EXISTS idx_latency_results_timestamp ON latency_test_results(timestamp);

-- Performance Baselines
CREATE TABLE IF NOT EXISTS latency_baselines (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    run_id VARCHAR(255) REFERENCES latency_test_runs(id),
    is_active BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    baseline_json JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_latency_baselines_active ON latency_baselines(is_active);
"""


def create_latency_storage(
    storage_type: str = "file",
    data_dir: Optional[Path] = None,
    connection_string: Optional[str] = None
) -> LatencyHarnessStorage:
    """
    Factory function to create the appropriate storage backend.

    Args:
        storage_type: "file" or "postgresql"
        data_dir: Directory for file-based storage
        connection_string: PostgreSQL connection string for DB storage

    Returns:
        LatencyHarnessStorage instance
    """
    if storage_type == "postgresql":
        if not connection_string:
            connection_string = os.environ.get(
                "LATENCY_DATABASE_URL",
                os.environ.get("DATABASE_URL", "postgresql://localhost/unamentis")
            )
        return PostgreSQLLatencyStorage(connection_string)
    else:
        if not data_dir:
            data_dir = Path(__file__).parent.parent / "data" / "latency_harness"
        return FileBasedLatencyStorage(data_dir)
