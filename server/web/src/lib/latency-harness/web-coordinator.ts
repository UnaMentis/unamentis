/**
 * UnaMentis - Web Client Latency Test Coordinator
 * ================================================
 *
 * Browser-based test execution for the latency harness.
 * Part of the Audio Latency Test Harness infrastructure.
 *
 * ARCHITECTURE OVERVIEW
 * ---------------------
 * This module provides the web client implementation for latency testing.
 * It mirrors the iOS LatencyTestCoordinator but operates in the browser
 * using Web APIs for timing and network communication.
 *
 * Key Components:
 * 1. WebMetricsCollector - Collects timing metrics during test execution
 * 2. WebLatencyTestCoordinator - Main coordinator for test execution
 *
 * TIMING PRECISION
 * ----------------
 * - Uses performance.now() for sub-millisecond precision
 * - Not as precise as iOS mach_absolute_time, but sufficient for web testing
 * - hasHighPrecisionTiming capability is set to false for web clients
 *
 * OBSERVER EFFECT MITIGATION
 * --------------------------
 * Like the iOS and Python implementations, this collector is designed to
 * minimize measurement overhead:
 * - All timing operations use local performance.now() (no syscalls)
 * - Results are assembled only at finalization
 * - Server reporting happens asynchronously after test completion
 *
 * USAGE EXAMPLE
 * -------------
 * ```typescript
 * import { getWebLatencyTestCoordinator } from './web-coordinator';
 *
 * const coordinator = getWebLatencyTestCoordinator('http://localhost:8766');
 *
 * // Execute a test
 * const result = await coordinator.executeTest(scenario, config);
 * console.log(`E2E: ${result.e2eLatencyMs}ms`);
 *
 * // Report result to server (fire-and-forget)
 * coordinator.reportResult(result);
 * ```
 *
 * NETWORK PROJECTIONS
 * -------------------
 * Web tests run against localhost APIs but project results to realistic
 * network conditions. Each stage (STT/LLM/TTS) that requires network
 * adds the profile's latency overhead.
 *
 * LIMITATIONS VS iOS
 * ------------------
 * - No device metrics (CPU, memory, thermal state)
 * - Lower timing precision
 * - No on-device ML support
 * - Limited to cloud STT (Web Speech API available as fallback)
 *
 * SEE ALSO
 * --------
 * - types.ts: Type definitions used by this module
 * - UnaMentis/Testing/LatencyHarness/LatencyTestCoordinator.swift: iOS equivalent
 * - server/latency_harness/orchestrator.py: Server-side orchestration
 * - docs/LATENCY_TEST_HARNESS_GUIDE.md: Complete usage guide
 */

import {
  TestConfiguration,
  TestResult,
  TestScenario,
  TestRun,
  ClientType,
  ClientCapabilities,
  ClientStatus,
  STTProvider,
  LLMProvider,
  TTSProvider,
  NetworkProfile,
  NETWORK_LATENCY_MS,
} from './types';

// ============================================================================
// Web Metrics Collector
// ============================================================================

/**
 * Collects latency metrics during web-based test execution.
 *
 * Uses performance.now() for timing, which provides sub-millisecond
 * precision in modern browsers. All timing operations are local and
 * non-blocking to minimize observer effect.
 *
 * TIMING ACCURACY
 * ---------------
 * performance.now() provides microsecond-resolution timestamps relative
 * to the page load. While not as precise as iOS mach_absolute_time,
 * it's accurate enough for latency measurements in the 100-1000ms range.
 *
 * USAGE
 * -----
 * 1. Call startTest() with the configuration
 * 2. Record stage latencies as they occur
 * 3. Call finalizeTest() to get the complete result
 */
class WebMetricsCollector {
  // ---- Test Context ----
  private testId: string = '';
  private configId: string = '';
  private scenarioName: string = '';
  private repetition: number = 0;
  /** Test start time from performance.now() */
  private testStartTime: number = 0;

  // ---- Per-stage Latencies (milliseconds) ----
  private sttLatencyMs?: number;
  private llmTTFBMs: number = 0;
  private llmCompletionMs: number = 0;
  private ttsTTFBMs: number = 0;
  private ttsCompletionMs: number = 0;
  private e2eLatencyMs: number = 0;

  // ---- Quality Metrics ----
  private sttConfidence?: number;
  private ttsAudioDurationMs?: number;
  private llmInputTokens?: number;
  private llmOutputTokens?: number;

  // ---- Error Tracking ----
  private errors: string[] = [];

  // ---- Configuration Snapshot ----
  private config?: TestConfiguration;

  /**
   * Start a new test measurement.
   *
   * Resets all metrics and records the start time.
   * Must be called before recording any stage latencies.
   *
   * @param config - The test configuration being executed
   */
  startTest(config: TestConfiguration): void {
    // Generate unique test ID
    this.testId = crypto.randomUUID();
    this.configId = config.id;
    this.scenarioName = config.scenarioName;
    this.repetition = config.repetition;
    this.config = config;

    // Reset all metrics to ensure clean state
    this.sttLatencyMs = undefined;
    this.llmTTFBMs = 0;
    this.llmCompletionMs = 0;
    this.ttsTTFBMs = 0;
    this.ttsCompletionMs = 0;
    this.e2eLatencyMs = 0;
    this.sttConfidence = undefined;
    this.ttsAudioDurationMs = undefined;
    this.llmInputTokens = undefined;
    this.llmOutputTokens = undefined;
    this.errors = [];

    // Record start time using performance.now() for sub-ms precision
    // This is the reference point for all latency calculations
    this.testStartTime = performance.now();
  }

  // ---- Latency Recording Methods ----
  // These are intentionally minimal to reduce measurement overhead

  /** Record STT recognition latency */
  recordSTTLatency(ms: number): void {
    this.sttLatencyMs = ms;
  }
  /** Record LLM time to first token */
  recordLLMTTFB(ms: number): void {
    this.llmTTFBMs = ms;
  }
  /** Record LLM total completion time */
  recordLLMCompletion(ms: number): void {
    this.llmCompletionMs = ms;
  }
  /** Record TTS time to first audio byte */
  recordTTSTTFB(ms: number): void {
    this.ttsTTFBMs = ms;
  }
  /** Record TTS total completion time */
  recordTTSCompletion(ms: number): void {
    this.ttsCompletionMs = ms;
  }
  /** Record end-to-end latency */
  recordE2ELatency(ms: number): void {
    this.e2eLatencyMs = ms;
  }

  // ---- Quality Metrics Recording ----

  /** Record STT transcription confidence (0.0-1.0) */
  recordSTTConfidence(confidence: number): void {
    this.sttConfidence = confidence;
  }
  /** Record total TTS audio duration in milliseconds */
  recordTTSAudioDuration(ms: number): void {
    this.ttsAudioDurationMs = ms;
  }
  /** Record LLM input/output token counts */
  recordLLMTokenCounts(input: number, output: number): void {
    this.llmInputTokens = input;
    this.llmOutputTokens = output;
  }

  /** Record an error that occurred during test execution */
  recordError(error: Error | string): void {
    this.errors.push(typeof error === 'string' ? error : error.message);
  }

  /**
   * Get elapsed time since test start.
   *
   * @returns Milliseconds elapsed since startTest() was called
   */
  getElapsedMs(): number {
    return performance.now() - this.testStartTime;
  }

  /**
   * Finalize the test and return the complete result.
   *
   * Assembles all collected metrics into a TestResult object.
   * Also calculates network projections for different network profiles.
   *
   * @returns Complete test result with all metrics and projections
   */
  finalizeTest(): TestResult {
    if (this.e2eLatencyMs === 0) {
      this.e2eLatencyMs = this.getElapsedMs();
    }

    // Calculate network projections
    const networkProjections = this.calculateNetworkProjections();

    const result: TestResult = {
      id: this.testId,
      configId: this.configId,
      scenarioName: this.scenarioName,
      repetition: this.repetition,
      timestamp: new Date().toISOString(),
      clientType: 'web',

      sttLatencyMs: this.sttLatencyMs,
      llmTTFBMs: this.llmTTFBMs,
      llmCompletionMs: this.llmCompletionMs,
      ttsTTFBMs: this.ttsTTFBMs,
      ttsCompletionMs: this.ttsCompletionMs,
      e2eLatencyMs: this.e2eLatencyMs,

      networkProfile: this.config?.networkProfile ?? 'localhost',
      networkProjections,

      sttConfidence: this.sttConfidence,
      ttsAudioDurationMs: this.ttsAudioDurationMs,
      llmOutputTokens: this.llmOutputTokens,
      llmInputTokens: this.llmInputTokens,

      // Web doesn't have device metrics
      peakCPUPercent: undefined,
      peakMemoryMB: undefined,
      thermalState: undefined,

      sttConfig: this.config?.stt ?? { provider: 'web-speech', language: 'en-US' },
      llmConfig: this.config?.llm ?? {
        provider: 'anthropic',
        model: 'claude-3-5-haiku',
        maxTokens: 512,
        temperature: 0.7,
        stream: true,
      },
      ttsConfig: this.config?.tts ?? { provider: 'web-speech', speed: 1.0, useStreaming: false },
      audioConfig: this.config?.audioEngine ?? {
        sampleRate: 48000,
        bufferSize: 1024,
        vadThreshold: 0.5,
        vadSmoothingWindow: 5,
      },

      errors: this.errors,
      isSuccess: this.errors.length === 0,
    };

    return result;
  }

  /**
   * Calculate network projections for all profiles.
   *
   * Projects the measured localhost latency to realistic network conditions
   * by adding round-trip latency for each stage that requires network access.
   *
   * PROJECTION LOGIC
   * ----------------
   * For each network profile, we add the profile's RTT overhead once per
   * stage that requires network communication:
   * - STT: +overhead if using cloud provider (not web-speech)
   * - LLM: +overhead if using cloud provider (not mlx)
   * - TTS: +overhead if using cloud provider (not web-speech)
   *
   * Example: 300ms localhost with all cloud providers on cellular_us (50ms):
   * 300 + 50 (STT) + 50 (LLM) + 50 (TTS) = 450ms projected
   *
   * @returns Projected E2E latency for each network profile
   */
  private calculateNetworkProjections(): Record<NetworkProfile, number> {
    // Initialize all projections to measured E2E
    const projections: Record<NetworkProfile, number> = {
      localhost: this.e2eLatencyMs,
      wifi: this.e2eLatencyMs,
      cellular_us: this.e2eLatencyMs,
      cellular_eu: this.e2eLatencyMs,
      intercontinental: this.e2eLatencyMs,
    };

    if (!this.config) return projections;

    // Determine which stages require network access
    // Local providers (web-speech, mlx) don't add network latency
    const sttRequiresNetwork = !['web-speech'].includes(this.config.stt.provider);
    const llmRequiresNetwork = !['mlx'].includes(this.config.llm.provider);
    const ttsRequiresNetwork = !['web-speech'].includes(this.config.tts.provider);

    // Calculate projection for each network profile
    for (const profile of Object.keys(NETWORK_LATENCY_MS) as NetworkProfile[]) {
      const overhead = NETWORK_LATENCY_MS[profile];
      let projected = this.e2eLatencyMs;

      // Add network overhead for each stage that needs it
      if (sttRequiresNetwork) projected += overhead;
      if (llmRequiresNetwork) projected += overhead;
      if (ttsRequiresNetwork) projected += overhead;

      projections[profile] = projected;
    }

    return projections;
  }
}

// ============================================================================
// Web Latency Test Coordinator
// ============================================================================

/**
 * Main coordinator for web-based latency test execution.
 *
 * Manages the complete test lifecycle: receiving configurations from
 * the server, executing tests, collecting metrics, and reporting results.
 *
 * ARCHITECTURE
 * ------------
 * The coordinator follows a client-server architecture where:
 * 1. The Python orchestrator assigns tests to available clients
 * 2. This coordinator executes tests and collects metrics
 * 3. Results are reported back to the server (fire-and-forget)
 *
 * SUPPORTED SCENARIOS
 * -------------------
 * - text_input: LLM → TTS pipeline (skips STT)
 * - tts_only: TTS only (useful for TTS provider comparison)
 * - audio_input: Falls back to text_input if text is available
 * - conversation: Not yet implemented
 *
 * THREAD SAFETY
 * -------------
 * The coordinator is not thread-safe. Only one test should be
 * executed at a time. Use isRunning to check current state.
 */
export class WebLatencyTestCoordinator {
  /** Unique identifier for this client instance */
  private clientId: string;
  /** URL of the management server API */
  private serverUrl: string;
  /** Metrics collector for timing measurements */
  private metricsCollector: WebMetricsCollector;
  /** Current test configuration (if running) */
  private currentConfig?: TestConfiguration;
  /** True if a test is currently in progress */
  private isRunning: boolean = false;

  /**
   * Create a new web latency test coordinator.
   *
   * @param serverUrl - URL of the management server (default: http://localhost:8766)
   */
  constructor(serverUrl: string = 'http://localhost:8766') {
    // Generate unique client ID with 'web_' prefix
    this.clientId = `web_${crypto.randomUUID().slice(0, 8)}`;
    this.serverUrl = serverUrl;
    this.metricsCollector = new WebMetricsCollector();
  }

  // ============================================================================
  // Client Info
  // ============================================================================

  /**
   * Get this client's capabilities.
   *
   * Used by the orchestrator to determine which configurations this
   * client can execute. Web clients have limited capabilities compared
   * to iOS clients (no on-device ML, no device metrics).
   *
   * @returns Capabilities describing what this client can do
   */
  getCapabilities(): ClientCapabilities {
    return {
      // Web can only use cloud STT providers + Web Speech API
      supportedSTTProviders: ['deepgram', 'assemblyai', 'whisper', 'groq', 'web-speech'],
      // Web can use all cloud LLM providers
      supportedLLMProviders: ['anthropic', 'openai', 'selfhosted'],
      // Web can use cloud TTS + Web Speech API
      supportedTTSProviders: [
        'deepgram',
        'elevenlabs-flash',
        'elevenlabs-turbo',
        'chatterbox',
        'vibevoice',
        'piper',
        'web-speech',
      ],
      // performance.now() is not as precise as mach_absolute_time
      hasHighPrecisionTiming: false,
      // Browser doesn't expose device metrics
      hasDeviceMetrics: false,
      // No on-device ML in browser
      hasOnDeviceML: false,
      // Can run many tests in parallel
      maxConcurrentTests: 10,
    };
  }

  /**
   * Get current client status.
   *
   * Used for heartbeat reporting to the server. The orchestrator uses
   * this to track client health and availability.
   *
   * @returns Current status of this client
   */
  getStatus(): ClientStatus {
    return {
      clientId: this.clientId,
      clientType: 'web',
      isConnected: true, // Assuming connected if this code is running
      isRunningTest: this.isRunning,
      currentConfigId: this.currentConfig?.id,
      lastHeartbeat: new Date(),
    };
  }

  // ============================================================================
  // Test Execution
  // ============================================================================

  /**
   * Execute a latency test with the given scenario and configuration.
   *
   * Runs the complete test pipeline based on scenario type:
   * - text_input: Sends text to LLM, then TTS
   * - tts_only: Sends text directly to TTS
   * - audio_input: Falls back to text_input if available
   *
   * OBSERVER EFFECT MITIGATION
   * --------------------------
   * All timing is done using lightweight performance.now() calls.
   * Results are assembled only at finalization, not during execution.
   * Server reporting happens after test completion (fire-and-forget).
   *
   * @param scenario - The test scenario defining input and expected response
   * @param config - The provider configuration to test
   * @returns Complete test result with all metrics
   */
  async executeTest(scenario: TestScenario, config: TestConfiguration): Promise<TestResult> {
    this.isRunning = true;
    this.currentConfig = config;

    // Start metrics collection
    this.metricsCollector.startTest(config);

    try {
      switch (scenario.scenarioType) {
        case 'text_input':
          await this.executeTextInputScenario(scenario, config);
          break;
        case 'tts_only':
          await this.executeTTSOnlyScenario(scenario, config);
          break;
        case 'audio_input':
          // Fallback to text if available
          if (scenario.userUtteranceText) {
            await this.executeTextInputScenario(scenario, config);
          } else {
            throw new Error('Audio input not supported in web client without text fallback');
          }
          break;
        case 'conversation':
          throw new Error('Conversation scenarios not yet implemented');
      }
    } catch (error) {
      this.metricsCollector.recordError(error as Error);
    }

    this.isRunning = false;
    return this.metricsCollector.finalizeTest();
  }

  // ============================================================================
  // Scenario Implementations
  // ============================================================================

  /**
   * Execute a text-input scenario (LLM → TTS).
   *
   * This is the most common scenario type, testing the LLM and TTS
   * stages without requiring audio input or STT.
   *
   * TIMING POINTS
   * -------------
   * 1. llmStart: When LLM request is sent
   * 2. llmTTFB: When first token is received (streaming)
   * 3. llmCompletion: When all tokens are received
   * 4. ttsStart: When TTS request is sent
   * 5. ttsTTFB: When first audio chunk is received (streaming)
   * 6. ttsCompletion: When all audio is received
   * 7. e2e: Total time from start to first audio
   *
   * @param scenario - Scenario with user text input
   * @param config - Provider configuration
   */
  private async executeTextInputScenario(
    scenario: TestScenario,
    config: TestConfiguration
  ): Promise<void> {
    const userText = scenario.userUtteranceText ?? 'What is the capital of France?';

    // Phase: LLM
    const llmStartTime = performance.now();
    let firstTokenReceived = false;
    let fullResponse = '';
    let outputTokenCount = 0;

    // Make streaming LLM request
    const llmResponse = await this.callLLMStreaming(userText, config.llm);

    for await (const token of llmResponse) {
      if (!firstTokenReceived) {
        firstTokenReceived = true;
        this.metricsCollector.recordLLMTTFB(performance.now() - llmStartTime);
      }
      fullResponse += token.content;
      if (token.tokenCount) {
        outputTokenCount = token.tokenCount;
      }
    }

    this.metricsCollector.recordLLMCompletion(performance.now() - llmStartTime);
    this.metricsCollector.recordLLMTokenCounts(
      Math.ceil(userText.length / 4), // Rough estimate
      outputTokenCount
    );

    // Phase: TTS
    const ttsStartTime = performance.now();
    let firstAudioReceived = false;
    let totalAudioDurationMs = 0;

    const ttsResponse = await this.callTTSStreaming(fullResponse, config.tts);

    for await (const chunk of ttsResponse) {
      if (!firstAudioReceived) {
        firstAudioReceived = true;
        this.metricsCollector.recordTTSTTFB(performance.now() - ttsStartTime);
      }
      totalAudioDurationMs += chunk.durationMs;
    }

    this.metricsCollector.recordTTSCompletion(performance.now() - ttsStartTime);
    this.metricsCollector.recordTTSAudioDuration(totalAudioDurationMs);

    // Record E2E - total time from test start to first audio
    this.metricsCollector.recordE2ELatency(this.metricsCollector.getElapsedMs());
  }

  /**
   * Execute a TTS-only scenario.
   *
   * Tests TTS latency in isolation, useful for comparing TTS providers
   * without LLM overhead. Uses predefined test text based on expected
   * response length.
   *
   * @param scenario - Scenario with expected response type
   * @param config - TTS provider configuration
   */
  private async executeTTSOnlyScenario(
    scenario: TestScenario,
    config: TestConfiguration
  ): Promise<void> {
    // Generate test text based on response type (short/medium/long)
    const testText = this.getTestText(scenario.expectedResponseType);

    const ttsStartTime = performance.now();
    let firstAudioReceived = false;
    let totalAudioDurationMs = 0;

    const ttsResponse = await this.callTTSStreaming(testText, config.tts);

    for await (const chunk of ttsResponse) {
      if (!firstAudioReceived) {
        firstAudioReceived = true;
        this.metricsCollector.recordTTSTTFB(performance.now() - ttsStartTime);
      }
      totalAudioDurationMs += chunk.durationMs;
    }

    this.metricsCollector.recordTTSCompletion(performance.now() - ttsStartTime);
    this.metricsCollector.recordTTSAudioDuration(totalAudioDurationMs);
    // For TTS-only, E2E equals TTS time
    this.metricsCollector.recordE2ELatency(performance.now() - ttsStartTime);
  }

  /**
   * Get predefined test text for a given response length.
   *
   * Used by TTS-only scenarios to have consistent test content.
   * Text lengths approximately match expected token counts:
   * - short: ~30 tokens
   * - medium: ~80 tokens
   * - long: ~150 tokens
   *
   * @param responseType - Expected response length category
   * @returns Test text appropriate for the response type
   */
  private getTestText(responseType: 'short' | 'medium' | 'long'): string {
    switch (responseType) {
      case 'short':
        return 'The capital of France is Paris. It is known for the Eiffel Tower.';
      case 'medium':
        return `Photosynthesis is the process by which plants convert sunlight into energy.
                During this process, plants absorb carbon dioxide from the air and water from the soil.
                Using sunlight as energy, they convert these into glucose and oxygen.
                The glucose provides energy for the plant to grow, while the oxygen is released into the atmosphere.`;
      case 'long':
        return `The human heart is a remarkable organ that serves as the body's primary circulatory pump.
                Located in the chest cavity between the lungs, it beats approximately 100,000 times per day.
                The heart consists of four chambers: two upper chambers called atria and two lower chambers called ventricles.
                Deoxygenated blood returns to the right atrium from the body through the superior and inferior vena cava.
                It then flows into the right ventricle, which pumps it to the lungs for oxygenation.
                Oxygen-rich blood returns from the lungs to the left atrium, flows into the left ventricle,
                and is then pumped throughout the body via the aorta.`;
    }
  }

  // ============================================================================
  // Provider Calls
  // ============================================================================

  /**
   * Make a streaming LLM request through the backend proxy.
   *
   * Calls the backend API which proxies to the configured LLM provider.
   * Uses Server-Sent Events (SSE) for streaming token delivery.
   *
   * SSE FORMAT
   * ----------
   * Each line follows the SSE format:
   * ```
   * data: {"content": "token text", "tokenCount": 5}
   * data: [DONE]
   * ```
   *
   * @param userText - The user's input text
   * @param config - LLM provider configuration
   * @yields Content and token count for each received token
   */
  private async *callLLMStreaming(
    userText: string,
    config: TestConfiguration['llm']
  ): AsyncGenerator<{ content: string; tokenCount?: number }> {
    // Call through backend API which proxies to LLM providers
    const response = await fetch(`${this.serverUrl}/api/llm/stream`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        provider: config.provider,
        model: config.model,
        messages: [
          { role: 'system', content: 'You are a helpful tutor. Be concise.' },
          { role: 'user', content: userText },
        ],
        maxTokens: config.maxTokens,
        temperature: config.temperature,
        stream: true,
      }),
    });

    if (!response.ok) {
      throw new Error(`LLM request failed: ${response.statusText}`);
    }

    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error('No response body');
    }

    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const data = line.slice(6);
          if (data === '[DONE]') continue;
          try {
            const parsed = JSON.parse(data);
            if (parsed.content) {
              yield { content: parsed.content, tokenCount: parsed.tokenCount };
            }
          } catch {
            // Ignore parse errors
          }
        }
      }
    }
  }

  /**
   * Make a streaming TTS request through the backend proxy.
   *
   * Calls the backend API which proxies to the configured TTS provider.
   * Audio is streamed as raw chunks for low-latency playback.
   *
   * AUDIO FORMAT
   * ------------
   * Expected: 24kHz 16-bit mono PCM
   * Duration is estimated from chunk size.
   *
   * @param text - The text to synthesize
   * @param config - TTS provider configuration
   * @yields Audio chunks with estimated duration
   */
  private async *callTTSStreaming(
    text: string,
    config: TestConfiguration['tts']
  ): AsyncGenerator<{ data: ArrayBuffer; durationMs: number }> {
    // Call through backend API which proxies to TTS providers
    const response = await fetch(`${this.serverUrl}/api/tts/stream`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        provider: config.provider,
        text,
        voiceId: config.voiceId,
        speed: config.speed,
        useStreaming: config.useStreaming,
        chatterboxConfig: config.chatterboxConfig,
      }),
    });

    if (!response.ok) {
      throw new Error(`TTS request failed: ${response.statusText}`);
    }

    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error('No response body');
    }

    // For simplicity, assuming chunked audio response
    // In production, would properly parse audio chunks
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      // Estimate duration from chunk size (rough approximation)
      // Assuming 24kHz 16-bit mono audio
      const samples = value.byteLength / 2;
      const durationMs = (samples / 24000) * 1000;

      yield { data: value.buffer, durationMs };
    }
  }

  // ============================================================================
  // Server Communication
  // ============================================================================

  /**
   * Report a test result to the server.
   *
   * This is a fire-and-forget operation - the result is queued for
   * server processing but we don't wait for confirmation. This
   * minimizes the impact of result reporting on test execution timing.
   *
   * OBSERVER EFFECT MITIGATION
   * --------------------------
   * Result reporting should be called AFTER test execution is complete
   * and metrics are finalized. Never call during active measurement.
   *
   * @param result - The complete test result to report
   */
  async reportResult(result: TestResult): Promise<void> {
    // Fire-and-forget: don't await response to minimize latency impact
    await fetch(`${this.serverUrl}/api/latency-tests/results`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        clientId: this.clientId,
        clientType: 'web',
        result,
      }),
    });
  }

  /**
   * Send a heartbeat to the server.
   *
   * Heartbeats inform the orchestrator that this client is alive and
   * available for test execution. Should be called periodically
   * (recommended: every 5 seconds).
   *
   * The heartbeat includes current status and capabilities, allowing
   * the orchestrator to make informed routing decisions.
   */
  async sendHeartbeat(): Promise<void> {
    await fetch(`${this.serverUrl}/api/latency-tests/heartbeat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        clientId: this.clientId,
        clientType: 'web',
        status: this.getStatus(),
        capabilities: this.getCapabilities(),
      }),
    });
  }
}

// ============================================================================
// Singleton Instance
// ============================================================================

/**
 * Singleton instance of the web coordinator.
 *
 * Use getWebLatencyTestCoordinator() to access the shared instance.
 * This ensures consistent client ID across the application.
 */
let instance: WebLatencyTestCoordinator | null = null;

/**
 * Get the singleton web latency test coordinator instance.
 *
 * Creates a new instance on first call, returns existing instance
 * on subsequent calls. The serverUrl parameter is only used on
 * first instantiation.
 *
 * @param serverUrl - URL of the management server (only used on first call)
 * @returns Singleton coordinator instance
 *
 * @example
 * ```typescript
 * const coordinator = getWebLatencyTestCoordinator('http://localhost:8766');
 * const result = await coordinator.executeTest(scenario, config);
 * coordinator.reportResult(result);  // Fire-and-forget
 * ```
 */
export function getWebLatencyTestCoordinator(serverUrl?: string): WebLatencyTestCoordinator {
  if (!instance) {
    instance = new WebLatencyTestCoordinator(serverUrl);
  }
  return instance;
}
