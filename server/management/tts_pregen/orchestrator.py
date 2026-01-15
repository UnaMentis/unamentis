# TTS Pre-Generation Orchestrator
# Job execution engine with retry logic and resource pool integration

import asyncio
import logging
import os
import wave
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional, Set
from uuid import UUID

from .models import TTSPregenJob, TTSJobItem, JobStatus, ItemStatus
from .job_manager import JobManager

logger = logging.getLogger(__name__)

# Retry configuration
MAX_RETRIES = 3
RETRY_DELAYS = [5, 15, 45]  # Exponential backoff in seconds
MAX_CONSECUTIVE_FAILURES = 5  # Auto-pause after this many failures


class TTSPregenOrchestrator:
    """Executes TTS pre-generation jobs with priority queuing.

    Features:
    - Per-item processing with database persistence
    - Integration with TTSResourcePool (Priority.SCHEDULED)
    - Retry logic with exponential backoff
    - Profile resolution
    - Pause/resume support
    - Auto-pause on consecutive failures
    """

    def __init__(
        self,
        job_manager: JobManager,
        tts_resource_pool: Any,  # TTSResourcePool
    ):
        """Initialize orchestrator.

        Args:
            job_manager: Job manager for database operations
            tts_resource_pool: TTS resource pool for generation
        """
        self.job_manager = job_manager
        self.tts_pool = tts_resource_pool
        self._running_jobs: Set[UUID] = set()
        self._stop_flags: Dict[UUID, bool] = {}

    async def start_job(self, job_id: UUID) -> bool:
        """Start processing a job.

        Args:
            job_id: Job ID to start

        Returns:
            True if job was started successfully
        """
        if job_id in self._running_jobs:
            logger.warning(f"Job {job_id} is already running")
            return False

        job = await self.job_manager.get_job(job_id)
        if not job:
            logger.error(f"Job {job_id} not found")
            return False

        if job.status not in (JobStatus.PENDING, JobStatus.PAUSED):
            logger.warning(f"Cannot start job {job_id} in status {job.status}")
            return False

        # Start job
        job = await self.job_manager.start_job(job_id)
        if not job:
            return False

        self._running_jobs.add(job_id)
        self._stop_flags[job_id] = False

        # Run processing in background
        asyncio.create_task(self._process_job(job_id))

        return True

    async def stop_job(self, job_id: UUID) -> bool:
        """Stop a running job (pause or cancel).

        Args:
            job_id: Job ID to stop

        Returns:
            True if stop signal was sent
        """
        if job_id not in self._running_jobs:
            return False

        self._stop_flags[job_id] = True
        return True

    async def _process_job(self, job_id: UUID) -> None:
        """Process all items in a job.

        Args:
            job_id: Job ID to process
        """
        try:
            job = await self.job_manager.get_job(job_id)
            if not job:
                return

            # Resolve TTS configuration
            tts_config = await self.job_manager.resolve_tts_config(job)
            provider = tts_config.get("provider", "")
            voice_id = tts_config.get("voice_id", "")
            settings = tts_config.get("settings", {})

            # Ensure output directory exists
            output_dir = await self.job_manager.ensure_output_directory(job)

            logger.info(f"Processing job {job_id} with provider={provider}, voice_id={voice_id}")

            consecutive_failures = 0

            while not self._stop_flags.get(job_id, False):
                # Get next batch of pending items
                pending_items = await self.job_manager.get_pending_items(job_id, limit=10)

                if not pending_items:
                    # No more items, job is complete
                    await self.job_manager.complete_job(job_id)
                    break

                for item in pending_items:
                    if self._stop_flags.get(job_id, False):
                        break

                    # Update current item
                    job = await self.job_manager.get_job(job_id)
                    if job:
                        job.current_item_index = item.item_index
                        job.current_item_text = item.text_content[:100]  # Truncate
                        await self.job_manager.repository.update_job(job)

                    # Process item with retries
                    success = await self._process_item(
                        item=item,
                        provider=provider,
                        voice_id=voice_id,
                        settings=settings,
                        output_dir=output_dir,
                        output_format=job.output_format,
                    )

                    # Update job counters
                    job = await self.job_manager.get_job(job_id)
                    if job:
                        if success:
                            job.completed_items += 1
                            consecutive_failures = 0
                            job.consecutive_failures = 0
                        else:
                            job.failed_items += 1
                            consecutive_failures += 1
                            job.consecutive_failures = consecutive_failures

                        await self.job_manager.repository.update_job(job)

                        # Auto-pause on too many consecutive failures
                        if consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                            logger.warning(
                                f"Job {job_id} auto-paused after {consecutive_failures} consecutive failures"
                            )
                            await self.job_manager.pause_job(job_id)
                            self._stop_flags[job_id] = True
                            break

            # Handle stop
            if self._stop_flags.get(job_id, False):
                job = await self.job_manager.get_job(job_id)
                if job and job.status == JobStatus.RUNNING:
                    await self.job_manager.pause_job(job_id)

        except Exception as e:
            logger.exception(f"Error processing job {job_id}: {e}")
            await self.job_manager.fail_job(job_id, str(e))

        finally:
            self._running_jobs.discard(job_id)
            self._stop_flags.pop(job_id, None)

    async def _process_item(
        self,
        item: TTSJobItem,
        provider: str,
        voice_id: str,
        settings: Dict[str, Any],
        output_dir: Path,
        output_format: str,
    ) -> bool:
        """Process a single item with retries.

        Args:
            item: Job item to process
            provider: TTS provider name
            voice_id: Voice ID
            settings: Provider-specific settings
            output_dir: Output directory
            output_format: Output format (wav, mp3, etc.)

        Returns:
            True if item was processed successfully
        """
        # Mark as processing
        item.status = ItemStatus.PROCESSING
        item.processing_started_at = datetime.now()
        item.attempt_count += 1
        await self.job_manager.update_item(item)

        for attempt in range(MAX_RETRIES):
            try:
                # Generate audio using resource pool
                # Import Priority here to avoid circular imports
                from ..tts_cache.resource_pool import Priority

                audio_data, sample_rate, duration = await self.tts_pool.generate_with_priority(
                    text=item.text_content,
                    voice_id=voice_id,
                    provider=provider,
                    speed=settings.get("speed", 1.0),
                    chatterbox_config=settings.get("chatterbox_config"),
                    priority=Priority.SCHEDULED,
                )

                # Save to file
                filename = f"{item.item_index:05d}_{item.text_hash[:8]}.{output_format}"
                output_path = output_dir / filename

                if output_format == "wav":
                    self._save_wav(output_path, audio_data, sample_rate)
                else:
                    # For other formats, just write raw audio
                    with open(output_path, "wb") as f:
                        f.write(audio_data)

                # Update item with success
                item.status = ItemStatus.COMPLETED
                item.output_file = str(output_path)
                item.duration_seconds = duration
                item.file_size_bytes = os.path.getsize(output_path)
                item.sample_rate = sample_rate
                item.processing_completed_at = datetime.now()
                item.last_error = None
                await self.job_manager.update_item(item)

                logger.debug(f"Generated item {item.item_index}: {output_path}")
                return True

            except Exception as e:
                logger.warning(
                    f"Attempt {attempt + 1}/{MAX_RETRIES} failed for item {item.item_index}: {e}"
                )
                item.last_error = str(e)
                item.attempt_count = attempt + 1
                await self.job_manager.update_item(item)

                if attempt < MAX_RETRIES - 1:
                    # Wait before retry
                    delay = RETRY_DELAYS[min(attempt, len(RETRY_DELAYS) - 1)]
                    await asyncio.sleep(delay)

        # All retries exhausted
        item.status = ItemStatus.FAILED
        item.processing_completed_at = datetime.now()
        await self.job_manager.update_item(item)

        logger.error(f"Item {item.item_index} failed after {MAX_RETRIES} attempts")
        return False

    def _save_wav(self, path: Path, audio_data: bytes, sample_rate: int) -> None:
        """Save audio data as WAV file.

        Args:
            path: Output file path
            audio_data: Raw audio data (16-bit PCM)
            sample_rate: Sample rate in Hz
        """
        with wave.open(str(path), "wb") as wav_file:
            wav_file.setnchannels(1)  # Mono
            wav_file.setsampwidth(2)  # 16-bit
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(audio_data)

    def is_job_running(self, job_id: UUID) -> bool:
        """Check if a job is currently running.

        Args:
            job_id: Job ID to check

        Returns:
            True if job is running
        """
        return job_id in self._running_jobs

    def get_running_jobs(self) -> Set[UUID]:
        """Get set of currently running job IDs.

        Returns:
            Set of running job IDs
        """
        return self._running_jobs.copy()
