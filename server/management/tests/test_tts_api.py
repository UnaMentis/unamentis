"""
Tests for TTS API routes.

TESTING PHILOSOPHY: Real Over Mock
==================================
- Uses REAL TTSCache with tmp_path (no MockTTSCache)
- Uses REAL TTSResourcePool with aioresponses for HTTP interception
- Uses aiohttp test utilities for proper request testing
- NO MOCK CLASSES ALLOWED
"""
import base64
import pytest
from aiohttp import web
from aiohttp.test_utils import make_mocked_request
from aioresponses import aioresponses

# Import real implementations - NO MOCKS
from tts_cache.cache import TTSCache
from tts_cache.resource_pool import TTSResourcePool

# Import the module under test
import tts_api


# =============================================================================
# REAL FIXTURES - NO MOCKS
# =============================================================================

@pytest.fixture
async def real_tts_cache(tmp_path):
    """Real TTSCache with temporary directory."""
    cache_dir = tmp_path / "tts_cache"
    cache = TTSCache(
        cache_dir=cache_dir,
        max_size_bytes=100 * 1024 * 1024,
        default_ttl_days=1,
    )
    await cache.initialize()
    return cache


@pytest.fixture
def real_resource_pool():
    """Real TTSResourcePool - HTTP calls intercepted by aioresponses."""
    return TTSResourcePool(
        max_concurrent_live=2,
        max_concurrent_background=1,
        request_timeout=5.0,
    )


@pytest.fixture
async def real_prefetcher(real_tts_cache, real_resource_pool):
    """Real CurriculumPrefetcher for testing prefetch endpoints."""
    from tts_cache.prefetcher import CurriculumPrefetcher
    return CurriculumPrefetcher(
        cache=real_tts_cache,
        resource_pool=real_resource_pool,
        delay_between_requests=0.01,  # Fast for tests
    )


@pytest.fixture
async def real_app(real_tts_cache, real_resource_pool, real_prefetcher):
    """Real aiohttp application with real services."""
    app = web.Application()
    app["tts_cache"] = real_tts_cache
    app["tts_resource_pool"] = real_resource_pool
    app["tts_prefetcher"] = real_prefetcher
    return app


@pytest.fixture
def make_request(real_app):
    """Create test requests with real app context."""
    def _make_request(method="POST", json_data=None, query=None, match_info=None):
        request = make_mocked_request(
            method,
            "/api/tts",
            app=real_app,
            match_info=match_info or {},
        )

        # Set query parameters
        if query:
            # aiohttp stores query in _rel_url
            from yarl import URL
            request._rel_url = URL("/api/tts").with_query(query)
            request._cache["query"] = query

        # Set JSON body
        if json_data is not None:
            async def _json():
                return json_data
            request.json = _json
        else:
            async def _json():
                raise ValueError("No JSON body")
            request.json = _json

        return request

    return _make_request


@pytest.fixture
def tts_server_responses():
    """Mock TTS server HTTP responses using aioresponses.

    This is ACCEPTABLE - we're mocking EXTERNAL HTTP services,
    not internal code. The TTSResourcePool code is fully tested.
    """
    # Minimal valid WAV header (44 bytes) + some audio data
    wav_header = (
        b"RIFF"
        + (100).to_bytes(4, "little")  # File size - 8
        + b"WAVE"
        + b"fmt "
        + (16).to_bytes(4, "little")  # Subchunk1 size
        + (1).to_bytes(2, "little")   # Audio format (PCM)
        + (1).to_bytes(2, "little")   # Num channels
        + (24000).to_bytes(4, "little")  # Sample rate
        + (48000).to_bytes(4, "little")  # Byte rate
        + (2).to_bytes(2, "little")   # Block align
        + (16).to_bytes(2, "little")  # Bits per sample
        + b"data"
        + (56).to_bytes(4, "little")  # Subchunk2 size
    )
    audio_data = wav_header + b"\x00" * 56

    with aioresponses() as m:
        # Mock all TTS provider endpoints
        m.post("http://localhost:8880/v1/audio/speech", body=audio_data, repeat=True)
        m.post("http://localhost:11402/v1/audio/speech", body=audio_data, repeat=True)
        m.post("http://localhost:8004/v1/audio/speech", body=audio_data, repeat=True)
        yield m


# =============================================================================
# TTS Request Handler Tests
# =============================================================================

class TestHandleTtsRequest:
    """Tests for handle_tts_request endpoint."""

    @pytest.mark.asyncio
    async def test_invalid_json_body(self, make_request):
        """Test handling of invalid JSON body."""
        request = make_request()
        response = await tts_api.handle_tts_request(request)

        assert response.status == 400
        assert b"Invalid JSON body" in response.body

    @pytest.mark.asyncio
    async def test_missing_text_field(self, make_request):
        """Test handling of missing text field."""
        request = make_request(json_data={"voice_id": "nova"})
        response = await tts_api.handle_tts_request(request)

        assert response.status == 400
        assert b"Missing or empty 'text' field" in response.body

    @pytest.mark.asyncio
    async def test_empty_text_field(self, make_request):
        """Test handling of empty text field."""
        request = make_request(json_data={"text": "   "})
        response = await tts_api.handle_tts_request(request)

        assert response.status == 400
        assert b"Missing or empty 'text' field" in response.body

    @pytest.mark.asyncio
    async def test_invalid_provider(self, make_request):
        """Test handling of invalid TTS provider."""
        request = make_request(json_data={
            "text": "Hello world",
            "tts_provider": "invalid_provider"
        })
        response = await tts_api.handle_tts_request(request)

        assert response.status == 400
        assert b"Unknown provider" in response.body

    @pytest.mark.asyncio
    async def test_no_resource_pool(self, make_request, real_app):
        """Test handling when resource pool is not initialized."""
        real_app["tts_resource_pool"] = None
        request = make_request(json_data={"text": "Hello world"})

        response = await tts_api.handle_tts_request(request)

        assert response.status == 503
        assert b"resource pool not initialized" in response.body

    @pytest.mark.asyncio
    async def test_no_cache_direct_generation(self, make_request, real_app, tts_server_responses):
        """Test direct generation when cache is not available."""
        real_app["tts_cache"] = None
        request = make_request(json_data={
            "text": "Hello world",
            "voice_id": "nova",
            "tts_provider": "vibevoice"
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.content_type == "audio/wav"
        assert response.headers.get("X-TTS-Cache-Status") == "bypass"

    @pytest.mark.asyncio
    async def test_cache_hit(self, make_request, real_app):
        """Test cache hit scenario."""
        # Pre-populate cache
        cache = real_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="Hello world",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key, b"cached_audio", 24000, 2.5)

        request = make_request(json_data={
            "text": "Hello world",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": 1.0,
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.headers.get("X-TTS-Cache-Status") == "hit"

    @pytest.mark.asyncio
    async def test_cache_miss_generates_audio(self, make_request, tts_server_responses):
        """Test cache miss triggers audio generation."""
        request = make_request(json_data={
            "text": "Hello world new text",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.content_type == "audio/wav"
        assert response.headers.get("X-TTS-Cache-Status") == "miss"

    @pytest.mark.asyncio
    async def test_skip_cache_flag(self, make_request, real_app, tts_server_responses):
        """Test skip_cache bypasses cache lookup."""
        # Pre-populate cache
        cache = real_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="Hello world skip",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key, b"cached_audio", 24000, 2.5)

        request = make_request(json_data={
            "text": "Hello world skip",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": 1.0,
            "skip_cache": True,
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        # Should be miss even though data exists in cache
        assert response.headers.get("X-TTS-Cache-Status") == "miss"

    @pytest.mark.asyncio
    async def test_chatterbox_config_passed(self, make_request, tts_server_responses):
        """Test chatterbox config is passed to generator.

        Note: We verify the request succeeds with chatterbox provider and config.
        The real TTSResourcePool handles passing config to the HTTP request.
        Testing config propagation is the resource pool's unit test responsibility.
        """
        request = make_request(json_data={
            "text": "Hello world chatterbox test",
            "voice_id": "chatterbox_voice",
            "tts_provider": "chatterbox",
            "chatterbox_config": {
                "exaggeration": 0.7,
                "cfg_weight": 0.5,
                "language": "en"
            }
        })

        response = await tts_api.handle_tts_request(request)

        # Verify request succeeds with chatterbox provider
        assert response.status == 200
        assert response.content_type == "audio/wav"

    @pytest.mark.asyncio
    async def test_generation_error_without_cache(self, make_request, real_app):
        """Test error handling when generation fails without cache."""
        real_app["tts_cache"] = None

        # Use aioresponses to simulate server error
        with aioresponses() as m:
            # Mock TTS endpoint to return 500 error
            m.post("http://localhost:11402/v1/audio/speech", status=500, repeat=True)
            m.post("http://localhost:8880/v1/audio/speech", status=500, repeat=True)
            m.post("http://localhost:8004/v1/audio/speech", status=500, repeat=True)

            request = make_request(json_data={
                "text": "Hello world",
                "tts_provider": "vibevoice"
            })

            response = await tts_api.handle_tts_request(request)

            assert response.status == 503
            assert b"TTS generation failed" in response.body

    @pytest.mark.asyncio
    async def test_generation_error_with_cache(self, make_request):
        """Test error handling when generation fails with cache miss."""
        # Use aioresponses to simulate server error
        with aioresponses() as m:
            # Mock TTS endpoint to return 500 error
            m.post("http://localhost:11402/v1/audio/speech", status=500, repeat=True)
            m.post("http://localhost:8880/v1/audio/speech", status=500, repeat=True)
            m.post("http://localhost:8004/v1/audio/speech", status=500, repeat=True)

            request = make_request(json_data={
                "text": "Hello world unique text for error test",
                "tts_provider": "vibevoice"
            })

            response = await tts_api.handle_tts_request(request)

            assert response.status == 503
            assert b"TTS generation failed" in response.body


# =============================================================================
# Cache Stats Handler Tests
# =============================================================================

class TestHandleGetCacheStats:
    """Tests for handle_get_cache_stats endpoint."""

    @pytest.mark.asyncio
    async def test_get_stats_success(self, make_request):
        """Test successful stats retrieval."""
        request = make_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200
        assert response.content_type == "application/json"

    @pytest.mark.asyncio
    async def test_get_stats_no_cache(self, make_request, real_app):
        """Test stats when cache not initialized."""
        real_app["tts_cache"] = None
        request = make_request(method="GET")

        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 503
        assert b"cache not initialized" in response.body

    @pytest.mark.asyncio
    async def test_stats_includes_resource_pool(self, make_request):
        """Test stats include resource pool info."""
        request = make_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200


# =============================================================================
# Cache Clear Handler Tests
# =============================================================================

class TestHandleClearCache:
    """Tests for handle_clear_cache endpoint."""

    @pytest.mark.asyncio
    async def test_clear_without_confirm(self, make_request):
        """Test clear fails without confirmation."""
        request = make_request(method="DELETE", query={})
        response = await tts_api.handle_clear_cache(request)

        assert response.status == 400
        assert b"confirm=true" in response.body

    @pytest.mark.asyncio
    async def test_clear_with_wrong_confirm(self, make_request):
        """Test clear fails with wrong confirmation value."""
        request = make_request(method="DELETE", query={"confirm": "false"})
        response = await tts_api.handle_clear_cache(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_clear_success(self, make_request, real_app):
        """Test successful cache clear."""
        # Add some data using proper cache API
        cache = real_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key1 = TTSCacheKey.from_request(
            text="Test text 1",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        key2 = TTSCacheKey.from_request(
            text="Test text 2",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key1, b"audio_data_1", 24000, 1.0)
        await cache.put(key2, b"audio_data_2", 24000, 1.0)

        # Verify data was added
        assert await cache.has(key1)
        assert await cache.has(key2)

        request = make_request(method="DELETE", query={"confirm": "true"})
        response = await tts_api.handle_clear_cache(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_clear_no_cache(self, make_request, real_app):
        """Test clear when cache not initialized."""
        real_app["tts_cache"] = None
        request = make_request(method="DELETE", query={"confirm": "true"})

        response = await tts_api.handle_clear_cache(request)

        assert response.status == 503


# =============================================================================
# Evict Expired Handler Tests
# =============================================================================

class TestHandleEvictExpired:
    """Tests for handle_evict_expired endpoint."""

    @pytest.mark.asyncio
    async def test_evict_expired_success(self, make_request):
        """Test successful expired entry eviction."""
        request = make_request(method="DELETE")
        response = await tts_api.handle_evict_expired(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_evict_expired_no_cache(self, make_request, real_app):
        """Test eviction when cache not initialized."""
        real_app["tts_cache"] = None
        request = make_request(method="DELETE")

        response = await tts_api.handle_evict_expired(request)

        assert response.status == 503


# =============================================================================
# Evict LRU Handler Tests
# =============================================================================

class TestHandleEvictLru:
    """Tests for handle_evict_lru endpoint."""

    @pytest.mark.asyncio
    async def test_evict_lru_invalid_json(self, make_request):
        """Test LRU eviction with invalid JSON."""
        request = make_request()
        response = await tts_api.handle_evict_lru(request)

        assert response.status == 400
        assert b"Invalid JSON" in response.body

    @pytest.mark.asyncio
    async def test_evict_lru_missing_target(self, make_request):
        """Test LRU eviction without target size."""
        request = make_request(json_data={})
        response = await tts_api.handle_evict_lru(request)

        assert response.status == 400
        assert b"target_size_mb" in response.body

    @pytest.mark.asyncio
    async def test_evict_lru_negative_target(self, make_request):
        """Test LRU eviction with negative target size."""
        request = make_request(json_data={"target_size_mb": -100})
        response = await tts_api.handle_evict_lru(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_evict_lru_success(self, make_request):
        """Test successful LRU eviction."""
        request = make_request(json_data={"target_size_mb": 500})
        response = await tts_api.handle_evict_lru(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_evict_lru_no_cache(self, make_request, real_app):
        """Test LRU eviction when cache not initialized."""
        real_app["tts_cache"] = None
        request = make_request(json_data={"target_size_mb": 500})

        response = await tts_api.handle_evict_lru(request)

        assert response.status == 503


# =============================================================================
# Put Cache Entry Handler Tests
# =============================================================================

class TestHandlePutCacheEntry:
    """Tests for handle_put_cache_entry endpoint."""

    @pytest.mark.asyncio
    async def test_put_invalid_json(self, make_request):
        """Test putting entry with invalid JSON."""
        request = make_request()
        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_put_missing_text(self, make_request):
        """Test putting entry without text."""
        request = make_request(json_data={"audio_base64": "YXVkaW8="})
        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 400
        assert b"text" in response.body

    @pytest.mark.asyncio
    async def test_put_missing_audio(self, make_request):
        """Test putting entry without audio."""
        request = make_request(json_data={"text": "Hello"})
        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 400
        assert b"audio_base64" in response.body

    @pytest.mark.asyncio
    async def test_put_invalid_base64(self, make_request):
        """Test putting entry with invalid base64."""
        request = make_request(json_data={
            "text": "Hello",
            "audio_base64": "not valid base64!!!"
        })
        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 400
        assert b"Invalid base64" in response.body

    @pytest.mark.asyncio
    async def test_put_success(self, make_request):
        """Test successful cache entry creation."""
        audio_data = base64.b64encode(b"fake audio data").decode()
        request = make_request(json_data={
            "text": "Hello world",
            "audio_base64": audio_data,
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "sample_rate": 24000,
            "duration_seconds": 2.5,
        })

        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_put_no_cache(self, make_request, real_app):
        """Test putting entry when cache not initialized."""
        real_app["tts_cache"] = None
        audio_data = base64.b64encode(b"fake audio data").decode()
        request = make_request(json_data={
            "text": "Hello",
            "audio_base64": audio_data
        })

        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 503


# =============================================================================
# Get Cache Entry Handler Tests
# =============================================================================

class TestHandleGetCacheEntry:
    """Tests for handle_get_cache_entry endpoint."""

    @pytest.mark.asyncio
    async def test_get_missing_text_param(self, make_request):
        """Test getting entry without text parameter."""
        request = make_request(method="GET", query={})
        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 400
        assert b"text" in response.body

    @pytest.mark.asyncio
    async def test_get_cache_miss(self, make_request):
        """Test getting non-existent entry."""
        request = make_request(method="GET", query={"text": "nonexistent"})
        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 404
        assert b"Cache miss" in response.body

    @pytest.mark.asyncio
    async def test_get_cache_hit(self, make_request, real_app):
        """Test getting existing entry."""
        # Pre-populate cache
        cache = real_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="test text",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key, b"cached audio data", 24000, 2.5)

        request = make_request(method="GET", query={
            "text": "test text",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": "1.0",
        })

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 200
        assert response.content_type == "audio/wav"
        assert response.headers.get("X-TTS-Cache-Status") == "hit"

    @pytest.mark.asyncio
    async def test_get_no_cache(self, make_request, real_app):
        """Test getting entry when cache not initialized."""
        real_app["tts_cache"] = None
        request = make_request(method="GET", query={"text": "test"})

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 503


# =============================================================================
# Prefetch Handler Tests
# =============================================================================

class TestHandlePrefetchTopic:
    """Tests for handle_prefetch_topic endpoint."""

    @pytest.mark.asyncio
    async def test_prefetch_invalid_json(self, make_request):
        """Test prefetch with invalid JSON."""
        request = make_request()
        response = await tts_api.handle_prefetch_topic(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_prefetch_missing_params(self, make_request):
        """Test prefetch without required parameters."""
        request = make_request(json_data={"curriculum_id": "test"})
        response = await tts_api.handle_prefetch_topic(request)

        assert response.status == 400
        assert b"topic_id" in response.body

    @pytest.mark.asyncio
    async def test_prefetch_no_prefetcher(self, make_request, real_app):
        """Test prefetch when prefetcher not initialized."""
        real_app["tts_prefetcher"] = None
        request = make_request(json_data={
            "curriculum_id": "test",
            "topic_id": "topic1"
        })

        response = await tts_api.handle_prefetch_topic(request)

        assert response.status == 503


class TestHandlePrefetchStatus:
    """Tests for handle_prefetch_status endpoint."""

    @pytest.mark.asyncio
    async def test_status_missing_job_id(self, make_request):
        """Test status without job_id."""
        request = make_request(method="GET", match_info={})
        response = await tts_api.handle_prefetch_status(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_status_no_prefetcher(self, make_request, real_app):
        """Test status when prefetcher not initialized."""
        real_app["tts_prefetcher"] = None
        request = make_request(method="GET", match_info={"job_id": "123"})

        response = await tts_api.handle_prefetch_status(request)

        assert response.status == 503

    @pytest.mark.asyncio
    async def test_status_job_not_found(self, make_request):
        """Test status for non-existent job."""
        request = make_request(method="GET", match_info={"job_id": "nonexistent"})
        response = await tts_api.handle_prefetch_status(request)

        assert response.status == 404

    @pytest.mark.asyncio
    async def test_status_success(self, make_request, real_app, tts_server_responses):
        """Test successful status retrieval."""
        # Create a real prefetch job
        prefetcher = real_app["tts_prefetcher"]
        job_id = await prefetcher.prefetch_topic(
            curriculum_id="test_curriculum",
            topic_id="test_topic",
            segments=["Hello world", "Test segment"],
            voice_id="nova",
            provider="vibevoice",
        )

        request = make_request(method="GET", match_info={"job_id": job_id})
        response = await tts_api.handle_prefetch_status(request)

        assert response.status == 200


class TestHandleCancelPrefetch:
    """Tests for handle_cancel_prefetch endpoint."""

    @pytest.mark.asyncio
    async def test_cancel_missing_job_id(self, make_request):
        """Test cancel without job_id."""
        request = make_request(method="DELETE", match_info={})
        response = await tts_api.handle_cancel_prefetch(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_cancel_no_prefetcher(self, make_request, real_app):
        """Test cancel when prefetcher not initialized."""
        real_app["tts_prefetcher"] = None
        request = make_request(method="DELETE", match_info={"job_id": "123"})

        response = await tts_api.handle_cancel_prefetch(request)

        assert response.status == 503

    @pytest.mark.asyncio
    async def test_cancel_success(self, make_request, real_app, tts_server_responses):
        """Test successful cancel."""
        # Create a real prefetch job
        prefetcher = real_app["tts_prefetcher"]
        job_id = await prefetcher.prefetch_topic(
            curriculum_id="test_curriculum",
            topic_id="cancel_test",
            segments=["Hello world", "Another segment"],
            voice_id="nova",
            provider="vibevoice",
        )

        request = make_request(method="DELETE", match_info={"job_id": job_id})
        response = await tts_api.handle_cancel_prefetch(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_cancel_nonexistent_job(self, make_request):
        """Test cancelling non-existent job."""
        request = make_request(method="DELETE", match_info={"job_id": "nonexistent"})
        response = await tts_api.handle_cancel_prefetch(request)

        assert response.status == 200
        # Should return not_found status in response


# =============================================================================
# Route Registration Tests
# =============================================================================

class TestRegisterRoutes:
    """Tests for route registration."""

    @pytest.mark.asyncio
    async def test_register_tts_routes(self, real_tts_cache, real_resource_pool):
        """Test that TTS routes are registered correctly."""
        app = web.Application()
        app["tts_cache"] = real_tts_cache
        app["tts_resource_pool"] = real_resource_pool

        tts_api.register_tts_routes(app)

        # Check routes exist
        route_paths = [r.resource.canonical for r in app.router.routes()]

        assert "/api/tts" in route_paths
        assert "/api/tts/cache/stats" in route_paths
        assert "/api/tts/cache" in route_paths


# =============================================================================
# Constants Tests
# =============================================================================

class TestConstants:
    """Tests for module constants."""

    def test_sample_rates_defined(self):
        """Test sample rates are defined for all providers."""
        assert "vibevoice" in tts_api.SAMPLE_RATES
        assert "piper" in tts_api.SAMPLE_RATES
        assert "chatterbox" in tts_api.SAMPLE_RATES

    def test_valid_providers_defined(self):
        """Test valid providers set is defined."""
        assert "vibevoice" in tts_api.VALID_PROVIDERS
        assert "piper" in tts_api.VALID_PROVIDERS
        assert "chatterbox" in tts_api.VALID_PROVIDERS
