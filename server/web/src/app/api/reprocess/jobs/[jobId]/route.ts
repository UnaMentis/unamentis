import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * GET /api/reprocess/jobs/[jobId]
 * Get detailed progress for a specific job
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ jobId: string }> }
) {
  const { jobId } = await params;

  try {
    const response = await fetch(`${BACKEND_URL}/api/reprocess/jobs/${jobId}`, {
      cache: 'no-store',
    });

    if (!response.ok) {
      throw new Error(`Backend returned ${response.status}`);
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error fetching job progress:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to fetch job progress' },
      { status: 503 }
    );
  }
}

/**
 * DELETE /api/reprocess/jobs/[jobId]
 * Cancel a running reprocessing job
 */
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ jobId: string }> }
) {
  const { jobId } = await params;

  try {
    const response = await fetch(`${BACKEND_URL}/api/reprocess/jobs/${jobId}`, {
      method: 'DELETE',
    });

    const data = await response.json();

    if (!response.ok) {
      return NextResponse.json(data, { status: response.status });
    }

    return NextResponse.json(data);
  } catch (error) {
    console.error('Error cancelling job:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to cancel job' },
      { status: 503 }
    );
  }
}
