# CodeRabbit AI Code Review Setup

CodeRabbit provides AI-powered code reviews on every pull request, catching issues that humans often miss.

**Cost for UnaMentis: FREE** (Pro features for open source projects)

## Quick Start (2 minutes)

### Step 1: Install from GitHub Marketplace

1. Go to [CodeRabbit on GitHub Marketplace](https://github.com/marketplace/coderabbitai)
2. Click "Set up a plan"
3. Select "Open Source" (free)
4. Choose "Only select repositories"
5. Select the `unamentis` repository
6. Click "Install"

### Step 2: Verify Installation

Open any PR in the repository. CodeRabbit will automatically:
- Post a summary of the changes
- Provide line-by-line review comments
- Suggest improvements with one-click apply

### Step 3: (Optional) Add to Android Repository

Repeat Step 1 for the Android client repository to get reviews there too.

## What CodeRabbit Reviews

Our configuration (`.coderabbit.yaml`) provides specialized review instructions for:

| File Type | Focus Areas |
|-----------|-------------|
| Swift (`.swift`) | Actor isolation, Sendable, retain cycles, performance |
| Python (`.py`) | Async patterns, type hints, security, validation |
| TypeScript (`.ts/.tsx`) | React hooks, SSR boundaries, accessibility |
| Workflows (`.yml`) | Action pinning, permissions, secrets |

## Interacting with CodeRabbit

### In PR Comments

Ask questions or request changes:
```
@coderabbitai Can you explain this change?
@coderabbitai Generate unit tests for this function
@coderabbitai Add docstrings to these methods
```

### Applying Suggestions

When CodeRabbit suggests a fix:
1. Click "Apply suggestion" to commit the change directly
2. Or click "Dismiss" if the suggestion doesn't apply

### Re-requesting Review

If you push new commits:
```
@coderabbitai review
```

Or for a full re-review:
```
@coderabbitai full review
```

## Configuration

The configuration file is at `.coderabbit.yaml` in the repository root.

### Key Settings

```yaml
reviews:
  profile: assertive        # Catches more issues (vs chill/default)
  drafts: true              # Review draft PRs early
  sequence_diagrams: true   # Generate diagrams for complex changes
  request_changes_workflow: true  # Block on high-severity issues
```

### Path-Specific Instructions

We've configured custom review rules per file type. See `.coderabbit.yaml` for details.

### Modifying Configuration

Edit `.coderabbit.yaml` and commit. Changes take effect on the next PR.

## Rate Limits (Open Source)

| Resource | Limit |
|----------|-------|
| Files reviewed | 200/hour |
| Reviews | 3 back-to-back, then 4/hour |
| Chat messages | 25 back-to-back, then 50/hour |

These limits are per-developer, per-repository. More than sufficient for our team size.

## Best Practices

### 1. Review the Review

CodeRabbit is an assistant, not a replacement for human review. Always:
- Read the AI's suggestions critically
- Apply suggestions that make sense
- Dismiss suggestions that don't fit the context

### 2. Teach CodeRabbit

When dismissing suggestions, explain why:
```
@coderabbitai This is intentional because [reason]
```

CodeRabbit learns from these interactions (knowledge_base setting).

### 3. Use for Complex PRs

Especially valuable for:
- Large refactors
- Security-sensitive changes
- Performance-critical code
- New team members' PRs

### 4. Don't Skip Human Review

CodeRabbit catches different issues than humans. Use both:
- CodeRabbit: Syntax, patterns, security, consistency
- Humans: Architecture, business logic, user experience

## Troubleshooting

### CodeRabbit Not Reviewing

1. Check installation: Settings > Integrations > Applications
2. Verify repository access is granted
3. Check if PR is to a configured base branch (`main` or `rea/main-dev`)

### Too Many Comments

Adjust the profile in `.coderabbit.yaml`:
```yaml
reviews:
  profile: chill  # Less aggressive (default is "assertive")
```

### Ignoring Specific Files

Add to `.coderabbit.yaml`:
```yaml
reviews:
  path_filters:
    - "!**/generated/**"
    - "!**/vendor/**"
```

## Integration with CI

CodeRabbit reviews are informational by default. To block merging on CodeRabbit issues:

1. Go to repository Settings > Branches > Branch protection
2. Add "coderabbitai" to required status checks

**Recommendation**: Start without blocking, enable after team is comfortable.

## Resources

- [CodeRabbit Documentation](https://docs.coderabbit.ai/)
- [Configuration Reference](https://docs.coderabbit.ai/guides/configure-coderabbit)
- [GitHub Integration Guide](https://docs.coderabbit.ai/platforms/github-com)
- [CodeRabbit Discord](https://discord.gg/coderabbit) (community support)

## Cost Summary

| Repository Type | Cost | Features |
|-----------------|------|----------|
| Public (open source) | **FREE** | Full Pro features |
| Private | $24-30/seat/month | Full Pro features |

UnaMentis repositories are public = **$0/month for unlimited AI code reviews**.
