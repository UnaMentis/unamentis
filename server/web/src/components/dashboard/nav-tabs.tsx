'use client';

import { cn } from '@/lib/utils';
import {
  LayoutDashboard,
  BarChart3,
  FileText,
  Smartphone,
  Server,
  FlaskConical,
  Activity,
  BookOpen,
  Library,
  Puzzle,
  Download,
  MonitorCog,
  Users,
  Timer,
  Brain,
  RefreshCw,
} from 'lucide-react';

// Section types
export type SectionId = 'operations' | 'content';

// Operations tabs
export type OpsTabId =
  | 'dashboard'
  | 'health'
  | 'latency'
  | 'fov'
  | 'metrics'
  | 'logs'
  | 'clients'
  | 'servers'
  | 'models'
  | 'users';

// Content tabs
export type ContentTabId = 'curricula' | 'sources' | 'plugins' | 'imports' | 'reprocess';

// Combined tab type
export type TabId = OpsTabId | ContentTabId;

interface SectionNavProps {
  activeSection: SectionId;
  onSectionChange: (section: SectionId) => void;
}

interface NavTabsProps {
  activeSection: SectionId;
  activeTab: TabId;
  onTabChange: (tab: TabId) => void;
}

const sections: { id: SectionId; label: string; icon: typeof MonitorCog }[] = [
  { id: 'operations', label: 'Operations', icon: MonitorCog },
  { id: 'content', label: 'Content', icon: Library },
];

const opsTabs: { id: OpsTabId; label: string; shortLabel: string; icon: typeof LayoutDashboard }[] =
  [
    { id: 'dashboard', label: 'Dashboard', shortLabel: 'Home', icon: LayoutDashboard },
    { id: 'health', label: 'System Health', shortLabel: 'Health', icon: Activity },
    { id: 'latency', label: 'Latency Tests', shortLabel: 'Latency', icon: Timer },
    { id: 'fov', label: 'FOV Context', shortLabel: 'FOV', icon: Brain },
    { id: 'metrics', label: 'Metrics', shortLabel: 'Metrics', icon: BarChart3 },
    { id: 'logs', label: 'Logs', shortLabel: 'Logs', icon: FileText },
    { id: 'clients', label: 'Clients', shortLabel: 'Clients', icon: Smartphone },
    { id: 'servers', label: 'Servers', shortLabel: 'Servers', icon: Server },
    { id: 'models', label: 'Models', shortLabel: 'Models', icon: FlaskConical },
    { id: 'users', label: 'Users', shortLabel: 'Users', icon: Users },
  ];

const contentTabs: {
  id: ContentTabId;
  label: string;
  shortLabel: string;
  icon: typeof BookOpen;
}[] = [
  { id: 'curricula', label: 'Curricula', shortLabel: 'Curricula', icon: BookOpen },
  { id: 'sources', label: 'Sources', shortLabel: 'Sources', icon: Library },
  { id: 'plugins', label: 'Plugins', shortLabel: 'Plugins', icon: Puzzle },
  { id: 'imports', label: 'Import Jobs', shortLabel: 'Imports', icon: Download },
  { id: 'reprocess', label: 'Reprocess', shortLabel: 'Reprocess', icon: RefreshCw },
];

export function SectionNav({ activeSection, onSectionChange }: SectionNavProps) {
  return (
    <nav className="bg-slate-900/80 border-b border-slate-700/30">
      <div className="max-w-[1920px] mx-auto px-2 sm:px-4">
        <div className="flex items-center gap-2 py-1.5">
          {sections.map((section) => {
            const Icon = section.icon;
            const isActive = activeSection === section.id;

            return (
              <button
                key={section.id}
                onClick={() => onSectionChange(section.id)}
                className={cn(
                  'flex items-center gap-2 px-4 py-1.5 text-sm font-medium rounded-md transition-all duration-150',
                  isActive
                    ? 'bg-orange-500/20 text-orange-300 border border-orange-500/30'
                    : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
                )}
              >
                <Icon className={cn('w-4 h-4', isActive ? 'text-orange-400' : '')} />
                <span>{section.label}</span>
              </button>
            );
          })}
        </div>
      </div>
    </nav>
  );
}

export function NavTabs({ activeSection, activeTab, onTabChange }: NavTabsProps) {
  const tabs = activeSection === 'operations' ? opsTabs : contentTabs;

  return (
    <nav className="bg-slate-800/50 border-b border-slate-700/50">
      <div className="max-w-[1920px] mx-auto px-2 sm:px-4">
        {/* Horizontally scrollable on mobile */}
        <div className="flex items-center gap-1 py-2 overflow-x-auto scrollbar-hide">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;

            return (
              <button
                key={tab.id}
                onClick={() => onTabChange(tab.id)}
                className={cn(
                  'flex items-center gap-1.5 sm:gap-2 px-2.5 sm:px-4 py-2 text-xs sm:text-sm font-medium rounded-md transition-all duration-150',
                  'border whitespace-nowrap flex-shrink-0',
                  isActive
                    ? 'bg-slate-700/80 text-white border-slate-600 shadow-sm'
                    : 'text-slate-400 border-transparent hover:text-slate-200 hover:bg-slate-700/40 hover:border-slate-600/50'
                )}
              >
                <Icon className={cn('w-4 h-4', isActive ? 'text-orange-400' : '')} />
                {/* Show short label on mobile, full label on larger screens */}
                <span className="sm:hidden">{tab.shortLabel}</span>
                <span className="hidden sm:inline">{tab.label}</span>
              </button>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
