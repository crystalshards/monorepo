# Runbook: Pod Not Ready

## Severity: P2 - MEDIUM

## Alert Name
- Prometheus alert: `PodNotReady`

## Symptoms
- Pod in Running state but not Ready
- Readiness probe failing
- Pod not receiving traffic
- Service not routing to pod

## Impact
- Reduced capacity
- Some requests may fail
- Risk of full outage if all pods fail

## Investigation

```bash
# Check pod readiness
kubectl get pods -n crystalshards -l app=crystalshards-api

# Describe pod
kubectl describe pod -n crystalshards <pod-name> | grep -A 20 Conditions

# Check readiness probe
kubectl describe pod -n crystalshards <pod-name> | grep -A 5 Readiness

# Check logs
kubectl logs -n crystalshards <pod-name> --tail=50
```

## Resolution

```bash
# Test readiness endpoint
kubectl exec -n crystalshards <pod-name> -- wget -qO- http://localhost:3000/health

# If endpoint works but probe fails, adjust probe settings
kubectl edit deployment crystalshards-api -n crystalshards
# Increase initialDelaySeconds or periodSeconds

# If application not starting, check dependencies
kubectl exec -n crystalshards <pod-name> -- env | grep DATABASE_URL

# Restart pod if stuck
kubectl delete pod -n crystalshards <pod-name>
```

## Prevention

- Set appropriate initialDelaySeconds
- Monitor startup times
- Test readiness endpoint in CI
- Ensure dependencies available before probe starts

## Related Runbooks
- [Pod Crash Loop](pod-crash-loop.md)
- [Application Unavailable](app-unavailable.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
