# Session-Cache Integration
# Bridges per-user sessions with global TTS cache

import asyncio
import logging
from typing import List, Optional, Tuple

from fov_context import UserSession, UserVoiceConfig
from tts_cache import TTSCache, TTSCacheKey, TTSResourcePool, Priority, CurriculumPrefetcher

logger = logging.getLogger(__name__)


class SessionCacheIntegration:
    """Bridges per-user sessions with global TTS cache.

    This class connects the session management system with the TTS caching system.
    Key responsibilities:
    - Translate user voice config to cache keys
    - Handle audio retrieval with cache-first strategy
    - Trigger prefetch for upcoming segments
    - Track cache hits per session for analytics

    Design principle: Cache keys are user-agnostic (no user_id).
    Same text + same voice config = same cache entry for ALL users.
    """

    def __init__(
        self,
        cache: TTSCache,
        resource_pool: TTSResourcePool,
        prefetcher: Optional[CurriculumPrefetcher] = None,
    ):
        """Initialize session-cache integration.

        Args:
            cache: Global TTS cache instance
            resource_pool: TTS resource pool for priority-based generation
            prefetcher: Optional prefetcher for background pre-generation
        """
        self.cache = cache
        self.resource_pool = resource_pool
        self.prefetcher = prefetcher

        # Per-session analytics (session_id -> stats)
        self._session_stats: dict[str, dict] = {}

    async def get_audio_for_segment(
        self,
        session: UserSession,
        segment_text: str,
    ) -> Tuple[bytes, bool, float]:
        """Get audio from cache or generate for a user session.

        Uses the session's voice configuration to build the cache key.
        Generates with LIVE priority if not cached (user is waiting).

        Args:
            session: User session with voice configuration
            segment_text: Text content to synthesize

        Returns:
            Tuple of (audio_bytes, was_cache_hit, duration_seconds)
        """
        voice_config = session.voice_config

        # Build user-agnostic cache key from session's voice config
        key = TTSCacheKey.from_request(
            text=segment_text,
            voice_id=voice_config.voice_id,
            provider=voice_config.tts_provider,
            speed=voice_config.speed,
            exaggeration=voice_config.exaggeration,
            cfg_weight=voice_config.cfg_weight,
            language=voice_config.language,
        )

        # Check global cache (shared by ALL users with same voice config)
        cached = await self.cache.get(key)
        if cached:
            # Get duration from entry
            hash_key = key.to_hash()
            async with self.cache._lock:
                entry = self.cache.index.get(hash_key)
                duration = entry.duration_seconds if entry else 0.0

            self._record_hit(session.session_id)
            return cached, True, duration

        # Cache miss - generate with LIVE priority (user is waiting)
        try:
            audio_data, sample_rate, duration = await self.resource_pool.generate_with_priority(
                text=segment_text,
                voice_id=voice_config.voice_id,
                provider=voice_config.tts_provider,
                speed=voice_config.speed,
                chatterbox_config=voice_config.get_chatterbox_config(),
                priority=Priority.LIVE,
            )

            # Store in global cache (available to all users with same config)
            await self.cache.put(key, audio_data, sample_rate, duration)

            self._record_miss(session.session_id)
            return audio_data, False, duration

        except Exception as e:
            logger.error(f"Failed to generate audio for session {session.session_id}: {e}")
            raise

    async def check_cache_coverage(
        self,
        voice_config: UserVoiceConfig,
        segments: List[str],
    ) -> dict:
        """Check how many segments are already cached for a voice config.

        Useful for:
        - Estimating time to generate missing audio
        - Showing cache coverage before starting playback
        - Validating scheduled deployment completeness

        Args:
            voice_config: Voice configuration to check
            segments: List of segment texts

        Returns:
            Dict with coverage statistics
        """
        cached_count = 0
        total_count = len(segments)

        for text in segments:
            key = TTSCacheKey.from_request(
                text=text,
                voice_id=voice_config.voice_id,
                provider=voice_config.tts_provider,
                speed=voice_config.speed,
                exaggeration=voice_config.exaggeration,
                cfg_weight=voice_config.cfg_weight,
                language=voice_config.language,
            )
            if await self.cache.has(key):
                cached_count += 1

        coverage_percent = (cached_count / total_count * 100) if total_count > 0 else 100.0

        return {
            "total_segments": total_count,
            "cached_segments": cached_count,
            "missing_segments": total_count - cached_count,
            "coverage_percent": round(coverage_percent, 1),
        }

    async def prefetch_upcoming(
        self,
        session: UserSession,
        current_index: int,
        segments: List[str],
        lookahead: Optional[int] = None,
    ) -> None:
        """Prefetch upcoming segments based on current playback position.

        Fire-and-forget operation that runs in background.
        Uses PREFETCH priority (lower than LIVE).

        Args:
            session: User session with voice configuration
            current_index: Current segment index
            segments: All segments in the topic
            lookahead: Number of segments to prefetch (default: session's setting)
        """
        if not self.prefetcher:
            return

        lookahead = lookahead or session.prefetch_lookahead
        voice_config = session.voice_config

        await self.prefetcher.prefetch_upcoming(
            curriculum_id=session.playback_state.curriculum_id,
            current_index=current_index,
            segments=segments,
            lookahead=lookahead,
            voice_id=voice_config.voice_id,
            provider=voice_config.tts_provider,
            speed=voice_config.speed,
            chatterbox_config=voice_config.get_chatterbox_config(),
        )

    def get_session_stats(self, session_id: str) -> Optional[dict]:
        """Get cache statistics for a specific session."""
        return self._session_stats.get(session_id)

    def get_all_session_stats(self) -> dict:
        """Get cache statistics for all sessions."""
        return dict(self._session_stats)

    def clear_session_stats(self, session_id: str) -> None:
        """Clear statistics for a session (e.g., when session ends)."""
        if session_id in self._session_stats:
            del self._session_stats[session_id]

    def _record_hit(self, session_id: str) -> None:
        """Record a cache hit for a session."""
        if session_id not in self._session_stats:
            self._session_stats[session_id] = {"hits": 0, "misses": 0}
        self._session_stats[session_id]["hits"] += 1

    def _record_miss(self, session_id: str) -> None:
        """Record a cache miss for a session."""
        if session_id not in self._session_stats:
            self._session_stats[session_id] = {"hits": 0, "misses": 0}
        self._session_stats[session_id]["misses"] += 1


async def estimate_generation_time(
    segments: List[str],
    voice_config: UserVoiceConfig,
    cache: TTSCache,
    avg_generation_time_ms: float = 500.0,
) -> dict:
    """Estimate time to generate missing audio for a voice config.

    Args:
        segments: List of segment texts
        voice_config: Voice configuration
        cache: TTS cache to check
        avg_generation_time_ms: Average time per generation in milliseconds

    Returns:
        Dict with time estimates
    """
    missing_count = 0

    for text in segments:
        key = TTSCacheKey.from_request(
            text=text,
            voice_id=voice_config.voice_id,
            provider=voice_config.tts_provider,
            speed=voice_config.speed,
            exaggeration=voice_config.exaggeration,
            cfg_weight=voice_config.cfg_weight,
            language=voice_config.language,
        )
        if not await cache.has(key):
            missing_count += 1

    estimated_ms = missing_count * avg_generation_time_ms
    estimated_seconds = estimated_ms / 1000
    estimated_minutes = estimated_seconds / 60

    return {
        "missing_segments": missing_count,
        "estimated_time_ms": estimated_ms,
        "estimated_time_seconds": round(estimated_seconds, 1),
        "estimated_time_minutes": round(estimated_minutes, 2),
    }
