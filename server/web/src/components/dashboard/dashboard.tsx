/**
 * UnaMentis Unified Console
 *
 * This console provides:
 *
 * OPERATIONS SECTION:
 * - System health monitoring (CPU, memory, thermal, battery)
 * - Service status and management (Ollama, VibeVoice, Piper, etc.)
 * - Power/idle management profiles and thresholds
 * - Logs, metrics, and performance data
 * - Client connection monitoring
 *
 * CONTENT SECTION:
 * - Curriculum management (browse, edit, delete)
 * - Source browser for external curriculum import (MIT OCW, Stanford, etc.)
 * - Plugin management for importers
 * - Import job monitoring and management
 */
'use client';

import { useEffect, useCallback } from 'react';
import { useQueryState, parseAsStringLiteral } from 'nuqs';
import { Zap, CheckCircle, Users, FileText, AlertTriangle, AlertCircle } from 'lucide-react';
import { Header } from './header';
import { SectionNav, NavTabs, SectionId, TabId, OpsTabId, ContentTabId } from './nav-tabs';
import { StatCard } from '@/components/ui/stat-card';
import { LogsPanel, LogsPanelCompact } from './logs-panel';
import { ServersPanelCompact, ServersPanel } from './servers-panel';
import { ClientsPanelCompact, ClientsPanel } from './clients-panel';
import { MetricsPanel, LatencyOverview } from './metrics-panel';
import { ModelsPanel } from './models-panel';
import { HealthPanel } from './health-panel';
import { UsersPanel } from './users-panel';
// Content section components (to be created)
import { CurriculaPanel } from './curricula-panel';
import { SourceBrowserPanel } from './source-browser-panel';
import { PluginsPanel } from './plugins-panel';
import { ImportJobsPanel } from './import-jobs-panel';
import { LatencyHarnessPanel } from './latency-harness-panel';
import { FOVContextPanel } from './fov-context-panel';
import { ReprocessPanel } from './reprocess-panel';
import type { DashboardStats } from '@/types';
import { getStats } from '@/lib/api-client';
import { formatDuration } from '@/lib/utils';
import { useWebSocketStatus } from '@/lib/websocket-provider';
import { useState } from 'react';

// Define valid values for URL state
const SECTIONS = ['operations', 'content'] as const;
const OPS_TABS = [
  'dashboard',
  'health',
  'latency',
  'fov',
  'metrics',
  'logs',
  'clients',
  'servers',
  'models',
  'users',
] as const;
const CONTENT_TABS = ['curricula', 'sources', 'plugins', 'imports', 'reprocess'] as const;
const ALL_TABS = [...OPS_TABS, ...CONTENT_TABS] as const;

export function Dashboard() {
  // URL-synced state for section and tab using nuqs
  const [activeSection, setActiveSection] = useQueryState(
    'section',
    parseAsStringLiteral(SECTIONS).withDefault('operations')
  );
  const [activeTab, setActiveTab] = useQueryState(
    'tab',
    parseAsStringLiteral(ALL_TABS).withDefault('dashboard')
  );

  const [stats, setStats] = useState<DashboardStats | null>(null);
  const { connected } = useWebSocketStatus();

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

  // Handle section change and set appropriate default tab
  const handleSectionChange = useCallback(
    (section: SectionId) => {
      setActiveSection(section);
      // Set default tab for each section
      if (section === 'operations') {
        setActiveTab('dashboard');
      } else {
        setActiveTab('curricula');
      }
    },
    [setActiveSection, setActiveTab]
  );

  return (
    <div className="h-screen flex flex-col bg-slate-950 text-slate-100 overflow-hidden">
      {/* Background Pattern - fixed behind everything */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-1/2 -right-1/2 w-full h-full bg-gradient-to-bl from-orange-500/5 via-transparent to-transparent" />
        <div className="absolute -bottom-1/2 -left-1/2 w-full h-full bg-gradient-to-tr from-amber-500/5 via-transparent to-transparent" />
      </div>

      {/* Sticky Header - never scrolls */}
      <div className="relative z-20 flex-shrink-0">
        <Header
          stats={{
            logsCount: stats?.total_logs ?? 0,
            clientsCount: stats?.online_clients ?? 0,
          }}
          connected={connected}
        />
        <SectionNav activeSection={activeSection} onSectionChange={handleSectionChange} />
        <NavTabs activeSection={activeSection} activeTab={activeTab} onTabChange={setActiveTab} />
      </div>

      {/* Scrollable Content Area */}
      <main className="relative z-10 flex-1 overflow-y-auto">
        <div className="max-w-[1920px] mx-auto p-4 sm:p-6">
          {/* Dashboard Tab */}
          {activeTab === 'dashboard' && (
            <div className="space-y-4 sm:space-y-6 animate-in fade-in duration-300">
              {/* Stats Grid - responsive columns */}
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 sm:gap-4">
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

              {/* Dashboard Content - responsive grid */}
              <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 sm:gap-6">
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

          {/* System Health Tab */}
          {activeTab === 'health' && (
            <div className="animate-in fade-in duration-300">
              <HealthPanel />
            </div>
          )}

          {/* Latency Test Harness Tab */}
          {activeTab === 'latency' && (
            <div className="animate-in fade-in duration-300">
              <LatencyHarnessPanel />
            </div>
          )}

          {/* FOV Context Tab */}
          {activeTab === 'fov' && (
            <div className="animate-in fade-in duration-300">
              <FOVContextPanel />
            </div>
          )}

          {/* Users Tab */}
          {activeTab === 'users' && (
            <div className="animate-in fade-in duration-300">
              <UsersPanel />
            </div>
          )}

          {/* ============================================= */}
          {/* CONTENT SECTION TABS                         */}
          {/* ============================================= */}

          {/* Curricula Tab */}
          {activeTab === 'curricula' && (
            <div className="animate-in fade-in duration-300">
              <CurriculaPanel />
            </div>
          )}

          {/* Sources Tab */}
          {activeTab === 'sources' && (
            <div className="animate-in fade-in duration-300">
              <SourceBrowserPanel />
            </div>
          )}

          {/* Plugins Tab */}
          {activeTab === 'plugins' && (
            <div className="animate-in fade-in duration-300">
              <PluginsPanel />
            </div>
          )}

          {/* Import Jobs Tab */}
          {activeTab === 'imports' && (
            <div className="animate-in fade-in duration-300">
              <ImportJobsPanel />
            </div>
          )}

          {/* Reprocess Tab */}
          {activeTab === 'reprocess' && (
            <div className="animate-in fade-in duration-300">
              <ReprocessPanel />
            </div>
          )}
        </div>
      </main>
    </div>
  );
}
