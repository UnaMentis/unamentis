import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * GET /api/tts/pregen/jobs/[jobId]/progress
 * Get progress for a running TTS batch job
 *
 * Returns:
 * - percentage: Completion percentage
 * - completed_items: Number of completed items
 * - failed_items: Number of failed items
 * - total_items: Total number of items
 * - current_item_index: Index of item being processed
 * - current_item_text: Text of current item (truncated)
 * - status: Current job status
 * - estimated_time_remaining: Estimated seconds remaining (optional)
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ jobId: string }> }
) {
  const { jobId } = await params;

  try {
    const response = await fetch(`${BACKEND_URL}/api/tts/pregen/jobs/${jobId}/progress`, {
      cache: 'no-store',
    });

    if (!response.ok) {
      const errorData = await response
        .json()
        .catch(() => ({ error: `Backend returned ${response.status}` }));
      return NextResponse.json(
        { success: false, error: errorData.error || `Job not found` },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error fetching TTS job progress:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to fetch job progress' },
      { status: 503 }
    );
  }
}
