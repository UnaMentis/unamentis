# TTS Cache Unit Tests

import asyncio
import tempfile
from pathlib import Path
import pytest

from tts_cache.models import TTSCacheKey, TTSCacheEntry, TTSCacheStats
from tts_cache.cache import TTSCache


class TestTTSCacheKey:
    """Tests for TTSCacheKey."""

    def test_normalize_text(self):
        """Test text normalization."""
        # Whitespace handling
        assert TTSCacheKey.normalize_text("  hello  ") == "hello"
        assert TTSCacheKey.normalize_text("hello   world") == "hello world"

        # Unicode normalization
        text = "café"
        normalized = TTSCacheKey.normalize_text(text)
        assert len(normalized) > 0

    def test_hash_text(self):
        """Test text hashing."""
        hash1 = TTSCacheKey.hash_text("hello world")
        hash2 = TTSCacheKey.hash_text("hello world")
        hash3 = TTSCacheKey.hash_text("different text")

        assert hash1 == hash2  # Same text = same hash
        assert hash1 != hash3  # Different text = different hash
        assert len(hash1) == 16  # First 16 chars of SHA-256

    def test_from_request(self):
        """Test creating key from request parameters."""
        key = TTSCacheKey.from_request(
            text="Hello world",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
        )

        assert key.voice_id == "nova"
        assert key.tts_provider == "vibevoice"
        assert key.speed == 1.0
        assert key.exaggeration is None  # Not chatterbox

    def test_from_request_chatterbox(self):
        """Test creating key with Chatterbox params."""
        key = TTSCacheKey.from_request(
            text="Hello world",
            voice_id="nova",
            provider="chatterbox",
            speed=1.0,
            exaggeration=0.5,
            cfg_weight=0.7,
        )

        assert key.tts_provider == "chatterbox"
        assert key.exaggeration == 0.5
        assert key.cfg_weight == 0.7

    def test_chatterbox_params_ignored_for_other_providers(self):
        """Chatterbox params should be None for non-chatterbox providers."""
        key = TTSCacheKey.from_request(
            text="Hello world",
            voice_id="nova",
            provider="vibevoice",
            speed=1.0,
            exaggeration=0.5,  # Should be ignored
            cfg_weight=0.7,    # Should be ignored
        )

        assert key.exaggeration is None
        assert key.cfg_weight is None

    def test_to_hash_deterministic(self):
        """Same key should always produce same hash."""
        key1 = TTSCacheKey.from_request("hello", "nova", "vibevoice")
        key2 = TTSCacheKey.from_request("hello", "nova", "vibevoice")

        assert key1.to_hash() == key2.to_hash()

    def test_to_hash_different_params(self):
        """Different params should produce different hashes."""
        key1 = TTSCacheKey.from_request("hello", "nova", "vibevoice", speed=1.0)
        key2 = TTSCacheKey.from_request("hello", "nova", "vibevoice", speed=1.5)

        assert key1.to_hash() != key2.to_hash()


class TestTTSCacheStats:
    """Tests for TTSCacheStats."""

    def test_hit_rate_zero(self):
        """Hit rate should be 0 with no hits."""
        stats = TTSCacheStats()
        assert stats.hit_rate == 0.0

    def test_hit_rate_calculation(self):
        """Hit rate should calculate correctly."""
        stats = TTSCacheStats(hits=80, misses=20)
        assert stats.hit_rate == 80.0

    def test_utilization_percent(self):
        """Utilization should calculate correctly."""
        stats = TTSCacheStats(
            total_size_bytes=1024 * 1024 * 500,  # 500MB
            max_size_bytes=1024 * 1024 * 1024 * 2,  # 2GB
        )
        assert 24.0 < stats.utilization_percent < 25.0

    def test_size_formatted(self):
        """Size should format to human-readable string."""
        stats = TTSCacheStats(total_size_bytes=1024 * 1024 * 512)  # 512MB
        assert "MB" in stats.total_size_formatted


class TestTTSCache:
    """Tests for TTSCache."""

    @pytest.fixture
    def cache_dir(self):
        """Create temporary directory for cache."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield Path(tmpdir)

    @pytest.mark.asyncio
    async def test_initialize(self, cache_dir):
        """Test cache initialization."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        assert cache._initialized
        assert (cache_dir / "audio").exists()

    @pytest.mark.asyncio
    async def test_put_and_get(self, cache_dir):
        """Test storing and retrieving audio."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        key = TTSCacheKey.from_request("hello world", "nova", "vibevoice")
        audio_data = b"fake audio data" * 100

        # Put
        entry = await cache.put(key, audio_data, 24000, 1.5)
        assert entry.size_bytes == len(audio_data)

        # Get
        retrieved = await cache.get(key)
        assert retrieved == audio_data

    @pytest.mark.asyncio
    async def test_cache_miss(self, cache_dir):
        """Test cache miss returns None."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        key = TTSCacheKey.from_request("not cached", "nova", "vibevoice")
        result = await cache.get(key)

        assert result is None

    @pytest.mark.asyncio
    async def test_has(self, cache_dir):
        """Test checking if key exists."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        key = TTSCacheKey.from_request("hello world", "nova", "vibevoice")

        assert not await cache.has(key)

        await cache.put(key, b"audio", 24000, 1.0)

        assert await cache.has(key)

    @pytest.mark.asyncio
    async def test_delete(self, cache_dir):
        """Test deleting an entry."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        key = TTSCacheKey.from_request("hello world", "nova", "vibevoice")
        await cache.put(key, b"audio", 24000, 1.0)

        assert await cache.has(key)
        assert await cache.delete(key)
        assert not await cache.has(key)

    @pytest.mark.asyncio
    async def test_stats(self, cache_dir):
        """Test getting cache statistics."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        key = TTSCacheKey.from_request("hello world", "nova", "vibevoice")
        await cache.put(key, b"audio data", 24000, 1.0)

        stats = await cache.get_stats()
        assert stats.total_entries == 1
        assert stats.total_size_bytes > 0
        assert "vibevoice" in stats.entries_by_provider

    @pytest.mark.asyncio
    async def test_clear(self, cache_dir):
        """Test clearing the cache."""
        cache = TTSCache(cache_dir)
        await cache.initialize()

        # Add some entries
        for i in range(5):
            key = TTSCacheKey.from_request(f"text {i}", "nova", "vibevoice")
            await cache.put(key, b"audio", 24000, 1.0)

        stats = await cache.get_stats()
        assert stats.total_entries == 5

        # Clear
        removed = await cache.clear()
        assert removed == 5

        stats = await cache.get_stats()
        assert stats.total_entries == 0

    @pytest.mark.asyncio
    async def test_persistence(self, cache_dir):
        """Test that cache persists across restarts."""
        # First instance
        cache1 = TTSCache(cache_dir)
        await cache1.initialize()

        key = TTSCacheKey.from_request("persistent", "nova", "vibevoice")
        await cache1.put(key, b"audio data", 24000, 1.0)
        await cache1.shutdown()

        # Second instance
        cache2 = TTSCache(cache_dir)
        await cache2.initialize()

        result = await cache2.get(key)
        assert result == b"audio data"
