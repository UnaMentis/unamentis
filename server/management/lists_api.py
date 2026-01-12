"""
API routes for curriculum lists management.

These routes enable users to:
- Create and manage personal curriculum lists
- Add/remove courses to/from lists
- Share lists with other users
- Query list memberships for courses
"""

import logging
from typing import Optional
from uuid import UUID

from aiohttp import web

logger = logging.getLogger(__name__)

# Reference to the aiohttp app for database access
_app: Optional[web.Application] = None


async def handle_get_lists(request: web.Request) -> web.Response:
    """GET /api/lists - Get user's lists and shared lists."""
    try:
        pool = request.app["db_pool"]

        # For now, get all lists (in production, filter by user_id)
        async with pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT
                    l.id, l.name, l.description, l.is_shared,
                    l.created_at, l.updated_at,
                    COUNT(li.id) as item_count
                FROM curriculum_lists l
                LEFT JOIN curriculum_list_items li ON l.id = li.list_id
                GROUP BY l.id
                ORDER BY l.updated_at DESC
            """)

            lists = []
            for row in rows:
                lists.append({
                    "id": str(row["id"]),
                    "name": row["name"],
                    "description": row["description"],
                    "isShared": row["is_shared"],
                    "itemCount": row["item_count"],
                    "createdAt": row["created_at"].isoformat() if row["created_at"] else None,
                    "updatedAt": row["updated_at"].isoformat() if row["updated_at"] else None,
                })

            return web.json_response({"lists": lists})
    except Exception as e:
        logger.error(f"Error fetching lists: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_create_list(request: web.Request) -> web.Response:
    """POST /api/lists - Create a new list."""
    try:
        data = await request.json()
        name = data.get("name")
        description = data.get("description", "")
        is_shared = data.get("isShared", False)

        if not name:
            return web.json_response({"error": "Name is required"}, status=400)

        pool = request.app["db_pool"]
        async with pool.acquire() as conn:
            row = await conn.fetchrow("""
                INSERT INTO curriculum_lists (name, description, is_shared)
                VALUES ($1, $2, $3)
                RETURNING id, name, description, is_shared, created_at, updated_at
            """, name, description, is_shared)

            return web.json_response({
                "id": str(row["id"]),
                "name": row["name"],
                "description": row["description"],
                "isShared": row["is_shared"],
                "itemCount": 0,
                "createdAt": row["created_at"].isoformat() if row["created_at"] else None,
                "updatedAt": row["updated_at"].isoformat() if row["updated_at"] else None,
            }, status=201)
    except Exception as e:
        logger.error(f"Error creating list: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_list(request: web.Request) -> web.Response:
    """GET /api/lists/{id} - Get a list with its items."""
    try:
        list_id = request.match_info["id"]
        pool = request.app["db_pool"]

        async with pool.acquire() as conn:
            # Get list details
            list_row = await conn.fetchrow("""
                SELECT id, name, description, is_shared, created_at, updated_at
                FROM curriculum_lists
                WHERE id = $1
            """, UUID(list_id))

            if not list_row:
                return web.json_response({"error": "List not found"}, status=404)

            # Get list items
            item_rows = await conn.fetch("""
                SELECT id, source_id, course_id, course_title,
                       course_thumbnail_url, notes, order_index, added_at
                FROM curriculum_list_items
                WHERE list_id = $1
                ORDER BY order_index, added_at
            """, UUID(list_id))

            items = []
            for row in item_rows:
                items.append({
                    "id": str(row["id"]),
                    "sourceId": row["source_id"],
                    "courseId": row["course_id"],
                    "courseTitle": row["course_title"],
                    "courseThumbnailUrl": row["course_thumbnail_url"],
                    "notes": row["notes"],
                    "orderIndex": row["order_index"],
                    "addedAt": row["added_at"].isoformat() if row["added_at"] else None,
                })

            return web.json_response({
                "id": str(list_row["id"]),
                "name": list_row["name"],
                "description": list_row["description"],
                "isShared": list_row["is_shared"],
                "itemCount": len(items),
                "items": items,
                "createdAt": list_row["created_at"].isoformat() if list_row["created_at"] else None,
                "updatedAt": list_row["updated_at"].isoformat() if list_row["updated_at"] else None,
            })
    except Exception as e:
        logger.error(f"Error fetching list: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_update_list(request: web.Request) -> web.Response:
    """PUT /api/lists/{id} - Update a list."""
    try:
        list_id = request.match_info["id"]
        data = await request.json()

        pool = request.app["db_pool"]
        async with pool.acquire() as conn:
            # Build update query dynamically
            updates = []
            params = []
            param_idx = 1

            if "name" in data:
                updates.append(f"name = ${param_idx}")
                params.append(data["name"])
                param_idx += 1

            if "description" in data:
                updates.append(f"description = ${param_idx}")
                params.append(data["description"])
                param_idx += 1

            if "isShared" in data:
                updates.append(f"is_shared = ${param_idx}")
                params.append(data["isShared"])
                param_idx += 1

            if not updates:
                return web.json_response({"error": "No fields to update"}, status=400)

            updates.append("updated_at = NOW()")
            params.append(UUID(list_id))

            query = f"""
                UPDATE curriculum_lists
                SET {", ".join(updates)}
                WHERE id = ${param_idx}
                RETURNING id, name, description, is_shared, created_at, updated_at
            """

            row = await conn.fetchrow(query, *params)

            if not row:
                return web.json_response({"error": "List not found"}, status=404)

            return web.json_response({
                "id": str(row["id"]),
                "name": row["name"],
                "description": row["description"],
                "isShared": row["is_shared"],
                "createdAt": row["created_at"].isoformat() if row["created_at"] else None,
                "updatedAt": row["updated_at"].isoformat() if row["updated_at"] else None,
            })
    except Exception as e:
        logger.error(f"Error updating list: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_delete_list(request: web.Request) -> web.Response:
    """DELETE /api/lists/{id} - Delete a list."""
    try:
        list_id = request.match_info["id"]
        pool = request.app["db_pool"]

        async with pool.acquire() as conn:
            result = await conn.execute("""
                DELETE FROM curriculum_lists WHERE id = $1
            """, UUID(list_id))

            if result == "DELETE 0":
                return web.json_response({"error": "List not found"}, status=404)

            return web.json_response({"success": True})
    except Exception as e:
        logger.error(f"Error deleting list: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_add_items_to_list(request: web.Request) -> web.Response:
    """POST /api/lists/{id}/items - Add courses to a list (supports bulk)."""
    try:
        list_id = request.match_info["id"]
        data = await request.json()

        # Support both single item and bulk items
        items = data.get("items", [])
        if not items and "sourceId" in data:
            # Single item format
            items = [{
                "sourceId": data["sourceId"],
                "courseId": data["courseId"],
                "courseTitle": data.get("courseTitle"),
                "courseThumbnailUrl": data.get("courseThumbnailUrl"),
                "notes": data.get("notes"),
            }]

        if not items:
            return web.json_response({"error": "No items provided"}, status=400)

        pool = request.app["db_pool"]
        async with pool.acquire() as conn:
            # Verify list exists
            list_exists = await conn.fetchval("""
                SELECT EXISTS(SELECT 1 FROM curriculum_lists WHERE id = $1)
            """, UUID(list_id))

            if not list_exists:
                return web.json_response({"error": "List not found"}, status=404)

            # Get current max order_index
            max_order = await conn.fetchval("""
                SELECT COALESCE(MAX(order_index), 0)
                FROM curriculum_list_items
                WHERE list_id = $1
            """, UUID(list_id))

            added_items = []
            for i, item in enumerate(items):
                try:
                    row = await conn.fetchrow("""
                        INSERT INTO curriculum_list_items
                            (list_id, source_id, course_id, course_title,
                             course_thumbnail_url, notes, order_index)
                        VALUES ($1, $2, $3, $4, $5, $6, $7)
                        ON CONFLICT (list_id, source_id, course_id) DO NOTHING
                        RETURNING id, source_id, course_id, course_title,
                                  course_thumbnail_url, notes, order_index, added_at
                    """, UUID(list_id), item["sourceId"], item["courseId"],
                        item.get("courseTitle"), item.get("courseThumbnailUrl"),
                        item.get("notes"), max_order + i + 1)

                    if row:
                        added_items.append({
                            "id": str(row["id"]),
                            "sourceId": row["source_id"],
                            "courseId": row["course_id"],
                            "courseTitle": row["course_title"],
                            "courseThumbnailUrl": row["course_thumbnail_url"],
                            "notes": row["notes"],
                            "orderIndex": row["order_index"],
                            "addedAt": row["added_at"].isoformat() if row["added_at"] else None,
                        })
                except Exception as item_error:
                    logger.warning(f"Failed to add item: {item_error}")

            # Update list's updated_at
            await conn.execute("""
                UPDATE curriculum_lists SET updated_at = NOW() WHERE id = $1
            """, UUID(list_id))

            return web.json_response({
                "addedCount": len(added_items),
                "items": added_items,
            }, status=201)
    except Exception as e:
        logger.error(f"Error adding items to list: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_remove_item_from_list(request: web.Request) -> web.Response:
    """DELETE /api/lists/{id}/items/{item_id} - Remove an item from a list."""
    try:
        list_id = request.match_info["id"]
        item_id = request.match_info["item_id"]

        pool = request.app["db_pool"]
        async with pool.acquire() as conn:
            result = await conn.execute("""
                DELETE FROM curriculum_list_items
                WHERE list_id = $1 AND id = $2
            """, UUID(list_id), UUID(item_id))

            if result == "DELETE 0":
                return web.json_response({"error": "Item not found"}, status=404)

            # Update list's updated_at
            await conn.execute("""
                UPDATE curriculum_lists SET updated_at = NOW() WHERE id = $1
            """, UUID(list_id))

            return web.json_response({"success": True})
    except Exception as e:
        logger.error(f"Error removing item from list: {e}")
        return web.json_response({"error": str(e)}, status=500)


async def handle_get_list_memberships(request: web.Request) -> web.Response:
    """GET /api/lists/memberships - Get list memberships for course IDs."""
    try:
        source_id = request.query.get("source_id")
        course_ids_param = request.query.get("course_ids", "")

        if not source_id or not course_ids_param:
            return web.json_response({"error": "source_id and course_ids required"}, status=400)

        course_ids = [cid.strip() for cid in course_ids_param.split(",") if cid.strip()]

        pool = request.app["db_pool"]
        async with pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT li.course_id, l.id as list_id, l.name as list_name
                FROM curriculum_list_items li
                JOIN curriculum_lists l ON li.list_id = l.id
                WHERE li.source_id = $1 AND li.course_id = ANY($2)
            """, source_id, course_ids)

            # Group by course_id
            memberships = {}
            for row in rows:
                course_id = row["course_id"]
                if course_id not in memberships:
                    memberships[course_id] = []
                memberships[course_id].append({
                    "id": str(row["list_id"]),
                    "name": row["list_name"],
                })

            return web.json_response({"memberships": memberships})
    except Exception as e:
        logger.error(f"Error fetching list memberships: {e}")
        return web.json_response({"error": str(e)}, status=500)


def register_lists_routes(app: web.Application):
    """Register all list-related routes on the application."""
    global _app
    _app = app

    # Lists CRUD
    app.router.add_get("/api/lists", handle_get_lists)
    app.router.add_post("/api/lists", handle_create_list)
    app.router.add_get("/api/lists/{id}", handle_get_list)
    app.router.add_put("/api/lists/{id}", handle_update_list)
    app.router.add_delete("/api/lists/{id}", handle_delete_list)

    # List items
    app.router.add_post("/api/lists/{id}/items", handle_add_items_to_list)
    app.router.add_delete("/api/lists/{id}/items/{item_id}", handle_remove_item_from_list)

    # Memberships query
    app.router.add_get("/api/lists/memberships", handle_get_list_memberships)

    logger.info("Lists API routes registered")
