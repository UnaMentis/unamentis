"""
Tests for Reprocess API routes.
"""
import pytest
from datetime import datetime
from unittest.mock import MagicMock, AsyncMock, patch
from aiohttp import web


class MockAnalysis:
    """Mock curriculum analysis result."""

    def __init__(self, curriculum_id: str):
        self.curriculum_id = curriculum_id
        self.issues_found = 5
        self.quality_score = 0.85

    def to_dict(self):
        return {
            "curriculum_id": self.curriculum_id,
            "issues_found": self.issues_found,
            "quality_score": self.quality_score,
        }


class MockReprocessProgress:
    """Mock reprocess job progress."""

    def __init__(self, job_id: str, status: str = "running"):
        self.id = job_id
        self.status = MagicMock(value=status)
        self.overall_progress = 0.5
        self.current_stage = "analyzing"
        self.started_at = datetime(2024, 1, 1)
        self.fixes_applied = []
        self.config = MagicMock()
        self.config.curriculum_id = "physics-101"

    def to_dict(self):
        return {
            "id": self.id,
            "status": self.status.value,
            "overall_progress": self.overall_progress,
            "current_stage": self.current_stage,
        }


class MockPreview:
    """Mock reprocess preview result."""

    def __init__(self, curriculum_id: str):
        self.curriculum_id = curriculum_id
        self.proposed_changes = []

    def to_dict(self):
        return {
            "curriculum_id": self.curriculum_id,
            "proposed_changes": self.proposed_changes,
        }


class MockOrchestrator:
    """Mock reprocess orchestrator."""

    def __init__(self):
        self._jobs = {}
        self._analyses = {}

    async def analyze_curriculum(self, curriculum_id, force=False):
        if curriculum_id == "not_found":
            raise ValueError("Curriculum not found")
        analysis = MockAnalysis(curriculum_id)
        self._analyses[curriculum_id] = analysis
        return analysis

    def get_cached_analysis(self, curriculum_id):
        return self._analyses.get(curriculum_id)

    async def start_reprocess(self, config):
        job_id = "reprocess-123"
        self._jobs[job_id] = MockReprocessProgress(job_id)
        return job_id

    def list_jobs(self, status=None, curriculum_id=None):
        jobs = list(self._jobs.values())
        if status:
            jobs = [j for j in jobs if j.status.value == status.value]
        if curriculum_id:
            jobs = [j for j in jobs if j.config.curriculum_id == curriculum_id]
        return jobs

    def get_progress(self, job_id):
        return self._jobs.get(job_id)

    async def cancel_job(self, job_id):
        if job_id in self._jobs:
            del self._jobs[job_id]
            return True
        return False

    async def preview_reprocess(self, config):
        if config.curriculum_id == "not_found":
            raise ValueError("Curriculum not found")
        return MockPreview(config.curriculum_id)


class MockState:
    """Mock server state."""

    def __init__(self):
        self.curriculum_dir = "/path/to/curriculum"
        self.curriculum_raw = {}


# Import the module under test
import reprocess_api


@pytest.fixture
def mock_app():
    """Create a mock aiohttp application."""
    app = web.Application()
    app["state"] = MockState()
    return app


@pytest.fixture
def mock_request(mock_app):
    """Create a factory for mock requests."""
    def _make_request(method="GET", json_data=None, query=None, match_info=None, has_body=True):
        request = MagicMock(spec=web.Request)
        request.app = mock_app
        request.method = method
        request.query = query or {}
        request.match_info = match_info or {}
        request.can_read_body = has_body and json_data is not None

        if json_data is not None:
            async def mock_json():
                return json_data
            request.json = mock_json
        else:
            async def mock_json():
                raise ValueError("No JSON")
            request.json = mock_json

        return request
    return _make_request


# =============================================================================
# Analysis Routes Tests
# =============================================================================

class TestHandleAnalyzeCurriculum:
    """Tests for handle_analyze_curriculum endpoint."""

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_analyze_success(self, mock_get_orch, mock_request):
        """Test successful curriculum analysis."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            method="POST",
            match_info={"curriculum_id": "physics-101"},
            json_data={"force": False}
        )
        response = await reprocess_api.handle_analyze_curriculum(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_analyze_force(self, mock_get_orch, mock_request):
        """Test forced re-analysis."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            method="POST",
            match_info={"curriculum_id": "physics-101"},
            json_data={"force": True}
        )
        response = await reprocess_api.handle_analyze_curriculum(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_analyze_no_body(self, mock_get_orch, mock_request):
        """Test analysis without request body."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            method="POST",
            match_info={"curriculum_id": "physics-101"},
            has_body=False
        )
        response = await reprocess_api.handle_analyze_curriculum(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_analyze_not_found(self, mock_get_orch, mock_request):
        """Test analysis of non-existent curriculum."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            method="POST",
            match_info={"curriculum_id": "not_found"}
        )
        response = await reprocess_api.handle_analyze_curriculum(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_analyze_error(self, mock_get_orch, mock_request):
        """Test error handling in analysis."""
        orch = MockOrchestrator()
        orch.analyze_curriculum = AsyncMock(side_effect=Exception("Analysis error"))
        mock_get_orch.return_value = orch

        request = mock_request(
            method="POST",
            match_info={"curriculum_id": "physics-101"}
        )
        response = await reprocess_api.handle_analyze_curriculum(request)

        assert response.status == 500


class TestHandleGetAnalysis:
    """Tests for handle_get_analysis endpoint."""

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_get_analysis_cached(self, mock_get_orch, mock_request):
        """Test getting cached analysis."""
        orch = MockOrchestrator()
        orch._analyses["physics-101"] = MockAnalysis("physics-101")
        mock_get_orch.return_value = orch

        request = mock_request(
            method="GET",
            match_info={"curriculum_id": "physics-101"}
        )
        response = await reprocess_api.handle_get_analysis(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_get_analysis_not_cached(self, mock_get_orch, mock_request):
        """Test getting analysis when not cached."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            method="GET",
            match_info={"curriculum_id": "physics-101"}
        )
        response = await reprocess_api.handle_get_analysis(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_get_analysis_error(self, mock_get_orch, mock_request):
        """Test error handling in get analysis."""
        mock_get_orch.side_effect = Exception("Orchestrator error")

        request = mock_request(
            method="GET",
            match_info={"curriculum_id": "physics-101"}
        )
        response = await reprocess_api.handle_get_analysis(request)

        assert response.status == 500


# =============================================================================
# Job Routes Tests
# =============================================================================

class TestHandleStartJob:
    """Tests for handle_start_job endpoint."""

    @pytest.mark.asyncio
    @patch('reprocess_api.ReprocessConfig')
    @patch('reprocess_api.get_orchestrator')
    async def test_start_job_success(self, mock_get_orch, mock_config, mock_request):
        """Test successful job start."""
        mock_get_orch.return_value = MockOrchestrator()
        config = MagicMock()
        config.curriculum_id = "physics-101"
        mock_config.from_dict.return_value = config

        request = mock_request(json_data={
            "curriculumId": "physics-101",
            "fixImages": True,
        })
        response = await reprocess_api.handle_start_job(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.ReprocessConfig')
    async def test_start_job_missing_field(self, mock_config, mock_request):
        """Test job start with missing required field."""
        mock_config.from_dict.side_effect = KeyError("curriculumId")

        request = mock_request(json_data={})
        response = await reprocess_api.handle_start_job(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_start_job_error(self, mock_get_orch, mock_request):
        """Test error handling in job start."""
        mock_get_orch.side_effect = Exception("Orchestrator error")

        request = mock_request(json_data={"curriculumId": "physics-101"})
        response = await reprocess_api.handle_start_job(request)

        assert response.status == 500


class TestHandleListJobs:
    """Tests for handle_list_jobs endpoint."""

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_list_jobs_success(self, mock_get_orch, mock_request):
        """Test successful job list."""
        orch = MockOrchestrator()
        orch._jobs["reprocess-123"] = MockReprocessProgress("reprocess-123")
        mock_get_orch.return_value = orch

        request = mock_request(method="GET")
        response = await reprocess_api.handle_list_jobs(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.ReprocessStatus')
    @patch('reprocess_api.get_orchestrator')
    async def test_list_jobs_with_status_filter(
        self, mock_get_orch, mock_status, mock_request
    ):
        """Test job list with status filter."""
        mock_get_orch.return_value = MockOrchestrator()
        mock_status.return_value = MagicMock(value="running")

        request = mock_request(
            method="GET",
            query={"status": "running"}
        )
        response = await reprocess_api.handle_list_jobs(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_list_jobs_with_curriculum_filter(self, mock_get_orch, mock_request):
        """Test job list with curriculum filter."""
        orch = MockOrchestrator()
        orch._jobs["reprocess-123"] = MockReprocessProgress("reprocess-123")
        mock_get_orch.return_value = orch

        request = mock_request(
            method="GET",
            query={"curriculumId": "physics-101"}
        )
        response = await reprocess_api.handle_list_jobs(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.ReprocessStatus')
    @patch('reprocess_api.get_orchestrator')
    async def test_list_jobs_invalid_status(
        self, mock_get_orch, mock_status, mock_request
    ):
        """Test job list with invalid status."""
        mock_get_orch.return_value = MockOrchestrator()
        mock_status.side_effect = ValueError("Invalid status")

        request = mock_request(
            method="GET",
            query={"status": "invalid"}
        )
        response = await reprocess_api.handle_list_jobs(request)

        # Invalid status is silently ignored, should still succeed
        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_list_jobs_error(self, mock_get_orch, mock_request):
        """Test error handling in job list."""
        mock_get_orch.side_effect = Exception("Orchestrator error")

        request = mock_request(method="GET")
        response = await reprocess_api.handle_list_jobs(request)

        assert response.status == 500


class TestHandleGetJob:
    """Tests for handle_get_job endpoint."""

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_get_job_success(self, mock_get_orch, mock_request):
        """Test successful job retrieval."""
        orch = MockOrchestrator()
        orch._jobs["reprocess-123"] = MockReprocessProgress("reprocess-123")
        mock_get_orch.return_value = orch

        request = mock_request(
            method="GET",
            match_info={"job_id": "reprocess-123"}
        )
        response = await reprocess_api.handle_get_job(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_get_job_not_found(self, mock_get_orch, mock_request):
        """Test job not found."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            method="GET",
            match_info={"job_id": "unknown"}
        )
        response = await reprocess_api.handle_get_job(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_get_job_error(self, mock_get_orch, mock_request):
        """Test error handling in get job."""
        mock_get_orch.side_effect = Exception("Orchestrator error")

        request = mock_request(
            method="GET",
            match_info={"job_id": "reprocess-123"}
        )
        response = await reprocess_api.handle_get_job(request)

        assert response.status == 500


class TestHandleCancelJob:
    """Tests for handle_cancel_job endpoint."""

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_cancel_job_success(self, mock_get_orch, mock_request):
        """Test successful job cancel."""
        orch = MockOrchestrator()
        orch._jobs["reprocess-123"] = MockReprocessProgress("reprocess-123")
        mock_get_orch.return_value = orch

        request = mock_request(
            method="DELETE",
            match_info={"job_id": "reprocess-123"}
        )
        response = await reprocess_api.handle_cancel_job(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_cancel_job_not_found(self, mock_get_orch, mock_request):
        """Test cancel of non-existent job."""
        mock_get_orch.return_value = MockOrchestrator()

        request = mock_request(
            method="DELETE",
            match_info={"job_id": "unknown"}
        )
        response = await reprocess_api.handle_cancel_job(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_cancel_job_error(self, mock_get_orch, mock_request):
        """Test error handling in cancel job."""
        mock_get_orch.side_effect = Exception("Orchestrator error")

        request = mock_request(
            method="DELETE",
            match_info={"job_id": "reprocess-123"}
        )
        response = await reprocess_api.handle_cancel_job(request)

        assert response.status == 500


# =============================================================================
# Preview Route Tests
# =============================================================================

class TestHandlePreview:
    """Tests for handle_preview endpoint."""

    @pytest.mark.asyncio
    @patch('reprocess_api.ReprocessConfig')
    @patch('reprocess_api.get_orchestrator')
    async def test_preview_success(self, mock_get_orch, mock_config, mock_request):
        """Test successful preview."""
        mock_get_orch.return_value = MockOrchestrator()
        config = MagicMock()
        config.curriculum_id = "physics-101"
        mock_config.from_dict.return_value = config

        request = mock_request(
            method="POST",
            match_info={"curriculum_id": "physics-101"},
            json_data={"fixImages": True}
        )
        response = await reprocess_api.handle_preview(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.ReprocessConfig')
    @patch('reprocess_api.get_orchestrator')
    async def test_preview_no_body(self, mock_get_orch, mock_config, mock_request):
        """Test preview without request body."""
        mock_get_orch.return_value = MockOrchestrator()
        config = MagicMock()
        config.curriculum_id = "physics-101"
        mock_config.from_dict.return_value = config

        request = mock_request(
            method="POST",
            match_info={"curriculum_id": "physics-101"},
            has_body=False
        )
        response = await reprocess_api.handle_preview(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('reprocess_api.ReprocessConfig')
    @patch('reprocess_api.get_orchestrator')
    async def test_preview_not_found(self, mock_get_orch, mock_config, mock_request):
        """Test preview of non-existent curriculum."""
        mock_get_orch.return_value = MockOrchestrator()
        config = MagicMock()
        config.curriculum_id = "not_found"
        mock_config.from_dict.return_value = config

        request = mock_request(
            method="POST",
            match_info={"curriculum_id": "not_found"},
            json_data={}
        )
        response = await reprocess_api.handle_preview(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('reprocess_api.get_orchestrator')
    async def test_preview_error(self, mock_get_orch, mock_request):
        """Test error handling in preview."""
        mock_get_orch.side_effect = Exception("Orchestrator error")

        request = mock_request(
            method="POST",
            match_info={"curriculum_id": "physics-101"},
            json_data={}
        )
        response = await reprocess_api.handle_preview(request)

        assert response.status == 500


# =============================================================================
# Helper Function Tests
# =============================================================================

class TestGetOrchestrator:
    """Tests for get_orchestrator helper."""

    @patch('reprocess_api._orchestrator', None)
    @patch('reprocess_api.ReprocessOrchestrator')
    def test_creates_orchestrator_on_first_call(self, mock_class, mock_app):
        """Test that orchestrator is created on first call."""
        mock_class.return_value = MockOrchestrator()
        result = reprocess_api.get_orchestrator(mock_app)
        mock_class.assert_called_once()

    @patch('reprocess_api._orchestrator', None)
    @patch('reprocess_api.ReprocessOrchestrator')
    def test_creates_orchestrator_without_state(self, mock_class, mock_app):
        """Test orchestrator creation without app state."""
        mock_app._state = {}  # No state
        mock_class.return_value = MockOrchestrator()
        result = reprocess_api.get_orchestrator(mock_app)
        mock_class.assert_called_once()


# =============================================================================
# Route Registration Tests
# =============================================================================

class TestRegisterRoutes:
    """Tests for route registration."""

    def test_register_reprocess_routes(self, mock_app):
        """Test that reprocess routes are registered correctly."""
        reprocess_api.register_reprocess_routes(mock_app)

        route_paths = [r.resource.canonical for r in mock_app.router.routes()]

        assert "/api/reprocess/analyze/{curriculum_id}" in route_paths
        assert "/api/reprocess/analysis/{curriculum_id}" in route_paths
        assert "/api/reprocess/jobs" in route_paths
        assert "/api/reprocess/jobs/{job_id}" in route_paths
        assert "/api/reprocess/preview/{curriculum_id}" in route_paths
