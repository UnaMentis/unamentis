# Latency Harness - iOS Implementation

Swift implementation of the latency test harness for iOS devices and simulators.

## Purpose

Execute latency tests on iOS with:
- High-precision timing (nanosecond via `mach_absolute_time`)
- Dynamic provider configuration per test
- Resource monitoring (CPU, memory, thermal state)
- Fire-and-forget result reporting

## Key Components

| File | Purpose |
|------|---------|
| `LatencyTestCoordinator.swift` | Main coordinator actor for test execution |
| `LatencyMetricsCollector.swift` | High-precision timing and metrics collection |
| `TestConfiguration.swift` | Swift models for test configuration |
| `TestResult.swift` | Swift models for test results with network projections |

## High-Precision Timing

The iOS harness uses `mach_absolute_time()` for sub-millisecond precision:

```swift
// Start timing
let start = mach_absolute_time()

// ... operation ...

// Record latency
let elapsed = mach_absolute_time() - start
let ms = machTimeToMs(elapsed)  // Converts via mach_timebase_info
```

**Why mach_absolute_time?**
- Zero syscall overhead (reads CPU time counter directly)
- Nanosecond precision
- No observer effect on measurements
- Available on all Apple platforms

## Observer Effect Mitigation

**Critical principle:** Measurement must not introduce latency.

Design patterns used:

1. **All timing operations are local, in-memory, non-blocking**
2. **No network I/O during test execution**
3. **Resource sampling runs on separate Task (100ms interval)**
4. **Results assembled only at finalization**
5. **Reporting to server is asynchronous (fire-and-forget)**

```swift
// Good: Fire-and-forget reporting
Task {
    try? await resultReporter.submit(result)
}

// Bad: Synchronous reporting (blocks next test)
try await resultReporter.submit(result)  // DON'T DO THIS
```

## Test Execution Flow

```swift
// 1. Configure providers for this test
try await coordinator.configure(with: config)

// 2. Execute test scenario
let result = try await coordinator.executeTest(scenario: scenario, repetition: 1)

// 3. Result contains all metrics automatically
// - sttLatencyMs, llmTTFBMs, llmCompletionMs, ttsTTFBMs, ttsCompletionMs
// - e2eLatencyMs
// - peakCPUPercent, peakMemoryMB, thermalState
// - networkProjections (localhost, wifi, cellular)
```

## Provider Configuration

The coordinator dynamically creates providers based on test configuration:

**STT Providers:**
- `deepgram` - Cloud streaming (WebSocket)
- `assemblyai` - Cloud batch
- `apple` - On-device (Apple Speech)
- `glm-asr` - On-device CoreML
- `groq` - Cloud (Whisper-large-v3-turbo)

**LLM Providers:**
- `anthropic` - Claude models
- `openai` - GPT models
- `selfhosted` - vLLM, llama.cpp, Ollama
- `mlx` - On-device MLX

**TTS Providers:**
- `chatterbox` - Self-hosted, emotion control
- `vibevoice` - Self-hosted, real-time
- `elevenlabs` - Cloud streaming
- `apple` - On-device AVSpeechSynthesizer
- `piper` - Self-hosted

## Resource Monitoring

During test execution, the collector samples every 100ms:

```swift
// CPU usage via thread introspection
func getCurrentCPUUsage() -> Double {
    var threads: thread_act_array_t?
    var threadCount: mach_msg_type_number_t = 0
    task_threads(mach_task_self_, &threads, &threadCount)
    // ... sum thread CPU times
}

// Memory usage via mach_task_basic_info
func getCurrentMemoryUsage() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), &info, &count)
    return info.resident_size
}

// Thermal state via ProcessInfo
let thermal = ProcessInfo.processInfo.thermalState
// Returns: .nominal, .fair, .serious, .critical
```

Peak values are included in test results for correlation analysis.

## Network Projections

Results automatically include projections for different network conditions:

```swift
// Network overhead added per stage that requires network
let projections = result.withNetworkProjections()

// Example projections:
// localhost: 285ms (base)
// wifi: 295ms (+10ms per network-dependent stage)
// cellular_us: 335ms (+50ms per network-dependent stage)
// cellular_eu: 355ms (+70ms per network-dependent stage)
```

Stages that require network (adds latency per profile):
- Cloud STT (Deepgram, AssemblyAI, Groq)
- Cloud LLM (Anthropic, OpenAI)
- Cloud TTS (ElevenLabs, Deepgram)

On-device stages add no network latency.

## Swift 6 Concurrency

Both `LatencyTestCoordinator` and `LatencyMetricsCollector` are actors:

```swift
public actor LatencyTestCoordinator {
    // All state mutations are isolated
    private var currentConfig: TestConfiguration?
    private var sttService: (any STTService)?
    private var llmService: (any LLMService)?
    private var ttsService: (any TTSService)?
}

public actor LatencyMetricsCollector {
    // Metrics collection is thread-safe
    private var sttLatencyMs: Double = 0
    private var llmTTFBMs: Double = 0
    private var cpuSamples: [Double] = []
}
```

## Integration with Session Manager

The coordinator can be used standalone or integrated with SessionManager:

```swift
// Standalone usage (for dedicated testing)
let coordinator = LatencyTestCoordinator(serverURL: serverURL)
try await coordinator.configure(with: config)
let result = try await coordinator.executeTest(scenario: scenario, repetition: 1)

// Integration with existing session
// Use coordinator's provider factory methods to create services
// that match test configuration
```

## Documentation

- Usage Guide: `docs/LATENCY_TEST_HARNESS_GUIDE.md`
- Architecture: `docs/design/AUDIO_LATENCY_TEST_HARNESS.md`
- Server Component: `server/latency_harness/CLAUDE.md`
