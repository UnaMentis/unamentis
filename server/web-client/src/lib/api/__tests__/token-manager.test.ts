/**
 * TokenManager Tests
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { TokenManager } from '../token-manager';
import { mockTokenPair } from '@/__tests__/mocks';

describe('TokenManager', () => {
  let tokenManager: TokenManager;

  beforeEach(() => {
    // Create a new instance for each test by clearing singleton
    // We need to access the private instance, so we use type casting
    const instance = TokenManager.getInstance();
    instance.clear();
    tokenManager = instance;
  });

  describe('getInstance', () => {
    it('should return singleton instance', () => {
      const instance1 = TokenManager.getInstance();
      const instance2 = TokenManager.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('setTokens', () => {
    it('should store the access token without persisting a refresh token', () => {
      tokenManager.setTokens(mockTokenPair);

      expect(tokenManager.getAccessToken()).toBe(mockTokenPair.access_token);
      // The refresh token must never be written to localStorage (B6); it lives
      // in an HttpOnly cookie the client cannot read.
      expect(localStorage.getItem('unamentis_refresh_token')).toBeNull();
      if (mockTokenPair.refresh_token) {
        expect(JSON.stringify(localStorage)).not.toContain(mockTokenPair.refresh_token);
      }
      // A non-sensitive session hint is recorded so a reload attempts a refresh.
      expect(localStorage.getItem('unamentis_session')).toBe('1');
    });

    it('should call onTokenChange callback when tokens are set', () => {
      const callback = vi.fn();
      tokenManager.setOnTokenChange(callback);

      tokenManager.setTokens(mockTokenPair);

      expect(callback).toHaveBeenCalledWith(mockTokenPair);
    });
  });

  describe('hasTokens', () => {
    it('should return false when no tokens are stored', () => {
      expect(tokenManager.hasTokens()).toBe(false);
    });

    it('should return true when tokens are stored', () => {
      tokenManager.setTokens(mockTokenPair);
      expect(tokenManager.hasTokens()).toBe(true);
    });
  });

  describe('isAccessTokenExpired', () => {
    it('should return true when no token is stored', () => {
      expect(tokenManager.isAccessTokenExpired()).toBe(true);
    });

    it('should return false when token is valid', () => {
      tokenManager.setTokens(mockTokenPair);
      expect(tokenManager.isAccessTokenExpired()).toBe(false);
    });

    it('should return true when token is about to expire', () => {
      // Set token with very short expiry (30 seconds, less than 60s buffer)
      tokenManager.setTokens({
        ...mockTokenPair,
        expires_in: 30,
      });
      expect(tokenManager.isAccessTokenExpired()).toBe(true);
    });
  });

  describe('isAccessTokenFullyExpired', () => {
    it('should return true when no token is stored', () => {
      expect(tokenManager.isAccessTokenFullyExpired()).toBe(true);
    });

    it('should return false when token is valid', () => {
      tokenManager.setTokens(mockTokenPair);
      expect(tokenManager.isAccessTokenFullyExpired()).toBe(false);
    });
  });

  describe('getValidToken', () => {
    it('should throw error when no tokens available', async () => {
      await expect(tokenManager.getValidToken()).rejects.toThrow(
        'No authentication tokens available'
      );
    });

    it('should return access token when not expired', async () => {
      tokenManager.setTokens(mockTokenPair);
      const token = await tokenManager.getValidToken();
      expect(token).toBe(mockTokenPair.access_token);
    });

    it('should refresh token when expired', async () => {
      const newTokenPair = {
        ...mockTokenPair,
        access_token: 'new-access-token',
      };

      const refreshCallback = vi.fn().mockResolvedValue(newTokenPair);
      tokenManager.setRefreshCallback(refreshCallback);

      // Set expired token
      tokenManager.setTokens({
        ...mockTokenPair,
        expires_in: 0, // Already expired
      });

      const token = await tokenManager.getValidToken();
      expect(token).toBe('new-access-token');
      expect(refreshCallback).toHaveBeenCalled();
    });

    it('should throw error when refresh fails', async () => {
      tokenManager.setRefreshCallback(vi.fn().mockRejectedValue(new Error('Refresh failed')));

      // Set expired token
      tokenManager.setTokens({
        ...mockTokenPair,
        expires_in: 0,
      });

      await expect(tokenManager.getValidToken()).rejects.toThrow('Token refresh failed');
    });

    it('should deduplicate concurrent refresh requests', async () => {
      const newTokenPair = {
        ...mockTokenPair,
        access_token: 'new-access-token',
      };

      const refreshCallback = vi.fn().mockImplementation(
        () =>
          new Promise((resolve) => {
            setTimeout(() => resolve(newTokenPair), 100);
          })
      );
      tokenManager.setRefreshCallback(refreshCallback);

      // Set expired token
      tokenManager.setTokens({
        ...mockTokenPair,
        expires_in: 0,
      });

      // Make concurrent requests
      const [token1, token2] = await Promise.all([
        tokenManager.getValidToken(),
        tokenManager.getValidToken(),
      ]);

      expect(token1).toBe('new-access-token');
      expect(token2).toBe('new-access-token');
      // Should only call refresh once
      expect(refreshCallback).toHaveBeenCalledTimes(1);
    });
  });

  describe('clear', () => {
    it('should clear all tokens', () => {
      tokenManager.setTokens(mockTokenPair);
      tokenManager.clear();

      expect(tokenManager.getAccessToken()).toBeNull();
      expect(tokenManager.hasTokens()).toBe(false);
      expect(localStorage.getItem('unamentis_session')).toBeNull();
    });

    it('should purge any pre-migration refresh token from localStorage', () => {
      localStorage.setItem('unamentis_refresh_token', 'old-secret');
      localStorage.setItem('unamentis_token_expires', '123');

      tokenManager.clear();

      expect(localStorage.getItem('unamentis_refresh_token')).toBeNull();
      expect(localStorage.getItem('unamentis_token_expires')).toBeNull();
    });

    it('should call onTokenChange with null when cleared', () => {
      const callback = vi.fn();
      tokenManager.setTokens(mockTokenPair);
      tokenManager.setOnTokenChange(callback);

      tokenManager.clear();

      expect(callback).toHaveBeenCalledWith(null);
    });
  });

  describe('getTimeUntilExpiry', () => {
    it('should return 0 when no token is stored', () => {
      expect(tokenManager.getTimeUntilExpiry()).toBe(0);
    });

    it('should return positive value when token is valid', () => {
      tokenManager.setTokens(mockTokenPair);
      const remaining = tokenManager.getTimeUntilExpiry();
      expect(remaining).toBeGreaterThan(0);
      expect(remaining).toBeLessThanOrEqual(mockTokenPair.expires_in * 1000);
    });
  });
});
