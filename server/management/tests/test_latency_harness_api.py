"""
Tests for Latency Harness API routes.

Comprehensive tests covering all endpoints in latency_harness_api.py.
"""
import json
import pytest
from datetime import datetime
from unittest.mock import MagicMock, AsyncMock, patch
from aiohttp import web


# =============================================================================
# Mock Classes
# =============================================================================

class MockClientCapabilities:
    """Mock client capabilities."""

    def __init__(
        self,
        supported_stt_providers=None,
        supported_llm_providers=None,
        supported_tts_providers=None,
        has_high_precision_timing=True,
        has_device_metrics=True,
        has_on_device_ml=False,
        max_concurrent_tests=1,
    ):
        self.supported_stt_providers = supported_stt_providers or ["deepgram"]
        self.supported_llm_providers = supported_llm_providers or ["anthropic"]
        self.supported_tts_providers = supported_tts_providers or ["chatterbox"]
        self.has_high_precision_timing = has_high_precision_timing
        self.has_device_metrics = has_device_metrics
        self.has_on_device_ml = has_on_device_ml
        self.max_concurrent_tests = max_concurrent_tests


class MockClientStatus:
    """Mock client status."""

    def __init__(self, is_connected=True, is_running_test=False, current_config_id=None):
        self.is_connected = is_connected
        self.is_running_test = is_running_test
        self.current_config_id = current_config_id


class MockClientType:
    """Mock client type enum."""

    def __init__(self, value):
        self.value = value


class MockConnectedClient:
    """Mock connected test client."""

    def __init__(
        self,
        client_id="test_client_1",
        client_type_value="ios_simulator",
        is_connected=True,
    ):
        self.client_id = client_id
        self.client_type = MockClientType(client_type_value)
        self.status = MockClientStatus(is_connected=is_connected)
        self.capabilities = MockClientCapabilities()
        self.last_heartbeat = datetime.now()


class MockNetworkProfile:
    """Mock network profile enum."""

    def __init__(self, value):
        self.value = value


class MockTestScenario:
    """Mock test scenario."""

    def __init__(self, scenario_id="scenario_1"):
        self.id = scenario_id
        self.name = "Test Scenario"
        self.description = "A test scenario"

    def to_dict(self):
        return {"id": self.id, "name": self.name, "description": self.description}


class MockParameterSpace:
    """Mock parameter space."""

    def __init__(self):
        self.stt_configs = [MagicMock(to_dict=lambda: {"provider": "deepgram"})]
        self.llm_configs = [MagicMock(to_dict=lambda: {"provider": "anthropic", "model": "claude-3-5-haiku"})]
        self.tts_configs = [MagicMock(to_dict=lambda: {"provider": "chatterbox"})]
        self.audio_configs = [MagicMock(to_dict=lambda: {"sampleRate": 24000})]


class MockTestSuiteDefinition:
    """Mock test suite definition."""

    def __init__(self, suite_id="quick_validation"):
        self.id = suite_id
        self.name = "Quick Validation"
        self.description = "Fast sanity check for CI/CD pipelines"
        self.scenarios = [MockTestScenario()]
        self.network_profiles = [MockNetworkProfile("localhost")]
        self.parameter_space = MockParameterSpace()

    @property
    def total_test_count(self):
        return 3

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
        }


class MockRunStatus:
    """Mock run status enum."""

    PENDING = MagicMock(value="pending")
    RUNNING = MagicMock(value="running")
    COMPLETED = MagicMock(value="completed")
    FAILED = MagicMock(value="failed")
    CANCELLED = MagicMock(value="cancelled")

    def __init__(self, value):
        self.value = value


class MockTestResult:
    """Mock test result."""

    def __init__(
        self,
        result_id="result_1",
        config_id="config_1",
        e2e_latency_ms=450.0,
        is_success=True,
    ):
        self.id = result_id
        self.config_id = config_id
        self.scenario_name = "Test Scenario"
        self.repetition = 1
        self.timestamp = datetime.now()
        self.stt_latency_ms = 100.0
        self.llm_ttfb_ms = 150.0
        self.llm_completion_ms = 300.0
        self.tts_ttfb_ms = 50.0
        self.tts_completion_ms = 200.0
        self.e2e_latency_ms = e2e_latency_ms
        self.network_profile = MockNetworkProfile("localhost")
        self.is_success = is_success
        self.errors = [] if is_success else ["Test error"]

    def to_dict(self):
        return {
            "id": self.id,
            "configId": self.config_id,
            "e2eLatencyMs": self.e2e_latency_ms,
            "isSuccess": self.is_success,
        }


class MockTestRun:
    """Mock test run."""

    def __init__(
        self,
        run_id="run_123",
        status_value="running",
        results=None,
    ):
        self.id = run_id
        self.suite_name = "Quick Validation"
        self.suite_id = "quick_validation"
        self.started_at = datetime.now()
        self.completed_at = None
        self.client_id = "test_client_1"
        self.client_type = MockClientType("ios_simulator")
        self.status = MockRunStatus(status_value)
        self.total_configurations = 10
        self.completed_configurations = 5
        self.results = results or [MockTestResult()]

    @property
    def elapsed_time(self):
        return 60.0

    def to_dict(self):
        return {
            "id": self.id,
            "suiteName": self.suite_name,
            "status": self.status.value,
            "totalConfigurations": self.total_configurations,
            "completedConfigurations": self.completed_configurations,
        }


class MockBaselineMetrics:
    """Mock baseline metrics."""

    def __init__(self, median_e2e_ms=400.0):
        self.median_e2e_ms = median_e2e_ms
        self.p99_e2e_ms = 600.0
        self.min_e2e_ms = 350.0
        self.max_e2e_ms = 700.0
        self.median_stt_ms = 100.0
        self.median_llm_ttfb_ms = 150.0
        self.median_llm_completion_ms = 300.0
        self.median_tts_ttfb_ms = 50.0
        self.median_tts_completion_ms = 200.0
        self.sample_count = 10

    def to_dict(self):
        return {
            "medianE2EMs": self.median_e2e_ms,
            "p99E2EMs": self.p99_e2e_ms,
        }


class MockPerformanceBaseline:
    """Mock performance baseline."""

    def __init__(self, baseline_id="baseline_1"):
        self.id = baseline_id
        self.name = "Test Baseline"
        self.description = "A test baseline"
        self.run_id = "run_123"
        self.created_at = datetime.now()
        self.is_active = True
        self.config_metrics = {"config_1": MockBaselineMetrics()}
        self.overall_metrics = MockBaselineMetrics()


class MockSummaryStatistics:
    """Mock summary statistics."""

    def __init__(self):
        self.total_configurations = 5
        self.total_tests = 50
        self.successful_tests = 48
        self.failed_tests = 2
        self.overall_median_e2e_ms = 425.0
        self.overall_p99_e2e_ms = 650.0
        self.overall_min_e2e_ms = 350.0
        self.overall_max_e2e_ms = 800.0
        self.median_stt_ms = 100.0
        self.median_llm_ttfb_ms = 150.0
        self.median_llm_completion_ms = 300.0
        self.median_tts_ttfb_ms = 50.0
        self.median_tts_completion_ms = 200.0
        self.test_duration_minutes = 5.5


class MockAnalysisReport:
    """Mock analysis report."""

    def __init__(self):
        self.run_id = "run_123"
        self.generated_at = datetime.now()
        self.summary = MockSummaryStatistics()
        self.best_configurations = []
        self.network_projections = []
        self.regressions = []
        self.recommendations = ["Use Chatterbox TTS for lowest latency"]


class MockOrchestrator:
    """Mock latency test orchestrator."""

    def __init__(self):
        self.suites = {
            "quick_validation": MockTestSuiteDefinition("quick_validation"),
            "provider_comparison": MockTestSuiteDefinition("provider_comparison"),
        }
        self.clients = {
            "test_client_1": MockConnectedClient("test_client_1"),
        }
        self._runs = {}

    def list_suites(self):
        return list(self.suites.values())

    def get_suite(self, suite_id):
        return self.suites.get(suite_id)

    def list_runs(self, status=None, limit=50):
        runs = list(self._runs.values())
        if status:
            runs = [r for r in runs if r.status.value == status.value]
        return runs[:limit]

    def get_run(self, run_id):
        return self._runs.get(run_id)

    async def start_test_run(self, suite_id, client_id=None, client_type=None):
        if suite_id not in self.suites:
            raise ValueError(f"Suite not found: {suite_id}")
        run = MockTestRun(run_id=f"run_{len(self._runs)}")
        self._runs[run.id] = run
        return run

    async def cancel_run(self, run_id):
        if run_id in self._runs:
            self._runs[run_id].status = MockRunStatus("cancelled")

    async def register_client(self, client_id, client_type, capabilities):
        self.clients[client_id] = MockConnectedClient(client_id, client_type.value)

    async def update_client_heartbeat(self, client_id):
        if client_id in self.clients:
            self.clients[client_id].last_heartbeat = datetime.now()


class MockStorage:
    """Mock latency storage."""

    def __init__(self):
        self._suites = {}
        self._baselines = {}

    async def get_suite(self, suite_id):
        return self._suites.get(suite_id)

    async def delete_suite(self, suite_id):
        if suite_id in self._suites:
            del self._suites[suite_id]
            return True
        return False

    async def list_baselines(self):
        return list(self._baselines.values())

    async def get_baseline(self, baseline_id):
        return self._baselines.get(baseline_id)

    async def save_baseline(self, baseline):
        self._baselines[baseline.id] = baseline


class MockMassTestProgress:
    """Mock mass test progress."""

    def __init__(self, run_id="mass_run_1"):
        self.run_id = run_id
        self.status = MagicMock(value="running")
        self.sessions_completed = 50
        self.sessions_total = 100
        self.active_clients = 4
        self.elapsed_seconds = 120.5
        self.estimated_remaining_seconds = 120.0
        self.latency_stats = {"median_e2e_ms": 450.0}
        self.errors = []
        self.system_resources = {"cpu_percent": 45.0}


class MockMassOrchestrator:
    """Mock mass test orchestrator."""

    def __init__(self):
        self._runs = {}

    async def start_mass_test(
        self,
        total_sessions=100,
        web_clients=4,
        provider_config=None,
        utterances=None,
        turns_per_session=3,
    ):
        run_id = f"mass_run_{len(self._runs)}"
        self._runs[run_id] = MockMassTestProgress(run_id)
        return run_id

    async def get_progress(self, run_id):
        if run_id not in self._runs:
            raise ValueError(f"Run not found: {run_id}")
        return self._runs[run_id]

    async def stop_test(self, run_id):
        if run_id not in self._runs:
            raise ValueError(f"Run not found: {run_id}")
        progress = self._runs[run_id]
        progress.status = MagicMock(value="stopped")
        return progress

    async def list_runs(self, limit=50):
        return list(self._runs.values())[:limit]


# Import the module under test
import latency_harness_api


# =============================================================================
# Fixtures
# =============================================================================


@pytest.fixture
def mock_app():
    """Create a mock aiohttp application."""
    app = web.Application()
    return app


@pytest.fixture
def mock_request(mock_app):
    """Create a factory for mock requests."""

    def _make_request(
        method="GET",
        json_data=None,
        query=None,
        match_info=None,
        raise_json_decode_error=False,
    ):
        request = MagicMock(spec=web.Request)
        request.app = mock_app
        request.method = method
        request.query = query or {}
        request.match_info = match_info or {}

        if json_data is not None:

            async def mock_json():
                return json_data

            request.json = mock_json
        elif raise_json_decode_error:

            async def mock_json():
                raise json.JSONDecodeError("Invalid JSON", "", 0)

            request.json = mock_json
        else:

            async def mock_json():
                return {}

            request.json = mock_json

        return request

    return _make_request


@pytest.fixture
def mock_orchestrator():
    """Create a mock orchestrator."""
    return MockOrchestrator()


@pytest.fixture
def mock_storage():
    """Create a mock storage."""
    return MockStorage()


# =============================================================================
# Test Suite Endpoints
# =============================================================================


class TestHandleListSuites:
    """Tests for handle_list_suites endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_list_suites_success(self, mock_get_orch, mock_request):
        """Test successful suite listing."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="GET")
        response = await latency_harness_api.handle_list_suites(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "suites" in data
        assert len(data["suites"]) == 2


class TestHandleGetSuite:
    """Tests for handle_get_suite endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_get_suite_success(self, mock_get_orch, mock_request):
        """Test successful suite retrieval."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="GET", match_info={"suite_id": "quick_validation"})
        response = await latency_harness_api.handle_get_suite(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["id"] == "quick_validation"

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_get_suite_not_found(self, mock_get_orch, mock_request):
        """Test suite not found."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="GET", match_info={"suite_id": "nonexistent"})
        response = await latency_harness_api.handle_get_suite(request)

        assert response.status == 404


class TestHandleUploadSuite:
    """Tests for handle_upload_suite endpoint."""

    @pytest.mark.asyncio
    async def test_upload_suite_not_implemented(self, mock_request):
        """Test suite upload returns not implemented."""
        request = mock_request(json_data={"id": "custom_suite", "name": "Custom Suite"})
        response = await latency_harness_api.handle_upload_suite(request)

        assert response.status == 501

    @pytest.mark.asyncio
    async def test_upload_suite_invalid_json(self, mock_request):
        """Test upload with invalid JSON."""
        request = mock_request(raise_json_decode_error=True)
        response = await latency_harness_api.handle_upload_suite(request)

        assert response.status == 400


class TestHandleDeleteSuite:
    """Tests for handle_delete_suite endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api._storage")
    async def test_delete_builtin_suite_rejected(self, mock_storage, mock_request):
        """Test that built-in suites cannot be deleted."""
        request = mock_request(method="DELETE", match_info={"suite_id": "quick_validation"})
        response = await latency_harness_api.handle_delete_suite(request)

        assert response.status == 400
        assert b"Cannot delete built-in suite" in response.body

    @pytest.mark.asyncio
    async def test_delete_suite_storage_not_initialized(self, mock_request):
        """Test delete when storage not initialized."""
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = None
            request = mock_request(method="DELETE", match_info={"suite_id": "custom_suite"})
            response = await latency_harness_api.handle_delete_suite(request)

            assert response.status == 500
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    async def test_delete_suite_not_found(self, mock_request, mock_storage):
        """Test delete suite not found."""
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(method="DELETE", match_info={"suite_id": "nonexistent"})
            response = await latency_harness_api.handle_delete_suite(request)

            assert response.status == 404
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    async def test_delete_suite_success(self, mock_request, mock_storage):
        """Test successful suite deletion."""
        mock_storage._suites["custom_suite"] = MockTestSuiteDefinition("custom_suite")
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(method="DELETE", match_info={"suite_id": "custom_suite"})
            response = await latency_harness_api.handle_delete_suite(request)

            assert response.status == 200
        finally:
            latency_harness_api._storage = original_storage


# =============================================================================
# Test Run Endpoints
# =============================================================================


class TestHandleStartRun:
    """Tests for handle_start_run endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_start_run_success(self, mock_get_orch, mock_request):
        """Test successful run start."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(json_data={"suiteId": "quick_validation"})
        response = await latency_harness_api.handle_start_run(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "runId" in data

    @pytest.mark.asyncio
    async def test_start_run_missing_suite_id(self, mock_request):
        """Test start run without suite ID."""
        request = mock_request(json_data={})
        response = await latency_harness_api.handle_start_run(request)

        assert response.status == 400
        assert b"suiteId is required" in response.body

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_start_run_invalid_client_type(self, mock_get_orch, mock_request):
        """Test start run with invalid client type."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            json_data={
                "suiteId": "quick_validation",
                "clientType": "invalid_type",
            }
        )
        response = await latency_harness_api.handle_start_run(request)

        assert response.status == 400
        assert b"Invalid clientType" in response.body

    @pytest.mark.asyncio
    async def test_start_run_invalid_json(self, mock_request):
        """Test start run with invalid JSON."""
        request = mock_request(raise_json_decode_error=True)
        response = await latency_harness_api.handle_start_run(request)

        assert response.status == 400


class TestHandleListRuns:
    """Tests for handle_list_runs endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_list_runs_success(self, mock_get_orch, mock_request):
        """Test successful run listing."""
        orch = MockOrchestrator()
        orch._runs["run_1"] = MockTestRun("run_1")
        mock_get_orch.return_value = orch

        request = mock_request(method="GET", query={})
        response = await latency_harness_api.handle_list_runs(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "runs" in data

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_list_runs_with_status_filter(self, mock_get_orch, mock_request):
        """Test run listing with status filter."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="GET", query={"status": "running", "limit": "10"})
        response = await latency_harness_api.handle_list_runs(request)

        assert response.status == 200


class TestHandleGetRun:
    """Tests for handle_get_run endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_get_run_success(self, mock_get_orch, mock_request):
        """Test successful run retrieval."""
        orch = MockOrchestrator()
        orch._runs["run_123"] = MockTestRun("run_123")
        mock_get_orch.return_value = orch

        request = mock_request(method="GET", match_info={"run_id": "run_123"})
        response = await latency_harness_api.handle_get_run(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_get_run_not_found(self, mock_get_orch, mock_request):
        """Test run not found."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="GET", match_info={"run_id": "nonexistent"})
        response = await latency_harness_api.handle_get_run(request)

        assert response.status == 404


class TestHandleGetRunResults:
    """Tests for handle_get_run_results endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_get_run_results_success(self, mock_get_orch, mock_request):
        """Test successful results retrieval."""
        orch = MockOrchestrator()
        orch._runs["run_123"] = MockTestRun("run_123")
        mock_get_orch.return_value = orch

        request = mock_request(method="GET", match_info={"run_id": "run_123"})
        response = await latency_harness_api.handle_get_run_results(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "results" in data

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_get_run_results_not_found(self, mock_get_orch, mock_request):
        """Test results for non-existent run."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="GET", match_info={"run_id": "nonexistent"})
        response = await latency_harness_api.handle_get_run_results(request)

        assert response.status == 404


class TestHandleCancelRun:
    """Tests for handle_cancel_run endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_cancel_run_success(self, mock_get_orch, mock_request):
        """Test successful run cancellation."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="DELETE", match_info={"run_id": "run_123"})
        response = await latency_harness_api.handle_cancel_run(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "cancelled" in data["message"].lower()


# =============================================================================
# Analysis Endpoints
# =============================================================================


class TestHandleGetAnalysis:
    """Tests for handle_get_analysis endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.ResultsAnalyzer")
    @patch("latency_harness_api.get_orchestrator")
    async def test_get_analysis_success(self, mock_get_orch, mock_analyzer_class, mock_request):
        """Test successful analysis retrieval."""
        orch = MockOrchestrator()
        orch._runs["run_123"] = MockTestRun("run_123")
        mock_get_orch.return_value = orch

        mock_analyzer = MagicMock()
        mock_analyzer.analyze.return_value = MockAnalysisReport()
        mock_analyzer_class.return_value = mock_analyzer

        request = mock_request(method="GET", match_info={"run_id": "run_123"})
        response = await latency_harness_api.handle_get_analysis(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "summary" in data

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_get_analysis_run_not_found(self, mock_get_orch, mock_request):
        """Test analysis for non-existent run."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="GET", match_info={"run_id": "nonexistent"})
        response = await latency_harness_api.handle_get_analysis(request)

        assert response.status == 404


class TestHandleCompareRuns:
    """Tests for handle_compare_runs endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.ResultsAnalyzer")
    @patch("latency_harness_api.get_orchestrator")
    async def test_compare_runs_success(self, mock_get_orch, mock_analyzer_class, mock_request):
        """Test successful run comparison."""
        orch = MockOrchestrator()
        orch._runs["run_1"] = MockTestRun("run_1")
        orch._runs["run_2"] = MockTestRun("run_2")
        mock_get_orch.return_value = orch

        mock_analyzer = MagicMock()
        mock_analyzer.compare_runs.return_value = {"comparison": "data"}
        mock_analyzer_class.return_value = mock_analyzer

        request = mock_request(json_data={"run1Id": "run_1", "run2Id": "run_2"})
        response = await latency_harness_api.handle_compare_runs(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_compare_runs_missing_ids(self, mock_request):
        """Test comparison without run IDs."""
        request = mock_request(json_data={"run1Id": "run_1"})
        response = await latency_harness_api.handle_compare_runs(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_compare_runs_first_not_found(self, mock_get_orch, mock_request):
        """Test comparison with first run not found."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(json_data={"run1Id": "nonexistent", "run2Id": "run_2"})
        response = await latency_harness_api.handle_compare_runs(request)

        assert response.status == 404

    @pytest.mark.asyncio
    async def test_compare_runs_invalid_json(self, mock_request):
        """Test comparison with invalid JSON."""
        request = mock_request(raise_json_decode_error=True)
        response = await latency_harness_api.handle_compare_runs(request)

        assert response.status == 400


class TestHandleExportResults:
    """Tests for handle_export_results endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_export_json_success(self, mock_get_orch, mock_request):
        """Test successful JSON export."""
        orch = MockOrchestrator()
        run = MockTestRun("run_123")
        run.completed_at = datetime.now()
        orch._runs["run_123"] = run
        mock_get_orch.return_value = orch

        request = mock_request(method="GET", match_info={"run_id": "run_123"}, query={"format": "json"})
        response = await latency_harness_api.handle_export_results(request)

        assert response.status == 200
        assert response.content_type == "application/json"

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_export_csv_success(self, mock_get_orch, mock_request):
        """Test successful CSV export."""
        orch = MockOrchestrator()
        orch._runs["run_123"] = MockTestRun("run_123")
        mock_get_orch.return_value = orch

        request = mock_request(method="GET", match_info={"run_id": "run_123"}, query={"format": "csv"})
        response = await latency_harness_api.handle_export_results(request)

        assert response.status == 200
        assert response.content_type == "text/csv"

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_export_run_not_found(self, mock_get_orch, mock_request):
        """Test export for non-existent run."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="GET", match_info={"run_id": "nonexistent"})
        response = await latency_harness_api.handle_export_results(request)

        assert response.status == 404


# =============================================================================
# Client Management Endpoints
# =============================================================================


class TestHandleListTestClients:
    """Tests for handle_list_test_clients endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_list_clients_success(self, mock_get_orch, mock_request):
        """Test successful client listing."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(method="GET")
        response = await latency_harness_api.handle_list_test_clients(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "clients" in data


class TestHandleClientHeartbeat:
    """Tests for handle_client_heartbeat_latency endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_heartbeat_existing_client(self, mock_get_orch, mock_request):
        """Test heartbeat for existing client."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            json_data={
                "clientId": "test_client_1",
                "clientType": "ios_simulator",
            }
        )
        response = await latency_harness_api.handle_client_heartbeat_latency(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_heartbeat_new_client(self, mock_get_orch, mock_request):
        """Test heartbeat for new client (registration)."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            json_data={
                "clientId": "new_client",
                "clientType": "web",
                "capabilities": {
                    "supportedSTTProviders": ["deepgram"],
                    "supportedLLMProviders": ["anthropic"],
                    "supportedTTSProviders": ["chatterbox"],
                },
            }
        )
        response = await latency_harness_api.handle_client_heartbeat_latency(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_heartbeat_missing_fields(self, mock_request):
        """Test heartbeat with missing required fields."""
        request = mock_request(json_data={"clientId": "test"})
        response = await latency_harness_api.handle_client_heartbeat_latency(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_heartbeat_invalid_client_type(self, mock_get_orch, mock_request):
        """Test heartbeat with invalid client type."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            json_data={
                "clientId": "test",
                "clientType": "invalid",
            }
        )
        response = await latency_harness_api.handle_client_heartbeat_latency(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_heartbeat_invalid_json(self, mock_request):
        """Test heartbeat with invalid JSON."""
        request = mock_request(raise_json_decode_error=True)
        response = await latency_harness_api.handle_client_heartbeat_latency(request)

        assert response.status == 400


class TestHandleSubmitResult:
    """Tests for handle_submit_result endpoint."""

    @pytest.mark.asyncio
    async def test_submit_result_success(self, mock_request):
        """Test successful result submission."""
        request = mock_request(
            json_data={
                "clientId": "test_client_1",
                "result": {
                    "configId": "config_1",
                    "e2eLatencyMs": 450.0,
                },
            }
        )
        response = await latency_harness_api.handle_submit_result(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_submit_result_missing_fields(self, mock_request):
        """Test submit with missing fields."""
        request = mock_request(json_data={"clientId": "test"})
        response = await latency_harness_api.handle_submit_result(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_submit_result_invalid_json(self, mock_request):
        """Test submit with invalid JSON."""
        request = mock_request(raise_json_decode_error=True)
        response = await latency_harness_api.handle_submit_result(request)

        assert response.status == 400


# =============================================================================
# Baseline Management Endpoints
# =============================================================================


class TestHandleListBaselines:
    """Tests for handle_list_baselines endpoint."""

    @pytest.mark.asyncio
    async def test_list_baselines_no_storage(self, mock_request):
        """Test list baselines when storage not initialized."""
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = None
            request = mock_request(method="GET")
            response = await latency_harness_api.handle_list_baselines(request)

            assert response.status == 500
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    async def test_list_baselines_success(self, mock_request, mock_storage):
        """Test successful baseline listing."""
        mock_storage._baselines["baseline_1"] = MockPerformanceBaseline("baseline_1")
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(method="GET")
            response = await latency_harness_api.handle_list_baselines(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "baselines" in data
        finally:
            latency_harness_api._storage = original_storage


class TestHandleCreateBaseline:
    """Tests for handle_create_baseline endpoint."""

    @pytest.mark.asyncio
    async def test_create_baseline_no_storage(self, mock_request):
        """Test create baseline when storage not initialized."""
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = None
            request = mock_request(json_data={"runId": "run_123"})
            response = await latency_harness_api.handle_create_baseline(request)

            assert response.status == 500
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    async def test_create_baseline_missing_run_id(self, mock_request, mock_storage):
        """Test create baseline without run ID."""
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(json_data={})
            response = await latency_harness_api.handle_create_baseline(request)

            assert response.status == 400
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_create_baseline_run_not_found(self, mock_get_orch, mock_request, mock_storage):
        """Test create baseline for non-existent run."""
        mock_get_orch.return_value = MockOrchestrator()
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(json_data={"runId": "nonexistent"})
            response = await latency_harness_api.handle_create_baseline(request)

            assert response.status == 404
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_create_baseline_run_not_completed(self, mock_get_orch, mock_request, mock_storage):
        """Test create baseline for non-completed run."""
        orch = MockOrchestrator()
        run = MockTestRun("run_123", status_value="running")
        orch._runs["run_123"] = run
        mock_get_orch.return_value = orch

        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(json_data={"runId": "run_123"})
            response = await latency_harness_api.handle_create_baseline(request)

            assert response.status == 400
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_create_baseline_no_successful_results(self, mock_get_orch, mock_request, mock_storage):
        """Test create baseline with no successful results."""
        orch = MockOrchestrator()
        run = MockTestRun("run_123", status_value="completed")
        run.status = MockRunStatus("completed")
        run.status.value = "completed"
        # Patch the RunStatus comparison
        with patch("latency_harness_api.RunStatus") as mock_run_status:
            mock_run_status.COMPLETED = run.status
            run.results = [MockTestResult(is_success=False)]
            orch._runs["run_123"] = run
            mock_get_orch.return_value = orch

            original_storage = latency_harness_api._storage
            try:
                latency_harness_api._storage = mock_storage
                request = mock_request(json_data={"runId": "run_123"})
                response = await latency_harness_api.handle_create_baseline(request)

                assert response.status == 400
            finally:
                latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    async def test_create_baseline_invalid_json(self, mock_request, mock_storage):
        """Test create baseline with invalid JSON."""
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(raise_json_decode_error=True)
            response = await latency_harness_api.handle_create_baseline(request)

            assert response.status == 400
        finally:
            latency_harness_api._storage = original_storage


class TestHandleCheckBaseline:
    """Tests for handle_check_baseline endpoint."""

    @pytest.mark.asyncio
    async def test_check_baseline_no_storage(self, mock_request):
        """Test check baseline when storage not initialized."""
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = None
            request = mock_request(
                method="GET",
                match_info={"baseline_id": "baseline_1"},
                query={"runId": "run_123"},
            )
            response = await latency_harness_api.handle_check_baseline(request)

            assert response.status == 500
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    async def test_check_baseline_missing_run_id(self, mock_request, mock_storage):
        """Test check baseline without run ID."""
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(method="GET", match_info={"baseline_id": "baseline_1"}, query={})
            response = await latency_harness_api.handle_check_baseline(request)

            assert response.status == 400
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    async def test_check_baseline_not_found(self, mock_request, mock_storage):
        """Test check baseline not found."""
        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(
                method="GET",
                match_info={"baseline_id": "nonexistent"},
                query={"runId": "run_123"},
            )
            response = await latency_harness_api.handle_check_baseline(request)

            assert response.status == 404
        finally:
            latency_harness_api._storage = original_storage

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    async def test_check_baseline_run_not_found(self, mock_get_orch, mock_request, mock_storage):
        """Test check baseline with run not found."""
        mock_get_orch.return_value = MockOrchestrator()
        mock_storage._baselines["baseline_1"] = MockPerformanceBaseline("baseline_1")

        original_storage = latency_harness_api._storage
        try:
            latency_harness_api._storage = mock_storage
            request = mock_request(
                method="GET",
                match_info={"baseline_id": "baseline_1"},
                query={"runId": "nonexistent"},
            )
            response = await latency_harness_api.handle_check_baseline(request)

            assert response.status == 404
        finally:
            latency_harness_api._storage = original_storage


# =============================================================================
# Test Target Discovery
# =============================================================================


class TestHandleListTestTargets:
    """Tests for handle_list_test_targets endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    @patch("subprocess.run")
    async def test_list_targets_success(self, mock_subprocess, mock_get_orch, mock_request):
        """Test successful target listing."""
        mock_get_orch.return_value = MockOrchestrator()

        # Mock simctl output
        mock_subprocess.return_value = MagicMock(
            returncode=0,
            stdout=json.dumps({
                "devices": {
                    "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
                        {
                            "name": "iPhone 16 Pro",
                            "udid": "ABC123",
                            "isAvailable": True,
                            "state": "Shutdown",
                            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                        }
                    ]
                }
            }),
        )

        request = mock_request(method="GET")
        response = await latency_harness_api.handle_list_test_targets(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "targets" in data
        assert "categories" in data
        assert "summary" in data

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_orchestrator")
    @patch("subprocess.run")
    async def test_list_targets_subprocess_failure(self, mock_subprocess, mock_get_orch, mock_request):
        """Test target listing when subprocess fails."""
        mock_get_orch.return_value = MockOrchestrator()
        mock_subprocess.side_effect = Exception("Command failed")

        request = mock_request(method="GET")
        response = await latency_harness_api.handle_list_test_targets(request)

        # Should still succeed with connected clients
        assert response.status == 200


# =============================================================================
# Mass Test Orchestrator Endpoints
# =============================================================================


class TestHandleStartMassTest:
    """Tests for handle_start_mass_test endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_mass_orchestrator")
    async def test_start_mass_test_success(self, mock_get_mass_orch, mock_request):
        """Test successful mass test start."""
        mock_get_mass_orch.return_value = MockMassOrchestrator()

        request = mock_request(
            json_data={
                "webClients": 4,
                "totalSessions": 100,
                "providerConfigs": {
                    "llm": "anthropic",
                    "llmModel": "claude-3-5-haiku-20241022",
                    "tts": "chatterbox",
                },
            }
        )
        response = await latency_harness_api.handle_start_mass_test(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "runId" in data

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_mass_orchestrator")
    async def test_start_mass_test_error(self, mock_get_mass_orch, mock_request):
        """Test mass test start with error."""
        mock_orch = MockMassOrchestrator()
        mock_orch.start_mass_test = AsyncMock(side_effect=Exception("Start failed"))
        mock_get_mass_orch.return_value = mock_orch

        request = mock_request(json_data={"totalSessions": 100})
        response = await latency_harness_api.handle_start_mass_test(request)

        assert response.status == 500


class TestHandleGetMassTestStatus:
    """Tests for handle_get_mass_test_status endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_mass_orchestrator")
    async def test_get_status_success(self, mock_get_mass_orch, mock_request):
        """Test successful status retrieval."""
        orch = MockMassOrchestrator()
        orch._runs["mass_run_1"] = MockMassTestProgress("mass_run_1")
        mock_get_mass_orch.return_value = orch

        request = mock_request(method="GET", match_info={"run_id": "mass_run_1"})
        response = await latency_harness_api.handle_get_mass_test_status(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_mass_orchestrator")
    async def test_get_status_not_found(self, mock_get_mass_orch, mock_request):
        """Test status for non-existent run."""
        mock_get_mass_orch.return_value = MockMassOrchestrator()

        request = mock_request(method="GET", match_info={"run_id": "nonexistent"})
        response = await latency_harness_api.handle_get_mass_test_status(request)

        assert response.status == 404


class TestHandleStopMassTest:
    """Tests for handle_stop_mass_test endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_mass_orchestrator")
    async def test_stop_success(self, mock_get_mass_orch, mock_request):
        """Test successful mass test stop."""
        orch = MockMassOrchestrator()
        orch._runs["mass_run_1"] = MockMassTestProgress("mass_run_1")
        mock_get_mass_orch.return_value = orch

        request = mock_request(method="POST", match_info={"run_id": "mass_run_1"})
        response = await latency_harness_api.handle_stop_mass_test(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_mass_orchestrator")
    async def test_stop_not_found(self, mock_get_mass_orch, mock_request):
        """Test stop for non-existent run."""
        mock_get_mass_orch.return_value = MockMassOrchestrator()

        request = mock_request(method="POST", match_info={"run_id": "nonexistent"})
        response = await latency_harness_api.handle_stop_mass_test(request)

        assert response.status == 404


class TestHandleListMassTests:
    """Tests for handle_list_mass_tests endpoint."""

    @pytest.mark.asyncio
    @patch("latency_harness_api.get_mass_orchestrator")
    async def test_list_success(self, mock_get_mass_orch, mock_request):
        """Test successful listing."""
        orch = MockMassOrchestrator()
        orch._runs["mass_run_1"] = MockMassTestProgress("mass_run_1")
        mock_get_mass_orch.return_value = orch

        request = mock_request(method="GET", query={"limit": "10"})
        response = await latency_harness_api.handle_list_mass_tests(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "runs" in data


# =============================================================================
# Unified Metrics Ingestion Endpoints
# =============================================================================


class TestHandleIngestMetrics:
    """Tests for handle_ingest_metrics endpoint."""

    @pytest.mark.asyncio
    async def test_ingest_single_metric(self, mock_request):
        """Test ingesting a single metric."""
        # Clear metrics state
        latency_harness_api._ingested_metrics.clear()
        latency_harness_api._metrics_by_session.clear()

        request = mock_request(
            json_data={
                "client": "ios",
                "clientId": "device-123",
                "sessionId": "session-456",
                "metrics": {
                    "e2e_latency_ms": 450.0,
                    "stt_latency_ms": 100.0,
                },
                "providers": {
                    "llm": "anthropic",
                },
            }
        )
        response = await latency_harness_api.handle_ingest_metrics(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["ingested"] == 1

    @pytest.mark.asyncio
    async def test_ingest_batch_metrics(self, mock_request):
        """Test ingesting a batch of metrics."""
        latency_harness_api._ingested_metrics.clear()
        latency_harness_api._metrics_by_session.clear()

        request = mock_request(
            json_data={
                "client": "web",
                "clientId": "browser-123",
                "batchSize": 2,
                "metrics": [
                    {"sessionId": "s1", "metrics": {"e2e_latency_ms": 400.0}},
                    {"sessionId": "s2", "metrics": {"e2e_latency_ms": 500.0}},
                ],
            }
        )
        response = await latency_harness_api.handle_ingest_metrics(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["ingested"] == 2

    @pytest.mark.asyncio
    async def test_ingest_invalid_json(self, mock_request):
        """Test ingesting with invalid JSON."""
        request = mock_request(raise_json_decode_error=True)
        response = await latency_harness_api.handle_ingest_metrics(request)

        assert response.status == 400


class TestHandleListMetricSessions:
    """Tests for handle_list_metric_sessions endpoint."""

    @pytest.mark.asyncio
    async def test_list_sessions_success(self, mock_request):
        """Test listing metric sessions."""
        # Set up some test data
        latency_harness_api._metrics_by_session.clear()
        latency_harness_api._metrics_by_session["session_1"] = {
            "sessionId": "session_1",
            "client": "ios",
            "clientId": "device-123",
            "clientName": None,
            "firstSeen": datetime.now().isoformat(),
            "lastSeen": datetime.now().isoformat(),
            "metricsCount": 5,
            "providers": {"llm": "anthropic"},
            "latencies": [400.0, 450.0, 500.0],
        }

        request = mock_request(method="GET", query={})
        response = await latency_harness_api.handle_list_metric_sessions(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "sessions" in data

    @pytest.mark.asyncio
    async def test_list_sessions_with_filters(self, mock_request):
        """Test listing sessions with filters."""
        # Set up some test data with proper structure
        latency_harness_api._metrics_by_session.clear()
        latency_harness_api._metrics_by_session["session_ios"] = {
            "sessionId": "session_ios",
            "client": "ios",
            "clientId": "device-ios",
            "clientName": None,
            "firstSeen": datetime.now().isoformat(),
            "lastSeen": datetime.now().isoformat(),
            "metricsCount": 3,
            "providers": {"llm": "anthropic"},
            "latencies": [400.0, 450.0, 500.0],
        }
        latency_harness_api._metrics_by_session["session_web"] = {
            "sessionId": "session_web",
            "client": "web",
            "clientId": "browser-123",
            "clientName": None,
            "firstSeen": datetime.now().isoformat(),
            "lastSeen": datetime.now().isoformat(),
            "metricsCount": 2,
            "providers": {"llm": "openai"},
            "latencies": [500.0, 600.0],
        }

        request = mock_request(method="GET", query={"client": "ios", "limit": "10"})
        response = await latency_harness_api.handle_list_metric_sessions(request)

        assert response.status == 200
        data = json.loads(response.body)
        # Should only return iOS sessions
        assert len(data["sessions"]) == 1
        assert data["sessions"][0]["sessionId"] == "session_ios"


class TestHandleGetMetricsSummary:
    """Tests for handle_get_metrics_summary endpoint."""

    @pytest.mark.asyncio
    async def test_get_summary_success(self, mock_request):
        """Test getting metrics summary."""
        # Set up some test data
        latency_harness_api._ingested_metrics.clear()
        latency_harness_api._ingested_metrics["device-123"] = [
            {
                "client": "ios",
                "sessionId": "s1",
                "metrics": {"e2e_latency_ms": 450.0},
                "providers": {"llm": "anthropic"},
            }
        ]

        request = mock_request(method="GET", query={})
        response = await latency_harness_api.handle_get_metrics_summary(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "totalMetrics" in data

    @pytest.mark.asyncio
    async def test_get_summary_with_client_filter(self, mock_request):
        """Test getting summary with client filter."""
        request = mock_request(method="GET", query={"client": "ios", "hours": "12"})
        response = await latency_harness_api.handle_get_metrics_summary(request)

        assert response.status == 200


class TestHandleGetClientMetrics:
    """Tests for handle_get_client_metrics endpoint."""

    @pytest.mark.asyncio
    async def test_get_client_metrics_success(self, mock_request):
        """Test getting client-specific metrics."""
        latency_harness_api._ingested_metrics.clear()
        latency_harness_api._ingested_metrics["device-123"] = [
            {"timestamp": datetime.now().isoformat(), "metrics": {"e2e_latency_ms": 450.0}}
        ]

        request = mock_request(method="GET", match_info={"client_id": "device-123"}, query={})
        response = await latency_harness_api.handle_get_client_metrics(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["clientId"] == "device-123"

    @pytest.mark.asyncio
    async def test_get_client_metrics_not_found(self, mock_request):
        """Test getting metrics for non-existent client."""
        latency_harness_api._ingested_metrics.clear()

        request = mock_request(method="GET", match_info={"client_id": "nonexistent"}, query={})
        response = await latency_harness_api.handle_get_client_metrics(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["metricsCount"] == 0


# =============================================================================
# Helper Function Tests
# =============================================================================


class TestGetOrchestrator:
    """Tests for get_orchestrator helper."""

    @patch("latency_harness_api._orchestrator", None)
    @patch("latency_harness_api.LatencyTestOrchestrator")
    def test_creates_orchestrator_on_first_call(self, mock_class):
        """Test that orchestrator is created on first call."""
        mock_class.return_value = MockOrchestrator()
        result = latency_harness_api.get_orchestrator()
        mock_class.assert_called_once()


class TestBroadcastLatencyUpdate:
    """Tests for broadcast_latency_update function."""

    @pytest.mark.asyncio
    async def test_broadcast_no_websockets(self):
        """Test broadcast when no WebSockets connected."""
        original_ws = latency_harness_api._latency_websockets.copy()
        try:
            latency_harness_api._latency_websockets.clear()
            # Should not raise
            await latency_harness_api.broadcast_latency_update("test", {"data": "value"})
        finally:
            latency_harness_api._latency_websockets = original_ws

    @pytest.mark.asyncio
    async def test_broadcast_with_failing_websocket(self):
        """Test broadcast removes failing WebSockets."""
        original_ws = latency_harness_api._latency_websockets.copy()
        try:
            latency_harness_api._latency_websockets.clear()
            mock_ws = MagicMock()
            mock_ws.send_str = AsyncMock(side_effect=Exception("Connection closed"))
            latency_harness_api._latency_websockets.add(mock_ws)

            await latency_harness_api.broadcast_latency_update("test", {"data": "value"})

            # The failing WebSocket should be removed
            assert mock_ws not in latency_harness_api._latency_websockets
        finally:
            latency_harness_api._latency_websockets = original_ws


# =============================================================================
# Route Registration Tests
# =============================================================================


class TestRegisterRoutes:
    """Tests for route registration."""

    def test_register_latency_harness_routes(self):
        """Test that all routes are registered correctly."""
        app = web.Application()

        latency_harness_api.register_latency_harness_routes(app)

        route_paths = [r.resource.canonical for r in app.router.routes()]

        # Test Suite routes
        assert "/api/latency-tests/suites" in route_paths
        assert "/api/latency-tests/suites/{suite_id}" in route_paths

        # Test Run routes
        assert "/api/latency-tests/runs" in route_paths
        assert "/api/latency-tests/runs/{run_id}" in route_paths
        assert "/api/latency-tests/runs/{run_id}/results" in route_paths
        assert "/api/latency-tests/runs/{run_id}/analysis" in route_paths
        assert "/api/latency-tests/runs/{run_id}/export" in route_paths

        # Client routes
        assert "/api/latency-tests/clients" in route_paths
        assert "/api/latency-tests/heartbeat" in route_paths
        assert "/api/latency-tests/results" in route_paths

        # Baseline routes
        assert "/api/latency-tests/baselines" in route_paths
        assert "/api/latency-tests/baselines/{baseline_id}/check" in route_paths

        # Target discovery
        assert "/api/latency-tests/targets" in route_paths

        # WebSocket
        assert "/api/latency-tests/ws" in route_paths

        # Mass test orchestrator
        assert "/api/test-orchestrator/start" in route_paths
        assert "/api/test-orchestrator/status/{run_id}" in route_paths
        assert "/api/test-orchestrator/stop/{run_id}" in route_paths
        assert "/api/test-orchestrator/runs" in route_paths

        # Metrics ingestion
        assert "/api/metrics/ingest" in route_paths
        assert "/api/metrics/sessions" in route_paths
        assert "/api/metrics/summary" in route_paths
        assert "/api/metrics/clients/{client_id}" in route_paths
