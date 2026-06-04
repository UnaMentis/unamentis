import type { NextConfig } from 'next';

// Content-Security-Policy for the learner-facing voice client.
//
// Shipped in REPORT-ONLY mode first (audit finding B6). This client drives a
// live voice pipeline (WebRTC to OpenAI Realtime, Deepgram/ElevenLabs streaming,
// audio worklets, blob workers) plus KaTeX and Leaflet, so an untuned enforcing
// CSP would silently break the pipeline. Report-only lets the browser evaluate
// the policy and report violations without blocking anything, so the directive
// set can be verified against the running stack before it is promoted to the
// enforcing `Content-Security-Policy` header.
//
// connect-src: OpenAI Realtime SDP exchange (https://api.openai.com) and the
//   Deepgram/ElevenLabs streaming sockets are reached directly from the browser;
//   the Management API is same-origin through the /api rewrite below.
// img-src / style-src: map tiles + Leaflet assets (unpkg) and KaTeX/Tailwind
//   inline styles. worker-src/media-src: audio worklets, VAD, blob playback.
const contentSecurityPolicy = [
  "default-src 'self'",
  // 'unsafe-eval'/'unsafe-inline' cover Next.js' dev HMR and inline bootstrap.
  // Tracked for tightening to nonces/hashes once report-only is verified clean.
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
            // Report-only until verified against the running voice pipeline,
            // then promote to 'Content-Security-Policy'. See note above.
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
