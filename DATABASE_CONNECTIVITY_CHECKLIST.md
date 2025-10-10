# Database Connectivity Troubleshooting Checklist

**Issue:** #52 - PostgreSQL connectivity failures across all applications
**Prerequisites:** RBAC permissions applied (see FIX_RBAC_BLOCKER.md)

## Quick Diagnostic Commands

Run these commands in order to identify the issue:

### 1. Check Operator Status

```bash
# Check if CloudNativePG operator is deployed
kubectl get deployment -n infrastructure -l app.kubernetes.io/name=cloudnative-pg

# Check operator pods
kubectl get pods -n infrastructure -l app.kubernetes.io/name=cloudnative-pg

# Check operator logs
kubectl logs -n infrastructure -l app.kubernetes.io/name=cloudnative-pg --tail=100
```

**Expected:** Operator deployment exists with 1/1 ready pods.

### 2. Check CRD Installation

```bash
# Verify CloudNativePG CRD exists
kubectl get crd clusters.postgresql.cnpg.io
```

**Expected:** CRD exists with proper API version.

### 3. Check Database Clusters

```bash
# List all PostgreSQL clusters
kubectl get clusters --all-namespaces

# Check specific clusters
kubectl get cluster crystalshards-postgres -n crystalshards -o yaml
kubectl get cluster crystaldocs-postgres -n crystaldocs -o yaml
kubectl get cluster crystalgigs-postgres -n crystalgigs -o yaml
kubectl get cluster crystalbits-postgres -n crystalbits -o yaml
```

**Expected:** All 4 clusters exist and show status "Cluster in healthy state"

### 4. Check Database Pods

```bash
# Check PostgreSQL pods for each app
kubectl get pods -n crystalshards -l cnpg.io/cluster=crystalshards-postgres
kubectl get pods -n crystaldocs -l cnpg.io/cluster=crystaldocs-postgres
kubectl get pods -n crystalgigs -l cnpg.io/cluster=crystalgigs-postgres
kubectl get pods -n crystalbits -l cnpg.io/cluster=crystalbits-postgres
```

**Expected:** 3 pods per cluster (primary + 2 replicas), all Running

### 5. Check Database Services

```bash
# Verify read-write services exist
kubectl get service crystalshards-postgres-rw -n crystalshards
kubectl get service crystaldocs-postgres-rw -n crystaldocs
kubectl get service crystalgigs-postgres-rw -n crystalgigs
kubectl get service crystalbits-postgres-rw -n crystalbits
```

**Expected:** All services exist with ClusterIP type

### 6. Check Database Secrets

```bash
# Verify PostgreSQL generates app user secrets
kubectl get secret crystalshards-postgres-app -n crystalshards
kubectl get secret crystaldocs-postgres-app -n crystaldocs
kubectl get secret crystalgigs-postgres-app -n crystalgigs
kubectl get secret crystalbits-postgres-app -n crystalbits
```

**Expected:** Secrets exist (created by CNPG operator)

### 7. Check Application Secrets

```bash
# Verify application secrets contain DATABASE_URL
kubectl get secret crystalshards-secrets -n crystalshards -o jsonpath='{.data.DATABASE_URL}' | base64 -d
kubectl get secret crystaldocs-secrets -n crystaldocs -o jsonpath='{.data.DATABASE_URL}' | base64 -d
kubectl get secret crystalgigs-secrets -n crystalgigs -o jsonpath='{.data.DATABASE_URL}' | base64 -d
kubectl get secret crystalbits-secrets -n crystalbits -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

**Expected:** Valid PostgreSQL connection strings pointing to `-rw` services

### 8. Check Application Pods

```bash
# Check application pod status
kubectl get pods -n crystalshards -l app=crystalshards-api
kubectl get pods -n crystalshards -l app=crystalshards-worker
kubectl get pods -n crystaldocs -l app=crystaldocs-api
kubectl get pods -n crystalgigs -l app=crystalgigs-api
kubectl get pods -n crystalbits -l app=crystalbits-api
```

**Expected:** Pods in Running state (not CrashLoopBackOff)

### 9. Check Application Logs

```bash
# Check for database connection errors
kubectl logs -n crystalshards -l app=crystalshards-api --tail=50 | grep -i "database\|postgres\|connection"
kubectl logs -n crystaldocs -l app=crystaldocs-api --tail=50 | grep -i "database\|postgres\|connection"
kubectl logs -n crystalgigs -l app=crystalgigs-api --tail=50 | grep -i "database\|postgres\|connection"
kubectl logs -n crystalbits -l app=crystalbits-api --tail=50 | grep -i "database\|postgres\|connection"
```

**Expected:** No connection errors or timeouts

### 10. Test DNS Resolution

```bash
# Test that database services are resolvable
kubectl run dns-test --image=busybox:1.36 -n crystalshards --rm -it --restart=Never -- \
  nslookup crystalshards-postgres-rw.crystalshards.svc.cluster.local
```

**Expected:** DNS resolves to service ClusterIP

### 11. Test Database Connectivity

```bash
# Test connection from application pod
POD=$(kubectl get pod -n crystalshards -l app=crystalshards-api -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n crystalshards $POD -- sh -c 'echo $DATABASE_URL'

# If psql is available in the pod:
# kubectl exec -n crystalshards $POD -- psql $DATABASE_URL -c "SELECT version();"
```

**Expected:** DATABASE_URL environment variable is set correctly

## Common Issues and Fixes

### Issue: Operator Not Found

**Symptom:** No deployment in infrastructure namespace
**Fix:** Deploy CloudNativePG operator (see MANUAL_INFRASTRUCTURE_DEPLOYMENT.md Step 3)

### Issue: CRD Not Found

**Symptom:** `error: the server doesn't have a resource type "clusters"`
**Fix:** Operator installation failed or CRD not registered. Reinstall operator.

### Issue: Clusters Not Found

**Symptom:** `No resources found`
**Fix:** Deploy PostgreSQL clusters (see MANUAL_INFRASTRUCTURE_DEPLOYMENT.md Step 7)

### Issue: Cluster Not Ready

**Symptom:** Cluster status shows errors or "Not Ready"
**Fix:** Check cluster events and pod logs
```bash
kubectl describe cluster crystalshards-postgres -n crystalshards
kubectl get events -n crystalshards --sort-by='.lastTimestamp' | tail -20
```

### Issue: Pods Pending

**Symptom:** Database pods stuck in Pending state
**Causes:**
- PVC not binding (check storage class)
- Resource constraints (check GKE Autopilot limits)
- Node scheduling issues

**Fix:**
```bash
kubectl describe pod -n crystalshards -l cnpg.io/cluster=crystalshards-postgres
kubectl get pvc -n crystalshards
kubectl get events -n crystalshards
```

### Issue: Pods CrashLooping

**Symptom:** Database pods in CrashLoopBackOff
**Causes:**
- Resource limits too low
- PVC permissions issue
- Image pull failure

**Fix:**
```bash
kubectl logs -n crystalshards -l cnpg.io/cluster=crystalshards-postgres --previous
kubectl describe pod -n crystalshards -l cnpg.io/cluster=crystalshards-postgres
```

### Issue: Service Not Found

**Symptom:** Service `-rw` doesn't exist
**Cause:** Cluster not fully initialized or operator issue

**Fix:** Wait for cluster to be ready (can take 5-10 minutes)
```bash
kubectl wait --for=condition=Ready cluster/crystalshards-postgres -n crystalshards --timeout=10m
```

### Issue: Secret Not Found

**Symptom:** `crystalshards-postgres-app` secret doesn't exist
**Cause:** CNPG operator hasn't created user credentials yet

**Fix:** Wait for cluster initialization, then check operator logs

### Issue: Wrong DATABASE_URL Format

**Symptom:** Application logs show "connection refused" or "no such host"
**Cause:** DATABASE_URL doesn't point to correct service

**Expected format:**
```
postgresql://app:PASSWORD@SERVICE-NAME.NAMESPACE.svc.cluster.local:5432/app
```

**Fix:** Terraform should populate this correctly from CNPG-generated secret. Check:
```bash
# Compare these two:
kubectl get secret crystalshards-postgres-app -n crystalshards -o jsonpath='{.data.uri}' | base64 -d
kubectl get secret crystalshards-secrets -n crystalshards -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

### Issue: Application Pods CrashLooping

**Symptom:** API/worker pods in CrashLoopBackOff
**Cause:** Database not ready or connection timeout

**Fix:**
1. Ensure database cluster is ready first
2. Restart application pods:
```bash
kubectl rollout restart deployment/crystalshards-api -n crystalshards
kubectl rollout restart deployment/crystalshards-worker -n crystalshards
```

### Issue: DNS Resolution Failing

**Symptom:** `nslookup` fails or returns NXDOMAIN
**Causes:**
- Service doesn't exist
- CoreDNS issues
- Wrong namespace in FQDN

**Fix:**
```bash
# Check service exists
kubectl get service crystalshards-postgres-rw -n crystalshards

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Verify FQDN format: SERVICE.NAMESPACE.svc.cluster.local
```

## Remediation Workflow

Based on findings, follow this workflow:

1. **If operators missing:** Deploy operators (Steps 3-4 in MANUAL_INFRASTRUCTURE_DEPLOYMENT.md)
2. **If clusters missing:** Deploy PostgreSQL clusters (Step 7 in MANUAL_INFRASTRUCTURE_DEPLOYMENT.md)
3. **If clusters unhealthy:** Investigate events and logs, fix resource issues
4. **If secrets incorrect:** Verify Terraform data sources and re-apply
5. **If applications crashing:** Restart deployments after infrastructure is healthy
6. **If connectivity failing:** Test DNS, check network policies, verify secrets

## Success Criteria

All of the following must be true:

- [ ] CloudNativePG operator is running (1/1 ready)
- [ ] All 4 PostgreSQL clusters show "Cluster in healthy state"
- [ ] Each cluster has 3 running pods (primary + 2 replicas)
- [ ] All `-rw` services are accessible
- [ ] All database secrets exist
- [ ] All application pods are Running (not CrashLoopBackOff)
- [ ] Application logs show successful database connections
- [ ] DNS resolution works for all database services
- [ ] Health endpoints return 200 OK:
  - https://crystalshards.org/api/health
  - https://crystaldocs.org/api/health
  - https://crystalgigs.com/api/health
  - https://crystalbits.org/api/health

## Reference

- **Full deployment runbook:** MANUAL_INFRASTRUCTURE_DEPLOYMENT.md
- **RBAC fix:** FIX_RBAC_BLOCKER.md
- **Diagnostic report:** infrastructure-diagnosis-2025-10-10.md
- **Terraform configs:** apps/*/terraform/

## Health Endpoint Testing

After fixes are applied, verify all applications are healthy:

```bash
# CrystalShards
curl -v https://crystalshards.org/api/health
# Expected: 200 OK

# CrystalDocs
curl -v https://crystaldocs.org/api/health
# Expected: 200 OK

# CrystalGigs
curl -v https://crystalgigs.com/api/health
# Expected: 200 OK

# CrystalBits
curl -v https://crystalbits.org/api/health
# Expected: 200 OK
```

All should return successful responses indicating database connectivity is working.
