# TTS Pre-Generation Job Manager
# CRUD operations and lifecycle management for batch TTS jobs

import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
from uuid import UUID

from .models import (
    TTSPregenJob,
    TTSJobItem,
    TTSProfile,
    JobStatus,
    ItemStatus,
)
from .repository import TTSPregenRepository

logger = logging.getLogger(__name__)

# Default output directory for pre-generated audio
DEFAULT_OUTPUT_DIR = "data/tts-pregenerated"


class JobManager:
    """Manages TTS pre-generation batch jobs.

    Handles job creation, lifecycle management, progress tracking,
    and profile resolution.
    """

    def __init__(self, repository: TTSPregenRepository, base_output_dir: str = DEFAULT_OUTPUT_DIR):
        """Initialize job manager.

        Args:
            repository: TTS pregen repository for database operations
            base_output_dir: Base directory for job output files
        """
        self.repository = repository
        self.base_output_dir = base_output_dir

    async def create_job(
        self,
        name: str,
        source_type: str,
        items: List[Dict[str, str]],
        profile_id: Optional[UUID] = None,
        tts_config: Optional[Dict[str, Any]] = None,
        source_id: Optional[str] = None,
        output_format: str = "wav",
        normalize_volume: bool = False,
        job_type: str = "batch",
    ) -> TTSPregenJob:
        """Create a new TTS pre-generation job.

        Args:
            name: Job name
            source_type: Source type ('knowledge-bowl', 'curriculum', 'custom')
            items: List of items, each with 'text' and optional 'source_ref'
            profile_id: Optional TTS profile ID
            tts_config: Optional inline TTS configuration
            source_id: Optional source identifier
            output_format: Output audio format (default 'wav')
            normalize_volume: Whether to normalize volume
            job_type: Job type ('batch' or 'comparison')

        Returns:
            Created job

        Raises:
            ValueError: If neither profile_id nor tts_config is provided
            ValueError: If items list is empty
        """
        if not profile_id and not tts_config:
            raise ValueError("Either profile_id or tts_config must be provided")

        if not items:
            raise ValueError("At least one item is required")

        # Create output directory for this job
        import uuid
        job_id = uuid.uuid4()
        output_dir = os.path.join(self.base_output_dir, "jobs", str(job_id), "audio")

        job = TTSPregenJob(
            id=job_id,
            name=name,
            job_type=job_type,
            status=JobStatus.PENDING,
            source_type=source_type,
            source_id=source_id,
            profile_id=profile_id,
            tts_config=tts_config,
            output_format=output_format,
            normalize_volume=normalize_volume,
            output_dir=output_dir,
            total_items=len(items),
            completed_items=0,
            failed_items=0,
            current_item_index=0,
        )

        # Create job in database
        job = await self.repository.create_job(job)

        # Create job items
        job_items = []
        for idx, item in enumerate(items):
            text = item.get("text", "")
            source_ref = item.get("source_ref")

            job_item = TTSJobItem(
                id=uuid.uuid4(),
                job_id=job.id,
                item_index=idx,
                text_content=text,
                text_hash=TTSJobItem.hash_text(text),
                source_ref=source_ref,
                status=ItemStatus.PENDING,
            )
            job_items.append(job_item)

        if job_items:
            await self.repository.create_job_items(job_items)

        logger.info(f"Created job {job.id} with {len(job_items)} items")
        return job

    async def get_job(self, job_id: UUID) -> Optional[TTSPregenJob]:
        """Get a job by ID.

        Args:
            job_id: Job ID

        Returns:
            Job if found, None otherwise
        """
        return await self.repository.get_job(job_id)

    async def list_jobs(
        self,
        status: Optional[JobStatus] = None,
        job_type: Optional[str] = None,
        source_type: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[TTSPregenJob]:
        """List jobs with optional filtering.

        Args:
            status: Optional status filter
            job_type: Optional job type filter
            source_type: Optional source type filter
            limit: Maximum number of jobs to return
            offset: Number of jobs to skip

        Returns:
            List of matching jobs
        """
        return await self.repository.list_jobs(
            status=status,
            job_type=job_type,
            source_type=source_type,
            limit=limit,
            offset=offset,
        )

    async def delete_job(self, job_id: UUID) -> bool:
        """Delete a job and all its items.

        Jobs that are currently running will be cancelled first.

        Args:
            job_id: Job ID

        Returns:
            True if job was deleted
        """
        job = await self.repository.get_job(job_id)
        if not job:
            return False

        # Cancel if running
        if job.status == JobStatus.RUNNING:
            await self.cancel_job(job_id)

        # Delete from database (cascades to items)
        await self.repository.delete_job(job_id)

        # Clean up files
        if job.output_dir and os.path.exists(job.output_dir):
            import shutil
            try:
                shutil.rmtree(job.output_dir)
            except Exception as e:
                logger.warning(f"Failed to clean up job directory: {e}")

        logger.info(f"Deleted job {job_id}")
        return True

    async def start_job(self, job_id: UUID) -> Optional[TTSPregenJob]:
        """Start a pending job.

        Args:
            job_id: Job ID

        Returns:
            Updated job if started, None if not found or invalid state
        """
        job = await self.repository.get_job(job_id)
        if not job:
            return None

        if job.status != JobStatus.PENDING:
            logger.warning(f"Cannot start job {job_id} in status {job.status}")
            return job

        job = await self.repository.update_job_status(
            job_id=job_id,
            status=JobStatus.RUNNING,
            started_at=datetime.now(),
        )

        logger.info(f"Started job {job_id}")
        return job

    async def pause_job(self, job_id: UUID) -> Optional[TTSPregenJob]:
        """Pause a running job.

        Args:
            job_id: Job ID

        Returns:
            Updated job if paused, None if not found or invalid state
        """
        job = await self.repository.get_job(job_id)
        if not job:
            return None

        if job.status != JobStatus.RUNNING:
            logger.warning(f"Cannot pause job {job_id} in status {job.status}")
            return job

        job = await self.repository.update_job_status(
            job_id=job_id,
            status=JobStatus.PAUSED,
            paused_at=datetime.now(),
        )

        logger.info(f"Paused job {job_id}")
        return job

    async def resume_job(self, job_id: UUID) -> Optional[TTSPregenJob]:
        """Resume a paused job.

        Args:
            job_id: Job ID

        Returns:
            Updated job if resumed, None if not found or invalid state
        """
        job = await self.repository.get_job(job_id)
        if not job:
            return None

        if job.status != JobStatus.PAUSED:
            logger.warning(f"Cannot resume job {job_id} in status {job.status}")
            return job

        job = await self.repository.update_job_status(
            job_id=job_id,
            status=JobStatus.RUNNING,
            paused_at=None,  # Clear paused timestamp
        )

        logger.info(f"Resumed job {job_id}")
        return job

    async def cancel_job(self, job_id: UUID) -> Optional[TTSPregenJob]:
        """Cancel a running or paused job.

        Args:
            job_id: Job ID

        Returns:
            Updated job if cancelled, None if not found or invalid state
        """
        job = await self.repository.get_job(job_id)
        if not job:
            return None

        if job.status not in (JobStatus.PENDING, JobStatus.RUNNING, JobStatus.PAUSED):
            logger.warning(f"Cannot cancel job {job_id} in status {job.status}")
            return job

        job = await self.repository.update_job_status(
            job_id=job_id,
            status=JobStatus.CANCELLED,
        )

        logger.info(f"Cancelled job {job_id}")
        return job

    async def complete_job(self, job_id: UUID) -> Optional[TTSPregenJob]:
        """Mark a job as completed.

        Args:
            job_id: Job ID

        Returns:
            Updated job if completed
        """
        job = await self.repository.update_job_status(
            job_id=job_id,
            status=JobStatus.COMPLETED,
            completed_at=datetime.now(),
        )

        logger.info(f"Completed job {job_id}")
        return job

    async def fail_job(self, job_id: UUID, error: str) -> Optional[TTSPregenJob]:
        """Mark a job as failed.

        Args:
            job_id: Job ID
            error: Error message

        Returns:
            Updated job if failed
        """
        job = await self.repository.update_job_status(
            job_id=job_id,
            status=JobStatus.FAILED,
            last_error=error,
        )

        logger.info(f"Failed job {job_id}: {error}")
        return job

    async def get_job_items(
        self,
        job_id: UUID,
        status: Optional[ItemStatus] = None,
        limit: int = 100,
        offset: int = 0,
    ) -> List[TTSJobItem]:
        """Get items for a job.

        Args:
            job_id: Job ID
            status: Optional status filter
            limit: Maximum number of items
            offset: Number of items to skip

        Returns:
            List of job items
        """
        return await self.repository.get_job_items(
            job_id=job_id,
            status=status,
            limit=limit,
            offset=offset,
        )

    async def get_pending_items(self, job_id: UUID, limit: int = 100) -> List[TTSJobItem]:
        """Get pending items for a job, ordered by index.

        Args:
            job_id: Job ID
            limit: Maximum number of items to return

        Returns:
            List of pending items
        """
        return await self.repository.get_pending_items(job_id, limit)

    async def retry_failed_items(self, job_id: UUID) -> int:
        """Reset failed items to pending so they can be retried.

        Args:
            job_id: Job ID

        Returns:
            Number of items reset
        """
        job = await self.repository.get_job(job_id)
        if not job:
            return 0

        count = await self.repository.reset_failed_items(job_id)

        # Update job counters if items were reset
        if count > 0:
            job.failed_items -= count
            await self.repository.update_job(job)

        logger.info(f"Reset {count} failed items in job {job_id}")
        return count

    async def update_item(self, item: TTSJobItem) -> TTSJobItem:
        """Update a job item.

        Args:
            item: Item to update

        Returns:
            Updated item
        """
        return await self.repository.update_job_item(item)

    async def get_job_progress(self, job_id: UUID) -> Dict[str, Any]:
        """Get progress information for a job.

        Args:
            job_id: Job ID

        Returns:
            Progress dict with counts and percentages
        """
        job = await self.repository.get_job(job_id)
        if not job:
            return {}

        return {
            "job_id": str(job_id),
            "status": job.status.value,
            "total_items": job.total_items,
            "completed_items": job.completed_items,
            "failed_items": job.failed_items,
            "pending_items": job.pending_items,
            "percent_complete": job.percent_complete,
            "current_item_index": job.current_item_index,
            "current_item_text": job.current_item_text,
            "started_at": job.started_at.isoformat() if job.started_at else None,
            "estimated_remaining": self._estimate_remaining_time(job),
        }

    def _estimate_remaining_time(self, job: TTSPregenJob) -> Optional[float]:
        """Estimate remaining time in seconds based on current progress.

        Args:
            job: The job to estimate

        Returns:
            Estimated seconds remaining, or None if can't estimate
        """
        if not job.started_at or job.completed_items == 0:
            return None

        elapsed = (datetime.now() - job.started_at).total_seconds()
        items_per_second = job.completed_items / elapsed
        remaining_items = job.pending_items

        if items_per_second > 0:
            return remaining_items / items_per_second
        return None

    async def resolve_tts_config(self, job: TTSPregenJob) -> Dict[str, Any]:
        """Resolve TTS configuration from profile or inline config.

        If job has a profile_id, looks up the profile settings.
        Otherwise uses the inline tts_config.

        Args:
            job: The job to resolve config for

        Returns:
            TTS configuration dict with provider, voice_id, settings
        """
        if job.profile_id:
            profile = await self.repository.get_profile(job.profile_id)
            if profile:
                return {
                    "provider": profile.provider,
                    "voice_id": profile.voice_id,
                    "settings": profile.settings,
                }
            else:
                logger.warning(f"Profile {job.profile_id} not found, using tts_config")

        if job.tts_config:
            return job.tts_config

        raise ValueError(f"Job {job.id} has no valid TTS configuration")

    async def ensure_output_directory(self, job: TTSPregenJob) -> Path:
        """Ensure the output directory exists for a job.

        Args:
            job: The job

        Returns:
            Path to the output directory
        """
        output_path = Path(job.output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        return output_path
