# CrystalShards Documentation

This directory contains comprehensive documentation for the CrystalShards platform.

## User Guides

**[User Guides](user-guides/)** - Complete guides for using all four CrystalShards platforms

Essential guides for end users:
- [User Guides Index](user-guides/README.md) - Overview of all user guides
- [Ecosystem Overview](user-guides/overview.md) - How all platforms work together

Platform-specific guides:
- [CrystalShards.org User Guide](user-guides/crystalshards.md) - Package registry for Crystal libraries
- [CrystalDocs.org User Guide](user-guides/crystaldocs.md) - Automated documentation hosting
- [CrystalGigs.org User Guide](user-guides/crystalgigs.md) - Job board for Crystal developers
- [CrystalBits.org User Guide](user-guides/crystalbits.md) - Blog and newsletter platform

Whether you're a library author, job seeker, employer, or Crystal developer, these guides will help you get the most out of the ecosystem.

## Table of Contents

- [User Guides](#user-guides)
- [Technical Guides](#technical-guides)
- [API Documentation](#api-documentation)
- [Infrastructure](#infrastructure)

## Technical Guides

### Security

**[Rate Limiting Guide](RATE_LIMITING.md)** - API rate limiting implementation
- Configuration
- Custom rate limits
- Troubleshooting

## API Documentation

API documentation for each application:

- **CrystalShards API**: [docs/api/crystalshards/](api/crystalshards/)
- **CrystalDocs API**: [docs/api/crystaldocs/](api/crystaldocs/)
- **CrystalGigs API**: [docs/api/crystalgigs/](api/crystalgigs/)
- **CrystalBits API**: [docs/api/crystalbits/](api/crystalbits/)

Each API directory contains:
- OpenAPI 3.0 specifications
- Endpoint documentation
- Authentication guides
- Example requests/responses

## Infrastructure

**[Terraform Configuration](../terraform/)** - Infrastructure as Code for the Cloud Run deployment
- Cloud Run services and the documentation build job
- Cloud SQL, Cloud Storage, Cloud Tasks and Secret Manager resources
- The global external Application Load Balancer and the Cloud DNS zones

Applies run in CI. Locally, limit yourself to `terraform fmt`, `terraform init -backend=false`, `terraform validate` and `terraform plan`.

## Architecture

### System Overview

The CrystalShards platform consists of four applications:

1. **CrystalShards.org** - Package registry for Crystal shards
2. **CrystalDocs.org** - Documentation hosting
3. **CrystalGigs.org** - Job board for Crystal developers
4. **CrystalBits.org** - Blog and newsletter platform

### Technology Stack

- **Framework**: Lucky (Crystal web framework)
- **Compute**: Cloud Run services with scale to zero, plus one Cloud Run Job for documentation builds
- **Database**: Cloud SQL for PostgreSQL, one instance holding a database per application
- **Object storage**: Cloud Storage
- **Queue**: Cloud Tasks
- **Secrets**: Secret Manager
- **Edge**: one global external Application Load Balancer with serverless NEGs and Google-managed certificates, with Cloud DNS holding the four zones
- **Observability**: Cloud Logging and Cloud Monitoring

## Contributing

See [CLAUDE.md](../CLAUDE.md) for development guidelines and [PROMPT.md](../PROMPT.md) for project context.

## Getting Help

- **Development setup**: See [DEVELOPMENT.md](../DEVELOPMENT.md)
- **Logs and metrics**: Cloud Logging and Cloud Monitoring in the `crystalshards-org` project

---

Last Updated: 2025-10-09
