// Set environment variables BEFORE any imports that might use them
// This is crucial for api-client which evaluates USE_MOCK at import time
process.env.NEXT_PUBLIC_BACKEND_URL = 'http://localhost:8766';
process.env.NEXT_PUBLIC_USE_MOCK = 'false';

import '@testing-library/jest-dom/vitest';

// MSW is NOT enabled globally to avoid conflicts with tests
// that have their own fetch mocking (e.g., feature-flags tests).
//
// Tests that need MSW should add these imports:
//   import { server, mswTestState } from '@/test/msw-server';
//   import { beforeAll, afterAll, afterEach } from 'vitest';
//
// And these hooks:
//   beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
//   afterEach(() => { server.resetHandlers(); mswTestState.reset(); });
//   afterAll(() => server.close());
