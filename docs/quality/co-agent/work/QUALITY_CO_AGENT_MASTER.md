# Quality Co-Agent: Master Specification

## 1. Vision and Philosophy

The Quality Co-Agent transforms quality from **reactive gatekeeping** to **collaborative automation**. It is not a separate service providing notifications, but an integrated participant in the multi-agent development workflow that:

1. **Collaborates** with the development agent in real-time, running checks continuously as work progresses
2. **Fixes** deterministic issues automatically (formatting, simple lint) before reporting remaining issues requiring judgment
3. **Enables** extended autonomous work sessions where the development agent keeps building until 100% of quality gates pass
4. **Enforces** the Tool Trust Doctrine as part of the workflow, not after it
5. **Routes** complex issues to appropriate analyzers with trust-based triage

The unit of work shifts from "commit" to "completed feature with all gates passing." Quality becomes a collaborator that enables full automation, not a friction point that interrupts it.

### Constructive Tension Model

The co-agent operates with high agency and constructive tension: counterbalancing the development agent through architectural questioning, quality pushback, and pattern enforcement. This is not adversarial gatekeeping but collaborative enablement, helping the coding agent do its absolute best work by surfacing issues early and fixing what it can automatically.

### Control vs. Agency: The Central Trade-off

Two complementary paradigms compose the system:

- **Deterministic Controller** (Rigour model): Treats the agent as an untrusted component wrapped in a verified state machine. Limits the search space to valid solutions. Optimized for constraint satisfaction. Cannot be bypassed by the LLM.
- **Generalist Orchestrator** (Goose model): Treats the agent as a trusted reasoning engine with self-verification tools. Expands capabilities to include quality assurance. Optimized for capability amplification.

Rigour excels at "ensure this commit meets standards" (tunnel vision as feature). Goose excels at "find out why the build failed and fix it" (broad reasoning, file browsing, log reading). The two are complementary, not competing.

---

## 2. Architectural Foundation

### 2.1 Goose as the Base Runtime

The system is built custom on Goose (by Block), an open-source agent runtime. Goose provides:

- **Rust core**: Memory safety without garbage collection (critical for 24/7 daemon), async/await concurrency for simultaneous I/O, single static binary (reduced supply chain attack surface vs npm dependency trees)
- **Unix philosophy**: Goose focuses solely on being the Agent Runtime connecting Brain (LLM) to Hands (Tools). Interface and tools are delegated externally. If an MCP server crashes, Goose survives.
- **Code Mode with boa**: Embeds an experimental JavaScript engine in Rust. LLM generates JS executed safely within Goose's process boundary, with Rust "Native Functions" exposed to the JS environment for low-level IO/API calls.
- **Recipe system**: YAML-based workflow definitions specifying system prompt, context, capabilities, and JSON output schemas. Shareable via git or deep links (`goose recipe deeplink`).
- **Native MCP client**: Goose discovers capabilities via MCP over stdio (local) or SSE (remote). On startup, Goose reads config listing MCP Servers, spawns each process, performs a capability negotiation handshake, discovers available tools via JSON schema, and executes tools via `call_tool` JSON-RPC messages. Power grows linearly with ecosystem growth. Custom MCP servers work with Goose, Claude Desktop, and Cursor simultaneously.

### 2.2 Rigour as the Quality Logic Core

Rigour provides the deterministic quality enforcement layer, deployed as an MCP server (not standalone):

- **Run Loop Contract (FSM)**: A strict Finite State Machine compiled into the binary: Execute (agent writes code) -> Audit (agent locked out, verification tools run) -> Decision (PASS exits, FAIL injects Fix Packet) -> Retry. Cannot be bypassed by the LLM.
- **Fix Packet**: JSON object formalizing failure as structured data (status, iteration count, violations array with stderr, file paths, line numbers, rule IDs). LLMs treat structured JSON as "constraint" rather than "discussion," making Fix Packets more effective than chat-based error reporting. This is the "anti-vibe mechanism."
- **AST Gates**: Abstract Syntax Tree analysis (not regex) for structural code understanding. Cyclomatic complexity calculation, architectural boundary enforcement (e.g., detect View importing Model in MVC).
- **Standards Packs**: Declarative rule bundles. `api` pack (SOLID, layer boundaries, complexity limits), `ui` pack (component size, accessibility, data-fetching hygiene), `data` pack (no secrets in cells, deterministic pipelines). Customizing quality means modifying Packs, not the core loop.
- **Dual modes**: CLI Wrapper (`rigour run`, the "Hard Loop") and MCP Server (exposes `rigour_check`, `rigour_explain`). The Integration Pattern uses MCP mode.

### 2.3 The Integration Pattern (Recommended Hybrid)

- **Base**: Deploy standard Goose binary (no fork)
- **Extension**: Deploy Rigour as MCP Server
- **Orchestration**: Goose Recipe `interactive-quality-gate`:
  - Instructions: "You are a Quality Assistant. When writing code, you MUST verify using `rigour_check`. If it returns a Fix Packet, you MUST prioritize fixing those errors over any other instruction."
  - Tools: `rigour-mcp`, `file-system`, `git`
- **Benefits**: Polished Goose UX + Rigour AST gate logic + low maintenance (no forks)

**Exception**: For headless CI/CD bots in GitHub Actions, fork Rigour CLI for a tight Execute->Audit->Fix->Commit loop without UI overhead, optionally sandboxed in Docker with no network access.

### 2.4 Target Deployment Stack

| Component | Technology |
|-----------|------------|
| Agent Runtime | Goose (local daemon) |
| Tool Connectivity | Dockerized MCP Servers (`mcp/github`, `mcp/slack`, `mcp/filesystem` restricted to safe dirs) |
| Code Execution | E2B MCP Server (sandboxed Python) or Docker MCP Toolkit (containerized tools) |
| Interface | Goose CLI (engineering), Goose Desktop (assistant) |
| Remote Access | Goose Mobile App via secure tunnel |

### 2.5 State Management Paradigms

| Dimension | Rigour (Deterministic) | Goose (Emergent) |
|-----------|----------------------|------------------|
| Control logic | Hard-coded FSM compiled into binary, cannot be bypassed | LLM decides to call tools again; probabilistic |
| Reliability | If audit fails, loop retries. Agent forced to address failure | Agent may "get tired," hallucinate success, or skip checks |
| Failure mode | Infinite loop on unfixable errors until iteration limit | Drift: wander off-task, accept sub-optimal solutions |
| Context scope | Local (focused on diff/changed files, resets to minimize noise) | Session-based (remembers history, enables multi-turn reasoning, accumulates noise) |
| Suitability | Best for CI/CD: headless, non-interactive, "No" means "No" | Best for co-pilot: interactive, human-in-loop guidance |

### 2.6 Extensibility Comparison

| Vector | Rigour (Fork) | Goose (Base) |
|--------|--------------|--------------|
| New linter rule | Write new AST Gate (code change) | Add linter to MCP server (config/script change) |
| New capability (e.g., web search) | Hack the loop for external tool calls (difficult) | Enable MCP tool in Recipe (trivial) |
| Custom UI | Modify CLI or build custom frontend (difficult) | Uses standard Goose Desktop/CLI |
| Model swapping | Supported, but loop may be tuned to specific model behaviors | Native multi-model support |

---

## 3. Four-Layer Architecture Stack

```
Layer 3: Agent SDK (Programmatic Multi-Agent)
┌──────────────────────────────────────────────────────────┐
│ Quality Agent  |  Continuous Monitor  |  Subagents       │
└──────────────────────────────────────────────────────────┘
                            │
Layer 2: MCP Server (Tool Interface)
┌──────────────────────────────────────────────────────────┐
│ mcp__quality (format, lint, test, coverage, trust, gates)│
│ mcp__rigour (rigour_check, rigour_explain)               │
└──────────────────────────────────────────────────────────┘
                            │
Layer 1: Quality Tools (Existing)
┌──────────────────────────────────────────────────────────┐
│ SwiftLint | Ruff | Clippy | Bandit | ESLint | XcodeBuild │
└──────────────────────────────────────────────────────────┘
                            │
Layer 0: Collaborative State (GitHub)
┌──────────────────────────────────────────────────────────┐
│ GitHub Issues | GitHub Projects | Actions Artifacts       │
└──────────────────────────────────────────────────────────┘
```

---

## 4. Three-Agent Collaboration Model

| Agent | Mode | Tools | Purpose |
|-------|------|-------|---------|
| Development Agent | Interactive (Claude Code) | Read, Write, Edit, Bash, Glob, Grep, mcp__quality | Writes code, runs builds |
| Quality Agent | On-demand (Agent SDK) | Read, Grep, Glob, Task, mcp__quality, mcp__github | Analyzes on request, creates Issues |
| Continuous Monitor | Scheduled (CI/CD) | Read, Grep, Glob, Task, mcp__quality, mcp__github | Detects regressions, tracks trends |

All three share the same MCP tools and GitHub state, addressing different time scales: immediate, per-session, and continuous.

### Collaboration Flow

```
Development Agent writes code
    │
    ├── PostToolCall hook fires
    │   ├── Auto-Fixer runs (ruff format, swiftformat, rustfmt)
    │   ├── Stages formatting fixes
    │   ├── Tool Runner runs (SwiftLint, Ruff, Clippy, Bandit)
    │   ├── Tool Trust Engine classifies findings
    │   └── Updates shared quality state
    │
    ├── Development Agent reads state, fixes flagged issues
    │
    ├── Quality Agent spawned for complex analysis
    │   ├── Uses mcp__quality tools + mcp__rigour
    │   ├── Creates GitHub Issues for INVESTIGATE/BLOCK findings
    │   └── Returns structured summary
    │
    └── All gates pass -> ready for commit
```

### Quality Gates (Deterministic)

All must pass before work is considered complete:
- All tests pass (100%)
- Coverage >= 80%
- Zero high/critical findings
- Zero lint violations
- Build succeeds

---

## 5. Quality MCP Server

### File Layout

```
.claude/mcp-servers/quality/
├── server.py              # FastMCP server (Python, entry point)
├── tools/
│   ├── __init__.py
│   ├── formatting.py      # auto_format, format_and_stage
│   ├── linting.py         # run_lint, lint_all_changed
│   ├── testing.py         # run_tests, affected-only mode
│   ├── coverage.py        # check_coverage, delta tracking
│   ├── security.py        # Security scanning (CodeQL, Bandit)
│   └── github.py          # Issue creation/closing, Projects
├── trust_engine.py        # Tool Trust Doctrine logic (SQLite-backed)
├── state.py               # Shared state management
├── config.py              # Tool configurations
└── requirements.txt
```

### MCP Tools

| Tool | Purpose |
|------|---------|
| `auto_format(file_path, language)` | Format a file, return diff |
| `format_and_stage(file_path)` | Format and git-stage changes |
| `run_lint(file_path, fix)` | Lint with optional auto-fix, returns findings + trust decisions |
| `lint_all_changed()` | Lint all uncommitted files |
| `run_tests(test_type, affected_only)` | Run quick/integration/all tests |
| `check_coverage(threshold)` | Check coverage against threshold (default 80%) |
| `check_all_gates()` | Check all quality gates, return pass/fail per gate |
| `validate()` | Full validation (lint + quick tests + coverage) |
| `create_quality_issue(finding)` | Create GitHub Issue for a finding |
| `close_resolved_issues()` | Close Issues for resolved findings |
| `get_trust_decision(finding)` | Get Tool Trust decision for a finding |
| `record_dismissal(finding, reason, analysis)` | Record documented dismissal with audit trail |

### Server Registration

```json
// .mcp.json (project root)
{
  "mcpServers": {
    "quality": {
      "command": "python",
      "args": [".claude/mcp-servers/quality/server.py"],
      "env": {
        "PROJECT_ROOT": "/Users/ramerman/dev/unamentis",
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

### Server Entry Point

FastMCP-based Python server with `@mcp.tool()` decorators for each tool. Transport: stdio. Each tool integrates with the Tool Trust Engine before returning results. The `validate()` tool is equivalent to the `/validate` skill.

---

## 6. Tool Trust Engine

Automated enforcement of the Tool Trust Doctrine: all findings from established tools are presumed legitimate until proven otherwise through rigorous analysis.

### Trust Decision Flow

```
Finding received
    │
    ├── Check SQLite history for similar prior findings
    │   └── If documented_false_positive -> TRACK (monitor, don't block)
    │
    ├── Check tool trust level
    │   HIGH: CodeQL, SwiftLint, Ruff, Clippy, Bandit
    │
    ├── Classify by severity
    │   ├── critical/high from HIGH trust tool -> BLOCK (must fix before commit)
    │   ├── medium -> INVESTIGATE (create GitHub Issue for human review)
    │   └── low -> TRACK (monitor for patterns)
    │
    └── Record finding + decision to SQLite history
```

### Trust Decisions

| Decision | Action | State |
|----------|--------|-------|
| BLOCK | Prevent commit, require fix | GitHub Issue with `quality-blocking` label |
| INVESTIGATE | Flag for human review | GitHub Issue with `quality` label |
| TRACK | Monitor for patterns | Record in Actions artifact (no Issue) |

### Dismissal Audit Trail

Any dismissal requires: the finding, a short reason, full analysis proving false positive, and a data flow trace. All recorded in SQLite history. This creates a verifiable audit trail for compliance.

### Pattern Learning

Prior decisions inform future ones via SQLite pattern matching. Similar findings to previously-analyzed ones get consistent treatment automatically.

---

## 7. Shared Quality State

### Inter-Agent Communication

The `.claude/quality-state.json` file serves as asynchronous communication between the quality co-agent and development agent:

```json
{
  "last_updated": "ISO timestamp",
  "status": "issues_found|clean",
  "summary": {
    "total_findings": 2,
    "auto_fixed": 3,
    "blocking": 0,
    "needs_investigation": 2
  },
  "findings": [
    {
      "tool": "SwiftLint",
      "rule": "force_unwrapping",
      "severity": "warning",
      "file": "path/to/file.swift",
      "line": 142,
      "message": "Force unwrapping should be avoided",
      "trust_decision": "INVESTIGATE"
    }
  ],
  "quality_gates": {
    "tests_pass": true,
    "coverage_above_80": true,
    "lint_clean": false,
    "build_success": true,
    "all_pass": false
  }
}
```

### GitHub Collaborative State

- **Issues**: Created for INVESTIGATE and BLOCK findings. Labels: `quality`, `quality-blocking`, `tool:swiftlint`, `tool:bandit`, `severity:*`, `trust:*`. Auto-closed when findings are resolved.
- **Projects v2**: Dashboard with custom fields (Tool, Severity, Trust Decision, File Path, Status). Views by tool, severity, status.
- **Actions Artifacts**: Transient state (current findings, auto-fixed counts). 90-day retention.

---

## 8. Claude Code Hooks Integration

Lightweight hooks trigger quality checks automatically during development:

```json
{
  "hooks": {
    "PreToolCall": [
      {"matcher": "Write|Edit", "command": "python scripts/quality-coagent.py pre-write $FILE"}
    ],
    "PostToolCall": [
      {"matcher": "Write|Edit", "command": "python scripts/quality-coagent.py post-write $FILE"}
    ],
    "PreBash": [
      {"matcher": "git commit", "command": "python scripts/quality-coagent.py pre-commit"}
    ]
  }
}
```

### Post-Write Hook Workflow

1. Auto-Fixer runs on the changed file (ruff format, swiftformat, rustfmt, prettier)
2. Stages any formatting changes
3. Tool Runner runs on the fixed code (SwiftLint, Ruff, Clippy, Bandit, ESLint)
4. Tool Trust Engine classifies all findings
5. Updates shared quality state JSON
6. Development agent reads state to decide next action

### Swift-Specific Integration

When Swift files change, the co-agent also triggers incremental builds via XcodeBuildMCP:
```python
await mcp.call("XcodeBuildMCP", "build_sim", {"scheme": "UnaMentis", "configuration": "Debug"})
```

---

## 9. Agent SDK Definitions

### Quality Agent (On-Demand)

```python
quality_agent_options = ClaudeAgentOptions(
    allowed_tools=["Read", "Grep", "Glob", "Task", "mcp__quality", "mcp__github"],
    permission_mode="bypassPermissions",
    system_prompt="""You are a quality assurance specialist applying the Tool Trust Doctrine.
All findings from established tools are presumed legitimate until proven otherwise.
For each finding:
1. Check if auto-fixable -> fix and stage
2. Check severity -> BLOCK if critical/high, INVESTIGATE if medium, TRACK if low
3. Create GitHub Issue if BLOCK or INVESTIGATE""",
    agents={
        "security-scanner": AgentDefinition(
            description="Security vulnerability scanner (CodeQL, Bandit patterns)",
            tools=["Read", "Grep", "Glob"],
            model="opus"  # Most capable model for security
        ),
        "style-checker": AgentDefinition(
            description="Code style and lint checker",
            tools=["Read", "Grep", "Glob"]
        ),
        "coverage-analyzer": AgentDefinition(
            description="Test coverage gap analyzer",
            tools=["Read", "Grep", "Glob"]
        )
    }
)
```

### Continuous Monitor (Scheduled)

```python
continuous_monitor_options = ClaudeAgentOptions(
    allowed_tools=["Read", "Grep", "Glob", "Task", "mcp__quality", "mcp__github"],
    permission_mode="bypassPermissions",
    system_prompt="""You are a continuous quality monitor.
1. Compare current quality metrics to baseline
2. Detect quality regressions
3. Generate trend reports
4. Create GitHub Issues for new findings
5. Close Issues for resolved findings""",
    agents={
        "regression-detector": AgentDefinition(description="Quality regression detector"),
        "trend-analyzer": AgentDefinition(description="Quality trend analyzer")
    }
)
```

### Session Resumption

Complex analysis supports follow-up questions via session resumption:
```python
result = await quality_agent.query("Analyze the authentication module")
# Later:
follow_up = await quality_agent.query(
    f"Resume agent {agent_id}: Which findings are highest priority?",
    options=ClaudeAgentOptions(resume=session_id)
)
```

---

## 10. CI/CD Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/quality-monitor.yml
name: Continuous Quality Monitor
on:
  schedule:
    - cron: '0 */4 * * *'  # Every 4 hours
  pull_request:
  push:
    branches: [main, develop]

jobs:
  quality-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install claude-agent-sdk
      - run: curl -fsSL https://claude.ai/install.sh | bash
      - run: python scripts/quality_monitor.py
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - uses: actions/upload-artifact@v4
        with:
          name: quality-report
          path: quality_report.json
          retention-days: 90
```

### Audit Trail

Rigour's FSM naturally produces structured audit trails: sequences of Fix Packets and Audit results as JSON. These are directly usable as compliance artifacts. The CI/CD quality bot produces these automatically on every PR and push.

---

## 11. Security Architecture

### Defense in Depth (Three Sandboxing Levels)

| Level | Mechanism | Risk | Use Case |
|-------|-----------|------|----------|
| 0: Bare Metal | Agent runs as user process | Total compromise | Unacceptable for autonomous agents |
| 1: Container | Tools in Docker containers | Reduced (container escape possible) | Goose + Docker MCP Toolkit |
| 2: MicroVM | Ephemeral Firecracker VMs | Near zero | E2B MCP Server for untrusted code |

### Key Security Principles

- **Insider Threat model**: Agentic AI is probabilistic, generating its own commands from intent. Assume the LLM will be compromised/subverted. Restrict blast radius via sandboxing.
- **Prompt injection defense**: Structured Fix Packets (not chat text) for error feedback. AST Gates that examine code structure, not LLM explanations.
- **Local-only execution**: No network calls from quality tools. No credential handling (uses existing tool auth). No code transmission.
- **Subprocess isolation**: External tools run in subprocess with timeout.
- **Audit trail**: All dismissals logged with justification.
- **Secure remote access**: Outbound tunnels (Cloudflare) instead of exposed ports. Zero open inbound ports. E2E encrypted, QR handshake auth.

### Docker MCP Toolkit

Treats MCP servers as plug-and-play containers. Capabilities defined in `compose.yaml`. Full container isolation, isolated Docker network, ENV vars passed to container. Install: `docker run -d mcp/browser`. Update: `docker pull mcp/browser:latest`.

---

## 12. Key Design Patterns

### Auto-Fix Before Report

Unlike traditional linters that only report, the co-agent fixes deterministic issues first, then reports remaining issues. The developer only sees problems requiring judgment.

### Structured Error Injection (Fix Packets)

Errors fed back to the agent as structured JSON, not chat text. LLMs treat structured data as constraints to satisfy, not discussion to acknowledge. This defeats "Vibe Coding" where agents gloss over failures.

### Continuous Quality Loop

Quality checks run continuously during work via PostToolCall hooks, not as a gate at commit time. Issues are discovered and fixed during development, dramatically reducing pre-commit hook failures and CI failures.

### Trust-Based Finding Triage

Automated classification prevents alert fatigue. Only BLOCK and INVESTIGATE findings require human attention. TRACK findings are silently monitored for patterns. Prior decisions inform future ones automatically.

### MCP as Universal Quality Interface

All quality tools wrapped behind MCP, accessible to any MCP-compatible agent. Decouples quality enforcement from any specific runtime. A custom MCP server works with Goose, Claude Desktop, and Cursor simultaneously.

### Day 2 Operations Focus

Detailed MCP communication logs for debugging. When a tool call fails, inspect JSON-RPC messages to see exactly why. Observability is essential for maintaining complex agentic systems.

---

## 13. Implementation Phases

### Phase 1: Quality MCP Server

**Files:**
```
.claude/mcp-servers/quality/server.py
.claude/mcp-servers/quality/tools/__init__.py
.claude/mcp-servers/quality/tools/formatting.py
.claude/mcp-servers/quality/tools/linting.py
.claude/mcp-servers/quality/requirements.txt
.mcp.json
```

**Deliverables:** FastMCP server with `auto_format`, `format_and_stage`, `run_lint`, `check_all_gates`. Server registration. Hook configuration.

**Verification:** Test via `mcp-inspector python .claude/mcp-servers/quality/server.py`. Call tools from Claude Code session.

### Phase 2: Tool Trust Engine + GitHub

**Files:**
```
.claude/mcp-servers/quality/trust_engine.py
.claude/mcp-servers/quality/state.py
.claude/mcp-servers/quality/tools/github.py
```

**Deliverables:** SQLite-backed finding history, automated BLOCK/INVESTIGATE/TRACK decisions, dismissal workflow with audit trail, GitHub Issue creation/closing, GitHub Labels.

**Verification:** Run lint on file with issues, verify Issue created with correct labels. Fix issue, re-lint, verify Issue auto-closed.

### Phase 3: Agent SDK Integration

**Files:**
```
scripts/quality_agent.py
scripts/quality_monitor.py
.github/workflows/quality-monitor.yml
```

**Deliverables:** On-demand Quality Agent with subagents (security-scanner, style-checker, coverage-analyzer). Continuous Monitor with regression-detector and trend-analyzer. GitHub Actions workflow (every 4 hours + PR/push triggers).

**Verification:** `python scripts/quality_agent.py --analyze "UnaMentis/Services/"`. `python scripts/quality_monitor.py --compare-baseline`.

### Phase 4: Full Integration + Dashboard

**Files:**
```
.claude/mcp-servers/quality/tools/testing.py
.claude/mcp-servers/quality/tools/coverage.py
```

**Deliverables:** Test runner integration, coverage delta tracking, `validate()` tool (replaces /validate skill), GitHub Projects dashboard, XcodeBuildMCP integration for iOS builds, Rigour MCP server integration with `interactive-quality-gate` Recipe.

**Verification:** End-to-end workflow: write code -> format_and_stage -> check_all_gates -> all pass -> commit -> CI passes -> dashboard green.

---

## 14. Success Criteria

| Metric | Baseline | Target |
|--------|----------|--------|
| Pre-commit hook failure rate | ~30% | ~5% |
| Time from code to quality feedback | 30s (at commit) | Immediate (post-write) |
| Auto-fixed issues (no human action) | 0% | ~60% |
| CI failure rate | ~10% | ~3% |
| Autonomous session length | Varies | Until all gates pass |

---

## 15. Confirmed Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Base runtime | Goose (custom build) | Rust, MCP-native, Unix philosophy, enterprise-backed |
| Quality logic | Rigour as MCP server | Deterministic FSM, Fix Packets, AST Gates |
| Integration model | Hybrid (Goose + Rigour via MCP) | Best of both: agency + control |
| Auto-fix behavior | Fix and stage automatically | Zero friction for deterministic issues |
| State storage | GitHub Issues + Projects + Actions Artifacts | Collaborative, first-class GitHub citizen |
| Primary interface | Quality MCP Server | Reusable, testable, discoverable, multi-agent |
| Hook integration | Hybrid hooks + subagents | Lightweight checks via hooks, complex analysis via subagents |
| CI/CD | GitHub Actions, every 4 hours + PR/push | Continuous monitoring with regression detection |
| Security model | Defense in depth, 3-level sandboxing | Assume LLM compromise, restrict blast radius |
| Headless CI bot | Fork Rigour CLI (exception case) | Tight loop, no UI overhead, Docker sandboxing |
