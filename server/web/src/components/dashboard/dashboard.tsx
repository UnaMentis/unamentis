'use client';

import { useState, useEffect } from 'react';
import { Zap, CheckCircle, Users, FileText, AlertTriangle, AlertCircle } from 'lucide-react';
import { Header } from './header';
import { NavTabs, TabId } from './nav-tabs';
import { StatCard } from '@/components/ui/stat-card';
import { LogsPanel, LogsPanelCompact } from './logs-panel';
import { ServersPanelCompact, ServersPanel } from './servers-panel';
import { ClientsPanelCompact, ClientsPanel } from './clients-panel';
import { MetricsPanel, LatencyOverview } from './metrics-panel';
import { ModelsPanel } from './models-panel';
import type { DashboardStats } from '@/types';
import { getStats } from '@/lib/api-client';
import { formatDuration } from '@/lib/utils';

export function Dashboard() {
  const [activeTab, setActiveTab] = useState<TabId>('dashboard');
  const [stats, setStats] = useState<DashboardStats | null>(null);

  useEffect(() => {
    const fetchStats = async () => {
      try {
        const data = await getStats();
        setStats(data);
      } catch (error) {
        console.error('Failed to fetch stats:', error);
      }
    };

    fetchStats();
    const interval = setInterval(fetchStats, 10000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      {/* Background Pattern */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-1/2 -right-1/2 w-full h-full bg-gradient-to-bl from-indigo-500/5 via-transparent to-transparent" />
        <div className="absolute -bottom-1/2 -left-1/2 w-full h-full bg-gradient-to-tr from-violet-500/5 via-transparent to-transparent" />
      </div>

      <div className="relative z-10">
        <Header
          stats={{
            logsCount: stats?.total_logs ?? 0,
            clientsCount: stats?.online_clients ?? 0,
          }}
          connected={true}
        />
        <NavTabs activeTab={activeTab} onTabChange={setActiveTab} />

        <main className="max-w-[1920px] mx-auto p-6">
          {/* Dashboard Tab */}
          {activeTab === 'dashboard' && (
            <div className="space-y-6 animate-in fade-in duration-300">
              {/* Stats Grid */}
              <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4">
                <StatCard
                  icon={Zap}
                  value={stats ? formatDuration(stats.uptime_seconds) : '--'}
                  label="Uptime"
                  iconColor="text-indigo-400"
                  iconBgColor="bg-indigo-400/20"
                />
                <StatCard
                  icon={CheckCircle}
                  value={`${stats?.healthy_servers ?? 0}/${stats?.total_servers ?? 0}`}
                  label="Healthy Servers"
                  iconColor="text-emerald-400"
                  iconBgColor="bg-emerald-400/20"
                />
                <StatCard
                  icon={Users}
                  value={stats?.online_clients ?? 0}
                  label="Online Clients"
                  iconColor="text-blue-400"
                  iconBgColor="bg-blue-400/20"
                />
                <StatCard
                  icon={FileText}
                  value={stats?.total_logs ?? 0}
                  label="Total Logs"
                  iconColor="text-violet-400"
                  iconBgColor="bg-violet-400/20"
                />
                <StatCard
                  icon={AlertTriangle}
                  value={stats?.warnings_count ?? 0}
                  label="Warnings"
                  iconColor="text-amber-400"
                  iconBgColor="bg-amber-400/20"
                />
                <StatCard
                  icon={AlertCircle}
                  value={stats?.errors_count ?? 0}
                  label="Errors"
                  iconColor="text-red-400"
                  iconBgColor="bg-red-400/20"
                />
              </div>

              {/* Dashboard Content */}
              <div className="grid lg:grid-cols-3 gap-6">
                {/* Latency Chart */}
                <LatencyOverview />

                {/* Recent Activity */}
                <LogsPanelCompact />

                {/* Server Status */}
                <ServersPanelCompact />

                {/* Connected Clients */}
                <ClientsPanelCompact />
              </div>
            </div>
          )}

          {/* Metrics Tab */}
          {activeTab === 'metrics' && (
            <div className="animate-in fade-in duration-300">
              <MetricsPanel />
            </div>
          )}

          {/* Logs Tab */}
          {activeTab === 'logs' && (
            <div className="animate-in fade-in duration-300">
              <LogsPanel />
            </div>
          )}

          {/* Clients Tab */}
          {activeTab === 'clients' && (
            <div className="animate-in fade-in duration-300">
              <ClientsPanel />
            </div>
          )}

          {/* Servers Tab */}
          {activeTab === 'servers' && (
            <div className="animate-in fade-in duration-300">
              <ServersPanel />
            </div>
          )}

          {/* Models Tab */}
          {activeTab === 'models' && (
            <div className="animate-in fade-in duration-300">
              <ModelsPanel />
            </div>
          )}
        </main>
      </div>
    </div>
  );
}
