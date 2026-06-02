/**
 * OpenAI Realtime Provider
 *
 * WebRTC-based provider for OpenAI's Realtime API.
 * Handles bidirectional voice conversation with lowest latency.
 */

import { tokenManager } from '../api/token-manager';
import type {
  STTResult,
  LLMToken,
  AudioChunk,
} from './types';

// ===== Types =====

export interface RealtimeConfig {
  /** Voice to use for TTS */
  voice?: 'alloy' | 'ash' | 'ballad' | 'coral' | 'echo' | 'sage' | 'shimmer' | 'verse';
  /** Model to use */
  model?: string;
  /** System instructions */
  instructions?: string;
  /** Turn detection settings */
  turnDetection?: {
    type: 'server_vad';
    threshold?: number;
    prefixPaddingMs?: number;
    silenceDurationMs?: number;
  };
}

export interface RealtimeEventHandlers {
  onSessionCreated?: (sessionId: string) => void;
  onTranscript?: (result: STTResult) => void;
  onResponseStart?: () => void;
  onResponseText?: (token: LLMToken) => void;
  onResponseAudio?: (chunk: AudioChunk) => void;
  onResponseComplete?: () => void;
  onError?: (error: Error) => void;
  onDisconnect?: () => void;
}

type RealtimeEvent =
  | { type: 'session.created'; session: { id: string; model: string } }
  | { type: 'session.updated'; session: { id: string } }
  | { type: 'conversation.item.input_audio_transcription.completed'; transcript: string }
  | { type: 'response.created'; response: { id: string } }
  | { type: 'response.text.delta'; delta: string }
  | { type: 'response.text.done'; text: string }
  | { type: 'response.audio.delta'; delta: string }
  | { type: 'response.audio.done' }
  | { type: 'response.done' }
  | { type: 'error'; error: { message: string; type: string } };

// ===== OpenAI Realtime Provider =====

export class OpenAIRealtimeProvider {
  readonly name = 'openai-realtime';
  readonly costPerHour = 0.06; // Approximate cost

  private peerConnection: RTCPeerConnection | null = null;
  private dataChannel: RTCDataChannel | null = null;
  private localStream: MediaStream | null = null;
  private remoteAudio: HTMLAudioElement | null = null;
  private sessionId: string | null = null;
  private handlers: RealtimeEventHandlers = {};
  private config: RealtimeConfig = {};

  /**
   * Connect to OpenAI Realtime API via WebRTC.
   */
  async connect(
    config: RealtimeConfig = {},
    handlers: RealtimeEventHandlers = {}
  ): Promise<void> {
    this.config = config;
    this.handlers = handlers;

    try {
      // 1. Get ephemeral token from our API. The token route requires auth to
      // defend against denial-of-wallet, so forward the access token.
      const tokenHeaders: Record<string, string> = { 'Content-Type': 'application/json' };
      const accessToken = await tokenManager.getValidToken();
      if (accessToken) {
        tokenHeaders['Authorization'] = `Bearer ${accessToken}`;
      }
      const tokenResponse = await fetch('/api/realtime/token', {
        method: 'POST',
        headers: tokenHeaders,
        body: JSON.stringify({
          model: config.model || 'gpt-4o-realtime-preview',
          voice: config.voice || 'coral',
        }),
      });

      if (!tokenResponse.ok) {
        throw new Error('Failed to get realtime token');
      }

      const { token } = await tokenResponse.json();

      // 2. Create peer connection
      this.peerConnection = new RTCPeerConnection();

      // 3. Get microphone access
      this.localStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: 24000,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });

      // 4. Add audio track to peer connection
      this.localStream.getAudioTracks().forEach((track) => {
        this.peerConnection!.addTrack(track, this.localStream!);
      });

      // 5. Handle remote audio (AI response)
      this.peerConnection.ontrack = (event) => {
        this.remoteAudio = new Audio();
        this.remoteAudio.srcObject = event.streams[0];
        this.remoteAudio.play().catch(console.error);
      };

      // 6. Create data channel for events
      this.dataChannel = this.peerConnection.createDataChannel('oai-events');
      this.dataChannel.onopen = () => this.onDataChannelOpen();
      this.dataChannel.onmessage = (event) => this.onDataChannelMessage(event);
      this.dataChannel.onerror = (event) => this.onDataChannelError(event);
      this.dataChannel.onclose = () => this.handlers.onDisconnect?.();

      // 7. Handle ICE candidates
      this.peerConnection.onicecandidate = (event) => {
        if (event.candidate) {
          console.debug('[Realtime] ICE candidate:', event.candidate.candidate);
        }
      };

      // 8. Create and send offer
      const offer = await this.peerConnection.createOffer();
      await this.peerConnection.setLocalDescription(offer);

      const sdpResponse = await fetch('https://api.openai.com/v1/realtime', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/sdp',
        },
        body: offer.sdp,
      });

      if (!sdpResponse.ok) {
        throw new Error('Failed to establish WebRTC connection');
      }

      const answerSdp = await sdpResponse.text();
      await this.peerConnection.setRemoteDescription({
        type: 'answer',
        sdp: answerSdp,
      });

    } catch (error) {
      this.handlers.onError?.(error instanceof Error ? error : new Error(String(error)));
      throw error;
    }
  }

  /**
   * Disconnect from OpenAI Realtime API.
   */
  disconnect(): void {
    // Close data channel
    if (this.dataChannel) {
      this.dataChannel.close();
      this.dataChannel = null;
    }

    // Close peer connection
    if (this.peerConnection) {
      this.peerConnection.close();
      this.peerConnection = null;
    }

    // Stop local stream
    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop());
      this.localStream = null;
    }

    // Stop remote audio
    if (this.remoteAudio) {
      this.remoteAudio.pause();
      this.remoteAudio.srcObject = null;
      this.remoteAudio = null;
    }

    this.sessionId = null;
  }

  /**
   * Send a text message to the conversation.
   */
  sendText(text: string): void {
    this.sendEvent({
      type: 'conversation.item.create',
      item: {
        type: 'message',
        role: 'user',
        content: [{ type: 'input_text', text }],
      },
    });

    // Trigger response
    this.sendEvent({ type: 'response.create' });
  }

  /**
   * Cancel the current response.
   */
  cancelResponse(): void {
    this.sendEvent({ type: 'response.cancel' });
  }

  /**
   * Mute/unmute the microphone.
   */
  setMuted(muted: boolean): void {
    if (this.localStream) {
      this.localStream.getAudioTracks().forEach((track) => {
        track.enabled = !muted;
      });
    }
  }

  /**
   * Get whether the microphone is muted.
   */
  get isMuted(): boolean {
    if (!this.localStream) return true;
    const track = this.localStream.getAudioTracks()[0];
    return !track?.enabled;
  }

  /**
   * Check if connected.
   */
  get isConnected(): boolean {
    return (
      this.peerConnection?.connectionState === 'connected' &&
      this.dataChannel?.readyState === 'open'
    );
  }

  // ===== Private Methods =====

  private onDataChannelOpen(): void {
    // Send session update with configuration
    this.sendEvent({
      type: 'session.update',
      session: {
        modalities: ['text', 'audio'],
        instructions: this.config.instructions || 'You are a helpful AI learning assistant.',
        voice: this.config.voice || 'coral',
        input_audio_format: 'pcm16',
        output_audio_format: 'pcm16',
        turn_detection: this.config.turnDetection || {
          type: 'server_vad',
          threshold: 0.5,
          prefix_padding_ms: 300,
          silence_duration_ms: 500,
        },
      },
    });
  }

  private onDataChannelMessage(event: MessageEvent): void {
    try {
      const data = JSON.parse(event.data) as RealtimeEvent;
      this.handleEvent(data);
    } catch (error) {
      console.error('[Realtime] Failed to parse event:', error);
    }
  }

  private onDataChannelError(event: Event): void {
    console.error('[Realtime] Data channel error:', event);
    this.handlers.onError?.(new Error('Data channel error'));
  }

  private handleEvent(event: RealtimeEvent): void {
    switch (event.type) {
      case 'session.created':
        this.sessionId = event.session.id;
        this.handlers.onSessionCreated?.(event.session.id);
        break;

      case 'conversation.item.input_audio_transcription.completed':
        this.handlers.onTranscript?.({
          text: event.transcript,
          isFinal: true,
        });
        break;

      case 'response.created':
        this.handlers.onResponseStart?.();
        break;

      case 'response.text.delta':
        this.handlers.onResponseText?.({
          content: event.delta,
        });
        break;

      case 'response.audio.delta':
        // Audio is handled via WebRTC track, but we can notify
        this.handlers.onResponseAudio?.({
          audio: new ArrayBuffer(0), // Placeholder - actual audio via WebRTC
          format: 'pcm',
          sampleRate: 24000,
          isFinal: false,
        });
        break;

      case 'response.done':
        this.handlers.onResponseComplete?.();
        break;

      case 'error':
        this.handlers.onError?.(new Error(event.error.message));
        break;
    }
  }

  private sendEvent(event: Record<string, unknown>): void {
    if (this.dataChannel?.readyState === 'open') {
      this.dataChannel.send(JSON.stringify(event));
    } else {
      console.warn('[Realtime] Cannot send event - data channel not open');
    }
  }
}

// ===== Singleton Instance =====

let instance: OpenAIRealtimeProvider | null = null;

export function getOpenAIRealtimeProvider(): OpenAIRealtimeProvider {
  if (!instance) {
    instance = new OpenAIRealtimeProvider();
  }
  return instance;
}
