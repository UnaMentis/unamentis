# Cross-Repository Access for AI Agents

This document explains how to configure and use cross-repository access in Claude Code, allowing AI agents to read from external repositories while working in the UnaMentis codebase.

## Overview

Cross-repo access enables AI agents to reference code, patterns, and documentation from related repositories without switching contexts. This is useful when:

- Implementing features that need to match patterns in another repo
- Referencing shared documentation or specifications
- Comparing implementations across platforms (iOS vs Android)
- Debugging issues that span multiple repositories

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  .claude/settings.json                                  │
│  └─ permissions.additionalDirectories: ["/path/..."]   │
│     (Grants filesystem access - always active)          │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  .claude/skills/read-external/SKILL.md                 │
│  └─ allowed-tools: Read, Grep, Glob, Task              │
│     (Documents repos + enforces read-only when invoked) │
└─────────────────────────────────────────────────────────┘
```

**Two-layer design:**
1. **settings.json** grants the permission (always active after Claude Code restart)
2. **Skill** documents available repos and enforces read-only when explicitly invoked

## Currently Configured Repositories

| Repository | Path | Purpose |
|------------|------|---------|
| unamentis-android | `/Users/ramerman/dev/unamentis-android` | Android client for UnaMentis |

## Usage for AI Agents

### Basic Access (Always Active)

Once configured, AI agents can read from external repos using absolute paths:

```bash
# Find files by pattern
Glob: /Users/ramerman/dev/unamentis-android/**/*.kt

# Search for content
Grep: "AudioSession" in /Users/ramerman/dev/unamentis-android/

# Read a specific file
Read: /Users/ramerman/dev/unamentis-android/app/src/main/java/com/unamentis/MainActivity.kt
```

### Read-Only Mode (Explicit Constraint)

Invoke `/read-external` to restrict tools to read-only operations:

```
/read-external
```

When this skill is active:
- Only `Read`, `Grep`, `Glob`, and `Task` tools are available
- `Edit`, `Write`, and `Bash` are blocked
- Prevents accidental modifications to external repos

### Example Workflows

**Comparing iOS and Android implementations:**
```
1. Read the iOS audio session code:
   Read: UnaMentis/Core/Audio/AudioSessionManager.swift

2. Read the Android equivalent:
   Read: /Users/ramerman/dev/unamentis-android/app/src/main/java/.../AudioManager.kt

3. Identify patterns and differences
```

**Finding how Android handles a feature:**
```
1. Search for the feature:
   Grep: "curriculum" in /Users/ramerman/dev/unamentis-android/

2. Read relevant files from results
```

## Adding a New External Repository

### Step 1: Update settings.json

Edit `.claude/settings.json` and add the path:

```json
{
  "permissions": {
    "additionalDirectories": [
      "/Users/ramerman/dev/unamentis-android",
      "/Users/ramerman/dev/NEW_REPO_HERE"
    ]
  }
}
```

### Step 2: Document in SKILL.md

Edit `.claude/skills/read-external/SKILL.md` and add a row to the table:

```markdown
| new-repo | /Users/ramerman/dev/new-repo | Description of what it contains |
```

### Step 3: Update CLAUDE.md and AGENTS.md

Add the new repo to the "Available External Repos" tables in both files.

### Step 4: Restart Claude Code

Permission changes require a Claude Code restart to take effect.

### Step 5: Test

Ask Claude to read a file from the new repo:
```
Read the README.md from /Users/ramerman/dev/new-repo/
```

## Configuration Files

| File | Purpose |
|------|---------|
| `.claude/settings.json` | Permission grant via `additionalDirectories` |
| `.claude/skills/read-external/SKILL.md` | Skill definition with read-only constraint |
| `.claude/skills/read-external/TEMPLATE.md` | Step-by-step instructions for adding repos |
| `CLAUDE.md` | AI instructions (includes repo list) |
| `AGENTS.md` | AI guidelines (includes repo list) |

## Security Considerations

- **Read-only by design**: The skill enforces read-only access when invoked
- **Explicit paths**: Only specifically configured paths are accessible
- **No wildcards**: Each repo must be explicitly added (no `~/dev/*`)
- **Auditable**: All configuration is committed to git

## Troubleshooting

### "Permission denied" or file not found

1. Verify the path is in `additionalDirectories` in settings.json
2. Restart Claude Code (permission changes require restart)
3. Ensure the path is absolute (starts with `/`)

### Skill not recognized

1. Verify `.claude/skills/read-external/SKILL.md` exists
2. Check the YAML frontmatter is valid
3. Restart Claude Code

### Want to prevent writes to external repo

Invoke `/read-external` before working. This restricts tools to read-only operations.

## Related Documentation

- [CLAUDE.md](../../CLAUDE.md) - Primary AI instructions
- [AGENTS.md](../../AGENTS.md) - AI development guidelines
- [Claude Code Skills Documentation](https://docs.anthropic.com/claude-code/skills)
