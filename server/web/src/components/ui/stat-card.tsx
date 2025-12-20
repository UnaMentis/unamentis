'use client';

import { cn } from '@/lib/utils';
import { LucideIcon } from 'lucide-react';

interface StatCardProps {
  icon: LucideIcon;
  value: string | number;
  label: string;
  iconColor?: string;
  iconBgColor?: string;
}

export function StatCard({
  icon: Icon,
  value,
  label,
  iconColor = 'text-indigo-400',
  iconBgColor = 'bg-indigo-400/20',
}: StatCardProps) {
  return (
    <div className="flex items-center gap-3 p-4 rounded-xl bg-slate-800/50 border border-slate-700/50 hover:border-slate-600/50 transition-all duration-200">
      <div className={cn('w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0', iconBgColor)}>
        <Icon className={cn('w-5 h-5', iconColor)} />
      </div>
      <div>
        <div className="text-xl font-bold text-slate-100">{value}</div>
        <div className="text-xs text-slate-400">{label}</div>
      </div>
    </div>
  );
}
