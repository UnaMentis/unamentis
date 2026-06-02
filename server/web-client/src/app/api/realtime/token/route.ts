/**
 * Realtime Token API Route
 *
 * Generates ephemeral tokens for OpenAI Realtime API WebRTC connections.
 * This endpoint mints PAID OpenAI sessions, so it is authenticated, rate-limited,
 * and capped to defend against denial-of-wallet abuse. It is called client-side
 * before establishing the WebRTC connection.
 */

import { NextRequest, NextResponse } from 'next/server';

const MANAGEMENT_API_URL = process.env.MANAGEMENT_API_URL || 'http://localhost:8766';

const MINUTE_MS = 60_000;
const DAY_MS = 86_400_000;

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

// Config is read at call time (not module load) so deployments and tests can
// adjust the guards via environment without reloading the module.
function getConfig() {
  return {
    // Fail closed: minting a paid session requires a valid user by default.
    // Set REALTIME_TOKEN_REQUIRE_AUTH=false only for fully local, no-auth dev.
    requireAuth: process.env.REALTIME_TOKEN_REQUIRE_AUTH !== 'false',
    // Per-identity rapid-abuse throttle (mints per rolling minute).
    perMinute: Number(process.env.REALTIME_TOKENS_PER_MINUTE ?? 10),
    // Global denial-of-wallet ceiling (mints per rolling day, per instance).
    dailyCap: Number(process.env.REALTIME_DAILY_TOKEN_CAP ?? 1000),
  };
}

// In-memory guard state (per server instance).
const perIdentity = new Map<string, number[]>();
let dayStart = 0;
let dayCount = 0;

/** Test-only: reset in-memory rate state between cases. */
export function __resetRateState(): void {
  perIdentity.clear();
  dayStart = 0;
  dayCount = 0;
}

function clientIp(request: NextRequest): string {
  const fwd = request.headers.get('x-forwarded-for');
  if (fwd) return fwd.split(',')[0].trim();
  return request.headers.get('x-real-ip') ?? 'unknown';
}

/** Reserve one slot against the global daily cap. Returns false when exhausted. */
function reserveDaily(now: number, dailyCap: number): boolean {
  if (now - dayStart >= DAY_MS) {
    dayStart = now;
    dayCount = 0;
  }
  if (dayCount >= dailyCap) {
    return false;
  }
  dayCount += 1;
  return true;
}

/** Record a hit for an identity. Returns false when over the per-minute limit. */
function allowIdentity(identity: string, now: number, perMinute: number): boolean {
  const recent = (perIdentity.get(identity) ?? []).filter((t) => now - t < MINUTE_MS);
  if (recent.length >= perMinute) {
    perIdentity.set(identity, recent);
    return false;
  }
  recent.push(now);
  perIdentity.set(identity, recent);
  return true;
}

/**
 * Validate the caller against the Management API.
 * Returns { ok, userId } where ok is false (fail closed) on any error.
 */
async function authenticate(
  request: NextRequest
): Promise<{ ok: boolean; userId: string | null }> {
  const authHeader = request.headers.get('authorization');
  if (!authHeader) {
    return { ok: false, userId: null };
  }
  try {
    const res = await fetch(`${MANAGEMENT_API_URL}/api/auth/me`, {
      method: 'GET',
      headers: { Authorization: authHeader },
    });
    if (!res.ok) {
      return { ok: false, userId: null };
    }
    const me = await res.json().catch(() => ({}));
    const id = me?.id ?? me?.user_id ?? me?.user?.id ?? null;
    return { ok: true, userId: id !== null ? String(id) : null };
  } catch {
    return { ok: false, userId: null };
  }
}

export async function POST(request: NextRequest) {
  try {
    const apiKey = process.env.OPENAI_API_KEY;

    if (!apiKey) {
      console.error('[Realtime Token] OPENAI_API_KEY not configured');
      return NextResponse.json(
        { error: 'OpenAI API key not configured' },
        { status: 500 }
      );
    }

    const config = getConfig();

    // 1. Authentication (fail closed). Bind the rate-limit identity to the user.
    let identity = clientIp(request);
    if (config.requireAuth) {
      const auth = await authenticate(request);
      if (!auth.ok) {
        return NextResponse.json({ error: 'Authentication required' }, { status: 401 });
      }
      if (auth.userId) {
        identity = auth.userId;
      }
    }

    const now = Date.now();

    // 2. Per-identity throttle (rapid-abuse guard).
    if (!allowIdentity(identity, now, config.perMinute)) {
      return NextResponse.json(
        { error: 'Rate limit exceeded. Please slow down.' },
        { status: 429 }
      );
    }

    // 3. Global daily wallet cap (denial-of-wallet ceiling).
    if (!reserveDaily(now, config.dailyCap)) {
      console.warn('[Realtime Token] Daily mint cap reached');
      return NextResponse.json(
        { error: 'Service temporarily unavailable. Please try again later.' },
        { status: 429 }
      );
    }

    // Parse request body (empty body is OK, we'll use defaults).
    let body: TokenRequest = {};
    try {
      body = await request.json();
    } catch {
      // Use defaults below.
    }

    const model = body.model || 'gpt-4o-realtime-preview-2024-12-17';
    const voice = body.voice || 'coral';

    // Request ephemeral token from OpenAI.
    const response = await fetch('https://api.openai.com/v1/realtime/sessions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ model, voice }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('[Realtime Token] OpenAI API error:', response.status, errorText);
      // Do not leak the upstream provider's error body to the client.
      return NextResponse.json({ error: 'Failed to get ephemeral token' }, { status: 502 });
    }

    const data: OpenAISessionResponse = await response.json();

    // Return just the token value.
    return NextResponse.json({
      token: data.client_secret.value,
      expiresAt: data.client_secret.expires_at,
      model: data.model,
      voice: data.voice,
    });
  } catch (error) {
    console.error('[Realtime Token] Unexpected error:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
