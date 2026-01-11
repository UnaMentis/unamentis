/**
 * Latency Charts Type Definitions
 * ===============================
 *
 * TypeScript types for the latency test dashboard visualizations.
 */

// ============================================================================
// Metric Types
// ============================================================================

/** Available latency metrics for visualization */
export type MetricType =
  | 'e2e'
  | 'stt'
  | 'llm_ttfb'
  | 'llm_completion'
  | 'tts_ttfb'
  | 'tts_completion';

/** Human-readable labels for metric types */
export const MetricLabels: Record<MetricType, string> = {
  e2e: 'End-to-End',
  stt: 'STT',
  llm_ttfb: 'LLM TTFB',
  llm_completion: 'LLM Completion',
  tts_ttfb: 'TTS TTFB',
  tts_completion: 'TTS Completion',
};

// ============================================================================
// Network Types
// ============================================================================

/** Network profile identifiers */
export type NetworkProfile =
  | 'localhost'
  | 'wifi'
  | 'cellular_us'
  | 'cellular_eu'
  | 'intercontinental';

/** Human-readable labels for network profiles */
export const NetworkProfileLabels: Record<NetworkProfile, string> = {
  localhost: 'Localhost',
  wifi: 'Wi-Fi',
  cellular_us: 'Cellular (US)',
  cellular_eu: 'Cellular (EU)',
  intercontinental: 'Intercontinental',
};

/** Added latency for each network profile (ms) */
export const NetworkLatencyMs: Record<NetworkProfile, number> = {
  localhost: 0,
  wifi: 10,
  cellular_us: 50,
  cellular_eu: 100,
  intercontinental: 200,
};

// ============================================================================
// Time Series Types
// ============================================================================

/** Data point for time-series trend charts */
export interface TimeSeriesDataPoint {
  /** Unix timestamp in milliseconds */
  timestamp: number;
  /** Median latency value */
  median: number;
  /** 99th percentile latency value */
  p99: number;
  /** Minimum latency value */
  min: number;
  /** Maximum latency value */
  max: number;
  /** Run identifier */
  runId: string;
  /** Suite name */
  suiteName: string;
}

// ============================================================================
// Distribution Types
// ============================================================================

/** Histogram bin for distribution charts */
export interface HistogramBin {
  /** Start of bin range (ms) */
  x: number;
  /** Count of values in bin */
  y: number;
  /** Human-readable range label */
  range: string;
}

/** Box plot data for distribution analysis */
export interface BoxPlotData {
  /** Configuration or provider name */
  name: string;
  /** Minimum value */
  min: number;
  /** First quartile (25th percentile) */
  q1: number;
  /** Median (50th percentile) */
  median: number;
  /** Third quartile (75th percentile) */
  q3: number;
  /** Maximum value */
  max: number;
  /** Outlier values */
  outliers: number[];
}

// ============================================================================
// Heatmap Types
// ============================================================================

/** Heatmap data for provider comparison */
export interface HeatmapData {
  /** X-axis labels (e.g., LLM providers) */
  xAxis: string[];
  /** Y-axis labels (e.g., TTS providers) */
  yAxis: string[];
  /** Data points [x, y, value] */
  data: [number, number, number][];
}

// ============================================================================
// Network Projection Types
// ============================================================================

/** Network projection data for a single profile */
export interface NetworkProjectionData {
  /** Network profile identifier */
  profile: NetworkProfile;
  /** Added latency for this profile */
  addedLatency: number;
  /** Projected median E2E latency */
  projectedMedian: number;
  /** Projected P99 E2E latency */
  projectedP99: number;
  /** Whether median meets 500ms target */
  meetsTarget500: boolean;
  /** Whether P99 meets 1000ms target */
  meetsTarget1000: boolean;
  /** Number of configs meeting target */
  configsMeetingTarget: number;
  /** Total number of configs */
  totalConfigs: number;
}

// ============================================================================
// Dashboard State Types
// ============================================================================

/** Chart tab identifiers */
export type ChartTabId = 'trends' | 'distribution' | 'comparison' | 'network';

/** Dashboard state */
export interface DashboardState {
  /** Selected run IDs for comparison (up to 5) */
  selectedRuns: string[];
  /** Selected metric type to display */
  selectedMetric: MetricType;
  /** Active chart tab */
  activeChartTab: ChartTabId;
  /** Whether real-time updates are enabled */
  isRealTimeEnabled: boolean;
}

// ============================================================================
// API Response Types
// ============================================================================

/** Test result from the API */
export interface TestResult {
  id: string;
  configId: string;
  scenarioName: string;
  repetition: number;
  timestamp: string;
  clientType: string;
  sttLatencyMs: number | null;
  llmTTFBMs: number;
  llmCompletionMs: number;
  ttsTTFBMs: number;
  ttsCompletionMs: number;
  e2eLatencyMs: number;
  networkProfile: NetworkProfile;
  networkProjections: Record<string, number>;
  sttConfidence: number | null;
  ttsAudioDurationMs: number | null;
  llmOutputTokens: number | null;
  llmInputTokens: number | null;
  peakCPUPercent: number | null;
  peakMemoryMB: number | null;
  thermalState: string | null;
  sttConfig: ProviderConfig | null;
  llmConfig: ProviderConfig | null;
  ttsConfig: ProviderConfig | null;
  audioConfig: AudioConfig | null;
  errors: string[];
  isSuccess: boolean;
}

/** Provider configuration snapshot */
export interface ProviderConfig {
  provider: string;
  model?: string;
}

/** Audio configuration snapshot */
export interface AudioConfig {
  sampleRate: number;
}

/** Test run from the API */
export interface TestRun {
  id: string;
  suiteName: string;
  suiteId: string;
  startedAt: string;
  completedAt: string | null;
  clientId: string;
  clientType: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  totalConfigurations: number;
  completedConfigurations: number;
  progressPercent: number;
  elapsedTimeSeconds: number;
  results: TestResult[];
}

/** Analysis summary from the API */
export interface AnalysisSummary {
  totalConfigurations: number;
  totalTests: number;
  successfulTests: number;
  failedTests: number;
  overallMedianE2EMs: number;
  overallP99E2EMs: number;
  overallMinE2EMs: number;
  overallMaxE2EMs: number;
  medianSTTMs: number | null;
  medianLLMTTFBMs: number;
  medianLLMCompletionMs: number;
  medianTTSTTFBMs: number;
  medianTTSCompletionMs: number;
  testDurationMinutes: number;
}
