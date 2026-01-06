"""
UnaMentis Latency Test Harness - Test Orchestrator

Coordinates test execution across iOS and web clients.
"""

import asyncio
import logging
from datetime import datetime
from typing import Dict, List, Optional, Set, Callable, Any
from dataclasses import dataclass, field
import uuid
import json

from .models import (
    TestConfiguration,
    TestResult,
    TestRun,
    TestScenario,
    TestSuiteDefinition,
    ClientType,
    ClientStatus,
    ClientCapabilities,
    RunStatus,
    NetworkProfile,
)

logger = logging.getLogger(__name__)


@dataclass
class ConnectedClient:
    """Represents a connected test client."""
    client_id: str
    client_type: ClientType
    capabilities: ClientCapabilities
    status: ClientStatus
    websocket: Optional[Any] = None  # aiohttp WebSocketResponse
    last_heartbeat: datetime = field(default_factory=datetime.now)


class LatencyTestOrchestrator:
    """
    Orchestrates latency test execution across multiple clients.

    Supports:
    - iOS Simulator clients
    - iOS Device clients
    - Web browser clients

    Each client type has different capabilities, and the orchestrator
    routes tests appropriately based on configuration requirements.
    """

    def __init__(self, storage: Optional["LatencyHarnessStorage"] = None):
        self.clients: Dict[str, ConnectedClient] = {}
        self.active_runs: Dict[str, TestRun] = {}
        self.completed_runs: Dict[str, TestRun] = {}
        self.suites: Dict[str, TestSuiteDefinition] = {}

        # Optional persistent storage
        self.storage = storage

        # Callbacks for real-time updates
        self.on_progress: Optional[Callable[[str, int, int], None]] = None
        self.on_result: Optional[Callable[[str, TestResult], None]] = None
        self.on_run_complete: Optional[Callable[[TestRun], None]] = None

        # Background tasks
        self._heartbeat_task: Optional[asyncio.Task] = None
        self._running = False

    # =========================================================================
    # Lifecycle
    # =========================================================================

    async def start(self):
        """Start the orchestrator background tasks."""
        self._running = True
        self._heartbeat_task = asyncio.create_task(self._heartbeat_monitor())

        # Load data from storage if available
        if self.storage:
            await self._load_from_storage()

        logger.info("Latency test orchestrator started")

    async def _load_from_storage(self):
        """Load suites and runs from persistent storage."""
        if not self.storage:
            return

        try:
            # Load suites
            suites = await self.storage.list_suites()
            for suite in suites:
                self.suites[suite.id] = suite
            logger.info(f"Loaded {len(suites)} test suites from storage")

            # Load recent runs
            runs, _ = await self.storage.list_runs(limit=100)
            for run in runs:
                if run.status == RunStatus.RUNNING:
                    # Stale running run (server restarted) - mark as failed
                    run.status = RunStatus.FAILED
                    await self.storage.save_run(run)
                    self.completed_runs[run.id] = run
                else:
                    self.completed_runs[run.id] = run
            logger.info(f"Loaded {len(runs)} test runs from storage")

        except Exception as e:
            logger.error(f"Failed to load from storage: {e}")

    async def stop(self):
        """Stop the orchestrator and cleanup."""
        self._running = False
        if self._heartbeat_task:
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass
        logger.info("Latency test orchestrator stopped")

    # =========================================================================
    # Client Management
    # =========================================================================

    async def register_client(
        self,
        client_id: str,
        client_type: ClientType,
        capabilities: ClientCapabilities,
        websocket: Optional[Any] = None,
    ) -> ConnectedClient:
        """Register a new test client."""
        status = ClientStatus(
            client_id=client_id,
            client_type=client_type,
            is_connected=True,
            is_running_test=False,
            current_config_id=None,
            last_heartbeat=datetime.now(),
            capabilities=capabilities,
        )

        client = ConnectedClient(
            client_id=client_id,
            client_type=client_type,
            capabilities=capabilities,
            status=status,
            websocket=websocket,
        )

        self.clients[client_id] = client
        logger.info(f"Registered client: {client_id} ({client_type.value})")

        return client

    async def unregister_client(self, client_id: str):
        """Unregister a test client."""
        if client_id in self.clients:
            del self.clients[client_id]
            logger.info(f"Unregistered client: {client_id}")

    async def update_client_heartbeat(self, client_id: str):
        """Update client heartbeat timestamp."""
        if client_id in self.clients:
            self.clients[client_id].last_heartbeat = datetime.now()
            self.clients[client_id].status.last_heartbeat = datetime.now()
            self.clients[client_id].status.is_connected = True

    def get_available_clients(
        self,
        client_type: Optional[ClientType] = None,
        required_providers: Optional[Dict[str, List[str]]] = None,
    ) -> List[ConnectedClient]:
        """Get available clients matching criteria."""
        clients = []

        for client in self.clients.values():
            # Check connection status
            if not client.status.is_connected:
                continue

            # Check if currently running a test
            if client.status.is_running_test:
                continue

            # Filter by client type
            if client_type and client.client_type != client_type:
                continue

            # Check provider requirements
            if required_providers:
                meets_requirements = True

                if "stt" in required_providers:
                    if not set(required_providers["stt"]).issubset(
                        set(client.capabilities.supported_stt_providers)
                    ):
                        meets_requirements = False

                if "llm" in required_providers:
                    if not set(required_providers["llm"]).issubset(
                        set(client.capabilities.supported_llm_providers)
                    ):
                        meets_requirements = False

                if "tts" in required_providers:
                    if not set(required_providers["tts"]).issubset(
                        set(client.capabilities.supported_tts_providers)
                    ):
                        meets_requirements = False

                if not meets_requirements:
                    continue

            clients.append(client)

        return clients

    # =========================================================================
    # Test Suite Management
    # =========================================================================

    async def register_suite(self, suite: TestSuiteDefinition):
        """Register a test suite definition."""
        self.suites[suite.id] = suite

        # Persist to storage
        if self.storage:
            try:
                await self.storage.save_suite(suite)
            except Exception as e:
                logger.error(f"Failed to persist suite: {e}")

        logger.info(f"Registered test suite: {suite.name} ({suite.total_test_count} tests)")

    def get_suite(self, suite_id: str) -> Optional[TestSuiteDefinition]:
        """Get a test suite by ID."""
        return self.suites.get(suite_id)

    def list_suites(self) -> List[TestSuiteDefinition]:
        """List all registered test suites."""
        return list(self.suites.values())

    # =========================================================================
    # Test Execution
    # =========================================================================

    async def start_test_run(
        self,
        suite_id: str,
        client_id: Optional[str] = None,
        client_type: Optional[ClientType] = None,
    ) -> TestRun:
        """
        Start a new test run.

        Args:
            suite_id: ID of the test suite to run
            client_id: Specific client to use (optional)
            client_type: Preferred client type (optional)

        Returns:
            The created TestRun
        """
        suite = self.suites.get(suite_id)
        if not suite:
            raise ValueError(f"Test suite not found: {suite_id}")

        # Find an available client
        if client_id:
            client = self.clients.get(client_id)
            if not client:
                raise ValueError(f"Client not found: {client_id}")
        else:
            available = self.get_available_clients(client_type=client_type)
            if not available:
                raise ValueError("No available clients")
            client = available[0]

        # Create test run
        run_id = f"run_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
        configurations = suite.generate_configurations()

        run = TestRun(
            id=run_id,
            suite_name=suite.name,
            suite_id=suite.id,
            started_at=datetime.now(),
            client_id=client.client_id,
            client_type=client.client_type,
            total_configurations=len(configurations),
            status=RunStatus.RUNNING,
        )

        self.active_runs[run_id] = run
        client.status.is_running_test = True

        # Persist to storage
        if self.storage:
            try:
                await self.storage.save_run(run)
            except Exception as e:
                logger.error(f"Failed to persist run: {e}")

        logger.info(f"Started test run: {run_id} on {client.client_id}")

        # Execute tests in background
        asyncio.create_task(self._execute_run(run, suite, client, configurations))

        return run

    async def _execute_run(
        self,
        run: TestRun,
        suite: TestSuiteDefinition,
        client: ConnectedClient,
        configurations: List[TestConfiguration],
    ):
        """Execute a test run (background task)."""
        try:
            # Get scenarios for quick lookup
            scenarios_by_name = {s.name: s for s in suite.scenarios}

            for i, config in enumerate(configurations):
                if run.status == RunStatus.CANCELLED:
                    break

                scenario = scenarios_by_name.get(config.scenario_name)
                if not scenario:
                    logger.warning(f"Scenario not found: {config.scenario_name}")
                    continue

                try:
                    # Send configuration to client
                    result = await self._execute_test_on_client(
                        client, scenario, config
                    )

                    run.results.append(result)
                    run.completed_configurations = i + 1

                    # Persist result
                    if self.storage:
                        try:
                            await self.storage.save_result(run.id, result)
                            await self.storage.update_run_status(
                                run.id, run.status, run.completed_configurations
                            )
                        except Exception as e:
                            logger.error(f"Failed to persist result: {e}")

                    # Notify progress
                    if self.on_progress:
                        self.on_progress(
                            run.id,
                            run.completed_configurations,
                            run.total_configurations,
                        )

                    if self.on_result:
                        self.on_result(run.id, result)

                except Exception as e:
                    logger.error(f"Test execution failed: {e}")
                    # Create error result
                    error_result = TestResult(
                        id=str(uuid.uuid4()),
                        config_id=config.config_id,
                        scenario_name=config.scenario_name,
                        repetition=config.repetition,
                        timestamp=datetime.now(),
                        client_type=client.client_type,
                        stt_latency_ms=None,
                        llm_ttfb_ms=0,
                        llm_completion_ms=0,
                        tts_ttfb_ms=0,
                        tts_completion_ms=0,
                        e2e_latency_ms=0,
                        network_profile=config.network_profile,
                        errors=[str(e)],
                    )
                    run.results.append(error_result)

            # Mark run as completed
            run.status = RunStatus.COMPLETED
            run.completed_at = datetime.now()

            # Move to completed runs
            if run.id in self.active_runs:
                del self.active_runs[run.id]
            self.completed_runs[run.id] = run

            client.status.is_running_test = False
            client.status.current_config_id = None

            # Persist final state
            if self.storage:
                try:
                    await self.storage.save_run(run)
                except Exception as e:
                    logger.error(f"Failed to persist completed run: {e}")

            logger.info(f"Test run completed: {run.id} ({len(run.results)} results)")

            if self.on_run_complete:
                self.on_run_complete(run)

        except Exception as e:
            logger.error(f"Test run failed: {e}")
            run.status = RunStatus.FAILED
            run.completed_at = datetime.now()
            client.status.is_running_test = False

            # Persist failed state
            if self.storage:
                try:
                    await self.storage.save_run(run)
                except Exception as persist_error:
                    logger.error(f"Failed to persist failed run: {persist_error}")

    async def _execute_test_on_client(
        self,
        client: ConnectedClient,
        scenario: TestScenario,
        config: TestConfiguration,
    ) -> TestResult:
        """Execute a single test on a client."""
        client.status.current_config_id = config.id

        if client.websocket:
            # Send via WebSocket for real clients
            message = {
                "type": "execute_test",
                "scenario": scenario.to_dict(),
                "config": config.to_dict(),
            }
            await client.websocket.send_json(message)

            # Wait for result
            async for msg in client.websocket:
                if msg.type == aiohttp.WSMsgType.TEXT:
                    data = json.loads(msg.data)
                    if data.get("type") == "test_result":
                        return self._parse_result(data["result"], client.client_type)

            raise TimeoutError("No response from client")

        else:
            # For testing without real clients, return mock result
            return self._create_mock_result(config, client.client_type)

    def _parse_result(
        self, data: Dict[str, Any], client_type: ClientType
    ) -> TestResult:
        """Parse a test result from client response."""
        return TestResult(
            id=data["id"],
            config_id=data["configId"],
            scenario_name=data["scenarioName"],
            repetition=data["repetition"],
            timestamp=datetime.fromisoformat(data["timestamp"]),
            client_type=client_type,
            stt_latency_ms=data.get("sttLatencyMs"),
            llm_ttfb_ms=data["llmTTFBMs"],
            llm_completion_ms=data["llmCompletionMs"],
            tts_ttfb_ms=data["ttsTTFBMs"],
            tts_completion_ms=data["ttsCompletionMs"],
            e2e_latency_ms=data["e2eLatencyMs"],
            network_profile=NetworkProfile(data["networkProfile"]),
            network_projections=data.get("networkProjections", {}),
            stt_confidence=data.get("sttConfidence"),
            tts_audio_duration_ms=data.get("ttsAudioDurationMs"),
            llm_output_tokens=data.get("llmOutputTokens"),
            llm_input_tokens=data.get("llmInputTokens"),
            peak_cpu_percent=data.get("peakCPUPercent"),
            peak_memory_mb=data.get("peakMemoryMB"),
            thermal_state=data.get("thermalState"),
            stt_config=data.get("sttConfig"),
            llm_config=data.get("llmConfig"),
            tts_config=data.get("ttsConfig"),
            audio_config=data.get("audioConfig"),
            errors=data.get("errors", []),
        )

    def _create_mock_result(
        self, config: TestConfiguration, client_type: ClientType
    ) -> TestResult:
        """Create a mock result for testing."""
        import random

        base_latency = 100 + random.uniform(0, 200)

        return TestResult(
            id=str(uuid.uuid4()),
            config_id=config.config_id,
            scenario_name=config.scenario_name,
            repetition=config.repetition,
            timestamp=datetime.now(),
            client_type=client_type,
            stt_latency_ms=40 + random.uniform(0, 30),
            llm_ttfb_ms=base_latency,
            llm_completion_ms=base_latency + 50 + random.uniform(0, 100),
            tts_ttfb_ms=50 + random.uniform(0, 50),
            tts_completion_ms=100 + random.uniform(0, 100),
            e2e_latency_ms=base_latency * 2 + random.uniform(0, 200),
            network_profile=config.network_profile,
            errors=[],
        )

    # =========================================================================
    # Run Management
    # =========================================================================

    async def cancel_run(self, run_id: str):
        """Cancel an active test run."""
        if run_id in self.active_runs:
            run = self.active_runs[run_id]
            run.status = RunStatus.CANCELLED
            run.completed_at = datetime.now()

            # Update client status
            client = self.clients.get(run.client_id)
            if client:
                client.status.is_running_test = False
                client.status.current_config_id = None

            logger.info(f"Cancelled test run: {run_id}")

    def get_run(self, run_id: str) -> Optional[TestRun]:
        """Get a test run by ID."""
        return self.active_runs.get(run_id) or self.completed_runs.get(run_id)

    def list_runs(
        self,
        status: Optional[RunStatus] = None,
        limit: int = 50,
    ) -> List[TestRun]:
        """List test runs with optional filtering."""
        all_runs = list(self.active_runs.values()) + list(self.completed_runs.values())

        if status:
            all_runs = [r for r in all_runs if r.status == status]

        # Sort by start time (newest first)
        all_runs.sort(key=lambda r: r.started_at, reverse=True)

        return all_runs[:limit]

    # =========================================================================
    # Background Tasks
    # =========================================================================

    async def _heartbeat_monitor(self):
        """Monitor client heartbeats and mark disconnected clients."""
        while self._running:
            try:
                now = datetime.now()
                timeout = 30  # seconds

                for client in list(self.clients.values()):
                    elapsed = (now - client.last_heartbeat).total_seconds()
                    if elapsed > timeout:
                        client.status.is_connected = False
                        logger.warning(
                            f"Client heartbeat timeout: {client.client_id}"
                        )

                await asyncio.sleep(10)

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Heartbeat monitor error: {e}")
                await asyncio.sleep(1)


# ============================================================================
# Global Instance
# ============================================================================

_orchestrator: Optional[LatencyTestOrchestrator] = None


def get_orchestrator() -> LatencyTestOrchestrator:
    """Get the global orchestrator instance."""
    global _orchestrator
    if _orchestrator is None:
        _orchestrator = LatencyTestOrchestrator()
    return _orchestrator
