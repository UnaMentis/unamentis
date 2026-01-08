/**
 * Metric Selector Component
 * =========================
 *
 * Button group for selecting which latency metric to visualize.
 */

'use client';

import type { MetricType } from '@/types/latency-charts';
import { MetricLabels } from '@/types/latency-charts';

interface MetricSelectorProps {
  /** Currently selected metric */
  selectedMetric: MetricType;
  /** Callback when selection changes */
  onMetricChange: (metric: MetricType) => void;
  /** Available metrics to show */
  availableMetrics?: MetricType[];
  /** Size variant */
  size?: 'sm' | 'md';
}

const defaultMetrics: MetricType[] = [
  'e2e',
  'stt',
  'llm_ttfb',
  'llm_completion',
  'tts_ttfb',
  'tts_completion',
];

/**
 * Metric selection button group.
 */
export function MetricSelector({
  selectedMetric,
  onMetricChange,
  availableMetrics = defaultMetrics,
  size = 'md',
}: MetricSelectorProps) {
  const sizeClasses = {
    sm: 'px-2 py-1 text-xs',
    md: 'px-3 py-1.5 text-sm',
  };

  return (
    <div className="space-y-2">
      <label className="block text-sm font-medium text-slate-400">Metric</label>
      <div className="flex flex-wrap gap-2">
        {availableMetrics.map((metric) => (
          <button
            key={metric}
            onClick={() => onMetricChange(metric)}
            className={`${sizeClasses[size]} font-medium rounded-lg transition-all ${
              selectedMetric === metric
                ? 'bg-indigo-500 text-white'
                : 'bg-slate-800 text-slate-300 hover:bg-slate-700 border border-slate-700'
            }`}
          >
            {MetricLabels[metric]}
          </button>
        ))}
      </div>
    </div>
  );
}
