# Runbook: Ingress Issues

## Severity: P1 - HIGH

## Symptoms
- Cannot access applications via domain
- DNS resolves but connection fails
- 502 Bad Gateway or 503 Service Unavailable
- SSL/TLS errors

## Impact
- Applications inaccessible from internet
- Users cannot reach service
- All external traffic blocked

## Investigation

```bash
# Check Gateway status
kubectl get gateway -n infrastructure

# Check HTTPRoutes
kubectl get httproute --all-namespaces

# Check Gateway pods
kubectl get pods -n envoy-gateway-system

# Check load balancer
kubectl get svc -n infrastructure | grep gateway

# Test DNS resolution
nslookup crystalshards.org

# Test from inside cluster
kubectl run curl-test --image=curlimages/curl -i --rm --restart=Never -- \
  curl -v http://crystalshards.crystalshards.svc.cluster.local:3000/health
```

## Resolution

```bash
# Restart Gateway
kubectl rollout restart deployment/envoy-gateway -n envoy-gateway-system

# Check external-dns logs
kubectl logs -n infrastructure -l app=external-dns --tail=100

# Verify HTTPRoute configuration
kubectl describe httproute crystalshards-route -n crystalshards

# Force DNS update
kubectl annotate httproute crystalshards-route -n crystalshards \
  external-dns.alpha.kubernetes.io/force-update="$(date +%s)" --overwrite

# Check Gateway IP
kubectl get gateway main-gateway -n infrastructure -o jsonpath='{.status.addresses[0].value}'
```

## Prevention

- Monitor Gateway health
- Test DNS propagation after changes
- Use health checks on Gateway
- Regular failover testing

## Related Runbooks
- [Certificate Expiry](certificate-expiry.md)
- [Application Unavailable](app-unavailable.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
