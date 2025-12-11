---
description: Allowlist for xcodebuild commands
---

# Allowed Xcodebuild Commands

This workflow defines allowed xcodebuild commands for turbo execution.

// turbo-all

1. Run tests with filtering (Clean):
```bash
xcodebuild clean test -scheme VoiceLearn -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VoiceLearnTests/CurriculumEngineTests -only-testing:VoiceLearnTests/DocumentProcessorTests -only-testing:VoiceLearnTests/ProgressTrackerTests
```

2. Run tests with filtering (No Clean):
```bash
xcodebuild test -scheme VoiceLearn -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VoiceLearnTests/CurriculumEngineTests -only-testing:VoiceLearnTests/DocumentProcessorTests -only-testing:VoiceLearnTests/ProgressTrackerTests
```

3. Run filtered tests (iPhone 16 Pro variant):
```bash
xcodebuild test -scheme VoiceLearn -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:VoiceLearnTests/ProgressTrackerTests
```

4. Build Project:
```bash
xcodebuild build -scheme VoiceLearn -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

5. Clean Build Project:
```bash
xcodebuild clean build -scheme VoiceLearn -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

6. Run All Tests:
```bash
xcodebuild test -scheme VoiceLearn -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
