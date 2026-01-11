# UnaMentis MCP Integration Setup

This guide sets up Slack and Trello MCP servers for Claude Code with secure credential management via GitHub Actions.

## Architecture Overview

```
sirfifer/unamentis-learning (private)     sirfifer/unamentis (public)
├── .github/workflows/                    ├── .mcp.json
│   └── get-mcp-creds.yml                 └── scripts/
└── (GitHub Secrets)                          ├── mcp-trello.sh
    ├── TRELLO_API_KEY                        ├── mcp-slack.sh
    ├── TRELLO_TOKEN                          └── fetch-mcp-creds.sh
    ├── SLACK_BOT_TOKEN
    └── SLACK_TEAM_ID

Flow:
1. Local script triggers workflow with age public key
2. Workflow encrypts secrets → uploads artifact
3. Local script downloads artifact → decrypts with private key
4. MCP server starts with credentials in environment
```

---

## Prerequisites

### 1. Install Required Tools

```bash
# macOS
brew install age jq gh

# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y age jq
# gh cli: https://github.com/cli/cli/blob/trunk/docs/install_linux.md

# Verify installations
age --version
jq --version
gh --version
```

### 2. Authenticate GitHub CLI

```bash
gh auth login
# Select: GitHub.com → HTTPS → Login with browser

# Verify access to private repo
gh repo view sirfifer/unamentis-learning
```

### 3. Install MCP Server Dependencies

```bash
# Ensure Node.js 18+ is installed
node --version

# Optional: Install bun for faster Trello server
curl -fsSL https://bun.sh/install | bash
```

---

## Step 1: Generate Age Encryption Keypair

Run this once per machine:

```bash
# Create config directory
mkdir -p ~/.config/unamentis

# Generate keypair
age-keygen -o ~/.config/unamentis/age-key.txt

# Set secure permissions
chmod 600 ~/.config/unamentis/age-key.txt

# Display public key (you'll need this to verify setup)
grep "public key:" ~/.config/unamentis/age-key.txt
```

**Important:** Back up `~/.config/unamentis/age-key.txt` securely. Without it, you cannot decrypt credentials.

---

## Step 2: Obtain Slack and Trello Credentials

### Slack Bot Token

1. Go to https://api.slack.com/apps
2. Click **Create New App** → **From scratch**
3. Name: `UnaMentis Bot`, Workspace: Your UnaMentis workspace
4. Navigate to **OAuth & Permissions**
5. Under **Scopes → Bot Token Scopes**, add:
   - `channels:read`
   - `channels:history`
   - `chat:write`
   - `users:read`
   - `reactions:write`
6. Click **Install to Workspace** and authorize
7. Copy the **Bot User OAuth Token** (starts with `xoxb-`)
8. Get your **Team ID**: In Slack, click workspace name → Settings → Workspace settings → look for Team ID in URL (starts with `T`)

### Trello API Credentials

1. Go to https://trello.com/app-key
2. Copy your **API Key**
3. Click the **Token** link on that page (or construct URL):
   ```
   https://trello.com/1/authorize?expiration=never&name=UnaMentis&scope=read,write&response_type=token&key=YOUR_API_KEY
   ```
4. Authorize and copy the **Token**

---

## Step 3: Add Secrets to Private Repository

```bash
# Add each secret to sirfifer/unamentis-learning
gh secret set TRELLO_API_KEY -R sirfifer/unamentis-learning
# Paste your Trello API key when prompted

gh secret set TRELLO_TOKEN -R sirfifer/unamentis-learning
# Paste your Trello token when prompted

gh secret set SLACK_BOT_TOKEN -R sirfifer/unamentis-learning
# Paste your Slack bot token when prompted

gh secret set SLACK_TEAM_ID -R sirfifer/unamentis-learning
# Paste your Slack team ID when prompted

# Verify secrets exist
gh secret list -R sirfifer/unamentis-learning
```

---

## Step 4: Create GitHub Actions Workflow

Create this file in the `sirfifer/unamentis-learning` repository:

### `.github/workflows/get-mcp-creds.yml`

```yaml
name: Get MCP Credentials

on:
  workflow_dispatch:
    inputs:
      public_key:
        description: 'age public key for encryption'
        required: true
        type: string

jobs:
  export-creds:
    runs-on: ubuntu-latest
    steps:
      - name: Install age
        run: |
          sudo apt-get update && sudo apt-get install -y age

      - name: Encrypt credentials
        run: |
          cat << 'EOF' | age -r "${{ inputs.public_key }}" -o creds.age
          {
            "trello_api_key": "${{ secrets.TRELLO_API_KEY }}",
            "trello_token": "${{ secrets.TRELLO_TOKEN }}",
            "slack_bot_token": "${{ secrets.SLACK_BOT_TOKEN }}",
            "slack_team_id": "${{ secrets.SLACK_TEAM_ID }}"
          }
          EOF

      - name: Upload encrypted artifact
        uses: actions/upload-artifact@v4
        with:
          name: mcp-creds
          path: creds.age
          retention-days: 1
```

Commit and push this workflow:

```bash
cd /path/to/unamentis-learning
mkdir -p .github/workflows
# Create the file above
git add .github/workflows/get-mcp-creds.yml
git commit -m "Add MCP credentials workflow"
git push
```

---

## Step 5: Create Scripts in UnaMentis Repository

Create these files in the public `sirfifer/unamentis` repository:

### `scripts/fetch-mcp-creds.sh`

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

### `scripts/mcp-trello.sh`

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

### `scripts/mcp-slack.sh`

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

### `scripts/refresh-mcp-creds.sh`

```bash
#!/usr/bin/env bash
# Force refresh of cached MCP credentials

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/fetch-mcp-creds.sh"

# Remove cache to force refresh
rm -f "$CACHE_FILE"

fetch_credentials
echo "Credentials refreshed successfully."
```

Make scripts executable:

```bash
chmod +x scripts/mcp-*.sh scripts/fetch-mcp-creds.sh scripts/refresh-mcp-creds.sh
```

---

## Step 6: Configure MCP in UnaMentis Repository

### `.mcp.json`

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

---

## Step 7: Test the Setup

### Test credential fetching

```bash
cd /path/to/unamentis

# Force a fresh credential fetch
./scripts/refresh-mcp-creds.sh

# Verify cache file exists and contains data
cat ~/.cache/unamentis/creds.json | jq 'keys'
# Should output: ["slack_bot_token", "slack_team_id", "trello_api_key", "trello_token"]
```

### Test MCP servers manually

```bash
# Test Trello server starts
./scripts/mcp-trello.sh &
MCP_PID=$!
sleep 3
kill $MCP_PID 2>/dev/null

# Test Slack server starts
./scripts/mcp-slack.sh &
MCP_PID=$!
sleep 3
kill $MCP_PID 2>/dev/null

echo "Both servers started successfully"
```

### Test with Claude Code

```bash
cd /path/to/unamentis
claude

# In Claude Code, try:
# "List my Trello boards"
# "List Slack channels"
```

---

## Troubleshooting

### "Age key not found"

```bash
# Generate the key
mkdir -p ~/.config/unamentis
age-keygen -o ~/.config/unamentis/age-key.txt
chmod 600 ~/.config/unamentis/age-key.txt
```

### "Could not find workflow run"

```bash
# Verify workflow exists
gh workflow list -R sirfifer/unamentis-learning

# Manually trigger to test
PUBLIC_KEY=$(grep "public key:" ~/.config/unamentis/age-key.txt | cut -d' ' -f4)
gh workflow run get-mcp-creds.yml -R sirfifer/unamentis-learning -f public_key="$PUBLIC_KEY"

# Watch the run
gh run list -R sirfifer/unamentis-learning -w get-mcp-creds.yml
```

### "Permission denied" on scripts

```bash
chmod +x scripts/*.sh
```

### Credentials seem stale

```bash
# Force refresh
./scripts/refresh-mcp-creds.sh

# Or delete cache
rm ~/.cache/unamentis/creds.json
```

### MCP server not connecting in Claude Code

```bash
# Verify .mcp.json is in project root
cat .mcp.json

# Check Claude Code sees it
claude mcp list
```

---

## Security Considerations

1. **Private key protection**: `~/.config/unamentis/age-key.txt` is the crown jewel. Back it up securely, never commit it.

2. **Cache security**: Decrypted credentials in `~/.cache/unamentis/creds.json` are protected by filesystem permissions (600). The cache auto-expires based on `MCP_CACHE_TTL`.

3. **Artifact exposure**: The GitHub artifact contains only encrypted data. Without the private key, it's useless.

4. **Repository access**: Only users with read access to `sirfifer/unamentis-learning` can trigger the workflow.

---

## Optional: Extend Cache TTL

For longer sessions without re-fetching:

```bash
# Set to 24 hours
export MCP_CACHE_TTL=86400
```

Or add to your shell profile for persistence.

---

## File Checklist

After setup, you should have:

**In `sirfifer/unamentis-learning` (private):**
- [ ] `.github/workflows/get-mcp-creds.yml`
- [ ] GitHub Secrets: `TRELLO_API_KEY`, `TRELLO_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID`

**In `sirfifer/unamentis` (public):**
- [ ] `.mcp.json`
- [ ] `scripts/fetch-mcp-creds.sh`
- [ ] `scripts/mcp-trello.sh`
- [ ] `scripts/mcp-slack.sh`
- [ ] `scripts/refresh-mcp-creds.sh`

**On local machine:**
- [ ] `~/.config/unamentis/age-key.txt`
- [ ] `age`, `jq`, `gh` installed
- [ ] `gh auth` completed
