# Una Mentis Curriculum Format (UMCF)

**A Standards-Based Curriculum Format for Conversational AI Tutoring**

[![Version](https://img.shields.io/badge/version-1.0.0--draft-blue.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()
[![Status](https://img.shields.io/badge/status-specification--complete-yellow.svg)]()

---

## Executive Summary

The Una Mentis Curriculum Format (UMCF) is a JSON-based specification for representing educational content optimized for **conversational AI tutoring**. Unlike traditional e-learning formats designed for Learning Management Systems (LMS), UMCF is purpose-built for voice-first, real-time tutoring interactions.

**Key Differentiators:**
- **Voice-native**: Every text field has optional `spokenText` variants optimized for TTS
- **Tutoring-first**: Stopping points, comprehension checks, misconception handling
- **Standards-grounded**: Full traceability to 10+ established educational standards
- **Unlimited hierarchy**: Topics nest to any depth (not limited like SCORM)
- **AI-enrichment ready**: Designed for automated content enhancement

---

## Table of Contents

1. [Vision & Philosophy](#vision--philosophy)
2. [Who This Is For](#who-this-is-for)
3. [What Makes UMCF Different](#what-makes-umcf-different)
4. [Standards Foundation](#standards-foundation)
5. [Specification Overview](#specification-overview)
6. [Import System](#import-system)
7. [AI Enrichment Pipeline](#ai-enrichment-pipeline)
8. [Repository Structure](#repository-structure)
9. [Current Status](#current-status)
10. [Future Direction](#future-direction)
11. [Getting Started](#getting-started)
12. [Contributing](#contributing)

---

## Vision & Philosophy

### The Problem

Existing curriculum standards (SCORM, xAPI, IMSCC) were designed for a different era:
- **LMS-centric**: Optimized for packaging and delivery through course management systems
- **Click-based interaction**: Designed for mouse/keyboard, not voice
- **Static content**: No support for dynamic, conversational tutoring
- **Limited hierarchy**: SCORM caps at ~4 levels of nesting

Modern AI tutors need:
- **Conversational delivery**: Content chunked for turn-by-turn dialogue
- **Comprehension verification**: Natural stopping points for understanding checks
- **Adaptive depth**: Multiple explanation styles for different learners
- **Voice optimization**: Text that sounds natural when spoken

### The Solution: Hub-and-Spoke Architecture

UMCF serves as the **canonical internal format** for tutoring systems, with established standards as import/export "spokes":

```
                    ┌─────────────┐
                    │   SCORM     │
                    │   IMSCC     │
                    │   QTI       │
                    └──────┬──────┘
                           │ Import
                           ▼
┌─────────────────────────────────────────────────────┐
│                       UMCF                           │
│              (Canonical Format)                      │
│                                                      │
│  • Conversational AI optimized                      │
│  • Voice-first design                               │
│  • Unlimited hierarchy                              │
│  • Rich tutoring metadata                           │
└─────────────────────────────────────────────────────┘
                           │
                           │ Tutoring Engine
                           ▼
                ┌─────────────────────┐
                │   UnaMentis App    │
                │   (or any tutor)    │
                └─────────────────────┘
```

### Design Principles

1. **Standards-based, not standards-bound**: Borrow proven patterns, innovate where needed
2. **Voice-native, not voice-adapted**: Designed for speech from the ground up
3. **Tutoring-first, not LMS-first**: Optimized for learning, not administration
4. **AI-ready**: Structured for automated enrichment and generation
5. **Future-proof**: Extension mechanisms for capabilities not yet imagined

---

## Who This Is For

### Primary Audiences

| Audience | Interest |
|----------|----------|
| **Educational Technologists** | Researchers and practitioners building next-generation learning systems |
| **AI/ML Educators** | Those creating AI tutoring systems who need structured content |
| **Curriculum Designers** | Instructional designers wanting voice-first content |
| **EdTech Developers** | Engineers building tutoring platforms |
| **Learning Scientists** | Researchers studying conversational learning |

### Academic Evaluation

This specification was developed with academic rigor and is suitable for evaluation by:
- Educational technology faculty
- Learning science researchers
- Instructional design professionals
- E-learning standards committees

The [Standards Traceability Document](spec/STANDARDS_TRACEABILITY.md) provides field-by-field mappings to established standards for scholarly review.

---

## What Makes UMCF Different

### Comparison with Existing Standards

| Feature | SCORM | xAPI | IMSCC | **UMCF** |
|---------|-------|------|-------|----------|
| **Primary use** | LMS delivery | Activity tracking | Content exchange | **Conversational tutoring** |
| **Content depth** | 3-4 levels | N/A | 2-3 levels | **Unlimited** |
| **Voice support** | None | None | None | **Native** |
| **Stopping points** | None | Verbs only | None | **Rich metadata** |
| **Misconceptions** | None | None | None | **Trigger + remediation** |
| **Alternative explanations** | None | None | None | **Multiple variants** |
| **AI enrichment** | N/A | N/A | N/A | **Purpose-built** |

### Novel Elements in UMCF

These elements are **not borrowed from any standard**—they are innovations for conversational tutoring:

1. **Transcript Segments with Stopping Points**
   ```json
   {
     "segments": [
       {
         "text": "The mitochondria produces ATP through cellular respiration.",
         "spokenText": "The mitochondria produces A T P through cellular respiration.",
         "stoppingPoint": {
           "type": "check_understanding",
           "prompt": "Can you explain what the mitochondria does?",
           "expectedConcepts": ["energy", "ATP", "cell"]
         }
       }
     ]
   }
   ```

2. **Alternative Explanations**
   ```json
   {
     "alternatives": {
       "simpler": "The mitochondria is like a tiny power plant inside each cell.",
       "technical": "Mitochondria are double-membraned organelles that generate ATP via oxidative phosphorylation.",
       "analogy": "Think of mitochondria as the batteries that keep your cells running."
     }
   }
   ```

3. **Misconception Handling**
   ```json
   {
     "misconceptions": [
       {
         "description": "Student thinks mitochondria only exist in animal cells",
         "triggerPhrases": ["only animals", "plants don't have"],
         "remediation": "Actually, both plant and animal cells have mitochondria...",
         "correctUnderstanding": "Mitochondria are found in all eukaryotic cells."
       }
     ]
   }
   ```

4. **Tutoring Configuration**
   ```json
   {
     "tutoringConfig": {
       "depth": "standard",
       "interactionMode": "socratic",
       "scaffoldingLevel": "moderate",
       "checkpointFrequency": "per_concept"
     }
   }
   ```

---

## Standards Foundation

UMCF is built on a foundation of established educational standards:

| Standard | What We Borrow | UMCF Usage |
|----------|----------------|------------|
| **IEEE LOM** (1484.12.1) | Metadata categories, lifecycle | Core metadata structure |
| **LRMI** (Schema.org) | Educational alignment, audience | `educational` block |
| **Dublin Core** | Title, creator, rights, language | Top-level fields |
| **SCORM** | Sequencing, completion tracking | Navigation hints |
| **xAPI** | Activity verbs, extensions | Assessment tracking |
| **CASE** (1EdTech) | Competency framework, objectives | `learningObjectives` |
| **QTI 3.0** | Assessment items, scoring | `assessments` array |
| **Open Badges 3.0** | Certification, criteria | `compliance.certification` |
| **Creative Commons** | License vocabulary | `rights.license` |
| **ISO 8601** | Duration, dates | All time fields |

### Traceability Statistics

From the [Standards Traceability Document](spec/STANDARDS_TRACEABILITY.md):

- **Total fields**: 152
- **Standards-derived**: 82 (54%)
- **UMCF-native**: 70 (46%)

The native fields are specifically designed for conversational tutoring—capabilities that don't exist in traditional standards.

---

## Specification Overview

### Document Structure

```
UMCF Document
│
├── umcf: "1.0.0"              # Format version
├── id                          # Unique identifier (UUID/ISBN/DOI)
├── title                       # Human-readable title
├── description                 # Overview
├── version                     # Content version
│
├── lifecycle                   # Status, contributors, dates
├── metadata                    # Language, keywords, structure
├── educational                 # Audience, alignment, duration
├── rights                      # License, attribution
├── compliance                  # Certification (optional)
│
├── content[]                   # Hierarchical content tree
│   └── contentNode             # Recursive structure
│       ├── id, title, type
│       ├── learningObjectives[]
│       ├── transcript          # Voice-optimized content
│       ├── examples[]
│       ├── assessments[]
│       ├── misconceptions[]
│       ├── tutoringConfig
│       └── children[]          # Nested nodes (unlimited)
│
├── glossary[]                  # Term definitions
└── extensions                  # Namespaced extensions
```

### Content Node Types

| Type | Description | Example |
|------|-------------|---------|
| `module` | Major section | "Chapter 1: Introduction" |
| `topic` | Teachable unit | "1.1 Basic Concepts" |
| `activity` | Interactive element | "Practice Exercise" |
| `assessment` | Evaluation | "Quiz: Key Terms" |
| `resource` | Reference material | "Additional Reading" |

### Key Files

| File | Description |
|------|-------------|
| [spec/umcf-schema.json](spec/umcf-schema.json) | JSON Schema (Draft 2020-12) |
| [spec/UMCF_SPECIFICATION.md](spec/UMCF_SPECIFICATION.md) | Human-readable specification |
| [spec/UMCF_FILE_FORMAT.md](spec/UMCF_FILE_FORMAT.md) | File format specification (.umcf/.umcfz) |
| [spec/STANDARDS_TRACEABILITY.md](spec/STANDARDS_TRACEABILITY.md) | Field-by-field standards mapping |

---

## File Formats

UMCF supports two file formats for storage and interchange:

| Extension | Format | Use Case |
|-----------|--------|----------|
| `.umcf` | Raw JSON | Development, version control, editing |
| `.umcfz` | Compressed | Distribution, sharing, offline use with bundled assets |

### Raw Format (.umcf)

Plain JSON files following the UMCF schema. Human-readable and Git-friendly.

```json
{
  "umcf": "1.0.0",
  "id": { "value": "my-curriculum-001" },
  "title": "Introduction to Machine Learning",
  "content": [...]
}
```

### Compressed Format (.umcfz)

Gzip-compressed archives that can include bundled image assets. Ideal for sharing curricula with embedded media.

See [spec/UMCF_FILE_FORMAT.md](spec/UMCF_FILE_FORMAT.md) for full details.

---

## Import System

UMCF includes a pluggable import system for converting external formats:

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     IMPORT PIPELINE                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Source Content              Importer Plugin           Output  │
│   ─────────────              ───────────────           ──────  │
│                                                                 │
│   CK-12 FlexBook  ──────►   CK12Importer   ──────►            │
│   (EPUB)                                              UMCF     │
│                                                       (.umcf)  │
│   Fast.ai Course  ──────►   FastaiImporter ──────►            │
│   (Jupyter)                                                    │
│                                                                 │
│   IMS Common      ──────►   IMSCCImporter  ──────►            │
│   Cartridge                                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Supported Sources

| Source | Format | Target Audience |
|--------|--------|-----------------|
| **CK-12 FlexBooks** | EPUB, PDF | K-12 (8th grade focus) |
| **Fast.ai** | Jupyter Notebooks | Collegiate AI/ML |
| **IMSCC** | ZIP package | General (future) |

### Plugin System

Importers are discovered via Python entry points (PEP 621):

```toml
# pyproject.toml
[project.entry-points."umcf.importers"]
ck12 = "umcf_importer.importers.ck12:CK12Importer"
fastai = "umcf_importer.importers.fastai:FastaiImporter"
```

### Key Files

| File | Description |
|------|-------------|
| [importers/IMPORTER_ARCHITECTURE.md](importers/IMPORTER_ARCHITECTURE.md) | System architecture |
| [importers/CK12_IMPORTER_SPEC.md](importers/CK12_IMPORTER_SPEC.md) | K-12 curriculum importer |
| [importers/FASTAI_IMPORTER_SPEC.md](importers/FASTAI_IMPORTER_SPEC.md) | AI/ML notebook importer |

---

## AI Enrichment Pipeline

The most innovative aspect of UMCF is the **AI-powered enrichment pipeline** that transforms sparse content into rich, tutoring-ready curriculum:

### The Problem

Most curriculum content is **sparse**:
- Plain text without structure
- No comprehension checkpoints
- Missing learning objectives
- No assessments
- No voice optimization

### The Solution: 7-Stage AI Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                   AI ENRICHMENT PIPELINE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Sparse Input                     Rich UMCF Output             │
│  ────────────                     ────────────────             │
│                                                                 │
│  "Plain text         Stage 1: Content Analysis                 │
│   about topic X"  →  Stage 2: Structure Inference              │
│                   →  Stage 3: Content Segmentation             │
│                   →  Stage 4: Learning Objective Extraction    │
│                   →  Stage 5: Assessment Generation            │
│                   →  Stage 6: Tutoring Enhancement             │
│                   →  Stage 7: Knowledge Graph Construction     │
│                                                                 │
│                      ↓                                         │
│                                                                 │
│                   Fully enriched UMCF with:                    │
│                   • Hierarchical structure                     │
│                   • Transcript segments                        │
│                   • Stopping points                            │
│                   • Comprehension questions                    │
│                   • Alternative explanations                   │
│                   • Misconception handling                     │
│                   • Knowledge graph                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Prior Art Foundation

The pipeline is built on proven techniques:

**Pre-AI (Established Research):**
- Readability formulas (Flesch-Kincaid, Dale-Chall, SMOG)
- Semantic Role Labeling for question generation
- Bloom's Taxonomy classification
- TextTiling for segmentation

**AI-Powered (State of the Art):**
- COGENT Framework (2025) for curriculum-oriented generation
- Meta-Chunking (2024) for intelligent segmentation
- LLM-enhanced knowledge graph construction
- Hybrid SRL + LLM question generation

### Human-in-the-Loop

AI-generated enrichments include confidence scores and are designed for human review:

```json
{
  "generated": true,
  "confidence": 0.85,
  "source": "llm_inference",
  "review_status": "pending"
}
```

A web-based editor (future) will allow curriculum designers to:
- Approve AI-generated content
- Edit enrichments
- Regenerate with feedback
- Add manual content

### Key File

| File | Description |
|------|-------------|
| [importers/AI_ENRICHMENT_PIPELINE.md](importers/AI_ENRICHMENT_PIPELINE.md) | Complete pipeline specification |

---

## Repository Structure

```
curriculum/
│
├── README.md                              # This document
│
├── spec/                                  # Core specification
│   ├── umcf-schema.json                  # JSON Schema (1,847 lines)
│   ├── UMCF_SPECIFICATION.md             # Human-readable spec
│   └── STANDARDS_TRACEABILITY.md         # Standards mapping
│
├── examples/                              # Example curricula
│   ├── minimal/                          # Schema validation examples
│   │   ├── minimal-topic.umcf
│   │   ├── minimal-assessment.umcf
│   │   └── minimal-compliance.umcf
│   └── realistic/                        # Full tutoring examples
│       ├── elementary-math.umcf          # 3rd-4th grade
│       ├── corporate-security.umcf       # Compliance training
│       └── pytorch-fundamentals.umcf     # Technical/collegiate
│
├── importers/                             # Import system specs
│   ├── IMPORTER_ARCHITECTURE.md          # Plugin architecture
│   ├── CK12_IMPORTER_SPEC.md            # K-12 importer
│   ├── FASTAI_IMPORTER_SPEC.md          # AI/ML importer
│   └── AI_ENRICHMENT_PIPELINE.md        # AI enrichment spec
│
└── ChatGPT-Create own format.md          # Original research notes
```

---

## Current Status

### Specification Status

| Component | Status | Notes |
|-----------|--------|-------|
| **UMCF Schema** | Draft 1.0.0 | Complete, ready for review |
| **Specification Doc** | Draft 1.0.0 | Complete |
| **Standards Traceability** | Complete | 152 fields mapped |
| **Minimal Examples** | Complete | 3 examples |
| **Realistic Examples** | Complete | 3 examples |
| **Import Architecture** | Draft 1.0.0 | Design complete |
| **CK-12 Importer Spec** | Draft 1.0.0 | Design complete |
| **Fast.ai Importer Spec** | Draft 1.0.0 | Design complete |
| **AI Enrichment Pipeline** | Draft 1.0.0 | Design complete |

### Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| **Python Importer Package** | Not Started | Spec complete |
| **Web Editor** | Not Started | Future work |
| **iOS Integration** | Not Started | Future work |
| **Validation Tools** | Not Started | Future work |

---

## Future Direction

### Potential Standalone Project

UMCF may be spun off into its own repository to enable:

1. **Community adoption**: Other tutoring systems could adopt the format
2. **Independent governance**: Standards evolution separate from UnaMentis
3. **Cross-platform tooling**: Validation, editing, conversion tools
4. **Academic publication**: Formal specification for peer review

### Roadmap

**Phase 1: Validation (Current)**
- Academic review of specification
- Community feedback
- Schema refinement

**Phase 2: Tooling**
- Python validation library
- Command-line tools
- Example importers

**Phase 3: Integration**
- UnaMentis iOS integration
- Web-based curriculum editor
- Public curriculum repository

**Phase 4: Standardization**
- Formal standard proposal
- Community governance
- Version 2.0 planning

---

## Getting Started

### For Reviewers

1. **Start with the specification**: [UMCF_SPECIFICATION.md](spec/UMCF_SPECIFICATION.md)
2. **Review standards mapping**: [STANDARDS_TRACEABILITY.md](spec/STANDARDS_TRACEABILITY.md)
3. **Examine examples**: [examples/realistic/](examples/realistic/)
4. **Validate schema**: Use any JSON Schema validator with [umcf-schema.json](spec/umcf-schema.json)

### For Developers

1. **Read the schema**: [umcf-schema.json](spec/umcf-schema.json)
2. **Study the import architecture**: [IMPORTER_ARCHITECTURE.md](importers/IMPORTER_ARCHITECTURE.md)
3. **Review importer specs**: CK12 and Fast.ai specs show implementation patterns
4. **Understand enrichment**: [AI_ENRICHMENT_PIPELINE.md](importers/AI_ENRICHMENT_PIPELINE.md)

### For Content Creators

1. **Start with minimal examples**: [examples/minimal/](examples/minimal/)
2. **Progress to realistic examples**: [examples/realistic/](examples/realistic/)
3. **Reference the specification**: [UMCF_SPECIFICATION.md](spec/UMCF_SPECIFICATION.md)

---

## Contributing

UMCF is currently part of the UnaMentis project. Contributions are welcome:

1. **Schema improvements**: Propose changes via issues
2. **Example content**: Submit new curriculum examples
3. **Documentation**: Improve specifications and guides
4. **Tooling**: Develop validators, converters, editors

See the main project [CONTRIBUTING.md](../docs/CONTRIBUTING.md) for guidelines.

---

## References

### Educational Standards

- IEEE LOM 1484.12.1-2020: https://standards.ieee.org/standard/1484_12_1-2020.html
- LRMI: https://www.dublincore.org/specifications/lrmi/
- SCORM 2004: https://scorm.com/scorm-explained/
- xAPI: https://xapi.com/overview/
- CASE 1.0: https://www.imsglobal.org/spec/case/v1p0
- QTI 3.0: https://www.imsglobal.org/spec/qti/v3p0
- Open Badges 3.0: https://www.imsglobal.org/spec/ob/v3p0
- Dublin Core: https://www.dublincore.org/specifications/dublin-core/dcmi-terms/

### Research Papers

- COGENT Framework (2025): arxiv.org/abs/2506.09367
- Meta-Chunking (2024): arxiv.org/abs/2410.12788
- QA-SRL Framework: He, Lewis & Zettlemoyer (2015)
- Bloom's Revised Taxonomy: Anderson & Krathwohl (2001)

### Tools & Libraries

- JSON Schema: https://json-schema.org/
- py-readability-metrics: https://github.com/cdimascio/py-readability-metrics
- spaCy: https://spacy.io/
- LangChain: https://langchain.com/

---

## License

This specification is released under the MIT License as part of the UnaMentis project.

Copyright (c) 2025 Richard Amerman

---

## Contact

For questions about UMCF:
- Open an issue on the UnaMentis GitHub repository
- See the main project README for contact information

---

*UMCF: Bringing educational content into the age of conversational AI.*
