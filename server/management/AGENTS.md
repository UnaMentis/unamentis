# Management Console

Python/aiohttp web server for content administration and curriculum management.

**URL:** http://localhost:8766

## Purpose

- Curriculum management (import, browse, edit)
- User progress tracking and analytics
- Visual asset management
- Source browser for external curriculum import (MIT OCW, Stanford, etc.)
- AI enrichment pipeline
- User management (future)

## Tech Stack

- **Python 3** with async/await
- **aiohttp** for async HTTP server
- **SQLite** for curriculum database
- **Vanilla JavaScript** for frontend (no framework)

## Key Files

| File | Purpose |
|------|---------|
| `server.py` | Main aiohttp server (3,500+ lines) |
| `import_api.py` | Curriculum import API endpoints |
| `resource_monitor.py` | System resource monitoring |
| `idle_manager.py` | Idle state management |
| `metrics_history.py` | Metrics collection and history |
| `diagnostic_logging.py` | Diagnostic logging system |
| `static/` | HTML/JavaScript frontend |
| `data/` | Runtime data directory |

## API Patterns

- All endpoints are async (`async def`)
- Use aiohttp request/response objects
- JSON responses with `web.json_response()`
- Error handling with appropriate HTTP status codes

## Database

The curriculum database is in `../database/`:
- Schema defined in `schema.sql`
- Python interface in `curriculum_db.py`

## Restart and Verify

Use the `/service` skill for service restarts. Never use bash commands like `pkill`.

```
/service restart management-api    # Restart this server
/service status                    # Check service status
```

Always restart after code changes and verify via API calls or log inspection.

## Testing

```bash
# Test API endpoints
curl http://localhost:8766/api/health
curl http://localhost:8766/api/curricula
```

## Writing Style

Never use em dashes or en dashes as sentence interrupters. Use commas for parenthetical phrases or periods to break up long sentences.
