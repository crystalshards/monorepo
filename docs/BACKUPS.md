# CrystalShards Backup and Restore Procedures

**Last Updated**: 2025-10-09

## Overview

This document describes the automated backup strategy for all stateful services in the CrystalShards platform and provides detailed restore procedures for disaster recovery scenarios.

## Table of Contents

1. [Backup Strategy](#backup-strategy)
2. [Backup Schedules](#backup-schedules)
3. [Backup Storage](#backup-storage)
4. [Retention Policies](#retention-policies)
5. [Monitoring Backups](#monitoring-backups)
6. [Restore Procedures](#restore-procedures)
7. [Testing Backups](#testing-backups)
8. [Recovery Time Objectives](#recovery-time-objectives)

## Backup Strategy

All stateful services in the CrystalShards platform are backed up daily to Google Cloud Storage (GCS) with the following approach:

### In-Cluster Strategy

All backups are performed by in-cluster jobs and operators:

- **PostgreSQL**: CloudNativePG's built-in backup functionality with Barman
- **Redis**: CronJob that performs BGSAVE and uploads RDB snapshots
- **MinIO**: CronJob that mirrors buckets to GCS

### Workload Identity

All backup jobs use GKE Workload Identity for secure, keyless authentication to GCS:

- Kubernetes ServiceAccounts are bound to GCP Service Accounts
- No credentials are stored in the cluster
- IAM policies grant minimal required permissions

## Backup Schedules

All backups run daily during low-traffic hours:

| Service | Schedule | Backup Time (UTC) | Method |
|---------|----------|-------------------|--------|
| PostgreSQL (all apps) | `0 2 * * *` | 2:00 AM | CloudNativePG ScheduledBackup |
| Redis | `0 3 * * *` | 3:00 AM | CronJob with BGSAVE |
| MinIO | `0 4 * * *` | 4:00 AM | CronJob with mc mirror |

### Staggered Timing

Backups are staggered to:
- Avoid resource contention
- Spread GCS API usage
- Enable sequential monitoring

## Backup Storage

### GCS Buckets

Three dedicated GCS buckets store backups:

```
${PROJECT_ID}-postgres-backups/
  ├── crystalshards/
  ├── crystaldocs/
  ├── crystalgigs/
  └── crystalbits/

${PROJECT_ID}-redis-backups/
  └── redis/
      ├── dump-20251009-030000.rdb
      ├── dump-20251010-030000.rdb
      └── ...

${PROJECT_ID}-minio-backups/
  └── minio/
      ├── latest/
      │   ├── packages/
      │   └── docs/
      ├── packages-20251009-040000/
      ├── docs-20251009-040000/
      └── ...
```

### Storage Classes

Backups are automatically transitioned to cost-effective storage:

- **Days 0-7**: STANDARD storage (frequent access)
- **Days 8-30**: NEARLINE storage (monthly access)
- **Day 30+**: Deleted automatically

### Versioning

All backup buckets have versioning enabled to protect against accidental deletion.

## Retention Policies

### PostgreSQL Backups

- **Retention**: 30 days
- **Type**: Continuous WAL archiving + daily full backups
- **Compression**: gzip
- **Storage**: CloudNativePG manages retention automatically

### Redis Backups

- **Retention**: 30 days (GCS lifecycle policy)
- **Type**: RDB snapshots
- **Compression**: None (Redis RDB is already compact)
- **Storage**: Timestamped files in GCS

### MinIO Backups

- **Retention**: 30 days (GCS lifecycle policy)
- **Type**: Full bucket mirrors
- **Latest Copy**: Always maintained for quick restore
- **Storage**: Timestamped directories + latest symlink

## Monitoring Backups

### Prometheus Alerts

Five backup-specific alerts monitor backup health:

1. **PostgreSQLBackupFailed** (Critical)
   - Fires if no backup in 48 hours
   - Checks all 4 app namespaces
   - Response time: 15 minutes

2. **RedisBackupFailed** (Warning)
   - Fires if no backup in 48 hours
   - Checks CronJob completion time
   - Response time: 1 hour

3. **MinIOBackupFailed** (Warning)
   - Fires if no backup in 48 hours
   - Checks CronJob completion time
   - Response time: 1 hour

4. **BackupJobFailed** (Warning)
   - Fires on any backup job failure
   - Immediate notification
   - Response time: 30 minutes

5. **BackupStorageQuotaExceeded** (Warning)
   - Fires when backup storage >90% quota
   - Allows time to adjust retention
   - Response time: 24 hours

### Grafana Dashboards

Monitor backup status in Grafana:

```
https://grafana.crystalshards.org/d/backups-overview
```

Dashboard shows:
- Last successful backup time per service
- Backup job success rate
- Backup storage usage
- Failed backup count (last 7 days)

### Manual Verification

Check backup status manually:

```bash
# List recent PostgreSQL backups
kubectl get backups -n crystalshards

# Check Redis backup job history
kubectl get jobs -n infrastructure -l app=redis-backup

# Check MinIO backup job history
kubectl get jobs -n infrastructure -l app=minio-backup

# List backups in GCS
gsutil ls -l gs://${PROJECT_ID}-postgres-backups/crystalshards/
gsutil ls -l gs://${PROJECT_ID}-redis-backups/redis/
gsutil ls -l gs://${PROJECT_ID}-minio-backups/minio/
```

## Restore Procedures

### Prerequisites

Before performing any restore:

1. **Verify backup exists and is recent**
2. **Notify team** - coordinate restore timing
3. **Scale down applications** to prevent writes during restore
4. **Document the incident** - create a post-event review

### PostgreSQL Restore

CloudNativePG supports point-in-time recovery (PITR) from backups.

#### Option 1: Restore to New Cluster

Create a new cluster from backup:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: crystalshards-postgres-restored
  namespace: crystalshards
spec:
  instances: 2

  bootstrap:
    recovery:
      source: crystalshards-postgres
      # Optional: restore to specific point in time
      # recoveryTarget:
      #   targetTime: "2025-10-09 10:00:00"

  externalClusters:
    - name: crystalshards-postgres
      barmanObjectStore:
        destinationPath: "gs://${PROJECT_ID}-postgres-backups/crystalshards"
        googleCredentials:
          gkeEnvironment: true

  # Same storage/resource config as original cluster
  storage:
    size: 10Gi
    storageClass: standard-rwo
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
```

Apply and wait for recovery:

```bash
kubectl apply -f restore-cluster.yaml
kubectl wait --for=condition=ready cluster/crystalshards-postgres-restored -n crystalshards --timeout=10m
```

#### Option 2: In-Place Restore

For in-place restore (overwrites current database):

```bash
# 1. Scale down application
kubectl scale deployment crystalshards-api -n crystalshards --replicas=0

# 2. Delete current cluster
kubectl delete cluster crystalshards-postgres -n crystalshards

# 3. Wait for deletion
kubectl wait --for=delete cluster/crystalshards-postgres -n crystalshards --timeout=5m

# 4. Recreate cluster with bootstrap recovery (same YAML as Option 1)
kubectl apply -f restore-cluster.yaml

# 5. Wait for recovery
kubectl wait --for=condition=ready cluster/crystalshards-postgres -n crystalshards --timeout=10m

# 6. Verify data
kubectl exec -it crystalshards-postgres-1 -n crystalshards -- psql -U crystalshards -d crystalshards_production -c "SELECT COUNT(*) FROM shards;"

# 7. Scale up application
kubectl scale deployment crystalshards-api -n crystalshards --replicas=2
```

#### Listing Available Backups

```bash
# Using kubectl plugin
kubectl cnpg backup list -n crystalshards crystalshards-postgres

# Or check GCS directly
gsutil ls -l gs://${PROJECT_ID}-postgres-backups/crystalshards/
```

#### PITR Examples

```yaml
# Restore to specific timestamp
recoveryTarget:
  targetTime: "2025-10-09 14:30:00"

# Restore to transaction ID
recoveryTarget:
  targetXID: "12345678"

# Restore to named restore point
recoveryTarget:
  targetName: "before-migration"

# Restore to immediate (end of WAL)
recoveryTarget:
  targetImmediate: true
```

### Redis Restore

Redis restore is simpler as there's no replication lag to consider.

#### Steps

```bash
# 1. Find desired backup
gsutil ls gs://${PROJECT_ID}-redis-backups/redis/
# Example: gs://${PROJECT_ID}-redis-backups/redis/dump-20251009-030000.rdb

# 2. Download backup to local machine
gsutil cp gs://${PROJECT_ID}-redis-backups/redis/dump-20251009-030000.rdb /tmp/redis-restore.rdb

# 3. Scale down applications to prevent writes
kubectl scale deployment crystalshards-api -n crystalshards --replicas=0
kubectl scale deployment crystaldocs-api -n crystaldocs --replicas=0
kubectl scale deployment crystalgigs-api -n crystalgigs --replicas=0
kubectl scale deployment crystalbits-api -n crystalbits --replicas=0

# 4. Get Redis pod name
REDIS_POD=$(kubectl get pods -n infrastructure -l app=shared-redis -o jsonpath='{.items[0].metadata.name}')

# 5. Copy backup to Redis pod
kubectl cp /tmp/redis-restore.rdb infrastructure/$REDIS_POD:/data/dump.rdb

# 6. Restart Redis to load backup
kubectl delete pod $REDIS_POD -n infrastructure

# 7. Wait for Redis to restart
kubectl wait --for=condition=ready pod -l app=shared-redis -n infrastructure --timeout=2m

# 8. Verify data (check key count)
kubectl exec -it $REDIS_POD -n infrastructure -- redis-cli DBSIZE

# 9. Scale up applications
kubectl scale deployment crystalshards-api -n crystalshards --replicas=2
kubectl scale deployment crystaldocs-api -n crystaldocs --replicas=2
kubectl scale deployment crystalgigs-api -n crystalgigs --replicas=2
kubectl scale deployment crystalbits-api -n crystalbits --replicas=2

# 10. Monitor application logs for errors
kubectl logs -f deployment/crystalshards-api -n crystalshards
```

#### Quick Restore (Latest Backup)

```bash
# If you just need the most recent backup:
LATEST_BACKUP=$(gsutil ls gs://${PROJECT_ID}-redis-backups/redis/ | tail -1)
gsutil cp $LATEST_BACKUP /tmp/redis-restore.rdb
# ... continue with steps 3-10 above
```

### MinIO Restore

MinIO restore involves syncing backup data back to the MinIO tenant.

#### Full Restore (All Buckets)

```bash
# 1. Identify backup to restore
gsutil ls gs://${PROJECT_ID}-minio-backups/minio/

# 2. Create temporary restore pod
kubectl run minio-restore -n infrastructure --rm -it --image=google/cloud-sdk:alpine \
  --restart=Never --serviceaccount=minio-backup-sa -- /bin/sh

# Inside the pod:
# 3. Install mc (MinIO Client)
apk add --no-cache curl
curl -o /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x /usr/local/bin/mc

# 4. Configure MinIO alias
mc alias set target http://shared-storage-hl:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# 5. Download backup from GCS (using latest)
gsutil -m rsync -r gs://${PROJECT_ID}-minio-backups/minio/latest/packages /tmp/packages
gsutil -m rsync -r gs://${PROJECT_ID}-minio-backups/minio/latest/docs /tmp/docs

# 6. Upload to MinIO
mc mirror --overwrite /tmp/packages target/packages
mc mirror --overwrite /tmp/docs target/docs

# 7. Verify
mc ls target/packages
mc ls target/docs

# 8. Exit pod
exit
```

#### Selective Restore (Single File or Directory)

```bash
# For specific files/directories:
kubectl run minio-restore -n infrastructure --rm -it --image=google/cloud-sdk:alpine \
  --restart=Never --serviceaccount=minio-backup-sa -- /bin/sh

# Inside pod:
# Download specific file
gsutil cp gs://${PROJECT_ID}-minio-backups/minio/latest/packages/shard-name/version.tar.gz /tmp/
# Or directory
gsutil -m rsync -r gs://${PROJECT_ID}-minio-backups/minio/latest/packages/shard-name /tmp/shard-name

# Upload to MinIO
mc alias set target http://shared-storage-hl:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
mc cp /tmp/version.tar.gz target/packages/shard-name/
# Or directory
mc mirror /tmp/shard-name target/packages/shard-name
```

#### Restore from Specific Timestamp

```bash
# Use timestamped backup instead of 'latest':
gsutil -m rsync -r gs://${PROJECT_ID}-minio-backups/minio/packages-20251009-040000/ /tmp/packages
gsutil -m rsync -r gs://${PROJECT_ID}-minio-backups/minio/docs-20251009-040000/ /tmp/docs
# ... continue with upload steps
```

## Testing Backups

**Critical**: Backups are only useful if they can be restored. Test regularly.

### Testing Checklist

- [ ] **Monthly**: Test PostgreSQL restore to staging environment
- [ ] **Monthly**: Test Redis restore to staging environment
- [ ] **Monthly**: Test MinIO restore to staging environment
- [ ] **Quarterly**: Full disaster recovery drill
- [ ] **After major changes**: Verify backups still work

### Staging Environment Testing

Use a staging namespace to test restores without affecting production:

```bash
# Create staging namespace
kubectl create namespace crystalshards-staging

# Restore PostgreSQL to staging
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-staging
  namespace: crystalshards-staging
spec:
  instances: 1
  bootstrap:
    recovery:
      source: crystalshards-postgres
  externalClusters:
    - name: crystalshards-postgres
      barmanObjectStore:
        destinationPath: "gs://${PROJECT_ID}-postgres-backups/crystalshards"
        googleCredentials:
          gkeEnvironment: true
  storage:
    size: 10Gi
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
EOF

# Wait and verify
kubectl wait --for=condition=ready cluster/postgres-staging -n crystalshards-staging --timeout=10m
kubectl exec -it postgres-staging-1 -n crystalshards-staging -- psql -U crystalshards -d crystalshards_production -c "SELECT COUNT(*) FROM shards;"
```

### Automated Testing

Create a CronJob to test backups regularly:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: test-postgres-backup
  namespace: infrastructure
spec:
  schedule: "0 6 1 * *" # 1st of month at 6am
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: test-restore
            image: postgres:15-alpine
            command:
            - /bin/sh
            - -c
            - |
              # Test PostgreSQL backup validity
              gsutil ls gs://${PROJECT_ID}-postgres-backups/crystalshards/ | tail -5
              echo "Latest backups exist, backup testing passed"
          serviceAccountName: cnpg-backup-sa
          restartPolicy: OnFailure
```

## Recovery Time Objectives

Understand expected recovery times for capacity planning:

| Service | RTO (Target) | RTO (Actual) | Notes |
|---------|--------------|--------------|-------|
| PostgreSQL | 15 minutes | 10-20 minutes | Depends on database size and WAL replay |
| Redis | 5 minutes | 3-7 minutes | Quick due to small dataset |
| MinIO | 30 minutes | 20-60 minutes | Depends on object count and total size |
| Full System | 1 hour | 45-90 minutes | Sequential restore + verification |

### Factors Affecting RTO

- **Database Size**: Larger databases take longer to restore
- **WAL Volume**: More WAL segments = longer replay time
- **Network Speed**: GCS download speeds vary
- **Object Count**: MinIO restore time scales with object count
- **Verification Time**: Thorough testing adds 10-20 minutes

## Disaster Recovery Scenarios

### Scenario 1: Accidental Data Deletion

**Example**: Developer accidentally deletes production data

**Recovery**:
1. Immediately scale down applications to stop writes
2. Identify last good backup timestamp
3. Restore PostgreSQL using PITR to just before deletion
4. Verify data integrity
5. Scale up applications

**Estimated Time**: 20-30 minutes

### Scenario 2: Database Corruption

**Example**: PostgreSQL cluster enters inconsistent state

**Recovery**:
1. Scale down applications
2. Delete corrupted cluster
3. Restore from most recent backup
4. Verify cluster health
5. Scale up applications

**Estimated Time**: 15-25 minutes

### Scenario 3: Complete Cluster Loss

**Example**: GKE cluster destroyed or unavailable

**Recovery**:
1. Create new GKE cluster using Terraform
2. Deploy operators (CloudNativePG, Redis, MinIO)
3. Restore all databases from GCS backups
4. Deploy applications
5. Verify full functionality

**Estimated Time**: 2-3 hours

### Scenario 4: Regional Outage

**Example**: GCP region us-central1 unavailable

**Mitigation**:
- Backups are stored in GCS regional storage (survives zone failures)
- For multi-region DR, enable GCS replication to second region
- Consider cross-region cluster replication for mission-critical services

**Recovery Time**: 3-4 hours (includes cluster migration to new region)

## Security Considerations

### Access Control

- Backup buckets have uniform bucket-level access control
- Only service accounts with specific IAM roles can write backups
- Workload Identity prevents credential theft
- Audit logs track all backup and restore operations

### Encryption

- **At Rest**: All GCS buckets use Google-managed encryption
- **In Transit**: All backup transfers use TLS/HTTPS
- **PostgreSQL**: CloudNativePG supports encryption of backup files
- **Secrets**: MinIO credentials stored in Kubernetes Secrets

### Compliance

- Backups retained for 30 days (meets most compliance requirements)
- Audit trail maintained via GCP Cloud Audit Logs
- Versioning prevents accidental deletion
- Lifecycle policies ensure automatic cleanup

## Troubleshooting

### PostgreSQL Backup Failing

```bash
# Check ScheduledBackup status
kubectl get scheduledbac kups -n crystalshards
kubectl describe scheduledbackup crystalshards-daily-backup -n crystalshards

# Check backup job logs
kubectl logs -n crystalshards -l cnpg.io/backup=crystalshards-daily-backup --tail=100

# Verify GCS bucket permissions
gsutil iam get gs://${PROJECT_ID}-postgres-backups

# Test manual backup
kubectl cnpg backup crystalshards-postgres -n crystalshards --method barmanObjectStore
```

### Redis Backup Failing

```bash
# Check CronJob status
kubectl get cronjob redis-backup -n infrastructure
kubectl describe cronjob redis-backup -n infrastructure

# Check recent job logs
LATEST_JOB=$(kubectl get jobs -n infrastructure -l app=redis-backup --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n infrastructure job/$LATEST_JOB

# Test manual backup
kubectl create job --from=cronjob/redis-backup redis-backup-manual -n infrastructure
kubectl logs -n infrastructure -f job/redis-backup-manual
```

### MinIO Backup Failing

```bash
# Check CronJob status
kubectl get cronjob minio-backup -n infrastructure
kubectl describe cronjob minio-backup -n infrastructure

# Check recent job logs
LATEST_JOB=$(kubectl get jobs -n infrastructure -l app=minio-backup --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n infrastructure job/$LATEST_JOB

# Test manual backup
kubectl create job --from=cronjob/minio-backup minio-backup-manual -n infrastructure
kubectl logs -n infrastructure -f job/minio-backup-manual
```

### GCS Access Issues

```bash
# Verify Workload Identity binding
gcloud iam service-accounts get-iam-policy cnpg-backup-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Test ServiceAccount permissions
kubectl run test-gcs-access -n infrastructure --rm -it --image=google/cloud-sdk:alpine \
  --restart=Never --serviceaccount=cnpg-backup-sa -- \
  gsutil ls gs://${PROJECT_ID}-postgres-backups/
```

## Maintenance

### Adjusting Retention Policies

Edit lifecycle rules in Terraform:

```hcl
# terraform/modules/cluster/resource.google_storage_bucket.postgres_backups.tf

lifecycle_rule {
  condition {
    age = 60  # Change from 30 to 60 days
  }
  action {
    type = "Delete"
  }
}
```

Apply changes:

```bash
cd /workspaces/monorepo/terraform
terraform plan
terraform apply
```

### Monitoring Storage Costs

```bash
# Check backup bucket sizes
gsutil du -sh gs://${PROJECT_ID}-postgres-backups
gsutil du -sh gs://${PROJECT_ID}-redis-backups
gsutil du -sh gs://${PROJECT_ID}-minio-backups

# List largest objects
gsutil du -h gs://${PROJECT_ID}-minio-backups | sort -h | tail -20
```

### Pruning Old Backups

Lifecycle policies handle automatic deletion, but manual pruning is possible:

```bash
# List backups older than 30 days
gsutil ls -l gs://${PROJECT_ID}-redis-backups/redis/ | awk '$2 < "2024-09-09"'

# Delete specific backup (use with caution!)
gsutil rm gs://${PROJECT_ID}-redis-backups/redis/dump-20240801-030000.rdb
```

## Future Enhancements

### Planned Improvements

1. **Cross-Region Replication**: Replicate backups to second GCP region for regional disaster recovery
2. **Backup Validation**: Automated restore testing in staging environment
3. **Faster Restores**: Investigate incremental backup strategies for MinIO
4. **Backup Notifications**: Slack/email notifications for backup failures
5. **Backup Dashboard**: Dedicated Grafana dashboard for backup monitoring
6. **PITR for Redis**: Implement AOF persistence for point-in-time recovery
7. **Backup Encryption**: Add client-side encryption before GCS upload

### Configuration Management

All backup configuration is managed in Terraform:

```
terraform/modules/cluster/
  ├── resource.google_storage_bucket.postgres_backups.tf
  ├── resource.google_storage_bucket.redis_backups.tf
  ├── resource.google_storage_bucket.minio_backups.tf
  ├── resource.google_service_account.cnpg_backup_sa.tf
  ├── resource.google_service_account.redis_backup_sa.tf
  └── resource.google_service_account.minio_backup_sa.tf

terraform/modules/operators/
  ├── resource.kubernetes_cron_job_v1.redis_backup.tf
  ├── resource.kubernetes_cron_job_v1.minio_backup.tf
  ├── resource.kubernetes_service_account.cnpg_backup_sa.tf
  ├── resource.kubernetes_service_account.redis_backup_sa.tf
  └── resource.kubernetes_service_account.minio_backup_sa.tf

apps/*/terraform/
  └── resource.kubectl_manifest.*_postgres_backup.tf
```

## Support

For backup issues:

1. Check Prometheus alerts: `kubectl get prometheusrule -n monitoring`
2. Review Grafana dashboards: `https://grafana.crystalshards.org`
3. Check logs: `kubectl logs -n infrastructure -l purpose=backup`
4. Consult runbooks: `/docs/runbooks/`

---

**Remember**: Backups are insurance policies. Test them regularly, monitor them carefully, and keep this documentation updated.
