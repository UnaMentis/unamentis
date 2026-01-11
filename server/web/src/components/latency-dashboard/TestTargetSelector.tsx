/**
 * Test Target Selector Component
 * ===============================
 *
 * A comprehensive selector for choosing test targets (simulators, devices, clients).
 * Supports single and multi-select modes with grouped display.
 */

'use client';

import { useState, useEffect, useMemo } from 'react';
import {
  Smartphone,
  Tablet,
  Monitor,
  Globe,
  Wifi,
  WifiOff,
  ChevronDown,
  ChevronRight,
  Check,
  Cpu,
  RefreshCw,
} from 'lucide-react';
import { cn } from '@/lib/utils';

// ============================================================================
// Types
// ============================================================================

export interface TestTarget {
  id: string;
  name: string;
  type: 'ios_simulator' | 'ios_device' | 'android_simulator' | 'android_device' | 'web';
  platform: string;
  model: string | null;
  udid: string | null;
  status: 'available' | 'booted' | 'connected' | 'offline';
  isConnected: boolean;
  isRunningTest?: boolean;
  deviceCategory?: 'iphone' | 'ipad' | 'other';
  capabilities?: {
    supportedSTTProviders: string[];
    supportedLLMProviders: string[];
    supportedTTSProviders: string[];
    hasHighPrecisionTiming: boolean;
    hasDeviceMetrics: boolean;
    hasOnDeviceML: boolean;
    maxConcurrentTests: number;
  } | null;
}

export interface TestTargetCategories {
  ios_simulators: TestTarget[];
  ios_devices: TestTarget[];
  android_simulators: TestTarget[];
  android_devices: TestTarget[];
  connected_clients: TestTarget[];
}

interface TestTargetSelectorProps {
  /** Currently selected target IDs */
  selectedTargets: string[];
  /** Callback when selection changes */
  onSelectionChange: (targetIds: string[]) => void;
  /** Enable multi-select mode */
  multiSelect?: boolean;
  /** Maximum selections in multi-select mode */
  maxSelections?: number;
  /** API base URL */
  apiBase?: string;
  /** Label text */
  label?: string;
  /** Show loading state */
  loading?: boolean;
}

// ============================================================================
// Helper Components
// ============================================================================

function TargetIcon({ target, className }: { target: TestTarget; className?: string }) {
  if (target.type === 'ios_simulator' || target.type === 'ios_device') {
    if (target.deviceCategory === 'ipad' || target.name.toLowerCase().includes('ipad')) {
      return <Tablet className={className} />;
    }
    return <Smartphone className={className} />;
  }
  if (target.type === 'android_simulator' || target.type === 'android_device') {
    return <Smartphone className={className} />;
  }
  if (target.type === 'web') {
    return <Globe className={className} />;
  }
  return <Monitor className={className} />;
}

function StatusIndicator({ status }: { status: TestTarget['status'] }) {
  const config = {
    available: { color: 'bg-slate-400', label: 'Available' },
    booted: { color: 'bg-emerald-400', label: 'Booted' },
    connected: { color: 'bg-emerald-400', label: 'Connected' },
    offline: { color: 'bg-red-400', label: 'Offline' },
  }[status];

  return (
    <span className="flex items-center gap-1.5">
      <span className={cn('w-2 h-2 rounded-full', config.color)} />
      <span className="text-xs text-slate-500">{config.label}</span>
    </span>
  );
}

// ============================================================================
// Main Component
// ============================================================================

export function TestTargetSelector({
  selectedTargets,
  onSelectionChange,
  multiSelect = false,
  maxSelections = 5,
  apiBase = 'http://localhost:8766',
  label = 'Test Target',
  loading: externalLoading = false,
}: TestTargetSelectorProps) {
  const [targets, setTargets] = useState<TestTarget[]>([]);
  const [categories, setCategories] = useState<TestTargetCategories | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isOpen, setIsOpen] = useState(false);
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(
    new Set(['ios_simulators', 'ios_devices', 'connected_clients'])
  );

  // Fetch targets from API
  useEffect(() => {
    async function fetchTargets() {
      try {
        setLoading(true);
        const response = await fetch(`${apiBase}/api/latency-tests/targets`);
        if (!response.ok) throw new Error('Failed to fetch targets');
        const data = await response.json();
        setTargets(data.targets || []);
        setCategories(data.categories || null);
        setError(null);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to fetch targets');
      } finally {
        setLoading(false);
      }
    }

    fetchTargets();
    // Refresh every 10 seconds to detect new devices
    const interval = setInterval(fetchTargets, 10000);
    return () => clearInterval(interval);
  }, [apiBase]);

  // Group targets for display
  const groupedTargets = useMemo(() => {
    if (!categories) return [];

    const groups: { key: string; label: string; icon: React.ReactNode; targets: TestTarget[] }[] =
      [];

    if (categories.ios_devices.length > 0) {
      groups.push({
        key: 'ios_devices',
        label: 'Physical iOS Devices',
        icon: <Smartphone className="w-4 h-4 text-emerald-400" />,
        targets: categories.ios_devices,
      });
    }

    if (categories.connected_clients.length > 0) {
      groups.push({
        key: 'connected_clients',
        label: 'Connected Clients',
        icon: <Wifi className="w-4 h-4 text-blue-400" />,
        targets: categories.connected_clients,
      });
    }

    if (categories.ios_simulators.length > 0) {
      // Group simulators by platform version
      const byPlatform = new Map<string, TestTarget[]>();
      for (const sim of categories.ios_simulators) {
        const platform = sim.platform || 'iOS';
        if (!byPlatform.has(platform)) {
          byPlatform.set(platform, []);
        }
        byPlatform.get(platform)!.push(sim);
      }

      // Sort platforms (newest first)
      const sortedPlatforms = Array.from(byPlatform.keys()).sort().reverse();

      for (const platform of sortedPlatforms) {
        const sims = byPlatform.get(platform)!;
        // Separate iPhones and iPads
        const iphones = sims.filter(
          (s) => s.deviceCategory === 'iphone' || s.name.toLowerCase().includes('iphone')
        );
        const ipads = sims.filter(
          (s) => s.deviceCategory === 'ipad' || s.name.toLowerCase().includes('ipad')
        );

        if (iphones.length > 0) {
          groups.push({
            key: `sims_iphone_${platform}`,
            label: `iPhone Simulators (${platform})`,
            icon: <Smartphone className="w-4 h-4 text-violet-400" />,
            targets: iphones,
          });
        }

        if (ipads.length > 0) {
          groups.push({
            key: `sims_ipad_${platform}`,
            label: `iPad Simulators (${platform})`,
            icon: <Tablet className="w-4 h-4 text-violet-400" />,
            targets: ipads,
          });
        }
      }
    }

    return groups;
  }, [categories]);

  const toggleGroup = (key: string) => {
    setExpandedGroups((prev) => {
      const next = new Set(prev);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  };

  const handleSelect = (targetId: string) => {
    if (multiSelect) {
      if (selectedTargets.includes(targetId)) {
        onSelectionChange(selectedTargets.filter((id) => id !== targetId));
      } else if (selectedTargets.length < maxSelections) {
        onSelectionChange([...selectedTargets, targetId]);
      }
    } else {
      onSelectionChange([targetId]);
      setIsOpen(false);
    }
  };

  const selectedTarget = targets.find((t) => t.id === selectedTargets[0]);

  const isLoading = loading || externalLoading;

  if (isLoading && targets.length === 0) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-slate-400">{label}</label>
        <div className="flex items-center gap-2 px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-400">
          <RefreshCw className="w-4 h-4 animate-spin" />
          <span>Loading targets...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-slate-400">{label}</label>
        <div className="px-3 py-2 bg-red-500/10 border border-red-500/30 rounded-lg text-red-400 text-sm">
          {error}
        </div>
      </div>
    );
  }

  if (targets.length === 0) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-slate-400">{label}</label>
        <div className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-500 text-sm">
          No test targets available. Start an iOS Simulator or connect a device.
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <label className="block text-sm font-medium text-slate-400">{label}</label>

      {/* Selected Target Display / Trigger */}
      <div className={cn('relative', isOpen && 'z-50')}>
        <button
          type="button"
          onClick={() => setIsOpen(!isOpen)}
          className={cn(
            'w-full flex items-center gap-3 px-3 py-2 bg-slate-800 border rounded-lg text-left transition-all',
            isOpen ? 'border-orange-500/50 ring-2 ring-orange-500/20' : 'border-slate-700',
            'hover:border-slate-600 focus:outline-none'
          )}
        >
          {selectedTarget ? (
            <>
              <TargetIcon target={selectedTarget} className="w-5 h-5 text-slate-400" />
              <div className="flex-1 min-w-0">
                <div className="text-sm font-medium text-slate-100 truncate">
                  {selectedTarget.name}
                </div>
                <div className="text-xs text-slate-500">{selectedTarget.platform}</div>
              </div>
              <StatusIndicator status={selectedTarget.status} />
            </>
          ) : multiSelect && selectedTargets.length > 0 ? (
            <span className="text-sm text-slate-300">
              {selectedTargets.length} target{selectedTargets.length !== 1 ? 's' : ''} selected
            </span>
          ) : (
            <span className="text-sm text-slate-500">Select a test target...</span>
          )}
          <ChevronDown
            className={cn('w-4 h-4 text-slate-400 transition-transform', isOpen && 'rotate-180')}
          />
        </button>

        {/* Dropdown */}
        {isOpen && (
          <div className="absolute z-50 w-full mt-2 bg-slate-900 border border-slate-700 rounded-xl shadow-2xl max-h-[400px] overflow-y-auto">
            {groupedTargets.map((group) => (
              <div key={group.key} className="border-b border-slate-800 last:border-b-0">
                {/* Group Header */}
                <button
                  type="button"
                  onClick={() => toggleGroup(group.key)}
                  className="w-full flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-300 hover:bg-slate-800/50 transition-all"
                >
                  {expandedGroups.has(group.key) ? (
                    <ChevronDown className="w-4 h-4 text-slate-500" />
                  ) : (
                    <ChevronRight className="w-4 h-4 text-slate-500" />
                  )}
                  {group.icon}
                  <span>{group.label}</span>
                  <span className="ml-auto text-xs text-slate-500">{group.targets.length}</span>
                </button>

                {/* Group Items */}
                {expandedGroups.has(group.key) && (
                  <div className="pb-1">
                    {group.targets.map((target) => {
                      const isSelected = selectedTargets.includes(target.id);
                      const isDisabled =
                        !isSelected && multiSelect && selectedTargets.length >= maxSelections;

                      return (
                        <button
                          key={target.id}
                          type="button"
                          onClick={() => !isDisabled && handleSelect(target.id)}
                          disabled={isDisabled}
                          className={cn(
                            'w-full flex items-center gap-3 px-4 py-2 text-left transition-all',
                            isSelected
                              ? 'bg-orange-500/10 border-l-2 border-orange-500'
                              : 'hover:bg-slate-800/50 border-l-2 border-transparent',
                            isDisabled && 'opacity-50 cursor-not-allowed'
                          )}
                        >
                          {multiSelect && (
                            <div
                              className={cn(
                                'w-4 h-4 rounded border flex items-center justify-center',
                                isSelected ? 'bg-orange-500 border-orange-500' : 'border-slate-600'
                              )}
                            >
                              {isSelected && <Check className="w-3 h-3 text-white" />}
                            </div>
                          )}
                          <TargetIcon
                            target={target}
                            className={cn(
                              'w-5 h-5',
                              isSelected ? 'text-orange-400' : 'text-slate-400'
                            )}
                          />
                          <div className="flex-1 min-w-0">
                            <div
                              className={cn(
                                'text-sm font-medium truncate',
                                isSelected ? 'text-orange-100' : 'text-slate-200'
                              )}
                            >
                              {target.name}
                            </div>
                            <div className="flex items-center gap-2 text-xs text-slate-500">
                              <span>{target.platform}</span>
                              {target.status === 'booted' && (
                                <span className="px-1.5 py-0.5 bg-emerald-500/20 text-emerald-400 rounded">
                                  Running
                                </span>
                              )}
                              {target.isRunningTest && (
                                <span className="px-1.5 py-0.5 bg-blue-500/20 text-blue-400 rounded">
                                  Testing
                                </span>
                              )}
                            </div>
                          </div>
                          {!multiSelect && isSelected && (
                            <Check className="w-4 h-4 text-orange-400" />
                          )}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Multi-select hint */}
      {multiSelect && (
        <div className="text-xs text-slate-500">
          Select up to {maxSelections} targets. Selected: {selectedTargets.length}
        </div>
      )}
    </div>
  );
}
