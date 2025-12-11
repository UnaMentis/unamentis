---
description: Run VoiceLearn unit tests with turbo mode
---

# Run Tests (Turbo)

This workflow runs the unit tests for the VoiceLearn project associated with the Curriculum feature.

// turbo-all
Run the tests using xcodebuild:
```bash
xcodebuild clean test -scheme VoiceLearn -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:VoiceLearnTests/CurriculumEngineTests -only-testing:VoiceLearnTests/DocumentProcessorTests -only-testing:VoiceLearnTests/ProgressTrackerTests
```
