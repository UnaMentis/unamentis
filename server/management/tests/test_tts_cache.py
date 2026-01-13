"""
Tests for TTS Cache Implementation

Comprehensive tests for the async file-based TTS cache with LRU eviction and TTL expiration.
Tests verify caching operations, eviction policies, persistence, and statistics tracking.
"""

import asyncio
import json
import pytest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch, mock_open

from tts_cache.cache import TTSCache
from tts_cache.models import TTSCacheKey, TTSCacheEntry, TTSCacheStats


# =============================================================================
# FIXTURES
# =============================================================================


@pytest.fixture
def tmp_cache_dir(tmp_path):
    """Create temporary directory for cache."""
    return tmp_path / "tts_cache"


@pytest.fixture
async def cache(tmp_cache_dir):
    """Create a TTSCache instance with temporary directory."""
    # Must be async because TTSCache creates asyncio.Lock() which requires event loop
    return TTSCache(
        cache_dir=tmp_cache_dir,
        max_size_bytes=1024 * 1024,  # 1MB for testing
        default_ttl_days=7,
    )


@pytest.fixture
def sample_key():
    """Create a sample cache key."""
    return TTSCacheKey.from_request(
        text="Hello world",
        voice_id="nova",
        provider="vibevoice",
        speed=1.0,
    )


@pytest.fixture
def sample_audio_data():
    """Create sample audio data."""
    return b"RIFF" + b"\x00" * 100  # Minimal WAV-like data


@pytest.fixture
def make_cache_key():
    """Factory fixture for creating cache keys."""
    def _make_key(text="Hello", voice_id="nova", provider="vibevoice", speed=1.0):
        return TTSCacheKey.from_request(
            text=text,
            voice_id=voice_id,
            provider=provider,
            speed=speed,
        )
    return _make_key


# =============================================================================
# TTS CACHE INITIALIZATION TESTS
# =============================================================================


class TestTTSCacheInit:
    """Tests for TTSCache initialization."""

    @pytest.mark.asyncio
    async def test_init_default_values(self, tmp_cache_dir):
        """Test default initialization values."""
        cache = TTSCache(cache_dir=tmp_cache_dir)

        assert cache.cache_dir == tmp_cache_dir
        assert cache.audio_dir == tmp_cache_dir / "audio"
        assert cache.index_path == tmp_cache_dir / "index.json"
        assert cache.max_size_bytes == 2 * 1024 * 1024 * 1024  # 2GB
        assert cache.default_ttl == timedelta(days=30)
        assert cache._initialized is False

    @pytest.mark.asyncio
    async def test_init_custom_values(self, tmp_cache_dir):
        """Test initialization with custom values."""
        cache = TTSCache(
            cache_dir=tmp_cache_dir,
            max_size_bytes=500 * 1024 * 1024,
            default_ttl_days=14,
        )

        assert cache.max_size_bytes == 500 * 1024 * 1024
        assert cache.default_ttl == timedelta(days=14)

    @pytest.mark.asyncio
    async def test_init_empty_index(self, tmp_cache_dir):
        """Test index is empty on init."""
        cache = TTSCache(cache_dir=tmp_cache_dir)

        assert cache.index == {}
        assert cache._stats.total_entries == 0
        assert cache._stats.total_size_bytes == 0

    @pytest.mark.asyncio
    async def test_initialize_creates_directories(self, cache, tmp_cache_dir):
        """Test initialize creates cache directories."""
        await cache.initialize()

        assert tmp_cache_dir.exists()
        assert cache.audio_dir.exists()

    @pytest.mark.asyncio
    async def test_initialize_creates_hash_prefix_dirs(self, cache):
        """Test initialize creates 256 hash prefix subdirectories."""
        await cache.initialize()

        for i in range(256):
            prefix_dir = cache.audio_dir / f"{i:02x}"
            assert prefix_dir.exists()

    @pytest.mark.asyncio
    async def test_initialize_idempotent(self, cache):
        """Test initialize is idempotent."""
        await cache.initialize()
        await cache.initialize()  # Second call should be no-op

        assert cache._initialized is True

    @pytest.mark.asyncio
    async def test_initialize_loads_existing_index(self, tmp_cache_dir):
        """Test initialize loads existing index from disk."""
        # Create a cache, add an entry, and save
        cache1 = TTSCache(cache_dir=tmp_cache_dir)
        await cache1.initialize()

        key = TTSCacheKey.from_request("test", "nova", "vibevoice")
        audio_data = b"test audio"
        await cache1.put(key, audio_data, 24000, 1.0)
        await cache1._save_index()

        # Create new cache and verify it loads the entry
        cache2 = TTSCache(cache_dir=tmp_cache_dir)
        await cache2.initialize()

        assert len(cache2.index) == 1


# =============================================================================
# TTS CACHE GET TESTS
# =============================================================================


class TestTTSCacheGet:
    """Tests for TTSCache.get method."""

    @pytest.mark.asyncio
    async def test_get_miss_returns_none(self, cache, sample_key):
        """Test get returns None for missing key."""
        await cache.initialize()

        result = await cache.get(sample_key)

        assert result is None
        assert cache._stats.misses == 1

    @pytest.mark.asyncio
    async def test_get_hit_returns_data(self, cache, sample_key, sample_audio_data):
        """Test get returns cached audio data."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        result = await cache.get(sample_key)

        assert result == sample_audio_data
        assert cache._stats.hits == 1

    @pytest.mark.asyncio
    async def test_get_updates_access_time(self, cache, sample_key, sample_audio_data):
        """Test get updates last_accessed_at."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        hash_key = sample_key.to_hash()

        original_access_time = cache.index[hash_key].last_accessed_at
        await asyncio.sleep(0.01)
        await cache.get(sample_key)

        assert cache.index[hash_key].last_accessed_at > original_access_time

    @pytest.mark.asyncio
    async def test_get_increments_access_count(self, cache, sample_key, sample_audio_data):
        """Test get increments access_count."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        hash_key = sample_key.to_hash()

        original_count = cache.index[hash_key].access_count
        await cache.get(sample_key)

        assert cache.index[hash_key].access_count == original_count + 1

    @pytest.mark.asyncio
    async def test_get_expired_entry_returns_none(self, cache, sample_key, sample_audio_data):
        """Test get returns None for expired entry."""
        await cache.initialize()
        # Put with very short TTL (will have expired by the time we get)
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        hash_key = sample_key.to_hash()

        # Manually set expiration to past
        cache.index[hash_key].created_at = datetime.now() - timedelta(days=100)
        cache.index[hash_key].ttl_seconds = 1

        result = await cache.get(sample_key)

        assert result is None
        assert cache._stats.misses == 1
        assert hash_key not in cache.index  # Entry should be removed

    @pytest.mark.asyncio
    async def test_get_missing_file_returns_none(self, cache, sample_key, sample_audio_data):
        """Test get returns None if file is missing from disk."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        hash_key = sample_key.to_hash()

        # Delete the file manually
        file_path = Path(cache.index[hash_key].file_path)
        file_path.unlink()

        result = await cache.get(sample_key)

        assert result is None
        assert cache._stats.misses == 1
        assert hash_key not in cache.index

    @pytest.mark.asyncio
    async def test_get_file_read_error_returns_none(self, cache, sample_key, sample_audio_data):
        """Test get returns None on file read error."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        # Mock aiofiles.open to raise an exception
        with patch("tts_cache.cache.aiofiles.open", side_effect=IOError("Read error")):
            result = await cache.get(sample_key)

        assert result is None
        assert cache._stats.misses == 1


# =============================================================================
# TTS CACHE HAS TESTS
# =============================================================================


class TestTTSCacheHas:
    """Tests for TTSCache.has method."""

    @pytest.mark.asyncio
    async def test_has_returns_false_for_missing(self, cache, sample_key):
        """Test has returns False for missing key."""
        await cache.initialize()

        result = await cache.has(sample_key)

        assert result is False

    @pytest.mark.asyncio
    async def test_has_returns_true_for_existing(self, cache, sample_key, sample_audio_data):
        """Test has returns True for existing key."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        result = await cache.has(sample_key)

        assert result is True

    @pytest.mark.asyncio
    async def test_has_returns_false_for_expired(self, cache, sample_key, sample_audio_data):
        """Test has returns False for expired entry."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        hash_key = sample_key.to_hash()

        # Manually expire the entry
        cache.index[hash_key].created_at = datetime.now() - timedelta(days=100)
        cache.index[hash_key].ttl_seconds = 1

        result = await cache.has(sample_key)

        assert result is False


# =============================================================================
# TTS CACHE PUT TESTS
# =============================================================================


class TestTTSCachePut:
    """Tests for TTSCache.put method."""

    @pytest.mark.asyncio
    async def test_put_creates_entry(self, cache, sample_key, sample_audio_data):
        """Test put creates cache entry."""
        await cache.initialize()

        entry = await cache.put(sample_key, sample_audio_data, 24000, 1.5)

        assert entry is not None
        assert entry.key == sample_key
        assert entry.size_bytes == len(sample_audio_data)
        assert entry.sample_rate == 24000
        assert entry.duration_seconds == 1.5

    @pytest.mark.asyncio
    async def test_put_writes_file(self, cache, sample_key, sample_audio_data):
        """Test put writes audio file to disk."""
        await cache.initialize()

        entry = await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        file_path = Path(entry.file_path)
        assert file_path.exists()
        assert file_path.read_bytes() == sample_audio_data

    @pytest.mark.asyncio
    async def test_put_uses_hash_prefix_directory(self, cache, sample_key, sample_audio_data):
        """Test put stores file in hash prefix subdirectory."""
        await cache.initialize()

        entry = await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        hash_key = sample_key.to_hash()
        expected_prefix = hash_key[:2]
        assert expected_prefix in entry.file_path

    @pytest.mark.asyncio
    async def test_put_updates_stats(self, cache, sample_key, sample_audio_data):
        """Test put updates cache statistics."""
        await cache.initialize()

        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        assert cache._stats.total_entries == 1
        assert cache._stats.total_size_bytes == len(sample_audio_data)

    @pytest.mark.asyncio
    async def test_put_updates_provider_count(self, cache, sample_key, sample_audio_data):
        """Test put updates entries_by_provider."""
        await cache.initialize()

        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        assert cache._stats.entries_by_provider["vibevoice"] == 1

    @pytest.mark.asyncio
    async def test_put_replaces_existing(self, cache, sample_key, sample_audio_data):
        """Test put replaces existing entry."""
        await cache.initialize()

        await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        new_data = b"NEW DATA" * 20
        entry = await cache.put(sample_key, new_data, 48000, 2.0)

        assert entry.sample_rate == 48000
        assert entry.size_bytes == len(new_data)
        assert cache._stats.total_entries == 1

    @pytest.mark.asyncio
    async def test_put_custom_ttl(self, cache, sample_key, sample_audio_data):
        """Test put with custom TTL."""
        await cache.initialize()

        entry = await cache.put(sample_key, sample_audio_data, 24000, 1.0, ttl_days=90)

        expected_ttl = 90 * 24 * 60 * 60
        assert entry.ttl_seconds == expected_ttl

    @pytest.mark.asyncio
    async def test_put_write_error_raises(self, cache, sample_key, sample_audio_data):
        """Test put raises exception on write error."""
        await cache.initialize()

        with patch("tts_cache.cache.aiofiles.open", side_effect=IOError("Write error")):
            with pytest.raises(IOError):
                await cache.put(sample_key, sample_audio_data, 24000, 1.0)

    @pytest.mark.asyncio
    async def test_put_triggers_eviction_when_over_limit(self, tmp_cache_dir, sample_audio_data):
        """Test put triggers LRU eviction when over size limit."""
        # Create cache with very small size limit
        cache = TTSCache(cache_dir=tmp_cache_dir, max_size_bytes=200)
        await cache.initialize()

        # Add entries that exceed the limit
        for i in range(5):
            key = TTSCacheKey.from_request(f"text{i}", "nova", "vibevoice")
            await cache.put(key, sample_audio_data, 24000, 1.0)

        # Some entries should have been evicted
        assert cache._stats.total_size_bytes <= cache.max_size_bytes


# =============================================================================
# TTS CACHE DELETE TESTS
# =============================================================================


class TestTTSCacheDelete:
    """Tests for TTSCache.delete method."""

    @pytest.mark.asyncio
    async def test_delete_existing_returns_true(self, cache, sample_key, sample_audio_data):
        """Test delete returns True for existing entry."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        result = await cache.delete(sample_key)

        assert result is True

    @pytest.mark.asyncio
    async def test_delete_missing_returns_false(self, cache, sample_key):
        """Test delete returns False for missing entry."""
        await cache.initialize()

        result = await cache.delete(sample_key)

        assert result is False

    @pytest.mark.asyncio
    async def test_delete_removes_from_index(self, cache, sample_key, sample_audio_data):
        """Test delete removes entry from index."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        hash_key = sample_key.to_hash()

        await cache.delete(sample_key)

        assert hash_key not in cache.index

    @pytest.mark.asyncio
    async def test_delete_removes_file(self, cache, sample_key, sample_audio_data):
        """Test delete removes audio file from disk."""
        await cache.initialize()
        entry = await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        file_path = Path(entry.file_path)

        await cache.delete(sample_key)

        assert not file_path.exists()

    @pytest.mark.asyncio
    async def test_delete_updates_stats(self, cache, sample_key, sample_audio_data):
        """Test delete updates statistics."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        await cache.delete(sample_key)

        assert cache._stats.total_size_bytes == 0
        assert "vibevoice" not in cache._stats.entries_by_provider


# =============================================================================
# TTS CACHE EVICTION TESTS
# =============================================================================


class TestTTSCacheEviction:
    """Tests for cache eviction methods."""

    @pytest.mark.asyncio
    async def test_evict_expired_removes_expired_entries(self, cache, make_cache_key, sample_audio_data):
        """Test evict_expired removes only expired entries."""
        await cache.initialize()

        # Add some entries
        fresh_key = make_cache_key("fresh")
        expired_key = make_cache_key("expired")

        await cache.put(fresh_key, sample_audio_data, 24000, 1.0)
        await cache.put(expired_key, sample_audio_data, 24000, 1.0)

        # Manually expire one entry
        expired_hash = expired_key.to_hash()
        cache.index[expired_hash].created_at = datetime.now() - timedelta(days=100)
        cache.index[expired_hash].ttl_seconds = 1

        removed = await cache.evict_expired()

        assert removed == 1
        assert expired_hash not in cache.index
        assert fresh_key.to_hash() in cache.index

    @pytest.mark.asyncio
    async def test_evict_expired_returns_zero_when_none_expired(self, cache, sample_key, sample_audio_data):
        """Test evict_expired returns 0 when no entries expired."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        removed = await cache.evict_expired()

        assert removed == 0

    @pytest.mark.asyncio
    async def test_evict_expired_records_eviction_stat(self, cache, sample_key, sample_audio_data):
        """Test evict_expired records eviction in stats."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        # Expire the entry
        hash_key = sample_key.to_hash()
        cache.index[hash_key].created_at = datetime.now() - timedelta(days=100)
        cache.index[hash_key].ttl_seconds = 1

        await cache.evict_expired()

        assert cache._stats.eviction_count == 1

    @pytest.mark.asyncio
    async def test_evict_lru_removes_oldest_entries(self, cache, make_cache_key, sample_audio_data):
        """Test evict_lru removes least recently used entries."""
        await cache.initialize()

        # Add entries with different access times
        keys = []
        for i in range(5):
            key = make_cache_key(f"text{i}")
            keys.append(key)
            await cache.put(key, sample_audio_data, 24000, 1.0)
            # Stagger access times
            hash_key = key.to_hash()
            cache.index[hash_key].last_accessed_at = datetime.now() - timedelta(hours=5 - i)

        # Evict to target size smaller than total
        target_size = len(sample_audio_data) * 2  # Keep only 2 entries
        removed = await cache.evict_lru(target_size_bytes=target_size)

        assert removed >= 3  # At least 3 should be removed
        # Newest entries should remain
        assert keys[4].to_hash() in cache.index or keys[3].to_hash() in cache.index

    @pytest.mark.asyncio
    async def test_evict_lru_default_target(self, tmp_cache_dir, make_cache_key, sample_audio_data):
        """Test evict_lru uses 80% of max as default target."""
        cache = TTSCache(cache_dir=tmp_cache_dir, max_size_bytes=1000)
        await cache.initialize()

        # Fill cache over the limit
        for i in range(20):
            key = make_cache_key(f"text{i}")
            await cache.put(key, sample_audio_data, 24000, 1.0)

        await cache.evict_lru()

        # Should be at or below 80% of max (800 bytes)
        assert cache._stats.total_size_bytes <= 800

    @pytest.mark.asyncio
    async def test_evict_lru_returns_zero_if_under_target(self, cache, sample_key, sample_audio_data):
        """Test evict_lru returns 0 if already under target."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        removed = await cache.evict_lru(target_size_bytes=1024 * 1024)  # 1MB target

        assert removed == 0


# =============================================================================
# TTS CACHE CLEAR TESTS
# =============================================================================


class TestTTSCacheClear:
    """Tests for TTSCache.clear method."""

    @pytest.mark.asyncio
    async def test_clear_removes_all_entries(self, cache, make_cache_key, sample_audio_data):
        """Test clear removes all entries."""
        await cache.initialize()

        # Add multiple entries
        for i in range(5):
            key = make_cache_key(f"text{i}")
            await cache.put(key, sample_audio_data, 24000, 1.0)

        count = await cache.clear()

        assert count == 5
        assert len(cache.index) == 0

    @pytest.mark.asyncio
    async def test_clear_resets_stats(self, cache, sample_key, sample_audio_data):
        """Test clear resets statistics."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        await cache.clear()

        assert cache._stats.total_entries == 0
        assert cache._stats.total_size_bytes == 0
        assert cache._stats.entries_by_provider == {}

    @pytest.mark.asyncio
    async def test_clear_returns_zero_on_empty_cache(self, cache):
        """Test clear returns 0 on empty cache."""
        await cache.initialize()

        count = await cache.clear()

        assert count == 0


# =============================================================================
# TTS CACHE STATS TESTS
# =============================================================================


class TestTTSCacheStats:
    """Tests for TTSCache.get_stats method."""

    @pytest.mark.asyncio
    async def test_get_stats_returns_copy(self, cache):
        """Test get_stats returns a copy of stats."""
        await cache.initialize()

        stats1 = await cache.get_stats()
        stats1.hits = 999  # Modify the returned copy

        stats2 = await cache.get_stats()
        assert stats2.hits != 999  # Original should be unchanged

    @pytest.mark.asyncio
    async def test_get_stats_reflects_current_state(self, cache, make_cache_key, sample_audio_data):
        """Test get_stats reflects current cache state."""
        await cache.initialize()

        # Add entries from different providers
        key1 = make_cache_key("text1", provider="vibevoice")
        key2 = make_cache_key("text2", provider="piper")
        await cache.put(key1, sample_audio_data, 24000, 1.0)
        await cache.put(key2, sample_audio_data, 22050, 1.0)

        # Generate some hits and misses
        await cache.get(key1)  # Hit
        await cache.get(make_cache_key("missing"))  # Miss

        stats = await cache.get_stats()

        assert stats.total_entries == 2
        assert stats.hits == 1
        assert stats.misses == 1
        assert stats.entries_by_provider["vibevoice"] == 1
        assert stats.entries_by_provider["piper"] == 1


# =============================================================================
# TTS CACHE INDEX PERSISTENCE TESTS
# =============================================================================


class TestTTSCacheIndexPersistence:
    """Tests for index loading and saving."""

    @pytest.mark.asyncio
    async def test_save_index_creates_file(self, cache, sample_key, sample_audio_data):
        """Test _save_index creates index file."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        await cache._save_index()

        assert cache.index_path.exists()

    @pytest.mark.asyncio
    async def test_save_index_contains_entries(self, cache, sample_key, sample_audio_data):
        """Test saved index contains entry data."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        await cache._save_index()

        with open(cache.index_path) as f:
            data = json.load(f)

        assert "entries" in data
        assert len(data["entries"]) == 1

    @pytest.mark.asyncio
    async def test_save_index_contains_stats(self, cache, sample_key, sample_audio_data):
        """Test saved index contains statistics."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        await cache.get(sample_key)  # Generate a hit

        await cache._save_index()

        with open(cache.index_path) as f:
            data = json.load(f)

        assert "stats" in data
        assert data["stats"]["hits"] == 1

    @pytest.mark.asyncio
    async def test_load_index_restores_entries(self, tmp_cache_dir):
        """Test _load_index restores entries from disk."""
        # Create and populate cache
        cache1 = TTSCache(cache_dir=tmp_cache_dir)
        await cache1.initialize()

        key = TTSCacheKey.from_request("test", "nova", "vibevoice")
        await cache1.put(key, b"audio data", 24000, 1.0)
        await cache1._save_index()

        # Load in new cache instance
        cache2 = TTSCache(cache_dir=tmp_cache_dir)
        await cache2._load_index()

        assert len(cache2.index) == 1
        assert key.to_hash() in cache2.index

    @pytest.mark.asyncio
    async def test_load_index_restores_stats(self, tmp_cache_dir):
        """Test _load_index restores statistics."""
        # Create cache with some stats
        cache1 = TTSCache(cache_dir=tmp_cache_dir)
        await cache1.initialize()

        key = TTSCacheKey.from_request("test", "nova", "vibevoice")
        await cache1.put(key, b"audio", 24000, 1.0)
        await cache1.get(key)  # Hit
        await cache1.get(TTSCacheKey.from_request("miss", "nova", "vibevoice"))  # Miss
        await cache1._save_index()

        # Load in new cache instance
        cache2 = TTSCache(cache_dir=tmp_cache_dir)
        await cache2._load_index()

        assert cache2._stats.hits == 1
        assert cache2._stats.misses == 1

    @pytest.mark.asyncio
    async def test_load_index_skips_missing_files(self, tmp_cache_dir):
        """Test _load_index skips entries with missing files."""
        # Create cache with entry
        cache1 = TTSCache(cache_dir=tmp_cache_dir)
        await cache1.initialize()

        key = TTSCacheKey.from_request("test", "nova", "vibevoice")
        entry = await cache1.put(key, b"audio", 24000, 1.0)
        await cache1._save_index()

        # Delete the audio file
        Path(entry.file_path).unlink()

        # Load in new cache instance
        cache2 = TTSCache(cache_dir=tmp_cache_dir)
        await cache2._load_index()

        assert len(cache2.index) == 0

    @pytest.mark.asyncio
    async def test_load_index_handles_missing_file(self, cache):
        """Test _load_index handles missing index file gracefully."""
        # Don't initialize (no index file)
        await cache._load_index()

        assert len(cache.index) == 0

    @pytest.mark.asyncio
    async def test_load_index_handles_corrupt_json(self, cache):
        """Test _load_index handles corrupt JSON gracefully."""
        await cache.initialize()

        # Write corrupt JSON
        with open(cache.index_path, "w") as f:
            f.write("{ invalid json }")

        await cache._load_index()

        # Should not raise, index should remain empty
        assert len(cache.index) == 0

    @pytest.mark.asyncio
    async def test_load_index_handles_corrupt_entry(self, cache, sample_key, sample_audio_data):
        """Test _load_index handles corrupt entries gracefully."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        await cache._save_index()

        # Corrupt one entry in the index
        with open(cache.index_path) as f:
            data = json.load(f)

        # Remove required field from entry
        hash_key = sample_key.to_hash()
        del data["entries"][hash_key]["file_path"]

        with open(cache.index_path, "w") as f:
            json.dump(data, f)

        # Create new cache and load
        cache2 = TTSCache(cache_dir=cache.cache_dir)
        await cache2._load_index()

        # Corrupt entry should be skipped
        assert hash_key not in cache2.index


# =============================================================================
# TTS CACHE SHUTDOWN TESTS
# =============================================================================


class TestTTSCacheShutdown:
    """Tests for TTSCache.shutdown method."""

    @pytest.mark.asyncio
    async def test_shutdown_saves_index(self, cache, sample_key, sample_audio_data):
        """Test shutdown saves the index."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        await cache.shutdown()

        assert cache.index_path.exists()


# =============================================================================
# TTS CACHE CONCURRENCY TESTS
# =============================================================================


class TestTTSCacheConcurrency:
    """Tests for concurrent cache operations."""

    @pytest.mark.asyncio
    async def test_concurrent_puts(self, cache, make_cache_key, sample_audio_data):
        """Test concurrent put operations are safe."""
        await cache.initialize()

        async def put_entry(i):
            key = make_cache_key(f"concurrent{i}")
            await cache.put(key, sample_audio_data, 24000, 1.0)

        # Run 10 concurrent puts
        await asyncio.gather(*[put_entry(i) for i in range(10)])

        assert len(cache.index) == 10

    @pytest.mark.asyncio
    async def test_concurrent_gets(self, cache, make_cache_key, sample_audio_data):
        """Test concurrent get operations are safe."""
        await cache.initialize()

        # Pre-populate cache
        keys = []
        for i in range(5):
            key = make_cache_key(f"concurrent{i}")
            keys.append(key)
            await cache.put(key, sample_audio_data, 24000, 1.0)

        async def get_entry(key):
            return await cache.get(key)

        # Run concurrent gets
        results = await asyncio.gather(*[get_entry(k) for k in keys * 2])

        assert all(r == sample_audio_data for r in results)
        assert cache._stats.hits == 10

    @pytest.mark.asyncio
    async def test_concurrent_mixed_operations(self, cache, make_cache_key, sample_audio_data):
        """Test concurrent mixed operations are safe."""
        await cache.initialize()

        async def put_and_get(i):
            key = make_cache_key(f"mixed{i}")
            await cache.put(key, sample_audio_data, 24000, 1.0)
            await asyncio.sleep(0.001)  # Small delay
            await cache.get(key)
            await cache.has(key)

        # Run concurrent mixed operations
        await asyncio.gather(*[put_and_get(i) for i in range(10)])

        assert len(cache.index) == 10


# =============================================================================
# TTS CACHE ENTRY REMOVAL TESTS
# =============================================================================


class TestTTSCacheEntryRemoval:
    """Tests for _remove_entry_unlocked method."""

    @pytest.mark.asyncio
    async def test_remove_nonexistent_entry_is_noop(self, cache):
        """Test removing nonexistent entry is a no-op."""
        await cache.initialize()

        # Should not raise
        await cache._remove_entry_unlocked("nonexistent_hash")

    @pytest.mark.asyncio
    async def test_remove_entry_updates_provider_count(self, cache, sample_key, sample_audio_data):
        """Test removing entry decrements provider count."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        assert cache._stats.entries_by_provider["vibevoice"] == 1

        hash_key = sample_key.to_hash()
        async with cache._lock:
            await cache._remove_entry_unlocked(hash_key)

        assert "vibevoice" not in cache._stats.entries_by_provider

    @pytest.mark.asyncio
    async def test_remove_entry_handles_file_deletion_error(self, cache, sample_key, sample_audio_data):
        """Test remove handles file deletion error gracefully."""
        await cache.initialize()
        entry = await cache.put(sample_key, sample_audio_data, 24000, 1.0)
        hash_key = sample_key.to_hash()

        # Delete file first to simulate deletion error
        Path(entry.file_path).unlink()

        # Should not raise
        async with cache._lock:
            await cache._remove_entry_unlocked(hash_key)

        assert hash_key not in cache.index


# =============================================================================
# TTS CACHE MAYBE EVICT TESTS
# =============================================================================


class TestTTSCacheMaybeEvict:
    """Tests for _maybe_evict method."""

    @pytest.mark.asyncio
    async def test_maybe_evict_when_under_limit(self, cache, sample_key, sample_audio_data):
        """Test _maybe_evict does nothing when under limit."""
        await cache.initialize()
        await cache.put(sample_key, sample_audio_data, 24000, 1.0)

        initial_entries = len(cache.index)
        await cache._maybe_evict()

        assert len(cache.index) == initial_entries

    @pytest.mark.asyncio
    async def test_maybe_evict_when_over_limit(self, tmp_cache_dir, make_cache_key, sample_audio_data):
        """Test _maybe_evict triggers eviction when over limit."""
        cache = TTSCache(cache_dir=tmp_cache_dir, max_size_bytes=200)
        await cache.initialize()

        # Add enough to exceed limit
        for i in range(10):
            key = make_cache_key(f"text{i}")
            await cache.put(key, sample_audio_data, 24000, 1.0)

        # Manually trigger eviction check
        await cache._maybe_evict()

        assert cache._stats.total_size_bytes <= cache.max_size_bytes


# =============================================================================
# TTS CACHE EDGE CASES
# =============================================================================


class TestTTSCacheEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.mark.asyncio
    async def test_empty_audio_data(self, cache, sample_key):
        """Test caching empty audio data."""
        await cache.initialize()

        entry = await cache.put(sample_key, b"", 24000, 0.0)

        assert entry.size_bytes == 0
        result = await cache.get(sample_key)
        assert result == b""

    @pytest.mark.asyncio
    async def test_large_audio_data(self, cache, sample_key):
        """Test caching large audio data."""
        await cache.initialize()
        large_data = b"\x00" * 100000  # 100KB

        entry = await cache.put(sample_key, large_data, 24000, 4.0)

        result = await cache.get(sample_key)
        assert result == large_data
        assert entry.size_bytes == 100000

    @pytest.mark.asyncio
    async def test_special_characters_in_text(self, cache, sample_audio_data):
        """Test caching with special characters in text."""
        await cache.initialize()

        key = TTSCacheKey.from_request(
            text="Hello! How are you? I'm fine. 123 @#$%",
            voice_id="nova",
            provider="vibevoice",
        )

        await cache.put(key, sample_audio_data, 24000, 1.0)
        result = await cache.get(key)

        assert result == sample_audio_data

    @pytest.mark.asyncio
    async def test_unicode_text(self, cache, sample_audio_data):
        """Test caching with unicode text."""
        await cache.initialize()

        key = TTSCacheKey.from_request(
            text="Hello World",
            voice_id="nova",
            provider="vibevoice",
        )

        await cache.put(key, sample_audio_data, 24000, 1.0)
        result = await cache.get(key)

        assert result == sample_audio_data

    @pytest.mark.asyncio
    async def test_chatterbox_provider_params(self, cache, sample_audio_data):
        """Test caching with Chatterbox provider parameters."""
        await cache.initialize()

        key = TTSCacheKey.from_request(
            text="Test",
            voice_id="default",
            provider="chatterbox",
            speed=1.2,
            exaggeration=0.5,
            cfg_weight=0.3,
            language="en",
        )

        await cache.put(key, sample_audio_data, 24000, 1.0)
        result = await cache.get(key)

        assert result == sample_audio_data

    @pytest.mark.asyncio
    async def test_different_voices_same_text(self, cache, sample_audio_data):
        """Test different voices with same text create different entries."""
        await cache.initialize()

        key1 = TTSCacheKey.from_request("Hello", "nova", "vibevoice")
        key2 = TTSCacheKey.from_request("Hello", "shimmer", "vibevoice")

        await cache.put(key1, sample_audio_data, 24000, 1.0)
        await cache.put(key2, b"different audio", 24000, 1.0)

        result1 = await cache.get(key1)
        result2 = await cache.get(key2)

        assert result1 == sample_audio_data
        assert result2 == b"different audio"
        assert len(cache.index) == 2

    @pytest.mark.asyncio
    async def test_different_speeds_same_text(self, cache, sample_audio_data):
        """Test different speeds with same text create different entries."""
        await cache.initialize()

        key1 = TTSCacheKey.from_request("Hello", "nova", "vibevoice", speed=1.0)
        key2 = TTSCacheKey.from_request("Hello", "nova", "vibevoice", speed=1.5)

        await cache.put(key1, sample_audio_data, 24000, 1.0)
        await cache.put(key2, b"faster audio", 24000, 0.67)

        result1 = await cache.get(key1)
        result2 = await cache.get(key2)

        assert result1 == sample_audio_data
        assert result2 == b"faster audio"
        assert len(cache.index) == 2


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
