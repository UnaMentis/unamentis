#!/bin/bash
set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Running lint checks..."

FAILED=0

# Swift (SwiftLint)
echo ""
echo "1. SwiftLint (Swift)..."
if command -v swiftlint &> /dev/null; then
    if swiftlint lint --strict; then
        echo -e "${GREEN}SwiftLint passed${NC}"
    else
        echo -e "${RED}SwiftLint failed${NC}"
        FAILED=1
    fi
else
    echo -e "${YELLOW}WARNING: SwiftLint not installed${NC}"
    if [ "${SKIP_LINT_IF_UNAVAILABLE:-false}" = "true" ]; then
        echo "SKIP_LINT_IF_UNAVAILABLE=true, skipping SwiftLint"
    else
        echo "Install SwiftLint with: brew install swiftlint"
        FAILED=1
    fi
fi

# Rust (Clippy + rustfmt)
echo ""
echo "2. Rust (Clippy + rustfmt)..."
if command -v cargo &> /dev/null; then
    RUST_DIR="server/usm-core"
    if [ -d "$RUST_DIR" ]; then
        pushd "$RUST_DIR" > /dev/null

        # Check formatting
        echo "   Checking rustfmt..."
        if cargo fmt --check 2>&1; then
            echo -e "   ${GREEN}rustfmt passed${NC}"
        else
            echo -e "   ${RED}rustfmt failed - run 'cargo fmt' to fix${NC}"
            FAILED=1
        fi

        # Run clippy (--all-targets ensures tests, examples, benchmarks are also linted)
        echo "   Running clippy..."
        if cargo clippy --all-targets -- -D warnings 2>&1; then
            echo -e "   ${GREEN}Clippy passed${NC}"
        else
            echo -e "   ${RED}Clippy failed${NC}"
            FAILED=1
        fi

        popd > /dev/null
    else
        echo -e "${YELLOW}WARNING: Rust project not found at $RUST_DIR${NC}"
    fi
else
    echo -e "${YELLOW}WARNING: Rust/Cargo not installed${NC}"
    if [ "${SKIP_LINT_IF_UNAVAILABLE:-false}" != "true" ]; then
        echo "Install Rust with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        FAILED=1
    else
        echo "SKIP_LINT_IF_UNAVAILABLE=true, skipping Rust checks"
    fi
fi

# Python (Ruff) - non-blocking for now
echo ""
echo "3. Ruff (Python)..."
if command -v ruff &> /dev/null; then
    if ruff check server/ --output-format=concise; then
        echo -e "${GREEN}Ruff passed${NC}"
    else
        echo -e "${YELLOW}Ruff found issues (non-blocking)${NC}"
    fi
else
    echo -e "${YELLOW}WARNING: Ruff not installed${NC}"
    echo "Install Ruff with: pip install ruff"
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All lint checks passed!${NC}"
    exit 0
else
    echo -e "${RED}Some lint checks failed${NC}"
    exit 1
fi
