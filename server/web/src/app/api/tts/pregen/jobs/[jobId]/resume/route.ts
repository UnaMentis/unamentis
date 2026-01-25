import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * POST /api/tts/pregen/jobs/[jobId]/resume
 * Resume a paused TTS batch job
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ jobId: string }> }
) {
  const { jobId } = await params;

  try {
    const response = await fetch(`${BACKEND_URL}/api/tts/pregen/jobs/${jobId}/resume`, {
      method: 'POST',
    });

    if (!response.ok) {
      const errorData = await response
        .json()
        .catch(() => ({ error: `Backend returned ${response.status}` }));
      return NextResponse.json(
        { success: false, error: errorData.error || `Failed to resume job` },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error resuming TTS batch job:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to resume TTS batch job' },
      { status: 503 }
    );
  }
}
