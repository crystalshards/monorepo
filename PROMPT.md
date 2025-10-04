# CrystalShards Development

Build the Crystal language ecosystem infrastructure:

1. **crystalshards.org** - Package registry (like hex.pm / rubygems.org)
2. **crystaldocs.org** - Documentation hosting (like hexdocs.pm)
3. **crystalgigs.com** - Job board (like elixirdevs.com)
4. **crystalbits.org** - Newsletter/blog

## Current State

See `terraform/.agent/STATUS.md` for complete status.

**TL;DR**: Infrastructure 85% done, but 0% deployable (missing Deployments, Services, Databases, Secrets).

## Architecture

### Monorepo Structure
```
apps/
  crystalshards/      # Package registry (Lucky app + JoobQ workers)
  crystaldocs/        # Documentation hosting (Lucky app)
  crystalgigs/        # Job board (Lucky app)
  crystalbits/        # Newsletter/blog (Lucky app)
  */terraform/        # App-specific K8s resources (namespace, ingress, deployment, etc)
terraform/
  modules/
    networking/       # VPC, subnets, NAT
    cluster/          # GKE Autopilot
    operators/        # cert-manager, CNPG, Redis, MinIO, Prometheus
    ingress/          # Traefik + external-dns
    applications/     # Orchestrates apps/*/terraform modules
.github/workflows/    # CI/CD
```

### Technology Stack
- **Framework**: Lucky (Crystal web framework)
- **Database**: CloudNativePG (in-cluster PostgreSQL operator)
- **Cache/Queue**: Redis operator (in-cluster)
- **Storage**: MinIO operator (for packages & docs)
- **Jobs**: JoobQ (background workers in crystalshards)
- **Ingress**: Traefik
- **Platform**: GKE Autopilot
- **IaC**: Terraform (one resource per file)

### Kubernetes Namespaces
- `crystalshards` - Package registry app
- `crystaldocs` - Documentation app
- `crystalgigs` - Job board app
- `crystalbits` - Newsletter app
- `infrastructure` - Shared operators (cert-manager, CNPG, Redis, MinIO, Prometheus)
- `traefik-system` - Ingress controller

## Critical Deployment Blockers

**Cannot deploy until these exist:**

Each app needs:
- [ ] `resource.kubernetes_deployment.<app>_api.tf` - API server pods
- [ ] `resource.kubernetes_service.<app>.tf` - Service to expose pods
- [ ] `resource.kubectl_manifest.<app>_postgres.tf` - PostgreSQL cluster (CNPG)
- [ ] `resource.kubernetes_secret.<app>_secrets.tf` - DATABASE_URL, REDIS_URL, SECRET_KEY_BASE

Shared:
- [ ] Redis cluster in infrastructure namespace
- [ ] MinIO tenant for package/doc storage

**Reference existing patterns:**
- `apps/crystalshards/terraform/resource.kubernetes_deployment.crystalshards_worker.tf` - Worker deployment example
- `apps/crystalshards/terraform/resource.kubernetes_ingress_v1.crystalshards.tf` - Ingress example
- `terraform/modules/operators/` - Operator examples

## Background Workers (crystalshards only)

JoobQ workers in `apps/crystalshards/src/workers/`:
- **IndexShardWorker** - Parse shard.yml, extract metadata, update search index
- **BuildDocsWorker** - Run `crystal docs` in sandbox, upload to MinIO
- **UpdateDependenciesWorker** - Update dependency graph

Worker deployment separate from API deployment (scales independently).

## Next Tasks

**Phase 1: Make Deployable** (current focus)
1. Create deployments for all 4 apps
2. Create services for all 4 apps
3. Create PostgreSQL clusters for all 4 apps
4. Create shared Redis cluster
5. Create secrets for all 4 apps
6. Test `terraform plan` succeeds

**Phase 2: Implement crystalshards**
1. Models: Shard, ShardVersion, Dependency, Download, Owner
2. Migrations for database schema
3. API endpoints: GET /shards, POST /shards, GET /shards/:name
4. Worker implementation (actual indexing logic)
5. MinIO integration for package storage

**Phase 3: Implement crystaldocs**
1. Fetch/serve docs from MinIO
2. Version switcher UI
3. Search within docs

**Phase 4: Other Apps**
1. crystalgigs MVP (post jobs, browse jobs)
2. crystalbits MVP (blog posts, newsletter)

## Important Conventions

### Terraform
- One resource per file: `resource.<type>.<name>.tf`
- Module files: `module.<name>.tf`
- All apps reference their namespace: `kubernetes_namespace.<app>.metadata[0].name`

### GKE Autopilot Requirements
All pods MUST have resource requests/limits:
```hcl
resources {
  requests = {
    cpu    = "250m"
    memory = "512Mi"
  }
  limits = {
    cpu    = "1000m"
    memory = "2Gi"
  }
}
```

### Environment Variables (Lucky apps)
Required:
- `LUCKY_ENV=production`
- `PORT=3000`
- `DATABASE_URL=postgresql://...`
- `SECRET_KEY_BASE=...`

crystalshards also needs:
- `REDIS_URL=redis://...` (for JoobQ workers)

## Workflow

1. **Before continuing**: Check CI status with `gh run list`, fix any failures
2. **Find work**: Check `.agent/STATUS.md` or `gh issue list`
3. **Make changes**: Follow conventions above
4. **Validate**: `terraform validate` must pass
5. **Commit**: Descriptive message, push frequently
6. **Watch CI**: Fix any failures immediately

## Error Handling

Never get blocked:
1. Log errors to `.agent/errors.log`
2. Try alternative approaches (3 attempts)
3. Document in STATUS.md
4. Continue with next task

Common fixes:
- Terraform errors: Check variable passing between modules
- CI failures: Read logs, fix root cause
- Missing files: Check paths, create if needed

---
**Current Focus**: Create missing Kubernetes resources to make infrastructure deployable.
