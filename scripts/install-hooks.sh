#!/bin/bash
# UnaMentis Git Hooks Installation Script
# This script installs pre-commit hooks for quality assurance across all components.
#
# Usage: ./scripts/install-hooks.sh
#
# What gets installed:
# - Pre-commit hook: Runs linters on staged files (Swift, Python, JS/TS)
# - Pre-push hook: Runs quick tests before pushing
#
# Requirements (install as needed):
# - SwiftLint: brew install swiftlint
# - SwiftFormat: brew install swiftformat
# - Ruff: pip install ruff (or brew install ruff)
# - Node.js/npm: For ESLint and Prettier in web client
# - Gitleaks (optional): brew install gitleaks

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HOOKS_SOURCE="$PROJECT_ROOT/.hooks"
HOOKS_TARGET="$PROJECT_ROOT/.git/hooks"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}UnaMentis Git Hooks Installation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if we're in a git repository
if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo -e "${RED}Error: Not a git repository. Run this from the project root.${NC}"
    exit 1
fi

# Check if hooks source directory exists
if [ ! -d "$HOOKS_SOURCE" ]; then
    echo -e "${RED}Error: Hooks source directory not found at $HOOKS_SOURCE${NC}"
    exit 1
fi

# Create hooks target directory if it doesn't exist
mkdir -p "$HOOKS_TARGET"

# Install pre-commit hook
echo -e "${YELLOW}Installing pre-commit hook...${NC}"
if [ -f "$HOOKS_SOURCE/pre-commit" ]; then
    cp "$HOOKS_SOURCE/pre-commit" "$HOOKS_TARGET/pre-commit"
    chmod +x "$HOOKS_TARGET/pre-commit"
    echo -e "${GREEN}  Pre-commit hook installed.${NC}"
else
    echo -e "${RED}  Pre-commit hook not found in source.${NC}"
fi

# Install pre-push hook if it exists
if [ -f "$HOOKS_SOURCE/pre-push" ]; then
    echo -e "${YELLOW}Installing pre-push hook...${NC}"
    cp "$HOOKS_SOURCE/pre-push" "$HOOKS_TARGET/pre-push"
    chmod +x "$HOOKS_TARGET/pre-push"
    echo -e "${GREEN}  Pre-push hook installed.${NC}"
fi

# Install prepare-commit-msg hook if it exists
if [ -f "$HOOKS_SOURCE/prepare-commit-msg" ]; then
    echo -e "${YELLOW}Installing prepare-commit-msg hook...${NC}"
    cp "$HOOKS_SOURCE/prepare-commit-msg" "$HOOKS_TARGET/prepare-commit-msg"
    chmod +x "$HOOKS_TARGET/prepare-commit-msg"
    echo -e "${GREEN}  Prepare-commit-msg hook installed (auto-populates from Claude draft).${NC}"
fi

# Install post-commit hook if it exists
if [ -f "$HOOKS_SOURCE/post-commit" ]; then
    echo -e "${YELLOW}Installing post-commit hook...${NC}"
    cp "$HOOKS_SOURCE/post-commit" "$HOOKS_TARGET/post-commit"
    chmod +x "$HOOKS_TARGET/post-commit"
    echo -e "${GREEN}  Post-commit hook installed (auto-clears Claude draft after commit).${NC}"
fi

echo ""
echo -e "${BLUE}Checking tool availability...${NC}"

# Check for required tools
check_tool() {
    local tool=$1
    local install_hint=$2
    if command -v "$tool" &> /dev/null; then
        echo -e "${GREEN}  ✓ $tool${NC}"
        return 0
    else
        echo -e "${YELLOW}  ✗ $tool (optional: $install_hint)${NC}"
        return 1
    fi
}

echo ""
echo "Swift tools:"
check_tool "swiftlint" "brew install swiftlint" || true
check_tool "swiftformat" "brew install swiftformat" || true

echo ""
echo "Python tools:"
check_tool "ruff" "pip install ruff" || true

echo ""
echo "JavaScript tools:"
if [ -f "$PROJECT_ROOT/server/web/package.json" ]; then
    echo -e "${GREEN}  ✓ server/web/package.json found${NC}"
    if [ -d "$PROJECT_ROOT/server/web/node_modules" ]; then
        echo -e "${GREEN}  ✓ node_modules installed${NC}"
    else
        echo -e "${YELLOW}  ✗ node_modules not found (run: cd server/web && npm install)${NC}"
    fi
else
    echo -e "${YELLOW}  ✗ server/web/package.json not found${NC}"
fi

echo ""
echo "Security tools:"
check_tool "gitleaks" "brew install gitleaks" || true

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Git hooks installed successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "The following hooks will run automatically:"
echo "  - Pre-commit: Lint staged Swift, Python, and JS/TS files"
echo "  - Pre-commit: Check for secrets (if gitleaks is installed)"
echo "  - Prepare-commit-msg: Pre-populate message from Claude's draft"
echo "  - Post-commit: Clear Claude's draft after successful commit"
echo ""
echo "To bypass hooks temporarily (not recommended):"
echo "  git commit --no-verify"
echo ""
echo "To uninstall hooks:"
echo "  rm .git/hooks/pre-commit .git/hooks/pre-push .git/hooks/prepare-commit-msg .git/hooks/post-commit"
echo ""
