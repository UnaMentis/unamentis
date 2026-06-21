# Beta Execution Plan

**Date:** 2026-06-10
**Goal:** Close everything that stands between the current state and a measurable, secure, honest TestFlight beta, across this repo and `unamentis-ios`.
**Basis:** `docs/reviews/SECURITY_OSS_READINESS_AUDIT_2026-05-30.md`, `docs/reviews/BETA_READINESS_PLAN_2026-05-31.md`, the iOS repo's `PRE_BETA_AUDIT.md` (2026-05-30), and a fresh verification pass against the current working trees (2026-06-10, since uncommitted work has already addressed some findings).
**Method:** Each task below carries a status and a verification method. Detailed change-by-change records live in `EXECUTION_LOG_2026-06-10.md` alongside this file. Nothing is committed; all changes await human review in the working trees.

Status legend: `[ ]` pending · `[~]` in progress · `[x]` done and verified · `[!]` blocked or needs a human decision · `[-]` dropped (with reason)

---

## Workstream 0: Website confidentiality and policy pages (added after verification)

| # | Task | Status | Verification |
|---|------|--------|--------------|
| 0.1 | Remove internal strategy/fundraising markdown from the publicly served website repo (live at unlinked URLs) | [x] | 21 files moved to private space; 20 tracked deletions staged in /Users/ramerman/dev/unamentis.org; goes live on next push (MORNING ACTION #1) |
| 0.2 | privacy.html + terms.html on unamentis.org (required for TestFlight) with footer links on every page | [x] | Pages created (v1.0, effective 2026-06-10), footer links on all 12 chrome pages, parse + link checks pass; live after the morning push |

## Workstream 1: Server security and privacy (beta blockers)

Verification (2026-06-10 ~23:05) found B7 WebSocket auth, the rate-limiter cold-start bug, and the refresh-token cookie migration already fixed on this branch.

| # | Task | Status | Verification |
|---|------|--------|--------------|
| 1.1 | Consent completion (B9): registration writes consent_records (age, terms, privacy, versioned), sets age_verified_at; explicit policy-acceptance checkbox in register form | [x] | 9 new auth tests + 48/48 web-client auth tests; live probe confirms enforcement. MORNING ACTION: apply migrations/005 via psql |
| 1.2 | Privacy reconciliation (B10): auth-path disclosure + 90-day retention sweep for auth audit IPs | [x] | 12 new tests; sweep verified live on real PostgreSQL (scrubbed 7+2 rows at startup) |
| 1.3 | Privacy artifacts: web-client /privacy and /terms, website privacy.html/terms.html, sub-processor disclosure linked | [x] | All exist; website pages live after morning push |
| 1.4 | CSP: reporting endpoints + feature-flag origin + enforcing header shipped alongside report-only on both apps | [x] | Live header checks on both running apps; 14 new route tests; also fixed a pre-existing next-build blocker found en route |
| 1.5 | Denial-of-wallet residuals: durable daily spend ceiling (default 200 mints/day) + per-IP quota, restart-surviving | [x] | 8 new tests; budget endpoints in management API |
| 1.6 | USM Core crash supervision loop (restart policy, crash-loop breaker) | [!] | Deferred tonight: large Rust change ranked post-beta by the 2026-05-31 plan, and services.toml carries uncommitted user edits. Morning decision. |
| 1.7 | (Discovered) Redact WS ?token= from access logs | [x] | RedactingAccessLogger; tests pass within the 3,013-test suite run |

## Workstream 2: Telemetry end-to-end (the beta must be measurable)

| # | Task | Status | Verification |
|---|------|--------|--------------|
| 2.1 | Server: persist metrics/logs/clients (SQLite) instead of in-memory deques; survive restart | [x] | telemetry_store.py; 13 store tests; dedupe and counters rehydrate on startup |
| 2.2 | Server: typed error-count/error-rate metric in intake and API | [x] | 27 intake tests; aggregates expose error rate and per-stage counts |
| 2.3 | Server: allow-list field validation plus byte caps (64KB body cap, byte-aware cache) | [x] | tests within the 3,013 suite; unknown fields dropped, never stored or re-broadcast |
| 2.4 | Console: P99/TTFA/error display, live-vs-mock banner, auth token support, dead routes removed, session counts deduped | [x] | 29 new vitest tests; build + typecheck clean |
| 2.5 | iOS: dead config keys fixed (uploader, curriculum prefetch, Chatterbox); upload decoupled from self-hosted mode | [x] | 13/13 targeted tests; grep confirms no dead-key reads remain |
| 2.6 | iOS: HTTPS-capable metrics endpoint configuration (telemetryEndpointURL precedence) | [x] | 6 URL-resolution tests |
| 2.7 | iOS: TTFA median/p99 and typed per-stage error counts in the metrics payload | [x] | 4 tests; keys match the server allow-list (ttfaMedian/ttfaP99/error_count/errors_by_stage) |
| 2.8 | iOS: consent-gated uploads; IDFV exporter compiled out of release | [x] | Call-path traced end to end; Release symbol check shows 0 IDFV references; live: consent timer queued metrics during the demo |

## Workstream 3: iOS TestFlight blockers

| # | Task | Status | Verification |
|---|------|--------|--------------|
| 3.1 | Add LICENSE (MIT) to the iOS repo; fix README license link | [x] | Already fixed before tonight (verification confirmed) |
| 3.2 | Draft privacy policy + terms content ready for publication (App Store requires a hosted URL) | [~] | website agent (0.2) |
| 3.3 | Privacy manifest accuracy: DiskSpace already declared; add missing SystemBootTime reason | [~] | API usage audit |
| 3.4 | Declare ITSAppUsesNonExemptEncryption | [x] | Already fixed before tonight |
| 3.5 | Reword speech/microphone usage descriptions to match real use | [x] | Already fixed before tonight |
| 3.6 | Core Data file protection for transcripts at rest | [x] | Already fixed before tonight |
| 3.7 | Demote/redact transcript logging in release builds (finish the remaining sites) | [~] | log site audit |
| 3.8 | Silent barge-in PCM playback bug (and KB drill/rebound views) | [x] | Superseded/fixed by the in-flight BargeInCoordinator work (verification confirmed) |
| 3.9 | APIKeyManager plaintext UserDefaults fallback gated to DEBUG | [x] | Already fixed before tonight |
| 3.10 | Pin SwiftReadability to a revision; ensure Package.resolved is tracked | [~] | build reproducibility |
| 3.11 | (Discovered) Beta consent + 13+ age gate in iOS onboarding (the app has no auth integration, so the server-side gate alone cannot cover TestFlight); revocable in Settings | [~] | build + UI flow |

## Workstream 4: Documentation alignment (claims match reality, repos in sync)

| # | Task | Status | Verification |
|---|------|--------|--------------|
| 4.1 | Server README: fix badges, broken links, stale monorepo/iOS content, Quick Start | [ ] | link check |
| 4.2 | Remove stale machine-generated architecture.json; fix CODEOWNERS stale paths | [ ] | repo check |
| 4.3 | Wording sweep: platform is a learning platform, not "a tutor" (tutoring is one capability) | [ ] | grep sweep |
| 4.4 | Honest status claims: importers, coverage gates, mutation testing, Lambda tier | [ ] | doc review |
| 4.5 | Provider counts consistent everywhere | [ ] | grep sweep |
| 4.6 | LICENSE/TRADEMARK split so GitHub detects MIT | [ ] | license file check |
| 4.7 | New docs/STATUS.md: ruthlessly honest "what works today" page | [ ] | written |
| 4.8 | iOS README + docs: Xcode version, simulator naming (iPhone 17 Pro), broken links, moved-doc pointers | [ ] | link check |
| 4.9 | PROJECT_OVERVIEW.md refreshed to match post-fix reality (mandatory per repo policy) | [ ] | doc review |
| 4.10 | TASK_STATUS.md updated with tonight's completed work | [ ] | doc review |

## Workstream 5: On-device LLM (the challenge)

| # | Task | Status | Verification |
|---|------|--------|--------------|
| 5.1 | Recover the existing on-device model research/plan from the repos; pick tonight's path | [x] | docs/ios/ON_DEVICE_LLM_AUDIT_2026-05.md recommends MLX/Qwen3 post-beta; tonight's path is the existing llama.cpp code plus the official b7263 xcframework (pre-verified: simulator slice, all 21 required symbols) and the already-on-disk Ministral-3-3B GGUF (verified via GGUF metadata). Gemma 3 4B GGUF confirmed compatible with the same path; deferred pending a chat-template branch. |
| 5.2 | Enable the on-device LLM compile path in production builds (project.yml) | [x] | llama.cpp b7263 xcframework embedded; LLAMA_AVAILABLE in Debug AND Release; OnDeviceLLMService un-excluded; 2.0GB dead bundle resource removed; batch-overflow + stop-sequence fixes; BUILD SUCCEEDED |
| 5.3 | Working on-device generation verified in the iOS Simulator (real tokens from a real local model) | [x] | Ministral-3-3B answered two questions; "LLM service type: OnDeviceLLMService" logged with model path; 4.36GB process RSS; [INST] template bleed proves raw in-process llama.cpp; screenshots captured |
| 5.4 | Document the result: model used, latency observed, how to reproduce, what remains for device | [~] | Execution log section written; dated note in the iOS repo assigned to the docs lane |

## Workstream 6: Validation and handoff

| # | Task | Status | Verification |
|---|------|--------|--------------|
| 6.1 | Server /validate passes (lint + tests) | [ ] | validate output |
| 6.2 | iOS lint + quick tests pass (scripts/health-check.sh or test-quick.sh) | [ ] | script output |
| 6.3 | Execution log complete: every change recorded with files and verification | [ ] | log review |
| 6.4 | Morning summary with decisions-needed list | [ ] | delivered |

## Decisions that stay human (not done tonight)

- Making the `unamentis-ios` repo public (it currently is not; everything tonight prepares for it).
- Publishing privacy/terms pages to the live website (drafts will be ready).
- Any git history rewrite on the public repo.
- Committing and pushing any of tonight's changes.
