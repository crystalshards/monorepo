# Manual Infrastructure Deployment Runbook
**Date:** 2025-10-10
**Purpose:** Manual deployment of infrastructure when Terraform is unavailable
**Applies to:** Issues #52 (Database Connectivity) and #53 (Redis Connectivity)

## Prerequisites

You must have:
- `cluster-admin` role or equivalent permissions
- `kubectl` configured to access the cluster
- `helm` CLI installed

## Step 1: Apply Agent RBAC

First, grant the claude-agent necessary permissions to monitor infrastructure:

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

Verify RBAC was applied:
```bash
kubectl get clusterrole claude-agent-role
kubectl get clusterrolebinding claude-agent-binding
```

## Step 2: Ensure Infrastructure Namespace Exists

```bash
kubectl create namespace infrastructure --dry-run=client -o yaml | kubectl apply -f -
```

Verify:
```bash
kubectl get namespace infrastructure
```

## Step 3: Deploy CloudNativePG Operator

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace infrastructure \
  --version 0.19.1 \
  --set replicaCount=1 \
  --set resources.limits.cpu=200m \
  --set resources.limits.memory=256Mi \
  --wait \
  --timeout 10m
```

Verify deployment:
```bash
kubectl get deployment -n infrastructure -l app.kubernetes.io/name=cloudnative-pg
kubectl get pods -n infrastructure -l app.kubernetes.io/name=cloudnative-pg
kubectl logs -n infrastructure -l app.kubernetes.io/name=cloudnative-pg --tail=50
```

Check CRD is installed:
```bash
kubectl get crd clusters.postgresql.cnpg.io
```

## Step 4: Deploy Redis Operator

```bash
helm repo add redis-operator https://ot-container-kit.github.io/helm-charts
helm repo update

helm upgrade --install redis-operator redis-operator/redis-operator \
  --namespace infrastructure \
  --version 0.15.0 \
  --set replicaCount=1 \
  --set resources.requests.cpu=50m \
  --set resources.requests.memory=64Mi \
  --set resources.limits.cpu=100m \
  --set resources.limits.memory=128Mi \
  --wait \
  --timeout 10m
```

Verify deployment:
```bash
kubectl get deployment -n infrastructure -l app.kubernetes.io/name=redis-operator
kubectl get pods -n infrastructure -l app.kubernetes.io/name=redis-operator
kubectl logs -n infrastructure -l app.kubernetes.io/name=redis-operator --tail=50
```

Check CRD is installed:
```bash
kubectl get crd redis.redis.opstreelabs.in
```

## Step 5: Deploy Shared Redis Instance

```bash
kubectl apply -f - <<'EOF'
apiVersion: redis.redis.opstreelabs.in/v1beta1
kind: Redis
metadata:
  name: shared-redis
  namespace: infrastructure
spec:
  kubernetesConfig:
    image: redis:7-alpine
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
    service:
      type: ClusterIP
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 5Gi
        storageClassName: standard-rwo
  redisConfig:
    maxmemory: "256mb"
    maxmemory-policy: "allkeys-lru"
EOF
```

Wait for Redis to be ready:
```bash
kubectl wait --for=condition=ready pod -l app=shared-redis -n infrastructure --timeout=5m
```

Verify Redis deployment:
```bash
kubectl get redis -n infrastructure
kubectl get pods -n infrastructure -l app=shared-redis
kubectl get service -n infrastructure shared-redis
kubectl describe redis shared-redis -n infrastructure
```

Test Redis connectivity:
```bash
kubectl run redis-test --image=redis:7-alpine -n infrastructure --rm -it --restart=Never -- \
  redis-cli -h shared-redis.infrastructure.svc.cluster.local ping
```

Expected output: `PONG`

## Step 6: Create Application Namespaces

```bash
for ns in crystalshards crystaldocs crystalgigs crystalbits; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done
```

Verify:
```bash
kubectl get namespaces | grep crystal
```

## Step 7: Deploy PostgreSQL Clusters for Each Application

### CrystalShards Database

```bash
kubectl apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: crystalshards-postgres
  namespace: crystalshards
spec:
  instances: 3
  primaryUpdateStrategy: unsupervised

  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"
      maintenance_work_mem: "64MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "1.1"
      effective_io_concurrency: "200"
      work_mem: "2621kB"
      min_wal_size: "1GB"
      max_wal_size: "4GB"

  storage:
    size: 10Gi
    storageClass: standard-rwo

  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"

  monitoring:
    enablePodMonitor: true
EOF
```

### CrystalDocs Database

```bash
kubectl apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: crystaldocs-postgres
  namespace: crystaldocs
spec:
  instances: 3
  primaryUpdateStrategy: unsupervised

  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"
      maintenance_work_mem: "64MB"

  storage:
    size: 10Gi
    storageClass: standard-rwo

  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"

  monitoring:
    enablePodMonitor: true
EOF
```

### CrystalGigs Database

```bash
kubectl apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: crystalgigs-postgres
  namespace: crystalgigs
spec:
  instances: 3
  primaryUpdateStrategy: unsupervised

  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"

  storage:
    size: 10Gi
    storageClass: standard-rwo

  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"

  monitoring:
    enablePodMonitor: true
EOF
```

### CrystalBits Database

```bash
kubectl apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: crystalbits-postgres
  namespace: crystalbits
spec:
  instances: 3
  primaryUpdateStrategy: unsupervised

  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"

  storage:
    size: 10Gi
    storageClass: standard-rwo

  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"

  monitoring:
    enablePodMonitor: true
EOF
```

### Wait for All Clusters to be Ready

```bash
# This may take 5-10 minutes
kubectl wait --for=condition=Ready cluster/crystalshards-postgres -n crystalshards --timeout=10m
kubectl wait --for=condition=Ready cluster/crystaldocs-postgres -n crystaldocs --timeout=10m
kubectl wait --for=condition=Ready cluster/crystalgigs-postgres -n crystalgigs --timeout=10m
kubectl wait --for=condition=Ready cluster/crystalbits-postgres -n crystalbits --timeout=10m
```

### Verify All Database Clusters

```bash
kubectl get clusters --all-namespaces
kubectl get pods -n crystalshards -l cnpg.io/cluster=crystalshards-postgres
kubectl get pods -n crystaldocs -l cnpg.io/cluster=crystaldocs-postgres
kubectl get pods -n crystalgigs -l cnpg.io/cluster=crystalgigs-postgres
kubectl get pods -n crystalbits -l cnpg.io/cluster=crystalbits-postgres
```

### Verify Database Services Exist

```bash
kubectl get service crystalshards-postgres-rw -n crystalshards
kubectl get service crystaldocs-postgres-rw -n crystaldocs
kubectl get service crystalgigs-postgres-rw -n crystalgigs
kubectl get service crystalbits-postgres-rw -n crystalbits
```

## Step 8: Test DNS Resolution

Test that services are resolvable from within the cluster:

```bash
# Test from crystalshards namespace
kubectl run dns-test --image=busybox:1.36 -n crystalshards --rm -it --restart=Never -- \
  nslookup crystalshards-postgres-rw.crystalshards.svc.cluster.local

kubectl run dns-test --image=busybox:1.36 -n crystalshards --rm -it --restart=Never -- \
  nslookup shared-redis.infrastructure.svc.cluster.local
```

Expected: Both should resolve to IP addresses.

## Step 9: Restart Application Pods

Now that infrastructure is healthy, restart all application deployments:

```bash
# CrystalShards
kubectl rollout restart deployment/crystalshards-api -n crystalshards
kubectl rollout restart deployment/crystalshards-worker -n crystalshards

# CrystalDocs
kubectl rollout restart deployment/crystaldocs-api -n crystaldocs

# CrystalGigs
kubectl rollout restart deployment/crystalgigs-api -n crystalgigs

# CrystalBits
kubectl rollout restart deployment/crystalbits-api -n crystalbits

# Wait for rollouts to complete
kubectl rollout status deployment/crystalshards-api -n crystalshards
kubectl rollout status deployment/crystalshards-worker -n crystalshards
kubectl rollout status deployment/crystaldocs-api -n crystaldocs
kubectl rollout status deployment/crystalgigs-api -n crystalgigs
kubectl rollout status deployment/crystalbits-api -n crystalbits
```

## Step 10: Verify Application Health

Check pod status:
```bash
kubectl get pods -n crystalshards
kubectl get pods -n crystaldocs
kubectl get pods -n crystalgigs
kubectl get pods -n crystalbits
```

Check pod logs for any connection errors:
```bash
kubectl logs -n crystalshards -l app=crystalshards-api --tail=50
kubectl logs -n crystalshards -l app=crystalshards-worker --tail=50
kubectl logs -n crystaldocs -l app=crystaldocs-api --tail=50
kubectl logs -n crystalgigs -l app=crystalgigs-api --tail=50
kubectl logs -n crystalbits -l app=crystalbits-api --tail=50
```

Test health endpoints:
```bash
curl -v https://crystalshards.org/api/health
curl -v https://crystaldocs.org/api/health
curl -v https://crystalgigs.com/api/health
curl -v https://crystalbits.org/api/health
```

All should return `200 OK`.

## Step 11: Verify Database Connectivity from Pods

Test PostgreSQL connection from an app pod:
```bash
kubectl exec -it -n crystalshards $(kubectl get pod -n crystalshards -l app=crystalshards-api -o jsonpath='{.items[0].metadata.name}') -- sh

# Inside the pod:
# Extract DATABASE_URL from environment
echo $DATABASE_URL

# If psql is available, test connection:
psql $DATABASE_URL -c "SELECT version();"
```

## Step 12: Verify Redis Connectivity from Worker Pods

Test Redis connection from a worker pod:
```bash
kubectl exec -it -n crystalshards $(kubectl get pod -n crystalshards -l app=crystalshards-worker -o jsonpath='{.items[0].metadata.name}') -- sh

# Inside the pod:
# If redis-cli is available:
redis-cli -h shared-redis.infrastructure.svc.cluster.local ping

# Expected output: PONG
```

## Troubleshooting

### Operators Not Starting

Check pod events:
```bash
kubectl describe pod -n infrastructure -l app.kubernetes.io/name=cloudnative-pg
kubectl describe pod -n infrastructure -l app.kubernetes.io/name=redis-operator
```

Common issues:
- ImagePullBackOff: Check image name and registry access
- CrashLoopBackOff: Check logs for errors
- Pending: Check resource requests vs GKE Autopilot limits

### Database Clusters Not Ready

Check cluster status:
```bash
kubectl describe cluster crystalshards-postgres -n crystalshards
kubectl get events -n crystalshards --sort-by='.lastTimestamp'
```

Common issues:
- PVC not binding: Check storage class exists
- Resource constraints: Adjust CPU/memory requests
- Image pull issues: Check network and registry access

### Redis Not Starting

Check Redis resource:
```bash
kubectl describe redis shared-redis -n infrastructure
kubectl get events -n infrastructure --sort-by='.lastTimestamp'
```

Common issues:
- Operator not ready: Wait for operator to be fully deployed
- PVC not binding: Check storage class
- Resource constraints: Adjust CPU/memory requests

### DNS Resolution Failing

Check CoreDNS:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

Check service exists:
```bash
kubectl get service -n <namespace> <service-name>
```

### Application Pods CrashLooping

Check logs:
```bash
kubectl logs -n <namespace> <pod-name> --previous
kubectl describe pod -n <namespace> <pod-name>
```

Common issues:
- Database connection timeout: Database may not be ready yet
- Redis connection timeout: Redis may not be ready yet
- Missing secrets: Check that secrets exist
- Resource limits: Check OOMKilled events

## Success Criteria

All of the following should be true:

- [ ] CloudNativePG operator is running
- [ ] Redis operator is running
- [ ] All 4 PostgreSQL clusters show status "Cluster in healthy state"
- [ ] Redis instance `shared-redis` is running
- [ ] All database services (`*-postgres-rw`) are accessible
- [ ] Redis service `shared-redis` is accessible
- [ ] Application pods are running without CrashLoopBackOff
- [ ] All health endpoints return 200 OK
- [ ] No database connectivity errors in application logs
- [ ] No Redis connectivity errors in worker logs

## Rollback Procedure

If something goes wrong, rollback in reverse order:

```bash
# Delete application database clusters
kubectl delete cluster crystalshards-postgres -n crystalshards
kubectl delete cluster crystaldocs-postgres -n crystaldocs
kubectl delete cluster crystalgigs-postgres -n crystalgigs
kubectl delete cluster crystalbits-postgres -n crystalbits

# Delete Redis
kubectl delete redis shared-redis -n infrastructure

# Uninstall operators
helm uninstall redis-operator -n infrastructure
helm uninstall cnpg -n infrastructure

# Note: Do NOT delete application pods - they will restart with old configuration
```

## Notes

- GKE Autopilot has specific CPU/memory ranges - adjust if pods are rejected
- Storage class `standard-rwo` is the default for GKE Autopilot
- Database cluster initialization takes 5-10 minutes
- Redis should be ready in 1-2 minutes
- Always check events and logs when troubleshooting

## Post-Deployment

After successful deployment:

1. Update GitHub issues #52 and #53 with resolution details
2. Monitor application logs for 15-30 minutes
3. Set up alerts for database/Redis connectivity failures
4. Document any deviations from this runbook
5. Update Terraform state if possible to match deployed resources
