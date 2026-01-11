---
description: Allowlist for xcodebuild commands
---

# Allowed Xcodebuild Commands

This workflow defines allowed xcodebuild commands for turbo execution.

// turbo-all

1. Run tests with filtering (Clean):
```bash
xcodebuild clean test -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:UnaMentisTests/CurriculumEngineTests -only-testing:UnaMentisTests/DocumentProcessorTests -only-testing:UnaMentisTests/ProgressTrackerTests
```

2. Run tests with filtering (No Clean):
```bash
xcodebuild test -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:UnaMentisTests/CurriculumEngineTests -only-testing:UnaMentisTests/DocumentProcessorTests -only-testing:UnaMentisTests/ProgressTrackerTests
```

3. Run filtered tests (iPhone 16 Pro variant):
```bash
xcodebuild test -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:UnaMentisTests/ProgressTrackerTests
```

4. Build Project:
```bash
xcodebuild build -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

5. Clean Build Project:
```bash
xcodebuild clean build -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

6. Run All Tests:
```bash
xcodebuild test -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

7. Run CurriculumEngineTests Only:
```bash
xcodebuild test -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:UnaMentisTests/CurriculumEngineTests
```

8. Run ProgressTrackerTests Only (iPhone 16 Pro):
```bash
xcodebuild test -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:UnaMentisTests/ProgressTrackerTests
```
