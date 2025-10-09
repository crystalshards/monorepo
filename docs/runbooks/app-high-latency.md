# Runbook: Application High Latency

## Severity: P2 - MEDIUM

## Alert Name
- Prometheus alert: `HighLatency`

## Symptoms
- P95 response time exceeding 1 second
- User complaints about slow page loads
- Grafana dashboard showing latency spike
- Timeouts occurring on some requests

## Impact
- Poor user experience
- Decreased conversion rates
- Risk of timeouts and errors
- User frustration

## Investigation

### 1. Initial Triage

- [ ] Check Grafana "Lucky Applications Overview" dashboard
- [ ] Identify which application(s) affected
- [ ] Check which endpoints are slow
- [ ] Review recent changes or traffic patterns
- [ ] Check alert history for patterns

```bash
# Check current response times
kubectl logs -n crystalshards -l app=crystalshards-api --tail=200 | \
  grep "duration=" | awk -F'duration=' '{print $2}' | awk '{print $1}' | sort -n | tail -20

# Check request rate
kubectl logs -n crystalshards -l app=crystalshards-api --tail=200 | \
  grep "status=" | wc -l
```

### 2. Identify Slow Endpoints

```bash
# Analyze logs for slow endpoints
kubectl logs -n crystalshards -l app=crystalshards-api --tail=500 | \
  grep "duration=" | awk '{print $3, $NF}' | sort -k2 -n | tail -20

# Most frequently called endpoints
kubectl logs -n crystalshards -l app=crystalshards-api --tail=1000 | \
  grep "method=" | awk '{print $5}' | sort | uniq -c | sort -nr | head -10
```

### 3. Check Database Performance

```bash
# Check active queries
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pid, now() - query_start as duration, state, left(query, 100) FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC;"

# Check slow queries (if pg_stat_statements enabled)
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT query, calls, mean_exec_time, max_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"

# Check table sizes (bloat can cause slow queries)
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema') ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;"

# Check index usage
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT schemaname, tablename, indexname, idx_scan FROM pg_stat_user_indexes WHERE idx_scan = 0 ORDER BY pg_size_pretty(pg_relation_size(indexrelid));"
```

### 4. Check Redis Cache Performance

```bash
# Check Redis hit rate
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli INFO stats | grep keyspace

# Check cache miss rate
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"

# Check slow log
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli SLOWLOG GET 10
```

### 5. Check Resource Utilization

```bash
# Check CPU/memory usage
kubectl top pods -n crystalshards

# Check if pods are throttled
kubectl describe pods -n crystalshards -l app=crystalshards-api | \
  grep -A 5 "Resource Limits"

# Check node resources
kubectl top nodes

# Check pod count
kubectl get pods -n crystalshards -l app=crystalshards-api
```

### 6. Check External Dependencies

```bash
# Check if external API calls are slow
kubectl logs -n crystalshards -l app=crystalshards-api --tail=200 | \
  grep -i "http" | grep -i "duration"

# Check DNS resolution
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  nslookup github.com

# Check network latency to external services
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  time curl -o /dev/null -s -w '%{time_total}\n' https://api.github.com
```

### 7. Root Cause Analysis

Common causes:
- Slow database queries (missing indexes, N+1 queries)
- High query volume overwhelming database
- Cache misses or cache not used
- External API calls timing out
- Resource constraints (CPU/memory)
- Large result sets not paginated
- Lock contention in database
- Network issues
- Too few replicas for current load

## Resolution

### Immediate Actions

#### If caused by slow database queries:

```bash
# Kill long-running queries if blocking
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state != 'idle' AND now() - query_start > interval '5 minutes';"

# Restart app to reset connection pool
kubectl rollout restart deployment/crystalshards-api -n crystalshards
```

#### If caused by high load:

```bash
# Scale up application replicas
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=5

# Monitor autoscaling
kubectl get hpa -n crystalshards
```

#### If caused by cache misses:

```bash
# Warm up cache for common queries
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  sh -c 'wget -qO- http://localhost:3000/api/shards?limit=100 > /dev/null'

# Check cache TTL settings
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli CONFIG GET maxmemory-policy
```

#### If caused by resource constraints:

```bash
# Temporarily increase pod limits
kubectl edit deployment crystalshards-api -n crystalshards

# Scale horizontally
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=5
```

### Permanent Fix

1. **Optimize Database Queries**:
   ```sql
   -- Add missing indexes
   CREATE INDEX CONCURRENTLY idx_shards_name ON shards(name);
   CREATE INDEX CONCURRENTLY idx_shard_versions_shard_id ON shard_versions(shard_id);

   -- Analyze query plans
   EXPLAIN ANALYZE SELECT * FROM shards WHERE name ILIKE '%search%';
   ```

2. **Implement Better Caching**:
   - Cache expensive queries
   - Use Redis for session storage
   - Add CDN for static assets
   - Implement query result caching in Lucky

3. **Optimize Code**:
   - Fix N+1 queries with proper preloading
   - Paginate large result sets
   - Use database views for complex queries
   - Implement lazy loading

4. **Scale Infrastructure**:
   ```bash
   # Update Terraform to increase resources
   # In apps/crystalshards/terraform/resource.kubernetes_deployment.crystalshards_api.tf
   # Increase CPU/memory limits

   # Apply changes
   cd terraform
   terraform apply -target=module.applications.module.crystalshards
   ```

5. **Implement Query Optimization**:
   - Use Lucky's query builder efficiently
   - Avoid SELECT * in large tables
   - Use database functions for aggregations
   - Implement materialized views for complex reports

## Commands Reference

### Database Query Analysis

```bash
# Enable query logging temporarily
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "ALTER DATABASE crystalshards SET log_min_duration_statement = 1000;"

# View query execution plan
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM shards WHERE name ILIKE '%crystal%' LIMIT 20;"

# Check connection pool status (if using pgbouncer)
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SHOW POOL;"
```

### Performance Testing

```bash
# Run load test
kubectl run siege --image=yokogawa/siege --rm -i --restart=Never -- \
  -c 50 -t 30S https://crystalshards.org/api/shards

# Monitor during load test
watch -n 2 kubectl top pods -n crystalshards
```

### Cache Operations

```bash
# Clear specific cache keys
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli --scan --pattern "shards:*" | xargs redis-cli DEL

# Monitor cache operations
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli MONITOR
```

## Prevention

1. **Implement Query Monitoring**:
   - Enable pg_stat_statements
   - Alert on slow queries > 2s
   - Regular query performance review
   - Automated slow query reporting

2. **Optimize Application**:
   - Profile code with crystal tool
   - Implement request tracing
   - Add performance tests to CI
   - Use database query explain in tests

3. **Better Caching Strategy**:
   - Cache common queries
   - Implement cache warming
   - Monitor cache hit rates
   - Set appropriate TTLs

4. **Capacity Planning**:
   - Monitor traffic trends
   - Scale proactively
   - Load test regularly
   - Implement autoscaling

5. **Code Review Process**:
   - Review query patterns in PRs
   - Require explain plans for complex queries
   - Test with production-like data
   - Performance benchmarks in CI

## Post-Incident

- [ ] Identify which queries were slow
- [ ] Create tickets for database optimizations
- [ ] Update monitoring thresholds if needed
- [ ] Add performance tests for affected endpoints
- [ ] Document query optimization decisions
- [ ] Update runbook with findings

## Related Runbooks
- [Application High Error Rate](app-high-error-rate.md)
- [PostgreSQL Connection Exhaustion](postgres-high-connections.md)
- [Redis Low Hit Rate](redis-low-hit-rate.md)
- [PostgreSQL Replication Lag](postgres-replication-lag.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
