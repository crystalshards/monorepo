# CrystalShards Development Guide

## Overview

This monorepo contains four Lucky framework applications:

1. **CrystalShards** (`apps/crystalshards`) - Package registry with background workers
2. **CrystalDocs** (`apps/crystaldocs`) - Documentation hosting platform
3. **CrystalGigs** (`apps/crystalgigs`) - Job board for Crystal developers
4. **CrystalBits** (`apps/crystalbits`) - Newsletter/blog platform

## Quick Start

```bash
# Clone and setup
git clone <repository-url>
cd monorepo

# Setup development environment
make setup
# Edit .env with your configuration

# Start all services
make dev
```

Local development runs entirely on docker-compose: four Lucky apps on ports 3000 to 3003, PostgreSQL in a container, object storage in a container, and an in-process job queue. No Google Cloud credentials are needed.

## Services

- **Registry**: http://localhost:3000
- **Docs**: http://localhost:3001
- **Gigs**: http://localhost:3002
- **Bits**: http://localhost:3003
- **MailHog**: http://localhost:8025
- **Object storage console**: http://localhost:9001 (MinIO, local development only; production uses Cloud Storage)

## Architecture

```
┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐
│ Registry  │ │   Docs    │ │   Gigs    │ │   Bits    │
│   :3000   │ │   :3001   │ │   :3002   │ │   :3003   │
└───────────┘ └───────────┘ └───────────┘ └───────────┘
      │             │             │             │
      └─────────────┴──────┬──────┴─────────────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
   ┌────────────┐   ┌────────────┐   ┌────────────┐
   │ PostgreSQL │   │Object Store│   │  MailHog   │
   │   :5432    │   │   :9000    │   │   :1025    │
   └────────────┘   └────────────┘   └────────────┘
```

## Development Commands

```bash
make help          # Show all commands
make setup         # Initial setup
make dev           # Start development environment
make test          # Run all tests
make lint          # Run linter
make format        # Format code
make build         # Build applications
make clean         # Clean up
```

## Database

Migrations are in `libraries/migrations/` and run automatically on startup.

Connect to database:

```bash
make db-console
```

## Background Jobs

Job classes live in `apps/crystalshards/src/workers/`:

- Documentation builds
- Shard discovery
- Shard indexing
- Dependency updates

Locally the queue runs in process, so `make dev` is all you need. In production a documentation build is enqueued on the Cloud Tasks queue `docs-builds`, which calls the `docs-launcher` service, which starts a `docs-build` Cloud Run Job execution.

## Testing

Run every suite with `make test`, or one app directly:

```bash
cd apps/crystalshards
export PKG_CONFIG_PATH=/opt/homebrew/opt/openssl@3/lib/pkgconfig:$PKG_CONFIG_PATH
DATABASE_URL="postgresql://postgres:password@localhost:5432/crystalshards_test" crystal spec
```

Swap `crystalshards` for `crystaldocs`, `crystalgigs` or `crystalbits`.

## Deployment

Every application is containerized and runs on Cloud Run in the `crystalshards-org` project, region `us-central1`. Images live in Artifact Registry at `us-central1-docker.pkg.dev/crystalshards-org/docker-images/<app>:<sha>`.

Deploys and `terraform apply` run in CI, never from a workstation. The `terraform/` directory holds the infrastructure definition; locally, limit yourself to `terraform fmt`, `terraform init -backend=false`, `terraform validate` and `terraform plan`.

## Contributing

1. Follow Crystal style guide
2. Run tests and linter before committing
3. Keep commits atomic and well-documented
4. Update documentation for new features
