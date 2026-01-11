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
  simulatorName: "iPhone 16 Pro"
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
# iOS build (uses iPhone 16 Pro for CI parity)
xcodebuild -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Testing (use the unified test runner for CI parity)
./scripts/test-quick.sh          # Unit tests only (fast)
./scripts/test-all.sh            # All tests + 80% coverage enforcement
./scripts/test-integration.sh    # Integration tests only
./scripts/test-ci.sh             # Direct runner with env var config

# Lint and format
./scripts/lint.sh
./scripts/format.sh

# Health check (lint + quick tests)
./scripts/health-check.sh

# Latency testing (see server/latency_harness/CLAUDE.md for details)
python -m latency_harness.cli --list-suites
python -m latency_harness.cli --suite quick_validation --mock
python -m latency_harness.cli --suite quick_validation --no-mock  # Real providers

# Hook audit (check for bypasses)
./scripts/hook-audit.sh
```

### Unified Test Runner

The `test-ci.sh` script is the single source of truth for test execution, used by both local scripts and CI workflows. This ensures local and CI environments behave identically.

```bash
# Environment variables for test-ci.sh:
TEST_TYPE=unit|integration|all  # Default: unit
SIMULATOR="iPhone 16 Pro"       # Default: iPhone 16 Pro (with fallback)
COVERAGE_THRESHOLD=80           # Default: 80%
ENABLE_COVERAGE=true|false      # Default: true
ENFORCE_COVERAGE=true|false     # Default: true in CI, false locally
```

## Server Management

**Use the `/service` skill for all service control.** Never use bash commands like pkill.

```
/service status              # Show all services
/service restart management-api  # Restart specific service
/service start-all           # Start all services
```

The USM menu bar app must be running. See `.claude/skills/service/SKILL.md` for full documentation.

## MANDATORY: Log Server for Debugging

**The log server MUST be running for debugging.** Use the `/debug-logs` skill for structured debugging:

```
/debug-logs              # Check log server and view recent logs
/debug-logs capture      # Clear, reproduce issue, then analyze
/debug-logs analyze      # Analyze current logs for issues
```

Log server runs on port 8765. Web UI at http://localhost:8765/

See `.claude/skills/debug-logs/SKILL.md` for the complete debugging workflow.

## MANDATORY: Definition of Done

**NO IMPLEMENTATION IS COMPLETE UNTIL `/validate` PASSES.** This is the single most important rule.

### The Golden Rule

Before marking any work "complete", run:
```
/validate           # Lint + quick tests
/validate --full    # For significant changes
```

**WRONG:** Write code, see it compiles, tell user "implementation is complete"
**RIGHT:** Write code, run `/validate`, verify PASS, THEN tell user "implementation is complete"

See `.claude/skills/validate/SKILL.md` for the complete validation workflow.

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

**BEFORE EVERY COMMIT:** Run `/validate` and ensure it passes. Do NOT commit if validation fails.

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
- `docs/testing/CHAOS_ENGINEERING_RUNBOOK.md` - Voice pipeline resilience testing

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

## Mutation Testing

Mutation testing validates that tests actually catch bugs, not just cover lines. A weekly workflow runs mutation testing:

```bash
# View mutation testing workflow
# .github/workflows/mutation.yml - Runs Sundays at 4am UTC
# Supports: mutmut (Python), Stryker (Web), Muter (iOS manual)
```

## Chaos Engineering

Voice pipeline resilience testing validates graceful degradation under adverse conditions:

```bash
# See the runbook for test scenarios
docs/testing/CHAOS_ENGINEERING_RUNBOOK.md

# Test scenarios include:
# - Network degradation (high latency, packet loss)
# - API timeouts and failures
# - Memory pressure and thermal throttling
```

## Cross-Repository Access

This project has read access to related external repositories. Use this when you need to reference code, patterns, or documentation from other UnaMentis projects.

### Available External Repos

| Repo | Path | Purpose |
|------|------|---------|
| unamentis-android | /Users/ramerman/dev/unamentis-android | Android client for UnaMentis |

### How to Use

Access is always active. Use absolute paths with Read, Grep, and Glob:

```bash
# Find files
Glob: /Users/ramerman/dev/unamentis-android/**/*.kt

# Search content
Grep: pattern in /Users/ramerman/dev/unamentis-android/

# Read specific file
Read: /Users/ramerman/dev/unamentis-android/README.md
```

### Read-Only Constraint

For explicit read-only mode, invoke `/read-external`. This restricts tools to Read, Grep, Glob, and Task only.

### Adding New Repos

See `.claude/skills/read-external/TEMPLATE.md` for instructions on adding additional external repositories.

## Available Skills

Skills are focused workflows that provide consistency and predictability. Invoke with `/skill-name`.

| Skill | Purpose | Usage |
|-------|---------|-------|
| `/validate` | Pre-commit validation (lint + tests) | Before marking work complete |
| `/service` | Manage services via USM API | Service control operations |
| `/debug-logs` | Log server debugging workflow | Troubleshooting issues |
| `/review` | Code review (CodeRabbit AI + manual) | Before PRs or code review |
| `/mcp-setup` | Configure MCP session defaults | Start of dev session |
| `/read-external` | Cross-repo read access | Reference external repos |
| `/comms` | Post to Slack/Trello with natural language | Team communication |

### Key Skills

**`/validate`** - Enforces "Definition of Done"
```
/validate           # Lint + quick tests
/validate --full    # Lint + full test suite + 80% coverage enforcement
```

**`/service`** - USM API service management (never use pkill!)
```
/service status              # Show all services
/service restart management-api  # Restart specific service
```

**`/debug-logs`** - Structured debugging with log server
```
/debug-logs capture    # Clear, wait, analyze
/debug-logs analyze    # Analyze current logs
```

**`/review`** - Code review with CodeRabbit AI + manual checks
```
/review              # Full review: CodeRabbit + manual
/review --quick      # Quick CodeRabbit review only
/review staged       # Review staged changes only
```

**`/mcp-setup`** - Configure MCP for iOS/USM development
```
/mcp-setup ios       # Main iOS app
/mcp-setup usm       # Server Manager app
```

See `.claude/skills/*/SKILL.md` for detailed documentation on each skill.
