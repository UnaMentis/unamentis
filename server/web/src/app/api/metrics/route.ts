import { NextRequest, NextResponse } from 'next/server';
import { mockMetrics } from '@/lib/mock-data';

const BACKEND_URL = process.env.BACKEND_URL || '';

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const limit = parseInt(searchParams.get('limit') || '100');
  const clientId = searchParams.get('client_id') || '';

  // Try to fetch from backend first
  if (BACKEND_URL) {
    try {
      const url = new URL(`${BACKEND_URL}/api/metrics`);
      url.searchParams.set('limit', String(limit));
      if (clientId) url.searchParams.set('client_id', clientId);

      const response = await fetch(url.toString(), {
        next: { revalidate: 5 },
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
  let filtered = [...mockMetrics];

  if (clientId) {
    filtered = filtered.filter(m => m.client_id === clientId);
  }

  filtered.sort((a, b) => b.received_at - a.received_at);
  filtered = filtered.slice(0, limit);

  const avg = (arr: number[]) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0);

  return NextResponse.json({
    metrics: filtered,
    aggregates: {
      avg_e2e_latency: Math.round(avg(filtered.map(m => m.e2e_latency_median)) * 100) / 100,
      avg_llm_ttft: Math.round(avg(filtered.map(m => m.llm_ttft_median)) * 100) / 100,
      avg_stt_latency: Math.round(avg(filtered.map(m => m.stt_latency_median)) * 100) / 100,
      avg_tts_ttfb: Math.round(avg(filtered.map(m => m.tts_ttfb_median)) * 100) / 100,
      total_cost: Math.round(filtered.reduce((sum, m) => sum + m.total_cost, 0) * 10000) / 10000,
      total_sessions: filtered.length,
      total_turns: filtered.reduce((sum, m) => sum + m.turns_total, 0),
    },
  });
}

export async function POST(request: NextRequest) {
  if (BACKEND_URL) {
    try {
      const body = await request.json();
      const response = await fetch(`${BACKEND_URL}/api/metrics`, {
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

  return NextResponse.json({ status: 'ok', note: 'Mock mode - metrics not stored' });
}
