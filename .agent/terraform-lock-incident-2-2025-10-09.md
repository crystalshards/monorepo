# Terraform State Lock Incident #2 - Resolution Report

**Date**: 2025-10-09
**Time**: 14:25 - 14:52 UTC
**Incident ID**: terraform-lock-2025-10-09-incident-2
**Status**: RESOLVED (Preventive measures implemented)

## Executive Summary

Multiple deployment workflows triggered simultaneously caused a Terraform state lock conflict. The root cause was the absence of concurrency controls in the deployment workflow, allowing parallel Terraform operations. This has been resolved by adding a concurrency group to ensure only one deployment runs at a time.

## Incident Timeline

| Time (UTC) | Event | Workflow ID |
|------------|-------|-------------|
| 14:25:47 | First deployment triggered (auto from CI) | 18379587131 |
| 14:27:28 | Second deployment triggered | 18379638497 |
| 14:28:20 | Terraform lock created (Lock ID: 1760020100905736) | 18379587131 |
| 14:29:25 | Third deployment triggered | 18379697706 |
| 14:27:28 | Second deployment fails with lock error | 18379638497 |
| 14:29:25 | Third deployment fails with lock error | 18379697706 |
| 14:38:25 | First deployment final job completes (failure) | 18379587131 |
| 14:43:00 | Investigation begins | - |
| 14:46:25 | Force-unlock workflow triggered | 18379942362 |
| 14:47:03 | Second force-unlock workflow triggered (duplicate) | 18379947168 |
| 14:50:00 | Concurrency controls added to deploy.yml | - |
| 14:52:00 | Changes committed and pushed | 5312c3a |

## Lock Details

```
Lock ID: 1760020100905736
Path: gs://[project]-terraform-state/terraform/state/default.tflock
Who: runner@runnervmwhb2z
Created: 2025-10-09 14:28:20 UTC
Operation: OperationTypeApply
```

## Root Cause Analysis

### Primary Cause
The deployment workflow (`deploy.yml`) had no concurrency controls, allowing multiple instances to run simultaneously. When the CI workflow succeeded multiple times in quick succession, it triggered multiple auto-deployments.

### Contributing Factors
1. **No concurrency group**: Deploy.yml lacked a `concurrency` configuration
2. **Multiple CI triggers**: Several commits caused back-to-back CI successes
3. **Workflow state bug**: GitHub Actions showed workflow 18379587131 as "in_progress" even though all jobs completed at 14:38:25
4. **Lock not auto-released**: Terraform state lock persisted despite workflow completion

### Why This Wasn't Caught Earlier
- The previous lock incident (#1) focused on timeout issues, not concurrent runs
- CI workflow was triggering deployments automatically (workflow_run trigger)
- No load testing of rapid successive commits

## Actions Taken

### Immediate Response
1. **Analyzed hung workflow**: Confirmed workflow 18379587131 had all jobs complete
   - Last job "Deploy Full Infrastructure" completed at 14:38:25 UTC
   - Workflow still showed as "in_progress" (GitHub Actions bug)

2. **Attempted to cancel**: GitHub API returned HTTP 500 error
   ```bash
   gh run cancel 18379587131
   # HTTP 500: Failed to cancel workflow run
   ```

3. **Triggered force-unlock**: Used existing force-unlock workflow
   ```bash
   echo '{"ref":"main","inputs":{"lock_id":"1760020100905736"}}' | \
     gh api repos/crystalshards/monorepo/actions/workflows/196422616/dispatches --input -
   ```
   - Workflow 18379942362 queued, waiting for production environment approval
   - Note: A duplicate workflow 18379947168 was also created accidentally

### Preventive Measures

#### 1. Added Concurrency Controls
**File**: `.github/workflows/deploy.yml`

```yaml
concurrency:
  group: terraform-deploy
  cancel-in-progress: false
```

**Impact**:
- Only ONE deployment can run at a time
- Subsequent deployments automatically queue
- No more simultaneous Terraform operations
- Prevents race conditions and lock conflicts

**Rationale for `cancel-in-progress: false`**:
- Deployments should complete, not be cancelled mid-flight
- Terraform state changes should not be interrupted
- Better to queue than to leave infrastructure in unknown state

#### 2. Documentation Updated
- Updated `.agent/STATUS.md` with incident details
- Created this incident report for future reference
- Added to lessons learned section

## Verification

### Before Fix
```bash
# Multiple workflows could run simultaneously
$ gh run list --limit 3
18379697706  Deploy to Production  completed  failure   2025-10-09T14:29:25Z
18379638497  Deploy to Production  completed  failure   2025-10-09T14:27:28Z
18379587131  Deploy to Production  in_progress  N/A     2025-10-09T14:25:47Z
```

### After Fix
```yaml
# In deploy.yml
concurrency:
  group: terraform-deploy
  cancel-in-progress: false
```

Now subsequent deployments will show as "pending" until the current one completes.

## Current Status

### Workflow States (as of 14:52 UTC)
| Workflow ID | Type | Status | Notes |
|-------------|------|--------|-------|
| 18379947168 | Force Unlock | queued | Waiting for approval (duplicate) |
| 18379942362 | Force Unlock | queued | Waiting for approval (primary) |
| 18379697706 | Deploy | failed | Lock conflict |
| 18379638497 | Deploy | failed | Lock conflict |
| 18379587131 | Deploy | in_progress | All jobs complete (GitHub bug) |

### Lock Status
- **Lock ID**: 1760020100905736
- **State**: Likely stale (all jobs in holding workflow completed)
- **Resolution Path**: Force-unlock workflow queued, will release when approved

### Deployment Readiness
- **Changes Committed**: Yes (commit 5312c3a)
- **Preventive Measures**: Implemented
- **Future Deployments**: Will queue properly
- **Can Deploy Now**: Once lock is released (manual approval required for unlock workflow)

## Lessons Learned

### Critical Insights
1. **Always use concurrency groups for Terraform workflows**
   - Prevents simultaneous state operations
   - Essential for any workflow that modifies shared state
   - Should be a standard pattern in all IaC workflows

2. **GitHub Actions workflow state can be misleading**
   - Workflow can show "in_progress" even when all jobs are complete
   - Always check individual job statuses
   - Don't trust workflow status alone

3. **Auto-deployment triggers need careful consideration**
   - `workflow_run` triggers can fire multiple times rapidly
   - Must have concurrency controls to prevent overlapping runs
   - Consider debouncing or rate limiting auto-deployments

4. **Force-unlock requires manual approval**
   - Production environment protection includes unlock workflows
   - Cannot be fully automated without approval
   - Consider emergency unlock procedures

### Recommendations for Future

#### Immediate (Implemented)
- ✅ Add concurrency group to deploy.yml
- ✅ Document incident and resolution

#### Short-term (Next Sprint)
- [ ] Add automatic lock timeout to Terraform backend config
  ```hcl
  backend "gcs" {
    bucket = "..."
    lock_timeout = "5m"  # Auto-release after 5 minutes
  }
  ```
- [ ] Consider adding workflow status check before triggering unlock
- [ ] Add monitoring/alerting for hung workflows

#### Long-term (Future Improvements)
- [ ] Implement deployment queue with retry logic
- [ ] Add pre-deployment lock status check
- [ ] Consider GitOps model (ArgoCD/Flux) to avoid workflow-based deployment
- [ ] Add deployment dashboard showing queue and current status

## Related Incidents

### Incident #1 (2025-10-09 ~07:15 UTC)
- **Issue**: Workflow cancellation didn't release lock
- **Lock ID**: 0f93ad67-67bf-1f4b-af84-c68ae5b2abe9
- **Resolution**: Force-unlock workflow created
- **Preventive**: Added 60-minute timeout

### Incident #2 (This Incident)
- **Issue**: Concurrent deployments caused lock conflict
- **Lock ID**: 1760020100905736
- **Resolution**: Added concurrency controls
- **Preventive**: Only one deployment at a time

## Technical Details

### Workflow Analysis
Workflow 18379587131 job completion times:
```
Deploy Cluster & Artifact Registry: 14:25:51 - 14:26:15 (24s) ✅
Build Images (crystalgigs, api):    14:26:18 - 14:27:45 (87s) ✅
Build Images (crystalshards, api):  14:26:18 - 14:27:53 (95s) ✅
Build Images (crystalbits, api):    14:26:17 - 14:27:43 (86s) ✅
Build Images (crystalshards, worker): 14:26:17 - 14:27:53 (96s) ✅
Build Images (crystaldocs, api):    14:26:17 - 14:27:46 (89s) ✅
Deploy Full Infrastructure:         14:27:55 - 14:38:25 (630s) ❌
```

The "Deploy Full Infrastructure" job held the Terraform lock from 14:28:20 until it failed at 14:38:25 (10 minutes and 5 seconds). During this time, two other deployments were triggered and immediately failed due to the lock.

### Concurrency Configuration Explained
```yaml
concurrency:
  group: terraform-deploy           # Unique identifier for this concurrency group
  cancel-in-progress: false         # Don't cancel running deployments
```

This ensures:
- All workflows in the `terraform-deploy` group share the same queue
- Only one can be "in_progress" at a time
- Others automatically enter "pending" state
- No manual intervention needed for queuing

## Commit Reference

**Commit**: 5312c3a
**Message**: fix(deploy): add concurrency controls to prevent Terraform state lock conflicts

**Files Changed**:
- `.github/workflows/deploy.yml` - Added concurrency group
- `.agent/STATUS.md` - Documented incident #2

## Conclusion

The Terraform state lock conflict was caused by missing concurrency controls allowing simultaneous deployments. This has been resolved by adding a concurrency group to the deployment workflow, ensuring only one deployment can run at a time. Future deployments will automatically queue and execute sequentially, preventing lock conflicts.

The force-unlock workflow has been triggered and is awaiting manual approval to release the stale lock. Once approved, normal deployment operations can resume with the new concurrency protections in place.

**Status**: RESOLVED - Preventive measures implemented, awaiting lock release for full resolution.
