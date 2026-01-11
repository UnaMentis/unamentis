"""
UnaMentis - Mass Automated Testing Orchestrator
================================================

Orchestrates mass automated latency testing across multiple web clients.
Uses Playwright to spawn browser instances that execute test hooks.

DESIGN PRINCIPLE
----------------
Use programmatic test hooks (not UI automation). The hooks trigger the same
code paths as button clicks but are called efficiently via JavaScript.

ARCHITECTURE
------------
```
┌────────────────────────────────────────────┐
│  MassTestOrchestrator                       │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  Playwright Browser Pool            │   │
│  │  ┌─────────┐ ┌─────────┐           │   │
│  │  │Browser1 │ │Browser2 │ ...       │   │
│  │  └────┬────┘ └────┬────┘           │   │
│  │       │           │                 │   │
│  │  Each browser calls test hooks:     │   │
│  │  - startSession()                   │   │
│  │  - sendUtterance()                  │   │
│  │  - endSession()                     │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  Metrics collected via normal telemetry    │
│  and aggregated into TestRun               │
└────────────────────────────────────────────┘
```

USAGE
-----
```python
from latency_harness.test_orchestrator import MassTestOrchestrator

orchestrator = MassTestOrchestrator()
run_id = await orchestrator.start_mass_test(
    total_sessions=500,
    web_clients=4,
    utterances=["Hello", "Explain history", "What is science?"]
)

# Check progress
progress = await orchestrator.get_progress(run_id)
print(f"Completed: {progress['sessionsCompleted']}/{progress['sessionsTotal']}")

# Stop if needed
await orchestrator.stop_test(run_id)
```

SEE ALSO
--------
- server/web/src/lib/test-hooks.ts: Web client test hooks
- orchestrator.py: Original latency harness orchestrator
"""

import asyncio
import logging
import uuid
from datetime import datetime
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any
from enum import Enum
import json

from latency_harness.system_monitor import (
    SystemMonitor,
    ResourceSnapshot,
    ResourceSummary,
)

logger = logging.getLogger(__name__)


class MassTestStatus(str, Enum):
    """Status of a mass test run."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    STOPPED = "stopped"
    FAILED = "failed"


@dataclass
class ProviderConfig:
    """Provider configuration for testing."""
    stt: str = "deepgram"
    llm: str = "anthropic"
    llm_model: str = "claude-3-5-haiku-20241022"
    tts: str = "chatterbox"
    tts_voice: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "stt": self.stt,
            "llm": self.llm,
            "llmModel": self.llm_model,
            "tts": self.tts,
            "ttsVoice": self.tts_voice,
        }


@dataclass
class SessionResult:
    """Result from a single test session."""
    session_id: str
    client_index: int
    turns_completed: int
    latency_p50_ms: float
    latency_p95_ms: float
    avg_latency_ms: float
    success_rate: float
    duration_ms: float
    timestamp: str
    errors: List[str] = field(default_factory=list)


@dataclass
class MassTestProgress:
    """Progress of a mass test run."""
    run_id: str
    status: MassTestStatus
    sessions_completed: int
    sessions_total: int
    active_clients: int
    elapsed_seconds: float
    estimated_remaining_seconds: float
    latency_stats: Dict[str, float] = field(default_factory=dict)
    errors: List[str] = field(default_factory=list)
    # System resource metrics
    system_resources: Optional[Dict[str, Any]] = None


@dataclass
class MassTestRun:
    """Represents a mass test run."""
    id: str
    status: MassTestStatus
    started_at: datetime
    completed_at: Optional[datetime] = None
    total_sessions: int = 0
    completed_sessions: int = 0
    web_clients: int = 0
    provider_config: Optional[ProviderConfig] = None
    utterances: List[str] = field(default_factory=list)
    session_results: List[SessionResult] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    _stop_requested: bool = False
    # System resource monitoring
    _system_monitor: Optional[SystemMonitor] = field(default=None, repr=False)
    resource_summary: Optional[ResourceSummary] = None


class MassTestOrchestrator:
    """
    Orchestrates mass automated testing across multiple web clients.

    Uses Playwright to spawn multiple browser instances, each running
    test hooks that exercise the full voice pipeline (LLM + TTS).
    """

    def __init__(
        self,
        app_url: str = "http://localhost:3000",
        management_url: str = "http://localhost:8766",
    ):
        self.app_url = app_url
        self.management_url = management_url
        self.active_runs: Dict[str, MassTestRun] = {}
        self.completed_runs: Dict[str, MassTestRun] = {}
        self._playwright = None
        self._browser = None

    async def _ensure_playwright(self):
        """Initialize Playwright if not already done."""
        if self._playwright is None:
            try:
                from playwright.async_api import async_playwright
                self._playwright = await async_playwright().start()
                self._browser = await self._playwright.chromium.launch(headless=True)
                logger.info("Playwright browser initialized")
            except ImportError:
                raise ImportError(
                    "Playwright not installed. Run: pip install playwright && playwright install chromium"
                )

    async def start_mass_test(
        self,
        total_sessions: int = 100,
        web_clients: int = 4,
        provider_config: Optional[ProviderConfig] = None,
        utterances: Optional[List[str]] = None,
        turns_per_session: int = 3,
    ) -> str:
        """
        Start a mass automated test run.

        Args:
            total_sessions: Total number of sessions to run
            web_clients: Number of parallel browser instances
            provider_config: LLM/TTS provider configuration
            utterances: List of test utterances to use
            turns_per_session: Number of turns per session

        Returns:
            Run ID for tracking progress
        """
        await self._ensure_playwright()

        run_id = f"mass_run_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"

        if utterances is None:
            utterances = [
                "Hello, how are you today?",
                "Can you explain photosynthesis?",
                "What is the capital of France?",
                "Tell me about ancient history",
                "How does electricity work?",
            ]

        if provider_config is None:
            provider_config = ProviderConfig()

        # Create system monitor for this run
        monitor = SystemMonitor(
            sample_interval_ms=500,  # Sample every 500ms
            run_id=run_id,
        )

        run = MassTestRun(
            id=run_id,
            status=MassTestStatus.RUNNING,
            started_at=datetime.now(),
            total_sessions=total_sessions,
            web_clients=web_clients,
            provider_config=provider_config,
            utterances=utterances,
            _system_monitor=monitor,
        )

        self.active_runs[run_id] = run

        # Start system monitoring
        await monitor.start()

        # Start execution in background
        asyncio.create_task(
            self._execute_mass_test(run, turns_per_session)
        )

        logger.info(
            f"Started mass test run {run_id}: "
            f"{total_sessions} sessions across {web_clients} clients"
        )

        return run_id

    async def _execute_mass_test(self, run: MassTestRun, turns_per_session: int):
        """Execute the mass test run."""
        try:
            # Calculate sessions per client
            sessions_per_client = run.total_sessions // run.web_clients
            remainder = run.total_sessions % run.web_clients

            # Create browser contexts (isolated sessions)
            contexts = []
            pages = []

            for i in range(run.web_clients):
                context = await self._browser.new_context()
                page = await context.new_page()
                await page.goto(self.app_url)
                # Wait for hooks to be available
                await page.wait_for_function(
                    "window.__TEST_HOOKS__ !== undefined",
                    timeout=10000
                )
                contexts.append(context)
                pages.append(page)

            logger.info(f"Spawned {len(pages)} browser clients")

            # Distribute work across clients
            async def run_client_sessions(
                page, client_index: int, num_sessions: int
            ):
                """Run sessions on a single client."""
                for session_idx in range(num_sessions):
                    if run._stop_requested:
                        break

                    try:
                        result = await self._run_single_session(
                            page,
                            client_index,
                            run.provider_config,
                            run.utterances,
                            turns_per_session,
                        )
                        run.session_results.append(result)
                        run.completed_sessions += 1

                        logger.debug(
                            f"Client {client_index}: Session {session_idx + 1}/{num_sessions} "
                            f"completed (p50: {result.latency_p50_ms:.1f}ms)"
                        )

                    except Exception as e:
                        error_msg = f"Client {client_index} session {session_idx}: {e}"
                        run.errors.append(error_msg)
                        logger.error(error_msg)
                        run.completed_sessions += 1  # Count as completed (failed)

            # Run clients in parallel
            tasks = []
            for i, page in enumerate(pages):
                num = sessions_per_client + (1 if i < remainder else 0)
                tasks.append(run_client_sessions(page, i, num))

            await asyncio.gather(*tasks)

            # Cleanup
            for context in contexts:
                await context.close()

            # Stop system monitoring and get summary
            if run._system_monitor:
                run.resource_summary = await run._system_monitor.stop()
                logger.info(
                    f"Resource summary - Peak CPU: {run.resource_summary.peak_cpu_percent}%, "
                    f"Peak Memory: {run.resource_summary.peak_memory_used_mb}MB, "
                    f"Thermal throttle time: {run.resource_summary.thermal_throttle_seconds}s"
                )

            # Update run status
            run.status = (
                MassTestStatus.STOPPED if run._stop_requested
                else MassTestStatus.COMPLETED
            )
            run.completed_at = datetime.now()

            # Move to completed
            if run.id in self.active_runs:
                del self.active_runs[run.id]
            self.completed_runs[run.id] = run

            logger.info(
                f"Mass test {run.id} completed: "
                f"{run.completed_sessions}/{run.total_sessions} sessions"
            )

        except Exception as e:
            # Stop system monitoring on failure too
            if run._system_monitor:
                try:
                    run.resource_summary = await run._system_monitor.stop()
                except Exception:
                    pass

            run.status = MassTestStatus.FAILED
            run.errors.append(str(e))
            run.completed_at = datetime.now()
            logger.error(f"Mass test {run.id} failed: {e}")

            if run.id in self.active_runs:
                del self.active_runs[run.id]
            self.completed_runs[run.id] = run

    async def _run_single_session(
        self,
        page,
        client_index: int,
        config: ProviderConfig,
        utterances: List[str],
        turns: int,
    ) -> SessionResult:
        """Run a single test session on a browser page."""
        import random

        # Use a subset of utterances for variety
        session_utterances = random.sample(utterances, min(turns, len(utterances)))

        # Execute session via test hooks
        result = await page.evaluate(
            """
            async ([config, utterances]) => {
                const hooks = window.__TEST_HOOKS__;

                try {
                    // Start session
                    await hooks.startSession(config);

                    // Send utterances
                    for (const text of utterances) {
                        await hooks.sendUtterance(text);
                    }

                    // End session and get metrics
                    const metrics = await hooks.endSession();

                    return {
                        success: true,
                        sessionId: metrics.sessionId,
                        turnsCompleted: metrics.turnsCompleted,
                        latencyP50Ms: metrics.latencyP50Ms,
                        latencyP95Ms: metrics.latencyP95Ms,
                        avgLatencyMs: metrics.avgLatencyMs,
                        successRate: metrics.successRate,
                        durationMs: metrics.totalDurationMs,
                        timestamp: new Date().toISOString(),
                        errors: [],
                    };
                } catch (e) {
                    return {
                        success: false,
                        sessionId: '',
                        turnsCompleted: 0,
                        latencyP50Ms: 0,
                        latencyP95Ms: 0,
                        avgLatencyMs: 0,
                        successRate: 0,
                        durationMs: 0,
                        timestamp: new Date().toISOString(),
                        errors: [e.message || String(e)],
                    };
                }
            }
            """,
            [config.to_dict(), session_utterances]
        )

        return SessionResult(
            session_id=result["sessionId"],
            client_index=client_index,
            turns_completed=result["turnsCompleted"],
            latency_p50_ms=result["latencyP50Ms"],
            latency_p95_ms=result["latencyP95Ms"],
            avg_latency_ms=result["avgLatencyMs"],
            success_rate=result["successRate"],
            duration_ms=result["durationMs"],
            timestamp=result["timestamp"],
            errors=result.get("errors", []),
        )

    async def get_progress(self, run_id: str) -> MassTestProgress:
        """Get current progress of a mass test run."""
        run = self.active_runs.get(run_id) or self.completed_runs.get(run_id)

        if not run:
            raise ValueError(f"Run not found: {run_id}")

        elapsed = (datetime.now() - run.started_at).total_seconds()

        # Estimate remaining time
        if run.completed_sessions > 0 and run.status == MassTestStatus.RUNNING:
            rate = run.completed_sessions / elapsed
            remaining = (run.total_sessions - run.completed_sessions) / rate
        else:
            remaining = 0

        # Calculate latency stats from completed sessions
        successful = [r for r in run.session_results if r.success_rate > 0]
        if successful:
            p50_values = sorted([r.latency_p50_ms for r in successful])
            avg_latency = sum([r.avg_latency_ms for r in successful]) / len(successful)
            idx = int(len(p50_values) * 0.5)
            p50 = p50_values[idx] if p50_values else 0
            idx95 = int(len(p50_values) * 0.95)
            p95 = p50_values[min(idx95, len(p50_values) - 1)] if p50_values else 0
        else:
            p50 = p95 = avg_latency = 0

        # Get current system resources
        system_resources = None
        if run.status == MassTestStatus.RUNNING and run._system_monitor:
            try:
                snapshot = await run._system_monitor.get_current()
                system_resources = snapshot.to_dict()
            except Exception as e:
                logger.debug(f"Failed to get resource snapshot: {e}")
        elif run.resource_summary:
            # For completed runs, return the summary
            system_resources = run.resource_summary.to_dict()

        return MassTestProgress(
            run_id=run.id,
            status=run.status,
            sessions_completed=run.completed_sessions,
            sessions_total=run.total_sessions,
            active_clients=run.web_clients if run.status == MassTestStatus.RUNNING else 0,
            elapsed_seconds=elapsed,
            estimated_remaining_seconds=remaining,
            latency_stats={
                "e2e_p50_ms": p50,
                "e2e_p95_ms": p95,
                "avg_ms": avg_latency,
            },
            errors=run.errors[-10:],  # Last 10 errors
            system_resources=system_resources,
        )

    async def stop_test(self, run_id: str) -> MassTestProgress:
        """Stop a running mass test."""
        run = self.active_runs.get(run_id)

        if not run:
            raise ValueError(f"Run not found or not running: {run_id}")

        run._stop_requested = True
        logger.info(f"Stop requested for run {run_id}")

        # Wait briefly for graceful stop
        for _ in range(10):
            if run.status != MassTestStatus.RUNNING:
                break
            await asyncio.sleep(0.5)

        return await self.get_progress(run_id)

    async def list_runs(
        self,
        status: Optional[MassTestStatus] = None,
        limit: int = 50,
    ) -> List[MassTestProgress]:
        """List mass test runs."""
        all_runs = list(self.active_runs.values()) + list(self.completed_runs.values())

        if status:
            all_runs = [r for r in all_runs if r.status == status]

        # Sort by start time (newest first)
        all_runs.sort(key=lambda r: r.started_at, reverse=True)

        results = []
        for run in all_runs[:limit]:
            progress = await self.get_progress(run.id)
            results.append(progress)

        return results

    async def cleanup(self):
        """Cleanup Playwright resources."""
        if self._browser:
            await self._browser.close()
        if self._playwright:
            await self._playwright.stop()
        logger.info("Playwright resources cleaned up")


# ============================================================================
# Singleton Instance
# ============================================================================

_instance: Optional[MassTestOrchestrator] = None


def get_mass_test_orchestrator(
    app_url: str = "http://localhost:3000",
    management_url: str = "http://localhost:8766",
) -> MassTestOrchestrator:
    """Get the singleton mass test orchestrator instance."""
    global _instance
    if _instance is None:
        _instance = MassTestOrchestrator(app_url, management_url)
    return _instance
