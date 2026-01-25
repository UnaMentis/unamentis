import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { BatchJobCreateForm } from './batch-job-create-form';
import type { TTSProfile } from '@/types/tts-pregen';

// Mock the API client
vi.mock('@/lib/api-client', () => ({
  extractContent: vi.fn(),
  createBatchJob: vi.fn(),
  startBatchJob: vi.fn(),
}));

import { extractContent, createBatchJob } from '@/lib/api-client';

const mockExtractContent = vi.mocked(extractContent);
const mockCreateBatchJob = vi.mocked(createBatchJob);
// startBatchJob is mocked but only used internally by the component

const mockProfiles: TTSProfile[] = [
  {
    id: 'profile-1',
    name: 'Default Voice',
    provider: 'chatterbox',
    voice_id: 'voice-1',
    tags: ['default', 'warm'],
    is_default: true,
    is_active: true,
    settings: { speed: 1.0, exaggeration: 0.5 },
    description: 'A warm, natural voice',
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

describe('BatchJobCreateForm', () => {
  const mockOnComplete = vi.fn();
  const mockOnCancel = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    mockExtractContent.mockResolvedValue({
      success: true,
      items: [
        { text: 'Question 1', source_ref: 'q1:question' },
        { text: 'Answer 1', source_ref: 'q1:answer' },
      ],
      total_count: 100,
      stats: {
        total_questions: 25,
        type_counts: { question: 25, answer: 25, hint: 30, explanation: 20 },
        domain_counts: { Physics: 50, Chemistry: 50 },
      },
    });
    mockCreateBatchJob.mockResolvedValue({
      success: true,
      job: {
        id: 'new-job-1',
        name: 'Test Job',
        job_type: 'batch',
        status: 'pending',
        source_type: 'knowledge-bowl',
        output_format: 'wav',
        normalize_volume: false,
        output_dir: '/data/output',
        total_items: 0,
        completed_items: 0,
        failed_items: 0,
        current_item_index: 0,
        created_at: '2024-01-15T10:00:00Z',
        updated_at: '2024-01-15T10:00:00Z',
        consecutive_failures: 0,
      },
    });
  });

  it('renders the modal with title', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    expect(screen.getByText('Create Batch Job')).toBeInTheDocument();
  });

  it('shows step indicator with 4 steps', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    expect(screen.getByText('1')).toBeInTheDocument();
    expect(screen.getByText('2')).toBeInTheDocument();
    expect(screen.getByText('3')).toBeInTheDocument();
    expect(screen.getByText('4')).toBeInTheDocument();
  });

  it('shows step labels', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    expect(screen.getByText('Source')).toBeInTheDocument();
    expect(screen.getByText('Profile')).toBeInTheDocument();
    expect(screen.getByText('Preview')).toBeInTheDocument();
    expect(screen.getByText('Create')).toBeInTheDocument();
  });

  it('starts on step 1 with source selection', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    expect(screen.getByText('Content Source')).toBeInTheDocument();
    expect(screen.getByText('Knowledge Bowl')).toBeInTheDocument();
    expect(screen.getByText('Curriculum')).toBeInTheDocument();
    expect(screen.getByText('Custom')).toBeInTheDocument();
  });

  it('shows content type checkboxes for Knowledge Bowl', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    expect(screen.getByText('Questions')).toBeInTheDocument();
    expect(screen.getByText('Answers')).toBeInTheDocument();
    expect(screen.getByText('Hints')).toBeInTheDocument();
    expect(screen.getByText('Explanations')).toBeInTheDocument();
  });

  it('has Next button on step 1', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    expect(screen.getByRole('button', { name: /next/i })).toBeInTheDocument();
  });

  it('calls onCancel when X button is clicked', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    // Find and click the close button
    const closeButton = screen.getAllByRole('button').find((btn) => btn.querySelector('.lucide-x'));
    expect(closeButton).toBeInTheDocument();

    fireEvent.click(closeButton!);
    expect(mockOnCancel).toHaveBeenCalled();
  });

  it('advances to step 2 when Next is clicked', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: /next/i }));

    expect(screen.getByText('TTS Profile')).toBeInTheDocument();
    expect(screen.getByText('Default Voice')).toBeInTheDocument();
    expect(screen.getByText('Fast Voice')).toBeInTheDocument();
  });

  it('shows profile details in step 2', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: /next/i }));

    expect(screen.getByText('chatterbox')).toBeInTheDocument();
    expect(screen.getByText('vibevoice')).toBeInTheDocument();
    expect(screen.getByText('A warm, natural voice')).toBeInTheDocument();
  });

  it('shows Default badge for default profile', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: /next/i }));

    expect(screen.getByText('Default')).toBeInTheDocument();
  });

  it('has Back button on step 2', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: /next/i }));

    expect(screen.getByRole('button', { name: /back/i })).toBeInTheDocument();
  });

  it('has Preview Content button on step 2', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: /next/i }));

    expect(screen.getByRole('button', { name: /preview content/i })).toBeInTheDocument();
  });

  it('calls extractContent when Preview Content is clicked', async () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: /next/i }));
    fireEvent.click(screen.getByRole('button', { name: /preview content/i }));

    await vi.waitFor(() => {
      expect(mockExtractContent).toHaveBeenCalledWith({
        source_type: 'knowledge-bowl',
        include_questions: true,
        include_answers: true,
        include_hints: true,
        include_explanations: true,
      });
    });
  });

  it('shows message when no profiles available', () => {
    render(
      <BatchJobCreateForm profiles={[]} onComplete={mockOnComplete} onCancel={mockOnCancel} />
    );

    fireEvent.click(screen.getByRole('button', { name: /next/i }));

    expect(screen.getByText('No profiles available. Create one first.')).toBeInTheDocument();
  });

  it('disables Next button on step 1 when no content types selected', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    // Uncheck all content types
    const checkboxes = screen.getAllByRole('checkbox');
    checkboxes.forEach((cb) => {
      if ((cb as HTMLInputElement).checked) {
        fireEvent.click(cb);
      }
    });

    expect(screen.getByRole('button', { name: /next/i })).toBeDisabled();
  });

  it('shows curriculum and custom as coming soon', () => {
    render(
      <BatchJobCreateForm
        profiles={mockProfiles}
        onComplete={mockOnComplete}
        onCancel={mockOnCancel}
      />
    );

    const comingSoonElements = screen.getAllByText('Coming soon');
    expect(comingSoonElements).toHaveLength(2);
  });
});
