'use client';

import { useState, useEffect } from 'react';
import { Server, RefreshCw, Plus, Wifi, WifiOff, AlertTriangle } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatCard } from '@/components/ui/stat-card';
import type { ServerStatus } from '@/types';
import { getServers } from '@/lib/api-client';
import { cn } from '@/lib/utils';

export function ServersPanel() {
  const [servers, setServers] = useState<ServerStatus[]>([]);
  const [stats, setStats] = useState({ healthy: 0, degraded: 0, unhealthy: 0 });
  const [loading, setLoading] = useState(true);

  const fetchServers = async () => {
    try {
      const response = await getServers();
      setServers(response.servers);
      setStats({
        healthy: response.healthy,
        degraded: response.degraded,
        unhealthy: response.unhealthy,
      });
    } catch (error) {
      console.error('Failed to fetch servers:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchServers();
    const interval = setInterval(fetchServers, 30000);
    return () => clearInterval(interval);
  }, []);

  const statusStyles: Record<string, { icon: typeof Wifi; color: string; badge: 'success' | 'warning' | 'error' | 'default' }> = {
    healthy: { icon: Wifi, color: 'text-emerald-400', badge: 'success' },
    degraded: { icon: AlertTriangle, color: 'text-amber-400', badge: 'warning' },
    unhealthy: { icon: WifiOff, color: 'text-red-400', badge: 'error' },
    unknown: { icon: WifiOff, color: 'text-slate-400', badge: 'default' },
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold">Backend Servers</h2>
        <div className="flex gap-2">
          <button
            onClick={fetchServers}
            className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
          >
            <RefreshCw className="w-4 h-4" />
            Refresh
          </button>
          <button className="flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg bg-indigo-500 hover:bg-indigo-400 text-white transition-all">
            <Plus className="w-4 h-4" />
            Add Server
          </button>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4">
        <StatCard
          icon={Wifi}
          value={stats.healthy}
          label="Healthy"
          iconColor="text-emerald-400"
          iconBgColor="bg-emerald-400/20"
        />
        <StatCard
          icon={AlertTriangle}
          value={stats.degraded}
          label="Degraded"
          iconColor="text-amber-400"
          iconBgColor="bg-amber-400/20"
        />
        <StatCard
          icon={WifiOff}
          value={stats.unhealthy}
          label="Unhealthy"
          iconColor="text-red-400"
          iconBgColor="bg-red-400/20"
        />
      </div>

      {/* Server Grid */}
      <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
        {loading ? (
          Array.from({ length: 4 }).map((_, i) => (
            <Card key={i}>
              <CardContent className="h-32 flex items-center justify-center">
                <div className="animate-pulse text-slate-500">Loading...</div>
              </CardContent>
            </Card>
          ))
        ) : (
          servers.map((server) => {
            const style = statusStyles[server.status] || statusStyles.unknown;
            const Icon = style.icon;

            return (
              <Card key={server.id} className="hover:border-slate-600/50 transition-all">
                <CardContent className="pt-4">
                  <div className="flex items-start justify-between mb-3">
                    <div className="flex items-center gap-2">
                      <Server className={cn('w-5 h-5', style.color)} />
                      <h3 className="font-semibold text-slate-100">{server.name}</h3>
                    </div>
                    <Badge variant={style.badge}>{server.status}</Badge>
                  </div>

                  <div className="space-y-2 text-sm">
                    <div className="flex justify-between">
                      <span className="text-slate-400">Type</span>
                      <span className="text-slate-200 capitalize">{server.type}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">URL</span>
                      <span className="text-slate-200 font-mono text-xs">{server.url}</span>
                    </div>
                    {server.response_time_ms > 0 && (
                      <div className="flex justify-between">
                        <span className="text-slate-400">Latency</span>
                        <span className="text-slate-200">{server.response_time_ms}ms</span>
                      </div>
                    )}
                    {server.models.length > 0 && (
                      <div className="flex justify-between">
                        <span className="text-slate-400">Models</span>
                        <span className="text-slate-200">{server.models.length}</span>
                      </div>
                    )}
                    {server.error_message && (
                      <div className="mt-2 text-xs text-red-400 bg-red-500/10 rounded px-2 py-1">
                        {server.error_message}
                      </div>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })
        )}
      </div>
    </div>
  );
}

// Compact version for dashboard
export function ServersPanelCompact() {
  const [servers, setServers] = useState<ServerStatus[]>([]);

  useEffect(() => {
    const fetchServers = async () => {
      try {
        const response = await getServers();
        setServers(response.servers);
      } catch (error) {
        console.error('Failed to fetch servers:', error);
      }
    };

    fetchServers();
    const interval = setInterval(fetchServers, 30000);
    return () => clearInterval(interval);
  }, []);

  const statusStyles: Record<string, string> = {
    healthy: 'bg-emerald-400',
    degraded: 'bg-amber-400',
    unhealthy: 'bg-red-400',
    unknown: 'bg-slate-400',
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>
          <Server className="w-5 h-5" />
          Server Status
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {servers.map((server) => (
            <div
              key={server.id}
              className="flex items-center justify-between p-3 rounded-lg bg-slate-800/30"
            >
              <div className="flex items-center gap-3">
                <div className={cn('w-2 h-2 rounded-full', statusStyles[server.status] || statusStyles.unknown)} />
                <div>
                  <div className="font-medium text-slate-100">{server.name}</div>
                  <div className="text-xs text-slate-400">{server.type}</div>
                </div>
              </div>
              {server.response_time_ms > 0 && (
                <span className="text-sm text-slate-400">{server.response_time_ms}ms</span>
              )}
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
