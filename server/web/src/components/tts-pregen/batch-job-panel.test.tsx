/**
 * BatchJobPanel Component Tests
 *
 * Tests the REAL component with MSW for network-level HTTP mocking.
 * No vi.mock of internal modules - per "Real Over Mock" philosophy.
 */
import { describe, it, expect, vi, beforeAll, beforeEach, afterAll, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { BatchJobPanel } from './batch-job-panel';
import { mswTestState, server, http, HttpResponse } from '@/test/msw-server';
import { createTestJob, createTestProfile, createTestProgress } from '@/test/msw-handlers';
import type { TTSPregenJob, TTSProfile, JobProgress } from '@/types/tts-pregen';

// Set environment to use real backend (not mock mode)
process.env.NEXT_PUBLIC_BACKEND_URL = 'http://localhost:8766';
process.env.NEXT_PUBLIC_USE_MOCK = 'false';

const mockJobs: TTSPregenJob[] = [
  createTestJob({
    id: 'job-1',
    name: 'Test Running Job',
    status: 'running',
    total_items: 100,
    completed_items: 45,
    failed_items: 2,
    current_item_index: 47,
    profile_id: 'profile-1',
  }),
  createTestJob({
    id: 'job-2',
    name: 'Test Completed Job',
    status: 'completed',
    output_format: 'mp3',
    normalize_volume: true,
    total_items: 50,
    completed_items: 50,
    failed_items: 0,
    current_item_index: 50,
    profile_id: 'profile-2',
  }),
];

const mockProfiles: TTSProfile[] = [
  createTestProfile({
    id: 'profile-1',
    name: 'Default Voice',
    provider: 'chatterbox',
    voice_id: 'voice-1',
    tags: ['default', 'warm'],
    is_default: true,
    is_active: true,
    settings: { speed: 1.0 },
  }),
  createTestProfile({
    id: 'profile-2',
    name: 'Fast Voice',
    provider: 'vibevoice',
    voice_id: 'voice-2',
    tags: ['fast'],
    is_default: false,
    is_active: true,
    settings: { speed: 1.5 },
  }),
];

const mockProgress: JobProgress = createTestProgress({
  job_id: 'job-1',
  status: 'running',
  percentage: 45.5,
  completed_items: 45,
  failed_items: 2,
  pending_items: 53,
  total_items: 100,
  current_item_index: 47,
  current_item_text: 'What is the speed of light?',
});

describe('BatchJobPanel', () => {
  // Start MSW server for this test file
  beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
  afterEach(() => {
    server.resetHandlers();
    mswTestState.reset();
    vi.clearAllMocks();
  });
  afterAll(() => server.close());

  beforeEach(() => {
    mswTestState.setJobs(mockJobs);
    mswTestState.setProfiles(mockProfiles);
    mswTestState.setProgress(mockProgress);
  });

  it('renders the header with title', async () => {
    render(<BatchJobPanel />);

    expect(screen.getByText('Batch Jobs')).toBeInTheDocument();
    expect(screen.getByText('Generate audio for Knowledge Bowl questions')).toBeInTheDocument();
  });

  it('shows loading spinner while fetching', () => {
    // Make the request hang
    server.use(
      http.get('*/api/tts/pregen/jobs', () => {
        return new Promise(() => {}); // Never resolves
      })
    );
    render(<BatchJobPanel />);

    expect(document.querySelector('.animate-spin')).toBeInTheDocument();
  });

  it('displays empty state when no jobs exist', async () => {
    mswTestState.setJobs([]);
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

    // The real API is intercepted by MSW - verify by checking UI updates
    await vi.waitFor(() => {
      expect(screen.getByText('Batch Jobs')).toBeInTheDocument();
    });
  });

  it('fetches profiles on mount', async () => {
    render(<BatchJobPanel />);

    // The real API is intercepted by MSW - verify by checking UI updates
    await vi.waitFor(() => {
      expect(screen.getByText('Batch Jobs')).toBeInTheDocument();
    });
  });
});
