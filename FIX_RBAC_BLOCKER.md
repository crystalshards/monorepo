# URGENT: Fix RBAC Blocker for Agent

**Issue:** Agent cannot diagnose or fix database connectivity issues (#52) due to missing RBAC permissions.

**Status:** BLOCKED - Requires manual intervention by cluster administrator.

## Problem

The `claude-agent` service account has minimal permissions and cannot:
- List namespaces or pods
- Check operator deployments
- View database clusters
- Inspect logs or events
- Perform any infrastructure diagnosis

The RBAC configuration exists in Terraform (`terraform/modules/agent/main.tf`) but was **never applied to the cluster**.

## Solution

A cluster administrator must apply the RBAC configuration. Two options:

### Option 1: Apply via kubectl (Fastest)

```bash
kubectl apply -f - <<'EOF'
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

### Option 2: Apply via Terraform (Preferred for production)

First, fix Terraform state backend access, then:

```bash
cd /workspaces/monorepo/terraform
terraform init
terraform apply -target=module.agent -auto-approve
```

## Verification

After applying, verify permissions work:

```bash
# These should now succeed (run as agent)
kubectl get namespaces
kubectl get pods --all-namespaces
kubectl get clusters --all-namespaces
```

## Next Steps After Fix

Once RBAC is applied, the agent can:
1. Check CloudNativePG operator status
2. Verify PostgreSQL clusters exist
3. Check Redis operator and instance
4. Diagnose actual connectivity issues
5. Apply fixes for database/Redis problems

## Related Documentation

- Full diagnosis report: `infrastructure-diagnosis-2025-10-10.md`
- Complete deployment runbook: `MANUAL_INFRASTRUCTURE_DEPLOYMENT.md`
- Terraform RBAC config: `terraform/modules/agent/main.tf`

## Security Note

The RBAC configuration grants **read-only** permissions for monitoring and troubleshooting. The agent cannot:
- Create or modify resources
- Delete anything
- Update secrets
- Change RBAC policies

This follows least-privilege principles for an SRE monitoring agent.
