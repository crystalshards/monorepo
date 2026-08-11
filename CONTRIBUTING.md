# Contributing to CrystalShards

Thank you for your interest in contributing to CrystalShards! We're building a comprehensive package registry and documentation platform for the Crystal programming language, and we welcome contributions from developers of all skill levels.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Development Workflow](#development-workflow)
- [Code Style Guidelines](#code-style-guidelines)
- [Testing Requirements](#testing-requirements)
- [Areas to Contribute](#areas-to-contribute)
- [Issue Guidelines](#issue-guidelines)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Review Process](#review-process)
- [Development Tips](#development-tips)
- [Getting Help](#getting-help)
- [Recognition](#recognition)
- [License](#license)

## Code of Conduct

This project adheres to the Contributor Covenant [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Getting Started

### Prerequisites

Before you begin, ensure you have the following installed:

- **Crystal Language**: >= 1.17.1 ([installation guide](https://crystal-lang.org/install/))
- **Lucky CLI**: Latest version ([installation guide](https://luckyframework.org/guides/getting-started/installing))
- **Docker** and **Docker Compose**: For the local service dependencies defined in `docker-compose.yml` ([installation guide](https://docs.docker.com/get-docker/))
- **Terraform**: >= 1.5.0, only if you are changing infrastructure ([installation guide](https://developer.hashicorp.com/terraform/downloads))
- **Git**: Version control ([installation guide](https://git-scm.com/downloads))
- **GitHub Account**: For pull requests and issue tracking

Optional but recommended:

- **mise**: Tool version manager (see `.mise.toml`)
- **gh**: GitHub CLI for easier issue/PR management
- **psql**: PostgreSQL client, for the database console commands in this guide

### Setting Up Development Environment

#### 1. Fork and Clone the Repository

```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/monorepo.git
cd monorepo

# Add upstream remote to stay in sync
git remote add upstream https://github.com/crystalshards/monorepo.git
```

#### 2. Install Dependencies

Run these from the repository root. Each step uses a subshell so your shell stays at the root for the next one.

```bash
for app in crystalshards crystaldocs crystalgigs crystalbits; do
  (cd apps/$app && shards install)
done
```

#### 3. Start Local Services and Set Up Databases

Bring up the local dependencies, then create each application's database. The Compose Postgres uses user `postgres` with password `password`, and the credentials an app falls back to when `DATABASE_URL` is unset do not match it, so set `DATABASE_URL` for the app you are working in:

```bash
# Start Postgres and object storage, waiting until both report healthy
docker compose up -d --wait postgres minio

# Create and migrate the development and test database of every application
for app in crystalshards crystaldocs crystalgigs crystalbits; do
  for env in development test; do
    (
      cd apps/$app
      export DATABASE_URL="postgresql://postgres:password@localhost:5432/${app}_${env}"
      lucky db.create
      lucky db.migrate
    )
  done
done

# Sample data for the registry
(
  cd apps/crystalshards
  export DATABASE_URL="postgresql://postgres:password@localhost:5432/crystalshards_development"
  lucky db.seed
)
```

#### 4. Configure Environment Variables

Each application loads `.env` from its own directory when you run it from there, so give every app its own copy. From the repository root:

```bash
for app in crystalshards crystaldocs crystalgigs crystalbits; do
  cp .env.example apps/$app/.env
done
```

Then edit each `apps/<app>/.env`, pointing `DATABASE_URL` at that application's own database and filling in the local secrets.

Required environment variables per application:

```bash
# Common to all apps
LUCKY_ENV=development
PORT=3000  # or 3001, 3002, 3003 for other apps
SECRET_KEY_BASE=generate_with_lucky_gen.secret_key
DATABASE_URL=postgresql://postgres:password@localhost:5432/<app>_development

# Object storage. Locally these point at the object store container docker
# compose runs. No Google Cloud credentials are needed to develop or to run
# the specs; production uses Google Cloud Storage with the service's own
# identity and ignores STORAGE_* entirely.
STORAGE_ENDPOINT=http://localhost:9000
STORAGE_ACCESS_KEY=minioadmin
STORAGE_SECRET_KEY=minioadmin

# Bucket names. CrystalShards writes documentation into DOCS_BUCKET and
# CrystalDocs reads it back, so both apps must agree. In production neither
# has a default and a missing one stops the service at boot.
DOCS_BUCKET=crystal-docs
PACKAGES_BUCKET=packages

# CrystalGigs only (for Stripe payments)
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
```

#### 5. Run Tests

Verify your setup is correct by running the test suite. Point `DATABASE_URL` at the `_test` database of the application you are testing:

```bash
export DATABASE_URL="postgresql://postgres:password@localhost:5432/crystalshards_test"

# Every spec for one application
(cd apps/crystalshards && crystal spec)

# A single spec file
(cd apps/crystalshards && crystal spec spec/models/crawl_state_spec.cr)

# With coverage
(cd apps/crystalshards && crystal spec --coverage)
```

#### 6. Start Development Server

```bash
# CrystalShards (main registry), served at http://localhost:3000
(cd apps/crystalshards && lucky watch)
```

For other applications, use the same `lucky watch` command from their respective directories.

## Project Structure

This is a monorepo containing multiple applications and infrastructure code:

```
monorepo/
├── apps/                         # All Lucky applications
│   ├── crystalshards/            # Main package registry
│   │   ├── src/                  # Source code
│   │   │   ├── actions/          # HTTP endpoints (Lucky actions)
│   │   │   ├── models/           # Database models (Avram)
│   │   │   ├── operations/       # Business logic (Avram operations)
│   │   │   ├── queries/          # Database queries (Avram queries)
│   │   │   ├── workers/          # Background jobs
│   │   │   ├── pages/            # HTML pages (Lucky HTML)
│   │   │   └── components/       # Reusable UI components
│   │   ├── spec/                 # Tests
│   │   ├── db/migrations/        # Database migrations
│   │   └── shard.yml             # Crystal dependencies
│   ├── crystaldocs/              # Documentation hosting
│   ├── crystalgigs/              # Job board
│   └── crystalbits/              # Blog platform
├── terraform/                    # Infrastructure as Code
├── .github/                      # GitHub configuration
│   └── workflows/                # CI/CD pipelines
├── docs/                         # Documentation
│   ├── user-guides/              # End user guides
│   ├── api/                      # OpenAPI specification
│   └── README.md                 # Documentation index
├── PROMPT.md                     # Project overview
├── CLAUDE.md                     # Agent development guidelines
└── README.md                     # Project README
```

### Technology Stack

- **Framework**: [Lucky](https://luckyframework.org/) - Type-safe, fast Crystal web framework
- **Compute**: [Cloud Run](https://cloud.google.com/run/docs) - one service per application, scaling to zero
- **Database**: [Cloud SQL for PostgreSQL](https://cloud.google.com/sql/docs/postgres) - a single instance with one database per application
- **Storage**: [Cloud Storage](https://cloud.google.com/storage/docs) for packages and built documentation
- **Queue**: [Cloud Tasks](https://cloud.google.com/tasks/docs) for documentation build requests
- **Edge**: one global external [Application Load Balancer](https://cloud.google.com/load-balancing/docs/https) with Google-managed certificates
- **Secrets**: [Secret Manager](https://cloud.google.com/secret-manager/docs), referenced by Cloud Run as environment variables
- **IaC**: [Terraform](https://www.terraform.io/) (one resource per file convention)
- **Observability**: [Cloud Logging](https://cloud.google.com/logging/docs) and [Cloud Monitoring](https://cloud.google.com/monitoring/docs)

## Development Workflow

### Branching Strategy

We use a simple branching model:

- `main` - Production-ready code (protected branch)
- `feature/<description>` - New features
- `fix/<description>` - Bug fixes
- `docs/<description>` - Documentation improvements
- `refactor/<description>` - Code refactoring

### Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:

- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Code style changes (formatting, no logic change)
- `refactor` - Code refactoring (no functionality change)
- `test` - Adding or updating tests
- `chore` - Maintenance tasks, dependencies, build changes

**Scopes** (examples):

- `crystalshards` - Changes to main registry app
- `crystaldocs` - Changes to documentation app
- `crystalgigs` - Changes to job board
- `crystalbits` - Changes to blog platform
- `api` - API changes
- `workers` - Background worker changes
- `ui` - User interface changes
- `infra` - Infrastructure/Terraform changes
- `ci` - CI/CD pipeline changes

**Examples**:

```bash
feat(crystalshards): add search autocomplete functionality

fix(api): handle null values in shard metadata response

docs(crystalshards): document the shard indexing flow

test(workers): add specs for BuildDocsWorker error handling

chore(deps): update Lucky framework to v1.4.1
```

### Pull Request Process

1. **Create a feature branch** from `main`:

   ```bash
   git checkout main
   git pull upstream main
   git checkout -b feature/my-awesome-feature
   ```

2. **Make your changes**:
   - Write code following our style guidelines
   - Add or update tests
   - Ensure all tests pass
   - Format code with `crystal tool format`
   - Update documentation if needed

3. **Commit your changes**:

   ```bash
   git add .
   git commit -m "feat(scope): description"
   ```

4. **Keep your branch up to date**:

   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

5. **Push to your fork**:

   ```bash
   git push origin feature/my-awesome-feature
   ```

6. **Create a Pull Request**:
   - Go to GitHub and create a PR from your fork
   - Fill out the PR template completely
   - Link related issues (e.g., "Closes #123")
   - Wait for CI checks to pass
   - Respond to review feedback

7. **After approval**:
   - Maintainers will merge your PR
   - Delete your feature branch

## Code Style Guidelines

### Crystal Code

Follow Crystal language conventions and best practices:

```crystal
# Use descriptive variable and method names
def calculate_download_stats(shard : Shard) : DownloadStats
  # Implementation
end

# Use type annotations for method parameters and return types
def find_shard(name : String) : Shard?
  ShardQuery.new.name(name).first?
end

# Prefer early returns for guard clauses
def process_shard(shard : Shard?) : Nil
  return if shard.nil?
  return unless shard.published?

  # Main logic here
end

# Use structs for value objects, classes for entities
struct VersionConstraint
  getter version : String
  getter operator : String
end

# Use meaningful constants
MAX_SEARCH_RESULTS = 100
DEFAULT_PAGE_SIZE  = 20
```

**Formatting**:

Always run Crystal's formatter before committing:

```bash
crystal tool format

# Format specific file
crystal tool format src/models/shard.cr

# Format all files in directory
find src -name "*.cr" -exec crystal tool format {} \;
```

### Lucky Framework Conventions

Follow Lucky's patterns for organizing code:

**Actions** (HTTP endpoints):

```crystal
# src/actions/shards/index.cr
class Shards::Index < BrowserAction
  get "/shards" do
    shards = ShardQuery.new.published.paginate(page: params.get?(:page, 1))
    html IndexPage, shards: shards
  end
end
```

**Operations** (business logic):

```crystal
# src/operations/save_shard.cr
class SaveShard < Shard::SaveOperation
  permit_columns name, description, repository_url

  before_save do
    validate_repository_url
    generate_slug
  end

  private def validate_repository_url
    # Validation logic
  end
end
```

**Queries** (database access):

```crystal
# src/queries/shard_query.cr
class ShardQuery < Shard::BaseQuery
  def published
    published(true)
  end

  def recent(limit = 10)
    order_by(created_at: :desc).limit(limit)
  end

  def search(term : String)
    where("name ILIKE ? OR description ILIKE ?", "%#{term}%", "%#{term}%")
  end
end
```

**Pages** (HTML rendering):

```crystal
# src/pages/shards/index_page.cr
class Shards::IndexPage < MainLayout
  needs shards : ShardQuery

  def content
    h1 "Crystal Shards"

    ul do
      shards.each do |shard|
        render ShardCard, shard: shard
      end
    end
  end
end
```

### Terraform Code

Follow Terraform best practices:

**One resource per file**:

```hcl
# resource.google_storage_bucket.docs.tf
resource "google_storage_bucket" "docs" {
  name     = "crystalshards-docs"
  location = var.region

  uniform_bucket_level_access = true
}
```

**Use variables for configuration**:

```hcl
# variables.tf
variable "region" {
  description = "GCP region for all regional resources"
  type        = string
  default     = "us-central1"
}
```

**Format before committing**:

```bash
terraform fmt -recursive
```

### Documentation

Write clear, helpful documentation:

- Use proper markdown formatting
- Include code examples with syntax highlighting
- Add table of contents for long documents
- Use descriptive headings
- Explain the "why" not just the "what"
- Keep language clear and concise

## Testing Requirements

### Writing Tests

All new features must include comprehensive test coverage:

```crystal
# spec/models/shard_spec.cr
require "../spec_helper"

describe Shard do
  describe "#published?" do
    it "returns true when shard is published" do
      shard = ShardFactory.create &.published(true)
      shard.published?.should be_true
    end

    it "returns false when shard is not published" do
      shard = ShardFactory.create &.published(false)
      shard.published?.should be_false
    end
  end

  describe ".search" do
    it "finds shards by name" do
      shard = ShardFactory.create &.name("http-client")
      results = ShardQuery.new.search("http").to_a
      results.should contain(shard)
    end

    it "handles special characters in search" do
      ShardFactory.create &.name("test-shard")
      results = ShardQuery.new.search("test's").to_a
      results.size.should eq(0)
    end
  end
end
```

**Test Categories**:

1. **Model specs** - Test database models and validations
2. **Operation specs** - Test business logic
3. **Query specs** - Test database queries
4. **Action specs** - Test HTTP endpoints
5. **Worker specs** - Test background jobs
6. **Integration specs** - Test complete workflows

### Running Tests

```bash
# Run all tests
crystal spec

# Run specific test file
crystal spec spec/models/crawl_state_spec.cr

# Run specific test by line number
crystal spec spec/models/crawl_state_spec.cr:7

# Run with coverage report
crystal spec --coverage

# Run in verbose mode
crystal spec --verbose
```

### Test Coverage Goals

- **Overall coverage**: Aim for >80%
- **Critical paths**: 100% coverage required
- **Edge cases**: Must be tested
- **Error handling**: Test failure scenarios
- **Happy path**: Test successful workflows

### Using Factories

Use factories for consistent test data:

```crystal
# spec/support/factories/shard_factory.cr
class ShardFactory < Avram::Factory
  def initialize
    name "example-shard"
    description "An example Crystal shard"
    repository_url "https://github.com/example/shard"
    published true
  end
end

# Usage in specs
shard = ShardFactory.create
shard = ShardFactory.create &.name("custom-name")
shards = ShardFactory.create_pair
```

## Areas to Contribute

We welcome contributions in many areas:

### Code Contributions

**New Features**:

- Advanced search capabilities (faceted search, filters)
- Dependency graph visualization
- Shard quality metrics and badges
- User profiles and authentication
- Shard ownership management
- API versioning improvements
- Documentation search improvements
- Job board payment integration enhancements
- Newsletter automation features

**Bug Fixes**:

- Check [open issues labeled "bug"](https://github.com/crystalshards/monorepo/issues?q=is%3Aissue+is%3Aopen+label%3Abug)
- Fix failing tests
- Resolve edge cases
- Handle error conditions

**Performance Improvements**:

- Database query optimization
- Caching strategies
- Background worker efficiency
- API response times
- Frontend load times

**Security Enhancements**:

- Input validation improvements
- Authentication/authorization hardening
- Rate limiting refinements
- Dependency vulnerability fixes
- Security audit findings

### Documentation

**User Guides**:

- Getting started with CrystalShards
- Publishing your first shard
- Documentation generation guide
- Search and discovery tips
- Troubleshooting common issues

**API Documentation**:

- Endpoint descriptions
- Request/response examples
- Authentication guides
- Rate limiting documentation
- Error handling guide

**Developer Documentation**:

- Architecture decision records
- Component interaction diagrams
- Database schema documentation
- Background worker workflows
- Deployment procedures

**Operations**:

- Incident response procedures
- Monitoring and alerting guides
- Performance troubleshooting
- Database maintenance
- Backup and recovery

### Infrastructure

**Terraform Improvements**:

- New module creation
- Resource optimization
- Cost reduction strategies
- Security hardening
- Multi-region support

**CI/CD Enhancements**:

- Faster build times
- Better test parallelization
- Enhanced security scanning
- Deployment automation
- Rollback procedures

**Monitoring & Observability**:

- Cloud Monitoring alert policies
- Structured logging improvements
- Log-based metrics
- Distributed tracing
- Performance profiling

### Design & UX

**User Interface**:

- Visual design improvements
- Component library development
- Responsive design enhancements
- Dark mode support
- Accessibility improvements

**User Experience**:

- Navigation improvements
- Search UX optimization
- Form validation feedback
- Error message clarity
- Onboarding experience

## Issue Guidelines

### Reporting Bugs

Before creating a bug report:

1. **Search existing issues** to avoid duplicates
2. **Verify the bug** in the latest version
3. **Collect information** about your environment

Use the bug report template and include:

- Clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs. actual behavior
- Environment details (OS, Crystal version, browser)
- Error messages and stack traces
- Screenshots if applicable

**Example**:

```markdown
**Bug**: Search returns duplicates when filtering by tag

**Steps to Reproduce**:
1. Go to /shards/search
2. Enter search query "http"
3. Select tag "networking"
4. Click search button

**Expected**: Unique results
**Actual**: Some shards appear twice

**Environment**:
- OS: macOS 13.4
- Browser: Chrome 120
- Crystal: 1.17.1
```

### Feature Requests

For feature requests, explain:

- **Problem**: What problem does this solve?
- **Solution**: Describe your proposed solution
- **Alternatives**: Other approaches you considered
- **Use cases**: Real-world scenarios
- **Impact**: Who benefits from this feature?

**Good feature request**:

```markdown
**Feature**: Add shard dependency graph visualization

**Problem**: Developers need to understand complex dependency chains
and identify potential circular dependencies or security vulnerabilities
in the dependency tree.

**Solution**: Add an interactive graph visualization on the shard
detail page showing direct and transitive dependencies with version
information.

**Alternatives**:
- Text-based tree view (less intuitive)
- External tool integration (extra friction)

**Use Cases**:
- Security auditing of dependencies
- Understanding library relationships
- Planning upgrades

**Impact**: All shard users and maintainers
```

### Issue Labels

Issues are categorized with labels:

- `bug` - Something isn't working correctly
- `enhancement` - New feature or improvement
- `documentation` - Documentation improvements
- `good first issue` - Good for newcomers
- `help wanted` - Extra attention needed
- `question` - Question or discussion
- `wontfix` - Will not be addressed
- `duplicate` - Duplicate of existing issue
- `invalid` - Issue is not valid
- `priority:high` - High priority
- `priority:medium` - Medium priority
- `priority:low` - Low priority

## Pull Request Guidelines

### Before Submitting

Ensure your PR meets these requirements:

- [ ] Tests added or updated for changes
- [ ] All tests pass locally (`crystal spec`)
- [ ] Code formatted with `crystal tool format`
- [ ] Documentation updated (if applicable)
- [ ] No new warnings or errors introduced
- [ ] Commit messages follow convention
- [ ] PR description explains the changes
- [ ] Related issues referenced

### PR Description Template

When creating a PR, use this template:

```markdown
## Description

Brief summary of changes (2-3 sentences).

## Motivation

Why is this change needed? What problem does it solve?

## Changes Made

- List of specific changes
- Each change on its own line
- Include both code and test changes

## Testing

How was this tested?

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed
- [ ] All tests pass locally

## Screenshots

If UI changes, include before/after screenshots.

## Related Issues

Closes #123
Relates to #456

## Checklist

- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] Code formatted
- [ ] All CI checks passing
- [ ] Ready for review
```

### PR Size

Keep PRs focused and reasonably sized:

- **Small PRs** (< 200 lines): Ideal, easy to review
- **Medium PRs** (200-500 lines): Acceptable
- **Large PRs** (> 500 lines): Consider splitting into smaller PRs

If you must create a large PR:

- Explain why it can't be split
- Provide detailed description
- Consider a draft PR for early feedback

### Draft PRs

Use draft PRs for:

- Work in progress (WIP)
- Seeking early feedback
- Discussing implementation approach
- Coordinating with other contributors

## Review Process

### What to Expect

- **Initial response**: A maintainer acknowledges the PR and flags anything blocking
- **Full review**: A maintainer reviews once CI is green
- **Feedback**: Constructive, specific, actionable
- **Approval**: When all feedback addressed and CI passes
- **Merge**: By maintainers after approval

### Review Criteria

Reviewers check for:

- **Correctness**: Does it work as intended?
- **Tests**: Adequate coverage and quality?
- **Code quality**: Readable, maintainable, follows conventions?
- **Documentation**: Clear and complete?
- **Performance**: No regressions?
- **Security**: No vulnerabilities introduced?

### Responding to Feedback

- Be respectful and professional
- Ask clarifying questions if feedback is unclear
- Explain your reasoning if you disagree
- Make requested changes promptly
- Push updates to the same branch
- Re-request review when ready

### Being a Good Reviewer

If you're reviewing PRs:

- Be respectful and constructive
- Explain why changes are needed
- Suggest specific improvements
- Acknowledge good work
- Approve when ready
- Test changes if possible

## Development Tips

### Local Development

**Watch Mode**: Auto-reload on file changes

```bash
lucky watch
```

**Debugging**: Use Crystal's built-in debugger

```crystal
require "debug"

def some_method
  debugger  # Execution pauses here
  # Step through code
end
```

**Database Console**:

```bash
# PostgreSQL console
psql crystalshards_development

# Run migrations
lucky db.migrate

# Rollback migration
lucky db.rollback

# Create new migration
lucky gen.migration AddPublishedAtToShards
```

### Common Issues

**Port Already in Use**:

```bash
# Find process using port 3000
lsof -i :3000

# Kill process
kill -9 <PID>
```

**Database Connection Errors**:

```bash
# Ensure PostgreSQL is running
pg_ctl status

# Restart PostgreSQL
pg_ctl restart

# Check connection
psql -h localhost -U postgres
```

**Dependency Issues**:

```bash
# Clear shard cache
rm -rf lib/ .shards/

# Reinstall dependencies
shards install

# Update dependencies
shards update
```

**Migration Conflicts**:

```bash
# Check migration status
lucky db.migrate.status

# Rollback to specific version
lucky db.rollback to=20240101120000

# Recreate database
lucky db.drop
lucky db.create
lucky db.migrate
lucky db.seed
```

### Useful Commands

**Code Quality**:

```bash
# Format all Crystal files
find . -name "*.cr" -exec crystal tool format {} \;

# Check for code issues with Ameba (if installed)
ameba

# View compiled code
crystal build src/crystalshards.cr --no-codegen --stats
```

**Database**:

```bash
# Generate new model
lucky gen.model Shard name:String description:Text

# Generate new migration
lucky gen.migration CreateShards

# Seed database
lucky db.seed

# Reset database
lucky db.drop && lucky db.create && lucky db.migrate && lucky db.seed
```

**Testing**:

```bash
# Run tests with color output
crystal spec --color

# Run tests in random order
crystal spec --order random

# Run specific describe block
crystal spec spec/models/crawl_state_spec.cr -e "only calls a sweep trustworthy"
```

**Cloud Run** (for infrastructure work, requires access to the GCP project):

```bash
# Inspect a deployed service
gcloud run services describe crystalshards --region us-central1

# Read recent logs for a service
gcloud run services logs read crystalshards --region us-central1

# List executions of the documentation build job
gcloud run jobs executions list --job docs-build --region us-central1
```

Ad-hoc log queries and metrics live in Cloud Logging and Cloud Monitoring in the `crystalshards-org` project.

## Getting Help

### Resources

- **Documentation**: `/docs/` directory in this repo
- **GitHub Discussions**: [Ask questions](https://github.com/crystalshards/monorepo/discussions)
- **GitHub Issues**: [Report bugs, request features](https://github.com/crystalshards/monorepo/issues)
- **Crystal Forum**: [forum.crystal-lang.org](https://forum.crystal-lang.org)
- **Lucky Gitter**: [gitter.im/luckyframework/lucky](https://gitter.im/luckyframework/lucky)
- **Crystal Discord**: [crystal-lang.org/community](https://crystal-lang.org/community)

### Before Asking

1. **Search documentation** in `/docs/`
2. **Check existing issues** for similar problems
3. **Review closed issues** for past solutions
4. **Read Lucky framework docs** at [luckyframework.org](https://luckyframework.org/)
5. **Check Crystal language docs** at [crystal-lang.org](https://crystal-lang.org/)

### Asking Good Questions

When asking for help:

- Provide context about what you're trying to do
- Include relevant code snippets
- Show error messages and stack traces
- Describe what you've already tried
- Specify your environment (OS, Crystal version, etc.)
- Be patient and respectful

**Good question example**:

```markdown
I'm trying to add a new API endpoint for searching shards by tag,
but I'm getting a compilation error:

Error: undefined method 'tagged' for ShardQuery

I've added the method to ShardQuery:

def tagged(tag : String)
  where("tags @> ARRAY[?]::text[]", tag)
end

But Crystal can't find it. I'm using Crystal 1.17.1 on macOS.
Any ideas what I'm missing?
```

## Recognition

We value all contributions and recognize our contributors:

- **Contributors list**: All contributors are listed in the README
- **Release notes**: Significant contributions are highlighted
- **GitHub mentions**: Contributors are thanked in merged PRs
- **Community recognition**: Outstanding contributors are featured

Thank you for helping make CrystalShards better!

## License

By contributing to CrystalShards, you agree that your contributions will be licensed under the same license as the project. See the LICENSE file for details.

---

**Questions?** Open a [GitHub Discussion](https://github.com/crystalshards/monorepo/discussions) or reach out to the maintainers.

**Ready to contribute?** Check out [good first issues](https://github.com/crystalshards/monorepo/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) to get started!
