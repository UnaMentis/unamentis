# Feature Flags Architecture

This document describes the feature flag architecture for UnaMentis, enabling runtime control over service tiers, cost management, and graceful degradation.

## Flag Categories

### Operational Flags (`ops_*`)
Long-lived flags for system operations. These are permanent and control infrastructure behavior.

| Flag | Default | Purpose |
|------|---------|---------|
| `ops_maintenance_mode` | OFF | Kill switch - blocks all session starts |
| `ops_verbose_logging` | ON | Enable detailed logging for debugging |
| `ops_analytics_enabled` | ON | Control analytics/telemetry collection |
| `ops_budget_cap_reached` | OFF | Emergency flag when hosting budget exhausted |

### Service Tier Flags (`service_*`)
Control which capabilities are available to users.

| Flag | Default | Purpose |
|------|---------|---------|
| `service_llm_interaction` | ON | Full two-way LLM conversation |
| `service_curriculum_delivery` | ON | TTS-based curriculum delivery |
| `service_source_dedicated_server` | ON | Use self-hosted server (primary) |
| `service_source_cloud_apis` | ON | Use cloud APIs (fallback) |

### Beta/Experiment Flags (`beta_*`, `exp_*`)
Temporary flags for gradual rollout. These flags should be removed within 30-60 days.

| Flag | Purpose | Target Removal |
|------|---------|----------------|
| `beta_new_tts_provider` | Test new TTS provider | After validation |
| `beta_curriculum_v2` | New curriculum format | After migration |
| `exp_session_length_120` | A/B test longer sessions | After data collected |

---

## Experience Tiers

Feature flags enable graceful degradation between experience tiers:

```
┌─────────────────────────────────────────────────────────────────┐
│ TIER 1: FULL EXPERIENCE                                         │
│                                                                  │
│ Flags: service_llm_interaction=ON                               │
│        service_curriculum_delivery=ON                           │
│                                                                  │
│ Features:                                                        │
│  - Two-way voice conversation with LLM                          │
│  - Real-time barge-in and interruption                          │
│  - Dynamic curriculum adaptation                                │
│  - Full TTS voice delivery                                      │
│  - Session persistence and caching                              │
├─────────────────────────────────────────────────────────────────┤
│ TIER 2: CURRICULUM DELIVERY MODE                                │
│                                                                  │
│ Flags: service_llm_interaction=OFF                              │
│        service_curriculum_delivery=ON                           │
│                                                                  │
│ Features:                                                        │
│  - Pre-authored curriculum delivered via TTS                    │
│  - No conversational interaction                                │
│  - Pause/resume controls                                        │
│  - Progress tracking                                            │
│  - Cached content available                                     │
│                                                                  │
│ Use when: Budget cap reached, LLM services unavailable          │
├─────────────────────────────────────────────────────────────────┤
│ TIER 3: OFFLINE/CACHED MODE                                     │
│                                                                  │
│ Flags: service_llm_interaction=OFF                              │
│        service_curriculum_delivery=OFF                          │
│                                                                  │
│ Features:                                                        │
│  - Previously cached content only                               │
│  - No new content generation                                    │
│  - Offline-capable                                              │
│                                                                  │
│ Use when: No network, all services unavailable                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Service Source Routing

Controls where AI services (LLM, TTS, STT) are sourced from:

```
┌──────────────────────────────────────────────────────────────────┐
│                     SERVICE REQUEST                              │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │ service_source_dedicated_server │
              │            enabled?             │
              └───────────────────────────────┘
                     │              │
                    YES             NO
                     │              │
                     ▼              │
         ┌─────────────────┐       │
         │  Try Dedicated  │       │
         │     Server      │       │
         └─────────────────┘       │
                │                   │
         success│fail              │
                │  │               │
                │  ▼               │
                │  ┌───────────────────────────┐
                │  │ service_source_cloud_apis │
                │  │         enabled?          │
                │  └───────────────────────────┘
                │         │              │
                │        YES             NO
                │         │              │
                │         ▼              ▼
                │  ┌─────────────┐  ┌─────────────┐
                │  │ Try Cloud   │  │   ERROR:    │
                │  │    APIs     │  │ No sources  │
                │  └─────────────┘  │  available  │
                │         │         └─────────────┘
                │  success│fail
                │         │  │
                ▼         ▼  ▼
         ┌─────────────────────────────────────┐
         │            RETURN RESULT            │
         └─────────────────────────────────────┘
```

### Configuration Scenarios

| Dedicated Server | Cloud APIs | Behavior |
|-----------------|------------|----------|
| ON | ON | Dedicated primary, cloud fallback |
| ON | OFF | Dedicated only (no fallback) |
| OFF | ON | Cloud only |
| OFF | OFF | Error - no services available |

---

## Cost Control Integration

When `ops_budget_cap_reached` is enabled:

1. **Immediate**: `service_llm_interaction` effectively disabled
2. **Graceful**: Client receives flag state, shows appropriate UI
3. **Degradation**: Falls back to curriculum delivery mode
4. **User notification**: "Interactive tutoring temporarily unavailable"

### Automation Hook

The management API can automatically toggle `ops_budget_cap_reached` based on:
- Daily/monthly spend thresholds
- API rate limit errors
- Infrastructure cost monitoring

```python
# Example: Auto-enable budget cap when threshold reached
if daily_spend >= DAILY_BUDGET_LIMIT:
    feature_flags.enable("ops_budget_cap_reached")
    notify_admin("Budget cap reached, degrading to curriculum mode")
```

---

## Client-Side Handling

### iOS (Swift)

```swift
// Check experience tier before starting session
let llmEnabled = await FeatureFlagService.shared.isEnabled("service_llm_interaction")
let curriculumEnabled = await FeatureFlagService.shared.isEnabled("service_curriculum_delivery")

if llmEnabled {
    // Full interactive mode
    try await startInteractiveSession()
} else if curriculumEnabled {
    // Curriculum delivery mode
    try await startCurriculumDelivery()
} else {
    // Offline/cached mode only
    showCachedContent()
}
```

### Web (React)

```tsx
function SessionView() {
  const llmEnabled = useFlag('service_llm_interaction');
  const curriculumEnabled = useFlag('service_curriculum_delivery');

  if (llmEnabled) {
    return <InteractiveSession />;
  } else if (curriculumEnabled) {
    return <CurriculumDelivery />;
  } else {
    return <OfflineContent />;
  }
}
```

---

## Additional Flag Suggestions

Based on the project architecture, consider these additional flags:

### Provider Selection
| Flag | Purpose |
|------|---------|
| `service_tts_provider_elevenlabs` | Use ElevenLabs for TTS |
| `service_tts_provider_chatterbox` | Use Chatterbox for TTS |
| `service_stt_provider_whisper` | Use Whisper for STT |
| `service_llm_provider_openai` | Use OpenAI for LLM |
| `service_llm_provider_anthropic` | Use Anthropic for LLM |
| `service_llm_provider_ollama` | Use local Ollama for LLM |

### Cost Optimization
| Flag | Purpose |
|------|---------|
| `ops_prefer_cached_responses` | Prefer cached LLM responses when available |
| `ops_batch_tts_requests` | Batch TTS for efficiency |
| `service_streaming_enabled` | Enable streaming (more responsive but potentially more expensive) |

### User Tiers (Future)
| Flag | Purpose |
|------|---------|
| `tier_premium_features` | Premium user features |
| `tier_extended_sessions` | Allow sessions > 90 minutes |
| `tier_priority_routing` | Priority access to resources |

### Curriculum
| Flag | Purpose |
|------|---------|
| `curriculum_sync_enabled` | Enable curriculum sync from server |
| `curriculum_offline_mode` | Force offline curriculum only |
| `curriculum_experimental_content` | Enable experimental curriculum |

---

## Best Practices

1. **Default to ON for service flags**: Users expect features to work
2. **Default to OFF for kill switches**: Only enable in emergencies
3. **Use variants for A/B tests**: Not just boolean toggles
4. **Set removal dates for beta flags**: Prevent flag sprawl
5. **Document flag dependencies**: If X requires Y, note it
6. **Monitor flag evaluation**: Track which flags are being checked
7. **Test both states**: Ensure graceful degradation works

---

## Management Commands

```bash
# View all flags
curl -s -H "Authorization: *:*.unleash-insecure-admin-api-token" \
  "http://localhost:4242/api/admin/projects/default/features" | jq '.features[].name'

# Enable a flag
curl -X POST "http://localhost:4242/api/admin/projects/default/features/FLAG_NAME/environments/development/on" \
  -H "Authorization: *:*.unleash-insecure-admin-api-token"

# Disable a flag
curl -X POST "http://localhost:4242/api/admin/projects/default/features/FLAG_NAME/environments/development/off" \
  -H "Authorization: *:*.unleash-insecure-admin-api-token"

# Emergency: Enable budget cap (triggers graceful degradation)
curl -X POST "http://localhost:4242/api/admin/projects/default/features/ops_budget_cap_reached/environments/development/on" \
  -H "Authorization: *:*.unleash-insecure-admin-api-token"
```

---

## Management Server Route Guards

The management API uses `guarded_routes` to gate entire API modules behind
feature flags at the route level. When a flag is disabled, all endpoints in
that module return HTTP 503 with the flag name in the response body.

### Guarded Modules

| Module | Flag | Default | Guarded Routes |
|--------|------|---------|----------------|
| Import pipeline | `ops_import_enabled` | ON | `/api/import/*` |
| Reprocessing | `ops_reprocessing_enabled` | ON | `/api/reprocess/*` |
| TTS generation | `ops_tts_generation_enabled` | ON | `/api/tts/*` |
| Media rendering | `ops_media_generation_enabled` | ON | `/api/media/*` |
| TTS pre-generation | `service_tts_pregen` | ON | `/api/tts/profiles/*`, `/api/tts/pregen/*` |
| TTS Lab | `service_tts_lab` | OFF | `/api/tts-lab/*` |
| Latency testing | `service_latency_testing` | OFF | `/api/latency-tests/*`, `/api/test-orchestrator/*` |
| KB packs | `service_kb_packs` | ON | `/api/kb/*` |
| Deployments | `service_deployment` | ON | `/api/deployments/*` |
| Lists | `service_lists` | ON | `/api/lists/*` |
| FOV context | `service_fov_context` | ON | `/api/sessions/*` |
| Plugins | `feature_plugin_system` | ON | `/api/plugins/*`, `/api/sources/*` |
| Modules | `feature_specialized_modules` | ON | `/api/modules/*` |

### Feature Flags API

```bash
# Get current state of all flags
GET /api/feature-flags

# Response
{
  "flags": {
    "ops_maintenance_mode": false,
    "ops_import_enabled": true,
    "service_tts_lab": false,
    ...
  },
  "source": "unleash"  // or "defaults" when Unleash is unavailable
}
```

---

## Current Flag Status

| Flag | Default | Category | Guarded Module |
|------|---------|----------|----------------|
| `ops_maintenance_mode` | OFF | ops | (global) |
| `ops_verbose_logging` | ON | ops | (logging) |
| `ops_analytics_enabled` | ON | ops | (telemetry) |
| `ops_budget_cap_reached` | OFF | ops | (cost control) |
| `ops_import_enabled` | ON | ops | Import pipeline |
| `ops_reprocessing_enabled` | ON | ops | Reprocessing |
| `ops_tts_generation_enabled` | ON | ops | TTS generation |
| `ops_media_generation_enabled` | ON | ops | Media rendering |
| `service_llm_interaction` | ON | service | (experience tier) |
| `service_curriculum_delivery` | ON | service | (experience tier) |
| `service_source_dedicated_server` | ON | service | (routing) |
| `service_source_cloud_apis` | ON | service | (routing) |
| `service_tts_pregen` | ON | service | TTS pre-generation |
| `service_tts_lab` | OFF | service | TTS Lab |
| `service_latency_testing` | OFF | service | Latency harness |
| `service_kb_packs` | ON | service | KB packs |
| `service_deployment` | ON | service | Deployments |
| `service_model_management` | ON | service | (models) |
| `service_lists` | ON | service | Lists |
| `service_fov_context` | ON | service | FOV context |
| `feature_plugin_system` | ON | feature | Plugins |
| `feature_specialized_modules` | ON | feature | Modules |
| `feature_team_mode` | ON | feature | (module-level) |
| `feature_competition_sim` | ON | feature | (module-level) |
