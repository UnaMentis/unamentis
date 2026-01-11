"""
Core Knowledge Foundation source handler.

Provides course catalog browsing and content downloading from the Core Knowledge
Foundation's free curriculum resources. Focuses on voice-friendly subjects:
History, Geography, Language Arts, Science concepts, and Arts.

All content is licensed under CC-BY-NC-SA 3.0 (Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported).

Reference: https://www.coreknowledge.org/

Download Strategy:
- Content available as PDFs from coreknowledge.org
- Organized by subject (CKHG, CKLA, CKSci) and grade level
- Includes teacher guides, student readers, and activity books

Voice Suitability:
- EXCELLENT: History, Geography, Language Arts (narrative content)
- GOOD: Science concepts (explanatory content)
- GOOD: Arts (descriptive content about composers, artists)

Key Features:
- Complete K-8 curriculum across multiple subjects
- Narrative-based content ideal for audio-first learning
- Standards-aligned to Common Core and state standards
"""

__version__ = "1.0.0"
__author__ = "UnaMentis Team"
__url__ = "https://www.coreknowledge.org/"

import asyncio
import json
import logging
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
# Core Knowledge License (applies to all content)
# =============================================================================

COREKNOWLEDGE_LICENSE = LicenseInfo(
    type="CC-BY-NC-SA-3.0",
    name="Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported",
    url="https://creativecommons.org/licenses/by-nc-sa/3.0/",
    permissions=["share", "adapt"],
    conditions=["attribution", "noncommercial", "sharealike"],
    attribution_required=True,
    attribution_format=(
        "Content from Core Knowledge Foundation (coreknowledge.org), "
        "licensed under CC-BY-NC-SA 3.0."
    ),
    holder_name="Core Knowledge Foundation",
    holder_url="https://www.coreknowledge.org/",
    restrictions=["no-commercial-use", "share-alike-required"],
)


# =============================================================================
# Core Knowledge Course Catalog
# =============================================================================

CATALOG_FILE = Path(__file__).parent.parent.parent / "data" / "coreknowledge_catalog.json"

_COURSES_CACHE: Optional[List[Dict[str, Any]]] = None


def _load_courses_from_catalog() -> List[Dict[str, Any]]:
    """Load courses from the JSON catalog file."""
    global _COURSES_CACHE

    if _COURSES_CACHE is not None:
        return _COURSES_CACHE

    if not CATALOG_FILE.exists():
        logger.warning(f"Core Knowledge catalog file not found: {CATALOG_FILE}")
        return []

    try:
        with open(CATALOG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            _COURSES_CACHE = data.get("courses", [])
            logger.info(f"Loaded {len(_COURSES_CACHE)} courses from Core Knowledge catalog")
            return _COURSES_CACHE
    except Exception as e:
        logger.error(f"Failed to load Core Knowledge catalog: {e}")
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
        logger.error(f"Failed to load Core Knowledge catalog metadata: {e}")
        return {}


def _reset_catalog_cache() -> None:
    """Reset the catalog cache. Mainly for testing."""
    global _COURSES_CACHE
    _COURSES_CACHE = None


# Subject categories (voice-friendly prioritized)
COREKNOWLEDGE_SUBJECTS = [
    "History & Geography",  # Excellent for voice
    "Language Arts",        # Excellent for voice
    "Science",              # Good for voice (concepts)
    "Arts",                 # Good for voice (music, art history)
]

COREKNOWLEDGE_GRADE_LEVELS = [
    "elementary",    # K-5
    "middle-school", # 6-8
]


# =============================================================================
# Core Knowledge Source Handler
# =============================================================================

@SourceRegistry.register
class CoreKnowledgeHandler(CurriculumSourceHandler):
    """
    Core Knowledge Foundation source handler.

    Provides:
    - Course catalog browsing (K-8 History, ELA, Science, Arts)
    - Course detail retrieval
    - Content downloading (PDF from coreknowledge.org)
    - License validation (CC-BY-NC-SA 3.0)

    Voice-First Focus:
    - Prioritizes narrative subjects (History, Literature)
    - Avoids visual-dependent content (Math)
    - Marks voice suitability for each course
    """

    BASE_URL = "https://www.coreknowledge.org"
    DOWNLOAD_BASE_URL = "https://www.coreknowledge.org/free-resource"

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
        for feature_name in data.get("features", []):
            features.append(CourseFeature(type=feature_name, count=1, available=True))

        # Add unit count as lessons feature
        unit_count = data.get("unit_count", 0)
        if unit_count:
            features.append(CourseFeature(type="units", count=unit_count, available=True))

        # Add PDF download feature
        features.append(CourseFeature(type="pdf", count=1, available=True))

        return CourseCatalogEntry(
            id=data["id"],
            source_id="coreknowledge",
            title=data["title"],
            instructors=data.get("authors", ["Core Knowledge Foundation"]),
            description=data.get("description", ""),
            level=data.get("level", "elementary"),
            department=data.get("subject"),
            semester=None,
            features=features,
            license=COREKNOWLEDGE_LICENSE,
            keywords=data.get("keywords", []),
            thumbnail_url=None,
        )

    # =========================================================================
    # Properties
    # =========================================================================

    @property
    def source_id(self) -> str:
        return "coreknowledge"

    @property
    def source_info(self) -> CurriculumSource:
        return CurriculumSource(
            id="coreknowledge",
            name="Core Knowledge Foundation",
            description=(
                "Comprehensive K-8 curriculum covering History, Geography, "
                "Language Arts, Science, and the Arts. Narrative-based content "
                "ideal for voice-first learning. Free and openly licensed."
            ),
            logo_url="/images/sources/coreknowledge-logo.png",
            license=COREKNOWLEDGE_LICENSE,
            course_count="24",
            features=["lessons", "teacher-guide", "student-reader", "pdf"],
            status="active",
            base_url=self.BASE_URL,
        )

    @property
    def default_license(self) -> LicenseInfo:
        return COREKNOWLEDGE_LICENSE

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
        """Get paginated course catalog."""
        filters = filters or {}

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

        # Apply subject filter
        if filters.get("subject"):
            subject = filters["subject"]
            courses = [c for c in courses if c.department == subject]

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

        # Apply series filter (CKHG, CKLA, CKSci)
        if filters.get("series"):
            series = filters["series"]
            courses = [
                c for c in courses
                if self._raw_data_cache.get(c.id, {}).get("series") == series
            ]

        # Apply voice suitability filter
        if filters.get("voice_friendly"):
            courses = [
                c for c in courses
                if self._raw_data_cache.get(c.id, {}).get("voice_suitability") == "excellent"
            ]

        total = len(courses)

        # Apply pagination
        start = (page - 1) * page_size
        end = start + page_size
        courses = courses[start:end]

        filter_options = {
            "subjects": COREKNOWLEDGE_SUBJECTS,
            "levels": ["elementary", "middle-school"],
            "grades": ["K", "1", "2", "3", "4", "5", "6", "7", "8"],
            "series": ["CKHG", "CKLA", "CKSci", "CK Arts"],
            "features": ["lessons", "teacher-guide", "student-reader", "pdf"],
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
    # Stage 2: Detail and Download Methods
    # =========================================================================

    async def get_course_detail(self, course_id: str) -> CourseDetail:
        """Get full details for a specific course."""
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        entry = self._catalog_cache.get(course_id)
        if not entry:
            raise ValueError(f"Course not found: {course_id}")

        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            raise ValueError(f"Course data not found: {course_id}")

        # Build lectures list from units
        lectures = []
        units = raw_data.get("units", [])
        for unit in units:
            unit_num = unit.get("number", 0)
            lesson_count = unit.get("lessons", 0)
            lectures.append(LectureInfo(
                id=f"unit-{unit_num}",
                number=unit_num,
                title=f"Unit {unit_num}: {unit.get('title', 'Untitled')}",
                has_video=False,
                has_transcript=False,
                has_notes=True,
                duration=f"{lesson_count} lessons",
            ))

        syllabus = self._build_syllabus(units, raw_data)

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
            prerequisites=[],
            lectures=lectures,
            assignments=[],
            exams=[],
            estimated_import_time=self._estimate_import_time(len(units)),
            estimated_output_size=self._estimate_output_size(len(units)),
            download_url=f"{self.BASE_URL}/curriculum/",
        )

    async def get_normalized_course_detail(self, course_id: str) -> NormalizedCourseDetail:
        """Get normalized course detail for generic plugin UI."""
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        entry = self._catalog_cache.get(course_id)
        if not entry:
            raise ValueError(f"Course not found: {course_id}")

        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            raise ValueError(f"Course data not found: {course_id}")

        # Build normalized content structure from units
        units = []
        raw_units = raw_data.get("units", [])

        for unit in raw_units:
            unit_num = unit.get("number", 0)
            lesson_count = unit.get("lessons", 0)

            # Generate topic entries for lessons
            topics = []
            for lesson_num in range(1, lesson_count + 1):
                topics.append(ContentTopic(
                    id=f"unit{unit_num}-lesson-{lesson_num}",
                    title=f"Lesson {lesson_num}",
                    number=lesson_num,
                    has_video=False,
                    has_transcript=False,
                    has_practice=True,
                ))

            units.append(ContentUnit(
                id=f"unit-{unit_num}",
                title=f"Unit {unit_num}: {unit.get('title', 'Untitled')}",
                number=unit_num,
                topics=topics,
            ))

        level_labels = {
            "elementary": "Elementary (K-5)",
            "middle-school": "Middle School (6-8)",
        }
        level_label = level_labels.get(entry.level, entry.level.replace("-", " ").title())

        content_structure = ContentStructure(
            unit_label="Unit",
            topic_label="Lesson",
            is_flat=False,
            units=units,
        )

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
            syllabus=self._build_syllabus(raw_units, raw_data),
            prerequisites=[],
            estimated_import_time=self._estimate_import_time(len(raw_units)),
            estimated_output_size=self._estimate_output_size(len(raw_units)),
            source_url=self.BASE_URL,
            download_url=f"{self.BASE_URL}/curriculum/",
        )

    def _build_syllabus(self, units: List[Dict], raw_data: Dict) -> str:
        """Build syllabus text from unit structure."""
        if not units:
            return raw_data.get("description", "")

        lines = [raw_data.get("description", ""), ""]
        series = raw_data.get("series", "")
        if series:
            lines.append(f"Series: {series}")
            lines.append("")

        voice_suitability = raw_data.get("voice_suitability", "good")
        lines.append(f"Voice Suitability: {voice_suitability.upper()}")
        lines.append("")

        lines.append("Units:")
        for unit in units:
            num = unit.get("number", 0)
            title = unit.get("title", "Untitled")
            lessons = unit.get("lessons", 0)
            lines.append(f"  Unit {num}: {title} ({lessons} lessons)")

        return "\n".join(lines)

    def _estimate_import_time(self, unit_count: int) -> str:
        """Estimate import time based on unit count."""
        if unit_count <= 4:
            return "2-5 minutes"
        elif unit_count <= 8:
            return "5-10 minutes"
        elif unit_count <= 12:
            return "10-15 minutes"
        else:
            return "15-20 minutes"

    def _estimate_output_size(self, unit_count: int) -> str:
        """Estimate output size based on unit count."""
        if unit_count <= 4:
            return "20-50 MB"
        elif unit_count <= 8:
            return "50-100 MB"
        elif unit_count <= 12:
            return "100-200 MB"
        else:
            return "200-400 MB"

    async def get_download_size(self, course_id: str) -> str:
        """Estimate download size for a course."""
        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            return "Unknown"

        unit_count = len(raw_data.get("units", []))
        return self._estimate_output_size(unit_count)

    # =========================================================================
    # Download Methods
    # =========================================================================

    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]] = None,
        selected_units: Optional[List[str]] = None,
    ) -> Path:
        """Download course content to local directory."""
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        entry = self._catalog_cache.get(course_id)
        if not entry:
            raise ValueError(f"Course not found: {course_id}")

        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            raise ValueError(f"Course data not found: {course_id}")

        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        course_output_dir = output_dir / course_id
        course_output_dir.mkdir(parents=True, exist_ok=True)

        if progress_callback:
            progress_callback(5, "Preparing download...")

        session = await self._get_session()

        # Get units to process
        units = raw_data.get("units", [])
        if selected_units:
            units = [u for u in units if f"unit-{u.get('number')}" in selected_units]

        downloaded_content = []

        if progress_callback:
            progress_callback(10, "Processing course structure...")

        # For Core Knowledge, we create a structured metadata file
        # The actual PDFs would need to be downloaded from specific URLs
        for idx, unit in enumerate(units):
            unit_num = unit.get("number", 1)
            unit_title = unit.get("title", "Unit")
            lesson_count = unit.get("lessons", 0)

            if progress_callback:
                progress = 10 + (idx / len(units)) * 70
                progress_callback(progress, f"Processing Unit {unit_num}: {unit_title}")

            downloaded_content.append({
                "unit": unit_num,
                "title": unit_title,
                "lessons": lesson_count,
                "voice_content": self._generate_voice_content(unit, raw_data),
            })

        if progress_callback:
            progress_callback(90, "Saving course metadata...")

        # Build lectures list for orchestrator compatibility
        # Each unit becomes a lecture entry with lessons as content
        lectures = []
        for idx, unit_data in enumerate(downloaded_content):
            unit_num = unit_data.get("unit", idx + 1)
            unit_title = unit_data.get("title", f"Unit {unit_num}")
            lesson_count = unit_data.get("lessons", 0)

            # Create a lecture entry for the unit
            lectures.append({
                "id": f"unit-{unit_num}",
                "number": unit_num,
                "title": f"Unit {unit_num}: {unit_title}",
                "has_video": False,
                "has_transcript": False,
                "text_preview": f"This unit contains {lesson_count} lessons covering {unit_title}.",
                "lesson_count": lesson_count,
            })

            # Also create individual lesson entries within each unit
            for lesson_num in range(1, lesson_count + 1):
                lectures.append({
                    "id": f"unit-{unit_num}-lesson-{lesson_num}",
                    "number": len(lectures),
                    "title": f"Unit {unit_num}, Lesson {lesson_num}",
                    "has_video": False,
                    "has_transcript": False,
                    "text_preview": f"Lesson {lesson_num} of {unit_title}.",
                    "parent_unit": unit_num,
                })

        # Save comprehensive metadata
        metadata = {
            "source": "coreknowledge",
            "course_id": course_id,
            "title": entry.title,
            "description": entry.description,
            "authors": entry.instructors,
            "instructors": entry.instructors,
            "subject": entry.department,
            "department": entry.department,
            "level": entry.level,
            "grades": raw_data.get("grades", []),
            "series": raw_data.get("series", ""),
            "voice_suitability": raw_data.get("voice_suitability", "good"),
            "keywords": entry.keywords,
            "license": COREKNOWLEDGE_LICENSE.to_dict(),
            "attribution": self.get_attribution_text(course_id, entry.title),
            "units": downloaded_content,
            # Content structure expected by orchestrator
            "content": {
                "lectures": lectures,
                "assignments": [],
                "exams": [],
                "resources": [],
            },
            "download_url": f"{self.BASE_URL}/curriculum/",
        }

        metadata_path = course_output_dir / "course_metadata.json"
        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        if progress_callback:
            progress_callback(100, "Download complete")

        logger.info(f"Downloaded course {course_id} to {course_output_dir}")
        return course_output_dir

    def _generate_voice_content(self, unit: Dict, raw_data: Dict) -> Dict:
        """Generate voice-friendly content structure for a unit."""
        return {
            "unit_title": unit.get("title", ""),
            "lesson_count": unit.get("lessons", 0),
            "subject": raw_data.get("subject", ""),
            "series": raw_data.get("series", ""),
            "voice_ready": raw_data.get("voice_suitability") == "excellent",
        }

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
        """Validate that a course can be imported."""
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
            license=COREKNOWLEDGE_LICENSE,
            warnings=[],
            attribution_text=self.get_attribution_text(course_id, entry.title),
        )

    def get_attribution_text(self, course_id: str, title: str = "") -> str:
        """Get required attribution text for a course."""
        if not title:
            entry = self._catalog_cache.get(course_id)
            title = entry.title if entry else course_id

        raw_data = self._raw_data_cache.get(course_id, {})
        series = raw_data.get("series", "")

        return (
            f'"{title}" ({series}) by Core Knowledge Foundation, '
            f"licensed under CC BY-NC-SA 3.0. "
            f"Available at: coreknowledge.org"
        )
