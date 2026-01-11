"""
Data models for the curriculum reprocessing system.

These models are used for:
- Analysis issue tracking
- Reprocessing job configuration
- Progress tracking
"""

from dataclasses import dataclass, field, asdict
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional


# =============================================================================
# Analysis Models
# =============================================================================

class IssueSeverity(Enum):
    """Severity levels for analysis issues."""
    CRITICAL = "critical"  # Curriculum broken/unusable without fix
    WARNING = "warning"    # Quality issue affecting learning experience
    INFO = "info"          # Enhancement opportunity


class IssueType(Enum):
    """Types of issues that can be detected."""
    BROKEN_IMAGE = "broken_image"
    PLACEHOLDER_IMAGE = "placeholder_image"
    OVERSIZED_SEGMENT = "oversized_segment"
    UNDERSIZED_SEGMENT = "undersized_segment"
    MISSING_OBJECTIVES = "missing_objectives"
    MISSING_CHECKPOINTS = "missing_checkpoints"
    MISSING_ALTERNATIVES = "missing_alternatives"
    MISSING_TIME_ESTIMATE = "missing_time_estimate"
    MISSING_METADATA = "missing_metadata"
    INVALID_BLOOM_LEVEL = "invalid_bloom_level"


@dataclass
class AnalysisIssue:
    """A detected issue in the curriculum."""
    id: str                         # Unique issue ID (e.g., "issue-001")
    issue_type: str                 # Type from IssueType enum
    severity: str                   # "critical", "warning", "info"
    location: str                   # JSON path (e.g., "/content/modules/0/topics/2")
    description: str                # Human-readable description
    suggested_fix: str              # What reprocessing will do
    auto_fixable: bool              # Can be fixed automatically
    node_id: Optional[str] = None   # UMCF node ID if applicable
    details: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "issueType": self.issue_type,
            "severity": self.severity,
            "location": self.location,
            "nodeId": self.node_id,
            "description": self.description,
            "suggestedFix": self.suggested_fix,
            "autoFixable": self.auto_fixable,
            "details": self.details,
        }


@dataclass
class AnalysisStats:
    """Summary statistics for an analysis."""
    total_issues: int = 0
    critical_count: int = 0
    warning_count: int = 0
    info_count: int = 0
    auto_fixable_count: int = 0
    issues_by_type: Dict[str, int] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "totalIssues": self.total_issues,
            "criticalCount": self.critical_count,
            "warningCount": self.warning_count,
            "infoCount": self.info_count,
            "autoFixableCount": self.auto_fixable_count,
            "issuesByType": self.issues_by_type,
        }


@dataclass
class CurriculumAnalysis:
    """Full analysis result for a curriculum."""
    curriculum_id: str
    curriculum_title: str
    analyzed_at: datetime
    analysis_duration_ms: int
    issues: List[AnalysisIssue]
    stats: AnalysisStats

    def to_dict(self) -> Dict[str, Any]:
        return {
            "curriculumId": self.curriculum_id,
            "curriculumTitle": self.curriculum_title,
            "analyzedAt": self.analyzed_at.isoformat(),
            "analysisDurationMs": self.analysis_duration_ms,
            "issues": [i.to_dict() for i in self.issues],
            "stats": self.stats.to_dict(),
        }


# =============================================================================
# Reprocessing Models
# =============================================================================

class ReprocessStatus(Enum):
    """Status values for reprocessing jobs."""
    QUEUED = "queued"
    LOADING = "loading"
    ANALYZING = "analyzing"
    FIXING_IMAGES = "fixing_images"
    RECHUNKING = "rechunking"
    GENERATING_OBJECTIVES = "generating_objectives"
    ADDING_CHECKPOINTS = "adding_checkpoints"
    ADDING_ALTERNATIVES = "adding_alternatives"
    FIXING_METADATA = "fixing_metadata"
    VALIDATING = "validating"
    STORING = "storing"
    COMPLETE = "complete"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass
class ReprocessConfig:
    """Configuration for a reprocessing job."""
    curriculum_id: str

    # What to fix (all True by default)
    fix_images: bool = True
    rechunk_segments: bool = True
    generate_objectives: bool = True
    add_checkpoints: bool = True
    add_alternatives: bool = True
    fix_metadata: bool = True

    # LLM configuration
    llm_model: str = "qwen2.5:32b"
    llm_temperature: float = 0.5

    # Image handling
    image_search_enabled: bool = True
    generate_placeholders: bool = True

    # Mode
    dry_run: bool = False  # Preview mode, don't save changes

    # Filtering (optional)
    issue_types: Optional[List[str]] = None  # Only fix these types
    node_ids: Optional[List[str]] = None     # Only fix these nodes

    def to_dict(self) -> Dict[str, Any]:
        return {
            "curriculumId": self.curriculum_id,
            "fixImages": self.fix_images,
            "rechunkSegments": self.rechunk_segments,
            "generateObjectives": self.generate_objectives,
            "addCheckpoints": self.add_checkpoints,
            "addAlternatives": self.add_alternatives,
            "fixMetadata": self.fix_metadata,
            "llmModel": self.llm_model,
            "llmTemperature": self.llm_temperature,
            "imageSearchEnabled": self.image_search_enabled,
            "generatePlaceholders": self.generate_placeholders,
            "dryRun": self.dry_run,
            "issueTypes": self.issue_types,
            "nodeIds": self.node_ids,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "ReprocessConfig":
        return cls(
            curriculum_id=data["curriculumId"],
            fix_images=data.get("fixImages", True),
            rechunk_segments=data.get("rechunkSegments", True),
            generate_objectives=data.get("generateObjectives", True),
            add_checkpoints=data.get("addCheckpoints", True),
            add_alternatives=data.get("addAlternatives", True),
            fix_metadata=data.get("fixMetadata", True),
            llm_model=data.get("llmModel", "qwen2.5:32b"),
            llm_temperature=data.get("llmTemperature", 0.5),
            image_search_enabled=data.get("imageSearchEnabled", True),
            generate_placeholders=data.get("generatePlaceholders", True),
            dry_run=data.get("dryRun", False),
            issue_types=data.get("issueTypes"),
            node_ids=data.get("nodeIds"),
        )


@dataclass
class ReprocessStage:
    """Progress information for a single stage."""
    id: str
    name: str
    status: str = "pending"  # pending, in_progress, complete, skipped, failed
    progress: float = 0.0    # 0-100
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    items_total: int = 0
    items_processed: int = 0
    error: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "status": self.status,
            "progress": self.progress,
            "startedAt": self.started_at.isoformat() if self.started_at else None,
            "completedAt": self.completed_at.isoformat() if self.completed_at else None,
            "itemsTotal": self.items_total,
            "itemsProcessed": self.items_processed,
            "error": self.error,
        }


@dataclass
class ReprocessResult:
    """Final result of a reprocessing job."""
    success: bool
    fixes_applied: List[str]  # List of fix descriptions
    issues_fixed: int
    issues_remaining: int
    duration_ms: int
    output_path: Optional[str] = None
    error: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "success": self.success,
            "fixesApplied": self.fixes_applied,
            "issuesFixed": self.issues_fixed,
            "issuesRemaining": self.issues_remaining,
            "durationMs": self.duration_ms,
            "outputPath": self.output_path,
            "error": self.error,
        }


@dataclass
class ReprocessProgress:
    """Full progress information for a reprocessing job."""
    id: str
    config: ReprocessConfig
    status: ReprocessStatus = ReprocessStatus.QUEUED
    overall_progress: float = 0.0  # 0-100
    current_stage: str = ""
    current_activity: str = ""
    stages: List[ReprocessStage] = field(default_factory=list)
    analysis: Optional[CurriculumAnalysis] = None
    fixes_applied: List[str] = field(default_factory=list)
    started_at: Optional[datetime] = None
    result: Optional[ReprocessResult] = None
    error: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "config": self.config.to_dict(),
            "status": self.status.value,
            "overallProgress": self.overall_progress,
            "currentStage": self.current_stage,
            "currentActivity": self.current_activity,
            "stages": [s.to_dict() for s in self.stages],
            "analysis": self.analysis.to_dict() if self.analysis else None,
            "fixesApplied": self.fixes_applied,
            "startedAt": self.started_at.isoformat() if self.started_at else None,
            "result": self.result.to_dict() if self.result else None,
            "error": self.error,
        }

    def add_fix(self, description: str):
        """Record a fix that was applied."""
        self.fixes_applied.append(description)

    def update_stage(
        self,
        stage_id: str,
        status: str,
        progress: float = None,
        items_processed: int = None,
        error: str = None
    ):
        """Update a stage's status."""
        for stage in self.stages:
            if stage.id == stage_id:
                stage.status = status
                if progress is not None:
                    stage.progress = progress
                if items_processed is not None:
                    stage.items_processed = items_processed
                if error is not None:
                    stage.error = error
                if status == "in_progress" and stage.started_at is None:
                    stage.started_at = datetime.utcnow()
                if status in ("complete", "skipped", "failed"):
                    stage.completed_at = datetime.utcnow()
                break


# =============================================================================
# Preview Models (for dry run)
# =============================================================================

@dataclass
class ProposedChange:
    """A change that would be made during reprocessing."""
    location: str
    change_type: str  # replace_image, split_segment, add_objectives, etc.
    before: Dict[str, Any]
    after: Dict[str, Any]
    description: str

    def to_dict(self) -> Dict[str, Any]:
        return {
            "location": self.location,
            "changeType": self.change_type,
            "before": self.before,
            "after": self.after,
            "description": self.description,
        }


@dataclass
class ReprocessPreview:
    """Preview of what reprocessing would do."""
    curriculum_id: str
    proposed_changes: List[ProposedChange]
    summary: Dict[str, int]  # Counts by change type

    def to_dict(self) -> Dict[str, Any]:
        return {
            "curriculumId": self.curriculum_id,
            "proposedChanges": [c.to_dict() for c in self.proposed_changes],
            "summary": self.summary,
        }
