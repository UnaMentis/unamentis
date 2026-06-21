import type { NextConfig } from 'next';

// Content-Security-Policy for the learner-facing voice client.
//
// The policy is now ENFORCED via `Content-Security-Policy` (audit finding B6),
// with the `Content-Security-Policy-Report-Only` twin kept in parallel for at
// least one release so any drift keeps reporting even if enforcement has to
// be relaxed. This client drives a live voice pipeline (WebRTC to OpenAI
// Realtime, Deepgram/ElevenLabs streaming, audio worklets, blob workers) plus
// KaTeX and Leaflet, and every directive below was checked against those
// surfaces. Violations from either header are delivered to /api/csp-report
// (see report-uri/report-to and the Reporting-Endpoints header below), which
// forwards them to the Management API log intake.
//
// connect-src: OpenAI Realtime SDP exchange (https://api.openai.com) and the
//   Deepgram/ElevenLabs streaming sockets are reached directly from the browser;
//   the Management API is same-origin through the /api rewrite below.
// img-src / style-src: map tiles + Leaflet assets (unpkg) and KaTeX/Tailwind
//   inline styles. worker-src/media-src: audio worklets, VAD, blob playback.
const contentSecurityPolicy = [
  "default-src 'self'",
  // 'unsafe-eval'/'unsafe-inline' cover Next.js' dev HMR and inline bootstrap.
  // Tracked for tightening to nonces/hashes now that reporting is in place.
  "script-src 'self' 'unsafe-eval' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline' https://unpkg.com",
  "img-src 'self' data: blob: https://server.arcgisonline.com https://tiles.stadiamaps.com https://unpkg.com",
  "font-src 'self' data:",
  "connect-src 'self' https://api.openai.com wss://api.deepgram.com wss://api.elevenlabs.io",
  "media-src 'self' blob:",
  "worker-src 'self' blob:",
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
  // Enable React strict mode for better development experience
  reactStrictMode: true,

  // Experimental features
  experimental: {
    // Enable server actions
    serverActions: {
      bodySizeLimit: '2mb',
    },
  },

  // Image optimization domains
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'localhost',
        port: '8766',
        pathname: '/api/media/**',
      },
      // Add production CDN domains here
    ],
  },

  // Headers for security
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

  // Rewrites for API proxy during development.
  //
  // IMPORTANT: /api/auth/* is deliberately excluded so it falls through to the
  // app/api/auth/[...path] route handler, which is the cookie adapter for the
  // refresh token (B6). Next evaluates afterFiles rewrites BEFORE catch-all
  // dynamic routes, so without this exclusion the rewrite would shadow the auth
  // handler and the refresh-token cookie logic would never run.
  async rewrites() {
    return [
      {
        source: '/api/:path((?!auth/).*)',
        destination: `${process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8766'}/api/:path`,
      },
    ];
  },
};

export default nextConfig;
