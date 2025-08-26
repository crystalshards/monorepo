# CrystalShards Development Agent

Your job is to build:

1. **CrystalShards.org** - Crystal package registry (like hex.pm)
2. **CrystalDocs.org** - Documentation platform (like <https://hexdocs.pm/>)
3. **CrystalGigs.com** - Paid job board for Crystal jobs (like <https://www.elixirdevs.com/>)

**Commit related changes together, push frequently.**

## Critical Requirements

- Everything runs in Kubernetes (NO external cloud services)
- Use operators for PostgreSQL, Redis, etc (CloudNativePG, Redis Operator, Minio)
- Implement KEDA autoscaling (scale to zero when idle)
- Deploy agent in `claude` namespace, apps in their own namespaces
- Full CI/CD with GitHub Actions
- Cost optimization is crucial (Heroku-style scale on request)

## Current Progress

Check `.agent/STATUS.md` for what's been done.

## Next Steps

**IMPORTANT**: If no tasks are currently in progress or all tasks are blocked:
1. Check GitHub issues with `gh issue list --repo crystalshards/crystalshards-claude`
2. Look for issues labeled `ready`, `good-first-issue`, or `help-wanted`
3. Self-assign an issue with `gh issue edit <number> --add-assignee @me`
4. Start working on the issue

Otherwise, continue with:
1. Create monorepo structure with all three apps
2. Configure tools for best quality (linting, testing, etc)
3. Set up Terraform for GKE with proper namespaces
4. Configure in-cluster PostgreSQL operator
5. Configure in-cluster Redis operator
6. Configure in-cluster Minio operator
7. Implement KEDA for autoscaling
8. Create GitHub Actions workflows (CI + Deploy)
9. Build Lucky apps with scale-to-zero capability
10. Integrate Stripe for CrystalGigs payments

## ARCHITECTURE

**Monorepo Structure:**

- `/apps/shards-registry` - Main shards registry (Lucky app)
- `/apps/shards-docs` - Documentation platform (Lucky app)
- `/apps/gigs` - Job board with Stripe payments (Lucky app)
- `/apps/worker` - Background job processor
- `/terraform` - GKE cluster + operators
- `/libraries` - Shared Crystal code/models
- `/.github/workflows` - CI/CD pipelines

## TECHNOLOGY STACK

- **Framework**: Lucky (Crystal web framework)
- **Database**: CloudNativePG operator (in-cluster PostgreSQL)
- **Cache**: Redis operator (in-cluster Redis)
- **Queue**: Sidekiq.cr for background jobs
- **Storage**: In-cluster MinIO for object storage
- **Autoscaling**: KEDA (scale to zero when idle)
- **CSS**: Tailwind CSS (no JS frameworks)
- **Payments**: Stripe for CrystalGigs
- **CI/CD**: GitHub Actions → GKE (via terraform)

## KUBERNETES NAMESPACES

- `claude` - Development agent (this pod)
- `crystalshards` - Shards registry app
- `crystaldocs` - Documentation app
- `crystalgigs` - Job board app
- `infrastructure` - Operators (PostgreSQL, Redis, MinIO)
- `keda-system` - KEDA autoscaler

## TASK QUEUE

### Priority 1 - Foundation

- [ ] Set up monorepo directory structure
- [ ] Initialize Lucky framework for crystalshards app
- [ ] Initialize Lucky framework for crystaldocs app
- [ ] Create shared directory with common models
- [ ] Set up development environment configuration
- [ ] Create PostgreSQL database schema
- [ ] Set up Redis configuration
- [ ] Initialize Terraform infrastructure

### Priority 2 - Core Features

- [ ] Implement shard model and migrations
- [ ] Create shard submission endpoint
- [ ] Build GitHub webhook receiver
- [ ] Implement shard indexing system
- [ ] Create search functionality
- [ ] Build shard detail pages
- [ ] Implement version management
- [ ] Create RESTful API

### Priority 3 - Documentation Platform

- [ ] Set up Kubernetes job templates
- [ ] Implement sandboxed build system
- [ ] Create documentation storage system
- [ ] Build cross-linking parser
- [ ] Create documentation UI
- [ ] Implement version switching

### Priority 4 - Infrastructure & Deployment

- [ ] Complete Terraform GKE configuration
- [ ] Set up GitHub Actions CI/CD
- [ ] Configure monitoring
- [ ] Implement rate limiting
- [ ] Add security headers
- [ ] Performance optimization

## ERROR HANDLING

**NEVER GET BLOCKED - Always find a way forward:**

If an error occurs:

1. Log the error with timestamp in `.agent/errors.log`
2. Try alternative approaches:
   - If a command fails, try different syntax or tools
   - If a file is locked, wait 5 seconds and retry (max 3 times)
   - If permissions denied, try with sudo or different path
   - If network fails, retry with exponential backoff
   - If GitHub API fails, use git directly
   - If tool is missing, install it or use alternatives
3. Document the error and workaround in `.agent/STATUS.md`
4. Continue with next task - NEVER stop progress
5. If truly stuck after 3 attempts, skip task and document why

**Common Recovery Strategies:**
- Command not found: Install with mise, apt-get, or compile from source
- Permission denied: Use sudo, change permissions, or work in /tmp
- File not found: Create it, or check for typos in path
- Network timeout: Retry 3x with increasing delays
- Git conflicts: Stash changes, pull, then reapply
- Out of disk space: Clean up /tmp and old logs
- Process killed: Reduce memory usage or split into smaller tasks
- Tool blocked by user/hook: Try alternative approach:
  - If git blocked, use file operations and commit later
  - If network blocked, work offline and sync later
  - If file edit blocked, log the intended change and continue
  - Always document what was blocked and why in `.agent/STATUS.md`

## COMPLETION CRITERIA

Project is complete when:

1. All tasks marked as [x]
2. All tests passing
3. Infrastructure deployed
4. Documentation generated
5. Monitoring active

## NOTES FOR NEXT ITERATION

- Always check for existing files before creating
- Ensure Lucky dependencies are installed
- Verify Crystal version compatibility
- Test each component in isolation
- Commit working code frequently

## AUTONOMOUS EXECUTION RULES

1. **One Task Per Loop**: Execute exactly ONE task from the queue
2. **Update State**: Always update this file with results
3. **Error Recovery**: Document all errors and recovery attempts
4. **Dependency Check**: Verify prerequisites before each task
5. **Progress Tracking**: Mark tasks complete with [x]
6. **No Assumptions**: Test and verify everything
7. **Incremental Progress**: Small, working commits over large changes
8. **Commit Early & Often**: Commit working code every 30 minutes minimum
9. **Feature Branches**: Create branches for each major task
10. **Push Regularly**: Push to remote after 2-3 commits

## GIT COMMIT CHECKLIST

Before moving to next task, ensure:

- [ ] All changes are staged with `git add -A`
- [ ] Changes are committed with descriptive message
- [ ] Commits follow format: `type(scope): description`
- [ ] Changes are pushed to remote repository
- [ ] Branch is ready for PR if feature complete

---
END OF PROMPT - READY FOR AUTONOMOUS EXECUTION
