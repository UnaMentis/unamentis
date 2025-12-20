'use client';

import { useState, useEffect } from 'react';
import { BarChart3, RefreshCw, TrendingUp, Clock, DollarSign, MessageCircle } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import type { MetricsSnapshot } from '@/types';
import { getMetrics } from '@/lib/api-client';
import { formatDuration, formatCost, formatTime, cn } from '@/lib/utils';

interface MetricCardProps {
  label: string;
  value: string;
  badge?: string;
  badgeColor?: string;
}

function MetricCard({ label, value, badge, badgeColor = 'bg-indigo-500/20 text-indigo-400' }: MetricCardProps) {
  return (
    <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
      <div className="flex items-center justify-between mb-2">
        <span className="text-sm text-slate-400">{label}</span>
        {badge && (
          <span className={cn('text-xs px-2 py-0.5 rounded-full font-medium', badgeColor)}>
            {badge}
          </span>
        )}
      </div>
      <div className="text-2xl font-bold text-slate-100">{value}</div>
    </div>
  );
}

export function MetricsPanel() {
  const [metrics, setMetrics] = useState<MetricsSnapshot[]>([]);
  const [aggregates, setAggregates] = useState({
    avg_e2e_latency: 0,
    avg_llm_ttft: 0,
    avg_stt_latency: 0,
    avg_tts_ttfb: 0,
    total_cost: 0,
    total_sessions: 0,
    total_turns: 0,
  });
  const [loading, setLoading] = useState(true);

  const fetchMetrics = async () => {
    try {
      const response = await getMetrics({ limit: 50 });
      setMetrics(response.metrics);
      setAggregates(response.aggregates);
    } catch (error) {
      console.error('Failed to fetch metrics:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchMetrics();
    const interval = setInterval(fetchMetrics, 15000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="space-y-6">
      {/* Metric Cards */}
      <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricCard
          label="Avg E2E Latency"
          value={`${aggregates.avg_e2e_latency} ms`}
          badge="median"
          badgeColor="bg-indigo-500/20 text-indigo-400"
        />
        <MetricCard
          label="LLM TTFT"
          value={`${aggregates.avg_llm_ttft} ms`}
          badge="median"
          badgeColor="bg-violet-500/20 text-violet-400"
        />
        <MetricCard
          label="STT Latency"
          value={`${aggregates.avg_stt_latency} ms`}
          badge="median"
          badgeColor="bg-emerald-500/20 text-emerald-400"
        />
        <MetricCard
          label="TTS TTFB"
          value={`${aggregates.avg_tts_ttfb} ms`}
          badge="median"
          badgeColor="bg-blue-500/20 text-blue-400"
        />
      </div>

      {/* Session History Table */}
      <Card>
        <CardHeader>
          <CardTitle>Session History</CardTitle>
          <button
            onClick={fetchMetrics}
            className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
          >
            <RefreshCw className="w-4 h-4" />
            Refresh
          </button>
        </CardHeader>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-slate-700/50">
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">Time</th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">Client</th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">Duration</th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">Turns</th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">E2E</th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">LLM</th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">Cost</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={7} className="text-center text-slate-500 py-8">Loading metrics...</td>
                </tr>
              ) : metrics.length === 0 ? (
                <tr>
                  <td colSpan={7} className="text-center text-slate-500 py-8">No session data yet</td>
                </tr>
              ) : (
                metrics.map((m) => (
                  <tr key={m.id} className="border-b border-slate-800/50 hover:bg-slate-800/30">
                    <td className="px-4 py-3 text-sm text-slate-300">{formatTime(m.timestamp)}</td>
                    <td className="px-4 py-3 text-sm text-slate-300">{m.client_name}</td>
                    <td className="px-4 py-3 text-sm text-slate-300">{formatDuration(m.session_duration)}</td>
                    <td className="px-4 py-3 text-sm text-slate-300">{m.turns_total}</td>
                    <td className="px-4 py-3 text-sm">
                      <span className={cn(
                        m.e2e_latency_median < 500 ? 'text-emerald-400' :
                        m.e2e_latency_median < 800 ? 'text-amber-400' : 'text-red-400'
                      )}>
                        {m.e2e_latency_median}ms
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm">
                      <span className={cn(
                        m.llm_ttft_median < 400 ? 'text-emerald-400' :
                        m.llm_ttft_median < 600 ? 'text-amber-400' : 'text-red-400'
                      )}>
                        {m.llm_ttft_median}ms
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-slate-300">{formatCost(m.total_cost)}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}

// Compact latency display for dashboard
export function LatencyOverview() {
  const [aggregates, setAggregates] = useState({
    avg_e2e_latency: 0,
    avg_llm_ttft: 0,
    avg_stt_latency: 0,
    avg_tts_ttfb: 0,
  });

  useEffect(() => {
    const fetchMetrics = async () => {
      try {
        const response = await getMetrics({ limit: 20 });
        setAggregates(response.aggregates);
      } catch (error) {
        console.error('Failed to fetch metrics:', error);
      }
    };

    fetchMetrics();
    const interval = setInterval(fetchMetrics, 15000);
    return () => clearInterval(interval);
  }, []);

  const latencyData = [
    { label: 'E2E', value: aggregates.avg_e2e_latency, target: 500, color: 'bg-indigo-500' },
    { label: 'LLM', value: aggregates.avg_llm_ttft, target: 500, color: 'bg-violet-500' },
    { label: 'STT', value: aggregates.avg_stt_latency, target: 300, color: 'bg-emerald-500' },
    { label: 'TTS', value: aggregates.avg_tts_ttfb, target: 200, color: 'bg-blue-500' },
  ];

  return (
    <Card className="lg:col-span-2">
      <CardHeader>
        <CardTitle>
          <TrendingUp className="w-5 h-5" />
          Latency Overview
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {latencyData.map((item) => (
            <div key={item.label} className="text-center">
              <div className="text-2xl font-bold text-slate-100">{item.value}ms</div>
              <div className="text-sm text-slate-400">{item.label}</div>
              <div className="mt-2 h-2 bg-slate-700 rounded-full overflow-hidden">
                <div
                  className={cn(
                    'h-full rounded-full transition-all duration-500',
                    item.color,
                    item.value > item.target ? 'opacity-70' : ''
                  )}
                  style={{ width: `${Math.min(100, (item.value / item.target) * 100)}%` }}
                />
              </div>
              <div className="text-xs text-slate-500 mt-1">target: {item.target}ms</div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
