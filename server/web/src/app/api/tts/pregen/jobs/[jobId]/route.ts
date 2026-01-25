import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * GET /api/tts/pregen/jobs/[jobId]
 * Get details for a specific TTS batch job
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ jobId: string }> }
) {
  const { jobId } = await params;

  try {
    const response = await fetch(`${BACKEND_URL}/api/tts/pregen/jobs/${jobId}`, {
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
    console.error('Error fetching TTS batch job:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to fetch TTS batch job' },
      { status: 503 }
    );
  }
}

/**
 * DELETE /api/tts/pregen/jobs/[jobId]
 * Delete a TTS batch job and all its items
 */
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ jobId: string }> }
) {
  const { jobId } = await params;

  try {
    const response = await fetch(`${BACKEND_URL}/api/tts/pregen/jobs/${jobId}`, {
      method: 'DELETE',
    });

    if (!response.ok) {
      const errorData = await response
        .json()
        .catch(() => ({ error: `Backend returned ${response.status}` }));
      return NextResponse.json(
        { success: false, error: errorData.error || `Failed to delete job` },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error deleting TTS batch job:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to delete TTS batch job' },
      { status: 503 }
    );
  }
}
