'use client';

import { cn } from '@/lib/utils';
import {
  LayoutDashboard,
  BarChart3,
  FileText,
  Smartphone,
  Server,
  FlaskConical,
} from 'lucide-react';

export type TabId = 'dashboard' | 'metrics' | 'logs' | 'clients' | 'servers' | 'models';

interface NavTabsProps {
  activeTab: TabId;
  onTabChange: (tab: TabId) => void;
}

const tabs: { id: TabId; label: string; icon: typeof LayoutDashboard }[] = [
  { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { id: 'metrics', label: 'Metrics', icon: BarChart3 },
  { id: 'logs', label: 'Logs', icon: FileText },
  { id: 'clients', label: 'Clients', icon: Smartphone },
  { id: 'servers', label: 'Servers', icon: Server },
  { id: 'models', label: 'Models', icon: FlaskConical },
];

export function NavTabs({ activeTab, onTabChange }: NavTabsProps) {
  return (
    <nav className="border-b border-slate-800/50 bg-slate-900/50">
      <div className="max-w-[1920px] mx-auto px-6">
        <div className="flex gap-1">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;

            return (
              <button
                key={tab.id}
                onClick={() => onTabChange(tab.id)}
                className={cn(
                  'flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-all duration-200',
                  isActive
                    ? 'text-indigo-400 border-indigo-400 bg-slate-800/20'
                    : 'text-slate-400 border-transparent hover:text-slate-200 hover:bg-slate-800/30'
                )}
              >
                <Icon className="w-4 h-4" />
                {tab.label}
              </button>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
