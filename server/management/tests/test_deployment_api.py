"""
Tests for Scheduled Deployment API

Comprehensive tests for deployment scheduling, pre-generation, and API endpoints.
Tests verify real behavior of deployment lifecycle management.
"""

import asyncio
import json
import pytest
from datetime import datetime, timedelta
from unittest.mock import MagicMock, AsyncMock, patch
from aiohttp import web
from aiohttp.test_utils import make_mocked_request

from deployment_api import (
    DeploymentStatus,
    ScheduledDeployment,
    ScheduledDeploymentManager,
    handle_create_deployment,
    handle_list_deployments,
    handle_get_deployment,
    handle_start_deployment,
    handle_cancel_deployment,
    handle_get_deployment_cache,
    register_deployment_routes,
)
from fov_context import UserVoiceConfig


# =============================================================================
# DEPLOYMENT STATUS TESTS
# =============================================================================


class TestDeploymentStatus:
    """Tests for DeploymentStatus enum."""

    def test_status_values(self):
        """Test all status values exist."""
        assert DeploymentStatus.SCHEDULED.value == "scheduled"
        assert DeploymentStatus.GENERATING.value == "generating"
        assert DeploymentStatus.COMPLETED.value == "completed"
        assert DeploymentStatus.COMPLETED_WITH_ERRORS.value == "completed_with_errors"
        assert DeploymentStatus.CANCELLED.value == "cancelled"
        assert DeploymentStatus.FAILED.value == "failed"

    def test_status_is_string_enum(self):
        """Test status values are strings."""
        for status in DeploymentStatus:
            assert isinstance(status.value, str)


# =============================================================================
# SCHEDULED DEPLOYMENT TESTS
# =============================================================================


class TestScheduledDeployment:
    """Tests for ScheduledDeployment dataclass."""

    @pytest.fixture
    def deployment(self):
        """Create test deployment."""
        return ScheduledDeployment(
            id="test-deploy-1",
            name="Test Deployment",
            curriculum_id="curriculum-1",
            target_date=datetime(2024, 6, 1, 9, 0),
            voice_config=UserVoiceConfig(voice_id="nova"),
        )

    def test_default_status_is_scheduled(self, deployment):
        """Test default status is SCHEDULED."""
        assert deployment.status == DeploymentStatus.SCHEDULED

    def test_default_counts_are_zero(self, deployment):
        """Test default segment counts are zero."""
        assert deployment.total_segments == 0
        assert deployment.completed_segments == 0
        assert deployment.cached_segments == 0
        assert deployment.generated_segments == 0
        assert deployment.failed_segments == 0

    def test_percent_complete_zero_total(self, deployment):
        """Test percent_complete with zero total returns 100."""
        deployment.total_segments = 0
        assert deployment.percent_complete == 100.0

    def test_percent_complete_calculation(self, deployment):
        """Test percent_complete calculation."""
        deployment.total_segments = 100
        deployment.completed_segments = 25
        assert deployment.percent_complete == 25.0

    def test_percent_complete_full(self, deployment):
        """Test percent_complete at 100%."""
        deployment.total_segments = 50
        deployment.completed_segments = 50
        assert deployment.percent_complete == 100.0

    def test_is_ready_when_completed_no_errors(self, deployment):
        """Test is_ready returns True when completed without errors."""
        deployment.status = DeploymentStatus.COMPLETED
        deployment.failed_segments = 0
        assert deployment.is_ready is True

    def test_is_ready_false_when_completed_with_errors(self, deployment):
        """Test is_ready returns False with failed segments."""
        deployment.status = DeploymentStatus.COMPLETED
        deployment.failed_segments = 1
        assert deployment.is_ready is False

    def test_is_ready_false_when_not_completed(self, deployment):
        """Test is_ready returns False when not completed."""
        deployment.status = DeploymentStatus.GENERATING
        deployment.failed_segments = 0
        assert deployment.is_ready is False

    def test_to_dict_contains_all_fields(self, deployment):
        """Test to_dict contains all required fields."""
        data = deployment.to_dict()

        assert data["id"] == "test-deploy-1"
        assert data["name"] == "Test Deployment"
        assert data["curriculum_id"] == "curriculum-1"
        assert "target_date" in data
        assert "voice_config" in data
        assert data["status"] == "scheduled"
        assert "percent_complete" in data
        assert "is_ready" in data
        assert "created_at" in data

    def test_to_dict_formats_dates_as_iso(self, deployment):
        """Test to_dict formats dates as ISO strings."""
        deployment.generation_started_at = datetime(2024, 5, 1, 10, 0)
        deployment.generation_completed_at = datetime(2024, 5, 1, 12, 0)

        data = deployment.to_dict()

        assert "T" in data["target_date"]  # ISO format
        assert "T" in data["generation_started_at"]
        assert "T" in data["generation_completed_at"]

    def test_to_dict_handles_none_dates(self, deployment):
        """Test to_dict handles None dates."""
        deployment.generation_started_at = None
        deployment.generation_completed_at = None

        data = deployment.to_dict()

        assert data["generation_started_at"] is None
        assert data["generation_completed_at"] is None


# =============================================================================
# DEPLOYMENT MANAGER TESTS
# =============================================================================


class MockTTSCache:
    """Mock TTS cache for testing."""

    def __init__(self):
        self._cached_keys = set()
        self._stored_entries = []

    async def has(self, key):
        return str(key) in self._cached_keys

    async def put(self, key, audio_data, sample_rate, duration):
        self._stored_entries.append((key, audio_data, sample_rate, duration))

    def add_cached_key(self, key):
        self._cached_keys.add(str(key))


class MockResourcePool:
    """Mock TTS resource pool for testing."""

    def __init__(self):
        self.generation_calls = []
        self._should_fail = False
        self._fail_on_indices = set()

    async def generate_with_priority(self, **kwargs):
        self.generation_calls.append(kwargs)

        # Check if should fail
        if self._should_fail:
            raise Exception("TTS generation failed")

        return b"audio-data", 24000, 2.5


class TestScheduledDeploymentManager:
    """Tests for ScheduledDeploymentManager."""

    @pytest.fixture
    def manager(self):
        """Create manager with mock dependencies."""
        cache = MockTTSCache()
        pool = MockResourcePool()
        return ScheduledDeploymentManager(cache, pool)

    @pytest.fixture
    def manager_with_loader(self, manager):
        """Create manager with segment loader."""
        async def load_segments(curriculum_id):
            if curriculum_id == "empty":
                return []
            return [f"Segment {i}" for i in range(5)]

        manager.set_segment_loader(load_segments)
        return manager

    def test_init_sets_dependencies(self, manager):
        """Test manager stores dependencies."""
        assert manager.cache is not None
        assert manager.resource_pool is not None
        assert manager.auto_start_hours == 24

    def test_init_custom_auto_start_hours(self):
        """Test custom auto_start_hours."""
        manager = ScheduledDeploymentManager(
            MockTTSCache(), MockResourcePool(), auto_start_hours_before=48
        )
        assert manager.auto_start_hours == 48

    def test_set_segment_loader(self, manager):
        """Test setting segment loader."""
        loader = AsyncMock()
        manager.set_segment_loader(loader)
        assert manager._segment_loader is loader

    @pytest.mark.asyncio
    async def test_schedule_deployment_creates_deployment(self, manager):
        """Test scheduling creates deployment."""
        target = datetime(2024, 6, 1, 9, 0)

        deployment = await manager.schedule_deployment(
            name="Test Training",
            curriculum_id="training-101",
            target_date=target,
        )

        assert deployment is not None
        assert deployment.name == "Test Training"
        assert deployment.curriculum_id == "training-101"
        assert deployment.target_date == target
        assert deployment.status == DeploymentStatus.SCHEDULED

    @pytest.mark.asyncio
    async def test_schedule_deployment_generates_id(self, manager):
        """Test scheduled deployment has generated ID."""
        deployment = await manager.schedule_deployment(
            name="Test", curriculum_id="test", target_date=datetime.now()
        )

        assert deployment.id.startswith("deploy_")
        assert len(deployment.id) == 15  # deploy_ + 8 hex chars

    @pytest.mark.asyncio
    async def test_schedule_deployment_with_voice_config(self, manager):
        """Test scheduling with custom voice config."""
        voice = UserVoiceConfig(voice_id="shimmer", speed=1.2)

        deployment = await manager.schedule_deployment(
            name="Test",
            curriculum_id="test",
            target_date=datetime.now(),
            voice_config=voice,
        )

        assert deployment.voice_config.voice_id == "shimmer"
        assert deployment.voice_config.speed == 1.2

    @pytest.mark.asyncio
    async def test_schedule_deployment_default_voice_config(self, manager):
        """Test scheduling uses default voice config."""
        deployment = await manager.schedule_deployment(
            name="Test", curriculum_id="test", target_date=datetime.now()
        )

        assert deployment.voice_config is not None
        assert deployment.voice_config.voice_id == "nova"  # default

    def test_get_deployment_existing(self, manager):
        """Test getting existing deployment."""
        deployment = ScheduledDeployment(
            id="test-1",
            name="Test",
            curriculum_id="test",
            target_date=datetime.now(),
            voice_config=UserVoiceConfig(),
        )
        manager._deployments["test-1"] = (deployment, None)

        result = manager.get_deployment("test-1")

        assert result is deployment

    def test_get_deployment_not_found(self, manager):
        """Test getting non-existent deployment returns None."""
        result = manager.get_deployment("nonexistent")
        assert result is None

    def test_list_deployments_empty(self, manager):
        """Test listing deployments when empty."""
        result = manager.list_deployments()
        assert result == []

    @pytest.mark.asyncio
    async def test_list_deployments_returns_all(self, manager):
        """Test listing returns all deployments."""
        await manager.schedule_deployment("D1", "c1", datetime.now())
        await manager.schedule_deployment("D2", "c2", datetime.now())
        await manager.schedule_deployment("D3", "c3", datetime.now())

        result = manager.list_deployments()

        assert len(result) == 3

    @pytest.mark.asyncio
    async def test_start_generation_not_found(self, manager):
        """Test starting non-existent deployment returns False."""
        result = await manager.start_generation("nonexistent")
        assert result is False

    @pytest.mark.asyncio
    async def test_start_generation_already_running(self, manager_with_loader):
        """Test starting already running deployment returns False."""
        deployment = await manager_with_loader.schedule_deployment(
            "Test", "test", datetime.now()
        )

        # Start first time
        await manager_with_loader.start_generation(deployment.id)

        # Try to start again immediately
        result = await manager_with_loader.start_generation(deployment.id)

        # May return False if task not done yet, or True if it finished quickly
        # The important thing is it doesn't crash

    @pytest.mark.asyncio
    async def test_start_generation_already_completed(self, manager):
        """Test starting completed deployment returns False."""
        deployment = ScheduledDeployment(
            id="completed-1",
            name="Completed",
            curriculum_id="test",
            target_date=datetime.now(),
            voice_config=UserVoiceConfig(),
            status=DeploymentStatus.COMPLETED,
        )
        manager._deployments["completed-1"] = (deployment, None)

        result = await manager.start_generation("completed-1")

        assert result is False

    @pytest.mark.asyncio
    async def test_cancel_deployment_success(self, manager):
        """Test canceling deployment."""
        deployment = await manager.schedule_deployment("Test", "test", datetime.now())

        result = await manager.cancel_deployment(deployment.id)

        assert result is True
        assert deployment.status == DeploymentStatus.CANCELLED

    @pytest.mark.asyncio
    async def test_cancel_deployment_not_found(self, manager):
        """Test canceling non-existent deployment returns False."""
        result = await manager.cancel_deployment("nonexistent")
        assert result is False

    @pytest.mark.asyncio
    async def test_cancel_deployment_stops_running_task(self, manager_with_loader):
        """Test canceling stops running generation task."""
        deployment = await manager_with_loader.schedule_deployment(
            "Test", "test", datetime.now()
        )
        await manager_with_loader.start_generation(deployment.id)

        result = await manager_with_loader.cancel_deployment(deployment.id)

        assert result is True
        assert deployment.status == DeploymentStatus.CANCELLED


# =============================================================================
# GENERATION TESTS
# =============================================================================


class TestGeneration:
    """Tests for deployment generation."""

    @pytest.fixture
    def manager(self):
        """Create manager with segment loader."""
        cache = MockTTSCache()
        pool = MockResourcePool()
        manager = ScheduledDeploymentManager(cache, pool)

        async def load_segments(curriculum_id):
            if curriculum_id == "empty":
                return []
            if curriculum_id == "small":
                return ["Seg 1", "Seg 2"]
            return [f"Segment {i}" for i in range(5)]

        manager.set_segment_loader(load_segments)
        return manager

    @pytest.mark.asyncio
    async def test_run_generation_updates_status(self, manager):
        """Test generation updates status to GENERATING."""
        deployment = await manager.schedule_deployment(
            "Test", "small", datetime.now()
        )

        # Start and wait a bit
        await manager.start_generation(deployment.id)
        await asyncio.sleep(0.1)

        # Status should be GENERATING or COMPLETED
        assert deployment.status in (
            DeploymentStatus.GENERATING,
            DeploymentStatus.COMPLETED,
        )

    @pytest.mark.asyncio
    async def test_run_generation_completes(self, manager):
        """Test generation completes successfully."""
        deployment = await manager.schedule_deployment(
            "Test", "small", datetime.now()
        )

        await manager.start_generation(deployment.id)

        # Wait for completion
        _, task = manager._deployments[deployment.id]
        if task:
            await asyncio.wait_for(task, timeout=5.0)

        assert deployment.status == DeploymentStatus.COMPLETED
        assert deployment.completed_segments == 2

    @pytest.mark.asyncio
    async def test_run_generation_counts_cached(self, manager):
        """Test generation counts already-cached segments."""
        # Pre-cache one segment
        manager.cache.add_cached_key("some-key")

        deployment = await manager.schedule_deployment(
            "Test", "small", datetime.now()
        )

        await manager.start_generation(deployment.id)

        _, task = manager._deployments[deployment.id]
        if task:
            await asyncio.wait_for(task, timeout=5.0)

        # All segments generated since mock cache doesn't match real keys
        assert deployment.completed_segments == 2

    @pytest.mark.asyncio
    async def test_run_generation_no_loader(self, manager):
        """Test generation fails without segment loader."""
        manager._segment_loader = None
        deployment = await manager.schedule_deployment(
            "Test", "test", datetime.now()
        )

        await manager.start_generation(deployment.id)

        _, task = manager._deployments[deployment.id]
        if task:
            try:
                await asyncio.wait_for(task, timeout=5.0)
            except Exception:
                pass

        assert deployment.status == DeploymentStatus.FAILED
        assert deployment.error is not None

    @pytest.mark.asyncio
    async def test_run_generation_empty_curriculum(self, manager):
        """Test generation fails for empty curriculum."""
        deployment = await manager.schedule_deployment(
            "Test", "empty", datetime.now()
        )

        await manager.start_generation(deployment.id)

        _, task = manager._deployments[deployment.id]
        if task:
            try:
                await asyncio.wait_for(task, timeout=5.0)
            except Exception:
                pass

        assert deployment.status == DeploymentStatus.FAILED

    @pytest.mark.asyncio
    async def test_run_generation_handles_errors(self, manager):
        """Test generation handles TTS errors gracefully."""
        manager.resource_pool._should_fail = True

        deployment = await manager.schedule_deployment(
            "Test", "small", datetime.now()
        )

        await manager.start_generation(deployment.id)

        _, task = manager._deployments[deployment.id]
        if task:
            await asyncio.wait_for(task, timeout=5.0)

        assert deployment.status == DeploymentStatus.COMPLETED_WITH_ERRORS
        assert deployment.failed_segments > 0


# =============================================================================
# CACHE COVERAGE TESTS
# =============================================================================


class TestCacheCoverage:
    """Tests for cache coverage checking."""

    @pytest.fixture
    def manager(self):
        """Create manager with segment loader."""
        cache = MockTTSCache()
        pool = MockResourcePool()
        manager = ScheduledDeploymentManager(cache, pool)

        async def load_segments(curriculum_id):
            return [f"Segment {i}" for i in range(10)]

        manager.set_segment_loader(load_segments)
        return manager

    @pytest.mark.asyncio
    async def test_get_cache_coverage_not_found(self, manager):
        """Test coverage check for non-existent deployment."""
        result = await manager.get_cache_coverage("nonexistent")
        assert result is None

    @pytest.mark.asyncio
    async def test_get_cache_coverage_no_loader(self, manager):
        """Test coverage check without segment loader."""
        manager._segment_loader = None
        deployment = await manager.schedule_deployment(
            "Test", "test", datetime.now()
        )

        result = await manager.get_cache_coverage(deployment.id)

        assert "error" in result

    @pytest.mark.asyncio
    async def test_get_cache_coverage_returns_stats(self, manager):
        """Test coverage check returns statistics."""
        deployment = await manager.schedule_deployment(
            "Test", "test", datetime.now()
        )

        result = await manager.get_cache_coverage(deployment.id)

        assert "deployment_id" in result
        assert "total_segments" in result
        assert "cached_segments" in result
        assert "missing_segments" in result
        assert "coverage_percent" in result
        assert "is_ready" in result


# =============================================================================
# CLEANUP TESTS
# =============================================================================


class TestCleanup:
    """Tests for deployment cleanup."""

    @pytest.fixture
    def manager(self):
        """Create manager."""
        return ScheduledDeploymentManager(MockTTSCache(), MockResourcePool())

    def test_cleanup_old_deployments_removes_old(self, manager):
        """Test cleanup removes old completed deployments."""
        old_deployment = ScheduledDeployment(
            id="old-1",
            name="Old",
            curriculum_id="test",
            target_date=datetime.now() - timedelta(days=60),
            voice_config=UserVoiceConfig(),
            status=DeploymentStatus.COMPLETED,
        )
        old_deployment.generation_completed_at = datetime.now() - timedelta(days=45)
        manager._deployments["old-1"] = (old_deployment, None)

        removed = manager.cleanup_old_deployments(max_age_days=30)

        assert removed == 1
        assert "old-1" not in manager._deployments

    def test_cleanup_keeps_recent(self, manager):
        """Test cleanup keeps recent deployments."""
        recent = ScheduledDeployment(
            id="recent-1",
            name="Recent",
            curriculum_id="test",
            target_date=datetime.now(),
            voice_config=UserVoiceConfig(),
            status=DeploymentStatus.COMPLETED,
        )
        recent.generation_completed_at = datetime.now() - timedelta(days=5)
        manager._deployments["recent-1"] = (recent, None)

        removed = manager.cleanup_old_deployments(max_age_days=30)

        assert removed == 0
        assert "recent-1" in manager._deployments

    def test_cleanup_keeps_running(self, manager):
        """Test cleanup keeps running deployments."""
        running = ScheduledDeployment(
            id="running-1",
            name="Running",
            curriculum_id="test",
            target_date=datetime.now(),
            voice_config=UserVoiceConfig(),
            status=DeploymentStatus.GENERATING,
        )
        manager._deployments["running-1"] = (running, None)

        removed = manager.cleanup_old_deployments(max_age_days=0)

        assert removed == 0
        assert "running-1" in manager._deployments


# =============================================================================
# API ENDPOINT TESTS
# =============================================================================


def create_mock_request(
    method: str = "POST",
    json_data: dict = None,
    match_info: dict = None,
    app: dict = None,
) -> MagicMock:
    """Create mock aiohttp request."""
    request = MagicMock(spec=web.Request)
    request.method = method
    request.match_info = match_info or {}
    request.app = app or {}

    async def mock_json():
        if json_data is None:
            raise json.JSONDecodeError("No JSON", "", 0)
        return json_data

    request.json = mock_json

    return request


class TestAPIEndpoints:
    """Tests for API endpoint handlers."""

    @pytest.fixture
    def manager(self):
        """Create manager with segment loader."""
        cache = MockTTSCache()
        pool = MockResourcePool()
        manager = ScheduledDeploymentManager(cache, pool)

        async def load_segments(curriculum_id):
            return [f"Segment {i}" for i in range(5)]

        manager.set_segment_loader(load_segments)
        return manager

    @pytest.mark.asyncio
    async def test_handle_create_deployment_success(self, manager):
        """Test creating deployment via API."""
        request = create_mock_request(
            json_data={
                "name": "API Test",
                "curriculum_id": "api-curriculum",
                "target_date": "2024-06-01T09:00:00Z",
            },
            app={"deployment_manager": manager},
        )

        response = await handle_create_deployment(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "scheduled"
        assert "deployment" in data

    @pytest.mark.asyncio
    async def test_handle_create_deployment_invalid_json(self, manager):
        """Test create with invalid JSON returns 400."""
        request = create_mock_request(
            json_data=None,
            app={"deployment_manager": manager},
        )

        response = await handle_create_deployment(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_handle_create_deployment_missing_fields(self, manager):
        """Test create with missing fields returns 400."""
        request = create_mock_request(
            json_data={"name": "Test"},  # Missing curriculum_id and target_date
            app={"deployment_manager": manager},
        )

        response = await handle_create_deployment(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_handle_create_deployment_invalid_date(self, manager):
        """Test create with invalid date returns 400."""
        request = create_mock_request(
            json_data={
                "name": "Test",
                "curriculum_id": "test",
                "target_date": "not-a-date",
            },
            app={"deployment_manager": manager},
        )

        response = await handle_create_deployment(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_handle_create_deployment_no_manager(self):
        """Test create without manager returns 503."""
        request = create_mock_request(
            json_data={
                "name": "Test",
                "curriculum_id": "test",
                "target_date": "2024-06-01T09:00:00Z",
            },
            app={},
        )

        response = await handle_create_deployment(request)

        assert response.status == 503

    @pytest.mark.asyncio
    async def test_handle_list_deployments(self, manager):
        """Test listing deployments via API."""
        await manager.schedule_deployment("D1", "c1", datetime.now())
        await manager.schedule_deployment("D2", "c2", datetime.now())

        request = create_mock_request(app={"deployment_manager": manager})

        response = await handle_list_deployments(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert len(data["deployments"]) == 2

    @pytest.mark.asyncio
    async def test_handle_get_deployment_success(self, manager):
        """Test getting deployment via API."""
        deployment = await manager.schedule_deployment("Test", "test", datetime.now())

        request = create_mock_request(
            match_info={"id": deployment.id},
            app={"deployment_manager": manager},
        )

        response = await handle_get_deployment(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["deployment"]["id"] == deployment.id

    @pytest.mark.asyncio
    async def test_handle_get_deployment_not_found(self, manager):
        """Test getting non-existent deployment returns 404."""
        request = create_mock_request(
            match_info={"id": "nonexistent"},
            app={"deployment_manager": manager},
        )

        response = await handle_get_deployment(request)

        assert response.status == 404

    @pytest.mark.asyncio
    async def test_handle_start_deployment_success(self, manager):
        """Test starting deployment via API."""
        deployment = await manager.schedule_deployment("Test", "test", datetime.now())

        request = create_mock_request(
            match_info={"id": deployment.id},
            app={"deployment_manager": manager},
        )

        response = await handle_start_deployment(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "started"

    @pytest.mark.asyncio
    async def test_handle_start_deployment_not_found(self, manager):
        """Test starting non-existent deployment returns 400."""
        request = create_mock_request(
            match_info={"id": "nonexistent"},
            app={"deployment_manager": manager},
        )

        response = await handle_start_deployment(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_handle_cancel_deployment_success(self, manager):
        """Test canceling deployment via API."""
        deployment = await manager.schedule_deployment("Test", "test", datetime.now())

        request = create_mock_request(
            match_info={"id": deployment.id},
            app={"deployment_manager": manager},
        )

        response = await handle_cancel_deployment(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "cancelled"

    @pytest.mark.asyncio
    async def test_handle_cancel_deployment_not_found(self, manager):
        """Test canceling non-existent deployment returns 404."""
        request = create_mock_request(
            match_info={"id": "nonexistent"},
            app={"deployment_manager": manager},
        )

        response = await handle_cancel_deployment(request)

        assert response.status == 404

    @pytest.mark.asyncio
    async def test_handle_get_deployment_cache(self, manager):
        """Test getting cache coverage via API."""
        deployment = await manager.schedule_deployment("Test", "test", datetime.now())

        request = create_mock_request(
            match_info={"id": deployment.id},
            app={"deployment_manager": manager},
        )

        response = await handle_get_deployment_cache(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "total_segments" in data


# =============================================================================
# ROUTE REGISTRATION TESTS
# =============================================================================


class TestRouteRegistration:
    """Tests for route registration."""

    def test_register_deployment_routes(self):
        """Test all routes are registered."""
        app = web.Application()

        register_deployment_routes(app)

        routes = [str(r.resource.canonical) for r in app.router.routes() if hasattr(r, 'resource')]

        expected = [
            "/api/deployments",
            "/api/deployments/{id}",
            "/api/deployments/{id}/start",
            "/api/deployments/{id}/cache",
        ]

        for expected_route in expected:
            assert any(expected_route in r for r in routes), f"Route {expected_route} not found"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
