import { NextResponse } from 'next/server';
import { mockModels } from '@/lib/mock-data';

const BACKEND_URL = process.env.BACKEND_URL || '';

export async function GET() {
  // Try to fetch from backend first
  if (BACKEND_URL) {
    try {
      const response = await fetch(`${BACKEND_URL}/api/models`, {
        next: { revalidate: 60 },
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
  const models = [...mockModels];

  return NextResponse.json({
    models,
    total: models.length,
    by_type: {
      llm: models.filter(m => m.type === 'llm').length,
      stt: models.filter(m => m.type === 'stt').length,
      tts: models.filter(m => m.type === 'tts').length,
    },
  });
}
