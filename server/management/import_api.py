"""
API routes for curriculum import sources and import jobs.

These routes power the Source Browser in the management dashboard,
enabling users to:
- Browse available curriculum sources
- Search and filter course catalogs
- Preview courses before importing
- Start and monitor import jobs
"""

import asyncio
import logging
import time
from pathlib import Path
from typing import Callable, Optional

from aiohttp import web

# Import the importer package
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from importers.core.registry import SourceRegistry, discover_handlers
from importers.core.orchestrator import ImportOrchestrator
from importers.core.models import ImportConfig, ImportStatus

# Import diagnostic logging
from diagnostic_logging import diag_logger, TimingContext

logger = logging.getLogger(__name__)

# Global orchestrator instance
_orchestrator: Optional[ImportOrchestrator] = None

# Reference to the aiohttp app for database access
_app: Optional[web.Application] = None

# Callback to reload curricula after import (set by server.py)
_on_import_complete_callback: Optional[Callable] = None


def set_import_complete_callback(callback: Callable):
    """Set callback to be called when an import completes."""
    global _on_import_complete_callback
    _on_import_complete_callback = callback


async def _record_imported_course(progress) -> None:
    """Record a completed import in the database for tracking."""
    global _app
    if _app is None or "db_pool" not in _app:
        logger.warning("Database pool not available, skipping import tracking")
        return

    try:
        pool = _app["db_pool"]
        async with pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO imported_courses (source_id, course_id, curriculum_id, import_job_id)
                VALUES ($1, $2, $3::uuid, $4)
                ON CONFLICT (source_id, course_id) DO UPDATE SET
                    curriculum_id = EXCLUDED.curriculum_id,
                    import_job_id = EXCLUDED.import_job_id,
                    imported_at = NOW()
                """,
                progress.config.source_id,
                progress.config.course_id,
                progress.result.curriculum_id if progress.result else None,
                progress.id,
            )
            logger.info(
                f"Recorded imported course: {progress.config.source_id}/{progress.config.course_id}"
            )
    except Exception as e:
        logger.error(f"Failed to record imported course: {e}")


def _handle_import_progress(progress):
    """Handle import progress updates. Trigger reload and tracking on completion."""
    from importers.core.models import ImportStatus

    if progress.status == ImportStatus.COMPLETE:
        logger.info(f"Import {progress.id} completed, triggering curriculum reload")

        # Record the import in the database (async operation)
        if _app is not None:
            asyncio.create_task(_record_imported_course(progress))

        if _on_import_complete_callback:
            try:
                _on_import_complete_callback(progress)
            except Exception as e:
                logger.error(f"Error in import complete callback: {e}")


def get_orchestrator() -> ImportOrchestrator:
    """Get or create the import orchestrator."""
    global _orchestrator
    if _orchestrator is None:
        output_dir = Path(__file__).parent.parent / "importers" / "output"
        _orchestrator = ImportOrchestrator(output_dir=output_dir)
        # Register progress callback to detect completion
        _orchestrator.add_progress_callback(_handle_import_progress)
    return _orchestrator


def init_import_system():
    """Initialize the import system (call on server startup)."""
    logger.info("Initializing curriculum import system...")
    discover_handlers()
    sources = SourceRegistry.list_source_ids()
    logger.info(f"Registered sources: {sources}")
    # Initialize the orchestrator to register callbacks
    get_orchestrator()


# =============================================================================
# Source Routes
# =============================================================================

async def handle_get_sources(request: web.Request) -> web.Response:
    """
    GET /api/import/sources

    Get list of all registered curriculum sources.
    """
    try:
        sources = SourceRegistry.get_all_sources()
        return web.json_response({
            "success": True,
            "sources": [s.to_dict() for s in sources],
        })
    except Exception as e:
        logger.exception("Error getting sources")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_source(request: web.Request) -> web.Response:
    """
    GET /api/import/sources/{source_id}

    Get details for a specific source.
    """
    source_id = request.match_info["source_id"]

    try:
        handler = SourceRegistry.get_handler(source_id)
        if not handler:
            return web.json_response({
                "success": False,
                "error": f"Source not found: {source_id}",
            }, status=404)

        return web.json_response({
            "success": True,
            "source": handler.source_info.to_dict(),
        })
    except Exception as e:
        logger.exception(f"Error getting source {source_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Course Catalog Routes
# =============================================================================

async def handle_get_courses(request: web.Request) -> web.Response:
    """
    GET /api/import/sources/{source_id}/courses

    Get course catalog for a source.

    Query parameters:
    - page: Page number (default: 1)
    - pageSize: Items per page (default: 20)
    - search: Search query
    - subject: Subject filter
    - level: Level filter
    - features: Feature filter (comma-separated)
    - sortBy: Sort field (title, level, date, relevance)
    - sortOrder: Sort direction (asc, desc)
    """
    source_id = request.match_info["source_id"]

    try:
        handler = SourceRegistry.get_handler(source_id)
        if not handler:
            return web.json_response({
                "success": False,
                "error": f"Source not found: {source_id}",
            }, status=404)

        # Parse query parameters
        page = int(request.query.get("page", "1"))
        page_size = int(request.query.get("pageSize", "20"))
        search = request.query.get("search")
        sort_by = request.query.get("sortBy", "relevance")
        sort_order = request.query.get("sortOrder", "asc")

        filters = {}
        if request.query.get("subject"):
            filters["subject"] = request.query["subject"]
        if request.query.get("level"):
            filters["level"] = request.query["level"]
        if request.query.get("features"):
            filters["features"] = request.query["features"].split(",")

        # Get courses
        courses, total, filter_options = await handler.get_course_catalog(
            page=page,
            page_size=page_size,
            filters=filters if filters else None,
            search=search,
        )

        # Apply sorting (handlers return courses, we sort them here)
        if courses and sort_by != "relevance":
            reverse = sort_order == "desc"
            if sort_by == "title":
                courses = sorted(courses, key=lambda c: c.title.lower(), reverse=reverse)
            elif sort_by == "level":
                # Sort by level with a defined order
                level_order = {
                    "undergraduate": 1, "graduate": 2, "high school": 0,
                    "introductory": 1, "intermediate": 2, "advanced": 3,
                }
                courses = sorted(
                    courses,
                    key=lambda c: level_order.get(c.level.lower() if c.level else "", 99),
                    reverse=reverse
                )
            elif sort_by == "date":
                # Sort by ID as a proxy for date (newer courses have higher IDs typically)
                courses = sorted(courses, key=lambda c: c.id, reverse=reverse)

        return web.json_response({
            "success": True,
            "courses": [c.to_dict() for c in courses],
            "pagination": {
                "page": page,
                "pageSize": page_size,
                "total": total,
                "totalPages": (total + page_size - 1) // page_size,
            },
            "filters": filter_options,
        })
    except Exception as e:
        logger.exception(f"Error getting courses for {source_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_search_courses(request: web.Request) -> web.Response:
    """
    GET /api/import/sources/{source_id}/search

    Search courses by query.

    Query parameters:
    - q: Search query (required)
    - limit: Max results (default: 20)
    """
    source_id = request.match_info["source_id"]

    try:
        handler = SourceRegistry.get_handler(source_id)
        if not handler:
            return web.json_response({
                "success": False,
                "error": f"Source not found: {source_id}",
            }, status=404)

        query = request.query.get("q", "")
        limit = int(request.query.get("limit", "20"))

        if not query:
            return web.json_response({
                "success": False,
                "error": "Search query required",
            }, status=400)

        courses = await handler.search_courses(query=query, limit=limit)

        return web.json_response({
            "success": True,
            "courses": [c.to_dict() for c in courses],
            "query": query,
        })
    except Exception as e:
        logger.exception(f"Error searching courses for {source_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_course_detail(request: web.Request) -> web.Response:
    """
    GET /api/import/sources/{source_id}/courses/{course_id}

    Get full details for a specific course.
    """
    source_id = request.match_info["source_id"]
    course_id = request.match_info["course_id"]

    try:
        handler = SourceRegistry.get_handler(source_id)
        if not handler:
            return web.json_response({
                "success": False,
                "error": f"Source not found: {source_id}",
            }, status=404)

        # Validate license first
        license_result = handler.validate_license(course_id)

        # Get course detail
        try:
            detail = await handler.get_course_detail(course_id)
        except ValueError as e:
            return web.json_response({
                "success": False,
                "error": str(e),
            }, status=404)

        return web.json_response({
            "success": True,
            "course": detail.to_dict(),
            "canImport": license_result.can_import,
            "licenseWarnings": license_result.warnings,
            "attribution": license_result.attribution_text,
        })
    except Exception as e:
        logger.exception(f"Error getting course detail {source_id}/{course_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Import Job Routes
# =============================================================================

async def handle_start_import(request: web.Request) -> web.Response:
    """
    POST /api/import/jobs

    Start a new import job.

    Request body:
    {
        "sourceId": "mit_ocw",
        "courseId": "6-001-spring-2005",
        "outputName": "sicp-6001",
        "selectedLectures": ["lecture-1", "lecture-2"],  // Optional
        "includeTranscripts": true,
        "includeLectureNotes": true,
        "includeAssignments": true,
        "includeExams": true,
        "includeVideos": false,
        "generateObjectives": true,
        "createCheckpoints": true,
        "generateSpokenText": true,
        "buildKnowledgeGraph": true,
        "generatePracticeProblems": false
    }
    """
    start_time = time.time()
    diag_logger.separator("IMPORT JOB REQUEST")

    try:
        data = await request.json()
        diag_logger.info("Import request received", context={
            "sourceId": data.get("sourceId"),
            "courseId": data.get("courseId"),
            "selectedLectures": data.get("selectedLectures", []),
            "client_ip": request.remote
        })

        # Parse config
        config = ImportConfig.from_dict(data)
        diag_logger.debug("ImportConfig parsed successfully", context={
            "source_id": config.source_id,
            "course_id": config.course_id,
            "selected_lectures_count": len(config.selected_lectures),
            "include_transcripts": config.include_transcripts,
            "include_videos": config.include_videos
        })

        # Validate source exists
        handler = SourceRegistry.get_handler(config.source_id)
        if not handler:
            diag_logger.warning(f"Source not found: {config.source_id}")
            return web.json_response({
                "success": False,
                "error": f"Source not found: {config.source_id}",
            }, status=404)

        diag_logger.debug(f"Source handler found: {handler.source_info.name}")

        # Validate license
        license_result = handler.validate_license(config.course_id)
        if not license_result.can_import:
            diag_logger.warning("License validation failed", context={
                "course_id": config.course_id,
                "warnings": license_result.warnings
            })
            return web.json_response({
                "success": False,
                "error": f"Cannot import: {license_result.warnings[0]}",
                "licenseRestriction": True,
            }, status=403)

        diag_logger.debug("License validation passed")

        # Start import
        orchestrator = get_orchestrator()
        job_id = await orchestrator.start_import(config)

        duration_ms = (time.time() - start_time) * 1000
        diag_logger.info("Import job started successfully", context={
            "job_id": job_id,
            "duration_ms": round(duration_ms, 2)
        })

        return web.json_response({
            "success": True,
            "jobId": job_id,
            "status": "queued",
        })
    except Exception as e:
        duration_ms = (time.time() - start_time) * 1000
        diag_logger.exception("Error starting import", context={
            "error": str(e),
            "duration_ms": round(duration_ms, 2)
        })
        logger.exception("Error starting import")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_import_progress(request: web.Request) -> web.Response:
    """
    GET /api/import/jobs/{job_id}

    Get progress for an import job.
    """
    job_id = request.match_info["job_id"]

    try:
        orchestrator = get_orchestrator()
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
        logger.exception(f"Error getting import progress {job_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_list_imports(request: web.Request) -> web.Response:
    """
    GET /api/import/jobs

    List all import jobs.

    Query parameters:
    - status: Filter by status (optional)
    """
    try:
        orchestrator = get_orchestrator()

        status_filter = request.query.get("status")
        if status_filter:
            try:
                status = ImportStatus(status_filter)
            except ValueError:
                return web.json_response({
                    "success": False,
                    "error": f"Invalid status: {status_filter}",
                }, status=400)
            jobs = orchestrator.list_jobs(status=status)
        else:
            jobs = orchestrator.list_jobs()

        return web.json_response({
            "success": True,
            "jobs": [j.to_dict() for j in jobs],
        })
    except Exception as e:
        logger.exception("Error listing imports")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_cancel_import(request: web.Request) -> web.Response:
    """
    DELETE /api/import/jobs/{job_id}

    Cancel an import job.
    """
    job_id = request.match_info["job_id"]

    try:
        orchestrator = get_orchestrator()
        cancelled = await orchestrator.cancel_import(job_id)

        if not cancelled:
            return web.json_response({
                "success": False,
                "error": f"Could not cancel job: {job_id}",
            }, status=400)

        return web.json_response({
            "success": True,
            "cancelled": True,
        })
    except Exception as e:
        logger.exception(f"Error cancelling import {job_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Import Status Routes
# =============================================================================

async def handle_get_import_status(request: web.Request) -> web.Response:
    """
    GET /api/import/status

    Query which courses have been imported.

    Query parameters:
    - source_id: Source ID (required)
    - course_ids: Comma-separated list of course IDs to check

    Returns import status for the requested courses.
    """
    try:
        source_id = request.query.get("source_id")
        course_ids_param = request.query.get("course_ids", "")

        if not source_id:
            return web.json_response({
                "success": False,
                "error": "source_id is required",
            }, status=400)

        course_ids = [c.strip() for c in course_ids_param.split(",") if c.strip()]

        if "db_pool" not in request.app:
            return web.json_response({
                "success": False,
                "error": "Database not available",
            }, status=503)

        pool = request.app["db_pool"]
        async with pool.acquire() as conn:
            if course_ids:
                # Query specific courses
                rows = await conn.fetch(
                    """
                    SELECT course_id, curriculum_id, imported_at
                    FROM imported_courses
                    WHERE source_id = $1 AND course_id = ANY($2)
                    """,
                    source_id,
                    course_ids,
                )
            else:
                # Query all courses for this source
                rows = await conn.fetch(
                    """
                    SELECT course_id, curriculum_id, imported_at
                    FROM imported_courses
                    WHERE source_id = $1
                    """,
                    source_id,
                )

        # Build response
        courses = {}
        for row in rows:
            courses[row["course_id"]] = {
                "imported": True,
                "curriculumId": str(row["curriculum_id"]) if row["curriculum_id"] else None,
                "importedAt": row["imported_at"].isoformat() if row["imported_at"] else None,
            }

        # Add entries for requested courses that aren't imported
        for course_id in course_ids:
            if course_id not in courses:
                courses[course_id] = {"imported": False}

        return web.json_response({
            "success": True,
            "courses": courses,
        })

    except Exception as e:
        logger.exception("Error querying import status")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Route Registration
# =============================================================================

def register_import_routes(app: web.Application):
    """Register all import-related routes on the application."""
    global _app
    _app = app  # Store app reference for database access in callbacks

    # Initialize import system
    init_import_system()

    # Sources
    app.router.add_get("/api/import/sources", handle_get_sources)
    app.router.add_get("/api/import/sources/{source_id}", handle_get_source)

    # Course catalog
    app.router.add_get("/api/import/sources/{source_id}/courses", handle_get_courses)
    app.router.add_get("/api/import/sources/{source_id}/search", handle_search_courses)
    app.router.add_get("/api/import/sources/{source_id}/courses/{course_id}", handle_get_course_detail)

    # Import jobs
    app.router.add_post("/api/import/jobs", handle_start_import)
    app.router.add_get("/api/import/jobs", handle_list_imports)
    app.router.add_get("/api/import/jobs/{job_id}", handle_get_import_progress)
    app.router.add_delete("/api/import/jobs/{job_id}", handle_cancel_import)

    # Import status (tracking which courses have been imported)
    app.router.add_get("/api/import/status", handle_get_import_status)

    logger.info("Import API routes registered")
