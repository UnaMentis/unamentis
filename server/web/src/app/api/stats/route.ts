import { NextResponse } from 'next/server';
import { getMockStats } from '@/lib/mock-data';

const BACKEND_URL = process.env.BACKEND_URL || '';

export async function GET() {
  // Try to fetch from backend first
  if (BACKEND_URL) {
    try {
      const response = await fetch(`${BACKEND_URL}/api/stats`, {
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
  return NextResponse.json(getMockStats());
}
