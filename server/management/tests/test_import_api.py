"""
Tests for Import API routes.

This module provides comprehensive tests for the curriculum import API,
including source browsing, course catalog operations, import job management,
and import status tracking.
"""
import pytest
from datetime import datetime
from unittest.mock import MagicMock, AsyncMock, patch
from aiohttp import web


# =============================================================================
# Mock Classes
# =============================================================================

class MockSourceInfo:
    """Mock source info."""

    def __init__(self, source_id: str, name: str = None):
        self.source_id = source_id
        self.name = name or f"Source {source_id}"

    def to_dict(self):
        return {
            "source_id": self.source_id,
            "name": self.name,
        }


class MockLicenseResult:
    """Mock license validation result."""

    def __init__(self, can_import: bool = True, warnings: list = None, attribution_text: str = None):
        self.can_import = can_import
        self.warnings = warnings or []
        self.attribution_text = attribution_text or "Attribution required"


class MockCourse:
    """Mock course."""

    def __init__(self, course_id: str, title: str = None, level: str = None):
        self.id = course_id
        self.title = title or f"Course {course_id}"
        self.level = level or "undergraduate"

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "level": self.level,
        }


class MockCourseDetail:
    """Mock course detail."""

    def __init__(self, course_id: str):
        self.course_id = course_id
        self.title = f"Course {course_id}"

    def to_dict(self):
        return {
            "course_id": self.course_id,
            "title": self.title,
        }


class MockSourceHandler:
    """Mock source handler."""

    def __init__(self):
        self.source_info = MockSourceInfo("mit_ocw", "MIT OpenCourseWare")

    async def get_course_catalog(self, page=1, page_size=20, filters=None, search=None):
        courses = [
            MockCourse("6-001", "SICP", "undergraduate"),
            MockCourse("6-002", "Circuits", "graduate"),
        ]
        return courses, 2, {"subjects": ["CS"], "levels": ["undergraduate", "graduate"]}

    async def search_courses(self, query, limit=20):
        return [MockCourse("6-001", "SICP")]

    async def get_course_detail(self, course_id):
        if course_id == "not_found":
            raise ValueError("Course not found")
        return MockCourseDetail(course_id)

    def validate_license(self, course_id):
        if course_id == "restricted":
            return MockLicenseResult(can_import=False, warnings=["License restricts redistribution"])
        return MockLicenseResult(can_import=True)


class MockSourceHandlerEmptyCourses:
    """Mock source handler that returns empty courses list."""

    def __init__(self):
        self.source_info = MockSourceInfo("empty_source", "Empty Source")

    async def get_course_catalog(self, page=1, page_size=20, filters=None, search=None):
        return [], 0, {"subjects": [], "levels": []}

    async def search_courses(self, query, limit=20):
        return []

    async def get_course_detail(self, course_id):
        raise ValueError("Course not found")

    def validate_license(self, course_id):
        return MockLicenseResult(can_import=True)


class MockSourceHandlerWithNullLevel:
    """Mock source handler with courses that have null levels."""

    def __init__(self):
        self.source_info = MockSourceInfo("null_level_source", "Null Level Source")

    async def get_course_catalog(self, page=1, page_size=20, filters=None, search=None):
        courses = [
            MockCourse("course-1", "Course 1", None),
            MockCourse("course-2", "Course 2", "introductory"),
        ]
        return courses, 2, {}

    async def search_courses(self, query, limit=20):
        return []

    async def get_course_detail(self, course_id):
        return MockCourseDetail(course_id)

    def validate_license(self, course_id):
        return MockLicenseResult(can_import=True)


class MockSourceHandlerRaisesCatalogError:
    """Mock source handler that raises errors on catalog operations."""

    def __init__(self):
        self.source_info = MockSourceInfo("error_source", "Error Source")

    async def get_course_catalog(self, page=1, page_size=20, filters=None, search=None):
        raise Exception("Catalog fetch failed")

    async def search_courses(self, query, limit=20):
        raise Exception("Search failed")

    async def get_course_detail(self, course_id):
        raise Exception("Detail fetch failed")

    def validate_license(self, course_id):
        return MockLicenseResult(can_import=True)


class MockImportProgress:
    """Mock import progress."""

    def __init__(self, job_id: str, status: str = "running"):
        self.id = job_id
        self.status = status
        self.config = MagicMock()
        self.config.source_id = "mit_ocw"
        self.config.course_id = "6-001"
        self.result = MagicMock()
        self.result.curriculum_id = "uuid-123"

    def to_dict(self):
        return {
            "id": self.id,
            "status": self.status,
        }


class MockImportProgressComplete:
    """Mock import progress for completed imports."""

    def __init__(self, job_id: str):
        self.id = job_id
        self.status = MagicMock()
        self.status.value = "complete"
        # Need to set this to match ImportStatus.COMPLETE
        self.config = MagicMock()
        self.config.source_id = "mit_ocw"
        self.config.course_id = "6-001"
        self.result = MagicMock()
        self.result.curriculum_id = "uuid-123"

    def to_dict(self):
        return {
            "id": self.id,
            "status": "complete",
        }


class MockOrchestrator:
    """Mock import orchestrator."""

    def __init__(self):
        self._jobs = {}
        self._callbacks = []

    def add_progress_callback(self, callback):
        self._callbacks.append(callback)

    async def start_import(self, config):
        job_id = "job-123"
        self._jobs[job_id] = MockImportProgress(job_id)
        return job_id

    def get_progress(self, job_id):
        return self._jobs.get(job_id)

    def list_jobs(self, status=None):
        jobs = list(self._jobs.values())
        if status:
            jobs = [j for j in jobs if j.status == status.value]
        return jobs

    async def cancel_import(self, job_id):
        if job_id in self._jobs:
            del self._jobs[job_id]
            return True
        return False


class MockOrchestratorRaisesError:
    """Mock orchestrator that raises errors."""

    def __init__(self):
        self._jobs = {}
        self._callbacks = []

    def add_progress_callback(self, callback):
        self._callbacks.append(callback)

    async def start_import(self, config):
        raise Exception("Import start failed")

    def get_progress(self, job_id):
        raise Exception("Progress fetch failed")

    def list_jobs(self, status=None):
        raise Exception("List jobs failed")

    async def cancel_import(self, job_id):
        raise Exception("Cancel failed")


class MockRow(dict):
    """Mock database row."""

    def __getitem__(self, key):
        return super().get(key)


class MockConnection:
    """Mock database connection."""

    def __init__(self, rows=None, should_raise=False):
        self.executed_queries = []
        self._rows = rows
        self._should_raise = should_raise

    async def fetch(self, query, *args):
        if self._should_raise:
            raise Exception("Database error")
        self.executed_queries.append(("fetch", query, args))
        if self._rows is not None:
            return self._rows
        return [
            MockRow({
                "course_id": "6-001",
                "curriculum_id": "uuid-123",
                "imported_at": datetime(2024, 1, 1),
            })
        ]

    async def execute(self, query, *args):
        if self._should_raise:
            raise Exception("Database execute error")
        self.executed_queries.append(("execute", query, args))
        return "OK"


class MockPool:
    """Mock database pool."""

    def __init__(self, rows=None, should_raise=False):
        self._connection = None
        self._rows = rows
        self._should_raise = should_raise

    def acquire(self):
        return MockPoolContextManager(self)


class MockPoolContextManager:
    """Async context manager for mock pool."""

    def __init__(self, pool):
        self.pool = pool

    async def __aenter__(self):
        self.pool._connection = MockConnection(
            rows=self.pool._rows,
            should_raise=self.pool._should_raise
        )
        return self.pool._connection

    async def __aexit__(self, *args):
        pass


# Import the module under test
import import_api


# =============================================================================
# Fixtures
# =============================================================================

@pytest.fixture
def mock_app():
    """Create a mock aiohttp application."""
    app = web.Application()
    app["db_pool"] = MockPool()
    return app


@pytest.fixture
def mock_request(mock_app):
    """Create a factory for mock requests."""
    def _make_request(method="GET", json_data=None, query=None, match_info=None, app=None):
        request = MagicMock(spec=web.Request)
        request.app = app if app is not None else mock_app
        request.method = method
        request.query = query or {}
        request.match_info = match_info or {}
        request.remote = "127.0.0.1"

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


@pytest.fixture
def mock_app_no_db():
    """Create a mock aiohttp application without database."""
    return web.Application()


@pytest.fixture
def mock_app_with_error_db():
    """Create a mock aiohttp application with an error-prone database."""
    app = web.Application()
    app["db_pool"] = MockPool(should_raise=True)
    return app


# =============================================================================
# Source Routes Tests
# =============================================================================

class TestHandleGetSources:
    """Tests for handle_get_sources endpoint."""

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_sources_success(self, mock_registry, mock_request):
        """Test successful sources retrieval."""
        mock_registry.get_all_sources.return_value = [
            MockSourceInfo("mit_ocw"),
            MockSourceInfo("khan_academy"),
        ]

        request = mock_request(method="GET")
        response = await import_api.handle_get_sources(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_sources_error(self, mock_registry, mock_request):
        """Test error handling in sources retrieval."""
        mock_registry.get_all_sources.side_effect = Exception("Registry error")

        request = mock_request(method="GET")
        response = await import_api.handle_get_sources(request)

        assert response.status == 500

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_sources_empty(self, mock_registry, mock_request):
        """Test empty sources list."""
        mock_registry.get_all_sources.return_value = []

        request = mock_request(method="GET")
        response = await import_api.handle_get_sources(request)

        assert response.status == 200


class TestHandleGetSource:
    """Tests for handle_get_source endpoint."""

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_source_success(self, mock_registry, mock_request):
        """Test successful source retrieval."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"}
        )
        response = await import_api.handle_get_source(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_source_not_found(self, mock_registry, mock_request):
        """Test source not found."""
        mock_registry.get_handler.return_value = None

        request = mock_request(
            method="GET",
            match_info={"source_id": "unknown"}
        )
        response = await import_api.handle_get_source(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_source_error(self, mock_registry, mock_request):
        """Test error handling in source retrieval."""
        mock_registry.get_handler.side_effect = Exception("Handler error")

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"}
        )
        response = await import_api.handle_get_source(request)

        assert response.status == 500


# =============================================================================
# Course Catalog Routes Tests
# =============================================================================

class TestHandleGetCourses:
    """Tests for handle_get_courses endpoint."""

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_success(self, mock_registry, mock_request):
        """Test successful courses retrieval."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={"page": "1", "pageSize": "20"}
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_source_not_found(self, mock_registry, mock_request):
        """Test courses for non-existent source."""
        mock_registry.get_handler.return_value = None

        request = mock_request(
            method="GET",
            match_info={"source_id": "unknown"}
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_with_filters(self, mock_registry, mock_request):
        """Test courses with filters."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={
                "page": "1",
                "subject": "CS",
                "level": "undergraduate",
                "features": "video,transcript"
            }
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_with_sort(self, mock_registry, mock_request):
        """Test courses with sorting."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={
                "sortBy": "title",
                "sortOrder": "desc"
            }
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_sort_by_level(self, mock_registry, mock_request):
        """Test courses sorted by level."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={"sortBy": "level"}
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_sort_by_date(self, mock_registry, mock_request):
        """Test courses sorted by date."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={"sortBy": "date", "sortOrder": "desc"}
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_empty_list(self, mock_registry, mock_request):
        """Test courses with empty list result."""
        mock_registry.get_handler.return_value = MockSourceHandlerEmptyCourses()

        request = mock_request(
            method="GET",
            match_info={"source_id": "empty_source"},
            query={"sortBy": "title"}
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_sort_with_null_level(self, mock_registry, mock_request):
        """Test courses sorted by level with null level values."""
        mock_registry.get_handler.return_value = MockSourceHandlerWithNullLevel()

        request = mock_request(
            method="GET",
            match_info={"source_id": "null_level_source"},
            query={"sortBy": "level", "sortOrder": "asc"}
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_error(self, mock_registry, mock_request):
        """Test error handling in courses retrieval."""
        mock_registry.get_handler.return_value = MockSourceHandlerRaisesCatalogError()

        request = mock_request(
            method="GET",
            match_info={"source_id": "error_source"},
            query={"page": "1"}
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 500

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_courses_sort_relevance(self, mock_registry, mock_request):
        """Test courses sorted by relevance (no sorting applied)."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={"sortBy": "relevance"}
        )
        response = await import_api.handle_get_courses(request)

        assert response.status == 200


class TestHandleSearchCourses:
    """Tests for handle_search_courses endpoint."""

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_search_courses_success(self, mock_registry, mock_request):
        """Test successful course search."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={"q": "algorithms", "limit": "10"}
        )
        response = await import_api.handle_search_courses(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_search_courses_source_not_found(self, mock_registry, mock_request):
        """Test search for non-existent source."""
        mock_registry.get_handler.return_value = None

        request = mock_request(
            method="GET",
            match_info={"source_id": "unknown"},
            query={"q": "test"}
        )
        response = await import_api.handle_search_courses(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_search_courses_no_query(self, mock_registry, mock_request):
        """Test search without query."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={}
        )
        response = await import_api.handle_search_courses(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_search_courses_error(self, mock_registry, mock_request):
        """Test error handling in course search."""
        mock_registry.get_handler.return_value = MockSourceHandlerRaisesCatalogError()

        request = mock_request(
            method="GET",
            match_info={"source_id": "error_source"},
            query={"q": "test"}
        )
        response = await import_api.handle_search_courses(request)

        assert response.status == 500

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_search_courses_default_limit(self, mock_registry, mock_request):
        """Test search with default limit."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={"q": "algorithms"}
        )
        response = await import_api.handle_search_courses(request)

        assert response.status == 200


class TestHandleGetCourseDetail:
    """Tests for handle_get_course_detail endpoint."""

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_course_detail_success(self, mock_registry, mock_request):
        """Test successful course detail retrieval."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw", "course_id": "6-001"}
        )
        response = await import_api.handle_get_course_detail(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_course_detail_source_not_found(self, mock_registry, mock_request):
        """Test course detail for non-existent source."""
        mock_registry.get_handler.return_value = None

        request = mock_request(
            method="GET",
            match_info={"source_id": "unknown", "course_id": "123"}
        )
        response = await import_api.handle_get_course_detail(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_course_detail_course_not_found(self, mock_registry, mock_request):
        """Test course detail for non-existent course."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw", "course_id": "not_found"}
        )
        response = await import_api.handle_get_course_detail(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('import_api.SourceRegistry')
    async def test_get_course_detail_error(self, mock_registry, mock_request):
        """Test error handling in course detail retrieval."""
        mock_registry.get_handler.return_value = MockSourceHandlerRaisesCatalogError()

        request = mock_request(
            method="GET",
            match_info={"source_id": "error_source", "course_id": "123"}
        )
        response = await import_api.handle_get_course_detail(request)

        assert response.status == 500


# =============================================================================
# Import Job Routes Tests
# =============================================================================

class TestHandleStartImport:
    """Tests for handle_start_import endpoint."""

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    @patch('import_api.SourceRegistry')
    @patch('import_api.ImportConfig')
    async def test_start_import_success(
        self, mock_config, mock_registry, mock_orchestrator, mock_request
    ):
        """Test successful import start."""
        mock_registry.get_handler.return_value = MockSourceHandler()
        mock_orchestrator.return_value = MockOrchestrator()

        config = MagicMock()
        config.source_id = "mit_ocw"
        config.course_id = "6-001"
        config.selected_lectures = []
        config.include_transcripts = True
        config.include_videos = False
        mock_config.from_dict.return_value = config

        request = mock_request(json_data={
            "sourceId": "mit_ocw",
            "courseId": "6-001",
            "outputName": "sicp",
        })
        response = await import_api.handle_start_import(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    @patch('import_api.SourceRegistry')
    @patch('import_api.ImportConfig')
    async def test_start_import_source_not_found(
        self, mock_config, mock_registry, mock_orchestrator, mock_request
    ):
        """Test import start with non-existent source."""
        mock_registry.get_handler.return_value = None
        config = MagicMock()
        config.source_id = "unknown"
        config.course_id = "123"
        mock_config.from_dict.return_value = config

        request = mock_request(json_data={
            "sourceId": "unknown",
            "courseId": "123",
            "outputName": "test",
        })
        response = await import_api.handle_start_import(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    @patch('import_api.SourceRegistry')
    @patch('import_api.ImportConfig')
    async def test_start_import_license_restricted(
        self, mock_config, mock_registry, mock_orchestrator, mock_request
    ):
        """Test import start with license restriction."""
        handler = MockSourceHandler()
        mock_registry.get_handler.return_value = handler

        config = MagicMock()
        config.source_id = "mit_ocw"
        config.course_id = "restricted"
        mock_config.from_dict.return_value = config

        request = mock_request(json_data={
            "sourceId": "mit_ocw",
            "courseId": "restricted",
            "outputName": "test",
        })
        response = await import_api.handle_start_import(request)

        assert response.status == 403

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    @patch('import_api.SourceRegistry')
    @patch('import_api.ImportConfig')
    async def test_start_import_error(
        self, mock_config, mock_registry, mock_orchestrator, mock_request
    ):
        """Test error handling in import start."""
        mock_registry.get_handler.return_value = MockSourceHandler()
        mock_orchestrator.return_value = MockOrchestratorRaisesError()

        config = MagicMock()
        config.source_id = "mit_ocw"
        config.course_id = "6-001"
        config.selected_lectures = []
        config.include_transcripts = True
        config.include_videos = False
        mock_config.from_dict.return_value = config

        request = mock_request(json_data={
            "sourceId": "mit_ocw",
            "courseId": "6-001",
            "outputName": "sicp",
        })
        response = await import_api.handle_start_import(request)

        assert response.status == 500

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    @patch('import_api.SourceRegistry')
    @patch('import_api.ImportConfig')
    async def test_start_import_json_error(
        self, mock_config, mock_registry, mock_orchestrator, mock_request
    ):
        """Test error handling when JSON parsing fails."""
        request = mock_request()  # No JSON data
        response = await import_api.handle_start_import(request)

        assert response.status == 500


class TestHandleGetImportProgress:
    """Tests for handle_get_import_progress endpoint."""

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    async def test_get_progress_success(self, mock_orchestrator, mock_request):
        """Test successful progress retrieval."""
        orch = MockOrchestrator()
        orch._jobs["job-123"] = MockImportProgress("job-123")
        mock_orchestrator.return_value = orch

        request = mock_request(
            method="GET",
            match_info={"job_id": "job-123"}
        )
        response = await import_api.handle_get_import_progress(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    async def test_get_progress_not_found(self, mock_orchestrator, mock_request):
        """Test progress for non-existent job."""
        mock_orchestrator.return_value = MockOrchestrator()

        request = mock_request(
            method="GET",
            match_info={"job_id": "unknown"}
        )
        response = await import_api.handle_get_import_progress(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    async def test_get_progress_error(self, mock_orchestrator, mock_request):
        """Test error handling in progress retrieval."""
        mock_orchestrator.return_value = MockOrchestratorRaisesError()

        request = mock_request(
            method="GET",
            match_info={"job_id": "job-123"}
        )
        response = await import_api.handle_get_import_progress(request)

        assert response.status == 500


class TestHandleListImports:
    """Tests for handle_list_imports endpoint."""

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    async def test_list_imports_success(self, mock_orchestrator, mock_request):
        """Test successful imports list."""
        orch = MockOrchestrator()
        orch._jobs["job-1"] = MockImportProgress("job-1")
        mock_orchestrator.return_value = orch

        request = mock_request(method="GET")
        response = await import_api.handle_list_imports(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.ImportStatus')
    @patch('import_api.get_orchestrator')
    async def test_list_imports_with_status_filter(
        self, mock_orchestrator, mock_status, mock_request
    ):
        """Test imports list with status filter."""
        mock_orchestrator.return_value = MockOrchestrator()
        mock_status.return_value = MagicMock(value="running")

        request = mock_request(
            method="GET",
            query={"status": "running"}
        )
        response = await import_api.handle_list_imports(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.ImportStatus')
    @patch('import_api.get_orchestrator')
    async def test_list_imports_invalid_status(
        self, mock_orchestrator, mock_status, mock_request
    ):
        """Test imports list with invalid status."""
        mock_orchestrator.return_value = MockOrchestrator()
        mock_status.side_effect = ValueError("Invalid status")

        request = mock_request(
            method="GET",
            query={"status": "invalid"}
        )
        response = await import_api.handle_list_imports(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    async def test_list_imports_error(self, mock_orchestrator, mock_request):
        """Test error handling in imports list."""
        mock_orchestrator.return_value = MockOrchestratorRaisesError()

        request = mock_request(method="GET")
        response = await import_api.handle_list_imports(request)

        assert response.status == 500

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    async def test_list_imports_empty(self, mock_orchestrator, mock_request):
        """Test empty imports list."""
        mock_orchestrator.return_value = MockOrchestrator()

        request = mock_request(method="GET")
        response = await import_api.handle_list_imports(request)

        assert response.status == 200


class TestHandleCancelImport:
    """Tests for handle_cancel_import endpoint."""

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    async def test_cancel_import_success(self, mock_orchestrator, mock_request):
        """Test successful import cancel."""
        orch = MockOrchestrator()
        orch._jobs["job-123"] = MockImportProgress("job-123")
        mock_orchestrator.return_value = orch

        request = mock_request(
            method="DELETE",
            match_info={"job_id": "job-123"}
        )
        response = await import_api.handle_cancel_import(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    async def test_cancel_import_not_found(self, mock_orchestrator, mock_request):
        """Test cancel of non-existent job."""
        mock_orchestrator.return_value = MockOrchestrator()

        request = mock_request(
            method="DELETE",
            match_info={"job_id": "unknown"}
        )
        response = await import_api.handle_cancel_import(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch('import_api.get_orchestrator')
    async def test_cancel_import_error(self, mock_orchestrator, mock_request):
        """Test error handling in import cancel."""
        mock_orchestrator.return_value = MockOrchestratorRaisesError()

        request = mock_request(
            method="DELETE",
            match_info={"job_id": "job-123"}
        )
        response = await import_api.handle_cancel_import(request)

        assert response.status == 500


# =============================================================================
# Import Status Routes Tests
# =============================================================================

class TestHandleGetImportStatus:
    """Tests for handle_get_import_status endpoint."""

    @pytest.mark.asyncio
    async def test_get_import_status_success(self, mock_request):
        """Test successful import status retrieval."""
        request = mock_request(
            method="GET",
            query={
                "source_id": "mit_ocw",
                "course_ids": "6-001,6-002"
            }
        )
        response = await import_api.handle_get_import_status(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_get_import_status_no_source_id(self, mock_request):
        """Test import status without source_id."""
        request = mock_request(
            method="GET",
            query={"course_ids": "6-001"}
        )
        response = await import_api.handle_get_import_status(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_get_import_status_no_db(self, mock_request, mock_app):
        """Test import status without database."""
        del mock_app["db_pool"]

        request = mock_request(
            method="GET",
            query={"source_id": "mit_ocw"}
        )
        response = await import_api.handle_get_import_status(request)

        assert response.status == 503

    @pytest.mark.asyncio
    async def test_get_import_status_no_course_ids(self, mock_request):
        """Test import status without specific course_ids (query all for source)."""
        request = mock_request(
            method="GET",
            query={"source_id": "mit_ocw"}
        )
        response = await import_api.handle_get_import_status(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_get_import_status_empty_course_ids(self, mock_request):
        """Test import status with empty course_ids string."""
        request = mock_request(
            method="GET",
            query={
                "source_id": "mit_ocw",
                "course_ids": ""
            }
        )
        response = await import_api.handle_get_import_status(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_get_import_status_database_error(self, mock_request, mock_app_with_error_db):
        """Test import status with database error."""
        request = mock_request(
            method="GET",
            query={"source_id": "mit_ocw", "course_ids": "6-001"},
            app=mock_app_with_error_db
        )
        response = await import_api.handle_get_import_status(request)

        assert response.status == 500

    @pytest.mark.asyncio
    async def test_get_import_status_with_not_imported_courses(self, mock_request):
        """Test import status includes entries for courses not imported."""
        # The mock connection returns 6-001 as imported, so 6-002 should be marked not imported
        request = mock_request(
            method="GET",
            query={
                "source_id": "mit_ocw",
                "course_ids": "6-001,6-002,6-003"
            }
        )
        response = await import_api.handle_get_import_status(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_get_import_status_null_curriculum_id(self, mock_request, mock_app):
        """Test import status with null curriculum_id in database."""
        mock_app["db_pool"] = MockPool(rows=[
            MockRow({
                "course_id": "6-001",
                "curriculum_id": None,
                "imported_at": None,
            })
        ])

        request = mock_request(
            method="GET",
            query={"source_id": "mit_ocw", "course_ids": "6-001"}
        )
        response = await import_api.handle_get_import_status(request)

        assert response.status == 200


# =============================================================================
# Helper Function Tests
# =============================================================================

class TestSetImportCompleteCallback:
    """Tests for set_import_complete_callback helper."""

    def test_sets_callback(self):
        """Test setting the callback."""
        callback = MagicMock()
        import_api.set_import_complete_callback(callback)
        assert import_api._on_import_complete_callback == callback

    def test_sets_callback_to_none(self):
        """Test setting the callback to None."""
        import_api.set_import_complete_callback(None)
        assert import_api._on_import_complete_callback is None


class TestGetOrchestrator:
    """Tests for get_orchestrator helper."""

    @patch('import_api._orchestrator', None)
    @patch('import_api.ImportOrchestrator')
    def test_creates_orchestrator_on_first_call(self, mock_class):
        """Test that orchestrator is created on first call."""
        mock_class.return_value = MockOrchestrator()
        result = import_api.get_orchestrator()
        mock_class.assert_called_once()

    @patch('import_api.ImportOrchestrator')
    def test_returns_existing_orchestrator(self, mock_class):
        """Test that existing orchestrator is returned on subsequent calls."""
        existing = MockOrchestrator()
        import_api._orchestrator = existing
        result = import_api.get_orchestrator()
        assert result == existing
        mock_class.assert_not_called()


class TestInitImportSystem:
    """Tests for init_import_system."""

    @patch('import_api.get_orchestrator')
    @patch('import_api.SourceRegistry')
    @patch('import_api.discover_handlers')
    def test_init_import_system(self, mock_discover, mock_registry, mock_get_orch):
        """Test import system initialization."""
        mock_registry.list_source_ids.return_value = ["mit_ocw", "khan_academy"]
        mock_get_orch.return_value = MockOrchestrator()

        import_api.init_import_system()

        mock_discover.assert_called_once()
        mock_registry.list_source_ids.assert_called_once()
        mock_get_orch.assert_called_once()


class TestRecordImportedCourse:
    """Tests for _record_imported_course."""

    @pytest.mark.asyncio
    async def test_record_imported_course_success(self, mock_app):
        """Test successful recording of imported course."""
        import_api._app = mock_app

        progress = MagicMock()
        progress.config.source_id = "mit_ocw"
        progress.config.course_id = "6-001"
        progress.result.curriculum_id = "uuid-123"
        progress.id = "job-123"

        await import_api._record_imported_course(progress)

        # Verify the connection was used
        conn = mock_app["db_pool"]._connection
        # Since MockPool returns a new connection each time, we can't verify directly
        # but we can verify no exception was raised

    @pytest.mark.asyncio
    async def test_record_imported_course_no_app(self):
        """Test recording when app is not set."""
        import_api._app = None

        progress = MagicMock()
        progress.config.source_id = "mit_ocw"
        progress.config.course_id = "6-001"

        # Should not raise, just log a warning
        await import_api._record_imported_course(progress)

    @pytest.mark.asyncio
    async def test_record_imported_course_no_db_pool(self):
        """Test recording when db_pool is not in app."""
        app = web.Application()  # No db_pool
        import_api._app = app

        progress = MagicMock()
        progress.config.source_id = "mit_ocw"
        progress.config.course_id = "6-001"

        # Should not raise, just log a warning
        await import_api._record_imported_course(progress)

    @pytest.mark.asyncio
    async def test_record_imported_course_database_error(self, mock_app_with_error_db):
        """Test recording with database error."""
        import_api._app = mock_app_with_error_db

        progress = MagicMock()
        progress.config.source_id = "mit_ocw"
        progress.config.course_id = "6-001"
        progress.result.curriculum_id = "uuid-123"
        progress.id = "job-123"

        # Should not raise, just log an error
        await import_api._record_imported_course(progress)

    @pytest.mark.asyncio
    async def test_record_imported_course_null_result(self, mock_app):
        """Test recording when result is None."""
        import_api._app = mock_app

        progress = MagicMock()
        progress.config.source_id = "mit_ocw"
        progress.config.course_id = "6-001"
        progress.result = None
        progress.id = "job-123"

        await import_api._record_imported_course(progress)


class TestHandleImportProgress:
    """Tests for _handle_import_progress."""

    @pytest.mark.asyncio
    async def test_handle_import_progress_complete(self, mock_app):
        """Test handling completed import progress."""
        import_api._app = mock_app
        import_api._on_import_complete_callback = None

        # Create a progress object with COMPLETE status
        from importers.core.models import ImportStatus
        progress = MagicMock()
        progress.status = ImportStatus.COMPLETE
        progress.id = "job-123"
        progress.config.source_id = "mit_ocw"
        progress.config.course_id = "6-001"
        progress.result.curriculum_id = "uuid-123"

        import_api._handle_import_progress(progress)

        # Let the asyncio.create_task complete
        import asyncio
        await asyncio.sleep(0.01)

    @pytest.mark.asyncio
    async def test_handle_import_progress_complete_with_callback(self, mock_app):
        """Test handling completed import with callback."""
        import_api._app = mock_app
        callback = MagicMock()
        import_api._on_import_complete_callback = callback

        from importers.core.models import ImportStatus
        progress = MagicMock()
        progress.status = ImportStatus.COMPLETE
        progress.id = "job-123"
        progress.config.source_id = "mit_ocw"
        progress.config.course_id = "6-001"
        progress.result.curriculum_id = "uuid-123"

        import_api._handle_import_progress(progress)

        callback.assert_called_once_with(progress)

        # Let the asyncio.create_task complete
        import asyncio
        await asyncio.sleep(0.01)

    @pytest.mark.asyncio
    async def test_handle_import_progress_complete_callback_error(self, mock_app):
        """Test handling completed import when callback raises error."""
        import_api._app = mock_app
        callback = MagicMock(side_effect=Exception("Callback error"))
        import_api._on_import_complete_callback = callback

        from importers.core.models import ImportStatus
        progress = MagicMock()
        progress.status = ImportStatus.COMPLETE
        progress.id = "job-123"
        progress.config.source_id = "mit_ocw"
        progress.config.course_id = "6-001"
        progress.result.curriculum_id = "uuid-123"

        # Should not raise, error is caught and logged
        import_api._handle_import_progress(progress)

        # Let the asyncio.create_task complete
        import asyncio
        await asyncio.sleep(0.01)

    def test_handle_import_progress_not_complete(self, mock_app):
        """Test handling non-complete import progress."""
        import_api._app = mock_app
        callback = MagicMock()
        import_api._on_import_complete_callback = callback

        from importers.core.models import ImportStatus
        progress = MagicMock()
        progress.status = ImportStatus.DOWNLOADING  # Not complete
        progress.id = "job-123"

        import_api._handle_import_progress(progress)

        # Callback should not be called for non-complete status
        callback.assert_not_called()


# =============================================================================
# Route Registration Tests
# =============================================================================

class TestRegisterRoutes:
    """Tests for route registration."""

    @patch('import_api.init_import_system')
    def test_register_import_routes(self, mock_init):
        """Test that import routes are registered correctly."""
        app = web.Application()
        app["db_pool"] = MockPool()

        import_api.register_import_routes(app)

        route_paths = [r.resource.canonical for r in app.router.routes()]

        assert "/api/import/sources" in route_paths
        assert "/api/import/sources/{source_id}" in route_paths
        assert "/api/import/sources/{source_id}/courses" in route_paths
        assert "/api/import/sources/{source_id}/search" in route_paths
        assert "/api/import/sources/{source_id}/courses/{course_id}" in route_paths
        assert "/api/import/jobs" in route_paths
        assert "/api/import/jobs/{job_id}" in route_paths
        assert "/api/import/status" in route_paths
        mock_init.assert_called_once()

    @patch('import_api.init_import_system')
    def test_register_import_routes_sets_app_reference(self, mock_init):
        """Test that register sets the global app reference."""
        app = web.Application()
        app["db_pool"] = MockPool()

        import_api.register_import_routes(app)

        assert import_api._app == app
