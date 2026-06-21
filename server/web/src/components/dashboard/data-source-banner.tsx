'use client';

import { useState, useSyncExternalStore } from 'react';
import { AlertTriangle, KeyRound } from 'lucide-react';
import {
  getDataSourceStatus,
  getServerDataSourceStatus,
  subscribeDataSourceStatus,
  setMgmtApiToken,
} from '@/lib/data-source-status';
import { isUsingMockData } from '@/lib/api-client';

/**
 * Visible warning banner for data provenance (T5/ND1).
 *
 * Rendered in the main dashboard layout. Shows an amber banner when any
 * recent request fell back to mock data, and a distinct 'authentication
 * required' state (with a token entry affordance) when the management API
 * rejected requests with 401/403. Hidden in explicit demo mode, where the
 * header badge already labels the data as sample data.
 */
export function DataSourceBanner() {
  const status = useSyncExternalStore(
    subscribeDataSourceStatus,
    getDataSourceStatus,
    getServerDataSourceStatus
  );
  const [tokenInput, setTokenInput] = useState('');

  // Explicit demo mode: the header badge already says 'Demo Mode'.
  if (isUsingMockData() || status.mode === 'live') {
    return null;
  }

  const saveToken = () => {
    setMgmtApiToken(tokenInput.trim());
    setTokenInput('');
  };

  if (status.mode === 'auth-required') {
    return (
      <div
        role="alert"
        className="flex flex-wrap items-center gap-x-3 gap-y-2 px-3 sm:px-6 py-2 bg-red-500/10 border-b border-red-500/30 text-sm text-red-300"
      >
        <KeyRound className="w-4 h-4 flex-shrink-0 text-red-400" aria-hidden="true" />
        <span>
          Authentication required: the management API rejected console requests. Live data is paused
          until a valid operator token is provided.
        </span>
        <form
          className="flex items-center gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            saveToken();
          }}
        >
          <input
            type="password"
            value={tokenInput}
            onChange={(e) => setTokenInput(e.target.value)}
            placeholder="Operator API token"
            aria-label="Management API token"
            className="px-2 py-1 rounded border border-red-500/30 bg-slate-900/70 text-slate-100 text-xs placeholder:text-slate-500 focus:outline-none focus:border-red-400 w-48"
          />
          <button
            type="submit"
            className="px-2 py-1 rounded border border-red-500/30 text-xs text-red-200 hover:bg-red-500/20 transition-colors"
          >
            Save token
          </button>
        </form>
      </div>
    );
  }

  // mock-fallback: at least one recent request was served sample data.
  return (
    <div
      role="alert"
      className="flex items-center gap-3 px-3 sm:px-6 py-2 bg-amber-500/10 border-b border-amber-500/30 text-sm text-amber-300"
    >
      <AlertTriangle className="w-4 h-4 flex-shrink-0 text-amber-400" aria-hidden="true" />
      <span>
        Showing sample data: backend unreachable. Values below are not live telemetry
        {status.degradedEndpoints.length > 0 && (
          <span className="text-amber-400/80">
            {' '}
            (affected: {status.degradedEndpoints.join(', ')})
          </span>
        )}
        .
      </span>
    </div>
  );
}
