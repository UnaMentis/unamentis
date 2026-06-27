# LLM Aggregator and Intelligent Routing: Feasibility and Strategy

**Date:** 2026-06-25
**Status:** Research / proposal
**Author:** AI investigation (Claude Code)
**Scope:** Whether UnaMentis should integrate an LLM aggregator (OpenRouter or similar) and build deliberate, cost- and quality-aware model routing on top of it.

---

## 1. Executive Summary

Today UnaMentis asks each cloud-LLM user to bring their own per-provider API keys (OpenAI, Anthropic, Google) and pick a default model by hand. That works, but it is friction-heavy and it leaves all the cost, quality, and reliability decisions to the user. As token economics become a larger concern, a single point of integration that gives access to many providers and many models, and lets the platform route between them deliberately, is genuinely attractive.

**Recommendation in one line:** Build a thin **routing abstraction layer** inside the existing `LLMService` protocol, add an **OpenRouter-backed provider** as the first aggregator implementation, and keep direct providers and on-device as first-class peers. Treat the aggregator as one option in a portfolio, not a replacement for the architecture we already have. Do this in phases, and be honest about where automatic routing helps and where it does not.

**Why this is feasible:** Our LLM layer is already an actor-based protocol (`LLMService`) with a working multi-tier fallback wrapper (`FallbackLLMService`) and per-provider cost tracking. An aggregator is "just another provider" that happens to expose hundreds of models behind one key. The integration surface is small and additive. No server changes are required for the minimal version.

**The honest caveats:**
- Independent 2026 benchmarks (RouterArena, LLMRouterBench) find that automatic routers frequently **do not** beat a well-chosen single model on the cost/quality frontier. Routing is real, but the marketing numbers ("40 to 70% savings, under 2% quality loss") are best-case and workload-specific.
- An aggregator adds a **network hop and a third party** to the most latency-sensitive path in the product. For a voice platform targeting sub-500ms end-to-end turn latency, that is a real cost that must be measured, not assumed away.
- It introduces a **new trust boundary** for user prompts, which matters a great deal given our privacy-aware positioning and a likely population of minors.

---

## 2. The Problem Today

From the codebase investigation:

- **Five LLM providers** are implemented client-side as independent services: OpenAI, Anthropic, Google, Self-Hosted (Ollama), and On-Device (Ministral-3B via llama.cpp). All conform to the `LLMService` actor protocol in `unamentis-ios/UnaMentis/Services/Protocols/LLMService.swift`.
- **API keys** are entered per provider in Settings and stored in the iOS Keychain via `APIKeyManager` (`Core/Config/APIKeyManager.swift`). One key per vendor.
- **Model and settings** (provider, model, temperature, max tokens) are chosen manually in `VoiceSettingsView.swift`.
- **Provider selection** happens at session start in `SessionView.swift` with a hand-written fallback ladder (on-device, then Anthropic, then OpenAI, then Google, then self-hosted).
- **Cost tracking** already exists: each service exposes `costPerInputToken` / `costPerOutputToken`, and `SessionManager` records LLM input/output cost to telemetry. Server stores `llm_cost` in `telemetry_store.py`.
- **No aggregator or generic router exists today.** The fallback ladder is hardcoded, not policy-driven.

The user-facing pain points this creates:
1. **Onboarding friction.** A user who wants cloud inference must create one or more vendor accounts, generate keys, and paste each one. That is a hard ask for a learning-platform audience.
2. **No portfolio management.** A user is locked to whatever single model they picked. There is no per-request "use the cheap model for easy turns, the strong model for hard ones."
3. **No cross-vendor resilience by default.** If a provider degrades, the user feels it unless they happened to configure the fallback ladder.
4. **Cost is opaque and unmanaged.** We track cost after the fact, but we do not act on it.

---

## 3. What an Aggregator Actually Gives You

An LLM aggregator (gateway) is a single API endpoint, usually OpenAI-compatible, that fronts many providers and many models behind one key. The reference product is **OpenRouter**.

### OpenRouter mechanics (as of mid-2026)
- **Catalog:** 400+ models from 60+ underlying providers through one API key. Drop-in OpenAI-compatible base URL.
- **Pricing model:** Passthrough of each underlying provider's per-token rate. OpenRouter's own fee is **~5.5% on credit purchases** (when a user funds their own OpenRouter balance), not a per-token markup. There are also free-tier models with tight rate limits.
- **BYOK:** You can attach your own provider keys to OpenRouter and route through it while billing the provider directly. First **10,000 BYOK requests/month are free**, then a **~5% fee** of the equivalent model cost. This matters: it means a user can use OpenRouter's routing and observability while still paying providers directly.
- **Privacy / data policy:** OpenRouter advertises **zero data retention by default**, "we do zero logging of your prompts/completions unless you opt in." Providers that log or whose policy is unconfirmed are excluded unless the user enables a training/logging toggle. There is an opt-in logging mode that trades a small discount for prompt retention.
- **Routing controls already built in:**
  - `:nitro` variant (prioritize throughput/latency), `:floor` variant (prioritize lowest price), `:exacto` (optimize tool-calling reliability).
  - **Automatic provider failover**: if one upstream errors, it transparently retries the next.
  - **Load balancing** across top providers for a given model to pool uptime.
  - **Auto Router** (`openrouter/auto`), powered by NotDiamond, picks a model per prompt from a curated pool.

### Why this maps cleanly onto our stack
- One `OpenRouterLLMService` conforming to `LLMService` exposes hundreds of models without writing a client per vendor.
- The user enters their own OpenRouter key in Settings exactly like the existing per-vendor keys, so it stays a user-controlled, bring-your-own-key provider.
- The built-in failover and load balancing overlap with what `FallbackLLMService` does today, so we can choose how much resilience to delegate vs. keep in-app.

---

## 4. The Landscape (Not Just OpenRouter)

| Platform | Shape | Strength | Best fit for us |
|---|---|---|---|
| **OpenRouter** | Hosted gateway, 400+ models, one key | Largest catalog, simplest BYOK, ZDR default, provisioning keys, drop-in OpenAI API | First aggregator to integrate; lowest effort, broadest reach |
| **Portkey** | Hosted + open-source (Apache-2.0 since 3/2026) gateway | 1,600+ models, 40+ guardrails, semantic caching, conditional routing, observability | If we want guardrails + caching as a platform layer, or to self-host the gateway |
| **LiteLLM** | Self-hosted proxy / library | Full control, policy-as-code, runs in our infra, no third-party in the path | If/when we run the minimal AWS server and want routing under our own roof |
| **Requesty** | Lightweight hosted router | Simplest setup | Fast experiment alternative to OpenRouter |
| **Cloudflare AI Gateway / Vercel AI Gateway** | Edge gateways | Caching, analytics, rate limiting at the edge | Relevant since we already use Cloudflare; good for a server-side proxy |
| **Azure AI Foundry Model Router** | Hosted trained router | Balanced/Cost/Quality modes across 27+ models | Reference design for routing modes, not a fit for our BYO-key audience |

Two architectural families matter here:
1. **Hosted aggregator (OpenRouter, Requesty, Portkey-cloud):** fastest to ship, adds a third party to the path and to the trust boundary.
2. **Self-hosted gateway (LiteLLM, Portkey-OSS, Cloudflare/Vercel in our own account):** keeps prompts inside infrastructure we control, but only helps once we actually run a server in the LLM path (today the iOS client calls providers directly).

These are not mutually exclusive. The right long-term design is an **abstraction that can sit in front of any of them, plus direct providers, plus on-device.**

---

## 5. Intelligent Routing: The Vision vs. the Evidence

The exciting part of the idea is deliberate, dynamic routing: go between vendors, and between models within a vendor, guided by user preferences and live cost/capability signals, adjusting on the fly.

**This is real and partly available off the shelf:**
- Rule-based routing adds <1ms; embedding-based ~5ms; semantic/ML classifiers 50 to 100ms; a trained domain classifier (e.g. Morph) ~430ms.
- Vendors publish live price and capability metadata we can pull and act on (OpenRouter exposes per-model pricing and provider stats; rankings and uptime are queryable).
- Azure's Model Router demonstrates the productized version: Balanced (cheapest model within 1 to 2% of best quality), Cost (widen the band, favor cheapest), Quality (always best).

**But the independent evidence is sobering and we should internalize it:**
- 2026 benchmarks (RouterArena, LLMRouterBench) find that many routers, **including commercial ones, do not reliably beat the best single model** on the cost/quality frontier. One evaluation ranked NotDiamond (which powers OpenRouter's Auto Router) poorly because it often picks expensive models.
- The headline "40 to 70% cost savings at under 2% quality loss" is achievable on **specific workloads with a well-tuned router**, not a guarantee. It depends heavily on having a workload where many turns are genuinely easy.

**What this means for UnaMentis specifically:** Our workload is unusually favorable for routing for one reason. A voice learning platform has a **wide spread of turn difficulty**. "Yes, that is correct, try the next one" is trivial. "Explain why this proof step is valid and generate a Socratic follow-up" is hard. That spread is exactly where cheap-model-for-easy-turns routing pays off. So routing is more promising for us than the average chat app, **but** the latency dimension (Section 6) constrains how aggressive we can be on the real-time path.

The pragmatic conclusion: **start with simple, explainable rule-based routing keyed on signals we already have** (task type, expected response length, context size, on-device eligibility), measure it against a fixed strong baseline, and only graduate to ML/semantic routing if the data justifies it. Do not lead with a black-box auto-router and assume savings.

---

## 6. Latency: The Constraint That Outranks Cost

UnaMentis targets <500ms median and <1000ms P99 end-to-end turn latency. The LLM is one stage in a STT to LLM to TTS pipeline, and time-to-first-token drives perceived responsiveness.

An aggregator inserts:
1. An extra **network hop** (client to gateway to provider) on a latency-critical path.
2. Possible **provider-selection overhead**, especially with auto-routing or cold provider fallback.

2026 router latency benchmarks show measurable added overhead versus calling a provider directly. For a real-time voice turn, that is not free.

**Design implications:**
- Use latency-pinned variants (OpenRouter `:nitro`, or pin a specific fast provider) on the **real-time speech path**.
- Reserve heavier, smarter routing (auto-router, semantic classifiers, cheaper-but-slower models) for **non-realtime work**: lesson generation, summarization, content prep, evaluation, grading, background curriculum tasks.
- Keep **on-device first** for the lowest-latency simple turns. The aggregator is for when we have already decided to go to the cloud.
- This argues against putting a hosted aggregator on the critical path **as the only option**. Keep direct-provider and on-device routes available, selected by policy.

---

## 7. Feasibility in Our Architecture

### Minimal integration (client-side, no server changes)
1. Add `OpenRouterLLMService` in `unamentis-ios/UnaMentis/Services/LLM/` conforming to `LLMService`. OpenRouter is OpenAI-compatible, so it is close to the existing OpenAI client with a different base URL, auth header, and model namespace.
2. Add an `openRouter` key type to `APIKeyManager.KeyType`.
3. Add OpenRouter (and a model picker that can list its catalog) to `VoiceSettingsView`.
4. Add instantiation to the selection logic in `SessionView`.
5. Cost tracking flows through automatically via the protocol's cost properties (populated from OpenRouter's per-model pricing metadata).

Effort: small. This is a few days of focused client work plus testing. It immediately collapses "three vendor keys" into "one key, hundreds of models."

### The routing layer (the actual value)
Introduce a `RoutingLLMService` (also conforming to `LLMService`) that wraps one or more underlying services and a **policy**:

```
RoutingLLMService
  inputs:  task descriptor (type, expected length, context size, realtime?),
           user preferences (cost ceiling, quality floor, privacy mode),
           live signals (model price/availability, recent latency, on-device eligibility)
  output:  a concrete (provider, model) choice + fallback chain
```

This generalizes the hardcoded ladder in `SessionView` into a declarative policy, and `FallbackLLMService` becomes the execution engine underneath it. The router can target OpenRouter models, direct-provider services, or on-device, uniformly.

### Optional server-side proxy (later)
If/when the minimal AWS server is in the LLM path, a self-hosted gateway (LiteLLM or Cloudflare AI Gateway in our own account) lets us:
- Keep prompts inside infrastructure we control (better privacy story than a third-party hosted gateway).
- Centralize routing policy, caching, and observability.

Trade-off: it puts our server on the latency path, which today it is not.

---

## 8. Pros and Cons by Dimension

### Cost
- **Pro:** The user's single OpenRouter key replaces N vendor keys. With BYOK the user keeps paying providers directly (first 10k BYOK requests/month free, then a ~5% fee), so there is no token markup in the path. Routing cheap-for-easy can genuinely cut the user's spend on our high-variance workload.
- **Con:** The aggregator fee is a real, if small, tax. Auto-routing can *increase* cost if it favors expensive models (documented with NotDiamond). Savings are not guaranteed and must be measured.

### User experience
- **Pro:** Dramatically simpler onboarding (one OpenRouter key replaces several vendor keys). Access to far more models without app updates. Better reliability via failover.
- **Con:** A model picker over 400+ models is its own UX problem; we would need sensible curated presets, not a raw list.

### Quality
- **Pro:** Ability to send hard turns to frontier models and easy turns to small ones can *raise* perceived quality per dollar. Access to new models the day they launch.
- **Con:** Routing can pick a worse model for a given turn. Quality routing needs evaluation harness support to trust. The latency harness (`server/latency_harness/`) is the natural place to add quality/cost regression checks per routing policy.

### Reliability
- **Pro:** Built-in cross-provider failover and uptime pooling. Reduces single-vendor outage exposure.
- **Con:** Introduces a **new single point of failure**: the aggregator itself. If OpenRouter is down, every cloud route through it is down. Mitigation: keep direct-provider and on-device routes as escape hatches in the policy.

### Privacy (high stakes for us)
- **Pro:** OpenRouter defaults to zero retention and excludes logging providers unless the user opts in. That is a defensible baseline.
- **Con:** It is still a **new third party that sees user prompts**. For a learning platform likely serving minors, that is a meaningful expansion of the trust boundary and a compliance surface (COPPA/FERPA-style concerns, data-processing agreements, regional data residency). On-device and direct-provider routes have a *shorter* trust chain. A self-hosted gateway keeps prompts in our infrastructure. This dimension may argue for making the aggregator **opt-in and clearly disclosed**, never a silent default, and for preferring a self-hosted gateway if a server-side gateway is ever introduced.

### Operational / strategic
- **Pro:** Less per-vendor client code to maintain; one integration tracks the whole market.
- **Con:** Concentration risk and dependency on a third party's pricing, policy, and survival. Vendor lock-in shifts from "many providers" to "one aggregator." Mitigation is the abstraction layer: the aggregator must be replaceable.

---

## 9. Deployment Models

These are not exclusive; a mature design supports both. A platform-managed or hosted-billing model is intentionally out of scope: this is an OSS, user-controlled tool, the user owns their provider account and their bill.

### Model A: Bring-Your-Own-Aggregator-Key
User pastes a single OpenRouter (or chosen gateway) key. The app does deliberate routing on their behalf. Replaces three vendor keys with one.
- **Pros:** Minimal effort, no billing/legal exposure for us, user owns the relationship and the bill, OSS-friendly. Strictly better than today's multi-key flow.
- **Cons:** User still has to create and fund an aggregator account. We do not control the privacy posture.
- **Verdict:** Ship this first. It is a clear, low-risk win and it is fully consistent with an OSS, user-controlled tool.

### Model C: Unified Routing Abstraction (the durable architecture)
A `RoutingLLMService` policy layer that treats on-device, direct providers, self-hosted, and one-or-more aggregators as interchangeable backends, selected per request by policy.
- **Pros:** No lock-in, aggregator is replaceable, on-device-first preserved, supports A and B underneath, future-proof.
- **Cons:** Most design effort. Needs a policy format and an evaluation harness.
- **Verdict:** This is the real target. Build it incrementally; Model A rides on top of it as the first backend.

---

## 10. A Routing Strategy Tuned for a Voice Learning Platform

Concrete starting policy, using only signals we already have:

1. **On-device first** for simple, latency-critical turns when the device is eligible and models are loaded. (Already partly true; formalize it.)
2. **Realtime cloud path:** when going to cloud mid-conversation, prefer latency-pinned routes (direct provider or `:nitro`-style variant) on a strong-but-fast model. Do not auto-route here.
3. **Difficulty-aware tiering:** classify the turn cheaply (task type from the lesson context, expected response length, whether tool/structured output is needed). Easy turns to a small cheap model, hard/Socratic turns to a frontier model. Start rule-based.
4. **Non-realtime work** (lesson/content generation, grading, summarization, embeddings): aggressive cost routing is fine here, including auto-router and cheaper-slower models, because latency is not user-facing.
5. **User preference dial:** expose a simple preset (Cost / Balanced / Quality / Privacy), mapping to policy parameters. "Privacy" forces on-device or direct-provider only and disables the third-party aggregator.
6. **Live signal feedback:** periodically pull model price/availability/latency stats and feed them into the policy. Keep a per-policy cost/quality scorecard via the latency harness so routing changes are measured, not vibes.
7. **Fallback always:** every policy choice produces a fallback chain executed by `FallbackLLMService`, ending in on-device so a fully degraded network still works.

---

## 11. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Aggregator becomes a single point of failure | High | Keep direct + on-device routes in every policy; never aggregator-only |
| Added latency on the realtime path | High | Pin fast routes for realtime; aggregator for non-realtime; measure with the harness |
| Routing does not actually save money / hurts quality | Medium | Start rule-based; A/B against a fixed strong baseline; gate ML routing on evidence |
| New privacy/compliance trust boundary (minors) | High | Make aggregator opt-in and disclosed; offer Privacy preset; prefer a self-hosted gateway if a server is ever in the path |
| Vendor lock-in shifts to the aggregator | Medium | Model C abstraction keeps the aggregator replaceable |
| Aggregator pricing/policy changes | Medium | BYOK option keeps provider billing direct; abstraction allows switching gateways |
| Over-complex model picker UX | Low | Curated presets, not a raw 400-model list |

---

## 12. Proposals

**Proposal 1 (do now, low risk): Ship Model A on top of a minimal Model C.**
Add `OpenRouterLLMService` and a first-cut `RoutingLLMService` that generalizes the current `SessionView` ladder into a declarative policy. Net user benefit: one key replaces three, plus built-in failover. No server changes. Frame it as user-controlled and opt-in.

**Proposal 2 (next): Difficulty-aware, latency-respecting routing.**
Implement the Section 10 policy with rule-based classification and the Cost/Balanced/Quality/Privacy preset. Wire per-policy cost/quality/latency measurement into `server/latency_harness/` so we can prove the policy beats a fixed baseline before defaulting anyone into it.

**Proposal 3 (evaluate, do not assume): Auto/ML routing for non-realtime work only.**
Try OpenRouter Auto Router or a self-hosted classifier on background tasks (content generation, grading). Keep it off the realtime path until measured.

**Sequencing:** Proposal 1, then 2, then 3.

---

## 13. Open Questions

1. What is the measured added latency of OpenRouter vs. direct providers on our actual realtime turn? (Run it through the harness before committing the realtime path.)
2. Do we want the aggregator opt-in or as a recommended default for cloud users? (Privacy/positioning question.)
3. How do we present model choice without overwhelming users? (Preset design.)
4. If a server-side gateway is ever introduced (Section 7), what is the privacy and compliance posture, especially for minors?
5. Does routing actually beat a fixed strong baseline on our workload, measured, before we default anyone into it?

---

## Sources

- OpenRouter docs: [Provider Routing](https://openrouter.ai/docs/guides/routing/provider-selection), [Models](https://openrouter.ai/docs/guides/overview/models), [FAQ](https://openrouter.ai/docs/faq), [Auto Router](https://openrouter.ai/docs/guides/routing/routers/auto-router), [BYOK](https://openrouter.ai/docs/use-cases/byok), [Provisioning API Keys](https://openrouter.ai/docs/features/provisioning-api-keys), [Organization Management](https://openrouter.ai/docs/cookbook/administration/organization-management)
- [OpenRouter pricing overview (costbench)](https://costbench.com/software/llm-api-providers/openrouter/), [OpenRouter pricing (costgoat)](https://costgoat.com/pricing/openrouter)
- [OpenRouter: Building a Multi-Model LLM Marketplace (ZenML)](https://www.zenml.io/llmops-database/building-a-multi-model-llm-marketplace-and-routing-platform)
- Alternatives and gateway comparisons: [Pinggy](https://pinggy.io/blog/best_ai_llm_routers_openrouter_alternatives/), [TrueFoundry LiteLLM vs OpenRouter](https://www.truefoundry.com/blog/litellm-vs-openrouter), [Portkey alternatives](https://portkey.ai/alternatives/openrouter-alternatives), [Eden AI](https://www.edenai.co/post/best-alternatives-to-openrouter), [TrueFoundry alternatives](https://www.truefoundry.com/blog/openrouter-alternatives)
- Routing concepts and economics: [DigitalApplied routing guide](https://www.digitalapplied.com/blog/llm-model-routing-2026-cost-quality-optimization-engineering-guide), [Morph LLM Router](https://www.morphllm.com/llm-router), [TrueFoundry cost/quality routing](https://www.truefoundry.com/blog/llm-routing-cost-quality-aware-model-selection), [Braintrust best routers 2026](https://www.braintrust.dev/articles/best-llm-routers-2026)
- Independent router benchmarks (skeptical evidence): [RouterArena (arXiv)](https://arxiv.org/html/2510.00202v1), [LLMRouterBench (arXiv)](https://arxiv.org/html/2601.07206v1), [OpenRouter model routing explainer](https://openrouter.ai/blog/insights/model-routing/), [LLM router latency benchmark (Opper)](https://opper.ai/blog/llm-router-latency-benchmark-2026)
- [Not-Diamond awesome-ai-model-routing](https://github.com/Not-Diamond/awesome-ai-model-routing)
