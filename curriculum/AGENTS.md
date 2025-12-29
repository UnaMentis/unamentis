# Curriculum System

This directory contains the UnaMentis Curriculum Format (UMLCF) specification and related documentation.

## What is UMLCF?

UMLCF (UnaMentis Learning Curriculum Format) is a voice-native, conversational AI-optimized curriculum format. It is:

- JSON-based with standards traceability
- Optimized for voice-first learning experiences
- Not SCORM/IMSCC compatible, but inspired by educational standards

## Directory Structure

```
curriculum/
├── spec/                          # Format specification
│   ├── UMLCF_SPECIFICATION.md     # Full specification document
│   ├── umlcf-schema.json          # JSON schema for validation
│   └── STANDARDS_TRACEABILITY.md  # Standards mapping
├── importers/                     # Importer specifications
│   ├── MIT_OCW_IMPORTER_SPEC.md
│   ├── STANFORD_SEE_IMPORTER_SPEC.md
│   ├── FASTAI_IMPORTER_SPEC.md
│   ├── CK12_IMPORTER_SPEC.md
│   ├── IMPORTER_ARCHITECTURE.md
│   ├── AI_ENRICHMENT_PIPELINE.md
│   └── CURRICULUM_SOURCE_BROWSER_SPEC.md
├── examples/                      # Sample curriculum data
├── assets/                        # Visual assets for curriculum
└── README.md                      # Format overview
```

## Key Documents

| Document | Purpose |
|----------|---------|
| `spec/UMLCF_SPECIFICATION.md` | Full format specification |
| `spec/umlcf-schema.json` | JSON schema for validation |
| `README.md` | Quick format overview |
| `importers/IMPORTER_ARCHITECTURE.md` | How importers work |
| `importers/AI_ENRICHMENT_PIPELINE.md` | AI enhancement process |

## Related Code

The actual importer implementations are in `server/importers/`. This directory contains only specifications and documentation.

## Creating Curriculum

1. Follow the UMLCF specification in `spec/`
2. Validate against `umlcf-schema.json`
3. Use examples in `examples/` as reference
4. Store visual assets in `assets/`

## Writing Style

Never use em dashes or en dashes as sentence interrupters. Use commas for parenthetical phrases or periods to break up long sentences.
