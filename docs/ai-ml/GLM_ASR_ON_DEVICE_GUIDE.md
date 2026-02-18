# GLM-ASR On-Device Implementation Guide

**Purpose:** Complete guide for implementing and using the on-device GLM-ASR-Nano speech recognition service in UnaMentis iOS.

**Last Updated:** February 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Model Files](#3-model-files)
4. [Implementation Details](#4-implementation-details)
5. [Setup Instructions](#5-setup-instructions)
6. [Configuration](#6-configuration)
7. [Testing](#7-testing)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Overview

### 1.1 What is On-Device GLM-ASR?

UnaMentis supports running GLM-ASR-Nano directly on the device using a unified GGUF model via llama.cpp. This provides:

- **Zero latency** - No network round-trip
- **Complete privacy** - Audio never leaves the device
- **Offline support** - Works without internet
- **No API costs** - No per-hour transcription fees

### 1.2 Device Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Device | iPhone 17 Pro | iPhone 17 Pro Max |
| RAM | 8GB (12GB recommended) | 12GB |
| iOS | 18.0 | 18.0+ |
| Storage | 1.5GB free | 3GB free |

The unified GGUF approach requires only ~1.06GB of storage for the model file, but 12GB of RAM is needed to accommodate runtime activations during inference.

### 1.3 When to Use On-Device

The `GLMASROnDeviceSTTService` is automatically selected when:

1. Device has sufficient RAM (12GB recommended, 8GB minimum)
2. Model files are present in the app bundle
3. Thermal state is nominal (not overheating)
4. User has enabled on-device mode in settings

---

## 2. Architecture

### 2.1 Component Overview

> **Architecture Change:** The original design decomposed GLM-ASR into multiple CoreML components
> (Whisper encoder, audio adapter, embed head) plus a GGUF text decoder, totaling ~2.4GB. The
> updated approach uses a unified GGUF model via llama.cpp's libmtmd audio support. A single
> Q4_K_M quantized file handles the full audio-to-text pipeline at ~1.06GB.

```
                 GLM-ASR On-Device Pipeline (Unified GGUF)
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Audio Input                                                    │
│  (16kHz PCM)                                                    │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────┐                   │
│  │     llama.cpp (unified GGUF)            │                   │
│  │     - Audio encoding via libmtmd        │                   │
│  │     - Whisper-based feature extraction  │                   │
│  │     - Autoregressive text decoding      │                   │
│  │     - Q4_K_M quantized (~1.06GB)        │                   │
│  └─────────────────────────────────────────┘                   │
│       │                                                         │
│       ▼                                                         │
│  Transcribed Text                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Key Classes

| Class | File | Purpose |
|-------|------|---------|
| `GLMASROnDeviceSTTService` | [GLMASROnDeviceSTTService.swift](../UnaMentis/Services/STT/GLMASROnDeviceSTTService.swift) | Main STT service implementation |
| `GLMTextDecoder` | (internal) | llama.cpp unified GGUF wrapper (handles full pipeline) |

### 2.3 Protocol Conformance

`GLMASROnDeviceSTTService` conforms to `STTServiceProtocol`:

```swift
public actor GLMASROnDeviceSTTService: STTServiceProtocol {
    public func startStreaming(audioFormat: AVAudioFormat) async throws -> AsyncStream<STTResult>
    public func sendAudio(_ buffer: AVAudioPCMBuffer) async
    public func stopStreaming() async -> STTResult?
    public func cancelStreaming() async

    public var metrics: STTMetrics { get }
    public var costPerHour: Decimal { 0.00 }  // Free - on-device

    public static var isDeviceSupported: Bool { get }
}
```

---

## 3. Model Files

### 3.1 Required Models

A single GGUF file is required:

| Model | Size | Format | Purpose |
|-------|------|--------|---------|
| glm-asr-nano-2512-q4km | ~1.06 GB | .gguf | Full audio-to-text pipeline (unified) |

### 3.2 Quantization Options

| Quantization | File Size | Quality | Use Case |
|-------------|-----------|---------|---------|
| Q4_K_M | ~1.06 GB | Recommended | On-device (best balance) |
| Q4_K_S | ~976 MB | Good | On-device (smaller) |
| IQ4_XS | ~925 MB | Acceptable | On-device (smallest usable) |
| Q8_0 | 1.7 GB | High | Server/development |

### 3.3 Model Location

Place the model at:

```
models/glm-asr-nano/
└── glm-asr-nano-2512-q4km.gguf
```

### 3.4 Downloading Models

```bash
# Download the Q4_K_M GGUF from community repository
huggingface-cli download Mungert/GLM-ASR-Nano-2512-GGUF \
    --include "glm-asr-nano-2512-q4km.gguf" \
    --local-dir models/glm-asr-nano
```

### 3.5 Deprecated: Multi-Component CoreML Pipeline

The following four-file approach is no longer used:

| File | Size | Status |
|------|------|--------|
| `GLMASRWhisperEncoder.mlpackage` | 1.2 GB | Deprecated |
| `GLMASRAudioAdapter.mlpackage` | 56 MB | Deprecated |
| `GLMASREmbedHead.mlpackage` | 232 MB | Deprecated |
| `glm-asr-nano-q4km.gguf` (old decoder only) | 935 MB | Deprecated |

The unified GGUF approach replaces all four components with a single file and eliminates the CoreML conversion requirement.

---

## 4. Implementation Details

### 4.1 Service Initialization

```swift
// Unified GGUF approach: single model file handles the full pipeline
let config = GLMASROnDeviceSTTService.Configuration(
    modelDirectory: Bundle.main.resourceURL!.appendingPathComponent("models/glm-asr-nano"),
    maxAudioDuration: 30.0,
    useNeuralEngine: true,
    gpuLayers: 99
)

let sttService = GLMASROnDeviceSTTService(configuration: config)
```

### 4.2 Audio Processing

The service expects 16kHz mono PCM audio:

```swift
let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000,
    channels: 1,
    interleaved: false
)!

let stream = try await sttService.startStreaming(audioFormat: format)

// Send audio buffers as they arrive
for await buffer in audioEngine.audioStream {
    await sttService.sendAudio(buffer)
}

// Process results
for await result in stream {
    print("Transcript: \(result.transcript)")
    if result.isFinal {
        break
    }
}
```

### 4.3 Device Support Check

Before initializing, check if the device supports on-device inference:

```swift
if GLMASROnDeviceSTTService.isDeviceSupported {
    // Initialize on-device service
    let service = GLMASROnDeviceSTTService(configuration: config)
} else {
    // Fall back to server-based service
    let service = GLMASRSTTService(configuration: serverConfig)
}
```

### 4.4 Simulator Support

For simulator testing, on-device mode is enabled when the GGUF model file is present:

```swift
#if targetEnvironment(simulator)
// Check if the unified GGUF model exists in the expected location
let modelDir = Configuration.default.modelDirectory
let ggufPath = modelDir.appendingPathComponent("glm-asr-nano-2512-q4km.gguf").path
return FileManager.default.fileExists(atPath: ggufPath)
#else
return true
#endif
```

---

## 5. Setup Instructions

### 5.1 Adding Models to Xcode Project

1. **Open Xcode** and your UnaMentis project
2. **Right-click** on the UnaMentis folder in the navigator
3. **Select "Add Files to UnaMentis..."**
4. **Navigate** to `models/glm-asr-nano/`
5. **Select the model file** (`glm-asr-nano-2512-q4km.gguf`)
6. **Check** "Copy items if needed"
7. **Check** "Add to targets: UnaMentis"
8. **Click Add**

### 5.2 Build Settings

Ensure these settings in your target:

```
Build Settings:
  SWIFT_OBJC_INTEROP_MODE = objcxx
  CLANG_CXX_LANGUAGE_STANDARD = c++17

Swift Compiler - Custom Flags:
  OTHER_SWIFT_FLAGS = -Xcc -std=c++17
```

### 5.3 Package Dependencies

The project's Package.swift includes llama.cpp:

```swift
dependencies: [
    .package(url: "https://github.com/StanfordBDHG/llama.cpp.git", from: "0.3.3"),
],
targets: [
    .target(
        name: "UnaMentis",
        dependencies: [
            .product(name: "llama", package: "llama.cpp"),
        ],
        swiftSettings: [
            .interoperabilityMode(.Cxx),
            .define("LLAMA_AVAILABLE"),
        ]
    ),
]
```

> **Blocker (February 2026):** StanfordBDHG/llama.cpp v0.3.3 was packaged before audio/multimodal
> support landed in upstream llama.cpp. The relevant upstream PRs are #17901 and #18142. Until
> the Swift wrapper is updated to a revision that includes those PRs, on-device audio inference
> via libmtmd is not available. The service can be built and tested structurally, but model
> loading will fail at runtime until this dependency is updated.

### 5.4 Entitlements

No special entitlements are required for on-device inference. Standard microphone access is already configured.

---

## 6. Configuration

### 6.1 Configuration Options

```swift
public struct Configuration: Sendable {
    /// Directory containing the unified GGUF model file
    public var modelDirectory: URL

    /// Maximum audio duration in seconds (default: 30.0)
    public var maxAudioDuration: TimeInterval = 30.0

    /// Use Neural Engine for acceleration (default: true)
    public var useNeuralEngine: Bool = true

    /// Number of GPU layers for llama.cpp (default: 99)
    public var gpuLayers: Int = 99
}
```

### 6.2 Compute Unit Selection

| Configuration | Description | Best For |
|---------------|-------------|----------|
| `useNeuralEngine: false, gpuLayers: 0` | CPU only | Debugging |
| `useNeuralEngine: true, gpuLayers: 33` | Neural Engine + limited GPU | 8GB devices |
| `useNeuralEngine: true, gpuLayers: 99` | Neural Engine + full GPU offload | **Recommended** (12GB devices) |

### 6.3 Memory Management

For devices with limited RAM, configure conservatively:

```swift
// For 8GB devices (conservative)
let config = GLMASROnDeviceSTTService.Configuration(
    modelDirectory: Bundle.main.resourceURL!.appendingPathComponent("models/glm-asr-nano"),
    maxAudioDuration: 15.0,
    useNeuralEngine: true,
    gpuLayers: 33   // Offload fewer layers to GPU
)

// For 12GB devices (iPhone 17 Pro/Pro Max)
let config = GLMASROnDeviceSTTService.Configuration(
    modelDirectory: Bundle.main.resourceURL!.appendingPathComponent("models/glm-asr-nano"),
    maxAudioDuration: 30.0,
    useNeuralEngine: true,
    gpuLayers: 99   // Full GPU offload
)
```

---

## 7. Testing

### 7.1 Simulator Testing

The iOS Simulator can run on-device mode if models are present:

1. **Copy models** to the simulator's Documents folder or bundle
2. **Build and run** in simulator
3. **Check device support:**
   ```swift
   print("Supported: \(GLMASROnDeviceSTTService.isDeviceSupported)")
   ```

Note: Simulator performance will be slower than real devices.

### 7.2 Device Testing

For accurate performance testing, use a physical device:

1. **Connect** iPhone 17 Pro or later (minimum supported device)
2. **Select device** as build target
3. **Build and run** (Cmd+R)
4. **Test with real speech**

### 7.3 Unit Tests

Run the GLM-ASR unit tests:

```bash
xcodebuild test \
  -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnaMentisTests/Unit/Services/GLMASROnDeviceSTTServiceTests
```

### 7.4 Performance Benchmarks

Expected performance on various devices:

| Device | First Token | Streaming | RTF |
|--------|-------------|-----------|-----|
| iPhone 17 Pro Max | ~200ms | ~50ms/chunk | 0.15x |
| iPhone 17 Pro | ~250ms | ~60ms/chunk | 0.18x |
| iPhone 16 Pro Max | ~400ms | ~100ms/chunk | 0.30x |
| iPhone 15 Pro | ~500ms | ~120ms/chunk | 0.40x |

RTF = Real-Time Factor (lower is better, <1.0 is real-time)

---

## 8. Troubleshooting

### 8.1 Model Not Found

**Symptom:** `Model file not found at path...`

**Solution:**
1. Verify models are in the app bundle
2. Check file names match exactly (case-sensitive)
3. Ensure models are added to target membership

```swift
// Debug: Print bundle contents
if let resourcePath = Bundle.main.resourcePath {
    let contents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
    print("Bundle contents: \(contents)")
}
```

### 8.2 Out of Memory

**Symptom:** App crashes or system kills app

**Solution:**
1. Reduce `gpuLayers` (e.g., from 99 to 33) to lower memory usage
2. Reduce `maxAudioDuration` to process shorter chunks
3. Ensure no other memory-heavy apps running
4. Consider server-based fallback for older devices

### 8.3 Slow Performance

**Symptom:** High latency, choppy audio

**Solution:**
1. Ensure `useNeuralEngine: true` in Configuration
2. Check thermal state (throttling when hot)
3. Reduce `gpuLayers` if memory-constrained
4. Profile with Instruments

### 8.4 GGUF Model Errors

**Symptom:** `Failed to load GGUF model` or `llama_model_load failed`

**Solution:**
1. Verify the GGUF file is not corrupted (re-download if needed)
2. Check quantization format matches expectations (Q4_K_M recommended)
3. Verify the file name matches `glm-asr-nano-2512-q4km.gguf`
4. Ensure sufficient free memory for model loading (~1.5GB at runtime)
5. Consider server-based fallback for unsupported devices

### 8.5 llama.cpp Errors

**Symptom:** `Failed to initialize llama context`

**Solution:**
1. Verify GGUF file is valid
2. Check quantization format (Q4_K_M recommended)
3. Ensure C++ interop is enabled in build settings
4. Check `LLAMA_AVAILABLE` flag is defined

### 8.6 Simulator Not Working

**Symptom:** `isDeviceSupported` returns false in simulator

**Solution:**
1. Ensure models are copied to correct location
2. Check file permissions
3. Verify paths in Configuration.default.modelDirectory
4. Restart simulator

---

## Related Documentation

- [GLM_ASR_NANO_2512.md](GLM_ASR_NANO_2512.md) - Model overview and evaluation
- [GLM_ASR_IMPLEMENTATION_PROGRESS.md](GLM_ASR_IMPLEMENTATION_PROGRESS.md) - Server-side implementation
- [GLM_ASR_SERVER_TRD.md](GLM_ASR_SERVER_TRD.md) - Server deployment guide
- [DEVICE_CAPABILITY_TIERS.md](DEVICE_CAPABILITY_TIERS.md) - Device tier definitions

---

**Document History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | December 2025 | Claude | Initial document |
| 2.0 | February 2026 | Claude | Revised to unified GGUF architecture, updated model sizes, documented llama.cpp Swift wrapper blocker, deprecated multi-component pipeline |
