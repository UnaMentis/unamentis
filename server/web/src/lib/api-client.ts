// API Client with mock data fallback for standalone operation
import type {
  LogsResponse,
  MetricsResponse,
  ClientsResponse,
  ServersResponse,
  ModelsResponse,
  DashboardStats,
  LogEntry,
  MetricsSnapshot,
} from '@/types';
import {
  mockLogs,
  mockMetrics,
  mockClients,
  mockServers,
  mockModels,
  getMockStats,
  generateMockLog,
} from './mock-data';

// Configuration
const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL || '';
const USE_MOCK = process.env.NEXT_PUBLIC_USE_MOCK === 'true' || !BACKEND_URL;

// In-memory state for demo mode (simulates backend state)
let demoLogs: LogEntry[] = [...mockLogs];
let demoMetrics: MetricsSnapshot[] = [...mockMetrics];
let lastLogTime = Date.now();

// Add periodic log generation for demo
if (typeof window !== 'undefined' && USE_MOCK) {
  setInterval(() => {
    if (Date.now() - lastLogTime > 5000) {
      demoLogs = [generateMockLog(), ...demoLogs].slice(0, 500);
      lastLogTime = Date.now();
    }
  }, 5000);
}

async function fetchWithFallback<T>(
  endpoint: string,
  mockFn: () => T,
  options?: RequestInit
): Promise<T> {
  // If explicitly using mock or no backend configured
  if (USE_MOCK) {
    // Simulate network delay
    await new Promise(resolve => setTimeout(resolve, 100 + Math.random() * 200));
    return mockFn();
  }

  try {
    const response = await fetch(`${BACKEND_URL}${endpoint}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...options?.headers,
      },
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    return await response.json();
  } catch (error) {
    console.warn(`Backend unavailable, using mock data for ${endpoint}:`, error);
    return mockFn();
  }
}

// API Functions
export async function getStats(): Promise<DashboardStats> {
  return fetchWithFallback('/api/stats', getMockStats);
}

export async function getLogs(params?: {
  limit?: number;
  offset?: number;
  level?: string;
  search?: string;
  client_id?: string;
}): Promise<LogsResponse> {
  const queryParams = new URLSearchParams();
  if (params?.limit) queryParams.set('limit', String(params.limit));
  if (params?.offset) queryParams.set('offset', String(params.offset));
  if (params?.level) queryParams.set('level', params.level);
  if (params?.search) queryParams.set('search', params.search);
  if (params?.client_id) queryParams.set('client_id', params.client_id);

  const query = queryParams.toString();
  const endpoint = `/api/logs${query ? `?${query}` : ''}`;

  return fetchWithFallback(endpoint, () => {
    let filtered = [...demoLogs];

    if (params?.level) {
      const levels = params.level.split(',');
      filtered = filtered.filter(l => levels.includes(l.level));
    }

    if (params?.search) {
      const search = params.search.toLowerCase();
      filtered = filtered.filter(
        l => l.message.toLowerCase().includes(search) || l.label.toLowerCase().includes(search)
      );
    }

    if (params?.client_id) {
      filtered = filtered.filter(l => l.client_id === params.client_id);
    }

    // Sort by received_at descending
    filtered.sort((a, b) => b.received_at - a.received_at);

    const offset = params?.offset || 0;
    const limit = params?.limit || 500;
    const paginated = filtered.slice(offset, offset + limit);

    return {
      logs: paginated,
      total: filtered.length,
      limit,
      offset,
    };
  });
}

export async function getMetrics(params?: {
  limit?: number;
  client_id?: string;
}): Promise<MetricsResponse> {
  const queryParams = new URLSearchParams();
  if (params?.limit) queryParams.set('limit', String(params.limit));
  if (params?.client_id) queryParams.set('client_id', params.client_id);

  const query = queryParams.toString();
  const endpoint = `/api/metrics${query ? `?${query}` : ''}`;

  return fetchWithFallback(endpoint, () => {
    let filtered = [...demoMetrics];

    if (params?.client_id) {
      filtered = filtered.filter(m => m.client_id === params.client_id);
    }

    // Sort by received_at descending
    filtered.sort((a, b) => b.received_at - a.received_at);

    const limit = params?.limit || 100;
    filtered = filtered.slice(0, limit);

    // Calculate aggregates
    const avg = (arr: number[]) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0);

    return {
      metrics: filtered,
      aggregates: {
        avg_e2e_latency: Math.round(avg(filtered.map(m => m.e2e_latency_median)) * 100) / 100,
        avg_llm_ttft: Math.round(avg(filtered.map(m => m.llm_ttft_median)) * 100) / 100,
        avg_stt_latency: Math.round(avg(filtered.map(m => m.stt_latency_median)) * 100) / 100,
        avg_tts_ttfb: Math.round(avg(filtered.map(m => m.tts_ttfb_median)) * 100) / 100,
        total_cost: Math.round(filtered.reduce((sum, m) => sum + m.total_cost, 0) * 10000) / 10000,
        total_sessions: filtered.length,
        total_turns: filtered.reduce((sum, m) => sum + m.turns_total, 0),
      },
    };
  });
}

export async function getClients(): Promise<ClientsResponse> {
  return fetchWithFallback('/api/clients', () => {
    const clients = [...mockClients];

    return {
      clients,
      total: clients.length,
      online: clients.filter(c => c.status === 'online').length,
      idle: clients.filter(c => c.status === 'idle').length,
      offline: clients.filter(c => c.status === 'offline').length,
    };
  });
}

export async function getServers(): Promise<ServersResponse> {
  return fetchWithFallback('/api/servers', () => {
    const servers = [...mockServers];

    return {
      servers,
      total: servers.length,
      healthy: servers.filter(s => s.status === 'healthy').length,
      degraded: servers.filter(s => s.status === 'degraded').length,
      unhealthy: servers.filter(s => s.status === 'unhealthy').length,
    };
  });
}

export async function getModels(): Promise<ModelsResponse> {
  return fetchWithFallback('/api/models', () => {
    const models = [...mockModels];

    return {
      models,
      total: models.length,
      by_type: {
        llm: models.filter(m => m.type === 'llm').length,
        stt: models.filter(m => m.type === 'stt').length,
        tts: models.filter(m => m.type === 'tts').length,
      },
    };
  });
}

// Clear logs (demo mode only affects in-memory state)
export async function clearLogs(): Promise<void> {
  if (USE_MOCK) {
    demoLogs = [];
    return;
  }

  await fetch(`${BACKEND_URL}/api/logs`, { method: 'DELETE' });
}

// Add log (for testing)
export async function addLog(log: Omit<LogEntry, 'id' | 'received_at'>): Promise<void> {
  if (USE_MOCK) {
    const newLog: LogEntry = {
      ...log,
      id: Math.random().toString(36).substring(2, 15),
      received_at: Date.now(),
    };
    demoLogs = [newLog, ...demoLogs].slice(0, 500);
    return;
  }

  await fetch(`${BACKEND_URL}/api/logs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(log),
  });
}

// Check if using mock mode
export function isUsingMockData(): boolean {
  return USE_MOCK;
}

// Get backend URL
export function getBackendUrl(): string {
  return BACKEND_URL || '(not configured)';
}
