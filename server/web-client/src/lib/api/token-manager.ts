/**
 * Token Manager
 *
 * Token storage with automatic refresh before expiry.
 * Access tokens are stored in memory only (never localStorage) for security.
 * Refresh tokens are persisted in localStorage to survive page navigation.
 */

import type { TokenPair } from '@/types';

// Refresh tokens 1 minute before expiry
const REFRESH_BUFFER_MS = 60 * 1000;

// LocalStorage keys
const STORAGE_KEY_REFRESH = 'unamentis_refresh_token';
const STORAGE_KEY_EXPIRES = 'unamentis_token_expires';

// Singleton instance
let instance: TokenManager | null = null;

export class TokenManager {
  private accessToken: string | null = null;
  private refreshToken: string | null = null;
  private expiresAt = 0;
  private refreshPromise: Promise<TokenPair | null> | null = null;
  private refreshCallback: ((refreshToken: string) => Promise<TokenPair>) | null = null;
  private onTokenChange: ((tokens: TokenPair | null) => void) | null = null;

  private constructor() {
    // Load persisted refresh token on initialization
    this.loadPersistedTokens();
  }

  static getInstance(): TokenManager {
    if (!instance) {
      instance = new TokenManager();
    }
    return instance;
  }

  /**
   * Load persisted refresh token from localStorage.
   * Access token is not persisted for security.
   */
  private loadPersistedTokens(): void {
    if (typeof window === 'undefined') return;

    try {
      const storedRefresh = localStorage.getItem(STORAGE_KEY_REFRESH);
      const storedExpires = localStorage.getItem(STORAGE_KEY_EXPIRES);

      if (storedRefresh) {
        this.refreshToken = storedRefresh;
        // Set a past expiry so access token will be refreshed on first use
        this.expiresAt = storedExpires ? parseInt(storedExpires, 10) : 0;
      }
    } catch {
      // localStorage not available (SSR or private mode)
    }
  }

  /**
   * Persist refresh token to localStorage.
   */
  private persistTokens(): void {
    if (typeof window === 'undefined') return;

    try {
      if (this.refreshToken) {
        localStorage.setItem(STORAGE_KEY_REFRESH, this.refreshToken);
        localStorage.setItem(STORAGE_KEY_EXPIRES, this.expiresAt.toString());
      }
    } catch {
      // localStorage not available
    }
  }

  /**
   * Clear persisted tokens from localStorage.
   */
  private clearPersistedTokens(): void {
    if (typeof window === 'undefined') return;

    try {
      localStorage.removeItem(STORAGE_KEY_REFRESH);
      localStorage.removeItem(STORAGE_KEY_EXPIRES);
    } catch {
      // localStorage not available
    }
  }

  /**
   * Set the callback function for refreshing tokens.
   * This is called when the access token is expired or about to expire.
   */
  setRefreshCallback(callback: (refreshToken: string) => Promise<TokenPair>): void {
    this.refreshCallback = callback;
  }

  /**
   * Set callback for token changes (for AuthProvider sync)
   */
  setOnTokenChange(callback: (tokens: TokenPair | null) => void): void {
    this.onTokenChange = callback;
  }

  /**
   * Store tokens after login/register/refresh.
   */
  setTokens(tokens: TokenPair): void {
    this.accessToken = tokens.access_token;
    this.refreshToken = tokens.refresh_token;
    // Calculate absolute expiry time
    this.expiresAt = Date.now() + tokens.expires_in * 1000;
    // Persist refresh token for session recovery
    this.persistTokens();
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
   * Get the refresh token.
   */
  getRefreshToken(): string | null {
    return this.refreshToken;
  }

  /**
   * Check if we have tokens stored (including persisted refresh token).
   */
  hasTokens(): boolean {
    return this.refreshToken !== null;
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
   * Get a valid access token, refreshing if necessary.
   * Deduplicates concurrent refresh requests.
   *
   * @throws Error if refresh fails or no tokens available
   */
  async getValidToken(): Promise<string> {
    // No refresh token at all
    if (!this.refreshToken) {
      throw new Error('No authentication tokens available');
    }

    // Token is still valid
    if (this.accessToken && !this.isAccessTokenExpired()) {
      return this.accessToken;
    }

    // Token needs refresh - deduplicate concurrent requests
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
   * Perform the actual token refresh.
   */
  private async performRefresh(): Promise<TokenPair | null> {
    if (!this.refreshToken) {
      return null;
    }

    if (!this.refreshCallback) {
      throw new Error('No refresh callback configured');
    }

    try {
      const newTokens = await this.refreshCallback(this.refreshToken);
      this.setTokens(newTokens);
      return newTokens;
    } catch {
      // Refresh failed - clear tokens
      this.clear();
      return null;
    }
  }

  /**
   * Clear all tokens (logout).
   */
  clear(): void {
    this.accessToken = null;
    this.refreshToken = null;
    this.expiresAt = 0;
    this.refreshPromise = null;
    this.clearPersistedTokens();
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
