"""
KB Packs API - Knowledge Bowl Question Pack Management.

Provides endpoints for managing question packs:
- GET /api/kb/packs - List all packs
- POST /api/kb/packs - Create a new pack
- GET /api/kb/packs/{pack_id} - Get pack details
- PATCH /api/kb/packs/{pack_id} - Update pack
- DELETE /api/kb/packs/{pack_id} - Delete pack
- POST /api/kb/packs/{pack_id}/questions - Add questions to pack
- DELETE /api/kb/packs/{pack_id}/questions/{question_id} - Remove question from pack
- POST /api/kb/packs/bundle - Create a bundle from multiple packs

Question management:
- GET /api/kb/questions - List questions (with filters)
- POST /api/kb/questions - Create a new question
- GET /api/kb/questions/{question_id} - Get question details
- PATCH /api/kb/questions/{question_id} - Update question
- DELETE /api/kb/questions/{question_id} - Delete question
- POST /api/kb/questions/bulk-update - Bulk update questions
"""

import json
import logging
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from aiohttp import web

from modules_api import load_module_content

logger = logging.getLogger(__name__)


def get_kb_repo(request: web.Request):
    """Get KB questions repository from request app, if database is available."""
    return request.app.get("kb_repo")

# Data directory for packs storage
DATA_DIR = Path(__file__).parent / "data"
PACKS_DIR = DATA_DIR / "kb_packs"


# Difficulty tier labels
DIFFICULTY_TIER_LABELS = {
    "elementary": "Elementary (Grades 3-5)",
    "middle_school": "Middle School (Grades 6-8)",
    "jv": "Junior Varsity (Grades 9-10)",
    "varsity": "Varsity (Grades 11-12)",
    "championship": "Championship",
    "college": "College",
}

VALID_DIFFICULTY_TIERS = set(DIFFICULTY_TIER_LABELS.keys())
VALID_QUESTION_TYPES = {"toss_up", "bonus", "pyramid", "lightning"}
VALID_QUESTION_SOURCES = {"naqt", "nsb", "qb_packets", "custom", "ai_generated"}
VALID_PACK_TYPES = {"system", "custom", "bundle"}
VALID_STATUSES = {"active", "draft", "archived"}


def validate_pack_id(pack_id: str) -> bool:
    """Validate pack_id to prevent path traversal attacks."""
    if not pack_id:
        return False
    return bool(re.match(r"^[a-zA-Z0-9_-]+$", pack_id))


def validate_question_id(question_id: str) -> bool:
    """Validate question_id format."""
    if not question_id:
        return False
    return bool(re.match(r"^[a-zA-Z0-9_-]+$", question_id))


def ensure_packs_directory():
    """Ensure packs directory exists."""
    PACKS_DIR.mkdir(parents=True, exist_ok=True)


def get_packs_registry_path() -> Path:
    """Get path to packs registry file."""
    return PACKS_DIR / "registry.json"


def get_questions_store_path() -> Path:
    """Get path to questions store file."""
    return PACKS_DIR / "questions.json"


def load_packs_registry() -> dict[str, Any]:
    """Load the packs registry from disk."""
    registry_path = get_packs_registry_path()
    if not registry_path.exists():
        return {"packs": [], "version": "1.0.0"}

    try:
        with open(registry_path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load packs registry: {e}")
        return {"packs": [], "version": "1.0.0"}


def save_packs_registry(registry: dict[str, Any]):
    """Save the packs registry to disk."""
    ensure_packs_directory()
    registry_path = get_packs_registry_path()

    try:
        with open(registry_path, "w", encoding="utf-8") as f:
            json.dump(registry, f, indent=2)
        logger.info(f"Saved packs registry with {len(registry.get('packs', []))} packs")
    except Exception as e:
        logger.error(f"Failed to save packs registry: {e}")


def load_questions_store() -> dict[str, Any]:
    """Load the questions store from disk."""
    store_path = get_questions_store_path()
    if not store_path.exists():
        return {"questions": {}, "version": "1.0.0"}

    try:
        with open(store_path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load questions store: {e}")
        return {"questions": {}, "version": "1.0.0"}


def save_questions_store(store: dict[str, Any]):
    """Save the questions store to disk."""
    ensure_packs_directory()
    store_path = get_questions_store_path()

    try:
        with open(store_path, "w", encoding="utf-8") as f:
            json.dump(store, f, indent=2)
        logger.info(f"Saved questions store with {len(store.get('questions', {}))} questions")
    except Exception as e:
        logger.error(f"Failed to save questions store: {e}")


def generate_pack_id() -> str:
    """Generate a unique pack ID."""
    return f"pack-{uuid.uuid4().hex[:8]}"


def generate_question_id(domain_id: str, subcategory: str) -> str:
    """Generate a unique question ID."""
    prefix = f"{domain_id[:3]}-{subcategory[:4].lower()}"
    return f"{prefix}-{uuid.uuid4().hex[:6]}"


def calculate_pack_stats(pack: dict, questions_store: dict) -> dict:
    """Calculate statistics for a pack."""
    questions = questions_store.get("questions", {})
    pack_questions = [questions.get(qid) for qid in pack.get("question_ids", []) if qid in questions]

    if not pack_questions:
        return {
            "question_count": 0,
            "domain_count": 0,
            "difficulty_distribution": {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
            "domain_distribution": {},
            "question_types": [],
            "audio_coverage_percent": 0,
            "missing_audio_count": 0,
        }

    # Calculate distributions
    difficulty_dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
    domain_dist: dict[str, int] = {}
    question_types: set[str] = set()
    has_audio_count = 0

    for q in pack_questions:
        if q:
            diff = q.get("difficulty", 1)
            if 1 <= diff <= 5:
                difficulty_dist[diff] += 1

            domain = q.get("domain_id", "unknown")
            domain_dist[domain] = domain_dist.get(domain, 0) + 1

            qtype = q.get("question_type", "toss_up")
            question_types.add(qtype)

            if q.get("has_audio", False):
                has_audio_count += 1

    total = len(pack_questions)
    audio_coverage = (has_audio_count / total * 100) if total > 0 else 0

    return {
        "question_count": total,
        "domain_count": len(domain_dist),
        "difficulty_distribution": difficulty_dist,
        "domain_distribution": domain_dist,
        "question_types": list(question_types),
        "audio_coverage_percent": round(audio_coverage, 1),
        "missing_audio_count": total - has_audio_count,
    }


def get_domain_groups(pack: dict, questions_store: dict) -> list[dict]:
    """Get questions organized by domain for a pack."""
    questions = questions_store.get("questions", {})
    pack_questions = [questions.get(qid) for qid in pack.get("question_ids", []) if qid in questions]

    domain_map: dict[str, dict] = {}
    for q in pack_questions:
        if not q:
            continue
        domain_id = q.get("domain_id", "unknown")
        subcategory = q.get("subcategory", "General")

        if domain_id not in domain_map:
            domain_map[domain_id] = {
                "domain_id": domain_id,
                "domain_name": domain_id.replace("-", " ").title(),
                "question_count": 0,
                "subcategories": {},
            }

        domain_map[domain_id]["question_count"] += 1

        if subcategory not in domain_map[domain_id]["subcategories"]:
            domain_map[domain_id]["subcategories"][subcategory] = 0
        domain_map[domain_id]["subcategories"][subcategory] += 1

    # Convert to list format
    result = []
    for domain_id, data in sorted(domain_map.items()):
        result.append(
            {
                "domain_id": domain_id,
                "domain_name": data["domain_name"],
                "question_count": data["question_count"],
                "subcategories": [
                    {"subcategory": sub, "question_count": count}
                    for sub, count in sorted(data["subcategories"].items())
                ],
            }
        )
    return result


# API Handlers


async def handle_list_packs(request: web.Request) -> web.Response:
    """GET /api/kb/packs

    List all question packs with optional filtering.

    Query params:
    - type: Filter by pack type (system, custom, bundle)
    - status: Filter by status (active, draft, archived)
    - search: Search in name/description
    - limit: Max results (default 50)
    - offset: Pagination offset (default 0)
    """
    try:
        registry = load_packs_registry()
        questions_store = load_questions_store()

        # Parse query params
        pack_type = request.query.get("type")
        status = request.query.get("status")
        search = request.query.get("search", "").lower()
        limit = min(int(request.query.get("limit", 50)), 100)
        offset = int(request.query.get("offset", 0))

        # Filter packs
        packs = registry.get("packs", [])
        filtered = []

        for pack in packs:
            # Type filter
            if pack_type and pack.get("type") != pack_type:
                continue

            # Status filter
            if status and pack.get("status") != status:
                continue

            # Search filter
            if search:
                name = pack.get("name", "").lower()
                desc = pack.get("description", "").lower()
                if search not in name and search not in desc:
                    continue

            # Calculate stats
            stats = calculate_pack_stats(pack, questions_store)

            filtered.append(
                {
                    "id": pack["id"],
                    "name": pack["name"],
                    "description": pack.get("description", ""),
                    "type": pack.get("type", "custom"),
                    "difficulty_tier": pack.get("difficulty_tier", "varsity"),
                    "question_count": stats["question_count"],
                    "domain_count": stats["domain_count"],
                    "audio_coverage_percent": stats["audio_coverage_percent"],
                    "status": pack.get("status", "active"),
                    "updated_at": pack.get("updated_at", pack.get("created_at", "")),
                }
            )

        # Paginate
        total = len(filtered)
        paginated = filtered[offset : offset + limit]

        return web.json_response(
            {
                "success": True,
                "packs": paginated,
                "total": total,
                "limit": limit,
                "offset": offset,
            }
        )

    except Exception:
        logger.exception("Error listing packs")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_create_pack(request: web.Request) -> web.Response:
    """POST /api/kb/packs

    Create a new question pack.

    Request body:
    {
        "name": "Pack Name",
        "description": "Description",
        "type": "custom",
        "difficulty_tier": "varsity",
        "competition_year": "2024-2025",
        "status": "draft"
    }
    """
    try:
        data = await request.json()

        # Validate required fields
        if "name" not in data:
            return web.json_response({"success": False, "error": "Missing required field: name"}, status=400)

        # Validate difficulty tier
        difficulty_tier = data.get("difficulty_tier", "varsity")
        if difficulty_tier not in VALID_DIFFICULTY_TIERS:
            return web.json_response(
                {"success": False, "error": f"Invalid difficulty_tier. Valid: {VALID_DIFFICULTY_TIERS}"}, status=400
            )

        # Validate pack type
        pack_type = data.get("type", "custom")
        if pack_type not in VALID_PACK_TYPES:
            return web.json_response(
                {"success": False, "error": f"Invalid pack type. Valid: {VALID_PACK_TYPES}"}, status=400
            )

        # Validate status
        status = data.get("status", "draft")
        if status not in VALID_STATUSES:
            return web.json_response(
                {"success": False, "error": f"Invalid status. Valid: {VALID_STATUSES}"}, status=400
            )

        registry = load_packs_registry()
        now = datetime.now(timezone.utc).isoformat()

        pack = {
            "id": generate_pack_id(),
            "name": data["name"],
            "description": data.get("description", ""),
            "type": pack_type,
            "difficulty_tier": difficulty_tier,
            "competition_year": data.get("competition_year"),
            "question_ids": [],
            "status": status,
            "created_at": now,
            "updated_at": now,
        }

        if "packs" not in registry:
            registry["packs"] = []
        registry["packs"].append(pack)
        save_packs_registry(registry)

        logger.info(f"Created pack: {pack['id']} - {pack['name']}")

        return web.json_response({"success": True, "pack": pack})

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)
    except Exception:
        logger.exception("Error creating pack")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_get_pack(request: web.Request) -> web.Response:
    """GET /api/kb/packs/{pack_id}

    Get detailed information about a pack including domain groups.
    """
    pack_id = request.match_info["pack_id"]

    if not validate_pack_id(pack_id):
        return web.json_response({"success": False, "error": f"Invalid pack_id: {pack_id}"}, status=400)

    try:
        registry = load_packs_registry()
        questions_store = load_questions_store()

        # Find pack
        pack = None
        for p in registry.get("packs", []):
            if p["id"] == pack_id:
                pack = p
                break

        if not pack:
            return web.json_response({"success": False, "error": f"Pack not found: {pack_id}"}, status=404)

        # Calculate stats
        stats = calculate_pack_stats(pack, questions_store)

        # Get domain groups
        domain_groups = get_domain_groups(pack, questions_store)

        response = {
            "success": True,
            "pack": {
                **pack,
                **stats,
            },
            "domain_groups": domain_groups,
        }

        return web.json_response(response)

    except Exception:
        logger.exception("Error getting pack")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_update_pack(request: web.Request) -> web.Response:
    """PATCH /api/kb/packs/{pack_id}

    Update pack metadata.
    """
    pack_id = request.match_info["pack_id"]

    if not validate_pack_id(pack_id):
        return web.json_response({"success": False, "error": f"Invalid pack_id: {pack_id}"}, status=400)

    try:
        data = await request.json()
        registry = load_packs_registry()

        # Find pack
        pack_idx = None
        for idx, p in enumerate(registry.get("packs", [])):
            if p["id"] == pack_id:
                pack_idx = idx
                break

        if pack_idx is None:
            return web.json_response({"success": False, "error": f"Pack not found: {pack_id}"}, status=404)

        pack = registry["packs"][pack_idx]

        # Check if system pack
        if pack.get("type") == "system" and "type" not in data:
            return web.json_response({"success": False, "error": "Cannot modify system pack"}, status=403)

        # Update allowed fields
        if "name" in data:
            pack["name"] = data["name"]
        if "description" in data:
            pack["description"] = data["description"]
        if "difficulty_tier" in data:
            if data["difficulty_tier"] not in VALID_DIFFICULTY_TIERS:
                return web.json_response(
                    {"success": False, "error": f"Invalid difficulty_tier. Valid: {VALID_DIFFICULTY_TIERS}"},
                    status=400,
                )
            pack["difficulty_tier"] = data["difficulty_tier"]
        if "competition_year" in data:
            pack["competition_year"] = data["competition_year"]
        if "status" in data:
            if data["status"] not in VALID_STATUSES:
                return web.json_response(
                    {"success": False, "error": f"Invalid status. Valid: {VALID_STATUSES}"}, status=400
                )
            pack["status"] = data["status"]

        pack["updated_at"] = datetime.now(timezone.utc).isoformat()
        registry["packs"][pack_idx] = pack
        save_packs_registry(registry)

        logger.info(f"Updated pack: {pack_id}")

        return web.json_response({"success": True, "pack": pack})

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)
    except Exception:
        logger.exception("Error updating pack")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_delete_pack(request: web.Request) -> web.Response:
    """DELETE /api/kb/packs/{pack_id}

    Delete a pack.
    """
    pack_id = request.match_info["pack_id"]

    if not validate_pack_id(pack_id):
        return web.json_response({"success": False, "error": f"Invalid pack_id: {pack_id}"}, status=400)

    try:
        registry = load_packs_registry()

        # Find pack
        pack = None
        for p in registry.get("packs", []):
            if p["id"] == pack_id:
                pack = p
                break

        if not pack:
            return web.json_response({"success": False, "error": f"Pack not found: {pack_id}"}, status=404)

        # Check if system pack
        if pack.get("type") == "system":
            return web.json_response({"success": False, "error": "Cannot delete system pack"}, status=403)

        # Remove pack
        registry["packs"] = [p for p in registry.get("packs", []) if p["id"] != pack_id]
        save_packs_registry(registry)

        logger.info(f"Deleted pack: {pack_id}")

        return web.json_response({"success": True, "pack_id": pack_id})

    except Exception:
        logger.exception("Error deleting pack")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_add_questions_to_pack(request: web.Request) -> web.Response:
    """POST /api/kb/packs/{pack_id}/questions

    Add questions to a pack.

    Request body:
    {
        "question_ids": ["q1", "q2", ...]
    }
    """
    pack_id = request.match_info["pack_id"]

    if not validate_pack_id(pack_id):
        return web.json_response({"success": False, "error": f"Invalid pack_id: {pack_id}"}, status=400)

    try:
        data = await request.json()
        question_ids = data.get("question_ids", [])

        if not question_ids:
            return web.json_response({"success": False, "error": "No question_ids provided"}, status=400)

        registry = load_packs_registry()
        questions_store = load_questions_store()

        # Find pack
        pack_idx = None
        for idx, p in enumerate(registry.get("packs", [])):
            if p["id"] == pack_id:
                pack_idx = idx
                break

        if pack_idx is None:
            return web.json_response({"success": False, "error": f"Pack not found: {pack_id}"}, status=404)

        pack = registry["packs"][pack_idx]

        # Check if system pack
        if pack.get("type") == "system":
            return web.json_response({"success": False, "error": "Cannot modify system pack"}, status=403)

        # Validate question IDs exist
        valid_ids = set(questions_store.get("questions", {}).keys())
        invalid_ids = [qid for qid in question_ids if qid not in valid_ids]
        if invalid_ids:
            return web.json_response(
                {"success": False, "error": f"Invalid question IDs: {invalid_ids[:5]}"}, status=400
            )

        # Add questions (avoid duplicates)
        existing_ids = set(pack.get("question_ids", []))
        added_ids = []
        for qid in question_ids:
            if qid not in existing_ids:
                pack.setdefault("question_ids", []).append(qid)
                existing_ids.add(qid)
                added_ids.append(qid)

                # Update question's pack_ids
                if qid in questions_store["questions"]:
                    q = questions_store["questions"][qid]
                    if pack_id not in q.get("pack_ids", []):
                        q.setdefault("pack_ids", []).append(pack_id)

        pack["updated_at"] = datetime.now(timezone.utc).isoformat()
        registry["packs"][pack_idx] = pack
        save_packs_registry(registry)
        save_questions_store(questions_store)

        logger.info(f"Added {len(added_ids)} questions to pack {pack_id}")

        return web.json_response({"success": True, "added_count": len(added_ids), "added_ids": added_ids})

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)
    except Exception:
        logger.exception("Error adding questions to pack")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_remove_question_from_pack(request: web.Request) -> web.Response:
    """DELETE /api/kb/packs/{pack_id}/questions/{question_id}

    Remove a question from a pack.
    """
    pack_id = request.match_info["pack_id"]
    question_id = request.match_info["question_id"]

    if not validate_pack_id(pack_id):
        return web.json_response({"success": False, "error": f"Invalid pack_id: {pack_id}"}, status=400)

    if not validate_question_id(question_id):
        return web.json_response({"success": False, "error": f"Invalid question_id: {question_id}"}, status=400)

    try:
        registry = load_packs_registry()
        questions_store = load_questions_store()

        # Find pack
        pack_idx = None
        for idx, p in enumerate(registry.get("packs", [])):
            if p["id"] == pack_id:
                pack_idx = idx
                break

        if pack_idx is None:
            return web.json_response({"success": False, "error": f"Pack not found: {pack_id}"}, status=404)

        pack = registry["packs"][pack_idx]

        # Check if system pack
        if pack.get("type") == "system":
            return web.json_response({"success": False, "error": "Cannot modify system pack"}, status=403)

        # Remove question from pack
        if question_id in pack.get("question_ids", []):
            pack["question_ids"].remove(question_id)
            pack["updated_at"] = datetime.now(timezone.utc).isoformat()

            # Update question's pack_ids
            if question_id in questions_store.get("questions", {}):
                q = questions_store["questions"][question_id]
                if pack_id in q.get("pack_ids", []):
                    q["pack_ids"].remove(pack_id)

            registry["packs"][pack_idx] = pack
            save_packs_registry(registry)
            save_questions_store(questions_store)

            logger.info(f"Removed question {question_id} from pack {pack_id}")

            return web.json_response({"success": True})
        else:
            return web.json_response({"success": False, "error": "Question not in pack"}, status=404)

    except Exception:
        logger.exception("Error removing question from pack")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_create_bundle(request: web.Request) -> web.Response:
    """POST /api/kb/packs/bundle

    Create a bundle pack from multiple existing packs.

    Request body:
    {
        "name": "Bundle Name",
        "description": "Description",
        "source_pack_ids": ["pack1", "pack2"],
        "is_reference_bundle": false,
        "deduplication_strategy": "keep_first",
        "excluded_question_ids": [],
        "difficulty_tier": "varsity"
    }
    """
    try:
        data = await request.json()

        # Validate required fields
        if "name" not in data:
            return web.json_response({"success": False, "error": "Missing required field: name"}, status=400)

        source_pack_ids = data.get("source_pack_ids", [])
        if not source_pack_ids:
            return web.json_response({"success": False, "error": "No source_pack_ids provided"}, status=400)

        registry = load_packs_registry()
        questions_store = load_questions_store()

        # Validate source packs exist
        pack_map = {p["id"]: p for p in registry.get("packs", [])}
        invalid_packs = [pid for pid in source_pack_ids if pid not in pack_map]
        if invalid_packs:
            return web.json_response(
                {"success": False, "error": f"Invalid source pack IDs: {invalid_packs}"}, status=400
            )

        # Collect all question IDs from source packs
        all_question_ids = []
        seen_questions: dict[str, str] = {}  # question_text -> first question_id
        duplicates = []
        dedup_strategy = data.get("deduplication_strategy", "keep_first")
        excluded_ids = set(data.get("excluded_question_ids", []))

        for pack_id in source_pack_ids:
            pack = pack_map[pack_id]
            for qid in pack.get("question_ids", []):
                if qid in excluded_ids:
                    continue

                q = questions_store.get("questions", {}).get(qid)
                if not q:
                    continue

                q_text = q.get("question_text", "")

                if dedup_strategy == "keep_first":
                    if q_text in seen_questions:
                        duplicates.append({"question_id": qid, "duplicate_of": seen_questions[q_text]})
                        continue
                    seen_questions[q_text] = qid

                if qid not in all_question_ids:
                    all_question_ids.append(qid)

        # Validate difficulty tier
        difficulty_tier = data.get("difficulty_tier", "varsity")
        if difficulty_tier not in VALID_DIFFICULTY_TIERS:
            return web.json_response(
                {"success": False, "error": f"Invalid difficulty_tier. Valid: {VALID_DIFFICULTY_TIERS}"}, status=400
            )

        now = datetime.now(timezone.utc).isoformat()

        bundle = {
            "id": generate_pack_id(),
            "name": data["name"],
            "description": data.get("description", ""),
            "type": "bundle",
            "difficulty_tier": difficulty_tier,
            "competition_year": data.get("competition_year"),
            "source_pack_ids": source_pack_ids,
            "is_reference_bundle": data.get("is_reference_bundle", False),
            "question_ids": all_question_ids,
            "status": "active",
            "created_at": now,
            "updated_at": now,
        }

        if "packs" not in registry:
            registry["packs"] = []
        registry["packs"].append(bundle)
        save_packs_registry(registry)

        # Update question pack_ids for the bundle
        for qid in all_question_ids:
            if qid in questions_store.get("questions", {}):
                q = questions_store["questions"][qid]
                if bundle["id"] not in q.get("pack_ids", []):
                    q.setdefault("pack_ids", []).append(bundle["id"])
        save_questions_store(questions_store)

        stats = calculate_pack_stats(bundle, questions_store)

        logger.info(f"Created bundle: {bundle['id']} with {len(all_question_ids)} questions from {len(source_pack_ids)} packs")

        return web.json_response(
            {
                "success": True,
                "pack": {**bundle, **stats},
                "duplicates_skipped": len(duplicates),
                "duplicates": duplicates[:20],  # Limit to first 20
            }
        )

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)
    except Exception:
        logger.exception("Error creating bundle")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_preview_deduplication(request: web.Request) -> web.Response:
    """POST /api/kb/packs/preview-dedup

    Preview duplicates before creating a bundle.

    Request body:
    {
        "source_pack_ids": ["pack1", "pack2"]
    }
    """
    try:
        data = await request.json()
        source_pack_ids = data.get("source_pack_ids", [])

        if not source_pack_ids:
            return web.json_response({"success": False, "error": "No source_pack_ids provided"}, status=400)

        registry = load_packs_registry()
        questions_store = load_questions_store()

        pack_map = {p["id"]: p for p in registry.get("packs", [])}

        # Find duplicates
        text_to_occurrences: dict[str, list] = {}

        for pack_id in source_pack_ids:
            if pack_id not in pack_map:
                continue
            pack = pack_map[pack_id]
            for qid in pack.get("question_ids", []):
                q = questions_store.get("questions", {}).get(qid)
                if not q:
                    continue

                q_text = q.get("question_text", "")
                if q_text not in text_to_occurrences:
                    text_to_occurrences[q_text] = []
                text_to_occurrences[q_text].append(
                    {"question_id": qid, "pack_id": pack_id, "pack_name": pack.get("name", "")}
                )

        # Find actual duplicates (more than one occurrence)
        duplicate_groups = []
        total_duplicates = 0
        unique_after_dedup = len(text_to_occurrences)

        for q_text, occurrences in text_to_occurrences.items():
            if len(occurrences) > 1:
                duplicate_groups.append({"question_text": q_text[:100] + "..." if len(q_text) > 100 else q_text, "occurrences": occurrences})
                total_duplicates += len(occurrences) - 1

        return web.json_response(
            {
                "success": True,
                "duplicate_groups": duplicate_groups[:50],  # Limit to 50 groups
                "total_duplicates": total_duplicates,
                "unique_questions_after_dedup": unique_after_dedup,
            }
        )

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)
    except Exception:
        logger.exception("Error previewing deduplication")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


# Question Management Handlers


async def handle_list_questions(request: web.Request) -> web.Response:
    """GET /api/kb/questions

    List questions with optional filtering.

    Query params:
    - pack_id: Filter by pack
    - domain_id: Filter by domain
    - subcategory: Filter by subcategory
    - difficulty: Filter by difficulty (comma-separated, e.g., "1,2,3")
    - question_type: Filter by type
    - has_audio: Filter by audio status
    - status: Filter by status
    - search: Search in question/answer text
    - limit: Max results (default 20)
    - offset: Pagination offset
    """
    try:
        # Parse query params
        pack_id = request.query.get("pack_id")
        domain_id = request.query.get("domain_id")
        subcategory = request.query.get("subcategory")
        difficulty_str = request.query.get("difficulty")
        question_type = request.query.get("question_type")
        has_audio_str = request.query.get("has_audio")
        status = request.query.get("status")
        search = request.query.get("search", "").lower() or None
        limit = min(int(request.query.get("limit", 20)), 100)
        offset = int(request.query.get("offset", 0))

        difficulties = None
        if difficulty_str:
            difficulties = [int(d) for d in difficulty_str.split(",") if d.isdigit()]

        has_audio = None
        if has_audio_str is not None:
            has_audio = has_audio_str.lower() == "true"

        # Try database first
        repo = get_kb_repo(request)
        if repo:
            questions, total = await repo.list_questions(
                pack_id=pack_id,
                domain_id=domain_id,
                subcategory=subcategory,
                difficulties=difficulties,
                question_type=question_type,
                has_audio=has_audio,
                status=status,
                search=search,
                limit=limit,
                offset=offset,
            )
            return web.json_response(
                {
                    "success": True,
                    "questions": questions,
                    "total": total,
                    "limit": limit,
                    "offset": offset,
                    "source": "database",
                }
            )

        # Fallback to JSON store
        questions_store = load_questions_store()
        registry = load_packs_registry()

        # Get questions to filter
        all_questions = list(questions_store.get("questions", {}).values())

        # If pack_id specified, filter to that pack's questions
        if pack_id:
            pack = None
            for p in registry.get("packs", []):
                if p["id"] == pack_id:
                    pack = p
                    break
            if pack:
                pack_question_ids = set(pack.get("question_ids", []))
                all_questions = [q for q in all_questions if q.get("id") in pack_question_ids]

        # Apply filters
        filtered = []
        for q in all_questions:
            if domain_id and q.get("domain_id") != domain_id:
                continue
            if subcategory and q.get("subcategory") != subcategory:
                continue
            if difficulties and q.get("difficulty") not in difficulties:
                continue
            if question_type and q.get("question_type") != question_type:
                continue
            if has_audio is not None:
                q_has_audio = q.get("has_audio", False)
                if has_audio and not q_has_audio:
                    continue
                if not has_audio and q_has_audio:
                    continue
            if status and q.get("status") != status:
                continue
            if search:
                q_text = q.get("question_text", "").lower()
                a_text = q.get("answer_text", "").lower()
                if search not in q_text and search not in a_text:
                    continue

            filtered.append(q)

        # Paginate
        total = len(filtered)
        paginated = filtered[offset : offset + limit]

        return web.json_response(
            {
                "success": True,
                "questions": paginated,
                "total": total,
                "limit": limit,
                "offset": offset,
                "source": "json",
            }
        )

    except Exception:
        logger.exception("Error listing questions")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_create_question(request: web.Request) -> web.Response:
    """POST /api/kb/questions

    Create a new question.

    Request body:
    {
        "domain_id": "science",
        "subcategory": "Physics",
        "question_text": "What is the SI unit of force?",
        "answer_text": "Newton",
        "acceptable_answers": ["Newton", "N"],
        "difficulty": 2,
        "speed_target_seconds": 5.0,
        "question_type": "toss_up",
        "hints": ["Named after a famous scientist"],
        "explanation": "The newton is the SI unit of force...",
        "difficulty_tier": "varsity",
        "question_source": "custom",
        "buzzable": true,
        "pack_ids": ["pack-1"]
    }
    """
    try:
        data = await request.json()

        # Validate required fields
        required = ["domain_id", "question_text", "answer_text"]
        missing = [f for f in required if f not in data]
        if missing:
            return web.json_response(
                {"success": False, "error": f"Missing required fields: {missing}"}, status=400
            )

        # Validate question type
        question_type = data.get("question_type", "toss_up")
        if question_type not in VALID_QUESTION_TYPES:
            return web.json_response(
                {"success": False, "error": f"Invalid question_type. Valid: {VALID_QUESTION_TYPES}"}, status=400
            )

        # Validate difficulty
        difficulty = data.get("difficulty", 2)
        if not (1 <= difficulty <= 5):
            return web.json_response({"success": False, "error": "Difficulty must be 1-5"}, status=400)

        # Validate question source
        question_source = data.get("question_source", "custom")
        if question_source not in VALID_QUESTION_SOURCES:
            return web.json_response(
                {"success": False, "error": f"Invalid question_source. Valid: {VALID_QUESTION_SOURCES}"}, status=400
            )

        questions_store = load_questions_store()
        registry = load_packs_registry()

        now = datetime.now(timezone.utc).isoformat()
        question_id = generate_question_id(data["domain_id"], data.get("subcategory", "general"))

        question = {
            "id": question_id,
            "domain_id": data["domain_id"],
            "subcategory": data.get("subcategory", "General"),
            "question_text": data["question_text"],
            "answer_text": data["answer_text"],
            "acceptable_answers": data.get("acceptable_answers", [data["answer_text"]]),
            "difficulty": difficulty,
            "speed_target_seconds": data.get("speed_target_seconds", 5.0),
            "question_type": question_type,
            "hints": data.get("hints", []),
            "explanation": data.get("explanation", ""),
            "difficulty_tier": data.get("difficulty_tier"),
            "competition_year": data.get("competition_year"),
            "question_source": question_source,
            "buzzable": data.get("buzzable", True),
            "pack_ids": data.get("pack_ids", []),
            "status": data.get("status", "active"),
            "has_audio": False,
            "created_at": now,
            "updated_at": now,
        }

        if "questions" not in questions_store:
            questions_store["questions"] = {}
        questions_store["questions"][question_id] = question
        save_questions_store(questions_store)

        # Add to specified packs
        pack_ids = data.get("pack_ids", [])
        if pack_ids:
            pack_map = {p["id"]: (idx, p) for idx, p in enumerate(registry.get("packs", []))}
            for pack_id in pack_ids:
                if pack_id in pack_map:
                    idx, pack = pack_map[pack_id]
                    if question_id not in pack.get("question_ids", []):
                        pack.setdefault("question_ids", []).append(question_id)
                        pack["updated_at"] = now
                        registry["packs"][idx] = pack
            save_packs_registry(registry)

        logger.info(f"Created question: {question_id}")

        return web.json_response({"success": True, "question": question})

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)
    except Exception:
        logger.exception("Error creating question")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_get_question(request: web.Request) -> web.Response:
    """GET /api/kb/questions/{question_id}

    Get a question by ID.
    """
    question_id = request.match_info["question_id"]

    if not validate_question_id(question_id):
        return web.json_response({"success": False, "error": f"Invalid question_id: {question_id}"}, status=400)

    try:
        questions_store = load_questions_store()

        question = questions_store.get("questions", {}).get(question_id)
        if not question:
            return web.json_response({"success": False, "error": f"Question not found: {question_id}"}, status=404)

        return web.json_response({"success": True, "question": question})

    except Exception:
        logger.exception("Error getting question")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_update_question(request: web.Request) -> web.Response:
    """PATCH /api/kb/questions/{question_id}

    Update a question.
    """
    question_id = request.match_info["question_id"]

    if not validate_question_id(question_id):
        return web.json_response({"success": False, "error": f"Invalid question_id: {question_id}"}, status=400)

    try:
        data = await request.json()
        questions_store = load_questions_store()

        question = questions_store.get("questions", {}).get(question_id)
        if not question:
            return web.json_response({"success": False, "error": f"Question not found: {question_id}"}, status=404)

        # Update allowed fields
        allowed_fields = [
            "domain_id",
            "subcategory",
            "question_text",
            "answer_text",
            "acceptable_answers",
            "difficulty",
            "speed_target_seconds",
            "question_type",
            "hints",
            "explanation",
            "difficulty_tier",
            "competition_year",
            "question_source",
            "buzzable",
            "status",
        ]

        for field in allowed_fields:
            if field in data:
                # Validate specific fields
                if field == "difficulty" and not (1 <= data[field] <= 5):
                    return web.json_response({"success": False, "error": "Difficulty must be 1-5"}, status=400)
                if field == "question_type" and data[field] not in VALID_QUESTION_TYPES:
                    return web.json_response(
                        {"success": False, "error": f"Invalid question_type. Valid: {VALID_QUESTION_TYPES}"},
                        status=400,
                    )
                if field == "question_source" and data[field] not in VALID_QUESTION_SOURCES:
                    return web.json_response(
                        {"success": False, "error": f"Invalid question_source. Valid: {VALID_QUESTION_SOURCES}"},
                        status=400,
                    )
                question[field] = data[field]

        question["updated_at"] = datetime.now(timezone.utc).isoformat()
        questions_store["questions"][question_id] = question
        save_questions_store(questions_store)

        logger.info(f"Updated question: {question_id}")

        return web.json_response({"success": True, "question": question})

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)
    except Exception:
        logger.exception("Error updating question")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_delete_question(request: web.Request) -> web.Response:
    """DELETE /api/kb/questions/{question_id}

    Delete a question.
    """
    question_id = request.match_info["question_id"]

    if not validate_question_id(question_id):
        return web.json_response({"success": False, "error": f"Invalid question_id: {question_id}"}, status=400)

    try:
        questions_store = load_questions_store()
        registry = load_packs_registry()

        question = questions_store.get("questions", {}).get(question_id)
        if not question:
            return web.json_response({"success": False, "error": f"Question not found: {question_id}"}, status=404)

        # Remove from all packs
        for pack in registry.get("packs", []):
            if question_id in pack.get("question_ids", []):
                pack["question_ids"].remove(question_id)
                pack["updated_at"] = datetime.now(timezone.utc).isoformat()
        save_packs_registry(registry)

        # Delete question
        del questions_store["questions"][question_id]
        save_questions_store(questions_store)

        logger.info(f"Deleted question: {question_id}")

        return web.json_response({"success": True, "question_id": question_id})

    except Exception:
        logger.exception("Error deleting question")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_bulk_update_questions(request: web.Request) -> web.Response:
    """POST /api/kb/questions/bulk-update

    Bulk update multiple questions.

    Request body:
    {
        "question_ids": ["q1", "q2"],
        "updates": {
            "difficulty": 3,
            "status": "active"
        }
    }
    """
    try:
        data = await request.json()

        question_ids = data.get("question_ids", [])
        updates = data.get("updates", {})

        if not question_ids:
            return web.json_response({"success": False, "error": "No question_ids provided"}, status=400)

        if not updates:
            return web.json_response({"success": False, "error": "No updates provided"}, status=400)

        questions_store = load_questions_store()

        # Validate updates
        if "difficulty" in updates and not (1 <= updates["difficulty"] <= 5):
            return web.json_response({"success": False, "error": "Difficulty must be 1-5"}, status=400)
        if "question_type" in updates and updates["question_type"] not in VALID_QUESTION_TYPES:
            return web.json_response(
                {"success": False, "error": f"Invalid question_type. Valid: {VALID_QUESTION_TYPES}"}, status=400
            )
        if "status" in updates and updates["status"] not in VALID_STATUSES:
            return web.json_response(
                {"success": False, "error": f"Invalid status. Valid: {VALID_STATUSES}"}, status=400
            )

        now = datetime.now(timezone.utc).isoformat()
        updated_count = 0
        errors = []

        for qid in question_ids:
            question = questions_store.get("questions", {}).get(qid)
            if not question:
                errors.append({"question_id": qid, "error": "Not found"})
                continue

            for field, value in updates.items():
                if field in ["difficulty", "status", "question_type", "difficulty_tier", "question_source"]:
                    question[field] = value

            question["updated_at"] = now
            questions_store["questions"][qid] = question
            updated_count += 1

        save_questions_store(questions_store)

        logger.info(f"Bulk updated {updated_count} questions")

        return web.json_response({"success": True, "affected_count": updated_count, "errors": errors if errors else None})

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)
    except Exception:
        logger.exception("Error bulk updating questions")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_import_from_module(request: web.Request) -> web.Response:
    """POST /api/kb/import-from-module

    Import questions from the Knowledge Bowl module into a pack.

    Request body:
    {
        "pack_id": "target-pack-id",
        "domains": ["science", "mathematics"],  // optional, all if not specified
        "difficulties": [1, 2, 3]  // optional, all if not specified
    }
    """
    try:
        data = await request.json()
        pack_id = data.get("pack_id")

        if not pack_id:
            return web.json_response({"success": False, "error": "pack_id is required"}, status=400)

        if not validate_pack_id(pack_id):
            return web.json_response({"success": False, "error": f"Invalid pack_id: {pack_id}"}, status=400)

        # Load KB module content
        module_content = load_module_content("knowledge-bowl")
        if not module_content:
            return web.json_response({"success": False, "error": "Knowledge Bowl module not found"}, status=404)

        registry = load_packs_registry()
        questions_store = load_questions_store()

        # Find pack
        pack_idx = None
        for idx, p in enumerate(registry.get("packs", [])):
            if p["id"] == pack_id:
                pack_idx = idx
                break

        if pack_idx is None:
            return web.json_response({"success": False, "error": f"Pack not found: {pack_id}"}, status=404)

        pack = registry["packs"][pack_idx]

        # Filter options
        filter_domains = data.get("domains")
        filter_difficulties = data.get("difficulties")

        # Import questions
        imported_count = 0
        skipped_count = 0
        now = datetime.now(timezone.utc).isoformat()

        for domain in module_content.get("domains", []):
            domain_id = domain.get("id")

            if filter_domains and domain_id not in filter_domains:
                continue

            for q in domain.get("questions", []):
                difficulty = q.get("difficulty", 2)
                if filter_difficulties and difficulty not in filter_difficulties:
                    continue

                question_id = q.get("id")

                # Check if already exists
                if question_id in questions_store.get("questions", {}):
                    # Add to pack if not already there
                    if question_id not in pack.get("question_ids", []):
                        pack.setdefault("question_ids", []).append(question_id)
                        existing_q = questions_store["questions"][question_id]
                        if pack_id not in existing_q.get("pack_ids", []):
                            existing_q.setdefault("pack_ids", []).append(pack_id)
                    else:
                        skipped_count += 1
                    continue

                # Create new question record
                question = {
                    "id": question_id,
                    "domain_id": q.get("domain_id", domain_id),
                    "subcategory": q.get("subcategory", "General"),
                    "question_text": q.get("question_text", ""),
                    "answer_text": q.get("answer_text", ""),
                    "acceptable_answers": q.get("acceptable_answers", []),
                    "difficulty": difficulty,
                    "speed_target_seconds": q.get("speed_target_seconds", 5.0),
                    "question_type": q.get("question_type", "toss-up").replace("-", "_"),
                    "hints": q.get("hints", []),
                    "explanation": q.get("explanation", ""),
                    "question_source": "naqt",  # From KB module
                    "buzzable": True,
                    "pack_ids": [pack_id],
                    "status": "active",
                    "has_audio": False,
                    "created_at": now,
                    "updated_at": now,
                }

                questions_store.setdefault("questions", {})[question_id] = question
                pack.setdefault("question_ids", []).append(question_id)
                imported_count += 1

        pack["updated_at"] = now
        registry["packs"][pack_idx] = pack
        save_packs_registry(registry)
        save_questions_store(questions_store)

        logger.info(f"Imported {imported_count} questions from KB module to pack {pack_id}")

        return web.json_response(
            {
                "success": True,
                "imported_count": imported_count,
                "skipped_count": skipped_count,
            }
        )

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)
    except Exception:
        logger.exception("Error importing from module")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_list_domains(request: web.Request) -> web.Response:
    """GET /api/kb/domains

    List all Knowledge Bowl domains.
    """
    try:
        repo = get_kb_repo(request)
        if repo:
            domains = await repo.list_domains()
            return web.json_response({"success": True, "domains": domains, "source": "database"})

        # Fallback to hardcoded domains from module
        module_content = load_module_content("knowledge-bowl")
        if module_content:
            domains = [
                {
                    "id": d["id"],
                    "name": d["name"],
                    "icon_name": d.get("icon_name"),
                    "weight": d.get("weight", 0.1),
                    "subcategories": d.get("subcategories", []),
                }
                for d in module_content.get("domains", [])
            ]
            return web.json_response({"success": True, "domains": domains, "source": "module"})

        return web.json_response({"success": True, "domains": [], "source": "none"})

    except Exception:
        logger.exception("Error listing domains")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


def _convert_difficulty_to_numeric(difficulty: str) -> int:
    """Convert string difficulty tier to numeric 1-5 scale."""
    mapping = {
        "elementary": 1,
        "middle_school": 2,
        "jv": 3,
        "varsity": 4,
        "championship": 5,
        "college": 5,
    }
    return mapping.get(difficulty.lower().replace(" ", "_"), 3)


def _transform_importer_question(q: dict) -> dict:
    """Transform a question from importer format to database format."""
    answer = q.get("answer", {})
    if isinstance(answer, str):
        answer_text = answer
        acceptable = []
    else:
        answer_text = answer.get("primary", "")
        acceptable = answer.get("acceptable", [])

    # Determine question type from tags
    tags = q.get("tags", [])
    question_type = "toss_up"
    if "bonus" in tags:
        question_type = "bonus"
    elif "lightning" in tags:
        question_type = "lightning"

    # Map domain names
    domain = q.get("domain", "miscellaneous").lower().replace(" ", "_")
    domain_mapping = {
        "science": "science",
        "biology": "science",
        "chemistry": "science",
        "physics": "science",
        "earth_science": "science",
        "math": "mathematics",
        "mathematics": "mathematics",
        "history": "history",
        "geography": "social_studies",
        "social_science": "social_studies",
        "literature": "literature",
        "fine_arts": "arts",
        "arts": "arts",
        "music": "arts",
        "current_events": "current_events",
        "mythology": "religion_philosophy",
        "religion": "religion_philosophy",
        "philosophy": "religion_philosophy",
        "sports": "pop_culture",
        "pop_culture": "pop_culture",
        "technology": "technology",
        "trash": "miscellaneous",
    }
    domain_id = domain_mapping.get(domain, "miscellaneous")

    # Determine difficulty
    diff_str = q.get("difficulty", "varsity")
    if isinstance(diff_str, int):
        difficulty = max(1, min(5, diff_str))
    else:
        difficulty = _convert_difficulty_to_numeric(diff_str)

    # Determine source
    source_str = q.get("source", "")
    if "science bowl" in source_str.lower():
        question_source = "nsb"
    elif "naqt" in source_str.lower():
        question_source = "naqt"
    elif "qbreader" in source_str.lower() or "packet" in source_str.lower():
        question_source = "qb_packets"
    elif "opentriviadb" in source_str.lower() or "trivia" in source_str.lower():
        question_source = "custom"
    else:
        question_source = "custom"

    return {
        "id": q.get("id"),
        "domain_id": domain_id,
        "subcategory": q.get("subdomain", q.get("subcategory", "General")),
        "question_text": q.get("text", q.get("question_text", "")),
        "answer_text": answer_text,
        "acceptable_answers": acceptable,
        "difficulty": difficulty,
        "difficulty_tier": diff_str if isinstance(diff_str, str) else None,
        "speed_target_seconds": 5.0,
        "question_type": question_type,
        "question_source": question_source,
        "buzzable": q.get("suitability", {}).get("forOral", True),
        "hints": q.get("hints", []),
        "explanation": q.get("explanation", ""),
        "has_audio": False,
        "status": "active",
    }


def _load_importer_questions() -> list[dict]:
    """Load questions from importer output files."""
    questions = []
    seen_ids = set()

    # Paths to check for importer output
    importer_paths = [
        Path(__file__).parent.parent / "importers" / "output" / "kb-all-questions.json",
        Path(__file__).parent.parent / "importers" / "plugins" / "sources" / "output" / "kb-all-questions.json",
    ]

    for path in importer_paths:
        if path.exists():
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
                    q_list = data.get("questions", data) if isinstance(data, dict) else data
                    if isinstance(q_list, list):
                        for q in q_list:
                            q_id = q.get("id")
                            if q_id and q_id not in seen_ids:
                                seen_ids.add(q_id)
                                transformed = _transform_importer_question(q)
                                if transformed.get("question_text"):
                                    questions.append(transformed)
                logger.info(f"Loaded {len(questions)} questions from {path}")
            except Exception as e:
                logger.warning(f"Failed to load questions from {path}: {e}")

    return questions


async def handle_sync_to_database(request: web.Request) -> web.Response:
    """POST /api/kb/sync-to-database

    Sync all questions from Knowledge Bowl module and importer outputs into the database.
    This is the primary way to populate the database with questions.
    """
    try:
        repo = get_kb_repo(request)
        if not repo:
            return web.json_response(
                {"success": False, "error": "Database not available. Check DATABASE_URL configuration."},
                status=503,
            )

        questions_to_import = []
        seen_ids = set()

        # 1. Load from KB module content (sample questions)
        module_content = load_module_content("knowledge-bowl")
        if module_content:
            for domain in module_content.get("domains", []):
                domain_id = domain.get("id")
                for q in domain.get("questions", []):
                    q_id = q.get("id")
                    if q_id and q_id not in seen_ids:
                        seen_ids.add(q_id)
                        question = {
                            "id": q_id,
                            "domain_id": q.get("domain_id", domain_id),
                            "subcategory": q.get("subcategory", "General"),
                            "question_text": q.get("question_text", ""),
                            "answer_text": q.get("answer_text", ""),
                            "acceptable_answers": q.get("acceptable_answers", []),
                            "difficulty": q.get("difficulty", 2),
                            "speed_target_seconds": q.get("speed_target_seconds", 5.0),
                            "question_type": q.get("question_type", "toss-up").replace("-", "_"),
                            "question_source": "naqt",
                            "buzzable": True,
                            "hints": q.get("hints", []),
                            "explanation": q.get("explanation", ""),
                            "has_audio": False,
                            "status": "active",
                        }
                        questions_to_import.append(question)

        module_count = len(questions_to_import)
        logger.info(f"Loaded {module_count} questions from module content")

        # 2. Load from importer output files
        importer_questions = _load_importer_questions()
        for q in importer_questions:
            q_id = q.get("id")
            if q_id and q_id not in seen_ids:
                seen_ids.add(q_id)
                questions_to_import.append(q)

        importer_count = len(questions_to_import) - module_count
        logger.info(f"Loaded {importer_count} additional questions from importers")

        # Import all questions in batches
        batch_size = 1000
        total_imported = 0
        for i in range(0, len(questions_to_import), batch_size):
            batch = questions_to_import[i : i + batch_size]
            imported = await repo.import_questions_bulk(batch)
            total_imported += imported
            logger.info(f"Imported batch {i // batch_size + 1}: {imported} questions")

        total_count = await repo.get_question_count()
        domain_counts = await repo.get_domain_question_counts()

        logger.info(f"Synced {total_imported} questions to database. Total: {total_count}")

        return web.json_response(
            {
                "success": True,
                "imported_count": total_imported,
                "module_questions": module_count,
                "importer_questions": importer_count,
                "total_questions": total_count,
                "domain_counts": domain_counts,
            }
        )

    except Exception:
        logger.exception("Error syncing to database")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


async def handle_database_status(request: web.Request) -> web.Response:
    """GET /api/kb/database-status

    Check the status of the KB questions database.
    """
    try:
        repo = get_kb_repo(request)
        if not repo:
            return web.json_response(
                {
                    "success": True,
                    "database_available": False,
                    "message": "Database not configured. Using JSON storage.",
                }
            )

        total_count = await repo.get_question_count()
        domain_counts = await repo.get_domain_question_counts()

        return web.json_response(
            {
                "success": True,
                "database_available": True,
                "total_questions": total_count,
                "domain_counts": domain_counts,
            }
        )

    except Exception:
        logger.exception("Error checking database status")
        return web.json_response({"success": False, "error": "Internal server error"}, status=500)


def register_kb_packs_routes(app: web.Application):
    """Register all KB packs management routes."""
    from feature_flag_guard import guarded_routes
    from feature_flag_keys import FlagKeys

    router = guarded_routes(app, FlagKeys.KB_PACKS)

    # Database status and sync
    router.add_get("/api/kb/database-status", handle_database_status)
    router.add_post("/api/kb/sync-to-database", handle_sync_to_database)
    router.add_get("/api/kb/domains", handle_list_domains)

    # Pack management
    router.add_get("/api/kb/packs", handle_list_packs)
    router.add_post("/api/kb/packs", handle_create_pack)
    router.add_get("/api/kb/packs/{pack_id}", handle_get_pack)
    router.add_patch("/api/kb/packs/{pack_id}", handle_update_pack)
    router.add_delete("/api/kb/packs/{pack_id}", handle_delete_pack)

    # Pack question management
    router.add_post("/api/kb/packs/{pack_id}/questions", handle_add_questions_to_pack)
    router.add_delete("/api/kb/packs/{pack_id}/questions/{question_id}", handle_remove_question_from_pack)

    # Bundle operations
    router.add_post("/api/kb/packs/bundle", handle_create_bundle)
    router.add_post("/api/kb/packs/preview-dedup", handle_preview_deduplication)

    # Question management
    router.add_get("/api/kb/questions", handle_list_questions)
    router.add_post("/api/kb/questions", handle_create_question)
    router.add_get("/api/kb/questions/{question_id}", handle_get_question)
    router.add_patch("/api/kb/questions/{question_id}", handle_update_question)
    router.add_delete("/api/kb/questions/{question_id}", handle_delete_question)
    router.add_post("/api/kb/questions/bulk-update", handle_bulk_update_questions)

    # Import
    router.add_post("/api/kb/import-from-module", handle_import_from_module)

    # Ensure directory exists
    ensure_packs_directory()

    logger.info("KB Packs API routes registered")
