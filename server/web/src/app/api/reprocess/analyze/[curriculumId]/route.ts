import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * POST /api/reprocess/analyze/[curriculumId]
 * Trigger analysis of a curriculum
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ curriculumId: string }> }
) {
  const { curriculumId } = await params;

  try {
    let body = {};
    if (request.headers.get('content-type')?.includes('application/json')) {
      try {
        body = await request.json();
      } catch {
        // Empty body is fine
      }
    }

    const response = await fetch(`${BACKEND_URL}/api/reprocess/analyze/${curriculumId}`, {
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
    console.error('Error analyzing curriculum:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to analyze curriculum' },
      { status: 503 }
    );
  }
}

/**
 * GET /api/reprocess/analyze/[curriculumId]
 * Get cached analysis results
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ curriculumId: string }> }
) {
  const { curriculumId } = await params;

  try {
    const response = await fetch(`${BACKEND_URL}/api/reprocess/analysis/${curriculumId}`, {
      cache: 'no-store',
    });

    if (!response.ok) {
      throw new Error(`Backend returned ${response.status}`);
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error fetching analysis:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to fetch analysis' },
      { status: 503 }
    );
  }
}
