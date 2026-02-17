# Technical Requirements Document: GLM-ASR-Nano Server Integration

**Purpose:** Detailed technical specification for implementing GLM-ASR-Nano-2512 as a self-hosted STT provider in UnaMentis iOS.

**Version:** 2.0
**Date:** February 2026
**Status:** Implementation Complete (iOS client), Server backend updating
**Related:** `GLM_ASR_NANO_2512.md`, `UnaMentis_TDD.md`

---

## Table of Contents

1. [Overview](#1-overview)
2. [System Architecture](#2-system-architecture)
3. [Server Infrastructure](#3-server-infrastructure)
4. [API Specification](#4-api-specification)
5. [iOS Client Implementation](#5-ios-client-implementation)
6. [Audio Pipeline](#6-audio-pipeline)
7. [Error Handling & Resilience](#7-error-handling--resilience)
8. [Monitoring & Observability](#8-monitoring--observability)
9. [Security Considerations](#9-security-considerations)
10. [Testing Strategy](#10-testing-strategy)
11. [Deployment Guide](#11-deployment-guide)
12. [Performance Targets](#12-performance-targets)
13. [Implementation Checklist](#13-implementation-checklist)

---

## 1. Overview

### 1.1 Objective

Implement a self-hosted GLM-ASR-Nano-2512 speech-to-text service that:

1. Integrates seamlessly with UnaMentis's existing `STTServiceProtocol`
2. Provides streaming transcription via WebSocket
3. Achieves latency parity with Deepgram (~300ms)
4. Reduces STT costs to near-zero at scale
5. Supports graceful failover to cloud providers

### 1.2 Scope

| In Scope | Out of Scope |
|----------|--------------|
| Server deployment (vLLM/SGLang) | On-device CoreML implementation |
| WebSocket streaming API | Fine-tuning the model |
| iOS client service implementation | Multi-tenant deployment |
| Health monitoring & failover | Real-time model updates |
| Basic authentication | Advanced user isolation |

### 1.3 Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Latency (p50)** | < 200ms | Time from audio chunk to partial transcript |
| **Latency (p99)** | < 400ms | Worst-case acceptable latency |
| **Accuracy** | ≥ Deepgram | Side-by-side WER comparison |
| **Uptime** | 99.5% | Server availability |
| **Failover Time** | < 2s | Time to switch to backup provider |

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           UnaMentis System                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   iOS App                                    GLM-ASR Server                 │
│   ┌─────────────────────────┐               ┌─────────────────────────────┐│
│   │      AudioEngine        │               │     Inference Server        ││
│   │  ┌─────────────────┐    │               │  ┌─────────────────────┐    ││
│   │  │ AVAudioEngine   │    │               │  │   vLLM / SGLang     │    ││
│   │  │ 16kHz Mono PCM  │    │               │  │   GLM-ASR-Nano      │    ││
│   │  └────────┬────────┘    │               │  │   FP16 / INT8       │    ││
│   │           │             │               │  └──────────┬──────────┘    ││
│   │           ▼             │               │             │               ││
│   │  ┌─────────────────┐    │   WebSocket   │  ┌──────────▼──────────┐    ││
│   │  │ GLMASRSTTService│════╬═══════════════╬══│  Streaming Handler  │    ││
│   │  │                 │    │   (wss://)    │  │  /v1/audio/stream   │    ││
│   │  │ • sendAudio()   │────┼──► PCM ───────┼─►│  • Chunk buffer     │    ││
│   │  │ • receiveText() │◄───┼── JSON ◄──────┼──│  • Inference loop   │    ││
│   │  └─────────────────┘    │               │  │  • Result streaming │    ││
│   │                         │               │  └─────────────────────┘    ││
│   └─────────────────────────┘               └─────────────────────────────┘│
│                                                                             │
│   Fallback Path                                                             │
│   ┌─────────────────────────┐                                              │
│   │   DeepgramSTTService    │◄──── Automatic failover if server unhealthy  │
│   └─────────────────────────┘                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Responsibilities

| Component | Responsibility |
|-----------|---------------|
| **AudioEngine** | Capture 16kHz mono PCM, apply VAD, buffer management |
| **GLMASRSTTService** | WebSocket client, audio streaming, result parsing |
| **Inference Server** | Run GLM-ASR-Nano, process audio chunks, stream results |
| **Streaming Handler** | WebSocket server, audio buffering, batch inference |
| **Health Monitor** | Check server status, trigger failover |

### 2.3 Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Data Flow Sequence                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Audio Capture                                                           │
│     AudioEngine captures 16kHz mono PCM in 100ms chunks (1600 samples)     │
│                                                                             │
│  2. VAD Filtering                                                           │
│     SileroVAD filters silence, only speech chunks sent                     │
│                                                                             │
│  3. WebSocket Send                                                          │
│     GLMASRSTTService sends binary PCM frame:                               │
│     ┌────────────────────────────────────────┐                             │
│     │ [4 bytes: length][N bytes: PCM data]   │                             │
│     └────────────────────────────────────────┘                             │
│                                                                             │
│  4. Server Processing                                                       │
│     • Buffer audio chunks (accumulate 500ms-1s)                            │
│     • Run inference on accumulated audio                                    │
│     • Stream partial results as available                                   │
│                                                                             │
│  5. Result Streaming                                                        │
│     Server sends JSON messages:                                             │
│     ┌────────────────────────────────────────────────────────────────┐     │
│     │ {"type":"partial","text":"Hello","confidence":0.85,"ts":1234}  │     │
│     │ {"type":"final","text":"Hello world","confidence":0.95}        │     │
│     └────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│  6. Client Processing                                                       │
│     GLMASRSTTService parses JSON, emits STTResult via AsyncStream          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Server Infrastructure

### 3.1 Hardware Requirements

#### Minimum (Development/Testing)

| Component | Specification |
|-----------|--------------|
| **GPU** | NVIDIA RTX 3060 12GB or equivalent |
| **VRAM** | 12GB (FP16 model + overhead) |
| **System RAM** | 16GB |
| **Storage** | 50GB SSD |
| **Network** | 100 Mbps symmetric |

#### Recommended (Production)

| Component | Specification |
|-----------|--------------|
| **GPU** | NVIDIA T4 16GB / A10G 24GB / L4 24GB |
| **VRAM** | 16-24GB |
| **System RAM** | 32GB |
| **Storage** | 100GB NVMe SSD |
| **Network** | 1 Gbps symmetric |
| **Redundancy** | 2+ instances behind load balancer |

### 3.2 Software Stack

> **Important (Dec 27, 2025):** Z.AI updated model weights for transformers 5.0.0 and SGLang
> compatibility. SGLang is now the recommended inference backend. vLLM requires transformers
> >= 5.0.0 (dev install). A legacy path using transformers 4.51.3 is available.

#### Option A: SGLang Backend (Recommended)

```yaml
# docker-compose.sglang.yml
version: '3.8'

services:
  glm-asr-server:
    image: lmsysorg/sglang:dev
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    ports:
      - "30000:30000"
    volumes:
      - ./models:/root/.cache/huggingface
    command: >
      python -m sglang.launch_server
      --model zai-org/GLM-ASR-Nano-2512
      --host 0.0.0.0
      --port 30000

  streaming-gateway:
    build: ./gateway
    ports:
      - "8080:8080"
    environment:
      - VLLM_ENDPOINT=http://glm-asr-server:30000
      - WS_PORT=8080
    depends_on:
      - glm-asr-server

  nginx:
    image: nginx:alpine
    ports:
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./certs:/etc/ssl/certs
    depends_on:
      - streaming-gateway
```

#### Option B: vLLM Backend (requires transformers 5.0.0)

```yaml
# docker-compose.yml
version: '3.8'

services:
  glm-asr-server:
    image: vllm/vllm-openai:latest
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - MODEL_NAME=zai-org/GLM-ASR-Nano-2512
      - DTYPE=float16
      - MAX_MODEL_LEN=4096
    ports:
      - "8000:8000"
    volumes:
      - ./models:/root/.cache/huggingface
    command: >
      pip install git+https://github.com/huggingface/transformers &&
      python -m vllm.entrypoints.openai.api_server
      --model ${MODEL_NAME}
      --dtype ${DTYPE}
      --max-model-len ${MAX_MODEL_LEN}
      --host 0.0.0.0
      --port 8000

  streaming-gateway:
    build: ./gateway
    ports:
      - "8080:8080"
    environment:
      - VLLM_ENDPOINT=http://glm-asr-server:8000
      - WS_PORT=8080
    depends_on:
      - glm-asr-server

  nginx:
    image: nginx:alpine
    ports:
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./certs:/etc/ssl/certs
    depends_on:
      - streaming-gateway
```

### 3.3 Streaming Gateway

The streaming gateway bridges WebSocket connections to the vLLM inference server:

```python
# gateway/server.py
import asyncio
import websockets
import numpy as np
from typing import AsyncGenerator
import aiohttp

class GLMASRStreamingGateway:
    def __init__(self, vllm_endpoint: str):
        self.vllm_endpoint = vllm_endpoint
        self.chunk_buffer_ms = 500  # Accumulate 500ms before inference
        self.sample_rate = 16000

    async def handle_connection(self, websocket):
        """Handle a single WebSocket connection."""
        audio_buffer = []
        buffer_samples = 0
        target_samples = int(self.chunk_buffer_ms * self.sample_rate / 1000)

        try:
            async for message in websocket:
                if isinstance(message, bytes):
                    # Decode PCM audio
                    audio_chunk = np.frombuffer(message, dtype=np.int16)
                    audio_buffer.append(audio_chunk)
                    buffer_samples += len(audio_chunk)

                    # Process when buffer is full
                    if buffer_samples >= target_samples:
                        audio_data = np.concatenate(audio_buffer)
                        audio_buffer = []
                        buffer_samples = 0

                        # Run inference and stream results
                        async for result in self.transcribe(audio_data):
                            await websocket.send(result.to_json())

                elif message == "END_STREAM":
                    # Process remaining audio
                    if audio_buffer:
                        audio_data = np.concatenate(audio_buffer)
                        async for result in self.transcribe(audio_data, is_final=True):
                            await websocket.send(result.to_json())
                    break

        except websockets.ConnectionClosed:
            pass

    async def transcribe(
        self,
        audio: np.ndarray,
        is_final: bool = False
    ) -> AsyncGenerator[TranscriptionResult, None]:
        """Run inference on audio chunk."""
        # Convert to format expected by GLM-ASR
        audio_b64 = base64.b64encode(audio.tobytes()).decode()

        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{self.vllm_endpoint}/v1/audio/transcriptions",
                json={
                    "audio": audio_b64,
                    "model": "glm-asr-nano",
                    "stream": True,
                    "language": "auto"
                }
            ) as response:
                async for line in response.content:
                    if line:
                        data = json.loads(line)
                        yield TranscriptionResult(
                            text=data["text"],
                            is_final=is_final or data.get("is_final", False),
                            confidence=data.get("confidence", 0.0),
                            latency_ms=data.get("latency_ms", 0)
                        )

async def main():
    gateway = GLMASRStreamingGateway(
        vllm_endpoint=os.environ.get("VLLM_ENDPOINT", "http://localhost:8000")
    )

    async with websockets.serve(
        gateway.handle_connection,
        "0.0.0.0",
        int(os.environ.get("WS_PORT", 8080))
    ):
        await asyncio.Future()  # Run forever

if __name__ == "__main__":
    asyncio.run(main())
```

---

## 4. API Specification

### 4.1 WebSocket Protocol

#### Connection

```
wss://your-server.com/v1/audio/stream
```

#### Authentication (Optional)

```
wss://your-server.com/v1/audio/stream?token=<jwt_token>
```

### 4.2 Message Types

#### Client → Server

##### Audio Data (Binary)

```
┌────────────────────────────────────────────────────────────────┐
│  Binary WebSocket Frame                                        │
├────────────────────────────────────────────────────────────────┤
│  Format: Raw PCM audio data                                    │
│  Encoding: 16-bit signed integer, little-endian               │
│  Sample Rate: 16000 Hz                                         │
│  Channels: 1 (mono)                                            │
│  Chunk Size: 1600 samples (100ms) recommended                  │
└────────────────────────────────────────────────────────────────┘
```

##### Control Messages (Text/JSON)

```json
// Start streaming session
{
    "type": "start",
    "config": {
        "language": "auto",          // "auto", "zh", "en", "yue"
        "interim_results": true,      // Send partial transcripts
        "punctuate": true,            // Add punctuation
        "profanity_filter": false
    }
}

// End streaming session
{
    "type": "end"
}

// Ping (keepalive)
{
    "type": "ping",
    "timestamp": 1702483200000
}
```

#### Server → Client

##### Transcription Results (Text/JSON)

```json
// Partial/interim result
{
    "type": "partial",
    "text": "Hello how are",
    "confidence": 0.82,
    "timestamp_ms": 1500,
    "words": [
        {"word": "Hello", "start": 0.0, "end": 0.3, "confidence": 0.95},
        {"word": "how", "start": 0.35, "end": 0.5, "confidence": 0.88},
        {"word": "are", "start": 0.55, "end": 0.7, "confidence": 0.76}
    ]
}

// Final result (end of utterance)
{
    "type": "final",
    "text": "Hello, how are you today?",
    "confidence": 0.94,
    "is_end_of_utterance": true,
    "duration_ms": 2100,
    "words": [
        {"word": "Hello", "start": 0.0, "end": 0.3, "confidence": 0.95},
        {"word": "how", "start": 0.35, "end": 0.5, "confidence": 0.92},
        {"word": "are", "start": 0.55, "end": 0.7, "confidence": 0.91},
        {"word": "you", "start": 0.75, "end": 0.9, "confidence": 0.93},
        {"word": "today", "start": 0.95, "end": 1.3, "confidence": 0.96}
    ]
}

// Pong (response to ping)
{
    "type": "pong",
    "timestamp": 1702483200000,
    "server_time": 1702483200005
}

// Error
{
    "type": "error",
    "code": "AUDIO_FORMAT_ERROR",
    "message": "Invalid audio format. Expected 16kHz mono PCM.",
    "recoverable": true
}
```

### 4.3 Error Codes

| Code | Description | Recoverable |
|------|-------------|-------------|
| `AUDIO_FORMAT_ERROR` | Invalid audio format | Yes |
| `BUFFER_OVERFLOW` | Audio buffer exceeded limit | Yes |
| `MODEL_UNAVAILABLE` | Inference server not ready | No |
| `RATE_LIMIT_EXCEEDED` | Too many requests | Yes |
| `AUTHENTICATION_FAILED` | Invalid token | No |
| `INTERNAL_ERROR` | Server error | No |

---

## 5. iOS Client Implementation

### 5.1 GLMASRSTTService

```swift
// UnaMentis/Services/STT/GLMASRSTTService.swift

import Foundation
import AVFoundation

/// GLM-ASR-Nano streaming STT service via WebSocket
public actor GLMASRSTTService: STTServiceProtocol {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public let serverURL: URL
        public let authToken: String?
        public let language: String
        public let interimResults: Bool
        public let punctuate: Bool
        public let reconnectAttempts: Int
        public let reconnectDelayMs: Int

        public static let `default` = Configuration(
            serverURL: URL(string: "wss://your-server.com/v1/audio/stream")!,
            authToken: nil,
            language: "auto",
            interimResults: true,
            punctuate: true,
            reconnectAttempts: 3,
            reconnectDelayMs: 1000
        )
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let telemetry: TelemetryEngine
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var resultContinuation: AsyncStream<STTResult>.Continuation?
    private var isStreaming = false
    private var sessionStartTime: Date?
    private var audioBytesSent: Int = 0

    // MARK: - STTServiceProtocol Properties

    public private(set) var metrics: STTMetrics = STTMetrics()
    public let costPerHour: Decimal = 0.00  // Self-hosted = $0

    // MARK: - Initialization

    public init(
        configuration: Configuration = .default,
        telemetry: TelemetryEngine
    ) {
        self.configuration = configuration
        self.telemetry = telemetry
        self.urlSession = URLSession(configuration: .default)
    }

    // MARK: - STTServiceProtocol Methods

    public func startStreaming(
        audioFormat: AVAudioFormat
    ) async throws -> AsyncStream<STTResult> {
        guard !isStreaming else {
            throw STTError.alreadyStreaming
        }

        // Validate audio format
        guard audioFormat.sampleRate == 16000,
              audioFormat.channelCount == 1 else {
            throw STTError.invalidAudioFormat(
                "Expected 16kHz mono, got \(audioFormat.sampleRate)Hz \(audioFormat.channelCount)ch"
            )
        }

        // Create WebSocket connection
        var request = URLRequest(url: configuration.serverURL)
        if let token = configuration.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        webSocket = urlSession.webSocketTask(with: request)
        webSocket?.resume()

        // Send start configuration
        let startMessage = StartMessage(
            type: "start",
            config: .init(
                language: configuration.language,
                interimResults: configuration.interimResults,
                punctuate: configuration.punctuate
            )
        )
        try await sendJSON(startMessage)

        isStreaming = true
        sessionStartTime = Date()
        audioBytesSent = 0

        await telemetry.recordEvent(.sttStreamingStarted(provider: "glm-asr-nano"))

        // Create result stream
        return AsyncStream { continuation in
            self.resultContinuation = continuation

            // Start receiving messages
            Task {
                await self.receiveLoop()
            }

            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.cleanup()
                }
            }
        }
    }

    public func sendAudio(_ buffer: AVAudioPCMBuffer) async {
        guard isStreaming, let webSocket = webSocket else { return }

        // Convert to Int16 PCM
        guard let floatData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        var int16Data = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, floatData[i]))
            int16Data[i] = Int16(sample * Float(Int16.max))
        }

        // Send as binary data
        let data = int16Data.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        do {
            try await webSocket.send(.data(data))
            audioBytesSent += data.count
        } catch {
            await handleError(error)
        }
    }

    public func stopStreaming() async -> STTResult? {
        guard isStreaming else { return nil }

        // Send end message
        try? await sendJSON(["type": "end"])

        // Wait for final result with timeout
        let finalResult = await waitForFinalResult(timeout: 2.0)

        await cleanup()
        await recordSessionMetrics()

        return finalResult
    }

    public func cancelStreaming() async {
        await cleanup()
    }

    // MARK: - Private Methods

    private func receiveLoop() async {
        guard let webSocket = webSocket else { return }

        while isStreaming {
            do {
                let message = try await webSocket.receive()

                switch message {
                case .string(let text):
                    await handleTextMessage(text)
                case .data(let data):
                    await handleBinaryMessage(data)
                @unknown default:
                    break
                }
            } catch {
                if isStreaming {
                    await handleError(error)
                }
                break
            }
        }
    }

    private func handleTextMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "partial":
            let result = parseTranscriptionResult(json, isFinal: false)
            resultContinuation?.yield(result)
            await telemetry.recordEvent(.sttPartialResult(
                text: result.text,
                latencyMs: result.latencyMs
            ))

        case "final":
            let result = parseTranscriptionResult(json, isFinal: true)
            resultContinuation?.yield(result)
            await telemetry.recordEvent(.sttFinalResult(
                text: result.text,
                confidence: result.confidence,
                latencyMs: result.latencyMs
            ))

        case "error":
            let code = json["code"] as? String ?? "UNKNOWN"
            let message = json["message"] as? String ?? "Unknown error"
            let recoverable = json["recoverable"] as? Bool ?? false

            await telemetry.recordEvent(.sttError(
                provider: "glm-asr-nano",
                error: "\(code): \(message)"
            ))

            if !recoverable {
                await cleanup()
            }

        case "pong":
            // Keepalive acknowledged
            break

        default:
            break
        }
    }

    private func handleBinaryMessage(_ data: Data) async {
        // Server shouldn't send binary data, but handle gracefully
    }

    private func parseTranscriptionResult(
        _ json: [String: Any],
        isFinal: Bool
    ) -> STTResult {
        let text = json["text"] as? String ?? ""
        let confidence = json["confidence"] as? Float ?? 0.0
        let timestampMs = json["timestamp_ms"] as? Int ?? 0
        let isEndOfUtterance = json["is_end_of_utterance"] as? Bool ?? isFinal

        // Parse word timestamps if available
        var words: [STTWordTimestamp] = []
        if let wordArray = json["words"] as? [[String: Any]] {
            words = wordArray.compactMap { wordJson in
                guard let word = wordJson["word"] as? String,
                      let start = wordJson["start"] as? Double,
                      let end = wordJson["end"] as? Double else {
                    return nil
                }
                return STTWordTimestamp(
                    word: word,
                    startTime: start,
                    endTime: end,
                    confidence: wordJson["confidence"] as? Float ?? 0.0
                )
            }
        }

        // Calculate latency from session start
        let latencyMs: Int
        if let startTime = sessionStartTime {
            latencyMs = Int(Date().timeIntervalSince(startTime) * 1000) - timestampMs
        } else {
            latencyMs = 0
        }

        return STTResult(
            text: text,
            isFinal: isFinal,
            isEndOfUtterance: isEndOfUtterance,
            confidence: confidence,
            latencyMs: latencyMs,
            words: words.isEmpty ? nil : words
        )
    }

    private func waitForFinalResult(timeout: TimeInterval) async -> STTResult? {
        // Implementation depends on your result handling pattern
        // Could use a continuation or simply return the last final result
        return nil
    }

    private func handleError(_ error: Error) async {
        await telemetry.recordEvent(.sttError(
            provider: "glm-asr-nano",
            error: error.localizedDescription
        ))

        // Attempt reconnection if configured
        if configuration.reconnectAttempts > 0 {
            await attemptReconnection()
        }
    }

    private func attemptReconnection() async {
        // Reconnection logic with exponential backoff
        for attempt in 1...configuration.reconnectAttempts {
            let delay = configuration.reconnectDelayMs * attempt
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)

            do {
                var request = URLRequest(url: configuration.serverURL)
                if let token = configuration.authToken {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                webSocket = urlSession.webSocketTask(with: request)
                webSocket?.resume()

                await telemetry.recordEvent(.sttReconnected(
                    provider: "glm-asr-nano",
                    attempt: attempt
                ))
                return
            } catch {
                continue
            }
        }

        // All reconnection attempts failed
        await cleanup()
    }

    private func cleanup() async {
        isStreaming = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        resultContinuation?.finish()
        resultContinuation = nil
    }

    private func recordSessionMetrics() async {
        guard let startTime = sessionStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        let audioDurationMs = audioBytesSent / 32  // 16kHz * 2 bytes = 32 bytes/ms

        metrics = STTMetrics(
            sessionDurationMs: Int(duration * 1000),
            audioDurationMs: audioDurationMs,
            latencyP50Ms: 150,  // Would calculate from recorded latencies
            latencyP99Ms: 350,
            totalTranscripts: 0  // Would count from results
        )
    }

    private func sendJSON<T: Encodable>(_ value: T) async throws {
        let data = try JSONEncoder().encode(value)
        let string = String(data: data, encoding: .utf8)!
        try await webSocket?.send(.string(string))
    }
}

// MARK: - Supporting Types

extension GLMASRSTTService {
    struct StartMessage: Encodable {
        let type: String
        let config: Config

        struct Config: Encodable {
            let language: String
            let interimResults: Bool
            let punctuate: Bool

            enum CodingKeys: String, CodingKey {
                case language
                case interimResults = "interim_results"
                case punctuate
            }
        }
    }
}

public enum STTError: Error {
    case alreadyStreaming
    case notStreaming
    case invalidAudioFormat(String)
    case connectionFailed(Error)
    case serverError(String)
}
```

### 5.2 Health Check & Failover

```swift
// UnaMentis/Services/STT/GLMASRHealthMonitor.swift

import Foundation

/// Monitors GLM-ASR server health and triggers failover
public actor GLMASRHealthMonitor {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public let healthEndpoint: URL
        public let checkIntervalSeconds: Int
        public let unhealthyThreshold: Int  // Consecutive failures before unhealthy
        public let healthyThreshold: Int    // Consecutive successes before healthy

        public static let `default` = Configuration(
            healthEndpoint: URL(string: "https://your-server.com/health")!,
            checkIntervalSeconds: 30,
            unhealthyThreshold: 3,
            healthyThreshold: 2
        )
    }

    // MARK: - State

    public enum HealthStatus: Sendable {
        case healthy
        case degraded
        case unhealthy
    }

    private let configuration: Configuration
    private var status: HealthStatus = .healthy
    private var consecutiveFailures: Int = 0
    private var consecutiveSuccesses: Int = 0
    private var monitorTask: Task<Void, Never>?
    private var statusContinuation: AsyncStream<HealthStatus>.Continuation?

    // MARK: - Public Interface

    public var currentStatus: HealthStatus { status }

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func startMonitoring() -> AsyncStream<HealthStatus> {
        return AsyncStream { continuation in
            self.statusContinuation = continuation

            self.monitorTask = Task {
                await self.monitorLoop()
            }

            continuation.onTermination = { @Sendable _ in
                Task { await self.stopMonitoring() }
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        statusContinuation?.finish()
        statusContinuation = nil
    }

    public func checkHealth() async -> HealthStatus {
        do {
            let (_, response) = try await URLSession.shared.data(
                from: configuration.healthEndpoint
            )

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return await recordFailure()
            }

            return await recordSuccess()
        } catch {
            return await recordFailure()
        }
    }

    // MARK: - Private Methods

    private func monitorLoop() async {
        while !Task.isCancelled {
            let newStatus = await checkHealth()

            if newStatus != status {
                status = newStatus
                statusContinuation?.yield(newStatus)
            }

            try? await Task.sleep(
                nanoseconds: UInt64(configuration.checkIntervalSeconds) * 1_000_000_000
            )
        }
    }

    private func recordSuccess() -> HealthStatus {
        consecutiveSuccesses += 1
        consecutiveFailures = 0

        if consecutiveSuccesses >= configuration.healthyThreshold {
            return .healthy
        } else if status == .unhealthy {
            return .degraded
        }
        return status
    }

    private func recordFailure() -> HealthStatus {
        consecutiveFailures += 1
        consecutiveSuccesses = 0

        if consecutiveFailures >= configuration.unhealthyThreshold {
            return .unhealthy
        } else if status == .healthy {
            return .degraded
        }
        return status
    }
}
```

### 5.3 STT Provider Router

```swift
// UnaMentis/Services/STT/STTProviderRouter.swift

import Foundation
import AVFoundation

/// Routes STT requests to appropriate provider with automatic failover
public actor STTProviderRouter: STTServiceProtocol {

    // MARK: - Providers

    private let glmASRService: GLMASRSTTService
    private let deepgramService: DeepgramSTTService
    private let healthMonitor: GLMASRHealthMonitor

    private var activeProvider: STTServiceProtocol
    private var healthStatus: GLMASRHealthMonitor.HealthStatus = .healthy

    // MARK: - STTServiceProtocol Properties

    public var metrics: STTMetrics {
        get async { await activeProvider.metrics }
    }

    public var costPerHour: Decimal {
        get async { await activeProvider.costPerHour }
    }

    // MARK: - Initialization

    public init(
        glmASRService: GLMASRSTTService,
        deepgramService: DeepgramSTTService,
        healthMonitor: GLMASRHealthMonitor
    ) {
        self.glmASRService = glmASRService
        self.deepgramService = deepgramService
        self.healthMonitor = healthMonitor
        self.activeProvider = glmASRService

        // Start health monitoring
        Task {
            await self.startHealthMonitoring()
        }
    }

    // MARK: - STTServiceProtocol Methods

    public func startStreaming(
        audioFormat: AVAudioFormat
    ) async throws -> AsyncStream<STTResult> {
        // Select provider based on health
        activeProvider = selectProvider()

        return try await activeProvider.startStreaming(audioFormat: audioFormat)
    }

    public func sendAudio(_ buffer: AVAudioPCMBuffer) async {
        await activeProvider.sendAudio(buffer)
    }

    public func stopStreaming() async -> STTResult? {
        return await activeProvider.stopStreaming()
    }

    public func cancelStreaming() async {
        await activeProvider.cancelStreaming()
    }

    // MARK: - Private Methods

    private func startHealthMonitoring() async {
        let healthStream = await healthMonitor.startMonitoring()

        for await status in healthStream {
            healthStatus = status

            // If current provider is GLM-ASR and it becomes unhealthy, switch
            if status == .unhealthy && activeProvider is GLMASRSTTService {
                await activeProvider.cancelStreaming()
                activeProvider = deepgramService
            }
        }
    }

    private func selectProvider() -> STTServiceProtocol {
        switch healthStatus {
        case .healthy:
            return glmASRService
        case .degraded:
            // Could implement more sophisticated logic here
            return glmASRService
        case .unhealthy:
            return deepgramService
        }
    }
}
```

---

## 6. Audio Pipeline

### 6.1 Audio Format Requirements

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Audio Format Specification                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Required Format:                                                           │
│  ├─ Sample Rate: 16,000 Hz (16 kHz)                                        │
│  ├─ Channels: 1 (Mono)                                                      │
│  ├─ Bit Depth: 16-bit signed integer (Int16)                               │
│  ├─ Byte Order: Little-endian                                              │
│  └─ Encoding: Linear PCM (uncompressed)                                    │
│                                                                             │
│  Chunk Configuration:                                                       │
│  ├─ Recommended Chunk Size: 100ms (1,600 samples = 3,200 bytes)            │
│  ├─ Minimum Chunk Size: 20ms (320 samples = 640 bytes)                     │
│  └─ Maximum Chunk Size: 500ms (8,000 samples = 16,000 bytes)               │
│                                                                             │
│  Buffer Math:                                                               │
│  ├─ Bytes per sample: 2 (Int16)                                            │
│  ├─ Bytes per second: 32,000 (16,000 samples × 2 bytes)                    │
│  ├─ Bytes per 100ms: 3,200                                                 │
│  └─ Bytes per minute: 1,920,000 (~1.83 MB)                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Audio Conversion

```swift
extension AVAudioPCMBuffer {
    /// Convert Float32 audio buffer to Int16 PCM data for GLM-ASR
    func toInt16PCMData() -> Data? {
        guard let floatData = floatChannelData?[0] else { return nil }

        let frameCount = Int(frameLength)
        var int16Samples = [Int16](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            // Clamp to [-1.0, 1.0] and convert to Int16 range
            let sample = max(-1.0, min(1.0, floatData[i]))
            int16Samples[i] = Int16(sample * Float(Int16.max))
        }

        return int16Samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}
```

### 6.3 VAD Integration

```swift
// Integrate with existing SileroVAD to filter silence
class GLMASRAudioPipeline {
    private let vadService: SileroVADService
    private let sttService: GLMASRSTTService

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        // Check VAD first
        let vadResult = await vadService.processBuffer(buffer)

        // Only send speech, not silence
        if vadResult.isSpeech {
            await sttService.sendAudio(buffer)
        }
    }
}
```

---

## 7. Error Handling & Resilience

### 7.1 Error Categories

| Category | Examples | Handling Strategy |
|----------|----------|-------------------|
| **Transient** | Network timeout, 503 | Retry with backoff |
| **Recoverable** | Buffer overflow, format error | Log, continue |
| **Fatal** | Auth failed, server down | Failover to Deepgram |
| **Client** | Invalid config | Throw, surface to user |

### 7.2 Retry Strategy

```swift
struct RetryConfiguration {
    let maxAttempts: Int = 3
    let initialDelayMs: Int = 100
    let maxDelayMs: Int = 5000
    let backoffMultiplier: Double = 2.0

    func delay(for attempt: Int) -> Int {
        let delay = Double(initialDelayMs) * pow(backoffMultiplier, Double(attempt - 1))
        return min(Int(delay), maxDelayMs)
    }
}
```

### 7.3 Circuit Breaker

```swift
actor CircuitBreaker {
    enum State {
        case closed      // Normal operation
        case open        // Failing, reject requests
        case halfOpen    // Testing recovery
    }

    private var state: State = .closed
    private var failureCount: Int = 0
    private var lastFailureTime: Date?

    let failureThreshold: Int = 5
    let resetTimeout: TimeInterval = 30

    func recordSuccess() {
        failureCount = 0
        state = .closed
    }

    func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()

        if failureCount >= failureThreshold {
            state = .open
        }
    }

    func canAttempt() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) > resetTimeout {
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }
}
```

---

## 8. Monitoring & Observability

### 8.1 Metrics to Track

| Metric | Type | Description |
|--------|------|-------------|
| `glm_asr_requests_total` | Counter | Total transcription requests |
| `glm_asr_latency_ms` | Histogram | Request latency distribution |
| `glm_asr_audio_duration_ms` | Histogram | Audio processed per request |
| `glm_asr_errors_total` | Counter | Errors by type |
| `glm_asr_failovers_total` | Counter | Failovers to backup provider |
| `glm_asr_active_sessions` | Gauge | Current streaming sessions |

### 8.2 Telemetry Events

```swift
extension TelemetryEvent {
    // GLM-ASR specific events
    static func glmAsrSessionStarted() -> TelemetryEvent {
        .init(name: "glm_asr_session_started", properties: [:])
    }

    static func glmAsrLatency(ms: Int, type: String) -> TelemetryEvent {
        .init(name: "glm_asr_latency", properties: [
            "latency_ms": ms,
            "result_type": type
        ])
    }

    static func glmAsrFailover(reason: String) -> TelemetryEvent {
        .init(name: "glm_asr_failover", properties: [
            "reason": reason,
            "fallback_provider": "deepgram"
        ])
    }
}
```

### 8.3 Server-Side Monitoring

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'glm-asr-server'
    static_configs:
      - targets: ['localhost:8000']
    metrics_path: /metrics

# Grafana dashboard queries
- name: "Request Latency P99"
  query: histogram_quantile(0.99, rate(glm_asr_latency_ms_bucket[5m]))

- name: "Error Rate"
  query: rate(glm_asr_errors_total[5m]) / rate(glm_asr_requests_total[5m])

- name: "GPU Utilization"
  query: nvidia_smi_utilization_gpu
```

---

## 9. Security Considerations

### 9.1 Authentication

```swift
// JWT token-based authentication
struct GLMASRAuthConfig {
    let tokenEndpoint: URL
    let clientId: String
    let clientSecret: String  // Stored in Keychain

    func getAccessToken() async throws -> String {
        // Implement OAuth2 client credentials flow
        // Token should be refreshed before expiry
    }
}
```

### 9.2 Transport Security

- **TLS 1.3** required for all WebSocket connections
- **Certificate pinning** recommended for production
- **No sensitive data in URLs** (use headers for auth)

### 9.3 Data Privacy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Data Privacy Measures                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Audio Data:                                                                │
│  ├─ Processed in-memory only (not persisted on server)                     │
│  ├─ Deleted immediately after transcription                                │
│  └─ Never logged or stored for training                                    │
│                                                                             │
│  Transcripts:                                                               │
│  ├─ Returned to client only                                                │
│  ├─ Not stored on server                                                   │
│  └─ Client-side storage follows user preferences                           │
│                                                                             │
│  Logs:                                                                      │
│  ├─ Request metadata only (no audio/transcript content)                    │
│  ├─ Latency, error codes, session IDs                                      │
│  └─ Retained for 30 days                                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Testing Strategy

### 10.1 Unit Tests

```swift
// UnaMentisTests/Unit/GLMASRSTTServiceTests.swift

final class GLMASRSTTServiceTests: XCTestCase {

    func testStartStreamingValidatesAudioFormat() async throws {
        let service = GLMASRSTTService(
            configuration: .mock,
            telemetry: MockTelemetry()
        )

        // Valid format should succeed
        let validFormat = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        )!
        _ = try await service.startStreaming(audioFormat: validFormat)
        await service.cancelStreaming()

        // Invalid format should throw
        let invalidFormat = AVAudioFormat(
            standardFormatWithSampleRate: 44100,
            channels: 2
        )!
        do {
            _ = try await service.startStreaming(audioFormat: invalidFormat)
            XCTFail("Should throw for invalid format")
        } catch STTError.invalidAudioFormat {
            // Expected
        }
    }

    func testAudioBufferConversion() {
        let buffer = createTestBuffer(samples: 1600)
        let data = buffer.toInt16PCMData()

        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 3200)  // 1600 samples × 2 bytes
    }

    func testParseTranscriptionResult() async {
        let json: [String: Any] = [
            "type": "final",
            "text": "Hello world",
            "confidence": 0.95,
            "is_end_of_utterance": true
        ]

        let service = GLMASRSTTService(
            configuration: .mock,
            telemetry: MockTelemetry()
        )

        // Test parsing logic via internal method or integration
    }
}
```

### 10.2 Integration Tests

```swift
// UnaMentisTests/Integration/GLMASRIntegrationTests.swift

final class GLMASRIntegrationTests: XCTestCase {

    var service: GLMASRSTTService!

    override func setUp() async throws {
        // Requires running GLM-ASR server
        guard ProcessInfo.processInfo.environment["GLM_ASR_SERVER_URL"] != nil else {
            throw XCTSkip("GLM-ASR server not available")
        }

        service = GLMASRSTTService(
            configuration: .init(
                serverURL: URL(string: ProcessInfo.processInfo.environment["GLM_ASR_SERVER_URL"]!)!,
                authToken: nil,
                language: "en",
                interimResults: true,
                punctuate: true,
                reconnectAttempts: 1,
                reconnectDelayMs: 100
            ),
            telemetry: TelemetryEngine()
        )
    }

    func testEndToEndTranscription() async throws {
        let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        )!

        // Load test audio file
        let testAudioURL = Bundle(for: type(of: self))
            .url(forResource: "hello_world", withExtension: "wav")!
        let audioFile = try AVAudioFile(forReading: testAudioURL)

        // Start streaming
        let resultStream = try await service.startStreaming(audioFormat: audioFormat)

        // Send audio in chunks
        let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: 1600
        )!

        while audioFile.framePosition < audioFile.length {
            try audioFile.read(into: buffer)
            await service.sendAudio(buffer)
        }

        // Get final result
        let result = await service.stopStreaming()

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.text.lowercased().contains("hello"))
    }
}
```

### 10.3 Load Tests

```python
# tests/load/glm_asr_load_test.py
import asyncio
import websockets
import time
import statistics

async def run_load_test(
    server_url: str,
    num_connections: int,
    duration_seconds: int
):
    """Simulate multiple concurrent streaming sessions."""

    results = []

    async def simulate_session(session_id: int):
        latencies = []
        start_time = time.time()

        async with websockets.connect(server_url) as ws:
            # Send start message
            await ws.send('{"type":"start","config":{"language":"en"}}')

            # Simulate audio streaming
            while time.time() - start_time < duration_seconds:
                # Send 100ms of audio
                audio_chunk = generate_test_audio(100)
                send_time = time.time()
                await ws.send(audio_chunk)

                # Receive result
                response = await ws.recv()
                receive_time = time.time()

                latencies.append((receive_time - send_time) * 1000)

            await ws.send('{"type":"end"}')

        return {
            "session_id": session_id,
            "latency_p50": statistics.median(latencies),
            "latency_p99": statistics.quantiles(latencies, n=100)[98],
            "num_results": len(latencies)
        }

    # Run concurrent sessions
    tasks = [simulate_session(i) for i in range(num_connections)]
    results = await asyncio.gather(*tasks)

    # Aggregate results
    all_p50 = [r["latency_p50"] for r in results]
    all_p99 = [r["latency_p99"] for r in results]

    print(f"Connections: {num_connections}")
    print(f"Overall P50 latency: {statistics.median(all_p50):.1f}ms")
    print(f"Overall P99 latency: {statistics.median(all_p99):.1f}ms")

if __name__ == "__main__":
    asyncio.run(run_load_test(
        server_url="wss://localhost:8080/v1/audio/stream",
        num_connections=50,
        duration_seconds=60
    ))
```

---

## 11. Deployment Guide

### 11.1 Quick Start (Development)

```bash
# 1. Clone server repository
git clone https://github.com/your-org/glm-asr-server.git
cd glm-asr-server

# 2. Start with Docker Compose
docker-compose up -d

# 3. Verify server is running
curl http://localhost:8000/health

# 4. Test WebSocket connection
wscat -c ws://localhost:8080/v1/audio/stream
```

### 11.2 Production Deployment (AWS)

```bash
# 1. Launch EC2 instance
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type g5.xlarge \
  --key-name your-key \
  --security-group-ids sg-12345678

# 2. Install NVIDIA drivers and Docker
sudo apt-get update
sudo apt-get install -y nvidia-driver-535 docker.io nvidia-container-toolkit

# 3. Pull and run container
docker pull your-registry/glm-asr-server:latest
docker run -d \
  --gpus all \
  -p 8080:8080 \
  -e MODEL_NAME=zai-org/GLM-ASR-Nano-2512 \
  your-registry/glm-asr-server:latest

# 4. Configure load balancer
aws elbv2 create-target-group \
  --name glm-asr-targets \
  --protocol HTTP \
  --port 8080 \
  --vpc-id vpc-12345678 \
  --health-check-path /health
```

### 11.3 Kubernetes Deployment

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: glm-asr-server
spec:
  replicas: 2
  selector:
    matchLabels:
      app: glm-asr-server
  template:
    metadata:
      labels:
        app: glm-asr-server
    spec:
      containers:
      - name: glm-asr
        image: your-registry/glm-asr-server:latest
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "16Gi"
          requests:
            nvidia.com/gpu: 1
            memory: "8Gi"
        ports:
        - containerPort: 8080
        env:
        - name: MODEL_NAME
          value: "zai-org/GLM-ASR-Nano-2512"
        - name: DTYPE
          value: "float16"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: glm-asr-service
spec:
  selector:
    app: glm-asr-server
  ports:
  - port: 8080
    targetPort: 8080
  type: LoadBalancer
```

---

## 12. Performance Targets

### 12.1 Latency Requirements

| Metric | Target | Acceptable | Degraded |
|--------|--------|------------|----------|
| **TTFB (Time to First Byte)** | < 150ms | < 250ms | < 400ms |
| **Partial Result Latency** | < 200ms | < 350ms | < 500ms |
| **Final Result Latency** | < 300ms | < 500ms | < 800ms |
| **End-to-End (audio → text)** | < 350ms | < 600ms | < 1000ms |

### 12.2 Throughput Requirements

| Metric | Target |
|--------|--------|
| **Concurrent Sessions per GPU (T4)** | 20-30 |
| **Audio Processing Rate** | Real-time (1x) minimum |
| **Peak Throughput** | 50 concurrent sessions |

### 12.3 Reliability Requirements

| Metric | Target |
|--------|--------|
| **Uptime** | 99.5% |
| **Error Rate** | < 0.1% |
| **Failover Time** | < 2 seconds |
| **Recovery Time** | < 30 seconds |

---

## 13. Implementation Checklist

### Phase 1: Server Setup

- [ ] Set up GPU server (RunPod/AWS/GCP)
- [ ] Install NVIDIA drivers and container runtime
- [ ] Deploy vLLM with GLM-ASR-Nano model
- [ ] Implement streaming WebSocket gateway
- [ ] Configure TLS/SSL certificates
- [ ] Set up health check endpoint
- [ ] Deploy monitoring (Prometheus/Grafana)

### Phase 2: iOS Client

- [ ] Create `GLMASRSTTService` implementing `STTServiceProtocol`
- [ ] Implement WebSocket connection management
- [ ] Add audio format conversion (Float32 → Int16)
- [ ] Implement result parsing and streaming
- [ ] Add reconnection logic with backoff
- [ ] Create `GLMASRHealthMonitor`
- [ ] Implement `STTProviderRouter` for failover

### Phase 3: Integration

- [ ] Register GLM-ASR endpoint in Patch Panel
- [ ] Add configuration in Settings UI
- [ ] Implement A/B testing framework
- [ ] Add telemetry events
- [ ] Update cost tracking (show $0 for self-hosted)

### Phase 4: Testing

- [ ] Unit tests for client service
- [ ] Integration tests against server
- [ ] Load testing (50 concurrent sessions)
- [ ] Latency benchmarking vs Deepgram
- [ ] Accuracy comparison (WER testing)
- [ ] Failover testing

### Phase 5: Production

- [ ] Deploy to production infrastructure
- [ ] Configure alerting
- [ ] Document runbooks
- [ ] Train team on operations
- [ ] Gradual rollout (10% → 50% → 100%)

---

**Document History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | December 2025 | Claude | Initial TRD |
| 2.0 | February 2026 | Claude | Added SGLang as recommended backend, added transformers 5.0.0 requirement, updated Docker configs |
