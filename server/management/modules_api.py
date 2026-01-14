"""
Modules API - Server-driven training module system.

Provides endpoints for module discovery and download:
- GET /api/modules - List available modules
- GET /api/modules/{module_id} - Get module details
- POST /api/modules/{module_id}/download - Download full module content

Modules are server-controlled:
- Server defines which modules are available
- Clients discover modules via API
- Downloaded modules include full content for offline operation
"""

import asyncio
import json
import logging
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, TYPE_CHECKING

from aiohttp import web

if TYPE_CHECKING:
    from tts_cache.kb_audio import KBAudioManager

logger = logging.getLogger(__name__)

# Data directory for module storage
DATA_DIR = Path(__file__).parent / "data"
MODULES_DIR = DATA_DIR / "modules"


def get_modules_registry_path() -> Path:
    """Get path to modules registry file."""
    return MODULES_DIR / "registry.json"


def validate_module_id(module_id: str) -> bool:
    """Validate module_id to prevent path traversal attacks.

    Module IDs must be alphanumeric with hyphens and underscores only.
    """
    if not module_id:
        return False
    return bool(re.match(r'^[a-zA-Z0-9_-]+$', module_id))


def get_module_content_path(module_id: str) -> Path:
    """Get path to module content file.

    Raises ValueError if module_id contains path traversal attempts.
    """
    if not validate_module_id(module_id):
        raise ValueError(f"Invalid module_id: {module_id}")

    content_path = MODULES_DIR / f"{module_id}.json"

    # Resolve to absolute path and verify it's within MODULES_DIR
    resolved = content_path.resolve()
    modules_resolved = MODULES_DIR.resolve()
    if not str(resolved).startswith(str(modules_resolved)):
        raise ValueError(f"Path traversal detected in module_id: {module_id}")

    return content_path


def ensure_modules_directory():
    """Ensure modules directory exists."""
    MODULES_DIR.mkdir(parents=True, exist_ok=True)


def load_modules_registry() -> dict[str, Any]:
    """Load the modules registry from disk."""
    registry_path = get_modules_registry_path()
    if not registry_path.exists():
        return {"modules": [], "version": "1.0.0"}

    try:
        with open(registry_path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load modules registry: {e}")
        return {"modules": [], "version": "1.0.0"}


def save_modules_registry(registry: dict[str, Any]):
    """Save the modules registry to disk."""
    ensure_modules_directory()
    registry_path = get_modules_registry_path()

    try:
        with open(registry_path, "w", encoding="utf-8") as f:
            json.dump(registry, f, indent=2)
        logger.info(f"Saved modules registry with {len(registry.get('modules', []))} modules")
    except Exception as e:
        logger.error(f"Failed to save modules registry: {e}")


def load_module_content(module_id: str) -> Optional[Dict[str, Any]]:
    """Load full module content from disk."""
    content_path = get_module_content_path(module_id)
    if not content_path.exists():
        return None

    try:
        with open(content_path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load module content for {module_id}: {e}")
        return None


def save_module_content(module_id: str, content: dict[str, Any]):
    """Save full module content to disk."""
    ensure_modules_directory()
    content_path = get_module_content_path(module_id)

    try:
        with open(content_path, "w", encoding="utf-8") as f:
            json.dump(content, f, indent=2)
        logger.info(f"Saved module content for {module_id}")
    except Exception as e:
        logger.error(f"Failed to save module content for {module_id}: {e}")


# API Handlers


def resolve_feature_flags(module: dict) -> dict:
    """Resolve effective feature flags by applying overrides to base flags.

    Feature flags work as follows:
    - Base flags (supports_team_mode, etc.) define module capabilities
    - Feature overrides can disable specific features per deployment
    - A feature is enabled only if base flag is True AND override is not False
    """
    overrides = module.get("feature_overrides", {})
    return {
        "supports_team_mode": module.get("supports_team_mode", False) and overrides.get("team_mode", True),
        "supports_speed_training": module.get("supports_speed_training", False) and overrides.get("speed_training", True),
        "supports_competition_sim": module.get("supports_competition_sim", False) and overrides.get("competition_sim", True),
    }


async def handle_list_modules(request: web.Request) -> web.Response:
    """GET /api/modules

    List all available modules with summary information.

    Query params:
    - include_disabled: If "true", include disabled modules (admin only)

    Response:
    {
        "modules": [
            {
                "id": "knowledge-bowl",
                "name": "Knowledge Bowl",
                "description": "...",
                "icon_name": "brain.head.profile",
                "theme_color_hex": "#9B59B6",
                "version": "1.0.0",
                "enabled": true,
                "supports_team_mode": true,
                "supports_speed_training": true,
                "supports_competition_sim": true,
                "download_size": 1048576
            }
        ],
        "server_version": "1.0.0"
    }
    """
    try:
        registry = load_modules_registry()
        include_disabled = request.query.get("include_disabled", "").lower() == "true"

        # Build summary list (without full content)
        modules_summary = []
        for module in registry.get("modules", []):
            # Skip disabled modules unless explicitly requested
            is_enabled = module.get("enabled", True)
            if not is_enabled and not include_disabled:
                continue

            # Resolve effective feature flags
            features = resolve_feature_flags(module)

            modules_summary.append({
                "id": module["id"],
                "name": module["name"],
                "description": module["description"],
                "icon_name": module["icon_name"],
                "theme_color_hex": module["theme_color_hex"],
                "version": module["version"],
                "enabled": is_enabled,
                "supports_team_mode": features["supports_team_mode"],
                "supports_speed_training": features["supports_speed_training"],
                "supports_competition_sim": features["supports_competition_sim"],
                "download_size": module.get("download_size"),
            })

        return web.json_response({
            "modules": modules_summary,
            "server_version": registry.get("version", "1.0.0"),
        })

    except Exception as e:
        logger.exception("Error listing modules")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_module(request: web.Request) -> web.Response:
    """GET /api/modules/{module_id}

    Get detailed information about a specific module.

    Response includes domains and study modes but NOT full question content.
    """
    module_id = request.match_info["module_id"]

    if not validate_module_id(module_id):
        return web.json_response(
            {"error": f"Invalid module_id: {module_id}"},
            status=400
        )

    try:
        registry = load_modules_registry()

        # Find module in registry
        module = None
        for m in registry.get("modules", []):
            if m["id"] == module_id:
                module = m
                break

        if not module:
            return web.json_response(
                {"error": f"Module not found: {module_id}"},
                status=404
            )

        # Load full content to get domain details
        content = load_module_content(module_id)

        # Resolve effective feature flags
        features = resolve_feature_flags(module)

        # Build response with detail but without full questions
        response = {
            "id": module["id"],
            "name": module["name"],
            "description": module["description"],
            "long_description": module.get("long_description", module["description"]),
            "icon_name": module["icon_name"],
            "theme_color_hex": module["theme_color_hex"],
            "version": module["version"],
            "enabled": module.get("enabled", True),
            "supports_team_mode": features["supports_team_mode"],
            "supports_speed_training": features["supports_speed_training"],
            "supports_competition_sim": features["supports_competition_sim"],
            # Include raw flags for admin UI to show base capabilities vs overrides
            "base_supports_team_mode": module.get("supports_team_mode", False),
            "base_supports_speed_training": module.get("supports_speed_training", False),
            "base_supports_competition_sim": module.get("supports_competition_sim", False),
            "feature_overrides": module.get("feature_overrides", {}),
        }

        if content:
            # Add domain summaries (without questions)
            domains = []
            for domain in content.get("domains", []):
                domains.append({
                    "id": domain["id"],
                    "name": domain["name"],
                    "weight": domain["weight"],
                    "icon_name": domain["icon_name"],
                    "question_count": len(domain.get("questions", [])),
                })
            response["domains"] = domains
            response["study_modes"] = [m["name"] for m in content.get("study_modes", [])]
            response["total_questions"] = sum(len(d.get("questions", [])) for d in content.get("domains", []))
            response["estimated_study_hours"] = content.get("estimated_study_hours")

        return web.json_response(response)

    except Exception as e:
        logger.exception(f"Error getting module {module_id}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_download_module(request: web.Request) -> web.Response:
    """POST /api/modules/{module_id}/download

    Download full module content for offline use.

    Response includes everything needed for offline operation:
    - All domains with full questions and answers
    - Study mode configurations
    - Module settings (timing, TTS options, etc.)
    """
    module_id = request.match_info["module_id"]

    if not validate_module_id(module_id):
        return web.json_response(
            {"error": f"Invalid module_id: {module_id}"},
            status=400
        )

    try:
        registry = load_modules_registry()

        # Find module in registry
        module = None
        for m in registry.get("modules", []):
            if m["id"] == module_id:
                module = m
                break

        if not module:
            return web.json_response(
                {"error": f"Module not found: {module_id}"},
                status=404
            )

        # Load full content
        content = load_module_content(module_id)
        if not content:
            return web.json_response(
                {"error": f"Module content not available: {module_id}"},
                status=404
            )

        # Resolve effective feature flags
        features = resolve_feature_flags(module)

        # Build full download response
        total_questions = sum(len(d.get("questions", [])) for d in content.get("domains", []))

        response = {
            "id": module["id"],
            "name": module["name"],
            "description": module["description"],
            "icon_name": module["icon_name"],
            "theme_color_hex": module["theme_color_hex"],
            "version": module["version"],
            "downloaded_at": datetime.now(timezone.utc).isoformat(),
            "enabled": module.get("enabled", True),
            # Effective feature flags (base AND override)
            "supports_team_mode": features["supports_team_mode"],
            "supports_speed_training": features["supports_speed_training"],
            "supports_competition_sim": features["supports_competition_sim"],
            # Full content for offline operation
            "domains": content.get("domains", []),
            "total_questions": total_questions,
            "study_modes": content.get("study_modes", []),
            "settings": content.get("settings", {}),
        }

        logger.info(f"Module downloaded: {module_id} ({total_questions} questions)")
        return web.json_response(response)

    except Exception as e:
        logger.exception(f"Error downloading module {module_id}")
        return web.json_response({"error": str(e)}, status=500)


# Admin endpoints for managing modules


async def handle_create_module(request: web.Request) -> web.Response:
    """POST /api/modules

    Create or update a module definition.
    Admin endpoint for adding new modules to the server.
    """
    try:
        data = await request.json()

        required_fields = ["id", "name", "description", "icon_name", "theme_color_hex"]
        for field in required_fields:
            if field not in data:
                return web.json_response(
                    {"error": f"Missing required field: {field}"},
                    status=400
                )

        registry = load_modules_registry()

        # Check if module already exists
        existing_idx = None
        for idx, m in enumerate(registry.get("modules", [])):
            if m["id"] == data["id"]:
                existing_idx = idx
                break

        module_entry = {
            "id": data["id"],
            "name": data["name"],
            "description": data["description"],
            "long_description": data.get("long_description", data["description"]),
            "icon_name": data["icon_name"],
            "theme_color_hex": data["theme_color_hex"],
            "version": data.get("version", "1.0.0"),
            "enabled": data.get("enabled", True),
            "supports_team_mode": data.get("supports_team_mode", False),
            "supports_speed_training": data.get("supports_speed_training", False),
            "supports_competition_sim": data.get("supports_competition_sim", False),
            "feature_overrides": data.get("feature_overrides", {}),
            "download_size": data.get("download_size"),
        }

        if existing_idx is not None:
            registry["modules"][existing_idx] = module_entry
            logger.info(f"Updated module: {data['id']}")
        else:
            if "modules" not in registry:
                registry["modules"] = []
            registry["modules"].append(module_entry)
            logger.info(f"Created module: {data['id']}")

        save_modules_registry(registry)

        # If content provided, save it
        if "content" in data:
            save_module_content(data["id"], data["content"])

        return web.json_response({
            "success": True,
            "module_id": data["id"],
            "created": existing_idx is None,
        })

    except json.JSONDecodeError:
        return web.json_response({"error": "Invalid JSON"}, status=400)
    except Exception as e:
        logger.exception("Error creating module")
        return web.json_response({"error": str(e)}, status=500)


async def handle_delete_module(request: web.Request) -> web.Response:
    """DELETE /api/modules/{module_id}

    Delete a module from the server.
    Admin endpoint.
    """
    module_id = request.match_info["module_id"]

    if not validate_module_id(module_id):
        return web.json_response(
            {"error": f"Invalid module_id: {module_id}"},
            status=400
        )

    try:
        registry = load_modules_registry()

        # Find and remove module
        original_count = len(registry.get("modules", []))
        registry["modules"] = [m for m in registry.get("modules", []) if m["id"] != module_id]

        if len(registry["modules"]) == original_count:
            return web.json_response(
                {"error": f"Module not found: {module_id}"},
                status=404
            )

        save_modules_registry(registry)

        # Delete content file if exists
        content_path = get_module_content_path(module_id)
        if content_path.exists():
            content_path.unlink()

        logger.info(f"Deleted module: {module_id}")
        return web.json_response({"success": True, "module_id": module_id})

    except Exception as e:
        logger.exception(f"Error deleting module {module_id}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_update_module_settings(request: web.Request) -> web.Response:
    """PATCH /api/modules/{module_id}/settings

    Update module settings (enabled state and feature overrides).
    Admin endpoint for controlling module availability and features.

    Request body:
    {
        "enabled": true/false,          // Enable or disable the module
        "feature_overrides": {          // Override specific features
            "team_mode": true/false,    // Enable/disable team mode
            "speed_training": true/false,
            "competition_sim": true/false
        }
    }

    Response:
    {
        "success": true,
        "module_id": "knowledge-bowl",
        "enabled": true,
        "feature_overrides": {...},
        "effective_features": {
            "supports_team_mode": true,
            "supports_speed_training": true,
            "supports_competition_sim": false
        }
    }
    """
    module_id = request.match_info["module_id"]

    if not validate_module_id(module_id):
        return web.json_response(
            {"error": f"Invalid module_id: {module_id}"},
            status=400
        )

    try:
        data = await request.json()
        registry = load_modules_registry()

        # Find module
        module_idx = None
        for idx, m in enumerate(registry.get("modules", [])):
            if m["id"] == module_id:
                module_idx = idx
                break

        if module_idx is None:
            return web.json_response(
                {"error": f"Module not found: {module_id}"},
                status=404
            )

        module = registry["modules"][module_idx]

        # Update enabled state if provided
        if "enabled" in data:
            module["enabled"] = bool(data["enabled"])
            logger.info(f"Module {module_id} enabled={module['enabled']}")

        # Update feature overrides if provided
        if "feature_overrides" in data:
            overrides = data["feature_overrides"]
            if not isinstance(overrides, dict):
                return web.json_response(
                    {"error": "feature_overrides must be an object"},
                    status=400
                )

            # Validate override keys
            valid_keys = {"team_mode", "speed_training", "competition_sim"}
            for key in overrides:
                if key not in valid_keys:
                    return web.json_response(
                        {"error": f"Invalid feature override key: {key}. Valid keys: {valid_keys}"},
                        status=400
                    )
                if not isinstance(overrides[key], bool):
                    return web.json_response(
                        {"error": f"Feature override value must be boolean: {key}"},
                        status=400
                    )

            # Merge with existing overrides
            existing_overrides = module.get("feature_overrides", {})
            existing_overrides.update(overrides)
            module["feature_overrides"] = existing_overrides
            logger.info(f"Module {module_id} feature_overrides={module['feature_overrides']}")

        # Save changes
        registry["modules"][module_idx] = module
        save_modules_registry(registry)

        # Resolve effective features for response
        features = resolve_feature_flags(module)

        return web.json_response({
            "success": True,
            "module_id": module_id,
            "enabled": module.get("enabled", True),
            "feature_overrides": module.get("feature_overrides", {}),
            "effective_features": features,
        })

    except json.JSONDecodeError:
        return web.json_response({"error": "Invalid JSON"}, status=400)
    except Exception as e:
        logger.exception(f"Error updating module settings for {module_id}")
        return web.json_response({"error": str(e)}, status=500)


def register_modules_routes(app: web.Application):
    """Register all module management routes."""
    # Public endpoints (for clients)
    app.router.add_get("/api/modules", handle_list_modules)
    app.router.add_get("/api/modules/{module_id}", handle_get_module)
    app.router.add_post("/api/modules/{module_id}/download", handle_download_module)

    # Admin endpoints (for managing modules)
    app.router.add_post("/api/modules", handle_create_module)
    app.router.add_patch("/api/modules/{module_id}/settings", handle_update_module_settings)
    app.router.add_delete("/api/modules/{module_id}", handle_delete_module)

    # Ensure modules directory exists
    ensure_modules_directory()

    # Seed Knowledge Bowl if not exists
    seed_knowledge_bowl_module()

    logger.info("Modules API routes registered")


def seed_knowledge_bowl_module():
    """Seed the Knowledge Bowl module if it doesn't exist."""
    registry = load_modules_registry()

    # Check if KB already exists
    for m in registry.get("modules", []):
        if m["id"] == "knowledge-bowl":
            logger.debug("Knowledge Bowl module already exists")
            return

    logger.info("Seeding Knowledge Bowl module...")

    # Create Knowledge Bowl module entry
    kb_module = {
        "id": "knowledge-bowl",
        "name": "Knowledge Bowl",
        "description": "Academic competition prep across 12 subject domains",
        "long_description": (
            "Prepare for Knowledge Bowl competitions with comprehensive training across "
            "Science, Mathematics, Literature, History, Social Studies, Arts, Current Events, "
            "Language, Technology, Pop Culture, Religion & Philosophy, and Miscellaneous topics. "
            "Features timed practice, competition simulation, and team collaboration modes."
        ),
        "icon_name": "brain.head.profile",
        "theme_color_hex": "#9B59B6",
        "version": "1.0.0",
        "enabled": True,
        "supports_team_mode": True,
        "supports_speed_training": True,
        "supports_competition_sim": True,
        "feature_overrides": {},  # No overrides by default
        "download_size": 2097152,  # ~2MB estimate
    }

    # Add to registry
    if "modules" not in registry:
        registry["modules"] = []
    registry["modules"].append(kb_module)
    save_modules_registry(registry)

    # Create Knowledge Bowl content with all 12 domains
    kb_content = create_knowledge_bowl_content()
    save_module_content("knowledge-bowl", kb_content)

    logger.info("Knowledge Bowl module seeded successfully")


def create_knowledge_bowl_content() -> dict[str, Any]:
    """Create the full Knowledge Bowl module content."""
    return {
        "domains": [
            create_science_domain(),
            create_mathematics_domain(),
            create_literature_domain(),
            create_history_domain(),
            create_social_studies_domain(),
            create_arts_domain(),
            create_current_events_domain(),
            create_language_domain(),
            create_technology_domain(),
            create_pop_culture_domain(),
            create_religion_philosophy_domain(),
            create_miscellaneous_domain(),
        ],
        "study_modes": [
            {
                "id": "diagnostic",
                "name": "Diagnostic",
                "description": "Assess your knowledge across all domains",
                "icon_name": "chart.pie",
                "question_count": 50,
                "time_limit_seconds": None,
                "allow_hints": False,
                "shuffle_questions": True,
            },
            {
                "id": "targeted",
                "name": "Targeted Practice",
                "description": "Focus on your weakest domains",
                "icon_name": "scope",
                "question_count": 25,
                "time_limit_seconds": None,
                "allow_hints": True,
                "shuffle_questions": True,
            },
            {
                "id": "breadth",
                "name": "Breadth Review",
                "description": "Maintain coverage across all domains",
                "icon_name": "rectangle.grid.3x2",
                "question_count": 36,
                "time_limit_seconds": None,
                "allow_hints": False,
                "shuffle_questions": True,
            },
            {
                "id": "speed",
                "name": "Speed Drill",
                "description": "Build quick recall with timed questions",
                "icon_name": "bolt.circle",
                "question_count": 20,
                "time_limit_seconds": 300,
                "allow_hints": False,
                "shuffle_questions": True,
            },
            {
                "id": "competition",
                "name": "Competition Simulation",
                "description": "Practice in realistic competition conditions",
                "icon_name": "trophy",
                "question_count": 45,
                "time_limit_seconds": 900,
                "allow_hints": False,
                "shuffle_questions": True,
            },
            {
                "id": "team",
                "name": "Team Practice",
                "description": "Practice with your team members",
                "icon_name": "person.3",
                "question_count": 45,
                "time_limit_seconds": None,
                "allow_hints": False,
                "shuffle_questions": True,
            },
        ],
        "settings": {
            "default_time_per_question": 15.0,
            "confer_time_seconds": 15.0,
            "enable_spoken_questions": True,
            "enable_spoken_answers": True,
            "minimum_mastery_for_completion": 0.75,
        },
        "estimated_study_hours": 40.0,
    }


def create_science_domain() -> dict[str, Any]:
    """Create Science domain with questions."""
    return {
        "id": "science",
        "name": "Science",
        "icon_name": "atom",
        "weight": 0.20,
        "subcategories": ["Physics", "Chemistry", "Biology", "Earth Science", "Astronomy"],
        "questions": [
            # Physics
            {
                "id": "sci-phys-001",
                "domain_id": "science",
                "subcategory": "Physics",
                "question_text": "What is the SI unit of electric current?",
                "answer_text": "Ampere",
                "acceptable_answers": ["Ampere", "Amp", "A"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Named after a French physicist"],
                "explanation": "The ampere (A) is the SI base unit of electric current, named after Andre-Marie Ampere.",
            },
            {
                "id": "sci-phys-002",
                "domain_id": "science",
                "subcategory": "Physics",
                "question_text": "What law states that the pressure of a gas is inversely proportional to its volume at constant temperature?",
                "answer_text": "Boyle's Law",
                "acceptable_answers": ["Boyle's Law", "Boyles Law"],
                "difficulty": 3,
                "speed_target_seconds": 8.0,
                "question_type": "toss-up",
                "hints": ["Named after a 17th-century Irish scientist"],
                "explanation": "Boyle's Law (PV = constant) describes the inverse relationship between pressure and volume.",
            },
            {
                "id": "sci-phys-003",
                "domain_id": "science",
                "subcategory": "Physics",
                "question_text": "What is the speed of light in a vacuum, approximately in meters per second?",
                "answer_text": "300 million meters per second",
                "acceptable_answers": ["3 x 10^8", "300,000,000", "300 million", "3e8"],
                "difficulty": 2,
                "speed_target_seconds": 6.0,
                "question_type": "toss-up",
                "hints": ["It's about 3 followed by 8 zeros"],
                "explanation": "The speed of light in vacuum is approximately 299,792,458 m/s, often rounded to 3×10^8 m/s.",
            },
            # Chemistry
            {
                "id": "sci-chem-001",
                "domain_id": "science",
                "subcategory": "Chemistry",
                "question_text": "What is the chemical symbol for gold?",
                "answer_text": "Au",
                "acceptable_answers": ["Au"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["From the Latin word 'aurum'"],
                "explanation": "Gold's symbol Au comes from the Latin 'aurum' meaning 'shining dawn'.",
            },
            {
                "id": "sci-chem-002",
                "domain_id": "science",
                "subcategory": "Chemistry",
                "question_text": "What type of bond involves the sharing of electrons between atoms?",
                "answer_text": "Covalent bond",
                "acceptable_answers": ["Covalent", "Covalent bond"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Think 'co-' meaning together"],
                "explanation": "Covalent bonds form when atoms share electrons, as opposed to ionic bonds where electrons are transferred.",
            },
            # Biology
            {
                "id": "sci-bio-001",
                "domain_id": "science",
                "subcategory": "Biology",
                "question_text": "What organelle is known as the powerhouse of the cell?",
                "answer_text": "Mitochondria",
                "acceptable_answers": ["Mitochondria", "Mitochondrion"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Produces ATP"],
                "explanation": "Mitochondria produce most of the cell's ATP through cellular respiration.",
            },
            {
                "id": "sci-bio-002",
                "domain_id": "science",
                "subcategory": "Biology",
                "question_text": "What molecule carries genetic information and has a double helix structure?",
                "answer_text": "DNA",
                "acceptable_answers": ["DNA", "Deoxyribonucleic acid"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Discovered by Watson and Crick"],
                "explanation": "DNA (deoxyribonucleic acid) stores genetic instructions in its double helix structure.",
            },
            # Earth Science
            {
                "id": "sci-earth-001",
                "domain_id": "science",
                "subcategory": "Earth Science",
                "question_text": "What scale measures the intensity of earthquakes based on observed effects?",
                "answer_text": "Mercalli scale",
                "acceptable_answers": ["Mercalli", "Mercalli scale", "Modified Mercalli"],
                "difficulty": 3,
                "speed_target_seconds": 8.0,
                "question_type": "toss-up",
                "hints": ["Different from the Richter scale"],
                "explanation": "The Modified Mercalli Intensity scale measures earthquake effects, while Richter measures magnitude.",
            },
            # Astronomy
            {
                "id": "sci-astro-001",
                "domain_id": "science",
                "subcategory": "Astronomy",
                "question_text": "What is the closest star to Earth?",
                "answer_text": "The Sun",
                "acceptable_answers": ["The Sun", "Sun", "Sol"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["You see it every day"],
                "explanation": "The Sun is our closest star at about 93 million miles. Proxima Centauri is the closest after the Sun.",
            },
            {
                "id": "sci-astro-002",
                "domain_id": "science",
                "subcategory": "Astronomy",
                "question_text": "What is the largest planet in our solar system?",
                "answer_text": "Jupiter",
                "acceptable_answers": ["Jupiter"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Named after the king of Roman gods"],
                "explanation": "Jupiter is the largest planet, with a mass more than twice that of all other planets combined.",
            },
        ],
    }


def create_mathematics_domain() -> dict[str, Any]:
    """Create Mathematics domain with questions."""
    return {
        "id": "mathematics",
        "name": "Mathematics",
        "icon_name": "function",
        "weight": 0.15,
        "subcategories": ["Algebra", "Geometry", "Calculus", "Statistics", "Number Theory"],
        "questions": [
            {
                "id": "math-alg-001",
                "domain_id": "mathematics",
                "subcategory": "Algebra",
                "question_text": "What is the quadratic formula?",
                "answer_text": "x = (-b ± √(b²-4ac)) / 2a",
                "acceptable_answers": ["negative b plus or minus square root of b squared minus 4ac all over 2a"],
                "difficulty": 2,
                "speed_target_seconds": 8.0,
                "question_type": "toss-up",
                "hints": ["Used to solve ax² + bx + c = 0"],
                "explanation": "The quadratic formula solves any quadratic equation ax² + bx + c = 0.",
            },
            {
                "id": "math-geo-001",
                "domain_id": "mathematics",
                "subcategory": "Geometry",
                "question_text": "What is the sum of interior angles in a triangle?",
                "answer_text": "180 degrees",
                "acceptable_answers": ["180", "180 degrees", "one hundred eighty"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Think of a straight line"],
                "explanation": "The interior angles of any triangle always sum to 180 degrees.",
            },
            {
                "id": "math-geo-002",
                "domain_id": "mathematics",
                "subcategory": "Geometry",
                "question_text": "What is the formula for the area of a circle?",
                "answer_text": "πr²",
                "acceptable_answers": ["pi r squared", "πr²", "pi times r squared"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Involves pi and the radius"],
                "explanation": "The area of a circle is π times the radius squared.",
            },
            {
                "id": "math-calc-001",
                "domain_id": "mathematics",
                "subcategory": "Calculus",
                "question_text": "What is the derivative of x²?",
                "answer_text": "2x",
                "acceptable_answers": ["2x", "two x"],
                "difficulty": 2,
                "speed_target_seconds": 4.0,
                "question_type": "toss-up",
                "hints": ["Use the power rule"],
                "explanation": "Using the power rule, d/dx(x^n) = nx^(n-1), so d/dx(x²) = 2x.",
            },
            {
                "id": "math-stat-001",
                "domain_id": "mathematics",
                "subcategory": "Statistics",
                "question_text": "What measure of central tendency is found by adding all values and dividing by the count?",
                "answer_text": "Mean",
                "acceptable_answers": ["Mean", "Average", "Arithmetic mean"],
                "difficulty": 1,
                "speed_target_seconds": 4.0,
                "question_type": "toss-up",
                "hints": ["Also called the average"],
                "explanation": "The mean (average) is the sum of all values divided by the number of values.",
            },
            {
                "id": "math-num-001",
                "domain_id": "mathematics",
                "subcategory": "Number Theory",
                "question_text": "What is the only even prime number?",
                "answer_text": "2",
                "acceptable_answers": ["2", "Two"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["It's the smallest prime"],
                "explanation": "2 is the only even prime because all other even numbers are divisible by 2.",
            },
        ],
    }


def create_literature_domain() -> dict[str, Any]:
    """Create Literature domain with questions."""
    return {
        "id": "literature",
        "name": "Literature",
        "icon_name": "book",
        "weight": 0.12,
        "subcategories": ["American Literature", "British Literature", "World Literature", "Poetry", "Drama"],
        "questions": [
            {
                "id": "lit-am-001",
                "domain_id": "literature",
                "subcategory": "American Literature",
                "question_text": "Who wrote 'The Great Gatsby'?",
                "answer_text": "F. Scott Fitzgerald",
                "acceptable_answers": ["F. Scott Fitzgerald", "Fitzgerald", "Scott Fitzgerald"],
                "difficulty": 1,
                "speed_target_seconds": 4.0,
                "question_type": "toss-up",
                "hints": ["Associated with the Jazz Age"],
                "explanation": "F. Scott Fitzgerald wrote The Great Gatsby in 1925, capturing the Jazz Age.",
            },
            {
                "id": "lit-brit-001",
                "domain_id": "literature",
                "subcategory": "British Literature",
                "question_text": "In which Shakespeare play does the character Hamlet appear?",
                "answer_text": "Hamlet",
                "acceptable_answers": ["Hamlet", "The Tragedy of Hamlet"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["The play shares his name"],
                "explanation": "Hamlet is the title character of Shakespeare's tragedy 'Hamlet'.",
            },
            {
                "id": "lit-brit-002",
                "domain_id": "literature",
                "subcategory": "British Literature",
                "question_text": "Who wrote 'Pride and Prejudice'?",
                "answer_text": "Jane Austen",
                "acceptable_answers": ["Jane Austen", "Austen"],
                "difficulty": 1,
                "speed_target_seconds": 4.0,
                "question_type": "toss-up",
                "hints": ["A female Regency-era novelist"],
                "explanation": "Jane Austen wrote Pride and Prejudice in 1813.",
            },
            {
                "id": "lit-poetry-001",
                "domain_id": "literature",
                "subcategory": "Poetry",
                "question_text": "Who wrote 'The Road Not Taken'?",
                "answer_text": "Robert Frost",
                "acceptable_answers": ["Robert Frost", "Frost"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["An American poet associated with rural New England"],
                "explanation": "Robert Frost wrote 'The Road Not Taken' in 1916.",
            },
            {
                "id": "lit-drama-001",
                "domain_id": "literature",
                "subcategory": "Drama",
                "question_text": "Who wrote 'Death of a Salesman'?",
                "answer_text": "Arthur Miller",
                "acceptable_answers": ["Arthur Miller", "Miller"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Also wrote 'The Crucible'"],
                "explanation": "Arthur Miller wrote 'Death of a Salesman' in 1949.",
            },
        ],
    }


def create_history_domain() -> dict[str, Any]:
    """Create History domain with questions."""
    return {
        "id": "history",
        "name": "History",
        "icon_name": "clock.arrow.circlepath",
        "weight": 0.12,
        "subcategories": ["US History", "World History", "Ancient History", "Modern History", "Military History"],
        "questions": [
            {
                "id": "hist-us-001",
                "domain_id": "history",
                "subcategory": "US History",
                "question_text": "In what year was the Declaration of Independence signed?",
                "answer_text": "1776",
                "acceptable_answers": ["1776", "seventeen seventy-six"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Think July 4th"],
                "explanation": "The Declaration of Independence was adopted on July 4, 1776.",
            },
            {
                "id": "hist-us-002",
                "domain_id": "history",
                "subcategory": "US History",
                "question_text": "Who was the first President of the United States?",
                "answer_text": "George Washington",
                "acceptable_answers": ["George Washington", "Washington"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["His face is on the dollar bill"],
                "explanation": "George Washington served as the first U.S. President from 1789-1797.",
            },
            {
                "id": "hist-world-001",
                "domain_id": "history",
                "subcategory": "World History",
                "question_text": "In what year did World War II end?",
                "answer_text": "1945",
                "acceptable_answers": ["1945", "nineteen forty-five"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["V-E Day and V-J Day"],
                "explanation": "WWII ended in 1945 with Germany's surrender in May and Japan's in September.",
            },
            {
                "id": "hist-ancient-001",
                "domain_id": "history",
                "subcategory": "Ancient History",
                "question_text": "What ancient wonder was located in Alexandria, Egypt?",
                "answer_text": "The Lighthouse of Alexandria",
                "acceptable_answers": ["Lighthouse of Alexandria", "Pharos of Alexandria", "Pharos"],
                "difficulty": 3,
                "speed_target_seconds": 8.0,
                "question_type": "toss-up",
                "hints": ["It helped ships navigate"],
                "explanation": "The Lighthouse (Pharos) of Alexandria was one of the Seven Wonders of the Ancient World.",
            },
            {
                "id": "hist-mil-001",
                "domain_id": "history",
                "subcategory": "Military History",
                "question_text": "What was the code name for the Allied invasion of Normandy in 1944?",
                "answer_text": "Operation Overlord",
                "acceptable_answers": ["Operation Overlord", "Overlord", "D-Day"],
                "difficulty": 2,
                "speed_target_seconds": 6.0,
                "question_type": "toss-up",
                "hints": ["Also known as D-Day"],
                "explanation": "Operation Overlord was the codename for the Battle of Normandy, launched on June 6, 1944.",
            },
        ],
    }


def create_social_studies_domain() -> dict[str, Any]:
    """Create Social Studies domain with questions."""
    return {
        "id": "social-studies",
        "name": "Social Studies",
        "icon_name": "globe.americas",
        "weight": 0.10,
        "subcategories": ["Geography", "Government", "Economics", "Civics"],
        "questions": [
            {
                "id": "ss-geo-001",
                "domain_id": "social-studies",
                "subcategory": "Geography",
                "question_text": "What is the capital of Australia?",
                "answer_text": "Canberra",
                "acceptable_answers": ["Canberra"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Not Sydney or Melbourne"],
                "explanation": "Canberra, not Sydney, is Australia's capital, chosen as a compromise between the two cities.",
            },
            {
                "id": "ss-geo-002",
                "domain_id": "social-studies",
                "subcategory": "Geography",
                "question_text": "What is the longest river in the world?",
                "answer_text": "The Nile",
                "acceptable_answers": ["Nile", "The Nile", "Nile River"],
                "difficulty": 1,
                "speed_target_seconds": 4.0,
                "question_type": "toss-up",
                "hints": ["Located in Africa"],
                "explanation": "The Nile River is approximately 6,650 km long, flowing through northeastern Africa.",
            },
            {
                "id": "ss-gov-001",
                "domain_id": "social-studies",
                "subcategory": "Government",
                "question_text": "How many justices serve on the United States Supreme Court?",
                "answer_text": "Nine",
                "acceptable_answers": ["9", "Nine"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["One Chief Justice plus associates"],
                "explanation": "The Supreme Court has nine justices: one Chief Justice and eight Associate Justices.",
            },
            {
                "id": "ss-econ-001",
                "domain_id": "social-studies",
                "subcategory": "Economics",
                "question_text": "What economic term describes the total value of goods and services produced by a country?",
                "answer_text": "Gross Domestic Product",
                "acceptable_answers": ["GDP", "Gross Domestic Product"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Abbreviated as GDP"],
                "explanation": "GDP measures the total monetary value of all goods and services produced within a country.",
            },
        ],
    }


def create_arts_domain() -> dict[str, Any]:
    """Create Arts domain with questions."""
    return {
        "id": "arts",
        "name": "Arts",
        "icon_name": "paintpalette",
        "weight": 0.08,
        "subcategories": ["Visual Arts", "Music", "Theater", "Architecture"],
        "questions": [
            {
                "id": "arts-vis-001",
                "domain_id": "arts",
                "subcategory": "Visual Arts",
                "question_text": "Who painted the Mona Lisa?",
                "answer_text": "Leonardo da Vinci",
                "acceptable_answers": ["Leonardo da Vinci", "Da Vinci", "Leonardo"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Italian Renaissance master"],
                "explanation": "Leonardo da Vinci painted the Mona Lisa between 1503-1519.",
            },
            {
                "id": "arts-vis-002",
                "domain_id": "arts",
                "subcategory": "Visual Arts",
                "question_text": "What art movement is Salvador Dali associated with?",
                "answer_text": "Surrealism",
                "acceptable_answers": ["Surrealism", "Surrealist"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Known for dreamlike imagery"],
                "explanation": "Dali was a leading figure in Surrealism, known for striking and bizarre imagery.",
            },
            {
                "id": "arts-mus-001",
                "domain_id": "arts",
                "subcategory": "Music",
                "question_text": "Who composed the 'Ninth Symphony' that includes 'Ode to Joy'?",
                "answer_text": "Ludwig van Beethoven",
                "acceptable_answers": ["Beethoven", "Ludwig van Beethoven"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["A German composer who became deaf"],
                "explanation": "Beethoven composed his Ninth Symphony in 1824, despite being almost completely deaf.",
            },
            {
                "id": "arts-arch-001",
                "domain_id": "arts",
                "subcategory": "Architecture",
                "question_text": "What architectural style features pointed arches and flying buttresses?",
                "answer_text": "Gothic",
                "acceptable_answers": ["Gothic", "Gothic architecture"],
                "difficulty": 2,
                "speed_target_seconds": 6.0,
                "question_type": "toss-up",
                "hints": ["Common in medieval European cathedrals"],
                "explanation": "Gothic architecture, prominent from the 12th-16th centuries, features pointed arches and flying buttresses.",
            },
        ],
    }


def create_current_events_domain() -> dict[str, Any]:
    """Create Current Events domain with questions."""
    return {
        "id": "current-events",
        "name": "Current Events",
        "icon_name": "newspaper",
        "weight": 0.08,
        "subcategories": ["Politics", "International", "Science News", "Business"],
        "questions": [
            # Note: Current events questions should be updated regularly
            {
                "id": "ce-placeholder-001",
                "domain_id": "current-events",
                "subcategory": "General",
                "question_text": "Current events questions are updated regularly based on recent news.",
                "answer_text": "This is a placeholder",
                "acceptable_answers": ["placeholder"],
                "difficulty": 1,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Check for updates"],
                "explanation": "Current events content is refreshed periodically.",
            },
        ],
    }


def create_language_domain() -> dict[str, Any]:
    """Create Language domain with questions."""
    return {
        "id": "language",
        "name": "Language",
        "icon_name": "textformat",
        "weight": 0.05,
        "subcategories": ["Grammar", "Vocabulary", "Etymology", "Foreign Languages"],
        "questions": [
            {
                "id": "lang-gram-001",
                "domain_id": "language",
                "subcategory": "Grammar",
                "question_text": "What part of speech describes a noun?",
                "answer_text": "Adjective",
                "acceptable_answers": ["Adjective"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Examples: big, red, happy"],
                "explanation": "Adjectives modify nouns by describing their qualities.",
            },
            {
                "id": "lang-vocab-001",
                "domain_id": "language",
                "subcategory": "Vocabulary",
                "question_text": "What does the prefix 'anti-' mean?",
                "answer_text": "Against",
                "acceptable_answers": ["Against", "Opposite", "Opposed to"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Think of 'antibiotic'"],
                "explanation": "The prefix 'anti-' means against or opposite, from Greek.",
            },
            {
                "id": "lang-etym-001",
                "domain_id": "language",
                "subcategory": "Etymology",
                "question_text": "From what language does the word 'kindergarten' originate?",
                "answer_text": "German",
                "acceptable_answers": ["German"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Means 'children's garden'"],
                "explanation": "Kindergarten is German, literally meaning 'children's garden'.",
            },
        ],
    }


def create_technology_domain() -> dict[str, Any]:
    """Create Technology domain with questions."""
    return {
        "id": "technology",
        "name": "Technology",
        "icon_name": "desktopcomputer",
        "weight": 0.04,
        "subcategories": ["Computer Science", "Engineering", "Inventions", "Internet"],
        "questions": [
            {
                "id": "tech-cs-001",
                "domain_id": "technology",
                "subcategory": "Computer Science",
                "question_text": "What does CPU stand for?",
                "answer_text": "Central Processing Unit",
                "acceptable_answers": ["Central Processing Unit"],
                "difficulty": 1,
                "speed_target_seconds": 4.0,
                "question_type": "toss-up",
                "hints": ["The 'brain' of a computer"],
                "explanation": "The CPU (Central Processing Unit) executes instructions and processes data.",
            },
            {
                "id": "tech-cs-002",
                "domain_id": "technology",
                "subcategory": "Computer Science",
                "question_text": "What programming language is known for its use in web browsers?",
                "answer_text": "JavaScript",
                "acceptable_answers": ["JavaScript", "JS"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Not the same as Java"],
                "explanation": "JavaScript is the primary programming language for web browser interactivity.",
            },
            {
                "id": "tech-inv-001",
                "domain_id": "technology",
                "subcategory": "Inventions",
                "question_text": "Who invented the telephone?",
                "answer_text": "Alexander Graham Bell",
                "acceptable_answers": ["Alexander Graham Bell", "Bell", "Graham Bell"],
                "difficulty": 1,
                "speed_target_seconds": 4.0,
                "question_type": "toss-up",
                "hints": ["His name is on a phone company"],
                "explanation": "Alexander Graham Bell patented the telephone in 1876.",
            },
        ],
    }


def create_pop_culture_domain() -> dict[str, Any]:
    """Create Pop Culture domain with questions."""
    return {
        "id": "pop-culture",
        "name": "Pop Culture",
        "icon_name": "star",
        "weight": 0.03,
        "subcategories": ["Movies", "Television", "Music", "Sports"],
        "questions": [
            {
                "id": "pop-mov-001",
                "domain_id": "pop-culture",
                "subcategory": "Movies",
                "question_text": "What 1977 film introduced audiences to Luke Skywalker?",
                "answer_text": "Star Wars",
                "acceptable_answers": ["Star Wars", "Star Wars: A New Hope", "A New Hope"],
                "difficulty": 1,
                "speed_target_seconds": 4.0,
                "question_type": "toss-up",
                "hints": ["In a galaxy far, far away"],
                "explanation": "Star Wars (later subtitled 'A New Hope') was released in 1977.",
            },
            {
                "id": "pop-tv-001",
                "domain_id": "pop-culture",
                "subcategory": "Television",
                "question_text": "What animated TV show features the Simpson family?",
                "answer_text": "The Simpsons",
                "acceptable_answers": ["The Simpsons", "Simpsons"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Yellow-skinned characters"],
                "explanation": "The Simpsons has been on air since 1989, making it the longest-running American animated series.",
            },
            {
                "id": "pop-sport-001",
                "domain_id": "pop-culture",
                "subcategory": "Sports",
                "question_text": "In what sport would you perform a slam dunk?",
                "answer_text": "Basketball",
                "acceptable_answers": ["Basketball"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Uses a hoop and backboard"],
                "explanation": "A slam dunk is a basketball shot where a player jumps and scores by putting the ball directly through the hoop.",
            },
        ],
    }


def create_religion_philosophy_domain() -> dict[str, Any]:
    """Create Religion & Philosophy domain with questions."""
    return {
        "id": "religion-philosophy",
        "name": "Religion & Philosophy",
        "icon_name": "sparkles",
        "weight": 0.02,
        "subcategories": ["World Religions", "Philosophy", "Mythology", "Ethics"],
        "questions": [
            {
                "id": "rel-wr-001",
                "domain_id": "religion-philosophy",
                "subcategory": "World Religions",
                "question_text": "What religion's holy book is the Torah?",
                "answer_text": "Judaism",
                "acceptable_answers": ["Judaism", "Jewish"],
                "difficulty": 1,
                "speed_target_seconds": 4.0,
                "question_type": "toss-up",
                "hints": ["The first five books of the Hebrew Bible"],
                "explanation": "The Torah is the central text of Judaism, containing the first five books of Moses.",
            },
            {
                "id": "rel-phil-001",
                "domain_id": "religion-philosophy",
                "subcategory": "Philosophy",
                "question_text": "Who said 'I think, therefore I am'?",
                "answer_text": "René Descartes",
                "acceptable_answers": ["Descartes", "René Descartes"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["A French philosopher"],
                "explanation": "Descartes' 'Cogito ergo sum' is a foundational element of Western philosophy.",
            },
            {
                "id": "rel-myth-001",
                "domain_id": "religion-philosophy",
                "subcategory": "Mythology",
                "question_text": "In Greek mythology, who is the king of the gods?",
                "answer_text": "Zeus",
                "acceptable_answers": ["Zeus"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Rules from Mount Olympus"],
                "explanation": "Zeus is the king of the Olympian gods in Greek mythology.",
            },
        ],
    }


def create_miscellaneous_domain() -> dict[str, Any]:
    """Create Miscellaneous domain with questions."""
    return {
        "id": "miscellaneous",
        "name": "Miscellaneous",
        "icon_name": "questionmark.diamond",
        "weight": 0.01,
        "subcategories": ["General Knowledge", "Trivia", "Cross-Domain"],
        "questions": [
            {
                "id": "misc-gen-001",
                "domain_id": "miscellaneous",
                "subcategory": "General Knowledge",
                "question_text": "How many continents are there on Earth?",
                "answer_text": "Seven",
                "acceptable_answers": ["7", "Seven"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["Think of the major landmasses"],
                "explanation": "The seven continents are Africa, Antarctica, Asia, Australia, Europe, North America, and South America.",
            },
            {
                "id": "misc-gen-002",
                "domain_id": "miscellaneous",
                "subcategory": "General Knowledge",
                "question_text": "What is the most widely spoken language in the world by number of native speakers?",
                "answer_text": "Mandarin Chinese",
                "acceptable_answers": ["Mandarin", "Chinese", "Mandarin Chinese"],
                "difficulty": 2,
                "speed_target_seconds": 5.0,
                "question_type": "toss-up",
                "hints": ["Spoken in the world's most populous country"],
                "explanation": "Mandarin Chinese has the most native speakers at over 900 million.",
            },
            {
                "id": "misc-trivia-001",
                "domain_id": "miscellaneous",
                "subcategory": "Trivia",
                "question_text": "What color are the stars on the American flag?",
                "answer_text": "White",
                "acceptable_answers": ["White"],
                "difficulty": 1,
                "speed_target_seconds": 3.0,
                "question_type": "toss-up",
                "hints": ["On a blue background"],
                "explanation": "The 50 white stars represent the 50 states on a blue field.",
            },
        ],
    }


# KB Audio Pre-generation


async def check_and_prefetch_kb_audio(
    kb_audio_manager: "KBAudioManager",
    force_regenerate: bool = False,
    voice_id: str = "nova",
    provider: str = "vibevoice",
) -> Optional[str]:
    """Check KB audio coverage and trigger prefetch if needed.

    Called at server startup to ensure KB module has pre-generated audio.
    Returns the job ID if prefetch was started, None if audio is already complete.

    Args:
        kb_audio_manager: The KBAudioManager instance
        force_regenerate: If True, regenerate all audio even if complete
        voice_id: Voice ID for TTS generation
        provider: TTS provider to use

    Returns:
        Job ID if prefetch was started, None if already complete
    """
    module_id = "knowledge-bowl"

    # Load module content
    content = load_module_content(module_id)
    if not content:
        logger.warning(f"KB module content not found, cannot prefetch audio")
        return None

    # Check current coverage
    coverage = kb_audio_manager.get_coverage_status(module_id, content)

    logger.info(
        f"KB audio coverage: {coverage.covered_segments}/{coverage.total_segments} "
        f"segments ({coverage.coverage_percent:.1f}%)"
    )

    # Trigger prefetch if coverage is incomplete or force regenerate requested
    if coverage.coverage_percent < 100.0 or force_regenerate:
        logger.info(f"Starting KB audio prefetch (force={force_regenerate})")

        # Start prefetch in background task
        job_id = await kb_audio_manager.prefetch_module(
            module_id=module_id,
            module_content=content,
            voice_id=voice_id,
            provider=provider,
            force_regenerate=force_regenerate,
        )

        return job_id
    else:
        logger.info("KB audio fully covered, no prefetch needed")
        return None


async def schedule_kb_audio_prefetch(app: web.Application) -> None:
    """Schedule KB audio prefetch after server startup.

    This should be called from a startup hook to trigger prefetch
    in the background after the server is fully initialized.
    """
    # Wait a moment for server to be fully ready
    await asyncio.sleep(2.0)

    kb_audio_manager = app.get("kb_audio_manager")
    if not kb_audio_manager:
        logger.warning("KB audio manager not available, skipping prefetch")
        return

    try:
        job_id = await check_and_prefetch_kb_audio(kb_audio_manager)
        if job_id:
            logger.info(f"KB audio prefetch started: {job_id}")
    except Exception as e:
        logger.error(f"KB audio prefetch failed: {e}")
