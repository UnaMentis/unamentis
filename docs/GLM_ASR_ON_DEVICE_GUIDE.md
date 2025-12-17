# GLM-ASR On-Device Implementation Guide

**Purpose:** Complete guide for implementing and using the on-device GLM-ASR-Nano speech recognition service in VoiceLearn iOS.

**Last Updated:** December 2025

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

VoiceLearn supports running GLM-ASR-Nano directly on the device using CoreML for the neural network components and llama.cpp for the text decoder. This provides:

- **Zero latency** - No network round-trip
- **Complete privacy** - Audio never leaves the device
- **Offline support** - Works without internet
- **No API costs** - No per-hour transcription fees

### 1.2 Device Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Device | iPhone 15 Pro | iPhone 17 Pro Max |
| RAM | 8GB | 12GB |
| iOS | 18.0 | 18.0+ |
| Storage | 2.5GB free | 5GB free |

### 1.3 When to Use On-Device

The `GLMASROnDeviceSTTService` is automatically selected when:

1. Device has sufficient RAM (12GB+ for optimal, 8GB minimum)
2. Model files are present in the app bundle
3. Thermal state is nominal (not overheating)
4. User has enabled on-device mode in settings

---

## 2. Architecture

### 2.1 Component Overview

```
                    GLM-ASR On-Device Pipeline
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Audio Input                                                    │
│  (16kHz PCM)                                                    │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────┐                   │
│  │     GLMASRWhisperEncoder (CoreML)       │                   │
│  │     - Mel spectrogram extraction         │                   │
│  │     - Whisper encoder (1.2GB model)      │                   │
│  │     - Outputs: audio embeddings          │                   │
│  └─────────────────────────────────────────┘                   │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────┐                   │
│  │     GLMASRAudioAdapter (CoreML)         │                   │
│  │     - Adapter network (56MB model)       │                   │
│  │     - Aligns audio features to LLM space │                   │
│  └─────────────────────────────────────────┘                   │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────┐                   │
│  │     GLMASREmbedHead (CoreML)            │                   │
│  │     - Embedding head (232MB model)       │                   │
│  │     - Produces token embeddings          │                   │
│  └─────────────────────────────────────────┘                   │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────┐                   │
│  │     GLM-4 Text Decoder (llama.cpp)      │                   │
│  │     - Q4_K_M quantized (935MB model)     │                   │
│  │     - Autoregressive text generation     │                   │
│  │     - Streaming token output             │                   │
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
| `GLMASROnDeviceSTTService` | [GLMASROnDeviceSTTService.swift](../VoiceLearn/Services/STT/GLMASROnDeviceSTTService.swift) | Main STT service implementation |
| `GLMWhisperEncoder` | (internal) | CoreML Whisper encoder wrapper |
| `GLMAudioAdapter` | (internal) | CoreML adapter wrapper |
| `GLMEmbedHead` | (internal) | CoreML embed head wrapper |
| `GLMTextDecoder` | (internal) | llama.cpp decoder wrapper |

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

| Model | Size | Format | Purpose |
|-------|------|--------|---------|
| GLMASRWhisperEncoder | 1.2 GB | .mlpackage | Audio feature extraction |
| GLMASRAudioAdapter | 56 MB | .mlpackage | Feature alignment |
| GLMASREmbedHead | 232 MB | .mlpackage | Token embedding |
| glm-asr-nano-q4km | 935 MB | .gguf | Text decoding (llama.cpp) |

**Total:** ~2.4 GB

### 3.2 Model Location

Models should be placed in:

```
models/glm-asr-nano/
├── GLMASRWhisperEncoder.mlpackage/
├── GLMASRAudioAdapter.mlpackage/
├── GLMASREmbedHead.mlpackage/
└── glm-asr-nano-q4km.gguf
```

### 3.3 Obtaining Models

Models are available from:

1. **Hugging Face:** https://huggingface.co/zai-org/GLM-ASR-Nano-2512
2. **Project scripts:** `./scripts/download-glm-models.sh` (if available)

### 3.4 CoreML Conversion

If you have the original PyTorch models, convert to CoreML:

```bash
# Install coremltools
pip install coremltools torch

# Run conversion script
python scripts/convert_glm_to_coreml.py \
    --input-dir /path/to/pytorch/models \
    --output-dir models/glm-asr-nano
```

### 3.5 GGUF Quantization

The text decoder uses Q4_K_M quantization for optimal size/quality balance:

```bash
# If you have the F16 model, quantize it:
/path/to/llama.cpp/build/bin/llama-quantize \
    models/glm-asr-nano/glm-asr-nano-f16.gguf \
    models/glm-asr-nano/glm-asr-nano-q4km.gguf \
    Q4_K_M
```

---

## 4. Implementation Details

### 4.1 Service Initialization

```swift
let config = GLMASROnDeviceConfiguration(
    encoderModelPath: Bundle.main.path(forResource: "GLMASRWhisperEncoder", ofType: "mlpackage"),
    adapterModelPath: Bundle.main.path(forResource: "GLMASRAudioAdapter", ofType: "mlpackage"),
    embedHeadModelPath: Bundle.main.path(forResource: "GLMASREmbedHead", ofType: "mlpackage"),
    decoderModelPath: Bundle.main.path(forResource: "glm-asr-nano-q4km", ofType: "gguf"),
    computeUnits: .cpuAndNeuralEngine,
    maxContextLength: 4096
)

let sttService = try await GLMASROnDeviceSTTService(configuration: config)
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
    let service = try await GLMASROnDeviceSTTService(configuration: config)
} else {
    // Fall back to server-based service
    let service = GLMASRSTTService(configuration: serverConfig)
}
```

### 4.4 Simulator Support

For simulator testing, on-device mode is enabled when models are present:

```swift
#if targetEnvironment(simulator)
// Check if models exist in the expected location
let modelDir = Configuration.default.modelDirectory
let encoderPath = modelDir.appendingPathComponent("GLMASRWhisperEncoder.mlpackage").path
return FileManager.default.fileExists(atPath: encoderPath)
#else
return true
#endif
```

---

## 5. Setup Instructions

### 5.1 Adding Models to Xcode Project

1. **Open Xcode** and your VoiceLearn project
2. **Right-click** on the VoiceLearn folder in the navigator
3. **Select "Add Files to VoiceLearn..."**
4. **Navigate** to `models/glm-asr-nano/`
5. **Select all model files** (.mlpackage folders and .gguf file)
6. **Check** "Copy items if needed"
7. **Check** "Add to targets: VoiceLearn"
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

The project's Package.swift already includes llama.cpp:

```swift
dependencies: [
    .package(url: "https://github.com/StanfordBDHG/llama.cpp.git", from: "0.3.3"),
],
targets: [
    .target(
        name: "VoiceLearn",
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

### 5.4 Entitlements

No special entitlements are required for on-device inference. Standard microphone access is already configured.

---

## 6. Configuration

### 6.1 Configuration Options

```swift
public struct GLMASROnDeviceConfiguration {
    /// Path to the Whisper encoder CoreML model
    public var encoderModelPath: String?

    /// Path to the audio adapter CoreML model
    public var adapterModelPath: String?

    /// Path to the embed head CoreML model
    public var embedHeadModelPath: String?

    /// Path to the GGUF decoder model
    public var decoderModelPath: String?

    /// CoreML compute units (default: cpuAndNeuralEngine)
    public var computeUnits: MLComputeUnits = .cpuAndNeuralEngine

    /// Maximum context length for decoder (default: 4096)
    public var maxContextLength: Int = 4096

    /// Number of threads for llama.cpp (default: 4)
    public var decoderThreads: Int = 4

    /// Enable streaming results (default: true)
    public var streamingEnabled: Bool = true

    /// Language hint (default: "auto")
    public var language: String = "auto"
}
```

### 6.2 Compute Unit Selection

| Compute Units | Description | Best For |
|---------------|-------------|----------|
| `.cpuOnly` | CPU only | Debugging |
| `.cpuAndGPU` | CPU + GPU | Not recommended |
| `.cpuAndNeuralEngine` | CPU + Neural Engine | **Recommended** |
| `.all` | All available | Maximum performance |

### 6.3 Memory Management

For devices with limited RAM, configure conservatively:

```swift
// For 8GB devices (iPhone 15 Pro)
let config = GLMASROnDeviceConfiguration(
    computeUnits: .cpuAndNeuralEngine,
    maxContextLength: 2048,  // Reduced
    decoderThreads: 2        // Reduced
)

// For 12GB devices (iPhone 17 Pro Max)
let config = GLMASROnDeviceConfiguration(
    computeUnits: .all,
    maxContextLength: 4096,
    decoderThreads: 4
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

1. **Connect** iPhone 15 Pro or later
2. **Select device** as build target
3. **Build and run** (Cmd+R)
4. **Test with real speech**

### 7.3 Unit Tests

Run the GLM-ASR unit tests:

```bash
xcodebuild test \
  -scheme VoiceLearn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VoiceLearnTests/Unit/Services/GLMASROnDeviceSTTServiceTests
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
1. Reduce `maxContextLength`
2. Use fewer `decoderThreads`
3. Ensure no other memory-heavy apps running
4. Consider server-based fallback for older devices

### 8.3 Slow Performance

**Symptom:** High latency, choppy audio

**Solution:**
1. Use `.cpuAndNeuralEngine` compute units
2. Check thermal state (throttling when hot)
3. Ensure models are optimized (CoreML compiled)
4. Profile with Instruments

### 8.4 CoreML Errors

**Symptom:** `CoreML model failed to load`

**Solution:**
1. Verify iOS version (18.0+ required)
2. Check model format (.mlpackage not .mlmodel)
3. Recompile models with latest coremltools
4. Check Xcode console for detailed errors

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
