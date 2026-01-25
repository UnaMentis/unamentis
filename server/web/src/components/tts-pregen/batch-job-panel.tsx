'use client';

import { useState, useEffect, useCallback } from 'react';
import { Zap, RefreshCw, Plus, CheckCircle, Play, AlertCircle } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Tooltip } from '@/components/ui/tooltip';
import { HelpButton, batchJobsHelpSections } from '@/components/ui/help-button';
import { BatchJobCard } from './batch-job-card';
import { BatchJobCreateForm } from './batch-job-create-form';
import { BatchJobItemsList } from './batch-job-items-list';
import type { TTSPregenJob, JobProgress, TTSProfile } from '@/types/tts-pregen';
import {
  getBatchJobs,
  getJobProgress,
  startBatchJob,
  pauseBatchJob,
  resumeBatchJob,
  deleteBatchJob,
  retryFailedItems,
  getTTSProfiles,
} from '@/lib/api-client';

export function BatchJobPanel() {
  const [jobs, setJobs] = useState<TTSPregenJob[]>([]);
  const [profiles, setProfiles] = useState<TTSProfile[]>([]);
  const [progressMap, setProgressMap] = useState<Record<string, JobProgress>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<string>('all');
  const [createModalOpen, setCreateModalOpen] = useState(false);
  const [viewItemsJobId, setViewItemsJobId] = useState<string | null>(null);

  const fetchJobs = useCallback(async () => {
    setError(null);
    try {
      const status = filter === 'all' ? undefined : filter;
      const data = await getBatchJobs({ status, job_type: 'batch' });
      setJobs(data.jobs || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load batch jobs');
    } finally {
      setLoading(false);
    }
  }, [filter]);

  const fetchProfiles = useCallback(async () => {
    try {
      const data = await getTTSProfiles({ is_active: true });
      setProfiles(data.profiles || []);
    } catch (err) {
      console.error('Failed to load profiles:', err);
    }
  }, []);

  // Poll progress for active jobs
  const fetchProgress = useCallback(async () => {
    const activeJobs = jobs.filter((j) => ['pending', 'running', 'paused'].includes(j.status));
    if (activeJobs.length === 0) return;

    const progressUpdates: Record<string, JobProgress> = {};
    await Promise.all(
      activeJobs.map(async (job) => {
        try {
          const progress = await getJobProgress(job.id);
          progressUpdates[job.id] = progress;
        } catch {
          // Ignore errors for individual progress fetches
        }
      })
    );
    setProgressMap((prev) => ({ ...prev, ...progressUpdates }));
  }, [jobs]);

  useEffect(() => {
    setLoading(true);
    fetchJobs();
    fetchProfiles();
  }, [filter, fetchJobs, fetchProfiles]);

  // Poll for updates every 3 seconds when there are active jobs
  useEffect(() => {
    const hasActiveJobs = jobs.some((job) => ['pending', 'running'].includes(job.status));
    if (!hasActiveJobs) return;

    const interval = setInterval(() => {
      fetchJobs();
      fetchProgress();
    }, 3000);

    return () => clearInterval(interval);
  }, [jobs, fetchJobs, fetchProgress]);

  // Initial progress fetch
  useEffect(() => {
    fetchProgress();
  }, [jobs, fetchProgress]);

  const handleStart = async (jobId: string) => {
    try {
      await startBatchJob(jobId);
      await fetchJobs();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to start job');
    }
  };

  const handlePause = async (jobId: string) => {
    try {
      await pauseBatchJob(jobId);
      await fetchJobs();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to pause job');
    }
  };

  const handleResume = async (jobId: string) => {
    try {
      await resumeBatchJob(jobId);
      await fetchJobs();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to resume job');
    }
  };

  const handleDelete = async (jobId: string) => {
    if (!confirm('Are you sure you want to delete this batch job?')) {
      return;
    }
    try {
      await deleteBatchJob(jobId);
      await fetchJobs();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete job');
    }
  };

  const handleRetryFailed = async (jobId: string) => {
    try {
      const result = await retryFailedItems(jobId);
      if (result.success) {
        await fetchJobs();
      } else {
        setError(result.error || 'Failed to retry failed items');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to retry failed items');
    }
  };

  const handleJobCreated = () => {
    setCreateModalOpen(false);
    fetchJobs();
  };

  const activeJobs = jobs.filter((j) => ['pending', 'running', 'paused'].includes(j.status));
  const completedJobs = jobs.filter((j) => ['completed', 'failed', 'cancelled'].includes(j.status));

  const getProfileName = (profileId?: string) => {
    if (!profileId) return 'Inline Config';
    const profile = profiles.find((p) => p.id === profileId);
    return profile?.name || 'Unknown Profile';
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white flex items-center gap-2">
            <Zap className="w-6 h-6 text-amber-400" />
            Batch Jobs
            <HelpButton
              title="Batch Jobs Help"
              description="Learn how to create and manage batch audio generation jobs"
              sections={batchJobsHelpSections}
            />
          </h2>
          <p className="text-slate-400 mt-1">Generate audio for Knowledge Bowl questions</p>
        </div>

        <div className="flex items-center gap-2">
          <Tooltip content="Filter jobs by their current status" side="bottom">
            <select
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              className="px-3 py-2 text-sm bg-slate-800 border border-slate-700 rounded-md text-slate-300 focus:outline-none focus:ring-2 focus:ring-amber-500/50"
            >
              <option value="all">All Jobs</option>
              <option value="pending">Pending</option>
              <option value="running">Running</option>
              <option value="paused">Paused</option>
              <option value="completed">Completed</option>
              <option value="failed">Failed</option>
            </select>
          </Tooltip>

          <Tooltip content="Reload the job list from the server" side="bottom">
            <Button onClick={fetchJobs} variant="outline" size="sm" className="text-slate-300">
              <RefreshCw className="w-4 h-4 mr-2" />
              Refresh
            </Button>
          </Tooltip>

          <Tooltip content="Create a new batch audio generation job" side="bottom">
            <Button
              onClick={() => setCreateModalOpen(true)}
              size="sm"
              className="bg-amber-600 hover:bg-amber-700"
            >
              <Plus className="w-4 h-4 mr-2" />
              New Job
            </Button>
          </Tooltip>
        </div>
      </div>

      {/* Error Message */}
      {error && (
        <div className="p-4 bg-red-500/10 border border-red-500/30 rounded-md text-red-400 flex items-center gap-2">
          <AlertCircle className="w-5 h-5 flex-shrink-0" />
          {error}
        </div>
      )}

      {/* Loading */}
      {loading ? (
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin w-8 h-8 border-2 border-amber-500 border-t-transparent rounded-full" />
        </div>
      ) : jobs.length === 0 ? (
        <Card className="bg-slate-900/50 border-slate-800">
          <CardContent className="flex flex-col items-center justify-center py-12 text-center">
            <Zap className="w-12 h-12 text-slate-600 mb-4" />
            <h3 className="text-lg font-medium text-slate-300 mb-2">No batch jobs</h3>
            <p className="text-slate-500 max-w-md mb-4">
              Create a batch job to generate audio files for Knowledge Bowl questions
            </p>
            <Button
              onClick={() => setCreateModalOpen(true)}
              className="bg-amber-600 hover:bg-amber-700"
            >
              <Plus className="w-4 h-4 mr-2" />
              Create First Job
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-6">
          {/* Active Jobs */}
          {activeJobs.length > 0 && (
            <div className="space-y-4">
              <h3 className="text-lg font-medium text-slate-200 flex items-center gap-2">
                <Play className="w-5 h-5 text-blue-400" />
                Active Jobs ({activeJobs.length})
              </h3>

              <div className="space-y-3">
                {activeJobs.map((job) => (
                  <BatchJobCard
                    key={job.id}
                    job={job}
                    progress={progressMap[job.id]}
                    profileName={getProfileName(job.profile_id)}
                    onStart={() => handleStart(job.id)}
                    onPause={() => handlePause(job.id)}
                    onResume={() => handleResume(job.id)}
                    onDelete={() => handleDelete(job.id)}
                    onRetryFailed={() => handleRetryFailed(job.id)}
                    onViewItems={() => setViewItemsJobId(job.id)}
                  />
                ))}
              </div>
            </div>
          )}

          {/* Completed Jobs */}
          {completedJobs.length > 0 && (
            <div className="space-y-4">
              <h3 className="text-lg font-medium text-slate-200 flex items-center gap-2">
                <CheckCircle className="w-5 h-5 text-slate-400" />
                Completed Jobs ({completedJobs.length})
              </h3>

              <div className="space-y-2">
                {completedJobs.map((job) => (
                  <BatchJobCard
                    key={job.id}
                    job={job}
                    progress={progressMap[job.id]}
                    profileName={getProfileName(job.profile_id)}
                    onStart={() => handleStart(job.id)}
                    onPause={() => handlePause(job.id)}
                    onResume={() => handleResume(job.id)}
                    onDelete={() => handleDelete(job.id)}
                    onRetryFailed={() => handleRetryFailed(job.id)}
                    onViewItems={() => setViewItemsJobId(job.id)}
                    compact
                  />
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Create Modal */}
      {createModalOpen && (
        <BatchJobCreateForm
          profiles={profiles}
          onComplete={handleJobCreated}
          onCancel={() => setCreateModalOpen(false)}
        />
      )}

      {/* Items List Modal */}
      {viewItemsJobId && (
        <BatchJobItemsList jobId={viewItemsJobId} onClose={() => setViewItemsJobId(null)} />
      )}
    </div>
  );
}
