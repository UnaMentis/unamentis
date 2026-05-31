# Contributing to UnaMentis

This repository holds the server infrastructure, curriculum system, and
project-wide documentation. The client applications live in their own
repositories: contribute iOS changes in
[unamentis-ios](https://github.com/UnaMentis/unamentis-ios) and Android changes
in [unamentis-android](https://github.com/UnaMentis/unamentis-android).

## Components and their stacks

| Component | Location | Stack | Lint / Format | Tests |
|-----------|----------|-------|---------------|-------|
| Management API | `server/management/` | Python 3, aiohttp | Ruff | `python -m pytest` |
| USM Core | `server/usm-core/` | Rust | Clippy, rustfmt | `cargo test` |
| Operations Console | `server/web/` | Next.js, TypeScript | ESLint, Prettier | `pnpm test` |
| Web Client | `server/web-client/` | Next.js, TypeScript | ESLint, Prettier | `pnpm test` |
| Importers | `server/importers/` | Python | Ruff | `python -m pytest` |
| Curriculum | `curriculum/` | UMCF JSON | JSON Schema validation | schema validation |

## CI/CD requirements

Pull requests to `main` must pass the relevant workflow checks before merging:

| Workflow | Scope |
|----------|-------|
| `server.yml` | Python lint (Ruff), tests, coverage |
| `web-client.yml` | Lint, typecheck, build, tests |
| `security.yml` | Secret scan (gitleaks), CodeQL, dependency audit |
| `docs-validation.yml` | Documentation, YAML, and JSON validation |

### Branch protection

The `main` branch is protected: required status checks, at least one approving
review from a CODEOWNER, dismissal of stale reviews, conversation resolution,
and no force pushes or deletions.

## Development workflow

### Branch strategy

```
main
  ↓
feature/your-feature   (or fix/*, refactor/*, docs/*, perf/*, ci/*, chore/*)
```

- `main` is production-ready; all work branches off `main` and is merged back via PR.

### Steps

1. Create a branch off `main`:
   ```bash
   git checkout main && git pull origin main
   git checkout -b feature/your-feature
   ```
2. Make your change with tests (see Testing below).
3. Validate locally before opening a PR:
   ```bash
   /validate            # lint + quick tests (Definition of Done)
   /validate --full     # for significant changes
   ```
4. Push and open a PR against `main`. Address review feedback and get approval.

> Commit policy: contributors commit their own work. Automated agents in this
> repo stage changes only; humans create the commits to preserve attribution.

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <description>

[optional body]
[optional footer]
```

Types: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `perf:`, `ci:`, `chore:`.

Examples:
```
feat: add Deepgram STT streaming to the importer pipeline
fix: seed rate-limiter buckets full so the first request is allowed
docs: refresh PROJECT_OVERVIEW for the multi-repo layout
test: add default-deny assertions for the auth middleware
```

## Code style

Run the language-appropriate tools (or `./scripts/format.sh` and
`./scripts/lint.sh` as aggregates):

- Python: Ruff for lint and format. No bare `except`; return generic error
  responses to clients and log details server-side; use parameterized SQL.
- Rust: `cargo fmt` and `cargo clippy -- -D warnings` (zero warnings).
- TypeScript: ESLint + Prettier; strict mode; avoid `any`.

Writing style for docs and comments: no em or en dashes as sentence
interrupters; use commas and periods. Be concise and direct.

## Testing

This project follows a "Real Over Mock" philosophy: only paid external APIs
(LLM, STT, TTS, embeddings) are mocked. Use real implementations with fixtures
for internal services. See `AGENTS.md` for details.

```bash
# Python (Management API / importers)
cd server/management && python -m pytest
cd server/importers && python -m pytest

# Rust (USM Core)
cd server/usm-core && cargo test

# Web (Operations Console / Web Client)
cd server/web && pnpm test
cd server/web-client && pnpm test
```

- New features: add tests. Bug fixes: add a regression test. Refactors: keep
  existing tests green.
- Security-relevant behavior (auth, access control, input validation) should
  have explicit tests that assert the secure outcome.

### Server changes: restart and verify

Server code changes only take effect after a restart. After changing a server,
restart it via the `/service` skill (never `pkill`) and verify against the
running stack:

```
/service restart management-api
/service status
```

A server change is not complete until it has been restarted and verified.

## Pull request process

Use the PR template. Reviews check correctness, tests, architecture
(separation of concerns, no tight coupling), performance (latency targets, no
leaks), and that no secrets or credentials are introduced.

## Running the web interfaces locally

| Interface | Port | Purpose |
|-----------|------|---------|
| Operations Console | 3000 | System health, services, logs |
| Management API | 8766 | Curriculum, users, progress, TTS cache |
| Web Client | 3001 | Browser voice learning |

```bash
# Management API (Python). Binds 127.0.0.1 by default.
cd server/management && python server.py

# Operations Console (Next.js)
cd server/web && pnpm install && pnpm dev
```

## Reporting issues

Use the issue templates. Include the component, OS, runtime version, and
version/commit. For iOS or Android client bugs, file in the respective client
repository.

## Code of Conduct

Be respectful, collaborative, constructive, and inclusive. See
[CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md).

## Questions

Open a GitHub Discussion, check existing Issues, or review the documentation in
`docs/`.

---

Thank you for contributing to UnaMentis.
