/**
 * Trend Chart Component
 * =====================
 *
 * Time-series line chart showing latency trends across test runs.
 * Displays median and P99 latency over time with a 500ms target line.
 */

'use client';

import { useMemo } from 'react';
import type { EChartsOption } from 'echarts';
import { EChartsWrapper } from '@/components/charts/EChartsWrapper';
import { latencyColors } from '@/components/charts/chart-theme';
import { transformToTimeSeries, formatMs } from '@/lib/latency-harness/chart-transforms';
import type { TestRun, MetricType } from '@/types/latency-charts';
import { MetricLabels } from '@/types/latency-charts';

interface TrendChartProps {
  /** Test runs to visualize */
  runs: TestRun[];
  /** Metric type to display */
  metric?: MetricType;
  /** Chart height */
  height?: number;
  /** Show loading state */
  loading?: boolean;
}

/**
 * Time-series trend chart for latency metrics.
 */
export function TrendChart({
  runs,
  metric = 'e2e',
  height = 400,
  loading = false,
}: TrendChartProps) {
  const option = useMemo((): EChartsOption => {
    const data = transformToTimeSeries(runs, metric);

    if (data.length === 0) {
      return {
        title: {
          text: `${MetricLabels[metric]} Latency Trends`,
          subtext: 'No data available',
        },
        xAxis: { type: 'time' },
        yAxis: { type: 'value' },
        series: [],
      };
    }

    // Prepare series data
    const medianData = data.map((d) => [d.timestamp, d.median]);
    const p99Data = data.map((d) => [d.timestamp, d.p99]);

    // Calculate y-axis max with some padding
    const maxValue = Math.max(...data.map((d) => d.p99));
    const yMax = Math.ceil(maxValue / 100) * 100 + 100;

    return {
      title: {
        text: `${MetricLabels[metric]} Latency Trends`,
        subtext: `${data.length} completed runs`,
      },
      tooltip: {
        trigger: 'axis',
        formatter: (params: unknown) => {
          const items = params as Array<{
            seriesName: string;
            value: [number, number];
            color: string;
          }>;
          if (!items || items.length === 0) return '';

          const date = new Date(items[0].value[0]).toLocaleString();
          const lines = items.map(
            (item) =>
              `<span style="color:${item.color}">●</span> ${item.seriesName}: <b>${formatMs(item.value[1])}</b>`
          );

          return `${date}<br/>${lines.join('<br/>')}`;
        },
      },
      legend: {
        data: ['Median', 'P99', '500ms Target'],
        top: 30,
      },
      grid: {
        top: 80,
        right: 40,
        bottom: 60,
        left: 60,
      },
      xAxis: {
        type: 'time',
        name: 'Time',
        nameLocation: 'middle',
        nameGap: 35,
        axisLabel: {
          formatter: (value: number) => {
            const date = new Date(value);
            return `${date.getMonth() + 1}/${date.getDate()}\n${date.getHours()}:${String(date.getMinutes()).padStart(2, '0')}`;
          },
        },
      },
      yAxis: {
        type: 'value',
        name: 'Latency (ms)',
        nameLocation: 'middle',
        nameGap: 45,
        min: 0,
        max: yMax,
        axisLabel: {
          formatter: (value: number) => formatMs(value),
        },
      },
      series: [
        {
          name: 'Median',
          type: 'line',
          smooth: true,
          data: medianData,
          symbol: 'circle',
          symbolSize: 8,
          lineStyle: {
            color: latencyColors.median,
            width: 3,
          },
          itemStyle: {
            color: latencyColors.median,
          },
          areaStyle: {
            color: {
              type: 'linear',
              x: 0,
              y: 0,
              x2: 0,
              y2: 1,
              colorStops: [
                { offset: 0, color: 'rgba(99, 102, 241, 0.3)' },
                { offset: 1, color: 'rgba(99, 102, 241, 0.05)' },
              ],
            },
          },
        },
        {
          name: 'P99',
          type: 'line',
          smooth: true,
          data: p99Data,
          symbol: 'diamond',
          symbolSize: 6,
          lineStyle: {
            color: latencyColors.p99,
            width: 2,
            type: 'dashed',
          },
          itemStyle: {
            color: latencyColors.p99,
          },
        },
        {
          name: '500ms Target',
          type: 'line',
          data:
            data.length > 0
              ? [
                  [data[0].timestamp, 500],
                  [data[data.length - 1].timestamp, 500],
                ]
              : [],
          lineStyle: {
            color: latencyColors.target,
            width: 2,
            type: 'dotted',
          },
          symbol: 'none',
          markLine: {
            silent: true,
            symbol: 'none',
            lineStyle: {
              color: latencyColors.target,
              type: 'dotted',
            },
            data: [{ yAxis: 500, name: 'Target' }],
            label: {
              formatter: '500ms Target',
              position: 'end',
            },
          },
        },
      ],
      dataZoom: [
        {
          type: 'inside',
          start: 0,
          end: 100,
        },
        {
          type: 'slider',
          start: 0,
          end: 100,
          height: 20,
          bottom: 10,
        },
      ],
    };
  }, [runs, metric]);

  return <EChartsWrapper option={option} height={height} loading={loading} />;
}
