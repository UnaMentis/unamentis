# Code Quality Initiative

> How a small team achieves enterprise-grade quality through intelligent automation

**Document Purpose:** This comprehensive document details UnaMentis's systematic approach to code quality, performance validation, and engineering excellence. It serves as the source material for website content, conference presentations, and stakeholder communications.

---

## Executive Summary

UnaMentis implements a **5-phase Code Quality Initiative** that enables a small development team to achieve quality standards typically requiring 10+ engineers. Through intelligent automation, AI-assisted code review, and data-driven metrics, the project maintains enterprise-grade quality while moving at startup velocity.

### Key Achievements

| Capability | Status | Impact |
|------------|--------|--------|
| Pre-commit quality gates | Implemented | Issues caught before commit |
| Hook bypass auditing | Implemented | Detect `--no-verify` usage |
| Automated dependency management | Implemented | Zero manual dependency tracking |
| 80% code coverage enforcement | Implemented | CI fails below threshold |
| Performance regression detection | Implemented | Automated latency monitoring |
| Security scanning | Implemented | Secrets, CodeQL, dependency audits |
| Feature flag lifecycle management | Implemented | Safe rollouts with cleanup tracking |
| DORA metrics and observability | Implemented | Engineering health visibility |
| AI-powered code review | Implemented | Every PR reviewed by CodeRabbit |
| Mutation testing | Implemented | Weekly test quality validation |
| Chaos engineering | Implemented | Voice pipeline resilience testing |

### Philosophy

Quality isn't a phase. It's woven into every stage of development:

1. **Shift Left**: Catch issues at commit time, not in production
2. **Automate Everything**: Humans shouldn't do what machines can do better
3. **Measure Continuously**: You can't improve what you don't measure
4. **Safe Experimentation**: Feature flags enable risk-free innovation
5. **Learn from Data**: DORA metrics guide engineering decisions

---

## The 5-Phase Implementation

### Phase 1: Foundation

**Goal:** Automate existing manual quality gates across iOS, Server, and Web components.

#### Pre-Commit Hooks

A unified hook system that runs automatically before every commit:

```
.hooks/
├── pre-commit     # Linting and formatting checks
└── pre-push       # Quick test validation
```

**Pre-Commit Checks:**
- **Swift**: SwiftLint (strict mode), SwiftFormat validation
- **Python**: Ruff linting and format checking
- **JavaScript/TypeScript**: ESLint, Prettier
- **Secrets**: Gitleaks detection across all files

**Characteristics:**
- Execution target: < 30 seconds
- Graceful degradation if tools not installed
- Bypass logging for audit purposes
- Single installation: `./scripts/install-hooks.sh`

#### Dependency Automation (Renovate)

Automated dependency management that eliminates manual tracking:

| Feature | Configuration |
|---------|--------------|
| Schedule | Mondays before 6am |
| Grouping | iOS, Python, npm dependencies grouped separately |
| Auto-merge | Security patches, patch updates, dev dependencies |
| Manual review | Major version updates, breaking changes |
| Lock file maintenance | Monthly cleanup |

**Why Renovate over Dependabot:**
- Superior grouping capabilities for monorepo
- Dependency dashboard for visibility
- More granular auto-merge rules
- Better semantic commit integration

#### Coverage Enforcement

Code coverage is not a suggestion. It's a gate:

| Metric | Threshold | Enforcement |
|--------|-----------|-------------|
| iOS Coverage | 80% minimum | CI fails if below |
| Coverage extraction | xccov from xcresult | Automated |
| Display | CI summary output | Always visible |

```yaml
# From .github/workflows/ios.yml
- name: Check Coverage
  run: |
    COVERAGE=$(xcrun xccov view --report *.xcresult --json | jq '.targets[].lineCoverage')
    if (( $(echo "$COVERAGE < 0.80" | bc -l) )); then
      echo "Coverage $COVERAGE is below 80% threshold"
      exit 1
    fi
```

---

### Phase 2: Enhanced Quality Gates

**Goal:** Catch more issues before merge with automated nightly testing and performance regression detection.

#### Nightly E2E Testing

Comprehensive end-to-end testing runs every night at 2am UTC:

**Components Tested:**
- iOS E2E tests with real API keys (from secrets)
- Latency regression tests using `provider_comparison` suite
- Full voice pipeline validation

**Failure Handling:**
- Automatic GitHub issue creation with "nightly-failure" label
- Comprehensive result summaries in workflow
- Test artifact retention: 14 days (E2E), 30 days (latency)

#### Performance Regression Detection

Voice applications live and die by latency. Performance regression detection ensures we never ship a slower release:

**Target Metrics:**

| Metric | P50 Target | P99 Target |
|--------|-----------|-----------|
| E2E Turn Latency | 500ms | 1000ms |
| STT Latency | 100ms | 200ms |
| LLM Time to First Token | 200ms | 400ms |
| TTS Latency | 100ms | 200ms |

**Regression Thresholds:**
- Warning: 10% above target
- Failure: 20% above target (blocks CI)
- Improvement: 10% below baseline (notable)

**Baseline Management:**
```bash
# Create baseline from successful run
curl -X POST http://localhost:8766/api/latency-tests/baselines \
  -d '{"runId": "run_xxx", "name": "v1.0 baseline", "setActive": true}'

# Check new run against baseline
curl -s "http://localhost:8766/api/latency-tests/baselines/{id}/check?runId=run_yyy"
```

#### Security Scanning

Multi-layered security scanning catches vulnerabilities before they reach production:

**Scanning Components:**

| Scanner | Purpose | Schedule |
|---------|---------|----------|
| Gitleaks | Secrets detection (full git history) | Every PR + weekly |
| CodeQL | Static analysis (Swift, Python, JavaScript) | Every PR + weekly |
| pip-audit | Python dependency vulnerabilities | Every PR + weekly |
| npm audit | JavaScript dependency vulnerabilities | Every PR + weekly |

**Output:**
- SARIF reports uploaded to GitHub Security tab
- Automated PR comments for findings
- Weekly full audit on Sundays at 3am UTC

---

### Phase 3: Feature Flag System

**Goal:** Enable safe feature development with full flag lifecycle management.

#### Infrastructure (Unleash)

Self-hosted feature flag system with enterprise capabilities:

```
server/feature-flags/
├── docker-compose.yml    # Full stack deployment
├── init.sql              # PostgreSQL schema
├── proxy-config.json     # Edge proxy configuration
├── flag_metadata.json    # Lifecycle tracking
└── README.md             # Documentation
```

**Architecture:**
- Unleash Server: Port 4242
- Unleash Proxy: Port 3063 (for client SDKs)
- PostgreSQL: Data persistence
- Custom metadata table for lifecycle tracking

#### SDK Integration

**iOS (Swift):**
```swift
// Actor-based service with async/await
@Observable
class FeatureFlagService {
    func isEnabled(_ flag: String) async -> Bool
    func getVariant(_ flag: String) async -> String?
}

// SwiftUI integration
Text("New Feature")
    .featureFlag("voice_new_engine")
```

**Web (React):**
```typescript
// Hooks-based API
const isEnabled = useFlag('voice_new_engine');
const variant = useFlagVariant('onboarding_flow');

// Component wrapper
<FeatureGate flag="voice_new_engine">
  <NewVoiceEngine />
</FeatureGate>
```

#### Lifecycle Management

Feature flags have a lifecycle. Forgotten flags become technical debt:

**Audit Automation:**
```bash
# Scan codebase for flag usage
./scripts/feature-flag-audit.sh

# CI workflow runs weekly + on PRs
# Creates issues for overdue flags
# Comments on PRs with flag changes
```

**Metadata Tracking:**
```json
{
  "voice_new_engine": {
    "owner": "audio-team",
    "created": "2025-01-01",
    "targetRemoval": "2025-03-01",
    "permanent": false,
    "purpose": "New voice processing pipeline"
  }
}
```

**Naming Convention:** `<scope>_<feature>` (e.g., `voice_new_engine`, `onboarding_v2`)

---

### Phase 4: Observability & Metrics

**Goal:** Visibility into quality trends and engineering health through DORA metrics and dashboards.

#### DORA Metrics (Apache DevLake)

The four key metrics that elite engineering teams track:

| Metric | What It Measures | Elite Target |
|--------|-----------------|--------------|
| Deployment Frequency | How often code ships | Multiple per day |
| Lead Time for Changes | Commit to production | Less than 1 hour |
| Change Failure Rate | Deployments causing failures | 0-15% |
| Mean Time to Recovery | Incident to resolution | Less than 1 hour |

**Infrastructure:**
```
server/devlake/
├── docker-compose.yml              # DevLake + Grafana + MySQL
├── blueprint.json                  # GitHub integration config
├── dashboards/unamentis-quality.json  # Custom dashboard
└── README.md                       # Setup guide
```

**Access Points:**
- Config UI: http://localhost:4000
- Grafana Dashboards: http://localhost:3002
- DevLake API: http://localhost:8080

#### Quality Dashboard

Daily automated metrics collection:

**Metrics Collected:**
- CI/CD success rates (iOS, Server, Web)
- Pull request metrics (count, average size)
- Bug metrics (open, closed in 30 days)
- Workflow run statistics

**Output:**
- JSON reports in `metrics/` directory
- GitHub workflow summary tables
- 90-day artifact retention
- Trend analysis over time

---

### Phase 5: Advanced Practices

**Goal:** Continuous improvement through AI assistance and cutting-edge testing practices.

#### AI-Powered Code Review (CodeRabbit)

Every pull request receives an automated AI review:

**Configuration Highlights:**
```yaml
# .coderabbit.yaml
reviews:
  profile: assertive           # Maximum issue detection
  request_changes_workflow: true  # Auto-request changes on high severity
  sequence_diagrams: true      # Visual architecture documentation

path_instructions:
  - path: "**/*.swift"
    instructions: |
      Review for Swift 6.0 concurrency safety. Check for:
      - Actor isolation violations
      - Sendable conformance issues
      - Data races in async code
      - Memory leaks and retain cycles
```

**Language-Specific Reviews:**
- **Swift**: Concurrency safety, Sendable, data races, memory leaks, force unwraps
- **Python**: Async/await usage, exception handling, type hints, security
- **TypeScript/React**: Hook dependencies, server/client boundaries, accessibility
- **CI/CD**: Action pinning, permissions, secrets, caching

**Cost:** FREE for open source projects (normally $24-30/seat/month)

#### Mutation Testing (Implemented)

Mutation testing proves tests catch bugs, not just hit lines:

**Weekly Workflow:** `.github/workflows/mutation.yml` runs every Sunday at 4am UTC

**Tools by Platform:**
| Platform | Tool | Workflow |
|----------|------|----------|
| Python | mutmut | Automated in CI |
| Web | Stryker | Automated in CI |
| iOS | Muter | Manual trigger |

**Configuration:**
```yaml
# From .github/workflows/mutation.yml
schedule:
  - cron: '0 4 * * 0'  # Sunday 4am UTC
```

**Metrics:**
- Mutation score target: >70%
- Results uploaded as artifacts (30-day retention)
- Trend analysis over time

#### Chaos Engineering (Implemented)

Voice pipeline resilience testing validates graceful degradation. See [CHAOS_ENGINEERING_RUNBOOK.md](testing/CHAOS_ENGINEERING_RUNBOOK.md).

**Test Scenarios:**
| Category | Scenarios |
|----------|-----------|
| Network | High latency (500ms+), packet loss (5-20%), disconnection |
| API | Provider timeouts, rate limiting, partial responses |
| Resources | Memory pressure, thermal throttling, battery constraints |
| Partial Failures | STT timeout with TTS working, mixed provider failures |

**Tools:**
- Network Link Conditioner (macOS/iOS)
- Charles Proxy for API mocking
- XCTest with custom conditions
- Automated test scripts

#### Contract Testing (Planned)

- Ensures iOS client and Server API stay in sync
- Tool: Pact
- Deferred until APIs stabilize

---

## Performance Testing Infrastructure

### Latency Test Harness

A comprehensive framework for validating voice pipeline performance:

#### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Latency Test Architecture                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐        ┌──────────────┐        ┌────────────┐ │
│  │ CLI Client   │ ──────►│ Orchestrator │◄──────►│ iOS Client │ │
│  └──────────────┘        └──────┬───────┘        └────────────┘ │
│                                 │                               │
│                    ┌────────────┼────────────┐                  │
│                    ▼            ▼            ▼                  │
│             ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│             │ Storage  │ │ Analyzer │ │ REST API │              │
│             └──────────┘ └──────────┘ └──────────┘              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Server CLI | `server/latency_harness/` | Test orchestration, analysis, storage |
| iOS Harness | `UnaMentis/Testing/LatencyHarness/` | High-precision iOS test execution |
| Web Dashboard | Operations Console | Real-time monitoring |
| REST API | Management API (port 8766) | Programmatic access |

#### Test Suites

| Suite | Tests | Duration | Use Case |
|-------|-------|----------|----------|
| `quick_validation` | ~30 | ~2 min | CI/CD, quick checks |
| `provider_comparison` | ~200+ | ~30 min | Full provider analysis |

#### High-Precision Timing

- iOS uses `mach_absolute_time()` for nanosecond precision
- Fire-and-forget result reporting eliminates observer effect
- Resource monitoring (CPU, memory, thermal) during tests
- Network projections for localhost, WiFi, cellular scenarios

#### CLI Usage

```bash
# List available test suites
python -m latency_harness.cli --list-suites

# Quick validation with mocks
python -m latency_harness.cli --suite quick_validation --mock

# Real provider testing
python -m latency_harness.cli --suite quick_validation --no-mock

# Full provider comparison
python -m latency_harness.cli --suite provider_comparison --no-mock

# CI mode with regression detection
python -m latency_harness.cli \
  --suite quick_validation \
  --ci \
  --baseline prod_baseline \
  --fail-on-regression
```

#### API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/latency-tests/suites` | GET | List test suites |
| `/api/latency-tests/runs` | POST | Start test run |
| `/api/latency-tests/runs/{id}` | GET | Get run status |
| `/api/latency-tests/runs/{id}/analysis` | GET | Get analysis report |
| `/api/latency-tests/baselines` | GET/POST | Manage performance baselines |

---

## GitHub Actions Workflows

Complete CI/CD automation through GitHub Actions:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **iOS CI** | Push/PR to main/develop | Build, lint, unit tests, coverage |
| **Server CI** | Push/PR to server/* | Importer, management, latency tests |
| **Web Client CI** | Push/PR to server/web/** | Lint, typecheck, tests, build |
| **Quality Metrics** | Daily + after CI | Collect CI/PR/bug metrics |
| **Performance** | Push/PR/scheduled | Latency regression detection |
| **Security** | Push/PR/scheduled | Secrets, CodeQL, dependency audit |
| **Nightly E2E** | Daily at 2am | iOS E2E + latency tests |
| **Documentation** | Push/PR to docs/** | Validate markdown/YAML/JSON |
| **Feature Flags** | Weekly + PRs | Audit for stale flags |

### Workflow Permissions

All workflows follow least-privilege principles:

```yaml
permissions:
  contents: read
  security-events: write  # Only for security workflows
  issues: write           # Only for nightly failure reporting
```

---

## Quality Gates Summary

| Gate | Threshold | Enforcement Point |
|------|-----------|-------------------|
| Code Coverage | 80% minimum | CI (iOS build fails) |
| Latency P50 | 500ms | CI (warns at +10%, fails at +20%) |
| Latency P99 | 1000ms | CI (warns at +10%, fails at +20%) |
| SwiftLint | Zero violations (strict) | Pre-commit hook |
| Ruff (Python) | Zero violations | Pre-commit hook |
| ESLint/Prettier | Zero violations | Pre-commit hook |
| Secrets Detection | Zero findings | Pre-commit + CI |
| Feature Flags | 90 days max age | Weekly audit |
| Security Vulnerabilities | Zero critical/high | Security workflow |

---

## Success Metrics & Targets

| Metric | Current | 3-Month Target | 6-Month Target |
|--------|---------|----------------|----------------|
| CI Failure Rate | TBD | < 10% | < 5% |
| Pre-merge Bug Detection | Low | > 60% | > 80% |
| Mean Time to Recovery | TBD | < 4 hours | < 1 hour |
| Deployment Frequency | ~Weekly | Daily capable | Multiple/day |
| Test Coverage (iOS) | 80% (enforced) | 80% maintained | 85% |
| Latency Regression Detection | Automated | Automated + CI blocking | Predictive alerts |
| Feature Flag Cleanup | N/A | < 30 days avg | < 14 days avg |

---

## Tool Selection Rationale

### Why These Tools?

| Tool | Alternative Considered | Selection Rationale |
|------|----------------------|---------------------|
| **Renovate** | Dependabot | Better grouping, dashboard, monorepo support |
| **Unleash** | LaunchDarkly | Open source, self-hosted, full control |
| **DevLake** | LinearB | Open source, configurable, zero cost |
| **CodeRabbit** | Codacy, SonarQube | FREE for OSS, AI-powered, language-specific |
| **SwiftLint** | SwiftFormat alone | Comprehensive linting + style enforcement |
| **Ruff** | Black + Flake8 | All-in-one, faster, modern |

### Commercial Upgrade Path

When budget allows, consider these upgrades in priority order:

| Tool | Open Source | Commercial | Monthly Cost |
|------|-------------|------------|--------------|
| Feature Flags | Unleash | LaunchDarkly | ~$75 |
| Code Quality | Codecov | CodeScene | ~$150 |
| DORA Metrics | DevLake | LinearB | ~$200 |
| Security | CodeQL | Snyk | ~$100 |
| **Total** | $0 | ~$525 | - |

---

## Quick Start Commands

```bash
# Install git hooks
./scripts/install-hooks.sh

# Run lint checks
./scripts/lint.sh

# Run quick tests
./scripts/test-quick.sh

# Run full health check
./scripts/health-check.sh

# Run all tests with coverage
./scripts/test-all.sh

# Audit feature flags
./scripts/feature-flag-audit.sh

# Audit for hook bypasses
./scripts/hook-audit.sh

# Run latency tests
python -m latency_harness.cli --suite quick_validation --mock

# Start DevLake (DORA metrics)
cd server/devlake && docker compose up -d

# Start Feature Flags (Unleash)
cd server/feature-flags && docker compose up -d
```

---

## Configuration Files Reference

| File | Purpose |
|------|---------|
| `.hooks/pre-commit` | Pre-commit quality checks |
| `.hooks/pre-push` | Pre-push test validation |
| `.coderabbit.yaml` | AI code review configuration |
| `renovate.json` | Dependency automation |
| `.swiftlint.yml` | Swift linting rules |
| `baselines/latency.json` | Performance targets |
| `.github/workflows/*.yml` | CI/CD pipelines |
| `server/feature-flags/` | Feature flag infrastructure |
| `server/devlake/` | DORA metrics infrastructure |

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| [QUALITY_INFRASTRUCTURE_PLAN.md](QUALITY_INFRASTRUCTURE_PLAN.md) | Implementation tracking |
| [LATENCY_TEST_HARNESS_GUIDE.md](LATENCY_TEST_HARNESS_GUIDE.md) | Complete latency testing guide |
| [design/AUDIO_LATENCY_TEST_HARNESS.md](design/AUDIO_LATENCY_TEST_HARNESS.md) | Latency harness architecture |
| [IOS_STYLE_GUIDE.md](ios/IOS_STYLE_GUIDE.md) | iOS coding standards |
| [setup/DEV_ENVIRONMENT.md](setup/DEV_ENVIRONMENT.md) | Developer setup guide |
| [setup/CODERABBIT_SETUP.md](setup/CODERABBIT_SETUP.md) | CodeRabbit configuration |

---

## Conclusion

The Code Quality Initiative transforms UnaMentis from a typical small-team project into an enterprise-grade operation. Through systematic automation and intelligent tooling, we achieve:

1. **Consistency**: Every commit passes the same quality checks
2. **Visibility**: Real-time insight into engineering health
3. **Safety**: Feature flags enable risk-free experimentation
4. **Performance**: Latency regressions are caught before deployment
5. **Security**: Multi-layered scanning prevents vulnerabilities

This infrastructure enables a small team to maintain quality standards typically requiring 10+ engineers, while maintaining the agility and velocity that makes small teams effective.

---

**Last Updated:** January 2025
**Status:** Phases 1-5 Complete (Mutation Testing, Chaos Engineering implemented)
