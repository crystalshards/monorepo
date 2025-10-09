# Grafana Dashboards for CrystalShards Platform

This directory contains Grafana dashboard JSON definitions for monitoring the CrystalShards platform.

## Dashboard Overview

### Application Dashboards

#### Lucky Applications Overview (RED Metrics)
- **File**: `lucky-apps-overview.json`
- **UID**: `lucky-apps-red`
- **Folder**: CrystalShards
- **Metrics**:
  - Request Rate (requests per second)
  - Error Rate (5xx responses as percentage)
  - Response Time Percentiles (p50, p95, p99)
  - HTTP Status Code Distribution
  - Active Connections

Covers all 4 Lucky applications:
- CrystalShards (package registry)
- CrystalDocs (documentation)
- CrystalGigs (job board)
- CrystalBits (code snippets)

### Infrastructure Dashboards

#### PostgreSQL Overview (CloudNativePG)
- **File**: `postgresql-overview.json`
- **UID**: `postgresql-cnpg`
- **Folder**: Infrastructure
- **Metrics**:
  - Active Connections by Namespace
  - Cache Hit Ratio
  - Query Performance (Tuples Fetched)
  - Replication Lag
  - Database Size

#### Redis Overview
- **File**: `redis-overview.json`
- **UID**: `redis-overview`
- **Folder**: Infrastructure
- **Metrics**:
  - Memory Usage Percentage
  - Connected Clients
  - Cache Hit Rate
  - Operations per Second
  - Keys per Database
  - Key Expiration and Eviction

#### MinIO Overview
- **File**: `minio-overview.json`
- **UID**: `minio-overview`
- **Folder**: Infrastructure
- **Metrics**:
  - Total Storage Used
  - Total Objects
  - Total Buckets
  - Request Rate by API
  - Network Bandwidth (received/sent)
  - Error Rate by API
  - Storage Usage by Bucket

#### GKE Cluster Overview
- **File**: `gke-cluster-overview.json`
- **UID**: `gke-cluster`
- **Folder**: Infrastructure
- **Metrics**:
  - Running/Failed Pods
  - Total Pod Restarts
  - Total Namespaces
  - CPU Usage by Namespace
  - Memory Usage by Namespace
  - Running Pods by Namespace
  - Pod Restart Rate by Namespace

## Dashboard Provisioning

Dashboards are automatically loaded into Grafana via ConfigMaps with the label `grafana_dashboard: "1"`.

The Grafana sidecar watches for ConfigMaps in all namespaces and automatically imports them.

## Accessing Grafana

After Terraform deployment, Grafana will be available via LoadBalancer:

```bash
# Get Grafana LoadBalancer IP
kubectl get svc -n monitoring prometheus-operator-grafana

# Default credentials (change in production)
Username: admin
Password: admin
```

## Prometheus Queries Used

### Application Metrics

Expected metrics from Lucky applications:
- `http_requests_total{namespace, status}` - Counter of HTTP requests
- `http_request_duration_seconds_bucket{namespace, le}` - Histogram of request durations
- `http_server_active_connections{namespace}` - Gauge of active connections

### PostgreSQL Metrics (CloudNativePG)

Expected metrics from PostgreSQL:
- `pg_stat_activity_count{namespace, state}` - Number of active connections
- `pg_stat_database_blks_read{namespace, datname}` - Disk blocks read
- `pg_stat_database_blks_hit{namespace, datname}` - Cache hits
- `pg_stat_database_tup_fetched{namespace, datname}` - Tuples fetched
- `pg_replication_lag{namespace, application_name}` - Replication lag in seconds
- `pg_stat_database_size{namespace, datname}` - Database size in bytes
- `pg_up{namespace}` - PostgreSQL instance up status

### Redis Metrics

Expected metrics from Redis:
- `redis_memory_used_bytes{namespace}` - Memory currently used
- `redis_memory_max_bytes{namespace}` - Maximum memory configured
- `redis_connected_clients{namespace}` - Number of connected clients
- `redis_keyspace_hits_total{namespace}` - Cache hits counter
- `redis_keyspace_misses_total{namespace}` - Cache misses counter
- `redis_commands_total{namespace, cmd}` - Commands executed counter
- `redis_db_keys{namespace, db}` - Number of keys per database
- `redis_expired_keys_total{namespace}` - Expired keys counter
- `redis_evicted_keys_total{namespace}` - Evicted keys counter
- `redis_up{namespace}` - Redis instance up status

### MinIO Metrics

Expected metrics from MinIO:
- `minio_bucket_usage_total_bytes{namespace, bucket}` - Total storage used per bucket
- `minio_bucket_usage_object_total{namespace, bucket}` - Total objects per bucket
- `minio_s3_requests_total{namespace, api}` - S3 API requests counter
- `minio_s3_traffic_received_bytes{namespace}` - Bytes received counter
- `minio_s3_traffic_sent_bytes{namespace}` - Bytes sent counter
- `minio_s3_requests_errors_total{namespace, api, error}` - Error counter
- `minio_up{namespace}` - MinIO instance up status

### Kubernetes Metrics

Expected metrics from kube-state-metrics:
- `kube_pod_status_phase{namespace, phase}` - Pod phase status
- `kube_pod_container_status_restarts_total{namespace, pod}` - Container restart count
- `kube_namespace_created` - Namespace creation timestamp
- `container_cpu_usage_seconds_total{namespace}` - CPU usage
- `container_memory_working_set_bytes{namespace}` - Memory usage
- `kube_pod_container_resource_requests{namespace, resource}` - Resource requests

## Alert Rules

Alert rules are defined in `/terraform/modules/operators/resource.kubectl_manifest.prometheus_rules.tf`:

### Application Alerts
- **HighErrorRate**: Triggers when error rate > 5% for 5 minutes (critical)
- **HighLatency**: Triggers when p95 latency > 1s for 5 minutes (warning)
- **ApplicationDown**: Triggers when application is down for 2 minutes (critical)

### Database Alerts
- **PostgreSQLConnectionExhaustion**: Triggers when connections > 80% for 5 minutes (warning)
- **PostgreSQLHighReplicationLag**: Triggers when lag > 30s for 5 minutes (warning)
- **PostgreSQLDown**: Triggers when PostgreSQL is down for 2 minutes (critical)

### Redis Alerts
- **RedisHighMemoryUsage**: Triggers when memory > 80% for 5 minutes (warning)
- **RedisDown**: Triggers when Redis is down for 2 minutes (critical)
- **RedisLowHitRate**: Triggers when hit rate < 50% for 10 minutes (warning)

### Pod Alerts
- **PodCrashLooping**: Triggers when pod restarts frequently for 5 minutes (critical)
- **PodNotReady**: Triggers when pod not ready for 10 minutes (warning)

### MinIO Alerts
- **MinIOHighErrorRate**: Triggers when errors > 10/sec for 5 minutes (warning)
- **MinIODown**: Triggers when MinIO is down for 2 minutes (critical)

## Customization

To modify dashboards:

1. Edit the JSON files in this directory
2. Run `terraform apply` to update the ConfigMaps
3. Grafana sidecar will automatically reload the dashboards

Alternatively, edit dashboards in Grafana UI and export the JSON to update these files.

## Troubleshooting

### Dashboards not appearing

Check ConfigMap labels:
```bash
kubectl get configmaps -n monitoring -l grafana_dashboard=1
```

Check Grafana logs:
```bash
kubectl logs -n monitoring deployment/prometheus-operator-grafana -c grafana-sc-dashboard
```

### No data in dashboards

Verify Prometheus is scraping metrics:
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-operator-kube-prom-prometheus 9090:9090

# Open http://localhost:9090 and check targets
```

Verify ServiceMonitors exist:
```bash
kubectl get servicemonitors -A
```

### Metrics not matching queries

Application metrics depend on the Lucky applications exposing metrics at `/metrics` endpoint. Ensure:
- Applications are running
- ServiceMonitors are configured correctly
- Prometheus has permission to scrape the namespaces

## Production Recommendations

1. **Change default password**: Update `adminPassword` in Prometheus operator Helm values
2. **Enable HTTPS**: Configure TLS for Grafana service
3. **Set up authentication**: Integrate with OAuth/LDAP for production
4. **Configure alerting**: Set up AlertManager for alert notifications
5. **Backup dashboards**: Export dashboards regularly or use GitOps
6. **Tune retention**: Adjust Prometheus retention based on storage capacity
7. **Scale Grafana**: Increase replicas for high availability

## Links

- [Grafana Documentation](https://grafana.com/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [kube-prometheus-stack Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [CloudNativePG Monitoring](https://cloudnative-pg.io/documentation/current/monitoring/)
