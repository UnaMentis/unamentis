import { NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || '';

/**
 * Get FOV context system health status
 * GET /api/fov/health
 */
export async function GET() {
  if (!BACKEND_URL) {
    return NextResponse.json({
      status: 'unavailable',
      error: 'Backend not configured',
      sessions: { total: 0, active: 0, paused: 0 },
    });
  }

  try {
    const response = await fetch(`${BACKEND_URL}/api/fov/health`, {
      next: { revalidate: 0 },
    });

    if (response.ok) {
      const data = await response.json();
      return NextResponse.json(data);
    }

    return NextResponse.json(
      {
        status: 'error',
        error: `Backend error: ${response.status}`,
        sessions: { total: 0, active: 0, paused: 0 },
      },
      { status: response.status }
    );
  } catch (error) {
    console.error('Failed to fetch FOV health:', error);
    return NextResponse.json(
      {
        status: 'error',
        error: 'Failed to connect to backend',
        sessions: { total: 0, active: 0, paused: 0 },
      },
      { status: 500 }
    );
  }
}
