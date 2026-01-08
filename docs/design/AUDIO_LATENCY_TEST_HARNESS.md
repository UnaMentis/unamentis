# Audio Latency Test Harness - Architectural Design

## Executive Summary

This document proposes a first-class latency optimization test harness for UnaMentis. The system enables systematic parameter exploration across the entire audio pipeline (STT → LLM → TTS), automated benchmarking, and data-driven optimization decisions for new model integrations.

## Problem Statement

UnaMentis targets **sub-500ms median latency** for voice interactions. Achieving this requires:
1. Systematic testing of provider/model combinations
2. Fine-tuning of dozens of parameters across 3+ pipeline stages
3. Accounting for real-world network conditions
4. Continuous regression testing as new models are introduced

Current state: Latency is tracked via TelemetryEngine, but no systematic exploration or optimization infrastructure exists.

---

## Critical: Observer Effect Mitigation

**The act of measuring latency must not introduce latency.**

This is a fundamental principle of the harness design. All observation, logging, and reporting mechanisms are designed to be **fire-and-forget** - they queue data for asynchronous processing and never block the test execution path.

### Key Architectural Decisions

1. **Timing Capture is Zero-Overhead**
   - iOS: Uses `mach_absolute_time()` (nanosecond precision, no syscalls)
   - Web: Uses `performance.now()` (microsecond precision)
   - No network I/O in the timing path

2. **Result Collection is In-Memory**
   - Results stored in local arrays during test execution
   - No database writes or network calls between test iterations

3. **Reporting is Asynchronous**
   - `ResultReporter` actor queues results in background
   - Batched sends every 2 seconds (configurable)
   - Short timeouts (5s) - never blocks indefinitely
   - Failed sends are logged, not retried endlessly

4. **Server Persistence is Fire-and-Forget**
   - `_enqueue_result()` returns immediately
   - Background `_persistence_worker()` batches and writes
   - Status updates are coalesced (only latest persisted)

5. **WebSocket Broadcasts are Non-Blocking**
   - Uses `asyncio.create_task()` for all broadcasts
   - Client disconnects don't block test execution

### Anti-Patterns to Avoid

```python
# ❌ BAD: Synchronous persistence between tests
for config in configurations:
    result = await run_test(config)
    await storage.save_result(result)  # BLOCKS NEXT TEST!
    await broadcast_to_clients(result)  # BLOCKS NEXT TEST!

# ✅ GOOD: Fire-and-forget with queue
for config in configurations:
    result = await run_test(config)
    queue.put_nowait((run_id, result))  # Returns immediately
```

---

## Two Operating Modes

### Mode 1: Curriculum Delivery
- Server delivers pre-structured curriculum content
- **Optimization opportunity**: Pre-fetch, pre-generate TTS, queue audio chunks
- Latency target: Near-zero perceived latency (audio ready before needed)
- Test focus: Prefetch timing, buffer depth, sentence boundary prediction

### Mode 2: Interactive/Barge-in
- User interrupts at any time for real-time conversation
- Full pipeline engaged: STT → LLM → TTS
- **Cannot pre-fetch** - latency is cumulative
- Latency target: <500ms (median), <1000ms (P99)
- Test focus: Per-stage optimization, provider selection, parameter tuning

---

## Architecture Overview

### Multi-Client Design Philosophy

The test harness supports **multiple client types** with a unified orchestration layer:
- **iOS Simulator** - For iOS-specific testing (audio engine, CoreML VAD, device metrics)
- **iOS Device** - Real hardware testing with actual network conditions
- **Web Client** - Browser-based testing (Next.js frontend)

This "translation approach" ensures:
1. **No single point of failure** - Tests can run on any available client
2. **Cross-platform validation** - Same test scenarios verified on multiple platforms
3. **Platform-specific insights** - Identify iOS vs Web performance differences
4. **Flexibility** - Use simulators for rapid iteration, devices for production validation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Test Harness Controller                              │
│                     (Server: Python/Management API)                          │
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────────────────┐ │
│  │ Test Definition │  │ Parameter Space  │  │ Results Analyzer            │ │
│  │ (YAML/JSON)     │  │ Explorer         │  │ - Statistical analysis      │ │
│  │                 │  │ - Grid search    │  │ - Percentile calculations   │ │
│  │ - Scenarios     │  │ - Random search  │  │ - Network-adjusted results  │ │
│  │ - Parameters    │  │ - Bayesian opt   │  │ - Regression detection      │ │
│  │ - Constraints   │  │   (future)       │  │ - Report generation         │ │
│  └────────┬────────┘  └────────┬─────────┘  └──────────────┬──────────────┘ │
│           │                    │                           │                 │
│           └────────────────────┼───────────────────────────┘                 │
│                                │                                             │
│                    ┌───────────▼───────────┐                                │
│                    │   Test Orchestrator   │                                │
│                    │   - Job scheduling    │                                │
│                    │   - Client selection  │◄──── Supports multiple clients │
│                    │   - Result collection │                                │
│                    │   - Cross-platform    │                                │
│                    └───────────┬───────────┘                                │
└────────────────────────────────┼────────────────────────────────────────────┘
                                 │ REST API / WebSocket
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  iOS Simulator  │   │   iOS Device    │   │   Web Client    │
│    Client       │   │    Client       │   │  (Next.js)      │
├─────────────────┤   ├─────────────────┤   ├─────────────────┤
│ Swift/XCTest    │   │ Swift App       │   │ TypeScript/     │
│ LatencyTest     │   │ LatencyTest     │   │ React           │
│ Coordinator     │   │ Coordinator     │   │ LatencyTest     │
│                 │   │                 │   │ Coordinator     │
├─────────────────┤   ├─────────────────┤   ├─────────────────┤
│ STT: All        │   │ STT: All        │   │ STT: WebRTC/    │
│ LLM: All        │   │ LLM: All        │   │      Cloud only │
│ TTS: All        │   │ TTS: All        │   │ LLM: All        │
│ VAD: Silero/    │   │ VAD: Silero/    │   │ TTS: Cloud +    │
│      CoreML     │   │      CoreML     │   │      Web Audio  │
├─────────────────┤   ├─────────────────┤   ├─────────────────┤
│ Metrics:        │   │ Metrics:        │   │ Metrics:        │
│ - mach_time     │   │ - mach_time     │   │ - performance   │
│ - CPU/Memory    │   │ - CPU/Memory    │   │   .now()        │
│ - Thermal state │   │ - Thermal state │   │ - Limited       │
│ - Full device   │   │ - Full device   │   │   browser APIs  │
└─────────────────┘   └─────────────────┘   └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                         Common Result Format
                         ┌───────▼───────┐
                         │  TestResult   │
                         │  (Unified)    │
                         └───────────────┘
```

### Client Abstraction Layer

All clients implement a common **TestClient** interface:

```
interface TestClient {
    clientId: string
    clientType: "ios_simulator" | "ios_device" | "web"
    capabilities: ClientCapabilities

    configure(config: TestConfiguration): Promise<void>
    executeTest(scenario: TestScenario): Promise<TestResult>
    getStatus(): ClientStatus
}

interface ClientCapabilities {
    supportedSTTProviders: STTProvider[]
    supportedLLMProviders: LLMProvider[]
    supportedTTSProviders: TTSProvider[]
    hasHighPrecisionTiming: boolean      // mach_time vs performance.now()
    hasDeviceMetrics: boolean            // CPU, memory, thermal
    hasOnDeviceML: boolean               // CoreML, MLX
    maxConcurrentTests: number
}
```

### Platform-Specific Considerations

| Capability | iOS Simulator | iOS Device | Web Client |
|------------|---------------|------------|------------|
| High-precision timing | Yes (mach_time) | Yes (mach_time) | Limited (performance.now) |
| On-device STT | Yes (Apple Speech) | Yes (Apple + GLM-ASR) | No |
| On-device LLM | Yes (MLX) | Yes (MLX) | No |
| On-device TTS | Yes (AVSpeechSynthesizer) | Yes | Limited (Web Speech API) |
| Device metrics | Partial | Full | No |
| Thermal monitoring | No | Yes | No |
| Real network conditions | No | Yes | Yes |
| Audio latency accuracy | Good | Best | Variable |
| Concurrent test capacity | High | Limited by battery | High |

---

## Component Design

### 1. Test Definition Schema (Server)

```yaml
# latency_test_suite.yaml
test_suite:
  name: "Q1 2026 Provider Evaluation"
  description: "Systematic evaluation of new TTS providers"

  # Network condition simulation
  network_profiles:
    - name: "localhost"
      added_latency_ms: 0
    - name: "wifi"
      added_latency_ms: 10
    - name: "cellular_us"
      added_latency_ms: 50
    - name: "cellular_eu"
      added_latency_ms: 70

  # Test scenarios
  scenarios:
    - name: "short_response"
      description: "User asks simple question, AI gives brief answer"
      user_utterance_audio: "test_audio/short_question.wav"
      expected_response_type: "short"  # 10-30 words
      repetitions: 10

    - name: "long_response"
      description: "User asks complex question, AI gives detailed answer"
      user_utterance_audio: "test_audio/complex_question.wav"
      expected_response_type: "long"  # 100-300 words
      repetitions: 5

    - name: "rapid_exchange"
      description: "Quick back-and-forth conversation"
      conversation_script: "test_scripts/rapid_exchange.json"
      repetitions: 3

  # Parameter space to explore
  parameter_space:
    stt:
      provider: ["deepgram", "assemblyai", "glm-asr", "apple"]
      # Provider-specific parameters
      deepgram:
        model: ["nova-3", "nova-2"]
        language: ["en-US"]
      glm_asr:
        chunk_size_ms: [100, 200, 500]

    llm:
      provider: ["anthropic", "openai", "selfhosted"]
      anthropic:
        model: ["claude-3-5-haiku-20241022", "claude-3-5-sonnet-20241022"]
        max_tokens: [256, 512, 1024]
        temperature: [0.5, 0.7]
      openai:
        model: ["gpt-4o-mini", "gpt-4o"]
        max_tokens: [256, 512]
      selfhosted:
        model: ["qwen2.5:7b", "llama3.2:3b"]

    tts:
      provider: ["chatterbox", "vibevoice", "elevenlabs", "apple"]
      chatterbox:
        exaggeration: [0.3, 0.5, 0.7]
        cfg_weight: [0.3, 0.5]
        speed: [0.9, 1.0, 1.1]
        use_streaming: [true]
      elevenlabs:
        model: ["eleven_flash_v2_5", "eleven_turbo_v2_5"]

    audio_engine:
      sample_rate: [24000, 48000]
      buffer_size: [512, 1024]
      vad_threshold: [0.4, 0.5, 0.6]

  # Constraints (filter invalid combinations)
  constraints:
    - "stt.provider == 'apple' implies audio_engine.sample_rate == 16000"
    - "tts.provider == 'chatterbox' implies audio_engine.sample_rate == 24000"
```

### 2. Test Orchestrator (Server: Python)

**Location**: `/server/latency_harness/orchestrator.py`

```python
@dataclass
class TestConfiguration:
    """A single test configuration to execute."""
    config_id: str
    scenario_name: str
    stt_config: dict
    llm_config: dict
    tts_config: dict
    audio_config: dict
    network_profile: str
    repetition: int

@dataclass
class TestResult:
    """Results from a single test execution."""
    config_id: str
    timestamp: datetime
    scenario_name: str
    repetition: int

    # Per-stage latencies (milliseconds)
    stt_latency_ms: float
    llm_ttfb_ms: float
    llm_completion_ms: float
    tts_ttfb_ms: float
    tts_completion_ms: float

    # End-to-end
    e2e_latency_ms: float

    # Network-adjusted projections
    network_profile: str
    projected_e2e_ms: dict[str, float]  # For each network profile

    # Quality metrics
    stt_confidence: float
    tts_audio_duration_ms: float

    # Resource utilization
    peak_cpu_percent: float
    peak_memory_mb: float
    thermal_state: str

    # Errors (if any)
    errors: list[str]

class LatencyTestOrchestrator:
    """Orchestrates latency test execution across iOS clients."""

    async def load_test_suite(self, path: str) -> TestSuite:
        """Load and validate test suite definition."""

    def generate_test_configurations(self, suite: TestSuite) -> list[TestConfiguration]:
        """Generate all parameter combinations (respecting constraints)."""

    async def execute_test_suite(self, suite: TestSuite, client_id: str) -> TestRun:
        """Execute full test suite on a specific iOS client."""

    async def send_configuration_to_client(self, config: TestConfiguration, client_id: str):
        """Send test configuration to iOS client via WebSocket."""

    async def collect_result(self, result: TestResult):
        """Collect and persist test result."""

    def analyze_results(self, run_id: str) -> AnalysisReport:
        """Analyze results and generate report."""
```

### 3. iOS Latency Test Coordinator

**Location**: `/UnaMentis/Testing/LatencyHarness/LatencyTestCoordinator.swift`

```swift
/// Coordinates latency test execution on iOS
public actor LatencyTestCoordinator {

    // MARK: - Configuration

    private let serverURL: URL
    private var currentConfig: TestConfiguration?
    private let metricsCollector: LatencyMetricsCollector

    // MARK: - Provider Management

    private var sttService: (any STTService)?
    private var llmService: (any LLMService)?
    private var ttsService: (any TTSService)?
    private var audioEngine: AudioEngine?

    // MARK: - Test Execution

    /// Configure providers for a test
    public func configure(with config: TestConfiguration) async throws {
        // Dynamically instantiate and configure providers
        sttService = try await createSTTService(config.stt)
        llmService = try await createLLMService(config.llm)
        ttsService = try await createTTSService(config.tts)
        audioEngine = try await createAudioEngine(config.audioEngine)
        currentConfig = config
    }

    /// Execute a single test scenario
    public func executeTest(
        scenario: TestScenario,
        repetition: Int
    ) async throws -> TestResult {
        guard let config = currentConfig else {
            throw TestError.notConfigured
        }

        let collector = metricsCollector
        await collector.startTest(configId: config.configId, repetition: repetition)

        do {
            // Phase 1: STT (if using audio input)
            let sttStart = mach_absolute_time()
            let transcript = try await runSTTPhase(scenario: scenario)
            let sttLatency = machTimeToMs(mach_absolute_time() - sttStart)
            await collector.recordSTTLatency(sttLatency)

            // Phase 2: LLM
            let llmStart = mach_absolute_time()
            var firstTokenTime: UInt64 = 0
            var fullResponse = ""

            let stream = try await llmService!.streamCompletion(
                messages: buildMessages(transcript: transcript, scenario: scenario),
                config: config.llm.toLLMConfig()
            )

            for await token in stream {
                if firstTokenTime == 0 {
                    firstTokenTime = mach_absolute_time()
                    await collector.recordLLMTTFB(machTimeToMs(firstTokenTime - llmStart))
                }
                fullResponse += token.content
            }
            let llmCompletion = machTimeToMs(mach_absolute_time() - llmStart)
            await collector.recordLLMCompletion(llmCompletion)

            // Phase 3: TTS
            let ttsStart = mach_absolute_time()
            var firstAudioTime: UInt64 = 0
            var totalAudioDuration: TimeInterval = 0

            let audioStream = try await ttsService!.synthesize(text: fullResponse)

            for await chunk in audioStream {
                if firstAudioTime == 0 {
                    firstAudioTime = mach_absolute_time()
                    await collector.recordTTSTTFB(machTimeToMs(firstAudioTime - ttsStart))
                }
                // Accumulate audio duration (for quality metrics)
                if let duration = calculateChunkDuration(chunk) {
                    totalAudioDuration += duration
                }
            }
            let ttsCompletion = machTimeToMs(mach_absolute_time() - ttsStart)
            await collector.recordTTSCompletion(ttsCompletion)

            // Calculate E2E
            let e2eLatency = sttLatency + llmCompletion + ttsCompletion
            await collector.recordE2ELatency(e2eLatency)

            return await collector.finalizeTest()

        } catch {
            await collector.recordError(error)
            return await collector.finalizeTest()
        }
    }
}
```

### 4. Latency Metrics Collector (iOS)

**Location**: `/UnaMentis/Testing/LatencyHarness/LatencyMetricsCollector.swift`

```swift
/// High-precision metrics collection for latency tests
public actor LatencyMetricsCollector {

    // MARK: - Timing Data

    private var testStartTime: UInt64 = 0
    private var configId: String = ""
    private var repetition: Int = 0

    // Stage latencies (milliseconds)
    private var sttLatencyMs: Double = 0
    private var llmTTFBMs: Double = 0
    private var llmCompletionMs: Double = 0
    private var ttsTTFBMs: Double = 0
    private var ttsCompletionMs: Double = 0
    private var e2eLatencyMs: Double = 0

    // Quality metrics
    private var sttConfidence: Float = 0
    private var ttsAudioDurationMs: Double = 0

    // Resource metrics
    private var cpuSamples: [Double] = []
    private var memorySamples: [UInt64] = []
    private var thermalStates: [ProcessInfo.ThermalState] = []

    // Errors
    private var errors: [String] = []

    // MARK: - Sampling Task

    private var samplingTask: Task<Void, Never>?

    // MARK: - API

    public func startTest(configId: String, repetition: Int) async {
        self.configId = configId
        self.repetition = repetition
        self.testStartTime = mach_absolute_time()

        // Reset all metrics
        sttLatencyMs = 0
        llmTTFBMs = 0
        llmCompletionMs = 0
        ttsTTFBMs = 0
        ttsCompletionMs = 0
        e2eLatencyMs = 0
        cpuSamples = []
        memorySamples = []
        thermalStates = []
        errors = []

        // Start resource sampling (every 100ms)
        startResourceSampling()
    }

    public func recordSTTLatency(_ ms: Double) { sttLatencyMs = ms }
    public func recordLLMTTFB(_ ms: Double) { llmTTFBMs = ms }
    public func recordLLMCompletion(_ ms: Double) { llmCompletionMs = ms }
    public func recordTTSTTFB(_ ms: Double) { ttsTTFBMs = ms }
    public func recordTTSCompletion(_ ms: Double) { ttsCompletionMs = ms }
    public func recordE2ELatency(_ ms: Double) { e2eLatencyMs = ms }
    public func recordSTTConfidence(_ conf: Float) { sttConfidence = conf }
    public func recordTTSAudioDuration(_ ms: Double) { ttsAudioDurationMs = ms }
    public func recordError(_ error: Error) { errors.append(error.localizedDescription) }

    public func finalizeTest() -> TestResult {
        stopResourceSampling()

        return TestResult(
            configId: configId,
            timestamp: Date(),
            repetition: repetition,

            sttLatencyMs: sttLatencyMs,
            llmTTFBMs: llmTTFBMs,
            llmCompletionMs: llmCompletionMs,
            ttsTTFBMs: ttsTTFBMs,
            ttsCompletionMs: ttsCompletionMs,
            e2eLatencyMs: e2eLatencyMs,

            sttConfidence: sttConfidence,
            ttsAudioDurationMs: ttsAudioDurationMs,

            peakCPUPercent: cpuSamples.max() ?? 0,
            peakMemoryMB: Double(memorySamples.max() ?? 0) / 1_000_000,
            thermalState: mostSevereThermalState(),

            errors: errors
        )
    }

    // MARK: - Resource Sampling

    private func startResourceSampling() {
        samplingTask = Task {
            while !Task.isCancelled {
                cpuSamples.append(getCurrentCPUUsage())
                memorySamples.append(getCurrentMemoryUsage())
                thermalStates.append(ProcessInfo.processInfo.thermalState)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
```

### 5. Results Analyzer (Server: Python)

**Location**: `/server/latency_harness/analyzer.py`

```python
@dataclass
class AnalysisReport:
    """Comprehensive analysis of test results."""
    run_id: str
    summary: SummaryStatistics
    per_configuration_stats: dict[str, ConfigurationStats]
    best_configurations: list[RankedConfiguration]
    regressions: list[Regression]
    network_projections: dict[str, NetworkProjection]
    recommendations: list[str]

class ResultsAnalyzer:
    """Analyzes latency test results and generates insights."""

    def analyze(self, run_id: str) -> AnalysisReport:
        results = self.load_results(run_id)

        return AnalysisReport(
            run_id=run_id,
            summary=self.compute_summary(results),
            per_configuration_stats=self.compute_per_config_stats(results),
            best_configurations=self.rank_configurations(results),
            regressions=self.detect_regressions(results),
            network_projections=self.project_for_networks(results),
            recommendations=self.generate_recommendations(results)
        )

    def project_for_networks(self, results: list[TestResult]) -> dict[str, NetworkProjection]:
        """Project localhost results to realistic network conditions."""
        network_overheads = {
            "localhost": 0,
            "wifi": 10,
            "cellular_us": 50,
            "cellular_eu": 70,
            "intercontinental": 120
        }

        projections = {}
        for network, overhead in network_overheads.items():
            projected_results = []
            for r in results:
                # Add network overhead to each stage that requires network
                projected_e2e = r.e2e_latency_ms
                if r.stt_requires_network:
                    projected_e2e += overhead
                if r.llm_requires_network:
                    projected_e2e += overhead
                if r.tts_requires_network:
                    projected_e2e += overhead
                projected_results.append(projected_e2e)

            projections[network] = NetworkProjection(
                network=network,
                added_latency_ms=overhead,
                projected_median_ms=statistics.median(projected_results),
                projected_p99_ms=percentile(projected_results, 99),
                meets_target=(statistics.median(projected_results) < 500)
            )

        return projections

    def rank_configurations(self, results: list[TestResult]) -> list[RankedConfiguration]:
        """Rank configurations by E2E latency, accounting for cost."""
        # Group by configuration
        by_config = defaultdict(list)
        for r in results:
            by_config[r.config_id].append(r)

        ranked = []
        for config_id, config_results in by_config.items():
            e2e_latencies = [r.e2e_latency_ms for r in config_results]

            ranked.append(RankedConfiguration(
                config_id=config_id,
                median_e2e_ms=statistics.median(e2e_latencies),
                p99_e2e_ms=percentile(e2e_latencies, 99),
                stddev_ms=statistics.stdev(e2e_latencies) if len(e2e_latencies) > 1 else 0,
                sample_count=len(config_results),
                estimated_cost_per_minute=self.estimate_cost(config_id)
            ))

        # Sort by median E2E (primary), then by P99 (secondary), then by cost
        ranked.sort(key=lambda x: (x.median_e2e_ms, x.p99_e2e_ms, x.estimated_cost_per_minute))

        return ranked
```

### 6. Database Schema (Server)

**Location**: `/server/latency_harness/schema.sql`

```sql
-- Test runs (a complete execution of a test suite)
CREATE TABLE IF NOT EXISTS latency_test_runs (
    id TEXT PRIMARY KEY,
    suite_name TEXT NOT NULL,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,
    client_id TEXT NOT NULL,
    client_device TEXT,
    status TEXT NOT NULL DEFAULT 'running',  -- running, completed, failed
    total_configurations INTEGER,
    completed_configurations INTEGER DEFAULT 0
);

-- Individual test results
CREATE TABLE IF NOT EXISTS latency_test_results (
    id SERIAL PRIMARY KEY,
    run_id TEXT NOT NULL REFERENCES latency_test_runs(id),
    config_id TEXT NOT NULL,
    scenario_name TEXT NOT NULL,
    repetition INTEGER NOT NULL,
    recorded_at TIMESTAMP NOT NULL,

    -- Per-stage latencies (milliseconds)
    stt_latency_ms REAL,
    llm_ttfb_ms REAL,
    llm_completion_ms REAL,
    tts_ttfb_ms REAL,
    tts_completion_ms REAL,
    e2e_latency_ms REAL NOT NULL,

    -- Quality metrics
    stt_confidence REAL,
    tts_audio_duration_ms REAL,

    -- Resource metrics
    peak_cpu_percent REAL,
    peak_memory_mb REAL,
    thermal_state TEXT,

    -- Errors
    errors JSONB,

    -- Full configuration (for reproducibility)
    stt_config JSONB NOT NULL,
    llm_config JSONB NOT NULL,
    tts_config JSONB NOT NULL,
    audio_config JSONB NOT NULL,

    INDEX idx_results_run_id (run_id),
    INDEX idx_results_config_id (config_id),
    INDEX idx_results_scenario (scenario_name)
);

-- Baseline results (for regression detection)
CREATE TABLE IF NOT EXISTS latency_baselines (
    id SERIAL PRIMARY KEY,
    config_id TEXT NOT NULL UNIQUE,
    scenario_name TEXT NOT NULL,
    established_at TIMESTAMP NOT NULL,

    -- Expected values
    expected_median_e2e_ms REAL NOT NULL,
    expected_p99_e2e_ms REAL NOT NULL,

    -- Acceptable variance (percentage)
    variance_threshold_percent REAL DEFAULT 10.0,

    -- Source run
    source_run_id TEXT REFERENCES latency_test_runs(id),
    sample_count INTEGER
);
```

---

## API Endpoints

### Management Server Extensions

**New endpoints on port 8766:**

```
# Test Suite Management
POST   /api/latency-tests/suites                 # Upload test suite definition
GET    /api/latency-tests/suites                 # List test suites
GET    /api/latency-tests/suites/{id}            # Get suite details
DELETE /api/latency-tests/suites/{id}            # Delete suite

# Test Execution
POST   /api/latency-tests/runs                   # Start new test run
GET    /api/latency-tests/runs                   # List runs (with filtering)
GET    /api/latency-tests/runs/{id}              # Get run status/progress
GET    /api/latency-tests/runs/{id}/results      # Get raw results
DELETE /api/latency-tests/runs/{id}              # Cancel/delete run

# Results & Analysis
GET    /api/latency-tests/runs/{id}/analysis     # Get analysis report
GET    /api/latency-tests/runs/{id}/export       # Export results (CSV/JSON)
POST   /api/latency-tests/compare                # Compare two runs

# Baselines
GET    /api/latency-tests/baselines              # List baselines
POST   /api/latency-tests/baselines              # Create baseline from run
GET    /api/latency-tests/baselines/{id}/check   # Check run against baseline

# WebSocket for real-time updates
WS     /api/latency-tests/ws                     # Live test progress/results
```

---

## Network Latency Accounting

Critical: Test results must be contextualized against real-world network conditions.

| Environment | Round-Trip Addition | Notes |
|-------------|---------------------|-------|
| Localhost | +0ms | Baseline measurement |
| Local WiFi | +5-15ms | Same network, minimal routing |
| US Cellular LTE | +30-70ms | Tower → backbone → cloud |
| US Cellular 5G | +15-40ms | Lower latency than LTE |
| EU Cellular | +40-80ms | Similar to US |
| Cross-Atlantic | +80-150ms | US ↔ EU routing |
| Cloud API (Anthropic/OpenAI) | +10-30ms | API overhead on top of network |

**Projection Formula:**

```
Projected_E2E = Measured_E2E
              + (STT_Needs_Network ? Network_RTT : 0)
              + (LLM_Needs_Network ? Network_RTT : 0)
              + (TTS_Needs_Network ? Network_RTT : 0)
```

**Example:**
- Measured localhost E2E: 200ms
- Using: Cloud STT (Deepgram), Cloud LLM (Anthropic), Self-hosted TTS
- On US Cellular: 200 + 50 + 50 + 0 = **300ms projected**

---

## Integration with Existing Systems

### TelemetryEngine Integration

The test harness extends existing telemetry:

```swift
// In TelemetryEngine.swift - add new event types
enum TelemetryEvent: Sendable {
    // ... existing events ...

    // New: Latency test events
    case latencyTestStarted(configId: String)
    case latencyTestCompleted(configId: String, e2eMs: Double)
    case latencyTestFailed(configId: String, error: String)
}
```

### MetricsUploadService Integration

Test results flow through existing metrics infrastructure:

```swift
// In MetricsUploadService - add test result upload
public func uploadTestResult(_ result: TestResult) async {
    let endpoint = serverHost.appendingPathComponent("/api/latency-tests/results")
    // ... upload logic ...
}
```

### ServerConfigManager Integration

Dynamic provider configuration uses existing server discovery:

```swift
// LatencyTestCoordinator uses ServerConfigManager
let healthyServers = await ServerConfigManager.shared.getHealthyLLMServers()
let bestEndpoint = await ServerConfigManager.shared.getBestLLMEndpoint()
```

---

## File Structure

```
UnaMentis/
├── Testing/
│   └── LatencyHarness/
│       ├── LatencyTestCoordinator.swift      # Main iOS coordinator
│       ├── LatencyMetricsCollector.swift     # High-precision metrics
│       ├── TestConfiguration.swift           # Configuration models
│       ├── TestResult.swift                  # Result models
│       ├── ProviderFactory.swift             # Dynamic provider creation
│       └── HarnessWebSocketClient.swift      # Server communication

server/
├── latency_harness/
│   ├── __init__.py
│   ├── models.py                             # Python data models
│   ├── orchestrator.py                       # Test orchestration
│   ├── analyzer.py                           # Results analysis
│   ├── api.py                                # REST endpoints
│   ├── websocket.py                          # WebSocket handlers
│   ├── schema.sql                            # Database schema
│   └── storage.py                            # Result persistence

tests/
├── latency_harness/
│   ├── test_suites/
│   │   ├── quick_validation.yaml             # Fast sanity check
│   │   ├── provider_comparison.yaml          # Compare providers
│   │   └── full_parameter_sweep.yaml         # Exhaustive search
│   └── test_audio/
│       ├── short_question.wav
│       ├── complex_question.wav
│       └── ...
```

---

## Execution Modes

### 1. Quick Validation (CI/CD)
- Subset of providers (default only)
- 3 repetitions per scenario
- ~5 minutes runtime
- Baseline regression check

```bash
python -m latency_harness.cli run --suite quick_validation --client simulator
```

### 2. Provider Comparison
- All providers, single model per provider
- 10 repetitions per scenario
- ~30 minutes runtime
- Generates comparison report

```bash
python -m latency_harness.cli run --suite provider_comparison --client device
```

### 3. Full Parameter Sweep
- All providers, all parameter combinations
- 5 repetitions per configuration
- ~4-8 hours runtime (run overnight)
- Comprehensive optimization data

```bash
python -m latency_harness.cli run --suite full_parameter_sweep --client device --schedule overnight
```

---

## Output & Visualization

### Console Output (During Execution)

```
╔════════════════════════════════════════════════════════════════════╗
║ Latency Test Run: run_2026_01_06_143022                            ║
║ Suite: provider_comparison | Client: iPhone17Pro                   ║
╠════════════════════════════════════════════════════════════════════╣
║ Progress: [████████████░░░░░░░░░░░░░░░░░░] 42% (126/300)          ║
║ Current: chatterbox + claude-3-5-haiku + deepgram (rep 3/10)      ║
╠════════════════════════════════════════════════════════════════════╣
║ Live Metrics (last 10):                                            ║
║   STT: 45ms (med) | LLM TTFB: 180ms | TTS TTFB: 95ms | E2E: 420ms ║
╠════════════════════════════════════════════════════════════════════╣
║ Top 3 Configs So Far:                                              ║
║   1. glm-asr + qwen2.5:7b + chatterbox       E2E: 285ms (local)   ║
║   2. deepgram + claude-haiku + chatterbox    E2E: 312ms (local)   ║
║   3. deepgram + gpt-4o-mini + vibevoice      E2E: 347ms (local)   ║
╚════════════════════════════════════════════════════════════════════╝
```

### Analysis Report (JSON)

```json
{
  "run_id": "run_2026_01_06_143022",
  "summary": {
    "total_configurations": 48,
    "total_tests": 480,
    "overall_median_e2e_ms": 356,
    "overall_p99_e2e_ms": 612,
    "test_duration_minutes": 32
  },
  "best_configurations": [
    {
      "rank": 1,
      "config_id": "glm-asr_qwen2.5-7b_chatterbox_default",
      "median_e2e_ms": 285,
      "p99_e2e_ms": 342,
      "breakdown": {
        "stt_ms": 42,
        "llm_ttfb_ms": 98,
        "llm_completion_ms": 156,
        "tts_ttfb_ms": 45,
        "tts_completion_ms": 89
      },
      "network_projections": {
        "localhost": { "e2e_ms": 285, "meets_500ms": true },
        "wifi": { "e2e_ms": 295, "meets_500ms": true },
        "cellular_us": { "e2e_ms": 335, "meets_500ms": true },
        "cellular_eu": { "e2e_ms": 355, "meets_500ms": true }
      },
      "estimated_cost_per_hour": 0.00
    }
  ],
  "recommendations": [
    "Self-hosted stack (GLM-ASR + Qwen + Chatterbox) meets <500ms target on all networks",
    "For cloud fallback, consider: Deepgram + Claude Haiku + Chatterbox",
    "Avoid OpenAI Whisper STT - adds 120ms vs Deepgram Nova-3"
  ]
}
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)
- [ ] Define test configuration schema (YAML)
- [ ] Implement LatencyTestCoordinator (iOS)
- [ ] Implement LatencyMetricsCollector (iOS)
- [ ] Basic orchestrator (server)
- [ ] Database schema and storage

### Phase 2: Core Functionality (Week 2-3)
- [ ] REST API endpoints
- [ ] WebSocket real-time updates
- [ ] Dynamic provider configuration (iOS)
- [ ] Results analyzer (basic statistics)
- [ ] Console output during execution

### Phase 3: Analysis & Visualization (Week 3-4)
- [ ] Network projection calculations
- [ ] Regression detection against baselines
- [ ] Comparison between runs
- [ ] Export to CSV/JSON
- [ ] Integration with Operations Console UI

### Phase 4: Advanced Features (Week 4+)
- [ ] Bayesian optimization for parameter search
- [ ] Automated baseline establishment
- [ ] CI/CD integration (quick validation)
- [ ] Historical trend analysis
- [ ] Alerting on regression

---

## Success Criteria

1. **Automation**: Full test suite runs without manual intervention
2. **Coverage**: All provider combinations testable
3. **Accuracy**: <5ms measurement variance on repeated tests
4. **Actionability**: Reports clearly identify optimal configurations
5. **Integration**: Seamless with existing TelemetryEngine and MetricsUploadService
6. **Extensibility**: Adding new providers requires only config changes
7. **Network Realism**: Projections accurately predict production latency

---

## Appendix: Tunable Parameter Reference

### STT Parameters
| Parameter | Range | Impact |
|-----------|-------|--------|
| Provider | deepgram, assemblyai, glm-asr, apple | Major latency impact |
| Model | provider-specific | Quality vs latency tradeoff |
| Language | en-US, etc. | Affects model selection |
| Chunk size (streaming) | 100-500ms | Latency vs accuracy |

### LLM Parameters
| Parameter | Range | Impact |
|-----------|-------|--------|
| Provider | anthropic, openai, selfhosted | Major latency/cost impact |
| Model | provider-specific | TTFB and generation speed |
| Max tokens | 256-2048 | Caps response length |
| Temperature | 0.0-1.0 | Quality (not latency) |
| Streaming | true/false | Essential for low latency |

### TTS Parameters
| Parameter | Range | Impact |
|-----------|-------|--------|
| Provider | chatterbox, vibevoice, elevenlabs, apple | Major latency impact |
| Voice | provider-specific | Quality (not latency) |
| Speed | 0.5-2.0 | Audio duration |
| Streaming | true/false | Essential for low latency |
| Chatterbox exaggeration | 0.0-1.5 | Expressiveness |
| Chatterbox CFG | 0.0-1.0 | Fidelity |

### Audio Engine Parameters
| Parameter | Range | Impact |
|-----------|-------|--------|
| Sample rate | 16000, 24000, 48000 | Processing overhead |
| Buffer size | 256, 512, 1024 | Latency vs stability |
| VAD threshold | 0.3-0.7 | Speech detection sensitivity |
| VAD smoothing | 1-10 frames | False positive reduction |
