# Comms Skill Complete Setup Guide

This document contains everything needed to get the `/comms` skill (Slack & Trello) working in Claude Code.

## Prerequisites

Install these tools before starting:

```bash
# GitHub CLI (for fetching credentials)
brew install gh

# Age encryption (for decrypting credentials)
brew install age

# jq (for parsing JSON)
brew install jq

# Node.js (for npx/MCP servers)
brew install node
```

Verify GitHub CLI is authenticated:

```bash
gh auth status
# Should show: Logged in to github.com as YOUR_USERNAME
```

If not logged in:

```bash
gh auth login
```

## Credential System Overview

Credentials are stored encrypted in a private GitHub repo. When the MCP servers start, they:

1. Trigger a GitHub Actions workflow that encrypts credentials with your public key
2. Download the encrypted artifact
3. Decrypt locally with your private key
4. Cache for 1 hour

**Secrets Repository:** `sirfifer/unamentis-learning`
**Workflow:** `get-mcp-creds.yml`

You must have push/workflow access to this repo.

## Step 1: Create Age Encryption Key

```bash
# Create config directory
mkdir -p ~/.config/unamentis

# Generate age keypair
age-keygen -o ~/.config/unamentis/age-key.txt

# Verify it was created
cat ~/.config/unamentis/age-key.txt
# Should show:
# # created: 2024-...
# # public key: age1...
# AGE-SECRET-KEY-...
```

**Keep this key safe.** It's used to decrypt your credentials.

## Step 2: Create Directory Structure

```bash
# In your project root
mkdir -p .claude/skills/comms
mkdir -p scripts
```

## Step 3: Create the Credential Fetching Script

Create `scripts/fetch-mcp-creds.sh`:

```bash
#!/usr/bin/env bash
# Shared credential fetching logic

set -euo pipefail

REPO="sirfifer/unamentis-learning"
WORKFLOW="get-mcp-creds.yml"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/unamentis"
CACHE_FILE="$CACHE_DIR/creds.json"
AGE_KEY="$HOME/.config/unamentis/age-key.txt"
CACHE_TTL="${MCP_CACHE_TTL:-3600}"  # Default 1 hour

ensure_credentials() {
    # Check if age key exists
    if [[ ! -f "$AGE_KEY" ]]; then
        echo "ERROR: Age key not found at $AGE_KEY" >&2
        echo "Run: age-keygen -o $AGE_KEY" >&2
        exit 1
    fi

    # Check if cache is valid
    if [[ -f "$CACHE_FILE" ]]; then
        local age_minutes=$((CACHE_TTL / 60))
        if [[ -z $(find "$CACHE_FILE" -mmin +${age_minutes} 2>/dev/null) ]]; then
            # Cache is fresh
            return 0
        fi
    fi

    # Need to fetch fresh credentials
    fetch_credentials
}

fetch_credentials() {
    echo "Fetching MCP credentials..." >&2
    mkdir -p "$CACHE_DIR"

    # Get public key
    local public_key
    public_key=$(grep "public key:" "$AGE_KEY" | cut -d' ' -f4)

    if [[ -z "$public_key" ]]; then
        echo "ERROR: Could not extract public key from $AGE_KEY" >&2
        exit 1
    fi

    # Trigger workflow
    echo "Triggering credential workflow..." >&2
    gh workflow run "$WORKFLOW" -R "$REPO" -f public_key="$public_key"

    # Wait for workflow to start
    sleep 5

    # Get run ID
    local run_id
    run_id=$(gh run list -R "$REPO" -w "$WORKFLOW" --limit 1 --json databaseId -q '.[0].databaseId')

    if [[ -z "$run_id" ]]; then
        echo "ERROR: Could not find workflow run" >&2
        exit 1
    fi

    echo "Waiting for workflow run $run_id to complete..." >&2
    gh run watch "$run_id" -R "$REPO" --exit-status

    # Download artifact
    echo "Downloading encrypted credentials..." >&2
    rm -rf "$CACHE_DIR/mcp-creds"  # Clean any old download
    gh run download "$run_id" -R "$REPO" -n mcp-creds -D "$CACHE_DIR"

    # Decrypt
    if [[ ! -f "$CACHE_DIR/creds.age" ]]; then
        echo "ERROR: Downloaded artifact missing creds.age" >&2
        exit 1
    fi

    echo "Decrypting credentials..." >&2
    age -d -i "$AGE_KEY" "$CACHE_DIR/creds.age" > "$CACHE_FILE"
    chmod 600 "$CACHE_FILE"
    rm -f "$CACHE_DIR/creds.age"

    echo "Credentials ready." >&2
}

get_credential() {
    local key="$1"
    ensure_credentials
    jq -r ".$key" "$CACHE_FILE"
}

# Export for use by other scripts
export -f ensure_credentials fetch_credentials get_credential
export CACHE_FILE AGE_KEY
```

Make it executable:

```bash
chmod +x scripts/fetch-mcp-creds.sh
```

## Step 4: Create Slack MCP Wrapper

Create `scripts/mcp-slack.sh`:

```bash
#!/usr/bin/env bash
# MCP Slack server wrapper with secure credential loading

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/fetch-mcp-creds.sh"

ensure_credentials

export SLACK_BOT_TOKEN=$(jq -r '.slack_bot_token' "$CACHE_FILE")
export SLACK_TEAM_ID=$(jq -r '.slack_team_id' "$CACHE_FILE")

exec npx -y @modelcontextprotocol/server-slack "$@"
```

Make it executable:

```bash
chmod +x scripts/mcp-slack.sh
```

## Step 5: Create Trello MCP Wrapper

Create `scripts/mcp-trello.sh`:

```bash
#!/usr/bin/env bash
# MCP Trello server wrapper with secure credential loading

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/fetch-mcp-creds.sh"

ensure_credentials

export TRELLO_API_KEY=$(jq -r '.trello_api_key' "$CACHE_FILE")
export TRELLO_TOKEN=$(jq -r '.trello_token' "$CACHE_FILE")

# Use bunx if available, fall back to npx
if command -v bunx &> /dev/null; then
    exec bunx @delorenj/mcp-server-trello "$@"
else
    exec npx -y @delorenj/mcp-server-trello "$@"
fi
```

Make it executable:

```bash
chmod +x scripts/mcp-trello.sh
```

## Step 6: Create MCP Configuration

Create `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "slack": {
      "command": "./scripts/mcp-slack.sh"
    },
    "trello": {
      "command": "./scripts/mcp-trello.sh"
    }
  }
}
```

## Step 7: Create the Skill Files

Create `.claude/skills/comms/SKILL.md`:

```markdown
---
name: comms
description: Post to Slack channels and manage Trello cards with natural language
---

# /comms - Slack & Trello Communications Skill

Post messages to Slack channels and create/update Trello cards with natural language commands.

## Usage

```
/comms [message or instruction]
```

## Key Rules

### Trello Comments
**Always prefix Trello comments with "From Claude Code: "**

### Fuzzy Matching
Match user input to channels/boards using aliases. Examples:
- "android" -> tech-android (Slack) or Android list (Trello)
- "ios" -> tech-ios (Slack) or IOS App list (Trello)
- "server" -> tech-server (Slack) or Server list (Trello)

## Example Commands

| User Says | Action |
|-----------|--------|
| "post to android: feature complete" | Post to tech-android channel |
| "create card on ios list: Fix crash bug" | Create card on Tech Work -> IOS App list |
| "tell server channel build is ready" | Post to tech-server channel |

## MCP Tools Used

### Slack
- `mcp__slack__slack_post_message` - Post to channel
- `mcp__slack__slack_reply_to_thread` - Reply in thread
- `mcp__slack__slack_get_channel_history` - Read messages
- `mcp__slack__slack_add_reaction` - Add emoji reaction

### Trello
- `mcp__trello__add_card_to_list` - Create card
- `mcp__trello__add_comment` - Add comment (remember prefix!)
- `mcp__trello__update_card_details` - Update card
- `mcp__trello__move_card` - Move card between lists
- `mcp__trello__get_cards_by_list_id` - List cards

## Resources

See [RESOURCES.md](RESOURCES.md) for complete channel/board mappings with IDs.
```

Create `.claude/skills/comms/RESOURCES.md` with your Slack channels and Trello boards:

```markdown
# Slack & Trello Resource Reference

## Slack Channels

| Channel | ID | Aliases |
|---------|-----|---------|
| all-unamentis | C0A5EE6FUT0 | all, general, main, everyone |
| org-general | C0A6EC0QJ9Y | org |
| org-marketing | C0A69UF198S | marketing |
| tech-general | C0A5PC9SV0T | tech |
| tech-ios | C0A5LST6Q7P | ios, apple |
| tech-android | C0A6J3WAV5K | android, droid |
| tech-server | C0A5Q9X99H8 | server, backend, api |
| tech-dev-tools | C0A5Q9ZSPR8 | devtools, tools, dev |
| tech-github | C0A5QH109FD | github, gh, git |
| tech-qa | C0A67TD1603 | qa, testing, test, quality |
| social | C0A512BL0LF | fun, random |
| issues | C0A7T8V1T8T | bugs, problems |

## Trello Boards

### Tech Work (Primary Tech Board)
**Board ID:** `694f0208f39b274214ad7b6b`
**Aliases:** tech, technical, dev, development

| List | ID | Aliases |
|------|-----|---------|
| IOS App | 694f0237410d79cd568122c7 | ios, apple, iphone |
| Server | 694f02413a50bb0df3724ede | server, backend, api |
| Android | 694f024a7914093d329e766b | android, droid |
| Curriculum | 694f025278144d1fdf331495 | curriculum, content, learning |
| Full System | 695acb434de18ea96a01aef3 | system, full, integration |

### Org-Business Work (Business/Org Board)
**Board ID:** `694f00ffe19f2a037658cf48`
**Aliases:** business, org, organization

| List | ID | Aliases |
|------|-----|---------|
| Ongoing and Repeat Work | 694f012115d52a09d69f2943 | ongoing, repeat, recurring |
| General | 694f02ae9f6bef6967e7122c | general |
| Website | 694f026dd323a5f4ebe735ed | website, web, site |
```

## Step 8: Test the Setup

### Test credential fetching manually:

```bash
cd /path/to/your/project
./scripts/fetch-mcp-creds.sh

# In a subshell, source and test
(
  source ./scripts/fetch-mcp-creds.sh
  ensure_credentials
  echo "Slack token starts with: $(jq -r '.slack_bot_token' "$CACHE_FILE" | cut -c1-10)..."
  echo "Trello key starts with: $(jq -r '.trello_api_key' "$CACHE_FILE" | cut -c1-10)..."
)
```

### Test MCP servers:

```bash
# Start Claude Code
claude

# Check MCP servers are connected
claude mcp list
# Should show:
# slack: Connected
# trello: Connected
```

### Test the skill:

```
/comms post to tech-general: Test message from Claude Code
```

## Troubleshooting

### "Age key not found"

```bash
# Create the key
mkdir -p ~/.config/unamentis
age-keygen -o ~/.config/unamentis/age-key.txt
```

### "Could not find workflow run"

Verify you have access to the repo:

```bash
gh repo view sirfifer/unamentis-learning
```

If you get a 404, you need to be added as a collaborator.

### "gh: command not found"

```bash
brew install gh
gh auth login
```

### MCP servers not connecting

1. Restart Claude Code after creating `.mcp.json`
2. Check script permissions: `chmod +x scripts/*.sh`
3. Test scripts manually: `./scripts/mcp-slack.sh` (should hang waiting for MCP input, Ctrl+C to exit)

### Credentials expired / not working

Clear the cache and re-fetch:

```bash
rm -rf ~/.cache/unamentis/creds.json
# Next MCP server start will fetch fresh credentials
```

### Wrong Slack workspace

The `SLACK_TEAM_ID` in the credentials must match your workspace. Verify in Slack:
- Open Slack in browser
- Team ID is in the URL: `https://app.slack.com/client/T12345678/...`

## File Structure Summary

After setup, you should have:

```
your-project/
├── .mcp.json                          # MCP server configuration
├── .claude/
│   └── skills/
│       └── comms/
│           ├── SKILL.md               # Skill definition
│           └── RESOURCES.md           # Channel/board IDs
├── scripts/
│   ├── fetch-mcp-creds.sh             # Credential fetching logic
│   ├── mcp-slack.sh                   # Slack MCP wrapper
│   └── mcp-trello.sh                  # Trello MCP wrapper
└── ~/.config/unamentis/
    └── age-key.txt                    # Your encryption key (in home dir)
```

## Quick Reference

| Item | Value |
|------|-------|
| Secrets Repo | `sirfifer/unamentis-learning` |
| Workflow | `get-mcp-creds.yml` |
| Age Key Path | `~/.config/unamentis/age-key.txt` |
| Cache Path | `~/.cache/unamentis/creds.json` |
| Cache TTL | 1 hour (3600 seconds) |
