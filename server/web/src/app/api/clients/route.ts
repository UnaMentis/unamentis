import { NextResponse } from 'next/server';
import { mockClients } from '@/lib/mock-data';

const BACKEND_URL = process.env.BACKEND_URL || '';

export async function GET() {
  // Try to fetch from backend first
  if (BACKEND_URL) {
    try {
      const response = await fetch(`${BACKEND_URL}/api/clients`, {
        next: { revalidate: 10 },
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
  const clients = [...mockClients];

  return NextResponse.json({
    clients,
    total: clients.length,
    online: clients.filter(c => c.status === 'online').length,
    idle: clients.filter(c => c.status === 'idle').length,
    offline: clients.filter(c => c.status === 'offline').length,
  });
}
