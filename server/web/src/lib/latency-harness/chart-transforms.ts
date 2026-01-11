/**
 * Chart Data Transformation Utilities
 * ====================================
 *
 * Functions to transform latency test data into formats suitable
 * for ECharts visualizations.
 */

import type {
  TestResult,
  TestRun,
  MetricType,
  NetworkProfile,
  TimeSeriesDataPoint,
  HistogramBin,
  BoxPlotData,
  HeatmapData,
  NetworkProjectionData,
} from '@/types/latency-charts';
import { NetworkLatencyMs } from '@/types/latency-charts';

// ============================================================================
// Statistical Utilities
// ============================================================================

/**
 * Calculate median of an array of numbers.
 */
export function calculateMedian(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 !== 0 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/**
 * Calculate a specific percentile of an array of numbers.
 */
export function calculatePercentile(values: number[], percentile: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const index = (percentile / 100) * (sorted.length - 1);
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  if (lower === upper) return sorted[lower];
  return sorted[lower] * (upper - index) + sorted[upper] * (index - lower);
}

/**
 * Calculate P99 (99th percentile) of an array.
 */
export function calculateP99(values: number[]): number {
  return calculatePercentile(values, 99);
}

/**
 * Find outliers using IQR method.
 */
export function findOutliers(values: number[]): number[] {
  if (values.length < 4) return [];
  const sorted = [...values].sort((a, b) => a - b);
  const q1 = calculatePercentile(sorted, 25);
  const q3 = calculatePercentile(sorted, 75);
  const iqr = q3 - q1;
  const lowerBound = q1 - 1.5 * iqr;
  const upperBound = q3 + 1.5 * iqr;
  return sorted.filter((v) => v < lowerBound || v > upperBound);
}

// ============================================================================
// Metric Extraction
// ============================================================================

/**
 * Get the metric value from a test result based on metric type.
 */
export function getMetricValue(result: TestResult, metric: MetricType): number | null {
  switch (metric) {
    case 'e2e':
      return result.e2eLatencyMs;
    case 'stt':
      return result.sttLatencyMs;
    case 'llm_ttfb':
      return result.llmTTFBMs;
    case 'llm_completion':
      return result.llmCompletionMs;
    case 'tts_ttfb':
      return result.ttsTTFBMs;
    case 'tts_completion':
      return result.ttsCompletionMs;
    default:
      return null;
  }
}

// ============================================================================
// Time Series Transforms
// ============================================================================

/**
 * Transform test runs to time-series data for trend charts.
 * Returns one data point per run with aggregated statistics.
 */
export function transformToTimeSeries(
  runs: TestRun[],
  metric: MetricType = 'e2e'
): TimeSeriesDataPoint[] {
  return runs
    .filter((run) => run.status === 'completed' && run.results.length > 0)
    .map((run) => {
      const values = run.results
        .map((r) => getMetricValue(r, metric))
        .filter((v): v is number => v !== null && !isNaN(v));

      if (values.length === 0) {
        return null;
      }

      return {
        timestamp: new Date(run.completedAt || run.startedAt).getTime(),
        median: calculateMedian(values),
        p99: calculateP99(values),
        min: Math.min(...values),
        max: Math.max(...values),
        runId: run.id,
        suiteName: run.suiteName,
      };
    })
    .filter((point): point is TimeSeriesDataPoint => point !== null)
    .sort((a, b) => a.timestamp - b.timestamp);
}

// ============================================================================
// Distribution Transforms
// ============================================================================

/**
 * Transform results to histogram bins for distribution charts.
 */
export function transformToHistogram(
  results: TestResult[],
  metric: MetricType = 'e2e',
  binCount: number = 20
): HistogramBin[] {
  const values = results
    .map((r) => getMetricValue(r, metric))
    .filter((v): v is number => v !== null && !isNaN(v));

  if (values.length === 0) {
    return [];
  }

  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min;

  // Handle edge case where all values are the same
  if (range === 0) {
    return [
      {
        x: min,
        y: values.length,
        range: `${Math.round(min)}ms`,
      },
    ];
  }

  const binWidth = range / binCount;

  const bins: HistogramBin[] = Array.from({ length: binCount }, (_, i) => ({
    x: min + i * binWidth + binWidth / 2, // Center of bin
    y: 0,
    range: `${Math.round(min + i * binWidth)}-${Math.round(min + (i + 1) * binWidth)}ms`,
  }));

  values.forEach((v) => {
    const binIndex = Math.min(Math.floor((v - min) / binWidth), binCount - 1);
    bins[binIndex].y++;
  });

  return bins;
}

/**
 * Transform results to box plot data grouped by configuration.
 */
export function transformToBoxPlot(
  results: TestResult[],
  metric: MetricType = 'e2e',
  groupBy: 'config' | 'provider' = 'config'
): BoxPlotData[] {
  // Group results
  const groups: Record<string, TestResult[]> = {};

  results.forEach((result) => {
    let key: string;
    if (groupBy === 'config') {
      key = result.configId;
    } else {
      // Group by provider combination (use helper functions for fallback)
      const llm = getLLMProvider(result);
      const tts = getTTSProvider(result);
      key = `${llm} + ${tts}`;
    }

    if (!groups[key]) {
      groups[key] = [];
    }
    groups[key].push(result);
  });

  // Calculate box plot data for each group
  return Object.entries(groups)
    .map(([name, groupResults]) => {
      const values = groupResults
        .map((r) => getMetricValue(r, metric))
        .filter((v): v is number => v !== null && !isNaN(v))
        .sort((a, b) => a - b);

      if (values.length === 0) {
        return null;
      }

      return {
        name: shortenConfigName(name),
        min: values[0],
        q1: calculatePercentile(values, 25),
        median: calculateMedian(values),
        q3: calculatePercentile(values, 75),
        max: values[values.length - 1],
        outliers: findOutliers(values),
      };
    })
    .filter((data): data is BoxPlotData => data !== null)
    .sort((a, b) => a.median - b.median); // Sort by median
}

// ============================================================================
// Heatmap Transforms
// ============================================================================

/**
 * Transform results to heatmap data for provider comparison.
 */
export function transformToHeatmap(results: TestResult[], metric: MetricType = 'e2e'): HeatmapData {
  // Extract unique providers using helper functions that fallback to configId parsing
  const llmProviders = [...new Set(results.map((r) => getLLMProvider(r)))].sort();
  const ttsProviders = [...new Set(results.map((r) => getTTSProvider(r)))].sort();

  // Calculate median for each combination
  const data: [number, number, number][] = [];

  llmProviders.forEach((llm, x) => {
    ttsProviders.forEach((tts, y) => {
      const matching = results.filter(
        (r) => getLLMProvider(r) === llm && getTTSProvider(r) === tts
      );

      if (matching.length > 0) {
        const values = matching
          .map((r) => getMetricValue(r, metric))
          .filter((v): v is number => v !== null && !isNaN(v));

        if (values.length > 0) {
          data.push([x, y, Math.round(calculateMedian(values))]);
        }
      }
    });
  });

  return {
    xAxis: llmProviders,
    yAxis: ttsProviders,
    data,
  };
}

// ============================================================================
// Network Projection Transforms
// ============================================================================

/**
 * Transform results to network projection data.
 */
export function transformToNetworkProjections(results: TestResult[]): NetworkProjectionData[] {
  const profiles: NetworkProfile[] = [
    'localhost',
    'wifi',
    'cellular_us',
    'cellular_eu',
    'intercontinental',
  ];

  return profiles.map((profile) => {
    // Get base E2E latencies
    const baseLatencies = results
      .map((r) => r.e2eLatencyMs)
      .filter((v): v is number => v !== null && !isNaN(v));

    if (baseLatencies.length === 0) {
      return {
        profile,
        addedLatency: NetworkLatencyMs[profile],
        projectedMedian: 0,
        projectedP99: 0,
        meetsTarget500: false,
        meetsTarget1000: false,
        configsMeetingTarget: 0,
        totalConfigs: 0,
      };
    }

    // Project latencies for this network profile
    const addedLatency = NetworkLatencyMs[profile];
    const projected = baseLatencies.map((v) => v + addedLatency);

    const projectedMedian = calculateMedian(projected);
    const projectedP99 = calculateP99(projected);
    const configsMeetingTarget = projected.filter((v) => v <= 500).length;

    return {
      profile,
      addedLatency,
      projectedMedian,
      projectedP99,
      meetsTarget500: projectedMedian <= 500,
      meetsTarget1000: projectedP99 <= 1000,
      configsMeetingTarget,
      totalConfigs: projected.length,
    };
  });
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Extract provider info from configId when config objects are null.
 * ConfigId format: "{stt}_{llm}_{model}_{tts}"
 * Example: "deepgram_anthropic_claude-3-5-haiku-20241022_chatterbox"
 */
export function parseConfigId(configId: string): {
  stt: string;
  llm: string;
  model: string;
  tts: string;
} {
  const parts = configId.split('_');
  if (parts.length >= 4) {
    // Format: stt_llm_model_tts (model may contain underscores)
    const stt = parts[0];
    const llm = parts[1];
    const tts = parts[parts.length - 1];
    // Model is everything between llm and tts
    const model = parts.slice(2, -1).join('_');
    return { stt, llm, model, tts };
  }
  // Fallback for unexpected formats
  return {
    stt: parts[0] || 'unknown',
    llm: parts[1] || 'unknown',
    model: parts[2] || 'unknown',
    tts: parts[3] || parts[parts.length - 1] || 'unknown',
  };
}

/**
 * Get LLM provider from result, falling back to configId parsing.
 */
export function getLLMProvider(result: TestResult): string {
  if (result.llmConfig?.provider) {
    return result.llmConfig.provider;
  }
  return parseConfigId(result.configId).llm;
}

/**
 * Get TTS provider from result, falling back to configId parsing.
 */
export function getTTSProvider(result: TestResult): string {
  if (result.ttsConfig?.provider) {
    return result.ttsConfig.provider;
  }
  return parseConfigId(result.configId).tts;
}

/**
 * Get STT provider from result, falling back to configId parsing.
 */
export function getSTTProvider(result: TestResult): string {
  if (result.sttConfig?.provider) {
    return result.sttConfig.provider;
  }
  return parseConfigId(result.configId).stt;
}

/**
 * Shorten a config ID for display.
 * Example: "deepgram_anthropic_claude-3-5-haiku_chatterbox" -> "deepgram/haiku/chatterbox"
 */
export function shortenConfigName(configId: string): string {
  const parts = configId.split('_');
  if (parts.length <= 2) return configId;

  // Try to extract meaningful parts
  const stt = parts[0];
  const model = parts.find(
    (p) => p.includes('claude') || p.includes('gpt') || p.includes('gemini')
  );
  const tts = parts[parts.length - 1];

  if (model) {
    // Extract just the model variant
    const modelShort = model
      .replace('claude-', '')
      .replace('gpt-', '')
      .replace('-20241022', '')
      .replace('-20250219', '');
    return `${stt}/${modelShort}/${tts}`;
  }

  return `${stt}/${tts}`;
}

/**
 * Format milliseconds for display.
 */
export function formatMs(ms: number): string {
  if (ms < 1) return '<1ms';
  if (ms < 1000) return `${Math.round(ms)}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

/**
 * Get all unique configurations from results.
 */
export function getUniqueConfigs(results: TestResult[]): string[] {
  return [...new Set(results.map((r) => r.configId))].sort();
}

/**
 * Aggregate results by run for summary statistics.
 */
export function aggregateByRun(
  runs: TestRun[],
  metric: MetricType = 'e2e'
): Array<{
  runId: string;
  suiteName: string;
  timestamp: string;
  median: number;
  p99: number;
  count: number;
}> {
  return runs
    .filter((run) => run.status === 'completed')
    .map((run) => {
      const values = run.results
        .map((r) => getMetricValue(r, metric))
        .filter((v): v is number => v !== null && !isNaN(v));

      return {
        runId: run.id,
        suiteName: run.suiteName,
        timestamp: run.completedAt || run.startedAt,
        median: calculateMedian(values),
        p99: calculateP99(values),
        count: values.length,
      };
    })
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
}
