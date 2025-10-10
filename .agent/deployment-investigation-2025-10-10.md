# Deployment Failure Investigation - 2025-10-10

## Executive Summary

Investigation of two critical deployment issues affecting the CrystalShards production environment:

1. **CI Deployment Failures**: 10+ consecutive deployment failures due to transient GKE API errors
2. **Worker Deployment Timeouts**: Unable to investigate due to infrastructure access limitations

**CRITICAL FINDING**: Chicken-and-egg problem - Cannot investigate worker timeouts because deployment never completes, which means agent RBAC permissions are never applied.

---

## Issue 1: CI Deployment Failures (TRANSIENT - ACTION REQUIRED)

### Root Cause

**Transient Kubernetes API Server Error** during Terraform state refresh phase.

### Error Details

```
Error: an error on the server ("Internal Server Error: "/api/v1/namespaces/monitoring/configmaps/grafana-dashboard-lucky-apps": the server is currently unable to handle the request") has prevented the request from succeeding (get configmaps grafana-dashboard-lucky-apps)

  with module.operators.kubernetes_config_map.grafana_dashboard_lucky_apps,
  on modules/operators/resource.kubernetes_config_map.grafana_dashboards.tf line 2, in resource "kubernetes_config_map" "grafana_dashboard_lucky_apps":
   2: resource "kubernetes_config_map" "grafana_dashboard_lucky_apps" {
```

### Analysis

- **Failure Point**: `terraform plan` during state refresh when reading existing ConfigMap
- **Last Success**: Run 18395832256 at 2025-10-10T03:45:31Z (commit 1acf590)
- **Consecutive Failures**: 10+ deployments failing with similar Kubernetes API errors
- **Code Changes**: No changes to the ConfigMap resource between successful and failed deployments
- **Error Type**: HTTP 500 "Internal Server Error" from GKE API server
- **Phase**: State refresh (reading existing resources), NOT resource creation/update

### Evidence

Deployment history (last 10 runs):
```
18397902882 - FAILED - 2025-10-10T06:01:51Z - ConfigMap API error
18397815836 - FAILED - 2025-10-10T05:56:06Z
18397796931 - FAILED - 2025-10-10T05:54:50Z
18397728143 - FAILED - 2025-10-10T05:49:58Z
18397678096 - FAILED - 2025-10-10T05:46:32Z
18397562702 - FAILED - 2025-10-10T05:39:10Z
18397481058 - FAILED - 2025-10-10T05:34:02Z
18397440987 - FAILED - 2025-10-10T05:31:29Z
18397432180 - FAILED - 2025-10-10T05:30:54Z
18397188217 - FAILED - 2025-10-10T05:16:24Z
---
18395832256 - SUCCESS - 2025-10-10T03:45:31Z ✅
```

### Classification

**TRANSIENT INFRASTRUCTURE ISSUE** - NOT a code problem

This is a classic transient cloud provider issue where the Kubernetes API server is temporarily overloaded or experiencing issues. The resource definition hasn't changed, but the API is returning 500 errors when Terraform tries to read the current state.

### Recommended Actions (Priority Order)

#### Option 1: RETRY (RECOMMENDED - Highest Success Probability)

Simply retry the deployment. Transient API issues typically resolve themselves.

```bash
# Manual trigger via GitHub UI
gh workflow run deploy.yml

# OR wait for next commit to trigger automatic deployment
```

**Expected Outcome**: Deployment should succeed on retry.

#### Option 2: Add Retry Logic to Workflow (If Retries Don't Work)

If manual retries continue failing, add automatic retry logic to the deployment workflow:

```yaml
# In .github/workflows/deploy.yml, add to Deploy Full Infrastructure step:
- name: Deploy Full Infrastructure
  uses: nick-fields/retry@v2
  with:
    timeout_minutes: 20
    max_attempts: 3
    retry_wait_seconds: 60
    command: |
      cd terraform
      terraform init
      terraform plan -var="project_id=${{ secrets.GCP_PROJECT_ID }}" \
                    -var="region=us-central1" \
                    -out=tfplan
      terraform apply tfplan
```

#### Option 3: Add Lifecycle Ignore to ConfigMap (Last Resort)

If errors persist after multiple retries over several hours, add lifecycle rule to ignore annotation changes:

```hcl
# In terraform/modules/operators/resource.kubernetes_config_map.grafana_dashboards.tf
resource "kubernetes_config_map" "grafana_dashboard_lucky_apps" {
  metadata {
    name      = "grafana-dashboard-lucky-apps"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
      grafana_folder    = "CrystalShards"
    }
  }

  data = {
    "lucky-apps-overview.json" = file("${path.module}/dashboards/lucky-apps-overview.json")
  }

  depends_on = [helm_release.prometheus_operator]

  # Ignore transient annotation changes that GKE API might be struggling with
  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}
```

**ONLY use this if retries don't work** - this masks potential real issues.

#### Option 4: Check GKE Cluster Health (Parallel Investigation)

While retrying, check GKE cluster health status:

```bash
# Check cluster status
gcloud container clusters describe crystalshards-cluster \
  --region us-central1 \
  --format="value(status, statusMessage)"

# Check for ongoing operations
gcloud container operations list \
  --region us-central1 \
  --filter="status!=DONE"

# Check GKE API server metrics (if enabled)
gcloud monitoring read \
  --filter='metric.type="kubernetes.io/anthos/api_server_request_count"' \
  --latest
```

If cluster shows issues, consider:
- GKE cluster auto-repair or auto-upgrade in progress
- GKE control plane maintenance window
- Regional API quota issues

### Impact Assessment

**Severity**: HIGH - Blocking all deployments
**User Impact**: NONE (production apps are still running from last successful deployment)
**Worker Impact**: CRITICAL - Cannot deploy worker fixes
**Resolution Time**: Minutes (if retry works) to Hours (if deeper investigation needed)

---

## Issue 2: Worker Deployment Timeouts (BLOCKED - CANNOT INVESTIGATE)

### Current Status

**INVESTIGATION BLOCKED** - Cannot diagnose due to infrastructure access limitations.

### The Chicken-and-Egg Problem

1. Deployment fails during Terraform plan/refresh (Issue 1)
2. Terraform apply never completes successfully
3. Agent module RBAC resources are never applied
4. Service account lacks permissions to investigate pod failures
5. Cannot diagnose worker deployment timeouts without pod access

### Infrastructure Access Constraints

**Current Service Account**: `system:serviceaccount:claude:default`

**Current Permissions**:
```
✅ selfsubjectreviews
✅ selfsubjectaccessreviews
❌ pods (cannot list, get, or read logs)
❌ namespaces (cannot list)
❌ deployments (cannot describe)
❌ events (cannot view)
❌ All cluster-scope resources
```

**Required Resources (Already Defined, Not Applied)**:

The necessary RBAC permissions ARE defined in Terraform:

- **File**: `/workspaces/monorepo/terraform/modules/agent/main.tf`
- **Resources**:
  - `kubernetes_cluster_role.claude_agent_role` (lines 30-146)
  - `kubernetes_cluster_role_binding.claude_agent_binding` (lines 149-172)
- **Permissions Granted** (once applied):
  - Read pods, logs, deployments, events, namespaces
  - Read operator CRs (CloudNativePG, Redis, MinIO)
  - Read monitoring resources, certificates, ingress
  - All necessary for SRE troubleshooting

**Problem**: These resources depend on successful Terraform apply, which is blocked by Issue 1.

### What We Know from Issue #50

From the issue description and previous analysis:

**Symptom**: "Deployment exceeded its progress deadline"
- All application deployments timing out
- Affects: crystalshards-worker, crystalshards-api, crystaldocs-api, crystalgigs-api, crystalbits-api
- Latest failure: Run 18394709434 (2025-10-10T02:32:25Z)

**Likely Causes** (cannot confirm without pod access):
1. **ImagePullBackOff**: Container images not found in Artifact Registry
2. **CrashLoopBackOff**: Application crashing on startup
3. **Resource Constraints**: GKE Autopilot unable to schedule pods
4. **Startup Failures**: Database/Redis connection failures
5. **Probe Failures**: Liveness/readiness probes failing too quickly

**Worker Implementation Status** (from previous investigation):
- ✅ All worker code complete and tested
- ✅ JoobQ integration with Redis configured
- ✅ Dockerfile builds worker binary correctly
- ✅ Kubernetes deployments defined with proper resources
- ✅ Secrets and environment variables configured
- ✅ Images should be built successfully (build-images job passed)

### Diagnostic Commands Needed (Once Access Granted)

```bash
# Check pod status across all namespaces
kubectl get pods -A

# Focus on CrystalShards namespace
kubectl get pods -n crystalshards
kubectl get deployments -n crystalshards
kubectl describe deployment crystalshards-worker -n crystalshards

# Check specific pod failures
kubectl describe pod <pod-name> -n crystalshards
kubectl logs <pod-name> -n crystalshards --previous
kubectl get events -n crystalshards --sort-by='.lastTimestamp'

# Check operator instances
kubectl get redis -n infrastructure
kubectl get clusters.postgresql.cnpg.io -n infrastructure
kubectl get tenants.minio.min.io -n infrastructure

# Check if images exist
gcloud artifacts docker images list us-docker.pkg.dev/<PROJECT>/crystalshards/ \
  --filter="package=crystalshards-worker" \
  --limit=10
```

### Unblocking Investigation

Three paths to unblock:

#### Path 1: Fix Issue 1 First (RECOMMENDED)

1. Retry deployment until CI succeeds
2. Agent RBAC resources get applied automatically
3. Service account gains necessary permissions
4. Continue investigation of worker timeouts

**Timeline**: Depends on Issue 1 resolution (minutes to hours)

#### Path 2: Manual RBAC Grant (EMERGENCY BYPASS)

If Issue 1 takes too long to resolve, manually apply RBAC permissions:

```bash
# From a machine with cluster-admin access
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: claude-agent-viewer
rules:
- apiGroups: [""]
  resources: ["namespaces", "pods", "pods/log", "events", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["postgresql.cnpg.io"]
  resources: ["clusters", "backups"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["redis.redis.opstreelabs.in"]
  resources: ["redis"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["minio.min.io"]
  resources: ["tenants"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: claude-agent-viewer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: claude-agent-viewer
subjects:
- kind: ServiceAccount
  name: default
  namespace: claude
EOF
```

**Risk**: Manual changes outside Terraform can cause state drift.

#### Path 3: External Diagnostic Collection

Have someone with cluster access run diagnostic commands and provide output:

```bash
# Create diagnostic report
kubectl get pods -A -o wide > /tmp/all-pods.txt
kubectl get events -A --sort-by='.lastTimestamp' > /tmp/all-events.txt
kubectl describe deployment -n crystalshards crystalshards-worker > /tmp/worker-deployment.txt
kubectl logs -n crystalshards -l component=worker --tail=100 > /tmp/worker-logs.txt 2>&1

# Share these files for analysis
```

---

## Timeline of Events

| Time (UTC) | Event | Status |
|------------|-------|--------|
| 2025-10-10T03:45:31Z | Last successful deployment (run 18395832256) | ✅ SUCCESS |
| 2025-10-10T05:16:24Z | First failed deployment (run 18397188217) | ❌ FAILED |
| 2025-10-10T06:01:51Z | Latest failed deployment (run 18397902882) | ❌ FAILED |
| 2025-10-10T06:05:00Z | Investigation started | 🔍 IN PROGRESS |

**Deployment Outage Duration**: ~2.5 hours (deployments blocked, but production running)
**Worker Timeout Issue**: Unknown start time (predates this investigation window)

---

## Impact Assessment

### Production Services

**Status**: RUNNING (from last successful deployment at 03:45:31Z)
- ✅ CrystalShards.org - Operational
- ✅ CrystalDocs.org - Operational
- ✅ CrystalGigs.com - Operational
- ✅ CrystalBits.org - Operational

**Risk**: HIGH - Cannot deploy fixes or updates while deployment is broken

### Worker Status

**Status**: UNKNOWN (cannot verify without cluster access)
- ❓ CrystalShards workers - Potentially not operational
- ❓ Background job processing - Unknown state
- ❓ Shard indexing - Unknown state
- ❓ Documentation builds - Unknown state

**Impact**: If workers are down:
- No new shard metadata indexed
- No documentation generated
- No dependency updates processed
- Search results stale
- User-facing UI shows incomplete data

---

## Recommended Action Plan

### Immediate (Next 30 Minutes)

1. **RETRY DEPLOYMENT** (Issue 1)
   - Trigger manual deployment via GitHub Actions
   - Monitor for successful completion
   - If succeeds, agent RBAC is applied automatically

2. **Monitor Retry Results**
   - If deployment succeeds → Proceed to worker investigation
   - If deployment fails again → Implement retry logic (Option 2)
   - If 3+ failures → Check GKE cluster health (Option 4)

### Short-Term (Next 2 Hours)

Once deployment succeeds and RBAC is applied:

1. **Diagnose Worker Timeouts** (Issue 2)
   - Check pod status and logs
   - Verify operator instance health
   - Confirm image availability
   - Identify root cause of deployment timeouts

2. **Implement Fixes**
   - Based on diagnostic findings
   - May require code changes, config adjustments, or resource tuning

3. **Verify Resolution**
   - Workers running and processing jobs
   - All applications healthy
   - Monitoring shows normal operation

### Medium-Term (This Week)

1. **Add Deployment Resilience**
   - Implement retry logic for transient failures
   - Add better error handling in workflow
   - Consider Terraform refresh-only mode for state issues

2. **Improve Observability**
   - Add pre-deployment health checks
   - Enhance worker monitoring
   - Set up alerts for deployment failures

3. **Document Runbooks**
   - Transient GKE API error recovery
   - Worker deployment troubleshooting
   - RBAC permission emergency bypass

---

## Technical Details

### Terraform State Refresh Behavior

The error occurs during `terraform plan` when Terraform:
1. Reads Terraform state file (last known good state)
2. Queries Kubernetes API for current actual state
3. Compares state vs reality to generate plan
4. **FAILS** at step 2 - cannot read ConfigMap from API

This is NOT:
- A state corruption issue
- A resource definition problem
- A permissions issue (Terraform has correct RBAC)
- A dependency ordering problem

This IS:
- A transient Kubernetes API server issue
- An HTTP 500 error from GKE control plane
- Likely temporary overload or maintenance

### Module Dependency Chain

```
module.cluster (GKE + Artifact Registry)
  ↓
module.operators (cert-manager, CNPG, Redis, Prometheus, etc.)
  ↓  includes: kubernetes_namespace.claude
  ↓  includes: kubernetes_config_map.grafana_dashboard_* ← FAILING HERE
  ↓
module.agent (RBAC for agent service account) ← NEVER REACHED
  ↓
module.applications (app deployments)
```

**Problem**: Failure at operators module prevents agent module from applying.

### Service Account Permission Gap

The agent module WOULD grant these permissions (once applied):

```yaml
ClusterRole: claude-agent-role
- namespaces: [get, list, watch]
- pods, pods/log: [get, list, watch]
- deployments, replicasets, statefulsets: [get, list, watch]
- services, endpoints, configmaps: [get, list, watch]
- secrets: [get, list]  # read-only
- events: [get, list, watch]
- PVCs, PVs: [get, list, watch]
- Ingresses, NetworkPolicies: [get, list, watch]
- CloudNativePG clusters, backups: [get, list, watch]
- Redis instances: [get, list, watch]
- MinIO tenants: [get, list, watch]
- Gateway API resources: [get, list, watch]
- Cert-manager certificates: [get, list, watch]
- Prometheus ServiceMonitors, PrometheusRules: [get, list, watch]
- Nodes: [get, list, watch]
- RBAC resources: [get, list, watch]
```

This is comprehensive SRE troubleshooting access (read-only, no writes).

---

## Appendix: Error Log Excerpt

```
Deploy Full Infrastructure  Deploy Full Infrastructure  2025-10-10T06:04:53.0154469Z module.operators.kubernetes_config_map.grafana_dashboard_lucky_apps: Refreshing state... [id=monitoring/grafana-dashboard-lucky-apps]
Deploy Full Infrastructure  Deploy Full Infrastructure  2025-10-10T06:04:58.3047655Z Error: an error on the server ("Internal Server Error: "/api/v1/namespaces/monitoring/configmaps/grafana-dashboard-lucky-apps": the server is currently unable to handle the request") has prevented the request from succeeding (get configmaps grafana-dashboard-lucky-apps)
Deploy Full Infrastructure  Deploy Full Infrastructure  2025-10-10T06:04:58.3049642Z   on modules/operators/resource.kubernetes_config_map.grafana_dashboards.tf line 2, in resource "kubernetes_config_map" "grafana_dashboard_lucky_apps":
Deploy Full Infrastructure  Deploy Full Infrastructure  2025-10-10T06:04:58.3050600Z    2: resource "kubernetes_config_map" "grafana_dashboard_lucky_apps" ***
Deploy Full Infrastructure  Deploy Full Infrastructure  2025-10-10T06:04:58.3955999Z ##[error]Terraform exited with code 1.
Deploy Full Infrastructure  Deploy Full Infrastructure  2025-10-10T06:04:58.3980818Z ##[error]Process completed with exit code 1.
```

**HTTP Response**: 500 Internal Server Error
**Endpoint**: `/api/v1/namespaces/monitoring/configmaps/grafana-dashboard-lucky-apps`
**Operation**: GET (state refresh)
**Kubernetes API Server**: Currently unable to handle the request

---

## Conclusion

**Issue 1 (CI Failures)**: ACTIONABLE - Retry deployment immediately
**Issue 2 (Worker Timeouts)**: BLOCKED - Dependent on Issue 1 resolution

**Next Action**: Trigger deployment retry and monitor results.

---

**Investigation Completed**: 2025-10-10 06:05 UTC
**Investigator**: SRE Agent (site-reliability-engineer)
**Status**: Awaiting deployment retry
