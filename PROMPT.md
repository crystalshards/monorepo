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
  - Stores rendered documentation in Google Cloud Storage
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

**TL;DR**: All four applications are implemented. The platform is migrating to Cloud Run in Google Cloud project `crystalshards-org`, region `us-central1`. Terraform applies run in CI only, never from a workstation.

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
  crystalshards/      # Package registry (Lucky app)
  crystaldocs/        # Documentation hosting (Lucky app)
  crystalgigs/        # Job board (Lucky app)
  crystalbits/        # Newsletter/blog (Lucky app)
terraform/            # All infrastructure as code, one resource per file
.github/workflows/    # CI/CD
```

### Technology Stack

- **Framework**: Lucky (Crystal web framework)
- **Platform**: Google Cloud project `crystalshards-org`, region `us-central1`
- **Compute**: Cloud Run services with scale to zero (`crystalshards`, `crystaldocs`, `crystalgigs`, `crystalbits`, `docs-launcher`) plus one Cloud Run Job (`docs-build`)
- **Database**: One Cloud SQL PostgreSQL instance `crystal-postgres` holding four databases, one per app, reached over the Cloud SQL unix socket at `/cloudsql/<connection_name>`. Each service sets `max_pool_size` 5, because the instance is small and four autoscaling services would otherwise exhaust its connection limit
- **Storage**: Google Cloud Storage, bucket `crystalshards-docs` for built documentation and `crystalshards-packages` for packages
- **Queue**: Cloud Tasks, queue `docs-builds`
- **Edge**: One global external Application Load Balancer with serverless NEGs and Google-managed certificates, serving all eight hostnames (apex and www for crystalshards.org, crystaldocs.org, crystalgigs.com, crystalbits.org). Cloud DNS holds the four managed zones
- **Images**: Artifact Registry repository `docker-images` in `us-central1`, image path `us-central1-docker.pkg.dev/crystalshards-org/docker-images/<app>:<sha>`
- **Secrets**: Secret Manager, referenced by Cloud Run as environment variables
- **Observability**: Cloud Logging and Cloud Monitoring
- **IaC**: Terraform (one resource per file)

## Background Work

Documentation builds run through Cloud Tasks. An enqueue puts a task on the `docs-builds` queue, the task calls `POST /internal/docs/build` on the `docs-launcher` service, and `docs-launcher` creates an execution of the `docs-build` Cloud Run Job.

The `docs-build` job runs `crystal docs` over untrusted third-party shard code, so it is deliberately powerless: its service account holds zero IAM bindings. It receives its input through a signed GET URL and writes its output through a signed PUT URL, both minted by `docs-launcher`. That isolation is the reason the platform runs on Cloud Run.

Shard indexing and dependency graph work lives in `apps/crystalshards/src/workers/`. Locally the queue is in-process.

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

**Platform migration in progress**: the four applications are moving to Cloud Run.

**Agent Directive**: Continue iterating toward full production readiness. See "Autonomous Iteration Workflow" section below for work discovery process.

**Current Priorities** (work on these in order):
1. **CrystalShards.org User Interface & Workers (TOP PRIORITY)** - Build the main package registry web interface and ensure background workers are functioning:
   - **Docs pipeline (CRITICAL)**: Documentation must actually build for the UI to be useful:
     * An enqueue puts a task on the `docs-builds` Cloud Tasks queue
     * The task calls `POST /internal/docs/build` on `docs-launcher`
     * `docs-launcher` creates a `docs-build` Cloud Run Job execution
     * Built output lands in the `crystalshards-docs` bucket
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
3. **Implement Multi-Provider Support** - Add support for GitHub, GitLab, Bitbucket, Codeberg, generic Git, Mercurial, and Fossil
4. Monitor CI/CD - fix any failures immediately
5. Address open GitHub issues
6. Complete Production Readiness Checklist items (see workflow section)
7. Improve monitoring and observability
8. Seed production data
9. Enhance documentation
10. Performance optimization
11. Security improvements

**Completed Phases** (pre-migration history, recorded before the move to Cloud Run):
- ✅ Phase 1: Infrastructure deployment
- ✅ Phase 2: CrystalShards implementation (models, API, workers)
- ✅ Phase 3: Production deployment (all 4 apps live)
- ✅ Phase 4: CrystalDocs implementation
- ✅ Phase 5: CrystalGigs and CrystalBits MVPs
- ✅ Phase 6: Production hardening (OpenAPI, rate limiting, security)

## Important Conventions

### Terraform

- One resource per file: `resource.<type>.<name>.tf`
- Module files: `module.<name>.tf`

### Environment Variables (Lucky apps)

Required:

- `LUCKY_ENV=production`
- `PORT=3000`
- `DATABASE_URL=postgresql://...`
- `SECRET_KEY_BASE=...`

Production also sets:

- `CLOUD_SQL_CONNECTION_NAME` - Cloud SQL instance connection name, socket path `/cloudsql/<connection_name>`
- `DOCS_BUCKET` - bucket for built documentation
- `PACKAGES_BUCKET` - bucket for packages
- `DOCS_BUILD_QUEUE` - Cloud Tasks queue for documentation builds
- `DOCS_LAUNCHER_URL` - URL of the `docs-launcher` service
- `DOCS_BUILD_JOB` - name of the `docs-build` Cloud Run Job

Secrets come from Secret Manager and are referenced by Cloud Run as environment variables. Credentials are never defaulted in code: a missing required production variable fails closed at boot with a message naming the variable.

Local development needs none of this. `make dev` runs the four apps on ports 3000 to 3003 against docker-compose Postgres, a local object store and an in-process queue, with no Google Cloud credentials.

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
   - **Push regularly** so work is never stranded locally
   - **Post progress comments** as milestones land: `gh issue comment <number> --body "Progress: [completed items]"`
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
- [ ] All 4 applications deployed on Cloud Run with HTTPS
- [ ] DNS configured and working
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
- [ ] Application metrics exposed

**Documentation:**
- [x] API documentation complete
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
```

## Error Handling

Never get blocked:

1. Use comments and issues on GitHub to track progress or report issues
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
**Current Status**: Migrating the four applications to Cloud Run. Continue iterating on the applications, observability, data seeding, and production polish.
