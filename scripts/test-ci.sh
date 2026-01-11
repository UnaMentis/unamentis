#!/bin/bash
#
# test-ci.sh - Unified Test Runner for UnaMentis
#
# Single source of truth for test execution, used by both local scripts and CI.
# This ensures local and CI environments behave identically.
#
# Environment Variables:
#   TEST_TYPE           - "unit", "integration", or "all" (default: unit)
#   SIMULATOR           - Simulator name (default: iPhone 16 Pro)
#   COVERAGE_THRESHOLD  - Minimum coverage percentage (default: 80)
#   ENABLE_COVERAGE     - "true" or "false" (default: true)
#   ENFORCE_COVERAGE    - "true" or "false" (default: true in CI)
#   RESULT_BUNDLE_PATH  - Path for xcresult bundle (optional)
#   CI                  - Set to "true" in CI environments
#   XCBEAUTIFY_RENDERER - Renderer for xcbeautify (default: github-actions in CI)
#
# Usage:
#   ./scripts/test-ci.sh                    # Run unit tests with coverage
#   TEST_TYPE=all ./scripts/test-ci.sh      # Run all tests
#   TEST_TYPE=integration ./scripts/test-ci.sh  # Run integration tests only
#   ENFORCE_COVERAGE=false ./scripts/test-ci.sh # Skip coverage enforcement
#

set -e

# Color output (disabled in CI for cleaner logs)
if [ -t 1 ] && [ -z "$CI" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Configuration with defaults
TEST_TYPE="${TEST_TYPE:-unit}"
SIMULATOR="${SIMULATOR:-iPhone 16 Pro}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"
ENABLE_COVERAGE="${ENABLE_COVERAGE:-true}"
ENFORCE_COVERAGE="${ENFORCE_COVERAGE:-${CI:-false}}"  # Default to CI value if set
PROJECT="UnaMentis.xcodeproj"
SCHEME="UnaMentis"

# CI-specific settings
if [ "$CI" = "true" ]; then
    XCBEAUTIFY_RENDERER="${XCBEAUTIFY_RENDERER:-github-actions}"
else
    XCBEAUTIFY_RENDERER="${XCBEAUTIFY_RENDERER:-}"
fi

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Check simulator availability and find fallback if needed
get_simulator() {
    local requested="$1"

    # Check if requested simulator exists
    if xcrun simctl list devices available 2>/dev/null | grep -q "$requested"; then
        echo "$requested"
        return 0
    fi

    log_warning "Simulator '$requested' not found, searching for alternative..."

    # Try common alternatives in order of preference
    local alternatives=("iPhone 16 Pro" "iPhone 17 Pro" "iPhone 15 Pro" "iPhone 14 Pro")
    for alt in "${alternatives[@]}"; do
        if xcrun simctl list devices available 2>/dev/null | grep -q "$alt"; then
            log_warning "Using fallback simulator: $alt"
            echo "$alt"
            return 0
        fi
    done

    # Last resort: use first available iPhone
    local fallback
    fallback=$(xcrun simctl list devices available 2>/dev/null | grep -o 'iPhone [^(]*' | head -1 | xargs)
    if [ -n "$fallback" ]; then
        log_warning "Using first available iPhone: $fallback"
        echo "$fallback"
        return 0
    fi

    log_error "No suitable iOS simulator found"
    exit 1
}

# Build xcbeautify command
get_xcbeautify_cmd() {
    if command -v xcbeautify &> /dev/null; then
        if [ -n "$XCBEAUTIFY_RENDERER" ]; then
            echo "xcbeautify --renderer $XCBEAUTIFY_RENDERER"
        else
            echo "xcbeautify"
        fi
    else
        log_warning "xcbeautify not found, using raw output"
        echo "cat"
    fi
}

# Extract coverage from xcresult bundle
extract_coverage() {
    local result_path="$1"

    if [ ! -d "$result_path" ]; then
        echo "0"
        return 1
    fi

    xcrun xccov view --report --json "$result_path" 2>/dev/null | \
        python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    targets = data.get('targets', [])

    # Find UnaMentis target (not Tests)
    for target in targets:
        name = target.get('name', '')
        if 'UnaMentis' in name and 'Tests' not in name:
            coverage = target.get('lineCoverage', 0)
            print(f'{coverage * 100:.1f}')
            sys.exit(0)

    # Fallback: average of non-test targets
    app_coverages = []
    for target in targets:
        name = target.get('name', '')
        if 'Tests' in name or name.startswith('_'):
            continue
        cov = target.get('lineCoverage', 0)
        if cov > 0:
            app_coverages.append(cov)

    if app_coverages:
        avg = sum(app_coverages) / len(app_coverages)
        print(f'{avg * 100:.1f}')
        sys.exit(0)

    print('0')
except Exception as e:
    print('0', file=sys.stderr)
    print('0')
" || echo "0"
}

# Check coverage against threshold
check_coverage() {
    local coverage="$1"
    local threshold="$2"

    # Skip if coverage couldn't be determined
    local coverage_int
    coverage_int=$(echo "$coverage" | cut -d. -f1)

    if [ -z "$coverage_int" ] || [ "$coverage_int" -eq 0 ] 2>/dev/null; then
        log_warning "Could not determine valid coverage (got ${coverage}%). Skipping threshold check."
        return 0
    fi

    # Compare coverage to threshold
    if (( $(echo "$coverage < $threshold" | bc -l) )); then
        log_error "Code coverage ${coverage}% is below minimum threshold of ${threshold}%"
        return 1
    fi

    log_success "Code coverage ${coverage}% meets threshold of ${threshold}%"
    return 0
}

# Main execution
main() {
    log_info "UnaMentis Test Runner"
    log_info "===================="
    log_info "Test Type: $TEST_TYPE"
    log_info "Coverage Enabled: $ENABLE_COVERAGE"
    log_info "Coverage Threshold: $COVERAGE_THRESHOLD%"
    log_info "Enforce Coverage: $ENFORCE_COVERAGE"

    # Get simulator (with fallback)
    SIMULATOR=$(get_simulator "$SIMULATOR")
    log_info "Simulator: $SIMULATOR"

    # Build destination string
    DESTINATION="platform=iOS Simulator,name=$SIMULATOR"

    # Determine test target(s)
    local test_targets=""
    case "$TEST_TYPE" in
        unit)
            test_targets="-only-testing:UnaMentisTests/Unit"
            ;;
        integration)
            test_targets="-only-testing:UnaMentisTests/Integration"
            ;;
        all)
            test_targets=""  # Run all tests
            ;;
        *)
            log_error "Unknown TEST_TYPE: $TEST_TYPE (expected: unit, integration, or all)"
            exit 1
            ;;
    esac

    # Build xcodebuild command
    local cmd="xcodebuild test -project $PROJECT -scheme $SCHEME -destination '$DESTINATION'"

    if [ -n "$test_targets" ]; then
        cmd="$cmd $test_targets"
    fi

    if [ "$ENABLE_COVERAGE" = "true" ]; then
        cmd="$cmd -enableCodeCoverage YES"
    fi

    # Result bundle for coverage extraction
    local result_bundle="${RESULT_BUNDLE_PATH:-TestResults.xcresult}"
    cmd="$cmd -resultBundlePath '$result_bundle'"
    cmd="$cmd CODE_SIGNING_ALLOWED=NO"

    # Get beautify command
    local beautify_cmd
    beautify_cmd=$(get_xcbeautify_cmd)

    # Remove old result bundle
    rm -rf "$result_bundle"

    # Run tests
    log_info "Running $TEST_TYPE tests..."
    log_info "Command: $cmd | $beautify_cmd"
    echo ""

    set -o pipefail
    if ! eval "$cmd" 2>&1 | $beautify_cmd; then
        log_error "Tests failed!"
        exit 1
    fi

    log_success "Tests passed!"

    # Coverage extraction and enforcement
    if [ "$ENABLE_COVERAGE" = "true" ] && [ -d "$result_bundle" ]; then
        echo ""
        log_info "Extracting coverage..."
        local coverage
        coverage=$(extract_coverage "$result_bundle")
        log_info "Coverage: ${coverage}%"

        if [ "$ENFORCE_COVERAGE" = "true" ]; then
            if ! check_coverage "$coverage" "$COVERAGE_THRESHOLD"; then
                exit 1
            fi
        fi

        # Export coverage for CI consumption
        if [ "$CI" = "true" ]; then
            echo "coverage=$coverage" >> "$GITHUB_OUTPUT" 2>/dev/null || true
        fi
    fi

    echo ""
    log_success "All checks passed!"
}

main "$@"
