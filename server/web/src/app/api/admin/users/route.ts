import { NextRequest, NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || '';

export async function GET() {
  if (BACKEND_URL) {
    try {
      const response = await fetch(`${BACKEND_URL}/api/admin/users`, {
        next: { revalidate: 10 },
      });
      if (response.ok) {
        const data = await response.json();
        return NextResponse.json(data);
      }
      // Return empty list if endpoint not implemented yet
      if (response.status === 404) {
        return NextResponse.json({
          users: [],
          total: 0,
          active: 0,
          admins: 0,
          message: 'Users endpoint not configured',
        });
      }
    } catch {
      // Fall through to mock data
    }
  }

  // Return mock data
  return NextResponse.json({
    users: [],
    total: 0,
    active: 0,
    admins: 0,
  });
}

export async function POST(request: NextRequest) {
  if (BACKEND_URL) {
    try {
      const body = await request.json();
      const response = await fetch(`${BACKEND_URL}/api/admin/users`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await response.json();
      return NextResponse.json(data, { status: response.status });
    } catch {
      return NextResponse.json({ error: 'Backend unavailable' }, { status: 503 });
    }
  }

  return NextResponse.json({ status: 'ok', note: 'Mock mode - user not created' });
}
