"""Tests for TTS Pre-Generation Job Manager."""

import pytest
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

from tts_pregen import (
    TTSPregenJob,
    TTSJobItem,
    TTSProfile,
    JobStatus,
    ItemStatus,
)
from tts_pregen.job_manager import JobManager


@pytest.fixture
def mock_repository():
    """Create a mock repository."""
    repo = AsyncMock()
    repo.create_job = AsyncMock()
    repo.get_job = AsyncMock()
    repo.list_jobs = AsyncMock()
    repo.update_job = AsyncMock()
    repo.update_job_status = AsyncMock()
    repo.delete_job = AsyncMock()
    repo.create_job_items = AsyncMock()
    repo.get_job_items = AsyncMock()
    repo.get_pending_items = AsyncMock()
    repo.update_job_item = AsyncMock()
    repo.reset_failed_items = AsyncMock()
    repo.get_profile = AsyncMock()
    return repo


@pytest.fixture
def job_manager(mock_repository):
    """Create job manager with mock repository."""
    return JobManager(repository=mock_repository, base_output_dir="/tmp/tts-test")


class TestJobManagerCreate:
    """Tests for job creation."""

    @pytest.mark.asyncio
    async def test_create_job_with_profile(self, job_manager, mock_repository):
        """Test creating a job with a profile ID."""
        profile_id = uuid4()
        items = [{"text": "Hello", "source_ref": "q1"}, {"text": "World", "source_ref": "q2"}]

        # Setup mock to return the job
        mock_repository.create_job.side_effect = lambda job: job
        mock_repository.create_job_items.return_value = 2

        job = await job_manager.create_job(
            name="Test Job",
            source_type="custom",
            items=items,
            profile_id=profile_id,
        )

        assert job.name == "Test Job"
        assert job.source_type == "custom"
        assert job.profile_id == profile_id
        assert job.total_items == 2
        assert job.status == JobStatus.PENDING
        mock_repository.create_job.assert_called_once()
        mock_repository.create_job_items.assert_called_once()

    @pytest.mark.asyncio
    async def test_create_job_with_tts_config(self, job_manager, mock_repository):
        """Test creating a job with inline TTS config."""
        tts_config = {"provider": "chatterbox", "voice_id": "nova"}
        items = [{"text": "Test text"}]

        mock_repository.create_job.side_effect = lambda job: job
        mock_repository.create_job_items.return_value = 1

        job = await job_manager.create_job(
            name="Config Job",
            source_type="custom",
            items=items,
            tts_config=tts_config,
        )

        assert job.tts_config == tts_config
        assert job.profile_id is None

    @pytest.mark.asyncio
    async def test_create_job_requires_config(self, job_manager):
        """Test that job creation requires either profile_id or tts_config."""
        with pytest.raises(ValueError, match="Either profile_id or tts_config"):
            await job_manager.create_job(
                name="No Config Job",
                source_type="custom",
                items=[{"text": "Test"}],
            )

    @pytest.mark.asyncio
    async def test_create_job_requires_items(self, job_manager):
        """Test that job creation requires at least one item."""
        with pytest.raises(ValueError, match="At least one item"):
            await job_manager.create_job(
                name="Empty Job",
                source_type="custom",
                items=[],
                tts_config={"provider": "test"},
            )


class TestJobManagerLifecycle:
    """Tests for job lifecycle management."""

    @pytest.mark.asyncio
    async def test_start_pending_job(self, job_manager, mock_repository):
        """Test starting a pending job."""
        job_id = uuid4()
        job = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.PENDING,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
        )

        mock_repository.get_job.return_value = job
        mock_repository.update_job_status.return_value = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.RUNNING,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
            started_at=datetime.now(),
        )

        result = await job_manager.start_job(job_id)

        assert result.status == JobStatus.RUNNING
        assert result.started_at is not None
        mock_repository.update_job_status.assert_called_once()

    @pytest.mark.asyncio
    async def test_cannot_start_running_job(self, job_manager, mock_repository):
        """Test that running jobs cannot be started again."""
        job_id = uuid4()
        job = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.RUNNING,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
        )

        mock_repository.get_job.return_value = job

        result = await job_manager.start_job(job_id)

        # Returns the job but doesn't change status
        assert result == job
        mock_repository.update_job_status.assert_not_called()

    @pytest.mark.asyncio
    async def test_pause_running_job(self, job_manager, mock_repository):
        """Test pausing a running job."""
        job_id = uuid4()
        job = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.RUNNING,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
        )

        mock_repository.get_job.return_value = job
        mock_repository.update_job_status.return_value = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.PAUSED,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
            paused_at=datetime.now(),
        )

        result = await job_manager.pause_job(job_id)

        assert result.status == JobStatus.PAUSED
        mock_repository.update_job_status.assert_called_once()

    @pytest.mark.asyncio
    async def test_resume_paused_job(self, job_manager, mock_repository):
        """Test resuming a paused job."""
        job_id = uuid4()
        job = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.PAUSED,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
        )

        mock_repository.get_job.return_value = job
        mock_repository.update_job_status.return_value = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.RUNNING,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
        )

        result = await job_manager.resume_job(job_id)

        assert result.status == JobStatus.RUNNING

    @pytest.mark.asyncio
    async def test_cancel_pending_job(self, job_manager, mock_repository):
        """Test cancelling a pending job."""
        job_id = uuid4()
        job = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.PENDING,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
        )

        mock_repository.get_job.return_value = job
        mock_repository.update_job_status.return_value = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.CANCELLED,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
        )

        result = await job_manager.cancel_job(job_id)

        assert result.status == JobStatus.CANCELLED

    @pytest.mark.asyncio
    async def test_cannot_cancel_completed_job(self, job_manager, mock_repository):
        """Test that completed jobs cannot be cancelled."""
        job_id = uuid4()
        job = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.COMPLETED,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
        )

        mock_repository.get_job.return_value = job

        result = await job_manager.cancel_job(job_id)

        assert result == job
        mock_repository.update_job_status.assert_not_called()


class TestJobManagerDelete:
    """Tests for job deletion."""

    @pytest.mark.asyncio
    async def test_delete_pending_job(self, job_manager, mock_repository):
        """Test deleting a pending job."""
        job_id = uuid4()
        job = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.PENDING,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp/nonexistent",
        )

        mock_repository.get_job.return_value = job
        mock_repository.delete_job.return_value = True

        result = await job_manager.delete_job(job_id)

        assert result is True
        mock_repository.delete_job.assert_called_once_with(job_id)

    @pytest.mark.asyncio
    async def test_delete_nonexistent_job(self, job_manager, mock_repository):
        """Test deleting a job that doesn't exist."""
        mock_repository.get_job.return_value = None

        result = await job_manager.delete_job(uuid4())

        assert result is False
        mock_repository.delete_job.assert_not_called()


class TestJobManagerItems:
    """Tests for job item management."""

    @pytest.mark.asyncio
    async def test_get_job_items(self, job_manager, mock_repository):
        """Test getting items for a job."""
        job_id = uuid4()
        items = [
            TTSJobItem(
                id=uuid4(),
                job_id=job_id,
                item_index=0,
                text_content="Test",
                text_hash="abc",
            ),
            TTSJobItem(
                id=uuid4(),
                job_id=job_id,
                item_index=1,
                text_content="Test 2",
                text_hash="def",
            ),
        ]

        mock_repository.get_job_items.return_value = items

        result = await job_manager.get_job_items(job_id)

        assert len(result) == 2
        mock_repository.get_job_items.assert_called_once()

    @pytest.mark.asyncio
    async def test_get_pending_items(self, job_manager, mock_repository):
        """Test getting pending items."""
        job_id = uuid4()
        items = [
            TTSJobItem(
                id=uuid4(),
                job_id=job_id,
                item_index=0,
                text_content="Pending 1",
                text_hash="abc",
                status=ItemStatus.PENDING,
            ),
        ]

        mock_repository.get_pending_items.return_value = items

        result = await job_manager.get_pending_items(job_id, limit=50)

        assert len(result) == 1
        mock_repository.get_pending_items.assert_called_once_with(job_id, 50)

    @pytest.mark.asyncio
    async def test_retry_failed_items(self, job_manager, mock_repository):
        """Test retrying failed items."""
        job_id = uuid4()
        job = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.PAUSED,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
            failed_items=3,
        )

        mock_repository.get_job.return_value = job
        mock_repository.reset_failed_items.return_value = 3

        count = await job_manager.retry_failed_items(job_id)

        assert count == 3
        mock_repository.reset_failed_items.assert_called_once_with(job_id)


class TestJobManagerProgress:
    """Tests for progress calculation."""

    @pytest.mark.asyncio
    async def test_get_job_progress(self, job_manager, mock_repository):
        """Test getting job progress."""
        job_id = uuid4()
        job = TTSPregenJob(
            id=job_id,
            name="Test",
            job_type="batch",
            status=JobStatus.RUNNING,
            source_type="custom",
            tts_config={"provider": "test"},
            output_dir="/tmp",
            total_items=10,
            completed_items=5,
            failed_items=1,
            started_at=datetime.now(),
        )

        mock_repository.get_job.return_value = job

        progress = await job_manager.get_job_progress(job_id)

        assert progress["status"] == "running"
        assert progress["total_items"] == 10
        assert progress["completed_items"] == 5
        assert progress["failed_items"] == 1
        assert progress["pending_items"] == 4
        assert progress["percent_complete"] == 50.0

    @pytest.mark.asyncio
    async def test_get_progress_not_found(self, job_manager, mock_repository):
        """Test getting progress for nonexistent job."""
        mock_repository.get_job.return_value = None

        progress = await job_manager.get_job_progress(uuid4())

        assert progress == {}


class TestJobManagerTTSConfig:
    """Tests for TTS configuration resolution."""

    @pytest.mark.asyncio
    async def test_resolve_config_from_profile(self, job_manager, mock_repository):
        """Test resolving TTS config from profile."""
        profile_id = uuid4()
        job = TTSPregenJob(
            id=uuid4(),
            name="Test",
            job_type="batch",
            status=JobStatus.PENDING,
            source_type="custom",
            profile_id=profile_id,
            output_dir="/tmp",
        )

        profile = TTSProfile(
            id=profile_id,
            name="Test Profile",
            provider="chatterbox",
            voice_id="nova",
            settings={"speed": 1.2},
        )

        mock_repository.get_profile.return_value = profile

        config = await job_manager.resolve_tts_config(job)

        assert config["provider"] == "chatterbox"
        assert config["voice_id"] == "nova"
        assert config["settings"]["speed"] == 1.2

    @pytest.mark.asyncio
    async def test_resolve_config_from_inline(self, job_manager, mock_repository):
        """Test resolving inline TTS config."""
        job = TTSPregenJob(
            id=uuid4(),
            name="Test",
            job_type="batch",
            status=JobStatus.PENDING,
            source_type="custom",
            tts_config={"provider": "piper", "voice_id": "default"},
            output_dir="/tmp",
        )

        config = await job_manager.resolve_tts_config(job)

        assert config["provider"] == "piper"
        assert config["voice_id"] == "default"

    @pytest.mark.asyncio
    async def test_resolve_config_profile_fallback(self, job_manager, mock_repository):
        """Test fallback to inline config when profile not found."""
        job = TTSPregenJob(
            id=uuid4(),
            name="Test",
            job_type="batch",
            status=JobStatus.PENDING,
            source_type="custom",
            profile_id=uuid4(),
            tts_config={"provider": "fallback"},
            output_dir="/tmp",
        )

        mock_repository.get_profile.return_value = None

        config = await job_manager.resolve_tts_config(job)

        assert config["provider"] == "fallback"

    @pytest.mark.asyncio
    async def test_resolve_config_no_config(self, job_manager, mock_repository):
        """Test error when no config available."""
        job = TTSPregenJob(
            id=uuid4(),
            name="Test",
            job_type="batch",
            status=JobStatus.PENDING,
            source_type="custom",
            output_dir="/tmp",
        )

        mock_repository.get_profile.return_value = None

        with pytest.raises(ValueError, match="no valid TTS configuration"):
            await job_manager.resolve_tts_config(job)
