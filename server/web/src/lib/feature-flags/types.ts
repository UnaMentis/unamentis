// Feature Flag Types for UnaMentis Web Client

/**
 * Configuration for the feature flag client
 */
export interface FeatureFlagConfig {
  /** URL of the Unleash proxy */
  proxyUrl: string;
  /** Client key for authentication */
  clientKey: string;
  /** Application name for context */
  appName: string;
  /** Refresh interval in milliseconds */
  refreshInterval?: number;
  /** Enable local storage caching */
  enableCache?: boolean;
}

/**
 * Context for feature flag evaluation
 */
export interface FeatureFlagContext {
  userId?: string;
  sessionId?: string;
  properties?: Record<string, string>;
}

/**
 * A feature flag variant
 */
export interface FeatureFlagVariant {
  name: string;
  enabled: boolean;
  payload?: FeatureFlagPayload;
}

/**
 * Payload types for variants
 */
export type FeatureFlagPayload =
  | { type: 'string'; value: string }
  | { type: 'number'; value: number }
  | { type: 'json'; value: Record<string, unknown> };

/**
 * A single toggle from the proxy
 */
export interface UnleashToggle {
  name: string;
  enabled: boolean;
  variant?: {
    name: string;
    enabled: boolean;
    payload?: {
      type: string;
      value: string;
    };
  };
  impressionData?: boolean;
}

/**
 * Response from the Unleash proxy
 */
export interface UnleashProxyResponse {
  toggles: UnleashToggle[];
}

/**
 * Feature flag state
 */
export interface FeatureFlagState {
  /** Whether flags have been loaded */
  isReady: boolean;
  /** Whether a fetch is in progress */
  isLoading: boolean;
  /** Error from last fetch */
  error: Error | null;
  /** Last successful fetch time */
  lastFetchTime: Date | null;
  /** Number of flags loaded */
  flagCount: number;
}

/**
 * Default configuration values
 */
export const DEFAULT_CONFIG: Required<Omit<FeatureFlagConfig, 'proxyUrl' | 'clientKey'>> = {
  appName: 'UnaMentis-Web',
  refreshInterval: 30000, // 30 seconds
  enableCache: true,
};

/**
 * Local storage key for cached flags
 */
export const CACHE_KEY = 'unamentis_feature_flags';

/**
 * Cache entry structure
 */
export interface CacheEntry {
  flags: Record<string, { enabled: boolean; variant?: FeatureFlagVariant }>;
  timestamp: number;
  version: number;
}

/**
 * Cache version (bump when format changes)
 */
export const CACHE_VERSION = 1;

/**
 * Maximum cache age in milliseconds (24 hours)
 */
export const MAX_CACHE_AGE = 24 * 60 * 60 * 1000;
