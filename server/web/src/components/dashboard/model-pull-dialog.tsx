'use client';

import { useState, useRef } from 'react';
import { Download, X, AlertTriangle, Check, Loader2 } from 'lucide-react';
import { pullModel } from '@/lib/api-client';
import type { ModelPullProgress } from '@/types';
import { cn } from '@/lib/utils';

interface Props {
  onClose: () => void;
  onComplete: () => void;
}

export function ModelPullDialog({ onClose, onComplete }: Props) {
  const [modelName, setModelName] = useState('');
  const [pulling, setPulling] = useState(false);
  const [progress, setProgress] = useState<ModelPullProgress | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [completed, setCompleted] = useState(false);
  const abortControllerRef = useRef<AbortController | null>(null);

  const handlePull = async () => {
    if (!modelName.trim()) {
      setError('Please enter a model name');
      return;
    }

    setPulling(true);
    setError(null);
    setProgress(null);
    setCompleted(false);

    abortControllerRef.current = new AbortController();

    try {
      await pullModel(
        modelName.trim(),
        (prog) => setProgress(prog),
        abortControllerRef.current.signal
      );
      setCompleted(true);
      setTimeout(() => {
        onComplete();
        onClose();
      }, 1500);
    } catch (err) {
      if (err instanceof Error && err.message === 'Pull cancelled') {
        setError('Pull cancelled');
      } else {
        setError(err instanceof Error ? err.message : 'Failed to pull model');
      }
    } finally {
      setPulling(false);
      abortControllerRef.current = null;
    }
  };

  const handleCancel = () => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }
  };

  const formatBytes = (bytes: number): string => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
  };

  const progressPercent =
    progress && progress.total > 0 ? Math.round((progress.completed / progress.total) * 100) : 0;

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6 w-full max-w-md shadow-xl">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-semibold text-slate-100 flex items-center gap-2">
            <Download className="w-5 h-5 text-indigo-400" />
            Pull Model
          </h2>
          <button
            onClick={onClose}
            disabled={pulling}
            className="text-slate-400 hover:text-slate-200 disabled:opacity-50"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {!pulling && !completed && (
          <>
            <div className="mb-4">
              <label className="block text-sm text-slate-400 mb-2">Model Name</label>
              <input
                type="text"
                value={modelName}
                onChange={(e) => setModelName(e.target.value)}
                placeholder="e.g., llama3.2:latest, qwen2.5:3b"
                className="w-full px-4 py-2 bg-slate-900 border border-slate-700 rounded-lg text-slate-100 placeholder-slate-500 focus:outline-none focus:border-indigo-500"
                onKeyDown={(e) => e.key === 'Enter' && handlePull()}
              />
              <p className="mt-2 text-xs text-slate-500">
                Enter the model name from the Ollama library (e.g., llama3.2, mistral, qwen2.5:7b)
              </p>
            </div>

            {error && (
              <div className="mb-4 flex items-center gap-2 text-red-400 text-sm bg-red-500/10 border border-red-500/30 rounded-lg px-3 py-2">
                <AlertTriangle className="w-4 h-4 flex-shrink-0" />
                {error}
              </div>
            )}

            <div className="flex gap-3">
              <button
                onClick={onClose}
                className="flex-1 px-4 py-2 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:bg-slate-700/50 transition-all"
              >
                Cancel
              </button>
              <button
                onClick={handlePull}
                disabled={!modelName.trim()}
                className={cn(
                  'flex-1 px-4 py-2 text-sm font-medium rounded-lg transition-all flex items-center justify-center gap-2',
                  modelName.trim()
                    ? 'bg-indigo-500 hover:bg-indigo-400 text-white'
                    : 'bg-slate-700 text-slate-400 cursor-not-allowed'
                )}
              >
                <Download className="w-4 h-4" />
                Pull Model
              </button>
            </div>
          </>
        )}

        {pulling && (
          <div className="space-y-4">
            <div className="flex items-center justify-between text-sm">
              <span className="text-slate-400">{progress?.status || 'Starting...'}</span>
              <span className="text-slate-200 font-medium">{progressPercent}%</span>
            </div>

            <div className="relative h-3 bg-slate-700 rounded-full overflow-hidden">
              <div
                className="absolute inset-y-0 left-0 bg-indigo-500 transition-all duration-300"
                style={{ width: `${progressPercent}%` }}
              />
            </div>

            {progress && progress.total > 0 && (
              <div className="text-xs text-slate-500 text-center">
                {formatBytes(progress.completed)} / {formatBytes(progress.total)}
              </div>
            )}

            {error && (
              <div className="flex items-center gap-2 text-red-400 text-sm bg-red-500/10 border border-red-500/30 rounded-lg px-3 py-2">
                <AlertTriangle className="w-4 h-4 flex-shrink-0" />
                {error}
              </div>
            )}

            <button
              onClick={handleCancel}
              className="w-full px-4 py-2 text-sm font-medium rounded-lg border border-amber-500/30 text-amber-400 hover:bg-amber-500/10 transition-all"
            >
              Cancel Download
            </button>
          </div>
        )}

        {completed && (
          <div className="text-center py-4">
            <div className="w-12 h-12 bg-emerald-500/20 rounded-full flex items-center justify-center mx-auto mb-3">
              <Check className="w-6 h-6 text-emerald-400" />
            </div>
            <p className="text-slate-200 font-medium">Model pulled successfully!</p>
            <p className="text-sm text-slate-400 mt-1">{modelName}</p>
          </div>
        )}
      </div>
    </div>
  );
}
