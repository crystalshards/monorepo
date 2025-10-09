# PrometheusRule for CrystalShards platform alerts
resource "kubectl_manifest" "crystalshards_alert_rules" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "crystalshards-alerts"
      namespace = "monitoring"
      labels = {
        prometheus = "kube-prometheus"
        role       = "alert-rules"
      }
    }
    spec = {
      groups = [
        {
          name = "application-alerts"
          interval = "30s"
          rules = [
            {
              alert = "HighErrorRate"
              expr  = "sum(rate(http_requests_total{namespace=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\",status=~\"5..\"}[5m])) by (namespace) / sum(rate(http_requests_total{namespace=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\"}[5m])) by (namespace) * 100 > 5"
              for   = "5m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "High error rate detected in {{ $labels.namespace }}"
                description = "Error rate is {{ $value }}% in namespace {{ $labels.namespace }} (threshold: 5%)"
              }
            },
            {
              alert = "HighLatency"
              expr  = "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\"}[5m])) by (namespace, le)) > 1"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "High latency detected in {{ $labels.namespace }}"
                description = "P95 latency is {{ $value }}s in namespace {{ $labels.namespace }} (threshold: 1s)"
              }
            },
            {
              alert = "ApplicationDown"
              expr  = "up{job=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\"} == 0"
              for   = "2m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Application {{ $labels.job }} is down"
                description = "Application {{ $labels.job }} in namespace {{ $labels.namespace }} has been down for more than 2 minutes"
              }
            }
          ]
        },
        {
          name = "database-alerts"
          interval = "30s"
          rules = [
            {
              alert = "PostgreSQLConnectionExhaustion"
              expr  = "pg_stat_activity_count{namespace=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\"} / pg_settings_max_connections{namespace=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\"} > 0.8"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "PostgreSQL connection pool near exhaustion in {{ $labels.namespace }}"
                description = "Connection pool is {{ $value | humanizePercentage }} full in namespace {{ $labels.namespace }} (threshold: 80%)"
              }
            },
            {
              alert = "PostgreSQLHighReplicationLag"
              expr  = "pg_replication_lag{namespace=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\"} > 30"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "High PostgreSQL replication lag in {{ $labels.namespace }}"
                description = "Replication lag is {{ $value }}s in namespace {{ $labels.namespace }} (threshold: 30s)"
              }
            },
            {
              alert = "PostgreSQLDown"
              expr  = "pg_up{namespace=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\"} == 0"
              for   = "2m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "PostgreSQL is down in {{ $labels.namespace }}"
                description = "PostgreSQL instance in namespace {{ $labels.namespace }} has been down for more than 2 minutes"
              }
            }
          ]
        },
        {
          name = "redis-alerts"
          interval = "30s"
          rules = [
            {
              alert = "RedisHighMemoryUsage"
              expr  = "redis_memory_used_bytes{namespace=\"infrastructure\"} / redis_memory_max_bytes{namespace=\"infrastructure\"} * 100 > 80"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Redis memory usage is high"
                description = "Redis memory usage is {{ $value }}% (threshold: 80%)"
              }
            },
            {
              alert = "RedisDown"
              expr  = "redis_up{namespace=\"infrastructure\"} == 0"
              for   = "2m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Redis is down"
                description = "Redis instance in infrastructure namespace has been down for more than 2 minutes"
              }
            },
            {
              alert = "RedisLowHitRate"
              expr  = "rate(redis_keyspace_hits_total{namespace=\"infrastructure\"}[5m]) / (rate(redis_keyspace_hits_total{namespace=\"infrastructure\"}[5m]) + rate(redis_keyspace_misses_total{namespace=\"infrastructure\"}[5m])) * 100 < 50"
              for   = "10m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Redis cache hit rate is low"
                description = "Redis cache hit rate is {{ $value }}% (threshold: 50%)"
              }
            }
          ]
        },
        {
          name = "pod-alerts"
          interval = "30s"
          rules = [
            {
              alert = "PodCrashLooping"
              expr  = "rate(kube_pod_container_status_restarts_total{namespace=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\"}[15m]) > 0"
              for   = "5m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Pod {{ $labels.pod }} is crash looping"
                description = "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is restarting frequently"
              }
            },
            {
              alert = "PodNotReady"
              expr  = "kube_pod_status_phase{namespace=~\"crystalshards|crystaldocs|crystalgigs|crystalbits\",phase!=\"Running\"} == 1"
              for   = "10m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Pod {{ $labels.pod }} is not ready"
                description = "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been in {{ $labels.phase }} state for more than 10 minutes"
              }
            }
          ]
        },
        {
          name = "minio-alerts"
          interval = "30s"
          rules = [
            {
              alert = "MinIOHighErrorRate"
              expr  = "rate(minio_s3_requests_errors_total{namespace=\"infrastructure\"}[5m]) > 10"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "MinIO has high error rate"
                description = "MinIO error rate is {{ $value }} errors/sec for API {{ $labels.api }}"
              }
            },
            {
              alert = "MinIODown"
              expr  = "minio_up{namespace=\"infrastructure\"} == 0"
              for   = "2m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "MinIO is down"
                description = "MinIO instance in infrastructure namespace has been down for more than 2 minutes"
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [helm_release.prometheus_operator]
}
