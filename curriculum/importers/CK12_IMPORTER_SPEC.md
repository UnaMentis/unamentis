# CK-12 FlexBook Importer Specification

**Version:** 1.0.0
**Status:** Draft
**Date:** 2025-12-17
**Target Audience:** K-12 (8th Grade Focus)

---

## Table of Contents

1. [Overview](#overview)
2. [CK-12 Platform Analysis](#ck-12-platform-analysis)
3. [Supported Formats](#supported-formats)
4. [Data Mapping](#data-mapping)
5. [Implementation Specification](#implementation-specification)
6. [Grade Level Alignment](#grade-level-alignment)
7. [Content Extraction](#content-extraction)
8. [Assessment Handling](#assessment-handling)
9. [Error Handling](#error-handling)
10. [Testing Strategy](#testing-strategy)

---

## Overview

The CK-12 importer converts CK-12 FlexBook content into VLCF format for use with VoiceLearn's conversational AI tutoring system. CK-12 is a nonprofit organization providing free, high-quality K-12 educational content with comprehensive coverage across math, science, ELA, and social studies.

### Why CK-12?

| Criterion | Assessment |
|-----------|------------|
| **License** | CC-BY-NC (Creative Commons Attribution-NonCommercial) |
| **Cost** | Free |
| **Quality** | Vetted, standards-aligned, used by millions |
| **Formats** | EPUB, PDF, HTML (all parseable) |
| **8th Grade Coverage** | Complete: Pre-Algebra, Physical Science, Life Science, ELA, Civics |
| **Standards Alignment** | Common Core, NGSS, state standards |
| **Modular Structure** | Chapters → Lessons → Sections (maps to VLCF hierarchy) |

### Import Scope

**In Scope:**
- FlexBooks in EPUB format (primary)
- FlexBooks in PDF format (fallback)
- HTML exports from CK-12 library
- Interactive practice problems (where extractable)
- Vocabulary and glossary terms

**Out of Scope:**
- Interactive simulations (PLIX) - URL references only
- Video content - URL references only
- Adaptive practice (requires CK-12 API, may add later)
- User data (progress, bookmarks)

---

## CK-12 Platform Analysis

### Content Organization

CK-12 organizes content in a clear hierarchy that maps well to VLCF:

```
FlexBook
├── Front Matter (Title, Description, Credits)
├── Chapter 1
│   ├── Lesson 1.1
│   │   ├── Section: Introduction
│   │   ├── Section: Core Content
│   │   ├── Section: Examples
│   │   ├── Section: Practice Problems
│   │   └── Section: Summary/Review
│   ├── Lesson 1.2
│   └── ...
├── Chapter 2
└── Back Matter (Glossary, Index, Appendix)
```

### FlexBook Types

| Type | Description | VLCF Mapping |
|------|-------------|--------------|
| **Textbook** | Full course content | Complete curriculum |
| **Concept** | Single topic deep-dive | Module or topic |
| **Study Guide** | Condensed review material | Review module |

### 8th Grade FlexBooks (Primary Targets)

| Subject | FlexBook Title | CK-12 ID |
|---------|---------------|----------|
| **Math** | CK-12 Pre-Algebra | 8th-pre-algebra |
| **Math** | CK-12 8th Grade Math | 8th-grade-math |
| **Science** | CK-12 Physical Science for Middle School | ms-physical-science |
| **Science** | CK-12 Life Science for Middle School | ms-life-science |
| **Science** | CK-12 Earth Science for Middle School | ms-earth-science |
| **ELA** | CK-12 8th Grade ELA | 8th-ela |
| **Social Studies** | CK-12 Civics | civics |

---

## Supported Formats

### Primary: EPUB

EPUB is the preferred format because:
- Structured XML (OPF manifest, NCX navigation)
- Clean HTML content with consistent markup
- Embedded images and resources
- Machine-readable table of contents
- Smaller file sizes than PDF

### Secondary: PDF

PDF as fallback when EPUB unavailable:
- Text extraction via pure Python (pdfminer.six)
- Structure inference from headings/fonts
- Less accurate than EPUB
- Larger files

### Tertiary: HTML

Direct HTML from CK-12 library:
- Available via web scraping (respect robots.txt)
- Most up-to-date content
- Requires URL-based access

---

## Data Mapping

### Metadata Mapping

| CK-12 Element | VLCF Field | Notes |
|---------------|------------|-------|
| `<dc:title>` | `title` | Book title |
| `<dc:creator>` | `lifecycle.contributors[].name` | Authors |
| `<dc:publisher>` | `lifecycle.contributors[].name` | CK-12 Foundation |
| `<dc:description>` | `description` | Book description |
| `<dc:subject>` | `metadata.keywords[]` | Subject tags |
| `<dc:rights>` | `rights.license` | CC-BY-NC |
| `<dc:language>` | `metadata.language` | en-US |
| `<dc:identifier>` | `id.value` | ISBN or CK-12 ID |
| NCX `<navMap>` | `content[]` hierarchy | Table of contents |

### Content Hierarchy Mapping

| CK-12 Level | VLCF Type | Example |
|-------------|-----------|---------|
| FlexBook | Root curriculum | "CK-12 Pre-Algebra" |
| Chapter | `module` | "Chapter 1: Numbers" |
| Lesson | `topic` | "1.1 Integer Operations" |
| Section | `topic` (child) | "Adding Integers" |
| Paragraph | `transcript.segments[]` | Content text |

### Educational Context Mapping

| CK-12 Metadata | VLCF Field | Transformation |
|----------------|------------|----------------|
| Grade Level | `educational.audience.gradeLevel` | Extract from metadata |
| Subject | `metadata.keywords[]` | Direct mapping |
| Reading Level | `educational.audience.educationalLevel` | Map to audience level |
| Standards | `educational.alignment[]` | Parse standard codes |

### Assessment Mapping

| CK-12 Question Type | VLCF Assessment Type | Notes |
|---------------------|---------------------|-------|
| Multiple Choice | `choice` | Direct mapping |
| True/False | `choice` | 2-option choice |
| Fill in Blank | `text-entry` | Requires text input |
| Matching | `choice` (expanded) | Each pair as separate question |
| Short Answer | `text-entry` | Free text response |

---

## Implementation Specification

### Module Structure

```python
vlcf_importer/
└── importers/
    └── ck12/
        ├── __init__.py
        ├── importer.py          # Main CK12Importer class
        ├── epub_parser.py       # EPUB-specific parsing
        ├── content_extractor.py # HTML to transcript conversion
        ├── quiz_extractor.py    # Practice problem extraction
        ├── standards_mapper.py  # Common Core/NGSS alignment
        └── models.py            # CK12-specific data models
```

### CK12Importer Class

```python
from vlcf_importer.core.base import CurriculumImporter, ValidationResult
from vlcf_importer.core.models import CurriculumData
from typing import Dict, Any, List, Optional
from pathlib import Path
import zipfile

class CK12Importer(CurriculumImporter):
    """
    Importer for CK-12 FlexBook content.

    Supports EPUB, PDF, and HTML formats from the CK-12 library.
    Primary focus: 8th grade content for comprehensive K-12 coverage.
    """

    name = "ck12"
    description = "Import CK-12 FlexBooks (EPUB, PDF, HTML)"
    file_extensions = [".epub", ".pdf", ".html", ".htm"]

    # CK-12 specific configuration
    DEFAULT_CONFIG = {
        "extract_quizzes": True,
        "extract_vocabulary": True,
        "extract_standards": True,
        "include_examples": True,
        "target_grade": 8,
        "spoken_text_simplification": True,
        "checkpoint_frequency": "per_section",  # per_paragraph, per_section, per_lesson
    }

    def __init__(
        self,
        storage: "StorageBackend",
        config: Optional[Dict[str, Any]] = None,
        logger: Optional["Logger"] = None
    ):
        super().__init__(storage, config, logger)
        self.config = {**self.DEFAULT_CONFIG, **(config or {})}

        # Initialize sub-parsers
        self._epub_parser = None
        self._content_extractor = None
        self._quiz_extractor = None
        self._standards_mapper = None

    async def validate(self, content: bytes) -> ValidationResult:
        """
        Validate CK-12 content format.

        Checks:
        - Valid EPUB/PDF structure
        - CK-12 metadata present
        - Required chapters/lessons exist
        """
        errors = []
        warnings = []
        metadata = {}

        # Detect format
        format_type = self._detect_format(content)
        metadata["format"] = format_type

        if format_type == "epub":
            return await self._validate_epub(content)
        elif format_type == "pdf":
            return await self._validate_pdf(content)
        elif format_type == "html":
            return await self._validate_html(content)
        else:
            return ValidationResult(
                is_valid=False,
                errors=["Unknown or unsupported file format"],
                format_version=None,
                metadata={"detected_bytes": content[:20].hex()}
            )

    def _detect_format(self, content: bytes) -> str:
        """Detect file format from magic bytes"""
        if content[:4] == b'PK\x03\x04':  # ZIP/EPUB
            return "epub"
        elif content[:5] == b'%PDF-':
            return "pdf"
        elif content[:5].lower() in (b'<!doc', b'<html', b'<?xml'):
            return "html"
        return "unknown"

    async def _validate_epub(self, content: bytes) -> ValidationResult:
        """Validate EPUB structure"""
        errors = []
        warnings = []
        metadata = {"format": "epub"}

        try:
            # Check ZIP structure
            import io
            with zipfile.ZipFile(io.BytesIO(content)) as zf:
                namelist = zf.namelist()

                # EPUB must have mimetype
                if "mimetype" not in namelist:
                    errors.append("Missing mimetype file (not a valid EPUB)")
                else:
                    mimetype = zf.read("mimetype").decode().strip()
                    if mimetype != "application/epub+zip":
                        warnings.append(f"Unexpected mimetype: {mimetype}")

                # Check for OPF manifest
                opf_files = [n for n in namelist if n.endswith(".opf")]
                if not opf_files:
                    errors.append("Missing OPF manifest")
                else:
                    metadata["opf_path"] = opf_files[0]

                # Check for NCX (navigation)
                ncx_files = [n for n in namelist if n.endswith(".ncx")]
                if not ncx_files:
                    warnings.append("Missing NCX navigation (older EPUB format)")

                # Look for CK-12 markers
                for name in namelist:
                    if "ck12" in name.lower() or "flexbook" in name.lower():
                        metadata["ck12_confirmed"] = True
                        break

                metadata["file_count"] = len(namelist)

        except zipfile.BadZipFile:
            errors.append("Invalid ZIP/EPUB file structure")
        except Exception as e:
            errors.append(f"EPUB validation error: {str(e)}")

        return ValidationResult(
            is_valid=len(errors) == 0,
            errors=errors,
            warnings=warnings,
            format_version="EPUB 2.0/3.0",
            metadata=metadata
        )

    async def extract(self, content: bytes) -> Dict[str, Any]:
        """
        Extract raw CK-12 structure before VLCF transformation.

        Returns intermediate representation with:
        - Metadata from OPF
        - Navigation from NCX
        - Raw HTML content per chapter
        - Quiz questions if present
        """
        format_type = self._detect_format(content)

        if format_type == "epub":
            return await self._extract_epub(content)
        elif format_type == "pdf":
            return await self._extract_pdf(content)
        else:
            return await self._extract_html(content)

    async def _extract_epub(self, content: bytes) -> Dict[str, Any]:
        """Extract data from EPUB format"""
        import io
        from xml.etree import ElementTree as ET

        result = {
            "format": "epub",
            "metadata": {},
            "navigation": [],
            "chapters": [],
            "glossary": [],
            "quizzes": []
        }

        with zipfile.ZipFile(io.BytesIO(content)) as zf:
            # Find and parse OPF
            opf_path = self._find_opf(zf)
            if opf_path:
                opf_content = zf.read(opf_path).decode('utf-8')
                result["metadata"] = self._parse_opf_metadata(opf_content)
                result["spine"] = self._parse_opf_spine(opf_content)

            # Find and parse NCX
            ncx_path = self._find_ncx(zf)
            if ncx_path:
                ncx_content = zf.read(ncx_path).decode('utf-8')
                result["navigation"] = self._parse_ncx(ncx_content)

            # Extract content from spine
            for item in result.get("spine", []):
                try:
                    html_content = zf.read(item["href"]).decode('utf-8')
                    chapter_data = self._parse_chapter_html(html_content, item)
                    result["chapters"].append(chapter_data)
                except Exception as e:
                    self.logger.warning(f"Failed to parse {item['href']}: {e}")

            # Extract glossary if present
            glossary_path = self._find_glossary(zf)
            if glossary_path:
                glossary_content = zf.read(glossary_path).decode('utf-8')
                result["glossary"] = self._parse_glossary(glossary_content)

        return result

    async def parse(self, content: bytes) -> CurriculumData:
        """
        Parse CK-12 content and transform to VLCF format.

        Full pipeline:
        1. Extract raw structure
        2. Map metadata to VLCF
        3. Convert chapters to content nodes
        4. Extract and map assessments
        5. Build glossary
        6. Generate spoken text variants
        """
        # Step 1: Extract
        raw = await self.extract(content)

        # Step 2: Build VLCF structure
        vlcf = {
            "vlcf": "1.0.0",
            "id": self._generate_id(raw),
            "title": raw["metadata"].get("title", "Untitled FlexBook"),
            "description": raw["metadata"].get("description", ""),
            "version": {
                "number": "1.0.0",
                "date": raw["metadata"].get("date", None)
            },
            "lifecycle": self._build_lifecycle(raw["metadata"]),
            "metadata": self._build_metadata(raw["metadata"]),
            "educational": self._build_educational(raw["metadata"]),
            "rights": self._build_rights(raw["metadata"]),
            "content": [],
            "glossary": self._transform_glossary(raw.get("glossary", []))
        }

        # Step 3: Transform chapters to content nodes
        for chapter in raw["chapters"]:
            content_node = await self._transform_chapter(chapter)
            vlcf["content"].append(content_node)

        return CurriculumData(**vlcf)

    async def _transform_chapter(self, chapter: Dict) -> Dict:
        """Transform a chapter to VLCF content node"""
        node = {
            "id": {"value": self._slugify(chapter["title"])},
            "title": chapter["title"],
            "type": "module",
            "orderIndex": chapter.get("order", 0),
            "description": chapter.get("description"),
            "children": []
        }

        # Transform lessons
        for lesson in chapter.get("lessons", []):
            lesson_node = await self._transform_lesson(lesson)
            node["children"].append(lesson_node)

        # Add chapter-level assessments
        if chapter.get("quizzes"):
            node["assessments"] = self._transform_quizzes(chapter["quizzes"])

        return node

    async def _transform_lesson(self, lesson: Dict) -> Dict:
        """Transform a lesson to VLCF topic node"""
        node = {
            "id": {"value": self._slugify(lesson["title"])},
            "title": lesson["title"],
            "type": "topic",
            "orderIndex": lesson.get("order", 0),
            "transcript": await self._build_transcript(lesson),
            "children": []
        }

        # Add learning objectives if extractable
        if lesson.get("objectives"):
            node["learningObjectives"] = [
                {
                    "id": {"value": f"obj-{i}"},
                    "text": obj,
                    "bloomLevel": self._infer_bloom_level(obj)
                }
                for i, obj in enumerate(lesson["objectives"])
            ]

        # Transform sections as child topics
        for section in lesson.get("sections", []):
            section_node = await self._transform_section(section)
            node["children"].append(section_node)

        # Add lesson-level assessments
        if lesson.get("practice_problems"):
            node["assessments"] = self._transform_quizzes(lesson["practice_problems"])

        # Add examples
        if lesson.get("examples"):
            node["examples"] = [
                {
                    "type": "worked_problem" if ex.get("solution") else "demonstration",
                    "title": ex.get("title", f"Example {i+1}"),
                    "content": ex["content"],
                    "solution": ex.get("solution")
                }
                for i, ex in enumerate(lesson["examples"])
            ]

        return node

    async def _build_transcript(self, lesson: Dict) -> Dict:
        """Build VLCF transcript from lesson content"""
        segments = []

        for i, para in enumerate(lesson.get("paragraphs", [])):
            segment = {
                "id": f"seg-{i}",
                "text": para["text"],
                "type": self._classify_segment_type(para),
            }

            # Generate spoken text variant if configured
            if self.config.get("spoken_text_simplification"):
                segment["spokenText"] = self._simplify_for_speech(para["text"])

            # Add stopping point for comprehension checks
            if self._should_add_checkpoint(i, para):
                segment["stoppingPoint"] = {
                    "type": "check_understanding",
                    "prompt": self._generate_checkpoint_prompt(para)
                }

            segments.append(segment)

        return {
            "segments": segments,
            "totalDuration": self._estimate_duration(segments)
        }

    def _simplify_for_speech(self, text: str) -> str:
        """
        Simplify text for text-to-speech.

        Transformations:
        - Expand abbreviations
        - Spell out symbols
        - Simplify complex sentences
        - Add natural pauses (commas)
        """
        import re

        result = text

        # Expand common abbreviations
        abbreviations = {
            r'\be\.g\.\b': 'for example',
            r'\bi\.e\.\b': 'that is',
            r'\betc\.\b': 'and so on',
            r'\bvs\.\b': 'versus',
            r'\bFig\.\b': 'Figure',
            r'\beq\.\b': 'equation',
        }
        for pattern, replacement in abbreviations.items():
            result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)

        # Spell out mathematical symbols
        symbols = {
            '=': ' equals ',
            '+': ' plus ',
            '-': ' minus ',
            '×': ' times ',
            '÷': ' divided by ',
            '<': ' is less than ',
            '>': ' is greater than ',
            '≤': ' is less than or equal to ',
            '≥': ' is greater than or equal to ',
            '≠': ' is not equal to ',
            '%': ' percent',
        }
        for symbol, replacement in symbols.items():
            result = result.replace(symbol, replacement)

        return result.strip()

    def _transform_quizzes(self, quizzes: List[Dict]) -> List[Dict]:
        """Transform CK-12 quiz questions to VLCF assessments"""
        assessments = []

        for q in quizzes:
            assessment = {
                "id": {"value": q.get("id", self._generate_uuid())},
                "type": self._map_question_type(q["type"]),
                "prompt": q["question"]
            }

            if q["type"] in ("multiple_choice", "true_false"):
                assessment["choices"] = [
                    {
                        "id": chr(97 + i),  # a, b, c, d...
                        "text": choice["text"],
                        "correct": choice.get("correct", False)
                    }
                    for i, choice in enumerate(q["choices"])
                ]

            if q.get("explanation"):
                assessment["feedback"] = {
                    "correct": q["explanation"],
                    "incorrect": q.get("hint", "Try again!")
                }

            assessments.append(assessment)

        return assessments

    def _map_question_type(self, ck12_type: str) -> str:
        """Map CK-12 question type to VLCF assessment type"""
        mapping = {
            "multiple_choice": "choice",
            "true_false": "choice",
            "fill_blank": "text-entry",
            "short_answer": "text-entry",
            "matching": "choice",  # Expand to multiple
        }
        return mapping.get(ck12_type, "text-entry")

    def _build_educational(self, metadata: Dict) -> Dict:
        """Build VLCF educational context from CK-12 metadata"""
        grade = self.config.get("target_grade", 8)

        return {
            "audience": {
                "type": "learner",
                "gradeLevel": {
                    "min": str(grade),
                    "max": str(grade)
                },
                "educationalLevel": "middle-school" if grade <= 8 else "high-school",
                "prerequisites": metadata.get("prerequisites", [])
            },
            "alignment": self._extract_standards(metadata),
            "duration": {
                "estimated": self._estimate_total_duration(metadata),
                "unit": "hours"
            }
        }

    def _extract_standards(self, metadata: Dict) -> List[Dict]:
        """Extract and map educational standards"""
        alignments = []

        # Look for Common Core in metadata
        cc_standards = metadata.get("common_core", [])
        for standard in cc_standards:
            alignments.append({
                "framework": "Common Core State Standards",
                "frameworkUrl": "http://www.corestandards.org/",
                "targetName": standard["code"],
                "targetDescription": standard.get("description", ""),
                "targetUrl": f"http://www.corestandards.org/Math/Content/{standard['code']}/"
            })

        # Look for NGSS in metadata
        ngss_standards = metadata.get("ngss", [])
        for standard in ngss_standards:
            alignments.append({
                "framework": "Next Generation Science Standards",
                "frameworkUrl": "https://www.nextgenscience.org/",
                "targetName": standard["code"],
                "targetDescription": standard.get("description", "")
            })

        return alignments

    def _build_rights(self, metadata: Dict) -> Dict:
        """Build VLCF rights from CK-12 license"""
        return {
            "license": {
                "type": "CC-BY-NC-3.0",
                "name": "Creative Commons Attribution-NonCommercial 3.0",
                "url": "https://creativecommons.org/licenses/by-nc/3.0/",
                "permissions": ["share", "adapt"],
                "conditions": ["attribution", "noncommercial"]
            },
            "attribution": {
                "required": True,
                "format": "Content from CK-12 Foundation (www.ck12.org), licensed under CC-BY-NC."
            },
            "holder": {
                "name": "CK-12 Foundation",
                "url": "https://www.ck12.org/"
            }
        }

    # Helper methods
    def _slugify(self, text: str) -> str:
        """Convert text to URL-safe slug"""
        import re
        slug = text.lower()
        slug = re.sub(r'[^\w\s-]', '', slug)
        slug = re.sub(r'[\s_]+', '-', slug)
        return slug.strip('-')

    def _generate_uuid(self) -> str:
        """Generate a UUID string"""
        from uuid import uuid4
        return str(uuid4())

    def _generate_id(self, raw: Dict) -> Dict:
        """Generate VLCF ID from CK-12 metadata"""
        isbn = raw["metadata"].get("isbn")
        if isbn:
            return {"catalog": "ISBN", "value": isbn}

        ck12_id = raw["metadata"].get("identifier")
        if ck12_id:
            return {"catalog": "CK-12", "value": ck12_id}

        return {"catalog": "UUID", "value": self._generate_uuid()}

    def _infer_bloom_level(self, objective: str) -> str:
        """Infer Bloom's taxonomy level from learning objective text"""
        objective_lower = objective.lower()

        bloom_keywords = {
            "create": ["design", "create", "construct", "develop", "formulate", "propose"],
            "evaluate": ["evaluate", "judge", "assess", "critique", "justify", "defend"],
            "analyze": ["analyze", "compare", "contrast", "differentiate", "examine", "investigate"],
            "apply": ["apply", "use", "solve", "demonstrate", "calculate", "compute"],
            "understand": ["understand", "explain", "describe", "summarize", "interpret", "classify"],
            "remember": ["remember", "recall", "identify", "list", "name", "define", "recognize"]
        }

        for level, keywords in bloom_keywords.items():
            if any(kw in objective_lower for kw in keywords):
                return level

        return "understand"  # Default
```
