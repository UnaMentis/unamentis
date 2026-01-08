# UnaMentis Feature Flag System

Self-hosted feature flag management using [Unleash](https://www.getunleash.io/).

## Quick Start

```bash
# Start all services
cd server/feature-flags
docker compose up -d

# View logs
docker compose logs -f

# Stop services
docker compose down
```

## Access

| Service | URL | Credentials |
|---------|-----|-------------|
| Unleash UI | http://localhost:4242 | admin / unleash4all |
| Unleash API | http://localhost:4242/api | See tokens below |
| Proxy (clients) | http://localhost:3063/proxy | proxy-client-key |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Feature Flag System                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐    │
│   │  Unleash UI │      │   Unleash   │      │  PostgreSQL │    │
│   │   :4242     │◄────►│   Server    │◄────►│   Database  │    │
│   └─────────────┘      └──────┬──────┘      └─────────────┘    │
│                               │                                  │
│                               ▼                                  │
│                        ┌─────────────┐                          │
│                        │   Unleash   │                          │
│                        │    Proxy    │                          │
│                        │   :3063     │                          │
│                        └──────┬──────┘                          │
│                               │                                  │
│              ┌────────────────┼────────────────┐                │
│              ▼                ▼                ▼                │
│        ┌──────────┐    ┌──────────┐    ┌──────────┐            │
│        │ iOS App  │    │ Web App  │    │  Server  │            │
│        └──────────┘    └──────────┘    └──────────┘            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## API Tokens

### Development Tokens (Insecure)

| Token Type | Token | Use Case |
|------------|-------|----------|
| Admin API | `*:*.unleash-insecure-admin-api-token` | Server-side admin operations |
| Client API | `default:development.unleash-insecure-client-token` | Server-side flag evaluation |
| Frontend API | `default:development.unleash-insecure-frontend-token` | Client-side (via proxy) |
| Proxy Client | `proxy-client-key` | iOS/Web apps connecting to proxy |

### Production Tokens

For production, create secure tokens in the Unleash UI:

1. Go to **Admin > API tokens**
2. Create tokens for each environment
3. Update `docker-compose.yml` or use environment variables:
   ```bash
   export UNLEASH_ADMIN_TOKEN="your-secure-admin-token"
   export UNLEASH_CLIENT_TOKEN="your-secure-client-token"
   ```

## Client Integration

### iOS (Swift)

```swift
import UnleashClient

// Initialize
let config = UnleashConfig(
    proxyUrl: "http://localhost:3063/proxy",
    clientKey: "proxy-client-key",
    appName: "UnaMentis-iOS"
)
let unleash = UnleashClient(config: config)

// Check flag
if unleash.isEnabled("new_voice_engine") {
    // Use new voice engine
}

// With context
let context = UnleashContext(userId: "user123")
if unleash.isEnabled("premium_features", context: context) {
    // Show premium features
}
```

### Web (TypeScript)

```typescript
import { UnleashClient } from '@unleash/proxy-client-react';

const unleash = new UnleashClient({
  url: 'http://localhost:3063/proxy',
  clientKey: 'proxy-client-key',
  appName: 'UnaMentis-Web',
});

// Check flag
if (unleash.isEnabled('dark_mode')) {
  enableDarkMode();
}
```

### Server (Python)

```python
from UnleashClient import UnleashClient

client = UnleashClient(
    url="http://localhost:4242/api",
    app_name="UnaMentis-Server",
    custom_headers={"Authorization": "default:development.unleash-insecure-client-token"}
)
client.initialize_client()

if client.is_enabled("maintenance_mode"):
    return {"status": "maintenance"}
```

## Flag Categories

| Category | Lifetime | Auto-merge | Example |
|----------|----------|------------|---------|
| `release` | < 30 days | After rollout | `new_onboarding_flow` |
| `experiment` | < 60 days | After analysis | `ab_test_pricing` |
| `ops` | Long-lived | N/A | `maintenance_mode` |
| `permission` | Permanent | N/A | `admin_access` |

## Flag Lifecycle

### Creating a Flag

1. **Register in database** (for lifecycle tracking):
   ```sql
   SELECT register_flag(
       'my_new_feature',           -- flag name
       'github_username',          -- owner
       'Description of feature',   -- description
       'release',                  -- category
       30                          -- days until target removal
   );
   ```

2. **Create in Unleash UI**:
   - Go to http://localhost:4242
   - Click "New feature toggle"
   - Use the same name as registered
   - Configure activation strategy

### Flag Naming Convention

```
<scope>_<feature>_<variant?>

Examples:
- voice_new_engine
- ui_dark_mode
- ab_pricing_variant_a
- ops_maintenance_mode
```

### Reviewing Flags

```sql
-- View flags needing attention
SELECT * FROM flags_needing_review;

-- Mark a flag as reviewed
SELECT review_flag('my_feature', 'Reviewed, extending 2 weeks', 14);
```

### Removing a Flag

1. Set flag to 100% rollout in Unleash
2. Remove flag checks from code
3. Delete flag from Unleash UI
4. Delete metadata: `DELETE FROM flag_metadata WHERE flag_name = 'my_feature';`

## Monitoring

### Flag Usage Stats

The `flag_usage_stats` table tracks aggregated usage:

```sql
-- Usage over last 7 days
SELECT
    flag_name,
    SUM(evaluation_count) as total_evals,
    SUM(true_count) as true_evals,
    SUM(unique_users) as unique_users
FROM flag_usage_stats
WHERE date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY flag_name
ORDER BY total_evals DESC;
```

### Health Checks

```bash
# Unleash server
curl http://localhost:4242/health

# Proxy
curl http://localhost:3063/proxy/health

# All flags for a user
curl -H "Authorization: proxy-client-key" \
     "http://localhost:3063/proxy?userId=test-user"
```

## Backup & Recovery

### Backup Database

```bash
docker compose exec postgres pg_dump -U unleash unleash > backup.sql
```

### Restore Database

```bash
docker compose exec -T postgres psql -U unleash unleash < backup.sql
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs
docker compose logs unleash
docker compose logs postgres

# Reset everything (data loss!)
docker compose down -v
docker compose up -d
```

### Flags Not Updating

1. Check proxy refresh interval (default 5s)
2. Verify proxy can reach Unleash: `docker compose logs unleash-proxy`
3. Check client is using correct token

### Database Connection Issues

```bash
# Test connection
docker compose exec postgres psql -U unleash -c "SELECT 1"

# Check postgres logs
docker compose logs postgres
```

## Production Considerations

### Security

- [ ] Replace all insecure tokens with secure ones
- [ ] Enable HTTPS (use reverse proxy like nginx)
- [ ] Restrict network access to Unleash UI
- [ ] Enable audit logging
- [ ] Set up SSO/OIDC authentication

### High Availability

- [ ] Run multiple Unleash instances behind load balancer
- [ ] Use managed PostgreSQL (RDS, Cloud SQL)
- [ ] Deploy proxy in multiple regions
- [ ] Set up monitoring and alerting

### Commercial Upgrade

When ready for enterprise features, consider upgrading to:

| Feature | Open Source | LaunchDarkly | Benefit |
|---------|-------------|--------------|---------|
| Hosting | Self-hosted | Managed | Zero maintenance |
| SDKs | Community | Official | Better support |
| Analytics | Basic | Advanced | Experimentation |
| Support | Community | Enterprise | SLA, dedicated |

Estimated cost: ~$75-150/month for small team
