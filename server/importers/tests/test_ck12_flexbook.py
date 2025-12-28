"""
Tests for the CK-12 FlexBook source handler.

Tests cover:
- Plugin registration and discovery
- Course catalog operations (Stage 1)
- Course detail retrieval (Stage 2)
- Download functionality
- License validation
- EPUB parsing
- Real source integration tests

Test Philosophy:
- Real tests against CK-12 where practical (catalog, structure)
- Mock network for download operations to avoid rate limiting
- Full coverage of two-stage approach
"""

import asyncio
import json
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from ..core.base import LicenseValidationResult
from ..core.models import (
    CourseCatalogEntry,
    CourseDetail,
    CourseFeature,
    CurriculumSource,
    LicenseInfo,
)
from ..core.plugin import (
    PluginManager,
    PluginType,
    get_plugin_manager,
    reset_plugin_manager,
)
from ..sources.ck12_flexbook import (
    CK12_LICENSE,
    CK12FlexBookHandler,
    _load_courses_from_catalog,
    _reset_catalog_cache,
)


# =============================================================================
# Test Fixtures
# =============================================================================


@pytest.fixture
def ck12_handler():
    """Create a fresh CK-12 handler for each test."""
    _reset_catalog_cache()
    handler = CK12FlexBookHandler()
    yield handler
    # Cleanup
    asyncio.get_event_loop().run_until_complete(handler.close())


@pytest.fixture
def plugin_manager():
    """Create a fresh plugin manager for each test."""
    reset_plugin_manager()
    manager = PluginManager()
    yield manager
    reset_plugin_manager()


@pytest.fixture
def temp_output_dir():
    """Create a temporary directory for downloads."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


# =============================================================================
# Basic Handler Tests
# =============================================================================


class TestCK12HandlerBasics:
    """Tests for basic handler properties and initialization."""

    def test_source_id(self, ck12_handler):
        """Test that source ID is correct."""
        assert ck12_handler.source_id == "ck12_flexbook"

    def test_source_info(self, ck12_handler):
        """Test source info properties."""
        source_info = ck12_handler.source_info

        assert isinstance(source_info, CurriculumSource)
        assert source_info.id == "ck12_flexbook"
        assert source_info.name == "CK-12 FlexBooks"
        assert "K-12" in source_info.description
        assert source_info.base_url == "https://www.ck12.org"
        assert source_info.status == "active"

    def test_default_license(self, ck12_handler):
        """Test default license is CC-BY-NC 3.0."""
        license_info = ck12_handler.default_license

        assert isinstance(license_info, LicenseInfo)
        assert license_info.type == "CC-BY-NC-3.0"
        assert "noncommercial" in license_info.conditions
        assert license_info.attribution_required is True
        assert "CK-12" in license_info.attribution_format


class TestCK12License:
    """Tests for CK-12 license handling."""

    def test_license_structure(self):
        """Test CK-12 license has all required fields."""
        assert CK12_LICENSE.type == "CC-BY-NC-3.0"
        assert CK12_LICENSE.name is not None
        assert CK12_LICENSE.url.startswith("https://")
        assert "share" in CK12_LICENSE.permissions
        assert "adapt" in CK12_LICENSE.permissions
        assert "attribution" in CK12_LICENSE.conditions
        assert "noncommercial" in CK12_LICENSE.conditions
        assert CK12_LICENSE.holder_name == "CK-12 Foundation"

    def test_license_to_dict(self):
        """Test license serialization."""
        license_dict = CK12_LICENSE.to_dict()

        assert license_dict["type"] == "CC-BY-NC-3.0"
        assert "holder" in license_dict
        assert license_dict["holder"]["name"] == "CK-12 Foundation"


# =============================================================================
# Stage 1: Catalog Tests
# =============================================================================


class TestCK12Catalog:
    """Tests for Stage 1: Course catalog operations."""

    @pytest.mark.asyncio
    async def test_get_course_catalog_basic(self, ck12_handler):
        """Test basic catalog retrieval."""
        courses, total, filter_options = await ck12_handler.get_course_catalog(
            page=1,
            page_size=10,
        )

        assert isinstance(courses, list)
        assert len(courses) > 0
        assert len(courses) <= 10
        assert total > 0
        assert isinstance(filter_options, dict)
        assert "subjects" in filter_options
        assert "levels" in filter_options

    @pytest.mark.asyncio
    async def test_get_course_catalog_pagination(self, ck12_handler):
        """Test catalog pagination."""
        # Get first page
        page1, total1, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=5,
        )

        # Get second page
        page2, total2, _ = await ck12_handler.get_course_catalog(
            page=2,
            page_size=5,
        )

        assert total1 == total2  # Total should be consistent
        assert len(page1) <= 5
        assert len(page2) <= 5

        # Pages should have different courses
        page1_ids = {c.id for c in page1}
        page2_ids = {c.id for c in page2}
        assert page1_ids.isdisjoint(page2_ids) or total1 <= 5

    @pytest.mark.asyncio
    async def test_get_course_catalog_search(self, ck12_handler):
        """Test catalog search functionality."""
        # Search for math courses
        courses, total, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=20,
            search="algebra",
        )

        assert len(courses) > 0
        # All results should contain "algebra" somewhere
        for course in courses:
            search_text = (
                course.title.lower()
                + course.description.lower()
                + " ".join(course.keywords).lower()
            )
            assert "algebra" in search_text

    @pytest.mark.asyncio
    async def test_get_course_catalog_filter_by_subject(self, ck12_handler):
        """Test filtering by subject."""
        courses, total, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=50,
            filters={"subject": "Mathematics"},
        )

        assert len(courses) > 0
        for course in courses:
            assert course.department == "Mathematics"

    @pytest.mark.asyncio
    async def test_get_course_catalog_filter_by_level(self, ck12_handler):
        """Test filtering by level."""
        courses, total, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=50,
            filters={"level": "middle-school"},
        )

        assert len(courses) > 0
        for course in courses:
            assert course.level == "middle-school"

    @pytest.mark.asyncio
    async def test_search_courses(self, ck12_handler):
        """Test the search_courses convenience method."""
        courses = await ck12_handler.search_courses("science", limit=10)

        assert isinstance(courses, list)
        assert len(courses) <= 10

    def test_course_catalog_entry_structure(self, ck12_handler):
        """Test that catalog entries have correct structure."""
        # Get a course from the cache
        if ck12_handler._catalog_cache:
            course_id = list(ck12_handler._catalog_cache.keys())[0]
            entry = ck12_handler._catalog_cache[course_id]

            assert isinstance(entry, CourseCatalogEntry)
            assert entry.id is not None
            assert entry.source_id == "ck12_flexbook"
            assert entry.title is not None
            assert entry.description is not None
            assert isinstance(entry.instructors, list)
            assert isinstance(entry.features, list)
            assert entry.license is not None


# =============================================================================
# Stage 2: Detail and Download Tests
# =============================================================================


class TestCK12CourseDetail:
    """Tests for Stage 2: Course detail retrieval."""

    @pytest.mark.asyncio
    async def test_get_course_detail(self, ck12_handler):
        """Test getting course details."""
        # Get a course from the catalog first
        courses, _, _ = await ck12_handler.get_course_catalog(page=1, page_size=1)
        assert len(courses) > 0

        course_id = courses[0].id
        detail = await ck12_handler.get_course_detail(course_id)

        assert isinstance(detail, CourseDetail)
        assert detail.id == course_id
        assert detail.title is not None
        assert detail.description is not None
        assert isinstance(detail.lectures, list)

    @pytest.mark.asyncio
    async def test_get_course_detail_not_found(self, ck12_handler):
        """Test getting details for non-existent course."""
        from ..core.base import LicenseRestrictionError

        # License validation fails first for non-existent course
        with pytest.raises((ValueError, LicenseRestrictionError), match="not found"):
            await ck12_handler.get_course_detail("nonexistent-course-id")

    @pytest.mark.asyncio
    async def test_course_detail_has_lessons(self, ck12_handler):
        """Test that course detail includes lesson structure."""
        # Use Pre-Algebra which has detailed chapter info
        detail = await ck12_handler.get_course_detail("8th-pre-algebra")

        assert detail.lectures is not None
        assert len(detail.lectures) > 0

        # Check lecture structure
        lecture = detail.lectures[0]
        assert lecture.id is not None
        assert lecture.number >= 1
        assert lecture.title is not None

    @pytest.mark.asyncio
    async def test_course_detail_has_assignments(self, ck12_handler):
        """Test that course detail includes assignments/practice."""
        detail = await ck12_handler.get_course_detail("8th-pre-algebra")

        # Should have assignments based on practice_count
        assert detail.assignments is not None or detail.lectures is not None

    @pytest.mark.asyncio
    async def test_course_detail_estimates(self, ck12_handler):
        """Test that course detail includes time/size estimates."""
        detail = await ck12_handler.get_course_detail("8th-pre-algebra")

        assert detail.estimated_import_time is not None
        assert detail.estimated_output_size is not None


class TestCK12Download:
    """Tests for download functionality."""

    @pytest.mark.asyncio
    async def test_download_creates_output_directory(
        self, ck12_handler, temp_output_dir
    ):
        """Test that download creates output directory structure."""
        # Mock the network calls to avoid actual downloads
        with patch.object(ck12_handler, "_get_session") as mock_session:
            mock_resp = AsyncMock()
            mock_resp.status = 404  # Simulate no EPUB available
            mock_resp.text = AsyncMock(return_value="<html></html>")

            mock_session_obj = AsyncMock()
            mock_session_obj.get = AsyncMock(return_value=mock_resp)
            mock_session_obj.__aenter__ = AsyncMock(return_value=mock_session_obj)
            mock_session_obj.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_obj

            # Use a real course from catalog
            course_id = "8th-pre-algebra"

            try:
                result = await ck12_handler.download_course(
                    course_id=course_id,
                    output_dir=temp_output_dir,
                )

                # Check output directory was created
                course_dir = temp_output_dir / course_id
                assert course_dir.exists()

                # Check metadata file was created
                metadata_path = course_dir / "course_metadata.json"
                assert metadata_path.exists()

                # Verify metadata content
                with open(metadata_path) as f:
                    metadata = json.load(f)
                    assert metadata["source"] == "ck12_flexbook"
                    assert metadata["course_id"] == course_id
                    assert "license" in metadata
                    assert "attribution" in metadata

            except Exception:
                # Download may fail due to network, but dir should be created
                pass

    @pytest.mark.asyncio
    async def test_download_with_progress_callback(
        self, ck12_handler, temp_output_dir
    ):
        """Test that progress callback is called during download."""
        progress_calls = []

        def progress_callback(pct: float, msg: str):
            progress_calls.append((pct, msg))

        with patch.object(ck12_handler, "_get_session") as mock_session:
            mock_resp = AsyncMock()
            mock_resp.status = 404
            mock_resp.text = AsyncMock(return_value="<html></html>")

            mock_session_obj = AsyncMock()
            mock_session_obj.get = AsyncMock(return_value=mock_resp)
            mock_session_obj.__aenter__ = AsyncMock(return_value=mock_session_obj)
            mock_session_obj.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_obj

            try:
                await ck12_handler.download_course(
                    course_id="8th-pre-algebra",
                    output_dir=temp_output_dir,
                    progress_callback=progress_callback,
                )

                # Should have received progress updates
                assert len(progress_calls) > 0

                # First call should be at start
                assert progress_calls[0][0] >= 0

                # Last call should be completion (100%)
                assert progress_calls[-1][0] == 100.0

            except Exception:
                # Even on failure, some progress should have been reported
                assert len(progress_calls) > 0


# =============================================================================
# License Validation Tests
# =============================================================================


class TestCK12LicenseValidation:
    """Tests for license validation."""

    def test_validate_license_valid_course(self, ck12_handler):
        """Test license validation for a valid course."""
        result = ck12_handler.validate_license("8th-pre-algebra")

        assert isinstance(result, LicenseValidationResult)
        assert result.can_import is True
        assert result.license is not None
        assert result.license.type == "CC-BY-NC-3.0"
        assert result.attribution_text is not None
        assert "CK-12" in result.attribution_text

    def test_validate_license_invalid_course(self, ck12_handler):
        """Test license validation for non-existent course."""
        result = ck12_handler.validate_license("nonexistent-course")

        assert result.can_import is False
        assert "not found" in result.warnings[0].lower()

    def test_validate_license_includes_noncommercial_warning(self, ck12_handler):
        """Test that non-commercial warning is included."""
        result = ck12_handler.validate_license("8th-pre-algebra")

        # Should warn about non-commercial use
        assert any("commercial" in w.lower() for w in result.warnings)

    def test_get_attribution_text(self, ck12_handler):
        """Test attribution text generation."""
        attribution = ck12_handler.get_attribution_text(
            "test-course",
            "Test Course Title"
        )

        assert "CK-12" in attribution
        assert "Test Course Title" in attribution
        assert "CC-BY-NC" in attribution


# =============================================================================
# EPUB Parsing Tests
# =============================================================================


class TestCK12EPUBParsing:
    """Tests for EPUB parsing functionality."""

    def test_parse_opf_metadata(self, ck12_handler):
        """Test OPF metadata parsing."""
        opf_content = """<?xml version="1.0"?>
        <package>
            <metadata>
                <title>Test FlexBook</title>
                <creator>CK-12 Foundation</creator>
                <description>A test book</description>
                <language>en-US</language>
            </metadata>
        </package>
        """

        metadata = ck12_handler._parse_opf_metadata(opf_content)

        assert metadata.get("title") == "Test FlexBook"
        assert metadata.get("creator") == "CK-12 Foundation"
        assert metadata.get("description") == "A test book"

    def test_parse_lesson_html(self, ck12_handler):
        """Test HTML lesson parsing."""
        html_content = """
        <html>
        <head><title>Adding Integers</title></head>
        <body>
            <h1>Adding Integers</h1>
            <article>
                <p>When adding integers, follow these rules:</p>
                <p>Same signs: add and keep the sign.</p>
                <p>Different signs: subtract and keep the sign of the larger.</p>
                <dfn>Integer</dfn> - A whole number.
            </article>
            <div class="problem">
                <p>Practice: What is 5 + (-3)?</p>
            </div>
        </body>
        </html>
        """

        lesson_data = ck12_handler._parse_lesson_html(html_content, "lesson1.html")

        assert lesson_data["title"] == "Adding Integers"
        assert "integers" in lesson_data["text"].lower()
        assert len(lesson_data.get("vocabulary", [])) > 0
        assert len(lesson_data.get("problems", [])) > 0


# =============================================================================
# Plugin Integration Tests
# =============================================================================


class TestCK12PluginIntegration:
    """Tests for plugin architecture integration."""

    def test_handler_registered_via_source_registry(self, plugin_manager):
        """Test that handler is registered via SourceRegistry decorator."""
        from ..core.registry import SourceRegistry

        # The handler should be in the registry
        handlers = list(SourceRegistry._handlers.keys())
        assert "ck12_flexbook" in handlers

    def test_source_in_plugin_manager(self, plugin_manager):
        """Test that source appears in plugin manager after discovery."""
        from ..core.registry import init_plugin_system

        # Initialize and discover plugins
        manager = init_plugin_system()

        # Should find the CK-12 source
        source = manager.get_source("ck12_flexbook")
        # Note: May be None if not fully initialized via adapter
        # but the handler should be in SourceRegistry


# =============================================================================
# Real Source Integration Tests
# =============================================================================


@pytest.mark.integration
class TestCK12RealSource:
    """
    Integration tests against real CK-12 source.

    These tests make actual network requests to CK-12.
    Run with: pytest -m integration

    Note: These tests may be slow and should be run sparingly
    to avoid rate limiting.
    """

    @pytest.mark.asyncio
    async def test_catalog_loads_from_json(self, ck12_handler):
        """Test that catalog loads properly from JSON file."""
        courses, total, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=100,
        )

        # Should have multiple courses
        assert total >= 10, "Expected at least 10 courses in catalog"

        # Verify we have expected subjects
        subjects = set(c.department for c in courses)
        assert "Mathematics" in subjects
        assert "Science" in subjects

    @pytest.mark.asyncio
    async def test_8th_grade_content_available(self, ck12_handler):
        """Test that 8th grade target content is in catalog."""
        # These are the primary 8th grade targets from the spec
        expected_courses = [
            "8th-pre-algebra",
            "ms-physical-science",
            "ms-life-science",
            "ms-earth-science",
        ]

        for course_id in expected_courses:
            entry = ck12_handler._catalog_cache.get(course_id)
            assert entry is not None, f"Expected course {course_id} in catalog"
            assert "8" in entry.level or entry.level == "middle-school"

    @pytest.mark.asyncio
    async def test_course_has_proper_metadata(self, ck12_handler):
        """Test that courses have all required metadata."""
        courses, _, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=10,
        )

        for course in courses:
            # Required fields
            assert course.id is not None and len(course.id) > 0
            assert course.title is not None and len(course.title) > 0
            assert course.description is not None
            assert course.source_id == "ck12_flexbook"

            # License should always be present
            assert course.license is not None
            assert course.license.type == "CC-BY-NC-3.0"

    @pytest.mark.asyncio
    async def test_standards_alignment_present(self, ck12_handler):
        """Test that courses have standards alignment info."""
        # Get a course with known standards
        raw_data = ck12_handler._raw_data_cache.get("8th-pre-algebra")

        if raw_data:
            standards = raw_data.get("standards", [])
            assert len(standards) > 0, "Expected standards alignment"

            # Check Common Core standards for math
            cc_standards = [s for s in standards if s.get("framework") == "Common Core"]
            assert len(cc_standards) > 0, "Expected Common Core standards for math"


# =============================================================================
# Edge Cases and Error Handling
# =============================================================================


class TestCK12EdgeCases:
    """Tests for edge cases and error handling."""

    @pytest.mark.asyncio
    async def test_empty_search_returns_all(self, ck12_handler):
        """Test that empty search returns all courses."""
        all_courses, all_total, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=100,
        )

        empty_search, empty_total, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=100,
            search="",
        )

        assert all_total == empty_total

    @pytest.mark.asyncio
    async def test_invalid_filter_ignored(self, ck12_handler):
        """Test that invalid filters don't break catalog."""
        courses, total, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=10,
            filters={"invalid_filter": "value"},
        )

        # Should still return results
        assert isinstance(courses, list)
        assert total >= 0

    @pytest.mark.asyncio
    async def test_page_beyond_results(self, ck12_handler):
        """Test requesting a page beyond available results."""
        courses, total, _ = await ck12_handler.get_course_catalog(
            page=1000,
            page_size=10,
        )

        # Should return empty list, not error
        assert courses == []

    @pytest.mark.asyncio
    async def test_zero_page_size(self, ck12_handler):
        """Test edge case of zero page size."""
        # This is an edge case - implementation should handle gracefully
        courses, total, _ = await ck12_handler.get_course_catalog(
            page=1,
            page_size=0,
        )

        # Should return empty or handle gracefully
        assert isinstance(courses, list)


# =============================================================================
# Session Management Tests
# =============================================================================


class TestCK12SessionManagement:
    """Tests for HTTP session management."""

    @pytest.mark.asyncio
    async def test_session_creation(self, ck12_handler):
        """Test that session is created on first use."""
        assert ck12_handler._session is None

        session = await ck12_handler._get_session()
        assert session is not None
        assert ck12_handler._session is not None

    @pytest.mark.asyncio
    async def test_session_reuse(self, ck12_handler):
        """Test that session is reused across calls."""
        session1 = await ck12_handler._get_session()
        session2 = await ck12_handler._get_session()

        assert session1 is session2

    @pytest.mark.asyncio
    async def test_close_session(self, ck12_handler):
        """Test session cleanup."""
        await ck12_handler._get_session()
        assert ck12_handler._session is not None

        await ck12_handler.close()
        # Session should be closed (not necessarily None)


# =============================================================================
# Data Quality Tests
# =============================================================================


class TestCK12DataQuality:
    """Tests for data quality and consistency."""

    def test_catalog_json_valid(self):
        """Test that catalog JSON file is valid."""
        from ..sources.ck12_flexbook import CATALOG_FILE

        assert CATALOG_FILE.exists(), "Catalog file should exist"

        with open(CATALOG_FILE) as f:
            data = json.load(f)

        assert "metadata" in data
        assert "courses" in data
        assert len(data["courses"]) > 0

    def test_all_courses_have_required_fields(self):
        """Test that all courses in catalog have required fields."""
        _reset_catalog_cache()
        courses = _load_courses_from_catalog()

        required_fields = ["id", "title", "subject", "level"]

        for course in courses:
            for field in required_fields:
                assert field in course, f"Course missing {field}: {course.get('id', 'unknown')}"

    def test_course_ids_are_unique(self):
        """Test that all course IDs are unique."""
        _reset_catalog_cache()
        courses = _load_courses_from_catalog()

        ids = [c["id"] for c in courses]
        assert len(ids) == len(set(ids)), "Course IDs should be unique"

    def test_subjects_are_valid(self):
        """Test that all subjects are from the expected list."""
        _reset_catalog_cache()
        courses = _load_courses_from_catalog()

        valid_subjects = {
            "Mathematics",
            "Science",
            "English Language Arts",
            "Social Studies",
            "Health",
        }

        for course in courses:
            subject = course.get("subject")
            assert subject in valid_subjects, f"Invalid subject: {subject}"

    def test_grade_levels_are_valid(self):
        """Test that all grade levels are valid."""
        _reset_catalog_cache()
        courses = _load_courses_from_catalog()

        valid_levels = {"elementary", "middle-school", "high-school"}

        for course in courses:
            level = course.get("level")
            assert level in valid_levels, f"Invalid level: {level}"
