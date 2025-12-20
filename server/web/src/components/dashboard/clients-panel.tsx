'use client';

import { useState, useEffect } from 'react';
import { Smartphone, RefreshCw, Circle } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatCard } from '@/components/ui/stat-card';
import type { RemoteClient } from '@/types';
import { getClients } from '@/lib/api-client';
import { formatRelativeTime, cn } from '@/lib/utils';

export function ClientsPanel() {
  const [clients, setClients] = useState<RemoteClient[]>([]);
  const [stats, setStats] = useState({ online: 0, idle: 0, offline: 0 });
  const [loading, setLoading] = useState(true);

  const fetchClients = async () => {
    try {
      const response = await getClients();
      setClients(response.clients);
      setStats({
        online: response.online,
        idle: response.idle,
        offline: response.offline,
      });
    } catch (error) {
      console.error('Failed to fetch clients:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchClients();
    const interval = setInterval(fetchClients, 10000);
    return () => clearInterval(interval);
  }, []);

  const statusStyles: Record<string, { color: string; badge: 'success' | 'warning' | 'default' }> = {
    online: { color: 'bg-emerald-400', badge: 'success' },
    idle: { color: 'bg-amber-400', badge: 'warning' },
    offline: { color: 'bg-slate-500', badge: 'default' },
  };

  return (
    <div className="space-y-6">
      {/* Stats */}
      <div className="grid grid-cols-3 gap-4">
        <StatCard
          icon={Circle}
          value={stats.online}
          label="Online"
          iconColor="text-emerald-400"
          iconBgColor="bg-emerald-400/20"
        />
        <StatCard
          icon={Circle}
          value={stats.idle}
          label="Idle"
          iconColor="text-amber-400"
          iconBgColor="bg-amber-400/20"
        />
        <StatCard
          icon={Circle}
          value={stats.offline}
          label="Offline"
          iconColor="text-slate-400"
          iconBgColor="bg-slate-500/20"
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Remote Clients</CardTitle>
          <button
            onClick={fetchClients}
            className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
          >
            <RefreshCw className="w-4 h-4" />
            Refresh
          </button>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="text-center text-slate-500 py-12">Loading clients...</div>
          ) : clients.length === 0 ? (
            <div className="text-center text-slate-500 py-12">
              <Smartphone className="w-16 h-16 mx-auto mb-4 opacity-30" />
              <p className="text-lg font-medium">No clients connected</p>
              <p className="text-sm mt-1">Clients will appear here when they connect</p>
            </div>
          ) : (
            <div className="space-y-4">
              {clients.map((client) => {
                const style = statusStyles[client.status] || statusStyles.offline;

                return (
                  <div
                    key={client.id}
                    className="flex items-center justify-between p-4 rounded-lg bg-slate-800/30 hover:bg-slate-800/50 transition-colors"
                  >
                    <div className="flex items-center gap-4">
                      <div className="w-12 h-12 rounded-xl bg-slate-700/50 flex items-center justify-center">
                        <Smartphone className="w-6 h-6 text-slate-300" />
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="font-semibold text-slate-100">{client.name}</h3>
                          <Badge variant={style.badge}>{client.status}</Badge>
                        </div>
                        <div className="flex items-center gap-4 text-sm text-slate-400 mt-1">
                          <span>{client.device_model}</span>
                          <span>{client.os_version}</span>
                          <span>v{client.app_version}</span>
                        </div>
                      </div>
                    </div>
                    <div className="text-right text-sm">
                      <div className="text-slate-300">{client.total_sessions} sessions</div>
                      <div className="text-slate-500">{formatRelativeTime(client.last_seen)}</div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

// Compact version for dashboard
export function ClientsPanelCompact() {
  const [clients, setClients] = useState<RemoteClient[]>([]);

  useEffect(() => {
    const fetchClients = async () => {
      try {
        const response = await getClients();
        setClients(response.clients);
      } catch (error) {
        console.error('Failed to fetch clients:', error);
      }
    };

    fetchClients();
    const interval = setInterval(fetchClients, 10000);
    return () => clearInterval(interval);
  }, []);

  const statusStyles: Record<string, string> = {
    online: 'bg-emerald-400',
    idle: 'bg-amber-400',
    offline: 'bg-slate-500',
  };

  return (
    <Card className="lg:col-span-2">
      <CardHeader>
        <CardTitle>
          <Smartphone className="w-5 h-5" />
          Connected Clients
        </CardTitle>
      </CardHeader>
      <CardContent>
        {clients.length === 0 ? (
          <div className="text-center text-slate-500 py-8">
            <Smartphone className="w-12 h-12 mx-auto mb-2 opacity-50" />
            <p>No clients connected</p>
          </div>
        ) : (
          <div className="grid gap-3">
            {clients.slice(0, 4).map((client) => (
              <div
                key={client.id}
                className="flex items-center justify-between p-3 rounded-lg bg-slate-800/30"
              >
                <div className="flex items-center gap-3">
                  <div className={cn('w-2 h-2 rounded-full', statusStyles[client.status] || statusStyles.offline)} />
                  <div>
                    <div className="font-medium text-slate-100">{client.name}</div>
                    <div className="text-xs text-slate-400">{client.device_model} • {client.os_version}</div>
                  </div>
                </div>
                <span className="text-sm text-slate-400">{formatRelativeTime(client.last_seen)}</span>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
