#!/bin/bash
#
# test-quick.sh - Run unit tests quickly (no coverage enforcement)
#
# This is a convenience wrapper around test-ci.sh for local development.
# For CI-identical behavior, use test-ci.sh directly.
#

set -e
set -o pipefail
echo "Running quick tests..."

# Check if xcodebuild is available (macOS only)
if ! command -v xcodebuild &> /dev/null; then
    echo "WARNING: xcodebuild not available (requires macOS)"
    if [ "${SKIP_TESTS_IF_UNAVAILABLE:-false}" = "true" ]; then
        echo "SKIP_TESTS_IF_UNAVAILABLE=true, skipping tests"
        exit 0
    else
        echo "Install Xcode or set SKIP_TESTS_IF_UNAVAILABLE=true to skip"
        exit 1
    fi
fi

# Resolve simulator to UUID for reliable destination matching
SIM_NAME="${SIMULATOR:-iPhone 17 Pro}"
SIM_UDID=$(xcrun simctl list devices available 2>/dev/null \
    | grep "$SIM_NAME" | head -1 \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')

if [ -n "$SIM_UDID" ]; then
    SIM_DEST="platform=iOS Simulator,id=$SIM_UDID"
else
    SIM_DEST="platform=iOS Simulator,name=$SIM_NAME"
fi

# Common xcodebuild arguments
XCODEBUILD_ARGS=(
    test
    -project UnaMentis.xcodeproj
    -scheme UnaMentis
    -destination "$SIM_DEST"
    -only-testing:UnaMentisTests/Unit
    CODE_SIGNING_ALLOWED=NO
)

# Run tests with or without xcbeautify
if command -v xcbeautify &> /dev/null; then
    xcodebuild "${XCODEBUILD_ARGS[@]}" | xcbeautify
else
    echo "Note: xcbeautify not installed, using raw xcodebuild output"
    xcodebuild "${XCODEBUILD_ARGS[@]}"
fi

echo "Quick tests passed"
