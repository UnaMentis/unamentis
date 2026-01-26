# UnaMentis Cloud Hosting & Architecture Guide

This document covers cloud hosting options, pricing analysis, and architectural considerations for deploying the UnaMentis server infrastructure.

## Current Server Requirements

### Models Being Hosted

| Model | Purpose | VRAM | RAM | Disk |
|-------|---------|------|-----|------|
| **Mistral 7B** (Ollama) | LLM for tutoring conversations | ~5-6 GB | ~8 GB | 4.4 GB |
| **VibeVoice 0.5B** (Microsoft) | Real-time TTS streaming | ~2-3 GB | ~4 GB | 1.9 GB |
| **Whisper-small** (whisper.cpp) | Speech-to-text | Minimal | ~500 MB | ~140 MB |
| **Piper** (backup TTS) | Fallback TTS | CPU-only | ~50 MB | ~50 MB |
| **TOTAL** | | **~8-9 GB** | **~12-14 GB** | **~7 GB** |

### Performance Targets

- End-to-end latency: <500ms (median), <1000ms (P99)
- Memory growth: <50MB over 90 minutes
- Session stability: 90+ minutes without crashes

---

## Cloud Provider Comparison

### Tier 1: Budget GPU Cloud ($50-150/month)

| Provider | GPU | $/hr | Monthly (24/7) | Notes |
|----------|-----|------|----------------|-------|
| [**Vast.ai**](https://vast.ai/pricing) | RTX 3090 | $0.13-0.20 | $95-145 | Marketplace, variable reliability |
| [**TensorDock**](https://tensordock.com/) | RTX 3060/3090 | $0.12-0.16 | $90-120 | Consumer GPUs |
| [**RunPod Community**](https://www.runpod.io/pricing) | RTX 4090 | $0.34 | $245 | Better reliability than Vast |
| [**RunPod Serverless**](https://www.runpod.io/pricing) | A40 | $0.00044/sec | Pay per inference | Best for sporadic use |

**Best Budget Option:** Vast.ai with RTX 3090 (24GB VRAM) at ~$0.15/hr
- Running 4 hours/day: **~$18/month**
- Running 8 hours/day: **~$36/month**
- Running 24/7: **~$110/month**

### Tier 2: Standard Cloud Providers

| Provider | GPU | $/hr On-Demand | $/hr Spot/Preemptible |
|----------|-----|----------------|----------------------|
| [AWS g4dn.xlarge](https://aws.amazon.com/ec2/instance-types/g4/) | T4 16GB | $0.526 | ~$0.16-0.20 |
| [GCP n1-standard-4 + T4](https://cloud.google.com/compute/gpus-pricing) | T4 16GB | $0.35 + GPU | ~$0.11-0.15 |
| [Azure NC4as_T4_v3](https://azure.microsoft.com/pricing/) | T4 16GB | $0.526 | ~$0.16 |
| [AWS g5.xlarge](https://aws.amazon.com/ec2/instance-types/g5/) | A10G 24GB | $1.01 | ~$0.30-0.40 |

**Best Mainstream Option:** GCP Spot T4 at ~$0.12/hr or AWS Spot g4dn.xlarge at ~$0.16/hr

### Tier 3: Free Tiers (Limited Use)

| Platform | GPU | Limits | Best For |
|----------|-----|--------|----------|
| [Google Colab](https://colab.research.google.com) | T4 16GB | 12hr sessions, throttled | Prototyping only |
| [Kaggle](https://www.kaggle.com/) | T4/P100 | 30 GPU-hours/week (~4hr/day) | Light testing |
| [AWS SageMaker Studio Lab](https://studiolab.sagemaker.aws/) | T4 | 4 hours/day | Quick demos |
| [Lightning.ai](https://lightning.ai/) | Limited GPU | Free CPU 24/7, GPU hours limited | Development |

**Note:** These are unsuitable for persistent services due to session limits and prohibitions on running servers.

---

## Recommended Architectures

### Architecture A: Single GPU Instance (Current)

Best for: Development, testing, small user base

```
┌─────────────────────────────────────────────────────────────┐
│           GPU Instance (RTX 3090 / T4 / A10G)               │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Ollama    │  │  VibeVoice  │  │  Whisper            │  │
│  │ mistral:7b  │  │    0.5B     │  │  (whisper.cpp)      │  │
│  │   :11434    │  │   :8880     │  │     :11401          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│           ~6GB          ~3GB              Minimal           │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Management Console (:8766)                 ││
│  │              Python/aiohttp                             ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

**Pros:** Simple, all services co-located, low latency between components
**Cons:** All models cold start together, single point of failure

### Architecture B: Hybrid with External STT

Best for: Cost optimization, faster cold starts

```
┌─────────────────────────────────────────────────────────────┐
│           GPU Instance (smaller, ~6-7GB VRAM needed)        │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Ollama    │  │  VibeVoice  │  │ Management Console  │  │
│  │ mistral:7b  │  │    0.5B     │  │    (Python/aiohttp) │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│           ~6GB          ~3GB              ~100MB            │
└─────────────────────────────────────────────────────────────┘
           │
           ▼
    ┌─────────────┐
    │  Groq API   │  ← Free tier: 14,400 req/day
    │  Whisper    │    ~100-200ms latency
    └─────────────┘
```

**Pros:** Reduces VRAM requirements, STT always available (no cold start), lower costs
**Cons:** Network dependency for STT, rate limits on free tier

### Architecture C: Serverless Split

Best for: Pay-per-use, sporadic usage patterns

```
┌─────────────────────────────────────────────────────────────┐
│           Management Console (CPU VPS: $5-10/mo)            │
│           Fly.io / Railway / DigitalOcean                   │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┬─────────────┐
        ▼             ▼             ▼             ▼
  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ Groq     │  │ RunPod   │  │ RunPod   │  │ Piper    │
  │ Whisper  │  │Serverless│  │Serverless│  │ (Backup) │
  │ STT      │  │ LLM      │  │ TTS      │  │ CPU-only │
  └──────────┘  └──────────┘  └──────────┘  └──────────┘
    Free tier   $0.0004/sec   $0.0004/sec     Free
```

**Pros:** Pay only for actual inference, each service scales independently
**Cons:** Cold starts (30-60s), complexity, network latency between services

### Architecture D: Full Kubernetes (Future)

Best for: 500+ concurrent users, enterprise deployment

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                    (GKE / EKS / AKS)                        │
└─────────────────────────────────────────────────────────────┘
                      │
     ┌────────────────┼────────────────┐
     ▼                ▼                ▼
┌─────────┐    ┌───────────┐    ┌───────────┐
│ Always  │    │ GPU Pod   │    │ GPU Pod   │
│ Warm    │    │ Scale 0→N │    │ Scale 0→N │
│ CPU Pod │    │           │    │           │
│         │    │           │    │           │
│ Whisper │    │  LLM      │    │ TTS       │
│ (tiny)  │    │ (Triton)  │    │ (Triton)  │
└─────────┘    └───────────┘    └───────────┘
```

**When to use K8s:**
- Multi-tenant scenarios requiring isolation
- Multiple different models to serve
- Enterprise compliance requirements
- 500+ concurrent users

**When NOT to use K8s:**
- Single-app, single-model scenarios
- Early stage with < 100 concurrent users
- When cold start latency matters (K8s adds overhead)

---

## Hibernation Strategy

The UnaMentis server includes built-in idle state management that is critical for cost optimization:

| State | Idle Time | Actions | Power Draw |
|-------|-----------|---------|------------|
| **ACTIVE** | 0-30s | Full operation | High |
| **WARM** | 30s-5min | Reduced polling, models hot | Medium |
| **COOL** | 5-30min | Unload TTS model | Low |
| **COLD** | 30min-2hr | Unload all models | Minimal |
| **DORMANT** | 2hr+ | Only management console | Very Low |

### Credit Optimization with Hibernation

Credits are time-based. Aggressive hibernation extends credit runway:

| Usage Pattern | Monthly GPU Hours | Credit Multiplier |
|---------------|-------------------|-------------------|
| 24/7 always-on | 720 hours | 1x |
| 8 hours/day | 240 hours | 3x |
| 4 hours/day | 120 hours | 6x |

**Recommendation:** Set 30-minute idle shutdown when using credit-based hosting.

---

## GPU Requirements Summary

| Configuration | Min VRAM | Recommended GPU |
|---------------|----------|-----------------|
| All models local | 8-9 GB | T4 16GB, RTX 3060 12GB |
| STT offloaded to Groq | 6-7 GB | RTX 3060 12GB works |
| LLM + TTS only | 8-9 GB | RTX 3090 24GB (headroom) |
| 32B model option | 22-24 GB | A10G 24GB, RTX 4090 |

---

## Scaling Path

| User Scale | Recommended Setup | Estimated Cost |
|------------|-------------------|----------------|
| Development | Local M4 Mac or Vast.ai | $0-50/month |
| < 10 users | Single GPU instance + Groq STT | $20-50/month |
| 10-100 users | RunPod Community or AWS Spot | $100-250/month |
| 100-500 users | RunPod Serverless | $200-500/month |
| 500+ users | K8s with KServe/Triton | $500+/month |

---

## Quick Start Commands

### Local Development (M4 Mac)

```bash
# Start server
cd server && ./start.sh

# Verify services
curl http://localhost:11400/health
```

### Docker Deployment

```bash
# Build container
docker build -t unamentis-server .

# Run with GPU
docker run --gpus all -p 11400:11400 unamentis-server
```

### AWS EC2 Deployment

```bash
# Launch spot instance
aws ec2 run-instances \
  --image-id ami-xxxxxxxx \
  --instance-type g4dn.xlarge \
  --spot-options '{"SpotInstanceType":"persistent"}' \
  --key-name your-key
```

---

## Sources

- [AWS EC2 GPU Instances](https://aws.amazon.com/ec2/instance-types/g4/)
- [GCP GPU Pricing](https://cloud.google.com/compute/gpus-pricing)
- [RunPod Pricing](https://www.runpod.io/pricing)
- [Vast.ai Pricing](https://vast.ai/pricing)
- [Groq Console](https://console.groq.com)
- [KServe Documentation](https://kserve.github.io/website/)
- [NVIDIA Triton](https://developer.nvidia.com/triton-inference-server)
