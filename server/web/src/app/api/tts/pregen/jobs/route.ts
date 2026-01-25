import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * GET /api/tts/pregen/jobs
 * List all TTS batch jobs
 *
 * Query parameters:
 * - status: Filter by status (optional)
 * - source_type: Filter by source type (optional)
 * - job_type: Filter by job type (optional)
 * - limit: Max results (default 50)
 * - offset: Pagination offset (default 0)
 */
export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const params = new URLSearchParams();

  // Forward query parameters
  const status = searchParams.get('status');
  const sourceType = searchParams.get('source_type');
  const jobType = searchParams.get('job_type');
  const limit = searchParams.get('limit');
  const offset = searchParams.get('offset');

  if (status) params.set('status', status);
  if (sourceType) params.set('source_type', sourceType);
  if (jobType) params.set('job_type', jobType);
  if (limit) params.set('limit', limit);
  if (offset) params.set('offset', offset);

  const query = params.toString();

  try {
    const url = `${BACKEND_URL}/api/tts/pregen/jobs${query ? `?${query}` : ''}`;

    const response = await fetch(url, {
      cache: 'no-store',
    });

    if (!response.ok) {
      const errorData = await response
        .json()
        .catch(() => ({ error: `Backend returned ${response.status}` }));
      return NextResponse.json(
        {
          success: false,
          jobs: [],
          error: errorData.error || `Backend returned ${response.status}`,
        },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error fetching TTS batch jobs:', error);
    return NextResponse.json(
      { success: false, jobs: [], error: 'Failed to fetch TTS batch jobs' },
      { status: 503 }
    );
  }
}

/**
 * POST /api/tts/pregen/jobs
 * Create a new TTS batch job
 *
 * Request body:
 * - name: Job name (required)
 * - source_type: 'knowledge-bowl' | 'curriculum' | 'custom' (required)
 * - source_id: Source identifier (optional, for KB/curriculum)
 * - profile_id: TTS profile ID (optional, either this or tts_config)
 * - tts_config: Inline TTS config (optional)
 * - items: Array of items for custom source (optional)
 * - output_format: Audio format (default 'wav')
 * - normalize_volume: Whether to normalize (default false)
 * - include_questions, include_answers, etc. for KB extraction
 */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();

    const response = await fetch(`${BACKEND_URL}/api/tts/pregen/jobs`, {
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
    console.error('Error creating TTS batch job:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to create TTS batch job' },
      { status: 503 }
    );
  }
}
