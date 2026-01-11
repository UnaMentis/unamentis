#!/bin/bash
set -e
echo "Running quick tests..."

# Check if xcodebuild is available (macOS only)
if ! command -v xcodebuild &> /dev/null; then
    echo "Warning: xcodebuild not available (requires macOS), skipping tests"
    exit 0
fi

xcodebuild test \
  -project UnaMentis.xcodeproj \
  -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnaMentisTests/Unit \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify
echo "Quick tests passed"
