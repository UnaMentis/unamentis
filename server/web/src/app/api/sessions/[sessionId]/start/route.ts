import { NextResponse, NextRequest } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || '';

type Params = Promise<{ sessionId: string }>;

/**
 * Start a session
 * POST /api/sessions/{sessionId}/start
 */
export async function POST(_request: NextRequest, { params }: { params: Params }) {
  const { sessionId } = await params;

  if (!BACKEND_URL) {
    return NextResponse.json({ error: 'Backend not configured' }, { status: 503 });
  }

  try {
    const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/start`, {
      method: 'POST',
    });

    const data = await response.json();
    return NextResponse.json(data, { status: response.status });
  } catch (error) {
    console.error('Failed to start session:', error);
    return NextResponse.json({ error: 'Failed to start session' }, { status: 500 });
  }
}
