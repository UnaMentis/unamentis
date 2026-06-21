/**
 * Data source provenance tracking for the Operations Console.
 *
 * fetchWithFallback in api-client.ts records whether each request was served
 * with live backend data, fell back to mock data, or was rejected by auth.
 * UI components (the DataSourceBanner) subscribe through the
 * useSyncExternalStore-compatible subscribe/getSnapshot helpers so the console
 * never silently presents sample data as live telemetry.
 *
 * This module also owns the management API auth token used for the
 * Authorization header: a runtime token persisted in localStorage takes
 * precedence, with NEXT_PUBLIC_MGMT_API_TOKEN as the dev-time fallback.
 */

export type DataSourceMode = 'live' | 'mock-fallback' | 'auth-required';

export interface DataSourceStatus {
  /**
   * Overall mode. 'auth-required' wins over 'mock-fallback' because an auth
   * failure means the backend is reachable but rejecting us, and we must not
   * paper over that with sample data.
   */
  mode: DataSourceMode;
  /** Endpoints currently served from mock fallback (backend unreachable or erroring). */
  degradedEndpoints: string[];
  /** Endpoints that returned 401/403 (authentication required). */
  authRequiredEndpoints: string[];
  lastFallbackAt: number | null;
  lastAuthFailureAt: number | null;
}

const TOKEN_STORAGE_KEY = 'unamentis.mgmt-api-token';

// Internal mutable state
const degradedEndpoints = new Set<string>();
const authRequiredEndpoints = new Set<string>();
let lastFallbackAt: number | null = null;
let lastAuthFailureAt: number | null = null;

const listeners = new Set<() => void>();

const INITIAL_STATUS: DataSourceStatus = Object.freeze({
  mode: 'live' as DataSourceMode,
  degradedEndpoints: [],
  authRequiredEndpoints: [],
  lastFallbackAt: null,
  lastAuthFailureAt: null,
});

let snapshot: DataSourceStatus = INITIAL_STATUS;

function buildSnapshot(): DataSourceStatus {
  const mode: DataSourceMode =
    authRequiredEndpoints.size > 0
      ? 'auth-required'
      : degradedEndpoints.size > 0
        ? 'mock-fallback'
        : 'live';
  return {
    mode,
    degradedEndpoints: [...degradedEndpoints].sort(),
    authRequiredEndpoints: [...authRequiredEndpoints].sort(),
    lastFallbackAt,
    lastAuthFailureAt,
  };
}

function emit(): void {
  snapshot = buildSnapshot();
  for (const listener of listeners) {
    listener();
  }
}

/** Strip query strings so '/api/metrics?limit=50' and '?limit=20' count as one endpoint. */
function normalizeEndpoint(endpoint: string): string {
  return endpoint.split('?')[0];
}

/** Record that an endpoint was served with live backend data. */
export function recordLiveData(endpoint: string): void {
  const key = normalizeEndpoint(endpoint);
  const wasDegraded = degradedEndpoints.delete(key);
  const wasAuthRequired = authRequiredEndpoints.delete(key);
  if (wasDegraded || wasAuthRequired) {
    emit();
  }
}

/** Record that an endpoint fell back to mock data (backend unreachable or erroring). */
export function recordMockFallback(endpoint: string): void {
  degradedEndpoints.add(normalizeEndpoint(endpoint));
  lastFallbackAt = Date.now();
  emit();
}

/** Record that an endpoint was rejected with 401/403. */
export function recordAuthRequired(endpoint: string): void {
  authRequiredEndpoints.add(normalizeEndpoint(endpoint));
  lastAuthFailureAt = Date.now();
  emit();
}

/**
 * Clear the auth-required state, e.g. after the operator enters a new token,
 * so the next poll cycle can re-test against the backend.
 */
export function clearAuthRequired(): void {
  if (authRequiredEndpoints.size === 0) {
    return;
  }
  authRequiredEndpoints.clear();
  emit();
}

/** Reset all tracked state. Intended for tests. */
export function resetDataSourceStatus(): void {
  degradedEndpoints.clear();
  authRequiredEndpoints.clear();
  lastFallbackAt = null;
  lastAuthFailureAt = null;
  emit();
}

/** Current provenance snapshot (stable identity between mutations). */
export function getDataSourceStatus(): DataSourceStatus {
  return snapshot;
}

/** Server-side snapshot for useSyncExternalStore hydration. */
export function getServerDataSourceStatus(): DataSourceStatus {
  return INITIAL_STATUS;
}

/** Subscribe to provenance changes. Returns an unsubscribe function. */
export function subscribeDataSourceStatus(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

// =============================================================================
// Management API auth token
// =============================================================================

/**
 * The token sent as 'Authorization: Bearer <token>' on management API calls.
 * Runtime token from localStorage wins; NEXT_PUBLIC_MGMT_API_TOKEN is the
 * build-time dev fallback. Returns '' when no token is configured.
 */
export function getMgmtApiToken(): string {
  if (typeof window !== 'undefined') {
    try {
      const stored = window.localStorage.getItem(TOKEN_STORAGE_KEY);
      if (stored) {
        return stored;
      }
    } catch {
      // localStorage unavailable (privacy mode); fall through to env token.
    }
  }
  return process.env.NEXT_PUBLIC_MGMT_API_TOKEN || '';
}

/**
 * Persist (or clear, with an empty string) the runtime management API token.
 * Clears any auth-required state so the next poll re-tests with the new token.
 */
export function setMgmtApiToken(token: string): void {
  if (typeof window !== 'undefined') {
    try {
      if (token) {
        window.localStorage.setItem(TOKEN_STORAGE_KEY, token);
      } else {
        window.localStorage.removeItem(TOKEN_STORAGE_KEY);
      }
    } catch {
      // localStorage unavailable; the env token (if any) still applies.
    }
  }
  clearAuthRequired();
}

/** Whether any management API token (runtime or env) is configured. */
export function hasMgmtApiToken(): boolean {
  return getMgmtApiToken().length > 0;
}
