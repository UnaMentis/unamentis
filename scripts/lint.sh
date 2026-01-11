#!/bin/bash
set -e
echo "Running SwiftLint..."
if command -v swiftlint &> /dev/null; then
    swiftlint lint --strict
    echo "Code passes linting"
else
    echo "SwiftLint not installed, skipping lint check"
fi
