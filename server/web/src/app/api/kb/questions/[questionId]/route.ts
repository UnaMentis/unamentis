import { NextResponse } from 'next/server';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

interface RouteParams {
  params: Promise<{ questionId: string }>;
}

/**
 * GET /api/kb/questions/[questionId]
 * Get a question by ID
 */
export async function GET(request: Request, { params }: RouteParams) {
  try {
    const { questionId } = await params;
    const response = await fetch(`${BACKEND_URL}/api/kb/questions/${questionId}`, {
      headers: {
        'Content-Type': 'application/json',
      },
      next: { revalidate: 0 },
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
    console.error('Error fetching question:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to fetch question' },
      { status: 503 }
    );
  }
}

/**
 * PATCH /api/kb/questions/[questionId]
 * Update a question
 */
export async function PATCH(request: Request, { params }: RouteParams) {
  try {
    const { questionId } = await params;
    const body = await request.json();

    const response = await fetch(`${BACKEND_URL}/api/kb/questions/${questionId}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
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
    console.error('Error updating question:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to update question' },
      { status: 503 }
    );
  }
}

/**
 * DELETE /api/kb/questions/[questionId]
 * Delete a question
 */
export async function DELETE(request: Request, { params }: RouteParams) {
  try {
    const { questionId } = await params;
    const response = await fetch(`${BACKEND_URL}/api/kb/questions/${questionId}`, {
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
    console.error('Error deleting question:', error);
    return NextResponse.json(
      { success: false, error: 'Failed to delete question' },
      { status: 503 }
    );
  }
}
