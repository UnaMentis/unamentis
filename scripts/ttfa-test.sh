#!/bin/bash
# =============================================================================
# UnaMentis TTFA Performance Test Runner
# =============================================================================
#
# Builds the app, installs on simulator, runs TTFA tests, and reports results.
#
# Usage:
#   ./scripts/ttfa-test.sh                          # Quick suite, text output
#   ./scripts/ttfa-test.sh --suite full             # Full suite
#   ./scripts/ttfa-test.sh --ci                     # CI mode (fail on regression)
#   ./scripts/ttfa-test.sh --create-baseline main   # Create baseline
#
# Environment variables:
#   SIMULATOR       - Simulator device name (default: "iPhone 16 Pro")
#   TTFA_SUITE      - Test suite to run (default: "quick")
#   TTFA_BASELINE   - Baseline name to compare against
#   TTFA_FORMAT     - Output format: text, json, markdown (default: text)
#   SKIP_BUILD      - Set to "true" to skip building (use existing .app)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$PROJECT_DIR/server"

# Configuration
SIMULATOR="${SIMULATOR:-iPhone 16 Pro}"
TTFA_SUITE="${TTFA_SUITE:-quick}"
TTFA_FORMAT="${TTFA_FORMAT:-text}"
SKIP_BUILD="${SKIP_BUILD:-false}"

# Colors
GREEN='\033[92m'
RED='\033[91m'
YELLOW='\033[93m'
CYAN='\033[96m'
RESET='\033[0m'

info() { echo -e "${CYAN}[TTFA]${RESET} $*"; }
success() { echo -e "${GREEN}[TTFA]${RESET} $*"; }
error() { echo -e "${RED}[TTFA]${RESET} $*"; }

# Parse arguments
EXTRA_ARGS=()
CI_MODE=false
CREATE_BASELINE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --suite)
            TTFA_SUITE="$2"
            shift 2
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        --create-baseline)
            CREATE_BASELINE="$2"
            shift 2
            ;;
        --format)
            TTFA_FORMAT="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# Find the built .app path
find_app_path() {
    local derived_data
    derived_data=$(xcodebuild -project "$PROJECT_DIR/UnaMentis.xcodeproj" \
        -scheme UnaMentis -showBuildSettings 2>/dev/null \
        | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')

    if [[ -n "$derived_data" && -d "$derived_data/UnaMentis.app" ]]; then
        echo "$derived_data/UnaMentis.app"
        return 0
    fi

    # Fallback: search DerivedData
    local app_path
    app_path=$(find ~/Library/Developer/Xcode/DerivedData \
        -name "UnaMentis.app" -path "*/Debug-iphonesimulator/*" \
        -maxdepth 5 2>/dev/null | head -1)

    if [[ -n "$app_path" ]]; then
        echo "$app_path"
        return 0
    fi

    return 1
}

# Build the app
if [[ "$SKIP_BUILD" != "true" ]]; then
    info "Building UnaMentis for simulator ($SIMULATOR)..."

    # Resolve simulator to UUID for reliable destination matching
    SIM_UDID=$(xcrun simctl list devices available 2>/dev/null \
        | grep "$SIMULATOR" | head -1 \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
    if [[ -n "$SIM_UDID" ]]; then
        DESTINATION="platform=iOS Simulator,id=$SIM_UDID"
    else
        DESTINATION="platform=iOS Simulator,name=$SIMULATOR"
    fi

    set +e
    xcodebuild -project "$PROJECT_DIR/UnaMentis.xcodeproj" \
        -scheme UnaMentis \
        -destination "$DESTINATION" \
        -configuration Debug \
        build 2>&1 | tail -5
    rc=${PIPESTATUS[0]}
    set -e

    if [[ $rc -ne 0 ]]; then
        error "Build failed!"
        exit 1
    fi

    success "Build complete."
else
    info "Skipping build (SKIP_BUILD=true)"
fi

# Find the built app
APP_PATH=$(find_app_path) || {
    error "Could not find built UnaMentis.app. Build first or set SKIP_BUILD=false."
    exit 1
}
info "Using app: $APP_PATH"

# Construct CLI command
CLI_ARGS=(
    python3 -m ttfa_harness.cli
    --suite "$TTFA_SUITE"
    --device "$SIMULATOR"
    --app-path "$APP_PATH"
    --format "$TTFA_FORMAT"
)

if [[ "$CI_MODE" == "true" ]]; then
    CLI_ARGS+=(--fail-on-regression)

    # Use 'main' baseline in CI if not specified
    if [[ -n "${TTFA_BASELINE:-}" ]]; then
        CLI_ARGS+=(--baseline "$TTFA_BASELINE")
    elif [[ -f "$SERVER_DIR/ttfa_harness/baselines/main.json" ]]; then
        CLI_ARGS+=(--baseline main)
    fi

    # Save results as artifact
    RESULTS_DIR="$PROJECT_DIR/build/ttfa-results"
    mkdir -p "$RESULTS_DIR"
    CLI_ARGS+=(--output "$RESULTS_DIR/ttfa-results.json")
fi

if [[ -n "$CREATE_BASELINE" ]]; then
    CLI_ARGS+=(--create-baseline "$CREATE_BASELINE")
fi

CLI_ARGS+=("${EXTRA_ARGS[@]}")

# Run TTFA tests
info "Running TTFA tests (suite: $TTFA_SUITE)..."
cd "$SERVER_DIR"

set +e
"${CLI_ARGS[@]}"
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 0 ]]; then
    success "TTFA tests passed!"
else
    error "TTFA tests failed (exit code: $EXIT_CODE)"
fi

exit $EXIT_CODE
