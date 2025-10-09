# Runbook: PostgreSQL High Connections

## Severity: P1 - HIGH

## Alert Name
- Prometheus alert: `PostgreSQLConnectionExhaustion`

## Symptoms
- Connection pool usage above 80% of max_connections
- New connections being rejected
- Application logs showing "too many connections" errors
- Intermittent database connection failures

## Impact
- New requests failing to get database connections
- Application unable to serve some requests
- Degraded service for users
- Risk of complete service outage

## Investigation

### 1. Initial Triage

- [ ] Check Grafana "PostgreSQL Overview" dashboard
- [ ] Identify which database cluster affected
- [ ] Check current connection count
- [ ] Review recent changes or traffic spikes

```bash
# Check connection count vs limit
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT count(*) as current_connections, (SELECT setting::int FROM pg_settings WHERE name='max_connections') as max_connections FROM pg_stat_activity;"

# Check connection breakdown by state
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state ORDER BY count(*) DESC;"
```

### 2. Identify Connection Sources

```bash
# See which applications/users have most connections
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT usename, application_name, count(*) FROM pg_stat_activity GROUP BY usename, application_name ORDER BY count(*) DESC;"

# See connections by client address
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT client_addr, count(*) FROM pg_stat_activity WHERE client_addr IS NOT NULL GROUP BY client_addr ORDER BY count(*) DESC;"

# Check pod count (more pods = more connections)
kubectl get pods -n crystalshards -l app=crystalshards-api -o wide
```

### 3. Check for Connection Leaks

```bash
# Look for idle connections
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pid, usename, application_name, state, state_change, now() - state_change as idle_time FROM pg_stat_activity WHERE state = 'idle' ORDER BY idle_time DESC LIMIT 20;"

# Look for idle in transaction (indicates connection leak)
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pid, usename, application_name, now() - state_change as duration, query FROM pg_stat_activity WHERE state LIKE 'idle in transaction%' ORDER BY duration DESC;"

# Check long-running queries holding connections
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pid, usename, now() - query_start as duration, state, left(query, 100) FROM pg_stat_activity WHERE state != 'idle' AND query_start IS NOT NULL ORDER BY duration DESC LIMIT 10;"
```

### 4. Check Application Configuration

```bash
# Check database URL and pool configuration
kubectl get secret -n crystalshards crystalshards-secrets -o jsonpath='{.data.DATABASE_URL}' | base64 -d | grep -o "pool=.*"

# Check how many replicas are running
kubectl get deployment -n crystalshards crystalshards-api -o jsonpath='{.spec.replicas}'

# Calculate total possible connections
# replicas * connections_per_replica = total
# Example: 3 replicas * 25 connections = 75 total connections
```

### 5. Root Cause Analysis

Common causes:
- Too many application replicas for database max_connections
- Connection pool size too large per application instance
- Connection leaks in application code
- Long-running queries holding connections
- Idle transactions not being cleaned up
- Sudden traffic spike
- Database max_connections set too low
- Failed graceful shutdown leaving zombie connections

## Resolution

### Immediate Actions

#### If caused by connection leaks:

```bash
# Kill idle in transaction connections (older than 5 minutes)
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state LIKE 'idle in transaction%' AND now() - state_change > interval '5 minutes';"

# Kill long-idle connections (older than 30 minutes)
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND now() - state_change > interval '30 minutes';"
```

#### If caused by too many replicas:

```bash
# Temporarily scale down application
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=2

# Monitor connection count
watch -n 5 "kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql \"\$DATABASE_URL\" -c \"SELECT count(*) FROM pg_stat_activity;\""
```

#### If caused by traffic spike:

```bash
# Check if HPA is enabled
kubectl get hpa -n crystalshards

# Temporarily increase database max_connections
# Connect to CloudNativePG primary pod
kubectl exec -it -n crystalshards <postgres-primary-pod> -- bash

# Edit postgresql.conf (requires restart)
# OR use ALTER SYSTEM (requires reload)
psql -U postgres -c "ALTER SYSTEM SET max_connections = 200;"
psql -U postgres -c "SELECT pg_reload_conf();"

# Note: CloudNativePG may override this - check cluster spec
```

#### If caused by hung queries:

```bash
# Identify and kill blocking queries
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state != 'idle' AND now() - query_start > interval '10 minutes';"
```

### Permanent Fix

1. **Adjust Connection Pool Configuration**:

   Calculate proper pool size:
   ```
   max_connections = 100 (database setting)
   reserved_connections = 10 (for admin)
   available = 90

   replicas = 3 (application pods)
   pool_size_per_replica = 90 / 3 = 30

   Set pool_size = 25 (with safety margin)
   ```

   Update database URL:
   ```bash
   # Edit secret with proper pool size
   kubectl edit secret crystalshards-secrets -n crystalshards

   # Add/update: ?pool=25&initial_pool_size=5&max_idle_pool_size=10
   ```

2. **Increase Database max_connections** (CloudNativePG):

   ```bash
   # Edit CloudNativePG cluster
   kubectl edit cluster -n crystalshards crystalshards-postgres

   # Add under spec.postgresql.parameters:
   # max_connections: "200"

   # CloudNativePG will rolling restart to apply
   ```

3. **Fix Connection Leaks in Code**:

   - Use Lucky's connection pool properly
   - Always close connections in ensure blocks
   - Set query timeout
   - Use transactions properly
   - Implement connection health checks

   ```crystal
   # Good pattern
   Avram::Database.run do |db|
     # Use connection
   end  # Automatically returned to pool

   # Set timeout
   Avram::Database.settings.query_timeout = 30.seconds
   ```

4. **Implement Connection Limits**:

   ```bash
   # Set per-user connection limits
   kubectl exec -n crystalshards deployment/crystalshards-api -- \
     psql "$DATABASE_URL" -c "ALTER ROLE crystalshards CONNECTION LIMIT 80;"
   ```

5. **Add Connection Monitoring**:

   ```bash
   # Add Grafana panel for connection usage
   # Query: pg_stat_activity_count / pg_settings_max_connections

   # Add alert for > 70% usage (warning)
   # Update prometheus rules
   ```

## Commands Reference

### Connection Diagnostics

```bash
# Detailed connection info
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pid, usename, application_name, client_addr, state, state_change, query_start, left(query, 50) FROM pg_stat_activity ORDER BY state_change;"

# Connection age distribution
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT state, EXTRACT(EPOCH FROM (now() - state_change))/60 as minutes_in_state, count(*) FROM pg_stat_activity GROUP BY state, minutes_in_state ORDER BY minutes_in_state DESC;"

# Find connection leaks by query
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT state, left(query, 80), count(*) FROM pg_stat_activity WHERE state = 'idle' GROUP BY state, query ORDER BY count(*) DESC;"
```

### Connection Management

```bash
# Gracefully terminate connections
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = 'crystalshards' AND pid != pg_backend_pid();"

# Force close specific connection
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pg_terminate_backend(<pid>);"

# Cancel running query (less aggressive than terminate)
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pg_cancel_backend(<pid>);"
```

### CloudNativePG Cluster Commands

```bash
# Check cluster status
kubectl get cluster -n crystalshards -o yaml

# Check current PostgreSQL configuration
kubectl exec -n crystalshards <postgres-primary-pod> -- \
  psql -U postgres -c "SHOW max_connections;"

# View all PostgreSQL settings
kubectl exec -n crystalshards <postgres-primary-pod> -- \
  psql -U postgres -c "SELECT name, setting, unit FROM pg_settings WHERE name LIKE '%connection%';"
```

## Prevention

1. **Proper Pool Sizing**:
   - Calculate based on: max_connections / (number_of_replicas + other_apps)
   - Set initial_pool_size low (5-10)
   - Set max_pool_size based on calculation
   - Monitor actual usage and adjust

2. **Connection Timeout Configuration**:
   ```crystal
   # In Avram database configuration
   Avram::Database.settings.connection_timeout = 5.seconds
   Avram::Database.settings.query_timeout = 30.seconds
   Avram::Database.settings.idle_timeout = 5.minutes
   ```

3. **Application Best Practices**:
   - Use connection pooling
   - Close connections promptly
   - Avoid idle in transaction
   - Set statement timeout
   - Use read replicas for read-heavy queries

4. **Monitoring**:
   - Alert on connection usage > 70%
   - Track connections by application
   - Monitor idle in transaction count
   - Track connection acquisition time

5. **Regular Maintenance**:
   - Review connection logs weekly
   - Identify patterns in connection spikes
   - Load test to find connection limits
   - Tune based on actual usage

## Post-Incident

- [ ] Review connection pool configuration
- [ ] Check for code causing connection leaks
- [ ] Update monitoring thresholds
- [ ] Document optimal pool sizes
- [ ] Create ticket for code fixes if leaks found
- [ ] Update runbook with findings

## Related Runbooks
- [PostgreSQL Unavailable](postgres-unavailable.md)
- [Application High Error Rate](app-high-error-rate.md)
- [Application High Latency](app-high-latency.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
