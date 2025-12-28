"""
Example Source Plugin Template

This is a complete, runnable example of a compliant source plugin.
Copy this file and modify it to create your own source plugin.

Usage:
    1. Copy this file to your project
    2. Rename the class and update plugin_id
    3. Implement the TODO sections
    4. Add tests
    5. Register via pyproject.toml entry points

See docs/PLUGIN_SPEC.md for the complete specification.
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

import aiohttp

# Import from the importer framework
# In your external plugin, use: from unamentis_importers.core import ...
from importers.core import (
    BaseImporterPlugin,
    PluginConfig,
    PluginMetadata,
    PluginRegistry,
    PluginType,
    hookimpl,
)
from importers.core.base import LicenseValidationResult
from importers.core.models import (
    AssignmentInfo,
    CourseCatalogEntry,
    CourseDetail,
    CourseFeature,
    CurriculumSource,
    ExamInfo,
    LectureInfo,
    LicenseInfo,
)

logger = logging.getLogger(__name__)


# =============================================================================
# License Definition
# =============================================================================

# Define the license for your source's content
# Use SPDX identifiers: https://spdx.org/licenses/
EXAMPLE_LICENSE = LicenseInfo(
    type="CC-BY-4.0",
    name="Creative Commons Attribution 4.0 International",
    url="https://creativecommons.org/licenses/by/4.0/",
    permissions=["share", "adapt", "commercial"],
    conditions=["attribution"],
    attribution_required=True,
    attribution_format=(
        "Content from Example Source (example.com), "
        "licensed under CC-BY 4.0."
    ),
    holder_name="Example Source Inc",
    holder_url="https://example.com",
    restrictions=[],
)


# =============================================================================
# Plugin Implementation
# =============================================================================

@PluginRegistry.register  # Optional: auto-register when module is imported
class ExampleSourcePlugin(BaseImporterPlugin):
    """
    Example Source Plugin

    This plugin demonstrates how to implement a compliant source plugin
    for the UnaMentis curriculum importer framework.

    Configuration:
        api_key: str (required)
            API key for authentication with Example Source

        timeout: int (default: 30)
            HTTP request timeout in seconds

        max_retries: int (default: 3)
            Number of retry attempts for failed requests
    """

    def __init__(self) -> None:
        """Initialize the plugin."""
        super().__init__()
        self._session: Optional[aiohttp.ClientSession] = None
        self._catalog_cache: Dict[str, CourseCatalogEntry] = {}

    # =========================================================================
    # Required Properties
    # =========================================================================

    @property
    def plugin_id(self) -> str:
        """
        Unique identifier for this plugin.

        Requirements:
        - Lowercase
        - Use underscores for spaces
        - Must be unique across all plugins
        """
        return "example_source"

    @property
    def plugin_type(self) -> PluginType:
        """Plugin type - must be SOURCE for source plugins."""
        return PluginType.SOURCE

    @property
    def metadata(self) -> PluginMetadata:
        """
        Plugin metadata for display and dependency resolution.

        Include:
        - name: Human-readable name
        - version: Semantic version (MAJOR.MINOR.PATCH)
        - description: Brief description
        - author: Your name/email
        - url: Repository or documentation URL
        - requires: List of required plugin IDs
        - provides: List of provided capabilities
        """
        return PluginMetadata(
            name="Example Source",
            version="1.0.0",
            description="Import courses from Example Source",
            plugin_type=PluginType.SOURCE,
            author="Your Name <you@example.com>",
            url="https://github.com/you/example-source-plugin",
            requires=[],  # No dependencies on other plugins
            provides=["source:example_source"],
        )

    # =========================================================================
    # Lifecycle Hooks
    # =========================================================================

    @hookimpl
    def plugin_registered(
        self,
        plugin: "ImporterPlugin",  # noqa: F821
        manager: "PluginManager",  # noqa: F821
    ) -> None:
        """
        Called when the plugin is registered.

        Use for initialization that requires access to the plugin manager.
        """
        logger.info(f"Example Source plugin registered: {self.plugin_id}")

    @hookimpl
    def plugin_unregistered(self, plugin: "ImporterPlugin") -> None:  # noqa: F821
        """
        Called when the plugin is unregistered.

        Use for cleanup (close connections, save state, etc.).
        """
        if self._session:
            # Close aiohttp session
            asyncio.create_task(self._close_session())
        logger.info(f"Example Source plugin unregistered: {self.plugin_id}")

    async def _close_session(self) -> None:
        """Close the HTTP session."""
        if self._session:
            await self._session.close()
            self._session = None

    @hookimpl
    def configure(self, config: PluginConfig) -> None:
        """
        Apply configuration to the plugin.

        Called after validate_config succeeds.
        Store configuration and initialize based on settings.
        """
        super().configure(config)  # Stores in self._config

        # Initialize API client if api_key provided
        api_key = config.settings.get("api_key")
        if api_key:
            logger.debug("API key configured")
            # TODO: Initialize your API client here

    @hookimpl
    def validate_config(self, config: PluginConfig) -> List[str]:
        """
        Validate configuration before applying.

        Returns list of error messages (empty if valid).
        This is called BEFORE configure().
        """
        errors = super().validate_config(config)

        # Validate required settings
        if "api_key" not in config.settings:
            errors.append("api_key is required in settings")

        # Validate setting types/values
        timeout = config.settings.get("timeout", 30)
        if not isinstance(timeout, int) or timeout < 1:
            errors.append("timeout must be a positive integer")

        max_retries = config.settings.get("max_retries", 3)
        if not isinstance(max_retries, int) or max_retries < 0:
            errors.append("max_retries must be a non-negative integer")

        return errors

    # =========================================================================
    # Source Information Hooks
    # =========================================================================

    @hookimpl
    def get_source_info(self) -> CurriculumSource:
        """
        Return information about this curriculum source.

        This is displayed in the UI when browsing sources.
        """
        return CurriculumSource(
            id=self.plugin_id,
            name="Example Source",
            description=(
                "Example Source provides high-quality educational content "
                "covering various subjects. All content is freely available "
                "under Creative Commons licenses."
            ),
            base_url="https://example.com",
            logo_url="https://example.com/logo.png",
            features=["pdf", "html", "video"],
        )

    @hookimpl
    def get_default_license(self) -> LicenseInfo:
        """
        Return the default license for this source's content.

        Individual courses may have different licenses.
        Use get_license_for_course() for course-specific licenses.
        """
        return EXAMPLE_LICENSE

    # =========================================================================
    # Catalog Hooks
    # =========================================================================

    @hookimpl
    async def get_course_catalog(
        self,
        page: int,
        page_size: int,
        filters: Optional[Dict[str, Any]],
        search: Optional[str],
    ) -> Tuple[List[CourseCatalogEntry], int, Dict[str, List[str]]]:
        """
        Return paginated course catalog.

        Args:
            page: Page number (1-indexed)
            page_size: Items per page (typically 10-50)
            filters: Filter criteria (subject, level, etc.)
            search: Search query string

        Returns:
            Tuple of:
            - List of CourseCatalogEntry objects for this page
            - Total count of matching courses
            - Available filter options (for UI dropdowns)
        """
        # TODO: Implement your catalog fetching logic
        # This example returns mock data

        # Calculate pagination
        start = (page - 1) * page_size
        end = start + page_size

        # Mock course data
        all_courses = self._get_mock_courses()

        # Apply filters
        if filters:
            if "level" in filters:
                all_courses = [c for c in all_courses if c.level == filters["level"]]
            if "subject" in filters:
                all_courses = [c for c in all_courses if c.department == filters["subject"]]

        # Apply search
        if search:
            search_lower = search.lower()
            all_courses = [
                c for c in all_courses
                if search_lower in c.title.lower()
                or search_lower in c.description.lower()
            ]

        # Get page
        total = len(all_courses)
        courses = all_courses[start:end]

        # Available filter options
        filter_options = {
            "levels": ["introductory", "intermediate", "advanced"],
            "subjects": ["Computer Science", "Mathematics", "Physics"],
            "features": ["video", "transcript", "assignments"],
        }

        return courses, total, filter_options

    @hookimpl
    async def get_course_detail(self, course_id: str) -> Optional[CourseDetail]:
        """
        Return detailed information about a specific course.

        Args:
            course_id: Unique course identifier

        Returns:
            CourseDetail with full information, or None if not found
        """
        # TODO: Implement your course detail fetching logic

        # Check cache first
        if course_id in self._catalog_cache:
            entry = self._catalog_cache[course_id]
        else:
            # Fetch from source
            return None

        # Return full detail (extends CourseCatalogEntry)
        return CourseDetail(
            # Base fields from CourseCatalogEntry
            id=entry.id,
            source_id=entry.source_id,
            title=entry.title,
            instructors=entry.instructors,
            description=entry.description,
            level=entry.level,
            department=entry.department,
            semester=entry.semester,
            features=entry.features,
            license=entry.license,
            keywords=entry.keywords,
            # Extended fields
            syllabus="Week 1: Introduction\nWeek 2: Fundamentals\n...",
            prerequisites=["Basic programming knowledge"],
            lectures=self._get_mock_lectures(course_id),
            assignments=self._get_mock_assignments(course_id),
            exams=[],
            estimated_import_time="5 minutes",
            estimated_output_size="25 MB",
            download_url=f"https://example.com/courses/{course_id}/download",
        )

    # =========================================================================
    # Download Hooks
    # =========================================================================

    @hookimpl
    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]],
    ) -> Path:
        """
        Download course content to local directory.

        Args:
            course_id: Course to download
            output_dir: Directory to save content
            progress_callback: Function to report progress
                - First arg: percentage (0-100)
                - Second arg: status message

        Returns:
            Path to downloaded content (file or directory)

        Raises:
            LicenseRestrictionError: If course cannot be downloaded
            ValueError: If course not found
        """
        # Report progress
        def report(pct: float, msg: str) -> None:
            if progress_callback:
                progress_callback(pct, msg)
            logger.debug(f"Download progress: {pct:.0f}% - {msg}")

        report(0.0, "Starting download...")

        # Validate license first
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            from importers.core.base import LicenseRestrictionError
            raise LicenseRestrictionError(
                f"Cannot download {course_id}: license validation failed"
            )

        report(10.0, "License validated")

        # TODO: Implement your download logic
        # This example creates a mock download

        # Create output directory
        course_dir = output_dir / course_id
        course_dir.mkdir(parents=True, exist_ok=True)

        report(20.0, "Downloading course materials...")

        # Simulate download
        await asyncio.sleep(0.1)  # Simulate network delay

        report(60.0, "Downloading lectures...")

        # Create mock files
        (course_dir / "course_metadata.json").write_text(
            f'{{"id": "{course_id}", "title": "Example Course"}}'
        )
        (course_dir / "lecture_1.txt").write_text("Lecture 1 content...")
        (course_dir / "lecture_2.txt").write_text("Lecture 2 content...")

        report(90.0, "Finalizing...")

        # Save attribution
        attribution = license_result.attribution_text
        (course_dir / "ATTRIBUTION.txt").write_text(attribution)

        report(100.0, "Download complete")

        return course_dir

    # =========================================================================
    # License Hooks
    # =========================================================================

    @hookimpl
    def validate_license(self, course_id: str) -> LicenseValidationResult:
        """
        Validate that a course can be imported under its license.

        CRITICAL: This is essential for legal compliance.
        Always call this before downloading content.

        Args:
            course_id: Course to validate

        Returns:
            LicenseValidationResult with:
            - can_import: Whether import is allowed
            - license: The applicable license
            - warnings: Any warnings (e.g., "attribution required")
            - attribution_text: Text that must be included
        """
        # TODO: Implement your license validation logic

        # Check for restricted courses
        restricted_courses = ["restricted-course-1", "no-import-course"]
        if course_id in restricted_courses:
            return LicenseValidationResult(
                can_import=False,
                license=None,
                warnings=["This course has restricted distribution"],
                attribution_text="",
            )

        # Get course-specific license or use default
        course_license = self._get_license_for_course(course_id)

        # Generate attribution text
        course_title = self._get_course_title(course_id)
        attribution = (
            f"This content is derived from Example Source (https://example.com). "
            f"Original course: \"{course_title}\". "
            f"Licensed under {course_license.name}."
        )

        # Check for warnings
        warnings = []
        if course_license.attribution_required:
            warnings.append("Attribution is required when using this content")
        if "noncommercial" in course_license.conditions:
            warnings.append("Commercial use is not permitted")

        return LicenseValidationResult(
            can_import=True,
            license=course_license,
            warnings=warnings,
            attribution_text=attribution,
        )

    # =========================================================================
    # Helper Methods
    # =========================================================================

    def _get_license_for_course(self, course_id: str) -> LicenseInfo:
        """Get the license for a specific course."""
        # TODO: Implement course-specific license lookup
        # For now, return default license
        return EXAMPLE_LICENSE

    def _get_course_title(self, course_id: str) -> str:
        """Get course title by ID."""
        if course_id in self._catalog_cache:
            return self._catalog_cache[course_id].title
        return f"Course {course_id}"

    def _get_mock_courses(self) -> List[CourseCatalogEntry]:
        """Generate mock course data for demonstration."""
        courses = [
            CourseCatalogEntry(
                id="cs101-intro-programming",
                source_id=self.plugin_id,
                title="Introduction to Programming",
                instructors=["Dr. Jane Smith"],
                description=(
                    "Learn the fundamentals of programming using Python. "
                    "No prior experience required."
                ),
                level="introductory",
                department="Computer Science",
                semester="Fall 2024",
                features=[
                    CourseFeature(type="video", count=24),
                    CourseFeature(type="transcript", count=24),
                    CourseFeature(type="assignments", count=10),
                ],
                license=EXAMPLE_LICENSE,
                keywords=["python", "programming", "beginner", "cs101"],
            ),
            CourseCatalogEntry(
                id="math201-linear-algebra",
                source_id=self.plugin_id,
                title="Linear Algebra",
                instructors=["Prof. Robert Johnson"],
                description=(
                    "A comprehensive introduction to linear algebra, "
                    "covering vectors, matrices, and transformations."
                ),
                level="intermediate",
                department="Mathematics",
                semester="Spring 2024",
                features=[
                    CourseFeature(type="lecture_notes", count=30),
                    CourseFeature(type="assignments", count=12),
                    CourseFeature(type="exams", count=3),
                ],
                license=EXAMPLE_LICENSE,
                keywords=["math", "linear algebra", "matrices", "vectors"],
            ),
            CourseCatalogEntry(
                id="phys301-quantum-mechanics",
                source_id=self.plugin_id,
                title="Quantum Mechanics",
                instructors=["Dr. Maria Garcia", "Prof. David Lee"],
                description=(
                    "An advanced course covering the principles of "
                    "quantum mechanics and their applications."
                ),
                level="advanced",
                department="Physics",
                semester="Fall 2024",
                features=[
                    CourseFeature(type="video", count=36),
                    CourseFeature(type="transcript", count=36),
                    CourseFeature(type="lecture_notes", count=36),
                ],
                license=EXAMPLE_LICENSE,
                keywords=["physics", "quantum", "advanced", "mechanics"],
            ),
        ]

        # Cache courses
        for course in courses:
            self._catalog_cache[course.id] = course

        return courses

    def _get_mock_lectures(self, course_id: str) -> List[LectureInfo]:
        """Generate mock lecture data."""
        return [
            LectureInfo(
                id="lecture-1",
                title="Introduction and Overview",
                sequence=1,
                duration="45:00",
                has_video=True,
                has_transcript=True,
                has_notes=True,
            ),
            LectureInfo(
                id="lecture-2",
                title="Core Concepts",
                sequence=2,
                duration="50:00",
                has_video=True,
                has_transcript=True,
                has_notes=True,
            ),
            LectureInfo(
                id="lecture-3",
                title="Practical Applications",
                sequence=3,
                duration="55:00",
                has_video=True,
                has_transcript=True,
                has_notes=False,
            ),
        ]

    def _get_mock_assignments(self, course_id: str) -> List[AssignmentInfo]:
        """Generate mock assignment data."""
        return [
            AssignmentInfo(
                id="assignment-1",
                title="Problem Set 1",
                description="Introduction exercises",
                due_sequence=3,
            ),
            AssignmentInfo(
                id="assignment-2",
                title="Problem Set 2",
                description="Core concept exercises",
                due_sequence=6,
            ),
        ]

    async def _get_session(self) -> aiohttp.ClientSession:
        """Get or create HTTP session."""
        if self._session is None:
            timeout = self.get_config_setting("timeout", 30)
            self._session = aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=timeout),
                headers={"User-Agent": f"UnaMentis-Importer/{self.metadata.version}"},
            )
        return self._session


# =============================================================================
# Module Exports
# =============================================================================

# Export the plugin class for entry point discovery
__all__ = ["ExampleSourcePlugin"]


# =============================================================================
# Testing Example
# =============================================================================

if __name__ == "__main__":
    """Quick test of the plugin."""
    import asyncio

    async def main():
        plugin = ExampleSourcePlugin()

        print(f"Plugin ID: {plugin.plugin_id}")
        print(f"Plugin Type: {plugin.plugin_type}")
        print(f"Version: {plugin.metadata.version}")
        print()

        source_info = plugin.get_source_info()
        print(f"Source: {source_info.name}")
        print(f"URL: {source_info.base_url}")
        print()

        courses, total, filters = await plugin.get_course_catalog(
            page=1, page_size=10, filters=None, search=None
        )
        print(f"Found {total} courses:")
        for course in courses:
            print(f"  - {course.title} ({course.level})")

    asyncio.run(main())
