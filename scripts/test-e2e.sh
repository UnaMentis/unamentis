#!/bin/bash
set -e
if [ ! -f .env ]; then
  echo "Error: .env file not found. Copy .env.example and add your API keys."
  exit 1
fi
source .env
if [ "$RUN_E2E_TESTS" != "true" ]; then
  echo "E2E tests disabled. Set RUN_E2E_TESTS=true in .env to run."
  exit 0
fi
echo "Running E2E tests (this may take 10-30 minutes)..."
xcodebuild test \
  -scheme VoiceLearn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VoiceLearnTests/E2E \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify
echo "E2E tests passed"
