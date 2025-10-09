# Runbook: MinIO Unavailable

## Severity: P1 - HIGH

## Alert Name
- Prometheus alert: `MinIODown`

## Symptoms
- Cannot connect to MinIO
- S3 API unavailable
- Package uploads/downloads failing

## Impact
- Cannot publish new shards
- Cannot access stored packages
- Documentation unavailable
- Critical feature outage

## Investigation

```bash
# Check MinIO tenant
kubectl get tenant -n infrastructure

# Check MinIO pods
kubectl get pods -n infrastructure -l v1.min.io/tenant=crystalshards

# Check logs
kubectl logs -n infrastructure -l v1.min.io/tenant=crystalshards --tail=100

# Check PVCs
kubectl get pvc -n infrastructure | grep minio
```

## Resolution

```bash
# Restart MinIO pods
kubectl delete pod -n infrastructure -l v1.min.io/tenant=crystalshards

# Check tenant configuration
kubectl describe tenant crystalshards -n infrastructure

# If tenant issue, recreate
kubectl delete tenant crystalshards -n infrastructure
# Reapply via Terraform
```

## Prevention
- Run multiple MinIO replicas
- Monitor disk usage
- Regular backup of bucket metadata
- Test failover scenarios

## Revision History
- 2025-10-09: Created by CrystalShards Agent
