# UnaMentis DevLake - DORA Metrics

Engineering metrics and insights using [Apache DevLake](https://devlake.apache.org/).

## Quick Start

```bash
cd server/devlake
docker compose up -d
```

## Access

| Service | URL | Credentials |
|---------|-----|-------------|
| Config UI | http://localhost:4000 | - |
| Grafana | http://localhost:3002 | admin / admin |
| DevLake API | http://localhost:8080 | - |

## DORA Metrics

DevLake collects and calculates the four key DORA metrics:

### 1. Deployment Frequency
**How often code is deployed to production**

| Level | Frequency |
|-------|-----------|
| Elite | Multiple deploys per day |
| High | Between once per day and once per week |
| Medium | Between once per week and once per month |
| Low | Less than once per month |

### 2. Lead Time for Changes
**Time from commit to production deployment**

| Level | Time |
|-------|------|
| Elite | Less than one hour |
| High | Between one day and one week |
| Medium | Between one week and one month |
| Low | More than one month |

### 3. Change Failure Rate
**Percentage of deployments causing failures**

| Level | Rate |
|-------|------|
| Elite | 0-15% |
| High | 16-30% |
| Medium | 31-45% |
| Low | > 45% |

### 4. Mean Time to Recovery (MTTR)
**Time to recover from production incidents**

| Level | Time |
|-------|------|
| Elite | Less than one hour |
| High | Less than one day |
| Medium | Between one day and one week |
| Low | More than one week |

## Setup Guide

### 1. Start Services

```bash
docker compose up -d

# Wait for services to be healthy
docker compose ps
```

### 2. Configure GitHub Connection

1. Open Config UI: http://localhost:4000
2. Go to **Connections** > **Add Connection** > **GitHub**
3. Enter:
   - Connection Name: `UnaMentis GitHub`
   - Endpoint: `https://api.github.com/`
   - Token: Your GitHub Personal Access Token

**Required Token Scopes:**
- `repo` (Full control of private repositories)
- `read:org` (Read org and team membership)
- `read:user` (Read user profile data)

### 3. Create Blueprint

1. Go to **Blueprints** > **Create Blueprint**
2. Select **GitHub** connection
3. Choose the `unamentis` repository
4. Configure transformation rules:
   - Deployment pattern: `^deploy|release`
   - Production branch: `^main$`
5. Set schedule: Daily at midnight

### 4. Run Initial Collection

1. Go to **Blueprints**
2. Click **Run Now** on your blueprint
3. Wait for data collection (may take 5-30 minutes)

### 5. View Dashboards

1. Open Grafana: http://localhost:3002
2. Navigate to **Dashboards** > **DORA**
3. Select time range (last 30 days recommended)

## Custom Dashboards

The `dashboards/` directory contains custom Grafana dashboards:

- **unamentis-quality.json**: Combined DORA + quality metrics

To add custom dashboards:
1. Create JSON file in `dashboards/`
2. Restart Grafana: `docker compose restart grafana`

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       DevLake Architecture                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────┐                    ┌──────────────┐          │
│   │  Config UI   │ ─── manages ────► │   DevLake    │          │
│   │   :4000      │                    │   Server     │          │
│   └──────────────┘                    └──────┬───────┘          │
│                                              │                   │
│                     ┌────────────────────────┼─────────────┐    │
│                     │                        │             │    │
│                     ▼                        ▼             ▼    │
│              ┌──────────┐            ┌──────────┐  ┌──────────┐ │
│              │  GitHub  │            │  MySQL   │  │ Grafana  │ │
│              │   API    │            │  :3306   │  │  :3002   │ │
│              └──────────┘            └──────────┘  └──────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Data Model

DevLake normalizes data from GitHub into a standard model:

| Table | Description |
|-------|-------------|
| `repos` | Repository metadata |
| `pull_requests` | PR data with metrics |
| `commits` | Commit history |
| `issues` | Issue tracking |
| `cicd_pipelines` | CI/CD runs |
| `cicd_deployments` | Production deployments |

## Troubleshooting

### Services Won't Start

```bash
# Check logs
docker compose logs devlake
docker compose logs mysql

# Reset everything
docker compose down -v
docker compose up -d
```

### No Data in Dashboards

1. Check blueprint status in Config UI
2. Verify GitHub token has correct permissions
3. Check DevLake logs for API errors
4. Ensure time range includes data period

### Slow Data Collection

- GitHub API rate limits: 5000 requests/hour
- Large repos take longer on first sync
- Check progress in Config UI pipeline view

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MYSQL_ROOT_PASSWORD` | admin | MySQL root password |
| `MYSQL_PASSWORD` | merico | DevLake MySQL user password |
| `GRAFANA_PASSWORD` | admin | Grafana admin password |

For production, set these in a `.env` file:

```bash
MYSQL_ROOT_PASSWORD=secure_root_pass
MYSQL_PASSWORD=secure_merico_pass
GRAFANA_PASSWORD=secure_grafana_pass
```

## Production Considerations

### Security
- [ ] Change default passwords
- [ ] Enable HTTPS (reverse proxy)
- [ ] Restrict network access
- [ ] Use GitHub App instead of PAT

### High Availability
- [ ] Use managed MySQL (RDS, Cloud SQL)
- [ ] Configure backup strategy
- [ ] Set up monitoring/alerting

### Commercial Alternative

For managed DORA metrics with zero maintenance:

| Feature | DevLake | LinearB |
|---------|---------|---------|
| Hosting | Self-hosted | Managed |
| Setup | Manual | Automatic |
| Support | Community | Enterprise |
| Cost | Free | ~$200/month |

## Related Documentation

- [Apache DevLake Docs](https://devlake.apache.org/docs/Overview/Introduction)
- [DORA Metrics Guide](https://dora.dev/)
- [QUALITY_INFRASTRUCTURE_PLAN.md](../../docs/QUALITY_INFRASTRUCTURE_PLAN.md)
