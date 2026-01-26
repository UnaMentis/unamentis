# UnaMentis: Scaling, Security & Multi-Tenancy Analysis

**Prepared by**: Security Architecture Review
**Date**: December 2024
**Classification**: Internal - Technical Leadership
**Scope**: Complete ecosystem analysis (iOS client, server infrastructure, data layer)

---

## Executive Summary

This document provides an uncompromising security and privacy analysis of the UnaMentis voice AI tutoring platform, examining its readiness to scale from beta testing (10-50 users) through mass adoption (millions of users), with particular focus on multi-tenant isolation for organizational deployments.

### Critical Finding Summary

| Category | Current State | Production Readiness |
|----------|---------------|---------------------|
| **Authentication** | None | 🔴 NOT READY |
| **Multi-Tenancy** | None | 🔴 NOT READY |
| **Data Encryption** | None (at rest) | 🔴 NOT READY |
| **Network Security** | Partial (HTTPS for external APIs only) | 🟡 PARTIAL |
| **Privacy Compliance** | Partial (export exists, gaps in consent) | 🟡 PARTIAL |
| **Scalability** | Single-instance design | 🟡 PARTIAL |

### The Uncompromising Privacy Principle

This analysis adopts the principle that user data is **never** monetizable, sellable, or accessible for purposes beyond the user's explicit educational intent. This means:

- No analytics that could profile users for advertising
- No data sharing with third parties beyond essential service providers
- No retention beyond user-controlled periods
- No administrative "backdoors" to access user learning content
- Complete data portability and deletion on demand

---

## Table of Contents

1. [Current Architecture Overview](#1-current-architecture-overview)
2. [Security Assessment](#2-security-assessment)
3. [Privacy Architecture Analysis](#3-privacy-architecture-analysis)
4. [Multi-Tenancy Requirements](#4-multi-tenancy-requirements)
5. [Scaling Roadmap](#5-scaling-roadmap)
6. [Implementation Priorities](#6-implementation-priorities)
7. [Appendix: File Reference](#7-appendix-file-reference)

---

## 1. Current Architecture Overview

### 1.1 System Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              UnaMentis Ecosystem                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐    │
│  │   iOS Client     │     │ Management       │     │  Web Console     │    │
│  │                  │     │ Console          │     │  (React)         │    │
│  │ • Swift 6.0      │     │ • Python/aiohttp │     │ • Next.js 16     │    │
│  │ • SwiftUI        │     │ • Port 8766      │     │ • Port 3000      │    │
│  │ • Core Data      │     │ • WebSocket      │     │ • TypeScript     │    │
│  └────────┬─────────┘     └────────┬─────────┘     └────────┬─────────┘    │
│           │                        │                        │               │
│           ▼                        ▼                        ▼               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         Data Layer                                   │   │
│  │  • Core Data (iOS) - SQLite, unencrypted                            │   │
│  │  • File-based JSON (Server) - UMCF curriculum files                 │   │
│  │  • PostgreSQL (optional) - No RLS, no encryption                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    External Service Providers                        │   │
│  │  • STT: Deepgram, AssemblyAI, OpenAI Whisper                        │   │
│  │  • TTS: ElevenLabs, Deepgram Aura                                   │   │
│  │  • LLM: OpenAI (GPT-4o), Anthropic (Claude)                         │   │
│  │  • Self-hosted: Ollama, Piper, VibeVoice, Whisper                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Data Flow Architecture

```
User Voice Input
       │
       ▼
┌──────────────────┐
│  AudioEngine     │ ◄─── AVAudioSession (16-48kHz PCM)
│  (On-Device)     │      Hardware AEC/AGC/NS
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  VAD (Silero)    │ ◄─── On-device voice activity detection
│  (On-Device)     │      No cloud transmission for VAD
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌─────────────────────────────────┐
│  STT Service     │────►│ Cloud: Deepgram/AssemblyAI      │
│  (Configurable)  │     │ Local: GLM-ASR/Apple Speech     │
└────────┬─────────┘     └─────────────────────────────────┘
         │
         ▼
┌──────────────────┐
│ TranscriptEntry  │ ◄─── Stored in Core Data (UNENCRYPTED)
│ (Core Data)      │      Full text of user speech
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌─────────────────────────────────┐
│  LLM Service     │────►│ Cloud: OpenAI/Anthropic         │
│  (Configurable)  │     │ Local: Ollama/On-device MLX     │
└────────┬─────────┘     └─────────────────────────────────┘
         │
         ▼
┌──────────────────┐     ┌─────────────────────────────────┐
│  TTS Service     │────►│ Cloud: ElevenLabs/Deepgram      │
│  (Configurable)  │     │ Local: Piper/VibeVoice          │
└────────┬─────────┘     └─────────────────────────────────┘
         │
         ▼
┌──────────────────┐
│  Audio Playback  │ ◄─── In-memory buffers only
│  (On-Device)     │      No audio persisted to disk
└──────────────────┘
```

### 1.3 Current Storage Model

| Data Type | Location | Encryption | Multi-Tenant Ready |
|-----------|----------|------------|-------------------|
| User Transcripts | Core Data (iOS) | ❌ None | ❌ No |
| Session Metrics | Core Data (iOS) | ❌ None | ❌ No |
| Learning Progress | Core Data (iOS) | ❌ None | ❌ No |
| API Keys | iOS Keychain | ✅ Hardware | N/A (per-device) |
| Curricula | JSON files (server) | ❌ None | ❌ No |
| Visual Assets | File system (server) | ❌ None | ❌ No |
| Client Logs | In-memory (server) | ❌ None | ❌ No |

---

## 2. Security Assessment

### 2.1 Authentication & Authorization

#### 2.1.1 Current State: NO AUTHENTICATION

**Management Console (Port 8766)**

The management server has **zero authentication**. Every endpoint is publicly accessible to anyone with network access:

```python
# server/management/server.py - Lines 3314-3327
@web.middleware
async def cors_middleware(request: web.Request, handler):
    response.headers["Access-Control-Allow-Origin"] = "*"  # CRITICAL VULNERABILITY
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, X-Client-ID, X-Client-Name"
```

**Impact**: Any attacker on the network can:
- Read all client logs (including user transcripts sent for debugging)
- Delete all curricula
- Start/stop system services
- Modify power profiles
- Access all metrics and telemetry

**iOS Client API Key Management**

The client does implement secure API key storage:

```swift
// UnaMentis/Core/Config/APIKeyManager.swift
// Keys stored in Keychain with kSecAttrAccessibleAfterFirstUnlock
// Priority: Keychain → Environment → UserDefaults (fallback)
```

However, these keys are for third-party services, not for authenticating to the UnaMentis backend.

#### 2.1.2 Required: Authentication Architecture

For production and multi-tenancy, implement:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Authentication Architecture                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────────┐ │
│  │ iOS Client  │───►│ Auth Layer  │───►│ Identity Provider           │ │
│  │             │    │ (Gateway)   │    │ • Self-hosted (recommended) │ │
│  │ • JWT Token │    │             │    │ • Auth0/Okta (optional)     │ │
│  │ • Refresh   │    │ • Validate  │    │ • SAML for Enterprise       │ │
│  │   Token     │    │ • Rate Limit│    │                             │ │
│  └─────────────┘    │ • Audit Log │    └─────────────────────────────┘ │
│                     └──────┬──────┘                                     │
│                            │                                            │
│                            ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Authorization Layer                           │   │
│  │  • Role-Based Access Control (RBAC)                             │   │
│  │  • Tenant isolation enforcement                                  │   │
│  │  • Resource-level permissions                                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Recommended Implementation**:

1. **JWT-based Authentication**
   - Short-lived access tokens (15 minutes)
   - Long-lived refresh tokens (7 days, revocable)
   - Token binding to device fingerprint
   - No token storage in localStorage (iOS Keychain only)

2. **Role-Based Access Control**
   ```
   Roles:
   ├── learner          # Can access own data only
   ├── instructor       # Can view learner progress in their courses
   ├── org_admin        # Can manage organization users and curricula
   ├── platform_admin   # Can manage multiple organizations (SaaS operator)
   └── system           # Internal service-to-service only
   ```

3. **API Key Scoping** (for programmatic access)
   - Read-only keys for analytics export
   - Write keys for curriculum import
   - Admin keys for user management
   - All keys tenant-scoped and rotatable

### 2.2 Network Security

#### 2.2.1 Current State

| Component | Protocol | TLS | Certificate Pinning |
|-----------|----------|-----|---------------------|
| Management Console | HTTP | ❌ | ❌ |
| Web Console | HTTP | ❌ | ❌ |
| OpenAI API | HTTPS | ✅ | ❌ |
| Anthropic API | HTTPS | ✅ | ❌ |
| Deepgram (WSS) | WSS | ✅ | ❌ |
| ElevenLabs (WSS) | WSS | ✅ | ❌ |
| Self-hosted servers | HTTP | ❌ | ❌ |

#### 2.2.2 Required: Network Hardening

**Certificate Pinning Implementation**:

```swift
// Required: Custom URLSessionDelegate for certificate pinning
class PinnedURLSessionDelegate: NSObject, URLSessionDelegate {
    private let pinnedCertificates: [String: [Data]] = [
        "api.openai.com": [/* SHA-256 public key hashes */],
        "api.anthropic.com": [/* SHA-256 public key hashes */],
        "api.deepgram.com": [/* SHA-256 public key hashes */],
        "api.elevenlabs.io": [/* SHA-256 public key hashes */]
    ]

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Validate certificate chain against pinned keys
        // Reject connections with mismatched certificates
    }
}
```

**TLS Requirements**:
- TLS 1.3 minimum for all connections
- HSTS headers on all server responses
- Certificate transparency logging
- OCSP stapling enabled

**Self-Hosted Server Security**:
- mTLS (mutual TLS) for service-to-service communication
- Private CA for internal certificates
- Automatic certificate rotation

### 2.3 Data Encryption

#### 2.3.1 Current State: NO ENCRYPTION AT REST

**iOS Client**:
```swift
// Core Data uses default SQLite storage
// Files located at: {app}/Documents/UnaMentis.sqlite
// NO application-level encryption
// Relies only on iOS file protection (insufficient for sensitive data)
```

**Server**:
```python
# Curriculum files stored as plain JSON
# Path: /curriculum/examples/realistic/*.json
# Visual assets unencrypted in: /curriculum/assets/
# PostgreSQL (if used): No column encryption, no TDE
```

#### 2.3.2 Required: Encryption Architecture

**Encryption at Rest**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Encryption Architecture                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  iOS Client:                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ • SQLCipher for Core Data (AES-256-CBC)                         │   │
│  │ • Key derived from: device key + user passphrase (optional)     │   │
│  │ • Secure Enclave for key storage                                │   │
│  │ • Automatic key rotation on app update                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Server:                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ • PostgreSQL with pgcrypto extension                            │   │
│  │ • Column-level encryption for sensitive fields                  │   │
│  │ • Envelope encryption: DEK encrypted by KEK                     │   │
│  │ • KEK stored in HSM or cloud KMS (AWS KMS, GCP Cloud KMS)       │   │
│  │ • Per-tenant encryption keys for isolation                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Key Management:                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ • Never store keys in code or config files                      │   │
│  │ • HSM-backed key generation                                     │   │
│  │ • Automatic rotation every 90 days                              │   │
│  │ • Key versioning for decrypt-during-rotation                    │   │
│  │ • Audit logging of all key access                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Fields Requiring Encryption**:

| Entity | Field | Sensitivity | Encryption Required |
|--------|-------|-------------|---------------------|
| TranscriptEntry | content | HIGH (user speech) | ✅ AES-256-GCM |
| Session | metricsSnapshot | MEDIUM | ✅ AES-256-GCM |
| Session | config | MEDIUM | ✅ AES-256-GCM |
| TopicProgress | quizScores | MEDIUM | ✅ AES-256-GCM |
| Document | content | LOW (curriculum) | Optional |
| Document | embedding | LOW (vectors) | Optional |

### 2.4 Input Validation & Injection Prevention

#### 2.4.1 Current Vulnerabilities

**Path Traversal** (server/management/server.py):
```python
# Line 1915 - Archive deletion accepts raw file_name
archived_path = archived_dir / file_name  # VULNERABLE
# Attacker could send: ../../../etc/passwd
```

**SSRF** (server/management/server.py):
```python
# Lines 2058-2077 - Arbitrary URL fetch
async with session.get(url) as response:  # VULNERABLE
    # No hostname validation, no allowlist
    # Attacker could fetch internal services
```

**Directory Traversal in Assets**:
```python
# Line 2197
assets_dir = PROJECT_ROOT / "curriculum" / "assets" / curriculum_id / topic_id
# curriculum_id and topic_id from user input, no sanitization
```

#### 2.4.2 Required: Input Validation

```python
# Required: Strict input validation
import re
from pathlib import Path

def validate_id(id_value: str) -> bool:
    """Only allow UUID format or alphanumeric with hyphens"""
    return bool(re.match(r'^[a-zA-Z0-9\-]{1,64}$', id_value))

def safe_path_join(base: Path, *parts: str) -> Path:
    """Prevent directory traversal"""
    result = base
    for part in parts:
        if not validate_id(part):
            raise ValueError(f"Invalid path component: {part}")
        result = result / part
    # Ensure result is still under base
    if not str(result.resolve()).startswith(str(base.resolve())):
        raise ValueError("Path traversal detected")
    return result

def validate_url(url: str, allowed_domains: list[str]) -> bool:
    """SSRF prevention - allowlist domains"""
    from urllib.parse import urlparse
    parsed = urlparse(url)
    return parsed.hostname in allowed_domains
```

### 2.5 Rate Limiting & DoS Protection

#### 2.5.1 Current State: MINIMAL

Only one rate limit exists:
```python
# Asset download rate limit (for Wikimedia compliance)
DOWNLOAD_RATE_LIMIT_SECONDS = 1.0  # 1 request per second
```

No rate limiting on:
- API endpoints
- Log submission
- Curriculum operations
- Service management

#### 2.5.2 Required: Comprehensive Rate Limiting

```python
# Required: Token bucket rate limiter
from dataclasses import dataclass
from time import time
from collections import defaultdict

@dataclass
class RateLimitConfig:
    requests_per_second: float
    burst_size: int

RATE_LIMITS = {
    "/api/logs": RateLimitConfig(10, 50),        # 10 req/s, burst 50
    "/api/curricula": RateLimitConfig(5, 20),    # 5 req/s, burst 20
    "/api/services/*": RateLimitConfig(1, 5),    # 1 req/s, burst 5 (admin ops)
    "/api/import/*": RateLimitConfig(0.1, 2),    # 1 req/10s, burst 2
    "default": RateLimitConfig(20, 100),         # 20 req/s default
}

class RateLimiter:
    def __init__(self):
        self.buckets = defaultdict(lambda: {"tokens": 0, "last_update": 0})

    def allow(self, client_id: str, endpoint: str) -> bool:
        config = self._get_config(endpoint)
        bucket = self.buckets[f"{client_id}:{endpoint}"]
        now = time()

        # Refill tokens
        elapsed = now - bucket["last_update"]
        bucket["tokens"] = min(
            config.burst_size,
            bucket["tokens"] + elapsed * config.requests_per_second
        )
        bucket["last_update"] = now

        # Check and consume
        if bucket["tokens"] >= 1:
            bucket["tokens"] -= 1
            return True
        return False
```

---

## 3. Privacy Architecture Analysis

### 3.1 Data Inventory & Classification

| Data Type | Classification | Retention | User Access | Deletion |
|-----------|---------------|-----------|-------------|----------|
| Voice Audio | Transient | Not stored | N/A | Automatic |
| Transcripts | Sensitive PII | Indefinite | Export ✅ | Manual ✅ |
| Learning Progress | Personal Data | Indefinite | Partial | Cascade |
| Session Metrics | Usage Data | Indefinite | Export ✅ | Manual ✅ |
| Device ID | Identifier | Session | Hidden | N/A |
| API Keys | Secret | Until removed | Hidden | Manual |

### 3.2 Third-Party Data Sharing

**Current Data Flows to External Services**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Third-Party Data Exposure                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Speech-to-Text (Cloud):                                                 │
│  ├── Deepgram: Raw audio (PCM) via WebSocket                            │
│  ├── AssemblyAI: Base64-encoded audio via WebSocket                     │
│  └── OpenAI Whisper: Audio files via HTTPS                              │
│      ⚠️  Full audio of user speech sent to third party                  │
│                                                                          │
│  Text-to-Speech (Cloud):                                                 │
│  ├── ElevenLabs: Full AI response text via WebSocket                    │
│  └── Deepgram Aura: Full AI response text via HTTPS                     │
│      ⚠️  Educational content + AI responses sent to third party         │
│                                                                          │
│  Language Models (Cloud):                                                │
│  ├── OpenAI: Full conversation history + system prompt                  │
│  └── Anthropic: Full conversation history + system prompt               │
│      ⚠️  Complete learning interaction sent to third party              │
│                                                                          │
│  Embeddings (Cloud):                                                     │
│  └── OpenAI: Curriculum document content                                │
│      ℹ️  Educational materials only (not user data)                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Privacy-First Architecture

**For uncompromising privacy, implement tiered data handling**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Privacy Tier Architecture                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  TIER 1: Maximum Privacy (On-Device Only)                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ • STT: Apple Speech Recognition (on-device)                      │   │
│  │ • STT: GLM-ASR On-Device                                         │   │
│  │ • TTS: Apple AVSpeechSynthesizer (on-device)                     │   │
│  │ • LLM: On-Device MLX models                                      │   │
│  │ • VAD: Silero (already on-device)                                │   │
│  │                                                                   │   │
│  │ Data exposure: ZERO - nothing leaves the device                  │   │
│  │ Trade-off: Lower quality, limited model capabilities             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  TIER 2: High Privacy (Self-Hosted)                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ • STT: Self-hosted Whisper (your infrastructure)                 │   │
│  │ • TTS: Piper or VibeVoice (your infrastructure)                  │   │
│  │ • LLM: Ollama with Llama/Mistral (your infrastructure)           │   │
│  │                                                                   │   │
│  │ Data exposure: Internal network only                             │   │
│  │ Trade-off: Infrastructure cost, moderate quality                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  TIER 3: Standard Privacy (Cloud with DPA)                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ • Use cloud providers with signed DPAs                           │   │
│  │ • Require zero-retention policies                                │   │
│  │ • Require SOC 2 Type II compliance                               │   │
│  │ • Contractual prohibition on training data use                   │   │
│  │                                                                   │   │
│  │ Data exposure: Third-party (contractually protected)             │   │
│  │ Trade-off: Highest quality, but data leaves your control         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.4 GDPR/CCPA Compliance Gaps

| Requirement | Current State | Gap |
|-------------|---------------|-----|
| Right to Access | Export exists | ✅ Compliant (needs enhancement) |
| Right to Deletion | Clear all exists | ⚠️ No selective deletion |
| Right to Portability | JSON export | ⚠️ Not machine-readable standard |
| Consent Collection | Toggle exists | ❌ No timestamp/signature |
| Privacy Policy | Link exists | ❌ Policy not implemented |
| Data Retention Limits | None | ❌ Indefinite storage |
| Breach Notification | None | ❌ No mechanism |
| DPO Contact | None | ❌ Not designated |

### 3.5 Required: Privacy Implementation

**Consent Management System**:

```swift
// Required: Proper consent tracking
struct ConsentRecord: Codable {
    let consentId: UUID
    let userId: UUID
    let consentType: ConsentType
    let granted: Bool
    let timestamp: Date
    let ipAddress: String?  // Hashed for audit, not tracking
    let appVersion: String
    let policyVersion: String

    enum ConsentType: String, Codable {
        case essentialProcessing    // Required for app function
        case cloudSTT               // Send audio to cloud STT
        case cloudTTS               // Send text to cloud TTS
        case cloudLLM               // Send conversations to cloud LLM
        case analytics              // Usage analytics (if any)
        case remoteDiagnostics      // Remote logging
    }
}
```

**Data Retention Policy**:

```swift
// Required: Automatic data cleanup
struct RetentionPolicy {
    static let sessionData: TimeInterval = 90 * 24 * 3600      // 90 days
    static let transcripts: TimeInterval = 30 * 24 * 3600      // 30 days
    static let progressData: TimeInterval = 365 * 24 * 3600    // 1 year
    static let auditLogs: TimeInterval = 7 * 365 * 24 * 3600   // 7 years (compliance)

    func scheduleCleanup() {
        // Background task to purge expired data
        // Secure deletion (overwrite before delete)
    }
}
```

---

## 4. Multi-Tenancy Requirements

### 4.1 Current State: ZERO MULTI-TENANCY

The system has no concept of tenants, organizations, or user isolation:

```python
# server/management/server.py
# All curricula visible to all clients
curricula = list(state.curriculums.values())  # No filtering

# All logs visible to all clients
logs = list(state.logs)  # No tenant isolation

# No tenant_id in any database table
# No organization concept in Core Data model
```

### 4.2 Multi-Tenancy Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Multi-Tenant Architecture                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Tenant Isolation Models                       │   │
│  ├─────────────────────────────────────────────────────────────────┤   │
│  │                                                                   │   │
│  │  Option A: Shared Database, Row-Level Security                   │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │ • Single PostgreSQL instance                             │    │   │
│  │  │ • tenant_id column on all tables                         │    │   │
│  │  │ • Row-Level Security policies enforce isolation          │    │   │
│  │  │ • Shared infrastructure, lower cost                      │    │   │
│  │  │ • Risk: RLS bypass vulnerability                         │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  │                                                                   │   │
│  │  Option B: Separate Schemas per Tenant                           │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │ • Single PostgreSQL instance                             │    │   │
│  │  │ • Each tenant gets own schema                            │    │   │
│  │  │ • Connection string includes schema                      │    │   │
│  │  │ • Better isolation, moderate cost                        │    │   │
│  │  │ • Easier compliance auditing                             │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  │                                                                   │   │
│  │  Option C: Separate Databases per Tenant (RECOMMENDED)          │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │ • Dedicated database per organization                    │    │   │
│  │  │ • Complete data isolation                                │    │   │
│  │  │ • Per-tenant encryption keys                             │    │   │
│  │  │ • Easy data export/deletion for compliance               │    │   │
│  │  │ • Higher cost, maximum security                          │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  │                                                                   │   │
│  │  Option D: Separate Infrastructure (Enterprise)                  │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │ • Dedicated servers/VMs per organization                 │    │   │
│  │  │ • Network isolation (VPC/subnet)                         │    │   │
│  │  │ • Custom domain and certificates                         │    │   │
│  │  │ • Maximum isolation for regulated industries             │    │   │
│  │  │ • Highest cost, highest security                         │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  │                                                                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Recommended: Hybrid Model

For UnaMentis, recommend a hybrid approach:

| Tier | Isolation Model | Use Case |
|------|-----------------|----------|
| Free/Individual | Shared DB + RLS | Individual learners |
| Team | Separate Schema | Small organizations (< 100 users) |
| Enterprise | Separate Database | Large organizations (100+ users) |
| Regulated | Dedicated Infrastructure | Healthcare, government, education |

### 4.4 Database Schema Changes

```sql
-- Required: Tenant-aware schema

-- Tenant registry (in platform database)
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(63) UNIQUE NOT NULL,  -- subdomain/identifier
    tier VARCHAR(20) NOT NULL DEFAULT 'free',  -- free, team, enterprise, regulated
    database_name VARCHAR(63),  -- NULL for shared, set for dedicated
    encryption_key_id VARCHAR(255),  -- Reference to KMS key
    created_at TIMESTAMPTZ DEFAULT NOW(),
    settings JSONB DEFAULT '{}'::jsonb,

    -- Compliance
    data_residency VARCHAR(10) DEFAULT 'us',  -- us, eu, etc.
    retention_days INTEGER DEFAULT 90,

    CONSTRAINT valid_tier CHECK (tier IN ('free', 'team', 'enterprise', 'regulated'))
);

-- User-tenant relationship
CREATE TABLE tenant_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,  -- References auth system
    role VARCHAR(20) NOT NULL DEFAULT 'learner',
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(tenant_id, user_id),
    CONSTRAINT valid_role CHECK (role IN ('learner', 'instructor', 'admin'))
);

-- Row-level security example (for shared database model)
ALTER TABLE curricula ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON curricula
    USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Set tenant context on each request
-- SET app.tenant_id = 'uuid-of-tenant';
```

### 4.5 API Changes for Multi-Tenancy

```python
# Required: Tenant context middleware
@web.middleware
async def tenant_middleware(request: web.Request, handler):
    # Extract tenant from JWT claims or subdomain
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    claims = validate_jwt(token)

    tenant_id = claims.get("tenant_id")
    if not tenant_id:
        return web.json_response({"error": "Tenant not specified"}, status=400)

    # Set tenant context for this request
    request["tenant_id"] = tenant_id
    request["tenant"] = await get_tenant(tenant_id)

    # Set database context
    await set_tenant_context(request["tenant"])

    return await handler(request)

# All data access filtered by tenant
async def get_curricula(request):
    tenant_id = request["tenant_id"]
    # Query automatically filtered by RLS or explicit WHERE clause
    curricula = await db.fetch_all(
        "SELECT * FROM curricula WHERE tenant_id = $1",
        tenant_id
    )
    return web.json_response(curricula)
```

---

## 5. Scaling Roadmap

### 5.1 Phase 1: Beta (10-50 Users)

**Current architecture is sufficient with security fixes.**

| Component | Current | Required Changes |
|-----------|---------|------------------|
| iOS Client | ✅ Works | Add encryption at rest |
| Management Console | ⚠️ Insecure | Add basic auth + HTTPS |
| Database | ✅ File-based OK | None |
| Hosting | Single machine | None |

**Priority fixes for beta**:
1. Add API key authentication to management console
2. Enable HTTPS (Let's Encrypt)
3. Implement Core Data encryption (SQLCipher)
4. Add consent tracking
5. Create privacy policy

**Estimated effort**: 2-3 weeks

### 5.2 Phase 2: Early Adopters (50-1,000 Users)

**Requires proper backend architecture.**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Phase 2 Architecture                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────────┐   │
│  │ iOS Clients │────►│   Nginx     │────►│  Management Console    │   │
│  │ (1000)      │     │   + TLS     │     │  (2-3 instances)       │   │
│  └─────────────┘     │   + Auth    │     └───────────┬─────────────┘   │
│                      └─────────────┘                 │                  │
│                                                      ▼                  │
│                                         ┌─────────────────────────┐    │
│                                         │  PostgreSQL Primary     │    │
│                                         │  + Read Replica         │    │
│                                         │  + Connection Pooling   │    │
│                                         └─────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Required changes**:
1. Migrate to PostgreSQL with proper schema
2. Add connection pooling (PgBouncer)
3. Implement horizontal scaling for management console
4. Add Redis for session storage and caching
5. Implement proper logging (structured, centralized)
6. Add monitoring (Prometheus + Grafana)
7. Implement rate limiting
8. Add input validation
9. Certificate pinning in iOS client

**Estimated effort**: 6-8 weeks

### 5.3 Phase 3: Growth (1,000-100,000 Users)

**Requires multi-tenant architecture and geographic distribution.**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Phase 3 Architecture                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        CDN (CloudFlare/Fastly)                   │   │
│  │  • Static asset caching                                          │   │
│  │  • DDoS protection                                               │   │
│  │  • Geographic routing                                            │   │
│  └────────────────────────────────┬────────────────────────────────┘   │
│                                   │                                     │
│         ┌─────────────────────────┼─────────────────────────┐          │
│         │                         │                         │          │
│         ▼                         ▼                         ▼          │
│  ┌─────────────┐           ┌─────────────┐           ┌─────────────┐  │
│  │  US-WEST    │           │  US-EAST    │           │  EU-WEST    │  │
│  │  Region     │           │  Region     │           │  Region     │  │
│  │             │           │             │           │             │  │
│  │ • K8s       │           │ • K8s       │           │ • K8s       │  │
│  │ • PostgreSQL│           │ • PostgreSQL│           │ • PostgreSQL│  │
│  │ • Redis     │           │ • Redis     │           │ • Redis     │  │
│  └─────────────┘           └─────────────┘           └─────────────┘  │
│         │                         │                         │          │
│         └─────────────────────────┼─────────────────────────┘          │
│                                   │                                     │
│                                   ▼                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │               Cross-Region Data Synchronization                  │   │
│  │  • Curriculum sync (eventual consistency OK)                     │   │
│  │  • User data stays in home region (data residency)              │   │
│  │  • Conflict resolution for progress data                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Required changes**:
1. Kubernetes deployment (EKS/GKE/AKS)
2. Multi-region PostgreSQL with cross-region replication
3. Tenant isolation implementation
4. Data residency compliance (GDPR: EU data stays in EU)
5. Automated scaling policies
6. Disaster recovery with RTO < 4 hours, RPO < 1 hour
7. SOC 2 Type II compliance preparation
8. Penetration testing

**Estimated effort**: 4-6 months

### 5.4 Phase 4: Scale (100,000-1,000,000+ Users)

**Enterprise-grade architecture with dedicated tenancy options.**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Phase 4 Architecture                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Global Traffic Management                     │   │
│  │  • Anycast DNS                                                   │   │
│  │  • Geographic load balancing                                     │   │
│  │  • Failover automation                                           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Shared Platform (Free/Team tiers):                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Multi-tenant Kubernetes clusters per region                   │   │
│  │  • Shared PostgreSQL with RLS                                    │   │
│  │  • Shared AI infrastructure (pooled API quotas)                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Dedicated Platform (Enterprise tier):                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Dedicated Kubernetes namespace or cluster                     │   │
│  │  • Dedicated PostgreSQL instance                                 │   │
│  │  • Dedicated AI API keys (customer-provided or managed)         │   │
│  │  • Custom domain + SSL                                           │   │
│  │  • SLA: 99.9% uptime                                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Isolated Platform (Regulated tier):                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  • Dedicated VPC/network isolation                               │   │
│  │  • Customer-managed encryption keys (BYOK)                       │   │
│  │  • On-premise deployment option                                  │   │
│  │  • HIPAA/FERPA/FedRAMP compliance                               │   │
│  │  • Audit logging with customer SIEM integration                  │   │
│  │  • SLA: 99.99% uptime                                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Required changes**:
1. Service mesh (Istio/Linkerd) for mTLS
2. Dedicated tenant provisioning automation
3. Customer-managed key support (BYOK)
4. Compliance certifications (SOC 2, ISO 27001, HIPAA if needed)
5. 24/7 security operations center
6. Bug bounty program
7. Regular third-party penetration testing
8. Incident response procedures

**Estimated effort**: 12-18 months

---

## 6. Implementation Priorities

### 6.1 Immediate (Week 1-2): Critical Security

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| P0 | Add authentication to management console | 2 days | 🔴 Critical |
| P0 | Enable HTTPS on all servers | 1 day | 🔴 Critical |
| P0 | Fix CORS to allowlist origins | 1 hour | 🔴 Critical |
| P0 | Add input validation (path traversal) | 1 day | 🔴 Critical |
| P0 | Disable remote logging in production | 1 hour | 🔴 Critical |

### 6.2 Short-Term (Week 3-6): Privacy & Encryption

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| P1 | Implement SQLCipher for Core Data | 3 days | 🟡 High |
| P1 | Add consent management system | 3 days | 🟡 High |
| P1 | Create and deploy privacy policy | 2 days | 🟡 High |
| P1 | Implement data retention/deletion | 2 days | 🟡 High |
| P1 | Add certificate pinning (iOS) | 2 days | 🟡 High |
| P1 | Implement rate limiting | 2 days | 🟡 High |

### 6.3 Medium-Term (Week 7-12): Multi-Tenancy Foundation

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| P2 | Design tenant data model | 1 week | 🟢 Medium |
| P2 | Migrate to PostgreSQL | 2 weeks | 🟢 Medium |
| P2 | Implement RLS policies | 1 week | 🟢 Medium |
| P2 | Add tenant-aware API layer | 2 weeks | 🟢 Medium |
| P2 | Implement audit logging | 1 week | 🟢 Medium |

### 6.4 Long-Term (Month 4-12): Scale & Compliance

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| P3 | Kubernetes deployment | 4 weeks | 🟢 Medium |
| P3 | Multi-region architecture | 6 weeks | 🟢 Medium |
| P3 | SOC 2 Type II preparation | 3 months | 🟢 Medium |
| P3 | Dedicated tenant infrastructure | 4 weeks | 🟢 Medium |
| P3 | BYOK implementation | 2 weeks | 🟢 Medium |

---

## 7. Appendix: File Reference

### 7.1 iOS Client Files

| File | Purpose | Security Relevance |
|------|---------|-------------------|
| `UnaMentis/Core/Config/APIKeyManager.swift` | Keychain API key storage | ✅ Properly implemented |
| `UnaMentis/Core/Persistence/PersistenceController.swift` | Core Data setup | ❌ No encryption |
| `UnaMentis/Core/Logging/RemoteLogHandler.swift` | Remote log transmission | ⚠️ Sends to HTTP |
| `UnaMentis/Services/LLM/OpenAILLMService.swift` | OpenAI API calls | ⚠️ No cert pinning |
| `UnaMentis/Services/LLM/AnthropicLLMService.swift` | Anthropic API calls | ⚠️ No cert pinning |
| `UnaMentis/Services/STT/DeepgramSTTService.swift` | Deepgram WebSocket | ⚠️ No cert pinning |
| `UnaMentis/Services/STT/AssemblyAISTTService.swift` | AssemblyAI WebSocket | ⚠️ No cert pinning |
| `UnaMentis/Services/TTS/ElevenLabsTTSService.swift` | ElevenLabs WebSocket | ⚠️ No cert pinning |
| `UnaMentis/UI/History/HistoryView.swift` | Data export/deletion | ✅ Export works |
| `UnaMentis/UI/Settings/SettingsView.swift` | Privacy toggles | ⚠️ No consent tracking |
| `UnaMentis/Info.plist` | App permissions | ✅ Minimal permissions |

### 7.2 Server Files

| File | Purpose | Security Relevance |
|------|---------|-------------------|
| `server/management/server.py` | Main management server | ❌ No authentication |
| `server/management/import_api.py` | Curriculum import | ❌ SSRF vulnerability |
| `server/database/curriculum_db.py` | Database abstraction | ❌ No encryption |
| `server/database/schema.sql` | PostgreSQL schema | ❌ No RLS |
| `server/web/src/lib/api-client.ts` | Frontend API client | ⚠️ Inherits backend issues |

### 7.3 Core Data Model

| Entity | Sensitive Fields | Encryption Required |
|--------|-----------------|---------------------|
| `Session` | metricsSnapshot, config | ✅ Yes |
| `TranscriptEntry` | content | ✅ Yes |
| `TopicProgress` | quizScores | ✅ Yes |
| `Topic` | title, outline | Optional |
| `Document` | content, embedding | Optional |
| `VisualAsset` | cachedData | Optional |

---

## Conclusion

UnaMentis has a solid foundation for voice-based AI tutoring, but requires significant security hardening before production deployment. The most critical gaps are:

1. **Zero authentication** on the management server
2. **Zero multi-tenancy** support
3. **Zero encryption** at rest
4. **Incomplete privacy compliance** mechanisms

For an uncompromising privacy stance, the recommended path forward is:

1. **Immediate**: Fix critical security vulnerabilities (authentication, HTTPS, input validation)
2. **Short-term**: Implement encryption and privacy controls
3. **Medium-term**: Build multi-tenant foundation with proper data isolation
4. **Long-term**: Scale infrastructure with dedicated tenancy options for organizations

The architecture should default to **maximum privacy** (on-device processing where possible) with cloud services as opt-in, clearly communicated choices that users make with full informed consent.

---

*Document version: 1.0*
*Last updated: December 2024*
*Next review: Before beta launch*
