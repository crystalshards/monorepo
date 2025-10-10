# Post-Event Review: Database and Redis Connectivity Outage

**Date:** 2025-10-10
**Severity:** Critical (SEV-1)
**Duration:** Ongoing (investigation started 2025-10-10)
**Impact:** All applications unable to function - no database or Redis connectivity

## Executive Summary

All four CrystalShards platform applications (CrystalShards.org, CrystalDocs.org, CrystalGigs.com, CrystalBits.org) experienced complete service outage due to database and Redis connectivity failures. Investigation revealed infrastructure configuration issues in Terraform definitions.

## Timeline

| Time (UTC) | Event |
|------------|-------|
| Unknown | Infrastructure deployed via Terraform |
| Unknown | Applications deployed but failing to start |
| 2025-10-10 09:34 | Issue #52 and #53 reported - database and Redis connectivity failures |
| 2025-10-10 09:40 | Investigation started - agent SRE begins diagnosis |
| 2025-10-10 09:45 | Limited kubectl permissions identified - using IaC analysis instead |
| 2025-10-10 09:55 | Root cause identified for PostgreSQL issue |
| 2025-10-10 10:00 | Creating fixes for both issues |

## Impact Assessment

### User Impact
- **Complete service outage** for all four platform applications
- Zero users able to access any functionality
- All API endpoints returning errors
- Background workers non-functional

### Business Impact
- Complete platform unavailability
- No package registry access for Crystal developers
- No documentation browsing capability
- No job board access
- No blog access

### Technical Impact
- All application pods in CrashLoopBackOff or failing health checks
- PostgreSQL clusters deployed but applications cannot connect
- Redis cluster deployed but CrystalShards cannot connect
- All background workers unable to process jobs

## Root Cause Analysis

### Issue #52: PostgreSQL Connectivity

**Root Cause:** DATABASE_URL constructed with hardcoded username instead of reading from CNPG-generated secret

**Details:**
- CloudNativePG creates secrets with BOTH `username` and `password` fields
- Terraform code only reads `password` field
- Username hardcoded as `app` in DATABASE_URL
- Actual username varies by application (e.g., `crystalshards`, `crystaldocs`, etc.)
- CNPG bootstrap initdb configuration sets owner to app-specific name, not `app`

**Affected Files:**
- `/workspaces/monorepo/apps/crystalshards/terraform/resource.kubernetes_secret.crystalshards_secrets.tf`
- `/workspaces/monorepo/apps/crystaldocs/terraform/resource.kubernetes_secret.crystaldocs_secrets.tf`
- `/workspaces/monorepo/apps/crystalgigs/terraform/resource.kubernetes_secret.crystalgigs_secrets.tf`
- `/workspaces/monorepo/apps/crystalbits/terraform/resource.kubernetes_secret.crystalbits_secrets.tf`

**Example Error:**
```hcl
# WRONG - hardcoded username
database_url = "postgresql://app:${data.kubernetes_secret.crystalshards_postgres_app.data["password"]}@..."

# CORRECT - read username from secret
database_url = "postgresql://${data.kubernetes_secret.crystalshards_postgres_app.data["username"]}:${data.kubernetes_secret.crystalshards_postgres_app.data["password"]}@..."
```

### Issue #53: Redis Connectivity

**Status:** Under investigation

**Initial Analysis:**
- Redis cluster deployed in infrastructure namespace as `shared-redis`
- REDIS_URL configured correctly in crystalshards secrets
- Network policy allows egress on port 6379 to infrastructure namespace
- Need to verify Redis operator created the service correctly
- Need to verify service name matches configuration

## What Went Well

1. **Infrastructure as Code:** All configuration in Terraform made investigation possible without direct cluster access
2. **Network Policies:** Correctly configured to allow cross-namespace access
3. **Secret Management:** Proper use of data sources to read operator-generated secrets
4. **Issue Tracking:** Issues clearly documented in GitHub

## What Didn't Go Well

1. **No Pre-Deployment Testing:** Infrastructure deployed without verifying connectivity
2. **Hardcoded Assumptions:** Username hardcoded instead of reading from secret
3. **Missing Validation:** No integration tests to verify database connectivity before marking deployment successful
4. **Limited Observability:** Agent pod has no kubectl permissions to investigate live cluster
5. **No Rollback:** No previous working state to roll back to

## Action Items

### Immediate (Do Now)

- [ ] **Fix DATABASE_URL in all 4 apps** - Read username from CNPG secret (Owner: Agent SRE, Due: 2025-10-10)
- [ ] **Verify Redis service name** - Confirm Redis operator created correct service (Owner: Agent SRE, Due: 2025-10-10)
- [ ] **Apply Terraform changes** - Run terraform apply to update secrets (Owner: DevOps, Due: 2025-10-10)
- [ ] **Verify application pods start** - Confirm health checks pass (Owner: Agent SRE, Due: 2025-10-10)
- [ ] **Test database connectivity** - Verify all apps can query PostgreSQL (Owner: Agent SRE, Due: 2025-10-10)
- [ ] **Test Redis connectivity** - Verify CrystalShards can connect to Redis (Owner: Agent SRE, Due: 2025-10-10)

### Short-term (This Week)

- [ ] **Add integration tests** - Test database connectivity in CI/CD before deploy (Owner: DevOps, Due: 2025-10-15)
- [ ] **Add Redis connectivity tests** - Test Redis connectivity in CI/CD (Owner: DevOps, Due: 2025-10-15)
- [ ] **Grant kubectl permissions to agent** - Allow agent to investigate live cluster issues (Owner: Platform, Due: 2025-10-15)
- [ ] **Add smoke tests** - Post-deployment verification of all services (Owner: DevOps, Due: 2025-10-17)
- [ ] **Document secret structure** - Add comments about CNPG secret fields (Owner: Agent SRE, Due: 2025-10-12)

### Long-term (This Month)

- [ ] **Implement automated rollback** - Auto-rollback on failed health checks (Owner: Platform, Due: 2025-10-30)
- [ ] **Add connectivity monitoring** - Alerts for database/Redis connection failures (Owner: SRE, Due: 2025-10-30)
- [ ] **Create runbook** - Document infrastructure troubleshooting procedures (Owner: SRE, Due: 2025-10-25)
- [ ] **Review all data sources** - Audit all secret reading code for similar issues (Owner: Agent SRE, Due: 2025-10-20)

## Prevention Measures

### Process Changes
1. **Mandatory smoke tests** - All deployments must pass connectivity tests
2. **Staging environment** - Test infrastructure changes in non-prod first
3. **Incremental rollouts** - Deploy to one app at a time, verify before next

### Technical Changes
1. **CI/CD validation** - Add database connectivity tests to pipeline
2. **Automated verification** - Post-apply Terraform tests to verify resources
3. **Better observability** - Grant agent appropriate cluster permissions

### Documentation Changes
1. **Secret structure documentation** - Document all operator-generated secret formats
2. **Troubleshooting guides** - Create runbooks for common infrastructure issues
3. **Architecture decision records** - Document why specific configurations were chosen

## Lessons Learned

1. **Always read all fields from operator-generated secrets** - Don't assume field values
2. **Test connectivity before marking deployment successful** - Health checks aren't enough
3. **Grant appropriate permissions** - Agent needs kubectl access to investigate production issues
4. **Infrastructure testing is critical** - Can't rely on "it should work" assumptions
5. **Document operator behaviors** - Each operator (CNPG, Redis, MinIO) has its own conventions

## Related Issues

- Issue #52: PostgreSQL connectivity failures (all apps)
- Issue #53: Redis connectivity failures (CrystalShards)

## Monitoring and Alerting Gaps

1. **No database connection alerts** - Should alert on connection failures
2. **No Redis connection alerts** - Should alert on Redis unavailability
3. **No pod crash alerts** - Should alert on CrashLoopBackOff immediately
4. **No health check alerts** - Should alert on repeated health check failures

## Follow-up Required

- Verify all applications fully functional after fixes applied
- Run full end-to-end tests on all four applications
- Update deployment documentation with new validation steps
- Schedule postmortem review meeting with team
- Share learnings with broader engineering organization

---

**Status:** Investigation in progress, fixes being developed
**Next Update:** After fixes applied and verified
**Owner:** Agent SRE
**Reviewers:** DevOps team, Platform team
