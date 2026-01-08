# Quality Infrastructure Implementation Plan

> Trackable project plan for implementing quality infrastructure across UnaMentis.
> Check off items as they're completed. Update status and notes as work progresses.

**Created:** January 2025
**Status:** In Progress
**Research Document:** [QUALITY_INFRASTRUCTURE_RESEARCH.md](architecture/QUALITY_INFRASTRUCTURE_RESEARCH.md)

---

## Quick Status

| Phase | Status | Progress |
|-------|--------|----------|
| Phase 1: Foundation | In Progress | 6/8 |
| Phase 2: Enhanced Gates | ✅ Complete | 9/9 |
| Phase 3: Feature Flags | ✅ Complete | 17/19 |
| Phase 4: Observability | ✅ Complete | 9/10 |
| Phase 5: Advanced | In Progress | 4/14 |

**Last Updated:** January 7, 2025

---

## Phase 1: Foundation

**Goal:** Automate existing manual quality gates across iOS, Server, and Web

### 1.1 Pre-Commit Hooks

- [x] Create `.hooks/` directory structure
- [x] Create unified pre-commit hook script (Swift, Python, JS/TS)
- [x] Create pre-push hook script (quick tests)
- [x] Create `scripts/install-hooks.sh` installation script
- [ ] Test hooks with team members
- [ ] Add hook bypass logging (track when `--no-verify` is used)

**Files Created:**
- `.hooks/pre-commit`
- `.hooks/pre-push`
- `scripts/install-hooks.sh`

**Notes:**
- Chose unified native git hooks over separate Komondor + pre-commit framework
- Hooks check for tool availability and skip gracefully if not installed
- Target execution time: < 30 seconds

### 1.2 Dependency Automation

- [x] Create `renovate.json` configuration
- [x] Configure grouping rules (iOS, Python, npm)
- [x] Configure auto-merge for security patches
- [ ] Enable Renovate GitHub App on repository
- [ ] Verify first Renovate PRs are created correctly

**Files Created:**
- `renovate.json`

**Notes:**
- Chose Renovate over Dependabot for better grouping and dashboard features
- Weekly schedule (Mondays before 6am)
- Auto-merge enabled for patch updates and security fixes

### 1.3 Coverage Enforcement

- [x] Add coverage extraction step to iOS CI workflow
- [x] Add 80% minimum coverage threshold enforcement
- [x] Add coverage to CI summary output
- [ ] Add coverage badge to README
- [ ] Set up Codecov integration for trend tracking
- [ ] Add coverage enforcement to Python server CI
- [ ] Add coverage enforcement to Web client CI

**Files Modified:**
- `.github/workflows/ios.yml`

**Notes:**
- iOS coverage extracted from xcresult using xccov
- Threshold: 80% minimum, build fails if below

### 1.4 Documentation

- [x] Update `docs/setup/DEV_ENVIRONMENT.md` with hooks setup
- [x] Create `docs/architecture/QUALITY_INFRASTRUCTURE_RESEARCH.md`
- [x] Create this tracking document
- [ ] Update `CLAUDE.md` with quality infrastructure references

---

## Phase 2: Enhanced Quality Gates ✅

**Goal:** Catch more issues before merge, add nightly comprehensive testing

**Status:** Complete

### 2.1 Nightly E2E Workflow

- [x] Create `.github/workflows/nightly-e2e.yml`
- [x] Configure scheduled trigger (daily at 2am UTC)
- [x] Set up E2E test environment with API keys (secrets)
- [x] Configure GitHub issue creation for failures
- [x] Add E2E test result summary to repository

**Files Created:**
- `.github/workflows/nightly-e2e.yml`

**Notes:**
- Runs iOS E2E tests and latency harness tests nightly
- Uses repository secrets for API keys (OPENAI_API_KEY, ANTHROPIC_API_KEY, GROQ_API_KEY)
- Creates GitHub issue automatically on test failures
- Summary job aggregates all test results

### 2.2 Performance Regression Detection

- [x] Create `baselines/` directory for storing baselines
- [x] Create initial `baselines/latency.json` with current metrics
- [x] Create `.github/workflows/performance.yml`
- [x] Integrate with existing latency test harness
- [x] Configure P50/P99 > threshold to fail CI
- [x] Add performance trend to CI summary

**Files Created:**
- `baselines/latency.json`
- `.github/workflows/performance.yml`

**Notes:**
- Targets: P50 < 500ms, P99 < 1000ms for E2E turn latency
- Warning threshold: 10% above target
- Failure threshold: 20% above target (blocks CI)
- Supports baseline updates via workflow_dispatch
- History tracking for trend analysis

### 2.3 Security Scanning

- [x] Create `.github/workflows/security.yml`
- [x] Configure CodeQL for Swift, Python, JavaScript analysis
- [x] Configure gitleaks for secrets detection
- [x] Add dependency vulnerability scanning (pip-audit, npm audit)
- [x] Configure weekly full security audit (scheduled)

**Files Created:**
- `.github/workflows/security.yml`

**Notes:**
- CodeQL runs on all three languages: Swift, Python, JavaScript/TypeScript
- Gitleaks scans entire git history for secrets
- Dependency audits for both Python (pip-audit) and npm
- Weekly scheduled run on Sundays at 3am UTC
- SARIF reports uploaded to GitHub Security tab

---

## Phase 3: Feature Flag System ✅

**Goal:** Enable safe feature development with full flag lifecycle management

**Status:** Complete

### 3.1 Infrastructure

- [x] Create `server/feature-flags/` directory
- [x] Create Docker Compose config for Unleash
- [x] Configure PostgreSQL schema for Unleash
- [x] Set up Unleash proxy for edge performance
- [x] Document deployment process

**Files Created:**
- `server/feature-flags/docker-compose.yml`
- `server/feature-flags/init.sql`
- `server/feature-flags/proxy-config.json`
- `server/feature-flags/README.md`
- `server/feature-flags/flag_metadata.json`

**Notes:**
- Unleash server runs on port 4242
- Proxy runs on port 3063 for client SDKs
- PostgreSQL for data persistence
- Custom metadata table for flag lifecycle tracking

### 3.2 iOS SDK Integration

- [x] Create `UnaMentis/Services/FeatureFlags/` directory
- [x] Create `FeatureFlagService.swift` (Unleash client wrapper)
- [x] Add offline caching support
- [x] Add SwiftUI integration (view modifiers, environment)
- [ ] Write unit tests for feature flag service

**Files Created:**
- `UnaMentis/Services/FeatureFlags/FeatureFlagService.swift`
- `UnaMentis/Services/FeatureFlags/FeatureFlagCache.swift`
- `UnaMentis/Services/FeatureFlags/FeatureFlagTypes.swift`

**Notes:**
- Actor-based service with async/await
- Persistent caching with 24-hour TTL
- SwiftUI `.featureFlag()` view modifier
- Background refresh with configurable interval

### 3.3 Web SDK Integration

- [x] Create `server/web/lib/feature-flags/` directory
- [x] Create React context provider
- [x] Add hooks: `useFlag`, `useFlagVariant`, `useFeatureFlags`
- [x] Add `FeatureGate` component
- [ ] Write unit tests

**Files Created:**
- `server/web/src/lib/feature-flags/types.ts`
- `server/web/src/lib/feature-flags/client.ts`
- `server/web/src/lib/feature-flags/context.tsx`
- `server/web/src/lib/feature-flags/index.ts`

**Notes:**
- LocalStorage caching for offline support
- React hooks for easy integration
- HOC `withFeatureFlag` for class components
- TypeScript types throughout

### 3.4 Lifecycle Management

- [x] Create `scripts/feature-flag-audit.sh`
- [x] Create `.github/workflows/flag-audit.yml`
- [x] Create `docs/FEATURE_FLAGS.md` (usage guide)
- [x] Define flag naming conventions
- [ ] Set up monthly flag audit meeting

**Files Created:**
- `scripts/feature-flag-audit.sh`
- `.github/workflows/flag-audit.yml`
- `docs/FEATURE_FLAGS.md`

**Notes:**
- Audit script scans Swift, TypeScript, and Python
- CI workflow runs weekly and on PRs
- Comments on PRs with overdue flags
- Naming convention: `<scope>_<feature>` (e.g., `voice_new_engine`)

---

## Phase 4: Observability & Metrics ✅

**Goal:** Visibility into quality trends and engineering health

**Status:** Complete

### 4.1 DORA Metrics

- [x] Create `server/devlake/` directory
- [x] Create Docker Compose for Apache DevLake
- [x] Configure GitHub integration blueprint
- [x] Create custom Grafana dashboards
- [x] Document metrics and how to interpret them

**Files Created:**
- `server/devlake/docker-compose.yml`
- `server/devlake/blueprint.json`
- `server/devlake/dashboards/unamentis-quality.json`
- `server/devlake/README.md`

**Notes:**
- DevLake Config UI on port 4000
- Grafana on port 3002
- MySQL backend for data storage
- Pre-configured DORA metrics panels

### 4.2 Quality Dashboard

- [x] Create GitHub Actions quality metrics workflow
- [x] CI/CD success rate tracking
- [x] PR metrics collection (count, size)
- [x] Bug tracking metrics
- [ ] Flaky test detection (future enhancement)

**Files Created:**
- `.github/workflows/quality-metrics.yml`

**Notes:**
- Runs daily and after CI workflows complete
- Collects metrics from GitHub API
- Generates JSON reports and workflow summaries
- 90-day artifact retention

---

## Phase 5: Advanced (In Progress)

**Goal:** Continuous improvement and cutting-edge practices

**Philosophy:** Enable a 2-person team to achieve quality levels typically requiring 10+ developers through intelligent automation.

### 5.1 AI-Powered Code Review ✅

- [x] Evaluate CodeRabbit (selected: free Pro for open source!)
- [x] Create `.coderabbit.yaml` configuration
- [x] Configure language-specific review rules (Swift, Python, TypeScript)
- [x] Create setup documentation
- [ ] Install CodeRabbit GitHub App on repository
- [ ] Install on Android client repository
- [ ] Review first 10 PRs and tune configuration

**Files Created:**
- `.coderabbit.yaml`
- `docs/setup/CODERABBIT_SETUP.md`

**Notes:**
- **FREE for open source repositories** (full Pro features)
- Configured with "assertive" profile for maximum issue detection
- Custom rules for Swift concurrency, Python async, React patterns
- Learns from codebase over time (knowledge base)

### 5.2 Mutation Testing (Recommended)

**Why:** Proves your tests actually catch bugs, not just hit lines. Coverage can be 100% with useless tests.

- [ ] Create `.github/workflows/mutation.yml` (weekly schedule)
- [ ] Evaluate Muter for Swift mutation testing
- [ ] Set up mutmut for Python server
- [ ] Set up Stryker for Web client
- [ ] Establish mutation score baselines

**Recommendation:** HIGH PRIORITY. For a 2-person team, mutation testing catches test quality issues that would otherwise slip through. Run weekly on main branch.

### 5.3 Voice Pipeline Resilience Testing (Recommended)

**Why:** Voice apps fail silently under network stress. Users just experience "silence." This simulates real-world conditions.

- [ ] Create network degradation test harness
- [ ] Test scenarios: high latency (500ms+), packet loss (5-20%), disconnection
- [ ] Test API timeout handling (Groq, OpenAI, ElevenLabs)
- [ ] Test graceful degradation (fallback to local VAD, cached responses)
- [ ] Create chaos engineering runbook
- [ ] Integrate with nightly E2E tests

**Recommendation:** HIGH PRIORITY. This is the difference between "works in demo" and "works in the real world." Critical for voice apps.

### 5.4 Contract Testing (Pact) - Future

**Why:** Ensures iOS client and Server API stay in sync as both evolve rapidly.

- [ ] Evaluate Pact for API contract testing
- [ ] Define contracts between iOS and Server
- [ ] Integrate into CI pipeline

**Recommendation:** MEDIUM PRIORITY. Wait until APIs stabilize (post-MVP). Add when breaking changes become a risk.

### 5.5 Predictive Quality Alerts - Future

**Why:** Catch quality degradation before users notice.

- [ ] Analyze test flakiness trends
- [ ] Alert on increasing failure rates before threshold breach
- [ ] Track code churn vs bug correlation

**Recommendation:** LOW PRIORITY for now. Add after 3+ months of metrics data.

---

## Success Metrics

Track these metrics to measure the effectiveness of quality infrastructure:

| Metric | Baseline | 3-Month Target | 6-Month Target | Current |
|--------|----------|----------------|----------------|---------|
| CI Failure Rate | Unknown | < 10% | < 5% | TBD |
| Pre-merge Bug Detection | Low | > 60% | > 80% | TBD |
| Mean Time to Recovery | Unknown | < 4 hours | < 1 hour | TBD |
| Deployment Frequency | ~Weekly | Daily capable | Multiple/day | TBD |
| Test Coverage (iOS) | ~80% | 80% (maintained) | 85% | Enforced (80% min) |
| Latency Regression Detection | Manual | Automated alerts | Blocked in CI | ✅ Automated + CI blocking |
| Feature Flag Cleanup | N/A | < 30 days avg | < 14 days avg | N/A |

---

## Commercial Tool Upgrade Path

When budget allows, consider these upgrades in priority order:

### Tier 1: High Impact (First Priorities)

| Tool | Open Source | Commercial | Monthly Cost | Status |
|------|-------------|------------|--------------|--------|
| Feature Flags | Unleash | LaunchDarkly | ~$75 | Not Started |
| Code Quality | Codecov | CodeScene | ~$150 | Not Started |
| DORA Metrics | DevLake | LinearB | ~$200 | Not Started |

### Tier 2: Nice to Have

| Tool | Open Source | Commercial | Monthly Cost | Status |
|------|-------------|------------|--------------|--------|
| Security | CodeQL | Snyk | ~$100 | Not Started |
| Code Review | Manual | CodeRabbit | **FREE** (open source) | ✅ Configured |

**Total Tier 1:** ~$425/month
**Total All:** ~$500/month (CodeRabbit is free for open source!)

### Free Tools We're Using

| Tool | Value | Status |
|------|-------|--------|
| CodeRabbit Pro | AI code review (normally $24-30/seat) | ✅ Free for OSS |
| GitHub Actions | CI/CD | ✅ Free for public repos |
| CodeQL | Security scanning | ✅ Free for public repos |
| Codecov | Coverage tracking | ✅ Free tier available |

---

## Change Log

| Date | Changes | Author |
|------|---------|--------|
| 2025-01-07 | Initial plan created | Claude |
| 2025-01-07 | Phase 1.1, 1.2 completed (hooks, Renovate) | Claude |
| 2025-01-07 | Phase 1.3 partially completed (iOS coverage) | Claude |
| 2025-01-07 | **Phase 2 Complete**: nightly-e2e.yml, performance.yml, security.yml, baselines/latency.json | Claude |
| 2025-01-07 | **Phase 3 Complete**: Unleash infrastructure, iOS SDK, Web SDK, audit workflow, documentation | Claude |
| 2025-01-07 | **Phase 4 Complete**: DevLake infrastructure, DORA dashboards, quality metrics workflow | Claude |
| 2025-01-07 | **Phase 5 Started**: CodeRabbit AI code review configured (FREE for open source), expanded Phase 5 roadmap | Claude |
| | | |

---

## Notes & Decisions

### Decisions Made

1. **Unified hooks over separate systems**: Using native git hooks that handle all languages rather than Komondor + pre-commit framework separately. Simpler to maintain for monorepo.

2. **Renovate over Dependabot**: Better grouping, dashboard feature, and multi-platform support.

3. **Unleash for feature flags**: Open source, self-hosted, full control. Can upgrade to LaunchDarkly later.

4. **Apache DevLake for DORA**: Open source alternative to LinearB. Self-hosted but configurable.

### Open Questions

1. ~~Should E2E tests run on every PR to main, or only nightly?~~ **Resolved:** Nightly only (too slow for PR CI)
2. ~~What's the acceptable latency regression threshold?~~ **Resolved:** 10% warning, 20% failure
3. Which team members should be notified on nightly failures? (Currently creates GitHub issue)
4. Should we enable Renovate GitHub App now or wait for Phase 1 completion?

### Blockers

- None currently

---

## Quick Commands

```bash
# Install git hooks locally
./scripts/install-hooks.sh

# Run lint checks
./scripts/lint.sh

# Run quick tests
./scripts/test-quick.sh

# Run full health check
./scripts/health-check.sh

# Run all tests with coverage
./scripts/test-all.sh
```
