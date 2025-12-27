# UnaMentis Importer Plugin Architecture

This document describes the industry-standard plugin architecture for the UnaMentis curriculum importer framework. The architecture is based on [Pluggy](https://pluggy.readthedocs.io/), the same plugin system used by pytest, tox, and devpi.

## Overview

The plugin architecture provides:

- **Standardized Contracts**: Hook specifications define clear interfaces for plugins
- **External Plugin Support**: Third-party plugins via setuptools entry points
- **Legacy Compatibility**: Existing handlers work through adapters
- **Configuration Management**: Per-plugin configuration with validation
- **Lifecycle Hooks**: Setup, teardown, and validation hooks

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Plugin Manager                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    Hook Caller                               │ │
│  │  get_source_info, get_course_catalog, download_course, etc. │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│  ┌───────────┬───────────────┼───────────────┬───────────────┐  │
│  │           │               │               │               │  │
│  ▼           ▼               ▼               ▼               ▼  │
│ ┌─────┐   ┌─────┐       ┌─────────┐    ┌─────────┐    ┌─────┐ │
│ │MIT  │   │Fast │       │External │    │Parser   │    │...  │ │
│ │OCW  │   │.ai  │       │Plugin   │    │Plugin   │    │     │ │
│ └─────┘   └─────┘       └─────────┘    └─────────┘    └─────┘ │
│     │         │              │               │                  │
│  Legacy    Native        Entry Point      Native               │
│  Adapter   Plugin        Discovery        Plugin               │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Using the Plugin System

```python
from importers.core import init_plugin_system

# Initialize and discover all plugins
manager = init_plugin_system()

# List available sources
for source in manager.list_sources():
    print(f"Source: {source.plugin_id}")
    print(f"  Type: {source.plugin_type}")
    print(f"  Version: {source.metadata.version}")

# Get a specific source
mit = manager.get_source("mit_ocw")
if mit:
    source_info = manager.hook.get_source_info()
    print(f"Source: {source_info.name}")

# Use async hooks
import asyncio

async def browse_catalog():
    result = await manager.call_async_hook_first(
        "get_course_catalog",
        page=1,
        page_size=20,
        filters=None,
        search="machine learning",
    )
    courses, total, filters = result
    print(f"Found {total} courses")
    for course in courses:
        print(f"  - {course.title}")

asyncio.run(browse_catalog())
```

### Creating a New Plugin

```python
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from importers.core import (
    BaseImporterPlugin,
    PluginMetadata,
    PluginRegistry,
    PluginType,
    hookimpl,
)
from importers.core.models import (
    CourseCatalogEntry,
    CourseDetail,
    CurriculumSource,
    LicenseInfo,
)
from importers.core.base import LicenseValidationResult


@PluginRegistry.register
class MySourcePlugin(BaseImporterPlugin):
    """A plugin for importing from My Source."""

    @property
    def plugin_id(self) -> str:
        return "my_source"

    @property
    def plugin_type(self) -> PluginType:
        return PluginType.SOURCE

    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="My Source",
            version="1.0.0",
            description="Import courses from My Source",
            plugin_type=PluginType.SOURCE,
            author="Your Name",
            url="https://mysource.example.com",
        )

    @hookimpl
    def get_source_info(self) -> CurriculumSource:
        return CurriculumSource(
            id="my_source",
            name="My Source",
            description="Educational content from My Source",
            base_url="https://mysource.example.com",
            logo_url="https://mysource.example.com/logo.png",
            supported_formats=["pdf", "html"],
        )

    @hookimpl
    def get_default_license(self) -> LicenseInfo:
        return LicenseInfo(
            type="CC-BY-4.0",
            name="Creative Commons Attribution 4.0",
            url="https://creativecommons.org/licenses/by/4.0/",
            permissions=["share", "adapt"],
            conditions=["attribution"],
            attribution_required=True,
            attribution_format="Content from My Source",
            holder_name="My Source Inc",
            holder_url="https://mysource.example.com",
            restrictions=[],
        )

    @hookimpl
    async def get_course_catalog(
        self,
        page: int,
        page_size: int,
        filters: Optional[Dict[str, Any]],
        search: Optional[str],
    ) -> Tuple[List[CourseCatalogEntry], int, Dict[str, List[str]]]:
        # Implement your catalog fetching logic
        courses = []
        total = 0
        filter_options = {"levels": ["beginner", "advanced"]}
        return courses, total, filter_options

    @hookimpl
    async def get_course_detail(self, course_id: str) -> Optional[CourseDetail]:
        # Implement your course detail fetching logic
        return None

    @hookimpl
    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]],
    ) -> Path:
        # Implement your download logic
        output_path = output_dir / f"{course_id}.zip"
        # ... download content ...
        return output_path

    @hookimpl
    def validate_license(self, course_id: str) -> LicenseValidationResult:
        return LicenseValidationResult(
            can_import=True,
            license=self.get_default_license(),
            warnings=[],
            attribution_text="Content from My Source",
        )
```

## Plugin Types

The framework supports five plugin types:

| Type | Description | Key Hooks |
|------|-------------|-----------|
| `SOURCE` | Curriculum sources (MIT OCW, etc.) | `get_course_catalog`, `download_course` |
| `PARSER` | Content parsers (PDF, HTML) | `parse_content`, `get_supported_formats` |
| `ENRICHER` | AI enrichment plugins | `enrich_content`, `get_enrichment_stages` |
| `EXPORTER` | Output format exporters | `export_content`, `get_export_formats` |
| `VALIDATOR` | Content validators | `validate_content` |

## Hook Specifications

### Lifecycle Hooks

All plugins can implement these lifecycle hooks:

```python
@hookimpl
def plugin_registered(self, plugin: ImporterPlugin, manager: PluginManager) -> None:
    """Called when the plugin is registered. Use for initialization."""
    pass

@hookimpl
def plugin_unregistered(self, plugin: ImporterPlugin) -> None:
    """Called when the plugin is unregistered. Use for cleanup."""
    pass

@hookimpl
def configure(self, config: PluginConfig) -> None:
    """Called to configure the plugin with runtime settings."""
    self._config = config

@hookimpl
def validate_config(self, config: PluginConfig) -> List[str]:
    """Validate configuration. Return list of error messages."""
    errors = []
    if "api_key" not in config.settings:
        errors.append("api_key is required")
    return errors
```

### Source Plugin Hooks

```python
@hookimpl
def get_source_info(self) -> CurriculumSource:
    """Return information about this source."""

@hookimpl
def get_default_license(self) -> LicenseInfo:
    """Return the default license for this source's content."""

@hookimpl
async def get_course_catalog(
    self,
    page: int,
    page_size: int,
    filters: Optional[Dict[str, Any]],
    search: Optional[str],
) -> Tuple[List[CourseCatalogEntry], int, Dict[str, List[str]]]:
    """Return paginated course catalog."""

@hookimpl
async def get_course_detail(self, course_id: str) -> Optional[CourseDetail]:
    """Return detailed information about a course."""

@hookimpl
async def download_course(
    self,
    course_id: str,
    output_dir: Path,
    progress_callback: Optional[Callable[[float, str], None]],
) -> Path:
    """Download course content. Return path to downloaded content."""

@hookimpl
def validate_license(self, course_id: str) -> LicenseValidationResult:
    """Validate that a course can be imported under its license."""
```

### Parser Plugin Hooks

```python
@hookimpl
def get_supported_formats(self) -> List[str]:
    """Return list of supported content formats."""
    return ["pdf", "html"]

@hookimpl
async def parse_content(
    self,
    content_path: Path,
    format_hint: Optional[str],
) -> Optional[Dict[str, Any]]:
    """Parse content from a file."""
```

### Enrichment Plugin Hooks

```python
@hookimpl
def get_enrichment_stages(self) -> List[str]:
    """Return list of enrichment stages provided."""
    return ["learning_objectives", "knowledge_graph"]

@hookimpl
async def enrich_content(
    self,
    content: Dict[str, Any],
    config: ImportConfig,
) -> Dict[str, Any]:
    """Enrich content with AI-generated additions."""
```

## Plugin Discovery

### Built-in Plugins

Built-in plugins are discovered automatically from the `sources/` directory:

```python
# In importers/sources/my_source.py
@PluginRegistry.register
class MySourcePlugin(BaseImporterPlugin):
    ...
```

### Entry Point Plugins

External plugins register via setuptools entry points in their `pyproject.toml`:

```toml
[project.entry-points."unamentis.importers.sources"]
my_source = "my_package.sources:MySourcePlugin"

[project.entry-points."unamentis.importers.parsers"]
pdf_parser = "my_package.parsers:PDFParserPlugin"
```

Entry point groups:
- `unamentis.importers.sources` - Source plugins
- `unamentis.importers.parsers` - Parser plugins
- `unamentis.importers.enrichers` - Enrichment plugins
- `unamentis.importers.exporters` - Exporter plugins
- `unamentis.importers.validators` - Validator plugins

## Legacy Handler Migration

Existing `CurriculumSourceHandler` implementations can be wrapped using the `LegacySourceAdapter`:

```python
from importers.core.adapter import LegacySourceAdapter
from importers.sources.mit_ocw import MITOCWHandler

# Wrap an existing handler
handler = MITOCWHandler()
plugin = LegacySourceAdapter(handler)

# Register with plugin manager
manager = get_plugin_manager()
manager.register(plugin)
```

Or use automatic discovery:

```python
from importers.core.adapter import discover_and_wrap_legacy_handlers

adapters = discover_and_wrap_legacy_handlers()
for adapter in adapters:
    manager.register(adapter)
```

## Configuration

Plugins can be configured at runtime:

```python
from importers.core import PluginConfig, get_plugin_manager

manager = get_plugin_manager()

# Configure a plugin
config = PluginConfig(
    enabled=True,
    priority=10,  # Lower = higher priority
    settings={
        "api_key": "your-api-key",
        "timeout": 30,
        "batch_size": 100,
    },
)

errors = manager.configure_plugin("my_source", config)
if errors:
    print(f"Configuration errors: {errors}")
```

Access configuration in your plugin:

```python
class MyPlugin(BaseImporterPlugin):
    @hookimpl
    def configure(self, config: PluginConfig) -> None:
        self._config = config

    def do_something(self):
        api_key = self.get_config_setting("api_key")
        timeout = self.get_config_setting("timeout", default=60)
```

## Testing Plugins

Use the provided test fixtures and utilities:

```python
import pytest
from importers.core import PluginManager, reset_plugin_manager

@pytest.fixture
def plugin_manager():
    """Create a fresh plugin manager for each test."""
    reset_plugin_manager()
    manager = PluginManager()
    yield manager
    reset_plugin_manager()

def test_my_plugin(plugin_manager):
    plugin = MySourcePlugin()
    plugin_manager.register(plugin)

    assert plugin_manager.get_source("my_source") is plugin

    # Test hooks
    source_info = plugin_manager.hook.get_source_info()
    assert source_info.id == "my_source"

@pytest.mark.asyncio
async def test_async_hooks(plugin_manager):
    plugin = MySourcePlugin()
    plugin_manager.register(plugin)

    result = await plugin_manager.call_async_hook_first(
        "get_course_catalog",
        page=1,
        page_size=10,
        filters=None,
        search=None,
    )
    assert result is not None
```

## Best Practices

### 1. Always Validate Licenses

```python
@hookimpl
def validate_license(self, course_id: str) -> LicenseValidationResult:
    # ALWAYS validate before allowing import
    license_info = self._get_course_license(course_id)
    if not license_info:
        return LicenseValidationResult(
            can_import=False,
            license=None,
            warnings=["No license information available"],
            attribution_text="",
        )
    return LicenseValidationResult(
        can_import=True,
        license=license_info,
        warnings=[],
        attribution_text=self._generate_attribution(course_id),
    )
```

### 2. Use Async for I/O Operations

```python
@hookimpl
async def download_course(self, course_id: str, output_dir: Path, progress_callback):
    async with aiohttp.ClientSession() as session:
        async with session.get(download_url) as response:
            # Stream the download
            with open(output_path, 'wb') as f:
                async for chunk in response.content.iter_chunked(8192):
                    f.write(chunk)
    return output_path
```

### 3. Report Progress

```python
@hookimpl
async def download_course(self, course_id: str, output_dir: Path, progress_callback):
    if progress_callback:
        progress_callback(0.0, "Starting download...")

    # ... download logic ...

    if progress_callback:
        progress_callback(50.0, "Downloaded, extracting...")

    # ... extraction logic ...

    if progress_callback:
        progress_callback(100.0, "Complete")

    return output_path
```

### 4. Handle Errors Gracefully

```python
@hookimpl
async def get_course_detail(self, course_id: str) -> Optional[CourseDetail]:
    try:
        return await self._fetch_course_detail(course_id)
    except aiohttp.ClientError as e:
        logger.error(f"Network error fetching {course_id}: {e}")
        return None
    except Exception as e:
        logger.exception(f"Unexpected error fetching {course_id}")
        raise
```

## Additional Documentation

- **[Plugin Development Specification](PLUGIN_SPEC.md)** - Complete spec for creating compliant plugins
- **[Example Source Plugin](examples/example_source_plugin.py)** - Full working example with comments

## References

- [Pluggy Documentation](https://pluggy.readthedocs.io/)
- [Python Packaging Guide - Plugins](https://packaging.python.org/en/latest/guides/creating-and-discovering-plugins/)
- [Setuptools Entry Points](https://setuptools.pypa.io/en/latest/userguide/entry_point.html)
- [Stevedore (OpenStack)](https://docs.openstack.org/stevedore/latest/)
