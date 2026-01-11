#!/usr/bin/env bash
# MCP Slack server wrapper with secure credential loading

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/fetch-mcp-creds.sh"

ensure_credentials

export SLACK_BOT_TOKEN=$(jq -r '.slack_bot_token' "$CACHE_FILE")
export SLACK_TEAM_ID=$(jq -r '.slack_team_id' "$CACHE_FILE")

exec npx -y @modelcontextprotocol/server-slack "$@"
