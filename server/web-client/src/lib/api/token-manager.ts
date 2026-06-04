/**
 * Token Manager
 *
 * Access tokens are held in memory only (never localStorage). The refresh token
 * is NOT held by JS at all: it lives in an HttpOnly cookie set by the auth proxy
 * (see app/api/auth/[...path]/route.ts), so an XSS cannot exfiltrate it. To know
 * whether a cookie session might exist after a reload, we keep a non-sensitive
 * JS-readable "session hint" flag in localStorage (not a credential).
 */

import type { TokenPair } from '@/types';

// Refresh tokens 1 minute before expiry
const REFRESH_BUFFER_MS = 60 * 1000;

// Non-sensitive flag indicating a refresh-token cookie may exist for this
// browser, so we should attempt a cookie-based refresh on load.
const STORAGE_KEY_SESSION = 'unamentis_session';

// Legacy keys from before the HttpOnly-cookie migration. We proactively remove
// any value left here so an old refresh token cannot linger in localStorage.
const LEGACY_KEY_REFRESH = 'unamentis_refresh_token';
const LEGACY_KEY_EXPIRES = 'unamentis_token_expires';

// Singleton instance
let instance: TokenManager | null = null;

export class TokenManager {
  private accessToken: string | null = null;
  private expiresAt = 0;
  private refreshPromise: Promise<TokenPair | null> | null = null;
  private refreshCallback: (() => Promise<TokenPair>) | null = null;
  private onTokenChange: ((tokens: TokenPair | null) => void) | null = null;

  private constructor() {
    // Clean up any refresh token persisted by a pre-migration build.
    this.purgeLegacyTokens();
  }

  static getInstance(): TokenManager {
    if (!instance) {
      instance = new TokenManager();
    }
    return instance;
  }

  /**
   * Remove refresh tokens left in localStorage by a pre-migration build.
   */
  private purgeLegacyTokens(): void {
    if (typeof window === 'undefined') return;
    try {
      localStorage.removeItem(LEGACY_KEY_REFRESH);
      localStorage.removeItem(LEGACY_KEY_EXPIRES);
    } catch {
      // localStorage not available (SSR or private mode)
    }
  }

  /**
   * Whether a refresh-token cookie may exist for this browser.
   */
  private hasSessionHint(): boolean {
    if (typeof window === 'undefined') return false;
    try {
      return localStorage.getItem(STORAGE_KEY_SESSION) === '1';
    } catch {
      return false;
    }
  }

  /**
   * Set or clear the non-sensitive session hint.
   */
  private setSessionHint(on: boolean): void {
    if (typeof window === 'undefined') return;
    try {
      if (on) {
        localStorage.setItem(STORAGE_KEY_SESSION, '1');
      } else {
        localStorage.removeItem(STORAGE_KEY_SESSION);
      }
    } catch {
      // localStorage not available
    }
  }

  /**
   * Set the callback used to refresh tokens. The callback hits the refresh
   * endpoint, which receives the refresh token from the HttpOnly cookie (the
   * proxy injects it), so no token is passed here.
   */
  setRefreshCallback(callback: () => Promise<TokenPair>): void {
    this.refreshCallback = callback;
  }

  /**
   * Set callback for token changes (for AuthProvider sync)
   */
  setOnTokenChange(callback: (tokens: TokenPair | null) => void): void {
    this.onTokenChange = callback;
  }

  /**
   * Store tokens after login/register/refresh. The refresh token is not part of
   * the browser-facing response (the proxy moved it into the cookie); we only
   * keep the access token in memory and record the session hint.
   */
  setTokens(tokens: TokenPair): void {
    this.accessToken = tokens.access_token;
    // Calculate absolute expiry time
    this.expiresAt = Date.now() + tokens.expires_in * 1000;
    this.setSessionHint(true);
    this.onTokenChange?.(tokens);
  }

  /**
   * Get the current access token.
   * Does NOT automatically refresh - use getValidToken() for that.
   */
  getAccessToken(): string | null {
    return this.accessToken;
  }

  /**
   * Check if we may have a session (a live access token or a cookie hint).
   */
  hasTokens(): boolean {
    return this.accessToken !== null || this.hasSessionHint();
  }

  /**
   * Check if the access token is expired or about to expire.
   */
  isAccessTokenExpired(): boolean {
    if (!this.accessToken) return true;
    return Date.now() > this.expiresAt - REFRESH_BUFFER_MS;
  }

  /**
   * Check if the access token is completely expired (past expiry, not just buffer).
   */
  isAccessTokenFullyExpired(): boolean {
    if (!this.accessToken) return true;
    return Date.now() > this.expiresAt;
  }

  /**
   * Get a valid access token, refreshing via the cookie if necessary.
   * Deduplicates concurrent refresh requests.
   *
   * @throws Error if refresh fails or no session is available
   */
  async getValidToken(): Promise<string> {
    // Token is still valid
    if (this.accessToken && !this.isAccessTokenExpired()) {
      return this.accessToken;
    }

    // Need a refresh. Only attempt it if a session might exist; otherwise there
    // is no cookie to refresh against.
    if (!this.hasSessionHint()) {
      throw new Error('No authentication tokens available');
    }

    // Deduplicate concurrent refresh requests
    if (!this.refreshPromise) {
      this.refreshPromise = this.performRefresh();
    }

    try {
      const newTokens = await this.refreshPromise;
      if (!newTokens) {
        throw new Error('Token refresh failed');
      }
      return newTokens.access_token;
    } finally {
      this.refreshPromise = null;
    }
  }

  /**
   * Perform the actual token refresh. The refresh token is supplied by the
   * HttpOnly cookie via the proxy, so nothing is passed to the callback.
   */
  private async performRefresh(): Promise<TokenPair | null> {
    if (!this.refreshCallback) {
      throw new Error('No refresh callback configured');
    }

    try {
      const newTokens = await this.refreshCallback();
      this.setTokens(newTokens);
      return newTokens;
    } catch {
      // Refresh failed - clear session
      this.clear();
      return null;
    }
  }

  /**
   * Clear all tokens (logout). The cookie itself is cleared by the logout
   * response from the proxy; here we drop the in-memory token and session hint.
   */
  clear(): void {
    this.accessToken = null;
    this.expiresAt = 0;
    this.refreshPromise = null;
    this.setSessionHint(false);
    this.purgeLegacyTokens();
    this.onTokenChange?.(null);
  }

  /**
   * Get time remaining until token expires (ms).
   * Returns 0 if no token or already expired.
   */
  getTimeUntilExpiry(): number {
    if (!this.accessToken) return 0;
    const remaining = this.expiresAt - Date.now();
    return Math.max(0, remaining);
  }
}

// Export singleton instance
export const tokenManager = TokenManager.getInstance();
