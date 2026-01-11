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
  SystemMetricsSummary,
  IdleStatus,
  PowerModesResponse,
  IdleTransition,
  HourlyMetrics,
  DailyMetrics,
  MetricsHistorySummary,
  ModelLoadRequest,
  ModelLoadResponse,
  ModelUnloadResponse,
  ModelPullProgress,
  ModelDeleteResponse,
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
const demoMetrics: MetricsSnapshot[] = [...mockMetrics];
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
    await new Promise((resolve) => setTimeout(resolve, 100 + Math.random() * 200));
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
      filtered = filtered.filter((l) => levels.includes(l.level));
    }

    if (params?.search) {
      const search = params.search.toLowerCase();
      filtered = filtered.filter(
        (l) => l.message.toLowerCase().includes(search) || l.label.toLowerCase().includes(search)
      );
    }

    if (params?.client_id) {
      filtered = filtered.filter((l) => l.client_id === params.client_id);
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
      filtered = filtered.filter((m) => m.client_id === params.client_id);
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
        avg_e2e_latency: Math.round(avg(filtered.map((m) => m.e2e_latency_median)) * 100) / 100,
        avg_llm_ttft: Math.round(avg(filtered.map((m) => m.llm_ttft_median)) * 100) / 100,
        avg_stt_latency: Math.round(avg(filtered.map((m) => m.stt_latency_median)) * 100) / 100,
        avg_tts_ttfb: Math.round(avg(filtered.map((m) => m.tts_ttfb_median)) * 100) / 100,
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
      online: clients.filter((c) => c.status === 'online').length,
      idle: clients.filter((c) => c.status === 'idle').length,
      offline: clients.filter((c) => c.status === 'offline').length,
    };
  });
}

export async function getServers(): Promise<ServersResponse> {
  return fetchWithFallback('/api/servers', () => {
    const servers = [...mockServers];

    return {
      servers,
      total: servers.length,
      healthy: servers.filter((s) => s.status === 'healthy').length,
      degraded: servers.filter((s) => s.status === 'degraded').length,
      unhealthy: servers.filter((s) => s.status === 'unhealthy').length,
    };
  });
}

export interface AddServerRequest {
  name: string;
  type: 'ollama' | 'whisper' | 'piper' | 'vibevoice' | 'custom';
  url: string;
  port: number;
}

export async function addServer(
  server: AddServerRequest
): Promise<{ status: string; server: ServersResponse['servers'][0] }> {
  if (USE_MOCK) {
    return {
      status: 'ok',
      server: {
        id: `mock-${Date.now()}`,
        name: server.name,
        type: server.type,
        url: `${server.url}:${server.port}`,
        port: server.port,
        status: 'healthy',
        last_check: Date.now(),
        response_time_ms: 50,
        models: [],
      },
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/servers`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(server),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function getModels(): Promise<ModelsResponse> {
  return fetchWithFallback('/api/models', () => {
    const models = [...mockModels];

    return {
      models,
      total: models.length,
      by_type: {
        llm: models.filter((m) => m.type === 'llm').length,
        stt: models.filter((m) => m.type === 'stt').length,
        tts: models.filter((m) => m.type === 'tts').length,
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

// =============================================================================
// System Health & Resource Monitoring APIs
// =============================================================================

const mockSystemMetrics: SystemMetricsSummary = {
  timestamp: Date.now() / 1000,
  power: {
    current_battery_draw_w: 8.5,
    avg_battery_draw_w: 7.2,
    battery_percent: 78,
    battery_charging: false,
    estimated_service_power_w: 5.3,
  },
  thermal: {
    pressure: 'nominal',
    pressure_level: 0,
    cpu_temp_c: 45.2,
    gpu_temp_c: 42.1,
    fan_speed_rpm: 0,
  },
  cpu: {
    total_percent: 12.5,
    by_service: {
      ollama: 2.1,
      vibevoice: 5.3,
      management: 1.2,
      nextjs: 3.9,
    },
  },
  services: {
    ollama: {
      service_id: 'ollama',
      service_name: 'Ollama',
      status: 'running',
      cpu_percent: 2.1,
      memory_mb: 245,
      gpu_memory_mb: 0,
      last_request_time: Date.now() / 1000 - 300,
      request_count_5m: 0,
      model_loaded: false,
      estimated_power_w: 0.5,
    },
    vibevoice: {
      service_id: 'vibevoice',
      service_name: 'VibeVoice',
      status: 'running',
      cpu_percent: 5.3,
      memory_mb: 2100,
      gpu_memory_mb: 1800,
      last_request_time: Date.now() / 1000 - 120,
      request_count_5m: 3,
      model_loaded: true,
      estimated_power_w: 2.5,
    },
  },
  history_minutes: 60,
};

const mockIdleStatus: IdleStatus = {
  enabled: true,
  current_state: 'warm',
  current_mode: 'balanced',
  seconds_idle: 45,
  last_activity_type: 'request',
  last_activity_time: Date.now() / 1000 - 45,
  thresholds: {
    warm: 30,
    cool: 300,
    cold: 1800,
    dormant: 7200,
  },
  keep_awake_remaining: 0,
  next_state_in: {
    state: 'cool',
    seconds_remaining: 255,
  },
};

const mockPowerModes: PowerModesResponse = {
  modes: {
    performance: {
      name: 'Performance',
      description: 'Never idle, always ready. Maximum responsiveness, highest power.',
      thresholds: { warm: 9999999, cool: 9999999, cold: 9999999, dormant: 9999999 },
      enabled: false,
    },
    balanced: {
      name: 'Balanced',
      description: 'Default settings. Good balance of responsiveness and power saving.',
      thresholds: { warm: 30, cool: 300, cold: 1800, dormant: 7200 },
      enabled: true,
    },
    power_saver: {
      name: 'Power Saver',
      description: 'Aggressive power saving. Longer wake times but much lower power.',
      thresholds: { warm: 10, cool: 60, cold: 300, dormant: 1800 },
      enabled: true,
    },
  },
  current: 'balanced',
};

export async function getSystemMetrics(): Promise<SystemMetricsSummary> {
  return fetchWithFallback('/api/system/metrics', () => mockSystemMetrics);
}

export async function getIdleStatus(): Promise<IdleStatus> {
  return fetchWithFallback('/api/system/idle/status', () => mockIdleStatus);
}

export async function getPowerModes(): Promise<PowerModesResponse> {
  return fetchWithFallback('/api/system/idle/modes', () => mockPowerModes);
}

export async function setIdleConfig(config: {
  mode?: string;
  thresholds?: { warm?: number; cool?: number; cold?: number; dormant?: number };
  enabled?: boolean;
}): Promise<{ status: string; config: IdleStatus }> {
  if (USE_MOCK) {
    return { status: 'ok', config: mockIdleStatus };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/idle/config`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(config),
  });

  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

export async function keepAwake(durationSeconds: number): Promise<{ status: string }> {
  if (USE_MOCK) {
    return { status: 'ok' };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/idle/keep-awake`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ duration_seconds: durationSeconds }),
  });

  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

export async function cancelKeepAwake(): Promise<{ status: string }> {
  if (USE_MOCK) {
    return { status: 'ok' };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/idle/cancel-keep-awake`, {
    method: 'POST',
  });

  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

export async function forceIdleState(state: string): Promise<{ status: string }> {
  if (USE_MOCK) {
    return { status: 'ok' };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/idle/force-state`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ state }),
  });

  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

export async function unloadAllModels(): Promise<{
  status: string;
  results: Record<string, boolean>;
}> {
  if (USE_MOCK) {
    return { status: 'ok', results: { ollama: true, vibevoice: true } };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/unload-models`, {
    method: 'POST',
  });

  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

export async function loadModel(
  modelId: string,
  options?: ModelLoadRequest
): Promise<ModelLoadResponse> {
  if (USE_MOCK) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    return {
      status: 'ok',
      model: modelId,
      vram_bytes: 4 * 1024 ** 3,
      vram_gb: 4,
      load_time_ms: 1000,
      message: 'Model loaded (mock)',
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/models/${encodeURIComponent(modelId)}/load`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(options || {}),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function unloadModel(modelId: string): Promise<ModelUnloadResponse> {
  if (USE_MOCK) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    return {
      status: 'ok',
      model: modelId,
      freed_vram_bytes: 4 * 1024 ** 3,
      freed_vram_gb: 4,
      message: 'Model unloaded (mock)',
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/models/${encodeURIComponent(modelId)}/unload`, {
    method: 'POST',
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function pullModel(
  modelName: string,
  onProgress?: (progress: ModelPullProgress) => void,
  signal?: AbortSignal
): Promise<void> {
  if (USE_MOCK) {
    // Simulate pull progress
    const stages = ['pulling manifest', 'downloading', 'verifying sha256', 'success'];
    for (let i = 0; i <= 100; i += 5) {
      if (signal?.aborted) throw new Error('Pull cancelled');
      await new Promise((resolve) => setTimeout(resolve, 100));
      const stage = i < 10 ? stages[0] : i < 90 ? stages[1] : i < 98 ? stages[2] : stages[3];
      onProgress?.({
        status: stage,
        completed: i * 1024 * 1024 * 40, // Simulate ~4GB download
        total: 4 * 1024 * 1024 * 1024,
      });
    }
    return;
  }

  const response = await fetch(`${BACKEND_URL}/api/models/pull`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: modelName }),
    signal,
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    throw new Error(data.error || `HTTP ${response.status}`);
  }

  // Read SSE stream
  const reader = response.body?.getReader();
  const decoder = new TextDecoder();

  if (!reader) throw new Error('No response body');

  let buffer = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      if (line.startsWith('data: ')) {
        try {
          const data = JSON.parse(line.slice(6)) as ModelPullProgress;
          onProgress?.(data);

          if (data.status === 'error') {
            throw new Error(data.error || 'Pull failed');
          }
        } catch (e) {
          if (e instanceof SyntaxError) continue;
          throw e;
        }
      }
    }
  }
}

export async function deleteModel(modelId: string): Promise<ModelDeleteResponse> {
  if (USE_MOCK) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    return {
      status: 'ok',
      model: modelId,
      message: 'Model deleted (mock)',
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/models/${encodeURIComponent(modelId)}`, {
    method: 'DELETE',
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return response.json();
}

import type {
  ModelConfig,
  ModelConfigResponse,
  SaveModelConfigResponse,
  ModelParameters,
  ModelParametersResponse,
  SaveModelParametersResponse,
} from '@/types';

const mockModelConfig: ModelConfig = {
  services: {
    llm: { default_model: null, fallback_model: null },
    tts: { default_provider: 'vibevoice', default_voice: 'nova' },
    stt: { default_model: 'whisper' },
  },
};

export async function getModelConfig(): Promise<ModelConfigResponse> {
  if (USE_MOCK) {
    return { status: 'ok', config: mockModelConfig };
  }

  const response = await fetch(`${BACKEND_URL}/api/models/config`);
  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function saveModelConfig(config: ModelConfig): Promise<SaveModelConfigResponse> {
  if (USE_MOCK) {
    return { status: 'ok', config, message: 'Configuration saved (mock)' };
  }

  const response = await fetch(`${BACKEND_URL}/api/models/config`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ config }),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return response.json();
}

const mockModelParameters: ModelParameters = {
  num_ctx: { value: 4096, min: 256, max: 131072, description: 'Context window size' },
  temperature: { value: 0.8, min: 0.0, max: 2.0, step: 0.1, description: 'Sampling temperature' },
  top_p: { value: 0.9, min: 0.0, max: 1.0, step: 0.05, description: 'Top-p (nucleus) sampling' },
  top_k: { value: 40, min: 1, max: 100, description: 'Top-k sampling' },
  repeat_penalty: { value: 1.1, min: 0.0, max: 2.0, step: 0.1, description: 'Repeat penalty' },
  seed: { value: -1, min: -1, max: 2147483647, description: 'Random seed (-1 for random)' },
};

export async function getModelParameters(modelId: string): Promise<ModelParametersResponse> {
  if (USE_MOCK) {
    return { status: 'ok', model: modelId, parameters: mockModelParameters };
  }

  const response = await fetch(
    `${BACKEND_URL}/api/models/${encodeURIComponent(modelId)}/parameters`
  );
  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function saveModelParameters(
  modelId: string,
  parameters: Record<string, number>
): Promise<SaveModelParametersResponse> {
  if (USE_MOCK) {
    return { status: 'ok', model: modelId, parameters, message: 'Parameters saved (mock)' };
  }

  const response = await fetch(
    `${BACKEND_URL}/api/models/${encodeURIComponent(modelId)}/parameters`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ parameters }),
    }
  );

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function getIdleHistory(
  limit: number = 50
): Promise<{ history: IdleTransition[]; count: number }> {
  return fetchWithFallback(`/api/system/idle/history?limit=${limit}`, () => ({
    history: [],
    count: 0,
  }));
}

export async function getHourlyHistory(
  days: number = 7
): Promise<{ history: HourlyMetrics[]; count: number }> {
  return fetchWithFallback(`/api/system/history/hourly?days=${days}`, () => ({
    history: [],
    count: 0,
  }));
}

export async function getDailyHistory(
  days: number = 30
): Promise<{ history: DailyMetrics[]; count: number }> {
  return fetchWithFallback(`/api/system/history/daily?days=${days}`, () => ({
    history: [],
    count: 0,
  }));
}

export async function getMetricsHistorySummary(): Promise<MetricsHistorySummary> {
  return fetchWithFallback('/api/system/history/summary', () => ({
    today: null,
    yesterday: null,
    this_week: null,
    total_days_tracked: 0,
    total_hours_tracked: 0,
    oldest_record: null,
  }));
}

// =============================================================================
// Profile Management APIs
// =============================================================================

import type {
  CreateProfileRequest,
  UpdateProfileRequest,
  ProfileResponse,
  PowerModeWithId,
} from '@/types';

export async function getProfile(profileId: string): Promise<PowerModeWithId> {
  if (USE_MOCK) {
    const modes = mockPowerModes.modes;
    const mode = modes[profileId as keyof typeof modes];
    if (!mode) throw new Error('Profile not found');
    return { ...mode, id: profileId, is_builtin: true, is_custom: false };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/profiles/${profileId}`);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

export async function createProfile(profile: CreateProfileRequest): Promise<ProfileResponse> {
  if (USE_MOCK) {
    return {
      status: 'created',
      profile: {
        id: profile.id,
        name: profile.name,
        description: profile.description || '',
        thresholds: profile.thresholds,
        enabled: profile.enabled ?? true,
        is_builtin: false,
        is_custom: true,
      },
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/profiles`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(profile),
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }));
    throw new Error(error.error || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function updateProfile(
  profileId: string,
  updates: UpdateProfileRequest
): Promise<ProfileResponse> {
  if (USE_MOCK) {
    return {
      status: 'updated',
      profile: {
        id: profileId,
        name: updates.name || 'Updated Profile',
        description: updates.description || '',
        thresholds: {
          warm: updates.thresholds?.warm || 30,
          cool: updates.thresholds?.cool || 300,
          cold: updates.thresholds?.cold || 1800,
          dormant: updates.thresholds?.dormant || 7200,
        },
        enabled: updates.enabled ?? true,
        is_builtin: false,
        is_custom: true,
      },
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/profiles/${profileId}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(updates),
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }));
    throw new Error(error.error || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function deleteProfile(
  profileId: string
): Promise<{ status: string; profile_id: string }> {
  if (USE_MOCK) {
    return { status: 'deleted', profile_id: profileId };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/profiles/${profileId}`, {
    method: 'DELETE',
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }));
    throw new Error(error.error || `HTTP ${response.status}`);
  }
  return response.json();
}

export async function duplicateProfile(
  sourceId: string,
  newId: string,
  newName: string
): Promise<ProfileResponse> {
  if (USE_MOCK) {
    const modes = mockPowerModes.modes;
    const source = modes[sourceId as keyof typeof modes];
    return {
      status: 'duplicated',
      profile: {
        id: newId,
        name: newName,
        description: source ? `Based on ${source.name}` : '',
        thresholds: source?.thresholds || { warm: 30, cool: 300, cold: 1800, dormant: 7200 },
        enabled: true,
        is_builtin: false,
        is_custom: true,
      },
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/system/profiles/${sourceId}/duplicate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ new_id: newId, new_name: newName }),
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }));
    throw new Error(error.error || `HTTP ${response.status}`);
  }
  return response.json();
}

// =============================================================================
// Curriculum Import System (Source Browser)
// =============================================================================

import type {
  SourcesResponse,
  CourseCatalogResponse,
  CourseDetailResponse,
  StartImportResponse,
  ImportProgressResponse,
  ImportJobsResponse,
  ImportConfig,
  CurriculumSource,
  CourseCatalogEntry,
} from '@/types';

// Mock data for import sources
const mockSources: CurriculumSource[] = [
  {
    id: 'mit_ocw',
    name: 'MIT OpenCourseWare',
    description: 'Free lecture notes, exams, and videos from MIT. No registration required.',
    provider: 'Massachusetts Institute of Technology',
    website: 'https://ocw.mit.edu',
    license: {
      type: 'CC-BY-NC-SA-4.0',
      name: 'Creative Commons Attribution-NonCommercial-ShareAlike 4.0',
      url: 'https://creativecommons.org/licenses/by-nc-sa/4.0/',
      requiresAttribution: true,
      allowsCommercialUse: false,
      allowsDerivatives: true,
      shareAlike: true,
    },
    contentTypes: ['lectures', 'transcripts', 'notes', 'assignments', 'exams'],
    subjects: ['Computer Science', 'Mathematics', 'Physics', 'Engineering'],
    courseCount: 2500,
    isActive: true,
  },
];

const mockCourses: CourseCatalogEntry[] = [
  {
    id: '6-001-spring-2005',
    title: 'Structure and Interpretation of Computer Programs',
    description: 'Introduction to programming using Scheme, from the legendary MIT course.',
    instructor: 'Hal Abelson, Gerald Jay Sussman',
    institution: 'MIT',
    subject: 'Computer Science',
    level: 'Undergraduate',
    language: 'English',
    url: 'https://ocw.mit.edu/courses/6-001-structure-and-interpretation-of-computer-programs-spring-2005/',
    license: mockSources[0].license,
    contentTypes: ['lectures', 'transcripts', 'notes', 'assignments'],
    estimatedDuration: '40 hours',
  },
  {
    id: '6-006-fall-2011',
    title: 'Introduction to Algorithms',
    description: 'Techniques for the design and analysis of efficient algorithms.',
    instructor: 'Erik Demaine, Srini Devadas',
    institution: 'MIT',
    subject: 'Computer Science',
    level: 'Undergraduate',
    language: 'English',
    url: 'https://ocw.mit.edu/courses/6-006-introduction-to-algorithms-fall-2011/',
    license: mockSources[0].license,
    contentTypes: ['lectures', 'transcripts', 'notes', 'assignments', 'exams'],
    estimatedDuration: '50 hours',
  },
];

/**
 * Get all registered curriculum sources
 */
export async function getImportSources(): Promise<SourcesResponse> {
  return fetchWithFallback('/api/import/sources', () => ({
    success: true,
    sources: mockSources,
  }));
}

/**
 * Get course catalog for a source
 */
export async function getCourseCatalog(
  sourceId: string,
  params?: {
    page?: number;
    pageSize?: number;
    search?: string;
    subject?: string;
    level?: string;
    features?: string[];
  }
): Promise<CourseCatalogResponse> {
  const queryParams = new URLSearchParams();
  if (params?.page) queryParams.set('page', String(params.page));
  if (params?.pageSize) queryParams.set('pageSize', String(params.pageSize));
  if (params?.search) queryParams.set('search', params.search);
  if (params?.subject) queryParams.set('subject', params.subject);
  if (params?.level) queryParams.set('level', params.level);
  if (params?.features) queryParams.set('features', params.features.join(','));

  const query = queryParams.toString();
  const endpoint = `/api/import/sources/${sourceId}/courses${query ? `?${query}` : ''}`;

  return fetchWithFallback(endpoint, () => {
    let filtered = [...mockCourses];

    if (params?.search) {
      const search = params.search.toLowerCase();
      filtered = filtered.filter(
        (c) =>
          c.title.toLowerCase().includes(search) || c.description.toLowerCase().includes(search)
      );
    }

    if (params?.subject) {
      filtered = filtered.filter((c) => c.subject === params.subject);
    }

    if (params?.level) {
      filtered = filtered.filter((c) => c.level === params.level);
    }

    const page = params?.page || 1;
    const pageSize = params?.pageSize || 20;
    const total = filtered.length;
    const start = (page - 1) * pageSize;
    const paginated = filtered.slice(start, start + pageSize);

    return {
      success: true,
      courses: paginated,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.ceil(total / pageSize),
      },
      filters: {
        subjects: ['Computer Science', 'Mathematics', 'Physics', 'Engineering'],
        levels: ['Undergraduate', 'Graduate'],
        features: ['transcripts', 'notes', 'assignments', 'exams', 'videos'],
      },
    };
  });
}

/**
 * Get detailed information for a specific course
 */
export async function getCourseDetail(
  sourceId: string,
  courseId: string
): Promise<CourseDetailResponse> {
  return fetchWithFallback(`/api/import/sources/${sourceId}/courses/${courseId}`, () => {
    const course = mockCourses.find((c) => c.id === courseId);
    if (!course) {
      return {
        success: false,
        course: null as unknown as CourseDetailResponse['course'],
        canImport: false,
        licenseWarnings: [],
        error: `Course not found: ${courseId}`,
      };
    }

    return {
      success: true,
      course: {
        ...course,
        longDescription: `${course.description}\n\nThis is a comprehensive course covering key topics in ${course.subject}.`,
        prerequisites: ['Basic programming knowledge'],
        learningOutcomes: [
          'Understand fundamental concepts',
          'Apply learned techniques to solve problems',
        ],
        topics: ['Introduction', 'Core Concepts', 'Advanced Topics'],
        contentSummary: {
          lectureCount: 24,
          hasTranscripts: true,
          hasLectureNotes: true,
          hasAssignments: true,
          hasExams: course.contentTypes.includes('exams'),
          hasVideos: false,
          hasSolutions: true,
        },
      },
      canImport: true,
      licenseWarnings: [],
      attribution: `This content is from ${course.institution}, licensed under ${course.license.name}.`,
    };
  });
}

/**
 * Start a new import job
 */
export async function startImport(config: ImportConfig): Promise<StartImportResponse> {
  if (USE_MOCK) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    return {
      success: true,
      jobId: `job-${Date.now()}`,
      status: 'queued',
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/import/jobs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(config),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: 'Unknown error' }));
    return {
      success: false,
      jobId: '',
      status: 'failed',
      error: data.error || `HTTP ${response.status}`,
      licenseRestriction: data.licenseRestriction,
    };
  }

  return response.json();
}

/**
 * Get progress for an import job
 */
export async function getImportProgress(jobId: string): Promise<ImportProgressResponse> {
  return fetchWithFallback(`/api/import/jobs/${jobId}`, () => ({
    success: false,
    progress: null as unknown as ImportProgressResponse['progress'],
    error: 'Mock mode - job not found',
  }));
}

/**
 * List all import jobs
 */
export async function getImportJobs(status?: string): Promise<ImportJobsResponse> {
  const endpoint = status ? `/api/import/jobs?status=${status}` : '/api/import/jobs';

  return fetchWithFallback(endpoint, () => ({
    success: true,
    jobs: [],
  }));
}

/**
 * Cancel an import job
 */
export async function cancelImport(jobId: string): Promise<{ success: boolean; error?: string }> {
  if (USE_MOCK) {
    return { success: true };
  }

  const response = await fetch(`${BACKEND_URL}/api/import/jobs/${jobId}`, {
    method: 'DELETE',
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: 'Unknown error' }));
    return { success: false, error: data.error || `HTTP ${response.status}` };
  }

  return response.json();
}

// =============================================================================
// Curriculum & Visual Asset Management
// =============================================================================
// NOTE: Curriculum data is served by the Management API (port 8766) and proxied through
// the UnaMentis Server's Next.js API routes. The Curriculum Studio provides a unified
// interface for viewing and editing curriculum content alongside system management.

// =============================================================================
// Generative Media APIs (Diagrams, Formulas, Maps)
// =============================================================================

import type {
  DiagramValidateRequest,
  DiagramValidateResponse,
  DiagramRenderRequest,
  DiagramRenderResponse,
  FormulaValidateRequest,
  FormulaValidateResponse,
  FormulaRenderRequest,
  FormulaRenderResponse,
  MapRenderRequest,
  MapRenderResponse,
  MapStylesResponse,
  MediaCapabilitiesResponse,
} from '@/types';

/**
 * Get media generation capabilities
 */
export async function getMediaCapabilities(): Promise<MediaCapabilitiesResponse> {
  return fetchWithFallback('/api/media/capabilities', () => ({
    success: true,
    capabilities: {
      diagrams: {
        formats: ['mermaid', 'graphviz', 'plantuml', 'd2', 'svg-raw'],
        renderers: {
          mermaid: false,
          graphviz: false,
          plantuml: false,
          d2: false,
        },
      },
      formulas: {
        renderers: {
          katex: false,
          latex: false,
        },
        clientSideSupported: true,
      },
      maps: {
        styles: ['standard', 'historical', 'physical', 'satellite', 'minimal', 'educational'],
        renderers: {
          cartopy: false,
          folium: false,
          staticTiles: true,
        },
        features: ['markers', 'routes', 'regions'],
      },
    },
  }));
}

/**
 * Validate diagram syntax
 */
export async function validateDiagram(
  request: DiagramValidateRequest
): Promise<DiagramValidateResponse> {
  if (USE_MOCK) {
    return {
      success: true,
      valid: request.code.trim().length > 0,
      errors: request.code.trim().length === 0 ? ['Empty diagram source'] : [],
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/media/diagrams/validate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: 'Validation failed' }));
    return { success: false, valid: false, errors: [data.error || 'Validation failed'] };
  }

  return response.json();
}

/**
 * Render a diagram to image
 */
export async function renderDiagram(request: DiagramRenderRequest): Promise<DiagramRenderResponse> {
  if (USE_MOCK) {
    // Return a placeholder SVG in mock mode
    const placeholderSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200">
      <rect fill="#f5f5f5" width="100%" height="100%" rx="8"/>
      <text x="50%" y="50%" text-anchor="middle" dy=".3em" font-family="system-ui" font-size="14" fill="#666">
        Diagram Preview (${request.format})
      </text>
    </svg>`;
    return {
      success: true,
      data: btoa(placeholderSvg),
      mimeType: 'image/svg+xml',
      width: 400,
      height: 200,
      renderMethod: 'placeholder',
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/media/diagrams/render`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: 'Rendering failed' }));
    return {
      success: false,
      error: data.error || 'Rendering failed',
      validationErrors: data.validationErrors,
    };
  }

  return response.json();
}

/**
 * Validate LaTeX formula syntax
 */
export async function validateFormula(
  request: FormulaValidateRequest
): Promise<FormulaValidateResponse> {
  if (USE_MOCK) {
    const hasUnbalancedBraces =
      (request.latex.match(/{/g) || []).length !== (request.latex.match(/}/g) || []).length;
    return {
      success: true,
      valid: !hasUnbalancedBraces && request.latex.trim().length > 0,
      errors: hasUnbalancedBraces ? ['Unbalanced braces'] : [],
      warnings: [],
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/media/formulas/validate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: 'Validation failed' }));
    return {
      success: false,
      valid: false,
      errors: [data.error || 'Validation failed'],
      warnings: [],
    };
  }

  return response.json();
}

/**
 * Render a LaTeX formula to image
 */
export async function renderFormula(request: FormulaRenderRequest): Promise<FormulaRenderResponse> {
  if (USE_MOCK) {
    // Return a placeholder SVG in mock mode
    const displayLatex = request.latex.replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const placeholderSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="300" height="60">
      <rect fill="#fafafa" width="100%" height="100%" rx="4"/>
      <text x="50%" y="50%" text-anchor="middle" dy=".3em" font-family="serif" font-style="italic" font-size="16" fill="#333">
        ${displayLatex.substring(0, 30)}${displayLatex.length > 30 ? '...' : ''}
      </text>
    </svg>`;
    return {
      success: true,
      data: btoa(placeholderSvg),
      mimeType: 'image/svg+xml',
      width: 300,
      height: 60,
      renderMethod: 'placeholder',
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/media/formulas/render`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: 'Rendering failed' }));
    return {
      success: false,
      error: data.error || 'Rendering failed',
      validationErrors: data.validationErrors,
    };
  }

  return response.json();
}

/**
 * Render a map to image
 */
export async function renderMap(request: MapRenderRequest): Promise<MapRenderResponse> {
  if (USE_MOCK) {
    // Return a placeholder SVG in mock mode
    const placeholderSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${request.width || 800}" height="${request.height || 600}">
      <rect fill="#e8f4e8" width="100%" height="100%"/>
      <text x="50%" y="45%" text-anchor="middle" font-family="system-ui" font-size="18" fill="#2d5a2d">
        ${request.title || 'Map Preview'}
      </text>
      <text x="50%" y="55%" text-anchor="middle" font-family="system-ui" font-size="12" fill="#666">
        ${request.center.latitude.toFixed(2)}°, ${request.center.longitude.toFixed(2)}° (zoom: ${request.zoom || 5})
      </text>
    </svg>`;
    return {
      success: true,
      data: btoa(placeholderSvg),
      mimeType: 'image/svg+xml',
      width: request.width || 800,
      height: request.height || 600,
      renderMethod: 'placeholder',
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/media/maps/render`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });

  if (!response.ok) {
    const data = await response.json().catch(() => ({ error: 'Rendering failed' }));
    return {
      success: false,
      error: data.error || 'Rendering failed',
    };
  }

  return response.json();
}

/**
 * Get available map styles
 */
export async function getMapStyles(): Promise<MapStylesResponse> {
  return fetchWithFallback('/api/media/maps/styles', () => ({
    success: true,
    styles: [
      { id: 'standard', name: 'Standard', description: 'Modern political map' },
      { id: 'historical', name: 'Historical', description: 'Aged parchment style' },
      { id: 'physical', name: 'Physical', description: 'Terrain and elevation focus' },
      { id: 'satellite', name: 'Satellite', description: 'Aerial imagery' },
      { id: 'minimal', name: 'Minimal', description: 'Clean, minimal styling' },
      { id: 'educational', name: 'Educational', description: 'Clear labels for learning' },
    ],
  }));
}

// =============================================================================
// FOV Context Management APIs
// =============================================================================

import type {
  FOVSessionsResponse,
  FOVSessionDebug,
  FOVHealthStatus,
  FOVConfidenceAnalysis,
  FOVContextBuildResponse,
} from '@/types';

/**
 * Get FOV system health status
 */
export async function getFOVHealth(): Promise<FOVHealthStatus> {
  return fetchWithFallback('/api/fov/health', () => ({
    status: 'unavailable' as const,
    sessions: { total: 0, active: 0, paused: 0 },
    error: 'Backend not available',
  }));
}

/**
 * List all FOV sessions
 */
export async function getFOVSessions(): Promise<FOVSessionsResponse> {
  return fetchWithFallback('/api/sessions', () => ({
    sessions: [],
    error: 'Backend not available',
  }));
}

/**
 * Create a new FOV session
 */
export async function createFOVSession(params: {
  curriculum_id: string;
  model_name?: string;
  model_context_window?: number;
  system_prompt?: string;
}): Promise<{ session_id: string; state: string; error?: string }> {
  if (USE_MOCK) {
    return {
      session_id: `mock-session-${Date.now()}`,
      state: 'created',
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/sessions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });

  return response.json();
}

/**
 * Get FOV session details
 */
export async function getFOVSession(
  sessionId: string
): Promise<FOVSessionDebug & { error?: string }> {
  return fetchWithFallback(`/api/sessions/${sessionId}`, () => ({
    error: 'Session not found',
    session_id: '',
    state: 'ended' as const,
    curriculum_id: '',
    turn_count: 0,
    barge_in_count: 0,
    model_tier: 'CLOUD' as const,
    buffers: {
      immediate: { current_segment: null, barge_in: null, turn_count: 0, max_turns: 10 },
      working: { topic_id: null, topic_title: null, glossary_count: 0, misconception_count: 0 },
      episodic: {
        topic_summary_count: 0,
        questions_count: 0,
        learner_signals: { clarifications: 0, repetitions: 0, confusions: 0 },
      },
      semantic: {
        curriculum_id: null,
        current_topic_index: 0,
        total_topics: 0,
        has_outline: false,
      },
    },
    token_usage: {
      immediate: { budget: 0, estimated_used: 0, percentage: 0 },
      working: { budget: 0, estimated_used: 0, percentage: 0 },
      episodic: { budget: 0, estimated_used: 0, percentage: 0 },
      semantic: { budget: 0, estimated_used: 0, percentage: 0 },
    },
    total_context_tokens: 0,
    confidence_history: [],
    barge_in_history: [],
    budget_config: {
      tier: 'CLOUD' as const,
      immediate_budget: 0,
      working_budget: 0,
      episodic_budget: 0,
      semantic_budget: 0,
      total_budget: 0,
      max_conversation_turns: 0,
    },
  }));
}

/**
 * Get detailed debug info for a session
 */
export async function getFOVSessionDebug(sessionId: string): Promise<FOVSessionDebug> {
  return fetchWithFallback(`/api/sessions/${sessionId}/debug`, () => ({
    session_id: '',
    state: 'ended' as const,
    curriculum_id: '',
    turn_count: 0,
    barge_in_count: 0,
    model_tier: 'CLOUD' as const,
    buffers: {
      immediate: { current_segment: null, barge_in: null, turn_count: 0, max_turns: 10 },
      working: { topic_id: null, topic_title: null, glossary_count: 0, misconception_count: 0 },
      episodic: {
        topic_summary_count: 0,
        questions_count: 0,
        learner_signals: { clarifications: 0, repetitions: 0, confusions: 0 },
      },
      semantic: {
        curriculum_id: null,
        current_topic_index: 0,
        total_topics: 0,
        has_outline: false,
      },
    },
    token_usage: {
      immediate: { budget: 0, estimated_used: 0, percentage: 0 },
      working: { budget: 0, estimated_used: 0, percentage: 0 },
      episodic: { budget: 0, estimated_used: 0, percentage: 0 },
      semantic: { budget: 0, estimated_used: 0, percentage: 0 },
    },
    total_context_tokens: 0,
    confidence_history: [],
    barge_in_history: [],
    budget_config: {
      tier: 'CLOUD' as const,
      immediate_budget: 0,
      working_budget: 0,
      episodic_budget: 0,
      semantic_budget: 0,
      total_budget: 0,
      max_conversation_turns: 0,
    },
  }));
}

/**
 * Start an FOV session
 */
export async function startFOVSession(
  sessionId: string
): Promise<{ state: string; error?: string }> {
  if (USE_MOCK) {
    return { state: 'active' };
  }

  const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/start`, {
    method: 'POST',
  });

  return response.json();
}

/**
 * Add a conversation turn
 */
export async function addFOVTurn(
  sessionId: string,
  role: 'user' | 'assistant',
  content: string
): Promise<{ turn_id: string; error?: string }> {
  if (USE_MOCK) {
    return { turn_id: `mock-turn-${Date.now()}` };
  }

  const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/turns`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ role, content }),
  });

  return response.json();
}

/**
 * Handle a barge-in event
 */
export async function handleFOVBargeIn(
  sessionId: string,
  utterance: string
): Promise<{
  context: FOVContextBuildResponse;
  messages: Array<{ role: string; content: string }>;
  error?: string;
}> {
  if (USE_MOCK) {
    return {
      context: {
        system_message: 'Mock system message',
        immediate: 'Mock immediate context',
        working: 'Mock working context',
        episodic: 'Mock episodic context',
        semantic: 'Mock semantic context',
        total_tokens: 1000,
      },
      messages: [
        { role: 'system', content: 'Mock system message' },
        { role: 'user', content: utterance },
      ],
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/barge-in`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ utterance }),
  });

  return response.json();
}

/**
 * Set current topic for a session
 */
export async function setFOVTopic(
  sessionId: string,
  params: {
    topic_id: string;
    topic_title: string;
    topic_content?: string;
    learning_objectives?: string[];
    glossary_terms?: Array<{ term: string; definition: string }>;
  }
): Promise<{ topic_id: string; error?: string }> {
  if (USE_MOCK) {
    return { topic_id: params.topic_id };
  }

  const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/topic`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });

  return response.json();
}

/**
 * Analyze response confidence
 */
export async function analyzeFOVResponse(
  sessionId: string,
  response: string
): Promise<FOVConfidenceAnalysis> {
  if (USE_MOCK) {
    return {
      confidence_score: 0.85,
      uncertainty_score: 0.15,
      hedging_score: 0.1,
      deflection_score: 0.05,
      knowledge_gap_score: 0.1,
      vague_language_score: 0.05,
      detected_markers: [],
      trend: 'stable',
    };
  }

  const resp = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/analyze-response`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ response }),
  });

  return resp.json();
}

/**
 * Build context for an LLM call
 */
export async function buildFOVContext(
  sessionId: string,
  bargeInUtterance?: string
): Promise<FOVContextBuildResponse> {
  if (USE_MOCK) {
    return {
      system_message: 'Mock system message',
      immediate: 'Mock immediate context',
      working: 'Mock working context',
      episodic: 'Mock episodic context',
      semantic: 'Mock semantic context',
      total_tokens: 1000,
    };
  }

  const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}/context/build`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ barge_in_utterance: bargeInUtterance }),
  });

  return response.json();
}

/**
 * Delete an FOV session
 */
export async function deleteFOVSession(
  sessionId: string
): Promise<{ deleted: boolean; error?: string }> {
  if (USE_MOCK) {
    return { deleted: true };
  }

  const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}`, {
    method: 'DELETE',
  });

  return response.json();
}
