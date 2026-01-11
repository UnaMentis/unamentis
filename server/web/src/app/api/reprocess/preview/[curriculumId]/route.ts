import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

/**
 * POST /api/reprocess/preview/[curriculumId]
 * Preview what changes would be made without applying them
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

    const response = await fetch(`${BACKEND_URL}/api/reprocess/preview/${curriculumId}`, {
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
    console.error('Error generating preview:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to generate preview' },
      { status: 503 }
    );
  }
}
