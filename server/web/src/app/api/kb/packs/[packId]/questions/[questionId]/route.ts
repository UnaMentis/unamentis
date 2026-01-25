import { NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

interface RouteParams {
  params: Promise<{ packId: string; questionId: string }>;
}

/**
 * DELETE /api/kb/packs/[packId]/questions/[questionId]
 * Remove a question from a pack
 */
export async function DELETE(request: Request, { params }: RouteParams) {
  try {
    const { packId, questionId } = await params;
    const response = await fetch(`${BACKEND_URL}/api/kb/packs/${packId}/questions/${questionId}`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
      },
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: 'Unknown error' }));
      return NextResponse.json(
        { success: false, error: error.error || `Backend returned ${response.status}` },
        { status: response.status }
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error) {
    console.error('Error removing question from pack:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to remove question' },
      { status: 503 }
    );
  }
}
