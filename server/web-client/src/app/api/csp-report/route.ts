/**
 * CSP violation report intake (audit finding B6).
 *
 * Browsers POST violation reports here via the policy's report-uri directive
 * (Content-Type: application/csp-report) or via report-to and the
 * Reporting-Endpoints header (Content-Type: application/reports+json). Both
 * shapes are normalized (see normalize.ts) and forwarded to the Management
 * API log intake (POST /api/logs, public per the auth middleware) under the
 * 'csp-report' component so violations are visible alongside the rest of the
 * system logs.
 *
 * This concrete route wins over the /api/:path rewrite in next.config.ts
 * because Next.js checks filesystem routes before afterFiles rewrites; only
 * catch-all dynamic routes need the rewrite exclusion.
 *
 * Reporting must never surface an error to the browser: every path returns
 * 204 No Content, including malformed payloads and forwarding failures.
 */

import { NextRequest, NextResponse } from 'next/server';
import { extractViolations } from './normalize';

const MANAGEMENT_API_URL = process.env.MANAGEMENT_API_URL || 'http://localhost:8766';

// Cap forwarded violations per request so a misbehaving page cannot flood the
// log intake through this unauthenticated endpoint.
const MAX_REPORTS_PER_REQUEST = 20;

export async function POST(request: NextRequest): Promise<NextResponse> {
  try {
    const raw = await request.text();
    if (!raw) return new NextResponse(null, { status: 204 });

    let payload: unknown;
    try {
      payload = JSON.parse(raw);
    } catch {
      return new NextResponse(null, { status: 204 });
    }

    const violations = extractViolations(payload).slice(0, MAX_REPORTS_PER_REQUEST);
    if (violations.length === 0) return new NextResponse(null, { status: 204 });

    const entries = violations.map((v) => ({
      level: 'WARNING',
      label: 'csp-report',
      message: `CSP ${v.disposition} violation: ${v.effectiveDirective || 'unknown-directive'} blocked ${v.blockedUri || 'unknown-uri'} on ${v.documentUri || 'unknown-document'}`,
      file: v.sourceFile,
      line: v.lineNumber,
      metadata: { component: 'csp-report', app: 'web-client', ...v },
    }));

    await fetch(`${MANAGEMENT_API_URL}/api/logs`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Client-ID': 'web-client-csp-report',
        'X-Client-Name': 'Web Client CSP Reporter',
      },
      body: JSON.stringify(entries),
    });
  } catch {
    // Fail silently: violation reporting must never break the browser.
  }
  return new NextResponse(null, { status: 204 });
}
