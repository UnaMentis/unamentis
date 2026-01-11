import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * GET /api/reprocess/jobs
 * List all reprocessing jobs
 *
 * Query parameters:
 * - status: Filter by status (optional)
 * - curriculumId: Filter by curriculum (optional)
 */
export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const status = searchParams.get('status');
  const curriculumId = searchParams.get('curriculumId');

  try {
    const params = new URLSearchParams();
    if (status) params.set('status', status);
    if (curriculumId) params.set('curriculumId', curriculumId);

    const queryString = params.toString();
    const url = queryString
      ? `${BACKEND_URL}/api/reprocess/jobs?${queryString}`
      : `${BACKEND_URL}/api/reprocess/jobs`;

    const response = await fetch(url, {
      cache: 'no-store', // Always get fresh data for jobs
    });

    if (!response.ok) {
      throw new Error(`Backend returned ${response.status}`);
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error fetching reprocess jobs:', error);
    return NextResponse.json(
      { success: false, jobs: [], error: 'Failed to fetch reprocess jobs' },
      { status: 503 }
    );
  }
}

/**
 * POST /api/reprocess/jobs
 * Start a new reprocessing job
 *
 * Request body: ReprocessConfig
 */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();

    const response = await fetch(`${BACKEND_URL}/api/reprocess/jobs`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    const data = await response.json();

    if (!response.ok) {
      return NextResponse.json(data, { status: response.status });
    }

    return NextResponse.json(data);
  } catch (error) {
    console.error('Error starting reprocess:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to start reprocess' },
      { status: 503 }
    );
  }
}
