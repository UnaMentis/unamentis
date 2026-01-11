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
import {
  getLLMProvider,
  getTTSProvider,
  getSTTProvider,
} from '@/lib/latency-harness/chart-transforms';

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
  const {
    autoRefresh = true,
    refreshInterval = DEFAULT_REFRESH_INTERVAL,
    limit = DEFAULT_LIMIT,
  } = options;

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
  const [analysisData, setAnalysisData] = useState<AnalysisSummary | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!runId) return;

    let cancelled = false;
    const abortController = new AbortController();

    const fetchAnalysis = async () => {
      try {
        const res = await fetch(`${API_BASE}/api/latency-tests/runs/${runId}/analysis`, {
          signal: abortController.signal,
        });
        if (!res.ok) throw new Error(`Failed to fetch analysis: ${res.status}`);
        const data = await res.json();
        if (!cancelled) {
          setAnalysisData(data.summary);
          setError(null);
          setLoading(false);
        }
      } catch (err) {
        if (!cancelled && err instanceof Error && err.name !== 'AbortError') {
          setError(err.message);
          setLoading(false);
        }
      }
    };

    // Set loading state before async work via microtask to satisfy lint rule
    queueMicrotask(() => {
      if (!cancelled) setLoading(true);
    });
    fetchAnalysis();

    return () => {
      cancelled = true;
      abortController.abort();
    };
  }, [runId]);

  // Derive null analysis when runId is null
  const analysis = runId ? analysisData : null;

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
  const [runsData, setRunsData] = useState<TestRun[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (runIds.length === 0) return;

    let cancelled = false;
    const abortController = new AbortController();

    const fetchRuns = async () => {
      try {
        const res = await fetch(`${API_BASE}/api/latency-tests/runs?limit=100`, {
          signal: abortController.signal,
        });
        if (!res.ok) throw new Error(`Failed to fetch runs: ${res.status}`);
        const data = await res.json();
        if (!cancelled) {
          const allRuns: TestRun[] = data.runs || [];
          const filtered = allRuns.filter((r) => runIds.includes(r.id));
          setRunsData(filtered);
          setError(null);
          setLoading(false);
        }
      } catch (err) {
        if (!cancelled && err instanceof Error && err.name !== 'AbortError') {
          setError(err.message);
          setLoading(false);
        }
      }
    };

    // Set loading state before async work via microtask to satisfy lint rule
    queueMicrotask(() => {
      if (!cancelled) setLoading(true);
    });
    fetchRuns();

    return () => {
      cancelled = true;
      abortController.abort();
    };
  }, [runIds.join(',')]); // eslint-disable-line react-hooks/exhaustive-deps

  // Derive empty array when no runIds
  const runs = runIds.length === 0 ? [] : runsData;

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
    // Use helper functions that fallback to configId parsing when configs are null
    const uniqueLLM = [...new Set(allResults.map((r) => getLLMProvider(r)))];
    const uniqueTTS = [...new Set(allResults.map((r) => getTTSProvider(r)))];
    const uniqueSTT = [...new Set(allResults.map((r) => getSTTProvider(r)))];

    return {
      results: allResults,
      count: allResults.length,
      uniqueConfigs,
      uniqueProviders: {
        llm: uniqueLLM,
        tts: uniqueTTS,
        stt: uniqueSTT,
      },
    };
  }, [runs]);
}
