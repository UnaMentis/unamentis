/**
 * Authentication Types
 * Based on Management API Reference
 */

// ===== User =====

export interface User {
  id: string;
  email: string;
  email_verified?: boolean;
  display_name: string;
  avatar_url?: string | null;
  locale?: string;
  timezone?: string;
  role: 'user' | 'admin';
  mfa_enabled?: boolean;
  created_at?: string;
  last_login_at?: string;
}

export interface UserUpdateRequest {
  display_name?: string;
  avatar_url?: string;
  locale?: string;
  timezone?: string;
}

// ===== Device =====

export interface DeviceInfo {
  fingerprint: string;
  name: string;
  type: 'web' | 'ios' | 'android' | 'desktop';
  model: string;
  os_version: string;
  app_version: string;
}

export interface RegisteredDevice {
  id: string;
  name: string;
  type: 'web' | 'ios' | 'android' | 'desktop';
  model: string;
  os_version: string;
  app_version: string;
  is_trusted: boolean;
  last_seen_at: string;
  created_at: string;
}

// ===== Tokens =====

export interface TokenPair {
  access_token: string;
  refresh_token: string;
  token_type: 'Bearer';
  expires_in: number;
}

// ===== Session =====

export interface AuthSession {
  id: string;
  ip_address: string;
  user_agent: string;
  location?: {
    country: string;
    city?: string;
  };
  device: {
    name: string;
    type: string;
  };
  created_at: string;
  last_activity_at: string;
}

// ===== Requests =====

export interface RegisterRequest {
  email: string;
  password: string;
  display_name: string;
  /** User confirms they are at least 13 years old (required by the server). */
  age_attestation: boolean;
  device: DeviceInfo;
}

export interface LoginRequest {
  email: string;
  password: string;
  device: DeviceInfo;
}

export interface RefreshTokenRequest {
  refresh_token: string;
}

export interface LogoutRequest {
  refresh_token: string;
  all_devices?: boolean;
}

export interface PasswordChangeRequest {
  current_password: string;
  new_password: string;
}

// ===== Responses =====

export interface AuthResponse {
  user: User;
  device: {
    id: string;
  };
  tokens: TokenPair;
}

export interface RefreshResponse {
  tokens: TokenPair;
}

export interface DeviceListResponse {
  devices: RegisteredDevice[];
}

export interface SessionListResponse {
  sessions: AuthSession[];
}

// ===== Auth State =====

export interface AuthState {
  isAuthenticated: boolean;
  isLoading: boolean;
  user: User | null;
  error: string | null;
}

// ===== Auth Context =====

export interface AuthContextValue extends AuthState {
  login: (email: string, password: string) => Promise<void>;
  register: (
    email: string,
    password: string,
    displayName: string,
    ageAttestation: boolean
  ) => Promise<void>;
  logout: () => Promise<void>;
  refreshToken: () => Promise<void>;
}
