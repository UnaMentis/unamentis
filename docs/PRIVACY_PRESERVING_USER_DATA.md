# Privacy-Preserving User Data Architecture

> **Purpose**: Technical specification for privacy-preserving storage and management of user learning preferences, usage patterns, and personal data in UnaMentis.
>
> **Last Updated**: December 2024
> **Status**: Living Document (target architecture, not all shipped)

---

> ⚠️ **Current beta behavior (authoritative).** The sections below describe the
> long-term privacy architecture and vision (on-device-first, zero-knowledge,
> COPPA/FERPA, a GDPR data-subject dashboard). Several of these are not yet
> shipped. What the hosted beta actually does today:
>
> - **Account data is stored on the server:** email, a hashed password, a device
>   fingerprint, and the user agent.
> - **Aggregate, non-content telemetry** (latency, turn and interruption counts,
>   costs, thermal/network events) is uploaded, keyed to a per-install random ID.
>   No transcripts or learning content reach the UnaMentis server.
> - **Cloud voice providers receive audio and transcripts** during inference (see
>   [SUBPROCESSORS.md](SUBPROCESSORS.md)). On-device providers keep audio local.
> - **Client IP is coarsened** (IPv4 to /24, IPv6 to /48) on telemetry and log
>   intake; the exact IP from those endpoints is not stored.
> - **Security logs keep exact IPs, time-bounded.** Account-security events
>   (login, registration, token refresh, device registration) record the exact
>   client IP in the auth audit log and on refresh tokens. Rationale: abuse and
>   credential-stuffing forensics need to distinguish individual hosts, and a
>   coarsened /24 cannot tell an attacker from a victim on the same network. A
>   retention sweep (`server/management/auth/ip_retention.py`, run at startup
>   and every 24 hours) nulls these IPs after 90 days (audit-log rows older
>   than 90 days, and expired or revoked refresh tokens issued more than 90
>   days ago). This window is disclosed on the web client's `/privacy` page;
>   change both together.
> - **Age:** a 13+ self-attestation is required at registration; under-13 is out
>   of scope. Verifiable parental consent (COPPA) is NOT implemented.
> - **Registration consent records:** registration requires explicit acceptance
>   of the Terms of Service and Privacy Policy (versioned, currently
>   `2026-06-10`) in addition to the age attestation. The server writes
>   `consent_records` rows for `age_attestation`, `terms_of_service`, and
>   `privacy_policy` with the accepted version and a SHA-256 hash of the
>   coarsened client IP (never the exact address), and stamps
>   `users.age_verified_at`.
> - **Not yet implemented:** hardware-backed on-device encryption as the default,
>   consent-gated sync, automated data export and deletion, enforced retention,
>   multi-tenant/FERPA isolation, and the privacy dashboard. Treat references to
>   these below as roadmap, not current functionality.
> - Do not describe the beta as "zero-knowledge", "COPPA compliant", or
>   "FERPA-ready". The user-facing statement of current practice is the Privacy
>   Policy served at `/privacy` in the web client.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Design Principles](#2-design-principles)
3. [Regulatory Compliance Framework](#3-regulatory-compliance-framework)
4. [Data Classification & Inventory](#4-data-classification--inventory)
5. [On-Device Architecture](#5-on-device-architecture)
6. [Encryption & Security Implementation](#6-encryption--security-implementation)
7. [Learning Preference Data Model](#7-learning-preference-data-model)
8. [Age Verification & Parental Consent (COPPA)](#8-age-verification--parental-consent-coppa)
9. [Educational Institution Integration (FERPA)](#9-educational-institution-integration-ferpa)
10. [User Rights & Controls](#10-user-rights--controls)
11. [Implementation Roadmap](#11-implementation-roadmap)
12. [References & Standards Attribution](#12-references--standards-attribution)

---

## 1. Executive Summary

### 1.1 Vision

UnaMentis collects learning preference and usage data to provide adaptive, personalized tutoring experiences. This document establishes a **privacy-first architecture** where:

- **All user data remains on-device**, encrypted with hardware-backed keys
- **No data syncs to servers** without explicit, granular user consent
- **Children are protected** through full COPPA compliance
- **Educational institutions** can deploy with FERPA confidence
- **Standards-based** approaches enable interoperability and auditability

### 1.2 Core Commitment

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      PRIVACY COMMITMENT                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  "The best protection for sensitive data is not having it."            │
│                                                                         │
│  UnaMentis processes learning data locally. Voice recordings are        │
│  deleted immediately after transcription. Learning preferences          │
│  never leave the device. The user owns their data, period.             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Scope of Data

This document covers the management of:

| Data Category | Examples | Sensitivity |
|---------------|----------|-------------|
| **Learning Preferences** | Example frequency, pacing, modality | Medium |
| **Performance Metrics** | Mastery levels, quiz scores, time-on-task | High |
| **Interaction Patterns** | Session frequency, interruption behavior | Medium |
| **Session Content** | Conversation transcripts | Restricted |
| **Voice Data** | Raw audio (transient only) | Restricted |
| **Derived Insights** | Learning style classification | Medium |

---

## 2. Design Principles

### 2.1 Privacy-by-Design Principles

These principles align with GDPR Article 25, Apple's Privacy Engineering practices, and the [W3C Privacy Principles](https://www.w3.org/mission/privacy/) (elevated to W3C Statement, May 2025).

| Principle | Implementation |
|-----------|----------------|
| **Data Minimization** | Collect only what's necessary for the specific learning feature |
| **Purpose Limitation** | Data collected for tutoring cannot be used for advertising |
| **On-Device Processing** | All learning analytics computed locally, no cloud ML |
| **User Control** | Granular consent, view, export, and deletion capabilities |
| **Transparency** | Clear documentation of what's collected and why |
| **Security by Default** | Encryption at rest using hardware-backed keys |
| **Accountability** | Audit logs for data access (stored locally) |

### 2.2 Apple's Local Differential Privacy Model

UnaMentis adopts [Apple's Local Differential Privacy](https://machinelearning.apple.com/research/learning-with-privacy-at-scale) approach for any analytics:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    LOCAL DIFFERENTIAL PRIVACY                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Data is RANDOMIZED on the user's device before any export          │
│  2. Mathematical noise obscures individual data points                  │
│  3. Aggregate patterns can be learned without individual identification │
│  4. The server NEVER sees raw, unprotected user data                   │
│                                                                         │
│  Key Properties:                                                        │
│  - Epsilon (ε) budget limits total privacy loss                        │
│  - Opt-in and transparent to users                                     │
│  - Transmission over encrypted channel, once per day maximum           │
│  - No device identifiers included                                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**For UnaMentis**: Since we use 100% on-device storage, differential privacy applies only if we ever introduce optional aggregated analytics sharing in the future. Currently, no data leaves the device.

### 2.3 Zero-Knowledge Principle

The UnaMentis backend has **zero knowledge** of user learning preferences:

- Server provides curriculum content (public data)
- Server receives performance metrics (latency, not content)
- Server never receives transcripts, preferences, or learning styles
- Device-to-device sync (future) would use end-to-end encryption

---

## 3. Regulatory Compliance Framework

### 3.1 COPPA (Children's Online Privacy Protection Act)

**Applicability**: UnaMentis serves all ages, including children under 13.

**Reference**: [FTC COPPA Rule](https://www.ftc.gov/legal-library/browse/rules/childrens-online-privacy-protection-rule-coppa) (16 CFR Part 312)

#### 3.1.1 COPPA Requirements and UnaMentis Compliance

| COPPA Requirement | UnaMentis Implementation |
|-------------------|--------------------------|
| **Verifiable Parental Consent (VPC)** | Required before any data collection for under-13 users |
| **Notice to Parents** | Clear privacy notice before consent request |
| **No More Than Necessary** | On-device only, minimal data collection |
| **Confidentiality & Security** | Secure Enclave encryption, no transmission |
| **Parental Access** | Parents can view all child's data via export |
| **Parental Deletion** | Parents can delete all child data at any time |
| **No Behavioral Advertising** | UnaMentis has no advertising whatsoever |
| **No Conditioning on Disclosure** | App functions fully with minimal consent |

#### 3.1.2 Verifiable Parental Consent Methods

Per FTC guidance, acceptable VPC methods include:

1. **Signed Consent Form** (mail/fax/email scan) - highest assurance
2. **Credit Card Transaction** - small charge as verification
3. **Video Conferencing** - for school deployments
4. **Knowledge-Based Authentication** - parent answers questions
5. **Government ID Check** - face matching against ID

**UnaMentis Recommendation**: For consumer use, implement **email-plus** method (email to parent with link to confirm, plus additional verification step). For educational institutions, rely on **school consent** under FERPA exception (see Section 9).

#### 3.1.3 Data Not Collected from Children

UnaMentis does **NOT** collect from children under 13:

- Geolocation data
- Photos or videos
- Voice recordings (deleted immediately after STT)
- Contact lists
- Persistent identifiers for cross-site tracking
- Behavioral data for advertising

### 3.2 FERPA (Family Educational Rights and Privacy Act)

**Applicability**: When UnaMentis is used by educational institutions.

**Reference**: [FERPA](https://studentprivacy.ed.gov/ferpa) (20 U.S.C. § 1232g; 34 CFR Part 99)

#### 3.2.1 FERPA Scope

FERPA protects **education records**, defined as records directly related to a student and maintained by an educational agency. When a school deploys UnaMentis:

- Learning progress data becomes part of education records
- School is the data controller, UnaMentis is a school official (contractor)
- Parental consent exceptions apply (schools can authorize without parent VPC)
- Students 18+ have rights that transfer from parents

#### 3.2.2 FERPA Compliance Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    FERPA DEPLOYMENT MODEL                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Educational Institution (Controller)                                   │
│  └── Executes Data Processing Agreement (DPA) with UnaMentis           │
│      └── UnaMentis designated as "School Official"                     │
│          └── Legitimate educational interest for data access           │
│                                                                         │
│  Data Handling:                                                         │
│  - Student data remains on student's device                            │
│  - School can receive aggregate, de-identified reports                 │
│  - Individual progress visible to authorized school staff              │
│  - Parent/eligible student can request data export                     │
│  - Annual notification of FERPA rights by school (not UnaMentis)       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### 3.2.3 School Official Designation

UnaMentis qualifies as a "school official" when:

1. School has formal DPA/contract with UnaMentis
2. UnaMentis performs a service the school would otherwise perform
3. UnaMentis is under direct control of school regarding data use
4. UnaMentis uses data only for authorized purposes
5. UnaMentis meets FERPA criteria in the contract

**Since data stays on-device**, UnaMentis has minimal access to education records, simplifying compliance.

### 3.3 GDPR (General Data Protection Regulation)

**Applicability**: EU residents, global best practice.

**Reference**: [GDPR](https://gdpr-info.eu/) (Regulation 2016/679)

#### 3.3.1 GDPR Principles Alignment

| GDPR Principle | UnaMentis Implementation |
|----------------|--------------------------|
| **Lawfulness, Fairness, Transparency** | Clear consent, privacy notice, no hidden collection |
| **Purpose Limitation** | Data used only for tutoring improvement |
| **Data Minimization** | Collect only necessary learning preferences |
| **Accuracy** | User can correct preferences at any time |
| **Storage Limitation** | Configurable retention (30/90/365 days) |
| **Integrity & Confidentiality** | Secure Enclave encryption |
| **Accountability** | Local audit log, exportable |

#### 3.3.2 Legal Basis for Processing

For adult users (or children with parental consent):

- **Consent** (Article 6(1)(a)): Primary basis for preference tracking
- **Legitimate Interest** (Article 6(1)(f)): Core tutoring functionality

For children under 16 (GDPR threshold, varies by member state):
- **Parental Consent** (Article 8): Required for information society services

#### 3.3.3 Data Subject Rights Implementation

| Right | Implementation |
|-------|----------------|
| **Right of Access (Art. 15)** | Export all data in JSON format |
| **Right to Rectification (Art. 16)** | Edit preferences in Settings |
| **Right to Erasure (Art. 17)** | Delete all data button |
| **Right to Restriction (Art. 18)** | Disable specific tracking features |
| **Right to Portability (Art. 20)** | xAPI-compatible export format |
| **Right to Object (Art. 21)** | Opt-out of any processing |

### 3.4 State Privacy Laws

#### California SOPIPA (Student Online Personal Information Protection Act)

- Prohibits targeted advertising based on student data
- Prohibits selling student data
- Requires reasonable security
- **UnaMentis Compliance**: No advertising, no data sales, on-device encryption

#### New York Education Law 2-d

- Requires data security and privacy plans
- Parents have access/correction rights
- Third-party contracts must include privacy terms
- **UnaMentis Compliance**: DPA template includes 2-d requirements

#### Other State Laws

Illinois SOPPA, Colorado Student Data Transparency Act, and others have similar requirements. On-device architecture satisfies the data protection requirements across jurisdictions.

---

## 4. Data Classification & Inventory

### 4.1 Data Classification Levels

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DATA CLASSIFICATION LEVELS                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  LEVEL 1: RESTRICTED (Never leaves device, shortest retention)         │
│  ├── Voice audio recordings (deleted immediately after STT)            │
│  ├── Raw conversation transcripts                                       │
│  └── Biometric-derived data (voice patterns)                           │
│                                                                         │
│  LEVEL 2: CONFIDENTIAL (Device-only, encrypted, user-controlled)       │
│  ├── Learning preferences (examples, pacing, difficulty)               │
│  ├── Performance metrics (mastery, quiz scores)                        │
│  ├── Session history and progress                                       │
│  └── Derived learning style classifications                            │
│                                                                         │
│  LEVEL 3: INTERNAL (Device storage, standard protection)               │
│  ├── Curriculum selections                                              │
│  ├── Topic completion status                                            │
│  └── UI preferences (theme, text size)                                  │
│                                                                         │
│  LEVEL 4: PUBLIC (No special handling)                                  │
│  ├── App version                                                        │
│  └── Public curriculum metadata                                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Complete Data Inventory

| Data Element | Classification | Storage Location | Encryption | Retention | COPPA Impact |
|--------------|----------------|------------------|------------|-----------|--------------|
| Voice audio | Restricted | RAM only | N/A | Session only | Never stored |
| Transcripts | Restricted | Core Data | Secure Enclave | User choice | Requires VPC |
| Example preference | Confidential | Core Data | Keychain-wrapped | User choice | Requires VPC |
| Pacing preference | Confidential | Core Data | Keychain-wrapped | User choice | Requires VPC |
| Modality preference | Confidential | Core Data | Keychain-wrapped | User choice | Requires VPC |
| Difficulty setting | Confidential | Core Data | Keychain-wrapped | User choice | Requires VPC |
| Topic interests | Confidential | Core Data | Keychain-wrapped | User choice | Requires VPC |
| Mastery levels | Confidential | Core Data | Keychain-wrapped | User choice | Requires VPC |
| Quiz scores | Confidential | Core Data | Keychain-wrapped | User choice | Requires VPC |
| Time-on-task | Confidential | Core Data | Standard | User choice | Requires VPC |
| Session count | Internal | Core Data | Standard | Indefinite | Low risk |
| Last accessed | Internal | Core Data | Standard | Indefinite | Low risk |
| Age bracket | Internal | Keychain | Standard | Indefinite | Required |
| Parental consent | Internal | Keychain | Standard | Indefinite | Required |
| UI theme | Internal | UserDefaults | None | Indefinite | No impact |
| Text size | Internal | UserDefaults | None | Indefinite | No impact |

### 4.3 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DATA FLOW                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  User Speech                                                            │
│      │                                                                  │
│      ▼                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐            │
│  │ Audio Buffer │────▶│   STT API    │────▶│  Transcript  │            │
│  │  (RAM only)  │     │  (External)  │     │ (Encrypted)  │            │
│  └──────────────┘     └──────────────┘     └──────────────┘            │
│      │                                           │                      │
│      ▼                                           ▼                      │
│  DELETE                                   ┌──────────────┐              │
│  IMMEDIATELY                              │   Session    │              │
│                                           │   Manager    │              │
│                                           └──────┬───────┘              │
│                                                  │                      │
│                    ┌─────────────────────────────┼─────────────────┐    │
│                    │                             │                 │    │
│                    ▼                             ▼                 ▼    │
│           ┌──────────────┐            ┌──────────────┐    ┌────────────┐│
│           │   Learning   │            │   Progress   │    │Performance ││
│           │ Preferences  │            │   Tracker    │    │  Metrics   ││
│           │  (Encrypted) │            │  (Encrypted) │    │ (Encrypted)││
│           └──────────────┘            └──────────────┘    └────────────┘│
│                    │                             │                 │    │
│                    └─────────────────────────────┴─────────────────┘    │
│                                        │                                │
│                                        ▼                                │
│                              ┌──────────────────┐                       │
│                              │    Core Data     │                       │
│                              │   (On-Device)    │                       │
│                              │  File Protection │                       │
│                              └──────────────────┘                       │
│                                        │                                │
│                                        ▼                                │
│                              ┌──────────────────┐                       │
│                              │   Secure File    │                       │
│                              │    System        │                       │
│                              │  (iOS Encrypted) │                       │
│                              └──────────────────┘                       │
│                                                                         │
│  NOTHING LEAVES THE DEVICE (except STT/TTS/LLM API calls)              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 5. On-Device Architecture

### 5.1 Storage Layer Stack

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    iOS STORAGE ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     SECURE ENCLAVE                               │   │
│  │  Hardware-isolated cryptographic processor                       │   │
│  │  ├── Master encryption key (P-256, never exported)              │   │
│  │  ├── Biometric authentication keys                              │   │
│  │  └── Key derivation for per-data-class keys                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                       KEYCHAIN                                   │   │
│  │  kSecAttrAccessibleAfterFirstUnlock                              │   │
│  │  ├── Wrapped Data Encryption Key (DEK) for preferences          │   │
│  │  ├── Consent records and timestamps                              │   │
│  │  ├── Age verification status                                     │   │
│  │  └── API keys (via existing APIKeyManager)                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      CORE DATA                                   │   │
│  │  SQLite with iOS Data Protection                                 │   │
│  │  ├── LearnerProfile (encrypted fields)                          │   │
│  │  ├── LearningPreferences (encrypted fields)                     │   │
│  │  ├── PrivacyConsent (audit trail)                               │   │
│  │  ├── Session (existing, extended)                               │   │
│  │  ├── TopicProgress (existing, extended)                         │   │
│  │  └── LocalAuditLog (access tracking)                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    USER DEFAULTS                                 │   │
│  │  Non-sensitive preferences only                                  │   │
│  │  ├── UI theme, text size                                        │   │
│  │  ├── Feature flags (non-privacy-affecting)                      │   │
│  │  └── Onboarding completion status                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.2 iOS Data Protection Classes

| Protection Class | Availability | Use Case |
|------------------|--------------|----------|
| `completeProtection` | Only when unlocked | Not used (too restrictive) |
| `completeUnlessOpen` | When unlocked, or file open | Not used |
| `afterFirstUnlock` | After first unlock until reboot | **Learning preferences** |
| `afterFirstUnlockThisDeviceOnly` | Same, no backup | **Transcripts** |
| `none` | Always available | Only for truly non-sensitive |

**Rationale**: `afterFirstUnlock` allows background session processing while maintaining encryption at rest. `ThisDeviceOnly` variants prevent iCloud backup of sensitive data.

### 5.3 Never Backed Up to iCloud

The following data uses `.excludeFromBackup` or `ThisDeviceOnly` protection:

- Conversation transcripts
- Voice-derived learning patterns
- Parental consent records
- Age verification status

---

## 6. Encryption & Security Implementation

### 6.1 Key Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ENCRYPTION KEY HIERARCHY                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│                 ┌─────────────────────────────────┐                     │
│                 │     Secure Enclave Master       │                     │
│                 │     (P-256, Hardware-Bound)     │                     │
│                 └───────────────┬─────────────────┘                     │
│                                 │                                       │
│                    HKDF Key Derivation                                  │
│                                 │                                       │
│         ┌───────────────────────┼───────────────────────┐               │
│         │                       │                       │               │
│         ▼                       ▼                       ▼               │
│  ┌─────────────┐        ┌─────────────┐        ┌─────────────┐         │
│  │ Preferences │        │ Transcripts │        │   Metrics   │         │
│  │     DEK     │        │     DEK     │        │     DEK     │         │
│  │ (AES-256)   │        │ (AES-256)   │        │ (AES-256)   │         │
│  └─────────────┘        └─────────────┘        └─────────────┘         │
│         │                       │                       │               │
│         ▼                       ▼                       ▼               │
│  Encrypted in            Encrypted in            Encrypted in          │
│  Core Data               Core Data               Core Data             │
│                                                                         │
│  Benefits:                                                              │
│  - Key separation: Compromise of one DEK doesn't expose others         │
│  - Hardware-bound: Master key never leaves Secure Enclave              │
│  - Rotation: Can rotate DEKs without re-encrypting master             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Secure Enclave Integration

**Reference**: [Apple Secure Enclave Documentation](https://developer.apple.com/documentation/security/certificate_key_and_trust_services/keys/protecting_keys_with_the_secure_enclave)

```swift
// Conceptual implementation pattern
actor SecurePreferenceEncryption {

    private let masterKeyTag = "com.unamentis.preferences.master"

    /// Generate or retrieve Secure Enclave master key
    func getMasterKey() async throws -> SecKey {
        // Check if key exists
        if let existingKey = try? retrieveKey(tag: masterKeyTag) {
            return existingKey
        }

        // Generate new key in Secure Enclave
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.privateKeyUsage],  // Biometric optional: add .biometryCurrentSet
            nil
        )!

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: masterKeyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String: access
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw EncryptionError.keyGenerationFailed(error?.takeRetainedValue())
        }

        return privateKey
    }

    /// Derive a data encryption key for a specific purpose
    func deriveDataKey(purpose: DataPurpose) async throws -> SymmetricKey {
        let masterKey = try await getMasterKey()

        // Use ECDH to derive shared secret, then HKDF
        // (Simplified - actual implementation uses CryptoKit)
        let info = purpose.rawValue.data(using: .utf8)!
        let derivedKey = try deriveSymmetricKey(
            from: masterKey,
            info: info,
            outputByteCount: 32
        )

        return derivedKey
    }
}

enum DataPurpose: String {
    case preferences = "com.unamentis.dek.preferences"
    case transcripts = "com.unamentis.dek.transcripts"
    case metrics = "com.unamentis.dek.metrics"
}
```

### 6.3 CryptoKit Encryption

**Reference**: [Apple CryptoKit Documentation](https://developer.apple.com/documentation/cryptokit)

```swift
import CryptoKit

struct EncryptedData: Codable {
    let ciphertext: Data
    let nonce: Data
    let tag: Data
}

/// Encrypt preference data using derived key
func encrypt(data: Data, with key: SymmetricKey) throws -> EncryptedData {
    let nonce = AES.GCM.Nonce()
    let sealed = try AES.GCM.seal(data, using: key, nonce: nonce)

    return EncryptedData(
        ciphertext: sealed.ciphertext,
        nonce: Data(nonce),
        tag: sealed.tag
    )
}

/// Decrypt preference data
func decrypt(encrypted: EncryptedData, with key: SymmetricKey) throws -> Data {
    let nonce = try AES.GCM.Nonce(data: encrypted.nonce)
    let sealed = try AES.GCM.SealedBox(
        nonce: nonce,
        ciphertext: encrypted.ciphertext,
        tag: encrypted.tag
    )

    return try AES.GCM.open(sealed, using: key)
}
```

### 6.4 Biometric Protection Option

For highly sensitive operations (export, delete all), require biometric authentication:

```swift
func requireBiometricForSensitiveOperation() async throws {
    let context = LAContext()
    var error: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
        throw AuthenticationError.biometricsUnavailable
    }

    let success = try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "Authenticate to export your learning data"
    )

    guard success else {
        throw AuthenticationError.biometricFailed
    }
}
```

---

## 7. Learning Preference Data Model

### 7.1 Core Data Entities

#### LearnerProfile

```swift
/// Core learner profile with encrypted sensitive fields
@objc(LearnerProfile)
public class LearnerProfile: NSManagedObject {

    // Identity (non-sensitive)
    @NSManaged public var id: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    // Age Bracket (for COPPA, stored in Keychain reference)
    @NSManaged public var ageBracket: String  // "child", "teen", "adult"

    // Encrypted Learning Style (stored as encrypted blob)
    @NSManaged public var encryptedPreferences: Data?

    // Relationships
    @NSManaged public var privacyConsent: PrivacyConsent?
    @NSManaged public var sessions: Set<Session>?
}
```

#### LearningPreferences (Encrypted Payload)

```swift
/// Learning preferences structure (encrypted before storage)
struct LearningPreferences: Codable {

    // Example Preferences
    var exampleFrequency: ExampleFrequency      // more, standard, fewer
    var exampleTypes: Set<ExampleType>          // realWorld, abstract, visual
    var exampleComplexity: ComplexityLevel      // simple, moderate, complex

    // Pacing Preferences
    var explanationSpeed: PacingSpeed           // slower, standard, faster
    var repetitionPreference: RepetitionLevel   // high, medium, low
    var breakFrequency: BreakFrequency          // frequent, moderate, minimal

    // Modality Preferences
    var primaryModality: LearningModality       // auditory, visual, readWrite
    var secondaryModality: LearningModality?
    var prefersDiagrams: Bool
    var prefersStepByStep: Bool

    // Difficulty Progression
    var difficultyMode: DifficultyMode          // adaptive, fixed, userControlled
    var challengePreference: ChallengeLevel     // comfortable, moderate, challenging
    var scaffoldingLevel: ScaffoldingLevel      // high, medium, low

    // Topic Interests (category weights 0.0-1.0)
    var topicInterests: [String: Float]         // e.g., "mathematics": 0.8
    var curiosityIndicators: [String]           // Topics user explored beyond curriculum
    var avoidedTopics: [String]                 // Topics user skipped/struggled with

    // Meta
    var lastUpdated: Date
    var version: Int
}

enum ExampleFrequency: String, Codable {
    case more, standard, fewer
}

enum LearningModality: String, Codable {
    case auditory, visual, readWrite, kinesthetic
}

enum DifficultyMode: String, Codable {
    case adaptive      // System adjusts based on performance
    case fixed         // User selects difficulty level
    case userControlled // User adjusts in real-time
}
```

#### PrivacyConsent

```swift
/// Tracks consent status for COPPA/GDPR compliance
@objc(PrivacyConsent)
public class PrivacyConsent: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date

    // Consent Flags
    @NSManaged public var coreTrackingConsent: Bool      // Required for preferences
    @NSManaged public var performanceMetricsConsent: Bool // Latency tracking
    @NSManaged public var adaptiveLearningConsent: Bool   // AI-driven adaptation

    // COPPA-Specific
    @NSManaged public var parentalConsentObtained: Bool
    @NSManaged public var parentalConsentDate: Date?
    @NSManaged public var parentalConsentMethod: String?  // "email_plus", "school"
    @NSManaged public var parentEmail: String?            // Encrypted

    // Retention
    @NSManaged public var retentionPeriodDays: Int32      // 30, 90, 365

    // Audit
    @NSManaged public var consentHistory: Data?           // JSON array of changes

    // Relationship
    @NSManaged public var profile: LearnerProfile?
}
```

#### LocalAuditLog

```swift
/// On-device audit log for data access
@objc(LocalAuditLog)
public class LocalAuditLog: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var timestamp: Date
    @NSManaged public var action: String        // "read", "update", "export", "delete"
    @NSManaged public var dataCategory: String  // "preferences", "transcripts", etc.
    @NSManaged public var component: String     // "SessionManager", "SettingsView"
    @NSManaged public var success: Bool
    @NSManaged public var metadata: Data?       // Optional JSON details
}
```

### 7.2 Preference Inference Logic

Learning preferences can be derived from user behavior (with consent):

```swift
actor PreferenceInferenceEngine {

    /// Infer preferences from session behavior
    func inferFromSession(_ session: Session) async -> PreferenceUpdates? {
        guard await hasAdaptiveLearningConsent() else {
            return nil  // No inference without consent
        }

        var updates = PreferenceUpdates()

        // Example frequency: Based on "more examples" requests
        let exampleRequests = countExampleRequests(in: session)
        if exampleRequests > 3 {
            updates.exampleFrequency = .more
        }

        // Pacing: Based on interruption patterns
        let interruptionRate = session.interruptionCount / session.duration
        if interruptionRate > 0.1 {
            updates.explanationSpeed = .faster
        }

        // Difficulty: Based on mastery progression
        if let avgMastery = session.averageMasteryGain {
            if avgMastery < 0.1 {
                updates.difficultyMode = .adaptive
                updates.scaffoldingLevel = .high
            }
        }

        return updates
    }
}
```

---

## 8. Age Verification & Parental Consent (COPPA)

### 8.1 Age Gate Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    AGE VERIFICATION FLOW                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  First Launch                                                           │
│      │                                                                  │
│      ▼                                                                  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  "What is your age?"                                              │  │
│  │                                                                   │  │
│  │  ○ Under 13                                                       │  │
│  │  ○ 13-17                                                          │  │
│  │  ○ 18 or older                                                    │  │
│  │                                                                   │  │
│  │  [We ask to ensure we provide age-appropriate experiences]        │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│      │                                                                  │
│      ├──── Under 13 ────┐                                               │
│      │                  ▼                                               │
│      │         ┌──────────────────────────────────────────┐            │
│      │         │  PARENTAL CONSENT REQUIRED               │            │
│      │         │                                          │            │
│      │         │  UnaMentis collects learning data to     │            │
│      │         │  personalize your child's experience.    │            │
│      │         │                                          │            │
│      │         │  Please enter a parent's email:          │            │
│      │         │  [_______________________________]       │            │
│      │         │                                          │            │
│      │         │  We will send a verification link.       │            │
│      │         └──────────────────────────────────────────┘            │
│      │                  │                                               │
│      │                  ▼                                               │
│      │         ┌──────────────────────────────────────────┐            │
│      │         │  Email Sent! Waiting for verification... │            │
│      │         │                                          │            │
│      │         │  [Child can use basic features while     │            │
│      │         │   waiting - no preference tracking]      │            │
│      │         └──────────────────────────────────────────┘            │
│      │                  │                                               │
│      │                  ▼  Parent clicks link, verifies                 │
│      │         ┌──────────────────────────────────────────┐            │
│      │         │  ✓ Parental Consent Verified             │            │
│      │         │  Full features now enabled               │            │
│      │         └──────────────────────────────────────────┘            │
│      │                                                                  │
│      ├──── 13-17 ──────▶ Standard consent flow (GDPR: may need parent) │
│      │                                                                  │
│      └──── 18+ ────────▶ Adult consent flow                            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Parental Consent Verification

**Email-Plus Method** (FTC-approved):

1. Parent enters email address
2. System sends verification email with:
   - Clear description of data collected
   - Link to full privacy policy
   - Unique verification link (expires in 48 hours)
3. Parent clicks link, lands on verification page
4. Parent completes secondary verification:
   - Answer security question, OR
   - Enter last 4 digits of credit card, OR
   - Call toll-free number
5. Consent recorded with timestamp

```swift
struct ParentalConsentRecord: Codable {
    let childProfileId: UUID
    let parentEmail: String  // Encrypted
    let consentDate: Date
    let verificationMethod: VerificationMethod
    let ipAddress: String?   // Hashed, optional
    let consentVersion: String  // Privacy policy version
    let dataCollectionAgreed: [DataCategory]

    enum VerificationMethod: String, Codable {
        case emailPlus
        case creditCard
        case phoneCall
        case schoolAuthorization
    }
}
```

### 8.3 Child-Mode Restrictions

When parental consent is NOT obtained (or pending), the app operates in **Child-Safe Mode**:

| Feature | Full Mode | Child-Safe Mode |
|---------|-----------|-----------------|
| Voice tutoring | Yes | Yes (no history saved) |
| Learning preferences | Tracked | Not tracked |
| Session history | Saved | Not saved |
| Progress tracking | Full | Basic (not personalized) |
| Export data | Available | N/A |
| Adaptive difficulty | Yes | Fixed/simple |

### 8.4 School-Based Consent (FERPA Exception)

When deployed through an educational institution:

```swift
struct SchoolConsentRecord: Codable {
    let institutionId: UUID
    let institutionName: String
    let dpaSignedDate: Date
    let ferpaDesignation: Bool  // School official status
    let studentProfileIds: [UUID]
    let adminContact: String

    // Schools can consent on behalf of parents under FERPA
    // No individual parental consent required
}
```

---

## 9. Educational Institution Integration (FERPA)

### 9.1 School Deployment Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    FERPA DEPLOYMENT ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    EDUCATIONAL INSTITUTION                       │   │
│  │                                                                  │   │
│  │  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │   │
│  │  │   Student    │     │   Student    │     │   Student    │    │   │
│  │  │   Device 1   │     │   Device 2   │     │   Device N   │    │   │
│  │  │              │     │              │     │              │    │   │
│  │  │ All data    │     │ All data    │     │ All data    │    │   │
│  │  │ on-device   │     │ on-device   │     │ on-device   │    │   │
│  │  └──────────────┘     └──────────────┘     └──────────────┘    │   │
│  │         │                   │                   │               │   │
│  │         └───────────────────┼───────────────────┘               │   │
│  │                             │                                   │   │
│  │                             ▼                                   │   │
│  │  ┌──────────────────────────────────────────────────────────┐  │   │
│  │  │               School Admin Dashboard                      │  │   │
│  │  │                                                           │  │   │
│  │  │  • View aggregate class progress (de-identified)         │  │   │
│  │  │  • Individual progress (with teacher authorization)       │  │   │
│  │  │  • No access to conversation content                      │  │   │
│  │  │  • FERPA-compliant data export for eligible students     │  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  Data stays on student devices. School sees only:                       │
│  - Aggregate analytics (class-level, de-identified)                    │
│  - Individual progress (for assigned teachers only)                     │
│  - Completion status and mastery levels                                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 9.2 Data Processing Agreement (DPA) Requirements

Schools must sign a DPA that includes:

| Requirement | UnaMentis Commitment |
|-------------|---------------------|
| **School Official Designation** | UnaMentis acts as school official under direct control |
| **Purpose Limitation** | Data used only for educational purposes |
| **Subcontractor Restrictions** | No sharing with third parties without school approval |
| **Security Measures** | On-device encryption, no central storage of student data |
| **Breach Notification** | Notify school within 72 hours of any breach |
| **Data Return/Deletion** | Export/delete all data upon contract termination |
| **Audit Rights** | School may audit compliance annually |

### 9.3 Teacher Access Controls

```swift
/// Teacher authorization for student progress access
struct TeacherAuthorization: Codable {
    let teacherId: UUID
    let institutionId: UUID
    let authorizedStudentIds: Set<UUID>
    let accessLevel: AccessLevel
    let expiresAt: Date

    enum AccessLevel: String, Codable {
        case progressOnly     // Mastery, completion, time
        case includeScores    // Above + quiz scores
        case fullExport       // Above + exportable data
        // Note: NEVER includes transcript content
    }
}
```

### 9.4 Student/Parent Rights Under FERPA

| Right | Implementation |
|-------|----------------|
| **Inspect Records** | Parent/student can export all data on-device |
| **Request Amendment** | Settings allow correction of preferences |
| **Consent to Disclosure** | Opt-in for any external sharing |
| **File Complaint** | Link to Department of Education complaint process |

---

## 10. User Rights & Controls

### 10.1 Privacy Dashboard

All users have access to a Privacy Dashboard in Settings:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PRIVACY DASHBOARD                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Your Learning Data                                                     │
│  ─────────────────                                                      │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │  Data Stored on This Device                                   │     │
│  │                                                                │     │
│  │  • Learning Preferences       [View]  [Edit]                  │     │
│  │  • Session History (42)       [View]  [Clear]                 │     │
│  │  • Progress Data              [View]  [Export]                │     │
│  │  • Consent Records            [View]                          │     │
│  │                                                                │     │
│  │  Total Storage: 12.4 MB                                       │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│  Data Controls                                                          │
│  ─────────────                                                          │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │                                                                │     │
│  │  [Export All Data]     Download your data in portable format  │     │
│  │                                                                │     │
│  │  [Delete All Data]     Permanently remove all learning data   │     │
│  │                        (Requires authentication)              │     │
│  │                                                                │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│  Consent Settings                                                       │
│  ────────────────                                                       │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │                                                                │     │
│  │  Learning Preference Tracking     [●━━━━━━━━━━━━━━━━━━━━━]   │     │
│  │  Stores your learning style to personalize sessions           │     │
│  │                                                                │     │
│  │  Adaptive Difficulty              [━━━━━━━━━━━━━━━━━━━━━○]   │     │
│  │  AI adjusts difficulty based on your progress                 │     │
│  │                                                                │     │
│  │  Performance Metrics              [●━━━━━━━━━━━━━━━━━━━━━]   │     │
│  │  Tracks session latency for app improvement                   │     │
│  │                                                                │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│  Data Retention: [30 days ▼]                                           │
│                                                                         │
│  [View Privacy Policy]  [View Consent History]                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 10.2 Data Export Format

Export uses [xAPI](https://xapi.com/overview/) (IEEE 9274.1.1-2023) compatible format for interoperability:

```json
{
  "exportDate": "2024-12-28T10:30:00Z",
  "exportVersion": "1.0",
  "profile": {
    "id": "urn:uuid:550e8400-e29b-41d4-a716-446655440000",
    "created": "2024-01-15T08:00:00Z",
    "ageBracket": "adult"
  },
  "learningPreferences": {
    "exampleFrequency": "more",
    "explanationSpeed": "standard",
    "primaryModality": "auditory",
    "difficultyMode": "adaptive"
  },
  "statements": [
    {
      "actor": {
        "objectType": "Agent",
        "account": {
          "homePage": "https://unamentis.com",
          "name": "local-device-id"
        }
      },
      "verb": {
        "id": "http://adlnet.gov/expapi/verbs/completed",
        "display": { "en-US": "completed" }
      },
      "object": {
        "id": "urn:unamentis:topic:algebra-101",
        "objectType": "Activity",
        "definition": {
          "name": { "en-US": "Introduction to Algebra" }
        }
      },
      "result": {
        "score": { "scaled": 0.85 },
        "success": true,
        "duration": "PT45M"
      },
      "timestamp": "2024-12-20T14:30:00Z"
    }
  ],
  "progressSummary": {
    "totalSessionsCompleted": 42,
    "totalTimeSpent": "PT35H20M",
    "topicsCompleted": 15,
    "averageMastery": 0.78
  }
}
```

### 10.3 Data Deletion

Full deletion requires biometric authentication and removes:

- All Core Data entities (LearnerProfile, preferences, sessions, progress)
- All Keychain items (encryption keys, consent records)
- UserDefaults preferences
- Local audit log

```swift
actor DataDeletionManager {

    func deleteAllUserData() async throws {
        // Require biometric authentication
        try await requireBiometricAuthentication()

        // Log the deletion request (before deleting logs)
        await auditLog.record(.deletionRequested)

        // Delete in order
        try await deleteCoreDateEntities()
        try await deleteKeychainItems()
        try await clearUserDefaults()
        try await deleteLocalFiles()

        // Final confirmation
        await notifyUser(.dataDeleted)
    }
}
```

---

## 11. Implementation Roadmap

### Phase 1: Foundation (Privacy Infrastructure)

**Goal**: Establish core privacy infrastructure.

**Tasks**:
- [ ] Create `UnaMentis/Core/Privacy/` module
- [ ] Implement `SecurePreferenceEncryption` with Secure Enclave
- [ ] Add `LearnerProfile`, `PrivacyConsent` Core Data entities
- [ ] Create `PrivacyConsentManager` for consent tracking
- [ ] Add age gate to onboarding flow
- [ ] Implement `LocalAuditLog` entity

**Key Files**:
- `UnaMentis/Core/Privacy/SecurePreferenceEncryption.swift`
- `UnaMentis/Core/Privacy/PrivacyConsentManager.swift`
- `UnaMentis.xcdatamodeld` (new entities)

### Phase 2: Learning Preferences

**Goal**: Implement learning preference tracking with encryption.

**Tasks**:
- [ ] Define `LearningPreferences` data model
- [ ] Implement `LearnerProfileManager` actor
- [ ] Create encrypted storage/retrieval methods
- [ ] Add preference editing in Settings
- [ ] Integrate with `SessionManager` for loading preferences

**Key Files**:
- `UnaMentis/Core/Privacy/LearnerProfileManager.swift`
- `UnaMentis/UI/Settings/PrivacySettingsView.swift`

### Phase 3: COPPA Compliance

**Goal**: Full COPPA compliance for child users.

**Tasks**:
- [ ] Implement age gate UI
- [ ] Create parental consent flow (email-plus)
- [ ] Build Child-Safe Mode (restricted features)
- [ ] Add parental dashboard (view/delete child data)
- [ ] Test consent verification flow

**Key Files**:
- `UnaMentis/UI/Onboarding/AgeGateView.swift`
- `UnaMentis/Core/Privacy/ParentalConsentManager.swift`

### Phase 4: User Controls

**Goal**: Full user rights implementation.

**Tasks**:
- [ ] Build Privacy Dashboard UI
- [ ] Implement data export (xAPI format)
- [ ] Implement data deletion with biometric
- [ ] Add consent history viewer
- [ ] Create preference editor

**Key Files**:
- `UnaMentis/UI/Settings/PrivacyDashboardView.swift`
- `UnaMentis/Core/Privacy/DataExportManager.swift`

### Phase 5: Educational Integration

**Goal**: FERPA-compliant school deployment.

**Tasks**:
- [ ] Create DPA template document
- [ ] Build school admin authorization flow
- [ ] Implement teacher access controls
- [ ] Add aggregate reporting (de-identified)
- [ ] Document school deployment guide

**Key Files**:
- `docs/SCHOOL_DEPLOYMENT_GUIDE.md`
- `UnaMentis/Core/Privacy/InstitutionalAuthorizationManager.swift`

---

## 12. References & Standards Attribution

### 12.1 Regulatory References

| Regulation | Citation | URL |
|------------|----------|-----|
| **COPPA** | 16 CFR Part 312 | [FTC COPPA Rule](https://www.ftc.gov/legal-library/browse/rules/childrens-online-privacy-protection-rule-coppa) |
| **FERPA** | 20 U.S.C. § 1232g; 34 CFR Part 99 | [Protecting Student Privacy](https://studentprivacy.ed.gov/ferpa) |
| **GDPR** | Regulation (EU) 2016/679 | [GDPR Info](https://gdpr-info.eu/) |
| **California SOPIPA** | Cal. Bus. & Prof. Code § 22584 | [California Legislative Info](https://leginfo.legislature.ca.gov/) |
| **NY Ed Law 2-d** | Education Law § 2-d | [NY State Education](https://www.nysed.gov/) |

### 12.2 Technical Standards

| Standard | Reference | URL |
|----------|-----------|-----|
| **xAPI** | IEEE 9274.1.1-2023 | [IEEE xAPI Standard](https://standards.ieee.org/ieee/9274.1.1/7321/) |
| **W3C Privacy Principles** | W3C Statement, May 2025 | [W3C Privacy](https://www.w3.org/mission/privacy/) |
| **W3C Encrypted Data Vaults** | DIF/W3C CCG Draft | [Encrypted Data Vaults](https://digitalbazaar.github.io/encrypted-data-vaults/) |
| **Learning Record Store** | xAPI LRS Spec | [xAPI LRS](https://xapi.com/learning-record-store/) |

### 12.3 Apple Documentation

| Topic | URL |
|-------|-----|
| **Secure Enclave** | [Apple Developer Docs](https://developer.apple.com/documentation/security/certificate_key_and_trust_services/keys/protecting_keys_with_the_secure_enclave) |
| **Keychain Services** | [Apple Developer Docs](https://developer.apple.com/documentation/security/keychain_services) |
| **CryptoKit** | [Apple Developer Docs](https://developer.apple.com/documentation/cryptokit) |
| **Data Protection** | [Apple Developer Docs](https://developer.apple.com/documentation/uikit/protecting_the_user_s_privacy/encrypting_your_app_s_files) |
| **Local Differential Privacy** | [Apple ML Research](https://machinelearning.apple.com/research/learning-with-privacy-at-scale) |

### 12.4 Research References

| Topic | Reference |
|-------|-----------|
| **Apple's Privacy-Preserving ML** | [Learning with Privacy at Scale](https://machinelearning.apple.com/research/learning-with-privacy-at-scale) |
| **Federated Learning with DP** | [Apple ML Research](https://machinelearning.apple.com/research/fed-learning-diff-privacy) |
| **PPML Workshop 2025** | [Apple ML Updates](https://machinelearning.apple.com/updates/ppml-2025) |

---

*This document is maintained by the UnaMentis team. For questions or updates, create an issue in the repository.*

*Last reviewed: December 2024*
