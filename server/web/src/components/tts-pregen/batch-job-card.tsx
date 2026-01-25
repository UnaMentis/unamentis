'use client';

import {
  Clock,
  Play,
  Pause,
  RotateCcw,
  Trash2,
  CheckCircle,
  XCircle,
  Loader2,
  List,
  AlertTriangle,
} from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Tooltip } from '@/components/ui/tooltip';
import type { TTSPregenJob, JobProgress, JobStatus } from '@/types/tts-pregen';

interface BatchJobCardProps {
  job: TTSPregenJob;
  progress?: JobProgress;
  profileName: string;
  onStart: () => void;
  onPause: () => void;
  onResume: () => void;
  onDelete: () => void;
  onRetryFailed: () => void;
  onViewItems: () => void;
  compact?: boolean;
}

const statusConfig: Record<JobStatus, { icon: typeof Clock; color: string; label: string }> = {
  pending: {
    icon: Clock,
    color: 'bg-slate-500/20 text-slate-400 border-slate-500/30',
    label: 'Pending',
  },
  running: {
    icon: Loader2,
    color: 'bg-blue-500/20 text-blue-400 border-blue-500/30',
    label: 'Running',
  },
  paused: {
    icon: Pause,
    color: 'bg-amber-500/20 text-amber-400 border-amber-500/30',
    label: 'Paused',
  },
  completed: {
    icon: CheckCircle,
    color: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30',
    label: 'Completed',
  },
  failed: {
    icon: XCircle,
    color: 'bg-red-500/20 text-red-400 border-red-500/30',
    label: 'Failed',
  },
  cancelled: {
    icon: XCircle,
    color: 'bg-slate-500/20 text-slate-400 border-slate-500/30',
    label: 'Cancelled',
  },
};

function formatDuration(startedAt?: string, endedAt?: string): string {
  if (!startedAt) return '-';
  const start = new Date(startedAt).getTime();
  const end = endedAt ? new Date(endedAt).getTime() : Date.now();
  const durationMs = end - start;

  const seconds = Math.floor(durationMs / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);

  if (hours > 0) {
    return `${hours}h ${minutes % 60}m`;
  } else if (minutes > 0) {
    return `${minutes}m ${seconds % 60}s`;
  } else {
    return `${seconds}s`;
  }
}

function formatSourceType(sourceType: string): string {
  switch (sourceType) {
    case 'knowledge-bowl':
      return 'Knowledge Bowl';
    case 'curriculum':
      return 'Curriculum';
    case 'custom':
      return 'Custom';
    default:
      return sourceType;
  }
}

export function BatchJobCard({
  job,
  progress,
  profileName,
  onStart,
  onPause,
  onResume,
  onDelete,
  onRetryFailed,
  onViewItems,
  compact = false,
}: BatchJobCardProps) {
  const config = statusConfig[job.status] || statusConfig.pending;
  const StatusIcon = config.icon;
  const isRunning = job.status === 'running';
  const isPaused = job.status === 'paused';
  const isPending = job.status === 'pending';
  const isCompleted = job.status === 'completed';
  const isFailed = job.status === 'failed';

  const percentage =
    progress?.percentage ??
    (job.total_items > 0 ? (job.completed_items / job.total_items) * 100 : 0);
  const completedItems = progress?.completed_items ?? job.completed_items;
  const failedItems = progress?.failed_items ?? job.failed_items;
  const totalItems = progress?.total_items ?? job.total_items;

  if (compact) {
    return (
      <Card className="bg-slate-900/50 border-slate-800">
        <CardContent className="p-4">
          <div className="flex items-center justify-between gap-4">
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <h4 className="font-medium text-slate-100 truncate">{job.name}</h4>
                <Badge className={config.color}>
                  <StatusIcon className="w-3 h-3 mr-1" />
                  {config.label}
                </Badge>
                {failedItems > 0 && (
                  <Badge className="bg-red-500/20 text-red-400 border-red-500/30">
                    <AlertTriangle className="w-3 h-3 mr-1" />
                    {failedItems} failed
                  </Badge>
                )}
              </div>

              {job.last_error && isFailed && (
                <p className="text-sm text-red-400 mt-1 truncate">{job.last_error}</p>
              )}

              <div className="flex items-center gap-4 mt-2 text-xs text-slate-500">
                <span>{formatSourceType(job.source_type)}</span>
                <span>Profile: {profileName}</span>
                <span>
                  Items: {completedItems}/{totalItems}
                </span>
                <span>Duration: {formatDuration(job.started_at, job.completed_at)}</span>
              </div>
            </div>

            <div className="flex items-center gap-1">
              {failedItems > 0 && (
                <Tooltip content="Reprocess all failed items" side="bottom">
                  <Button variant="ghost" size="sm" onClick={onRetryFailed}>
                    <RotateCcw className="w-4 h-4" />
                  </Button>
                </Tooltip>
              )}
              <Tooltip content="View individual items and their status" side="bottom">
                <Button variant="ghost" size="sm" onClick={onViewItems}>
                  <List className="w-4 h-4" />
                </Button>
              </Tooltip>
              <Tooltip content="Delete this job and its generated files" side="bottom">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={onDelete}
                  className="text-red-400 hover:text-red-300"
                >
                  <Trash2 className="w-4 h-4" />
                </Button>
              </Tooltip>
            </div>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="bg-slate-900/50 border-slate-800">
      <CardContent className="p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="flex-1">
            <div className="flex items-center gap-2 mb-2">
              <h4 className="font-medium text-slate-100">{job.name}</h4>
              <Badge className={config.color}>
                <StatusIcon className={`w-3 h-3 mr-1 ${isRunning ? 'animate-spin' : ''}`} />
                {config.label}
              </Badge>
              {failedItems > 0 && (
                <Badge className="bg-red-500/20 text-red-400 border-red-500/30">
                  <AlertTriangle className="w-3 h-3 mr-1" />
                  {failedItems} failed
                </Badge>
              )}
            </div>

            <div className="flex items-center gap-3 text-sm text-slate-400 mb-3">
              <span className="flex items-center gap-1">
                Source: {formatSourceType(job.source_type)}
              </span>
              <span className="text-slate-600">|</span>
              <span>Profile: {profileName}</span>
            </div>

            {/* Progress info for running/paused jobs */}
            {(isRunning || isPaused) && progress?.current_item_text && (
              <p className="text-sm text-slate-400 mb-3 truncate">
                Current: {progress.current_item_text}
              </p>
            )}

            {/* Progress Bar */}
            {(isRunning || isPaused || isCompleted || isFailed) && (
              <div className="space-y-2">
                <div className="flex justify-between text-xs text-slate-500">
                  <span>
                    {completedItems} / {totalItems} items
                  </span>
                  <span>{Math.round(percentage)}%</span>
                </div>
                <div className="h-2 bg-slate-800 rounded-full overflow-hidden">
                  <div
                    className={`h-full transition-all duration-300 ${
                      isFailed
                        ? 'bg-gradient-to-r from-red-500 to-red-600'
                        : isCompleted
                          ? 'bg-gradient-to-r from-emerald-500 to-emerald-600'
                          : 'bg-gradient-to-r from-blue-500 to-cyan-500'
                    }`}
                    style={{ width: `${percentage}%` }}
                  />
                </div>
              </div>
            )}

            {/* Stats */}
            <div className="flex items-center gap-4 mt-3 text-xs text-slate-500">
              <span>Format: {job.output_format}</span>
              {job.started_at && (
                <span>Duration: {formatDuration(job.started_at, job.completed_at)}</span>
              )}
              {job.created_at && <span>Created: {new Date(job.created_at).toLocaleString()}</span>}
            </div>

            {/* Error message */}
            {job.last_error && <p className="text-sm text-red-400 mt-2">{job.last_error}</p>}
          </div>

          {/* Action Buttons */}
          <div className="flex flex-col gap-2">
            {isPending && (
              <Tooltip content="Begin processing this batch job" side="left">
                <Button size="sm" onClick={onStart} className="bg-emerald-600 hover:bg-emerald-700">
                  <Play className="w-4 h-4 mr-1" />
                  Start
                </Button>
              </Tooltip>
            )}
            {isRunning && (
              <Tooltip content="Temporarily pause processing (can be resumed)" side="left">
                <Button size="sm" onClick={onPause} variant="outline">
                  <Pause className="w-4 h-4 mr-1" />
                  Pause
                </Button>
              </Tooltip>
            )}
            {isPaused && (
              <Tooltip content="Continue processing from where it left off" side="left">
                <Button size="sm" onClick={onResume} className="bg-blue-600 hover:bg-blue-700">
                  <Play className="w-4 h-4 mr-1" />
                  Resume
                </Button>
              </Tooltip>
            )}
            {failedItems > 0 && (
              <Tooltip content="Reprocess only the items that failed" side="left">
                <Button size="sm" variant="outline" onClick={onRetryFailed}>
                  <RotateCcw className="w-4 h-4 mr-1" />
                  Retry Failed
                </Button>
              </Tooltip>
            )}
            <Tooltip content="View all items in this job with their status" side="left">
              <Button size="sm" variant="ghost" onClick={onViewItems}>
                <List className="w-4 h-4 mr-1" />
                Items
              </Button>
            </Tooltip>
            <Tooltip content="Permanently delete this job and its files" side="left">
              <Button
                size="sm"
                variant="ghost"
                onClick={onDelete}
                className="text-red-400 hover:text-red-300 hover:bg-red-500/10"
              >
                <Trash2 className="w-4 h-4 mr-1" />
                Delete
              </Button>
            </Tooltip>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
