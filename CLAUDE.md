# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL: Git Commit Policy

**Claude may commit ONLY on an explicit, real-time command from the human, and must NEVER push.**

- **Staging** (`git add`) is always allowed.
- **Committing** (`git commit`) is allowed ONLY when the human gives a direct, in-the-moment instruction to commit (for example, "commit this"). There is no standing or blanket permission: each commit needs its own explicit go-ahead, so the human keeps the final call and the commit message is right. Without that explicit command, stage the changes and tell the human they are ready.
- **Pushing** (`git push`, or anything that publishes to a remote) is NEVER done by Claude. The human handles all pushes.

This keeps the human making the final call on what lands and preserves the integrity of the contribution history.

## Project Overview

UnaMentis is a voice AI learning platform. This repository contains the server infrastructure, documentation, and curriculum. The project is developed with 100% AI assistance.

**The iOS app is in a separate repository:** `unamentis-ios` at `/Users/ramerman/dev/unamentis-ios/`

## Repository Structure

| Component | Location | Purpose |
|-----------|----------|---------|
| Server | `server/` | Backend infrastructure |
| **USM Core** | `server/usm-core/` | Rust cross-platform service manager (port 8787) |
| Management API | `server/management/` | Python/aiohttp backend API (port 8766) |
| Web Interface | `server/web/` | Next.js/React web interface (port 3000) |
| Importers | `server/importers/` | Curriculum import framework |
| Curriculum | `curriculum/` | UMCF format specification |
| Latency Test Harness | `server/latency_harness/` | Automated latency testing CLI |
| Demo Video Generator | `demo/` | Automated iOS demo video creation |

### Related Repositories

| Repo | Path | Purpose |
|------|------|---------|
| unamentis-ios | `/Users/ramerman/dev/unamentis-ios/` | iOS client (Swift 6/SwiftUI) |
| unamentis-android | `/Users/ramerman/dev/unamentis-android/` | Android client (Kotlin) |
| unamentis-models | `/Users/ramerman/dev/unamentis-models/` | Shared ML models |

See the CLAUDE.md in each directory for component-specific instructions.

## iOS Development

**iOS development has moved to the `unamentis-ios` repo.** See `/Users/ramerman/dev/unamentis-ios/CLAUDE.md` for MCP servers, Xcode project generation, and iOS build commands.

## Quick Commands

```bash
# Latency testing (see server/latency_harness/CLAUDE.md for details)
python -m latency_harness.cli --list-suites
python -m latency_harness.cli --suite quick_validation --mock
python -m latency_harness.cli --suite quick_validation --no-mock  # Real providers

# Hook audit (check for bypasses)
./scripts/hook-audit.sh

# Rust (USM Core)
cd server/usm-core
cargo build                      # Debug build
cargo build --release            # Release build (optimized)
cargo test                       # Run all tests
cargo clippy -- -D warnings      # Lint with clippy
cargo fmt                        # Format code
cargo fmt --check                # Check formatting without modifying
```

For iOS build/test commands, see `unamentis-ios/CLAUDE.md`.

## Server Management

**Use the `/service` skill for all service control.** Never use bash commands like pkill.

```
/service status              # Show all services
/service restart management-api  # Restart specific service
/service start-all           # Start all services
```

The USM menu bar app must be running. See `.claude/skills/service/SKILL.md` for full documentation.

## MANDATORY: Graceful Application Termination

**Always use graceful quit commands to stop applications. Never use kill as a first resort.**

**IMPORTANT: UnaMentis/USM services MUST be controlled via the `/service` USM API only. The commands below apply to non-USM applications only. Never use pkill, killall, or kill on USM-managed services.**

This is a universal principle across all operating systems. Graceful termination allows applications to:
- Save state and user data
- Clean up resources properly
- Close file handles and network connections
- Avoid data corruption

### macOS

**Note:** These commands are for non-USM applications only. For USM-managed services, use `/service stop <service-name>`.

```bash
# CORRECT: Graceful quit via AppleScript
osascript -e 'tell application "AppName" to quit'

# CORRECT: Graceful termination signal (non-USM apps only)
pkill -TERM ProcessName

# LAST RESORT ONLY: Forceful kill (non-USM apps only)
killall ProcessName        # Sends SIGTERM by default
kill -9 PID               # SIGKILL - cannot be caught, use only when app is unresponsive
```

### Linux

**Note:** These commands are for non-USM applications only. For USM-managed services, use `/service stop <service-name>`.

```bash
# CORRECT: Graceful termination (non-USM apps only)
kill PID                  # Sends SIGTERM
pkill ProcessName         # Sends SIGTERM

# LAST RESORT ONLY: Forceful kill (non-USM apps only)
kill -9 PID              # SIGKILL
pkill -9 ProcessName     # SIGKILL
```

### Windows

```powershell
# CORRECT: Graceful termination
Stop-Process -Name "ProcessName"

# LAST RESORT ONLY: Forceful kill
Stop-Process -Name "ProcessName" -Force
taskkill /F /IM "ProcessName.exe"
```

**Rule: Attempt graceful quit first. Only escalate to forceful termination if the application is unresponsive.**

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

## Pre-Commit Hook: Quality Enforcement

The pre-commit hook enforces code quality through multiple checks.

### Mock Test Detection

Enforces the "Real Over Mock" testing philosophy by blocking commits with forbidden mock patterns:

| Language | Forbidden Patterns | Allowed Exceptions |
|----------|-------------------|-------------------|
| Python | `class Mock*`, `MagicMock()`, `AsyncMock()` | `# ALLOWED: <reason>` comment |
| TypeScript | `vi.mock('@/lib/...')` | `// ALLOWED: <reason>` comment |
| Rust | `mockall` crate, `mock!` macro, `struct Mock*` | `// ALLOWED: <reason>` comment |

For Swift mock test detection, see `unamentis-ios/.hooks/pre-commit`.

**Remediation:** Use real implementations with fixtures. See `docs/testing/MOCK_VIOLATIONS_INVENTORY.md` for patterns.

### Dependency Vulnerability Scanning

When `requirements*.txt` or `package.json`/`pnpm-lock.yaml` are staged, the hook scans for known vulnerabilities:

- **Python:** Uses `pip-audit` (install: `pip install pip-audit`)
- **Node.js:** Uses `pnpm audit` or `npm audit`

These checks are **warning-only** and won't block commits. CI enforces strictly.

## MANDATORY: Tool Trust Doctrine

**All findings from security and quality tools are presumed legitimate until proven otherwise through rigorous analysis.**

### The Principle

When CodeQL, SwiftLint, Ruff, Clippy, ESLint, or any established tool flags an issue:

1. **Assume it's real** (not "might be real", assume it IS real)
2. **Investigate deeply** (full data flow analysis, not cursory review)
3. **Fix the code** (the default outcome)
4. **Adapt patterns** (if tools don't understand our code, our code should change)

### What You Must NEVER Do

- Create custom configs to suppress tool findings as a first response
- Dismiss findings as "false positives" without exhaustive proof
- Work around tools instead of fixing the underlying code
- Assume your code is correct and the tool is wrong

### Process for Tool Findings

```
Tool flags an issue
        ↓
Assume it's legitimate (DEFAULT)
        ↓
Deep investigation
        ↓
    ┌───┴───┐
    ↓       ↓
Real issue? → Fix the code, adapt patterns
    ↓
Proven false positive? → Document WHY in detail
                       → Consider if pattern should change anyway
                       → Only then suppress (with audit trail)
```

### Proving a False Positive Requires

1. Full data flow trace showing why the concern doesn't apply
2. Edge case analysis (what if code is refactored? copied?)
3. Written documentation in PR or commit
4. Answer: Could this be written in a tool-recognized way?

See `docs/quality/TOOL_TRUST_DOCTRINE.md` and the "Tool Trust Doctrine" section in `AGENTS.md` for full documentation and case studies.

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

## Parallel Development with Worktrees

Use `/worktree` skill to manage isolated development sessions for 2-4 parallel tasks:

```
/worktree create kb-feature    # Create worktree + auto-open VS Code
/worktree list                 # List all worktrees with disk usage
/worktree cleanup              # Clean DerivedData from inactive worktrees
```

Each worktree:
- Has complete file isolation (no stashing/switching needed)
- Runs an independent Claude Code session
- Has its own MCP connections (run `/mcp-setup ios` in each)
- Shares the same git history (lightweight, no repo duplication)

Worktrees are created as siblings: `../unamentis-<name>/`

See `.claude/skills/worktree/SKILL.md` for full documentation.

## Commit Convention

Follow Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `perf:`, `ci:`, `chore:`

**BEFORE EVERY COMMIT:** Run `/validate` and ensure it passes. Do NOT commit if validation fails.

## Accumulative Commit Message Tracking

Claude automatically tracks work completed, building commit message notes tied to the current uncommitted changes.

### How It Works
1. After completing a logical unit of work, Claude appends a note to `.claude/draft-commit.md`
2. Before appending, Claude reads existing content and consolidates:
   - Identical items are skipped
   - Related count-based items get combined when specifics don't matter
   - Specifics are preserved when they add value beyond what's obvious from the changed files
3. Claude never removes content it didn't add

### Detail Level
- **Be specific** when it tells a story (e.g., "Added retry logic with exponential backoff")
- **Be concise** when obvious from context (e.g., don't mention routine import updates)
- **Use counts** when individual items aren't important (e.g., "Fixed 5 linting warnings")

### Viewing and Clearing
- Use `/commit-message` to view the accumulated notes formatted for commit
- Use `/commit-message clear` to manually reset if needed
- The draft is **automatically cleared** by the post-commit hook after successful commits

### Lifecycle
1. Work begins, draft accumulates notes
2. Work complete, human reviews draft via `/commit-message`
3. Human commits with their preferred message
4. Post-commit hook automatically clears the draft for the next commit

## Key Documentation

**This repo is the single source of truth for cross-cutting documentation.** Client-specific docs live in their respective repos (unamentis-ios, unamentis-android). Cross-cutting docs (client-spec, modules, design, testing philosophy) live here.

- `docs/setup/DEV_ENVIRONMENT.md` - **Developer environment setup guide**
- `docs/architecture/UnaMentis_TDD.md` - Technical design document
- `docs/architecture/PROJECT_OVERVIEW.md` - **Authoritative project overview (must be kept current)**
- `docs/TASK_STATUS.md` - Current task status
- `AGENTS.md` - AI development guidelines and testing philosophy
- `curriculum/README.md` - UMCF curriculum format
- `docs/LATENCY_TEST_HARNESS_GUIDE.md` - Latency harness usage guide
- `docs/design/AUDIO_LATENCY_TEST_HARNESS.md` - Latency harness architecture
- `docs/testing/CHAOS_ENGINEERING_RUNBOOK.md` - Voice pipeline resilience testing

For iOS-specific docs (style guide, app architecture), see `unamentis-ios/docs/`.
For Android-specific docs (dev environment, API reference), see `unamentis-android/docs/`.

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

This project has read access to all UnaMentis ecosystem repositories via global additionalDirectories.

### Available External Repos

| Repo | Path | Purpose |
|------|------|---------|
| unamentis-ios | /Users/ramerman/dev/unamentis-ios | iOS client (standalone repo) |
| unamentis-android | /Users/ramerman/dev/unamentis-android | Android client |
| unamentis-models | /Users/ramerman/dev/unamentis-models | Shared ML models |

### How to Use

Access is always active. Use absolute paths with Read, Grep, and Glob:

```bash
# iOS repo
Glob: /Users/ramerman/dev/unamentis-ios/**/*.swift

# Android repo
Glob: /Users/ramerman/dev/unamentis-android/**/*.kt

# Shared models
Read: /Users/ramerman/dev/unamentis-models/CLAUDE.md
```

### Read-Only Constraint

For explicit read-only mode, invoke `/read-external`. This restricts tools to Read, Grep, Glob, and Task only.

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
| `/worktree` | Manage git worktrees for parallel development | Parallel task isolation |

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

For iOS-specific skills (`/demo-video`, `/xcode-project`, `/mcp-setup ios`), see `unamentis-ios`.

See `.claude/skills/*/SKILL.md` for detailed documentation on each skill.
