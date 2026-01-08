# Adding a New External Repository

Follow these steps to grant Claude Code read access to another local repository.

## Step 1: Add to settings.json

Edit `.claude/settings.json` and add the repository path to `additionalDirectories`:

```json
{
  "permissions": {
    "additionalDirectories": [
      "/Users/ramerman/dev/existing-repo",
      "/Users/ramerman/dev/NEW_REPO_HERE"
    ]
  }
}
```

## Step 2: Document in SKILL.md

Add a row to the "Available External Repos" table in `SKILL.md`:

```markdown
| new-repo | /Users/ramerman/dev/new-repo | What this repo contains |
```

## Step 3: Test

Restart Claude Code (or start a new session), then verify access:

```
"Read the README.md from /Users/ramerman/dev/new-repo/"
```

## Step 4: Optionally Add to Other Repo

For bi-directional access, repeat this process in the other repository's `.claude/settings.json` pointing back to this repo.

## Notes

- Paths must be absolute (start with `/`)
- Access is read-only when `/read-external` skill is invoked
- Changes to settings.json require a Claude Code restart to take effect
