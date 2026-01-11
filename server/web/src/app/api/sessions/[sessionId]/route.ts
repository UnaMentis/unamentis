import { NextResponse, NextRequest } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || '';

type Params = Promise<{ sessionId: string }>;

/**
 * Get session details
 * GET /api/sessions/{sessionId}
 */
export async function GET(_request: NextRequest, { params }: { params: Params }) {
  const { sessionId } = await params;

  if (!BACKEND_URL) {
    return NextResponse.json({ error: 'Backend not configured' }, { status: 503 });
  }

  try {
    const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}`, {
      next: { revalidate: 0 },
    });

    if (!response.ok) {
      return NextResponse.json(
        { error: `Session not found or error: ${response.status}` },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Failed to fetch session:', error);
    return NextResponse.json({ error: 'Failed to fetch session' }, { status: 500 });
  }
}

/**
 * Delete session
 * DELETE /api/sessions/{sessionId}
 */
export async function DELETE(_request: NextRequest, { params }: { params: Params }) {
  const { sessionId } = await params;

  if (!BACKEND_URL) {
    return NextResponse.json({ error: 'Backend not configured' }, { status: 503 });
  }

  try {
    const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}`, {
      method: 'DELETE',
    });

    const data = await response.json();
    return NextResponse.json(data, { status: response.status });
  } catch (error) {
    console.error('Failed to delete session:', error);
    return NextResponse.json({ error: 'Failed to delete session' }, { status: 500 });
  }
}
