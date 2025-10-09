# Runbook: Stripe Payment Failures

## Severity: P2 - MEDIUM

## Symptoms
- Job posting payments failing
- Stripe API errors in logs
- Users reporting payment issues
- Webhook delivery failures

## Impact
- Cannot post paid jobs on CrystalGigs
- Revenue loss
- User frustration
- Reputation damage

## Investigation

```bash
# Check application logs for Stripe errors
kubectl logs -n crystalgigs -l app=crystalgigs-api --tail=200 | grep -i stripe

# Check Stripe environment variables
kubectl get secret -n crystalgigs crystalgigs-secrets -o jsonpath='{.data.STRIPE_SECRET_KEY}' | base64 -d | head -c 10

# Test Stripe API connectivity
kubectl exec -n crystalgigs deployment/crystalgigs-api -- \
  curl -u sk_test_xxx: https://api.stripe.com/v1/customers/cus_test

# Check webhook endpoint
kubectl exec -n crystalgigs deployment/crystalgigs-api -- \
  wget -qO- http://localhost:3000/webhooks/stripe
```

## Resolution

### API Key Issues

```bash
# Verify API keys are correct
# Log into Stripe Dashboard: https://dashboard.stripe.com/apikeys

# Update secret if wrong
kubectl create secret generic crystalgigs-secrets -n crystalgigs \
  --from-literal=STRIPE_SECRET_KEY=sk_live_xxx \
  --from-literal=STRIPE_PUBLISHABLE_KEY=pk_live_xxx \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart application
kubectl rollout restart deployment/crystalgigs-api -n crystalgigs
```

### Webhook Failures

```bash
# Check Stripe webhook configuration
# Dashboard > Developers > Webhooks
# Verify endpoint: https://crystalgigs.org/webhooks/stripe

# Check webhook secret
kubectl get secret -n crystalgigs crystalgigs-secrets -o jsonpath='{.data.STRIPE_WEBHOOK_SECRET}'

# Retry failed webhook from Stripe Dashboard
```

### Network Issues

```bash
# Test external connectivity
kubectl exec -n crystalgigs deployment/crystalgigs-api -- \
  curl -I https://api.stripe.com

# Check egress rules if blocked
```

## Prevention

- Monitor Stripe API response times
- Alert on payment failure rate > 5%
- Test webhook delivery regularly
- Rotate API keys securely
- Implement idempotent payment processing

## Related Runbooks
- [Application High Error Rate](app-high-error-rate.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
