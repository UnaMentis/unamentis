# Honcho and the Coordination Spectrum: Memory and Group Learning for UnaMentis

Research and analysis, 2026-06-26. Status: exploratory, not a commitment.

## Executive summary

Honcho (honcho.dev, by Plastic Labs) is an open-source "memory that reasons" layer for stateful AI agents. Its one genuinely novel idea, the part worth our attention, is not the memory store. It is the **peer/session data model**. In Honcho, a *Peer* can be a person, an agent, a group, or even an idea, and *Sessions* relate to Peers many-to-many. The system maintains per-peer *Representations* (theory-of-mind snapshots) and can answer "what does peer A understand about peer B (or about topic T)."

That single abstraction is a surprisingly clean fit for the thing this analysis was asked to explore: how UnaMentis could support learning together across the full range from a top-down classroom to a self-organizing trivia night, with memory and coordination as the connective tissue.

The honest tension: Honcho is a server. It needs PostgreSQL + pgvector + Redis + LLM calls. That directly conflicts with two things in our DNA, the on-device-first vision and the genuinely serverless "people self-organize without our server" use case. So the recommendation splits cleanly:

- **Adopt the conceptual model now** (peers, sessions, many-to-many membership, per-peer representations). It costs nothing and it future-proofs the data model.
- **Treat Honcho-the-product as an optional Tier-2/Tier-3 backend**, evaluated post-beta, never on the beta critical path, and never as the thing that makes group learning possible. Group learning should be possible with no central server at all.

The current reality check: UnaMentis today is a single-learner, single-session platform. There is no persistent learner model, no teams (only unused enterprise schema), and the only realtime layer is a point-to-point audio WebSocket. Everything below is greenfield.

---

## 1. What Honcho actually is

### Primitives

| Primitive | Meaning |
|-----------|---------|
| **Peer** | Any entity: a human, an AI agent, an NPC, a group, or an idea. The atomic identity. |
| **Session** | A conversation context. Peers join and leave sessions; the relationship is many-to-many. |
| **Message** | An atomic unit inside a session, labeled by its source peer. |
| **Workspace** | Top-level scope for queries (workspace / peer / session levels). |
| **Representation** | A theory-of-mind snapshot of a peer: communication style, beliefs, preferences, mental models. Built asynchronously. A "working representation" is a cached snapshot of a peer in the context of one session. |

### Key methods

- **`context()`**: returns curated reasoning plus conversation history in ~200ms, so the agent does not hand-build a context window. Claims 60-90% token savings.
- **Dialectic API / `chat()`**: send a natural-language query *about a peer* and get an answer from that peer's representation. Example: "What is the best way to explain technical concepts to this user?" Tiered cost from minimal ($0.001) to max ($0.50) per call.
- **Dreaming**: background reasoning that runs continuously, finding patterns and testing hypotheses without blocking runtime.

### The differentiator: theory of mind across peers

Because sessions are many-to-many with peers, Honcho can model **"what does Alice know about Bob"** or "what does the support-agent persona think the customer wants" as first-class queries. This is the thing a plain vector database cannot do. It is the reason Honcho is interesting for *group* learning specifically, not just per-user memory.

### Deployment, license, cost

- Open source (FastAPI server, Docker Compose). License reported as Apache-style; verify current terms before any adoption.
- Self-host requires **PostgreSQL + pgvector + Redis + an LLM backend**. Independent reviewers put setup at ~30 minutes versus ~30 seconds for lighter tools like Mem0.
- Managed cloud: ingestion ~$2.00 / million tokens, unlimited `context()` calls, dreaming included. Free credits for startups.
- Reported benchmarks: 90.4% LongMem S, 89.9% LoCoMo, using ~5% median context. Strong, but vendor-reported.
- **Cannot run edge-only or in-browser, and cannot run on-device.** This matters a lot for us.

Education is one of Honcho's own named use cases, described as "tracking misconceptions across sessions." That is almost exactly what a learning platform wants.

---

## 2. Why this is relevant: the peer/session model is a coordination substrate

The request framed a spectrum:

> from a very purposely and hard-organized top-down [classroom] ... to something kind of like self-organizing among individuals [trivia night, a learning-focused reading group].

The insight is that **all of these are the same data model at different altitudes.** Every one of them is:

- a set of **peers** (learners, plus optionally a facilitator agent, plus the *group itself* as a peer),
- sharing one or more **sessions** (a study session, a quiz round, a curriculum walkthrough),
- each peer carrying a **representation** (what they individually understand),
- and the group peer carrying a **collective representation** (what the group has covered, where the shared gaps are).

The only thing that changes across the spectrum is **where the representation lives and who coordinates the session**:

- On a single device (solo).
- On the devices in the room, synced peer-to-peer (self-organizing, no server).
- On one peer's phone acting as a temporary host (a designated "table captain").
- On our cloud (persistent groups across distance).
- On an institutional deployment with rosters and dashboards (classroom).

Honcho proves the abstraction is sound. Whether we *use Honcho* or implement the same primitives ourselves is a separate, later decision (section 8).

---

## 3. Current UnaMentis state (the gap we are reasoning against)

From a full sweep of the repos:

- **Memory is session-scoped only.** `FOVSession` holds conversation history and a hierarchical FOV context (immediate/working/episodic/semantic), but it lives in memory and is discarded when the session ends. There is no persistent learner model server-side.
  - `server/management/fov_context/session.py`, `server/management/fov_context/manager.py`
- **Progress is on-device only.** iOS `ProgressTracker.swift` and Android `TopicProgressEntity.kt` track time-spent and a per-topic mastery estimate (0.0-1.0), locally, never uploaded, never synced across devices.
- **No teams, only unused schema.** `server/database/schema.sql` defines `organizations` (personal, school, district, university, enterprise, **homeschool_coop**), `organization_memberships` (student, teacher, admin, parent, guardian), and `guardian_relationships`. None of it is wired to endpoints. There is no classroom, cohort, roster, shared session, or instructor view in code.
- **The only realtime layer is point-to-point.** `server/management/audio_ws.py` maps one `session_id` to one WebSocket for one user. No broadcast, no pub/sub, no group messaging, no join mechanism.
- **Curriculum (UMCF) is shareable but uncoordinated.** Many learners can follow the same curriculum, but each does so in isolation with no shared checkpoints or awareness of others.
- **Relevant assets already exist:** a Knowledge Bowl / trivia module, the Socratic Engine vision, and the homeschool/school org types. The group story is not starting from zero conceptually, only in code.

Bottom line: the platform is an excellent *single-learner session engine* with *no persistent learner memory and no multi-user coordination*. Both are greenfield.

---

## 4. The coordination spectrum, as an architecture

A single abstraction (peers + sessions + per-peer representations) deployed at four altitudes. Lower tiers need no server, which is the part that matters for the "self-organizing without us" question.

### Tier 0, Solo (today)
One learner, one device, on-device progress. Already exists. The missing piece is promoting on-device progress into a real persistent **learner representation** (cross-session, cross-device). This is the foundation everything else reuses.

### Tier 1, Ephemeral peer mesh, NO server
The trivia night, the in-person study group, the family at the kitchen table. Devices in proximity form a session over local transport (iOS MultipeerConnectivity, Android Nearby Connections, or a LAN). State is a **shared ephemeral session** synced device-to-device, ideally with CRDTs so there is no authoritative server and no conflict on reconnect. One device can volunteer as a lightweight "table captain" to run the facilitator agent (on-device LLM, Ministral-3B), or each device runs its own and they sync only the shared facts (current question, scores, whose turn, group coverage).

This is the tier that is **architecturally incompatible with Honcho-the-product** and that is fine. Here the "representation" is small and lives on-device. We implement the primitives ourselves at this altitude.

### Tier 2, Persistent group, cloud-backed
A standing learning circle that meets weekly but lives in different cities. Needs durable shared state, async catch-up, and a group representation that survives between meetings. This is where a Honcho-style backend (ours or theirs) earns its keep: a **group peer** accumulates collective coverage, and the facilitator can ask "what has this circle not yet understood about chapter 4."

### Tier 3, Institutional classroom, top-down
Instructor assigns a curriculum to a roster, sees per-student mastery and **class-level misconceptions**, and the system adapts. This is the full org schema plus per-student representations plus a class representation plus an instructor dashboard. Honcho's named education use case ("tracking misconceptions across sessions") maps directly here. This is also where privacy and compliance get serious (section 7).

The elegance: **Tier 1 and Tier 3 use the same vocabulary.** A trivia team and a classroom are both "a group peer with member peers sharing a session." We can ship Tier 1 with no server and later light up Tiers 2-3 by changing where the representation is hosted, not by rewriting the model.

---

## 5. Concrete use cases mapped to UnaMentis

| Use case | Tier | Group-peer value | UnaMentis tie-in |
|----------|------|------------------|------------------|
| **Knowledge Bowl / trivia team practice** | 1 (in person) or 2 (remote) | Track the *team's* collective coverage; route each question to the member weakest on it; quiz the gaps | Knowledge Bowl module already exists |
| **Learning circle / "reading group but for learning"** | 1 or 2 | Sync everyone's position in a curriculum; facilitate cross-member Socratic dialogue; surface where the group disagrees or is confused | Socratic Engine vision; UMCF curriculum |
| **Classroom** | 3 | Per-student mastery + class-level misconception map; adaptive pacing; instructor dashboard | school/district org types; guardian relationships |
| **Peer tutoring / study buddy** | 1 or 2 | Theory-of-mind "what does the stronger peer know that the struggling peer doesn't," to scaffold explanations | Dialectic-style query over two representations |
| **Homeschool co-op / family** | 1 (kitchen table) or 2 | Shared progress across siblings; parent as facilitator peer | `homeschool_coop` org type already in schema |
| **SAT / cert exam study group** | 1 or 2 | Collective weak-area heatmap; group drills on shared gaps | SAT prep, language cert modules |

The recurring pattern: the **group is a peer with its own representation**, and the facilitator agent reasons over both the individual and the collective. That is the capability a vector DB cannot give us and the reason Honcho's model is worth borrowing.

---

## 6. The serverless self-organizing question, answered honestly

The most interesting part of the prompt is whether people can "self-organize ... without having the server." The honest answer has two halves.

**Yes, and it is a real differentiator.** UnaMentis already runs models on-device (Ministral-3B, Pocket TTS, Silero VAD). That means a group can, in principle, run a full voice learning session with **no cloud at all**: local model for facilitation, local TTS for voice, and peer-to-peer sync for the shared session state. For a privacy-sensitive, on-device-first OSS, nonprofit-oriented project, "your study group works on a plane with no internet and no account" is a genuinely strong, on-brand capability. Almost nobody else can credibly offer it.

**But Honcho cannot be what enables it.** Honcho is intrinsically a server (Postgres, pgvector, Redis, LLM calls; no edge, no browser, no device). So for Tier 1 we adopt Honcho's *ideas*, not its *binary*. The serverless tier needs:

- a **CRDT-based shared session document** (last-writer-wins or OR-set for scores, turn order, current item, group coverage),
- **local peer transport** (MultipeerConnectivity / Nearby Connections / LAN/mDNS),
- an **on-device, shrunken representation** rather than a dreaming background reasoner,
- optional **opt-in cloud handoff**: when the group wants persistence, the ephemeral session is promoted into a Tier-2 cloud (or one-peer-hosted) representation.

So the strategic framing is: **the conceptual model is universal; the deployment is tiered; Honcho is one possible Tier-2/3 backend, not the foundation.** Building group learning *on top of* a mandatory Honcho dependency would quietly kill the serverless use case, which is one of our most distinctive ones. That is the trap to avoid.

---

## 7. Tensions, risks, and ethics

This is where the prompt's "challenge every aspect" applies hardest.

1. **On-device vision vs Honcho's server requirement.** Direct conflict. Resolved only by treating Honcho as optional backend, never foundation. If we ever frame group learning as "requires our cloud," we have regressed on a core principle.

2. **Profiling minors.** Theory-of-mind representations are, bluntly, psychological profiles. Classrooms and homeschool co-ops mean **children**. Building and storing persistent psychological models of minors triggers COPPA, FERPA, and GDPR-for-kids obligations, plus a real ethical bar. The existing `guardian_relationships` and privacy-tier schema are necessary but nowhere near sufficient. Any Tier-3 work must lead with consent, data minimization, retention limits, and the ability to *not* build a representation at all. "Dreaming" background inference on a child's conversations is exactly the kind of feature a regulator and a parent will scrutinize.

3. **Cost and the beta.** Honcho ingestion is ~$2/M tokens (cloud) or a non-trivial self-host stack. The beta direction is deliberately *minimal* AWS doing OSS-model inference with privacy-aware telemetry. Honcho does not belong anywhere near the beta critical path. It is a post-beta evaluation at the earliest.

4. **Vendor and architectural lock-in.** Honcho's value is in its representations. If those live in their cloud and their format, migrating later is painful. Self-hosting mitigates this but imports the full operational burden (Postgres + pgvector + Redis + LLM ops) onto a project that is trying to stay lean.

5. **Maturity.** Strong but vendor-reported benchmarks, a young product, evolving license terms. Fine to learn from, risky to depend on for anything user-facing before the model and license stabilize.

6. **The representation can be wrong, confidently.** A theory-of-mind snapshot that mislabels a learner ("this student doesn't grasp fractions") and then drives pacing can entrench a wrong call. Group representations compound this. Any adoption needs the representation to be inspectable, correctable, and never a silent gate.

---

## 8. Build vs adopt

For each tier:

- **Tier 0-1 (solo + serverless group): build our own primitives.** They must be small, on-device, and CRDT-syncable. Honcho structurally cannot serve here. This is also where most of the distinctive product value is.
- **Tier 2-3 (persistent + institutional): evaluate, do not assume.** Options, lightest to heaviest:
  - Build a minimal "group representation" service ourselves on the existing management API (we already have FOV context machinery to extend).
  - Adopt a lighter memory layer (Mem0, Zep) if we only need per-user memory and can add group logic ourselves.
  - Adopt self-hosted Honcho if the *theory-of-mind-across-peers* capability proves to be the thing that makes group facilitation good, and only if we can carry the ops.

The decision hinges on one empirical question: **does cross-peer theory of mind measurably improve group facilitation enough to justify the operational and privacy cost?** We cannot answer that from a doc. It needs a prototype.

---

## 9. Recommendation and phased path

1. **Now (data model only, near-zero cost):** Adopt the peer/session vocabulary in our own schema. Promote on-device progress into a real persistent **learner representation** with cross-device sync. Add a `Peer` notion that can be a person *or a group*, and a many-to-many `session_participants`. This makes every later tier cheap and does not touch the beta runtime.
2. **Post-beta, prototype Tier 1 (no server):** Build the serverless ephemeral group session for **Knowledge Bowl trivia practice**, since that module exists and is the most fun, lowest-stakes proving ground. Local transport + CRDT shared state + on-device facilitation. Measure whether a "group coverage" representation makes the practice meaningfully better.
3. **Then Tier 2 (cloud, optional):** Add opt-in promotion of an ephemeral group into a persistent cloud group for the distributed learning circle. *Here* run a head-to-head: our own minimal group-representation service vs self-hosted Honcho, judged on facilitation quality, cost, and privacy posture.
4. **Only with a real institutional partner, Tier 3 (classroom):** Wire the org schema, build the instructor dashboard, and do the consent/compliance work first, not last. Lead with the privacy story for minors.

The throughline: **borrow Honcho's idea immediately, decide on Honcho's software much later, and never let either compromise the serverless, on-device-first capability that makes group learning on UnaMentis genuinely different.**

---

## Sources

- [Honcho](https://honcho.dev) and [Honcho docs](https://docs.honcho.to/)
- [plastic-labs/honcho on GitHub](https://github.com/plastic-labs/honcho)
- [Honcho Review: Plastic Labs' Agent Memory Layer (2026), andrew.ooo](https://andrew.ooo/posts/honcho-plastic-labs-agent-memory-review/)
- [Honcho, A Dialectic API to Personalize AI Agents using Theory of Mind (AI Tinkerers Seattle)](https://seattle.aitinkerers.org/talks/rsvp_-NsjdNcildg)
- [Agent Framework Integrations, plastic-labs/honcho (DeepWiki)](https://deepwiki.com/plastic-labs/honcho/9.1-agent-framework-integrations)

Internal current-state references: `server/management/fov_context/session.py`, `server/management/audio_ws.py`, `server/database/schema.sql`, `curriculum/spec/UMCF_SPECIFICATION.md`, iOS `ProgressTracker.swift`, Android `TopicProgressEntity.kt`.
