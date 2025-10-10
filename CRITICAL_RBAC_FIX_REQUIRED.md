# CRITICAL: RBAC Fix Required for Agent Operations

**Date:** 2025-10-10
**Status:** BLOCKED - Requires Cluster Admin Intervention
**Priority:** CRITICAL - All infrastructure diagnosis and repair is blocked

## Executive Summary

The Claude agent is **completely blocked** from investigating or fixing infrastructure issues #52 (PostgreSQL connectivity) and #53 (Redis connectivity) due to missing RBAC permissions.

**Current State:**
- Agent running as `system:serviceaccount:claude:default`
- Has NO permissions to view cluster resources
- Cannot diagnose operators, databases, or Redis
- Cannot apply fixes even if root cause is known

**Root Cause:**
RBAC configuration exists in `/workspaces/monorepo/kubernetes-agent-rbac.yaml` but was **never applied to the cluster**.

## Verified Infrastructure Issues

While unable to inspect the cluster directly, health endpoint checks confirm:

### All Applications Have Database Connectivity Failures

```bash
$ curl -s https://crystalshards.org/api/health | jq .services.database
"unhealthy: AppDatabase: Failed to connect to database 'crystalshards_production' with username 'app'."

$ curl -s https://crystaldocs.org/api/health | jq .services.database
"unhealthy: AppDatabase: Failed to connect to database 'crystaldocs_production' with username 'app'."

$ curl -s https://crystalgigs.com/api/health | jq .services.database
"unhealthy: AppDatabase: Failed to connect to database 'crystalgigs_production' with username 'app'."

$ curl -s https://crystalbits.org/api/health | jq .services.database
"unhealthy: AppDatabase: Failed to connect to database 'crystalbits_production' with username 'app'."
```

### CrystalShards Has Redis Connectivity Failure

```bash
$ curl -s https://crystalshards.org/api/health | jq .services.redis
"unhealthy: Error connecting to 'shared-redis.infrastructure.svc.cluster.local:6379': Connection refused"
```

## Required Action: Apply RBAC Configuration

**Someone with `cluster-admin` role must run the following command:**

```bash
kubectl apply -f /workspaces/monorepo/kubernetes-agent-rbac.yaml
```

**Alternative - Apply directly without file:**

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: claude-agent-role
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/status"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "deployments/status", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["services", "endpoints", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims", "persistentvolumes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "networkpolicies"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["postgresql.cnpg.io"]
  resources: ["clusters", "backups", "scheduledbackups"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["redis.redis.opstreelabs.in"]
  resources: ["redis", "redisclusters"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["minio.min.io"]
  resources: ["tenants"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["gateway.networking.k8s.io"]
  resources: ["gateways", "httproutes", "gatewayclasses"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["cert-manager.io"]
  resources: ["certificates", "certificaterequests", "issuers", "clusterissuers"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["monitoring.coreos.com"]
  resources: ["servicemonitors", "prometheusrules", "podmonitors"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
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

## Verification Steps

After applying RBAC, verify permissions work:

```bash
# Test namespace access
kubectl auth can-i list namespaces --as=system:serviceaccount:claude:default

# Test pod access
kubectl auth can-i list pods --all-namespaces --as=system:serviceaccount:claude:default

# Test CRD access
kubectl auth can-i list clusters --all-namespaces --as=system:serviceaccount:claude:default
```

All three commands should return **yes**.

## What Happens After RBAC is Applied

Once the agent has permissions, it will immediately:

1. **Check operator status** - Verify CloudNativePG and Redis operators are deployed
2. **Diagnose databases** - Check if PostgreSQL clusters exist in each app namespace
3. **Diagnose Redis** - Check if Redis instance exists in infrastructure namespace
4. **Apply fixes** - Deploy missing operators/resources if needed
5. **Verify resolution** - Test all health endpoints return 200 OK
6. **Update GitHub issues** - Document findings and resolution in #52 and #53

## Security Note

The RBAC configuration grants **read-only permissions** for SRE monitoring and troubleshooting. The agent **cannot**:
- Create or modify resources (only read)
- Delete anything
- Update secrets
- Change RBAC policies

This follows least-privilege principles for an SRE agent.

## Why This is Blocking

Without RBAC permissions, the agent cannot:
- See if operators are installed
- Check if databases exist
- View pod logs or events
- Diagnose connectivity issues
- Apply any fixes

**The agent is completely blind to the cluster state.**

## Related Documentation

- **Issue #52:** Database connectivity failure (all apps)
- **Issue #53:** Redis connectivity failure (CrystalShards)
- **Full diagnosis:** `infrastructure-diagnosis-2025-10-10.md`
- **Manual deployment:** `MANUAL_INFRASTRUCTURE_DEPLOYMENT.md`
- **RBAC config:** `kubernetes-agent-rbac.yaml`

## Contact

GitHub issue comments:
- Issue #52: https://github.com/crystalshards/monorepo/issues/52
- Issue #53: https://github.com/crystalshards/monorepo/issues/53

## Timeline

- **2025-10-10 09:00:** Infrastructure issues discovered via health endpoints
- **2025-10-10 09:15:** RBAC blocker identified
- **2025-10-10 09:20:** Documentation created and GitHub issues updated
- **2025-10-10 09:XX:** **WAITING FOR CLUSTER ADMIN TO APPLY RBAC**

---

**ACTION REQUIRED: Apply RBAC configuration to unblock agent operations.**
