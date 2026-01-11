#!/bin/bash
#
# test-integration.sh - Run integration tests locally
#
# This is a convenience wrapper around test-ci.sh for local development.
# Integration tests are typically only run in CI on main branch,
# but this script allows running them locally when needed.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running integration tests..."

# Run integration tests (no coverage enforcement, as these are slower)
TEST_TYPE=integration \
ENABLE_COVERAGE=false \
ENFORCE_COVERAGE=false \
"$SCRIPT_DIR/test-ci.sh"
