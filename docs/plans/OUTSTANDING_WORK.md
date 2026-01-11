# Outstanding Work Plan

> **Created:** January 10, 2026
> **Purpose:** Consolidated list of all outstanding work identified during project audit

This document consolidates all incomplete items from planning documentation, TODO comments in code, and feature gaps discovered during the comprehensive project audit.

---

## Priority 1: Code TODOs (Wire-up Work)

These are explicit TODO comments in the codebase that represent incomplete implementations.

### iOS Client

| File | Line | TODO | Priority | Description |
|------|------|------|----------|-------------|
| `UnaMentis/Testing/LatencyHarness/LatencyTestCoordinator.swift` | 874 | Calculate from provider costs | Low | Latency test cost estimation is hardcoded to 0 |
| `UnaMentis/Services/STT/GLMASROnDeviceSTTService.swift` | 380 | Implement full mel spectrogram with FFT | Low | Using simplified energy-based approximation instead of proper FFT |
| `UnaMentis/Services/STT/GLMASROnDeviceSTTService.swift` | 448 | Integrate audio embeddings with decoder | Low | Using simple text completion instead of proper audio embedding integration |
| `UnaMentis/Services/Curriculum/CurriculumDownloadManager.swift` | 338 | Topic-level filtering | Low | Bandwidth optimization for partial curriculum downloads |
| `UnaMentis/Core/Routing/PatchPanelService.swift` | 406 | Implement real system state capture | Medium | Routing context uses default values instead of real battery/thermal/network state |

**Note:** GLM-ASR on-device STT is working via Apple Speech fallback. The mel spectrogram and audio embedding TODOs are for the full llama.cpp integration path which is not currently active (`llamaAvailable = false`).

---

## Priority 2: Server Infrastructure Completion

### Server Idle Optimization (Phase 5)
**Status:** 90% Complete

Outstanding items:
- [ ] Measure actual power savings with different power modes
- [ ] Validate response time targets when transitioning between states
- [ ] Create user guide for power mode configuration

### Server Resource Monitoring (Phase 4)
**Status:** 80% Complete

Outstanding items:
- [ ] Export metrics to OpenTelemetry/SigNoz (deferred, low priority)
- [ ] Create troubleshooting runbook for resource issues

---

## Priority 3: Quality Infrastructure

### From QUALITY_INFRASTRUCTURE_PLAN.md

| Item | Status | Notes |
|------|--------|-------|
| Web feature flag unit tests | Missing | Add tests for React feature flag hooks |
| Coverage badge in README | Missing | Add Codecov badge |
| Codecov integration | Incomplete | Configure for all targets |
| Python server coverage setup | Incomplete | pytest-cov configuration |
| Web client coverage setup | Incomplete | Jest coverage configuration |

### From DEVELOPMENT_EXCELLENCE.md (Phase 2)

| Item | Status | Notes |
|------|--------|-------|
| test-generator subagent | Not implemented | Could add but not critical |
| TDD skill | Covered by /validate | No action needed |
| iOS testing skill | Covered by /mcp-setup + /debug-logs | No action needed |
| code-reviewer subagent | Covered by /review skill | No action needed |

---

## Priority 4: Future Features

### Watch App Phase 2 (Voice Communication)
**Status:** Phase 1 Complete, Phase 2 Not Started

Phase 2 would enable:
- Direct voice communication through Watch
- Remote STT/TTS via WiFi/Cellular
- Standalone session capability

This is a future enhancement, not blocking current functionality.

### Curriculum Reprocessing System
**File:** `docs/planning/CURRICULUM_REPROCESSING_IMPLEMENTATION.md`
**Status:** Ready for implementation (High Priority Future)

System for re-enriching existing curricula with LLM enrichment without re-importing.

---

## NOT Outstanding (Clarifications)

The following items were in planning docs but are actually complete:

| Item | Status | Evidence |
|------|--------|----------|
| Server Idle Manager | Complete | `server/management/idle_manager.py` with full implementation |
| Server Resource Monitor | Complete | `server/management/resource_monitor.py` with full implementation |
| Patch Panel | Complete | All routing models and service implemented in `UnaMentis/Core/Routing/` |
| GLM-ASR On-Device STT | Working | Uses Apple Speech fallback, `GLMASROnDeviceSTTService.swift` exists |
| Watch App (Phase 1) | Complete | Control plane implemented in `UnaMentis Watch App/` |

---

## Summary

| Category | Total Items | Critical | Medium | Low |
|----------|-------------|----------|--------|-----|
| Code TODOs | 5 | 0 | 1 | 4 |
| Server Completion | 4 | 0 | 2 | 2 |
| Quality Infrastructure | 5 | 0 | 2 | 3 |
| Future Features | 2 | 0 | 0 | 2 |
| **Total** | **16** | **0** | **5** | **11** |

**Key Finding:** No critical outstanding work. The project is in good shape with mostly low-priority polish items remaining.

---

## Next Steps

1. **Short-term:** Address the Medium priority items:
   - Implement real system state capture in PatchPanelService (device battery, thermal, network)
   - Validate server idle power savings
   - Add web feature flag tests

2. **When prioritized:** Future features can be tackled when there's specific need:
   - Watch App voice communication
   - Curriculum reprocessing system

3. **Ongoing:** Quality infrastructure items can be addressed incrementally.

---

*This document supersedes individual workstream and implementation plan documents.*
