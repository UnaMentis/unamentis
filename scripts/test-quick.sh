#!/bin/bash
set -e
echo "Running quick tests..."
xcodebuild test \
  -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:UnaMentisTests/Unit \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify
echo "Quick tests passed"
