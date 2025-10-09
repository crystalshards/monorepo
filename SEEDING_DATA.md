# Seeding Data for CrystalShards Platform

This guide explains how to populate the CrystalShards platform applications with sample data for development and testing.

## Overview

Each application in the monorepo has its own seed script that populates realistic sample data:

- **CrystalShards** (`apps/crystalshards/`) - Popular Crystal shards with version history
- **CrystalDocs** (`apps/crystaldocs/`) - Documentation entries for the seeded shards
- **CrystalGigs** (`apps/crystalgigs/`) - Crystal developer job postings
- **CrystalBits** (`apps/crystalbits/`) - Blog posts about Crystal

## Prerequisites

Before running seed scripts, ensure:

1. Databases are created and migrated
2. Applications are properly configured
3. Dependencies are installed (`shards install`)

## Running Seed Scripts

### CrystalShards

Seeds 12 popular Crystal shards with realistic version history, GitHub stats, and metadata.

```bash
cd apps/crystalshards
lucky db.seed.sample_data
```

**Seeded Data:**
- lucky (3 versions)
- kemal (3 versions)
- amber (2 versions)
- granite (3 versions)
- jennifer (3 versions)
- ameba (2 versions)
- spec-kemal (2 versions)
- crystal-redis (2 versions)
- crystal-pg (3 versions)
- http-client-digest_auth (2 versions)
- jwt (2 versions)
- spectator (2 versions)

**Total:** 12 shards, 29 versions

### CrystalDocs

Seeds documentation entries for the same shards with build statistics and version info.

```bash
cd apps/crystaldocs
lucky db.seed.sample_data
```

**Seeded Data:**
- 11 documentation packages
- Multiple versions per package
- Build status, file counts, and storage paths
- Realistic view counts

### CrystalGigs

Seeds 6 Crystal developer job postings covering different experience levels and job types.

```bash
cd apps/crystalgigs
lucky db.seed.sample_data
```

**Seeded Data:**
- Senior Crystal Backend Engineer (remote, $150k-$200k)
- Crystal Developer - Remote (remote, $120k-$160k, featured)
- Full Stack Developer (Crystal + React) (remote, $110k-$145k)
- Junior Crystal Developer (onsite NYC, $70k-$90k)
- Freelance Crystal Consultant (remote, $100-$200/hr)
- Crystal Platform Engineer (remote, $140k-$180k)

### CrystalBits

Seeds 6 blog posts about Crystal language, frameworks, and ecosystem.

```bash
cd apps/crystalbits
lucky db.seed.sample_data
```

**Seeded Data:**
- "Crystal 1.0: A New Era for the Language" (featured)
- "Building High-Performance APIs with Lucky Framework"
- "Crystal vs Go vs Rust: Performance Comparison" (featured)
- "Migrating from Ruby to Crystal: A Case Study"
- "Top 10 Crystal Shards You Should Know About" (featured)
- "Understanding Crystal's Type System"

## Seed All Applications

To seed all applications at once, run:

```bash
cd /workspaces/monorepo
./scripts/seed-all.sh
```

Or manually:

```bash
for app in crystalshards crystaldocs crystalgigs crystalbits; do
  echo "Seeding $app..."
  cd apps/$app
  lucky db.seed.sample_data
  cd ../..
done
```

## Idempotency

All seed scripts are idempotent - they check if records already exist before creating them. This means you can safely run the scripts multiple times without creating duplicates.

Each script uses uniqueness checks:
- **CrystalShards:** Checks shard name
- **CrystalDocs:** Checks package name
- **CrystalGigs:** Checks title + company name
- **CrystalBits:** Checks slug

## Clearing Data

To reset and reseed:

```bash
cd apps/[app-name]
lucky db.drop
lucky db.create
lucky db.migrate
lucky db.seed.sample_data
```

Or use the helper script:

```bash
./scripts/reset-and-seed-all.sh
```

## Development Workflow

### Initial Setup

```bash
# 1. Create and migrate all databases
for app in crystalshards crystaldocs crystalgigs crystalbits; do
  cd apps/$app
  lucky db.create
  lucky db.migrate
  cd ../..
done

# 2. Seed all applications
./scripts/seed-all.sh
```

### Testing Specific Features

```bash
# Seed just the app you're working on
cd apps/crystalshards
lucky db.seed.sample_data
```

## Customizing Seed Data

To modify seed data, edit the respective `sample_data.cr` files:

- `/workspaces/monorepo/apps/crystalshards/tasks/db/seed/sample_data.cr`
- `/workspaces/monorepo/apps/crystaldocs/tasks/db/seed/sample_data.cr`
- `/workspaces/monorepo/apps/crystalgigs/tasks/db/seed/sample_data.cr`
- `/workspaces/monorepo/apps/crystalbits/tasks/db/seed/sample_data.cr`

After editing, format the files:

```bash
cd apps/[app-name]
crystal tool format tasks/db/seed/sample_data.cr
```

## Seed Script Features

### Common Patterns

All seed scripts follow these conventions:

1. **Idempotent Operations** - Check for existing records before creating
2. **Realistic Data** - Use actual Crystal ecosystem examples
3. **Timestamps** - Include realistic created_at/updated_at values
4. **Relationships** - Properly link related records (shards to versions, etc.)
5. **Console Output** - Print progress messages

### Helper Methods

Each seed script includes helper methods for creating records:

- `create_shard_with_versions` - Creates shard with all its versions
- `create_doc_with_versions` - Creates documentation with version history
- `create_job` - Creates job posting with all fields
- `create_post` - Creates blog post with slug generation

## Troubleshooting

### Database Connection Errors

Ensure PostgreSQL is running and credentials are correct in `config/database.cr`.

### Validation Errors

Check that all required fields are provided in seed data. Review operation validations in `src/operations/save_*.cr`.

### Duplicate Key Errors

Seed scripts should handle this automatically via uniqueness checks. If you encounter these errors, clear the database and reseed.

### Missing Dependencies

Ensure all shards are installed:

```bash
cd apps/[app-name]
shards install
```

## Production Considerations

These seed scripts are designed for **development and testing only**. Do not run them in production.

For production data:
1. Create separate migration scripts
2. Use proper data import pipelines
3. Implement rate limiting for bulk operations
4. Add proper error handling and rollback mechanisms

## Additional Resources

- [Lucky Framework Tasks](https://luckyframework.org/guides/command-line-tasks/custom-tasks)
- [Avram Operations](https://luckyframework.org/guides/database/saving-records)
- [Crystal Standard Library](https://crystal-lang.org/api/)

## Summary

The seeding system provides:
- **12 Crystal shards** with 29 total versions
- **11 documentation packages** with multiple versions each
- **6 job postings** covering different roles and experience levels
- **6 blog posts** about Crystal and its ecosystem

All data is realistic, production-quality sample content that demonstrates the full capabilities of the CrystalShards platform.
