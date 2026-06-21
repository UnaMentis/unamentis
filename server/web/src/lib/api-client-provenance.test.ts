/**
 * Data provenance and auth behavior of fetchWithFallback (T5/ND1).
 *
 * Tests the REAL api-client code using MSW for network-level HTTP mocking.
 * No vi.mock of internal modules - per "Real Over Mock" philosophy.
 */
import { describe, it, expect, beforeAll, beforeEach, afterAll, afterEach } from 'vitest';
import { server, mswTestState, http, HttpResponse } from '@/test/msw-server';
import { getStats, getMetrics, ApiAuthError } from './api-client';
import { getDataSourceStatus, resetDataSourceStatus, setMgmtApiToken } from './data-source-status';
import { getMockStats } from './mock-data';

const BACKEND = 'http://localhost:8766';

const liveStats = {
  ...getMockStats(),
  total_logs: 4242,
};

describe('fetchWithFallback provenance and auth', () => {
  beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
  beforeEach(() => {
    window.localStorage.clear();
    setMgmtApiToken('');
    resetDataSourceStatus();
  });
  afterEach(() => {
    server.resetHandlers();
    mswTestState.reset();
  });
  afterAll(() => server.close());

  it('records live provenance when the backend responds', async () => {
    server.use(http.get(`${BACKEND}/api/stats`, () => HttpResponse.json(liveStats)));

    const stats = await getStats();
    expect(stats.total_logs).toBe(4242);
    expect(getDataSourceStatus().mode).toBe('live');
    expect(getDataSourceStatus().degradedEndpoints).toEqual([]);
  });

  it('records a mock fallback when the backend returns a server error', async () => {
    server.use(
      http.get(`${BACKEND}/api/stats`, () => HttpResponse.json({ error: 'boom' }, { status: 500 }))
    );

    const stats = await getStats();
    // Mock data is served, but the fallback is recorded, never silent.
    expect(stats).toBeTruthy();
    const status = getDataSourceStatus();
    expect(status.mode).toBe('mock-fallback');
    expect(status.degradedEndpoints).toEqual(['/api/stats']);
    expect(status.lastFallbackAt).not.toBeNull();
  });

  it('records a mock fallback on network failure', async () => {
    server.use(http.get(`${BACKEND}/api/stats`, () => HttpResponse.error()));

    await getStats();
    expect(getDataSourceStatus().mode).toBe('mock-fallback');
  });

  it('strips query strings when recording degraded endpoints', async () => {
    server.use(http.get(`${BACKEND}/api/metrics`, () => HttpResponse.error()));

    await getMetrics({ limit: 5 });
    expect(getDataSourceStatus().degradedEndpoints).toEqual(['/api/metrics']);
  });

  it('clears the degraded state once the backend recovers', async () => {
    server.use(http.get(`${BACKEND}/api/stats`, () => HttpResponse.error()));
    await getStats();
    expect(getDataSourceStatus().mode).toBe('mock-fallback');

    server.resetHandlers();
    server.use(http.get(`${BACKEND}/api/stats`, () => HttpResponse.json(liveStats)));
    await getStats();
    expect(getDataSourceStatus().mode).toBe('live');
  });

  it('throws ApiAuthError on 401 instead of returning mock data', async () => {
    server.use(
      http.get(`${BACKEND}/api/stats`, () =>
        HttpResponse.json({ error: 'unauthorized' }, { status: 401 })
      )
    );

    await expect(getStats()).rejects.toBeInstanceOf(ApiAuthError);
    const status = getDataSourceStatus();
    expect(status.mode).toBe('auth-required');
    expect(status.authRequiredEndpoints).toEqual(['/api/stats']);
    expect(status.lastAuthFailureAt).not.toBeNull();
  });

  it('treats 403 the same as 401', async () => {
    server.use(
      http.get(`${BACKEND}/api/stats`, () =>
        HttpResponse.json({ error: 'forbidden' }, { status: 403 })
      )
    );

    await expect(getStats()).rejects.toBeInstanceOf(ApiAuthError);
    expect(getDataSourceStatus().mode).toBe('auth-required');
  });

  it('sends Authorization header when a runtime token is set', async () => {
    setMgmtApiToken('operator-token');
    let seenAuth: string | null = null;
    server.use(
      http.get(`${BACKEND}/api/stats`, ({ request }) => {
        seenAuth = request.headers.get('authorization');
        return HttpResponse.json(liveStats);
      })
    );

    await getStats();
    expect(seenAuth).toBe('Bearer operator-token');
  });

  it('omits the Authorization header when no token is configured', async () => {
    let seenAuth: string | null = 'sentinel';
    server.use(
      http.get(`${BACKEND}/api/stats`, ({ request }) => {
        seenAuth = request.headers.get('authorization');
        return HttpResponse.json(liveStats);
      })
    );

    await getStats();
    expect(seenAuth).toBeNull();
  });

  it('a 401 followed by a valid token and a 200 returns to live mode', async () => {
    server.use(
      http.get(`${BACKEND}/api/stats`, () =>
        HttpResponse.json({ error: 'unauthorized' }, { status: 401 })
      )
    );
    await expect(getStats()).rejects.toBeInstanceOf(ApiAuthError);

    setMgmtApiToken('operator-token'); // clears the auth-required state
    server.resetHandlers();
    server.use(http.get(`${BACKEND}/api/stats`, () => HttpResponse.json(liveStats)));
    await getStats();
    expect(getDataSourceStatus().mode).toBe('live');
  });
});
