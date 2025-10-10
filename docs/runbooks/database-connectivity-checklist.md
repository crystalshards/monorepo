# Database Connectivity Troubleshooting Checklist

## Severity: P0 - CRITICAL

When applications cannot connect to PostgreSQL databases, follow this systematic checklist to identify the root cause.

## Quick Triage Checklist

Work through this checklist in order. Each step rules out a category of problems.

### 1. Is the Infrastructure Deployed?

**Symptom**: All applications failing with database connection errors

**Check**:
```bash
# Check if CNPG operator is installed
kubectl api-resources | grep -i cnpg

# Expected output if deployed:
# backups          backup    postgresql.cnpg.io/v1
# clusters         cluster   postgresql.cnpg.io/v1
# ...
```

**If empty**: Infrastructure not deployed yet - Terraform needs to be applied.

**Resolution**: See [Deployment Runbook](../../terraform/DEPLOYMENT_RUNBOOK.md)

**Common Cause**: Fresh cluster, Terraform never applied, or operator uninstalled

---

### 2. Is the CNPG Operator Running?

**Symptom**: CNPG resources exist but clusters aren't being created

**Check**:
```bash
# Check CNPG operator pod
kubectl get pods -n infrastructure -l app.kubernetes.io/name=cloudnative-pg

# Expected output:
# NAME                                    READY   STATUS
# cloudnative-pg-controller-manager-xxx   1/1     Running
```

**If not running**:
```bash
# Check operator logs
kubectl logs -n infrastructure -l app.kubernetes.io/name=cloudnative-pg --tail=100

# Check Helm release
kubectl get helmrelease -n infrastructure cnpg
```

**Resolution**: Restart operator or reinstall via Terraform

---

### 3. Do PostgreSQL Clusters Exist?

**Symptom**: Operator running but no database clusters

**Check**:
```bash
# List all PostgreSQL clusters
kubectl get cluster -A

# Expected output (all 4 apps):
# NAMESPACE       NAME                   INSTANCES  READY  STATUS
# crystalshards   crystalshards-postgres    2        2      Cluster in healthy state
# crystaldocs     crystaldocs-postgres      2        2      Cluster in healthy state
# crystalgigs     crystalgigs-postgres      2        2      Cluster in healthy state
# crystalbits     crystalbits-postgres      2        2      Cluster in healthy state
```

**If clusters missing**:
```bash
# Check if cluster resources were created
kubectl get cluster -n crystalshards crystalshards-postgres

# If not found, check Terraform state
cd /workspaces/monorepo/apps/crystalshards/terraform
terraform state list | grep postgres
```

**Resolution**: Apply Terraform for specific app namespace

---

### 4. Are PostgreSQL Pods Running?

**Symptom**: Clusters exist but pods aren't ready

**Check**:
```bash
# Check PostgreSQL pods for each app
kubectl get pods -n crystalshards -l cnpg.io/cluster=crystalshards-postgres
kubectl get pods -n crystaldocs -l cnpg.io/cluster=crystaldocs-postgres
kubectl get pods -n crystalgigs -l cnpg.io/cluster=crystalgigs-postgres
kubectl get pods -n crystalbits -l cnpg.io/cluster=crystalbits-postgres

# Expected: 2 pods per app in Running state
# NAME                           READY   STATUS
# crystalshards-postgres-1       1/1     Running
# crystalshards-postgres-2       1/1     Running
```

**If pods not ready**:
```bash
# Check pod details
kubectl describe pod -n crystalshards <postgres-pod-name>

# Common issues:
# - ImagePullBackOff: Wrong CNPG operator version
# - Pending: Insufficient cluster resources
# - CrashLoopBackOff: Check logs for database corruption
```

**Resolution**: See [Pod Not Ready Runbook](pod-not-ready.md)

---

### 5. Do Database Credentials Exist?

**Symptom**: Pods running but apps can't authenticate

**Check**:
```bash
# CNPG creates a secret named <cluster-name>-app with credentials
kubectl get secret -n crystalshards crystalshards-postgres-app
kubectl get secret -n crystaldocs crystaldocs-postgres-app
kubectl get secret -n crystalgigs crystalgigs-postgres-app
kubectl get secret -n crystalbits crystalbits-postgres-app

# Check secret contents (base64 encoded)
kubectl get secret -n crystalshards crystalshards-postgres-app -o yaml
```

**Expected keys in secret**:
- `username` (usually "app")
- `password` (auto-generated)
- `dbname` (database name)

**If secret missing**: CNPG cluster not fully initialized, wait or check operator logs

---

### 6. Are Application Secrets Configured?

**Symptom**: Database credentials exist but apps don't have DATABASE_URL

**Check**:
```bash
# Check application secrets
kubectl get secret -n crystalshards crystalshards-secrets
kubectl get secret -n crystaldocs crystaldocs-secrets
kubectl get secret -n crystalgigs crystalgigs-secrets
kubectl get secret -n crystalbits crystalbits-secrets

# Verify DATABASE_URL is present
kubectl get secret -n crystalshards crystalshards-secrets -o jsonpath='{.data.database_url}' | base64 -d

# Expected format:
# postgresql://app:<password>@<cluster-name>-rw:5432/<dbname>
```

**If missing or malformed**:
```bash
# Check Terraform data source
cd /workspaces/monorepo/apps/crystalshards/terraform
terraform state list | grep kubernetes_secret

# Reapply Terraform to recreate secrets
terraform apply -target=kubernetes_secret.crystalshards_secrets
```

---

### 7. Are PostgreSQL Services Accessible?

**Symptom**: Credentials correct but network unreachable

**Check**:
```bash
# CNPG creates read-write and read-only services
kubectl get svc -n crystalshards | grep postgres
kubectl get svc -n crystaldocs | grep postgres
kubectl get svc -n crystalgigs | grep postgres
kubectl get svc -n crystalbits | grep postgres

# Expected services:
# <cluster-name>-rw    ClusterIP   <ip>   5432/TCP  # read-write
# <cluster-name>-ro    ClusterIP   <ip>   5432/TCP  # read-only
# <cluster-name>-r     ClusterIP   <ip>   5432/TCP  # replicas
```

**If services missing**: CNPG cluster not healthy, check cluster status

---

### 8. Do Network Policies Allow Connections?

**Symptom**: Services exist but connections are blocked

**Check**:
```bash
# Check network policies
kubectl get networkpolicy -n crystalshards
kubectl get networkpolicy -n infrastructure

# Verify policy allows app pods to reach infrastructure namespace
kubectl describe networkpolicy -n crystalshards allow-infrastructure-access
```

**Expected network policy** (for apps with infrastructure dependencies):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-infrastructure-access
spec:
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: infrastructure
  podSelector:
    matchLabels:
      app: crystalshards-api
```

**If network policy too restrictive**: Update Terraform network policy configuration

---

### 9. Can App Pods Reach Database?

**Symptom**: Network allows traffic but DNS or routing issue

**Check**:
```bash
# Test DNS resolution from app pod
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  nslookup crystalshards-postgres-rw.crystalshards.svc.cluster.local

# Test TCP connection to database
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  nc -zv crystalshards-postgres-rw 5432

# Expected output:
# crystalshards-postgres-rw (10.x.x.x:5432) open
```

**If DNS fails**: Check CoreDNS pods in kube-system namespace

**If connection refused**: Check PostgreSQL is listening on port 5432

---

### 10. Can App Authenticate to Database?

**Symptom**: Network reachable but authentication fails

**Check**:
```bash
# Test database connection with credentials from app secret
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT 1;"

# Expected output:
# ?column?
# ----------
#        1
# (1 row)
```

**If authentication fails**:
```bash
# Verify password matches between secrets
APP_PASS=$(kubectl get secret -n crystalshards crystalshards-secrets -o jsonpath='{.data.database_url}' | base64 -d | grep -oP '//app:\K[^@]+')
CNPG_PASS=$(kubectl get secret -n crystalshards crystalshards-postgres-app -o jsonpath='{.data.password}' | base64 -d)

echo "App password: $APP_PASS"
echo "CNPG password: $CNPG_PASS"

# If they don't match, Terraform needs to reapply
```

---

### 11. Are Database Migrations Applied?

**Symptom**: Connection works but tables don't exist

**Check**:
```bash
# List tables in database
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "\dt"

# Expected: List of application tables
# If no tables exist, migrations haven't run
```

**Resolution**: Run database migrations via CI/CD or manually

---

### 12. Are There Database Connection Limits?

**Symptom**: Some connections work, others timeout

**Check**:
```bash
# Check current connections
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT count(*) FROM pg_stat_activity;"

# Check max connections setting
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SHOW max_connections;"

# Check connection pool usage in app logs
kubectl logs -n crystalshards -l app=crystalshards-api --tail=100 | grep -i "connection"
```

**If connection limit reached**: Scale up PostgreSQL or reduce app connection pools

---

## Summary Matrix

| Symptom | Root Cause | Resolution |
|---------|------------|------------|
| CNPG API resources missing | Infrastructure not deployed | Apply Terraform |
| Operator pod not running | Operator crashed or not installed | Check logs, redeploy via Terraform |
| Cluster resource missing | Terraform not applied for app | Apply app-specific Terraform |
| PostgreSQL pods pending | Insufficient cluster resources | Scale cluster or reduce resource requests |
| Credentials secret missing | CNPG cluster not initialized | Wait 2-5 minutes or check operator logs |
| DATABASE_URL missing | App secrets not created | Apply Terraform for app secrets |
| Service not found | CNPG cluster unhealthy | Check cluster status and operator logs |
| Network policy blocks traffic | Restrictive network policy | Update network policy in Terraform |
| DNS resolution fails | CoreDNS issue | Check kube-system namespace |
| Authentication fails | Password mismatch | Reapply Terraform to sync secrets |
| Tables don't exist | Migrations not run | Run database migrations |
| Connection limit reached | Too many connections | Scale PostgreSQL or tune connection pools |

## Quick Recovery Commands

### Fastest Path: Restart Everything
```bash
# Restart app deployments (forces reconnection)
kubectl rollout restart deployment/crystalshards-api -n crystalshards
kubectl rollout restart deployment/crystaldocs-api -n crystaldocs
kubectl rollout restart deployment/crystalgigs-api -n crystalgigs
kubectl rollout restart deployment/crystalbits-api -n crystalbits

# Wait for rollout
kubectl rollout status deployment/crystalshards-api -n crystalshards
```

### Recreate App Secrets
```bash
# Reapply Terraform for specific app to recreate DATABASE_URL
cd /workspaces/monorepo/apps/crystalshards/terraform
terraform apply -target=kubernetes_secret.crystalshards_secrets
```

### Recreate PostgreSQL Cluster
```bash
# Last resort - deletes data! Only if cluster corrupted
kubectl delete cluster -n crystalshards crystalshards-postgres

# Reapply Terraform to recreate
cd /workspaces/monorepo/apps/crystalshards/terraform
terraform apply -target=kubectl_manifest.crystalshards_postgres
```

## Post-Resolution Verification

After fixing connectivity issues, verify all apps can connect:

```bash
# Test all 4 apps
for app in crystalshards crystaldocs crystalgigs crystalbits; do
  echo "Testing $app..."
  kubectl exec -n $app deployment/${app}-api -- \
    psql "$DATABASE_URL" -c "SELECT 1;" && echo "✅ $app OK" || echo "❌ $app FAILED"
done

# Check application logs for successful startup
kubectl logs -n crystalshards -l app=crystalshards-api --tail=20 | grep -i "database\|connected\|ready"
```

## Related Runbooks
- [PostgreSQL Unavailable](postgres-unavailable.md)
- [PostgreSQL High Connections](postgres-high-connections.md)
- [Application Unavailable](app-unavailable.md)
- [Pod Not Ready](pod-not-ready.md)
- [Deployment Runbook](../../terraform/DEPLOYMENT_RUNBOOK.md)

## Revision History
- 2025-10-10: Created comprehensive database connectivity checklist
