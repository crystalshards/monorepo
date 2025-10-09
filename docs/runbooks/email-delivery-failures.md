# Runbook: Email Delivery Failures

## Severity: P3 - LOW

## Symptoms
- Newsletter emails not being sent
- Email confirmation not received by users
- SMTP errors in logs
- High bounce rate

## Impact
- Subscribers not receiving newsletters
- New subscribers cannot confirm email
- Poor user experience
- Reduced engagement

## Investigation

```bash
# Check application logs for email errors
kubectl logs -n crystalbits -l app=crystalbits-api --tail=200 | grep -i "email\|smtp\|mail"

# Check email service configuration
kubectl get secret -n crystalbits crystalbits-secrets -o yaml | grep -i smtp

# Test SMTP connectivity
kubectl exec -n crystalbits deployment/crystalbits-api -- \
  sh -c 'echo "test" | telnet smtp.example.com 587'

# Check for queued emails
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli LLEN email:queue
```

## Resolution

### SMTP Configuration

```bash
# Verify SMTP settings in secret
kubectl describe secret crystalbits-secrets -n crystalbits

# Update if incorrect
kubectl create secret generic crystalbits-secrets -n crystalbits \
  --from-literal=SMTP_HOST=smtp.sendgrid.net \
  --from-literal=SMTP_PORT=587 \
  --from-literal=SMTP_USER=apikey \
  --from-literal=SMTP_PASSWORD=SG.xxx \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart application
kubectl rollout restart deployment/crystalbits-api -n crystalbits
```

### Email Service Provider Issues

```bash
# Check email service dashboard for issues
# (SendGrid, Mailgun, AWS SES, etc.)

# Verify sending quota not exceeded
# Check bounce rate and reputation
```

### SPF/DKIM Configuration

```bash
# Verify DNS records
nslookup -type=TXT crystalbits.org
nslookup -type=TXT _dmarc.crystalbits.org

# Check SPF includes email provider
# Example: v=spf1 include:sendgrid.net ~all
```

## Prevention

- Monitor email delivery rate
- Track bounces and complaints
- Warm up new IP addresses
- Implement retry logic for transient failures
- Regular DNS record validation

## Related Runbooks
- [Application High Error Rate](app-high-error-rate.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
