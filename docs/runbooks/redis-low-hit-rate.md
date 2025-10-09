# Runbook: Redis Low Hit Rate

## Severity: P3 - LOW

## Alert Name
- Prometheus alert: `RedisLowHitRate`

## Symptoms
- Cache hit rate below 50%
- High database query load
- Slow application response times
- Excessive cache misses

## Impact
- Increased database load
- Higher latency for cached queries
- Inefficient cache usage
- Increased costs

## Investigation

### 1. Check Hit Rate

```bash
# Get hit/miss statistics
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli INFO stats | grep keyspace

# Calculate hit rate
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli INFO stats | awk '/keyspace_hits/ {hits=$2} /keyspace_misses/ {misses=$2} END {print "Hit Rate:", hits/(hits+misses)*100 "%"}'
```

### 2. Analyze Cache Keys

```bash
# Check key count
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli DBSIZE

# Sample random keys to see patterns
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli --scan --pattern "*" | head -50

# Check TTL distribution
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli --scan | while read key; do redis-cli TTL "$key"; done | sort -n | uniq -c
```

### 3. Root Cause

Common causes:
- Cache not being used by application
- TTLs too short
- Cache keys changing frequently
- High volume of unique requests
- Cache warming not implemented
- Invalidation too aggressive

## Resolution

### Actions

1. **Adjust TTL Strategy**:
   ```crystal
   # Longer TTL for stable data
   REDIS.setex("shard:#{id}:info", 1.hour, data)

   # Shorter TTL for frequently changing data
   REDIS.setex("stats:current", 5.minutes, stats)
   ```

2. **Implement Cache Warming**:
   ```crystal
   # Pre-populate popular items
   PopularShards.cache_popular_shards
   ```

3. **Optimize Cache Keys**:
   - Use consistent key patterns
   - Cache frequently accessed data
   - Avoid caching unique requests

## Prevention

- Monitor hit rate trends
- Review cache strategy quarterly
- Cache frequently accessed data
- Use appropriate TTLs
- Implement cache warming for popular content

## Related Runbooks
- [Redis High Memory](redis-high-memory.md)
- [Application High Latency](app-high-latency.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
