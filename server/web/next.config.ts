import type { NextConfig } from 'next';

// Content-Security-Policy for the Operations Console (audit finding B6).
//
// Shipped REPORT-ONLY first: the browser connects directly to the Management
// API (see app/providers.tsx via NEXT_PUBLIC_MANAGEMENT_SERVER_URL) for live
// data, and the console renders ECharts with inline styles, so the connect-src
// and style-src need verifying against the running app before this is promoted
// to an enforcing `Content-Security-Policy`. Report-only reports violations
// without blocking, so it is safe to land now. The Management origin (and its
// ws:// form for live streams) is derived from the env var rather than
// hardcoded so it stays correct in every deployment.
const managementOrigin = process.env.NEXT_PUBLIC_MANAGEMENT_SERVER_URL || 'http://localhost:8766';
const managementWsOrigin = managementOrigin.replace(/^http/, 'ws');

const contentSecurityPolicy = [
  "default-src 'self'",
  // 'unsafe-eval'/'unsafe-inline' cover Next.js' dev HMR and inline bootstrap;
  // tracked for tightening to nonces/hashes once report-only is verified clean.
  "script-src 'self' 'unsafe-eval' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https://images.unsplash.com",
  "font-src 'self' data:",
  `connect-src 'self' ${managementOrigin} ${managementWsOrigin}`,
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
].join('; ');

const nextConfig: NextConfig = {
  // Security headers applied to all responses.
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          {
            key: 'X-Frame-Options',
            value: 'DENY',
          },
          {
            key: 'X-Content-Type-Options',
            value: 'nosniff',
          },
          {
            key: 'Referrer-Policy',
            value: 'strict-origin-when-cross-origin',
          },
          {
            key: 'Strict-Transport-Security',
            value: 'max-age=31536000; includeSubDomains',
          },
          {
            // Report-only until verified against the running console, then
            // promote to 'Content-Security-Policy'. See note above.
            key: 'Content-Security-Policy-Report-Only',
            value: contentSecurityPolicy,
          },
        ],
      },
    ];
  },
};

export default nextConfig;
