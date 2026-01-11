/**
 * Distribution Chart Component
 * ============================
 *
 * Histogram and box plot visualization for latency distribution analysis.
 * Supports toggling between histogram and box plot views.
 */

'use client';

import { useMemo, useState } from 'react';
import type { EChartsOption } from 'echarts';
import { EChartsWrapper } from '@/components/charts/EChartsWrapper';
import { latencyColors } from '@/components/charts/chart-theme';
import {
  transformToHistogram,
  transformToBoxPlot,
  formatMs,
} from '@/lib/latency-harness/chart-transforms';
import type { TestResult, MetricType } from '@/types/latency-charts';
import { MetricLabels } from '@/types/latency-charts';

interface DistributionChartProps {
  /** Test results to visualize */
  results: TestResult[];
  /** Metric type to display */
  metric?: MetricType;
  /** Chart height */
  height?: number;
  /** Show loading state */
  loading?: boolean;
}

type ViewMode = 'histogram' | 'boxplot';

/**
 * Distribution chart with histogram and box plot views.
 */
export function DistributionChart({
  results,
  metric = 'e2e',
  height = 400,
  loading = false,
}: DistributionChartProps) {
  const [viewMode, setViewMode] = useState<ViewMode>('histogram');

  const histogramOption = useMemo((): EChartsOption => {
    const bins = transformToHistogram(results, metric, 20);

    if (bins.length === 0) {
      return {
        title: {
          text: `${MetricLabels[metric]} Distribution`,
          subtext: 'No data available',
        },
        xAxis: { type: 'value' },
        yAxis: { type: 'value' },
        series: [],
      };
    }

    return {
      title: {
        text: `${MetricLabels[metric]} Distribution`,
        subtext: `${results.length} measurements`,
      },
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: 'shadow' },
        formatter: (params: unknown) => {
          const items = params as Array<{
            data: { range: string; y: number };
          }>;
          if (!items || items.length === 0) return '';
          const item = items[0];
          return `${item.data.range}<br/>Count: <b>${item.data.y}</b>`;
        },
      },
      grid: {
        top: 80,
        right: 40,
        bottom: 60,
        left: 60,
      },
      xAxis: {
        type: 'value',
        name: 'Latency (ms)',
        nameLocation: 'middle',
        nameGap: 35,
        axisLabel: {
          formatter: (value: number) => formatMs(value),
        },
      },
      yAxis: {
        type: 'value',
        name: 'Frequency',
        nameLocation: 'middle',
        nameGap: 45,
      },
      series: [
        {
          type: 'bar',
          data: bins.map((b) => ({
            value: [b.x, b.y],
            range: b.range,
            y: b.y,
          })),
          barWidth: '90%',
          itemStyle: {
            color: {
              type: 'linear',
              x: 0,
              y: 0,
              x2: 0,
              y2: 1,
              colorStops: [
                { offset: 0, color: latencyColors.median },
                { offset: 1, color: 'rgba(99, 102, 241, 0.6)' },
              ],
            },
            borderRadius: [4, 4, 0, 0],
          },
          emphasis: {
            itemStyle: {
              color: '#818cf8',
            },
          },
        },
      ],
      // Mark the 500ms target
      markLine: {
        silent: true,
        data: [
          {
            xAxis: 500,
            lineStyle: { color: latencyColors.target, type: 'dashed' },
            label: { formatter: '500ms', position: 'end' },
          },
        ],
      },
    };
  }, [results, metric]);

  const boxPlotOption = useMemo((): EChartsOption => {
    const boxData = transformToBoxPlot(results, metric, 'config');

    if (boxData.length === 0) {
      return {
        title: {
          text: `${MetricLabels[metric]} by Configuration`,
          subtext: 'No data available',
        },
        xAxis: { type: 'category' },
        yAxis: { type: 'value' },
        series: [],
      };
    }

    // Prepare data for ECharts boxplot format: [min, Q1, median, Q3, max]
    const boxplotData = boxData.map((d) => [d.min, d.q1, d.median, d.q3, d.max]);
    const categories = boxData.map((d) => d.name);

    return {
      title: {
        text: `${MetricLabels[metric]} by Configuration`,
        subtext: `${boxData.length} configurations`,
      },
      tooltip: {
        trigger: 'item',
        formatter: (params: unknown) => {
          const p = params as {
            name: string;
            data: number[];
          };
          if (!p || !p.data) return '';
          const [min, q1, median, q3, max] = p.data;
          return `
            <b>${p.name}</b><br/>
            Max: ${formatMs(max)}<br/>
            Q3: ${formatMs(q3)}<br/>
            Median: ${formatMs(median)}<br/>
            Q1: ${formatMs(q1)}<br/>
            Min: ${formatMs(min)}
          `;
        },
      },
      grid: {
        top: 80,
        right: 40,
        bottom: 100,
        left: 60,
      },
      xAxis: {
        type: 'category',
        data: categories,
        axisLabel: {
          rotate: 45,
          interval: 0,
          fontSize: 10,
        },
      },
      yAxis: {
        type: 'value',
        name: 'Latency (ms)',
        nameLocation: 'middle',
        nameGap: 45,
        axisLabel: {
          formatter: (value: number) => formatMs(value),
        },
      },
      series: [
        {
          type: 'boxplot',
          data: boxplotData,
          itemStyle: {
            color: 'rgba(99, 102, 241, 0.3)',
            borderColor: latencyColors.median,
            borderWidth: 2,
          },
          emphasis: {
            itemStyle: {
              borderColor: '#818cf8',
              borderWidth: 3,
            },
          },
        },
      ],
    };
  }, [results, metric]);

  return (
    <div className="space-y-4">
      {/* View Mode Toggle */}
      <div className="flex gap-2">
        <button
          onClick={() => setViewMode('histogram')}
          className={`px-3 py-1.5 text-sm font-medium rounded-lg transition-all ${
            viewMode === 'histogram'
              ? 'bg-indigo-500 text-white'
              : 'bg-slate-800 text-slate-300 hover:bg-slate-700'
          }`}
        >
          Histogram
        </button>
        <button
          onClick={() => setViewMode('boxplot')}
          className={`px-3 py-1.5 text-sm font-medium rounded-lg transition-all ${
            viewMode === 'boxplot'
              ? 'bg-indigo-500 text-white'
              : 'bg-slate-800 text-slate-300 hover:bg-slate-700'
          }`}
        >
          Box Plot
        </button>
      </div>

      {/* Chart */}
      <EChartsWrapper
        option={viewMode === 'histogram' ? histogramOption : boxPlotOption}
        height={height}
        loading={loading}
      />
    </div>
  );
}
