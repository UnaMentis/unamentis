/**
 * Network Projection Grid Component
 * ==================================
 *
 * Grid of cards showing projected latency across different network conditions.
 * Visualizes how latency changes from localhost to various network profiles.
 */

'use client';

import { useMemo } from 'react';
import { Wifi, Globe, Radio, Server, Plane } from 'lucide-react';
import { transformToNetworkProjections, formatMs } from '@/lib/latency-harness/chart-transforms';
import type { TestResult, NetworkProfile } from '@/types/latency-charts';
import { NetworkProfileLabels } from '@/types/latency-charts';

interface NetworkProjectionGridProps {
  /** Test results to analyze */
  results: TestResult[];
  /** Show loading state */
  loading?: boolean;
}

/** Icons for each network profile */
const NetworkIcons: Record<NetworkProfile, React.ComponentType<{ className?: string }>> = {
  localhost: Server,
  wifi: Wifi,
  cellular_us: Radio,
  cellular_eu: Globe,
  intercontinental: Plane,
};

/** Colors for each network profile */
const NetworkColors: Record<NetworkProfile, string> = {
  localhost: 'text-indigo-400 bg-indigo-500/10 border-indigo-500/30',
  wifi: 'text-emerald-400 bg-emerald-500/10 border-emerald-500/30',
  cellular_us: 'text-amber-400 bg-amber-500/10 border-amber-500/30',
  cellular_eu: 'text-violet-400 bg-violet-500/10 border-violet-500/30',
  intercontinental: 'text-red-400 bg-red-500/10 border-red-500/30',
};

/**
 * Grid showing latency projections across network conditions.
 */
export function NetworkProjectionGrid({ results, loading = false }: NetworkProjectionGridProps) {
  const projections = useMemo(() => transformToNetworkProjections(results), [results]);

  if (loading) {
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
        {[1, 2, 3, 4, 5].map((i) => (
          <div
            key={i}
            className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50 animate-pulse"
          >
            <div className="h-8 w-8 bg-slate-700 rounded-lg mb-3" />
            <div className="h-4 w-24 bg-slate-700 rounded mb-2" />
            <div className="h-8 w-16 bg-slate-700 rounded mb-2" />
            <div className="h-3 w-20 bg-slate-700 rounded" />
          </div>
        ))}
      </div>
    );
  }

  if (results.length === 0) {
    return (
      <div className="text-center py-12 text-slate-500">
        <Globe className="w-12 h-12 mx-auto mb-3 opacity-50" />
        <p>No data available for network projections</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-semibold text-slate-100">Network Condition Projections</h3>
        <span className="text-sm text-slate-400">{results.length} measurements analyzed</span>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
        {projections.map((projection) => {
          const Icon = NetworkIcons[projection.profile];
          const colorClass = NetworkColors[projection.profile];

          return (
            <div
              key={projection.profile}
              className={`p-4 rounded-xl border transition-all hover:scale-[1.02] ${colorClass}`}
            >
              {/* Header */}
              <div className="flex items-center gap-2 mb-3">
                <Icon className="w-5 h-5" />
                <span className="font-medium text-slate-100">
                  {NetworkProfileLabels[projection.profile]}
                </span>
              </div>

              {/* Metrics */}
              <div className="space-y-2">
                {/* Median */}
                <div>
                  <div className="text-xs text-slate-400 mb-0.5">Median E2E</div>
                  <div
                    className={`text-2xl font-bold ${
                      projection.meetsTarget500 ? 'text-emerald-400' : 'text-red-400'
                    }`}
                  >
                    {formatMs(projection.projectedMedian)}
                  </div>
                </div>

                {/* P99 */}
                <div>
                  <div className="text-xs text-slate-400 mb-0.5">P99 E2E</div>
                  <div
                    className={`text-lg font-semibold ${
                      projection.meetsTarget1000 ? 'text-emerald-400' : 'text-amber-400'
                    }`}
                  >
                    {formatMs(projection.projectedP99)}
                  </div>
                </div>

                {/* Added Latency */}
                <div className="pt-2 border-t border-slate-700/50">
                  <div className="text-xs text-slate-500">
                    +{projection.addedLatency}ms network latency
                  </div>
                </div>

                {/* Target Status */}
                <div className="flex items-center gap-2">
                  {projection.meetsTarget500 ? (
                    <span className="px-2 py-0.5 text-xs font-medium bg-emerald-500/20 text-emerald-400 rounded-full">
                      Meets 500ms
                    </span>
                  ) : (
                    <span className="px-2 py-0.5 text-xs font-medium bg-red-500/20 text-red-400 rounded-full">
                      Exceeds 500ms
                    </span>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Summary */}
      <div className="p-4 rounded-xl bg-slate-800/30 border border-slate-700/30">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-center">
          <div>
            <div className="text-2xl font-bold text-emerald-400">
              {projections.filter((p) => p.meetsTarget500).length}
            </div>
            <div className="text-xs text-slate-400">Profiles meeting 500ms median</div>
          </div>
          <div>
            <div className="text-2xl font-bold text-emerald-400">
              {projections.filter((p) => p.meetsTarget1000).length}
            </div>
            <div className="text-xs text-slate-400">Profiles meeting 1000ms P99</div>
          </div>
          <div>
            <div className="text-2xl font-bold text-indigo-400">
              {formatMs(projections[0]?.projectedMedian || 0)}
            </div>
            <div className="text-xs text-slate-400">Localhost baseline</div>
          </div>
          <div>
            <div className="text-2xl font-bold text-red-400">
              {formatMs(projections[projections.length - 1]?.projectedMedian || 0)}
            </div>
            <div className="text-xs text-slate-400">Worst case (intercontinental)</div>
          </div>
        </div>
      </div>
    </div>
  );
}
