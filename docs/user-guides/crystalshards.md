# CrystalShards.org User Guide

## Table of Contents

- [Introduction](#introduction)
- [Getting Started](#getting-started)
- [Using Shards](#using-shards)
- [Package Details](#package-details)
- [Publishing Shards](#publishing-shards)
- [Best Practices](#best-practices)
- [API Usage](#api-usage)
- [Troubleshooting](#troubleshooting)

## Introduction

### What is CrystalShards.org?

CrystalShards.org is the official package registry for the Crystal programming language. Similar to rubygems.org for Ruby or npmjs.com for JavaScript, CrystalShards serves as the central repository for discovering, sharing, and managing Crystal libraries (called "shards").

### Why Use CrystalShards?

- **Discover Libraries**: Find high-quality Crystal libraries for any use case
- **Easy Installation**: Simple dependency management with `shards` command
- **GitHub Integration**: Automatic syncing with GitHub repositories
- **Documentation Links**: Direct access to hosted documentation on CrystalDocs.org
- **Community Driven**: Built by and for the Crystal community

### Key Features

- Advanced search with filtering by tags, license, stars, and activity
- Real-time statistics on downloads and usage
- Dependency visualization
- Version history and changelog tracking
- API access for automation
- GitHub webhook integration

## Getting Started

### Browsing Shards

Visit [https://crystalshards.org](https://crystalshards.org) to start exploring:

1. **Homepage** displays featured and popular shards
2. **Search bar** at the top for quick searches
3. **Browse** button to view all shards with filtering options
4. **Tags** to explore shards by category

### Searching for Packages

The search functionality supports multiple criteria:

**Basic Search:**
```
Type any keyword in the search bar:
- "http" - finds HTTP-related shards
- "database" - finds database libraries
- "testing" - finds testing frameworks
```

**Advanced Filters:**

- **Tags**: Filter by functionality (web, cli, database, etc.)
- **License**: Find shards with specific licenses (MIT, Apache, etc.)
- **Crystal Version**: Compatible with your Crystal version
- **Stars**: Minimum GitHub stars for quality indication
- **Recent Activity**: Find actively maintained projects

**Sorting Options:**

- **Relevance**: Best match for your search (default)
- **Downloads**: Most downloaded shards
- **Stars**: Highest GitHub stars
- **Recent**: Recently updated
- **Name**: Alphabetical order

### Understanding Search Results

Each result shows:

```
┌─────────────────────────────────────────────┐
│ 📦 kemal                           ⭐ 3,567 │
│ Lightning fast web framework                │
│ 📥 125,430 downloads  🏷️ web, framework     │
│ 📜 MIT  📅 Updated 2 days ago               │
└─────────────────────────────────────────────┘
```

- **Name**: Shard identifier
- **Stars**: GitHub popularity
- **Description**: What the shard does
- **Downloads**: Total download count
- **Tags**: Categorization
- **License**: Open source license
- **Updated**: Last activity date

## Using Shards

### Installing a Shard

To use a shard in your Crystal project:

**1. Add to `shard.yml`:**

```yaml
name: my_app
version: 0.1.0

dependencies:
  kemal:
    github: kemalcr/kemal
    version: ~> 1.4.0
```

**2. Install dependencies:**

```bash
shards install
```

This downloads the shard and its dependencies into the `lib/` directory.

### Understanding shard.yml

The `shard.yml` file is the manifest for your Crystal project:

```yaml
# Basic Information
name: my_shard                    # Shard name (required)
version: 0.1.0                   # Semantic version (required)
description: A useful library    # Brief description

# Crystal Version Requirement
crystal: >= 1.0.0

# Dependencies
dependencies:
  lucky:
    github: luckyframework/lucky  # GitHub repo
    version: ~> 1.0              # Version constraint

  postgres:
    github: will/crystal-pg
    version: ~> 0.24.0

# Development Dependencies (not installed in production)
development_dependencies:
  ameba:
    github: crystal-ameba/ameba
    version: ~> 1.5.0

  webmock:
    github: manastech/webmock.cr
    version: ~> 0.14.0

# Author Information
authors:
  - Your Name <you@example.com>

# License
license: MIT

# Repository
repository: https://github.com/yourusername/my_shard
```

### Version Constraints

Crystal uses semantic versioning (semver). Common patterns:

```yaml
dependencies:
  exact_version:
    github: user/shard
    version: 1.2.3              # Exact version only

  optimistic:
    github: user/shard
    version: ~> 1.2.3           # >= 1.2.3 and < 1.3.0

  optimistic_minor:
    github: user/shard
    version: ~> 1.2             # >= 1.2.0 and < 2.0.0

  minimum:
    github: user/shard
    version: ">= 1.0.0"         # Any version >= 1.0.0

  range:
    github: user/shard
    version: ">= 1.0.0, < 2.0"  # Between versions
```

**Recommendation**: Use `~>` (pessimistic operator) for most dependencies. It allows patch updates but prevents breaking changes.

### Using Installed Shards

After installation, require the shard in your code:

```crystal
require "kemal"

get "/" do
  "Hello World!"
end

Kemal.run
```

### Updating Dependencies

**Update all shards to latest compatible versions:**
```bash
shards update
```

**Update specific shard:**
```bash
shards update kemal
```

**Check for outdated shards:**
```bash
shards outdated
```

## Package Details

### Viewing Shard Information

Click any shard to view detailed information:

**Overview Tab:**
- Full description
- Installation instructions
- Quick start example
- Latest version info

**Versions Tab:**
- All published versions
- Release dates
- Changelog/release notes
- Version-specific documentation links

**Dependencies Tab:**
- Runtime dependencies
- Development dependencies
- Dependency graph visualization
- Transitive dependencies

**Statistics Tab:**
- Total downloads
- Downloads by version
- Download trends over time
- Popular dependents

**README Tab:**
- Full README from GitHub
- Rendered markdown
- Code examples
- Badges and links

### Version Information

Each version displays:

```
Version 1.4.0 (Latest)
Released: 2025-09-15
Downloads: 45,230
Crystal: >= 1.0.0

[View Docs] [View on GitHub] [Download .tar.gz]
```

### Dependency Graph

Visual representation of dependencies:

```
my_app (0.1.0)
├── kemal (~> 1.4.0)
│   ├── radix (~> 0.4.0)
│   └── exception_page (~> 0.3.0)
├── db (~> 0.11.0)
│   └── crystal-db (~> 0.11.0)
└── pg (~> 0.24.0)
    └── db (~> 0.11.0)
```

Helps identify:
- Direct vs transitive dependencies
- Potential conflicts
- Dependency bloat
- Update impact

## Publishing Shards

### Prerequisites

Before publishing:

1. **GitHub Repository**: Your shard must be hosted on GitHub
2. **shard.yml**: Must include all required fields
3. **README.md**: Clear documentation
4. **LICENSE**: Open source license file
5. **Tests**: Working test suite (recommended)

### Preparing Your Shard

**1. Complete shard.yml:**

```yaml
name: my_awesome_shard
version: 0.1.0
description: |
  A comprehensive description of what your shard does.
  Multiple lines are fine.

crystal: >= 1.0.0

dependencies:
  # List any runtime dependencies

development_dependencies:
  # List dev dependencies

authors:
  - Your Name <you@example.com>

license: MIT
repository: https://github.com/yourusername/my_awesome_shard
```

**2. Write a good README:**

```markdown
# My Awesome Shard

Brief description of what it does.

## Installation

Add this to your application's `shard.yml`:

\`\`\`yaml
dependencies:
  my_awesome_shard:
    github: yourusername/my_awesome_shard
    version: ~> 0.1.0
\`\`\`

## Usage

\`\`\`crystal
require "my_awesome_shard"

# Example code here
\`\`\`

## Contributing

1. Fork it
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

MIT License - see LICENSE file
```

**3. Tag a release on GitHub:**

```bash
git tag v0.1.0
git push origin v0.1.0
```

### Publishing via Web Interface

1. Visit [https://crystalshards.org](https://crystalshards.org)
2. Click "Sign In" (GitHub OAuth)
3. Click "Publish Shard"
4. Enter your GitHub repository URL: `https://github.com/yourusername/my_awesome_shard`
5. Click "Submit"

The system will:
- Validate your shard.yml
- Check for required files
- Index your shard
- Trigger documentation build on CrystalDocs.org
- Make your shard searchable

### Publishing via API

For automation (CI/CD pipelines):

```bash
# Obtain API token from your profile
export CRYSTALSHARDS_TOKEN="your_token_here"

# Submit shard
curl -X POST https://api.crystalshards.org/api/v1/shards \
  -H "Authorization: Bearer $CRYSTALSHARDS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "github_url": "https://github.com/yourusername/my_awesome_shard"
  }'
```

Response:
```json
{
  "message": "Shard submitted successfully",
  "status": "published",
  "shard": {
    "id": 1234,
    "name": "my_awesome_shard",
    "github_url": "https://github.com/yourusername/my_awesome_shard"
  }
}
```

### Automatic Updates

Once published, CrystalShards automatically:

1. **Syncs with GitHub** - Monitors for new releases
2. **Updates metadata** - Stars, forks, description
3. **Triggers docs** - Builds documentation on CrystalDocs.org
4. **Indexes versions** - Makes new versions searchable

No manual updates needed after initial publication!

### GitHub Webhooks (Optional)

For instant updates, configure webhook:

1. Go to your GitHub repo → Settings → Webhooks
2. Add webhook URL: `https://crystalshards.org/webhooks/github`
3. Content type: `application/json`
4. Events: "Just the push event"
5. Active: ✓

Now updates appear instantly on CrystalShards.

## Best Practices

### Naming Conventions

**Good names:**
- Short and descriptive: `http_client`, `json_parser`
- Indicate purpose: `stripe_api`, `postgres_adapter`
- Use underscores: `crystal_db` not `crystal-db`

**Avoid:**
- Generic names: `utils`, `helpers`
- Prefixes: `cr-*` (unnecessary in Crystal ecosystem)
- Trademark conflicts: Don't copy existing tools

### Versioning Strategy

Follow semantic versioning (semver):

```
MAJOR.MINOR.PATCH
  1  .  2  .  3

MAJOR: Breaking changes (v1.0.0 → v2.0.0)
MINOR: New features, backward compatible (v1.0.0 → v1.1.0)
PATCH: Bug fixes (v1.0.0 → v1.0.1)
```

**Version 0.x.y:**
- Pre-1.0 signals "not production ready"
- Breaking changes can occur in minor versions
- Reach 1.0.0 when API is stable

**Examples:**
- `0.1.0` - Initial release
- `0.2.0` - Added feature (may break API)
- `1.0.0` - First stable release
- `1.1.0` - New feature, backward compatible
- `1.1.1` - Bug fix
- `2.0.0` - Breaking change

### Documentation Quality

**Essential documentation:**

1. **Installation**: Clear `shard.yml` example
2. **Quick Start**: Simple working example
3. **API Reference**: Use Crystal's doc comments
4. **Examples**: Real-world use cases
5. **Contributing**: How others can help

**Crystal doc comments:**

```crystal
# Fetches user data from the API.
#
# Returns a `User` object if found, `nil` otherwise.
#
# ```
# user = api.fetch_user(123)
# puts user.name if user
# ```
def fetch_user(id : Int32) : User?
  # Implementation
end
```

These comments appear in auto-generated documentation.

### Dependency Management

**Keep dependencies minimal:**
- Each dependency adds maintenance burden
- More dependencies = more potential conflicts
- Consider stdlib alternatives first

**Pin versions appropriately:**
```yaml
dependencies:
  # For libraries you maintain together
  my_other_shard:
    github: me/other
    version: ~> 1.0

  # For stable, popular libraries
  kemal:
    github: kemalcr/kemal
    version: ~> 1.4.0

  # For unreleased features (temporary)
  experimental:
    github: user/experimental
    branch: feature-branch  # Not recommended for production
```

**Avoid:**
- Unpinned versions (no `version:` field)
- Git branches in production dependencies
- Circular dependencies

### Testing

Include comprehensive tests:

```crystal
# spec/my_shard_spec.cr
require "./spec_helper"

describe MyAwesomeShard do
  it "works correctly" do
    result = MyAwesomeShard.do_something
    result.should eq "expected"
  end

  it "handles errors" do
    expect_raises(MyAwesomeShard::Error) do
      MyAwesomeShard.invalid_operation
    end
  end
end
```

Run tests with:
```bash
crystal spec
```

### README Checklist

Ensure your README includes:

- [ ] Clear description of what the shard does
- [ ] Installation instructions with shard.yml example
- [ ] Quick start code example
- [ ] Link to full documentation
- [ ] Contributing guidelines
- [ ] License information
- [ ] CI/build status badges
- [ ] Usage examples for main features
- [ ] Requirements (Crystal version, system dependencies)

### License Selection

Popular open source licenses:

- **MIT**: Permissive, simple, most common
- **Apache 2.0**: Permissive with patent grant
- **BSD**: Permissive, similar to MIT
- **GPL**: Copyleft, requires derivatives be open source

Include a `LICENSE` file in your repository.

## API Usage

### Authentication

Obtain an API token:

1. Sign in to CrystalShards.org
2. Go to Profile → API Tokens
3. Generate a new token with appropriate scopes
4. Store securely (never commit to Git)

### Available Endpoints

**Search shards:**
```bash
curl "https://api.crystalshards.org/api/v1/search?q=http&sort_by=downloads"
```

**List all shards:**
```bash
curl "https://api.crystalshards.org/api/v1/shards?page=1&per_page=20"
```

**Get shard details:**
```bash
curl "https://api.crystalshards.org/api/v1/shards/kemal"
```

**Submit shard (authenticated):**
```bash
curl -X POST "https://api.crystalshards.org/api/v1/shards" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"github_url": "https://github.com/user/repo"}'
```

### Rate Limits

- **Anonymous**: 100 requests/hour
- **Authenticated**: 2,000 requests/hour
- **API Keys**: Up to 10,000 requests/hour

Check headers:
```
X-RateLimit-Limit: 2000
X-RateLimit-Remaining: 1950
X-RateLimit-Reset: 1640000000
```

### Complete API Documentation

See the [OpenAPI specification](../api/openapi.yml) for complete API documentation.

## Troubleshooting

### Common Issues

**"Shard not found"**

Shard hasn't been published yet. Make sure:
- GitHub repository is public
- Repository contains valid `shard.yml`
- Shard has been submitted to CrystalShards
- Allow time for indexing (5-10 minutes)

**"Version constraint conflict"**

Multiple dependencies require incompatible versions:

```
Error: Conflicting dependencies:
  - kemal requires db ~> 0.10.0
  - postgres requires db ~> 0.11.0
```

Solutions:
- Update dependencies to compatible versions
- Contact maintainers about version requirements
- Fork and adjust version constraints (temporary)

**"Failed to resolve dependencies"**

Common causes:
- Invalid version constraint syntax
- Circular dependencies
- Deleted or renamed repositories
- Private repositories

Check:
```bash
shards install --verbose
```

**"Crystal version mismatch"**

Shard requires different Crystal version:

```
Error: Shard requires Crystal >= 1.2.0 (you have 1.0.0)
```

Solutions:
- Upgrade Crystal: `brew upgrade crystal` (macOS)
- Use version-specific shard version
- Check shard changelog for compatible versions

**Documentation not appearing**

If docs aren't generated after publishing:

1. Check CrystalDocs.org build status
2. Verify repository contains Crystal source files
3. Ensure `crystal doc` runs locally
4. Check for syntax errors in doc comments
5. Allow 10-15 minutes for build completion

**Webhook not triggering**

If updates aren't appearing:

1. Check webhook configuration in GitHub
2. Verify webhook URL is correct
3. Check Recent Deliveries in GitHub
4. Ensure payload is `application/json`
5. Wait for next scheduled sync (every 6 hours)

### Getting Help

If you encounter issues:

1. **Check Status**: [status.crystalshards.org](https://status.crystalshards.org)
2. **Search Issues**: [GitHub Issues](https://github.com/crystalshards/crystalshards/issues)
3. **Ask Community**: [Crystal Forum](https://forum.crystal-lang.org)
4. **Email Support**: support@crystalshards.org

Include in bug reports:
- Crystal version (`crystal --version`)
- Shards version (`shards --version`)
- Full error message
- Steps to reproduce
- Your `shard.yml` (if relevant)

### Security Issues

For security vulnerabilities:
- Email: security@crystalshards.org
- Do not create public issues
- Include detailed description
- We aim to respond within 24 hours

## Next Steps

Now that you understand CrystalShards:

- **Explore**: Browse [popular shards](https://crystalshards.org/popular)
- **Read Docs**: Visit [CrystalDocs.org](https://crystaldocs.org) for API references
- **Publish**: Share your own shards with the community
- **Contribute**: Help improve CrystalShards [on GitHub](https://github.com/crystalshards/crystalshards)

## Additional Resources

- **Crystal Language**: [crystal-lang.org](https://crystal-lang.org)
- **Crystal Book**: [crystal-lang.org/reference](https://crystal-lang.org/reference)
- **API Documentation**: [docs/api/README.md](../api/README.md)
- **Community Forum**: [forum.crystal-lang.org](https://forum.crystal-lang.org)

---

**Last Updated**: 2025-10-09
**Guide Version**: 1.0.0

For feedback or corrections, please [open an issue](https://github.com/crystalshards/crystalshards/issues).
