---
name: read-external
description: Read-only access to external repositories for cross-repo context. Use when you need to reference code, patterns, or documentation from other local repositories.
allowed-tools: Read, Grep, Glob, Task
---

# Cross-Repository Read Access

This skill provides constrained read-only access to external repositories configured in `additionalDirectories`.

## Available External Repos

| Repo | Path | Purpose |
|------|------|---------|
| *(add repos here)* | /Users/ramerman/dev/REPO | Description |

## Usage

Access is always active via `additionalDirectories` in settings.json. When you need external context:

1. **Find files**: Use `Glob` with path `/Users/ramerman/dev/REPO/**/*.swift`
2. **Search content**: Use `Grep` with pattern in `/Users/ramerman/dev/REPO/`
3. **Read files**: Use `Read` with absolute path `/Users/ramerman/dev/REPO/file.swift`

## Constraints

When this skill is explicitly invoked with `/read-external`:
- ONLY Read, Grep, Glob, and Task tools are available
- No modifications to external repos (Edit/Write blocked)
- Reference and adapt code, don't copy wholesale

## Adding New Repositories

See [TEMPLATE.md](TEMPLATE.md) for step-by-step instructions on adding new external repositories.
