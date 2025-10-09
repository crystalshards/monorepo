# Loki Log Query Examples

This document contains useful LogQL queries for troubleshooting and monitoring the CrystalShards platform.

## LogQL Basics

LogQL is Loki's query language, similar to PromQL but for logs. It consists of:
- **Log stream selector**: `{label="value"}` - Filters log streams
- **Log pipeline**: `|= "text"` - Filters log lines
- **Parsers**: `| json` - Parses structured logs
- **Aggregations**: `count_over_time()` - Metrics from logs

## Application Logs

### All Logs from CrystalShards Application
```logql
{namespace="crystalshards"}
```

### All Logs from All Applications
```logql
{namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"}
```

### Logs from Specific App and Container
```logql
{namespace="crystalshards", container="api"}
```

### CrystalShards Worker Logs
```logql
{namespace="crystalshards", app="worker"}
```

## Error Tracking

### All Error Logs Across Applications
```logql
{namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"} |~ "(?i)(error|exception|fatal)"
```

### HTTP 5xx Errors
```logql
{namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"} |~ "status=5[0-9]{2}"
```

### HTTP 4xx Errors
```logql
{namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"} |~ "status=4[0-9]{2}"
```

### Database Connection Errors
```logql
{namespace=~".*"} |~ "(?i)(could not connect to server|connection refused|connection reset)"
```

### Redis Connection Errors
```logql
{namespace=~".*"} |~ "(?i)(redis.*error|connection to redis)"
```

## Performance Monitoring

### Slow HTTP Requests (>500ms)
```logql
{namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"} |~ "duration=[5-9][0-9]{2,}ms"
```

### Very Slow Requests (>1000ms)
```logql
{namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"} | regexp "duration=(?P<duration>[0-9]+)ms" | duration > 1000
```

### Database Slow Queries (>100ms)
```logql
{namespace=~".*"} |~ "(?i)(query took|execution time).*[1-9][0-9]{2,}ms"
```

## Worker Job Monitoring

### JoobQ Worker Job Execution
```logql
{namespace="crystalshards", app="worker"} |= "perform"
```

### Failed Worker Jobs
```logql
{namespace="crystalshards", app="worker"} |~ "(?i)(failed|error)" |= "job"
```

### IndexShardWorker Activity
```logql
{namespace="crystalshards", app="worker"} |= "IndexShardWorker"
```

### BuildDocsWorker Activity
```logql
{namespace="crystalshards", app="worker"} |= "BuildDocsWorker"
```

### UpdateDependenciesWorker Activity
```logql
{namespace="crystalshards", app="worker"} |= "UpdateDependenciesWorker"
```

## Infrastructure Logs

### PostgreSQL (CloudNativePG) Logs
```logql
{namespace="infrastructure"} |= "postgres"
```

### PostgreSQL Errors
```logql
{namespace="infrastructure"} |= "postgres" |~ "(?i)(error|fatal|panic)"
```

### PostgreSQL Connection Issues
```logql
{namespace="infrastructure"} |= "postgres" |~ "(?i)(connection|authentication failed)"
```

### Redis Logs
```logql
{namespace="infrastructure"} |= "redis"
```

### Redis Memory Issues
```logql
{namespace="infrastructure"} |= "redis" |~ "(?i)(memory|oom)"
```

### MinIO Logs
```logql
{namespace="infrastructure"} |= "minio"
```

### MinIO Errors
```logql
{namespace="infrastructure"} |= "minio" |~ "(?i)error"
```

## Ingress & Gateway Logs

### Envoy Gateway Logs
```logql
{namespace="envoy-gateway-system"}
```

### Ingress Access Logs
```logql
{namespace="envoy-gateway-system"} |~ "GET|POST|PUT|DELETE"
```

### Gateway Errors
```logql
{namespace="envoy-gateway-system"} |~ "(?i)error"
```

## Security & Authentication

### Authentication Failures
```logql
{namespace=~".*"} |~ "(?i)(authentication failed|unauthorized|forbidden)"
```

### Rate Limiting Events
```logql
{namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"} |~ "(?i)(rate limit|too many requests)"
```

### Suspicious Activity (SQL Injection, XSS attempts)
```logql
{namespace=~".*"} |~ "(?i)(union select|script>|<iframe|javascript:)"
```

## Aggregation Queries (Metrics from Logs)

### Error Rate by Namespace (last 5 minutes)
```logql
sum by (namespace) (rate({namespace=~".*"} |~ "(?i)error" [5m]))
```

### HTTP Request Count by Status Code
```logql
sum by (status) (count_over_time({namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"} | regexp "status=(?P<status>[0-9]{3})" [1h]))
```

### Top 10 Error Messages (last hour)
```logql
topk(10, sum by (msg) (count_over_time({namespace=~".*"} |~ "(?i)error" | regexp "(?P<msg>.*)" [1h])))
```

### Worker Job Processing Rate
```logql
sum(rate({namespace="crystalshards", app="worker"} |= "perform" [5m]))
```

## Troubleshooting Workflows

### Application Crash Investigation
1. Find crash time:
```logql
{namespace="crystalshards"} |~ "(?i)(crash|panic|fatal)"
```

2. Get context around crash (5 minutes before):
```logql
{namespace="crystalshards"} | line_format "{{.timestamp}} {{.message}}"
```

3. Check for resource issues:
```logql
{namespace="crystalshards"} |~ "(?i)(oom|memory|disk full)"
```

### Database Connection Pool Exhaustion
```logql
{namespace=~".*"} |~ "(?i)(connection pool|too many connections|connection timeout)"
```

### Redis Queue Backlog
```logql
{namespace="crystalshards"} |~ "(?i)(queue.*full|redis.*backlog)"
```

### Deployment Issues
```logql
{namespace=~"crystalshards|crystaldocs|crystalgigs|crystalbits"} |~ "(?i)(readiness|liveness|startup)" | line_format "{{.timestamp}} {{.pod}} {{.message}}"
```

## JSON Log Parsing

If your applications log in JSON format, you can parse and filter:

### Parse JSON Logs
```logql
{namespace="crystalshards"} | json
```

### Filter by JSON Field
```logql
{namespace="crystalshards"} | json | level="error"
```

### Extract and Filter by HTTP Method
```logql
{namespace="crystalshards"} | json | method="POST"
```

## Tips & Best Practices

1. **Use Time Ranges**: Always limit queries with time ranges for performance
   - Use the Grafana time picker or add ranges like `[5m]`, `[1h]`, `[24h]`

2. **Narrow Down Early**: Start with namespace/pod filters before text searches
   - Bad: `{namespace=~".*"} |= "error"`
   - Good: `{namespace="crystalshards"} |= "error"`

3. **Case-Insensitive Searches**: Use `(?i)` regex flag for case-insensitive matching
   - Example: `|~ "(?i)error"` matches "ERROR", "Error", "error"

4. **Combine Filters**: Chain multiple filters for precision
   - Example: `{namespace="crystalshards"} |= "api" |~ "error" != "deprecated"`

5. **Use Line Format**: Format output for readability
   - Example: `| line_format "{{.timestamp}} [{{.level}}] {{.message}}"`

6. **Aggregate for Alerts**: Use `count_over_time()` and `rate()` for alerting
   - Example: `sum(rate({namespace="crystalshards"} |~ "error" [5m])) > 10`

7. **Save Useful Queries**: Add frequently-used queries to Grafana dashboards

## Additional Resources

- **Loki Documentation**: https://grafana.com/docs/loki/latest/
- **LogQL Reference**: https://grafana.com/docs/loki/latest/logql/
- **Grafana Explore**: Use the Explore UI to test queries interactively
