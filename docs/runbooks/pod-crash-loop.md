# Runbook: Pod Crash Looping

## Severity: P0 - CRITICAL

## Alert Name
- Prometheus alert: `PodCrashLooping`

## Symptoms
- Pod repeatedly restarting
- Container exit code non-zero
- Application unavailable or degraded
- Increasing restart count

## Impact
- Service degradation or outage
- Resource waste from constant restarts
- Possible data loss
- System instability

## Investigation

```bash
# Check pod status
kubectl get pods -n crystalshards -l app=crystalshards-api

# Describe pod to see crash reason
kubectl describe pod -n crystalshards <pod-name> | grep -A 20 "Last State"

# Check logs from current attempt
kubectl logs -n crystalshards <pod-name>

# Check logs from previous crash
kubectl logs -n crystalshards <pod-name> --previous

# Check events
kubectl get events -n crystalshards --sort-by='.lastTimestamp' | tail -20
```

## Common Causes & Resolutions

### OOMKilled (Out of Memory)

```bash
# Verify OOM
kubectl describe pod -n crystalshards <pod-name> | grep -i oomkilled

# Immediate fix: Increase memory
kubectl edit deployment crystalshards-api -n crystalshards
# Increase memory limits

# Restart deployment
kubectl rollout restart deployment/crystalshards-api -n crystalshards
```

### Application Error

```bash
# Check application logs for stack trace
kubectl logs -n crystalshards <pod-name> --previous | tail -100

# Rollback to previous version
kubectl rollout undo deployment/crystalshards-api -n crystalshards
```

### Configuration Error

```bash
# Check environment variables
kubectl describe pod -n crystalshards <pod-name> | grep -A 20 Environment

# Verify secrets exist
kubectl get secret -n crystalshards crystalshards-secrets

# Check secret values (be careful)
kubectl get secret -n crystalshards crystalshards-secrets -o yaml
```

### Failed Health Checks

```bash
# Check liveness/readiness probes
kubectl describe deployment -n crystalshards crystalshards-api | grep -A 5 Liveness

# Test health endpoint manually
kubectl exec -n crystalshards <pod-name> -- wget -qO- http://localhost:3000/health

# Adjust probe timeouts if needed
kubectl edit deployment crystalshards-api -n crystalshards
```

## Prevention

- Set appropriate resource limits
- Implement proper health checks
- Test deployments in staging
- Monitor memory usage trends
- Use liveness and readiness probes correctly
- Implement graceful shutdown

## Related Runbooks
- [Application Unavailable](app-unavailable.md)
- [Pod Not Ready](pod-not-ready.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
