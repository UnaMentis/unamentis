'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  RefreshCw,
  XCircle,
  CheckCircle,
  Clock,
  Loader2,
  AlertTriangle,
  AlertCircle,
  Info,
  Search,
  Wrench,
  Eye,
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import type {
  ReprocessJobSummary,
  ReprocessProgress,
  ReprocessStatus,
  CurriculumAnalysis,
  CurriculumSummary,
} from '@/types';

// API functions for reprocessing
async function getReprocessJobs(): Promise<{ success: boolean; jobs: ReprocessJobSummary[] }> {
  const response = await fetch('/api/reprocess/jobs');
  if (!response.ok) {
    throw new Error('Failed to fetch reprocess jobs');
  }
  return response.json();
}

async function getJobProgress(jobId: string): Promise<{ success: boolean; progress: ReprocessProgress }> {
  const response = await fetch(`/api/reprocess/jobs/${jobId}`);
  if (!response.ok) {
    throw new Error('Failed to fetch job progress');
  }
  return response.json();
}

async function cancelReprocessJob(jobId: string): Promise<void> {
  const response = await fetch(`/api/reprocess/jobs/${jobId}`, { method: 'DELETE' });
  if (!response.ok) {
    throw new Error('Failed to cancel reprocess job');
  }
}

async function analyzeCurriculum(curriculumId: string): Promise<{ success: boolean; analysis: CurriculumAnalysis }> {
  const response = await fetch(`/api/reprocess/analyze/${curriculumId}`, { method: 'POST' });
  if (!response.ok) {
    throw new Error('Failed to analyze curriculum');
  }
  return response.json();
}

async function getCurricula(): Promise<{ curricula: CurriculumSummary[] }> {
  const response = await fetch('/api/curricula');
  if (!response.ok) {
    throw new Error('Failed to fetch curricula');
  }
  return response.json();
}

const statusConfig: Record<ReprocessStatus, { icon: typeof Clock; color: string; label: string }> = {
  queued: { icon: Clock, color: 'bg-slate-500/20 text-slate-400 border-slate-500/30', label: 'Queued' },
  loading: { icon: Loader2, color: 'bg-blue-500/20 text-blue-400 border-blue-500/30', label: 'Loading' },
  analyzing: { icon: Search, color: 'bg-violet-500/20 text-violet-400 border-violet-500/30', label: 'Analyzing' },
  fixing_images: { icon: Loader2, color: 'bg-indigo-500/20 text-indigo-400 border-indigo-500/30', label: 'Fixing Images' },
  rechunking: { icon: Loader2, color: 'bg-cyan-500/20 text-cyan-400 border-cyan-500/30', label: 'Re-chunking' },
  generating_objectives: { icon: Loader2, color: 'bg-teal-500/20 text-teal-400 border-teal-500/30', label: 'Generating Objectives' },
  adding_checkpoints: { icon: Loader2, color: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30', label: 'Adding Checkpoints' },
  adding_alternatives: { icon: Loader2, color: 'bg-green-500/20 text-green-400 border-green-500/30', label: 'Adding Alternatives' },
  fixing_metadata: { icon: Loader2, color: 'bg-lime-500/20 text-lime-400 border-lime-500/30', label: 'Fixing Metadata' },
  validating: { icon: Loader2, color: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30', label: 'Validating' },
  storing: { icon: Loader2, color: 'bg-amber-500/20 text-amber-400 border-amber-500/30', label: 'Storing' },
  complete: { icon: CheckCircle, color: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30', label: 'Complete' },
  failed: { icon: XCircle, color: 'bg-red-500/20 text-red-400 border-red-500/30', label: 'Failed' },
  cancelled: { icon: XCircle, color: 'bg-amber-500/20 text-amber-400 border-amber-500/30', label: 'Cancelled' },
};

function formatDuration(startedAt?: string): string {
  if (!startedAt) return '-';
  const start = new Date(startedAt).getTime();
  const durationMs = Date.now() - start;

  const seconds = Math.floor(durationMs / 1000);
  const minutes = Math.floor(seconds / 60);

  if (minutes > 0) {
    return `${minutes}m ${seconds % 60}s`;
  }
  return `${seconds}s`;
}

interface CurriculumWithAnalysis {
  curriculum: CurriculumSummary;
  analysis?: CurriculumAnalysis;
  analyzing?: boolean;
}

interface ReprocessPanelProps {
  onOpenAnalysisModal?: (curriculumId: string, analysis: CurriculumAnalysis) => void;
}

export function ReprocessPanel({ onOpenAnalysisModal }: ReprocessPanelProps) {
  const [jobs, setJobs] = useState<ReprocessJobSummary[]>([]);
  const [curricula, setCurricula] = useState<CurriculumWithAnalysis[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedJob, setSelectedJob] = useState<ReprocessProgress | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [jobsData, curriculaData] = await Promise.all([
        getReprocessJobs(),
        getCurricula(),
      ]);
      setJobs(jobsData.jobs);
      setCurricula(curriculaData.curricula.map(c => ({ curriculum: c })));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();

    // Poll for updates every 5 seconds when there are active jobs
    const interval = setInterval(() => {
      const hasActiveJobs = jobs.some(
        (job) => !['complete', 'failed', 'cancelled'].includes(job.status)
      );
      if (hasActiveJobs) {
        fetchData();
      }
    }, 5000);

    return () => clearInterval(interval);
  }, [fetchData, jobs]);

  const handleAnalyze = async (curriculumId: string) => {
    setCurricula(prev =>
      prev.map(c =>
        c.curriculum.id === curriculumId ? { ...c, analyzing: true } : c
      )
    );

    try {
      const result = await analyzeCurriculum(curriculumId);
      setCurricula(prev =>
        prev.map(c =>
          c.curriculum.id === curriculumId
            ? { ...c, analysis: result.analysis, analyzing: false }
            : c
        )
      );
    } catch (err) {
      setCurricula(prev =>
        prev.map(c =>
          c.curriculum.id === curriculumId ? { ...c, analyzing: false } : c
        )
      );
      setError(err instanceof Error ? err.message : 'Failed to analyze curriculum');
    }
  };

  const handleCancel = async (jobId: string) => {
    if (!confirm('Are you sure you want to cancel this reprocessing job?')) {
      return;
    }
    try {
      await cancelReprocessJob(jobId);
      await fetchData();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to cancel job');
    }
  };

  const handleViewDetails = async (jobId: string) => {
    try {
      const result = await getJobProgress(jobId);
      setSelectedJob(result.progress);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch job details');
    }
  };

  const activeJobs = jobs.filter((j) => !['complete', 'failed', 'cancelled'].includes(j.status));
  const completedJobs = jobs.filter((j) => ['complete', 'failed', 'cancelled'].includes(j.status));

  // Curricula with issues
  const curriculaWithIssues = curricula.filter(c => c.analysis && c.analysis.stats.totalIssues > 0);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-semibold text-white">Curriculum Reprocessing</h2>
          <p className="text-sm text-slate-400 mt-1">
            Analyze and fix quality issues in existing curricula
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={fetchData}
          disabled={loading}
          className="gap-2"
        >
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>

      {error && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4 text-red-400">
          {error}
        </div>
      )}

      {/* Active Jobs */}
      {activeJobs.length > 0 && (
        <Card className="bg-slate-800/50 border-slate-700">
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              <Loader2 className="h-4 w-4 animate-spin text-cyan-400" />
              Active Jobs ({activeJobs.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {activeJobs.map((job) => {
              const config = statusConfig[job.status] || statusConfig.queued;
              const StatusIcon = config.icon;

              return (
                <div
                  key={job.id}
                  className="flex items-center justify-between p-3 rounded-lg bg-slate-900/50 border border-slate-700"
                >
                  <div className="flex items-center gap-3">
                    <StatusIcon className={`h-5 w-5 ${job.status !== 'queued' && job.status !== 'complete' && job.status !== 'failed' && job.status !== 'cancelled' ? 'animate-spin' : ''}`} />
                    <div>
                      <div className="font-medium text-white">{job.curriculumId}</div>
                      <div className="text-sm text-slate-400">{job.currentStage}</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-4">
                    <div className="text-right">
                      <div className="text-sm font-medium text-white">{Math.round(job.overallProgress)}%</div>
                      <div className="text-xs text-slate-400">{formatDuration(job.startedAt)}</div>
                    </div>
                    <div className="w-24 h-2 bg-slate-700 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-cyan-500 transition-all duration-300"
                        style={{ width: `${job.overallProgress}%` }}
                      />
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleViewDetails(job.id)}
                      className="text-slate-400 hover:text-white"
                    >
                      <Eye className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleCancel(job.id)}
                      className="text-red-400 hover:text-red-300"
                    >
                      <XCircle className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}

      {/* Curricula with Issues */}
      <Card className="bg-slate-800/50 border-slate-700">
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 text-amber-400" />
            Curricula Needing Attention
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading && curricula.length === 0 ? (
            <div className="text-center py-8 text-slate-400">
              <Loader2 className="h-6 w-6 animate-spin mx-auto mb-2" />
              Loading curricula...
            </div>
          ) : curricula.length === 0 ? (
            <div className="text-center py-8 text-slate-400">
              No curricula found
            </div>
          ) : (
            <div className="space-y-3">
              {curricula.map(({ curriculum, analysis, analyzing }) => (
                <div
                  key={curriculum.id}
                  className="flex items-center justify-between p-3 rounded-lg bg-slate-900/50 border border-slate-700"
                >
                  <div className="flex-1">
                    <div className="font-medium text-white">{curriculum.title}</div>
                    <div className="text-sm text-slate-400">{curriculum.id}</div>
                  </div>

                  {analysis ? (
                    <div className="flex items-center gap-3">
                      {/* Issue summary badges */}
                      {analysis.stats.criticalCount > 0 && (
                        <Badge variant="outline" className="bg-red-500/20 text-red-400 border-red-500/30 gap-1">
                          <AlertCircle className="h-3 w-3" />
                          {analysis.stats.criticalCount}
                        </Badge>
                      )}
                      {analysis.stats.warningCount > 0 && (
                        <Badge variant="outline" className="bg-amber-500/20 text-amber-400 border-amber-500/30 gap-1">
                          <AlertTriangle className="h-3 w-3" />
                          {analysis.stats.warningCount}
                        </Badge>
                      )}
                      {analysis.stats.infoCount > 0 && (
                        <Badge variant="outline" className="bg-blue-500/20 text-blue-400 border-blue-500/30 gap-1">
                          <Info className="h-3 w-3" />
                          {analysis.stats.infoCount}
                        </Badge>
                      )}
                      {analysis.stats.totalIssues === 0 && (
                        <Badge variant="outline" className="bg-emerald-500/20 text-emerald-400 border-emerald-500/30 gap-1">
                          <CheckCircle className="h-3 w-3" />
                          No issues
                        </Badge>
                      )}
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => onOpenAnalysisModal?.(curriculum.id, analysis)}
                        className="gap-1"
                      >
                        <Eye className="h-3 w-3" />
                        View
                      </Button>
                      {analysis.stats.totalIssues > 0 && (
                        <Button
                          variant="default"
                          size="sm"
                          onClick={() => onOpenAnalysisModal?.(curriculum.id, analysis)}
                          className="gap-1 bg-cyan-600 hover:bg-cyan-700"
                        >
                          <Wrench className="h-3 w-3" />
                          Reprocess
                        </Button>
                      )}
                    </div>
                  ) : (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleAnalyze(curriculum.id)}
                      disabled={analyzing}
                      className="gap-1"
                    >
                      {analyzing ? (
                        <>
                          <Loader2 className="h-3 w-3 animate-spin" />
                          Analyzing...
                        </>
                      ) : (
                        <>
                          <Search className="h-3 w-3" />
                          Analyze
                        </>
                      )}
                    </Button>
                  )}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Recent Jobs */}
      {completedJobs.length > 0 && (
        <Card className="bg-slate-800/50 border-slate-700">
          <CardHeader className="pb-3">
            <CardTitle className="text-base">Recent Jobs</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {completedJobs.slice(0, 5).map((job) => {
              const config = statusConfig[job.status] || statusConfig.complete;
              const StatusIcon = config.icon;

              return (
                <div
                  key={job.id}
                  className="flex items-center justify-between p-2 rounded-lg bg-slate-900/50"
                >
                  <div className="flex items-center gap-2">
                    <StatusIcon className="h-4 w-4" />
                    <span className="text-sm text-slate-300">{job.curriculumId}</span>
                  </div>
                  <Badge variant="outline" className={config.color}>
                    {config.label}
                  </Badge>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}

      {/* Job Details Modal */}
      {selectedJob && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <Card className="bg-slate-800 border-slate-700 w-full max-w-2xl max-h-[80vh] overflow-auto m-4">
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle>Job Details: {selectedJob.id}</CardTitle>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setSelectedJob(null)}
              >
                <XCircle className="h-4 w-4" />
              </Button>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <div className="text-sm text-slate-400">Status</div>
                  <Badge variant="outline" className={statusConfig[selectedJob.status]?.color}>
                    {statusConfig[selectedJob.status]?.label || selectedJob.status}
                  </Badge>
                </div>
                <div>
                  <div className="text-sm text-slate-400">Progress</div>
                  <div className="text-lg font-medium text-white">{Math.round(selectedJob.overallProgress)}%</div>
                </div>
              </div>

              <div>
                <div className="text-sm text-slate-400 mb-2">Stages</div>
                <div className="space-y-2">
                  {selectedJob.stages.map((stage) => (
                    <div key={stage.id} className="flex items-center gap-2">
                      <div className={`w-2 h-2 rounded-full ${
                        stage.status === 'complete' ? 'bg-emerald-500' :
                        stage.status === 'in_progress' ? 'bg-cyan-500 animate-pulse' :
                        stage.status === 'failed' ? 'bg-red-500' :
                        stage.status === 'skipped' ? 'bg-slate-600' :
                        'bg-slate-500'
                      }`} />
                      <span className="text-sm text-slate-300 flex-1">{stage.name}</span>
                      {stage.itemsTotal > 0 && (
                        <span className="text-xs text-slate-400">
                          {stage.itemsProcessed}/{stage.itemsTotal}
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              </div>

              {selectedJob.fixesApplied.length > 0 && (
                <div>
                  <div className="text-sm text-slate-400 mb-2">Fixes Applied ({selectedJob.fixesApplied.length})</div>
                  <div className="max-h-40 overflow-auto space-y-1">
                    {selectedJob.fixesApplied.map((fix, i) => (
                      <div key={i} className="text-xs text-slate-400 flex items-start gap-1">
                        <CheckCircle className="h-3 w-3 text-emerald-500 mt-0.5 flex-shrink-0" />
                        {fix}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {selectedJob.error && (
                <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-3">
                  <div className="text-sm text-red-400">{selectedJob.error}</div>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
