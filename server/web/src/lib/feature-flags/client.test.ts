// Feature Flag Client Tests for UnaMentis Web
// Unit tests for FeatureFlagClient and related functionality
//
// Part of Quality Infrastructure (Phase 3)

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { FeatureFlagClient, devConfig, getFeatureFlagClient } from './client';
import type { FeatureFlagConfig, FeatureFlagContext, UnleashProxyResponse } from './types';
import { CACHE_KEY, CACHE_VERSION, MAX_CACHE_AGE } from './types';

// Mock localStorage
const mockLocalStorage = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: vi.fn((key: string) => store[key] || null),
    setItem: vi.fn((key: string, value: string) => {
      store[key] = value;
    }),
    removeItem: vi.fn((key: string) => {
      delete store[key];
    }),
    clear: vi.fn(() => {
      store = {};
    }),
  };
})();

Object.defineProperty(window, 'localStorage', { value: mockLocalStorage });

// Mock fetch
const mockFetch = vi.fn();
global.fetch = mockFetch;

describe('FeatureFlagClient', () => {
  let client: FeatureFlagClient;

  const testConfig: FeatureFlagConfig = {
    proxyUrl: 'http://test.example.com/proxy',
    clientKey: 'test-client-key',
    appName: 'TestApp',
    refreshInterval: 60000,
    enableCache: true,
  };

  const mockResponse: UnleashProxyResponse = {
    toggles: [
      { name: 'feature_a', enabled: true },
      { name: 'feature_b', enabled: false },
      {
        name: 'feature_c',
        enabled: true,
        variant: {
          name: 'control',
          enabled: true,
          payload: { type: 'string', value: 'test-value' },
        },
      },
    ],
  };

  beforeEach(() => {
    vi.clearAllMocks();
    mockLocalStorage.clear();
    mockFetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockResponse),
    });
  });

  afterEach(() => {
    client?.stop();
  });

  // Initialization tests
  describe('initialization', () => {
    it('creates client with config', () => {
      client = new FeatureFlagClient(testConfig);
      expect(client).toBeDefined();
    });

    it('merges config with defaults', () => {
      const minimalConfig: FeatureFlagConfig = {
        proxyUrl: 'http://test.com/proxy',
        clientKey: 'key',
        appName: 'App',
      };
      client = new FeatureFlagClient(minimalConfig);
      expect(client).toBeDefined();
    });
  });

  // Flag evaluation tests
  describe('flag evaluation', () => {
    beforeEach(async () => {
      client = new FeatureFlagClient(testConfig);
      await client.start();
    });

    it('returns true for enabled flag', () => {
      expect(client.isEnabled('feature_a')).toBe(true);
    });

    it('returns false for disabled flag', () => {
      expect(client.isEnabled('feature_b')).toBe(false);
    });

    it('returns false for unknown flag', () => {
      expect(client.isEnabled('unknown_flag')).toBe(false);
    });

    it('returns variant for flag with variant', () => {
      const variant = client.getVariant('feature_c');
      expect(variant).toBeDefined();
      expect(variant?.name).toBe('control');
      expect(variant?.payload).toEqual({ type: 'string', value: 'test-value' });
    });

    it('returns undefined variant for flag without variant', () => {
      const variant = client.getVariant('feature_a');
      expect(variant).toBeUndefined();
    });

    it('returns all flag names', () => {
      const names = client.getFlagNames();
      expect(names).toContain('feature_a');
      expect(names).toContain('feature_b');
      expect(names).toContain('feature_c');
    });
  });

  // State management tests
  describe('state management', () => {
    it('starts with initial state', () => {
      client = new FeatureFlagClient(testConfig);
      const state = client.getState();
      expect(state.isReady).toBe(false);
      expect(state.isLoading).toBe(false);
      expect(state.error).toBeNull();
      expect(state.flagCount).toBe(0);
    });

    it('updates state after successful fetch', async () => {
      client = new FeatureFlagClient(testConfig);
      await client.start();
      const state = client.getState();
      expect(state.isReady).toBe(true);
      expect(state.isLoading).toBe(false);
      expect(state.flagCount).toBe(3);
      expect(state.lastFetchTime).not.toBeNull();
    });

    it('updates state on fetch error', async () => {
      mockFetch.mockRejectedValueOnce(new Error('Network error'));
      client = new FeatureFlagClient(testConfig);

      await client.start().catch(() => {});

      const state = client.getState();
      expect(state.isLoading).toBe(false);
      expect(state.error).not.toBeNull();
    });
  });

  // Subscription tests
  describe('subscriptions', () => {
    it('notifies subscribers on state change', async () => {
      const listener = vi.fn();
      client = new FeatureFlagClient(testConfig);
      client.subscribe(listener);

      await client.start();

      expect(listener).toHaveBeenCalled();
    });

    it('allows unsubscribing', async () => {
      const listener = vi.fn();
      client = new FeatureFlagClient(testConfig);
      const unsubscribe = client.subscribe(listener);

      unsubscribe();
      await client.start();

      // Listener may have been called before unsubscribe
      const callCount = listener.mock.calls.length;
      await client.refresh();

      // Should not have additional calls after unsubscribe
      expect(listener.mock.calls.length).toBe(callCount);
    });
  });

  // Context tests
  describe('context', () => {
    it('includes context in fetch request', async () => {
      client = new FeatureFlagClient(testConfig);
      await client.start({ userId: 'user-123', sessionId: 'session-456' });

      expect(mockFetch).toHaveBeenCalledWith(
        expect.stringContaining('userId=user-123'),
        expect.any(Object)
      );
    });

    it('updates context and refreshes', async () => {
      client = new FeatureFlagClient(testConfig);
      await client.start();

      mockFetch.mockClear();
      await client.updateContext({ userId: 'new-user' });

      expect(mockFetch).toHaveBeenCalled();
    });
  });

  // Cache tests
  describe('caching', () => {
    it('saves flags to localStorage', async () => {
      client = new FeatureFlagClient(testConfig);
      await client.start();

      expect(mockLocalStorage.setItem).toHaveBeenCalledWith(
        CACHE_KEY,
        expect.any(String)
      );
    });

    it('loads flags from valid cache', () => {
      const cacheEntry = {
        flags: {
          cached_flag: { enabled: true },
        },
        timestamp: Date.now(),
        version: CACHE_VERSION,
      };
      mockLocalStorage.getItem.mockReturnValueOnce(JSON.stringify(cacheEntry));

      client = new FeatureFlagClient(testConfig);
      // Trigger cache load by calling start (cache is loaded synchronously before fetch)
    });

    it('ignores expired cache', () => {
      const cacheEntry = {
        flags: {
          old_flag: { enabled: true },
        },
        timestamp: Date.now() - MAX_CACHE_AGE - 1000,
        version: CACHE_VERSION,
      };
      mockLocalStorage.getItem.mockReturnValueOnce(JSON.stringify(cacheEntry));

      client = new FeatureFlagClient(testConfig);
      expect(client.isEnabled('old_flag')).toBe(false);
    });

    it('ignores cache with wrong version', () => {
      const cacheEntry = {
        flags: {
          versioned_flag: { enabled: true },
        },
        timestamp: Date.now(),
        version: CACHE_VERSION - 1,
      };
      mockLocalStorage.getItem.mockReturnValueOnce(JSON.stringify(cacheEntry));

      client = new FeatureFlagClient(testConfig);
      expect(client.isEnabled('versioned_flag')).toBe(false);
    });
  });

  // Error handling tests
  describe('error handling', () => {
    it('handles network errors gracefully', async () => {
      mockFetch.mockRejectedValueOnce(new Error('Network error'));
      client = new FeatureFlagClient(testConfig);

      await expect(client.start()).resolves.not.toThrow();
    });

    it('handles HTTP errors', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 500,
      });
      client = new FeatureFlagClient(testConfig);

      await client.start();

      const state = client.getState();
      expect(state.error?.message).toContain('500');
    });

    it('continues with cached data on fetch failure', async () => {
      const cacheEntry = {
        flags: {
          cached_flag: { enabled: true },
        },
        timestamp: Date.now(),
        version: CACHE_VERSION,
      };
      mockLocalStorage.getItem.mockReturnValue(JSON.stringify(cacheEntry));

      mockFetch.mockRejectedValueOnce(new Error('Network error'));
      client = new FeatureFlagClient(testConfig);

      await client.start();

      const state = client.getState();
      expect(state.isReady).toBe(true);
      expect(client.isEnabled('cached_flag')).toBe(true);
    });
  });

  // Lifecycle tests
  describe('lifecycle', () => {
    it('stops refresh timer on stop()', async () => {
      vi.useFakeTimers();
      client = new FeatureFlagClient({ ...testConfig, refreshInterval: 1000 });
      await client.start();

      const initialCalls = mockFetch.mock.calls.length;
      client.stop();

      // Advance time past refresh interval
      vi.advanceTimersByTime(2000);

      // No additional calls should have been made
      expect(mockFetch.mock.calls.length).toBe(initialCalls);

      vi.useRealTimers();
    });

    it('does not duplicate refresh requests', async () => {
      client = new FeatureFlagClient(testConfig);

      // Slow down the fetch to test concurrent calls
      let resolvePromise: () => void;
      mockFetch.mockReturnValueOnce(
        new Promise((resolve) => {
          resolvePromise = () =>
            resolve({
              ok: true,
              json: () => Promise.resolve(mockResponse),
            });
        })
      );

      // Start multiple refresh calls
      const promise1 = client.refresh();
      const promise2 = client.refresh();

      resolvePromise!();
      await Promise.all([promise1, promise2]);

      // Only one fetch should have been made
      expect(mockFetch).toHaveBeenCalledTimes(1);
    });
  });
});

describe('devConfig', () => {
  it('has development defaults', () => {
    expect(devConfig.proxyUrl).toBe('http://localhost:3063/proxy');
    expect(devConfig.clientKey).toBe('proxy-client-key');
    expect(devConfig.appName).toBe('UnaMentis-Web-Dev');
  });
});

describe('getFeatureFlagClient', () => {
  it('throws without initialization', () => {
    expect(() => getFeatureFlagClient()).toThrow();
  });
});
