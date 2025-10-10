# Database and Redis Connectivity Troubleshooting Runbook

**Last Updated:** 2025-10-10
**Owner:** SRE Team
**Related PER:** `/workspaces/monorepo/pers/2025-10-10-database-redis-connectivity-outage.md`

## Overview

This runbook provides step-by-step procedures for diagnosing and resolving database (PostgreSQL via CNPG) and Redis connectivity issues in the CrystalShards platform.

## Prerequisites

- `kubectl` access to GKE cluster
- Terraform CLI installed
- `gcloud` CLI authenticated
- Access to GitHub repository

## Quick Diagnosis

### Check Application Pod Status

```bash
# Check all application namespaces
for ns in crystalshards crystaldocs crystalgigs crystalbits; do
  echo "=== $ns ==="
  kubectl get pods -n $ns
done
```

**Expected Output:** All pods should be `Running` with `READY 2/2` (or `1/1` for workers)

**Problem Indicators:**
- `CrashLoopBackOff` - Application failing to start
- `0/1` or `0/2` Ready - Health checks failing
- `ImagePullBackOff` - Container image issues

### Check Application Logs

```bash
# Check API logs for database errors
kubectl logs -n crystalshards -l component=api --tail=50

# Check worker logs for Redis errors
kubectl logs -n crystalshards -l component=worker --tail=50
```

**Look for:**
- `connection refused` - Service not reachable
- `authentication failed` - Wrong credentials
- `password authentication failed` - Wrong username/password
- `could not connect to server` - Network/DNS issue

### Check Infrastructure Services

```bash
# Check PostgreSQL clusters
kubectl get clusters.postgresql.cnpg.io -A

# Check Redis instances
kubectl get redis -n infrastructure

# Check MinIO tenants
kubectl get tenants.minio.min.io -n infrastructure

# Check all infrastructure services
kubectl get svc -n infrastructure
```

**Expected Output:**
- PostgreSQL clusters: `<app>-postgres` with `Cluster in healthy state`
- Redis: `shared-redis` with status indicators
- Services: `shared-redis`, `shared-storage-hl`, etc.

## PostgreSQL (CNPG) Troubleshooting

### Issue: Applications Cannot Connect to Database

#### Symptom
Application logs show:
```
FATAL: password authentication failed for user "app"
```

#### Root Cause
DATABASE_URL using hardcoded username instead of reading from CNPG secret.

#### Diagnosis Steps

1. **Check CNPG cluster status:**
   ```bash
   kubectl get cluster -n crystalshards
   kubectl describe cluster crystalshards-postgres -n crystalshards
   ```

2. **Check CNPG-generated secret:**
   ```bash
   kubectl get secret crystalshards-postgres-app -n crystalshards
   kubectl get secret crystalshards-postgres-app -n crystalshards -o jsonpath='{.data.username}' | base64 -d
   kubectl get secret crystalshards-postgres-app -n crystalshards -o jsonpath='{.data.password}' | base64 -d
   ```

3. **Check application secret:**
   ```bash
   kubectl get secret crystalshards-secrets -n crystalshards -o jsonpath='{.data.database_url}' | base64 -d
   ```

4. **Verify connection from pod:**
   ```bash
   kubectl exec -n crystalshards deploy/crystalshards-api -- sh -c 'echo "SELECT 1" | psql $DATABASE_URL'
   ```

#### Resolution

**Option 1: Fix Terraform Configuration (RECOMMENDED)**

Edit `/workspaces/monorepo/apps/<app>/terraform/resource.kubernetes_secret.<app>_secrets.tf`:

```hcl
# WRONG - hardcoded username
database_url = "postgresql://app:${data.kubernetes_secret.app_postgres_app.data["password"]}@..."

# CORRECT - read username from secret
database_url = "postgresql://${data.kubernetes_secret.app_postgres_app.data["username"]}:${data.kubernetes_secret.app_postgres_app.data["password"]}@..."
```

Apply the fix:
```bash
cd apps/<app>/terraform
terraform init
terraform apply
```

Restart application pods:
```bash
kubectl rollout restart deployment/<app>-api -n <app>
kubectl rollout restart deployment/<app>-worker -n <app>
```

**Option 2: Manual Secret Fix (TEMPORARY)**

```bash
# Get correct username from CNPG secret
USERNAME=$(kubectl get secret crystalshards-postgres-app -n crystalshards -o jsonpath='{.data.username}' | base64 -d)
PASSWORD=$(kubectl get secret crystalshards-postgres-app -n crystalshards -o jsonpath='{.data.password}' | base64 -d)

# Create corrected DATABASE_URL
DATABASE_URL="postgresql://$USERNAME:$PASSWORD@crystalshards-postgres-rw:5432/crystalshards_production"

# Update application secret
kubectl patch secret crystalshards-secrets -n crystalshards \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/data/database_url\", \"value\": \"$(echo -n $DATABASE_URL | base64 -w0)\"}]"

# Restart pods
kubectl rollout restart deployment/crystalshards-api -n crystalshards
kubectl rollout restart deployment/crystalshards-worker -n crystalshards
```

#### Verification

```bash
# Check pods are running
kubectl get pods -n crystalshards

# Check logs for successful connection
kubectl logs -n crystalshards -l app=crystalshards --tail=20 | grep -i "database\|postgres\|connected"

# Test database connectivity
kubectl exec -n crystalshards deploy/crystalshards-api -- sh -c 'echo "SELECT version();" | psql $DATABASE_URL'
```

### Issue: CNPG Cluster Not Ready

#### Symptom
```bash
kubectl get cluster -n crystalshards
NAME                   AGE   INSTANCES   READY   STATUS
crystalshards-postgres 10m   2           0       Creating
```

#### Diagnosis Steps

1. **Check CNPG operator logs:**
   ```bash
   kubectl logs -n infrastructure -l app.kubernetes.io/name=cloudnative-pg --tail=100
   ```

2. **Check cluster events:**
   ```bash
   kubectl describe cluster crystalshards-postgres -n crystalshards
   ```

3. **Check PostgreSQL pod logs:**
   ```bash
   kubectl logs -n crystalshards crystalshards-postgres-1 --tail=100
   ```

#### Common Issues

**Issue: PVC Not Bound**
```bash
kubectl get pvc -n crystalshards
```
If PVC is `Pending`, check StorageClass and node resources.

**Issue: Resource Limits Too Low**
Check cluster spec and increase resources if needed.

**Issue: Backup Configuration Invalid**
Verify GCS bucket exists and service account has permissions.

## Redis Troubleshooting

### Issue: Applications Cannot Connect to Redis

#### Symptom
Application logs show:
```
Error connecting to Redis: connection refused
```

#### Diagnosis Steps

1. **Check Redis operator:**
   ```bash
   kubectl get pods -n infrastructure | grep redis-operator
   kubectl logs -n infrastructure -l name=redis-operator --tail=100
   ```

2. **Check Redis instance:**
   ```bash
   kubectl get redis -n infrastructure
   kubectl describe redis shared-redis -n infrastructure
   ```

3. **Check Redis pod:**
   ```bash
   kubectl get pods -n infrastructure | grep shared-redis
   kubectl logs -n infrastructure shared-redis-0 --tail=50
   ```

4. **Check Redis service:**
   ```bash
   kubectl get svc -n infrastructure | grep shared-redis
   kubectl describe svc shared-redis -n infrastructure
   ```

5. **Verify DNS resolution:**
   ```bash
   kubectl exec -n crystalshards deploy/crystalshards-api -- nslookup shared-redis.infrastructure.svc.cluster.local
   ```

6. **Test Redis connectivity:**
   ```bash
   kubectl exec -n crystalshards deploy/crystalshards-api -- redis-cli -h shared-redis.infrastructure.svc.cluster.local ping
   ```

#### Resolution

**If Service Doesn't Exist:**

The Redis operator should create a service named `shared-redis` (matching the resource name).

Check Redis CRD specification:
```bash
kubectl get redis shared-redis -n infrastructure -o yaml
```

Verify `kubernetesConfig.service.type: ClusterIP` is set.

**If Service Name Mismatch:**

Update REDIS_URL in Terraform:

Edit `/workspaces/monorepo/apps/crystalshards/terraform/resource.kubernetes_secret.crystalshards_secrets.tf`:

```hcl
# Update redis_url to match actual service name
redis_url = "redis://<actual-service-name>.infrastructure.svc.cluster.local:6379/0"
```

Apply:
```bash
cd apps/crystalshards/terraform
terraform apply
kubectl rollout restart deployment -n crystalshards
```

**If Network Policy Blocks Access:**

Check network policies:
```bash
kubectl get networkpolicy -n crystalshards
kubectl get networkpolicy -n infrastructure
```

Verify egress rule allows Redis port (6379) to infrastructure namespace.

Edit `/workspaces/monorepo/apps/crystalshards/terraform/resource.kubernetes_network_policy.allow_infrastructure_access.tf` if needed.

#### Verification

```bash
# Check Redis is responding
kubectl exec -n crystalshards deploy/crystalshards-api -- redis-cli -h shared-redis.infrastructure.svc.cluster.local ping
# Expected: PONG

# Check worker can connect
kubectl logs -n crystalshards -l component=worker --tail=20 | grep -i redis

# Test Redis operations
kubectl exec -n crystalshards deploy/crystalshards-api -- redis-cli -h shared-redis.infrastructure.svc.cluster.local SET test "hello"
kubectl exec -n crystalshards deploy/crystalshards-api -- redis-cli -h shared-redis.infrastructure.svc.cluster.local GET test
# Expected: "hello"
```

## Network Policy Troubleshooting

### Issue: Cross-Namespace Communication Blocked

#### Diagnosis Steps

1. **List network policies:**
   ```bash
   kubectl get networkpolicy -A
   ```

2. **Check egress from app namespace:**
   ```bash
   kubectl describe networkpolicy allow-infrastructure-access -n crystalshards
   ```

3. **Check ingress to infrastructure namespace:**
   ```bash
   kubectl get networkpolicy -n infrastructure
   ```

4. **Test connectivity:**
   ```bash
   # Test Redis from app pod
   kubectl exec -n crystalshards deploy/crystalshards-api -- nc -zv shared-redis.infrastructure.svc.cluster.local 6379

   # Test PostgreSQL within namespace
   kubectl exec -n crystalshards deploy/crystalshards-api -- nc -zv crystalshards-postgres-rw 5432
   ```

#### Resolution

Ensure egress policy allows:
- Port 6379 to infrastructure namespace (Redis)
- Port 9000 to infrastructure namespace (MinIO)
- Port 5432 to PostgreSQL pods in same namespace
- Port 53 UDP for DNS
- Port 443 TCP for HTTPS

Example network policy in `/workspaces/monorepo/apps/crystalshards/terraform/resource.kubernetes_network_policy.allow_infrastructure_access.tf`

## DNS Resolution Troubleshooting

### Issue: Service DNS Not Resolving

#### Diagnosis Steps

```bash
# Check kube-dns/CoreDNS
kubectl get pods -n kube-system | grep dns

# Test DNS from pod
kubectl exec -n crystalshards deploy/crystalshards-api -- nslookup shared-redis.infrastructure.svc.cluster.local
kubectl exec -n crystalshards deploy/crystalshards-api -- nslookup crystalshards-postgres-rw
```

#### Resolution

If DNS not resolving:
1. Check CoreDNS pods are running
2. Check service exists: `kubectl get svc -A | grep <service>`
3. Wait 30-60 seconds for DNS propagation
4. Restart CoreDNS if needed: `kubectl rollout restart deployment/coredns -n kube-system`

## Secret Management

### Verify All Secrets Exist

```bash
# Check application secrets
for ns in crystalshards crystaldocs crystalgigs crystalbits; do
  echo "=== $ns ==="
  kubectl get secrets -n $ns | grep -E "secrets|postgres-app"
done

# Check infrastructure secrets
kubectl get secrets -n infrastructure | grep -E "shared-storage|redis"
```

### Verify Secret Contents

```bash
# Check DATABASE_URL format
kubectl get secret crystalshards-secrets -n crystalshards -o jsonpath='{.data.database_url}' | base64 -d
# Should show: postgresql://USERNAME:PASSWORD@SERVICE:5432/DATABASE

# Check REDIS_URL format
kubectl get secret crystalshards-secrets -n crystalshards -o jsonpath='{.data.redis_url}' | base64 -d
# Should show: redis://SERVICE.infrastructure.svc.cluster.local:6379/0
```

## Terraform State Management

### Apply Infrastructure Changes

```bash
# Apply all application Terraform
cd /workspaces/monorepo
for app in crystalshards crystaldocs crystalgigs crystalbits; do
  echo "=== Applying $app ==="
  cd apps/$app/terraform
  terraform init
  terraform plan
  terraform apply -auto-approve
  cd /workspaces/monorepo
done
```

### Verify Terraform Applied Secrets

```bash
# Check terraform state
cd apps/crystalshards/terraform
terraform show | grep -A 10 "kubernetes_secret.crystalshards_secrets"
```

## End-to-End Verification

### Full Application Stack Test

```bash
#!/bin/bash
# verify-app-connectivity.sh

NAMESPACE=$1  # e.g., crystalshards

echo "=== Testing $NAMESPACE connectivity ==="

# 1. Check pods are running
echo "1. Checking pod status..."
kubectl get pods -n $NAMESPACE

# 2. Test database connectivity
echo "2. Testing PostgreSQL connectivity..."
kubectl exec -n $NAMESPACE deploy/${NAMESPACE}-api -- sh -c 'echo "SELECT 1 as test;" | psql $DATABASE_URL'

# 3. Test Redis connectivity (crystalshards only)
if [ "$NAMESPACE" = "crystalshards" ]; then
  echo "3. Testing Redis connectivity..."
  kubectl exec -n $NAMESPACE deploy/${NAMESPACE}-api -- redis-cli -u $REDIS_URL ping
fi

# 4. Check application health endpoint
echo "4. Checking health endpoint..."
kubectl exec -n $NAMESPACE deploy/${NAMESPACE}-api -- curl -s http://localhost:3000/api/health

# 5. Check recent logs
echo "5. Checking recent logs..."
kubectl logs -n $NAMESPACE -l component=api --tail=10

echo "=== $NAMESPACE verification complete ==="
```

Usage:
```bash
chmod +x verify-app-connectivity.sh
./verify-app-connectivity.sh crystalshards
./verify-app-connectivity.sh crystaldocs
./verify-app-connectivity.sh crystalgigs
./verify-app-connectivity.sh crystalbits
```

## Rollback Procedures

### Rollback Terraform Changes

```bash
cd apps/<app>/terraform
terraform plan  # Review changes
terraform apply -target=kubernetes_secret.<app>_secrets  # Apply only secret
```

### Rollback Application Deployment

```bash
# View revision history
kubectl rollout history deployment/<app>-api -n <app>

# Rollback to previous version
kubectl rollout undo deployment/<app>-api -n <app>
kubectl rollout undo deployment/<app>-worker -n <app>

# Rollback to specific revision
kubectl rollout undo deployment/<app>-api -n <app> --to-revision=<N>
```

## Monitoring and Alerts

### Check Prometheus Alerts

```bash
# View active alerts
kubectl port-forward -n infrastructure svc/prometheus-operator-kube-prom-prometheus 9090:9090

# Navigate to: http://localhost:9090/alerts
```

### Check Application Metrics

```bash
# View metrics
kubectl port-forward -n infrastructure svc/grafana 3000:80

# Navigate to: http://localhost:3000
# Default credentials: admin / (check secret)
```

## Common Error Messages

| Error Message | Cause | Resolution |
|--------------|-------|------------|
| `password authentication failed for user "app"` | Hardcoded username in DATABASE_URL | Read username from CNPG secret |
| `connection refused` | Service not reachable | Check service exists and network policies |
| `could not connect to server` | DNS or networking issue | Verify service DNS and network connectivity |
| `no pg_hba.conf entry for host` | PostgreSQL not configured for connection | Check CNPG cluster configuration |
| `Error: NOAUTH Authentication required` | Redis requires password (not expected) | Redis should not have password in current setup |
| `CrashLoopBackOff` | Application failing to start | Check logs for specific error |

## Escalation

If issues persist after following this runbook:

1. **Collect diagnostics:**
   ```bash
   kubectl cluster-info dump --namespaces crystalshards,crystaldocs,crystalgigs,crystalbits,infrastructure > cluster-dump.txt
   ```

2. **Check operator logs:**
   ```bash
   kubectl logs -n infrastructure -l app.kubernetes.io/name=cloudnative-pg --tail=500 > cnpg-logs.txt
   kubectl logs -n infrastructure -l name=redis-operator --tail=500 > redis-operator-logs.txt
   ```

3. **Create GitHub issue** with:
   - Symptoms observed
   - Steps taken from this runbook
   - Diagnostic outputs
   - Application logs

4. **Tag:** @platform-team @sre-team

## Related Documentation

- Post-Event Review: `/workspaces/monorepo/pers/2025-10-10-database-redis-connectivity-outage.md`
- CNPG Documentation: https://cloudnative-pg.io/
- Redis Operator Documentation: https://ot-container-kit.github.io/redis-operator/
- GitHub Issue #52: PostgreSQL connectivity
- GitHub Issue #53: Redis connectivity

## Changelog

| Date | Change | Author |
|------|--------|--------|
| 2025-10-10 | Initial version | Agent SRE |
