# MCP Setup Implementation Plan

Reference: [MCP_SETUP.md](MCP_SETUP.md)

---

## Phase 1: Prerequisites and Installations

### 1.1 Install Required Tools
- [x] Install `age` encryption tool (`brew install age`)
- [x] Verify `jq` installed (v1.7.1 present)
- [x] Verify `gh` CLI installed (v2.83.2 present)
- [x] Verify `gh auth` completed (authenticated as sirfifer)

### 1.2 Generate Encryption Keypair
- [x] Create config directory (`~/.config/unamentis/`)
- [x] Generate age keypair (`age-keygen -o ~/.config/unamentis/age-key.txt`)
- [x] Set secure permissions (`chmod 600`)
- [ ] Back up keypair securely (user action)

**Public Key:** `age1xw5tu2fa9y5mqqg45fxxsnc457jaegv2pyy5es66ugucvflkqd9shmevdm`

---

## Phase 2: Create MCP Scripts in UnaMentis Repository

### 2.1 Create fetch-mcp-creds.sh
- [x] Create `scripts/fetch-mcp-creds.sh` with credential fetching logic
- [x] Make executable (`chmod +x`)

### 2.2 Create mcp-trello.sh
- [x] Create `scripts/mcp-trello.sh` wrapper script
- [x] Make executable (`chmod +x`)

### 2.3 Create mcp-slack.sh
- [x] Create `scripts/mcp-slack.sh` wrapper script
- [x] Make executable (`chmod +x`)

### 2.4 Create refresh-mcp-creds.sh
- [x] Create `scripts/refresh-mcp-creds.sh` for manual refresh
- [x] Make executable (`chmod +x`)

---

## Phase 3: Update MCP Configuration

- [x] Update `.mcp.json` to add `slack` server entry
- [x] Update `.mcp.json` to add `trello` server entry

---

## Phase 4: User Actions (Manual Steps)

### 4.1 Obtain Slack Credentials
- [x] Create Slack app at https://api.slack.com/apps
- [x] Add required scopes (channels:read, channels:history, chat:write, users:read, reactions:write)
- [x] Install to workspace
- [x] Copy Bot Token (`xoxb-...`)
- [x] Get Team ID from workspace settings

### 4.2 Obtain Trello Credentials
- [x] Get API Key from https://trello.com/app-key
- [x] Generate Token via authorization URL
- [x] Copy Token

### 4.3 Add Secrets to Private Repository
- [x] `gh secret set TRELLO_API_KEY -R sirfifer/unamentis-learning`
- [x] `gh secret set TRELLO_TOKEN -R sirfifer/unamentis-learning`
- [x] `gh secret set SLACK_BOT_TOKEN -R sirfifer/unamentis-learning`
- [x] `gh secret set SLACK_TEAM_ID -R sirfifer/unamentis-learning`

### 4.4 Create GitHub Actions Workflow
- [x] Create `.github/workflows/get-mcp-creds.yml` in `sirfifer/unamentis-learning`
- [x] Commit and push workflow

---

## Phase 5: Testing and Verification

- [x] Run `./scripts/refresh-mcp-creds.sh` to test credential fetch
- [x] Verify cache file exists at `~/.cache/unamentis/creds.json`
- [x] Test Trello server starts manually
- [x] Test Slack server starts manually
- [x] Restart IDE/Claude Code
- [x] Verify `claude mcp list` shows slack and trello
- [x] Test "List my Trello boards" in Claude
- [x] Test "List Slack channels" in Claude

---

## Files to Create/Modify

| File | Action | Status |
|------|--------|--------|
| `scripts/fetch-mcp-creds.sh` | Create | Done |
| `scripts/mcp-trello.sh` | Create | Done |
| `scripts/mcp-slack.sh` | Create | Done |
| `scripts/refresh-mcp-creds.sh` | Create | Done |
| `.mcp.json` | Modify | Done |

---

## Current Progress

**Completed:** All phases complete. MCP setup is fully operational.

**Status:** Slack and Trello MCP servers are working. Credentials are securely managed via GitHub Actions + age encryption.
