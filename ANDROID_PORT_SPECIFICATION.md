# UnaMentis Android Port Specification

**Version:** 1.0
**Date:** January 2026
**Status:** Planning
**Target Platform:** Android 14+ (API 34+)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Why Feature Parity Matters](#2-why-feature-parity-matters)
3. [iOS App Architecture Overview](#3-ios-app-architecture-overview)
4. [Technology Mapping: iOS to Android](#4-technology-mapping-ios-to-android)
5. [Core Features Specification](#5-core-features-specification)
6. [UI/UX Specification](#6-uiux-specification)
7. [Server Communication](#7-server-communication)
8. [Performance Requirements](#8-performance-requirements)
9. [Native Android Optimizations](#9-native-android-optimizations)
10. [Device Capability Tiers](#10-device-capability-tiers)
11. [Accessibility Requirements](#11-accessibility-requirements)
12. [Implementation Roadmap](#12-implementation-roadmap)
13. [Testing Strategy](#13-testing-strategy)

---

## 1. Executive Summary

UnaMentis is a voice AI tutoring application that enables 60-90+ minute voice-based learning sessions with sub-500ms latency. This document specifies the requirements for porting the iOS application to Android while:

1. **Maintaining strict feature parity** with the iOS app
2. **Leveraging native Android capabilities** for optimal performance
3. **Preserving the same user experience** across platforms
4. **Meeting identical performance targets** for latency, stability, and resource usage

### Core Value Proposition

UnaMentis differentiates through:
- **Voice-first interaction** with natural conversation flow
- **Sub-500ms response latency** for fluid dialogue
- **90-minute session stability** without crashes or degradation
- **Multi-provider flexibility** for STT, TTS, and LLM services
- **Curriculum-driven learning** with structured content and progress tracking
- **Cost transparency** with real-time API cost tracking

---

## 2. Why Feature Parity Matters

### 2.1 Business Rationale

**Cross-Platform Consistency:**
- Users may switch between iOS and Android devices
- Learning progress must sync seamlessly across platforms
- Marketing and documentation should describe one product, not two
- Support teams need consistent behavior to troubleshoot

**Brand Identity:**
- UnaMentis should feel identical regardless of platform
- UI patterns, animations, and interactions must match
- Voice tutoring quality cannot vary by device OS

**Development Efficiency:**
- Shared server infrastructure and APIs
- Common curriculum format (UMCF)
- Unified telemetry and analytics pipeline
- Single source of truth for business logic

### 2.2 Technical Rationale

**Server Compatibility:**
- Both apps communicate with the same Management Console (port 8766)
- Identical REST API contracts and WebSocket protocols
- Shared curriculum database and content format
- Common metrics upload format for analytics

**Provider Integration:**
- Same STT providers (Deepgram, AssemblyAI, Groq, self-hosted)
- Same TTS providers (ElevenLabs, Deepgram, self-hosted)
- Same LLM providers (OpenAI, Anthropic, self-hosted)
- Identical API contracts and authentication patterns

### 2.3 What "Feature Parity" Means

| Aspect | Requirement |
|--------|-------------|
| **Functionality** | Every iOS feature must exist on Android |
| **UI/UX** | Same screens, flows, and interaction patterns |
| **Performance** | Same latency, stability, and resource targets |
| **Accessibility** | Same accessibility support (TalkBack vs VoiceOver) |
| **Offline** | Same offline capabilities with on-device models |

### 2.4 Platform-Specific Excellence

Feature parity does NOT mean ignoring platform strengths. Android should leverage:

- **Android Speech Services** for on-device STT (equivalent to Apple Speech)
- **Android TTS Engine** for on-device synthesis (equivalent to AVSpeechSynthesizer)
- **TensorFlow Lite / NNAPI** for on-device ML (equivalent to Core ML)
- **Material Design 3** for native look-and-feel (equivalent to SwiftUI styling)
- **Jetpack Compose** for modern declarative UI (equivalent to SwiftUI)
- **Kotlin Coroutines** for async operations (equivalent to Swift async/await)
- **Room Database** for local persistence (equivalent to Core Data)

---

## 3. iOS App Architecture Overview

Understanding the iOS architecture is essential for creating an equivalent Android implementation.

### 3.1 Architecture Pattern

**iOS:** MVVM + Actor-based concurrency (Swift 6.0)

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS Architecture                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   UI Layer (SwiftUI)                                            │
│   ├── Views (@MainActor)                                        │
│   ├── ViewModels (@MainActor, @Observable)                      │
│   └── Navigation (NavigationStack, TabView)                     │
│                                                                  │
│   Service Layer (Actors)                                        │
│   ├── SessionManager (orchestrates voice sessions)              │
│   ├── AudioEngine (audio I/O, VAD integration)                  │
│   ├── STT/TTS/LLM Services (provider implementations)           │
│   └── CurriculumEngine (content management)                     │
│                                                                  │
│   Core Layer                                                    │
│   ├── PatchPanelService (intelligent LLM routing)               │
│   ├── TelemetryEngine (metrics, costs, latency)                 │
│   ├── PersistenceController (Core Data)                         │
│   └── APIKeyManager (Keychain storage)                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Directory Structure (iOS)

```
UnaMentis/
├── Core/                           # Business logic
│   ├── Audio/                      # AudioEngine, VAD integration
│   ├── Session/                    # SessionManager
│   ├── Curriculum/                 # CurriculumEngine, progress tracking
│   ├── Routing/                    # PatchPanel LLM routing
│   ├── Persistence/                # Core Data stack
│   ├── Telemetry/                  # Metrics and cost tracking
│   ├── Config/                     # API keys, server config
│   └── Logging/                    # Remote log handler
├── Services/                       # External integrations
│   ├── STT/                        # Speech-to-text providers
│   ├── TTS/                        # Text-to-speech providers
│   ├── LLM/                        # Language model providers
│   ├── VAD/                        # Voice activity detection
│   └── Embeddings/                 # Text embeddings
├── UI/                             # SwiftUI views
│   ├── Session/                    # Main voice session UI
│   ├── Curriculum/                 # Content browsing
│   ├── TodoList/                   # Task management
│   ├── History/                    # Session history
│   ├── Analytics/                  # Telemetry dashboard
│   ├── Settings/                   # Configuration
│   └── Onboarding/                 # First-run experience
└── Intents/                        # Siri/Shortcuts integration
```

### 3.3 Key Components

| Component | iOS Implementation | Lines of Code |
|-----------|-------------------|---------------|
| SessionManager | Actor with state machine | ~1,600 |
| AudioEngine | AVAudioEngine wrapper | ~630 |
| SessionView | Main voice UI | ~3,000 |
| SettingsView | Configuration UI | ~2,200 |
| CurriculumView | Content browser | ~1,300 |
| TelemetryEngine | Metrics collection | ~800 |

---

## 4. Technology Mapping: iOS to Android

### 4.1 Core Technologies

| iOS Technology | Android Equivalent | Notes |
|----------------|-------------------|-------|
| Swift 6.0 | Kotlin 2.0+ | Similar modern language features |
| SwiftUI | Jetpack Compose | Declarative UI frameworks |
| Combine | Kotlin Flow | Reactive streams |
| async/await | Kotlin Coroutines | Structured concurrency |
| Actors | Mutex/synchronized or custom | Thread-safe state isolation |
| Core Data | Room Database | Local persistence |
| Keychain | EncryptedSharedPreferences | Secure credential storage |
| AVAudioEngine | AudioRecord/AudioTrack + Oboe | Audio I/O |
| Core ML | TensorFlow Lite + NNAPI | On-device ML |
| URLSession | OkHttp/Retrofit | Networking |
| WebSocket (URLSession) | OkHttp WebSocket | Real-time communication |

### 4.2 UI Components

| iOS Component | Android Equivalent |
|---------------|-------------------|
| NavigationStack | NavHost (Navigation Compose) |
| TabView | BottomNavigation + NavHost |
| NavigationSplitView | ListDetailPaneScaffold |
| List | LazyColumn |
| Sheet/FullScreenCover | ModalBottomSheet / Dialog |
| @State | remember { mutableStateOf() } |
| @StateObject | viewModel() |
| @EnvironmentObject | CompositionLocal / Hilt |
| @Published | StateFlow / MutableState |

### 4.3 Service Providers

| iOS Provider | Android Equivalent |
|--------------|-------------------|
| Apple Speech (SFSpeechRecognizer) | Android SpeechRecognizer |
| AVSpeechSynthesizer | Android TextToSpeech |
| Silero VAD (Core ML) | Silero VAD (TFLite) |
| llama.cpp (Swift) | llama.cpp (JNI/NDK) |
| LiveKit SDK | LiveKit Android SDK |

### 4.4 Platform Services

| iOS Feature | Android Equivalent |
|-------------|-------------------|
| Siri Shortcuts | Google Assistant Actions / Shortcuts |
| Spotlight Search | App Search (AppSearchManager) |
| Background Audio | Foreground Service with notification |
| Haptic Feedback | Vibrator / HapticFeedbackConstants |
| Dynamic Type | Font scaling (sp units) |
| VoiceOver | TalkBack |

---

## 5. Core Features Specification

### 5.1 Voice AI Tutoring Pipeline

The core tutoring loop must be identical:

```
User speaks → VAD detects speech → STT transcribes →
LLM generates response → TTS synthesizes → Audio plays
```

**Latency Budget (same as iOS):**
- STT: <300ms median
- LLM First Token: <200ms median
- TTS TTFB: <200ms median
- **E2E Turn: <500ms median, <1000ms P99**

### 5.2 Speech-to-Text (STT) Providers

Must support all iOS providers:

| Provider | Type | API | Priority |
|----------|------|-----|----------|
| Deepgram Nova-3 | Cloud (WebSocket) | wss://api.deepgram.com | Primary |
| AssemblyAI | Cloud (WebSocket) | wss://api.assemblyai.com | Secondary |
| Groq Whisper | Cloud (REST) | api.groq.com | Free tier |
| Android SpeechRecognizer | On-device | Android SDK | Offline |
| GLM-ASR | Self-hosted | HTTP/WebSocket | Custom server |

**Android-Specific Implementation:**
```kotlin
// Use Android's native SpeechRecognizer for on-device STT
class AndroidSTTService : STTService {
    private val speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)

    override fun startStreaming(): Flow<STTResult> = callbackFlow {
        speechRecognizer.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle) {
                val text = results.getStringArrayList(RESULTS_RECOGNITION)?.firstOrNull()
                trySend(STTResult(text ?: "", isFinal = true))
            }
            override fun onPartialResults(partialResults: Bundle) {
                val text = partialResults.getStringArrayList(RESULTS_RECOGNITION)?.firstOrNull()
                trySend(STTResult(text ?: "", isFinal = false))
            }
            // ... other callbacks
        })
        speechRecognizer.startListening(intent)
        awaitClose { speechRecognizer.stopListening() }
    }
}
```

### 5.3 Text-to-Speech (TTS) Providers

Must support all iOS providers:

| Provider | Type | API | Priority |
|----------|------|-----|----------|
| ElevenLabs | Cloud (WebSocket) | wss://api.elevenlabs.io | Primary |
| Deepgram Aura-2 | Cloud (WebSocket) | wss://api.deepgram.com | Secondary |
| Android TTS | On-device | Android SDK | Offline |
| Piper/VibeVoice | Self-hosted | HTTP | Custom server |

**Android-Specific Implementation:**
```kotlin
// Use Android's native TextToSpeech for on-device TTS
class AndroidTTSService : TTSService {
    private val tts = TextToSpeech(context) { status ->
        if (status == TextToSpeech.SUCCESS) {
            tts.language = Locale.US
        }
    }

    override fun synthesize(text: String): Flow<TTSAudioChunk> = callbackFlow {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String) {
                trySend(TTSAudioChunk(isFirst = true))
            }
            override fun onDone(utteranceId: String) {
                close()
            }
            // ... other callbacks
        })
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
        awaitClose { tts.stop() }
    }
}
```

### 5.4 Language Model (LLM) Providers

Must support all iOS providers:

| Provider | Type | API | Models |
|----------|------|-----|--------|
| OpenAI | Cloud (SSE) | api.openai.com | GPT-4o, GPT-4o-mini |
| Anthropic | Cloud (SSE) | api.anthropic.com | Claude 3.5 Sonnet/Haiku |
| Ollama | Self-hosted | localhost:11434 | Qwen, Llama, Mistral |
| llama.cpp | On-device | JNI | Ministral-3B |

**On-Device LLM via llama.cpp:**
```kotlin
// JNI wrapper for llama.cpp
class OnDeviceLLMService : LLMService {
    private external fun loadModel(modelPath: String): Long
    private external fun generateToken(contextPtr: Long, prompt: String): String
    private external fun freeModel(contextPtr: Long)

    companion object {
        init {
            System.loadLibrary("llama")
        }
    }

    override fun streamCompletion(messages: List<LLMMessage>): Flow<LLMToken> = flow {
        val prompt = formatMessages(messages)
        var token: String
        do {
            token = generateToken(contextPtr, prompt)
            emit(LLMToken(content = token, isDone = token.isEmpty()))
        } while (token.isNotEmpty())
    }
}
```

### 5.5 Voice Activity Detection (VAD)

**Must use Silero VAD for consistency:**

```kotlin
// Silero VAD via TensorFlow Lite
class SileroVADService : VADService {
    private val interpreter: Interpreter
    private val inputBuffer = FloatArray(512)  // 32ms at 16kHz

    init {
        val model = loadModelFile("silero_vad.tflite")
        interpreter = Interpreter(model)
    }

    override fun processAudio(samples: FloatArray): VADResult {
        interpreter.run(samples, outputBuffer)
        val probability = outputBuffer[0]
        return VADResult(
            isSpeech = probability > threshold,
            confidence = probability
        )
    }
}
```

### 5.6 Session Management

The SessionManager must implement the same state machine:

```kotlin
enum class SessionState {
    IDLE,
    USER_SPEAKING,
    PROCESSING_UTTERANCE,
    AI_THINKING,
    AI_SPEAKING,
    INTERRUPTED,
    PAUSED,
    ERROR
}

class SessionManager(
    private val audioEngine: AudioEngine,
    private val sttService: STTService,
    private val llmService: LLMService,
    private val ttsService: TTSService,
    private val telemetry: TelemetryEngine
) {
    private val _state = MutableStateFlow(SessionState.IDLE)
    val state: StateFlow<SessionState> = _state.asStateFlow()

    // Conversation history
    private val conversationHistory = mutableListOf<LLMMessage>()

    // Turn-taking with 1.5s silence threshold
    private val silenceThresholdMs = 1500L

    suspend fun startSession(topic: Topic? = null) {
        // Initialize services, start audio capture, begin VAD monitoring
    }

    suspend fun stopSession() {
        // Clean up all async tasks, persist session to database
    }

    // Barge-in handling with 600ms confirmation window
    private suspend fun handleInterruption() {
        // Stop TTS playback, transition to USER_SPEAKING
    }
}
```

### 5.7 Curriculum Engine

Must support the UMCF (Una Mentis Curriculum Format):

```kotlin
data class Curriculum(
    val id: String,
    val title: String,
    val description: String,
    val version: String,
    val topics: List<Topic>
)

data class Topic(
    val id: String,
    val title: String,
    val orderIndex: Int,
    val transcript: List<TranscriptSegment>,
    val learningObjectives: List<String>,
    val documents: List<Document>,
    val visualAssets: List<VisualAsset>
)

data class TranscriptSegment(
    val id: String,
    val type: String,  // "content", "checkpoint", "activity"
    val content: String,
    val spokenText: String?,  // TTS-optimized version
    val stoppingPoint: StoppingPoint?
)
```

### 5.8 Progress Tracking

```kotlin
@Entity(tableName = "topic_progress")
data class TopicProgress(
    @PrimaryKey val topicId: String,
    val curriculumId: String,
    val timeSpentSeconds: Long,
    val masteryLevel: Float,  // 0.0 - 1.0
    val lastAccessedAt: Long,
    val completedSegments: List<String>
)
```

### 5.9 Telemetry Engine

Must track identical metrics:

```kotlin
class TelemetryEngine {
    // Latency tracking
    fun recordLatency(type: LatencyType, durationMs: Long)

    // Cost tracking
    fun recordCost(provider: String, costUsd: Double)

    // Session metrics
    fun getSessionMetrics(): SessionMetrics

    // Export for server upload
    fun exportMetrics(): MetricsSnapshot
}

data class SessionMetrics(
    val sttMedianLatencyMs: Long,
    val sttP99LatencyMs: Long,
    val llmMedianLatencyMs: Long,
    val llmP99LatencyMs: Long,
    val ttsMedianLatencyMs: Long,
    val ttsP99LatencyMs: Long,
    val e2eMedianLatencyMs: Long,
    val e2eP99LatencyMs: Long,
    val totalCostUsd: Double,
    val sessionDurationSeconds: Long,
    val turnCount: Int,
    val interruptionCount: Int
)
```

### 5.10 Patch Panel (LLM Routing)

Intelligent routing based on task type and conditions:

```kotlin
class PatchPanelService(
    private val endpoints: List<LLMEndpoint>,
    private val routingTable: RoutingTable
) {
    fun selectEndpoint(
        taskType: LLMTaskType,
        context: RoutingContext
    ): LLMEndpoint {
        // Evaluate routing rules
        val matchingRules = routingTable.rules.filter { rule ->
            rule.conditions.all { it.matches(context) }
        }

        // Return highest priority matching endpoint
        return matchingRules
            .sortedByDescending { it.priority }
            .firstOrNull()?.endpoint
            ?: endpoints.first()
    }
}

enum class LLMTaskType {
    TUTORING,           // Main conversation
    PLANNING,           // Session planning
    SUMMARIZATION,      // Content summarization
    ASSESSMENT,         // Quiz/evaluation
    SIMPLE_RESPONSE     // Quick acknowledgments
}
```

---

## 6. UI/UX Specification

### 6.1 Navigation Structure

**6 Primary Tabs (identical to iOS):**

```
┌─────────────────────────────────────────────────────────────────┐
│                        UnaMentis                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   [Session] [Curriculum] [To-Do] [History] [Analytics] [Settings]│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Screen Specifications

#### 6.2.1 Session Screen (Main Voice Interface)

**Purpose:** Primary voice conversation interface

**Components:**
- Transcript display (scrolling list of user/AI messages)
- Audio level visualization (waveform or VU meter)
- Visual asset overlay (images, diagrams for curriculum)
- Session control bar (mute, pause, slide-to-stop)
- Status indicator (listening, thinking, speaking)

**Key Interactions:**
- Tap anywhere to start session
- Slide-to-stop gesture for ending session
- Tap mute button to toggle microphone
- Tap pause button to pause/resume

**Compose Implementation:**
```kotlin
@Composable
fun SessionScreen(
    viewModel: SessionViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val transcript by viewModel.transcript.collectAsState()

    Scaffold(
        bottomBar = {
            SessionControlBar(
                isMuted = state.isMuted,
                isPaused = state.isPaused,
                onMuteToggle = viewModel::toggleMute,
                onPauseToggle = viewModel::togglePause,
                onStop = viewModel::stopSession
            )
        }
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            // Status indicator
            SessionStatusBanner(state = state.sessionState)

            // Transcript
            LazyColumn(
                reverseLayout = true,
                modifier = Modifier.weight(1f)
            ) {
                items(transcript) { entry ->
                    TranscriptBubble(entry = entry)
                }
            }

            // Visual asset overlay (if curriculum mode)
            state.currentVisualAsset?.let { asset ->
                VisualAssetView(asset = asset)
            }
        }
    }
}
```

#### 6.2.2 Curriculum Screen

**Purpose:** Browse and import curriculum content

**Components:**
- Curriculum list with search
- Curriculum detail view with topics
- Topic detail with learning objectives
- Server browser for remote import
- Download progress indicator

**Adaptive Layout (phone vs tablet):**
```kotlin
@Composable
fun CurriculumScreen() {
    val windowSizeClass = currentWindowAdaptiveInfo().windowSizeClass

    if (windowSizeClass.widthSizeClass == WindowWidthSizeClass.Expanded) {
        // Tablet: List-detail layout
        ListDetailPaneScaffold(
            listPane = { CurriculumList() },
            detailPane = { CurriculumDetail() }
        )
    } else {
        // Phone: Navigation-based
        NavHost(navController, startDestination = "list") {
            composable("list") { CurriculumList() }
            composable("detail/{id}") { CurriculumDetail() }
        }
    }
}
```

#### 6.2.3 To-Do Screen

**Purpose:** Task management for learning goals

**Components:**
- Filter tabs (Active, Completed, Archived)
- Todo item rows with status, type, source
- Add/edit todo sheet
- Resume from context badge

#### 6.2.4 History Screen

**Purpose:** Session history and playback

**Components:**
- Session list with date, duration, cost
- Session detail with full transcript
- Export functionality (JSON, text)
- Metrics summary per session

#### 6.2.5 Analytics Screen

**Purpose:** Telemetry dashboard

**Components:**
- Quick stats cards (E2E latency, cost, turns)
- Latency breakdown charts (STT, LLM, TTS)
- Cost breakdown by provider
- Quality metrics (interruptions, thermal events)
- Session history trends

#### 6.2.6 Settings Screen

**Purpose:** App configuration

**Sections:**
1. **API Providers** - Manage API keys and select providers
2. **Audio Settings** - Sample rate, buffer size, voice processing
3. **VAD Settings** - Threshold, sensitivity, silence duration
4. **Server Configuration** - Self-hosted server setup
5. **Telemetry** - Logging, metrics export
6. **Presets** - Quick configuration (Balanced, Low Latency, Cost Optimized)
7. **Debug** - Developer tools, device metrics

#### 6.2.7 Onboarding Screen

**Purpose:** First-run experience

**Pages (TabLayout with ViewPager):**
1. Welcome - App introduction
2. Structured Learning - Curriculum features
3. Offline Mode - On-device capabilities
4. Voice Control - Hands-free operation

### 6.3 Custom Components

#### 6.3.1 SlideToStopButton

```kotlin
@Composable
fun SlideToStopButton(
    onStop: () -> Unit,
    modifier: Modifier = Modifier
) {
    var offsetX by remember { mutableFloatStateOf(0f) }
    val trackWidth = 200.dp
    val thumbSize = 56.dp
    val completionThreshold = 0.8f

    Box(
        modifier = modifier
            .width(trackWidth)
            .height(thumbSize)
            .background(
                color = MaterialTheme.colorScheme.surfaceVariant,
                shape = RoundedCornerShape(28.dp)
            )
    ) {
        // Instruction text
        Text(
            text = "Slide to stop",
            modifier = Modifier.align(Alignment.Center),
            alpha = 1f - (offsetX / maxOffset)
        )

        // Draggable thumb
        Box(
            modifier = Modifier
                .offset { IntOffset(offsetX.roundToInt(), 0) }
                .size(thumbSize)
                .background(Color.Red, CircleShape)
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            if (offsetX / maxOffset > completionThreshold) {
                                onStop()
                            }
                            offsetX = 0f
                        },
                        onHorizontalDrag = { _, dragAmount ->
                            offsetX = (offsetX + dragAmount).coerceIn(0f, maxOffset)
                        }
                    )
                }
        ) {
            Icon(
                imageVector = Icons.Default.Stop,
                contentDescription = "Stop",
                tint = Color.White,
                modifier = Modifier.align(Alignment.Center)
            )
        }
    }
}
```

#### 6.3.2 TranscriptBubble

```kotlin
@Composable
fun TranscriptBubble(
    entry: TranscriptEntry,
    modifier: Modifier = Modifier
) {
    val isUser = entry.role == "user"

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        Surface(
            color = if (isUser)
                MaterialTheme.colorScheme.primary
            else
                MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(
                topStart = 16.dp,
                topEnd = 16.dp,
                bottomStart = if (isUser) 16.dp else 4.dp,
                bottomEnd = if (isUser) 4.dp else 16.dp
            ),
            modifier = Modifier.widthIn(max = 280.dp)
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                Text(
                    text = entry.text,
                    color = if (isUser)
                        MaterialTheme.colorScheme.onPrimary
                    else
                        MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = formatTimestamp(entry.timestamp),
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.align(Alignment.End)
                )
            }
        }
    }
}
```

### 6.4 Theming

**Material Design 3 with custom colors:**

```kotlin
private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF1976D2),        // Blue
    secondary = Color(0xFF388E3C),       // Green
    tertiary = Color(0xFFF57C00),        // Orange
    error = Color(0xFFD32F2F),           // Red
    background = Color(0xFFFAFAFA),
    surface = Color(0xFFFFFFFF),
    onPrimary = Color.White,
    onSecondary = Color.White,
    onBackground = Color(0xFF1C1B1F),
    onSurface = Color(0xFF1C1B1F)
)

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF90CAF9),
    secondary = Color(0xFF81C784),
    tertiary = Color(0xFFFFB74D),
    error = Color(0xFFEF5350),
    background = Color(0xFF121212),
    surface = Color(0xFF1E1E1E),
    onPrimary = Color.Black,
    onSecondary = Color.Black,
    onBackground = Color(0xFFE6E1E5),
    onSurface = Color(0xFFE6E1E5)
)
```

### 6.5 Animations

Match iOS animation patterns:

```kotlin
// Spring animation for session controls
val animatedOffset by animateFloatAsState(
    targetValue = if (isDragging) offset else 0f,
    animationSpec = spring(
        dampingRatio = 0.7f,
        stiffness = Spring.StiffnessLow
    )
)

// Scale animation for buttons
val scale by animateFloatAsState(
    targetValue = if (isPressed) 1.1f else 1.0f,
    animationSpec = spring(dampingRatio = 0.5f)
)
```

---

## 7. Server Communication

### 7.1 REST API Endpoints

**Base URL:** `http://{host}:8766` (Management Console)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/curricula` | GET | List all curricula |
| `/api/curricula/{id}` | GET | Get curriculum details |
| `/api/curricula/{id}/full-with-assets` | GET | Download curriculum with assets |
| `/api/curricula/{id}/topics/{topicId}/transcript` | GET | Get topic transcript |
| `/api/metrics` | POST | Upload session metrics |

### 7.2 WebSocket Connections

**Deepgram STT:**
```kotlin
val client = OkHttpClient()
val request = Request.Builder()
    .url("wss://api.deepgram.com/v1/listen?model=nova-2&smart_format=true")
    .addHeader("Authorization", "Token $apiKey")
    .build()

val webSocket = client.newWebSocket(request, object : WebSocketListener() {
    override fun onMessage(webSocket: WebSocket, text: String) {
        val response = Json.decodeFromString<DeepgramResponse>(text)
        // Emit STT result
    }
})
```

**ElevenLabs TTS:**
```kotlin
val request = Request.Builder()
    .url("wss://api.elevenlabs.io/v1/text-to-speech/$voiceId/stream-input")
    .addHeader("xi-api-key", apiKey)
    .build()

val webSocket = client.newWebSocket(request, object : WebSocketListener() {
    override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
        // Play audio chunk
    }
})
```

### 7.3 Client Identification Headers

All requests include:
```
X-Client-ID: {device UUID}
X-Client-Name: {device model}
X-Client-Platform: Android
X-Client-Version: {app version}
```

### 7.4 Error Handling

Implement same error types as iOS:

```kotlin
sealed class NetworkError : Exception() {
    data class ConnectionFailed(override val message: String) : NetworkError()
    object AuthenticationFailed : NetworkError()
    data class RateLimited(val retryAfterSeconds: Int?) : NetworkError()
    object QuotaExceeded : NetworkError()
    data class ServerError(val statusCode: Int, override val message: String?) : NetworkError()
}
```

---

## 8. Performance Requirements

### 8.1 Latency Targets (Same as iOS)

| Component | Target (Median) | Acceptable (P99) |
|-----------|----------------|------------------|
| STT | <300ms | <1000ms |
| LLM First Token | <200ms | <500ms |
| TTS TTFB | <200ms | <400ms |
| **E2E Turn** | **<500ms** | **<1000ms** |

### 8.2 Stability Targets

- **90-min Sessions:** 100% completion rate without crashes
- **Memory Growth:** <50MB over 90 minutes
- **Thermal Throttle:** <3 events per 90-min session
- **Interruption Success:** >90% successful barge-ins

### 8.3 Resource Usage

| Resource | Target |
|----------|--------|
| Battery drain | <15%/hour during active session |
| Memory (app) | <300MB baseline |
| Memory growth | <50MB over 90 minutes |
| CPU (idle) | <5% when paused |
| CPU (active) | <40% average during session |

### 8.4 Cost Targets

- **Balanced Preset:** <$3/hour per user
- **Cost-Optimized:** <$1.50/hour per user

---

## 9. Native Android Optimizations

### 9.1 Audio Pipeline (Oboe Library)

Use Google's Oboe library for lowest-latency audio:

```kotlin
class AudioEngine {
    private external fun nativeCreateStream(
        sampleRate: Int,
        channelCount: Int,
        callback: AudioCallback
    ): Long

    private external fun nativeStartStream(streamPtr: Long)
    private external fun nativeStopStream(streamPtr: Long)

    companion object {
        init {
            System.loadLibrary("audio_engine")
        }
    }
}
```

**C++ (JNI):**
```cpp
#include <oboe/Oboe.h>

class AudioCallback : public oboe::AudioStreamCallback {
    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream *stream,
        void *audioData,
        int32_t numFrames
    ) override {
        // Process audio with minimal latency
        return oboe::DataCallbackResult::Continue;
    }
};
```

### 9.2 Neural Network Acceleration (NNAPI)

```kotlin
// Use NNAPI delegate for TensorFlow Lite models
val options = Interpreter.Options().apply {
    addDelegate(NnApiDelegate())
}
val interpreter = Interpreter(modelBuffer, options)
```

### 9.3 Foreground Service for Background Audio

```kotlin
class SessionForegroundService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("UnaMentis Session Active")
            .setContentText("Tap to return to session")
            .setSmallIcon(R.drawable.ic_mic)
            .addAction(R.drawable.ic_stop, "Stop", stopPendingIntent)
            .build()
    }
}
```

### 9.4 Memory-Mapped Model Loading

```kotlin
// Memory-map large model files for efficient loading
val modelFile = File(context.filesDir, "llama-3b.gguf")
val fileChannel = FileInputStream(modelFile).channel
val mappedBuffer = fileChannel.map(
    FileChannel.MapMode.READ_ONLY,
    0,
    modelFile.length()
)
```

### 9.5 Thermal Monitoring

```kotlin
class ThermalMonitor(context: Context) {
    private val powerManager = context.getSystemService(PowerManager::class.java)

    fun getCurrentThermalStatus(): ThermalStatus {
        return when (powerManager.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> ThermalStatus.NOMINAL
            PowerManager.THERMAL_STATUS_LIGHT -> ThermalStatus.FAIR
            PowerManager.THERMAL_STATUS_MODERATE -> ThermalStatus.FAIR
            PowerManager.THERMAL_STATUS_SEVERE -> ThermalStatus.SERIOUS
            PowerManager.THERMAL_STATUS_CRITICAL -> ThermalStatus.CRITICAL
            else -> ThermalStatus.NOMINAL
        }
    }

    fun addThermalListener(listener: (ThermalStatus) -> Unit) {
        powerManager.addThermalStatusListener(executor) { status ->
            listener(mapThermalStatus(status))
        }
    }
}
```

---

## 10. Device Capability Tiers

### 10.1 Tier Definitions (Match iOS)

**Tier 1: Flagship**
- Snapdragon 8 Gen 2+ or equivalent
- 12GB+ RAM
- Full on-device capabilities

**Tier 2: Standard**
- Snapdragon 8 Gen 1+ or equivalent
- 8GB+ RAM
- Reduced on-device capabilities

**Minimum Supported:**
- Snapdragon 7 Gen 1+ or equivalent
- 6GB+ RAM
- Cloud-primary with limited on-device

### 10.2 Capability Detection

```kotlin
object DeviceCapabilityDetector {
    fun detectTier(context: Context): DeviceTier {
        val activityManager = context.getSystemService(ActivityManager::class.java)
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        val totalRamGb = memInfo.totalMem / (1024 * 1024 * 1024)
        val cpuCores = Runtime.getRuntime().availableProcessors()

        return when {
            totalRamGb >= 12 && cpuCores >= 8 -> DeviceTier.FLAGSHIP
            totalRamGb >= 8 && cpuCores >= 6 -> DeviceTier.STANDARD
            totalRamGb >= 6 -> DeviceTier.MINIMUM
            else -> DeviceTier.UNSUPPORTED
        }
    }
}
```

### 10.3 Dynamic Fallback

Same triggers as iOS:
- Thermal throttling → Reduce on-device model size
- Memory pressure → Unload optional models
- Low battery → Disable on-device LLM
- High inference latency → Fall back to cloud

---

## 11. Accessibility Requirements

### 11.1 TalkBack Support

All interactive elements must have content descriptions:

```kotlin
@Composable
fun SessionControlButton(
    onClick: () -> Unit,
    icon: ImageVector,
    contentDescription: String,
    modifier: Modifier = Modifier
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.semantics {
            this.contentDescription = contentDescription
            this.role = Role.Button
        }
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null  // Handled by semantics
        )
    }
}
```

### 11.2 Dynamic Font Scaling

Use `sp` units for all text:

```kotlin
Text(
    text = "Session Active",
    style = MaterialTheme.typography.headlineMedium,
    // Typography uses sp units automatically
)
```

### 11.3 Minimum Touch Targets

Ensure 48dp minimum touch targets (Android guideline):

```kotlin
IconButton(
    onClick = onClick,
    modifier = Modifier.size(48.dp)  // Minimum touch target
) {
    Icon(...)
}
```

### 11.4 Reduce Motion

Respect system animation settings:

```kotlin
@Composable
fun AnimatedComponent() {
    val reduceMotion = LocalReduceMotion.current

    val animatedValue by animateFloatAsState(
        targetValue = targetValue,
        animationSpec = if (reduceMotion) {
            snap()  // No animation
        } else {
            spring(dampingRatio = 0.7f)
        }
    )
}
```

---

## 12. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-3)

- [ ] Project setup (Kotlin, Compose, Hilt, Room)
- [ ] Core data models and Room entities
- [ ] API client and networking layer
- [ ] Basic navigation structure

### Phase 2: Audio Pipeline (Weeks 4-5)

- [ ] Oboe audio engine integration
- [ ] VAD service (Silero TFLite)
- [ ] Audio level monitoring
- [ ] Basic recording/playback

### Phase 3: Provider Integration (Weeks 6-8)

- [ ] STT providers (Deepgram, AssemblyAI, Android Speech)
- [ ] TTS providers (ElevenLabs, Deepgram, Android TTS)
- [ ] LLM providers (OpenAI, Anthropic, self-hosted)
- [ ] Provider routing (Patch Panel)

### Phase 4: Session Management (Weeks 9-10)

- [ ] SessionManager state machine
- [ ] Conversation history
- [ ] Turn-taking logic
- [ ] Barge-in handling
- [ ] Session persistence

### Phase 5: UI Implementation (Weeks 11-14)

- [ ] Session screen
- [ ] Curriculum browser
- [ ] Settings screens
- [ ] Analytics dashboard
- [ ] Onboarding flow

### Phase 6: Polish & Testing (Weeks 15-16)

- [ ] Performance optimization
- [ ] Accessibility audit
- [ ] 90-minute stability testing
- [ ] Memory leak detection
- [ ] Thermal management

---

## 13. Testing Strategy

### 13.1 Unit Tests

- All ViewModels
- All Services
- All data transformations
- Provider routing logic

### 13.2 Integration Tests

- Audio pipeline end-to-end
- Server communication
- Database operations
- Provider failover

### 13.3 UI Tests

- Navigation flows
- Accessibility compliance
- Orientation changes
- Different screen sizes

### 13.4 Performance Tests

- Latency benchmarks
- Memory profiling (90-minute sessions)
- Thermal behavior
- Battery consumption

### 13.5 Device Testing Matrix

| Device | Tier | Priority |
|--------|------|----------|
| Pixel 8 Pro | Flagship | High |
| Samsung S24 Ultra | Flagship | High |
| Pixel 7a | Standard | High |
| Samsung A54 | Standard | Medium |
| Various tablets | Mixed | Medium |

---

## Appendix A: File Structure (Proposed)

```
app/
├── src/main/
│   ├── kotlin/com/unamentis/
│   │   ├── core/
│   │   │   ├── audio/
│   │   │   │   ├── AudioEngine.kt
│   │   │   │   └── AudioConfig.kt
│   │   │   ├── session/
│   │   │   │   ├── SessionManager.kt
│   │   │   │   └── SessionState.kt
│   │   │   ├── curriculum/
│   │   │   │   ├── CurriculumEngine.kt
│   │   │   │   └── ProgressTracker.kt
│   │   │   ├── routing/
│   │   │   │   ├── PatchPanelService.kt
│   │   │   │   └── RoutingTable.kt
│   │   │   ├── telemetry/
│   │   │   │   └── TelemetryEngine.kt
│   │   │   └── config/
│   │   │       ├── ApiKeyManager.kt
│   │   │       └── ServerConfig.kt
│   │   ├── services/
│   │   │   ├── stt/
│   │   │   │   ├── STTService.kt
│   │   │   │   ├── DeepgramSTTService.kt
│   │   │   │   ├── AssemblyAISTTService.kt
│   │   │   │   └── AndroidSTTService.kt
│   │   │   ├── tts/
│   │   │   │   ├── TTSService.kt
│   │   │   │   ├── ElevenLabsTTSService.kt
│   │   │   │   └── AndroidTTSService.kt
│   │   │   ├── llm/
│   │   │   │   ├── LLMService.kt
│   │   │   │   ├── OpenAILLMService.kt
│   │   │   │   └── AnthropicLLMService.kt
│   │   │   └── vad/
│   │   │       └── SileroVADService.kt
│   │   ├── data/
│   │   │   ├── local/
│   │   │   │   ├── AppDatabase.kt
│   │   │   │   ├── dao/
│   │   │   │   └── entities/
│   │   │   ├── remote/
│   │   │   │   ├── ApiClient.kt
│   │   │   │   └── dto/
│   │   │   └── repository/
│   │   │       ├── CurriculumRepository.kt
│   │   │       └── SessionRepository.kt
│   │   ├── ui/
│   │   │   ├── session/
│   │   │   │   ├── SessionScreen.kt
│   │   │   │   └── SessionViewModel.kt
│   │   │   ├── curriculum/
│   │   │   │   ├── CurriculumScreen.kt
│   │   │   │   └── CurriculumViewModel.kt
│   │   │   ├── settings/
│   │   │   │   ├── SettingsScreen.kt
│   │   │   │   └── SettingsViewModel.kt
│   │   │   ├── analytics/
│   │   │   │   └── AnalyticsScreen.kt
│   │   │   ├── components/
│   │   │   │   ├── SlideToStopButton.kt
│   │   │   │   ├── TranscriptBubble.kt
│   │   │   │   └── SessionControlBar.kt
│   │   │   └── theme/
│   │   │       ├── Theme.kt
│   │   │       ├── Color.kt
│   │   │       └── Typography.kt
│   │   ├── di/
│   │   │   └── AppModule.kt
│   │   └── UnaMentisApp.kt
│   ├── cpp/
│   │   ├── audio_engine.cpp
│   │   └── llama_jni.cpp
│   └── res/
│       ├── values/
│       │   ├── strings.xml
│       │   └── themes.xml
│       └── drawable/
└── build.gradle.kts
```

---

## Appendix B: Dependencies

```kotlin
// build.gradle.kts (app)
dependencies {
    // Core Android
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")

    // Compose
    implementation(platform("androidx.compose:compose-bom:2024.01.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material3.adaptive:adaptive")
    implementation("androidx.navigation:navigation-compose:2.7.6")

    // Dependency Injection
    implementation("com.google.dagger:hilt-android:2.50")
    kapt("com.google.dagger:hilt-compiler:2.50")
    implementation("androidx.hilt:hilt-navigation-compose:1.1.0")

    // Room Database
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    kapt("androidx.room:room-compiler:2.6.1")

    // Networking
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")

    // TensorFlow Lite (VAD, embeddings)
    implementation("org.tensorflow:tensorflow-lite:2.14.0")
    implementation("org.tensorflow:tensorflow-lite-gpu:2.14.0")

    // DataStore (preferences)
    implementation("androidx.datastore:datastore-preferences:1.0.0")

    // Security (encrypted preferences)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}
```

---

*Document created: January 2026*
*Last updated: January 2026*
