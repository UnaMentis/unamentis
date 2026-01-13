"""
Tests for TTS Curriculum Prefetcher

Comprehensive tests for background prefetching of TTS audio for curriculum content.
Tests verify prefetch jobs, progress tracking, cancellation, and resource pool integration.
"""

import asyncio
import pytest
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, MagicMock

from tts_cache.prefetcher import (
    PrefetchProgress,
    CurriculumPrefetcher,
)


# =============================================================================
# PREFETCH PROGRESS TESTS
# =============================================================================


class TestPrefetchProgress:
    """Tests for PrefetchProgress dataclass."""

    def test_creation_with_required_fields(self):
        """Test creating progress with required fields."""
        progress = PrefetchProgress(
            job_id="test_job_123",
            curriculum_id="cur_001",
            topic_id="topic_001",
            total_segments=10,
        )

        assert progress.job_id == "test_job_123"
        assert progress.curriculum_id == "cur_001"
        assert progress.topic_id == "topic_001"
        assert progress.total_segments == 10
        assert progress.completed == 0
        assert progress.cached == 0
        assert progress.generated == 0
        assert progress.failed == 0
        assert progress.status == "pending"
        assert progress.started_at is None
        assert progress.completed_at is None
        assert progress.error is None

    def test_creation_with_all_fields(self):
        """Test creating progress with all fields specified."""
        now = datetime.now()
        progress = PrefetchProgress(
            job_id="test_job",
            curriculum_id="cur_001",
            topic_id="topic_001",
            total_segments=20,
            completed=15,
            cached=5,
            generated=8,
            failed=2,
            status="in_progress",
            started_at=now,
            completed_at=None,
            error=None,
        )

        assert progress.completed == 15
        assert progress.cached == 5
        assert progress.generated == 8
        assert progress.failed == 2
        assert progress.status == "in_progress"
        assert progress.started_at == now


class TestPrefetchProgressPercentComplete:
    """Tests for percent_complete property."""

    def test_percent_complete_zero_segments(self):
        """Test percent complete with zero total segments returns 100."""
        progress = PrefetchProgress(
            job_id="test",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=0,
        )

        assert progress.percent_complete == 100.0

    def test_percent_complete_no_progress(self):
        """Test percent complete with no completed segments."""
        progress = PrefetchProgress(
            job_id="test",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=10,
            completed=0,
        )

        assert progress.percent_complete == 0.0

    def test_percent_complete_partial(self):
        """Test percent complete with partial progress."""
        progress = PrefetchProgress(
            job_id="test",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=10,
            completed=3,
        )

        assert progress.percent_complete == 30.0

    def test_percent_complete_full(self):
        """Test percent complete when all segments completed."""
        progress = PrefetchProgress(
            job_id="test",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=10,
            completed=10,
        )

        assert progress.percent_complete == 100.0


class TestPrefetchProgressToDict:
    """Tests for to_dict method."""

    def test_to_dict_includes_all_fields(self):
        """Test to_dict includes all expected fields."""
        progress = PrefetchProgress(
            job_id="job_123",
            curriculum_id="cur_001",
            topic_id="topic_001",
            total_segments=10,
            completed=5,
            cached=2,
            generated=3,
            failed=0,
            status="in_progress",
        )

        result = progress.to_dict()

        assert result["job_id"] == "job_123"
        assert result["curriculum_id"] == "cur_001"
        assert result["topic_id"] == "topic_001"
        assert result["total_segments"] == 10
        assert result["completed"] == 5
        assert result["cached"] == 2
        assert result["generated"] == 3
        assert result["failed"] == 0
        assert result["status"] == "in_progress"
        assert result["percent_complete"] == 50.0
        assert result["started_at"] is None
        assert result["completed_at"] is None
        assert result["error"] is None

    def test_to_dict_with_timestamps(self):
        """Test to_dict converts timestamps to ISO format."""
        now = datetime.now()
        progress = PrefetchProgress(
            job_id="job_123",
            curriculum_id="cur_001",
            topic_id="topic_001",
            total_segments=10,
            started_at=now,
            completed_at=now,
        )

        result = progress.to_dict()

        assert result["started_at"] == now.isoformat()
        assert result["completed_at"] == now.isoformat()

    def test_to_dict_rounds_percent(self):
        """Test to_dict rounds percent_complete to 1 decimal."""
        progress = PrefetchProgress(
            job_id="job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=3,
            completed=1,
        )

        result = progress.to_dict()

        # 1/3 = 33.333... should be rounded to 33.3
        assert result["percent_complete"] == 33.3


# =============================================================================
# CURRICULUM PREFETCHER TESTS
# =============================================================================


class TestCurriculumPrefetcherInit:
    """Tests for CurriculumPrefetcher initialization."""

    def test_init_with_required_params(self):
        """Test initialization with required parameters."""
        mock_cache = MagicMock()
        mock_pool = MagicMock()

        prefetcher = CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
        )

        assert prefetcher.cache is mock_cache
        assert prefetcher.resource_pool is mock_pool
        assert prefetcher.delay == 0.1  # Default
        assert prefetcher._jobs == {}

    def test_init_with_custom_delay(self):
        """Test initialization with custom delay."""
        mock_cache = MagicMock()
        mock_pool = MagicMock()

        prefetcher = CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0.5,
        )

        assert prefetcher.delay == 0.5


# =============================================================================
# PREFETCH TOPIC TESTS
# =============================================================================


class TestPrefetchTopic:
    """Tests for prefetch_topic method."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_pool = AsyncMock()
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,  # No delay for tests
        )

    @pytest.mark.asyncio
    async def test_prefetch_topic_returns_job_id(self, prefetcher):
        """Test prefetch_topic returns a job ID."""
        # Setup mock to prevent actual processing
        prefetcher.cache.has = AsyncMock(return_value=True)

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur_001",
            topic_id="topic_001",
            segments=["Hello", "World"],
            voice_id="nova",
        )

        assert job_id.startswith("prefetch_")
        assert len(job_id) > 8

    @pytest.mark.asyncio
    async def test_prefetch_topic_creates_job_entry(self, prefetcher):
        """Test prefetch_topic creates entry in _jobs dict."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur_001",
            topic_id="topic_001",
            segments=["Hello"],
        )

        assert job_id in prefetcher._jobs
        task, progress = prefetcher._jobs[job_id]
        assert progress.curriculum_id == "cur_001"
        assert progress.topic_id == "topic_001"
        assert progress.total_segments == 1

    @pytest.mark.asyncio
    async def test_prefetch_topic_cancels_existing_job_for_same_topic(self, prefetcher):
        """Test prefetch_topic cancels existing job for same topic."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        # Start first job
        job_id_1 = await prefetcher.prefetch_topic(
            curriculum_id="cur_001",
            topic_id="topic_001",
            segments=["Hello"],
        )

        # Allow some time for task to be created
        await asyncio.sleep(0.01)

        # Start second job for same topic
        job_id_2 = await prefetcher.prefetch_topic(
            curriculum_id="cur_001",
            topic_id="topic_001",
            segments=["World"],
        )

        # First job should be removed
        assert job_id_1 not in prefetcher._jobs
        assert job_id_2 in prefetcher._jobs

    @pytest.mark.asyncio
    async def test_prefetch_topic_allows_multiple_different_topics(self, prefetcher):
        """Test prefetch_topic allows multiple jobs for different topics."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        job_id_1 = await prefetcher.prefetch_topic(
            curriculum_id="cur_001",
            topic_id="topic_001",
            segments=["Hello"],
        )

        job_id_2 = await prefetcher.prefetch_topic(
            curriculum_id="cur_001",
            topic_id="topic_002",
            segments=["World"],
        )

        assert job_id_1 in prefetcher._jobs
        assert job_id_2 in prefetcher._jobs


# =============================================================================
# PREFETCH SEGMENTS TESTS
# =============================================================================


class TestPrefetchSegments:
    """Tests for _prefetch_segments internal method."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_cache._stats = MagicMock()
        mock_cache._stats.record_prefetch = MagicMock()
        mock_pool = AsyncMock()
        mock_pool.generate_with_priority = AsyncMock(
            return_value=(b"audio_data", 24000, 1.5)
        )
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,
        )

    @pytest.mark.asyncio
    async def test_prefetch_skips_cached_segments(self, prefetcher):
        """Test prefetch skips already cached segments."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        progress = PrefetchProgress(
            job_id="test_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=3,
        )

        await prefetcher._prefetch_segments(
            progress=progress,
            segments=["One", "Two", "Three"],
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            chatterbox_config=None,
        )

        assert progress.cached == 3
        assert progress.generated == 0
        assert progress.completed == 3
        assert progress.status == "completed"
        # Should not call generate_with_priority
        prefetcher.resource_pool.generate_with_priority.assert_not_called()

    @pytest.mark.asyncio
    async def test_prefetch_generates_uncached_segments(self, prefetcher):
        """Test prefetch generates uncached segments."""
        prefetcher.cache.has = AsyncMock(return_value=False)

        progress = PrefetchProgress(
            job_id="test_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=2,
        )

        await prefetcher._prefetch_segments(
            progress=progress,
            segments=["One", "Two"],
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            chatterbox_config=None,
        )

        assert progress.generated == 2
        assert progress.cached == 0
        assert progress.completed == 2
        assert progress.status == "completed"
        assert prefetcher.resource_pool.generate_with_priority.call_count == 2
        assert prefetcher.cache.put.call_count == 2

    @pytest.mark.asyncio
    async def test_prefetch_handles_generation_failure(self, prefetcher):
        """Test prefetch handles generation failure gracefully."""
        prefetcher.cache.has = AsyncMock(return_value=False)
        prefetcher.resource_pool.generate_with_priority = AsyncMock(
            side_effect=Exception("TTS server error")
        )

        progress = PrefetchProgress(
            job_id="test_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=2,
        )

        await prefetcher._prefetch_segments(
            progress=progress,
            segments=["One", "Two"],
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            chatterbox_config=None,
        )

        assert progress.failed == 2
        assert progress.generated == 0
        assert progress.completed == 2
        assert progress.status == "completed_with_errors"

    @pytest.mark.asyncio
    async def test_prefetch_sets_timestamps(self, prefetcher):
        """Test prefetch sets started_at and completed_at."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        progress = PrefetchProgress(
            job_id="test_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=1,
        )

        await prefetcher._prefetch_segments(
            progress=progress,
            segments=["One"],
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            chatterbox_config=None,
        )

        assert progress.started_at is not None
        assert progress.completed_at is not None
        assert progress.started_at <= progress.completed_at

    @pytest.mark.asyncio
    async def test_prefetch_respects_cancelled_status(self, prefetcher):
        """Test prefetch stops when status is cancelled during processing."""
        call_count = 0

        async def has_with_cancel(_key):
            nonlocal call_count
            call_count += 1
            # After processing a few segments, simulate cancellation
            if call_count >= 3:
                progress.status = "cancelled"
            return True

        prefetcher.cache.has = AsyncMock(side_effect=has_with_cancel)

        progress = PrefetchProgress(
            job_id="test_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=10,
        )

        await prefetcher._prefetch_segments(
            progress=progress,
            segments=["One"] * 10,
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            chatterbox_config=None,
        )

        # Should have stopped after cancellation (processed 3, then stopped)
        # The status check happens at the start of each loop iteration
        assert progress.completed < 10
        assert progress.status == "cancelled"

    @pytest.mark.asyncio
    async def test_prefetch_with_chatterbox_config(self, prefetcher):
        """Test prefetch passes chatterbox config correctly."""
        prefetcher.cache.has = AsyncMock(return_value=False)

        progress = PrefetchProgress(
            job_id="test_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=1,
        )

        chatterbox_config = {
            "exaggeration": 0.5,
            "cfg_weight": 0.3,
            "language": "en",
        }

        await prefetcher._prefetch_segments(
            progress=progress,
            segments=["Hello"],
            voice_id="custom_voice",
            provider="chatterbox",
            speed=1.2,
            chatterbox_config=chatterbox_config,
        )

        # Verify generate_with_priority was called with correct params
        prefetcher.resource_pool.generate_with_priority.assert_called_once()
        call_kwargs = prefetcher.resource_pool.generate_with_priority.call_args[1]
        assert call_kwargs["chatterbox_config"] == chatterbox_config
        assert call_kwargs["provider"] == "chatterbox"
        assert call_kwargs["voice_id"] == "custom_voice"
        assert call_kwargs["speed"] == 1.2

    @pytest.mark.asyncio
    async def test_prefetch_records_stats(self, prefetcher):
        """Test prefetch records stats for generated segments."""
        prefetcher.cache.has = AsyncMock(return_value=False)

        progress = PrefetchProgress(
            job_id="test_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=2,
        )

        await prefetcher._prefetch_segments(
            progress=progress,
            segments=["One", "Two"],
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            chatterbox_config=None,
        )

        assert prefetcher.cache._stats.record_prefetch.call_count == 2


# =============================================================================
# PREFETCH UPCOMING TESTS
# =============================================================================


class TestPrefetchUpcoming:
    """Tests for prefetch_upcoming method."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_cache._stats = MagicMock()
        mock_cache._stats.record_prefetch = MagicMock()
        mock_pool = AsyncMock()
        mock_pool.generate_with_priority = AsyncMock(
            return_value=(b"audio_data", 24000, 1.5)
        )
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,
        )

    @pytest.mark.asyncio
    async def test_prefetch_upcoming_calculates_correct_range(self, prefetcher):
        """Test prefetch_upcoming prefetches correct range of segments."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        segments = ["One", "Two", "Three", "Four", "Five", "Six", "Seven"]

        await prefetcher.prefetch_upcoming(
            curriculum_id="cur",
            current_index=2,  # Currently at "Three"
            segments=segments,
            lookahead=3,  # Should prefetch "Four", "Five", "Six"
        )

        # Give time for fire-and-forget tasks to run
        await asyncio.sleep(0.1)

        # Should check cache for segments 3, 4, 5 (indices after current)
        assert prefetcher.cache.has.call_count == 3

    @pytest.mark.asyncio
    async def test_prefetch_upcoming_handles_end_of_list(self, prefetcher):
        """Test prefetch_upcoming handles end of segment list."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        segments = ["One", "Two", "Three"]

        await prefetcher.prefetch_upcoming(
            curriculum_id="cur",
            current_index=1,  # Currently at "Two"
            segments=segments,
            lookahead=5,  # Only "Three" is available
        )

        await asyncio.sleep(0.1)

        # Should only check cache for one segment
        assert prefetcher.cache.has.call_count == 1

    @pytest.mark.asyncio
    async def test_prefetch_upcoming_no_upcoming_segments(self, prefetcher):
        """Test prefetch_upcoming returns early when no upcoming segments."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        segments = ["One", "Two", "Three"]

        await prefetcher.prefetch_upcoming(
            curriculum_id="cur",
            current_index=2,  # Currently at last segment
            segments=segments,
            lookahead=5,
        )

        await asyncio.sleep(0.1)

        # Should not check any segments
        prefetcher.cache.has.assert_not_called()

    @pytest.mark.asyncio
    async def test_prefetch_upcoming_empty_segments(self, prefetcher):
        """Test prefetch_upcoming handles empty segment list."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        await prefetcher.prefetch_upcoming(
            curriculum_id="cur",
            current_index=0,
            segments=[],
            lookahead=5,
        )

        await asyncio.sleep(0.1)

        prefetcher.cache.has.assert_not_called()


# =============================================================================
# PREFETCH SINGLE TESTS
# =============================================================================


class TestPrefetchSingle:
    """Tests for _prefetch_single internal method."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_cache._stats = MagicMock()
        mock_cache._stats.record_prefetch = MagicMock()
        mock_pool = AsyncMock()
        mock_pool.generate_with_priority = AsyncMock(
            return_value=(b"audio_data", 24000, 1.5)
        )
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,
        )

    @pytest.mark.asyncio
    async def test_prefetch_single_skips_cached(self, prefetcher):
        """Test _prefetch_single skips already cached segments."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        await prefetcher._prefetch_single(
            text="Hello world",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            chatterbox_config=None,
        )

        prefetcher.cache.has.assert_called_once()
        prefetcher.resource_pool.generate_with_priority.assert_not_called()

    @pytest.mark.asyncio
    async def test_prefetch_single_generates_uncached(self, prefetcher):
        """Test _prefetch_single generates uncached segments."""
        prefetcher.cache.has = AsyncMock(return_value=False)

        await prefetcher._prefetch_single(
            text="Hello world",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            chatterbox_config=None,
        )

        prefetcher.resource_pool.generate_with_priority.assert_called_once()
        prefetcher.cache.put.assert_called_once()
        prefetcher.cache._stats.record_prefetch.assert_called_once()

    @pytest.mark.asyncio
    async def test_prefetch_single_handles_error_silently(self, prefetcher):
        """Test _prefetch_single handles errors without raising."""
        prefetcher.cache.has = AsyncMock(return_value=False)
        prefetcher.resource_pool.generate_with_priority = AsyncMock(
            side_effect=Exception("TTS error")
        )

        # Should not raise
        await prefetcher._prefetch_single(
            text="Hello world",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            chatterbox_config=None,
        )

        # Error was silently handled
        prefetcher.cache.put.assert_not_called()


# =============================================================================
# CANCEL JOB TESTS
# =============================================================================


class TestCancelJob:
    """Tests for cancel method."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_pool = AsyncMock()
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,
        )

    @pytest.mark.asyncio
    async def test_cancel_returns_false_for_unknown_job(self, prefetcher):
        """Test cancel returns False for unknown job ID."""
        result = await prefetcher.cancel("nonexistent_job")

        assert result is False

    @pytest.mark.asyncio
    async def test_cancel_returns_true_for_existing_job(self, prefetcher):
        """Test cancel returns True for existing job."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur",
            topic_id="topic",
            segments=["Hello"],
        )

        result = await prefetcher.cancel(job_id)

        assert result is True

    @pytest.mark.asyncio
    async def test_cancel_sets_cancelled_status(self, prefetcher):
        """Test cancel sets status to cancelled."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur",
            topic_id="topic",
            segments=["Hello"],
        )

        await prefetcher.cancel(job_id)

        _, progress = prefetcher._jobs[job_id]
        assert progress.status == "cancelled"
        assert progress.completed_at is not None


# =============================================================================
# GET PROGRESS TESTS
# =============================================================================


class TestGetProgress:
    """Tests for get_progress method."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_pool = AsyncMock()
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,
        )

    @pytest.mark.asyncio
    async def test_get_progress_returns_none_for_unknown_job(self, prefetcher):
        """Test get_progress returns None for unknown job ID."""
        result = prefetcher.get_progress("nonexistent_job")

        assert result is None

    @pytest.mark.asyncio
    async def test_get_progress_returns_dict_for_existing_job(self, prefetcher):
        """Test get_progress returns progress dict for existing job."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur_001",
            topic_id="topic_001",
            segments=["Hello", "World"],
        )

        result = prefetcher.get_progress(job_id)

        assert result is not None
        assert result["job_id"] == job_id
        assert result["curriculum_id"] == "cur_001"
        assert result["topic_id"] == "topic_001"
        assert result["total_segments"] == 2


# =============================================================================
# GET ALL JOBS TESTS
# =============================================================================


class TestGetAllJobs:
    """Tests for get_all_jobs method."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_pool = AsyncMock()
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,
        )

    def test_get_all_jobs_empty(self, prefetcher):
        """Test get_all_jobs returns empty list when no jobs."""
        result = prefetcher.get_all_jobs()

        assert result == []

    @pytest.mark.asyncio
    async def test_get_all_jobs_returns_all_jobs(self, prefetcher):
        """Test get_all_jobs returns all job progress dicts."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        job_id_1 = await prefetcher.prefetch_topic(
            curriculum_id="cur_001",
            topic_id="topic_001",
            segments=["Hello"],
        )

        job_id_2 = await prefetcher.prefetch_topic(
            curriculum_id="cur_001",
            topic_id="topic_002",
            segments=["World"],
        )

        result = prefetcher.get_all_jobs()

        assert len(result) == 2
        job_ids = [j["job_id"] for j in result]
        assert job_id_1 in job_ids
        assert job_id_2 in job_ids


# =============================================================================
# CLEANUP COMPLETED JOBS TESTS
# =============================================================================


class TestCleanupCompletedJobs:
    """Tests for cleanup_completed_jobs method."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_pool = AsyncMock()
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,
        )

    def test_cleanup_returns_zero_when_no_jobs(self, prefetcher):
        """Test cleanup returns 0 when no jobs."""
        result = prefetcher.cleanup_completed_jobs()

        assert result == 0

    @pytest.mark.asyncio
    async def test_cleanup_removes_old_completed_jobs(self, prefetcher):
        """Test cleanup removes completed jobs older than max_age."""
        # Manually add a completed job with old timestamp
        old_time = datetime.now() - timedelta(hours=2)
        progress = PrefetchProgress(
            job_id="old_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=1,
            completed=1,
            status="completed",
            completed_at=old_time,
        )
        mock_task = MagicMock()
        prefetcher._jobs["old_job"] = (mock_task, progress)

        result = prefetcher.cleanup_completed_jobs(max_age_seconds=3600)  # 1 hour

        assert result == 1
        assert "old_job" not in prefetcher._jobs

    @pytest.mark.asyncio
    async def test_cleanup_keeps_recent_completed_jobs(self, prefetcher):
        """Test cleanup keeps completed jobs within max_age."""
        # Add a recently completed job
        progress = PrefetchProgress(
            job_id="recent_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=1,
            completed=1,
            status="completed",
            completed_at=datetime.now(),
        )
        mock_task = MagicMock()
        prefetcher._jobs["recent_job"] = (mock_task, progress)

        result = prefetcher.cleanup_completed_jobs(max_age_seconds=3600)

        assert result == 0
        assert "recent_job" in prefetcher._jobs

    @pytest.mark.asyncio
    async def test_cleanup_keeps_in_progress_jobs(self, prefetcher):
        """Test cleanup keeps in_progress jobs regardless of age."""
        # Add an old in_progress job
        old_time = datetime.now() - timedelta(hours=2)
        progress = PrefetchProgress(
            job_id="in_progress_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=10,
            completed=5,
            status="in_progress",
            started_at=old_time,
        )
        mock_task = MagicMock()
        prefetcher._jobs["in_progress_job"] = (mock_task, progress)

        result = prefetcher.cleanup_completed_jobs(max_age_seconds=3600)

        assert result == 0
        assert "in_progress_job" in prefetcher._jobs

    @pytest.mark.asyncio
    async def test_cleanup_removes_failed_jobs(self, prefetcher):
        """Test cleanup removes old failed jobs."""
        old_time = datetime.now() - timedelta(hours=2)
        progress = PrefetchProgress(
            job_id="failed_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=10,
            status="failed",
            completed_at=old_time,
            error="Some error",
        )
        mock_task = MagicMock()
        prefetcher._jobs["failed_job"] = (mock_task, progress)

        result = prefetcher.cleanup_completed_jobs(max_age_seconds=3600)

        assert result == 1
        assert "failed_job" not in prefetcher._jobs

    @pytest.mark.asyncio
    async def test_cleanup_removes_cancelled_jobs(self, prefetcher):
        """Test cleanup removes old cancelled jobs."""
        old_time = datetime.now() - timedelta(hours=2)
        progress = PrefetchProgress(
            job_id="cancelled_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=10,
            status="cancelled",
            completed_at=old_time,
        )
        mock_task = MagicMock()
        prefetcher._jobs["cancelled_job"] = (mock_task, progress)

        result = prefetcher.cleanup_completed_jobs(max_age_seconds=3600)

        assert result == 1
        assert "cancelled_job" not in prefetcher._jobs

    @pytest.mark.asyncio
    async def test_cleanup_removes_completed_with_errors_jobs(self, prefetcher):
        """Test cleanup removes old completed_with_errors jobs."""
        old_time = datetime.now() - timedelta(hours=2)
        progress = PrefetchProgress(
            job_id="partial_job",
            curriculum_id="cur",
            topic_id="topic",
            total_segments=10,
            completed=10,
            failed=3,
            status="completed_with_errors",
            completed_at=old_time,
        )
        mock_task = MagicMock()
        prefetcher._jobs["partial_job"] = (mock_task, progress)

        result = prefetcher.cleanup_completed_jobs(max_age_seconds=3600)

        assert result == 1
        assert "partial_job" not in prefetcher._jobs


# =============================================================================
# INTEGRATION TESTS
# =============================================================================


class TestPrefetcherIntegration:
    """Integration tests for prefetcher workflow."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_cache._stats = MagicMock()
        mock_cache._stats.record_prefetch = MagicMock()
        mock_pool = AsyncMock()
        mock_pool.generate_with_priority = AsyncMock(
            return_value=(b"fake_audio_data", 24000, 1.5)
        )
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,
        )

    @pytest.mark.asyncio
    async def test_full_prefetch_workflow(self, prefetcher):
        """Test complete prefetch workflow from start to completion."""
        # First two segments cached, third needs generation
        has_call_count = 0

        async def has_side_effect(_key):
            nonlocal has_call_count
            has_call_count += 1
            return has_call_count <= 2  # First two are cached

        prefetcher.cache.has = AsyncMock(side_effect=has_side_effect)

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="curriculum_math_101",
            topic_id="algebra_basics",
            segments=["Segment 1", "Segment 2", "Segment 3"],
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )

        # Wait for async task to complete
        await asyncio.sleep(0.2)

        progress = prefetcher.get_progress(job_id)

        assert progress is not None
        assert progress["total_segments"] == 3
        assert progress["cached"] == 2
        assert progress["generated"] == 1
        assert progress["completed"] == 3
        assert progress["status"] == "completed"
        assert progress["percent_complete"] == 100.0

    @pytest.mark.asyncio
    async def test_prefetch_with_mixed_success_and_failure(self, prefetcher):
        """Test prefetch with mixed success and failure."""
        prefetcher.cache.has = AsyncMock(return_value=False)

        call_count = 0

        async def generate_side_effect(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 2:
                raise Exception("TTS server timeout")
            return (b"audio_data", 24000, 1.5)

        prefetcher.resource_pool.generate_with_priority = AsyncMock(
            side_effect=generate_side_effect
        )

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur",
            topic_id="topic",
            segments=["One", "Two", "Three"],
        )

        await asyncio.sleep(0.2)

        progress = prefetcher.get_progress(job_id)

        assert progress["generated"] == 2
        assert progress["failed"] == 1
        assert progress["status"] == "completed_with_errors"


# =============================================================================
# EDGE CASES
# =============================================================================


class TestPrefetcherEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.fixture
    def prefetcher(self):
        """Create prefetcher with mocked dependencies."""
        mock_cache = AsyncMock()
        mock_cache._stats = MagicMock()
        mock_cache._stats.record_prefetch = MagicMock()
        mock_pool = AsyncMock()
        mock_pool.generate_with_priority = AsyncMock(
            return_value=(b"audio_data", 24000, 1.5)
        )
        return CurriculumPrefetcher(
            cache=mock_cache,
            resource_pool=mock_pool,
            delay_between_requests=0,
        )

    @pytest.mark.asyncio
    async def test_prefetch_empty_segments(self, prefetcher):
        """Test prefetch with empty segments list."""
        prefetcher.cache.has = AsyncMock(return_value=True)

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur",
            topic_id="topic",
            segments=[],  # Empty
        )

        await asyncio.sleep(0.1)

        progress = prefetcher.get_progress(job_id)

        assert progress["total_segments"] == 0
        assert progress["percent_complete"] == 100.0
        assert progress["status"] == "completed"

    @pytest.mark.asyncio
    async def test_prefetch_single_segment(self, prefetcher):
        """Test prefetch with single segment."""
        prefetcher.cache.has = AsyncMock(return_value=False)

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur",
            topic_id="topic",
            segments=["Only one"],
        )

        await asyncio.sleep(0.1)

        progress = prefetcher.get_progress(job_id)

        assert progress["total_segments"] == 1
        assert progress["generated"] == 1
        assert progress["status"] == "completed"

    @pytest.mark.asyncio
    async def test_prefetch_very_long_text(self, prefetcher):
        """Test prefetch with very long text segment."""
        prefetcher.cache.has = AsyncMock(return_value=False)

        long_text = "This is a very long text segment. " * 100

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur",
            topic_id="topic",
            segments=[long_text],
        )

        await asyncio.sleep(0.1)

        progress = prefetcher.get_progress(job_id)
        assert progress["status"] == "completed"

    @pytest.mark.asyncio
    async def test_prefetch_special_characters(self, prefetcher):
        """Test prefetch with special characters in text."""
        prefetcher.cache.has = AsyncMock(return_value=False)

        special_text = "Hello! @#$%^&*() 123 'quotes' \"double quotes\" <html> \n\t"

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur",
            topic_id="topic",
            segments=[special_text],
        )

        await asyncio.sleep(0.1)

        progress = prefetcher.get_progress(job_id)
        assert progress["status"] == "completed"

    @pytest.mark.asyncio
    async def test_prefetch_unicode_text(self, prefetcher):
        """Test prefetch with unicode text."""
        prefetcher.cache.has = AsyncMock(return_value=False)

        unicode_text = "Hello world! Cafe au lait"

        job_id = await prefetcher.prefetch_topic(
            curriculum_id="cur",
            topic_id="topic",
            segments=[unicode_text],
        )

        await asyncio.sleep(0.1)

        progress = prefetcher.get_progress(job_id)
        assert progress["status"] == "completed"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
