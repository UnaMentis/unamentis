/**
 * Auth API Proxy
 *
 * Proxies authentication requests to the Management API on port 8766, and acts
 * as the cookie adapter for the refresh token (audit finding B6).
 *
 * The Management API speaks body-based tokens (it returns/accepts the refresh
 * token in JSON), which the mobile clients rely on. The browser, however, must
 * never see the long-lived refresh token in JS-readable form. So this proxy is
 * the single place that translates between the two:
 *   - on login/register/refresh responses it lifts `tokens.refresh_token` out of
 *     the JSON body and into an HttpOnly cookie, and strips it from the body;
 *   - on refresh/logout requests it reads that cookie back and injects it into
 *     the upstream JSON body so the Management API is unchanged;
 *   - on logout it clears the cookie.
 * The access token stays in the JSON body (memory-only on the client).
 */

import { NextRequest, NextResponse } from 'next/server';

const MANAGEMENT_API_URL = process.env.MANAGEMENT_API_URL || 'http://localhost:8766';

// HttpOnly refresh-token cookie. Path-scoped to /api/auth so it is only ever
// attached to the refresh and logout calls, minimizing exposure and CSRF surface.
const REFRESH_COOKIE = 'unamentis_refresh';
const REFRESH_COOKIE_MAX_AGE = 60 * 60 * 24 * 30; // 30 days

function refreshCookieOptions() {
  return {
    httpOnly: true,
    // Gated on prod so dev over http://localhost still works.
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict' as const,
    path: '/api/auth',
    maxAge: REFRESH_COOKIE_MAX_AGE,
  };
}

async function proxyRequest(request: NextRequest, path: string) {
  const url = `${MANAGEMENT_API_URL}/api/auth/${path}`;
  const isRefresh = path === 'refresh';
  const isLogout = path === 'logout';
  const isTokenIssuer = path === 'login' || path === 'register' || isRefresh;

  try {
    // Get request body for POST/PUT/PATCH requests
    let body: string | undefined;
    if (['POST', 'PUT', 'PATCH'].includes(request.method)) {
      body = await request.text();
    }

    // For refresh/logout, inject the HttpOnly refresh cookie into the upstream
    // body so the body-based Management API still receives the token.
    if (isRefresh || isLogout) {
      const cookieToken = request.cookies.get(REFRESH_COOKIE)?.value;
      if (cookieToken) {
        let parsed: Record<string, unknown> = {};
        if (body) {
          try {
            parsed = JSON.parse(body);
          } catch {
            parsed = {};
          }
        }
        parsed.refresh_token = cookieToken;
        body = JSON.stringify(parsed);
      }
    }

    // Forward headers (excluding host/connection, and content-length since the
    // body may have been rewritten above; fetch recomputes it).
    const headers: Record<string, string> = {};
    request.headers.forEach((value, key) => {
      if (!['host', 'connection', 'content-length'].includes(key.toLowerCase())) {
        headers[key] = value;
      }
    });
    if ((isRefresh || isLogout) && body) {
      headers['content-type'] = 'application/json';
    }

    // Make the proxied request
    const response = await fetch(url, {
      method: request.method,
      headers,
      body,
    });

    // Get response body
    let responseBody = await response.text();
    const ok = response.status >= 200 && response.status < 300;

    // On a successful token-issuing response, lift the refresh token out of the
    // JSON body and into the HttpOnly cookie (covers rotation on refresh too).
    let refreshTokenToSet: string | null = null;
    if (isTokenIssuer && ok && responseBody) {
      try {
        const data = JSON.parse(responseBody);
        const rt = data?.tokens?.refresh_token;
        if (typeof rt === 'string' && rt.length > 0) {
          refreshTokenToSet = rt;
          delete data.tokens.refresh_token;
          responseBody = JSON.stringify(data);
        }
      } catch {
        // Non-JSON or unexpected shape: pass the body through untouched.
      }
    }

    // Return proxied response
    const nextResponse = new NextResponse(responseBody, {
      status: response.status,
      headers: {
        'Content-Type': response.headers.get('Content-Type') || 'application/json',
      },
    });

    if (refreshTokenToSet) {
      nextResponse.cookies.set(REFRESH_COOKIE, refreshTokenToSet, refreshCookieOptions());
    }
    // Clear the cookie on logout, and on a failed refresh (the server has
    // revoked the family, so the stored token is now useless).
    if (isLogout || (isRefresh && !ok)) {
      nextResponse.cookies.set(REFRESH_COOKIE, '', {
        ...refreshCookieOptions(),
        maxAge: 0,
      });
    }

    return nextResponse;
  } catch (error) {
    console.error(`Auth proxy error for ${path}:`, error);
    return NextResponse.json(
      { error: 'Failed to connect to authentication service' },
      { status: 502 }
    );
  }
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params;
  return proxyRequest(request, path.join('/'));
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params;
  return proxyRequest(request, path.join('/'));
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params;
  return proxyRequest(request, path.join('/'));
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params;
  return proxyRequest(request, path.join('/'));
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params;
  return proxyRequest(request, path.join('/'));
}
