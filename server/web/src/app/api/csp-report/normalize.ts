/**
 * Normalization for CSP violation reports (audit finding B6).
 *
 * Browsers deliver violations in two formats: the legacy report-uri shape
 * (application/csp-report, kebab-case keys wrapped in "csp-report") and the
 * Reporting API shape (application/reports+json, an array of typed reports
 * with camelCase body keys). Both are reduced to one NormalizedViolation
 * shape so the log intake sees consistent fields.
 *
 * Kept separate from route.ts because Next.js route modules may only export
 * HTTP method handlers and route config fields.
 */

export interface NormalizedViolation {
  documentUri: string;
  effectiveDirective: string;
  blockedUri: string;
  disposition: string;
  sourceFile: string;
  lineNumber: number;
  columnNumber: number;
  originalPolicy: string;
  sample: string;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function str(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function num(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/** Normalize the legacy report-uri shape: { "csp-report": { kebab-case keys } }. */
function normalizeLegacyReport(report: Record<string, unknown>): NormalizedViolation {
  return {
    documentUri: str(report['document-uri']),
    effectiveDirective: str(report['effective-directive']) || str(report['violated-directive']),
    blockedUri: str(report['blocked-uri']),
    disposition: str(report['disposition']) || 'enforce',
    sourceFile: str(report['source-file']),
    lineNumber: num(report['line-number']),
    columnNumber: num(report['column-number']),
    originalPolicy: str(report['original-policy']),
    sample: str(report['script-sample']),
  };
}

/** Normalize one Reporting API entry: { type: "csp-violation", body: { camelCase keys } }. */
function normalizeReportingApiEntry(body: Record<string, unknown>): NormalizedViolation {
  return {
    documentUri: str(body.documentURL),
    effectiveDirective: str(body.effectiveDirective),
    blockedUri: str(body.blockedURL),
    disposition: str(body.disposition) || 'enforce',
    sourceFile: str(body.sourceFile),
    lineNumber: num(body.lineNumber),
    columnNumber: num(body.columnNumber),
    originalPolicy: str(body.originalPolicy),
    sample: str(body.sample),
  };
}

/** Extract CSP violations from either delivery format, ignoring everything else. */
export function extractViolations(payload: unknown): NormalizedViolation[] {
  // Reporting API (application/reports+json): an array of typed reports.
  if (Array.isArray(payload)) {
    const violations: NormalizedViolation[] = [];
    for (const entry of payload) {
      const record = asRecord(entry);
      if (!record || record.type !== 'csp-violation') continue;
      const body = asRecord(record.body);
      if (!body) continue;
      violations.push(normalizeReportingApiEntry(body));
    }
    return violations;
  }

  const record = asRecord(payload);
  if (!record) return [];

  // Legacy report-uri (application/csp-report): a single wrapped report.
  const legacy = asRecord(record['csp-report']);
  if (legacy) return [normalizeLegacyReport(legacy)];

  // A single unwrapped Reporting API entry, just in case.
  if (record.type === 'csp-violation') {
    const body = asRecord(record.body);
    if (body) return [normalizeReportingApiEntry(body)];
  }

  return [];
}
