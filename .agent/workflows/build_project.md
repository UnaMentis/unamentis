---
description: Build the VoiceLearn project (compilation check)
---

# Build Project (Turbo)

This workflow builds the VoiceLearn project to verify compilation.

// turbo-all
1.  Build the project using xcodebuild:
    ```bash
    xcodebuild build -scheme VoiceLearn -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
    ```
