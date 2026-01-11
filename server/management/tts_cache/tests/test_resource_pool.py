# TTS Resource Pool Tests
# Tests for priority-based TTS generation with concurrency control

import asyncio
from unittest.mock import patch
import pytest

from tts_cache.resource_pool import TTSResourcePool, Priority, GenerationResult


class TestPriority:
    """Tests for Priority enum."""

    def test_priority_ordering(self):
        """LIVE > PREFETCH > SCHEDULED."""
        assert Priority.LIVE > Priority.PREFETCH
        assert Priority.PREFETCH > Priority.SCHEDULED
        assert Priority.LIVE > Priority.SCHEDULED

    def test_priority_values(self):
        """Priority values are as expected."""
        assert Priority.LIVE == 10
        assert Priority.PREFETCH == 5
        assert Priority.SCHEDULED == 1


class TestTTSResourcePool:
    """Tests for TTSResourcePool."""

    @pytest.fixture
    def pool(self):
        """Create a resource pool for testing."""
        return TTSResourcePool(
            max_concurrent_live=3,
            max_concurrent_background=2,
            request_timeout=5.0,
        )

    def test_init(self, pool):
        """Test pool initialization."""
        assert pool.max_concurrent_live == 3
        assert pool.max_concurrent_background == 2
        assert pool.request_timeout == 5.0

    def test_stats_initial(self, pool):
        """Test initial stats are zero."""
        stats = pool.get_stats()
        assert stats["live_requests"] == 0
        assert stats["background_requests"] == 0
        assert stats["live_in_flight"] == 0
        assert stats["background_in_flight"] == 0
        assert stats["errors"] == 0

    def test_configure_server(self, pool):
        """Test configuring custom TTS server."""
        pool.configure_server("custom", "http://localhost:9000/tts", 48000)
        assert pool.tts_servers["custom"] == "http://localhost:9000/tts"
        assert pool.sample_rates["custom"] == 48000


class TestResourcePoolConcurrency:
    """Concurrency tests for TTSResourcePool."""

    @pytest.fixture
    def mock_pool(self):
        """Create a pool with mocked TTS generation."""
        pool = TTSResourcePool(
            max_concurrent_live=2,
            max_concurrent_background=1,
        )
        return pool

    @pytest.mark.asyncio
    async def test_live_requests_counted_correctly(self, mock_pool):
        """LIVE priority requests should increment live counter."""
        async def mock_generate(*args, **kwargs):
            return GenerationResult(b"audio", 24000, 1.0)

        with patch.object(mock_pool, '_generate_tts', side_effect=mock_generate):
            await mock_pool.generate_with_priority(
                text="test",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.LIVE,
            )

        assert mock_pool._live_requests == 1
        assert mock_pool._background_requests == 0

    @pytest.mark.asyncio
    async def test_background_requests_counted_correctly(self, mock_pool):
        """SCHEDULED priority requests should increment background counter."""
        async def mock_generate(*args, **kwargs):
            return GenerationResult(b"audio", 24000, 1.0)

        with patch.object(mock_pool, '_generate_tts', side_effect=mock_generate):
            await mock_pool.generate_with_priority(
                text="test",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.SCHEDULED,
            )

        assert mock_pool._background_requests == 1
        assert mock_pool._live_requests == 0

    @pytest.mark.asyncio
    async def test_prefetch_uses_background_semaphore(self, mock_pool):
        """PREFETCH priority should use background semaphore."""
        async def mock_generate(*args, **kwargs):
            return GenerationResult(b"audio", 24000, 1.0)

        with patch.object(mock_pool, '_generate_tts', side_effect=mock_generate):
            await mock_pool.generate_with_priority(
                text="test",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.PREFETCH,
            )

        assert mock_pool._background_requests == 1
        assert mock_pool._live_requests == 0

    @pytest.mark.asyncio
    async def test_live_and_background_use_separate_semaphores(self, mock_pool):
        """LIVE and BACKGROUND requests use separate semaphores."""
        async def mock_generate(*args, **kwargs):
            return GenerationResult(b"audio", 24000, 1.0)

        with patch.object(mock_pool, '_generate_tts', side_effect=mock_generate):
            # Run both live and background requests concurrently
            await asyncio.gather(
                mock_pool.generate_with_priority(
                    text="background",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.SCHEDULED,
                ),
                mock_pool.generate_with_priority(
                    text="live",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.LIVE,
                ),
            )

        # Both should have completed
        assert mock_pool._live_requests == 1
        assert mock_pool._background_requests == 1

    @pytest.mark.asyncio
    async def test_error_tracking(self, mock_pool):
        """Errors should be tracked in stats."""
        async def mock_generate(*args, **kwargs):
            raise Exception("TTS server error")

        with patch.object(mock_pool, '_generate_tts', side_effect=mock_generate):
            with pytest.raises(Exception):
                await mock_pool.generate_with_priority(
                    text="test",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.LIVE,
                )

        assert mock_pool._errors == 1

    @pytest.mark.asyncio
    async def test_stats_after_requests(self, mock_pool):
        """Stats should accurately reflect request counts."""
        async def mock_generate(*args, **kwargs):
            return GenerationResult(b"audio", 24000, 1.0)

        with patch.object(mock_pool, '_generate_tts', side_effect=mock_generate):
            # 3 live, 2 background
            for _ in range(3):
                await mock_pool.generate_with_priority(
                    text="live",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.LIVE,
                )

            for _ in range(2):
                await mock_pool.generate_with_priority(
                    text="background",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.SCHEDULED,
                )

        stats = mock_pool.get_stats()
        assert stats["live_requests"] == 3
        assert stats["background_requests"] == 2
        assert stats["live_in_flight"] == 0
        assert stats["background_in_flight"] == 0


class TestResourcePoolStress:
    """Stress tests for resource pool."""

    @pytest.mark.asyncio
    async def test_high_concurrency(self):
        """Test with many concurrent requests."""
        pool = TTSResourcePool(max_concurrent_live=5, max_concurrent_background=2)

        max_live_concurrent = 0
        max_bg_concurrent = 0
        live_concurrent = 0
        bg_concurrent = 0
        lock = asyncio.Lock()

        async def mock_generate(*args, **kwargs):
            await asyncio.sleep(0.01)  # Small delay
            return GenerationResult(b"audio", 24000, 1.0)

        with patch.object(pool, '_generate_tts', side_effect=mock_generate):
            # 50 live + 20 background requests
            live_tasks = [
                pool.generate_with_priority(
                    text=f"live {i}",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.LIVE,
                )
                for i in range(50)
            ]

            bg_tasks = [
                pool.generate_with_priority(
                    text=f"bg {i}",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.SCHEDULED,
                )
                for i in range(20)
            ]

            await asyncio.gather(*live_tasks, *bg_tasks)

        stats = pool.get_stats()
        assert stats["live_requests"] == 50
        assert stats["background_requests"] == 20
        assert stats["errors"] == 0
