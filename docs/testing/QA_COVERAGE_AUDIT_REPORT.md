# QA Test Coverage Audit Report

**Date:** 2026-01-26
**Auditor:** QA Lead (20 years agile experience)
**Scope:** UnaMentis monorepo unit testing coverage

---

## Executive Summary

This audit evaluated test quality, mock compliance with "Real Over Mock" philosophy, and coverage across all components. The primary finding is a **critical coverage gap in the Next.js web client** (4.35% line coverage) while iOS maintains strong compliance (80% threshold enforced).

### Risk Matrix

| Component | Coverage | Mock Compliance | Risk Level |
|-----------|----------|-----------------|------------|
| **Web Client** | 4.35% lines | Needs remediation | **CRITICAL** |
| **Rust USM Core** | Not measured | Compliant | **HIGH** |
| **Python Management** | Branch enabled | 12 files need audit | **MEDIUM** |
| **iOS App** | 80%+ enforced | Exemplary | **LOW** |

---

## 1. Web Client Audit (Next.js)

### 1.1 Coverage Baseline

```
Lines:      4.35%  (CRITICAL - target 70%+)
Statements: 4.35%
Functions:  51.47%
Branches:   66%
```

### 1.2 Test File Inventory (9 files)

| File | Lines | Mock Usage | Compliance |
|------|-------|------------|------------|
| tts-pregen.test.ts | 218 | None | COMPLIANT |
| ui-components.test.tsx | 75 | None | COMPLIANT |
| utils.test.ts | 49 | None | COMPLIANT |
| feature-flags/client.test.ts | 386 | fetch (external) | COMPLIANT |
| batch-job-card.test.tsx | 192 | vi.fn callbacks | COMPLIANT |
| batch-job-api.test.ts | 310 | vi.mock api-client | **QUESTIONABLE** |
| batch-job-items-list.test.tsx | 209 | vi.mock api-client | **QUESTIONABLE** |
| batch-job-create-form.test.tsx | 329 | vi.mock api-client | **QUESTIONABLE** |
| batch-job-panel.test.tsx | 179 | vi.mock api-client | **QUESTIONABLE** |

### 1.3 Mock Compliance Issues

**4 files mock the internal api-client module.** Per "Real Over Mock" philosophy:
- Internal services should NOT be mocked
- The api-client makes HTTP calls to internal Management API

**Recommendation:** Replace `vi.mock('@/lib/api-client')` with MSW (Mock Service Worker) to intercept at the network layer. This tests real api-client code paths while still allowing controlled responses.

### 1.4 Critical Untested Areas

| Area | Files | Risk |
|------|-------|------|
| API Routes | 70 routes | HIGH - user-facing |
| Components | 82 total, 6 tested | HIGH - UI integrity |
| Hooks | 2 files | MEDIUM |
| Core Lib (api-client.ts) | 2390 lines | HIGH - foundation |

**Top 5 Priority Areas for Testing:**
1. API Routes: sessions (10), kb (13), tts (9), curricula (8)
2. api-client.ts - Core HTTP client (0% tested)
3. Dashboard components - User-facing
4. session-state.ts - Critical state management
5. useLatencyData hook - Data transformation

---

## 2. Python Management API Audit

### 2.1 Mock Violation Inventory

**38 test files use mocks. 12 files have potential "Real Over Mock" violations:**

| File | Mock Classes | Severity |
|------|--------------|----------|
| test_tts_api.py | MockTTSCache, MockResourcePool | HIGH |
| test_tts_api_extended.py | MockTTSCache, MockResourcePool | HIGH |
| test_server.py | MockConnection, MockDBPool | HIGH |
| test_server_extended.py | MockConnection, MockDBPool | HIGH |
| test_session_cache_integration.py | MockSessionCache | MEDIUM |
| test_auth_api.py | MockSessionManager | MEDIUM |
| test_deployment_api.py | MockResourcePool | MEDIUM |
| test_fov_context_api.py | MockTTSCache | MEDIUM |
| test_import_api.py | MockResourcePool | MEDIUM |
| test_latency_harness_api_extended.py | MockResourcePool | MEDIUM |
| test_lists_api.py | MockTTSCache | MEDIUM |
| test_audio_ws.py | MockSessionManager | MEDIUM |

### 2.2 Recommended Remediations

**HIGH severity (replace immediately):**
- `MockConnection`/`MockDBPool` -> Use `aiosqlite` with `:memory:` database
- `MockTTSCache` -> Use real TTSCache with `tmp_path` fixture
- `MockResourcePool` -> Use real pool with test configuration

**Pattern for remediation:**
```python
# BEFORE (violation)
@pytest.fixture
def mock_cache():
    return MockTTSCache()

# AFTER (compliant)
@pytest.fixture
async def real_cache(tmp_path):
    cache = TTSCache(cache_dir=tmp_path / "cache")
    await cache.initialize()
    yield cache
    await cache.close()
```

---

## 3. iOS App Audit (Reference Standard)

### 3.1 Compliance Status: EXEMPLARY

The iOS test suite demonstrates best practices:

- **69 test files** organized into Unit/Integration/Watch
- **80% coverage threshold** enforced in CI
- **MockServices.swift** follows "Real Over Mock" perfectly:
  - Only mocks paid APIs (LLM, Embeddings)
  - Faithful mocks with input validation
  - Error condition simulation
  - Realistic latency modeling
  - Metric tracking for assertions

### 3.2 Mock Inventory (Compliant)

| Mock | Reason | Faithful? |
|------|--------|-----------|
| MockLLMService | Anthropic API costs $3-15/M tokens | YES |
| MockEmbeddingService | OpenAI API costs money | YES |
| MockVADService | Test spy for on-device ML | YES (spy pattern) |

**Real implementations used for:**
- TelemetryEngine
- PersistenceController (inMemory: true)
- AudioEngine components
- All Knowledge Bowl services

---

## 4. Rust USM Core Audit

### 4.1 Coverage Status: NOT MEASURED

- 9 modules with inline tests
- 37+ property-based tests using proptest
- Uses tempfile for file system tests
- No coverage measurement in CI

### 4.2 Recommendations

1. Add `cargo-tarpaulin` to CI pipeline
2. Set initial threshold at measured baseline
3. Track coverage trends over time

---

## 5. Prioritized Action Plan

### Phase 1: Immediate (Week 1-2)
- [ ] Increase web coverage threshold: 1% -> 5% -> 15%
- [ ] Add 25 web tests for critical API routes
- [ ] Replace web api-client mocks with MSW

### Phase 2: Foundation (Week 3-4)
- [ ] Add Rust coverage to CI with tarpaulin
- [ ] Audit Python mock violations (12 files)
- [ ] Create remediation tasks for HIGH severity mocks

### Phase 3: Remediation (Week 5-8)
- [ ] Increase web coverage to 50%
- [ ] Replace Python MockConnection/MockDBPool with real in-memory DB
- [ ] Replace Python MockTTSCache/MockResourcePool with real implementations

### Phase 4: Excellence (Week 9-12)
- [ ] Increase web coverage to 70%
- [ ] Complete Python mock remediation
- [ ] Add e2e tests for web client (Playwright)

---

## 6. Coverage Targets

| Component | Current | Phase 1 | Phase 2 | Phase 3 | Target |
|-----------|---------|---------|---------|---------|--------|
| Web Client | 4.35% | 15% | 30% | 50% | **70%+** |
| Python | Branch | Branch | Branch | Branch | **80%+** |
| Rust | Unknown | Measured | Threshold | Maintained | **70%+** |
| iOS | 80%+ | Maintained | Maintained | Maintained | **80%+** |

---

## 7. Key Metrics to Track

1. **Line Coverage** - Primary metric
2. **Branch Coverage** - Ensure conditional logic tested
3. **Mock Count** - Track mocks of internal services (should decrease)
4. **Test/Code Ratio** - Ensure tests keep pace with code growth

---

## Appendix: "Real Over Mock" Quick Reference

### Acceptable Mocks
- Paid external APIs (LLM, STT, TTS, Embeddings)
- APIs requiring unavailable credentials (temporary)
- Unreliable external services with no local alternative

### NOT Acceptable
- Internal services (caches, pools, managers)
- Databases (use in-memory SQLite/Core Data)
- File system (use temp directories)
- Free external APIs
- Local computations

### Faithful Mock Requirements
1. Validate inputs like real API
2. Simulate all error conditions
3. Match realistic timing/latency
4. Track metrics for assertions

---

*Report generated by QA Lead audit of UnaMentis monorepo*
