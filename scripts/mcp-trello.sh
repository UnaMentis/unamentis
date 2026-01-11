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
