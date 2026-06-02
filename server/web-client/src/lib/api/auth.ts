/**
 * Authentication API Functions
 *
 * Login, register, refresh, logout, and user management.
 */

import type {
  AuthResponse,
  DeviceInfo,
  DeviceListResponse,
  LoginRequest,
  LogoutRequest,
  PasswordChangeRequest,
  RefreshResponse,
  RegisterRequest,
  SessionListResponse,
  User,
  UserUpdateRequest,
} from '@/types';
import { post, get, patch, del } from './client';
import { tokenManager } from './token-manager';

// App version for device registration
const APP_VERSION = '1.0.0';

/**
 * Generate a device fingerprint for device registration.
 * Uses browser characteristics to create a semi-stable identifier.
 */
export async function generateDeviceFingerprint(): Promise<string> {
  const components = [
    navigator.userAgent,
    navigator.language,
    screen.width.toString(),
    screen.height.toString(),
    new Date().getTimezoneOffset().toString(),
    navigator.hardwareConcurrency?.toString() || '0',
  ];

  const data = components.join('|');
  const encoder = new TextEncoder();
  const hash = await crypto.subtle.digest('SHA-256', encoder.encode(data));

  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Get device information for registration.
 */
export async function getDeviceInfo(): Promise<DeviceInfo> {
  const fingerprint = await generateDeviceFingerprint();

  // Parse user agent for browser info
  const ua = navigator.userAgent;
  let browserName = 'Unknown';
  let browserVersion = '0';

  if (ua.includes('Chrome')) {
    browserName = 'Chrome';
    const match = ua.match(/Chrome\/(\d+)/);
    if (match) browserVersion = match[1];
  } else if (ua.includes('Firefox')) {
    browserName = 'Firefox';
    const match = ua.match(/Firefox\/(\d+)/);
    if (match) browserVersion = match[1];
  } else if (ua.includes('Safari')) {
    browserName = 'Safari';
    const match = ua.match(/Version\/(\d+)/);
    if (match) browserVersion = match[1];
  } else if (ua.includes('Edge')) {
    browserName = 'Edge';
    const match = ua.match(/Edg\/(\d+)/);
    if (match) browserVersion = match[1];
  }

  // Detect OS
  let osName = 'Unknown';
  if (ua.includes('Mac')) osName = 'macOS';
  else if (ua.includes('Windows')) osName = 'Windows';
  else if (ua.includes('Linux')) osName = 'Linux';
  else if (ua.includes('Android')) osName = 'Android';
  else if (ua.includes('iOS') || ua.includes('iPhone') || ua.includes('iPad'))
    osName = 'iOS';

  return {
    fingerprint,
    name: `${browserName} on ${osName}`,
    type: 'web',
    model: browserName,
    os_version: browserVersion,
    app_version: APP_VERSION,
  };
}

/**
 * Register a new user account.
 *
 * @param email - User email address
 * @param password - User password
 * @param displayName - User display name
 * @param ageAttestation - User confirms they are at least 13 years old (required)
 * @returns Auth response with user and tokens
 */
export async function register(
  email: string,
  password: string,
  displayName: string,
  ageAttestation: boolean
): Promise<AuthResponse> {
  const device = await getDeviceInfo();

  const request: RegisterRequest = {
    email,
    password,
    display_name: displayName,
    age_attestation: ageAttestation,
    device,
  };

  const response = await post<AuthResponse>('/auth/register', request, {
    skipAuth: true,
  });

  // Store tokens
  tokenManager.setTokens(response.tokens);

  return response;
}

/**
 * Login with email and password.
 *
 * @param email - User email address
 * @param password - User password
 * @returns Auth response with user and tokens
 */
export async function login(
  email: string,
  password: string
): Promise<AuthResponse> {
  const device = await getDeviceInfo();

  const request: LoginRequest = {
    email,
    password,
    device,
  };

  const response = await post<AuthResponse>('/auth/login', request, {
    skipAuth: true,
  });

  // Store tokens
  tokenManager.setTokens(response.tokens);

  return response;
}

/**
 * Refresh the access token using the refresh token.
 *
 * @param refreshToken - The refresh token to use
 * @returns New token pair
 */
export async function refreshTokens(
  refreshToken: string
): Promise<RefreshResponse> {
  const response = await post<RefreshResponse>(
    '/auth/refresh',
    { refresh_token: refreshToken },
    { skipAuth: true }
  );

  return response;
}

/**
 * Logout and revoke tokens.
 *
 * @param allDevices - If true, logout from all devices
 */
export async function logout(allDevices: boolean = false): Promise<void> {
  const refreshToken = tokenManager.getRefreshToken();

  if (refreshToken) {
    const request: LogoutRequest = {
      refresh_token: refreshToken,
      all_devices: allDevices,
    };

    try {
      await post('/auth/logout', request);
    } catch {
      // Ignore errors on logout - we're clearing tokens anyway
    }
  }

  // Clear local tokens
  tokenManager.clear();
}

/**
 * Get the current user profile.
 *
 * @returns User profile
 */
export async function getCurrentUser(): Promise<{ user: User }> {
  return get<{ user: User }>('/auth/me');
}

/**
 * Update the current user profile.
 *
 * @param updates - Profile updates
 * @returns Updated user profile
 */
export async function updateCurrentUser(
  updates: UserUpdateRequest
): Promise<{ user: User }> {
  return patch<{ user: User }>('/auth/me', updates);
}

/**
 * Change user password.
 *
 * @param currentPassword - Current password
 * @param newPassword - New password
 */
export async function changePassword(
  currentPassword: string,
  newPassword: string
): Promise<{ message: string }> {
  const request: PasswordChangeRequest = {
    current_password: currentPassword,
    new_password: newPassword,
  };

  return post<{ message: string }>('/auth/password', request);
}

/**
 * List registered devices.
 *
 * @returns List of devices
 */
export async function listDevices(): Promise<DeviceListResponse> {
  return get<DeviceListResponse>('/auth/devices');
}

/**
 * Remove a device.
 *
 * @param deviceId - Device ID to remove
 */
export async function removeDevice(
  deviceId: string
): Promise<{ message: string }> {
  return del<{ message: string }>(`/auth/devices/${deviceId}`);
}

/**
 * List active sessions.
 *
 * @returns List of sessions
 */
export async function listSessions(): Promise<SessionListResponse> {
  return get<SessionListResponse>('/auth/sessions');
}

/**
 * Terminate a session.
 *
 * @param sessionId - Session ID to terminate
 */
export async function terminateSession(
  sessionId: string
): Promise<{ message: string }> {
  return del<{ message: string }>(`/auth/sessions/${sessionId}`);
}

// Initialize token manager with refresh callback
tokenManager.setRefreshCallback(async (refreshToken: string) => {
  const response = await refreshTokens(refreshToken);
  return response.tokens;
});
