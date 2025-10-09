# CrystalShards Development

## CrystalShards.org Ecosystem

The Vision: A comprehensive package registry and developer platform for the Crystal programming language, similar to what NPM is to Node.js or RubyGems is to Ruby.

The Four Applications:

1. CrystalShards.org (Main Registry)
  - Package registry for Crystal shards (libraries)
  - Developers can publish and discover Crystal packages
  - Tracks versions, dependencies, downloads
  - Background workers index shard metadata from GitHub
  - Automatically builds and hosts documentation
  - The core of the ecosystem

1. CrystalDocs.org (Documentation Host)
  - Hosts auto-generated documentation for all published shards
  - Supports multiple versions per package
  - Integrates with MinIO for static file storage
  - Provides version-switching for docs
  - Makes Crystal library documentation searchable and accessible

1. CrystalGigs.com (Job Board)
  - Job board specifically for Crystal developers
  - Companies can post Crystal-related jobs (paid feature via Stripe)
  - Helps grow the Crystal developer community
  - Job search and filtering

1. CrystalBits.org (Blog/Newsletter)
  - Blog platform for Crystal-related content
  - Users get generated email newsletters in their inbox if they subscribe
  - News, tutorials, community updates
  - Post tracking (view counts)
  - Auto-generates slugs
  - Community engagement platform

## Current State

**TL;DR**: All 6 phases complete (Infrastructure, CrystalShards, CrystalDocs, CrystalGigs, CrystalBits, Production Hardening). All CI passing. Ready for Terraform apply and deployment.

See GitHub Projects for detailed task tracking:
- CrystalShards.org → Project #1
- CrystalDocs.org → Project #2
- CrystalGigs.com → Project #3
- CrystalBits.org → Project #4
- Agent → Project #5

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
- **Jobs**: JoobQ (Redis-backed background workers in crystalshards)
- **Ingress**: Traefik
- **Platform**: GKE Autopilot
- **IaC**: Terraform (one resource per file)

### Kubernetes Namespaces

- `crystalshards` - Package registry app
- `crystaldocs` - Documentation app
- `crystalgigs` - Job board app
- `crystalbits` - Newsletter app
- `infrastructure` - Shared operators (cert-manager, CNPG, Redis, MinIO, Prometheus)

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

JoobQ workers in `apps/crystalshards/src/workers/` (Redis-backed job queue):

- **IndexShardWorker** - Parse shard.yml, extract metadata, update search index
- **BuildDocsWorker** - Run `crystal docs` in sandbox, upload to MinIO
- **UpdateDependenciesWorker** - Update dependency graph

Worker deployment separate from API deployment (scales independently).

### Multi-Provider Support

Workers should support multiple Git hosting providers with provider-specific implementations:

- **GitHub** - Primary provider with API integration
- **GitLab** - Self-hosted and gitlab.com support
- **Bitbucket** - Cloud and server versions
- **Codeberg** - Open-source alternative
- **Generic Git** - Any Git repository URL
- **Mercurial** - Alternative VCS support
- **Fossil** - Alternative VCS support

Each provider has independent worker implementations to handle provider-specific APIs, authentication, and webhooks.

## Current Focus: Continuous Production Readiness

**All initial phases complete!** ✅ Infrastructure deployed, all apps live with HTTPS.

**Agent Directive**: Continue iterating toward full production readiness. See "Autonomous Iteration Workflow" section below for work discovery process.

**Current Priorities** (work on these in order):
1. **CrystalShards.org User Interface & Workers (TOP PRIORITY)** - Build the main package registry web interface and ensure background workers are functioning:
   - **Workers (CRITICAL)**: Ensure all JoobQ workers are operational for the UI to be useful:
     * IndexShardWorker - Parse shard.yml, extract metadata, update search index
     * BuildDocsWorker - Run `crystal docs` in sandbox, upload to MinIO
     * UpdateDependenciesWorker - Update dependency graph
     * Workers must actually process jobs from Redis queue
     * Test with real shard indexing workflow
   - **Homepage**: Hero section, search bar, featured/popular shards, recent updates
   - **Browse/Search Page**: Paginated list of all shards with search and filter capabilities
   - **Package Detail Page**: Show package info, versions, installation instructions, dependencies, README, download stats, link to docs
   - Use Lucky framework's HTML rendering (no separate JS framework)
   - Responsive design with clean, modern CSS
   - Wire up to existing Shard/ShardVersion models and API actions
   - This is the core product - focus here first before other apps
   - **After UI implementation, verify with Playwright MCP** (see CLAUDE.md section 12):
     * Navigate to https://crystalshards.org
     * Check accessibility and layout with `browser_snapshot`
     * Test interactive elements (search, navigation, forms)
     * Verify responsive design (mobile, tablet, desktop)
     * Check console for JavaScript errors
     * Document any UI issues as GitHub issues
2. **Other Application UIs** - After CrystalShards is complete:
   - CrystalDocs.org: Documentation browser, version switcher, search
   - CrystalGigs.org: Job listing page, job detail, job posting form (with Stripe integration)
   - CrystalBits.org: Blog homepage, post listing, individual post pages, newsletter signup
   - **Verify each UI with Playwright after implementation**
3. **Migrate from Mosquito to JoobQ** - Replace background job system with JoobQ (https://github.com/azutoolkit/joobq)
4. **Implement Multi-Provider Support** - Add support for GitHub, GitLab, Bitbucket, Codeberg, generic Git, Mercurial, and Fossil
5. Monitor CI/CD - fix any failures immediately
6. Address open GitHub issues
7. Complete Production Readiness Checklist items (see workflow section)
8. Improve monitoring and observability
9. Seed production data
10. Enhance documentation
11. Performance optimization
12. Security improvements

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

- `REDIS_URL=redis://...` (for JoobQ workers)

## Autonomous Iteration Workflow

**GOAL**: Build a fully functional, production-ready system. Never idle - always iterate toward completion.

### Core Principle: Continuous Work

The agent should ALWAYS have work to do. Follow this priority order to find tasks:

1. **Active Tasks in PROMPT.md** → Work on current phase tasks
2. **CI Failures** → Fix immediately (`gh run list`, check logs)
3. **GitHub Projects (PRIMARY SOURCE OF TRUTH - NO STATUS.md)** → Check project boards for Ready items
   - CrystalShards.org → Project #1: https://github.com/orgs/crystalshards/projects/1 (TOP PRIORITY)
   - CrystalDocs.org → Project #2: https://github.com/orgs/crystalshards/projects/2
   - CrystalGigs.com → Project #3: https://github.com/orgs/crystalshards/projects/3
   - CrystalBits.org → Project #4: https://github.com/orgs/crystalshards/projects/4
   - Agent Enhancements → Project #5: https://github.com/orgs/crystalshards/projects/5
4. **GitHub Issues** → Check for open issues (`gh issue list`)
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

**CRITICAL**: GitHub Projects and Issues are the ONLY source of truth for all task tracking. **NO STATUS.md** - all progress updates happen through issue comments, not files. This enables parallel agent execution without conflicts.

### Iteration Steps

1. **Find Work** (use priority order above - NEVER idle)

2. **Before Starting**:
   - Check CI status: `gh run list` - fix any failures immediately
   - Self-assign issue: `gh issue edit <number> --add-assignee @me`
   - **Comment that you're starting**: `gh issue comment <number> --body "Starting work on this issue. Plan: [your plan]"`
   - Add issue to project if needed: `gh project item-add <project-num> --owner crystalshards --url <issue-url>`
   - **Update project status to "In Progress"** via web UI

3. **During Work**:
   - Make changes following conventions in this file
   - Validate: `terraform validate`, `crystal spec`, etc
   - Test: Write and run tests for new code
   - **Verify UI/UX (MANDATORY for user-facing changes)**: Use Playwright MCP (see CLAUDE.md section 12):
     * Navigate to deployed site (https://crystalshards.org, etc.)
     * Take accessibility snapshot with `browser_snapshot` (ALWAYS do this first)
     * Check console for errors with `browser_console_messages --onlyErrors true`
     * Test interactive elements (clicks, forms, navigation)
     * Verify responsive design at multiple viewport sizes (mobile, tablet, desktop)
     * Document ANY issues found as GitHub issues immediately
     * **UI verification is NOT optional - it's part of "done"**
   - **Commit frequently** with issue reference (`refs #123` in commit body)
   - **Push regularly** (at least every 30 minutes of work)
   - **Progress comments** every few hours: `gh issue comment <number> --body "Progress: [completed items]"`
   - Watch CI: Monitor for failures and fix immediately

4. **When Complete**:
   - Create PR with `Closes #<number>` in description
   - **Include UI/UX verification results** in PR description (if applicable):
     ```markdown
     ## UI/UX Verification
     - [x] Verified on https://[app-url]
     - [x] Accessibility snapshot reviewed
     - [x] No console errors
     - [x] Responsive design tested (mobile, tablet, desktop)
     - [x] Interactive elements functioning
     ```
   - **Comment completion**: `gh issue comment <number> --body "Work completed in PR #<pr-num>. Summary: [changes]"`
   - **Update project status** via web UI: In Progress → In Review → Done (after merge)
   - Close issue if not auto-closed: `gh issue close <number> --comment "Merged in <commit-sha>"`

5. **Communication Protocol**:
   - **Always comment** when starting, making progress, encountering blockers, or completing work
   - Use issue comments for transparency and async coordination
   - Document errors and blockers in comments
   - Reference commits and PRs in comments

6. **Find Next Work**: Immediately return to step 1 - no idle time

### Parallel Agent Execution

Multiple agents can work simultaneously using GitHub Projects as coordination:

- **Different Issues**: Each agent works on separate GitHub issues (self-assign to claim)
- **Different Apps**: Prefer working on different applications to minimize conflicts
- **Comment Coordination**: Use issue comments to communicate, not shared files
- **No STATUS.md**: All tracking in GitHub prevents file conflicts
- **Real-time Visibility**: GitHub Projects shows who's working on what

See CLAUDE.md section "11. Parallel Agent Execution" for detailed examples and guidelines.

### Production Readiness Checklist

Continue iterating until ALL of these are complete:

**Infrastructure & Deployment:**
- [x] GKE cluster deployed
- [x] All operators configured (cert-manager, CNPG, Redis, MinIO, Prometheus)
- [x] All 4 applications deployed with HTTPS
- [x] DNS configured and working
- [x] Grafana dashboards configured
- [x] Prometheus alerting rules set up
- [x] Log aggregation configured
- [x] Backup schedules configured
- [ ] Disaster recovery tested

**Application Features:**
- [x] All core APIs implemented
- [x] All tests passing (84 tests)
- [x] OpenAPI specs complete
- [x] Rate limiting enabled
- [ ] All UIs verified with Playwright for pleasant UX (see CLAUDE.md section 12)
  - [ ] CrystalShards.org: Homepage, search, package detail
  - [ ] CrystalDocs.org: Documentation browser, version switcher
  - [ ] CrystalGigs.com: Job listings, job detail, job posting
  - [ ] CrystalBits.org: Blog posts, newsletter signup
- [ ] Production data seeded
- [ ] E2E tests for critical paths
- [ ] Performance benchmarks established
- [ ] Load testing completed

**Monitoring & Observability:**
- [x] Health endpoints working
- [x] ServiceMonitors configured
- [ ] Application metrics exposed
- [x] Custom dashboards created
- [x] Alert rules defined
- [x] On-call runbooks written
- [x] Log queries documented

**Documentation:**
- [x] API documentation complete
- [x] Deployment runbook written
- [x] Operational runbooks for common incidents
- [ ] User guides for each application
- [ ] Contributing guide
- [ ] Architecture decision records

### Work Discovery Commands

```bash
# Check CI status
gh run list --limit 5

# Check GitHub Projects for ready work
gh project view 1 --owner crystalshards  # CrystalShards.org
gh project view 2 --owner crystalshards  # CrystalDocs.org
gh project view 3 --owner crystalshards  # CrystalGigs.com
gh project view 4 --owner crystalshards  # CrystalBits.org

# List items by project
gh project item-list 1 --owner crystalshards
gh project item-list 2 --owner crystalshards
gh project item-list 3 --owner crystalshards
gh project item-list 4 --owner crystalshards
gh project item-list 5 --owner crystalshards

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
3. Document in GitHub issue comments
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
3. ✅ If no active tasks, check GitHub Projects for Ready items (`gh project view <num> --owner crystalshards`)
4. ✅ If no project items, check GitHub issues (`gh issue list`)
5. ✅ If no GitHub issues, search for TODOs in code
6. ✅ If no TODOs, work on Production Readiness Checklist
7. ✅ ALWAYS be working toward a better, more complete system

**The goal is a fully production-ready platform, not just "deployed code."**

**CRITICAL CHANGE**: **NO MORE STATUS.md** - GitHub Projects is the ONLY source of truth for all task tracking. This enables parallel agent execution without file conflicts. All updates via issue comments.

### Project Board Quick Reference

All 5 GitHub Projects (in priority order):

- **CrystalShards.org** (Project #1): Main package registry - **TOP PRIORITY**
- **CrystalDocs.org** (Project #2): Documentation hosting
- **CrystalGigs.com** (Project #3): Job board
- **CrystalBits.org** (Project #4): Blog/newsletter
- **Agent Enhancements** (Project #5): Agent workflow improvements

View any board: `gh project view <1-5> --owner crystalshards --web`
View all boards: `for i in {1..5}; do gh project view $i --owner crystalshards; done`

---
**Current Status**: All apps deployed and live. Continue iterating on monitoring, observability, data seeding, and production polish.
