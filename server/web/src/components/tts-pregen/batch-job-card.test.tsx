import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { BatchJobCard } from './batch-job-card';
import type { TTSPregenJob, JobProgress } from '@/types/tts-pregen';

const createMockJob = (overrides: Partial<TTSPregenJob> = {}): TTSPregenJob => ({
  id: 'job-1',
  name: 'Test Batch Job',
  job_type: 'batch',
  status: 'pending',
  source_type: 'knowledge-bowl',
  profile_id: 'profile-1',
  output_format: 'wav',
  normalize_volume: false,
  output_dir: '/data/tts-pregenerated/jobs/job-1/audio',
  total_items: 100,
  completed_items: 0,
  failed_items: 0,
  current_item_index: 0,
  created_at: '2024-01-15T10:00:00Z',
  updated_at: '2024-01-15T10:00:00Z',
  consecutive_failures: 0,
  ...overrides,
});

const createMockProgress = (overrides: Partial<JobProgress> = {}): JobProgress => ({
  job_id: 'job-1',
  status: 'running',
  percentage: 50,
  completed_items: 50,
  failed_items: 0,
  pending_items: 50,
  total_items: 100,
  current_item_index: 50,
  current_item_text: 'What is the speed of light?',
  ...overrides,
});

describe('BatchJobCard', () => {
  const defaultProps = {
    job: createMockJob(),
    profileName: 'Default TTS Profile',
    onStart: vi.fn(),
    onPause: vi.fn(),
    onResume: vi.fn(),
    onDelete: vi.fn(),
    onRetryFailed: vi.fn(),
    onViewItems: vi.fn(),
  };

  it('renders job name and profile', () => {
    render(<BatchJobCard {...defaultProps} />);
    expect(screen.getByText('Test Batch Job')).toBeInTheDocument();
    expect(screen.getByText(/Default TTS Profile/)).toBeInTheDocument();
  });

  it('displays pending status badge', () => {
    render(<BatchJobCard {...defaultProps} />);
    expect(screen.getByText('Pending')).toBeInTheDocument();
  });

  it('displays running status with progress', () => {
    const runningJob = createMockJob({ status: 'running' });
    const progress = createMockProgress();

    render(<BatchJobCard {...defaultProps} job={runningJob} progress={progress} />);

    expect(screen.getByText('Running')).toBeInTheDocument();
    expect(screen.getByText('50 / 100 items')).toBeInTheDocument();
    expect(screen.getByText('50%')).toBeInTheDocument();
  });

  it('shows current item text when running', () => {
    const runningJob = createMockJob({ status: 'running' });
    const progress = createMockProgress();

    render(<BatchJobCard {...defaultProps} job={runningJob} progress={progress} />);

    expect(screen.getByText(/What is the speed of light/)).toBeInTheDocument();
  });

  it('displays failed items badge when there are failures', () => {
    const jobWithFailures = createMockJob({
      status: 'completed',
      completed_items: 95,
      failed_items: 5,
    });

    render(<BatchJobCard {...defaultProps} job={jobWithFailures} />);
    expect(screen.getByText('5 failed')).toBeInTheDocument();
  });

  it('shows Start button for pending jobs', () => {
    render(<BatchJobCard {...defaultProps} />);
    expect(screen.getByRole('button', { name: /start/i })).toBeInTheDocument();
  });

  it('shows Pause button for running jobs', () => {
    const runningJob = createMockJob({ status: 'running' });
    render(<BatchJobCard {...defaultProps} job={runningJob} />);
    expect(screen.getByRole('button', { name: /pause/i })).toBeInTheDocument();
  });

  it('shows Resume button for paused jobs', () => {
    const pausedJob = createMockJob({ status: 'paused' });
    render(<BatchJobCard {...defaultProps} job={pausedJob} />);
    expect(screen.getByRole('button', { name: /resume/i })).toBeInTheDocument();
  });

  it('shows Retry Failed button when there are failed items', () => {
    const jobWithFailures = createMockJob({
      status: 'completed',
      failed_items: 5,
    });
    render(<BatchJobCard {...defaultProps} job={jobWithFailures} />);
    expect(screen.getByRole('button', { name: /retry failed/i })).toBeInTheDocument();
  });

  it('calls onStart when Start button is clicked', () => {
    const onStart = vi.fn();
    render(<BatchJobCard {...defaultProps} onStart={onStart} />);

    fireEvent.click(screen.getByRole('button', { name: /start/i }));
    expect(onStart).toHaveBeenCalledTimes(1);
  });

  it('calls onPause when Pause button is clicked', () => {
    const onPause = vi.fn();
    const runningJob = createMockJob({ status: 'running' });
    render(<BatchJobCard {...defaultProps} job={runningJob} onPause={onPause} />);

    fireEvent.click(screen.getByRole('button', { name: /pause/i }));
    expect(onPause).toHaveBeenCalledTimes(1);
  });

  it('calls onViewItems when Items button is clicked', () => {
    const onViewItems = vi.fn();
    render(<BatchJobCard {...defaultProps} onViewItems={onViewItems} />);

    fireEvent.click(screen.getByRole('button', { name: /items/i }));
    expect(onViewItems).toHaveBeenCalledTimes(1);
  });

  it('calls onDelete when Delete button is clicked', () => {
    const onDelete = vi.fn();
    render(<BatchJobCard {...defaultProps} onDelete={onDelete} />);

    fireEvent.click(screen.getByRole('button', { name: /delete/i }));
    expect(onDelete).toHaveBeenCalledTimes(1);
  });

  it('displays error message for failed jobs', () => {
    const failedJob = createMockJob({
      status: 'failed',
      last_error: 'TTS service unavailable',
    });
    render(<BatchJobCard {...defaultProps} job={failedJob} />);
    expect(screen.getByText('TTS service unavailable')).toBeInTheDocument();
  });

  it('shows completed status with green progress bar', () => {
    const completedJob = createMockJob({
      status: 'completed',
      completed_items: 100,
    });
    render(<BatchJobCard {...defaultProps} job={completedJob} />);
    expect(screen.getByText('Completed')).toBeInTheDocument();
  });

  it('renders compact view correctly', () => {
    const completedJob = createMockJob({
      status: 'completed',
      completed_items: 100,
    });
    render(<BatchJobCard {...defaultProps} job={completedJob} compact />);

    // Compact view should still show name and status
    expect(screen.getByText('Test Batch Job')).toBeInTheDocument();
    expect(screen.getByText('Completed')).toBeInTheDocument();
  });

  it('displays source type correctly', () => {
    render(<BatchJobCard {...defaultProps} />);
    expect(screen.getByText(/Source: Knowledge Bowl/)).toBeInTheDocument();
  });

  it('displays output format', () => {
    render(<BatchJobCard {...defaultProps} />);
    expect(screen.getByText(/Format: wav/)).toBeInTheDocument();
  });
});
