import { NextRequest, NextResponse } from 'next/server';
import { mockLogs } from '@/lib/mock-data';
import type { LogEntry } from '@/types';

const BACKEND_URL = process.env.BACKEND_URL || '';

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const limit = parseInt(searchParams.get('limit') || '500');
  const offset = parseInt(searchParams.get('offset') || '0');
  const level = searchParams.get('level') || '';
  const search = searchParams.get('search') || '';
  const clientId = searchParams.get('client_id') || '';

  // Try to fetch from backend first
  if (BACKEND_URL) {
    try {
      const url = new URL(`${BACKEND_URL}/api/logs`);
      url.searchParams.set('limit', String(limit));
      url.searchParams.set('offset', String(offset));
      if (level) url.searchParams.set('level', level);
      if (search) url.searchParams.set('search', search);
      if (clientId) url.searchParams.set('client_id', clientId);

      const response = await fetch(url.toString(), {
        next: { revalidate: 2 },
      });
      if (response.ok) {
        const data = await response.json();
        return NextResponse.json(data);
      }
    } catch {
      // Fall through to mock data
    }
  }

  // Return mock data with filtering
  let filtered: LogEntry[] = [...mockLogs];

  if (level) {
    const levels = level.split(',');
    filtered = filtered.filter(l => levels.includes(l.level));
  }

  if (search) {
    const searchLower = search.toLowerCase();
    filtered = filtered.filter(
      l => l.message.toLowerCase().includes(searchLower) || l.label.toLowerCase().includes(searchLower)
    );
  }

  if (clientId) {
    filtered = filtered.filter(l => l.client_id === clientId);
  }

  // Sort by received_at descending
  filtered.sort((a, b) => b.received_at - a.received_at);

  const paginated = filtered.slice(offset, offset + limit);

  return NextResponse.json({
    logs: paginated,
    total: filtered.length,
    limit,
    offset,
  });
}

export async function POST(request: NextRequest) {
  // Proxy to backend
  if (BACKEND_URL) {
    try {
      const body = await request.json();
      const response = await fetch(`${BACKEND_URL}/api/logs`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Client-ID': request.headers.get('X-Client-ID') || 'unknown',
          'X-Client-Name': request.headers.get('X-Client-Name') || 'Unknown',
        },
        body: JSON.stringify(body),
      });
      const data = await response.json();
      return NextResponse.json(data);
    } catch {
      return NextResponse.json({ error: 'Backend unavailable' }, { status: 503 });
    }
  }

  return NextResponse.json({ status: 'ok', note: 'Mock mode - log not stored' });
}

export async function DELETE() {
  if (BACKEND_URL) {
    try {
      await fetch(`${BACKEND_URL}/api/logs`, { method: 'DELETE' });
    } catch {
      // Ignore
    }
  }
  return NextResponse.json({ status: 'ok' });
}
