# Server Components

This directory contains the backend server infrastructure for UnaMentis.

## Architecture

There are **two separate web interfaces** serving different purposes:

| Interface | Port | Purpose | Location |
|-----------|------|---------|----------|
| **Management Console** | 8766 | Content administration, curriculum, users | `management/` |
| **Operations Console** | 3000 | DevOps monitoring, system health, logs | `web/` |

Additional components:

| Component | Purpose | Location |
|-----------|---------|----------|
| **Importers** | External curriculum ingestion pipeline | `importers/` |
| **Database** | Curriculum database (SQLite) | `database/` |

## Server Work Completion Requirements

**When modifying server code, you MUST:**

1. **Restart the affected server** after making code changes
2. **Verify the changes are working** by testing the modified functionality
3. **Check server logs** to confirm the new code is running

This is non-negotiable. Server work is NOT complete until:
- The server has been restarted with your changes
- You have verified the changes work as expected
- You have confirmed via logs or API calls that your code is active

**Why:** Unlike compiled code where build success confirms the code will run, server code changes only take effect after restart.

## Restart Commands

Use the `/service` skill for all service restarts. Never use bash commands like `pkill`.

```
/service restart management-api    # Management Console (port 8766)
/service restart web-client        # Operations Console (port 3000)
/service status                    # Check service status
```

The Operations Console usually auto-reloads with Next.js dev server.

## Verification Methods

- Make API calls to test modified endpoints
- Check server logs for expected log messages
- Confirm the browser shows updated behavior (if UI was changed)
- Use `curl` or browser dev tools to inspect API responses

## Writing Style

Never use em dashes or en dashes as sentence interrupters. Use commas for parenthetical phrases or periods to break up long sentences.

See `AGENTS.md` in subdirectories for component-specific guidance.
