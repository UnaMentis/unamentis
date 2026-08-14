# On-device LLM and FOV context: stocktake

**Status:** live · **Class:** state · **Date:** 2026-08-12
**Supersedes:** [AI_MODEL_SELECTION_2026.md](../AI_MODEL_SELECTION_2026.md) (partial: its on-device LLM sections only, which were already superseded by the June 2026 iOS decision record)
**Superseded by:** none

Where the on-device LLM stack and the FOV context system actually stand on 2026-08-12, what
is open, and what the August 2026 model landscape changes about the June decision. Lifecycle
rules: [DOCUMENTATION-LIFECYCLE.md](../DOCUMENTATION-LIFECYCLE.md).

Related document: `docs/status/2026-07-28-ios-beta-readiness.md` covers what remains before the
iOS TestFlight beta. It is a separate stocktake and was not yet committed when this one was
written, so the link is by filename only.

Repos examined: `unamentis`, `unamentis-ios`. Every repo claim below was checked against the
files on 2026-08-12.

## 1. On-device LLM

The canonical decision record is
[unamentis-ios/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md](https://github.com/UnaMentis/unamentis-ios/blob/main/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md)
(written 2026-06-20, carried through 2026-06-26). It replaced the Ministral-3-3B choice made
during the 2026-06-10 overnight sprint.

### The decided ladder

Selection is by physical RAM, implemented in
`UnaMentis/Services/LLM/OnDeviceLLMModelManager.swift` (`recommendedForDevice` and
`bestRunnableForDevice`).

| Device RAM | Model | Artifact | Size |
|---|---|---|---|
| 12 GB and up | Gemma 4 E2B | `unsloth/gemma-4-E2B-it-GGUF`, Q4_K_M, ctx 8192 | 3.11 GB |
| 8 GB | Qwen3 1.7B | `unsloth/Qwen3-1.7B-GGUF` | ~1.05 GB |
| 6 GB | Qwen3 0.6B | GGUF | ~400 MB |
| below 6 GB | none, server LLM fallback | | |

Ministral 3 3B is deprecated and retained only so older installs keep working. It is
excluded from the ladder.

Runtime is llama.cpp via the official prebuilt `llama.xcframework` b9821, which is gitignored
and fetched by CI. LFM2.5 was evaluated in June and rejected on license. MLX-Swift was never
started. LiteRT-LM was evaluated and deferred.

On-device is the default LLM provider in the app. It serves full tutoring turns, barge-in
responses (`BargeInResponder`), and speculative pre-generation (`ResponsePreGenerator`).
Canned TTS clips (`CannedResponseBank`) cover instant filler. The last substantive commit on
this path is `0d5d86e`, 2026-06-26, roughly seven weeks ago.

### Open items

1. **Device validation gap.** Gemma 4 E2B has never been validated on a real 12 GB device.
   The only evidence is a simulator smoke test, recorded in the `runsOnBundledRuntime` comment
   in `OnDeviceLLMModelManager.swift`. The unblock plan called for device validation before the
   enable flag was flipped on 2026-06-26. That step was skipped.
2. **Memory tension.** Gemma 4 sits at 2.5 to 2.9 GB resident. The barge-in goal
   (`unamentis-ios/.claude/goals/barge-in.json`) carries a 600 MB peak-memory criterion, advisory
   rather than gated, and the 90 minute session budget is a separate long-run check. Jetsam risk
   is real alongside Pocket TTS, Parakeet STT, and Silero VAD.
3. **Housekeeping, since fixed by work package C (merged 2026-08-14, PR #6).** SHA256
   verification of model downloads
   is missing (audit finding SEC-5). Dead Core ML endpoints `llama-3b-device` and
   `llama-1b-device` remain in `UnaMentis/Core/Routing/Models/LLMEndpoint.swift`.
   `unamentis-ios/docs/ios/PERSONAL_ASSISTANT_INTEGRATION_DISCOVERY_2026-06.md` still claims
   `OnDeviceLLMService` is marked incompatible and excluded in `project.yml`, which stopped
   being true on 2026-06-10.
4. **Stale sibling doc.** [AI_MODEL_SELECTION_2026.md](../AI_MODEL_SELECTION_2026.md)
   (2026-01-19) still recommends SmolLM3-3B and frames the on-device LLM as Knowledge Bowl
   answer validation only. It has misled at least one review. A currency note and inline
   supersession markers were added on 2026-08-12; see section 4.
5. **Studio cannot build this path.** On the Mac Studio the `models` symlink dangles and
   `llama.xcframework` is absent, so the on-device path needs CI-style placeholders to build.

## 2. FOV context

As-built reference: [docs/architecture/FOV_CONTEXT_MANAGEMENT.md](../architecture/FOV_CONTEXT_MANAGEMENT.md).
Built January 2026. Four-tier cognitive buffers (Immediate verbatim, Working full detail with
an `alternativeExplanations` slot, Episodic summarized past, Semantic full curriculum outline
plus position), per-model-tier token budgets down to 2K, and a confidence-driven expansion loop.

Two implementations exist: the Python server side in `server/management/fov_context/` (nine
HTTP routes, tests, dashboard panel) and roughly 3,200 lines of Swift in
`unamentis-ios/UnaMentis/Core/Context/`. Only test coverage has been added since January.

### Gaps relative to the foveated-context vision

1. **Curriculum only.** The reading and document path has only
   `ReadingFOVContextManager.swift`, which takes 3 raw chunks behind and 2 ahead with suffix
   truncation, no outline and no summaries. The February 2026 reading list feature was never
   integrated into the foveation model.
2. **No precomputation pass anywhere.** All summaries are lazy, computed at runtime, cached in
   memory with a 1 hour TTL, and lost on relaunch. `ReadingAudioPreGenerator` and its
   `audioPreGenStatusRaw` status field are the template to clone.
3. **Two resolution levels only.** Full text and one summary step. There is no
   distance-to-position granularity ramp and no level-k summaries.
4. **Forward context is nearly absent.** It amounts to three bare topic titles, and outline
   overflow is handled by amputating the tail (`BufferModels.swift`, `render(tokenBudget:)`),
   which is the exact failure foveation is supposed to prevent.
5. **Back-pocket material dropped client-side.** UMCF carries per-segment
   `alternativeExplanations` (simpler, technical, analogy, example-based), typed examples with
   spoken variants, and misconceptions with remediation. The server generates and stores them.
   iOS parses them in `UMCFParser.swift`, and then `CurriculumEngine.getAlternativeExplanations`
   and `getMisconceptionTriggers` both return empty arrays with a "for now" comment. Core Data
   has no entity for them. Since fixed by work package A (merged 2026-08-14, PR #5).
6. **Linear search, no embeddings.** Curriculum search is a linear loop with a hardcoded
   relevance score, and `searchRelatedTopics` is a stub. There are no embeddings anywhere in
   the context path.

### Open expert panel findings

From [docs/reviews/EXPERT_PANEL_REVIEW.md](../reviews/EXPERT_PANEL_REVIEW.md) (2026-03-29),
still open:

- **F10-3** (medium): token estimation is `text.count / 4`, inaccurate for non-English, code,
  and math, and the 60/30/10 FOV budget splits amplify the error.
- **F12-1** (high): the pedagogical metadata never reaches the system prompt. ContentDepth AI
  instructions, teachback configs, Bloom's levels, learner signals, and misconception triggers
  are modelled but not surfaced to the LLM.
- **F12-2** (high): no cross-session learner profile. `reset()` clears all buffers, so confusion
  areas, pace preferences, and misconception patterns vanish between sessions.

Findings 5 above and F12-1 overlap. Wiring the UMCF back-pocket material through
`CurriculumEngine` into the working buffer is the first half of F12-1.

## 3. August 2026 landscape refresh

A web scan on 2026-08-12 found four things that bear on the June decision.

- **LFM2.5-2.6B** shipped 2026-08-04 to 2026-08-06: 2.69B params, 131K context, under 2.5 GB,
  roughly 30 tok/s on phones per the vendor, strong instruction following and tool calling per
  byte, day-one GGUF and MLX. The license is unchanged (lfm1.0, free under 10M USD revenue).
  The June rejection doc says to revisit if the MIT-weights requirement is relaxed, so this is
  now a real decision rather than an automatic disqualification.
- **Qwen3.5 small series** shipped 2026-03-02 (0.8B, 2B, 4B, Apache 2.0, 262K context). The
  decided 8 GB tier model, Qwen3-1.7B, is a generation old. Qwen3.5-2B posted the best
  independent iPhone decode number found: 61 tok/s on MLX at 1.28 GB on iPhone 17 Pro
  (MLBoy / john-rocky benchmark, June 2026). It is close to a drop-in upgrade for the middle tier.
- **LiteRT-LM memory result.** The same independent benchmark runs Gemma 4 E2B on Google's
  LiteRT-LM (INT4 QAT) at 55 tok/s in 641 MB peak memory, against roughly 2.9 GB resident on
  llama.cpp or MLX. That speaks directly to open item 2 in section 1, and LiteRT-LM is the
  natural Android runtime as well. The June deferral is worth revisiting. The June doc's own
  caveat still applies: weight caching pages from flash, which risks TTFT spikes mid-utterance.
- **Apple Foundation Models (iOS 26)** are viable for the continuity job only. Zero download,
  excellent TTFT, streaming, guided generation, against a hard 4,096 token context, guardrail
  false-positive risk, and an iPhone 15 Pro floor. It needs an instant fallback path. iOS 27
  betas open the framework to any provider, including an MLXLanguageModel backend.
- **Top TTFT lever for grounded tasks:** KV-cache precomputation of the static prefix, meaning
  the system prompt plus the current curriculum section, computed when a section loads so that
  barge-in only has to prefill recent turns. Separately, mlx-lm 0.21 (May 2026) shipped
  speculative decoding on Apple Silicon.

**Recommended posture** carried from the research pass: keep Gemma 4 E2B as the quality anchor
and test LiteRT-LM as the memory fix, bump the middle tier to Qwen3.5-2B after device
validation, evaluate LFM2.5-2.6B as a possible single model for both jobs if the license
dependency is acceptable, and consider Apple Foundation Models as a free continuity engine on
capable devices. None of this is decided.

## 4. The 2026-08-12 work block

Four work packages ran on 2026-08-12. Delivery update, 2026-08-14: packages A, B, and C are
merged to `unamentis-ios` `main` with CI green, after each passed an eight-angle adversarial
review whose confirmed findings were fixed before merge:

- A: [unamentis-ios PR #5](https://github.com/UnaMentis/unamentis-ios/pull/5), merged
  2026-08-14. The review also fixed a misconception decode bug (legacy `trigger` key shadowing
  `triggerPhrases`) and a render-priority regression.
- C: [unamentis-ios PR #6](https://github.com/UnaMentis/unamentis-ios/pull/6), merged
  2026-08-14. The review expanded the package into a full download-path hardening: staging
  then commit-by-rename, pinned Hugging Face revisions, a verified-hash sidecar covering
  pre-existing installs, and continuation lifecycle fixes.
- B: [unamentis-ios PR #7](https://github.com/UnaMentis/unamentis-ios/pull/7), merged
  2026-08-14. The review fixed retry and cancellation lifecycle bugs, outline misalignment
  after failed sections, and the table-of-contents section-marker trap.
- D: this document, delivered through the same review-and-merge pipeline in this repo.

The original package descriptions follow as written on 2026-08-12.

| Package | Repo | Work |
|---|---|---|
| A | `unamentis-ios` | Wire `alternativeExplanations` and `misconceptionTriggers` from UMCF through `CurriculumEngine` into the FOV working buffer, with tests. Closes gap 5 in section 2. |
| B | `unamentis-ios` | Reader foveation phase 1: background summary and outline pre-generation cloned from the audio pre-gen pattern and persisted, `ReadingFOVContextManager` assembling outline plus summary bands plus a raw near window, and a fix for suffix truncation. Addresses gaps 1, 2, and 3. |
| C | `unamentis-ios` | SHA256 verification for model downloads (SEC-5), removal of the dead Core ML endpoints, and correction of the stale `OnDeviceLLMService` claim in the personal-assistant discovery doc. Closes open item 3 in section 1. |
| D | `unamentis` | This document, plus the supersession pointer and inline markers on [AI_MODEL_SELECTION_2026.md](../AI_MODEL_SELECTION_2026.md). |

**Validation constraint.** The Mac Studio has Xcode 26.6 and the iOS 26.5 SDK but no simulator
runtimes, so tests cannot run locally. The local ceiling was SwiftLint plus type-checking under
Swift 6 strict concurrency, with a `DEVELOPER_DIR` override and CI-style placeholder models
(deeper still than first assessed: the iOS platform itself is not installed, so even
`build-for-testing` cannot run). CI was the build and test gate for packages A, B, and C, and
it went green for each before merge.
