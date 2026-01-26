# UnaMentis Cloud Deployment Execution Plan

**Status**: In Progress
**Last Updated**: 2025-01-25
**Target Completion**: 6 weeks from start
**Budget Target**: <$50/month for beta

This is the live tracking document for implementing the cloud architecture defined in [CLOUD_HOSTING_ARCHITECTURE.md](CLOUD_HOSTING_ARCHITECTURE.md).

---

## Phase Summary

| Phase | Description | Timeline | Status |
|-------|-------------|----------|--------|
| **Phase 0** | Documentation Housekeeping | Immediate | **Complete** |
| **Phase A** | Create SAM Project Structure | Week 1 | **In Progress** |
| **Phase B** | Extract Auth Service to Lambda | Week 1-2 | Not Started |
| **Phase C** | Extract KB Service to Lambda | Week 2-3 | Not Started |
| **Phase D** | Extract Curriculum + Metrics Services | Week 3 | Not Started |
| **Phase E** | Create Core Service Container | Week 3-4 | Not Started |
| **Phase F** | AWS Deployment | Week 4-5 | Not Started |
| **Phase G** | Monitoring + Hardening | Week 5-6 | Not Started |

---

## Phase 0: Documentation Housekeeping

**Status**: Complete
**Completed**: 2025-01-25

### Tasks

- [x] Create `docs/archive/` directory
- [x] Move `docs/architecture/CLOUD_HOSTING_ARCHITECTURE.md` → `docs/archive/CLOUD_HOSTING_ARCHITECTURE.old.md`
- [x] Move `docs/SCALING_SECURITY_MULTITENANCY_ANALYSIS.md` → `docs/archive/`
- [x] Create new `docs/architecture/CLOUD_HOSTING_ARCHITECTURE.md` from approved plan
- [x] Create this execution plan document

---

## Phase A: Create SAM Project Structure

**Status**: In Progress
**Timeline**: Week 1
**Estimated Cost**: $0 (local development only)
**Started**: 2025-01-25

### Prerequisites

- [ ] AWS account created and configured
- [ ] AWS CLI installed and configured with credentials
- [ ] SAM CLI installed (`brew install aws-sam-cli`)
- [ ] Docker Desktop installed (for `sam local`)

### Tasks

#### A.1: Install and Configure AWS SAM CLI
- [ ] Install SAM CLI: `brew install aws-sam-cli`
- [ ] Verify installation: `sam --version`
- [ ] Configure AWS credentials: `aws configure`
- [ ] Test SAM: `sam init` (interactive, then delete test project)

#### A.2: Create SAM Project Structure
- [x] Create `server/lambda/` directory
- [x] Create `server/lambda/template.yaml` (SAM template)
- [x] Create `server/lambda/samconfig.toml` (SAM config)
- [x] Create `server/lambda/services/` directory structure
- [x] Create `server/lambda/README.md` (setup instructions)

#### A.3: Create Shared Utilities
- [x] Create `server/lambda/services/shared/__init__.py`
- [x] Create `server/lambda/services/shared/db.py` (database connection pool)
- [x] Create `server/lambda/services/shared/auth.py` (JWT validation)
- [x] Create `server/lambda/services/shared/response.py` (standard API responses)
- [x] Create `server/lambda/services/shared/requirements.txt`

#### A.4: Create Service Placeholders
- [x] Create `server/lambda/services/auth/handler.py` (full implementation)
- [x] Create `server/lambda/services/kb/handler.py` (placeholder)
- [x] Create `server/lambda/services/curriculum/handler.py` (placeholder)
- [x] Create `server/lambda/services/metrics/handler.py` (placeholder)

#### A.5: Test Local Development
- [ ] Run `sam local start-api --port 8766`
- [ ] Verify hot reload works
- [ ] Test health endpoint

### Deliverables
- [x] SAM project structure in `server/lambda/`
- [x] Shared utilities for all Lambda functions
- [x] Auth service with all 11 endpoints (placeholder logic)
- [ ] Working local development environment (requires SAM CLI install)

---

## Phase B: Extract Auth Service to Lambda

**Status**: Not Started
**Timeline**: Week 1-2
**Source**: `server/management/auth/auth_api.py`

### Tasks

#### B.1: Create Auth Lambda Structure
- [ ] Create `server/lambda/services/auth/` directory
- [ ] Create `server/lambda/services/auth/__init__.py`
- [ ] Create `server/lambda/services/auth/handler.py`
- [ ] Create `server/lambda/services/auth/routes.py`
- [ ] Create `server/lambda/services/auth/requirements.txt`

#### B.2: Migrate Auth Endpoints (11 total)
- [ ] `POST /api/auth/register` - User registration
- [ ] `POST /api/auth/login` - User login
- [ ] `POST /api/auth/refresh` - Token refresh
- [ ] `POST /api/auth/logout` - User logout
- [ ] `GET /api/auth/me` - Get current user
- [ ] `POST /api/auth/forgot-password` - Password reset request
- [ ] `POST /api/auth/reset-password` - Password reset confirm
- [ ] `GET /api/auth/verify-email` - Email verification
- [ ] `POST /api/auth/resend-verification` - Resend verification email
- [ ] `GET /api/auth/sessions` - List user sessions
- [ ] `DELETE /api/auth/sessions/{id}` - Revoke session

#### B.3: Update SAM Template
- [ ] Add AuthFunction resource to `template.yaml`
- [ ] Configure API Gateway events for all auth routes
- [ ] Add environment variables (DATABASE_URL, JWT_SECRET)

#### B.4: Implement Beta Token Auth
- [ ] Add beta token validation middleware
- [ ] Create token storage (Secrets Manager or env var)
- [ ] Add rate limiting per token

#### B.5: Testing
- [ ] Test locally with `sam local invoke`
- [ ] Test with iOS client
- [ ] Test with Web client
- [ ] Test with Android client (when available)

### Deliverables
- Auth Lambda function with all 11 endpoints
- Beta token authentication working
- All three clients (iOS, Android, Web) connecting successfully

---

## Phase C: Extract KB Service to Lambda

**Status**: Not Started
**Timeline**: Week 2-3
**Source**: `server/management/kb_packs_api.py`

### Tasks

#### C.1: Create KB Lambda Structure
- [ ] Create `server/lambda/services/kb/` directory
- [ ] Create `server/lambda/services/kb/__init__.py`
- [ ] Create `server/lambda/services/kb/handler.py`
- [ ] Create `server/lambda/services/kb/routes.py`
- [ ] Create `server/lambda/services/kb/requirements.txt`

#### C.2: Migrate KB Endpoints (~20 total)
- [ ] `GET /api/kb/packs` - List question packs
- [ ] `POST /api/kb/packs` - Create question pack
- [ ] `GET /api/kb/packs/{id}` - Get pack details
- [ ] `PUT /api/kb/packs/{id}` - Update pack
- [ ] `DELETE /api/kb/packs/{id}` - Delete pack
- [ ] `GET /api/kb/packs/{id}/questions` - List questions in pack
- [ ] `POST /api/kb/packs/{id}/questions` - Add question to pack
- [ ] `GET /api/kb/questions` - List all questions
- [ ] `POST /api/kb/questions` - Create question
- [ ] `GET /api/kb/questions/{id}` - Get question details
- [ ] `PUT /api/kb/questions/{id}` - Update question
- [ ] `DELETE /api/kb/questions/{id}` - Delete question
- [ ] `GET /api/kb/domains` - List domains
- [ ] `POST /api/kb/domains` - Create domain
- [ ] `GET /api/kb/categories` - List categories
- [ ] Additional KB endpoints as identified

#### C.3: Skip for Core Service (Keep Stateful)
- [ ] Document `/api/kb/audio/*` endpoints (cache-dependent)
- [ ] Document `/api/kb/prefetch` (background task)
- [ ] Keep these in core service migration plan

#### C.4: Update SAM Template
- [ ] Add KBFunction resource to `template.yaml`
- [ ] Configure API Gateway events for all KB routes
- [ ] Add environment variables

#### C.5: Testing
- [ ] Test all CRUD operations locally
- [ ] Integration test with auth service
- [ ] Test with iOS client

### Deliverables
- KB Lambda function with ~20 endpoints
- Full CRUD working for packs and questions
- Integration with auth middleware

---

## Phase D: Extract Curriculum + Metrics Services

**Status**: Not Started
**Timeline**: Week 3

### Tasks

#### D.1: Create Curriculum Lambda
- [ ] Create `server/lambda/services/curriculum/` structure
- [ ] Migrate curriculum metadata endpoints (5)
  - [ ] `GET /api/curricula` - List curricula
  - [ ] `GET /api/curricula/{id}` - Get curriculum details
  - [ ] `GET /api/curricula/{id}/subjects` - List subjects
  - [ ] `GET /api/curricula/{id}/topics` - List topics
  - [ ] `GET /api/curricula/{id}/progress` - Get user progress
- [ ] Add to SAM template

#### D.2: Create Metrics Lambda
- [ ] Create `server/lambda/services/metrics/` structure
- [ ] Migrate system metrics endpoints (14)
  - [ ] `GET /api/metrics/system` - System health
  - [ ] `GET /api/metrics/sessions` - Session stats
  - [ ] `GET /api/metrics/users` - User stats
  - [ ] `GET /api/metrics/latency` - Latency metrics
  - [ ] Additional metrics endpoints
- [ ] Add to SAM template

#### D.3: Testing
- [ ] Test all curriculum endpoints
- [ ] Test all metrics endpoints
- [ ] Verify read-only nature

### Deliverables
- Curriculum Lambda (5 endpoints)
- Metrics Lambda (14 endpoints)
- All stateless reads migrated

---

## Phase E: Create Core Service Container

**Status**: Not Started
**Timeline**: Week 3-4

### Tasks

#### E.1: Create Core Service Structure
- [ ] Create `server/core/` directory
- [ ] Create `server/core/Dockerfile`
- [ ] Create `server/core/docker-compose.yml`
- [ ] Create `server/core/requirements.txt`

#### E.2: Extract WebSocket Handler
- [ ] Create `server/core/src/websocket/` directory
- [ ] Migrate `/ws` endpoint
- [ ] Migrate `/ws/audio` endpoint
- [ ] Implement WebSocket authentication (token in query param)

#### E.3: Extract TTS Cache
- [ ] Create `server/core/src/tts/` directory
- [ ] Migrate TTS caching logic
- [ ] Migrate TTS generation
- [ ] Configure S3/R2 for cache overflow

#### E.4: Extract Audio Streaming
- [ ] Create `server/core/src/audio/` directory
- [ ] Migrate audio streaming logic
- [ ] Optimize for low latency

#### E.5: Create SQS Consumer
- [ ] Create `server/core/src/jobs/` directory
- [ ] Implement SQS message consumption
- [ ] Add graceful shutdown handling
- [ ] Add job status tracking

#### E.6: Local Testing
- [ ] Test with docker-compose
- [ ] Test alongside SAM local API
- [ ] Verify WebSocket connections work
- [ ] Test voice session end-to-end

### Deliverables
- Core service Docker container
- WebSocket, TTS, audio streaming working
- SQS job processing ready

---

## Phase F: AWS Deployment

**Status**: Not Started
**Timeline**: Week 4-5
**Estimated Cost**: ~$17-30/month

### Tasks

#### F.1: Set Up AWS Infrastructure
- [ ] Create VPC with public/private subnets
- [ ] Set up NAT Gateway (or NAT instance for cost savings)
- [ ] Create security groups
- [ ] Create RDS PostgreSQL (db.t4g.micro, free tier)
- [ ] Create S3 bucket for TTS cache
- [ ] Set up Secrets Manager for API keys

#### F.2: Deploy Lambda Functions
- [ ] Run `sam build`
- [ ] Run `sam deploy --guided` (first time)
- [ ] Verify all Lambda functions deployed
- [ ] Test API Gateway endpoints

#### F.3: Deploy Core Service
- [ ] Push Docker image to ECR
- [ ] Create ECS Fargate Spot task definition
- [ ] Create ECS service
- [ ] Configure ALB target group
- [ ] Test WebSocket through ALB

#### F.4: Configure Cloudflare
- [ ] Add DNS records for unamentis.net
  - [ ] `api.unamentis.net` → API Gateway/ALB
  - [ ] `app.unamentis.net` → ALB (Web Client)
  - [ ] `admin.unamentis.net` → Cloudflare Tunnel
- [ ] Configure WAF rules
- [ ] Set up rate limiting
- [ ] Configure Cloudflare Access for admin console

#### F.5: Integration Testing
- [ ] Test full flow: Cloudflare → AWS → Lambda/ECS
- [ ] Test iOS client against cloud
- [ ] Test Web client against cloud
- [ ] Test Android client against cloud
- [ ] Test admin console access

### Deliverables
- All services running on AWS
- Cloudflare proxying all traffic
- All clients connecting successfully

---

## Phase G: Monitoring + Hardening

**Status**: Not Started
**Timeline**: Week 5-6

### Tasks

#### G.1: CloudWatch Setup
- [ ] Create CloudWatch dashboard for Lambda
- [ ] Create CloudWatch dashboard for ECS
- [ ] Set up log groups with retention
- [ ] Configure log insights queries

#### G.2: Alarms
- [ ] Lambda error rate alarm (>1%)
- [ ] Lambda duration alarm (>5s average)
- [ ] ECS CPU alarm (>80%)
- [ ] ECS memory alarm (>80%)
- [ ] RDS connection alarm
- [ ] API Gateway 5xx rate alarm

#### G.3: X-Ray Tracing
- [ ] Enable X-Ray for Lambda functions
- [ ] Enable X-Ray for API Gateway
- [ ] Configure service map
- [ ] Set up trace analysis

#### G.4: Cloudflare WAF
- [ ] Enable OWASP Core Rule Set
- [ ] Configure custom rules for known attack patterns
- [ ] Set up bot management (if needed)
- [ ] Review and tune false positives

#### G.5: Documentation
- [ ] Create runbook for common issues
- [ ] Document deployment process
- [ ] Document rollback procedure
- [ ] Create on-call playbook

#### G.6: Beta Tester Onboarding
- [ ] Create beta token generation process
- [ ] Document beta tester setup
- [ ] Set up feedback collection
- [ ] Establish usage metering

### Deliverables
- Full monitoring and alerting
- WAF protection active
- Beta testers onboarded

---

## Cost Tracking

| Date | Component | Cost | Notes |
|------|-----------|------|-------|
| - | Lambda | $0 | Free tier |
| - | API Gateway | $0 | Free tier |
| - | ECS Fargate Spot | TBD | Estimate $5-8 |
| - | RDS PostgreSQL | $0 | Free tier first 12mo |
| - | S3 | TBD | Estimate <$1 |
| - | Cloudflare | $0 | Free tier |
| - | **Monthly Total** | **TBD** | **Target: <$50** |

---

## Blockers and Risks

| Risk | Mitigation | Status |
|------|------------|--------|
| AWS account not set up | User needs to create AWS account | Not Started |
| Cloudflare account not set up | User needs to create Cloudflare account | Not Started |
| Cold start latency | Use provisioned concurrency if needed | Monitor |
| Spot instance interruption | Implement graceful shutdown | Phase E |
| Cost overrun | Set up billing alerts early | Phase F |

---

## Notes and Decisions

### 2025-01-25 (Evening)
- Phase A structure complete:
  - Created `server/lambda/` SAM project with full structure
  - Created `template.yaml` with all 4 services (auth, kb, curriculum, metrics)
  - Created shared utilities (db.py, auth.py, response.py)
  - Auth service has full placeholder implementation with 11 endpoints
  - Other services have placeholder handlers
- **Blocker**: SAM CLI not installed. User needs to run `brew install aws-sam-cli`
- Created README.md with setup instructions

### 2025-01-25 (Earlier)
- Architecture plan approved
- Phase 0 complete: Documentation housekeeping done
- Old docs archived to `docs/archive/`
- New architecture doc and execution plan created

---

## Next Steps

1. **Immediate**: Install SAM CLI (`brew install aws-sam-cli`) to complete Phase A testing
2. **After SAM Install**: Run `sam build && sam local start-api --port 8766` to test
3. **Phase B**: Begin full auth service implementation with database integration
4. **Decision Needed**: Confirm AWS account is ready for deployment
