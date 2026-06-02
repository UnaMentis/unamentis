/**
 * Auth API Tests
 */

import { describe, it, expect, beforeEach, vi, type Mock } from 'vitest';
import {
  login,
  register,
  logout,
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
} from '../auth';
import { tokenManager } from '../token-manager';
import * as client from '../client';
import { mockUser, mockTokenPair, mockAuthResponse } from '@/__tests__/mocks';

// Mock the client module
vi.mock('../client', () => ({
  get: vi.fn(),
  post: vi.fn(),
  patch: vi.fn(),
  del: vi.fn(),
}));

// Mock tokenManager
vi.mock('../token-manager', () => ({
  tokenManager: {
    setTokens: vi.fn(),
    getRefreshToken: vi.fn(),
    clear: vi.fn(),
    setRefreshCallback: vi.fn(),
  },
}));

describe('Auth API', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('generateDeviceFingerprint', () => {
    it('should generate a fingerprint hash', async () => {
      const fingerprint = await generateDeviceFingerprint();
      expect(fingerprint).toBeDefined();
      expect(typeof fingerprint).toBe('string');
    });
  });

  describe('getDeviceInfo', () => {
    it('should return device information', async () => {
      const deviceInfo = await getDeviceInfo();

      expect(deviceInfo).toHaveProperty('fingerprint');
      expect(deviceInfo).toHaveProperty('name');
      expect(deviceInfo).toHaveProperty('type', 'web');
      expect(deviceInfo).toHaveProperty('model');
      expect(deviceInfo).toHaveProperty('os_version');
      expect(deviceInfo).toHaveProperty('app_version');
    });

    it('should detect Chrome browser', async () => {
      Object.defineProperty(navigator, 'userAgent', {
        value: 'Mozilla/5.0 Chrome/120.0.0.0',
        writable: true,
      });

      const deviceInfo = await getDeviceInfo();
      expect(deviceInfo.model).toBe('Chrome');
    });
  });

  describe('register', () => {
    it('should register a new user', async () => {
      (client.post as Mock).mockResolvedValue(mockAuthResponse);

      const result = await register('test@example.com', 'password123', 'Test User', true);

      expect(client.post).toHaveBeenCalledWith(
        '/auth/register',
        expect.objectContaining({
          email: 'test@example.com',
          password: 'password123',
          display_name: 'Test User',
          age_attestation: true,
          device: expect.any(Object),
        }),
        { skipAuth: true }
      );

      expect(tokenManager.setTokens).toHaveBeenCalledWith(mockAuthResponse.tokens);
      expect(result.user).toEqual(mockUser);
    });

    it('should propagate errors from registration', async () => {
      (client.post as Mock).mockRejectedValue(new Error('Email already exists'));

      await expect(
        register('test@example.com', 'password123', 'Test User', true)
      ).rejects.toThrow('Email already exists');
    });
  });

  describe('login', () => {
    it('should login a user', async () => {
      (client.post as Mock).mockResolvedValue(mockAuthResponse);

      const result = await login('test@example.com', 'password123');

      expect(client.post).toHaveBeenCalledWith(
        '/auth/login',
        expect.objectContaining({
          email: 'test@example.com',
          password: 'password123',
          device: expect.any(Object),
        }),
        { skipAuth: true }
      );

      expect(tokenManager.setTokens).toHaveBeenCalledWith(mockAuthResponse.tokens);
      expect(result.user).toEqual(mockUser);
    });

    it('should propagate login errors', async () => {
      (client.post as Mock).mockRejectedValue(new Error('Invalid credentials'));

      await expect(login('test@example.com', 'wrongpassword')).rejects.toThrow(
        'Invalid credentials'
      );
    });
  });

  describe('refreshTokens', () => {
    it('should refresh tokens', async () => {
      const refreshResponse = { tokens: mockTokenPair };
      (client.post as Mock).mockResolvedValue(refreshResponse);

      const result = await refreshTokens('old-refresh-token');

      expect(client.post).toHaveBeenCalledWith(
        '/auth/refresh',
        { refresh_token: 'old-refresh-token' },
        { skipAuth: true }
      );

      expect(result.tokens).toEqual(mockTokenPair);
    });
  });

  describe('logout', () => {
    it('should logout and clear tokens', async () => {
      (tokenManager.getRefreshToken as Mock).mockReturnValue('refresh-token');
      (client.post as Mock).mockResolvedValue({});

      await logout();

      expect(client.post).toHaveBeenCalledWith('/auth/logout', {
        refresh_token: 'refresh-token',
        all_devices: false,
      });
      expect(tokenManager.clear).toHaveBeenCalled();
    });

    it('should logout from all devices when specified', async () => {
      (tokenManager.getRefreshToken as Mock).mockReturnValue('refresh-token');
      (client.post as Mock).mockResolvedValue({});

      await logout(true);

      expect(client.post).toHaveBeenCalledWith('/auth/logout', {
        refresh_token: 'refresh-token',
        all_devices: true,
      });
    });

    it('should clear tokens even if logout API fails', async () => {
      (tokenManager.getRefreshToken as Mock).mockReturnValue('refresh-token');
      (client.post as Mock).mockRejectedValue(new Error('Network error'));

      await logout();

      expect(tokenManager.clear).toHaveBeenCalled();
    });

    it('should skip API call if no refresh token', async () => {
      (tokenManager.getRefreshToken as Mock).mockReturnValue(null);

      await logout();

      expect(client.post).not.toHaveBeenCalled();
      expect(tokenManager.clear).toHaveBeenCalled();
    });
  });

  describe('getCurrentUser', () => {
    it('should get current user profile', async () => {
      (client.get as Mock).mockResolvedValue({ user: mockUser });

      const result = await getCurrentUser();

      expect(client.get).toHaveBeenCalledWith('/auth/me');
      expect(result.user).toEqual(mockUser);
    });
  });

  describe('updateCurrentUser', () => {
    it('should update user profile', async () => {
      const updates = { display_name: 'New Name' };
      (client.patch as Mock).mockResolvedValue({ user: { ...mockUser, display_name: 'New Name' } });

      const result = await updateCurrentUser(updates);

      expect(client.patch).toHaveBeenCalledWith('/auth/me', updates);
      expect(result.user.display_name).toBe('New Name');
    });
  });

  describe('changePassword', () => {
    it('should change password', async () => {
      (client.post as Mock).mockResolvedValue({ message: 'Password changed successfully' });

      const result = await changePassword('oldPassword', 'newPassword');

      expect(client.post).toHaveBeenCalledWith('/auth/password', {
        current_password: 'oldPassword',
        new_password: 'newPassword',
      });
      expect(result.message).toBe('Password changed successfully');
    });
  });

  describe('listDevices', () => {
    it('should list registered devices', async () => {
      const mockDevices = [{ id: 'device-1', name: 'Chrome on macOS' }];
      (client.get as Mock).mockResolvedValue({ devices: mockDevices });

      const result = await listDevices();

      expect(client.get).toHaveBeenCalledWith('/auth/devices');
      expect(result.devices).toEqual(mockDevices);
    });
  });

  describe('removeDevice', () => {
    it('should remove a device', async () => {
      (client.del as Mock).mockResolvedValue({ message: 'Device removed' });

      const result = await removeDevice('device-123');

      expect(client.del).toHaveBeenCalledWith('/auth/devices/device-123');
      expect(result.message).toBe('Device removed');
    });
  });

  describe('listSessions', () => {
    it('should list active sessions', async () => {
      const mockSessions = [{ id: 'session-1', ip_address: '127.0.0.1' }];
      (client.get as Mock).mockResolvedValue({ sessions: mockSessions });

      const result = await listSessions();

      expect(client.get).toHaveBeenCalledWith('/auth/sessions');
      expect(result.sessions).toEqual(mockSessions);
    });
  });

  describe('terminateSession', () => {
    it('should terminate a session', async () => {
      (client.del as Mock).mockResolvedValue({ message: 'Session terminated' });

      const result = await terminateSession('session-123');

      expect(client.del).toHaveBeenCalledWith('/auth/sessions/session-123');
      expect(result.message).toBe('Session terminated');
    });
  });
});
