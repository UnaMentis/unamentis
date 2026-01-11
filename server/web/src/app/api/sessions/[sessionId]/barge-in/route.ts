import { NextResponse, NextRequest } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || '';

type Params = Promise<{ sessionId: string }>;

/**
 * Handle a barge-in/interruption event
 * POST /api/sessions/{sessionId}/barge-in
 */
export async function POST(request: NextRequest, { params }: { params: Params }) {
  const { sessionId } = await params;

  if (!BACKEND_URL) {
    return NextResponse.json({ error: 'Backend not configured' }, { status: 503 });
  }

  try {
    const body = await request.json();
    const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/barge-in`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    const data = await response.json();
    return NextResponse.json(data, { status: response.status });
  } catch (error) {
    console.error('Failed to handle barge-in:', error);
    return NextResponse.json({ error: 'Failed to handle barge-in' }, { status: 500 });
  }
}
