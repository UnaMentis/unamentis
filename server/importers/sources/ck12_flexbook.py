"""
CK-12 FlexBook source handler.

Provides course catalog browsing and content downloading from CK-12 Foundation.
All content is licensed under CC-BY-NC 3.0 (Creative Commons Attribution-NonCommercial).

Reference: https://www.ck12.org/

Download Strategy:
- CK-12 provides EPUB format for FlexBooks (primary)
- PDF format available as fallback
- HTML available via web scraping (respect robots.txt)

Two-Stage Approach:
- Stage 1: Get catalog with metadata for UI (lightweight)
- Stage 2: Get detailed course info and perform download (on demand)

Key Features:
- 8th Grade Focus: Pre-Algebra, Physical Science, Life Science, Earth Science, ELA, Civics
- Standards Alignment: Common Core, NGSS, state standards
- Modular Content: FlexBooks -> Chapters -> Lessons -> Sections
"""

import asyncio
import io
import json
import logging
import re
import zipfile
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple
from urllib.parse import urljoin, quote
from xml.etree import ElementTree as ET

import aiohttp
from bs4 import BeautifulSoup

from ..core.base import (
    CurriculumSourceHandler,
    LicenseRestrictionError,
    LicenseValidationResult,
)
from ..core.models import (
    AssignmentInfo,
    CourseCatalogEntry,
    CourseDetail,
    CourseFeature,
    CurriculumSource,
    ExamInfo,
    LectureInfo,
    LicenseInfo,
)
from ..core.registry import SourceRegistry

logger = logging.getLogger(__name__)


# =============================================================================
# CK-12 License (applies to all FlexBook content)
# =============================================================================

CK12_LICENSE = LicenseInfo(
    type="CC-BY-NC-3.0",
    name="Creative Commons Attribution-NonCommercial 3.0 Unported",
    url="https://creativecommons.org/licenses/by-nc/3.0/",
    permissions=["share", "adapt"],
    conditions=["attribution", "noncommercial"],
    attribution_required=True,
    attribution_format=(
        "Content from CK-12 Foundation (www.ck12.org), "
        "licensed under CC-BY-NC 3.0."
    ),
    holder_name="CK-12 Foundation",
    holder_url="https://www.ck12.org/",
    restrictions=["no-commercial-use"],
)


# =============================================================================
# CK-12 Course Catalog
# =============================================================================

# Path to the comprehensive course catalog JSON file
CATALOG_FILE = Path(__file__).parent.parent / "data" / "ck12_catalog.json"

# In-memory cache of courses loaded from JSON
_COURSES_CACHE: Optional[List[Dict[str, Any]]] = None


def _load_courses_from_catalog() -> List[Dict[str, Any]]:
    """Load courses from the JSON catalog file."""
    global _COURSES_CACHE

    if _COURSES_CACHE is not None:
        return _COURSES_CACHE

    if not CATALOG_FILE.exists():
        logger.warning(f"CK-12 catalog file not found: {CATALOG_FILE}")
        return []

    try:
        with open(CATALOG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            _COURSES_CACHE = data.get("courses", [])
            logger.info(f"Loaded {len(_COURSES_CACHE)} courses from CK-12 catalog")
            return _COURSES_CACHE
    except Exception as e:
        logger.error(f"Failed to load CK-12 catalog: {e}")
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
        logger.error(f"Failed to load CK-12 catalog metadata: {e}")
        return {}


def _reset_catalog_cache() -> None:
    """Reset the catalog cache. Mainly for testing."""
    global _COURSES_CACHE
    _COURSES_CACHE = None


# Subject categories
CK12_SUBJECTS = [
    "Mathematics",
    "Science",
    "English Language Arts",
    "Social Studies",
    "Health",
]

# Grade levels
CK12_GRADE_LEVELS = [
    "elementary",  # K-5
    "middle-school",  # 6-8
    "high-school",  # 9-12
]


# =============================================================================
# CK-12 FlexBook Source Handler
# =============================================================================

@SourceRegistry.register
class CK12FlexBookHandler(CurriculumSourceHandler):
    """
    CK-12 FlexBook source handler.

    Provides:
    - Course catalog browsing (FlexBooks for K-12)
    - Course detail retrieval
    - Content downloading (EPUB/PDF)
    - License validation (CC-BY-NC 3.0)

    Two-Stage Approach:
    - Stage 1: get_course_catalog() - returns lightweight metadata for UI browsing
    - Stage 2: get_course_detail() + download_course() - full content retrieval
    """

    # CK-12 base URLs
    BASE_URL = "https://www.ck12.org"
    FLEXBOOK_URL = "https://www.ck12.org/fbbrowse/"
    API_URL = "https://www.ck12.org/apis"

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
            "practice": ("practice", data.get("practice_count")),
            "quizzes": ("quizzes", data.get("quiz_count")),
            "videos": ("videos", data.get("video_count")),
            "simulations": ("simulations", data.get("simulation_count")),
        }

        for feature_name in data.get("features", []):
            if feature_name in feature_map:
                ftype, count = feature_map[feature_name]
                features.append(CourseFeature(type=ftype, count=count, available=True))

        # Add default features
        features.append(CourseFeature(type="epub", count=1, available=True))
        features.append(CourseFeature(type="pdf", count=1, available=True))

        return CourseCatalogEntry(
            id=data["id"],
            source_id="ck12_flexbook",
            title=data["title"],
            instructors=data.get("authors", ["CK-12 Foundation"]),
            description=data.get("description", ""),
            level=data.get("level", "middle-school"),
            department=data.get("subject"),
            semester=None,  # CK-12 doesn't use semesters
            features=features,
            license=CK12_LICENSE,
            keywords=data.get("keywords", []),
            thumbnail_url=data.get("thumbnail_url"),
        )

    # =========================================================================
    # Properties
    # =========================================================================

    @property
    def source_id(self) -> str:
        return "ck12_flexbook"

    @property
    def source_info(self) -> CurriculumSource:
        return CurriculumSource(
            id="ck12_flexbook",
            name="CK-12 FlexBooks",
            description=(
                "Free, high-quality K-12 educational content from CK-12 Foundation. "
                "Comprehensive coverage of Math, Science, ELA, and Social Studies. "
                "Standards-aligned to Common Core and NGSS."
            ),
            logo_url="/images/sources/ck12-logo.png",
            license=CK12_LICENSE,
            course_count="100+",
            features=["epub", "pdf", "lessons", "practice", "quizzes", "videos"],
            status="active",
            base_url=self.BASE_URL,
        )

    @property
    def default_license(self) -> LicenseInfo:
        return CK12_LICENSE

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

        Args:
            page: Page number (1-indexed)
            page_size: Items per page
            filters: Optional filter criteria
            search: Optional search query

        Returns:
            Tuple of (entries, total_count, filter_options)
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
                or any(search_lower in i.lower() for i in c.instructors)
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

        # Apply features filter
        if filters.get("features"):
            required_features = set(filters["features"])
            courses = [
                c for c in courses
                if required_features.issubset({f.type for f in c.features if f.available})
            ]

        # Get total count before pagination
        total = len(courses)

        # Apply pagination
        start = (page - 1) * page_size
        end = start + page_size
        courses = courses[start:end]

        # Get available filter options
        all_courses = list(self._catalog_cache.values())
        filter_options = {
            "subjects": sorted(set(c.department for c in all_courses if c.department)),
            "levels": ["elementary", "middle-school", "high-school"],
            "grades": ["K", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"],
            "features": ["epub", "pdf", "lessons", "practice", "quizzes", "videos", "simulations"],
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

        Stage 2 of two-stage approach - may make network requests
        to fetch additional metadata.

        Args:
            course_id: Course identifier

        Returns:
            CourseDetail with full information
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

        # Build lessons list from chapters/lessons
        lessons = []
        chapters = raw_data.get("chapters", [])
        lesson_number = 1
        for chapter in chapters:
            for lesson in chapter.get("lessons", []):
                lessons.append(LectureInfo(
                    id=f"lesson-{lesson_number}",
                    number=lesson_number,
                    title=f"{chapter.get('title', 'Chapter')}: {lesson.get('title', 'Lesson')}",
                    has_video=lesson.get("has_video", False),
                    has_transcript=lesson.get("has_transcript", False),
                    has_notes=True,  # FlexBooks always have written content
                ))
                lesson_number += 1

        # If no chapters in catalog, try to fetch from source
        if not lessons:
            lessons = await self._fetch_lesson_structure(course_id, raw_data.get("url"))

        # Build assignments from practice problems
        assignments = []
        if raw_data.get("practice_count", 0) > 0:
            for i in range(min(raw_data.get("practice_count", 5), 10)):
                assignments.append(AssignmentInfo(
                    id=f"practice-{i + 1}",
                    title=f"Practice Set {i + 1}",
                    has_solutions=True,
                ))

        # Build exams from quizzes
        exams = []
        if raw_data.get("quiz_count", 0) > 0:
            for i in range(min(raw_data.get("quiz_count", 2), 5)):
                exams.append(ExamInfo(
                    id=f"quiz-{i + 1}",
                    title=f"Quiz {i + 1}",
                    exam_type="quiz",
                    has_solutions=True,
                ))

        # Build standards alignment
        standards = raw_data.get("standards", [])
        prerequisites = raw_data.get("prerequisites", [])
        syllabus = self._build_syllabus(chapters, raw_data)

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
            lectures=lessons,
            assignments=assignments,
            exams=exams,
            estimated_import_time=self._estimate_import_time(len(lessons)),
            estimated_output_size=self._estimate_output_size(len(lessons)),
            download_url=raw_data.get("download_url") or raw_data.get("url"),
        )

    async def _fetch_lesson_structure(
        self,
        course_id: str,
        course_url: Optional[str]
    ) -> List[LectureInfo]:
        """
        Fetch lesson structure from CK-12 website.

        Makes network request to get actual chapter/lesson titles.
        """
        if not course_url:
            return []

        lessons = []
        session = await self._get_session()

        try:
            async with session.get(course_url, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                if resp.status != 200:
                    logger.warning(f"CK-12 course page returned {resp.status}")
                    return lessons

                html = await resp.text()
                soup = BeautifulSoup(html, "html.parser")

                # Find chapter/lesson structure in the page
                # CK-12 uses various class names for TOC
                toc_container = soup.find("div", class_=re.compile(r"toc|contents|chapters"))

                if toc_container:
                    lesson_number = 1
                    for link in toc_container.find_all("a", href=True):
                        title = link.get_text(strip=True)
                        if title and len(title) > 2:  # Skip empty/short links
                            lessons.append(LectureInfo(
                                id=f"lesson-{lesson_number}",
                                number=lesson_number,
                                title=title,
                                has_video=False,
                                has_transcript=False,
                                has_notes=True,
                            ))
                            lesson_number += 1

                logger.info(f"Fetched {len(lessons)} lessons from {course_url}")

        except asyncio.TimeoutError:
            logger.warning(f"Timeout fetching lessons from {course_url}")
        except Exception as e:
            logger.warning(f"Error fetching lessons: {e}")

        return lessons

    def _build_syllabus(self, chapters: List[Dict], raw_data: Dict) -> str:
        """Build syllabus text from chapter structure."""
        if not chapters:
            return raw_data.get("description", "")

        lines = []
        for i, chapter in enumerate(chapters, 1):
            lines.append(f"Chapter {i}: {chapter.get('title', 'Untitled')}")
            for lesson in chapter.get("lessons", []):
                lines.append(f"  - {lesson.get('title', 'Lesson')}")

        return "\n".join(lines)

    def _estimate_import_time(self, lesson_count: int) -> str:
        """Estimate import time based on lesson count."""
        if lesson_count <= 5:
            return "2-3 minutes"
        elif lesson_count <= 15:
            return "5-10 minutes"
        elif lesson_count <= 30:
            return "10-15 minutes"
        else:
            return "15-25 minutes"

    def _estimate_output_size(self, lesson_count: int) -> str:
        """Estimate output size based on lesson count."""
        if lesson_count <= 5:
            return "1-5 MB"
        elif lesson_count <= 15:
            return "5-15 MB"
        elif lesson_count <= 30:
            return "15-30 MB"
        else:
            return "30-50 MB"

    # =========================================================================
    # Download Methods
    # =========================================================================

    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]] = None,
        selected_lessons: Optional[List[str]] = None,
    ) -> Path:
        """
        Download course content to local directory.

        Downloads the EPUB package from CK-12, extracts it, and parses
        the content to create structured output.

        Args:
            course_id: Course identifier
            output_dir: Directory to save content
            progress_callback: Optional callback for progress updates
            selected_lessons: Optional list of lesson IDs to download
        """
        # Validate license first
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        entry = self._catalog_cache.get(course_id)
        if not entry:
            raise ValueError(f"Course not found: {course_id}")

        raw_data = self._raw_data_cache.get(course_id)
        course_url = raw_data.get("url") if raw_data else None
        download_url = raw_data.get("download_url") if raw_data else None

        if not course_url and not download_url:
            raise ValueError(f"No URL for course: {course_id}")

        # Create output directory
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        course_output_dir = output_dir / course_id
        course_output_dir.mkdir(parents=True, exist_ok=True)

        if progress_callback:
            progress_callback(5, "Validating course...")

        session = await self._get_session()

        if progress_callback:
            progress_callback(10, "Fetching course page...")

        # Step 1: Get course page to find download links
        epub_url = await self._find_epub_download_url(session, course_url, download_url)

        if progress_callback:
            progress_callback(20, "Downloading EPUB...")

        # Step 2: Download EPUB
        content_data = {}
        if epub_url:
            try:
                epub_path = await self._download_epub(
                    session, epub_url, course_output_dir, progress_callback
                )
                if progress_callback:
                    progress_callback(60, "Parsing EPUB content...")

                # Step 3: Parse EPUB
                content_data = await self._parse_epub(epub_path, selected_lessons)

            except Exception as e:
                logger.warning(f"EPUB download/parse failed: {e}")
                if progress_callback:
                    progress_callback(65, "EPUB failed, trying HTML fallback...")

                # Fallback to HTML scraping
                content_data = await self._scrape_html_content(
                    session, course_url, selected_lessons, progress_callback
                )
        else:
            if progress_callback:
                progress_callback(25, "No EPUB available, fetching HTML content...")

            content_data = await self._scrape_html_content(
                session, course_url, selected_lessons, progress_callback
            )

        if progress_callback:
            progress_callback(90, "Saving course metadata...")

        # Step 4: Save comprehensive metadata
        metadata = {
            "source": "ck12_flexbook",
            "course_id": course_id,
            "title": entry.title,
            "description": entry.description,
            "authors": entry.instructors,
            "subject": entry.department,
            "level": entry.level,
            "course_url": course_url,
            "license": CK12_LICENSE.to_dict(),
            "attribution": self.get_attribution_text(course_id, entry.title),
            "content": content_data,
            "selected_lessons": selected_lessons,
            "standards": raw_data.get("standards", []) if raw_data else [],
        }

        metadata_path = course_output_dir / "course_metadata.json"
        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        if progress_callback:
            progress_callback(100, "Download complete")

        logger.info(f"Downloaded course {course_id} to {course_output_dir}")
        return course_output_dir

    async def _find_epub_download_url(
        self,
        session: aiohttp.ClientSession,
        course_url: Optional[str],
        download_url: Optional[str],
    ) -> Optional[str]:
        """Find the EPUB download URL for a course."""
        # If we have a direct download URL, use it
        if download_url and download_url.endswith(".epub"):
            return download_url

        if not course_url:
            return None

        try:
            async with session.get(course_url, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                if resp.status != 200:
                    return None

                html = await resp.text()
                soup = BeautifulSoup(html, "html.parser")

                # Look for EPUB download link
                for link in soup.find_all("a", href=True):
                    href = link.get("href", "")
                    text = link.get_text(strip=True).lower()

                    if href.endswith(".epub") or "epub" in text:
                        return urljoin(course_url, href)

                    # CK-12 download buttons
                    if "download" in text and ("book" in text or "epub" in text):
                        return urljoin(course_url, href)

        except Exception as e:
            logger.warning(f"Error finding EPUB URL: {e}")

        return None

    async def _download_epub(
        self,
        session: aiohttp.ClientSession,
        epub_url: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]] = None,
    ) -> Path:
        """Download EPUB file from URL."""
        logger.info(f"Downloading EPUB from {epub_url}")

        async with session.get(epub_url) as resp:
            if resp.status != 200:
                raise ValueError(f"EPUB download failed with status {resp.status}")

            total_size = int(resp.headers.get("content-length", 0))
            downloaded = 0
            chunks = []

            async for chunk in resp.content.iter_chunked(8192):
                chunks.append(chunk)
                downloaded += len(chunk)
                if progress_callback and total_size:
                    pct = 20 + (downloaded / total_size) * 35
                    progress_callback(pct, f"Downloading... {downloaded // 1024}KB")

            epub_data = b"".join(chunks)

        epub_path = output_dir / "flexbook.epub"
        with open(epub_path, "wb") as f:
            f.write(epub_data)

        logger.info(f"Saved EPUB to {epub_path}")
        return epub_path

    async def _parse_epub(
        self,
        epub_path: Path,
        selected_lessons: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """Parse EPUB file and extract structured content."""
        content = {
            "format": "epub",
            "lessons": [],
            "glossary": [],
            "metadata": {},
        }

        try:
            with zipfile.ZipFile(epub_path, "r") as zf:
                namelist = zf.namelist()

                # Find and parse OPF manifest
                opf_path = None
                for name in namelist:
                    if name.endswith(".opf"):
                        opf_path = name
                        break

                if opf_path:
                    opf_content = zf.read(opf_path).decode("utf-8")
                    content["metadata"] = self._parse_opf_metadata(opf_content)

                # Find content files
                html_files = [n for n in namelist if n.endswith((".html", ".xhtml", ".htm"))]

                # Parse each content file
                lesson_number = 1
                for html_file in html_files:
                    try:
                        html_content = zf.read(html_file).decode("utf-8")
                        lesson_data = self._parse_lesson_html(html_content, html_file)

                        if lesson_data.get("text"):
                            lesson_id = f"lesson-{lesson_number}"

                            # Skip if not in selected lessons
                            if selected_lessons and lesson_id not in selected_lessons:
                                continue

                            lesson_data["id"] = lesson_id
                            lesson_data["number"] = lesson_number
                            content["lessons"].append(lesson_data)
                            lesson_number += 1

                    except Exception as e:
                        logger.warning(f"Failed to parse {html_file}: {e}")

        except zipfile.BadZipFile:
            logger.error(f"Invalid EPUB file: {epub_path}")
            raise ValueError("Invalid EPUB file")

        return content

    def _parse_opf_metadata(self, opf_content: str) -> Dict[str, Any]:
        """Parse OPF manifest for metadata."""
        metadata = {}

        try:
            # Remove namespace prefixes for easier parsing
            opf_content = re.sub(r'xmlns[^=]*="[^"]*"', '', opf_content)

            root = ET.fromstring(opf_content)

            # Find metadata element
            meta_elem = root.find(".//metadata")
            if meta_elem is None:
                meta_elem = root

            # Extract Dublin Core elements
            dc_elements = {
                "title": "title",
                "creator": "creator",
                "publisher": "publisher",
                "description": "description",
                "subject": "subject",
                "language": "language",
                "identifier": "identifier",
                "rights": "rights",
            }

            for key, tag in dc_elements.items():
                elem = meta_elem.find(f".//{tag}")
                if elem is not None and elem.text:
                    metadata[key] = elem.text.strip()

        except Exception as e:
            logger.warning(f"Failed to parse OPF metadata: {e}")

        return metadata

    def _parse_lesson_html(self, html_content: str, filename: str) -> Dict[str, Any]:
        """Parse lesson HTML content."""
        soup = BeautifulSoup(html_content, "html.parser")

        # Extract title
        title_elem = soup.find(["h1", "h2", "title"])
        title = title_elem.get_text(strip=True) if title_elem else Path(filename).stem

        # Extract main content
        main_content = soup.find(["main", "article", "body", "div"])
        if main_content:
            # Remove scripts and styles
            for elem in main_content.find_all(["script", "style", "nav", "header", "footer"]):
                elem.decompose()

            text = main_content.get_text(separator="\n", strip=True)
        else:
            text = ""

        # Extract vocabulary terms
        vocabulary = []
        for dfn in soup.find_all(["dfn", "strong"]):
            term = dfn.get_text(strip=True)
            if len(term) > 2 and len(term) < 50:
                vocabulary.append(term)

        # Extract practice problems
        problems = []
        for problem in soup.find_all(class_=re.compile(r"problem|question|exercise")):
            problem_text = problem.get_text(strip=True)
            if problem_text:
                problems.append(problem_text)

        return {
            "title": title,
            "text": text,
            "vocabulary": vocabulary[:10],  # Limit vocabulary
            "problems": problems[:5],  # Limit problems
            "source_file": filename,
        }

    async def _scrape_html_content(
        self,
        session: aiohttp.ClientSession,
        course_url: Optional[str],
        selected_lessons: Optional[List[str]],
        progress_callback: Optional[Callable[[float, str], None]] = None,
    ) -> Dict[str, Any]:
        """Fallback: Scrape HTML content from CK-12 website."""
        content = {
            "format": "html",
            "lessons": [],
            "metadata": {},
        }

        if not course_url:
            return content

        try:
            async with session.get(course_url, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                if resp.status != 200:
                    return content

                html = await resp.text()
                soup = BeautifulSoup(html, "html.parser")

                # Extract metadata
                title_elem = soup.find("title")
                if title_elem:
                    content["metadata"]["title"] = title_elem.get_text(strip=True)

                # Find lesson links
                lesson_links = []
                for link in soup.find_all("a", href=True):
                    href = link.get("href", "")
                    text = link.get_text(strip=True)
                    if "/lesson/" in href or "/section/" in href:
                        lesson_links.append({
                            "url": urljoin(course_url, href),
                            "title": text,
                        })

                # Fetch lesson content (limit to avoid rate limiting)
                lesson_number = 1
                for i, lesson_link in enumerate(lesson_links[:20]):
                    lesson_id = f"lesson-{lesson_number}"

                    # Skip if not in selected lessons
                    if selected_lessons and lesson_id not in selected_lessons:
                        continue

                    if progress_callback:
                        pct = 25 + (i / len(lesson_links)) * 50
                        progress_callback(pct, f"Fetching lesson {lesson_number}...")

                    try:
                        async with session.get(
                            lesson_link["url"],
                            timeout=aiohttp.ClientTimeout(total=10)
                        ) as lesson_resp:
                            if lesson_resp.status == 200:
                                lesson_html = await lesson_resp.text()
                                lesson_data = self._parse_lesson_html(
                                    lesson_html, lesson_link["title"]
                                )
                                lesson_data["id"] = lesson_id
                                lesson_data["number"] = lesson_number
                                lesson_data["title"] = lesson_link["title"]
                                content["lessons"].append(lesson_data)
                                lesson_number += 1

                        # Rate limiting
                        await asyncio.sleep(0.5)

                    except Exception as e:
                        logger.warning(f"Failed to fetch lesson: {e}")

        except Exception as e:
            logger.warning(f"HTML scraping failed: {e}")

        return content

    async def get_download_size(self, course_id: str) -> str:
        """Estimate download size for a course."""
        entry = self._catalog_cache.get(course_id)
        if not entry:
            return "Unknown"

        # Estimate based on features
        lesson_count = 0
        for feature in entry.features:
            if feature.type == "lessons" and feature.count:
                lesson_count = feature.count
                break

        return self._estimate_output_size(lesson_count or 10)

    # =========================================================================
    # License Methods (CRITICAL)
    # =========================================================================

    def validate_license(self, course_id: str) -> LicenseValidationResult:
        """
        Validate that a course can be imported.

        All CK-12 FlexBook content is CC-BY-NC 3.0, so all courses can be imported
        as long as attribution is preserved and use is non-commercial.
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
            license=CK12_LICENSE,
            warnings=["Non-commercial use only"],
            attribution_text=self.get_attribution_text(course_id, entry.title),
        )

    def get_attribution_text(self, course_id: str, course_title: str) -> str:
        """Generate attribution text for a course."""
        return (
            f'This content is derived from CK-12 Foundation (www.ck12.org). '
            f'Original FlexBook: "{course_title}". '
            f'Licensed under Creative Commons Attribution-NonCommercial 3.0 Unported (CC-BY-NC 3.0). '
            f'Copyright CK-12 Foundation.'
        )

    # =========================================================================
    # Session Management
    # =========================================================================

    async def _get_session(self) -> aiohttp.ClientSession:
        """Get or create HTTP session."""
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                headers={
                    "User-Agent": "UnaMentis-Curriculum-Importer/1.0 (Educational Use)",
                }
            )
        return self._session

    async def close(self):
        """Close HTTP session."""
        if self._session and not self._session.closed:
            await self._session.close()
