# FOV Context Management

Foveated context management for voice tutoring sessions. This system manages hierarchical cognitive buffers to build optimal LLM context for real-time tutoring interactions.

## Overview

The FOV (Field of View) Context system is inspired by **foveated rendering** from VR/AR, where the center of visual attention receives full resolution while the periphery is progressively compressed. Applied to LLM context:

- **Immediate Context** (center of attention): Full detail, always included
- **Working Context** (current topic): High detail, injected as needed
- **Episodic Context** (session history): Summarized, compressed
- **Semantic Context** (curriculum overview): Highly compressed outline

This hierarchical approach enables:
- Efficient token usage across different model context windows
- Fast context building for barge-in scenarios
- Adaptive context based on learner needs
- Automatic expansion when uncertainty is detected

## Architecture

### Hierarchical Cognitive Buffers

```
+-------------------------------------------------------------------+
|                    FOV CONTEXT MANAGER                             |
+-------------------------------------------------------------------+
|  IMMEDIATE BUFFER (always in context, highest priority)           |
|  - Current TTS segment being played + adjacent segments           |
|  - Last N conversation turns (verbatim)                           |
|  - User's barge-in utterance                                      |
|  - Adaptive: 3-10 turns based on model context window             |
+-------------------------------------------------------------------+
|  WORKING BUFFER (current topic, high detail)                      |
|  - Current topic's full content + learning objectives             |
|  - Glossary terms relevant to current segment                     |
|  - Misconception triggers for current topic                       |
|  - Alternative explanations (retrieved on demand)                 |
+-------------------------------------------------------------------+
|  EPISODIC BUFFER (session memory, summarized)                     |
|  - Prior topics covered (compressed summaries)                    |
|  - User's questions and confusions from earlier                   |
|  - Misconceptions triggered and remediated                        |
|  - Learning profile signals (pace, style preferences)             |
+-------------------------------------------------------------------+
|  SEMANTIC BUFFER (curriculum-wide, highly compressed)             |
|  - Full curriculum outline (titles + objectives only)             |
|  - Current position in curriculum journey                         |
|  - Topic prerequisites and dependencies                           |
+-------------------------------------------------------------------+
```

### Adaptive Token Budgets

Token budgets scale based on the model's context window size:

| Model Tier | Context Window | Total Budget | Immediate | Working | Episodic | Semantic |
|------------|----------------|--------------|-----------|---------|----------|----------|
| **Cloud** | 100K+ tokens | 12,000 | 4,000 | 4,000 | 2,500 | 1,500 |
| **Mid-Range** | 32K-100K | 8,000 | 2,500 | 3,000 | 1,500 | 1,000 |
| **On-Device** | 8K-32K | 4,000 | 1,500 | 1,500 | 600 | 400 |
| **Tiny** | <8K | 2,000 | 800 | 700 | 300 | 200 |

**Model Tier Detection:**
- Cloud: Claude 3.5, GPT-4o, Gemini Pro (128K+ context)
- Mid-Range: GPT-4o-mini, smaller Claude models (32K-100K)
- On-Device: Ministral-3B, Qwen 7B (8K-32K)
- Tiny: TinyLlama, small quantized models (<8K)

### Context Flow

```
Barge-in Event
     |
     v
+--------------------+
| Build FOV Context  |
| (all 4 buffers)    |
+--------------------+
     |
     v
+--------------------+
| LLM Response       |
+--------------------+
     |
     v
+--------------------+
| Confidence         |
| Analysis           |
+--------------------+
     |
     +---> High Confidence ---> Continue Session
     |
     +---> Low Confidence ---> Expand Context ---> Re-prompt
```

## Confidence Monitoring

The system monitors LLM responses for uncertainty signals and automatically expands context when needed.

### Uncertainty Detection

The ConfidenceMonitor analyzes responses for four types of markers:

| Marker Type | Examples | Weight |
|-------------|----------|--------|
| **Hedging** | "I think", "I'm not sure", "possibly", "maybe" | 0.25 |
| **Deflection** | "I can't help with that", "outside my scope" | 0.30 |
| **Knowledge Gap** | "I don't have information about", "my knowledge doesn't cover" | 0.35 |
| **Vague Language** | "probably", "sometimes", "sort of", "kind of" | 0.10 |

### Expansion Strategy

When confidence drops below threshold (default: 0.5):

| Priority | Trigger | Expansion Scope | Action |
|----------|---------|-----------------|--------|
| **HIGH** | Confidence < 0.3 | Full Curriculum | Semantic search across all content |
| **MEDIUM** | Confidence < 0.5 | Current Unit | Expand to related topics in unit |
| **LOW** | Declining trend | Current Topic | Add more detail from current topic |

### Trend Analysis

The system tracks confidence over recent responses to detect patterns:
- **Stable**: Confidence consistent
- **Improving**: Confidence increasing (good sign)
- **Declining**: Confidence decreasing (triggers expansion)

## Implementation

### Server-Side (Primary)

The FOV context system is implemented server-side in Python, as the server handles LLM interactions for barge-in scenarios.

**Location:** `server/management/fov_context/`

| File | Purpose |
|------|---------|
| `models.py` | Buffer models, token budgets, model tiers |
| `manager.py` | FOVContextManager for building LLM context |
| `confidence.py` | ConfidenceMonitor for uncertainty detection |
| `session.py` | FOVSession integrating context + confidence |
| `__init__.py` | Package exports |

**API Endpoints:** `server/management/fov_context_api.py`

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/sessions` | POST | Create new session with FOV context |
| `/api/sessions/{id}` | GET | Get session state |
| `/api/sessions/{id}` | DELETE | End session |
| `/api/sessions/{id}/topic` | PUT | Set current topic |
| `/api/sessions/{id}/position` | PUT | Set curriculum position |
| `/api/sessions/{id}/segment` | PUT | Set current TTS segment |
| `/api/sessions/{id}/barge-in` | POST | Record barge-in event |
| `/api/sessions/{id}/messages` | GET | Build LLM messages |
| `/api/sessions/{id}/analyze-response` | POST | Analyze response confidence |

### iOS Client (Complementary)

The iOS client maintains a lightweight FOV context coordinator that syncs with the server.

**Location:** `UnaMentis/Core/Context/`

| File | Purpose |
|------|---------|
| `BufferModels.swift` | Buffer data structures |
| `FOVContextManager.swift` | Local context management |
| `ConfidenceMonitor.swift` | Client-side confidence tracking |
| `SessionManager+FOVContext.swift` | SessionManager integration |

## Usage

### Creating a Session

```python
from fov_context import FOVSession, SessionConfig

# Create session with custom config
config = SessionConfig(
    model_name="claude-3-5-sonnet",
    model_context_window=200_000,
    auto_expand_context=True,
    confidence_threshold=0.5
)

session = FOVSession.create(
    curriculum_id="physics-101",
    config=config
)
session.start()
```

### Setting Topic Context

```python
# Set current topic with all relevant content
session.set_current_topic(
    topic_id="topic-123",
    topic_title="Newton's Laws of Motion",
    topic_content="Newton's first law states that...",
    learning_objectives=[
        "Understand inertia",
        "Apply F=ma to problems"
    ],
    glossary_terms=[
        {"term": "Inertia", "definition": "Resistance to change in motion"},
        {"term": "Force", "definition": "A push or pull on an object"}
    ],
    misconceptions=[
        {
            "trigger_phrase": "heavier objects fall faster",
            "misconception": "Mass affects falling speed in vacuum",
            "remediation": "In vacuum, all objects fall at the same rate..."
        }
    ]
)
```

### Building LLM Context

```python
# Build context for LLM call
context = session.build_llm_context(
    barge_in_utterance="Wait, what about friction?"
)

# Get as system message
system_message = context.to_system_message()

# Or get as message list for LLM API
messages = session.build_llm_messages(
    barge_in_utterance="Wait, what about friction?"
)
```

### Confidence Analysis

```python
# Analyze LLM response
llm_response = "I'm not entirely sure, but I think friction might..."

analysis, recommendation = session.process_response_with_confidence(llm_response)

if recommendation and recommendation.should_expand:
    print(f"Expanding context: {recommendation.reason}")
    print(f"Priority: {recommendation.priority}")
    print(f"Scope: {recommendation.suggested_scope}")
```

### Learner Signals

```python
# Record learner signals for context adaptation
session.record_clarification_request()  # User asked for clarification
session.record_repetition_request()     # User asked to repeat
session.record_confusion_signal()       # Detected confusion

# Record topic completion
session.record_topic_completion(
    summary="Covered Newton's three laws with examples",
    mastery_level=0.85
)
```

## API Reference

### FOVSession

The main entry point for FOV context management.

```python
class FOVSession:
    # Lifecycle
    def start() -> None
    def pause() -> None
    def resume() -> None
    def end() -> None

    # Curriculum Context
    def set_current_topic(topic_id, topic_title, topic_content, ...)
    def set_curriculum_position(curriculum_title, current_topic_index, ...)
    def set_current_segment(segment: TranscriptSegment)

    # Conversation
    def add_user_turn(content: str, is_barge_in: bool = False)
    def add_assistant_turn(content: str)

    # Context Building
    def build_llm_context(barge_in_utterance: str = None) -> FOVContext
    def build_llm_messages(barge_in_utterance: str = None) -> list[dict]

    # Confidence
    def analyze_response(response: str) -> ConfidenceAnalysis
    def process_response_with_confidence(response: str) -> tuple

    # State
    def get_state() -> dict
    def get_events(event_type: str = None) -> list[dict]
```

### FOVContextManager

Low-level buffer management.

```python
class FOVContextManager:
    @classmethod
    def for_context_window(context_window: int, system_prompt: str = None)

    @classmethod
    def for_model(model_name: str, system_prompt: str = None)

    def build_context(history: list, barge_in: str = None) -> FOVContext
    def build_messages_for_llm(history: list, barge_in: str = None) -> list

    # Buffer updates
    def set_current_segment(segment: TranscriptSegment)
    def set_current_topic(topic_id, topic_title, ...)
    def set_curriculum_position(curriculum_id, ...)
    def record_topic_completion(summary: TopicSummary)
```

### ConfidenceMonitor

Response confidence analysis.

```python
class ConfidenceMonitor:
    def analyze_response(response: str) -> ConfidenceAnalysis
    def should_trigger_expansion(analysis: ConfidenceAnalysis) -> bool
    def get_expansion_recommendation(analysis) -> ExpansionRecommendation
```

## Testing

The FOV context system has comprehensive test coverage:

```bash
# Run all FOV context tests
cd server && python3 -m pytest management/fov_context/tests/ -v

# Run specific test files
python3 -m pytest management/fov_context/tests/test_models.py -v
python3 -m pytest management/fov_context/tests/test_manager.py -v
python3 -m pytest management/fov_context/tests/test_confidence.py -v
python3 -m pytest management/fov_context/tests/test_session.py -v
```

**Test Coverage:**
- Model tier classification
- Token budget calculations
- Buffer rendering and truncation
- Context building with all buffer layers
- Confidence marker detection
- Trend analysis
- Expansion recommendations
- Session lifecycle
- Event tracking

## Design Rationale

### Why Foveated Context?

1. **Efficient Token Usage**: Different information has different relevance levels. A 90-minute tutoring session generates thousands of turns, but only recent ones matter for the current question.

2. **Fast Barge-in Response**: When a user interrupts, we need context immediately. Pre-computed buffers enable sub-100ms context assembly.

3. **Adaptive Scaling**: Cloud models (128K context) can hold more history; on-device models (8K context) need aggressive compression.

4. **Curriculum Awareness**: The AI tutor needs awareness of where we are in the curriculum, what's coming next, and what was already covered.

### Why Server-Side?

The FOV context is implemented primarily on the server because:

1. **LLM Integration**: The server handles LLM calls, especially for barge-in scenarios
2. **Cross-Client Consistency**: Same context logic for iOS, Web, and Android clients
3. **Session Persistence**: Server can maintain session state across client reconnections
4. **Resource Efficiency**: Context computation on server, not on mobile device

### Why Confidence Monitoring?

Uncertainty detection prevents the "confident nonsense" problem:

1. **Early Detection**: Catch uncertainty before the user notices
2. **Automatic Recovery**: Expand context and re-prompt without user intervention
3. **Learning Signals**: Repeated uncertainty on a topic indicates need for better content
4. **Quality Assurance**: Track confidence trends to improve curriculum

## Related Documentation

- [TRANSCRIPT_DRIVEN_TUTORING.md](../TRANSCRIPT_DRIVEN_TUTORING.md): Tiered tutoring approach
- [CURRICULUM_SESSION_UX.md](../CURRICULUM_SESSION_UX.md): Session playback experience
- [ios/SPEAKER_MIC_BARGE_IN_DESIGN.md](../ios/SPEAKER_MIC_BARGE_IN_DESIGN.md): Voice interruption handling
- [PATCH_PANEL_ARCHITECTURE.md](PATCH_PANEL_ARCHITECTURE.md): LLM routing system
- [../curriculum/README.md](../../curriculum/README.md): UMCF curriculum format

---

*Last updated: January 2025*
