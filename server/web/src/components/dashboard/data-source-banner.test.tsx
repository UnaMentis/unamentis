/**
 * DataSourceBanner rendering tests (T5/ND1).
 *
 * Uses the real provenance store, no module mocks. vitest.setup.ts configures
 * NEXT_PUBLIC_BACKEND_URL so the api-client is not in static demo mode.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen, fireEvent, act, cleanup } from '@testing-library/react';
import { DataSourceBanner } from './data-source-banner';
import {
  recordMockFallback,
  recordAuthRequired,
  resetDataSourceStatus,
  getDataSourceStatus,
  getMgmtApiToken,
  setMgmtApiToken,
} from '@/lib/data-source-status';

describe('DataSourceBanner', () => {
  beforeEach(() => {
    cleanup();
    window.localStorage.clear();
    setMgmtApiToken('');
    resetDataSourceStatus();
  });

  it('renders nothing while all data is live', () => {
    const { container } = render(<DataSourceBanner />);
    expect(container).toBeEmptyDOMElement();
  });

  it('shows the sample-data warning when a request fell back to mock', () => {
    render(<DataSourceBanner />);
    act(() => {
      recordMockFallback('/api/metrics');
    });
    expect(screen.getByRole('alert')).toHaveTextContent('Showing sample data: backend unreachable');
    expect(screen.getByRole('alert')).toHaveTextContent('/api/metrics');
  });

  it('clears the warning once live data is served again', () => {
    render(<DataSourceBanner />);
    act(() => {
      recordMockFallback('/api/metrics');
    });
    expect(screen.queryByRole('alert')).not.toBeNull();
    act(() => {
      // Live again
      resetDataSourceStatus();
    });
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('shows the authentication-required state on 401, not the sample-data text', () => {
    render(<DataSourceBanner />);
    act(() => {
      recordMockFallback('/api/stats');
      recordAuthRequired('/api/metrics');
    });
    const alert = screen.getByRole('alert');
    expect(alert).toHaveTextContent('Authentication required');
    expect(alert).not.toHaveTextContent('Showing sample data');
  });

  it('saves an operator token from the banner and clears the auth state', () => {
    render(<DataSourceBanner />);
    act(() => {
      recordAuthRequired('/api/metrics');
    });

    const input = screen.getByLabelText('Management API token');
    fireEvent.change(input, { target: { value: '  operator-token  ' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save token' }));

    expect(getMgmtApiToken()).toBe('operator-token');
    expect(getDataSourceStatus().mode).toBe('live');
    expect(screen.queryByRole('alert')).toBeNull();
  });
});
