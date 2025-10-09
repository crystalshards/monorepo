# Quick Reference Guide

Essential commands and access patterns for CrystalShards production operations.

## Table of Contents

- [Cluster Access](#cluster-access)
- [Common kubectl Commands](#common-kubectl-commands)
- [Database Commands](#database-commands)
- [Redis Commands](#redis-commands)
- [MinIO Commands](#minio-commands)
- [Monitoring Access](#monitoring-access)
- [Application Logs](#application-logs)
- [Emergency Procedures](#emergency-procedures)

## Cluster Access

### Connect to GKE Cluster

```bash
# Configure kubectl context
gcloud container clusters get-credentials crystalshards-production \
  --region us-central1 \
  --project <project-id>

# Verify connection
kubectl cluster-info
kubectl get nodes
```

### Set Default Namespace

```bash
# Set default namespace for session
kubectl config set-context --current --namespace=crystalshards

# Or use kubens (if installed)
kubens crystalshards
```

## Common kubectl Commands

### Viewing Resources

```bash
# All pods across namespaces
kubectl get pods --all-namespaces

# Pods in specific namespace
kubectl get pods -n crystalshards

# Wide output with more details
kubectl get pods -n crystalshards -o wide

# Watch pods in real-time
watch kubectl get pods -n crystalshards

# Deployments
kubectl get deployments -n crystalshards

# Services
kubectl get svc -n crystalshards

# Ingress/Gateway
kubectl get gateway -n infrastructure
kubectl get httproute --all-namespaces
```

### Describing Resources

```bash
# Detailed pod information
kubectl describe pod <pod-name> -n crystalshards

# Deployment details
kubectl describe deployment crystalshards-api -n crystalshards

# Service details
kubectl describe svc crystalshards -n crystalshards

# Check events
kubectl get events -n crystalshards --sort-by='.lastTimestamp'
```

### Resource Usage

```bash
# Pod resource usage
kubectl top pods -n crystalshards

# Node resource usage
kubectl top nodes

# All namespaces
kubectl top pods --all-namespaces
```

### Scaling

```bash
# Scale deployment
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=5

# Check HPA
kubectl get hpa -n crystalshards

# Edit HPA
kubectl edit hpa crystalshards-api -n crystalshards
```

### Rollouts

```bash
# Check rollout status
kubectl rollout status deployment/crystalshards-api -n crystalshards

# Rollout history
kubectl rollout history deployment/crystalshards-api -n crystalshards

# Rollback
kubectl rollout undo deployment/crystalshards-api -n crystalshards

# Rollback to specific revision
kubectl rollout undo deployment/crystalshards-api -n crystalshards --to-revision=5

# Restart deployment (rolling restart)
kubectl rollout restart deployment/crystalshards-api -n crystalshards

# Pause rollout
kubectl rollout pause deployment/crystalshards-api -n crystalshards

# Resume rollout
kubectl rollout resume deployment/crystalshards-api -n crystalshards
```

### Logs

```bash
# Current logs
kubectl logs <pod-name> -n crystalshards

# Previous container logs (after crash)
kubectl logs <pod-name> -n crystalshards --previous

# Tail logs
kubectl logs <pod-name> -n crystalshards --tail=100

# Follow logs
kubectl logs <pod-name> -n crystalshards -f

# All containers in pod
kubectl logs <pod-name> -n crystalshards --all-containers=true

# Logs from all pods with label
kubectl logs -n crystalshards -l app=crystalshards-api --tail=50

# Logs with timestamps
kubectl logs <pod-name> -n crystalshards --timestamps
```

### Exec into Pods

```bash
# Exec into pod
kubectl exec -it <pod-name> -n crystalshards -- sh

# Run single command
kubectl exec <pod-name> -n crystalshards -- ls -la /app

# Exec into specific container
kubectl exec -it <pod-name> -n crystalshards -c <container-name> -- sh
```

### Port Forwarding

```bash
# Forward local port to pod
kubectl port-forward <pod-name> -n crystalshards 3000:3000

# Forward to deployment
kubectl port-forward deployment/crystalshards-api -n crystalshards 3000:3000

# Forward to service
kubectl port-forward svc/crystalshards -n crystalshards 3000:3000

# Background port forward
kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090 &
```

### Secrets

```bash
# List secrets
kubectl get secrets -n crystalshards

# Describe secret (doesn't show values)
kubectl describe secret crystalshards-secrets -n crystalshards

# Get secret values (base64 encoded)
kubectl get secret crystalshards-secrets -n crystalshards -o yaml

# Decode specific secret key
kubectl get secret crystalshards-secrets -n crystalshards -o jsonpath='{.data.DATABASE_URL}' | base64 -d

# Edit secret
kubectl edit secret crystalshards-secrets -n crystalshards
```

## Database Commands

### CloudNativePG Cluster

```bash
# Check cluster status
kubectl get cluster -n crystalshards

# Detailed cluster info
kubectl describe cluster crystalshards-postgres -n crystalshards

# Get primary pod
kubectl get pods -n crystalshards -l cnpg.io/cluster=crystalshards-postgres,role=primary

# Get replica pods
kubectl get pods -n crystalshards -l cnpg.io/cluster=crystalshards-postgres,role=replica
```

### PostgreSQL Queries

```bash
# Connect to database
kubectl exec -it -n crystalshards <postgres-pod> -- psql -U postgres -d crystalshards

# Run query from command line
kubectl exec -n crystalshards <postgres-pod> -- \
  psql -U postgres -d crystalshards -c "SELECT count(*) FROM shards;"

# Using DATABASE_URL from app pod
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT version();"

# Check connections
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT count(*) FROM pg_stat_activity;"

# Active queries
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pid, state, query FROM pg_stat_activity WHERE state != 'idle';"

# Kill query
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  psql "$DATABASE_URL" -c "SELECT pg_terminate_backend(<pid>);"
```

### Database Backups

```bash
# List backups
kubectl get backup -n crystalshards

# Describe backup
kubectl describe backup <backup-name> -n crystalshards

# Trigger manual backup
kubectl cnpg backup crystalshards-postgres -n crystalshards
```

## Redis Commands

### Redis Connection

```bash
# Connect to Redis
kubectl exec -it -n infrastructure deployment/redis-master -- redis-cli

# Ping
kubectl exec -n infrastructure deployment/redis-master -- redis-cli PING

# Info
kubectl exec -n infrastructure deployment/redis-master -- redis-cli INFO

# Memory info
kubectl exec -n infrastructure deployment/redis-master -- redis-cli INFO memory

# Stats
kubectl exec -n infrastructure deployment/redis-master -- redis-cli INFO stats
```

### Redis Operations

```bash
# List all keys (careful in production!)
kubectl exec -n infrastructure deployment/redis-master -- redis-cli KEYS "*"

# Count keys
kubectl exec -n infrastructure deployment/redis-master -- redis-cli DBSIZE

# Scan keys (safer than KEYS)
kubectl exec -n infrastructure deployment/redis-master -- redis-cli --scan --pattern "shards:*"

# Get key value
kubectl exec -n infrastructure deployment/redis-master -- redis-cli GET "key:name"

# Delete key
kubectl exec -n infrastructure deployment/redis-master -- redis-cli DEL "key:name"

# Check TTL
kubectl exec -n infrastructure deployment/redis-master -- redis-cli TTL "key:name"

# Queue length (for JoobQ)
kubectl exec -n infrastructure deployment/redis-master -- redis-cli LLEN joobq:default:queue

# View queue contents (first 10)
kubectl exec -n infrastructure deployment/redis-master -- redis-cli LRANGE joobq:default:queue 0 9
```

### Redis Monitoring

```bash
# Monitor commands in real-time
kubectl exec -n infrastructure deployment/redis-master -- redis-cli MONITOR

# Slow log
kubectl exec -n infrastructure deployment/redis-master -- redis-cli SLOWLOG GET 10

# Client list
kubectl exec -n infrastructure deployment/redis-master -- redis-cli CLIENT LIST
```

## MinIO Commands

### MinIO Access

```bash
# Port forward MinIO console
kubectl port-forward -n infrastructure svc/minio-console 9001:9001

# Access in browser: http://localhost:9001

# Get MinIO credentials
kubectl get secret -n infrastructure minio-secret -o jsonpath='{.data.accesskey}' | base64 -d
kubectl get secret -n infrastructure minio-secret -o jsonpath='{.data.secretkey}' | base64 -d
```

### MinIO CLI (mc)

```bash
# Exec into MinIO pod
kubectl exec -it -n infrastructure minio-0 -- sh

# Configure mc alias
mc alias set minio http://localhost:9000 <access-key> <secret-key>

# List buckets
mc ls minio

# List objects in bucket
mc ls minio/crystalshards

# Copy file
mc cp /tmp/file.tar.gz minio/crystalshards/packages/

# Remove file
mc rm minio/crystalshards/packages/old-file.tar.gz

# Bucket info
mc stat minio/crystalshards
```

## Monitoring Access

### Prometheus

```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Access in browser: http://localhost:9090

# Query from CLI
kubectl run curl-test --image=curlimages/curl -i --rm --restart=Never -- \
  curl -s 'http://prometheus-operated.monitoring.svc:9090/api/v1/query?query=up'
```

### Grafana

```bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Access in browser: http://localhost:3000

# Get admin password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

### Loki (Logs)

```bash
# Port forward Loki
kubectl port-forward -n monitoring svc/loki-gateway 3100:80

# Query logs via API
curl -G -s 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query={namespace="crystalshards"}' | jq

# Query logs via LogCLI (if installed)
logcli query --addr=http://localhost:3100 '{namespace="crystalshards"}'
```

## Application Logs

### Application Namespaces

- crystalshards - Package registry
- crystaldocs - Documentation hosting
- crystalgigs - Job board
- crystalbits - Blog/newsletter

### Quick Log Access

```bash
# CrystalShards API
kubectl logs -n crystalshards -l app=crystalshards-api --tail=100 -f

# CrystalShards Workers
kubectl logs -n crystalshards -l app=crystalshards-workers --tail=100 -f

# CrystalDocs
kubectl logs -n crystaldocs -l app=crystaldocs-api --tail=100 -f

# CrystalGigs
kubectl logs -n crystalgigs -l app=crystalgigs-api --tail=100 -f

# CrystalBits
kubectl logs -n crystalbits -l app=crystalbits-api --tail=100 -f
```

### Filtering Logs

```bash
# Errors only
kubectl logs -n crystalshards -l app=crystalshards-api --tail=500 | grep -i error

# Specific endpoint
kubectl logs -n crystalshards -l app=crystalshards-api --tail=500 | grep "/api/shards"

# HTTP status codes
kubectl logs -n crystalshards -l app=crystalshards-api --tail=500 | grep "status=5"

# Time range (with timestamps)
kubectl logs -n crystalshards -l app=crystalshards-api --timestamps --since=1h

# Multiple grep filters
kubectl logs -n crystalshards -l app=crystalshards-api --tail=1000 | \
  grep -i error | grep -v "health" | tail -20
```

## Emergency Procedures

### Complete Service Restart

```bash
# Restart all CrystalShards components
kubectl rollout restart deployment/crystalshards-api -n crystalshards
kubectl rollout restart deployment/crystalshards-workers -n crystalshards

# Wait for rollout
kubectl rollout status deployment/crystalshards-api -n crystalshards
kubectl rollout status deployment/crystalshards-workers -n crystalshards
```

### Force Pod Restart

```bash
# Delete specific pod (deployment will recreate)
kubectl delete pod <pod-name> -n crystalshards

# Delete all pods for deployment (rolling restart)
kubectl delete pods -n crystalshards -l app=crystalshards-api
```

### Rollback Deployment

```bash
# Immediate rollback to previous version
kubectl rollout undo deployment/crystalshards-api -n crystalshards

# Check rollout status
kubectl rollout status deployment/crystalshards-api -n crystalshards

# Verify pods are healthy
kubectl get pods -n crystalshards -l app=crystalshards-api
```

### Scale to Zero (Emergency Stop)

```bash
# Scale down to stop processing
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=0

# Scale back up
kubectl scale deployment/crystalshards-api -n crystalshards --replicas=3
```

### Clear Job Queue

```bash
# Check queue size
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli LLEN joobq:default:queue

# Clear entire queue (DANGEROUS - use with caution)
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli DEL joobq:default:queue

# Clear failed jobs
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli DEL joobq:default:failed
```

### Certificate Emergency Renewal

```bash
# Delete certificate to force renewal
kubectl delete certificate crystalshards-tls -n crystalshards
kubectl delete secret crystalshards-tls-secret -n crystalshards

# Watch certificate recreate
watch kubectl get certificate -n crystalshards

# Check certificate request
kubectl get certificaterequest -n crystalshards
```

## Useful Aliases

Add these to your shell profile for faster operations:

```bash
# kubectl aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgd='kubectl get deployments'
alias kgs='kubectl get svc'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias ke='kubectl exec -it'
alias kpf='kubectl port-forward'

# Namespace-specific
alias kcs='kubectl -n crystalshards'
alias kcd='kubectl -n crystaldocs'
alias kcg='kubectl -n crystalgigs'
alias kcb='kubectl -n crystalbits'
alias kinfra='kubectl -n infrastructure'
alias kmon='kubectl -n monitoring'

# Common operations
alias kgpa='kubectl get pods --all-namespaces'
alias ktopn='kubectl top nodes'
alias ktopp='kubectl top pods'
alias kevents='kubectl get events --sort-by=.metadata.creationTimestamp'
```

## Additional Resources

- [Deployment Runbook](../../terraform/DEPLOYMENT_RUNBOOK.md)
- [Logging Documentation](../LOGGING.md)
- [Log Query Examples](../../terraform/modules/operators/LOG_QUERIES.md)
- [Rate Limiting Guide](../RATE_LIMITING.md)

---

Last Updated: 2025-10-09
