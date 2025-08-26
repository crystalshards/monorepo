# CrystalShards Development Guide

## Overview

This monorepo contains three Crystal applications:

1. **CrystalShards Registry** (`apps/shards-registry`) - Package registry at `:3000`
2. **CrystalDocs** (`apps/shards-docs`) - Documentation platform at `:3001`  
3. **CrystalGigs** (`apps/gigs`) - Job board at `:3002`
4. **Worker** (`apps/worker`) - Background job processor

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

## Services

- **Registry**: http://localhost:3000
- **Docs**: http://localhost:3001  
- **Gigs**: http://localhost:3002
- **MailHog**: http://localhost:8025
- **MinIO**: http://localhost:9001

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Registry      │    │      Docs       │    │      Gigs       │
│    :3000        │    │     :3001       │    │     :3002       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
         ┌─────────────────┬─────┴─────┬─────────────────┐
         │                 │           │                 │
   ┌─────────┐       ┌──────────┐  ┌────────┐      ┌──────────┐
   │PostgreSQL│       │  Redis   │  │ MinIO  │      │ MailHog  │
   │  :5432  │       │  :6379   │  │ :9000  │      │  :1025   │
   └─────────┘       └──────────┘  └────────┘      └──────────┘
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

The worker processes background jobs including:
- Documentation generation
- Shard indexing  
- Search index updates
- Email notifications
- Health checks

## Testing

Each app has its own test suite:
```bash
cd apps/shards-registry && crystal spec
cd apps/shards-docs && crystal spec  
cd apps/gigs && crystal spec
cd apps/worker && crystal spec
```

## Deployment

All applications are containerized and ready for Kubernetes deployment.

See `terraform/` directory for infrastructure setup.

## Contributing

1. Follow Crystal style guide
2. Run tests and linter before committing
3. Keep commits atomic and well-documented
4. Update documentation for new features