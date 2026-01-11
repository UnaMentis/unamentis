import { NextResponse, NextRequest } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || '';

type Params = Promise<{ sessionId: string }>;

/**
 * Analyze an LLM response for confidence
 * POST /api/sessions/{sessionId}/analyze-response
 */
export async function POST(request: NextRequest, { params }: { params: Params }) {
  const { sessionId } = await params;

  if (!BACKEND_URL) {
    return NextResponse.json({ error: 'Backend not configured' }, { status: 503 });
  }

  try {
    const body = await request.json();
    const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/analyze-response`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    const data = await response.json();
    return NextResponse.json(data, { status: response.status });
  } catch (error) {
    console.error('Failed to analyze response:', error);
    return NextResponse.json({ error: 'Failed to analyze response' }, { status: 500 });
  }
}
