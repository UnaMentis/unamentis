# AI Model Selection for UnaMentis (2026)

**Last Updated:** January 19, 2026
**Research Date:** January 19, 2026
**Status:** Active recommendations based on latest available models

> ## ⚠️ Currency note (added 2026-08-12)
>
> **The on-device LLM sections of this document are superseded as of 2026-06-26.** Section 1
> below, its entry in "Implementation Priorities", and its row in the Quick Reference appendix
> recommend SmolLM3-3B and frame the on-device LLM as Knowledge Bowl answer validation only.
> Both claims are wrong now. Do not plan from them.
>
> The current on-device model decision is
> `docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md`, which lives in the **iOS repo**
> (`unamentis-ios`), not this one:
> [unamentis-ios/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md](https://github.com/UnaMentis/unamentis-ios/blob/main/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md).
> It decides a RAM-tiered ladder (Gemma 4 E2B at 12 GB, Qwen3-1.7B at 8 GB, Qwen3-0.6B at 6 GB,
> server fallback below that), and the on-device LLM is the app's default provider for full
> tutoring turns, not a validation-only component.
>
> Current overall status, including the August 2026 landscape refresh, is in
> [docs/status/2026-08-12-on-device-llm-and-fov-context-stocktake.md](status/2026-08-12-on-device-llm-and-fov-context-stocktake.md).
>
> Everything else in this document, including the server LLM, server TTS, and on-device TTS
> sections, has not been reviewed as part of this note and stands as written.

## Executive Summary

This document provides comprehensive research and recommendations for AI model selection across all UnaMentis use cases. The AI landscape evolved significantly throughout 2025, with new state-of-the-art models that substantially outperform our current choices.

**Critical Finding:** Our current on-device LLM choice (Llama 3.2 1B, released September 2024) is outdated and has been surpassed by models released in late 2025 that offer superior performance at similar or smaller sizes.

## Research Methodology

- **Date:** January 19, 2026
- **Sources:** Academic papers, official model releases, benchmark leaderboards, community evaluations
- **Criteria:** Release date (prioritizing 2025-2026), performance benchmarks, size constraints, licensing, deployment feasibility
- **Focus:** Latest models only - excluding anything released before Q4 2024 unless no better alternative exists

---

## 1. On-Device LLM (Knowledge Bowl Answer Validation)

> **SUPERSEDED 2026-06-26** by [unamentis-ios/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md](https://github.com/UnaMentis/unamentis-ios/blob/main/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md) (iOS repo). This whole section, including its use case framing, is historical.

### Use Case Requirements

- **Purpose:** Semantic answer validation for Knowledge Bowl questions
- **Target Accuracy:** 95-98% on validation tasks
- **Size Constraint:** 1-2GB quantized (4-bit)
- **Latency Target:** <250ms per validation
- **Device Requirements:** iPhone 12+ (A14+), Android 10+ with 4GB+ RAM
- **Availability:** Server administrator feature flags (open source)

### Current Implementation

**Model:** Llama 3.2 1B
**Release Date:** September 2024
**Status:** ⚠️ **OUTDATED** - Multiple superior alternatives available
**Size:** ~650MB (Q4)
**Performance:** Baseline, surpassed by newer models

### Recommended Replacements

#### 1. SmolLM3-3B ⭐ **RECOMMENDED**

**Release Date:** December 2025
**Parameters:** 3 billion
**Size:** ~1.5GB (Q4 quantized)
**License:** Apache 2.0
**Developer:** Hugging Face

**Performance:**
- Outperforms Llama 3.2 3B and Qwen2.5 3B across benchmarks
- Competitive with 4B-class models
- First or second place on knowledge benchmarks (HellaSwag, ARC, BoolQ)
- Strong math and coding performance within 3B class
- Optional reasoning mode: 36.7% on AIME 2025 (vs 9.3% base)

**Benchmarks:**
- MMLU: ~65%
- IFEval: Superior instruction following vs peers
- HellaSwag: 1st/2nd place in 3B class
- ARC: 1st/2nd place in 3B class

**Deployment:**
- Compatible with llama.cpp (GGUF format)
- Runs on iPhone 12+ (A14+), Android 10+ with 4GB RAM
- Efficient inference on mobile CPUs

**Why This Model:**
- Latest release (Dec 2025) - most current technology
- Best performance in the 3B parameter class
- Fully open source from trusted source (Hugging Face)
- Optimal size for mobile deployment
- Strong performance on knowledge and reasoning tasks (ideal for Knowledge Bowl)

**Sources:**
- [SmolLM3 Official Blog](https://huggingface.co/blog/smollm3)
- [BentoML: Best Open-Source Small Language Models (SLMs) in 2026](https://www.bentoml.com/blog/the-best-open-source-small-language-models)

#### 2. Qwen3-1.7B **ALTERNATIVE**

**Release Date:** May 2025
**Parameters:** 1.7 billion
**Size:** ~900MB (Q4 quantized)
**License:** Apache 2.0
**Developer:** Alibaba Cloud (Qwen Team)

**Performance:**
- Performs as well as Qwen2.5-3B-Base despite being smaller
- Significant density improvements over previous generation
- Latest Qwen generation with strong instruction following

**Why Consider:**
- Smaller size (900MB vs 1.5GB) if storage is critical
- Official Alibaba release with strong backing
- Excellent multilingual support
- Proven Qwen architecture lineage

**When to Choose:**
- Storage constraints are primary concern
- Need multilingual capabilities
- Prefer smaller model with good performance over larger model with excellent performance

**Sources:**
- [Qwen3 Technical Report](https://arxiv.org/pdf/2505.09388)
- [Best Qwen Models in 2026](https://apidog.com/blog/best-qwen-models/)

#### 3. Gemma 3n-E2B-IT **MULTIMODAL OPTION**

**Release Date:** Late 2025
**Parameters:** ~5B (selective activation reduces effective size to ~2B)
**Size:** ~1.2GB effective memory footprint
**License:** Gemma License
**Developer:** Google DeepMind

**Performance:**
- Multimodal capabilities (text + images)
- Instruction-tuned for on-device deployment
- Selective parameter activation for efficiency

**Why Consider:**
- Future-proofing for multimodal questions (images in Knowledge Bowl)
- Official Google optimization for mobile
- Innovative architecture

**Trade-offs:**
- Less established track record than SmolLM3
- More complex architecture
- Gemma license vs fully open Apache 2.0

**Sources:**
- [BentoML: Best Open-Source Small Language Models (SLMs) in 2026](https://www.bentoml.com/blog/the-best-open-source-small-language-models)

### Recommendation Summary

**Primary Choice:** SmolLM3-3B
- Best performance in class
- Latest release (Dec 2025)
- Optimal balance of size and capability
- Strong knowledge and reasoning (critical for Knowledge Bowl)

**Alternative:** Qwen3-1.7B if size constraints are critical

**Migration Priority:** HIGH - Llama 3.2 1B is over a year old and significantly outperformed

---

## 2. Server LLM (AI Tutoring & Instruction Following)

### Use Case Requirements

- **Purpose:** Interactive AI tutoring across all subjects
- **Target Performance:** Elite instruction following, reasoning, domain knowledge
- **Size Constraint:** None (server deployment)
- **Latency Target:** <2s for typical responses
- **Deployment:** GPU servers (A100/H100 class)

### Recommended Models

#### 1. Qwen3-235B-A22B-Instruct ⭐ **PRIMARY RECOMMENDATION**

**Release Date:** May 2025
**Parameters:** 235B total, 22B active (Mixture-of-Experts)
**Size:** ~120GB
**License:** Apache 2.0
**Developer:** Alibaba Cloud (Qwen Team)

**Performance:**
- Exceptional instruction following
- State-of-the-art reasoning capabilities
- Elite-level math, science, and coding
- Strong tool use capabilities
- Comprehensive multilingual support

**Why This Model:**
- Latest generation (May 2025) with most current capabilities
- MoE architecture provides efficiency (only 22B active parameters)
- Proven track record - Qwen series widely deployed
- Apache 2.0 license (fully open)
- Comprehensive documentation and community support

**Deployment:**
- Requires GPU server (A100 or H100 recommended)
- ~120GB model storage
- Efficient inference with MoE activation

**Sources:**
- [Qwen3 Technical Report](https://arxiv.org/pdf/2505.09388)
- [Qwen 3: The new open standard](https://www.interconnects.ai/p/qwen-3-the-new-open-standard)
- [Best Qwen Models in 2026](https://apidog.com/blog/best-qwen-models/)

#### 2. GLM-4.7 **BEST FOR CODE**

**Release Date:** Late 2025
**Parameters:** ~70B
**Size:** ~50GB
**License:** Apache 2.0
**Developer:** Zhipu AI (Tsinghua University)

**Performance:**
- **91.2% on SWE-bench** (best score among open models)
- Interleaved thinking architecture
- Preserves reasoning cache for complex repositories
- Thinks before responses and tool calls

**Why Consider:**
- If code/programming tutoring is primary focus
- Superior repository understanding
- Innovative architecture for reasoning

**Trade-offs:**
- Smaller than Qwen3 (less general capability breadth)
- Newer/less proven in production

**Sources:**
- [BentoML: Best Open-Source LLMs in 2026](https://www.bentoml.com/blog/navigating-the-world-of-open-source-large-language-models)
- [Top 10 Open Source LLMs 2026: DeepSeek Revolution Guide](https://o-mega.ai/articles/top-10-open-source-llms-the-deepseek-revolution-2026)

#### 3. DeepSeek-V3.2 **BEST FOR GENERAL KNOWLEDGE**

**Release Date:** Late 2025
**Parameters:** ~671B total (MoE)
**Size:** ~140GB
**License:** MIT
**Developer:** DeepSeek AI

**Performance:**
- **94.2% on MMLU** (ties with proprietary models like GPT-4)
- Most reliable for general knowledge and education
- Exceptional breadth across domains

**Why Consider:**
- If general knowledge is paramount
- MIT license (most permissive)
- Matches proprietary model performance

**Trade-offs:**
- Largest model (140GB vs 120GB for Qwen3)
- Higher compute requirements

**Sources:**
- [State of LLMs 2025: Progress and Predictions](https://magazine.sebastianraschka.com/p/state-of-llms-2025)
- [Top 10 Open Source LLMs 2026](https://o-mega.ai/articles/top-10-open-source-llms-the-deepseek-revolution-2026)

#### 4. GPT-OSS-120B **OPENAI'S OPEN SOURCE**

**Release Date:** Late 2025
**Parameters:** 117B total (MoE)
**Size:** ~60GB
**License:** Apache 2.0
**Developer:** OpenAI

**Performance:**
- Rivals o4-mini (OpenAI's proprietary model)
- First fully open-weight model from OpenAI
- Commercial use allowed

**Why Consider:**
- OpenAI's first open source contribution
- Proven lineage from GPT architecture
- Smaller size than Qwen3/DeepSeek

**Trade-offs:**
- Newest with least production history
- Less comprehensive than Qwen3 for education

**Sources:**
- [BentoML: Best Open-Source LLMs in 2026](https://www.bentoml.com/blog/navigating-the-world-of-open-source-large-language-models)

### Recommendation Summary

**Primary Choice:** Qwen3-235B-A22B-Instruct
- Latest release (May 2025)
- Best overall for education/tutoring use case
- Efficient MoE architecture
- Comprehensive domain coverage

**Specialized Alternatives:**
- GLM-4.7 if code tutoring is primary
- DeepSeek-V3.2 if general knowledge breadth is critical

---

## 3. Server TTS (Pre-generated Tutoring Audio)

### Use Case Requirements

- **Purpose:** Pre-generate high-quality tutoring audio content
- **Target Quality:** Near-human naturalness, expressive, engaging
- **Size Constraint:** None (server deployment)
- **Latency:** Not critical (batch processing)
- **Multilingual:** Beneficial for future expansion

### Recommended Models

#### 1. Fish Speech V1.5 ⭐ **PRIMARY RECOMMENDATION**

**Release Date:** Late 2025
**Architecture:** DualAR (Dual Autoregressive Transformer)
**Size:** ~2GB
**License:** BSD-3-Clause
**Developer:** Fish Audio

**Performance:**
- **ELO Score: 1339** (industry-leading)
- **Word Error Rate (English): 3.5%**
- **Character Error Rate (English): 1.2%**
- Exceptional multilingual support

**Training Data:**
- 300,000+ hours English and Chinese
- 100,000+ hours Japanese
- Additional languages supported

**Why This Model:**
- Industry-leading quality metrics
- Innovative DualAR architecture
- Extensive multilingual training
- Very low error rates
- Designed for production use

**Deployment:**
- GPU server recommended
- Can run on CPU for small batches
- Batch processing friendly

**Sources:**
- [Fish Speech Official Site](https://speech.fish.audio/)
- [BentoML: Best Open-Source Text-to-Speech Models in 2026](https://www.bentoml.com/blog/exploring-the-world-of-open-source-text-to-speech-models)
- [SiliconFlow: Best Open Source Text-to-Speech Models in 2026](https://www.siliconflow.com/articles/en/best-open-source-text-to-speech-models)

#### 2. Kyutai TTS 1.6B **LOW-LATENCY STREAMING**

**Release Date:** July 2025
**Parameters:** 1.6 billion
**Size:** ~1.6GB
**License:** MIT
**Developer:** Kyutai Labs

**Performance:**
- Delayed streams modeling
- Starts generating audio before complete text input
- ~220ms delay with Unmute wrapper system
- Ideal for voice assistants and low-latency applications

**Language Support:**
- English and French

**Why Consider:**
- If low-latency voice assistant is primary use case
- Streaming architecture for real-time responses
- MIT license (most permissive)
- From same lab as Pocket TTS (trusted source)
- Part of Unmute system (LLM + STT + TTS wrapper)

**When to Choose:**
- Building voice assistants or conversational AI
- Need minimal delay between text and audio
- English/French languages sufficient

**Trade-offs vs Fish Speech:**
- Limited to English/French vs multilingual
- Smaller training dataset
- Older release (July 2025 vs Late 2025)

**Sources:**
- [Hugging Face: kyutai/tts-1.6b-en_fr](https://huggingface.co/kyutai/tts-1.6b-en_fr)
- [GitHub: kyutai-labs/delayed-streams-modeling](https://github.com/kyutai-labs/delayed-streams-modeling)

#### 3. IndexTTS-2 **PRECISE CONTROL**

**Release Date:** Late 2025
**Size:** ~1.5GB
**License:** Apache 2.0
**Developer:** Alibaba DAMO Academy

**Performance:**
- Zero-shot voice synthesis
- Precise duration control
- Emotional disentanglement
- Professional-grade expressiveness

**Why Consider:**
- Perfect for video dubbing scenarios
- Fine-grained timing control
- Professional expressive speech
- Zero-shot capabilities

**When to Choose:**
- Need precise timing synchronization
- Multiple character voices
- Professional content production

**Sources:**
- [BentoML: Best Open-Source Text-to-Speech Models in 2026](https://www.bentoml.com/blog/exploring-the-world-of-open-source-text-to-speech-models)
- [SiliconFlow: Best Open Source Text-to-Speech Models in 2026](https://www.siliconflow.com/articles/en/best-open-source-text-to-speech-models)

#### 4. VibeVoice-1.5B **LONG-FORM CONTENT**

**Release Date:** Late 2025
**Parameters:** 1.5 billion
**Size:** ~3GB
**License:** MIT
**Developer:** Microsoft

**Performance:**
- Up to 90 minutes of continuous speech
- Four distinct speakers
- Highly expressive
- Long-form narration optimized

**Why Consider:**
- If generating long lectures/lessons
- Multi-speaker dialogue scenarios
- Microsoft backing and support

**When to Choose:**
- Tutoring sessions require extended audio
- Multi-character educational content
- Need variety in speaker voices

**Sources:**
- [Microsoft VibeVoice](https://aka.ms/vibevoice)
- [BentoML: Best Open-Source Text-to-Speech Models in 2026](https://www.bentoml.com/blog/exploring-the-world-of-open-source-text-to-speech-models)

#### 5. XTTS-v2 **VOICE CLONING**

**Release Date:** 2024-2025
**Size:** ~2GB
**License:** CPML (Coqui Public Model License)
**Developer:** Coqui (community maintained)

**Performance:**
- Zero-shot voice cloning from 6 seconds
- 17 languages supported
- High quality multilingual synthesis

**Why Consider:**
- Custom tutor voices from samples
- Extensive language support
- Established production use

**Trade-offs:**
- CPML license (check commercial terms)
- Coqui company shutdown (community maintained)

**Sources:**
- [BentoML: Best Open-Source Text-to-Speech Models in 2026](https://www.bentoml.com/blog/exploring-the-world-of-open-source-text-to-speech-models)
- [The Top Open-Source Text to Speech (TTS) Models](https://modal.com/blog/open-source-tts)

### Recommendation Summary

**Primary Choice:** Fish Speech V1.5
- Industry-leading quality
- Best metrics (ELO 1339)
- Extensive multilingual training
- Production-ready

**Specialized Alternatives:**
- Kyutai TTS 1.6B for low-latency voice assistants
- IndexTTS-2 for precise timing control
- VibeVoice-1.5B for very long content
- XTTS-v2 for voice cloning needs

---

## 4. On-Device TTS (Interactive Fallback)

### Use Case Requirements

- **Purpose:** Real-time TTS when server unavailable (last resort)
- **Target Quality:** Good enough for interaction, efficiency prioritized
- **Size Constraint:** <500MB preferred
- **Latency Target:** Real-time (<100ms per sentence)
- **Deployment:** iPhone 12+, Android 10+

### Current Implementation

**Model:** Apple Neural TTS (iOS/macOS built-in)
**Status:** ✅ **ADEQUATE** but upgrades available
**Size:** 0 bytes (built-in)
**Quality:** Efficient but limited naturalness
**License:** Proprietary

**Current Assessment:**
- Zero download size is major advantage
- Always available as fallback
- Acceptable for emergency use
- Not as natural as dedicated models

### Recommended Upgrades

#### 1. Kyutai Pocket TTS ⭐⭐⭐ **BEST CHOICE** (Released Jan 13, 2026)

**Release Date:** January 13, 2026 (6 days ago!)
**Parameters:** 100 million
**Size:** ~100MB
**License:** MIT
**Developer:** Kyutai Labs

**Performance:**
- **Best-in-class Word Error Rate: 1.84%** (beats 700M+ models)
- **Sub-50ms latency**
- **6x real-time speed** on MacBook Air M4 (2 CPU cores)
- Voice cloning from 5 seconds of audio
- First audio in 200 milliseconds

**Architecture:**
- Continuous Audio Language Models (CALM) framework
- CPU-only (no GPU required)
- 88,000 hours of training data
- Full training code published (reproducible)

**Why This Model:**
- **NEWEST model available** (Jan 13, 2026)
- **Best benchmarks:** 1.84% WER beats models 7x larger
- **Smallest size:** Only 100MB (5x smaller than NeuTTS)
- **CPU-only:** Works on any device without GPU
- **Production-grade quality** from academic research lab
- **MIT license:** Most permissive open source license

**Deployment:**
- Any CPU: iPhone, Android, laptops, even Raspberry Pi
- Supports Python 3.10-3.14
- Requires only PyTorch 2.5+ (CPU version)
- Real-time synthesis guaranteed

**Current Status:** English only (multilingual in development)

**Sources:**
- [Kyutai Pocket TTS Official Blog](https://kyutai.org/blog/2026-01-13-pocket-tts)
- [GitHub: kyutai-labs/pocket-tts](https://github.com/kyutai-labs/pocket-tts)
- [Hugging Face: kyutai/pocket-tts](https://huggingface.co/kyutai/pocket-tts)
- [Pocket TTS Technical Report](https://kyutai.org/pocket-tts-technical-report)

#### 2. NeuTTS Air **ALTERNATIVE**

**Release Date:** Late 2025
**Parameters:** 0.5 billion
**Size:** ~500MB (GGUF format)
**License:** Apache 2.0
**Developer:** Neuphonic

**Performance:**
- "Super-realistic" quality
- Instant voice cloning
- Near-human speech quality
- Real-time performance

**Why Consider:**
- llama.cpp compatible (GGUF/GGML format)
- Already integrated infrastructure if using llama.cpp
- Larger model may have quality advantages in some scenarios

**Trade-offs vs Pocket TTS:**
- 5x larger (500MB vs 100MB)
- Older release (late 2025 vs Jan 2026)
- No published WER benchmarks for direct comparison

**Sources:**
- [NeuTTS GitHub](https://github.com/neuphonic/neutts)
- [BentoML: Best Open-Source Text-to-Speech Models in 2026](https://www.bentoml.com/blog/exploring-the-world-of-open-source-text-to-speech-models)

#### 3. Kokoro-82M **ULTRA-LIGHTWEIGHT**

**Release Date:** Late 2025
**Parameters:** 82 million
**Size:** ~80MB
**License:** Apache 2.0
**Developer:** Kokoro AI

**Performance:**
- Quality comparable to much larger models
- Extremely lightweight (only 82M params)
- Fast generation (no encoders/diffusion)
- Based on StyleTTS2 and ISTFTNet

**Why Consider:**
- If size is critical (<100MB)
- Runs on any modern smartphone
- Very fast inference
- Cost-effective

**When to Choose:**
- Storage at absolute premium
- Need to run on very low-end devices
- Want faster-than-realtime synthesis

**Sources:**
- [Kokoro GitHub](https://github.com/kokoro-ai/kokoro)
- [BentoML: Best Open-Source Text-to-Speech Models in 2026](https://www.bentoml.com/blog/exploring-the-world-of-open-source-text-to-speech-models)

#### 3. CosyVoice2-0.5B **ULTRA-LOW LATENCY**

**Release Date:** 2025
**Parameters:** 0.5 billion
**Size:** ~500MB
**License:** Apache 2.0
**Developer:** Alibaba

**Performance:**
- Ultra-low latency streaming
- Optimized for real-time applications
- 0.5B parameters (similar to NeuTTS)

**Why Consider:**
- Streaming-first architecture
- Alibaba backing
- Real-time optimized

**Trade-offs:**
- Less proven than NeuTTS Air
- Newer release (less production history)

**Sources:**
- [BentoML: Best Open-Source Text-to-Speech Models in 2026](https://www.bentoml.com/blog/exploring-the-world-of-open-source-text-to-speech-models)

### Recommendation Summary

**Current Strategy:** Keep Apple Neural TTS as baseline fallback (zero cost)

**Primary Recommendation:** Kyutai Pocket TTS ⭐⭐⭐
- **Released Jan 13, 2026** (newest available)
- Only 100MB download
- Best WER (1.84%) in class
- CPU-only, works on any device
- Dramatic quality improvement over Apple TTS
- MIT license (most permissive)

**Alternatives:**
- NeuTTS Air if llama.cpp integration is priority
- Kokoro-82M if need <100MB (80MB)

---

## Implementation Priorities

### Immediate (Q1 2026)

1. **Replace Llama 3.2 1B with SmolLM3-3B** - HIGH PRIORITY
   > **SUPERSEDED 2026-06-26.** SmolLM3-3B was not adopted. See [unamentis-ios/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md](https://github.com/UnaMentis/unamentis-ios/blob/main/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md) (iOS repo).
   - Model is 14+ months outdated
   - Significant performance improvements available
   - ~1.5GB download (acceptable for target devices)
   - Update Knowledge Bowl validation code
   - Update documentation
   - Create migration plan

2. **Select and Deploy Server LLM** - HIGH PRIORITY
   - Choose Qwen3-235B-A22B-Instruct
   - Set up GPU server infrastructure
   - Test tutoring scenarios
   - Benchmark performance

### Near-term (Q2 2026)

3. **Implement Server TTS** - MEDIUM PRIORITY
   - Deploy Fish Speech V1.5
   - Create batch processing pipeline
   - Pre-generate common tutoring phrases
   - Test quality and latency

4. **Add NeuTTS Air as On-Device TTS Upgrade** - MEDIUM PRIORITY
   - Implement as optional download
   - Keep Apple TTS as fallback
   - User preference system
   - Test on target devices

### Future Considerations

- Monitor for newer model releases (2026 will see continued progress)
- Benchmark replacement models against current choices
- Update this document quarterly
- Consider multimodal models as they mature

---

## Model Evaluation Criteria

When evaluating future model updates, use these criteria:

### On-Device Models

> **Partly superseded 2026-06-26.** The on-device LLM size ceiling below (1-2GB) does not match the decided ladder, whose 12 GB tier is a 3.11 GB artifact. See [unamentis-ios/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md](https://github.com/UnaMentis/unamentis-ios/blob/main/docs/ios/ON_DEVICE_LLM_MODEL_RECONSIDERATION_2026-06-20.md) (iOS repo). The TTS criteria are unaffected.

1. **Release Date** - Prefer models from last 6 months
2. **Size** - Must fit within mobile constraints (1-2GB LLM, <500MB TTS)
3. **Benchmarks** - Quantitative performance on standard tasks
4. **License** - Apache 2.0 or similarly permissive strongly preferred
5. **Deployment** - llama.cpp/GGUF compatibility essential
6. **Community** - Active development and support

### Server Models

1. **Release Date** - Prefer latest generation
2. **Benchmarks** - Focus on instruction following, reasoning, domain knowledge
3. **License** - Must allow commercial use
4. **Documentation** - Well-documented with clear deployment guides
5. **Community** - Active ecosystem and support
6. **Hardware** - Feasible on available GPU infrastructure

---

## Tracking Updates

This document should be updated when:

- New state-of-the-art models are released
- Benchmark results significantly change
- Implementation priorities shift
- Quarterly review (minimum)

**Next Review:** April 2026

---

## Sources

### General Model Research
- [BentoML: Best Open-Source LLMs in 2026](https://www.bentoml.com/blog/navigating-the-world-of-open-source-large-language-models)
- [BentoML: Best Open-Source Small Language Models (SLMs) in 2026](https://www.bentoml.com/blog/the-best-open-source-small-language-models)
- [BentoML: Best Open-Source Text-to-Speech Models in 2026](https://www.bentoml.com/blog/exploring-the-world-of-open-source-text-to-speech-models)
- [State of LLMs 2025: Progress and Predictions](https://magazine.sebastianraschka.com/p/state-of-llms-2025)
- [Top 10 Open Source LLMs 2026: DeepSeek Revolution](https://o-mega.ai/articles/top-10-open-source-llms-the-deepseek-revolution-2026)

### On-Device LLMs
- [SmolLM3 Official Blog](https://huggingface.co/blog/smollm3)
- [Qwen3 Technical Report](https://arxiv.org/pdf/2505.09388)
- [Best Qwen Models in 2026](https://apidog.com/blog/best-qwen-models/)
- [GitHub: Awesome Mobile LLM](https://github.com/stevelaskaridis/awesome-mobile-llm)

### Server TTS
- [Fish Speech Official](https://speech.fish.audio/)
- [SiliconFlow: Best Open Source Text-to-Speech Models in 2026](https://www.siliconflow.com/articles/en/best-open-source-text-to-speech-models)
- [The Top Open-Source Text to Speech (TTS) Models](https://modal.com/blog/open-source-tts)

### Kyutai Labs Models
- [Kyutai Pocket TTS Official Blog](https://kyutai.org/blog/2026-01-13-pocket-tts)
- [Kyutai Pocket TTS Technical Report](https://kyutai.org/pocket-tts-technical-report)
- [GitHub: kyutai-labs/pocket-tts](https://github.com/kyutai-labs/pocket-tts)
- [Hugging Face: kyutai/pocket-tts](https://huggingface.co/kyutai/pocket-tts)
- [Hugging Face: kyutai/tts-1.6b-en_fr](https://huggingface.co/kyutai/tts-1.6b-en_fr)
- [GitHub: kyutai-labs/delayed-streams-modeling](https://github.com/kyutai-labs/delayed-streams-modeling)

### On-Device TTS
- [NeuTTS GitHub](https://github.com/neuphonic/neutts)
- [Kokoro GitHub](https://github.com/kokoro-ai/kokoro)

---

## Appendix: Quick Reference

| Use Case | Current | Recommended | Priority | Size | Status |
|----------|---------|-------------|----------|------|--------|
| On-Device LLM (KB Validation) | Llama 3.2 1B (Sept 2024) | SmolLM3-3B (Dec 2025) | HIGH | ~1.5GB | **SUPERSEDED 2026-06-26**, see currency note at top |
| Server LLM (Tutoring) | Not deployed | Qwen3-235B (May 2025) | HIGH | ~120GB | NEW |
| Server TTS (Pre-gen Audio) | Not deployed | Fish Speech V1.5 (Late 2025) | MEDIUM | ~2GB | NEW |
| On-Device TTS (Fallback) | Apple Neural TTS | Kyutai Pocket TTS (Jan 13, 2026) | HIGH | ~100MB | **UPGRADE NOW** |

---

*This document represents research conducted in January 2026. The AI model landscape evolves rapidly. Validate recommendations against latest releases and benchmarks before implementation.*
