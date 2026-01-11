"""
MERLOT source handler.

Provides course catalog browsing and content discovery from MERLOT
(Multimedia Educational Resource for Learning and Online Teaching).

MERLOT is a referatory (catalog) linking to external OER sources.
Individual materials have their own Creative Commons licenses.

CRITICAL: Only import materials with derivatives-allowed licenses:
- CC0, CC BY, CC BY-SA, CC BY-NC, CC BY-NC-SA
- NEVER import CC BY-ND or CC BY-NC-ND (no derivatives allowed)
- NEVER import materials with unclear/unspecified licenses

Reference: https://www.merlot.org
API Docs: https://info.merlot.org/merlothelp/MERLOT_Technologies.htm

Required Attribution:
"Reproduced with permission from MERLOT - the Multimedia Resource
for Learning Online and Teaching (www.merlot.org). Some rights reserved."
"""

__version__ = "1.0.0"
__author__ = "UnaMentis Team"
__url__ = "https://www.merlot.org/"

import asyncio
import json
import logging
import os
import re
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

import aiohttp

from ...core.base import (
    CurriculumSourceHandler,
    LicenseRestrictionError,
    LicenseValidationResult,
)
from ...core.models import (
    ContentStructure,
    ContentTopic,
    ContentUnit,
    CourseCatalogEntry,
    CourseDetail,
    CourseFeature,
    CurriculumSource,
    LicenseInfo,
    NormalizedCourseDetail,
)
from ...core.registry import SourceRegistry

logger = logging.getLogger(__name__)


# =============================================================================
# MERLOT License Definitions
# =============================================================================

# Licenses that ALLOW derivatives (we can adapt for voice tutoring)
ALLOWED_LICENSES: Set[str] = {
    "CC0",
    "CC BY",
    "CC BY-SA",
    "CC BY-NC",
    "CC BY-NC-SA",
    "Public Domain",
}

# Licenses that PROHIBIT derivatives (we CANNOT use these)
PROHIBITED_LICENSES: Set[str] = {
    "CC BY-ND",
    "CC BY-NC-ND",
}


def _create_license_info(license_type: str) -> LicenseInfo:
    """Create LicenseInfo from MERLOT license type string."""
    # Normalize license type
    normalized = license_type.upper().strip()

    # Map to SPDX identifiers and full info
    license_map = {
        "CC0": LicenseInfo(
            type="CC0-1.0",
            name="Creative Commons Zero (Public Domain)",
            url="https://creativecommons.org/publicdomain/zero/1.0/",
            permissions=["share", "adapt", "commercial"],
            conditions=[],
            attribution_required=False,
            attribution_format="",
            restrictions=[],
        ),
        "CC BY": LicenseInfo(
            type="CC-BY-4.0",
            name="Creative Commons Attribution 4.0 International",
            url="https://creativecommons.org/licenses/by/4.0/",
            permissions=["share", "adapt", "commercial"],
            conditions=["attribution"],
            attribution_required=True,
            attribution_format="",
            restrictions=[],
        ),
        "CC BY-SA": LicenseInfo(
            type="CC-BY-SA-4.0",
            name="Creative Commons Attribution-ShareAlike 4.0 International",
            url="https://creativecommons.org/licenses/by-sa/4.0/",
            permissions=["share", "adapt", "commercial"],
            conditions=["attribution", "sharealike"],
            attribution_required=True,
            attribution_format="",
            restrictions=[],
        ),
        "CC BY-NC": LicenseInfo(
            type="CC-BY-NC-4.0",
            name="Creative Commons Attribution-NonCommercial 4.0 International",
            url="https://creativecommons.org/licenses/by-nc/4.0/",
            permissions=["share", "adapt"],
            conditions=["attribution", "noncommercial"],
            attribution_required=True,
            attribution_format="",
            restrictions=["noncommercial"],
        ),
        "CC BY-NC-SA": LicenseInfo(
            type="CC-BY-NC-SA-4.0",
            name="Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International",
            url="https://creativecommons.org/licenses/by-nc-sa/4.0/",
            permissions=["share", "adapt"],
            conditions=["attribution", "noncommercial", "sharealike"],
            attribution_required=True,
            attribution_format="",
            restrictions=["noncommercial"],
        ),
        "PUBLIC DOMAIN": LicenseInfo(
            type="CC0-1.0",
            name="Public Domain",
            url="https://creativecommons.org/publicdomain/zero/1.0/",
            permissions=["share", "adapt", "commercial"],
            conditions=[],
            attribution_required=False,
            attribution_format="",
            restrictions=[],
        ),
    }

    # Try to find matching license
    for key, info in license_map.items():
        if key in normalized:
            return info

    # Return unknown license (should be filtered out)
    return LicenseInfo(
        type="UNKNOWN",
        name=f"Unknown License: {license_type}",
        url="",
        permissions=[],
        conditions=[],
        attribution_required=True,
        attribution_format="",
        restrictions=["unknown"],
    )


def _is_license_allowed(license_str: str) -> bool:
    """
    Check if a license allows creating derivatives.

    CRITICAL: This is the gatekeeper preventing import of ND-licensed content.
    """
    if not license_str:
        return False

    normalized = license_str.upper().strip()

    # Explicit rejection of ND (NoDerivatives) licenses
    if "ND" in normalized:
        return False

    # Reject unclear/unspecified licenses
    unclear_terms = {"UNSURE", "UNKNOWN", "UNSPECIFIED", "N/A", "NONE", ""}
    if normalized in unclear_terms:
        return False

    # Check against allowed licenses
    for allowed in ALLOWED_LICENSES:
        if allowed in normalized:
            return True

    return False


# Default MERLOT attribution (required for all content)
MERLOT_ATTRIBUTION = (
    "Reproduced with permission from MERLOT - the Multimedia Resource "
    "for Learning Online and Teaching (www.merlot.org). Some rights reserved."
)


# =============================================================================
# MERLOT Material Types
# =============================================================================

MATERIAL_TYPES = {
    "Open Textbook": "textbook",
    "Tutorial": "tutorial",
    "Lecture": "lecture",
    "Simulation": "simulation",
    "Animation": "animation",
    "Assessment": "assessment",
    "Case Study": "case_study",
    "Collection": "collection",
    "Reference": "reference",
    "Workshop": "workshop",
    "Presentation": "presentation",
    "Learning Object": "learning_object",
}

# Priority material types for import (best for voice tutoring)
PRIORITY_MATERIAL_TYPES = ["Open Textbook", "Tutorial", "Lecture", "Reference"]


# =============================================================================
# MERLOT Subject Categories
# =============================================================================

MERLOT_CATEGORIES = [
    "Arts",
    "Business",
    "Education",
    "Humanities",
    "Mathematics and Statistics",
    "Science and Technology",
    "Social Sciences",
    "Workforce Development",
]


# =============================================================================
# MERLOT Source Handler
# =============================================================================

@SourceRegistry.register
class MERLOTHandler(CurriculumSourceHandler):
    """
    MERLOT source handler.

    MERLOT is a referatory (catalog) of OER, not a content host.
    Materials link to external sources with their own licenses.

    CRITICAL: We only import materials with derivatives-allowed licenses.

    API Key Configuration:
    1. Environment variable: MERLOT_API_KEY (checked first)
    2. Plugin settings: settings['api_key'] (checked second)
    3. Management Console: Configure via Plugin Manager UI

    Request API key at: https://www.merlot.org/merlot/signWebServicesForm.htm
    """

    def __init__(self):
        self._session: Optional[aiohttp.ClientSession] = None
        self._api_key: Optional[str] = None
        self._catalog_cache: Dict[str, CourseCatalogEntry] = {}
        self._raw_data_cache: Dict[str, Dict[str, Any]] = {}

        # Load API key (environment variable takes precedence)
        self._load_api_key()

    def _load_api_key(self) -> None:
        """
        Load API key from environment or plugin settings.

        Priority:
        1. Environment variable MERLOT_API_KEY
        2. Plugin settings from management console
        """
        # Check environment variable first
        self._api_key = os.environ.get("MERLOT_API_KEY")

        if self._api_key:
            logger.info("MERLOT API key loaded from environment variable")
            return

        # Try to load from plugin settings
        try:
            from ...core.discovery import get_plugin_discovery
            discovery = get_plugin_discovery()
            state = discovery._states.get("merlot")
            if state and state.settings.get("api_key"):
                self._api_key = state.settings["api_key"]
                logger.info("MERLOT API key loaded from plugin settings")
                return
        except Exception as e:
            logger.debug(f"Could not load API key from settings: {e}")

        logger.warning(
            "MERLOT_API_KEY not configured. API access will be limited. "
            "Configure in Plugin Manager or set MERLOT_API_KEY environment variable. "
            "Request a key at: https://www.merlot.org/merlot/signWebServicesForm.htm"
        )

    def configure(self, settings: Dict[str, Any]) -> None:
        """
        Configure the plugin with new settings.

        Called by the Plugin Manager when settings are updated.

        Args:
            settings: Dictionary containing 'api_key' and other settings
        """
        if "api_key" in settings:
            new_key = settings["api_key"]
            if new_key and new_key != self._api_key:
                self._api_key = new_key
                logger.info("MERLOT API key updated via configuration")
            elif not new_key:
                self._api_key = None
                logger.info("MERLOT API key cleared")

    def get_configuration_schema(self) -> Dict[str, Any]:
        """
        Return the configuration schema for the management UI.

        This tells the UI what settings are available and how to display them.
        """
        return {
            "settings": [
                {
                    "key": "api_key",
                    "label": "MERLOT API Key",
                    "type": "password",
                    "required": True,
                    "placeholder": "Enter your MERLOT Web Services license key",
                    "help_text": (
                        "Request a free API key for nonprofits at: "
                        "https://www.merlot.org/merlot/signWebServicesForm.htm"
                    ),
                    "help_url": "https://www.merlot.org/merlot/signWebServicesForm.htm",
                },
            ],
            "test_endpoint": "/api/plugins/merlot/test",
        }

    async def test_api_key(self, api_key: Optional[str] = None) -> Dict[str, Any]:
        """
        Test if an API key is valid by making a simple API request.

        Args:
            api_key: Key to test (uses current key if not provided)

        Returns:
            Dict with 'valid' boolean and 'message' string
        """
        test_key = api_key or self._api_key

        if not test_key:
            return {
                "valid": False,
                "message": "No API key provided",
            }

        session = await self._get_session()

        try:
            params = {
                "licenseKey": test_key,
                "keywords": "test",
                "pageSize": 1,
            }

            async with session.get(
                "https://www.merlot.org/merlot/materials.rest",
                params=params,
                timeout=aiohttp.ClientTimeout(total=15),
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    if "materials" in data or "results" in data:
                        return {
                            "valid": True,
                            "message": "API key is valid and working",
                        }
                    else:
                        return {
                            "valid": False,
                            "message": "Unexpected API response format",
                        }
                elif resp.status == 401:
                    return {
                        "valid": False,
                        "message": "Invalid or expired API key",
                    }
                elif resp.status == 403:
                    return {
                        "valid": False,
                        "message": "API key not authorized for this operation",
                    }
                else:
                    return {
                        "valid": False,
                        "message": f"API returned status {resp.status}",
                    }

        except asyncio.TimeoutError:
            return {
                "valid": False,
                "message": "Connection timeout - MERLOT API may be unavailable",
            }
        except Exception as e:
            return {
                "valid": False,
                "message": f"Connection error: {str(e)}",
            }

    @property
    def is_configured(self) -> bool:
        """Check if the plugin has a valid API key configured."""
        return bool(self._api_key)

    # =========================================================================
    # Properties
    # =========================================================================

    @property
    def source_id(self) -> str:
        return "merlot"

    @property
    def source_info(self) -> CurriculumSource:
        return CurriculumSource(
            id="merlot",
            name="MERLOT",
            description=(
                "Multimedia Educational Resource for Learning and Online Teaching. "
                "A curated collection of 100,000+ peer-reviewed learning materials."
            ),
            logo_url="/images/sources/merlot-logo.png",
            license=None,  # License varies per material
            course_count="100,000+",
            features=["peer_reviewed", "multiple_formats", "all_levels", "configurable"],
            status="active" if self.is_configured else "needs_config",
            base_url="https://www.merlot.org/",
        )

    @property
    def default_license(self) -> Optional[LicenseInfo]:
        # No default license - each material has its own
        return None

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
        """
        Get paginated course catalog from MERLOT.

        CRITICAL: Only returns materials with derivatives-allowed licenses.
        """
        filters = filters or {}

        # Build API parameters
        params = {
            "page": page,
            "pageSize": page_size,
            # CRITICAL: Only fetch CC-licensed materials
            "creativeCommons": "true",
        }

        if self._api_key:
            params["licenseKey"] = self._api_key

        if search:
            params["keywords"] = search

        if filters.get("subject"):
            params["category"] = filters["subject"]

        if filters.get("level"):
            params["audience"] = self._map_level_to_merlot(filters["level"])

        if filters.get("material_type"):
            params["materialType"] = filters["material_type"]

        # Minimum peer review rating (default 3.0 for quality)
        min_rating = filters.get("min_rating", 3.0)

        try:
            materials = await self._search_materials(params)
        except Exception as e:
            logger.error(f"MERLOT API error: {e}")
            # Return cached results if available
            cached = list(self._catalog_cache.values())
            return cached[:page_size], len(cached), self._get_filter_options()

        # Filter results
        entries = []
        for material in materials:
            # CRITICAL: License check
            license_type = material.get("creativeCommons", "")
            if not _is_license_allowed(license_type):
                logger.debug(f"Skipping material {material.get('materialId')} - license: {license_type}")
                continue

            # Quality filter
            rating = float(material.get("peerReviewRating", 0) or 0)
            if rating > 0 and rating < min_rating:
                continue

            entry = self._material_to_entry(material)
            entries.append(entry)

            # Cache for later
            self._catalog_cache[entry.id] = entry
            self._raw_data_cache[entry.id] = material

        # Note: MERLOT API returns total count, but we filter some out
        # So actual total may be less than reported
        total = len(entries)  # Best we can do without full scan

        return entries, total, self._get_filter_options()

    async def get_course_detail(self, course_id: str) -> CourseDetail:
        """Get full details for a specific material."""
        # Validate license first
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        # Check cache
        if course_id in self._catalog_cache:
            entry = self._catalog_cache[course_id]
            raw_data = self._raw_data_cache.get(course_id, {})
        else:
            # Fetch from API
            raw_data = await self._get_material_detail(course_id)
            if not raw_data:
                raise ValueError(f"Material not found: {course_id}")
            entry = self._material_to_entry(raw_data)
            self._catalog_cache[course_id] = entry
            self._raw_data_cache[course_id] = raw_data

        # Get license info
        license_type = raw_data.get("creativeCommons", "")
        license_info = _create_license_info(license_type)

        return CourseDetail(
            id=entry.id,
            source_id=entry.source_id,
            title=entry.title,
            instructors=entry.instructors,
            description=entry.description,
            level=entry.level,
            department=entry.department,
            features=entry.features,
            license=license_info,
            keywords=entry.keywords,
            syllabus=raw_data.get("description", ""),
            prerequisites=[],
            lectures=[],  # MERLOT materials are typically single items
            assignments=[],
            exams=[],
            estimated_import_time="5-10 minutes",
            estimated_output_size="1-10 MB",
            download_url=raw_data.get("url"),
        )

    async def get_normalized_course_detail(self, course_id: str) -> NormalizedCourseDetail:
        """Get normalized course detail for generic plugin UI."""
        # Validate license first
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        # Get data
        if course_id in self._catalog_cache:
            entry = self._catalog_cache[course_id]
            raw_data = self._raw_data_cache.get(course_id, {})
        else:
            raw_data = await self._get_material_detail(course_id)
            if not raw_data:
                raise ValueError(f"Material not found: {course_id}")
            entry = self._material_to_entry(raw_data)

        # Get license info
        license_type = raw_data.get("creativeCommons", "")
        license_info = _create_license_info(license_type)

        # MERLOT materials are typically single items, not multi-lecture courses
        # Create a single topic representing the material
        topics = [
            ContentTopic(
                id="main",
                title=entry.title,
                number=1,
                has_video="video" in raw_data.get("materialType", "").lower(),
                has_transcript=False,
                has_practice="assessment" in raw_data.get("materialType", "").lower(),
            )
        ]

        units = [
            ContentUnit(
                id="content",
                title="Content",
                number=1,
                topics=topics,
            )
        ]

        content_structure = ContentStructure(
            unit_label="Material",
            topic_label="Resource",
            is_flat=True,
            units=units,
        )

        # Map level
        level = self._map_merlot_level(raw_data.get("audience", ""))
        level_labels = {
            "introductory": "Introductory",
            "intermediate": "Intermediate",
            "advanced": "Advanced",
            "k12": "K-12",
            "professional": "Professional",
        }
        level_label = level_labels.get(level, level.title())

        return NormalizedCourseDetail(
            id=entry.id,
            source_id=self.source_id,
            title=entry.title,
            description=entry.description,
            instructors=entry.instructors,
            level=level,
            level_label=level_label,
            department=entry.department,
            keywords=entry.keywords,
            thumbnail_url=None,
            license=license_info,
            features=entry.features,
            content_structure=content_structure,
            assignments=[],
            exams=[],
            syllabus=raw_data.get("description", ""),
            prerequisites=[],
            estimated_import_time="5-10 minutes",
            estimated_output_size="1-10 MB",
            source_url=raw_data.get("url"),
            download_url=raw_data.get("url"),
        )

    async def search_courses(
        self,
        query: str,
        limit: int = 20,
    ) -> List[CourseCatalogEntry]:
        """Search materials by query."""
        courses, _, _ = await self.get_course_catalog(
            page=1,
            page_size=limit,
            search=query,
        )
        return courses

    # =========================================================================
    # Download Methods
    # =========================================================================

    async def get_download_size(self, course_id: str) -> str:
        """Estimate download size for a material."""
        raw_data = self._raw_data_cache.get(course_id, {})
        material_type = raw_data.get("materialType", "").lower()

        # Rough estimates based on material type
        if "textbook" in material_type:
            return "5-50 MB"
        elif "video" in material_type:
            return "100-500 MB"
        elif "simulation" in material_type or "animation" in material_type:
            return "1-10 MB"
        else:
            return "1-10 MB"

    async def download_course(
        self,
        course_id: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]] = None,
        selected_lectures: Optional[List[str]] = None,
    ) -> Path:
        """
        Download material content.

        Since MERLOT is a referatory, this fetches content from the source URL.
        """
        # Validate license first
        license_result = self.validate_license(course_id)
        if not license_result.can_import:
            raise LicenseRestrictionError(license_result.warnings[0])

        # Get material data
        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            raw_data = await self._get_material_detail(course_id)
            if not raw_data:
                raise ValueError(f"Material not found: {course_id}")

        entry = self._catalog_cache.get(course_id)
        if not entry:
            entry = self._material_to_entry(raw_data)

        # Create output directory
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        material_output_dir = output_dir / course_id
        material_output_dir.mkdir(parents=True, exist_ok=True)

        if progress_callback:
            progress_callback(10, "Fetching material from source...")

        # Get the source URL
        source_url = raw_data.get("url", "")
        if not source_url:
            raise ValueError(f"No source URL for material: {course_id}")

        # Fetch content from source
        content_data = await self._fetch_source_content(source_url, material_output_dir, progress_callback)

        if progress_callback:
            progress_callback(80, "Saving metadata...")

        # Get license info
        license_type = raw_data.get("creativeCommons", "")
        license_info = _create_license_info(license_type)

        # Save metadata
        metadata = {
            "source": "merlot",
            "material_id": course_id,
            "title": entry.title,
            "description": entry.description,
            "authors": entry.instructors,
            "institution": raw_data.get("authorInstitution", ""),
            "source_url": source_url,
            "merlot_url": f"https://www.merlot.org/merlot/viewMaterial.htm?id={course_id}",
            "material_type": raw_data.get("materialType", ""),
            "category": raw_data.get("category", ""),
            "audience": raw_data.get("audience", ""),
            "peer_review_rating": raw_data.get("peerReviewRating"),
            "user_rating": raw_data.get("userRating"),
            "license": license_info.to_dict(),
            "attribution": {
                "merlot": MERLOT_ATTRIBUTION,
                "material": self.get_attribution_text(course_id, entry.title),
            },
            "content": content_data,
        }

        metadata_path = material_output_dir / "material_metadata.json"
        with open(metadata_path, "w") as f:
            json.dump(metadata, f, indent=2)

        if progress_callback:
            progress_callback(100, "Download complete")

        logger.info(f"Downloaded material {course_id} to {material_output_dir}")
        return material_output_dir

    async def _fetch_source_content(
        self,
        source_url: str,
        output_dir: Path,
        progress_callback: Optional[Callable[[float, str], None]] = None,
    ) -> Dict[str, Any]:
        """
        Fetch content from the source URL.

        Handles different content types (HTML, PDF, etc.)
        """
        session = await self._get_session()
        content_data = {
            "source_url": source_url,
            "content_type": "unknown",
            "extracted_text": "",
            "files": [],
        }

        try:
            # Check robots.txt compliance
            # (simplified - in production, use robotparser)

            async with session.get(
                source_url,
                timeout=aiohttp.ClientTimeout(total=30),
                allow_redirects=True,
            ) as resp:
                if resp.status != 200:
                    logger.warning(f"Source URL returned {resp.status}: {source_url}")
                    return content_data

                content_type = resp.headers.get("Content-Type", "")
                content_data["content_type"] = content_type

                if progress_callback:
                    progress_callback(40, f"Downloading content ({content_type})...")

                if "text/html" in content_type:
                    html = await resp.text()
                    content_data["extracted_text"] = self._extract_text_from_html(html)

                    # Save HTML
                    html_path = output_dir / "content.html"
                    with open(html_path, "w", encoding="utf-8") as f:
                        f.write(html)
                    content_data["files"].append("content.html")

                elif "application/pdf" in content_type:
                    pdf_bytes = await resp.read()

                    # Save PDF
                    pdf_path = output_dir / "content.pdf"
                    with open(pdf_path, "wb") as f:
                        f.write(pdf_bytes)
                    content_data["files"].append("content.pdf")

                    # Note: PDF text extraction would go here
                    # For now, just mark it for later processing

                else:
                    # Save as generic file
                    data = await resp.read()
                    ext = self._guess_extension(content_type)
                    file_path = output_dir / f"content{ext}"
                    with open(file_path, "wb") as f:
                        f.write(data)
                    content_data["files"].append(f"content{ext}")

        except asyncio.TimeoutError:
            logger.warning(f"Timeout fetching {source_url}")
        except Exception as e:
            logger.error(f"Error fetching {source_url}: {e}")

        return content_data

    def _extract_text_from_html(self, html: str) -> str:
        """Extract readable text from HTML."""
        try:
            from bs4 import BeautifulSoup
            soup = BeautifulSoup(html, "html.parser")

            # Remove script and style elements
            for element in soup(["script", "style", "nav", "footer", "header"]):
                element.decompose()

            # Get text
            text = soup.get_text(separator="\n", strip=True)

            # Clean up whitespace
            text = re.sub(r"\n{3,}", "\n\n", text)
            text = re.sub(r"[ \t]+", " ", text)

            return text[:50000]  # Limit to 50K chars
        except Exception as e:
            logger.warning(f"Error extracting text from HTML: {e}")
            return ""

    def _guess_extension(self, content_type: str) -> str:
        """Guess file extension from content type."""
        type_map = {
            "text/html": ".html",
            "application/pdf": ".pdf",
            "text/plain": ".txt",
            "application/json": ".json",
            "application/xml": ".xml",
            "text/xml": ".xml",
        }
        for mime, ext in type_map.items():
            if mime in content_type:
                return ext
        return ".bin"

    # =========================================================================
    # License Methods (CRITICAL)
    # =========================================================================

    def validate_license(self, course_id: str) -> LicenseValidationResult:
        """
        Validate that a material can be imported.

        CRITICAL: This is the gatekeeper preventing import of ND-licensed content.
        """
        raw_data = self._raw_data_cache.get(course_id)
        if not raw_data:
            return LicenseValidationResult(
                can_import=False,
                license=None,
                warnings=[f"Material not found: {course_id}. Please search again."],
                attribution_text="",
            )

        license_type = raw_data.get("creativeCommons", "")

        # Check if license allows derivatives
        if not _is_license_allowed(license_type):
            reason = "NoDerivatives" if "ND" in license_type.upper() else "unclear/unspecified"
            return LicenseValidationResult(
                can_import=False,
                license=None,
                warnings=[
                    f"Cannot import: License ({license_type}) does not allow derivatives. "
                    f"Reason: {reason}. "
                    "UnaMentis requires permission to create derivative works for voice tutoring."
                ],
                attribution_text="",
            )

        license_info = _create_license_info(license_type)
        entry = self._catalog_cache.get(course_id)
        title = entry.title if entry else raw_data.get("title", "Unknown")

        return LicenseValidationResult(
            can_import=True,
            license=license_info,
            warnings=[],
            attribution_text=self.get_attribution_text(course_id, title),
        )

    def get_attribution_text(self, course_id: str, title: str) -> str:
        """Generate attribution text for a material."""
        raw_data = self._raw_data_cache.get(course_id, {})
        author = raw_data.get("author", "Unknown Author")
        license_type = raw_data.get("creativeCommons", "Unknown License")

        return (
            f'"{title}" by {author}. '
            f"Retrieved from MERLOT (www.merlot.org). "
            f"Licensed under {license_type}. "
            f"{MERLOT_ATTRIBUTION}"
        )

    # =========================================================================
    # API Methods
    # =========================================================================

    async def _search_materials(self, params: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Search MERLOT API for materials."""
        session = await self._get_session()

        try:
            async with session.get(
                "https://www.merlot.org/merlot/materials.rest",
                params=params,
                timeout=aiohttp.ClientTimeout(total=30),
            ) as resp:
                if resp.status != 200:
                    logger.error(f"MERLOT API returned {resp.status}")
                    return []

                data = await resp.json()
                return data.get("materials", [])

        except Exception as e:
            logger.error(f"MERLOT API error: {e}")
            return []

    async def _get_material_detail(self, material_id: str) -> Optional[Dict[str, Any]]:
        """Get detailed information about a specific material."""
        session = await self._get_session()

        params = {"id": material_id}
        if self._api_key:
            params["licenseKey"] = self._api_key

        try:
            async with session.get(
                "https://www.merlot.org/merlot/material.rest",
                params=params,
                timeout=aiohttp.ClientTimeout(total=30),
            ) as resp:
                if resp.status != 200:
                    logger.error(f"MERLOT API returned {resp.status} for material {material_id}")
                    return None

                return await resp.json()

        except Exception as e:
            logger.error(f"MERLOT API error fetching material {material_id}: {e}")
            return None

    # =========================================================================
    # Helper Methods
    # =========================================================================

    def _material_to_entry(self, material: Dict[str, Any]) -> CourseCatalogEntry:
        """Convert MERLOT material to CourseCatalogEntry."""
        material_type = material.get("materialType", "")

        features = []
        if "video" in material_type.lower():
            features.append(CourseFeature(type="video", available=True))
        if "transcript" in material_type.lower():
            features.append(CourseFeature(type="transcript", available=True))
        if material.get("peerReviewRating"):
            features.append(CourseFeature(
                type="peer_reviewed",
                available=True,
                count=int(float(material.get("peerReviewRating", 0)))
            ))

        # Get license info
        license_type = material.get("creativeCommons", "")
        license_info = _create_license_info(license_type) if license_type else None

        return CourseCatalogEntry(
            id=str(material.get("materialId", "")),
            source_id=self.source_id,
            title=material.get("title", "Untitled"),
            instructors=[material.get("author", "")] if material.get("author") else [],
            description=material.get("description", "")[:500],  # Truncate
            level=self._map_merlot_level(material.get("audience", "")),
            department=material.get("category", ""),
            features=features,
            license=license_info,
            keywords=material.get("keywords", "").split(",") if material.get("keywords") else [],
        )

    def _map_merlot_level(self, audience: str) -> str:
        """Map MERLOT audience to standard level."""
        audience_lower = audience.lower() if audience else ""

        if "grade school" in audience_lower or "elementary" in audience_lower:
            return "k12"
        elif "middle school" in audience_lower:
            return "k12"
        elif "high school" in audience_lower:
            return "k12"
        elif "lower division" in audience_lower:
            return "introductory"
        elif "upper division" in audience_lower:
            return "intermediate"
        elif "graduate" in audience_lower:
            return "advanced"
        elif "professional" in audience_lower:
            return "professional"
        else:
            return "intermediate"

    def _map_level_to_merlot(self, level: str) -> str:
        """Map standard level to MERLOT audience."""
        level_map = {
            "introductory": "College/Lower Division",
            "intermediate": "College/Upper Division",
            "advanced": "Graduate School",
            "k12": "High School",
            "professional": "Professional",
        }
        return level_map.get(level, "")

    def _get_filter_options(self) -> Dict[str, List[str]]:
        """Get available filter options."""
        return {
            "subjects": MERLOT_CATEGORIES,
            "levels": ["introductory", "intermediate", "advanced", "k12", "professional"],
            "material_types": list(MATERIAL_TYPES.keys()),
        }

    # =========================================================================
    # Session Management
    # =========================================================================

    async def _get_session(self) -> aiohttp.ClientSession:
        """Get or create HTTP session."""
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                headers={
                    "User-Agent": "UnaMentis-Curriculum-Importer/1.0 (Educational Use; nonprofit)",
                    "Accept": "application/json",
                }
            )
        return self._session

    async def close(self):
        """Close HTTP session."""
        if self._session and not self._session.closed:
            await self._session.close()
