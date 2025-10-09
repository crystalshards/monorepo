# Lucky Applications Metrics Verification Report

**Date**: 2025-10-09
**Task**: Verify Prometheus metrics exposure for all four Lucky applications
**Status**: CRITICAL - No metrics endpoints implemented

---

## Executive Summary

All four Lucky applications (CrystalShards, CrystalDocs, CrystalGigs, CrystalBits) have ServiceMonitor configurations deployed that expect `/metrics` endpoints, but **NONE of the applications currently expose Prometheus metrics**. This means Prometheus is attempting to scrape endpoints that don't exist, resulting in failed scrapes and no application-level observability.

---

## Current State Analysis

### 1. ServiceMonitor Configurations (DEPLOYED)

All four applications have ServiceMonitors configured and ready to scrape:

| Application | ServiceMonitor | Endpoint | Interval | Status |
|------------|----------------|----------|----------|--------|
| CrystalShards | crystalshards-api | `/metrics` | 30s | Configured |
| CrystalDocs | crystaldocs-api | `/metrics` | 30s | Configured |
| CrystalGigs | crystalgigs-api | `/metrics` | 30s | Configured |
| CrystalBits | crystalbits-api | `/metrics` | 30s | Configured |

**Files**:
- `/workspaces/monorepo/apps/crystalshards/terraform/resource.kubectl_manifest.servicemonitor.tf`
- `/workspaces/monorepo/apps/crystaldocs/terraform/resource.kubectl_manifest.servicemonitor.tf`
- `/workspaces/monorepo/apps/crystalgigs/terraform/resource.kubectl_manifest.servicemonitor.tf`
- `/workspaces/monorepo/apps/crystalbits/terraform/resource.kubectl_manifest.servicemonitor.tf`

### 2. Application Dependencies (MISSING METRICS LIBRARIES)

**CrystalShards** (`/workspaces/monorepo/apps/crystalshards/shard.yml`):
- Has Lucky framework and supporting libraries
- Has Redis client (crystal-redis)
- Has JoobQ for background jobs
- **MISSING**: No Prometheus metrics library

**CrystalDocs, CrystalGigs, CrystalBits**:
- Similar Lucky framework setup
- **MISSING**: No Prometheus metrics library

### 3. Existing Endpoints

**CrystalShards** has a health check endpoint:
- Location: `/workspaces/monorepo/apps/crystalshards/src/actions/api/health/show.cr`
- Route: `GET /api/health`
- Checks: Database connectivity, Redis connectivity
- Format: JSON response (not Prometheus format)

**Other applications**: Health endpoints unknown (need verification)

### 4. Worker Process (CrystalShards)

The worker process (`/workspaces/monorepo/apps/crystalshards/src/worker.cr`):
- Runs JoobQ background jobs
- **NO HTTP server** - cannot expose metrics endpoint
- Would need separate metrics exposure mechanism

---

## Available Crystal Metrics Libraries

### Option 1: prometheus-exporter (RECOMMENDED)

**Repository**: https://github.com/marmaxev/prometheus-exporter

**Pros**:
- Built specifically for Lucky framework integration
- Provides middleware: `PrometheusExporter::Middleware::LuckyHttpRequestCollector`
- Supports process-level metrics
- Active maintenance
- Simple integration pattern

**Cons**:
- Requires additional setup for custom metrics
- Less documentation than more mature libraries

**Lucky Integration Example**:
```crystal
# In src/app_server.cr middleware array
PrometheusExporter::Middleware::LuckyHttpRequestCollector.new
```

### Option 2: Crometheus

**Repository**: https://github.com/Darwinnn/crometheus

**Pros**:
- Direct Prometheus client (no middleware)
- Supports all metric types (Counter, Gauge, Histogram, Summary)
- Labeled metrics support
- Built-in HTTP server for metrics

**Cons**:
- "In early development, comes with no guarantees"
- Last release October 2022
- Requires manual instrumentation
- Would need separate endpoint setup in Lucky

---

## Missing Metrics Assessment

### Critical Metrics (RED - Rate, Errors, Duration)

**MISSING** - All applications need:

1. **HTTP Request Metrics**:
   - `http_requests_total` - Counter by method, path, status
   - `http_request_duration_seconds` - Histogram by method, path
   - `http_requests_in_flight` - Gauge

2. **Error Metrics**:
   - `http_errors_total` - Counter by error type, path
   - `exceptions_total` - Counter by exception class

### Database Metrics

**MISSING** - All applications need:

1. **Avram/Database Connection Pool**:
   - `db_connections_active` - Gauge
   - `db_connections_idle` - Gauge
   - `db_connections_waiting` - Gauge
   - `db_connection_checkout_duration_seconds` - Histogram
   - `db_query_duration_seconds` - Histogram by query type

### Redis Metrics

**MISSING** - CrystalShards and other apps using Redis need:

1. **Redis Client Metrics**:
   - `redis_commands_total` - Counter by command
   - `redis_command_duration_seconds` - Histogram
   - `redis_connection_errors_total` - Counter
   - `redis_connections_active` - Gauge

### Background Job Metrics (CrystalShards Worker)

**MISSING** - CrystalShards worker needs:

1. **JoobQ Job Metrics**:
   - `joobq_jobs_processed_total` - Counter by queue, status
   - `joobq_job_duration_seconds` - Histogram by job type
   - `joobq_jobs_waiting` - Gauge by queue
   - `joobq_jobs_in_progress` - Gauge by queue
   - `joobq_jobs_failed_total` - Counter by job type, error
   - `joobq_queue_size` - Gauge by queue

### Business Logic Metrics

**MISSING** - Application-specific metrics:

**CrystalShards**:
- `shards_total` - Counter
- `shard_versions_total` - Counter
- `shard_downloads_total` - Counter by shard
- `shard_builds_total` - Counter by status (success/failure)
- `doc_generation_duration_seconds` - Histogram

**CrystalDocs**:
- `docs_pages_served_total` - Counter by shard
- `docs_search_queries_total` - Counter
- `docs_search_duration_seconds` - Histogram

**CrystalGigs**:
- `jobs_posted_total` - Counter
- `job_applications_total` - Counter

**CrystalBits**:
- `blog_posts_total` - Counter
- `blog_views_total` - Counter by post

### Process Metrics

**MISSING** - All applications need:

1. **Runtime Metrics**:
   - `process_cpu_seconds_total` - Counter
   - `process_resident_memory_bytes` - Gauge
   - `process_virtual_memory_bytes` - Gauge
   - `process_open_fds` - Gauge
   - `crystal_gc_collections_total` - Counter
   - `crystal_gc_duration_seconds` - Histogram

---

## Impact Assessment

### Current Impact

1. **No Application Observability**: Cannot see request rates, error rates, or latencies
2. **Failed Prometheus Scrapes**: ServiceMonitors scraping non-existent endpoints
3. **No Alerting**: Cannot configure alerts for application issues
4. **No SLI/SLO Tracking**: Cannot measure service level indicators
5. **Limited Troubleshooting**: Must rely on logs alone for debugging

### Production Risks

- **Cannot detect performance degradation** until users complain
- **No capacity planning data** for scaling decisions
- **Cannot identify slow endpoints** for optimization
- **No visibility into background job health** (worker)
- **Database connection pool exhaustion** would go unnoticed
- **Redis connection issues** would be invisible until failures

---

## Recommendations

### Immediate Actions (Before Deployment)

1. **Add prometheus-exporter to all applications**:
   ```yaml
   dependencies:
     prometheus-exporter:
       github: marmaxev/prometheus-exporter
   ```

2. **Implement metrics middleware in all apps**:
   - Add to `src/app_server.cr` middleware stack
   - Automatically collects HTTP request metrics (RED metrics)

3. **Create metrics endpoint action** for each app:
   ```crystal
   # src/actions/metrics/show.cr
   class Metrics::Show < ApiAction
     include Api::Auth::SkipRequireAuthToken

     get "/metrics" do
       # Return Prometheus-formatted metrics
       plain_text PrometheusExporter::Client.metrics
     end
   end
   ```

4. **Test metrics endpoints locally**:
   ```bash
   curl http://localhost:3000/metrics
   ```

### Short-term Enhancements (1-2 weeks)

1. **Add custom business metrics**:
   - Shard upload/download counters
   - Documentation build success/failure rates
   - Search query performance

2. **Add database connection pool monitoring**:
   - Instrument Avram connection pool
   - Track query execution times

3. **Add worker metrics endpoint**:
   - Create separate HTTP server in worker for metrics
   - Expose JoobQ queue depths and job processing metrics
   - Add worker-specific ServiceMonitor

4. **Implement process metrics**:
   - Memory usage tracking
   - GC metrics
   - File descriptor counts

### Long-term Improvements (1 month+)

1. **Create application-specific Grafana dashboards**:
   - Request rate, error rate, duration for each app
   - Database performance dashboard
   - Background job queue dashboard

2. **Set up SLO-based alerting**:
   - Define SLIs (e.g., 99th percentile latency < 500ms)
   - Create alerts for SLO violations
   - Implement error budget tracking

3. **Add distributed tracing integration**:
   - Consider OpenTelemetry for Crystal
   - Trace requests across services
   - Correlate logs, metrics, and traces

4. **Implement metrics-based autoscaling**:
   - Use custom metrics for HPA decisions
   - Scale based on queue depth (worker)
   - Scale based on request rate (API)

---

## Implementation Priority

### P0 - CRITICAL (Block deployment):
- [ ] Add prometheus-exporter shard to all 4 applications
- [ ] Implement metrics middleware in all 4 app_server.cr files
- [ ] Create `/metrics` endpoint in all 4 applications
- [ ] Test metrics endpoints return valid Prometheus format
- [ ] Update deployments and verify ServiceMonitors scrape successfully

### P1 - HIGH (Complete within 1 week):
- [ ] Add database connection pool metrics
- [ ] Add Redis connection metrics
- [ ] Add business-specific metrics (uploads, downloads, etc.)
- [ ] Create worker metrics endpoint (separate HTTP server)
- [ ] Add worker ServiceMonitor configuration

### P2 - MEDIUM (Complete within 2 weeks):
- [ ] Add process-level metrics (memory, GC, etc.)
- [ ] Create application-specific Grafana dashboards
- [ ] Document metrics for team

### P3 - LOW (Complete within 1 month):
- [ ] Implement SLO-based alerting
- [ ] Add distributed tracing
- [ ] Implement custom metric-based autoscaling

---

## Technical Implementation Guide

### Step 1: Add Dependency

For each application (`crystalshards`, `crystaldocs`, `crystalgigs`, `crystalbits`):

```yaml
# apps/{app}/shard.yml
dependencies:
  prometheus-exporter:
    github: marmaxev/prometheus-exporter
```

### Step 2: Add Middleware

```crystal
# apps/{app}/src/app_server.cr
class AppServer < Lucky::BaseAppServer
  def middleware : Array(HTTP::Handler)
    [
      Lucky::RequestIdHandler.new,
      Lucky::ForceSSLHandler.new,
      Lucky::HttpMethodOverrideHandler.new,
      Lucky::LogHandler.new,
      PrometheusExporter::Middleware::LuckyHttpRequestCollector.new, # ADD THIS
      Lucky::ErrorHandler.new(action: Errors::Show),
      # ... rest of middleware
    ] of HTTP::Handler
  end
end
```

### Step 3: Create Metrics Endpoint

```crystal
# apps/{app}/src/actions/metrics/show.cr
class Metrics::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/metrics" do
    context.response.content_type = "text/plain; version=0.0.4"
    plain_text PrometheusExporter::Client.metrics
  end
end
```

### Step 4: Run Shards Install

```bash
cd apps/{app}
shards install
```

### Step 5: Test Locally

```bash
# Start application
cd apps/{app}
lucky dev

# In another terminal, check metrics
curl http://localhost:3000/metrics
```

Expected output should include:
```
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/api/health",status="200"} 1

# HELP http_request_duration_seconds HTTP request duration in seconds
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",path="/api/health",le="0.005"} 1
...
```

### Step 6: Deploy and Verify

```bash
# Deploy to cluster
terraform apply

# Verify ServiceMonitor is scraping
kubectl get servicemonitor -n {app-namespace}
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -f | grep "{app-namespace}"
```

---

## Worker-Specific Implementation

The CrystalShards worker needs special handling as it doesn't run an HTTP server:

### Option A: Embedded HTTP Server (RECOMMENDED)

```crystal
# apps/crystalshards/src/worker.cr
require "http/server"
require "./app"

module CrystalShards
  class Worker
    def self.run
      Log.info { "Starting CrystalShards worker process..." }

      # Start metrics HTTP server on separate port
      spawn do
        metrics_server = HTTP::Server.new([
          HTTP::StaticFileHandler.new(".", fallthrough: true),
          HTTP::Handler::HandlerProc.new do |context|
            if context.request.path == "/metrics"
              context.response.content_type = "text/plain; version=0.0.4"
              context.response.print PrometheusExporter::Client.metrics
            else
              context.response.status = HTTP::Status::NOT_FOUND
            end
          end
        ])

        Log.info { "Worker metrics server listening on :9090" }
        metrics_server.bind_tcp "0.0.0.0", 9090
        metrics_server.listen
      end

      # ... rest of worker setup
      JoobQ.configure do |config|
        # ... configuration
      end

      JoobQ.forge
    end
  end
end
```

### Worker Deployment Changes

```hcl
# apps/crystalshards/terraform/resource.kubernetes_deployment.crystalshards_worker.tf
resource "kubernetes_deployment" "crystalshards_worker" {
  # ... existing config

  spec {
    template {
      spec {
        container {
          name  = "worker"
          # ... existing config

          # Add metrics port
          port {
            name           = "metrics"
            container_port = 9090
            protocol       = "TCP"
          }
        }
      }
    }
  }
}
```

### Worker Service

```hcl
# apps/crystalshards/terraform/resource.kubernetes_service.crystalshards_worker.tf
resource "kubernetes_service" "crystalshards_worker" {
  metadata {
    name      = "crystalshards-worker"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
    labels = {
      app       = "crystalshards"
      component = "worker"
    }
  }

  spec {
    selector = {
      app       = "crystalshards"
      component = "worker"
    }

    port {
      port        = 9090
      target_port = 9090
      protocol    = "TCP"
      name        = "metrics"
    }

    type = "ClusterIP"
  }
}
```

### Worker ServiceMonitor

```hcl
# apps/crystalshards/terraform/resource.kubectl_manifest.servicemonitor_worker.tf
resource "kubectl_manifest" "crystalshards_worker_servicemonitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "crystalshards-worker"
      namespace = kubernetes_namespace.crystalshards.metadata[0].name
      labels = {
        app       = "crystalshards"
        component = "worker"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app       = "crystalshards"
          component = "worker"
        }
      }
      endpoints = [{
        port     = "metrics"
        interval = "30s"
        path     = "/metrics"
      }]
    }
  })

  depends_on = [kubernetes_service.crystalshards_worker]
}
```

---

## Verification Checklist

After implementation, verify:

- [ ] All 4 applications have prometheus-exporter in shard.yml
- [ ] All 4 applications have middleware configured
- [ ] All 4 applications respond to GET /metrics with Prometheus format
- [ ] Worker has separate metrics HTTP server on port 9090
- [ ] Worker responds to GET /metrics on port 9090
- [ ] All ServiceMonitors show as "Up" in Prometheus UI
- [ ] Prometheus targets page shows all 5 endpoints (4 apps + 1 worker)
- [ ] Basic metrics visible in Grafana (http_requests_total, etc.)
- [ ] No errors in Prometheus logs about failed scrapes

---

## Conclusion

While the monitoring infrastructure (Prometheus, Grafana, ServiceMonitors) is deployed and ready, **all Lucky applications are currently missing metrics instrumentation**. This is a critical gap that must be addressed before deployment to production.

The immediate recommendation is to implement the prometheus-exporter library across all applications with the basic HTTP request metrics. This provides foundational RED metrics (Rate, Errors, Duration) that are essential for production observability.

Additional custom metrics can be added incrementally after the basic foundation is in place.

**Status**: BLOCKED - Deployment should not proceed until P0 metrics implementation is complete.
