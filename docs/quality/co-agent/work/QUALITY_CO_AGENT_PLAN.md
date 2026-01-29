# Quality Co-Agent: Collaborative Quality Automation for UnaMentis

## Executive Summary

This plan proposes adapting patterns from moltbot (a self-hosted AI assistant platform) to create a **Quality Co-Agent** for UnaMentis: not just a gatekeeper, but an active participant in the development workflow that collaborates with the primary development agent to maintain quality standards continuously as work progresses.

### The Key Insight

Traditional quality automation is **reactive gatekeeping**: write code, then check quality. The novel approach is **collaborative quality**: a quality agent that works alongside the development agent, running checks continuously, fixing issues automatically where possible, and enabling extended autonomous work sessions where the development agent can keep building until 100% of tests pass and all quality standards are met.

This transforms quality from a "stop and check" friction point into a "continuous collaborator" that enables, rather than inhibits, full automation.

---

## Part 1: Project Context

### What UnaMentis Is

UnaMentis is an AI-powered voice tutoring platform built with 100% AI assistance. Key characteristics:

- **iOS Primary**: Swift 6.0/SwiftUI with sub-500ms voice latency targets
- **Multi-platform**: iOS app, Web client, Android (in development)
- **Complex server stack**: Rust service manager (USM Core), Python management API, Next.js consoles
- **9 STT providers, 8 TTS providers, 5 LLM providers**: All swappable via protocol-based design
- **126+ unit tests, 16+ integration tests**: 80% coverage enforcement

### Current Quality Infrastructure (5-Phase Initiative)

| Phase | Status | Components |
|-------|--------|------------|
| **1. Foundation** | Complete | Pre-commit hooks, Renovate, 80% coverage gates |
| **2. Enhanced Gates** | Complete | Nightly E2E, latency regression detection, security scanning |
| **3. Feature Flags** | Complete | Unleash (self-hosted), iOS/Web SDKs, lifecycle audits |
| **4. Observability** | Complete | DORA metrics (DevLake), quality dashboards |
| **5. Advanced** | Complete | CodeRabbit AI review, mutation testing, property testing, chaos engineering |

### Tool Trust Doctrine

The project's core quality principle: **All findings from established tools are presumed legitimate until proven otherwise through rigorous analysis.** This means:

1. Assume the tool is right (not "might be right")
2. Fix the code, not the config
3. Prove false positives with full data flow analysis
4. Adapt patterns tools understand rather than suppress findings

---

## Part 2: Moltbot Analysis

### What Moltbot Is

Moltbot is a self-hosted personal AI assistant with a **Gateway architecture**: a central control plane that orchestrates messaging, tools, and automation across multiple channels (WhatsApp, Telegram, Slack, Discord, Signal, iMessage).

### Key Patterns Worth Adopting

| Pattern | Moltbot Implementation | Quality Gateway Application |
|---------|----------------------|---------------------------|
| **Central Gateway** | WebSocket hub at port 18789 coordinating all channels | Quality hub coordinating all quality tools and feedback |
| **Multi-Agent Routing** | Different channels route to different agent contexts | Different quality concerns route to specialized analyzers |
| **Session Isolation** | Per-channel/user session contexts | Per-development-session quality context |
| **Skills Platform** | Bundled, managed, workspace skills with discovery | Quality skills (lint, test, coverage, security) as discoverable plugins |
| **Node Execution** | Device-local executors for platform-specific actions | MCP integration for iOS-specific quality (XcodeBuildMCP, simulator) |
| **DM Pairing/Trust** | Unknown senders need approval before interaction | Untrusted code patterns need human approval before suppression |
| **Sandbox Separation** | Main sessions trusted, non-main sandboxed | Core code paths trusted, generated/external code sandboxed |

### Patterns We Should NOT Adopt

1. **Multi-user messaging complexity**: We're single-developer focused
2. **External service integrations**: No WhatsApp/Telegram for quality feedback
3. **Pairing codes**: Not relevant for local development
4. **Full TypeScript rewrite**: Leverage existing Python/Swift infrastructure

---

## Part 3: The Novel Proposal - Quality Co-Agent

### Vision

Transform quality from **reactive gatekeeping** to **collaborative automation**. The Quality Co-Agent is not a separate service providing notifications, but an **integrated participant** in the multi-agent development workflow that:

1. **Collaborates** with the development agent in real-time
2. **Fixes** issues automatically where possible (formatting, simple lint fixes)
3. **Enables** extended autonomous work sessions until standards are met
4. **Routes** complex issues to appropriate analyzers
5. **Enforces** the Tool Trust Doctrine as part of the workflow, not after it

### The Multi-Agent Collaboration Model

```
┌─────────────────────────────────────────────────────────────────────┐
│                   Autonomous Development Loop                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────────────┐          ┌──────────────────┐                │
│   │  Development     │◄────────►│  Quality         │                │
│   │  Agent           │  collab  │  Co-Agent        │                │
│   │  (Claude Code)   │          │  (hooks/subagent)│                │
│   └────────┬─────────┘          └────────┬─────────┘                │
│            │                             │                           │
│            │ writes code                 │ validates continuously    │
│            │ runs builds                 │ fixes auto-fixable issues │
│            │ runs tests                  │ flags issues needing fix  │
│            │                             │ tracks tool findings      │
│            │                             │                           │
│            ▼                             ▼                           │
│   ┌─────────────────────────────────────────────────────────┐       │
│   │              Shared Quality State                        │       │
│   │  - Current findings (with severity)                      │       │
│   │  - Auto-fix queue                                        │       │
│   │  - Tool trust decisions                                  │       │
│   │  - Coverage delta tracking                               │       │
│   │  - Test pass/fail status                                 │       │
│   └─────────────────────────────────────────────────────────┘       │
│                              │                                       │
│                              ▼                                       │
│   ┌─────────────────────────────────────────────────────────┐       │
│   │              Deterministic Quality Gates                 │       │
│   │  - All tests pass (100%)                                 │       │
│   │  - Coverage >= 80%                                       │       │
│   │  - Zero high/critical findings                           │       │
│   │  - Zero lint violations                                  │       │
│   │  - Build succeeds                                        │       │
│   └─────────────────────────────────────────────────────────┘       │
│                              │                                       │
│                              ▼                                       │
│              Work continues until ALL gates pass                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Difference from Traditional CI/CD

| Aspect | Traditional (Gatekeeping) | Collaborative (Co-Agent) |
|--------|--------------------------|-------------------------|
| **When** | After commit/push | Continuously during work |
| **Role** | Blocks bad code | Helps fix code |
| **Automation** | Reports findings | Fixes what it can |
| **Workflow** | Stop → check → fix → retry | Keep building until clean |
| **Agent integration** | None | Active collaborator |
| **Goal** | Prevent bad merges | Enable autonomous sessions |

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Quality Co-Agent System                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                   Claude Code Hooks Integration                 │ │
│  │  PreToolCall(Write/Edit) → quality-coagent.py pre-write        │ │
│  │  PostToolCall(Write/Edit) → quality-coagent.py post-write      │ │
│  │  PreBash(git commit) → quality-coagent.py pre-commit           │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                              │                                       │
│                              ▼                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                   Quality Co-Agent Core                         │ │
│  │                   (scripts/quality-coagent.py)                  │ │
│  ├────────────────────────────────────────────────────────────────┤ │
│  │                                                                  │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │ │
│  │  │ Auto-Fixer   │  │ Tool Runner  │  │ Tool Trust Engine    │  │ │
│  │  │              │  │              │  │                      │  │ │
│  │  │ • ruff format│  │ • SwiftLint  │  │ • Finding history    │  │ │
│  │  │ • swiftformat│  │ • Ruff lint  │  │ • Trust decisions    │  │ │
│  │  │ • rustfmt    │  │ • Clippy     │  │ • Dismissal audit    │  │ │
│  │  │ • prettier   │  │ • Bandit     │  │ • Pattern learning   │  │ │
│  │  │              │  │ • ESLint     │  │                      │  │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │ │
│  │         │                 │                      │              │ │
│  │         ▼                 ▼                      ▼              │ │
│  │  ┌─────────────────────────────────────────────────────────┐   │ │
│  │  │              Shared Quality State                        │   │ │
│  │  │         (.claude/quality-state.json or .sqlite)          │   │ │
│  │  │                                                          │   │ │
│  │  │  • current_findings[]  • auto_fix_applied[]              │   │ │
│  │  │  • coverage_delta      • test_status                     │   │ │
│  │  │  • trust_decisions{}   • finding_history[]               │   │ │
│  │  └─────────────────────────────────────────────────────────┘   │ │
│  │                              │                                  │ │
│  └──────────────────────────────┼──────────────────────────────────┘ │
│                                 │                                    │
│         ┌───────────────────────┼───────────────────────┐           │
│         ▼                       ▼                       ▼           │
│  ┌─────────────┐        ┌─────────────┐        ┌─────────────┐     │
│  │ MCP Servers │        │ Build Tools │        │ Test Runner │     │
│  │ (XcodeBuild │        │ (xcodebuild │        │ (test-ci.sh │     │
│  │ ios-sim)    │        │ cargo)      │        │ pytest)     │     │
│  └─────────────┘        └─────────────┘        └─────────────┘     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Core Components

#### 1. Claude Code Hooks Integration

The Co-Agent integrates via Claude Code's hook system, running automatically as part of the development workflow:

```json
// .claude/settings.json hooks configuration
{
  "hooks": {
    "PreToolCall": [{
      "matcher": "Write|Edit",
      "command": "python scripts/quality-coagent.py pre-write \"$TOOL_INPUT\""
    }],
    "PostToolCall": [{
      "matcher": "Write|Edit",
      "command": "python scripts/quality-coagent.py post-write \"$TOOL_INPUT\""
    }],
    "PreBash": [{
      "matcher": "git commit",
      "command": "python scripts/quality-coagent.py pre-commit"
    }]
  }
}
```

#### 2. Auto-Fixer Module

Automatically fixes issues that have deterministic solutions:

```python
class AutoFixer:
    """Automatic fixes for deterministic issues."""

    async def fix_python(self, files: List[Path]) -> FixResult:
        """Run ruff format + ruff --fix."""
        subprocess.run(["ruff", "format"] + files)
        subprocess.run(["ruff", "--fix"] + files)
        return FixResult(fixed=True, changes=get_diff())

    async def fix_swift(self, files: List[Path]) -> FixResult:
        """Run swiftformat with project rules."""
        subprocess.run(["swiftformat", "--config", ".swiftformat"] + files)
        return FixResult(fixed=True, changes=get_diff())

    async def fix_rust(self, files: List[Path]) -> FixResult:
        """Run rustfmt."""
        subprocess.run(["cargo", "fmt"])
        return FixResult(fixed=True, changes=get_diff())
```

#### 3. Tool Runner Module

Runs quality tools and collects findings:

```python
class ToolRunner:
    """Run quality tools and collect findings."""

    TOOL_CONFIGS = {
        "swift": [
            ("swiftlint", ["swiftlint", "lint", "--reporter", "json"]),
        ],
        "python": [
            ("ruff", ["ruff", "check", "--output-format", "json"]),
            ("bandit", ["bandit", "-r", "-f", "json"]),
        ],
        "rust": [
            ("clippy", ["cargo", "clippy", "--message-format", "json"]),
        ],
    }

    async def run_for_files(self, files: List[Path]) -> List[Finding]:
        """Run appropriate tools for the given files."""
        findings = []
        by_language = self._group_by_language(files)
        for lang, lang_files in by_language.items():
            for tool_name, cmd in self.TOOL_CONFIGS.get(lang, []):
                result = await self._run_tool(cmd, lang_files)
                findings.extend(self._parse_output(tool_name, result))
        return findings
```

#### 4. Tool Trust Engine

The heart of the system: an automated enforcement of the Tool Trust Doctrine.

```python
class ToolTrustEngine:
    """Automated Tool Trust Doctrine enforcement."""

    def __init__(self):
        self.finding_history = FindingHistory()  # SQLite-backed
        self.trust_levels = {
            "CodeQL": TrustLevel.HIGH,
            "SwiftLint": TrustLevel.HIGH,
            "Ruff": TrustLevel.HIGH,
            "Clippy": TrustLevel.HIGH,
            # ...
        }

    async def process_finding(self, finding: Finding) -> TrustDecision:
        """
        Apply Tool Trust Doctrine to a finding.

        Returns:
        - ENFORCE: Block commit, require fix
        - INVESTIGATE: Flag for human review with context
        - TRACK: Known pattern, monitor for changes
        """
        # Step 1: Check if this exact pattern was previously analyzed
        prior = await self.finding_history.find_similar(finding)
        if prior and prior.disposition == "proven_false_positive":
            # Still track, but don't block (rare case)
            return TrustDecision.TRACK

        # Step 2: Check tool trust level
        trust = self.trust_levels.get(finding.tool, TrustLevel.MEDIUM)

        # Step 3: Classify by severity
        if finding.severity in ("critical", "high") and trust >= TrustLevel.HIGH:
            return TrustDecision.ENFORCE

        # Step 4: Require investigation for medium findings
        if finding.severity == "medium":
            return TrustDecision.INVESTIGATE

        # Step 5: Track low severity for patterns
        return TrustDecision.TRACK

    async def record_dismissal(
        self,
        finding: Finding,
        reason: str,
        analysis: str,
        data_flow_trace: str
    ):
        """
        Record a human-approved dismissal with full justification.
        This creates an audit trail as required by TTD.
        """
        ...
```

#### 5. Output Channels

**WebSocket (real-time)**:
```json
{
  "type": "quality_finding",
  "severity": "high",
  "tool": "CodeQL",
  "file": "server/management/server.py",
  "line": 265,
  "message": "Potential path injection vulnerability",
  "trust_decision": "ENFORCE",
  "suggested_fix": "Use resolved path with startswith check"
}
```

**VS Code Extension Integration**:
- Inline diagnostics from Quality Gateway
- "Trust Decision" code actions (investigate, track, document dismissal)
- Quality session status in status bar

**Terminal Notifications**:
- macOS `osascript` notifications for blocking findings
- Summary at end of Quality Gateway session

### Novel Features

#### 1. Continuous Quality Loop (Not Gatekeeping)

The key innovation: quality checks run continuously as part of work, not as a gate after work:

```
Development Agent writes SessionManager.swift
    │
    ├── [PostToolCall Hook Fires]
    │   │
    │   ├── Auto-Fixer runs swiftformat → fixes formatting
    │   ├── Tool Runner runs SwiftLint → 2 warnings found
    │   ├── Co-Agent stages formatting fix
    │   └── Co-Agent reports: "2 SwiftLint warnings (see state file)"
    │
Development Agent reads warnings, fixes them
    │
    ├── [PostToolCall Hook Fires]
    │   │
    │   ├── SwiftLint → 0 warnings
    │   └── Co-Agent reports: "Clean"
    │
Development Agent continues work...
```

This enables the development agent to keep working until quality gates pass, rather than discovering issues at commit time.

#### 2. Auto-Fix Before Report

Unlike traditional linters that only report, the Co-Agent fixes first:

```python
async def handle_post_write(self, file_path: Path):
    """Called after every Write/Edit tool call."""

    # Step 1: Auto-fix what can be fixed
    fix_result = await self.auto_fixer.fix_file(file_path)
    if fix_result.changes:
        await self.stage_changes(fix_result.changes)
        self.log(f"Auto-fixed: {fix_result.summary}")

    # Step 2: Run tools on the fixed code
    findings = await self.tool_runner.run_for_file(file_path)

    # Step 3: Apply Tool Trust Engine
    decisions = await self.trust_engine.process_findings(findings)

    # Step 4: Update shared state (development agent reads this)
    await self.update_state({
        "last_file": str(file_path),
        "findings": [f.to_dict() for f in findings],
        "decisions": [d.to_dict() for d in decisions],
        "status": "clean" if not findings else "issues_found"
    })
```

#### 3. Shared Quality State

The Co-Agent maintains state that the development agent can read:

```json
// .claude/quality-state.json
{
  "last_updated": "2026-01-28T12:34:56Z",
  "status": "issues_found",
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
      "file": "UnaMentis/Services/TTS/KyutaiPocketTTSService.swift",
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

The development agent can read this to decide whether to continue working or address findings.

#### 4. Tool Trust Automation

The Tool Trust Doctrine is enforced automatically:

```python
async def process_findings(self, findings: List[Finding]) -> List[TrustDecision]:
    """Apply Tool Trust Doctrine to all findings."""
    decisions = []
    for finding in findings:
        # Check history for similar findings
        prior = await self.history.find_similar(finding)

        if prior and prior.disposition == "documented_false_positive":
            # Previously analyzed and documented
            decision = TrustDecision.TRACK
        elif finding.tool in HIGH_TRUST_TOOLS:
            # HIGH trust tool → assume legitimate
            if finding.severity in ("critical", "high"):
                decision = TrustDecision.BLOCK
            else:
                decision = TrustDecision.INVESTIGATE
        else:
            decision = TrustDecision.TRACK

        decisions.append(decision)
        await self.history.record(finding, decision)

    return decisions
```

#### 5. MCP Integration for iOS

When Swift files change, the Co-Agent can trigger builds via MCP:

```python
async def handle_swift_change(self, file_path: Path):
    """Handle Swift file changes with MCP integration."""

    # Quick lint first
    lint_findings = await self.tool_runner.run_swiftlint([file_path])

    # Trigger incremental build via MCP (if available)
    if self.mcp_available:
        build_result = await self.mcp.call("XcodeBuildMCP", "build_sim", {
            "scheme": "UnaMentis",
            "configuration": "Debug"
        })
        if not build_result.success:
            self.update_state({"build_success": False, "build_errors": build_result.errors})
```

---

## Part 4: Implementation Approach

### Phase 1: Core Co-Agent (First Sprint)

1. Create `scripts/quality-coagent.py` with core logic
2. Implement Auto-Fixer module (ruff format, swiftformat, rustfmt)
3. Implement Tool Runner module (SwiftLint, Ruff, Clippy, Bandit)
4. Create shared state file (`.claude/quality-state.json`)
5. Document hook configuration for Claude Code

**Deliverables:**
- Working `quality-coagent.py` script
- Hook configuration in `.claude/settings.json`
- Auto-fixing for Python and Swift formatting

### Phase 2: Tool Trust Engine

1. SQLite-backed finding history (`.claude/quality-history.sqlite`)
2. Trust level configuration per tool
3. Automated decision logic (BLOCK/INVESTIGATE/TRACK)
4. Dismissal workflow with audit trail
5. Pattern matching for similar findings

**Deliverables:**
- Tool Trust Engine class
- Finding history database
- Audit log for dismissals

### Phase 3: Full Integration

1. MCP server integration for iOS builds (XcodeBuildMCP)
2. Coverage delta tracking after test runs
3. Test selection optimization (run affected tests only)
4. Integration with existing pre-commit hooks (enhance, not replace)

**Deliverables:**
- MCP integration module
- Coverage tracking
- Enhanced pre-commit hooks

### Security Considerations

1. **Local-only execution**: All tools run locally, no network calls
2. **No credential handling**: Uses existing tool auth (git config, keychain)
3. **Audit trail**: All dismissals logged with justification
4. **Subprocess isolation**: External tools run in subprocess with timeout
5. **No code transmission**: Findings and state stay local

---

## Part 5: Expected Outcomes

### Immediate Benefits

1. **Extended autonomous sessions**: Development agent can work until all gates pass
2. **Zero-friction formatting**: Auto-fixed before you even notice
3. **Tool Trust automation**: Consistent, documented application of the doctrine
4. **Reduced commit failures**: Issues fixed during work, not at commit time

### Long-term Benefits

1. **Learning system**: Patterns of findings inform future decisions
2. **Quality culture**: Quality is a collaborator, not a gatekeeper
3. **Audit trail**: Every dismissal documented for compliance/review
4. **Reduced CI load**: Issues caught locally, fewer CI failures

### Metrics to Track

| Metric | Baseline | Target |
|--------|----------|--------|
| Pre-commit hook failure rate | ~30% (estimated) | ~5% |
| Time from code to feedback | 30s (commit hook) | Immediate (post-write hook) |
| Auto-fixed issues (no human action) | 0% | ~60% (formatting, simple lint) |
| CI failure rate | ~10% | ~3% |
| Autonomous session length | Varies | Until all gates pass |

---

## Part 6: Alternatives Considered

### Alternative 1: Extend Pre-Commit Hooks Only

**Pros**: Simple, existing infrastructure
**Cons**: Still reactive (at commit time), no collaboration with development agent, no learning

### Alternative 2: Separate Quality Service (Original Proposal)

**Pros**: Clean separation, WebSocket for real-time updates
**Cons**: Not integrated into agent workflow, adds complexity, still "notification" model

### Alternative 3: Full Moltbot Integration

**Pros**: Feature-rich platform, multi-channel
**Cons**: Overkill, TypeScript rewrite, security concerns, not focused on quality

### Why Quality Co-Agent is Better

- **Agent-integrated**: Works with Claude Code hooks, part of the development loop
- **Action-oriented**: Fixes issues, not just reports them
- **Enables automation**: Development agent can work until gates pass
- **Leverages existing tools**: SwiftLint, Ruff, Clippy, MCP servers
- **Python-based**: Matches server stack, easy to extend
- **Incremental**: Can be adopted module by module

---

---

## Part 7: Context on Pre-Commit Failures (From Your Selection)

The git error output you shared shows the current quality infrastructure catching several issues. Here's what each means:

### Ruff Formatting Issues (Auto-Fixable)

```
Would reformat: demo/ios_demo_video_generator.py
Would reformat: demo/tests/test_generator.py
```

**What it is**: Ruff found Python code formatting inconsistencies (whitespace, line lengths, etc.)
**Severity**: Low (cosmetic)
**Auto-fixable**: Yes, `ruff format .` fixes automatically

**Co-Agent behavior**: The Quality Co-Agent would automatically run `ruff format` and stage the changes, removing this as a blocker entirely.

### Bandit B310 Security Warnings (Needs Analysis)

```
Issue: [B310:blacklist] Audit url open for permitted schemes.
Severity: Medium   Confidence: High
Location: ./demo/ios_demo_video_generator.py:265
```

**What it is**: Bandit is a Python security scanner. B310 is a specific rule that flags `urllib.request.urlopen()` calls because they can open arbitrary URLs, potentially including:
- `file://` URLs (reading local files)
- Custom protocol handlers
- URLs from user input (leading to SSRF attacks)

**Why it's flagged**: The tool doesn't know if the URL is controlled/trusted or comes from untrusted input.

**The 7 locations in the demo video generator**:
1. Line 265: TTS server request (localhost, user-configured)
2. Line 356: TTS server health check (localhost)
3. Line 378: Shotstack API render status (fixed domain api.shotstack.io)
4. Line 463: Shotstack API submit (fixed domain)
5. Line 486: Shotstack API upload info (fixed domain)
6. Line 494: Signed URL upload (URL from Shotstack API response)
7. Line 777: Download final video (URL from Shotstack cdn.shotstack.io)

**Tool Trust Doctrine analysis**:
- These are NOT arbitrary user input URLs
- They are either:
  - Localhost URLs to a user-configured TTS server
  - Fixed API domains (api.shotstack.io, cdn.shotstack.io)
  - Signed URLs returned by a trusted API
- However, per TTD: "Even false positives often indicate code that could be written better"

**Two valid approaches**:
1. **Document with inline comments**: Add `# nosec B310: <rationale>` with analysis
2. **Refactor for clarity**: Use `requests` library with explicit URL validation

**Co-Agent behavior**: The Quality Co-Agent would:
1. Detect these are B310 findings with HIGH trust (Bandit is a covered tool)
2. Apply Tool Trust Doctrine: assume legitimate until proven otherwise
3. Since auto-fix isn't possible, flag for human decision
4. Track the finding and decision in the Tool Trust history
5. Once decision is made (document or refactor), apply it consistently to all 7 locations

### iOS Coverage Check (Passed but Unusual)

```
[INFO] Coverage: 0.0%
[WARN] Could not determine valid coverage (got 0.0%). Skipping threshold check.
```

**What it is**: The coverage extraction found 0% which is likely a parsing issue, so it skipped enforcement.
**Co-Agent behavior**: Would investigate why coverage extraction failed and fix the parsing.

---

## Part 8: Implementation Approach (Revised)

### Approach A: Hook-Based Co-Agent

Implement the Quality Co-Agent as Claude Code hooks that run automatically:

```json
// .claude/settings.json
{
  "hooks": {
    "PreToolCall": [
      {
        "matcher": "Write|Edit",
        "command": "python scripts/quality-coagent.py pre-write $FILE"
      }
    ],
    "PostToolCall": [
      {
        "matcher": "Write|Edit",
        "command": "python scripts/quality-coagent.py post-write $FILE"
      }
    ],
    "PreCommit": [
      {
        "command": "python scripts/quality-coagent.py pre-commit"
      }
    ]
  }
}
```

**Pros**: Integrated into Claude Code workflow, runs automatically
**Cons**: Limited to Claude Code, hook system capabilities

### Approach B: Subagent Model

The Quality Co-Agent runs as a Task subagent spawned by the primary development agent:

```
Development Agent (Claude Code)
├── Writes code
├── Spawns Quality Co-Agent (Task tool)
│   ├── Runs quality checks
│   ├── Returns findings + auto-fixes
│   └── Updates shared state file
└── Continues work incorporating feedback
```

**Pros**: Full agent capabilities, parallel execution
**Cons**: More complex orchestration

### Approach C: Hybrid (Recommended)

Combine hooks for lightweight checks with subagent for complex analysis:

1. **Hooks** handle:
   - Auto-formatting (ruff format, swiftformat)
   - Simple lint fixes
   - Build status tracking
   - Test run triggering

2. **Subagent** handles:
   - Tool Trust analysis
   - Coverage delta calculations
   - Complex finding investigation
   - Multi-file refactoring

### Phase 1: Foundation (This Sprint)

1. Create `scripts/quality-coagent.py` with core logic
2. Implement auto-fix for Ruff formatting
3. Implement auto-fix for simple SwiftLint issues
4. Track findings in `.claude/quality-state.json`
5. Integrate with existing pre-commit hooks

### Phase 2: Tool Trust Engine

1. SQLite-backed finding history
2. Automated Tool Trust Doctrine decisions
3. Dismissal workflow with audit trail
4. Pattern learning (similar findings get similar treatment)

### Phase 3: Full Integration

1. MCP server integration for iOS builds
2. Coverage delta tracking
3. Test selection optimization
4. Subagent spawning for complex analysis

---

## Part 9: Confirmed Decisions

Based on your input:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Implementation approach** | Hybrid | Hooks for lightweight checks + subagent for complex analysis |
| **Auto-fix aggressiveness** | Auto-fix and stage | Zero friction for formatting and simple lint |

---

## Part 10: GitHub-Native State Storage (Research Required)

### The Requirement

Quality state and finding history must be:
- **Collaborative**: Multiple agents and humans can see and contribute
- **First-class GitHub citizen**: Use existing GitHub infrastructure
- **Centralized**: Not local files, not our own log server
- **Best practice**: Leverage existing structures, don't reinvent the wheel

### Option Analysis

#### Option A: GitHub Issues as Quality Findings

Use GitHub Issues with labels to track quality findings:

```yaml
# Each finding becomes an issue
Title: "[Quality] SwiftLint: force_unwrapping in SessionManager.swift:142"
Labels: ["quality", "swiftlint", "severity:warning", "trust:investigate"]
Body: |
  **Tool:** SwiftLint
  **Rule:** force_unwrapping
  **File:** UnaMentis/Services/TTS/KyutaiPocketTTSService.swift:142
  **Message:** Force unwrapping should be avoided
  **Trust Decision:** INVESTIGATE
  **Auto-fixable:** No
```

**Pros:**
- Native GitHub collaboration (comments, assignments, linked PRs)
- Searchable, filterable by label
- History preserved in issue timeline
- Integrates with GitHub Projects for Kanban views

**Cons:**
- Could become noisy if many findings
- No structured query (beyond labels)
- Need to manage issue lifecycle (close when fixed)

#### Option B: GitHub Projects for Quality Dashboard

Use GitHub Projects (v2) with custom fields:

```yaml
Project: "Quality Dashboard"
Fields:
  - Tool (select: SwiftLint, Ruff, Clippy, Bandit, CodeQL)
  - Severity (select: critical, high, medium, low)
  - Trust Decision (select: BLOCK, INVESTIGATE, TRACK)
  - File Path (text)
  - Status (select: Open, Investigating, Documented, Fixed)
```

**Pros:**
- Rich views (table, board, timeline)
- Custom fields for structured data
- GitHub-native, first-class citizen
- Can link to Issues and PRs

**Cons:**
- Projects v2 API is GraphQL-only (more complex)
- Still needs Issues for detailed discussion

#### Option C: GitHub Actions Artifacts + Workflow Dispatch

Store quality state as workflow artifacts:

```yaml
# .github/workflows/quality-state.yml
name: Quality State
on:
  workflow_dispatch:
    inputs:
      action:
        type: choice
        options: [record_finding, dismiss_finding, get_state]

jobs:
  manage-state:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: quality-state
          path: .quality/
      # ... process action ...
      - uses: actions/upload-artifact@v4
        with:
          name: quality-state
          path: .quality/
```

**Pros:**
- Fully automated
- State persists across runs (90 days retention)
- No issue noise

**Cons:**
- Artifacts are ephemeral (90 days max)
- Complex to query
- Not human-friendly to view

#### Option D: Hybrid (Recommended)

Combine GitHub Issues (for human-visible findings) with GitHub Actions (for automation state):

1. **GitHub Issues** for findings needing human attention (INVESTIGATE, BLOCK)
2. **GitHub Actions artifacts** for transient state (current findings, auto-fixed count)
3. **GitHub Projects** for dashboard view of open quality items

**Workflow:**
```
Co-Agent finds issue
    │
    ├── TRACK → Record in Actions artifact (no issue)
    │
    ├── INVESTIGATE → Create GitHub Issue with "quality" label
    │                 Add to "Quality Dashboard" project
    │
    └── BLOCK → Create GitHub Issue with "quality-blocking" label
                Add to project, assign to relevant person
```

### Proposed Implementation

**Phase 1:** Use GitHub Issues with labels
- Simple, immediately useful
- Labels: `quality`, `quality-blocking`, `tool:swiftlint`, `tool:bandit`, etc.
- Co-Agent creates issues for INVESTIGATE/BLOCK findings
- Co-Agent closes issues when findings are fixed

**Phase 2:** Add GitHub Projects dashboard
- Visual overview of quality state
- Custom fields for structured tracking
- Views by tool, severity, status

**Phase 3:** Evaluate persistence needs
- If ephemeral state is needed, add Actions artifacts
- If history queries are needed, consider GitHub Discussions or external store

---

## Part 11: Bandit B310 - Complete Explanation and Proposal

### What is Bandit?

**Bandit** is a Python security scanner (similar to what SwiftLint is for Swift or Clippy is for Rust). It scans Python code for common security issues and reports findings with severity and confidence levels.

### What is B310?

**B310** is a specific Bandit rule called "blacklist: urllib_urlopen". It flags any use of `urllib.request.urlopen()` because this function can be dangerous if:

1. The URL comes from **untrusted user input** (could lead to SSRF attacks)
2. The URL uses **file:// scheme** (could read local files)
3. The URL uses **custom protocol handlers** (unpredictable behavior)

### Why These 7 Locations Were Flagged

In `demo/ios_demo_video_generator.py`, there are 7 uses of `urllib.request.urlopen()`:

| Line | Purpose | URL Source | Actual Risk |
|------|---------|------------|-------------|
| 265 | Fetch TTS audio | Localhost TTS server (user-configured in settings) | Low: User controls their own TTS server |
| 356 | TTS health check | Same localhost TTS server | Low: Same reason |
| 378 | Check Shotstack render status | Fixed domain: api.shotstack.io | Low: Hardcoded trusted API |
| 463 | Submit render to Shotstack | Fixed domain: api.shotstack.io | Low: Hardcoded trusted API |
| 486 | Get upload info from Shotstack | Fixed domain: api.shotstack.io | Low: Hardcoded trusted API |
| 494 | Upload to signed URL | URL from Shotstack API response | Medium: URL from external API, but it's a signed URL from a trusted API |
| 777 | Download final video | URL from Shotstack cdn.shotstack.io | Low: URL from trusted API response |

### Tool Trust Doctrine Analysis

Per the Tool Trust Doctrine:
1. **Assume the tool is right**: Bandit is correct that these patterns could be dangerous in other contexts
2. **Investigate deeply**: All 7 URLs are either hardcoded trusted domains or URLs from trusted API responses
3. **Fix the code or document**: Two valid paths forward

### Proposed Solution: Document with Inline Analysis

The recommended approach is to **document each use with a `# nosec B310` comment** that explains why it's safe:

```python
# Line 265: TTS server request
# nosec B310: URL is localhost TTS server configured by user in settings,
# not arbitrary input. User controls their own development TTS server.
with urllib.request.urlopen(req, timeout=60) as resp:
    ...

# Line 378: Shotstack API
# nosec B310: URL is hardcoded Shotstack API domain (api.shotstack.io),
# not arbitrary input. This is a fixed, trusted third-party API.
with urllib.request.urlopen(req, timeout=10) as resp:
    ...

# Line 494: Signed URL upload
# nosec B310: URL is a signed upload URL returned by Shotstack API.
# The URL comes from a trusted API response, not user input.
urllib.request.urlopen(upload_req)
```

### Why Not Refactor to `requests` Library?

The alternative (using the `requests` library with explicit URL validation) would be "cleaner" but:
1. Adds a dependency to a simple demo script
2. The current code is actually safe for its purpose
3. Per TTD: "Fix the code" includes "document why it's safe"

### Implementation Plan

1. **Add `# nosec B310` comments** to all 7 locations with rationale
2. **Add to Tool Trust history** (once the Co-Agent is built) so future similar patterns are recognized
3. **Run Bandit again** to verify the findings are suppressed
4. **Pre-commit hook passes** after documentation is added

This will be executed as part of Phase 1 of the Quality Co-Agent implementation, demonstrating the Tool Trust workflow in action.

---

## Part 12: MCP-Based Architecture (Enhanced Approach)

### Why MCP is Better Than Hooks Alone

| Aspect | Hook-Based | MCP-Based |
|--------|-----------|-----------|
| **Reusability** | Claude Code specific | Any MCP-compatible agent |
| **API surface** | Implicit (file changes) | Explicit tools with schemas |
| **Testability** | Hard to test in isolation | MCP Inspector, unit tests |
| **On-demand** | Triggered by file writes | Called when needed |
| **Multi-agent** | Needs file-based coordination | Native tool sharing |
| **Discoverability** | Hidden in hook scripts | Tools listed with descriptions |

### Quality MCP Server Architecture

```
.claude/mcp-servers/quality/
├── server.py              # FastMCP server (Python)
├── tools/
│   ├── __init__.py
│   ├── formatting.py      # Auto-fix tools (ruff format, swiftformat)
│   ├── linting.py         # Lint tools (SwiftLint, Ruff, Clippy, Bandit)
│   ├── testing.py         # Test runner integration
│   ├── coverage.py        # Coverage delta tracking
│   ├── security.py        # Security scanning (CodeQL, Bandit)
│   └── github.py          # GitHub Issues integration
├── trust_engine.py        # Tool Trust Doctrine logic
├── state.py               # Shared state management
├── config.py              # Tool configurations
└── requirements.txt       # Dependencies (mcp, etc.)
```

### MCP Server Implementation (FastMCP)

```python
# .claude/mcp-servers/quality/server.py
from mcp.server.fastmcp import FastMCP
from tools import formatting, linting, testing, coverage, github
from trust_engine import ToolTrustEngine

mcp = FastMCP("quality")
trust = ToolTrustEngine()

# ==================== FORMATTING TOOLS ====================

@mcp.tool()
async def auto_format(file_path: str, language: str = "auto") -> dict:
    """Auto-format a file and return the diff.

    Args:
        file_path: Path to file to format
        language: Language (swift, python, rust, typescript, auto)

    Returns:
        dict with: formatted (bool), diff (str), staged (bool)
    """
    return await formatting.format_file(file_path, language)

@mcp.tool()
async def format_and_stage(file_path: str) -> dict:
    """Format a file and stage the changes.

    Args:
        file_path: Path to file to format and stage

    Returns:
        dict with: formatted (bool), staged (bool), message (str)
    """
    result = await formatting.format_file(file_path)
    if result["formatted"]:
        await formatting.stage_file(file_path)
        result["staged"] = True
    return result

# ==================== LINTING TOOLS ====================

@mcp.tool()
async def run_lint(file_path: str, fix: bool = False) -> dict:
    """Run linting on a file.

    Args:
        file_path: Path to file to lint
        fix: Whether to auto-fix issues (default: False)

    Returns:
        dict with: findings (list), fixed_count (int), status (str)
    """
    findings = await linting.lint_file(file_path, fix=fix)
    decisions = await trust.process_findings(findings)
    return {
        "findings": [f.to_dict() for f in findings],
        "decisions": [d.to_dict() for d in decisions],
        "status": "clean" if not findings else "issues_found"
    }

@mcp.tool()
async def lint_all_changed() -> dict:
    """Lint all files with uncommitted changes.

    Returns:
        dict with: files_checked (int), total_findings (int), by_file (dict)
    """
    return await linting.lint_changed_files()

# ==================== TESTING TOOLS ====================

@mcp.tool()
async def run_tests(test_type: str = "quick", affected_only: bool = False) -> dict:
    """Run test suite.

    Args:
        test_type: Type of tests (quick, integration, all)
        affected_only: Only run tests affected by recent changes

    Returns:
        dict with: passed (bool), total (int), failed (int), output (str)
    """
    return await testing.run_tests(test_type, affected_only)

@mcp.tool()
async def check_coverage(threshold: int = 80) -> dict:
    """Check test coverage against threshold.

    Args:
        threshold: Minimum coverage percentage (0-100)

    Returns:
        dict with: current (float), threshold (int), passing (bool), delta (float)
    """
    return await coverage.check_coverage(threshold)

# ==================== QUALITY GATES ====================

@mcp.tool()
async def check_all_gates() -> dict:
    """Check all quality gates.

    Returns:
        dict with status of each gate and overall pass/fail
    """
    return {
        "lint_clean": await linting.is_clean(),
        "tests_pass": await testing.all_pass(),
        "coverage_met": await coverage.meets_threshold(80),
        "build_success": await testing.build_succeeds(),
        "all_pass": all([...])  # All gates must pass
    }

@mcp.tool()
async def validate() -> dict:
    """Run full validation (equivalent to /validate skill).

    Returns:
        dict with: passed (bool), summary (str), details (dict)
    """
    # Run lint, quick tests, check coverage
    lint_result = await linting.lint_all()
    test_result = await testing.run_tests("quick")
    coverage_result = await coverage.check_coverage(80)

    passed = all([
        not lint_result["findings"],
        test_result["passed"],
        coverage_result["passing"]
    ])

    return {
        "passed": passed,
        "summary": "PASS" if passed else "FAIL",
        "lint": lint_result,
        "tests": test_result,
        "coverage": coverage_result
    }

# ==================== GITHUB INTEGRATION ====================

@mcp.tool()
async def create_quality_issue(
    finding: dict,
    title: str = None,
    labels: list = None
) -> dict:
    """Create a GitHub Issue for a quality finding.

    Args:
        finding: The finding dict from lint/security tools
        title: Custom title (default: auto-generated)
        labels: Additional labels (quality labels added automatically)

    Returns:
        dict with: issue_number (int), url (str)
    """
    return await github.create_issue(finding, title, labels)

@mcp.tool()
async def close_resolved_issues() -> dict:
    """Close GitHub Issues for findings that are now resolved.

    Returns:
        dict with: closed (int), still_open (int)
    """
    return await github.close_resolved()

# ==================== TOOL TRUST ====================

@mcp.tool()
async def get_trust_decision(finding: dict) -> dict:
    """Get Tool Trust Doctrine decision for a finding.

    Args:
        finding: The finding dict from a quality tool

    Returns:
        dict with: decision (BLOCK|INVESTIGATE|TRACK), rationale (str)
    """
    return await trust.get_decision(finding)

@mcp.tool()
async def record_dismissal(
    finding: dict,
    reason: str,
    analysis: str
) -> dict:
    """Record a documented dismissal of a finding (per Tool Trust Doctrine).

    Args:
        finding: The finding being dismissed
        reason: Short reason for dismissal
        analysis: Full analysis proving false positive

    Returns:
        dict with: recorded (bool), audit_id (str)
    """
    return await trust.record_dismissal(finding, reason, analysis)

# ==================== SERVER ENTRY POINT ====================

def main():
    mcp.run(transport="stdio")

if __name__ == "__main__":
    main()
```

### MCP Server Registration

```json
// .mcp.json (project root - shared with team)
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

### Multi-Agent Collaboration via MCP

With the Quality MCP Server, any agent can:

```
Development Agent                    Quality Agent (or same agent)
      │                                      │
      │ writes code                          │
      │                                      │
      ├── calls mcp__quality__auto_format ───┤
      │                                      │ formats and stages
      │◄── returns {formatted: true} ────────┤
      │                                      │
      ├── calls mcp__quality__run_lint ──────┤
      │                                      │ runs SwiftLint/Ruff
      │◄── returns {findings: [...]} ────────┤
      │                                      │
      │ fixes issues                         │
      │                                      │
      ├── calls mcp__quality__check_all_gates┤
      │                                      │ validates all gates
      │◄── returns {all_pass: true} ─────────┤
      │                                      │
      │ continues to next task               │
```

### Hybrid Approach: MCP + Hooks

For the most robust system, combine MCP with lightweight hooks:

1. **MCP Server**: Provides the quality tools
2. **Hooks**: Automatically trigger MCP tools on file changes

```json
// .claude/settings.json
{
  "hooks": {
    "PostToolCall": [{
      "matcher": "Write|Edit",
      "command": "python -c \"import subprocess; subprocess.run(['claude', 'mcp', 'call', 'quality', 'format_and_stage', '--', '$FILE'])\""
    }]
  }
}
```

Or simpler: the development agent learns to call `mcp__quality__format_and_stage` after every write.

---

## Part 13: Agent SDK Multi-Agent Architecture

### What Claude Agent SDK Enables

The Agent SDK allows building **programmatic agents** that run on top of Claude Code, enabling:

| Capability | Description |
|------------|-------------|
| **Subagent definitions** | Specialized agents for security, performance, coverage, etc. |
| **Parallel execution** | Multiple agents analyze simultaneously |
| **Session resumption** | Follow-up questions on previous analysis |
| **MCP integration** | Direct access to MCP servers in agent options |
| **CI/CD integration** | Scheduled quality checks via GitHub Actions |
| **Tool restrictions** | Per-agent tool allowlists for safety |

### Three-Agent Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Multi-Agent Quality System                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    Shared Infrastructure                          │   │
│  │  ┌────────────────┐  ┌────────────────┐  ┌─────────────────────┐ │   │
│  │  │ Quality MCP    │  │ GitHub MCP     │  │ XcodeBuild MCP     │ │   │
│  │  │ Server         │  │ Server         │  │ Server             │ │   │
│  │  │ (mcp__quality) │  │ (mcp__github)  │  │ (mcp__XcodeBuild)  │ │   │
│  │  └────────────────┘  └────────────────┘  └─────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│         ┌──────────────────────────┼──────────────────────────┐         │
│         ▼                          ▼                          ▼         │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐   │
│  │ Development     │     │ Quality         │     │ Continuous      │   │
│  │ Agent           │     │ Agent           │     │ Monitor         │   │
│  │                 │     │                 │     │                 │   │
│  │ Tools:          │     │ Tools:          │     │ Tools:          │   │
│  │ • Read, Write   │     │ • Read, Grep    │     │ • Read, Grep    │   │
│  │ • Edit, Bash    │     │ • Glob, Task    │     │ • Task          │   │
│  │ • Glob, Grep    │     │ • mcp__quality  │     │ • mcp__quality  │   │
│  │ • mcp__quality  │     │ • mcp__github   │     │ • mcp__github   │   │
│  │                 │     │                 │     │                 │   │
│  │ Mode:           │     │ Mode:           │     │ Mode:           │   │
│  │ Interactive     │     │ On-demand       │     │ Scheduled       │   │
│  │ (Claude Code)   │     │ (SDK)           │     │ (CI/CD)         │   │
│  └────────┬────────┘     └────────┬────────┘     └────────┬────────┘   │
│           │                       │                       │             │
│           │ writes code           │ analyzes changes      │ reports     │
│           │                       │                       │ trends      │
│           │                       │                       │             │
│           └───────────────────────┼───────────────────────┘             │
│                                   ▼                                      │
│                    ┌─────────────────────────────┐                      │
│                    │ GitHub Issues & Projects    │                      │
│                    │ (Collaborative State)       │                      │
│                    └─────────────────────────────┘                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Agent Definitions

#### Development Agent (Interactive)

Used via Claude Code for feature development:

```python
# Not explicitly defined - this is the interactive Claude Code session
# Has full tool access, writes code, runs builds
```

#### Quality Agent (On-Demand)

Called by Development Agent or triggered by file changes:

```python
quality_agent_options = ClaudeAgentOptions(
    allowed_tools=["Read", "Grep", "Glob", "Task", "mcp__quality", "mcp__github"],
    permission_mode="bypassPermissions",  # Read-only, no prompts needed

    system_prompt="""You are a quality assurance specialist applying the Tool Trust Doctrine.
All findings from established tools are presumed legitimate until proven otherwise.
For each finding:
1. Check if auto-fixable → fix and stage
2. Check severity → BLOCK if critical/high, INVESTIGATE if medium, TRACK if low
3. Create GitHub Issue if BLOCK or INVESTIGATE
""",

    agents={
        "security-scanner": AgentDefinition(
            description="Security vulnerability scanner (CodeQL, Bandit patterns)",
            prompt="Identify security vulnerabilities using OWASP Top 10 patterns",
            tools=["Read", "Grep", "Glob"],
            model="opus"  # Use most capable model for security
        ),
        "style-checker": AgentDefinition(
            description="Code style and lint checker",
            prompt="Check code style using SwiftLint, Ruff, Clippy patterns",
            tools=["Read", "Grep", "Glob"]
        ),
        "coverage-analyzer": AgentDefinition(
            description="Test coverage gap analyzer",
            prompt="Identify untested code paths and suggest test scenarios",
            tools=["Read", "Grep", "Glob"]
        )
    },

    mcp_servers={
        "quality": {
            "command": "python",
            "args": [".claude/mcp-servers/quality/server.py"]
        },
        "github": {
            "command": "gh",
            "args": ["mcp-server"]  # GitHub's official MCP server
        }
    }
)
```

#### Continuous Monitor (Scheduled)

Runs on schedule via GitHub Actions:

```python
# quality_monitor.py - Run via CI/CD
continuous_monitor_options = ClaudeAgentOptions(
    allowed_tools=["Read", "Grep", "Glob", "Task", "mcp__quality", "mcp__github"],
    permission_mode="bypassPermissions",

    system_prompt="""You are a continuous quality monitor.
Your job is to:
1. Compare current quality metrics to baseline
2. Detect quality regressions
3. Generate trend reports
4. Create GitHub Issues for new findings
5. Close Issues for resolved findings
""",

    agents={
        "regression-detector": AgentDefinition(
            description="Quality regression detector",
            prompt="Compare current metrics to baseline, flag regressions",
            tools=["Read", "Grep", "Glob"]
        ),
        "trend-analyzer": AgentDefinition(
            description="Quality trend analyzer",
            prompt="Analyze quality trends over time, predict issues",
            tools=["Read", "Grep", "Glob"]
        )
    }
)
```

### GitHub Actions Integration

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

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install Claude Agent SDK
        run: pip install claude-agent-sdk

      - name: Install Claude Code
        run: |
          curl -fsSL https://claude.ai/install.sh | bash
          claude --version

      - name: Run Quality Monitor
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: python scripts/quality_monitor.py

      - name: Upload Quality Report
        uses: actions/upload-artifact@v4
        with:
          name: quality-report
          path: quality_report.json
          retention-days: 90
```

### Collaboration Flow

```
Developer starts work (Claude Code)
    │
    ├── Writes code
    │
    ├── [Development Agent] "Check quality after my changes"
    │   │
    │   ├── Spawns Quality Agent via Task tool
    │   │   │
    │   │   ├── Uses mcp__quality__format_and_stage
    │   │   │   └── Auto-fixes formatting, stages changes
    │   │   │
    │   │   ├── Uses mcp__quality__run_lint
    │   │   │   └── Returns findings with Tool Trust decisions
    │   │   │
    │   │   ├── Uses mcp__quality__check_all_gates
    │   │   │   └── Returns gate status
    │   │   │
    │   │   └── If INVESTIGATE findings:
    │   │       └── Uses mcp__github__create_issue
    │   │
    │   └── Returns: "2 issues auto-fixed, 1 finding needs investigation (Issue #123)"
    │
    ├── Developer fixes finding
    │
    ├── [Development Agent] "Verify fix"
    │   │
    │   └── Quality Agent confirms: "All gates pass"
    │
    └── Developer commits (pre-commit hooks pass because issues already fixed)

Meanwhile (every 4 hours):
    │
    [Continuous Monitor via CI/CD]
    │
    ├── Compares to baseline metrics
    ├── Detects any regressions
    ├── Updates GitHub Project dashboard
    └── Creates summary Issue if needed
```

### Session Resumption for Complex Analysis

```python
# First: Initial analysis
result = await quality_agent.query("Analyze the authentication module")
agent_id = extract_agent_id(result)
session_id = result.session_id

# Later: Follow-up questions (agent remembers context)
follow_up = await quality_agent.query(
    f"Resume agent {agent_id}: Which of these findings is highest priority?",
    options=ClaudeAgentOptions(resume=session_id, ...)
)
```

---

## Part 14: Final Implementation Plan

### Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                    Quality Automation Stack                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Layer 3: Agent SDK (Programmatic Multi-Agent)                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Quality Agent | Continuous Monitor | Specialized Subagents │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│  Layer 2: MCP Server (Tool Interface)                           │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ mcp__quality__format_and_stage | run_lint | check_all_gates│ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│  Layer 1: Quality Tools (Existing)                              │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ SwiftLint | Ruff | Clippy | Bandit | XcodeBuildMCP         │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│  Layer 0: Collaborative State (GitHub)                          │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ GitHub Issues | GitHub Projects | GitHub Actions Artifacts │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Confirmed Configuration

| Setting | Value |
|---------|-------|
| **Architecture** | 4-layer stack (Tools → MCP → Agent SDK → CI/CD) |
| **Primary interface** | Quality MCP Server exposing tools |
| **Multi-agent** | Agent SDK for Quality Agent + Continuous Monitor |
| **Auto-fix behavior** | Auto-fix and stage via MCP tool |
| **State storage** | GitHub Issues + Projects |
| **Scheduling** | GitHub Actions for continuous monitoring |
| **B310 resolution** | Document with `# nosec B310` comments |

### Phase 1: Quality MCP Server (First Sprint)

**Goal:** Create the foundational tool layer that all agents use.

**Deliverables:**
1. `.claude/mcp-servers/quality/` directory structure
2. `server.py` with FastMCP implementation
3. Core tools: `auto_format`, `format_and_stage`, `run_lint`, `check_all_gates`
4. `.mcp.json` configuration for project-wide sharing
5. Documentation in `.claude/mcp-servers/quality/README.md`

**Files to create:**
```
.claude/mcp-servers/quality/
├── server.py              # FastMCP server (main entry)
├── tools/
│   ├── __init__.py
│   ├── formatting.py      # auto_format, format_and_stage
│   └── linting.py         # run_lint, lint_all_changed
├── requirements.txt       # mcp, subprocess, etc.
└── README.md              # Documentation

.mcp.json                   # Server registration (project root)
```

**Immediate action:**
- Document B310 findings with `# nosec B310` comments

### Phase 2: Tool Trust Engine + GitHub Integration

**Goal:** Automate the Tool Trust Doctrine with collaborative state.

**Deliverables:**
1. `trust_engine.py` with decision logic (BLOCK/INVESTIGATE/TRACK)
2. `tools/github.py` with Issue creation/closing
3. MCP tools: `get_trust_decision`, `record_dismissal`, `create_quality_issue`
4. GitHub Labels: `quality`, `quality-blocking`, `tool:*`, `severity:*`

**Files to add:**
```
.claude/mcp-servers/quality/
├── trust_engine.py        # Tool Trust Doctrine logic
├── state.py               # Local SQLite for pattern matching
└── tools/
    └── github.py          # GitHub Issue/Project integration
```

### Phase 3: Agent SDK Integration

**Goal:** Enable programmatic multi-agent quality automation.

**Deliverables:**
1. `scripts/quality_agent.py` - On-demand Quality Agent (SDK)
2. `scripts/quality_monitor.py` - Continuous Monitor (SDK + CI/CD)
3. Subagent definitions (security-scanner, coverage-analyzer, style-checker)
4. Session resumption for complex analysis

**Files to create:**
```
scripts/
├── quality_agent.py       # On-demand Quality Agent
└── quality_monitor.py     # Continuous Monitor (for CI/CD)

.github/workflows/
└── quality-monitor.yml    # Scheduled quality checks
```

### Phase 4: Full Integration + Dashboard

**Goal:** Complete integration with existing infrastructure.

**Deliverables:**
1. Testing tools: `run_tests`, `check_coverage`
2. Gate tools: `validate` (can replace /validate skill)
3. GitHub Projects dashboard for quality overview
4. XcodeBuildMCP integration for iOS builds
5. Optional: Hook configuration for automatic triggering

### Critical Files Summary

| File | Layer | Purpose |
|------|-------|---------|
| `.claude/mcp-servers/quality/server.py` | MCP | FastMCP server |
| `.claude/mcp-servers/quality/tools/*.py` | MCP | Tool implementations |
| `.claude/mcp-servers/quality/trust_engine.py` | MCP | Tool Trust logic |
| `.mcp.json` | MCP | Server registration |
| `scripts/quality_agent.py` | SDK | On-demand quality agent |
| `scripts/quality_monitor.py` | SDK | Continuous monitor |
| `.github/workflows/quality-monitor.yml` | CI/CD | Scheduled runs |
| `demo/ios_demo_video_generator.py` | Immediate | B310 documentation |

### Verification Plan

**Phase 1 Verification:**
```bash
# Test MCP server in isolation
mcp-inspector python .claude/mcp-servers/quality/server.py

# Call tools from Claude Code
> mcp__quality__format_and_stage file_path="demo/ios_demo_video_generator.py"
> mcp__quality__run_lint file_path="UnaMentis/Core/Session/SessionManager.swift"
> mcp__quality__check_all_gates
```

**Phase 2 Verification:**
```bash
# Run lint on file with issues
> mcp__quality__run_lint file_path="<file with issues>"
# Verify GitHub Issue created with correct labels

# Fix issue
> Edit <file>

# Run lint again
> mcp__quality__run_lint file_path="<same file>"
# Verify GitHub Issue auto-closed
```

**Phase 3 Verification:**
```bash
# Run Quality Agent manually
python scripts/quality_agent.py --analyze "UnaMentis/Services/"

# Run Continuous Monitor
python scripts/quality_monitor.py --compare-baseline
```

**Phase 4 Verification:**
```
# Full workflow test:
1. Developer writes code via Claude Code
2. Developer calls mcp__quality__format_and_stage
3. Developer calls mcp__quality__check_all_gates
4. All gates pass
5. Developer commits (pre-commit hooks pass)
6. CI runs quality-monitor.yml
7. GitHub Project dashboard shows green status
```

### Success Criteria

1. **Auto-fix reduces friction**: Formatting issues fixed and staged automatically
2. **Tool Trust enforced**: Findings classified, issues created for INVESTIGATE/BLOCK
3. **Extended sessions work**: Agent can work until all gates pass
4. **Collaborative state**: Quality state visible in GitHub Issues/Projects
5. **Continuous monitoring**: Quality trends tracked over time
6. **Multi-agent works**: Quality Agent can be spawned by Development Agent
