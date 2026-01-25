import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { BatchJobItemsList } from './batch-job-items-list';
import type { TTSJobItem } from '@/types/tts-pregen';

// Mock the API client
vi.mock('@/lib/api-client', () => ({
  getJobItems: vi.fn(),
  retryFailedItems: vi.fn(),
}));

import { getJobItems, retryFailedItems } from '@/lib/api-client';

const mockGetJobItems = vi.mocked(getJobItems);
const mockRetryFailedItems = vi.mocked(retryFailedItems);

const mockItems: TTSJobItem[] = [
  {
    id: 'item-1',
    job_id: 'job-1',
    item_index: 0,
    text_content: 'What is the capital of France?',
    text_hash: 'hash1',
    status: 'completed',
    attempt_count: 1,
    duration_seconds: 1.5,
    output_file: '/audio/item-1.wav',
  },
  {
    id: 'item-2',
    job_id: 'job-1',
    item_index: 1,
    text_content: 'What is 2 + 2?',
    text_hash: 'hash2',
    status: 'failed',
    attempt_count: 3,
    last_error: 'TTS generation timeout',
  },
  {
    id: 'item-3',
    job_id: 'job-1',
    item_index: 2,
    text_content: 'Name the planets in our solar system.',
    text_hash: 'hash3',
    status: 'pending',
    attempt_count: 0,
  },
];

describe('BatchJobItemsList', () => {
  const mockOnClose = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    mockGetJobItems.mockResolvedValue({
      success: true,
      items: mockItems,
      total: 3,
      limit: 20,
      offset: 0,
    });
  });

  it('renders the modal with title', async () => {
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    expect(screen.getByText('Job Items')).toBeInTheDocument();
  });

  it('shows loading spinner while fetching', () => {
    mockGetJobItems.mockImplementation(() => new Promise(() => {}));
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
    mockRetryFailedItems.mockResolvedValue({ success: true, reset_count: 1 });
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByRole('button', { name: /retry failed/i })).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole('button', { name: /retry failed/i }));

    await vi.waitFor(() => {
      expect(mockRetryFailedItems).toHaveBeenCalledWith('job-1');
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
    mockGetJobItems.mockResolvedValue({
      success: true,
      items: [],
      total: 0,
      limit: 20,
      offset: 0,
    });
    render(<BatchJobItemsList jobId="job-1" onClose={mockOnClose} />);

    await vi.waitFor(() => {
      expect(screen.getByText('No items found')).toBeInTheDocument();
    });
  });

  it('shows pagination when more than one page', async () => {
    mockGetJobItems.mockResolvedValue({
      success: true,
      items: mockItems,
      total: 50, // More than pageSize of 20
      limit: 20,
      offset: 0,
    });
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
