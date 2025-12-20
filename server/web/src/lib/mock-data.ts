// Mock data for standalone frontend development
import type {
  LogEntry,
  MetricsSnapshot,
  RemoteClient,
  ServerStatus,
  ModelInfo,
  DashboardStats,
} from '@/types';

const now = Date.now();

// Helper to generate random ID
const genId = () => Math.random().toString(36).substring(2, 15);

// Mock Logs
export const mockLogs: LogEntry[] = [
  {
    id: genId(),
    timestamp: new Date(now - 1000).toISOString(),
    level: 'INFO',
    label: 'com.voicelearn.session',
    message: 'Session started with curriculum: Introduction to Swift',
    client_id: 'device-001',
    client_name: 'iPhone 16 Pro Max',
    received_at: now - 1000,
  },
  {
    id: genId(),
    timestamp: new Date(now - 5000).toISOString(),
    level: 'DEBUG',
    label: 'com.voicelearn.audio',
    message: 'AudioEngine initialized with sample rate 48000Hz',
    file: 'AudioEngine.swift',
    function: 'start()',
    line: 142,
    client_id: 'device-001',
    client_name: 'iPhone 16 Pro Max',
    received_at: now - 5000,
  },
  {
    id: genId(),
    timestamp: new Date(now - 10000).toISOString(),
    level: 'INFO',
    label: 'com.voicelearn.stt',
    message: 'STT streaming started with Deepgram Nova-3',
    client_id: 'device-001',
    client_name: 'iPhone 16 Pro Max',
    received_at: now - 10000,
  },
  {
    id: genId(),
    timestamp: new Date(now - 15000).toISOString(),
    level: 'WARNING',
    label: 'com.voicelearn.thermal',
    message: 'Thermal state changed to FAIR - reducing quality',
    client_id: 'device-002',
    client_name: 'iPhone 15 Pro',
    received_at: now - 15000,
  },
  {
    id: genId(),
    timestamp: new Date(now - 20000).toISOString(),
    level: 'INFO',
    label: 'com.voicelearn.llm',
    message: 'LLM response completed in 387ms (Claude 3.5 Sonnet)',
    metadata: { ttft: 387, tokens: 156 },
    client_id: 'device-001',
    client_name: 'iPhone 16 Pro Max',
    received_at: now - 20000,
  },
  {
    id: genId(),
    timestamp: new Date(now - 30000).toISOString(),
    level: 'ERROR',
    label: 'com.voicelearn.network',
    message: 'Connection timeout to self-hosted Ollama server',
    file: 'SelfHostedLLMService.swift',
    function: 'streamCompletion()',
    line: 89,
    client_id: 'device-002',
    client_name: 'iPhone 15 Pro',
    received_at: now - 30000,
  },
  {
    id: genId(),
    timestamp: new Date(now - 45000).toISOString(),
    level: 'INFO',
    label: 'com.voicelearn.tts',
    message: 'TTS playback started - TTFB: 142ms (ElevenLabs)',
    client_id: 'device-001',
    client_name: 'iPhone 16 Pro Max',
    received_at: now - 45000,
  },
  {
    id: genId(),
    timestamp: new Date(now - 60000).toISOString(),
    level: 'DEBUG',
    label: 'com.voicelearn.vad',
    message: 'VAD detected speech start with confidence 0.94',
    client_id: 'device-001',
    client_name: 'iPhone 16 Pro Max',
    received_at: now - 60000,
  },
];

// Mock Metrics
export const mockMetrics: MetricsSnapshot[] = [
  {
    id: genId(),
    client_id: 'device-001',
    client_name: 'iPhone 16 Pro Max',
    timestamp: new Date(now - 60000).toISOString(),
    received_at: now - 60000,
    session_duration: 1847,
    turns_total: 24,
    interruptions: 2,
    stt_latency_median: 245,
    stt_latency_p99: 412,
    llm_ttft_median: 387,
    llm_ttft_p99: 623,
    tts_ttfb_median: 142,
    tts_ttfb_p99: 289,
    e2e_latency_median: 486,
    e2e_latency_p99: 834,
    stt_cost: 0.0024,
    tts_cost: 0.0018,
    llm_cost: 0.0156,
    total_cost: 0.0198,
    thermal_throttle_events: 0,
    network_degradations: 1,
  },
  {
    id: genId(),
    client_id: 'device-002',
    client_name: 'iPhone 15 Pro',
    timestamp: new Date(now - 120000).toISOString(),
    received_at: now - 120000,
    session_duration: 2456,
    turns_total: 31,
    interruptions: 4,
    stt_latency_median: 289,
    stt_latency_p99: 478,
    llm_ttft_median: 456,
    llm_ttft_p99: 712,
    tts_ttfb_median: 168,
    tts_ttfb_p99: 312,
    e2e_latency_median: 534,
    e2e_latency_p99: 912,
    stt_cost: 0.0032,
    tts_cost: 0.0024,
    llm_cost: 0.0234,
    total_cost: 0.029,
    thermal_throttle_events: 2,
    network_degradations: 0,
  },
];

// Mock Clients
export const mockClients: RemoteClient[] = [
  {
    id: 'device-001',
    name: 'iPhone 16 Pro Max',
    device_model: 'iPhone17,2',
    os_version: 'iOS 18.1',
    app_version: '1.0.0',
    first_seen: now - 86400000,
    last_seen: now - 30000,
    ip_address: '192.168.1.45',
    status: 'online',
    current_session_id: 'session-abc123',
    total_sessions: 47,
    total_logs: 1234,
  },
  {
    id: 'device-002',
    name: 'iPhone 15 Pro',
    device_model: 'iPhone16,1',
    os_version: 'iOS 18.0',
    app_version: '1.0.0',
    first_seen: now - 172800000,
    last_seen: now - 180000,
    ip_address: '192.168.1.67',
    status: 'idle',
    total_sessions: 23,
    total_logs: 567,
  },
  {
    id: 'device-003',
    name: 'iPad Pro',
    device_model: 'iPad14,3',
    os_version: 'iOS 18.1',
    app_version: '1.0.0',
    first_seen: now - 604800000,
    last_seen: now - 86400000,
    ip_address: '192.168.1.89',
    status: 'offline',
    total_sessions: 12,
    total_logs: 234,
  },
];

// Mock Servers
export const mockServers: ServerStatus[] = [
  {
    id: 'ollama',
    name: 'Ollama LLM',
    type: 'ollama',
    url: 'http://localhost:11434',
    port: 11434,
    status: 'healthy',
    last_check: now - 5000,
    response_time_ms: 12,
    models: ['llama3.2:3b', 'qwen2.5:7b', 'deepseek-r1:8b'],
    capabilities: { models: ['llama3.2:3b', 'qwen2.5:7b', 'deepseek-r1:8b'] },
  },
  {
    id: 'whisper',
    name: 'Whisper STT',
    type: 'whisper',
    url: 'http://localhost:11401',
    port: 11401,
    status: 'healthy',
    last_check: now - 5000,
    response_time_ms: 8,
    models: ['whisper-large-v3'],
  },
  {
    id: 'piper',
    name: 'Piper TTS',
    type: 'piper',
    url: 'http://localhost:11402',
    port: 11402,
    status: 'degraded',
    last_check: now - 5000,
    response_time_ms: 156,
    models: ['en_US-lessac-medium', 'en_US-amy-medium'],
    error_message: 'High latency detected',
  },
  {
    id: 'gateway',
    name: 'VoiceLearn Gateway',
    type: 'voicelearnGateway',
    url: 'http://localhost:11400',
    port: 11400,
    status: 'unhealthy',
    last_check: now - 5000,
    response_time_ms: 0,
    models: [],
    error_message: 'Connection refused',
  },
];

// Mock Models
export const mockModels: ModelInfo[] = [
  {
    id: 'ollama:llama3.2:3b',
    name: 'llama3.2:3b',
    type: 'llm',
    server_id: 'ollama',
    server_name: 'Ollama LLM',
    status: 'available',
    parameters: '3B',
  },
  {
    id: 'ollama:qwen2.5:7b',
    name: 'qwen2.5:7b',
    type: 'llm',
    server_id: 'ollama',
    server_name: 'Ollama LLM',
    status: 'available',
    parameters: '7B',
    quantization: 'Q4_K_M',
  },
  {
    id: 'ollama:deepseek-r1:8b',
    name: 'deepseek-r1:8b',
    type: 'llm',
    server_id: 'ollama',
    server_name: 'Ollama LLM',
    status: 'available',
    parameters: '8B',
  },
  {
    id: 'whisper:whisper-large-v3',
    name: 'whisper-large-v3',
    type: 'stt',
    server_id: 'whisper',
    server_name: 'Whisper STT',
    status: 'available',
  },
  {
    id: 'piper:en_US-lessac-medium',
    name: 'en_US-lessac-medium',
    type: 'tts',
    server_id: 'piper',
    server_name: 'Piper TTS',
    status: 'available',
  },
  {
    id: 'piper:en_US-amy-medium',
    name: 'en_US-amy-medium',
    type: 'tts',
    server_id: 'piper',
    server_name: 'Piper TTS',
    status: 'available',
  },
];

// Mock Dashboard Stats
export function getMockStats(): DashboardStats {
  const uptimeBase = 3600 + Math.floor(Math.random() * 1000);
  return {
    uptime_seconds: uptimeBase,
    total_logs: mockLogs.length + Math.floor(Math.random() * 100),
    total_metrics: mockMetrics.length + Math.floor(Math.random() * 10),
    errors_count: 1,
    warnings_count: 1,
    logs_last_hour: mockLogs.length,
    sessions_last_hour: mockMetrics.length,
    online_clients: mockClients.filter(c => c.status === 'online').length,
    total_clients: mockClients.length,
    healthy_servers: mockServers.filter(s => s.status === 'healthy').length,
    total_servers: mockServers.length,
    avg_e2e_latency: 486,
    avg_llm_ttft: 387,
    websocket_connections: 0,
  };
}

// Helper to add a new mock log (for simulating real-time updates)
export function generateMockLog(): LogEntry {
  const levels: LogEntry['level'][] = ['DEBUG', 'INFO', 'INFO', 'INFO', 'WARNING', 'ERROR'];
  const labels = [
    'com.voicelearn.session',
    'com.voicelearn.audio',
    'com.voicelearn.stt',
    'com.voicelearn.tts',
    'com.voicelearn.llm',
    'com.voicelearn.vad',
  ];
  const messages = [
    'Processing audio buffer',
    'VAD detected speech',
    'STT partial result received',
    'LLM streaming token',
    'TTS chunk received',
    'Session state changed',
    'Network latency spike detected',
    'Thermal state nominal',
  ];

  const client = mockClients[Math.floor(Math.random() * mockClients.length)];
  const currentTime = Date.now();

  return {
    id: genId(),
    timestamp: new Date(currentTime).toISOString(),
    level: levels[Math.floor(Math.random() * levels.length)],
    label: labels[Math.floor(Math.random() * labels.length)],
    message: messages[Math.floor(Math.random() * messages.length)],
    client_id: client.id,
    client_name: client.name,
    received_at: currentTime,
  };
}
