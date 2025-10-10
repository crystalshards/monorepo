# Agent RBAC Configuration

This document describes the read-only RBAC configuration for the CrystalShards agent running in the `claude` namespace.

## Overview

The agent needs read-only access to cluster resources for debugging and monitoring purposes. This configuration follows the principle of least privilege - providing only the permissions necessary for read-only operations.

## Components

### 1. Namespace: `claude`
- **File**: `resource.kubernetes_namespace.claude.tf`
- **Purpose**: Dedicated namespace for the agent pod and related resources

### 2. ServiceAccount: `crystalshards-agent`
- **File**: `resource.kubernetes_service_account.agent_sa.tf`
- **Namespace**: `claude`
- **Purpose**: Identity for the agent pod to authenticate with the Kubernetes API

### 3. ClusterRole: `crystalshards-agent-readonly`
- **File**: `resource.kubernetes_cluster_role.agent_readonly.tf`
- **Purpose**: Defines read-only permissions across all namespaces
- **Scope**: Cluster-wide

### 4. ClusterRoleBinding: `crystalshards-agent-readonly`
- **File**: `resource.kubernetes_cluster_role_binding.agent_readonly.tf`
- **Purpose**: Binds the ClusterRole to the agent ServiceAccount

## Permissions Granted

The agent has **read-only** access to the following resources:

### Core Resources
- **Pods**: get, list, watch (including logs and status)
- **Services**: get, list, watch
- **Endpoints**: get, list, watch
- **ConfigMaps**: get, list
- **Secrets**: get, list
- **Events**: get, list, watch
- **Namespaces**: get, list, watch
- **PersistentVolumeClaims**: get, list, watch
- **PersistentVolumes**: get, list, watch
- **Nodes**: get, list, watch

### Workload Resources
- **Deployments**: get, list, watch
- **StatefulSets**: get, list, watch
- **DaemonSets**: get, list, watch
- **ReplicaSets**: get, list, watch
- **Jobs**: get, list, watch
- **CronJobs**: get, list, watch

### Networking Resources
- **NetworkPolicies**: get, list, watch
- **Ingresses**: get, list, watch

### Operator CRDs
- **CNPG PostgreSQL**: clusters, backups, scheduledbackups, poolers
- **Redis Operator**: redis, redisclusters, redissentinels, redisreplications
- **MinIO Operator**: tenants
- **Cert-Manager**: certificates, certificaterequests, issuers, clusterissuers

### Monitoring Resources
- **Prometheus**: servicemonitors, prometheusrules, prometheuses, alertmanagers
- **KEDA**: scaledobjects, scaledjobs, triggerauthentications
- **HorizontalPodAutoscalers**: get, list, watch

### RBAC Resources (Read-Only)
- **Roles**: get, list, watch
- **RoleBindings**: get, list, watch
- **ClusterRoles**: get, list, watch
- **ClusterRoleBindings**: get, list, watch

### Storage Resources
- **StorageClasses**: get, list, watch

## Permissions NOT Granted

The agent **cannot**:
- Create, update, or delete any resources
- Patch resources
- Execute commands in pods (no exec access)
- Port-forward
- Attach to pods
- Modify RBAC rules
- Access resources in the `kube-system` namespace (except via ClusterRole)

## Deployment

### Apply via Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This will create:
1. `claude` namespace
2. `crystalshards-agent` service account
3. `crystalshards-agent-readonly` ClusterRole
4. `crystalshards-agent-readonly` ClusterRoleBinding

### Update Agent Pod

The agent pod manifest (`kubernetes-dev-pod.yaml`) has been updated to use the service account:

```yaml
spec:
  serviceAccountName: crystalshards-agent
```

## Verification

### 1. Verify Service Account
```bash
kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster get serviceaccount crystalshards-agent -n claude
```

### 2. Verify ClusterRole
```bash
kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster get clusterrole crystalshards-agent-readonly
kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster describe clusterrole crystalshards-agent-readonly
```

### 3. Verify ClusterRoleBinding
```bash
kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster get clusterrolebinding crystalshards-agent-readonly
kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster describe clusterrolebinding crystalshards-agent-readonly
```

### 4. Test Read Permissions (from within agent pod)

```bash
# Should succeed - list pods in all namespaces
kubectl get pods --all-namespaces

# Should succeed - view PostgreSQL clusters
kubectl get clusters.postgresql.cnpg.io -A

# Should succeed - view Redis instances
kubectl get redis.redis.redis.opstreelabs.in -A

# Should succeed - view logs
kubectl logs -n crystalshards <pod-name>

# Should succeed - describe resources
kubectl describe deployment -n crystalshards crystalshards-api
```

### 5. Test Write Restrictions (from within agent pod)

```bash
# Should fail - cannot create pods
kubectl run test --image=nginx -n claude
# Error: forbidden: User "system:serviceaccount:claude:crystalshards-agent" cannot create resource "pods"

# Should fail - cannot delete pods
kubectl delete pod <pod-name> -n claude
# Error: forbidden: User "system:serviceaccount:claude:crystalshards-agent" cannot delete resource "pods"

# Should fail - cannot edit configmaps
kubectl edit configmap <name> -n claude
# Error: forbidden: User "system:serviceaccount:claude:crystalshards-agent" cannot update resource "configmaps"
```

## Troubleshooting

### Permission Denied Errors

If the agent encounters permission denied errors:

1. **Check the pod is using the service account**:
   ```bash
   kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster get pod crystalshards-agent -n claude -o jsonpath='{.spec.serviceAccountName}'
   ```
   Should output: `crystalshards-agent`

2. **Verify ClusterRoleBinding exists**:
   ```bash
   kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster get clusterrolebinding crystalshards-agent-readonly -o yaml
   ```

3. **Check RBAC rules are applied**:
   ```bash
   kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster auth can-i list pods --as=system:serviceaccount:claude:crystalshards-agent
   kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster auth can-i get clusters.postgresql.cnpg.io --as=system:serviceaccount:claude:crystalshards-agent
   ```
   Should output: `yes`

4. **Verify write operations are blocked**:
   ```bash
   kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster auth can-i delete pods --as=system:serviceaccount:claude:crystalshards-agent
   ```
   Should output: `no`

### Adding New Permissions

If the agent needs additional read permissions:

1. Edit `resource.kubernetes_cluster_role.agent_readonly.tf`
2. Add new `rule` blocks with appropriate API groups and resources
3. Ensure only read verbs are used: `get`, `list`, `watch`
4. Apply changes: `terraform plan && terraform apply`

**Example**:
```hcl
rule {
  api_groups = ["example.io"]
  resources  = ["exampleresources"]
  verbs      = ["get", "list", "watch"]
}
```

## Security Considerations

1. **Read-Only by Design**: All permissions use only read verbs (get, list, watch)
2. **No Exec Access**: Agent cannot execute commands in pods
3. **Secrets Access**: Limited to reading secret metadata (names, namespaces) - not recommended to read secret values
4. **Cluster-Wide Scope**: Agent can view resources across all namespaces for debugging
5. **No Modification Rights**: Agent cannot create, update, or delete any resources

## Integration with Issue #24

This RBAC configuration addresses issue #24 by providing the agent with the necessary permissions to:
- Debug pod health check failures
- View deployment configurations
- Check PostgreSQL cluster status (CNPG)
- Review Redis operator status
- Inspect network policies and ingress configurations
- View resource events and logs

The agent can now investigate infrastructure issues without requiring admin-level access.

## Kubectl Context Variable

All shell scripts have been updated to use the `KUBECTL_CONTEXT` environment variable:

```bash
export KUBECTL_CONTEXT=gke_crystalshards-org_us-central1_crystalshards-cluster
./start-remote-agent.sh
```

**Updated scripts**:
- `start-remote-agent.sh`
- `remote-claude.sh`
- `scripts/verify-grafana-deployment.sh`
- `scripts/deploy-infrastructure.sh`

Default context: `gke_crystalshards-org_us-central1_crystalshards-cluster`

## References

- Kubernetes RBAC documentation: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Service Account documentation: https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- CrystalShards GitHub Issue #24: Pod Health Check Failures
