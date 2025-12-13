#!/bin/bash
set -e
echo "Running full test suite..."
xcodebuild test \
  -scheme VoiceLearn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify
echo "All tests passed"
