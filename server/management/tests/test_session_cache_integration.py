"""
Tests for Session-Cache Integration

Comprehensive tests for bridging user sessions with global TTS cache.
Tests verify cache-first retrieval, prefetching, and session analytics.
"""

import pytest
from unittest.mock import MagicMock, AsyncMock

from session_cache_integration import (
    SessionCacheIntegration,
    estimate_generation_time,
)


# =============================================================================
# MOCK CLASSES
# =============================================================================


class MockVoiceConfig:
    """Mock voice configuration."""

    def __init__(
        self,
        voice_id: str = "nova",
        tts_provider: str = "vibevoice",
        speed: float = 1.0,
        exaggeration: float = None,
        cfg_weight: float = None,
        language: str = None,
    ):
        self.voice_id = voice_id
        self.tts_provider = tts_provider
        self.speed = speed
        self.exaggeration = exaggeration
        self.cfg_weight = cfg_weight
        self.language = language

    def get_chatterbox_config(self):
        return None


class MockPlaybackState:
    """Mock playback state."""

    def __init__(self, curriculum_id: str = "test-curriculum", topic_id: str = "test-topic"):
        self.curriculum_id = curriculum_id
        self.topic_id = topic_id
        self.segment_index = 0


class MockUserSession:
    """Mock user session."""

    def __init__(
        self,
        session_id: str = "test-session",
        voice_config: MockVoiceConfig = None,
        prefetch_lookahead: int = 3,
    ):
        self.session_id = session_id
        self.voice_config = voice_config or MockVoiceConfig()
        self.prefetch_lookahead = prefetch_lookahead
        self.playback_state = MockPlaybackState()


class MockCacheEntry:
    """Mock cache entry."""

    def __init__(self, duration_seconds: float = 2.5):
        self.duration_seconds = duration_seconds


class MockAsyncLock:
    """Mock async lock for testing."""

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass


class MockTTSCache:
    """Mock TTS cache."""

    def __init__(self):
        self._data = {}
        self._has_keys = set()
        self.index = {}
        self._lock = MockAsyncLock()
        self.put_calls = []
        self.get_calls = []

    async def get(self, key):
        self.get_calls.append(key)
        hash_key = key.to_hash()
        return self._data.get(hash_key)

    async def put(self, key, audio_data, sample_rate, duration):
        hash_key = key.to_hash()
        self._data[hash_key] = audio_data
        self.index[hash_key] = MockCacheEntry(duration)
        self.put_calls.append((key, audio_data, sample_rate, duration))

    async def has(self, key):
        hash_key = key.to_hash()
        return hash_key in self._has_keys or hash_key in self._data

    def add_cached_entry(self, key, audio_data: bytes = b"cached-audio", duration: float = 2.5):
        """Helper to pre-populate cache."""
        hash_key = key.to_hash()
        self._data[hash_key] = audio_data
        self._has_keys.add(hash_key)
        self.index[hash_key] = MockCacheEntry(duration)


class MockResourcePool:
    """Mock TTS resource pool."""

    def __init__(self):
        self.generate_calls = []
        self._audio_data = b"generated-audio"
        self._sample_rate = 24000
        self._duration = 3.0
        self._should_fail = False

    async def generate_with_priority(self, **kwargs):
        self.generate_calls.append(kwargs)

        if self._should_fail:
            raise Exception("TTS generation failed")

        return self._audio_data, self._sample_rate, self._duration


class MockPrefetcher:
    """Mock curriculum prefetcher."""

    def __init__(self):
        self.prefetch_calls = []

    async def prefetch_upcoming(self, **kwargs):
        self.prefetch_calls.append(kwargs)


# =============================================================================
# SESSION CACHE INTEGRATION TESTS
# =============================================================================


class TestSessionCacheIntegrationInit:
    """Tests for SessionCacheIntegration initialization."""

    def test_init_stores_dependencies(self):
        """Test init stores cache and resource pool."""
        cache = MockTTSCache()
        pool = MockResourcePool()

        integration = SessionCacheIntegration(cache, pool)

        assert integration.cache is cache
        assert integration.resource_pool is pool
        assert integration._session_stats == {}

    def test_init_with_prefetcher(self):
        """Test init with optional prefetcher."""
        cache = MockTTSCache()
        pool = MockResourcePool()
        prefetcher = MockPrefetcher()

        integration = SessionCacheIntegration(cache, pool, prefetcher)

        assert integration.prefetcher is prefetcher


# =============================================================================
# GET AUDIO TESTS
# =============================================================================


class TestGetAudioForSegment:
    """Tests for get_audio_for_segment method."""

    @pytest.fixture
    def integration(self):
        """Create integration with mocks."""
        cache = MockTTSCache()
        pool = MockResourcePool()
        return SessionCacheIntegration(cache, pool)

    @pytest.fixture
    def session(self):
        """Create test session."""
        return MockUserSession()

    @pytest.mark.asyncio
    async def test_get_audio_cache_hit(self, integration, session):
        """Test getting audio from cache."""
        # Pre-populate cache
        from tts_cache import TTSCacheKey

        key = TTSCacheKey.from_request(
            text="Test segment",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        integration.cache.add_cached_entry(key, b"cached-audio", 2.5)

        audio, was_hit, duration = await integration.get_audio_for_segment(
            session, "Test segment"
        )

        assert audio == b"cached-audio"
        assert was_hit is True
        assert duration == 2.5

    @pytest.mark.asyncio
    async def test_get_audio_cache_miss_generates(self, integration, session):
        """Test cache miss triggers generation."""
        audio, was_hit, duration = await integration.get_audio_for_segment(
            session, "New segment"
        )

        assert audio == b"generated-audio"
        assert was_hit is False
        assert duration == 3.0
        assert len(integration.resource_pool.generate_calls) == 1

    @pytest.mark.asyncio
    async def test_get_audio_uses_session_voice_config(self, integration):
        """Test generation uses session's voice config."""
        session = MockUserSession(
            voice_config=MockVoiceConfig(
                voice_id="shimmer",
                tts_provider="openai",
                speed=1.5,
            )
        )

        await integration.get_audio_for_segment(session, "Test segment")

        call = integration.resource_pool.generate_calls[0]
        assert call["voice_id"] == "shimmer"
        assert call["provider"] == "openai"
        assert call["speed"] == 1.5

    @pytest.mark.asyncio
    async def test_get_audio_stores_in_cache(self, integration, session):
        """Test generated audio is stored in cache."""
        await integration.get_audio_for_segment(session, "Store test")

        assert len(integration.cache.put_calls) == 1

    @pytest.mark.asyncio
    async def test_get_audio_records_hit_stats(self, integration, session):
        """Test cache hit records stats."""
        from tts_cache import TTSCacheKey

        key = TTSCacheKey.from_request(
            text="Stats test",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        integration.cache.add_cached_entry(key)

        await integration.get_audio_for_segment(session, "Stats test")

        stats = integration.get_session_stats(session.session_id)
        assert stats["hits"] == 1
        assert stats["misses"] == 0

    @pytest.mark.asyncio
    async def test_get_audio_records_miss_stats(self, integration, session):
        """Test cache miss records stats."""
        await integration.get_audio_for_segment(session, "Miss test")

        stats = integration.get_session_stats(session.session_id)
        assert stats["hits"] == 0
        assert stats["misses"] == 1

    @pytest.mark.asyncio
    async def test_get_audio_raises_on_generation_error(self, integration, session):
        """Test generation error is propagated."""
        integration.resource_pool._should_fail = True

        with pytest.raises(Exception, match="TTS generation failed"):
            await integration.get_audio_for_segment(session, "Fail test")

    @pytest.mark.asyncio
    async def test_get_audio_live_priority(self, integration, session):
        """Test generation uses LIVE priority."""
        from tts_cache import Priority

        await integration.get_audio_for_segment(session, "Priority test")

        call = integration.resource_pool.generate_calls[0]
        assert call["priority"] == Priority.LIVE


# =============================================================================
# CACHE COVERAGE TESTS
# =============================================================================


class TestCheckCacheCoverage:
    """Tests for check_cache_coverage method."""

    @pytest.fixture
    def integration(self):
        """Create integration."""
        cache = MockTTSCache()
        pool = MockResourcePool()
        return SessionCacheIntegration(cache, pool)

    @pytest.mark.asyncio
    async def test_coverage_all_cached(self, integration):
        """Test coverage when all segments are cached."""
        voice_config = MockVoiceConfig()

        from tts_cache import TTSCacheKey

        segments = ["Seg 1", "Seg 2", "Seg 3"]
        for text in segments:
            key = TTSCacheKey.from_request(
                text=text,
                voice_id=voice_config.voice_id,
                provider=voice_config.tts_provider,
                speed=voice_config.speed,
            )
            integration.cache.add_cached_entry(key)

        result = await integration.check_cache_coverage(voice_config, segments)

        assert result["total_segments"] == 3
        assert result["cached_segments"] == 3
        assert result["missing_segments"] == 0
        assert result["coverage_percent"] == 100.0

    @pytest.mark.asyncio
    async def test_coverage_none_cached(self, integration):
        """Test coverage when no segments are cached."""
        voice_config = MockVoiceConfig()
        segments = ["New 1", "New 2", "New 3"]

        result = await integration.check_cache_coverage(voice_config, segments)

        assert result["total_segments"] == 3
        assert result["cached_segments"] == 0
        assert result["missing_segments"] == 3
        assert result["coverage_percent"] == 0.0

    @pytest.mark.asyncio
    async def test_coverage_partial(self, integration):
        """Test coverage with partial caching."""
        voice_config = MockVoiceConfig()

        from tts_cache import TTSCacheKey

        # Cache first segment only
        key = TTSCacheKey.from_request(
            text="Partial 1",
            voice_id=voice_config.voice_id,
            provider=voice_config.tts_provider,
            speed=voice_config.speed,
        )
        integration.cache.add_cached_entry(key)

        segments = ["Partial 1", "Partial 2"]
        result = await integration.check_cache_coverage(voice_config, segments)

        assert result["cached_segments"] == 1
        assert result["missing_segments"] == 1
        assert result["coverage_percent"] == 50.0

    @pytest.mark.asyncio
    async def test_coverage_empty_segments(self, integration):
        """Test coverage with empty segment list."""
        voice_config = MockVoiceConfig()

        result = await integration.check_cache_coverage(voice_config, [])

        assert result["total_segments"] == 0
        assert result["coverage_percent"] == 100.0


# =============================================================================
# PREFETCH TESTS
# =============================================================================


class TestPrefetchUpcoming:
    """Tests for prefetch_upcoming method."""

    @pytest.fixture
    def integration(self):
        """Create integration with prefetcher."""
        cache = MockTTSCache()
        pool = MockResourcePool()
        prefetcher = MockPrefetcher()
        return SessionCacheIntegration(cache, pool, prefetcher)

    @pytest.fixture
    def session(self):
        """Create test session."""
        return MockUserSession(prefetch_lookahead=3)

    @pytest.mark.asyncio
    async def test_prefetch_calls_prefetcher(self, integration, session):
        """Test prefetch calls prefetcher."""
        segments = ["Seg 1", "Seg 2", "Seg 3", "Seg 4"]

        await integration.prefetch_upcoming(session, 0, segments)

        assert len(integration.prefetcher.prefetch_calls) == 1

    @pytest.mark.asyncio
    async def test_prefetch_uses_session_config(self, integration, session):
        """Test prefetch uses session voice config."""
        session.voice_config = MockVoiceConfig(voice_id="alloy")
        segments = ["Seg 1", "Seg 2"]

        await integration.prefetch_upcoming(session, 0, segments)

        call = integration.prefetcher.prefetch_calls[0]
        assert call["voice_id"] == "alloy"

    @pytest.mark.asyncio
    async def test_prefetch_uses_session_lookahead(self, integration, session):
        """Test prefetch uses session's lookahead setting."""
        session.prefetch_lookahead = 5
        segments = ["Seg " + str(i) for i in range(10)]

        await integration.prefetch_upcoming(session, 0, segments)

        call = integration.prefetcher.prefetch_calls[0]
        assert call["lookahead"] == 5

    @pytest.mark.asyncio
    async def test_prefetch_custom_lookahead(self, integration, session):
        """Test prefetch with custom lookahead override."""
        segments = ["Seg 1", "Seg 2", "Seg 3"]

        await integration.prefetch_upcoming(session, 0, segments, lookahead=2)

        call = integration.prefetcher.prefetch_calls[0]
        assert call["lookahead"] == 2

    @pytest.mark.asyncio
    async def test_prefetch_no_prefetcher(self):
        """Test prefetch does nothing without prefetcher."""
        cache = MockTTSCache()
        pool = MockResourcePool()
        integration = SessionCacheIntegration(cache, pool, prefetcher=None)
        session = MockUserSession()

        # Should not raise
        await integration.prefetch_upcoming(session, 0, ["Seg 1"])


# =============================================================================
# SESSION STATS TESTS
# =============================================================================


class TestSessionStats:
    """Tests for session statistics management."""

    @pytest.fixture
    def integration(self):
        """Create integration."""
        return SessionCacheIntegration(MockTTSCache(), MockResourcePool())

    def test_get_session_stats_empty(self, integration):
        """Test getting stats for unknown session."""
        result = integration.get_session_stats("unknown-session")

        assert result is None

    def test_get_all_session_stats(self, integration):
        """Test getting all session stats."""
        integration._session_stats["session-1"] = {"hits": 5, "misses": 2}
        integration._session_stats["session-2"] = {"hits": 3, "misses": 1}

        result = integration.get_all_session_stats()

        assert len(result) == 2
        assert "session-1" in result
        assert "session-2" in result

    def test_clear_session_stats(self, integration):
        """Test clearing session stats."""
        integration._session_stats["session-1"] = {"hits": 5, "misses": 2}

        integration.clear_session_stats("session-1")

        assert integration.get_session_stats("session-1") is None

    def test_clear_session_stats_nonexistent(self, integration):
        """Test clearing stats for non-existent session."""
        # Should not raise
        integration.clear_session_stats("nonexistent")

    def test_record_hit_creates_stats(self, integration):
        """Test recording hit creates stats entry."""
        integration._record_hit("new-session")

        stats = integration.get_session_stats("new-session")
        assert stats["hits"] == 1
        assert stats["misses"] == 0

    def test_record_hit_increments(self, integration):
        """Test recording hit increments counter."""
        integration._record_hit("session-1")
        integration._record_hit("session-1")
        integration._record_hit("session-1")

        stats = integration.get_session_stats("session-1")
        assert stats["hits"] == 3

    def test_record_miss_creates_stats(self, integration):
        """Test recording miss creates stats entry."""
        integration._record_miss("new-session")

        stats = integration.get_session_stats("new-session")
        assert stats["hits"] == 0
        assert stats["misses"] == 1

    def test_record_miss_increments(self, integration):
        """Test recording miss increments counter."""
        integration._record_miss("session-1")
        integration._record_miss("session-1")

        stats = integration.get_session_stats("session-1")
        assert stats["misses"] == 2


# =============================================================================
# ESTIMATE GENERATION TIME TESTS
# =============================================================================


class TestEstimateGenerationTime:
    """Tests for estimate_generation_time function."""

    @pytest.fixture
    def cache(self):
        """Create mock cache."""
        return MockTTSCache()

    @pytest.fixture
    def voice_config(self):
        """Create voice config."""
        return MockVoiceConfig()

    @pytest.mark.asyncio
    async def test_estimate_all_missing(self, cache, voice_config):
        """Test estimate when all segments missing."""
        segments = ["Seg 1", "Seg 2", "Seg 3"]

        result = await estimate_generation_time(
            segments, voice_config, cache, avg_generation_time_ms=500.0
        )

        assert result["missing_segments"] == 3
        assert result["estimated_time_ms"] == 1500.0
        assert result["estimated_time_seconds"] == 1.5

    @pytest.mark.asyncio
    async def test_estimate_none_missing(self, cache, voice_config):
        """Test estimate when all segments cached."""
        from tts_cache import TTSCacheKey

        segments = ["Cached 1", "Cached 2"]
        for text in segments:
            key = TTSCacheKey.from_request(
                text=text,
                voice_id=voice_config.voice_id,
                provider=voice_config.tts_provider,
                speed=voice_config.speed,
            )
            cache.add_cached_entry(key)

        result = await estimate_generation_time(segments, voice_config, cache)

        assert result["missing_segments"] == 0
        assert result["estimated_time_ms"] == 0

    @pytest.mark.asyncio
    async def test_estimate_custom_avg_time(self, cache, voice_config):
        """Test estimate with custom average time."""
        segments = ["Seg 1", "Seg 2"]

        result = await estimate_generation_time(
            segments, voice_config, cache, avg_generation_time_ms=1000.0
        )

        assert result["estimated_time_ms"] == 2000.0
        assert result["estimated_time_seconds"] == 2.0

    @pytest.mark.asyncio
    async def test_estimate_empty_segments(self, cache, voice_config):
        """Test estimate with empty segment list."""
        result = await estimate_generation_time([], voice_config, cache)

        assert result["missing_segments"] == 0
        assert result["estimated_time_ms"] == 0

    @pytest.mark.asyncio
    async def test_estimate_returns_minutes(self, cache, voice_config):
        """Test estimate includes minutes calculation."""
        segments = [f"Seg {i}" for i in range(120)]  # 120 segments

        result = await estimate_generation_time(
            segments, voice_config, cache, avg_generation_time_ms=500.0
        )

        assert "estimated_time_minutes" in result
        assert result["estimated_time_minutes"] == 1.0  # 60 seconds


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
