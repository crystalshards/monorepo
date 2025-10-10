# Post-Event Review: Database Connection Username Error Outage

**Date**: 2025-10-10
**Duration**: ~6 hours (08:00 - 14:00 UTC estimated)
**Severity**: High (2/4 applications affected)
**Status**: Ongoing / In Resolution

## Executive Summary

CrystalShards.org and CrystalGigs.com experienced database connectivity issues due to incorrect database username ('app' instead of application-specific usernames like 'crystalshards', 'crystalgigs'). CrystalDocs.org and CrystalBits.org were unaffected or recovered earlier.

## Timeline

**2025-10-10 08:00 UTC** (estimated) - Issue begins
- Applications deployed with incorrect DATABASE_URL containing username 'app'
- CrystalShards and CrystalGigs unable to connect to their databases

**2025-10-10 13:42 UTC** - Investigation begins (Run #18408284133)
- Identified root cause: Terraform config using hardcoded 'app' username
- Fixed Terraform to use correct app-specific usernames from CNPG secrets

**2025-10-10 13:45 UTC** - First deployment (#11) with fix
- Terraform updated and deployed
- Kubernetes secrets updated correctly (verified via kubectl)
- CrystalDocs and CrystalBits became healthy
- **CrystalShards and CrystalGigs remained unhealthy**

**2025-10-10 13:51 UTC** - Manual pod restart attempts begin
- Created force-restart-pods.yml workflow
- Multiple attempts to restart pods via GitHub Actions
- Encountered issues: missing GCP auth plugin, non-existent worker deployments

**2025-10-10 13:56 UTC** - Final restart attempt (Run #18408695599)
- Workflow succeeded in triggering restart
- **Restart timed out after 5 minutes**
- Pods did not become healthy within timeout window

**2025-10-10 14:03 UTC** - Current state
- CrystalDocs.org: HEALTHY
- CrystalBits.org: HEALTHY
- CrystalGigs.com: HEALTHY (became healthy during investigation)
- CrystalShards.org: **STILL UNHEALTHY** (username 'app' error persists)
- **NEW**: CrystalShards showing Redis connection errors

## Root Cause Analysis

### Primary Cause
**Incorrect DATABASE_URL in Kubernetes secrets** - Terraform configuration was using hardcoded username 'app' instead of reading the correct username from CloudNativePG (CNPG) operator secrets.

**Code location**: `/workspaces/monorepo/terraform/modules/apps/main.tf` (lines 77-95)

**Before (incorrect)**:
```hcl
database_url = "postgres://app:${random_password.postgres_password.result}@${var.app_name}-postgres-rw:5432/${var.app_name}_${var.environment}"
```

**After (correct)**:
```hcl
database_url = "postgres://${data.kubernetes_secret.postgres_app.data.username}:${data.kubernetes_secret.postgres_app.data.password}@${var.app_name}-postgres-rw:5432/${data.kubernetes_secret.postgres_app.data.dbname}"
```

### Secondary Cause (Amplified Impact)
**Pods did not automatically restart when secrets changed** - Despite Terraform having `secret-hash` annotation mechanism (noted in deploy.yml line 192-193), pods did not restart to pick up new DATABASE_URL values.

This suggests:
1. The annotation mechanism may not be working as expected
2. Pods need manual restart to pick up secret changes
3. There may be a delay in Kubernetes propagating secret changes to pods

### Tertiary Issues Discovered
1. **Redis connection errors in CrystalShards** - Attempting to connect to 'shared-redis.infrastructure.svc.cluster.local:6379' which is refusing connections
2. **Worker deployments don't exist** - crystalshards-workers deployment not found (may be intentional)
3. **Manual restart workflow complexity** - Multiple iterations needed to get force-restart-pods workflow functioning

## Impact Assessment

### User Impact
- **CrystalShards.org**: Users unable to browse/search packages, view documentation, or register accounts
- **CrystalGigs.com**: Users unable to browse jobs or post job listings (recovered during investigation)
- **Traffic**: Unknown (metrics not available)
- **Duration**: ~6 hours estimated

### Business Impact
- Core product (CrystalShards) completely non-functional
- Job board functionality affected
- Reputation damage for "production-ready" platform
- Lost user engagement during outage window

### Technical Impact
- 50% of applications affected (2/4)
- Database connectivity broken for affected apps
- Deployment pipeline blocked further releases
- Emergency procedures needed for resolution

## What Went Well

1. **Rapid Root Cause Identification** - Identified Terraform username issue quickly via debugging
2. **Kubernetes Secrets Fixed Correctly** - Verified via kubectl that secrets contain correct values
3. **Partial Recovery** - 3/4 apps became healthy (CrystalDocs, CrystalGigs, CrystalBits)
4. **Created Reusable Workflow** - force-restart-pods.yml for future manual interventions
5. **Documentation in Real-Time** - Clear tracking via GitHub issue comments

## What Didn't Go Well

1. **Pods Didn't Auto-Restart** - Secret-hash annotation mechanism failed to trigger pod restarts
2. **Manual Restart Complexity** - Multiple workflow iterations needed (auth issues, plugin missing, deployment existence checks)
3. **No Monitoring Alerts** - No automated alerts for database connectivity failures
4. **Long Detection Time** - Issue may have existed for hours before investigation began
5. **Redis Issues Discovered** - Additional CrystalShards dependency problem revealed during investigation
6. **Insufficient Testing** - Terraform changes not validated in staging environment first

## Action Items

### Immediate (Do Now)

- [ ] **Trigger full deployment** to force CrystalShards pod restart (#52)
  - Owner: SRE Agent
  - Due: 2025-10-10 14:30 UTC
  - Action: Run deploy.yml workflow to force pod recreation

- [ ] **Investigate Redis connection error** in CrystalShards (#52)
  - Owner: SRE Agent
  - Due: 2025-10-10 15:00 UTC
  - Action: Check if shared-redis exists in infrastructure namespace

- [ ] **Verify all apps healthy** after deployment (#52, #53)
  - Owner: SRE Agent
  - Due: 2025-10-10 15:00 UTC
  - Action: Check all health endpoints return database:healthy

### Short-Term (This Week)

- [ ] **Add health check monitoring alerts** (#TBD)
  - Owner: SRE / DevOps
  - Due: 2025-10-15
  - Action: Configure Prometheus alerts for database connectivity failures

- [ ] **Test secret-hash annotation mechanism** (#TBD)
  - Owner: SRE
  - Due: 2025-10-15
  - Action: Verify pods auto-restart when secrets change, or implement alternative

- [ ] **Implement staging environment testing** (#TBD)
  - Owner: SRE / DevOps
  - Due: 2025-10-17
  - Action: Deploy Terraform changes to staging before production

- [ ] **Document manual restart runbook** (#TBD)
  - Owner: SRE
  - Due: 2025-10-15
  - Action: Create runbook for manually restarting pods when secrets change

### Long-Term (This Month)

- [ ] **Implement blue-green deployments** (#TBD)
  - Owner: DevOps
  - Due: 2025-10-31
  - Action: Zero-downtime deployment strategy for database changes

- [ ] **Add integration tests for database connectivity** (#TBD)
  - Owner: Backend Engineer
  - Due: 2025-10-31
  - Action: Test DATABASE_URL parsing and connection in CI/CD

- [ ] **Implement chaos engineering** (#TBD)
  - Owner: SRE
  - Due: 2025-11-15
  - Action: Regularly test failure scenarios (wrong credentials, network issues)

- [ ] **Review and improve deployment pipeline** (#TBD)
  - Owner: DevOps / SRE
  - Due: 2025-10-31
  - Action: Add validation steps, improve observability, implement rollback automation

## Prevention Measures

### Immediate
1. Always trigger full deployment after Terraform secret changes
2. Manually verify pod restarts via kubectl after secret changes
3. Check all application health endpoints after deployment

### Short-Term
1. Add Prometheus alerts for database connectivity
2. Implement automatic health check validation in CI/CD
3. Document and test secret update procedures

### Long-Term
1. Implement blue-green deployment strategy
2. Add integration tests for infrastructure dependencies
3. Implement chaos engineering to test failure scenarios
4. Add staging environment for Terraform testing

## Related Issues

- [#52](https://github.com/crystalshards/monorepo/issues/52) - Database connection issues (CrystalShards, CrystalGigs)
- [#53](https://github.com/crystalshards/monorepo/issues/53) - Health check failing for CrystalShards

## Related Commits

- [8d453f8](https://github.com/crystalshards/monorepo/commit/8d453f8) - fix(terraform): use correct database username from CNPG secrets
- [2cec0ba](https://github.com/crystalshards/monorepo/commit/2cec0ba) - feat(ci): add workflow to force restart pods
- [d6c9d00](https://github.com/crystalshards/monorepo/commit/d6c9d00) - fix(ci): use correct GCP auth method
- [8df0421](https://github.com/crystalshards/monorepo/commit/8df0421) - fix(ci): install gke-gcloud-auth-plugin
- [db0717f](https://github.com/crystalshards/monorepo/commit/db0717f) - fix(ci): handle non-existent worker deployments

## Monitoring Dashboards

- CrystalShards Health: https://crystalshards.org/api/health
- CrystalDocs Health: https://crystaldocs.org/api/health
- CrystalGigs Health: https://crystalgigs.com/api/health
- CrystalBits Health: https://crystalbits.org/api/health

## Lessons Learned

1. **Secret changes require explicit pod restarts** - Don't rely on annotation mechanisms alone
2. **Test infrastructure changes in staging** - Even simple Terraform changes can have widespread impact
3. **Monitor all critical dependencies** - Database, Redis, and other services need health checks
4. **Automate health verification** - Manual checks after deployment are error-prone
5. **Document emergency procedures** - Having runbooks speeds up incident response

## Conclusion

This outage was caused by incorrect DATABASE_URL configuration in Terraform, which was fixed but not properly applied due to pods not restarting automatically. The next step is to trigger a full deployment to force pod recreation and verify all applications are healthy.

The incident revealed several systemic issues:
- Lack of automated monitoring and alerting
- Insufficient testing of infrastructure changes
- Pod restart mechanisms not working as expected
- Missing staging environment for validation

Implementing the action items above will prevent similar outages in the future.

---

**Document Status**: Living document, updated during incident resolution
**Last Updated**: 2025-10-10 14:05 UTC
**Next Review**: After CrystalShards becomes healthy
