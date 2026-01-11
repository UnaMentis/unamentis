# Server Components

This directory contains the backend server infrastructure for UnaMentis.

## Architecture

There are **two separate web interfaces** serving different purposes:

| Interface | Port | Purpose | Location |
|-----------|------|---------|----------|
| **Management Console** | 8766 | Content administration, curriculum, users | `management/` |
| **Operations Console** | 3000 | DevOps monitoring, system health, logs | `web/` |

Additionally, there is a shared component:

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

**Why:** Unlike compiled code where build success confirms the code will run, server code changes only take effect after restart. Telling the user to restart the server means you haven't verified your work actually functions.

## Restarting Servers

**Use the `/service` skill to manage all server restarts.** Never use pkill or manual restart commands.

```
/service restart management-api    # Restart Management Console
/service restart web-server        # Restart Operations Console
/service status                    # Check all service status
```

See the skill documentation at `.claude/skills/service/SKILL.md` for full usage.

## Verification Methods

- Make API calls to test modified endpoints
- Check server logs for expected log messages
- Confirm the browser shows updated behavior (if UI was changed)
- Use `curl` or browser dev tools to inspect API responses

See `AGENTS.md` in the project root for detailed restart and verification procedures.
