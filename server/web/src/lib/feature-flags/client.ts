// Feature Flag Client for UnaMentis Web
// Unleash proxy client with caching and React integration

import type {
  FeatureFlagConfig,
  FeatureFlagContext,
  FeatureFlagVariant,
  FeatureFlagState,
  UnleashProxyResponse,
  CacheEntry,
} from './types';
import { DEFAULT_CONFIG, CACHE_KEY, CACHE_VERSION, MAX_CACHE_AGE } from './types';

type FlagValue = { enabled: boolean; variant?: FeatureFlagVariant };
type Listener = () => void;

/**
 * Feature flag client for the web application
 */
export class FeatureFlagClient {
  private config: Required<FeatureFlagConfig>;
  private flags: Map<string, FlagValue> = new Map();
  private state: FeatureFlagState = {
    isReady: false,
    isLoading: false,
    error: null,
    lastFetchTime: null,
    flagCount: 0,
  };
  private context: FeatureFlagContext = {};
  private refreshTimer: ReturnType<typeof setInterval> | null = null;
  private listeners: Set<Listener> = new Set();

  constructor(config: FeatureFlagConfig) {
    this.config = {
      ...DEFAULT_CONFIG,
      ...config,
    };
  }

  /**
   * Initialize the client and start fetching flags
   */
  async start(context?: FeatureFlagContext): Promise<void> {
    if (context) {
      this.context = context;
    }

    // Load from cache first for immediate availability
    if (this.config.enableCache && typeof window !== 'undefined') {
      this.loadFromCache();
    }

    // Fetch fresh flags
    await this.refresh();

    // Start background refresh
    this.startRefreshLoop();
  }

  /**
   * Stop the client
   */
  stop(): void {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  /**
   * Update context (e.g., when user logs in)
   */
  async updateContext(context: FeatureFlagContext): Promise<void> {
    this.context = { ...this.context, ...context };
    await this.refresh();
  }

  /**
   * Check if a flag is enabled
   */
  isEnabled(flagName: string): boolean {
    const flag = this.flags.get(flagName);
    return flag?.enabled ?? false;
  }

  /**
   * Get a flag's variant
   */
  getVariant(flagName: string): FeatureFlagVariant | undefined {
    return this.flags.get(flagName)?.variant;
  }

  /**
   * Get all flag names
   */
  getFlagNames(): string[] {
    return Array.from(this.flags.keys());
  }

  /**
   * Get current state
   */
  getState(): FeatureFlagState {
    return { ...this.state };
  }

  /**
   * Subscribe to state changes
   */
  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Force refresh flags from server
   */
  async refresh(): Promise<void> {
    if (this.state.isLoading) return;

    this.updateState({ isLoading: true, error: null });

    try {
      const url = new URL(this.config.proxyUrl);
      url.searchParams.set('appName', this.config.appName);

      if (this.context.userId) {
        url.searchParams.set('userId', this.context.userId);
      }
      if (this.context.sessionId) {
        url.searchParams.set('sessionId', this.context.sessionId);
      }
      if (this.context.properties) {
        url.searchParams.set('properties', JSON.stringify(this.context.properties));
      }

      const response = await fetch(url.toString(), {
        method: 'GET',
        headers: {
          Authorization: this.config.clientKey,
          Accept: 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`Failed to fetch flags: ${response.status}`);
      }

      const data: UnleashProxyResponse = await response.json();

      // Update flags
      this.flags.clear();
      for (const toggle of data.toggles) {
        const variant = toggle.variant
          ? {
              name: toggle.variant.name,
              enabled: toggle.variant.enabled,
              payload: toggle.variant.payload
                ? this.parsePayload(toggle.variant.payload)
                : undefined,
            }
          : undefined;

        this.flags.set(toggle.name, {
          enabled: toggle.enabled,
          variant,
        });
      }

      // Update state
      this.updateState({
        isReady: true,
        isLoading: false,
        lastFetchTime: new Date(),
        flagCount: this.flags.size,
      });

      // Save to cache
      if (this.config.enableCache && typeof window !== 'undefined') {
        this.saveToCache();
      }

      console.log(`[FeatureFlags] Loaded ${this.flags.size} flags`);
    } catch (error) {
      console.error('[FeatureFlags] Failed to fetch flags:', error);
      this.updateState({
        isLoading: false,
        error: error instanceof Error ? error : new Error(String(error)),
      });

      // If we have cached data, mark as ready anyway
      if (this.flags.size > 0) {
        this.updateState({ isReady: true });
      }
    }
  }

  // Private methods

  private parsePayload(payload: { type: string; value: string }): FeatureFlagVariant['payload'] {
    switch (payload.type) {
      case 'number':
        return { type: 'number', value: parseFloat(payload.value) };
      case 'json':
        try {
          return { type: 'json', value: JSON.parse(payload.value) };
        } catch {
          return { type: 'string', value: payload.value };
        }
      default:
        return { type: 'string', value: payload.value };
    }
  }

  private loadFromCache(): void {
    try {
      const cached = localStorage.getItem(CACHE_KEY);
      if (!cached) return;

      const entry: CacheEntry = JSON.parse(cached);

      // Check version
      if (entry.version !== CACHE_VERSION) {
        localStorage.removeItem(CACHE_KEY);
        return;
      }

      // Check age
      if (Date.now() - entry.timestamp > MAX_CACHE_AGE) {
        localStorage.removeItem(CACHE_KEY);
        return;
      }

      // Load flags
      for (const [name, value] of Object.entries(entry.flags)) {
        this.flags.set(name, value);
      }

      this.updateState({
        isReady: true,
        flagCount: this.flags.size,
      });

      console.log(`[FeatureFlags] Loaded ${this.flags.size} flags from cache`);
    } catch (error) {
      console.warn('[FeatureFlags] Failed to load cache:', error);
    }
  }

  private saveToCache(): void {
    try {
      const flags: Record<string, FlagValue> = {};
      for (const [name, value] of this.flags) {
        flags[name] = value;
      }

      const entry: CacheEntry = {
        flags,
        timestamp: Date.now(),
        version: CACHE_VERSION,
      };

      localStorage.setItem(CACHE_KEY, JSON.stringify(entry));
    } catch (error) {
      console.warn('[FeatureFlags] Failed to save cache:', error);
    }
  }

  private startRefreshLoop(): void {
    if (this.refreshTimer) return;

    this.refreshTimer = setInterval(() => {
      this.refresh().catch(console.error);
    }, this.config.refreshInterval);
  }

  private updateState(partial: Partial<FeatureFlagState>): void {
    this.state = { ...this.state, ...partial };
    this.notifyListeners();
  }

  private notifyListeners(): void {
    for (const listener of this.listeners) {
      try {
        listener();
      } catch (error) {
        console.error('[FeatureFlags] Listener error:', error);
      }
    }
  }
}

// Default client instance
let defaultClient: FeatureFlagClient | null = null;

/**
 * Get or create the default client
 */
export function getFeatureFlagClient(config?: FeatureFlagConfig): FeatureFlagClient {
  if (!defaultClient && config) {
    defaultClient = new FeatureFlagClient(config);
  }
  if (!defaultClient) {
    throw new Error(
      'Feature flag client not initialized. Call getFeatureFlagClient with config first.'
    );
  }
  return defaultClient;
}

/**
 * Development configuration
 */
export const devConfig: FeatureFlagConfig = {
  proxyUrl: 'http://localhost:3063/proxy',
  clientKey: 'proxy-client-key',
  appName: 'UnaMentis-Web-Dev',
};
