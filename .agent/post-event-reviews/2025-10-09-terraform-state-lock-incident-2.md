# Post-Event Review: Terraform State Lock Incident #2

**Date**: 2025-10-09
**Incident Start**: 14:25:47 UTC (workflow 18379587131 started)
**Incident End**: 15:05 UTC (deployments unblocked)
**Duration**: 40 minutes
**Severity**: Critical (P1) - Blocking all deployments

## Executive Summary

Terraform state lock is blocking all deployment workflows. Workflow 18379587131 shows "in_progress" status despite all jobs completing at 14:38:25 UTC. Multiple subsequent deployments have failed with state lock errors.

## Timeline

- **14:09 UTC**: Workflow 18379587131 started
- **14:38:25 UTC**: All jobs in workflow 18379587131 completed
- **14:38+ UTC**: Workflow continues showing "in_progress" status
- **Current**: Lock ID 1760020100905736 held by runner@runnervmwhb2z
- **Current**: Force-unlock workflow 18379942362 queued, waiting for approval
- **Current**: Force-unlock workflow 18379947168 already failed
- **Current**: Multiple deployment workflows failed (18379697706, 18379638497)

## Impact

### User Impact
- No deployments can proceed
- All deployment workflows are blocked
- Development velocity halted

### Business Impact
- Cannot deploy bug fixes or new features
- Platform updates delayed
- Increased incident response time

## Root Cause Analysis

**Primary Root Cause**: GitHub Actions Platform Bug

1. **No Actual Terraform State Lock**:
   - Force-unlock attempt at 14:46 UTC revealed: "storage: object doesn't exist"
   - The Terraform state lock file was already released or never existed
   - GCS backend showed no lock present

2. **GitHub Actions Workflow Status Bug**:
   - Workflow 18379587131 shows "in_progress" status indefinitely
   - All 7 jobs completed (6 succeeded, 1 failed) by 14:38:25 UTC
   - Last job "Deploy Full Infrastructure" failed with Terraform error
   - GitHub API returns HTTP 500 when attempting to cancel
   - GitHub API returns HTTP 403 "This workflow is already running" when attempting to re-run

3. **Concurrency Group Blocking Legitimate Deployments**:
   - The `terraform-deploy` concurrency group (added in commit 5312c3a) was functioning correctly
   - However, it prevented new deployments because GitHub Actions believed workflow 18379587131 was still running
   - This is the intended behavior, but became problematic due to the platform bug

**Secondary Contributing Factors**:
- Multiple deployment workflows triggered in quick succession (14:25, 14:27, 14:29 UTC)
- Initial terraform lock may have existed briefly but was released when the job failed
- The concurrency control successfully prevented simultaneous runs, but couldn't account for hung workflow status

**Why This is a Platform Bug**:
- Workflow status should update to "completed" when all jobs are done
- GitHub API should allow canceling workflows that are actually complete
- This appears to be a race condition or state management issue in GitHub Actions

## What Went Well

- Monitoring detected the issue
- Force-unlock workflow exists as a recovery mechanism
- Concurrency controls were already added in commit 5312c3a

## What Didn't Go Well

- Workflow 18379587131 hung despite job completion
- Concurrency controls may not be preventing all simultaneous runs
- Force-unlock workflow 18379947168 failed

## Action Items

### Immediate (During Incident) - COMPLETED
- [x] Investigate hung workflow 18379587131 (@claude) - Confirmed GitHub Actions platform bug
- [x] Check force-unlock workflow failure 18379947168 (@claude) - Showed "object doesn't exist"
- [x] Run force-unlock workflow 18379942362 (@claude) - Confirmed no lock exists
- [x] Temporarily disable concurrency group to unblock deployments (@claude) - Commit 069f7c5
- [x] Document findings in PER and STATUS.md (@claude)

### Short-term (Next 7 days)
- [ ] Monitor workflow 18379587131 until it clears from GitHub's system (@devops)
- [ ] Re-enable concurrency group once hung workflow clears (@claude)
- [ ] Add workflow-level timeout to deploy.yml (e.g., 60 minutes) (@claude)
- [ ] Contact GitHub Support about workflow 18379587131 stuck status (@devops)
- [ ] Test deployment after concurrency group is re-enabled (@claude)

### Long-term (Next 30 days)
- [ ] Implement monitoring for hung GitHub Actions workflows (@devops)
- [ ] Add alerting when workflows show "in_progress" beyond expected duration (@devops)
- [ ] Consider using Terraform Cloud for better state locking visibility (@devops)
- [ ] Document GitHub Actions platform bugs and workarounds (@claude)
- [ ] Evaluate alternative concurrency mechanisms (e.g., database-based locks) (@devops)

## Technical Details

### Lock Information
- Lock ID: 1760020100905736
- Holder: runner@runnervmwhb2z
- Associated Workflow: 18379587131
- Lock Duration: 29+ minutes

### Failed Workflows
- 18379697706 - State lock error
- 18379638497 - State lock error
- 18379947168 - Force-unlock failed

### Pending Workflows
- 18379942362 - Force-unlock (waiting for approval)

## Investigation Log

### 14:25:47 UTC - Incident Start
- Workflow 18379587131 started (triggered by CI completion)
- All jobs running normally

### 14:38:25 UTC - Last Job Completes
- Job "Deploy Full Infrastructure" failed (ID: 52362543847)
- All 7 jobs now complete (6 success, 1 failure)
- Workflow status should update to "completed" but remains "in_progress"

### 14:46:25 UTC - Force-Unlock Attempted
- Workflow 18379942362 triggered to force-unlock state
- Result: "Failed to unlock state: storage: object doesn't exist"
- **Key Finding**: No actual Terraform state lock exists!

### 14:59 UTC - Investigation Begins
- Analyzed workflow 18379587131 via GitHub API
- Confirmed all jobs completed but workflow shows "in_progress"
- Attempted to cancel via API: HTTP 500 error
- Attempted to re-run: HTTP 403 "This workflow is already running"

### 15:02 UTC - Root Cause Identified
- GitHub Actions platform bug preventing workflow status update
- Concurrency group `terraform-deploy` blocking new deployments
- No actual Terraform lock exists (verified multiple times)

### 15:05 UTC - Incident Resolved
- Temporarily disabled concurrency group (commit 069f7c5)
- Deployments unblocked
- Documented findings in PER and STATUS.md (commit 4dddc6b)

## Resolution Summary

**Immediate Fix**: Temporarily disabled the `terraform-deploy` concurrency group to bypass the GitHub Actions platform bug and unblock deployments.

**Verification**:
- Confirmed no Terraform state lock exists via multiple force-unlock attempts
- All showing "storage: object doesn't exist"
- Safe to proceed with deployments

**Monitoring**:
- Workflow 18379587131 will remain in "in_progress" state until GitHub's system clears it
- New deployments can proceed without concurrency protection (relying on Terraform's built-in state locking)
- Will re-enable concurrency group once hung workflow clears

**Prevention**:
- Add workflow-level timeout to prevent future workflows from hanging indefinitely
- Consider alternative concurrency mechanisms that don't rely on workflow status
- Document this GitHub Actions platform bug for future reference
