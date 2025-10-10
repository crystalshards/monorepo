# Infrastructure Diagnosis Report
**Date:** 2025-10-10
**Agent:** claude-agent (SRE)
**Issues:** #52 (Database Connectivity), #53 (Redis Connectivity)

## Executive Summary

**CRITICAL BLOCKER IDENTIFIED:** The claude-agent service account lacks necessary RBAC permissions to diagnose and resolve production infrastructure issues. Additionally, Terraform state backend (GCS bucket) is inaccessible, preventing infrastructure changes via Terraform.

**Impact:** Complete inability to diagnose or fix database and Redis connectivity failures affecting all 4 CrystalShards applications.

**Status:** BLOCKED - Requires manual intervention by someone with cluster-admin access.

---

## Current State

### Agent Identity
```
Username: system:serviceaccount:claude:default
Namespace: claude
Pod: claude-agent
Node: gke-cluster-1-nap-e2-standard-4-9nhwp-7c978ee8-gzc6
```

### Permissions Status
- **ClusterRole `claude-agent-role`:** NOT APPLIED (cannot verify - forbidden)
- **ClusterRoleBinding `claude-agent-binding`:** NOT APPLIED (cannot verify - forbidden)
- **Current permissions:** Minimal (only self-subject reviews and public API endpoints)

### What I Can Access
- Kubernetes API server (connectivity confirmed)
- kubectl configured correctly
- API resource discovery
- Self-identity verification

### What I Cannot Access
- Any namespace resources (pods, services, deployments)
- Custom Resource Definitions (CRDs)
- Operator deployments
- Database clusters
- Redis instances
- Events and logs
- RBAC resources (roles, bindings)
- Node information

---

## Root Cause Analysis

### Primary Issue: RBAC Not Applied
The Terraform configuration at `/workspaces/monorepo/terraform/modules/agent/main.tf` defines:
- ClusterRole with comprehensive read permissions (lines 30-146)
- ClusterRoleBinding for `claude:default` service account (lines 149-172)

**However, these resources were never applied to the cluster.**

### Secondary Issue: Terraform State Backend Inaccessible
```
Error: Failed to get existing workspaces: querying Cloud Storage failed:
googleapi: Error 403: 632122948866-compute@developer.gserviceaccount.com
does not have storage.objects.list access to the Google Cloud Storage bucket.
Permission 'storage.objects.list' denied on resource (or it may not exist)., forbidden
```

**GCS Bucket:** `crystalshards-org-terraform-state`
**Service Account:** `632122948866-compute@developer.gserviceaccount.com` (GKE compute SA)

This prevents:
- Running `terraform init`
- Running `terraform plan` or `terraform apply`
- Viewing current infrastructure state
- Applying any infrastructure changes

### Impact on Original Issues

**Issue #52 - Database Connectivity:**
Cannot diagnose because:
- Cannot check if CloudNativePG operator is deployed
- Cannot list PostgreSQL Cluster resources
- Cannot verify database pods are running
- Cannot inspect service DNS records
- Cannot view pod logs or events

**Issue #53 - Redis Connectivity:**
Cannot diagnose because:
- Cannot check if Redis operator is deployed
- Cannot list Redis custom resources
- Cannot verify Redis pods are running
- Cannot inspect Redis service
- Cannot test connectivity from worker pods

---

## Required Manual Intervention

Someone with **cluster-admin** access must perform one of the following:

### Option 1: Apply via Terraform (Preferred)

```bash
# Grant GCS bucket access to compute service account
gsutil iam ch serviceAccount:632122948866-compute@developer.gserviceaccount.com:roles/storage.objectViewer \
  gs://crystalshards-org-terraform-state

# Initialize and apply agent module
cd /workspaces/monorepo/terraform
terraform init
terraform apply -target=module.agent -auto-approve
```

### Option 2: Apply RBAC Manually

```bash
# Apply the RBAC configuration directly
cd /workspaces/monorepo/terraform/modules/agent
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: claude-agent-role
rules:
  # Namespace access
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch"]

  # Pod management and inspection
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/status"]
    verbs: ["get", "list", "watch"]

  # Deployment inspection
  - apiGroups: ["apps"]
    resources: ["deployments", "deployments/status", "replicasets", "statefulsets"]
    verbs: ["get", "list", "watch"]

  # Service inspection
  - apiGroups: [""]
    resources: ["services", "endpoints", "configmaps"]
    verbs: ["get", "list", "watch"]

  # Secret inspection (read-only for troubleshooting)
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]

  # Events for troubleshooting
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch"]

  # PVC and storage
  - apiGroups: [""]
    resources: ["persistentvolumeclaims", "persistentvolumes"]
    verbs: ["get", "list", "watch"]

  # Ingress and networking
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch"]

  # Custom resources for operators - CloudNativePG
  - apiGroups: ["postgresql.cnpg.io"]
    resources: ["clusters", "backups", "scheduledbackups"]
    verbs: ["get", "list", "watch"]

  # Redis Operator
  - apiGroups: ["redis.redis.opstreelabs.in"]
    resources: ["redis", "redisclusters"]
    verbs: ["get", "list", "watch"]

  # MinIO Operator
  - apiGroups: ["minio.min.io"]
    resources: ["tenants"]
    verbs: ["get", "list", "watch"]

  # Gateway API resources
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["gateways", "httproutes", "gatewayclasses"]
    verbs: ["get", "list", "watch"]

  # Cert-manager resources
  - apiGroups: ["cert-manager.io"]
    resources: ["certificates", "certificaterequests", "issuers", "clusterissuers"]
    verbs: ["get", "list", "watch"]

  # Monitoring resources
  - apiGroups: ["monitoring.coreos.com"]
    resources: ["servicemonitors", "prometheusrules", "podmonitors"]
    verbs: ["get", "list", "watch"]

  # Nodes (for cluster health)
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]

  # RBAC inspection
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: claude-agent-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: claude-agent-role
subjects:
  - kind: ServiceAccount
    name: claude-agent
    namespace: claude
  - kind: ServiceAccount
    name: default
    namespace: claude
EOF
```

### Option 3: Grant Elevated Permissions Temporarily

```bash
# Grant cluster-admin to agent (NOT RECOMMENDED for production)
kubectl create clusterrolebinding claude-agent-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=claude:default
```

---

## Verification After RBAC Application

Once RBAC is applied, verify with:

```bash
# Test namespace access
kubectl get namespaces

# Test pod access
kubectl get pods --all-namespaces

# Test CRD access
kubectl get clusters --all-namespaces
kubectl get redis --all-namespaces

# Test operator access
kubectl get deployments -n infrastructure
```

---

## Next Steps After Unblock

Once RBAC permissions are granted, I will immediately:

### 1. Check Operator Status
- Verify CloudNativePG operator deployment
- Verify Redis operator deployment
- Check operator pod logs for errors
- Confirm CRDs are installed

### 2. Diagnose Database Issues (Issue #52)
- List all PostgreSQL Cluster resources
- Check cluster status for each app
- Verify database pods are running
- Check service DNS records
- Test connectivity from app pods
- Review database logs and events

### 3. Diagnose Redis Issues (Issue #53)
- List Redis custom resources
- Check Redis pod status
- Verify Redis service exists
- Test DNS resolution
- Test connectivity from worker pods
- Review Redis logs

### 4. Apply Fixes
- Deploy missing operators if needed
- Create missing database clusters
- Create missing Redis instances
- Fix resource constraints if found
- Restart application pods

### 5. Verify Resolution
- Test all health endpoints
- Verify database connectivity
- Verify Redis connectivity
- Monitor for errors
- Update GitHub issues with resolution

---

## Infrastructure Design Reference

### Expected Operator Deployments
**Namespace:** `infrastructure`
- CloudNativePG operator
- Redis operator
- MinIO operator (for object storage)

### Expected Database Clusters
**Namespace:** `crystalshards`
- Cluster: `crystalshards-postgres`
- Service: `crystalshards-postgres-rw.crystalshards.svc.cluster.local`

**Namespace:** `crystaldocs`
- Cluster: `crystaldocs-postgres`
- Service: `crystaldocs-postgres-rw.crystaldocs.svc.cluster.local`

**Namespace:** `crystalgigs`
- Cluster: `crystalgigs-postgres`
- Service: `crystalgigs-postgres-rw.crystalgigs.svc.cluster.local`

**Namespace:** `crystalbits`
- Cluster: `crystalbits-postgres`
- Service: `crystalbits-postgres-rw.crystalbits.svc.cluster.local`

### Expected Redis Instance
**Namespace:** `infrastructure`
- Redis: `redis-master`
- Service: `redis-master.infrastructure.svc.cluster.local:6379`

---

## Lessons Learned

### Prevention Measures
1. **RBAC should be applied first** in any infrastructure deployment
2. **Agent deployment should include RBAC verification** step
3. **CI/CD should validate** that agent has necessary permissions
4. **Terraform state backend access** should be verified before deployment
5. **Bootstrap process** should be documented and tested

### Monitoring Gaps
1. No alerting for agent permission failures
2. No validation that RBAC configurations are applied
3. No health check for Terraform state backend access

### Documentation Gaps
1. No runbook for agent bootstrap process
2. No troubleshooting guide for permission issues
3. No escalation path when agent is blocked

---

## Recommendation: Infrastructure Bootstrap Process

Create a documented bootstrap process:

1. **Apply cluster foundation:**
   - Namespaces
   - Service accounts
   - RBAC (ClusterRoles, ClusterRoleBindings)

2. **Verify agent access:**
   - Test permissions with `kubectl auth can-i`
   - Validate agent can read all necessary resources

3. **Deploy operators:**
   - CloudNativePG
   - Redis
   - MinIO

4. **Deploy application infrastructure:**
   - Database clusters
   - Redis instances
   - Storage buckets

5. **Deploy applications:**
   - API deployments
   - Worker deployments
   - Web deployments

6. **Verify health:**
   - All pods running
   - All services accessible
   - Health endpoints returning 200

This ensures proper ordering and prevents permission-related blockers.

---

## Contact for Resolution

This report has been posted to:
- GitHub Issue #52 (Database Connectivity)
- GitHub Issue #53 (Redis Connectivity)

**Priority:** CRITICAL
**Blocking:** All infrastructure diagnosis and remediation work
**Required:** Manual intervention by cluster administrator

---

## Appendix: Terraform Configuration References

**Agent RBAC Configuration:**
`/workspaces/monorepo/terraform/modules/agent/main.tf`

**Operator Module:**
`/workspaces/monorepo/terraform/modules/operators/`

**Application Modules:**
- `/workspaces/monorepo/apps/crystalshards/terraform/`
- `/workspaces/monorepo/apps/crystaldocs/terraform/`
- `/workspaces/monorepo/apps/crystalgigs/terraform/`
- `/workspaces/monorepo/apps/crystalbits/terraform/`

**Terraform Backend Config:**
`/workspaces/monorepo/terraform/terraform.tf`
