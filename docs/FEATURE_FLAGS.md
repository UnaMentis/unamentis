# Feature Flags Guide

This guide covers the feature flag system used in UnaMentis for safe feature rollouts, A/B testing, and operational toggles.

## Overview

UnaMentis uses [Unleash](https://www.getunleash.io/), a self-hosted open-source feature management platform. The system consists of:

- **Unleash Server**: Central management UI and API
- **Unleash Proxy**: Edge proxy for client-side evaluation
- **iOS SDK**: Swift service with offline caching
- **Web SDK**: React hooks and components

## Quick Start

### For Developers

#### iOS

```swift
import UnaMentis

// Check if a feature is enabled
if await FeatureFlagService.shared.isEnabled("new_voice_engine") {
    // Use new voice engine
} else {
    // Use old voice engine
}

// SwiftUI: Conditionally show views
SomeView()
    .featureFlag("dark_mode")
```

#### Web

```tsx
import { useFlag, FeatureGate } from '@/lib/feature-flags';

// Hook-based
function MyComponent() {
  const isNewUI = useFlag('new_ui');
  return isNewUI ? <NewUI /> : <OldUI />;
}

// Component-based
function App() {
  return (
    <FeatureGate flag="beta_features" fallback={<StandardFeatures />}>
      <BetaFeatures />
    </FeatureGate>
  );
}
```

### For Product/Ops

1. Access Unleash UI: http://localhost:4242 (or production URL)
2. Log in with your credentials
3. Create or modify feature toggles
4. Configure activation strategies (gradual rollout, user targeting, etc.)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Feature Flag Flow                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐                    ┌──────────────┐           │
│  │  Unleash UI  │ ─── manages ────► │   Unleash    │           │
│  │  (Admin)     │                    │   Server     │           │
│  └──────────────┘                    └──────┬───────┘           │
│                                             │                    │
│                                             ▼                    │
│                                      ┌──────────────┐           │
│                                      │   Unleash    │           │
│                                      │    Proxy     │           │
│                                      └──────┬───────┘           │
│                                             │                    │
│              ┌──────────────────────────────┼──────────────┐    │
│              │                              │              │    │
│              ▼                              ▼              ▼    │
│       ┌──────────┐                  ┌──────────┐   ┌──────────┐ │
│       │ iOS App  │                  │ Web App  │   │  Server  │ │
│       │ (cache)  │                  │ (cache)  │   │          │ │
│       └──────────┘                  └──────────┘   └──────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Flag Categories

| Category | Purpose | Max Lifetime | Example |
|----------|---------|--------------|---------|
| `release` | Feature rollouts | 30 days | `new_onboarding_flow` |
| `experiment` | A/B tests | 60 days | `ab_pricing_variant` |
| `ops` | Operational toggles | Unlimited | `maintenance_mode` |
| `permission` | User permissions | Permanent | `admin_access` |

## Flag Lifecycle

### 1. Planning

Before creating a flag:

1. Determine the category
2. Assign an owner (GitHub username)
3. Set a target removal date
4. Document the purpose

### 2. Creation

#### In Unleash UI

1. Go to Feature toggles > New toggle
2. Name: Use convention `<scope>_<feature>` (e.g., `voice_new_engine`)
3. Description: Clear explanation of what the flag controls
4. Type: Select appropriate type (Release, Experiment, etc.)

#### Register Metadata

Add entry to `server/feature-flags/flag_metadata.json`:

```json
{
  "new_voice_engine": {
    "owner": "ramerman",
    "description": "New voice processing engine with reduced latency",
    "category": "release",
    "created_at": "2025-01-07",
    "target_removal_date": "2025-02-07",
    "is_permanent": false,
    "platforms": ["ios"],
    "jira_ticket": "UNA-123"
  }
}
```

### 3. Implementation

#### iOS

```swift
// Simple check
let enabled = await FeatureFlagService.shared.isEnabled("new_voice_engine")

// With user context
let context = FeatureFlagContext(userId: user.id)
let enabled = await FeatureFlagService.shared.isEnabled("premium_features", context: context)

// Get variant for A/B tests
if let variant = await FeatureFlagService.shared.getVariant("pricing_experiment") {
    switch variant.name {
    case "control": showControlPricing()
    case "variant_a": showVariantAPricing()
    default: showControlPricing()
    }
}
```

#### Web

```tsx
// Hooks
const { isEnabled, getVariant, state } = useFeatureFlags();

// Simple hook
const showNewFeature = useFlag('new_feature');

// Variant hook
const variant = useFlagVariant('ab_test');

// Provider setup (in app layout)
<FeatureFlagProvider config={featureFlagConfig}>
  <App />
</FeatureFlagProvider>
```

### 4. Rollout

Unleash supports multiple activation strategies:

| Strategy | Use Case |
|----------|----------|
| **Standard** | Simple on/off |
| **Gradual Rollout** | Percentage-based (e.g., 10% → 50% → 100%) |
| **UserIDs** | Specific users (for beta testing) |
| **IPs** | IP-based targeting |
| **Hostname** | Environment-based |
| **Custom** | Complex business rules |

Typical rollout sequence:
1. Internal testing (specific user IDs)
2. Beta users (10%)
3. Gradual expansion (25% → 50% → 75%)
4. Full rollout (100%)
5. Flag removal

### 5. Removal

When a flag reaches 100% rollout:

1. Remove all flag checks from code
2. Delete the flag from Unleash UI
3. Remove the metadata entry
4. Update documentation

**Do not leave flags at 100% indefinitely** - this creates technical debt.

## Naming Convention

```
<scope>_<feature>_<variant?>

Scopes:
- voice_    Voice/audio features
- ui_       User interface changes
- api_      Backend API changes
- ab_       A/B test experiments
- ops_      Operational toggles
- perm_     Permission flags

Examples:
- voice_new_engine
- ui_dark_mode
- ab_pricing_v2
- ops_maintenance
- perm_admin_panel
```

## Best Practices

### Do's

- Set target removal dates for all non-permanent flags
- Use meaningful, descriptive names
- Document flag purpose in metadata
- Test both enabled and disabled states
- Use gradual rollouts for risky changes
- Clean up flags promptly after full rollout

### Don'ts

- Don't nest feature flags (flag A checks flag B)
- Don't use flags for permanent configuration
- Don't create flags without owners
- Don't leave flags at 100% without removal plan
- Don't use flags to hide broken code

## Offline Support

Both iOS and Web SDKs cache flags locally:

- **iOS**: Persisted to app cache directory, 24-hour TTL
- **Web**: LocalStorage, 24-hour TTL

On app start:
1. Load cached flags immediately
2. Fetch fresh flags in background
3. Update cache on successful fetch

If network fails:
1. Continue using cached values
2. Retry on next refresh interval
3. Log warning but don't block app

## Monitoring

### Metrics

The system tracks:
- Flag evaluation count
- Cache hit/miss rate
- Refresh success/failure
- Network latency

### Audit

Weekly automated audit checks:
- Flags past target removal date
- Flags without owners
- Unused flags (no evaluations in 30 days)

Run manually:
```bash
./scripts/feature-flag-audit.sh
```

## Troubleshooting

### Flag Not Working

1. Check Unleash UI - is the flag enabled?
2. Check activation strategy - does user match criteria?
3. Check client logs for fetch errors
4. Verify proxy connection

### Stale Flags

If flags seem outdated:
1. Force refresh: `await FeatureFlagService.shared.refresh()`
2. Check refresh interval configuration
3. Clear local cache and restart app

### Proxy Connection Issues

```bash
# Check proxy health
curl http://localhost:3063/proxy/health

# Check proxy logs
cd server/feature-flags
docker compose logs unleash-proxy
```

## Local Development

### Start Unleash Locally

```bash
cd server/feature-flags
docker compose up -d
```

Access:
- Unleash UI: http://localhost:4242 (admin / unleash4all)
- Proxy: http://localhost:3063/proxy

### Create Test Flags

1. Log into Unleash UI
2. Create toggle with name matching your code
3. Enable for development environment
4. Test in your app

### iOS Configuration

```swift
// Development config (automatic in DEBUG builds)
let config = FeatureFlagConfig(
    proxyURL: URL(string: "http://localhost:3063/proxy")!,
    clientKey: "proxy-client-key",
    appName: "UnaMentis-iOS-Dev"
)
```

### Web Configuration

```typescript
// In your environment config
const featureFlagConfig = {
  proxyUrl: 'http://localhost:3063/proxy',
  clientKey: 'proxy-client-key',
  appName: 'UnaMentis-Web-Dev',
};
```

## Production Deployment

### Security Checklist

- [ ] Replace default admin credentials
- [ ] Generate secure API tokens
- [ ] Enable HTTPS
- [ ] Restrict UI access (VPN/SSO)
- [ ] Set up audit logging

### High Availability

For production:
1. Run multiple Unleash instances
2. Use managed PostgreSQL
3. Deploy proxy in multiple regions
4. Configure health checks and alerts

## Related Documentation

- [server/feature-flags/README.md](../server/feature-flags/README.md) - Infrastructure setup
- [QUALITY_INFRASTRUCTURE_PLAN.md](QUALITY_INFRASTRUCTURE_PLAN.md) - Overall quality strategy
- [Unleash Documentation](https://docs.getunleash.io/) - Official Unleash docs
