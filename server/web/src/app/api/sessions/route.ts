import { NextResponse, NextRequest } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || '';

/**
 * List all FOV sessions
 * GET /api/sessions
 */
export async function GET() {
  if (!BACKEND_URL) {
    return NextResponse.json({
      sessions: [],
      error: 'Backend not configured',
    });
  }

  try {
    const response = await fetch(`${BACKEND_URL}/api/sessions`, {
      next: { revalidate: 0 },
    });
    if (response.ok) {
      const data = await response.json();
      return NextResponse.json(data);
    }
    return NextResponse.json(
      { error: `Backend error: ${response.status}` },
      { status: response.status }
    );
  } catch (error) {
    console.error('Failed to fetch sessions:', error);
    return NextResponse.json({ error: 'Failed to fetch sessions', sessions: [] }, { status: 500 });
  }
}

/**
 * Create a new FOV session
 * POST /api/sessions
 */
export async function POST(request: NextRequest) {
  if (!BACKEND_URL) {
    return NextResponse.json({ error: 'Backend not configured' }, { status: 503 });
  }

  try {
    const body = await request.json();
    const response = await fetch(`${BACKEND_URL}/api/sessions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    const data = await response.json();
    return NextResponse.json(data, { status: response.status });
  } catch (error) {
    console.error('Failed to create session:', error);
    return NextResponse.json({ error: 'Failed to create session' }, { status: 500 });
  }
}
