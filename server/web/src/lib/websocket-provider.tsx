'use client';

import React, { createContext, useContext, useEffect, useState, useCallback, useRef } from 'react';

// WebSocket message types from the Python backend
export type WebSocketMessageType =
  | 'log'
  | 'metrics'
  | 'client_update'
  | 'server_added'
  | 'server_deleted'
  | 'service_update'
  | 'logs_cleared'
  | 'curriculum_imported'
  | 'curriculum_updated'
  | 'curriculum_archived'
  | 'curriculum_deleted'
  | 'models_unloaded'
  | 'import_progress'
  | 'stats_update'
  | 'plugin_update';

export interface WebSocketMessage {
  type: WebSocketMessageType;
  data: unknown;
  timestamp: string;
}

type MessageHandler = (data: unknown) => void;

interface WebSocketContextValue {
  connected: boolean;
  connecting: boolean;
  error: string | null;
  lastMessage: WebSocketMessage | null;
  subscribe: (type: WebSocketMessageType, handler: MessageHandler) => () => void;
  reconnect: () => void;
}

const WebSocketContext = createContext<WebSocketContextValue | null>(null);

// Default WebSocket URL points directly to Python backend
const DEFAULT_WS_URL = 'ws://localhost:8766/ws';

interface WebSocketProviderProps {
  children: React.ReactNode;
  url?: string;
  reconnectInterval?: number;
  maxReconnectAttempts?: number;
}

export function WebSocketProvider({
  children,
  url = DEFAULT_WS_URL,
  reconnectInterval = 3000,
  maxReconnectAttempts = 10,
}: WebSocketProviderProps) {
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastMessage, setLastMessage] = useState<WebSocketMessage | null>(null);

  const wsRef = useRef<WebSocket | null>(null);
  const handlersRef = useRef<Map<WebSocketMessageType, Set<MessageHandler>>>(new Map());
  const reconnectAttemptsRef = useRef(0);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const mountedRef = useRef(true);
  // Store config in refs to avoid stale closures
  const configRef = useRef({ url, reconnectInterval, maxReconnectAttempts });
  configRef.current = { url, reconnectInterval, maxReconnectAttempts };

  // Create socket connection - defined as a regular function, not useCallback
  // to avoid circular dependency issues
  const createConnection = useCallback(function doConnect(): void {
    const {
      url: wsUrl,
      maxReconnectAttempts: maxAttempts,
      reconnectInterval: interval,
    } = configRef.current;

    // Don't connect if we're already connected or connecting
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      return;
    }

    // Don't exceed max reconnect attempts
    if (reconnectAttemptsRef.current >= maxAttempts) {
      setError(`Failed to connect after ${maxAttempts} attempts`);
      return;
    }

    setConnecting(true);
    setError(null);

    try {
      const socket = new WebSocket(wsUrl);

      socket.onopen = () => {
        if (!mountedRef.current) return;
        setConnected(true);
        setConnecting(false);
        setError(null);
        reconnectAttemptsRef.current = 0;
        console.log('[WebSocket] Connected to', wsUrl);
      };

      socket.onclose = (event) => {
        if (!mountedRef.current) return;
        setConnected(false);
        setConnecting(false);
        wsRef.current = null;

        if (!event.wasClean && mountedRef.current) {
          console.log('[WebSocket] Connection closed unexpectedly, attempting reconnect...');
          // Schedule reconnect using the function recursively
          reconnectAttemptsRef.current += 1;
          const delay = Math.min(interval * Math.pow(1.5, reconnectAttemptsRef.current - 1), 30000);
          reconnectTimeoutRef.current = setTimeout(() => {
            if (mountedRef.current) {
              doConnect();
            }
          }, delay);
        } else {
          console.log('[WebSocket] Connection closed cleanly');
        }
      };

      socket.onerror = () => {
        if (!mountedRef.current) return;
        setError('WebSocket connection error');
        setConnecting(false);
      };

      socket.onmessage = (event) => {
        if (!mountedRef.current) return;
        try {
          const message: WebSocketMessage = JSON.parse(event.data);
          setLastMessage(message);

          // Dispatch to registered handlers
          const typeHandlers = handlersRef.current.get(message.type);
          if (typeHandlers) {
            typeHandlers.forEach((handler) => {
              try {
                handler(message.data);
              } catch (err) {
                // Use String() to ensure message.type is safely converted to a string
                console.error('[WebSocket] Handler error for ' + String(message.type) + ':', err);
              }
            });
          }
        } catch (err) {
          console.error('[WebSocket] Failed to parse message:', err);
        }
      };

      wsRef.current = socket;
    } catch (err) {
      console.error('[WebSocket] Failed to create connection:', err);
      setConnecting(false);
      setError('Failed to create WebSocket connection');
    }
  }, []);

  const reconnect = useCallback(() => {
    // Close existing connection if any
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }

    // Reset reconnect counter
    reconnectAttemptsRef.current = 0;

    // Clear any pending reconnect
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }

    // Connect immediately
    createConnection();
  }, [createConnection]);

  const subscribe = useCallback(
    (type: WebSocketMessageType, handler: MessageHandler): (() => void) => {
      if (!handlersRef.current.has(type)) {
        handlersRef.current.set(type, new Set());
      }

      handlersRef.current.get(type)!.add(handler);

      // Return unsubscribe function
      return () => {
        const handlers = handlersRef.current.get(type);
        if (handlers) {
          handlers.delete(handler);
          if (handlers.size === 0) {
            handlersRef.current.delete(type);
          }
        }
      };
    },
    []
  );

  // Initial connection and cleanup
  useEffect(() => {
    mountedRef.current = true;
    createConnection();

    return () => {
      mountedRef.current = false;
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, [createConnection]);

  const value: WebSocketContextValue = {
    connected,
    connecting,
    error,
    lastMessage,
    subscribe,
    reconnect,
  };

  return <WebSocketContext.Provider value={value}>{children}</WebSocketContext.Provider>;
}

/**
 * Hook to access WebSocket connection state and subscribe to messages
 */
export function useWebSocket() {
  const context = useContext(WebSocketContext);

  if (!context) {
    throw new Error('useWebSocket must be used within a WebSocketProvider');
  }

  return context;
}

/**
 * Hook to subscribe to specific WebSocket message types
 */
export function useWebSocketSubscription(
  type: WebSocketMessageType,
  handler: MessageHandler,
  deps: React.DependencyList = []
) {
  const { subscribe } = useWebSocket();

  useEffect(() => {
    const unsubscribe = subscribe(type, handler);
    return unsubscribe;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [type, subscribe, ...deps]);
}

/**
 * Hook to get the current connection status
 */
export function useWebSocketStatus() {
  const { connected, connecting, error } = useWebSocket();
  return { connected, connecting, error };
}
