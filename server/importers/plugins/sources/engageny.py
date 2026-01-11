"""
EngageNY Mathematics source handler.

Provides course catalog browsing and content downloading from the EngageNY
Mathematics archive (preserved on Internet Archive after original site
discontinued in 2022).

All content is licensed under CC-BY-NC-SA 4.0 (Creative Commons
Attribution-NonCommercial-ShareAlike 4.0 International).

Reference:
- Archive: https://archive.org/details/engageny-mathematics
- NYSED: https://www.nysed.gov/curriculum-instruction

Download Strategy:
- Content is available as ZIP files from Internet Archive
- Each module is a separate ZIP containing Word/PDF documents
- Organized by grade level and module number

Two-Stage Approach:
- Stage 1: Get catalog with metadata for UI (lightweight, from JSON)
- Stage 2: Get detailed course info and perform download (on demand)

Key Features:
- Complete PreK-12 Mathematics curriculum
- Standards-aligned to Common Core
- Modular structure: Grades -> Modules -> Topics -> Lessons
"""

__version__ = "1.0.0"
__author__ = "UnaMentis Team"
__url__ = "https://archive.org/details/engageny-mathematics"

import asyncio
import io
import json
import logging
import os
import re
import zipfile
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

import aiohttp

from ...core.base import (
    CurriculumSourceHandler,
    LicenseRestrictionError,
    LicenseValidationResult,
)
from ...core.models import (
    AssignmentInfo,
    ContentStructure,
    ContentTopic,
    ContentUnit,
    CourseCatalogEntry,
    CourseDetail,
    CourseFeature,
    CurriculumSource,
    ExamInfo,
    LectureInfo,
    LicenseInfo,
    NormalizedCourseDetail,
)
from ...core.registry import SourceRegistry

logger = logging.getLogger(__name__)


# =============================================================================
# EngageNY License (applies to all content)
# =============================================================================

ENGAGENY_LICENSE = LicenseInfo(
    type="CC-BY-NC-SA-4.0",
    name="Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International",
    url="https://creativecommons.org/licenses/by-nc-sa/4.0/",
    permissions=["share", "adapt"],
    conditions=["attribution", "noncommercial", "sharealike"],
    attribution_required=True,
    attribution_format=(
        "Content from EngageNY (New York State Education Department), "
        "licensed under CC-BY-NC-SA 4.0. "
        "Original materials available at archive.org/details/engageny-mathematics"
    ),
    holder_name="New York State Education Department",
    holder_url="https://www.nysed.gov/",
    restrictions=["no-commercial-use", "share-alike-required"],
)


# =============================================================================
# EngageNY Course Catalog
# =============================================================================

# Path to the comprehensive course catalog JSON file
CATALOG_FILE = Path(__file__).parent.parent.parent / "data" / "engageny_catalog.json"

# In-memory cache of courses loaded from JSON
_COURSES_CACHE: Optional[List[Dict[str, Any]]] = None


def _load_courses_from_catalog() -> List[Dict[str, Any]]:
    """Load courses from the JSON catalog file."""
    global _COURSES_CACHE

    if _COURSES_CACHE is not None:
        return _COURSES_CACHE

    if not CATALOG_FILE.exists():
        logger.warning(f"EngageNY catalog file not found: {CATALOG_FILE}")
        return []

    try:
        with open(CATALOG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            _COURSES_CACHE = data.get("courses", [])
            logger.info(f"Loaded {len(_COURSES_CACHE)} courses from EngageNY catalog")
            return _COURSES_CACHE
    except Exception as e:
        logger.error(f"Failed to load EngageNY catalog: {e}")
        return []


def _get_catalog_metadata() -> Dict[str, Any]:
    """Get metadata from the catalog file."""
    if not CATALOG_FILE.exists():
        return {}

    try:
        with open(CATALOG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data.get("metadata", {})
    except Exception as e:
        logger.error(f"Failed to load EngageNY catalog metadata: {e}")
        return {}


def _reset_catalog_cache() -> None:
    """Reset the catalog cache. Mainly for testing."""
    global _COURSES_CACHE
    _COURSES_CACHE = None


# Subject categories
ENGAGENY_SUBJECTS = ["Mathematics"]

# Grade levels
ENGAGENY_GRADE_LEVELS = [
    "elementary",  # K-5
    "middle-school",  # 6-8
    "high-school",  # 9-12
]


# =============================================================================
# EngageNY Source Handler
# =============================================================================

@SourceRegistry.register
class EngageNYHandler(CurriculumSourceHandler):
    """
    EngageNY Mathematics source handler.

    Provides:
    - Course catalog browsing (PreK-12 Mathematics)
    - Course detail retrieval
    - Content downloading (ZIP from Internet Archive)
    - License validation (CC-BY-NC-SA 4.0)

    Two-Stage Approach:
    - Stage 1: get_course_catalog() - returns lightweight metadata for UI browsing
    - Stage 2: get_course_detail() + download_course() - full content retrieval
    """

    # Archive base URL
    BASE_URL = "https://archive.org/details/engageny-mathematics"
    DOWNLOAD_BASE_URL = "https://archive.org/download/engageny-mathematics"

    def __init__(self):
        self._session: Optional[aiohttp.ClientSession] = None
        self._catalog_cache: Dict[str, CourseCatalogEntry] = {}
        self._raw_data_cache: Dict[str, Dict[str, Any]] = {}
        self._load_catalog()

    def _load_catalog(self):
        """Load the course catalog from JSON file into cache."""
        courses = _load_courses_from_catalog()
        for course_data in courses:
            entry = self._course_data_to_entry(course_data)
            self._catalog_cache[entry.id] = entry
            self._raw_data_cache[entry.id] = course_data

    def _course_data_to_entry(self, data: Dict[str, Any]) -> CourseCatalogEntry:
        """Convert catalog data to CourseCatalogEntry."""
        features = []

        # Map features from catalog data
        feature_map = {
            "lessons": ("lessons", data.get("lesson_count")),
            "practice": ("practice", data.get("module_count")),
        }

        for feature_name in data.get("features", []):
            if feature_name in feature_map:
                ftype, count = feature_map[feature_name]
                features.append(CourseFeature(type=ftype, count=count, available=True))

        # Add ZIP download feature
        features.append(CourseFeature(type="zip", count=1, available=True))

        return CourseCatalogEntry(
            id=data["id"],
            source_id="engageny",
            title=data["title"],
            instructors=data.get("authors", ["New York State Education Department"]),
            description=data.get("description", ""),
            level=data.get("level", "elementary"),
            department=data.get("subject"),
            semester=None,  # EngageNY doesn't use semesters
            features=features,
            license=ENGAGENY_LICENSE,
            keywords=data.get("keywords", []),
            thumbnail_url=None,  # No thumbnails in archive
        )

    # =========================================================================
    # Properties
    # =========================================================================

    @property
    def source_id(self) -> str:
        return "engageny"

    @property
    def source_info(self) -> CurriculumSource:
        return CurriculumSource(
            id="engageny",
            name="EngageNY Mathematics",
            description=(
                "Complete PreK-12 Mathematics curriculum from New York State "
                "Education Department. Standards-aligned to Common Core. "
                "Archived from the original EngageNY initiative (2012-2022)."
            ),
            logo_url="/images/sources/engageny-logo.png",
            license=ENGAGENY_LICENSE,
            course_count="14",
            features=["lessons", "practice", "zip"],
            status="active",
            base_url=self.BASE_URL,
        )

    @property
    def default_license(self) -> LicenseInfo:
        return ENGAGENY_LICENSE

    # =========================================================================
    # Stage 1: Catalog Methods (Lightweight for UI)
    # =========================================================================

    async def get_course_catalog(
        self,
        page: int = 1,
        page_size: int = 20,
        filters: Optional[Dict[str, Any]] = None,
        search: Optional[str] = None,
    ) -> Tuple[List[CourseCatalogEntry], int, Dict[str, List[str]]]:
        """
        Get paginated course catalog.

        Stage 1 of two-stage approach - returns lightweight metadata for UI browsing.
        No network requests made if catalog is cached.
        """
        filters = filters or {}

        # Start with all courses
        courses = list(self._catalog_cache.values())

        # Apply search filter
        if search:
            search_lower = search.lower()
            courses = [
                c for c in courses
                if search_lower in c.title.lower()
                or search_lower in c.description.lower()
                or any(search_lower in k.lower() for k in c.keywords)
            ]

        # Apply level filter
        if filters.get("level"):
            level = filters["level"]
            courses = [c for c in courses if c.level == level]

        # Apply grade filter
        if filters.get("grade"):
            grade = filters["grade"]
            courses = [
                c for c in courses
                if self._matches_grade(c.id, grade)
            ]

        # Get total count before pagination
        total = len(courses)

        # Apply pagination
        start = (page - 1) * page_size
        end = start + page_size
        courses = courses[start:end]

        # Get available filter options
        filter_options = {
            "subjects": ["Mathematics"],
            "levels": ["elementary", "middle-school", "high-school"],
            "grades": ["PK", "K", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"],
            "features": ["lessons", "practice", "zip"],
        }

        return courses, total, filter_options

    def _matches_grade(self, course_id: str, grade: str) -> bool:
        """Check if a course matches the specified grade level."""
        raw_data = self._raw_data_cache.get(course_id, {})
        target_grades = raw_data.get("grades", [])
        return grade in target_grades

    async def search_courses(
        self,
        query: str,
        limit: int = 20,
    ) -> List[CourseCatalogEntry]:
        """Search courses by query."""
        courses, _, _ = await self.get_course_catalog(
            page=1,
            page_size=limit,
            search=query,
        )
        return courses

    # =========================================================================
    # Stage 2: Detail and Download Methods (Full Content)
    # =========================================================================

    async def get_course_detail(self, course_id: str) -> CourseDetail:
        """
        Get full details for a specific course.

        Stage 2 of two-stage approach.
        """
        # Validate license first
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        # Get base entry from catalog
        entry = self._catalog_cache.get(course_id)
        if not entry:
            raise ValueError(f"Course not found: {course_id}")

        # Get the raw data for additional details
        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            raise ValueError(f"Course data not found: {course_id}")

        # Build lectures list from modules
        lectures = []
        modules = raw_data.get("modules", [])
        for module in modules:
            module_num = module.get("number", 0)
            lesson_count = module.get("lessons", 0)
            lectures.append(LectureInfo(
                id=f"module-{module_num}",
                number=module_num,
                title=f"Module {module_num}: {module.get('title', 'Untitled')}",
                has_video=False,
                has_transcript=False,
                has_notes=True,
                duration=f"{lesson_count} lessons",
            ))

        # Build standards alignment
        standards = raw_data.get("standards", [])
        prerequisites = raw_data.get("prerequisites", [])
        syllabus = self._build_syllabus(modules, raw_data)

        return CourseDetail(
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
            thumbnail_url=entry.thumbnail_url,
            syllabus=syllabus,
            prerequisites=prerequisites,
            lectures=lectures,
            assignments=[],
            exams=[],
            estimated_import_time=self._estimate_import_time(len(modules)),
            estimated_output_size=self._estimate_output_size(len(modules)),
            download_url=raw_data.get("archive_url"),
        )

    async def get_normalized_course_detail(self, course_id: str) -> NormalizedCourseDetail:
        """
        Get normalized course detail for generic plugin UI.

        EngageNY uses a module/lesson structure:
        - unitLabel: "Module"
        - topicLabel: "Lesson"
        """
        # Validate license first
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        # Get base entry from catalog
        entry = self._catalog_cache.get(course_id)
        if not entry:
            raise ValueError(f"Course not found: {course_id}")

        # Get the raw data for additional details
        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            raise ValueError(f"Course data not found: {course_id}")

        # Build normalized content structure from modules
        units = []
        modules = raw_data.get("modules", [])

        for module in modules:
            module_num = module.get("number", 0)
            lesson_count = module.get("lessons", 0)

            # Generate topic entries for lessons in this module
            topics = []
            for lesson_num in range(1, lesson_count + 1):
                topics.append(ContentTopic(
                    id=f"mod{module_num}-lesson-{lesson_num}",
                    title=f"Lesson {lesson_num}",
                    number=lesson_num,
                    has_video=False,
                    has_transcript=False,
                    has_practice=True,
                ))

            units.append(ContentUnit(
                id=f"module-{module_num}",
                title=f"Module {module_num}: {module.get('title', 'Untitled')}",
                number=module_num,
                topics=topics,
            ))

        # Determine level label based on grade level
        level_labels = {
            "elementary": "Elementary (K-5)",
            "middle-school": "Middle School (6-8)",
            "high-school": "High School (9-12)",
        }
        level_label = level_labels.get(entry.level, entry.level.replace("-", " ").title())

        # Build content structure with EngageNY terminology
        content_structure = ContentStructure(
            unit_label="Module",
            topic_label="Lesson",
            is_flat=False,  # EngageNY has nested structure
            units=units,
        )

        # Count total lessons for estimates
        total_lessons = sum(len(u.topics) for u in units)

        return NormalizedCourseDetail(
            id=entry.id,
            source_id=entry.source_id,
            title=entry.title,
            description=entry.description,
            instructors=entry.instructors,
            level=entry.level,
            level_label=level_label,
            department=entry.department,
            semester=None,
            keywords=entry.keywords,
            thumbnail_url=entry.thumbnail_url,
            license=entry.license,
            features=entry.features,
            content_structure=content_structure,
            assignments=[],
            exams=[],
            syllabus=self._build_syllabus(modules, raw_data),
            prerequisites=raw_data.get("prerequisites", []),
            estimated_import_time=self._estimate_import_time(len(modules)),
            estimated_output_size=self._estimate_output_size(len(modules)),
            source_url=self.BASE_URL,
            download_url=raw_data.get("archive_url"),
        )

    def _build_syllabus(self, modules: List[Dict], raw_data: Dict) -> str:
        """Build syllabus text from module structure."""
        if not modules:
            return raw_data.get("description", "")

        lines = [raw_data.get("description", ""), ""]
        lines.append("Modules:")
        for module in modules:
            num = module.get("number", 0)
            title = module.get("title", "Untitled")
            lessons = module.get("lessons", 0)
            lines.append(f"  Module {num}: {title} ({lessons} lessons)")

        return "\n".join(lines)

    def _estimate_import_time(self, module_count: int) -> str:
        """Estimate import time based on module count."""
        if module_count <= 3:
            return "2-5 minutes"
        elif module_count <= 5:
            return "5-10 minutes"
        elif module_count <= 7:
            return "10-15 minutes"
        else:
            return "15-25 minutes"

    def _estimate_output_size(self, module_count: int) -> str:
        """Estimate output size based on module count."""
        # EngageNY modules are typically 50-200MB each as ZIP
        if module_count <= 3:
            return "100-300 MB"
        elif module_count <= 5:
            return "300-500 MB"
        elif module_count <= 7:
            return "500-800 MB"
        else:
            return "800 MB - 1.2 GB"

    async def get_download_size(self, course_id: str) -> str:
        """
        Estimate download size for a course.

        Args:
            course_id: Course identifier

        Returns:
            Human-readable size estimate
        """
        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            return "Unknown"

        module_count = len(raw_data.get("modules", []))
        return self._estimate_output_size(module_count)

    # =========================================================================
    # Download Methods
    # =========================================================================

    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]] = None,
        selected_modules: Optional[List[str]] = None,
    ) -> Path:
        """
        Download course content to local directory.

        Downloads ZIP files from Internet Archive, extracts them, and
        organizes the content.

        Args:
            course_id: Course identifier
            output_dir: Directory to save content
            progress_callback: Optional callback for progress updates
            selected_modules: Optional list of module IDs to download
        """
        # Validate license first
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        entry = self._catalog_cache.get(course_id)
        if not entry:
            raise ValueError(f"Course not found: {course_id}")

        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            raise ValueError(f"Course data not found: {course_id}")

        # Create output directory
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        course_output_dir = output_dir / course_id
        course_output_dir.mkdir(parents=True, exist_ok=True)

        if progress_callback:
            progress_callback(5, "Preparing download...")

        session = await self._get_session()

        # Get modules to download
        modules = raw_data.get("modules", [])
        if selected_modules:
            modules = [m for m in modules if f"module-{m.get('number')}" in selected_modules]

        total_modules = len(modules)
        downloaded_content = []

        for idx, module in enumerate(modules):
            module_num = module.get("number", 1)
            module_title = module.get("title", "Module")

            if progress_callback:
                progress = 10 + (idx / total_modules) * 70
                progress_callback(progress, f"Downloading Module {module_num}...")

            # Construct download URL based on grade and module
            zip_url = self._get_module_download_url(course_id, module_num, raw_data)

            try:
                module_content = await self._download_module(
                    session, zip_url, course_output_dir, module_num
                )
                downloaded_content.append({
                    "module": module_num,
                    "title": module_title,
                    "files": module_content,
                })
            except Exception as e:
                logger.warning(f"Failed to download module {module_num}: {e}")
                downloaded_content.append({
                    "module": module_num,
                    "title": module_title,
                    "error": str(e),
                })

        if progress_callback:
            progress_callback(90, "Saving course metadata...")

        # Save comprehensive metadata
        metadata = {
            "source": "engageny",
            "course_id": course_id,
            "title": entry.title,
            "description": entry.description,
            "authors": entry.instructors,
            "subject": entry.department,
            "level": entry.level,
            "grades": raw_data.get("grades", []),
            "license": ENGAGENY_LICENSE.to_dict(),
            "attribution": self.get_attribution_text(course_id, entry.title),
            "modules": downloaded_content,
            "standards": raw_data.get("standards", []),
            "archive_source": self.BASE_URL,
        }

        metadata_path = course_output_dir / "course_metadata.json"
        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        if progress_callback:
            progress_callback(100, "Download complete")

        logger.info(f"Downloaded course {course_id} to {course_output_dir}")
        return course_output_dir

    def _get_module_download_url(
        self, course_id: str, module_num: int, raw_data: Dict
    ) -> str:
        """Construct download URL for a specific module."""
        # Map course IDs to archive file naming convention
        grade_map = {
            "prekindergarten-math": "Prekindergarten",
            "kindergarten-math": "Kindergarten",
            "grade1-math": "Grade%201",
            "grade2-math": "Grade%202",
            "grade3-math": "Grade%203",
            "grade4-math": "Grade%204",
            "grade5-math": "Grade%205",
            "grade6-math": "Grade%206",
            "grade7-math": "Grade%207",
            "grade8-math": "Grade%208",
            "algebra1": "Algebra%20I",
            "geometry": "Geometry",
            "algebra2": "Algebra%20II",
            "precalculus": "Precalculus",
        }

        grade_prefix = grade_map.get(course_id, course_id)
        filename = f"{grade_prefix}%20Module%20{module_num}.zip"
        return f"{self.DOWNLOAD_BASE_URL}/{filename}"

    async def _download_module(
        self,
        session: aiohttp.ClientSession,
        zip_url: str,
        output_dir: Path,
        module_num: int,
    ) -> List[str]:
        """Download and extract a module ZIP file."""
        logger.info(f"Downloading module from {zip_url}")

        extracted_files = []

        try:
            async with session.get(
                zip_url, timeout=aiohttp.ClientTimeout(total=300)
            ) as resp:
                if resp.status != 200:
                    raise ValueError(f"Download failed with status {resp.status}")

                zip_data = await resp.read()

            # Extract ZIP contents
            module_dir = output_dir / f"module_{module_num}"
            module_dir.mkdir(parents=True, exist_ok=True)

            with zipfile.ZipFile(io.BytesIO(zip_data), "r") as zf:
                for member in zf.namelist():
                    # Skip directories
                    if member.endswith("/"):
                        continue

                    # Extract file
                    filename = os.path.basename(member)
                    if filename:
                        target_path = module_dir / filename
                        with open(target_path, "wb") as f:
                            f.write(zf.read(member))
                        extracted_files.append(str(target_path.relative_to(output_dir)))

            logger.info(f"Extracted {len(extracted_files)} files to {module_dir}")

        except asyncio.TimeoutError:
            raise ValueError(f"Download timeout for {zip_url}")
        except zipfile.BadZipFile:
            raise ValueError(f"Invalid ZIP file from {zip_url}")

        return extracted_files

    async def _get_session(self) -> aiohttp.ClientSession:
        """Get or create an aiohttp session."""
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                headers={
                    "User-Agent": "UnaMentis/1.0 (Educational AI Tutor; https://github.com/unamentis)"
                }
            )
        return self._session

    async def close(self) -> None:
        """Close the aiohttp session."""
        if self._session and not self._session.closed:
            await self._session.close()

    # =========================================================================
    # License Methods
    # =========================================================================

    def validate_license(self, course_id: str) -> LicenseValidationResult:
        """
        Validate that a course can be imported.

        All EngageNY content uses CC-BY-NC-SA 4.0, which is compatible
        with UnaMentis's non-commercial educational use.
        """
        entry = self._catalog_cache.get(course_id)
        if not entry:
            return LicenseValidationResult(
                can_import=False,
                license=None,
                warnings=[f"Course not found: {course_id}"],
                attribution_text="",
            )

        return LicenseValidationResult(
            can_import=True,
            license=ENGAGENY_LICENSE,
            warnings=[],
            attribution_text=self.get_attribution_text(course_id, entry.title),
        )

    def get_attribution_text(self, course_id: str, title: str = "") -> str:
        """Get required attribution text for a course."""
        if not title:
            entry = self._catalog_cache.get(course_id)
            title = entry.title if entry else course_id

        return (
            f'"{title}" by New York State Education Department, '
            f"EngageNY (archive.org/details/engageny-mathematics), "
            f"licensed under CC BY-NC-SA 4.0."
        )
