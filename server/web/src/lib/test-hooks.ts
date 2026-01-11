/**
 * UnaMentis - Web Client Test Hooks
 * ==================================
 *
 * Programmatic hooks for automated latency testing.
 *
 * DESIGN PRINCIPLE
 * ----------------
 * These hooks trigger the SAME code paths as user interactions, not mocks.
 * They call real LLM and TTS providers through the backend APIs.
 *
 * For the web client (which is a dashboard, not a voice client), this means:
 * - Sending text to LLM providers and streaming the response
 * - Sending text to TTS providers and streaming audio
 * - Collecting latency metrics at each stage
 *
 * USAGE (from Playwright or browser console)
 * ------------------------------------------
 * ```javascript
 * const hooks = window.__TEST_HOOKS__;
 * const session = await hooks.startSession({ llm: 'anthropic', tts: 'chatterbox' });
 * const turn1 = await hooks.sendUtterance("Hello, how are you?");
 * const turn2 = await hooks.sendUtterance("Tell me about history");
 * const metrics = await hooks.endSession();
 * console.log(`E2E p50: ${metrics.latencyP50Ms}ms`);
 * ```
 *
 * SEE ALSO
 * --------
 * - web-coordinator.ts: Lower-level test execution
 * - test_orchestrator.py: Server-side orchestration of mass testing
 */

// ============================================================================
// Types
// ============================================================================

export interface ProviderConfig {
  stt?: 'deepgram' | 'assemblyai' | 'groq' | 'whisper' | 'web-speech';
  llm?: 'anthropic' | 'openai' | 'selfhosted';
  llmModel?: string;
  tts?:
    | 'chatterbox'
    | 'vibevoice'
    | 'elevenlabs-flash'
    | 'elevenlabs-turbo'
    | 'deepgram'
    | 'piper'
    | 'web-speech';
  ttsVoice?: string;
}

export interface TurnResult {
  turnNumber: number;
  userUtterance: string;
  aiResponse: string;
  latencies: {
    llmTTFBMs: number;
    llmCompletionMs: number;
    ttsTTFBMs: number;
    ttsCompletionMs: number;
    e2eMs: number;
  };
  tokenCounts: {
    inputTokens: number;
    outputTokens: number;
  };
  timestamp: string;
  isSuccess: boolean;
  error?: string;
}

export interface SessionMetrics {
  sessionId: string;
  turnsCompleted: number;
  totalDurationMs: number;
  latencyP50Ms: number;
  latencyP95Ms: number;
  latencyP99Ms: number;
  avgLatencyMs: number;
  successRate: number;
  turns: TurnResult[];
  config: ProviderConfig;
}

// ============================================================================
// Test Hooks Implementation
// ============================================================================

/**
 * Test hooks for automated latency testing.
 *
 * Each hook triggers the same code path as the corresponding user action.
 * This is NOT a mock - it calls real providers through the backend.
 */
export class TestHooks {
  private serverUrl: string;
  private sessionId: string | null = null;
  private sessionStartTime: number = 0;
  private turns: TurnResult[] = [];
  private config: ProviderConfig = {};
  private isSessionActive: boolean = false;

  constructor(serverUrl: string = 'http://localhost:8766') {
    this.serverUrl = serverUrl;
  }

  /**
   * Start a new test session.
   *
   * Equivalent to user clicking "Start Session" button.
   * Initializes the session state and provider configuration.
   *
   * @param config - Provider configuration (LLM, TTS, etc.)
   * @returns Session ID
   */
  async startSession(config: ProviderConfig = {}): Promise<string> {
    if (this.isSessionActive) {
      throw new Error('Session already active. Call endSession() first.');
    }

    this.sessionId = crypto.randomUUID();
    this.sessionStartTime = performance.now();
    this.turns = [];
    this.config = {
      llm: config.llm ?? 'anthropic',
      llmModel: config.llmModel ?? 'claude-3-5-haiku-20241022',
      tts: config.tts ?? 'chatterbox',
      ttsVoice: config.ttsVoice,
      ...config,
    };
    this.isSessionActive = true;

    // Optionally notify server of session start
    try {
      await fetch(`${this.serverUrl}/api/metrics/session-start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sessionId: this.sessionId,
          clientType: 'web_test',
          config: this.config,
          timestamp: new Date().toISOString(),
        }),
      });
    } catch {
      // Fire-and-forget, don't fail if server unavailable
    }

    return this.sessionId;
  }

  /**
   * Send an utterance and get AI response.
   *
   * Equivalent to user speaking into microphone.
   * For testing, accepts text directly (bypasses STT) to test LLM + TTS.
   *
   * Pipeline executed:
   * 1. Text sent to LLM (streaming)
   * 2. LLM response sent to TTS (streaming)
   * 3. Metrics collected at each stage
   *
   * @param text - The user's utterance text
   * @returns Turn result with AI response and latencies
   */
  async sendUtterance(text: string): Promise<TurnResult> {
    if (!this.isSessionActive || !this.sessionId) {
      throw new Error('No active session. Call startSession() first.');
    }

    const turnNumber = this.turns.length + 1;
    const turnStartTime = performance.now();

    let llmTTFBMs = 0;
    let llmCompletionMs = 0;
    let ttsTTFBMs = 0;
    let ttsCompletionMs = 0;
    let aiResponse = '';
    let inputTokens = 0;
    let outputTokens = 0;
    let isSuccess = true;
    let error: string | undefined;

    try {
      // Phase 1: LLM streaming
      const llmStartTime = performance.now();
      let firstTokenReceived = false;

      const llmResponse = await fetch(`${this.serverUrl}/api/llm/stream`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          provider: this.config.llm,
          model: this.config.llmModel,
          messages: [
            { role: 'system', content: 'You are a helpful tutor. Be concise but informative.' },
            // Include conversation history for context
            ...this.turns
              .map((t) => [
                { role: 'user', content: t.userUtterance },
                { role: 'assistant', content: t.aiResponse },
              ])
              .flat(),
            { role: 'user', content: text },
          ],
          maxTokens: 512,
          temperature: 0.7,
          stream: true,
        }),
      });

      if (!llmResponse.ok) {
        throw new Error(`LLM request failed: ${llmResponse.statusText}`);
      }

      const reader = llmResponse.body?.getReader();
      if (!reader) throw new Error('No response body');

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
                if (!firstTokenReceived) {
                  firstTokenReceived = true;
                  llmTTFBMs = performance.now() - llmStartTime;
                }
                aiResponse += parsed.content;
              }
              if (parsed.tokenCount) {
                outputTokens = parsed.tokenCount;
              }
            } catch {
              // Ignore parse errors
            }
          }
        }
      }

      llmCompletionMs = performance.now() - llmStartTime;
      inputTokens = Math.ceil(text.length / 4); // Rough estimate

      // Phase 2: TTS streaming
      const ttsStartTime = performance.now();
      let firstAudioReceived = false;

      const ttsResponse = await fetch(`${this.serverUrl}/api/tts/stream`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          provider: this.config.tts,
          text: aiResponse,
          voiceId: this.config.ttsVoice,
          speed: 1.0,
          useStreaming: true,
        }),
      });

      if (!ttsResponse.ok) {
        throw new Error(`TTS request failed: ${ttsResponse.statusText}`);
      }

      const ttsReader = ttsResponse.body?.getReader();
      if (ttsReader) {
        while (true) {
          const { done, value } = await ttsReader.read();
          if (done) break;

          if (!firstAudioReceived && value && value.length > 0) {
            firstAudioReceived = true;
            ttsTTFBMs = performance.now() - ttsStartTime;
          }
        }
      }

      ttsCompletionMs = performance.now() - ttsStartTime;
    } catch (e) {
      isSuccess = false;
      error = e instanceof Error ? e.message : String(e);
    }

    const e2eMs = performance.now() - turnStartTime;

    const result: TurnResult = {
      turnNumber,
      userUtterance: text,
      aiResponse,
      latencies: {
        llmTTFBMs,
        llmCompletionMs,
        ttsTTFBMs,
        ttsCompletionMs,
        e2eMs,
      },
      tokenCounts: {
        inputTokens,
        outputTokens,
      },
      timestamp: new Date().toISOString(),
      isSuccess,
      error,
    };

    this.turns.push(result);

    // Fire-and-forget metric reporting
    try {
      await fetch(`${this.serverUrl}/api/metrics/turn`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sessionId: this.sessionId,
          ...result,
        }),
      });
    } catch {
      // Ignore reporting errors
    }

    return result;
  }

  /**
   * End the current session.
   *
   * Equivalent to user clicking "End Session" button.
   * Calculates aggregate metrics and reports to server.
   *
   * @returns Complete session metrics with all turns
   */
  async endSession(): Promise<SessionMetrics> {
    if (!this.isSessionActive || !this.sessionId) {
      throw new Error('No active session to end.');
    }

    const totalDurationMs = performance.now() - this.sessionStartTime;

    // Calculate latency percentiles from E2E times
    const e2eLatencies = this.turns
      .filter((t) => t.isSuccess)
      .map((t) => t.latencies.e2eMs)
      .sort((a, b) => a - b);

    const percentile = (arr: number[], p: number): number => {
      if (arr.length === 0) return 0;
      const idx = Math.ceil((p / 100) * arr.length) - 1;
      return arr[Math.max(0, idx)];
    };

    const avgLatencyMs =
      e2eLatencies.length > 0 ? e2eLatencies.reduce((a, b) => a + b, 0) / e2eLatencies.length : 0;

    const successRate =
      this.turns.length > 0
        ? (this.turns.filter((t) => t.isSuccess).length / this.turns.length) * 100
        : 0;

    const metrics: SessionMetrics = {
      sessionId: this.sessionId,
      turnsCompleted: this.turns.length,
      totalDurationMs,
      latencyP50Ms: percentile(e2eLatencies, 50),
      latencyP95Ms: percentile(e2eLatencies, 95),
      latencyP99Ms: percentile(e2eLatencies, 99),
      avgLatencyMs,
      successRate,
      turns: this.turns,
      config: this.config,
    };

    // Report final metrics to server
    try {
      await fetch(`${this.serverUrl}/api/metrics/session-end`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...metrics,
          timestamp: new Date().toISOString(),
        }),
      });
    } catch {
      // Ignore reporting errors
    }

    // Reset state
    this.isSessionActive = false;
    this.sessionId = null;
    this.turns = [];

    return metrics;
  }

  /**
   * Check if a session is currently active.
   */
  isActive(): boolean {
    return this.isSessionActive;
  }

  /**
   * Get the current session ID.
   */
  getSessionId(): string | null {
    return this.sessionId;
  }

  /**
   * Get the number of turns completed in the current session.
   */
  getTurnCount(): number {
    return this.turns.length;
  }
}

// ============================================================================
// Global Singleton for Browser Access
// ============================================================================

let instance: TestHooks | null = null;

/**
 * Get the singleton TestHooks instance.
 *
 * @param serverUrl - Server URL (only used on first call)
 */
export function getTestHooks(serverUrl?: string): TestHooks {
  if (!instance) {
    instance = new TestHooks(serverUrl);
  }
  return instance;
}

/**
 * Initialize and expose test hooks on window for browser/Playwright access.
 *
 * Call this during app initialization to make hooks available globally:
 * ```typescript
 * import { initializeTestHooks } from '@/lib/test-hooks';
 * initializeTestHooks('http://localhost:8766');
 * ```
 *
 * Then access from Playwright:
 * ```javascript
 * await page.evaluate(async () => {
 *   const hooks = window.__TEST_HOOKS__;
 *   await hooks.startSession();
 *   await hooks.sendUtterance("Hello");
 *   return await hooks.endSession();
 * });
 * ```
 */
export function initializeTestHooks(serverUrl?: string): TestHooks {
  const hooks = getTestHooks(serverUrl);

  if (typeof window !== 'undefined') {
    // Expose on window for Playwright/browser access
    (window as unknown as { __TEST_HOOKS__: TestHooks }).__TEST_HOOKS__ = hooks;
  }

  return hooks;
}

// Auto-initialize in browser environment
if (typeof window !== 'undefined') {
  initializeTestHooks();
}
