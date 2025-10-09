# Runbook: Documentation Build Failures

## Severity: P3 - LOW

## Symptoms
- Documentation not being published
- BuildDocsWorker failing
- Missing documentation for new shard versions
- Build errors in worker logs

## Impact
- Users cannot view documentation for new versions
- Documentation site incomplete
- Poor user experience for shard authors

## Investigation

```bash
# Check worker logs for build errors
kubectl logs -n crystalshards -l app=crystalshards-workers --tail=200 | grep -i "BuildDocsWorker"

# Check specific failed build
kubectl logs -n crystalshards -l app=crystalshards-workers --tail=500 | grep -A 20 "BuildDocsWorker.*error"

# Check Redis for failed jobs
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli LRANGE joobq:default:failed 0 -1 | grep BuildDocs

# Check MinIO connectivity
kubectl exec -n crystalshards deployment/crystalshards-workers -- \
  sh -c 'echo "Testing MinIO" && curl -I http://minio.infrastructure.svc.cluster.local'
```

## Common Causes & Resolutions

### Crystal Compilation Errors

```bash
# Shard has syntax errors or incompatible Crystal version
# Review worker logs for specific error
kubectl logs -n crystalshards <worker-pod> | grep -A 30 "crystal doc"

# Resolution: Contact shard author to fix issues
# Or: Skip this version and mark as failed in database
```

### Missing Dependencies

```bash
# Shard.yml has dependencies that don't exist
# Worker logs will show "Shard not found" errors

# Resolution: Verify shard dependencies exist
# May need to index dependencies first
```

### Timeout

```bash
# Large shards may exceed build timeout
# Check worker configuration for timeout settings

# Increase timeout in worker configuration
kubectl edit deployment crystalshards-workers -n crystalshards
# Update DOCS_BUILD_TIMEOUT environment variable
```

### MinIO Upload Failure

```bash
# Check MinIO status
kubectl get pods -n infrastructure -l app=minio

# Test upload
kubectl exec -n crystalshards deployment/crystalshards-workers -- \
  sh -c 'echo "test" | mc pipe minio/crystaldocs/test.txt'

# Resolution: Fix MinIO connectivity (see minio-unavailable.md)
```

## Resolution

```bash
# Retry specific failed build
kubectl exec -n crystalshards deployment/crystalshards-api -- \
  crystal eval 'require "./src/workers/build_docs_worker"; BuildDocsWorker.new.perform(shard_id: <id>, version_id: <ver>)'

# Skip broken builds
kubectl exec -n infrastructure deployment/redis-master -- \
  redis-cli LREM joobq:default:failed 1 "*BuildDocsWorker*shard_id:<id>*"

# Restart workers if system issue
kubectl rollout restart deployment/crystalshards-workers -n crystalshards
```

## Prevention

- Validate shard.yml before queueing build
- Set appropriate timeouts
- Implement build sandboxing
- Monitor build success rate
- Alert on failure rate > 10%

## Related Runbooks
- [Worker Queue Backlog](worker-queue-backlog.md)
- [MinIO Unavailable](minio-unavailable.md)

## Revision History
- 2025-10-09: Created by CrystalShards Agent
