/**
 * STT/TTS/LLM Provider Types
 * Based on WEB_CLIENT_TDD.md Section 5
 */

// ===== Common Types =====

export type ProviderType = 'stt' | 'llm' | 'tts';

export interface ProviderInfo {
  name: string;
  displayName: string;
  type: ProviderType;
  isAvailable: boolean;
  requiresApiKey: boolean;
  supportsSelfHosted: boolean;
}

// ===== STT Provider =====

export interface WordTiming {
  word: string;
  start: number;
  end: number;
  confidence: number;
}

export interface STTResult {
  text: string;
  isFinal: boolean;
  confidence?: number;
  words?: WordTiming[];
  language?: string;
}

export interface STTEndpointing {
  silenceThreshold: number; // ms
  utteranceEndTimeout: number; // ms
}

export interface STTConfig {
  sampleRate: number;
  channels: number;
  language?: string;
  model?: string;
  interimResults?: boolean;
  endpointing?: STTEndpointing;
}

export interface STTProvider {
  readonly name: string;
  readonly costPerHour: number;
  readonly isStreaming: boolean;

  connect(config: STTConfig): Promise<void>;
  startStreaming(): AsyncIterable<STTResult>;
  sendAudio(buffer: ArrayBuffer): void;
  stopStreaming(): Promise<STTResult | null>;
  disconnect(): void;
}

export type STTProviderName =
  | 'openai-realtime'
  | 'deepgram'
  | 'assemblyai'
  | 'groq'
  | 'self-hosted';

// ===== LLM Provider =====

export interface ToolCall {
  id: string;
  type: 'function';
  function: {
    name: string;
    arguments: string;
  };
}

export interface ToolDefinition {
  type: 'function';
  function: {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
  };
}

export type FinishReason = 'stop' | 'length' | 'tool_calls';

export interface LLMToken {
  content: string;
  finishReason?: FinishReason;
  toolCalls?: ToolCall[];
}

export type MessageRole = 'system' | 'user' | 'assistant' | 'tool';

export interface Message {
  role: MessageRole;
  content: string;
  toolCallId?: string;
  name?: string;
  timestamp?: Date;
}

export interface LLMConfig {
  model: string;
  maxTokens: number;
  temperature: number;
  topP?: number;
  stopSequences?: string[];
  tools?: ToolDefinition[];
}

export interface LLMProvider {
  readonly name: string;
  readonly costPerInputToken: number;
  readonly costPerOutputToken: number;

  streamCompletion(
    messages: Message[],
    config: LLMConfig
  ): AsyncIterable<LLMToken>;

  cancelCompletion(): void;
}

export type LLMProviderName = 'openai' | 'anthropic' | 'self-hosted';

// ===== TTS Provider =====

export type AudioFormat = 'pcm' | 'mp3' | 'opus';

export interface AudioChunk {
  audio: ArrayBuffer;
  format: AudioFormat;
  sampleRate: number;
  isFinal: boolean;
}

export interface TTSConfig {
  voice: string;
  speed?: number; // 0.5 - 2.0
  pitch?: number; // -20 to 20 semitones
  stability?: number; // 0 - 1 (ElevenLabs)
  similarityBoost?: number; // 0 - 1 (ElevenLabs)
}

export interface TTSProvider {
  readonly name: string;
  readonly costPerCharacter: number;

  configure(config: TTSConfig): void;
  synthesize(text: string): AsyncIterable<AudioChunk>;
  flush(): Promise<void>;
  cancel(): void;
}

export type TTSProviderName =
  | 'openai-realtime'
  | 'elevenlabs'
  | 'deepgram'
  | 'self-hosted';

// ===== Provider Registry =====

export interface STTProviderConfig {
  provider: STTProviderName;
  model?: string;
  language?: string;
  punctuate?: boolean;
  interimResults?: boolean;
}

export interface LLMProviderConfig {
  provider: LLMProviderName;
  model: string;
  maxTokens?: number;
  temperature?: number;
}

export interface TTSProviderConfig {
  provider: TTSProviderName;
  voice: string;
  model?: string;
  stability?: number;
  similarityBoost?: number;
}

export interface ProviderConfig {
  stt: STTProviderConfig;
  llm: LLMProviderConfig;
  tts: TTSProviderConfig;
}

// ===== Default Configurations =====

export const defaultSTTConfigs: Record<STTProviderName, Partial<STTProviderConfig>> = {
  'openai-realtime': {
    model: 'gpt-4o-realtime-preview',
    language: 'en',
  },
  deepgram: {
    model: 'nova-3',
    language: 'en-US',
    punctuate: true,
    interimResults: true,
  },
  assemblyai: {
    model: 'universal',
    language: 'en',
  },
  groq: {
    model: 'whisper-large-v3',
    language: 'en',
  },
  'self-hosted': {},
};

export const defaultLLMConfigs: Record<LLMProviderName, Partial<LLMProviderConfig>> = {
  openai: {
    model: 'gpt-4o',
    maxTokens: 1024,
    temperature: 0.7,
  },
  anthropic: {
    model: 'claude-3-5-sonnet-20241022',
    maxTokens: 1024,
    temperature: 0.7,
  },
  'self-hosted': {
    model: 'llama3.2',
    maxTokens: 2048,
    temperature: 0.7,
  },
};

export const defaultTTSConfigs: Record<TTSProviderName, Partial<TTSProviderConfig>> = {
  'openai-realtime': {
    voice: 'coral',
  },
  elevenlabs: {
    voice: 'EXAVITQu4vr4xnSDxMaL', // Bella
    model: 'eleven_turbo_v2_5',
    stability: 0.5,
    similarityBoost: 0.75,
  },
  deepgram: {
    voice: 'aura-asteria-en',
  },
  'self-hosted': {
    voice: 'default',
  },
};

// ===== Audio Configuration =====

export interface AudioConfig {
  sampleRate: 16000 | 22050 | 24000 | 44100 | 48000;
  bitDepth: 16 | 24 | 32;
  channels: 1 | 2;
  codec?: 'pcm' | 'opus' | 'mp3';
}

export const providerAudioRequirements: Record<string, AudioConfig> = {
  'openai-realtime': {
    sampleRate: 24000,
    bitDepth: 16,
    channels: 1,
    codec: 'opus',
  },
  deepgram: {
    sampleRate: 16000,
    bitDepth: 16,
    channels: 1,
    codec: 'pcm',
  },
  assemblyai: {
    sampleRate: 16000,
    bitDepth: 16,
    channels: 1,
    codec: 'pcm',
  },
  elevenlabs: {
    sampleRate: 24000,
    bitDepth: 16,
    channels: 1,
    codec: 'mp3',
  },
};

// ===== Provider Manager Types =====

export interface ProviderManagerState {
  stt: {
    provider: STTProviderName;
    isConnected: boolean;
    isStreaming: boolean;
  };
  llm: {
    provider: LLMProviderName;
    isGenerating: boolean;
  };
  tts: {
    provider: TTSProviderName;
    isPlaying: boolean;
    queue: number;
  };
}

export interface ProviderManagerActions {
  configureProviders: (config: ProviderConfig) => Promise<void>;
  switchSTT: (provider: STTProviderName, config?: Partial<STTProviderConfig>) => Promise<void>;
  switchLLM: (provider: LLMProviderName, config?: Partial<LLMProviderConfig>) => Promise<void>;
  switchTTS: (provider: TTSProviderName, config?: Partial<TTSProviderConfig>) => Promise<void>;
  getProviderCosts: () => {
    stt: { costPerHour: number };
    llm: { costPerInputToken: number; costPerOutputToken: number };
    tts: { costPerCharacter: number };
  };
}
