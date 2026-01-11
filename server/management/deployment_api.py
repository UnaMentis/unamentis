# Scheduled Deployment API
# Pre-generation of entire curricula before scheduled deployments

import asyncio
import logging
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional

from aiohttp import web

from fov_context import UserVoiceConfig
from tts_cache import TTSCache, TTSCacheKey, TTSResourcePool, Priority

logger = logging.getLogger(__name__)


class DeploymentStatus(str, Enum):
    """Status of a scheduled deployment."""
    SCHEDULED = "scheduled"
    GENERATING = "generating"
    COMPLETED = "completed"
    COMPLETED_WITH_ERRORS = "completed_with_errors"
    CANCELLED = "cancelled"
    FAILED = "failed"


@dataclass
class ScheduledDeployment:
    """A scheduled curriculum deployment with pre-generation.

    Represents an admin-scheduled training deployment where TTS audio
    should be pre-generated before the target date.
    """
    id: str
    name: str
    curriculum_id: str
    target_date: datetime
    voice_config: UserVoiceConfig

    # Status tracking
    status: DeploymentStatus = DeploymentStatus.SCHEDULED
    total_segments: int = 0
    completed_segments: int = 0
    cached_segments: int = 0      # Already in cache (free!)
    generated_segments: int = 0   # Newly generated
    failed_segments: int = 0

    # Timing
    created_at: datetime = field(default_factory=datetime.now)
    generation_started_at: Optional[datetime] = None
    generation_completed_at: Optional[datetime] = None

    # Error tracking
    error: Optional[str] = None
    failed_segment_indices: List[int] = field(default_factory=list)

    @property
    def percent_complete(self) -> float:
        if self.total_segments == 0:
            return 100.0
        return (self.completed_segments / self.total_segments) * 100

    @property
    def is_ready(self) -> bool:
        """Check if deployment is ready (all segments cached)."""
        return self.status == DeploymentStatus.COMPLETED and self.failed_segments == 0

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "id": self.id,
            "name": self.name,
            "curriculum_id": self.curriculum_id,
            "target_date": self.target_date.isoformat(),
            "voice_config": self.voice_config.to_dict(),
            "status": self.status.value,
            "total_segments": self.total_segments,
            "completed_segments": self.completed_segments,
            "cached_segments": self.cached_segments,
            "generated_segments": self.generated_segments,
            "failed_segments": self.failed_segments,
            "percent_complete": round(self.percent_complete, 1),
            "is_ready": self.is_ready,
            "created_at": self.created_at.isoformat(),
            "generation_started_at": self.generation_started_at.isoformat() if self.generation_started_at else None,
            "generation_completed_at": self.generation_completed_at.isoformat() if self.generation_completed_at else None,
            "error": self.error,
        }


class ScheduledDeploymentManager:
    """Manages pre-generation of entire curricula for scheduled deployments.

    Features:
    - Schedule deployments with target dates
    - Background pre-generation using SCHEDULED priority
    - Progress tracking and status monitoring
    - Cache coverage verification
    - Cancellation support

    Usage:
        manager = ScheduledDeploymentManager(cache, resource_pool)

        # Schedule a deployment
        deployment = await manager.schedule_deployment(
            name="Security Training 2024",
            curriculum_id="security-2024",
            target_date=datetime(2024, 3, 1, 9, 0),
            voice_config=UserVoiceConfig(voice_id="nova")
        )

        # Start generation (or wait for automatic start)
        await manager.start_generation(deployment.id)

        # Check status
        status = manager.get_deployment(deployment.id)
    """

    def __init__(
        self,
        cache: TTSCache,
        resource_pool: TTSResourcePool,
        auto_start_hours_before: int = 24,
    ):
        """Initialize deployment manager.

        Args:
            cache: Global TTS cache
            resource_pool: TTS resource pool
            auto_start_hours_before: Hours before target date to auto-start generation
        """
        self.cache = cache
        self.resource_pool = resource_pool
        self.auto_start_hours = auto_start_hours_before

        # Deployments: id -> (deployment, task)
        self._deployments: Dict[str, tuple[ScheduledDeployment, Optional[asyncio.Task]]] = {}

        # Curriculum segment loader (set by server.py)
        self._segment_loader: Optional[callable] = None

    def set_segment_loader(self, loader: callable) -> None:
        """Set the function to load curriculum segments.

        Args:
            loader: async function(curriculum_id) -> List[str]
        """
        self._segment_loader = loader

    async def schedule_deployment(
        self,
        name: str,
        curriculum_id: str,
        target_date: datetime,
        voice_config: Optional[UserVoiceConfig] = None,
        auto_start: bool = True,
    ) -> ScheduledDeployment:
        """Schedule a new deployment for pre-generation.

        Args:
            name: Human-readable deployment name
            curriculum_id: Curriculum to pre-generate
            target_date: When the training is scheduled
            voice_config: Voice configuration (default nova/vibevoice)
            auto_start: Whether to auto-start generation before target date

        Returns:
            The created deployment
        """
        deployment_id = f"deploy_{uuid.uuid4().hex[:8]}"

        deployment = ScheduledDeployment(
            id=deployment_id,
            name=name,
            curriculum_id=curriculum_id,
            target_date=target_date,
            voice_config=voice_config or UserVoiceConfig(),
        )

        self._deployments[deployment_id] = (deployment, None)

        logger.info(
            f"Scheduled deployment {deployment_id}: {name} for {curriculum_id}, "
            f"target date {target_date.isoformat()}"
        )

        return deployment

    async def start_generation(self, deployment_id: str) -> bool:
        """Start pre-generation for a deployment.

        Args:
            deployment_id: Deployment to start

        Returns:
            True if started, False if not found or already running
        """
        if deployment_id not in self._deployments:
            return False

        deployment, task = self._deployments[deployment_id]

        if task and not task.done():
            logger.warning(f"Deployment {deployment_id} already running")
            return False

        if deployment.status in (DeploymentStatus.COMPLETED, DeploymentStatus.COMPLETED_WITH_ERRORS):
            logger.warning(f"Deployment {deployment_id} already completed")
            return False

        # Start generation task
        task = asyncio.create_task(self._run_generation(deployment))
        self._deployments[deployment_id] = (deployment, task)

        logger.info(f"Started generation for deployment {deployment_id}")
        return True

    async def cancel_deployment(self, deployment_id: str) -> bool:
        """Cancel a deployment and stop generation.

        Args:
            deployment_id: Deployment to cancel

        Returns:
            True if cancelled, False if not found
        """
        if deployment_id not in self._deployments:
            return False

        deployment, task = self._deployments[deployment_id]

        if task and not task.done():
            task.cancel()

        deployment.status = DeploymentStatus.CANCELLED
        logger.info(f"Cancelled deployment {deployment_id}")
        return True

    def get_deployment(self, deployment_id: str) -> Optional[ScheduledDeployment]:
        """Get a deployment by ID."""
        if deployment_id in self._deployments:
            deployment, _ = self._deployments[deployment_id]
            return deployment
        return None

    def list_deployments(self) -> List[ScheduledDeployment]:
        """List all deployments."""
        return [d for d, _ in self._deployments.values()]

    async def get_cache_coverage(self, deployment_id: str) -> Optional[dict]:
        """Get cache coverage for a deployment.

        Returns:
            Dict with coverage statistics, or None if not found
        """
        if deployment_id not in self._deployments:
            return None

        deployment, _ = self._deployments[deployment_id]

        if not self._segment_loader:
            return {"error": "Segment loader not configured"}

        # Load segments
        segments = await self._segment_loader(deployment.curriculum_id)
        if not segments:
            return {"error": "No segments found"}

        # Check cache coverage
        cached_count = 0
        voice_config = deployment.voice_config

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

        total = len(segments)
        coverage = (cached_count / total * 100) if total > 0 else 100.0

        return {
            "deployment_id": deployment_id,
            "curriculum_id": deployment.curriculum_id,
            "total_segments": total,
            "cached_segments": cached_count,
            "missing_segments": total - cached_count,
            "coverage_percent": round(coverage, 1),
            "is_ready": cached_count == total,
        }

    async def _run_generation(self, deployment: ScheduledDeployment) -> None:
        """Internal: Run pre-generation for a deployment."""
        deployment.status = DeploymentStatus.GENERATING
        deployment.generation_started_at = datetime.now()

        try:
            if not self._segment_loader:
                raise ValueError("Segment loader not configured")

            # Load segments
            segments = await self._segment_loader(deployment.curriculum_id)
            if not segments:
                raise ValueError(f"No segments found for curriculum {deployment.curriculum_id}")

            deployment.total_segments = len(segments)
            voice_config = deployment.voice_config

            logger.info(
                f"Starting generation for deployment {deployment.id}: "
                f"{len(segments)} segments"
            )

            for i, text in enumerate(segments):
                # Check if cancelled
                if deployment.status == DeploymentStatus.CANCELLED:
                    break

                key = TTSCacheKey.from_request(
                    text=text,
                    voice_id=voice_config.voice_id,
                    provider=voice_config.tts_provider,
                    speed=voice_config.speed,
                    exaggeration=voice_config.exaggeration,
                    cfg_weight=voice_config.cfg_weight,
                    language=voice_config.language,
                )

                # Check if already cached
                if await self.cache.has(key):
                    deployment.cached_segments += 1
                    deployment.completed_segments += 1
                    continue

                # Generate with SCHEDULED priority (low, won't starve live users)
                try:
                    audio_data, sample_rate, duration = await self.resource_pool.generate_with_priority(
                        text=text,
                        voice_id=voice_config.voice_id,
                        provider=voice_config.tts_provider,
                        speed=voice_config.speed,
                        chatterbox_config=voice_config.get_chatterbox_config(),
                        priority=Priority.SCHEDULED,
                    )

                    await self.cache.put(key, audio_data, sample_rate, duration)
                    deployment.generated_segments += 1
                    deployment.completed_segments += 1

                except asyncio.CancelledError:
                    deployment.status = DeploymentStatus.CANCELLED
                    break
                except Exception as e:
                    logger.warning(f"Failed to generate segment {i} for deployment {deployment.id}: {e}")
                    deployment.failed_segments += 1
                    deployment.completed_segments += 1
                    deployment.failed_segment_indices.append(i)

            # Mark complete
            if deployment.status != DeploymentStatus.CANCELLED:
                if deployment.failed_segments > 0:
                    deployment.status = DeploymentStatus.COMPLETED_WITH_ERRORS
                else:
                    deployment.status = DeploymentStatus.COMPLETED

            deployment.generation_completed_at = datetime.now()

            logger.info(
                f"Deployment {deployment.id} generation complete: "
                f"{deployment.generated_segments} generated, "
                f"{deployment.cached_segments} cached, "
                f"{deployment.failed_segments} failed"
            )

        except asyncio.CancelledError:
            deployment.status = DeploymentStatus.CANCELLED
            deployment.generation_completed_at = datetime.now()
        except Exception as e:
            deployment.status = DeploymentStatus.FAILED
            deployment.error = str(e)
            deployment.generation_completed_at = datetime.now()
            logger.error(f"Deployment {deployment.id} failed: {e}")

    def cleanup_old_deployments(self, max_age_days: int = 30) -> int:
        """Remove completed deployments older than max_age.

        Returns:
            Number of deployments removed
        """
        now = datetime.now()
        removed = 0

        for deployment_id in list(self._deployments.keys()):
            deployment, _ = self._deployments[deployment_id]

            if deployment.status in (
                DeploymentStatus.COMPLETED,
                DeploymentStatus.COMPLETED_WITH_ERRORS,
                DeploymentStatus.CANCELLED,
                DeploymentStatus.FAILED,
            ):
                if deployment.generation_completed_at:
                    age_days = (now - deployment.generation_completed_at).days
                    if age_days > max_age_days:
                        del self._deployments[deployment_id]
                        removed += 1

        return removed


# =============================================================================
# API Endpoints
# =============================================================================


async def handle_create_deployment(request: web.Request) -> web.Response:
    """
    POST /api/deployments

    Schedule a new curriculum deployment.

    Request body:
    {
        "name": "Security Training 2024",
        "curriculum_id": "security-2024",
        "target_date": "2024-03-01T09:00:00Z",
        "voice_config": {
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": 1.0
        }
    }
    """
    try:
        data = await request.json()
    except Exception:
        return web.json_response({"error": "Invalid JSON body"}, status=400)

    name = data.get("name")
    curriculum_id = data.get("curriculum_id")
    target_date_str = data.get("target_date")

    if not name or not curriculum_id or not target_date_str:
        return web.json_response(
            {"error": "Missing required fields: name, curriculum_id, target_date"},
            status=400,
        )

    try:
        target_date = datetime.fromisoformat(target_date_str.replace("Z", "+00:00"))
    except ValueError:
        return web.json_response({"error": "Invalid target_date format"}, status=400)

    # Parse voice config
    voice_config = None
    if "voice_config" in data:
        vc = data["voice_config"]
        voice_config = UserVoiceConfig(
            voice_id=vc.get("voice_id", "nova"),
            tts_provider=vc.get("tts_provider", "vibevoice"),
            speed=vc.get("speed", 1.0),
            exaggeration=vc.get("exaggeration"),
            cfg_weight=vc.get("cfg_weight"),
            language=vc.get("language"),
        )

    manager: ScheduledDeploymentManager = request.app.get("deployment_manager")
    if not manager:
        return web.json_response({"error": "Deployment manager not initialized"}, status=503)

    deployment = await manager.schedule_deployment(
        name=name,
        curriculum_id=curriculum_id,
        target_date=target_date,
        voice_config=voice_config,
    )

    return web.json_response({
        "status": "scheduled",
        "deployment": deployment.to_dict(),
    })


async def handle_list_deployments(request: web.Request) -> web.Response:
    """
    GET /api/deployments

    List all deployments.
    """
    manager: ScheduledDeploymentManager = request.app.get("deployment_manager")
    if not manager:
        return web.json_response({"error": "Deployment manager not initialized"}, status=503)

    deployments = manager.list_deployments()
    return web.json_response({
        "deployments": [d.to_dict() for d in deployments],
    })


async def handle_get_deployment(request: web.Request) -> web.Response:
    """
    GET /api/deployments/{id}

    Get deployment status and progress.
    """
    deployment_id = request.match_info.get("id")
    if not deployment_id:
        return web.json_response({"error": "Missing deployment id"}, status=400)

    manager: ScheduledDeploymentManager = request.app.get("deployment_manager")
    if not manager:
        return web.json_response({"error": "Deployment manager not initialized"}, status=503)

    deployment = manager.get_deployment(deployment_id)
    if not deployment:
        return web.json_response({"error": f"Deployment not found: {deployment_id}"}, status=404)

    return web.json_response({"deployment": deployment.to_dict()})


async def handle_start_deployment(request: web.Request) -> web.Response:
    """
    POST /api/deployments/{id}/start

    Manually start generation for a deployment.
    """
    deployment_id = request.match_info.get("id")
    if not deployment_id:
        return web.json_response({"error": "Missing deployment id"}, status=400)

    manager: ScheduledDeploymentManager = request.app.get("deployment_manager")
    if not manager:
        return web.json_response({"error": "Deployment manager not initialized"}, status=503)

    started = await manager.start_generation(deployment_id)
    if not started:
        return web.json_response(
            {"error": f"Could not start deployment {deployment_id}"},
            status=400,
        )

    return web.json_response({"status": "started", "deployment_id": deployment_id})


async def handle_cancel_deployment(request: web.Request) -> web.Response:
    """
    DELETE /api/deployments/{id}

    Cancel a deployment.
    """
    deployment_id = request.match_info.get("id")
    if not deployment_id:
        return web.json_response({"error": "Missing deployment id"}, status=400)

    manager: ScheduledDeploymentManager = request.app.get("deployment_manager")
    if not manager:
        return web.json_response({"error": "Deployment manager not initialized"}, status=503)

    cancelled = await manager.cancel_deployment(deployment_id)
    if not cancelled:
        return web.json_response(
            {"error": f"Deployment not found: {deployment_id}"},
            status=404,
        )

    return web.json_response({"status": "cancelled", "deployment_id": deployment_id})


async def handle_get_deployment_cache(request: web.Request) -> web.Response:
    """
    GET /api/deployments/{id}/cache

    Get cache coverage for a deployment.
    """
    deployment_id = request.match_info.get("id")
    if not deployment_id:
        return web.json_response({"error": "Missing deployment id"}, status=400)

    manager: ScheduledDeploymentManager = request.app.get("deployment_manager")
    if not manager:
        return web.json_response({"error": "Deployment manager not initialized"}, status=503)

    coverage = await manager.get_cache_coverage(deployment_id)
    if not coverage:
        return web.json_response(
            {"error": f"Deployment not found: {deployment_id}"},
            status=404,
        )

    if "error" in coverage:
        return web.json_response({"error": coverage["error"]}, status=500)

    return web.json_response(coverage)


def register_deployment_routes(app: web.Application) -> None:
    """Register deployment API routes."""
    logger.info("Registering deployment API routes...")

    app.router.add_post("/api/deployments", handle_create_deployment)
    app.router.add_get("/api/deployments", handle_list_deployments)
    app.router.add_get("/api/deployments/{id}", handle_get_deployment)
    app.router.add_post("/api/deployments/{id}/start", handle_start_deployment)
    app.router.add_delete("/api/deployments/{id}", handle_cancel_deployment)
    app.router.add_get("/api/deployments/{id}/cache", handle_get_deployment_cache)

    logger.info("Deployment API routes registered")
