# CrystalShards Logging Architecture

This document describes the centralized logging system for the CrystalShards platform.

## Architecture Overview

The logging infrastructure uses the **Loki + Promtail** stack integrated with our existing Grafana monitoring system.

```
┌─────────────────────────────────────────────────────────┐
│                     Applications                        │
│  (crystalshards, crystaldocs, crystalgigs, crystalbits) │
│              Writing logs to STDOUT                     │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│                   Promtail DaemonSet                    │
│         (Runs on every node, collects pod logs)         │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│                        Loki                             │
│         (Log aggregation and storage backend)           │
│              Retention: 7 days (168h)                   │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│                      Grafana                            │
│         (Query and visualize logs via Explore)          │
│            Dashboards for common patterns               │
└─────────────────────────────────────────────────────────┘
```

## Components

### Loki

**Purpose**: Centralized log aggregation and storage
**Deployment**: Single binary mode (cost-efficient for our scale)
**Namespace**: `monitoring`
**Service**: `loki-gateway:80`
**Storage**: 50Gi persistent volume (filesystem-based)
**Retention**: 7 days

**Configuration Highlights**:
- Single binary deployment for simplicity
- Filesystem storage (no external dependencies)
- 16MB/s ingestion rate limit
- TSDB schema for efficient queries
- ServiceMonitor enabled for Prometheus metrics

### Promtail

**Purpose**: Log shipping agent (collects and forwards logs to Loki)
**Deployment**: DaemonSet (runs on every node)
**Namespace**: `monitoring`
**Resources**: 100m CPU, 128Mi memory (per pod)

**What It Collects**:
- All pod logs from application namespaces (crystalshards, crystaldocs, crystalgigs, crystalbits)
- System component logs (envoy-gateway, monitoring, cert-manager, infrastructure)
- Labels added automatically: `namespace`, `pod`, `container`, `app`

**What It Excludes**:
- `kube-system` namespace (too noisy, not actionable)

### Grafana Integration

**Data Source**: Loki is automatically configured as a Grafana data source
**Access URL**: `http://loki-gateway:80`
**Dashboard**: "Logs Overview" dashboard pre-configured
**Explore UI**: Available at Grafana → Explore → Select "Loki"

## Log Collection Strategy

### Application Requirements

All Lucky applications MUST log to **STDOUT** for Promtail to collect logs. This is the standard for containerized applications.

**Crystal/Lucky Logging Best Practices**:

1. **Use Lucky's Logger**:
```crystal
# config/log_handler.cr
Log.setup do |config|
  config.bind "*", :info, Log::IOBackend.new(STDOUT)
end
```

2. **Structured Logging** (Recommended):
```crystal
Log.info { "request_completed", method: "GET", path: "/shards", duration: 45.ms, status: 200 }
```

3. **Include Context**:
- Request ID for tracing
- User ID for debugging
- Job ID for worker logs
- Timestamp (automatic)

4. **Log Levels**:
- `DEBUG`: Detailed information for troubleshooting
- `INFO`: General informational messages
- `WARN`: Warning messages (potential issues)
- `ERROR`: Error messages (failures)
- `FATAL`: Critical errors requiring immediate attention

### Log Sources

**Application Logs**:
- CrystalShards: API server + JoobQ workers
- CrystalDocs: API server
- CrystalGigs: API server
- CrystalBits: API server

**Infrastructure Logs**:
- PostgreSQL (CloudNativePG)
- Redis
- MinIO
- Envoy Gateway
- cert-manager

## Querying Logs

### Grafana Explore UI

1. Navigate to Grafana → Explore
2. Select "Loki" data source from dropdown
3. Enter LogQL query
4. Set time range
5. Click "Run query"

### Common Queries

See `/workspaces/monorepo/terraform/modules/operators/LOG_QUERIES.md` for comprehensive query examples.

**Quick Reference**:

```logql
# All logs from CrystalShards
{namespace="crystalshards"}

# All error logs across applications
{namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"} |~ "(?i)error"

# Worker job processing
{namespace="crystalshards", app="worker"} |= "perform"

# HTTP 5xx errors
{namespace=~".*"} |~ "status=5[0-9]{2}"
```

### Grafana Dashboard

Pre-configured dashboard: **"Logs Overview"**

**Panels**:
1. Log Volume by Namespace (timeseries)
2. Error Rate by Namespace (timeseries)
3. Application Logs Stream (live tail)
4. Top 10 Namespaces by Error Count (table)
5. Log Distribution by Application (pie chart)
6. Error Logs (filtered stream)
7. Worker Logs (JoobQ)
8. Infrastructure Logs
9. CrystalShards Pods Log Volume

**Features**:
- Auto-refresh every 30s
- Live log streaming
- Error highlighting
- Namespace filtering
- Time range selection

## Retention Policy

**Current**: 7 days (168 hours)

Logs are automatically deleted after 7 days to manage storage costs.

**Considerations for Adjustment**:
- Increase retention for compliance requirements
- Decrease for cost optimization
- Archive to object storage for long-term retention (future enhancement)

**To Change Retention**:
Edit `/workspaces/monorepo/terraform/modules/operators/resource.helm_release.loki.tf`:
```hcl
limits_config = {
  retention_period = "336h" # 14 days
}
```

## Adding New Log Sources

### For New Applications

1. **Ensure Application Logs to STDOUT**:
```crystal
Log.setup do |config|
  config.bind "*", :info, Log::IOBackend.new(STDOUT)
end
```

2. **Deploy Application to Kubernetes**:
Promtail automatically discovers and collects logs from all pods.

3. **Verify in Grafana**:
```logql
{namespace="your-new-app"}
```

### For New Infrastructure Components

1. **Check Component Logs to STDOUT**:
Most Kubernetes operators and Helm charts log to STDOUT by default.

2. **Add Namespace to Promtail Scrape Config** (if needed):
Edit `/workspaces/monorepo/terraform/modules/operators/resource.helm_release.promtail.tf`:
```hcl
- source_labels: [__meta_kubernetes_namespace]
  regex: (envoy-gateway-system|monitoring|cert-manager|infrastructure|your-namespace)
  action: keep
```

## Troubleshooting Guide

### No Logs Appearing in Grafana

**Symptoms**: Query returns no results

**Checks**:
1. Verify Loki is running:
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
   ```

2. Verify Promtail is running on all nodes:
   ```bash
   kubectl get daemonset -n monitoring promtail
   ```

3. Check Promtail logs for errors:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=50
   ```

4. Verify application is logging to STDOUT:
   ```bash
   kubectl logs -n crystalshards <pod-name> --tail=20
   ```

5. Check Loki ingestion:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=50
   ```

### High Log Volume / Storage Issues

**Symptoms**: Loki PVC filling up, slow queries

**Solutions**:
1. Reduce retention period (see Retention Policy section)
2. Increase PVC size:
   ```hcl
   persistence = {
     size = "100Gi" # Increase from 50Gi
   }
   ```
3. Exclude noisy pods/namespaces from Promtail scrape config
4. Implement log sampling for high-traffic apps

### Query Performance Issues

**Symptoms**: Slow queries, timeouts

**Solutions**:
1. Narrow time range (default to last 1 hour)
2. Use specific namespace filters early in query
3. Avoid regex on high-cardinality fields
4. Use `|= "text"` (exact match) instead of `|~ "regex"` when possible
5. Increase Loki resources:
   ```hcl
   resources = {
     limits = {
       cpu    = "2000m"
       memory = "2Gi"
     }
   }
   ```

### Logs Missing from Specific Pods

**Checks**:
1. Verify pod is in a monitored namespace
2. Check if pod has label `app` (helps with filtering)
3. Verify Promtail has access to node logs:
   ```bash
   kubectl exec -n monitoring promtail-xxxx -- ls -la /var/log/pods/
   ```

### Loki Out of Memory

**Symptoms**: Loki pod restarting, OOMKilled

**Solutions**:
1. Reduce ingestion rate:
   ```hcl
   limits_config = {
     ingestion_rate_mb = 8  # Reduce from 16
   }
   ```
2. Increase memory limits:
   ```hcl
   resources = {
     limits = {
       memory = "2Gi"  # Increase from 1Gi
     }
   }
   ```
3. Enable query splitting for large time ranges

## Performance & Cost Optimization

### Cost Considerations

**Storage**: 50Gi PVC costs approximately $10/month on GCP

**CPU/Memory**: Minimal overhead (Loki: 250m/512Mi, Promtail: 100m/128Mi per node)

**Network**: Minimal egress (all traffic internal to cluster)

### Optimization Tips

1. **Filter Early**: Use namespace/pod filters before text searches
2. **Limit Time Range**: Default to last 1 hour for ad-hoc queries
3. **Use Dashboard Variables**: Create reusable dashboard queries
4. **Aggregate at Query Time**: Use `count_over_time()` instead of storing metrics
5. **Archive Old Logs**: Export to GCS for compliance (future enhancement)

## Security Considerations

### Access Control

**Grafana**: Protected by Grafana authentication (default admin password in Helm values)
**Loki**: Internal-only access (no external ingress)
**Promtail**: Runs with minimal privileges (system-node-critical priority class)

**Recommendations**:
1. Change Grafana admin password (in Terraform or via UI)
2. Enable RBAC for Grafana (different roles for different teams)
3. Rotate credentials regularly

### Sensitive Data

**Risk**: Logs may contain sensitive information (PII, API keys, passwords)

**Mitigations**:
1. Avoid logging sensitive data in application code
2. Use structured logging with field-level filtering
3. Implement log redaction for known patterns (future enhancement)
4. Set appropriate retention periods for compliance

## Monitoring Loki Itself

### Metrics

Loki exposes Prometheus metrics via ServiceMonitor.

**Key Metrics**:
- `loki_ingester_streams_created_total` - Stream creation rate
- `loki_ingester_memory_streams` - Active streams in memory
- `loki_ingester_bytes_received_total` - Ingestion throughput
- `loki_distributor_lines_received_total` - Lines received
- `loki_request_duration_seconds` - Query latency

### Alerts

Add Prometheus alerts for Loki health:

```yaml
- alert: LokiDown
  expr: up{job="loki"} == 0
  for: 5m
  annotations:
    summary: "Loki is down"

- alert: LokiHighIngestionRate
  expr: rate(loki_distributor_lines_received_total[5m]) > 10000
  for: 10m
  annotations:
    summary: "Loki ingestion rate is high"
```

## Future Enhancements

**Planned Improvements**:
1. **AlertManager Integration**: Send alerts based on log patterns
2. **Long-term Archive**: Export old logs to GCS for compliance
3. **Multi-tenancy**: Separate tenants for different teams
4. **Log Sampling**: Sample high-volume logs to reduce costs
5. **Distributed Deployment**: Scale to multiple Loki instances for HA
6. **Structured Logging**: Standardize JSON log format across all apps
7. **Log Redaction**: Automatically redact sensitive data patterns

## Resources

**Internal Documentation**:
- Log Query Examples: `/workspaces/monorepo/terraform/modules/operators/LOG_QUERIES.md`
- Terraform Configuration: `/workspaces/monorepo/terraform/modules/operators/resource.helm_release.loki.tf`
- Grafana Dashboard: `/workspaces/monorepo/terraform/modules/operators/dashboards/logs-overview.json`

**External Resources**:
- Loki Documentation: https://grafana.com/docs/loki/latest/
- LogQL Reference: https://grafana.com/docs/loki/latest/logql/
- Promtail Configuration: https://grafana.com/docs/loki/latest/clients/promtail/
- Best Practices: https://grafana.com/docs/loki/latest/best-practices/

## Support

For issues with logging infrastructure:
1. Check this troubleshooting guide
2. Review Loki/Promtail pod logs
3. Query Loki metrics in Prometheus
4. Create GitHub issue with details

---

**Last Updated**: 2025-10-09
**Maintained By**: CrystalShards DevOps Team
