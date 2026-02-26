# Verified Knowledge Stream: Exploration & Architecture Proposal

**Version:** 1.0.0
**Date:** 2026-02-25
**Status:** Exploration / Proposal
**Author:** AI-Assisted Design

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Competitive Landscape Analysis](#2-competitive-landscape-analysis)
3. [Design Philosophy](#3-design-philosophy)
4. [Scientific Foundations: Verification Framework](#4-scientific-foundations-verification-framework)
5. [Architecture: Content Ingestion Pipeline](#5-architecture-content-ingestion-pipeline)
6. [Architecture: Verification Engine](#6-architecture-verification-engine)
7. [Architecture: Enhancement & Delivery Engine](#7-architecture-enhancement--delivery-engine)
8. [User Interaction & Configuration](#8-user-interaction--configuration)
9. [Integration with Existing UnaMentis Features](#9-integration-with-existing-unamentis-features)
10. [Data Model & Schemas](#10-data-model--schemas)
11. [Phased Rollout](#11-phased-rollout)
12. [Open Questions](#12-open-questions)
13. [Summary: What This Is and Isn't](#13-summary-what-this-is-and-isnt)
14. [References](#14-references)

---

## 1. Executive Summary

### The Opportunity

People consume more information than ever, from more sources, with more variation in quality. Podcasts, newsletters, social media, articles, and AI-generated content flood in from every direction. Much of it raises more questions than it answers. Some of it presents conclusions without evidence. Some applies rigorous methodology to important questions. The consumer has no reliable way to tell the difference.

UnaMentis is uniquely positioned to address this. The platform already supports voice-first, hands-free learning sessions. It already ingests web articles, PDFs, and markdown documents. It already chunks text for TTS playback. It has 9 STT providers, 8 TTS providers, and 5 LLM providers. The voice pipeline, content processing, and AI infrastructure all exist.

What's missing is a system that takes everything a user consumes and applies consistent, unbiased, evidence-based verification to it, then delivers the enhanced information through the same hands-free voice experience the user already relies on.

The market is wide open. Pocket shut down in July 2025, leaving millions of users without a read-it-later tool. No existing product combines voice-first interaction with scientific verification and integrated learning. Ground News shows bias ratings but has no voice interface. Snipd transcribes podcasts but doesn't verify claims. NotebookLM processes documents but isn't mobile-first. Nobody does all three.

### Current Gap

UnaMentis's Reading List module provides a strong foundation:

| System | Location | What It Does |
|--------|----------|--------------|
| `ReadingListManager` | `Core/ReadingList/ReadingListManager.swift` | Import and manage documents |
| `HTMLArticleExtractor` | `Core/ReadingList/HTMLArticleExtractor.swift` | Extract article content from web pages |
| `WebArticleFetcher` | `Core/ReadingList/WebArticleFetcher.swift` | Fetch and validate web content |
| `ReadingTextChunker` | `Core/ReadingList/ReadingTextChunker.swift` | Segment text for low-latency TTS |
| `ReadingListSourceType` | `Core/ReadingList/ReadingListSourceType.swift` | PDF, plain text, markdown, web article |
| Importer Plugins | `server/importers/core/plugin.py` | Pluggy-based content import framework |

What's missing:

- **Automated ingestion** from email, RSS, podcasts, and browser activity
- **Claim extraction** that identifies falsifiable statements in content
- **Verification pipeline** that cross-references claims against multiple sources
- **Source quality assessment** that scores publishers on methodology and track record
- **Bias detection** that flags framing, omissions, and emotional language
- **Enhanced playback** that weaves verification context into voice delivery
- **User configuration** for verification depth, trusted sources, and topic priorities

### Core Insight

> "Don't just read it. Verify it. Understand where it comes from, who benefits, and what the evidence says."

The Verified Knowledge Stream (VKS) extends the UnaMentis learning mission beyond formal curriculum to all information a user consumes. It applies the same rigor to a health newsletter that a good researcher applies to a journal article, not to tell the user what to believe, but to give them the context they need to decide for themselves.

---

## 2. Competitive Landscape Analysis

### 2.1 Competitive Matrix

| Product | Content Capture | Verification | Voice/Audio | Learning Integration | Mobile-First | Status |
|---------|:-:|:-:|:-:|:-:|:-:|--------|
| **Ground News** | News aggregation | Bias ratings, factuality | None | None | Yes (iOS/Android) | Active |
| **AllSides** | News aggregation | Left/center/right labels | None | None | Web-first | Active |
| **NewsGuard** | Browser extension | Human expert ratings (9 criteria) | None | None | Extension + apps | Active |
| **Snipd** | Podcasts | None | Transcription, summaries | Readwise/Notion export | iOS app | Active |
| **Podwise** | Podcasts | None | Transcription, insights | Notion/Obsidian export | Web-first | Active |
| **NotebookLM** | Documents upload | None (synthesis only) | Audio overview generation | None | Web-first | Active (Google) |
| **Perplexity** | Web search | Citations, source links | Voice queries (mobile) | None | Yes (iOS/Android) | Active |
| **Readwise Reader** | Articles, PDFs, RSS, newsletters | None | None | Spaced repetition | iOS app | Active |
| **Speechify** | Text, web, docs | None | Two-way voice (TTS + questions) | None | Yes (iOS) | Active |
| **ClaimBuster** | Live discourse, social media | NLP claim identification | None | None | API/web only | Research |
| **Consensus** | Academic papers | Supporting/contradicting evidence | None | None | Web-first | Active |
| **Elicit** | Academic literature | Systematic review automation | None | None | Web-first | Active |
| **UnaMentis VKS** | All formats + subscriptions | Scientific method pipeline | Voice-first, hands-free | Full learning loop | Yes (iOS native) | Proposed |

### 2.2 Gap Analysis

**Verification-focused tools** (Ground News, AllSides, NewsGuard) provide bias ratings and source quality scores but have no voice interface, no learning integration, and treat verification as a label rather than an explorable evidence chain. Ground News averages ratings from three bias organizations. NewsGuard employs journalists to rate 35,000+ sources on 9 criteria. Neither helps users engage with the evidence itself.

**Podcast AI tools** (Snipd, Podwise, ChatPods) excel at transcription, summarization, and knowledge extraction from audio content. They export to second-brain tools. But they don't verify any claims in the podcasts they transcribe. A podcast could make 20 factual claims in an hour and these tools would faithfully transcribe all of them without noting that half are disputed.

**Knowledge management tools** (NotebookLM, Perplexity, Consensus, Elicit) provide deep synthesis and citation tracking. Perplexity surfaces citations for every claim. Consensus specifically maps supporting versus contradicting evidence. But they're web-first, not voice-first, and they don't integrate into a learning workflow. They answer questions on demand rather than proactively enhancing content you're already consuming.

**Read-it-later tools** (Readwise Reader, Instapaper, Raindrop.io) capture content and organize it. Readwise Reader handles RSS, newsletters, PDFs, and YouTube transcripts. But these tools provide no verification, no voice playback beyond basic TTS, and no learning integration. Pocket's shutdown in July 2025 has left a significant gap in this space.

**Voice/TTS tools** (Speechify) come closest to UnaMentis's approach by offering two-way voice interaction with documents. Speechify reads content aloud and lets users ask questions. But it has no verification layer, no source quality assessment, and no connection to learning outcomes.

### 2.3 UnaMentis's Unique Position

No product in the market combines:
1. Voice-first, hands-free content consumption
2. Scientific-method-inspired claim verification with citations
3. Integrated learning workflows (content becomes curriculum)
4. On-device processing for privacy
5. Configurable verification depth through natural conversation
6. Multi-format ingestion (articles, podcasts, newsletters, documents)

The closest competitors would need to merge Ground News's bias detection, Snipd's podcast AI, Readwise's content capture, Perplexity's citation engine, and Speechify's voice interface. UnaMentis already has the voice pipeline, content processing, and AI infrastructure to build this as a natural extension.

### 2.4 Market Timing

- **Pocket shutdown (July 2025):** Millions of users actively seeking a new content consumption tool
- **AI verification feasibility:** LLMs with RAG now produce reliable claim verification when properly confidence-gated
- **Growing information quality concerns:** NewsGuard's August 2025 finding that AI tools repeat false news 35% of the time highlights the need for verification infrastructure
- **Mobile-first gap:** Most verification and knowledge tools remain web-first, leaving mobile users underserved

---

## 3. Design Philosophy

### 3.1 Scientific Rigor, Not Opinion

VKS does not tell users what to think. It does not label content as "true" or "false." It provides evidence, provenance, methodology assessment, and alternative perspectives. The user makes their own judgments with better information.

This mirrors how the scientific method itself works: it doesn't declare absolute truth. It establishes confidence levels based on evidence, reproducibility, and peer scrutiny. A claim supported by three independent meta-analyses gets a high confidence score. A claim from a single unreviewed source gets a low one. The system reports both without editorializing.

### 3.2 Voice-Native Verification

Verification insights are delivered conversationally, not as annotations or badges. When the user listens to an article, the AI voice naturally weaves in context: "This claim about coffee reducing cancer risk by 30% comes from a 2025 observational study. Three independent meta-analyses support a modest protective effect, though the magnitude varies from 12% to 30%, and the figure applies specifically to colorectal cancer."

This is how a knowledgeable friend would share information with you. Context arrives naturally, not as a popup or sidebar.

### 3.3 Privacy-First Content Processing

User content is sensitive. Newsletter subscriptions, browsing history, and podcast preferences reveal personal interests, political leanings, and health concerns.

VKS processes content on-device wherever possible. Email content never leaves the device. When server-side verification is needed (for web search cross-referencing), only extracted claims are sent, not full articles. The existing on-device Ministral-3B model handles claim extraction and basic verification locally. Server-side LLMs handle complex cross-referencing with anonymized claims.

### 3.4 Configurable Depth

Not every piece of content needs the same level of scrutiny. A recipe doesn't need the same verification as a health claim. Users control depth through:

- **Persistent settings:** Default verification depth per content type and topic
- **Voice commands:** "Verify this more thoroughly" or "Just give me the summary"
- **Automatic escalation:** The system deepens verification when it detects disputed or high-stakes claims (health, finance, safety)
- **Learning over time:** The system learns what the user cares about verifying based on their follow-up questions and engagement patterns

---

## 4. Scientific Foundations: Verification Framework

### 4.1 Established Verification Methods

VKS draws from four established frameworks, each contributing a specific capability:

| Framework | Origin | Strengths | Limitations | VKS Application |
|-----------|--------|-----------|-------------|-----------------|
| **SIFT** | Mike Caulfield (WSU) | Fast, practical, 4 clear steps | Binary good/bad thinking | Quick-check layer for initial triage |
| **CRAAP Test** | CSU Chico librarians | Comprehensive 5-dimension scoring | Subjective without data | Source quality scoring algorithm |
| **Scientific Method** | Research tradition | Rigorous, falsifiability-focused | Time-intensive | Deep verification of specific claims |
| **Triangulation** | Journalism/research | Multi-source corroboration | Requires diverse sources | Cross-reference engine design |

**SIFT (Stop, Investigate, Find, Trace):** Developed by Mike Caulfield, validated by Stanford History Education Group research showing that lateral readers (who leave a source to investigate it) dramatically outperform deep readers (who evaluate a source by reading it closely). VKS automates lateral reading.

**CRAAP Test (Currency, Relevance, Authority, Accuracy, Purpose):** The standard library framework for source evaluation. VKS implements each dimension as a computable score rather than a subjective judgment.

**Scientific Method:** The hypothesis-testing approach adapted for claims: formulate the claim as a testable hypothesis, seek both supporting and disproving evidence, weight evidence by methodology quality, and assign confidence based on the evidence balance.

**Triangulation:** The research methodology of comparing 2+ independent sources. VKS implements data triangulation (multiple sources), methodological triangulation (different evidence types), and investigator triangulation (different organizations reaching the same conclusion).

### 4.2 VKS Verification Pipeline

The pipeline layers these methods into a coherent process:

```
                    Content Arrives (any channel)
                              |
                              v
                 ┌──────────────────────────┐
                 │  Layer 1: SIFT Quick Check │
                 │                            │
                 │  - Spam/satire filter       │
                 │  - Publisher identification  │
                 │  - Source track record lookup│
                 │  - Original source tracing   │
                 └────────────┬───────────────┘
                              |
                              v
                 ┌──────────────────────────┐
                 │  Layer 2: Source Quality    │
                 │  (CRAAP-Inspired Scoring)   │
                 │                            │
                 │  - Currency: publication age │
                 │  - Relevance: topic match   │
                 │  - Authority: credentials    │
                 │  - Accuracy: citation count  │
                 │  - Purpose: intent analysis  │
                 └────────────┬───────────────┘
                              |
                              v
                 ┌──────────────────────────┐
                 │  Layer 3: Claim Extraction  │
                 │  & Verification             │
                 │                            │
                 │  - Extract falsifiable claims│
                 │  - Cross-reference sources   │
                 │  - Supporting evidence       │
                 │  - Contradicting evidence    │
                 │  - Confidence scoring        │
                 └────────────┬───────────────┘
                              |
                              v
                 ┌──────────────────────────┐
                 │  Layer 4: Bias Detection    │
                 │                            │
                 │  - Framing analysis         │
                 │  - Omission detection       │
                 │  - Emotional language        │
                 │  - Conflict of interest      │
                 └────────────┬───────────────┘
                              |
                              v
                 ┌──────────────────────────┐
                 │  Verification Report        │
                 │                            │
                 │  - Overall confidence (0-100)│
                 │  - Per-claim results         │
                 │  - Source quality rating      │
                 │  - Bias indicators           │
                 │  - Suggested further reading  │
                 └──────────────────────────┘
```

### 4.3 Confidence Scoring Model

VKS uses a transparent, multi-factor confidence score:

**Source Reliability Score (0-100)**
- Historical accuracy (correction frequency, retraction history)
- Methodology transparency (do they show their work?)
- Funding transparency (who pays for this content?)
- Editorial standards (fact-checking process, corrections policy)
- Peer assessment (how do other reliable sources cite this one?)

**Claim Verification Score (0-100)**
- Number of corroborating independent sources
- Quality of corroborating evidence (meta-analysis > single study > expert opinion)
- Presence of contradicting evidence and its quality
- Recency weight (newer evidence weighted higher for evolving topics)
- Methodological rigor of cited studies

**Combined Confidence Score**
```
confidence = (source_reliability * 0.3) + (claim_verification * 0.5) + (consensus_indicator * 0.2)
```

The weights reflect that claim-level evidence matters most, source reputation provides important context, and scientific consensus indicates the broader knowledge landscape.

**Consensus Categories:**
- **Strong consensus:** 90%+ of quality sources agree
- **Emerging consensus:** 60-90% agreement, active research
- **Contested:** Significant disagreement among credible sources
- **Insufficient evidence:** Not enough quality sources to assess

### 4.4 Cognitive Bias Detection

VKS actively monitors for biases, both in the content and in the user's consumption patterns:

| Bias | Detection Method | User Notification |
|------|-----------------|-------------------|
| **Confirmation bias** | Content clustering analysis across user's library | "You've consumed 8 articles supporting X this month. Here's a well-sourced alternative perspective." |
| **Availability heuristic** | Topic frequency vs. statistical base rates | "This topic is trending in your feeds, but the underlying data hasn't changed significantly." |
| **Authority bias** | Source diversity metrics | "This claim comes primarily from one institution. Here are independent assessments." |
| **Framing effect** | Sentiment/language comparison across sources | "Three sources report the same data with different framing. Here's a neutral summary." |
| **Anchoring bias** | First-exposure tracking per topic | "The first article you read on this topic used the figure 30%. Subsequent studies found 12-30%." |
| **Omission detection** | Cross-source coverage comparison | "This article discusses benefits but omits the side effects mentioned in three other sources." |

---

## 5. Architecture: Content Ingestion Pipeline

### 5.1 Ingestion Channel Overview

| Channel | Phase | Implementation Approach | Existing Infrastructure |
|---------|-------|------------------------|------------------------|
| Manual URL/Document | 1 (exists) | `WebArticleFetcher`, `ReadingListManager` | Full, production-ready |
| iOS Share Sheet | 1 | Share Extension + App Group | URL import pattern exists (`URLImportSheet.swift`) |
| RSS/Podcast Feeds | 2 | Server-side feed parser plugin | Pluggy framework (`server/importers/core/plugin.py`) |
| Email Newsletter | 2 | On-device IMAP/JMAP client | `HTMLArticleExtractor` reusable for email HTML |
| Safari Web Extension | 3 | Safari Web Extension API | Web article fetching infrastructure |
| MCP Server/Tool | 3 | MCP protocol handler | Existing MCP infrastructure in dev workflow |

### 5.2 Unified Content Model

All channels produce a normalized `VerifiableContent` structure that extends the existing Reading List data model:

```swift
/// Content ingested through any VKS channel, ready for verification
public struct VerifiableContent: Codable, Sendable {
    public let id: UUID
    public let sourceChannel: IngestionChannel
    public let originalURL: URL?
    public let title: String
    public let author: String?
    public let publisher: String?
    public let publishedDate: Date?
    public let rawText: String
    public let contentType: ContentType

    // Source metadata for verification
    public let sourceDomain: String?
    public let sourceReputationScore: Float?

    // Processing state
    public var verificationStatus: VerificationStatus
    public var claims: [ExtractedClaim]
    public var verificationReport: VerificationReport?

    // TTS-ready chunks (reuse existing infrastructure)
    public var chunks: [TextChunkResult]
}

public enum IngestionChannel: String, Codable, Sendable {
    case manual         // URL import, file import
    case shareSheet     // iOS Share Extension
    case rssFeed        // RSS/Atom subscription
    case podcast        // Podcast transcript
    case newsletter     // Email newsletter
    case browser        // Safari Web Extension
    case mcpTool        // MCP server integration
}

public enum ContentType: String, Codable, Sendable {
    case article
    case newsletter
    case podcastTranscript
    case socialPost
    case academicPaper
    case document
}

public enum VerificationStatus: String, Codable, Sendable {
    case pending        // Awaiting verification
    case inProgress     // Verification running
    case verified       // Verification complete
    case skipped        // User chose to skip
    case failed         // Verification could not complete
}
```

### 5.3 iOS Share Sheet Extension

The Share Extension captures URLs and text from any app:

```
┌────────────────────┐     ┌──────────────────┐     ┌────────────────────┐
│  Any iOS App       │────>│  Share Extension  │────>│  App Group Store   │
│  (Safari, News,    │     │                   │     │  (Shared Container)│
│   Podcasts, etc.)  │     │  - Receive URL    │     │                    │
└────────────────────┘     │  - Quick preview  │     │  - Queued items    │
                           │  - Queue for      │     │  - Sync on launch  │
                           │    processing     │     │                    │
                           └──────────────────┘     └────────┬───────────┘
                                                              |
                                                              v
                                                    ┌────────────────────┐
                                                    │  Main App          │
                                                    │                    │
                                                    │  - Pick up queued  │
                                                    │  - Normalize       │
                                                    │  - Enter pipeline  │
                                                    └────────────────────┘
```

The existing `URLImportSheet.swift` pattern provides the UI model. The Share Extension adds the system integration that lets users send content from any app.

### 5.4 RSS & Podcast Feed Engine

A server-side component using the existing importer plugin architecture:

```python
# New plugin type in server/importers/
class FeedIngestionPlugin:
    """
    Pluggy-based feed ingestion following the existing
    importer pattern at server/importers/core/plugin.py
    """

    @hookimpl
    def ingest_feed(self, feed_url: str, feed_type: FeedType) -> list[ContentItem]:
        # Parse RSS/Atom feed
        # For articles: fetch full content via readability extraction
        # For podcasts: fetch audio, transcribe via STT provider
        # Return normalized content items
        pass

    @hookimpl
    def get_feed_metadata(self, feed_url: str) -> FeedMetadata:
        # Title, description, update frequency, content type
        pass
```

Feed polling runs on a configurable schedule. New content is pushed to the device via the existing sync mechanism. Podcast transcription uses the same STT providers already available in UnaMentis.

### 5.5 Email Newsletter Ingestion

On-device processing for maximum privacy:

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Email Server     │────>│  On-Device IMAP  │────>│  Newsletter      │
│  (User's inbox    │     │  Client          │     │  Extraction      │
│   or dedicated    │     │                  │     │                  │
│   address)        │     │  - Fetch by rule │     │  - HTML extract  │
└──────────────────┘     │  - Filter junk   │     │    (reuses       │
                          │  - Match senders │     │    HTMLArticle   │
                          └──────────────────┘     │    Extractor)    │
                                                    │  - Normalize     │
                                                    └──────────────────┘
```

Two configuration options:
- **Dedicated forwarding address:** User sets up a forwarding rule from their main inbox to an address monitored by UnaMentis. Simpler, no credential management.
- **Direct IMAP access:** User provides IMAP credentials (stored in Keychain). More capable, allows filtering by sender/label. All processing on-device.

The existing `HTMLArticleExtractor` handles newsletter HTML-to-text conversion, stripping ads, tracking pixels, and navigation elements.

### 5.6 Content Normalization Pipeline

Regardless of ingestion channel, all content flows through the same normalization pipeline:

```
[Any Channel] ──> Content Normalization ──> Claim Extraction Queue ──> Verification ──> Enhanced Content

Normalization steps:
  1. HTML extraction (HTMLArticleExtractor)
  2. Text cleaning (strip boilerplate, ads, navigation)
  3. Metadata extraction (author, date, publisher, original URL)
  4. Language detection
  5. Text chunking for TTS (ReadingTextChunker)
  6. Source quality pre-scoring (domain lookup)
```

---

## 6. Architecture: Verification Engine

### 6.1 Claim Extraction

The LLM identifies falsifiable statements in normalized content:

```swift
public struct ExtractedClaim: Codable, Sendable {
    public let id: UUID
    public let text: String                       // The claim as stated
    public let normalizedText: String              // Standardized form for comparison
    public let claimType: ClaimType
    public let extractionConfidence: Float         // How confident we are this IS a claim
    public let sourceSpan: Range<Int>              // Character range in original text
    public var verificationResult: ClaimVerification?
}

public enum ClaimType: String, Codable, Sendable {
    case factual        // "Coffee reduces cancer risk by 30%"
    case statistical    // "73% of respondents said..."
    case causal         // "Lack of sleep causes weight gain"
    case attribution    // "According to NASA..."
    case opinion        // "This is the best approach" (flagged, not verified)
    case prediction     // "By 2030, all cars will be electric"
}
```

Claim types determine verification strategy. Factual and statistical claims get full cross-referencing. Causal claims get methodology scrutiny. Attribution claims get source tracing. Opinions are flagged as opinions. Predictions are noted with current evidence for/against.

### 6.2 Cross-Reference Engine

Multi-layer verification with graceful degradation:

```
┌──────────────────────────────────────────────────┐
│                Cross-Reference Engine              │
│                                                    │
│  ┌────────────────┐  ┌─────────────────────────┐ │
│  │ On-Device      │  │ Server-Side             │ │
│  │ Knowledge Base │  │                         │ │
│  │                │  │ ┌─────────────────────┐ │ │
│  │ - Embedded     │  │ │ Web Search          │ │ │
│  │   fact database│  │ │ (corroboration)     │ │ │
│  │ - User's own   │  │ └─────────────────────┘ │ │
│  │   verified     │  │ ┌─────────────────────┐ │ │
│  │   content      │  │ │ Source Reputation DB │ │ │
│  │ - Updated      │  │ │ (quality scores)    │ │ │
│  │   periodically │  │ └─────────────────────┘ │ │
│  └────────────────┘  │ ┌─────────────────────┐ │ │
│                       │ │ Academic Search     │ │ │
│                       │ │ (peer-reviewed)     │ │ │
│                       │ └─────────────────────┘ │ │
│                       └─────────────────────────┘ │
└──────────────────────────────────────────────────┘
```

**On-device knowledge base:** A curated, periodically updated database of well-established facts. Handles common claims without network access. The user's own verified content library becomes a personal knowledge graph over time, so previously verified claims can be referenced instantly.

**Server-side web search:** For claims not in the local database, the verification engine searches the web through the LLM provider's capabilities (RAG pattern). Results are filtered by source quality before being included as evidence.

**Academic search:** For claims citing research, the engine queries academic databases (Semantic Scholar API, CrossRef) to locate the original study and its citation context (supporting, contradicting, or contextualizing references).

### 6.3 Source Reputation Database

A curated, transparent database of source quality scores:

| Field | Description | Example |
|-------|-------------|---------|
| `domain` | Publisher domain | nytimes.com |
| `name` | Publisher name | The New York Times |
| `reliability_score` | Overall quality (0-100) | 82 |
| `methodology_score` | Rigor of reporting (0-100) | 85 |
| `correction_rate` | How often corrections are issued | 0.03 |
| `bias_direction` | Political/ideological lean | center-left |
| `bias_magnitude` | How strong the lean is (0-100) | 25 |
| `transparency_score` | Funding/ownership transparency (0-100) | 78 |
| `last_updated` | When this rating was last reviewed | 2026-01-15 |
| `methodology_note` | How the score was determined | Aggregated from NewsGuard, MBFC, Ad Fontes |

Initial data sources:
- NewsGuard ratings (35,000+ sources, 9 journalism criteria)
- Media Bias/Fact Check ratings
- Ad Fontes Media reliability/bias chart
- AllSides bias ratings

The database is transparent: users can see why a source has its score and override it for their own use ("I trust this source" / "I don't trust this source").

### 6.4 On-Device vs. Server Processing

| Operation | On-Device (Ministral-3B) | Server-Side (Cloud LLM) | Decision Criteria |
|-----------|:------------------------:|:-----------------------:|-------------------|
| Claim extraction | Short content (<2000 words) | Long/complex content | Content length, claim density |
| Source reputation lookup | Cached database | Full database | Cache hit/miss |
| Basic fact-checking | Common claims in local DB | Novel or complex claims | Local DB coverage |
| Web search verification | Not possible | Required | Always server |
| Academic search | Not possible | Required | Always server |
| Bias analysis | Basic framing detection | Nuanced analysis | Accuracy requirement |
| Report generation | Simple summaries | Detailed reports | Model capability |

The system degrades gracefully: without network, on-device processing still provides source quality scores (from cached DB) and basic claim extraction. The user is informed when verification is limited by connectivity.

---

## 7. Architecture: Enhancement & Delivery Engine

### 7.1 Verification-Enhanced TTS Playback

The defining user experience: listening to content with inline verification woven in by the AI voice.

**Verbosity Levels:**

**Minimal** (quick badges, interrupts only for problems):
> "A new study found that coffee reduces cancer risk by 30%." *[No interruption, claim is well-supported]*
>
> "A new breakthrough pill cures diabetes in one week." *[Verification note: This claim could not be verified. The cited study has not been peer-reviewed.]*

**Standard** (brief context for key claims):
> "A new study found that coffee reduces cancer risk by 30%. *By the way, this figure comes from a large observational study and is specifically about colorectal cancer. Three meta-analyses support a protective effect, though estimates range from 12% to 30%.*"

**Thorough** (full citations and counter-evidence):
> "A new study found that coffee reduces cancer risk by 30%. *This statistic comes from a 2025 prospective cohort study by Chen et al., published in the Journal of Clinical Oncology, tracking 50,000 participants over 12 years. The 30% figure refers to colorectal cancer, not all cancers. Supporting evidence includes meta-analyses by Park et al. (2023, n=41 studies, OR=0.74) and Liu et al. (2024, n=28 studies, OR=0.82). A dissenting analysis by Freedman et al. (2024) found only a 12% reduction when controlling for additional lifestyle factors. The scientific consensus is that moderate coffee consumption is likely protective against colorectal cancer, with the magnitude of effect still being refined.*"

### 7.2 Interactive Voice Exploration

During playback, users can interrupt with natural voice commands:

- **"Tell me more about that study"** triggers a deeper dive into the cited research
- **"Who funded this research?"** surfaces funding and conflict-of-interest information
- **"What's the counter-argument?"** presents the strongest opposing evidence
- **"How reliable is this source?"** gives the publisher's reputation summary
- **"Skip verification for this article"** turns off enhancement for the current item
- **"Flag this for later"** bookmarks a claim for follow-up research

This leverages the existing voice pipeline (STT -> LLM -> TTS) with the verification report loaded into the FOV context manager as additional context.

### 7.3 Visual Verification Dashboard

When the user has screen access, a visual layer overlays the reading experience:

```
┌─────────────────────────────────────────────────┐
│  Article: "Coffee and Cancer: New Research"       │
│  Source: Health Science Weekly                     │
│  ┌─────────────────────────────────────────────┐ │
│  │  Source Quality: ████████░░ 78/100           │ │
│  │  Overall Confidence: ███████░░░ 71/100       │ │
│  │  Bias: Slight pro-supplement lean            │ │
│  └─────────────────────────────────────────────┘ │
│                                                    │
│  "A new study found that coffee reduces cancer    │
│  risk by [30%]←── Tap for evidence chain          │
│                    ┌──────────────────────┐       │
│                    │ ● Verified (3 sources) │      │
│                    │ ● Range: 12-30%        │      │
│                    │ ● Colorectal specific   │      │
│                    │ ▸ View full evidence    │      │
│                    └──────────────────────┘       │
│                                                    │
│  Researchers at Stanford University               │
│  [confirmed]←── Attribution verified               │
│  that moderate consumption is associated with..."  │
└─────────────────────────────────────────────────┘
```

Claim badges are color-coded:
- **Green:** Well-supported by multiple quality sources
- **Yellow:** Partially supported or context-dependent
- **Orange:** Disputed or limited evidence
- **Red:** Contradicted by stronger evidence
- **Gray:** Opinion, not a factual claim

### 7.4 Learning Integration

Verified content connects to the UnaMentis learning journey:

**Knowledge Bowl integration:** Well-verified facts from content the user consumed become quiz questions. "Last week you read that moderate coffee consumption may reduce colorectal cancer risk. What percentage range do meta-analyses suggest?"

**Discussion topics:** Disputed or nuanced claims become learning session conversation starters. "An article you read made a claim about sleep and weight gain that has mixed evidence. Would you like to explore the research together?"

**Curriculum suggestions:** Content themes can suggest formal curriculum additions. "You've been reading a lot about nutrition science. Would you like to add a structured nutrition module to your learning plan?"

**Media literacy module:** VKS itself becomes a teaching tool. "Let's practice evaluating a claim together. I'll walk you through the SIFT method on this article."

---

## 8. User Interaction & Configuration

### 8.1 Voice-First Configuration

Users configure VKS through natural conversation:

| Voice Command | Effect |
|--------------|--------|
| "Verify everything from [author/publisher] more carefully" | Increases verification depth for that source |
| "I trust [source], skip detailed verification" | Adds to trusted list, minimal verification |
| "Focus on scientific claims, skip product reviews" | Sets topic priority filter |
| "Give me the full context for health claims" | Sets thorough verbosity for health topics |
| "This source got something wrong" | Opens correction flow, adjusts personal score |
| "Why did you flag that?" | Explains the verification reasoning |
| "Show me what I've been reading this week" | Consumption summary with verification stats |

### 8.2 Settings UI

Persistent configuration accessible in the app's Settings:

**Verification Settings**
- Default verification depth: Minimal / Standard / Thorough
- Auto-escalation: Automatically increase depth for health, finance, safety claims
- Offline mode behavior: Skip verification / Use cached data only / Queue for later

**Content Sources**
- Manage RSS/podcast subscriptions
- Configure email ingestion (forwarding address or IMAP)
- Enable/disable Safari extension
- Enable/disable MCP tool integration

**Source Management**
- Trusted sources list (reduced verification)
- Untrusted sources list (increased verification)
- Custom source scores (override database ratings)

**Topic Priorities**
- Topics requiring thorough verification (e.g., health, finance)
- Topics where minimal verification is sufficient (e.g., entertainment)
- Topics to exclude from verification entirely

**Processing Schedule**
- Immediate: Verify as content arrives
- Batch: Verify all pending content at a scheduled time (e.g., morning briefing)
- Manual: Verify only when user requests

**Privacy**
- Which content types can use server-side verification
- Data retention period for verification reports
- Opt-in/out of anonymized consensus data sharing

### 8.3 Onboarding Flow

A voice-guided onboarding experience:

1. **Introduction:** "I can help you understand the quality and context of everything you read and listen to. I won't tell you what to think, just give you better information to think with."
2. **Channel setup:** Walk through enabling Share Sheet, email, and RSS sources
3. **Depth calibration:** Process a sample article at each verbosity level, let user choose their default
4. **Topic priorities:** "Are there topics where you want me to be especially thorough? Health claims? Financial advice?"
5. **First verification:** Process one of the user's saved articles to demonstrate the full pipeline

---

## 9. Integration with Existing UnaMentis Features

### 9.1 Reading List Integration

VKS extends the existing Reading List rather than replacing it:

- `ReadingListSourceType` gains new cases: `.newsletter`, `.rssFeed`, `.podcastTranscript`
- `ReadingListItem` (Core Data entity) gains a relationship to `VerificationReport`
- Existing TTS chunking via `ReadingTextChunker` is reused without modification
- The `ReadingPlaybackService` gains a "verified mode" that intersperses verification context between chunks
- `HTMLArticleExtractor` is reused for newsletter and web content normalization
- `WebArticleFetcher` is reused for RSS article full-text retrieval

### 9.2 Session Manager Integration

Learning sessions can reference the user's verified content library:

- System prompt includes relevant verification context when the user discusses topics they've consumed content about
- "Let's discuss an article you read this week" triggers a session focused on exploring verified and disputed claims
- Session transcripts capture the user's engagement with verification, informing the Learner Profile
- FOV Context Management (`docs/architecture/FOV_CONTEXT_MANAGEMENT.md`) handles windowing verification data into the LLM context

### 9.3 Curriculum Engine Integration

- Auto-suggest curriculum topics based on content consumption themes
- Verified content can be imported as supplementary reading within existing curriculum modules
- Verification reports feed into the Learner Profile (what topics is the user consuming? what depth do they engage at?)
- The existing importer plugin architecture handles new content source types

### 9.4 Telemetry Integration

New telemetry events for VKS (extending the existing `TelemetryEngine`):

| Event | Data | Purpose |
|-------|------|---------|
| `content_ingested` | Channel, content type, word count | Volume and source tracking |
| `verification_completed` | Depth, duration, confidence distribution | Pipeline performance |
| `verification_engagement` | Did user listen to context? Ask follow-ups? | Feature value measurement |
| `claim_interaction` | Which claims did user explore? | Interest and depth patterns |
| `source_override` | User trusted/untrusted a source | Personalization signal |
| `correction_submitted` | User disputed a verification result | Accuracy improvement |

---

## 10. Data Model & Schemas

### 10.1 Core Data Extensions (iOS)

New entities for the iOS Core Data model:

```
VerificationReport
├── id: UUID (primary key)
├── contentItemId: UUID (foreign key to ReadingListItem)
├── createdAt: Date
├── overallConfidenceScore: Float (0-100)
├── sourceQualityScore: Float (0-100)
├── biasDirection: String? (left, center-left, center, center-right, right)
├── biasMagnitude: Float? (0-100)
├── verificationDepth: String (minimal, standard, thorough)
├── reportJSON: String (full structured report)
└── claims: [VerifiedClaim] (one-to-many relationship)

VerifiedClaim
├── id: UUID (primary key)
├── reportId: UUID (foreign key to VerificationReport)
├── claimText: String
├── claimType: String (factual, statistical, causal, attribution, opinion, prediction)
├── verificationStatus: String (verified, disputed, unverifiable, opinion, insufficient_evidence)
├── confidenceScore: Float (0-100)
├── evidenceSummary: String
├── sourcesJSON: String (array of citation objects)
├── sourceSpanStart: Int (character offset in original text)
├── sourceSpanEnd: Int (character offset in original text)
└── report: VerificationReport (inverse relationship)

ContentSource
├── id: UUID (primary key)
├── domain: String (indexed, unique)
├── name: String
├── reliabilityScore: Float (0-100)
├── methodologyScore: Float (0-100)
├── biasDirection: String?
├── biasMagnitude: Float?
├── transparencyScore: Float (0-100)
├── lastUpdated: Date
├── methodologyNote: String
└── userTrustOverride: String? (trusted, untrusted, nil for default)

FeedSubscription
├── id: UUID (primary key)
├── feedURL: String
├── feedType: String (rss, atom, podcast, newsletter)
├── title: String
├── lastPolled: Date?
├── pollInterval: Int (seconds)
├── isEnabled: Bool
├── verificationDepth: String (minimal, standard, thorough)
└── items: [ReadingListItem] (one-to-many relationship)
```

### 10.2 Server-Side Schema

For the management API database (extending existing Python/aiohttp backend):

```sql
-- Source reputation data (periodically synced to devices)
CREATE TABLE source_reputation (
    domain TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    reliability_score REAL NOT NULL,
    methodology_score REAL NOT NULL,
    bias_direction TEXT,
    bias_magnitude REAL,
    transparency_score REAL,
    correction_rate REAL,
    data_sources TEXT NOT NULL,  -- JSON array of rating sources
    last_reviewed DATE NOT NULL,
    methodology_note TEXT
);

-- Verification result cache (avoid re-verifying identical claims)
CREATE TABLE verification_cache (
    claim_hash TEXT PRIMARY KEY,  -- SHA-256 of normalized claim text
    result_json TEXT NOT NULL,
    confidence_score REAL NOT NULL,
    sources_json TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    hit_count INTEGER DEFAULT 0
);

-- Feed subscription management
CREATE TABLE feed_subscriptions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    feed_url TEXT NOT NULL,
    feed_type TEXT NOT NULL,
    title TEXT,
    poll_interval INTEGER DEFAULT 3600,
    last_polled TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE(user_id, feed_url)
);
```

### 10.3 UMCF Extensions

For verified content that enters the curriculum, optional UMCF metadata:

```json
{
  "metadata": {
    "source": "vks_ingestion",
    "verification": {
      "verified_at": "2026-02-25T10:00:00Z",
      "confidence_score": 87,
      "source_quality_score": 78,
      "sources_count": 5,
      "verification_depth": "standard",
      "methodology": "vks_v1"
    }
  }
}
```

---

## 11. Phased Rollout

### Phase 1: Foundation (Enhanced Reading List)

**Duration:** 4-6 weeks
**Goal:** Extend the existing Reading List with basic verification and new ingestion

- Extend `ReadingListSourceType` with `.newsletter`, `.rssFeed`, `.podcastTranscript`
- Implement iOS Share Sheet extension for capturing URLs from any app
- Add basic claim extraction using on-device LLM (Ministral-3B)
- Implement source quality lookup against curated database
- Display verification badges on Reading List items (green/yellow/orange/red)
- Voice playback with minimal verification context (flag unverified claims only)
- Core Data schema additions (VerificationReport, VerifiedClaim, ContentSource)

**Success criteria:** Users can share articles from Safari, see source quality badges, and hear basic verification notes during playback.

### Phase 2: Verification Engine

**Duration:** 6-8 weeks
**Goal:** Full 4-layer verification pipeline

- Implement all four verification layers (SIFT, source quality, claim verification, bias detection)
- Server-side cross-reference engine with web search and academic search
- Configurable verification depth (minimal/standard/thorough)
- Interactive voice follow-up on claims during playback
- Visual verification dashboard for on-screen reading
- Confidence scoring model with transparent methodology
- Source reputation database with initial 10,000+ sources

**Success criteria:** Users can listen to articles with inline verification at their chosen depth and ask follow-up questions about specific claims.

### Phase 3: Multi-Channel Ingestion

**Duration:** 4-6 weeks
**Goal:** RSS, email, and browser extension support

- RSS/podcast feed engine as server-side importer plugin
- Podcast transcription using existing STT providers
- Email newsletter ingestion with on-device processing
- Safari Web Extension for one-tap content capture
- Feed subscription management UI
- Background processing with notification of newly verified content
- Processing schedule options (immediate, batch, manual)

**Success criteria:** Users receive a daily verified digest of their subscriptions, accessible hands-free.

### Phase 4: Learning Integration

**Duration:** 4-6 weeks
**Goal:** Connect verified content to the learning journey

- Verified facts become Knowledge Bowl questions
- Disputed claims become learning session discussion topics
- Curriculum suggestions based on content consumption themes
- Media literacy module teaching the SIFT method and source evaluation
- Personal knowledge graph from verified content library
- Bias awareness tracking integrated into Learner Profile
- Consumption analytics ("What have I been reading? How verified is it?")

**Success criteria:** Learning sessions reference content the user has consumed, and verified facts appear in Knowledge Bowl.

### Phase 5: Intelligence Layer

**Duration:** 4-6 weeks
**Goal:** Proactive insights and advanced integration

- Proactive alerts: "Three sources you follow disagree about X"
- Content recommendations to fill verification gaps
- MCP server/tool for AI workflow integration
- Cognitive bias tracking and periodic nudges
- Cross-user anonymized consensus data (opt-in)
- Verification quality feedback loop (correction tracking improves future accuracy)
- API for third-party integration

**Success criteria:** Users receive proactive insights that help them notice patterns in their information consumption they wouldn't have seen otherwise.

---

## 12. Open Questions

### 12.1 Verification Accuracy Standards

How do we handle verification errors? When VKS marks a claim as "verified" and it turns out to be wrong, or marks a claim as "disputed" when it's well-established?

**Options:**
- Transparent confidence scores with clear caveats ("Based on 3 sources, confidence 72%")
- User correction mechanism that improves future accuracy
- Regular accuracy audits against known fact-check databases
- Disclaimer that VKS provides context, not definitive truth

### 12.2 Political Neutrality

VKS must avoid being perceived as politically biased. Content touching political topics requires special care.

**Options:**
- Focus exclusively on falsifiable factual claims, skip opinion framing
- Present all perspectives with evidence quality ratings, let users decide
- Allow users to configure political sensitivity levels
- Use multiple bias-rating sources to triangulate, avoiding reliance on any single rater

### 12.3 Source Reputation Governance

Who maintains the source reputation database? This is a sensitive responsibility.

**Options:**
- Curated by the team with transparent methodology documentation
- Aggregated from multiple independent rating organizations (NewsGuard, MBFC, Ad Fontes)
- Community-driven with moderation and transparent dispute resolution
- User-configurable with personal overrides (current baseline)

**Recommendation:** Aggregate from established third parties (Option B) with user overrides. This avoids UnaMentis becoming an arbiter of source quality while leveraging expert assessment.

### 12.4 Monetization

Could VKS be a premium feature?

**Considerations:**
- Basic verification (source badges, minimal context) could be free
- Full pipeline (thorough depth, web cross-referencing, academic search) requires server costs
- Email and RSS ingestion have infrastructure costs
- Subscription tiers could map to verification depth and processing volume

### 12.5 Scale and Rate Limits

Real-time web search verification has costs and rate limits.

**Mitigation strategies:**
- Verification result caching (same claim doesn't need re-verification within TTL)
- Batch processing for non-urgent content
- Tiered verification depth based on content priority
- On-device processing for common claims to reduce server load

### 12.6 Legal Considerations

- **Copyright:** Ingesting newsletter and RSS content for private use is generally fair use, but republishing verification reports that include excerpts needs review
- **Email privacy:** Accessing user email requires clear consent and secure credential storage
- **Source reputation claims:** Publishing quality scores about news sources could attract legal challenges. Aggregating from established raters provides defensibility
- **GDPR/privacy:** Verification reports contain derived personal data (what the user reads) and must comply with data protection regulations

---

## 13. Summary: What This Is and Isn't

### This IS:

- A **verification system** that helps users understand the quality and context of information they consume
- A **voice-native experience** that delivers insights through natural conversation
- An **extension of UnaMentis's learning mission** to all information, not just formal curriculum
- A **configurable system** where users control depth, topics, and trusted sources
- A **privacy-first design** that processes sensitive content on-device
- Built on **existing infrastructure** (Reading List, TTS pipeline, LLM providers, importer plugins)
- Grounded in **established verification frameworks** (SIFT, CRAAP, scientific method, triangulation)

### This IS NOT:

- A **fact-checker** that declares content "true" or "false"
- A **political bias detector** that tells users what to think
- A **news aggregator** or social media feed
- A **replacement for critical thinking** (it strengthens critical thinking by providing better inputs)
- A **content filter or censor** (all content is presented, verification is additive)
- A **single source of truth** (it surfaces evidence and lets users decide)

---

## 14. References

### Verification Frameworks

1. Caulfield, M. "SIFT (The Four Moves)." Hapgood Blog. https://hapgood.us/2019/06/19/sift-the-four-moves/
2. Blakeslee, S. "The CRAAP Test." California State University, Chico. https://library.csuchico.edu/help/source-or-information-good
3. Stanford History Education Group (2017). "Lateral Reading: Reading Less and Learning More." https://purl.stanford.edu/yk133ht8603
4. University of Iowa Libraries. "Lateral Reading Guide." https://guides.lib.uiowa.edu/c.php?g=849536&p=6077640

### Media Literacy & Bias

5. Ground News. "Media Bias Ratings." https://ground.news/
6. AllSides. "Media Bias Ratings." https://www.allsides.com/media-bias
7. NewsGuard. "Nutrition Label for the Internet." https://www.newsguardtech.com/
8. Ad Fontes Media. "Media Bias Chart." https://adfontesmedia.com/

### AI Fact-Checking Research

9. Frontiers in AI (2024). "Perils and Promises of Fact-Checking with Large Language Models." https://www.frontiersin.org/journals/artificial-intelligence/articles/10.3389/frai.2024.1341697/full
10. PNAS (2024). "Fact-checking information from large language models decreases headline discernment." https://www.pnas.org/doi/10.1073/pnas.2322823121
11. ArXiv (2025). "From Hallucination to Truth: A Survey." https://arxiv.org/html/2508.03860v1
12. Nature AI Intelligence (2025). "Large language models in the scientific method." https://www.nature.com/articles/s44387-025-00019-5

### Cognitive Bias Research

13. PMC (2024). "Impact of Confirmation Bias Awareness on Susceptibility to Misinformation." https://pmc.ncbi.nlm.nih.gov/articles/PMC11518834/
14. Nature Scientific Reports (2024). "Confirmation Bias as a Factor in Information Evaluation." https://www.nature.com/articles/s41598-024-78053-7
15. The Decision Lab. "Confirmation Bias." https://thedecisionlab.com/biases/confirmation-bias

### Triangulation Methodology

16. Better Evaluation. "Triangulation." https://www.betterevaluation.org/methods-approaches/methods/triangulation
17. Scribbr. "Triangulation in Research." https://www.scribbr.com/methodology/triangulation/

### Competitors

18. Snipd. "AI Podcast Player." https://www.snipd.com/
19. Podwise. "The AI Podcast Knowledge Management." https://podwise.ai/
20. NotebookLM. "Your AI Research Assistant." https://notebooklm.google.com/
21. Perplexity. "Ask Anything." https://www.perplexity.ai/
22. Readwise. "Reader." https://readwise.io/read
23. Speechify. "Voice AI Assistant." https://speechify.com/
24. Consensus. "Evidence-Based Answers, Faster." https://consensus.app/
25. ClaimBuster. "Automated Claim Detection." https://idir.uta.edu/claimbuster/

### Epistemology of Fact-Checking

26. Sage Journals (2025). "Fact-Checking as Epistemic Infrastructure." https://journals.sagepub.com/doi/10.1177/27523543251344972
27. Springer (2025). "Automating Epistemology." https://link.springer.com/article/10.1007/s00146-025-02560-y

---

*Document created as exploration and proposal. Implementation decisions pending review.*
