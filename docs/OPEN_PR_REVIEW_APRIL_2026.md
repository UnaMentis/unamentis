# Open Pull Request Review, April 2026

**Date:** April 8-9, 2026
**Total Open PRs:** 15 (14 Dependabot + 1 manual fix)
**Branch under review:** main

## Known CI Issue

All PRs show the "Generate & Deploy Architecture Viz" workflow as FAILED. This is a known infrastructure issue: the Cloudflare deploy step requires `CLOUDFLARE_API_TOKEN`, which GitHub does not expose to Dependabot-initiated workflows. PR #100 was intended to fix this but itself has merge conflicts. This failure is **not related to any dependency change**.

---

## Priority: Merge ASAP (Security Fixes)

| PR | Upgrade | Component | CI | CVEs/Advisories |
|----|---------|-----------|-----|-----------------|
| **#102** | Next.js 16.1.6 -> 16.1.7 | Web UI | PASS | **5 CVEs**: HTTP request smuggling (CVE-2026-29057), cross-site websocket (CVE-2026-27977), Server Action from sensitive contexts (CVE-2026-27978), maxPostponedStateSize bypass (CVE-2026-27979), image optimization disk cache (CVE-2026-27980) |
| **#101** | PyJWT 2.10.1 -> 2.12.0 | Management API | PASS | **1 advisory** (GHSA-752w): crit header validation per RFC 7515. Also adds stricter ECDSA curve, key length, and iss type validation. |
| **#93** | React group 19.2.3 -> 19.2.4 | Web UI | PASS | Security hardening: DoS mitigations for Server Actions/Components. Includes @types/react 19.2.7 -> 19.2.14. |

---

## Safe to Merge (All CI Passing)

### Python / Management API

| PR | Upgrade | Notes |
|----|---------|-------|
| **#105** | aiohttp 3.13.3 -> 3.13.4 | Patch bump, bug fixes only |
| **#103** | Pygments 2.19.2 -> 2.20.0 | New/updated lexers, perf improvements (entry point caching), catastrophic backtracking fixes. Dropped Python 3.8 (not a concern). |

### Web UI (server/web)

| PR | Upgrade | Type | Notes |
|----|---------|------|-------|
| **#99** | Prettier 3.7.4 -> 3.8.1 | dev | Formatter, no runtime impact. Adds Angular v21.1 support. |
| **#97** | Tailwind CSS 4.1.18 -> 4.2.1 | dev | New color palettes, logical property utilities. Deprecates `start-*`/`end-*` in favor of `inset-s-*`/`inset-e-*` (no removal yet). |
| **#95** | echarts-for-react 3.0.5 -> 3.0.6 | prod | Patch bump, used by EChartsWrapper component. |

### Rust / USM Core (server/usm-core)

| PR | Upgrade | Notes |
|----|---------|-------|
| **#96** | cbindgen 0.26.0 -> 0.29.2 | Build tool (C header generator). MSRV bump to 1.74. Rust CI passes. |
| **#92** | Tokio 1.49.0 -> 1.50.0 | Minor bump. Bug fixes (AsyncFd, scheduler race conditions). New: `TcpStream::set_zero_linger`, `is_rt_shutdown_err`. |
| **#91** | tower-http 0.5.2 -> 0.6.8 | USM Core uses only CorsLayer + tracing. Some deprecated items removed in 0.6 but none affect this codebase. CI passes. |
| **#90** | notify 6.1.1 -> 8.2.0 | 2 major version jumps. However, notify is barely used: `RecommendedWatcher` is imported as a type but the watcher is always `None`. CI passes. Safe now, will need v8 API when file watching is implemented. |

---

## Needs Investigation

### PR #98: @types/node 20.19.27 -> 25.3.3 (Web UI, dev dependency)

**Issue:** 5 major version jump in Node.js type definitions. CI passes (lint, type check, tests, build all green), but these types may declare APIs that don't exist at runtime.

**Recommendation:** Check the project's actual Node.js runtime version. If running Node 20 LTS, consider pinning `@types/node` to `20.x` and closing this PR. The types should match the runtime to avoid using APIs that compile but fail at runtime.

### PR #100: sysinfo upgrade + Arch Viz CI fix (manual PR)

**Issue:** Has **merge conflicts** (CONFLICTING status). 294 files changed with CodeRabbit requesting changes. Bundles two unrelated fixes:
1. Arch Viz CI fix for Dependabot PRs (adds `dependabot[bot]` actor condition)
2. sysinfo 0.30 -> 0.38 migration (fixes `Process::name()` -> `&OsStr`, replaces `System::global_cpu_info().cpu_usage()` with `System::global_cpu_usage()`)

**Recommendation:** Rebase onto current main, or extract the Arch Viz CI fix into its own clean PR.

### PR #94: sysinfo 0.30.13 -> 0.38.3 (USM Core, Rust)

**Issue:** **Rust CI FAILING.** Major API breakage across 8 minor versions:
- `System::new_all()` and `System::refresh_all()` removed (0.31.0)
- `process.name()` returns `&OsStr` instead of `&str` (0.31.0)
- `System::global_cpu_info()` removed (0.32.0)
- `LoadAvg` moved, `System::load_average()` changed (0.33.0)
- MSRV bumped to Rust 1.88 (0.37.0)

**Affected files:** `monitor/macos.rs`, `monitor/linux.rs`, `metrics/mod.rs`

**Recommendation:** Close this PR. Do the sysinfo migration on a feature branch with the necessary code changes. Note overlap with PR #100.

---

## Recommended Merge Order

1. **Security first:** #102 (Next.js, 5 CVEs) -> #101 (PyJWT, 1 CVE) -> #93 (React security hardening)
2. **Safe patches:** #105 -> #103 -> #95 -> #92 -> #99 -> #97 -> #96 -> #91 -> #90
3. **Investigate:** #98 (pin @types/node to match runtime?)
4. **Resolve manually:** #100 (rebase or split), #94 (close, do migration separately)

---

## Notes

- All "UNKNOWN" mergeable statuses likely need a Dependabot rebase (`@dependabot rebase` comment on the PR)
- PRs #94 and #100 overlap (both address sysinfo), only one should ultimately be merged
- The Arch Viz CI fix from #100 should be extracted and merged independently to unblock the known CI failure on all Dependabot PRs
