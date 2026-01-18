#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Running health check..."
echo ""

# PR validation checks (catches common review issues)
echo "0. PR validation checks..."
"$SCRIPT_DIR/lint-pr-checks.sh" || echo "PR checks had warnings (non-blocking)"
echo ""

# Swift checks
echo "1. SwiftLint..."
swiftlint lint --strict
echo ""

echo "2. Swift quick tests..."
./scripts/test-quick.sh
echo ""

# Rust checks (if Rust is installed)
if command -v cargo &> /dev/null; then
    RUST_DIR="$PROJECT_DIR/server/usm-core"
    if [ -d "$RUST_DIR" ]; then
        echo "3. Rust formatting check..."
        (cd "$RUST_DIR" && cargo fmt --check)
        echo ""

        echo "4. Rust clippy..."
        (cd "$RUST_DIR" && cargo clippy -- -D warnings)
        echo ""

        echo "5. Rust tests..."
        (cd "$RUST_DIR" && cargo test)
        echo ""
    fi
else
    echo "Note: Rust not installed, skipping Rust checks"
    echo ""
fi

echo "Health check passed!"
