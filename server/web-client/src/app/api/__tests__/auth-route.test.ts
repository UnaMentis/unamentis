/**
 * Auth API Route Tests
 *
 * Integration tests for the auth proxy route.
 */

import { describe, it, expect, beforeEach, vi, type Mock } from 'vitest';
import { NextRequest } from 'next/server';
import { GET, POST, PUT, DELETE, PATCH } from '../auth/[...path]/route';

// Mock fetch
global.fetch = vi.fn();

describe('Auth API Route', () => {
  const baseUrl = 'http://localhost:3000';

  beforeEach(() => {
    vi.clearAllMocks();
    (global.fetch as Mock).mockResolvedValue({
      status: 200,
      text: async () => JSON.stringify({ success: true }),
      headers: new Headers({ 'Content-Type': 'application/json' }),
    });
  });

  describe('GET requests', () => {
    it('should proxy GET requests to management API', async () => {
      const request = new NextRequest(`${baseUrl}/api/auth/me`);
      const params = Promise.resolve({ path: ['me'] });

      await GET(request, { params });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/auth/me'),
        expect.objectContaining({ method: 'GET' })
      );
    });

    it('should forward headers', async () => {
      const request = new NextRequest(`${baseUrl}/api/auth/me`, {
        headers: {
          Authorization: 'Bearer token123',
          'Content-Type': 'application/json',
        },
      });
      const params = Promise.resolve({ path: ['me'] });

      await GET(request, { params });

      const fetchCall = (global.fetch as Mock).mock.calls[0];
      // Headers are forwarded as an object, check the authorization header
      expect(fetchCall[1].headers).toBeDefined();
      expect(fetchCall[1].headers['authorization']).toBe('Bearer token123');
    });

    it('should handle multi-segment paths', async () => {
      const request = new NextRequest(`${baseUrl}/api/auth/devices/123`);
      const params = Promise.resolve({ path: ['devices', '123'] });

      await GET(request, { params });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/auth/devices/123'),
        expect.any(Object)
      );
    });
  });

  describe('POST requests', () => {
    it('should proxy POST requests with body', async () => {
      const body = JSON.stringify({ email: 'test@example.com', password: 'password123' });
      const request = new NextRequest(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        body,
        headers: { 'Content-Type': 'application/json' },
      });
      const params = Promise.resolve({ path: ['login'] });

      await POST(request, { params });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/auth/login'),
        expect.objectContaining({
          method: 'POST',
          body: expect.any(String),
        })
      );
    });

    it('should handle registration requests', async () => {
      const body = JSON.stringify({
        email: 'new@example.com',
        password: 'Password123',
        display_name: 'New User',
      });
      const request = new NextRequest(`${baseUrl}/api/auth/register`, {
        method: 'POST',
        body,
        headers: { 'Content-Type': 'application/json' },
      });
      const params = Promise.resolve({ path: ['register'] });

      await POST(request, { params });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/auth/register'),
        expect.objectContaining({ method: 'POST' })
      );
    });

    it('should handle refresh token requests', async () => {
      const body = JSON.stringify({ refresh_token: 'refresh-token-123' });
      const request = new NextRequest(`${baseUrl}/api/auth/refresh`, {
        method: 'POST',
        body,
        headers: { 'Content-Type': 'application/json' },
      });
      const params = Promise.resolve({ path: ['refresh'] });

      await POST(request, { params });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/auth/refresh'),
        expect.objectContaining({ method: 'POST' })
      );
    });
  });

  describe('PUT requests', () => {
    it('should proxy PUT requests with body', async () => {
      const body = JSON.stringify({ display_name: 'Updated Name' });
      const request = new NextRequest(`${baseUrl}/api/auth/profile`, {
        method: 'PUT',
        body,
        headers: { 'Content-Type': 'application/json' },
      });
      const params = Promise.resolve({ path: ['profile'] });

      await PUT(request, { params });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/auth/profile'),
        expect.objectContaining({
          method: 'PUT',
          body: expect.any(String),
        })
      );
    });
  });

  describe('PATCH requests', () => {
    it('should proxy PATCH requests with body', async () => {
      const body = JSON.stringify({ display_name: 'Patched Name' });
      const request = new NextRequest(`${baseUrl}/api/auth/me`, {
        method: 'PATCH',
        body,
        headers: { 'Content-Type': 'application/json' },
      });
      const params = Promise.resolve({ path: ['me'] });

      await PATCH(request, { params });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/auth/me'),
        expect.objectContaining({
          method: 'PATCH',
          body: expect.any(String),
        })
      );
    });
  });

  describe('DELETE requests', () => {
    it('should proxy DELETE requests', async () => {
      const request = new NextRequest(`${baseUrl}/api/auth/devices/123`, {
        method: 'DELETE',
      });
      const params = Promise.resolve({ path: ['devices', '123'] });

      await DELETE(request, { params });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/auth/devices/123'),
        expect.objectContaining({ method: 'DELETE' })
      );
    });

    it('should handle session termination', async () => {
      const request = new NextRequest(`${baseUrl}/api/auth/sessions/abc123`, {
        method: 'DELETE',
      });
      const params = Promise.resolve({ path: ['sessions', 'abc123'] });

      await DELETE(request, { params });

      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/auth/sessions/abc123'),
        expect.objectContaining({ method: 'DELETE' })
      );
    });
  });

  describe('response handling', () => {
    it('should return proxied response with status', async () => {
      (global.fetch as Mock).mockResolvedValueOnce({
        status: 201,
        text: async () => JSON.stringify({ user: { id: '123' } }),
        headers: new Headers({ 'Content-Type': 'application/json' }),
      });

      const request = new NextRequest(`${baseUrl}/api/auth/register`, {
        method: 'POST',
        body: JSON.stringify({ email: 'test@example.com' }),
      });
      const params = Promise.resolve({ path: ['register'] });

      const response = await POST(request, { params });
      expect(response.status).toBe(201);
    });

    it('should forward error responses', async () => {
      (global.fetch as Mock).mockResolvedValueOnce({
        status: 401,
        text: async () =>
          JSON.stringify({ error: 'invalid_credentials', message: 'Invalid credentials' }),
        headers: new Headers({ 'Content-Type': 'application/json' }),
      });

      const request = new NextRequest(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        body: JSON.stringify({ email: 'test@example.com', password: 'wrong' }),
      });
      const params = Promise.resolve({ path: ['login'] });

      const response = await POST(request, { params });
      expect(response.status).toBe(401);

      const body = await response.json();
      expect(body.error).toBe('invalid_credentials');
    });

    it('should forward Content-Type header', async () => {
      (global.fetch as Mock).mockResolvedValueOnce({
        status: 200,
        text: async () => JSON.stringify({ success: true }),
        headers: new Headers({ 'Content-Type': 'application/json; charset=utf-8' }),
      });

      const request = new NextRequest(`${baseUrl}/api/auth/me`);
      const params = Promise.resolve({ path: ['me'] });

      const response = await GET(request, { params });
      expect(response.headers.get('Content-Type')).toContain('application/json');
    });
  });

  describe('error handling', () => {
    it('should return 502 on network error', async () => {
      (global.fetch as Mock).mockRejectedValueOnce(new Error('Network error'));

      const request = new NextRequest(`${baseUrl}/api/auth/me`);
      const params = Promise.resolve({ path: ['me'] });

      const response = await GET(request, { params });
      expect(response.status).toBe(502);

      const body = await response.json();
      expect(body.error).toBe('Failed to connect to authentication service');
    });

    it('should return 502 on timeout', async () => {
      (global.fetch as Mock).mockRejectedValueOnce(new Error('Timeout'));

      const request = new NextRequest(`${baseUrl}/api/auth/me`);
      const params = Promise.resolve({ path: ['me'] });

      const response = await GET(request, { params });
      expect(response.status).toBe(502);
    });
  });

  describe('header filtering', () => {
    it('should not forward host header', async () => {
      const request = new NextRequest(`${baseUrl}/api/auth/me`, {
        headers: {
          host: 'localhost:3000',
          Authorization: 'Bearer token',
        },
      });
      const params = Promise.resolve({ path: ['me'] });

      await GET(request, { params });

      const fetchCall = (global.fetch as Mock).mock.calls[0];
      expect(fetchCall[1].headers['host']).toBeUndefined();
    });

    it('should not forward connection header', async () => {
      const request = new NextRequest(`${baseUrl}/api/auth/me`, {
        headers: {
          connection: 'keep-alive',
          Authorization: 'Bearer token',
        },
      });
      const params = Promise.resolve({ path: ['me'] });

      await GET(request, { params });

      const fetchCall = (global.fetch as Mock).mock.calls[0];
      expect(fetchCall[1].headers['connection']).toBeUndefined();
    });
  });

  describe('refresh token cookie (B6)', () => {
    function jsonResponse(status: number, payload: unknown) {
      return {
        status,
        text: async () => JSON.stringify(payload),
        headers: new Headers({ 'Content-Type': 'application/json' }),
      };
    }

    it('moves the login refresh token into an HttpOnly, SameSite=Strict cookie and strips it from the body', async () => {
      (global.fetch as Mock).mockResolvedValueOnce(
        jsonResponse(200, {
          user: { id: '123' },
          tokens: {
            access_token: 'access-abc',
            refresh_token: 'refresh-xyz',
            token_type: 'Bearer',
            expires_in: 900,
          },
        })
      );

      const request = new NextRequest(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        body: JSON.stringify({ email: 'a@b.com', password: 'x' }),
        headers: { 'Content-Type': 'application/json' },
      });
      const response = await POST(request, { params: Promise.resolve({ path: ['login'] }) });

      const setCookie = response.headers.get('set-cookie') || '';
      expect(setCookie).toContain('unamentis_refresh=refresh-xyz');
      expect(setCookie.toLowerCase()).toContain('httponly');
      expect(setCookie.toLowerCase()).toContain('samesite=strict');
      expect(setCookie).toContain('Path=/api/auth');

      const body = await response.json();
      expect(body.tokens.access_token).toBe('access-abc');
      expect(body.tokens.refresh_token).toBeUndefined();
    });

    it('injects the cookie token into the upstream refresh body and rotates the cookie', async () => {
      (global.fetch as Mock).mockResolvedValueOnce(
        jsonResponse(200, {
          tokens: {
            access_token: 'access-new',
            refresh_token: 'refresh-rotated',
            token_type: 'Bearer',
            expires_in: 900,
          },
        })
      );

      const request = new NextRequest(`${baseUrl}/api/auth/refresh`, {
        method: 'POST',
        body: JSON.stringify({}),
        headers: { 'Content-Type': 'application/json', Cookie: 'unamentis_refresh=refresh-old' },
      });
      const response = await POST(request, { params: Promise.resolve({ path: ['refresh'] }) });

      const fetchCall = (global.fetch as Mock).mock.calls[0];
      expect(JSON.parse(fetchCall[1].body)).toEqual({ refresh_token: 'refresh-old' });

      const setCookie = response.headers.get('set-cookie') || '';
      expect(setCookie).toContain('unamentis_refresh=refresh-rotated');

      const body = await response.json();
      expect(body.tokens.access_token).toBe('access-new');
      expect(body.tokens.refresh_token).toBeUndefined();
    });

    it('clears the cookie and forwards the token on logout', async () => {
      (global.fetch as Mock).mockResolvedValueOnce(
        jsonResponse(200, { message: 'Logged out successfully' })
      );

      const request = new NextRequest(`${baseUrl}/api/auth/logout`, {
        method: 'POST',
        body: JSON.stringify({ all_devices: false }),
        headers: { 'Content-Type': 'application/json', Cookie: 'unamentis_refresh=refresh-old' },
      });
      const response = await POST(request, { params: Promise.resolve({ path: ['logout'] }) });

      const fetchCall = (global.fetch as Mock).mock.calls[0];
      expect(JSON.parse(fetchCall[1].body)).toEqual({
        all_devices: false,
        refresh_token: 'refresh-old',
      });

      const setCookie = response.headers.get('set-cookie') || '';
      expect(setCookie).toContain('unamentis_refresh=');
      expect(setCookie).toContain('Max-Age=0');
    });

    it('clears the cookie when a refresh fails', async () => {
      (global.fetch as Mock).mockResolvedValueOnce(
        jsonResponse(401, { error: 'invalid_token' })
      );

      const request = new NextRequest(`${baseUrl}/api/auth/refresh`, {
        method: 'POST',
        body: JSON.stringify({}),
        headers: { 'Content-Type': 'application/json', Cookie: 'unamentis_refresh=refresh-old' },
      });
      const response = await POST(request, { params: Promise.resolve({ path: ['refresh'] }) });

      expect(response.status).toBe(401);
      const setCookie = response.headers.get('set-cookie') || '';
      expect(setCookie).toContain('Max-Age=0');
    });

    it('does not set a cookie for non-token auth routes', async () => {
      (global.fetch as Mock).mockResolvedValueOnce(
        jsonResponse(200, { user: { id: '123' } })
      );

      const request = new NextRequest(`${baseUrl}/api/auth/me`);
      const response = await GET(request, { params: Promise.resolve({ path: ['me'] }) });

      expect(response.headers.get('set-cookie')).toBeNull();
    });
  });
});
