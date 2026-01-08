'use client';

// React Context Provider for Feature Flags
// Provides hooks and components for feature flag integration

import React, {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  useMemo,
  type ReactNode,
} from 'react';
import { FeatureFlagClient, getFeatureFlagClient } from './client';
import type {
  FeatureFlagConfig,
  FeatureFlagContext as FFContext,
  FeatureFlagState,
  FeatureFlagVariant,
} from './types';

// Context types
interface FeatureFlagContextValue {
  /** Check if a flag is enabled */
  isEnabled: (flagName: string) => boolean;
  /** Get a flag's variant */
  getVariant: (flagName: string) => FeatureFlagVariant | undefined;
  /** Current state of the feature flag system */
  state: FeatureFlagState;
  /** Force refresh flags */
  refresh: () => Promise<void>;
  /** Update user context */
  updateContext: (context: FFContext) => Promise<void>;
  /** The underlying client */
  client: FeatureFlagClient;
}

// Create context
const FeatureFlagContext = createContext<FeatureFlagContextValue | null>(null);

// Provider props
interface FeatureFlagProviderProps {
  children: ReactNode;
  /** Configuration for the feature flag client */
  config: FeatureFlagConfig;
  /** Initial context (e.g., userId) */
  initialContext?: FFContext;
}

/**
 * Provider component for feature flags
 *
 * @example
 * ```tsx
 * <FeatureFlagProvider config={config}>
 *   <App />
 * </FeatureFlagProvider>
 * ```
 */
export function FeatureFlagProvider({
  children,
  config,
  initialContext,
}: FeatureFlagProviderProps) {
  const [client] = useState(() => getFeatureFlagClient(config));
  const [state, setState] = useState<FeatureFlagState>(client.getState());

  // Subscribe to state changes
  useEffect(() => {
    const unsubscribe = client.subscribe(() => {
      setState(client.getState());
    });

    // Start the client
    client.start(initialContext).catch(console.error);

    return () => {
      unsubscribe();
      client.stop();
    };
  }, [client, initialContext]);

  // Memoized methods
  const isEnabled = useCallback((flagName: string) => client.isEnabled(flagName), [client]);

  const getVariant = useCallback((flagName: string) => client.getVariant(flagName), [client]);

  const refresh = useCallback(() => client.refresh(), [client]);

  const updateContext = useCallback(
    (context: FFContext) => client.updateContext(context),
    [client]
  );

  // Context value
  const value = useMemo<FeatureFlagContextValue>(
    () => ({
      isEnabled,
      getVariant,
      state,
      refresh,
      updateContext,
      client,
    }),
    [isEnabled, getVariant, state, refresh, updateContext, client]
  );

  return <FeatureFlagContext.Provider value={value}>{children}</FeatureFlagContext.Provider>;
}

/**
 * Hook to access feature flags
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const { isEnabled } = useFeatureFlags();
 *
 *   if (isEnabled('new_feature')) {
 *     return <NewFeature />;
 *   }
 *   return <OldFeature />;
 * }
 * ```
 */
export function useFeatureFlags(): FeatureFlagContextValue {
  const context = useContext(FeatureFlagContext);
  if (!context) {
    throw new Error('useFeatureFlags must be used within a FeatureFlagProvider');
  }
  return context;
}

/**
 * Hook to check a specific flag
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const isNewUI = useFlag('new_ui');
 *   return isNewUI ? <NewUI /> : <OldUI />;
 * }
 * ```
 */
export function useFlag(flagName: string): boolean {
  const { isEnabled, state } = useFeatureFlags();

  // Re-render when flags are ready
  const [, setRerender] = useState(0);
  useEffect(() => {
    if (!state.isReady) {
      const interval = setInterval(() => setRerender((n) => n + 1), 100);
      return () => clearInterval(interval);
    }
  }, [state.isReady]);

  return isEnabled(flagName);
}

/**
 * Hook to get a flag's variant
 *
 * @example
 * ```tsx
 * function PricingPage() {
 *   const variant = useFlagVariant('pricing_experiment');
 *   if (variant?.name === 'variant_a') {
 *     return <PricingA />;
 *   }
 *   return <PricingB />;
 * }
 * ```
 */
export function useFlagVariant(flagName: string): FeatureFlagVariant | undefined {
  const { getVariant, state } = useFeatureFlags();

  // Re-render when flags are ready
  const [, setRerender] = useState(0);
  useEffect(() => {
    if (!state.isReady) {
      const interval = setInterval(() => setRerender((n) => n + 1), 100);
      return () => clearInterval(interval);
    }
  }, [state.isReady]);

  return getVariant(flagName);
}

/**
 * Component that renders children only when a flag is enabled
 *
 * @example
 * ```tsx
 * <FeatureGate flag="dark_mode">
 *   <DarkModeToggle />
 * </FeatureGate>
 * ```
 */
interface FeatureGateProps {
  /** Name of the feature flag */
  flag: string;
  /** Content to render when flag is enabled */
  children: ReactNode;
  /** Optional fallback when flag is disabled */
  fallback?: ReactNode;
}

export function FeatureGate({ flag, children, fallback = null }: FeatureGateProps) {
  const isEnabled = useFlag(flag);
  return <>{isEnabled ? children : fallback}</>;
}

/**
 * HOC to wrap a component with feature flag check
 *
 * @example
 * ```tsx
 * const NewFeature = withFeatureFlag('new_feature', OldFeature)(NewFeatureComponent);
 * ```
 */
export function withFeatureFlag<P extends object>(
  flagName: string,
  FallbackComponent?: React.ComponentType<P>
) {
  return function wrapper(WrappedComponent: React.ComponentType<P>) {
    function WithFeatureFlag(props: P) {
      const isEnabled = useFlag(flagName);

      if (!isEnabled) {
        return FallbackComponent ? <FallbackComponent {...props} /> : null;
      }

      return <WrappedComponent {...props} />;
    }

    WithFeatureFlag.displayName = `withFeatureFlag(${flagName})(${
      WrappedComponent.displayName || WrappedComponent.name || 'Component'
    })`;

    return WithFeatureFlag;
  };
}
