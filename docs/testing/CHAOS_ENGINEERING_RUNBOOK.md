# Chaos Engineering Runbook

> Voice Pipeline Resilience Testing for UnaMentis

This runbook defines chaos engineering practices for testing the resilience of the UnaMentis voice pipeline. Voice applications fail silently under network stress, and users just experience "silence." This testing simulates real-world conditions to ensure graceful degradation.

## Overview

### Why Chaos Engineering for Voice?

Voice applications are uniquely vulnerable to network issues:
- **Latency spikes**: Users notice delays over 500ms
- **Packet loss**: Audio becomes choppy or unintelligible
- **Connection drops**: Sessions terminate unexpectedly
- **API timeouts**: Responses never arrive

Traditional testing doesn't catch these issues because it runs in ideal conditions. Chaos engineering deliberately introduces failures to ensure the system handles them gracefully.

### Goals

1. Validate graceful degradation under network stress
2. Ensure fallback mechanisms activate correctly
3. Measure recovery time from failures
4. Document system behavior under various failure modes

## Test Scenarios

### 1. High Latency (500ms+)

**Scenario**: Network latency exceeds acceptable thresholds.

**Expected Behavior**:
- App shows latency indicator to user
- Continues processing with degraded experience
- Falls back to on-device processing if available
- Maintains session state

**Test Steps**:
```bash
# On macOS with Network Link Conditioner
# Or use Charles Proxy / mitmproxy

# Add 500ms latency to all requests
# Monitor: User experience, fallback activation, error rates
```

**Success Criteria**:
- No crashes or freezes
- User informed of degraded conditions
- Session continues or gracefully terminates
- Recovery within 5 seconds of network restoration

### 2. Packet Loss (5-20%)

**Scenario**: Intermittent packet loss causing audio gaps.

**Expected Behavior**:
- Audio buffers absorb minor gaps
- TTS gracefully handles missing audio chunks
- STT provides partial transcripts where possible
- No cascading failures

**Test Steps**:
```bash
# Simulate 10% packet loss
# Network Link Conditioner: "100% Loss, 10% of time"

# Monitor:
# - Audio quality degradation
# - STT accuracy
# - TTS playback continuity
```

**Success Criteria**:
- Audio remains mostly intelligible
- App doesn't crash on corrupt audio frames
- Recovery is automatic when packet loss ends

### 3. Complete Disconnection

**Scenario**: Network connection is lost mid-session.

**Expected Behavior**:
- Immediate detection of disconnection
- User notification within 2 seconds
- Graceful session pause (not termination)
- Auto-reconnect attempts with backoff
- Session resumption when connection restored

**Test Steps**:
```bash
# Toggle WiFi/cellular off mid-conversation
# Observe behavior for 30 seconds
# Restore connectivity

# Monitor:
# - Detection time
# - User feedback
# - Reconnection behavior
# - Session state preservation
```

**Success Criteria**:
- User informed within 2 seconds
- No data loss during brief outages
- Session resumes without restart
- Clean termination if disconnection persists

### 4. API Timeout Handling

**Scenario**: External APIs (Groq, OpenAI, ElevenLabs) don't respond.

**Expected Behavior**:
- Timeout after configured interval (10s default)
- Fallback to alternative provider if available
- User notification of delay
- Retry with exponential backoff

**Test Steps**:
```bash
# Use Charles Proxy to add 30s delay to API endpoints
# Or configure mock server with delayed responses

# Test each provider:
# - STT: Groq Whisper, Deepgram, Apple Speech
# - LLM: Anthropic, OpenAI, Ollama
# - TTS: ElevenLabs, Deepgram Aura, Apple TTS
```

**Success Criteria**:
- Timeout triggers within configured interval
- Fallback provider activates automatically
- User experience continues (degraded is OK)
- No hung connections or memory leaks

### 5. Partial API Failure

**Scenario**: One API in the pipeline fails while others work.

**Expected Behavior**:
- Failure isolated to affected component
- Other components continue functioning
- Graceful error message to user
- System remains stable

**Test Steps**:
```bash
# Block only TTS API while STT and LLM work
# User speaks, AI responds, but no audio output

# Monitor:
# - Error isolation
# - User feedback
# - Fallback to Apple TTS
```

**Success Criteria**:
- Failure doesn't cascade
- User understands what failed
- Session can continue with fallback

### 6. Memory Pressure

**Scenario**: Device memory is constrained during long session.

**Expected Behavior**:
- Graceful memory cleanup
- Non-critical caches cleared first
- Core session preserved
- Warning before critical threshold

**Test Steps**:
```bash
# Run memory pressure test alongside 60+ minute session
# Use Xcode Instruments to monitor memory

# Simulate:
# - Background apps consuming memory
# - Large audio buffer accumulation
# - Context window growth
```

**Success Criteria**:
- Memory stays under 200MB growth
- No OOM crashes
- Graceful degradation if pressure persists
- Session can complete

### 7. Thermal Throttling

**Scenario**: Device overheats and throttles CPU.

**Expected Behavior**:
- Reduced processing continues
- Latency increases gracefully
- No crashes or freezes
- User notified if severe

**Test Steps**:
```bash
# Run CPU-intensive tasks while in session
# Monitor thermal state
# Use Xcode Instruments

# Simulate:
# - Run benchmark app in background
# - Use device in direct sunlight
# - Extended session (60+ minutes)
```

**Success Criteria**:
- App adapts to reduced performance
- User experience degrades gracefully
- No crashes from thermal events
- Recovery when device cools

## Network Simulation Tools

### macOS Network Link Conditioner

1. Download from Apple Developer > More Downloads
2. Install the preference pane
3. Enable and select profile:
   - "3G" for high latency
   - "Edge" for poor connection
   - Custom profiles for specific tests

### Charles Proxy

```yaml
# Throttle settings for voice testing
download_bandwidth: 128 Kbps
upload_bandwidth: 64 Kbps
latency: 500ms
packet_loss: 10%
```

### iOS Simulator

```bash
# Use xcrun to configure network conditions
xcrun simctl status_bar booted --dataNetwork 3g
```

## Automation Scripts

### Network Degradation Test

```bash
#!/bin/bash
# scripts/chaos/network-degradation-test.sh

# Prerequisites:
# - Network Link Conditioner installed
# - App running in simulator

echo "Starting network degradation test..."

# Test phases
PHASES=(
    "No degradation:0:0"
    "High latency:500:0"
    "Moderate packet loss:100:10"
    "Severe packet loss:200:20"
    "Combined:500:15"
)

for phase in "${PHASES[@]}"; do
    IFS=':' read -r name latency loss <<< "$phase"
    echo ""
    echo "=== Phase: $name (latency: ${latency}ms, loss: ${loss}%) ==="

    # Apply network conditions (implementation depends on tool)
    # Record behavior for 30 seconds
    # Collect metrics

    sleep 30
done

echo ""
echo "Test complete. Review results above."
```

### API Failure Simulation

```python
#!/usr/bin/env python3
# scripts/chaos/api-failure-test.py

"""
API Failure Simulation for Chaos Testing

Run a mock server that simulates API failures.
"""

from aiohttp import web
import asyncio
import random

failure_modes = {
    "timeout": lambda: asyncio.sleep(60),  # Never responds
    "error_500": lambda: web.Response(status=500, text="Internal Server Error"),
    "error_429": lambda: web.Response(status=429, text="Rate Limited"),
    "partial": lambda: web.Response(text='{"partial":'),  # Incomplete JSON
    "slow": lambda: asyncio.sleep(5),  # Slow but responds
}

async def chaos_handler(request):
    mode = request.query.get("mode", "normal")

    if mode == "random":
        mode = random.choice(list(failure_modes.keys()) + ["normal", "normal"])

    if mode in failure_modes:
        result = failure_modes[mode]()
        if asyncio.iscoroutine(result):
            await result
            return web.Response(text="OK")
        return result

    return web.Response(text='{"status": "ok"}')

app = web.Application()
app.router.add_route("*", "/{path:.*}", chaos_handler)

if __name__ == "__main__":
    web.run_app(app, port=8888)
```

## Metrics to Collect

During chaos tests, collect these metrics:

| Metric | Target | Critical |
|--------|--------|----------|
| Detection Time | < 2s | < 5s |
| User Notification | < 3s | < 10s |
| Fallback Activation | < 5s | < 15s |
| Recovery Time | < 10s | < 30s |
| Memory Growth | < 50MB | < 100MB |
| Crash Count | 0 | 0 |
| Session Preservation | 100% | > 90% |

## Runbook Execution Schedule

| Frequency | Tests | Duration |
|-----------|-------|----------|
| Weekly | Basic resilience (scenarios 1-3) | 30 min |
| Monthly | Full suite (all scenarios) | 2 hours |
| Release | Critical paths (1, 3, 4) | 1 hour |
| Ad-hoc | Specific scenarios | As needed |

## Integration with CI/CD

Chaos tests can be integrated into the nightly E2E workflow:

```yaml
# Add to .github/workflows/nightly-e2e.yml
chaos-tests:
  name: Chaos Engineering Tests
  runs-on: macos-14
  steps:
    - name: Run network degradation tests
      run: ./scripts/chaos/network-degradation-test.sh

    - name: Validate graceful degradation
      run: ./scripts/chaos/validate-degradation.sh
```

## Incident Response

When chaos tests reveal issues:

1. **Document the failure mode** precisely
2. **Create a GitHub issue** with:
   - Failure scenario
   - Expected vs actual behavior
   - Logs and screenshots
   - Priority based on user impact
3. **Fix and re-test** before next release
4. **Add regression test** to prevent recurrence

## Related Documentation

- [LATENCY_TEST_HARNESS_GUIDE.md](../LATENCY_TEST_HARNESS_GUIDE.md) - Performance testing
- [design/AUDIO_LATENCY_TEST_HARNESS.md](../design/AUDIO_LATENCY_TEST_HARNESS.md) - Latency harness architecture
- [CODE_QUALITY_INITIATIVE.md](../quality/CODE_QUALITY_INITIATIVE.md) - Quality infrastructure overview

## Appendix: Failure Mode Reference

| Failure | User Experience | Recovery | Priority |
|---------|-----------------|----------|----------|
| High latency (>500ms) | Noticeable delay | Automatic | Medium |
| Packet loss (5-10%) | Minor audio gaps | Automatic | Low |
| Packet loss (10-20%) | Choppy audio | Automatic | Medium |
| API timeout | "Thinking..." indicator | Fallback/Retry | High |
| Complete disconnect | Session paused | Manual reconnect | Critical |
| Memory pressure | Slower response | Automatic cleanup | Medium |
| Thermal throttling | Slower response | Device dependent | Low |

---

**Last Updated:** January 2025
**Status:** Active
**Owner:** Quality Infrastructure Team
