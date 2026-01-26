# UnaMentis Lambda Services

AWS SAM-based serverless backend for UnaMentis voice tutoring platform.

## Prerequisites

1. **AWS CLI** - Install and configure with your credentials:
   ```bash
   brew install awscli
   aws configure
   ```

2. **AWS SAM CLI** - Install the Serverless Application Model CLI:
   ```bash
   brew install aws-sam-cli
   ```

3. **Docker** - Required for `sam local`:
   ```bash
   # Docker Desktop should be installed and running
   ```

4. **Python 3.11** - Required for Lambda runtime:
   ```bash
   brew install python@3.11
   ```

## Project Structure

```
server/lambda/
├── template.yaml           # SAM template (all Lambda definitions)
├── samconfig.toml          # SAM CLI configuration
├── services/
│   ├── auth/               # Authentication service
│   │   ├── handler.py      # Lambda entry point
│   │   └── requirements.txt
│   ├── kb/                 # Knowledge Base service
│   │   ├── handler.py
│   │   └── requirements.txt
│   ├── curriculum/         # Curriculum service
│   │   ├── handler.py
│   │   └── requirements.txt
│   ├── metrics/            # Metrics service
│   │   ├── handler.py
│   │   └── requirements.txt
│   └── shared/             # Shared utilities
│       ├── __init__.py
│       ├── auth.py         # JWT/token validation
│       ├── db.py           # Database connections
│       ├── response.py     # Standard API responses
│       └── requirements.txt
└── tests/                  # Test files
```

## Local Development

### Start Local API

```bash
cd server/lambda

# Build the Lambda functions
sam build

# Start local API Gateway (port 8766)
sam local start-api --port 8766

# Or with hot reload
sam local start-api --port 8766 --warm-containers EAGER
```

### Test Endpoints

```bash
# Health check
curl http://localhost:8766/api/health

# Login (returns placeholder token)
curl -X POST http://localhost:8766/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Get current user (requires token)
curl http://localhost:8766/api/auth/me \
  -H "Authorization: Bearer <token>"
```

### Environment Variables

For local development, create a `env.json` file:

```json
{
  "AuthFunction": {
    "DATABASE_URL": "postgresql://user:pass@localhost:5432/unamentis",
    "JWT_SECRET": "dev-secret-key",
    "BETA_TOKENS": "uma_beta_test_token",
    "ENVIRONMENT": "dev"
  }
}
```

Then run with:
```bash
sam local start-api --port 8766 --env-vars env.json
```

## Deployment

### Deploy to AWS

```bash
cd server/lambda

# First time (guided)
sam deploy --guided

# Subsequent deployments
sam deploy

# Deploy to specific environment
sam deploy --config-env staging
sam deploy --config-env prod
```

### Configuration

Edit `samconfig.toml` for environment-specific settings:

- **dev**: Fast deploys, no confirmations
- **staging**: Confirmations required
- **prod**: Full confirmations, no rollback disabled

## Services

### Auth Service (11 endpoints)
- `GET /api/health` - Health check
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `POST /api/auth/refresh` - Token refresh
- `POST /api/auth/logout` - User logout
- `GET /api/auth/me` - Get current user
- `POST /api/auth/forgot-password` - Password reset request
- `POST /api/auth/reset-password` - Password reset confirm
- `GET /api/auth/verify-email` - Email verification
- `POST /api/auth/resend-verification` - Resend verification
- `GET /api/auth/sessions` - List sessions
- `DELETE /api/auth/sessions/{sessionId}` - Revoke session

### KB Service (~20 endpoints)
- Question packs CRUD
- Questions CRUD
- Domains management

### Curriculum Service (5 endpoints)
- Curriculum metadata
- Progress tracking

### Metrics Service (5+ endpoints)
- System metrics
- Session analytics
- Usage statistics

## Authentication

### Tier 1: Beta Tokens (Client Auth)
```
Authorization: Bearer uma_beta_2024_xxxxx
```

### Tier 2: JWT (Authenticated Endpoints)
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

### Tier 3: Cloudflare Access (Admin)
Requires CF-Access-Authenticated-User-Email header from Cloudflare Access.

## Testing

```bash
# Invoke a specific function
sam local invoke AuthFunction --event events/login.json

# Run Python tests
cd services
python -m pytest ../tests/
```

## Troubleshooting

### "sam" command not found
```bash
brew install aws-sam-cli
```

### Docker not running
```bash
open -a Docker
# Wait for Docker to start, then retry
```

### Template validation
```bash
sam validate
```

### View logs
```bash
sam logs -n AuthFunction --tail
```
