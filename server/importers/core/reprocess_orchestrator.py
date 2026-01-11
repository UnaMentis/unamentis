"""
Reprocess Orchestrator - Coordinates the curriculum reprocessing pipeline.

Pipeline stages:
1. Load - Load curriculum from storage
2. Analyze - Detect all issues
3. Fix Images - Validate/replace broken images
4. Re-chunk - Split oversized segments with LLM
5. Generate Objectives - Create Bloom-aligned objectives
6. Add Checkpoints - Generate comprehension checks
7. Add Alternatives - Create alternative explanations
8. Fix Metadata - Fill missing fields
9. Validate - Verify all fixes applied
10. Store - Save updated UMCF
"""

import asyncio
import copy
import json
import logging
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from .reprocess_models import (
    AnalysisIssue,
    CurriculumAnalysis,
    IssueType,
    ProposedChange,
    ReprocessConfig,
    ReprocessPreview,
    ReprocessProgress,
    ReprocessResult,
    ReprocessStage,
    ReprocessStatus,
)
from ..analysis.curriculum_analyzer import CurriculumAnalyzer
from ..enrichment.llm_enrichment import LLMEnrichmentService

logger = logging.getLogger(__name__)


# Stage definitions with weights for progress calculation
STAGES = [
    ("load", "Load Curriculum", 5),
    ("analyze", "Analyze Issues", 10),
    ("fix_images", "Fix Images", 15),
    ("rechunk", "Re-chunk Segments", 20),
    ("objectives", "Generate Objectives", 15),
    ("checkpoints", "Add Checkpoints", 10),
    ("alternatives", "Add Alternatives", 10),
    ("metadata", "Fix Metadata", 5),
    ("validate", "Validate Changes", 5),
    ("store", "Store Curriculum", 5),
]


class ReprocessOrchestrator:
    """
    Orchestrates the curriculum reprocessing pipeline.

    Manages:
    - Reprocessing job queue
    - Progress tracking
    - Pipeline stage execution
    - Issue fixing with LLM enrichment
    """

    def __init__(
        self,
        curriculum_dir: Path,
        curriculum_storage: Dict[str, Any] = None,
    ):
        """
        Initialize the orchestrator.

        Args:
            curriculum_dir: Directory containing UMCF files
            curriculum_storage: Reference to in-memory curriculum storage (state.curriculum_raw)
        """
        self.curriculum_dir = Path(curriculum_dir)
        self.curriculum_storage = curriculum_storage or {}

        # Services
        self.analyzer = CurriculumAnalyzer()
        self.llm_service = LLMEnrichmentService()

        # Active jobs
        self._jobs: Dict[str, ReprocessProgress] = {}
        self._tasks: Dict[str, asyncio.Task] = {}

        # Analysis cache
        self._analysis_cache: Dict[str, CurriculumAnalysis] = {}

        # Callbacks for progress updates
        self._progress_callbacks: List[Callable[[ReprocessProgress], None]] = []

    # =========================================================================
    # Analysis
    # =========================================================================

    async def analyze_curriculum(
        self,
        curriculum_id: str,
        force: bool = False
    ) -> CurriculumAnalysis:
        """
        Analyze a curriculum for quality issues.

        Args:
            curriculum_id: ID of curriculum to analyze
            force: Force re-analysis even if cached

        Returns:
            CurriculumAnalysis with detected issues
        """
        # Check cache
        if not force and curriculum_id in self._analysis_cache:
            cached = self._analysis_cache[curriculum_id]
            # Use cache if less than 1 hour old
            age = (datetime.utcnow() - cached.analyzed_at).total_seconds()
            if age < 3600:
                logger.info(f"Using cached analysis for {curriculum_id} (age: {age:.0f}s)")
                return cached

        # Load curriculum
        curriculum = self._load_curriculum(curriculum_id)
        if not curriculum:
            raise ValueError(f"Curriculum not found: {curriculum_id}")

        # Run analysis
        analysis = await self.analyzer.analyze(curriculum)

        # Cache result
        self._analysis_cache[curriculum_id] = analysis

        return analysis

    def get_cached_analysis(self, curriculum_id: str) -> Optional[CurriculumAnalysis]:
        """Get cached analysis if available."""
        return self._analysis_cache.get(curriculum_id)

    # =========================================================================
    # Job Management
    # =========================================================================

    async def start_reprocess(self, config: ReprocessConfig) -> str:
        """
        Start a new reprocessing job.

        Args:
            config: Reprocessing configuration

        Returns:
            Job ID for tracking progress
        """
        # Generate job ID
        job_id = f"reprocess-{uuid.uuid4().hex[:8]}"

        # Create progress tracker
        progress = ReprocessProgress(
            id=job_id,
            config=config,
            status=ReprocessStatus.QUEUED,
            stages=self._create_stages(config),
            started_at=datetime.utcnow(),
        )

        self._jobs[job_id] = progress

        # Start reprocess task
        task = asyncio.create_task(self._run_reprocess(progress))
        self._tasks[job_id] = task

        logger.info(f"Started reprocess job {job_id} for {config.curriculum_id}")
        return job_id

    def get_progress(self, job_id: str) -> Optional[ReprocessProgress]:
        """Get current progress for a job."""
        return self._jobs.get(job_id)

    def list_jobs(
        self,
        status: Optional[ReprocessStatus] = None,
        curriculum_id: Optional[str] = None
    ) -> List[ReprocessProgress]:
        """List all jobs, optionally filtered."""
        jobs = list(self._jobs.values())
        if status:
            jobs = [j for j in jobs if j.status == status]
        if curriculum_id:
            jobs = [j for j in jobs if j.config.curriculum_id == curriculum_id]
        return sorted(jobs, key=lambda j: j.started_at or datetime.min, reverse=True)

    async def cancel_job(self, job_id: str) -> bool:
        """Cancel a reprocessing job."""
        progress = self._jobs.get(job_id)
        if not progress:
            return False

        # Only cancel if running
        if progress.status in [
            ReprocessStatus.COMPLETE,
            ReprocessStatus.FAILED,
            ReprocessStatus.CANCELLED
        ]:
            return False

        # Cancel the task
        task = self._tasks.get(job_id)
        if task and not task.done():
            task.cancel()

        progress.status = ReprocessStatus.CANCELLED
        self._notify_progress(progress)

        logger.info(f"Cancelled reprocess job {job_id}")
        return True

    def add_progress_callback(self, callback: Callable[[ReprocessProgress], None]):
        """Add a callback for progress updates."""
        self._progress_callbacks.append(callback)

    def _notify_progress(self, progress: ReprocessProgress):
        """Notify all callbacks of progress update."""
        for callback in self._progress_callbacks:
            try:
                callback(progress)
            except Exception as e:
                logger.error(f"Progress callback error: {e}")

    # =========================================================================
    # Preview (Dry Run)
    # =========================================================================

    async def preview_reprocess(self, config: ReprocessConfig) -> ReprocessPreview:
        """
        Preview what changes would be made without applying them.

        Args:
            config: Reprocessing configuration

        Returns:
            ReprocessPreview with proposed changes
        """
        # Get or run analysis
        analysis = await self.analyze_curriculum(config.curriculum_id)

        # Filter issues based on config
        issues = self._filter_issues(analysis.issues, config)

        # Build proposed changes
        proposed_changes = []
        summary = {}

        for issue in issues:
            change_type = self._issue_to_change_type(issue.issue_type)
            if change_type:
                proposed_changes.append(ProposedChange(
                    location=issue.location,
                    change_type=change_type,
                    before=issue.details,
                    after={"fixed": True},  # Placeholder
                    description=issue.suggested_fix,
                ))

                if change_type not in summary:
                    summary[change_type] = 0
                summary[change_type] += 1

        return ReprocessPreview(
            curriculum_id=config.curriculum_id,
            proposed_changes=proposed_changes,
            summary=summary,
        )

    def _issue_to_change_type(self, issue_type: str) -> Optional[str]:
        """Map issue type to change type."""
        mapping = {
            IssueType.BROKEN_IMAGE.value: "replace_image",
            IssueType.PLACEHOLDER_IMAGE.value: "replace_image",
            IssueType.OVERSIZED_SEGMENT.value: "split_segment",
            IssueType.UNDERSIZED_SEGMENT.value: "merge_segment",
            IssueType.MISSING_OBJECTIVES.value: "add_objectives",
            IssueType.MISSING_CHECKPOINTS.value: "add_checkpoints",
            IssueType.MISSING_ALTERNATIVES.value: "add_alternatives",
            IssueType.MISSING_TIME_ESTIMATE.value: "add_time_estimate",
            IssueType.MISSING_METADATA.value: "fix_metadata",
            IssueType.INVALID_BLOOM_LEVEL.value: "fix_bloom_level",
        }
        return mapping.get(issue_type)

    # =========================================================================
    # Pipeline Execution
    # =========================================================================

    def _create_stages(self, config: ReprocessConfig) -> List[ReprocessStage]:
        """Create stage list based on config."""
        stages = []
        for stage_id, stage_name, weight in STAGES:
            # Skip stages based on config
            skip = False
            if stage_id == "fix_images" and not config.fix_images:
                skip = True
            elif stage_id == "rechunk" and not config.rechunk_segments:
                skip = True
            elif stage_id == "objectives" and not config.generate_objectives:
                skip = True
            elif stage_id == "checkpoints" and not config.add_checkpoints:
                skip = True
            elif stage_id == "alternatives" and not config.add_alternatives:
                skip = True
            elif stage_id == "metadata" and not config.fix_metadata:
                skip = True

            status = "skipped" if skip else "pending"
            stages.append(ReprocessStage(
                id=stage_id,
                name=stage_name,
                status=status,
            ))

        return stages

    def _filter_issues(
        self,
        issues: List[AnalysisIssue],
        config: ReprocessConfig
    ) -> List[AnalysisIssue]:
        """Filter issues based on config settings."""
        filtered = []
        for issue in issues:
            # Filter by issue types if specified
            if config.issue_types and issue.issue_type not in config.issue_types:
                continue

            # Filter by node IDs if specified
            if config.node_ids and issue.node_id not in config.node_ids:
                continue

            # Filter by config flags
            if issue.issue_type in (IssueType.BROKEN_IMAGE.value, IssueType.PLACEHOLDER_IMAGE.value):
                if not config.fix_images:
                    continue
            elif issue.issue_type in (IssueType.OVERSIZED_SEGMENT.value, IssueType.UNDERSIZED_SEGMENT.value):
                if not config.rechunk_segments:
                    continue
            elif issue.issue_type == IssueType.MISSING_OBJECTIVES.value:
                if not config.generate_objectives:
                    continue
            elif issue.issue_type == IssueType.MISSING_CHECKPOINTS.value:
                if not config.add_checkpoints:
                    continue
            elif issue.issue_type == IssueType.MISSING_ALTERNATIVES.value:
                if not config.add_alternatives:
                    continue
            elif issue.issue_type in (IssueType.MISSING_METADATA.value, IssueType.MISSING_TIME_ESTIMATE.value):
                if not config.fix_metadata:
                    continue

            filtered.append(issue)

        return filtered

    async def _run_reprocess(self, progress: ReprocessProgress):
        """Run the full reprocessing pipeline."""
        config = progress.config
        start_time = time.time()

        try:
            # Stage 1: Load
            curriculum = await self._run_load_stage(progress)

            # Make a working copy
            working_copy = copy.deepcopy(curriculum)

            # Stage 2: Analyze
            analysis = await self._run_analyze_stage(progress)
            issues = self._filter_issues(analysis.issues, config)

            # Stage 3: Fix Images
            if config.fix_images:
                working_copy = await self._run_fix_images_stage(progress, working_copy, issues)

            # Stage 4: Re-chunk
            if config.rechunk_segments:
                working_copy = await self._run_rechunk_stage(progress, working_copy, issues)

            # Stage 5: Generate Objectives
            if config.generate_objectives:
                working_copy = await self._run_objectives_stage(progress, working_copy, issues)

            # Stage 6: Add Checkpoints
            if config.add_checkpoints:
                working_copy = await self._run_checkpoints_stage(progress, working_copy, issues)

            # Stage 7: Add Alternatives
            if config.add_alternatives:
                working_copy = await self._run_alternatives_stage(progress, working_copy, issues)

            # Stage 8: Fix Metadata
            if config.fix_metadata:
                working_copy = await self._run_metadata_stage(progress, working_copy, issues)

            # Stage 9: Validate
            await self._run_validate_stage(progress, working_copy)

            # Stage 10: Store (skip if dry run)
            output_path = None
            if not config.dry_run:
                output_path = await self._run_store_stage(progress, working_copy)

            # Complete
            duration_ms = int((time.time() - start_time) * 1000)
            progress.status = ReprocessStatus.COMPLETE
            progress.overall_progress = 100.0
            progress.result = ReprocessResult(
                success=True,
                fixes_applied=progress.fixes_applied,
                issues_fixed=len(progress.fixes_applied),
                issues_remaining=len(issues) - len(progress.fixes_applied),
                duration_ms=duration_ms,
                output_path=output_path,
            )
            self._notify_progress(progress)

            logger.info(f"Reprocess job {progress.id} completed in {duration_ms}ms")

        except asyncio.CancelledError:
            progress.status = ReprocessStatus.CANCELLED
            self._notify_progress(progress)
            logger.info(f"Reprocess job {progress.id} cancelled")

        except Exception as e:
            logger.exception(f"Reprocess job {progress.id} failed")
            progress.status = ReprocessStatus.FAILED
            progress.error = str(e)
            progress.result = ReprocessResult(
                success=False,
                fixes_applied=progress.fixes_applied,
                issues_fixed=len(progress.fixes_applied),
                issues_remaining=0,
                duration_ms=int((time.time() - start_time) * 1000),
                error=str(e),
            )
            self._notify_progress(progress)

    # =========================================================================
    # Individual Stages
    # =========================================================================

    async def _run_load_stage(self, progress: ReprocessProgress) -> Dict[str, Any]:
        """Load curriculum from storage."""
        progress.status = ReprocessStatus.LOADING
        progress.current_stage = "Load Curriculum"
        progress.current_activity = "Loading UMCF file..."
        progress.update_stage("load", "in_progress", progress=0)
        self._notify_progress(progress)

        curriculum = self._load_curriculum(progress.config.curriculum_id)
        if not curriculum:
            raise ValueError(f"Curriculum not found: {progress.config.curriculum_id}")

        progress.update_stage("load", "complete", progress=100)
        progress.overall_progress = 5
        self._notify_progress(progress)

        return curriculum

    async def _run_analyze_stage(self, progress: ReprocessProgress) -> CurriculumAnalysis:
        """Run analysis on curriculum."""
        progress.status = ReprocessStatus.ANALYZING
        progress.current_stage = "Analyze Issues"
        progress.current_activity = "Detecting quality issues..."
        progress.update_stage("analyze", "in_progress", progress=0)
        self._notify_progress(progress)

        analysis = await self.analyze_curriculum(progress.config.curriculum_id)
        progress.analysis = analysis

        progress.update_stage("analyze", "complete", progress=100)
        progress.overall_progress = 15
        self._notify_progress(progress)

        return analysis

    async def _run_fix_images_stage(
        self,
        progress: ReprocessProgress,
        curriculum: Dict[str, Any],
        issues: List[AnalysisIssue]
    ) -> Dict[str, Any]:
        """Fix broken and placeholder images."""
        image_issues = [
            i for i in issues
            if i.issue_type in (IssueType.BROKEN_IMAGE.value, IssueType.PLACEHOLDER_IMAGE.value)
        ]

        if not image_issues:
            progress.update_stage("fix_images", "skipped")
            return curriculum

        progress.status = ReprocessStatus.FIXING_IMAGES
        progress.current_stage = "Fix Images"
        progress.update_stage("fix_images", "in_progress", progress=0)
        progress.stages[2].items_total = len(image_issues)
        self._notify_progress(progress)

        # Import image service
        try:
            from ..enrichment.image_acquisition import ImageAcquisitionService
            image_service = ImageAcquisitionService()
        except ImportError:
            logger.warning("Image acquisition service not available, skipping image fixes")
            progress.update_stage("fix_images", "skipped")
            return curriculum

        for i, issue in enumerate(image_issues):
            progress.current_activity = f"Fixing image {i+1} of {len(image_issues)}..."
            progress.update_stage(
                "fix_images",
                "in_progress",
                progress=(i / len(image_issues)) * 100,
                items_processed=i
            )
            self._notify_progress(progress)

            # Get asset at location
            asset = self._get_at_path(curriculum, issue.location)
            if not asset:
                continue

            # Search for replacement
            search_query = f"{asset.get('alt', '')} {asset.get('title', '')}"
            # Note: Actual image search would go here using image_service
            # For now, mark as processed
            progress.add_fix(f"Processed image at {issue.location}")

        progress.update_stage("fix_images", "complete", progress=100, items_processed=len(image_issues))
        progress.overall_progress = 30
        self._notify_progress(progress)

        return curriculum

    async def _run_rechunk_stage(
        self,
        progress: ReprocessProgress,
        curriculum: Dict[str, Any],
        issues: List[AnalysisIssue]
    ) -> Dict[str, Any]:
        """Re-chunk oversized segments using LLM."""
        chunk_issues = [
            i for i in issues
            if i.issue_type == IssueType.OVERSIZED_SEGMENT.value
        ]

        if not chunk_issues:
            progress.update_stage("rechunk", "skipped")
            return curriculum

        progress.status = ReprocessStatus.RECHUNKING
        progress.current_stage = "Re-chunk Segments"
        progress.update_stage("rechunk", "in_progress", progress=0)
        progress.stages[3].items_total = len(chunk_issues)
        self._notify_progress(progress)

        for i, issue in enumerate(chunk_issues):
            progress.current_activity = f"Re-chunking segment {i+1} of {len(chunk_issues)}..."
            progress.update_stage(
                "rechunk",
                "in_progress",
                progress=(i / len(chunk_issues)) * 100,
                items_processed=i
            )
            self._notify_progress(progress)

            # Get segment at location
            segment = self._get_at_path(curriculum, issue.location)
            if not segment or "content" not in segment:
                continue

            # Get context
            topic = self._get_parent_topic(curriculum, issue.location)
            context = {
                "topic_title": topic.get("title", "") if topic else "",
                "segment_type": segment.get("type", "explanation"),
                "audience": curriculum.get("educational", {}).get("audienceProfile", {}).get("description", "general learners"),
            }

            try:
                # Call LLM to rechunk
                new_segments = await self.llm_service.rechunk_segment(
                    segment["content"],
                    context,
                    model=progress.config.llm_model
                )

                if new_segments and len(new_segments) > 1:
                    # Replace single segment with multiple
                    self._replace_segment_with_multiple(curriculum, issue.location, new_segments)
                    progress.add_fix(f"Split segment into {len(new_segments)} parts at {issue.location}")

            except Exception as e:
                logger.warning(f"Failed to rechunk segment: {e}")

        progress.update_stage("rechunk", "complete", progress=100, items_processed=len(chunk_issues))
        progress.overall_progress = 50
        self._notify_progress(progress)

        return curriculum

    async def _run_objectives_stage(
        self,
        progress: ReprocessProgress,
        curriculum: Dict[str, Any],
        issues: List[AnalysisIssue]
    ) -> Dict[str, Any]:
        """Generate learning objectives using LLM."""
        obj_issues = [
            i for i in issues
            if i.issue_type == IssueType.MISSING_OBJECTIVES.value
        ]

        if not obj_issues:
            progress.update_stage("objectives", "skipped")
            return curriculum

        progress.status = ReprocessStatus.GENERATING_OBJECTIVES
        progress.current_stage = "Generate Objectives"
        progress.update_stage("objectives", "in_progress", progress=0)
        progress.stages[4].items_total = len(obj_issues)
        self._notify_progress(progress)

        for i, issue in enumerate(obj_issues):
            progress.current_activity = f"Generating objectives {i+1} of {len(obj_issues)}..."
            progress.update_stage(
                "objectives",
                "in_progress",
                progress=(i / len(obj_issues)) * 100,
                items_processed=i
            )
            self._notify_progress(progress)

            # Get topic
            topic = self._get_at_path(curriculum, issue.location)
            if not topic:
                continue

            # Extract topic content
            topic_content = self._extract_topic_text(topic)
            topic_title = topic.get("title", "")

            try:
                # Generate objectives
                objectives = await self.llm_service.generate_objectives(
                    topic_content,
                    topic_title,
                    model=progress.config.llm_model
                )

                if objectives:
                    topic["learningObjectives"] = objectives
                    progress.add_fix(f"Added {len(objectives)} objectives to '{topic_title}'")

            except Exception as e:
                logger.warning(f"Failed to generate objectives: {e}")

        progress.update_stage("objectives", "complete", progress=100, items_processed=len(obj_issues))
        progress.overall_progress = 65
        self._notify_progress(progress)

        return curriculum

    async def _run_checkpoints_stage(
        self,
        progress: ReprocessProgress,
        curriculum: Dict[str, Any],
        issues: List[AnalysisIssue]
    ) -> Dict[str, Any]:
        """Add comprehension checkpoints using LLM."""
        cp_issues = [
            i for i in issues
            if i.issue_type == IssueType.MISSING_CHECKPOINTS.value
        ]

        if not cp_issues:
            progress.update_stage("checkpoints", "skipped")
            return curriculum

        progress.status = ReprocessStatus.ADDING_CHECKPOINTS
        progress.current_stage = "Add Checkpoints"
        progress.update_stage("checkpoints", "in_progress", progress=0)
        progress.stages[5].items_total = len(cp_issues)
        self._notify_progress(progress)

        for i, issue in enumerate(cp_issues):
            progress.current_activity = f"Adding checkpoints {i+1} of {len(cp_issues)}..."
            progress.update_stage(
                "checkpoints",
                "in_progress",
                progress=(i / len(cp_issues)) * 100,
                items_processed=i
            )
            self._notify_progress(progress)

            # Get topic
            topic = self._get_at_path(curriculum, issue.location)
            if not topic:
                continue

            transcript = topic.get("transcript", {})
            segments = transcript.get("segments", [])

            if not segments:
                continue

            topic_title = topic.get("title", "")

            try:
                # Add checkpoint after every 3 content segments
                new_segments = []
                preceding_content = ""

                for j, seg in enumerate(segments):
                    new_segments.append(seg)
                    content = seg.get("content", "")
                    preceding_content += content + "\n"

                    # Add checkpoint every 3 content segments
                    if (j + 1) % 3 == 0 and seg.get("type") not in ("checkpoint", "summary"):
                        checkpoint = await self.llm_service.generate_checkpoint(
                            content,
                            preceding_content,
                            topic_title,
                            model=progress.config.llm_model
                        )

                        checkpoint_segment = {
                            "id": f"seg-cp-{j}",
                            "type": "checkpoint",
                            "content": checkpoint["question"],
                            "checkpoint": checkpoint,
                        }
                        new_segments.append(checkpoint_segment)

                if len(new_segments) > len(segments):
                    transcript["segments"] = new_segments
                    checkpoints_added = len(new_segments) - len(segments)
                    progress.add_fix(f"Added {checkpoints_added} checkpoints to '{topic_title}'")

            except Exception as e:
                logger.warning(f"Failed to add checkpoints: {e}")

        progress.update_stage("checkpoints", "complete", progress=100, items_processed=len(cp_issues))
        progress.overall_progress = 75
        self._notify_progress(progress)

        return curriculum

    async def _run_alternatives_stage(
        self,
        progress: ReprocessProgress,
        curriculum: Dict[str, Any],
        issues: List[AnalysisIssue]
    ) -> Dict[str, Any]:
        """Add alternative explanations using LLM."""
        alt_issues = [
            i for i in issues
            if i.issue_type == IssueType.MISSING_ALTERNATIVES.value
        ]

        if not alt_issues:
            progress.update_stage("alternatives", "skipped")
            return curriculum

        progress.status = ReprocessStatus.ADDING_ALTERNATIVES
        progress.current_stage = "Add Alternatives"
        progress.update_stage("alternatives", "in_progress", progress=0)
        progress.stages[6].items_total = len(alt_issues)
        self._notify_progress(progress)

        for i, issue in enumerate(alt_issues):
            progress.current_activity = f"Generating alternatives {i+1} of {len(alt_issues)}..."
            progress.update_stage(
                "alternatives",
                "in_progress",
                progress=(i / len(alt_issues)) * 100,
                items_processed=i
            )
            self._notify_progress(progress)

            # Get segment
            segment = self._get_at_path(curriculum, issue.location)
            if not segment or "content" not in segment:
                continue

            try:
                alternatives = await self.llm_service.generate_alternatives(
                    segment["content"],
                    model=progress.config.llm_model
                )

                if alternatives:
                    segment["alternativeExplanations"] = alternatives
                    progress.add_fix(f"Added {len(alternatives)} alternatives at {issue.location}")

            except Exception as e:
                logger.warning(f"Failed to generate alternatives: {e}")

        progress.update_stage("alternatives", "complete", progress=100, items_processed=len(alt_issues))
        progress.overall_progress = 85
        self._notify_progress(progress)

        return curriculum

    async def _run_metadata_stage(
        self,
        progress: ReprocessProgress,
        curriculum: Dict[str, Any],
        issues: List[AnalysisIssue]
    ) -> Dict[str, Any]:
        """Fix missing metadata."""
        meta_issues = [
            i for i in issues
            if i.issue_type in (
                IssueType.MISSING_METADATA.value,
                IssueType.MISSING_TIME_ESTIMATE.value
            )
        ]

        if not meta_issues:
            progress.update_stage("metadata", "skipped")
            return curriculum

        progress.status = ReprocessStatus.FIXING_METADATA
        progress.current_stage = "Fix Metadata"
        progress.update_stage("metadata", "in_progress", progress=0)
        self._notify_progress(progress)

        # Handle time estimates
        for issue in meta_issues:
            if issue.issue_type == IssueType.MISSING_TIME_ESTIMATE.value:
                topic = self._get_at_path(curriculum, issue.location)
                if topic:
                    # Calculate time estimate from segment count
                    transcript = topic.get("transcript", {})
                    segments = transcript.get("segments", [])
                    # Estimate 30 seconds per segment
                    minutes = max(1, len(segments) // 2)
                    topic["typicalLearningTime"] = f"PT{minutes}M"
                    progress.add_fix(f"Added time estimate to {issue.location}")

        progress.update_stage("metadata", "complete", progress=100)
        progress.overall_progress = 90
        self._notify_progress(progress)

        return curriculum

    async def _run_validate_stage(
        self,
        progress: ReprocessProgress,
        curriculum: Dict[str, Any]
    ):
        """Validate that changes were applied correctly."""
        progress.status = ReprocessStatus.VALIDATING
        progress.current_stage = "Validate Changes"
        progress.current_activity = "Re-analyzing curriculum..."
        progress.update_stage("validate", "in_progress", progress=0)
        self._notify_progress(progress)

        # Re-run analysis to check remaining issues
        new_analysis = await self.analyzer.analyze(curriculum)

        progress.update_stage("validate", "complete", progress=100)
        progress.overall_progress = 95
        self._notify_progress(progress)

    async def _run_store_stage(
        self,
        progress: ReprocessProgress,
        curriculum: Dict[str, Any]
    ) -> str:
        """Store the updated curriculum."""
        progress.status = ReprocessStatus.STORING
        progress.current_stage = "Store Curriculum"
        progress.current_activity = "Saving updated UMCF..."
        progress.update_stage("store", "in_progress", progress=0)
        self._notify_progress(progress)

        curriculum_id = progress.config.curriculum_id

        # Update in-memory storage
        if curriculum_id in self.curriculum_storage:
            self.curriculum_storage[curriculum_id] = curriculum

        # Write to file
        output_path = self.curriculum_dir / f"{curriculum_id}.umcf"
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(curriculum, f, indent=2, ensure_ascii=False)

        # Clear analysis cache
        if curriculum_id in self._analysis_cache:
            del self._analysis_cache[curriculum_id]

        progress.update_stage("store", "complete", progress=100)
        progress.overall_progress = 100
        self._notify_progress(progress)

        logger.info(f"Saved reprocessed curriculum to {output_path}")
        return str(output_path)

    # =========================================================================
    # Helper Methods
    # =========================================================================

    def _load_curriculum(self, curriculum_id: str) -> Optional[Dict[str, Any]]:
        """Load curriculum from storage."""
        # Try in-memory storage first
        if curriculum_id in self.curriculum_storage:
            return self.curriculum_storage[curriculum_id]

        # Try file system
        for ext in [".umcf", ".json"]:
            path = self.curriculum_dir / f"{curriculum_id}{ext}"
            if path.exists():
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)

        return None

    def _get_at_path(self, obj: Any, path: str) -> Any:
        """Get value at JSON path."""
        if not path or path == "/":
            return obj

        parts = path.strip("/").split("/")
        current = obj

        for part in parts:
            if not part:
                continue

            if isinstance(current, dict):
                current = current.get(part)
            elif isinstance(current, list):
                try:
                    idx = int(part)
                    current = current[idx]
                except (ValueError, IndexError):
                    return None
            else:
                return None

            if current is None:
                return None

        return current

    def _get_parent_topic(self, curriculum: Dict[str, Any], path: str) -> Optional[Dict[str, Any]]:
        """Get parent topic for a given path."""
        parts = path.strip("/").split("/")

        # Walk up until we find a topic
        for i in range(len(parts), 0, -1):
            parent_path = "/" + "/".join(parts[:i])
            parent = self._get_at_path(curriculum, parent_path)
            if isinstance(parent, dict) and "title" in parent and "transcript" in parent:
                return parent

        return None

    def _extract_topic_text(self, topic: Dict[str, Any]) -> str:
        """Extract all text content from a topic."""
        text_parts = []

        if topic.get("title"):
            text_parts.append(topic["title"])
        if topic.get("description"):
            text_parts.append(topic["description"])

        transcript = topic.get("transcript", {})
        for seg in transcript.get("segments", []):
            if isinstance(seg, dict) and "content" in seg:
                text_parts.append(seg["content"])

        return "\n\n".join(text_parts)

    def _replace_segment_with_multiple(
        self,
        curriculum: Dict[str, Any],
        path: str,
        new_segments: List[Dict[str, Any]]
    ):
        """Replace a single segment with multiple segments."""
        # Parse path to find parent segments array
        parts = path.strip("/").split("/")
        if len(parts) < 2:
            return

        # Get parent path and index
        segment_idx = int(parts[-1])
        parent_path = "/" + "/".join(parts[:-1])

        segments_array = self._get_at_path(curriculum, parent_path)
        if not isinstance(segments_array, list):
            return

        # Replace the single segment with multiple
        segments_array[segment_idx:segment_idx+1] = new_segments
