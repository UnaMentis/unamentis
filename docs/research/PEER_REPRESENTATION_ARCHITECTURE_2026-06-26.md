# Peer & Representation Layer: Architecture Proposal

Status: proposal for ratification, 2026-06-26. Companion to [HONCHO_AND_GROUP_LEARNING_2026-06-26.md](HONCHO_AND_GROUP_LEARNING_2026-06-26.md).
Method: deep code-dive of the actual Honcho source (AGPL-3.0, ~38.5k LOC) plus a multi-agent design pass (8 research threads, 3 competing proposals, a 3-judge panel, adversarial critique). All claims about UnaMentis internals below are verified against current code with file:line citations.

---

## 1. The recommendation, up front

Build **our own** peer/representation engine, clean-room, as a **first-class, permanent contract** that runs the **identical model on a phone (SQLite) and on the lean server (Postgres)**. Make a **group a kind of peer**, so groups-of-groups need no special case. Put the heavy reasoning behind **two swappable interface seams**, so we can grow the intelligence in waves, and so an **optional, network-isolated, source-published Honcho service** can be plugged in later for heavy server-tier reasoning **without ever touching the client, the model, or the beta**.

Land the **entire model now** as inert, flag-dark stubs (migration 006 + a stubbed `peer_api.py` + two no-op seams in the FOV layer). The beta runtime does not change. Capability then ships in additive waves, and because the ten decisions in section 8 are locked correctly in the first stub, **no later wave forces a re-architecture**.

This is not a "simple v1." The model is complete on day one. Only the build is phased.

## 2. Why this shape won

Three proposals were argued at full strength and scored by a 3-judge panel:

| Approach | License/Distribution judge | Pragmatism judge | Data-model-rigor judge |
|---|---|---|---|
| **P1 Fork-and-refactor Honcho** | 48 | 47 | 47 |
| **P2 Clean-room spine** | 53 | 55 | 55 |
| **P3 Hybrid interface-first** | **56** | **57** | 53 |

The panel converged, near-unanimously, on a synthesis: **P2's clean-room, ID-keyed, recursion-native model as the spine**, **P3's pluggable backend port**, and **P1's forked Honcho kept strictly behind that port** (optional, off-device, post-beta). The rigor judge added the decisive correction that the adversarial critic then confirmed: do **not** collapse the observation log into the representation edge (P3's one real flaw), because that single shortcut breaks CRDT convergence, group rollup, and minor-deletion purge all at once.

Fork-and-refactor (P1) lost on a concrete self-contradiction the critic verified: Honcho's `Collection`/`Document`/`Peer` are keyed on `peers.name` + `workspace_name` composite FKs ([honcho `src/models.py:130,335`]), so you cannot both "reuse the tables verbatim" and "rekey them to immutable client-mintable IDs," which the offline/serverless tier requires. You would migrate the core tables anyway, and you would still have to build a separate clean-room engine for the App Store binary (see section 7). Two engines, a fast-moving AGPL fork to rebase, and roughly double the minimal-AWS footprint, for an 80% you mostly cannot reuse on a phone.

## 3. The one model

Seven tables in `server/database/migrations/006_peer_representation_stubs.sql` (the next migration number is confirmed 006: 002-005 exist). The **same logical schema** is created in on-device SQLite, with two documented divergences (the closure table is server-only; the embedding column is pgvector on server, sqlite-vec or absent on device). DDL below is illustrative, not final.

### 3.1 Peers (a group is just a peer)

```sql
CREATE TABLE peers (
  id            UUID PRIMARY KEY,          -- UUIDv7, CLIENT-MINTABLE (offline-safe). See lock #1.
  kind          TEXT NOT NULL DEFAULT 'person'
                CHECK (kind IN ('person','group','agent','topic')),
  display_name  TEXT,
  user_id       UUID REFERENCES users(id) ON DELETE SET NULL,          -- v4 id-space (lock #1)
  organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL, -- bridges existing recursive org tree
  is_local_only        BOOLEAN NOT NULL DEFAULT true,
  treat_as_minor       BOOLEAN NOT NULL DEFAULT true,   -- protective default (lock #4)
  representations_enabled BOOLEAN NOT NULL DEFAULT false, -- opt-in (lock #4)
  metadata      JSONB NOT NULL DEFAULT '{}',
  lamport       BIGINT NOT NULL DEFAULT 0,   -- CRDT (lock #3)
  hlc           TEXT,                        -- hybrid logical clock (lock #3)
  origin_device TEXT,                        -- CRDT (lock #3)
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ                  -- tombstone, never hard-delete (lock #3)
);
```

`organization_id` is the optional bridge to the **existing recursive `organizations` tree** (`schema.sql:801`, `parent_organization_id`; index at `:818`; `organization_memberships` at `:1025`; `guardian_relationships` at `:1062`). Institutions reuse that tenancy/SSO/DPA machinery instead of reinventing it. The serverless tier leaves it NULL.

### 3.2 Recursive membership (groups-of-groups)

```sql
CREATE TABLE peer_memberships (        -- self-referential edge = arbitrary nesting
  id             UUID PRIMARY KEY,
  parent_peer_id UUID NOT NULL REFERENCES peers(id),
  member_peer_id UUID NOT NULL REFERENCES peers(id),  -- may itself be kind='group'
  role           TEXT CHECK (role IN ('member','facilitator','captain','instructor','guardian')),
  edge_config    JSONB NOT NULL DEFAULT '{}',
  joined_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  left_at        TIMESTAMPTZ,           -- soft membership (OR-Set remove)
  lamport BIGINT, hlc TEXT, origin_device TEXT, deleted_at TIMESTAMPTZ,
  CHECK (parent_peer_id <> member_peer_id),
  UNIQUE (parent_peer_id, member_peer_id) -- active dup guarded in app/partial index on left_at IS NULL
);

CREATE TABLE peer_closure (            -- SERVER-ONLY transitive cache, NOT source of truth
  ancestor_id   UUID NOT NULL REFERENCES peers(id),
  descendant_id UUID NOT NULL REFERENCES peers(id),
  depth         INT  NOT NULL,
  PRIMARY KEY (ancestor_id, descendant_id)
);
```

On device there is no `peer_closure`; transitive membership over the tiny local graph is a recursive CTE. The conformance suite (lock #10) proves the two paths return identical answers on diamond, multi-parent, and cycle graphs.

### 3.3 Sessions (distinct from the FOV session)

```sql
CREATE TABLE learning_sessions (       -- a shared learning EVENT with N participants
  id            UUID PRIMARY KEY,
  host_peer_id  UUID REFERENCES peers(id),
  curriculum_id TEXT, topic_id TEXT,
  mode          TEXT CHECK (mode IN ('solo','adhoc','circle','classroom','competition')),
  transport     TEXT CHECK (transport IN ('local','cloud','p2p')),
  is_active     BOOLEAN NOT NULL DEFAULT true,
  lamport BIGINT, hlc TEXT, origin_device TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(), deleted_at TIMESTAMPTZ
);

CREATE TABLE session_participants (
  session_id     UUID NOT NULL REFERENCES learning_sessions(id),
  peer_id        UUID NOT NULL REFERENCES peers(id),
  role           TEXT,
  observe_me     BOOLEAN NOT NULL DEFAULT false,  -- consent, protective default (lock #4)
  observe_others BOOLEAN NOT NULL DEFAULT false,  -- consent, protective default (lock #4)
  joined_at TIMESTAMPTZ, left_at TIMESTAMPTZ,
  lamport BIGINT, hlc TEXT, origin_device TEXT,
  UNIQUE (session_id, peer_id)
);
```

**`learning_session` is a NEW entity, not an extension of the FOV `UserSession`.** The FOV runtime is a one-session-per-user singleton: `SessionManager._users_to_sessions: dict[str, str]  # user_id -> session_id` ([session.py:635](../../server/management/fov_context/session.py#L635)), `UserSession` at [:518](../../server/management/fov_context/session.py#L518). The mapping is documented as: **one FOV `UserSession` = one participant row** in a `learning_session`. Conflating them is the Wave-3 re-architecture trap (lock #5).

### 3.4 Representation = a directed edge (collection) + an append-only log

This is the corrected, two-table design. A **collection** is the directed `observer → observed` theory-of-mind edge. **Observations** are the append-only, provenance-linked facts under it. A **Representation** (the thing a caller receives) is a **runtime projection** over observations, never a stored blob.

```sql
CREATE TABLE peer_collections (        -- directed observer/observed edge (Honcho "Collection")
  id            UUID PRIMARY KEY,
  observer_peer_id UUID NOT NULL REFERENCES peers(id),
  observed_peer_id UUID REFERENCES peers(id),   -- typed FK (lock #8)
  observed_topic_id TEXT,                        -- mutually exclusive with observed_peer_id
  scope         TEXT CHECK (scope IN ('self','peer','aggregated','coverage')),
  lamport BIGINT, hlc TEXT, origin_device TEXT, deleted_at TIMESTAMPTZ,
  CHECK ((observed_peer_id IS NULL) <> (observed_topic_id IS NULL)),
  UNIQUE (observer_peer_id, observed_peer_id, observed_topic_id, scope)
);

CREATE TABLE peer_observations (       -- append-only fact log (Honcho "Document")
  id            UUID PRIMARY KEY,
  collection_id UUID NOT NULL REFERENCES peer_collections(id) ON DELETE CASCADE,
  level         TEXT NOT NULL DEFAULT 'explicit'
                CHECK (level IN ('explicit','deductive','inductive','contradiction','aggregated')),
  content       JSONB NOT NULL,
  topic_id TEXT, objective_id TEXT, mastery REAL, confidence REAL, coverage_count INT,
  source_ids    JSONB NOT NULL DEFAULT '[]',     -- provenance DAG (GIN-indexed)
  contributor_peer_id UUID REFERENCES peers(id), -- whose data rolled up (lock for minor purge)
  source_session_id UUID,
  embedding     VECTOR,                           -- pgvector (server) / sqlite-vec or NULL (device)
  times_derived INT NOT NULL DEFAULT 0,
  derived_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ,                      -- tombstone (lock #3)
  lamport BIGINT, hlc TEXT, origin_device TEXT
);
```

`observer == observed` is self-knowledge. `observer = group, observed = member` is the group's model of a member. `observed_topic_id` is coverage/gaps. The same mechanism works at person grain and group grain, so "a classroom's model of a student" and "a student's self-model" are the same shape.

## 4. Recursive groups, end to end

A group is a peer (`kind='group'`); nesting is the self-referential `peer_memberships` edge whose member may itself be a group. Company → department → member is just nested edges at arbitrary depth. Two query modes everywhere: **direct** (depth 1 over edges) and **transitive** (server: `peer_closure` index scan; device: recursive CTE).

A **group representation** is `observer == group` (scope `aggregated`), produced by a rollup that walks descendants via closure and emits `level='aggregated'` observations with `source_ids` + `contributor_peer_id` provenance. Coverage rule: a topic is "covered" by the group if **at least k members** have an explicit/deductive observation on it; a "gap" is a topic no member covers; mastery aggregates as a **cohort statistic**, never a raw concatenation. A **k-anonymity / minimum-cohort gate** runs before any aggregate materializes, so a single learner's gap cannot leak upward.

Two correctness rules the critic surfaced, locked from day one:
- **`derive()` for a group observer is always UnaMentis-side** (closure-walk + cohort-stat). It is never delegated to the optional Honcho backend, because Honcho is structurally flat-peer-only and would derive from the group peer's own messages, not roll up members (lock #7).
- **The k-gate is evaluated per ancestor-group, not globally.** A learner in group A (k=5) and group B (k=2, below threshold) must contribute to A's aggregate but be suppressed in B's. And **erasure re-evaluates the k-gate after a delete**: if removing one child drops a cohort below k, the aggregate is deleted, not merely decremented.

## 5. Three tiers, one model

Selected by `learning_sessions.transport`. The model is identical; only the host changes.

- **Tier 0, serverless (two phones, no internet, `transport=p2p|local`).** The same tables in on-device SQLite (no `peer_closure`; recursive CTE instead). Each phone mints its own person-peer, a shared group-peer, and the edges. Observations are an append-only OR-Set synced over MultipeerConnectivity / Nearby. On-device extraction runs the cheap explicit-fact tier only (Qwen3-1.7B today, no embeddings needed: recency + lexical retrieval). This tier **is the on-device-first identity** and it cannot contain any AGPL code (section 7).
- **Tier 1, cloud group (lean AWS, `transport=cloud`).** The same tables in Postgres. A Postgres lease-queue deriver (the Honcho pattern, clean-room: a queue table + a unique active-lease + `FOR UPDATE SKIP LOCKED` reclaim + `ON CONFLICT DO NOTHING` claim, **no Redis**) computes server-side observations and group rollups. Devices still keep their local SQLite copy and sync deltas up, so phone → cloud is the **same** reconciliation as phone → phone (with the asymmetry noted in lock #9 caveats).
- **Tier 2, institutional (orgs-of-orgs).** Same tables; `organization_id` links the peer tree to the existing recursive `organizations` table; `peer_closure` makes "all transitive members of district X" a single index scan. Heavy deductive/inductive/contradiction derivation for **non-group** peers may optionally be delegated to the Honcho backend (section 7).

## 6. Honcho disposition and the license firewall

UnaMentis is open source forever; the server may be paid-hosted exactly as published, which is standard for OSS and AGPL-compatible. So AGPL is **not** a problem on copyleft-philosophy grounds. The only two technical frictions are real and both are respected:

1. **No AGPL code in the App Store binary.** Shipping AGPL/GPL-family code inside an iOS app via the App Store conflicts with Apple's distribution terms (the documented VLC/GPL precedent), independent of anything commercial. So the **on-device engine is clean-room, full stop.**
2. **No AGPL imported in-process.** The optional Honcho backend, if ever deployed, runs as a **separate network service** reached over HTTP. Honcho's own license split is the proven pattern: the server is AGPL-3.0 (verified: `LICENSE` is verbatim Affero GPLv3; `src/main.py` declares `AGPL-3.0-only`), but its Python SDK is Apache-2.0 and is a **pure httpx client that imports none of the AGPL server code**. We reach the service the same way. The network boundary is the copyleft firewall.

So:
- **CONCEPT, clean-room (used everywhere, incl. on-device):** the directed `(observer, observed)` key with the `self` convention; the append-only observation log with a `source_ids` provenance DAG and the epistemic level lattice; the fast-extractor vs slow-reflector split; temporal soft membership; the budgeted non-LLM `get_context` projection; the Redis-free Postgres lease-queue pattern. Ideas and data-model and API shapes are not copyrightable; expression is. Hygiene: a two-room protocol (a spec engineer may read Honcho and write non-expressive behavior/interface specs; a separate implementation engineer codes only from specs), with a written audit trail and SPDX headers.
- **CODE, optional, server-only, behind the port:** forked or, ideally, **unmodified** Honcho as a separate AGPL service for heavy per-peer reasoning at Tier 1/2. Running it unmodified avoids even triggering the modified-network-service obligation; if forked, we publish source (which we do anyway) and add a visible source link. It is never load-bearing: the port **degrades to the clean-room LocalBackend**.

This is engineering strategy, not legal advice. Confirm the in-process-vs-service line and the Apple/AGPL question with OSS counsel before shipping any Honcho-backed combination.

## 7. The ten locks (this is the "no re-architecture" guarantee)

Each of these, if gotten wrong in migration 006, forces exactly the later re-architecture we are trying to avoid. They are cheap now and a graph-wide migration later. **These must be right in stub #1.**

1. **ID regime.** `peers.id` is a **client-mintable UUIDv7**. `user_id` and `organization_id` are FKs into the existing **server v4 id-space**, a deliberately separate regime, documented. Define how an offline-minted peer (no user, no org) **binds to a server `user_id` at first authenticated sync**.
2. **Two tables, not one.** `peer_collections` (directed edge) separate from `peer_observations` (append-only, provenance DAG). Do not collapse them into a single `content JSONB` table. This split is the spine of CRDT convergence, group rollup, and minor purge.
3. **Full CRDT columns on every syncable table from v1:** `lamport BIGINT` + `hlc TEXT` + `origin_device TEXT` + `deleted_at` tombstone (never hard-delete). Lamport alone is insufficient; HLC gives wall-clock-meaningful ordering for last-writer-wins on scalar facts.
4. **Protective minor defaults as NOT NULL DB defaults**, not app code: `representations_enabled DEFAULT false`, `treat_as_minor` defaulting to the safe value when unknown (the device has no `users` row), `observe_me`/`observe_others DEFAULT false`. Any direct write path (FOV sink, device extractor, importer) must be structurally OFF until explicit opt-in.
5. **`learning_session` is a new entity distinct from the FOV `UserSession` singleton.** Document the one-FOV-session-equals-one-participant-row mapping. Do not extend the FOV session.
6. **Route namespace.** Peer routes live under **`/api/peer-sessions`** and `/api/peers`, never `/api/sessions` (that path is already owned by `fov_context_api.py:38-45` and a duplicate registration crashes the whole management API at boot). "Mirror Honcho names" applies to the **backend port method names only**, never the public HTTP path.
7. **Group `derive()` is UnaMentis-side.** The backend port signature must make a group representation a local closure-walk + cohort-stat; only non-group per-peer derivation is delegable to the optional Honcho backend.
8. **Referential integrity for the observed target.** Use typed FKs (`observed_peer_id` XOR `observed_topic_id`) so a DB cascade can enforce minor erasure, rather than an opaque `'peer:UUID'` text string that makes deletion an application-code best-effort.
9. **Serverless cycle-breaker.** OR-Set edges alone do not prevent cycles: two phones can each add an individually-acyclic edge that forms a cycle after merge. Specify a deterministic post-merge cycle-detection-and-break pass before Wave 2. Related caveat: phone↔cloud sync is **asymmetric** (device appends explicit observations; server derives higher levels that sync back down), so erasure must purge **server-derived descendants** of a deleted observation too.
10. **Conformance suite, written in Wave 0.** It must assert (a) transitive-membership **equality** between the server closure path and the device recursive-CTE path on diamond/multi-parent/cycle graphs, and (b) the non-embedding `get_context` projection is **identical across tiers** (semantic retrieval is a server-only enhancement that must not change coverage/membership answers).

## 8. First-class stubs to land now (Wave 0, beta-safe)

All inert, all behind flags flipped to False. **The flag flip must ship in the same commit as the routes**, with a test asserting the default is False, or half-built endpoints go live to TestFlight.

- **(a)** `migration 006_peer_representation_stubs.sql`: the seven tables, empty. Targets the auth/users Postgres. (Confirm the minimal-AWS beta footprint actually provisions that Postgres, or make 006 a no-op there.)
- **(b)** `server/management/peer_api.py`, modeled on `fov_context_api.py`, every route under `guarded_routes(app, FlagKeys.TEAM_MODE)` returning 503 (or 501 NotImplemented) in beta: `POST/GET /api/peers`, `GET /api/peers/{id}`, `POST /api/peer-memberships`, `POST /api/peer-sessions`, `POST /api/peer-sessions/{id}/participants` (join), `DELETE .../participants/{peer_id}` (leave), `GET /api/peers/{id}/representation?target=`, `POST /api/peers/{id}/chat` (dialectic, 501).
- **(c)** Flip `FlagKeys.TEAM_MODE` and `FlagKeys.COMPETITION_SIM` defaults True → False at [feature_flag_keys.py:111-112](../../server/management/feature_flag_keys.py#L111-L112).
- **(d)** Two no-op seams in the FOV layer: an optional `representation_sink` (default None) called at `FOVSession.record_topic_completion` ([session.py:445](../../server/management/fov_context/session.py#L445)) and `FOVSession.end` ([:234](../../server/management/fov_context/session.py#L234)), emitting a mastery/struggling-concepts delta. None in beta = pure no-op. Add as a pure additive optional param with a test that `FOVSession` still constructs with no sink (it is the live tutoring path).
- **(e)** Add `peer_id: Optional[str] = None` to `UserSession` so the realtime layer already carries the identity a future multi-peer fan-out keys on.
- **(f)** Two Python `Protocol`s as the swap seams: **`RepresentationStore`** (`get_context`, `get_representation`, `write_observation`) and **`ObservationDeriver`** (`derive`), with a default no-op/empty `LocalBackend`. Two seams, not one, so the cheap on-device extractor and the heavy server reasoner are independently swappable.
- **(g)** A one-page ADR in `docs/architecture/` recording the model, the ten locks, the two license invariants, and the documented audio-WS seam (later: `Dict[str, Set[ws]]` fan-out + replace the ownership check at [audio_ws.py:146](../../server/management/audio_ws.py#L146) with a `session_participants` membership check, reusing `broadcast_to_session` at [:487](../../server/management/audio_ws.py#L487)). Do not touch `audio_ws.py` or UMCF in beta.
- **(h)** The conformance test scaffolding from lock #10.

## 9. Build waves (model whole now; capability additive)

| Wave | Delivers | Tier | New model? |
|---|---|---|---|
| **0** | Migration 006 + stubs + seams + Protocols + ADR + conformance scaffold. Flag-dark. | n/a | None (whole model lands) |
| **1** | Solo cross-session memory: FOV sink writes self-observations; non-LLM `recent + most-derived` projection. | server + device | None |
| **2** | Ad-hoc 2-peer, serverless: on-device SQLite engine, device-to-device OR-Set sync, cycle-breaker. Knowledge Bowl trivia is the proving ground. | Tier 0 | None |
| **3** | Cloud groups (study circle / classroom / competition): audio-WS fan-out + membership check; Postgres lease-queue deriver; consent toggles. | Tier 1 | None |
| **4** | Group rollup + dialectic: bounded deterministic coverage rollup with the k-gate; optional Honcho backend for non-group reasoning; pgvector semantic retrieval. | Tier 1/2 | None |
| **5** | Nested institutions: `peer_closure` scaling, `organization_id` linkage, multi-parent permission merge, erasure cascade through closure + provenance. | Tier 2 | None |

## 10. Minors and privacy are load-bearing, not a footnote

Theory-of-mind representations are psychological profiles, and classrooms and homeschool co-ops mean children (COPPA/FERPA/GDPR-for-kids). The model treats this as structural, not advisory:
- Representations **default OFF / opt-in** for minors, enforced as NOT NULL DB defaults (lock #4). No background derivation ("dreaming") for minors ever.
- The minor signal lives **on the peer row** (`treat_as_minor`) and **syncs**, defaulting to the safe value when unknown, because the serverless tier has no `users` row to consult.
- Erasure is **provenance-driven and re-gated**: deleting a child purges its `contributor_peer_id` observations upward, and re-evaluates the k-gate so a sub-k aggregate is deleted rather than left re-identifying.
- **Cross-peer, cross-device erasure:** if adult A's phone holds a theory-of-mind representation of minor B from a co-learning session, B's tombstone must propagate to A on next sync and purge A-about-B observations, not just B's self-observations.

## 11. Risks and open questions

- **Rebuilding the heavy reasoning is multi-quarter.** De-risked by shipping stable Protocols + a non-LLM projection first (real value in Wave 1), growing the engine in waves, and keeping the optional Honcho backend as the escape hatch for server-tier intelligence we choose not to rebuild.
- **On-device structured output** (explicit-fact extraction on a small model) is unproven. Keep on-device to explicit facts with tolerant parsing; defer deduction/induction/contradiction to the server tier. (Note: the on-device LLM is now Qwen3-1.7B / Gemma-class, not Ministral, per the current model stack.)
- **Closure write-amplification** at institutional depth is O(ancestors × descendants); bound with a documented max-depth guard (and accept that the guard also bounds nesting depth, an explicit decision, not an implicit constant).
- **Clean-room taint** is a people-process risk: separate engineers, two-room protocol, audit trail.
- **CRDT correctness** (concurrent membership edits, cross-tier asymmetric derivation) needs property-based tests, not a v1 hack.

## 12. Decisions to ratify

1. **Adopt the clean-room spine + pluggable backend** as the direction (vs forking Honcho as the core).
2. **Accept the seven-table, two-table-split model** and the ten locks as binding for migration 006.
3. **Approve a flag-dark Wave 0** landing in/around the beta window (no beta runtime change).
4. **Confirm timing:** is Wave 0 something you want staged now alongside the beta hardening, or strictly after the security audit and TestFlight ship?
5. **Legal check:** before any Honcho-backed Tier-1/2 deployment (Wave 4+), get OSS counsel to confirm the in-process-vs-service boundary and the App Store/AGPL question.

---

### Appendix: verified-against-code anchors
`feature_flag_keys.py:73,75,111-112` (TEAM_MODE/COMPETITION_SIM, default True) · `database/migrations/` (002-005 present; 006 next) · `database/schema.sql:765,801,818,1025,1062` (organizations recursive tree, memberships, guardians) · `fov_context_api.py:36-45` (`/api/sessions` owned under guarded_routes) · `fov_context/session.py:518,635` (UserSession, one-session-per-user singleton) · `fov_context/session.py:234,445` (FOV sinks) · `audio_ws.py:146,487` (ownership check, broadcast). Honcho source at AGPL-3.0: `src/models.py:130,335,379` (flat peers, composite-name-keyed Collection/Document, pgvector-bound storage); Apache-2.0 SDK is a pure HTTP client.
