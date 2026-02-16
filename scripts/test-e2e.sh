#!/bin/bash
set -eo pipefail
if [ ! -f .env ]; then
  echo "Error: .env file not found. Copy .env.example and add your API keys."
  exit 1
fi
source .env
if [ "$RUN_E2E_TESTS" != "true" ]; then
  echo "E2E tests disabled. Set RUN_E2E_TESTS=true in .env to run."
  exit 0
fi

# Generate Xcode project if needed
if [ ! -f "UnaMentis.xcodeproj/project.pbxproj" ]; then
  echo "Generating Xcode project..."
  xcodegen generate
fi

# Check E2E tests exist
if [ ! -d "UnaMentisTests/E2E" ] || [ -z "$(ls -A UnaMentisTests/E2E 2>/dev/null)" ]; then
  echo "No E2E tests found in UnaMentisTests/E2E/. Nothing to run."
  exit 0
fi

echo "Running E2E tests (this may take 10-30 minutes)..."

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

xcodebuild test \
  -project UnaMentis.xcodeproj \
  -scheme UnaMentis \
  -destination "$SIM_DEST" \
  -only-testing:UnaMentisTests/E2E \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify
echo "E2E tests passed"
