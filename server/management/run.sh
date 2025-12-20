#!/bin/bash
#
# VoiceLearn Web Management Server
# Run this script to start the management interface
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       VoiceLearn Web Management Server                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}Python 3 is required but not installed.${NC}"
    exit 1
fi

# Check/install dependencies
echo -e "${GREEN}Checking dependencies...${NC}"
python3 -c "import aiohttp" 2>/dev/null || {
    echo -e "${YELLOW}Installing aiohttp...${NC}"
    pip3 install aiohttp
}

# Set default port
PORT="${VOICELEARN_MGMT_PORT:-8766}"
HOST="${VOICELEARN_MGMT_HOST:-0.0.0.0}"

echo ""
echo -e "${GREEN}Starting server on http://${HOST}:${PORT}${NC}"
echo ""

# Run the server
python3 server.py
