'use client';

import { useState, useEffect, useCallback } from 'react';
import { Search, Pause, Play, Trash2, FileText } from 'lucide-react';
import { Card, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import type { LogEntry } from '@/types';
import { getLogs, clearLogs } from '@/lib/api-client';
import { formatTime, cn } from '@/lib/utils';

interface LogsPanelProps {
  maxHeight?: string;
}

const levelStyles: Record<string, { badge: 'default' | 'info' | 'warning' | 'error'; textClass: string }> = {
  DEBUG: { badge: 'default', textClass: 'text-slate-400' },
  INFO: { badge: 'info', textClass: 'text-blue-400' },
  WARNING: { badge: 'warning', textClass: 'text-amber-400' },
  ERROR: { badge: 'error', textClass: 'text-red-400' },
  CRITICAL: { badge: 'error', textClass: 'text-red-500' },
};

export function LogsPanel({ maxHeight = '600px' }: LogsPanelProps) {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [paused, setPaused] = useState(false);
  const [search, setSearch] = useState('');
  const [levelFilter, setLevelFilter] = useState<string>('');

  const fetchLogs = useCallback(async () => {
    if (paused) return;
    try {
      const response = await getLogs({
        limit: 200,
        search: search || undefined,
        level: levelFilter || undefined,
      });
      setLogs(response.logs);
      setTotal(response.total);
    } catch (error) {
      console.error('Failed to fetch logs:', error);
    } finally {
      setLoading(false);
    }
  }, [paused, search, levelFilter]);

  useEffect(() => {
    fetchLogs();
    const interval = setInterval(fetchLogs, 3000);
    return () => clearInterval(interval);
  }, [fetchLogs]);

  const handleClear = async () => {
    await clearLogs();
    setLogs([]);
    setTotal(0);
  };

  const levels = ['', 'DEBUG', 'INFO', 'WARNING', 'ERROR'];

  return (
    <Card>
      {/* Filters */}
      <CardHeader className="flex-col gap-4 sm:flex-row">
        <div className="flex items-center gap-4 flex-wrap">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
            <input
              type="text"
              placeholder="Search logs..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 placeholder-slate-500 focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 transition-all text-sm"
            />
          </div>
          <div className="flex gap-2">
            {levels.map((level) => (
              <button
                key={level || 'all'}
                onClick={() => setLevelFilter(level)}
                className={cn(
                  'px-3 py-1.5 text-sm font-medium rounded-lg border transition-all',
                  levelFilter === level
                    ? 'bg-indigo-500/20 border-indigo-500/50 text-indigo-400'
                    : 'border-slate-700 text-slate-400 hover:text-slate-200 hover:bg-slate-700/50'
                )}
              >
                {level || 'All'}
              </button>
            ))}
          </div>
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => setPaused(!paused)}
            className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
          >
            {paused ? <Play className="w-4 h-4" /> : <Pause className="w-4 h-4" />}
            {paused ? 'Resume' : 'Pause'}
          </button>
          <button
            onClick={handleClear}
            className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
          >
            <Trash2 className="w-4 h-4" />
            Clear
          </button>
        </div>
      </CardHeader>

      {/* Log Header */}
      <div className="flex items-center justify-between px-4 py-2 bg-slate-800/30 border-b border-slate-700/50">
        <CardTitle>
          Live Logs
          <span className="ml-2 text-sm font-normal text-slate-400">({total} entries)</span>
        </CardTitle>
        <div className="flex items-center gap-1.5 text-sm">
          <div className={cn(
            'w-2 h-2 rounded-full',
            paused ? 'bg-amber-400' : 'bg-emerald-400 animate-pulse'
          )} />
          <span className={paused ? 'text-amber-400' : 'text-emerald-400'}>
            {paused ? 'Paused' : 'Live'}
          </span>
        </div>
      </div>

      {/* Log Entries */}
      <div className="font-mono text-sm overflow-y-auto bg-slate-900/50" style={{ maxHeight }}>
        {loading ? (
          <div className="text-center text-slate-500 py-12">Loading logs...</div>
        ) : logs.length === 0 ? (
          <div className="text-center text-slate-500 py-12">
            <FileText className="w-16 h-16 mx-auto mb-4 opacity-30" />
            <p className="text-lg font-medium">Waiting for logs...</p>
            <p className="text-sm mt-1">Logs will appear here in real-time</p>
          </div>
        ) : (
          logs.map((log) => {
            const style = levelStyles[log.level] || levelStyles.DEBUG;
            return (
              <div
                key={log.id}
                className="px-4 py-2 border-b border-slate-800/50 flex items-start gap-3 hover:bg-slate-700/30 transition-colors"
              >
                <span className="text-slate-500 flex-shrink-0 w-20">
                  {formatTime(log.timestamp)}
                </span>
                <Badge variant={style.badge} className="flex-shrink-0 w-16 text-center">
                  {log.level}
                </Badge>
                <span className="flex-1 text-slate-200 break-all">{log.message}</span>
                <span className="text-slate-500 text-xs flex-shrink-0">{log.label}</span>
              </div>
            );
          })
        )}
      </div>
    </Card>
  );
}

// Compact version for dashboard
export function LogsPanelCompact() {
  const [logs, setLogs] = useState<LogEntry[]>([]);

  useEffect(() => {
    const fetchLogs = async () => {
      try {
        const response = await getLogs({ limit: 10 });
        setLogs(response.logs);
      } catch (error) {
        console.error('Failed to fetch logs:', error);
      }
    };

    fetchLogs();
    const interval = setInterval(fetchLogs, 5000);
    return () => clearInterval(interval);
  }, []);

  return (
    <Card>
      <CardHeader>
        <CardTitle>
          <FileText className="w-5 h-5" />
          Recent Activity
        </CardTitle>
      </CardHeader>
      <div className="p-4 max-h-[300px] overflow-y-auto">
        {logs.length === 0 ? (
          <div className="text-center text-slate-500 py-8">
            <p>No recent activity</p>
          </div>
        ) : (
          <div className="space-y-2">
            {logs.slice(0, 8).map((log) => {
              const style = levelStyles[log.level] || levelStyles.DEBUG;
              return (
                <div key={log.id} className="flex items-center gap-2 text-sm">
                  <Badge variant={style.badge}>{log.level}</Badge>
                  <span className="text-slate-300 truncate flex-1">{log.message}</span>
                  <span className="text-slate-500 text-xs">{formatTime(log.timestamp)}</span>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </Card>
  );
}
