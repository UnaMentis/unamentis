#!/usr/bin/env bash
# Force refresh of cached MCP credentials

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/fetch-mcp-creds.sh"

# Remove cache to force refresh
rm -f "$CACHE_FILE"

fetch_credentials
echo "Credentials refreshed successfully."
