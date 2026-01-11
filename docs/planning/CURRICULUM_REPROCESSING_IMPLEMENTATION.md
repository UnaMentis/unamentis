# Curriculum Reprocessing System Implementation Plan

**Last Updated:** January 10, 2026
**Status:** Ready for Implementation
**Priority:** High

---

## Overview

This document specifies the implementation of a curriculum reprocessing system that allows existing UMCF curricula to be analyzed for quality issues and re-enriched using self-hosted Ollama LLMs without re-importing from external sources.

### Problem Statement

Some imported curricula have quality issues:
- Broken or placeholder images
- Inappropriately chunked content (e.g., physics lectures not segmented properly)
- Missing learning objectives, checkpoints, or alternative explanations
- Incomplete metadata

Currently, the only option is to delete and re-import, losing any manual customizations. We need a reprocessing capability that can fix issues in place.

### Goals

1. **Analysis API** - Automatically detect quality issues in existing curricula
2. **Reprocessing Pipeline** - Fix detected issues using LLM enrichment
3. **Decision Support** - Generate reports showing what issues exist and what would be fixed
4. **UI Dashboard** - Web interface to view analysis results and trigger reprocessing

---

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        Web UI (port 3000)                       │
│  ┌─────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │  ReprocessPanel │  │ AnalysisModal    │  │ CurriculaPanel│  │
│  │  (job tracking) │  │ (issue details)  │  │ (+Analyze btn)│  │
│  └────────┬────────┘  └────────┬─────────┘  └───────┬───────┘  │
└───────────┼─────────────────────┼───────────────────┼───────────┘
            │                     │                   │
            ▼                     ▼                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Management API (port 8766)                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   reprocess_api.py                       │    │
│  │  POST /api/reprocess/analyze/{id}                        │    │
│  │  GET  /api/reprocess/analysis/{id}                       │    │
│  │  POST /api/reprocess/jobs                                │    │
│  │  GET  /api/reprocess/jobs                                │    │
│  │  GET  /api/reprocess/jobs/{job_id}                       │    │
│  │  DELETE /api/reprocess/jobs/{job_id}                     │    │
│  │  POST /api/reprocess/preview/{id}                        │    │
│  └─────────────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Importers Package                           │
│  ┌─────────────────┐  ┌────────────────┐  ┌─────────────────┐   │
│  │CurriculumAnalyzer│  │ReprocessOrch.  │  │LLMEnrichment    │   │
│  │ - check_images  │  │ - 10 stages    │  │ - rechunk       │   │
│  │ - check_chunking│  │ - progress     │  │ - objectives    │   │
│  │ - check_objectives│ │ - callbacks   │  │ - checkpoints   │   │
│  │ - check_metadata │  │ - cancellation│  │ - alternatives  │   │
│  └─────────────────┘  └────────────────┘  └─────────────────┘   │
│                                                    │             │
│  ┌─────────────────┐                               │             │
│  │ImageAcquisition │ ◄─────────────────────────────┘             │
│  │ (existing)      │                                             │
│  └─────────────────┘                                             │
└───────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Ollama (localhost:11434)                      │
│  ┌─────────────────┐  ┌────────────────┐  ┌─────────────────┐   │
│  │ qwen2.5:32b     │  │ mistral:7b     │  │ llama3.1:70b    │   │
│  │ (rechunking)    │  │ (objectives)   │  │ (alternatives)  │   │
│  └─────────────────┘  └────────────────┘  └─────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. User clicks "Analyze" on curriculum card
   └─► POST /api/reprocess/analyze/{curriculum_id}
       └─► CurriculumAnalyzer.analyze()
           ├─► check_images() - HEAD requests to validate URLs
           ├─► check_chunking() - Measure segment lengths
           ├─► check_objectives() - Find missing objectives
           ├─► check_checkpoints() - Find missing comprehension checks
           ├─► check_alternatives() - Find missing alt explanations
           └─► check_metadata() - Validate required fields
       └─► Return CurriculumAnalysis with issues list

2. User reviews issues in modal, clicks "Start Reprocessing"
   └─► POST /api/reprocess/jobs
       └─► ReprocessOrchestrator.start_job()
           └─► Returns job_id immediately
           └─► Background task runs pipeline:
               Stage 1: Load curriculum from storage
               Stage 2: Analyze (get full issue list)
               Stage 3: Fix images (Wikimedia search, placeholders)
               Stage 4: Re-chunk (LLM splits oversized segments)
               Stage 5: Generate objectives (LLM)
               Stage 6: Add checkpoints (LLM)
               Stage 7: Add alternatives (LLM)
               Stage 8: Fix metadata (fill missing fields)
               Stage 9: Validate (verify all fixes applied)
               Stage 10: Store (save updated UMCF)

3. UI polls for progress
   └─► GET /api/reprocess/jobs/{job_id}
       └─► Returns current stage, progress %, fixes applied
```

---

## Issue Detection

### Issue Types

| Type | Description | Severity | Detection Method |
|------|-------------|----------|------------------|
| `broken_image` | Image URL returns 404 or error | critical | HEAD request with 5s timeout |
| `placeholder_image` | Image marked with `isPlaceholder: true` | warning | Check UMCF flag |
| `oversized_segment` | Transcript segment > 2000 characters | warning | Character count |
| `undersized_segment` | Transcript segment < 100 characters | info | Character count |
| `missing_objectives` | Topic has no `learningObjectives` array | warning | Check for empty/missing |
| `missing_checkpoints` | Topic has no `checkpoint` segments | warning | Count checkpoint types |
| `missing_alternatives` | Segment has no `alternativeExplanations` | info | Check array presence |
| `missing_time_estimate` | Topic missing `typicalLearningTime` | info | Check field presence |
| `missing_metadata` | Required fields empty (title, description) | warning | Validate required fields |
| `invalid_bloom_level` | Objective has invalid Bloom taxonomy level | info | Validate against enum |

### Severity Levels

- **Critical** - Curriculum is broken/unusable without fix (e.g., broken images)
- **Warning** - Quality issue that affects learning experience (e.g., poor chunking)
- **Info** - Enhancement opportunity (e.g., missing alternatives)

### Detection Thresholds

```python
# Chunking thresholds
MAX_SEGMENT_LENGTH = 2000  # Characters - longer is hard to follow in voice
MIN_SEGMENT_LENGTH = 100   # Characters - shorter may be too fragmented

# Checkpoint frequency
CHECKPOINT_EVERY_N_SEGMENTS = 3  # Insert comprehension check every 3 content segments

# Required metadata fields
REQUIRED_METADATA = ["title", "description", "difficulty", "typicalLearningTime"]
```

---

## Reprocessing Pipeline

### Stage Definitions

| Stage | Name | Weight | Description |
|-------|------|--------|-------------|
| 1 | Load | 5% | Load UMCF from file storage |
| 2 | Analyze | 10% | Run full analysis to get issue list |
| 3 | Fix Images | 15% | Validate URLs, search Wikimedia, generate placeholders |
| 4 | Re-chunk | 20% | Use LLM to split oversized segments |
| 5 | Generate Objectives | 15% | Use LLM for Bloom-aligned learning objectives |
| 6 | Add Checkpoints | 10% | Use LLM for comprehension questions |
| 7 | Add Alternatives | 10% | Use LLM for simpler/technical explanations |
| 8 | Fix Metadata | 5% | Fill missing required fields |
| 9 | Validate | 5% | Verify all fixes applied correctly |
| 10 | Store | 5% | Save updated UMCF to storage |

### Image Fixing Logic

```python
async def fix_image(self, asset: dict, context: dict) -> dict:
    """
    Fix a broken or placeholder image.

    Strategy:
    1. Build search query from title, alt text, caption
    2. Search Wikimedia Commons
    3. If found: download, update URL, add attribution
    4. If not found: generate SVG placeholder with description
    """
    # Reuse existing ImageAcquisitionService
    service = ImageAcquisitionService()

    search_query = self._build_search_query(
        title=asset.get("title", ""),
        alt=asset.get("alt", ""),
        caption=asset.get("caption", ""),
        topic_title=context.get("topic_title", "")
    )

    result = await service.search_wikimedia(search_query)

    if result.found:
        return {
            "url": result.url,
            "attribution": result.attribution,
            "source": "wikimedia",
            "isPlaceholder": False
        }
    else:
        placeholder = await service.generate_placeholder(
            description=search_query,
            dimensions=(800, 600)
        )
        return {
            "data": placeholder.base64,
            "mimeType": "image/svg+xml",
            "source": "generated",
            "isPlaceholder": True
        }
```

### Re-chunking with LLM

```python
RECHUNK_SYSTEM_PROMPT = """You are an expert educational content editor. Your task is to break up
a long piece of educational content into smaller, conversational segments suitable for voice-based tutoring.

Guidelines:
- Each segment should be 150-400 words (under 2000 characters)
- Preserve the semantic meaning and flow
- Create natural break points between concepts
- Each segment should feel like a complete thought or explanation
- Maintain the original voice and tone
- Preserve any technical terminology

Output format: Return a JSON array of segment objects, each with:
- "content": The text content of the segment
- "type": One of "introduction", "explanation", "example", "summary"
- "speakingNotes": Optional notes for the voice tutor
"""

async def rechunk_segment(self, segment_text: str, context: dict) -> List[dict]:
    """Split an oversized segment into conversational turns."""

    user_prompt = f"""Break this educational content into smaller segments:

Topic: {context.get('topic_title', 'Unknown')}
Target audience: {context.get('audience', 'general learners')}

Content to split:
{segment_text}

Return a JSON array of segments."""

    response = await self._call_llm(
        model="qwen2.5:32b",
        messages=[
            {"role": "system", "content": RECHUNK_SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt}
        ],
        temperature=0.3  # Lower temperature for consistent structure
    )

    return json.loads(response)
```

### Learning Objectives Generation

```python
OBJECTIVES_SYSTEM_PROMPT = """You are an expert instructional designer. Generate Bloom's taxonomy-aligned
learning objectives for educational content.

Bloom's Taxonomy Levels (use these exact values):
- remember: Recall facts and basic concepts
- understand: Explain ideas or concepts
- apply: Use information in new situations
- analyze: Draw connections among ideas
- evaluate: Justify a stand or decision
- create: Produce new or original work

Output format: Return a JSON array of objective objects, each with:
- "id": Unique identifier (e.g., "obj-1")
- "text": The objective statement starting with an action verb
- "bloomLevel": One of the taxonomy levels above
- "assessable": true if this can be directly assessed
"""

async def generate_objectives(self, topic_content: str, audience: str) -> List[dict]:
    """Generate 2-4 Bloom-aligned learning objectives for a topic."""

    user_prompt = f"""Generate 2-4 learning objectives for this educational content:

Target audience: {audience}

Content:
{topic_content[:3000]}  # Limit context to avoid token overflow

Return a JSON array of learning objectives."""

    response = await self._call_llm(
        model="mistral:7b",  # Fast model for structured output
        messages=[
            {"role": "system", "content": OBJECTIVES_SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt}
        ],
        temperature=0.5
    )

    return json.loads(response)
```

### Checkpoint Generation

```python
CHECKPOINT_SYSTEM_PROMPT = """You are an expert tutor creating comprehension checks. Generate a question
that verifies the learner understood the preceding content.

Guidelines:
- Ask one clear, focused question
- Target the key concept just explained
- Provide expected answer patterns (not exact answers)
- Include keywords the learner should mention
- Keep it conversational, not quiz-like

Output format: Return a JSON object with:
- "type": "comprehension_check"
- "question": The question to ask
- "expectedResponsePatterns": Array of regex patterns for valid answers
- "expectedKeywords": Array of key terms that should appear in response
- "hintOnStruggle": A hint to give if learner struggles
- "celebrationMessage": Brief praise for correct answer
"""

async def generate_checkpoint(self, segment_content: str, preceding_content: str) -> dict:
    """Generate a comprehension check for a segment."""

    user_prompt = f"""Create a comprehension check for this content:

What was just explained:
{segment_content}

Previous context:
{preceding_content[-1000:]}

Generate a conversational comprehension check question."""

    response = await self._call_llm(
        model="mistral:7b",
        messages=[
            {"role": "system", "content": CHECKPOINT_SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt}
        ],
        temperature=0.6
    )

    return json.loads(response)
```

---

## Data Models

### Analysis Models

```python
# server/importers/analysis/curriculum_analyzer.py

@dataclass
class AnalysisIssue:
    """A detected issue in the curriculum."""
    id: str                         # Unique issue ID (e.g., "issue-001")
    issue_type: str                 # Type from IssueType enum
    severity: str                   # "critical", "warning", "info"
    location: str                   # JSON path (e.g., "/content/modules/0/topics/2")
    node_id: Optional[str]          # UMCF node ID if applicable
    description: str                # Human-readable description
    suggested_fix: str              # What reprocessing will do
    auto_fixable: bool              # Can be fixed automatically
    details: Dict[str, Any]         # Issue-specific details

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
            "details": self.details
        }


@dataclass
class AnalysisStats:
    """Summary statistics for an analysis."""
    total_issues: int
    critical_count: int
    warning_count: int
    info_count: int
    auto_fixable_count: int
    issues_by_type: Dict[str, int]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "totalIssues": self.total_issues,
            "criticalCount": self.critical_count,
            "warningCount": self.warning_count,
            "infoCount": self.info_count,
            "autoFixableCount": self.auto_fixable_count,
            "issuesByType": self.issues_by_type
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
            "stats": self.stats.to_dict()
        }
```

### Reprocessing Models

```python
# server/importers/core/reprocess_models.py

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
    dry_run: bool = False  # Preview mode - don't save changes

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
            "nodeIds": self.node_ids
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
            node_ids=data.get("nodeIds")
        )


@dataclass
class ReprocessStage:
    """Progress information for a single stage."""
    name: str
    status: str  # "pending", "in_progress", "complete", "skipped", "failed"
    progress: float  # 0-100
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    items_total: int = 0
    items_processed: int = 0
    error: Optional[str] = None


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


@dataclass
class ReprocessProgress:
    """Full progress information for a reprocessing job."""
    id: str
    config: ReprocessConfig
    status: ReprocessStatus
    overall_progress: float  # 0-100
    current_stage: str
    current_activity: str
    stages: List[ReprocessStage]
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
            "stages": [asdict(s) for s in self.stages],
            "analysis": self.analysis.to_dict() if self.analysis else None,
            "fixesApplied": self.fixes_applied,
            "startedAt": self.started_at.isoformat() if self.started_at else None,
            "result": asdict(self.result) if self.result else None,
            "error": self.error
        }
```

---

## API Specification

### Endpoints

#### POST /api/reprocess/analyze/{curriculum_id}

Trigger analysis of a curriculum.

**Request:**
```json
{
  "force": false  // Optional: re-analyze even if cached
}
```

**Response:**
```json
{
  "success": true,
  "analysis": {
    "curriculumId": "physics-101",
    "curriculumTitle": "Introduction to Physics",
    "analyzedAt": "2026-01-10T14:30:00Z",
    "analysisDurationMs": 2340,
    "issues": [
      {
        "id": "issue-001",
        "issueType": "broken_image",
        "severity": "critical",
        "location": "/content/modules/0/topics/2/assets/0",
        "nodeId": "img-forces-diagram",
        "description": "Image URL returns 404: https://example.com/forces.png",
        "suggestedFix": "Search Wikimedia Commons for replacement image",
        "autoFixable": true,
        "details": {
          "url": "https://example.com/forces.png",
          "httpStatus": 404
        }
      },
      {
        "id": "issue-002",
        "issueType": "oversized_segment",
        "severity": "warning",
        "location": "/content/modules/1/topics/0/transcript/segments/5",
        "nodeId": "seg-newton-laws",
        "description": "Segment has 3,247 characters (max 2,000)",
        "suggestedFix": "Use LLM to split into 2-3 smaller segments",
        "autoFixable": true,
        "details": {
          "charCount": 3247,
          "recommendedMax": 2000
        }
      }
    ],
    "stats": {
      "totalIssues": 12,
      "criticalCount": 3,
      "warningCount": 5,
      "infoCount": 4,
      "autoFixableCount": 10,
      "issuesByType": {
        "broken_image": 2,
        "placeholder_image": 1,
        "oversized_segment": 4,
        "missing_objectives": 3,
        "missing_checkpoints": 2
      }
    }
  }
}
```

#### GET /api/reprocess/analysis/{curriculum_id}

Get cached analysis results.

**Response:** Same as POST analyze

#### POST /api/reprocess/jobs

Start a reprocessing job.

**Request:**
```json
{
  "curriculumId": "physics-101",
  "fixImages": true,
  "rechunkSegments": true,
  "generateObjectives": true,
  "addCheckpoints": true,
  "addAlternatives": false,
  "fixMetadata": true,
  "llmModel": "qwen2.5:32b",
  "dryRun": false
}
```

**Response:**
```json
{
  "success": true,
  "jobId": "reprocess-a1b2c3d4",
  "status": "queued"
}
```

#### GET /api/reprocess/jobs

List all reprocessing jobs.

**Query Parameters:**
- `status`: Filter by status (optional)
- `curriculum_id`: Filter by curriculum (optional)

**Response:**
```json
{
  "success": true,
  "jobs": [
    {
      "id": "reprocess-a1b2c3d4",
      "curriculumId": "physics-101",
      "curriculumTitle": "Introduction to Physics",
      "status": "rechunking",
      "overallProgress": 45.5,
      "startedAt": "2026-01-10T14:30:00Z"
    }
  ]
}
```

#### GET /api/reprocess/jobs/{job_id}

Get detailed job progress.

**Response:**
```json
{
  "success": true,
  "progress": {
    "id": "reprocess-a1b2c3d4",
    "config": { ... },
    "status": "rechunking",
    "overallProgress": 45.5,
    "currentStage": "Re-chunk Segments",
    "currentActivity": "Processing segment 3 of 8",
    "stages": [
      {"name": "Load", "status": "complete", "progress": 100},
      {"name": "Analyze", "status": "complete", "progress": 100},
      {"name": "Fix Images", "status": "complete", "progress": 100},
      {"name": "Re-chunk", "status": "in_progress", "progress": 37.5, "itemsTotal": 8, "itemsProcessed": 3},
      {"name": "Generate Objectives", "status": "pending", "progress": 0},
      ...
    ],
    "fixesApplied": [
      "Replaced broken image in Unit 1, Topic 2",
      "Found Wikimedia replacement for forces diagram",
      "Split segment 'Newton's Laws' into 3 parts"
    ],
    "analysis": { ... }
  }
}
```

#### DELETE /api/reprocess/jobs/{job_id}

Cancel a running job.

**Response:**
```json
{
  "success": true,
  "cancelled": true
}
```

#### POST /api/reprocess/preview/{curriculum_id}

Dry run to show what would change.

**Request:** Same as POST /api/reprocess/jobs with `dryRun: true`

**Response:**
```json
{
  "success": true,
  "preview": {
    "curriculumId": "physics-101",
    "proposedChanges": [
      {
        "location": "/content/modules/0/topics/2/assets/0",
        "changeType": "replace_image",
        "before": {"url": "https://broken.com/img.png"},
        "after": {"url": "https://wikimedia.org/...", "source": "wikimedia"}
      },
      {
        "location": "/content/modules/1/topics/0/transcript/segments/5",
        "changeType": "split_segment",
        "before": {"charCount": 3247},
        "after": {"segmentCount": 3, "avgCharCount": 1082}
      }
    ],
    "summary": {
      "totalChanges": 15,
      "imagesFixed": 3,
      "segmentsRechunked": 4,
      "objectivesAdded": 5,
      "checkpointsAdded": 3
    }
  }
}
```

---

## Files to Create

### Backend Files

| File | Purpose | Lines (Est.) |
|------|---------|--------------|
| `server/importers/analysis/__init__.py` | Package init | 5 |
| `server/importers/analysis/curriculum_analyzer.py` | Issue detection logic | 400 |
| `server/importers/core/reprocess_models.py` | Data models | 200 |
| `server/importers/core/reprocess_orchestrator.py` | Job orchestration | 500 |
| `server/importers/enrichment/llm_enrichment.py` | Ollama LLM integration | 300 |
| `server/management/reprocess_api.py` | API routes | 350 |

### Frontend Files

| File | Purpose | Lines (Est.) |
|------|---------|--------------|
| `server/web/src/app/api/reprocess/analyze/[curriculumId]/route.ts` | Analyze proxy | 40 |
| `server/web/src/app/api/reprocess/jobs/route.ts` | Jobs list/create proxy | 50 |
| `server/web/src/app/api/reprocess/jobs/[jobId]/route.ts` | Job status proxy | 50 |
| `server/web/src/components/dashboard/reprocess-panel.tsx` | Main UI | 400 |
| `server/web/src/components/dashboard/curriculum-analysis-modal.tsx` | Issue details | 300 |

---

## Files to Modify

| File | Change |
|------|--------|
| `server/management/server.py` | Add `register_reprocess_routes(app)` call |
| `server/importers/core/__init__.py` | Export new modules |
| `server/web/src/types/index.ts` | Add TypeScript types for analysis and reprocessing |
| `server/web/src/components/dashboard/dashboard.tsx` | Add Reprocess tab |
| `server/web/src/components/dashboard/nav-tabs.tsx` | Add "Reprocess" navigation item |
| `server/web/src/components/dashboard/curricula-panel.tsx` | Add "Analyze" button to curriculum cards |

---

## Implementation Phases

### Phase 1: Analysis System (Backend)

**Goal:** Detect issues in existing curricula

**Tasks:**
1. Create `server/importers/analysis/` package
2. Implement `CurriculumAnalyzer` with all check methods
3. Create `reprocess_models.py` with analysis data models
4. Create `reprocess_api.py` with analyze endpoints only
5. Register routes in `server.py`
6. Test with curl against known-problematic curriculum

**Verification:**
```bash
# Analyze a curriculum
curl -X POST http://localhost:8766/api/reprocess/analyze/physics-101

# Should return issues list with broken images, chunking problems, etc.
```

### Phase 2: LLM Enrichment Service (Backend)

**Goal:** Enable LLM-based content generation

**Tasks:**
1. Create `server/importers/enrichment/llm_enrichment.py`
2. Implement `rechunk_segment()` with chunking prompt
3. Implement `generate_objectives()` with Bloom's taxonomy
4. Implement `generate_checkpoint()` for comprehension checks
5. Implement `generate_alternatives()` for explanation variants
6. Test each function independently against Ollama

**Verification:**
```python
# Test rechunking
service = LLMEnrichmentService()
result = await service.rechunk_segment(
    "Very long text...",
    {"topic_title": "Newton's Laws"}
)
# Should return list of 2-3 segment dicts
```

### Phase 3: Reprocessing Orchestrator (Backend)

**Goal:** Run full reprocessing pipeline with progress tracking

**Tasks:**
1. Create `ReprocessOrchestrator` modeled after `ImportOrchestrator`
2. Implement 10-stage pipeline with progress callbacks
3. Integrate with existing `ImageAcquisitionService`
4. Integrate with `LLMEnrichmentService`
5. Add job management (start, cancel, list, get progress)
6. Add API endpoints for job management

**Verification:**
```bash
# Start a reprocessing job
curl -X POST http://localhost:8766/api/reprocess/jobs \
  -H "Content-Type: application/json" \
  -d '{"curriculumId": "physics-101", "dryRun": true}'

# Check progress
curl http://localhost:8766/api/reprocess/jobs/{job_id}
```

### Phase 4: Frontend UI

**Goal:** Dashboard for viewing analysis and managing reprocessing

**Tasks:**
1. Add TypeScript types to `index.ts`
2. Create Next.js API proxy routes
3. Create `ReprocessPanel` component
4. Create `CurriculumAnalysisModal` component
5. Add "Reprocess" tab to dashboard navigation
6. Add "Analyze" button to curriculum cards
7. Add issue count badges to curriculum cards

**Verification:**
- Navigate to dashboard, see Reprocess tab
- Click Analyze on a curriculum, see issues modal
- Start reprocessing, see progress in panel
- Verify curriculum updated after completion

### Phase 5: Integration Testing

**Goal:** End-to-end validation

**Tasks:**
1. Run full reprocess on physics curriculum (known chunking issues)
2. Verify LLM prompts produce quality output
3. Test cancellation mid-job
4. Test error handling (Ollama down, invalid curriculum)
5. Performance testing (large curriculum with many issues)

---

## LLM Model Selection

| Task | Recommended Model | Rationale |
|------|-------------------|-----------|
| Re-chunking | qwen2.5:32b | Complex reasoning for natural break points |
| Learning Objectives | mistral:7b | Fast, good at structured output |
| Checkpoints | mistral:7b | Quick question generation |
| Alternative Explanations | qwen2.5:32b | Creative paraphrasing needs larger model |
| Metadata Inference | mistral:7b | Simple extraction tasks |

**Ollama Endpoint:** `http://localhost:11434/v1/chat/completions`

---

## Testing Commands

```bash
# 1. Test analysis endpoint
curl -X POST http://localhost:8766/api/reprocess/analyze/physics-101 | jq

# 2. Test job creation (dry run)
curl -X POST http://localhost:8766/api/reprocess/jobs \
  -H "Content-Type: application/json" \
  -d '{"curriculumId": "physics-101", "dryRun": true}' | jq

# 3. Check job progress
curl http://localhost:8766/api/reprocess/jobs/{job_id} | jq

# 4. List all jobs
curl http://localhost:8766/api/reprocess/jobs | jq

# 5. Cancel a job
curl -X DELETE http://localhost:8766/api/reprocess/jobs/{job_id} | jq

# 6. Preview changes
curl -X POST http://localhost:8766/api/reprocess/preview/physics-101 \
  -H "Content-Type: application/json" \
  -d '{"fixImages": true, "rechunkSegments": true}' | jq
```

---

## Related Documentation

- [Import API](../server/README.md) - Existing import system patterns
- [UMCF Specification](../../curriculum/spec/UMCF_SPECIFICATION.md) - Curriculum format
- [FOV Context Management](./FOV_CONTEXT_MANAGEMENT.md) - LLM context patterns
- [Project Overview](./PROJECT_OVERVIEW.md) - Overall architecture

---

## Changelog

| Date | Change |
|------|--------|
| 2026-01-10 | Initial plan created |
