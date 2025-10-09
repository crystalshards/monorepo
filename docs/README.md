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
- [Operational Documentation](#operational-documentation)
- [Technical Guides](#technical-guides)
- [API Documentation](#api-documentation)
- [Infrastructure](#infrastructure)

## Operational Documentation

### Runbooks

**[Operational Runbooks](runbooks/)** - Step-by-step incident response procedures

Essential runbooks for on-call engineers:
- [Runbook Index](runbooks/README.md) - Complete list of all runbooks
- [Quick Reference Guide](runbooks/QUICK_REFERENCE.md) - Common commands and patterns
- [On-Call Guide](runbooks/ON_CALL_GUIDE.md) - On-call responsibilities and procedures

Key incident runbooks:
- Application Issues: [High Error Rate](runbooks/app-high-error-rate.md), [High Latency](runbooks/app-high-latency.md), [Unavailable](runbooks/app-unavailable.md)
- Database Issues: [High Connections](runbooks/postgres-high-connections.md), [Replication Lag](runbooks/postgres-replication-lag.md), [Unavailable](runbooks/postgres-unavailable.md)
- Infrastructure: [Pod Crash Loop](runbooks/pod-crash-loop.md), [Ingress Issues](runbooks/ingress-issues.md), [Certificate Expiry](runbooks/certificate-expiry.md)

## Technical Guides

### Observability

**[Logging Guide](LOGGING.md)** - Centralized logging with Loki and Promtail
- Architecture overview
- Log query examples
- Troubleshooting procedures
- Performance optimization

**[Log Query Examples](../terraform/modules/operators/LOG_QUERIES.md)** - 50+ LogQL query patterns
- Application logs
- Error tracking
- Performance monitoring
- Security queries

### Security

**[Rate Limiting Guide](RATE_LIMITING.md)** - API rate limiting implementation
- Configuration
- Redis backend
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

**[Deployment Runbook](../terraform/DEPLOYMENT_RUNBOOK.md)** - Complete deployment procedures
- Prerequisites
- Terraform workflow
- Deployment steps
- Verification
- Troubleshooting
- Rollback procedures

**[Terraform Documentation](../terraform/)** - Infrastructure as Code
- Module structure
- GKE cluster configuration
- Operator deployments
- Application resources

## Architecture

### System Overview

The CrystalShards platform consists of four applications:

1. **CrystalShards.org** - Package registry for Crystal shards
2. **CrystalDocs.org** - Documentation hosting
3. **CrystalGigs.org** - Job board for Crystal developers
4. **CrystalBits.org** - Blog and newsletter platform

### Technology Stack

- **Framework**: Lucky (Crystal web framework)
- **Database**: CloudNativePG (PostgreSQL operator)
- **Cache/Queue**: Redis operator
- **Storage**: MinIO operator
- **Ingress**: Envoy Gateway (Kubernetes Gateway API)
- **Monitoring**: Prometheus + Grafana
- **Logging**: Loki + Promtail
- **Platform**: GKE Autopilot

### Namespaces

- `crystalshards` - Main package registry
- `crystaldocs` - Documentation hosting
- `crystalgigs` - Job board
- `crystalbits` - Blog platform
- `infrastructure` - Shared services (Redis, MinIO, PostgreSQL operators)
- `monitoring` - Prometheus, Grafana, Loki
- `envoy-gateway-system` - Ingress gateway

## Contributing

See [CLAUDE.md](../CLAUDE.md) for development guidelines and [PROMPT.md](../PROMPT.md) for project context.

## Getting Help

- **On-Call**: Follow [On-Call Guide](runbooks/ON_CALL_GUIDE.md)
- **Incidents**: Check [Runbook Index](runbooks/README.md)
- **Quick Commands**: See [Quick Reference](runbooks/QUICK_REFERENCE.md)
- **Logs**: Review [Logging Guide](LOGGING.md)

---

Last Updated: 2025-10-09
