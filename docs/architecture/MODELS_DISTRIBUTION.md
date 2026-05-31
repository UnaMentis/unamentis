# Model Distribution Strategy (unamentis-models)

**Status:** Decision record. Last updated 2026-05-30.
**Decision:** `unamentis-models` is a **manifest / download** repository. It distributes **no model weights**. It fetches them from their upstream sources (for example Hugging Face) at pinned revisions during setup, under each model's own license.

## Context

On-device and self-hosted inference uses several third-party model artifacts (LLMs, ASR, TTS, VAD). Today these live in a local, untracked `~/dev/unamentis-models` folder (roughly 6 GB) that client repos reference via a symlink. As the UnaMentis ecosystem goes public, we need a reproducible, legally sound way to obtain these models without turning the project into an unauthorized redistributor.

## The licensing problem with redistributing weights

Bundling or hosting the weights in a public repo (for example via Git-LFS) is an active, public, timestamped act of redistribution. Several of the models we use do not permit that cleanly:

| Model | Upstream license | Redistribution status |
|-------|------------------|------------------------|
| Llama 3.2 3B | Llama 3.2 Community License (not OSI open source) | Conditional. Requires shipping the license, prominent "Built with Llama" notice, and the specific attribution notice in a Notice file; the Acceptable Use Policy binds downstream; a separate Meta license is required above 700M monthly active users. A quantized GGUF is a derivative and is covered. |
| Ministral 3B | Mistral Research License | **Non-commercial / research only.** Incompatible on its face with redistribution as part of a product that has any commercial path. Must be excluded from any public or commercial build. |
| TinyLlama 1.1B | Apache 2.0 | Freely redistributable. |
| GLM-ASR Nano | MIT | Freely redistributable. |
| Kyutai Pocket TTS / Mimi | Unresolved at time of writing | Treat as "no redistribution rights until verified." The iOS app bundles `PocketTTS.xcframework`, so this must be confirmed before that repo flips public. |
| Silero VAD | MIT | Freely redistributable. |

Redistributing Llama or Ministral weights publicly, especially as the basis of a product with a future commercial tier, creates direct and documentable infringement risk. That risk is avoidable.

## Why manifest/download (not Git-LFS, not private-forever)

- **Git-LFS public weights repo (rejected):** converts every restricted-license concern above into active public redistribution. Worst posture for Llama's notice requirements and a clear breach for Ministral. Also carries multi-GB bandwidth and storage cost.
- **Private/local forever (rejected):** does not serve the self-sufficient public ecosystem goal; contributors and CI need a reproducible way to obtain models.
- **Manifest/download (chosen):** keeps the convenience of the shared folder while removing redistribution liability. Each user downloads from upstream under that model's own license. UnaMentis distributes only metadata and scripts.

## Repository shape (when created)

`unamentis-models` becomes a small git repository containing:

- `manifest.json` (or `models.lock`): per-model entries `{ name, upstream repo id, pinned revision/commit, sha256, target path, license id, redistribution: false }`.
- `scripts/download-models.(sh|py)`: fetches from upstream at the pinned revision into the local folder and verifies sha256. This replaces today's manual folder population.
- `LICENSES/`: documents each model's upstream license **by reference** (link plus summary), and states explicitly that UnaMentis does not redistribute Llama or Mistral weights.
- `README.md`: states clearly that the repo distributes no model weights, that it fetches them from upstream under each model's own license, and that Ministral is research/non-commercial and excluded from commercial builds.
- `.gitignore`: ignores `*.gguf`, `*.safetensors`, `*.mlpackage`, and the download target folders, so weights are never committed accidentally.

The existing symlink contract (`unamentis-ios/models -> ~/dev/unamentis-models`) stays intact; the manifest just populates that folder.

## Commercial-build rule

Commercial or broadly public builds may include only Apache/MIT models (for example TinyLlama, GLM-ASR, Silero). Llama may be used only under a direct Meta agreement that satisfies the Community License and the 700M-MAU clause. **Ministral must never appear in a public or commercial build path** (research/eval only).

## Action items

- [ ] Confirm the Kyutai Pocket TTS license terms before the iOS app (which bundles `PocketTTS.xcframework`) flips public.
- [ ] Stand up `unamentis-models` as a manifest/download repo per the shape above (separate effort, outside the `unamentis` server repo).
- [ ] Ensure NOTICE files in client repos that bundle weights carry the required Llama attribution and "Built with Llama" notice where applicable.

> Scope note: this document is the decision record only. Creating the `unamentis-models` repo and the per-client NOTICE files is separate work outside the `unamentis` server repo, which is the source of truth for this decision.
