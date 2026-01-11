#!/bin/bash
set -e
echo "Running quick tests..."
if command -v xcodebuild &> /dev/null; then
    xcodebuild test \
      -project UnaMentis.xcodeproj \
      -scheme UnaMentis \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -only-testing:UnaMentisTests/Unit \
      CODE_SIGNING_ALLOWED=NO \
      | xcbeautify
    echo "Quick tests passed"
else
    echo "xcodebuild not available, skipping tests"
fi
