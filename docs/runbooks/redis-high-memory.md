# Runbook: Redis High Memory Usage

## Severity: P2 - MEDIUM

## Alert Name
- Prometheus alert: `RedisHighMemoryUsage`

## Symptoms
- Redis memory usage above 80%
- Cache evictions occurring
- Slow cache operations
- Risk of OOM kill

## Impact
- Cache performance degraded
- Increased database load from cache misses
- Risk of Redis crash if memory exhausted
- Worker queue may be affected

## Investigation

### 1. Check Current Memory Usage

```bash
# Check memory info
kubectl exec -n infrastructure deployment/redis-master -- redis-cli INFO memory

# Check maxmemory settings
kubectl exec -n infrastructure deployment/redis-master -- redis-cli CONFIG GET maxmemory

# Check eviction policy
kubectl exec -n infrastructure deployment/redis-master -- redis-cli CONFIG GET maxmemory-policy
```

### 2. Identify Large Keys

```bash
# Find largest keys
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli --bigkeys

# Count keys by pattern
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli --scan --pattern "shards:*" | wc -l

# Sample key sizes
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli --memkeys --memkeys-samples 10000
```

### 3. Check Eviction Stats

```bash
# Check evicted keys count
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli INFO stats | grep evicted_keys

# Check keyspace statistics
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli INFO keyspace
```

## Resolution

### Immediate Actions

```bash
# Clear old cache entries (if safe)
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli --scan --pattern "cache:old:*" | xargs redis-cli DEL

# Flush specific database (careful!)
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli -n 1 FLUSHDB

# Set eviction policy if not set
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

### Permanent Fix

1. **Increase Memory Limit**:
   ```bash
   kubectl edit deployment redis-master -n infrastructure
   # Increase memory limits

   # Update Redis maxmemory
   kubectl exec -n infrastructure deployment/redis-master -- \
     redis-cli CONFIG SET maxmemory 4gb
   ```

2. **Optimize Cache Usage**:
   - Set appropriate TTLs on keys
   - Reduce cache value sizes
   - Clear unused cache namespaces
   - Use Redis hashes for related data

3. **Implement Cache Warming**:
   ```crystal
   # Selective cache warming instead of caching everything
   cache_key = "shards:popular:#{date}"
   REDIS.setex(cache_key, 1.hour, popular_shards.to_json)
   ```

## Prevention

- Set maxmemory-policy to allkeys-lru
- Monitor memory trends
- Regular cache analysis
- Set appropriate TTLs
- Alert at 70% usage

## Related Runbooks
- [Redis Unavailable](redis-unavailable.md)
- [Redis Low Hit Rate](redis-low-hit-rate.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
