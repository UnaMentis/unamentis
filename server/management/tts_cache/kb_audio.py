# Knowledge Bowl Audio Manager
# Pre-generation and serving of TTS audio for KB questions

import asyncio
import json
import logging
import os
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from .resource_pool import TTSResourcePool

logger = logging.getLogger(__name__)


class KBSegmentType(str, Enum):
    """Types of audio segments for a KB question."""
    QUESTION = "question"
    ANSWER = "answer"
    HINT = "hint"
    EXPLANATION = "explanation"


@dataclass
class KBSegment:
    """A segment of KB content to be converted to audio."""
    question_id: str
    segment_type: KBSegmentType
    text: str
    hint_index: int = 0  # For questions with multiple hints

    @property
    def filename(self) -> str:
        """Generate filename for this segment."""
        if self.segment_type == KBSegmentType.HINT:
            return f"hint_{self.hint_index}.wav"
        return f"{self.segment_type.value}.wav"


@dataclass
class KBAudioEntry:
    """Metadata for a cached KB audio file."""
    question_id: str
    segment_type: str
    file_path: str
    size_bytes: int
    duration_seconds: float
    sample_rate: int
    created_at: datetime
    hint_index: int = 0

    def to_dict(self) -> Dict:
        return {
            "question_id": self.question_id,
            "segment_type": self.segment_type,
            "file_path": self.file_path,
            "size_bytes": self.size_bytes,
            "duration_seconds": self.duration_seconds,
            "sample_rate": self.sample_rate,
            "created_at": self.created_at.isoformat(),
            "hint_index": self.hint_index,
        }

    @classmethod
    def from_dict(cls, d: Dict) -> "KBAudioEntry":
        return cls(
            question_id=d["question_id"],
            segment_type=d["segment_type"],
            file_path=d["file_path"],
            size_bytes=d["size_bytes"],
            duration_seconds=d["duration_seconds"],
            sample_rate=d["sample_rate"],
            created_at=datetime.fromisoformat(d["created_at"]),
            hint_index=d.get("hint_index", 0),
        )


@dataclass
class KBManifest:
    """Manifest tracking all pre-generated audio for a module."""
    module_id: str
    voice_id: str
    provider: str
    generated_at: datetime
    total_questions: int = 0
    total_segments: int = 0
    total_size_bytes: int = 0
    total_duration_seconds: float = 0.0
    segments: Dict[str, Dict[str, KBAudioEntry]] = field(default_factory=dict)

    def to_dict(self) -> Dict:
        segments_dict = {}
        for qid, entries in self.segments.items():
            segments_dict[qid] = {
                seg_type: entry.to_dict()
                for seg_type, entry in entries.items()
            }

        return {
            "module_id": self.module_id,
            "voice_id": self.voice_id,
            "provider": self.provider,
            "generated_at": self.generated_at.isoformat(),
            "total_questions": self.total_questions,
            "total_segments": self.total_segments,
            "total_size_bytes": self.total_size_bytes,
            "total_duration_seconds": round(self.total_duration_seconds, 2),
            "segments": segments_dict,
        }

    @classmethod
    def from_dict(cls, d: Dict) -> "KBManifest":
        segments = {}
        for qid, entries in d.get("segments", {}).items():
            segments[qid] = {
                seg_type: KBAudioEntry.from_dict(entry)
                for seg_type, entry in entries.items()
            }

        return cls(
            module_id=d["module_id"],
            voice_id=d["voice_id"],
            provider=d["provider"],
            generated_at=datetime.fromisoformat(d["generated_at"]),
            total_questions=d.get("total_questions", 0),
            total_segments=d.get("total_segments", 0),
            total_size_bytes=d.get("total_size_bytes", 0),
            total_duration_seconds=d.get("total_duration_seconds", 0.0),
            segments=segments,
        )


@dataclass
class KBPrefetchProgress:
    """Progress tracking for KB audio pre-generation."""
    job_id: str
    module_id: str
    total_segments: int
    completed: int = 0
    cached: int = 0
    generated: int = 0
    failed: int = 0
    status: str = "pending"
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
            "module_id": self.module_id,
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


@dataclass
class KBCoverageStatus:
    """Status of audio coverage for a module."""
    module_id: str
    total_questions: int
    covered_questions: int
    total_segments: int
    covered_segments: int
    missing_segments: int
    total_size_bytes: int
    is_complete: bool

    @property
    def coverage_percent(self) -> float:
        """Calculate coverage percentage."""
        if self.total_segments == 0:
            return 0.0
        return round(self.covered_segments / self.total_segments * 100, 1)

    def to_dict(self) -> Dict:
        return {
            "module_id": self.module_id,
            "total_questions": self.total_questions,
            "covered_questions": self.covered_questions,
            "total_segments": self.total_segments,
            "covered_segments": self.covered_segments,
            "missing_segments": self.missing_segments,
            "total_size_bytes": self.total_size_bytes,
            "is_complete": self.is_complete,
            "coverage_percent": self.coverage_percent,
        }


class KBAudioManager:
    """Manages pre-generated TTS audio for Knowledge Bowl questions.

    Features:
    - Pre-generates all audio for a module's questions
    - Stores audio in organized directory structure
    - Tracks progress and provides manifest
    - Serves audio efficiently
    """

    def __init__(
        self,
        base_dir: str,
        resource_pool: "TTSResourcePool",
        delay_between_requests: float = 0.1,
    ):
        """Initialize KB Audio Manager.

        Args:
            base_dir: Base directory for KB audio storage
            resource_pool: TTS resource pool for generation
            delay_between_requests: Rate limiting delay
        """
        self.base_dir = Path(base_dir)
        self.resource_pool = resource_pool
        self.delay = delay_between_requests

        # Active jobs
        self._jobs: Dict[str, tuple[asyncio.Task, KBPrefetchProgress]] = {}

        # Cached manifests
        self._manifests: Dict[str, KBManifest] = {}

        # Lock for thread safety
        self._lock = asyncio.Lock()

    async def initialize(self) -> None:
        """Initialize storage directories and load existing manifests."""
        self.base_dir.mkdir(parents=True, exist_ok=True)

        # Create feedback directory
        feedback_dir = self.base_dir / "feedback"
        feedback_dir.mkdir(exist_ok=True)

        # Load existing manifests
        for module_dir in self.base_dir.iterdir():
            if module_dir.is_dir() and module_dir.name != "feedback":
                manifest_path = module_dir / "manifest.json"
                if manifest_path.exists():
                    try:
                        with open(manifest_path) as f:
                            data = json.load(f)
                            self._manifests[module_dir.name] = KBManifest.from_dict(data)
                            logger.info(f"Loaded manifest for module {module_dir.name}")
                    except Exception as e:
                        logger.warning(f"Failed to load manifest for {module_dir.name}: {e}")

    def extract_segments(self, module_content: Dict) -> List[KBSegment]:
        """Extract all speakable segments from KB module content.

        Args:
            module_content: KB module JSON content

        Returns:
            List of segments to generate audio for
        """
        segments = []

        for domain in module_content.get("domains", []):
            for question in domain.get("questions", []):
                qid = question["id"]

                # Question text
                if question.get("question_text"):
                    segments.append(KBSegment(
                        question_id=qid,
                        segment_type=KBSegmentType.QUESTION,
                        text=question["question_text"],
                    ))

                # Answer text
                if question.get("answer_text"):
                    segments.append(KBSegment(
                        question_id=qid,
                        segment_type=KBSegmentType.ANSWER,
                        text=question["answer_text"],
                    ))

                # Hints (may have multiple)
                for i, hint in enumerate(question.get("hints", [])):
                    segments.append(KBSegment(
                        question_id=qid,
                        segment_type=KBSegmentType.HINT,
                        text=hint,
                        hint_index=i,
                    ))

                # Explanation
                if question.get("explanation"):
                    segments.append(KBSegment(
                        question_id=qid,
                        segment_type=KBSegmentType.EXPLANATION,
                        text=question["explanation"],
                    ))

        return segments

    async def prefetch_module(
        self,
        module_id: str,
        module_content: Dict,
        voice_id: str = "nova",
        provider: str = "vibevoice",
        speed: float = 1.0,
        force_regenerate: bool = False,
    ) -> str:
        """Start pre-generation of all audio for a module.

        Args:
            module_id: Module identifier
            module_content: Full module JSON content
            voice_id: Voice to use for TTS
            provider: TTS provider
            speed: Speech speed
            force_regenerate: If True, regenerate even if already cached

        Returns:
            Job ID for tracking progress
        """
        job_id = f"kb_prefetch_{uuid.uuid4().hex[:8]}"

        # Cancel existing job for this module
        async with self._lock:
            for jid, (task, progress) in list(self._jobs.items()):
                if progress.module_id == module_id:
                    task.cancel()
                    del self._jobs[jid]
                    logger.info(f"Cancelled existing job {jid} for module {module_id}")

        # Extract segments
        segments = self.extract_segments(module_content)

        if not segments:
            logger.warning(f"No segments found in module {module_id}")
            return job_id

        progress = KBPrefetchProgress(
            job_id=job_id,
            module_id=module_id,
            total_segments=len(segments),
        )

        task = asyncio.create_task(
            self._generate_module_audio(
                progress=progress,
                segments=segments,
                voice_id=voice_id,
                provider=provider,
                speed=speed,
                force_regenerate=force_regenerate,
            )
        )

        async with self._lock:
            self._jobs[job_id] = (task, progress)

        logger.info(
            f"Started KB prefetch job {job_id} for {module_id} "
            f"({len(segments)} segments)"
        )

        return job_id

    async def _generate_module_audio(
        self,
        progress: KBPrefetchProgress,
        segments: List[KBSegment],
        voice_id: str,
        provider: str,
        speed: float,
        force_regenerate: bool,
    ) -> None:
        """Internal: Generate audio for all segments."""
        from .resource_pool import Priority

        progress.status = "in_progress"
        progress.started_at = datetime.now()

        # Create module directory
        module_dir = self.base_dir / progress.module_id
        module_dir.mkdir(parents=True, exist_ok=True)

        # Initialize manifest
        manifest = KBManifest(
            module_id=progress.module_id,
            voice_id=voice_id,
            provider=provider,
            generated_at=datetime.now(),
        )

        question_ids = set()

        try:
            for segment in segments:
                if progress.status == "cancelled":
                    break

                question_ids.add(segment.question_id)

                # Create question directory
                question_dir = module_dir / segment.question_id
                question_dir.mkdir(exist_ok=True)

                # Check if already exists
                file_path = question_dir / segment.filename
                if file_path.exists() and not force_regenerate:
                    progress.cached += 1
                    progress.completed += 1

                    # Add to manifest from existing file
                    entry = KBAudioEntry(
                        question_id=segment.question_id,
                        segment_type=segment.segment_type.value,
                        file_path=str(file_path),
                        size_bytes=file_path.stat().st_size,
                        duration_seconds=self._estimate_duration(file_path.stat().st_size),
                        sample_rate=24000,
                        created_at=datetime.fromtimestamp(file_path.stat().st_mtime),
                        hint_index=segment.hint_index,
                    )
                    self._add_to_manifest(manifest, entry)
                    continue

                # Generate audio
                try:
                    audio_data, sample_rate, duration = await self.resource_pool.generate_with_priority(
                        text=segment.text,
                        voice_id=voice_id,
                        provider=provider,
                        speed=speed,
                        chatterbox_config=None,
                        priority=Priority.SCHEDULED,
                    )

                    # Save audio file
                    with open(file_path, "wb") as f:
                        f.write(audio_data)

                    entry = KBAudioEntry(
                        question_id=segment.question_id,
                        segment_type=segment.segment_type.value,
                        file_path=str(file_path),
                        size_bytes=len(audio_data),
                        duration_seconds=duration,
                        sample_rate=sample_rate,
                        created_at=datetime.now(),
                        hint_index=segment.hint_index,
                    )
                    self._add_to_manifest(manifest, entry)

                    progress.generated += 1
                    progress.completed += 1

                    # Rate limiting
                    if self.delay > 0:
                        await asyncio.sleep(self.delay)

                except asyncio.CancelledError:
                    progress.status = "cancelled"
                    break
                except Exception as e:
                    logger.warning(f"Failed to generate {segment.question_id}/{segment.segment_type}: {e}")
                    progress.failed += 1
                    progress.completed += 1

            # Update manifest totals
            manifest.total_questions = len(question_ids)
            manifest.total_segments = progress.completed

            # Save manifest
            if progress.status != "cancelled":
                manifest_path = module_dir / "manifest.json"
                with open(manifest_path, "w") as f:
                    json.dump(manifest.to_dict(), f, indent=2)

                async with self._lock:
                    self._manifests[progress.module_id] = manifest

            # Update status
            if progress.status != "cancelled":
                progress.status = "completed" if progress.failed == 0 else "completed_with_errors"

            progress.completed_at = datetime.now()

            logger.info(
                f"KB prefetch job {progress.job_id} complete: "
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
            logger.error(f"KB prefetch job {progress.job_id} failed: {e}")

    def _add_to_manifest(self, manifest: KBManifest, entry: KBAudioEntry) -> None:
        """Add an entry to the manifest."""
        qid = entry.question_id

        if qid not in manifest.segments:
            manifest.segments[qid] = {}

        # Use hint index for hint segments
        if entry.segment_type == KBSegmentType.HINT.value:
            key = f"hint_{entry.hint_index}"
        else:
            key = entry.segment_type

        manifest.segments[qid][key] = entry
        manifest.total_size_bytes += entry.size_bytes
        manifest.total_duration_seconds += entry.duration_seconds

    def _estimate_duration(self, size_bytes: int, sample_rate: int = 24000) -> float:
        """Estimate audio duration from file size (WAV format)."""
        # WAV: 44 byte header + 2 bytes per sample (16-bit mono)
        data_bytes = max(0, size_bytes - 44)
        samples = data_bytes // 2
        return samples / sample_rate

    async def get_audio(
        self,
        module_id: str,
        question_id: str,
        segment_type: str,
        hint_index: int = 0,
    ) -> Optional[bytes]:
        """Get pre-generated audio for a question segment.

        Args:
            module_id: Module identifier
            question_id: Question identifier
            segment_type: Type of segment (question, answer, hint, explanation)
            hint_index: Index for hint segments

        Returns:
            Audio bytes if found, None otherwise
        """
        if segment_type == "hint":
            filename = f"hint_{hint_index}.wav"
        else:
            filename = f"{segment_type}.wav"

        file_path = self.base_dir / module_id / question_id / filename

        if not file_path.exists():
            return None

        try:
            with open(file_path, "rb") as f:
                return f.read()
        except Exception as e:
            logger.error(f"Failed to read audio file {file_path}: {e}")
            return None

    async def get_manifest(self, module_id: str) -> Optional[KBManifest]:
        """Get manifest for a module."""
        async with self._lock:
            return self._manifests.get(module_id)

    def get_coverage_status(self, module_id: str, module_content: Dict) -> KBCoverageStatus:
        """Check how much of a module has pre-generated audio.

        Args:
            module_id: Module identifier
            module_content: Full module content to compare against

        Returns:
            Coverage status
        """
        segments = self.extract_segments(module_content)
        total_segments = len(segments)
        total_questions = len(set(s.question_id for s in segments))

        covered_segments = 0
        covered_questions = set()
        total_size = 0

        module_dir = self.base_dir / module_id

        for segment in segments:
            file_path = module_dir / segment.question_id / segment.filename
            if file_path.exists():
                covered_segments += 1
                covered_questions.add(segment.question_id)
                total_size += file_path.stat().st_size

        return KBCoverageStatus(
            module_id=module_id,
            total_questions=total_questions,
            covered_questions=len(covered_questions),
            total_segments=total_segments,
            covered_segments=covered_segments,
            missing_segments=total_segments - covered_segments,
            total_size_bytes=total_size,
            is_complete=covered_segments == total_segments,
        )

    def get_progress(self, job_id: str) -> Optional[Dict]:
        """Get progress for a prefetch job."""
        if job_id not in self._jobs:
            return None
        _, progress = self._jobs[job_id]
        return progress.to_dict()

    def get_all_jobs(self) -> List[Dict]:
        """Get all active and recent jobs."""
        return [p.to_dict() for _, (_, p) in self._jobs.items()]

    async def cancel(self, job_id: str) -> bool:
        """Cancel a prefetch job."""
        if job_id not in self._jobs:
            return False

        task, progress = self._jobs[job_id]
        task.cancel()
        progress.status = "cancelled"
        progress.completed_at = datetime.now()

        logger.info(f"Cancelled KB prefetch job {job_id}")
        return True

    async def generate_feedback_audio(
        self,
        voice_id: str = "nova",
        provider: str = "vibevoice",
        speed: float = 1.0,
    ) -> None:
        """Generate static feedback phrases (Correct!, Incorrect, etc.)."""
        from .resource_pool import Priority

        feedback_dir = self.base_dir / "feedback"
        feedback_dir.mkdir(exist_ok=True)

        phrases = [
            ("correct", "Correct!"),
            ("incorrect", "Incorrect."),
        ]

        for filename, text in phrases:
            file_path = feedback_dir / f"{filename}.wav"
            if file_path.exists():
                continue

            try:
                audio_data, _, _ = await self.resource_pool.generate_with_priority(
                    text=text,
                    voice_id=voice_id,
                    provider=provider,
                    speed=speed,
                    chatterbox_config=None,
                    priority=Priority.SCHEDULED,
                )

                with open(file_path, "wb") as f:
                    f.write(audio_data)

                logger.info(f"Generated feedback audio: {filename}")

            except Exception as e:
                logger.warning(f"Failed to generate feedback audio {filename}: {e}")

    async def get_feedback_audio(self, feedback_type: str) -> Optional[bytes]:
        """Get feedback audio (correct/incorrect)."""
        file_path = self.base_dir / "feedback" / f"{feedback_type}.wav"

        if not file_path.exists():
            return None

        try:
            with open(file_path, "rb") as f:
                return f.read()
        except Exception as e:
            logger.error(f"Failed to read feedback audio {feedback_type}: {e}")
            return None

    def cleanup_completed_jobs(self, max_age_seconds: int = 3600) -> int:
        """Remove completed jobs older than max_age."""
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
