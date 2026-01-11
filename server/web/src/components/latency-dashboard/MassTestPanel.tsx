/**
 * UnaMentis - Mass Test Orchestrator Panel
 * =========================================
 *
 * UI for the mass automated testing orchestrator.
 * Enables running hundreds or thousands of test sessions
 * across multiple web client instances in parallel.
 *
 * FEATURES
 * --------
 * - Configure number of parallel web clients
 * - Set total sessions to run
 * - Select provider configurations
 * - Monitor real-time progress
 * - View latency statistics as tests complete
 *
 * API ENDPOINTS USED
 * ------------------
 * - POST /api/test-orchestrator/start - Start mass test
 * - GET /api/test-orchestrator/status/{runId} - Get progress
 * - POST /api/test-orchestrator/stop/{runId} - Stop test
 * - GET /api/test-orchestrator/runs - List mass test runs
 */

'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  Play,
  Square,
  RefreshCw,
  CheckCircle,
  XCircle,
  Clock,
  Globe,
  AlertTriangle,
  Zap,
  Users,
  Timer,
  Activity,
  Cpu,
  HardDrive,
  Thermometer,
  Gauge,
} from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { getLatencyColor } from '@/components/charts';

// ============================================================================
// Types
// ============================================================================

interface SystemResources {
  cpu_percent: number;
  cpu_per_core?: number[];
  memory_total_mb: number;
  memory_used_mb: number;
  memory_available_mb?: number;
  memory_wired_mb: number; // Includes GPU allocations on Apple Silicon
  memory_gpu_mb?: number; // Estimated GPU-specific memory
  thermal_pressure: 'none' | 'nominal' | 'moderate' | 'heavy' | 'critical';
  browser_memory_mb?: number;
  // Aggregated fields (for completed runs)
  peak_cpu_percent?: number;
  peak_memory_mb?: number;
  avg_cpu_percent?: number;
  avg_memory_mb?: number;
  sample_count?: number;
}

interface MassTestRun {
  runId: string;
  status: 'pending' | 'running' | 'completed' | 'stopped' | 'failed';
  sessionsCompleted: number;
  sessionsTotal: number;
  activeClients: number;
  elapsedSeconds: number;
  estimatedRemainingSeconds: number;
  latencyStats: {
    e2e_p50_ms?: number;
    e2e_p95_ms?: number;
    avg_ms?: number;
  };
  errors?: string[];
  systemResources?: SystemResources;
}

interface MassTestConfig {
  webClients: number;
  totalSessions: number;
  turnsPerSession: number;
  providerConfigs: {
    stt: string;
    llm: string;
    llmModel: string;
    tts: string;
    ttsVoice?: string;
  };
  utterances: string[];
}

// ============================================================================
// API Functions
// ============================================================================

const API_BASE = process.env.NEXT_PUBLIC_MANAGEMENT_API_URL || 'http://localhost:8766';

async function startMassTest(config: MassTestConfig): Promise<{ runId: string }> {
  const response = await fetch(`${API_BASE}/api/test-orchestrator/start`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(config),
  });
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to start mass test');
  }
  return response.json();
}

async function getMassTestStatus(runId: string): Promise<MassTestRun> {
  const response = await fetch(`${API_BASE}/api/test-orchestrator/status/${runId}`);
  if (!response.ok) throw new Error('Failed to get status');
  const data = await response.json();
  return {
    runId: data.runId,
    status: data.status,
    sessionsCompleted: data.progress.sessionsCompleted,
    sessionsTotal: data.progress.sessionsTotal,
    activeClients: data.progress.activeClients,
    elapsedSeconds: data.progress.elapsedSeconds,
    estimatedRemainingSeconds: data.progress.estimatedRemainingSeconds,
    latencyStats: data.latencyStats,
    errors: data.errors,
    systemResources: data.systemResources,
  };
}

async function stopMassTest(runId: string): Promise<void> {
  const response = await fetch(`${API_BASE}/api/test-orchestrator/stop/${runId}`, {
    method: 'POST',
  });
  if (!response.ok) throw new Error('Failed to stop test');
}

async function listMassTests(limit = 20): Promise<MassTestRun[]> {
  const response = await fetch(`${API_BASE}/api/test-orchestrator/runs?limit=${limit}`);
  if (!response.ok) throw new Error('Failed to list tests');
  const data = await response.json();
  return data.runs;
}

// ============================================================================
// Utility Functions
// ============================================================================

function formatDuration(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${Math.round(seconds % 60)}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

function getThermalColor(pressure: string): string {
  switch (pressure) {
    case 'none':
    case 'nominal':
      return 'text-emerald-400';
    case 'moderate':
      return 'text-amber-400';
    case 'heavy':
      return 'text-orange-400';
    case 'critical':
      return 'text-red-400';
    default:
      return 'text-slate-400';
  }
}

function getThermalBgColor(pressure: string): string {
  switch (pressure) {
    case 'none':
    case 'nominal':
      return 'bg-emerald-500/20';
    case 'moderate':
      return 'bg-amber-500/20';
    case 'heavy':
      return 'bg-orange-500/20';
    case 'critical':
      return 'bg-red-500/20';
    default:
      return 'bg-slate-500/20';
  }
}

function formatMemory(mb: number): string {
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)} GB`;
  return `${Math.round(mb)} MB`;
}

// ============================================================================
// StatusBadge Component
// ============================================================================

function StatusBadge({ status }: { status: MassTestRun['status'] }) {
  const config = {
    pending: { color: 'bg-slate-500/20 text-slate-400', icon: Clock, label: 'Pending' },
    running: { color: 'bg-blue-500/20 text-blue-400', icon: Play, label: 'Running' },
    completed: {
      color: 'bg-emerald-500/20 text-emerald-400',
      icon: CheckCircle,
      label: 'Completed',
    },
    stopped: { color: 'bg-amber-500/20 text-amber-400', icon: Square, label: 'Stopped' },
    failed: { color: 'bg-red-500/20 text-red-400', icon: XCircle, label: 'Failed' },
  }[status];

  const Icon = config.icon;

  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium',
        config.color
      )}
    >
      <Icon className="w-3 h-3" />
      {config.label}
    </span>
  );
}

// ============================================================================
// Main Component
// ============================================================================

export function MassTestPanel() {
  const [runs, setRuns] = useState<MassTestRun[]>([]);
  const [activeRun, setActiveRun] = useState<MassTestRun | null>(null);
  const [loading, setLoading] = useState(true);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Configuration state
  const [webClients, setWebClients] = useState(4);
  const [totalSessions, setTotalSessions] = useState(100);
  const [turnsPerSession, setTurnsPerSession] = useState(3);
  const [llmProvider, setLlmProvider] = useState('anthropic');
  const [llmModel, setLlmModel] = useState('claude-3-5-haiku-20241022');
  const [ttsProvider, setTtsProvider] = useState('chatterbox');
  const [utterances, setUtterances] = useState(
    'Hello, how are you today?\nCan you explain photosynthesis?\nWhat is the capital of France?\nTell me about ancient history\nHow does electricity work?'
  );

  // Fetch runs
  const fetchRuns = useCallback(async () => {
    try {
      const runsData = await listMassTests();
      setRuns(runsData);

      // Check if there's an active run
      const running = runsData.find((r) => r.status === 'running');
      if (running) {
        setActiveRun(running);
      }
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch data');
    } finally {
      setLoading(false);
    }
  }, []);

  // Poll for updates when there's an active run
  useEffect(() => {
    fetchRuns();
    const interval = setInterval(fetchRuns, 3000);
    return () => clearInterval(interval);
  }, [fetchRuns]);

  // Update active run status
  useEffect(() => {
    if (!activeRun || activeRun.status !== 'running') return;

    const pollStatus = async () => {
      try {
        const status = await getMassTestStatus(activeRun.runId);
        setActiveRun(status);

        if (status.status !== 'running') {
          fetchRuns();
        }
      } catch (err) {
        console.error('Failed to poll status:', err);
      }
    };

    const interval = setInterval(pollStatus, 2000);
    return () => clearInterval(interval);
  }, [activeRun, fetchRuns]);

  // Start a mass test
  const handleStart = async () => {
    setStarting(true);
    setError(null);

    try {
      const config: MassTestConfig = {
        webClients,
        totalSessions,
        turnsPerSession,
        providerConfigs: {
          stt: 'deepgram',
          llm: llmProvider,
          llmModel,
          tts: ttsProvider,
        },
        utterances: utterances.split('\n').filter((u) => u.trim()),
      };

      const result = await startMassTest(config);
      const status = await getMassTestStatus(result.runId);
      setActiveRun(status);
      await fetchRuns();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to start mass test');
    } finally {
      setStarting(false);
    }
  };

  // Stop active test
  const handleStop = async () => {
    if (!activeRun) return;

    try {
      await stopMassTest(activeRun.runId);
      await fetchRuns();
      setActiveRun(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to stop test');
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
      </div>
    );
  }

  const completedRuns = runs.filter((r) => r.status === 'completed');

  return (
    <div className="space-y-6">
      {/* Error Alert */}
      {error && (
        <div className="p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 flex items-center gap-3">
          <AlertTriangle className="w-5 h-5 flex-shrink-0" />
          <span>{error}</span>
          <button
            onClick={() => setError(null)}
            className="ml-auto text-red-300 hover:text-red-200"
          >
            <XCircle className="w-4 h-4" />
          </button>
        </div>
      )}

      {/* Header Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
          <div className="flex items-center gap-2 mb-2">
            <Users className="w-4 h-4 text-blue-400" />
            <span className="text-sm text-slate-400">Web Clients</span>
          </div>
          <div className="text-2xl font-bold text-slate-100">{activeRun?.activeClients || 0}</div>
        </div>
        <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
          <div className="flex items-center gap-2 mb-2">
            <Activity className="w-4 h-4 text-emerald-400" />
            <span className="text-sm text-slate-400">Sessions Done</span>
          </div>
          <div className="text-2xl font-bold text-slate-100">
            {activeRun?.sessionsCompleted || 0}
          </div>
        </div>
        <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
          <div className="flex items-center gap-2 mb-2">
            <Timer className="w-4 h-4 text-orange-400" />
            <span className="text-sm text-slate-400">P50 Latency</span>
          </div>
          <div
            className={cn(
              'text-2xl font-bold',
              activeRun?.latencyStats?.e2e_p50_ms
                ? getLatencyColor(activeRun.latencyStats.e2e_p50_ms)
                : 'text-slate-500'
            )}
          >
            {activeRun?.latencyStats?.e2e_p50_ms
              ? `${Math.round(activeRun.latencyStats.e2e_p50_ms)}ms`
              : '--'}
          </div>
        </div>
        <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
          <div className="flex items-center gap-2 mb-2">
            <CheckCircle className="w-4 h-4 text-violet-400" />
            <span className="text-sm text-slate-400">Completed Runs</span>
          </div>
          <div className="text-2xl font-bold text-slate-100">{completedRuns.length}</div>
        </div>
      </div>

      {/* Active Run Progress */}
      {activeRun && activeRun.status === 'running' && (
        <Card>
          <CardHeader>
            <CardTitle>
              <Activity className="w-5 h-5 text-blue-400 animate-pulse" />
              Mass Test in Progress
            </CardTitle>
            <button
              onClick={handleStop}
              className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-red-400 hover:text-red-300 hover:bg-red-500/10 rounded-lg transition-all"
            >
              <Square className="w-3 h-3" />
              Stop
            </button>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {/* Progress bar */}
              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-400">Progress</span>
                  <span className="text-slate-300">
                    {activeRun.sessionsCompleted} / {activeRun.sessionsTotal} sessions (
                    {Math.round((activeRun.sessionsCompleted / activeRun.sessionsTotal) * 100)}%)
                  </span>
                </div>
                <div className="h-3 bg-slate-700 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-blue-500 rounded-full transition-all duration-300"
                    style={{
                      width: `${(activeRun.sessionsCompleted / activeRun.sessionsTotal) * 100}%`,
                    }}
                  />
                </div>
              </div>

              {/* Stats grid */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 pt-4 border-t border-slate-700/50">
                <div>
                  <div className="text-xs text-slate-500 mb-1">Active Clients</div>
                  <div className="text-lg font-semibold text-slate-100 flex items-center gap-2">
                    <Globe className="w-4 h-4 text-blue-400" />
                    {activeRun.activeClients}
                  </div>
                </div>
                <div>
                  <div className="text-xs text-slate-500 mb-1">Elapsed</div>
                  <div className="text-lg font-semibold text-slate-100">
                    {formatDuration(activeRun.elapsedSeconds)}
                  </div>
                </div>
                <div>
                  <div className="text-xs text-slate-500 mb-1">Est. Remaining</div>
                  <div className="text-lg font-semibold text-slate-100">
                    {activeRun.estimatedRemainingSeconds > 0
                      ? formatDuration(activeRun.estimatedRemainingSeconds)
                      : '--'}
                  </div>
                </div>
                <div>
                  <div className="text-xs text-slate-500 mb-1">Avg Latency</div>
                  <div
                    className={cn(
                      'text-lg font-semibold',
                      activeRun.latencyStats?.avg_ms
                        ? getLatencyColor(activeRun.latencyStats.avg_ms)
                        : 'text-slate-500'
                    )}
                  >
                    {activeRun.latencyStats?.avg_ms
                      ? `${Math.round(activeRun.latencyStats.avg_ms)}ms`
                      : '--'}
                  </div>
                </div>
              </div>

              {/* System Resources */}
              {activeRun.systemResources && (
                <div className="pt-4 border-t border-slate-700/50">
                  <div className="text-xs text-slate-400 mb-3 flex items-center gap-2">
                    <Gauge className="w-3.5 h-3.5" />
                    System Resources (Live)
                  </div>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                    {/* CPU */}
                    <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700/50">
                      <div className="flex items-center gap-2 mb-2">
                        <Cpu className="w-4 h-4 text-cyan-400" />
                        <span className="text-xs text-slate-400">CPU</span>
                      </div>
                      <div className="text-xl font-bold text-slate-100">
                        {activeRun.systemResources.cpu_percent.toFixed(1)}%
                      </div>
                      {activeRun.systemResources.cpu_per_core && (
                        <div className="mt-2 flex gap-0.5">
                          {activeRun.systemResources.cpu_per_core.slice(0, 8).map((core, i) => (
                            <div
                              key={i}
                              className="flex-1 h-1 rounded-full bg-slate-700 overflow-hidden"
                              title={`Core ${i}: ${core.toFixed(0)}%`}
                            >
                              <div
                                className={cn(
                                  'h-full rounded-full',
                                  core > 80
                                    ? 'bg-red-400'
                                    : core > 50
                                      ? 'bg-amber-400'
                                      : 'bg-cyan-400'
                                )}
                                style={{ width: `${Math.min(100, core)}%` }}
                              />
                            </div>
                          ))}
                        </div>
                      )}
                    </div>

                    {/* Memory */}
                    <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700/50">
                      <div className="flex items-center gap-2 mb-2">
                        <HardDrive className="w-4 h-4 text-violet-400" />
                        <span className="text-xs text-slate-400">Memory</span>
                      </div>
                      <div className="text-xl font-bold text-slate-100">
                        {formatMemory(activeRun.systemResources.memory_used_mb)}
                      </div>
                      <div className="text-xs text-slate-500 mt-1">
                        of {formatMemory(activeRun.systemResources.memory_total_mb)}
                      </div>
                      {/* Memory breakdown bar */}
                      <div className="mt-2 h-2 rounded-full bg-slate-700 overflow-hidden flex">
                        <div
                          className="h-full bg-violet-500"
                          title={`Wired/GPU: ${formatMemory(activeRun.systemResources.memory_wired_mb)}`}
                          style={{
                            width: `${(activeRun.systemResources.memory_wired_mb / activeRun.systemResources.memory_total_mb) * 100}%`,
                          }}
                        />
                        <div
                          className="h-full bg-violet-400/50"
                          title={`App: ${formatMemory(activeRun.systemResources.memory_used_mb - activeRun.systemResources.memory_wired_mb)}`}
                          style={{
                            width: `${((activeRun.systemResources.memory_used_mb - activeRun.systemResources.memory_wired_mb) / activeRun.systemResources.memory_total_mb) * 100}%`,
                          }}
                        />
                      </div>
                    </div>

                    {/* Wired/GPU Memory */}
                    <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700/50">
                      <div className="flex items-center gap-2 mb-2">
                        <Gauge className="w-4 h-4 text-amber-400" />
                        <span className="text-xs text-slate-400">Wired/GPU</span>
                      </div>
                      <div className="text-xl font-bold text-slate-100">
                        {formatMemory(activeRun.systemResources.memory_wired_mb)}
                      </div>
                      {activeRun.systemResources.memory_gpu_mb !== undefined && (
                        <div className="text-xs text-slate-500 mt-1">
                          ~{formatMemory(activeRun.systemResources.memory_gpu_mb)} GPU
                        </div>
                      )}
                      {activeRun.systemResources.browser_memory_mb !== undefined && (
                        <div className="text-xs text-slate-500 mt-1">
                          Browsers: {formatMemory(activeRun.systemResources.browser_memory_mb)}
                        </div>
                      )}
                    </div>

                    {/* Thermal */}
                    <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700/50">
                      <div className="flex items-center gap-2 mb-2">
                        <Thermometer className="w-4 h-4 text-rose-400" />
                        <span className="text-xs text-slate-400">Thermal</span>
                      </div>
                      <div
                        className={cn(
                          'inline-flex items-center gap-1.5 px-2 py-1 rounded-full text-sm font-medium capitalize',
                          getThermalBgColor(activeRun.systemResources.thermal_pressure),
                          getThermalColor(activeRun.systemResources.thermal_pressure)
                        )}
                      >
                        {activeRun.systemResources.thermal_pressure}
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* Errors */}
              {activeRun.errors && activeRun.errors.length > 0 && (
                <div className="pt-4 border-t border-slate-700/50">
                  <div className="text-xs text-red-400 mb-2">Recent Errors</div>
                  <div className="space-y-1 max-h-24 overflow-y-auto">
                    {activeRun.errors.slice(-5).map((err, i) => (
                      <div key={i} className="text-xs text-red-300/80 font-mono">
                        {err}
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Configuration & Start */}
      {(!activeRun || activeRun.status !== 'running') && (
        <Card>
          <CardHeader>
            <CardTitle>
              <Zap className="w-5 h-5" />
              Start Mass Test
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-2 gap-6">
              {/* Left column: Basic settings */}
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-2">
                    Parallel Web Clients
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={10}
                    value={webClients}
                    onChange={(e) => setWebClients(parseInt(e.target.value) || 1)}
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                  />
                  <p className="text-xs text-slate-500 mt-1">
                    Number of browser instances to run in parallel
                  </p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-2">
                    Total Sessions
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={10000}
                    value={totalSessions}
                    onChange={(e) => setTotalSessions(parseInt(e.target.value) || 1)}
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                  />
                  <p className="text-xs text-slate-500 mt-1">
                    Total number of test sessions to execute
                  </p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-2">
                    Turns Per Session
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={10}
                    value={turnsPerSession}
                    onChange={(e) => setTurnsPerSession(parseInt(e.target.value) || 1)}
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                  />
                  <p className="text-xs text-slate-500 mt-1">
                    Number of conversation turns per session
                  </p>
                </div>
              </div>

              {/* Right column: Provider settings */}
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-2">
                    LLM Provider
                  </label>
                  <select
                    value={llmProvider}
                    onChange={(e) => setLlmProvider(e.target.value)}
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                  >
                    <option value="anthropic">Anthropic</option>
                    <option value="openai">OpenAI</option>
                    <option value="selfhosted">Self-Hosted</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-2">LLM Model</label>
                  <select
                    value={llmModel}
                    onChange={(e) => setLlmModel(e.target.value)}
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                  >
                    <option value="claude-3-5-haiku-20241022">Claude 3.5 Haiku</option>
                    <option value="claude-3-5-sonnet-20241022">Claude 3.5 Sonnet</option>
                    <option value="gpt-4o-mini">GPT-4o Mini</option>
                    <option value="gpt-4o">GPT-4o</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-2">
                    TTS Provider
                  </label>
                  <select
                    value={ttsProvider}
                    onChange={(e) => setTtsProvider(e.target.value)}
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                  >
                    <option value="chatterbox">Chatterbox</option>
                    <option value="vibevoice">VibeVoice</option>
                    <option value="elevenlabs-flash">ElevenLabs Flash</option>
                    <option value="deepgram">Deepgram</option>
                  </select>
                </div>
              </div>
            </div>

            {/* Utterances */}
            <div className="mt-6">
              <label className="block text-sm font-medium text-slate-400 mb-2">
                Test Utterances (one per line)
              </label>
              <textarea
                value={utterances}
                onChange={(e) => setUtterances(e.target.value)}
                rows={4}
                className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500/50 font-mono text-sm"
              />
            </div>

            {/* Start Button */}
            <div className="mt-6 flex justify-end">
              <button
                onClick={handleStart}
                disabled={starting}
                className={cn(
                  'flex items-center gap-2 px-6 py-3 rounded-lg font-medium transition-all text-lg',
                  starting
                    ? 'bg-slate-700 text-slate-400 cursor-not-allowed'
                    : 'bg-orange-500 hover:bg-orange-600 text-white'
                )}
              >
                {starting ? (
                  <RefreshCw className="w-5 h-5 animate-spin" />
                ) : (
                  <Play className="w-5 h-5" />
                )}
                Start Mass Test
                <span className="text-sm opacity-75">
                  ({totalSessions} sessions, {webClients} clients)
                </span>
              </button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Run History */}
      <Card>
        <CardHeader>
          <CardTitle>
            <Clock className="w-5 h-5" />
            Mass Test History
          </CardTitle>
          <button
            onClick={fetchRuns}
            className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
          >
            <RefreshCw className="w-4 h-4" />
            Refresh
          </button>
        </CardHeader>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-slate-700/50">
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                  Status
                </th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                  Run ID
                </th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                  Sessions
                </th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                  P50 Latency
                </th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                  P95 Latency
                </th>
                <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                  Duration
                </th>
              </tr>
            </thead>
            <tbody>
              {runs.length === 0 ? (
                <tr>
                  <td colSpan={6} className="text-center text-slate-500 py-8">
                    No mass test runs yet
                  </td>
                </tr>
              ) : (
                runs.map((run) => (
                  <tr
                    key={run.runId}
                    className="border-b border-slate-800/50 hover:bg-slate-800/30"
                  >
                    <td className="px-4 py-3">
                      <StatusBadge status={run.status} />
                    </td>
                    <td className="px-4 py-3 text-sm text-slate-300 font-mono">
                      {run.runId.split('_').pop()}
                    </td>
                    <td className="px-4 py-3 text-sm text-slate-300">
                      {run.sessionsCompleted}/{run.sessionsTotal}
                    </td>
                    <td className="px-4 py-3">
                      <span
                        className={cn(
                          'text-sm font-medium',
                          run.latencyStats?.e2e_p50_ms
                            ? getLatencyColor(run.latencyStats.e2e_p50_ms)
                            : 'text-slate-500'
                        )}
                      >
                        {run.latencyStats?.e2e_p50_ms
                          ? `${Math.round(run.latencyStats.e2e_p50_ms)}ms`
                          : '--'}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <span
                        className={cn(
                          'text-sm font-medium',
                          run.latencyStats?.e2e_p95_ms
                            ? getLatencyColor(run.latencyStats.e2e_p95_ms, 1000)
                            : 'text-slate-500'
                        )}
                      >
                        {run.latencyStats?.e2e_p95_ms
                          ? `${Math.round(run.latencyStats.e2e_p95_ms)}ms`
                          : '--'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-slate-400">
                      {formatDuration(run.elapsedSeconds)}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
