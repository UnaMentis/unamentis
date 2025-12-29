# MERLOT Importer Specification

**Version:** 1.0.0
**Status:** Draft
**Date:** 2025-12-29
**Target Audience:** All levels (K-12 through Graduate)

---

## Table of Contents

1. [Overview](#overview)
2. [Licensing and Compliance Analysis](#licensing-and-compliance-analysis)
3. [API Access Requirements](#api-access-requirements)
4. [MERLOT Platform Analysis](#merlot-platform-analysis)
5. [Data Mapping](#data-mapping)
6. [Implementation Specification](#implementation-specification)
7. [Content Extraction Strategy](#content-extraction-strategy)
8. [Error Handling](#error-handling)
9. [Testing Strategy](#testing-strategy)
10. [Implementation Timeline](#implementation-timeline)

---

## Overview

The MERLOT importer discovers and catalogs open educational resources from the MERLOT repository for integration with UnaMentis's conversational AI tutoring system. MERLOT (Multimedia Educational Resource for Learning and Online Teaching) is the world's largest curated collection of OER, with 100,000+ peer-reviewed learning materials.

### Why MERLOT?

| Criterion | Assessment |
|-----------|------------|
| **API Availability** | REST API with license key |
| **Content Volume** | 100,000+ learning resources |
| **Quality Control** | Peer-reviewed by academic community |
| **License** | Various CC licenses (must check per-resource) |
| **Cost** | Free for nonprofits |
| **Coverage** | All disciplines, all education levels |
| **Metadata Quality** | Rich metadata including reviews, ratings |
| **History** | Established 1997, mature and stable |

### Import Architecture

MERLOT is unique among our import sources: it is primarily a **referatory** (directory of resources) rather than a content host. Most resources link to external sites.

```
MERLOT API → Material Metadata → License Check → External Content Fetch → UMCF Generation
```

**Two-Phase Import:**
1. **Discovery Phase:** Query MERLOT API for materials matching criteria
2. **Content Phase:** Fetch actual content from source URLs (respecting licenses)

### Import Scope

**In Scope:**
- MERLOT material metadata (title, description, author, reviews)
- License information for each material
- Peer review ratings and comments
- Material URLs for CC-licensed content
- Content extraction from CC-licensed source URLs
- Open textbooks hosted on MERLOT

**Out of Scope:**
- Materials with All Rights Reserved or unclear licensing
- Materials with CC-ND (NoDerivatives) licenses
- Interactive simulations requiring external accounts
- Paid/subscription content
- Materials requiring institutional access

---

## Licensing and Compliance Analysis

### MERLOT Platform Licensing

**Critical Understanding:** MERLOT itself is a catalog/directory. Each material has its own license set by its creator.

#### MERLOT Web Services Agreement

| Requirement | UnaMentis Compliance |
|-------------|---------------------|
| Nonprofit organization | **Yes** - Open source educational project |
| Non-commercial use | **Yes** - Free tutoring app |
| Display MERLOT logo | **Yes** - Will include in attribution |
| Link to MERLOT repository | **Yes** - Source URLs preserved |
| Display CC license notices | **Yes** - UMCF includes license metadata |
| No competing searchable repository | **Yes** - We're a tutoring app, not a catalog |
| No harvesting for resale | **Yes** - Educational use only |
| Attribution required | **Yes** - Full attribution in UMCF |

**Required Attribution Text:**
> "Reproduced with permission from MERLOT - the Multimedia Resource for Learning Online and Teaching (www.merlot.org). Some rights reserved."

#### Individual Material Licensing

**License Filter Strategy:**

| License | Import? | Notes |
|---------|---------|-------|
| CC0 (Public Domain) | **Yes** | Ideal |
| CC BY | **Yes** | Ideal, full flexibility |
| CC BY-SA | **Yes** | Good, must share alike |
| CC BY-NC | **Yes** | Acceptable for nonprofit |
| CC BY-NC-SA | **Yes** | Acceptable for nonprofit |
| CC BY-ND | **No** | Cannot create derivatives |
| CC BY-NC-ND | **No** | Cannot create derivatives |
| All Rights Reserved | **No** | No permission |
| "Unsure" / Unspecified | **No** | Too risky |
| Custom License | **Manual Review** | Case-by-case |

**Warning:** Many MERLOT contributors select "unsure" for licensing. We MUST filter these out.

### Legal Risk Assessment

| Risk | Mitigation |
|------|------------|
| Unclear material licenses | Filter to only known CC licenses |
| MERLOT API agreement violation | Obtain license key, follow all terms |
| External site ToS violation | Respect robots.txt, rate limiting |
| Attribution failure | Automated attribution in all UMCF files |
| License change over time | Record license at import time, periodic revalidation |

### Compliance Checklist

Before deploying:
- [ ] Obtain MERLOT Web Services license key
- [ ] Sign WSRS Agreement as nonprofit
- [ ] Implement CC license filtering (exclude ND, unclear)
- [ ] Implement MERLOT attribution in all outputs
- [ ] Implement individual material attribution
- [ ] Add robots.txt compliance for external fetches
- [ ] Document license at time of import
- [ ] Create process for handling DMCA requests

---

## API Access Requirements

### Obtaining API Access

1. **Request URL:** https://www.merlot.org/merlot/signWebServicesForm.htm
2. **Requirements:**
   - Authorized organizational representative
   - Agreement to WSRS terms
   - Technical contact information
3. **Processing Time:** ~3 business days
4. **Cost:** Free for nonprofits

### API Tiers

| Tier | Access | Availability |
|------|--------|--------------|
| **Basic Search** | Simple keyword search | All MERLOT members |
| **Advanced Search** | Field-specific queries | Partners/Approved orgs |
| **Contribute** | Add materials | Partners |
| **Personal Collections** | Manage collections | Partners |

**Recommended:** Request Advanced Search access for field-specific filtering.

### API Endpoints

Based on available documentation:

```
Base URL: https://www.merlot.org/merlot/

Search Endpoints:
- GET /materials.rest - Search materials
- GET /material.rest?id={id} - Get material details

Parameters:
- keywords - Search terms
- category - Subject area
- materialType - Type filter
- creativeCommons - License filter (CRITICAL)
- page - Pagination
- pageSize - Results per page
```

### Rate Limiting

MERLOT does not publish specific rate limits, but best practices:
- Maximum 1 request per second
- Implement exponential backoff on errors
- Cache responses (materials don't change frequently)
- Batch operations during off-peak hours

---

## MERLOT Platform Analysis

### Material Types

| Type | Description | UMCF Suitability |
|------|-------------|------------------|
| **Open Textbook** | Complete textbook | Excellent |
| **Tutorial** | Step-by-step instruction | Excellent |
| **Lecture** | Recorded lecture | Good (transcript needed) |
| **Simulation** | Interactive model | Limited (URL reference) |
| **Animation** | Visual explanation | Limited (URL reference) |
| **Assessment** | Quiz/test | Good |
| **Case Study** | Scenario-based | Good |
| **Collection** | Curated set | Good (import individually) |
| **Reference** | Encyclopedia-style | Good |
| **Workshop** | Hands-on activity | Moderate |

**Priority for Import:**
1. Open Textbooks (complete, structured content)
2. Tutorials (step-by-step, voice-friendly)
3. Lectures (with transcripts)
4. Reference materials

### Subject Categories

MERLOT organizes content into discipline trees:

```
- Arts
- Business
- Education
- Humanities
- Mathematics and Statistics
- Science and Technology
  - Biology
  - Chemistry
  - Computer Science
  - Engineering
  - Physics
  - etc.
- Social Sciences
- Workforce Development
```

### Quality Indicators

MERLOT provides rich quality metadata:

| Indicator | Source | Use |
|-----------|--------|-----|
| **Peer Review Rating** | Expert reviewers | Quality filter (3.0+ minimum) |
| **User Rating** | Community votes | Secondary quality signal |
| **Comments** | Community feedback | Identify issues |
| **Editor's Choice** | MERLOT editors | Premium content |
| **Learning Exercises** | Linked assessments | Enhancement opportunity |

---

## Data Mapping

### MERLOT to UMCF Field Mapping

| MERLOT Field | UMCF Field | Notes |
|--------------|------------|-------|
| `title` | `metadata.title` | Direct |
| `description` | `metadata.description` | May need enrichment |
| `author` | `metadata.creators[].name` | Parse if multiple |
| `authorInstitution` | `metadata.creators[].affiliation` | |
| `creativeCommons` | `metadata.rights.license` | Map to SPDX |
| `category` | `metadata.educationalContext.subjects[]` | Normalize |
| `materialType` | `content[].type` | Map to UMCF types |
| `audience` | `metadata.educationalContext.level` | Map to ISCED |
| `peerReviewRating` | `extensions.merlot.peerReviewRating` | Preserve |
| `userRating` | `extensions.merlot.userRating` | Preserve |
| `dateCreated` | `metadata.lifecycle.created` | ISO 8601 |
| `dateModified` | `metadata.lifecycle.modified` | ISO 8601 |
| `url` | `content[].source.url` | Source content |
| `merlotId` | `metadata.identifiers[].value` | type="merlot" |
| `keywords` | `metadata.keywords[]` | |
| `language` | `metadata.language` | ISO 639-1 |

### License Mapping

| MERLOT License | SPDX Identifier | UMCF `rights.license` |
|----------------|-----------------|----------------------|
| CC BY | CC-BY-4.0 | `CC-BY-4.0` |
| CC BY-SA | CC-BY-SA-4.0 | `CC-BY-SA-4.0` |
| CC BY-NC | CC-BY-NC-4.0 | `CC-BY-NC-4.0` |
| CC BY-NC-SA | CC-BY-NC-SA-4.0 | `CC-BY-NC-SA-4.0` |
| Public Domain | CC0-1.0 | `CC0-1.0` |

### Audience Level Mapping

| MERLOT Audience | UMCF Level | ISCED |
|-----------------|------------|-------|
| Grade School | primary | 1 |
| Middle School | lower_secondary | 2 |
| High School | upper_secondary | 3 |
| College/Lower Division | undergraduate | 5 |
| College/Upper Division | undergraduate | 6 |
| Graduate School | graduate | 7 |
| Professional | professional | 8 |

---

## Implementation Specification

### Plugin Architecture

```python
# server/importers/sources/merlot.py

from ..core.plugin import CurriculumSourceHandler, SourceMetadata, CourseInfo
from typing import AsyncIterator, Optional
import aiohttp

class MerlotHandler(CurriculumSourceHandler):
    """MERLOT OER repository handler."""

    source_id = "merlot"
    source_name = "MERLOT"
    source_url = "https://www.merlot.org"

    # License whitelist (excludes ND and unclear)
    ALLOWED_LICENSES = {
        "CC BY", "CC BY-SA", "CC BY-NC", "CC BY-NC-SA",
        "Public Domain", "CC0"
    }

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://www.merlot.org/merlot"

    async def get_metadata(self) -> SourceMetadata:
        return SourceMetadata(
            source_id=self.source_id,
            source_name=self.source_name,
            source_url=self.source_url,
            description="Multimedia Educational Resource for Learning and Online Teaching",
            license_info="Various Creative Commons (filtered for derivatives-allowed)",
            content_types=["textbook", "tutorial", "lecture", "reference"],
            education_levels=["K-12", "Undergraduate", "Graduate", "Professional"],
            subjects=["All disciplines"],
            attribution_required=True,
            attribution_text=(
                "Reproduced with permission from MERLOT - the Multimedia Resource "
                "for Learning Online and Teaching (www.merlot.org). Some rights reserved."
            )
        )

    async def search_courses(
        self,
        query: Optional[str] = None,
        subject: Optional[str] = None,
        level: Optional[str] = None,
        material_type: Optional[str] = None,
        min_rating: float = 3.0,
        page: int = 1,
        page_size: int = 50
    ) -> AsyncIterator[CourseInfo]:
        """Search MERLOT with license filtering."""

        params = {
            "licenseKey": self.api_key,
            "page": page,
            "pageSize": page_size,
            # CRITICAL: Only fetch CC-licensed materials
            "creativeCommons": "true"
        }

        if query:
            params["keywords"] = query
        if subject:
            params["category"] = subject
        if level:
            params["audience"] = level
        if material_type:
            params["materialType"] = material_type

        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{self.base_url}/materials.rest",
                params=params
            ) as response:
                data = await response.json()

                for material in data.get("materials", []):
                    # Secondary license check
                    license_type = material.get("creativeCommons", "")
                    if not self._is_allowed_license(license_type):
                        continue

                    # Quality filter
                    rating = float(material.get("peerReviewRating", 0))
                    if rating < min_rating and rating > 0:
                        continue

                    yield self._to_course_info(material)

    def _is_allowed_license(self, license_str: str) -> bool:
        """Check if license allows derivatives."""
        if not license_str:
            return False
        # Reject ND (NoDerivatives) licenses
        if "ND" in license_str.upper():
            return False
        # Reject unclear/unspecified
        if license_str.lower() in ("unsure", "unknown", ""):
            return False
        return any(allowed in license_str for allowed in self.ALLOWED_LICENSES)

    def _to_course_info(self, material: dict) -> CourseInfo:
        """Convert MERLOT material to CourseInfo."""
        return CourseInfo(
            source_id=self.source_id,
            course_id=str(material.get("materialId")),
            title=material.get("title", ""),
            description=material.get("description", ""),
            url=material.get("url", ""),
            merlot_url=f"https://www.merlot.org/merlot/viewMaterial.htm?id={material.get('materialId')}",
            authors=[material.get("author", "")],
            institution=material.get("authorInstitution", ""),
            license=self._normalize_license(material.get("creativeCommons", "")),
            subjects=[material.get("category", "")],
            level=self._map_level(material.get("audience", "")),
            material_type=material.get("materialType", ""),
            language=material.get("language", "en"),
            peer_review_rating=float(material.get("peerReviewRating", 0)),
            user_rating=float(material.get("userRating", 0)),
            date_created=material.get("dateCreated"),
            date_modified=material.get("dateModified"),
            keywords=material.get("keywords", "").split(",")
        )
```

### Content Fetching Strategy

Since MERLOT links to external content:

```python
class MerlotContentFetcher:
    """Fetch and extract content from MERLOT-linked resources."""

    # Known good sources for direct content extraction
    TRUSTED_SOURCES = {
        "openstax.org": OpenStaxExtractor,
        "cnx.org": CNXExtractor,
        "oercommons.org": OERCommonsExtractor,
        "pressbooks.com": PressbooksExtractor,
        "libretexts.org": LibreTextsExtractor,
        "saylor.org": SaylorExtractor,
    }

    async def fetch_content(self, course_info: CourseInfo) -> Optional[ExtractedContent]:
        """Fetch content from source URL."""

        url = course_info.url
        domain = self._extract_domain(url)

        # Check robots.txt first
        if not await self._check_robots_allowed(url):
            return None

        # Use specialized extractor if available
        if domain in self.TRUSTED_SOURCES:
            extractor = self.TRUSTED_SOURCES[domain]()
            return await extractor.extract(url)

        # Generic extraction for unknown sources
        return await self._generic_extract(url)

    async def _generic_extract(self, url: str) -> Optional[ExtractedContent]:
        """Generic HTML/PDF content extraction."""

        async with aiohttp.ClientSession() as session:
            async with session.get(url) as response:
                content_type = response.headers.get("Content-Type", "")

                if "text/html" in content_type:
                    html = await response.text()
                    return self._extract_from_html(html, url)

                elif "application/pdf" in content_type:
                    pdf_bytes = await response.read()
                    return self._extract_from_pdf(pdf_bytes, url)

        return None
```

### UMCF Generation

```python
async def generate_umcf(
    course_info: CourseInfo,
    extracted_content: ExtractedContent
) -> dict:
    """Generate UMCF document from MERLOT material."""

    return {
        "umcfVersion": "1.0.0",
        "metadata": {
            "title": course_info.title,
            "description": course_info.description,
            "version": "1.0.0",
            "language": course_info.language,
            "creators": [{
                "name": author,
                "role": "author",
                "affiliation": course_info.institution
            } for author in course_info.authors],
            "identifiers": [
                {"type": "merlot", "value": course_info.course_id},
                {"type": "url", "value": course_info.url}
            ],
            "rights": {
                "license": course_info.license,
                "licenseUrl": f"https://creativecommons.org/licenses/{course_info.license.lower()}/",
                "attributionText": (
                    f"'{course_info.title}' by {', '.join(course_info.authors)}. "
                    f"Retrieved from MERLOT (www.merlot.org). "
                    f"Licensed under {course_info.license}."
                ),
                "sourceUrl": course_info.url,
                "merlotUrl": course_info.merlot_url
            },
            "educationalContext": {
                "level": course_info.level,
                "subjects": course_info.subjects,
                "typicalAgeRange": _level_to_age_range(course_info.level)
            },
            "lifecycle": {
                "status": "published",
                "created": course_info.date_created,
                "modified": course_info.date_modified,
                "importedFrom": "merlot",
                "importedAt": datetime.utcnow().isoformat()
            },
            "keywords": course_info.keywords
        },
        "content": extracted_content.to_umcf_content(),
        "extensions": {
            "merlot": {
                "materialId": course_info.course_id,
                "materialType": course_info.material_type,
                "peerReviewRating": course_info.peer_review_rating,
                "userRating": course_info.user_rating,
                "merlotAttribution": (
                    "Reproduced with permission from MERLOT - the Multimedia "
                    "Resource for Learning Online and Teaching (www.merlot.org). "
                    "Some rights reserved."
                )
            }
        }
    }
```

---

## Content Extraction Strategy

### Priority Order

1. **Open Textbooks** - Complete, structured, ideal for tutoring
2. **Tutorials** - Step-by-step content, voice-friendly
3. **Lecture transcripts** - Spoken content, easy to adapt
4. **Reference materials** - Factual content for Q&A

### Source-Specific Strategies

| Source Domain | Strategy |
|---------------|----------|
| **openstax.org** | Use OpenStax API (already planned) |
| **libretexts.org** | HTML scraping with section detection |
| **pressbooks.com** | EPUB export if available |
| **oercommons.org** | Metadata + source redirect |
| **YouTube** | Transcript extraction via API |
| **PDF sources** | PDF parsing with structure detection |
| **Generic HTML** | Readability extraction + structure inference |

### Content Quality Gates

Before generating UMCF:

1. **License verified** - CC license without ND
2. **Content accessible** - URL returns 200, content extractable
3. **Minimum length** - At least 500 words of content
4. **Language match** - Content matches declared language
5. **Structure present** - Headings or sections detected

---

## Error Handling

### API Errors

| Error | Response | Recovery |
|-------|----------|----------|
| 401 Unauthorized | Invalid/expired API key | Refresh key, notify admin |
| 429 Rate Limited | Too many requests | Exponential backoff |
| 500 Server Error | MERLOT service issue | Retry with backoff |
| Timeout | Slow response | Retry once, then skip |

### Content Fetch Errors

| Error | Response | Recovery |
|-------|----------|----------|
| 404 Not Found | Material URL dead | Mark as unavailable, report to MERLOT |
| 403 Forbidden | Access denied | Skip, log for review |
| Paywall detected | Content behind login | Skip, mark as inaccessible |
| PDF extraction failed | Corrupted/scanned PDF | Try OCR or skip |
| HTML extraction failed | JavaScript-heavy site | Skip, mark for manual review |

### Logging

```python
logger.info(f"MERLOT search: query={query}, results={count}")
logger.warning(f"MERLOT material {id} has unclear license: {license}")
logger.error(f"MERLOT API error: {status_code} - {message}")
logger.info(f"MERLOT content fetched: {url}, size={size}KB")
```

---

## Testing Strategy

### Unit Tests

```python
class TestMerlotHandler:

    def test_license_filtering_rejects_nd(self):
        """ND licenses must be rejected."""
        handler = MerlotHandler(api_key="test")
        assert not handler._is_allowed_license("CC BY-ND")
        assert not handler._is_allowed_license("CC BY-NC-ND")

    def test_license_filtering_accepts_sa(self):
        """SA licenses should be accepted."""
        handler = MerlotHandler(api_key="test")
        assert handler._is_allowed_license("CC BY-SA")
        assert handler._is_allowed_license("CC BY-NC-SA")

    def test_license_filtering_rejects_unclear(self):
        """Unclear licenses must be rejected."""
        handler = MerlotHandler(api_key="test")
        assert not handler._is_allowed_license("unsure")
        assert not handler._is_allowed_license("")
        assert not handler._is_allowed_license(None)
```

### Integration Tests

```python
@pytest.mark.integration
async def test_merlot_search_returns_results():
    """Live search should return CC-licensed materials."""
    handler = MerlotHandler(api_key=os.environ["MERLOT_API_KEY"])
    results = []
    async for course in handler.search_courses(
        query="calculus",
        material_type="Open Textbook",
        min_rating=3.0
    ):
        results.append(course)
        if len(results) >= 5:
            break
    assert len(results) > 0
    for course in results:
        assert "ND" not in course.license
```

### Manual Testing Checklist

- [ ] API key obtained and working
- [ ] Search returns results
- [ ] License filtering excludes ND
- [ ] Quality filtering works (min rating)
- [ ] Content fetch succeeds for sample URLs
- [ ] Attribution text generated correctly
- [ ] UMCF validates against schema

---

## Implementation Timeline

### Phase 1: API Integration (Week 1)

- [ ] Obtain MERLOT API license key
- [ ] Implement basic search endpoint
- [ ] Implement license filtering
- [ ] Add to source browser UI

### Phase 2: Content Discovery (Week 2)

- [ ] Implement material type filtering
- [ ] Add quality filtering (ratings)
- [ ] Build subject category browser
- [ ] Cache search results

### Phase 3: Content Extraction (Weeks 3-4)

- [ ] Implement generic HTML extractor
- [ ] Implement PDF extractor
- [ ] Add source-specific extractors for common domains
- [ ] Build content quality gates

### Phase 4: UMCF Generation (Week 5)

- [ ] Implement UMCF generator
- [ ] Add attribution generation
- [ ] Integrate with AI enrichment pipeline
- [ ] Validate against UMCF schema

### Phase 5: Testing & Polish (Week 6)

- [ ] Complete unit test coverage
- [ ] Run integration tests
- [ ] Performance optimization
- [ ] Documentation

---

## Appendix A: Sample API Responses

### Search Response

```json
{
  "results": 1523,
  "page": 1,
  "pageSize": 10,
  "materials": [
    {
      "materialId": 12345,
      "title": "Introduction to Calculus",
      "description": "A comprehensive introduction to differential calculus...",
      "author": "John Smith",
      "authorInstitution": "State University",
      "url": "https://example.edu/calculus-textbook",
      "creativeCommons": "CC BY",
      "category": "Mathematics and Statistics",
      "materialType": "Open Textbook",
      "audience": "College/Lower Division",
      "peerReviewRating": 4.5,
      "userRating": 4.2,
      "language": "English",
      "dateCreated": "2023-01-15",
      "dateModified": "2024-06-20",
      "keywords": "calculus, derivatives, integrals, mathematics"
    }
  ]
}
```

---

## Appendix B: MERLOT Contact Information

- **Web Services Request:** https://www.merlot.org/merlot/signWebServicesForm.htm
- **General Contact:** webmaster@merlot.org
- **Licensing Questions:** webmaster@merlot.org
- **DMCA/Copyright:** Follow DMCA procedures on their site

---

## Appendix C: References

- [MERLOT Policies and Practices](https://info.merlot.org/merlothelp/Policies_and_Practices.htm)
- [MERLOT Web Services](https://info.merlot.org/merlothelp/MERLOT_Technologies.htm)
- [Creative Commons License Types](https://creativecommons.org/licenses/)
- [UMCF Specification](../spec/UMCF_SPECIFICATION.md)
