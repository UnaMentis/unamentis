# Latency Test Harness - Complete Usage Guide

This guide covers everything you need to use, configure, troubleshoot, and extend the UnaMentis Audio Latency Test Harness.

**Related Documentation:**
- [Architectural Design](design/AUDIO_LATENCY_TEST_HARNESS.md) - Deep dive into system architecture
- [iOS Style Guide](IOS_STYLE_GUIDE.md) - Swift coding standards

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Running Tests](#running-tests)
3. [Test Suite Configuration](#test-suite-configuration)
4. [Understanding Results](#understanding-results)
5. [Operations Console UI](#operations-console-ui)
6. [CLI Reference](#cli-reference)
7. [AI Agent Usage](#ai-agent-usage)
8. [API Reference](#api-reference)
9. [Troubleshooting](#troubleshooting)
10. [Extending the Harness](#extending-the-harness)
11. [Performance Tuning](#performance-tuning)

---

## Quick Start

### Prerequisites

```bash
# Server dependencies
cd server
pip install aiohttp asyncpg pytest pytest-asyncio

# Start the management server
python -m management.server
```

### Run Your First Test

```bash
# List available test suites
python -m latency_harness.cli --list-suites

# Run quick validation (uses mock client)
python -m latency_harness.cli --suite quick_validation --mock --output text
```

### View Results in UI

1. Open http://localhost:3000 (Operations Console)
2. Navigate to **Operations → Latency Tests**
3. View test runs, start new tests, analyze results

---

## Running Tests

### Method 1: Operations Console UI

The web UI provides the easiest way to run and monitor tests:

1. **Start a Test Run:**
   - Select a test suite from the dropdown
   - Optionally select a specific client
   - Click "Start Run"

2. **Monitor Progress:**
   - Watch real-time progress bar
   - See individual test results as they complete
   - Cancel if needed

3. **Analyze Results:**
   - Click "Analysis" on completed runs
   - View latency breakdown by stage
   - Export to CSV for further analysis

### Method 2: CLI (Recommended for CI/CD)

```bash
# Basic test run
python -m latency_harness.cli --suite quick_validation

# With specific options
python -m latency_harness.cli \
  --suite provider_comparison \
  --timeout 600 \
  --output json \
  --ci

# Check for regressions against baseline
python -m latency_harness.cli \
  --suite quick_validation \
  --baseline baseline_20240115 \
  --regression-threshold 0.15 \
  --fail-on-regression
```

### Method 3: REST API

```bash
# Start a test run
curl -X POST http://localhost:8766/api/latency-tests/runs \
  -H "Content-Type: application/json" \
  -d '{"suiteId": "quick_validation"}'

# Check run status
curl http://localhost:8766/api/latency-tests/runs/{run_id}

# Get analysis
curl http://localhost:8766/api/latency-tests/runs/{run_id}/analysis
```

### Method 4: WebSocket (Real-time Updates)

```javascript
const ws = new WebSocket('ws://localhost:8766/api/latency-tests/ws');

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  switch (msg.type) {
    case 'test_progress':
      console.log(`Progress: ${msg.data.completed}/${msg.data.total}`);
      break;
    case 'test_result':
      console.log(`Result: ${msg.data.e2eLatencyMs}ms`);
      break;
    case 'run_complete':
      console.log('Run finished!');
      break;
  }
};
```

---

## Test Suite Configuration

### Built-in Test Suites

| Suite ID | Purpose | Tests | Duration |
|----------|---------|-------|----------|
| `quick_validation` | Fast smoke test | ~30 | ~2 min |
| `provider_comparison` | Compare all providers | ~200+ | ~15 min |

### Creating Custom Test Suites

Test suites are defined in Python using dataclasses:

```python
from latency_harness.models import (
    TestSuiteDefinition,
    TestScenario,
    ParameterSpace,
    STTTestConfig,
    LLMTestConfig,
    TTSTestConfig,
    NetworkProfile,
    ScenarioType,
    ResponseType,
)

# Define your custom suite
custom_suite = TestSuiteDefinition(
    id="my_custom_suite",
    name="My Custom Test Suite",
    description="Tests specific to my use case",

    # Define test scenarios
    scenarios=[
        TestScenario(
            id="greeting",
            name="Simple Greeting",
            description="User says hello",
            scenario_type=ScenarioType.TEXT_INPUT,
            repetitions=10,  # Run 10 times for statistical significance
            user_utterance_text="Hello, how are you today?",
            expected_response_type=ResponseType.SHORT,
        ),
        TestScenario(
            id="complex_question",
            name="Complex Explanation",
            description="User asks for detailed explanation",
            scenario_type=ScenarioType.TEXT_INPUT,
            repetitions=5,
            user_utterance_text="Explain the process of photosynthesis in detail.",
            expected_response_type=ResponseType.LONG,
        ),
    ],

    # Network conditions to test
    network_profiles=[
        NetworkProfile.LOCALHOST,      # +0ms
        NetworkProfile.WIFI,           # +10ms
        NetworkProfile.CELLULAR_US,    # +50ms
    ],

    # Parameter combinations to explore
    parameter_space=ParameterSpace(
        stt_configs=[
            STTTestConfig(provider="deepgram"),
            STTTestConfig(provider="apple"),
        ],
        llm_configs=[
            LLMTestConfig(provider="anthropic", model="claude-3-5-haiku-20241022"),
            LLMTestConfig(provider="selfhosted", model="qwen2.5:7b"),
        ],
        tts_configs=[
            TTSTestConfig(provider="chatterbox"),
            TTSTestConfig(provider="apple"),
        ],
    ),
)

# Register with orchestrator
await orchestrator.register_suite(custom_suite)
```

### Configuration Options Reference

#### STTTestConfig

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `provider` | str | required | Provider ID: `deepgram`, `assemblyai`, `apple`, `whisper` |
| `model` | str | None | Model variant (provider-specific) |
| `chunk_size_ms` | int | None | Audio chunk size for streaming |
| `language` | str | `"en-US"` | Recognition language |

#### LLMTestConfig

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `provider` | str | required | `anthropic`, `openai`, `selfhosted` |
| `model` | str | required | Model ID (e.g., `claude-3-5-haiku-20241022`) |
| `max_tokens` | int | 512 | Maximum response tokens |
| `temperature` | float | 0.7 | Sampling temperature |
| `top_p` | float | None | Nucleus sampling threshold |
| `stream` | bool | True | Enable streaming (always True for latency tests) |

#### TTSTestConfig

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `provider` | str | required | `chatterbox`, `vibevoice`, `apple`, `elevenlabs` |
| `voice_id` | str | None | Voice identifier |
| `speed` | float | 1.0 | Speech rate multiplier |
| `use_streaming` | bool | True | Enable audio streaming |
| `chatterbox_config` | ChatterboxConfig | None | Chatterbox-specific settings |

#### ChatterboxConfig (for Chatterbox TTS)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `exaggeration` | float | 0.5 | Expressiveness (0.0-1.0) |
| `cfg_weight` | float | 0.5 | Classifier-free guidance |
| `speed` | float | 1.0 | Speech rate |
| `enable_paralinguistic_tags` | bool | False | Enable [laugh], [sigh] etc. |
| `use_multilingual` | bool | False | Use multilingual model |
| `language` | str | `"en"` | Target language |
| `seed` | int | None | Random seed for reproducibility |

#### NetworkProfile

| Profile | Added Latency | Use Case |
|---------|--------------|----------|
| `LOCALHOST` | +0ms | Development baseline |
| `WIFI` | +10ms | Home/office WiFi |
| `CELLULAR_US` | +50ms | US mobile network |
| `CELLULAR_INTL` | +150ms | International mobile |
| `SATELLITE` | +600ms | Satellite connection |

---

## Understanding Results

### Key Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| **E2E Latency** | <500ms median | Total time from user speech end to audio playback start |
| **STT Latency** | <200ms | Speech-to-text recognition time |
| **LLM TTFB** | <300ms | Time to first token from LLM |
| **LLM Completion** | varies | Total LLM generation time |
| **TTS TTFB** | <150ms | Time to first audio byte from TTS |
| **TTS Completion** | varies | Total audio generation time |

### Interpreting the Analysis Report

```json
{
  "summary": {
    "totalConfigurations": 24,
    "totalTests": 240,
    "successfulTests": 238,
    "failedTests": 2,
    "overallMedianE2EMs": 423.5,     // ✅ Under 500ms target
    "overallP99E2EMs": 892.3,        // ✅ Under 1000ms target
    "overallMinE2EMs": 312.1,
    "overallMaxE2EMs": 1245.8        // ⚠️ Outlier - investigate
  },
  "bestConfigurations": [
    {
      "rank": 1,
      "configId": "deepgram_haiku_chatterbox",
      "medianE2EMs": 387.2,
      "p99E2EMs": 654.1,
      "breakdown": {
        "sttMs": 89.3,
        "llmTTFBMs": 156.2,
        "llmCompletionMs": 423.1,
        "ttsTTFBMs": 78.4,
        "ttsCompletionMs": 312.5
      }
    }
  ],
  "networkProjections": [
    {
      "network": "WiFi (+10ms)",
      "projectedMedianMs": 433.5,
      "meetsTarget": true
    },
    {
      "network": "Cellular US (+50ms)",
      "projectedMedianMs": 473.5,
      "meetsTarget": true
    }
  ],
  "recommendations": [
    "Best configuration: deepgram_haiku_chatterbox with 387ms median E2E",
    "Target of <500ms median achieved on localhost",
    "Consider Chatterbox TTS for lowest TTFB"
  ]
}
```

### Network-Adjusted Results

The harness automatically projects localhost results to real-world network conditions:

```
Localhost Result: 400ms E2E
├── WiFi Projection: 400 + 10ms = 410ms ✅ meets target
├── Cellular US Projection: 400 + 50ms = 450ms ✅ meets target
└── Satellite Projection: 400 + 600ms = 1000ms ❌ exceeds target
```

### Regression Detection

When comparing against a baseline:

```python
# Severity levels
MINOR = change < 10%      # Acceptable variance
MODERATE = 10% <= change < 20%  # Worth investigating
SEVERE = change >= 20%    # Likely regression
```

---

## Operations Console UI

### Accessing the Dashboard

1. Start the web server: `cd server/web && npm run dev`
2. Open http://localhost:3000
3. Navigate to **Operations → Latency Tests**

### Dashboard Features

#### Test Suites Panel
- View all registered test suites
- See test count and estimated duration
- Upload custom suite definitions

#### Active Runs Panel
- Real-time progress tracking
- Per-test result streaming
- Cancel running tests

#### Run History
- Filter by status, suite, date
- Quick access to analysis
- Export results (CSV, JSON)

#### Analysis Modal
- Latency breakdown by stage
- Best configurations ranking
- Network projections
- Recommendations

#### Connected Clients
- View all test clients
- Client capabilities display
- Connection status

---

## CLI Reference

```
python -m latency_harness.cli [OPTIONS]

Options:
  --suite TEXT              Test suite ID to run
  --list-suites             List available test suites
  --timeout INT             Test timeout in seconds (default: 300)
  --mock / --no-mock        Use mock client (default: --mock)
  --baseline TEXT           Baseline ID for regression checking
  --regression-threshold FLOAT
                            Regression threshold (default: 0.2 = 20%)
  --output [text|json]      Output format (default: text)
  --data-dir PATH           Data directory for storage
  --ci                      CI mode - exit with non-zero code on failure
  --fail-on-regression      Exit with non-zero code if regressions detected
  --help                    Show this message and exit

Examples:
  # List suites
  python -m latency_harness.cli --list-suites

  # Run quick validation
  python -m latency_harness.cli --suite quick_validation

  # CI mode with regression check
  python -m latency_harness.cli \
    --suite quick_validation \
    --ci \
    --baseline prod_baseline_v1 \
    --fail-on-regression

Exit Codes:
  0 - Success
  1 - Test failure or regression detected
  2 - Timeout
```

---

## AI Agent Usage

This section covers autonomous usage by AI agents (Claude Code, Cursor, etc.) for automated latency validation.

### Autonomous Workflow

AI agents should follow this workflow when making provider or performance-sensitive changes:

```
1. BEFORE making changes:
   python -m latency_harness.cli --suite quick_validation --mock
   (Smoke test - verifies harness infrastructure works)

2. AFTER making changes:
   python -m latency_harness.cli --suite quick_validation --no-mock --output json
   (Real provider test with parseable output)

3. IF regressions detected:
   python -m latency_harness.cli --suite provider_comparison --no-mock
   (Full investigation to identify bottleneck)
```

### Decision Matrix

| Scenario | Suite | Mode | Expected Duration |
|----------|-------|------|-------------------|
| Quick infrastructure check | `quick_validation` | `--mock` | ~30 seconds |
| Post-change validation | `quick_validation` | `--no-mock` | ~2 minutes |
| Performance investigation | `provider_comparison` | `--no-mock` | ~30 minutes |
| CI/CD pipeline | `quick_validation` | `--mock --ci` | ~30 seconds |

### Parsing JSON Output

For programmatic analysis, use JSON output:

```bash
python -m latency_harness.cli --suite quick_validation --output json > results.json
```

Key fields to check:
```json
{
  "summary": {
    "overallMedianE2EMs": 423.5,    // Must be <500ms
    "overallP99E2EMs": 892.3,       // Must be <1000ms
    "failedTests": 0                 // Must be 0
  },
  "regressions": []                  // Must be empty
}
```

### Automated Regression Check

```bash
# Returns exit code 1 if regressions detected
python -m latency_harness.cli \
  --suite quick_validation \
  --no-mock \
  --ci \
  --fail-on-regression

# Check exit code
if [ $? -eq 0 ]; then
  echo "No regressions detected"
else
  echo "Regressions detected - investigate!"
fi
```

### Mock vs Real Mode

**Mock mode (`--mock`) is acceptable for AI agents because:**
- Validates test infrastructure without external dependencies
- Fast execution for quick feedback loops
- Deterministic results (no network variance)
- Zero cost (no API calls)

**Real mode (`--no-mock`) is required when:**
- Validating actual provider performance
- Creating baselines for regression detection
- After changes to provider implementations
- Investigating performance issues

### Error Handling

| Exit Code | Meaning | AI Agent Action |
|-----------|---------|-----------------|
| 0 | Success | Continue work |
| 1 | Failure or regression | Investigate, run provider_comparison |
| 2 | Timeout | Increase timeout, check network |

### Baseline Management for Agents

```bash
# Create baseline after successful real-provider test
curl -X POST http://localhost:8766/api/latency-tests/baselines \
  -H "Content-Type: application/json" \
  -d '{"runId": "run_xxx", "name": "post-change baseline", "setActive": true}'

# Check new run against baseline
curl -s "http://localhost:8766/api/latency-tests/baselines/{id}/check?runId=run_yyy" | \
  python -c "import json,sys; d=json.load(sys.stdin); exit(1 if d['summary']['regressedConfigs'] > 0 else 0)"
```

### Pre-Approved Commands

The following commands are pre-approved in `.claude/settings.local.json` and do not require user confirmation:

```bash
# All latency harness CLI commands
python -m latency_harness.cli [any options]

# REST API calls
curl http://localhost:8766/api/latency-tests/*
```

See `server/latency_harness/CLAUDE.md` for detailed autonomous usage guidance.

---

## API Reference

### Base URL
```
http://localhost:8766/api/latency-tests
```

### Endpoints

#### Test Suites

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/suites` | List all test suites |
| GET | `/suites/{id}` | Get suite details |
| POST | `/suites` | Upload custom suite |
| DELETE | `/suites/{id}` | Delete suite |

#### Test Runs

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/runs` | List runs (paginated) |
| POST | `/runs` | Start new run |
| GET | `/runs/{id}` | Get run details |
| DELETE | `/runs/{id}` | Cancel/delete run |
| GET | `/runs/{id}/results` | Get all results |
| GET | `/runs/{id}/analysis` | Get analysis report |
| GET | `/runs/{id}/export` | Export (CSV/JSON) |

#### Clients

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/clients` | List connected clients |
| POST | `/clients/{id}/heartbeat` | Client heartbeat |
| POST | `/clients/{id}/results` | Submit batch results |

#### Baselines

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/baselines` | List baselines |
| POST | `/baselines` | Create from run |
| GET | `/baselines/{id}/check` | Check regression |

#### WebSocket

| Endpoint | Description |
|----------|-------------|
| `/ws` | Real-time updates |

---

## Troubleshooting

### Common Issues

#### "No available clients" error

**Cause:** No test client is connected to the orchestrator.

**Solutions:**
1. Use `--mock` flag for CLI testing
2. Start an iOS Simulator with the test app
3. Open the web client at http://localhost:3000

#### Results seem too fast/slow

**Cause:** Mock client returns simulated results.

**Solution:** Use real clients for accurate measurements:
```bash
# Disable mock mode
python -m latency_harness.cli --suite quick_validation --no-mock
```

#### WebSocket disconnects frequently

**Cause:** Network instability or server overload.

**Solutions:**
1. Check server logs for errors
2. Reduce concurrent tests
3. Increase heartbeat timeout

#### Tests timeout

**Cause:** Provider latency or network issues.

**Solutions:**
1. Increase timeout: `--timeout 600`
2. Check provider health in Operations Console
3. Verify network connectivity to external APIs

#### Inconsistent results between runs

**Cause:** System load, thermal throttling, or network variance.

**Solutions:**
1. Increase repetitions per scenario (e.g., 20 instead of 10)
2. Run on dedicated hardware
3. Check thermal state in results
4. Use statistical aggregates (median, P99) not individual tests

### Debug Mode

Enable verbose logging:

```python
import logging
logging.getLogger('latency_harness').setLevel(logging.DEBUG)
```

Or via environment variable:
```bash
LOG_LEVEL=DEBUG python -m latency_harness.cli --suite quick_validation
```

### Inspecting Raw Data

```bash
# File-based storage location
ls server/data/latency_harness/
├── suites/
│   ├── quick_validation.json
│   └── provider_comparison.json
├── runs/
│   └── run_20240115_143022_abc123.json
└── baselines/
    └── prod_baseline_v1.json
```

---

## Extending the Harness

### Adding a New Provider

1. **Define the config:**

```python
# In models.py, add to STTTestConfig, LLMTestConfig, or TTSTestConfig
@dataclass
class MyNewProviderConfig:
    api_key: str
    model: str
    custom_param: float = 0.5
```

2. **Implement the service adapter:**

```swift
// In iOS client
class MyNewSTTService: STTService {
    func transcribe(audio: AudioData) async throws -> String {
        // Implementation
    }
}
```

3. **Register in coordinator:**

```swift
// In LatencyTestCoordinator.swift
private func createSTTService(_ config: STTTestConfig) async throws -> any STTService {
    switch config.provider {
    case "my_new_provider":
        return MyNewSTTService(config: config)
    // ...
    }
}
```

### Adding Custom Metrics

1. **Extend TestResult:**

```python
@dataclass
class TestResult:
    # Existing fields...

    # Add your custom metric
    my_custom_metric: Optional[float] = None
```

2. **Record in collector:**

```swift
// In LatencyMetricsCollector.swift
public func recordMyCustomMetric(_ value: Double) {
    myCustomMetric = value
}
```

3. **Include in analysis:**

```python
# In analyzer.py
def analyze(self, run: TestRun) -> AnalysisReport:
    # Add to summary
    custom_metrics = [r.my_custom_metric for r in run.results if r.my_custom_metric]
    summary.my_custom_metric_median = statistics.median(custom_metrics)
```

### Creating Custom Analyzers

```python
from latency_harness.analyzer import ResultsAnalyzer

class MyCustomAnalyzer(ResultsAnalyzer):
    def analyze(self, run: TestRun) -> AnalysisReport:
        report = super().analyze(run)

        # Add custom analysis
        report.custom_insights = self._generate_insights(run)

        return report

    def _generate_insights(self, run: TestRun) -> List[str]:
        insights = []

        # Example: detect provider-specific patterns
        by_provider = self._group_by_provider(run.results)
        for provider, results in by_provider.items():
            median = statistics.median([r.e2e_latency_ms for r in results])
            if median > 500:
                insights.append(f"{provider} exceeds target: {median:.0f}ms")

        return insights
```

---

## Performance Tuning

### Optimizing Test Execution

1. **Reduce test count for faster iterations:**
```python
TestScenario(
    repetitions=5,  # Fewer reps during development
    # ...
)
```

2. **Limit parameter combinations:**
```python
ParameterSpace(
    stt_configs=[STTTestConfig(provider="deepgram")],  # Single provider
    llm_configs=[LLMTestConfig(provider="selfhosted", model="qwen2.5:7b")],
    tts_configs=[TTSTestConfig(provider="chatterbox")],
)
```

3. **Use localhost only for initial testing:**
```python
network_profiles=[NetworkProfile.LOCALHOST]  # Skip network projections
```

### Optimizing Storage

For high-volume testing, use PostgreSQL instead of file storage:

```bash
export LATENCY_STORAGE_TYPE=postgresql
export LATENCY_DATABASE_URL=postgresql://user:pass@localhost/unamentis
```

### Reducing Observer Effect

The harness is designed to minimize measurement overhead, but be aware:

1. **CPU sampling** runs every 100ms - acceptable overhead
2. **Result queue** batches every 2s - no impact on tests
3. **WebSocket broadcasts** are fire-and-forget - no blocking

If you need absolute minimal overhead:
```python
# Disable resource sampling
metricsCollector.samplingIntervalMs = 0  # Disables CPU/memory sampling
```

---

## Appendix: File Structure

```
server/
├── latency_harness/
│   ├── __init__.py         # Module exports
│   ├── models.py           # Data models (TestResult, TestRun, etc.)
│   ├── orchestrator.py     # Test execution coordination
│   ├── analyzer.py         # Results analysis and statistics
│   ├── storage.py          # Persistence layer (file + PostgreSQL)
│   └── cli.py              # Command-line interface
├── management/
│   ├── latency_harness_api.py  # REST API endpoints
│   └── server.py           # Main server (imports harness)
└── web/
    └── src/
        ├── lib/latency-harness/
        │   ├── types.ts    # TypeScript type definitions
        │   └── web-coordinator.ts  # Web client coordinator
        └── components/dashboard/
            └── latency-harness-panel.tsx  # UI dashboard

UnaMentis/
└── Testing/
    └── LatencyHarness/
        ├── TestConfiguration.swift    # Swift config models
        ├── TestResult.swift           # Swift result models
        ├── LatencyMetricsCollector.swift  # High-precision timing
        └── LatencyTestCoordinator.swift   # iOS test execution

docs/
├── LATENCY_TEST_HARNESS_GUIDE.md  # This file
└── design/
    └── AUDIO_LATENCY_TEST_HARNESS.md  # Architectural design
```
