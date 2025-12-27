# UnaMentis Importer Plugin Development Specification

**Version:** 1.0.0
**Status:** Stable
**Last Updated:** 2025-01-15

This specification defines the requirements and best practices for creating compliant plugins for the UnaMentis curriculum importer framework.

## Table of Contents

1. [Overview](#overview)
2. [Plugin Requirements](#plugin-requirements)
3. [Plugin Types](#plugin-types)
4. [Source Plugin Specification](#source-plugin-specification)
5. [Parser Plugin Specification](#parser-plugin-specification)
6. [Enricher Plugin Specification](#enricher-plugin-specification)
7. [Exporter Plugin Specification](#exporter-plugin-specification)
8. [Validator Plugin Specification](#validator-plugin-specification)
9. [Configuration Specification](#configuration-specification)
10. [Testing Requirements](#testing-requirements)
11. [Distribution](#distribution)
12. [Compliance Checklist](#compliance-checklist)

---

## Overview

The UnaMentis importer plugin system is built on [Pluggy](https://pluggy.readthedocs.io/), providing a standardized way to extend the curriculum import pipeline. Plugins can:

- Add new curriculum sources (MIT OCW, Coursera, etc.)
- Parse new content formats (EPUB, DOCX, etc.)
- Provide AI enrichment capabilities
- Export to different formats (SCORM, xAPI, etc.)
- Validate content against custom schemas

### Architecture Principles

1. **Loose Coupling**: Plugins communicate only through defined hooks
2. **Fail-Safe**: Plugin failures don't crash the system
3. **Async-First**: I/O operations use async/await
4. **License-First**: All content must have validated licenses
5. **Observable**: Plugins report progress and can be monitored

---

## Plugin Requirements

### Mandatory Requirements

All plugins MUST:

| Requirement | Description |
|-------------|-------------|
| **Inherit from BaseImporterPlugin** | Use the provided base class |
| **Implement plugin_id property** | Unique identifier (lowercase, underscores) |
| **Implement plugin_type property** | One of the PluginType enum values |
| **Implement metadata property** | Return PluginMetadata with version info |
| **Use @hookimpl decorator** | Mark all hook implementations |
| **Handle errors gracefully** | Never raise unhandled exceptions |
| **Support configuration** | Accept PluginConfig via configure hook |

### Naming Conventions

```
Plugin ID:     lowercase_with_underscores (e.g., "mit_ocw", "pdf_parser")
Class Name:    PascalCase + Plugin suffix (e.g., "MITOCWPlugin", "PDFParserPlugin")
Module Name:   lowercase_with_underscores (e.g., "mit_ocw.py", "pdf_parser.py")
```

### Version Requirements

- Use [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH)
- Increment MAJOR for breaking changes
- Increment MINOR for new features
- Increment PATCH for bug fixes

---

## Plugin Types

```python
from importers.core import PluginType

class PluginType(Enum):
    SOURCE = "source"       # Curriculum sources
    PARSER = "parser"       # Content parsers
    ENRICHER = "enricher"   # AI enrichment
    EXPORTER = "exporter"   # Output formats
    VALIDATOR = "validator" # Content validation
```

---

## Source Plugin Specification

Source plugins import curriculum from external platforms.

### Required Hooks

```python
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from importers.core import (
    BaseImporterPlugin,
    PluginMetadata,
    PluginType,
    hookimpl,
)
from importers.core.base import LicenseValidationResult
from importers.core.models import (
    CourseCatalogEntry,
    CourseDetail,
    CurriculumSource,
    LicenseInfo,
)


class MySourcePlugin(BaseImporterPlugin):
    """A compliant source plugin."""

    @property
    def plugin_id(self) -> str:
        """REQUIRED: Unique identifier."""
        return "my_source"

    @property
    def plugin_type(self) -> PluginType:
        """REQUIRED: Must be PluginType.SOURCE."""
        return PluginType.SOURCE

    @property
    def metadata(self) -> PluginMetadata:
        """REQUIRED: Plugin metadata."""
        return PluginMetadata(
            name="My Source",
            version="1.0.0",
            description="Import courses from My Source",
            plugin_type=PluginType.SOURCE,
            author="Your Name <email@example.com>",
            url="https://github.com/you/my-source-plugin",
            requires=[],  # Other plugins this depends on
            provides=["source:my_source"],
        )

    @hookimpl
    def get_source_info(self) -> CurriculumSource:
        """REQUIRED: Return source information."""
        return CurriculumSource(
            id=self.plugin_id,
            name="My Source",
            description="Educational content from My Source",
            base_url="https://mysource.example.com",
            logo_url="https://mysource.example.com/logo.png",
            supported_formats=["pdf", "html", "video"],
        )

    @hookimpl
    def get_default_license(self) -> LicenseInfo:
        """REQUIRED: Return the default license."""
        return LicenseInfo(
            type="CC-BY-4.0",
            name="Creative Commons Attribution 4.0 International",
            url="https://creativecommons.org/licenses/by/4.0/",
            permissions=["share", "adapt", "commercial"],
            conditions=["attribution"],
            attribution_required=True,
            attribution_format="Content from {course_title} by {instructor}, My Source",
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
        """
        REQUIRED: Return paginated course catalog.

        Args:
            page: Page number (1-indexed)
            page_size: Number of items per page
            filters: Optional filter criteria
            search: Optional search query

        Returns:
            Tuple of:
            - List of CourseCatalogEntry objects
            - Total count of matching courses
            - Available filter options
        """
        # Implementation here
        courses = []
        total = 0
        filter_options = {
            "levels": ["beginner", "intermediate", "advanced"],
            "subjects": ["Computer Science", "Mathematics"],
        }
        return courses, total, filter_options

    @hookimpl
    async def get_course_detail(self, course_id: str) -> Optional[CourseDetail]:
        """
        REQUIRED: Return detailed course information.

        Args:
            course_id: Unique course identifier

        Returns:
            CourseDetail or None if not found
        """
        # Implementation here
        return None

    @hookimpl
    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]],
    ) -> Path:
        """
        REQUIRED: Download course content.

        Args:
            course_id: Course to download
            output_dir: Directory to save content
            progress_callback: Function to report progress (0-100, message)

        Returns:
            Path to downloaded content (file or directory)

        Raises:
            LicenseRestrictionError: If course cannot be downloaded
            ValueError: If course not found
        """
        if progress_callback:
            progress_callback(0.0, "Starting download...")

        # Implementation here
        output_path = output_dir / f"{course_id}"

        if progress_callback:
            progress_callback(100.0, "Download complete")

        return output_path

    @hookimpl
    def validate_license(self, course_id: str) -> LicenseValidationResult:
        """
        REQUIRED: Validate that a course can be imported.

        This is CRITICAL for legal compliance. Always validate before import.

        Args:
            course_id: Course to validate

        Returns:
            LicenseValidationResult with import permission
        """
        return LicenseValidationResult(
            can_import=True,
            license=self.get_default_license(),
            warnings=[],
            attribution_text=f"Content from My Source, course {course_id}",
        )
```

### Source Plugin Data Models

#### CurriculumSource

```python
@dataclass
class CurriculumSource:
    id: str                      # Unique source ID
    name: str                    # Display name
    description: str             # Source description
    base_url: str                # Source website URL
    logo_url: Optional[str]      # Logo image URL
    supported_formats: List[str] # Content formats available
```

#### CourseCatalogEntry

```python
@dataclass
class CourseCatalogEntry:
    id: str                      # Unique course ID
    source_id: str               # Source plugin ID
    title: str                   # Course title
    instructors: List[str]       # Instructor names
    description: str             # Course description
    level: str                   # "introductory", "intermediate", "advanced"
    department: Optional[str]    # Department/subject area
    semester: Optional[str]      # Term offered
    features: List[CourseFeature]# Available content types
    license: Optional[LicenseInfo]
    keywords: List[str]          # Search keywords
```

#### CourseDetail (extends CourseCatalogEntry)

```python
@dataclass
class CourseDetail(CourseCatalogEntry):
    syllabus: Optional[str]           # Course syllabus text
    prerequisites: List[str]          # Required prerequisites
    lectures: List[LectureInfo]       # Lecture list
    assignments: List[AssignmentInfo] # Assignment list
    exams: List[ExamInfo]             # Exam list
    estimated_import_time: str        # e.g., "10 minutes"
    estimated_output_size: str        # e.g., "50 MB"
    download_url: Optional[str]       # Direct download URL
```

#### LicenseInfo

```python
@dataclass
class LicenseInfo:
    type: str                    # SPDX identifier (e.g., "CC-BY-4.0")
    name: str                    # Full license name
    url: str                     # License URL
    permissions: List[str]       # ["share", "adapt", "commercial"]
    conditions: List[str]        # ["attribution", "sharealike"]
    attribution_required: bool   # Must attribute?
    attribution_format: str      # Attribution template
    holder_name: str             # Copyright holder
    holder_url: str              # Holder website
    restrictions: List[str]      # Special restrictions
```

---

## Parser Plugin Specification

Parser plugins extract content from files.

### Required Hooks

```python
class MyParserPlugin(BaseImporterPlugin):

    @property
    def plugin_id(self) -> str:
        return "my_parser"

    @property
    def plugin_type(self) -> PluginType:
        return PluginType.PARSER

    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="My Parser",
            version="1.0.0",
            description="Parse My Format files",
            plugin_type=PluginType.PARSER,
        )

    @hookimpl
    def get_supported_formats(self) -> List[str]:
        """
        REQUIRED: Return supported format identifiers.

        Format IDs should be:
        - File extensions: "pdf", "html", "docx"
        - MIME types: "application/pdf"
        - Custom: "myformat/v2"
        """
        return ["myformat", "application/x-myformat"]

    @hookimpl
    async def parse_content(
        self,
        content_path: Path,
        format_hint: Optional[str],
    ) -> Optional[Dict[str, Any]]:
        """
        REQUIRED: Parse content from a file.

        Args:
            content_path: Path to the file
            format_hint: Optional hint about format

        Returns:
            Parsed content as dictionary, or None if cannot parse

        The returned dictionary should include:
        - "text": Extracted text content
        - "metadata": Document metadata
        - "structure": Document structure info
        """
        if not self._can_parse(content_path, format_hint):
            return None

        return {
            "text": "Extracted text...",
            "metadata": {
                "title": "Document Title",
                "author": "Author Name",
                "created": "2024-01-15",
            },
            "structure": {
                "sections": [...],
                "headings": [...],
            },
        }
```

---

## Enricher Plugin Specification

Enricher plugins add AI-generated content.

### Required Hooks

```python
class MyEnricherPlugin(BaseImporterPlugin):

    @property
    def plugin_id(self) -> str:
        return "my_enricher"

    @property
    def plugin_type(self) -> PluginType:
        return PluginType.ENRICHER

    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="My Enricher",
            version="1.0.0",
            description="AI enrichment for curriculum",
            plugin_type=PluginType.ENRICHER,
        )

    @hookimpl
    def get_enrichment_stages(self) -> List[str]:
        """
        REQUIRED: Return enrichment stages this plugin provides.

        Standard stages:
        - "learning_objectives": Generate learning objectives
        - "knowledge_graph": Build concept graph
        - "spoken_text": Generate tutoring dialogue
        - "assessments": Generate practice questions
        - "misconceptions": Identify common misconceptions
        """
        return ["learning_objectives", "assessments"]

    @hookimpl
    async def enrich_content(
        self,
        content: Dict[str, Any],
        config: ImportConfig,
    ) -> Dict[str, Any]:
        """
        REQUIRED: Enrich content with AI-generated additions.

        Args:
            content: Content to enrich (UMLCF structure)
            config: Import configuration with enrichment options

        Returns:
            Enriched content (modified in place is acceptable)
        """
        if config.generate_objectives:
            content["learning_objectives"] = await self._generate_objectives(content)

        if config.generate_practice_problems:
            content["assessments"] = await self._generate_assessments(content)

        return content
```

---

## Exporter Plugin Specification

Exporter plugins output content in different formats.

### Required Hooks

```python
class MyExporterPlugin(BaseImporterPlugin):

    @property
    def plugin_id(self) -> str:
        return "my_exporter"

    @property
    def plugin_type(self) -> PluginType:
        return PluginType.EXPORTER

    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="My Exporter",
            version="1.0.0",
            description="Export to My Format",
            plugin_type=PluginType.EXPORTER,
        )

    @hookimpl
    def get_export_formats(self) -> List[str]:
        """
        REQUIRED: Return supported export format IDs.

        Standard formats:
        - "umlcf": UnaMentis Curriculum Format (JSON)
        - "scorm": SCORM 2004 package
        - "xapi": xAPI statements
        - "markdown": Markdown files
        """
        return ["myformat"]

    @hookimpl
    async def export_content(
        self,
        content: Dict[str, Any],
        output_path: Path,
        format_id: str,
    ) -> Optional[Path]:
        """
        REQUIRED: Export content to specified format.

        Args:
            content: UMLCF content to export
            output_path: Directory for output
            format_id: Format to export to

        Returns:
            Path to exported file(s), or None if cannot export
        """
        if format_id not in self.get_export_formats():
            return None

        export_file = output_path / "content.myformat"
        # Export logic here
        return export_file
```

---

## Validator Plugin Specification

Validator plugins check content for issues.

### Required Hooks

```python
from importers.core.base import ValidationResult

class MyValidatorPlugin(BaseImporterPlugin):

    @property
    def plugin_id(self) -> str:
        return "my_validator"

    @property
    def plugin_type(self) -> PluginType:
        return PluginType.VALIDATOR

    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="My Validator",
            version="1.0.0",
            description="Validate content quality",
            plugin_type=PluginType.VALIDATOR,
        )

    @hookimpl
    async def validate_content(
        self,
        content: Dict[str, Any],
        content_type: str,
    ) -> ValidationResult:
        """
        REQUIRED: Validate content.

        Args:
            content: Content to validate
            content_type: Type of content ("course", "lecture", etc.)

        Returns:
            ValidationResult with errors and warnings
        """
        errors = []
        warnings = []
        metadata = {}

        # Validation logic
        if not content.get("title"):
            errors.append("Missing required field: title")

        if len(content.get("description", "")) < 50:
            warnings.append("Description is very short")

        return ValidationResult(
            is_valid=len(errors) == 0,
            errors=errors,
            warnings=warnings,
            metadata=metadata,
        )
```

---

## Configuration Specification

Plugins receive configuration through the `configure` hook.

### PluginConfig Structure

```python
@dataclass
class PluginConfig:
    enabled: bool = True         # Plugin enabled/disabled
    priority: int = 100          # Lower = higher priority
    settings: Dict[str, Any] = field(default_factory=dict)
```

### Implementing Configuration

```python
class MyPlugin(BaseImporterPlugin):

    @hookimpl
    def configure(self, config: PluginConfig) -> None:
        """Store configuration."""
        self._config = config

        # Initialize based on config
        api_key = config.settings.get("api_key")
        if api_key:
            self._client = APIClient(api_key)

    @hookimpl
    def validate_config(self, config: PluginConfig) -> List[str]:
        """
        Validate configuration before applying.

        Returns list of error messages (empty if valid).
        """
        errors = []

        # Check required settings
        if "api_key" not in config.settings:
            errors.append("api_key is required in settings")

        # Validate setting values
        timeout = config.settings.get("timeout", 30)
        if not isinstance(timeout, int) or timeout < 1:
            errors.append("timeout must be a positive integer")

        return errors
```

### Configuration Schema (Recommended)

Document your plugin's configuration schema:

```python
class MyPlugin(BaseImporterPlugin):
    """
    Configuration Schema:

    settings:
        api_key: str (required)
            API key for authentication

        timeout: int (default: 30)
            Request timeout in seconds

        batch_size: int (default: 100)
            Number of items to process per batch

        retry_attempts: int (default: 3)
            Number of retry attempts on failure

    Example:
        config = PluginConfig(
            enabled=True,
            priority=10,
            settings={
                "api_key": "your-api-key",
                "timeout": 60,
                "batch_size": 50,
            }
        )
    """
```

---

## Testing Requirements

All plugins MUST include tests.

### Minimum Test Coverage

1. **Plugin Registration**: Plugin can be registered
2. **Metadata**: Metadata is complete and valid
3. **Hook Implementations**: All required hooks work
4. **Error Handling**: Errors are handled gracefully
5. **Configuration**: Configuration validation works

### Test Template

```python
import pytest
from pathlib import Path

from importers.core import PluginManager, reset_plugin_manager
from my_plugin import MySourcePlugin


@pytest.fixture
def plugin_manager():
    reset_plugin_manager()
    manager = PluginManager()
    yield manager
    reset_plugin_manager()


@pytest.fixture
def plugin():
    return MySourcePlugin()


class TestMySourcePlugin:
    """Tests for MySourcePlugin."""

    def test_plugin_id(self, plugin):
        """Plugin has valid ID."""
        assert plugin.plugin_id == "my_source"
        assert plugin.plugin_id.islower()
        assert " " not in plugin.plugin_id

    def test_plugin_type(self, plugin):
        """Plugin has correct type."""
        from importers.core import PluginType
        assert plugin.plugin_type == PluginType.SOURCE

    def test_metadata(self, plugin):
        """Plugin metadata is complete."""
        metadata = plugin.metadata
        assert metadata.name
        assert metadata.version
        assert metadata.description
        assert metadata.plugin_type == plugin.plugin_type

    def test_registration(self, plugin_manager, plugin):
        """Plugin can be registered."""
        plugin_manager.register(plugin)
        assert plugin_manager.get_plugin(plugin.plugin_id) is plugin

    def test_get_source_info(self, plugin_manager, plugin):
        """get_source_info hook works."""
        plugin_manager.register(plugin)
        source_info = plugin_manager.hook.get_source_info()
        assert source_info is not None
        assert source_info.id == plugin.plugin_id

    def test_get_default_license(self, plugin_manager, plugin):
        """get_default_license hook works."""
        plugin_manager.register(plugin)
        license_info = plugin_manager.hook.get_default_license()
        assert license_info is not None
        assert license_info.type  # Has license type

    @pytest.mark.asyncio
    async def test_get_course_catalog(self, plugin_manager, plugin):
        """get_course_catalog hook works."""
        plugin_manager.register(plugin)
        result = await plugin_manager.call_async_hook_first(
            "get_course_catalog",
            page=1,
            page_size=10,
            filters=None,
            search=None,
        )
        assert result is not None
        courses, total, filters = result
        assert isinstance(courses, list)
        assert isinstance(total, int)
        assert isinstance(filters, dict)

    @pytest.mark.asyncio
    async def test_download_course(self, plugin_manager, plugin, tmp_path):
        """download_course hook works."""
        plugin_manager.register(plugin)

        # Get a course ID first
        result = await plugin_manager.call_async_hook_first(
            "get_course_catalog",
            page=1, page_size=1, filters=None, search=None,
        )
        courses, _, _ = result
        if not courses:
            pytest.skip("No courses available")

        course_id = courses[0].id
        download_path = await plugin_manager.call_async_hook_first(
            "download_course",
            course_id=course_id,
            output_dir=tmp_path,
            progress_callback=None,
        )
        assert download_path is not None

    def test_validate_license(self, plugin_manager, plugin):
        """validate_license hook works."""
        plugin_manager.register(plugin)
        result = plugin_manager.hook.validate_license(course_id="test-course")
        assert result is not None
        assert hasattr(result, "can_import")

    def test_configuration(self, plugin_manager, plugin):
        """Plugin accepts configuration."""
        from importers.core import PluginConfig

        plugin_manager.register(plugin)
        config = PluginConfig(
            enabled=True,
            settings={"api_key": "test123"},
        )
        errors = plugin_manager.configure_plugin(plugin.plugin_id, config)
        assert isinstance(errors, list)

    def test_error_handling(self, plugin_manager, plugin):
        """Plugin handles errors gracefully."""
        plugin_manager.register(plugin)

        # Test with invalid course ID
        result = plugin_manager.hook.validate_license(course_id="nonexistent")
        # Should not raise, should return a result
        assert result is not None
```

---

## Distribution

### Package Structure

```
my-importer-plugin/
├── pyproject.toml
├── README.md
├── LICENSE
├── src/
│   └── my_plugin/
│       ├── __init__.py
│       └── source.py
└── tests/
    └── test_source.py
```

### pyproject.toml Template

```toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "unamentis-plugin-mysource"
version = "1.0.0"
description = "My Source plugin for UnaMentis importers"
readme = "README.md"
requires-python = ">=3.10"
license = {text = "MIT"}
authors = [
    {name = "Your Name", email = "you@example.com"}
]
classifiers = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
]
dependencies = [
    "unamentis-importers>=1.0.0",
    "aiohttp>=3.8.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0.0",
    "pytest-asyncio>=0.21.0",
]

# Register as a source plugin
[project.entry-points."unamentis.importers.sources"]
my_source = "my_plugin.source:MySourcePlugin"

[tool.setuptools.packages.find]
where = ["src"]
```

### Entry Point Groups

| Plugin Type | Entry Point Group |
|-------------|-------------------|
| SOURCE | `unamentis.importers.sources` |
| PARSER | `unamentis.importers.parsers` |
| ENRICHER | `unamentis.importers.enrichers` |
| EXPORTER | `unamentis.importers.exporters` |
| VALIDATOR | `unamentis.importers.validators` |

---

## Compliance Checklist

Use this checklist before publishing your plugin:

### Required

- [ ] Plugin inherits from `BaseImporterPlugin`
- [ ] `plugin_id` is unique, lowercase, uses underscores
- [ ] `plugin_type` matches the plugin category
- [ ] `metadata` includes name, version, description
- [ ] All required hooks are implemented with `@hookimpl`
- [ ] Async hooks use `async def`
- [ ] License validation is implemented (for SOURCE plugins)
- [ ] Errors are caught and handled gracefully
- [ ] Progress is reported via callbacks (where applicable)
- [ ] Tests cover all required hooks
- [ ] pyproject.toml has correct entry point

### Recommended

- [ ] Version follows Semantic Versioning
- [ ] Configuration schema is documented
- [ ] README includes usage examples
- [ ] Logging uses the `logging` module
- [ ] Type hints are complete
- [ ] Docstrings follow Google/NumPy style

### Best Practices

- [ ] Uses `aiohttp` for HTTP requests
- [ ] Implements retry logic for network operations
- [ ] Caches expensive operations
- [ ] Supports cancellation where possible
- [ ] Includes integration tests

---

## Support

- **Documentation**: `docs/PLUGIN_ARCHITECTURE.md`
- **Examples**: `server/importers/sources/mit_ocw.py`
- **Issues**: https://github.com/sirfifer/voicelearn-ios/issues

---

## Changelog

### 1.0.0 (2025-01-15)

- Initial plugin specification
- Source, Parser, Enricher, Exporter, Validator plugin types
- Pluggy-based hook system
- Configuration management
- Testing requirements
