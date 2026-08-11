# Claude Development Guidelines for CrystalShards

## RepoMirror-Inspired Philosophy

**Less is more** - Focus on the engine, not the scaffolding. Simple prompts are better than complex ones.

## Project Context

Building CrystalShards.org and CrystalDocs.org - a comprehensive Crystal language package registry and documentation platform.

## Quick Reference: Current Priorities

**TOP PRIORITY: CrystalShards.org UI & Workers**
- Background workers MUST be operational (IndexShardWorker, BuildDocsWorker, UpdateDependenciesWorker)
- Web interface: Homepage, Browse/Search, Package Detail
- **Verify ALL UI changes with Playwright MCP (Section 12)**
- This is the core product - focus here before other apps

**Key Principles:**
1. **GitHub Projects = Single Source of Truth** (NO STATUS.md)
2. **UI/UX Verification is Mandatory** (Playwright for all user-facing changes)
3. **Parallel Execution Enabled** (Multiple agents can work simultaneously)
4. **Comment-Based Communication** (Update issues, not files)
5. **CrystalShards First** (Other apps after core product is complete)

**All 5 GitHub Projects:**
- Project #1: CrystalShards.org (TOP PRIORITY)
- Project #2: CrystalDocs.org
- Project #3: CrystalGigs.com
- Project #4: CrystalBits.org
- Project #5: Agent Enhancements

**See PROMPT.md for active tasks. See .claude/ULTRATHINK.md for strategic guidance.**

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

- Use database connection pooling with `max_pool_size` 5 per service. The shared Cloud SQL instance is small and four autoscaling services would otherwise exhaust its connection limit
- Optimize queries with EXPLAIN ANALYZE
- Implement pagination for list endpoints
- Use background jobs for heavy operations
- Let Cloud Run scale to zero so idle services cost nothing

### 9. Infrastructure (Cloud Run on GCP)

Project `crystalshards-org`, region `us-central1`.

- **Compute**: Cloud Run services `crystalshards`, `crystaldocs`, `crystalgigs`, `crystalbits` and `docs-launcher`, all scaling to zero, plus one Cloud Run Job named `docs-build`
- **Database**: one Cloud SQL PostgreSQL instance `crystal-postgres` holding four databases (`crystalshards`, `crystaldocs`, `crystalgigs`, `crystalbits`), reached over the Cloud SQL unix socket at `/cloudsql/<connection_name>`
- **Object storage**: Cloud Storage buckets `crystalshards-docs` for built documentation and `crystalshards-packages`
- **Queue**: Cloud Tasks queue `docs-builds`. A task targets `POST /internal/docs/build` on `docs-launcher`, which creates a `docs-build` Job execution
- **Doc build isolation**: the `docs-build` job runs untrusted third-party shard code during `crystal docs`, so its service account holds zero IAM bindings. It takes input by signed GET URL and writes output by signed PUT URL, both minted by `docs-launcher`. This isolation is why the platform runs on Cloud Run
- **Edge**: one global external Application Load Balancer with serverless NEGs and Google-managed certificates, serving all eight hostnames (apex and www for crystalshards.org, crystaldocs.org, crystalgigs.com, crystalbits.org). Cloud DNS holds the four managed zones
- **Secrets**: Secret Manager, referenced by Cloud Run as environment variables. Never default a credential in code. Missing required production config fails closed at boot with a message naming the variable
- **Images**: Artifact Registry repository `docker-images`, image path `us-central1-docker.pkg.dev/crystalshards-org/docker-images/<app>:<sha>`
- **Observability**: Cloud Logging and Cloud Monitoring, which Cloud Run provides by default
- **Terraform** lives in `terraform/` and applies run in CI only. Locally, limit yourself to `terraform fmt`, `terraform init -backend=false`, `terraform validate` and `terraform plan`

### 10. Progress Tracking

**CRITICAL: NO STATUS.md FILES** - GitHub Projects is the ONLY source of truth for all task tracking and progress.

**Why NO STATUS.md:**
- Causes merge conflicts with parallel agents
- Creates bottleneck for coordination
- Duplicates information already in GitHub
- File locks prevent async collaboration
- GitHub Projects provides better visibility

**Instead, use:**

- **GitHub Projects**: Track all tasks and their status (Ready → In Progress → In Review → Done)
- **Issue Comments**: Document progress, blockers, and updates (REQUIRED for transparency)
- **PROMPT.md**: High-level phase tracking only (production readiness checklist)
- **Commit Messages**: Link to issues with `refs #<number>` in commit body
- **PR Descriptions**: Close issues with `Closes #<number>` in description
- **Push Frequently**: Commit and push working code regularly for visibility
- **Full Traceability**: Project Item → Issue → Commits → PR → Merged Code

**This enables parallel agent execution since GitHub provides coordination without file conflicts.**

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
gh issue comment 22 --body "Starting: Tune Cloud Run request timeouts"
# Work on terraform/ (different area)
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

### 12. UI/UX Verification with Playwright

Use the Playwright MCP server to verify deployed applications provide a pleasant user experience. This ensures that deployed apps are not just functional but also human-readable, accessible, and visually appealing.

#### When to Use Playwright Verification

**ALWAYS verify UI/UX after:**
- Deploying or updating any web application
- Implementing new UI features or pages
- Making CSS or layout changes
- Updating frontend components
- Completing user-facing features
- Before marking a task as complete

**Use as part of:**
- Production readiness checks
- E2E testing workflow
- UI implementation tasks
- Bug fix verification
- Release validation

#### Available Playwright Tools

Key MCP tools for verification (all prefixed with `mcp__playwright__`):

**Navigation & Inspection:**
- `browser_navigate` - Visit application URLs
- `browser_snapshot` - Capture accessibility tree (PREFERRED - faster and more informative than screenshots)
- `browser_take_screenshot` - Visual verification (use when snapshot isn't enough)
- `browser_console_messages` - Check for JavaScript errors

**Interaction Testing:**
- `browser_click` - Click buttons, links, and interactive elements
- `browser_type` - Fill in text inputs
- `browser_fill_form` - Fill multiple form fields at once
- `browser_select_option` - Select dropdown options
- `browser_hover` - Test hover states
- `browser_drag` - Test drag-and-drop functionality

**Advanced Inspection:**
- `browser_evaluate` - Run JavaScript to inspect page state
- `browser_network_requests` - Check network traffic and API calls
- `browser_resize` - Test responsive design at different viewport sizes
- `browser_press_key` - Test keyboard navigation

**Browser Management:**
- `browser_tabs` - Manage multiple tabs
- `browser_navigate_back` - Test navigation flow
- `browser_wait_for` - Wait for content to load

#### UI/UX Verification Checklist

When verifying a live application, check all of the following:

**Visual & Layout:**
- [ ] Page renders correctly without broken layouts
- [ ] No visual glitches or overlapping elements
- [ ] Images load properly with appropriate alt text
- [ ] Consistent spacing and alignment
- [ ] Responsive design works at different viewport sizes (mobile, tablet, desktop)
- [ ] Typography is readable with proper font sizes and line heights
- [ ] Color contrast meets accessibility standards

**Navigation & Usability:**
- [ ] All links work and navigate to correct pages
- [ ] Navigation menu is intuitive and accessible
- [ ] Breadcrumbs or path indicators work correctly
- [ ] Back button works as expected
- [ ] Search functionality works and returns relevant results

**Interactive Elements:**
- [ ] Buttons respond to clicks with visual feedback
- [ ] Forms accept input and validate correctly
- [ ] Form submission works and shows success/error states
- [ ] Dropdowns and selects function properly
- [ ] Modals/dialogs open and close correctly
- [ ] Interactive elements have visible hover states

**Accessibility:**
- [ ] Semantic HTML structure (headings, landmarks, lists)
- [ ] Proper ARIA labels on interactive elements
- [ ] Keyboard navigation works (Tab, Enter, Escape)
- [ ] Focus indicators are visible
- [ ] Screen reader compatibility (check accessibility tree)

**Performance & Errors:**
- [ ] Page loads quickly (no long spinners)
- [ ] No JavaScript console errors
- [ ] No failed network requests (check 404s, 500s)
- [ ] Loading states display appropriately
- [ ] Error messages are clear and actionable

**Content:**
- [ ] Text is readable and grammatically correct
- [ ] Placeholder content replaced with real data
- [ ] Empty states handled gracefully
- [ ] Date/time formatting is correct
- [ ] Numbers formatted appropriately (currency, percentages, etc.)

#### Example Verification Workflow

**Verify CrystalShards.org Homepage:**

```bash
# 1. Navigate to the site
mcp__playwright__browser_navigate --url "https://crystalshards.org"

# 2. Take accessibility snapshot (ALWAYS DO THIS FIRST)
mcp__playwright__browser_snapshot

# 3. Check for console errors
mcp__playwright__browser_console_messages --onlyErrors true

# 4. Test search functionality
mcp__playwright__browser_type \
  --element "search input" \
  --ref "[search-input-ref-from-snapshot]" \
  --text "http client"

mcp__playwright__browser_press_key --key "Enter"

# 5. Wait for results and verify
mcp__playwright__browser_wait_for --text "results"
mcp__playwright__browser_snapshot

# 6. Test navigation to package detail
mcp__playwright__browser_click \
  --element "first search result" \
  --ref "[result-ref-from-snapshot]"

# 7. Verify package detail page
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot --filename "crystalshards-package-detail.png"

# 8. Test responsive design
mcp__playwright__browser_resize --width 375 --height 667  # iPhone size
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot --filename "crystalshards-mobile.png"

# 9. Check network requests for errors
mcp__playwright__browser_network_requests
```

**Verify CrystalDocs.org Documentation:**

```bash
# Navigate to docs site
mcp__playwright__browser_navigate --url "https://crystaldocs.org"
mcp__playwright__browser_snapshot

# Search for a package
mcp__playwright__browser_type \
  --element "search input" \
  --ref "[search-ref]" \
  --text "lucky"

mcp__playwright__browser_press_key --key "Enter"
mcp__playwright__browser_snapshot

# Click on a documentation page
mcp__playwright__browser_click \
  --element "Lucky framework docs" \
  --ref "[docs-link-ref]"

# Verify version switcher works
mcp__playwright__browser_click \
  --element "version dropdown" \
  --ref "[version-dropdown-ref]"

mcp__playwright__browser_snapshot
```

**Verify CrystalGigs.com Job Board:**

```bash
# Navigate to job board
mcp__playwright__browser_navigate --url "https://crystalgigs.com"
mcp__playwright__browser_snapshot
mcp__playwright__browser_console_messages

# Test job listing browsing
mcp__playwright__browser_click \
  --element "first job listing" \
  --ref "[job-ref]"

mcp__playwright__browser_snapshot

# Test job posting form
mcp__playwright__browser_navigate --url "https://crystalgigs.com/jobs/new"

mcp__playwright__browser_fill_form --fields '[
  {
    "name": "Job title",
    "type": "textbox",
    "ref": "[title-ref]",
    "value": "Senior Crystal Developer"
  },
  {
    "name": "Company name",
    "type": "textbox",
    "ref": "[company-ref]",
    "value": "Test Company"
  }
]'

mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot --filename "crystalgigs-form.png"
```

**Verify CrystalBits.org Blog:**

```bash
# Navigate to blog
mcp__playwright__browser_navigate --url "https://crystalbits.org"
mcp__playwright__browser_snapshot

# Check blog post listing
mcp__playwright__browser_click \
  --element "first blog post" \
  --ref "[post-ref]"

# Verify post content is readable
mcp__playwright__browser_snapshot
mcp__playwright__browser_take_screenshot --filename "crystalbits-post.png"

# Test newsletter signup
mcp__playwright__browser_type \
  --element "email input" \
  --ref "[email-ref]" \
  --text "test@example.com"

mcp__playwright__browser_click \
  --element "subscribe button" \
  --ref "[subscribe-ref]"

mcp__playwright__browser_snapshot
```

#### Verification Best Practices

**Snapshot First, Screenshot Second:**
- Always start with `browser_snapshot` - it's faster and provides semantic structure
- Only use `browser_take_screenshot` when visual verification is essential
- Accessibility snapshots show semantic HTML structure and ARIA labels

**Check Console for Errors:**
- Always run `browser_console_messages --onlyErrors true` on each page
- JavaScript errors indicate broken functionality
- Document any errors found as GitHub issues

**Test Key User Journeys:**
- **CrystalShards**: Browse → Search → View Package → Install Instructions
- **CrystalDocs**: Search → View Docs → Switch Version
- **CrystalGigs**: Browse Jobs → View Detail → Post Job (with Stripe)
- **CrystalBits**: Browse Posts → Read Post → Subscribe to Newsletter

**Verify Responsive Design:**
- Test at multiple viewport sizes:
  - Mobile: 375×667 (iPhone SE)
  - Tablet: 768×1024 (iPad)
  - Desktop: 1920×1080
- Ensure layout adapts gracefully
- Check that interactive elements remain usable

**Document Issues as GitHub Issues:**
```bash
# If you find a UX issue during verification
gh issue create \
  --title "UI Issue: Search input not visible on mobile" \
  --body "$(cat <<'EOF'
## Description
Search input on CrystalShards.org homepage is not visible on mobile viewport (375px width).

## Steps to Reproduce
1. Navigate to https://crystalshards.org
2. Resize viewport to 375×667
3. Search input is hidden or cut off

## Expected Behavior
Search input should be fully visible and functional on all screen sizes.

## Screenshots
[Attach screenshot from Playwright verification]

## Browser
Playwright (Chromium)

## Priority
Medium - affects mobile users
EOF
)" \
  --label "bug,ui,mobile"
```

**Create Evidence Trail:**
- Take screenshots of issues found
- Include console error messages in issue reports
- Reference verification in issue comments
- Link to specific pages or user flows that have problems

**Verify After Fixes:**
- After fixing UI issues, re-run verification workflow
- Confirm the issue is resolved
- Update the GitHub issue with verification results
- Close issue only after verification passes

#### Integration with Task Workflow

**UI verification should be part of every task that touches user-facing code:**

1. **After Implementation** (step 8 in "For Each Task"):
   - Write and run E2E tests that exercise the browser
   - **NEW**: Run Playwright verification on deployed app

2. **Before Creating PR** (step 13):
   - Ensure Playwright verification passes
   - Include verification results or screenshots in PR description

3. **In PR Description**:
   ```markdown
   ## UI/UX Verification
   - [x] Verified on https://crystalshards.org
   - [x] Accessibility snapshot reviewed
   - [x] No console errors
   - [x] Responsive design tested (mobile, tablet, desktop)
   - [x] Interactive elements functioning
   - [x] Screenshots attached (if applicable)
   ```

#### Common Issues to Watch For

**Layout Issues:**
- Overlapping elements
- Content overflowing containers
- Broken grid layouts
- Inconsistent spacing

**Interactive Issues:**
- Buttons that don't respond to clicks
- Forms that don't submit
- Links that navigate to 404s
- Hover states that don't work

**Accessibility Issues:**
- Missing alt text on images
- No focus indicators on interactive elements
- Poor color contrast
- Missing ARIA labels
- Non-semantic HTML

**Performance Issues:**
- Slow page loads
- Long-running JavaScript
- Failed network requests
- Large image files not optimized

**Content Issues:**
- Lorem ipsum placeholder text
- Broken image links
- Incorrect or missing data
- Poorly formatted text

#### Production URL Reference

Always verify against these live URLs:

- **CrystalShards.org**: https://crystalshards.org
  - Homepage, search, package detail, user dashboard
- **CrystalDocs.org**: https://crystaldocs.org
  - Documentation browser, version switcher, search
- **CrystalGigs.com**: https://crystalgigs.com
  - Job listings, job detail, job posting form
- **CrystalBits.org**: https://crystalbits.org
  - Blog homepage, post listing, individual posts, newsletter signup

#### Automated Verification Script

Create a verification script for comprehensive checks:

```bash
#!/bin/bash
# verify-all-uis.sh - Comprehensive UI verification

apps=(
  "crystalshards.org:CrystalShards"
  "crystaldocs.org:CrystalDocs"
  "crystalgigs.com:CrystalGigs"
  "crystalbits.org:CrystalBits"
)

for app_info in "${apps[@]}"; do
  IFS=':' read -r url name <<< "$app_info"

  echo "=== Verifying $name ==="

  # Navigate
  mcp__playwright__browser_navigate --url "https://$url"

  # Snapshot
  mcp__playwright__browser_snapshot

  # Check errors
  mcp__playwright__browser_console_messages --onlyErrors true

  # Screenshot
  mcp__playwright__browser_take_screenshot \
    --filename "$name-desktop.png"

  # Mobile check
  mcp__playwright__browser_resize --width 375 --height 667
  mcp__playwright__browser_snapshot
  mcp__playwright__browser_take_screenshot \
    --filename "$name-mobile.png"

  # Reset viewport
  mcp__playwright__browser_resize --width 1920 --height 1080

  echo "✓ $name verification complete"
  echo ""
done

echo "All UI verifications complete!"
```

#### Remember

**UI/UX verification is NOT optional** - it's a critical part of delivering quality software:

- Users interact with UIs, not APIs
- A broken UI means a broken product
- Accessibility matters for all users
- Pleasant UX drives adoption
- Visual bugs damage credibility

**Always verify before closing issues or merging PRs that touch user-facing code.**

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
- Write to stdout and stderr. Cloud Run ships that to Cloud Logging with no extra setup

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

The monorepo uses GitHub Projects for visual task management across all applications. Each app and the agent have their own project board with a Workflow Status field.

### Project Boards

All 5 GitHub Projects (in priority order):

- **CrystalShards.org Development** - Project #1 - https://github.com/orgs/crystalshards/projects/1 (TOP PRIORITY)
- **CrystalDocs.org Development** - Project #2 - https://github.com/orgs/crystalshards/projects/2
- **CrystalGigs.com Development** - Project #3 - https://github.com/orgs/crystalshards/projects/3
- **CrystalBits.org Development** - Project #4 - https://github.com/orgs/crystalshards/projects/4
- **Agent Enhancements** - Project #5 - https://github.com/orgs/crystalshards/projects/5

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
# CrystalShards.org → Project 1 (TOP PRIORITY)
gh project view 1 --owner crystalshards

# CrystalDocs.org → Project 2
gh project view 2 --owner crystalshards

# CrystalGigs.com → Project 3
gh project view 3 --owner crystalshards

# CrystalBits.org → Project 4
gh project view 4 --owner crystalshards

# Agent Enhancements → Project 5
gh project view 5 --owner crystalshards
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
for i in {1..5}; do
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
2. **Check GitHub Projects** for ready tasks (all 5 projects):
   ```bash
   # View project boards for each app
   gh project view 1 --owner crystalshards  # CrystalShards (TOP PRIORITY)
   gh project view 2 --owner crystalshards  # CrystalDocs
   gh project view 3 --owner crystalshards  # CrystalGigs
   gh project view 4 --owner crystalshards  # CrystalBits
   gh project view 5 --owner crystalshards  # Agent Enhancements

   # List items in Ready status for priority project
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
9. **Verify UI/UX**: Use Playwright MCP to check deployed app for pleasant UX (see section 12)
   - Navigate to live site
   - Take accessibility snapshot
   - Check console for errors
   - Test interactive elements
   - Verify responsive design
   - Document any issues found as GitHub issues
10. **Commit frequently**: With issue reference (`refs #<number>` in commit body)
11. **Progress comments**: Update issue with progress every few hours or at milestones
12. **Push regularly**: Push to remote after completing logical units
13. **Handle errors**: Document errors in issue comments (see Task Lifecycle section)
14. **Create PR**: When complete, create PR with `Closes #<number>` in description
    - Include UI/UX verification results in PR description
15. **Comment completion**: Add completion comment to issue with summary
16. **Update project**: Move to "In Review" then "Done" after merge

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
