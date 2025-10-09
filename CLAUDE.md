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
- Track progress in GitHub issues and project comments

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
- Document workarounds in GitHub issue comments
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

- Implement aggressive caching with Redis
- Use database connection pooling
- Optimize queries with EXPLAIN ANALYZE
- Implement pagination for list endpoints
- Use background jobs for heavy operations
- Set resource limits on all pods
- Use spot instances for workers
- Configure GKE Autopilot autoscaling policies

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

GitHub Projects is the single source of truth for all task tracking and progress:

- **GitHub Projects**: Track all tasks and their status (Ready → In Progress → In Review → Done)
- **Issue Comments**: Document progress, blockers, and updates
- **PROMPT.md**: High-level phase tracking only (production readiness checklist)
- **Commit Messages**: Link to issues with `refs #<number>`
- **PR Descriptions**: Close issues with `Closes #<number>`
- **Push Frequently**: Commit and push working code regularly
- **Full Traceability**: Project Item → Issue → Commits → PR → Merged Code

This enables parallel agent execution since GitHub provides coordination.

### 11. Parallel Agent Execution

GitHub Projects as the single source of truth enables multiple agents to work simultaneously without conflicts. This architecture supports true asynchronous, parallel development.

#### How It Works

1. **Issue-Based Coordination**: Each agent self-assigns distinct GitHub issues
2. **Project Visibility**: All agents see current status in real-time via GitHub Projects
3. **Comment Communication**: Agents coordinate through issue comments (not STATUS.md files)
4. **Automatic Conflict Avoidance**: Work on different issues, preferably different applications

#### Parallel Work Guidelines

- **Different Issues**: Each agent must work on separate GitHub issues
- **Self-Assignment**: Use `gh issue edit <number> --add-assignee @me` to claim work
- **Status Updates**: Update project status to "In Progress" when starting (via web UI)
- **Progress Comments**: Regular comments ensure visibility across agents
- **Different Apps Preferred**: Minimize conflicts by working on different applications
- **No STATUS.md**: All tracking happens in GitHub - no shared file conflicts

#### Example Parallel Workflow

Agent 1 working on CrystalShards:
```bash
# Find and claim work
gh issue list --label "crystalshards" --assignee=""
gh issue edit 15 --add-assignee @me
gh issue comment 15 --body "Starting: Implement shard publishing API"
# Update project status to "In Progress" via web UI
# Work on apps/crystalshards/
```

Agent 2 working on CrystalDocs (simultaneously, no conflicts):
```bash
# Find and claim different work
gh issue list --label "crystaldocs" --assignee=""
gh issue edit 18 --add-assignee @me
gh issue comment 18 --body "Starting: Implement documentation search"
# Update project status to "In Progress" via web UI
# Work on apps/crystaldocs/ (different app, different files)
```

Agent 3 working on infrastructure (simultaneously):
```bash
# Work on cross-cutting concern
gh issue edit 22 --add-assignee @me
gh issue comment 22 --body "Starting: Add Prometheus alerting rules"
# Work on terraform/modules/operators/ (different area)
```

#### Coordination Through GitHub

All coordination happens through GitHub, not shared files:

- **Check assigned issues**: `gh issue list --assignee @me`
- **View in-progress work**: `gh project item-list <num> --owner crystalshards`
- **See who's working on what**: Check issue assignments and comments
- **No file locks**: No STATUS.md means no merge conflicts
- **Real-time visibility**: GitHub Projects shows current state instantly

#### Conflict Prevention

To avoid merge conflicts when multiple agents work in parallel:

1. **Work on different applications** (crystalshards vs crystaldocs vs crystalgigs vs crystalbits)
2. **Work on different modules** within the same app (models vs actions vs workers)
3. **Communicate via comments** if working in same area
4. **Push frequently** to make changes visible to other agents
5. **Pull before starting** new work to get latest changes

#### Benefits

- **Faster Development**: Multiple agents work simultaneously
- **No Bottlenecks**: No waiting for STATUS.md file locks
- **Better Tracking**: GitHub provides superior audit trail
- **Natural Coordination**: Issue assignments prevent duplicate work
- **Scalable**: Can add more agents without coordination overhead

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
6. **Link to Issues/Projects**: Reference issue numbers in commits and PRs

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

refs #<issue-number>

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

# Stage and commit changes with issue reference
git add -A
git commit -m "type(scope): description

refs #123"

# Push to remote
git push origin feature/task-name

# Create PR when feature is complete (links to issue automatically)
gh pr create --title "Feature: Task Name" --body "Description of changes

Closes #123"
```

### Linking to GitHub Projects

When working on items from GitHub Projects:

1. **Create issue from project item** (or use existing issue)
2. **Add issue to project**: `gh project item-add <project-num> --owner crystalshards --url <issue-url>`
3. **Reference issue in commits**: Use `refs #123` in commit message body
4. **Link PR to issue**: Use `Closes #123` in PR description
5. **Update project status**: Move item through workflow (Ready → In Progress → In Review → Done) via web UI

This creates a full audit trail: Project Item → Issue → Commits → PR → Merged Code

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
gh project --help

# Specific command help
gh issue create --help
gh pr view --help
gh project --help
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

## GitHub Projects Integration

The monorepo uses GitHub Projects for visual task management across all four applications. Each app has its own project board with a Workflow Status field.

### Project Boards

- **CrystalShards.org Development** - Project #1 - https://github.com/orgs/crystalshards/projects/1
- **CrystalDocs.org Development** - Project #2 - https://github.com/orgs/crystalshards/projects/2
- **CrystalGigs.com Development** - Project #3 - https://github.com/orgs/crystalshards/projects/3
- **CrystalBits.org Development** - Project #4 - https://github.com/orgs/crystalshards/projects/4

### Workflow Status Field Values

All projects use the same workflow status field:
- **Backlog** - Not yet ready to work on
- **Ready** - Ready to be picked up
- **In Progress** - Currently being worked on
- **In Review** - PR submitted, awaiting review
- **Done** - Completed

### Project Management Commands

```bash
# View project board
gh project view 1 --owner crystalshards --web  # Open in browser
gh project view 1 --owner crystalshards        # View in terminal

# List project items (tasks)
gh project item-list 1 --owner crystalshards
gh project item-list 1 --owner crystalshards --format json

# Add issue to project
gh project item-add 1 --owner crystalshards --url https://github.com/crystalshards/crystalshards-claude/issues/123

# Note: Status field updates via gh CLI are complex
# Prefer using the web UI or API for field updates
# Or use gh api directly:
gh api graphql -f query='
  mutation {
    updateProjectV2ItemFieldValue(input: {
      projectId: "PROJECT_ID"
      itemId: "ITEM_ID"
      fieldId: "FIELD_ID"
      value: {singleSelectOptionId: "OPTION_ID"}
    }) {
      projectV2Item {
        id
      }
    }
  }
'
```

### Mapping Apps to Projects

When working on specific apps, use the corresponding project:

```bash
# CrystalShards.org → Project 1
gh project view 1 --owner crystalshards

# CrystalDocs.org → Project 2
gh project view 2 --owner crystalshards

# CrystalGigs.com → Project 3
gh project view 3 --owner crystalshards

# CrystalBits.org → Project 4
gh project view 4 --owner crystalshards
```

### Project-Based Work Discovery

```bash
# Find ready tasks for CrystalShards
gh project item-list 1 --owner crystalshards --format json | \
  jq '.items[] | select(.status == "Ready")'

# Find in-progress items
gh project item-list 1 --owner crystalshards --format json | \
  jq '.items[] | select(.status == "In Progress")'

# View all projects
for i in {1..4}; do
  echo "=== Project $i ==="
  gh project view $i --owner crystalshards
done
```

## Task Lifecycle and Comment-Based Communication

GitHub issues and project items follow a structured lifecycle with transparent communication through comments. This ensures visibility and enables asynchronous coordination.

### Task Lifecycle States

Tasks flow through these states in GitHub Projects:

1. **Backlog** → Not yet ready to work on, future work
2. **Ready** → Actionable, all prerequisites met, can be picked up
3. **In Progress** → Currently being worked on (assign to yourself)
4. **In Review** → PR submitted and awaiting review
5. **Done** → Completed and merged

### Status Update Protocol

**When starting work on a task:**

```bash
# Self-assign the issue
gh issue edit <number> --add-assignee @me

# Comment to indicate you're starting work
gh issue comment <number> --body "Starting work on this issue now.

Current plan:
- Step 1
- Step 2
- Step 3

Expected completion: [timeframe if relevant]"

# Update project status to "In Progress" (via web UI or GraphQL API)
# gh project item-edit requires complex GraphQL - use web UI for simplicity
```

**During active work (provide progress updates):**

```bash
# Regular progress updates (every few hours or at milestones)
gh issue comment <number> --body "Progress update:

Completed:
- [x] Step 1
- [x] Step 2

In progress:
- [ ] Step 3

Next:
- [ ] Step 4"

# If you encounter blockers
gh issue comment <number> --body "⚠️ Blocker encountered:

Issue: [description of blocker]
Impact: [what's blocked]
Next steps: [what needs to happen to unblock]"
```

**When completing a task:**

```bash
# Create PR with issue reference
gh pr create --title "feat(scope): description" --body "$(cat <<'EOF'
## Summary
[Brief description of changes]

## Changes
- Change 1
- Change 2
- Change 3

## Testing
- [x] Unit tests passing
- [x] Integration tests passing
- [x] Manual testing completed

Closes #<number>
EOF
)"

# Comment on issue with completion details
gh issue comment <number> --body "Work completed in PR #<pr-number>

Summary of changes:
- [list key changes]

Commit: <commit-sha>
All tests passing: ✅"

# After PR is merged, close issue (if not auto-closed by "Closes #")
gh issue close <number> --comment "Merged in commit <sha>"

# Update project status to "Done" via web UI
```

### Comment-Based Interaction Patterns

**Asking Questions:**

```bash
gh issue comment <number> --body "Question about implementation:

Context: [what you're working on]
Question: [specific question]
Options considered:
1. [option A]
2. [option B]

Current thinking: [your proposed approach]"
```

**Reporting Errors:**

```bash
gh issue comment <number> --body "❌ Error encountered:

Error: [error message or description]
Context: [what you were doing]
Attempted fixes:
1. [fix 1] - [result]
2. [fix 2] - [result]

Current status: [blocked/investigating/found workaround]"
```

**Requesting Review or Help:**

```bash
gh issue comment <number> --body "@username Could you review this approach?

Context: [brief context]
Proposal: [what you're proposing]
Questions:
1. [specific question 1]
2. [specific question 2]

PR: #<pr-number> (if applicable)"
```

### Automated Status Transitions

While gh CLI doesn't easily update project fields, you can:

1. **Use web UI** - Click through Ready → In Progress → In Review → Done
2. **Use GraphQL API** - For automation (complex, see GitHub Projects Integration section)
3. **Use GitHub Actions** - Auto-transition on PR events (future enhancement)

### Comment Requirements for Transparency

Always comment when:
- Starting work on an issue
- Encountering blockers or errors
- Making significant progress (every few hours)
- Completing work or submitting PR
- Needing input or review
- Discovering new tasks or scope changes

This creates a transparent audit trail and enables async coordination without constant monitoring.

## Development Workflow

### Finding Work

**When no active task or all tasks are blocked:**

1. **Check PROMPT.md** for active tasks and priorities
2. **Check GitHub Projects** for ready tasks:
   ```bash
   # View project boards for each app
   gh project view 1 --owner crystalshards  # CrystalShards
   gh project view 2 --owner crystalshards  # CrystalDocs
   gh project view 3 --owner crystalshards  # CrystalGigs
   gh project view 4 --owner crystalshards  # CrystalBits

   # List items in Ready status
   gh project item-list 1 --owner crystalshards
   ```
3. **Check GitHub issues**: `gh issue list --repo crystalshards/crystalshards-claude`
4. Filter for actionable issues:
   - `gh issue list --label "ready" --assignee=""`
   - `gh issue list --label "good-first-issue" --assignee=""`
   - `gh issue list --label "help-wanted" --assignee=""`
5. Self-assign: `gh issue edit <number> --add-assignee @me`
6. Add to project: `gh project item-add <project-num> --owner crystalshards --url <issue-url>`
7. Create branch: `git checkout -b issue-<number>-<brief-description>`
8. Link commits to issue: Use "refs #<number>" in commit messages

### For Each Task

1. **Pick up work**: Read current state from PROMPT.md or check GitHub Projects/Issues
2. **Self-assign**: `gh issue edit <number> --add-assignee @me`
3. **Comment start**: Announce you're starting work with your plan (see Task Lifecycle section)
4. **Update project status**: Move to "In Progress" via web UI
5. **Create branch**: `git checkout -b issue-<number>-<brief-description>`
6. **Check prerequisites**: Verify dependencies and requirements
7. **Implement**: Build the feature – include unit/integration tests
8. **Test**: Write and run E2E tests that exercise the browser
9. **Commit frequently**: With issue reference (`refs #<number>` in commit body)
10. **Progress comments**: Update issue with progress every few hours or at milestones
11. **Push regularly**: Push to remote after completing logical units
12. **Handle errors**: Document errors in issue comments (see Task Lifecycle section)
13. **Create PR**: When complete, create PR with `Closes #<number>` in description
14. **Comment completion**: Add completion comment to issue with summary
15. **Update project**: Move to "In Review" then "Done" after merge

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
- Issue comments document completion and results
- GitHub Project status updated to "In Review" or "Done"
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
