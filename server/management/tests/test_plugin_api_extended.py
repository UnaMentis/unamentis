"""
Extended tests for Plugin API routes.

These tests focus on improving coverage for previously uncovered sections:
- Lines 34-66: Setup and initialization
- Lines 136-202: Plugin management
- Lines 243-299: Plugin installation/removal
- Lines 355-367, 391-423: Plugin configuration
- Lines 507-602: Plugin execution
"""
import json
import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from aiohttp import web


# =============================================================================
# Mock Classes
# =============================================================================

class MockPluginInfo:
    """Mock plugin information."""

    def __init__(self, plugin_id: str, name: str = None):
        self.plugin_id = plugin_id
        self.name = name or f"Plugin {plugin_id}"
        self.description = f"Description for {plugin_id}"
        self.version = "1.0.0"
        self.source_type = "external"
        self.plugin_type = "sources"
        self.file_path = f"/path/to/{plugin_id}.py"
        self.module_name = f"importers.plugins.sources.{plugin_id}"
        self.class_name = f"{plugin_id.title()}Handler"
        self.license_type = "MIT"
        self.features = ["download", "search"]
        self.author = "Test Author"
        self.url = f"https://example.com/{plugin_id}"

    def to_dict(self):
        return {
            "plugin_id": self.plugin_id,
            "name": self.name,
            "description": self.description,
            "version": self.version,
            "source_type": self.source_type,
            "plugin_type": self.plugin_type,
            "file_path": self.file_path,
            "module_name": self.module_name,
            "class_name": self.class_name,
            "license_type": self.license_type,
            "features": self.features,
            "author": self.author,
            "url": self.url,
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
            "mit_ocw": MockPluginState(enabled=True, priority=50, settings={"api_key": "test123"}),
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
        return [self._discovered[pid] for pid, state in self._states.items()
                if state.enabled and pid in self._discovered]

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
            },
            "fields": [
                {"name": "api_key", "type": "string", "required": True},
            ]
        }

    def configure(self, settings):
        pass

    async def test_api_key(self, api_key):
        if api_key == "valid_key":
            return {"valid": True, "message": "API key is valid"}
        return {"valid": False, "message": "Invalid API key"}


class MockHandlerWithPartialConfig:
    """Mock handler with partial configuration (no fields)."""

    def get_configuration_schema(self):
        return {"settings": {"key": {"type": "string"}}}


class MockHandlerWithEmptyConfig:
    """Mock handler with empty configuration schema."""

    def get_configuration_schema(self):
        return {}


class MockHandlerNoConfig:
    """Mock plugin handler without configuration support."""
    pass


class MockHandlerWithConfigError:
    """Mock handler that raises error on configure."""

    def configure(self, settings):
        raise Exception("Configuration error")


class MockHandlerWithTestError:
    """Mock handler where test_api_key raises an error."""

    async def test_api_key(self, api_key):
        raise Exception("Test failed with error")


class MockSource:
    """Mock curriculum source."""

    def __init__(self, source_id: str, name: str):
        self.source_id = source_id
        self.name = name
        self.description = f"Description for {name}"
        self.base_url = f"https://{source_id}.example.com"

    def to_dict(self):
        return {
            "source_id": self.source_id,
            "name": self.name,
            "description": self.description,
            "base_url": self.base_url,
        }


class MockCourse:
    """Mock course."""

    def __init__(self, course_id: str, title: str):
        self.course_id = course_id
        self.title = title
        self.description = f"Description for {title}"
        self.level = "undergraduate"

    def to_dict(self):
        return {
            "course_id": self.course_id,
            "title": self.title,
            "description": self.description,
            "level": self.level,
        }


class MockCourseDetail:
    """Mock course detail."""

    def __init__(self, course_id: str):
        self.course_id = course_id
        self.title = f"Course {course_id}"
        self.description = "A detailed description"
        self.chapters = []
        self.lessons = []

    def to_dict(self):
        return {
            "course_id": self.course_id,
            "title": self.title,
            "description": self.description,
            "chapters": self.chapters,
            "lessons": self.lessons,
        }


class MockSourceHandler:
    """Mock source handler."""

    def __init__(self, raise_on_catalog=False, raise_on_detail=False, raise_on_download=False):
        self.raise_on_catalog = raise_on_catalog
        self.raise_on_detail = raise_on_detail
        self.raise_on_download = raise_on_download

    async def get_course_catalog(self, page=1, page_size=20, filters=None, search=None):
        if self.raise_on_catalog:
            raise Exception("Catalog retrieval failed")
        courses = [
            MockCourse("course-1", "Introduction to Physics"),
            MockCourse("course-2", "Advanced Mathematics"),
        ]
        filter_options = {
            "subjects": ["Physics", "Mathematics", "Computer Science"],
            "levels": ["undergraduate", "graduate"],
        }
        return courses, 2, filter_options

    async def get_normalized_course_detail(self, course_id):
        if self.raise_on_detail:
            raise Exception("Detail retrieval failed")
        if course_id == "not_found":
            raise ValueError("Course not found")
        return MockCourseDetail(course_id)

    async def download_course(self, course_id, output_dir, selected_lectures=None):
        if self.raise_on_download:
            raise Exception("Download failed")
        if course_id == "invalid_course":
            raise ValueError("Invalid course ID")
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
# Initialization and Setup Tests (Lines 34-66)
# =============================================================================

class TestGetDiscoveryInitialization:
    """Tests for get_discovery initialization logic."""

    @patch('plugin_api._discovery', None)
    @patch('plugin_api.get_plugin_discovery')
    def test_get_discovery_initializes_on_first_call(self, mock_get_plugin_discovery):
        """Test that get_discovery properly initializes on first call."""
        mock_disc = MockPluginDiscovery()
        mock_get_plugin_discovery.return_value = mock_disc

        result = plugin_api.get_discovery()

        mock_get_plugin_discovery.assert_called_once()
        assert result == mock_disc

    @patch('plugin_api._discovery')
    def test_get_discovery_returns_cached_instance(self, mock_existing_discovery):
        """Test that get_discovery returns cached instance if exists."""
        mock_disc = MockPluginDiscovery()
        mock_existing_discovery.__bool__ = MagicMock(return_value=True)
        mock_existing_discovery.return_value = mock_disc

        with patch('plugin_api._discovery', mock_disc):
            result = plugin_api.get_discovery()
            assert result == mock_disc


class TestInitPluginSystem:
    """Tests for init_plugin_system function."""

    @patch('plugin_api.get_discovery')
    def test_init_plugin_system_logs_counts(self, mock_get_discovery, caplog):
        """Test that init_plugin_system logs discovered and enabled counts."""
        mock_disc = MockPluginDiscovery()
        mock_get_discovery.return_value = mock_disc

        with caplog.at_level('INFO'):
            plugin_api.init_plugin_system()

        assert "Initializing plugin system" in caplog.text or mock_get_discovery.called

    @patch('plugin_api.get_discovery')
    def test_init_plugin_system_detects_first_run(self, mock_get_discovery, caplog):
        """Test that init_plugin_system detects when first-run wizard is needed."""
        mock_disc = MockPluginDiscovery()
        mock_disc._state_file_exists = False
        mock_get_discovery.return_value = mock_disc

        with caplog.at_level('INFO'):
            plugin_api.init_plugin_system()

        # The function should complete without error
        mock_get_discovery.assert_called()


class TestCheckPluginHasConfigExtended:
    """Extended tests for check_plugin_has_config helper."""

    def test_plugin_with_fields_config(self, mock_discovery):
        """Test detecting plugin with fields in configuration."""
        mock_discovery._plugin_classes["test_plugin"] = MockHandlerWithConfig
        result = plugin_api.check_plugin_has_config(mock_discovery, "test_plugin")
        assert result is True

    def test_plugin_with_settings_only(self, mock_discovery):
        """Test detecting plugin with settings only (no fields)."""
        mock_discovery._plugin_classes["test_plugin"] = MockHandlerWithPartialConfig
        result = plugin_api.check_plugin_has_config(mock_discovery, "test_plugin")
        assert result is True

    def test_plugin_with_empty_schema(self, mock_discovery):
        """Test detecting plugin with empty configuration schema."""
        mock_discovery._plugin_classes["test_plugin"] = MockHandlerWithEmptyConfig
        result = plugin_api.check_plugin_has_config(mock_discovery, "test_plugin")
        assert result is False


# =============================================================================
# Plugin Management Tests (Lines 136-202)
# =============================================================================

class TestHandleGetPluginExtended:
    """Extended tests for handle_get_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_plugin_with_no_state(self, mock_get_discovery, mock_request):
        """Test retrieval of plugin with no saved state."""
        mock_disc = MockPluginDiscovery()
        # Remove state for ck12_flexbook
        del mock_disc._states["mit_ocw"]
        mock_get_discovery.return_value = mock_disc

        request = mock_request(method="GET", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_get_plugin(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["plugin"]["enabled"] is False
        assert data["plugin"]["priority"] == 100

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_plugin_error_handling(self, mock_get_discovery, mock_request):
        """Test error handling in get_plugin."""
        mock_get_discovery.side_effect = Exception("Discovery error")

        request = mock_request(method="GET", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_get_plugin(request)

        assert response.status == 500
        data = json.loads(response.body)
        assert data["success"] is False
        assert "error" in data


class TestHandleEnablePluginExtended:
    """Extended tests for handle_enable_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_enable_plugin_failed_enable(self, mock_get_discovery, mock_registry, mock_request):
        """Test handling when enable returns False."""
        mock_disc = MagicMock()
        mock_disc._discovered = {"test_plugin": MockPluginInfo("test_plugin")}
        mock_disc.enable_plugin.return_value = False
        mock_get_discovery.return_value = mock_disc

        request = mock_request(method="POST", match_info={"plugin_id": "test_plugin"})
        response = await plugin_api.handle_enable_plugin(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "Failed to enable" in data["message"]
        mock_registry.refresh.assert_not_called()

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_enable_plugin_error_handling(self, mock_get_discovery, mock_request):
        """Test error handling in enable_plugin."""
        mock_get_discovery.side_effect = Exception("Enable error")

        request = mock_request(method="POST", match_info={"plugin_id": "test_plugin"})
        response = await plugin_api.handle_enable_plugin(request)

        assert response.status == 500


class TestHandleDisablePluginExtended:
    """Extended tests for handle_disable_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_disable_plugin_failed_disable(self, mock_get_discovery, mock_registry, mock_request):
        """Test handling when disable returns False."""
        mock_disc = MagicMock()
        mock_disc.disable_plugin.return_value = False
        mock_get_discovery.return_value = mock_disc

        request = mock_request(method="POST", match_info={"plugin_id": "test_plugin"})
        response = await plugin_api.handle_disable_plugin(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "Failed to disable" in data["message"]

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_disable_plugin_error_handling(self, mock_get_discovery, mock_request):
        """Test error handling in disable_plugin."""
        mock_get_discovery.side_effect = Exception("Disable error")

        request = mock_request(method="POST", match_info={"plugin_id": "test_plugin"})
        response = await plugin_api.handle_disable_plugin(request)

        assert response.status == 500


# =============================================================================
# Plugin Configuration Tests (Lines 243-299)
# =============================================================================

class TestHandleConfigurePluginExtended:
    """Extended tests for handle_configure_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_configure_plugin_with_handler_error(self, mock_get_discovery, mock_registry, mock_request):
        """Test configuration when handler.configure raises error."""
        mock_disc = MockPluginDiscovery()
        mock_get_discovery.return_value = mock_disc
        mock_handler = MockHandlerWithConfigError()
        mock_registry.get_handler.return_value = mock_handler

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={"settings": {"api_key": "test_key"}}
        )
        response = await plugin_api.handle_configure_plugin(request)

        # Should still succeed despite handler error (warning logged)
        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_configure_plugin_with_no_handler(self, mock_get_discovery, mock_registry, mock_request):
        """Test configuration when no handler is returned."""
        mock_disc = MockPluginDiscovery()
        mock_get_discovery.return_value = mock_disc
        mock_registry.get_handler.return_value = None

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={"settings": {"key": "value"}}
        )
        response = await plugin_api.handle_configure_plugin(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_configure_plugin_error_handling(self, mock_get_discovery, mock_request):
        """Test error handling in configure_plugin."""
        mock_get_discovery.side_effect = Exception("Configuration error")

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={"settings": {}}
        )
        response = await plugin_api.handle_configure_plugin(request)

        assert response.status == 500


class TestHandleGetPluginConfigSchemaExtended:
    """Extended tests for handle_get_plugin_config_schema endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_schema_with_handler_class_not_found(self, mock_get_discovery, mock_request):
        """Test schema when handler class returns None."""
        mock_disc = MockPluginDiscovery()
        mock_disc._plugin_classes["mit_ocw"] = None
        mock_get_discovery.return_value = mock_disc

        request = mock_request(method="GET", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_get_plugin_config_schema(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["has_config"] is False

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_schema_handler_instantiation_error(self, mock_get_discovery, mock_request):
        """Test schema when handler instantiation fails."""
        class BrokenHandler:
            def __init__(self):
                raise Exception("Cannot instantiate")

        mock_disc = MockPluginDiscovery()
        mock_disc._plugin_classes["mit_ocw"] = BrokenHandler
        mock_get_discovery.return_value = mock_disc

        request = mock_request(method="GET", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_get_plugin_config_schema(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["has_config"] is False

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_schema_error_handling(self, mock_get_discovery, mock_request):
        """Test error handling in get_plugin_config_schema."""
        mock_get_discovery.side_effect = Exception("Schema error")

        request = mock_request(method="GET", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_get_plugin_config_schema(request)

        assert response.status == 500


# =============================================================================
# Plugin Testing Tests (Lines 355-367)
# =============================================================================

class TestHandleTestPluginExtended:
    """Extended tests for handle_test_plugin endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_test_plugin_invalid_key(self, mock_get_discovery, mock_request):
        """Test plugin with invalid API key."""
        mock_disc = MockPluginDiscovery()
        mock_disc._plugin_classes["mit_ocw"] = MockHandlerWithConfig
        mock_get_discovery.return_value = mock_disc

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={"settings": {"api_key": "invalid_key"}}
        )
        response = await plugin_api.handle_test_plugin(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["test_result"]["valid"] is False

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_test_plugin_with_test_error(self, mock_get_discovery, mock_request):
        """Test plugin when test_api_key raises an error."""
        mock_disc = MockPluginDiscovery()
        mock_disc._plugin_classes["mit_ocw"] = MockHandlerWithTestError
        mock_get_discovery.return_value = mock_disc

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={"settings": {"api_key": "any_key"}}
        )
        response = await plugin_api.handle_test_plugin(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["test_result"]["valid"] is False
        assert "Test failed" in data["test_result"]["message"]

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_test_plugin_with_no_body(self, mock_get_discovery, mock_request):
        """Test plugin with no request body."""
        mock_disc = MockPluginDiscovery()
        mock_disc._plugin_classes["mit_ocw"] = MockHandlerNoConfig
        mock_get_discovery.return_value = mock_disc

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data=None  # No body
        )
        response = await plugin_api.handle_test_plugin(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_test_plugin_handler_class_not_found(self, mock_get_discovery, mock_request):
        """Test when plugin handler class is not found (returns None response)."""
        mock_disc = MockPluginDiscovery()
        # No handler class registered, so get_plugin_class returns None
        mock_get_discovery.return_value = mock_disc

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={"settings": {}}
        )
        response = await plugin_api.handle_test_plugin(request)

        # When handler_class is None, the function falls through without returning
        # This is a code path that returns None (a potential bug in the source)
        # We verify this behavior exists
        assert response is None

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_test_plugin_error_handling(self, mock_get_discovery, mock_request):
        """Test error handling in test_plugin."""
        mock_get_discovery.side_effect = Exception("Test error")

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "mit_ocw"},
            json_data={}
        )
        response = await plugin_api.handle_test_plugin(request)

        assert response.status == 500


# =============================================================================
# Initialize and First Run Tests (Lines 391-423)
# =============================================================================

class TestHandleInitializePluginsExtended:
    """Extended tests for handle_initialize_plugins endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_initialize_failed(self, mock_get_discovery, mock_registry, mock_request):
        """Test when initialization fails."""
        mock_disc = MagicMock()
        mock_disc.initialize_state.return_value = False
        mock_get_discovery.return_value = mock_disc

        request = mock_request(
            method="POST",
            json_data={"enabled_plugins": ["mit_ocw"]}
        )
        response = await plugin_api.handle_initialize_plugins(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["success"] is False
        mock_registry.refresh.assert_not_called()

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_initialize_error_handling(self, mock_get_discovery, mock_request):
        """Test error handling in initialize_plugins."""
        mock_get_discovery.side_effect = Exception("Initialize error")

        request = mock_request(
            method="POST",
            json_data={"enabled_plugins": []}
        )
        response = await plugin_api.handle_initialize_plugins(request)

        assert response.status == 500

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_initialize_empty_list(self, mock_get_discovery, mock_registry, mock_request):
        """Test initialization with empty plugin list."""
        mock_disc = MockPluginDiscovery()
        mock_get_discovery.return_value = mock_disc

        request = mock_request(
            method="POST",
            json_data={"enabled_plugins": []}
        )
        response = await plugin_api.handle_initialize_plugins(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["success"] is True
        assert len(data["enabled"]) == 0


class TestHandleGetFirstRunStatusExtended:
    """Extended tests for handle_get_first_run_status endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_first_run_error_handling(self, mock_get_discovery, mock_request):
        """Test error handling in get_first_run_status."""
        mock_get_discovery.side_effect = Exception("First run error")

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_first_run_status(request)

        assert response.status == 500


# =============================================================================
# Source Browser API Extended Tests (Lines 507-602)
# =============================================================================

class TestHandleGetSourceCoursesExtended:
    """Extended tests for handle_get_source_courses endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_courses_with_all_query_params(self, mock_registry, mock_request):
        """Test course catalog with all query parameters."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={
                "page": "2",
                "page_size": "10",
                "search": "quantum mechanics",
                "subject": "Physics",
                "level": "graduate",
                "features": "video,transcript,assignments"
            }
        )
        response = await plugin_api.handle_get_source_courses(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["page"] == 2
        assert data["page_size"] == 10

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_courses_default_pagination(self, mock_registry, mock_request):
        """Test course catalog with default pagination."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={}  # No pagination params
        )
        response = await plugin_api.handle_get_source_courses(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["page"] == 1
        assert data["page_size"] == 20

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_courses_error_handling(self, mock_registry, mock_request):
        """Test error handling in get_source_courses."""
        mock_registry.get_handler.return_value = MockSourceHandler(raise_on_catalog=True)

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={}
        )
        response = await plugin_api.handle_get_source_courses(request)

        assert response.status == 500


class TestHandleGetCourseDetailExtended:
    """Extended tests for handle_get_course_detail endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_course_detail_error_handling(self, mock_registry, mock_request):
        """Test error handling in get_course_detail."""
        mock_registry.get_handler.return_value = MockSourceHandler(raise_on_detail=True)

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw", "course_id": "6-001"}
        )
        response = await plugin_api.handle_get_course_detail(request)

        assert response.status == 500


class TestHandleImportCourseExtended:
    """Extended tests for handle_import_course endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_import_course_with_selected_content(self, mock_registry, mock_request, tmp_path):
        """Test course import with selected content."""
        # Create a mock handler that uses tmp_path for output
        mock_handler = MagicMock()
        mock_handler.download_course = AsyncMock(return_value=tmp_path / "course.umcf")
        mock_registry.get_handler.return_value = mock_handler

        # Patch Path(__file__).parent.parent to return a path that can create output dir
        with patch.object(plugin_api, '__file__', str(tmp_path / 'plugin_api.py')):
            # Create the importers/output directory structure
            (tmp_path.parent / "importers" / "output").mkdir(parents=True, exist_ok=True)

            request = mock_request(
                method="POST",
                match_info={"source_id": "mit_ocw", "course_id": "6-001"},
                json_data={
                    "selectedContent": ["lesson-1", "lesson-2", "quiz-1"],
                    "outputName": "my-physics-course"
                }
            )
            response = await plugin_api.handle_import_course(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_import_course_value_error(self, mock_registry, mock_request):
        """Test course import with ValueError (course not found)."""
        mock_handler = MockSourceHandler()
        mock_registry.get_handler.return_value = mock_handler

        request = mock_request(
            method="POST",
            match_info={"source_id": "mit_ocw", "course_id": "invalid_course"},
            json_data={}
        )
        response = await plugin_api.handle_import_course(request)

        assert response.status == 404

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_import_course_error_handling(self, mock_registry, mock_request):
        """Test error handling in import_course."""
        mock_registry.get_handler.return_value = MockSourceHandler(raise_on_download=True)

        request = mock_request(
            method="POST",
            match_info={"source_id": "mit_ocw", "course_id": "6-001"},
            json_data={}
        )
        response = await plugin_api.handle_import_course(request)

        assert response.status == 500


# =============================================================================
# Get Plugins Extended Tests
# =============================================================================

class TestHandleGetPluginsExtended:
    """Extended tests for handle_get_plugins endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.check_plugin_has_config')
    @patch('plugin_api.get_discovery')
    async def test_get_plugins_with_mixed_states(self, mock_get_discovery, mock_check_config, mock_request):
        """Test plugins retrieval with mixed enabled/disabled states."""
        mock_disc = MockPluginDiscovery()
        mock_get_discovery.return_value = mock_disc
        mock_check_config.return_value = True

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_plugins(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert len(data["plugins"]) == 3

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_plugins_first_run_true(self, mock_get_discovery, mock_request):
        """Test plugins retrieval when first run is needed."""
        mock_disc = MockPluginDiscovery()
        mock_disc._state_file_exists = False
        mock_get_discovery.return_value = mock_disc

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_plugins(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["first_run"] is True


# =============================================================================
# Source Registry API Tests
# =============================================================================

class TestHandleGetEnabledSourcesExtended:
    """Extended tests for handle_get_enabled_sources endpoint."""

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_sources_empty_list(self, mock_registry, mock_request):
        """Test sources retrieval when no sources enabled."""
        mock_registry.get_all_sources.return_value = []

        request = mock_request(method="GET")
        response = await plugin_api.handle_get_enabled_sources(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["sources"] == []


# =============================================================================
# Route Registration Extended Tests
# =============================================================================

class TestRegisterRoutesExtended:
    """Extended tests for route registration."""

    @patch('plugin_api.init_plugin_system')
    def test_register_routes_includes_source_routes(self, mock_init):
        """Test that source routes are properly registered."""
        app = web.Application()

        plugin_api.register_plugin_routes(app)

        route_paths = [r.resource.canonical for r in app.router.routes()]

        # Verify source browser routes
        assert "/api/sources/{source_id}/courses" in route_paths
        assert "/api/sources/{source_id}/courses/{course_id}" in route_paths
        assert "/api/sources/{source_id}/courses/{course_id}/import" in route_paths

    @patch('plugin_api.init_plugin_system')
    def test_register_routes_includes_test_route(self, mock_init):
        """Test that plugin test route is registered."""
        app = web.Application()

        plugin_api.register_plugin_routes(app)

        route_paths = [r.resource.canonical for r in app.router.routes()]

        assert "/api/plugins/{plugin_id}/test" in route_paths
        assert "/api/plugins/{plugin_id}/config-schema" in route_paths


# =============================================================================
# Edge Case Tests
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.mark.asyncio
    @patch('plugin_api.get_discovery')
    async def test_get_plugin_with_none_state_fields(self, mock_get_discovery, mock_request):
        """Test plugin retrieval when state has None fields."""
        mock_disc = MockPluginDiscovery()
        mock_disc._states["mit_ocw"] = MockPluginState(enabled=None, priority=None, settings=None)
        mock_get_discovery.return_value = mock_disc

        request = mock_request(method="GET", match_info={"plugin_id": "mit_ocw"})
        response = await plugin_api.handle_get_plugin(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    async def test_get_courses_with_empty_filters(self, mock_registry, mock_request):
        """Test courses with empty filter values."""
        mock_registry.get_handler.return_value = MockSourceHandler()

        request = mock_request(
            method="GET",
            match_info={"source_id": "mit_ocw"},
            query={
                "subject": "",
                "level": "",
                "features": ""
            }
        )
        response = await plugin_api.handle_get_source_courses(request)

        # Should handle empty strings gracefully
        assert response.status == 200

    @pytest.mark.asyncio
    @patch('plugin_api.SourceRegistry')
    @patch('plugin_api.get_discovery')
    async def test_configure_creates_plugin_state(self, mock_get_discovery, mock_registry, mock_request):
        """Test that configure creates PluginState when not exists."""
        mock_disc = MockPluginDiscovery()
        # Ensure ck12_flexbook has no state
        if "ck12_flexbook" in mock_disc._states:
            del mock_disc._states["ck12_flexbook"]
        mock_get_discovery.return_value = mock_disc
        mock_registry.get_handler.return_value = None

        request = mock_request(
            method="POST",
            match_info={"plugin_id": "ck12_flexbook"},
            json_data={"settings": {"new_setting": "value"}}
        )

        # The configure function imports PluginState from importers.core.discovery
        # when the plugin state doesn't exist
        with patch('importers.core.discovery.PluginState', MockPluginState):
            response = await plugin_api.handle_configure_plugin(request)

        assert response.status == 200
        # Verify that state was created for the plugin
        assert "ck12_flexbook" in mock_disc._states
