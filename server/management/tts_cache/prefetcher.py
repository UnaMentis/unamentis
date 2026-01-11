# Curriculum Prefetcher
# Background prefetching of TTS audio for curriculum content

import asyncio
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Dict, List, Optional, TYPE_CHECKING

from .cache import TTSCache
from .models import TTSCacheKey

if TYPE_CHECKING:
    from .resource_pool import TTSResourcePool

logger = logging.getLogger(__name__)


@dataclass
class PrefetchProgress:
    """Progress tracking for a prefetch job."""
    job_id: str
    curriculum_id: str
    topic_id: str
    total_segments: int
    completed: int = 0
    cached: int = 0       # Already in cache (skipped)
    generated: int = 0    # Newly generated
    failed: int = 0
    status: str = "pending"  # pending, in_progress, completed, cancelled, failed
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    error: Optional[str] = None

    @property
    def percent_complete(self) -> float:
        if self.total_segments == 0:
            return 100.0
        return (self.completed / self.total_segments) * 100

    def to_dict(self) -> Dict:
        return {
            "job_id": self.job_id,
            "curriculum_id": self.curriculum_id,
            "topic_id": self.topic_id,
            "total_segments": self.total_segments,
            "completed": self.completed,
            "cached": self.cached,
            "generated": self.generated,
            "failed": self.failed,
            "status": self.status,
            "percent_complete": round(self.percent_complete, 1),
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "error": self.error,
        }


class CurriculumPrefetcher:
    """Predictive caching for curriculum TTS content.

    Features:
    - Background prefetching of topic segments using resource pool
    - Cancellable prefetch tasks
    - Progress tracking
    - Priority-based generation (PREFETCH priority, doesn't starve live users)
    - Automatic cache checking before generation
    """

    def __init__(
        self,
        cache: TTSCache,
        resource_pool: "TTSResourcePool",
        delay_between_requests: float = 0.1,
    ):
        """Initialize prefetcher.

        Args:
            cache: TTS cache instance
            resource_pool: TTS resource pool for priority-based generation
            delay_between_requests: Delay between requests (rate limiting)
        """
        self.cache = cache
        self.resource_pool = resource_pool
        self.delay = delay_between_requests

        # Active jobs: job_id -> (task, progress)
        self._jobs: Dict[str, tuple[asyncio.Task, PrefetchProgress]] = {}

    async def prefetch_topic(
        self,
        curriculum_id: str,
        topic_id: str,
        segments: List[str],
        voice_id: str = "nova",
        provider: str = "vibevoice",
        speed: float = 1.0,
        chatterbox_config: Optional[dict] = None,
    ) -> str:
        """Start background prefetch for a topic.

        Args:
            curriculum_id: Curriculum identifier
            topic_id: Topic identifier
            segments: List of text segments to prefetch
            voice_id: Voice to use
            provider: TTS provider
            speed: Speech speed
            chatterbox_config: Optional Chatterbox parameters

        Returns:
            Job ID for tracking progress
        """
        job_id = f"prefetch_{uuid.uuid4().hex[:8]}"

        # Cancel existing job for this topic if any
        existing_key = f"{curriculum_id}:{topic_id}"
        for jid, (task, progress) in list(self._jobs.items()):
            if f"{progress.curriculum_id}:{progress.topic_id}" == existing_key:
                task.cancel()
                del self._jobs[jid]

        progress = PrefetchProgress(
            job_id=job_id,
            curriculum_id=curriculum_id,
            topic_id=topic_id,
            total_segments=len(segments),
        )

        task = asyncio.create_task(
            self._prefetch_segments(
                progress=progress,
                segments=segments,
                voice_id=voice_id,
                provider=provider,
                speed=speed,
                chatterbox_config=chatterbox_config,
            )
        )

        self._jobs[job_id] = (task, progress)

        logger.info(
            f"Started prefetch job {job_id} for {curriculum_id}/{topic_id} "
            f"({len(segments)} segments)"
        )

        return job_id

    async def prefetch_upcoming(
        self,
        curriculum_id: str,
        current_index: int,
        segments: List[str],
        lookahead: int = 5,
        voice_id: str = "nova",
        provider: str = "vibevoice",
        speed: float = 1.0,
        chatterbox_config: Optional[dict] = None,
    ) -> None:
        """Prefetch next N segments from current position.

        This is a fire-and-forget operation for real-time prefetching
        during playback.

        Args:
            curriculum_id: Curriculum identifier
            current_index: Current segment index
            segments: All segments in topic
            lookahead: Number of segments to prefetch ahead
            voice_id: Voice to use
            provider: TTS provider
            speed: Speech speed
            chatterbox_config: Optional Chatterbox parameters
        """
        # Get upcoming segments
        start = current_index + 1
        end = min(start + lookahead, len(segments))
        upcoming = segments[start:end]

        if not upcoming:
            return

        # Prefetch each segment (fire and forget)
        for text in upcoming:
            asyncio.create_task(
                self._prefetch_single(
                    text=text,
                    voice_id=voice_id,
                    provider=provider,
                    speed=speed,
                    chatterbox_config=chatterbox_config,
                )
            )

    async def cancel(self, job_id: str) -> bool:
        """Cancel a prefetch job.

        Returns:
            True if job was cancelled, False if not found
        """
        if job_id not in self._jobs:
            return False

        task, progress = self._jobs[job_id]
        task.cancel()
        progress.status = "cancelled"
        progress.completed_at = datetime.now()

        logger.info(f"Cancelled prefetch job {job_id}")
        return True

    def get_progress(self, job_id: str) -> Optional[Dict]:
        """Get progress for a prefetch job."""
        if job_id not in self._jobs:
            return None

        _, progress = self._jobs[job_id]
        return progress.to_dict()

    def get_all_jobs(self) -> List[Dict]:
        """Get all active and recent jobs."""
        return [p.to_dict() for _, (_, p) in self._jobs.items()]

    async def _prefetch_segments(
        self,
        progress: PrefetchProgress,
        segments: List[str],
        voice_id: str,
        provider: str,
        speed: float,
        chatterbox_config: Optional[dict],
    ) -> None:
        """Internal: Prefetch all segments for a job."""
        from .resource_pool import Priority

        progress.status = "in_progress"
        progress.started_at = datetime.now()

        try:
            for i, text in enumerate(segments):
                # Check if cancelled
                if progress.status == "cancelled":
                    break

                key = TTSCacheKey.from_request(
                    text=text,
                    voice_id=voice_id,
                    provider=provider,
                    speed=speed,
                    exaggeration=chatterbox_config.get("exaggeration") if chatterbox_config else None,
                    cfg_weight=chatterbox_config.get("cfg_weight") if chatterbox_config else None,
                    language=chatterbox_config.get("language") if chatterbox_config else None,
                )

                # Check if already cached
                if await self.cache.has(key):
                    progress.cached += 1
                    progress.completed += 1
                    continue

                # Generate using resource pool with PREFETCH priority
                try:
                    audio_data, sample_rate, duration = await self.resource_pool.generate_with_priority(
                        text=text,
                        voice_id=voice_id,
                        provider=provider,
                        speed=speed,
                        chatterbox_config=chatterbox_config,
                        priority=Priority.PREFETCH,
                    )

                    await self.cache.put(key, audio_data, sample_rate, duration)
                    self.cache._stats.record_prefetch()

                    progress.generated += 1
                    progress.completed += 1

                    # Rate limiting delay
                    if self.delay > 0:
                        await asyncio.sleep(self.delay)

                except asyncio.CancelledError:
                    progress.status = "cancelled"
                    break
                except Exception as e:
                    logger.warning(f"Prefetch failed for segment {i}: {e}")
                    progress.failed += 1
                    progress.completed += 1

            # Mark complete
            if progress.status != "cancelled":
                progress.status = "completed" if progress.failed == 0 else "completed_with_errors"

            progress.completed_at = datetime.now()

            logger.info(
                f"Prefetch job {progress.job_id} complete: "
                f"{progress.generated} generated, {progress.cached} cached, "
                f"{progress.failed} failed"
            )

        except asyncio.CancelledError:
            progress.status = "cancelled"
            progress.completed_at = datetime.now()
        except Exception as e:
            progress.status = "failed"
            progress.error = str(e)
            progress.completed_at = datetime.now()
            logger.error(f"Prefetch job {progress.job_id} failed: {e}")

    async def _prefetch_single(
        self,
        text: str,
        voice_id: str,
        provider: str,
        speed: float,
        chatterbox_config: Optional[dict],
    ) -> None:
        """Internal: Prefetch a single segment (fire and forget)."""
        from .resource_pool import Priority

        key = TTSCacheKey.from_request(
            text=text,
            voice_id=voice_id,
            provider=provider,
            speed=speed,
            exaggeration=chatterbox_config.get("exaggeration") if chatterbox_config else None,
            cfg_weight=chatterbox_config.get("cfg_weight") if chatterbox_config else None,
            language=chatterbox_config.get("language") if chatterbox_config else None,
        )

        # Skip if already cached
        if await self.cache.has(key):
            return

        try:
            audio_data, sample_rate, duration = await self.resource_pool.generate_with_priority(
                text=text,
                voice_id=voice_id,
                provider=provider,
                speed=speed,
                chatterbox_config=chatterbox_config,
                priority=Priority.PREFETCH,
            )

            await self.cache.put(key, audio_data, sample_rate, duration)
            self.cache._stats.record_prefetch()

        except Exception as e:
            logger.debug(f"Single prefetch failed: {e}")

    def cleanup_completed_jobs(self, max_age_seconds: int = 3600) -> int:
        """Remove completed jobs older than max_age.

        Returns:
            Number of jobs removed
        """
        now = datetime.now()
        removed = 0

        for job_id in list(self._jobs.keys()):
            _, progress = self._jobs[job_id]

            if progress.status in ("completed", "completed_with_errors", "cancelled", "failed"):
                if progress.completed_at:
                    age = (now - progress.completed_at).total_seconds()
                    if age > max_age_seconds:
                        del self._jobs[job_id]
                        removed += 1

        return removed
