// VoiceLearn Management Console Types

export interface LogEntry {
  id: string;
  timestamp: string;
  level: 'DEBUG' | 'INFO' | 'WARNING' | 'ERROR' | 'CRITICAL';
  label: string;
  message: string;
  file?: string;
  function?: string;
  line?: number;
  metadata?: Record<string, unknown>;
  client_id: string;
  client_name: string;
  received_at: number;
}

export interface MetricsSnapshot {
  id: string;
  client_id: string;
  client_name: string;
  timestamp: string;
  received_at: number;
  session_duration: number;
  turns_total: number;
  interruptions: number;
  // Latencies (in ms)
  stt_latency_median: number;
  stt_latency_p99: number;
  llm_ttft_median: number;
  llm_ttft_p99: number;
  tts_ttfb_median: number;
  tts_ttfb_p99: number;
  e2e_latency_median: number;
  e2e_latency_p99: number;
  // Costs
  stt_cost: number;
  tts_cost: number;
  llm_cost: number;
  total_cost: number;
  // Device stats
  thermal_throttle_events: number;
  network_degradations: number;
}

export interface RemoteClient {
  id: string;
  name: string;
  device_model: string;
  os_version: string;
  app_version: string;
  first_seen: number;
  last_seen: number;
  ip_address: string;
  status: 'online' | 'idle' | 'offline';
  current_session_id?: string;
  total_sessions: number;
  total_logs: number;
  config?: Record<string, unknown>;
}

export interface ServerStatus {
  id: string;
  name: string;
  type: 'ollama' | 'whisper' | 'piper' | 'voicelearnGateway' | 'custom';
  url: string;
  port: number;
  status: 'unknown' | 'healthy' | 'degraded' | 'unhealthy';
  last_check: number;
  response_time_ms: number;
  capabilities?: Record<string, unknown>;
  models: string[];
  error_message?: string;
}

export interface ModelInfo {
  id: string;
  name: string;
  type: 'llm' | 'stt' | 'tts';
  server_id: string;
  server_name: string;
  status: 'available' | 'loading' | 'unavailable';
  size_bytes?: number;
  parameters?: string;
  quantization?: string;
}

export interface DashboardStats {
  uptime_seconds: number;
  total_logs: number;
  total_metrics: number;
  errors_count: number;
  warnings_count: number;
  logs_last_hour: number;
  sessions_last_hour: number;
  online_clients: number;
  total_clients: number;
  healthy_servers: number;
  total_servers: number;
  avg_e2e_latency: number;
  avg_llm_ttft: number;
  websocket_connections: number;
}

// API Response types
export interface LogsResponse {
  logs: LogEntry[];
  total: number;
  limit: number;
  offset: number;
}

export interface MetricsResponse {
  metrics: MetricsSnapshot[];
  aggregates: {
    avg_e2e_latency: number;
    avg_llm_ttft: number;
    avg_stt_latency: number;
    avg_tts_ttfb: number;
    total_cost: number;
    total_sessions: number;
    total_turns: number;
  };
}

export interface ClientsResponse {
  clients: RemoteClient[];
  total: number;
  online: number;
  idle: number;
  offline: number;
}

export interface ServersResponse {
  servers: ServerStatus[];
  total: number;
  healthy: number;
  degraded: number;
  unhealthy: number;
}

export interface ModelsResponse {
  models: ModelInfo[];
  total: number;
  by_type: {
    llm: number;
    stt: number;
    tts: number;
  };
}
