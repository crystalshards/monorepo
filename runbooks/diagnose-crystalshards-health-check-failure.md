# Runbook: Diagnose and Fix CrystalShards Health Check Failures

**Purpose**: Diagnose why CrystalShards.org pods are failing health checks and restore service
**Severity**: CRITICAL - Production outage
**Prerequisites**: Cluster admin access to GKE cluster
**Estimated Time**: 30-60 minutes

## Quick Reference

**Symptoms**:
- `curl https://crystalshards.org` returns JSON instead of HTML
- `/api/health` endpoint returns "upstream request timeout"
- Pods failing readiness/liveness probes
- Deployment timeouts after 20 minutes

**Most Likely Causes**:
1. CNPG PostgreSQL cluster not ready
2. Network policy blocking database access within same namespace
3. Database or Redis connectivity issues

## Prerequisites Check

Before starting, verify you have necessary access:

```bash
# Verify kubectl context
kubectl config current-context
# Should show: gke_PROJECT_ID_us-central1_crystalshards-cluster

# Verify cluster access
kubectl auth can-i get pods --all-namespaces
# Should return: yes

# Set up shell for easy namespace switching
export NS_CRYSTALSHARDS=crystalshards
export NS_INFRASTRUCTURE=infrastructure
export NS_CNPG=cnpg-system
```

## Step 1: Apply RBAC Permissions (REQUIRED FIRST STEP)

The SRE agent needs cluster access to investigate further issues.

```bash
# Apply RBAC configuration for agent
kubectl apply -f /workspaces/monorepo/kubernetes-agent-rbac.yaml

# Expected output:
# serviceaccount/claude-agent created or configured
# clusterrole.rbac.authorization.k8s.io/claude-agent-role created or configured
# clusterrolebinding.rbac.authorization.k8s.io/claude-agent-binding created or configured

# Verify RBAC was applied
kubectl get clusterrole claude-agent-role
kubectl get clusterrolebinding claude-agent-binding

# If agent pod exists, restart it to pick up new permissions
kubectl rollout restart deployment -n claude claude-agent 2>/dev/null || echo "No agent deployment to restart"
```

**Success Criteria**: RBAC resources created without errors

## Step 2: Check CrystalShards Namespace Status

```bash
# Check namespace exists
kubectl get namespace $NS_CRYSTALSHARDS

# List all resources in namespace
kubectl get all -n $NS_CRYSTALSHARDS

# Expected resources:
# - deployment/crystalshards-api (should have 2 replicas)
# - service/crystalshards-api
# - pods (2x crystalshards-api-XXX)
# - CNPG cluster resources (if present)
```

**Success Criteria**: Namespace exists, deployment present (even if pods failing)

## Step 3: Check Pod Status and Logs

```bash
# Get pod status
kubectl get pods -n $NS_CRYSTALSHARDS -l app=crystalshards,component=api

# Expected states:
# - Running (healthy)
# - Running but not Ready (failing health checks) <- LIKELY
# - CrashLoopBackOff (crashing on startup)
# - Pending (not scheduled)

# Describe first pod to see events
POD=$(kubectl get pods -n $NS_CRYSTALSHARDS -l app=crystalshards,component=api -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $POD -n $NS_CRYSTALSHARDS

# Look for:
# - "Readiness probe failed" (health check failures)
# - "Liveness probe failed" (pod being restarted)
# - Event messages about connectivity

# Get pod logs
kubectl logs $POD -n $NS_CRYSTALSHARDS --tail=100

# Look for:
# - Database connection errors
# - Redis connection errors
# - Timeout errors
# - Stack traces
```

**Success Criteria**: Pods are running (even if not ready), logs visible

**Common Issues**:
- If pods are Pending: Check node resources or scheduling issues
- If CrashLoopBackOff: Check application startup errors in logs
- If no pods: Deployment may have failed to create ReplicaSet

## Step 4: Verify CNPG PostgreSQL Cluster

This is the most likely root cause.

```bash
# Check if CNPG operator is installed and running
kubectl get pods -n $NS_CNPG

# Expected: cnpg-controller-manager pods in Running state

# Check CNPG cluster status
kubectl get clusters.postgresql.cnpg.io -n $NS_CRYSTALSHARDS

# Expected output:
# NAME                     AGE   INSTANCES   READY   STATUS
# crystalshards-postgres   XXd   2           2       Cluster in healthy state

# If cluster exists, get detailed status
kubectl get clusters.postgresql.cnpg.io crystalshards-postgres -n $NS_CRYSTALSHARDS -o yaml | grep -A 10 "status:"

# Check CNPG pods
kubectl get pods -n $NS_CRYSTALSHARDS -l cnpg.io/cluster=crystalshards-postgres

# Expected: 2 postgres pods in Running state
# - crystalshards-postgres-1 (primary or replica)
# - crystalshards-postgres-2 (primary or replica)

# Check postgres pod logs if they exist
kubectl logs -n $NS_CRYSTALSHARDS crystalshards-postgres-1 --tail=50

# Check if CNPG created the app secret
kubectl get secret crystalshards-postgres-app -n $NS_CRYSTALSHARDS

# If secret exists, verify it has correct keys
kubectl get secret crystalshards-postgres-app -n $NS_CRYSTALSHARDS -o jsonpath='{.data}' | jq 'keys'

# Expected keys: ["password", "username"] (base64 encoded)
```

**Success Criteria**:
- CNPG operator running
- Cluster in "healthy" state
- 2 postgres pods running
- App secret exists

**Common Issues**:

### Issue: CNPG cluster doesn't exist
**Symptom**: `Error from server (NotFound): clusters.postgresql.cnpg.io "crystalshards-postgres" not found`

**Cause**: Terraform didn't create cluster or creation failed

**Fix**: Re-run Terraform to create cluster
```bash
cd /workspaces/monorepo/terraform
terraform init
terraform apply -target=module.crystalshards -var="project_id=PROJECT_ID" -var="region=us-central1"
```

### Issue: CNPG cluster stuck in "Creating" or "Initializing"
**Symptom**: Cluster status is not "healthy", READY shows 0/2

**Cause**: Storage provisioning issues, initialization timeout, or operator issues

**Fix**: Check CNPG controller logs
```bash
kubectl logs -n $NS_CNPG -l app.kubernetes.io/name=cloudnative-pg --tail=200

# Look for errors related to crystalshards-postgres
# Common issues:
# - Storage class not available
# - Insufficient resources
# - Backup configuration errors
```

**Fix**: Check events for cluster
```bash
kubectl describe cluster crystalshards-postgres -n $NS_CRYSTALSHARDS | grep -A 20 Events
```

### Issue: App secret not generated
**Symptom**: `Error from server (NotFound): secrets "crystalshards-postgres-app" not found`

**Cause**: CNPG cluster not fully initialized yet

**Fix**: Wait for cluster to reach healthy state, or check CNPG operator logs

## Step 5: Verify Database Connectivity from App Pod

```bash
# Get a shell in the app pod
POD=$(kubectl get pods -n $NS_CRYSTALSHARDS -l app=crystalshards,component=api -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -n $NS_CRYSTALSHARDS -- sh

# Inside the pod, test DNS resolution
nslookup crystalshards-postgres-rw
nslookup crystalshards-postgres-rw.crystalshards.svc.cluster.local

# Expected: Should resolve to ClusterIP

# Test TCP connectivity to PostgreSQL
nc -zv crystalshards-postgres-rw 5432

# Expected: "crystalshards-postgres-rw (10.X.X.X:5432) open"

# If nc not available, try telnet or curl
telnet crystalshards-postgres-rw 5432

# Exit pod shell
exit
```

**Success Criteria**: DNS resolves, TCP connection succeeds

**Common Issues**:

### Issue: DNS resolution fails
**Symptom**: `nslookup: can't resolve 'crystalshards-postgres-rw'`

**Cause**:
- Service doesn't exist
- DNS not working in cluster
- Network policy blocking DNS

**Fix**: Check if service exists
```bash
kubectl get service crystalshards-postgres-rw -n $NS_CRYSTALSHARDS

# CNPG creates this service automatically
# If missing, CNPG cluster is not ready
```

### Issue: TCP connection refused or timeout
**Symptom**: `nc: crystalshards-postgres-rw (10.X.X.X:5432): Connection refused/timed out`

**Cause**:
- PostgreSQL not listening
- Network policy blocking traffic
- Postgres pods not ready

**Fix**: See network policy diagnosis in Step 6

## Step 6: Check Network Policies

```bash
# List network policies in crystalshards namespace
kubectl get networkpolicies -n $NS_CRYSTALSHARDS

# Expected: allow-infrastructure-access

# Describe the network policy
kubectl describe networkpolicy allow-infrastructure-access -n $NS_CRYSTALSHARDS

# Check policy rules
kubectl get networkpolicy allow-infrastructure-access -n $NS_CRYSTALSHARDS -o yaml
```

**Critical Issue to Check**: The current network policy allows egress to infrastructure namespace but may NOT allow same-namespace database access.

**Current policy** (egress only):
- Allows egress to infrastructure namespace (for Redis)
- Allows DNS (UDP 53)
- Allows HTTPS (TCP 443)
- **MISSING**: Explicit egress rule for PostgreSQL within same namespace

**Fix**: Add same-namespace database egress rule

```bash
# Create a patch file
cat > /tmp/network-policy-patch.yaml <<'EOF'
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  # Allow access to infrastructure namespace (Redis, MinIO)
  - to:
    - namespaceSelector:
        matchLabels:
          name: infrastructure
  # Allow DNS resolution
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: UDP
      port: 53
  # Allow external HTTPS traffic
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: TCP
      port: 443
  # NEW: Allow PostgreSQL access within same namespace
  - to:
    - podSelector:
        matchLabels:
          cnpg.io/cluster: crystalshards-postgres
    ports:
    - protocol: TCP
      port: 5432
EOF

# Apply the patch
kubectl apply -f /tmp/network-policy-patch.yaml -n $NS_CRYSTALSHARDS

# Verify policy updated
kubectl get networkpolicy allow-infrastructure-access -n $NS_CRYSTALSHARDS -o yaml
```

**Alternative**: If you want to allow all same-namespace traffic (less restrictive):

```yaml
egress:
  # Allow all traffic within same namespace
  - to:
    - podSelector: {}
```

## Step 7: Verify Redis Connectivity

```bash
# Check Redis in infrastructure namespace
kubectl get pods -n $NS_INFRASTRUCTURE -l app=redis

# Expected: Redis pod(s) in Running state

# Get Redis service
kubectl get service -n $NS_INFRASTRUCTURE | grep redis

# Expected: shared-redis service

# Test connectivity from app pod
POD=$(kubectl get pods -n $NS_CRYSTALSHARDS -l app=crystalshards,component=api -o jsonpath='{.items[0].metadata.name}')

kubectl exec $POD -n $NS_CRYSTALSHARDS -- nslookup shared-redis.infrastructure.svc.cluster.local

# Expected: Should resolve

kubectl exec $POD -n $NS_CRYSTALSHARDS -- nc -zv shared-redis.infrastructure.svc.cluster.local 6379

# Expected: Connection succeeds
```

**Success Criteria**: Redis accessible from app pod

## Step 8: Check Application Secrets

```bash
# Verify application secret exists
kubectl get secret crystalshards-secrets -n $NS_CRYSTALSHARDS

# Inspect secret contents (keys only, not values)
kubectl get secret crystalshards-secrets -n $NS_CRYSTALSHARDS -o jsonpath='{.data}' | jq 'keys'

# Expected keys:
# - database_url
# - redis_url
# - secret_key_base
# - minio_* (several MinIO keys)

# Decode DATABASE_URL to verify format
kubectl get secret crystalshards-secrets -n $NS_CRYSTALSHARDS -o jsonpath='{.data.database_url}' | base64 -d
echo "" # newline

# Expected format:
# postgresql://app:PASSWORD@crystalshards-postgres-rw:5432/crystalshards_production

# Decode REDIS_URL
kubectl get secret crystalshards-secrets -n $NS_CRYSTALSHARDS -o jsonpath='{.data.redis_url}' | base64 -d
echo "" # newline

# Expected format:
# redis://shared-redis.infrastructure.svc.cluster.local:6379/0
```

**Success Criteria**: Secret exists with correct keys and formats

**Common Issues**:

### Issue: Secret doesn't exist
**Symptom**: `Error from server (NotFound): secrets "crystalshards-secrets" not found`

**Cause**: Terraform didn't create secret, likely because CNPG app secret is missing

**Fix**: Ensure CNPG cluster is healthy first, then re-run Terraform

### Issue: DATABASE_URL format incorrect
**Symptom**: URL missing password or has wrong service name

**Cause**: Terraform data source failed to read CNPG app secret

**Fix**: Manually update secret or re-run Terraform

## Step 9: Test Health Endpoint Manually

```bash
# Port-forward to app pod
POD=$(kubectl get pods -n $NS_CRYSTALSHARDS -l app=crystalshards,component=api -o jsonpath='{.items[0].metadata.name}')

kubectl port-forward $POD -n $NS_CRYSTALSHARDS 3000:3000 &
PF_PID=$!

# Wait a moment for port-forward to establish
sleep 2

# Test health endpoint
curl -v http://localhost:3000/api/health

# Expected response (healthy):
# HTTP/1.1 200 OK
# {"status":"ok","version":"0.1.0","timestamp":"...","services":{"database":"healthy","redis":"healthy"}}

# Expected response (unhealthy):
# HTTP/1.1 503 Service Unavailable
# {"status":"degraded","version":"0.1.0","timestamp":"...","services":{"database":"unhealthy: ERROR MESSAGE","redis":"healthy"}}

# Kill port-forward
kill $PF_PID
```

**Success Criteria**: Health endpoint returns 200 OK with all services healthy

**Common Errors**:

- `"database":"unhealthy: could not connect to server"` → Database not accessible
- `"database":"unhealthy: connection refused"` → Database not listening or network blocked
- `"database":"unhealthy: timeout"` → Network policy or slow startup
- `"redis":"unhealthy: connection refused"` → Redis not accessible

## Step 10: Restart Pods After Fixes

After fixing any issues (network policy, CNPG cluster, etc.), restart pods:

```bash
# Restart deployment to pick up fixes
kubectl rollout restart deployment crystalshards-api -n $NS_CRYSTALSHARDS

# Watch rollout status
kubectl rollout status deployment crystalshards-api -n $NS_CRYSTALSHARDS

# Check pod status
kubectl get pods -n $NS_CRYSTALSHARDS -l app=crystalshards,component=api

# Expected: 2/2 Running and READY (1/1)

# Check health endpoint via service
kubectl port-forward service/crystalshards-api -n $NS_CRYSTALSHARDS 3000:80 &
PF_PID=$!
sleep 2
curl http://localhost:3000/api/health
kill $PF_PID
```

**Success Criteria**: Pods running and ready, health check returns 200 OK

## Step 11: Verify HTML UI is Serving

```bash
# Test via port-forward to service
kubectl port-forward service/crystalshards-api -n $NS_CRYSTALSHARDS 3000:80 &
PF_PID=$!
sleep 2

# Request homepage
curl -v http://localhost:3000/

# Expected: HTML content (not JSON)
# Look for: <!DOCTYPE html> or <html>

kill $PF_PID

# If ingress is set up, test via public URL
curl -v https://crystalshards.org/

# Expected: HTML homepage
```

**Success Criteria**: HTML UI is served correctly

## Step 12: Monitor for Stability

```bash
# Watch pods for 5 minutes to ensure they stay healthy
kubectl get pods -n $NS_CRYSTALSHARDS -l app=crystalshards,component=api -w

# In another terminal, watch events
kubectl get events -n $NS_CRYSTALSHARDS --watch

# Look for:
# - No probe failures
# - No crashes
# - No restarts
```

## Rollback Procedure

If fixes don't work and you need to rollback:

```bash
# Rollback deployment to previous version
kubectl rollout undo deployment crystalshards-api -n $NS_CRYSTALSHARDS

# Check rollout history
kubectl rollout history deployment crystalshards-api -n $NS_CRYSTALSHARDS

# Rollback to specific revision
kubectl rollout undo deployment crystalshards-api -n $NS_CRYSTALSHARDS --to-revision=N
```

## Success Verification Checklist

- [ ] RBAC applied successfully
- [ ] CNPG cluster in healthy state (2/2 instances ready)
- [ ] Database app secret exists
- [ ] App pods running and ready (2/2)
- [ ] Health endpoint returns 200 OK
- [ ] Database service healthy
- [ ] Redis service healthy
- [ ] HTML UI serving correctly (not JSON)
- [ ] No errors in pod logs
- [ ] Pods stable for 5+ minutes
- [ ] Public URL serving HTML

## Monitoring Queries

After restoration, monitor these metrics:

```bash
# Prometheus queries (if accessible)
# - Health check success rate
rate(http_requests_total{path="/api/health",status="200"}[5m])

# - Database connection pool
database_connections_active{namespace="crystalshards"}

# - Redis connection status
redis_connected_clients{namespace="infrastructure"}
```

## Post-Incident Actions

Once service is restored:

1. Update Post-Event Review: `/workspaces/monorepo/pers/2025-10-09-crystalshards-health-check-failure-outage.md`
2. Document root cause found
3. Update GitHub issue #24 with resolution
4. Create follow-up issues for prevention measures
5. Schedule post-mortem review

## Troubleshooting Tips

### Get comprehensive debugging info
```bash
# One-liner to dump all relevant info
{
  echo "=== NAMESPACE STATUS ==="
  kubectl get all -n crystalshards
  echo ""
  echo "=== CNPG CLUSTER ==="
  kubectl get clusters.postgresql.cnpg.io -n crystalshards
  echo ""
  echo "=== SECRETS ==="
  kubectl get secrets -n crystalshards
  echo ""
  echo "=== NETWORK POLICIES ==="
  kubectl get networkpolicies -n crystalshards
  echo ""
  echo "=== POD LOGS (last 20 lines) ==="
  kubectl logs -n crystalshards -l app=crystalshards,component=api --tail=20
  echo ""
  echo "=== EVENTS ==="
  kubectl get events -n crystalshards --sort-by='.lastTimestamp' | tail -20
} > /tmp/crystalshards-debug.txt

cat /tmp/crystalshards-debug.txt
```

### Common kubectl tips
```bash
# Get all resources including CRDs
kubectl api-resources --verbs=list -o name | xargs -n 1 kubectl get -n crystalshards --show-kind --ignore-not-found

# Watch all events in real-time
kubectl get events -n crystalshards --watch

# Follow logs from all pods matching label
kubectl logs -n crystalshards -l app=crystalshards,component=api --follow --prefix

# Get YAML of all resources for backup
kubectl get all,secrets,configmaps,networkpolicies -n crystalshards -o yaml > /tmp/crystalshards-backup.yaml
```

## Contact Information

- GitHub Issue: #24
- Post-Event Review: `/workspaces/monorepo/pers/2025-10-09-crystalshards-health-check-failure-outage.md`
- Incident Severity: CRITICAL
- SRE Agent: Claude (waiting on RBAC permissions)
