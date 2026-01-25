import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { BatchJobPanel } from './batch-job-panel';
import type { TTSPregenJob, TTSProfile, JobProgress } from '@/types/tts-pregen';

// Mock the API client
vi.mock('@/lib/api-client', () => ({
  getBatchJobs: vi.fn(),
  getJobProgress: vi.fn(),
  startBatchJob: vi.fn(),
  pauseBatchJob: vi.fn(),
  resumeBatchJob: vi.fn(),
  deleteBatchJob: vi.fn(),
  retryFailedItems: vi.fn(),
  getTTSProfiles: vi.fn(),
}));

import { getBatchJobs, getJobProgress, getTTSProfiles } from '@/lib/api-client';

const mockGetBatchJobs = vi.mocked(getBatchJobs);
const mockGetJobProgress = vi.mocked(getJobProgress);
const mockGetTTSProfiles = vi.mocked(getTTSProfiles);

const mockJobs: TTSPregenJob[] = [
  {
    id: 'job-1',
    name: 'Test Running Job',
    job_type: 'batch',
    status: 'running',
    source_type: 'knowledge-bowl',
    output_format: 'wav',
    normalize_volume: false,
    output_dir: '/data/output',
    total_items: 100,
    completed_items: 45,
    failed_items: 2,
    current_item_index: 47,
    created_at: '2024-01-15T10:00:00Z',
    updated_at: '2024-01-15T10:30:00Z',
    profile_id: 'profile-1',
    consecutive_failures: 0,
  },
  {
    id: 'job-2',
    name: 'Test Completed Job',
    job_type: 'batch',
    status: 'completed',
    source_type: 'knowledge-bowl',
    output_format: 'mp3',
    normalize_volume: true,
    output_dir: '/data/output',
    total_items: 50,
    completed_items: 50,
    failed_items: 0,
    current_item_index: 50,
    created_at: '2024-01-14T10:00:00Z',
    updated_at: '2024-01-14T11:00:00Z',
    profile_id: 'profile-2',
    consecutive_failures: 0,
  },
];

const mockProfiles: TTSProfile[] = [
  {
    id: 'profile-1',
    name: 'Default Voice',
    provider: 'chatterbox',
    voice_id: 'voice-1',
    tags: ['default', 'warm'],
    is_default: true,
    is_active: true,
    settings: { speed: 1.0 },
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
  },
  {
    id: 'profile-2',
    name: 'Fast Voice',
    provider: 'vibevoice',
    voice_id: 'voice-2',
    tags: ['fast'],
    is_default: false,
    is_active: true,
    settings: { speed: 1.5 },
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
  },
];

const mockProgress: JobProgress = {
  job_id: 'job-1',
  status: 'running',
  percentage: 45.5,
  completed_items: 45,
  failed_items: 2,
  pending_items: 53,
  total_items: 100,
  current_item_index: 47,
  current_item_text: 'What is the speed of light?',
};

describe('BatchJobPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetBatchJobs.mockResolvedValue({
      success: true,
      jobs: mockJobs,
      total: 2,
      limit: 50,
      offset: 0,
    });
    mockGetTTSProfiles.mockResolvedValue({ profiles: mockProfiles, total: 2 });
    mockGetJobProgress.mockResolvedValue(mockProgress);
  });

  it('renders the header with title', async () => {
    render(<BatchJobPanel />);

    expect(screen.getByText('Batch Jobs')).toBeInTheDocument();
    expect(screen.getByText('Generate audio for Knowledge Bowl questions')).toBeInTheDocument();
  });

  it('shows loading spinner while fetching', () => {
    mockGetBatchJobs.mockImplementation(() => new Promise(() => {})); // Never resolves
    render(<BatchJobPanel />);

    expect(document.querySelector('.animate-spin')).toBeInTheDocument();
  });

  it('displays empty state when no jobs exist', async () => {
    mockGetBatchJobs.mockResolvedValue({ success: true, jobs: [], total: 0, limit: 50, offset: 0 });
    render(<BatchJobPanel />);

    // Wait for loading to complete
    await vi.waitFor(() => {
      expect(screen.getByText('No batch jobs')).toBeInTheDocument();
    });
    expect(screen.getByText('Create First Job')).toBeInTheDocument();
  });

  it('has filter dropdown with all status options', () => {
    render(<BatchJobPanel />);

    const select = screen.getByRole('combobox');
    expect(select).toBeInTheDocument();

    // Check options exist
    expect(screen.getByRole('option', { name: 'All Jobs' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Pending' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Running' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Paused' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Completed' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Failed' })).toBeInTheDocument();
  });

  it('has Refresh and New Job buttons', () => {
    render(<BatchJobPanel />);

    expect(screen.getByRole('button', { name: /refresh/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /new job/i })).toBeInTheDocument();
  });

  it('fetches jobs on mount', async () => {
    render(<BatchJobPanel />);

    await vi.waitFor(() => {
      expect(mockGetBatchJobs).toHaveBeenCalledWith({ status: undefined, job_type: 'batch' });
    });
  });

  it('fetches profiles on mount', async () => {
    render(<BatchJobPanel />);

    await vi.waitFor(() => {
      expect(mockGetTTSProfiles).toHaveBeenCalledWith({ is_active: true });
    });
  });
});
