# CrystalShards Operational Runbooks

## Overview

This directory contains operational runbooks for responding to common production incidents in the CrystalShards platform. Each runbook provides step-by-step investigation and resolution procedures for specific alert conditions.

## Quick Access by Severity

### P0 - Critical (Service Down)
- [ApplicationDown](app-unavailable.md)
- [PostgreSQLDown](postgres-unavailable.md)
- [RedisDown](redis-unavailable.md)
- [MinIODown](minio-unavailable.md)
- [PodCrashLooping](pod-crash-loop.md)

### P1 - High (Degraded Service)
- [HighErrorRate](app-high-error-rate.md)
- [PostgreSQLConnectionExhaustion](postgres-high-connections.md)
- [WorkerQueueBacklog](worker-queue-backlog.md)

### P2 - Medium (Performance Issues)
- [HighLatency](app-high-latency.md)
- [RedisHighMemoryUsage](redis-high-memory.md)
- [PostgreSQLHighReplicationLag](postgres-replication-lag.md)

### P3 - Low (Warnings)
- [RedisLowHitRate](redis-low-hit-rate.md)
- [PodNotReady](pod-not-ready.md)
- [CertificateExpiry](certificate-expiry.md)

## Runbook Index

### Application Incidents
- [High Error Rate](app-high-error-rate.md) - 5xx errors exceeding threshold
- [High Latency](app-high-latency.md) - Response times degraded
- [Application Unavailable](app-unavailable.md) - Service down or unreachable

### Database Incidents
- [PostgreSQL High Connections](postgres-high-connections.md) - Connection pool exhaustion
- [PostgreSQL Replication Lag](postgres-replication-lag.md) - Replica falling behind
- [PostgreSQL Unavailable](postgres-unavailable.md) - Database down

### Cache & Queue Incidents
- [Redis High Memory](redis-high-memory.md) - Memory usage critical
- [Redis Low Hit Rate](redis-low-hit-rate.md) - Cache performance degraded
- [Redis Unavailable](redis-unavailable.md) - Cache unavailable

### Storage Incidents
- [MinIO High Error Rate](minio-high-error-rate.md) - Object storage errors
- [MinIO Unavailable](minio-unavailable.md) - Object storage down

### Infrastructure Incidents
- [Pod Crash Loop](pod-crash-loop.md) - Pod repeatedly crashing
- [Pod Not Ready](pod-not-ready.md) - Pod failing readiness checks
- [Ingress Issues](ingress-issues.md) - Domain access problems
- [Certificate Expiry](certificate-expiry.md) - SSL certificate issues

### Worker & Job Incidents
- [Worker Queue Backlog](worker-queue-backlog.md) - Background jobs piling up
- [Documentation Build Failures](doc-build-failures.md) - Docs not building

### External Service Incidents
- [Stripe Payment Failures](stripe-payment-failures.md) - Payment processing issues
- [Email Delivery Failures](email-delivery-failures.md) - Newsletter emails failing

## How to Use These Runbooks

### During an Incident

1. **Identify the Alert**: Find the matching runbook by alert name
2. **Check Severity**: Understand the impact level (P0-P3)
3. **Follow Investigation Steps**: Execute each step in order
4. **Implement Resolution**: Apply fixes as documented
5. **Verify Recovery**: Confirm the issue is resolved
6. **Document**: Add notes to the incident log

### After an Incident

1. **Update Runbook**: Add any learnings or new steps
2. **Create Post-Mortem**: For P0/P1 incidents
3. **Implement Preventive Measures**: Fix root causes
4. **Share Knowledge**: Brief team on findings

## Essential Resources

### Quick Reference
- [Quick Reference Guide](QUICK_REFERENCE.md) - Common commands and access patterns

### On-Call Information
- [On-Call Guide](ON_CALL_GUIDE.md) - On-call responsibilities and procedures

### Cluster Access

**GKE Cluster**: crystalshards-production (us-central1)

```bash
# Configure kubectl context
gcloud container clusters get-credentials crystalshards-production \
  --region us-central1 \
  --project <project-id>

# Verify access
kubectl get nodes
```

### Monitoring Access

**Grafana**: https://grafana.crystalshards.org (or via port-forward)
**Prometheus**: http://prometheus-operated.monitoring.svc:9090 (cluster-internal)

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
```

### Application Namespaces

- `crystalshards` - Main package registry
- `crystaldocs` - Documentation hosting
- `crystalgigs` - Job board
- `crystalbits` - Blog platform
- `infrastructure` - Shared services (Redis, MinIO, PostgreSQL operators)
- `monitoring` - Prometheus, Grafana

## Escalation Procedures

### Severity Levels

**P0 - Critical**
- Service completely down
- Data loss occurring
- Security breach
- **Response Time**: Immediate
- **Escalation**: Notify all on-call immediately

**P1 - High**
- Service degraded for users
- Risk of service outage
- **Response Time**: 15 minutes
- **Escalation**: Notify primary on-call

**P2 - Medium**
- Performance degraded
- Non-critical feature unavailable
- **Response Time**: 1 hour
- **Escalation**: Standard on-call response

**P3 - Low**
- Warning conditions
- No user impact yet
- **Response Time**: 4 hours
- **Escalation**: Can wait for business hours

### On-Call Escalation Path

1. **L1 - Primary On-Call Engineer**: First responder
2. **L2 - Secondary On-Call Engineer**: Escalate after 15 minutes if stuck
3. **L3 - Platform Team Lead**: Escalate for P0 or if L2 unavailable
4. **L4 - CTO/Engineering Director**: Escalate only for critical business impact

## Communication Templates

### Incident Notification

```
[SEVERITY] [COMPONENT] Brief description

Impact: What users are experiencing
Status: Investigating / Mitigating / Resolved
ETA: Expected resolution time
Updates: Link to status page or incident channel
```

Example:
```
[P1] [CrystalShards] High error rate on shard publishing

Impact: Users unable to publish new shards
Status: Investigating - checking database connections
ETA: 30 minutes
Updates: #incident-2025-10-09 Slack channel
```

### Resolution Notification

```
[RESOLVED] [COMPONENT] Brief description

Issue: What was wrong
Root Cause: Why it happened
Resolution: What was done
Prevention: Steps to prevent recurrence
Duration: Total incident time
```

## Incident Log

All incidents should be logged in the platform's incident tracking system with:

- Incident ID
- Start/end time
- Alert name
- Severity
- Affected services
- Actions taken
- Root cause
- Preventive measures

## Post-Incident Reviews (PIR)

Required for:
- All P0 incidents
- All P1 incidents lasting > 1 hour
- Any incident with data loss
- Any incident with security implications

PIR should include:
- Timeline of events
- Root cause analysis
- Impact assessment
- Action items with owners
- Documentation updates needed

## Contributing to Runbooks

Runbooks are living documents. After using a runbook:

1. Add any missing steps you discovered
2. Update commands if they've changed
3. Add new troubleshooting tips
4. Fix any errors or outdated information
5. Commit changes with clear description

## Support Contacts

### Internal Teams
- Platform Team: #platform-team
- Security Team: #security
- Database Team: #database

### External Vendors
- GCP Support: Via Cloud Console
- Stripe Support: dashboard.stripe.com/support
- Email Provider: (Configured service dashboard)

## Additional Documentation

- [Deployment Runbook](../terraform/DEPLOYMENT_RUNBOOK.md)
- [Architecture Documentation](../README.md)
- [Rate Limiting Guide](../RATE_LIMITING.md)
- [API Documentation](../api/)

---

Last Updated: 2025-10-09
