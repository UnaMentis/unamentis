"""
MIT OpenCourseWare source handler.

Provides course catalog browsing and content downloading from MIT OCW.
All content is licensed under CC-BY-NC-SA 4.0.

Reference: https://ocw.mit.edu/

Course catalog is loaded from: data/mit_ocw_catalog.json
This file contains 247 courses with full metadata, URLs, and keywords.

Download Strategy:
- MIT OCW provides ZIP packages at {course_url}/download/ containing all
  non-video materials (HTML, PDFs, images)
- Videos must be downloaded separately if needed
- We parse the downloaded HTML to extract lecture structure and content
"""

__version__ = "1.0.0"
__author__ = "UnaMentis Team"
__url__ = "https://ocw.mit.edu/"

import asyncio
import io
import json
import logging
import re
import subprocess
import zipfile
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple
from urllib.parse import urljoin

import aiohttp
from bs4 import BeautifulSoup

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
# MIT OCW License (applies to all content)
# =============================================================================

MIT_OCW_LICENSE = LicenseInfo(
    type="CC-BY-NC-SA-4.0",
    name="Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International",
    url="https://creativecommons.org/licenses/by-nc-sa/4.0/",
    permissions=["share", "adapt"],
    conditions=["attribution", "noncommercial", "sharealike"],
    attribution_required=True,
    attribution_format=(
        "Content from MIT OpenCourseWare (ocw.mit.edu), "
        "licensed under CC-BY-NC-SA 4.0."
    ),
    holder_name="Massachusetts Institute of Technology",
    holder_url="https://ocw.mit.edu/",
    restrictions=[],
)


# =============================================================================
# MIT OCW Course Catalog
# =============================================================================

# Path to the comprehensive course catalog JSON file
# This catalog contains 247 courses with full metadata, URLs, and keywords
# Note: Goes up 3 levels from plugins/sources/ to importers/ to reach data/
CATALOG_FILE = Path(__file__).parent.parent.parent / "data" / "mit_ocw_catalog.json"

# In-memory cache of courses loaded from JSON
_COURSES_CACHE: Optional[List[Dict[str, Any]]] = None


def _load_courses_from_catalog() -> List[Dict[str, Any]]:
    """Load courses from the JSON catalog file."""
    global _COURSES_CACHE

    if _COURSES_CACHE is not None:
        return _COURSES_CACHE

    if not CATALOG_FILE.exists():
        logger.warning(f"MIT OCW catalog file not found: {CATALOG_FILE}")
        return []

    try:
        with open(CATALOG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            _COURSES_CACHE = data.get("courses", [])
            logger.info(f"Loaded {len(_COURSES_CACHE)} courses from MIT OCW catalog")
            return _COURSES_CACHE
    except Exception as e:
        logger.error(f"Failed to load MIT OCW catalog: {e}")
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
        logger.error(f"Failed to load MIT OCW catalog metadata: {e}")
        return {}

# Subject/Department categories (loaded from catalog metadata or fallback)
def _get_mit_subjects() -> List[str]:
    """Get list of MIT departments/subjects."""
    metadata = _get_catalog_metadata()
    if metadata.get("departments"):
        return metadata["departments"]
    # Fallback to hardcoded list
    return [
        "Aeronautics and Astronautics",
        "Anthropology",
        "Architecture",
        "Biological Engineering",
        "Biology",
        "Brain and Cognitive Sciences",
        "Chemical Engineering",
        "Chemistry",
        "Civil and Environmental Engineering",
        "Comparative Media Studies",
        "Earth, Atmospheric, and Planetary Sciences",
        "Economics",
        "Electrical Engineering and Computer Science",
        "Engineering Systems Division",
        "Health Sciences and Technology",
        "History",
        "Linguistics and Philosophy",
        "Literature",
        "Materials Science and Engineering",
        "Mathematics",
        "Mechanical Engineering",
        "Media Arts and Sciences",
        "Music and Theater Arts",
        "Nuclear Science and Engineering",
        "Physics",
        "Political Science",
        "Science, Technology, and Society",
        "Sloan School of Management",
        "Urban Studies and Planning",
        "Writing and Humanistic Studies",
    ]


# =============================================================================
# MIT OCW Source Handler
# =============================================================================

@SourceRegistry.register
class MITOCWHandler(CurriculumSourceHandler):
    """
    MIT OpenCourseWare source handler.

    Provides:
    - Course catalog browsing (2,500+ courses)
    - Course detail retrieval
    - Content downloading (ZIP packages)
    - License validation (CC-BY-NC-SA 4.0)
    """

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
        feature_map = {
            "video": ("video", data.get("lecture_count")),
            "transcript": ("transcript", data.get("lecture_count")),
            "lecture_notes": ("lecture_notes", data.get("lecture_count")),
            "assignments": ("assignments", None),
            "exams": ("exams", None),
        }

        for feature_name in data.get("features", []):
            if feature_name in feature_map:
                ftype, count = feature_map[feature_name]
                features.append(CourseFeature(type=ftype, count=count, available=True))

        return CourseCatalogEntry(
            id=data["id"],
            source_id="mit_ocw",
            title=data["title"],
            instructors=data["instructors"],
            description=data["description"],
            level=data.get("level", "intermediate"),
            department=data.get("department"),
            semester=data.get("semester"),
            features=features,
            license=MIT_OCW_LICENSE,
            keywords=data.get("keywords", []),
        )

    # =========================================================================
    # Properties
    # =========================================================================

    @property
    def source_id(self) -> str:
        return "mit_ocw"

    @property
    def source_info(self) -> CurriculumSource:
        return CurriculumSource(
            id="mit_ocw",
            name="MIT OpenCourseWare",
            description="Free course materials from over 2,500 MIT courses",
            logo_url="/images/sources/mit-ocw-logo.png",
            license=MIT_OCW_LICENSE,
            course_count="2,500+",
            features=["video", "transcript", "lecture_notes", "assignments", "exams"],
            status="active",
            base_url="https://ocw.mit.edu/",
        )

    @property
    def default_license(self) -> LicenseInfo:
        return MIT_OCW_LICENSE

    # =========================================================================
    # Catalog Methods
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
            "levels": ["introductory", "intermediate", "advanced"],
            "features": ["video", "transcript", "lecture_notes", "assignments", "exams"],
        }

        return courses, total, filter_options

    async def get_course_detail(self, course_id: str) -> CourseDetail:
        """Get full details for a specific course."""
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

        # Course features
        has_video = "video" in raw_data.get("features", [])
        has_transcript = "transcript" in raw_data.get("features", [])
        has_notes = "lecture_notes" in raw_data.get("features", [])
        course_url = raw_data.get("url", "")

        # Try to fetch actual lecture titles from the course pages
        lectures = []
        if course_url:
            fetched_lectures = await self._fetch_lecture_titles(course_url)
            if fetched_lectures:
                for lec in fetched_lectures:
                    lectures.append(LectureInfo(
                        id=lec["id"],
                        number=lec["number"],
                        title=lec["title"],
                        has_video=has_video,
                        has_transcript=has_transcript,
                        has_notes=has_notes,
                        video_url=lec.get("url"),
                    ))

        # Fallback to generic titles if fetch failed
        if not lectures:
            lecture_count = raw_data.get("lecture_count", 0)
            for i in range(1, lecture_count + 1):
                video_url = None
                if has_video and course_url:
                    base_url = course_url if course_url.endswith("/") else f"{course_url}/"
                    video_url = f"{base_url}video-lectures/lecture-{i}/"

                lectures.append(LectureInfo(
                    id=f"lecture-{i}",
                    number=i,
                    title=f"Lecture {i}",
                    has_video=has_video,
                    has_transcript=has_transcript,
                    has_notes=has_notes,
                    video_url=video_url,
                ))

        # Generate assignments/exams (placeholder)
        assignments = []
        if "assignments" in raw_data.get("features", []):
            for i in range(1, 6):  # Assume ~5 assignments
                assignments.append(AssignmentInfo(
                    id=f"assignment-{i}",
                    title=f"Problem Set {i}",
                    has_solutions=True,
                ))

        exams = []
        if "exams" in raw_data.get("features", []):
            exams = [
                ExamInfo(id="midterm", title="Midterm Exam", exam_type="midterm", has_solutions=True),
                ExamInfo(id="final", title="Final Exam", exam_type="final", has_solutions=True),
            ]

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
            syllabus=f"This course covers {entry.description}",  # Placeholder
            prerequisites=[],
            lectures=lectures,
            assignments=assignments,
            exams=exams,
            estimated_import_time="10-15 minutes",
            estimated_output_size="2-5 MB",
            download_url=raw_data.get("url"),
        )

    async def get_normalized_course_detail(self, course_id: str) -> NormalizedCourseDetail:
        """
        Get normalized course detail for generic plugin UI.

        MIT OCW uses a flat lecture structure:
        - unitLabel: "Lecture"
        - topicLabel: "Lecture"
        - isFlat: True (single unit containing all lectures)
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

        # Course features
        has_video = "video" in raw_data.get("features", [])
        has_transcript = "transcript" in raw_data.get("features", [])
        course_url = raw_data.get("url", "")

        # Try to fetch actual lecture titles from the course pages
        topics = []
        if course_url:
            fetched_lectures = await self._fetch_lecture_titles(course_url)
            if fetched_lectures:
                for lec in fetched_lectures:
                    topics.append(ContentTopic(
                        id=lec["id"],
                        title=lec["title"],
                        number=lec["number"],
                        has_video=has_video,
                        has_transcript=has_transcript,
                        has_practice=False,
                    ))

        if not topics:
            lecture_count = raw_data.get("lecture_count", 0)
            for i in range(1, lecture_count + 1):
                topics.append(ContentTopic(
                    id=f"lecture-{i}",
                    title=f"Lecture {i}",
                    number=i,
                    has_video=has_video,
                    has_transcript=has_transcript,
                    has_practice=False,
                ))

        # Group topics into units if they have section data
        units = []
        if topics:
            # Check if we have section data
            has_sections = any(hasattr(t, 'section') and t.section for t in topics if hasattr(t, 'section'))
            
            # If fetch_lecture_titles added 'section' to the dicts, we need to access it
            # But here topics contains ContentTopic objects which might not have 'section'
            # We need to preserve the section info when creating ContentTopic or map it differently.
            
            # Let's re-build topics from fetched_lectures to include section info if available
            grouped_lectures = {}
            if course_url and fetched_lectures:
                for lec in fetched_lectures:
                    section = lec.get("section", "General")
                    if section not in grouped_lectures:
                        grouped_lectures[section] = []
                    
                    grouped_lectures[section].append(ContentTopic(
                        id=lec["id"],
                        title=lec["title"],
                        number=lec["number"],
                        has_video=has_video,
                        has_transcript=has_transcript,
                        # Store section title for reference if needed, though mostly for grouping
                    ))
                
                # Create units from groups
                unit_num = 1
                for section_title, unit_topics in grouped_lectures.items():
                    # clean up section title (week-1-kinematics -> Week 1: Kinematics)
                    display_title = section_title.replace("-", " ").title()
                    # Fix "Week 1" spacing
                    display_title = re.sub(r"Week (\d)", r"Week \1:", display_title)
                    
                    units.append(ContentUnit(
                        id=f"unit-{unit_num}",
                        title=display_title,
                        number=unit_num,
                        topics=unit_topics
                    ))
                    unit_num += 1
            
            # Fallback to flat structure if no grouping
            if not units:
                units.append(ContentUnit(
                    id="all-lectures",
                    title="All Lectures",
                    number=1,
                    topics=topics,
                ))

        # Build content structure with MIT OCW terminology
        is_hierarchical = len(units) > 1
        content_structure = ContentStructure(
            unit_label="Week" if is_hierarchical else "Lecture",
            topic_label="Lecture",
            is_flat=not is_hierarchical,
            units=units,
        )

        # Level labels
        level_labels = {
            "introductory": "Introductory",
            "intermediate": "Intermediate",
            "advanced": "Advanced",
        }
        level_label = level_labels.get(entry.level, entry.level.title())

        # Generate assignments/exams (placeholder)
        assignments = []
        if "assignments" in raw_data.get("features", []):
            for i in range(1, 6):  # Assume ~5 assignments
                assignments.append(AssignmentInfo(
                    id=f"assignment-{i}",
                    title=f"Problem Set {i}",
                    has_solutions=True,
                ))

        exams = []
        if "exams" in raw_data.get("features", []):
            exams = [
                ExamInfo(id="midterm", title="Midterm Exam", exam_type="midterm", has_solutions=True),
                ExamInfo(id="final", title="Final Exam", exam_type="final", has_solutions=True),
            ]

        return NormalizedCourseDetail(
            id=entry.id,
            source_id=entry.source_id,
            title=entry.title,
            description=entry.description,
            instructors=entry.instructors,
            level=entry.level,
            level_label=level_label,
            department=entry.department,
            semester=entry.semester,
            keywords=entry.keywords,
            thumbnail_url=None,
            license=entry.license,
            features=entry.features,
            content_structure=content_structure,
            assignments=assignments,
            exams=exams,
            syllabus=f"This course covers {entry.description}",
            prerequisites=[],
            estimated_import_time="10-15 minutes",
            estimated_output_size="2-5 MB",
            source_url=raw_data.get("url"),
            download_url=raw_data.get("url"),
        )

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
    # Lecture Title Fetching
    # =========================================================================

    async def _fetch_lecture_titles(self, course_url: str) -> List[Dict[str, Any]]:
        """
        Fetch actual lecture titles from MIT OCW course pages.

        Parses the course pages list to extract lecture structure and titles.
        Returns a list of dicts with id, number, title, url, week info.
        """
        lectures = []
        session = await self._get_session()

        try:
            # Try the pages index first
            pages_url = course_url.rstrip("/") + "/pages/"
            async with session.get(pages_url, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                if resp.status != 200:
                    logger.warning(f"Pages index returned {resp.status}")
                    return lectures

                html = await resp.text()
                soup = BeautifulSoup(html, "html.parser")

                # Find all lecture/lesson links
                # Pattern: /pages/week-X-topic/X-Y-lecture-title/
                lecture_pattern = re.compile(r"/pages/([^/]+)/(\d+)-(\d+)-([^/]+)/?$")
                seen_ids = set()

                for link in soup.find_all("a", href=True):
                    href = link.get("href", "")
                    match = lecture_pattern.search(href)
                    if match:
                        section_slug = match.group(1)
                        lesson_num = match.group(2)
                        sub_num = match.group(3)
                        slug = match.group(4)

                        lecture_id = f"lecture-{lesson_num}-{sub_num}"

                        # Skip duplicates
                        if lecture_id in seen_ids:
                            continue
                        seen_ids.add(lecture_id)

                        # Convert slug to title
                        title = slug.replace("-", " ").title()
                        title = re.sub(r"\s+", " ", title)
                        title = re.sub(r"\b1d\b", "1D", title, flags=re.I)
                        title = re.sub(r"\b2d\b", "2D", title, flags=re.I)
                        title = re.sub(r"\b3d\b", "3D", title, flags=re.I)

                        full_url = urljoin(course_url, href)

                        lectures.append({
                            "id": lecture_id,
                            "number": int(lesson_num),
                            "sub_number": int(sub_num),
                            "title": f"{lesson_num}.{sub_num} {title}",
                            "url": full_url,
                            "slug": slug,
                            "section": section_slug,
                        })

                # Strategy 2: Check /video_galleries/video-lectures/ (Legacy/Standard courses like SICP)
                if not lectures:
                    try:
                        gallery_url = course_url.rstrip("/") + "/video_galleries/video-lectures/"
                        async with session.get(gallery_url, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                            if resp.status == 200:
                                html = await resp.text()
                                soup = BeautifulSoup(html, "html.parser")
                                logger.info(f"Scanning video gallery at {gallery_url}")

                                resource_pattern = re.compile(r"/resources/([^/]+)/?$")
                                seen_ids = set()
                                
                                for link in soup.find_all("a", href=True):
                                    href = link.get("href", "")
                                    match = resource_pattern.search(href)
                                    if match and course_url.split("/courses/")[1].rstrip("/") in href:
                                        slug = match.group(1)
                                        
                                        num_match = re.match(r"^(\d+[a-z]?)-", slug)
                                        if num_match:
                                            lecture_id = f"lecture-{num_match.group(1)}"
                                        else:
                                            lecture_id = f"lecture-{slug}"

                                        if lecture_id in seen_ids:
                                            continue
                                        seen_ids.add(lecture_id)

                                        title = link.get_text(strip=True)
                                        if not title:
                                            title = slug.replace("-", " ").title()

                                        full_url = urljoin(gallery_url, href)

                                        lectures.append({
                                            "id": lecture_id,
                                            "number": len(lectures) + 1,
                                            "title": title,
                                            "url": full_url,
                                            "slug": slug,
                                            "section": "Video Lectures"
                                        })
                    except Exception as e:
                        logger.warning(f"Error checking video gallery: {e}")

                # Strategy 3: Check /pages/lecture-notes/ (or calendar, reading) for table-based listing
                # Many courses like 24.09 list lectures in a table on these pages
                if not lectures:
                    try:
                        # Potential pages that might list lectures
                        pages_subpaths = ["/pages/lecture-notes/", "/pages/calendar/", "/pages/readings/", "/pages/syllabus/"]
                        
                        for subpath in pages_subpaths:
                            if lectures: break # Stop if found
                            
                            page_url = course_url.rstrip("/") + subpath
                            async with session.get(page_url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                                if resp.status == 200:
                                    html = await resp.text()
                                    soup = BeautifulSoup(html, "html.parser")
                                    
                                    # Scan ALL rows in the document because of malformed HTML
                                    # (MIT OCW sometimes has <p> tags inside tables breaking them)
                                    all_rows = soup.find_all("tr")
                                    
                                    ses_idx = -1
                                    topic_idx = -1
                                    
                                    for row in all_rows:
                                        # Check if this is a header row
                                        th_cols = row.find_all("th")
                                        if th_cols:
                                            # Normalize headers
                                            raw_headers = [th.get_text(strip=True).upper() for th in th_cols]
                                            headers = [re.sub(r"[^A-Z#]", "", h) for h in raw_headers]
                                            
                                            if any(kw in headers for kw in ["SES#", "LEC#", "SESSION", "LECTURE", "WEEK"]):
                                                # Reset indices for new table/section
                                                ses_idx = -1
                                                topic_idx = -1
                                                
                                                for i, h in enumerate(headers):
                                                    if "TOPIC" in h or "TITLE" in h:
                                                        topic_idx = i
                                                    elif any(kw == h for kw in ["SES#", "LEC#", "SESSION", "LECTURE", "WEEK"]):
                                                        ses_idx = i
                                                
                                                # Fallback logic
                                                if topic_idx == -1 and ses_idx != -1 and len(headers) > ses_idx + 1:
                                                    topic_idx = ses_idx + 1
                                                
                                                if topic_idx != -1:
                                                    logger.info(f"Found lecture headers in {subpath}: {headers}")
                                            continue

                                        # Check if this is a data row and we have valid indices
                                        if topic_idx != -1:
                                            cols = row.find_all(["td", "th"])
                                            
                                            # Validate column count
                                            # Allow for colspan or loose matching? Strict for now.
                                            if len(cols) > topic_idx:
                                                # Extract data
                                                ses_num_str = ""
                                                if ses_idx != -1 and len(cols) > ses_idx:
                                                    ses_num_str = cols[ses_idx].get_text(strip=True)
                                                
                                                # Clean up session number
                                                ses_match = re.search(r"\d+", ses_num_str)
                                                if ses_match:
                                                    ses_num = int(ses_match.group(0))
                                                else:
                                                    continue

                                                title_text = cols[topic_idx].get_text(strip=True)
                                                title_text = title_text.strip('"').strip()
                                                
                                                # Extract PDF
                                                pdf_url = ""
                                                for col in cols:
                                                    link = col.find("a", href=re.compile(r"\.pdf$"))
                                                    if link:
                                                        pdf_url = urljoin(page_url, link["href"])
                                                        break
                                                
                                                if title_text and "exam" not in title_text.lower():
                                                    lecture_id = f"lecture-{ses_num}"
                                                    if any(l["id"] == lecture_id for l in lectures):
                                                        continue

                                                    lectures.append({
                                                        "id": lecture_id,
                                                        "number": ses_num,
                                                        "title": title_text,
                                                        "url": page_url,
                                                        "transcript_url": pdf_url if "transcript" in pdf_url.lower() or "notes" in pdf_url.lower() else "",
                                                        "section": "Lecture Notes"
                                                    })

                                    if lectures:
                                        logger.info(f"Extracted {len(lectures)} lectures from {subpath}")
                                        break

                    except Exception as e:
                        logger.warning(f"Error checking lecture list pages: {e}")

                # If no structured lectures found, try video-lectures pattern
                if not lectures:
                    video_pattern = re.compile(r"/video-lectures/lecture-(\d+)")
                    for link in soup.find_all("a", href=True):
                        href = link.get("href", "")
                        match = video_pattern.search(href)
                        if match:
                            num = int(match.group(1))
                            title = link.get_text(strip=True) or f"Lecture {num}"
                            full_url = urljoin(course_url, href)

                            lectures.append({
                                "id": f"lecture-{num}",
                                "number": num,
                                "title": title,
                                "url": full_url,
                                "section": "Video Lectures"
                            })

                # Sort by number, then sub_number
                lectures.sort(key=lambda x: (x.get("number", 0), x.get("sub_number", 0)))

                logger.info(f"Fetched {len(lectures)} lecture titles from {course_url}")

        except asyncio.TimeoutError:
            logger.warning(f"Timeout fetching lecture titles from {course_url}")
        except Exception as e:
            logger.warning(f"Error fetching lecture titles: {e}")

        return lectures

    async def _fetch_lecture_title_from_page(self, page_url: str) -> Optional[str]:
        """Fetch the actual title from a lecture page."""
        session = await self._get_session()
        try:
            async with session.get(page_url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status != 200:
                    return None
                html = await resp.text()
                soup = BeautifulSoup(html, "html.parser")

                # Try h2 first (usually contains the actual title)
                h2 = soup.find("h2", class_=re.compile(r"pb-1|title"))
                if h2:
                    return h2.get_text(strip=True)

                # Try title tag
                title = soup.find("title")
                if title:
                    text = title.get_text(strip=True)
                    # Strip the " | Course | Department | MIT OpenCourseWare" suffix
                    if "|" in text:
                        text = text.split("|")[0].strip()
                    return text

                return None
        except Exception as e:
            logger.debug(f"Error fetching page title: {e}")
            return None

    async def _fetch_transcript_url(self, lecture_url: str) -> Optional[str]:
        """
        Fetch the transcript PDF URL from a lecture page.

        MIT OCW provides transcripts as PDF files linked from lecture pages.
        """
        session = await self._get_session()
        try:
            async with session.get(lecture_url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status != 200:
                    return None
                html = await resp.text()
                soup = BeautifulSoup(html, "html.parser")

                # Look for transcript download link
                for link in soup.find_all("a", href=True):
                    href = link.get("href", "")
                    text = link.get_text(strip=True).lower()
                    # Transcript links typically contain "transcript" in text and end with .pdf
                    if "transcript" in text and href.endswith(".pdf"):
                        return urljoin(lecture_url, href)

                return None
        except Exception as e:
            logger.debug(f"Error fetching transcript URL: {e}")
            return None

    def _extract_text_from_pdf(self, pdf_path: Path) -> str:
        """
        Extract text from a PDF file using pdftotext.

        Falls back to empty string if extraction fails.
        """
        try:
            # Try multiple paths for pdftotext
            pdftotext_paths = [
                "/opt/homebrew/bin/pdftotext",  # macOS ARM Homebrew
                "/usr/local/bin/pdftotext",     # macOS Intel Homebrew
                "pdftotext",                     # System PATH
            ]

            pdftotext_cmd = None
            for path in pdftotext_paths:
                try:
                    subprocess.run([path, "-v"], capture_output=True, timeout=5)
                    pdftotext_cmd = path
                    break
                except (FileNotFoundError, subprocess.TimeoutExpired):
                    continue

            if not pdftotext_cmd:
                logger.warning("pdftotext not found. Install poppler for PDF extraction.")
                return ""

            result = subprocess.run(
                [pdftotext_cmd, "-layout", str(pdf_path), "-"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode == 0:
                text = result.stdout.strip()
                # Clean up the text
                # Remove excessive whitespace while preserving paragraph breaks
                text = re.sub(r'\n{3,}', '\n\n', text)
                text = re.sub(r'[ \t]+', ' ', text)
                return text
            else:
                logger.warning(f"pdftotext failed for {pdf_path}: {result.stderr}")
                return ""
        except FileNotFoundError:
            logger.warning("pdftotext not found. Install poppler-utils for PDF extraction.")
            return ""
        except subprocess.TimeoutExpired:
            logger.warning(f"PDF extraction timed out for {pdf_path}")
            return ""
        except Exception as e:
            logger.warning(f"Failed to extract text from {pdf_path}: {e}")
            return ""

    async def _fetch_lecture_with_transcript(
        self,
        lecture: Dict[str, Any],
        course_output_dir: Path,
    ) -> Dict[str, Any]:
        """
        Fetch transcript for a single lecture.

        Fetches the transcript PDF URL from the lecture page, finds the
        corresponding PDF in the downloaded content, and extracts text.
        """
        lecture_url = lecture.get("url", "")
        if not lecture_url:
            return lecture

        # Get transcript URL from lecture page
        transcript_url = await self._fetch_transcript_url(lecture_url)
        if transcript_url:
            lecture["transcript_url"] = transcript_url

            # Try to find the PDF in the downloaded content
            # The URL is like: /courses/.../33f61131009a6cd12d9a4c0e42eb7f44_ErlP_SBcA1s.pdf
            # The file is at: static_resources/33f61131009a6cd12d9a4c0e42eb7f44_ErlP_SBcA1s.pdf
            pdf_filename = transcript_url.split("/")[-1]

            # Search for the PDF in the extracted content
            possible_paths = [
                course_output_dir / "static_resources" / pdf_filename,
                course_output_dir / pdf_filename,
            ]

            # Also search recursively in case it's in a subdirectory
            found_pdf_path = None
            for pdf_path in course_output_dir.rglob(pdf_filename):
                found_pdf_path = pdf_path
                break
            
            if not found_pdf_path:
                for path in possible_paths:
                    if path.exists():
                        found_pdf_path = path
                        break
            
            # If not found locally (partial download mode), download it now
            if not found_pdf_path and transcript_url:
                try:
                    download_path = course_output_dir / "static_resources" / pdf_filename
                    download_path.parent.mkdir(parents=True, exist_ok=True)
                    
                    logger.info(f"Downloading transcript PDF from {transcript_url}")
                    async with await self._get_session() as session:
                        async with session.get(transcript_url) as resp:
                            if resp.status == 200:
                                with open(download_path, "wb") as f:
                                    f.write(await resp.read())
                                found_pdf_path = download_path
                            else:
                                logger.warning(f"Failed to download transcript PDF: {resp.status}")
                except Exception as e:
                    logger.warning(f"Error downloading transcript PDF: {e}")

            if found_pdf_path and found_pdf_path.exists():
                logger.info(f"Found transcript PDF: {found_pdf_path}")
                transcript_text = self._extract_text_from_pdf(found_pdf_path)
                if transcript_text:
                    lecture["transcript_text"] = transcript_text
                    logger.info(f"Extracted {len(transcript_text)} chars from {pdf_filename}")
        
        return lecture

    # =========================================================================
    # Download Methods
    # =========================================================================

    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]] = None,
        selected_lectures: Optional[List[str]] = None,
    ) -> Path:
        """
        Download course content to local directory.

        Downloads the ZIP package from MIT OCW, extracts it, and parses
        the HTML to create structured content.

        Args:
            course_id: Course identifier
            output_dir: Directory to save content
            progress_callback: Optional callback for progress updates
            selected_lectures: Optional list of lecture IDs to download
        """
        # Validate license first
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        entry = self._catalog_cache.get(course_id)
        if not entry:
            raise ValueError(f"Course not found: {course_id}")

        # Get course URL from raw data
        raw_data = self._raw_data_cache.get(course_id)
        course_url = raw_data.get("url") if raw_data else None

        if not course_url:
            raise ValueError(f"No URL for course: {course_id}")

        # Create output directory
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        course_output_dir = output_dir / course_id
        course_output_dir.mkdir(parents=True, exist_ok=True)

        if progress_callback:
            progress_callback(5, "Fetching lecture titles...")

        # Step 0: Fetch actual lecture titles from MIT OCW
        fetched_lectures = await self._fetch_lecture_titles(course_url)
        if fetched_lectures:
            logger.info(f"Fetched {len(fetched_lectures)} lecture titles for {course_id}")
        else:
            logger.info(f"No lecture titles fetched, will use generic titles")

        if progress_callback:
            progress_callback(10, "Fetching course page...")

        session = await self._get_session()

        # Step 1: Fetch the main course page to discover content structure
        try:
            async with session.get(course_url) as resp:
                if resp.status != 200:
                    logger.warning(f"Course page returned {resp.status}, trying download page")
                else:
                    course_html = await resp.text()
                    await self._parse_course_page(
                        course_html, course_url, course_output_dir, entry
                    )
        except Exception as e:
            logger.warning(f"Failed to fetch course page: {e}")

        if progress_callback:
            progress_callback(20, "Fetching download page...")

        # Step 2: Try to find and download the ZIP package
        download_page_url = course_url.rstrip("/") + "/download/"
        zip_url = None

        try:
            async with session.get(download_page_url) as resp:
                if resp.status == 200:
                    download_html = await resp.text()
                    zip_url = await self._find_zip_download_url(download_html, download_page_url)
        except Exception as e:
            logger.warning(f"Failed to fetch download page: {e}")

        if progress_callback:
            progress_callback(25, "Downloading course materials...")

        # Step 3: Download and extract ZIP if available (UNLESS partial download selected)
        if zip_url:
            # OPTIMIZATION: If user selected specific lectures, try to avoid downloading the whole ZIP.
            # We'll only skip ZIP if we have a robust way to get content otherwise (which we do via fetch_lecture_with_transcript)
            should_download_zip = True
            if selected_lectures and len(selected_lectures) < 5:  # Arbitrary threshold for optimization
                logger.info(f"Partial download ({len(selected_lectures)} lectures): Skipping ZIP to save bandwidth.")
                should_download_zip = False

            if should_download_zip:
                try:
                    await self._download_and_extract_zip(
                        session, zip_url, course_output_dir, progress_callback
                    )
                except Exception as e:
                    logger.warning(f"Failed to download ZIP: {e}")
            else:
                logger.info("Skipping ZIP download for partial import - will scrape pages directly.")

        if progress_callback:
            progress_callback(70, "Parsing course content...")

        # Step 4: Parse the downloaded/fetched content
        content_data = await self._parse_downloaded_content(
            course_output_dir, entry, raw_data, selected_lectures, fetched_lectures
        )

        if progress_callback:
            progress_callback(90, "Saving course metadata...")

        # Step 5: Save comprehensive metadata
        metadata = {
            "source": "mit_ocw",
            "course_id": course_id,
            "title": entry.title,
            "description": entry.description,
            "instructors": entry.instructors,
            "department": entry.department,
            "semester": entry.semester,
            "level": entry.level,
            "course_url": course_url,
            "license": MIT_OCW_LICENSE.to_dict(),
            "attribution": self.get_attribution_text(course_id, entry.title),
            "content": content_data,
            "selected_lectures": selected_lectures,
        }

        metadata_path = course_output_dir / "course_metadata.json"
        with open(metadata_path, "w") as f:
            json.dump(metadata, f, indent=2)

        if progress_callback:
            progress_callback(100, "Download complete")

        logger.info(f"Downloaded course {course_id} to {course_output_dir}")
        return course_output_dir

    async def _parse_course_page(
        self,
        html: str,
        base_url: str,
        output_dir: Path,
        entry: CourseCatalogEntry,
    ):
        """Parse the main course page to extract structure and links."""
        soup = BeautifulSoup(html, "html.parser")

        # Extract syllabus if available
        syllabus_content = []
        for section in soup.find_all(["section", "div"], class_=re.compile(r"syllabus|overview")):
            text = section.get_text(strip=True, separator="\n")
            if text:
                syllabus_content.append(text)

        if syllabus_content:
            syllabus_path = output_dir / "syllabus.txt"
            with open(syllabus_path, "w") as f:
                f.write("\n\n".join(syllabus_content))

        # Extract navigation links to find lecture pages
        nav_links = []
        for link in soup.find_all("a", href=True):
            href = link.get("href", "")
            text = link.get_text(strip=True)
            if any(kw in href.lower() or kw in text.lower()
                   for kw in ["video", "lecture", "transcript", "pages"]):
                full_url = urljoin(base_url, href)
                nav_links.append({"text": text, "url": full_url})

        if nav_links:
            links_path = output_dir / "navigation_links.json"
            with open(links_path, "w") as f:
                json.dump(nav_links, f, indent=2)

    async def _find_zip_download_url(self, html: str, base_url: str) -> Optional[str]:
        """Find the ZIP download URL from the download page."""
        soup = BeautifulSoup(html, "html.parser")

        # Look for ZIP download link
        for link in soup.find_all("a", href=True):
            href = link.get("href", "")
            text = link.get_text(strip=True).lower()
            if href.endswith(".zip") or "download" in text and "zip" in text.lower():
                return urljoin(base_url, href)

        # Try common OCW ZIP patterns
        for link in soup.find_all("a", href=re.compile(r"\.zip$", re.I)):
            return urljoin(base_url, link["href"])

        return None

    async def _download_and_extract_zip(
        self,
        session: aiohttp.ClientSession,
        zip_url: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]] = None,
    ):
        """Download and extract the course ZIP file."""
        logger.info(f"Downloading ZIP from {zip_url}")

        async with session.get(zip_url) as resp:
            if resp.status != 200:
                raise ValueError(f"ZIP download failed with status {resp.status}")

            total_size = int(resp.headers.get("content-length", 0))
            downloaded = 0
            chunks = []

            async for chunk in resp.content.iter_chunked(8192):
                chunks.append(chunk)
                downloaded += len(chunk)
                if progress_callback and total_size:
                    pct = 25 + (downloaded / total_size) * 40
                    progress_callback(pct, f"Downloading... {downloaded // 1024}KB")

            zip_data = b"".join(chunks)

        # Extract ZIP
        if progress_callback:
            progress_callback(65, "Extracting ZIP...")

        zip_buffer = io.BytesIO(zip_data)
        with zipfile.ZipFile(zip_buffer, "r") as zf:
            zf.extractall(output_dir)

        logger.info(f"Extracted ZIP to {output_dir}")

    async def _parse_downloaded_content(
        self,
        output_dir: Path,
        entry: CourseCatalogEntry,
        raw_data: Dict[str, Any],
        selected_lectures: Optional[List[str]] = None,
        fetched_lectures: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """Parse downloaded content to extract structured data."""
        content = {
            "lectures": [],
            "assignments": [],
            "exams": [],
            "resources": [],
        }

        has_video = "video" in raw_data.get("features", [])
        has_transcript = "transcript" in raw_data.get("features", [])

        # Use pre-fetched lecture titles if available
        if fetched_lectures:
            # Filter to selected lectures first
            lectures_to_process = []
            for lec in fetched_lectures:
                lecture_id = lec["id"]
                # Skip if not in selected lectures
                if selected_lectures and lecture_id not in selected_lectures:
                    continue
                lectures_to_process.append(lec)

            # Fetch transcripts for selected lectures (limit concurrency)
            logger.info(f"Fetching transcripts for {len(lectures_to_process)} lectures...")
            semaphore = asyncio.Semaphore(3)  # Limit to 3 concurrent requests

            async def fetch_with_semaphore(lec: Dict[str, Any]) -> Dict[str, Any]:
                async with semaphore:
                    return await self._fetch_lecture_with_transcript(lec, output_dir)

            enriched_lectures = await asyncio.gather(
                *[fetch_with_semaphore(lec) for lec in lectures_to_process]
            )

            for lec in enriched_lectures:
                content["lectures"].append({
                    "id": lec["id"],
                    "number": lec["number"],
                    "title": lec["title"],
                    "has_video": has_video,
                    "has_transcript": has_transcript,
                    "url": lec.get("url", ""),
                    "transcript_text": lec.get("transcript_text", ""),
                    "transcript_url": lec.get("transcript_url", ""),
                })
        else:
            # Fall back to parsing HTML files from the output directory
            html_files = list(output_dir.rglob("*.html")) + list(output_dir.rglob("*.htm"))

            # Parse each HTML file for content
            lecture_pattern = re.compile(r"lecture[_-]?(\d+)|lec[_-]?(\d+)", re.I)
            transcript_pattern = re.compile(r"transcript", re.I)

            for html_file in html_files:
                try:
                    with open(html_file, "r", encoding="utf-8", errors="ignore") as f:
                        html_content = f.read()

                    soup = BeautifulSoup(html_content, "html.parser")
                    title = soup.find("title")
                    title_text = title.get_text(strip=True) if title else html_file.stem

                    # Check if this is a lecture page
                    match = lecture_pattern.search(str(html_file))
                    if match:
                        lecture_num = int(match.group(1) or match.group(2))
                        lecture_id = f"lecture-{lecture_num}"

                        # Skip if not in selected lectures
                        if selected_lectures and lecture_id not in selected_lectures:
                            continue

                        # Extract lecture content
                        lecture_data = {
                            "id": lecture_id,
                            "number": lecture_num,
                            "title": title_text,
                            "file": str(html_file.relative_to(output_dir)),
                            "has_transcript": bool(transcript_pattern.search(html_content)),
                        }

                        # Extract text content
                        main_content = soup.find(["main", "article", "div"],
                                                class_=re.compile(r"content|main|body"))
                        if main_content:
                            lecture_data["text_preview"] = main_content.get_text(
                                strip=True, separator=" "
                            )[:500]

                        content["lectures"].append(lecture_data)

                except Exception as e:
                    logger.warning(f"Failed to parse {html_file}: {e}")

        # Look for PDF files
        pdf_files = list(output_dir.rglob("*.pdf"))
        for pdf_file in pdf_files:
            filename = pdf_file.name.lower()
            resource = {
                "file": str(pdf_file.relative_to(output_dir)),
                "name": pdf_file.stem,
            }

            if any(kw in filename for kw in ["exam", "midterm", "final", "quiz"]):
                content["exams"].append(resource)
            elif any(kw in filename for kw in ["problem", "assignment", "pset", "homework"]):
                content["assignments"].append(resource)
            else:
                content["resources"].append(resource)

        # Sort lectures by number, then sub_number if present
        content["lectures"].sort(key=lambda x: (x.get("number", 0), x.get("sub_number", 0)))

        # If still no lectures, create from catalog data
        if not content["lectures"]:
            lecture_count = raw_data.get("lecture_count", 0)

            for i in range(1, lecture_count + 1):
                lecture_id = f"lecture-{i}"
                if selected_lectures and lecture_id not in selected_lectures:
                    continue

                content["lectures"].append({
                    "id": lecture_id,
                    "number": i,
                    "title": f"Lecture {i}",
                    "has_video": has_video,
                    "has_transcript": has_transcript,
                })

        return content

    async def get_download_size(self, course_id: str) -> str:
        """Estimate download size for a course."""
        # Rough estimates based on typical MIT OCW courses
        entry = self._catalog_cache.get(course_id)
        if not entry:
            return "Unknown"

        has_video = any(f.type == "video" for f in entry.features if f.available)

        if has_video:
            return "1-5 GB (with video)"
        else:
            return "10-50 MB (materials only)"

    # =========================================================================
    # License Methods (CRITICAL)
    # =========================================================================

    def validate_license(self, course_id: str) -> LicenseValidationResult:
        """
        Validate that a course can be imported.

        All MIT OCW content is CC-BY-NC-SA 4.0, so all courses can be imported
        as long as attribution is preserved.
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
            license=MIT_OCW_LICENSE,
            warnings=[],
            attribution_text=self.get_attribution_text(course_id, entry.title),
        )

    def get_attribution_text(self, course_id: str, course_title: str) -> str:
        """Generate attribution text for a course."""
        return (
            f'This content is derived from MIT OpenCourseWare (ocw.mit.edu). '
            f'Original course: "{course_title}" (Course Number: {course_id.split("-")[0]}). '
            f'Licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC-BY-NC-SA 4.0). '
            f'Copyright Massachusetts Institute of Technology.'
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
