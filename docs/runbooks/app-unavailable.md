# Runbook: Application Unavailable

## Severity: P0 - CRITICAL

## Alert Name
- Prometheus alert: `ApplicationDown`

## Symptoms
- Application health check returning non-200 status
- Users receiving "Service Unavailable" (503) errors
- Cannot access application via domain
- All requests timing out

## Impact
- **CRITICAL**: Service completely unavailable
- All users affected
- Zero functionality available
- Revenue loss for paid features
- Reputation damage

## Investigation

### 1. Initial Triage (2 minutes)

- [ ] Confirm outage via external monitoring
- [ ] Check all 4 applications or just one?
- [ ] Check Grafana dashboards
- [ ] Review recent changes (last 30 minutes)

```bash
# Quick health check from external
curl -I https://crystalshards.org/health
curl -I https://crystaldocs.org/health
curl -I https://crystalgigs.org/health
curl -I https://crystalbits.org/health

# Check recent deployments
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | head -20
```

### 2. Check Pod Status (1 minute)

```bash
# Check all application pods
kubectl get pods -n crystalshards
kubectl get pods -n crystaldocs
kubectl get pods -n crystalgigs
kubectl get pods -n crystalbits

# Quick status summary
kubectl get pods --all-namespaces | grep -E "crystalshards|crystaldocs|crystalgigs|crystalbits"

# Check pod events
kubectl describe pods -n crystalshards -l app=crystalshards-api | grep -A 10 Events
```

### 3. Check Pod Logs (2 minutes)

```bash
# Get logs from affected application
kubectl logs -n crystalshards -l app=crystalshards-api --tail=50

# Check for specific errors
kubectl logs -n crystalshards -l app=crystalshards-api --tail=200 | \
  grep -i -E "error|fatal|panic|exception"

# Check all containers in pod
kubectl logs -n crystalshards deployment/crystalshards-api --all-containers=true --tail=50
```

### 4. Check Service and Ingress (1 minute)

```bash
# Check service endpoints
kubectl get svc -n crystalshards
kubectl describe svc crystalshards -n crystalshards

# Check if service has endpoints
kubectl get endpoints -n crystalshards

# Check ingress configuration
kubectl get httproute -n crystalshards
kubectl describe httproute crystalshards-route -n crystalshards

# Check Envoy Gateway status
kubectl get gateway -n infrastructure
```

### 5. Check Dependencies (2 minutes)

```bash
# Check PostgreSQL status
kubectl get cluster -n crystalshards
kubectl get pods -n crystalshards | grep postgres

# Check Redis status
kubectl get pods -n infrastructure | grep redis

# Check MinIO status
kubectl get pods -n infrastructure | grep minio
```

### 6. Root Cause Analysis

Common causes (in order of frequency):
1. Pod crash loop (OOMKilled, application error)
2. Recent deployment broke application
3. Database connection failure
4. Redis unavailable
5. Kubernetes node issues
6. Ingress/Gateway misconfiguration
7. Certificate expiry
8. Resource quota exceeded
9. Image pull failure
10. Network policy blocking traffic

## Resolution

### Critical Path: Get Service Back Online (Target: < 5 minutes)

#### Scenario 1: Pods CrashLooping

```bash
# Check crash reason
kubectl describe pod -n crystalshards -l app=crystalshards-api | grep -A 5 "Last State"

# If OOMKilled - temporarily increase memory
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=0
kubectl edit deployment crystalshards-api -n crystalshards
# Increase memory limit to 2Gi or 4Gi
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=3

# If application error - rollback deployment
kubectl rollout undo deployment/crystalshards-api -n crystalshards
kubectl rollout status deployment/crystalshards-api -n crystalshards
```

#### Scenario 2: Recent Bad Deployment

```bash
# Immediate rollback
kubectl rollout undo deployment/crystalshards-api -n crystalshards

# Monitor rollback
kubectl rollout status deployment/crystalshards-api -n crystalshards

# Verify pods are running
kubectl get pods -n crystalshards -l app=crystalshards-api

# Test health endpoint
curl https://crystalshards.org/health
```

#### Scenario 3: Database Connection Failure

```bash
# Check PostgreSQL cluster
kubectl get cluster -n crystalshards -o yaml

# Check if database is accepting connections
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT 1;"

# If database is down, see postgres-unavailable.md
# If database is up, restart application pods
kubectl rollout restart deployment/crystalshards-api -n crystalshards
```

#### Scenario 4: No Healthy Pods

```bash
# Check pod status
kubectl get pods -n crystalshards -l app=crystalshards-api

# If no pods exist, scale up
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=3

# If pods are pending, check node resources
kubectl describe pods -n crystalshards -l app=crystalshards-api | grep -A 10 Events

# If ImagePullBackOff, check image exists
kubectl describe pods -n crystalshards -l app=crystalshards-api | grep Image:
```

#### Scenario 5: Ingress/Gateway Issues

```bash
# Check Gateway status
kubectl get gateway -n infrastructure
kubectl describe gateway main-gateway -n infrastructure

# Check HTTPRoute
kubectl get httproute -n crystalshards
kubectl describe httproute crystalshards-route -n crystalshards

# Check Gateway pods
kubectl get pods -n envoy-gateway-system

# Restart Gateway if needed
kubectl rollout restart deployment/envoy-gateway -n envoy-gateway-system
```

#### Scenario 6: Certificate Issues

```bash
# Check certificate status
kubectl get certificate -n crystalshards

# Check certificate details
kubectl describe certificate crystalshards-tls -n crystalshards

# If expired or invalid, delete and recreate
kubectl delete certificate crystalshards-tls -n crystalshards
# cert-manager will recreate automatically

# Force cert-manager to renew
kubectl delete certificaterequest -n crystalshards --all
```

### Verification (1 minute)

```bash
# Test health endpoint
curl -v https://crystalshards.org/health

# Test from inside cluster
kubectl run curl-test --image=curlimages/curl -i --rm --restart=Never -- \
  curl -v http://crystalshards.crystalshards.svc.cluster.local:3000/health

# Check pod logs for successful requests
kubectl logs -n crystalshards -l app=crystalshards-api --tail=20

# Verify in Grafana
# Check "Lucky Applications Overview" dashboard
```

## Commands Reference

### Emergency Rollback

```bash
# View rollout history
kubectl rollout history deployment/crystalshards-api -n crystalshards

# Rollback to previous version
kubectl rollout undo deployment/crystalshards-api -n crystalshards

# Rollback to specific revision
kubectl rollout undo deployment/crystalshards-api -n crystalshards --to-revision=5

# Pause rollout if needed
kubectl rollout pause deployment/crystalshards-api -n crystalshards
```

### Force Pod Restart

```bash
# Delete all pods (deployment will recreate)
kubectl delete pods -n crystalshards -l app=crystalshards-api

# Rolling restart
kubectl rollout restart deployment/crystalshards-api -n crystalshards

# Force recreation
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=0
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=3
```

### Debug Pod Access

```bash
# Exec into running pod
kubectl exec -it -n crystalshards deployment/crystalshards-api -- sh

# Run debug container in same namespace
kubectl run debug --image=nicolaka/netshoot -it --rm --restart=Never -n crystalshards -- bash

# Port forward for local testing
kubectl port-forward -n crystalshards deployment/crystalshards-api 3000:3000
```

### Service Troubleshooting

```bash
# Check service endpoints
kubectl get endpoints -n crystalshards

# Describe service
kubectl describe svc crystalshards -n crystalshards

# Test service from another pod
kubectl run curl-test --image=curlimages/curl -i --rm --restart=Never -- \
  curl -v http://crystalshards.crystalshards.svc.cluster.local:3000/health
```

## Prevention

1. **Deployment Safety**:
   - Implement blue-green deployments
   - Use canary releases for risky changes
   - Automated rollback on health check failure
   - Require manual approval for production deploys

2. **Better Health Checks**:
   - Implement comprehensive health endpoint
   - Check database connectivity
   - Check Redis connectivity
   - Check critical dependencies
   - Add startup probe for slow-starting apps

3. **Resource Management**:
   - Set appropriate resource limits
   - Implement pod disruption budgets
   - Use Horizontal Pod Autoscaler
   - Monitor resource usage trends

4. **Monitoring & Alerting**:
   - Alert on pod crash loops
   - Alert on high restart counts
   - Monitor deployment success rate
   - Track mean time to recovery (MTTR)

5. **Infrastructure Resilience**:
   - Run multiple replicas (minimum 3)
   - Use pod anti-affinity rules
   - Implement circuit breakers
   - Test failover scenarios regularly

## Communication Template

### Initial Notification (within 2 minutes)

```
[P0] [CrystalShards] Service Unavailable

Impact: CrystalShards.org is completely down
Status: Investigating - checking pod status
ETA: 5 minutes for initial assessment
Team: Primary on-call responding
Updates: Will update every 5 minutes
```

### Progress Update (every 5 minutes)

```
[P0] [CrystalShards] Service Unavailable - Update

Root Cause: Recent deployment caused pod crash loop
Action: Rolling back to previous version
Progress: Rollback in progress, 2/3 pods healthy
ETA: Service recovery expected in 2 minutes
```

### Resolution Notification

```
[RESOLVED] [CrystalShards] Service Unavailable

Issue: Deployment v123 introduced memory leak causing OOMKill
Root Cause: Missing memory limit in new feature code
Resolution: Rolled back to v122, service restored
Duration: 8 minutes total downtime
Prevention: Adding memory profiling to CI pipeline
PIR: Will publish post-incident review within 24 hours
```

## Post-Incident

- [ ] **REQUIRED**: Create Post-Incident Review (PIR)
- [ ] Update incident log with exact timeline
- [ ] Identify root cause with evidence
- [ ] Create tickets for preventive measures
- [ ] Update monitoring/alerting if gaps found
- [ ] Share learnings with team
- [ ] Update runbook with any new steps
- [ ] Schedule PIR meeting within 48 hours

## Related Runbooks
- [Pod Crash Loop](pod-crash-loop.md)
- [PostgreSQL Unavailable](postgres-unavailable.md)
- [Redis Unavailable](redis-unavailable.md)
- [Ingress Issues](ingress-issues.md)
- [Certificate Expiry](certificate-expiry.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
