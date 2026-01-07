/**
 * Realtime Token API Route
 *
 * Generates ephemeral tokens for OpenAI Realtime API WebRTC connections.
 * This endpoint should be called client-side before establishing WebRTC connection.
 */

import { NextRequest, NextResponse } from 'next/server';

interface TokenRequest {
  model?: string;
  voice?: string;
}

interface OpenAISessionResponse {
  id: string;
  object: string;
  model: string;
  modalities: string[];
  instructions: string;
  voice: string;
  client_secret: {
    value: string;
    expires_at: number;
  };
}

export async function POST(request: NextRequest) {
  try {
    // Get OpenAI API key from environment
    const apiKey = process.env.OPENAI_API_KEY;

    if (!apiKey) {
      console.error('[Realtime Token] OPENAI_API_KEY not configured');
      return NextResponse.json(
        { error: 'OpenAI API key not configured' },
        { status: 500 }
      );
    }

    // Parse request body
    let body: TokenRequest = {};
    try {
      body = await request.json();
    } catch {
      // Empty body is OK, we'll use defaults
    }

    const model = body.model || 'gpt-4o-realtime-preview-2024-12-17';
    const voice = body.voice || 'coral';

    // Request ephemeral token from OpenAI
    const response = await fetch('https://api.openai.com/v1/realtime/sessions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        voice,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('[Realtime Token] OpenAI API error:', response.status, errorText);
      return NextResponse.json(
        { error: 'Failed to get ephemeral token', details: errorText },
        { status: response.status }
      );
    }

    const data: OpenAISessionResponse = await response.json();

    // Return just the token value
    return NextResponse.json({
      token: data.client_secret.value,
      expiresAt: data.client_secret.expires_at,
      model: data.model,
      voice: data.voice,
    });

  } catch (error) {
    console.error('[Realtime Token] Unexpected error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
