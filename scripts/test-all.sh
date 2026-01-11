#!/bin/bash
#
# test-all.sh - Run full test suite with coverage enforcement
#
# This is a convenience wrapper around test-ci.sh for local development.
# Matches CI behavior: runs all tests and enforces 80% coverage threshold.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running full test suite with coverage..."

# Run all tests with coverage enforcement (matches CI)
TEST_TYPE=all \
ENABLE_COVERAGE=true \
ENFORCE_COVERAGE=true \
COVERAGE_THRESHOLD=80 \
"$SCRIPT_DIR/test-ci.sh"
