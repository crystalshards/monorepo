# Runbook: Worker Queue Backlog

## Severity: P2 - MEDIUM

## Symptoms
- Background job queue growing
- Jobs not processing
- Delayed shard indexing
- Documentation builds queued but not running

## Impact
- New shards not appearing in search
- Documentation not being published
- User experience degraded for new content
- Risk of queue overflow

## Investigation

```bash
# Check worker pods
kubectl get pods -n crystalshards -l app=crystalshards-workers

# Check worker logs
kubectl logs -n crystalshards -l app=crystalshards-workers --tail=100

# Check Redis queue size
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli LLEN joobq:default:queue

# Check for failed jobs
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli LLEN joobq:default:failed

# Check worker resource usage
kubectl top pods -n crystalshards -l app=crystalshards-workers
```

## Resolution

### Scale Workers

```bash
# Increase worker replicas
kubectl scale deployment/crystalshards-workers -n crystalshards --replicas=5

# Monitor queue size
watch -n 5 "kubectl exec -n infrastructure deployment/redis-master -- redis-cli LLEN joobq:default:queue"
```

### Clear Failed Jobs

```bash
# Check failed jobs
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli LRANGE joobq:default:failed 0 10

# Clear dead letter queue if jobs are unfixable
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli DEL joobq:default:failed
```

### Restart Workers

```bash
# Restart worker pods
kubectl rollout restart deployment/crystalshards-workers -n crystalshards

# Check if workers are processing
kubectl logs -n crystalshards -l app=crystalshards-workers -f | grep -i "processing"
```

## Prevention

- Monitor queue depth (alert > 100)
- Scale workers based on queue size
- Implement job timeouts
- Add dead letter queue monitoring
- Regular worker health checks

## Related Runbooks
- [Documentation Build Failures](doc-build-failures.md)
- [Redis Unavailable](redis-unavailable.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
