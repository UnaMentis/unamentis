# UnaMentis - Testing Guide

## Testing Philosophy

**Core Principle**: Real implementations, no mocks.

### Why No Mocks?

- **Real behavior**: Tests use actual implementations
- **Integration confidence**: Catches real issues
- **Simple**: No complex mocking infrastructure
- **Honest**: Tests reflect actual system behavior

### Test Doubles

Only use simple test doubles when necessary:
- Fake implementations for expensive operations
- Stubs for unavoidable external dependencies (network, APIs)
- **Never** complex mocking frameworks

## Test Structure

### Directory Layout

```
UnaMentisTests/
├── Unit/                    # Fast, isolated tests (103+ tests)
│   ├── AudioEngineTests.swift       # Audio capture, VAD, playback
│   ├── SessionManagerTests.swift    # Session lifecycle, state machine
│   ├── CurriculumEngineTests.swift  # Curriculum loading, progress
│   ├── TelemetryEngineTests.swift   # Metrics, cost tracking
│   ├── ProgressTrackerTests.swift   # Progress persistence
│   ├── DocumentProcessorTests.swift # PDF/text processing
│   └── ...more service tests
├── Integration/             # Multi-component tests (16+ tests)
│   ├── VoiceSessionIntegrationTests.swift  # Full pipeline tests
│   └── ...                  # Telemetry, curriculum, Core Data
├── E2E/                     # End-to-end scenarios (requires API keys)
│   ├── ConversationFlowTests.swift
│   ├── InterruptionTests.swift
│   └── LongSessionTests.swift
└── Helpers/                 # Test utilities
    ├── MockServices.swift           # MockLLMService, MockEmbeddingService
    ├── TestDataFactory.swift        # Core Data test helpers
    └── AudioTestHelpers.swift       # Audio buffer utilities
```

### Test Categories

**Unit Tests** - Single component, fast
- Target: <100ms per test
- Run on every save
- No network, no disk I/O

**Integration Tests** - Multiple components
- Target: <1s per test
- May use disk, local network
- Run before commit

**E2E Tests** - Full system
- Target: <60s per test
- Use real APIs (if keys provided)
- Run before PR merge

## Running Tests

### Quick Tests (Unit only)

```bash
./scripts/test-quick.sh

# Or in Xcode
⌘ + U with Unit scheme
```

### All Tests

```bash
./scripts/test-all.sh

# Or
xcodebuild test -scheme UnaMentis
```

### E2E Tests

```bash
# Requires API keys in .env
./scripts/test-e2e.sh
```

### Specific Tests

```bash
# Single test class
xcodebuild test \
  -scheme UnaMentis \
  -only-testing:UnaMentisTests/Unit/AudioEngineTests

# Single test method
xcodebuild test \
  -scheme UnaMentis \
  -only-testing:UnaMentisTests/Unit/AudioEngineTests/testVADDetection
```

## Writing Tests

### Example: Unit Test

```swift
import XCTest
@testable import UnaMentis

final class AudioEngineTests: XCTestCase {
    var audioEngine: AudioEngine!
    var testConfig: AudioEngineConfig!
    
    override func setUp() async throws {
        testConfig = AudioEngineConfig(
            sampleRate: 16000,
            bufferSize: 512,
            enableVoiceProcessing: false  // Faster for tests
        )
        
        // Real AudioEngine, not a mock!
        audioEngine = AudioEngine(
            config: testConfig,
            vadService: SileroVAD(),  // Real VAD
            telemetry: TelemetryEngine()
        )
    }
    
    func testVADDetection() async throws {
        try await audioEngine.configure(config: testConfig)
        try await audioEngine.start()
        
        // Load test audio file
        let testAudio = try loadTestAudio("speech-sample.wav")
        
        // Process through real pipeline
        var detectedSpeech = false
        for buffer in testAudio.buffers {
            let (_, vadResult) = await audioEngine.processBuffer(buffer)
            if vadResult.isSpeech {
                detectedSpeech = true
                break
            }
        }
        
        XCTAssertTrue(detectedSpeech, "VAD should detect speech in test audio")
    }
}
```

### Example: Integration Test

```swift
final class STTIntegrationTests: XCTestCase {
    func testAssemblyAITranscription() async throws {
        // Skip if no API key
        let apiKey = ProcessInfo.processInfo.environment["ASSEMBLYAI_API_KEY"]
        try XCTSkipIf(apiKey == nil, "ASSEMBLYAI_API_KEY not set")
        
        // Real AssemblyAI service
        let stt = AssemblyAISTT(apiKey: apiKey!)
        let testAudio = try loadTestAudio("hello-world.wav")
        
        let stream = try await stt.startStreaming(audioFormat: testAudio.format)
        
        var finalTranscript = ""
        for buffer in testAudio.buffers {
            try await stt.sendAudio(buffer)
        }
        
        for await result in stream {
            if result.isFinal {
                finalTranscript = result.transcript
                break
            }
        }
        
        XCTAssertTrue(
            finalTranscript.lowercased().contains("hello"),
            "Should transcribe 'hello world'"
        )
    }
}
```

### Example: E2E Test

```swift
final class ConversationFlowTests: XCTestCase {
    func testFullConversation() async throws {
        // This test uses REAL APIs
        let config = loadE2EConfig()  // Loads from .env
        
        let sessionManager = SessionManager(
            audioEngine: AudioEngine(...),
            sttService: AssemblyAISTT(...),  // Real
            ttsService: DeepgramAura2(...),  // Real
            llmService: OpenAILLM(...),      // Real
            ...
        )
        
        try await sessionManager.startSession(topic: nil)
        
        // Simulate user speaking
        let userAudio = try loadTestAudio("user-question.wav")
        for buffer in userAudio.buffers {
            await sessionManager.processAudioBuffer(buffer)
        }
        
        // Wait for AI response
        await wait(for: sessionManager.state, equals: .aiSpeaking, timeout: 10)
        
        // Verify transcript captured
        let transcript = sessionManager.currentTranscript
        XCTAssertFalse(transcript.isEmpty)
    }
}
```

## Test Data

### Audio Fixtures

Located in `Tests/Fixtures/`:

- `speech-sample.wav` - Clean speech for VAD testing
- `hello-world.wav` - "Hello world" for STT testing
- `long-audio.wav` - 2 minutes for session testing
- `noisy-speech.wav` - Background noise testing

Generate fixtures:
```bash
cd Tests/Fixtures
./generate-test-audio.sh
```

### Test Configurations

```swift
struct TestConfiguration {
    // Fast configuration for unit tests
    static let unit = AudioEngineConfig(
        sampleRate: 16000,
        bufferSize: 512,
        enableVoiceProcessing: false,
        vadThreshold: 0.5
    )
    
    // Real-world config for integration tests
    static let integration = AudioEngineConfig(
        sampleRate: 48000,
        bufferSize: 1024,
        enableVoiceProcessing: true,
        vadThreshold: 0.6
    )
}
```

## Performance Testing

### Latency Tests

```swift
func testE2ELatency() async throws {
    let startTime = Date()
    
    // Process full turn
    await sessionManager.processUserUtterance("What is AI?")
    
    let latency = Date().timeIntervalSince(startTime)
    
    XCTAssertLessThan(
        latency,
        0.5,  // 500ms target
        "E2E latency should be under 500ms"
    )
}
```

### Memory Tests

```swift
func testMemoryStability() async throws {
    let initialMemory = getMemoryUsage()
    
    // Run 90-minute simulation
    for _ in 0..<90 {
        await sessionManager.simulateOneMinute()
    }
    
    let finalMemory = getMemoryUsage()
    let growth = finalMemory - initialMemory
    
    XCTAssertLessThan(
        growth,
        50_000_000,  // 50MB
        "Memory growth should be under 50MB"
    )
}
```

## Continuous Integration

Tests run automatically on:
- Every push to `main` or `develop`
- Every pull request
- Nightly (full E2E suite)

See `.github/workflows/ios.yml` for configuration.

### CI Environment

- **Runner**: macOS 14
- **Xcode**: 15.2
- **Simulator**: iPhone 16 Pro Max
- **Timeout**: 30 minutes

## Best Practices

### DO ✅

- Use real implementations
- Test actual behavior
- Keep tests fast (unit <100ms)
- Use descriptive test names
- Test edge cases
- Use test fixtures
- Run tests before committing

### DON'T ❌

- Use complex mocking frameworks
- Mock everything
- Write brittle tests
- Test implementation details
- Ignore flaky tests
- Skip setup/teardown
- Commit failing tests

## Debugging Tests

### Print Debug Info

```swift
func testVAD() async throws {
    XCTContext.runActivity(named: "Processing audio") { _ in
        print("Buffer size: \(buffer.frameLength)")
        print("VAD threshold: \(config.vadThreshold)")
    }
}
```

### Breakpoint Tests

Set breakpoint in test, run with:
```bash
xcodebuild test -scheme UnaMentis \
  -only-testing:MyTest/testMethod
```

### View Test Logs

```bash
# Latest test log
cat ~/Library/Developer/Xcode/DerivedData/.../Logs/Test/*.xcresult
```

## Test Coverage

### View Coverage

```bash
# Run with coverage
xcodebuild test \
  -scheme UnaMentis \
  -enableCodeCoverage YES

# View report
open DerivedData/.../coverage.lcov
```

### Coverage Targets

- **Unit Tests**: >80% coverage
- **Integration Tests**: Critical paths
- **E2E Tests**: User flows

## Integration Tests

The integration test suite (`VoiceSessionIntegrationTests.swift`) tests multiple components working together:

### Test Classes

**VoiceSessionIntegrationTests** - Core integration tests:
- `testTelemetry_tracksLatencyMetrics` - Verifies latency recording (STT, LLM, TTS, E2E)
- `testTelemetry_tracksCosts` - Verifies cost tracking across providers
- `testTelemetry_recordsEvents` - Verifies event logging
- `testMockLLM_streamsResponse` - Tests mock LLM streaming behavior
- `testMockLLM_validatesInput` - Tests input validation
- `testMockLLM_simulatesErrors` - Tests error condition simulation
- `testCurriculumContext_injectedIntoSession` - Tests context generation
- `testCurriculumNavigation_acrossTopics` - Tests topic navigation
- `testProgressTracking_updatesOnTopicCompletion` - Tests progress persistence
- `testCoreData_curriculumPersistence` - Tests curriculum storage
- `testCoreData_topicProgressPersistence` - Tests progress storage
- `testCoreData_documentAssociation` - Tests document relationships

**AudioPipelineIntegrationTests** - Audio system tests:
- `testAudioEngine_configuresVAD` - Tests VAD configuration
- `testAudioEngine_processesBufferThroughVAD` - Tests audio processing
- `testAudioEngine_stopsPlaybackOnInterrupt` - Tests barge-in handling

**ThermalManagementIntegrationTests** - Thermal handling:
- `testThermalStateChange_recordsTelemetry` - Tests thermal event logging

### Running Integration Tests

```bash
# Run all integration tests
xcodebuild test -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnaMentisTests/Integration

# Run specific integration test class
xcodebuild test -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnaMentisTests/VoiceSessionIntegrationTests
```

## Property-Based Testing

Property-based testing complements example-based tests by verifying that invariants hold across randomly generated inputs. This catches edge cases that hand-written examples miss.

### Frameworks

| Language | Framework | Location |
|----------|-----------|----------|
| Python | Hypothesis | `server/management/tests/property/` |
| Rust | proptest | `server/usm-core/crates/usm-core/src/config/mod.rs` |

### Python Property Tests (Hypothesis)

**Test Coverage (70 tests):**
- **TTS Cache**: Hash determinism, dict roundtrip, TTL expiration, stats bounds, stateful testing
- **FOV Context**: Model tier classification, budget sum invariants, tier ordering, buffer rendering
- **TTS Pre-generation**: Job progress invariants, status state machine, text hashing, serialization roundtrips

**Running Property Tests:**
```bash
# Run all property tests
cd server/management
python -m pytest tests/property/ -v --hypothesis-show-statistics

# With specific profile
HYPOTHESIS_PROFILE=thorough pytest tests/property/
```

**Hypothesis Profiles:**
- `default`: 100 examples (local development)
- `ci`: 50 examples (faster CI runs)
- `thorough`: 500 examples (comprehensive testing)
- `debug`: 10 examples (quick debugging)

**Example Property Test:**
```python
from hypothesis import given, strategies as st

@given(st.integers(), st.integers())
def test_addition_is_commutative(a, b):
    """Property: a + b == b + a for all integers."""
    assert a + b == b + a
```

### Rust Property Tests (proptest)

**Test Coverage (37 property tests, 49 total with unit):**
- **Config**: Port validation, TOML roundtrip, path resolution idempotency (12 tests)
- **Template**: Port validation, allocation, command substitution, JSON roundtrip (10 tests)
- **Instance**: Tag matching, validation, serialization, uptime (15 tests)

**Running Property Tests:**
```bash
cd server/usm-core
cargo test config::property_tests

# Run all tests (includes property tests)
cargo test
```

**Example Property Test:**
```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn path_resolution_idempotent(path in "[a-zA-Z0-9/_.-]{1,100}") {
        let resolved1 = resolve_path(&path);
        let resolved2 = resolve_path(&resolved1);
        prop_assert_eq!(resolved1, resolved2);
    }
}
```

### CI Integration

Property tests run automatically in CI via the "Property Tests (Hypothesis)" job in `.github/workflows/server.yml`. Results are included in the workflow summary.

### When to Write Property Tests

Write property tests when:
1. **Mathematical invariants exist**: Bounds, ordering, sums
2. **Round-trip operations**: Serialization, parsing
3. **Idempotency matters**: Repeated operations should have same result
4. **Edge cases are hard to enumerate**: String handling, numeric boundaries

Property tests complement (don't replace) example-based tests. Use both.

## Troubleshooting

### Issue: Tests timeout

**Solution**: Increase timeout or check for deadlocks
```swift
wait(for: [expectation], timeout: 10)
```

### Issue: Flaky tests

**Solution**: Add proper async/await, don't use sleep()
```swift
// ❌ Bad
sleep(1)

// ✅ Good
await asyncOperation()
```

### Issue: Tests fail in CI but pass locally

**Check**:
- Simulator differences
- Environment variables
- File paths (use Bundle)
- Network availability

---

**Questions?** See [CONTRIBUTING.md](CONTRIBUTING.md) or open an issue.
