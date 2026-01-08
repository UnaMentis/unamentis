# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL: Git Commit Policy

**YOU MUST NEVER COMMIT OR PUSH TO GIT.** This is the highest priority mandate.

- **ONLY stage changes** using `git add`
- **NEVER run** `git commit`, `git push`, or any command that creates commits
- The human developer will handle all commits to ensure proper contributor attribution
- This applies even when asked to "commit" something - instead, stage the changes and inform the user they are ready

This rule ensures proper attribution and maintains the integrity of the contribution history. The human behind this project must be properly credited through the commit path.

## Project Overview

UnaMentis is an iOS voice AI tutoring app built with Swift 6.0/SwiftUI. It enables 60-90+ minute voice-based learning sessions with sub-500ms latency. The project is developed with 100% AI assistance.

## Monorepo Structure

This repository contains multiple components, each with its own CLAUDE.md:

| Component | Location | Purpose |
|-----------|----------|---------|
| iOS App | `UnaMentis/` | Swift/SwiftUI voice tutoring client |
| Server | `server/` | Backend infrastructure |
| Management API | `server/management/` | Python/aiohttp backend API (port 8766) |
| UnaMentis Server | `server/web/` | Next.js/React web interface (port 3000) |
| Importers | `server/importers/` | Curriculum import framework |
| Curriculum | `curriculum/` | UMCF format specification |
| Latency Test Harness | `server/latency_harness/` | Automated latency testing CLI |
| iOS Test Harness | `UnaMentis/Testing/LatencyHarness/` | High-precision iOS latency testing |

See the CLAUDE.md in each directory for component-specific instructions.

## MANDATORY: MCP Server Integration

**You MUST use the configured MCP servers for all Xcode and Simulator operations.** This enables first-class, round-trip development and debugging.

### Required MCP Servers

Verify both servers are connected:
```bash
claude mcp list
# Should show:
# ios-simulator: ✓ Connected
# XcodeBuildMCP: ✓ Connected
```

If not connected, restart the Claude Code session.

### MCP Tools to Use

| Task | MCP Tool |
|------|----------|
| Set session defaults | `mcp__XcodeBuildMCP__session-set-defaults` |
| Build for simulator | `mcp__XcodeBuildMCP__build_sim` |
| Build and run | `mcp__XcodeBuildMCP__build_run_sim` |
| Install app | `mcp__XcodeBuildMCP__install_app_sim` |
| Launch app | `mcp__XcodeBuildMCP__launch_app_sim` |
| Capture logs | `mcp__XcodeBuildMCP__start_sim_log_cap` / `stop_sim_log_cap` |
| Take screenshot | `mcp__XcodeBuildMCP__screenshot` or `mcp__ios-simulator__screenshot` |
| Describe UI | `mcp__XcodeBuildMCP__describe_ui` |
| Tap UI | `mcp__XcodeBuildMCP__tap` or `mcp__ios-simulator__ui_tap` |
| Type text | `mcp__XcodeBuildMCP__type_text` or `mcp__ios-simulator__ui_type` |
| Swipe | `mcp__XcodeBuildMCP__swipe` or `mcp__ios-simulator__ui_swipe` |
| Gestures | `mcp__XcodeBuildMCP__gesture` |

**Important**: Before building, set session defaults:
```
mcp__XcodeBuildMCP__session-set-defaults({
  projectPath: "/Users/ramerman/dev/unamentis/UnaMentis.xcodeproj",
  scheme: "UnaMentis",
  simulatorName: "iPhone 17 Pro"
})
```

### Round-Trip Debugging Workflow

When debugging UI issues:
1. Build with XcodeBuildMCP
2. Install and launch with XcodeBuildMCP
3. Capture logs with XcodeBuildMCP
4. Screenshot with ios-simulator MCP
5. Interact with ios-simulator MCP
6. Analyze and iterate

This workflow allows autonomous debugging without manual user intervention.

## Quick Commands

```bash
# iOS build
xcodebuild -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run all tests
xcodebuild test -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Quick tests
./scripts/test-quick.sh

# All tests
./scripts/test-all.sh

# Lint and format
./scripts/lint.sh
./scripts/format.sh

# Health check (lint + quick tests)
./scripts/health-check.sh

# Latency testing (see server/latency_harness/CLAUDE.md for details)
python -m latency_harness.cli --list-suites
python -m latency_harness.cli --suite quick_validation --mock
python -m latency_harness.cli --suite quick_validation --no-mock  # Real providers
```

## MANDATORY: Log Server Must Always Be Running

**The log server MUST be running whenever the iOS app or any server is running.** This is non-negotiable.

```bash
# Start log server FIRST, before anything else
python3 scripts/log_server.py &

# Verify it's running
curl -s http://localhost:8765/health  # Returns "OK"
```

**Access logs:**
- Web interface: http://localhost:8765/
- JSON API: `curl -s http://localhost:8765/logs`
- Clear logs: `curl -s -X POST http://localhost:8765/clear`

**When debugging issues:**
1. Ensure log server is running
2. Clear logs: `curl -s -X POST http://localhost:8765/clear`
3. Reproduce the issue
4. Fetch logs: `curl -s http://localhost:8765/logs | python3 -m json.tool`
5. The last log message before a freeze identifies the blocking point

Without the log server, debugging is guesswork. Always start it first.

## MANDATORY: Definition of Done

**NO IMPLEMENTATION IS COMPLETE UNTIL TESTS PASS.** This is the single most important rule.

### The Golden Rule
You MUST run `./scripts/test-quick.sh` (or `./scripts/test-all.sh` for significant changes) and verify ALL tests pass BEFORE:
- Telling the user the work is "done" or "complete"
- Summarizing what you accomplished
- Moving on to the next task
- Committing any changes

### What "Complete" Means
1. Code is written and compiles
2. `./scripts/lint.sh` passes with no violations
3. `./scripts/test-quick.sh` passes with ALL tests green
4. You have ACTUALLY RUN these commands and seen the results yourself

### Failure Mode to Avoid
**WRONG:** Write code, see it compiles, tell user "implementation is complete"
**RIGHT:** Write code, run tests, verify all pass, THEN tell user "implementation is complete"

If you tell the user "tests are passing" or "implementation is complete" when tests are actually failing, you have failed at your job. Always verify by running tests locally.

### Pre-Commit Checklist
```bash
./scripts/lint.sh && ./scripts/test-quick.sh
```

If either command fails, fix the issues before proceeding.

## Key Technical Requirements

**Testing Philosophy (Real Over Mock):**
- Only mock paid external APIs (LLM, STT, TTS, Embeddings)
- Use real implementations for all internal services
- See `AGENTS.md` for detailed testing philosophy

**Performance Targets:**
- E2E turn latency: <500ms (median), <1000ms (P99)
- Memory growth: <50MB over 90 minutes
- Session stability: 90+ minutes without crashes

## Multi-Agent Coordination

Check `docs/TASK_STATUS.md` before starting work. Claim tasks before working to prevent conflicts with other AI agents.

## Commit Convention

Follow Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `perf:`, `ci:`, `chore:`

**BEFORE EVERY COMMIT:**
```bash
./scripts/lint.sh && ./scripts/test-quick.sh
```

Do NOT commit if either command fails. Fix the issues first.

## Key Documentation

- `docs/setup/DEV_ENVIRONMENT.md` - **Developer environment setup guide**
- `docs/ios/IOS_STYLE_GUIDE.md` - Mandatory iOS coding standards
- `docs/architecture/UnaMentis_TDD.md` - Technical design document
- `docs/architecture/PROJECT_OVERVIEW.md` - **Authoritative project overview (must be kept current)**
- `docs/TASK_STATUS.md` - Current task status
- `AGENTS.md` - AI development guidelines and testing philosophy
- `curriculum/README.md` - UMCF curriculum format
- `docs/LATENCY_TEST_HARNESS_GUIDE.md` - Latency harness usage guide
- `docs/design/AUDIO_LATENCY_TEST_HARNESS.md` - Latency harness architecture

## MANDATORY: PROJECT_OVERVIEW.md Maintenance

The file `docs/architecture/PROJECT_OVERVIEW.md` is the **authoritative project overview** used to update the website and communicate project status. Keeping it current is part of the definition of done.

**Update PROJECT_OVERVIEW.md when:**
- Adding a new AI model or provider (STT, TTS, LLM, VAD, Embeddings)
- Adding a new client application or platform
- Adding a new server component or API
- Implementing a significant feature
- Completing a roadmap phase

**Required content (must always be complete):**
- All AI models with names and characteristics
- All client applications with status (iOS, Web, Android)
- All server components with ports and tech stacks
- All self-hosted server options
- Accurate service counts
- Current completion status

This is not optional. The document is used externally and must reflect the true state of the project.

## Autonomous Latency Testing

AI agents can autonomously run latency tests to validate changes and detect regressions. The CLI commands are pre-approved and do not require user confirmation.

### When to Run Tests

| Situation | Suite | Mode | Command |
|-----------|-------|------|---------|
| Before provider changes | `quick_validation` | mock | `python -m latency_harness.cli --suite quick_validation --mock` |
| After provider changes | `quick_validation` | real | `python -m latency_harness.cli --suite quick_validation --no-mock` |
| Investigating performance | `provider_comparison` | real | `python -m latency_harness.cli --suite provider_comparison --no-mock` |

### Decision Tree

```
Has provider code changed? -> Yes -> Run quick_validation --no-mock
                          -> No  -> Run quick_validation --mock

Did validation fail?      -> Yes -> Run provider_comparison for investigation
                          -> No  -> Proceed with work
```

### Interpreting Results

- **Exit code 0**: All tests passed, performance within targets
- **Exit code 1**: Tests failed or regressions detected
- **JSON output**: Use `--format json` for machine-readable results

### Baseline Management

```bash
# List baselines
curl -s http://localhost:8766/api/latency-tests/baselines

# Create baseline from completed run
curl -X POST http://localhost:8766/api/latency-tests/baselines \
  -H "Content-Type: application/json" \
  -d '{"runId": "run_xxx", "name": "v1.0 baseline", "setActive": true}'

# Check run against baseline
curl -s "http://localhost:8766/api/latency-tests/baselines/{id}/check?runId=run_yyy"
```

### Target Metrics

- E2E latency: <500ms median, <1000ms P99 (localhost)
- These targets inform test pass/fail criteria

See `server/latency_harness/CLAUDE.md` for detailed CLI documentation.
