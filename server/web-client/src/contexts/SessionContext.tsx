'use client';

/**
 * Session Context
 *
 * Provides voice session state management using the ProviderManager.
 * Handles WebRTC connection, state machine, and conversation history.
 */

import * as React from 'react';
import { getProviderManager, type ProviderManager } from '@/lib/providers';
import type { SessionState, Message, VisualAsset } from '@/types';

// ===== Types =====

interface SessionContextValue {
  // State
  state: SessionState;
  conversationHistory: Message[];
  currentUtterance: string;
  visualAssets: VisualAsset[];
  duration: number;
  isMuted: boolean;
  isSpeakerMuted: boolean;
  isConnecting: boolean;
  error: Error | null;

  // Actions
  startSession: (config?: SessionConfig) => Promise<void>;
  stopSession: () => void;
  pauseSession: () => void;
  resumeSession: () => void;
  toggleMute: () => void;
  toggleSpeaker: () => void;
  sendTextMessage: (text: string) => void;
  clearError: () => void;
}

interface SessionConfig {
  curriculumId?: string;
  topicId?: string;
  instructions?: string;
  voice?: 'alloy' | 'ash' | 'ballad' | 'coral' | 'echo' | 'sage' | 'shimmer' | 'verse';
}

// ===== Context =====

const SessionContext = React.createContext<SessionContextValue | null>(null);

// ===== Provider =====

export function SessionProvider({ children }: { children: React.ReactNode }) {
  // State
  const [state, setState] = React.useState<SessionState>('idle');
  const [conversationHistory, setConversationHistory] = React.useState<Message[]>([]);
  const [currentUtterance, setCurrentUtterance] = React.useState('');
  const [visualAssets, setVisualAssets] = React.useState<VisualAsset[]>([]);
  const [duration, setDuration] = React.useState(0);
  const [isMuted, setIsMuted] = React.useState(false);
  const [isSpeakerMuted, setIsSpeakerMuted] = React.useState(false);
  const [isConnecting, setIsConnecting] = React.useState(false);
  const [error, setError] = React.useState<Error | null>(null);

  // Refs
  const providerManagerRef = React.useRef<ProviderManager | null>(null);
  const timerRef = React.useRef<ReturnType<typeof setInterval> | null>(null);

  // Duration timer
  React.useEffect(() => {
    if (state !== 'idle' && state !== 'paused' && state !== 'error') {
      timerRef.current = setInterval(() => {
        setDuration((d) => d + 1);
      }, 1000);
    } else if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }

    return () => {
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
    };
  }, [state]);

  // Cleanup on unmount
  React.useEffect(() => {
    return () => {
      providerManagerRef.current?.dispose();
    };
  }, []);

  // Start session
  const startSession = React.useCallback(async (config?: SessionConfig) => {
    if (state !== 'idle') return;

    setIsConnecting(true);
    setError(null);

    try {
      // Get or create provider manager
      const manager = getProviderManager();
      providerManagerRef.current = manager;

      // Configure the provider manager
      await manager.configure(
        {
          stt: {
            provider: 'openai-realtime',
            model: 'gpt-4o-realtime-preview-2024-12-17',
          },
          llm: {
            provider: 'openai',
            model: 'gpt-4o',
          },
          tts: {
            provider: 'openai-realtime',
            voice: config?.voice || 'coral',
          },
        },
        {
          onSTTConnected: () => {
            setState('userSpeaking');
            setConversationHistory([
              {
                role: 'system',
                content: 'Session started. You can begin speaking.',
                timestamp: new Date(),
              },
            ]);
          },
          onSTTResult: (result) => {
            if (result.isFinal) {
              // Add to conversation history
              setConversationHistory((h) => [
                ...h,
                {
                  role: 'user',
                  content: result.text,
                  timestamp: new Date(),
                },
              ]);
              setCurrentUtterance('');
              setState('aiThinking');
            } else {
              setCurrentUtterance(result.text);
            }
          },
          onTTSStart: () => {
            setState('aiSpeaking');
          },
          onTTSComplete: () => {
            setState('userSpeaking');
          },
          onError: (err, source) => {
            console.error(`[Session] Error from ${source}:`, err);
            setError(err);
            setState('error');
          },
          onStateChange: (providerState) => {
            console.debug('[Session] Provider state:', providerState);
          },
        }
      );

      // Connect to OpenAI Realtime
      await manager.connectSTT();
      await manager.startSTTStreaming();

    } catch (err) {
      console.error('[Session] Failed to start:', err);
      setError(err instanceof Error ? err : new Error(String(err)));
      setState('error');
    } finally {
      setIsConnecting(false);
    }
  }, [state]);

  // Stop session
  const stopSession = React.useCallback(() => {
    providerManagerRef.current?.dispose();
    providerManagerRef.current = null;

    setState('idle');
    setCurrentUtterance('');
    setDuration(0);
    setConversationHistory([]);
    setVisualAssets([]);
    setError(null);
  }, []);

  // Pause session
  const pauseSession = React.useCallback(() => {
    if (state === 'userSpeaking' || state === 'aiSpeaking' || state === 'aiThinking') {
      setState('paused');
      providerManagerRef.current?.stopSTTStreaming();
    }
  }, [state]);

  // Resume session
  const resumeSession = React.useCallback(() => {
    if (state === 'paused') {
      setState('userSpeaking');
      providerManagerRef.current?.startSTTStreaming();
    }
  }, [state]);

  // Toggle mute
  const toggleMute = React.useCallback(() => {
    setIsMuted((m) => {
      const newMuted = !m;
      // If using OpenAI Realtime, this is handled via the provider
      return newMuted;
    });
  }, []);

  // Toggle speaker
  const toggleSpeaker = React.useCallback(() => {
    setIsSpeakerMuted((m) => !m);
  }, []);

  // Send text message (for accessibility or text input mode)
  const sendTextMessage = React.useCallback((text: string) => {
    if (!text.trim()) return;

    setConversationHistory((h) => [
      ...h,
      {
        role: 'user',
        content: text,
        timestamp: new Date(),
      },
    ]);

    setState('aiThinking');

    // Synthesize response
    providerManagerRef.current?.synthesize(text);
  }, []);

  // Clear error
  const clearError = React.useCallback(() => {
    setError(null);
    if (state === 'error') {
      setState('idle');
    }
  }, [state]);

  // Context value
  const value: SessionContextValue = {
    state,
    conversationHistory,
    currentUtterance,
    visualAssets,
    duration,
    isMuted,
    isSpeakerMuted,
    isConnecting,
    error,
    startSession,
    stopSession,
    pauseSession,
    resumeSession,
    toggleMute,
    toggleSpeaker,
    sendTextMessage,
    clearError,
  };

  return (
    <SessionContext.Provider value={value}>
      {children}
    </SessionContext.Provider>
  );
}

// ===== Hook =====

export function useSession(): SessionContextValue {
  const context = React.useContext(SessionContext);
  if (!context) {
    throw new Error('useSession must be used within a SessionProvider');
  }
  return context;
}

// ===== Export =====

export { SessionContext };
