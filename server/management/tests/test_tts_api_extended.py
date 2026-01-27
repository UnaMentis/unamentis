"""
Extended tests for TTS API routes.

TESTING PHILOSOPHY: Real Over Mock
==================================
- Uses REAL TTSCache with tmp_path (no MockTTSCache)
- Uses REAL TTSResourcePool with aioresponses for HTTP interception
- Uses REAL CurriculumPrefetcher
- NO MOCK CLASSES ALLOWED

These tests cover additional edge cases and functionality not covered
by test_tts_api.py, specifically targeting:
- Lines 217-220: Resource pool stats in cache stats response
- Lines 426-428: Float conversion of exaggeration/cfg_weight in get cache entry
- Lines 517-556: Prefetch topic with curriculum parsing and segment extraction
"""
import base64
import pytest
from unittest.mock import patch  # Only for external services
from aiohttp import web
from aiohttp.test_utils import make_mocked_request
from aioresponses import aioresponses
from yarl import URL

# Import real implementations - NO MOCKS
from tts_cache.cache import TTSCache
from tts_cache.resource_pool import TTSResourcePool
from tts_cache.prefetcher import CurriculumPrefetcher

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


# Backward compatibility aliases
mock_app = real_app
mock_request = make_request


# =============================================================================
# Tests for Lines 217-220: Resource Pool Stats in Cache Stats Response
# =============================================================================

class TestCacheStatsWithResourcePool:
    """Tests for resource pool statistics in cache stats endpoint."""

    @pytest.mark.asyncio
    async def test_stats_with_resource_pool_present(self, make_request):
        """Test that resource pool stats are included when pool is available."""
        request = make_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200
        import json
        body = json.loads(response.body.decode())
        # Real TTSResourcePool returns different stats structure
        assert "resource_pool" in body
        # Check that stats exist (real pool has these keys)
        assert "live_in_flight" in body["resource_pool"]
        assert "background_in_flight" in body["resource_pool"]

    @pytest.mark.asyncio
    async def test_stats_without_resource_pool(self, make_request, real_app):
        """Test stats response when resource pool is None."""
        real_app["tts_resource_pool"] = None
        request = make_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200
        import json
        body = json.loads(response.body.decode())
        # Should not include resource_pool key when pool is None
        assert "resource_pool" not in body
        assert "cache" in body

    @pytest.mark.asyncio
    async def test_stats_returns_cache_metrics(self, make_request, real_app):
        """Test stats include cache metrics."""
        # Add some data to cache to have non-zero stats
        cache = real_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="stats test",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key, b"test audio", 24000, 2.5)

        request = make_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200
        import json
        body = json.loads(response.body.decode())
        assert "cache" in body
        # Real cache has these keys
        assert "total_entries" in body["cache"]
        assert "total_size_bytes" in body["cache"]


# =============================================================================
# Tests for Lines 426-428: Float Conversion in Get Cache Entry
# =============================================================================

class TestGetCacheEntryFloatConversion:
    """Tests for float parameter conversion in get cache entry endpoint."""

    @pytest.mark.asyncio
    async def test_exaggeration_float_conversion(self, mock_request, mock_app):
        """Test that exaggeration string is converted to float."""
        # Pre-populate cache with chatterbox entry
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="test chatterbox",
            voice_id="chatterbox_voice",
            provider="chatterbox",
            speed=1.0,
            exaggeration=0.75,
            cfg_weight=None,
            language=None,
        )
        await cache.put(key, b"chatterbox audio", 24000, 3.0)

        # Request with exaggeration as string (from query param)
        request = mock_request(method="GET", query={
            "text": "test chatterbox",
            "voice_id": "chatterbox_voice",
            "tts_provider": "chatterbox",
            "speed": "1.0",
            "exaggeration": "0.75",
        })

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 200
        assert response.content_type == "audio/wav"

    @pytest.mark.asyncio
    async def test_cfg_weight_float_conversion(self, mock_request, mock_app):
        """Test that cfg_weight string is converted to float."""
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="test cfg weight",
            voice_id="chatterbox_voice",
            provider="chatterbox",
            speed=1.0,
            exaggeration=None,
            cfg_weight=0.6,
            language=None,
        )
        await cache.put(key, b"cfg audio", 24000, 2.0)

        request = mock_request(method="GET", query={
            "text": "test cfg weight",
            "voice_id": "chatterbox_voice",
            "tts_provider": "chatterbox",
            "speed": "1.0",
            "cfg_weight": "0.6",
        })

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 200
        assert response.content_type == "audio/wav"

    @pytest.mark.asyncio
    async def test_both_exaggeration_and_cfg_weight_conversion(self, mock_request, mock_app):
        """Test both parameters converted to float together."""
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="test both params",
            voice_id="chatterbox_voice",
            provider="chatterbox",
            speed=1.0,
            exaggeration=0.8,
            cfg_weight=0.4,
            language=None,
        )
        await cache.put(key, b"both params audio", 24000, 2.5)

        request = mock_request(method="GET", query={
            "text": "test both params",
            "voice_id": "chatterbox_voice",
            "tts_provider": "chatterbox",
            "speed": "1.0",
            "exaggeration": "0.8",
            "cfg_weight": "0.4",
        })

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_none_exaggeration_no_conversion(self, mock_request, mock_app):
        """Test that None exaggeration skips conversion."""
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="test no exag",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        await cache.put(key, b"no exag audio", 24000, 2.0)

        # No exaggeration or cfg_weight in query
        request = mock_request(method="GET", query={
            "text": "test no exag",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": "1.0",
        })

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_language_parameter_passed(self, mock_request, mock_app):
        """Test that language parameter is passed correctly."""
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="test language",
            voice_id="chatterbox_voice",
            provider="chatterbox",
            speed=1.0,
            exaggeration=0.5,
            cfg_weight=0.5,
            language="es",
        )
        await cache.put(key, b"spanish audio", 24000, 2.0)

        request = mock_request(method="GET", query={
            "text": "test language",
            "voice_id": "chatterbox_voice",
            "tts_provider": "chatterbox",
            "speed": "1.0",
            "exaggeration": "0.5",
            "cfg_weight": "0.5",
            "language": "es",
        })

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 200


# =============================================================================
# Tests for Lines 517-556: Prefetch Topic with Curriculum Parsing
# =============================================================================

class TestPrefetchTopicCurriculum:
    """Tests for prefetch topic with curriculum parsing and segment extraction."""

    @pytest.mark.asyncio
    async def test_prefetch_curriculum_not_found(self, mock_request, mock_app):
        """Test prefetch when curriculum is not found."""
        with patch("server.state") as mock_state:
            mock_state.curriculum_raw = {}  # Empty curriculum store

            request = mock_request(json_data={
                "curriculum_id": "nonexistent-curriculum",
                "topic_id": "topic1",
                "voice_id": "nova",
                "tts_provider": "vibevoice",
            })

            response = await tts_api.handle_prefetch_topic(request)

            assert response.status == 404
            assert b"Curriculum not found" in response.body

    @pytest.mark.asyncio
    async def test_prefetch_topic_not_found(self, mock_request, mock_app):
        """Test prefetch when topic is not found in curriculum."""
        with patch("server.state") as mock_state:
            mock_state.curriculum_raw = {
                "test-curriculum": {
                    "content": [{
                        "children": [
                            {"id": "other-topic", "transcript": {"segments": []}}
                        ]
                    }]
                }
            }

            request = mock_request(json_data={
                "curriculum_id": "test-curriculum",
                "topic_id": "missing-topic",
                "voice_id": "nova",
                "tts_provider": "vibevoice",
            })

            response = await tts_api.handle_prefetch_topic(request)

            assert response.status == 404
            assert b"Topic not found" in response.body

    @pytest.mark.asyncio
    async def test_prefetch_topic_no_segments(self, mock_request, mock_app):
        """Test prefetch when topic has no segments."""
        with patch("server.state") as mock_state:
            mock_state.curriculum_raw = {
                "test-curriculum": {
                    "content": [{
                        "children": [
                            {"id": "empty-topic", "transcript": {"segments": []}}
                        ]
                    }]
                }
            }

            request = mock_request(json_data={
                "curriculum_id": "test-curriculum",
                "topic_id": "empty-topic",
                "voice_id": "nova",
                "tts_provider": "vibevoice",
            })

            response = await tts_api.handle_prefetch_topic(request)

            assert response.status == 404
            assert b"no segments" in response.body

    @pytest.mark.asyncio
    async def test_prefetch_success_with_segments(self, mock_request, mock_app):
        """Test successful prefetch with valid segments."""
        with patch("server.state") as mock_state:
            mock_state.curriculum_raw = {
                "physics-101": {
                    "content": [{
                        "children": [
                            {
                                "id": "intro-quantum",
                                "transcript": {
                                    "segments": [
                                        {"content": "Welcome to quantum physics."},
                                        {"content": "In this lesson, we will explore wave-particle duality."},
                                        {"content": "Let's start with the basics."},
                                    ]
                                }
                            }
                        ]
                    }]
                }
            }

            request = mock_request(json_data={
                "curriculum_id": "physics-101",
                "topic_id": "intro-quantum",
                "voice_id": "nova",
                "tts_provider": "vibevoice",
            })

            response = await tts_api.handle_prefetch_topic(request)

            assert response.status == 200
            import json
            body = json.loads(response.body.decode())
            assert body["status"] == "started"
            assert body["total_segments"] == 3

    @pytest.mark.asyncio
    async def test_prefetch_uses_default_voice_and_provider(self, mock_request, mock_app):
        """Test prefetch uses default voice_id and provider when not specified."""
        with patch("server.state") as mock_state:
            mock_state.curriculum_raw = {
                "test-curriculum": {
                    "content": [{
                        "children": [
                            {
                                "id": "topic1",
                                "transcript": {
                                    "segments": [{"content": "Test segment"}]
                                }
                            }
                        ]
                    }]
                }
            }

            # Only provide required fields, not voice_id or provider
            request = mock_request(json_data={
                "curriculum_id": "test-curriculum",
                "topic_id": "topic1",
            })

            response = await tts_api.handle_prefetch_topic(request)

            assert response.status == 200

    @pytest.mark.asyncio
    async def test_prefetch_empty_content_segments(self, mock_request, mock_app):
        """Test prefetch skips segments without content."""
        with patch("server.state") as mock_state:
            mock_state.curriculum_raw = {
                "test-curriculum": {
                    "content": [{
                        "children": [
                            {
                                "id": "mixed-topic",
                                "transcript": {
                                    "segments": [
                                        {"content": "Valid segment"},
                                        {"content": ""},  # Empty
                                        {},  # No content key
                                        {"content": "Another valid segment"},
                                    ]
                                }
                            }
                        ]
                    }]
                }
            }

            request = mock_request(json_data={
                "curriculum_id": "test-curriculum",
                "topic_id": "mixed-topic",
            })

            response = await tts_api.handle_prefetch_topic(request)

            assert response.status == 200
            import json
            body = json.loads(response.body.decode())
            # Should only count segments with content
            assert body["total_segments"] == 2

    @pytest.mark.asyncio
    async def test_prefetch_empty_curriculum_content(self, mock_request, mock_app):
        """Test prefetch when curriculum content is empty."""
        with patch("server.state") as mock_state:
            mock_state.curriculum_raw = {
                "empty-curriculum": {
                    "content": []  # Empty content
                }
            }

            request = mock_request(json_data={
                "curriculum_id": "empty-curriculum",
                "topic_id": "any-topic",
            })

            response = await tts_api.handle_prefetch_topic(request)

            assert response.status == 404
            assert b"no segments" in response.body

    @pytest.mark.asyncio
    async def test_prefetch_no_children_in_content(self, mock_request, mock_app):
        """Test prefetch when content item has no children."""
        with patch("server.state") as mock_state:
            mock_state.curriculum_raw = {
                "no-children-curriculum": {
                    "content": [{}]  # Content item without children
                }
            }

            request = mock_request(json_data={
                "curriculum_id": "no-children-curriculum",
                "topic_id": "any-topic",
            })

            response = await tts_api.handle_prefetch_topic(request)

            assert response.status == 404


# =============================================================================
# Additional Edge Case Tests
# =============================================================================

class TestTTSRequestEdgeCases:
    """Additional edge case tests for TTS request handling."""

    @pytest.mark.asyncio
    async def test_tts_request_with_piper_provider(self, mock_request, mock_app):
        """Test TTS request with piper provider."""
        request = mock_request(json_data={
            "text": "Hello with piper",
            "voice_id": "piper_voice",
            "tts_provider": "piper",
            "speed": 1.2,
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.content_type == "audio/wav"

    @pytest.mark.asyncio
    async def test_tts_request_with_chatterbox_provider(self, make_request, tts_server_responses):
        """Test TTS request with chatterbox provider."""
        request = make_request(json_data={
            "text": "Hello with chatterbox",
            "voice_id": "chatterbox_voice",
            "tts_provider": "chatterbox",
            "speed": 0.9,
            "chatterbox_config": {
                "exaggeration": 0.3,
                "cfg_weight": 0.7,
                "language": "en",
            },
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.content_type == "audio/wav"

    @pytest.mark.asyncio
    async def test_cache_hit_with_proper_entry(self, make_request, real_app):
        """Test cache hit returns cached audio."""
        cache = real_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="test cache entry",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        # Add properly to cache using real API
        await cache.put(key, b"cached audio", 24000, 2.5)

        request = make_request(json_data={
            "text": "test cache entry",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": 1.0,
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.headers.get("X-TTS-Cache-Status") == "hit"

    @pytest.mark.asyncio
    async def test_get_cache_entry_returns_data(self, make_request, real_app):
        """Test get cache entry returns cached audio."""
        cache = real_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="entry for get",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        # Add properly to cache
        await cache.put(key, b"audio data for get", 24000, 2.5)

        request = make_request(method="GET", query={
            "text": "entry for get",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": "1.0",
        })

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 200
        assert response.headers.get("X-TTS-Cache-Status") == "hit"


class TestCacheEntryWithChatterboxConfig:
    """Tests for cache entry operations with Chatterbox configuration."""

    @pytest.mark.asyncio
    async def test_put_cache_entry_with_chatterbox_config(self, mock_request):
        """Test putting cache entry with full chatterbox config."""
        audio_data = base64.b64encode(b"chatterbox audio data").decode()
        request = mock_request(json_data={
            "text": "Hello chatterbox world",
            "audio_base64": audio_data,
            "voice_id": "chatterbox_voice",
            "tts_provider": "chatterbox",
            "sample_rate": 24000,
            "duration_seconds": 3.0,
            "exaggeration": 0.6,
            "cfg_weight": 0.4,
            "language": "en",
        })

        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 200
        import json
        body = json.loads(response.body.decode())
        assert body["status"] == "ok"
        assert "hash" in body

    @pytest.mark.asyncio
    async def test_put_cache_entry_with_defaults(self, mock_request):
        """Test putting cache entry using all defaults."""
        audio_data = base64.b64encode(b"default audio").decode()
        request = mock_request(json_data={
            "text": "Minimal entry",
            "audio_base64": audio_data,
        })

        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_put_cache_entry_with_speed(self, mock_request):
        """Test putting cache entry with custom speed."""
        audio_data = base64.b64encode(b"fast audio").decode()
        request = mock_request(json_data={
            "text": "Fast speech",
            "audio_base64": audio_data,
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": 1.5,
            "sample_rate": 24000,
            "duration_seconds": 1.5,
        })

        response = await tts_api.handle_put_cache_entry(request)

        assert response.status == 200


class TestSampleRateFallbacks:
    """Tests for sample rate fallback behavior."""

    def test_vibevoice_sample_rate(self):
        """Test vibevoice sample rate constant."""
        assert tts_api.SAMPLE_RATES["vibevoice"] == 24000

    def test_piper_sample_rate(self):
        """Test piper sample rate constant."""
        assert tts_api.SAMPLE_RATES["piper"] == 22050

    def test_chatterbox_sample_rate(self):
        """Test chatterbox sample rate constant."""
        assert tts_api.SAMPLE_RATES["chatterbox"] == 24000

    @pytest.mark.asyncio
    async def test_cache_hit_uses_stored_sample_rate(self, make_request, real_app):
        """Test that cache hit uses stored sample rate from cache entry."""
        cache = real_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="piper test cached",
            voice_id="piper_voice",
            provider="piper",
            speed=1.0,
        )
        # Store with piper sample rate (22050)
        await cache.put(key, b"piper audio", 22050, 2.5)

        request = make_request(json_data={
            "text": "piper test cached",
            "voice_id": "piper_voice",
            "tts_provider": "piper",
            "speed": 1.0,
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        assert response.headers.get("X-TTS-Cache-Status") == "hit"


class TestEvictionEndpoints:
    """Additional tests for eviction endpoints."""

    @pytest.mark.asyncio
    async def test_evict_lru_zero_target(self, mock_request):
        """Test LRU eviction with zero target size."""
        request = mock_request(json_data={"target_size_mb": 0})
        response = await tts_api.handle_evict_lru(request)

        # 0 is not positive, should fail validation
        assert response.status == 400

    @pytest.mark.asyncio
    async def test_evict_lru_large_target(self, mock_request):
        """Test LRU eviction with very large target size."""
        request = mock_request(json_data={"target_size_mb": 10000})
        response = await tts_api.handle_evict_lru(request)

        assert response.status == 200


class TestRouteRegistration:
    """Additional tests for route registration."""

    @pytest.mark.asyncio
    async def test_all_routes_registered(self, real_tts_cache, real_resource_pool):
        """Test that all expected routes are registered."""
        app = web.Application()
        app["tts_cache"] = real_tts_cache
        app["tts_resource_pool"] = real_resource_pool

        tts_api.register_tts_routes(app)

        route_paths = [r.resource.canonical for r in app.router.routes()]

        # Check all expected routes
        expected_routes = [
            "/api/tts",
            "/api/tts/cache/stats",
            "/api/tts/cache",
            "/api/tts/cache/expired",
            "/api/tts/cache/evict",
            "/api/tts/prefetch/topic",
            "/api/tts/prefetch/status/{job_id}",
            "/api/tts/prefetch/{job_id}",
        ]
        for route in expected_routes:
            assert route in route_paths, f"Missing route: {route}"

    def test_route_methods(self):
        """Test that routes have correct HTTP methods."""
        app = web.Application()
        tts_api.register_tts_routes(app)

        # Build a map of route paths to methods
        routes = {}
        for route in app.router.routes():
            path = route.resource.canonical
            method = route.method
            if path not in routes:
                routes[path] = []
            routes[path].append(method)

        # Verify methods
        assert "POST" in routes.get("/api/tts", [])
        assert "GET" in routes.get("/api/tts/cache/stats", [])
        assert "GET" in routes.get("/api/tts/cache", [])
        assert "PUT" in routes.get("/api/tts/cache", [])
        assert "DELETE" in routes.get("/api/tts/cache", [])


class TestValidProviders:
    """Tests for valid provider validation."""

    @pytest.mark.asyncio
    async def test_all_valid_providers_accepted(self, make_request, tts_server_responses):
        """Test that all valid providers are accepted."""
        for provider in ["vibevoice", "piper", "chatterbox"]:
            request = make_request(json_data={
                "text": f"Test {provider}",
                "tts_provider": provider,
            })
            response = await tts_api.handle_tts_request(request)
            assert response.status == 200, f"Provider {provider} should be accepted"

    @pytest.mark.asyncio
    async def test_invalid_provider_rejected(self, make_request):
        """Test that invalid providers are rejected."""
        for provider in ["openai", "elevenlabs", "azure", "VIBEVOICE", ""]:
            request = make_request(json_data={
                "text": "Test invalid",
                "tts_provider": provider,
            })
            response = await tts_api.handle_tts_request(request)
            assert response.status == 400, f"Provider {provider} should be rejected"
