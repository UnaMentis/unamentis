import type { NextConfig } from 'next';

// Content-Security-Policy for the Operations Console (audit finding B6).
//
// The policy is now ENFORCED via `Content-Security-Policy`, with the
// `Content-Security-Policy-Report-Only` twin kept in parallel for at least one
// release so any drift keeps reporting even if enforcement has to be relaxed.
// Violations from either header are delivered to /api/csp-report (see the
// report-uri/report-to directives and the Reporting-Endpoints header below),
// which forwards them to the Management API log intake. The Management origin
// (and its ws:// form for live streams) is derived from the env var rather
// than hardcoded so it stays correct in every deployment.
const managementOrigin = process.env.NEXT_PUBLIC_MANAGEMENT_SERVER_URL || 'http://localhost:8766';
const managementWsOrigin = managementOrigin.replace(/^http/, 'ws');

// The feature-flag proxy is fetched directly from the browser (see
// app/providers.tsx via NEXT_PUBLIC_FEATURE_FLAG_URL). The env var carries a
// path (default http://localhost:3063/proxy), so reduce it to an origin for
// connect-src; CSP source expressions with paths match too narrowly.
function deriveOrigin(url: string, fallback: string): string {
  try {
    return new URL(url).origin;
  } catch {
    return fallback;
  }
}
const featureFlagOrigin = deriveOrigin(
  process.env.NEXT_PUBLIC_FEATURE_FLAG_URL || 'http://localhost:3063',
  'http://localhost:3063'
);

const contentSecurityPolicy = [
  "default-src 'self'",
  // 'unsafe-eval'/'unsafe-inline' cover Next.js' dev HMR and inline bootstrap;
  // tracked for tightening to nonces/hashes now that reporting is in place.
  "script-src 'self' 'unsafe-eval' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https://images.unsplash.com",
  "font-src 'self' data:",
  `connect-src 'self' ${managementOrigin} ${managementWsOrigin} ${featureFlagOrigin}`,
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
  // Violation reporting: report-uri is the legacy delivery mechanism,
  // report-to uses the named endpoint from the Reporting-Endpoints header.
  'report-uri /api/csp-report',
  'report-to csp',
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
            // Named endpoint for the report-to directive. A relative URL is
            // resolved against the response URL per the Reporting API.
            key: 'Reporting-Endpoints',
            value: 'csp="/api/csp-report"',
          },
          {
            // Enforcing policy (B6 promotion). See note above.
            key: 'Content-Security-Policy',
            value: contentSecurityPolicy,
          },
          {
            // Report-only twin kept alongside enforcement for at least one
            // release so violations keep reporting if enforcement is relaxed.
            key: 'Content-Security-Policy-Report-Only',
            value: contentSecurityPolicy,
          },
        ],
      },
    ];
  },
};

export default nextConfig;
