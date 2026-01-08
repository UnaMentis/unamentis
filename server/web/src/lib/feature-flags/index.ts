// Feature Flags - UnaMentis Web Client
// Export all public APIs

// Types
export type {
  FeatureFlagConfig,
  FeatureFlagContext,
  FeatureFlagVariant,
  FeatureFlagPayload,
  FeatureFlagState,
} from './types';

// Client
export { FeatureFlagClient, getFeatureFlagClient, devConfig } from './client';

// React integration
export {
  FeatureFlagProvider,
  useFeatureFlags,
  useFlag,
  useFlagVariant,
  FeatureGate,
  withFeatureFlag,
} from './context';
