'use client';

import { useState, useEffect } from 'react';
import { X, Loader2, Save, RotateCcw, Settings } from 'lucide-react';
import type { ModelInfo, ModelParameters } from '@/types';
import { getModelParameters, saveModelParameters } from '@/lib/api-client';
import { cn } from '@/lib/utils';

interface ModelParametersModalProps {
  model: ModelInfo;
  onClose: () => void;
}

export function ModelParametersModal({ model, onClose }: ModelParametersModalProps) {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [parameters, setParameters] = useState<ModelParameters | null>(null);
  const [values, setValues] = useState<Record<string, number>>({});

  useEffect(() => {
    const fetchParams = async () => {
      setLoading(true);
      setError(null);
      try {
        const response = await getModelParameters(model.id);
        setParameters(response.parameters);
        // Extract current values
        const currentValues: Record<string, number> = {};
        for (const [key, def] of Object.entries(response.parameters)) {
          currentValues[key] = def.value;
        }
        setValues(currentValues);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load parameters');
      } finally {
        setLoading(false);
      }
    };
    fetchParams();
  }, [model.id]);

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    try {
      await saveModelParameters(model.id, values);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save parameters');
    } finally {
      setSaving(false);
    }
  };

  const handleReset = () => {
    if (!parameters) return;
    const defaultValues: Record<string, number> = {};
    for (const [key, def] of Object.entries(parameters)) {
      defaultValues[key] = def.value;
    }
    setValues(defaultValues);
  };

  const updateValue = (key: string, value: number) => {
    setValues((prev) => ({ ...prev, [key]: value }));
  };

  // Format display value based on step
  const formatValue = (value: number, step?: number): string => {
    if (step && step < 1) {
      const decimals = String(step).split('.')[1]?.length || 1;
      return value.toFixed(decimals);
    }
    return String(Math.round(value));
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6 w-full max-w-lg max-h-[90vh] overflow-y-auto shadow-xl">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-semibold text-slate-100 flex items-center gap-2">
            <Settings className="w-5 h-5 text-violet-400" />
            Model Parameters
          </h2>
          <button
            onClick={onClose}
            disabled={saving}
            className="text-slate-400 hover:text-slate-200 disabled:opacity-50"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Model Name */}
        <div className="mb-6 p-3 bg-slate-900/50 rounded-lg">
          <span className="text-sm text-slate-400">Model:</span>
          <span className="ml-2 font-medium text-slate-100">{model.name}</span>
        </div>

        {/* Error Display */}
        {error && (
          <div className="mb-4 bg-red-500/10 border border-red-500/30 rounded-lg px-4 py-3 text-red-400 text-sm">
            {error}
          </div>
        )}

        {/* Loading State */}
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-8 h-8 animate-spin text-slate-400" />
          </div>
        ) : parameters ? (
          <div className="space-y-6">
            {/* Context Size */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-slate-300">
                  {parameters.num_ctx.description}
                </label>
                <span className="text-sm font-mono text-indigo-400">
                  {formatValue(values.num_ctx)}
                </span>
              </div>
              <input
                type="range"
                min={parameters.num_ctx.min}
                max={parameters.num_ctx.max}
                step={1024}
                value={values.num_ctx}
                onChange={(e) => updateValue('num_ctx', parseInt(e.target.value))}
                className="w-full h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-indigo-500"
              />
              <div className="flex justify-between text-xs text-slate-500">
                <span>{parameters.num_ctx.min}</span>
                <span>{parameters.num_ctx.max}</span>
              </div>
            </div>

            {/* Temperature */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-slate-300">
                  {parameters.temperature.description}
                </label>
                <span className="text-sm font-mono text-indigo-400">
                  {formatValue(values.temperature, parameters.temperature.step)}
                </span>
              </div>
              <input
                type="range"
                min={parameters.temperature.min}
                max={parameters.temperature.max}
                step={parameters.temperature.step || 0.1}
                value={values.temperature}
                onChange={(e) => updateValue('temperature', parseFloat(e.target.value))}
                className="w-full h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-indigo-500"
              />
              <div className="flex justify-between text-xs text-slate-500">
                <span>Deterministic</span>
                <span>Creative</span>
              </div>
            </div>

            {/* Top P */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-slate-300">
                  {parameters.top_p.description}
                </label>
                <span className="text-sm font-mono text-indigo-400">
                  {formatValue(values.top_p, parameters.top_p.step)}
                </span>
              </div>
              <input
                type="range"
                min={parameters.top_p.min}
                max={parameters.top_p.max}
                step={parameters.top_p.step || 0.05}
                value={values.top_p}
                onChange={(e) => updateValue('top_p', parseFloat(e.target.value))}
                className="w-full h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-indigo-500"
              />
              <div className="flex justify-between text-xs text-slate-500">
                <span>{parameters.top_p.min}</span>
                <span>{parameters.top_p.max}</span>
              </div>
            </div>

            {/* Top K */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-slate-300">
                  {parameters.top_k.description}
                </label>
                <span className="text-sm font-mono text-indigo-400">
                  {formatValue(values.top_k)}
                </span>
              </div>
              <input
                type="range"
                min={parameters.top_k.min}
                max={parameters.top_k.max}
                step={1}
                value={values.top_k}
                onChange={(e) => updateValue('top_k', parseInt(e.target.value))}
                className="w-full h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-indigo-500"
              />
              <div className="flex justify-between text-xs text-slate-500">
                <span>{parameters.top_k.min}</span>
                <span>{parameters.top_k.max}</span>
              </div>
            </div>

            {/* Repeat Penalty */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-slate-300">
                  {parameters.repeat_penalty.description}
                </label>
                <span className="text-sm font-mono text-indigo-400">
                  {formatValue(values.repeat_penalty, parameters.repeat_penalty.step)}
                </span>
              </div>
              <input
                type="range"
                min={parameters.repeat_penalty.min}
                max={parameters.repeat_penalty.max}
                step={parameters.repeat_penalty.step || 0.1}
                value={values.repeat_penalty}
                onChange={(e) => updateValue('repeat_penalty', parseFloat(e.target.value))}
                className="w-full h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-indigo-500"
              />
              <div className="flex justify-between text-xs text-slate-500">
                <span>No penalty</span>
                <span>Strong penalty</span>
              </div>
            </div>

            {/* Seed */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-slate-300">
                  {parameters.seed.description}
                </label>
                <input
                  type="number"
                  min={parameters.seed.min}
                  max={parameters.seed.max}
                  value={values.seed}
                  onChange={(e) => updateValue('seed', parseInt(e.target.value) || -1)}
                  className="w-32 px-2 py-1 bg-slate-900 border border-slate-700 rounded text-sm font-mono text-indigo-400 focus:outline-none focus:border-indigo-500"
                />
              </div>
              <p className="text-xs text-slate-500">Use -1 for random seed each generation</p>
            </div>
          </div>
        ) : null}

        {/* Actions */}
        <div className="mt-6 pt-4 border-t border-slate-700 flex gap-3">
          <button
            onClick={handleReset}
            disabled={loading || saving}
            className="flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:bg-slate-700/50 transition-all disabled:opacity-50"
          >
            <RotateCcw className="w-4 h-4" />
            Reset
          </button>
          <button
            onClick={onClose}
            disabled={saving}
            className="flex-1 px-4 py-2 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:bg-slate-700/50 transition-all disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={loading || saving}
            className={cn(
              'flex-1 flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-all',
              loading || saving
                ? 'bg-slate-700 text-slate-400 cursor-not-allowed'
                : 'bg-indigo-500 hover:bg-indigo-400 text-white'
            )}
          >
            {saving ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                Saving...
              </>
            ) : (
              <>
                <Save className="w-4 h-4" />
                Save
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}
