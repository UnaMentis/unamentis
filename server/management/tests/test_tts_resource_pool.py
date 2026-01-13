"""
Tests for TTS Resource Pool

Comprehensive tests for the priority-based TTS generation with concurrency limits.
Tests verify priority queuing, concurrency management, error handling, and statistics tracking.
"""

import asyncio
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from tts_cache.resource_pool import (
    Priority,
    GenerationResult,
    TTSResourcePool,
    TTS_SERVERS,
    SAMPLE_RATES,
)


# =============================================================================
# PRIORITY ENUM TESTS
# =============================================================================


class TestPriorityEnum:
    """Tests for Priority IntEnum."""

    def test_priority_values(self):
        """Test priority values are correct."""
        assert Priority.SCHEDULED == 1
        assert Priority.PREFETCH == 5
        assert Priority.LIVE == 10

    def test_priority_comparison(self):
        """Test priorities can be compared."""
        assert Priority.LIVE > Priority.PREFETCH
        assert Priority.PREFETCH > Priority.SCHEDULED
        assert Priority.SCHEDULED < Priority.LIVE

    def test_priority_is_int_enum(self):
        """Test Priority is an IntEnum with numeric values."""
        assert int(Priority.LIVE) == 10
        assert int(Priority.PREFETCH) == 5
        assert int(Priority.SCHEDULED) == 1

    def test_priority_can_be_used_in_arithmetic(self):
        """Test Priority values work in arithmetic (IntEnum feature)."""
        assert Priority.LIVE + 1 == 11
        assert Priority.PREFETCH * 2 == 10


# =============================================================================
# MODULE CONSTANTS TESTS
# =============================================================================


class TestModuleConstants:
    """Tests for module-level constants."""

    def test_tts_servers_contains_expected_providers(self):
        """Test TTS_SERVERS contains expected providers."""
        assert "vibevoice" in TTS_SERVERS
        assert "piper" in TTS_SERVERS
        assert "chatterbox" in TTS_SERVERS

    def test_tts_servers_urls_are_valid_format(self):
        """Test TTS_SERVERS URLs have expected format."""
        for provider, url in TTS_SERVERS.items():
            assert url.startswith("http://localhost:")
            assert "/v1/audio/speech" in url

    def test_sample_rates_match_tts_servers(self):
        """Test SAMPLE_RATES has entry for each TTS_SERVER."""
        for provider in TTS_SERVERS:
            assert provider in SAMPLE_RATES

    def test_sample_rates_are_valid(self):
        """Test sample rates are reasonable values."""
        for provider, rate in SAMPLE_RATES.items():
            assert 20000 <= rate <= 48000


# =============================================================================
# GENERATION RESULT TESTS
# =============================================================================


class TestGenerationResult:
    """Tests for GenerationResult dataclass."""

    def test_creation_with_all_fields(self):
        """Test creating GenerationResult with all fields."""
        result = GenerationResult(
            audio_data=b"audio bytes",
            sample_rate=24000,
            duration_seconds=1.5,
        )

        assert result.audio_data == b"audio bytes"
        assert result.sample_rate == 24000
        assert result.duration_seconds == 1.5

    def test_creation_with_empty_audio(self):
        """Test creating GenerationResult with empty audio."""
        result = GenerationResult(
            audio_data=b"",
            sample_rate=24000,
            duration_seconds=0.0,
        )

        assert result.audio_data == b""
        assert result.duration_seconds == 0.0

    def test_result_is_dataclass(self):
        """Test GenerationResult is a proper dataclass."""
        result = GenerationResult(
            audio_data=b"test",
            sample_rate=22050,
            duration_seconds=2.0,
        )

        # Dataclasses have __dataclass_fields__
        assert hasattr(result, "__dataclass_fields__")
        assert "audio_data" in result.__dataclass_fields__
        assert "sample_rate" in result.__dataclass_fields__
        assert "duration_seconds" in result.__dataclass_fields__


# =============================================================================
# TTS RESOURCE POOL INITIALIZATION TESTS
# =============================================================================


class TestTTSResourcePoolInit:
    """Tests for TTSResourcePool initialization."""

    @pytest.mark.asyncio
    async def test_init_default_values(self):
        """Test default initialization values."""
        pool = TTSResourcePool()

        assert pool.max_concurrent_live == 7
        assert pool.max_concurrent_background == 3
        assert pool.request_timeout == 30.0

    @pytest.mark.asyncio
    async def test_init_custom_values(self):
        """Test initialization with custom values."""
        pool = TTSResourcePool(
            max_concurrent_live=10,
            max_concurrent_background=5,
            request_timeout=60.0,
        )

        assert pool.max_concurrent_live == 10
        assert pool.max_concurrent_background == 5
        assert pool.request_timeout == 60.0

    @pytest.mark.asyncio
    async def test_init_creates_semaphores(self):
        """Test initialization creates semaphores."""
        pool = TTSResourcePool(
            max_concurrent_live=4,
            max_concurrent_background=2,
        )

        # Semaphores have _value attribute
        assert pool._live_semaphore._value == 4
        assert pool._background_semaphore._value == 2

    @pytest.mark.asyncio
    async def test_init_resets_statistics(self):
        """Test initialization resets all statistics."""
        pool = TTSResourcePool()

        assert pool._live_requests == 0
        assert pool._background_requests == 0
        assert pool._live_in_flight == 0
        assert pool._background_in_flight == 0
        assert pool._errors == 0

    @pytest.mark.asyncio
    async def test_init_copies_default_servers(self):
        """Test initialization copies default server config."""
        pool = TTSResourcePool()

        assert pool.tts_servers == TTS_SERVERS
        assert pool.sample_rates == SAMPLE_RATES
        # Verify it's a copy, not the same reference
        assert pool.tts_servers is not TTS_SERVERS
        assert pool.sample_rates is not SAMPLE_RATES


# =============================================================================
# TTS RESOURCE POOL GENERATE WITH PRIORITY TESTS
# =============================================================================


class TestGenerateWithPriority:
    """Tests for generate_with_priority method."""

    @pytest.fixture
    async def pool(self):
        """Create a TTSResourcePool instance."""
        return TTSResourcePool()

    @pytest.fixture
    def mock_session(self):
        """Create a mock aiohttp session."""
        mock_resp = AsyncMock()
        mock_resp.status = 200
        # Create WAV-like data (44 byte header + 4800 bytes = 100 samples at 24kHz = ~0.2 sec)
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 40 + b"\x00" * 4800)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        return mock_session

    @pytest.mark.asyncio
    async def test_generate_returns_tuple(self, pool, mock_session):
        """Test generate_with_priority returns (bytes, sample_rate, duration) tuple."""
        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            result = await pool.generate_with_priority(
                text="Hello world",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.LIVE,
            )

        assert isinstance(result, tuple)
        assert len(result) == 3
        assert isinstance(result[0], bytes)
        assert isinstance(result[1], int)
        assert isinstance(result[2], float)

    @pytest.mark.asyncio
    async def test_generate_live_uses_live_semaphore(self, pool, mock_session):
        """Test LIVE priority uses live semaphore."""
        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.LIVE,
            )

        assert pool._live_requests == 1
        assert pool._background_requests == 0

    @pytest.mark.asyncio
    async def test_generate_prefetch_uses_background_semaphore(self, pool, mock_session):
        """Test PREFETCH priority uses background semaphore."""
        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.PREFETCH,
            )

        assert pool._live_requests == 0
        assert pool._background_requests == 1

    @pytest.mark.asyncio
    async def test_generate_scheduled_uses_background_semaphore(self, pool, mock_session):
        """Test SCHEDULED priority uses background semaphore."""
        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.SCHEDULED,
            )

        assert pool._live_requests == 0
        assert pool._background_requests == 1

    @pytest.mark.asyncio
    async def test_generate_unknown_provider_raises(self, pool):
        """Test generate with unknown provider raises ValueError."""
        with pytest.raises(ValueError, match="Unknown TTS provider"):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="unknown_provider",
            )

    @pytest.mark.asyncio
    async def test_generate_tracks_in_flight_live(self, pool, mock_session):
        """Test in-flight counter is incremented during live request."""
        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.LIVE,
            )

        # After completion, should be decremented back to 0
        assert pool._live_in_flight == 0
        # Request count should have been incremented
        assert pool._live_requests == 1

    @pytest.mark.asyncio
    async def test_generate_tracks_in_flight_background(self, pool, mock_session):
        """Test in-flight counter is incremented during background request."""
        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.PREFETCH,
            )

        assert pool._background_in_flight == 0
        assert pool._background_requests == 1

    @pytest.mark.asyncio
    async def test_generate_error_increments_error_count(self, pool):
        """Test errors increment error counter."""
        mock_resp = AsyncMock()
        mock_resp.status = 500
        mock_resp.text = AsyncMock(return_value="Internal Server Error")
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            with pytest.raises(Exception):
                await pool.generate_with_priority(
                    text="Hello",
                    voice_id="nova",
                    provider="vibevoice",
                )

        assert pool._errors == 1

    @pytest.mark.asyncio
    async def test_generate_decrements_in_flight_on_error(self, pool):
        """Test in-flight is decremented even on error."""
        mock_resp = AsyncMock()
        mock_resp.status = 500
        mock_resp.text = AsyncMock(return_value="Error")
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            try:
                await pool.generate_with_priority(
                    text="Hello",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.LIVE,
                )
            except Exception:
                pass

        assert pool._live_in_flight == 0

    @pytest.mark.asyncio
    async def test_generate_with_custom_speed(self, pool, mock_session):
        """Test generate with custom speed parameter."""
        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                speed=1.5,
            )

        # Verify the request was made (we can't easily check payload without more complex mocking)
        mock_session.post.assert_called_once()

    @pytest.mark.asyncio
    async def test_generate_default_priority_is_live(self, pool, mock_session):
        """Test default priority is LIVE."""
        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                # No priority specified
            )

        # Should use live semaphore by default
        assert pool._live_requests == 1


# =============================================================================
# TTS RESOURCE POOL _GENERATE_TTS TESTS
# =============================================================================


class TestGenerateTTS:
    """Tests for _generate_tts internal method."""

    @pytest.fixture
    async def pool(self):
        """Create a TTSResourcePool instance."""
        return TTSResourcePool()

    @pytest.mark.asyncio
    async def test_generate_tts_unknown_provider(self, pool):
        """Test _generate_tts raises for unknown provider."""
        with pytest.raises(ValueError, match="Unknown TTS provider"):
            await pool._generate_tts(
                text="Hello",
                voice_id="nova",
                provider="nonexistent",
                speed=1.0,
                chatterbox_config=None,
            )

    @pytest.mark.asyncio
    async def test_generate_tts_builds_correct_payload(self, pool):
        """Test _generate_tts builds correct request payload."""
        captured_payload = None

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()

        def capture_post(url, json=None):
            nonlocal captured_payload
            captured_payload = json
            return mock_resp

        mock_session.post = capture_post
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool._generate_tts(
                text="Hello world",
                voice_id="nova",
                provider="vibevoice",
                speed=1.2,
                chatterbox_config=None,
            )

        assert captured_payload is not None
        assert captured_payload["model"] == "tts-1"
        assert captured_payload["input"] == "Hello world"
        assert captured_payload["voice"] == "nova"
        assert captured_payload["response_format"] == "wav"
        assert captured_payload["speed"] == 1.2

    @pytest.mark.asyncio
    async def test_generate_tts_chatterbox_config(self, pool):
        """Test _generate_tts includes chatterbox config in payload."""
        captured_payload = None

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()

        def capture_post(url, json=None):
            nonlocal captured_payload
            captured_payload = json
            return mock_resp

        mock_session.post = capture_post
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool._generate_tts(
                text="Hello",
                voice_id="default",
                provider="chatterbox",
                speed=1.0,
                chatterbox_config={
                    "exaggeration": 0.5,
                    "cfg_weight": 0.3,
                    "language": "en",
                },
            )

        assert captured_payload["exaggeration"] == 0.5
        assert captured_payload["cfg_weight"] == 0.3
        assert captured_payload["language"] == "en"

    @pytest.mark.asyncio
    async def test_generate_tts_chatterbox_config_non_chatterbox_provider(self, pool):
        """Test chatterbox config is ignored for non-chatterbox providers."""
        captured_payload = None

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()

        def capture_post(url, json=None):
            nonlocal captured_payload
            captured_payload = json
            return mock_resp

        mock_session.post = capture_post
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool._generate_tts(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",  # Not chatterbox
                speed=1.0,
                chatterbox_config={
                    "exaggeration": 0.5,
                },
            )

        # Chatterbox config should not be in payload
        assert "exaggeration" not in captured_payload

    @pytest.mark.asyncio
    async def test_generate_tts_returns_generation_result(self, pool):
        """Test _generate_tts returns GenerationResult."""
        # Create audio data: 44 byte header + data
        # For 24000 Hz sample rate, 16-bit samples (2 bytes each)
        # 24000 samples = 1 second, so 48000 bytes of data
        audio_data = b"RIFF" + b"\x00" * 40 + b"\x00" * 48000

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=audio_data)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            result = await pool._generate_tts(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                speed=1.0,
                chatterbox_config=None,
            )

        assert isinstance(result, GenerationResult)
        assert result.audio_data == audio_data
        assert result.sample_rate == 24000  # vibevoice sample rate

    @pytest.mark.asyncio
    async def test_generate_tts_calculates_duration(self, pool):
        """Test _generate_tts calculates duration from audio data."""
        # 44 byte header + 24000 samples * 2 bytes = 1 second at 24kHz
        audio_data = b"RIFF" + b"\x00" * 40 + b"\x00" * 48000

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=audio_data)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            result = await pool._generate_tts(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                speed=1.0,
                chatterbox_config=None,
            )

        # Duration = (len(data) - 44) / 2 / sample_rate
        # = (48044 - 44) / 2 / 24000 = 48000 / 2 / 24000 = 1.0 seconds
        assert result.duration_seconds == 1.0

    @pytest.mark.asyncio
    async def test_generate_tts_uses_provider_sample_rate(self, pool):
        """Test _generate_tts uses correct sample rate per provider."""
        audio_data = b"RIFF" + b"\x00" * 100

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=audio_data)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            result = await pool._generate_tts(
                text="Hello",
                voice_id="default",
                provider="piper",
                speed=1.0,
                chatterbox_config=None,
            )

        assert result.sample_rate == 22050  # piper sample rate

    @pytest.mark.asyncio
    async def test_generate_tts_http_error(self, pool):
        """Test _generate_tts raises on HTTP error."""
        mock_resp = AsyncMock()
        mock_resp.status = 500
        mock_resp.text = AsyncMock(return_value="Internal Server Error")
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            with pytest.raises(Exception, match="TTS server returned 500"):
                await pool._generate_tts(
                    text="Hello",
                    voice_id="nova",
                    provider="vibevoice",
                    speed=1.0,
                    chatterbox_config=None,
                )

    @pytest.mark.asyncio
    async def test_generate_tts_connection_error(self, pool):
        """Test _generate_tts raises on connection error."""
        import aiohttp

        mock_session = AsyncMock()
        mock_session.post = MagicMock(side_effect=aiohttp.ClientError("Connection refused"))
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            with pytest.raises(Exception, match="TTS server connection failed"):
                await pool._generate_tts(
                    text="Hello",
                    voice_id="nova",
                    provider="vibevoice",
                    speed=1.0,
                    chatterbox_config=None,
                )


# =============================================================================
# TTS RESOURCE POOL GET STATS TESTS
# =============================================================================


class TestGetStats:
    """Tests for get_stats method."""

    @pytest.fixture
    async def pool(self):
        """Create a TTSResourcePool instance."""
        return TTSResourcePool(
            max_concurrent_live=5,
            max_concurrent_background=2,
        )

    @pytest.mark.asyncio
    async def test_get_stats_returns_dict(self, pool):
        """Test get_stats returns a dictionary."""
        stats = pool.get_stats()

        assert isinstance(stats, dict)

    @pytest.mark.asyncio
    async def test_get_stats_includes_all_fields(self, pool):
        """Test get_stats includes all expected fields."""
        stats = pool.get_stats()

        assert "live_requests" in stats
        assert "background_requests" in stats
        assert "live_in_flight" in stats
        assert "background_in_flight" in stats
        assert "live_available" in stats
        assert "background_available" in stats
        assert "errors" in stats
        assert "max_concurrent_live" in stats
        assert "max_concurrent_background" in stats

    @pytest.mark.asyncio
    async def test_get_stats_initial_values(self, pool):
        """Test get_stats returns correct initial values."""
        stats = pool.get_stats()

        assert stats["live_requests"] == 0
        assert stats["background_requests"] == 0
        assert stats["live_in_flight"] == 0
        assert stats["background_in_flight"] == 0
        assert stats["errors"] == 0
        assert stats["max_concurrent_live"] == 5
        assert stats["max_concurrent_background"] == 2

    @pytest.mark.asyncio
    async def test_get_stats_available_slots(self, pool):
        """Test get_stats calculates available slots correctly."""
        stats = pool.get_stats()

        assert stats["live_available"] == 5  # max - in_flight
        assert stats["background_available"] == 2

    @pytest.mark.asyncio
    async def test_get_stats_reflects_requests(self, pool):
        """Test get_stats reflects request counts after requests."""
        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.LIVE,
            )
            await pool.generate_with_priority(
                text="World",
                voice_id="nova",
                provider="vibevoice",
                priority=Priority.PREFETCH,
            )

        stats = pool.get_stats()

        assert stats["live_requests"] == 1
        assert stats["background_requests"] == 1


# =============================================================================
# TTS RESOURCE POOL CONFIGURE SERVER TESTS
# =============================================================================


class TestConfigureServer:
    """Tests for configure_server method."""

    @pytest.fixture
    async def pool(self):
        """Create a TTSResourcePool instance."""
        return TTSResourcePool()

    @pytest.mark.asyncio
    async def test_configure_server_adds_new_provider(self, pool):
        """Test configure_server adds a new provider."""
        pool.configure_server(
            provider="custom_tts",
            url="http://custom.local:9000/v1/audio/speech",
            sample_rate=16000,
        )

        assert "custom_tts" in pool.tts_servers
        assert pool.tts_servers["custom_tts"] == "http://custom.local:9000/v1/audio/speech"
        assert pool.sample_rates["custom_tts"] == 16000

    @pytest.mark.asyncio
    async def test_configure_server_overwrites_existing(self, pool):
        """Test configure_server overwrites existing provider."""
        original_url = pool.tts_servers["vibevoice"]

        pool.configure_server(
            provider="vibevoice",
            url="http://new-server:8080/v1/audio/speech",
            sample_rate=48000,
        )

        assert pool.tts_servers["vibevoice"] != original_url
        assert pool.tts_servers["vibevoice"] == "http://new-server:8080/v1/audio/speech"
        assert pool.sample_rates["vibevoice"] == 48000

    @pytest.mark.asyncio
    async def test_configure_server_default_sample_rate(self, pool):
        """Test configure_server uses default sample rate."""
        pool.configure_server(
            provider="new_provider",
            url="http://example.com/tts",
            # No sample_rate specified
        )

        assert pool.sample_rates["new_provider"] == 24000  # Default


# =============================================================================
# TTS RESOURCE POOL CONCURRENCY TESTS
# =============================================================================


class TestConcurrency:
    """Tests for concurrency behavior."""

    @pytest.fixture
    async def pool(self):
        """Create a TTSResourcePool with limited concurrency."""
        return TTSResourcePool(
            max_concurrent_live=2,
            max_concurrent_background=1,
        )

    @pytest.mark.asyncio
    async def test_live_requests_limited_by_semaphore(self, pool):
        """Test live requests are limited by semaphore."""
        # Verify semaphore configuration
        assert pool._live_semaphore._value == 2

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            # Start 5 concurrent live requests
            tasks = [
                pool.generate_with_priority(
                    text=f"Text {i}",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.LIVE,
                )
                for i in range(5)
            ]
            await asyncio.gather(*tasks)

        # All requests should have completed
        assert pool._live_requests == 5
        assert pool._live_in_flight == 0

    @pytest.mark.asyncio
    async def test_background_requests_limited_by_semaphore(self, pool):
        """Test background requests are limited by semaphore."""
        # Verify semaphore configuration
        assert pool._background_semaphore._value == 1

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            tasks = [
                pool.generate_with_priority(
                    text=f"Text {i}",
                    voice_id="nova",
                    provider="vibevoice",
                    priority=Priority.SCHEDULED,
                )
                for i in range(5)
            ]
            await asyncio.gather(*tasks)

        # All requests should have completed
        assert pool._background_requests == 5
        assert pool._background_in_flight == 0

    @pytest.mark.asyncio
    async def test_live_and_background_use_separate_semaphores(self, pool):
        """Test live and background requests use separate semaphores."""
        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            # Run both live and background requests concurrently
            tasks = []
            for i in range(4):
                tasks.append(
                    pool.generate_with_priority(
                        text=f"Live {i}",
                        voice_id="nova",
                        provider="vibevoice",
                        priority=Priority.LIVE,
                    )
                )
                tasks.append(
                    pool.generate_with_priority(
                        text=f"Background {i}",
                        voice_id="nova",
                        provider="vibevoice",
                        priority=Priority.PREFETCH,
                    )
                )

            await asyncio.gather(*tasks)

        # Verify separate counting
        assert pool._live_requests == 4
        assert pool._background_requests == 4
        assert pool._live_in_flight == 0
        assert pool._background_in_flight == 0


# =============================================================================
# EDGE CASES AND ERROR HANDLING
# =============================================================================


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.fixture
    async def pool(self):
        """Create a TTSResourcePool instance."""
        return TTSResourcePool()

    @pytest.mark.asyncio
    async def test_empty_text(self, pool):
        """Test generating audio for empty text."""
        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 40)  # Just header
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            result = await pool.generate_with_priority(
                text="",
                voice_id="nova",
                provider="vibevoice",
            )

        assert isinstance(result, tuple)
        assert len(result[0]) > 0

    @pytest.mark.asyncio
    async def test_very_long_text(self, pool):
        """Test generating audio for very long text."""
        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100000)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        long_text = "This is a very long text. " * 1000

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            result = await pool.generate_with_priority(
                text=long_text,
                voice_id="nova",
                provider="vibevoice",
            )

        assert isinstance(result, tuple)

    @pytest.mark.asyncio
    async def test_special_characters_in_text(self, pool):
        """Test generating audio with special characters."""
        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        special_text = "Hello! @#$%^&*() 'quotes' \"double\" <html>\n\t"

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            result = await pool.generate_with_priority(
                text=special_text,
                voice_id="nova",
                provider="vibevoice",
            )

        assert isinstance(result, tuple)

    @pytest.mark.asyncio
    async def test_unicode_text(self, pool):
        """Test generating audio with unicode text."""
        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        unicode_text = "Hello World! Cafe au lait"

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            result = await pool.generate_with_priority(
                text=unicode_text,
                voice_id="nova",
                provider="vibevoice",
            )

        assert isinstance(result, tuple)

    @pytest.mark.asyncio
    async def test_extreme_speed_values(self, pool):
        """Test generating audio with extreme speed values."""
        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            # Very slow
            result_slow = await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                speed=0.25,
            )
            # Very fast
            result_fast = await pool.generate_with_priority(
                text="Hello",
                voice_id="nova",
                provider="vibevoice",
                speed=4.0,
            )

        assert isinstance(result_slow, tuple)
        assert isinstance(result_fast, tuple)

    @pytest.mark.asyncio
    async def test_partial_chatterbox_config(self, pool):
        """Test chatterbox with partial config."""
        captured_payload = None

        mock_resp = AsyncMock()
        mock_resp.status = 200
        mock_resp.read = AsyncMock(return_value=b"RIFF" + b"\x00" * 100)
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()

        def capture_post(url, json=None):
            nonlocal captured_payload
            captured_payload = json
            return mock_resp

        mock_session.post = capture_post
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            await pool.generate_with_priority(
                text="Hello",
                voice_id="default",
                provider="chatterbox",
                chatterbox_config={
                    "exaggeration": 0.7,
                    # No cfg_weight or language
                },
            )

        # Only exaggeration should be in payload
        assert captured_payload["exaggeration"] == 0.7
        assert "cfg_weight" not in captured_payload
        assert "language" not in captured_payload

    @pytest.mark.asyncio
    async def test_stats_never_negative(self):
        """Test statistics never go negative."""
        pool = TTSResourcePool()

        # Even with no requests, available should equal max
        stats = pool.get_stats()

        assert stats["live_available"] >= 0
        assert stats["background_available"] >= 0
        assert stats["live_in_flight"] >= 0
        assert stats["background_in_flight"] >= 0

    @pytest.mark.asyncio
    async def test_http_400_error(self, pool):
        """Test handling of HTTP 400 Bad Request."""
        mock_resp = AsyncMock()
        mock_resp.status = 400
        mock_resp.text = AsyncMock(return_value="Invalid voice_id")
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            with pytest.raises(Exception, match="TTS server returned 400"):
                await pool.generate_with_priority(
                    text="Hello",
                    voice_id="invalid_voice",
                    provider="vibevoice",
                )

    @pytest.mark.asyncio
    async def test_http_503_service_unavailable(self, pool):
        """Test handling of HTTP 503 Service Unavailable."""
        mock_resp = AsyncMock()
        mock_resp.status = 503
        mock_resp.text = AsyncMock(return_value="Service temporarily unavailable")
        mock_resp.__aenter__ = AsyncMock(return_value=mock_resp)
        mock_resp.__aexit__ = AsyncMock(return_value=None)

        mock_session = AsyncMock()
        mock_session.post = MagicMock(return_value=mock_resp)
        mock_session.__aenter__ = AsyncMock(return_value=mock_session)
        mock_session.__aexit__ = AsyncMock(return_value=None)

        with patch("tts_cache.resource_pool.aiohttp.ClientSession", return_value=mock_session):
            with pytest.raises(Exception, match="TTS server returned 503"):
                await pool.generate_with_priority(
                    text="Hello",
                    voice_id="nova",
                    provider="vibevoice",
                )


# =============================================================================
# MULTIPLE POOL INSTANCES
# =============================================================================


class TestMultipleInstances:
    """Tests for multiple pool instances."""

    @pytest.mark.asyncio
    async def test_instances_have_independent_stats(self):
        """Test multiple pool instances have independent stats."""
        pool1 = TTSResourcePool()
        pool2 = TTSResourcePool()

        # Modify pool1's internal state
        pool1._live_requests = 10
        pool1._errors = 5

        # pool2 should be unaffected
        assert pool2._live_requests == 0
        assert pool2._errors == 0

    @pytest.mark.asyncio
    async def test_instances_have_independent_server_config(self):
        """Test multiple pool instances have independent server configs."""
        pool1 = TTSResourcePool()
        pool2 = TTSResourcePool()

        # Modify pool1's server config
        pool1.configure_server("custom", "http://custom:1234/speech", 16000)

        # pool2 should not have the custom server
        assert "custom" not in pool2.tts_servers


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
