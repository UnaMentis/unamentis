/**
 * ECharts Wrapper Component
 * =========================
 *
 * Base wrapper component for Apache ECharts that applies the dark theme
 * and provides consistent configuration across all charts.
 */

'use client';

import { useRef, useEffect, memo } from 'react';
import ReactECharts from 'echarts-for-react';
import type { EChartsOption, ECharts } from 'echarts';
import { latencyDarkTheme, baseChartOptions } from './chart-theme';

interface EChartsWrapperProps {
  /** ECharts option configuration */
  option: EChartsOption;
  /** Chart height (CSS value or number in pixels) */
  height?: string | number;
  /** Show loading spinner */
  loading?: boolean;
  /** Event handlers */
  onEvents?: Record<string, (params: unknown) => void>;
  /** Additional class names */
  className?: string;
  /** Callback when chart is ready */
  onChartReady?: (instance: ECharts) => void;
  /** Merge base options with provided options */
  mergeBaseOptions?: boolean;
}

/**
 * Wrapper component for ECharts with dark theme and consistent styling.
 *
 * @example
 * ```tsx
 * <EChartsWrapper
 *   option={{
 *     xAxis: { type: 'category', data: ['A', 'B', 'C'] },
 *     yAxis: { type: 'value' },
 *     series: [{ type: 'line', data: [1, 2, 3] }]
 *   }}
 *   height={400}
 * />
 * ```
 */
function EChartsWrapperComponent({
  option,
  height = 400,
  loading = false,
  onEvents,
  className = '',
  onChartReady,
  mergeBaseOptions = true,
}: EChartsWrapperProps) {
  const chartRef = useRef<ReactECharts>(null);

  // Merge base options if enabled
  const mergedOption = mergeBaseOptions
    ? {
        ...baseChartOptions,
        ...option,
        grid: {
          ...baseChartOptions.grid,
          ...(option.grid as object),
        },
      }
    : option;

  // Handle chart ready callback
  useEffect(() => {
    if (onChartReady && chartRef.current) {
      const instance = chartRef.current.getEchartsInstance();
      onChartReady(instance);
    }
  }, [onChartReady]);

  // Handle window resize
  useEffect(() => {
    const handleResize = () => {
      if (chartRef.current) {
        chartRef.current.getEchartsInstance().resize();
      }
    };

    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  return (
    <ReactECharts
      ref={chartRef}
      option={mergedOption}
      theme={latencyDarkTheme}
      style={{ height, width: '100%' }}
      showLoading={loading}
      loadingOption={{
        text: 'Loading...',
        color: '#6366f1',
        textColor: '#94a3b8',
        maskColor: 'rgba(15, 23, 42, 0.8)',
      }}
      onEvents={onEvents}
      opts={{
        renderer: 'canvas',
        devicePixelRatio: typeof window !== 'undefined' ? window.devicePixelRatio : 1,
      }}
      className={className}
      notMerge={true}
      lazyUpdate={true}
    />
  );
}

// Memoize to prevent unnecessary re-renders
export const EChartsWrapper = memo(EChartsWrapperComponent);
