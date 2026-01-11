'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  FlaskConical,
  RefreshCw,
  Cpu,
  Mic,
  Volume2,
  Play,
  Square,
  Loader2,
  HardDrive,
  Download,
  Settings,
  ChevronDown,
  ChevronUp,
  Save,
} from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import type { ModelInfo, ModelConfig } from '@/types';
import {
  getModels,
  loadModel,
  unloadModel,
  getModelConfig,
  saveModelConfig,
} from '@/lib/api-client';
import { cn } from '@/lib/utils';
import { ModelPullDialog } from './model-pull-dialog';
import { ModelParametersModal } from './model-parameters-modal';

export function ModelsPanel() {
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [counts, setCounts] = useState({ llm: 0, stt: 0, tts: 0 });
  const [loading, setLoading] = useState(true);
  const [operatingModels, setOperatingModels] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const [showPullDialog, setShowPullDialog] = useState(false);
  const [configuringModel, setConfiguringModel] = useState<ModelInfo | null>(null);

  // Service configuration state
  const [showConfig, setShowConfig] = useState(false);
  const [config, setConfig] = useState<ModelConfig | null>(null);
  const [configLoading, setConfigLoading] = useState(false);
  const [configSaving, setConfigSaving] = useState(false);
  const [configError, setConfigError] = useState<string | null>(null);

  const fetchModels = useCallback(async () => {
    try {
      const response = await getModels();
      setModels(response.models);
      setCounts(response.by_type);
      setError(null);
    } catch (err) {
      console.error('Failed to fetch models:', err);
      setError('Failed to fetch models');
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchConfig = useCallback(async () => {
    setConfigLoading(true);
    setConfigError(null);
    try {
      const response = await getModelConfig();
      setConfig(response.config);
    } catch (err) {
      console.error('Failed to fetch model config:', err);
      setConfigError(err instanceof Error ? err.message : 'Failed to load configuration');
    } finally {
      setConfigLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchModels();
    fetchConfig();
    const interval = setInterval(fetchModels, 60000);
    return () => clearInterval(interval);
  }, [fetchModels, fetchConfig]);

  const handleLoadModel = async (model: ModelInfo) => {
    if (operatingModels.has(model.id)) return;

    setOperatingModels((prev) => new Set(prev).add(model.id));
    setError(null);

    try {
      await loadModel(model.id);
      // Refresh model list to get updated status
      await fetchModels();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load model');
    } finally {
      setOperatingModels((prev) => {
        const next = new Set(prev);
        next.delete(model.id);
        return next;
      });
    }
  };

  const handleUnloadModel = async (model: ModelInfo) => {
    if (operatingModels.has(model.id)) return;

    setOperatingModels((prev) => new Set(prev).add(model.id));
    setError(null);

    try {
      await unloadModel(model.id);
      // Refresh model list to get updated status
      await fetchModels();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to unload model');
    } finally {
      setOperatingModels((prev) => {
        const next = new Set(prev);
        next.delete(model.id);
        return next;
      });
    }
  };

  const handleSaveConfig = async () => {
    if (!config) return;
    setConfigSaving(true);
    setConfigError(null);
    try {
      await saveModelConfig(config);
    } catch (err) {
      setConfigError(err instanceof Error ? err.message : 'Failed to save configuration');
    } finally {
      setConfigSaving(false);
    }
  };

  const updateConfig = (service: 'llm' | 'tts' | 'stt', key: string, value: string | null) => {
    if (!config) return;
    setConfig({
      ...config,
      services: {
        ...config.services,
        [service]: {
          ...config.services[service],
          [key]: value,
        },
      },
    });
  };

  // Get available LLM models for the dropdown
  const llmModels = models.filter((m) => m.type === 'llm');

  const typeStyles: Record<string, { icon: typeof Cpu; color: string; bgColor: string }> = {
    llm: { icon: Cpu, color: 'text-violet-400', bgColor: 'bg-violet-500/10 border-violet-500/30' },
    stt: {
      icon: Mic,
      color: 'text-emerald-400',
      bgColor: 'bg-emerald-500/10 border-emerald-500/30',
    },
    tts: { icon: Volume2, color: 'text-blue-400', bgColor: 'bg-blue-500/10 border-blue-500/30' },
  };

  const getStatusBadgeVariant = (status: string): 'success' | 'warning' | 'default' => {
    switch (status) {
      case 'loaded':
        return 'success';
      case 'loading':
        return 'warning';
      default:
        return 'default';
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold">Available Models</h2>
        <div className="flex gap-2">
          <button
            onClick={fetchModels}
            className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
          >
            <RefreshCw className="w-4 h-4" />
            Refresh
          </button>
          <button
            onClick={() => setShowPullDialog(true)}
            className="flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg bg-indigo-500 hover:bg-indigo-400 text-white transition-all"
          >
            <Download className="w-4 h-4" />
            Pull Model
          </button>
        </div>
      </div>

      {/* Pull Model Dialog */}
      {showPullDialog && (
        <ModelPullDialog
          onClose={() => setShowPullDialog(false)}
          onComplete={() => fetchModels()}
        />
      )}

      {/* Parameters Modal */}
      {configuringModel && (
        <ModelParametersModal model={configuringModel} onClose={() => setConfiguringModel(null)} />
      )}

      {/* Error Display */}
      {error && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-lg px-4 py-3 text-red-400 text-sm">
          {error}
        </div>
      )}

      {/* Type Filters */}
      <div className="flex gap-4">
        {(['llm', 'stt', 'tts'] as const).map((type) => {
          const style = typeStyles[type];
          const Icon = style.icon;
          return (
            <div
              key={type}
              className={cn('flex items-center gap-2 px-4 py-2 rounded-lg border', style.bgColor)}
            >
              <Icon className={cn('w-5 h-5', style.color)} />
              <span className="font-medium">{counts[type]}</span>
              <span className="text-slate-400 uppercase text-sm">{type}</span>
            </div>
          );
        })}
      </div>

      {/* Service Configuration */}
      <Card className="border-slate-700/50">
        <button
          onClick={() => setShowConfig(!showConfig)}
          className="w-full px-4 py-3 flex items-center justify-between text-left hover:bg-slate-800/30 transition-colors rounded-lg"
        >
          <div className="flex items-center gap-3">
            <Settings className="w-5 h-5 text-indigo-400" />
            <span className="font-medium text-slate-100">Service Configuration</span>
            <Badge variant="default" className="text-xs">
              {config?.services.llm.default_model ? 'Configured' : 'Default'}
            </Badge>
          </div>
          {showConfig ? (
            <ChevronUp className="w-5 h-5 text-slate-400" />
          ) : (
            <ChevronDown className="w-5 h-5 text-slate-400" />
          )}
        </button>

        {showConfig && (
          <CardContent className="pt-0 pb-4">
            {configError && (
              <div className="mb-4 bg-red-500/10 border border-red-500/30 rounded-lg px-4 py-3 text-red-400 text-sm">
                {configError}
              </div>
            )}

            {configLoading ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-6 h-6 animate-spin text-slate-400" />
              </div>
            ) : config ? (
              <div className="space-y-6">
                {/* LLM Configuration */}
                <div className="space-y-3">
                  <h4 className="text-sm font-medium text-slate-300 flex items-center gap-2">
                    <Cpu className="w-4 h-4 text-violet-400" />
                    LLM Model
                  </h4>
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="block text-xs text-slate-400 mb-1">Default Model</label>
                      <select
                        value={config.services.llm.default_model || ''}
                        onChange={(e) =>
                          updateConfig('llm', 'default_model', e.target.value || null)
                        }
                        className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
                      >
                        <option value="">None (auto-select)</option>
                        {llmModels.map((m) => (
                          <option key={m.id} value={m.name}>
                            {m.name}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div>
                      <label className="block text-xs text-slate-400 mb-1">Fallback Model</label>
                      <select
                        value={config.services.llm.fallback_model || ''}
                        onChange={(e) =>
                          updateConfig('llm', 'fallback_model', e.target.value || null)
                        }
                        className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
                      >
                        <option value="">None</option>
                        {llmModels.map((m) => (
                          <option key={m.id} value={m.name}>
                            {m.name}
                          </option>
                        ))}
                      </select>
                    </div>
                  </div>
                </div>

                {/* TTS Configuration */}
                <div className="space-y-3">
                  <h4 className="text-sm font-medium text-slate-300 flex items-center gap-2">
                    <Volume2 className="w-4 h-4 text-blue-400" />
                    TTS (Text-to-Speech)
                  </h4>
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="block text-xs text-slate-400 mb-1">Provider</label>
                      <select
                        value={config.services.tts.default_provider}
                        onChange={(e) =>
                          updateConfig(
                            'tts',
                            'default_provider',
                            e.target.value as 'vibevoice' | 'piper'
                          )
                        }
                        className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
                      >
                        <option value="vibevoice">VibeVoice</option>
                        <option value="piper">Piper</option>
                      </select>
                    </div>
                    <div>
                      <label className="block text-xs text-slate-400 mb-1">Default Voice</label>
                      <input
                        type="text"
                        value={config.services.tts.default_voice}
                        onChange={(e) => updateConfig('tts', 'default_voice', e.target.value)}
                        placeholder="nova"
                        className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
                      />
                    </div>
                  </div>
                </div>

                {/* STT Configuration */}
                <div className="space-y-3">
                  <h4 className="text-sm font-medium text-slate-300 flex items-center gap-2">
                    <Mic className="w-4 h-4 text-emerald-400" />
                    STT (Speech-to-Text)
                  </h4>
                  <div>
                    <label className="block text-xs text-slate-400 mb-1">Default Model</label>
                    <input
                      type="text"
                      value={config.services.stt.default_model}
                      onChange={(e) => updateConfig('stt', 'default_model', e.target.value)}
                      placeholder="whisper"
                      className="w-full max-w-xs px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
                    />
                  </div>
                </div>

                {/* Save Button */}
                <div className="pt-2 border-t border-slate-700/50">
                  <button
                    onClick={handleSaveConfig}
                    disabled={configSaving}
                    className={cn(
                      'flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-all',
                      configSaving
                        ? 'bg-slate-700 text-slate-400 cursor-not-allowed'
                        : 'bg-indigo-500 hover:bg-indigo-400 text-white'
                    )}
                  >
                    {configSaving ? (
                      <>
                        <Loader2 className="w-4 h-4 animate-spin" />
                        Saving...
                      </>
                    ) : (
                      <>
                        <Save className="w-4 h-4" />
                        Save Configuration
                      </>
                    )}
                  </button>
                </div>
              </div>
            ) : null}
          </CardContent>
        )}
      </Card>

      {/* Models Grid */}
      <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
        {loading ? (
          Array.from({ length: 6 }).map((_, i) => (
            <Card key={i}>
              <CardContent className="h-24 flex items-center justify-center">
                <div className="animate-pulse text-slate-500">Loading...</div>
              </CardContent>
            </Card>
          ))
        ) : models.length === 0 ? (
          <div className="col-span-full text-center text-slate-500 py-12">
            <FlaskConical className="w-16 h-16 mx-auto mb-4 opacity-30" />
            <p className="text-lg font-medium">No models available</p>
            <p className="text-sm mt-1">Models will appear when servers are healthy</p>
          </div>
        ) : (
          models.map((model) => {
            const style = typeStyles[model.type] || typeStyles.llm;
            const Icon = style.icon;
            const isOperating = operatingModels.has(model.id);
            const isLoaded = model.status === 'loaded';
            const isLLM = model.type === 'llm';

            return (
              <Card key={model.id} className="hover:border-slate-600/50 transition-all">
                <CardContent className="pt-4">
                  <div className="flex items-start justify-between mb-3">
                    <div className="flex items-center gap-2">
                      <Icon className={cn('w-5 h-5', style.color)} />
                      <h3 className="font-semibold text-slate-100 truncate" title={model.name}>
                        {model.name}
                      </h3>
                    </div>
                    <Badge variant={getStatusBadgeVariant(model.status)}>{model.status}</Badge>
                  </div>

                  <div className="space-y-1 text-sm">
                    <div className="flex justify-between">
                      <span className="text-slate-400">Type</span>
                      <span className="text-slate-200 uppercase">{model.type}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Server</span>
                      <span className="text-slate-200">{model.server_name}</span>
                    </div>
                    {(model.parameter_size || model.parameters) && (
                      <div className="flex justify-between">
                        <span className="text-slate-400">Params</span>
                        <span className="text-slate-200">{model.parameter_size || model.parameters}</span>
                      </div>
                    )}
                    {model.quantization && (
                      <div className="flex justify-between">
                        <span className="text-slate-400">Quant</span>
                        <span className="text-slate-200 font-mono text-xs">
                          {model.quantization}
                        </span>
                      </div>
                    )}
                    {model.context_window_formatted && (
                      <div className="flex justify-between">
                        <span className="text-slate-400">Context</span>
                        <span className="text-indigo-400 font-medium">
                          {model.context_window_formatted}
                        </span>
                      </div>
                    )}
                    {model.size_gb !== undefined && model.size_gb > 0 && (
                      <div className="flex justify-between">
                        <span className="text-slate-400">Size</span>
                        <span className="text-slate-200">{model.size_gb.toFixed(1)} GB</span>
                      </div>
                    )}
                    {isLoaded && model.vram_gb !== undefined && model.vram_gb > 0 && (
                      <div className="flex justify-between items-center">
                        <span className="text-slate-400 flex items-center gap-1">
                          <HardDrive className="w-3 h-3" />
                          VRAM
                        </span>
                        <span className="text-emerald-400 font-medium">
                          {model.vram_gb.toFixed(1)} GB
                        </span>
                      </div>
                    )}
                  </div>

                  {/* Load/Unload and Configure buttons for LLM models */}
                  {isLLM && (
                    <div className="mt-4 pt-3 border-t border-slate-700/50 space-y-2">
                      <div className="flex gap-2">
                        {isLoaded ? (
                          <button
                            onClick={() => handleUnloadModel(model)}
                            disabled={isOperating}
                            className={cn(
                              'flex-1 flex items-center justify-center gap-2 px-3 py-2 text-sm font-medium rounded-lg transition-all',
                              isOperating
                                ? 'bg-slate-700 text-slate-400 cursor-not-allowed'
                                : 'bg-amber-500/20 text-amber-400 hover:bg-amber-500/30 border border-amber-500/30'
                            )}
                          >
                            {isOperating ? (
                              <>
                                <Loader2 className="w-4 h-4 animate-spin" />
                                Unloading...
                              </>
                            ) : (
                              <>
                                <Square className="w-4 h-4" />
                                Unload
                              </>
                            )}
                          </button>
                        ) : (
                          <button
                            onClick={() => handleLoadModel(model)}
                            disabled={isOperating}
                            className={cn(
                              'flex-1 flex items-center justify-center gap-2 px-3 py-2 text-sm font-medium rounded-lg transition-all',
                              isOperating
                                ? 'bg-slate-700 text-slate-400 cursor-not-allowed'
                                : 'bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500/30 border border-emerald-500/30'
                            )}
                          >
                            {isOperating ? (
                              <>
                                <Loader2 className="w-4 h-4 animate-spin" />
                                Loading...
                              </>
                            ) : (
                              <>
                                <Play className="w-4 h-4" />
                                Load
                              </>
                            )}
                          </button>
                        )}
                        <button
                          onClick={() => setConfiguringModel(model)}
                          className="px-3 py-2 text-sm font-medium rounded-lg bg-slate-700/50 text-slate-300 hover:bg-slate-700 border border-slate-600/50 transition-all"
                          title="Configure parameters"
                        >
                          <Settings className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  )}
                </CardContent>
              </Card>
            );
          })
        )}
      </div>
    </div>
  );
}
