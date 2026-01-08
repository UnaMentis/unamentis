# Latency Test Harness - Server Component

Python-based orchestration for systematic latency testing across iOS and web clients.

## Purpose

Enable systematic exploration of voice pipeline latency across:
- Multiple STT providers (Deepgram, AssemblyAI, Apple, GLM-ASR, Groq)
- Multiple LLM providers (Anthropic, OpenAI, self-hosted, MLX)
- Multiple TTS providers (Chatterbox, VibeVoice, ElevenLabs, Apple, Piper)
- Network condition simulations (localhost, WiFi, cellular)

## Key Components

| File | Purpose |
|------|---------|
| `models.py` | Data models (TestConfiguration, TestResult, TestRun, PerformanceBaseline) |
| `orchestrator.py` | Test orchestration, client management, job scheduling |
| `analyzer.py` | Results analysis, statistics, regression detection, recommendations |
| `storage.py` | Persistence layer (file-based and PostgreSQL) |
| `cli.py` | Command-line interface for CI/CD and local testing |

## Running Tests

```bash
# List available suites
cd server && python -m latency_harness.cli --list-suites

# Run quick validation (mock client, ~2 min)
cd server && python -m latency_harness.cli --suite quick_validation --mock

# Run quick validation (real clients, ~5 min)
cd server && python -m latency_harness.cli --suite quick_validation --no-mock

# Run provider comparison (comprehensive, ~30 min)
cd server && python -m latency_harness.cli --suite provider_comparison --mock --timeout 600

# CI mode with regression checking
cd server && python -m latency_harness.cli --suite quick_validation --ci --baseline prod_v1 --fail-on-regression --output json
```

## Storage Configuration

### PostgreSQL (RECOMMENDED for autonomous AI testing)

```bash
export LATENCY_STORAGE_TYPE=postgresql
export LATENCY_DATABASE_URL=postgresql://user:pass@localhost/unamentis
```

Benefits:
- Concurrent access (multiple AI agents can run tests simultaneously)
- Persistent history across sessions
- Rich querying for trend analysis
- Transaction safety for reliable regression detection

### File-based (development)

```bash
export LATENCY_STORAGE_TYPE=file
# Data stored in server/data/latency_harness/
```

## API Integration

The harness exposes REST endpoints via the Management API (port 8766):

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/latency-tests/suites` | List available test suites |
| POST | `/api/latency-tests/runs` | Start new test run |
| GET | `/api/latency-tests/runs/{id}` | Get run status and progress |
| GET | `/api/latency-tests/runs/{id}/analysis` | Get analysis report |
| GET | `/api/latency-tests/runs/{id}/export` | Export results (CSV/JSON) |
| GET | `/api/latency-tests/baselines` | List performance baselines |
| POST | `/api/latency-tests/baselines` | Create baseline from run |
| WS | `/api/latency-tests/ws` | Real-time WebSocket updates |

## Observer Effect Mitigation

**Critical design principle:** The act of measuring must not introduce latency.

All reporting and persistence is designed to be fire-and-forget:
- Results queued in memory during test execution
- Background workers handle persistence asynchronously
- WebSocket broadcasts use `asyncio.create_task()` (non-blocking)
- Short timeouts on network operations (never block indefinitely)

```python
# Good: Fire-and-forget result enqueueing
queue.put_nowait((run_id, result))  # Returns immediately

# Bad: Synchronous persistence (blocks next test)
await storage.save_result(result)  # DON'T DO THIS IN TEST LOOP
```

## Autonomous AI Agent Usage

AI agents can run tests without human intervention:

### Decision Tree

```
Has provider code changed? -> Yes -> Run quick_validation --no-mock
                           -> No  -> Run quick_validation --mock

Did validation fail?       -> Yes -> Run provider_comparison for investigation
                           -> No  -> Proceed with work
```

### Interpreting Results

Parse `--output json` for automated decisions:

```json
{
  "summary": {
    "median_e2e_ms": 423.5,    // Target: <500ms
    "p99_e2e_ms": 892.3,       // Target: <1000ms
    "success_rate": 100.0
  },
  "has_regressions": false
}
```

Success criteria:
- `median_e2e_ms < 500` - Median target met
- `p99_e2e_ms < 1000` - P99 target met
- `success_rate == 100` - All tests passed
- `has_regressions == false` - No regression from baseline

### Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | Proceed with work |
| 1 | Failure or regression | Investigate, do not commit |
| 2 | Timeout | Increase timeout, check providers |

## Adding Test Suites

Test suites are defined programmatically:

```python
from latency_harness.models import (
    TestSuiteDefinition,
    TestScenario,
    ParameterSpace,
    STTTestConfig,
    LLMTestConfig,
    TTSTestConfig,
)

my_suite = TestSuiteDefinition(
    id="my_custom_suite",
    name="My Custom Suite",
    scenarios=[
        TestScenario(
            id="greeting",
            name="Simple Greeting",
            scenario_type=ScenarioType.TEXT_INPUT,
            repetitions=10,
            user_utterance_text="Hello, how are you?",
            expected_response_type=ResponseType.SHORT,
        ),
    ],
    parameter_space=ParameterSpace(
        stt_configs=[STTTestConfig(provider="deepgram")],
        llm_configs=[LLMTestConfig(provider="anthropic", model="claude-3-5-haiku-20241022")],
        tts_configs=[TTSTestConfig(provider="chatterbox")],
    ),
)

await orchestrator.register_suite(my_suite)
```

## Documentation

- Usage Guide: `docs/LATENCY_TEST_HARNESS_GUIDE.md`
- Architecture: `docs/design/AUDIO_LATENCY_TEST_HARNESS.md`
