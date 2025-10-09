# Grafana Access Guide

## Overview

Grafana is deployed as part of the kube-prometheus-stack in the `monitoring` namespace. It provides visualization and dashboards for all CrystalShards platform metrics.

## Accessing Grafana

### Via LoadBalancer (Production)

After Terraform deployment, Grafana is exposed via a LoadBalancer service:

```bash
# Get the LoadBalancer external IP
kubectl get svc -n monitoring prometheus-operator-grafana

# Example output:
# NAME                          TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)        AGE
# prometheus-operator-grafana   LoadBalancer   10.XX.XX.XX     35.XXX.XX.XX    80:XXXXX/TCP   10m
```

Access Grafana at: `http://EXTERNAL-IP`

### Via Port Forward (Development)

For local development or testing:

```bash
# Port forward Grafana to localhost
kubectl port-forward -n monitoring svc/prometheus-operator-grafana 3000:80

# Access at http://localhost:3000
```

## Default Credentials

**Default credentials** (configured in Terraform):
- **Username**: `admin`
- **Password**: `admin`

**IMPORTANT**: Change the password immediately after first login in production!

## Updating Admin Password

### Option 1: Via Terraform (Recommended for Production)

Edit `/workspaces/monorepo/terraform/modules/operators/resource.helm_release.prometheus_operator.tf`:

```hcl
grafana = {
  # ... other config ...
  adminPassword = "your-secure-password-here"
}
```

Then apply:
```bash
cd /workspaces/monorepo/terraform
terraform apply
```

### Option 2: Via Grafana UI

1. Log in to Grafana
2. Click on your profile icon (bottom left)
3. Go to "Preferences" > "Change password"
4. Update password

### Option 3: Via Kubernetes Secret

```bash
# Update the secret directly
kubectl -n monitoring patch secret prometheus-operator-grafana \
  -p '{"data":{"admin-password":"'$(echo -n "new-password" | base64)'"}}'

# Restart Grafana to pick up the change
kubectl -n monitoring rollout restart deployment/prometheus-operator-grafana
```

## Available Dashboards

After deployment, the following dashboards will be automatically provisioned:

### CrystalShards Folder
- **Lucky Applications Overview (RED Metrics)**: Request rate, error rate, duration for all 4 apps

### Infrastructure Folder
- **PostgreSQL Overview**: Connection pool, query performance, replication lag
- **Redis Overview**: Memory usage, cache hit rate, operations per second
- **MinIO Overview**: Storage usage, request rates, bandwidth
- **GKE Cluster Overview**: Pod status, resource utilization, node health

## Navigating Grafana

### Finding Dashboards

1. Click the **Dashboards** icon (four squares) in the left sidebar
2. Browse by folder: "CrystalShards" or "Infrastructure"
3. Use the search box to find specific dashboards

### Using Dashboards

- **Time Range**: Adjust using the time picker in the top-right corner
- **Refresh Rate**: Set auto-refresh interval (default: 30s)
- **Variables**: Some dashboards have dropdowns to filter by namespace/pod
- **Zoom**: Click and drag on a panel to zoom into a time range
- **Panel Details**: Click panel title → View → Full screen for detailed view

## Setting Up Alerts

### Viewing Existing Alerts

1. Click the **Alerting** icon (bell) in the left sidebar
2. View "Alert rules" to see all configured alerts
3. View "Silences" to temporarily mute alerts

### Current Alert Rules

Alerts are defined in Prometheus and visible in Grafana:

**Application Alerts**:
- High Error Rate (>5% for 5m)
- High Latency (p95 >1s for 5m)
- Application Down (>2m)

**Database Alerts**:
- PostgreSQL Connection Exhaustion (>80% for 5m)
- PostgreSQL High Replication Lag (>30s for 5m)
- PostgreSQL Down (>2m)

**Redis Alerts**:
- High Memory Usage (>80% for 5m)
- Low Hit Rate (<50% for 10m)
- Redis Down (>2m)

**Pod Alerts**:
- Pod Crash Looping (restarts for 5m)
- Pod Not Ready (>10m)

**MinIO Alerts**:
- High Error Rate (>10 errors/sec for 5m)
- MinIO Down (>2m)

### Configuring Alert Notifications

To receive alert notifications, configure AlertManager (currently disabled):

1. Enable AlertManager in Terraform:
   ```hcl
   alertmanager = {
     enabled = true
   }
   ```

2. Configure notification channels:
   - Email
   - Slack
   - PagerDuty
   - Webhook

See [AlertManager documentation](https://prometheus.io/docs/alerting/latest/alertmanager/) for details.

## Exploring Metrics

### Via Explore Tab

1. Click the **Explore** icon (compass) in the left sidebar
2. Select "Prometheus" as data source
3. Build queries using:
   - **Metrics browser**: Click "Metrics" to browse available metrics
   - **Query builder**: Use dropdown menus to build queries
   - **Code mode**: Write PromQL directly

### Common Queries

**Application Metrics**:
```promql
# Request rate per app
sum(rate(http_requests_total[5m])) by (namespace)

# Error rate
sum(rate(http_requests_total{status=~"5.."}[5m])) by (namespace)

# p95 latency
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (namespace, le))
```

**Database Metrics**:
```promql
# Active connections
pg_stat_activity_count

# Cache hit ratio
rate(pg_stat_database_blks_hit[5m]) / (rate(pg_stat_database_blks_hit[5m]) + rate(pg_stat_database_blks_read[5m]))
```

**Redis Metrics**:
```promql
# Memory usage percentage
redis_memory_used_bytes / redis_memory_max_bytes * 100

# Cache hit rate
rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) * 100
```

## Creating Custom Dashboards

### From UI

1. Click **+** icon in left sidebar
2. Select "New Dashboard"
3. Click "Add visualization"
4. Select "Prometheus" as data source
5. Build your query and customize visualization
6. Save dashboard to a folder

### From JSON

1. Click **Dashboards** → **New** → **Import**
2. Paste JSON or upload file
3. Select Prometheus data source
4. Save to folder

### Exporting Dashboards

To save custom dashboards to Git:

1. Click dashboard title → **Share** → **Export**
2. Toggle "Export for sharing externally"
3. Click "Save to file"
4. Save JSON to `/workspaces/monorepo/terraform/modules/operators/dashboards/`
5. Update ConfigMap in Terraform
6. Commit to Git

## Troubleshooting

### Cannot Access Grafana

```bash
# Check if Grafana pod is running
kubectl get pods -n monitoring | grep grafana

# Check Grafana logs
kubectl logs -n monitoring deployment/prometheus-operator-grafana

# Check service
kubectl get svc -n monitoring prometheus-operator-grafana
```

### Dashboards Not Loading

```bash
# Check ConfigMaps
kubectl get configmaps -n monitoring -l grafana_dashboard=1

# Check dashboard sidecar logs
kubectl logs -n monitoring deployment/prometheus-operator-grafana -c grafana-sc-dashboard

# Restart Grafana
kubectl rollout restart -n monitoring deployment/prometheus-operator-grafana
```

### No Data in Panels

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-operator-kube-prom-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check ServiceMonitors
kubectl get servicemonitors -A

# Check if apps are exposing metrics
kubectl port-forward -n crystalshards svc/crystalshards 5000:80
# Visit http://localhost:5000/metrics
```

### Authentication Issues

```bash
# Reset admin password
kubectl -n monitoring delete secret prometheus-operator-grafana

# Restart Grafana (will recreate secret with default password)
kubectl -n monitoring rollout restart deployment/prometheus-operator-grafana
```

## Performance Optimization

### Dashboard Loading Slow

- Reduce time range (e.g., last 1h instead of 24h)
- Increase refresh interval (e.g., 1m instead of 30s)
- Reduce number of panels on dashboard
- Optimize PromQL queries (use recording rules)

### High Memory Usage

```bash
# Check Grafana resource usage
kubectl top pod -n monitoring | grep grafana

# Increase memory limits in Terraform if needed
```

## Security Best Practices

1. **Change Default Password**: Immediately after deployment
2. **Enable HTTPS**: Configure TLS for production
3. **Set Up SSO**: Use OAuth/LDAP/SAML for authentication
4. **Role-Based Access**: Create viewer/editor roles for different teams
5. **API Key Rotation**: Rotate API keys regularly if using programmatic access
6. **Audit Logs**: Enable audit logging for compliance

## Data Retention

Prometheus retention is configured in Terraform:

```hcl
prometheus = {
  prometheusSpec = {
    retention = "7d"  # Keep metrics for 7 days
  }
}
```

To adjust:
1. Update retention value in Terraform
2. Apply changes: `terraform apply`
3. Grafana queries will only show data within retention period

## Backup and Restore

### Backup Dashboards

Dashboards are automatically backed up to Git via ConfigMaps. For additional backup:

```bash
# Export all dashboards via API
kubectl port-forward -n monitoring svc/prometheus-operator-grafana 3000:80

# Use Grafana API to export (requires API key)
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:3000/api/search | jq -r '.[].uid' | \
  xargs -I {} curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:3000/api/dashboards/uid/{} > backup-{}.json
```

### Restore Dashboards

Dashboards are automatically restored from ConfigMaps on Grafana startup.

## Additional Resources

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/best-practices/best-practices-for-creating-dashboards/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)

## Support

For issues or questions:
1. Check logs: `kubectl logs -n monitoring deployment/prometheus-operator-grafana`
2. Review Prometheus targets: Port-forward to 9090 and check `/targets`
3. Check GitHub issues: [CrystalShards repository](https://github.com/crystalshards/crystalshards)
