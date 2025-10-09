# On-Call Guide for CrystalShards Platform

## Overview

This guide covers on-call responsibilities, procedures, and best practices for CrystalShards platform engineers.

## Table of Contents

- [On-Call Responsibilities](#on-call-responsibilities)
- [Alert Notification Setup](#alert-notification-setup)
- [Severity Levels](#severity-levels)
- [Escalation Procedures](#escalation-procedures)
- [Incident Response Process](#incident-response-process)
- [Communication Guidelines](#communication-guidelines)
- [Post-Incident Procedures](#post-incident-procedures)
- [On-Call Checklist](#on-call-checklist)
- [Tools and Access](#tools-and-access)

## On-Call Responsibilities

### Primary On-Call (L1)

- **Monitoring**: Watch for alerts 24/7 during on-call shift
- **Response Time**: Acknowledge alerts within 5 minutes
- **Initial Triage**: Assess severity and impact
- **Investigation**: Follow runbooks to diagnose issues
- **Communication**: Update stakeholders on incident status
- **Resolution**: Fix issues or escalate if needed
- **Documentation**: Log all actions taken

### Secondary On-Call (L2)

- **Backup**: Available if primary cannot respond
- **Escalation**: Assist primary when issues are complex
- **Response Time**: Available within 15 minutes of escalation
- **Coverage**: Cover for primary during breaks (meal, personal)

### On-Call Schedule

- **Shift Duration**: 1 week (Monday 9 AM to Monday 9 AM)
- **Handoff Time**: Mondays at 9 AM local time
- **Rotation**: Engineers rotate weekly
- **Schedule Tool**: PagerDuty / Opsgenie (TBD)

## Alert Notification Setup

### Notification Channels

1. **PagerDuty/Opsgenie**: Primary alerting (phone, SMS, push)
2. **Slack**: #incidents channel for team visibility
3. **Email**: Backup notification method

### Alert Routing

- **P0 (Critical)**: Phone call + SMS + Push + Slack
- **P1 (High)**: SMS + Push + Slack
- **P2 (Medium)**: Push + Slack
- **P3 (Low)**: Slack only

### Alert Sources

- **Prometheus**: Application and infrastructure metrics
- **Loki**: Log-based alerts (future)
- **External Monitoring**: Uptime checks (Pingdom/DataDog)
- **User Reports**: Support ticket system

## Severity Levels

### P0 - Critical (Service Down)

**Response Time**: Immediate (< 5 minutes)
**Resolution Target**: < 15 minutes

**Examples**:
- CrystalShards.org completely unavailable
- PostgreSQL cluster down across all apps
- Data loss occurring
- Security breach detected

**Actions**:
1. Acknowledge alert immediately
2. Post in #incidents Slack channel
3. Start investigation using runbooks
4. Notify L2 and leadership immediately
5. Update status every 5 minutes
6. Declare major incident if >15 minutes

### P1 - High (Degraded Service)

**Response Time**: < 15 minutes
**Resolution Target**: < 1 hour

**Examples**:
- High error rate (>5%)
- Database connection pool exhausted
- One application unavailable
- Payment processing failures

**Actions**:
1. Acknowledge alert within 15 minutes
2. Post in #incidents channel
3. Follow runbook procedures
4. Escalate to L2 if stuck after 30 minutes
5. Update status every 15 minutes

### P2 - Medium (Performance Issues)

**Response Time**: < 1 hour
**Resolution Target**: < 4 hours

**Examples**:
- High latency (P95 > 1s)
- Redis memory usage high
- Worker queue backlog
- Non-critical feature unavailable

**Actions**:
1. Acknowledge within 1 hour
2. Post in #incidents if user-impacting
3. Investigate during business hours if after-hours
4. Document findings and create ticket for fix

### P3 - Low (Warnings)

**Response Time**: < 4 hours
**Resolution Target**: Next business day

**Examples**:
- Low cache hit rate
- Certificate expiring in 30 days
- Pod not ready (but others healthy)
- Disk usage at 70%

**Actions**:
1. Review during business hours
2. Create ticket for tracking
3. Schedule fix during normal maintenance
4. Update monitoring if false positive

## Escalation Procedures

### Escalation Path

```
L1 (Primary On-Call)
    ↓ (15 min for P0, 30 min for P1, stuck on issue)
L2 (Secondary On-Call)
    ↓ (If multiple services affected or >30 min)
L3 (Platform Team Lead / Senior Engineer)
    ↓ (If critical business impact or >1 hour)
L4 (CTO / Engineering Director)
```

### When to Escalate

**Escalate Immediately**:
- P0 incident with no clear resolution path
- Multiple cascading failures
- Security incident detected
- Data corruption or loss
- Unable to access critical systems

**Escalate After Timeboxing**:
- P0: After 15 minutes if no progress
- P1: After 30 minutes if stuck
- P2: If becomes user-impacting

**Escalate for Expertise**:
- Database-specific issues → DBA team
- Security concerns → Security team
- GCP infrastructure → Platform team lead
- Application bugs → Development team

### Escalation Contact Info

Keep this information current and accessible:

- **L2 On-Call**: [Phone/Slack]
- **Platform Team Lead**: [Phone/Slack]
- **Security Team**: [Phone/Slack/Email]
- **CTO**: [Phone] (P0 only)
- **GCP Support**: Via Cloud Console (for infrastructure)

## Incident Response Process

### 1. Alert Received (0-2 minutes)

- [ ] Acknowledge alert in PagerDuty/Opsgenie
- [ ] Check Grafana dashboards for context
- [ ] Post in #incidents: "Investigating [alert name]"
- [ ] Determine severity level

### 2. Initial Triage (2-5 minutes)

- [ ] Identify affected services/users
- [ ] Check recent changes (deployments, configs)
- [ ] Find matching runbook
- [ ] Assess if escalation needed

### 3. Investigation (5-15 minutes)

- [ ] Follow runbook procedures
- [ ] Check application logs
- [ ] Review metrics in Grafana
- [ ] Query Loki for error patterns
- [ ] Test affected functionality

### 4. Mitigation (Ongoing)

- [ ] Apply immediate fixes (rollback, restart, scale)
- [ ] Verify mitigation working
- [ ] Update #incidents with progress
- [ ] Continue until issue resolved

### 5. Resolution (Final)

- [ ] Verify all symptoms cleared
- [ ] Monitor for 15 minutes to ensure stability
- [ ] Post resolution in #incidents
- [ ] Mark incident as resolved in PagerDuty
- [ ] Begin post-incident procedures

## Communication Guidelines

### Incident Notifications

**Initial Post** (within 2 minutes):
```
[P1] [CrystalShards] High Error Rate Detected

Impact: 10% of shard publishing requests failing
Status: Investigating - checking database connections
ETA: 15 minutes for initial assessment
Responder: @john.doe
Updates: Will update every 5 minutes
```

**Progress Updates** (every 5-15 minutes):
```
[P1] [CrystalShards] High Error Rate - UPDATE

Root Cause: Database connection pool exhausted (spike in traffic)
Action: Scaled app replicas 3→5, restarting connection pool
Progress: Error rate decreasing (10% → 3%)
ETA: Full resolution in 5 minutes
```

**Resolution Post**:
```
[RESOLVED] [P1] [CrystalShards] High Error Rate

Issue: Traffic spike exhausted database connection pool
Root Cause: Insufficient pool size for current load
Resolution: Scaled to 5 replicas, adjusted pool configuration
Impact: 8 minutes of degraded service (10% error rate)
Prevention: Updated pool size config, added scaling alert
PIR: Will create post-incident review by EOD
```

### Status Page Updates

For P0/P1 incidents affecting users:
1. Update status page: status.crystalshards.org (TBD)
2. Post brief updates every 15 minutes
3. Update resolution and timeline

### User Communication

- Keep updates brief and non-technical
- Focus on impact and ETA, not internal details
- Use status page for major incidents
- Follow up after resolution if data affected

## Post-Incident Procedures

### Immediate (Within 1 hour)

- [ ] Complete incident log entry
- [ ] Document timeline and actions taken
- [ ] Close alert in PagerDuty
- [ ] Thank team members who helped
- [ ] Get rest if late-night incident

### Short-term (Within 24 hours)

For P0/P1 incidents:
- [ ] Create Post-Incident Review (PIR) document
- [ ] Identify root cause with evidence
- [ ] List action items with owners
- [ ] Schedule PIR meeting (within 48 hours)
- [ ] Update relevant runbooks

### Long-term (Within 1 week)

- [ ] Complete all PIR action items
- [ ] Implement preventive measures
- [ ] Update monitoring/alerting if needed
- [ ] Share learnings in team meeting
- [ ] Update documentation

## On-Call Checklist

### Start of Shift

- [ ] Check handoff notes from previous on-call
- [ ] Verify access to all tools (kubectl, GCP, Grafana)
- [ ] Test notification channels (PagerDuty/Opsgenie)
- [ ] Review open incidents from previous shift
- [ ] Check system health in Grafana
- [ ] Ensure laptop charged and accessible
- [ ] Review recent changes/deployments
- [ ] Confirm secondary on-call contact

### During Shift

- [ ] Respond to alerts promptly
- [ ] Keep Slack #incidents channel updated
- [ ] Document all actions in incident log
- [ ] Escalate when appropriate
- [ ] Take breaks but remain reachable
- [ ] Handoff to secondary for meals/personal time

### End of Shift

- [ ] Document any ongoing issues
- [ ] Update handoff notes for next on-call
- [ ] Complete any pending PIRs
- [ ] Close all resolved incidents
- [ ] Schedule follow-up work if needed
- [ ] Confirm next on-call received handoff

## Tools and Access

### Required Access

- **GKE Cluster**: kubectl access to crystalshards-production
- **GCP Console**: Viewer role for monitoring
- **Grafana**: Admin access for dashboards
- **Prometheus**: Query access for metrics
- **Loki**: Query access for logs
- **GitHub**: Read access to repository
- **PagerDuty/Opsgenie**: Responder role
- **Slack**: Access to #incidents channel

### Essential Tools

**On Laptop**:
- kubectl (configured with cluster access)
- gcloud CLI
- gh (GitHub CLI)
- curl/wget
- jq (JSON parsing)

**Bookmarks**:
- Grafana: https://grafana.crystalshards.org
- Status Page: https://status.crystalshards.org (TBD)
- Runbooks: https://github.com/crystalshards/monorepo/docs/runbooks
- GKE Console: https://console.cloud.google.com/kubernetes
- PagerDuty: https://crystalshards.pagerduty.com (TBD)

**Shortcuts**:
- Quick Reference Guide: [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
- Runbooks Index: [README.md](README.md)
- Deployment Runbook: [DEPLOYMENT_RUNBOOK.md](../../terraform/DEPLOYMENT_RUNBOOK.md)

## Best Practices

### During Incidents

1. **Stay Calm**: Clear thinking is critical
2. **Follow Runbooks**: Don't improvise unless necessary
3. **Document Everything**: Actions, timestamps, observations
4. **Communicate Frequently**: Over-communicate rather than under
5. **Ask for Help**: Escalate early if unsure
6. **Focus on Mitigation**: Fix first, understand later
7. **Verify Fixes**: Don't assume, test and confirm

### Avoiding Burnout

1. **Set Boundaries**: Use secondary for breaks
2. **Handoff Properly**: Don't extend shift unnecessarily
3. **Sleep**: Get rest, especially after late-night incidents
4. **Escalate**: Don't be a hero, ask for help
5. **Decompress**: Take time after major incidents
6. **Feedback**: Share concerns about on-call load

### Learning and Improvement

1. **Update Runbooks**: Add learnings after each incident
2. **Share Knowledge**: Document new procedures
3. **Review Alerts**: Tune noisy or unclear alerts
4. **Automate**: Identify repetitive tasks to automate
5. **Preventive Work**: Fix root causes, not symptoms

## Common Scenarios

### Scenario: Alert During Meal

1. Check severity (P0/P1 requires immediate response)
2. Acknowledge alert
3. If P2/P3, can wait 30 minutes
4. If P0/P1, hand off to secondary on-call
5. Post in #incidents that secondary is covering

### Scenario: Multiple Simultaneous Alerts

1. Acknowledge all alerts
2. Assess if related (common root cause)
3. Prioritize by severity and user impact
4. Escalate to L2 for help
5. Divide responsibilities if multiple issues

### Scenario: Alert During Sleep

1. Wake up, acknowledge alert
2. Assess severity with quick check
3. If P0, start immediate response
4. If P1/P2, assess if can wait until morning
5. Escalate if too complex for middle-of-night

### Scenario: Unsure How to Proceed

1. Don't panic or guess
2. Search runbooks for similar issues
3. Check recent incidents for patterns
4. Escalate to L2 for guidance
5. Document what you tried

## Emergency Contacts

### Internal

- **Primary On-Call**: [Current rotation]
- **Secondary On-Call**: [Current rotation]
- **Platform Team Lead**: [Name/Phone/Slack]
- **Security Team**: [Name/Phone/Slack]
- **CTO**: [Name/Phone] (Emergencies only)

### External

- **GCP Support**: Via Cloud Console → Support
- **Stripe Support**: dashboard.stripe.com/support
- **DNS Provider**: [Support contact]
- **CDN Provider**: [Support contact if applicable]

## Additional Resources

- [Runbooks Index](README.md)
- [Quick Reference Guide](QUICK_REFERENCE.md)
- [Logging Documentation](../LOGGING.md)
- [Deployment Runbook](../../terraform/DEPLOYMENT_RUNBOOK.md)
- [Rate Limiting Guide](../RATE_LIMITING.md)

---

**Remember**: The goal is to restore service quickly and safely. When in doubt, escalate. No one expects you to know everything.

**Take care of yourself**: On-call can be stressful. Use resources, ask for help, and don't hesitate to escalate for your own wellbeing.

---

Last Updated: 2025-10-09
