"""
Tests for the plugin architecture.

Tests cover:
- Plugin registration and discovery
- Hook specifications and implementations
- Legacy adapter compatibility
- Configuration management
- Entry point discovery
"""

import asyncio
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple
from unittest.mock import MagicMock, patch

import pytest

from ..core.base import CurriculumSourceHandler, LicenseValidationResult
from ..core.models import (
    CourseCatalogEntry,
    CourseDetail,
    CurriculumSource,
    LicenseInfo,
)
from ..core.plugin import (
    BaseImporterPlugin,
    ImporterHookSpec,
    ImporterPlugin,
    PluginConfig,
    PluginManager,
    PluginMetadata,
    PluginRegistry,
    PluginType,
    get_plugin_manager,
    hookimpl,
    reset_plugin_manager,
)
from ..core.adapter import LegacySourceAdapter


# =============================================================================
# Test Fixtures
# =============================================================================


@pytest.fixture
def plugin_manager():
    """Create a fresh plugin manager for each test."""
    reset_plugin_manager()
    manager = PluginManager()
    yield manager
    reset_plugin_manager()


@pytest.fixture
def mock_license():
    """Create a mock license for testing."""
    return LicenseInfo(
        type="CC-BY-4.0",
        name="Creative Commons Attribution 4.0",
        url="https://creativecommons.org/licenses/by/4.0/",
        permissions=["share", "adapt"],
        conditions=["attribution"],
        attribution_required=True,
        attribution_format="Content licensed under CC-BY-4.0",
        holder_name="Test Holder",
        holder_url="https://example.com",
        restrictions=[],
    )


@pytest.fixture
def mock_source_info():
    """Create a mock source info for testing."""
    return CurriculumSource(
        id="test_source",
        name="Test Source",
        description="A test curriculum source",
        base_url="https://example.com",
        logo_url="https://example.com/logo.png",
        features=["pdf", "html"],
    )


# =============================================================================
# Test Plugin Classes
# =============================================================================


class MockSourcePlugin(BaseImporterPlugin):
    """A mock source plugin for testing."""

    def __init__(self, source_id: str = "mock_source"):
        super().__init__()
        self._source_id = source_id
        self._source_info = CurriculumSource(
            id=source_id,
            name="Mock Source",
            description="A mock source for testing",
            base_url="https://mock.example.com",
            logo_url="https://mock.example.com/logo.png",
            features=["pdf"],
        )
        self._license = LicenseInfo(
            type="CC-BY-4.0",
            name="Creative Commons Attribution 4.0",
            url="https://creativecommons.org/licenses/by/4.0/",
            permissions=["share", "adapt"],
            conditions=["attribution"],
            attribution_required=True,
            attribution_format="Mock content",
            holder_name="Mock Holder",
            holder_url="https://mock.example.com",
            restrictions=[],
        )

    @property
    def plugin_id(self) -> str:
        return self._source_id

    @property
    def plugin_type(self) -> PluginType:
        return PluginType.SOURCE

    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="Mock Source Plugin",
            version="1.0.0",
            description="A mock source plugin for testing",
            plugin_type=PluginType.SOURCE,
            author="Test Author",
            url="https://mock.example.com",
            requires=[],
            provides=["source:mock_source"],
        )

    @hookimpl
    def get_source_info(self) -> CurriculumSource:
        return self._source_info

    @hookimpl
    def get_default_license(self) -> LicenseInfo:
        return self._license

    @hookimpl
    async def get_course_catalog(
        self,
        page: int,
        page_size: int,
        filters: Optional[Dict[str, Any]],
        search: Optional[str],
    ) -> Tuple[List[CourseCatalogEntry], int, Dict[str, List[str]]]:
        courses = [
            CourseCatalogEntry(
                id="mock-course-1",
                source_id=self._source_id,
                title="Mock Course 1",
                instructors=["Dr. Mock"],
                description="A mock course for testing",
                level="introductory",
                department="Computer Science",
                semester="Fall 2024",
                features=[],
                license=self._license,
                keywords=["mock", "test"],
            ),
            CourseCatalogEntry(
                id="mock-course-2",
                source_id=self._source_id,
                title="Mock Course 2",
                instructors=["Prof. Test"],
                description="Another mock course",
                level="advanced",
                department="Mathematics",
                semester="Spring 2024",
                features=[],
                license=self._license,
                keywords=["mock", "advanced"],
            ),
        ]
        return courses, len(courses), {"levels": ["introductory", "advanced"]}

    @hookimpl
    async def get_course_detail(self, course_id: str) -> Optional[CourseDetail]:
        if course_id == "mock-course-1":
            return CourseDetail(
                id="mock-course-1",
                source_id=self._source_id,
                title="Mock Course 1",
                instructors=["Dr. Mock"],
                description="A mock course for testing",
                level="introductory",
                department="Computer Science",
                semester="Fall 2024",
                features=[],
                license=self._license,
                keywords=["mock", "test"],
                syllabus="Week 1: Introduction\nWeek 2: Basics",
                prerequisites=["Basic Programming"],
                lectures=[],
                assignments=[],
                exams=[],
                estimated_import_time="5 minutes",
                estimated_output_size="10 MB",
                download_url="https://mock.example.com/download/course-1.zip",
            )
        return None

    @hookimpl
    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]],
    ) -> Path:
        # Simulate download
        output_path = output_dir / f"{course_id}.zip"
        output_path.write_text("mock content")
        if progress_callback:
            progress_callback(100.0, "Download complete")
        return output_path

    @hookimpl
    def validate_license(self, course_id: str) -> LicenseValidationResult:
        return LicenseValidationResult(
            can_import=True,
            license=self._license,
            warnings=[],
            attribution_text="Mock content from Mock Source",
        )


class MockLegacyHandler(CurriculumSourceHandler):
    """A mock legacy handler for testing the adapter."""

    @property
    def source_id(self) -> str:
        return "legacy_source"

    @property
    def source_info(self) -> CurriculumSource:
        return CurriculumSource(
            id="legacy_source",
            name="Legacy Source",
            description="A legacy source for testing",
            base_url="https://legacy.example.com",
            logo_url="https://legacy.example.com/logo.png",
            features=["html"],
        )

    @property
    def default_license(self) -> LicenseInfo:
        return LicenseInfo(
            type="CC-BY-NC-4.0",
            name="Creative Commons Attribution-NonCommercial 4.0",
            url="https://creativecommons.org/licenses/by-nc/4.0/",
            permissions=["share", "adapt"],
            conditions=["attribution", "noncommercial"],
            attribution_required=True,
            attribution_format="Legacy content",
            holder_name="Legacy Holder",
            holder_url="https://legacy.example.com",
            restrictions=["no-commercial"],
        )

    async def get_course_catalog(
        self,
        page: int = 1,
        page_size: int = 20,
        filters: Optional[Dict[str, Any]] = None,
        search: Optional[str] = None,
    ) -> Tuple[List[CourseCatalogEntry], int, Dict[str, List[str]]]:
        return [], 0, {}

    async def get_course_detail(self, course_id: str) -> CourseDetail:
        raise ValueError(f"Course not found: {course_id}")

    async def search_courses(
        self,
        query: str,
        limit: int = 20,
    ) -> List[CourseCatalogEntry]:
        return []

    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]] = None,
    ) -> Path:
        return output_dir / f"{course_id}.zip"

    async def get_download_size(self, course_id: str) -> str:
        return "0 MB"

    def validate_license(self, course_id: str) -> LicenseValidationResult:
        return LicenseValidationResult(
            can_import=True,
            license=self.default_license,
            warnings=[],
            attribution_text="Legacy content",
        )


# =============================================================================
# Plugin Manager Tests
# =============================================================================


class TestPluginManager:
    """Tests for PluginManager."""

    def test_create_manager(self, plugin_manager):
        """Test that a plugin manager can be created."""
        assert plugin_manager is not None
        assert len(plugin_manager.list_plugins()) == 0

    def test_register_plugin(self, plugin_manager):
        """Test registering a plugin."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        assert plugin_manager.get_plugin("mock_source") is plugin
        assert plugin_manager.get_source("mock_source") is plugin
        assert len(plugin_manager.list_sources()) == 1

    def test_register_duplicate_plugin(self, plugin_manager):
        """Test that registering a duplicate plugin is handled."""
        plugin1 = MockSourcePlugin("test_source")
        plugin2 = MockSourcePlugin("test_source")

        plugin_manager.register(plugin1)
        plugin_manager.register(plugin2)  # Should be skipped

        assert len(plugin_manager.list_plugins()) == 1
        assert plugin_manager.get_plugin("test_source") is plugin1

    def test_unregister_plugin(self, plugin_manager):
        """Test unregistering a plugin."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        assert plugin_manager.unregister("mock_source") is True
        assert plugin_manager.get_plugin("mock_source") is None
        assert len(plugin_manager.list_plugins()) == 0

    def test_unregister_nonexistent_plugin(self, plugin_manager):
        """Test unregistering a plugin that doesn't exist."""
        assert plugin_manager.unregister("nonexistent") is False

    def test_list_plugins_by_type(self, plugin_manager):
        """Test listing plugins filtered by type."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        sources = plugin_manager.list_plugins(PluginType.SOURCE)
        parsers = plugin_manager.list_plugins(PluginType.PARSER)

        assert len(sources) == 1
        assert len(parsers) == 0

    def test_get_plugin_metadata(self, plugin_manager):
        """Test getting plugin metadata."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        metadata = plugin_manager.get_plugin_metadata("mock_source")
        assert metadata is not None
        assert metadata.name == "Mock Source Plugin"
        assert metadata.version == "1.0.0"
        assert metadata.plugin_type == PluginType.SOURCE

    def test_get_all_metadata(self, plugin_manager):
        """Test getting all plugin metadata."""
        plugin1 = MockSourcePlugin("source1")
        plugin2 = MockSourcePlugin("source2")
        plugin_manager.register(plugin1)
        plugin_manager.register(plugin2)

        all_metadata = plugin_manager.get_all_metadata()
        assert len(all_metadata) == 2
        assert "source1" in all_metadata
        assert "source2" in all_metadata


# =============================================================================
# Hook Tests
# =============================================================================


class TestHooks:
    """Tests for hook specifications and implementations."""

    def test_get_source_info_hook(self, plugin_manager):
        """Test the get_source_info hook."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        result = plugin_manager.hook.get_source_info()
        assert result is not None
        # firstresult=True returns single result
        assert result.id == "mock_source"
        assert result.name == "Mock Source"

    def test_get_default_license_hook(self, plugin_manager):
        """Test the get_default_license hook."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        result = plugin_manager.hook.get_default_license()
        assert result is not None
        assert result.type == "CC-BY-4.0"

    @pytest.mark.asyncio
    async def test_get_course_catalog_hook(self, plugin_manager):
        """Test the async get_course_catalog hook."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        result = await plugin_manager.call_async_hook_first(
            "get_course_catalog",
            page=1,
            page_size=20,
            filters=None,
            search=None,
        )
        assert result is not None
        courses, total, filters = result
        assert len(courses) == 2
        assert total == 2
        assert "levels" in filters

    @pytest.mark.asyncio
    async def test_get_course_detail_hook(self, plugin_manager):
        """Test the async get_course_detail hook."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        result = await plugin_manager.call_async_hook_first(
            "get_course_detail",
            course_id="mock-course-1",
        )
        assert result is not None
        assert result.id == "mock-course-1"
        assert result.title == "Mock Course 1"

    def test_validate_license_hook(self, plugin_manager):
        """Test the validate_license hook."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        result = plugin_manager.hook.validate_license(course_id="mock-course-1")
        assert result is not None
        assert result.can_import is True


# =============================================================================
# Legacy Adapter Tests
# =============================================================================


class TestLegacyAdapter:
    """Tests for the legacy handler adapter."""

    def test_create_adapter(self):
        """Test creating an adapter from a legacy handler."""
        handler = MockLegacyHandler()
        adapter = LegacySourceAdapter(handler)

        assert adapter.plugin_id == "legacy_source"
        assert adapter.plugin_type == PluginType.SOURCE
        assert adapter.handler is handler

    def test_adapter_metadata(self):
        """Test adapter metadata extraction."""
        handler = MockLegacyHandler()
        adapter = LegacySourceAdapter(handler)

        metadata = adapter.metadata
        assert metadata.name == "Legacy Source"
        assert metadata.plugin_type == PluginType.SOURCE
        assert "source:legacy_source" in metadata.provides

    def test_adapter_from_class(self):
        """Test creating adapter from handler class."""
        adapter = LegacySourceAdapter.from_handler_class(MockLegacyHandler)
        assert adapter.plugin_id == "legacy_source"

    def test_adapter_hook_delegation(self, plugin_manager):
        """Test that adapter properly delegates to handler."""
        handler = MockLegacyHandler()
        adapter = LegacySourceAdapter(handler)
        plugin_manager.register(adapter)

        source_info = plugin_manager.hook.get_source_info()
        assert source_info.id == "legacy_source"

        license_info = plugin_manager.hook.get_default_license()
        assert license_info.type == "CC-BY-NC-4.0"

    @pytest.mark.asyncio
    async def test_adapter_async_hooks(self, plugin_manager):
        """Test adapter with async hooks."""
        handler = MockLegacyHandler()
        adapter = LegacySourceAdapter(handler)
        plugin_manager.register(adapter)

        result = await plugin_manager.call_async_hook_first(
            "get_course_catalog",
            page=1,
            page_size=20,
            filters=None,
            search=None,
        )
        assert result is not None
        courses, total, _ = result
        assert total == 0


# =============================================================================
# Plugin Configuration Tests
# =============================================================================


class TestPluginConfiguration:
    """Tests for plugin configuration."""

    def test_default_config(self):
        """Test default plugin configuration."""
        config = PluginConfig()
        assert config.enabled is True
        assert config.priority == 100
        assert config.settings == {}

    def test_config_from_dict(self):
        """Test creating config from dictionary."""
        data = {
            "enabled": False,
            "priority": 50,
            "settings": {"api_key": "test123"},
        }
        config = PluginConfig.from_dict(data)
        assert config.enabled is False
        assert config.priority == 50
        assert config.settings["api_key"] == "test123"

    def test_configure_plugin(self, plugin_manager):
        """Test configuring a plugin."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        config = PluginConfig(
            enabled=True,
            priority=10,
            settings={"timeout": 30},
        )
        errors = plugin_manager.configure_plugin("mock_source", config)

        assert len(errors) == 0
        assert plugin_manager.get_plugin_config("mock_source") == config
        assert plugin.config == config

    def test_get_config_setting(self):
        """Test getting configuration settings."""
        plugin = MockSourcePlugin()
        config = PluginConfig(settings={"key1": "value1"})
        plugin._config = config

        assert plugin.get_config_setting("key1") == "value1"
        assert plugin.get_config_setting("key2", "default") == "default"


# =============================================================================
# Plugin Registry Tests
# =============================================================================


class TestPluginRegistry:
    """Tests for the decorator-based plugin registry."""

    def test_register_decorator(self):
        """Test the @PluginRegistry.register decorator."""
        PluginRegistry.clear()

        @PluginRegistry.register
        class TestPlugin(BaseImporterPlugin):
            @property
            def plugin_id(self) -> str:
                return "test_decorator_plugin"

            @property
            def plugin_type(self) -> PluginType:
                return PluginType.SOURCE

            @property
            def metadata(self) -> PluginMetadata:
                return PluginMetadata(
                    name="Test Plugin",
                    version="1.0.0",
                    description="Test",
                    plugin_type=PluginType.SOURCE,
                )

        assert len(PluginRegistry._pending) == 1
        PluginRegistry.clear()

    def test_register_pending(self, plugin_manager):
        """Test registering pending plugins with manager."""
        PluginRegistry.clear()

        @PluginRegistry.register
        class TestPlugin(BaseImporterPlugin):
            @property
            def plugin_id(self) -> str:
                return "pending_test"

            @property
            def plugin_type(self) -> PluginType:
                return PluginType.SOURCE

            @property
            def metadata(self) -> PluginMetadata:
                return PluginMetadata(
                    name="Pending Test",
                    version="1.0.0",
                    description="Test",
                    plugin_type=PluginType.SOURCE,
                )

        count = PluginRegistry.register_pending(plugin_manager)
        assert count == 1
        assert plugin_manager.get_plugin("pending_test") is not None
        PluginRegistry.clear()


# =============================================================================
# Plugin Metadata Tests
# =============================================================================


class TestPluginMetadata:
    """Tests for plugin metadata."""

    def test_metadata_to_dict(self):
        """Test converting metadata to dictionary."""
        metadata = PluginMetadata(
            name="Test Plugin",
            version="1.0.0",
            description="A test plugin",
            plugin_type=PluginType.SOURCE,
            author="Test Author",
            url="https://example.com",
            requires=["dep1"],
            provides=["feat1"],
            entry_point="test.plugin:TestPlugin",
        )

        data = metadata.to_dict()
        assert data["name"] == "Test Plugin"
        assert data["version"] == "1.0.0"
        assert data["plugin_type"] == "source"
        assert data["author"] == "Test Author"
        assert data["requires"] == ["dep1"]
        assert data["provides"] == ["feat1"]


# =============================================================================
# Global Plugin Manager Tests
# =============================================================================


class TestGlobalPluginManager:
    """Tests for the global plugin manager singleton."""

    def test_get_plugin_manager(self):
        """Test getting the global plugin manager."""
        reset_plugin_manager()
        manager1 = get_plugin_manager()
        manager2 = get_plugin_manager()
        assert manager1 is manager2
        reset_plugin_manager()

    def test_reset_plugin_manager(self):
        """Test resetting the global plugin manager."""
        manager1 = get_plugin_manager()
        plugin = MockSourcePlugin()
        manager1.register(plugin)

        reset_plugin_manager()
        manager2 = get_plugin_manager()

        assert manager1 is not manager2
        assert len(manager2.list_plugins()) == 0
        reset_plugin_manager()


# =============================================================================
# Integration Tests
# =============================================================================


class TestPluginIntegration:
    """Integration tests for the plugin system."""

    def test_multiple_sources(self, plugin_manager):
        """Test registering and using multiple source plugins."""
        plugin1 = MockSourcePlugin("source_a")
        plugin2 = MockSourcePlugin("source_b")

        plugin_manager.register(plugin1)
        plugin_manager.register(plugin2)

        sources = plugin_manager.list_sources()
        assert len(sources) == 2

        source_ids = [s.plugin_id for s in sources]
        assert "source_a" in source_ids
        assert "source_b" in source_ids

    def test_mixed_legacy_and_native(self, plugin_manager):
        """Test using both legacy adapters and native plugins."""
        # Native plugin
        native = MockSourcePlugin("native_source")
        plugin_manager.register(native)

        # Legacy adapter
        handler = MockLegacyHandler()
        adapter = LegacySourceAdapter(handler)
        plugin_manager.register(adapter)

        sources = plugin_manager.list_sources()
        assert len(sources) == 2

        # Both should work via hooks
        native_info = plugin_manager.hook.get_source_info()
        assert native_info is not None

    @pytest.mark.asyncio
    async def test_full_import_workflow(self, plugin_manager, tmp_path):
        """Test a full import workflow through the plugin system."""
        plugin = MockSourcePlugin()
        plugin_manager.register(plugin)

        # 1. Get catalog
        catalog_result = await plugin_manager.call_async_hook_first(
            "get_course_catalog",
            page=1,
            page_size=10,
            filters=None,
            search=None,
        )
        courses, total, _ = catalog_result
        assert len(courses) > 0

        # 2. Get course detail
        course_id = courses[0].id
        detail = await plugin_manager.call_async_hook_first(
            "get_course_detail",
            course_id=course_id,
        )
        assert detail is not None
        assert detail.id == course_id

        # 3. Validate license
        license_result = plugin_manager.hook.validate_license(course_id=course_id)
        assert license_result.can_import is True

        # 4. Download course
        download_path = await plugin_manager.call_async_hook_first(
            "download_course",
            course_id=course_id,
            output_dir=tmp_path,
            progress_callback=None,
        )
        assert download_path is not None
        assert download_path.exists()
