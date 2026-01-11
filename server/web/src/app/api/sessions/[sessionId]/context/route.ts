import { NextResponse, NextRequest } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || '';

type Params = Promise<{ sessionId: string }>;

/**
 * Get current FOV context state
 * GET /api/sessions/{sessionId}/context
 */
export async function GET(_request: NextRequest, { params }: { params: Params }) {
  const { sessionId } = await params;

  if (!BACKEND_URL) {
    return NextResponse.json({ error: 'Backend not configured' }, { status: 503 });
  }

  try {
    const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/context`, {
      next: { revalidate: 0 },
    });

    if (!response.ok) {
      return NextResponse.json(
        { error: `Failed to get context: ${response.status}` },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Failed to fetch context:', error);
    return NextResponse.json({ error: 'Failed to fetch context' }, { status: 500 });
  }
}
