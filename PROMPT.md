# CrystalShards Development

Build the Crystal language ecosystem infrastructure:

1. **crystalshards.org** - Package registry (like hex.pm / rubygems.org)
2. **crystaldocs.org** - Documentation hosting (like hexdocs.pm)
3. **crystalgigs.com** - Job board (like elixirdevs.com)
4. **crystalbits.org** - Newsletter/blog

## Current State

See `.agent/STATUS.md` for complete status.

**TL;DR**: All 6 phases complete (Infrastructure, CrystalShards, CrystalDocs, CrystalGigs, CrystalBits, Production Hardening). All CI passing. Ready for Terraform apply and deployment.

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
- **Jobs**: Mosquito (background workers in crystalshards)
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

## Infrastructure Status

✅ **All deployment resources created:**

Each app has:

- ✅ `resource.kubernetes_deployment.<app>_api.tf` - API server pods
- ✅ `resource.kubernetes_service.<app>.tf` - Service to expose pods
- ✅ `resource.kubectl_manifest.<app>_postgres.tf` - PostgreSQL cluster (CNPG)
- ✅ `resource.kubernetes_secret.<app>_secrets.tf` - DATABASE_URL, REDIS_URL, SECRET_KEY_BASE

Shared:

- ✅ Redis cluster in infrastructure namespace
- ✅ MinIO tenant for package/doc storage

## Background Workers (crystalshards only)

Mosquito workers in `apps/crystalshards/src/workers/`:

- **IndexShardWorker** - Parse shard.yml, extract metadata, update search index
- **BuildDocsWorker** - Run `crystal docs` in sandbox, upload to MinIO
- **UpdateDependenciesWorker** - Update dependency graph

Worker deployment separate from API deployment (scales independently).

## Current Focus: Continuous Production Readiness

**All initial phases complete!** ✅ Infrastructure deployed, all apps live with HTTPS.

**Agent Directive**: Continue iterating toward full production readiness. See "Autonomous Iteration Workflow" section below for work discovery process.

**Current Priorities** (work on these in order):
1. Monitor CI/CD - fix any failures immediately
2. Address open GitHub issues
3. Complete Production Readiness Checklist items (see workflow section)
4. Improve monitoring and observability
5. Seed production data
6. Enhance documentation
7. Performance optimization
8. Security improvements

**Completed Phases** (for reference):
- ✅ Phase 1: Infrastructure deployment (GKE, operators, networking)
- ✅ Phase 2: CrystalShards implementation (models, API, workers)
- ✅ Phase 3: Production deployment (all 4 apps live)
- ✅ Phase 4: CrystalDocs implementation
- ✅ Phase 5: CrystalGigs and CrystalBits MVPs
- ✅ Phase 6: Production hardening (OpenAPI, rate limiting, security)

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

- `REDIS_URL=redis://...` (for Mosquito workers)

## Autonomous Iteration Workflow

**GOAL**: Build a fully functional, production-ready system. Never idle - always iterate toward completion.

### Core Principle: Continuous Work

The agent should ALWAYS have work to do. Follow this priority order to find tasks:

1. **Active Tasks in PROMPT.md** → Work on current phase tasks
2. **CI Failures** → Fix immediately (`gh run list`, check logs)
3. **GitHub Issues** → Check for open issues (`gh issue list`)
4. **STATUS.md Remaining Items** → Review `.agent/STATUS.md` for incomplete work
5. **Codebase TODOs** → Search for `TODO`, `FIXME`, `XXX` comments
6. **Production Readiness Improvements**:
   - Add monitoring dashboards (Grafana)
   - Set up alerting rules (Prometheus)
   - Implement log aggregation
   - Seed production data
   - Performance testing and optimization
   - Security hardening improvements
   - Documentation gaps
   - E2E test coverage
   - Error handling improvements
   - User experience polish

### Iteration Steps

1. **Find Work** (use priority order above - NEVER idle)
2. **Before Starting**:
   - Check CI status: `gh run list`
   - Fix any failures immediately
   - Self-assign GitHub issue if working on one: `gh issue edit <number> --add-assignee @me`
3. **Make Changes**: Follow conventions in this file
4. **Validate**: Run appropriate validation (`terraform validate`, `crystal spec`, etc)
5. **Test**: Write and run tests for new code
6. **Commit**: Descriptive message with issue reference if applicable (`refs #123`)
7. **Push**: Push frequently (at least every 30 minutes of work)
8. **Watch CI**: Monitor for failures and fix immediately
9. **Update Status**: Update `.agent/STATUS.md` with progress
10. **Close Issues**: If complete, close with `gh issue close <number> --comment "Completed in <commit-sha>"`
11. **Find Next Work**: Immediately return to step 1 - no idle time

### Production Readiness Checklist

Continue iterating until ALL of these are complete:

**Infrastructure & Deployment:**
- [x] GKE cluster deployed
- [x] All operators configured (cert-manager, CNPG, Redis, MinIO, Prometheus)
- [x] All 4 applications deployed with HTTPS
- [x] DNS configured and working
- [ ] Grafana dashboards configured
- [ ] Prometheus alerting rules set up
- [ ] Log aggregation configured
- [ ] Backup schedules configured
- [ ] Disaster recovery tested

**Application Features:**
- [x] All core APIs implemented
- [x] All tests passing (84 tests)
- [x] OpenAPI specs complete
- [x] Rate limiting enabled
- [ ] Production data seeded
- [ ] E2E tests for critical paths
- [ ] Performance benchmarks established
- [ ] Load testing completed

**Monitoring & Observability:**
- [x] Health endpoints working
- [x] ServiceMonitors configured
- [ ] Application metrics exposed
- [ ] Custom dashboards created
- [ ] Alert rules defined
- [ ] On-call runbooks written
- [ ] Log queries documented

**Documentation:**
- [x] API documentation complete
- [x] Deployment runbook written
- [ ] Operational runbooks for common incidents
- [ ] User guides for each application
- [ ] Contributing guide
- [ ] Architecture decision records

### Work Discovery Commands

```bash
# Check CI status
gh run list --limit 5

# Find GitHub issues
gh issue list --state open
gh issue list --label "ready" --assignee=""
gh issue list --label "good-first-issue"

# Search for TODOs
grep -r "TODO" apps/
grep -r "FIXME" apps/

# Check deployment status
kubectl get pods --all-namespaces

# Review monitoring gaps
kubectl get servicemonitors --all-namespaces
```

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

## Remember: Never Idle

This is an autonomous agent operating continuously toward production excellence. When you start a session:

1. ✅ Check CI status first (`gh run list`)
2. ✅ Look for active tasks in this file
3. ✅ If no active tasks, check GitHub issues
4. ✅ If no GitHub issues, review STATUS.md for remaining items
5. ✅ If nothing there, search for TODOs in code
6. ✅ If no TODOs, work on Production Readiness Checklist
7. ✅ ALWAYS be working toward a better, more complete system

**The goal is a fully production-ready platform, not just "deployed code."**

---
**Current Status**: All apps deployed and live. Continue iterating on monitoring, observability, data seeding, and production polish.
