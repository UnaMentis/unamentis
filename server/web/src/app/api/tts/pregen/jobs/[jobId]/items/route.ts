import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * GET /api/tts/pregen/jobs/[jobId]/items
 * Get items for a TTS batch job
 *
 * Query parameters:
 * - status: Filter by item status (optional)
 * - limit: Max results (default 50)
 * - offset: Pagination offset (default 0)
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ jobId: string }> }
) {
  const { jobId } = await params;
  const searchParams = request.nextUrl.searchParams;
  const queryParams = new URLSearchParams();

  const status = searchParams.get('status');
  const limit = searchParams.get('limit');
  const offset = searchParams.get('offset');

  if (status) queryParams.set('status', status);
  if (limit) queryParams.set('limit', limit);
  if (offset) queryParams.set('offset', offset);

  const query = queryParams.toString();

  try {
    const url = `${BACKEND_URL}/api/tts/pregen/jobs/${jobId}/items${query ? `?${query}` : ''}`;

    const response = await fetch(url, {
      cache: 'no-store',
    });

    if (!response.ok) {
      const errorData = await response
        .json()
        .catch(() => ({ error: `Backend returned ${response.status}` }));
      return NextResponse.json(
        { success: false, items: [], error: errorData.error || `Failed to fetch items` },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error fetching TTS job items:', error);
    return NextResponse.json(
      { success: false, items: [], error: 'Failed to fetch job items' },
      { status: 503 }
    );
  }
}
