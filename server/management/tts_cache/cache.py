# TTS Cache Implementation
# Async file-based cache with LRU eviction and TTL expiration

import asyncio
import aiofiles
import json
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Optional, Tuple

from .models import TTSCacheKey, TTSCacheEntry, TTSCacheStats

logger = logging.getLogger(__name__)


class TTSCache:
    """Async file-based TTS cache with LRU eviction.

    Features:
    - File-based storage organized by hash prefix
    - Persistent index for fast lookups
    - LRU eviction when size limit exceeded
    - TTL-based expiration
    - Thread-safe async operations
    """

    def __init__(
        self,
        cache_dir: Path,
        max_size_bytes: int = 2 * 1024 * 1024 * 1024,  # 2GB
        default_ttl_days: int = 30,
    ):
        """Initialize TTS cache.

        Args:
            cache_dir: Directory for cache storage
            max_size_bytes: Maximum cache size in bytes (default 2GB)
            default_ttl_days: Default TTL for entries in days (default 30)
        """
        self.cache_dir = Path(cache_dir)
        self.audio_dir = self.cache_dir / "audio"
        self.index_path = self.cache_dir / "index.json"
        self.max_size_bytes = max_size_bytes
        self.default_ttl = timedelta(days=default_ttl_days)

        # In-memory index: hash -> TTSCacheEntry
        self.index: Dict[str, TTSCacheEntry] = {}
        self._lock = asyncio.Lock()

        # Statistics
        self._stats = TTSCacheStats(max_size_bytes=max_size_bytes)

        # Track if initialized
        self._initialized = False

    async def initialize(self) -> None:
        """Initialize cache: create directories and load index."""
        if self._initialized:
            return

        # Create directories
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.audio_dir.mkdir(parents=True, exist_ok=True)

        # Create hash prefix subdirectories (00-ff)
        for i in range(256):
            prefix_dir = self.audio_dir / f"{i:02x}"
            prefix_dir.mkdir(exist_ok=True)

        # Load existing index
        await self._load_index()

        # Cleanup expired entries
        expired = await self.evict_expired()
        if expired > 0:
            logger.info(f"TTS cache initialized, evicted {expired} expired entries")

        self._initialized = True
        logger.info(
            f"TTS cache ready: {self._stats.total_entries} entries, "
            f"{self._stats.total_size_formatted}"
        )

    async def get(self, key: TTSCacheKey) -> Optional[bytes]:
        """Get cached audio data.

        Args:
            key: Cache key for the audio

        Returns:
            Audio bytes if found and not expired, None otherwise
        """
        hash_key = key.to_hash()

        async with self._lock:
            if hash_key not in self.index:
                self._stats.record_miss()
                return None

            entry = self.index[hash_key]

            # Check expiration
            if entry.is_expired:
                await self._remove_entry_unlocked(hash_key)
                self._stats.record_miss()
                return None

            # Update access time
            entry.touch()

        # Read file outside lock
        audio_path = Path(entry.file_path)
        if not audio_path.exists():
            # File missing, remove from index
            async with self._lock:
                await self._remove_entry_unlocked(hash_key)
            self._stats.record_miss()
            return None

        try:
            async with aiofiles.open(audio_path, "rb") as f:
                data = await f.read()
            self._stats.record_hit()
            return data
        except Exception as e:
            logger.error(f"Failed to read cached audio {audio_path}: {e}")
            self._stats.record_miss()
            return None

    async def has(self, key: TTSCacheKey) -> bool:
        """Check if key exists and is not expired."""
        hash_key = key.to_hash()

        async with self._lock:
            if hash_key not in self.index:
                return False

            entry = self.index[hash_key]
            if entry.is_expired:
                await self._remove_entry_unlocked(hash_key)
                return False

            return True

    async def put(
        self,
        key: TTSCacheKey,
        audio_data: bytes,
        sample_rate: int,
        duration_seconds: float,
        ttl_days: Optional[int] = None,
    ) -> TTSCacheEntry:
        """Store audio in cache.

        Args:
            key: Cache key
            audio_data: Raw audio bytes
            sample_rate: Audio sample rate (e.g., 24000)
            duration_seconds: Audio duration
            ttl_days: Optional custom TTL in days

        Returns:
            The created cache entry
        """
        hash_key = key.to_hash()
        ttl_seconds = (ttl_days or self.default_ttl.days) * 24 * 60 * 60

        # Determine file path using hash prefix for distribution
        prefix = hash_key[:2]
        file_name = f"{hash_key}.wav"
        file_path = self.audio_dir / prefix / file_name

        # Write file first
        try:
            async with aiofiles.open(file_path, "wb") as f:
                await f.write(audio_data)
        except Exception as e:
            logger.error(f"Failed to write cache file {file_path}: {e}")
            raise

        # Create entry
        now = datetime.now()
        entry = TTSCacheEntry(
            key=key,
            file_path=str(file_path),
            size_bytes=len(audio_data),
            sample_rate=sample_rate,
            duration_seconds=duration_seconds,
            created_at=now,
            last_accessed_at=now,
            access_count=1,
            ttl_seconds=ttl_seconds,
        )

        # Update index
        async with self._lock:
            # Remove old entry if exists (replacement)
            if hash_key in self.index:
                old_entry = self.index[hash_key]
                self._stats.total_size_bytes -= old_entry.size_bytes
                provider = old_entry.key.tts_provider
                if provider in self._stats.entries_by_provider:
                    self._stats.entries_by_provider[provider] -= 1

            self.index[hash_key] = entry
            self._stats.total_size_bytes += entry.size_bytes
            self._stats.total_entries = len(self.index)

            # Update provider count
            provider = key.tts_provider
            if provider not in self._stats.entries_by_provider:
                self._stats.entries_by_provider[provider] = 0
            self._stats.entries_by_provider[provider] += 1

        # Check if we need to evict (outside lock to avoid blocking)
        await self._maybe_evict()

        # Save index periodically (not on every put)
        if len(self.index) % 10 == 0:
            asyncio.create_task(self._save_index())

        logger.debug(f"Cached TTS audio: {hash_key} ({len(audio_data)} bytes)")
        return entry

    async def delete(self, key: TTSCacheKey) -> bool:
        """Remove entry from cache.

        Returns:
            True if entry was removed, False if not found
        """
        hash_key = key.to_hash()

        async with self._lock:
            if hash_key not in self.index:
                return False
            await self._remove_entry_unlocked(hash_key)
            return True

    async def evict_expired(self) -> int:
        """Remove all expired entries.

        Returns:
            Number of entries removed
        """
        removed = 0

        async with self._lock:
            expired_keys = [
                h for h, entry in self.index.items() if entry.is_expired
            ]

            for hash_key in expired_keys:
                await self._remove_entry_unlocked(hash_key)
                removed += 1

            if removed > 0:
                self._stats.record_eviction(removed)

        if removed > 0:
            await self._save_index()
            logger.info(f"Evicted {removed} expired TTS cache entries")

        return removed

    async def evict_lru(self, target_size_bytes: Optional[int] = None) -> int:
        """Evict least recently used entries until under target size.

        Args:
            target_size_bytes: Target size (default: 80% of max)

        Returns:
            Number of entries evicted
        """
        if target_size_bytes is None:
            target_size_bytes = int(self.max_size_bytes * 0.8)

        removed = 0

        async with self._lock:
            if self._stats.total_size_bytes <= target_size_bytes:
                return 0

            # Sort by last access time (oldest first)
            sorted_entries = sorted(
                self.index.items(),
                key=lambda x: x[1].last_accessed_at,
            )

            for hash_key, _entry in sorted_entries:
                if self._stats.total_size_bytes <= target_size_bytes:
                    break
                await self._remove_entry_unlocked(hash_key)
                removed += 1

            if removed > 0:
                self._stats.record_eviction(removed)

        if removed > 0:
            await self._save_index()
            logger.info(f"LRU evicted {removed} TTS cache entries")

        return removed

    async def clear(self) -> int:
        """Clear entire cache.

        Returns:
            Number of entries removed
        """
        async with self._lock:
            count = len(self.index)

            for hash_key in list(self.index.keys()):
                await self._remove_entry_unlocked(hash_key)

            self._stats.total_entries = 0
            self._stats.total_size_bytes = 0
            self._stats.entries_by_provider = {}

        await self._save_index()
        logger.info(f"Cleared TTS cache: {count} entries removed")
        return count

    async def get_stats(self) -> TTSCacheStats:
        """Get current cache statistics."""
        async with self._lock:
            self._stats.total_entries = len(self.index)
            return TTSCacheStats(
                total_entries=self._stats.total_entries,
                total_size_bytes=self._stats.total_size_bytes,
                max_size_bytes=self._stats.max_size_bytes,
                hits=self._stats.hits,
                misses=self._stats.misses,
                eviction_count=self._stats.eviction_count,
                prefetch_count=self._stats.prefetch_count,
                prefetch_hits=self._stats.prefetch_hits,
                entries_by_provider=dict(self._stats.entries_by_provider),
            )

    async def _maybe_evict(self) -> None:
        """Trigger LRU eviction if over size limit."""
        if self._stats.total_size_bytes > self.max_size_bytes:
            await self.evict_lru()

    async def _remove_entry_unlocked(self, hash_key: str) -> None:
        """Remove entry from index and delete file. Must hold lock."""
        if hash_key not in self.index:
            return

        entry = self.index[hash_key]

        # Update stats
        self._stats.total_size_bytes -= entry.size_bytes
        provider = entry.key.tts_provider
        if provider in self._stats.entries_by_provider:
            self._stats.entries_by_provider[provider] -= 1
            if self._stats.entries_by_provider[provider] <= 0:
                del self._stats.entries_by_provider[provider]

        # Remove from index
        del self.index[hash_key]

        # Delete file (don't await, fire and forget)
        file_path = Path(entry.file_path)
        if file_path.exists():
            try:
                file_path.unlink()
            except Exception as e:
                logger.warning(f"Failed to delete cache file {file_path}: {e}")

    async def _load_index(self) -> None:
        """Load cache index from disk."""
        if not self.index_path.exists():
            logger.info("No existing TTS cache index found")
            return

        try:
            async with aiofiles.open(self.index_path, "r") as f:
                data = json.loads(await f.read())

            entries = data.get("entries", {})
            stats = data.get("stats", {})

            for hash_key, entry_dict in entries.items():
                try:
                    entry = TTSCacheEntry.from_dict(entry_dict)
                    # Verify file exists
                    if Path(entry.file_path).exists():
                        self.index[hash_key] = entry
                except Exception as e:
                    logger.warning(f"Failed to load cache entry {hash_key}: {e}")

            # Restore stats
            self._stats.total_entries = len(self.index)
            self._stats.total_size_bytes = sum(e.size_bytes for e in self.index.values())
            self._stats.hits = stats.get("hits", 0)
            self._stats.misses = stats.get("misses", 0)
            self._stats.eviction_count = stats.get("eviction_count", 0)
            self._stats.prefetch_count = stats.get("prefetch_count", 0)
            self._stats.prefetch_hits = stats.get("prefetch_hits", 0)

            # Rebuild provider counts
            self._stats.entries_by_provider = {}
            for entry in self.index.values():
                provider = entry.key.tts_provider
                if provider not in self._stats.entries_by_provider:
                    self._stats.entries_by_provider[provider] = 0
                self._stats.entries_by_provider[provider] += 1

            logger.info(f"Loaded TTS cache index: {len(self.index)} entries")
        except Exception as e:
            logger.error(f"Failed to load TTS cache index: {e}")

    async def _save_index(self) -> None:
        """Persist cache index to disk."""
        try:
            async with self._lock:
                data = {
                    "version": 1,
                    "saved_at": datetime.now().isoformat(),
                    "entries": {
                        h: entry.to_dict() for h, entry in self.index.items()
                    },
                    "stats": {
                        "hits": self._stats.hits,
                        "misses": self._stats.misses,
                        "eviction_count": self._stats.eviction_count,
                        "prefetch_count": self._stats.prefetch_count,
                        "prefetch_hits": self._stats.prefetch_hits,
                    },
                }

            # Write to temp file first, then rename for atomicity
            temp_path = self.index_path.with_suffix(".tmp")
            async with aiofiles.open(temp_path, "w") as f:
                await f.write(json.dumps(data, indent=2))

            temp_path.rename(self.index_path)
            logger.debug("Saved TTS cache index")
        except Exception as e:
            logger.error(f"Failed to save TTS cache index: {e}")

    async def shutdown(self) -> None:
        """Graceful shutdown: save index."""
        await self._save_index()
        logger.info("TTS cache shutdown complete")
