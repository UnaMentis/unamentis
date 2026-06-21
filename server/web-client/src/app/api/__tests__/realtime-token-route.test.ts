/**
 * Realtime Token API Route Tests
 *
 * The route mints PAID OpenAI Realtime sessions, so these tests pin the
 * denial-of-wallet defenses: auth-required (fail closed), per-identity
 * throttle, global daily cap, and no upstream-error leakage.
 */

import { describe, it, expect, beforeEach, afterEach, vi, type Mock } from 'vitest';
import { NextRequest } from 'next/server';
import { POST } from '../realtime/token/route';
import { __resetRateState } from '../realtime/token/rate-limit';

const URL = 'http://localhost:3000/api/realtime/token';

interface FetchScenario {
  meOk?: boolean;
  meBody?: unknown;
  openaiOk?: boolean;
  openaiBody?: unknown;
  openaiText?: string;
}

function mockFetch(s: FetchScenario = {}) {
  const {
    meOk = true,
    meBody = { id: 'user-1' },
    openaiOk = true,
    openaiBody = {
      client_secret: { value: 'ephemeral-abc', expires_at: 12345 },
      model: 'gpt-4o-realtime-preview-2024-12-17',
      voice: 'coral',
    },
    openaiText = '',
  } = s;
  (global.fetch as Mock).mockImplementation(async (url: string) => {
    if (String(url).includes('/api/auth/me')) {
      return { ok: meOk, status: meOk ? 200 : 401, json: async () => meBody };
    }
    return {
      ok: openaiOk,
      status: openaiOk ? 200 : 400,
      json: async () => openaiBody,
      text: async () => openaiText,
    };
  });
}

function authedRequest() {
  return new NextRequest(URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer good-token' },
    body: JSON.stringify({ model: 'gpt-4o-realtime-preview', voice: 'coral' }),
  });
}

describe('Realtime Token Route (denial-of-wallet defenses)', () => {
  const ORIGINAL_ENV = { ...process.env };

  beforeEach(() => {
    vi.clearAllMocks();
    global.fetch = vi.fn();
    __resetRateState();
    process.env.OPENAI_API_KEY = 'test-key';
    delete process.env.REALTIME_TOKEN_REQUIRE_AUTH;
    delete process.env.REALTIME_TOKENS_PER_MINUTE;
    delete process.env.REALTIME_DAILY_TOKEN_CAP;
  });

  afterEach(() => {
    process.env = { ...ORIGINAL_ENV };
  });

  it('returns 500 when OPENAI_API_KEY is not configured', async () => {
    delete process.env.OPENAI_API_KEY;
    mockFetch();
    const res = await POST(authedRequest());
    expect(res.status).toBe(500);
  });

  it('rejects an unauthenticated mint with 401 and never calls OpenAI', async () => {
    mockFetch();
    const req = new NextRequest(URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }, // no Authorization
      body: JSON.stringify({}),
    });
    const res = await POST(req);
    expect(res.status).toBe(401);
    // No call should have reached the OpenAI sessions endpoint.
    const calledOpenAI = (global.fetch as Mock).mock.calls.some((c) =>
      String(c[0]).includes('api.openai.com')
    );
    expect(calledOpenAI).toBe(false);
  });

  it('rejects with 401 when the management API does not validate the token', async () => {
    mockFetch({ meOk: false });
    const res = await POST(authedRequest());
    expect(res.status).toBe(401);
  });

  it('mints a token on the authenticated happy path', async () => {
    mockFetch();
    const res = await POST(authedRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.token).toBe('ephemeral-abc');
    expect(body.expiresAt).toBe(12345);
  });

  it('enforces the per-identity per-minute throttle', async () => {
    process.env.REALTIME_TOKENS_PER_MINUTE = '1';
    mockFetch();
    const first = await POST(authedRequest());
    expect(first.status).toBe(200);
    const second = await POST(authedRequest());
    expect(second.status).toBe(429);
  });

  it('enforces the global daily wallet cap', async () => {
    process.env.REALTIME_DAILY_TOKEN_CAP = '1';
    process.env.REALTIME_TOKENS_PER_MINUTE = '100'; // isolate the daily cap
    mockFetch();
    const first = await POST(authedRequest());
    expect(first.status).toBe(200);
    const second = await POST(authedRequest());
    expect(second.status).toBe(429);
  });

  it('does not leak the upstream OpenAI error body to the client', async () => {
    mockFetch({ openaiOk: false, openaiText: 'sk-secret quota detail from OpenAI' });
    const res = await POST(authedRequest());
    expect(res.status).toBe(502);
    const body = await res.json();
    expect(JSON.stringify(body)).not.toContain('OpenAI');
    expect(body.details).toBeUndefined();
  });

  it('refuses the mint when the durable budget API returns 429', async () => {
    (global.fetch as Mock).mockImplementation(async (url: string) => {
      if (String(url).includes('/api/auth/me')) {
        return { ok: true, status: 200, json: async () => ({ id: 'user-1' }) };
      }
      if (String(url).includes('/api/realtime/budget/reserve')) {
        return {
          ok: false,
          status: 429,
          json: async () => ({ allowed: false, reason: 'daily token budget exceeded' }),
        };
      }
      return {
        ok: true,
        status: 200,
        json: async () => ({
          client_secret: { value: 'ephemeral-abc', expires_at: 12345 },
          model: 'gpt-4o-realtime-preview-2024-12-17',
          voice: 'coral',
        }),
        text: async () => '',
      };
    });
    const res = await POST(authedRequest());
    expect(res.status).toBe(429);
    // The exhausted budget must stop the paid upstream call.
    const calledOpenAI = (global.fetch as Mock).mock.calls.some((c) =>
      String(c[0]).includes('api.openai.com')
    );
    expect(calledOpenAI).toBe(false);
  });

  it('falls back to in-memory guards when the budget API is unreachable', async () => {
    (global.fetch as Mock).mockImplementation(async (url: string) => {
      if (String(url).includes('/api/auth/me')) {
        return { ok: true, status: 200, json: async () => ({ id: 'user-1' }) };
      }
      if (String(url).includes('/api/realtime/budget/reserve')) {
        throw new Error('connection refused');
      }
      return {
        ok: true,
        status: 200,
        json: async () => ({
          client_secret: { value: 'ephemeral-abc', expires_at: 12345 },
          model: 'gpt-4o-realtime-preview-2024-12-17',
          voice: 'coral',
        }),
        text: async () => '',
      };
    });
    const res = await POST(authedRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.token).toBe('ephemeral-abc');
  });

  it('allows minting without auth when REALTIME_TOKEN_REQUIRE_AUTH=false', async () => {
    process.env.REALTIME_TOKEN_REQUIRE_AUTH = 'false';
    mockFetch();
    const req = new NextRequest(URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }, // no Authorization
      body: JSON.stringify({}),
    });
    const res = await POST(req);
    expect(res.status).toBe(200);
    // Auth validation should be skipped entirely.
    const calledMe = (global.fetch as Mock).mock.calls.some((c) =>
      String(c[0]).includes('/api/auth/me')
    );
    expect(calledMe).toBe(false);
  });
});
