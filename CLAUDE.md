# Claude Development Guidelines for CrystalShards

## RepoMirror-Inspired Philosophy

**Less is more** - Focus on the engine, not the scaffolding. Simple prompts are better than complex ones.

## Project Context

Building CrystalShards.org and CrystalDocs.org - a comprehensive Crystal language package registry and documentation platform.

## Development Principles

### 1. Autonomous Execution (RepoMirror Style)

- **Commit logical groups of changes and push frequently** - Keep git history meaningful
- Focus on building, not planning
- Self-regulate scope - know when to stop
- Let the simple prompt guide you
- Track progress in .agent/STATUS.md

### 2. Code Style & Conventions

- Follow Crystal language best practices
- Use Lucky framework conventions for web apps
- Keep code simple, readable, and well-structured
- No comments unless absolutely necessary for complex logic
- Use descriptive variable and method names

### 3. File Management

- Always check if files exist before creating
- Prefer editing existing files over creating new ones
- Never create documentation files unless explicitly needed
- Use consistent directory structure as defined in PROMPT.md

### 4. Testing & Verification

- Test each component in isolation
- Verify Crystal dependencies are available
- Check Lucky framework compatibility
- Run crystal tool format on all Crystal files
- Ensure database migrations are reversible

### 5. Security Best Practices

- Never commit secrets or API keys
- Use environment variables for configuration
- Sanitize all user inputs
- Implement rate limiting on public endpoints
- Run documentation builds in sandboxed environments

### 6. Database Design

- Use PostgreSQL best practices
- Create proper indexes for search queries
- Use JSONB for flexible metadata storage
- Implement soft deletes where appropriate
- Add created_at/updated_at timestamps to all tables

### 7. Error Handling & Self-Recovery

**NEVER GET BLOCKED - Always find a way forward:**

- Log errors with timestamps and context in `.agent/errors.log`
- Try multiple approaches before giving up:
  - If command fails, try alternative commands or tools
  - If API fails, use fallback methods or retry with backoff
  - If file locked, wait and retry (max 3 attempts)
  - If permission denied, try sudo or alternative paths
- Document workarounds in `.agent/STATUS.md`
- Provide meaningful error messages to users
- Implement proper HTTP status codes
- Use Lucky's error handling mechanisms
- Continue with next task if truly stuck after 3 attempts

**Recovery Examples:**
```bash
# If gh command fails
git log --oneline | grep "issue" || echo "No issues found"

# If mise fails
asdf install || apt-get install -y <tool> || compile from source

# If network timeout
for i in {1..3}; do command && break || sleep $((i*5)); done

# If disk full
rm -rf /tmp/* && docker system prune -f
```

### 8. Performance & Cost Optimization

- Implement KEDA autoscaling on ALL apps
- Configure scale-to-zero with 5 minute idle timeout
- Use HTTP-based scaling (requests trigger scale-up)
- Implement aggressive caching with Redis
- Use database connection pooling
- Optimize queries with EXPLAIN ANALYZE
- Implement pagination for list endpoints
- Use background jobs for heavy operations
- Set resource limits on all pods
- Use spot instances for workers

### 9. Infrastructure (All In-Cluster)

- Use Terraform for GKE cluster + operators only
- NO external cloud services (Cloud SQL, Memorystore, etc)
- Use operators for all stateful services:
  - CloudNativePG for PostgreSQL
  - Redis Operator for Redis
  - MinIO for object storage
- Separate namespaces for each app
- Agent runs in `claude` namespace
- Implement proper resource limits
- Set up monitoring with Prometheus/Grafana

### 10. Progress Tracking

- Update task checkboxes in PROMPT.md
- Log all actions with timestamps
- Commit and Push working code frequently
- Use descriptive commit messages
- Track blockers and dependencies

## Lucky Framework Specifics

### Setup Commands

```bash
# Install Lucky CLI
brew install luckyframework/homebrew-tap/lucky

# Create new Lucky app
lucky init.custom <app_name>

# Install dependencies
shards install

# Setup database
lucky db.create
lucky db.migrate
```

### Common Patterns

- Use Lucky actions for HTTP endpoints
- Implement operations for business logic
- Use queries for database access
- Follow RESTful conventions
- Use Lucky's built-in authentication

## Crystal Language Best Practices

### Shard Management

- Always specify version constraints
- Use semantic versioning
- Document all dependencies
- Keep shard.yml up to date
- Test with latest Crystal version

### Performance Tips

- Use compile-time macros when possible
- Avoid unnecessary allocations
- Use structs for value objects
- Profile with crystal tool hierarchy
- Benchmark critical paths

## Monitoring & Observability

### Key Metrics

- Response times < 100ms for search
- Documentation build success rate > 95%
- Zero downtime deployments
- Database query performance
- Background job processing time

### Logging Standards

- Use structured logging (JSON)
- Include request IDs
- Log at appropriate levels
- Avoid logging sensitive data
- Set up log aggregation

## Git Workflow - Commit Early and Often

### Commit Strategy

1. **Atomic Commits**: Each commit should represent one logical change
2. **Frequent Commits**: Commit working code at least every 30 minutes
3. **Descriptive Messages**: Use clear, concise commit messages
4. **Feature Branches**: Create branches for each major feature
5. **Push Frequently**: Push to remote after completing logical units of work

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: feat, fix, docs, style, refactor, test, chore
Example: `feat(shards): add search functionality`

### Git Commands to Use

```bash
# Configure git identity (run once)
git config --global user.name "CrystalShards Bot"
git config --global user.email "bot@crystalshards.org"

# Create feature branch
git checkout -b feature/task-name

# Stage and commit changes
git add -A
git commit -m "type(scope): description"

# Push to remote
git push origin feature/task-name

# Create PR when feature is complete
gh pr create --title "Feature: Task Name" --body "Description of changes"
```

## GitHub CLI Tool Reference

The GitHub CLI (`gh`) is the primary tool for interacting with GitHub. Instead of loading extensive MCP context, use `gh --help` and subcommand help to discover functionality.

### Getting Help

```bash
# Main help
gh --help

# Subcommand help
gh issue --help
gh pr --help
gh repo --help
gh workflow --help

# Specific command help
gh issue create --help
gh pr view --help
```

### Common GitHub CLI Commands

```bash
# Issues
gh issue list                           # List issues
gh issue create --title "Title"         # Create issue
gh issue view <number>                   # View issue details
gh issue edit <number>                   # Edit issue
gh issue close <number>                  # Close issue
gh issue comment <number> --body "msg"  # Add comment

# Pull Requests
gh pr list                              # List PRs
gh pr create                            # Create PR interactively
gh pr view <number>                     # View PR details
gh pr checkout <number>                 # Checkout PR branch
gh pr merge <number>                    # Merge PR
gh pr review <number>                   # Review PR

# Repositories
gh repo view                            # View current repo
gh repo clone <owner>/<name>           # Clone repo
gh repo fork                           # Fork current repo

# Workflows
gh workflow list                        # List workflows
gh workflow view <name>                # View workflow details
gh workflow run <name>                 # Trigger workflow
gh run list                           # List workflow runs
gh run view <run-id>                  # View run details

# Authentication
gh auth status                         # Check auth status
gh auth login                         # Login to GitHub
```

### Best Practices

1. **Use help pages instead of memorizing**: Always check `--help` for accurate syntax
2. **Leverage interactive modes**: Many commands have interactive modes when flags are omitted
3. **Use JSON output for parsing**: Add `--json` flag for machine-readable output
4. **Filter and format**: Use `--jq` for filtering JSON output

## Development Workflow

### Finding Work

**When no active task or all tasks are blocked:**
1. Check GitHub issues: `gh issue list --repo crystalshards/crystalshards-claude`
2. Filter for actionable issues:
   - `gh issue list --label "ready" --assignee=""`
   - `gh issue list --label "good-first-issue" --assignee=""`
   - `gh issue list --label "help-wanted" --assignee=""`
3. Self-assign: `gh issue edit <number> --add-assignee @me`
4. Create branch: `git checkout -b issue-<number>-<brief-description>`
5. Link commits to issue: Use "refs #<number>" in commit messages

### For Each Task

1. Read current state from PROMPT.md
2. Check GitHub issues if no active task
3. Create/checkout appropriate git branch
4. Check prerequisites and dependencies
5. Implement the specific task – don't forget to write unit/integration tests
6. Test the implementation – always write e2e tests that excercise the browser
7. **Commit working code immediately** (with issue reference if applicable)
8. Update PROMPT.md with results
9. Handle any errors appropriately
10. **Push to remote repository after completing logical work units**
11. Prepare notes for next iteration
12. Close issue if complete: `gh issue close <number> --comment "Completed in <commit-sha>"`

### Commit Checkpoints

- After creating new files
- After implementing a function/method
- After passing tests
- Before switching to a different task
- Every 30 minutes of active development
- When achieving any milestone

### Before Moving to Next Task

- Ensure current task is fully complete
- All tests are passing
- Code is properly formatted
- **All changes are committed and pushed**
- PROMPT.md is updated with latest status
- No uncommitted work remains
- Branch is ready for PR if feature complete

## Remember

- This is an autonomous process - no humans in the loop
- Make decisions based on best practices
- Document everything for future iterations
- Keep the system running smoothly
- Focus on delivering a working product

---
Last Updated: 2025-08-25
