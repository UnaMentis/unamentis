/**
 * Latency Dashboard Component
 * ===========================
 *
 * Main container for the latency test analytics dashboard.
 * Provides visualizations for trends, distributions, provider comparisons,
 * and network projections.
 */

'use client';

import { useState, useMemo } from 'react';
import { TrendingUp, BarChart3, Grid3X3, Globe, RefreshCw, Activity } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { useLatencyData, useAggregatedResults } from '@/hooks/useLatencyData';
import { TrendChart } from './TrendChart';
import { DistributionChart } from './DistributionChart';
import { ProviderHeatmap } from './ProviderHeatmap';
import { NetworkProjectionGrid } from './NetworkProjectionGrid';
import { RunSelector } from './RunSelector';
import { MetricSelector } from './MetricSelector';
import { calculateMedian, calculateP99 } from '@/lib/latency-harness/chart-transforms';
import type { MetricType, ChartTabId } from '@/types/latency-charts';

type TabConfig = {
  id: ChartTabId;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
};

const tabs: TabConfig[] = [
  { id: 'trends', label: 'Trends', icon: TrendingUp },
  { id: 'distribution', label: 'Distribution', icon: BarChart3 },
  { id: 'comparison', label: 'Comparison', icon: Grid3X3 },
  { id: 'network', label: 'Network', icon: Globe },
];

/**
 * Main latency analytics dashboard.
 */
export function LatencyDashboard() {
  // Data fetching
  const { runs, loading, error, refetch, runsWithResults } = useLatencyData({
    autoRefresh: true,
    refreshInterval: 30000,
  });

  // UI state
  const [selectedRuns, setSelectedRuns] = useState<string[]>([]);
  const [selectedMetric, setSelectedMetric] = useState<MetricType>('e2e');
  const [activeTab, setActiveTab] = useState<ChartTabId>('trends');

  // Get runs for visualization (selected or all with results)
  const visualizationRuns = useMemo(() => {
    if (selectedRuns.length > 0) {
      return runsWithResults.filter((r) => selectedRuns.includes(r.id));
    }
    // Default to most recent runs with results
    return runsWithResults.slice(0, 10);
  }, [selectedRuns, runsWithResults]);

  // Aggregate results from selected runs
  const { results, count, uniqueConfigs, uniqueProviders } =
    useAggregatedResults(visualizationRuns);

  // Summary statistics
  const summaryStats = useMemo(() => {
    if (results.length === 0) {
      return { median: 0, p99: 0, count: 0, configCount: 0 };
    }
    const e2eValues = results.map((r) => r.e2eLatencyMs).filter((v) => v !== null);
    return {
      median: calculateMedian(e2eValues),
      p99: calculateP99(e2eValues),
      count: e2eValues.length,
      configCount: uniqueConfigs.length,
    };
  }, [results, uniqueConfigs]);

  if (error) {
    return (
      <div className="p-6 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400">
        <p className="font-medium">Error loading data</p>
        <p className="text-sm mt-1">{error}</p>
        <button
          onClick={refetch}
          className="mt-3 px-4 py-2 text-sm font-medium bg-red-500/20 hover:bg-red-500/30 rounded-lg transition-all"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold text-slate-100">Latency Analytics</h2>
          <p className="text-sm text-slate-400">
            {runsWithResults.length} completed runs with {count} total measurements
          </p>
        </div>
        <button
          onClick={refetch}
          disabled={loading}
          className="flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
      </div>

      {/* Summary Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
          <div className="flex items-center gap-2 mb-2">
            <Activity className="w-4 h-4 text-indigo-400" />
            <span className="text-sm text-slate-400">Median E2E</span>
          </div>
          <div
            className={`text-2xl font-bold ${
              summaryStats.median <= 500 ? 'text-emerald-400' : 'text-amber-400'
            }`}
          >
            {summaryStats.median > 0 ? `${Math.round(summaryStats.median)}ms` : '-'}
          </div>
        </div>
        <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
          <div className="flex items-center gap-2 mb-2">
            <TrendingUp className="w-4 h-4 text-amber-400" />
            <span className="text-sm text-slate-400">P99 E2E</span>
          </div>
          <div
            className={`text-2xl font-bold ${
              summaryStats.p99 <= 1000 ? 'text-emerald-400' : 'text-red-400'
            }`}
          >
            {summaryStats.p99 > 0 ? `${Math.round(summaryStats.p99)}ms` : '-'}
          </div>
        </div>
        <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
          <div className="flex items-center gap-2 mb-2">
            <BarChart3 className="w-4 h-4 text-emerald-400" />
            <span className="text-sm text-slate-400">Measurements</span>
          </div>
          <div className="text-2xl font-bold text-slate-100">{summaryStats.count}</div>
        </div>
        <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
          <div className="flex items-center gap-2 mb-2">
            <Grid3X3 className="w-4 h-4 text-violet-400" />
            <span className="text-sm text-slate-400">Configurations</span>
          </div>
          <div className="text-2xl font-bold text-slate-100">{summaryStats.configCount}</div>
        </div>
      </div>

      {/* Controls */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <RunSelector
          runs={runs}
          selectedRuns={selectedRuns}
          onSelectionChange={setSelectedRuns}
          multiSelect={true}
          maxSelections={5}
          label="Compare Runs"
        />
        <MetricSelector selectedMetric={selectedMetric} onMetricChange={setSelectedMetric} />
      </div>

      {/* Chart Tabs */}
      <Card>
        <CardHeader>
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <CardTitle>
              <Activity className="w-5 h-5" />
              Visualizations
            </CardTitle>
            <div className="flex gap-1 bg-slate-800/50 p-1 rounded-lg">
              {tabs.map((tab) => {
                const Icon = tab.icon;
                return (
                  <button
                    key={tab.id}
                    onClick={() => setActiveTab(tab.id)}
                    className={`flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-md transition-all ${
                      activeTab === tab.id
                        ? 'bg-indigo-500 text-white'
                        : 'text-slate-400 hover:text-slate-200 hover:bg-slate-700/50'
                    }`}
                  >
                    <Icon className="w-4 h-4" />
                    <span className="hidden sm:inline">{tab.label}</span>
                  </button>
                );
              })}
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {loading && results.length === 0 ? (
            <div className="flex items-center justify-center h-96">
              <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
            </div>
          ) : results.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-96 text-slate-500">
              <BarChart3 className="w-12 h-12 mb-3 opacity-50" />
              <p>No data available</p>
              <p className="text-sm mt-1">Run some latency tests to see analytics</p>
            </div>
          ) : (
            <>
              {activeTab === 'trends' && (
                <TrendChart
                  runs={visualizationRuns}
                  metric={selectedMetric}
                  height={450}
                  loading={loading}
                />
              )}
              {activeTab === 'distribution' && (
                <DistributionChart
                  results={results}
                  metric={selectedMetric}
                  height={450}
                  loading={loading}
                />
              )}
              {activeTab === 'comparison' && (
                <ProviderHeatmap
                  results={results}
                  metric={selectedMetric}
                  height={450}
                  loading={loading}
                />
              )}
              {activeTab === 'network' && (
                <NetworkProjectionGrid results={results} loading={loading} />
              )}
            </>
          )}
        </CardContent>
      </Card>

      {/* Provider Summary */}
      {uniqueProviders.llm.length > 0 && (
        <div className="p-4 rounded-xl bg-slate-800/30 border border-slate-700/30">
          <h3 className="text-sm font-medium text-slate-400 mb-3">Providers in Dataset</h3>
          <div className="flex flex-wrap gap-2">
            {uniqueProviders.llm.map((p) => (
              <span
                key={`llm-${p}`}
                className="px-2 py-1 text-xs font-medium bg-indigo-500/20 text-indigo-400 rounded"
              >
                LLM: {p}
              </span>
            ))}
            {uniqueProviders.tts.map((p) => (
              <span
                key={`tts-${p}`}
                className="px-2 py-1 text-xs font-medium bg-emerald-500/20 text-emerald-400 rounded"
              >
                TTS: {p}
              </span>
            ))}
            {uniqueProviders.stt.map((p) => (
              <span
                key={`stt-${p}`}
                className="px-2 py-1 text-xs font-medium bg-amber-500/20 text-amber-400 rounded"
              >
                STT: {p}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
