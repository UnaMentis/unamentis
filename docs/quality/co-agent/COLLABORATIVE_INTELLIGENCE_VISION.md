# Collaborative Intelligence System: Architectural Vision

A system of collaborative agents that operates as institutional memory, quality enforcer, research advisor, and session manager for a team of development agents. Originally conceived as a "Quality Co-Agent," the scope expanded to encompass the full spectrum of what makes autonomous multi-agent development sessions successful over hours, not minutes.

---

## Core Principles

**P1: Mutual Confidence, Not Gatekeeping**
The quality system and dev agents should "have each other's back." Confidence in tool calls comes from genuine understanding of the VALUE of each action. The quality agent doesn't just check boxes; it understands why a check matters. The dev agent trusts that quality feedback is genuinely helpful. Neither side "owns" quality; it's shared.

**P2: Bidirectional Agency**
The quality system is not an admonishing schoolmarm. It pushes back constructively, questions architectural decisions, but ultimately enables the coding agent to do its best work. The dev agent should feel supported, not policed.

**P3: True Multi-Agentic Composition**
Not "multiple copies of the same thing." True specialization where:
- Task specialists handle specific domains (CodeRabbit for code review, specialized linters per language)
- External specialist agents are delegated to and their output consumed agentically (not just human-readable PR comments)
- If something is 3x better at TypeScript linting, it gets the TypeScript work

**P4: Specialist Delegation with Agentic Information Exchange**
External tools designed for human consumption (CodeRabbit PR reviews, etc.) should be consumed programmatically. The information exchange between all agents should be agentic and full of agency, not limited to human-readable formats.

**P5: Justified Complexity / Simplicity as a Vector**
Every architectural decision must justify its existence. "Simple" is not a state but an intention, a constant reflective pressure. When pushing hard on features, the answer will often be "yes, this earns its place." But not always. Architectural flexibility and pluggability where needed, but not where it doesn't earn its keep.

**P6: Extended Autonomous Sessions (The Ultimate Goal)**
A system of 1-to-many coding agents + the quality system works for hours (many hours) without:
- Derailing or losing focus
- Quality degradation
- Going into the weeds
- Being unchecked

End result is not just what was hoped for but potentially BETTER. That success is attributable specifically to the collaboration, not achievable by multiple Claude Code instances alone.

---

## The Core Metaphor: A Team, Not a Pipeline

A pipeline is: hooks fire, tools run, state files update, agents read state. That's plumbing. This system is a **team** where:

- Members have distinct expertise and genuinely different perspectives
- They communicate bidirectionally with rich context, not just pass structured findings
- They develop working confidence in each other through track record, not just permission scoping
- The quality of the collective output exceeds what any individual member could produce
- They can sustain focus and coherence over long working sessions

The architecture must support the team metaphor at every level.

---

## 1. Agent Topology: Three Tiers

```
┌─────────────────────────────────────────────────────────────┐
│                    SESSION ORCHESTRATOR                       │
│  Maintains session goals, tracks progress, detects drift,    │
│  manages checkpoints, brokers communication between tiers    │
└────────────┬────────────────────────────┬───────────────────┘
             │                            │
    ┌────────┴────────┐          ┌────────┴────────┐
    │  WORKER AGENTS  │          │  QUALITY AGENTS  │
    │  (1-N dev agents│◄────────►│  (co-agent system│
    │   doing impl)   │  collab  │   we're building)│
    └────────┬────────┘          └────────┬────────┘
             │                            │
             │         ┌──────────────────┤
             │         │                  │
    ┌────────┴─────────┴──┐     ┌────────┴────────┐
    │  SPECIALIST POOL     │     │ EXTERNAL SERVICES│
    │  (routed by domain)  │     │ (CodeRabbit, etc)│
    └─────────────────────┘     └─────────────────┘
```

**Tier 1: Session Orchestrator**
- Not an implementation agent. A coordination layer.
- Holds the session's goals, acceptance criteria, and progress state
- Detects drift ("the dev agent has been debugging the same test for 40 minutes without progress")
- Manages checkpoints so work can resume after failures
- Brokers communication: decides when to involve quality agents, when to route to specialists
- Think of this as the "project lead" who doesn't write code but keeps the team focused

**Tier 2: Worker Agents + Quality Agents (Peers)**
- Worker agents: 1-N Claude Code instances doing implementation work
- Quality agents: The co-agent system, operating as a peer, not a supervisor
- These are the team members who interact most frequently
- Communication is bidirectional and rich (not just "here are your lint errors")

**Tier 3: Specialist Pool + External Services**
- Domain specialists routed to by capability (best Rust linter, best security scanner, etc.)
- External services wrapped in MCP (CodeRabbit, etc.) consumed agentically
- These are "consultants" brought in for specific expertise

---

## 2. Communication Architecture: Structured Dialogue, Not File Drops

Writing to `quality-state.json` for another agent to read is a bulletin board. A team needs dialogue.

**Three communication channels:**

**Channel A: Structured Event Stream**
- All agents publish events to a lightweight event bus (could be as simple as a local message queue, or Kafka for production)
- Events are typed: `finding`, `fix_applied`, `gate_status`, `drift_alert`, `confidence_update`, `delegation_request`, `delegation_result`
- Any agent can subscribe to events it cares about
- This replaces static JSON files with a live, temporal stream
- Events carry context (why this matters, not just what happened)

**Channel B: Direct Dialogue (Rich Context Exchange)**
- For situations requiring back-and-forth reasoning, not just data passing
- Quality agent says: "I see you're adding a new service protocol. The existing pattern in KBOralSessionView uses dependency injection via init. Are you intentionally diverging, or should this follow the same pattern?"
- Dev agent responds with reasoning, quality agent updates its understanding
- This is where "having each other's back" manifests: the quality agent explains WHY it's asking, the dev agent explains WHY it chose a path
- Mechanically: structured messages with `context`, `question`, `rationale` fields, not chat

**Channel C: Session State (Orchestrator-managed)**
- Goals, progress checkpoints, current focus area, known blockers
- Managed by the Session Orchestrator
- All agents can read; only the orchestrator writes
- This is the "project board" that keeps everyone aligned

**Simplicity check (P5)**: Channel C is essential (session state). Channel A replaces static quality-state JSON with something temporal rather than static, a modest upgrade. Channel B is new and is the key architectural addition that enables the collaborative spirit. All three earn their place.

---

## 3. Mutual Confidence: Earned Trust, Not Assigned Permissions

Tool trust (trusting SwiftLint, Ruff, etc.) operates at the mechanical layer. Agent confidence operates at the collaboration layer, built from three things:

**a) Track Record (Observable Outcomes)**
- Each agent-to-agent interaction has an observable outcome: was the suggestion helpful? Did the fix work? Did the flagged issue turn out to be real?
- The system tracks these outcomes in a lightweight history
- Over a session, patterns emerge: "the security specialist has flagged 12 things, 11 were real issues" = high confidence
- This is not a numeric score displayed to agents. It's context that informs how the orchestrator routes work and how agents weight each other's input

**b) Explanation Quality (Show Your Work)**
- Findings come with rationale, not just verdicts
- "This force unwrap is dangerous because KBOralSessionView can receive nil from the STT pipeline during network transitions" is high-confidence feedback
- "Force unwrapping should be avoided" is low-confidence feedback (it's a generic lint rule with no project-specific reasoning)
- Agents that provide project-specific reasoning earn more weight in the collaboration

**c) Proportional Response (Not Everything Is a Fire)**
- The quality system must calibrate its response to the actual risk
- A formatting issue gets auto-fixed silently (no dialogue needed)
- An architectural concern gets a dialogue exchange (Channel B)
- A security vulnerability gets escalated with urgency
- An agent that treats everything as critical loses the dev agent's confidence quickly

---

## 4. Specialist Routing: Best-in-Class Per Domain

**The routing problem**: When the quality system needs to check something, who does it?

**Capability Registry**: Each specialist declares what it's good at and how good it is.

```yaml
specialists:
  - id: swiftlint
    domains: [swift, ios]
    capabilities: [lint, style]
    strength: high  # well-tuned for this project's .swiftlint.yml

  - id: ruff
    domains: [python]
    capabilities: [lint, style, security]
    strength: high

  - id: coderabbit
    domains: [all]
    capabilities: [review, architecture, patterns]
    strength: high
    type: external  # consumed via MCP wrapper
    latency: async  # returns minutes later, not seconds

  - id: clippy
    domains: [rust]
    capabilities: [lint, correctness, performance]
    strength: high

  - id: generic-llm-reviewer
    domains: [all]
    capabilities: [review, architecture, patterns]
    strength: medium  # good generalist, not as deep as specialists
    latency: sync
```

**Routing logic** (in the orchestrator or quality agent):
1. Determine the domain of the work (Swift? Rust? Cross-cutting architecture?)
2. Determine the type of quality concern (lint? architectural pattern? security? test coverage?)
3. Route to the highest-strength specialist for that (domain, concern) pair
4. If async specialists are available and time permits, dispatch to them in parallel
5. If no specialist exists, fall back to the generalist

**External service integration**: CodeRabbit, for example, is wrapped in an MCP server that:
- Accepts a diff or file set
- Calls CodeRabbit's API programmatically
- Parses the structured review output (not the human-readable PR comment)
- Returns findings in the same format as internal specialists
- The quality system consumes this identically to an internal specialist's output

**Simplicity check (P5)**: Start with a static YAML registry. Only add dynamic capability discovery if the number of specialists grows beyond what's manageable in a config file. Don't build an Agent Card (A2A) system until there are enough agents to need service discovery.

---

## 5. Extended Session Coherence: How to Work for Hours

This is the ultimate goal. The architecture must support sessions measured in hours, not minutes.

**Five mechanisms:**

**a) Session Goals + Acceptance Criteria (Set Once, Reference Always)**
- At session start, the orchestrator captures: what are we building? What does "done" look like? What are the deterministic criteria (tests pass, coverage met, build succeeds)?
- Every agent can reference these. When the quality agent pushes back, it's grounded in: "this doesn't meet acceptance criterion #3" not "I think this could be better."

**b) Checkpoint-Resume**
- After each meaningful unit of work (feature complete, test passing, module done), the orchestrator creates a checkpoint
- Checkpoint captures: what's done, what's remaining, current quality state, any open findings
- If an agent drifts, crashes, or loses context, work resumes from the last checkpoint, not from scratch
- LangGraph-style: state saved after every significant step

**c) Drift Detection**
- The orchestrator monitors for drift signals:
  - Time on a single task exceeding a threshold without progress
  - Repeated failures on the same issue (fix loop not converging)
  - Agent working on something not in the session goals
  - Quality degradation (new findings accumulating faster than they're resolved)
- On drift detection: intervene. Redirect. Suggest a different approach. Escalate to human if needed.

**d) Context Hygiene**
- Context is a finite resource. Long sessions degrade if context fills with irrelevant history.
- Between phases of work: summarize what was accomplished, clear detailed context, carry forward only what's relevant
- Quality agents maintain their own focused context (current findings, patterns seen) separate from dev agent context
- Specialists get only the context relevant to their domain (don't send the full session history to a linter)

**e) Progressive Confidence**
- As the session progresses and more work passes quality checks, the system builds momentum
- Early in a session: more frequent quality checks, more dialogue
- Mid-session with good track record: lighter touch, trust the dev agent more
- Late session or after regressions: increase scrutiny
- This adaptive intensity prevents alert fatigue while maintaining safety

---

## 6. The Enabling Role: Making Dev Agents Better

The quality system's primary purpose is making the dev agent produce better work than it would alone. This is the hardest part to mechanize, but there are four concrete mechanisms:

**a) Pattern Memory**
- The quality system remembers patterns from this project (not just findings)
- "In this codebase, new services always implement the protocol pattern. Here's an example from TTSService."
- This is proactive guidance, not reactive checking

**b) Architectural Guardrails as Navigation Aids**
- Instead of "you violated the layer boundary," the message is: "The pattern in this codebase for accessing the data layer from a view model is through the ServiceRegistry. Here's how SessionManager does it."
- The quality system acts as institutional memory of the codebase

**c) Suggestion, Not Just Rejection**
- When a finding requires a non-obvious fix, the quality agent suggests HOW, not just WHAT
- "This cyclomatic complexity of 15 could be reduced by extracting the retry logic into a shared RetryPolicy, similar to what exists in NetworkService.swift:45"

**d) Celebration of Quality**
- When a dev agent writes something genuinely well-architected, the quality system notes it
- Not empty praise, but recognition that builds the feedback loop: "This protocol-based approach to STT providers is exactly the pattern we want. Registering it as a reference for future similar work."
- This is how "having each other's back" manifests positively, not just in catching mistakes

---

## 7. The Memory Architecture

Without memory, agents are amnesiac collaborators who can accidentally destroy each other's work. This is the most critical addition to the vision.

### Three Memory Types

**1. Architectural Memory (Long-term, Project-scoped)**

Purpose: Protect architectural decisions and significant work from being casually rewritten.

Content:
- Which components represent significant intentional architecture (not just "code that exists")
- What pattern each component follows and why (protocol-based DI, service registry, etc.)
- What alternatives were considered and rejected (and why)
- Who/what built it and how much effort it represents

Mechanics:
- A structured document (or set of documents) that the system reads before suggesting changes to established components
- When an agent proposes rewriting something, the memory system flags it: "This component was built with X effort following Y pattern. It should be FIXED, not rewritten. Here's the architectural context."
- This is the specific defense against the rewrite problem: an agent seeing something that looks broken and deciding to rewrite it from scratch instead of understanding and fixing it

Example entry:
```yaml
component: KBOralSessionView
architecture: Protocol-based DI via init injection
established: 2026-01-10
effort: significant (3 sessions, multiple iterations)
pattern: Follows ServiceRegistry pattern from docs/ios/IOS_STYLE_GUIDE.md
note: "If this appears broken, it likely needs targeted fixes, not rewriting. The architecture is intentional and tested."
```

**2. Troubleshooting Memory (Medium-term, Problem-scoped)**

Purpose: When a problem recurs, know what was tried before.

Content:
- Problem descriptions (symptoms, context, error messages)
- Approaches attempted (what, when, outcome)
- What ultimately worked (the fix) or didn't work (still open)
- Why certain approaches failed (the specific reason, not just "didn't work")

Mechanics:
- Builds naturally from session activity (the system observes fix attempts and their outcomes)
- When a similar problem appears: "We've seen this before. 5 things were tried. 3 failed because [reasons]. Approach 4 worked. The current situation may differ because [context], but start with approach 4 as a hypothesis."

Key insight: A combination of factors that led to a fix doesn't always mean the same thing will work again, because the situation might be subtly different. The memory should present history as context, not as prescription.

**3. Solution Memory (Long-term, Pattern-scoped)**

Purpose: Recognize when a current situation matches a previously-solved class of problem.

Content:
- Patterns of problems that recur across different components
- Generalized solutions (not just "what we did in file X" but "the general approach")
- Successful architectural patterns worth replicating

Mechanics:
- More abstract than troubleshooting memory (patterns, not instances)
- When the quality/research agent sees code that matches a known pattern: proactively suggest the proven approach
- "This is a provider protocol implementation. The established pattern in this codebase is [X]. Here's TTSService as a reference."

### Memory Storage (Simplicity Check)

Don't over-engineer this. Start with:
- **Architectural Memory**: A structured YAML/markdown file in the repo, manually maintained initially, system-assisted updates later
- **Troubleshooting Memory**: Append-only structured log, searchable by problem description and symptoms. Could be SQLite or just a well-structured markdown file.
- **Solution Memory**: Curated document of generalized patterns, updated when a new pattern is identified. This is basically an evolving internal knowledge base.

All three are readable by any agent at session start. The orchestrator ensures agents consult memory before proposing changes to established components.

---

## 8. What We Don't Build (Simplicity Vector)

Applying P5 rigorously:

| Idea | Verdict | Reasoning |
|------|---------|-----------|
| Kafka event bus | Skip (for now) | Overkill for 1-3 agents on a single machine. A simple local message queue or structured log file with file-watching is sufficient. Revisit if agent count grows. |
| A2A protocol / Agent Cards | Skip (for now) | Formal service discovery for <10 specialists is YAML config. A2A is for internet-scale agent meshes. |
| Quantified confidence scores | Skip | Research shows the field hasn't solved this. Use structural trust (track record, explanation quality) instead of numeric scores. |
| Full peer-review debate architecture | Simplify | Don't need formal "author/reviewer/editor" roles. Use Channel B direct dialogue for the same effect with less ceremony. |
| W3C agent standards | Too early | Standards expected 2026-2027. Build on MCP now, adopt standards when they mature. |
| Dynamic capability discovery | Skip (for now) | Static YAML registry until the specialist count demands automation. |

---

## Lessons from PocketTTS: The Embryonic Pattern

The PocketTTS project already implements a crude but effective version of multi-agent collaboration that informed this vision.

### What Works Well

1. **Fresh Eyes Principle**: Each agent runs in a completely fresh session. This prevents confirmation bias and tunnel vision. The Research Advisor starts by re-reading everything rather than inheriting stale assumptions.

2. **Artifact-Based Communication**: Agents talk through files (`docs/audit/`), not real-time chat. Reports are structured, timestamped, versioned (2-version rotation). The Implementation Agent reads the Research Advisor's report as a briefing, not a conversation.

3. **"Don't Repeat Work" as a Core Rule**: The Research Advisor prompt explicitly says "Read what's been tried and suggest NEW things." `PORTING_STATUS.md` tracks "Issues Found and Fixed" and "Hypotheses Ruled Out." This is proto-memory.

4. **Confidence Levels on Output**: Suggestions are categorized as "High Confidence," "Worth Trying," and "Speculative." This graduated certainty builds the dev agent's trust. The dev agent learned to ask for the Research Advisor because its reports repeatedly broke through blockers.

5. **Separation of Concerns**: Each agent has one job. The Cleanup Auditor doesn't write code. The Verification Agent doesn't suggest fixes. The Research Advisor doesn't implement. This prevents role confusion.

### What's Missing (and This System Must Address)

1. **Automation**: Everything is manually triggered (copy-paste prompt into fresh session). No orchestration.
2. **Real-time collaboration**: No dialogue channel. It's async file drops only.
3. **Memory beyond 2 reports**: The 2-version rotation means history evaporates. No pattern memory.
4. **Confidence as track record**: The confidence levels are self-assessed by each agent. There's no system-level tracking of "this agent's High Confidence suggestions worked 11/12 times."
5. **No orchestration layer**: The human IS the orchestrator, deciding when to run which agent.
6. **No architectural protection**: Nothing prevents a fresh agent from rewriting code that another agent spent days building.

---

## Beyond "Quality": The Full Scope

"Quality Co-Agent" is too narrow a name for what this system actually is:

| Domain | What It Does | Example |
|--------|-------------|---------|
| **Quality** | Lint, test, coverage, security scanning | SwiftLint findings, test failures |
| **Architecture** | Guard architectural decisions, enforce patterns, prevent destructive rewrites | "This component uses protocol-based DI. Don't rewrite it, fix it." |
| **Research** | Fresh perspective, external knowledge, hypothesis generation | PocketTTS Research Advisor pattern, automated |
| **Troubleshooting Memory** | Remember what was tried, what failed, what worked | "We tried approach X on Jan 15. It failed because Y. Approach Z worked." |
| **Solution Memory** | Recognize recurring patterns and apply proven solutions | "This is the same class of bug we fixed in TTSService. The fix was..." |
| **Drift Prevention** | Keep multi-hour sessions on track | "You've been on this for 40 minutes. The Research Advisor broke a similar jam last time." |

This is **institutional memory + quality enforcement + research capability + session management**, all operating as a collaborative peer to the dev agents.

---

## Vision Summary

A session orchestrator maintains goals and coherence over multi-hour autonomous sessions. Worker agents (Claude Code instances) and quality agents operate as peers, communicating through structured dialogue (not just file drops), building mutual confidence through demonstrated value (not assigned permissions). When specialized expertise is needed, work routes to the best available specialist via a capability registry, with external services like CodeRabbit consumed agentically through MCP wrappers. The quality system's primary role is enabling, not gatekeeping: it provides pattern memory, architectural guidance, and proactive suggestions alongside its mechanical checking. Drift detection and adaptive intensity keep sessions productive over hours. Simplicity is maintained by building only what earns its place, starting with the smallest viable communication layer and growing only when complexity is justified.

**Core capabilities:**
1. **Quality enforcement**: Lint, test, coverage, security, Tool Trust
2. **Architectural memory**: Protect established decisions, prevent destructive rewrites, enforce patterns
3. **Troubleshooting memory**: Remember what was tried, what failed, what worked, present history as context
4. **Solution memory**: Recognize recurring problem classes, suggest proven approaches
5. **Research capability**: Fresh perspective on demand, breaking through blockers (automated)
6. **Session orchestration**: Goals, checkpoints, drift detection, adaptive intensity
7. **Specialist routing**: Best-in-class per domain, external services consumed agentically
8. **Structured dialogue**: Rich bidirectional communication, not just findings dumps

**The confidence mechanism**: Confidence emerges naturally from track record. When the research agent's "High Confidence" suggestions work 11/12 times, the dev agent develops genuine operational trust. When the quality system's architectural memory prevents a destructive rewrite, the dev agent learns to consult it proactively rather than resenting it. This is earned trust through demonstrated value, not assigned authority.

**The team relationship**: Dev agents and the collaborative intelligence system have each other's back. The system isn't just catching mistakes; it's providing the institutional memory, research capability, and quality infrastructure that makes the dev agents dramatically more effective than they would be alone. The dev agents aren't being policed; they're being supported by a teammate that remembers everything, knows the codebase patterns, and can bring fresh external research when things get stuck.

---

*This vision document is the conceptual foundation. The implementation details (specific tools, configurations, MCP servers, hooks) live in `work/QUALITY_CO_AGENT_MASTER.md`. This document answers "why this system exists, what it's shaped like, how the pieces relate, and what principles govern it." The master doc answers "what specific tools and configurations do we build."*
