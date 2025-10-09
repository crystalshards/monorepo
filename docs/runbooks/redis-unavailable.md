# Runbook: Redis Unavailable

## Severity: P0 - CRITICAL (if used for sessions/critical features) or P1 - HIGH (if only cache)

## Alert Name
- Prometheus alert: `RedisDown`

## Symptoms
- Cannot connect to Redis
- Cache operations failing
- Worker jobs not processing
- Session storage unavailable (if used)

## Impact
- Cache unavailable → increased database load
- Worker queues stopped → background jobs not processing
- Sessions lost if using Redis for sessions
- Rate limiting may fail

## Investigation

### 1. Quick Triage

```bash
# Check Redis pods
kubectl get pods -n infrastructure -l app=redis

# Check Redis operator
kubectl get pods -n infrastructure -l app.kubernetes.io/name=redis-operator

# Check recent events
kubectl get events -n infrastructure --sort-by='.lastTimestamp' | grep redis
```

### 2. Check Redis Status

```bash
# Try to connect
kubectl exec -n infrastructure deployment/redis-master -- redis-cli PING

# Check logs
kubectl logs -n infrastructure -l app=redis --tail=100

# Check resource usage
kubectl top pods -n infrastructure -l app=redis
```

## Resolution

### Immediate Actions

```bash
# Restart Redis pod
kubectl delete pod -n infrastructure -l app=redis

# Check if PVC has issues
kubectl get pvc -n infrastructure | grep redis

# Verify deployment
kubectl get deployment -n infrastructure redis-master
```

### If Corrupted

```bash
# Backup and restart
kubectl exec -n infrastructure deployment/redis-master -- redis-cli SAVE

# If corruption detected, start fresh (loses cache data)
kubectl scale deployment redis-master -n infrastructure --replicas=0
kubectl scale deployment redis-master -n infrastructure --replicas=1
```

## Prevention

- Run Redis in HA mode with sentinel
- Regular persistence to disk
- Monitor Redis health
- Set appropriate memory limits

## Related Runbooks
- [Redis High Memory](redis-high-memory.md)
- [Worker Queue Backlog](worker-queue-backlog.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
