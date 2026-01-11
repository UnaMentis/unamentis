#!/bin/bash
#
# test-quick.sh - Run unit tests quickly (no coverage enforcement)
#
# This is a convenience wrapper around test-ci.sh for local development.
# For CI-identical behavior, use test-ci.sh directly.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running quick unit tests..."

# Run unit tests without coverage enforcement
TEST_TYPE=unit \
ENABLE_COVERAGE=false \
ENFORCE_COVERAGE=false \
"$SCRIPT_DIR/test-ci.sh"
