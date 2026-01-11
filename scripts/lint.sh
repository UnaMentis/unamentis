#!/bin/bash
set -e
echo "Running SwiftLint..."

# Check if swiftlint is available
if ! command -v swiftlint &> /dev/null; then
    echo "Warning: SwiftLint not installed, skipping lint check"
    echo "Install with: brew install swiftlint"
    exit 0
fi

swiftlint lint --strict
echo "Code passes linting"
