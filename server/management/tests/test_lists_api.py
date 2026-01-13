"""
Tests for Lists API routes.
"""
import pytest
from uuid import UUID, uuid4
from datetime import datetime
from unittest.mock import MagicMock, AsyncMock
from aiohttp import web


class MockRow(dict):
    """Mock database row that supports both dict and attribute access."""

    def __getitem__(self, key):
        return super().get(key)

    def __getattr__(self, key):
        try:
            return self[key]
        except KeyError:
            raise AttributeError(key)


class MockConnection:
    """Mock asyncpg connection for testing."""

    def __init__(self, data_store: dict):
        self.data_store = data_store
        self.executed_queries = []

    async def fetch(self, query: str, *args):
        self.executed_queries.append(("fetch", query, args))

        if "curriculum_lists" in query and "curriculum_list_items" in query.lower() and "count" in query.lower():
            # Get lists query
            return [
                MockRow({
                    "id": UUID("11111111-1111-1111-1111-111111111111"),
                    "name": "My List",
                    "description": "A test list",
                    "is_shared": False,
                    "created_at": datetime(2024, 1, 1),
                    "updated_at": datetime(2024, 1, 2),
                    "item_count": 2,
                }),
                MockRow({
                    "id": UUID("22222222-2222-2222-2222-222222222222"),
                    "name": "Shared List",
                    "description": "A shared list",
                    "is_shared": True,
                    "created_at": datetime(2024, 1, 1),
                    "updated_at": datetime(2024, 1, 2),
                    "item_count": 0,
                }),
            ]
        elif "curriculum_list_items" in query and "WHERE list_id" in query:
            # Get items for a list
            list_id = args[0] if args else None
            if list_id == UUID("11111111-1111-1111-1111-111111111111"):
                return [
                    MockRow({
                        "id": UUID("aaaa1111-1111-1111-1111-111111111111"),
                        "source_id": "mit_ocw",
                        "course_id": "6-001",
                        "course_title": "Structure and Interpretation",
                        "course_thumbnail_url": "http://example.com/thumb.jpg",
                        "notes": "Great course",
                        "order_index": 1,
                        "added_at": datetime(2024, 1, 1),
                    }),
                ]
            return []
        elif "curriculum_list_items li" in query and "JOIN curriculum_lists l" in query:
            # Memberships query
            return [
                MockRow({
                    "course_id": "6-001",
                    "list_id": UUID("11111111-1111-1111-1111-111111111111"),
                    "list_name": "My List",
                }),
            ]

        return []

    async def fetchrow(self, query: str, *args):
        self.executed_queries.append(("fetchrow", query, args))

        if "INSERT INTO curriculum_lists" in query:
            return MockRow({
                "id": UUID("33333333-3333-3333-3333-333333333333"),
                "name": args[0] if args else "New List",
                "description": args[1] if len(args) > 1 else "",
                "is_shared": args[2] if len(args) > 2 else False,
                "created_at": datetime.now(),
                "updated_at": datetime.now(),
            })
        elif "SELECT id, name, description" in query and "curriculum_lists" in query and "WHERE id" in query:
            # Get single list
            list_id = args[0] if args else None
            if list_id == UUID("11111111-1111-1111-1111-111111111111"):
                return MockRow({
                    "id": UUID("11111111-1111-1111-1111-111111111111"),
                    "name": "My List",
                    "description": "A test list",
                    "is_shared": False,
                    "created_at": datetime(2024, 1, 1),
                    "updated_at": datetime(2024, 1, 2),
                })
            elif list_id == UUID("99999999-9999-9999-9999-999999999999"):
                return None  # Not found
            return None
        elif "UPDATE curriculum_lists" in query:
            return MockRow({
                "id": args[-1] if args else UUID("11111111-1111-1111-1111-111111111111"),
                "name": "Updated List",
                "description": "Updated description",
                "is_shared": True,
                "created_at": datetime(2024, 1, 1),
                "updated_at": datetime.now(),
            })
        elif "INSERT INTO curriculum_list_items" in query:
            return MockRow({
                "id": UUID("bbbb1111-1111-1111-1111-111111111111"),
                "source_id": args[1] if len(args) > 1 else "mit_ocw",
                "course_id": args[2] if len(args) > 2 else "6-001",
                "course_title": args[3] if len(args) > 3 else "Test Course",
                "course_thumbnail_url": args[4] if len(args) > 4 else None,
                "notes": args[5] if len(args) > 5 else None,
                "order_index": args[6] if len(args) > 6 else 1,
                "added_at": datetime.now(),
            })

        return None

    async def fetchval(self, query: str, *args):
        self.executed_queries.append(("fetchval", query, args))

        if "EXISTS" in query and "curriculum_lists" in query:
            list_id = args[0] if args else None
            if list_id == UUID("11111111-1111-1111-1111-111111111111"):
                return True
            return False
        elif "MAX(order_index)" in query:
            return 5

        return None

    async def execute(self, query: str, *args):
        self.executed_queries.append(("execute", query, args))

        if "DELETE FROM curriculum_lists" in query:
            list_id = args[0] if args else None
            if list_id == UUID("11111111-1111-1111-1111-111111111111"):
                return "DELETE 1"
            return "DELETE 0"
        elif "DELETE FROM curriculum_list_items" in query:
            if len(args) >= 2:
                list_id, item_id = args[0], args[1]
                if list_id == UUID("11111111-1111-1111-1111-111111111111") and \
                   item_id == UUID("aaaa1111-1111-1111-1111-111111111111"):
                    return "DELETE 1"
            return "DELETE 0"
        elif "UPDATE curriculum_lists SET updated_at" in query:
            return "UPDATE 1"

        return "EXECUTE"


class MockPool:
    """Mock database connection pool."""

    def __init__(self):
        self.data_store = {}
        self._connection = None

    def acquire(self):
        """Return an async context manager that yields a connection."""
        return MockPoolContextManager(self)


class MockPoolContextManager:
    """Async context manager for mock pool."""

    def __init__(self, pool):
        self.pool = pool

    async def __aenter__(self):
        self.pool._connection = MockConnection(self.pool.data_store)
        return self.pool._connection

    async def __aexit__(self, *args):
        pass


# Import the module under test
import lists_api


@pytest.fixture
def mock_app():
    """Create a mock aiohttp application."""
    app = web.Application()
    app["db_pool"] = MockPool()
    return app


@pytest.fixture
def mock_request(mock_app):
    """Create a factory for mock requests."""
    def _make_request(method="GET", json_data=None, query=None, match_info=None):
        request = MagicMock(spec=web.Request)
        request.app = mock_app
        request.method = method
        request.query = query or {}
        request.match_info = match_info or {}

        if json_data is not None:
            async def mock_json():
                return json_data
            request.json = mock_json
        else:
            async def mock_json():
                raise ValueError("No JSON")
            request.json = mock_json

        return request
    return _make_request


# =============================================================================
# Get Lists Tests
# =============================================================================

class TestHandleGetLists:
    """Tests for handle_get_lists endpoint."""

    @pytest.mark.asyncio
    async def test_get_lists_success(self, mock_request):
        """Test successful retrieval of all lists."""
        request = mock_request(method="GET")
        response = await lists_api.handle_get_lists(request)

        assert response.status == 200
        assert response.content_type == "application/json"

    @pytest.mark.asyncio
    async def test_get_lists_db_error(self, mock_request, mock_app):
        """Test handling of database error."""
        # Make pool raise an exception
        mock_app["db_pool"].acquire = MagicMock(side_effect=Exception("DB error"))

        request = mock_request(method="GET")
        response = await lists_api.handle_get_lists(request)

        assert response.status == 500


# =============================================================================
# Create List Tests
# =============================================================================

class TestHandleCreateList:
    """Tests for handle_create_list endpoint."""

    @pytest.mark.asyncio
    async def test_create_list_success(self, mock_request):
        """Test successful list creation."""
        request = mock_request(json_data={
            "name": "My New List",
            "description": "A description",
            "isShared": False
        })

        response = await lists_api.handle_create_list(request)

        assert response.status == 201
        assert response.content_type == "application/json"

    @pytest.mark.asyncio
    async def test_create_list_missing_name(self, mock_request):
        """Test list creation without name fails."""
        request = mock_request(json_data={
            "description": "No name provided"
        })

        response = await lists_api.handle_create_list(request)

        assert response.status == 400
        assert b"Name is required" in response.body

    @pytest.mark.asyncio
    async def test_create_list_defaults(self, mock_request):
        """Test list creation with minimal data uses defaults."""
        request = mock_request(json_data={
            "name": "Minimal List"
        })

        response = await lists_api.handle_create_list(request)

        assert response.status == 201


# =============================================================================
# Get Single List Tests
# =============================================================================

class TestHandleGetList:
    """Tests for handle_get_list endpoint."""

    @pytest.mark.asyncio
    async def test_get_list_success(self, mock_request):
        """Test successful retrieval of single list."""
        request = mock_request(
            method="GET",
            match_info={"id": "11111111-1111-1111-1111-111111111111"}
        )

        response = await lists_api.handle_get_list(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_get_list_not_found(self, mock_request):
        """Test retrieval of non-existent list."""
        request = mock_request(
            method="GET",
            match_info={"id": "99999999-9999-9999-9999-999999999999"}
        )

        response = await lists_api.handle_get_list(request)

        assert response.status == 404
        assert b"List not found" in response.body


# =============================================================================
# Update List Tests
# =============================================================================

class TestHandleUpdateList:
    """Tests for handle_update_list endpoint."""

    @pytest.mark.asyncio
    async def test_update_list_name(self, mock_request):
        """Test updating list name."""
        request = mock_request(
            method="PUT",
            match_info={"id": "11111111-1111-1111-1111-111111111111"},
            json_data={"name": "Updated Name"}
        )

        response = await lists_api.handle_update_list(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_update_list_description(self, mock_request):
        """Test updating list description."""
        request = mock_request(
            method="PUT",
            match_info={"id": "11111111-1111-1111-1111-111111111111"},
            json_data={"description": "New description"}
        )

        response = await lists_api.handle_update_list(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_update_list_shared(self, mock_request):
        """Test updating list sharing status."""
        request = mock_request(
            method="PUT",
            match_info={"id": "11111111-1111-1111-1111-111111111111"},
            json_data={"isShared": True}
        )

        response = await lists_api.handle_update_list(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_update_list_no_fields(self, mock_request):
        """Test update with no fields fails."""
        request = mock_request(
            method="PUT",
            match_info={"id": "11111111-1111-1111-1111-111111111111"},
            json_data={}
        )

        response = await lists_api.handle_update_list(request)

        assert response.status == 400
        assert b"No fields to update" in response.body


# =============================================================================
# Delete List Tests
# =============================================================================

class TestHandleDeleteList:
    """Tests for handle_delete_list endpoint."""

    @pytest.mark.asyncio
    async def test_delete_list_success(self, mock_request):
        """Test successful list deletion."""
        request = mock_request(
            method="DELETE",
            match_info={"id": "11111111-1111-1111-1111-111111111111"}
        )

        response = await lists_api.handle_delete_list(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_delete_list_not_found(self, mock_request):
        """Test deletion of non-existent list."""
        request = mock_request(
            method="DELETE",
            match_info={"id": "99999999-9999-9999-9999-999999999999"}
        )

        response = await lists_api.handle_delete_list(request)

        assert response.status == 404


# =============================================================================
# Add Items Tests
# =============================================================================

class TestHandleAddItemsToList:
    """Tests for handle_add_items_to_list endpoint."""

    @pytest.mark.asyncio
    async def test_add_single_item(self, mock_request):
        """Test adding a single item to list."""
        request = mock_request(
            method="POST",
            match_info={"id": "11111111-1111-1111-1111-111111111111"},
            json_data={
                "sourceId": "mit_ocw",
                "courseId": "6-001",
                "courseTitle": "SICP",
            }
        )

        response = await lists_api.handle_add_items_to_list(request)

        assert response.status == 201

    @pytest.mark.asyncio
    async def test_add_bulk_items(self, mock_request):
        """Test adding multiple items to list."""
        request = mock_request(
            method="POST",
            match_info={"id": "11111111-1111-1111-1111-111111111111"},
            json_data={
                "items": [
                    {"sourceId": "mit_ocw", "courseId": "6-001"},
                    {"sourceId": "mit_ocw", "courseId": "6-002"},
                ]
            }
        )

        response = await lists_api.handle_add_items_to_list(request)

        assert response.status == 201

    @pytest.mark.asyncio
    async def test_add_items_no_items(self, mock_request):
        """Test adding with no items fails."""
        request = mock_request(
            method="POST",
            match_info={"id": "11111111-1111-1111-1111-111111111111"},
            json_data={"items": []}
        )

        response = await lists_api.handle_add_items_to_list(request)

        assert response.status == 400
        assert b"No items provided" in response.body

    @pytest.mark.asyncio
    async def test_add_items_list_not_found(self, mock_request):
        """Test adding items to non-existent list."""
        request = mock_request(
            method="POST",
            match_info={"id": "99999999-9999-9999-9999-999999999999"},
            json_data={
                "sourceId": "mit_ocw",
                "courseId": "6-001"
            }
        )

        response = await lists_api.handle_add_items_to_list(request)

        assert response.status == 404


# =============================================================================
# Remove Item Tests
# =============================================================================

class TestHandleRemoveItemFromList:
    """Tests for handle_remove_item_from_list endpoint."""

    @pytest.mark.asyncio
    async def test_remove_item_success(self, mock_request):
        """Test successful item removal."""
        request = mock_request(
            method="DELETE",
            match_info={
                "id": "11111111-1111-1111-1111-111111111111",
                "item_id": "aaaa1111-1111-1111-1111-111111111111"
            }
        )

        response = await lists_api.handle_remove_item_from_list(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_remove_item_not_found(self, mock_request):
        """Test removal of non-existent item."""
        request = mock_request(
            method="DELETE",
            match_info={
                "id": "11111111-1111-1111-1111-111111111111",
                "item_id": "99999999-9999-9999-9999-999999999999"
            }
        )

        response = await lists_api.handle_remove_item_from_list(request)

        assert response.status == 404


# =============================================================================
# Get List Memberships Tests
# =============================================================================

class TestHandleGetListMemberships:
    """Tests for handle_get_list_memberships endpoint."""

    @pytest.mark.asyncio
    async def test_get_memberships_success(self, mock_request):
        """Test successful membership retrieval."""
        request = mock_request(
            method="GET",
            query={
                "source_id": "mit_ocw",
                "course_ids": "6-001,6-002"
            }
        )

        response = await lists_api.handle_get_list_memberships(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_get_memberships_missing_source(self, mock_request):
        """Test membership query without source_id."""
        request = mock_request(
            method="GET",
            query={"course_ids": "6-001,6-002"}
        )

        response = await lists_api.handle_get_list_memberships(request)

        assert response.status == 400
        assert b"source_id" in response.body

    @pytest.mark.asyncio
    async def test_get_memberships_missing_course_ids(self, mock_request):
        """Test membership query without course_ids."""
        request = mock_request(
            method="GET",
            query={"source_id": "mit_ocw"}
        )

        response = await lists_api.handle_get_list_memberships(request)

        assert response.status == 400
        assert b"course_ids" in response.body


# =============================================================================
# Route Registration Tests
# =============================================================================

class TestRegisterRoutes:
    """Tests for route registration."""

    def test_register_lists_routes(self):
        """Test that list routes are registered correctly."""
        app = web.Application()
        app["db_pool"] = MockPool()

        lists_api.register_lists_routes(app)

        route_paths = [r.resource.canonical for r in app.router.routes()]

        assert "/api/lists" in route_paths
        assert "/api/lists/{id}" in route_paths
        assert "/api/lists/{id}/items" in route_paths
        assert "/api/lists/{id}/items/{item_id}" in route_paths
        assert "/api/lists/memberships" in route_paths


# =============================================================================
# Edge Cases and Error Handling
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and error handling."""

    @pytest.mark.asyncio
    async def test_invalid_uuid_format(self, mock_request):
        """Test handling of invalid UUID format."""
        request = mock_request(
            method="GET",
            match_info={"id": "not-a-valid-uuid"}
        )

        response = await lists_api.handle_get_list(request)

        # Should return 500 because UUID() will throw
        assert response.status == 500

    @pytest.mark.asyncio
    async def test_db_error_on_create(self, mock_request, mock_app):
        """Test database error during create."""
        # Create a pool that will error on acquire
        class ErrorPool:
            def acquire(self):
                raise Exception("Database connection failed")

        mock_app["db_pool"] = ErrorPool()

        request = mock_request(json_data={"name": "Test"})
        response = await lists_api.handle_create_list(request)

        assert response.status == 500

    @pytest.mark.asyncio
    async def test_whitespace_course_ids(self, mock_request):
        """Test handling of whitespace in course_ids."""
        request = mock_request(
            method="GET",
            query={
                "source_id": "mit_ocw",
                "course_ids": "6-001 , 6-002 ,  6-003"
            }
        )

        response = await lists_api.handle_get_list_memberships(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_empty_course_ids_list(self, mock_request):
        """Test handling of empty course_ids after parsing."""
        request = mock_request(
            method="GET",
            query={
                "source_id": "mit_ocw",
                "course_ids": ""
            }
        )

        response = await lists_api.handle_get_list_memberships(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_item_with_all_optional_fields(self, mock_request):
        """Test adding item with all optional fields."""
        request = mock_request(
            method="POST",
            match_info={"id": "11111111-1111-1111-1111-111111111111"},
            json_data={
                "sourceId": "mit_ocw",
                "courseId": "6-001",
                "courseTitle": "SICP",
                "courseThumbnailUrl": "http://example.com/thumb.jpg",
                "notes": "Important course"
            }
        )

        response = await lists_api.handle_add_items_to_list(request)

        assert response.status == 201

    @pytest.mark.asyncio
    async def test_update_multiple_fields(self, mock_request):
        """Test updating multiple fields at once."""
        request = mock_request(
            method="PUT",
            match_info={"id": "11111111-1111-1111-1111-111111111111"},
            json_data={
                "name": "New Name",
                "description": "New description",
                "isShared": True
            }
        )

        response = await lists_api.handle_update_list(request)

        assert response.status == 200
