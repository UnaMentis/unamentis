/**
 * MSW server setup for Node.js test environment (Vitest).
 *
 * This provides network-level HTTP mocking that allows testing
 * the REAL api-client code instead of mocking it with vi.mock.
 */
import { setupServer } from 'msw/node';
import { handlers, mswTestState } from './msw-handlers';

// Create MSW server instance
export const server = setupServer(...handlers);

// Re-export test state manipulation
export { mswTestState };

// Re-export handler utilities for custom handlers in tests
export { http, HttpResponse } from 'msw';
export { handlers } from './msw-handlers';
