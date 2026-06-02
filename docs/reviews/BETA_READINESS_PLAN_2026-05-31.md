# UnaMentis First-Beta Readiness Plan

**Date:** 2026-05-31
**Scope:** What it takes to run an effective first beta: iOS via TestFlight, alongside a minimal AWS server that serves our own OSS-model inference and curriculum, with privacy-aware client telemetry the server can actually see.
**Basis:** A 5-track investigation (server telemetry audit, iOS telemetry audit, privacy-telemetry design, AWS inference/model/cost research, synthesis), grounded in the code and current 2026 AWS/model data. Companion to `SECURITY_OSS_READINESS_AUDIT_2026-05-30.md`.

---

## 1. Three headline findings

1. **The security criticals are mostly already closed on `feature/pre-beta-updates`.** Verified on-branch: USM Core loopback+token+CORS (B1), Management API default-deny auth middleware (B2), unconditional rate limiting + fail-closed bind (B3), Lambda fail-closed JWT secret (B4), log-server loopback+token (B8), importer SSRF/zip-slip (B5), rate-limiter cold-start (B11). What still blocks a *public* server: **WebSocket auth (B7), denial-of-wallet spend cap, CSP + cookie (B6), and the unwired privacy/consent posture (B9/B10).**

2. **Client telemetry is a no-op in a release TestFlight build today.** A real device pointed at AWS would send the server **nothing**, because of a chain of issues (Section 3). The server *intake* works and parses the right fields, but stores everything **in memory only** (lost on restart, capped at 1000 sessions), has **no error-rate metric**, and the **dashboard silently shows mock data** on any backend error. This directly undercuts the "monitor the beta from the server" goal and must be fixed for the beta to be measurable.

3. **Lambda cannot back this beta; Bedrock + the aiohttp server can.** The AWS Lambda tier's curriculum and metrics handlers are `not_implemented` stubs with no telemetry POST ingest, and Lambda cannot host GPU inference. The realistic shape: serve inference via **Amazon Bedrock (`gpt-oss-20b`, Apache-2.0) per-token** (single-digit $/month at beta scale, zero idle/ops), and front the **proven aiohttp Management API on a small EC2/Fargate host behind HTTPS** for curriculum + telemetry, with a self-hosted-GPU on-ramp for later.

---

## 2. Security: what remains before the server is public

(All from the security audit; these are the items this branch has NOT yet addressed.)

| Item | Why it blocks a public beta | Area |
|------|------------------------------|------|
| **WebSocket auth (B7)** | `audio_ws.py:87-115` trusts a client-supplied `user_id` with no token check, so any learner (possibly a minor) can hijack another's live voice session. The one CRITICAL/HIGH not yet fixed on-branch. | Management API |
| **Denial-of-wallet cap** | No spend ceiling / per-IP quota / circuit breaker anywhere (only an unused `BUDGET_CAP_REACHED` enum). With unauthenticated `/api/metrics` + `/api/logs` intake and paid Bedrock inference, spend is unbounded. | Management API + inference |
| **CSP + cookie (B6)** | No Content-Security-Policy on either Next app; web-client refresh token is in localStorage; pair with KaTeX `trust:false`. Defense-in-depth against curriculum-LaTeX XSS → token theft. | Web apps |
| **Consent + age gate (B9)** | `consent_records`/`privacy_tiers`/`data_retention_policies` exist in schema but registration writes none; no age capture. K-12 audience makes under-13 foreseeable (COPPA/FERPA/GDPR-K). | Privacy |
| **Claims vs reality + telemetry PII (B10)** | Docs claim "no data leaves the device"; telemetry uploads per-session metrics. Stop storing raw client IP on intake; neutralize the iOS IDFV+device-name path; publish real `/privacy` + `/terms` + a Bedrock sub-processor disclosure. | Privacy |

---

## 3. Telemetry: why nothing reaches the server today, and the fix

**The dead chain (iOS, release build → AWS):**
- The production uploader only runs when `selfHostedEnabled && server IP set`, and it reads the **wrong UserDefaults key** (`serverIP` at `SessionManager.swift:425` vs the app-wide `primaryServerIP`), so it never configures and **queues to disk forever**.
- There is **no cloud/HTTPS endpoint** in the client; `MetricsUploadService` hardcodes `http://<ip>:8766` (cleartext → ATS-blocked in release).
- **TTFA (the headline metric) is never transmitted** — it goes only to `os_log` for an external simulator harness.
- The richer per-turn exporter (`MetricsExporter` → `/api/metrics/ingest`) is **test-only** and carries IDFV + device name; the server doesn't implement that route anyway.
- The **AWS Lambda metrics service is a `not_implemented` stub** with only GET routes and no POST ingest.

**The server side:** `POST /api/metrics` intake works and parses session duration, turn/interruption counts, STT/LLM/TTS/E2E median+P99, costs, thermal/network counters. But: **in-memory deques only** (no persistence, restart wipes everything, 1000-snapshot cap), **no error-rate field**, P99 stored but not displayed, and `fetchWithFallback` **silently substitutes mock data** on backend errors (plus dead `app/api/*` proxy routes reading an unset `BACKEND_URL`).

**Good privacy news:** the *production* upload path is already clean — aggregate-only, keyed by a per-install random UUID, no transcripts, no IDFV, no device name. The gaps are the test-only IDFV exporter (ships in the binary), raw-IP storage server-side, and no consent/age gate.

**Telemetry fix (in order):**
- iOS: fix the `serverIP`→`primaryServerIP` key bug; decouple upload from self-hosted mode; add a release cloud HTTPS endpoint; gate upload on **consent**; add a real **TTFA** field and a typed **error-count** field; standardize on the per-install UUID and remove/compile-out the IDFV exporter path.
- Server: deploy the aiohttp intake (not the Lambda stub) behind HTTPS with **allow-list field validation** (drop unknown fields, so "no transcript on the server" is server-enforced); **persist** metrics/logs/clients with retention rollups; add a typed **error-rate** metric and surface P99 + TTFA + error rate in the console; add a **live-vs-mock banner**; drop/coarsen raw IP in public-beta mode.
- Validate in a **release-configuration** build (not the simulator harness), consent granted, confirming real-device metrics land persisted in the dashboard over HTTPS.

---

## 4. AWS inference: recommendation, models, cost

**Recommended start: Amazon Bedrock per-token, `gpt-oss-20b` (Apache-2.0, MoE ~3.6B active, 128K ctx) as the single default for both tiers**, differentiated by system prompt/decoding (warmer/simpler for middle/high-school; more rigorous for graduate). Add `gpt-oss-120b` (Apache-2.0) as the graduate upgrade when real graduate traffic appears.

Why: at tens-of-bursty-users it is **single-to-low-double-digit dollars/month with zero idle spend, zero GPU ops, no cold start**, and Apache-2.0 keeps the license clean for a minor-serving beta. One OpenAI-compatible surface lets you A/B models without renting GPUs.

**Model candidates (all checked for self-host license):**

| Tier | Model | License | Notes |
|------|-------|---------|-------|
| School | **Qwen3-4B-Instruct** | Apache-2.0 (cleanest) | Friendly, fast, multilingual; successor to the Qwen2.5 you already run |
| School | Phi-4-mini (3.8B) | MIT | Stronger reasoning/math for size; good for SAT/Knowledge-Bowl Q&A |
| School | Llama 3.2 3B | Llama Community (700M-MAU + AUP) | Zero-friction continuity (already in Ollama lineup), but flag field-of-use terms |
| Graduate | **gpt-oss-20b** | Apache-2.0 | MoE: near-o3-mini reasoning at small-model cost; Bedrock or self-host |
| Graduate | Qwen3-32B | Apache-2.0 | Single-GPU (L40S INT4) self-host; direct continuity with Qwen2.5:32B |
| Graduate | Llama 3.3 70B (INT4) | Llama Community | Top open-weight quality; accept community-license terms or stay Apache-only |

**Cost shapes (us-east-1, May 2026; Spot ~60-70% cheaper):**
- **Bedrock per-token (recommended):** gpt-oss-20b ~$0.03/1M in + $0.14/1M out → a 40-turn voice session is well under 1 cent; ~50 users × 5 sessions/wk ≈ a **few $/month**. gpt-oss-120b stays in low tens of $/month.
- **Always-on GPU (self-host on-ramp):** school tier g6.xlarge (L4 24GB) ~$0.805/hr (~$588/mo 24×7); graduate tier g6e.xlarge (L40S 48GB) ~$1.861/hr (~$1,359/mo). Use school-hours start/stop to cut idle.
- Avoid **TGI** (maintenance mode since Dec 2025) and **Inferentia2** (defer); SageMaker scale-to-zero is a poor fit for live voice (2-5 min cold start). For self-host, **vLLM** is the default, **SGLang** the TTFA optimizer later, **Ollama** the easiest on-ramp.

**Privacy tradeoff:** Bedrock means transcripts traverse a managed third party → needs a sub-processor disclosure (B10). Self-hosting on your own GPU keeps transcripts in-house. Keep the self-host path ready for data-residency or volume.

---

## 5. AWS deploy shape (minimal beta)

- **Inference plane:** Amazon Bedrock (`gpt-oss-20b`) behind our own auth'd, default-deny endpoint with a hard daily-cost cap + per-IP quota; no raw-transcript logging; sub-processor disclosure published.
- **Data plane (curriculum + telemetry):** the hardened **aiohttp Management API** on a small EC2 (e.g. `t4g.small/medium`) or Fargate container, behind an **ALB/CloudFront for TLS**, with **RDS Postgres (or EBS SQLite)** for telemetry persistence. Curriculum (UMCF) static assets via **S3 + CloudFront**. Reuses the strong auth primitives already on this branch.
- **Do NOT** put this beta on the Lambda tier (stub handlers, no telemetry ingest, `DefaultAuthorizer: NONE`, can't host GPU). Park or clearly mark the Lambda data-plane stubs.
- **Envelope:** TLS everywhere; `AUTH_SECRET_KEY`/`JWT_SECRET`/`BETA_TOKENS` from Secrets Manager; security groups locked to the ALB; USM Core + log server never publicly exposed.

---

## 6. Sequencing

- **Phase 0 (verify):** run `/validate` + tests to confirm the on-branch hardening (B1/B2/B3/B4/B5/B8/B11) is green; add regression tests pinning them; lock the AWS data-plane + inference vehicle decisions.
- **Phase 1 (close public blockers):** WebSocket auth (B7); denial-of-wallet cap; CSP + KaTeX `trust:false` + cookie (B6); consent + age gate (B9); privacy reconciliation incl. raw-IP + IDFV + `/privacy`+`/terms` + sub-processor disclosure (B10).
- **Phase 2 (telemetry end-to-end):** iOS upload fixes (key bug, cloud URL, consent gate, TTFA + error fields, single identifier); server persistence + error-rate + P99/TTFA surfacing + allow-list validation + live-vs-mock banner.
- **Phase 3 (stand up minimal AWS beta + validate):** deploy aiohttp on EC2/Fargate behind HTTPS with persistence; enable Bedrock behind the capped endpoint; release-build TestFlight run verifying real-device telemetry lands in the dashboard.
- **Phase 4 (defer):** self-hosted GPU on-ramp if needed; audit Section 5 mediums + Section 9 follow-ups; real retention/anonymization job; retire or finish the Lambda tier.

---

## 7. Open decisions (need your input)

1. **Minors in scope?** 13+/18+ self-attestation with under-13 documented out-of-scope (lowest-risk for a first beta) vs building verifiable parental consent now. Drives the Phase-1 consent scope.
2. **Inference approach:** approve Bedrock `gpt-oss-20b` to start (recommended) vs self-hosted GPU from day one for data residency.
3. **Budget ceiling:** the hard daily-cost cap value for the circuit breaker, and whether to keep a self-host GPU warm (~$588-$1,359/mo).
4. **Data-plane vehicle:** approve fronting the aiohttp Management API on EC2/Fargate and parking the Lambda stubs for the beta.
5. **Region:** us-east-1 (pricing basis, broadest Bedrock availability) vs other; verify gpt-oss availability + GPU pricing at deploy.
6. **Telemetry store:** SQLite-on-EBS (cheapest) vs RDS Postgres (matches the consent/retention schema).
7. **Privacy/terms authoring:** who writes the real `/privacy` + `/terms` + sub-processor list (a launch gate).
