# Runbook: MinIO High Error Rate

## Severity: P2 - MEDIUM

## Alert Name
- Prometheus alert: `MinIOHighErrorRate`

## Symptoms
- S3 API errors exceeding threshold
- Failed package/documentation uploads
- Failed downloads of shards or docs

## Impact
- Cannot publish new shards
- Cannot upload documentation
- Users cannot download packages
- Documentation not accessible

## Investigation

```bash
# Check MinIO pods
kubectl get pods -n infrastructure -l app=minio

# Check MinIO logs
kubectl logs -n infrastructure -l app=minio --tail=100 | grep -i error

# Check tenant status
kubectl get tenant -n infrastructure

# Test S3 API
kubectl run aws-cli --image=amazon/aws-cli -i --rm --restart=Never -- \
  s3 ls s3://crystalshards --endpoint-url http://minio.infrastructure.svc.cluster.local
```

## Resolution

```bash
# Restart MinIO pods
kubectl rollout restart statefulset/minio -n infrastructure

# Check disk space
kubectl exec -n infrastructure minio-0 -- df -h

# Clear old data if space issue
# (Implement retention policy in MinIO)
```

## Prevention
- Monitor disk space
- Implement retention policies
- Regular health checks
- Alert on error rate > 1%

## Revision History
- 2025-10-09: Created by CrystalShards Agent
