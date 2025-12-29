# Curriculum Importer Framework

Python framework for importing external curriculum sources into UMLCF format.

## Purpose

Ingest curriculum from external sources (MIT OCW, CK-12, and future sources) and convert to the UnaMentis Curriculum Format (UMLCF).

## Plugin Architecture

The framework uses a **filesystem-based plugin architecture** with explicit enable/disable control:

- **Auto-Discovery**: Plugins are automatically discovered from the `plugins/` folder
- **Explicit Enablement**: Plugins must be enabled via the Plugin Manager UI
- **Persistent State**: Plugin enabled/disabled state persists in `plugins.json`
- **First-Run Wizard**: New installations prompt users to select which plugins to enable

### Plugin Lifecycle

1. **Discovery**: Server scans `plugins/sources/`, `plugins/parsers/`, `plugins/enrichers/`
2. **First-Run**: If no `plugins.json` exists, the Plugin Manager shows a setup wizard
3. **Enable/Disable**: Users toggle plugins on/off via the Plugin Manager tab
4. **Runtime**: Only enabled plugins appear in the Source Browser

## Architecture

```
importers/
├── plugins/               # All plugins live here
│   ├── sources/           # Source importer plugins
│   │   ├── mit_ocw.py     # MIT OpenCourseWare
│   │   └── ck12_flexbook.py # CK-12 FlexBooks
│   ├── parsers/           # Parser plugins (future)
│   └── enrichers/         # Enricher plugins (future)
├── core/                  # Framework core
│   ├── base.py            # CurriculumSourceHandler base class
│   ├── discovery.py       # Plugin discovery system
│   ├── registry.py        # SourceRegistry (enabled plugins only)
│   ├── plugin.py          # PluginManager
│   ├── models.py          # Data models
│   └── orchestrator.py    # Import orchestration engine
├── data/                  # Catalog data files
├── tests/                 # Unit and integration tests
└── output/                # Import output
```

## Creating a New Plugin

1. Create a new `.py` file in `plugins/sources/`:

```python
# plugins/sources/my_source.py
from ...core.base import CurriculumSourceHandler
from ...core.models import CurriculumSource, LicenseInfo
from ...core.registry import SourceRegistry

@SourceRegistry.register
class MySourceHandler(CurriculumSourceHandler):
    """My curriculum source handler."""

    @property
    def source_id(self) -> str:
        return "my_source"

    @property
    def source_info(self) -> CurriculumSource:
        return CurriculumSource(
            id=self.source_id,
            name="My Source",
            description="Description of my source",
            # ... other fields
        )

    async def get_course_catalog(self, page, page_size, filters, search):
        # Return courses, total count, and filter options
        return courses, total, filter_options

    async def download_course(self, course_id, output_dir, progress_callback):
        # Download course content
        return output_path
```

2. Restart the server to discover the plugin
3. Enable it in the Plugin Manager tab

## Testing

```bash
cd server/importers
python -m pytest tests/ -v           # Run all tests
python -m pytest tests/test_plugin_architecture.py  # Plugin tests
python -m pytest tests/test_ck12_flexbook.py       # CK-12 tests
python -m pytest tests/test_orchestrator.py        # Orchestrator tests
```

## Key Files

| File | Purpose |
|------|---------|
| `core/discovery.py` | Plugin discovery and state management |
| `core/registry.py` | SourceRegistry for accessing enabled plugins |
| `core/base.py` | CurriculumSourceHandler base class |

## Output Format

All importers produce UMLCF-compliant JSON. See `curriculum/spec/` for the full specification.

## Writing Style

Never use em dashes or en dashes as sentence interrupters. Use commas for parenthetical phrases or periods to break up long sentences.
