/**
 * API Module
 *
 * Public exports for the API client, authentication, and data fetching hooks.
 *
 * Usage:
 *   import { login, logout, useCurricula, apiRequest } from '@/lib/api';
 */

// Token Manager
export { tokenManager, TokenManager } from './token-manager';

// API Client
export {
  apiRequest,
  get,
  post,
  put,
  patch,
  del,
  upload,
  ApiError,
  type ApiClientOptions,
} from './client';

// Authentication
export {
  login,
  logout,
  register,
  refreshTokens,
  getCurrentUser,
  updateCurrentUser,
  changePassword,
  listDevices,
  removeDevice,
  listSessions,
  terminateSession,
  generateDeviceFingerprint,
  getDeviceInfo,
  POLICIES_VERSION,
} from './auth';

// SWR Hooks
export {
  // Auth
  useUser,
  // Curricula
  useCurricula,
  useCurriculum,
  useTopicTranscript,
  // Session
  useSessionHistory,
  // System
  useHealth,
  useServerStats,
  // Media
  useMediaCapabilities,
  // Import
  useImportSources,
  useImportCourses,
  useImportProgress,
  useStartImportJob,
  // Plugins
  usePlugins,
  // Mutations
  useReloadCurricula,
} from './hooks';
