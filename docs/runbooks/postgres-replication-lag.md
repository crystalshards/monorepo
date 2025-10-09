# Runbook: PostgreSQL Replication Lag

## Severity: P2 - MEDIUM

## Alert Name
- Prometheus alert: `PostgreSQLHighReplicationLag`

## Symptoms
- Read replicas falling behind primary by > 30 seconds
- Stale data being served from replicas
- Inconsistent query results between reads

## Impact
- Users may see outdated information
- Read queries returning stale data
- Risk of replica falling too far behind
- Potential for longer recovery if primary fails

## Investigation

### 1. Check Replication Status

```bash
# Check CloudNativePG cluster status
kubectl get cluster -n crystalshards

# Check replication lag
kubectl exec -n crystalshards <primary-pod> -- \
  psql -U postgres -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"

# Check from replica perspective
kubectl exec -n crystalshards <replica-pod> -- \
  psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

### 2. Check Write Load

```bash
# Check transaction rate on primary
kubectl exec -n crystalshards <primary-pod> -- \
  psql -U postgres -c "SELECT xact_commit + xact_rollback as total_txns FROM pg_stat_database WHERE datname = 'crystalshards';"

# Check WAL generation rate
kubectl exec -n crystalshards <primary-pod> -- \
  psql -U postgres -c "SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());"
```

### 3. Root Cause

Common causes:
- High write volume on primary
- Network issues between primary and replica
- Replica resource constraints
- Long-running queries on replica
- Disk I/O bottleneck on replica

## Resolution

### Immediate Actions

```bash
# Check replica resources
kubectl top pod -n crystalshards <replica-pod>

# Check if replica has long-running queries
kubectl exec -n crystalshards <replica-pod> -- \
  psql -U postgres -c "SELECT pid, now() - query_start as duration, query FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC;"

# Kill long queries on replica if blocking
kubectl exec -n crystalshards <replica-pod> -- \
  psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state != 'idle' AND now() - query_start > interval '10 minutes';"
```

### Permanent Fix

1. **Increase Replica Resources**:
   ```bash
   kubectl edit cluster -n crystalshards crystalshards-postgres
   # Increase CPU/memory for replicas
   ```

2. **Tune Replication Settings**:
   ```sql
   -- Increase WAL sender priority
   ALTER SYSTEM SET wal_sender_timeout = '120s';
   SELECT pg_reload_conf();
   ```

3. **Reduce Write Load**:
   - Batch writes where possible
   - Use connection pooling
   - Optimize write-heavy queries

## Prevention

- Monitor replication lag continuously
- Alert on lag > 10 seconds
- Ensure replicas have adequate resources
- Regular replication testing

## Related Runbooks
- [PostgreSQL Unavailable](postgres-unavailable.md)
- [PostgreSQL High Connections](postgres-high-connections.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
