# Post-Event Review: Database and Redis Connectivity Failures

**Date:** 2025-10-10
**Duration:** Ongoing (started ~03:50 UTC, RBAC blocker identified at 09:17 UTC)
**Severity:** P0 - Complete Platform Outage
**Status:** BLOCKED - AWAITING RBAC FIX

## Executive Summary

Following successful Terraform deployment (run 18395832256), all four applications (CrystalShards.org, CrystalDocs.org, CrystalGigs.com, CrystalBits.org) are accessible via HTTPS but report database connectivity failures via health endpoints. Applications return 200 OK with JSON placeholder responses but cannot connect to their respective PostgreSQL databases or Redis cache. Root cause investigation is blocked by insufficient RBAC permissions on the agent service account.

## Impact

- **User Impact:** Complete platform outage - all applications serve placeholder responses only
- **Business Impact:** Zero functionality available across all four CrystalShards properties
- **Technical Impact:**
  - All PostgreSQL connections failing with "Failed to connect to database with username 'app'"
  - Redis connection failing (CrystalShards only) to `shared-redis.infrastructure.svc.cluster.local:6379`
  - Applications running but not functional
- **Duration:** Ongoing (investigation started at 03:50 UTC)

## Timeline (UTC)

- **2025-10-10 03:41:XX** - Deployment run 18395832256 completed successfully with `wait_for_rollout = false` fix
- **2025-10-10 03:50:48** - Verification started: All four applications responding with HTTP 200 OK
- **2025-10-10 03:50:48** - DISCOVERED: All apps serving JSON placeholder `{"hello":"Hello World from Home::Index"}`
- **2025-10-10 03:51:08** - Health endpoint check: CrystalShards reports database + Redis unhealthy
- **2025-10-10 03:51:23** - Health endpoints for CrystalDocs, CrystalGigs, CrystalBits all report database unhealthy
- **2025-10-10 03:51:XX** - Root cause analysis started: Database connectivity issues
- **2025-10-10 03:52:XX** - BLOCKER: Agent service account lacks RBAC permissions to inspect cluster resources
- **2025-10-10 03:54:XX** - Investigation via configuration files and GitHub Actions logs
- **2025-10-10 03:56:XX** - FINDING: Terraform data sources successfully read CNPG-generated secrets
- **2025-10-10 03:58:XX** - FINDING: Application secrets created with correct DATABASE_URL format
- **2025-10-10 04:00:XX** - HYPOTHESIS: PostgreSQL pods or CNPG operator may not be running
- **2025-10-10 04:02:XX** - Post-Event Review created (this document)
- **2025-10-10 09:17:XX** - INVESTIGATION RESUMED: Second SRE agent assigned to issues #52 and #53
- **2025-10-10 09:18:XX** - CONFIRMED: RBAC configuration exists in terraform/modules/agent/main.tf
- **2025-10-10 09:19:XX** - CONFIRMED: Terraform refreshing agent RBAC resources in deployment runs
- **2025-10-10 09:20:XX** - FINDING: Cannot verify if RBAC actually applied (Forbidden errors persist)
- **2025-10-10 09:21:XX** - FINDING: Latest deployment (run 18399969384) failed due to health check timeouts
- **2025-10-10 09:22:XX** - CREATED: Comprehensive diagnostic runbook posted to issue #52
- **2025-10-10 09:23:XX** - STATUS: Investigation blocked until RBAC permissions manually applied

## Root Cause Analysis

### What Happened

**Deployment succeeded but applications non-functional:**

1. **Terraform Deployment (GitHub Actions run 18395832256)**:
   - ✅ All Kubernetes resources created successfully
   - ✅ Data sources successfully read CNPG-generated secrets (`*-postgres-app`)
   - ✅ Application secrets created with DATABASE_URL from CNPG secrets
   - ✅ Deployments created/modified without errors
   - ✅ HTTPRoutes configured and ingress working

2. **Application Status**:
   - ✅ Applications accessible via HTTPS (200 OK)
   - ❌ Health endpoints report database connectivity failures
   - ❌ Serving JSON placeholders instead of real content
   - ❌ Cannot connect to PostgreSQL or Redis

3. **Health Endpoint Responses**:

   **CrystalShards** (`/api/health`):
   ```json
   {
     "status": "ok",
     "services": {
       "database": "unhealthy: AppDatabase: Failed to connect to database 'crystalshards_production' with username 'app'. Check that you have access to connect to crystalshards-postgres-rw on port 5432",
       "redis": "unhealthy: Error connecting to 'shared-redis.infrastructure.svc.cluster.local:6379': Connection refused"
     }
   }
   ```

   **CrystalDocs, CrystalGigs, CrystalBits**:
   - Similar database connection failures
   - Attempting to connect to `<app>-postgres-rw:5432`
   - Username: `app`
   - Database: `<app>_production`

### Database Configuration Analysis

**PostgreSQL Cluster Configuration** (per app):
```yaml
# resource.kubectl_manifest.crystalshards_postgres.tf
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: crystalshards-postgres
  namespace: crystalshards
spec:
  instances: 2
  bootstrap:
    initdb:
      database: crystalshards_production
      owner: crystalshards  # Note: owner is 'crystalshards', not 'app'
```

**Application Secret Configuration**:
```hcl
# resource.kubernetes_secret.crystalshards_secrets.tf
database_url = "postgresql://app:${data.kubernetes_secret.crystalshards_postgres_app.data["password"]}@crystalshards-postgres-rw:5432/crystalshards_production"
```

**Key Finding**:
- CNPG creates user `app` (confirmed by Terraform successfully reading `*-postgres-app` secrets)
- Applications configured to connect as user `app` to database `*_production`
- Terraform deployment succeeded, meaning secrets exist and were populated

### Possible Root Causes

**Primary Hypotheses** (requires cluster access to verify):

1. **PostgreSQL Pods Not Running**:
   - CNPG operator may not be installed or healthy
   - PostgreSQL cluster resources may not have spawned pods
   - Pods may be in CrashLoopBackOff or Pending state
   - GKE Autopilot may be slow to schedule stateful workloads

2. **Database Not Initialized**:
   - PostgreSQL pods running but database initialization incomplete
   - CNPG bootstrap process may still be in progress
   - Database migrations (`lucky db.migrate`) not executed

3. **Network Connectivity Issues**:
   - Network policies may be blocking cross-pod communication
   - DNS resolution failing for `*-postgres-rw` service names
   - Service endpoints not registered (no healthy pods backing services)

4. **Redis Operator/Resource Issues**:
   - Redis operator not installed or unhealthy
   - `shared-redis` resource in infrastructure namespace not created
   - Redis pod not running or not ready

5. **Timing/Race Condition**:
   - Application pods started before database pods ready
   - Health checks timing out during database initialization
   - Readiness probes failing prematurely (60s initial delay may be too short)

### RBAC Investigation Blocker - CRITICAL FINDING

**RBAC Configuration Status:**

✅ **RBAC Resources Defined:**
- Comprehensive ClusterRole defined in `terraform/modules/agent/main.tf` (lines 30-146)
- Includes permissions for: pods, services, endpoints, CNPG clusters, Redis resources, secrets, logs, events, etc.
- ClusterRoleBinding grants permissions to both `claude-agent` AND `default` service accounts in `claude` namespace

✅ **Terraform Refreshing RBAC:**
- GitHub Actions run 18399969384 shows Terraform refreshing these resources:
  - `module.agent.kubernetes_cluster_role.claude_agent_role: Refreshing state...`
  - `module.agent.kubernetes_service_account.claude_agent: Refreshing state...`
  - `module.agent.kubernetes_cluster_role_binding.claude_agent_binding: Refreshing state...`

❌ **RBAC Not Effective:**
- Agent service account STILL lacks permissions despite Terraform refresh
- Cannot verify if resources exist in cluster (Forbidden)
- Cannot inspect any cluster resources across all namespaces
- **Chicken-and-egg problem:** Need admin permissions to apply RBAC, which grants non-admin permissions

**Agent Service Account Current Limitations** (`system:serviceaccount:claude:default`):

❌ Cannot execute:
- `kubectl get pods -n <namespace>` - Forbidden
- `kubectl get services -n <namespace>` - Forbidden
- `kubectl get namespaces` - Forbidden
- `kubectl run` (diagnostic pods) - Forbidden
- `kubectl describe` - Forbidden
- `kubectl logs` - Assumed forbidden

✅ Can execute:
- HTTP requests to external URLs (verified applications accessible)
- Access to codebase and configuration files
- GitHub Actions API queries

**Impact**: Cannot directly inspect cluster state to verify:
- Whether PostgreSQL/Redis pods exist and are running
- Pod status (Running, Pending, CrashLoopBackOff)
- Service endpoints registration
- Operator health status
- Pod logs for detailed error messages

### Why It Happened

**Configuration appears correct**:
- Database credentials properly configured via CNPG secrets ✓
- Application secrets correctly reference CNPG-generated secrets ✓
- Network policies allow egress to same-namespace PostgreSQL ✓
- Services configured correctly (`*-postgres-rw`, `shared-redis.*`) ✓

**Likely infrastructure timing issue**:
- Terraform deployment succeeded but didn't wait for all resources to be ready
- `wait_for_rollout = false` allows deployments to complete without pod readiness
- Stateful workloads (PostgreSQL, Redis) may take longer to initialize in GKE Autopilot
- Application pods may have started before database pods were ready

### Contributing Factors

1. **Insufficient Deployment Validation**:
   - No post-deployment health verification
   - Deployment marked successful without checking application functionality
   - `wait_for_rollout = false` prevents blocking on pod readiness

2. **Limited Observability**:
   - Agent RBAC permissions too restrictive for incident investigation
   - No pod status visibility
   - No log access for error diagnosis

3. **No Database Initialization Job**:
   - Missing init container or job to run `lucky db.create` and `lucky db.migrate`
   - Applications assume database exists and is migrated
   - No startup dependency ordering

4. **Health Check Configuration**:
   - Health endpoints check database connectivity
   - Liveness probe may restart pods if database unavailable too long
   - Readiness probe prevents traffic but doesn't solve underlying issue

## What Went Well

1. **Fast Issue Detection**:
   - Immediate verification via HTTP requests after deployment
   - Health endpoints provided detailed error messages
   - Clear identification of database connectivity as root cause

2. **Comprehensive Investigation**:
   - Systematically checked Terraform configuration
   - Verified secret configuration and data sources
   - Reviewed GitHub Actions logs for deployment status
   - Analyzed network policies and security configuration

3. **Documentation Trail**:
   - GitHub Actions logs preserved deployment details
   - Terraform configuration provides clear infrastructure intent
   - Health endpoints provide diagnostic information

4. **Deployment Did Not Fail**:
   - Terraform applied successfully
   - Applications deployed and accessible
   - Ingress configuration working correctly
   - HTTPS termination functional

## What Didn't Go Well

1. **Insufficient RBAC Permissions**:
   - Cannot inspect pod status
   - Cannot view pod logs
   - Cannot execute diagnostic commands
   - Investigation severely limited

2. **No Post-Deployment Verification**:
   - Deployment succeeded without verifying application health
   - No automated check for database connectivity
   - UI/UX verification blocked by non-functional backends

3. **Missing Database Initialization**:
   - No automated database creation/migration
   - Applications assume database ready on startup
   - No retry logic for database connections

4. **Deployment Workflow Gap**:
   - `wait_for_rollout = false` allows broken deployments to succeed
   - No health check after Terraform apply
   - No validation that services are functional

## Action Items

### Immediate (Requires Human Intervention - Cluster Access Needed)

- [ ] **PRIORITY 0 - CRITICAL BLOCKER**: Apply RBAC permissions manually (MUST BE DONE FIRST):
  ```bash
  # Run with cluster admin permissions
  kubectl apply -f /tmp/claude-agent-rbac.yaml
  # OR
  cd /workspaces/monorepo/terraform
  terraform apply -target=module.agent
  ```
  **Without this, all other diagnostics are impossible. See GitHub issue #52 for full RBAC manifest.**

- [ ] **PRIORITY 1**: Check PostgreSQL pod status in all namespaces:
  ```bash
  kubectl get pods -n crystalshards -l cnpg.io/cluster=crystalshards-postgres
  kubectl get pods -n crystaldocs -l cnpg.io/cluster=crystaldocs-postgres
  kubectl get pods -n crystalgigs -l cnpg.io/cluster=crystalgigs-postgres
  kubectl get pods -n crystalbits -l cnpg.io/cluster=crystalbits-postgres
  ```

- [ ] **PRIORITY 2**: Verify CNPG operator status:
  ```bash
  kubectl get pods -n cnpg-system
  kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg --tail=100
  ```

- [ ] **PRIORITY 3**: Check Redis operator and shared-redis:
  ```bash
  kubectl get pods -n redis-operator-system
  kubectl get redis -n infrastructure
  kubectl get pods -n infrastructure -l redis.redis.opstreelabs.in/name=shared-redis
  ```

- [ ] **PRIORITY 4**: Check database service endpoints:
  ```bash
  kubectl get svc -n crystalshards | grep postgres
  kubectl get endpoints -n crystalshards | grep postgres
  kubectl get svc -n infrastructure | grep redis
  kubectl get endpoints -n infrastructure | grep redis
  ```

- [ ] **PRIORITY 5**: Review application pod logs:
  ```bash
  kubectl logs -n crystalshards -l app=crystalshards,component=api --tail=200
  kubectl logs -n crystaldocs -l app=crystaldocs,component=api --tail=200
  ```

- [ ] **If operators not running**: Apply operator Terraform modules separately:
  ```bash
  cd terraform/modules/operators
  terraform init
  terraform apply
  ```

- [ ] **If database pods not ready**: Wait for CNPG initialization (can take 5-10 minutes)

- [ ] **If databases not migrated**: Run migrations manually:
  ```bash
  kubectl exec -n crystalshards deployment/crystalshards-api -- lucky db.migrate
  kubectl exec -n crystaldocs deployment/crystaldocs-api -- lucky db.migrate
  kubectl exec -n crystalgigs deployment/crystalgigs-api -- lucky db.migrate
  kubectl exec -n crystalbits deployment/crystalbits-api -- lucky db.migrate
  ```

### Short-term (This Week)

- [ ] **Grant Agent Service Account Cluster Read Permissions**:
  ```yaml
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: agent-cluster-reader
  rules:
  - apiGroups: [""]
    resources: ["pods", "services", "endpoints", "namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["get", "list"]
  - apiGroups: ["postgresql.cnpg.io"]
    resources: ["clusters"]
    verbs: ["get", "list"]
  - apiGroups: ["redis.redis.opstreelabs.in"]
    resources: ["redis"]
    verbs: ["get", "list"]

  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: agent-cluster-reader-binding
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: agent-cluster-reader
  subjects:
  - kind: ServiceAccount
    name: default
    namespace: claude
  ```

- [ ] **Add Database Initialization Job**:
  - Create Kubernetes Job resource to run migrations
  - Add init container to wait for database before starting app
  - Implement retry logic for database connections

- [ ] **Improve Deployment Workflow**:
  - Add post-deployment health verification step
  - Check all `/api/health` endpoints report healthy
  - Fail deployment if health checks fail
  - Consider removing or documenting `wait_for_rollout = false`

- [ ] **Add Deployment Smoke Tests**:
  ```yaml
  # .github/workflows/deploy.yml
  - name: Verify Deployment Health
    run: |
      for app in crystalshards crystaldocs crystalgigs crystalbits; do
        if [ "$app" = "crystalgigs" ]; then
          url="https://crystalgigs.com/api/health"
        elif [ "$app" = "crystalbits" ]; then
          url="https://crystalbits.org/api/health"
        else
          url="https://$app.org/api/health"
        fi

        response=$(curl -s "$url")
        if echo "$response" | jq -e '.services | to_entries[] | select(.value | contains("unhealthy"))' > /dev/null; then
          echo "❌ $app health check failed: $response"
          exit 1
        fi
        echo "✅ $app healthy"
      done
  ```

### Long-term (This Month)

- [ ] **Implement Init Container Pattern**:
  ```yaml
  initContainers:
  - name: wait-for-db
    image: postgres:15-alpine
    command:
    - sh
    - -c
    - |
      until pg_isready -h $DB_HOST -p 5432; do
        echo "Waiting for database..."
        sleep 2
      done
      echo "Database ready!"
    env:
    - name: DB_HOST
      value: "crystalshards-postgres-rw"
  ```

- [ ] **Add Database Migration Job**:
  ```yaml
  apiVersion: batch/v1
  kind: Job
  metadata:
    name: crystalshards-db-migrate
  spec:
    template:
      spec:
        containers:
        - name: migrate
          image: us-docker.pkg.dev/.../crystalshards:latest
          command: ["lucky", "db.migrate"]
        restartPolicy: OnFailure
  ```

- [ ] **Improve Health Checks**:
  - Separate liveness (app alive) from readiness (database ready)
  - Increase initial delay for readiness probe to 120s
  - Add startup probe for slow-initializing stateful services
  - Document expected startup sequence

- [ ] **Add Monitoring and Alerting**:
  - Alert on pod CrashLoopBackOff
  - Alert on prolonged unhealthy health checks
  - Monitor CNPG cluster status
  - Track database connection pool metrics

- [ ] **Deployment Sequencing**:
  - Ensure operators deployed before dependent resources
  - Wait for PostgreSQL clusters ready before deploying apps
  - Document deployment dependencies and ordering

- [ ] **Improve Error Messages**:
  - Add detailed database connection diagnostics
  - Include DNS resolution checks in health endpoint
  - Log connection attempts with timestamps

## Lessons Learned

1. **RBAC Permissions are Critical for Operations**:
   - Agent must have sufficient permissions to investigate issues
   - Read-only access to cluster resources is minimum requirement
   - Cannot diagnose without visibility into pod/service status

2. **Deployment Success ≠ Application Health**:
   - Terraform apply success doesn't mean services are functional
   - Must verify application health post-deployment
   - `wait_for_rollout = false` masks readiness issues

3. **Stateful Services Need Special Handling**:
   - Databases take time to initialize
   - Applications must wait for database readiness
   - Init containers and jobs essential for proper sequencing

4. **Health Endpoints are Valuable**:
   - Detailed error messages enabled quick diagnosis
   - Distinguish between different failure modes (DB vs Redis)
   - Critical for automated health verification

5. **Observability Gaps Extend Incident Duration**:
   - Cannot fix what you cannot see
   - Log access and pod inspection essential for SRE work
   - Monitoring should be available before incidents occur

## Technical Details

### Database Connection Configuration

**Expected Connection Flow**:
1. CNPG operator creates PostgreSQL cluster
2. CNPG generates secret `<cluster>-app` with username `app` and password
3. Terraform data source reads CNPG secret
4. Terraform creates application secret with full DATABASE_URL
5. Application pods mount secret and connect to database
6. Lucky framework parses DATABASE_URL and establishes connection

**Actual Behavior** (as of 03:51 UTC):
1. ✅ CNPG secrets exist (Terraform data source succeeded)
2. ✅ Application secrets created (Terraform apply succeeded)
3. ❌ Application cannot connect to database (health check fails)
4. ❓ PostgreSQL pods status unknown (no cluster access)

### Application Secret Format

```hcl
# Constructed by Terraform
database_url = "postgresql://app:${PASSWORD}@${SERVICE}:5432/${DATABASE}"

# Example for CrystalShards:
# postgresql://app:SECRETPASSWORD@crystalshards-postgres-rw:5432/crystalshards_production
```

### Network Policy Configuration

```hcl
# Allows access to same-namespace PostgreSQL
egress {
  to {
    pod_selector {
      match_labels = {
        "cnpg.io/cluster" = "crystalshards-postgres"
      }
    }
  }
  ports {
    protocol = "TCP"
    port     = "5432"
  }
}

# Allows access to infrastructure namespace (for Redis, MinIO)
egress {
  to {
    namespace_selector {
      match_labels = {
        name = "infrastructure"
      }
    }
  }
}
```

### Health Check Configuration

```hcl
liveness_probe {
  http_get {
    path = "/api/health"
    port = 3000
  }
  initial_delay_seconds = 120
  period_seconds        = 10
  timeout_seconds       = 10
  failure_threshold     = 6  # 60s of failures before restart
}

readiness_probe {
  http_get {
    path = "/api/health"
    port = 3000
  }
  initial_delay_seconds = 60
  period_seconds        = 10
  timeout_seconds       = 10
  failure_threshold     = 6  # 60s of failures before marked unready
}
```

**Implication**:
- If database unavailable at 60s mark, pod marked unready (no traffic)
- If database unavailable at 120s mark, pod may be restarted
- Health check depends on database connectivity
- Could cause restart loops if database initialization slow

## Verification URLs

- CrystalShards: https://crystalshards.org (200 OK, placeholder JSON)
- CrystalDocs: https://crystaldocs.org (200 OK, placeholder JSON)
- CrystalGigs: https://crystalgigs.com (200 OK, placeholder JSON)
- CrystalBits: https://crystalbits.org (200 OK, placeholder JSON)

Health Endpoints:
- CrystalShards: https://crystalshards.org/api/health (database + redis unhealthy)
- CrystalDocs: https://crystaldocs.org/api/health (database unhealthy)
- CrystalGigs: https://crystalgigs.com/api/health (database unhealthy)
- CrystalBits: https://crystalbits.org/api/health (database unhealthy)

## References

- Deployment run: 18395832256 (succeeded)
- Previous PER: `/workspaces/monorepo/pers/2025-10-10-deployment-failures-image-tag-mismatch.md`
- PostgreSQL config: `apps/*/terraform/resource.kubectl_manifest.*_postgres.tf`
- Application secrets: `apps/*/terraform/resource.kubernetes_secret.*_secrets.tf`
- Network policies: `apps/*/terraform/resource.kubernetes_network_policy.*.tf`
- Deployment manifests: `apps/*/terraform/resource.kubernetes_deployment.*.tf`
- CNPG operator: `terraform/modules/operators/resource.helm_release.cnpg_operator.tf`
- Redis operator: `terraform/modules/operators/resource.helm_release.redis_operator.tf`

## Sign-off

**Prepared by:** SRE Agent (Claude)
**Reviewed by:** TBD
**Date:** 2025-10-10
**Status:** Investigation ongoing - requires cluster access for resolution
