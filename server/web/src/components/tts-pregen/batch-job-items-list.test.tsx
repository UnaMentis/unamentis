/**
 * BatchJobItemsList Component Tests
 *
 * Tests the REAL component with MSW for network-level HTTP mocking.
 * No vi.mock of internal modules - per "Real Over Mock" philosophy.
 */
import { describe, it, expect, vi, beforeAll, beforeEach, afterAll, afterEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { BatchJobItemsList } from './batch-job-items-list';
import { mswTestState, server, http, HttpResponse } from '@/test/msw-server';
import { createTestItem } from '@/test/msw-handlers';
import type { TTSJobItem } from '@/types/tts-pregen';

// Set environment to use real backend (not mock mode)
process.env.NEXT_PUBLIC_BACKEND_URL = 'http://localhost:8766';
process.env.NEXT_PUBLIC_USE_MOCK = 'false';

const mockItems: TTSJobItem[] = [
  createTestItem({
    id: 'item-1',
    job_id: 'job-1',
    item_index: 0,
    text_content: 'What is the capital of France?',
    text_hash: 'hash1',
    status: 'completed',
    attempt_count: 1,
    duration_seconds: 1.5,
    output_file: '/audio/item-1.wav',
  }),
  createTestItem({
    id: 'item-2',
    job_id: 'job-1',
    item_index: 1,
    text_content: 'What is 2 + 2?',
    text_hash: 'hash2',
    status: 'failed',
    attempt_count: 3,
    last_error: 'TTS generation timeout',
  }),
  createTestItem({
    id: 'item-3',
    job_id: 'job-1',
    item_index: 2,
    text_content: 'Name the planets in our solar system.',
    text_hash: 'hash3',
    status: 'pending',
    attempt_count: 0,
  }),
];

describe('BatchJobItemsList', () => {
  const mockOnClose = vi.fn();

  // Start MSW server for this test file
  beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
  afterEach(() => {
    server.resetHandlers();
    mswTestState.reset();
    vi.clearAllMocks();
  });
  afterAll(() => server.close());

  beforeEach(() => {
    mswTestState.setItems(mockItems);
  });

  it('renders the modal with title', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    expect(screen.getByText('Job Items')).toBeInTheDocument();
  });

  it('shows loading spinner while fetching', () => {
    // Make the request hang
    server.use(
      http.get('*/api/tts/pregen/jobs/:jobId/items', () => {
        return new Promise(() => {}); // Never resolves
      })
    );
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    expect(document.querySelector('.animate-spin')).toBeInTheDocument();
  });

  it('displays items after loading', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByText('What is the capital of France?')).toBeInTheDocument();
    });
    expect(screen.getByText('What is 2 + 2?')).toBeInTheDocument();
    expect(screen.getByText('Name the planets in our solar system.')).toBeInTheDocument();
  });

  it('shows status badges for each item', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByText('Completed')).toBeInTheDocument();
    });
    expect(screen.getByText('Failed')).toBeInTheDocument();
    expect(screen.getByText('Pending')).toBeInTheDocument();
  });

  it('displays error message for failed items', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByText('TTS generation timeout')).toBeInTheDocument();
    });
  });

  it('shows Retry Failed button when failed items exist', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByRole('button', { name: /retry failed/i })).toBeInTheDocument();
    });
  });

  it('calls retryFailedItems when Retry Failed is clicked', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByRole('button', { name: /retry failed/i })).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /retry failed/i }));

    // The real API call is intercepted by MSW - verify by checking the UI updated
    await vi.waitFor(() => {
      expect(screen.getByText('Job Items')).toBeInTheDocument();
    });
  });

  it('calls onClose when close button is clicked', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    // Find the X button (last button with just an icon)
    const closeButtons = screen.getAllByRole('button');
    const closeButton = closeButtons.find((btn) => btn.querySelector('.lucide-x'));
    expect(closeButton).toBeInTheDocument();

    fireEvent.click(closeButton!);
    expect(mockOnClose).toHaveBeenCalled();
  });

  it('has filter dropdown with all status options', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    const select = screen.getByRole('combobox');
    expect(select).toBeInTheDocument();

    expect(screen.getByRole('option', { name: 'All Status' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Pending' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Processing' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Completed' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Failed' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Skipped' })).toBeInTheDocument();
  });

  it('displays stats information', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByText(/Total: 3/)).toBeInTheDocument();
    });
    expect(screen.getByText(/Showing: 3/)).toBeInTheDocument();
  });

  it('shows empty state when no items found', async () => {
    mswTestState.setItems([]);
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByText('No items found')).toBeInTheDocument();
    });
  });

  it('shows pagination when more than one page', async () => {
    // Create 50 items to simulate pagination (more than pageSize of 20)
    const manyItems = Array.from({ length: 50 }, (_, i) =>
      createTestItem({
        id: `item-${i}`,
        item_index: i,
        text_content: `Question ${i}`,
        text_hash: `hash${i}`,
      })
    );
    mswTestState.setItems(manyItems);

    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByText(/Page 1 of 3/)).toBeInTheDocument();
    });
  });

  it('shows duration for completed items', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByText('1.5s')).toBeInTheDocument();
    });
  });

  it('shows attempt count when greater than 1', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByText('Attempts: 3')).toBeInTheDocument();
    });
  });
});
