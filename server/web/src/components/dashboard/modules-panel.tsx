'use client';

import { useState, useEffect, useCallback } from 'react';
import { Brain, Check, X, Users, Timer, Trophy, RefreshCw, AlertTriangle } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';

interface ModuleFeatures {
  supports_team_mode: boolean;
  supports_speed_training: boolean;
  supports_competition_sim: boolean;
}

interface FeatureOverrides {
  team_mode?: boolean;
  speed_training?: boolean;
  competition_sim?: boolean;
}

interface Module {
  id: string;
  name: string;
  description: string;
  icon_name: string;
  theme_color_hex: string;
  version: string;
  enabled: boolean;
  // Base capabilities (what the module supports)
  base_supports_team_mode: boolean;
  base_supports_speed_training: boolean;
  base_supports_competition_sim: boolean;
  // Effective flags (base AND overrides)
  supports_team_mode: boolean;
  supports_speed_training: boolean;
  supports_competition_sim: boolean;
  // Current overrides
  feature_overrides: FeatureOverrides;
  download_size?: number;
}

interface ModulesResponse {
  modules: Module[];
  server_version: string;
}

interface ModuleSettingsResponse {
  success: boolean;
  module_id: string;
  enabled: boolean;
  feature_overrides: FeatureOverrides;
  effective_features: ModuleFeatures;
}

// API functions
async function getModules(includeDisabled = true): Promise<ModulesResponse> {
  const response = await fetch(`/api/modules?include_disabled=${includeDisabled}`);
  if (!response.ok) {
    throw new Error('Failed to fetch modules');
  }
  return response.json();
}

async function getModuleDetails(moduleId: string): Promise<Module> {
  const response = await fetch(`/api/modules/${moduleId}`);
  if (!response.ok) {
    throw new Error('Failed to fetch module details');
  }
  return response.json();
}

async function updateModuleSettings(
  moduleId: string,
  settings: { enabled?: boolean; feature_overrides?: FeatureOverrides }
): Promise<ModuleSettingsResponse> {
  const response = await fetch(`/api/modules/${moduleId}/settings`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(settings),
  });
  if (!response.ok) {
    throw new Error('Failed to update module settings');
  }
  return response.json();
}

export function ModulesPanel() {
  const [modules, setModules] = useState<Module[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [updating, setUpdating] = useState<string | null>(null);

  const fetchModules = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await getModules(true);
      // Fetch detailed info for each module to get base flags and overrides
      const detailedModules = await Promise.all(
        data.modules.map(async (m) => {
          try {
            return await getModuleDetails(m.id);
          } catch {
            return m;
          }
        })
      );
      setModules(detailedModules);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load modules');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchModules();
  }, [fetchModules]);

  const handleToggleEnabled = async (module: Module) => {
    setUpdating(module.id);
    try {
      await updateModuleSettings(module.id, { enabled: !module.enabled });
      await fetchModules();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to toggle module');
    } finally {
      setUpdating(null);
    }
  };

  const handleToggleFeature = async (
    module: Module,
    feature: 'team_mode' | 'speed_training' | 'competition_sim'
  ) => {
    setUpdating(module.id);
    try {
      const currentValue = module.feature_overrides[feature] ?? true;
      await updateModuleSettings(module.id, {
        feature_overrides: { [feature]: !currentValue },
      });
      await fetchModules();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to toggle feature');
    } finally {
      setUpdating(null);
    }
  };

  const getFeatureStatus = (
    module: Module,
    feature: 'team_mode' | 'speed_training' | 'competition_sim'
  ): { supported: boolean; enabled: boolean; overridden: boolean } => {
    const baseKey = `base_supports_${feature}` as keyof Module;
    const effectiveKey = `supports_${feature}` as keyof Module;
    const supported = Boolean(module[baseKey]);
    const enabled = Boolean(module[effectiveKey]);
    const overridden = feature in module.feature_overrides;
    return { supported, enabled, overridden };
  };

  const formatBytes = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  if (loading) {
    return (
      <Card className="bg-slate-800/50 border-slate-700/50">
        <CardContent className="py-8">
          <div className="flex items-center justify-center gap-2 text-slate-400">
            <RefreshCw className="w-5 h-5 animate-spin" />
            <span>Loading modules...</span>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="bg-slate-800/50 border-slate-700/50">
        <CardContent className="py-8">
          <div className="flex items-center justify-center gap-2 text-red-400">
            <AlertTriangle className="w-5 h-5" />
            <span>{error}</span>
            <button
              onClick={fetchModules}
              className="ml-4 px-3 py-1 bg-slate-700 rounded text-sm hover:bg-slate-600"
            >
              Retry
            </button>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <Card className="bg-slate-800/50 border-slate-700/50">
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-lg font-semibold text-slate-200 flex items-center gap-2">
            <Brain className="w-5 h-5 text-purple-400" />
            Training Modules
          </CardTitle>
          <button
            onClick={fetchModules}
            disabled={loading}
            className="p-2 rounded-md bg-slate-700/50 hover:bg-slate-600/50 transition-colors"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-slate-400">
            Manage specialized training modules available to clients. Enable or disable modules, and
            control feature availability for privacy and compliance requirements.
          </p>
        </CardContent>
      </Card>

      {/* Modules List */}
      <div className="grid grid-cols-1 gap-4">
        {modules.map((module) => (
          <Card
            key={module.id}
            className={`bg-slate-800/50 border-slate-700/50 transition-all ${
              !module.enabled ? 'opacity-60' : ''
            }`}
          >
            <CardContent className="p-6">
              <div className="flex items-start justify-between gap-4">
                {/* Module Info */}
                <div className="flex-1">
                  <div className="flex items-center gap-3 mb-2">
                    <div
                      className="w-10 h-10 rounded-lg flex items-center justify-center"
                      style={{ backgroundColor: `${module.theme_color_hex}20` }}
                    >
                      <Brain className="w-5 h-5" style={{ color: module.theme_color_hex }} />
                    </div>
                    <div>
                      <h3 className="text-lg font-semibold text-slate-200">{module.name}</h3>
                      <div className="flex items-center gap-2 text-xs text-slate-500">
                        <span>v{module.version}</span>
                        {module.download_size && (
                          <>
                            <span>•</span>
                            <span>{formatBytes(module.download_size)}</span>
                          </>
                        )}
                      </div>
                    </div>
                  </div>
                  <p className="text-sm text-slate-400 mb-4">{module.description}</p>

                  {/* Feature Toggles */}
                  <div className="space-y-3">
                    <h4 className="text-xs font-medium text-slate-500 uppercase tracking-wider">
                      Feature Controls
                    </h4>
                    <div className="flex flex-wrap gap-2">
                      {/* Team Mode */}
                      <FeatureToggle
                        label="Team Mode"
                        icon={Users}
                        status={getFeatureStatus(module, 'team_mode')}
                        disabled={updating === module.id || !module.enabled}
                        onToggle={() => handleToggleFeature(module, 'team_mode')}
                        tooltip="Allow multi-device team collaboration"
                      />

                      {/* Speed Training */}
                      <FeatureToggle
                        label="Speed Training"
                        icon={Timer}
                        status={getFeatureStatus(module, 'speed_training')}
                        disabled={updating === module.id || !module.enabled}
                        onToggle={() => handleToggleFeature(module, 'speed_training')}
                        tooltip="Timed practice drills"
                      />

                      {/* Competition Sim */}
                      <FeatureToggle
                        label="Competition Sim"
                        icon={Trophy}
                        status={getFeatureStatus(module, 'competition_sim')}
                        disabled={updating === module.id || !module.enabled}
                        onToggle={() => handleToggleFeature(module, 'competition_sim')}
                        tooltip="Full competition simulation with AI opponents"
                      />
                    </div>
                  </div>
                </div>

                {/* Enable/Disable Toggle */}
                <div className="flex flex-col items-end gap-2">
                  <button
                    onClick={() => handleToggleEnabled(module)}
                    disabled={updating === module.id}
                    className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                      module.enabled ? 'bg-green-500' : 'bg-slate-600'
                    } ${updating === module.id ? 'opacity-50' : ''}`}
                  >
                    <span
                      className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                        module.enabled ? 'translate-x-6' : 'translate-x-1'
                      }`}
                    />
                  </button>
                  <span className="text-xs text-slate-500">
                    {module.enabled ? 'Enabled' : 'Disabled'}
                  </span>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {modules.length === 0 && (
        <Card className="bg-slate-800/50 border-slate-700/50">
          <CardContent className="py-12 text-center text-slate-400">
            <Brain className="w-12 h-12 mx-auto mb-4 opacity-50" />
            <p>No modules configured.</p>
            <p className="text-sm mt-2">
              Modules will appear here once they are added to the server.
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

// Feature Toggle Component
interface FeatureToggleProps {
  label: string;
  icon: typeof Users;
  status: { supported: boolean; enabled: boolean; overridden: boolean };
  disabled: boolean;
  onToggle: () => void;
  tooltip: string;
}

function FeatureToggle({
  label,
  icon: Icon,
  status,
  disabled,
  onToggle,
  tooltip,
}: FeatureToggleProps) {
  if (!status.supported) {
    return (
      <div className="flex items-center gap-2 px-3 py-1.5 rounded-md bg-slate-700/30 text-slate-500 text-sm">
        <Icon className="w-4 h-4" />
        <span>{label}</span>
        <Badge className="bg-slate-600/50 text-slate-400 text-xs">Not Supported</Badge>
      </div>
    );
  }

  return (
    <button
      onClick={onToggle}
      disabled={disabled}
      title={tooltip}
      className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-sm transition-colors ${
        status.enabled
          ? 'bg-green-500/20 text-green-400 hover:bg-green-500/30'
          : 'bg-red-500/20 text-red-400 hover:bg-red-500/30'
      } ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}
    >
      <Icon className="w-4 h-4" />
      <span>{label}</span>
      {status.enabled ? <Check className="w-3.5 h-3.5" /> : <X className="w-3.5 h-3.5" />}
      {status.overridden && (
        <Badge className="bg-amber-500/30 text-amber-400 text-xs ml-1">Override</Badge>
      )}
    </button>
  );
}
