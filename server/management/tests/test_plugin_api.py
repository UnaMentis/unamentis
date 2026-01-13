"""
Tests for Plugin API routes.
"""
import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from aiohttp import web


class MockPluginInfo:
    """Mock plugin information."""

    def __init__(self, plugin_id: str, name: str = None):
        self.plugin_id = plugin_id
        self.name = name or f"Plugin {plugin_id}"
        self.description = f"Description for {plugin_id}"
        self.version = "1.0.0"
        self.source_type = "external"

    def to_dict(self):
        return {
            "plugin_id": self.plugin_id,
            "name": self.name,
            "description": self.description,
            "version": self.version,
            "source_type": self.source_type,
        }


class MockPluginState:
    """Mock plugin state."""

    def __init__(self, enabled: bool = False, priority: int = 100, settings: dict = None):
        self.enabled = enabled
        self.priority = priority
        self.settings = settings or {}


class MockPluginDiscovery:
    """Mock plugin discovery service."""

    def __init__(self):
        self._discovered = {
            "mit_ocw": MockPluginInfo("mit_ocw", "MIT OpenCourseWare"),
            "khan_academy": MockPluginInfo("khan_academy", "Khan Academy"),
            "ck12_flexbook": MockPluginInfo("ck12_flexbook", "CK-12 FlexBooks"),
        }
        self._states = {
            "mit_ocw": MockPluginState(enabled=True, priority=50),
            "khan_academy": MockPluginState(enabled=False, priority=100),
        }
        self._state_file_exists = True
        self._plugin_classes = {}

    def discover_all(self):
        pass

    def load_state(self):
        pass

    def has_state_file(self):
        return self._state_file_exists

    def get_enabled_plugins(self):
        return [pid for pid, state in self._states.items() if state.enabled]

    def enable_plugin(self, plugin_id: str):
        if plugin_id in self._discovered:
            if plugin_id not in self._states:
                self._states[plugin_id] = MockPluginState()
            self._states[plugin_id].enabled = True
            return True
        return False

    def disable_plugin(self, plugin_id: str):
        if plugin_id in self._states:
            self._states[plugin_id].enabled = False
            return True
        return False

    def save_state(self):
        pass

    def initialize_state(self, enabled_plugins):
        for pid in enabled_plugins:
            if pid in self._discovered:
                if pid not in self._states:
                    self._states[pid] = MockPluginState()
                self._states[pid].enabled = True
        self._state_file_exists = True
        return True

    def get_plugin_class(self, plugin_id: str):
        return self._plugin_classes.get(plugin_id)


class MockHandlerWithConfig:
    """Mock plugin handler with configuration support."""

    def get_configuration_schema(self):
        return {
            "settings": {
                "api_key": {"type": "string", "required": True},
                "timeout": {"type": "number", "default": 30},
            }
        }

    def configure(self, settings):
        pass

    async def test_api_key(self, api_key):
        if api_key == "valid_key":
            return {"valid": True, "message": "API key is valid"}
        return {"valid": False, "message": "Invalid API key"}


class MockHandlerNoConfig:
    """Mock plugin handler without configuration support."""
    pass


class MockSource:
    """Mock curriculum source."""

    def __init__(self, source_id: str, name: str):
        self.source_id = source_id
        self.name = name

    def to_dict(self):
        return {
            "source_id": self.source_id,
            "name": self.name,
        }


class MockCourse:
    """Mock course."""

    def __init__(self, course_id: str, title: str):
        self.course_id = course_id
        self.title = title

    def to_dict(self):
        return {
            "course_id": self.course_id,
            "title": self.title,
        }


class MockCourseDetail:
    """Mock course detail."""

    def __init__(self, course_id: str):
        self.course_id = course_id
        self.title = f"Course {course_id}"
        self.description = "A detailed description"

    def to_dict(self):
        return {
            "course_id": self.course_id,
            "title": self.title,
            "description": self.description,
        }


class MockSourceHandler:
    """Mock source handler."""

    async def get_course_catalog(self, page=1, page_size=20, filters=None, search=None):
        courses = [MockCourse("course-1", "Course 1"), MockCourse("course-2", "Course 2")]
        return courses, 2, {"subjects": ["Math", "Science"]}

    async def get_normalized_course_detail(self, course_id):
        if course_id == "not_found":
            raise ValueError("Course not found")
        return MockCourseDetail(course_id)

    async def download_course(self, course_id, output_dir, selected_lectures=None):
        return output_dir / f"{course_id}.umcf"


# Import the module under test
import plugin_api


@pytest.fixture
def mock_discovery():
    """Create a mock discovery instance."""
    return MockPluginDiscovery()


@pytest.fixture
def mock_app():
    """Create a mock aiohttp application."""
    return web.Application()


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
# Helper Function Tests
# =============================================================================

class TestGetDiscovery:
    """Tests for get_discovery helper."""

    @patch('plugin_api._discovery', None)
    @patch('plugin_api.get_plugin_discovery')
    def test_creates_discovery_on_first_call(self, mock_get_plugin_discovery):
        """Test that discovery is created on first call."""
        mock_disc = MockPluginDiscovery()
        mock_get_plugin_discovery.return_value = mock_disc

        result = plugin_api.get_discovery()

        mock_get_plugin_discovery.assert_called_once()
        assert result == mock_disc


class TestCheckPluginHasConfig:
    """Tests for check_plugin_has_config helper."""

    def test_plugin_with_config(self, mock_discovery):
        """Test detecting plugin with configuration."""
        mock_discovery._plugin_classes["mit_ocw"] = MockHandlerWithConfig
        result = plugin_api.check_plugin_has_config(mock_discovery, "mit_ocw")
        assert result is True

    def test_plugin_without_config(self, mock_discovery):
        """Test detecting plugin without configuration."""
        mock_discovery._plugin_classes["khan_academy"] = MockHandlerNoConfig
        result = plugin_api.check_plugin_has_config(mock_discovery, "khan_academy")
        assert result is False

    def test_plugin_class_not_found(self, mock_discovery):
        """Test when plugin class is not found."""
        result = plugin_api.check_plugin_has_config(mock_discovery, "unknown")
        assert result is False

    def test_plugin_config_error(self, mock_discovery):
        """Test error handling when checking config."""
        class ErrorHandler:
            def get_configuration_schema(self):
                raise Exception("Error getting schema")

        mock_discovery._plugin_classes["error_plugin"] = ErrorHandler
        result = plugin_api.check_plugin_has_config(mock_discovery, "error_plugin")
        assert result is False


# =============================================================================
# Get Plugins Tests
# =============================================================================

class TestHandleGetPlugins:
    """Tests for handle_get_plugins endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_plugins_success(self, mock_get_discovery, mock_request):
        """Test successful plugins retrieval."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_plugins(request)

        assert response.status == 200
        assert response.content_type == "application/json"

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_plugins_error(self, mock_get_discovery, mock_request):
        """Test error handling in plugins retrieval."""
        mock_get_discovery.side_effect = Exception("Discovery error")

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_plugins(request)

        assert response.status == 500


# =============================================================================
# Get Single Plugin Tests
# =============================================================================

class TestHandleGetPlugin:
    """Tests for handle_get_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_plugin_success(self, mock_get_discovery, mock_request):
        """Test successful single plugin retrieval."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(method="GET", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_get_plugin(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_plugin_not_found(self, mock_get_discovery, mock_request):
        """Test retrieval of non-existent plugin."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(method="GET", match_info={"plugin_id": "unknown"})
        response = await plugin_api.handle_get_plugin(request)

        assert response.status == 404


# =============================================================================
# Enable Plugin Tests
# =============================================================================

class TestHandleEnablePlugin:
    """Tests for handle_enable_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_enable_plugin_success(self, mock_get_discovery, mock_registry, mock_request):
        """Test successful plugin enable."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(method="POST", match_info={"plugin_id": "khan_academy"})
        response = await plugin_api.handle_enable_plugin(request)

        assert response.status == 200
        mock_registry.refresh.assert_called_once()

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_enable_plugin_not_found(self, mock_get_discovery, mock_request):
        """Test enabling non-existent plugin."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(method="POST", match_info={"plugin_id": "unknown"})
        response = await plugin_api.handle_enable_plugin(request)

        assert response.status == 404


# =============================================================================
# Disable Plugin Tests
# =============================================================================

class TestHandleDisablePlugin:
    """Tests for handle_disable_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_disable_plugin_success(self, mock_get_discovery, mock_registry, mock_request):
        """Test successful plugin disable."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(method="POST", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_disable_plugin(request)

        assert response.status == 200


# =============================================================================
# Configure Plugin Tests
# =============================================================================

class TestHandleConfigurePlugin:
    """Tests for handle_configure_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_configure_plugin_success(self, mock_get_discovery, mock_registry, mock_request):
        """Test successful plugin configuration."""
        discovery = MockPluginDiscovery()
        mock_get_discovery.return_value = discovery
        mock_registry.get_handler.return_value = MockHandlerWithConfig()

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={"settings": {"api_key": "test_key"}}
        )
        response = await plugin_api.handle_configure_plugin(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_configure_plugin_not_found(self, mock_get_discovery, mock_request):
        """Test configuring non-existent plugin."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "unknown"},
            json_data={"settings": {}}
        )
        response = await plugin_api.handle_configure_plugin(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_configure_plugin_creates_state(self, mock_get_discovery, mock_registry, mock_request):
        """Test configuration creates state if not exists."""
        discovery = MockPluginDiscovery()
        # Remove state for ck12_flexbook
        discovery._states.pop("ck12_flexbook", None)
        mock_get_discovery.return_value = discovery
        mock_registry.get_handler.return_value = None

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "ck12_flexbook"},
            json_data={"settings": {"key": "value"}}
        )
        response = await plugin_api.handle_configure_plugin(request)

        assert response.status == 200
        assert "ck12_flexbook" in discovery._states


# =============================================================================
# Get Plugin Config Schema Tests
# =============================================================================

class TestHandleGetPluginConfigSchema:
    """Tests for handle_get_plugin_config_schema endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_schema_success(self, mock_get_discovery, mock_request):
        """Test successful schema retrieval."""
        discovery = MockPluginDiscovery()
        discovery._plugin_classes["mit_ocw"] = MockHandlerWithConfig
        mock_get_discovery.return_value = discovery

        request = mock_request(method="GET", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_get_plugin_config_schema(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_schema_not_found(self, mock_get_discovery, mock_request):
        """Test schema for non-existent plugin."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(method="GET", match_info={"plugin_id": "unknown"})
        response = await plugin_api.handle_get_plugin_config_schema(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_schema_no_config(self, mock_get_discovery, mock_request):
        """Test schema for plugin without config."""
        discovery = MockPluginDiscovery()
        discovery._plugin_classes["mit_ocw"] = MockHandlerNoConfig
        mock_get_discovery.return_value = discovery

        request = mock_request(method="GET", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_get_plugin_config_schema(request)

        assert response.status == 200


# =============================================================================
# Test Plugin Tests
# =============================================================================

class TestHandleTestPlugin:
    """Tests for handle_test_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_test_plugin_valid_key(self, mock_get_discovery, mock_request):
        """Test plugin with valid API key."""
        discovery = MockPluginDiscovery()
        discovery._plugin_classes["mit_ocw"] = MockHandlerWithConfig
        mock_get_discovery.return_value = discovery

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={"settings": {"api_key": "valid_key"}}
        )
        response = await plugin_api.handle_test_plugin(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_test_plugin_not_found(self, mock_get_discovery, mock_request):
        """Test testing non-existent plugin."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "unknown"},
            json_data={}
        )
        response = await plugin_api.handle_test_plugin(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_test_plugin_no_test_method(self, mock_get_discovery, mock_request):
        """Test plugin without test_api_key method."""
        discovery = MockPluginDiscovery()
        discovery._plugin_classes["mit_ocw"] = MockHandlerNoConfig
        mock_get_discovery.return_value = discovery

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={}
        )
        response = await plugin_api.handle_test_plugin(request)

        assert response.status == 200


# =============================================================================
# Initialize Plugins Tests
# =============================================================================

class TestHandleInitializePlugins:
    """Tests for handle_initialize_plugins endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_initialize_success(self, mock_get_discovery, mock_registry, mock_request):
        """Test successful initialization."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(
            method="POST",
            json_data={"enabled_plugins": ["mit_ocw", "khan_academy"]}
        )
        response = await plugin_api.handle_initialize_plugins(request)

        assert response.status == 200
        mock_registry.refresh.assert_called_once()


# =============================================================================
# First Run Status Tests
# =============================================================================

class TestHandleGetFirstRunStatus:
    """Tests for handle_get_first_run_status endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_first_run_needed(self, mock_get_discovery, mock_request):
        """Test when first run is needed."""
        discovery = MockPluginDiscovery()
        discovery._state_file_exists = False
        mock_get_discovery.return_value = discovery

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_first_run_status(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_first_run_not_needed(self, mock_get_discovery, mock_request):
        """Test when first run is not needed."""
        mock_get_discovery.return_value = MockPluginDiscovery()

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_first_run_status(request)

        assert response.status == 200


# =============================================================================
# Source Browser API Tests
# =============================================================================

class TestHandleGetEnabledSources:
    """Tests for handle_get_enabled_sources endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_sources_success(self, mock_registry, mock_request):
        """Test successful sources retrieval."""
        mock_registry.get_all_sources.return_value = [
            MockSource("mit_ocw", "MIT OCW"),
            MockSource("khan", "Khan Academy"),
        ]

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_enabled_sources(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_sources_error(self, mock_registry, mock_request):
        """Test error handling in sources retrieval."""
        mock_registry.get_all_sources.side_effect = Exception("Registry error")

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_enabled_sources(request)

        assert response.status == 500


class TestHandleGetSourceCourses:
    """Tests for handle_get_source_courses endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_courses_success(self, mock_registry, mock_request):
        """Test successful course catalog retrieval."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={"page": "1", "page_size": "20"}
        )
        response = await plugin_api.handle_get_source_courses(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_courses_source_not_found(self, mock_registry, mock_request):
        """Test courses for non-existent source."""
        mock_registry.get_handler.return_value = None

        request = mock_request(method="GET", match_info={"source_id": "unknown"})
        response = await plugin_api.handle_get_source_courses(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_courses_with_filters(self, mock_registry, mock_request):
        """Test course catalog with filters."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={
                "page": "1",
                "page_size": "10",
                "search": "quantum",
                "subject": "Physics",
                "level": "undergraduate",
                "features": "video,transcript"
            }
        )
        response = await plugin_api.handle_get_source_courses(request)

        assert response.status == 200


class TestHandleGetCourseDetail:
    """Tests for handle_get_course_detail endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_course_detail_success(self, mock_registry, mock_request):
        """Test successful course detail retrieval."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw", "course_id": "6-001"}
        )
        response = await plugin_api.handle_get_course_detail(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_course_detail_source_not_found(self, mock_registry, mock_request):
        """Test course detail for non-existent source."""
        mock_registry.get_handler.return_value = None

        request = mock_request(
            method="GET",
            match_info={"source_id": "unknown", "course_id": "123"}
        )
        response = await plugin_api.handle_get_course_detail(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_course_detail_course_not_found(self, mock_registry, mock_request):
        """Test course detail for non-existent course."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw", "course_id": "not_found"}
        )
        response = await plugin_api.handle_get_course_detail(request)

        assert response.status == 404


class TestHandleImportCourse:
    """Tests for handle_import_course endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_import_course_success(self, mock_registry, mock_request):
        """Test successful course import."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="POST",
            match_info={"source_id": "mit_ocw", "course_id": "6-001"},
            json_data={"selectedContent": [], "outputName": "my-course"}
        )
        response = await plugin_api.handle_import_course(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_import_course_source_not_found(self, mock_registry, mock_request):
        """Test import for non-existent source."""
        mock_registry.get_handler.return_value = None

        request = mock_request(
            method="POST",
            match_info={"source_id": "unknown", "course_id": "123"},
            json_data={}
        )
        response = await plugin_api.handle_import_course(request)

        assert response.status == 404


# =============================================================================
# Route Registration Tests
# =============================================================================

class TestRegisterRoutes:
    """Tests for route registration."""

    @patch('plugin_api.init_plugin_system')
    def test_register_plugin_routes(self, mock_init):
        """Test that plugin routes are registered correctly."""
        app = web.Application()

        plugin_api.register_plugin_routes(app)

        route_paths = [r.resource.canonical for r in app.router.routes()]

        assert "/api/plugins" in route_paths
        assert "/api/plugins/first-run" in route_paths
        assert "/api/plugins/initialize" in route_paths
        assert "/api/plugins/{plugin_id}" in route_paths
        assert "/api/plugins/{plugin_id}/enable" in route_paths
        assert "/api/plugins/{plugin_id}/disable" in route_paths
        assert "/api/plugins/{plugin_id}/configure" in route_paths
        assert "/api/sources" in route_paths
        mock_init.assert_called_once()
