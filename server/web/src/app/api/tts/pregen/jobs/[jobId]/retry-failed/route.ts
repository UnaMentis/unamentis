import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * POST /api/tts/pregen/jobs/[jobId]/retry-failed
 * Reset all failed items to pending status for retry
 *
 * Returns:
 * - reset_count: Number of items reset
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ jobId: string }> }
) {
  const { jobId } = await params;

  try {
    const response = await fetch(`${BACKEND_URL}/api/tts/pregen/jobs/${jobId}/retry-failed`, {
      method: 'POST',
    });

    if (!response.ok) {
      const errorData = await response
        .json()
        .catch(() => ({ error: `Backend returned ${response.status}` }));
      return NextResponse.json(
        { success: false, error: errorData.error || `Failed to retry failed items` },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error retrying failed items:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to retry failed items' },
      { status: 503 }
    );
  }
}
