/**
 * Run Selector Component
 * ======================
 *
 * Dropdown selector for choosing test runs to analyze.
 * Supports multi-select for comparing multiple runs.
 */

'use client';

import { useMemo } from 'react';
import { Check, ChevronDown } from 'lucide-react';
import type { TestRun } from '@/types/latency-charts';

interface RunSelectorProps {
  /** Available test runs */
  runs: TestRun[];
  /** Currently selected run IDs */
  selectedRuns: string[];
  /** Callback when selection changes */
  onSelectionChange: (runIds: string[]) => void;
  /** Enable multi-select mode */
  multiSelect?: boolean;
  /** Maximum selections in multi-select mode */
  maxSelections?: number;
  /** Label text */
  label?: string;
}

/**
 * Run selection component.
 */
export function RunSelector({
  runs,
  selectedRuns,
  onSelectionChange,
  multiSelect = false,
  maxSelections = 5,
  label = 'Select Run',
}: RunSelectorProps) {
  // Sort runs by completion time (newest first)
  const sortedRuns = useMemo(
    () =>
      [...runs]
        .filter((r) => r.status === 'completed')
        .sort(
          (a, b) =>
            new Date(b.completedAt || b.startedAt).getTime() -
            new Date(a.completedAt || a.startedAt).getTime()
        ),
    [runs]
  );

  const handleToggle = (runId: string) => {
    if (multiSelect) {
      if (selectedRuns.includes(runId)) {
        onSelectionChange(selectedRuns.filter((id) => id !== runId));
      } else if (selectedRuns.length < maxSelections) {
        onSelectionChange([...selectedRuns, runId]);
      }
    } else {
      onSelectionChange([runId]);
    }
  };

  const formatRunLabel = (run: TestRun) => {
    const date = new Date(run.completedAt || run.startedAt);
    const dateStr = date.toLocaleDateString();
    const timeStr = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    return `${run.suiteName} - ${dateStr} ${timeStr}`;
  };

  if (sortedRuns.length === 0) {
    return <div className="text-sm text-slate-500">No completed runs available</div>;
  }

  return (
    <div className="space-y-2">
      <label className="block text-sm font-medium text-slate-400">{label}</label>
      <div className="relative">
        <select
          value={multiSelect ? '' : selectedRuns[0] || ''}
          onChange={(e) => !multiSelect && handleToggle(e.target.value)}
          className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 appearance-none cursor-pointer"
          disabled={multiSelect}
        >
          <option value="">
            {multiSelect ? `${selectedRuns.length} runs selected` : 'Select a run...'}
          </option>
          {!multiSelect &&
            sortedRuns.map((run) => (
              <option key={run.id} value={run.id}>
                {formatRunLabel(run)} ({run.results?.length || 0} results)
              </option>
            ))}
        </select>
        <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" />
      </div>

      {/* Multi-select list */}
      {multiSelect && (
        <div className="max-h-48 overflow-y-auto space-y-1 mt-2 p-2 bg-slate-800/50 rounded-lg border border-slate-700/50">
          {sortedRuns.map((run) => {
            const isSelected = selectedRuns.includes(run.id);
            const isDisabled = !isSelected && selectedRuns.length >= maxSelections;

            return (
              <button
                key={run.id}
                onClick={() => handleToggle(run.id)}
                disabled={isDisabled}
                className={`w-full flex items-center gap-2 px-3 py-2 rounded-lg text-left text-sm transition-all ${
                  isSelected
                    ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                    : isDisabled
                      ? 'text-slate-500 cursor-not-allowed'
                      : 'text-slate-300 hover:bg-slate-700/50'
                }`}
              >
                <div
                  className={`w-4 h-4 rounded border flex items-center justify-center ${
                    isSelected ? 'bg-indigo-500 border-indigo-500' : 'border-slate-600'
                  }`}
                >
                  {isSelected && <Check className="w-3 h-3 text-white" />}
                </div>
                <span className="flex-1 truncate">{formatRunLabel(run)}</span>
                <span className="text-xs text-slate-500">{run.results?.length || 0} results</span>
              </button>
            );
          })}
        </div>
      )}

      {multiSelect && (
        <div className="text-xs text-slate-500">
          Select up to {maxSelections} runs for comparison
        </div>
      )}
    </div>
  );
}
