/**
 * CSP report intake route tests (audit finding B6).
 *
 * Pins the contract the browser depends on: both delivery formats are
 * accepted and normalized, reports are forwarded to the Management API log
 * intake with the csp-report component, and every path (including malformed
 * payloads and a dead backend) fails silently with 204 No Content.
 */

import { describe, it, expect, beforeEach, vi, type Mock } from 'vitest';
import { NextRequest } from 'next/server';
import { POST } from '../csp-report/route';
import { extractViolations } from '../csp-report/normalize';

const URL = 'http://localhost:3000/api/csp-report';

function request(body: string, contentType: string): NextRequest {
  return new NextRequest(URL, {
    method: 'POST',
    headers: { 'Content-Type': contentType },
    body,
  });
}

const legacyPayload = {
  'csp-report': {
    'document-uri': 'http://localhost:3000/session',
    'violated-directive': "connect-src 'self'",
    'effective-directive': 'connect-src',
    'blocked-uri': 'wss://api.example.net/stream',
    'original-policy': "default-src 'self'",
    disposition: 'report',
    'source-file': 'http://localhost:3000/_next/static/chunks/app.js',
    'line-number': 42,
    'column-number': 7,
  },
};

const reportingApiPayload = [
  {
    type: 'csp-violation',
    url: 'http://localhost:3000/session',
    body: {
      documentURL: 'http://localhost:3000/session',
      effectiveDirective: 'img-src',
      blockedURL: 'https://evil.example/pixel.png',
      originalPolicy: "default-src 'self'",
      disposition: 'enforce',
      sourceFile: 'http://localhost:3000/_next/static/chunks/page.js',
      lineNumber: 10,
      columnNumber: 3,
    },
  },
  // Non-CSP report types arriving at the same endpoint must be ignored.
  { type: 'deprecation', url: 'http://localhost:3000/', body: { id: 'WebSQL' } },
];

describe('CSP report route', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    global.fetch = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ status: 'ok' }) });
  });

  it('forwards a legacy application/csp-report payload to the log intake', async () => {
    const res = await POST(request(JSON.stringify(legacyPayload), 'application/csp-report'));
    expect(res.status).toBe(204);

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [url, init] = (global.fetch as Mock).mock.calls[0];
    expect(String(url)).toContain('/api/logs');
    const entries = JSON.parse(init.body);
    expect(entries).toHaveLength(1);
    expect(entries[0].level).toBe('WARNING');
    expect(entries[0].label).toBe('csp-report');
    expect(entries[0].metadata.component).toBe('csp-report');
    expect(entries[0].metadata.effectiveDirective).toBe('connect-src');
    expect(entries[0].message).toContain('connect-src');
    expect(entries[0].message).toContain('wss://api.example.net/stream');
  });

  it('forwards application/reports+json violations and skips non-CSP types', async () => {
    const res = await POST(
      request(JSON.stringify(reportingApiPayload), 'application/reports+json')
    );
    expect(res.status).toBe(204);

    const [, init] = (global.fetch as Mock).mock.calls[0];
    const entries = JSON.parse(init.body);
    expect(entries).toHaveLength(1);
    expect(entries[0].metadata.blockedUri).toBe('https://evil.example/pixel.png');
    expect(entries[0].metadata.disposition).toBe('enforce');
  });

  it('returns 204 without forwarding on malformed JSON', async () => {
    const res = await POST(request('not json {', 'application/csp-report'));
    expect(res.status).toBe(204);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('returns 204 without forwarding when the payload has no CSP violations', async () => {
    const res = await POST(request(JSON.stringify({ hello: 'world' }), 'application/json'));
    expect(res.status).toBe(204);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('still returns 204 when the log intake is unreachable', async () => {
    (global.fetch as Mock).mockRejectedValue(new Error('connection refused'));
    const res = await POST(request(JSON.stringify(legacyPayload), 'application/csp-report'));
    expect(res.status).toBe(204);
  });

  it('caps the number of forwarded violations per request', async () => {
    const flood = Array.from({ length: 100 }, () => reportingApiPayload[0]);
    const res = await POST(request(JSON.stringify(flood), 'application/reports+json'));
    expect(res.status).toBe(204);
    const [, init] = (global.fetch as Mock).mock.calls[0];
    expect(JSON.parse(init.body).length).toBeLessThanOrEqual(20);
  });

  it('normalizes both formats to the same shape', () => {
    const legacy = extractViolations(legacyPayload)[0];
    const modern = extractViolations(reportingApiPayload)[0];
    expect(Object.keys(legacy).sort()).toEqual(Object.keys(modern).sort());
    expect(legacy.disposition).toBe('report');
    expect(modern.disposition).toBe('enforce');
  });
});
