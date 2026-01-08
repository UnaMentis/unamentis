/**
 * Provider Heatmap Component
 * ==========================
 *
 * Heatmap visualization comparing provider combinations.
 * Shows median latency for each LLM x TTS provider combination.
 */

'use client';

import { useMemo } from 'react';
import type { EChartsOption } from 'echarts';
import { EChartsWrapper } from '@/components/charts/EChartsWrapper';
import { latencyColors } from '@/components/charts/chart-theme';
import { transformToHeatmap, formatMs } from '@/lib/latency-harness/chart-transforms';
import type { TestResult, MetricType } from '@/types/latency-charts';
import { MetricLabels } from '@/types/latency-charts';

interface ProviderHeatmapProps {
  /** Test results to visualize */
  results: TestResult[];
  /** Metric type to display */
  metric?: MetricType;
  /** Chart height */
  height?: number;
  /** Show loading state */
  loading?: boolean;
}

/**
 * Heatmap showing provider combination latencies.
 */
export function ProviderHeatmap({
  results,
  metric = 'e2e',
  height = 400,
  loading = false,
}: ProviderHeatmapProps) {
  const option = useMemo((): EChartsOption => {
    const heatmapData = transformToHeatmap(results, metric);

    if (heatmapData.data.length === 0) {
      return {
        title: {
          text: `Provider Combination ${MetricLabels[metric]} Latency`,
          subtext: 'No data available',
        },
        xAxis: { type: 'category' },
        yAxis: { type: 'category' },
        series: [],
      };
    }

    // Calculate min/max for color scale
    const values = heatmapData.data.map((d) => d[2]);
    const minValue = Math.min(...values);
    const maxValue = Math.max(...values);

    return {
      title: {
        text: `Provider Combination ${MetricLabels[metric]} Latency`,
        subtext: `${heatmapData.xAxis.length} LLM x ${heatmapData.yAxis.length} TTS combinations`,
      },
      tooltip: {
        position: 'top',
        formatter: (params: unknown) => {
          const p = params as {
            data: [number, number, number];
            name: string;
          };
          if (!p || !p.data) return '';
          const [x, y, value] = p.data;
          const llm = heatmapData.xAxis[x];
          const tts = heatmapData.yAxis[y];
          return `
            <b>${llm}</b> + <b>${tts}</b><br/>
            Median: <b>${formatMs(value)}</b>
          `;
        },
      },
      grid: {
        top: 80,
        right: 120,
        bottom: 100,
        left: 100,
      },
      xAxis: {
        type: 'category',
        data: heatmapData.xAxis,
        name: 'LLM Provider',
        nameLocation: 'middle',
        nameGap: 70,
        axisLabel: {
          rotate: 45,
          interval: 0,
          fontSize: 11,
        },
        splitArea: {
          show: true,
        },
      },
      yAxis: {
        type: 'category',
        data: heatmapData.yAxis,
        name: 'TTS Provider',
        nameLocation: 'middle',
        nameGap: 80,
        axisLabel: {
          fontSize: 11,
        },
        splitArea: {
          show: true,
        },
      },
      visualMap: {
        min: minValue,
        max: maxValue,
        calculable: true,
        orient: 'vertical',
        right: 10,
        top: 'center',
        itemHeight: 200,
        inRange: {
          color: [latencyColors.heatmapMin, latencyColors.heatmapMid, latencyColors.heatmapMax],
        },
        text: ['High', 'Low'],
        textStyle: {
          color: '#94a3b8',
        },
        formatter: ((value: unknown) => formatMs(Number(value))) as unknown as string,
      },
      series: [
        {
          type: 'heatmap',
          data: heatmapData.data,
          label: {
            show: true,
            formatter: (params: unknown) => {
              const p = params as { data: [number, number, number] };
              return formatMs(p.data[2]);
            },
            fontSize: 10,
            color: '#fff',
          },
          emphasis: {
            itemStyle: {
              shadowBlur: 10,
              shadowColor: 'rgba(0, 0, 0, 0.5)',
            },
          },
          itemStyle: {
            borderColor: '#1e293b',
            borderWidth: 2,
            borderRadius: 4,
          },
        },
      ],
    };
  }, [results, metric]);

  return <EChartsWrapper option={option} height={height} loading={loading} />;
}
