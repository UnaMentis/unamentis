# Sub-Processors

This page lists the third-party services that may receive data when you use the
UnaMentis hosted beta. It reflects what is wired in the code today. It is a
factual disclosure of current practice and is subject to legal review before
general availability.

Last updated: 2026-05-31. Scope: the hosted beta (iOS client plus the minimal
AWS server). UnaMentis is for users 13 and older.

## What "sub-processor" means here

A sub-processor is an external service that receives some data to provide part
of the product. "External" below means data leaves UnaMentis-controlled
infrastructure. Self-hosted components run on the UnaMentis server or on your
device and do not send data to a third party.

## External sub-processors (data leaves UnaMentis)

| Service | Purpose | Data shared |
|---------|---------|-------------|
| **OpenAI (Realtime API)** | Real-time cloud voice inference (STT, LLM, TTS) for voice sessions when the OpenAI Realtime provider is selected. | Session audio, transcribed speech, conversation context, and model instructions. This is content data. Governed by OpenAI's policies. |
| **Wikimedia Commons API** | Server-side fallback acquisition of curriculum images during content import. Runs in the curriculum pipeline, not during user learning sessions. | Image titles, asset descriptions, and search keywords from curriculum content. No user or learner data. |
| **Remote syslog endpoint** (optional, operator-configured) | Optional off-box log aggregation if the server operator configures `DIAGNOSTIC_SYSLOG_HOST`. Not enabled by default; no provider is hardcoded. | Structured diagnostic logs. Client IP in these logs is coarsened (IPv4 to /24, IPv6 to /48). |

### Planned, not yet active

| Service | Status |
|---------|--------|
| **Amazon Bedrock** | Planned cloud LLM inference for a future server tier. Not wired today; no data is sent to Bedrock. This list will be updated if and when it ships. |

## Self-hosted / on-device components (data does not leave)

These process data locally on the UnaMentis server or on your device, with no
third-party egress: Ollama (local LLM for curriculum enrichment), VibeVoice,
Piper, and Chatterbox (local TTS), Silero VAD (local voice-activity detection),
and on-box metrics aggregation.

## Notes

- Selecting on-device providers in the client keeps audio and transcripts on the
  device and avoids the external voice sub-processor.
- The UnaMentis server itself does not store voice recordings or transcripts. It
  stores account data and aggregate, non-content session telemetry. See the
  [Privacy Policy](PRIVACY_PRESERVING_USER_DATA.md).
- Controller/processor roles, EU/UK scope, and a formal DPA are pending legal
  review and are not represented here.
