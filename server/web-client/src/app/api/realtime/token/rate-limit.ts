/**
 * In-memory rate-limit guards for the realtime token route.
 *
 * Kept separate from route.ts because Next.js route modules may only export
 * HTTP method handlers and route config fields, and the tests need to reset
 * this state between cases. State is per server instance.
 */

const MINUTE_MS = 60_000;
const DAY_MS = 86_400_000;

// In-memory guard state (per server instance).
const perIdentity = new Map<string, number[]>();
let dayStart = 0;
let dayCount = 0;

/** Test-only: reset in-memory rate state between cases. */
export function __resetRateState(): void {
  perIdentity.clear();
  dayStart = 0;
  dayCount = 0;
}

/** Reserve one slot against the global daily cap. Returns false when exhausted. */
export function reserveDaily(now: number, dailyCap: number): boolean {
  if (now - dayStart >= DAY_MS) {
    dayStart = now;
    dayCount = 0;
  }
  if (dayCount >= dailyCap) {
    return false;
  }
  dayCount += 1;
  return true;
}

/** Record a hit for an identity. Returns false when over the per-minute limit. */
export function allowIdentity(identity: string, now: number, perMinute: number): boolean {
  const recent = (perIdentity.get(identity) ?? []).filter((t) => now - t < MINUTE_MS);
  if (recent.length >= perMinute) {
    perIdentity.set(identity, recent);
    return false;
  }
  recent.push(now);
  perIdentity.set(identity, recent);
  return true;
}
