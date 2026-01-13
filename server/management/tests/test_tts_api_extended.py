"""
Extended tests for TTS API routes.

These tests cover additional edge cases and functionality not covered
by test_tts_api.py, specifically targeting:
- Lines 217-220: Resource pool stats in cache stats response
- Lines 426-428: Float conversion of exaggeration/cfg_weight in get cache entry
- Lines 517-556: Prefetch topic with curriculum parsing and segment extraction
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
# Tests for Lines 217-220: Resource Pool Stats in Cache Stats Response
# =============================================================================

class TestCacheStatsWithResourcePool:
    """Tests for resource pool statistics in cache stats endpoint."""

    @pytest.mark.asyncio
    async def test_stats_with_resource_pool_present(self, mock_request, mock_app):
        """Test that resource pool stats are included when pool is available."""
        request = mock_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200
        # Response should include resource_pool key
        import json
        body = json.loads(response.body.decode())
        assert "resource_pool" in body
        assert body["resource_pool"]["active_requests"] == 2
        assert body["resource_pool"]["pending_live"] == 1

    @pytest.mark.asyncio
    async def test_stats_without_resource_pool(self, mock_request, mock_app):
        """Test stats response when resource pool is None."""
        mock_app["tts_resource_pool"] = None
        request = mock_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200
        import json
        body = json.loads(response.body.decode())
        # Should not include resource_pool key when pool is None
        assert "resource_pool" not in body
        assert "cache" in body

    @pytest.mark.asyncio
    async def test_stats_resource_pool_with_custom_stats(self, mock_request, mock_app):
        """Test stats with custom resource pool statistics."""
        custom_pool = MockResourcePool()
        custom_pool.get_stats = lambda: {
            "active_requests": 10,
            "pending_live": 5,
            "pending_prefetch": 15,
            "total_generated": 500,
            "errors": 3,
        }
        mock_app["tts_resource_pool"] = custom_pool

        request = mock_request(method="GET")
        response = await tts_api.handle_get_cache_stats(request)

        assert response.status == 200
        import json
        body = json.loads(response.body.decode())
        assert body["resource_pool"]["active_requests"] == 10
        assert body["resource_pool"]["total_generated"] == 500
        assert body["resource_pool"]["errors"] == 3


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
    async def test_tts_request_with_chatterbox_provider(self, mock_request, mock_app):
        """Test TTS request with chatterbox provider."""
        request = mock_request(json_data={
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
    async def test_cache_hit_with_missing_entry_metadata(self, mock_request, mock_app):
        """Test cache hit when index entry is missing (edge case)."""
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="orphan entry",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        # Add to data but not to index
        hash_key = key.to_hash()
        cache._data[hash_key] = b"orphan audio"
        # Do not add to cache.index

        request = mock_request(json_data={
            "text": "orphan entry",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": 1.0,
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        # Should still return data, using fallback sample rate
        assert response.headers.get("X-TTS-Cache-Status") == "hit"

    @pytest.mark.asyncio
    async def test_get_cache_entry_with_missing_index(self, mock_request, mock_app):
        """Test get cache entry when entry exists but not in index."""
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="missing index entry",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )
        hash_key = key.to_hash()
        cache._data[hash_key] = b"audio without index"
        # Intentionally not adding to index

        request = mock_request(method="GET", query={
            "text": "missing index entry",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": "1.0",
        })

        response = await tts_api.handle_get_cache_entry(request)

        assert response.status == 200
        # Should use default sample rate
        assert response.headers.get("X-TTS-Sample-Rate") == "24000"


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
    async def test_cache_hit_uses_piper_fallback_rate(self, mock_request, mock_app):
        """Test that piper provider uses correct fallback sample rate."""
        cache = mock_app["tts_cache"]
        from tts_cache import TTSCacheKey
        key = TTSCacheKey.from_request(
            text="piper test",
            voice_id="piper_voice",
            provider="piper",
            speed=1.0,
        )
        hash_key = key.to_hash()
        cache._data[hash_key] = b"piper audio"
        # No index entry - will use fallback

        request = mock_request(json_data={
            "text": "piper test",
            "voice_id": "piper_voice",
            "tts_provider": "piper",
            "speed": 1.0,
        })

        response = await tts_api.handle_tts_request(request)

        assert response.status == 200
        # Should use piper fallback rate
        assert response.headers.get("X-TTS-Sample-Rate") == "22050"


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

    def test_all_routes_registered(self):
        """Test that all expected routes are registered."""
        app = web.Application()
        app["tts_cache"] = MockTTSCache()
        app["tts_resource_pool"] = MockResourcePool()

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
    async def test_all_valid_providers_accepted(self, mock_request):
        """Test that all valid providers are accepted."""
        for provider in ["vibevoice", "piper", "chatterbox"]:
            request = mock_request(json_data={
                "text": f"Test {provider}",
                "tts_provider": provider,
            })
            response = await tts_api.handle_tts_request(request)
            assert response.status == 200, f"Provider {provider} should be accepted"

    @pytest.mark.asyncio
    async def test_invalid_provider_rejected(self, mock_request):
        """Test that invalid providers are rejected."""
        for provider in ["openai", "elevenlabs", "azure", "VIBEVOICE", ""]:
            request = mock_request(json_data={
                "text": "Test invalid",
                "tts_provider": provider,
            })
            response = await tts_api.handle_tts_request(request)
            assert response.status == 400, f"Provider {provider} should be rejected"
