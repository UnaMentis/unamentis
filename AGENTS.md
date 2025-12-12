# AI Development Guidelines for VoiceLearn

## Development Model

This project is developed with **100% AI assistance**. All code, tests, documentation, and architecture decisions are made collaboratively between human direction and AI implementation.

## Time Estimation Guidelines

### DO NOT use traditional software development timelines

Traditional estimates assume:
- Human typing speed and cognitive load
- Meeting overhead and context switching
- Learning curves and documentation reading
- Code review cycles with async feedback
- 6-8 productive hours per day

### DO use AI-assisted development timelines

AI-assisted development enables:
- Parallel exploration and implementation
- Instant context recall across entire codebase
- Continuous iteration without fatigue
- Real-time code review and correction
- 10-100x speedup on implementation tasks

### Calibration Data (This Project)

On December 11, 2025, the entire VoiceLearn iOS app (Phases 1-5 of a 12-week roadmap) was implemented in approximately 5 hours:

| Scope | Traditional Estimate | AI-Assisted Actual |
|-------|---------------------|-------------------|
| Full iOS app (Phases 1-5) | 10 weeks | ~5 hours |
| Single subsystem (Curriculum) | 2-4 weeks | ~2 hours |
| New feature with tests | 1-2 weeks | 30-60 minutes |
| Bug fix with regression test | 1-2 days | 5-15 minutes |

**Speedup Factor:** ~200x faster than traditional human team estimates

### When Providing Estimates

1. **Relative sizing is useful** - "This is 2x the complexity of the Curriculum system"
2. **Absolute timelines need context** - Always specify "AI-assisted" or "human team"
3. **The long tail matters** - Initial implementation is fast; polish/edge cases take proportionally longer
4. **Phase 6 is different** - Optimization, testing, and hardening don't parallelize as well

---

## Project Architecture

### Core Patterns
- **Swift 6.0 strict concurrency** - All services are actors
- **Protocol-first design** - Services defined by protocols, swappable implementations
- **TDD methodology** - Tests written before implementation
- **Real implementations in tests** - Only mock truly external dependencies (see Testing Philosophy below)

### Key Directories
```
VoiceLearn/
├── Core/           # Core business logic
│   ├── Audio/      # Audio pipeline, VAD integration
│   ├── Curriculum/ # Curriculum management, progress tracking
│   └── Telemetry/  # Metrics, cost tracking, observability
├── Services/       # External service integrations (STT, TTS, LLM)
├── UI/             # SwiftUI views
└── Persistence/    # Core Data stack

VoiceLearnTests/
├── Unit/           # Unit tests (run frequently)
├── Integration/    # Integration tests
└── Helpers/        # Test utilities, mock services
```

### Build & Test Commands
```bash
# Build for simulator
xcodebuild -project VoiceLearn.xcodeproj -scheme VoiceLearn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run all tests
xcodebuild test -project VoiceLearn.xcodeproj -scheme VoiceLearn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run specific test class
xcodebuild test -project VoiceLearn.xcodeproj -scheme VoiceLearn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VoiceLearnTests/ProgressTrackerTests
```

---

## Working with This Codebase

### Before Implementation
1. Read relevant tests first - they document expected behavior
2. Check existing patterns in similar components
3. Reference `docs/VoiceLearn_TDD.md` for architectural decisions

### During Implementation
1. Write tests first (TDD)
2. Ensure Swift 6 concurrency compliance (@MainActor, Sendable, actors)
3. Run build frequently to catch issues early
4. Use TodoWrite to track progress on multi-step tasks

### Quality Gates
- All tests pass
- Build succeeds for iOS Simulator
- No force unwraps (!)
- Public APIs documented with /// comments
- Code follows existing patterns in the codebase

---

## Technical Specifications

### Performance Targets
- E2E turn latency: <500ms (median), <1000ms (P99)
- 90-minute session stability without crashes
- Memory growth: <50MB over 90 minutes

### Cost Targets
- Balanced preset: <$3/hour
- Cost-optimized: <$1.50/hour

See `docs/VoiceLearn_TDD.md` for complete specifications.

---

## Multi-Agent Coordination

This project may have multiple AI agents working on it simultaneously (Claude Code, Cursor, Windsurf, ChatGPT, etc.). To prevent duplicate work and ensure smooth collaboration, all agents must follow this protocol.

### Task Status Document

**Location:** `docs/TASK_STATUS.md`

This document is the single source of truth for what's being worked on.

### Protocol for ALL AI Agents

1. **Before ANY work**: Read `docs/TASK_STATUS.md` first
2. **Claim your task**: Add an entry to "Currently Active" with your agent/tool name and timestamp
3. **Check for conflicts**: Do not work on tasks another agent has already claimed
4. **Update on completion**: Move your task to "Completed" section with notes
5. **Note blockers**: If you hit a blocker, add it to "Blocked/Pending" section

### Why This Matters

Without coordination:
- Two agents might implement the same feature differently
- One agent might break code another is actively working on
- Time gets wasted on duplicate effort

With coordination:
- Clear visibility into who's doing what
- Async collaboration between different AI tools
- Audit trail of progress

---

## Writing Style Guidelines

All AI agents must follow these style rules when writing documentation, comments, and any text in this project.

### Punctuation Rules

**Never use em dashes or en dashes as sentence interrupters.** This is a strict rule.

- Wrong: "The feature — which was added last week — improves performance"
- Wrong: "The feature – which was added last week – improves performance"
- Correct: "The feature, which was added last week, improves performance"
- Also correct: "The feature improves performance. It was added last week."

Use commas for parenthetical phrases. Use periods to break up long sentences. Do not use dashes as a substitute for commas or to set off phrases.

### General Style

- Be concise and direct
- Use active voice
- Avoid jargon unless it's standard in the domain
- Match the existing tone and style of the codebase

---

## Testing Philosophy: Real Over Mock

**Mock testing is unacceptable for most scenarios.** Tests should exercise real code paths to provide genuine confidence in behavior.

### When Mocking is VALID

Mocks are only acceptable for:

1. **Paid third-party APIs** (LLM, Embeddings, TTS, STT)
   - These cost money per request
   - Would make CI/CD expensive
   - Rate limiting could break builds

2. **APIs requiring credentials we don't have**
   - Interim situation during development
   - Should be replaced with real tests once credentials exist

3. **Unreliable external services**
   - Services with unpredictable uptime
   - But only if local alternatives don't exist

### When Mocking is NOT ACCEPTABLE

Do NOT mock:

1. **Internal services** (TelemetryEngine, PersistenceController, etc.)
   - Use the real implementation with in-memory stores
   - These are free to run and deterministic

2. **File system operations**
   - Use temp directories, clean up after

3. **Core Data**
   - Use `PersistenceController(inMemory: true)`

4. **Free external APIs**
   - If it doesn't cost money and doesn't require credentials, test against the real thing

5. **Local computations**
   - Cosine similarity, text chunking, etc. should always be tested with real implementations

### Mock Requirements (When Mocking is Necessary)

When you must mock, the mock must be **faithful and realistic**:

1. **Reproduce real API behavior**
   - Return data in the exact same format
   - Emit tokens/chunks at realistic intervals
   - Track input/output token counts accurately

2. **Simulate all error conditions the real API produces**
   - Rate limiting (with retry-after values)
   - Authentication failures
   - Network timeouts
   - Invalid request errors
   - Content filtering
   - Context length exceeded
   - Quota exceeded

3. **Validate inputs like the real API**
   - Check that requests are well-formed
   - Throw appropriate errors for malformed requests

4. **Match realistic performance characteristics**
   - Simulate TTFT (time to first token)
   - Simulate inter-token streaming delays
   - Optionally respect rate limits in stress tests

### Example: Good vs Bad Mocks

**Bad Mock (unacceptable):**
```swift
actor BadMockLLM: LLMService {
    func streamCompletion(...) async throws -> AsyncStream<LLMToken> {
        // Single token, no validation, no realistic behavior
        return AsyncStream { $0.yield(LLMToken(content: "response", isDone: true)); $0.finish() }
    }
}
```

**Good Mock (faithful):**
```swift
actor FaithfulMockLLM: LLMService {
    var shouldSimulateRateLimit = false
    var responseText = "Default response"

    func streamCompletion(messages: [LLMMessage], config: LLMConfig) async throws -> AsyncStream<LLMToken> {
        // Validate inputs like real API
        guard !messages.isEmpty else {
            throw LLMError.invalidRequest("Messages cannot be empty")
        }
        if config.maxTokens > 4096 {
            throw LLMError.contextLengthExceeded(maxTokens: 4096)
        }

        // Simulate rate limiting
        if shouldSimulateRateLimit {
            throw LLMError.rateLimited(retryAfter: 30)
        }

        return AsyncStream { continuation in
            Task {
                // Simulate realistic TTFT (150ms)
                try? await Task.sleep(nanoseconds: 150_000_000)

                // Stream tokens with realistic delays
                let words = responseText.split(separator: " ")
                for (index, word) in words.enumerated() {
                    let isLast = index == words.count - 1
                    let token = LLMToken(
                        content: String(word) + (isLast ? "" : " "),
                        isDone: isLast,
                        stopReason: isLast ? .endTurn : nil,
                        tokenCount: 1
                    )
                    continuation.yield(token)
                    // 20ms between tokens
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                continuation.finish()
            }
        }
    }
}
```

### Current Mock Inventory

**Valid mocks (external paid APIs):**
- `MockLLMService` - LLM API calls cost money
- `MockEmbeddingService` - Embedding API calls cost money

**Should NOT be mocked (use real implementations):**
- `TelemetryEngine` - Internal, use real with in-memory store
- `PersistenceController` - Use `PersistenceController(inMemory: true)`
- File operations - Use temp directories
- Cosine similarity, chunking, etc. - Test real implementations
