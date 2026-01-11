---
description: Run UnaMentis unit tests with turbo mode
---

# Run Tests (Turbo)

This workflow runs the unit tests for the UnaMentis project.

**Preferred:** Use the unified test runner for CI parity:
```bash
./scripts/test-quick.sh          # Unit tests only (fast)
./scripts/test-all.sh            # All tests + 80% coverage enforcement
```

For specific tests, use xcodebuild directly:
```bash
xcodebuild test -scheme UnaMentis -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:UnaMentisTests/CurriculumEngineTests
```
