"""
Tests for TTS API routes.
"""
import base64
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from aiohttp import web


class MockAsyncLock:
    """Mock async lock for testing."""
    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass


class MockTTSCacheEntry:
    """Mock TTS cache entry."""
    def __init__(self, sample_rate=24000, duration_seconds=2.5):
        self.sample_rate = sample_rate
        self.duration_seconds = duration_seconds


class MockTTSCacheStats:
    """Mock TTS cache stats."""
    def __init__(self):
        self.total_entries = 10
        self.total_size_bytes = 1024 * 1024
        self.hit_count = 100
        self.miss_count = 20

    def to_dict(self):
        return {
            "total_entries": self.total_entries,
            "total_size_bytes": self.total_size_bytes,
            "hit_count": self.hit_count,
            "miss_count": self.miss_count,
        }


class MockTTSCache:
    """Mock TTS cache for testing."""
    def __init__(self):
        self._data = {}
        self.index = {}
        self._lock = MockAsyncLock()

    async def get(self, key):
        hash_key = key.to_hash()
        return self._data.get(hash_key)

    async def put(self, key, audio_data, sample_rate, duration):
        hash_key = key.to_hash()
        self._data[hash_key] = audio_data
        self.index[hash_key] = MockTTSCacheEntry(sample_rate, duration)

    async def get_stats(self):
        return MockTTSCacheStats()

    async def clear(self):
        count = len(self._data)
        self._data.clear()
        self.index.clear()
        return count

    async def evict_expired(self):
        return 5

    async def evict_lru(self, target_bytes):
        return 3


class MockResourcePool:
    """Mock TTS resource pool."""
    def __init__(self):
        self.audio_data = b"RIFF" + b"\x00" * 100  # Fake WAV data
        self.sample_rate = 24000
        self.duration = 2.5

    async def generate_with_priority(self, **kwargs):
        return self.audio_data, self.sample_rate, self.duration

    def get_stats(self):
        return {
            "active_requests": 2,
            "pending_live": 1,
            "pending_prefetch": 3,
            "total_generated": 100,
        }


class MockPrefetcher:
    """Mock TTS prefetcher."""
    def __init__(self):
        self._jobs = {}

    async def prefetch_topic(self, **kwargs):
        job_id = "job_123"
        self._jobs[job_id] = {
            "status": "running",
            "completed": 5,
            "total": 10,
        }
        return job_id

    def get_progress(self, job_id):
        return self._jobs.get(job_id)

    async def cancel(self, job_id):
        if job_id in self._jobs:
            del self._jobs[job_id]
            return True
        return False


# Import the module under test
import tts_api


@pytest.fixture
def mock_app():
    """Create a mock aiohttp application."""
    app = web.Application()
    app["tts_cache"] = MockTTSCache()
    app["tts_resource_pool"] = MockResourcePool()
    app["tts_prefetcher"] = MockPrefetcher()
    return app


@pytest.fixture
def mock_request(mock_app):
    """Create a factory for mock requests."""
    def _make_request(method="POST", json_data=None, query=None, match_info=None):
        request = MagicMock(spec=web.Request)
        request.app = mock_app
        request.method = method
        request.query = query or {}
        request.match_info = match_info or {}

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
# TTS Request Handler Tests
# =============================================================================

class TestHandleTtsRequest:
    """Tests for handle_tts_request endpoint."""

    @pytest.mark.asyncio
    async def test_invalid_json_body(self, mock_request):
        """Test handling of invalid JSON body."""
        request = mock_request()
        response = await tts_api.handle_tts_request(request)

        assert response.status == 400
        assert b"Invalid JSON body" in response.body

    @pytest.mark.asyncio
    async def test_missing_text_field(self, mock_request):
        """Test handling of missing text field."""
        request = mock_request(json_data={"voice_id": "nova"})
        response = await tts_api.handle_tts_request(request)

        assert response.status == 400
        assert b"Missing or empty 'text' field" in response.body

    @pytest.mark.asyncio
    async def test_empty_text_field(self, mock_request):
        """Test handling of empty text field."""
        request = mock_request(json_data={"text": "   "})
        response = await tts_api.handle_tts_request(request)

        assert response.status == 400
        assert b"Missing or empty 'text' field" in response.body

    @pytest.mark.asyncio
    async def test_invalid_provider(self, mock_request):
        """Test handling of invalid TTS provider."""
        request = mock_request(json_data={
            "text": "Hello world",
            "tts_provider": "invalid_provider"
        })
        response = await tts_api.handle_tts_request(request)

        assert response.status == 400
        assert b"Unknown provider" in response.body

    @pytest.mark.asyncio
    async def test_no_resource_pool(self, mock_request, mock_app):
        """Test handling when resource pool is not initialized."""
        mock_app["tts_resource_pool"] = None
        request = mock_request(json_data={"text": "Hello world"})

        response = await tts_api.handle_tts_request(request)

        assert response.status == 503
        assert b"resource pool not initialized" in response.body

    @pytest.mark.asyncio
    async def test_no_cache_direct_generation(self, mock_request, mock_app):
        """Test direct generation when cache is not available."""
        mock_app["tts_cache"] = None
        request = mock_request(json_data={
            "text": "Hello world",
            "voice_id": "nova",
            "tts_provider": "vibevoice"
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.content_type == "audio/wav"
        assert response.headers.get("X-TTS-Cache-Status") == "bypass"

    @pytest.mark.asyncio
    async def test_cache_hit(self, mock_request, mock_app):
        """Test cache hit scenario."""
        # Pre-populate cache
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="Hello world",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key, b"cached_audio", 24000, 2.5)

        request = mock_request(json_data={
            "text": "Hello world",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": 1.0,
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.headers.get("X-TTS-Cache-Status") == "hit"

    @pytest.mark.asyncio
    async def test_cache_miss_generates_audio(self, mock_request):
        """Test cache miss triggers audio generation."""
        request = mock_request(json_data={
            "text": "Hello world new text",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.content_type == "audio/wav"
        assert response.headers.get("X-TTS-Cache-Status") == "miss"

    @pytest.mark.asyncio
    async def test_skip_cache_flag(self, mock_request, mock_app):
        """Test skip_cache bypasses cache lookup."""
        # Pre-populate cache
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="Hello world skip",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key, b"cached_audio", 24000, 2.5)

        request = mock_request(json_data={
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
    async def test_chatterbox_config_passed(self, mock_request, mock_app):
        """Test chatterbox config is passed to generator."""
        pool = mock_app["tts_resource_pool"]
        pool.generate_with_priority = AsyncMock(return_value=(b"audio", 24000, 2.5))

        request = mock_request(json_data={
            "text": "Hello world",
            "voice_id": "chatterbox_voice",
            "tts_provider": "chatterbox",
            "chatterbox_config": {
                "exaggeration": 0.7,
                "cfg_weight": 0.5,
                "language": "en"
            }
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        # Verify chatterbox_config was passed
        call_kwargs = pool.generate_with_priority.call_args.kwargs
        assert call_kwargs["chatterbox_config"]["exaggeration"] == 0.7

    @pytest.mark.asyncio
    async def test_generation_error_without_cache(self, mock_request, mock_app):
        """Test error handling when generation fails without cache."""
        mock_app["tts_cache"] = None
        pool = mock_app["tts_resource_pool"]
        pool.generate_with_priority = AsyncMock(side_effect=Exception("Generation failed"))

        request = mock_request(json_data={
            "text": "Hello world",
            "tts_provider": "vibevoice"
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 503
        assert b"Generation failed" in response.body

    @pytest.mark.asyncio
    async def test_generation_error_with_cache(self, mock_request, mock_app):
        """Test error handling when generation fails with cache miss."""
        pool = mock_app["tts_resource_pool"]
        pool.generate_with_priority = AsyncMock(side_effect=Exception("Generation error"))

        request = mock_request(json_data={
            "text": "Hello world unique text",
            "tts_provider": "vibevoice"
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 503
        assert b"Generation error" in response.body


# =============================================================================
# Cache Stats Handler Tests
# =============================================================================

class TestHandleGetCacheStats:
    """Tests for handle_get_cache_stats endpoint."""

    @pytest.mark.asyncio
    async def test_get_stats_success(self, mock_request):
        """Test successful stats retrieval."""
        request = mock_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200
        assert response.content_type == "application/json"

    @pytest.mark.asyncio
    async def test_get_stats_no_cache(self, mock_request, mock_app):
        """Test stats when cache not initialized."""
        mock_app["tts_cache"] = None
        request = mock_request(method="GET")

        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 503
        assert b"cache not initialized" in response.body

    @pytest.mark.asyncio
    async def test_stats_includes_resource_pool(self, mock_request):
        """Test stats include resource pool info."""
        request = mock_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200


# =============================================================================
# Cache Clear Handler Tests
# =============================================================================

class TestHandleClearCache:
    """Tests for handle_clear_cache endpoint."""

    @pytest.mark.asyncio
    async def test_clear_without_confirm(self, mock_request):
        """Test clear fails without confirmation."""
        request = mock_request(method="DELETE", query={})
        response = await tts_api.handle_clear_cache(request)

        assert response.status == 400
        assert b"confirm=true" in response.body

    @pytest.mark.asyncio
    async def test_clear_with_wrong_confirm(self, mock_request):
        """Test clear fails with wrong confirmation value."""
        request = mock_request(method="DELETE", query={"confirm": "false"})
        response = await tts_api.handle_clear_cache(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_clear_success(self, mock_request, mock_app):
        """Test successful cache clear."""
        # Add some data first
        cache = mock_app["tts_cache"]
        cache._data["key1"] = b"data1"
        cache._data["key2"] = b"data2"

        request = mock_request(method="DELETE", query={"confirm": "true"})
        response = await tts_api.handle_clear_cache(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_clear_no_cache(self, mock_request, mock_app):
        """Test clear when cache not initialized."""
        mock_app["tts_cache"] = None
        request = mock_request(method="DELETE", query={"confirm": "true"})

        response = await tts_api.handle_clear_cache(request)

        assert response.status == 503


# =============================================================================
# Evict Expired Handler Tests
# =============================================================================

class TestHandleEvictExpired:
    """Tests for handle_evict_expired endpoint."""

    @pytest.mark.asyncio
    async def test_evict_expired_success(self, mock_request):
        """Test successful expired entry eviction."""
        request = mock_request(method="DELETE")
        response = await tts_api.handle_evict_expired(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_evict_expired_no_cache(self, mock_request, mock_app):
        """Test eviction when cache not initialized."""
        mock_app["tts_cache"] = None
        request = mock_request(method="DELETE")

        response = await tts_api.handle_evict_expired(request)

        assert response.status == 503


# =============================================================================
# Evict LRU Handler Tests
# =============================================================================

class TestHandleEvictLru:
    """Tests for handle_evict_lru endpoint."""

    @pytest.mark.asyncio
    async def test_evict_lru_invalid_json(self, mock_request):
        """Test LRU eviction with invalid JSON."""
        request = mock_request()
        response = await tts_api.handle_evict_lru(request)

        assert response.status == 400
        assert b"Invalid JSON" in response.body

    @pytest.mark.asyncio
    async def test_evict_lru_missing_target(self, mock_request):
        """Test LRU eviction without target size."""
        request = mock_request(json_data={})
        response = await tts_api.handle_evict_lru(request)

        assert response.status == 400
        assert b"target_size_mb" in response.body

    @pytest.mark.asyncio
    async def test_evict_lru_negative_target(self, mock_request):
        """Test LRU eviction with negative target size."""
        request = mock_request(json_data={"target_size_mb": -100})
        response = await tts_api.handle_evict_lru(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_evict_lru_success(self, mock_request):
        """Test successful LRU eviction."""
        request = mock_request(json_data={"target_size_mb": 500})
        response = await tts_api.handle_evict_lru(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_evict_lru_no_cache(self, mock_request, mock_app):
        """Test LRU eviction when cache not initialized."""
        mock_app["tts_cache"] = None
        request = mock_request(json_data={"target_size_mb": 500})

        response = await tts_api.handle_evict_lru(request)

        assert response.status == 503


# =============================================================================
# Put Cache Entry Handler Tests
# =============================================================================

class TestHandlePutCacheEntry:
    """Tests for handle_put_cache_entry endpoint."""

    @pytest.mark.asyncio
    async def test_put_invalid_json(self, mock_request):
        """Test putting entry with invalid JSON."""
        request = mock_request()
        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_put_missing_text(self, mock_request):
        """Test putting entry without text."""
        request = mock_request(json_data={"audio_base64": "YXVkaW8="})
        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 400
        assert b"text" in response.body

    @pytest.mark.asyncio
    async def test_put_missing_audio(self, mock_request):
        """Test putting entry without audio."""
        request = mock_request(json_data={"text": "Hello"})
        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 400
        assert b"audio_base64" in response.body

    @pytest.mark.asyncio
    async def test_put_invalid_base64(self, mock_request):
        """Test putting entry with invalid base64."""
        request = mock_request(json_data={
            "text": "Hello",
            "audio_base64": "not valid base64!!!"
        })
        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 400
        assert b"Invalid base64" in response.body

    @pytest.mark.asyncio
    async def test_put_success(self, mock_request):
        """Test successful cache entry creation."""
        audio_data = base64.b64encode(b"fake audio data").decode()
        request = mock_request(json_data={
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
    async def test_put_no_cache(self, mock_request, mock_app):
        """Test putting entry when cache not initialized."""
        mock_app["tts_cache"] = None
        audio_data = base64.b64encode(b"fake audio data").decode()
        request = mock_request(json_data={
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
    async def test_get_missing_text_param(self, mock_request):
        """Test getting entry without text parameter."""
        request = mock_request(method="GET", query={})
        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 400
        assert b"text" in response.body

    @pytest.mark.asyncio
    async def test_get_cache_miss(self, mock_request):
        """Test getting non-existent entry."""
        request = mock_request(method="GET", query={"text": "nonexistent"})
        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 404
        assert b"Cache miss" in response.body

    @pytest.mark.asyncio
    async def test_get_cache_hit(self, mock_request, mock_app):
        """Test getting existing entry."""
        # Pre-populate cache
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="test text",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key, b"cached audio data", 24000, 2.5)

        request = mock_request(method="GET", query={
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
    async def test_get_no_cache(self, mock_request, mock_app):
        """Test getting entry when cache not initialized."""
        mock_app["tts_cache"] = None
        request = mock_request(method="GET", query={"text": "test"})

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 503


# =============================================================================
# Prefetch Handler Tests
# =============================================================================

class TestHandlePrefetchTopic:
    """Tests for handle_prefetch_topic endpoint."""

    @pytest.mark.asyncio
    async def test_prefetch_invalid_json(self, mock_request):
        """Test prefetch with invalid JSON."""
        request = mock_request()
        response = await tts_api.handle_prefetch_topic(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_prefetch_missing_params(self, mock_request):
        """Test prefetch without required parameters."""
        request = mock_request(json_data={"curriculum_id": "test"})
        response = await tts_api.handle_prefetch_topic(request)

        assert response.status == 400
        assert b"topic_id" in response.body

    @pytest.mark.asyncio
    async def test_prefetch_no_prefetcher(self, mock_request, mock_app):
        """Test prefetch when prefetcher not initialized."""
        mock_app["tts_prefetcher"] = None
        request = mock_request(json_data={
            "curriculum_id": "test",
            "topic_id": "topic1"
        })

        response = await tts_api.handle_prefetch_topic(request)

        assert response.status == 503


class TestHandlePrefetchStatus:
    """Tests for handle_prefetch_status endpoint."""

    @pytest.mark.asyncio
    async def test_status_missing_job_id(self, mock_request):
        """Test status without job_id."""
        request = mock_request(method="GET", match_info={})
        response = await tts_api.handle_prefetch_status(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_status_no_prefetcher(self, mock_request, mock_app):
        """Test status when prefetcher not initialized."""
        mock_app["tts_prefetcher"] = None
        request = mock_request(method="GET", match_info={"job_id": "123"})

        response = await tts_api.handle_prefetch_status(request)

        assert response.status == 503

    @pytest.mark.asyncio
    async def test_status_job_not_found(self, mock_request):
        """Test status for non-existent job."""
        request = mock_request(method="GET", match_info={"job_id": "nonexistent"})
        response = await tts_api.handle_prefetch_status(request)

        assert response.status == 404

    @pytest.mark.asyncio
    async def test_status_success(self, mock_request, mock_app):
        """Test successful status retrieval."""
        # Create a job first
        prefetcher = mock_app["tts_prefetcher"]
        prefetcher._jobs["existing_job"] = {
            "status": "running",
            "completed": 5,
            "total": 10,
        }

        request = mock_request(method="GET", match_info={"job_id": "existing_job"})
        response = await tts_api.handle_prefetch_status(request)

        assert response.status == 200


class TestHandleCancelPrefetch:
    """Tests for handle_cancel_prefetch endpoint."""

    @pytest.mark.asyncio
    async def test_cancel_missing_job_id(self, mock_request):
        """Test cancel without job_id."""
        request = mock_request(method="DELETE", match_info={})
        response = await tts_api.handle_cancel_prefetch(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_cancel_no_prefetcher(self, mock_request, mock_app):
        """Test cancel when prefetcher not initialized."""
        mock_app["tts_prefetcher"] = None
        request = mock_request(method="DELETE", match_info={"job_id": "123"})

        response = await tts_api.handle_cancel_prefetch(request)

        assert response.status == 503

    @pytest.mark.asyncio
    async def test_cancel_success(self, mock_request, mock_app):
        """Test successful cancel."""
        prefetcher = mock_app["tts_prefetcher"]
        prefetcher._jobs["job_to_cancel"] = {"status": "running"}

        request = mock_request(method="DELETE", match_info={"job_id": "job_to_cancel"})
        response = await tts_api.handle_cancel_prefetch(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_cancel_nonexistent_job(self, mock_request):
        """Test cancelling non-existent job."""
        request = mock_request(method="DELETE", match_info={"job_id": "nonexistent"})
        response = await tts_api.handle_cancel_prefetch(request)

        assert response.status == 200
        # Should return not_found status in response


# =============================================================================
# Route Registration Tests
# =============================================================================

class TestRegisterRoutes:
    """Tests for route registration."""

    def test_register_tts_routes(self):
        """Test that TTS routes are registered correctly."""
        app = web.Application()
        app["tts_cache"] = MockTTSCache()
        app["tts_resource_pool"] = MockResourcePool()

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
