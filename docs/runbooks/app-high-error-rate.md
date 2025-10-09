# Runbook: Application High Error Rate

## Severity: P1 - HIGH

## Alert Name
- Prometheus alert: `HighErrorRate`

## Symptoms
- 5xx HTTP errors exceeding 5% of total requests
- User reports of "Internal Server Error" messages
- Grafana dashboard showing error rate spike
- Application logs showing exceptions

## Impact
- Users experiencing service errors
- Some requests failing
- Reputation damage
- Possible data inconsistency

## Investigation

### 1. Initial Triage

- [ ] Check Grafana "Lucky Applications Overview" dashboard
- [ ] Identify which application(s) affected (crystalshards, crystaldocs, crystalgigs, crystalbits)
- [ ] Review recent deployments in last 2 hours
- [ ] Check alert history for similar incidents

```bash
# Check recent deployments
kubectl get deployments -n crystalshards -o json | \
  jq '.items[] | {name: .metadata.name, updated: .metadata.annotations."deployment.kubernetes.io/revision"}'

# Check pod events
kubectl get events -n crystalshards --sort-by='.lastTimestamp' | tail -20
```

### 2. Check Application Logs

```bash
# Get pods for affected application
kubectl get pods -n crystalshards -l app=crystalshards-api

# Check recent logs for errors
kubectl logs -n crystalshards -l app=crystalshards-api --tail=100 | grep -i error

# Follow logs in real-time
kubectl logs -n crystalshards -l app=crystalshards-api -f
```

### 3. Check Database Connectivity

```bash
# Check PostgreSQL cluster status
kubectl get cluster -n crystalshards

# Check database connections
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT count(*) FROM pg_stat_activity;"

# Check for long-running queries
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pid, now() - query_start as duration, state, query FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC LIMIT 10;"
```

### 4. Check Redis Connectivity

```bash
# Check Redis status
kubectl get pods -n infrastructure -l app=redis

# Test Redis connection from app
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  sh -c 'echo "PING" | redis-cli -u "$REDIS_URL"'

# Check Redis memory
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli INFO memory | grep used_memory_human
```

### 5. Check Resource Utilization

```bash
# Check pod resource usage
kubectl top pods -n crystalshards

# Check node capacity
kubectl top nodes

# Check for OOMKilled pods
kubectl get pods -n crystalshards -o json | \
  jq '.items[] | select(.status.containerStatuses[].lastState.terminated.reason == "OOMKilled") | {name: .metadata.name, reason: .status.containerStatuses[].lastState.terminated.reason}'
```

### 6. Root Cause Analysis

Common causes:
- Recent deployment introduced bugs
- Database connection pool exhausted
- External API timeouts
- Memory leaks causing OOM
- Redis cache unavailable
- Unhandled exceptions in code
- Database deadlocks
- Disk space issues

## Resolution

### Immediate Actions

#### If caused by recent deployment:

```bash
# Rollback deployment
kubectl rollout undo deployment/crystalshards-api -n crystalshards

# Monitor rollback
kubectl rollout status deployment/crystalshards-api -n crystalshards

# Verify error rate decreased
# (Check Grafana dashboard)
```

#### If caused by database issues:

```bash
# Restart application pods to reset connections
kubectl rollout restart deployment/crystalshards-api -n crystalshards

# If database has issues, check postgres-unavailable.md runbook
```

#### If caused by memory issues:

```bash
# Restart pods to clear memory
kubectl rollout restart deployment/crystalshards-api -n crystalshards

# Scale up replicas temporarily
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=5
```

#### If caused by Redis issues:

```bash
# Restart Redis if needed
kubectl rollout restart deployment/redis-master -n infrastructure

# Clear Redis cache if corrupted
kubectl exec -n infrastructure deployment/redis-master -- redis-cli FLUSHALL
```

### Permanent Fix

1. **Fix Code Bug**:
   - Identify exception in logs
   - Create hotfix branch
   - Add error handling
   - Add tests to prevent regression
   - Deploy fix

2. **Adjust Resource Limits**:
   ```bash
   # Edit deployment to increase memory/CPU
   kubectl edit deployment crystalshards-api -n crystalshards

   # Update limits in terraform code for next deploy
   ```

3. **Optimize Database Queries**:
   - Identify slow queries
   - Add indexes
   - Optimize N+1 queries
   - Use Lucky query optimization

4. **Improve Error Handling**:
   - Add proper exception handling
   - Return appropriate HTTP status codes
   - Log errors with context
   - Implement circuit breakers

## Commands Reference

### View Application Metrics

```bash
# Error rate over last 15 minutes
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
# Then query: rate(http_requests_total{namespace="crystalshards",status=~"5.."}[5m])

# Check specific endpoint errors
kubectl logs -n crystalshards -l app=crystalshards-api --tail=500 | \
  grep "status=5" | awk '{print $5}' | sort | uniq -c | sort -nr
```

### Check Application Health

```bash
# Health endpoint check
kubectl run curl-test --image=curlimages/curl -i --rm --restart=Never -- \
  curl -v http://crystalshards.crystalshards.svc.cluster.local:3000/health

# Check all replicas
for pod in $(kubectl get pods -n crystalshards -l app=crystalshards-api -o name); do
  echo "=== $pod ==="
  kubectl exec -n crystalshards $pod -- wget -qO- http://localhost:3000/health
done
```

### Scale Application

```bash
# Scale up
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=5

# Scale down (after issue resolved)
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=3
```

## Prevention

1. **Improve Testing**:
   - Add integration tests for error scenarios
   - Load test before production deploy
   - Test database connection pool limits
   - Test Redis failure scenarios

2. **Better Monitoring**:
   - Alert on error rate increase > 2%
   - Monitor error rate by endpoint
   - Track error types and patterns
   - Set up error tracking (Sentry, Rollbar)

3. **Deployment Best Practices**:
   - Use canary deployments
   - Implement automatic rollback on errors
   - Add deployment health checks
   - Deploy during low-traffic windows

4. **Code Quality**:
   - Implement comprehensive error handling
   - Add circuit breakers for external services
   - Use timeouts on all external calls
   - Implement retry logic with backoff

## Post-Incident

- [ ] Update incident log with timeline
- [ ] Create Post-Incident Review if > 30 minutes
- [ ] Identify root cause
- [ ] Create tickets for preventive measures
- [ ] Update monitoring if needed
- [ ] Update runbook with learnings

## Related Runbooks
- [Application High Latency](app-high-latency.md)
- [Application Unavailable](app-unavailable.md)
- [PostgreSQL Connection Exhaustion](postgres-high-connections.md)
- [Redis Unavailable](redis-unavailable.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
