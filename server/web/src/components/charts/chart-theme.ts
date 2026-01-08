/**
 * ECharts Theme Configuration
 * ===========================
 *
 * Dark theme matching the slate-950 color palette used throughout
 * the UnaMentis web management interface.
 */

import type { EChartsOption } from 'echarts';

/**
 * Dark theme configuration for ECharts.
 * Matches the existing Tailwind slate-950 dark theme.
 */
export const latencyDarkTheme = {
  // Background is transparent to let Card handle it
  backgroundColor: 'transparent',

  // Text styling
  textStyle: {
    color: '#e2e8f0', // slate-200
    fontFamily:
      'ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
  },

  // Title styling
  title: {
    textStyle: {
      color: '#f1f5f9', // slate-100
      fontSize: 16,
      fontWeight: 600,
    },
    subtextStyle: {
      color: '#94a3b8', // slate-400
      fontSize: 12,
    },
  },

  // Legend styling
  legend: {
    textStyle: {
      color: '#94a3b8', // slate-400
    },
  },

  // Tooltip styling
  tooltip: {
    backgroundColor: '#1e293b', // slate-800
    borderColor: '#334155', // slate-700
    borderWidth: 1,
    textStyle: {
      color: '#e2e8f0', // slate-200
    },
    extraCssText: 'box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1);',
  },

  // Axis styling
  categoryAxis: {
    axisLine: {
      lineStyle: {
        color: '#475569', // slate-600
      },
    },
    axisTick: {
      lineStyle: {
        color: '#475569',
      },
    },
    axisLabel: {
      color: '#94a3b8', // slate-400
    },
    splitLine: {
      lineStyle: {
        color: '#334155', // slate-700
      },
    },
  },

  valueAxis: {
    axisLine: {
      lineStyle: {
        color: '#475569',
      },
    },
    axisTick: {
      lineStyle: {
        color: '#475569',
      },
    },
    axisLabel: {
      color: '#94a3b8',
    },
    splitLine: {
      lineStyle: {
        color: '#334155',
        type: 'dashed',
      },
    },
  },

  // Grid styling
  grid: {
    borderColor: '#334155',
  },

  // Data zoom styling
  dataZoom: {
    backgroundColor: '#1e293b',
    dataBackgroundColor: '#334155',
    fillerColor: 'rgba(99, 102, 241, 0.2)', // indigo with opacity
    handleColor: '#6366f1',
    textStyle: {
      color: '#94a3b8',
    },
  },

  // Visual map (for heatmaps)
  visualMap: {
    textStyle: {
      color: '#94a3b8',
    },
  },

  // Color palette matching project conventions
  color: [
    '#6366f1', // Indigo (primary)
    '#8b5cf6', // Violet
    '#10b981', // Emerald
    '#f59e0b', // Amber
    '#ef4444', // Red
    '#3b82f6', // Blue
    '#ec4899', // Pink
    '#14b8a6', // Teal
    '#f97316', // Orange
    '#a855f7', // Purple
  ],
};

/**
 * Common chart options that match project styling.
 * Merge these with specific chart options.
 */
export const baseChartOptions: Partial<EChartsOption> = {
  animation: true,
  animationDuration: 300,
  animationEasing: 'cubicOut',
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    top: '15%',
    containLabel: true,
  },
};

/**
 * Color utilities for latency visualization.
 */
export const latencyColors = {
  // Status colors
  success: '#10b981', // emerald-500
  warning: '#f59e0b', // amber-500
  error: '#ef4444', // red-500

  // Latency target colors
  belowTarget: '#10b981', // Green - good
  nearTarget: '#f59e0b', // Amber - warning
  aboveTarget: '#ef4444', // Red - bad

  // Chart series colors
  median: '#6366f1', // Indigo
  p99: '#f59e0b', // Amber
  target: '#ef4444', // Red (dotted line)
  area: 'rgba(99, 102, 241, 0.1)', // Indigo with low opacity

  // Heatmap gradient
  heatmapMin: '#10b981', // Emerald (low latency = good)
  heatmapMid: '#fbbf24', // Amber (medium)
  heatmapMax: '#ef4444', // Red (high latency = bad)
};

/**
 * Get color for a latency value based on target thresholds.
 */
export function getLatencyColor(ms: number, target = 500): string {
  if (ms <= target) return latencyColors.belowTarget;
  if (ms <= target * 1.5) return latencyColors.nearTarget;
  return latencyColors.aboveTarget;
}

/**
 * Network profile colors for consistent visualization.
 */
export const networkProfileColors: Record<string, string> = {
  localhost: '#6366f1', // Indigo
  wifi: '#10b981', // Emerald
  cellular_us: '#f59e0b', // Amber
  cellular_eu: '#8b5cf6', // Violet
  intercontinental: '#ef4444', // Red
};
