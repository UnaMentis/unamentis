# UnaMentis AWS + Cloudflare Hosting Architecture

This document provides the comprehensive architecture for hosting UnaMentis on AWS with Cloudflare as the frontend, focusing on:
- **Extreme cost optimization** targeting **under $50/month** for initial beta (10-50 users)
- **Security** with proper API access control for **iOS, Android, and Web clients**
- **Separation of concerns** between public, authenticated, and internal services
- **Future-proof** path to Kubernetes and microservices (start simple, migrate later)

## Target Constraints

- **Budget**: <$50/month for beta, scaling up as user base grows
- **Users**: 10-50 initial beta users
- **Clients**: iOS, Android, Web (all need authenticated API access)
- **Strategy**: Simple architecture now, clear migration path to K8s later
- **Domain**: All servers on `unamentis.net`

## Two Deployment Models

**Model A: UnaMentis-Hosted (SaaS)**
- Free beta testers initially, expanding to public access
- Must be metered/controlled (budget cannot blow out)
- Primarily individual users
- Team competition access (segregated by team) - future
- Multi-tenant from the start

**Model B: Self-Hosted (Open Source)**
- Organizations deploy themselves (schools, enterprises)
- Straightforward installation on AWS or local servers
- Architecture must be **compatible with**:
  - Multi-tenant hosting
  - Enterprise security requirements (encryption, compliance)
  - Proprietary add-ons (outside this project scope)

## Authentication Strategy

| Component | Auth Level | Implementation |
|-----------|------------|----------------|
| **Client APIs** (iOS, Android, Web) | Simple | Pre-shared beta token initially. Keep strangers out, don't over-engineer. |
| **Admin Console** | Full | Cloudflare Access + JWT + MFA. Serious security. |
| **CF → API Backend** | Full | Verified Cloudflare headers + API keys. Prevent bypass. |

## Lambda Expansion Philosophy

The architecture assumes Lambda services **will expand significantly**:
- Current: ~40% Lambda-ready
- Target: ~70-80% Lambda (expand as we migrate more)
- Container-only: ML/AI inference, WebSocket, long-running jobs

This isn't just about migrating existing code. New features should default to Lambda microservices unless they have specific requirements (state, streaming, long-running).

---

## Current State Assessment

### Server Components

| Service | Port | Technology | Current State |
|---------|------|------------|---------------|
| **Management API** | 8766 | Python/aiohttp | Core backend, WebSocket for voice |
| **Operations Console** | 3000 | Next.js | Admin UI |
| **Web Client** | 3001 | Next.js | Voice tutoring for browsers |
| **USM Core** | 8787 | Rust/Axum | Service manager |
| **Ollama (LLM)** | 11434 | LLM inference | Self-hosted AI |
| **VibeVoice (TTS)** | 8880 | TTS streaming | Self-hosted AI |
| **Whisper (STT)** | 11401 | STT | Self-hosted AI |

### Critical Security Gaps (Must Fix)

1. **Zero Authentication** on Management API (CORS: `*`)
2. **No Multi-Tenancy** support
3. **No Data Encryption** at rest
4. **No Rate Limiting** at application level

---

## Target Architecture

### Network Topology

```
                              INTERNET
                                  │
              ┌───────────────────┴───────────────────┐
              │           CLOUDFLARE                   │
              │  ┌─────────────────────────────────┐  │
              │  │  DNS + WAF + DDoS Protection    │  │
              │  │  • app.unamentis.net (Web Client)│  │
              │  │  • api.unamentis.net (Mgmt API) │  │
              │  │  • admin.unamentis.net (CF Access)│ │
              │  └─────────────────────────────────┘  │
              │                    │                   │
              │  ┌─────────────────┴──────────────┐   │
              │  │     Cloudflare Tunnel          │   │
              │  │  (Admin access only)           │   │
              │  └─────────────────┬──────────────┘   │
              └────────────────────┼──────────────────┘
                                   │
┌──────────────────────────────────┼──────────────────────────────────┐
│                         AWS VPC (10.0.0.0/16)                        │
│                                  │                                   │
│    ┌─────────────────────────────┼─────────────────────────────┐    │
│    │              PUBLIC SUBNET (10.0.1.0/24)                   │    │
│    │  ┌──────────────────┐  ┌───────────────────────┐          │    │
│    │  │  NAT Gateway     │  │  Application Load     │          │    │
│    │  │  (outbound)      │  │  Balancer (ALB)       │          │    │
│    │  └──────────────────┘  │  • HTTPS termination  │          │    │
│    │                        │  • WebSocket support  │          │    │
│    │                        └──────────┬────────────┘          │    │
│    └───────────────────────────────────┼───────────────────────┘    │
│                                        │                             │
│    ┌───────────────────────────────────┼───────────────────────┐    │
│    │             PRIVATE SUBNET (10.0.10.0/24)                  │    │
│    │                                   │                        │    │
│    │   ┌───────────────┐  ┌───────────┴────────┐  ┌──────────┐ │    │
│    │   │ Web Client    │  │ Management API     │  │ Ops      │ │    │
│    │   │ (3001)        │  │ (8766)             │  │ Console  │ │    │
│    │   │ [PUBLIC]      │  │ [CLIENT AUTH]      │  │ (3000)   │ │    │
│    │   └───────────────┘  └────────────────────┘  │ [CF ACCESS]│    │
│    │                                               └──────────┘ │    │
│    │                        ┌──────────────┐                    │    │
│    │                        │  USM Core    │                    │    │
│    │                        │  (8787)      │                    │    │
│    │                        │  [INTERNAL]  │                    │    │
│    │                        └──────────────┘                    │    │
│    └────────────────────────────────────────────────────────────┘    │
│                                                                       │
│    ┌────────────────────────────────────────────────────────────┐    │
│    │              GPU SUBNET (10.0.20.0/24)                      │    │
│    │   ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  │    │
│    │   │ Ollama (LLM)  │  │ VibeVoice     │  │ Whisper (STT) │  │    │
│    │   │ (11434)       │  │ (8880)        │  │ (11401)       │  │    │
│    │   │ [INTERNAL]    │  │ [INTERNAL]    │  │ [INTERNAL]    │  │    │
│    │   └───────────────┘  └───────────────┘  └───────────────┘  │    │
│    └────────────────────────────────────────────────────────────┘    │
│                                                                       │
│    ┌────────────────────────────────────────────────────────────┐    │
│    │              DATA SUBNET (10.0.30.0/24)                     │    │
│    │   ┌─────────────────┐  ┌─────────────────┐                 │    │
│    │   │  RDS PostgreSQL │  │  ElastiCache    │                 │    │
│    │   │  (Multi-AZ)     │  │  Redis          │                 │    │
│    │   └─────────────────┘  └─────────────────┘                 │    │
│    └────────────────────────────────────────────────────────────┘    │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

              ┌────────────────────────────────────────┐
              │          CLOUDFLARE R2                 │
              │  • Curriculum assets (static)          │
              │  • TTS cache overflow                  │
              │  • Zero egress fees                    │
              └────────────────────────────────────────┘
```

---

## Component Access Matrix

| Component | Port | Access Level | Exposure Method | Authentication |
|-----------|------|--------------|-----------------|----------------|
| **Web Client** | 3001 | Public | CF Proxy -> ALB | None (public app) |
| **Management API** | 8766 | Authenticated | CF Proxy -> ALB | JWT (iOS/Web clients) |
| **Management API (Admin)** | 8766 | Admin only | CF Access | MFA required |
| **Operations Console** | 3000 | Admin only | CF Tunnel + Access | MFA required |
| **USM Core** | 8787 | Internal only | VPC security group | N/A |
| **AI Models** | 8880, 11401, 11434 | Internal only | GPU subnet SG | N/A |
| **PostgreSQL** | 5432 | Internal only | Data subnet SG | N/A |

---

## Cloudflare Configuration

### DNS Records

```
# Public endpoints (Cloudflare Proxied - orange cloud)
app.unamentis.net       CNAME  [ALB DNS name]    Proxied    # Web Client
api.unamentis.net       CNAME  [ALB DNS name]    Proxied    # Management API

# Admin endpoints (Cloudflare Access protected)
admin.unamentis.net     CNAME  [Tunnel ID].cfargotunnel.com  Proxied
```

### Cloudflare Access Policy (Zero Trust)

```yaml
Application: "UnaMentis Admin Console"
Domain: admin.unamentis.net
Type: self_hosted

Policies:
  - Name: "Admin Team Only"
    Decision: allow
    Include:
      - Email domain: unamentis.com
      - Specific emails:
        - admin1@gmail.com
        - admin2@gmail.com
    Require:
      - MFA: true

Session Duration: 8h
```

### WAF and Security Rules

```yaml
# Rate limiting
- Pattern: api.unamentis.net/api/*
  Rate: 100 requests/minute per IP
  Action: challenge

# Block non-Cloudflare traffic at ALB
- Only allow Cloudflare IP ranges to ALB security group

# WebSocket support (automatic with proxy)
- Pattern: api.unamentis.net/ws/*
  Idle timeout: Configure 300s at ALB for voice sessions
  Heartbeat: Implement 30s ping/pong in application
```

### Cloudflare Tunnel for Internal Services

```yaml
# /etc/cloudflared/config.yml
tunnel: [tunnel-uuid]
credentials-file: /etc/cloudflared/credentials.json

ingress:
  # Operations Console (internal admin)
  - hostname: admin.unamentis.net
    service: http://localhost:3000

  # Catch-all
  - service: http_status:404
```

---

## Hybrid Microservices Architecture (RECOMMENDED)

Based on API analysis, ~40% of endpoints are Lambda-ready, ~60% require a stateful container. The recommended architecture splits these cleanly.

### Architecture Overview

```
                         INTERNET
                             │
         ┌───────────────────┴───────────────────┐
         │         CLOUDFLARE (Free Tier)         │
         │  • DNS: *.unamentis.net               │
         │  • WAF, DDoS protection               │
         │  • Static assets (R2)                  │
         │  • api.unamentis.net -> AWS            │
         │  • app.unamentis.net -> AWS            │
         │  • admin.unamentis.net -> CF Access    │
         └───────────────────┬───────────────────┘
                             │
         ┌───────────────────┴───────────────────┐
         │              AWS                       │
         │                                        │
         │  ┌─────────────────────────────────┐  │
         │  │     API Gateway + Lambda         │  │
         │  │     (Stateless microservices)    │  │
         │  │                                  │  │
         │  │  Current (~50 endpoints):        │  │
         │  │  • Auth (11 endpoints)           │  │
         │  │  • KB CRUD (20)                  │  │
         │  │  • Curriculum metadata (5)       │  │
         │  │  • System metrics (14)           │  │
         │  │                                  │  │
         │  │  Future expansion (~30-40% more):│  │
         │  │  • Lists, FOV, Media             │  │
         │  │  • Import browsing               │  │
         │  │  • New features (default Lambda) │  │
         │  │                                  │  │
         │  │  Cost: Pay-per-request           │  │
         │  │  (Free tier: 1M req/mo)          │  │
         │  └─────────────────────────────────┘  │
         │                   │                    │
         │                   ▼                    │
         │  ┌─────────────────────────────────┐  │
         │  │     ECS Fargate Spot            │  │
         │  │     (Stateful core service)      │  │
         │  │                                  │  │
         │  │  • WebSocket handler             │  │
         │  │  • TTS cache + generation        │  │
         │  │  • Audio streaming               │  │
         │  │  • Long-running jobs (SQS)       │  │
         │  │  • ML inference (future)         │  │
         │  │                                  │  │
         │  │  Cost: ~$5-15/month              │  │
         │  │  (Fargate Spot 0.25vCPU/0.5GB)   │  │
         │  └─────────────────────────────────┘  │
         │                   │                    │
         │                   ▼                    │
         │  ┌─────────────────────────────────┐  │
         │  │     Shared Data Layer            │  │
         │  │                                  │  │
         │  │  • RDS PostgreSQL (free tier)   │  │
         │  │  • S3 (TTS cache, curricula)    │  │
         │  │  • SQS (job queue)              │  │
         │  │  • Secrets Manager              │  │
         │  └─────────────────────────────────┘  │
         │                   │                    │
         │                   ▼                    │
         │  ┌─────────────────────────────────┐  │
         │  │     External AI APIs             │  │
         │  │     (Pay-per-use)                │  │
         │  │                                  │  │
         │  │  • Groq: Free STT (14K req/day) │  │
         │  │  • OpenAI: LLM ($0.15/1M tokens)│  │
         │  │  • Deepgram: TTS ($0.0043/sec)  │  │
         │  │  • Future: AWS Bedrock          │  │
         │  └─────────────────────────────────┘  │
         └────────────────────────────────────────┘
```

### Service Split

| Service | Runtime | Endpoints | Why |
|---------|---------|-----------|-----|
| **auth-service** | Lambda | 11 | Stateless, quick DB ops |
| **curriculum-service** | Lambda | 5 read + metadata | Stateless reads |
| **kb-service** | Lambda | 20 | CRUD, mostly stateless |
| **metrics-service** | Lambda | 14 | Read-only metrics |
| **core-service** | ECS/EC2 | WebSocket, TTS, streaming | Stateful, long-lived |

### Cost Estimate (Cloud-Only)

| Component | Specification | Cost/Month |
|-----------|---------------|------------|
| **Lambda** | 1M free requests, then $0.20/M | $0-5 |
| **API Gateway** | 1M free requests, then $3.50/M | $0-5 |
| **ECS Fargate Spot** | 0.25 vCPU, 0.5GB (spot) | $5-8 |
| **RDS PostgreSQL** | db.t4g.micro (750hr free tier) | $0 (first 12mo) |
| **S3** | 5GB TTS cache + curricula | $0.15 |
| **SQS** | 1M free requests | $0 |
| **Secrets Manager** | 5 secrets | $2 |
| **CloudWatch** | Basic logs/metrics | $0-5 |
| **Cloudflare** | Free tier | $0 |
| **External AI APIs** | Groq (free), OpenAI, Deepgram | $10-30 (usage) |
| **Total (Beta)** | | **$17-50/month** |

**After AWS Free Tier expires (12 months):**
- RDS: +$15/month
- Total: **$32-65/month**

### Lambda Function Structure (SAM)

```yaml
# template.yaml (AWS SAM)
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Globals:
  Function:
    Runtime: python3.11
    Timeout: 30
    MemorySize: 256
    Environment:
      Variables:
        DATABASE_URL: !Ref DatabaseUrl

Resources:
  # Auth Service
  AuthFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: auth.handler
      CodeUri: services/auth/
      Events:
        Register:
          Type: Api
          Properties:
            Path: /api/auth/register
            Method: POST
        Login:
          Type: Api
          Properties:
            Path: /api/auth/login
            Method: POST
        # ... more auth endpoints

  # KB Service
  KBFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: kb.handler
      CodeUri: services/kb/
      Events:
        ListPacks:
          Type: Api
          Properties:
            Path: /api/kb/packs
            Method: GET
        # ... more KB endpoints

  # Curriculum Service (read-only)
  CurriculumFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: curriculum.handler
      CodeUri: services/curriculum/
      Events:
        List:
          Type: Api
          Properties:
            Path: /api/curricula
            Method: GET
```

### Local Development with SAM

```bash
# Install SAM CLI
brew install aws-sam-cli

# Start local API (Lambda emulation)
cd server/lambda
sam local start-api --port 8766

# Start core service (container)
docker-compose up core-service

# Both run locally, same code deploys to AWS
```

### Directory Structure

```
server/
├── lambda/                     # Lambda functions (SAM project)
│   ├── template.yaml           # SAM template
│   ├── samconfig.toml          # SAM config
│   ├── services/
│   │   ├── auth/
│   │   │   ├── __init__.py
│   │   │   ├── handler.py      # Lambda entry point
│   │   │   ├── routes.py       # Route definitions
│   │   │   └── requirements.txt
│   │   ├── kb/
│   │   ├── curriculum/
│   │   ├── metrics/
│   │   └── shared/             # Shared utilities
│   │       ├── db.py           # Database connection
│   │       ├── auth.py         # JWT validation
│   │       └── response.py     # Standard responses
│   └── tests/
│
├── core/                       # Stateful container service
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── src/
│   │   ├── websocket/          # WebSocket handlers
│   │   ├── tts/                # TTS cache + generation
│   │   ├── audio/              # Audio streaming
│   │   └── jobs/               # Long-running job processor
│   └── requirements.txt
│
└── management/                 # Current monolith (gradually migrate)
    └── server.py
```

---

## AWS Resource Recommendations (Future Scaling)

### Tier 1: Minimal Cloud ($150-250/month)

**For: 10-50 users, development, early beta**

| Resource | Specification | Cost/Month |
|----------|---------------|------------|
| EC2 t3.medium | 2 vCPU, 4GB (App services) | $30 |
| EC2 g4dn.xlarge (Spot) | T4 GPU (AI models) | $80-120 |
| RDS db.t3.micro | PostgreSQL, 20GB | $15 |
| EBS gp3 | 100GB (TTS cache) | $8 |
| NAT Gateway | Outbound internet | $30-45 |
| **Total** | | **$163-218** |

**Cloudflare**: Free tier (100K req/day, basic WAF)

### Tier 2: Recommended Production ($400-600/month)

**For: 50-500 users, production launch**

| Resource | Specification | Cost/Month |
|----------|---------------|------------|
| ECS Fargate | 2 tasks (Web + API) | $75 |
| EC2 g4dn.xlarge | 70% spot / 30% on-demand | $140 |
| RDS db.t3.small | Multi-AZ, 50GB | $50 |
| ElastiCache t3.micro | Redis for sessions | $15 |
| ALB | Load balancer + SSL | $20 |
| NAT Gateway | Enhanced | $45 |
| CloudWatch | Logs + metrics | $20 |
| Secrets Manager | 10 secrets | $5 |
| **Total** | | **$370-470** |

**Cloudflare Pro**: $20/month (enhanced WAF, analytics)

### Tier 3: Growth ($1,500-2,500/month)

**For: 500-5,000 users, scaling**

| Resource | Specification | Cost/Month |
|----------|---------------|------------|
| EKS | Managed Kubernetes | $73 |
| EC2 ASG | 2-6 c6i.large | $200-400 |
| GPU ASG | 1-3 g4dn.xlarge mixed | $200-450 |
| RDS db.r6g.large | Multi-AZ, 200GB | $300 |
| ElastiCache r6g.large | Redis cluster | $150 |
| EFS | 500GB TTS cache | $150 |
| **Total** | | **$1,073-1,523** |

**Cloudflare Business**: $200/month (custom WAF, 100% SLA)

---

## Security Layers

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Edge (Cloudflare)                                   │
│   • DDoS mitigation (unmetered)                             │
│   • WAF (OWASP core rules)                                  │
│   • Bot management                                          │
│   • Rate limiting (1000 req/10s)                            │
│   • IP reputation                                           │
└─────────────────────────────────┬───────────────────────────┘
                                  │
┌─────────────────────────────────┴───────────────────────────┐
│ Layer 2: Access Control (Cloudflare Access)                  │
│   • Zero-trust for admin interfaces                         │
│   • MFA requirement                                         │
│   • Device posture checks (optional)                        │
└─────────────────────────────────┬───────────────────────────┘
                                  │
┌─────────────────────────────────┴───────────────────────────┐
│ Layer 3: Network (AWS VPC)                                   │
│   • ALB only accepts Cloudflare IPs                         │
│   • Security groups restrict internal traffic               │
│   • Private subnets for data/GPU                            │
│   • VPC Flow Logs for audit                                 │
└─────────────────────────────────┬───────────────────────────┘
                                  │
┌─────────────────────────────────┴───────────────────────────┐
│ Layer 4: Application                                         │
│   • JWT authentication for client APIs                      │
│   • CORS allowlist (not wildcard)                           │
│   • Input validation                                        │
│   • Rate limiting (token bucket)                            │
└─────────────────────────────────┬───────────────────────────┘
                                  │
┌─────────────────────────────────┴───────────────────────────┐
│ Layer 5: Data                                                │
│   • RDS encryption at rest (AES-256)                        │
│   • TLS 1.3 in transit                                      │
│   • Secrets Manager for API keys                            │
│   • EFS encryption                                          │
└─────────────────────────────────────────────────────────────┘
```

---

## API Access Control Strategy

### Authentication Tiers

| Tier | Components | Auth Method | Purpose |
|------|------------|-------------|---------|
| **Tier 1: Client** | iOS, Android, Web apps | Pre-shared beta token | Keep strangers out, simple for beta |
| **Tier 2: Admin** | Operations Console | Cloudflare Access + JWT + MFA | Serious security for admin functions |
| **Tier 3: Backend** | CF → API Gateway | CF-Access-Authenticated-User-Email header + secret | Prevent direct API bypass |

### Tier 1: Client Authentication (Simple Beta Token)

For beta phase, use a simple pre-shared token approach:

```
# Client includes on all requests:
Authorization: Bearer uma_beta_2024_<random_suffix>
X-Client-Platform: ios|android|web
X-Client-Version: 1.0.0

# Server validates:
- Token matches known beta tokens list
- Rate limits per token (prevent abuse)
- Optional: token tied to device ID
```

**Beta token management:**
- Tokens stored in AWS Secrets Manager or environment variable
- Each beta tester gets a unique token
- Tokens can be revoked individually
- Future: migrate to full OAuth when needed

### Tier 2: Admin Authentication (Full Security)

```
Admin Console (admin.unamentis.net)
         │
         ▼
┌─────────────────────────────────────────┐
│     Cloudflare Access (Zero Trust)      │
│  • Email allowlist or domain            │
│  • MFA required                         │
│  • Session duration: 8 hours            │
└─────────────────────────────────────────┘
         │
         ▼ (CF-Access-Authenticated-User-Email header)
         │
┌─────────────────────────────────────────┐
│     API Gateway / Lambda                │
│  • Validate CF header                   │
│  • Check user in admin role             │
│  • Full audit logging                   │
└─────────────────────────────────────────┘
```

### Tier 3: Backend Security (CF → AWS)

Prevent direct API access (bypassing Cloudflare):

```python
# Lambda middleware
def validate_cloudflare_request(event):
    # 1. Check Cloudflare IP ranges (optional but recommended)
    source_ip = event['requestContext']['identity']['sourceIp']
    if not is_cloudflare_ip(source_ip):
        return unauthorized()

    # 2. Validate CF-connecting IP header
    cf_ip = event['headers'].get('CF-Connecting-IP')

    # 3. For admin routes, validate CF Access headers
    if is_admin_route(event['path']):
        cf_email = event['headers'].get('CF-Access-Authenticated-User-Email')
        if not cf_email or not is_admin(cf_email):
            return forbidden()
```

### Endpoint Classification

```
/api/health              → PUBLIC (no auth, for health checks)
/api/curricula/*         → TIER_1 (beta token required)
/api/sessions/*          → TIER_1 (beta token required)
/api/tts/*               → TIER_1 (beta token required)
/api/kb/*                → TIER_1 (beta token required)
/ws/audio                → TIER_1 (token in query param)
/api/admin/*             → TIER_2 (Cloudflare Access + admin role)
/api/import-jobs/*       → TIER_2
/api/deployments/*       → TIER_2
```

### Future: Full OAuth (Post-Beta)

When ready to move beyond beta tokens:

```yaml
# iOS
apple_sign_in:
  client_id: com.unamentis.app
  redirect_uri: https://api.unamentis.net/auth/apple/callback

# Android
google_sign_in:
  client_id: [from Google Cloud Console]
  redirect_uri: https://api.unamentis.net/auth/google/callback

# Web
google_oauth:
  client_id: [from Google Cloud Console]
  redirect_uri: https://app.unamentis.net/auth/callback
```

---

## Multi-Tenancy & Self-Hosted Compatibility

The architecture must support two deployment models. While we're building Model A first, the design must be **compatible** with Model B requirements.

### Model A: UnaMentis-Hosted (SaaS)

```
┌─────────────────────────────────────────────────────────────┐
│                    unamentis.net                             │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Individual  │  │ Individual  │  │   Team      │         │
│  │   User A    │  │   User B    │  │ Competition │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                  │
│         ▼                ▼                ▼                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Shared Multi-Tenant Backend               │   │
│  │                                                      │   │
│  │  • User isolation via tenant_id in all queries      │   │
│  │  • Rate limiting per user/team                      │   │
│  │  • Usage metering for budget control                │   │
│  │  • Team segregation for competitions                │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Key features:**
- Metered usage (prevent budget blowout)
- Individual user isolation
- Team competition mode (future): segregated team access
- Shared infrastructure, logical isolation

### Model B: Self-Hosted (Open Source)

```
┌─────────────────────────────────────────────────────────────┐
│              Organization's Infrastructure                   │
│              (school.edu or enterprise.com)                  │
│                                                              │
│  Option 1: AWS Deployment                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  CloudFormation/Terraform template provided         │   │
│  │  • Lambda + API Gateway (microservices)             │   │
│  │  • ECS Fargate (core service)                       │   │
│  │  • RDS PostgreSQL                                   │   │
│  │  • S3 for storage                                   │   │
│  │  One-click deploy with customizable config          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  Option 2: On-Premises / Private Cloud                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Docker Compose or Kubernetes Helm chart            │   │
│  │  • All services containerized                       │   │
│  │  • PostgreSQL (container or external)               │   │
│  │  • S3-compatible storage (MinIO)                    │   │
│  │  Works on any server with Docker                    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Architecture Compatibility Requirements

For the architecture to support both models, we need:

| Requirement | Implementation | Notes |
|-------------|----------------|-------|
| **Tenant isolation** | `tenant_id` column in all tables | Filter all queries by tenant |
| **Configurable auth** | Auth service abstraction | Swap providers (beta token, OAuth, SAML) |
| **Storage abstraction** | S3-compatible interface | Works with S3, R2, MinIO |
| **Database abstraction** | PostgreSQL only | Standard, works everywhere |
| **Secrets abstraction** | Environment variables | Works with AWS Secrets Manager, Vault, or plain env |
| **Queue abstraction** | SQS interface | Can swap for RabbitMQ, Redis queues |

### Enterprise Extensions (Outside Project Scope)

These are **not** part of this project but the architecture must not block them:

- Full encryption at rest (database, S3)
- SAML/OIDC enterprise SSO
- Audit logging for compliance
- Data residency controls
- Role-based access control (RBAC)
- SOC 2 / HIPAA compliance features

The core architecture provides the **hooks** for these:
- All data access goes through repositories (encryption layer can be added)
- Auth is abstracted (SAML provider can be added)
- Logging infrastructure exists (compliance logging can be added)
- Tenant isolation is built-in (data residency can be added per tenant)

### Cloudflare Workers for API Security

```javascript
// Cloudflare Worker (edge proxy for api.unamentis.net)
export default {
  async fetch(request, env) {
    // Add security headers
    const response = await fetch(request);
    const newHeaders = new Headers(response.headers);
    newHeaders.set('X-Content-Type-Options', 'nosniff');
    newHeaders.set('X-Frame-Options', 'DENY');
    newHeaders.set('Strict-Transport-Security', 'max-age=31536000');

    return new Response(response.body, {
      status: response.status,
      headers: newHeaders
    });
  }
};
```

---

## Scaling Path

### Phase 1: Single Instance (Current -> 50 users)

```
┌─────────────────────────────────────────────┐
│  EC2 t3.medium + g4dn.xlarge (spot)         │
│                                              │
│  [Web Client] [Mgmt API] [Ops Console]      │
│              [SQLite]                        │
│  [Ollama] [VibeVoice] [Whisper]             │
│                                              │
│  Cost: ~$150-180/month                       │
└─────────────────────────────────────────────┘
```

**Trigger for Phase 2**: >30 concurrent users OR >200ms API latency

### Phase 2: Service Separation (50-500 users)

```
┌─────────────────────────────────────────────┐
│  ECS Fargate                                 │
│  [Web Client x2] [Mgmt API x2] [Ops x1]     │
│              ↓                               │
│         [RDS PostgreSQL]                     │
│              ↓                               │
│  GPU Instance (dedicated)                    │
│  [Ollama] [VibeVoice] [Whisper]             │
│                                              │
│  Cost: ~$400-500/month                       │
└─────────────────────────────────────────────┘
```

**Trigger for Phase 3**: >300 concurrent users OR GPU >80%

### Phase 3: Kubernetes (500-5,000 users)

```
┌─────────────────────────────────────────────┐
│  EKS Cluster                                 │
│  ┌────────────────────────────────────────┐ │
│  │ App Nodes (ASG): Web x4, API x4        │ │
│  └────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────┐ │
│  │ GPU Nodes (ASG): LLM x3, TTS x2, STT x2│ │
│  └────────────────────────────────────────┘ │
│  [RDS Multi-AZ] [ElastiCache Cluster]       │
│                                              │
│  Cost: ~$1,500-2,500/month                   │
└─────────────────────────────────────────────┘
```

### Phase 4: Multi-Region (10,000+ users)

```
┌─────────────────────────────────────────────────────────────┐
│  Cloudflare Global Traffic Manager                           │
│              │                                               │
│   ┌──────────┼──────────┬──────────┐                        │
│   ↓          ↓          ↓                                    │
│ [US-West]  [US-East]  [EU-West]                             │
│  EKS        EKS        EKS                                   │
│  RDS Pri    RDS Rep    RDS Rep                              │
│                                                              │
│  Cost: ~$8,000-15,000/month                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Cost Optimization Strategies

1. **Spot Instances for GPU**: 60-70% savings on g4dn
   - Use Spot Fleet with fallback instance types
   - Graceful model unloading on spot interruption

2. **Reserved Instances**: 30% savings for baseline
   - Reserve RDS and 1 application instance
   - Keep burst capacity on-demand

3. **Cloudflare R2 vs S3**: Zero egress fees
   - TTS cache overflow to R2
   - Static curriculum assets on R2

4. **Right-sizing**: Start small, scale on metrics
   - Use AWS Compute Optimizer

5. **Hibernation**: Existing idle management
   - COOL state after 5-30min idle
   - DORMANT after 2hr+

---

## Files to Create/Modify

### New Files (Lambda)
```
server/lambda/
├── template.yaml                    # SAM template
├── samconfig.toml                   # SAM config
├── services/
│   ├── auth/handler.py              # Auth Lambda
│   ├── kb/handler.py                # KB Lambda
│   ├── curriculum/handler.py        # Curriculum Lambda
│   ├── metrics/handler.py           # Metrics Lambda
│   └── shared/
│       ├── db.py                    # DB connection
│       ├── auth.py                  # JWT validation
│       └── response.py              # Standard responses
└── tests/
```

### New Files (Core Service)
```
server/core/
├── Dockerfile
├── docker-compose.yml
├── src/
│   ├── main.py                      # Entry point
│   ├── websocket/handler.py         # WebSocket
│   ├── tts/cache.py                 # TTS cache
│   ├── audio/streaming.py           # Audio streaming
│   └── jobs/consumer.py             # SQS consumer
└── requirements.txt
```

### Files to Modify
- `server/management/server.py` - Remove migrated endpoints, keep as core service base
- `server/management/auth/` - Extract to Lambda, keep for reference
- `server/management/kb_packs_api.py` - Extract to Lambda

---

## Verification Plan

### Security Testing
- [ ] Verify Cloudflare WAF blocks common attacks
- [ ] Confirm ALB only accepts Cloudflare IPs
- [ ] Test JWT authentication flow (iOS + Web)
- [ ] Verify admin routes require Cloudflare Access
- [ ] Confirm internal services not accessible from internet

### Performance Testing
- [ ] WebSocket latency through Cloudflare (<50ms overhead)
- [ ] API response times under load
- [ ] Voice session stability (90+ minutes)
- [ ] Spot instance interruption handling

### Cost Monitoring
- [ ] Set up AWS Cost Explorer alerts
- [ ] Track Cloudflare request usage
- [ ] Monitor GPU utilization for right-sizing

---

## Key Reference Documents

- [CLOUD_HOSTING_ARCHITECTURE.old.md](../archive/CLOUD_HOSTING_ARCHITECTURE.old.md) - Previous cost analysis (archived)
- [SCALING_SECURITY_MULTITENANCY_ANALYSIS.md](../archive/SCALING_SECURITY_MULTITENANCY_ANALYSIS.md) - Security gaps analysis (archived)
- [server/management/server.py](../../server/management/server.py) - Main API to secure
- [server/management/auth/](../../server/management/auth/) - Existing JWT implementation
- [CLOUD_DEPLOYMENT_EXECUTION_PLAN.md](CLOUD_DEPLOYMENT_EXECUTION_PLAN.md) - Live implementation tracking

## External Resources

- [Cloudflare Security Architecture](https://developers.cloudflare.com/reference-architecture/architectures/security/)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)
- [Cloudflare API Gateway](https://developers.cloudflare.com/api-shield/api-gateway/)
- [AWS + Cloudflare Integration](https://www.subaud.io/deploying-aws-applications-with-cloudflare/)
