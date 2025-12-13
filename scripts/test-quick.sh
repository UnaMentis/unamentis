#!/bin/bash
set -e
echo "Running quick tests..."
xcodebuild test \
  -scheme VoiceLearn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VoiceLearnTests/Unit \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify
echo "Quick tests passed"
