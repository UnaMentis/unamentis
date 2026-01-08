/**
 * Latency Data Hook
 * =================
 *
 * Custom hook for fetching and managing latency test data
 * with caching and optional auto-refresh.
 */

'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import type { TestRun, AnalysisSummary } from '@/types/latency-charts';

// ============================================================================
// Configuration
// ============================================================================

const API_BASE = process.env.NEXT_PUBLIC_MANAGEMENT_API_URL || 'http://localhost:8766';
const DEFAULT_REFRESH_INTERVAL = 30000; // 30 seconds
const DEFAULT_LIMIT = 50;

// ============================================================================
// Types
// ============================================================================

interface UseLatencyDataOptions {
  /** Enable automatic refresh */
  autoRefresh?: boolean;
  /** Refresh interval in milliseconds */
  refreshInterval?: number;
  /** Maximum number of runs to fetch */
  limit?: number;
}

interface UseLatencyDataReturn {
  /** List of test runs */
  runs: TestRun[];
  /** Loading state */
  loading: boolean;
  /** Error message if any */
  error: string | null;
  /** Manually refresh data */
  refetch: () => Promise<void>;
  /** Get completed runs only */
  completedRuns: TestRun[];
  /** Get runs with results */
  runsWithResults: TestRun[];
}

interface UseRunAnalysisReturn {
  /** Analysis data */
  analysis: AnalysisSummary | null;
  /** Loading state */
  loading: boolean;
  /** Error message if any */
  error: string | null;
}

// ============================================================================
// Main Hook
// ============================================================================

/**
 * Hook for fetching latency test runs with auto-refresh support.
 *
 * @example
 * ```tsx
 * const { runs, loading, error, refetch } = useLatencyData({
 *   autoRefresh: true,
 *   refreshInterval: 30000,
 * });
 * ```
 */
export function useLatencyData(options: UseLatencyDataOptions = {}): UseLatencyDataReturn {
  const { autoRefresh = true, refreshInterval = DEFAULT_REFRESH_INTERVAL, limit = DEFAULT_LIMIT } = options;

  const [runs, setRuns] = useState<TestRun[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRuns = useCallback(async () => {
    try {
      const response = await fetch(`${API_BASE}/api/latency-tests/runs?limit=${limit}`);
      if (!response.ok) {
        throw new Error(`Failed to fetch runs: ${response.status}`);
      }
      const data = await response.json();
      setRuns(data.runs || []);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }, [limit]);

  // Initial fetch
  useEffect(() => {
    fetchRuns();
  }, [fetchRuns]);

  // Auto-refresh
  useEffect(() => {
    if (!autoRefresh) return;

    const interval = setInterval(fetchRuns, refreshInterval);
    return () => clearInterval(interval);
  }, [autoRefresh, refreshInterval, fetchRuns]);

  // Derived data
  const completedRuns = useMemo(() => runs.filter((r) => r.status === 'completed'), [runs]);

  const runsWithResults = useMemo(
    () => runs.filter((r) => r.status === 'completed' && r.results && r.results.length > 0),
    [runs]
  );

  return {
    runs,
    loading,
    error,
    refetch: fetchRuns,
    completedRuns,
    runsWithResults,
  };
}

// ============================================================================
// Run Analysis Hook
// ============================================================================

/**
 * Hook for fetching analysis for a specific run.
 */
export function useRunAnalysis(runId: string | null): UseRunAnalysisReturn {
  const [analysis, setAnalysis] = useState<AnalysisSummary | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!runId) {
      setAnalysis(null);
      return;
    }

    setLoading(true);
    setError(null);

    fetch(`${API_BASE}/api/latency-tests/runs/${runId}/analysis`)
      .then((res) => {
        if (!res.ok) throw new Error(`Failed to fetch analysis: ${res.status}`);
        return res.json();
      })
      .then((data) => setAnalysis(data.summary))
      .catch((err) => setError(err instanceof Error ? err.message : 'Unknown error'))
      .finally(() => setLoading(false));
  }, [runId]);

  return { analysis, loading, error };
}

// ============================================================================
// Multiple Runs Hook
// ============================================================================

/**
 * Hook for fetching multiple specific runs by ID.
 */
export function useMultipleRuns(runIds: string[]): {
  runs: TestRun[];
  loading: boolean;
  error: string | null;
} {
  const [runs, setRuns] = useState<TestRun[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (runIds.length === 0) {
      setRuns([]);
      return;
    }

    setLoading(true);
    setError(null);

    // Fetch all runs and filter by IDs
    fetch(`${API_BASE}/api/latency-tests/runs?limit=100`)
      .then((res) => {
        if (!res.ok) throw new Error(`Failed to fetch runs: ${res.status}`);
        return res.json();
      })
      .then((data) => {
        const allRuns: TestRun[] = data.runs || [];
        const filtered = allRuns.filter((r) => runIds.includes(r.id));
        setRuns(filtered);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Unknown error'))
      .finally(() => setLoading(false));
  }, [runIds.join(',')]); // eslint-disable-line react-hooks/exhaustive-deps

  return { runs, loading, error };
}

// ============================================================================
// Aggregated Results Hook
// ============================================================================

/**
 * Hook that aggregates results from multiple runs.
 */
export function useAggregatedResults(runs: TestRun[]) {
  return useMemo(() => {
    const allResults = runs.flatMap((r) => r.results || []);

    if (allResults.length === 0) {
      return {
        results: [],
        count: 0,
        uniqueConfigs: [],
        uniqueProviders: { llm: [], tts: [], stt: [] },
      };
    }

    const uniqueConfigs = [...new Set(allResults.map((r) => r.configId))];
    const uniqueLLM = [...new Set(allResults.map((r) => r.llmConfig?.provider).filter(Boolean))];
    const uniqueTTS = [...new Set(allResults.map((r) => r.ttsConfig?.provider).filter(Boolean))];
    const uniqueSTT = [...new Set(allResults.map((r) => r.sttConfig?.provider).filter(Boolean))];

    return {
      results: allResults,
      count: allResults.length,
      uniqueConfigs,
      uniqueProviders: {
        llm: uniqueLLM as string[],
        tts: uniqueTTS as string[],
        stt: uniqueSTT as string[],
      },
    };
  }, [runs]);
}
