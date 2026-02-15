# TTFA (Time To First Audio) Test Harness

## Overview

Real-world, simulator-based performance test suite measuring activation-to-first-audio for every audio-producing feature. **Target: < 1 second, no exceptions.**

## Architecture

Two halves working together:

**In-app instrumentation** (`TTFAInstrumentation.swift`): Lightweight actor emitting structured `os_log` events at exact audio moments using `mach_absolute_time()`. Compiled into all builds with minimal overhead.

**External harness** (this Python package): Drives the simulator via `xcrun simctl`, captures log events, computes TTFA per feature, and manages baselines for regression detection.

```
┌─────────────────────────────────────┐
│  iOS App (TTFAInstrumentation)      │
│  os_log → [TTFA] EVENT|feature|ms|  │
└──────────┬──────────────────────────┘
           │ xcrun simctl spawn log stream
┌──────────▼──────────────────────────┐
│  Python CLI (ttfa_harness)          │
│  parser → results → baselines       │
└─────────────────────────────────────┘
```

## Quick Start

```bash
# List available test scenarios
python -m ttfa_harness.cli --list-scenarios

# Run quick suite (4 scenarios, ~2 min)
python -m ttfa_harness.cli --suite quick --device "iPhone 16 Pro"

# Run full suite (9 scenarios, ~10 min)
python -m ttfa_harness.cli --suite full

# Create a baseline from current run
python -m ttfa_harness.cli --suite full --create-baseline initial

# Compare against baseline (CI mode)
python -m ttfa_harness.cli --suite quick --baseline main --fail-on-regression

# Output formats
python -m ttfa_harness.cli --suite quick --format json
python -m ttfa_harness.cli --suite quick --format markdown
```

## Shell Script Runner

For CI and automated builds:

```bash
# Quick suite with automatic build
./scripts/ttfa-test.sh

# Full suite
./scripts/ttfa-test.sh --suite full

# CI mode (fail on regression, save artifacts)
./scripts/ttfa-test.sh --ci

# Skip build (use existing .app)
./scripts/ttfa-test.sh --skip-build

# Create baseline
./scripts/ttfa-test.sh --create-baseline main
```

Environment variables: `SIMULATOR`, `TTFA_SUITE`, `TTFA_BASELINE`, `TTFA_FORMAT`, `SKIP_BUILD`

## Test Scenarios

| ID | Feature | Audio Path | Description |
|---|---|---|---|
| `session-cold-start` | session.chat | streaming | Freeform chat session to first AI audio |
| `session-curriculum` | session.curriculum | streaming | Curriculum topic to first audio segment |
| `kb-oral-cached` | kb.oral | cached | KB question with server audio cache warm |
| `kb-oral-uncached` | kb.oral | streaming | KB question with local TTS |
| `kb-drill` | kb.drill | streaming | Domain drill question read |
| `kb-rebound` | kb.rebound | streaming | Rebound training question read |
| `reading-cached` | reading.play | cached | Reading list with pre-generated audio |
| `reading-uncached` | reading.play | streaming | Reading list via TTS streaming |
| `reading-resume` | reading.resume | cached | Resume paused reading list item |

**Suites:**
- `quick`: session-cold-start, kb-oral-uncached, reading-cached, reading-uncached (4 scenarios)
- `full`: All 9 scenarios

## Baselines and Regression Detection

Baselines are JSON files stored in `server/ttfa_harness/baselines/`.

**Thresholds:**
- Minor: >10% increase from baseline
- Moderate: >20% increase
- Severe: >50% increase
- Absolute ceiling: Any TTFA > 1000ms is automatic SEVERE

```bash
# List saved baselines
python -m ttfa_harness.cli --list-baselines

# Create baseline
python -m ttfa_harness.cli --suite full --create-baseline v1.0

# Compare and fail on regression
python -m ttfa_harness.cli --suite quick --baseline v1.0 --fail-on-regression
```

## In-App Instrumentation Points

The `TTFAInstrumentation` actor emits events at these points:

| Event | When Emitted | Emitting Code |
|---|---|---|
| `ACTIVATE` | User triggers a feature | Feature entry points (SessionView, ReadingPlaybackService, KBVoiceCoordinator, etc.) |
| `TTS_FIRST` | First TTS audio chunk received | KBOnDeviceTTS, KBVoiceCoordinator, ReadingPlaybackService, SessionView |
| `AUDIO_SCHEDULED` | Buffer scheduled to AVAudioPlayerNode | AudioEngine.playAudio(), AudioEngine.playRawAudio() |
| `AUDIO_PLAYING` | playerNode.play() called | AudioEngine.playAudio(), AudioEngine.playRawAudio() |
| `CACHED_HIT` | Audio served from cache | ReadingPlaybackService, KBVoiceCoordinator |
| `ERROR` | Feature failed to produce audio | TTFAInstrumentation.markError() |

Log format: `[TTFA] EVENT|feature_id|elapsed_ms|metadata`

## Module Structure

```
server/ttfa_harness/
├── __init__.py          # Package init
├── __main__.py          # python -m entry point
├── models.py            # Dataclass models (scenarios, events, results, baselines)
├── parser.py            # os_log event parser
├── simulator.py         # Simulator control (xcrun simctl)
├── baselines.py         # Baseline management and regression detection
├── cli.py               # CLI entry point and reporting
├── baselines/           # Saved baseline JSON files
└── tests/
    ├── test_parser.py   # Parser unit tests
    ├── test_models.py   # Model unit tests
    └── test_baselines.py # Baseline management tests
```

## Running Tests

```bash
cd server
PYTHONPATH=. pytest ttfa_harness/tests/ -v
```

## Adding New Features

To instrument a new audio-producing feature:

1. Add a case to `TTFAFeature` enum in `TTFAInstrumentation.swift`
2. Add `markActivation(.newFeature)` at the user action point
3. Add `markTTSFirstChunk()` where the first audio chunk arrives
4. AudioEngine handles `AUDIO_SCHEDULED` and `AUDIO_PLAYING` automatically
5. Add a scenario to `get_predefined_scenarios()` in `models.py`
6. Add the scenario ID to the appropriate suite in `SUITES`
7. Run the tests: `pytest ttfa_harness/tests/ -v`

## Exit Codes

- `0`: All scenarios under 1000ms target, no regressions
- `1`: At least one scenario failed or regression detected
