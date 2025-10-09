# Runbook: PostgreSQL Unavailable

## Severity: P0 - CRITICAL

## Alert Name
- Prometheus alert: `PostgreSQLDown`

## Symptoms
- Cannot connect to PostgreSQL database
- All database queries failing
- Applications showing database connection errors
- CloudNativePG cluster in unhealthy state

## Impact
- **CRITICAL**: All applications unable to function
- No data reads or writes possible
- Complete service outage
- Data loss risk if cluster corrupted

## Investigation

### 1. Quick Triage (1 minute)

```bash
# Check CloudNativePG cluster status
kubectl get cluster -n crystalshards

# Check all PostgreSQL pods
kubectl get pods -n crystalshards | grep postgres

# Check recent events
kubectl get events -n crystalshards --sort-by='.lastTimestamp' | grep postgres
```

### 2. Check Pod Status

```bash
# Detailed pod status
kubectl describe pods -n crystalshards -l cnpg.io/cluster=crystalshards-postgres

# Check pod logs
kubectl logs -n crystalshards -l cnpg.io/cluster=crystalshards-postgres --tail=100

# Check operator logs
kubectl logs -n infrastructure -l app.kubernetes.io/name=cloudnative-pg --tail=100
```

### 3. Check Storage

```bash
# Check PVCs
kubectl get pvc -n crystalshards | grep postgres

# Check disk space
kubectl exec -n crystalshards <postgres-pod> -- df -h
```

## Resolution

### Critical Path (Target: < 5 minutes)

#### Scenario 1: Pods CrashLooping

```bash
# Check crash reason
kubectl describe pod -n crystalshards <postgres-pod> | grep -A 10 "Last State"

# Check if data corruption
kubectl logs -n crystalshards <postgres-pod> --previous | grep -i "corruption\|panic\|fatal"

# If configuration issue, edit cluster spec
kubectl edit cluster -n crystalshards crystalshards-postgres

# Force restart if needed
kubectl delete pod -n crystalshards <postgres-pod>
```

#### Scenario 2: Cluster in Failover

```bash
# Check cluster status
kubectl get cluster -n crystalshards -o yaml | grep -A 20 status

# CloudNativePG should auto-failover
# Wait for new primary election (usually 30-60 seconds)

# Force failover if stuck
kubectl cnpg promote -n crystalshards crystalshards-postgres <replica-pod>
```

#### Scenario 3: Out of Disk Space

```bash
# Check disk usage
kubectl exec -n crystalshards <postgres-pod> -- du -sh /var/lib/postgresql/data

# Clean up WAL files if safe
kubectl exec -n crystalshards <postgres-pod> -- \
  psql -U postgres -c "SELECT pg_switch_wal(); CHECKPOINT;"

# Increase PVC size (requires restart)
kubectl edit pvc -n crystalshards postgres-crystalshards-postgres-1
```

#### Scenario 4: Complete Cluster Loss

```bash
# Restore from backup
kubectl get backup -n crystalshards

# Create restore cluster
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: crystalshards-postgres-restore
  namespace: crystalshards
spec:
  instances: 3
  bootstrap:
    recovery:
      backup:
        name: <backup-name>
EOF
```

### Verification

```bash
# Test connection
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT 1;"

# Check cluster is healthy
kubectl get cluster -n crystalshards

# Verify replication
kubectl exec -n crystalshards <primary-pod> -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

## Prevention

1. **Regular Backups**:
   - Automated daily backups
   - Test restore procedures monthly
   - Store backups in separate region

2. **Monitoring**:
   - Alert on pod restarts
   - Monitor disk space (alert at 70%)
   - Track replication health

3. **High Availability**:
   - Run 3 instances minimum
   - Use pod anti-affinity
   - Regular failover testing

## Post-Incident

- [ ] **REQUIRED**: Create Post-Incident Review
- [ ] Verify all backups valid
- [ ] Check data consistency
- [ ] Review cluster logs for root cause
- [ ] Test replica promotion

## Related Runbooks
- [PostgreSQL High Connections](postgres-high-connections.md)
- [PostgreSQL Replication Lag](postgres-replication-lag.md)
- [Application Unavailable](app-unavailable.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
