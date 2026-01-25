'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  X,
  FileAudio,
  CheckCircle,
  XCircle,
  Clock,
  Loader2,
  RotateCcw,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import type { TTSJobItem, ItemStatus } from '@/types/tts-pregen';
import { getJobItems, retryFailedItems } from '@/lib/api-client';

interface BatchJobItemsListProps {
  jobId: string;
  onClose: () => void;
}

const statusConfig: Record<ItemStatus, { icon: typeof Clock; color: string; label: string }> = {
  pending: {
    icon: Clock,
    color: 'bg-slate-500/20 text-slate-400 border-slate-500/30',
    label: 'Pending',
  },
  processing: {
    icon: Loader2,
    color: 'bg-blue-500/20 text-blue-400 border-blue-500/30',
    label: 'Processing',
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
  skipped: {
    icon: Clock,
    color: 'bg-amber-500/20 text-amber-400 border-amber-500/30',
    label: 'Skipped',
  },
};

export function BatchJobItemsList({ jobId, onClose }: BatchJobItemsListProps) {
  const [items, setItems] = useState<TTSJobItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<string>('all');
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [retrying, setRetrying] = useState(false);
  const pageSize = 20;

  const fetchItems = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const status = filter === 'all' ? undefined : filter;
      const offset = (page - 1) * pageSize;
      const result = await getJobItems(jobId, { status, limit: pageSize, offset });
      setItems(result.items || []);
      setTotal(result.total || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load items');
    } finally {
      setLoading(false);
    }
  }, [jobId, filter, page]);

  useEffect(() => {
    fetchItems();
  }, [fetchItems]);

  const handleRetryFailed = async () => {
    setRetrying(true);
    try {
      const result = await retryFailedItems(jobId);
      if (result.success) {
        await fetchItems();
      } else {
        setError(result.error || 'Failed to retry');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to retry');
    } finally {
      setRetrying(false);
    }
  };

  const totalPages = Math.ceil(total / pageSize);
  const failedCount = items.filter((i) => i.status === 'failed').length;

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
      <Card className="bg-slate-900 border-slate-700 w-full max-w-4xl max-h-[90vh] flex flex-col">
        <CardHeader className="flex flex-row items-center justify-between border-b border-slate-800 pb-4 flex-shrink-0">
          <CardTitle className="flex items-center gap-2 text-white">
            <FileAudio className="w-5 h-5 text-amber-400" />
            Job Items
          </CardTitle>
          <div className="flex items-center gap-2">
            <select
              value={filter}
              onChange={(e) => {
                setFilter(e.target.value);
                setPage(1);
              }}
              className="px-3 py-1.5 text-sm bg-slate-800 border border-slate-700 rounded-md text-slate-300 focus:outline-none focus:ring-2 focus:ring-amber-500/50"
            >
              <option value="all">All Status</option>
              <option value="pending">Pending</option>
              <option value="processing">Processing</option>
              <option value="completed">Completed</option>
              <option value="failed">Failed</option>
              <option value="skipped">Skipped</option>
            </select>
            {failedCount > 0 && (
              <Button size="sm" variant="outline" onClick={handleRetryFailed} disabled={retrying}>
                {retrying ? (
                  <Loader2 className="w-4 h-4 mr-1 animate-spin" />
                ) : (
                  <RotateCcw className="w-4 h-4 mr-1" />
                )}
                Retry Failed
              </Button>
            )}
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>
        </CardHeader>

        <CardContent className="pt-4 flex-1 overflow-hidden flex flex-col">
          {/* Error */}
          {error && (
            <div className="p-3 mb-4 bg-red-500/10 border border-red-500/30 rounded-md text-red-400 text-sm">
              {error}
            </div>
          )}

          {/* Stats */}
          <div className="flex items-center gap-4 mb-4 text-sm text-slate-400">
            <span>Total: {total}</span>
            <span>Showing: {items.length}</span>
            <span>
              Page: {page} / {totalPages || 1}
            </span>
          </div>

          {/* Items List */}
          <div className="flex-1 overflow-y-auto">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <div className="animate-spin w-8 h-8 border-2 border-amber-500 border-t-transparent rounded-full" />
              </div>
            ) : items.length === 0 ? (
              <div className="text-center py-12 text-slate-500">No items found</div>
            ) : (
              <div className="space-y-2">
                {items.map((item) => {
                  const config = statusConfig[item.status] || statusConfig.pending;
                  const StatusIcon = config.icon;

                  return (
                    <div
                      key={item.id}
                      className="p-3 bg-slate-800/50 rounded-lg border border-slate-700"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <span className="text-xs text-slate-500">#{item.item_index}</span>
                            <Badge className={config.color}>
                              <StatusIcon
                                className={`w-3 h-3 mr-1 ${
                                  item.status === 'processing' ? 'animate-spin' : ''
                                }`}
                              />
                              {config.label}
                            </Badge>
                            {item.source_ref && (
                              <span className="text-xs text-slate-500 truncate">
                                {item.source_ref}
                              </span>
                            )}
                          </div>
                          <p className="text-sm text-slate-300 line-clamp-2">{item.text_content}</p>
                          {item.last_error && (
                            <p className="text-xs text-red-400 mt-1">{item.last_error}</p>
                          )}
                        </div>
                        <div className="text-xs text-slate-500 text-right flex-shrink-0">
                          {item.duration_seconds && <div>{item.duration_seconds.toFixed(1)}s</div>}
                          {item.attempt_count > 1 && <div>Attempts: {item.attempt_count}</div>}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-center gap-2 mt-4 pt-4 border-t border-slate-800">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={page === 1}
              >
                <ChevronLeft className="w-4 h-4" />
              </Button>
              <span className="text-sm text-slate-400">
                Page {page} of {totalPages}
              </span>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={page === totalPages}
              >
                <ChevronRight className="w-4 h-4" />
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
