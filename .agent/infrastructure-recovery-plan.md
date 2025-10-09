# Infrastructure Recovery Plan

**Status**: Ready for Execution
**Requires**: Human operator with cluster-admin access
**Estimated Duration**: 20-30 minutes

## Problem Summary

The entire CrystalShards infrastructure has never been deployed. All Terraform configuration is complete but has not been applied to the cluster. This is causing a complete platform outage.

## What's Missing

- All application namespaces (crystalshards, crystaldocs, crystalgigs, crystalbits)
- Infrastructure namespace
- All operators (CloudNativePG, Redis, MinIO)
- All PostgreSQL clusters (4 instances)
- Redis cluster (shared)
- MinIO tenant (shared)
- Agent RBAC permissions

## Recovery Steps

### Option 1: Full Terraform Apply (Recommended)

Apply the complete Terraform configuration to provision all infrastructure:

```bash
# Navigate to terraform directory
cd /workspaces/monorepo/terraform

# Initialize Terraform
# Note: GCS backend may have permission issues
# If terraform init fails, see Option 2 below
terraform init -reconfigure

# Generate and review plan
terraform plan -out=tfplan

# Review the plan output carefully
# Should show creation of:
# - 4 app namespaces + infrastructure namespace + claude namespace
# - ClusterRole: claude-agent-role
# - ClusterRoleBinding: claude-agent-binding
# - Multiple Helm releases (CNPG, Redis Operator, MinIO Operator)
# - PostgreSQL clusters (4)
# - Redis cluster (1)
# - MinIO tenant (1)
# - Kubernetes secrets (multiple)

# Apply the plan
terraform apply tfplan
```

### Option 2: Local Backend (If GCS Fails)

If GCS backend access fails with permission error:

```bash
cd /workspaces/monorepo/terraform

# Comment out GCS backend in terraform.tf
# Or create a backend override
cat > backend_override.tf <<'EOF'
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF

# Initialize with local backend
terraform init -reconfigure -migrate-state

# Continue with plan and apply
terraform plan -out=tfplan
terraform apply tfplan
```

### Option 3: Manual RBAC First (Minimal Fix)

If you only want to grant agent permissions first (to enable diagnostics):

```bash
# Apply only the agent module
cd /workspaces/monorepo/terraform

# Extract agent resources
terraform plan -target=module.agent -out=tfplan-agent

# Review (should only show RBAC resources)
terraform show tfplan-agent

# Apply
terraform apply tfplan-agent

# Verify agent can now access cluster
kubectl auth can-i list pods --as=system:serviceaccount:claude:default -A
# Should return: yes
```

## Verification Steps

After applying Terraform, verify the deployment:

### 1. Check Namespaces

```bash
kubectl get namespaces

# Expected output should include:
# NAME              STATUS   AGE
# claude            Active   1m
# crystalshards     Active   1m
# crystaldocs       Active   1m
# crystalgigs       Active   1m
# crystalbits       Active   1m
# infrastructure    Active   1m
```

### 2. Check Operators

```bash
kubectl get pods -n infrastructure

# Expected output (may take 5-10 minutes):
# NAME                                      READY   STATUS    RESTARTS   AGE
# cloudnativepg-operator-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
# redis-operator-xxxxxxxxxx-xxxxx           1/1     Running   0          5m
# minio-operator-xxxxxxxxxx-xxxxx           1/1     Running   0          5m
```

### 3. Check CRDs Installed

```bash
kubectl api-resources | grep -E "cluster|redis|tenant"

# Expected output:
# clusters                          postgresql.cnpg.io/v1          true         Cluster
# redis                             redis.redis.opstreelabs.in/v1  true         Redis
# tenants                           minio.min.io/v2                true         Tenant
```

### 4. Check PostgreSQL Clusters

```bash
kubectl get cluster.postgresql.cnpg.io -A

# Expected output (4 clusters):
# NAMESPACE        NAME                AGE
# crystalshards    crystalshards-db    5m
# crystaldocs      crystaldocs-db      5m
# crystalgigs      crystalgigs-db      5m
# crystalbits      crystalbits-db      5m

# Check cluster status
kubectl get cluster.postgresql.cnpg.io -A -o wide

# All clusters should show: PHASE=Ready
```

### 5. Check Redis

```bash
kubectl get redis -n infrastructure

# Expected output:
# NAME              REPLICAS   AGE
# shared-redis      1          5m
```

### 6. Check MinIO

```bash
kubectl get tenant -n infrastructure

# Expected output:
# NAME            STATE     AGE
# shared-minio    Ready     5m
```

### 7. Verify Agent RBAC

```bash
# Check ClusterRole exists
kubectl get clusterrole claude-agent-role

# Check ClusterRoleBinding exists
kubectl get clusterrolebinding claude-agent-binding

# Test agent permissions
kubectl auth can-i list namespaces --as=system:serviceaccount:claude:default
# Should return: yes

kubectl auth can-i list pods --as=system:serviceaccount:claude:default -A
# Should return: yes

kubectl auth can-i get secrets --as=system:serviceaccount:claude:default -n crystalshards
# Should return: yes
```

### 8. Watch Application Pods

Once infrastructure is ready, application pods should start automatically:

```bash
# Watch all pods in app namespaces
watch -n 5 "kubectl get pods -A | grep -E 'crystalshards|crystaldocs|crystalgigs|crystalbits'"

# Wait for all pods to show: 1/1 Running
# This may take 5-10 minutes as pods:
# 1. Wait for databases to be ready
# 2. Run database migrations
# 3. Start application servers
```

### 9. Test Application Health

Once pods are running, test health endpoints:

```bash
# Test each application (from inside cluster)
for app in crystalshards crystaldocs crystalgigs crystalbits; do
  echo "=== Testing $app ==="
  kubectl exec -n $app -it $(kubectl get pod -n $app -l app=$app -o jsonpath='{.items[0].metadata.name}') -- curl -s localhost:5000/health
  echo ""
done

# Expected output from each:
# {"status":"ok","version":"0.1.0","timestamp":"2025-10-09T..."}
```

## Troubleshooting

### Issue: Terraform init fails with GCS permission error

**Error**:
```
Error: Failed to get existing workspaces: querying Cloud Storage failed:
googleapi: Error 403: 632122948866-compute@developer.gserviceaccount.com
does not have storage.objects.list access to the Google Cloud Storage bucket.
```

**Solution**: Use local backend (see Option 2 above) or fix GCS permissions:

```bash
SA_EMAIL="632122948866-compute@developer.gserviceaccount.com"
PROJECT_ID="your-project-id"  # Replace with actual
BUCKET_NAME="${PROJECT_ID}-terraform-state"

gsutil iam ch serviceAccount:${SA_EMAIL}:roles/storage.objectViewer gs://${BUCKET_NAME}
```

### Issue: Helm releases fail to install

**Symptom**: Terraform apply fails on Helm resources

**Solution**: Check cluster connectivity and Helm version:

```bash
# Verify cluster access
kubectl cluster-info

# Check Helm version
helm version

# Manually test operator installation
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm search repo cnpg
```

### Issue: PostgreSQL clusters stuck in Pending

**Symptom**: Clusters created but not becoming Ready

**Solution**: Check operator logs:

```bash
kubectl logs -n infrastructure -l app.kubernetes.io/name=cloudnative-pg --tail=50

# Check cluster status
kubectl describe cluster crystalshards-db -n crystalshards
```

### Issue: Pods stuck in Pending

**Symptom**: Pods created but not scheduled

**Solution**: Check node resources:

```bash
# Check node status
kubectl get nodes

# Check pod events
kubectl get events -n crystalshards --sort-by='.lastTimestamp' | tail -20

# Describe pending pod
kubectl describe pod -n crystalshards <pod-name>
```

## Success Criteria

Infrastructure deployment is successful when:

- ✅ All 6 namespaces exist (4 apps + infrastructure + claude)
- ✅ All operators are Running (CNPG, Redis, MinIO)
- ✅ All CRDs are installed (clusters, redis, tenants)
- ✅ All 4 PostgreSQL clusters are Ready
- ✅ Redis cluster is Running
- ✅ MinIO tenant is Ready
- ✅ Agent RBAC is configured (can list pods)
- ✅ All application pods are Running (1/1 Ready)
- ✅ All health checks return HTTP 200 OK

## Timeline Estimate

- Terraform apply: 10-15 minutes
- Operator installation: 2-5 minutes
- Database initialization: 5-10 minutes
- Application pod startup: 3-5 minutes
- **Total**: 20-35 minutes

## Post-Recovery Actions

After infrastructure is deployed and verified:

1. Run full diagnostic: `bash /workspaces/monorepo/scripts/diagnose-deployments.sh`
2. Update GitHub issue #24 with results
3. Run E2E tests to verify full functionality
4. Update PER document with actual recovery timeline
5. Document any issues encountered during deployment

## References

- Terraform configuration: `/workspaces/monorepo/terraform/`
- Deployment runbook: `/workspaces/monorepo/terraform/DEPLOYMENT_RUNBOOK.md`
- Agent RBAC config: `/workspaces/monorepo/terraform/modules/agent/main.tf`
- PER document: `/workspaces/monorepo/pers/2025-10-09-infrastructure-unavailable-outage.md`
- GitHub issue: https://github.com/crystalshards/monorepo/issues/24

## Contact

This recovery plan was created by the SRE Agent. For questions or issues during execution, update GitHub issue #24.
