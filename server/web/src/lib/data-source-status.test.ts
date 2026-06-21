/**
 * Tests for the data source provenance store (T5/ND1).
 *
 * Pure module-level store, no network involved.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  getDataSourceStatus,
  getServerDataSourceStatus,
  subscribeDataSourceStatus,
  recordLiveData,
  recordMockFallback,
  recordAuthRequired,
  clearAuthRequired,
  resetDataSourceStatus,
  getMgmtApiToken,
  setMgmtApiToken,
  hasMgmtApiToken,
} from './data-source-status';

describe('data-source-status store', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetDataSourceStatus();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('starts in live mode with no degraded endpoints', () => {
    const status = getDataSourceStatus();
    expect(status.mode).toBe('live');
    expect(status.degradedEndpoints).toEqual([]);
    expect(status.authRequiredEndpoints).toEqual([]);
    expect(status.lastFallbackAt).toBeNull();
  });

  it('records mock fallback per endpoint and switches mode', () => {
    recordMockFallback('/api/stats');
    const status = getDataSourceStatus();
    expect(status.mode).toBe('mock-fallback');
    expect(status.degradedEndpoints).toEqual(['/api/stats']);
    expect(status.lastFallbackAt).not.toBeNull();
  });

  it('normalizes query strings so one endpoint is tracked once', () => {
    recordMockFallback('/api/metrics?limit=50');
    recordMockFallback('/api/metrics?limit=20');
    expect(getDataSourceStatus().degradedEndpoints).toEqual(['/api/metrics']);
  });

  it('clears a degraded endpoint when live data is served again', () => {
    recordMockFallback('/api/stats');
    recordMockFallback('/api/clients');
    recordLiveData('/api/stats');
    const status = getDataSourceStatus();
    expect(status.mode).toBe('mock-fallback');
    expect(status.degradedEndpoints).toEqual(['/api/clients']);

    recordLiveData('/api/clients');
    expect(getDataSourceStatus().mode).toBe('live');
  });

  it('auth-required wins over mock-fallback', () => {
    recordMockFallback('/api/stats');
    recordAuthRequired('/api/metrics');
    expect(getDataSourceStatus().mode).toBe('auth-required');
    expect(getDataSourceStatus().authRequiredEndpoints).toEqual(['/api/metrics']);
  });

  it('clearAuthRequired resets the auth state but keeps fallback state', () => {
    recordMockFallback('/api/stats');
    recordAuthRequired('/api/metrics');
    clearAuthRequired();
    const status = getDataSourceStatus();
    expect(status.mode).toBe('mock-fallback');
    expect(status.authRequiredEndpoints).toEqual([]);
  });

  it('notifies subscribers on changes and supports unsubscribe', () => {
    let calls = 0;
    const unsubscribe = subscribeDataSourceStatus(() => {
      calls += 1;
    });
    recordMockFallback('/api/stats');
    expect(calls).toBe(1);
    unsubscribe();
    recordMockFallback('/api/clients');
    expect(calls).toBe(1);
  });

  it('returns a stable snapshot identity between mutations', () => {
    recordMockFallback('/api/stats');
    const first = getDataSourceStatus();
    expect(getDataSourceStatus()).toBe(first);
    recordLiveData('/api/stats');
    expect(getDataSourceStatus()).not.toBe(first);
  });

  it('server snapshot is the stable initial status', () => {
    expect(getServerDataSourceStatus()).toBe(getServerDataSourceStatus());
    expect(getServerDataSourceStatus().mode).toBe('live');
  });
});

describe('management API token source', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetDataSourceStatus();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('returns empty string when no token is configured', () => {
    expect(getMgmtApiToken()).toBe('');
    expect(hasMgmtApiToken()).toBe(false);
  });

  it('falls back to NEXT_PUBLIC_MGMT_API_TOKEN when localStorage is empty', () => {
    vi.stubEnv('NEXT_PUBLIC_MGMT_API_TOKEN', 'env-token');
    expect(getMgmtApiToken()).toBe('env-token');
  });

  it('prefers the runtime token persisted in localStorage over the env token', () => {
    vi.stubEnv('NEXT_PUBLIC_MGMT_API_TOKEN', 'env-token');
    setMgmtApiToken('runtime-token');
    expect(getMgmtApiToken()).toBe('runtime-token');
    expect(window.localStorage.getItem('unamentis.mgmt-api-token')).toBe('runtime-token');
  });

  it('clears the runtime token when set to an empty string', () => {
    setMgmtApiToken('runtime-token');
    setMgmtApiToken('');
    expect(window.localStorage.getItem('unamentis.mgmt-api-token')).toBeNull();
    expect(getMgmtApiToken()).toBe('');
  });

  it('saving a token clears the auth-required state so polling can retry', () => {
    recordAuthRequired('/api/metrics');
    expect(getDataSourceStatus().mode).toBe('auth-required');
    setMgmtApiToken('fresh-token');
    expect(getDataSourceStatus().mode).toBe('live');
  });
});
