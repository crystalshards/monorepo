# CrystalShards Autonomous Development

An autonomous agent that builds CrystalShards.org and CrystalDocs.org - a comprehensive Crystal language package registry and documentation platform.

## Quick Start

Local development needs Crystal, Docker and docker compose. It needs no Google Cloud account, credentials or cloud access of any kind.

```bash
# Start the local Postgres the apps develop against
docker compose up -d postgres

# Install dependencies, create the databases, migrate and load sample data
# (this also starts the object storage and mail containers)
make setup

# Run all four apps. Any missing binary is built first.
make dev
```

`make dev` serves:

- crystalshards: http://localhost:3000
- crystaldocs: http://localhost:3001
- crystalgigs: http://localhost:3002
- crystalbits: http://localhost:3003

`make dev` only builds what is missing, so run `make build` yourself after changing an app's source. `make help` lists every target. See `DEVELOPMENT.md` and `CONTRIBUTING.md` for the longer version.

## Philosophy

Following the "less is more" approach - a simple prompt drives continuous development with frequent commits.

## What It Builds

1. **CrystalShards.org** - Package registry like rubygems.org
2. **CrystalDocs.org** - Documentation platform like docs.rs
3. **CrystalGigs.com** - Job board for Crystal developers
4. **CrystalBits.org** - Newsletter/blog platform

Features:

- Full-text search, dependency graphs, download stats
- Automated documentation generation, queued and built out of band
- Untrusted shard code compiles in an isolated build job whose service account holds no IAM bindings
- Services scale to zero when idle

## Files

- `PROMPT.md` - Simple prompt that guides the agent
- `dev-agent/loop` - Continuous loop: pull, feed the prompt to Claude Code, wait for CI, repeat
- `dev-agent/wait-for-ci` - Blocks until every GitHub Actions run for the current commit finishes
- `.agent/post-event-reviews/` - Write-ups of past incidents
- `CLAUDE.md` - Development guidelines

## Architecture

```
/apps/crystalshards     - Main registry (Lucky app)
/apps/crystaldocs       - Documentation platform (Lucky app)
/apps/crystalgigs       - Job board (Lucky app)
/apps/crystalbits       - Newsletter/blog (Lucky app)
/libraries              - Shared models, migrations and helpers
/terraform              - Infrastructure as code for the Cloud Run platform
/.github/workflows      - CI/CD pipelines
```

## Platform

Project `crystalshards-org`, region `us-central1`. Deploys run in CI, never from a workstation.

- **Compute**: Cloud Run services `crystalshards`, `crystaldocs`, `crystalgigs`, `crystalbits` and `docs-launcher`, all scaling to zero
- **Database**: One Cloud SQL PostgreSQL instance, `crystal-postgres`, with a database per app, reached over the Cloud SQL unix socket. Each service caps `max_pool_size` at 5 so four autoscaling services cannot exhaust a small instance
- **Object storage**: Cloud Storage buckets `crystalshards-docs` for built documentation and `crystalshards-packages`
- **Documentation builds**: The `docs-builds` Cloud Tasks queue posts to `docs-launcher`, which starts a `docs-build` job execution. The job gets its input by signed GET URL and writes its output by signed PUT URL, so the untrusted compile holds no credentials
- **Images**: Artifact Registry repository `docker-images`, published as `us-central1-docker.pkg.dev/crystalshards-org/docker-images/<app>:<sha>`
- **Edge**: One global external Application Load Balancer with serverless NEGs and Google-managed certificates, serving apex and www for all four domains. Cloud DNS holds the zones
- **Secrets**: Secret Manager, referenced by Cloud Run as environment variables. Missing required production config fails closed at boot and names the variable
- **Observability**: Cloud Logging and Cloud Monitoring

Locally, docker compose stands in for all of it: Postgres for the databases, a local object store, and an in-process queue instead of Cloud Tasks.

## Autonomous Agent

`dev-agent/loop` runs inside the dev container. Each pass pulls `main`, feeds `PROMPT.md` to Claude Code, then calls `dev-agent/wait-for-ci`, which blocks on every workflow run for the new commit and exits non-zero if any of them fail.

## Development Approach

The agent:

1. Commits after EVERY file edit
2. Self-regulates scope
3. Pushes to GitHub regularly
4. Creates PRs when features are complete
5. Writes a post event review after an incident

## Requirements

Local development:

- Crystal and Node, pinned in `.mise.toml` and installed with `mise install`
- Docker and docker compose
- No Google Cloud account or credentials

Running the agent also needs:

- Claude API key
- GitHub token with repo permissions
- GitHub repository configured (see GITHUB_SETUP.md)

## Cost Control

- Cloud Run scales to zero, so idle services cost nothing
- One Cloud SQL instance serves all four apps
- One load balancer fronts every hostname instead of one per app
- Documentation builds run as a job only when work is queued
- Built docs and packages sit in Cloud Storage rather than an always-on service

## GitHub Setup Required

See `GITHUB_SETUP.md` for required:

- Repository secrets
- Service account setup
- Branch protection rules
- GitHub environments
- Container registry access
