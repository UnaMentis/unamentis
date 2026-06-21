# UnaMentis: What Works Today

**Last Updated:** 2026-06-11

This page is deliberately blunt. It says what runs today, what runs with caveats, and what does not exist yet. The aspirational view lives in [PROJECT_OVERVIEW.md](architecture/PROJECT_OVERVIEW.md) and the roadmap; this page is the reality check.

---

## Voice Pipeline

**Works today.** The iOS app ([unamentis-ios](https://github.com/UnaMentis/unamentis-ios)) runs the full loop: microphone capture, Silero VAD, streaming STT, LLM, streaming TTS, playback, with barge-in (interrupt the AI by speaking). Cloud providers (Deepgram, AssemblyAI, Groq, Anthropic, OpenAI, ElevenLabs) and self-hosted providers (Ollama, whisper.cpp, Piper, Chatterbox, VibeVoice, Kyutai) are wired and selectable.

Caveats:
- Latency targets (<500ms median E2E) are met on localhost test configurations; real-network performance varies by provider.
- Some STT enum cases are not wired into the live session path (see the unamentis-ios audit); the selectable set is smaller than the implementation count.
- The web client does voice through the OpenAI Realtime API only.

## On-Device Inference

**Now real (as of 2026-06-11).**
- **LLM:** llama.cpp b7263 xcframework is integrated with `LLAMA_AVAILABLE` enabled in Debug and Release. `OnDeviceLLMService` has been proven generating real tokens with the Ministral 3B GGUF in the iPhone 17 Pro simulator.
- **TTS:** Kyutai Pocket TTS (100M, Rust/Candle) runs on-device and is the primary on-device TTS.
- **STT:** Apple Speech always works on-device; FluidAudio (Parakeet, CoreML) provides streaming on-device STT with end-of-utterance detection.

Caveats:
- The Settings "Load Model" button is a stub; model loading happens through the session path.
- Model display names need cosmetic cleanup.
- Physical-device validation and latency characterization are still pending; simulator is proven, device numbers are not yet published.
- GLM-ASR on-device remains blocked on a llama.cpp wrapper update.
- MLX with Qwen3-class models is the research direction, not shipping code.

## Curriculum and Content

**Format done, content thin.** The UMCF v1.0 specification and JSON Schema are complete. The repo ships an example UMCF library (13 example files), not a content catalog.

- Source importers are implemented for MIT OCW, CK-12, EngageNY, and MERLOT, plus Knowledge Bowl question sources (QBReader, OpenTriviaQA, DOE Science Bowl, Core Knowledge).
- Imports land in a local curriculum database; the often-cited "247 courses" is a development instance, not shipped content.
- The AI enrichment pipeline (the part that turns raw imports into rich, voice-ready UMCF) is in progress; the enricher/parser plugin directories are currently empty.

## Telemetry

**Works, privacy-aware, recently hardened (2026-06-10/11).**
- Server persists metrics/logs/clients in SQLite (survives restart), with an allow-list of accepted fields, byte caps, typed error counts, TTFA and P99 metrics, and unique-session counting.
- iOS uploads are consent-gated behind a 13+ onboarding attestation, revocable in Settings; the endpoint is HTTPS-capable; the IDFV exporter is compiled out of release builds.
- Only aggregate, non-content metrics are uploaded (latency, counts, costs); no transcripts or audio.
- The Operations Console shows live-vs-mock state, P99/TTFA, and error rates.

## Security Posture

**Beta-grade and improving; audits are public.** See [docs/reviews/](reviews/) for the 2026-05-30 security audit and follow-ups.
- Landed: JWT auth with rate limiting, authenticated audio WebSocket, consent records with policy versioning, coarsened intake IPs with 90-day auth IP retention, CSP (enforcing plus report-only with reporting endpoints) on both web apps, daily realtime spend budget, importer SSRF/zip-slip guards, WebSocket token redaction in logs.
- Not yet: multi-tenancy, per-tenant encryption, SOC 2 anything. Authentication is appropriate for a small beta, not for scale.

## Quality Gates (honest version)

- Server coverage is reported to Codecov but informational; thresholds are intentionally low while they ratchet up (web client hard-fails below a 5% floor).
- The iOS 80% coverage gate lives in unamentis-ios CI and is currently soft.
- Mutation testing runs weekly but is advisory (non-blocking).
- Lint gates (Ruff, ESLint, Clippy, SwiftLint) are real and enforced.

## Not Done Yet

| Item | Status |
|------|--------|
| TestFlight beta | Not submitted. Preparation is active; submission is a human decision. |
| Android client | Paused since February 2026. |
| AI enrichment pipeline | In progress; not usable end to end. |
| USM Core crash supervision | Deferred post-beta (restart policy, crash-loop breaker). |
| Lambda serverless tier | Parked. Auth handler exists; curriculum/metrics handlers are stubs. The beta runs on the aiohttp Management API. |
| Fast.ai / Stanford SEE importers | Spec complete, not implemented. |
| Multi-user team sync (Knowledge Bowl) | In progress (WebSocket sync pending). |
| Physical-device on-device LLM benchmarks | Pending; simulator proven only. |

---

If this page disagrees with any other document, this page is more recent or the other document is wrong. Please open an issue either way.
