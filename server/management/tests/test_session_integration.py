# Session Cache Integration Tests
# Tests for the bridge between user sessions and TTS cache

import tempfile
from pathlib import Path
from unittest.mock import patch
import pytest

from fov_context import UserSession, UserVoiceConfig, PlaybackState, SessionManager
from tts_cache import TTSCache, TTSResourcePool, TTSCacheKey
from session_cache_integration import SessionCacheIntegration, estimate_generation_time


class TestUserVoiceConfig:
    """Tests for UserVoiceConfig."""

    def test_default_config(self):
        """Test default voice configuration."""
        config = UserVoiceConfig()
        assert config.voice_id == "nova"
        assert config.tts_provider == "vibevoice"
        assert config.speed == 1.0
        assert config.exaggeration is None

    def test_to_dict(self):
        """Test serialization to dict."""
        config = UserVoiceConfig(
            voice_id="shimmer",
            tts_provider="chatterbox",
            speed=1.2,
            exaggeration=0.5,
        )
        d = config.to_dict()
        assert d["voice_id"] == "shimmer"
        assert d["tts_provider"] == "chatterbox"
        assert d["speed"] == 1.2
        assert d["exaggeration"] == 0.5

    def test_get_chatterbox_config_vibevoice(self):
        """Non-chatterbox providers return None for chatterbox config."""
        config = UserVoiceConfig(tts_provider="vibevoice", exaggeration=0.5)
        assert config.get_chatterbox_config() is None

    def test_get_chatterbox_config_chatterbox(self):
        """Chatterbox provider returns config dict."""
        config = UserVoiceConfig(
            tts_provider="chatterbox",
            exaggeration=0.5,
            cfg_weight=0.7,
        )
        cb_config = config.get_chatterbox_config()
        assert cb_config == {"exaggeration": 0.5, "cfg_weight": 0.7}


class TestPlaybackState:
    """Tests for PlaybackState."""

    def test_default_state(self):
        """Test default playback state."""
        state = PlaybackState()
        assert state.curriculum_id == ""
        assert state.segment_index == 0
        assert state.is_playing is False

    def test_update_position(self):
        """Test updating playback position."""
        state = PlaybackState()
        state.update_position(5, 1500, True)

        assert state.segment_index == 5
        assert state.segment_offset_ms == 1500
        assert state.is_playing is True
        assert state.last_heartbeat is not None

    def test_set_topic(self):
        """Test setting current topic."""
        state = PlaybackState()
        state.set_topic("physics-101", "quantum-intro")

        assert state.curriculum_id == "physics-101"
        assert state.topic_id == "quantum-intro"
        assert state.segment_index == 0


class TestUserSession:
    """Tests for UserSession."""

    def test_create(self):
        """Test creating a user session."""
        session = UserSession.create("user-123", "org-456")

        assert session.user_id == "user-123"
        assert session.organization_id == "org-456"
        assert session.session_id is not None
        assert session.voice_config is not None

    def test_update_voice_config(self):
        """Test updating voice configuration."""
        session = UserSession.create("user-123")
        session.update_voice_config(voice_id="shimmer", speed=1.5)

        assert session.voice_config.voice_id == "shimmer"
        assert session.voice_config.speed == 1.5

    def test_update_playback(self):
        """Test updating playback state."""
        session = UserSession.create("user-123")
        session.update_playback(10, 2000, True)

        assert session.playback_state.segment_index == 10
        assert session.playback_state.segment_offset_ms == 2000

    def test_get_state(self):
        """Test getting session state dict."""
        session = UserSession.create("user-123")
        session.set_current_topic("physics", "topic-1")

        state = session.get_state()
        assert state["user_id"] == "user-123"
        assert state["playback_state"]["curriculum_id"] == "physics"
        assert "voice_config" in state


class TestSessionManager:
    """Tests for SessionManager with user sessions."""

    def test_create_user_session(self):
        """Test creating a user session."""
        manager = SessionManager()
        session = manager.create_user_session("user-123")

        assert session.user_id == "user-123"
        assert manager.get_user_session(session.session_id) == session

    def test_get_user_session_by_user(self):
        """Test getting session by user ID."""
        manager = SessionManager()
        session = manager.create_user_session("user-123")

        found = manager.get_user_session_by_user("user-123")
        assert found == session

    def test_create_returns_existing(self):
        """Creating session for same user returns existing session."""
        manager = SessionManager()
        session1 = manager.create_user_session("user-123")
        session2 = manager.create_user_session("user-123")

        assert session1 is session2

    def test_end_user_session(self):
        """Test ending a user session."""
        manager = SessionManager()
        session = manager.create_user_session("user-123")

        assert manager.end_user_session(session.session_id) is True
        assert manager.get_user_session(session.session_id) is None
        assert manager.get_user_session_by_user("user-123") is None

    def test_list_user_sessions(self):
        """Test listing all user sessions."""
        manager = SessionManager()
        manager.create_user_session("user-1")
        manager.create_user_session("user-2")
        manager.create_user_session("user-3")

        sessions = manager.list_user_sessions()
        assert len(sessions) == 3


class TestSessionCacheIntegration:
    """Tests for SessionCacheIntegration."""

    @pytest.fixture
    def cache_dir(self):
        """Create temporary directory for cache."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield Path(tmpdir)

    @pytest.fixture
    async def setup(self, cache_dir):
        """Set up cache, pool, and integration."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        pool = TTSResourcePool(max_concurrent_live=2, max_concurrent_background=1)

        integration = SessionCacheIntegration(cache, pool)

        return cache, pool, integration

    @pytest.mark.asyncio
    async def test_get_audio_cache_hit(self, setup):
        """Test getting audio when it's already cached."""
        cache, pool, integration = setup

        session = UserSession.create("user-123")

        # Pre-populate cache
        key = TTSCacheKey.from_request(
            text="Hello world",
            voice_id=session.voice_config.voice_id,
            provider=session.voice_config.tts_provider,
            speed=session.voice_config.speed,
        )
        await cache.put(key, b"cached audio", 24000, 1.5)

        # Get through integration
        audio, cache_hit, duration = await integration.get_audio_for_segment(
            session, "Hello world"
        )

        assert audio == b"cached audio"
        assert cache_hit is True
        assert duration == 1.5

    @pytest.mark.asyncio
    async def test_get_audio_cache_miss(self, setup):
        """Test getting audio when not cached (generates new)."""
        cache, pool, integration = setup

        session = UserSession.create("user-123")

        # Mock the pool's generate method
        async def mock_generate(*args, **kwargs):
            from tts_cache.resource_pool import GenerationResult
            return GenerationResult(b"generated audio", 24000, 2.0)

        with patch.object(pool, '_generate_tts', side_effect=mock_generate):
            audio, cache_hit, duration = await integration.get_audio_for_segment(
                session, "New text"
            )

        assert audio == b"generated audio"
        assert cache_hit is False
        assert duration == 2.0

        # Should now be cached
        key = TTSCacheKey.from_request(
            text="New text",
            voice_id=session.voice_config.voice_id,
            provider=session.voice_config.tts_provider,
            speed=session.voice_config.speed,
        )
        assert await cache.has(key)

    @pytest.mark.asyncio
    async def test_session_stats_tracking(self, setup):
        """Test that session stats are tracked."""
        cache, pool, integration = setup

        session = UserSession.create("user-123")

        # Pre-populate cache
        key = TTSCacheKey.from_request(
            text="Hello",
            voice_id=session.voice_config.voice_id,
            provider=session.voice_config.tts_provider,
            speed=session.voice_config.speed,
        )
        await cache.put(key, b"audio", 24000, 1.0)

        # Get (hit)
        await integration.get_audio_for_segment(session, "Hello")

        stats = integration.get_session_stats(session.session_id)
        assert stats["hits"] == 1
        assert stats["misses"] == 0

    @pytest.mark.asyncio
    async def test_check_cache_coverage(self, setup):
        """Test checking cache coverage for segments."""
        cache, pool, integration = setup

        voice_config = UserVoiceConfig()

        # Pre-cache 2 of 5 segments
        for text in ["seg1", "seg2"]:
            key = TTSCacheKey.from_request(
                text=text,
                voice_id=voice_config.voice_id,
                provider=voice_config.tts_provider,
                speed=voice_config.speed,
            )
            await cache.put(key, b"audio", 24000, 1.0)

        segments = ["seg1", "seg2", "seg3", "seg4", "seg5"]
        coverage = await integration.check_cache_coverage(voice_config, segments)

        assert coverage["total_segments"] == 5
        assert coverage["cached_segments"] == 2
        assert coverage["missing_segments"] == 3
        assert coverage["coverage_percent"] == 40.0

    @pytest.mark.asyncio
    async def test_cross_user_cache_sharing(self, setup):
        """Two users with same voice config share cache."""
        cache, pool, integration = setup

        # Two users with identical voice config
        user1 = UserSession.create("user-1")
        user2 = UserSession.create("user-2")

        # Both use default config (nova, vibevoice, 1.0)
        assert user1.voice_config.voice_id == user2.voice_config.voice_id
        assert user1.voice_config.tts_provider == user2.voice_config.tts_provider

        # Pre-populate cache
        key = TTSCacheKey.from_request(
            text="Shared content",
            voice_id=user1.voice_config.voice_id,
            provider=user1.voice_config.tts_provider,
            speed=user1.voice_config.speed,
        )
        await cache.put(key, b"shared audio", 24000, 1.0)

        # User 1 gets cache hit
        audio1, hit1, _ = await integration.get_audio_for_segment(user1, "Shared content")
        assert hit1 is True

        # User 2 also gets cache hit (same audio!)
        audio2, hit2, _ = await integration.get_audio_for_segment(user2, "Shared content")
        assert hit2 is True
        assert audio1 == audio2

    @pytest.mark.asyncio
    async def test_different_voice_config_separate_cache(self, setup):
        """Users with different voice configs have separate cache entries."""
        cache, pool, integration = setup

        user1 = UserSession.create("user-1")
        user2 = UserSession.create("user-2")

        # User 2 uses different voice
        user2.update_voice_config(voice_id="shimmer")

        # Pre-populate cache for user1's config only
        key = TTSCacheKey.from_request(
            text="Hello",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key, b"nova audio", 24000, 1.0)

        # Mock generation for user2's different voice
        async def mock_generate(*args, **kwargs):
            from tts_cache.resource_pool import GenerationResult
            return GenerationResult(b"shimmer audio", 24000, 1.0)

        with patch.object(pool, '_generate_tts', side_effect=mock_generate):
            # User 1 gets cache hit (nova)
            audio1, hit1, _ = await integration.get_audio_for_segment(user1, "Hello")
            assert hit1 is True
            assert audio1 == b"nova audio"

            # User 2 gets cache miss (shimmer not cached)
            audio2, hit2, _ = await integration.get_audio_for_segment(user2, "Hello")
            assert hit2 is False
            assert audio2 == b"shimmer audio"


class TestEstimateGenerationTime:
    """Tests for generation time estimation."""

    @pytest.fixture
    def cache_dir(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            yield Path(tmpdir)

    @pytest.mark.asyncio
    async def test_estimate_all_missing(self, cache_dir):
        """Test estimate when all segments are missing."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        voice_config = UserVoiceConfig()
        segments = ["seg1", "seg2", "seg3", "seg4", "seg5"]

        estimate = await estimate_generation_time(
            segments, voice_config, cache, avg_generation_time_ms=500.0
        )

        assert estimate["missing_segments"] == 5
        assert estimate["estimated_time_ms"] == 2500.0
        assert estimate["estimated_time_seconds"] == 2.5

    @pytest.mark.asyncio
    async def test_estimate_some_cached(self, cache_dir):
        """Test estimate when some segments are cached."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        voice_config = UserVoiceConfig()

        # Cache 3 segments
        for text in ["seg1", "seg2", "seg3"]:
            key = TTSCacheKey.from_request(
                text=text,
                voice_id=voice_config.voice_id,
                provider=voice_config.tts_provider,
                speed=voice_config.speed,
            )
            await cache.put(key, b"audio", 24000, 1.0)

        segments = ["seg1", "seg2", "seg3", "seg4", "seg5"]

        estimate = await estimate_generation_time(
            segments, voice_config, cache, avg_generation_time_ms=500.0
        )

        assert estimate["missing_segments"] == 2
        assert estimate["estimated_time_ms"] == 1000.0
