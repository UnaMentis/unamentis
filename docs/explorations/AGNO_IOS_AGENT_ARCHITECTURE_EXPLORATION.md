# Agno Framework: iOS Agent Architecture Exploration

**Date**: 2026-02-28
**Status**: Exploration
**Context**: Hackathon preparation for farming voice AI assistant with Agno server backend and iOS client with graceful on-device fallback

## Overview

This document explores using the Agno agent framework as the server-side core for a voice AI assistant, and investigates how to mirror lightweight Agno components on iOS to create a seamless, gracefully degrading client-server architecture. The goal: if the server is available, the full agent runs there with maximum capability; if not, the on-device agent handles what it can transparently.

## What Is Agno?

Agno (formerly PhiData) is an open-source Python agent framework with 38k+ GitHub stars, Apache 2.0 license. It provides three architectural layers:

1. **SDK Layer**: Python abstractions for agents, tools, memory, knowledge, guardrails, and 100+ integrations
2. **Engine Layer**: Runtime handling model invocation, tool execution, streaming, structured outputs, and session management
3. **AgentOS Layer**: Pre-built FastAPI application with 50+ endpoints, JWT authentication, SSE streaming, tracing

**Key stats**: 99.7% Python, 45+ LLM providers, 120+ built-in tools, 15+ database backends, 22 vector DB adapters, 19 embedding providers.

### Core Components

| Module | Purpose |
|--------|---------|
| `agent/` | Core autonomous reasoning entity combining model, tools, memory |
| `team/` | Multi-agent coordination with delegation modes |
| `workflow/` | Sequential/parallel task orchestration |
| `models/` | Abstract Model base + 45+ provider implementations |
| `tools/` | Function class, @tool decorator, 120+ built-in toolkits, MCP integration |
| `memory/` | MemoryManager for user memories, session summaries |
| `knowledge/` | RAG system: readers, chunkers, embedders, vector search |
| `db/` | 15+ transactional database backends |
| `vectordb/` | 22 vector database adapters |
| `os/` | AgentOS FastAPI server, auth, routers, tracing |

### Agent Execution Flow

```
1. Load AgentSession from database (if session_id exists)
2. Add historical context from previous runs
3. Assemble context: system message + instructions + user input +
   chat history + user memories + session state
4. Invoke model with tools
5. If tool_calls returned:
   - Execute pre-hooks
   - Execute function with parsed arguments
   - Execute post-hooks
   - Return tool results to model
   - LOOP back to step 4
6. Model returns final content (no more tool calls)
7. Save updated AgentSession to database
8. Return RunOutput with content, metrics, messages
```

The agent class instantiates in <5 microseconds and uses ~3.75 KiB of memory. The execution loop is ~200 lines of state machine logic.

## Architecture Split: Lightweight vs Heavy

### Lightweight / Portable (could run on device)

- **Agent class**: Configuration container + state machine, stateless between runs
- **Tool definitions**: Callables with type annotations converted to JSON schemas
- **RunContext / session_state**: Simple dictionary
- **Message types**: Pydantic models (map to Swift Codable structs)
- **Model protocol**: Abstract interface with 4 methods (invoke, ainvoke, invoke_stream, ainvoke_stream)
- **Media classes**: Simple data containers for Image/Audio/Video/File references

### Heavy / Server-Side

- **AgentOS (FastAPI server)**: 50+ REST endpoints, SSE streaming, JWT auth
- **PostgreSQL + PgVector**: Production session persistence and vector search
- **Knowledge ingestion pipeline**: Reader, Chunker, Embedder, VectorDB (CPU/GPU intensive)
- **120+ tool integrations**: All Python-ecosystem specific
- **Multi-agent Teams**: Complex coordination overhead
- **Tracing/Observability**: Database-backed span collection

### Critical Insight

The orchestration logic and infrastructure are cleanly separated via abstract base classes:

- `Model` (abstract) separates orchestration from LLM providers
- `BaseDb` (abstract) separates orchestration from databases
- `VectorDb` (abstract) separates orchestration from vector storage
- `Embedder` (abstract) separates orchestration from embedding providers
- `KnowledgeProtocol` separates orchestration from RAG implementations

This means the ~5-10 core files of orchestration logic can be reimplemented in Swift or Rust, with iOS-native implementations behind the same interfaces.

## iOS Porting Strategies

### Strategy 1: Swift-Native Agent (Recommended for Hackathon)

Build a minimal agent loop in Swift using Apple's Foundation Models framework (iOS 26+) for on-device LLM and the SwiftAgent framework for agent architecture.

**SwiftAgent** (github.com/1amageek/SwiftAgent):
- Declarative, SwiftUI-like syntax for composing agent steps
- Supports Foundation Models (on-device 3B), OpenAI, Claude, Ollama
- MCP tool integration built-in
- Step types: Transform, Generate, Gate, Loop, Map, Reduce, Parallel, Race, Pipeline
- Requires iOS 26+, Swift 6.2+

**Apple Foundation Models** (WWDC 2025):
- On-device 3B parameter LLM with native tool calling
- Guided generation (structured output)
- Native Swift API, zero cloud cost
- Works offline, 15 language support

**Effort**: ~500-1,000 lines of Swift for the on-device agent

```
iOS App
  +-- Swift Agent Loop
        |-- Foundation Models 3B (on-device, free)
        |-- Local tools via Tool protocol
        |-- Complexity router -> delegates to server when needed
        +-- AG-UI/WebSocket <-> Server Agno Agent
```

### Strategy 2: Rust Core with UniFFI Bindings (Best for Production)

Build the agent runtime in Rust using the Rig framework or ADK-Rust, then generate Swift bindings via UniFFI. Same core runs on server and iOS.

**Rig** (github.com/0xPlaygrounds/rig):
- Most mature Rust agent framework
- Unified interface for 20+ LLM providers
- 10+ vector store integrations
- Full WASM compatibility
- Agent builder pattern with tool calling, RAG, reasoning

**ADK-Rust** (github.com/zavora-ai/adk-rust):
- Rust port of Google's Agent Development Kit
- Agent types: LlmAgent, SequentialAgent, ParallelAgent, LoopAgent
- MCP support, sessions, memory, streaming
- Realtime voice agent support with bidirectional audio streaming

**Effort**: ~800-1,200 lines Rust + UniFFI bindings

```
iOS App                          Server
  +-- Swift UI Layer               +-- Agno (Python) or Rust Agent
        +-- UniFFI Bindings              +-- Same Rust core
              +-- Rust Agent Core              +-- Full LLM + RAG + Memory
                    |-- On-device LLM (callback to Swift FoundationModels)
                    +-- AG-UI protocol <-> Server
```

### Strategy 3: Thin Client + Server Agno (Simplest)

iOS is just a voice UI. All agent logic runs server-side in Agno. Communication via AG-UI protocol.

**Effort**: Minimal iOS work, standard API client
**Tradeoff**: No offline capability, no graceful degradation

### Why NOT Embed Python on iOS

- CPython 3.13+ supports iOS (PEP 730) but adds ~50-100MB
- No multiprocessing, no dynamic code loading, no stdin/stdout
- GIL limits concurrency
- Binary module packaging is painful
- Performance overhead unacceptable for real-time voice

## Seamless Handoff Architecture

### Protocol Stack

| Layer | Protocol | Purpose |
|-------|----------|---------|
| Events | AG-UI | Agent lifecycle, streaming text, tool calls, state sync |
| Tools | MCP | Tool discovery and invocation across device/server boundary |
| Transport | WebSocket/SSE | Bidirectional for voice, SSE for text-only |

### AG-UI Protocol

An open standard for agent-frontend communication that Agno already supports. 16 event types covering lifecycle, text messages, tool calls, and state management. Works over SSE or WebSocket.

Agno has AG-UI support in `cookbook/agent_os/interfaces/agui/`.

### MCP (Model Context Protocol)

Tool-level interoperability across the device/server boundary. Official Swift MCP SDK (github.com/modelcontextprotocol/swift-sdk) supports iOS 16+. Apple is adding system-level MCP support in iOS 26.

This lets the on-device agent discover and call server tools dynamically, and vice versa.

### Complexity Router

On-device logic that decides whether to handle locally or delegate to server:

```
User speaks -> STT -> Text
                       |
               +-------v--------+
               | Complexity      |
               | Router          |
               +---+--------+---+
                   |        |
          Simple   |        |  Complex
                   |        |
     +-------------v-+  +--v--------------+
     | On-Device      |  | Server Agent     |
     | Foundation 3B  |  | (Agno + Claude)  |
     | Local tools    |  | Full RAG/Memory  |
     | Session memory |  | All tools        |
     +-------+--------+  +-------+----------+
             |                    |
             +--------+-----------+
                      |
               +------v------+
               | Unified      |
               | Response     |
               | Stream       |
               +------+-------+
                      |
                 Text -> TTS -> User hears
```

Simple routing heuristic:
- Needs RAG/knowledge lookup? -> Server
- Needs multi-step reasoning? -> Server
- Needs tools only available server-side? -> Server
- Simple Q&A, follow-ups, basic lookups? -> On-device
- Server unreachable? -> On-device with degraded capability

The user never knows where processing happened. Both paths produce the same response format streamed through the same voice pipeline.

## What Would Need Reimplementing for iOS

### Straightforward (~200-400 lines of Swift)

1. **Agent execution loop**: State machine (build messages, call model, handle tools, loop)
2. **Message/Response types**: Pydantic models map to Swift structs with Codable
3. **Model protocol**: 4 abstract methods map to Swift protocol with async/await
4. **Tool system**: Function + JSON Schema maps to Swift protocol + Encodable
5. **Session types**: Simple data classes map to Swift structs

### Moderate Effort (iOS-native replacements)

1. **LLM providers**: Implement 2-3 (Foundation Models on-device, OpenAI-compatible, Anthropic) using URLSession
2. **Session storage**: Core Data or SQLite instead of 15 backends
3. **Hooks/guardrails**: Swift closures instead of Python callables

### Server-Side Only

1. **RAG pipeline**: Document readers, embedders, vector DBs
2. **120+ tools**: Replace with iOS-native tools
3. **Team/Workflow**: Complex multi-agent orchestration
4. **AgentOS**: FastAPI server infrastructure

## Existing iOS/Rust Agent Frameworks

### Swift

| Project | Description |
|---------|-------------|
| SwiftAgent | Declarative agent SDK, FoundationModels compatible |
| SwiftAIAgent | Lightweight AI agent framework |
| Foundation Models Playgrounds | ReAct, PlanExecute, Reflection agent loops (reference implementations) |
| LLM.swift | Simple library for local LLM interaction |
| LocalLLMClient | Swift package supporting MLX and llama.cpp backends |

### Rust

| Project | Description |
|---------|-------------|
| Rig | Most mature Rust agent framework, WASM compatible |
| ADK-Rust | Rust port of Google ADK, voice agent support |
| Swarm | Multi-agent orchestration with MCP and A2A |

## Hackathon Plan

### Recommended Approach: Strategy 1 + 3 Combined

1. **Server**: Stand up Agno with farming domain knowledge, tools, and Claude/GPT-4o. Use AgentOS for instant REST/SSE API.

2. **iOS**: Build minimal Swift agent with Foundation Models for simple queries. WebSocket client talks AG-UI to server for complex ones.

3. **Router**: For hackathon, always route to server but demonstrate the architecture. If server unreachable, fall back to Foundation Models on-device. This demonstrates graceful degradation.

4. **MCP for tools**: Use Swift MCP SDK so iOS agent discovers server-side tools dynamically. The on-device agent doesn't hardcode what the server can do.

### Minimum Viable Components

| Component | On-Device | Server |
|-----------|-----------|--------|
| Agent loop | Swift (~500 lines) | Agno (Python) |
| LLM | Foundation Models 3B | Claude/GPT-4o via Agno |
| Tools | Local (audio, session state) | Domain tools (crop DB, weather API, etc.) |
| Memory | In-memory + Core Data | PostgreSQL |
| Protocol | AG-UI client | AG-UI server (Agno built-in) |
| Tool discovery | MCP client (Swift SDK) | MCP server (Agno built-in) |

## Full Port Feasibility Assessment

Porting Agno fully to iOS is neither practical nor necessary:

- 99.7% Python with deep ecosystem dependencies
- 120+ tools, 22 vector DBs, 15 DB backends are all Python-specific
- Running Python on iOS adds ~50-100MB with severe limitations

What IS practical: reimplementing the ~5-10 core orchestration files (~200-400 lines of actual logic) in Swift or Rust. Everything else plugs in behind abstract interfaces that map cleanly to Swift protocols. The Rig and SwiftAgent frameworks have already done much of this work.

For production (post-hackathon), the Rust UniFFI approach provides true code sharing across iOS, Android, server, and web (via WASM) with the same agent runtime everywhere.

## Key Resources

| Resource | URL |
|----------|-----|
| Agno repo | github.com/agno-agi/agno |
| Agno docs | docs.agno.com |
| SwiftAgent | github.com/1amageek/SwiftAgent |
| Rig (Rust agents) | github.com/0xPlaygrounds/rig |
| ADK-Rust | github.com/zavora-ai/adk-rust |
| MCP Swift SDK | github.com/modelcontextprotocol/swift-sdk |
| AG-UI Protocol | docs.ag-ui.com |
| Apple Foundation Models | developer.apple.com/documentation/FoundationModels |
| EcoAgent (device-cloud agents) | arxiv.org/abs/2505.05440 |
| Agno AG-UI cookbook | github.com/agno-agi/agno/tree/main/cookbook/agent_os/interfaces/agui |
| Foundation Models Playgrounds | github.com/IvanCampos/Foundation-Models-Playgrounds |
