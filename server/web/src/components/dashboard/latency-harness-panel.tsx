/**
 * UnaMentis - Latency Test Harness Dashboard Panel
 * =================================================
 *
 * React component for the Operations Console latency testing interface.
 * Part of the Audio Latency Test Harness infrastructure.
 *
 * FEATURES
 * --------
 * - View available test suites and their configuration
 * - Start/stop test runs on connected clients
 * - Monitor real-time progress of running tests
 * - View test history and analysis results
 * - Export results to CSV for external analysis
 *
 * DATA FLOW
 * ---------
 * 1. Panel fetches suites, runs, and clients from management API
 * 2. User selects suite and optionally a target client
 * 3. Panel sends start request to management API
 * 4. Orchestrator assigns work to clients
 * 5. Panel polls for progress updates (5-second interval)
 * 6. Completed runs show analysis button
 *
 * API ENDPOINTS USED
 * ------------------
 * - GET  /api/latency-tests/suites - List available test suites
 * - GET  /api/latency-tests/runs - List test runs
 * - GET  /api/latency-tests/clients - List connected clients
 * - POST /api/latency-tests/runs - Start a new test run
 * - DELETE /api/latency-tests/runs/:id - Cancel a running test
 * - GET  /api/latency-tests/runs/:id/analysis - Get analysis report
 * - GET  /api/latency-tests/runs/:id/export?format=csv - Export results
 *
 * STYLING
 * -------
 * Uses Tailwind CSS with the project's dark theme.
 * Status colors follow project conventions:
 * - Emerald: Success/connected
 * - Blue: Running/active
 * - Amber: Warning/cancelled
 * - Red: Error/failed
 * - Slate: Neutral/pending
 *
 * SEE ALSO
 * --------
 * - server/management/latency_harness_api.py: Backend API handlers
 * - server/web/src/lib/latency-harness/types.ts: Type definitions
 * - docs/LATENCY_TEST_HARNESS_GUIDE.md: Complete usage guide
 */

'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  Timer,
  Play,
  Square,
  RefreshCw,
  CheckCircle,
  XCircle,
  Clock,
  Smartphone,
  Monitor,
  Globe,
  AlertTriangle,
  BarChart3,
  Zap,
  Download,
  Settings,
  LineChart,
  Rocket,
} from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { getLatencyColor } from '@/components/charts';
import {
  LatencyDashboard,
  TestTargetSelector,
  MassTestPanel,
} from '@/components/latency-dashboard';

// ============================================================================
// Type Definitions
// ============================================================================
// These types match the server API response models

/** Test suite definition from the server */
interface TestSuite {
  id: string;
  name: string;
  description: string;
  scenarioCount: number;
  totalTestCount: number;
  networkProfiles: string[];
}

/** Test run status and progress */
interface TestRun {
  id: string;
  suiteName: string;
  suiteId: string;
  startedAt: string;
  completedAt: string | null;
  clientId: string;
  clientType: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  totalConfigurations: number;
  completedConfigurations: number;
  progressPercent: number;
  elapsedTimeSeconds: number;
}

/** Connected test client with capabilities */
interface TestClient {
  clientId: string;
  clientType: string;
  isConnected: boolean;
  isRunningTest: boolean;
  currentConfigId: string | null;
  lastHeartbeat: string;
  capabilities: {
    supportedSTTProviders: string[];
    supportedLLMProviders: string[];
    supportedTTSProviders: string[];
    hasHighPrecisionTiming: boolean;
    hasDeviceMetrics: boolean;
    hasOnDeviceML: boolean;
    maxConcurrentTests: number;
  };
}

/** Summary statistics from analysis report */
interface AnalysisSummary {
  totalConfigurations: number;
  totalTests: number;
  successfulTests: number;
  failedTests: number;
  overallMedianE2EMs: number;
  overallP99E2EMs: number;
  overallMinE2EMs: number;
  overallMaxE2EMs: number;
  medianSTTMs: number | null;
  medianLLMTTFBMs: number;
  medianLLMCompletionMs: number;
  medianTTSTTFBMs: number;
  medianTTSCompletionMs: number;
  testDurationMinutes: number;
}

// ============================================================================
// API Configuration
// ============================================================================

/**
 * Base URL for the management server API.
 * Defaults to localhost:8766 for local development.
 */
const API_BASE = process.env.NEXT_PUBLIC_MANAGEMENT_API_URL || 'http://localhost:8766';

// ============================================================================
// API Functions
// ============================================================================

/** Fetch all available test suites */
async function fetchSuites(): Promise<TestSuite[]> {
  const response = await fetch(`${API_BASE}/api/latency-tests/suites`);
  if (!response.ok) throw new Error('Failed to fetch suites');
  const data = await response.json();
  return data.suites;
}

/** Fetch recent test runs (default: last 20) */
async function fetchRuns(limit = 20): Promise<TestRun[]> {
  const response = await fetch(`${API_BASE}/api/latency-tests/runs?limit=${limit}`);
  if (!response.ok) throw new Error('Failed to fetch runs');
  const data = await response.json();
  return data.runs;
}

/** Fetch all connected test clients */
async function fetchClients(): Promise<TestClient[]> {
  const response = await fetch(`${API_BASE}/api/latency-tests/clients`);
  if (!response.ok) throw new Error('Failed to fetch clients');
  const data = await response.json();
  return data.clients;
}

/**
 * Start a new test run.
 * @param suiteId - ID of the test suite to run
 * @param clientId - Optional specific client to target (any available if omitted)
 */
async function startTestRun(suiteId: string, clientId?: string): Promise<TestRun> {
  const response = await fetch(`${API_BASE}/api/latency-tests/runs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ suiteId, clientId }),
  });
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to start test run');
  }
  return response.json();
}

/** Cancel a running test */
async function cancelTestRun(runId: string): Promise<void> {
  const response = await fetch(`${API_BASE}/api/latency-tests/runs/${runId}`, {
    method: 'DELETE',
  });
  if (!response.ok) throw new Error('Failed to cancel run');
}

/** Fetch analysis report for a completed run */
async function fetchAnalysis(runId: string): Promise<{ summary: AnalysisSummary }> {
  const response = await fetch(`${API_BASE}/api/latency-tests/runs/${runId}/analysis`);
  if (!response.ok) throw new Error('Failed to fetch analysis');
  return response.json();
}

// ============================================================================
// Helper Components
// ============================================================================

/**
 * Status badge component with color-coded icons.
 * Maps run status to appropriate colors and icons.
 */
function StatusBadge({ status }: { status: TestRun['status'] }) {
  const config = {
    pending: { color: 'bg-slate-500/20 text-slate-400', icon: Clock, label: 'Pending' },
    running: { color: 'bg-blue-500/20 text-blue-400', icon: Play, label: 'Running' },
    completed: {
      color: 'bg-emerald-500/20 text-emerald-400',
      icon: CheckCircle,
      label: 'Completed',
    },
    failed: { color: 'bg-red-500/20 text-red-400', icon: XCircle, label: 'Failed' },
    cancelled: { color: 'bg-amber-500/20 text-amber-400', icon: Square, label: 'Cancelled' },
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

// Client type icon
function ClientTypeIcon({ type, className }: { type: string; className?: string }) {
  const Icon =
    {
      ios_simulator: Smartphone,
      ios_device: Smartphone,
      web: Globe,
    }[type] || Monitor;

  return <Icon className={className} />;
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Format duration in human-readable form.
 * Shows seconds for <1min, minutes+seconds for <1hr, hours+minutes otherwise.
 */
function formatDuration(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${Math.round(seconds % 60)}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

/**
 * Format ISO timestamp to local time (HH:MM).
 */
function formatTime(isoString: string): string {
  const date = new Date(isoString);
  return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
}

// ============================================================================
// Main Component
// ============================================================================

/**
 * Latency Harness Dashboard Panel.
 *
 * Provides the complete UI for managing latency tests:
 * - Header stats showing suite/run/client counts
 * - Test suite selection and run initiation
 * - Active run progress monitoring
 * - Test history with analysis access
 * - Connected client list with capabilities
 */
export function LatencyHarnessPanel() {
  const [suites, setSuites] = useState<TestSuite[]>([]);
  const [runs, setRuns] = useState<TestRun[]>([]);
  const [clients, setClients] = useState<TestClient[]>([]);
  const [selectedSuite, setSelectedSuite] = useState<string>('');
  const [selectedTargets, setSelectedTargets] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedRunAnalysis, setSelectedRunAnalysis] = useState<{
    runId: string;
    summary: AnalysisSummary;
  } | null>(null);
  const [view, setView] = useState<'control' | 'analytics' | 'mass-test'>('control');

  // Fetch data
  const fetchData = useCallback(async () => {
    try {
      const [suitesData, runsData, clientsData] = await Promise.all([
        fetchSuites(),
        fetchRuns(),
        fetchClients(),
      ]);
      setSuites(suitesData);
      setRuns(runsData);
      setClients(clientsData);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, [fetchData]);

  // Start a test run
  const handleStartRun = async () => {
    if (!selectedSuite) {
      setError('Please select a test suite');
      return;
    }

    if (selectedTargets.length === 0) {
      setError('Please select at least one test target');
      return;
    }

    setStarting(true);
    setError(null);

    try {
      // Start runs for all selected targets concurrently
      const results = await Promise.allSettled(
        selectedTargets.map((targetId) => startTestRun(selectedSuite, targetId))
      );

      // Check for any failures
      const failures = results.filter(
        (r): r is PromiseRejectedResult => r.status === 'rejected'
      );

      if (failures.length > 0) {
        // Some runs failed, show first error but continue with successful ones
        const firstError = failures[0].reason;
        setError(
          `${failures.length} of ${selectedTargets.length} runs failed: ${firstError instanceof Error ? firstError.message : String(firstError)}`
        );
      }

      await fetchData();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to start test runs');
    } finally {
      setStarting(false);
    }
  };

  // Cancel a run
  const handleCancelRun = async (runId: string) => {
    try {
      await cancelTestRun(runId);
      await fetchData();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to cancel run');
    }
  };

  // View analysis
  const handleViewAnalysis = async (runId: string) => {
    try {
      const data = await fetchAnalysis(runId);
      setSelectedRunAnalysis({ runId, summary: data.summary });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch analysis');
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <RefreshCw className="w-8 h-8 text-slate-400 animate-spin" />
      </div>
    );
  }

  const activeRuns = runs.filter((r) => r.status === 'running');
  const connectedClients = clients.filter((c) => c.isConnected);

  return (
    <div className="space-y-6">
      {/* View Toggle */}
      <div className="flex items-center justify-between">
        <div className="flex gap-2 p-1 bg-slate-800/50 rounded-lg">
          <button
            onClick={() => setView('control')}
            className={cn(
              'flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-md transition-all',
              view === 'control'
                ? 'bg-orange-500 text-white'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-700/50'
            )}
          >
            <Settings className="w-4 h-4" />
            Control
          </button>
          <button
            onClick={() => setView('analytics')}
            className={cn(
              'flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-md transition-all',
              view === 'analytics'
                ? 'bg-orange-500 text-white'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-700/50'
            )}
          >
            <LineChart className="w-4 h-4" />
            Analytics
          </button>
          <button
            onClick={() => setView('mass-test')}
            className={cn(
              'flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-md transition-all',
              view === 'mass-test'
                ? 'bg-orange-500 text-white'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-700/50'
            )}
          >
            <Rocket className="w-4 h-4" />
            Mass Test
          </button>
        </div>
      </div>

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

      {/* Analytics View */}
      {view === 'analytics' && <LatencyDashboard />}

      {/* Mass Test View */}
      {view === 'mass-test' && <MassTestPanel />}

      {/* Control View */}
      {view === 'control' && (
        <>
          {/* Header Stats */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
              <div className="flex items-center gap-2 mb-2">
                <Timer className="w-4 h-4 text-orange-400" />
                <span className="text-sm text-slate-400">Test Suites</span>
              </div>
              <div className="text-2xl font-bold text-slate-100">{suites.length}</div>
            </div>
            <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
              <div className="flex items-center gap-2 mb-2">
                <Play className="w-4 h-4 text-blue-400" />
                <span className="text-sm text-slate-400">Active Runs</span>
              </div>
              <div className="text-2xl font-bold text-slate-100">{activeRuns.length}</div>
            </div>
            <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
              <div className="flex items-center gap-2 mb-2">
                <Smartphone className="w-4 h-4 text-emerald-400" />
                <span className="text-sm text-slate-400">Connected Clients</span>
              </div>
              <div className="text-2xl font-bold text-slate-100">{connectedClients.length}</div>
            </div>
            <div className="p-4 rounded-xl bg-slate-800/50 border border-slate-700/50">
              <div className="flex items-center gap-2 mb-2">
                <CheckCircle className="w-4 h-4 text-violet-400" />
                <span className="text-sm text-slate-400">Completed Runs</span>
              </div>
              <div className="text-2xl font-bold text-slate-100">
                {runs.filter((r) => r.status === 'completed').length}
              </div>
            </div>
          </div>

          {/* Start New Run */}
          <Card>
            <CardHeader>
              <CardTitle>
                <Zap className="w-5 h-5" />
                Start New Test Run
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex flex-wrap gap-4 items-end">
                <div className="flex-1 min-w-[200px]">
                  <label className="block text-sm font-medium text-slate-400 mb-2">
                    Test Suite
                  </label>
                  <select
                    value={selectedSuite}
                    onChange={(e) => setSelectedSuite(e.target.value)}
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                  >
                    <option value="">Select a test suite...</option>
                    {suites.map((suite) => (
                      <option key={suite.id} value={suite.id}>
                        {suite.name} ({suite.totalTestCount} tests)
                      </option>
                    ))}
                  </select>
                </div>
                <div className="flex-1 min-w-[250px]">
                  <TestTargetSelector
                    selectedTargets={selectedTargets}
                    onSelectionChange={setSelectedTargets}
                    multiSelect={false}
                    label="Test Target"
                    apiBase={API_BASE}
                  />
                </div>
                <button
                  onClick={handleStartRun}
                  disabled={!selectedSuite || selectedTargets.length === 0 || starting}
                  className={cn(
                    'flex items-center gap-2 px-6 py-2 rounded-lg font-medium transition-all',
                    selectedSuite && selectedTargets.length > 0 && !starting
                      ? 'bg-orange-500 hover:bg-orange-600 text-white'
                      : 'bg-slate-700 text-slate-400 cursor-not-allowed'
                  )}
                >
                  {starting ? (
                    <RefreshCw className="w-4 h-4 animate-spin" />
                  ) : (
                    <Play className="w-4 h-4" />
                  )}
                  Start Run
                </button>
              </div>
            </CardContent>
          </Card>

          {/* Active Runs */}
          {activeRuns.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle>
                  <Play className="w-5 h-5 text-blue-400" />
                  Active Test Runs
                </CardTitle>
              </CardHeader>
              <div className="divide-y divide-slate-700/50">
                {activeRuns.map((run) => (
                  <div key={run.id} className="p-4">
                    <div className="flex items-center justify-between mb-3">
                      <div className="flex items-center gap-3">
                        <StatusBadge status={run.status} />
                        <span className="font-medium text-slate-100">{run.suiteName}</span>
                        <span className="text-sm text-slate-400">on {run.clientId}</span>
                      </div>
                      <button
                        onClick={() => handleCancelRun(run.id)}
                        className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-red-400 hover:text-red-300 hover:bg-red-500/10 rounded-lg transition-all"
                      >
                        <Square className="w-3 h-3" />
                        Cancel
                      </button>
                    </div>
                    <div className="space-y-2">
                      <div className="flex items-center justify-between text-sm">
                        <span className="text-slate-400">Progress</span>
                        <span className="text-slate-300">
                          {run.completedConfigurations} / {run.totalConfigurations} (
                          {Math.round(run.progressPercent)}%)
                        </span>
                      </div>
                      <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-blue-500 rounded-full transition-all duration-300"
                          style={{ width: `${run.progressPercent}%` }}
                        />
                      </div>
                      <div className="flex items-center justify-between text-xs text-slate-500">
                        <span>Started {formatTime(run.startedAt)}</span>
                        <span>Elapsed: {formatDuration(run.elapsedTimeSeconds)}</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          )}

          {/* Test Run History */}
          <Card>
            <CardHeader>
              <CardTitle>
                <Clock className="w-5 h-5" />
                Test Run History
              </CardTitle>
              <button
                onClick={fetchData}
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
                      Suite
                    </th>
                    <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                      Client
                    </th>
                    <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                      Progress
                    </th>
                    <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                      Started
                    </th>
                    <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                      Duration
                    </th>
                    <th className="text-left text-xs font-medium text-slate-400 uppercase tracking-wider px-4 py-3">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {runs.length === 0 ? (
                    <tr>
                      <td colSpan={7} className="text-center text-slate-500 py-8">
                        No test runs yet
                      </td>
                    </tr>
                  ) : (
                    runs.map((run) => (
                      <tr
                        key={run.id}
                        className="border-b border-slate-800/50 hover:bg-slate-800/30"
                      >
                        <td className="px-4 py-3">
                          <StatusBadge status={run.status} />
                        </td>
                        <td className="px-4 py-3 text-sm text-slate-300">{run.suiteName}</td>
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-2 text-sm text-slate-300">
                            <ClientTypeIcon
                              type={run.clientType}
                              className="w-4 h-4 text-slate-400"
                            />
                            <span>{run.clientId}</span>
                          </div>
                        </td>
                        <td className="px-4 py-3 text-sm text-slate-300">
                          {run.completedConfigurations}/{run.totalConfigurations}
                        </td>
                        <td className="px-4 py-3 text-sm text-slate-400">
                          {formatTime(run.startedAt)}
                        </td>
                        <td className="px-4 py-3 text-sm text-slate-400">
                          {formatDuration(run.elapsedTimeSeconds)}
                        </td>
                        <td className="px-4 py-3">
                          {run.status === 'completed' && (
                            <button
                              onClick={() => handleViewAnalysis(run.id)}
                              className="flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium text-emerald-400 hover:text-emerald-300 hover:bg-emerald-500/10 rounded-lg transition-all"
                            >
                              <BarChart3 className="w-3 h-3" />
                              Analysis
                            </button>
                          )}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </Card>

          {/* Analysis Modal */}
          {selectedRunAnalysis && (
            <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
              <div className="bg-slate-900 rounded-2xl border border-slate-700 shadow-2xl max-w-2xl w-full mx-4 max-h-[80vh] overflow-y-auto">
                <div className="p-6 border-b border-slate-700">
                  <div className="flex items-center justify-between">
                    <h2 className="text-xl font-semibold text-slate-100">Test Analysis</h2>
                    <button
                      onClick={() => setSelectedRunAnalysis(null)}
                      className="p-2 text-slate-400 hover:text-slate-200 hover:bg-slate-800 rounded-lg transition-all"
                    >
                      <XCircle className="w-5 h-5" />
                    </button>
                  </div>
                </div>
                <div className="p-6 space-y-6">
                  <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                    <div className="p-4 bg-slate-800/50 rounded-xl">
                      <div className="text-sm text-slate-400 mb-1">Median E2E</div>
                      <div
                        className={cn(
                          'text-2xl font-bold',
                          getLatencyColor(selectedRunAnalysis.summary.overallMedianE2EMs)
                        )}
                      >
                        {Math.round(selectedRunAnalysis.summary.overallMedianE2EMs)}ms
                      </div>
                    </div>
                    <div className="p-4 bg-slate-800/50 rounded-xl">
                      <div className="text-sm text-slate-400 mb-1">P99 E2E</div>
                      <div
                        className={cn(
                          'text-2xl font-bold',
                          getLatencyColor(selectedRunAnalysis.summary.overallP99E2EMs, 1000)
                        )}
                      >
                        {Math.round(selectedRunAnalysis.summary.overallP99E2EMs)}ms
                      </div>
                    </div>
                    <div className="p-4 bg-slate-800/50 rounded-xl">
                      <div className="text-sm text-slate-400 mb-1">Success Rate</div>
                      <div className="text-2xl font-bold text-emerald-400">
                        {Math.round(
                          (selectedRunAnalysis.summary.successfulTests /
                            selectedRunAnalysis.summary.totalTests) *
                            100
                        )}
                        %
                      </div>
                    </div>
                    <div className="p-4 bg-slate-800/50 rounded-xl">
                      <div className="text-sm text-slate-400 mb-1">LLM TTFB</div>
                      <div
                        className={cn(
                          'text-2xl font-bold',
                          getLatencyColor(selectedRunAnalysis.summary.medianLLMTTFBMs, 300)
                        )}
                      >
                        {Math.round(selectedRunAnalysis.summary.medianLLMTTFBMs)}ms
                      </div>
                    </div>
                    <div className="p-4 bg-slate-800/50 rounded-xl">
                      <div className="text-sm text-slate-400 mb-1">TTS TTFB</div>
                      <div
                        className={cn(
                          'text-2xl font-bold',
                          getLatencyColor(selectedRunAnalysis.summary.medianTTSTTFBMs, 200)
                        )}
                      >
                        {Math.round(selectedRunAnalysis.summary.medianTTSTTFBMs)}ms
                      </div>
                    </div>
                    <div className="p-4 bg-slate-800/50 rounded-xl">
                      <div className="text-sm text-slate-400 mb-1">Total Tests</div>
                      <div className="text-2xl font-bold text-slate-100">
                        {selectedRunAnalysis.summary.totalTests}
                      </div>
                    </div>
                  </div>
                  <div className="flex justify-end gap-3">
                    <button
                      onClick={() => setSelectedRunAnalysis(null)}
                      className="px-4 py-2 text-sm font-medium text-slate-300 hover:text-slate-100 hover:bg-slate-800 rounded-lg transition-all"
                    >
                      Close
                    </button>
                    <button
                      onClick={() =>
                        window.open(
                          `${API_BASE}/api/latency-tests/runs/${selectedRunAnalysis.runId}/export?format=csv`,
                          '_blank'
                        )
                      }
                      className="flex items-center gap-2 px-4 py-2 text-sm font-medium bg-orange-500 hover:bg-orange-600 text-white rounded-lg transition-all"
                    >
                      <Download className="w-4 h-4" />
                      Export CSV
                    </button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Connected Clients */}
          <Card>
            <CardHeader>
              <CardTitle>
                <Smartphone className="w-5 h-5" />
                Test Clients
              </CardTitle>
            </CardHeader>
            <div className="p-4">
              {clients.length === 0 ? (
                <div className="text-center text-slate-500 py-8">
                  <Smartphone className="w-12 h-12 mx-auto mb-3 opacity-50" />
                  <p>No test clients connected</p>
                  <p className="text-sm mt-1">
                    Start an iOS Simulator or Web client to begin testing
                  </p>
                </div>
              ) : (
                <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {clients.map((client) => (
                    <div
                      key={client.clientId}
                      className={cn(
                        'p-4 rounded-xl border transition-all',
                        client.isConnected
                          ? 'bg-slate-800/50 border-slate-700/50'
                          : 'bg-slate-900/50 border-slate-800/50 opacity-60'
                      )}
                    >
                      <div className="flex items-center gap-3 mb-3">
                        <ClientTypeIcon
                          type={client.clientType}
                          className={cn(
                            'w-8 h-8',
                            client.isConnected ? 'text-emerald-400' : 'text-slate-500'
                          )}
                        />
                        <div>
                          <div className="font-medium text-slate-100">{client.clientId}</div>
                          <div className="text-xs text-slate-400">
                            {client.clientType.replace('_', ' ')}
                          </div>
                        </div>
                        {client.isConnected ? (
                          <span className="ml-auto px-2 py-0.5 text-xs font-medium bg-emerald-500/20 text-emerald-400 rounded-full">
                            Connected
                          </span>
                        ) : (
                          <span className="ml-auto px-2 py-0.5 text-xs font-medium bg-slate-600/20 text-slate-500 rounded-full">
                            Offline
                          </span>
                        )}
                      </div>
                      {client.isRunningTest && (
                        <div className="flex items-center gap-2 text-sm text-blue-400 mt-2">
                          <RefreshCw className="w-3 h-3 animate-spin" />
                          Running test: {client.currentConfigId}
                        </div>
                      )}
                      <div className="mt-3 pt-3 border-t border-slate-700/50">
                        <div className="text-xs text-slate-500 mb-1">Capabilities</div>
                        <div className="flex flex-wrap gap-1.5">
                          {client.capabilities.hasHighPrecisionTiming && (
                            <span className="px-1.5 py-0.5 text-xs bg-violet-500/20 text-violet-400 rounded">
                              High-precision
                            </span>
                          )}
                          {client.capabilities.hasOnDeviceML && (
                            <span className="px-1.5 py-0.5 text-xs bg-amber-500/20 text-amber-400 rounded">
                              On-device ML
                            </span>
                          )}
                          {client.capabilities.hasDeviceMetrics && (
                            <span className="px-1.5 py-0.5 text-xs bg-blue-500/20 text-blue-400 rounded">
                              Device metrics
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </Card>
        </>
      )}
    </div>
  );
}
