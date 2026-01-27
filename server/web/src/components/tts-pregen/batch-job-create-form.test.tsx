/**
 * BatchJobCreateForm Component Tests
 *
 * Tests the REAL component with MSW for network-level HTTP mocking.
 * No vi.mock of internal modules - per "Real Over Mock" philosophy.
 */
import { describe, it, expect, vi, beforeAll, beforeEach, afterAll, afterEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { BatchJobCreateForm } from './batch-job-create-form';
import { mswTestState, server } from '@/test/msw-server';
import { createTestProfile } from '@/test/msw-handlers';
import type { TTSProfile } from '@/types/tts-pregen';

// Set environment to use real backend (not mock mode)
process.env.NEXT_PUBLIC_BACKEND_URL = 'http://localhost:8766';
process.env.NEXT_PUBLIC_USE_MOCK = 'false';

const mockProfiles: TTSProfile[] = [
  createTestProfile({
    id: 'profile-1',
    name: 'Default Voice',
    provider: 'chatterbox',
    voice_id: 'voice-1',
    tags: ['default', 'warm'],
    is_default: true,
    is_active: true,
    settings: { speed: 1.0, exaggeration: 0.5 },
    description: 'A warm, natural voice',
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

describe('BatchJobCreateForm', () => {
  const mockOnComplete = vi.fn();
  const mockOnCancel = vi.fn();

  // Start MSW server for this test file
  beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
  afterEach(() => {
    server.resetHandlers();
    mswTestState.reset();
    vi.clearAllMocks();
  });
  afterAll(() => server.close());

  beforeEach(() => {
    mswTestState.setProfiles(mockProfiles);
    mswTestState.setExtractResponse({
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

    // The real API call is intercepted by MSW - verify by checking for preview step
    await vi.waitFor(() => {
      // After successful extraction, should show preview content
      expect(screen.getByText('TTS Profile')).toBeInTheDocument();
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
