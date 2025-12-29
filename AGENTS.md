# AI Development Guidelines for UnaMentis

## Development Model

This project is developed with **100% AI assistance**. All code, tests, documentation, and architecture decisions are made collaboratively between human direction and AI implementation.

## Monorepo Structure

This repository contains multiple components, each with its own AGENTS.md:

| Component | Location | Purpose |
|-----------|----------|---------|
| iOS App | `UnaMentis/` | Swift/SwiftUI voice tutoring client |
| Server | `server/` | Backend infrastructure |
| Management Console | `server/management/` | Python/aiohttp content admin (port 8766) |
| Operations Console | `server/web/` | Next.js/React DevOps monitoring (port 3000) |
| Importers | `server/importers/` | Curriculum import framework |
| Curriculum | `curriculum/` | UMLCF format specification |

See the AGENTS.md in each directory for component-specific instructions.

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

On December 11, 2025, the entire UnaMentis iOS app (Phases 1-5 of a 12-week roadmap) was implemented in approximately 5 hours:

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
UnaMentis/
├── Core/           # Core business logic
│   ├── Audio/      # Audio pipeline, VAD integration
│   ├── Curriculum/ # Curriculum management, progress tracking
│   └── Telemetry/  # Metrics, cost tracking, observability
├── Services/       # External service integrations (STT, TTS, LLM)
├── UI/             # SwiftUI views
└── Persistence/    # Core Data stack

UnaMentisTests/
├── Unit/           # Unit tests (run frequently)
├── Integration/    # Integration tests
└── Helpers/        # Test utilities, mock services

server/
├── management/     # Management Console (port 8766) - curriculum, users, content
│   └── static/     # HTML/JS frontend
├── database/       # Curriculum database
└── web/            # Operations Console (port 3000) - system monitoring
```

### Web Interfaces

There are TWO separate web interfaces. Do not confuse them:

| Interface | Port | Purpose | Tech |
|-----------|------|---------|------|
| **Operations Console** | 3000 | DevOps: system health, services, logs, metrics | React/TypeScript |
| **Management Console** | 8766 | Content: curriculum, users, progress, assets | Python/vanilla JS |

**Operations Console (port 3000)** is for backend infrastructure:
- System health (CPU, memory, thermal, battery)
- Service status (Ollama, VibeVoice, Piper)
- Power/idle management
- Logs, metrics, client connections

**Management Console (port 8766)** is for everything else:
- Curriculum management (import, browse, edit, visual assets)
- User progress tracking and analytics
- Source browser for external curriculum (MIT OCW, Stanford, etc.)
- AI enrichment pipeline
- User management (future)

### Build & Test Commands
```bash
# Build for simulator
xcodebuild -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run all tests
xcodebuild test -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run specific test class
xcodebuild test -project UnaMentis.xcodeproj -scheme UnaMentis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnaMentisTests/ProgressTrackerTests
```

---

## Working with This Codebase

### Before Implementation
1. **Read the iOS Style Guide**: `docs/IOS_STYLE_GUIDE.md` (MANDATORY)
2. Read relevant tests first - they document expected behavior
3. Check existing patterns in similar components
4. Reference `docs/UnaMentis_TDD.md` for architectural decisions

### During Implementation
1. Write tests first (TDD)
2. Ensure Swift 6 concurrency compliance (@MainActor, Sendable, actors)
3. Run build frequently to catch issues early
4. Use TodoWrite to track progress on multi-step tasks
5. **Follow iOS Style Guide requirements for accessibility and i18n**

### CRITICAL: Definition of Done

**YOU MUST RUN TESTS BEFORE DECLARING WORK COMPLETE.** This is the most important rule.

Work is NOT complete until you have:
1. Run `./scripts/lint.sh` and verified 0 violations
2. Run `./scripts/test-quick.sh` and verified ALL tests pass
3. Actually observed the test output yourself (not assumed it passes)

**FAILURE MODE TO AVOID:**
- Writing code, seeing it compile, and telling the user "done"
- Summarizing accomplishments without running tests first
- Saying "tests should pass" instead of "tests pass" (you ran them)

If you tell the user "implementation is complete" when tests are failing, you have failed at your job.

### Quality Gates
- All tests pass (you must verify by running them)
- Build succeeds for iOS Simulator
- No force unwraps (!)
- Public APIs documented with /// comments
- Code follows existing patterns in the codebase
- **Accessibility labels on all interactive elements** (per iOS Style Guide)
- **Localizable strings for all user-facing text** (per iOS Style Guide)
- **iPad adaptive layouts using size class detection** (per iOS Style Guide)

### Server Work Completion Requirements

**When modifying server code (Management Console, Operations Console, or any Python/Node backend), you MUST:**

1. **Restart the affected server** after making code changes
2. **Verify the changes are working** by testing the modified functionality
3. **Check server logs** to confirm the new code is running (look for expected log output)

This is non-negotiable. Server work is NOT complete until:
- The server has been restarted with your changes
- You have verified the changes work as expected
- You have confirmed via logs or API calls that your code is active

**Why:** Unlike compiled code where build success confirms the code will run, server code changes only take effect after restart. Telling the user to restart the server means you haven't verified your work actually functions.

**How to restart:**
```bash
# Management Console (port 8766)
pkill -f "server/management/server.py"
cd server/management && python server.py &

# Operations Console (port 3000)
# Usually auto-reloads, but if needed:
cd server/web && npm run dev
```

**How to verify:**
- Make API calls to test modified endpoints
- Check server logs for expected log messages
- Confirm the browser shows updated behavior (if UI was changed)

---

## Technical Specifications

### Performance Targets
- E2E turn latency: <500ms (median), <1000ms (P99)
- 90-minute session stability without crashes
- Memory growth: <50MB over 90 minutes

### Cost Targets
- Balanced preset: <$3/hour
- Cost-optimized: <$1.50/hour

See `docs/UnaMentis_TDD.md` for complete specifications.

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
- `MockLLMService` - LLM API calls cost money (in `UnaMentisTests/Helpers/MockServices.swift`)
- `MockEmbeddingService` - Embedding API calls cost money (in `UnaMentisTests/Helpers/MockServices.swift`)

**Test Spies (for behavior verification):**
- `MockVADService` - A test spy (not a mock) that tracks method calls for verification while providing controllable VAD results. Located in `UnaMentisTests/Unit/AudioEngineTests.swift`. This is acceptable because:
  - VAD is on-device (Silero model), not a paid API
  - The spy allows testing AudioEngine's VAD integration without loading the ML model
  - It tracks `configureWasCalled`, `processBufferWasCalled`, and `lastConfiguration` for test assertions
  - It provides controllable `shouldDetectSpeech` and `speechConfidence` for testing different scenarios

**Should NOT be mocked (use real implementations):**
- `TelemetryEngine` - Internal, use real with in-memory store
- `PersistenceController` - Use `PersistenceController(inMemory: true)`
- File operations - Use temp directories
- Cosine similarity, chunking, etc. - Test real implementations

### Test Data Helpers

`TestDataFactory` (in `UnaMentisTests/Helpers/MockServices.swift`) provides helpers for creating test data:
- `createCurriculum(in:name:topicCount:)` - Creates test curricula with optional topics
- `createTopic(in:title:orderIndex:mastery:)` - Creates test topics
- `createDocument(in:title:type:content:summary:)` - Creates test documents
- `createProgress(in:for:timeSpent:quizScores:)` - Creates test progress records

These are NOT mocks. They create real Core Data entities in an in-memory store.
