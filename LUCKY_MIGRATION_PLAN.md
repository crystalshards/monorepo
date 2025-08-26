# Lucky Framework Migration Plan

## Overview
Migrate existing Kemal-based applications to Lucky framework for better architecture, type safety, and maintainability.

## Migration Strategy

### Phase 1: Infrastructure Setup
1. ✅ Create simple-lucky-registry app (already done)
2. Update shard.yml files to replace Kemal with Lucky dependencies
3. Set up Lucky configuration files (config/, db/migrations/, etc.)
4. Create Lucky-compatible directory structure

### Phase 2: Core Application Migration
1. **Database Layer (Avram ORM)**
   - Convert repository classes to Avram models
   - Migrate database connection setup to Avram
   - Update queries to use Avram query syntax
   
2. **HTTP Layer (Lucky Actions)**
   - Convert Kemal route handlers to Lucky actions
   - Migrate middleware to Lucky handlers
   - Update request/response handling

3. **View Layer (Lucky Pages)**
   - Convert HTML generation to Lucky pages
   - Migrate templates and layouts
   - Update asset handling

### Phase 3: Application-Specific Migration

#### shards-registry (Priority 1)
```crystal
# Current Kemal structure:
get "/api/shards" do |env|
  # handler code
end

# Lucky structure:
class Api::Shards::Index < ApiAction
  get "/api/shards" do
    # handler code
  end
end
```

**Components to migrate:**
- [x] Authentication middleware → Lucky authentication
- [x] Rate limiting → Lucky handlers  
- [x] Metrics collection → Lucky handlers
- [x] Shard submission service
- [x] Search functionality
- [x] Analytics service

#### gigs (Priority 2)  
**Components to migrate:**
- [x] Stripe integration
- [x] Job repository → Avram models
- [x] Payment flow handlers
- [x] Job listing pages

#### shards-docs (Priority 3)
**Components to migrate:**
- [x] Documentation build service
- [x] Storage integration (MinIO)  
- [x] Parser service
- [x] Documentation display pages

#### admin (Priority 4)
**Components to migrate:**
- [x] WebSocket live updates
- [x] Admin authentication
- [x] Dashboard pages
- [x] Management interfaces

#### worker (Priority 5)
**Components to migrate:**
- [x] Background job processing
- [x] Sidekiq integration
- [x] Analytics cleanup jobs

## Migration Steps per Application

### 1. Prepare Lucky Structure
```bash
# For each app (e.g., shards-registry):
cd apps/shards-registry-lucky  # Create new Lucky version
lucky init.custom .
```

### 2. Update Dependencies
```yaml
# shard.yml changes:
dependencies:
  lucky: 
    github: luckyframework/lucky
    version: ~> 1.0
  avram:
    github: luckyframework/avram  
    version: ~> 1.0
  # Remove kemal dependency
```

### 3. Database Migration (Avram)
```crystal
# Convert repository pattern:
class ShardRepository
  # Current PG.connect usage
end

# To Avram model:
class Shard < BaseModel
  table do
    column name : String
    column description : String?
    # ...
  end
end
```

### 4. Route Migration
```crystal
# Current Kemal routes:
get "/api/shards" do |env|
  # logic
end

# Lucky actions:
class Api::Shards::Index < ApiAction
  get "/api/shards" do
    json ShardQuery.new.to_json
  end
end
```

### 5. Middleware Migration
```crystal
# Current Kemal middleware:
add_handler AuthMiddleware.new

# Lucky handlers:
class AuthHandler < Lucky::BaseHandler
  def call(context)
    # auth logic
    call_next(context)
  end
end
```

## Benefits of Migration

1. **Type Safety**: Lucky provides compile-time type checking for routes, params, and database queries
2. **Better Architecture**: Lucky enforces better separation of concerns with actions, pages, and models
3. **Database Type Safety**: Avram provides type-safe database operations
4. **Built-in Features**: Authentication, CSRF protection, asset compilation out of the box
5. **Development Experience**: Better error messages, helpful compiler feedback
6. **Testing**: Lucky has excellent testing support with built-in test helpers

## Risk Mitigation

1. **Incremental Migration**: Migrate one app at a time, starting with simple-registry
2. **Parallel Development**: Keep Kemal versions running while developing Lucky versions  
3. **Feature Parity**: Ensure all existing functionality is preserved
4. **Database Compatibility**: Avram can work with existing PostgreSQL schema
5. **API Compatibility**: Maintain same API endpoints for client compatibility

## Timeline

- **Week 1**: Complete shards-registry migration
- **Week 2**: Complete gigs migration  
- **Week 3**: Complete shards-docs migration
- **Week 4**: Complete admin and worker migrations

## Testing Strategy

1. **Unit Tests**: Migrate existing Crystal specs to Lucky testing framework
2. **Integration Tests**: Update HTTP endpoint tests for Lucky actions
3. **E2E Tests**: Existing Playwright tests should work without changes
4. **Performance Tests**: Compare response times between Kemal and Lucky versions

## Deployment Strategy

1. **Blue-Green Deployment**: Deploy Lucky versions alongside Kemal versions
2. **Feature Flags**: Use environment variables to toggle between versions
3. **Gradual Rollout**: Migrate traffic percentage by percentage  
4. **Rollback Plan**: Keep Kemal versions available for quick rollback

## Configuration Changes

### Docker
```dockerfile
# Update Dockerfile to include Lucky requirements
RUN shards install --production
RUN crystal build --release src/app_name.cr
```

### Kubernetes
```yaml
# Update deployment manifests for Lucky apps
# Lucky apps may need different resource requirements
```

### CI/CD
```yaml
# Update build steps for Lucky compilation
- name: Build Lucky app
  run: |
    shards install
    lucky build.release
```

## Next Actions

1. ✅ Create this migration plan
2. ⏳ Fix current CI issues to ensure stable baseline
3. ⏳ Start with simple-registry Lucky migration
4. Test and validate Lucky version works correctly  
5. Gradually migrate other applications following same pattern

---

This migration will modernize the codebase and provide a more maintainable foundation for future development while preserving all existing functionality.