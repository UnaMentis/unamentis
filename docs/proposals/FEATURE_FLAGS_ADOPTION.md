# Feature Flags Adoption Proposal

## Current State

UnaMentis has a **fully implemented but unused** feature flags system:
- Unleash server infrastructure (Docker Compose)
- iOS SDK (actor-based, offline caching)
- Web SDK (React hooks, localStorage caching)
- Audit tooling and CI workflow

**What's missing:** No flags are registered, no app code uses the SDK, the server isn't running.

---

## Proposed Adoption Strategy

### Phase 1: Foundation (Before Beta Launch)

**Goal:** Get the system running and establish patterns.

#### 1.1 Start Using the Infrastructure

```bash
# Start Unleash (run once, stays running)
cd server/feature-flags
docker compose up -d
```

Add to Server Manager (see below) so it starts automatically.

#### 1.2 Wire SDK into App Startup

**iOS (UnaMentisApp.swift or AppDelegate):**
```swift
// In app initialization
Task {
    try? await FeatureFlagService.shared.start()
}
```

**Web (layout.tsx or _app.tsx):**
```tsx
<FeatureFlagProvider config={featureFlagConfig}>
  <App />
</FeatureFlagProvider>
```

#### 1.3 Create First Operational Flags

| Flag Name | Category | Purpose |
|-----------|----------|---------|
| `ops_maintenance_mode` | ops | Kill switch for emergencies |
| `ops_verbose_logging` | ops | Enable detailed logging for debugging |
| `ops_analytics_enabled` | ops | Control analytics collection |

These are permanent ops flags, not feature rollouts.

---

### Phase 2: Beta Rollout Flags

**Goal:** Control feature availability during beta expansion.

#### 2.1 User Targeting Strategy

For beta, use these Unleash strategies:

1. **Specific User IDs** - First 10 beta testers
2. **Gradual Rollout** - Expand from 10% to 100%
3. **Context Properties** - Beta tier (alpha/beta/public)

#### 2.2 Recommended Beta Flags

| Flag Name | Category | Purpose | Rollout Strategy |
|-----------|----------|---------|------------------|
| `beta_new_voice_engine` | release | Test new voice processing | User IDs → 10% → 50% → 100% |
| `beta_tts_provider_switch` | release | Switch TTS providers | User IDs only initially |
| `beta_curriculum_v2` | release | New curriculum format | Gradual 25% increments |
| `exp_session_length_test` | experiment | Test 120min vs 90min sessions | 50/50 A/B test |
| `exp_voice_latency_mode` | experiment | Test aggressive vs conservative buffering | 50/50 A/B test |

#### 2.3 Implementation Pattern

```swift
// iOS example
func startVoiceSession() async {
    let useNewEngine = await FeatureFlagService.shared.isEnabled("beta_new_voice_engine")

    if useNewEngine {
        await startWithNewEngine()
    } else {
        await startWithLegacyEngine()
    }
}
```

```tsx
// Web example
function VoiceControls() {
    const useNewEngine = useFlag('beta_new_voice_engine');

    return useNewEngine ? <NewVoiceControls /> : <LegacyVoiceControls />;
}
```

---

### Phase 3: Rapid Beta Expansion

**Goal:** Safely expand from small group to larger beta.

#### 3.1 Rollout Checklist

Before increasing rollout percentage:
- [ ] Check error rates in logs
- [ ] Review user feedback from current cohort
- [ ] Verify latency metrics are acceptable
- [ ] Confirm no memory leaks in longer sessions

#### 3.2 Rollback Strategy

If issues arise:
1. Set flag to 0% in Unleash UI (immediate, no deploy)
2. Users fall back to stable code path
3. Investigate and fix
4. Resume gradual rollout

#### 3.3 Flag Lifecycle

```
Week 1: Create flag, 0% (code ships with flag checks)
Week 2: Internal testing (specific user IDs)
Week 3: 10% beta testers
Week 4: 25% if metrics good
Week 5: 50%
Week 6: 100%
Week 7-8: Monitor, then remove flag and dead code
```

---

## Server Manager Integration

### Development Mode Concept

Add a "Development Mode" toggle to the Server Manager that:
- **OFF (default):** Shows production services only
- **ON:** Shows additional dev/maintenance tools

### Services by Mode

| Service | Mode | Purpose |
|---------|------|---------|
| PostgreSQL | Always | Core database |
| Log Server | Always | Central logging |
| Management API | Always | Backend API |
| Operations Console | Always | Admin UI |
| Web Client | Always | User-facing web |
| Ollama | Always | Local LLM |
| **Feature Flags (Unleash)** | Dev Mode | Flag management |
| **Latency Harness** | Dev Mode | Performance testing |
| **Mock Servers** | Dev Mode | Testing infrastructure |

### UI Design

```
┌─────────────────────────────────────────┐
│ UnaMentis Server Manager        ⟳       │
├─────────────────────────────────────────┤
│ ● PostgreSQL        0.1%    45MB  ▶ ■ ⟳ │
│ ● Log Server        0.0%    12MB  ▶ ■ ⟳ │
│ ● Management API    0.5%    89MB  ▶ ■ ⟳ │
│ ● Operations Console 1.2%  156MB  ▶ ■ ⟳ │
│ ● Web Client        0.8%   124MB  ▶ ■ ⟳ │
│ ● Ollama            0.0%   2.1GB  ▶ ■ ⟳ │
├─────────────────────────────────────────┤
│ ▼ Development Tools                     │  ← Collapsible section
│   ○ Feature Flags   —      —     ▶ ■ ⟳ │
│   ○ Latency Harness —      —     ▶ ■ ⟳ │
├─────────────────────────────────────────┤
│ [Start All] [Stop All]     🌐 💻 📄    │
├─────────────────────────────────────────┤
│ ☐ Development Mode              [Quit] │
└─────────────────────────────────────────┘
```

### Unleash Service Details

| Property | Value |
|----------|-------|
| Display Name | Feature Flags |
| Process Detection | `unleash-server` container |
| Ports | 4242 (UI), 3063 (Proxy) |
| Start Command | `docker compose -f server/feature-flags/docker-compose.yml up -d` |
| Stop Command | `docker compose -f server/feature-flags/docker-compose.yml down` |
| Quick Links | Open Unleash UI (localhost:4242) |

---

## Implementation Checklist

### Immediate (This Week)

- [ ] Add Unleash to Server Manager with dev mode toggle
- [ ] Wire FeatureFlagService.start() into iOS app launch
- [ ] Wire FeatureFlagProvider into web app root
- [ ] Create `ops_maintenance_mode` flag in Unleash UI
- [ ] Test kill switch works end-to-end

### Before Beta

- [ ] Create beta rollout flags in Unleash
- [ ] Add flag checks around new/experimental features
- [ ] Set up user context passing (user ID, app version)
- [ ] Document flag removal process for team

### During Beta

- [ ] Use gradual rollout for each new feature
- [ ] Monitor flag evaluation metrics
- [ ] Run weekly flag audit to identify stale flags
- [ ] Remove flags as features become stable

---

## Benefits of This Approach

1. **Instant Rollback** - Disable features without deploying
2. **Gradual Rollout** - Catch issues with small user groups
3. **A/B Testing** - Compare implementations with data
4. **Kill Switch** - Emergency brake for critical bugs
5. **User Targeting** - Give power users early access

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Flag sprawl | Weekly audit, 30-day max age for release flags |
| Complexity | Start with 3-5 flags, not 50 |
| Testing burden | Test both flag states in CI |
| Offline issues | 24-hour cache already implemented |

---

## Next Steps

1. Review this proposal
2. Implement Server Manager changes (see separate PR)
3. Start Unleash and create first ops flags
4. Add SDK initialization to apps
5. Begin using for first beta feature
