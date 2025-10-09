# Post-Event Review: CrystalShards.org Health Check Failures

**Date**: 2025-10-09
**Incident**: Production pods failing health checks, serving JSON instead of HTML UI
**Status**: IN PROGRESS - INVESTIGATION
**Severity**: CRITICAL - Production down
**Duration**: Unknown (investigation started 2025-10-09)

## Executive Summary

CrystalShards.org production pods are failing health checks and not serving the HTML UI. The `/api/health` endpoint returns "upstream request timeout" and production deployments time out after 20 minutes. The root cause appears to be connectivity issues between application pods and critical infrastructure (PostgreSQL CNPG cluster and/or Redis).

## Timeline

- **Unknown**: Production deployments start failing (GitHub Actions deployment workflow #266-270 all failed)
- **2025-10-09 22:00 UTC**: Issue #24 created reporting health check failures
- **2025-10-09 22:20 UTC**: SRE agent assigned to investigate
- **2025-10-09 22:25 UTC**: RBAC permissions blocker identified - cannot access cluster directly
- **2025-10-09 22:30 UTC**: Code review analysis and runbook creation in progress

## Impact

### User Impact
- **Total production outage**: CrystalShards.org not accessible to users
- `curl https://crystalshards.org` returns JSON stub instead of HTML UI
- All package browsing, search, and documentation features unavailable

### Business Impact
- Complete service unavailability
- Cannot onboard new Crystal developers to ecosystem
- Damage to platform credibility and adoption

## Root Cause Analysis

### Confirmed Facts

1. **Health check implementation** (`apps/crystalshards/src/actions/api/health/show.cr`):
   - Tests database connectivity: `AppDatabase.run { |db| db.query_one "SELECT 1", as: Int32 }`
   - Tests Redis connectivity: `redis.ping`
   - Returns 503 if either service is unhealthy

2. **Database configuration** (`apps/crystalshards/terraform/resource.kubernetes_secret.crystalshards_secrets.tf`):
   - DATABASE_URL: `postgresql://app:PASSWORD@crystalshards-postgres-rw:5432/crystalshards_production`
   - Uses CNPG-generated secret: `crystalshards-postgres-app`
   - Connects to CNPG read-write service: `crystalshards-postgres-rw`

3. **Redis configuration**:
   - REDIS_URL: `redis://shared-redis.infrastructure.svc.cluster.local:6379/0`
   - Shared Redis in `infrastructure` namespace

4. **Network policy** (`resource.kubernetes_network_policy.allow_infrastructure_access.tf`):
   - Allows egress to infrastructure namespace
   - Allows DNS (UDP 53)
   - Allows HTTPS (TCP 443)
   - **CRITICAL**: Policy is egress-only, pod selector is empty (applies to all pods)

5. **Deployment configuration**:
   - Health check timeout: 10 seconds
   - Initial delay: 120s (liveness), 60s (readiness)
   - Failure threshold: 6 attempts

6. **CNPG Cluster** (`resource.kubectl_manifest.crystalshards_postgres.tf`):
   - 2 instances
   - Database: `crystalshards_production`
   - Owner: `crystalshards` (but app uses `app` user from CNPG-generated secret)
   - Service: `crystalshards-postgres-rw` (read-write)

### Likely Root Causes (Ranked by Probability)

#### 1. CNPG Cluster Not Ready or Not Existing (HIGHEST PROBABILITY)
**Evidence**:
- Terraform deployments timing out after 20 minutes
- Health checks consistently failing
- CNPG cluster might not have been created or is stuck in non-ready state

**Why this happens**:
- CNPG cluster creation can fail if operator is not installed
- Database initialization can timeout in GKE Autopilot
- Storage provisioning issues
- Secret generation delays

**Diagnosis commands** (requires cluster access):
```bash
# Check if CNPG cluster exists and is ready
kubectl get clusters.postgresql.cnpg.io -n crystalshards
kubectl get clusters.postgresql.cnpg.io crystalshards-postgres -n crystalshards -o yaml

# Check CNPG pods
kubectl get pods -n crystalshards -l cnpg.io/cluster=crystalshards-postgres

# Check if app secret was generated
kubectl get secret crystalshards-postgres-app -n crystalshards

# Check CNPG operator
kubectl get pods -n cnpg-system
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg --tail=100
```

#### 2. Network Policy Blocking Database Access (MEDIUM PROBABILITY)
**Evidence**:
- Network policy allows egress to infrastructure namespace
- BUT: PostgreSQL is in the SAME namespace (crystalshards), not infrastructure
- Network policy is egress-only - might be blocking database within same namespace

**Why this happens**:
- Egress policy may not have rule for same-namespace communication
- Missing egress rule for PostgreSQL port 5432

**Diagnosis commands**:
```bash
# Check network policies
kubectl get networkpolicies -n crystalshards
kubectl describe networkpolicy allow-infrastructure-access -n crystalshards

# Test connectivity from app pod to database
kubectl exec -n crystalshards deployment/crystalshards-api -- nc -zv crystalshards-postgres-rw 5432
kubectl exec -n crystalshards deployment/crystalshards-api -- nslookup crystalshards-postgres-rw
```

**Fix**: Add egress rule for same-namespace database access:
```yaml
# Add to network policy
egress:
  # Existing rules...

  # Allow PostgreSQL access within same namespace
  - to:
      - podSelector:
          matchLabels:
            cnpg.io/cluster: crystalshards-postgres
    ports:
      - protocol: TCP
        port: 5432
```

#### 3. Redis Not Accessible from CrystalShards Namespace (LOW PROBABILITY)
**Evidence**:
- Redis is in infrastructure namespace
- Network policy DOES allow egress to infrastructure namespace
- Less likely to be the blocker

**Diagnosis commands**:
```bash
# Check Redis status
kubectl get redis -n infrastructure
kubectl get pods -n infrastructure -l app=redis

# Test connectivity from app pod
kubectl exec -n crystalshards deployment/crystalshards-api -- nc -zv shared-redis.infrastructure.svc.cluster.local 6379
kubectl exec -n crystalshards deployment/crystalshards-api -- nslookup shared-redis.infrastructure.svc.cluster.local
```

#### 4. Database Secret Not Generated or Incorrect (MEDIUM PROBABILITY)
**Evidence**:
- Terraform uses data source to fetch CNPG-generated secret
- If secret doesn't exist, Terraform plan/apply would fail
- Recent deployments timing out suggests Terraform is stuck

**Diagnosis commands**:
```bash
# Check if secret exists
kubectl get secret crystalshards-secrets -n crystalshards

# Inspect secret contents (base64 encoded)
kubectl get secret crystalshards-secrets -n crystalshards -o yaml

# Decode DATABASE_URL
kubectl get secret crystalshards-secrets -n crystalshards -o jsonpath='{.data.database_url}' | base64 -d
```

#### 5. RBAC Permissions Not Applied to Agent (CONFIRMED BLOCKER)
**Evidence**:
- Agent running as `system:serviceaccount:claude:default`
- No permissions to list pods, namespaces, or any cluster resources
- RBAC configuration exists but not applied

**Impact**: Cannot diagnose or fix issues directly - requires cluster admin intervention

**Fix**: Apply RBAC configuration:
```bash
# Cluster admin must run:
kubectl apply -f /workspaces/monorepo/kubernetes-agent-rbac.yaml

# OR via Terraform:
cd /workspaces/monorepo/terraform
terraform apply -target=module.agent
```

### Database User Mismatch (Potential Issue)
**Observation**: CNPG cluster defines owner as `crystalshards`, but connection string uses `app` user from CNPG-generated secret. This is likely intentional (CNPG creates both owner and app users), but worth verifying.

## Action Items

### Immediate Actions (CRITICAL - Required to Restore Service)

1. **Apply RBAC permissions** (Cluster Admin)
   - Owner: Cluster Admin
   - Priority: CRITICAL
   - Due: Immediately
   - Action: `kubectl apply -f kubernetes-agent-rbac.yaml`

2. **Verify CNPG cluster status** (SRE Agent - after RBAC)
   - Owner: SRE Agent
   - Priority: CRITICAL
   - Due: Within 5 minutes of RBAC application
   - Action: Run diagnosis commands from "Root Cause #1"

3. **Fix network policy if needed** (SRE Agent)
   - Owner: SRE Agent
   - Priority: CRITICAL
   - Due: Within 15 minutes
   - Action: Add same-namespace database egress rule if missing

4. **Verify pod health** (SRE Agent)
   - Owner: SRE Agent
   - Priority: CRITICAL
   - Due: Within 20 minutes
   - Action: Check pod logs, test health endpoint, verify UI loads

### Short-Term Actions (Within 24 Hours)

5. **Add connectivity tests to CI/CD** (Backend Engineer)
   - Owner: Backend Engineer
   - Priority: HIGH
   - Due: 2025-10-10
   - Action: Create pre-deployment smoke tests for database/Redis connectivity

6. **Improve health check logging** (Backend Engineer)
   - Owner: Backend Engineer
   - Priority: HIGH
   - Due: 2025-10-10
   - Action: Log detailed error messages instead of generic "unhealthy"

7. **Add monitoring alerts** (SRE Agent)
   - Owner: SRE Agent
   - Priority: HIGH
   - Due: 2025-10-10
   - Action: Create Prometheus alerts for health check failures

### Long-Term Actions (Within 1 Week)

8. **Document infrastructure dependencies** (SRE Agent)
   - Owner: SRE Agent
   - Priority: MEDIUM
   - Due: 2025-10-16
   - Action: Create architecture diagram showing all service dependencies

9. **Implement deployment health verification** (Backend Engineer)
   - Owner: Backend Engineer
   - Priority: MEDIUM
   - Due: 2025-10-16
   - Action: Add post-deployment health check to CI/CD pipeline

10. **Review and optimize network policies** (SRE Agent)
    - Owner: SRE Agent
    - Priority: MEDIUM
    - Due: 2025-10-16
    - Action: Audit all network policies for correctness and completeness

## What Went Well

- Health check implementation correctly identifies failures (503 status)
- Network policy exists and is mostly correct (allows infrastructure access)
- RBAC configuration already defined (just not applied)
- Comprehensive Terraform configuration for infrastructure
- Issue was reported quickly (#24)

## What Didn't Go Well

- Production deployment failures not caught in pre-production environment
- No staging environment to test deployments before production
- RBAC permissions not applied during initial cluster setup
- No monitoring/alerting for health check failures
- Agent cannot self-diagnose due to missing permissions
- Deployment workflow timeouts after 20 minutes without clear failure messages

## Lessons Learned

1. **Always verify RBAC before deployment**: Ensure all service accounts have necessary permissions
2. **Staging environment is critical**: Should have caught this before production
3. **Network policies need same-namespace rules**: Don't forget intra-namespace communication
4. **Health checks need detailed logging**: Generic "unhealthy" messages don't help debugging
5. **CI/CD should verify connectivity**: Pre-deployment smoke tests would have caught this

## Prevention Measures

### Immediate (This Week)
- Apply RBAC permissions to agent
- Fix network policy if needed
- Add health check logging
- Create monitoring alerts

### Short-Term (This Month)
- Implement pre-deployment connectivity tests in CI/CD
- Add post-deployment verification step
- Document all infrastructure dependencies

### Long-Term (This Quarter)
- Create staging environment that mirrors production
- Implement comprehensive observability (metrics, logs, traces)
- Add automated rollback on health check failures
- Create incident response playbook

## Related Issues

- GitHub Issue #24: https://github.com/crystalshards/monorepo/issues/24
- Deployment workflow failures: #266, #267, #268, #269, #270

## Incident Commander Notes

**Next Steps**:
1. Waiting for cluster admin to apply RBAC permissions
2. Once RBAC applied, will run comprehensive diagnostics
3. Will implement fix based on root cause identified
4. Will verify HTML UI is serving correctly
5. Will update this PER with final root cause and resolution

**Status**: Investigation blocked on RBAC permissions - runbook created for cluster admin
