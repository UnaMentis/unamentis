'use client';

import { useState, useEffect } from 'react';
import { Mic, FileText, Users } from 'lucide-react';
import { cn } from '@/lib/utils';
import { isUsingMockData } from '@/lib/api-client';

interface HeaderProps {
  stats?: {
    logsCount: number;
    clientsCount: number;
  };
  connected?: boolean;
}

export function Header({ stats, connected = false }: HeaderProps) {
  const [currentTime, setCurrentTime] = useState('--:--:--');
  const isMock = isUsingMockData();

  useEffect(() => {
    const updateTime = () => {
      setCurrentTime(new Date().toLocaleTimeString('en-US', { hour12: false }));
    };
    updateTime();
    const interval = setInterval(updateTime, 1000);
    return () => clearInterval(interval);
  }, []);

  return (
    <header className="border-b border-slate-800/50 bg-slate-900/70 backdrop-blur-xl sticky top-0 z-50">
      <div className="max-w-[1920px] mx-auto px-6 py-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-indigo-500 to-violet-500 flex items-center justify-center">
                <Mic className="w-6 h-6 text-white" />
              </div>
              <div>
                <h1 className="text-xl font-bold bg-gradient-to-r from-indigo-400 via-violet-400 to-pink-400 bg-clip-text text-transparent">
                  VoiceLearn
                </h1>
                <p className="text-xs text-slate-400">Management Console</p>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-6">
            {/* Connection Status */}
            <div className={cn(
              'flex items-center gap-2 px-3 py-1.5 rounded-full border',
              isMock
                ? 'bg-amber-500/10 border-amber-500/30'
                : connected
                  ? 'bg-emerald-500/10 border-emerald-500/30'
                  : 'bg-slate-800/50 border-slate-700/50'
            )}>
              <div className={cn(
                'w-2 h-2 rounded-full',
                isMock
                  ? 'bg-amber-400 animate-pulse'
                  : connected
                    ? 'bg-emerald-400 animate-pulse'
                    : 'bg-slate-500'
              )} />
              <span className={cn(
                'text-sm',
                isMock
                  ? 'text-amber-400'
                  : connected
                    ? 'text-emerald-400'
                    : 'text-slate-400'
              )}>
                {isMock ? 'Demo Mode' : connected ? 'Connected' : 'Connecting...'}
              </span>
            </div>

            {/* Quick Stats */}
            <div className="hidden md:flex items-center gap-4 text-sm">
              <div className="flex items-center gap-2">
                <FileText className="w-4 h-4 text-emerald-400" />
                <span className="text-slate-300">
                  <span className="font-semibold text-slate-100">{stats?.logsCount ?? 0}</span> logs
                </span>
              </div>
              <div className="flex items-center gap-2">
                <Users className="w-4 h-4 text-blue-400" />
                <span className="text-slate-300">
                  <span className="font-semibold text-slate-100">{stats?.clientsCount ?? 0}</span> clients
                </span>
              </div>
            </div>

            {/* Time */}
            <div className="text-sm text-slate-400 font-mono">{currentTime}</div>
          </div>
        </div>
      </div>
    </header>
  );
}
