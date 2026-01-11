'use client';

import { useEffect } from 'react';
import { WebSocketProvider } from '@/lib/websocket-provider';
import { initializeTestHooks } from '@/lib/test-hooks';

interface ProvidersProps {
  children: React.ReactNode;
}

export function Providers({ children }: ProvidersProps) {
  // Initialize test hooks for automated testing via Playwright
  useEffect(() => {
    // Use management server URL (defaults to localhost:8766)
    const serverUrl = process.env.NEXT_PUBLIC_MANAGEMENT_SERVER_URL || 'http://localhost:8766';
    initializeTestHooks(serverUrl);
  }, []);

  return <WebSocketProvider>{children}</WebSocketProvider>;
}
