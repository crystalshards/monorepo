# Runbook: Certificate Expiry

## Severity: P1 - HIGH

## Symptoms
- SSL certificate expired or expiring soon
- Browser showing certificate warnings
- cert-manager renewal failing
- HTTPS connections failing

## Impact
- Users see security warnings
- Cannot access site over HTTPS
- Loss of trust
- Search engine penalties

## Investigation

```bash
# Check all certificates
kubectl get certificate --all-namespaces

# Check specific certificate
kubectl describe certificate crystalshards-tls -n crystalshards

# Check certificate expiry
kubectl get certificate crystalshards-tls -n crystalshards -o jsonpath='{.status.notAfter}'

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# Check Let's Encrypt rate limits
curl https://crystalshards.org 2>&1 | openssl s_client -connect crystalshards.org:443 -servername crystalshards.org | openssl x509 -noout -dates
```

## Resolution

```bash
# Force certificate renewal
kubectl delete certificate crystalshards-tls -n crystalshards
kubectl delete secret crystalshards-tls-secret -n crystalshards
# cert-manager will recreate automatically

# Check certificate request
kubectl get certificaterequest -n crystalshards

# If stuck, check challenge
kubectl get challenge -n crystalshards
kubectl describe challenge -n crystalshards <challenge-name>

# Restart cert-manager if needed
kubectl rollout restart deployment/cert-manager -n cert-manager

# Verify new certificate
kubectl get certificate crystalshards-tls -n crystalshards -o yaml
```

## Prevention

- Monitor certificate expiry (alert 30 days before)
- Ensure cert-manager healthy
- Regular renewal testing
- Backup certificate secrets
- Monitor Let's Encrypt rate limits

## Related Runbooks
- [Ingress Issues](ingress-issues.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
