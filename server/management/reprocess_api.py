"""
API routes for curriculum reprocessing.

These routes enable:
- Analyzing curricula for quality issues
- Starting and monitoring reprocessing jobs
- Previewing changes before applying them
"""

import logging
from pathlib import Path
from typing import Optional

from aiohttp import web

# Import reprocessing system
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from importers.core.reprocess_orchestrator import ReprocessOrchestrator
from importers.core.reprocess_models import ReprocessConfig, ReprocessStatus

logger = logging.getLogger(__name__)

# Global orchestrator instance
_orchestrator: Optional[ReprocessOrchestrator] = None


def get_orchestrator(app: web.Application) -> ReprocessOrchestrator:
    """Get or create the reprocess orchestrator."""
    global _orchestrator
    if _orchestrator is None:
        # Get curriculum directory from app state
        state = app.get("state")
        if state and hasattr(state, "curriculum_dir"):
            curriculum_dir = Path(state.curriculum_dir)
        else:
            curriculum_dir = Path(__file__).parent.parent / "curriculum" / "examples" / "realistic"

        # Get curriculum storage from app state
        curriculum_storage = {}
        if state and hasattr(state, "curriculum_raw"):
            curriculum_storage = state.curriculum_raw

        _orchestrator = ReprocessOrchestrator(
            curriculum_dir=curriculum_dir,
            curriculum_storage=curriculum_storage,
        )

    return _orchestrator


def init_reprocess_system(app: web.Application):
    """Initialize the reprocessing system (call on server startup)."""
    logger.info("Initializing curriculum reprocessing system...")
    get_orchestrator(app)


# =============================================================================
# Analysis Routes
# =============================================================================

async def handle_analyze_curriculum(request: web.Request) -> web.Response:
    """
    POST /api/reprocess/analyze/{curriculum_id}

    Analyze a curriculum for quality issues.

    Request body (optional):
    {
        "force": false  // Force re-analysis even if cached
    }

    Response:
    {
        "success": true,
        "analysis": { ... }
    }
    """
    curriculum_id = request.match_info["curriculum_id"]

    try:
        # Parse request body
        force = False
        if request.can_read_body:
            try:
                body = await request.json()
                force = body.get("force", False)
            except Exception:
                pass

        orchestrator = get_orchestrator(request.app)
        analysis = await orchestrator.analyze_curriculum(curriculum_id, force=force)

        return web.json_response({
            "success": True,
            "analysis": analysis.to_dict(),
        })

    except ValueError as e:
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=404)

    except Exception as e:
        logger.exception(f"Error analyzing curriculum {curriculum_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_analysis(request: web.Request) -> web.Response:
    """
    GET /api/reprocess/analysis/{curriculum_id}

    Get cached analysis results for a curriculum.

    Response:
    {
        "success": true,
        "analysis": { ... } | null
    }
    """
    curriculum_id = request.match_info["curriculum_id"]

    try:
        orchestrator = get_orchestrator(request.app)
        analysis = orchestrator.get_cached_analysis(curriculum_id)

        if analysis:
            return web.json_response({
                "success": True,
                "analysis": analysis.to_dict(),
            })
        else:
            return web.json_response({
                "success": True,
                "analysis": None,
                "message": "No cached analysis available. Run POST /api/reprocess/analyze/{id} first.",
            })

    except Exception as e:
        logger.exception(f"Error getting analysis for {curriculum_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Job Routes
# =============================================================================

async def handle_start_job(request: web.Request) -> web.Response:
    """
    POST /api/reprocess/jobs

    Start a new reprocessing job.

    Request body:
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

    Response:
    {
        "success": true,
        "jobId": "reprocess-abc123",
        "status": "queued"
    }
    """
    try:
        body = await request.json()
        config = ReprocessConfig.from_dict(body)

        orchestrator = get_orchestrator(request.app)
        job_id = await orchestrator.start_reprocess(config)

        return web.json_response({
            "success": True,
            "jobId": job_id,
            "status": "queued",
        })

    except KeyError as e:
        return web.json_response({
            "success": False,
            "error": f"Missing required field: {e}",
        }, status=400)

    except Exception as e:
        logger.exception("Error starting reprocess job")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_list_jobs(request: web.Request) -> web.Response:
    """
    GET /api/reprocess/jobs

    List all reprocessing jobs.

    Query parameters:
    - status: Filter by status (optional)
    - curriculumId: Filter by curriculum (optional)

    Response:
    {
        "success": true,
        "jobs": [ ... ]
    }
    """
    try:
        # Parse query parameters
        status_str = request.query.get("status")
        curriculum_id = request.query.get("curriculumId")

        status = None
        if status_str:
            try:
                status = ReprocessStatus(status_str)
            except ValueError:
                pass

        orchestrator = get_orchestrator(request.app)
        jobs = orchestrator.list_jobs(status=status, curriculum_id=curriculum_id)

        # Return summary view for list
        job_summaries = []
        for job in jobs:
            job_summaries.append({
                "id": job.id,
                "curriculumId": job.config.curriculum_id,
                "status": job.status.value,
                "overallProgress": job.overall_progress,
                "currentStage": job.current_stage,
                "startedAt": job.started_at.isoformat() if job.started_at else None,
                "fixesApplied": len(job.fixes_applied),
            })

        return web.json_response({
            "success": True,
            "jobs": job_summaries,
        })

    except Exception as e:
        logger.exception("Error listing reprocess jobs")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_job(request: web.Request) -> web.Response:
    """
    GET /api/reprocess/jobs/{job_id}

    Get detailed progress for a specific job.

    Response:
    {
        "success": true,
        "progress": { ... }
    }
    """
    job_id = request.match_info["job_id"]

    try:
        orchestrator = get_orchestrator(request.app)
        progress = orchestrator.get_progress(job_id)

        if not progress:
            return web.json_response({
                "success": False,
                "error": f"Job not found: {job_id}",
            }, status=404)

        return web.json_response({
            "success": True,
            "progress": progress.to_dict(),
        })

    except Exception as e:
        logger.exception(f"Error getting job {job_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_cancel_job(request: web.Request) -> web.Response:
    """
    DELETE /api/reprocess/jobs/{job_id}

    Cancel a running reprocessing job.

    Response:
    {
        "success": true,
        "cancelled": true
    }
    """
    job_id = request.match_info["job_id"]

    try:
        orchestrator = get_orchestrator(request.app)
        cancelled = await orchestrator.cancel_job(job_id)

        if not cancelled:
            return web.json_response({
                "success": False,
                "error": f"Job not found or already completed: {job_id}",
            }, status=404)

        return web.json_response({
            "success": True,
            "cancelled": True,
        })

    except Exception as e:
        logger.exception(f"Error cancelling job {job_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Preview Route
# =============================================================================

async def handle_preview(request: web.Request) -> web.Response:
    """
    POST /api/reprocess/preview/{curriculum_id}

    Preview what changes would be made without applying them.

    Request body: Same as POST /api/reprocess/jobs but dryRun is implied.

    Response:
    {
        "success": true,
        "preview": {
            "curriculumId": "...",
            "proposedChanges": [ ... ],
            "summary": { ... }
        }
    }
    """
    curriculum_id = request.match_info["curriculum_id"]

    try:
        body = await request.json() if request.can_read_body else {}
        body["curriculumId"] = curriculum_id
        body["dryRun"] = True  # Always dry run for preview

        config = ReprocessConfig.from_dict(body)

        orchestrator = get_orchestrator(request.app)
        preview = await orchestrator.preview_reprocess(config)

        return web.json_response({
            "success": True,
            "preview": preview.to_dict(),
        })

    except ValueError as e:
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=404)

    except Exception as e:
        logger.exception(f"Error previewing reprocess for {curriculum_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Route Registration
# =============================================================================

def register_reprocess_routes(app: web.Application):
    """Register reprocessing API routes."""

    # Analysis routes
    app.router.add_post("/api/reprocess/analyze/{curriculum_id}", handle_analyze_curriculum)
    app.router.add_get("/api/reprocess/analysis/{curriculum_id}", handle_get_analysis)

    # Job routes
    app.router.add_post("/api/reprocess/jobs", handle_start_job)
    app.router.add_get("/api/reprocess/jobs", handle_list_jobs)
    app.router.add_get("/api/reprocess/jobs/{job_id}", handle_get_job)
    app.router.add_delete("/api/reprocess/jobs/{job_id}", handle_cancel_job)

    # Preview route
    app.router.add_post("/api/reprocess/preview/{curriculum_id}", handle_preview)

    logger.info("Registered reprocessing API routes")
