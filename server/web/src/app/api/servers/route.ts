import { NextRequest, NextResponse } from 'next/server';
import { mockServers } from '@/lib/mock-data';

const BACKEND_URL = process.env.BACKEND_URL || '';

export async function GET() {
  // Try to fetch from backend first
  if (BACKEND_URL) {
    try {
      const response = await fetch(`${BACKEND_URL}/api/servers`, {
        next: { revalidate: 30 },
      });
      if (response.ok) {
        const data = await response.json();
        return NextResponse.json(data);
      }
    } catch {
      // Fall through to mock data
    }
  }

  // Return mock data
  const servers = [...mockServers];

  return NextResponse.json({
    servers,
    total: servers.length,
    healthy: servers.filter(s => s.status === 'healthy').length,
    degraded: servers.filter(s => s.status === 'degraded').length,
    unhealthy: servers.filter(s => s.status === 'unhealthy').length,
  });
}

export async function POST(request: NextRequest) {
  if (BACKEND_URL) {
    try {
      const body = await request.json();
      const response = await fetch(`${BACKEND_URL}/api/servers`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await response.json();
      return NextResponse.json(data);
    } catch {
      return NextResponse.json({ error: 'Backend unavailable' }, { status: 503 });
    }
  }

  return NextResponse.json({ status: 'ok', note: 'Mock mode - server not added' });
}
