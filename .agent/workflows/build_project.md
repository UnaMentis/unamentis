---
description: Build the UnaMentis project (compilation check)
---

# Build Project (Turbo)

This workflow builds the UnaMentis project to verify compilation.

Build using xcodebuild (iPhone 16 Pro for CI parity):
```bash
xcodebuild build -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Or use MCP:
```
mcp__XcodeBuildMCP__build_sim()
```
