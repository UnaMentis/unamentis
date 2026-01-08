/**
 * UnaMentis - Latency Test Harness Types
 * ============================================
 *
 * Shared type definitions for the web client latency test harness.
 * Part of the Audio Latency Test Harness infrastructure.
 *
 * ARCHITECTURE OVERVIEW
 * ---------------------
 * This module defines the TypeScript types that mirror the Python server models,
 * ensuring type safety across the frontend-backend boundary. All types here
 * correspond to JSON schemas exchanged via the REST API.
 *
 * TYPE CATEGORIES
 * ---------------
 * 1. Client Types - Identify and describe test clients (iOS, Web)
 * 2. Provider Types - STT, LLM, TTS provider identifiers
 * 3. Configuration Types - Test configuration parameters
 * 4. Result Types - Test execution results and metrics
 * 5. Analysis Types - Statistical analysis and reports
 *
 * NETWORK LATENCY MODEL
 * ---------------------
 * The harness models network latency to project localhost measurements
 * to realistic production scenarios:
 *
 * | Profile          | Added Latency | Represents                    |
 * |------------------|---------------|-------------------------------|
 * | localhost        | 0ms           | Local development             |
 * | wifi             | 10ms          | Home/office WiFi              |
 * | cellular_us      | 50ms          | US cellular (4G/5G)           |
 * | cellular_eu      | 70ms          | EU cellular                   |
 * | intercontinental | 120ms         | Cross-continent connections   |
 *
 * USAGE EXAMPLE
 * -------------
 * ```typescript
 * import { TestConfiguration, TestResult, NETWORK_LATENCY_MS } from './types';
 *
 * // Create a test configuration
 * const config: TestConfiguration = {
 *   id: 'config_123',
 *   scenarioName: 'greeting',
 *   repetition: 1,
 *   stt: { provider: 'deepgram', language: 'en-US' },
 *   llm: { provider: 'anthropic', model: 'claude-3-5-haiku', ... },
 *   tts: { provider: 'chatterbox', speed: 1.0, useStreaming: true },
 *   audioEngine: { sampleRate: 48000, bufferSize: 1024, ... },
 *   networkProfile: 'localhost',
 * };
 *
 * // Project latency for different networks
 * const baseLatency = 250; // ms measured on localhost
 * const projectedCellular = baseLatency + NETWORK_LATENCY_MS['cellular_us'];
 * console.log(`Projected cellular: ${projectedCellular}ms`);
 * ```
 *
 * SEE ALSO
 * --------
 * - web-coordinator.ts: Uses these types for test execution
 * - latency-harness-panel.tsx: Dashboard UI using these types
 * - server/latency_harness/models.py: Python equivalents
 * - docs/LATENCY_TEST_HARNESS_GUIDE.md: Complete usage guide
 */

// ============================================================================
// Client Types
// ============================================================================

/**
 * Identifies the type of test client executing latency tests.
 *
 * - ios_simulator: Xcode iOS Simulator (mach_absolute_time precision)
 * - ios_device: Physical iOS device (highest precision + thermal metrics)
 * - web: Browser-based client (performance.now() precision)
 */
export type ClientType = 'ios_simulator' | 'ios_device' | 'web';

/**
 * Describes what a test client can do.
 *
 * Used by the orchestrator to route test configurations to appropriate clients.
 * For example, on-device ML tests can only run on ios_device clients with
 * hasOnDeviceML capability.
 */
export interface ClientCapabilities {
  /** STT providers this client can use (cloud APIs, on-device, etc.) */
  supportedSTTProviders: STTProvider[];
  /** LLM providers this client can use (cloud APIs, MLX, etc.) */
  supportedLLMProviders: LLMProvider[];
  /** TTS providers this client can use (cloud APIs, on-device, etc.) */
  supportedTTSProviders: TTSProvider[];
  /** True if client has sub-ms timing (iOS mach_absolute_time) */
  hasHighPrecisionTiming: boolean;
  /** True if client can report CPU, memory, thermal metrics */
  hasDeviceMetrics: boolean;
  /** True if client supports on-device ML (CoreML, MLX) */
  hasOnDeviceML: boolean;
  /** Maximum tests this client can run in parallel */
  maxConcurrentTests: number;
}

/**
 * Real-time status of a connected test client.
 *
 * Sent via heartbeats every 5 seconds. Used by the orchestrator to
 * track client health and availability for test assignment.
 */
export interface ClientStatus {
  /** Unique identifier for this client instance */
  clientId: string;
  /** Type of client (ios_simulator, ios_device, web) */
  clientType: ClientType;
  /** True if client is reachable and healthy */
  isConnected: boolean;
  /** True if client is currently executing a test */
  isRunningTest: boolean;
  /** ID of the configuration currently being tested (if any) */
  currentConfigId?: string;
  /** Timestamp of last heartbeat received */
  lastHeartbeat: Date;
}

// ============================================================================
// Provider Types
// ============================================================================

/**
 * Speech-to-Text (STT) provider identifiers.
 *
 * LATENCY CHARACTERISTICS (typical TTFB):
 * - deepgram: ~100-150ms (streaming, recommended)
 * - groq: ~80-120ms (Whisper-3 turbo)
 * - assemblyai: ~200-300ms (batch)
 * - whisper: ~500ms+ (OpenAI, batch)
 * - apple: ~50ms (on-device, iOS only)
 * - glm-asr-ondevice: ~30ms (on-device, iOS only)
 * - web-speech: ~100ms (browser API, quality varies)
 */
export type STTProvider =
  | 'deepgram' // Cloud streaming STT, excellent quality
  | 'assemblyai' // Cloud batch STT
  | 'whisper' // OpenAI Whisper API
  | 'groq' // Groq Whisper-3 turbo
  | 'apple' // iOS on-device Speech framework
  | 'glm-asr' // GLM ASR cloud
  | 'glm-asr-ondevice' // GLM ASR on-device (iOS)
  | 'web-speech'; // Browser Web Speech API

/**
 * Large Language Model (LLM) provider identifiers.
 *
 * LATENCY CHARACTERISTICS (typical TTFB):
 * - anthropic: ~200-400ms (Claude models)
 * - openai: ~200-500ms (GPT models)
 * - selfhosted: ~50-200ms (local vLLM/llama.cpp)
 * - mlx: ~30-100ms (on-device MLX, macOS/iOS only)
 *
 * For sub-500ms E2E, prioritize selfhosted or anthropic with haiku.
 */
export type LLMProvider =
  | 'anthropic' // Claude models (recommended)
  | 'openai' // GPT models
  | 'selfhosted' // vLLM, llama.cpp, etc.
  | 'mlx'; // Apple MLX on-device

/**
 * Text-to-Speech (TTS) provider identifiers.
 *
 * LATENCY CHARACTERISTICS (typical TTFB):
 * - chatterbox: ~50-100ms (local, streaming, recommended)
 * - piper: ~20-50ms (local, very fast)
 * - vibevoice: ~30-80ms (local)
 * - deepgram: ~100-200ms (cloud streaming)
 * - elevenlabs-flash: ~150-250ms (cloud)
 * - elevenlabs-turbo: ~200-400ms (cloud, better quality)
 * - apple: ~30ms (on-device, iOS only)
 * - web-speech: ~50ms (browser API, robotic quality)
 */
export type TTSProvider =
  | 'deepgram' // Cloud streaming TTS
  | 'elevenlabs-flash' // ElevenLabs Flash (faster)
  | 'elevenlabs-turbo' // ElevenLabs Turbo (better quality)
  | 'playht' // PlayHT cloud
  | 'apple' // iOS AVSpeechSynthesizer
  | 'piper' // Local Piper TTS (very fast)
  | 'vibevoice' // Local VibeVoice
  | 'chatterbox' // Local Chatterbox (recommended)
  | 'web-speech'; // Browser speechSynthesis API

// ============================================================================
// Test Configuration
// ============================================================================

/**
 * Complete test configuration for a single latency measurement.
 *
 * Defines all parameters for one test execution: which providers to use,
 * their settings, and the network profile for latency projection.
 *
 * The configuration ID is derived from a hash of all parameters, ensuring
 * configurations with identical settings share the same ID for aggregation.
 */
export interface TestConfiguration {
  /** Unique identifier derived from configuration parameters */
  id: string;
  /** Name of the test scenario being executed */
  scenarioName: string;
  /** Which repetition this is (1-based) */
  repetition: number;
  /** Speech-to-text configuration */
  stt: STTTestConfig;
  /** LLM configuration */
  llm: LLMTestConfig;
  /** Text-to-speech configuration */
  tts: TTSTestConfig;
  /** Audio engine settings */
  audioEngine: AudioEngineTestConfig;
  /** Network profile for latency projection */
  networkProfile: NetworkProfile;
}

/**
 * Speech-to-Text provider configuration.
 *
 * Controls which STT service to use and how to configure it.
 * Chunk size affects the latency/accuracy tradeoff for streaming providers.
 */
export interface STTTestConfig {
  /** Which STT provider to use */
  provider: STTProvider;
  /** Provider-specific model (e.g., 'nova-2' for Deepgram) */
  model?: string;
  /** Audio chunk size for streaming (smaller = lower latency, more CPU) */
  chunkSizeMs?: number;
  /** BCP-47 language code (e.g., 'en-US') */
  language: string;
}

/**
 * LLM provider configuration.
 *
 * Controls which LLM to use, token limits, and generation parameters.
 * Streaming is strongly recommended for low latency (measures TTFB).
 */
export interface LLMTestConfig {
  /** Which LLM provider to use */
  provider: LLMProvider;
  /** Model identifier (e.g., 'claude-3-5-haiku-20241022') */
  model: string;
  /** Maximum tokens to generate (affects completion time) */
  maxTokens: number;
  /** Sampling temperature (0.0-2.0) */
  temperature: number;
  /** Nucleus sampling parameter (optional) */
  topP?: number;
  /** Use streaming for token-by-token delivery (recommended: true) */
  stream: boolean;
}

/**
 * Text-to-Speech provider configuration.
 *
 * Controls which TTS service to use and audio generation settings.
 * Streaming TTS significantly reduces time-to-first-audio.
 */
export interface TTSTestConfig {
  /** Which TTS provider to use */
  provider: TTSProvider;
  /** Voice identifier (provider-specific) */
  voiceId?: string;
  /** Speech speed multiplier (1.0 = normal) */
  speed: number;
  /** Use streaming audio generation (recommended: true) */
  useStreaming: boolean;
  /** Chatterbox-specific settings (if provider is 'chatterbox') */
  chatterboxConfig?: ChatterboxConfig;
}

/**
 * Chatterbox TTS-specific configuration.
 *
 * Fine-grained control over Chatterbox voice synthesis.
 * These parameters affect both quality and latency.
 */
export interface ChatterboxConfig {
  /** Emotional expressiveness (0.0-1.0, higher = more expressive) */
  exaggeration: number;
  /** Classifier-free guidance weight (higher = more controlled) */
  cfgWeight: number;
  /** Speech speed multiplier */
  speed: number;
  /** Enable paralinguistic tags like [laughs], [sighs] */
  enableParalinguisticTags: boolean;
  /** Use multilingual model (supports more languages) */
  useMultilingual: boolean;
  /** Target language code */
  language: string;
  /** Enable streaming audio generation */
  useStreaming: boolean;
  /** Random seed for reproducibility (optional) */
  seed?: number;
}

/**
 * Audio engine configuration.
 *
 * Controls audio capture and processing settings.
 * Buffer size affects latency vs. CPU tradeoff.
 */
export interface AudioEngineTestConfig {
  /** Audio sample rate in Hz (typically 16000 or 48000) */
  sampleRate: number;
  /** Audio buffer size in samples (smaller = lower latency) */
  bufferSize: number;
  /** Voice activity detection threshold (0.0-1.0) */
  vadThreshold: number;
  /** VAD smoothing window in frames */
  vadSmoothingWindow: number;
}

/**
 * Network profile for latency projection.
 *
 * Tests run on localhost but results are projected to realistic
 * network conditions by adding estimated round-trip latency.
 */
export type NetworkProfile =
  | 'localhost' // Local development (0ms added)
  | 'wifi' // Home/office WiFi (10ms added)
  | 'cellular_us' // US cellular (50ms added)
  | 'cellular_eu' // EU cellular (70ms added)
  | 'intercontinental'; // Cross-continent (120ms added)

/**
 * Network latency values for each profile.
 *
 * These are conservative estimates for round-trip latency.
 * Actual latency may vary based on provider locations.
 *
 * Used to project localhost measurements to production scenarios.
 */
export const NETWORK_LATENCY_MS: Record<NetworkProfile, number> = {
  localhost: 0, // No network overhead
  wifi: 10, // ~10ms WiFi RTT
  cellular_us: 50, // ~50ms US cellular RTT
  cellular_eu: 70, // ~70ms EU cellular RTT
  intercontinental: 120, // ~120ms cross-continent RTT
};

// ============================================================================
// Test Scenario
// ============================================================================

/**
 * Type of test scenario to execute.
 *
 * Different scenarios exercise different parts of the pipeline:
 * - audio_input: Full STT → LLM → TTS pipeline
 * - text_input: LLM → TTS only (skips STT)
 * - tts_only: TTS only (useful for TTS provider comparison)
 * - conversation: Multi-turn dialogue (not yet implemented)
 */
export type ScenarioType = 'audio_input' | 'text_input' | 'tts_only' | 'conversation';

/**
 * Expected response length category.
 *
 * Affects LLM token generation and TTS audio duration:
 * - short: ~20-50 tokens, ~3-5 seconds audio
 * - medium: ~100-200 tokens, ~10-20 seconds audio
 * - long: ~300-500 tokens, ~30-60 seconds audio
 */
export type ResponseType = 'short' | 'medium' | 'long';

/**
 * Test scenario definition.
 *
 * Describes a reproducible test case with user input and expected
 * response characteristics. Scenarios can specify either audio or
 * text input (or both for fallback).
 */
export interface TestScenario {
  /** Unique scenario identifier */
  id: string;
  /** Human-readable scenario name */
  name: string;
  /** Detailed description of what this scenario tests */
  description: string;
  /** Which pipeline stages to exercise */
  scenarioType: ScenarioType;
  /** How many times to repeat for statistical significance */
  repetitions: number;
  /** Path to pre-recorded audio file (for audio_input scenarios) */
  userUtteranceAudioPath?: string;
  /** Text representation of user input (for text_input or fallback) */
  userUtteranceText?: string;
  /** Expected response length category */
  expectedResponseType: ResponseType;
}

// ============================================================================
// Test Result
// ============================================================================

/**
 * Complete result from a single test execution.
 *
 * Contains all latency measurements, quality metrics, resource utilization,
 * and the configuration snapshot that produced these results.
 *
 * LATENCY METRICS (all in milliseconds)
 * -------------------------------------
 * | Metric           | Description                              | Target   |
 * |------------------|------------------------------------------|----------|
 * | sttLatencyMs     | STT recognition time                     | <150ms   |
 * | llmTTFBMs        | LLM time to first token                  | <300ms   |
 * | llmCompletionMs  | LLM total completion time                | varies   |
 * | ttsTTFBMs        | TTS time to first audio byte             | <100ms   |
 * | ttsCompletionMs  | TTS total audio generation time          | varies   |
 * | e2eLatencyMs     | End-to-end latency (user speaks to audio)| <500ms   |
 *
 * NETWORK PROJECTIONS
 * -------------------
 * Results include projected E2E latency for different network conditions.
 * For example, a localhost result of 300ms might project to 420ms on cellular.
 */
export interface TestResult {
  /** Unique result identifier (UUID) */
  id: string;
  /** Configuration ID this result belongs to */
  configId: string;
  /** Name of the scenario that was executed */
  scenarioName: string;
  /** Which repetition this was (1-based) */
  repetition: number;
  /** When this test completed (ISO 8601 format) */
  timestamp: string;
  /** Type of client that executed this test */
  clientType: ClientType;

  // ---- Per-stage latencies (milliseconds) ----

  /** STT recognition latency (undefined if text_input scenario) */
  sttLatencyMs?: number;
  /** LLM time to first token (streaming) */
  llmTTFBMs: number;
  /** LLM total completion time */
  llmCompletionMs: number;
  /** TTS time to first audio byte (streaming) */
  ttsTTFBMs: number;
  /** TTS total audio generation time */
  ttsCompletionMs: number;
  /** End-to-end latency from input to first audio output */
  e2eLatencyMs: number;

  // ---- Network projections ----

  /** Network profile this test was run under */
  networkProfile: NetworkProfile;
  /** Projected E2E latency for each network profile */
  networkProjections: Record<NetworkProfile, number>;

  // ---- Quality metrics ----

  /** STT transcription confidence (0.0-1.0) */
  sttConfidence?: number;
  /** Total TTS audio duration in milliseconds */
  ttsAudioDurationMs?: number;
  /** Number of output tokens generated by LLM */
  llmOutputTokens?: number;
  /** Number of input tokens sent to LLM */
  llmInputTokens?: number;

  // ---- Resource utilization (iOS only) ----

  /** Peak CPU usage during test (percentage) */
  peakCPUPercent?: number;
  /** Peak memory usage during test (megabytes) */
  peakMemoryMB?: number;
  /** iOS thermal state (nominal/fair/serious/critical) */
  thermalState?: string;

  // ---- Configuration snapshot ----

  /** STT configuration used for this test */
  sttConfig: STTTestConfig;
  /** LLM configuration used for this test */
  llmConfig: LLMTestConfig;
  /** TTS configuration used for this test */
  ttsConfig: TTSTestConfig;
  /** Audio engine configuration used for this test */
  audioConfig: AudioEngineTestConfig;

  // ---- Error tracking ----

  /** Error messages encountered during test (empty if successful) */
  errors: string[];
  /** True if test completed without errors */
  isSuccess: boolean;
}

// ============================================================================
// Test Run
// ============================================================================

/**
 * Status of a test run.
 *
 * Lifecycle: pending → running → completed|failed|cancelled
 */
export type RunStatus = 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';

/**
 * A test run executes a test suite on a specific client.
 *
 * Contains all results from executing multiple configurations,
 * along with progress tracking and timing information.
 */
export interface TestRun {
  /** Unique run identifier (UUID) */
  id: string;
  /** Human-readable suite name */
  suiteName: string;
  /** ID of the test suite being executed */
  suiteId: string;
  /** When the run started (ISO 8601 format) */
  startedAt: string;
  /** When the run completed (undefined if still running) */
  completedAt?: string;
  /** ID of the client executing this run */
  clientId: string;
  /** Type of client executing this run */
  clientType: ClientType;
  /** Current run status */
  status: RunStatus;
  /** Total number of configurations to test */
  totalConfigurations: number;
  /** Number of configurations completed so far */
  completedConfigurations: number;
  /** Results collected so far (grows as tests complete) */
  results: TestResult[];
}

// ============================================================================
// Analysis Report
// ============================================================================

/**
 * Complete analysis report for a test run.
 *
 * Generated after a test run completes, containing statistical analysis,
 * ranked configurations, network projections, and actionable recommendations.
 */
export interface AnalysisReport {
  /** ID of the test run this analysis is for */
  runId: string;
  /** When this analysis was generated (ISO 8601 format) */
  generatedAt: string;
  /** Overall summary statistics */
  summary: SummaryStatistics;
  /** Configurations ranked by E2E latency (best first) */
  bestConfigurations: RankedConfiguration[];
  /** Network projections showing how results scale */
  networkProjections: NetworkProjection[];
  /** Detected regressions from baseline */
  regressions: Regression[];
  /** Actionable recommendations based on results */
  recommendations: string[];
}

/**
 * Summary statistics across all test results.
 *
 * Provides high-level overview of test run performance,
 * including median/P99/min/max for key metrics.
 */
export interface SummaryStatistics {
  /** Number of unique configurations tested */
  totalConfigurations: number;
  /** Total number of individual test executions */
  totalTests: number;
  /** Number of tests that completed without errors */
  successfulTests: number;
  /** Number of tests that failed */
  failedTests: number;
  /** Median E2E latency across all tests (ms) */
  overallMedianE2EMs: number;
  /** 99th percentile E2E latency (ms) */
  overallP99E2EMs: number;
  /** Minimum E2E latency observed (ms) */
  overallMinE2EMs: number;
  /** Maximum E2E latency observed (ms) */
  overallMaxE2EMs: number;
  /** Median STT latency (ms, undefined if no STT tests) */
  medianSTTMs?: number;
  /** Median LLM time to first token (ms) */
  medianLLMTTFBMs: number;
  /** Median LLM completion time (ms) */
  medianLLMCompletionMs: number;
  /** Median TTS time to first byte (ms) */
  medianTTSTTFBMs: number;
  /** Median TTS completion time (ms) */
  medianTTSCompletionMs: number;
  /** Total test run duration in minutes */
  testDurationMinutes: number;
}

/**
 * A configuration ranked by performance.
 *
 * Includes statistical metrics and breakdown of where time is spent.
 */
export interface RankedConfiguration {
  /** Rank position (1 = best) */
  rank: number;
  /** Configuration identifier */
  configId: string;
  /** Median E2E latency for this config (ms) */
  medianE2EMs: number;
  /** 99th percentile E2E latency (ms) */
  p99E2EMs: number;
  /** Standard deviation of E2E latency (ms) */
  stddevMs: number;
  /** Number of test samples for this config */
  sampleCount: number;
  /** Per-stage latency breakdown */
  breakdown: LatencyBreakdown;
  /** Network projections with target assessment */
  networkProjections: Record<string, NetworkMeetsTarget>;
  /** Estimated API cost per hour of usage ($) */
  estimatedCostPerHour: number;
}

/**
 * Breakdown of latency by pipeline stage.
 *
 * Shows where time is spent in the STT → LLM → TTS pipeline.
 * Useful for identifying bottlenecks.
 */
export interface LatencyBreakdown {
  /** STT latency (undefined for text-only tests) */
  sttMs?: number;
  /** LLM time to first token */
  llmTTFBMs: number;
  /** LLM total completion time */
  llmCompletionMs: number;
  /** TTS time to first byte */
  ttsTTFBMs: number;
  /** TTS total completion time */
  ttsCompletionMs: number;
}

/**
 * Network projection with target assessment.
 *
 * Shows whether a configuration meets latency targets
 * under specific network conditions.
 */
export interface NetworkMeetsTarget {
  /** Projected E2E latency under this network (ms) */
  e2eMs: number;
  /** True if projected E2E < 500ms (primary target) */
  meets500ms: boolean;
  /** True if projected E2E < 1000ms (secondary target) */
  meets1000ms: boolean;
}

/**
 * Network projection summary.
 *
 * Aggregates results across configurations for a network profile.
 */
export interface NetworkProjection {
  /** Network profile name */
  network: string;
  /** Latency added by this network profile (ms) */
  addedLatencyMs: number;
  /** Projected median E2E across all configs (ms) */
  projectedMedianMs: number;
  /** Projected P99 E2E across all configs (ms) */
  projectedP99Ms: number;
  /** True if median meets primary target (500ms) */
  meetsTarget: boolean;
  /** Number of configurations meeting target */
  configsMeetingTarget: number;
  /** Total number of configurations */
  totalConfigs: number;
}

/**
 * Detected performance regression.
 *
 * Indicates that a configuration performs worse than baseline.
 * Severity is determined by the magnitude of the regression.
 */
export interface Regression {
  /** Configuration that regressed */
  configId: string;
  /** Which metric regressed (e.g., 'e2eLatencyMs') */
  metric: string;
  /** Baseline value from previous measurements */
  baselineValue: number;
  /** Current value from this test run */
  currentValue: number;
  /** Percentage change ((current - baseline) / baseline * 100) */
  changePercent: number;
  /** Severity level based on change magnitude */
  severity: 'minor' | 'moderate' | 'severe';
}

// ============================================================================
// Test Suite Definition
// ============================================================================

/**
 * Complete test suite definition.
 *
 * A test suite defines a collection of scenarios and a parameter space
 * to explore. The orchestrator generates all combinations and executes
 * them systematically.
 *
 * EXAMPLE
 * -------
 * A suite with 2 scenarios × 3 LLM configs × 2 TTS configs × 5 repetitions
 * would execute 2 × 3 × 2 × 5 = 60 individual tests.
 */
export interface TestSuiteDefinition {
  /** Unique suite identifier */
  id: string;
  /** Human-readable suite name */
  name: string;
  /** Detailed description of what this suite tests */
  description: string;
  /** Test scenarios to execute */
  scenarios: TestScenario[];
  /** Network profiles to project results for */
  networkProfiles: NetworkProfile[];
  /** Parameter space to explore */
  parameterSpace: ParameterSpace;
}

/**
 * Parameter space defining configurations to test.
 *
 * Each array contains configurations for a pipeline stage.
 * The orchestrator generates the Cartesian product of all
 * configurations (or a sampling if the space is too large).
 */
export interface ParameterSpace {
  /** STT configurations to test */
  sttConfigs: STTTestConfig[];
  /** LLM configurations to test */
  llmConfigs: LLMTestConfig[];
  /** TTS configurations to test */
  ttsConfigs: TTSTestConfig[];
  /** Audio engine configurations to test */
  audioConfigs: AudioEngineTestConfig[];
}
