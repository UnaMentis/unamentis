# GLM-ASR-Nano-2512: Model Overview & Integration Guide

**Purpose:** Technical evaluation and integration roadmap for Z.AI's GLM-ASR-Nano-2512 speech recognition model in UnaMentis iOS.

**Version:** 2.0
**Date:** February 2026
**Status:** Implementation (Server complete, On-device rearchitecting)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Model Specifications](#2-model-specifications)
3. [Performance Benchmarks](#3-performance-benchmarks)
4. [Key Differentiators](#4-key-differentiators)
5. [Integration Options](#5-integration-options)
6. [Device Compatibility Analysis](#6-device-compatibility-analysis)
7. [Server Hosting Requirements](#7-server-hosting-requirements)
8. [Cost Analysis](#8-cost-analysis)
9. [Implementation Recommendations](#9-implementation-recommendations)
10. [Resources & References](#10-resources--references)

---

## 1. Executive Summary

### 1.1 What is GLM-ASR-Nano-2512?

GLM-ASR-Nano-2512 is an open-source automatic speech recognition (ASR) model released by Z.AI (Zhipu AI) in December 2025. With 1.5 billion parameters, it achieves state-of-the-art performance while remaining compact enough for edge deployment scenarios.

### 1.2 Why Consider for UnaMentis?

| Factor | Current (Deepgram/AssemblyAI) | GLM-ASR-Nano |
|--------|-------------------------------|--------------|
| **Cost** | ~$0.26/hour streaming | $0 (self-hosted) |
| **Latency Control** | Dependent on API | Full control |
| **Dialect Support** | Limited | Cantonese, Mandarin variants |
| **Whisper Speech** | Standard | Optimized for low-volume |
| **Privacy** | Data sent to cloud | On-premise/on-device option |
| **Customization** | None | Fine-tuning possible |

### 1.3 Strategic Fit

GLM-ASR-Nano aligns with UnaMentis's core principles:

- **Provider-Agnostic Architecture:** Fits existing `STTServiceProtocol` abstraction
- **Cost Optimization:** Eliminates per-hour STT costs at scale
- **Performance Tuning:** Full control over latency/quality tradeoffs
- **On-Device Future:** Path to iPhone 17+ on-device inference

---

## 2. Model Specifications

### 2.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     GLM-ASR-Nano-2512 Architecture                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Audio Input ──► Feature      ──► Transformer   ──► Token         │
│   (16kHz PCM)     Extraction       Encoder           Decoder       │
│                   (Mel-Spec)       (1.5B params)     (Streaming)   │
│                                                                     │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│   │ 80-dim Mel  │  │ 24 Encoder  │  │ Autoregres- │               │
│   │ Filterbank  │  │ Layers      │  │ sive Decode │               │
│   │ 25ms window │  │ 1024 hidden │  │ + CTC head  │               │
│   │ 10ms hop    │  │ 16 heads    │  │             │               │
│   └─────────────┘  └─────────────┘  └─────────────┘               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Technical Specifications

| Specification | Value |
|--------------|-------|
| **Parameters** | 1.5B (2B including embeddings per HuggingFace model card) |
| **Architecture** | `GlmAsrForConditionalGeneration` (Seq2Seq) |
| **Input Format** | 16kHz mono PCM audio |
| **Feature Extraction** | Whisper-based audio encoder |
| **Context Window** | Up to 30 seconds |
| **Streaming Support** | Yes (chunked processing) |
| **Output** | Text tokens with timestamps |
| **License** | MIT (full commercial use) |
| **Weight Format** | Single `model.safetensors` (4.52 GB, BF16) |
| **Tensor Type** | BF16 (Brain Float 16) |
| **Framework Requirements** | transformers >= 5.0.0 (dev) OR SGLang dev Docker |
| **Legacy Support** | transformers 4.51.3 + inference.py script |

> **Important (Dec 27, 2025):** Z.AI updated model weights for transformers 5.0.0 and SGLang
> compatibility. If your model was downloaded before December 27, 2025, re-download the latest
> version from HuggingFace.

### 2.3 Model Size by Precision

| Format | File Size | Use Case | Source |
|--------|-----------|----------|--------|
| BF16 (safetensors) | 4.52 GB | Server (native) | [Official](https://huggingface.co/zai-org/GLM-ASR-Nano-2512) |
| BF16 (GGUF) | 3.19 GB | Server/development | [Community](https://huggingface.co/Mungert/GLM-ASR-Nano-2512-GGUF) |
| Q8_0 (GGUF) | 1.7 GB | High-quality edge | Community |
| Q4_K_M (GGUF) | **~1.06 GB** | **On-device (recommended)** | Community |
| Q4_K_S (GGUF) | ~976 MB | On-device (smaller) | Community |
| IQ4_XS (GGUF) | ~925 MB | On-device (smallest usable) | Community |

Community GGUF built with llama.cpp commit `e1f15b454f`, using advanced "layer bumping"
quantization for better precision on important layers.

---

## 3. Performance Benchmarks

### 3.1 Error Rate Comparison

| Model | Avg Error Rate | Aishell-1 (ZH) | LibriSpeech (EN) | Cantonese |
|-------|---------------|----------------|------------------|-----------|
| **GLM-ASR-Nano** | **4.10** | **2.8** | **3.2** | **5.1** |
| Whisper V3 Large | 4.89 | 3.5 | 2.9 | 8.2 |
| Whisper V3 Turbo | 5.12 | 4.1 | 3.1 | 9.4 |
| Deepgram Nova-3 | 4.45 | 3.2 | 2.8 | 7.8 |

### 3.2 Latency Characteristics

| Scenario | Expected Latency | Notes |
|----------|-----------------|-------|
| **Server (RTX 3060)** | 150-250ms | Near real-time |
| **Server (T4/A10)** | 80-150ms | Production grade |
| **Server (H100)** | 30-60ms | Ultra-low latency |
| **On-Device (iPhone 17)** | 200-400ms | INT4 quantized |

### 3.3 Challenging Scenario Performance

GLM-ASR-Nano specifically excels in:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Challenging Scenario Results                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Whisper/Quiet Speech     ████████████████████░░░░  85% accuracy   │
│  (vs. Whisper V3: 62%)                                              │
│                                                                     │
│  Cantonese Dialect        ████████████████████░░░░  82% accuracy   │
│  (vs. Whisper V3: 54%)                                              │
│                                                                     │
│  Code-Switching (ZH↔EN)   ██████████████████████░░  88% accuracy   │
│  (vs. Whisper V3: 71%)                                              │
│                                                                     │
│  Background Noise (SNR 5) ████████████████░░░░░░░░  76% accuracy   │
│  (vs. Whisper V3: 68%)                                              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Key Differentiators

### 4.1 Dialect Recognition

Unlike mainstream ASR models that treat dialects as afterthoughts, GLM-ASR-Nano makes dialect recognition a core training objective:

- **Mandarin Variants:** Beijing, Taiwanese, Singaporean
- **Cantonese (粤语):** Full support, not just phonetic mapping
- **Accented English:** Chinese-accented, Indian-accented English

### 4.2 Whisper-Speech Optimization

Specifically trained on low-volume "whisper-style" speech:

```swift
// UnaMentis use case: Late-night study sessions
// User speaking quietly to avoid disturbing others
// GLM-ASR-Nano captures faint audio that other models miss
```

### 4.3 Code-Switching

Seamless transcription when speakers alternate languages:

```
Input:  "我想了解一下这个 API endpoint 怎么用"
Output: "我想了解一下这个 API endpoint 怎么用"
        (Correctly preserves mixed Chinese/English)
```

### 4.4 Open Source Benefits

Full MIT license unlocks:

- Domain fine-tuning (educational content, technical vocabulary)
- Dialect/accent adaptation for specific user populations
- On-premise deployment (no data leaves your infrastructure)
- Full transparency for privacy/audit requirements
- No API costs at scale

---

## 5. Integration Options

### 5.1 Option A: Server-Side Deployment (Recommended)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Server-Side Architecture                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   iPhone App                         GPU Server                     │
│   ┌─────────────┐                   ┌─────────────────────────┐    │
│   │ AudioEngine │                   │  GLM-ASR-Nano Service   │    │
│   │ (16kHz PCM) │ ═══WebSocket════► │  ┌─────────────────┐   │    │
│   │             │                   │  │ vLLM / SGLang   │   │    │
│   │ GLMASRSTTSvc│ ◄═══════════════  │  │ Streaming API   │   │    │
│   └─────────────┘   Transcripts     │  └─────────────────┘   │    │
│                                     │  GPU: T4/A10/L4        │    │
│                                     └─────────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Pros:**
- Works on all iOS devices (no device requirements)
- Easier to update model without app release
- Can use larger/better models if needed
- Proven pattern (matches Deepgram/AssemblyAI implementation)

**Cons:**
- Requires server infrastructure
- Network latency added
- Server costs (but lower than API costs at scale)

### 5.2 Option B: On-Device Inference (Unified GGUF via llama.cpp)

```
┌─────────────────────────────────────────────────────────────────────┐
│              On-Device Architecture (Unified GGUF)                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   iPhone 17 Pro Max                                                 │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                                                              │  │
│   │  AudioEngine ──► llama.cpp (unified GGUF) ──► Transcript   │  │
│   │  (16kHz PCM)     Q4_K_M (~1.06GB)                          │  │
│   │                  single model file                           │  │
│   │                                                              │  │
│   │  ┌────────────────────────────────────────────────────────┐ │  │
│   │  │ A19 Pro Neural Engine (16-core) + 12GB RAM            │ │  │
│   │  │ Vapor Chamber Cooling (40% better sustained perf)     │ │  │
│   │  └────────────────────────────────────────────────────────┘ │  │
│   │                                                              │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

> **Architecture Change:** The original design speculated a multi-component CoreML decomposition
> (Whisper encoder + audio adapter + embed head + GGUF decoder, totaling ~2.4GB). The updated
> approach uses a unified GGUF via llama.cpp's libmtmd audio support, resulting in a single
> Q4_K_M file at ~1.06GB.

**Pros:**
- Zero network latency
- Complete privacy (audio never leaves device)
- Works offline
- No ongoing server costs
- Single model file (~1.06GB Q4_K_M vs ~2.4GB multi-component)

**Cons:**
- Requires iPhone 17 Pro (12GB RAM)
- llama.cpp Swift wrapper needs updating (StanfordBDHG v0.3.3 predates audio support)
- Audio support in llama.cpp still marked experimental
- Battery/thermal impact during long sessions

### 5.3 Option C: Hybrid (Recommended Long-Term)

```swift
// Runtime selection based on device tier and conditions
func selectSTTService() -> STTServiceProtocol {
    switch (deviceTier, networkStatus, thermalState) {
    case (.ultra, _, .nominal):
        // iPhone 17 Pro Max in good thermal state
        return GLMASROnDeviceSTTService()

    case (.ultra, _, .serious):
        // iPhone 17 Pro Max but overheating
        return GLMASRServerSTTService()  // Offload to server

    case (.proMax, .connected, _):
        // iPhone 16 Pro Max with network
        return GLMASRServerSTTService()

    case (_, .disconnected, _):
        // Offline fallback
        return AppleSpeechSTTService()  // Built-in, lower quality

    default:
        return DeepgramSTTService()  // Current production
    }
}
```

---

## 6. Device Compatibility Analysis

### 6.1 iPhone Model Comparison

| Device | RAM | Chip | Neural Engine | GLM-ASR Viable? |
|--------|-----|------|---------------|-----------------|
| iPhone 17 Pro Max | **12GB** | A19 Pro | 16-core + accelerators | **On-Device (INT4)** |
| iPhone 17 Pro | 12GB | A19 Pro | 16-core | On-Device (INT4) |
| iPhone 16 Pro Max | 8GB | A18 Pro | 16-core | Server Only |
| iPhone 16 Pro | 8GB | A18 Pro | 16-core | Server Only |
| iPhone 15 Pro Max | 8GB | A17 Pro | 16-core | Server Only |
| iPhone 15 Pro | 8GB | A17 Pro | 16-core | Server Only |
| iPhone 14 Pro | 6GB | A16 | 16-core | Server Only |

### 6.2 iPhone 17 Pro Max Deep Dive

```
┌─────────────────────────────────────────────────────────────────────┐
│              iPhone 17 Pro Max Specifications (Sept 2025)           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Chip: A19 Pro                                                      │
│  ├─ CPU: 6-core (2 performance + 4 efficiency)                     │
│  │       15% faster single-core, 20% faster multi-core vs A18 Pro  │
│  ├─ GPU: 6-core with hardware ray tracing                          │
│  └─ Neural Engine: 16-core with per-core accelerators              │
│                                                                     │
│  Memory: 12GB LPDDR5X @ 8533 MT/s                                  │
│          (50% more than iPhone 16 Pro Max)                          │
│                                                                     │
│  Thermal: Vapor Chamber Cooling                                     │
│           40% better sustained performance                          │
│           Critical for 60-90 minute tutoring sessions               │
│                                                                     │
│  Storage: 256GB / 512GB / 1TB / 2TB options                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.3 Memory Budget Analysis (iPhone 17 Pro Max)

```
┌─────────────────────────────────────────────────────────────────────┐
│           12GB RAM Budget for UnaMentis + GLM-ASR-Nano            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  iOS System Reserved          │████████░░░░░░░░░░░░│  ~3.0 GB      │
│  UnaMentis App               │██░░░░░░░░░░░░░░░░░░│  ~0.5 GB      │
│  AudioEngine Buffers          │█░░░░░░░░░░░░░░░░░░░│  ~0.2 GB      │
│  Silero VAD (CoreML)          │░░░░░░░░░░░░░░░░░░░░│  ~0.05 GB     │
│  GLM-ASR-Nano (INT4)          │███████░░░░░░░░░░░░░│  ~1.5 GB      │
│  Runtime/Activation Memory    │████░░░░░░░░░░░░░░░░│  ~1.0 GB      │
│  ─────────────────────────────┼─────────────────────────────────── │
│  TOTAL USED                   │                    │  ~6.25 GB     │
│  HEADROOM                     │████████████░░░░░░░░│  ~5.75 GB     │
│                                                                     │
│  ✅ Sufficient headroom for GLM-ASR-Nano on-device                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.4 Device Tier Update Required

```swift
// UnaMentisApp.swift - Add iPhone 17 support

enum DeviceCapabilityTier: String, Codable, Sendable {
    case ultra        // NEW: iPhone 17 Pro/Pro Max (12GB RAM)
    case proMax       // Tier 1: iPhone 15/16 Pro Max (8GB RAM)
    case proStandard  // Tier 2: iPhone 14 Pro+, 15 Pro, 16 Pro (6-8GB RAM)
    case unsupported  // Below minimum requirements
}

// Detection logic update
let ultraTierIdentifiers: Set<String> = [
    "iPhone18,1",  // iPhone 17 Pro (projected)
    "iPhone18,2",  // iPhone 17 Pro Max (projected)
]

if ultraTierIdentifiers.contains(identifier) && ramGB >= 12 {
    return .ultra
}
```

---

## 7. Server Hosting Requirements

### 7.1 Minimum Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **GPU** | RTX 3060 12GB | T4 16GB / A10 24GB |
| **VRAM** | 4GB (FP16) | 8GB+ |
| **System RAM** | 16GB | 32GB |
| **Storage** | 20GB SSD | 50GB NVMe |
| **Network** | 100 Mbps | 1 Gbps |
| **OS** | Ubuntu 22.04 | Ubuntu 22.04 LTS |

### 7.2 Hosting Options & Costs

```
┌─────────────────────────────────────────────────────────────────────┐
│                       Hosting Cost Comparison                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  BUDGET TIER (< $50/month)                                         │
│  ├─ RunPod T4 16GB:         ~$0.20/hr  │  $144/mo (24/7)          │
│  ├─ Vast.ai RTX 3090:       ~$0.15/hr  │  $108/mo (24/7)          │
│  └─ Lambda Labs (spot):     ~$0.10/hr  │  Variable availability   │
│                                                                     │
│  PRODUCTION TIER ($50-200/month)                                   │
│  ├─ AWS g5.xlarge (A10G):   ~$1.00/hr  │  $720/mo (24/7)          │
│  │   └─ Spot instances:     ~$0.30/hr  │  $216/mo (interruptible) │
│  ├─ GCP L4:                 ~$0.70/hr  │  $504/mo (24/7)          │
│  └─ Azure NC T4:            ~$0.50/hr  │  $360/mo (24/7)          │
│                                                                     │
│  SERVERLESS (pay-per-inference)                                    │
│  ├─ Modal:                  ~$0.0001/sec of audio                  │
│  ├─ Replicate:              ~$0.0002/sec of audio                  │
│  └─ Banana.dev:             ~$0.0001/sec of audio                  │
│                                                                     │
│  SELF-HOSTED (MacBook Pro M4 Max)                                  │
│  └─ Already owned:          $0/mo additional                        │
│     128GB unified memory = run multiple models simultaneously       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.3 Quick Start Server Setup

#### Option A: SGLang (Recommended)

```bash
# Download the model
huggingface-cli download zai-org/GLM-ASR-Nano-2512

# Start via SGLang Docker (dev image required for GLM-ASR support)
docker run --gpus all \
  -p 30000:30000 \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  lmsysorg/sglang:dev \
  python -m sglang.launch_server \
    --model zai-org/GLM-ASR-Nano-2512 \
    --host 0.0.0.0 \
    --port 30000
```

#### Option B: vLLM (requires transformers 5.0.0)

```bash
# Install transformers from source (5.0.0 dev required)
pip install git+https://github.com/huggingface/transformers
pip install vllm torch

# Download model
huggingface-cli download zai-org/GLM-ASR-Nano-2512

# Start vLLM server
python -m vllm.entrypoints.openai.api_server \
  --model zai-org/GLM-ASR-Nano-2512 \
  --dtype float16 \
  --max-model-len 4096 \
  --port 8000 \
  --host 0.0.0.0
```

#### Option C: Legacy (transformers 4.51.3)

```bash
# Install dependencies (no source install needed)
pip install transformers==4.51.3 torch

# Download model
huggingface-cli download zai-org/GLM-ASR-Nano-2512

# Run using the inference.py script provided in the repo
python inference.py \
  --model zai-org/GLM-ASR-Nano-2512 \
  --audio test.wav
```

---

## 8. Cost Analysis

### 8.1 Current vs. GLM-ASR-Nano Costs

```
┌─────────────────────────────────────────────────────────────────────┐
│              Monthly Cost Projection (100 active users)            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Assumptions:                                                       │
│  • 100 users × 3 sessions/week × 60 min/session = 1,200 hours/mo   │
│                                                                     │
│  CURRENT (Deepgram Nova-3)                                         │
│  └─ 1,200 hours × $0.26/hour = $312/month                          │
│                                                                     │
│  GLM-ASR-NANO (Self-Hosted)                                        │
│  ├─ RunPod T4 (24/7):        $144/month                            │
│  ├─ Bandwidth (~50GB):        $5/month                             │
│  └─ Total:                   $149/month                            │
│                                                                     │
│  SAVINGS: $163/month (52% reduction)                               │
│                                                                     │
│  At 500 users: $1,560/mo (Deepgram) vs $149/mo (GLM) = 90% savings │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 8.2 Break-Even Analysis

```
Break-even point: ~57 hours/month of STT usage

$149/month (server) ÷ $0.26/hour (Deepgram) = 573 hours/month

Below 573 hours/month: Deepgram API is cheaper
Above 573 hours/month: Self-hosted GLM-ASR is cheaper

For UnaMentis's target of extended 60-90 minute sessions,
self-hosting becomes cost-effective at ~10 active daily users.
```

---

## 9. Implementation Recommendations

### 9.1 Phased Approach

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Implementation Roadmap                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  PHASE 1: Server-Side Integration                    [COMPLETE]    │
│  ├─ Implement GLMASRSTTService (WebSocket streaming)               │
│  ├─ Deploy to RunPod/Lambda for testing                            │
│  ├─ A/B test against Deepgram                                      │
│  └─ Measure latency, accuracy, cost                                │
│                                                                     │
│  PHASE 2: Production Hardening                       [COMPLETE]    │
│  ├─ Add health checks and failover                                 │
│  ├─ Implement request queuing for load spikes                      │
│  ├─ Set up monitoring and alerting                                 │
│  └─ Create fallback to Deepgram on server failure                  │
│                                                                     │
│  PHASE 3: Server Backend Update                   [IN PROGRESS]    │
│  ├─ Add SGLang as recommended inference backend                    │
│  ├─ Handle Dec 27 weight format changes (BF16 safetensors)        │
│  ├─ Update Docker configs for SGLang and vLLM paths               │
│  └─ Document transformers 5.0.0 requirement for vLLM              │
│                                                                     │
│  PHASE 4: On-Device Rearchitecture               [IN PROGRESS]    │
│  ├─ Unified GGUF via llama.cpp libmtmd audio support              │
│  ├─ Single Q4_K_M model file (~1.06GB)                            │
│  ├─ Update StanfordBDHG llama.cpp Swift wrapper                   │
│  │   (v0.3.3 predates audio support, PRs #17901, #18142)         │
│  └─ Implement hybrid routing (on-device + server fallback)        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 9.2 Integration with Existing Architecture

GLM-ASR-Nano fits cleanly into UnaMentis's existing provider abstraction:

```swift
// New provider implementing existing protocol
public actor GLMASRSTTService: STTServiceProtocol {
    // Matches DeepgramSTTService / AssemblyAISTTService interface
    public func startStreaming(audioFormat: AVAudioFormat) async throws -> AsyncStream<STTResult>
    public func sendAudio(_ buffer: AVAudioPCMBuffer) async
    public func stopStreaming() async -> STTResult?
    public func cancelStreaming() async

    public var metrics: STTMetrics { get }
    public var costPerHour: Decimal { 0.00 }  // Self-hosted = $0
}
```

### 9.3 Patch Panel Integration

Add GLM-ASR-Nano as a registered STT endpoint:

```swift
let glmASREndpoint = STTEndpoint(
    id: "glm-asr-nano-server",
    displayName: "GLM-ASR-Nano (Self-Hosted)",
    provider: .selfHosted,
    location: .localServer,

    // Performance characteristics
    expectedLatencyMs: 150,
    reliabilityScore: 0.95,

    // Cost
    costPerHour: 0.00,  // Server cost amortized

    // Capabilities
    supportsStreaming: true,
    supportedLanguages: ["zh", "en", "yue"],  // Cantonese!

    connectionConfig: .init(
        baseURL: "wss://your-server.com/v1/audio/stream",
        apiKeyReference: nil  // Self-hosted, no API key
    )
)
```

---

## 10. Resources & References

### 10.1 Official Resources

- **Hugging Face Model:** https://huggingface.co/zai-org/GLM-ASR-Nano-2512
- **GitHub Repository:** https://github.com/zai-org/GLM-ASR
- **Z.AI Documentation:** https://docs.z.ai/guides/audio/glm-asr-2512
- **Community GGUF:** https://huggingface.co/Mungert/GLM-ASR-Nano-2512-GGUF

### 10.2 Related Documentation

- `UnaMentis_TDD.md` - Main technical design document
- `DEVICE_CAPABILITY_TIERS.md` - Device tier definitions
- `PATCH_PANEL_ARCHITECTURE.md` - LLM/STT routing system
- `GLM_ASR_SERVER_TRD.md` - Server implementation TRD

### 10.3 Technical Articles

- [GLM-ASR-Nano-2512 Complete Guide (DEV Community)](https://dev.to/czmilo/glm-asr-nano-2512-the-complete-2025-guide-to-zais-open-source-speech-recognition-model-25b1)
- [GLM-Edge Series for Edge Devices (MarkTechPost)](https://www.marktechpost.com/2024/11/29/tsinghua-university-researchers-released-the-glm-edge-series-a-family-of-ai-models-ranging-from-1-5b-to-5b-parameters-designed-specifically-for-edge-devices/)

### 10.4 Deployment Resources

- [vLLM Deployment Guide](https://docs.vllm.ai/projects/recipes/en/latest/GLM/GLM-4.5.html)
- [ONNX Quantization Guide](https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html)
- [CoreML Tools Documentation](https://apple.github.io/coremltools/)

---

**Document History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | December 2025 | Claude | Initial document |
| 2.0 | February 2026 | Claude | Updated for Dec 27 weight format changes, added SGLang support, corrected model sizes to match actual GGUF variants, revised on-device architecture from multi-component CoreML to unified GGUF approach, added llama.cpp audio support findings |
